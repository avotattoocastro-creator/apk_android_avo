// AVO GIRTH LINK v1 — girth unit (cincha, ESP32-C6) <-> back (Heltec) over ESP-NOW.
//
// Separate from the chest<->back link (different magic), same radio channel. The back is the hub:
// it receives the girth's IMU batches and forwards them to the chest as IMU_SAMPLE frames, and it
// reports the girth link (connected, RSSI, packets, losses) in its STATUS.
//
// Packet (<= 250 bytes):
//   off size
//   0   2    magic 0xA5 0x47 ('G')
//   2   1    link version (1)
//   3   1    kind (GirthKind)
//   4   4    boot_id of the sender (random per boot: a change resets loss counting)
//   8   4    seq of the sender (per kind family, +1 per packet)
//   12  2    body length
//   14  2    CRC-16/CCITT-FALSE over bytes 0..13 and the body
//   16  ...  body
//
// Pairing: the girth broadcasts HELLO every second until a back answers WELCOME (unicast). The back
// accepts the first girth it ever sees (stored in NVS) and afterwards only that one, unless its
// pairing window is open (USER/PRG held 3 s), which lets a new girth replace it. The girth stores the
// back MAC and talks unicast from then on (MAC-level ACK + retries).
#pragma once
#include <stdint.h>
#include <stddef.h>
#include <string.h>

namespace avo {

static const uint8_t GIRTH_MAGIC0 = 0xA5, GIRTH_MAGIC1 = 0x47;
static const uint8_t GIRTH_LINK_VERSION = 1;
static const size_t GIRTH_HDR = 16;
static const size_t GIRTH_MAX_PACKET = 250;
static const size_t GIRTH_MAX_BODY = GIRTH_MAX_PACKET - GIRTH_HDR;   // 234
// IMU samples per packet so that the forwarded IMU_SAMPLE frame still fits one chest packet:
// 24 (IMU header) + 10 * 18 = 204 bytes of payload.
static const uint8_t GIRTH_IMU_MAX_SAMPLES = 10;

enum class GirthKind : uint8_t { HELLO = 1, WELCOME = 2, STATUS = 3, IMU = 4, PING = 5 };

struct GirthHeader {
  GirthKind kind = GirthKind::STATUS;
  uint32_t boot_id = 0;
  uint32_t seq = 0;
  uint16_t body_len = 0;
};

size_t girth_build(const GirthHeader& h, const uint8_t* body, size_t body_len, uint8_t* out, size_t cap);
bool girth_parse(const uint8_t* p, size_t n, GirthHeader* h, const uint8_t** body);

// HELLO (girth -> broadcast) and WELCOME (back -> girth): identity of the sender.
struct GirthHello {
  char dev_id[16] = {0};   // MAC as hex
  char fw[16] = {0};       // firmware version
  uint8_t hw = 0;          // girth: 1 = ESP32-C6 · back: 0
  uint8_t imu_count = 0;   // IMUs the girth expects (0 while none is wired)
};
static const size_t GIRTH_HELLO_LEN = 34;
size_t girth_hello_encode(const GirthHello& m, uint8_t* out, size_t cap);
bool girth_hello_decode(const uint8_t* p, size_t n, GirthHello* m);

// STATUS (girth -> back, 1 Hz)
struct GirthStatus {
  uint32_t uptime_ms = 0;
  uint16_t batt_mv = 0;        // 0 = not measured
  uint8_t imu_mask = 0;        // b0..b2: IMU 0..2 detected
  uint8_t imu_count = 0;
  int8_t rssi_back = 0;        // RSSI of the last packet from the back (dBm)
  uint32_t tx_ok = 0, tx_fail = 0;
  uint32_t imu_batches = 0;    // IMU packets sent since boot
  uint32_t pings_rx = 0;       // PINGs received from the back
};
static const size_t GIRTH_STATUS_LEN = 25;
size_t girth_status_encode(const GirthStatus& s, uint8_t* out, size_t cap);
bool girth_status_decode(const uint8_t* p, size_t n, GirthStatus* s);

// PING (back -> girth, 1 Hz): lets the girth know the link is alive both ways.
struct GirthPing {
  uint8_t flags = 0;          // b0 chest online (back <-> chest link up)
  int8_t rssi_girth = 0;      // RSSI the back sees from the girth
  uint32_t rx_packets = 0;    // girth packets the back accepted
  uint32_t lost = 0;          // girth packets the back detected as lost (seq gaps)
};
static const size_t GIRTH_PING_LEN = 10;
size_t girth_ping_encode(const GirthPing& p, uint8_t* out, size_t cap);
bool girth_ping_decode(const uint8_t* p, size_t n, GirthPing* g);

// ------------------------------------------------------------------ back side
class GirthHub {
 public:
  struct Io {
    virtual ~Io() {}
    virtual bool send(const uint8_t mac[6], const uint8_t* d, size_t n) = 0;   // unicast
    virtual void add_peer(const uint8_t mac[6]) = 0;
    virtual void store_girth(const uint8_t mac[6]) = 0;                         // persist the paired girth
    virtual void forward_imu(const uint8_t* payload, size_t n) = 0;             // IMU_SAMPLE frame to the chest
  };
  GirthHub(Io* io, const char* dev_id, const char* fw, uint32_t boot_id);
  void set_boot_id(uint32_t b) { boot_id_ = b; }
  void begin(const uint8_t* stored_mac);       // nullptr = none paired yet
  // Every radio packet; returns false if it is not a girth packet (the caller tries the chest link).
  bool on_radio(const uint8_t mac[6], const uint8_t* d, size_t n, int8_t rssi, uint32_t now_ms, bool pairing_open);
  void tick(uint32_t now_ms, bool chest_online);

  bool paired() const { return have_; }
  bool connected(uint32_t now_ms) const { return have_ && last_rx_ms_ && now_ms - last_rx_ms_ < 3000; }
  const uint8_t* mac() const { return mac_; }
  int8_t rssi() const { return rssi_; }
  uint32_t rx_packets() const { return rx_; }
  uint32_t lost() const { return lost_; }
  uint32_t imu_forwarded() const { return imu_fwd_; }
  uint32_t rejected() const { return rejected_; }
  const GirthStatus& status() const { return st_; }
  const GirthHello& hello() const { return hello_; }

 private:
  void welcome(const uint8_t mac[6], uint32_t now_ms);
  void count_seq(const GirthHeader& h);
  Io* io_;
  char dev_[16] = {0}, fw_[16] = {0};
  uint32_t boot_id_, seq_ = 0;
  bool have_ = false;
  uint8_t mac_[6] = {0};
  uint32_t last_rx_ms_ = 0, last_ping_ms_ = 0;
  int8_t rssi_ = 0;
  uint32_t rx_ = 0, lost_ = 0, imu_fwd_ = 0, rejected_ = 0;
  uint32_t peer_boot_ = 0, last_seq_ = 0;
  bool have_seq_ = false;
  GirthStatus st_;
  GirthHello hello_;
};

}  // namespace avo
