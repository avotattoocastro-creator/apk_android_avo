#include "avo_ble_auth.h"
#include "avo_bytes.h"
#include "avo_crc.h"
#include "avo_sha256.h"
#include <string.h>

namespace avo {

static const uint32_t STORE_MAGIC = 0x4B455941;  // "AYEK"

size_t auth_store_serialize(const AuthStore& s, uint8_t* out, size_t cap) {
  ByteWriter w(out, cap);
  w.u32(STORE_MAGIC); w.u8(s.count); w.u8(0); w.u16(0);
  for (uint8_t i = 0; i < s.count && i < AUTH_MAX_KEYS; i++) {
    w.bytes(s.keys[i].id, 8); w.bytes(s.keys[i].key, 32); w.u32(s.keys[i].seq); w.str(s.keys[i].name, 24);
  }
  if (!w.ok()) return 0;
  uint32_t c = crc32(out, w.size());
  w.u32(c);
  return w.ok() ? w.size() : 0;
}

bool auth_store_deserialize(const uint8_t* p, size_t n, AuthStore* s) {
  *s = AuthStore();
  if (n < 12) return false;
  if (crc32(p, n - 4) != get_u32(p + n - 4)) return false;
  ByteReader r(p, n - 4);
  if (r.u32() != STORE_MAGIC) return false;
  uint8_t cnt = r.u8(); r.u8(); r.u16();
  if (cnt > AUTH_MAX_KEYS) return false;
  for (uint8_t i = 0; i < cnt; i++) {
    r.bytes(s->keys[i].id, 8); r.bytes(s->keys[i].key, 32); s->keys[i].seq = r.u32(); r.str(s->keys[i].name, 24);
  }
  if (!r.ok()) { *s = AuthStore(); return false; }
  s->count = cnt;
  return true;
}

static void proof(const char* tag, const uint8_t key[32], const uint8_t a[16], const uint8_t b[16], const char* dev, uint8_t out[32]) {
  uint8_t m[4 + 16 + 16 + 12];
  memcpy(m, tag, 4);
  memcpy(m + 4, a, 16);
  memcpy(m + 20, b, 16);
  memset(m + 36, 0, 12);
  size_t dl = strnlen(dev, 12);
  memcpy(m + 36, dev, dl);
  hmac_sha256(key, 32, m, sizeof(m), out);
}

void auth_watch_proof(const uint8_t key[32], const uint8_t pn[16], const uint8_t wn[16], const char* dev, uint8_t out[32]) {
  proof("AVOW", key, pn, wn, dev, out);
}
void auth_phone_proof(const uint8_t key[32], const uint8_t wn[16], const uint8_t pn[16], const char* dev, uint8_t out[32]) {
  proof("AVOP", key, wn, pn, dev, out);
}

void AuthManager::init(const AuthStore& stored, const char* dev_id, RandomFn rnd, SaveFn save) {
  store_ = stored;
  strncpy(dev_id_, dev_id ? dev_id : "", 12);
  dev_id_[12] = 0;
  rnd_ = rnd;
  save_ = save;
  next_seq_ = 1;
  for (uint8_t i = 0; i < store_.count; i++) if (store_.keys[i].seq >= next_seq_) next_seq_ = store_.keys[i].seq + 1;
  on_disconnect();
}

void AuthManager::on_connect(uint16_t) {
  on_disconnect();
  connected_ = true;
}

void AuthManager::on_disconnect() {
  connected_ = false;
  authorized_ = false;
  cur_key_ = -1;
  have_hello_ = false;
  fails_ = 0;
  claim_open_ = claim_confirmed_ = claim_delivered_ = false;
  memset(&claim_key_, 0, sizeof(claim_key_));
}

int AuthManager::find(const uint8_t id[8]) const {
  for (uint8_t i = 0; i < store_.count; i++) if (memcmp(store_.keys[i].id, id, 8) == 0) return i;
  return -1;
}

bool AuthManager::hello(const uint8_t key_id[8], const uint8_t pn[16], uint8_t wn_out[16], uint8_t wp_out[32]) {
  if (!connected_) return false;
  int k = find(key_id);
  if (k < 0) return false;
  cur_key_ = k;
  memcpy(pn_, pn, 16);
  rnd_(wn_, 16);
  memcpy(wn_out, wn_, 16);
  auth_watch_proof(store_.keys[k].key, pn_, wn_, dev_id_, wp_out);
  have_hello_ = true;
  authorized_ = false;
  return true;
}

AuthManager::ProofResult AuthManager::proof(const uint8_t pp[32]) {
  if (fails_ >= AUTH_MAX_FAILS) return PROOF_LOCKED;
  if (!have_hello_ || cur_key_ < 0) return PROOF_NO_HELLO;
  uint8_t want[32];
  auth_phone_proof(store_.keys[cur_key_].key, wn_, pn_, dev_id_, want);
  have_hello_ = false;  // nonces are single use
  if (!ct_equal(want, pp, 32)) { fails_++; return PROOF_BAD; }
  authorized_ = true;
  return PROOF_OK;
}

bool AuthManager::claim_begin(uint32_t now, const char* name) {
  if (!connected_) return false;
  claim_open_ = true;
  claim_confirmed_ = false;
  claim_delivered_ = false;
  claim_t0_ = now;
  memset(claim_name_, 0, sizeof(claim_name_));
  if (name) strncpy(claim_name_, name, sizeof(claim_name_) - 1);
  return true;
}

bool AuthManager::claim_pending(uint32_t now) const {
  return claim_open_ && !claim_confirmed_ && now - claim_t0_ < AUTH_CLAIM_WINDOW_MS;
}

bool AuthManager::claim_confirm(uint32_t now) {
  if (!claim_pending(now)) return false;
  rnd_(claim_key_.id, 8);
  rnd_(claim_key_.key, 32);
  claim_key_.seq = next_seq_++;
  memcpy(claim_key_.name, claim_name_, sizeof(claim_key_.name));
  claim_key_.name[sizeof(claim_key_.name) - 1] = 0;
  claim_confirmed_ = true;
  return true;
}

AuthManager::ClaimResult AuthManager::claim_result(uint32_t now, uint8_t id_out[8], uint8_t key_out[32]) {
  if (!claim_open_) return CLAIM_NONE;
  if (!claim_confirmed_) return now - claim_t0_ < AUTH_CLAIM_WINDOW_MS ? CLAIM_PENDING : CLAIM_EXPIRED;
  if (claim_delivered_) return CLAIM_NONE;
  AuthStore next = store_;
  int slot;
  if (next.count < AUTH_MAX_KEYS) slot = next.count++;
  else {  // full: replace the oldest key
    slot = 0;
    for (uint8_t i = 1; i < next.count; i++) if (next.keys[i].seq < next.keys[slot].seq) slot = i;
  }
  next.keys[slot] = claim_key_;
  if (save_ && !save_(next)) return CLAIM_SAVE_FAILED;
  store_ = next;
  memcpy(id_out, claim_key_.id, 8);
  memcpy(key_out, claim_key_.key, 32);
  claim_delivered_ = true;
  claim_open_ = false;
  authorized_ = true;
  cur_key_ = slot;
  return CLAIM_DONE;
}

bool AuthManager::revoke(const uint8_t id[8]) {
  if (!authorized_) return false;
  static const uint8_t ALL[8] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
  AuthStore next;
  if (memcmp(id, ALL, 8) == 0) {
    if (cur_key_ >= 0) { next.keys[0] = store_.keys[cur_key_]; next.count = 1; }
  } else {
    int k = find(id);
    if (k < 0) return false;
    for (uint8_t i = 0; i < store_.count; i++) if ((int)i != k) next.keys[next.count++] = store_.keys[i];
  }
  if (save_ && !save_(next)) return false;
  // keep the current key index valid
  int cur = -1;
  if (cur_key_ >= 0) {
    for (uint8_t i = 0; i < next.count; i++) if (memcmp(next.keys[i].id, store_.keys[cur_key_].id, 8) == 0) cur = i;
  }
  store_ = next;
  cur_key_ = cur;
  if (cur < 0) authorized_ = false;  // the phone revoked itself
  return true;
}

}  // namespace avo
