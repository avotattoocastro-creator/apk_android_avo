// AVO CHEST V3.7.5-usb1 — training download to the PC over the USB cable (protocol AVO1).
//
// Design (docs: firmware/chest/V3_7_5_USB/PROTOCOLO_USB.md):
//  * Runs inside the Arduino loop task, which was idle (app_loop only slept): no new task, no extra internal RAM.
//    Buffers (line in, answer out, file chunk) are allocated once in PSRAM.
//  * Text protocol on the existing USB serial port. Commands "AVO1 ...\n"; every answer is a single line
//    "#AVO1 ...\n" written with ONE write() call, so a log line printed by another task can come before or after it
//    but never inside it (HWCDC::write holds its TX lock for the whole buffer). The PC ignores any other line.
//  * Read-only. Sessions in OPEN state (recording or interrupted without recovery) are never served, and nothing
//    is served while a recording runs. Paths are built only from validated identifiers (no arbitrary SD access).
//  * Same session listing, etag and SHA-256 (concatenated segments) as the Wi-Fi download of 3.7.4, so the PC and
//    the phone describe a training the same way.
//  * Integrity: every DATA line carries its offset, length and CRC-32; the PC checks the SHA-256 of the whole
//    training against the watch before it keeps the file.
#include "usb_sync.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <dirent.h>

#include "avo_raw.h"
#include "avo_crc.h"
#include "avo_sha256.h"

#ifndef AVO_SD_MOUNT
#define AVO_SD_MOUNT "/sdcard"
#endif

using namespace avo;

