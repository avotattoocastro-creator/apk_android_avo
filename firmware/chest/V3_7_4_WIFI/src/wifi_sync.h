// AVO CHEST V3.7.4 — training download over Wi-Fi (SoftAP + HTTP).
// The phone turns it on through BLE (WIFI_SYNC 0x64); the AP shares the radio with ESP-NOW (same channel)
// and BLE. It never runs during a recording, and it turns itself off when there is no activity.
#pragma once
#include <stddef.h>
#include <stdint.h>

namespace wifisync {

enum class State : uint8_t { OFF = 0, STARTING = 1, READY = 2, CLIENT = 3, STOPPING = 4 };

// Reasons for refusing to turn on (BLE status mapping in ble_service).
enum class StartResult : uint8_t { OK = 0, RECORDING = 1, LOW_BATTERY = 2, NO_SD = 3, RADIO_ERROR = 4, BUSY = 5 };

// Stop reasons (diagnostics).
enum class StopReason : uint8_t { NONE = 0, APP = 1, IDLE = 2, NO_CLIENT = 3, MAX_TIME = 4, RECORDING = 5, LOW_BATTERY = 6, CLIENT_LEFT = 7, ERROR = 8, AUTH_FAIL = 9, DONE = 10 };

struct Credentials {
  char ssid[33];
  char password[33];
  char token[33];       // 128-bit session token in hex; new on every start
  char ip[16];
  uint8_t bssid[6];     // AP MAC (lets Android remember the approval and auto-connect)
  uint8_t channel;
  uint16_t port;
  uint32_t idle_timeout_s;
};

struct Stats {
  State state;
  StopReason last_stop;
  uint32_t starts, requests, auth_failures, bytes_sent, on_ms_total, completes;
};

bool init();                                   // creates the supervision task (AP off)
StartResult start(Credentials* out);           // idempotent: if already on, returns the same credentials
void stop(StopReason why);
bool regenerate_password();                    // new per-device password (only with AP off)
State state();
bool set_enabled(bool on);                     // rc2: WIFI_SYNC 5 (re-enable after a block)
bool enabled();
void stats(Stats* out);
const char* stop_reason_text(StopReason r);

}  // namespace wifisync
