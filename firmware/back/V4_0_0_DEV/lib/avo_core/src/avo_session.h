// Training session lifecycle and metrics derived from measured data only.
#pragma once
#include <stdint.h>
#include <stddef.h>
#include "avo_config.h"
#include "avo_payloads.h"
#include "avo_geo.h"

namespace avo {

enum class SessionState : uint8_t {
  IDLE = 0, ARMED, RECORDING, PAUSED, STOPPED_WAITING_UPLOAD, COMPLETED, RECOVERY, ERROR,
};
const char* session_state_str(SessionState s);

enum class StartReason : uint8_t { MANUAL_BUTTON = 0, MANUAL_APP = 1, GEOFENCE = 2, RESUME_AFTER_REBOOT = 3, MANUAL_DEV = 4 };

static const int AVO_N_SPLITS = 5;  // 100, 200, 400, 800, 1000 m
extern const uint16_t kSplitDistances[AVO_N_SPLITS];

struct SessionMetrics {
  uint32_t active_ms = 0;       // recording time excluding pauses
  uint32_t wall_ms = 0;         // since start, including pauses
  double distance_m = 0;        // Doppler-speed integration, quality gated
  double max_speed_mps = 0;
  double max_accel_mps2 = 0;
  double max_decel_mps2 = 0;    // positive number
  uint32_t gnss_samples = 0;
  uint32_t gnss_valid = 0;
  uint32_t imu_batches = 0;
  uint32_t imu_samples = 0;
  uint32_t uart_frames_lost = 0;    // from UART seq gaps
  uint32_t girth_pkts_lost = 0;     // from original girth seq gaps
  uint32_t records_dropped = 0;     // chest-side buffer overflow
  uint32_t t_fix_ms = 0, t_float_ms = 0, t_gnss_ms = 0, t_nofix_ms = 0;
  uint32_t split_ms[AVO_N_SPLITS] = {0};  // time to reach distance since last split reset, 0 = not reached
  uint32_t markers = 0;
  uint32_t laps = 0;
  uint32_t last_lap_ms = 0, best_lap_ms = 0;
  uint32_t series = 0;
  uint32_t series_total_ms = 0;
  uint32_t incidents = 0;
  uint32_t line_cross[4] = {0, 0, 0, 0};
  double mean_speed_mps() const { return active_ms ? distance_m / (active_ms / 1000.0) : 0; }
};

class SessionMetricsCalc {
 public:
  void reset(const Config& cfg);
  // Call for every GNSS sample while the session is RECORDING (not paused).
  void on_gnss(const GnssSample& s, uint32_t now_ms);
  void on_imu_batch(uint8_t count) { m_.imu_batches++; m_.imu_samples += count; }
  void on_marker(uint32_t now_ms);
  void on_pause_gap() { have_prev_ = false; }
  void set_time(uint32_t active_ms, uint32_t wall_ms) { m_.active_ms = active_ms; m_.wall_ms = wall_ms; }
  SessionMetrics& m() { return m_; }
  const SessionMetrics& m() const { return m_; }
 private:
  Config cfg_;
  SessionMetrics m_;
  bool have_prev_ = false;
  GnssSample prev_;
  uint32_t prev_ms_ = 0;
  double split_base_m_ = 0;
  uint32_t split_base_ms_ = 0;
  double speed_hist_[32] = {0};   // >= 1.2 s of history up to 25 Hz
  uint32_t speed_t_[32] = {0};
  int hist_n_ = 0;
  bool line_init_ = false;
  LocalFrame lf_[4];
  uint32_t lap_start_ms_ = 0;
  bool lap_started_ = false;
  bool in_series_ = false;
  uint32_t series_start_ms_ = 0;
  uint32_t above_ms_ = 0;
};

// Lifecycle with validated transitions. Times in chest monotonic ms.
class SessionLifecycle {
 public:
  SessionState state() const { return st_; }
  bool arm(bool auto_enabled);              // IDLE <-> ARMED
  bool start(uint32_t now_ms, StartReason r);
  bool pause(uint32_t now_ms);
  bool resume(uint32_t now_ms);
  bool stop(uint32_t now_ms);               // -> STOPPED_WAITING_UPLOAD
  bool mark_uploaded();                     // STOPPED_WAITING_UPLOAD -> COMPLETED
  void enter_recovery() { st_ = SessionState::RECOVERY; }
  void enter_error() { st_ = SessionState::ERROR; }
  bool active() const { return st_ == SessionState::RECORDING || st_ == SessionState::PAUSED; }
  uint32_t active_ms(uint32_t now_ms) const;
  uint32_t wall_ms(uint32_t now_ms) const { return active() ? now_ms - start_ms_ : last_wall_; }
  StartReason reason() const { return reason_; }
  // Restores timing after a reboot (active time already elapsed before the reset).
  void restore(uint32_t now_ms, uint32_t prior_active_ms, StartReason r);
 private:
  SessionState st_ = SessionState::IDLE;
  StartReason reason_ = StartReason::MANUAL_BUTTON;
  uint32_t start_ms_ = 0, seg_start_ms_ = 0, active_acc_ = 0, last_wall_ = 0;
};

// "S<dev4hex>_<boot6>_<n3>" — unique without GNSS time (boot counter persisted in NVS).
void make_session_id(uint16_t dev_id, uint32_t boot_count, uint16_t n, char out[24]);

}  // namespace avo