namespace usbsync {

static const size_t LINE_IN = 160;
static const size_t OUT_CAP = 6144;             // >= "#AVO1 DATA ..." header + base64(MAX_READ) + "\n"
static const uint16_t MAX_SEGS = 64;

static const char* s_root = AVO_SD_MOUNT "/AVO";   // pointer only: no internal RAM for the path
static char* s_in = nullptr;
static size_t s_in_n = 0;
static bool s_in_overflow = false;
static char* s_out = nullptr;
static uint8_t* s_chunk = nullptr;
static Stats s_stats = {};

struct ShaCache { char id[24]; uint64_t total; uint32_t etag; uint8_t h[32]; bool valid; };
static const int SHA_SLOTS = 4;
static ShaCache* s_sha = nullptr;   // PSRAM (static internal RAM is what the watch lacks)
static int s_sha_slot = 0;

void set_root(const char* root) { s_root = root; }   // test hook: the caller keeps the string alive

void stats(Stats* out) { *out = s_stats; }

bool init() {
  if (!s_in) s_in = (char*)port::alloc(LINE_IN);
  if (!s_out) s_out = (char*)port::alloc(OUT_CAP);
  if (!s_chunk) s_chunk = (uint8_t*)port::alloc(MAX_READ);
  if (!s_sha) {
    s_sha = (ShaCache*)port::alloc(SHA_SLOTS * sizeof(ShaCache));
    if (s_sha) memset(s_sha, 0, SHA_SLOTS * sizeof(ShaCache));
  }
  s_in_n = 0;
  s_in_overflow = false;
  return s_in && s_out && s_chunk && s_sha;
}

// ------------------------------------------------------------------ helpers
static void send_line(size_t n) {
  if (n >= OUT_CAP - 1) n = OUT_CAP - 2;
  s_out[n++] = '\n';
  port::write(s_out, n);
  s_stats.bytes_sent += (uint32_t)n;
}

static void send_fmt(const char* fmt, const char* a, const char* b) {
  int n = snprintf(s_out, OUT_CAP, fmt, a, b);
  if (n > 0) send_line((size_t)n);
}

static void send_err(const char* cmd, const char* code) {
  s_stats.errors++;
  send_fmt("#AVO1 ERR %s %s", cmd, code);
}

static void hex(const uint8_t* b, size_t n, char* out) {
  static const char* H = "0123456789abcdef";
  for (size_t i = 0; i < n; i++) { out[2 * i] = H[b[i] >> 4]; out[2 * i + 1] = H[b[i] & 15]; }
  out[2 * n] = 0;
}

static size_t base64(const uint8_t* in, size_t n, char* out) {
  static const char* A = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  size_t o = 0, i = 0;
  for (; i + 2 < n; i += 3) {
    uint32_t v = ((uint32_t)in[i] << 16) | ((uint32_t)in[i + 1] << 8) | in[i + 2];
    out[o++] = A[(v >> 18) & 63]; out[o++] = A[(v >> 12) & 63]; out[o++] = A[(v >> 6) & 63]; out[o++] = A[v & 63];
  }
  if (i < n) {
    uint32_t v = (uint32_t)in[i] << 16;
    if (i + 1 < n) v |= (uint32_t)in[i + 1] << 8;
    out[o++] = A[(v >> 18) & 63]; out[o++] = A[(v >> 12) & 63];
    out[o++] = i + 1 < n ? A[(v >> 6) & 63] : '=';
    out[o++] = '=';
  }
  return o;
}

// Session identifier as written by the watch ("S" + letters/digits/_/-), no separators or "..".
static bool valid_id(const char* id) {
  size_t n = strlen(id);
  if (n < 2 || n > 23 || id[0] != 'S') return false;
  for (size_t i = 0; i < n; i++) {
    char c = id[i];
    if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' || c == '-')) return false;
  }
  return true;
}

struct SessionInfo {
  SessionMetaFile m;
  bool meta_ok;
  uint16_t segs;
  uint32_t sizes[MAX_SEGS];
  uint64_t total;
  uint32_t etag;
};
static SessionInfo* s_si = nullptr;   // PSRAM (sizeof ~ 400 B), allocated on first use

static void seg_path(const char* id, uint16_t seg, char* out, size_t cap) {
  snprintf(out, cap, "%s/%s/P%03u.avr", s_root, id, (unsigned)seg);
}

// Meta + real segment sizes; etag computed exactly like wifi_sync.cpp (3.7.4) so both transports agree.
static bool session_info(const char* id, SessionInfo* si) {
  char dir[160];
  snprintf(dir, sizeof(dir), "%s/%s", s_root, id);
  struct stat st;
  if (stat(dir, &st) != 0) return false;
  si->meta_ok = session_meta_read(dir, &si->m);
  si->segs = 0; si->total = 0;
  uint32_t h = 2166136261u;
  for (uint16_t s = 1; s <= MAX_SEGS; s++) {
    char p[192];
    seg_path(id, s, p, sizeof(p));
    if (stat(p, &st) != 0) break;
    si->sizes[si->segs++] = (uint32_t)st.st_size;
    si->total += (uint64_t)st.st_size;
    h = (h ^ (uint32_t)st.st_size) * 16777619u;
    h = (h ^ s) * 16777619u;
  }
  if (si->meta_ok) { h = (h ^ (uint32_t)si->m.start_rtc_ms) * 16777619u; h = (h ^ (uint32_t)si->m.state) * 16777619u; }
  si->etag = h;
  return true;
}

static bool servable(const SessionInfo& si) {
  return si.meta_ok && si.m.state != SessionFileState::OPEN && si.segs > 0;
}

static SessionInfo* info() {
  if (!s_si) s_si = (SessionInfo*)port::alloc(sizeof(SessionInfo));
  return s_si;
}

// ------------------------------------------------------------------ commands
static void cmd_hello() {
  s_stats.hellos++;
  int pct = -1; bool vbus = false, sd = false;
  port::power(&pct, &vbus, &sd);
  int n = snprintf(s_out, OUT_CAP,
                   "#AVO1 HELLO {\"api\":%u,\"name\":\"AVO-CHEST\",\"fw\":\"%s\",\"device\":\"%s\",\"recording\":%s,"
                   "\"sd\":%s,\"battery_pct\":%d,\"vbus\":%s,\"raw_format\":%u,\"max_read\":%u}",
                   (unsigned)API, port::fw_version(), port::device_id(), port::recording() ? "true" : "false",
                   sd ? "true" : "false", pct, vbus ? "true" : "false", (unsigned)RAW_FORMAT_VERSION, (unsigned)MAX_READ);
  send_line((size_t)n);
}

static void cmd_list() {
  if (port::recording()) { send_err("LIST", "recording"); return; }
  SessionInfo* si = info();
  if (!si) { send_err("LIST", "mem"); return; }
  DIR* d = opendir(s_root);
  if (!d) { send_err("LIST", "sd"); return; }
  unsigned count = 0;
  struct dirent* e;
  while ((e = readdir(d)) != nullptr) {
    if (!valid_id(e->d_name) || !session_info(e->d_name, si)) continue;
    int n = snprintf(s_out, OUT_CAP,
                     "#AVO1 T {\"id\":\"%s\",\"state\":%u,\"ready\":%s,\"segments\":%u,\"size\":%llu,\"start_rtc_ms\":%llu,"
                     "\"active_ms\":%u,\"etag\":\"%08x\",\"sizes\":[",
                     e->d_name, si->meta_ok ? (unsigned)si->m.state : 0, servable(*si) ? "true" : "false", (unsigned)si->segs,
                     (unsigned long long)si->total, (unsigned long long)(si->meta_ok ? si->m.start_rtc_ms : 0),
                     (unsigned)(si->meta_ok ? si->m.active_ms : 0), (unsigned)si->etag);
    for (uint16_t i = 0; i < si->segs && n < (int)OUT_CAP - 32; i++)
      n += snprintf(s_out + n, OUT_CAP - n, "%s%u", i ? "," : "", (unsigned)si->sizes[i]);
    n += snprintf(s_out + n, OUT_CAP - n, "]}");
    send_line((size_t)n);
    count++;
    port::yield();
  }
  closedir(d);
  int n = snprintf(s_out, OUT_CAP, "#AVO1 END %u", count);
  send_line((size_t)n);
}

static void cmd_sha(const char* id) {
  if (port::recording()) { send_err("SHA", "recording"); return; }
  if (!valid_id(id)) { send_err("SHA", "id"); return; }
  SessionInfo* si = info();
  if (!si) { send_err("SHA", "mem"); return; }
  if (!session_info(id, si)) { send_err("SHA", "id"); return; }
  if (!servable(*si)) { send_err("SHA", "open"); return; }
  uint8_t h[32];
  bool cached = false;
  for (int i = 0; i < SHA_SLOTS; i++) {
    const ShaCache& c = s_sha[i];
    if (c.valid && !strcmp(c.id, id) && c.total == si->total && c.etag == si->etag) { memcpy(h, c.h, 32); cached = true; }
  }
  if (!cached) {
    Sha256 ctx;
    ctx.init();
    for (uint16_t s = 1; s <= si->segs; s++) {
      char p[192];
      seg_path(id, s, p, sizeof(p));
      FILE* f = fopen(p, "rb");
      if (!f) { send_err("SHA", "io"); return; }
      size_t n;
      while ((n = fread(s_chunk, 1, MAX_READ, f)) > 0) {
        ctx.update(s_chunk, n);
        port::yield();
        if (port::recording()) { fclose(f); send_err("SHA", "recording"); return; }
      }
      fclose(f);
    }
    ctx.final(h);
    ShaCache& c = s_sha[s_sha_slot++ % SHA_SLOTS];
    snprintf(c.id, sizeof(c.id), "%s", id);
    c.total = si->total; c.etag = si->etag; memcpy(c.h, h, 32); c.valid = true;
  }
  char hs[65];
  hex(h, 32, hs);
  int n = snprintf(s_out, OUT_CAP, "#AVO1 SHA {\"id\":\"%s\",\"sha256\":\"%s\",\"size\":%llu,\"etag\":\"%08x\"}",
                   id, hs, (unsigned long long)si->total, (unsigned)si->etag);
  send_line((size_t)n);
}

// READ <id> <seg> <offset> <len> <etag>  →  #AVO1 DATA <seg> <offset> <n> <crc32> <base64>
static void cmd_read(const char* id, unsigned seg, unsigned long off, unsigned long len, const char* etag) {
  if (port::recording()) { send_err("READ", "recording"); return; }
  if (!valid_id(id)) { send_err("READ", "id"); return; }
  SessionInfo* si = info();
  if (!si) { send_err("READ", "mem"); return; }
  if (!session_info(id, si)) { send_err("READ", "id"); return; }
  if (!servable(*si)) { send_err("READ", "open"); return; }
  if (seg < 1 || seg > si->segs) { send_err("READ", "segment"); return; }
  char cur[12];
  snprintf(cur, sizeof(cur), "%08x", (unsigned)si->etag);
  if (strcmp(etag, cur) != 0) { send_err("READ", "changed"); return; }
  uint32_t size = si->sizes[seg - 1];
  if (off >= size || len == 0) { send_err("READ", "range"); return; }
  if (len > MAX_READ) len = MAX_READ;
  if (len > size - off) len = size - off;
  char p[192];
  seg_path(id, (uint16_t)seg, p, sizeof(p));
  FILE* f = fopen(p, "rb");
  if (!f) { send_err("READ", "io"); return; }
  size_t got = 0;
  if (fseek(f, (long)off, SEEK_SET) == 0) got = fread(s_chunk, 1, len, f);
  fclose(f);
  if (got != len) { send_err("READ", "io"); return; }
  int n = snprintf(s_out, OUT_CAP, "#AVO1 DATA %u %lu %lu %08x ", seg, off, (unsigned long)got, (unsigned)crc32(s_chunk, got));
  n += (int)base64(s_chunk, got, s_out + n);
  send_line((size_t)n);
}

// Splits "AVO1 CMD a b c d e" in place. Returns the number of tokens.
static int split(char* s, char** tok, int max) {
  int k = 0;
  while (*s && k < max) {
    while (*s == ' ') s++;
    if (!*s) break;
    tok[k++] = s;
    while (*s && *s != ' ') s++;
    if (*s) *s++ = 0;
  }
  return k;
}

static bool parse_ul(const char* s, unsigned long* out) {
  if (!s || !*s) return false;
  char* end = nullptr;
  *out = strtoul(s, &end, 10);
  return end && *end == 0;
}

static void handle(char* line) {
  char* t[8];
  int k = split(line, t, 8);
  if (k < 2 || strcmp(t[0], "AVO1") != 0) return;   // not for us: ignore silently
  s_stats.commands++;
  const char* c = t[1];
  if (!strcmp(c, "HELLO") && k == 2) cmd_hello();
  else if (!strcmp(c, "LIST") && k == 2) cmd_list();
  else if (!strcmp(c, "SHA") && k == 3) cmd_sha(t[2]);
  else if (!strcmp(c, "READ") && k == 7) {
    unsigned long seg, off, len;
    if (!parse_ul(t[3], &seg) || !parse_ul(t[4], &off) || !parse_ul(t[5], &len) || seg > MAX_SEGS) send_err("READ", "cmd");
    else cmd_read(t[2], (unsigned)seg, off, len, t[6]);
  } else send_err(c, "cmd");
}

void poll() {
  if (!s_in && !init()) return;
  for (int budget = 0; budget < 512; budget++) {
    int b = port::read_byte();
    if (b < 0) return;
    if (b == '\r') continue;
    if (b == '\n') {
      if (!s_in_overflow && s_in_n > 0) { s_in[s_in_n] = 0; handle(s_in); }
      s_in_n = 0;
      s_in_overflow = false;
      continue;
    }
    if (s_in_n < LINE_IN - 1) s_in[s_in_n++] = (char)b;
    else s_in_overflow = true;   // too long: dropped up to the next newline
  }
}

}  // namespace usbsync

