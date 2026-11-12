#include "avo_geofence_fsm.h"

namespace avo {

const char* gf_state_str(GfState s) {
  switch (s) {
    case GfState::AUTO_DISABLED: return "DISABLED";
    case GfState::WAITING_GNSS: return "WAITING_GNSS";
    case GfState::OUTSIDE: return "OUTSIDE";
    case GfState::ENTRY_PENDING: return "ENTRY_PENDING";
    case GfState::INSIDE: return "INSIDE";
    case GfState::RECORDING: return "RECORDING";
    case GfState::EXIT_PENDING: return "EXIT_PENDING";
    case GfState::POST_RECORDING: return "POST_RECORDING";
    case GfState::PAUSED: return "PAUSED";
    case GfState::ERROR: return "ERROR";
  }
  return "?";
}

bool gnss_quality_ok(const GnssSample& s, uint32_t hacc_max_cm) {
  if (!s.gnss_fix_ok()) return false;
  if (s.fix_type != 3 && s.fix_type != 4) return false;  // 3D or GNSS+DR; RTK not required
  if (s.invalid_llh()) return false;
  if (s.hacc_mm > hacc_max_cm * 10u) return false;
  return true;
}

void GeofenceFsm::emit(GfActionType t, GfEvent e, uint32_t now, bool manual, int32_t arg) {
  uint8_t next = (uint8_t)((qt_ + 1) % 16);
  if (next == qh_) qh_ = (uint8_t)((qh_ + 1) % 16);  // drop oldest (consumer polls every cycle)
  GfAction& a = q_[qt_];
  a.type = t; a.event = e; a.manual = manual; a.t_ms = now; a.arg = arg;
  qt_ = next;
}

bool GeofenceFsm::poll(GfAction* out) {
  if (qh_ == qt_) return false;
  *out = q_[qh_];
  qh_ = (uint8_t)((qh_ + 1) % 16);
  return true;
}

void GeofenceFsm::configure(const Config& cfg, bool fences_ok, uint32_t now) {
  cfg_ = cfg;
  fences_ok_ = fences_ok;
  bool rec = recording() || paused();
  if (rec) return;  // never interrupt a session because of a configuration change
  if (!cfg_.auto_enabled) { go(GfState::AUTO_DISABLED); return; }
  if (!fences_ok_) {
    if (st_ != GfState::ERROR) emit(GfActionType::EVENT, GfEvent::CONFIG_ERROR, now);
    go(GfState::ERROR);
    return;
  }
  if (st_ == GfState::AUTO_DISABLED || st_ == GfState::ERROR || st_ == GfState::ENTRY_PENDING) {
    timer_running_ = false;
    go(GfState::WAITING_GNSS);
  }
}

Zone GeofenceFsm::classify(const FixInput& in) const {
  if (!in.valid) return Zone::INVALID;
  double k = cfg_.uncertainty_k_x100 / 100.0;
  double em = cfg_.entry_margin_cm / 100.0, xm = cfg_.exit_margin_cm / 100.0;
  if (in.sd_m <= -em && in.sd_m + k * in.hacc_m <= 0) return Zone::IN;
  if (in.sd_m >= xm && in.sd_m - k * in.hacc_m >= 0) return Zone::OUT;
  return Zone::AMBIGUOUS;
}

void GeofenceFsm::track_rearm(Zone z, uint32_t now) {
  if (!inhibit_) { outside_tracking_ = false; return; }
  if (z == Zone::OUT) {
    if (!outside_tracking_) { outside_tracking_ = true; outside_since_ = now; }
    if (now - outside_since_ >= (uint32_t)cfg_.exit_confirm_s * 1000u) {
      inhibit_ = false;
      outside_tracking_ = false;
      emit(GfActionType::EVENT, GfEvent::REARMED, now);
    }
  } else {
    outside_tracking_ = false;
  }
}

void GeofenceFsm::on_invalid(uint32_t now) {
  zone_ = Zone::INVALID;
  outside_tracking_ = false;
  bool was_valid = have_valid_ && !gnss_lost_;
  if (was_valid) { gnss_lost_ = true; emit(GfActionType::EVENT, GfEvent::GNSS_LOST, now); }
  switch (st_) {
    case GfState::EXIT_PENDING:
      // Loss of signal is never an exit.
      timer_running_ = false;
      emit(GfActionType::EVENT, GfEvent::EXIT_CANCELLED, now);
      go(GfState::RECORDING);
      break;
    case GfState::POST_RECORDING:
    case GfState::PAUSED:
      timer_running_ = false;  // re-entry/resume confirmation restarts from zero
      break;
    case GfState::ENTRY_PENDING:
      timer_running_ = false;
      emit(GfActionType::EVENT, GfEvent::ENTRY_CANCELLED, now);
      go(GfState::WAITING_GNSS);
      break;
    case GfState::OUTSIDE:
    case GfState::INSIDE:
      go(GfState::WAITING_GNSS);  // inhibit flag is preserved
      break;
    default:
      break;
  }
}

void GeofenceFsm::on_fix(const FixInput& in, uint32_t now) {
  if (!in.valid) { on_invalid(now); return; }
  stale_ = false;
  if (gnss_lost_) { gnss_lost_ = false; emit(GfActionType::EVENT, GfEvent::GNSS_RECOVERED, now); }
  have_valid_ = true;
  last_valid_ms_ = now;
  last_sd_ = in.sd_m;
  Zone z = classify(in);
  zone_ = z;
  if (!auto_active()) return;
  if (st_ == GfState::WAITING_GNSS || st_ == GfState::OUTSIDE || st_ == GfState::INSIDE) track_rearm(z, now);

  const uint32_t entry_ms = (uint32_t)cfg_.entry_confirm_s * 1000u;
  const uint32_t exit_ms = (uint32_t)cfg_.exit_confirm_s * 1000u;

  switch (st_) {
    case GfState::WAITING_GNSS:
    case GfState::OUTSIDE:
    case GfState::INSIDE:
      if (z == Zone::IN) {
        if (inhibit_) { go(GfState::INSIDE); break; }
        start_timer(now);
        go(GfState::ENTRY_PENDING);
        emit(GfActionType::EVENT, GfEvent::ENTRY_PENDING, now);
        if (entry_ms == 0) {
          emit(GfActionType::EVENT, GfEvent::ENTRY_CONFIRMED, now);
          emit(GfActionType::START, GfEvent::ENTRY_CONFIRMED, now, false, in.fence_id);
          manual_session_ = false; timer_running_ = false; exit_continued_ = false;
          go(GfState::RECORDING);
        }
      } else if (z == Zone::OUT) {
        go(GfState::OUTSIDE);
      } else if (st_ == GfState::WAITING_GNSS) {
        // ambiguous: decision deferred, stay waiting for a clear classification
      }
      break;

    case GfState::ENTRY_PENDING:
      if (z == Zone::IN) {
        if (elapsed(now) >= entry_ms) {
          emit(GfActionType::EVENT, GfEvent::ENTRY_CONFIRMED, now);
          emit(GfActionType::START, GfEvent::ENTRY_CONFIRMED, now, false, in.fence_id);
          manual_session_ = false; timer_running_ = false; exit_continued_ = false;
          go(GfState::RECORDING);
        }
      } else if (z == Zone::OUT || in.sd_m >= 0) {
        timer_running_ = false;
        emit(GfActionType::EVENT, GfEvent::ENTRY_CANCELLED, now);
        go(GfState::OUTSIDE);
      } else {
        start_timer(now);  // inside but too uncertain / within margin: restart confirmation
      }
      break;

    case GfState::RECORDING:
      if (manual_session_) break;  // manual sessions are never stopped by the geofence
      if (exit_continued_) { if (in.sd_m <= 0) exit_continued_ = false; break; }
      if (z == Zone::OUT) {
        start_timer(now);
        go(GfState::EXIT_PENDING);
        emit(GfActionType::EVENT, GfEvent::EXIT_PENDING, now);
        if (exit_ms != 0) break;
      } else {
        break;
      }
      // immediate exit when exit_confirm_s == 0
      [[fallthrough]];
    case GfState::EXIT_PENDING:
      if (z == Zone::OUT) {
        if (elapsed(now) >= exit_ms) {
          timer_running_ = false;
          emit(GfActionType::EVENT, GfEvent::EXIT_CONFIRMED, now);
          switch (cfg_.exit_action) {
            case ExitAction::STOP_AND_SAVE:
              if (cfg_.post_s > 0) {
                post_start_ = now;
                emit(GfActionType::EVENT, GfEvent::POST_RECORD_BEGIN, now, false, cfg_.post_s);
                go(GfState::POST_RECORDING);
              } else {
                emit(GfActionType::STOP, GfEvent::EXIT_CONFIRMED, now);
                after_stop(now, false);
              }
              break;
            case ExitAction::PAUSE:
              emit(GfActionType::PAUSE, GfEvent::EXIT_CONFIRMED, now);
              paused_manual_ = false;
              go(GfState::PAUSED);
              break;
            case ExitAction::CONTINUE:
              emit(GfActionType::EVENT, GfEvent::EXIT_CONTINUE, now);
              exit_continued_ = true;
              go(GfState::RECORDING);
              break;
          }
        }
      } else if (in.sd_m <= 0) {
        timer_running_ = false;
        emit(GfActionType::EVENT, GfEvent::EXIT_CANCELLED, now);
        go(GfState::RECORDING);
      } else {
        start_timer(now);  // between boundary and exit margin: restart confirmation
      }
      break;

    case GfState::POST_RECORDING:
      if (z == Zone::IN) {
        if (!timer_running_) start_timer(now);
        if (elapsed(now) >= entry_ms) {
          timer_running_ = false;
          emit(GfActionType::EVENT, GfEvent::POST_RECORD_CANCELLED, now);
          go(GfState::RECORDING);
        }
      } else {
        timer_running_ = false;
      }
      break;

    case GfState::PAUSED:
      if (paused_manual_) break;
      if (z == Zone::IN) {
        if (!timer_running_) start_timer(now);
        if (elapsed(now) >= entry_ms) {
          timer_running_ = false;
          emit(GfActionType::RESUME, GfEvent::ENTRY_CONFIRMED, now);
          go(GfState::RECORDING);
        }
      } else {
        timer_running_ = false;
      }
      break;

    case GfState::AUTO_DISABLED:
    case GfState::ERROR:
      break;
  }
}

void GeofenceFsm::tick(uint32_t now) {
  if (have_valid_ && !stale_ && now - last_valid_ms_ > cfg_.gnss_loss_ms) {
    stale_ = true;
    on_invalid(now);
  }
  if (st_ == GfState::POST_RECORDING && now - post_start_ >= (uint32_t)cfg_.post_s * 1000u) {
    emit(GfActionType::STOP, GfEvent::EXIT_CONFIRMED, now);
    after_stop(now, false);
  }
  if (inhibit_ && cfg_.rearm_timeout_s > 0 && now - inhibit_since_ >= (uint32_t)cfg_.rearm_timeout_s * 1000u) {
    inhibit_ = false;
    emit(GfActionType::EVENT, GfEvent::REARMED, now);
    if (st_ == GfState::INSIDE) go(GfState::WAITING_GNSS);
  }
}

void GeofenceFsm::after_stop(uint32_t now, bool manual) {
  manual_session_ = false;
  exit_continued_ = false;
  paused_manual_ = false;
  timer_running_ = false;
  if (!cfg_.auto_enabled) { go(GfState::AUTO_DISABLED); return; }
  if (!fences_ok_) { go(GfState::ERROR); return; }
  if (manual && zone_ != Zone::OUT) {
    // Stopped by the user while (possibly) inside: inhibit automatic restart.
    inhibit_ = true;
    inhibit_since_ = now;
    outside_tracking_ = false;
    emit(GfActionType::EVENT, GfEvent::INHIBITED, now);
    go(zone_ == Zone::INVALID ? GfState::WAITING_GNSS : GfState::INSIDE);
    return;
  }
  go(zone_ == Zone::OUT ? GfState::OUTSIDE : GfState::WAITING_GNSS);
}

void GeofenceFsm::manual_start(uint32_t now) {
  if (recording()) return;
  if (st_ == GfState::PAUSED) { manual_resume(now); return; }
  emit(GfActionType::START, GfEvent::NONE, now, true);
  manual_session_ = true;
  inhibit_ = false;
  exit_continued_ = false;
  timer_running_ = false;
  go(GfState::RECORDING);
}

void GeofenceFsm::manual_stop(uint32_t now) {
  if (!recording() && st_ != GfState::PAUSED) return;
  emit(GfActionType::STOP, GfEvent::NONE, now, true);
  after_stop(now, true);
}

void GeofenceFsm::manual_pause(uint32_t now) {
  if (!recording()) return;
  emit(GfActionType::PAUSE, GfEvent::NONE, now, true);
  paused_manual_ = true;
  timer_running_ = false;
  go(GfState::PAUSED);
}

void GeofenceFsm::manual_resume(uint32_t now) {
  if (st_ != GfState::PAUSED) return;
  emit(GfActionType::RESUME, GfEvent::NONE, now, true);
  paused_manual_ = false;
  timer_running_ = false;
  go(GfState::RECORDING);
}

void GeofenceFsm::manual_rearm(uint32_t now) {
  if (!inhibit_) return;
  inhibit_ = false;
  emit(GfActionType::EVENT, GfEvent::REARMED, now, true);
  if (st_ == GfState::INSIDE) go(GfState::WAITING_GNSS);
}

void GeofenceFsm::resume_after_reboot(bool manual_session, uint32_t now) {
  (void)now;
  manual_session_ = manual_session;
  have_valid_ = false;
  gnss_lost_ = false;
  timer_running_ = false;
  exit_continued_ = false;
  go(GfState::RECORDING);
}

uint32_t GeofenceFsm::pending_remaining_ms(uint32_t now) const {
  uint32_t total = 0, el = 0;
  if (st_ == GfState::ENTRY_PENDING) { total = cfg_.entry_confirm_s * 1000u; el = elapsed(now); }
  else if (st_ == GfState::EXIT_PENDING) { total = cfg_.exit_confirm_s * 1000u; el = elapsed(now); }
  else if (st_ == GfState::POST_RECORDING) { total = cfg_.post_s * 1000u; el = now - post_start_; }
  else return 0;
  return el >= total ? 0 : total - el;
}

}  // namespace avo
