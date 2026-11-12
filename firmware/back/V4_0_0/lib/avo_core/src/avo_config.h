// AVO CONFIG SCHEMA v1 — persistent configuration of the chest.
// Binary container (little-endian):
//   "AVOC" | u16 schema | u16 reserved | u32 body_len | body | u32 crc32(all previous bytes)
// body = sequence of sections: u16 tag | u16 len | bytes
// Sections are fixed layouts that may only grow by appending fields. Unknown
// tags are skipped; missing tags or missing trailing fields keep defaults.
// Credentials are never stored here.
#pragma once
#include <stdint.h>
#include <stddef.h>
#include "avo_geo.h"

namespace avo {

static const uint16_t AVO_CONFIG_SCHEMA = 1;

enum class ExitAction : uint8_t { STOP_AND_SAVE = 0, PAUSE = 1, CONTINUE = 2 };

struct VirtualLine {
  uint8_t enabled = 0;
  int32_t a_lat_e7 = 0, a_lon_e7 = 0, b_lat_e7 = 0, b_lon_e7 = 0;
};

struct Config {
  uint16_t schema = AVO_CONFIG_SCHEMA;
  // identity
  char device_name[20] = "AVO-CHEST";
  uint32_t horse_id = 0;
  char horse_name[24] = "";
  uint32_t rider_id = 0;
  char rider_name[24] = "";
  // geofence automation
  uint8_t auto_enabled = 1;
  uint8_t active_mask = 0x01;       // bit i => fence slot i active (union)
  uint16_t entry_confirm_s = 5;     // 0..60
  uint16_t exit_confirm_s = 15;     // 0..120
  uint32_t entry_margin_cm = 500;   // 0..10000
  uint32_t exit_margin_cm = 1500;   // 0..10000
  uint32_t hacc_max_cm = 1000;      // 50..5000
  uint16_t uncertainty_k_x100 = 100;  // 0..300 (hAcc multiplier in decisions)
  ExitAction exit_action = ExitAction::STOP_AND_SAVE;
  uint8_t pre_s = 30;               // 0..60
  uint8_t post_s = 15;              // 0..60
  uint16_t rearm_timeout_s = 0;     // 0 = only re-arm after a confirmed exit
  uint16_t gnss_loss_ms = 3000;     // 500..30000: no valid sample for this long => GNSS lost
  uint16_t resume_window_s = 300;   // reboot during session: continue if back within this window
  uint8_t fence_count = 0;
  FenceDef fences[AVO_MAX_FENCES];
  // display
  uint8_t brightness = 180;         // 10..255
  uint16_t screen_timeout_s = 30;   // 0 = never
  uint8_t dim_on_low_batt = 1;
  // recording
  uint16_t flush_ms = 1000;         // 200..5000
  uint16_t fsync_ms = 2000;         // 500..10000
  uint16_t segment_mb = 512;        // 16..2048
  uint32_t nominal_rate_bps = 32000;  // bytes/s used to size the pre-buffer
  // BLE
  uint8_t ble_require_bond = 1;
  // training
  uint16_t series_speed_cms = 400;  // speed threshold for a work series
  uint16_t series_min_s = 10;
  VirtualLine lines[4];
  // UART link
  uint32_t uart_baud = 921600;      // 115200, 230400, 460800, 921600
  // power
  uint8_t low_batt_pct = 15;
  uint8_t critical_batt_pct = 5;
  uint16_t critical_batt_mv = 3450;
};

void config_defaults(Config* c);
// Clamps every field to its legal range. Returns number of fields corrected.
int config_validate(Config* c);

enum class ConfigLoad : uint8_t { OK = 0, TOO_SHORT, BAD_MAGIC, BAD_CRC, BAD_LENGTH, NEWER_SCHEMA_OK, MIGRATED };
size_t config_serialize(const Config& c, uint8_t* out, size_t cap);
// Always leaves *c in a valid state (defaults on failure).
ConfigLoad config_deserialize(const uint8_t* p, size_t n, Config* c);
size_t config_max_size();

// Single-section encoders used by BLE (SET_FENCE / GET_FENCE).
size_t fence_serialize(const FenceDef& f, uint8_t* out, size_t cap);
bool fence_deserialize(const uint8_t* p, size_t n, FenceDef* f);

}  // namespace avo