// ------------------------------------------------------------------ watch platform layer
#ifndef AVO_HOST_TEST
#include <Arduino.h>
#include <esp_heap_caps.h>
#include "app_state.h"
#include "services.h"
#include "sys_util.h"
#include "avo_version.h"

namespace usbsync {
namespace port {

int read_byte() { return Serial.available() > 0 ? Serial.read() : -1; }

void write(const char* data, size_t n) { Serial.write((const uint8_t*)data, n); }

bool recording() {
  AppSnapshot* s = new AppSnapshot();   // PSRAM (extmem >= 1 KB, 3.7.5)
  appstate::get(s);
  bool rec = s->storage.rec == RecStatus::RECORDING;
  delete s;
  return rec || storage::session_active();
}

void power(int* pct, bool* vbus, bool* sd) {
  AppSnapshot* s = new AppSnapshot();
  appstate::get(s);
  *pct = s->power.pmu.batt_pct; *vbus = s->power.pmu.vbus; *sd = s->storage.mounted;
  delete s;
}

const char* fw_version() { return AVO_FW_VERSION; }
const char* device_id() { return sys::device_id_hex(); }
void* alloc(size_t n) { return heap_caps_malloc(n, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT); }
void yield() { vTaskDelay(1); }

}  // namespace port
}  // namespace usbsync
#endif
