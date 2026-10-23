#include "avo_eq/motion.h"
#include "avo_eq/dsp.h"
#include <algorithm>
#include <cmath>
#include <map>

namespace avoeq {

const char* gait_name(Gait g) {
  switch (g) { case Gait::STOPPED: return "PARADO"; case Gait::WALK: return "PASO"; case Gait::TROT: return "TROTE";
    case Gait::CANTER_GALLOP: return "GALOPE"; case Gait::TRANSITION: return "TRANSICION"; case Gait::UNKNOWN: return "DESCONOCIDO";
    case Gait::INSUFFICIENT_DATA: return "DATOS_INSUFICIENTES"; }
  return "?";
}
const char* gait_code(Gait g) {
  switch (g) { case Gait::STOPPED: return "STOPPED"; case Gait::WALK: return "WALK"; case Gait::TROT: return "TROT";
    case Gait::CANTER_GALLOP: return "CANTER_GALLOP"; case Gait::TRANSITION: return "TRANSITION"; case Gait::UNKNOWN: return "UNKNOWN";
    case Gait::INSUFFICIENT_DATA: return "INSUFFICIENT_DATA"; }
  return "?";
}
const char* cadence_status_name(CadenceStatus s) {
  switch (s) { case CadenceStatus::VALID: return "VALIDA"; case CadenceStatus::WEAK_PERIODICITY: return "PERIODICIDAD_DEBIL";
    case CadenceStatus::AMBIGUOUS: return "AMBIGUA"; case CadenceStatus::UNCERTAIN: return "INCIERTA"; case CadenceStatus::INSUFFICIENT_DATA: return "DATOS_INSUFICIENTES"; }
  return "?";
}

std::vector<ImuSeries> build_imu_series(const Session& s, const ValidationReport& v) {
  std::map<uint8_t, std::vector<size_t>> by;
  for (size_t i = 0; i < s.imu.size(); i++) {
    uint32_t f = i < v.imu_flags.size() ? v.imu_flags[i] : 0;
    if (f & (IF_DUPLICATE | IF_TIME_BACKWARDS)) continue;     // never used, still kept in the session
    by[s.imu[i].imu_id].push_back(i);
  }
  std::vector<ImuSeries> out;
  for (auto& kv : by) {
    ImuSeries ser; ser.imu_id = kv.first;
    auto& idx = kv.second;
    std::stable_sort(idx.begin(), idx.end(), [&](size_t a, size_t b) { return s.imu[a].girth_us < s.imu[b].girth_us; });
    double hz = v.imu_nominal_hz[std::min<uint8_t>(kv.first, 2)];
    if (hz <= 0) continue;
    ser.fs = hz;
    double per_us = 1e6 / hz;
    ImuSeries::Piece cur;
    int64_t last = 0;
    for (size_t k = 0; k < idx.size(); k++) {
      const ImuSample& x = s.imu[idx[k]];
      uint32_t f = v.imu_flags[idx[k]];
      if (f & IF_SATURATED) ser.saturated++;
      bool gap = k && (double)(x.girth_us - last) > 1.5 * per_us;
      if (gap) {
        ser.missing += (uint32_t)std::lround((double)(x.girth_us - last) / per_us) - 1;
        if (cur.amag.size() > 1) ser.pieces.push_back(std::move(cur));
        cur = ImuSeries::Piece();
      }
      if (cur.amag.empty()) cur.t0 = (double)x.girth_us * 1e-6;
      cur.ax.push_back(x.ax); cur.ay.push_back(x.ay); cur.az.push_back(x.az);
      cur.gx.push_back(x.gx); cur.gy.push_back(x.gy); cur.gz.push_back(x.gz);
      cur.amag.push_back((float)std::sqrt((double)x.ax * x.ax + (double)x.ay * x.ay + (double)x.az * x.az));
      last = x.girth_us;
      ser.samples++;
    }
    if (cur.amag.size() > 1) ser.pieces.push_back(std::move(cur));
    out.push_back(std::move(ser));
  }
  return out;
}

// cycles of a band-passed window, delimited by peaks spaced about one period
static void window_regularity(const std::vector<double>& y, double fs, double period_s, CadenceWindow* w, std::vector<double>* intervals) {
  size_t per = (size_t)std::lround(period_s * fs);
  if (per < 4 || y.size() < 3 * per) return;
  std::vector<size_t> pk = dsp::find_peaks(y, 0.0, (size_t)(0.7 * per));
  std::sort(pk.begin(), pk.end());
  if (pk.size() < 3) return;
  std::vector<double> iv, amp, p2p;
  for (size_t i = 1; i < pk.size(); i++) {
    iv.push_back((double)(pk[i] - pk[i - 1]) / fs);
    double lo = y[pk[i - 1]];
    for (size_t k = pk[i - 1]; k <= pk[i]; k++) lo = std::min(lo, y[k]);
    p2p.push_back(std::max(y[pk[i - 1]], y[pk[i]]) - lo);
  }
  for (size_t p : pk) amp.push_back(y[p]);
  double mi = dsp::mean(iv), ma = dsp::mean(amp);
  w->interval_cv = mi > 0 ? dsp::stddev(iv) / mi : -1;
  w->amplitude_cv = ma != 0 ? std::fabs(dsp::stddev(amp) / ma) : -1;
  w->p2p = dsp::median(p2p);
  *intervals = iv;
  // template of one cycle (resampled to 64 points) and correlation of each cycle with it
  const size_t L = 64;
  std::vector<std::vector<double>> cyc;
  for (size_t i = 1; i < pk.size(); i++) {
    std::vector<double> c(L);
    size_t a = pk[i - 1], b = pk[i];
    for (size_t k = 0; k < L; k++) {
      double pos = a + (double)(b - a) * k / (L - 1);
      size_t i0 = (size_t)pos; double fr = pos - i0;
      c[k] = (i0 + 1 < y.size()) ? y[i0] * (1 - fr) + y[i0 + 1] * fr : y[i0];
    }
    cyc.push_back(c);
  }
  std::vector<double> tmpl(L, 0);
  for (auto& c : cyc) for (size_t k = 0; k < L; k++) tmpl[k] += c[k] / cyc.size();
  double cs = 0;
  for (auto& c : cyc) {
    double mc = dsp::mean(c), mt = dsp::mean(tmpl), num = 0, d1 = 0, d2 = 0;
    for (size_t k = 0; k < L; k++) { num += (c[k] - mc) * (tmpl[k] - mt); d1 += (c[k] - mc) * (c[k] - mc); d2 += (tmpl[k] - mt) * (tmpl[k] - mt); }
    cs += (d1 > 0 && d2 > 0) ? num / std::sqrt(d1 * d2) : 0;
  }
  w->cycle_corr = cs / cyc.size();
}

static double spectra_corr(const std::vector<double>& a, const std::vector<double>& b, double df, double f_lo, double f_hi) {
  size_t k0 = (size_t)std::ceil(f_lo / df), k1 = std::min(a.size(), b.size());
  k1 = std::min(k1, (size_t)(f_hi / df) + 1);
  if (k1 <= k0 + 2) return -1;
  std::vector<double> x(a.begin() + k0, a.begin() + k1), y(b.begin() + k0, b.begin() + k1);
  double mx = dsp::mean(x), my = dsp::mean(y), n = 0, dx = 0, dy = 0;
  for (size_t i = 0; i < x.size(); i++) { n += (x[i] - mx) * (y[i] - my); dx += (x[i] - mx) * (x[i] - mx); dy += (y[i] - my) * (y[i] - my); }
  return (dx > 0 && dy > 0) ? n / std::sqrt(dx * dy) : -1;
}

static void spectral_features(const std::vector<double>& w, const std::vector<double>* axes[3], double fs, double f0, const CadenceConfig& c, CadenceWindow* cw) {
  double df = 0;
  std::vector<double> p = dsp::power_spectrum(w, fs, &df, 4096);
  double hi = std::min(c.band_hi, fs * 0.45);
  double total = dsp::band_power(p, df, c.band_lo, hi);
  if (total <= 0) return;
  const double edges[5] = {0.4, 1.5, 3.0, 6.0, 10.0};
  for (int b = 0; b < 4; b++) cw->band_energy[b] = dsp::band_power(p, df, edges[b], std::min(edges[b + 1], hi)) / total;
  // dominant peak in the analysis band
  size_t k0 = (size_t)std::ceil(c.band_lo / df), k1 = std::min(p.size() - 1, (size_t)(hi / df));
  size_t kd = k0;
  for (size_t k = k0; k <= k1; k++) if (p[k] > p[kd]) kd = k;
  double off = (kd > 0 && kd + 1 < p.size()) ? dsp::parabolic_offset(p[kd - 1], p[kd], p[kd + 1]) : 0;
  cw->dominant_hz = (kd + off) * df;
  if (f0 > 0) {
    double hw = std::max(1.5 * df, 0.06 * f0);
    double p1 = dsp::band_power(p, df, f0 - hw, f0 + hw), sum = 0;
    for (int k = 1; k <= 4; k++) {
      double pk = dsp::band_power(p, df, k * f0 - hw, k * f0 + hw);
      sum += pk;
      cw->harmonic_ratio[k - 1] = p1 > 0 ? pk / p1 : -1;
    }
    cw->harmonic_energy = sum / total;
    // power at half the candidate frequency vs the noise floor (median bin power of the band)
    std::vector<double> band(p.begin() + k0, p.begin() + k1 + 1);
    double floor_bin = dsp::median(band);
    double nb = std::max(1.0, std::floor(2 * hw / df) + 1);
    if (floor_bin > 0 && f0 / 2 >= c.band_lo) cw->subharmonic_snr = dsp::band_power(p, df, f0 / 2 - hw, f0 / 2 + hw) / (floor_bin * nb);
    double k = cw->dominant_hz / f0;
    int kr = (int)std::lround(k);
    cw->dominant_harmonic = (kr >= 1 && kr <= 6 && std::fabs(k - kr) < 0.12) ? kr : 0;
  }
  // spectral stability: spectra of both halves of the window
  size_t h = w.size() / 2;
  if (h >= 16) {
    std::vector<double> a(w.begin(), w.begin() + h), b(w.begin() + h, w.begin() + 2 * h);
    double d1, d2;
    std::vector<double> pa = dsp::power_spectrum(a, fs, &d1, 4096), pb = dsp::power_spectrum(b, fs, &d2, 4096);
    cw->spectral_stability = spectra_corr(pa, pb, d1, c.band_lo, std::min(6.0, hi));
  }
  // energy distribution per axis (band-passed, orientation unknown: only relative within this sensor)
  double e[3] = {0, 0, 0}, et = 0;
  for (int i = 0; i < 3; i++) if (axes[i]) { double r = dsp::rms(*axes[i]); e[i] = r * r; et += e[i]; }
  if (et > 0) for (int i = 0; i < 3; i++) cw->axis_energy[i] = e[i] / et;
}

CadenceResult analyse_cadence(const ImuSeries& s, const CadenceConfig& c) {
  CadenceResult r; r.imu_id = s.imu_id; r.fs = s.fs;
  if (s.fs <= 0) return r;
  size_t W = (size_t)std::lround(c.window_s * s.fs), H = (size_t)std::max<long>(1, std::lround(c.hop_s * s.fs));
  double hi = std::min(c.band_hi, s.fs * 0.45);
  // ---- controlled interpolation: join pieces separated by short gaps into a derived working copy
  struct Work : ImuSeries::Piece { std::vector<uint8_t> interp; };
  std::vector<Work> work;
  for (const auto& p : s.pieces) {
    bool join = false;
    if (!work.empty()) {
      Work& w = work.back();
      double t_end = w.t0 + (double)(w.amag.size() - 1) / s.fs;
      double gap = p.t0 - t_end;
      long missing = std::lround(gap * s.fs) - 1;
      if (gap > 0 && gap <= c.max_bridge_s + 0.5 / s.fs && missing >= 0) {
        join = true;
        std::vector<float>* dst[7] = {&w.ax, &w.ay, &w.az, &w.gx, &w.gy, &w.gz, &w.amag};
        const std::vector<float>* sr[7] = {&p.ax, &p.ay, &p.az, &p.gx, &p.gy, &p.gz, &p.amag};
        // linear ramp from the last real sample to the first real sample after the gap (derived copy only)
        for (int a = 0; a < 7; a++) {
          float v0 = dst[a]->back(), v1 = (*sr[a])[0];
          for (long k = 1; k <= missing; k++) dst[a]->push_back((float)(v0 + (v1 - v0) * (double)k / (double)(missing + 1)));
        }
        w.interp.insert(w.interp.end(), (size_t)missing, 1);
        for (int a = 0; a < 7; a++) dst[a]->insert(dst[a]->end(), sr[a]->begin(), sr[a]->end());
        w.interp.insert(w.interp.end(), p.amag.size(), 0);
      }
    }
    if (!join) { Work w; static_cast<ImuSeries::Piece&>(w) = p; w.interp.assign(p.amag.size(), 0); work.push_back(std::move(w)); }
  }
  for (const auto& p : work) {
    if (p.amag.size() < W) continue;
    std::vector<double> mag(p.amag.begin(), p.amag.end());
    std::vector<double> bp = dsp::bandpass_zero_phase(mag, c.band_lo, hi, s.fs);
    std::vector<double> axbp[3];
    const std::vector<float>* src[3] = {&p.ax, &p.ay, &p.az};
    for (int i = 0; i < 3; i++) { std::vector<double> v(src[i]->begin(), src[i]->end()); axbp[i] = dsp::bandpass_zero_phase(v, c.band_lo, hi, s.fs); }
    for (size_t st = 0; st + W <= bp.size(); st += H) {
      std::vector<double> w(bp.begin() + st, bp.begin() + st + W);
      std::vector<double> wa[3];
      for (int i = 0; i < 3; i++) wa[i].assign(axbp[i].begin() + st, axbp[i].begin() + st + W);
      const std::vector<double>* axes[3] = {&wa[0], &wa[1], &wa[2]};
      CadenceWindow cw;
      cw.t_mid = p.t0 + (st + W / 2.0) / s.fs;
      cw.rms = dsp::rms(w);
      size_t ni = 0; for (size_t k = st; k < st + W; k++) ni += p.interp[k];
      cw.interpolated_fraction = (double)ni / (double)W;
      if (cw.interpolated_fraction > c.max_interp_fraction) { cw.status = CadenceStatus::INSUFFICIENT_DATA; r.windows.push_back(cw); continue; }
      for (size_t k = st; k < st + W; k++) {
        float m = std::max(std::fabs(p.ax[k]), std::max(std::fabs(p.ay[k]), std::fabs(p.az[k])));
        if (m >= 32760.f) cw.saturated++;
      }
      dsp::Fundamental f = dsp::fundamental(w, s.fs, c.f_min, c.f_max, c.min_strength);
      if (f.freq_hz <= 0) {
        cw.status = CadenceStatus::WEAK_PERIODICITY;
        spectral_features(w, axes, s.fs, 0, c, &cw);
        r.windows.push_back(cw);
        continue;
      }
      cw.candidate_hz = f.freq_hz; cw.period_s = f.period_s; cw.strength = f.strength; cw.subharmonic = f.subharmonic_chosen;
      std::vector<double> iv;
      window_regularity(w, s.fs, f.period_s, &cw, &iv);
      std::vector<double> ac = dsp::autocorr(dsp::detrend_mean(w), (size_t)(f.period_s * s.fs) + 2);
      size_t full = (size_t)std::lround(f.period_s * s.fs), half = (size_t)std::lround(f.period_s * s.fs / 2);
      if (full < ac.size() && ac[full] > 0.05 && half > 0) cw.half_cycle_ratio = std::max(-1.0, std::min(1.0, ac[half] / ac[full]));
      spectral_features(w, axes, s.fs, f.freq_hz, c, &cw);
      // ---- uncertainty: dispersion of the cycle durations (σ of their mean) + lag resolution
      double sig = -1;
      if (iv.size() >= 2) {
        double T = dsp::mean(iv);
        cw.interval_freq_hz = T > 0 ? 1.0 / T : 0;
        double sT = dsp::stddev(iv) / std::sqrt((double)iv.size());
        double s_int = sT / (T * T);
        double s_res = f.freq_hz * f.freq_hz * (0.25 / s.fs);   // ±¼ sample on the lag after parabolic refinement
        sig = std::sqrt(s_int * s_int + s_res * s_res);
      }
      cw.uncertainty_hz = sig;
      if (sig < 0) cw.status = CadenceStatus::INSUFFICIENT_DATA;
      else if (cw.interval_freq_hz > 0 && std::fabs(cw.interval_freq_hz - f.freq_hz) > std::max(3 * sig, c.max_disagreement * f.freq_hz)) cw.status = CadenceStatus::AMBIGUOUS;
      else if (!f.subharmonic_chosen && cw.subharmonic_snr > 5) cw.status = CadenceStatus::AMBIGUOUS;   // cycle could be 2/f0
      else if (sig > c.max_rel_uncertainty * f.freq_hz) cw.status = CadenceStatus::UNCERTAIN;
      else cw.status = CadenceStatus::VALID;
      if (cw.status == CadenceStatus::VALID) { cw.freq_hz = f.freq_hz; cw.cpm = f.freq_hz * 60; }
      r.windows.push_back(cw);
    }
  }
  std::vector<double> f, fs_, cv, cc, ss, acv;
  for (auto& w : r.windows) if (w.status == CadenceStatus::VALID) {
    f.push_back(w.freq_hz); fs_.push_back(w.uncertainty_hz);
    if (w.interval_cv >= 0) cv.push_back(w.interval_cv);
    if (w.amplitude_cv >= 0) acv.push_back(w.amplitude_cv);
    if (w.cycle_corr >= 0) cc.push_back(w.cycle_corr);
    if (w.spectral_stability >= 0) ss.push_back(w.spectral_stability);
  }
  auto mk = [&](const char* n, const char* u, double v, const char* alg) {
    Metric m; m.name = n; m.unit = u; m.value = v; m.algorithm = alg; m.version = CADENCE_VERSION;
    m.samples_used = (uint32_t)f.size(); m.samples_excluded = (uint32_t)(r.windows.size() - f.size());
    m.quality = r.windows.empty() ? Quality::UNKNOWN : (f.size() * 2 >= r.windows.size() ? Quality::USABLE : Quality::POOR);
    m.warnings.push_back("frecuencia del ciclo de la señal de la cincha; no identifica apoyos de extremidades");
    if (m.samples_excluded) m.warnings.push_back(std::to_string(m.samples_excluded) + " ventanas sin cadencia fiable (no se promedian)");
    return m;
  };
  if (!f.empty()) {
    Metric m = mk("cadencia_media", "ciclos/min", dsp::mean(f) * 60, "autocorrelación en ventanas de 6 s, subarmónico y contraste con intervalos entre picos");
    // uncertainty of the session mean: spread between windows dominates (the cadence really changes)
    double s_between = dsp::stddev(f), s_within = dsp::mean(fs_);
    m.uncertainty = std::sqrt(s_between * s_between + s_within * s_within) * 60;
    r.metrics.push_back(m);
    r.metrics.push_back(mk("duracion_media_ciclo", "s", 1.0 / dsp::mean(f), "1 / frecuencia media"));
    r.metrics.push_back(mk("variabilidad_cadencia", "CV", dsp::mean(f) > 0 ? dsp::stddev(f) / dsp::mean(f) : 0, "desviación típica / media de la frecuencia por ventana"));
    r.metrics.push_back(mk("incertidumbre_media_ventana", "Hz", dsp::mean(fs_), "σ por ventana: dispersión de intervalos + resolución del retardo"));
  }
  if (!cv.empty()) r.metrics.push_back(mk("variabilidad_intervalos", "CV", dsp::median(cv), "mediana del CV de la duración de ciclo por ventana"));
  if (!acv.empty()) r.metrics.push_back(mk("regularidad_amplitud_cv", "CV", dsp::median(acv), "mediana del CV de la altura de pico por ventana"));
  if (!cc.empty()) r.metrics.push_back(mk("correlacion_entre_ciclos", "r", dsp::median(cc), "mediana de la correlación de cada ciclo con la plantilla de su ventana"));
  if (!ss.empty()) r.metrics.push_back(mk("estabilidad_espectral", "r", dsp::median(ss), "mediana de la correlación entre los espectros de ambas mitades de la ventana"));
  Metric mv = mk("ventanas_cadencia_validas", "n", (double)f.size(), "ventanas con estado VALIDA");
  mv.warnings.clear();
  r.metrics.push_back(mv);
  return r;
}

}  // namespace avoeq
