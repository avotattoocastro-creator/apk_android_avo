// BLE application-level authorization (AVO BLE PROTOCOL v1, V3.4.4 extension).
//
// Why: the four-band display cannot show a passkey, so BLE pairing is "Just
// Works" (LE Secure Connections, encrypted, bonded, no PIN). Authorization of
// a phone is done here, on top of the encrypted link:
//   * CLAIM: the phone asks; the watch opens a 60 s window; the user presses
//     BOOT on the watch (physical possession); the watch generates a random
//     32-byte key, stores it (max 4 phones) and gives it to the phone once.
//   * Every connection: mutual challenge-response with HMAC-SHA256:
//       watch_proof = HMAC(K, "AVOW" | pn | wn | dev_id)
//       phone_proof = HMAC(K, "AVOP" | wn | pn | dev_id)
//     pn/wn = 16-byte nonces of phone/watch, dev_id = 12 ASCII hex chars.
// Portable (no Arduino/FreeRTOS): storage and randomness are injected.
#pragma once
#include <stdint.h>
#include <stddef.h>

namespace avo {

static const uint8_t AUTH_MAX_KEYS = 4;
static const uint32_t AUTH_CLAIM_WINDOW_MS = 60000;
static const uint8_t AUTH_MAX_FAILS = 5;

struct AuthKey {
  uint8_t id[8];
  uint8_t key[32];
  uint32_t seq;         // creation order (oldest replaced when full)
  char name[24];
};

struct AuthStore {
  uint8_t count = 0;
  AuthKey keys[AUTH_MAX_KEYS];
};
size_t auth_store_serialize(const AuthStore& s, uint8_t* out, size_t cap);
bool auth_store_deserialize(const uint8_t* p, size_t n, AuthStore* s);
static const size_t AUTH_STORE_MAX = 8 + AUTH_MAX_KEYS * 68 + 4;

void auth_watch_proof(const uint8_t key[32], const uint8_t pn[16], const uint8_t wn[16], const char* dev_id, uint8_t out[32]);
void auth_phone_proof(const uint8_t key[32], const uint8_t wn[16], const uint8_t pn[16], const char* dev_id, uint8_t out[32]);

class AuthManager {
 public:
  typedef void (*RandomFn)(uint8_t* out, size_t n);
  typedef bool (*SaveFn)(const AuthStore& s);
  void init(const AuthStore& stored, const char* dev_id, RandomFn rnd, SaveFn save);

  // Connection lifecycle (any previous session state is dropped).
  void on_connect(uint16_t conn);
  void on_disconnect();

  // AUTH_HELLO: false => unknown key id (phone must CLAIM).
  bool hello(const uint8_t key_id[8], const uint8_t pn[16], uint8_t wn_out[16], uint8_t watch_proof_out[32]);
  // AUTH_PROOF: true => this connection is authorized.
  enum ProofResult { PROOF_OK, PROOF_BAD, PROOF_NO_HELLO, PROOF_LOCKED };
  ProofResult proof(const uint8_t phone_proof[32]);

  // CLAIM
  bool claim_begin(uint32_t now_ms, const char* phone_name);  // false: not connected
  bool claim_pending(uint32_t now_ms) const;
  bool claim_confirm(uint32_t now_ms);                        // BOOT pressed (controller task)
  enum ClaimResult { CLAIM_NONE, CLAIM_PENDING, CLAIM_DONE, CLAIM_EXPIRED, CLAIM_SAVE_FAILED };
  // On CLAIM_DONE the new key is returned once and the connection becomes authorized.
  ClaimResult claim_result(uint32_t now_ms, uint8_t key_id_out[8], uint8_t key_out[32]);

  // AUTH_REVOKE (authorized only). all-0xFF id = revoke every key except the current one.
  bool revoke(const uint8_t key_id[8]);

  bool authorized() const { return authorized_; }
  uint8_t key_count() const { return store_.count; }
  const AuthStore& store() const { return store_; }
  uint8_t fails() const { return fails_; }

 private:
  int find(const uint8_t id[8]) const;
  AuthStore store_;
  char dev_id_[13] = {0};
  RandomFn rnd_ = nullptr;
  SaveFn save_ = nullptr;
  bool connected_ = false;
  bool authorized_ = false;
  int cur_key_ = -1;
  bool have_hello_ = false;
  uint8_t pn_[16], wn_[16];
  uint8_t fails_ = 0;
  // claim
  bool claim_open_ = false, claim_confirmed_ = false, claim_delivered_ = false;
  uint32_t claim_t0_ = 0;
  char claim_name_[24] = {0};
  AuthKey claim_key_;
  uint32_t next_seq_ = 1;
};

}  // namespace avo
