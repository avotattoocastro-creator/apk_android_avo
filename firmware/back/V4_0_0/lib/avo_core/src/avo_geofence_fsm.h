// Geofence-driven automatic recording — explicit state machine.
// Normative description: GEOFENCE_STATE_MACHINE.md
#pragma once
#include <stdint.h>
#include <stddef.h>
#include "avo_config.h"
#include "avo_payloads.h"

namespace avo {

enum class GfState : uint8_t {
  AUTO_DISABLED = 0, WAITING_GNSS, OUTSIDE, ENTRY_PENDING, INSIDE, RECORDING, EXIT_PENDING, POST_RECORDING, PAUSED, ERROR,
};
const char* gf_state_str(GfState s);

enum class Zone : uint8_t { INVALID = 0, IN, OUT, AMBIGUOUS };

// Quality gate for geofence decisions. RTK FIX is NOT required: any valid
// 3D (or GNSS+DR) solution with gnssFixOK and hAcc <= hacc_max is accepted.
struct FixInput {
  bool valid = false;
  double sd_m = 0;        // signed distance to the fence union (neg = inside)
  double hacc_m = 0;
  uint8_t fence_id = 0;
};
bool gnss_quality_ok(const GnssSample& s, uint32_t hacc_max_cm);

enum class GfActionType : uint8_t { NONE = 0, START, STOP, PAUSE, RESUME, EVENT };
enum class GfEvent : uint16_t {
  NONE = 0, ENTRY_PENDING = 0x100, ENTRY_CONFIRMED, ENTRY_CANCELLED, EXIT_PENDING, EXIT_CONFIRMED,
  EXIT_CANCELLED, GNSS_LOST, GNSS_RECOVERED, INHIBITED, REARMED, POST_RECORD_BEGIN, POST_RECORD_CANCELLED,
  CONFIG_ERROR, DECISION_DEFERRED, EXIT_CONTINUE,
};
struct GfAction {
  GfActionType type = GfActionType::NONE;
  GfEvent event = GfEvent::NONE;
  bool manual = false;     // action originated from a manual command
  uint32_t t_ms = 0;
  int32_t arg = 0;
};

class GeofenceFsm {
 public:
  // fences_ok: at least one active fence compiled successfully.
  void configure(const Config& cfg, bool fences_ok, uint32_t now_ms);
  // Feed one GNSS evaluation (call for every GNSS sample, valid or not).
  void on_fix(const FixInput& in, uint32_t now_ms);
  // Periodic tick (>= 5 Hz recommended): GNSS timeouts, post-record and re-arm timers.
  void tick(uint32_t now_ms);
  // Manual control (BOOT, Android, developer mode). Manual commands always win.
  void manual_start(uint32_t now_ms);
  void manual_stop(uint32_t now_ms);
  void manual_pause(uint32_t now_ms);
  void manual_resume(uint32_t now_ms);
  void manual_rearm(uint32_t now_ms);
  // After a reboot in the middle of a session the controller re-enters RECORDING.
  void resume_after_reboot(bool manual_session, uint32_t now_ms);

  bool poll(GfAction* out);
  GfState state() const { return st_; }
  bool recording() const { return st_ == GfState::RECORDING || st_ == GfState::EXIT_PENDING || st_ == GfState::POST_RECORDING; }
  bool paused() const { return st_ == GfState::PAUSED; }
  bool inhibited() const { return inhibit_; }
  bool manual_session() const { return manual_session_; }
  bool gnss_lost() const { return gnss_lost_; }
  Zone last_zone() const { return zone_; }
  double last_sd() const { return last_sd_; }
  // Remaining confirmation time (ms) for the pending entry/exit/post, 0 if none.
  uint32_t pending_remaining_ms(uint32_t now_ms) const;
  Zone classify(const FixInput& in) const;

 private:
  void emit(GfActionType t, GfEvent e, uint32_t now, bool manual = false, int32_t arg = 0);
  void go(GfState s) { st_ = s; }
  void on_invalid(uint32_t now);
  void after_stop(uint32_t now, bool manual);
  bool auto_active() const { return cfg_.auto_enabled && fences_ok_; }
  void track_rearm(Zone z, uint32_t now);
  void start_timer(uint32_t now) { timer_start_ = now; timer_running_ = true; }
  uint32_t elapsed(uint32_t now) const { return timer_running_ ? now - timer_start_ : 0; }

  Config cfg_;
  bool fences_ok_ = false;
  GfState st_ = GfState::AUTO_DISABLED;
  Zone zone_ = Zone::INVALID;
  double last_sd_ = 0;
  bool inhibit_ = false;
  uint32_t inhibit_since_ = 0;
  bool manual_session_ = false;
  bool gnss_lost_ = false;
  bool have_valid_ = false;
  bool exit_continued_ = false;   // CONTINUE action already taken for this excursion
  bool paused_manual_ = false;    // paused by the user: never auto-resumed
  bool stale_ = false;            // GNSS timeout already processed
  uint32_t last_valid_ms_ = 0;
  uint32_t timer_start_ = 0;      // entry/exit/reentry confirmation start
  bool timer_running_ = false;
  uint32_t post_start_ = 0;
  uint32_t outside_since_ = 0;    // re-arm tracking while INSIDE (inhibited)
  bool outside_tracking_ = false;
  GfAction q_[16];
  uint8_t qh_ = 0, qt_ = 0;
};

}  // namespace avo
