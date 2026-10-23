// Synthetic sessions with ANALYTIC ground truth (independent of the algorithms under test).
#pragma once
#include <cmath>
#include <random>
#include <vector>
#include "avo_eq/types.h"

namespace synth {
static const double PI = 3.14159265358979323846;
static const double M_PER_DEG_LAT = 111320.0;   // local flat-earth approximation used to build positions

struct Leg { double secs; double speed; double radius; };   // radius 0 = straight line
struct Truth { double distance = 0; std::vector<double> t, speed, heading_rate_deg_s, radius; };

// GNSS track at rate_hz along the legs. rtk(t) returns the carrSoln (0,1,2) for each time.
inline std::vector<avoeq::GnssEpoch> track(const std::vector<Leg>& legs, double rate_hz, Truth* tr,
                                           int (*rtk)(double) = nullptr, double speed_noise = 0.0, unsigned seed = 1) {
  std::mt19937 rng(seed); std::normal_distribution<double> nz(0, 1);
  std::vector<avoeq::GnssEpoch> out;
  double x = 0, y = 0, hdg = 0, t = 0, lat0 = 43.4, lon0 = -3.43;
  double dt = 1.0 / rate_hz;
  uint32_t itow0 = 345600000;
  for (const auto& L : legs) {
    int n = (int)std::lround(L.secs * rate_hz);
    for (int k = 0; k < n; k++) {
      avoeq::GnssEpoch e;
      e.itow_ms = itow0 + (uint32_t)std::lround(t * 1000);
      e.fix_type = 3; e.num_sv = 24;
      int cs = rtk ? rtk(t) : 2;
      e.flags = 0x01 | (cs ? 0x02 : 0) | (uint8_t)(cs << 6);
      e.lat_deg = lat0 + y / M_PER_DEG_LAT;
      e.lon_deg = lon0 + x / (M_PER_DEG_LAT * std::cos(lat0 * PI / 180));
      double v = L.speed + speed_noise * nz(rng);
      e.gspeed_ms = std::max(0.0, v); e.sacc_ms = std::max(0.05, speed_noise);
      e.veln_ms = v * std::cos(hdg); e.vele_ms = v * std::sin(hdg);
      e.hacc_m = cs == 2 ? 0.014 : cs == 1 ? 0.3 : 1.2; e.vacc_m = 2 * e.hacc_m;
      e.chest_us = (uint64_t)((t + 1000.0) * 1e6 + 8000);   // chest clock = GNSS + 1000 s, 8 ms latency
      e.nav_rate_hz = (uint8_t)rate_hz;
      out.push_back(e);
      if (tr) { tr->t.push_back(t); tr->speed.push_back(L.speed);
        tr->heading_rate_deg_s.push_back(L.radius > 0 ? L.speed / L.radius * 180 / PI : 0); tr->radius.push_back(L.radius); }
      // advance (exact for circles: constant turn rate)
      double w = L.radius > 0 ? L.speed / L.radius : 0;
      if (w > 0) {
        // heading h from north, clockwise: east dx = ∫ v sin h dt, north dy = ∫ v cos h dt (exact arc)
        double h1 = hdg + w * dt;
        x += L.speed / w * (std::cos(hdg) - std::cos(h1));
        y += L.speed / w * (std::sin(h1) - std::sin(hdg));
        hdg = h1;
      } else { x += L.speed * std::sin(hdg) * dt; y += L.speed * std::cos(hdg) * dt; }
      if (tr) tr->distance += L.speed * dt;
      t += dt;
    }
  }
  return out;
}

// One IMU whose |a| oscillates at stride frequency f(t) with two beats per stride (different shapes).
// girth clock = (t_gnss - 3.2 s) * (1 + drift) ; chest reception = gnss + 1000 s + latency (random, >= 3 ms)
struct ImuSpec { double fs = 200; double drift_ppm = 50; double offset_s = -3.2; double latency_mean_s = 0.012; double loss = 0.0; int batch = 20; };
inline std::vector<avoeq::ImuSample> imu(double secs, double (*freq)(double), const ImuSpec& sp, uint8_t id = 0, unsigned seed = 2,
                                          double noise = 30) {
  std::mt19937 rng(seed); std::normal_distribution<double> nz(0, 1); std::exponential_distribution<double> lat(1.0 / sp.latency_mean_s);
  std::uniform_real_distribution<double> u(0, 1);
  std::vector<avoeq::ImuSample> out;
  double phase = 0; uint32_t bseq = 0;
  size_t n = (size_t)(secs * sp.fs);
  for (size_t b0 = 0; b0 < n; b0 += sp.batch, bseq++) {
    bool lost = u(rng) < sp.loss;
    double t_last = (double)std::min(n - 1, b0 + sp.batch - 1) / sp.fs;
    double rx = t_last + 1000.0 + 0.003 + lat(rng);
    for (size_t i = b0; i < std::min(n, b0 + sp.batch); i++) {
      double t = i / sp.fs;
      double f = freq(t);
      phase += 2 * PI * f / sp.fs;
      double mag = 2048 + 600 * std::sin(2 * phase) + 280 * std::sin(phase + 0.6) + noise * nz(rng);
      if (lost) continue;
      avoeq::ImuSample s;
      s.imu_id = id; s.batch_seq = bseq; s.index = (uint16_t)(i - b0);
      s.girth_us = (int64_t)std::llround(((t + sp.offset_s) * (1 + sp.drift_ppm * 1e-6)) * 1e6);
      s.chest_us = (uint64_t)std::llround(rx * 1e6);
      s.az = (int16_t)std::lround(mag); s.ax = (int16_t)std::lround(0.1 * mag); s.ay = 0;
      out.push_back(s);
    }
  }
  return out;
}
// General track: speed v(t) (m/s) and turn rate w(t) (rad/s, + right), integrated with small sub-steps.
// keep(i) may drop epochs (irregular timestamps / losses). sacc is the speed accuracy reported by the "receiver".
inline std::vector<avoeq::GnssEpoch> track_fn(double secs, double rate_hz, double (*v)(double), double (*w)(double),
                                              double speed_noise = 0.0, double drop = 0.0, unsigned seed = 3, double* true_dist = nullptr) {
  std::mt19937 rng(seed); std::normal_distribution<double> nz(0, 1); std::uniform_real_distribution<double> u(0, 1);
  std::vector<avoeq::GnssEpoch> out;
  double x = 0, y = 0, hdg = 0, lat0 = 43.4, lon0 = -3.43, dist = 0;
  int n = (int)std::lround(secs * rate_hz);
  const int SUB = 20;
  for (int k = 0; k < n; k++) {
    double t = k / rate_hz;
    if (!(drop > 0 && u(rng) < drop)) {
      avoeq::GnssEpoch e;
      e.itow_ms = 345600000 + (uint32_t)std::lround(t * 1000);
      e.fix_type = 3; e.num_sv = 24; e.flags = 0x01 | 0x02 | (2 << 6);
      e.lat_deg = lat0 + y / M_PER_DEG_LAT;
      e.lon_deg = lon0 + x / (M_PER_DEG_LAT * std::cos(lat0 * PI / 180));
      double vv = v(t), vm = vv + speed_noise * nz(rng);
      double hn = hdg;
      e.gspeed_ms = std::max(0.0, vm); e.sacc_ms = std::max(0.05, speed_noise);
      e.veln_ms = (vv + speed_noise * nz(rng)) * std::cos(hn); e.vele_ms = (vv + speed_noise * nz(rng)) * std::sin(hn);
      e.hacc_m = 0.014; e.vacc_m = 0.03;
      e.chest_us = (uint64_t)((t + 1000.0) * 1e6 + 8000);
      e.nav_rate_hz = (uint8_t)rate_hz;
      out.push_back(e);
    }
    double h = 1.0 / rate_hz / SUB;
    for (int j = 0; j < SUB; j++) {
      double tt = t + j * h, vv = v(tt);
      x += vv * std::sin(hdg) * h; y += vv * std::cos(hdg) * h; dist += vv * h;
      hdg += w(tt) * h;
    }
  }
  if (true_dist) *true_dist = dist;
  return out;
}
// IMU with configurable shape: |a| = 2048 + a2(t)·sin(2φ) + a1(t)·sin(φ+0.6) + noise, φ' = 2π f(t).
// a2 dominant: two oscillations per stride (walk/trot); a1 dominant: one per stride (canter/gallop).
inline std::vector<avoeq::ImuSample> imu_shape(double secs, double (*freq)(double), double (*a1)(double), double (*a2)(double),
                                                const ImuSpec& sp, uint8_t id = 0, unsigned seed = 2, double noise = 30) {
  std::mt19937 rng(seed); std::normal_distribution<double> nz(0, 1); std::exponential_distribution<double> lat(1.0 / sp.latency_mean_s);
  std::uniform_real_distribution<double> u(0, 1);
  std::vector<avoeq::ImuSample> out;
  double phase = 0; uint32_t bseq = 0;
  size_t n = (size_t)(secs * sp.fs);
  for (size_t b0 = 0; b0 < n; b0 += sp.batch, bseq++) {
    bool lost = u(rng) < sp.loss;
    double t_last = (double)std::min(n - 1, b0 + sp.batch - 1) / sp.fs;
    double rx = t_last + 1000.0 + 0.003 + lat(rng);
    for (size_t i = b0; i < std::min(n, b0 + sp.batch); i++) {
      double t = i / sp.fs;
      phase += 2 * PI * freq(t) / sp.fs;
      double mag = 2048 + a2(t) * std::sin(2 * phase) + a1(t) * std::sin(phase + 0.6) + noise * nz(rng);
      double lateral = 0.3 * a1(t) * std::sin(phase + 1.1) + 0.5 * noise * nz(rng);
      if (lost) continue;
      avoeq::ImuSample s;
      s.imu_id = id; s.batch_seq = bseq; s.index = (uint16_t)(i - b0);
      s.girth_us = (int64_t)std::llround(((t + sp.offset_s) * (1 + sp.drift_ppm * 1e-6)) * 1e6);
      s.chest_us = (uint64_t)std::llround(rx * 1e6);
      s.az = (int16_t)std::lround(std::max(-32768.0, std::min(32767.0, mag)));
      s.ax = (int16_t)std::lround(0.1 * mag); s.ay = (int16_t)std::lround(lateral);
      out.push_back(s);
    }
  }
  return out;
}
// Two beats per stride as Gaussian pulses on az (gravity axis): beat 1 amplitude A at phase 0, beat 2 amplitude B
// at phase `frac` of the stride. Optional delay (s) of the whole signal and phase jitter (irregular movement).
struct Beats { double f = 1.45, A = 900, B = 900, frac = 0.5, width = 0.06, delay_s = 0, jitter = 0, noise = 20; };
inline std::vector<avoeq::ImuSample> imu_beats(double secs, const Beats& bt, const ImuSpec& sp, uint8_t id, unsigned seed = 9) {
  std::mt19937 rng(seed); std::normal_distribution<double> nz(0, 1); std::exponential_distribution<double> lat(1.0 / sp.latency_mean_s);
  std::vector<avoeq::ImuSample> out;
  size_t n = (size_t)(secs * sp.fs);
  std::vector<double> starts; double t = -1;
  while (t < secs + 2) { starts.push_back(t); t += (1.0 / bt.f) * (1 + bt.jitter * nz(rng)); }
  uint32_t bseq = 0;
  for (size_t b0 = 0; b0 < n; b0 += sp.batch, bseq++) {
    double t_last = (double)std::min(n - 1, b0 + sp.batch - 1) / sp.fs;
    double rx = t_last + 1000.0 + 0.003 + lat(rng);
    for (size_t i = b0; i < std::min(n, b0 + sp.batch); i++) {
      double tt = i / sp.fs - bt.delay_s, v = 0;
      for (size_t k = 0; k + 1 < starts.size(); k++) {
        double T = starts[k + 1] - starts[k];
        if (tt < starts[k] - 1 || tt > starts[k + 1] + 1) continue;
        double d1 = tt - starts[k], d2 = tt - (starts[k] + bt.frac * T);
        v += bt.A * std::exp(-0.5 * d1 * d1 / (bt.width * bt.width)) + bt.B * std::exp(-0.5 * d2 * d2 / (bt.width * bt.width));
      }
      avoeq::ImuSample s;
      s.imu_id = id; s.batch_seq = bseq; s.index = (uint16_t)(i - b0);
      s.girth_us = (int64_t)std::llround(((i / sp.fs + sp.offset_s) * (1 + sp.drift_ppm * 1e-6)) * 1e6);
      s.chest_us = (uint64_t)std::llround(rx * 1e6);
      s.az = (int16_t)std::lround(std::max(-32768.0, std::min(32767.0, 2048 + v + bt.noise * nz(rng))));
      s.ax = (int16_t)std::lround(0.15 * v + bt.noise * nz(rng)); s.ay = (int16_t)std::lround(0.05 * v + bt.noise * nz(rng));
      out.push_back(s);
    }
  }
  return out;
}
}  // namespace synth
