// AVO PPK — gzip (RFC 1952) / DEFLATE (RFC 1951) decoder, own implementation without external libraries.
// 27/11/2026: the iPad decoded the IGN bases with Apple's Compression framework, which can consume all its input
// without reporting the end of the stream ("gzip cortado" with complete files). The engine decodes them instead, the
// same on iPad, Android and Windows. Several members in a row are concatenated (gzip of concatenated files). Every
// member is checked with its CRC-32 and ISIZE: a truncated or damaged download is an error, never partial data.
#include "avo_eq/ppk.h"

#include <cstring>

namespace avoeq {
namespace {

struct Bits {
  const uint8_t* p;
  size_t n, pos = 0;
  uint32_t buf = 0;
  int cnt = 0;
  bool over = false;
  Bits(const uint8_t* d, size_t len, size_t start) : p(d), n(len), pos(start) {}
  int need(int k) {
    while (cnt < k) {
      if (pos >= n) { over = true; return 0; }
      buf |= (uint32_t)p[pos++] << cnt;
      cnt += 8;
    }
    return 1;
  }
  uint32_t get(int k) {
    if (k == 0) return 0;
    if (!need(k)) return 0;
    uint32_t v = buf & ((1u << k) - 1);
    buf >>= k;
    cnt -= k;
    return v;
  }
  void align() { buf = 0; cnt = 0; }   // whole bytes only remain in p (cnt is always < 8 after a symbol)
};

struct Huff {
  uint16_t count[16];
  uint16_t sym[320];
};

static bool build(Huff* h, const uint8_t* len, int n) {
  std::memset(h->count, 0, sizeof(h->count));
  for (int i = 0; i < n; i++) h->count[len[i]]++;
  h->count[0] = 0;
  int left = 1;
  for (int l = 1; l < 16; l++) {
    left <<= 1;
    left -= h->count[l];
    if (left < 0) return false;   // over-subscribed
  }
  uint16_t offs[16];
  offs[1] = 0;
  for (int l = 1; l < 15; l++) offs[l + 1] = (uint16_t)(offs[l] + h->count[l]);
  for (int i = 0; i < n; i++)
    if (len[i]) h->sym[offs[len[i]]++] = (uint16_t)i;
  return true;
}

static int decode(Bits& b, const Huff& h) {
  int code = 0, first = 0, index = 0;
  for (int l = 1; l < 16; l++) {
    code |= (int)b.get(1);
    if (b.over) return -1;
    int c = h.count[l];
    if (code - c < first) return h.sym[index + (code - first)];
    index += c;
    first += c;
    first <<= 1;
    code <<= 1;
  }
  return -1;
}

static const uint16_t kLenBase[29] = {3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115,
                                      131, 163, 195, 227, 258};
static const uint8_t kLenExtra[29] = {0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0};
static const uint16_t kDistBase[30] = {1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025,
                                       1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577};
static const uint8_t kDistExtra[30] = {0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13};

static bool codes(Bits& b, std::vector<uint8_t>* out, size_t start, const Huff& lc, const Huff& dc) {
  for (;;) {
    int s = decode(b, lc);
    if (s < 0) return false;
    if (s < 256) { out->push_back((uint8_t)s); continue; }
    if (s == 256) return true;
    s -= 257;
    if (s >= 29) return false;
    size_t len = kLenBase[s] + b.get(kLenExtra[s]);
    int d = decode(b, dc);
    if (d < 0 || d >= 30) return false;
    size_t dist = kDistBase[d] + b.get(kDistExtra[d]);
    if (b.over || dist > out->size() - start) return false;
    size_t from = out->size() - dist;
    for (size_t i = 0; i < len; i++) out->push_back((*out)[from + i]);
  }
}

// One raw DEFLATE stream from byte `pos`; on success *end is the byte after it.
static bool inflate_raw(const uint8_t* d, size_t n, size_t pos, std::vector<uint8_t>* out, size_t* end) {
  Bits b(d, n, pos);
  const size_t start = out->size();
  int last = 0;
  do {
    last = (int)b.get(1);
    int type = (int)b.get(2);
    if (b.over) return false;
    if (type == 0) {
      b.align();
      if (b.pos + 4 > n) return false;
      uint16_t len = (uint16_t)(d[b.pos] | d[b.pos + 1] << 8), nlen = (uint16_t)(d[b.pos + 2] | d[b.pos + 3] << 8);
      if ((uint16_t)~nlen != len) return false;
      b.pos += 4;
      if (b.pos + len > n) return false;
      out->insert(out->end(), d + b.pos, d + b.pos + len);
      b.pos += len;
    } else if (type == 1) {
      static Huff fl, fd;
      static bool ready = false;
      if (!ready) {
        uint8_t l[288];
        int i = 0;
        for (; i < 144; i++) l[i] = 8;
        for (; i < 256; i++) l[i] = 9;
        for (; i < 280; i++) l[i] = 7;
        for (; i < 288; i++) l[i] = 8;
        build(&fl, l, 288);
        uint8_t dl[30];
        for (i = 0; i < 30; i++) dl[i] = 5;
        build(&fd, dl, 30);
        ready = true;
      }
      if (!codes(b, out, start, fl, fd)) return false;
    } else if (type == 2) {
      int nlen = (int)b.get(5) + 257, ndist = (int)b.get(5) + 1, ncode = (int)b.get(4) + 4;
      if (b.over || nlen > 286 || ndist > 30) return false;
      static const uint8_t order[19] = {16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15};
      uint8_t cl[19] = {0};
      for (int i = 0; i < ncode; i++) cl[order[i]] = (uint8_t)b.get(3);
      Huff ch;
      if (b.over || !build(&ch, cl, 19)) return false;
      uint8_t lens[320] = {0};
      int i = 0;
      while (i < nlen + ndist) {
        int s = decode(b, ch);
        if (s < 0) return false;
        if (s < 16) { lens[i++] = (uint8_t)s; continue; }
        int rep = 0;
        uint8_t v = 0;
        if (s == 16) { if (i == 0) return false; v = lens[i - 1]; rep = 3 + (int)b.get(2); }
        else if (s == 17) rep = 3 + (int)b.get(3);
        else rep = 11 + (int)b.get(7);
        if (b.over || i + rep > nlen + ndist) return false;
        while (rep--) lens[i++] = v;
      }
      if (lens[256] == 0) return false;
      Huff lc, dc;
      if (!build(&lc, lens, nlen) || !build(&dc, lens + nlen, ndist)) return false;
      if (!codes(b, out, start, lc, dc)) return false;
    } else {
      return false;
    }
  } while (!last);
  *end = b.pos;   // the bits left in the last byte are padding
  return true;
}

}  // namespace

uint32_t ppk_crc32(const uint8_t* d, size_t n, uint32_t crc) {
  static uint32_t t[256];
  static bool ready = false;
  if (!ready) {
    for (uint32_t i = 0; i < 256; i++) {
      uint32_t c = i;
      for (int k = 0; k < 8; k++) c = (c & 1) ? 0xEDB88320u ^ (c >> 1) : c >> 1;
      t[i] = c;
    }
    ready = true;
  }
  crc = ~crc;
  for (size_t i = 0; i < n; i++) crc = t[(crc ^ d[i]) & 0xFF] ^ (crc >> 8);
  return ~crc;
}

bool ppk_gunzip(const uint8_t* d, size_t n, std::vector<uint8_t>* out, std::string* error) {
  auto fail = [&](const char* m) { if (error) *error = m; return false; };
  out->clear();
  size_t pos = 0;
  int members = 0;
  while (pos + 18 <= n) {
    if (d[pos] != 0x1F || d[pos + 1] != 0x8B || d[pos + 2] != 8) {
      if (members == 0) return fail("el fichero no es gzip");
      break;   // trailing garbage after the last member (as gzip -d accepts)
    }
    const uint8_t flg = d[pos + 3];
    size_t p = pos + 10;
    if (flg & 0x04) { if (p + 2 > n) return fail("gzip cortado"); p += 2 + (size_t)(d[p] | d[p + 1] << 8); }
    if (flg & 0x08) { while (p < n && d[p]) p++; p++; }
    if (flg & 0x10) { while (p < n && d[p]) p++; p++; }
    if (flg & 0x02) p += 2;
    if (p >= n) return fail("gzip cortado");
    const size_t start = out->size();
    size_t end = 0;
    if (!inflate_raw(d, n, p, out, &end)) return fail("gzip cortado o dañado");
    if (end + 8 > n) return fail("gzip cortado");
    const uint32_t crc = (uint32_t)d[end] | (uint32_t)d[end + 1] << 8 | (uint32_t)d[end + 2] << 16 | (uint32_t)d[end + 3] << 24;
    const uint32_t isz = (uint32_t)d[end + 4] | (uint32_t)d[end + 5] << 8 | (uint32_t)d[end + 6] << 16 | (uint32_t)d[end + 7] << 24;
    const size_t got = out->size() - start;
    if (isz != (uint32_t)got || crc != ppk_crc32(out->data() + start, got, 0)) return fail("gzip dañado (CRC)");
    pos = end + 8;
    members++;
  }
  if (members == 0) return fail(n < 18 ? "gzip cortado" : "el fichero no es gzip");
  return true;
}

}  // namespace avoeq
