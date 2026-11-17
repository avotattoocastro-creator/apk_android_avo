#include "avo_eq/symmetry.h"
#include "avo_eq/dsp.h"
#include <algorithm>
#include <cmath>
#include <map>

namespace avoeq {

namespace {
struct WinSym {
  uint8_t imu; double t_imu, t_gnss = NAN, sigma_t = NAN, period; Gait gait = Gait::UNKNOWN;
  std::vector<double> bp;                      // band-passed |a| (for the inter-sensor lag)
  double amp = NAN, timing = NAN, half = NAN, vert = NAN, hratio = NAN, rms = NAN;
  uint32_t strides = 0;
};

Spread spread(std::vector<double> v, double min_sign, int min_n) {
  Spread s; s.n = (uint32_t)v.size();
  if (v.empty()) return s;
  std::sort(v.begin(), v.end());
  s.median = dsp::median(v);
  auto q = [&](double p) { double pos = p * (v.size() - 1); size_t i = (size_t)pos; double f = pos - i; return i + 1 < v.size() ? v[i] * (1 - f) + v[i + 1] * f : v[i]; };
  s.iqr = q(0.75) - q(0.25);
  size_t pos = 0, neg = 0; for (double x : v) { if (x > 0) pos++; else if (x < 0) neg++; }
  s.sign_consistency = (double)std::max(pos, neg) / v.size();
  double se = (s.iqr / 1.349) / std::sqrt((double)v.size());
  s.reproducible = (int)v.size() >= min_n && s.sign_consistency >= min_sign && std::fabs(s.median) > 2 * se;
  return s;
}

double corr(const std::vector<double>& a, const std::vector<double>& b) {
  double ma = dsp::mean(a), mb = dsp::mean(b), n = 0, da = 0, db = 0;
  for (size_t i = 0; i < a.size() && i < b.size(); i++) { n += (a[i] - ma) * (b[i] - mb); da += (a[i] - ma) * (a[i] - ma); db += (b[i] - mb) * (b[i] - mb); }
  return (da > 0 && db > 0) ? n / std::sqrt(da * db) : NAN;
}

std::vector<double> resample(const std::vector<double>& y, size_t a, size_t b, size_t L) {
  std::vector<double> c(L);
  for (size_t k = 0; k < L; k++) {
    double pos = a + (double)(b - a) * k / (L - 1);
    size_t i0 = (size_t)pos; double fr = pos - i0;
    c[k] = (i0 + 1 < y.size()) ? y[i0] * (1 - fr) + y[i0 + 1] * fr : y[i0];
  }
  return c;
}
}  // namespace

SymmetryResult analyse_symmetry(const std::vector<ImuSeries>& imu, const std::vector<CadenceResult>& cad, const ClockMap girth_to_gnss[3],
                                const GaitResult* gait, const CadenceConfig& cc, const SymmetryConfig& c) {
  SymmetryResult r;
  r.controls.push_back({"CALIBRACION", c.sensors_calibrated ? "OK" : "AVISO",
                        c.sensors_calibrated ? "sensores declarados calibrados" : "IMU sin calibrar: solo cocientes dentro de un mismo sensor; amplitudes entre sensores bloqueadas"});
  r.controls.push_back({"ORIENTACION", "AVISO", "orientación de las IMU desconocida: eje vertical estimado por la gravedad media; ejes horizontales sin identificar (lateral / longitudinal)"});
  if (imu.empty()) { r.controls.push_back({"DATOS", "BLOQUEA", "SIN DATOS DE CINCHA"}); r.notes.push_back("no hay datos de la cincha"); return r; }
  std::vector<WinSym> ws;
  for (const auto& cr : cad) {
    const ImuSeries* ser = nullptr;
    for (auto& s : imu) if (s.imu_id == cr.imu_id) ser = &s;
    if (!ser || ser->fs <= 0) continue;
    size_t W = (size_t)std::lround(cc.window_s * ser->fs);
    double hi = std::min(cc.band_hi, ser->fs * 0.45);
    for (const auto& w : cr.windows) {
      if (w.status != CadenceStatus::VALID) { r.excluded_status++; continue; }
      if (w.saturated > c.max_saturated_frac * W) { r.excluded_saturated++; continue; }
      if (w.cycle_corr < c.min_cycle_corr) { r.excluded_irregular++; continue; }
      if (w.interpolated_fraction > 0) { r.excluded_status++; continue; }
      // window samples from the raw piece (no interpolated data)
      double t_start = w.t_mid - cc.window_s / 2;
      const ImuSeries::Piece* pc = nullptr; size_t st = 0;
      for (auto& p : ser->pieces) {
        long k = std::lround((t_start - p.t0) * ser->fs);
        if (k >= 0 && (size_t)k + W <= p.amag.size()) { pc = &p; st = (size_t)k; break; }
      }
      if (!pc) { r.excluded_status++; continue; }
      WinSym x; x.imu = cr.imu_id; x.t_imu = w.t_mid; x.period = 1.0 / w.freq_hz;
      double tg, sg;
      if (girth_to_gnss[std::min<uint8_t>(cr.imu_id, 2)].map(w.t_mid, &tg, &sg)) {
        x.t_gnss = tg; x.sigma_t = sg;
        if (gait) for (auto& s : gait->segments) if (tg >= s.t0 && tg < s.t1) x.gait = s.gait;
      }
      std::vector<double> mag(pc->amag.begin() + st, pc->amag.begin() + st + W);
      x.bp = dsp::bandpass_zero_phase(mag, cc.band_lo, hi, ser->fs);
      x.rms = dsp::rms(x.bp);
      // axes: gravity (raw mean) gives the estimated vertical; band energy per axis
      const std::vector<float>* ax[3] = {&pc->ax, &pc->ay, &pc->az};
      double mean_abs[3], energy[3];
      for (int i = 0; i < 3; i++) {
        std::vector<double> v(ax[i]->begin() + st, ax[i]->begin() + st + W);
        mean_abs[i] = std::fabs(dsp::mean(v));
        double e = dsp::rms(dsp::bandpass_zero_phase(v, cc.band_lo, hi, ser->fs)); energy[i] = e * e;
      }
      int vert = (int)(std::max_element(mean_abs, mean_abs + 3) - mean_abs);
      double et = energy[0] + energy[1] + energy[2];
      int h1 = (vert + 1) % 3, h2 = (vert + 2) % 3;
      if (et > 0) x.vert = energy[vert] / et;
      if (energy[h2] > 0) x.hratio = energy[h1] / energy[h2];
      // strides: peaks one period apart; second beat = maximum between 25 % and 75 % of the stride
      size_t per = (size_t)std::lround(x.period * ser->fs);
      std::vector<size_t> pk = dsp::find_peaks(x.bp, 0.0, (size_t)(0.7 * per));
      std::sort(pk.begin(), pk.end());
      std::vector<double> amp, tim, half;
      for (size_t k = 1; k < pk.size(); k++) {
        size_t a = pk[k - 1], b = pk[k];
        if (b - a < per / 2 || b - a > 2 * per) continue;
        size_t lo = a + (b - a) / 4, hi2 = a + 3 * (b - a) / 4, m = lo;
        for (size_t i = lo; i <= hi2; i++) if (x.bp[i] > x.bp[m]) m = i;
        if (m == lo || m == hi2) continue;   // no clear second beat
        // peak-to-trough amplitudes (independent of the baseline left by the band-pass)
        double tr1 = x.bp[a], tr2 = x.bp[m];
        size_t from = (k >= 2) ? pk[k - 2] + (a - pk[k - 2]) / 2 : (a > per / 2 ? a - per / 2 : 0);
        for (size_t i = from; i < a; i++) tr1 = std::min(tr1, x.bp[i]);
        for (size_t i = a; i < m; i++) tr2 = std::min(tr2, x.bp[i]);
        double A1 = x.bp[a] - tr1, A2 = x.bp[m] - tr2;
        if (A1 <= 0 || A2 <= 0) continue;
        amp.push_back(std::log(A1 / A2));
        double d1 = (double)(m - a), d2 = (double)(b - m);
        tim.push_back((d1 - d2) / (d1 + d2));
        half.push_back(corr(resample(x.bp, a, m, 32), resample(x.bp, m, b, 32)));
      }
      if (amp.size() < 2) { r.excluded_status++; continue; }
      x.strides = (uint32_t)amp.size();
      x.amp = dsp::median(amp); x.timing = dsp::median(tim); x.half = dsp::median(half);
      ws.push_back(std::move(x));
    }
  }
  r.windows_used = (uint32_t)ws.size();
  if (r.excluded_saturated) r.controls.push_back({"SATURACION", "BLOQUEA", std::to_string(r.excluded_saturated) + " ventanas con saturación excluidas"});
  else r.controls.push_back({"SATURACION", "OK", "sin ventanas saturadas"});
  r.controls.push_back({"MOVIMIENTO_IRREGULAR", r.excluded_irregular ? "AVISO" : "OK", std::to_string(r.excluded_irregular) + " ventanas irregulares excluidas (correlación entre ciclos < " + std::to_string(c.min_cycle_corr).substr(0, 4) + ")"});
  // groups per IMU and gait (+ TODOS)
  std::map<std::pair<int, std::string>, std::vector<const WinSym*>> grp;
  for (auto& x : ws) { grp[{x.imu, gait_name(x.gait)}].push_back(&x); grp[{x.imu, "TODOS"}].push_back(&x); }
  for (auto& kv : grp) {
    SymmetryGroup g; g.imu_id = (uint8_t)kv.first.first; g.gait = kv.first.second; g.windows = (uint32_t)kv.second.size();
    std::vector<double> a, t, h, v, hr;
    for (auto* x : kv.second) {
      g.strides += x->strides;
      a.push_back(x->amp); t.push_back(x->timing); h.push_back(x->half);
      if (!std::isnan(x->vert)) v.push_back(x->vert);
      if (!std::isnan(x->hratio)) hr.push_back(x->hratio);
    }
    g.amp_log_ratio = spread(a, c.min_sign_consistency, c.min_windows);
    g.timing_asym = spread(t, c.min_sign_consistency, c.min_windows);
    g.half_similarity = spread(h, 2, c.min_windows);          // a similarity has no sign: never "reproducible difference"
    g.vertical_energy = spread(v, 2, c.min_windows);
    g.horizontal_ratio = spread(hr, 2, c.min_windows);
    r.groups.push_back(g);
    if ((int)g.windows >= c.min_windows) r.conclusions_allowed = true;
  }
  // inter-sensor (left / right girth IMUs 1 and 2)
  std::map<std::string, std::vector<std::pair<const WinSym*, const WinSym*>>> pairs;
  bool have1 = false, have2 = false;
  for (auto& x : ws) { have1 |= x.imu == 1; have2 |= x.imu == 2; }
  if (have1 && have2) {
    std::string blocked;
    for (auto& x : ws) if (x.imu == 1) {
      for (auto& y : ws) if (y.imu == 2 && !std::isnan(x.t_gnss) && !std::isnan(y.t_gnss) && std::fabs(x.t_gnss - y.t_gnss) < 0.5) {
        if (x.sigma_t > c.max_sync_sigma_s || y.sigma_t > c.max_sync_sigma_s) { blocked = "sincronía insuficiente entre sensores"; continue; }
        pairs[gait_name(x.gait)].push_back({&x, &y}); pairs["TODOS"].push_back({&x, &y});
      }
    }
    if (pairs.empty()) {
      InterSensor is; is.gait = "TODOS"; is.state = "BLOQUEA"; is.reason = blocked.empty() ? "sin ventanas simultáneas de ambos sensores" : blocked;
      r.inter.push_back(is);
    }
    for (auto& kv : pairs) {
      InterSensor is; is.gait = kv.first; is.state = "OK";
      std::vector<double> lag, frac, ratio;
      for (auto& p : kv.second) {
        const auto& A = p.first->bp; const auto& B = p.second->bp;
        double fs = (double)A.size() / cc.window_s;
        long maxlag = std::lround(0.5 * p.first->period * fs), best = 0; double bv = -2;
        double dt = p.second->t_gnss - p.first->t_gnss;   // window centres differ slightly: correct for it
        for (long L = -maxlag; L <= maxlag; L++) {
          double n = 0, da = 0, db = 0;
          for (size_t i = 0; i < A.size(); i++) { long j = (long)i + L; if (j < 0 || j >= (long)B.size()) continue; n += A[i] * B[(size_t)j]; da += A[i] * A[i]; db += B[(size_t)j] * B[(size_t)j]; }
          double cr = (da > 0 && db > 0) ? n / std::sqrt(da * db) : -2;
          if (cr > bv) { bv = cr; best = L; }
        }
        double l = (double)best / fs + dt;   // b lags a by l seconds
        lag.push_back(l); frac.push_back(l / p.first->period);
        if (c.sensors_calibrated && p.first->rms > 0) ratio.push_back(p.second->rms / p.first->rms);
      }
      is.lag_s = spread(lag, c.min_sign_consistency, c.min_windows);
      is.lag_cycle_fraction = spread(frac, c.min_sign_consistency, c.min_windows);
      if (c.sensors_calibrated) is.rms_ratio = spread(ratio, 2, c.min_windows);
      else is.reason = "comparación de amplitudes entre sensores bloqueada: sin calibración";
      r.inter.push_back(is);
    }
    r.controls.push_back({"TIEMPO_ENTRE_SENSORES", pairs.empty() ? "BLOQUEA" : "OK", pairs.empty() ? "no se pueden comparar tiempos entre sensores" : "incertidumbre de sincronía dentro del límite"});
  }
  if (!r.conclusions_allowed) r.notes.push_back("datos insuficientes para cualquier afirmación (mínimo " + std::to_string(c.min_windows) + " ventanas regulares por aire)");
  r.notes.push_back("resultado exploratorio de la señal de la cincha; describe diferencias de la señal, no del estado del caballo");
  return r;
}

}  // namespace avoeq
