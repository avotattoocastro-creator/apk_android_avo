#include "avo_session.h"
#include <math.h>

namespace {
// Strict crossing of segment P->Q over the finite line A-B. A point exactly on
// the line counts as being on the positive side, so touching it never yields
// two crossings.
bool crosses(double ax, double ay, double bx, double by, double px, double py, double qx, double qy) {
  double sp = (bx - ax) * (py - ay) - (by - ay) * (px - ax);
  double sq = (bx - ax) * (qy - ay) - (by - ay) * (qx - ax);
  bool p_pos = sp >= 0, q_pos = sq >= 0;
  if (p_pos == q_pos) return false;
  double sa = (qx - px) * (ay - py) - (qy - py) * (ax - px);
  double sb = (qx - px) * (by - py) - (qy - py) * (bx - px);
  return (sa >= 0) != (sb >= 0) || sa == 0 || sb == 0;
}
}  // namespace
#include <stdio.h>
#include <string.h>

namespace avo {

const uint16_t kSplitDistances[AVO_N_SPLITS] = {100, 200, 400, 800, 1000};

const char* session_state_str(SessionState s) {
  switch (s) {
    case SessionState::IDLE: return "IDLE";
    case SessionState::ARMED: return "ARMED";
    case SessionState::RECORDING: return "RECORDING";
    case SessionState::PAUSED: return "PAUSED";
    case SessionState::STOPPED_WAITING_UPLOAD: return "STOPPED_WAITING_UPLOAD";
    case SessionState::COMPLETED: return "COMPLETED";
    case SessionState::RECOVERY: return "RECOVERY";
    case SessionState::ERROR: return "ERROR";
  }
  return "?";
}

void make_session_id(uint16_t dev_id, uint32_t boot_count, uint16_t n, char out[24]) {
  snprintf(out, 24, "S%04X_%06lu_%03u", dev_id, (unsigned long)(boot_count % 1000000u), (unsigned)(n % 1000u));
}

// ---------------------------------------------------------------- lifecycle
bool SessionLifecycle::arm(bool auto_enabled) {
  if (st_ == SessionState::IDLE && auto_enabled) { st_ = SessionState::ARMED; return true; }
  if (st_ == SessionState::ARMED && !auto_enabled) { st_ = SessionState::IDLE; return true; }
  return false;
}

bool SessionLifecycle::start(uint32_t now, StartReason r) {
  switch (st_) {
    case SessionState::IDLE: case SessionState::ARMED: case SessionState::STOPPED_WAITING_UPLOAD:
    case SessionState::COMPLETED: case SessionState::RECOVERY: case SessionState::ERROR:
      st_ = SessionState::RECORDING;
      reason_ = r;
      start_ms_ = seg_start_ms_ = now;
      active_acc_ = 0;
      return true;
    default:
      return false;  // never two simultaneous sessions
  }
}

bool SessionLifecycle::pause(uint32_t now) {
  if (st_ != SessionState::RECORDING) return false;
  active_acc_ += now - seg_start_ms_;
  st_ = SessionState::PAUSED;
  return true;
}

bool SessionLifecycle::resume(uint32_t now) {
  if (st_ != SessionState::PAUSED) return false;
  seg_start_ms_ = now;
  st_ = SessionState::RECORDING;
  return true;
}

bool SessionLifecycle::stop(uint32_t now) {
  if (st_ == SessionState::RECORDING) active_acc_ += now - seg_start_ms_;
  else if (st_ != SessionState::PAUSED) return false;
  last_wall_ = now - start_ms_;
  st_ = SessionState::STOPPED_WAITING_UPLOAD;
  return true;
}

bool SessionLifecycle::mark_uploaded() {
  if (st_ != SessionState::STOPPED_WAITING_UPLOAD) return false;
  st_ = SessionState::COMPLETED;
  return true;
}

uint32_t SessionLifecycle::active_ms(uint32_t now) const {
  if (st_ == SessionState::RECORDING) return active_acc_ + (now - seg_start_ms_);
  return active_acc_;
}

void SessionLifecycle::restore(uint32_t now, uint32_t prior_active_ms, StartReason r) {
  st_ = SessionState::RECORDING;
  reason_ = r;
  start_ms_ = now - prior_active_ms;
  seg_start_ms_ = now;
  active_acc_ = prior_active_ms;
}

// ---------------------------------------------------------------- metrics
void SessionMetricsCalc::reset(const Config& cfg) {
  cfg_ = cfg;
  m_ = SessionMetrics();
  have_prev_ = false;
  split_base_m_ = 0;
  split_base_ms_ = 0;
  hist_n_ = 0;
  line_init_ = false;
  lap_started_ = false;
  in_series_ = false;
  above_ms_ = 0;
}

static bool valid_fix(const GnssSample& s) {
  return s.gnss_fix_ok() && (s.fix_type == 3 || s.fix_type == 4) && !s.invalid_llh();
}

void SessionMetricsCalc::on_marker(uint32_t now) {
  m_.markers++;
  split_base_m_ = m_.distance_m;
  split_base_ms_ = now;
  for (int i = 0; i < AVO_N_SPLITS; i++) m_.split_ms[i] = 0;
}

void SessionMetricsCalc::on_gnss(const GnssSample& s, uint32_t now) {
  m_.gnss_samples++;
  bool ok = valid_fix(s);
  if (ok) m_.gnss_valid++;
  if (m_.gnss_samples == 1) split_base_ms_ = now;

  uint32_t dt = 0;
  if (have_prev_) {
    dt = now - prev_ms_;
    if (dt > 2000) dt = 0;  // gap: do not attribute time or distance
  }
  if (dt) {
    // time-in-quality accounting attributed to the previous epoch's solution
    if (!valid_fix(prev_)) m_.t_nofix_ms += dt;
    else if (prev_.carr_soln() == 2) m_.t_fix_ms += dt;
    else if (prev_.carr_soln() == 1) m_.t_float_ms += dt;
    else m_.t_gnss_ms += dt;
  }

  double v = s.gspeed_mm_s / 1000.0;
  bool speed_ok = ok && s.sacc_mm_s <= 1000;
  if (dt && speed_ok && valid_fix(prev_) && prev_.sacc_mm_s <= 1000) {
    double vm = (v + prev_.gspeed_mm_s / 1000.0) / 2.0;
    if (vm >= 0.2) m_.distance_m += vm * dt / 1000.0;  // stationary threshold: Doppler noise is not distance
  }
  if (ok && s.sacc_mm_s <= 500 && v > m_.max_speed_mps) m_.max_speed_mps = v;

  // acceleration over a ~1 s window of good speed samples
  if (speed_ok) {
    if (hist_n_ == 32) { memmove(speed_hist_, speed_hist_ + 1, 31 * sizeof(double)); memmove(speed_t_, speed_t_ + 1, 31 * sizeof(uint32_t)); hist_n_ = 31; }
    speed_hist_[hist_n_] = v; speed_t_[hist_n_] = now; hist_n_++;
    for (int i = hist_n_ - 2; i >= 0; i--) {  // newest sample at least 0.8 s old
      uint32_t w = now - speed_t_[i];
      if (w >= 800 && w <= 1500) {
        double a = (v - speed_hist_[i]) / (w / 1000.0);
        if (a > m_.max_accel_mps2) m_.max_accel_mps2 = a;
        if (-a > m_.max_decel_mps2) m_.max_decel_mps2 = -a;
        break;
      }
    }
  } else {
    hist_n_ = 0;
  }

  // splits
  double d = m_.distance_m - split_base_m_;
  for (int i = 0; i < AVO_N_SPLITS; i++)
    if (m_.split_ms[i] == 0 && d >= kSplitDistances[i]) m_.split_ms[i] = now - split_base_ms_;

  // virtual lines (crossing between consecutive valid positions)
  if (ok && have_prev_ && valid_fix(prev_) && dt) {
    for (int i = 0; i < 4; i++) {
      const VirtualLine& l = cfg_.lines[i];
      if (!l.enabled) continue;
      if (!line_init_) lf_[i].init(l.a_lat_e7, l.a_lon_e7);
      double ax, ay, bx, by, px, py, qx, qy;
      lf_[i].to_xy(l.a_lat_e7, l.a_lon_e7, &ax, &ay);
      lf_[i].to_xy(l.b_lat_e7, l.b_lon_e7, &bx, &by);
      lf_[i].to_xy(prev_.lat_e7, prev_.lon_e7, &px, &py);
      lf_[i].to_xy(s.lat_e7, s.lon_e7, &qx, &qy);
      if (crosses(ax, ay, bx, by, px, py, qx, qy)) {
        m_.line_cross[i]++;
        if (i == 0) {
          if (lap_started_) {
            uint32_t lap = now - lap_start_ms_;
            m_.laps++;
            m_.last_lap_ms = lap;
            if (m_.best_lap_ms == 0 || lap < m_.best_lap_ms) m_.best_lap_ms = lap;
          }
          lap_started_ = true;
          lap_start_ms_ = now;
        }
      }
    }
    line_init_ = true;
  }

  // work series
  if (speed_ok && v * 100.0 >= cfg_.series_speed_cms) {
    if (above_ms_ == 0) above_ms_ = now ? now : 1;
    if (!in_series_ && now - above_ms_ >= (uint32_t)cfg_.series_min_s * 1000u) {
      in_series_ = true;
      series_start_ms_ = above_ms_;
      m_.series++;
    }
  } else if (speed_ok) {
    if (in_series_) m_.series_total_ms += now - series_start_ms_;
    in_series_ = false;
    above_ms_ = 0;
  }

  prev_ = s;
  prev_ms_ = now;
  have_prev_ = true;
}

}  // namespace avo
