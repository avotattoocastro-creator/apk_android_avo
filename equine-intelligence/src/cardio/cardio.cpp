// AVO Cardio 1.0.0: ECG de la cincha PROTOTIPO 0.5.x → latidos, RR, FC por épocas, fases, V200, VHRmax, recuperación
// y candidatos a ectopia. Descripción y fuentes en include/avo_eq/cardio.h y docs/algoritmos/15_ECG_V200.md.
#include "avo_eq/cardio.h"
#include <algorithm>
#include <cstdio>
#include <sstream>
#include "avo_eq/dsp.h"
#include "avo_eq/session_sync.h"

namespace avoeq {

namespace {
const double kNaN = NAN;

double median_v(std::vector<double> x) {
  if (x.empty()) return kNaN;
  size_t m = x.size() / 2;
  std::nth_element(x.begin(), x.begin() + m, x.end());
  double hi = x[m];
  if (x.size() % 2) return hi;
  double lo = *std::max_element(x.begin(), x.begin() + m);
  return 0.5 * (lo + hi);
}

double quantile_v(std::vector<double> x, double q) {
  if (x.empty()) return kNaN;
  size_t k = (size_t)std::min<double>((double)x.size() - 1, std::max(0.0, q * (double)(x.size() - 1)));
  std::nth_element(x.begin(), x.begin() + k, x.end());
  return x[k];
}

// Solape de [a, b) con una lista de intervalos ordenados (pueden solaparse entre sí; se suman sin unir: la lista que
// se pasa aquí se construye sin solapes).
double overlap(const std::vector<std::pair<double, double>>& iv, double a, double b) {
  double s = 0;
  for (const auto& p : iv) {
    if (p.second <= a) continue;
    if (p.first >= b) break;
    s += std::min(b, p.second) - std::max(a, p.first);
  }
  return s;
}

std::vector<std::pair<double, double>> merge_intervals(std::vector<std::pair<double, double>> v) {
  std::sort(v.begin(), v.end());
  std::vector<std::pair<double, double>> out;
  for (const auto& p : v) {
    if (!(p.second > p.first)) continue;
    if (!out.empty() && p.first <= out.back().second) out.back().second = std::max(out.back().second, p.second);
    else out.push_back(p);
  }
  return out;
}

// Media de y en [a, b] sobre una serie temporal ordenada; *coverage = fracción de muestras finitas.
double window_mean(const std::vector<double>& t, const std::vector<double>& y, double a, double b, double* coverage = nullptr) {
  auto lo = std::lower_bound(t.begin(), t.end(), a);
  double s = 0; int n = 0, all = 0;
  for (auto it = lo; it != t.end() && *it <= b; ++it) {
    size_t i = (size_t)(it - t.begin());
    all++;
    if (std::isfinite(y[i])) { s += y[i]; n++; }
  }
  if (coverage) *coverage = all ? (double)n / all : 0.0;
  return n ? s / n : kNaN;
}

std::string num(double v) {
  if (std::isnan(v) || std::isinf(v)) return "null";
  char b[40]; snprintf(b, sizeof(b), "%.10g", v); return b;
}
std::string esc(const std::string& s) {
  std::string o;
  for (char ch : s) {
    if (ch == '"' || ch == '\\') { o += '\\'; o += ch; }
    else if (ch == '\n') o += "\\n";
    else if ((unsigned char)ch < 0x20) { char b[8]; snprintf(b, sizeof(b), "\\u%04x", ch); o += b; }
    else o += ch;
  }
  return o;
}
}  // namespace

const char* cardio_phase_name(int p) {
  static const char* n[PH_COUNT] = {"CALENTAMIENTO", "MAXIMA", "RECUPERACION_0_2MIN", "RECUPERACION_TARDIA"};
  return p >= 0 && p < PH_COUNT ? n[p] : "SIN_FASE";
}

// ------------------------------------------------------------------ detector anclado en S
std::vector<EcgBeat> detect_beats(const std::vector<double>& mv_in, double fs, const CardioConfig& c, int* polarity_out) {
  std::vector<EcgBeat> beats;
  const size_t n = mv_in.size();
  if (polarity_out) *polarity_out = 0;
  if (n < (size_t)(fs * 1.0) || !(fs > 0)) return beats;
  std::vector<double> x(mv_in);
  for (auto& v : x) if (!std::isfinite(v)) v = 0;
  std::vector<double> bp = dsp::bandpass_zero_phase(dsp::detrend_mean(x), c.band_lo_hz, c.band_hi_hz, fs);
  // energía de pendiente: derivada centrada al cuadrado, media móvil centrada de energy_window_s
  std::vector<double> d2(n, 0.0), e(n, 0.0);
  for (size_t i = 1; i + 1 < n; i++) { double d = (bp[i + 1] - bp[i - 1]) * fs * 0.5; d2[i] = d * d; }
  const size_t w = std::max<size_t>(1, (size_t)std::lround(c.energy_window_s * fs));
  {
    double acc = 0; size_t h = w / 2;
    std::vector<double> cs(n + 1, 0.0);
    for (size_t i = 0; i < n; i++) { acc += d2[i]; cs[i + 1] = acc; }
    for (size_t i = 0; i < n; i++) {
      size_t a = i >= h ? i - h : 0, b = std::min(n, i + h + 1);
      e[i] = (cs[b] - cs[a]) / (double)(b - a);
    }
  }
  // máximos locales de la energía separados ≥ 80 ms (barrido lineal: el mayor de cada grupo)
  const size_t sep = (size_t)std::lround(0.08 * fs);
  std::vector<size_t> pk;
  for (size_t i = 1; i + 1 < n; i++) {
    if (!(e[i] > e[i - 1] && e[i] >= e[i + 1])) continue;
    if (!pk.empty() && i - pk.back() < sep) { if (e[i] > e[pk.back()]) pk.back() = i; continue; }
    pk.push_back(i);
  }
  if (pk.empty()) return beats;
  const size_t sw = (size_t)std::lround(c.search_s * fs);
  auto extreme = [&](size_t p, int pol, size_t* at) {
    size_t a = p > sw ? p - sw : 0, b = std::min(n - 1, p + sw);
    double best = -1e300; size_t bi = p;
    for (size_t i = a; i <= b; i++) { double v = pol * bp[i]; if (v > best) { best = v; bi = i; } }
    *at = bi; return best;
  };
  // polaridad de la S: signo con la mayor deflexión mediana en los picos de energía altos
  double thr_global = c.threshold_fraction * quantile_v(e, 0.98);
  std::vector<double> pos, neg;
  for (size_t p : pk) if (e[p] >= thr_global) { size_t at; pos.push_back(extreme(p, +1, &at)); neg.push_back(extreme(p, -1, &at)); }
  int pol = median_v(neg) > median_v(pos) ? -1 : +1;
  if (polarity_out) *polarity_out = pol;

  auto local_thr = [&](size_t center) {
    size_t span = (size_t)std::lround(3.0 * fs);
    size_t a = center > span / 3 ? center - span / 3 : 0, b = std::min(n, a + span);
    std::vector<double> sub(e.begin() + a, e.begin() + b);
    return c.threshold_fraction * quantile_v(sub, 0.98);
  };
  double thr = local_thr(0);
  std::vector<double> hist_e, hist_rr;
  double last_t = -1e9, last_e = 0;
  for (size_t p : pk) {
    double tp = p / fs;
    double rr_med = hist_rr.size() >= 3 ? median_v(hist_rr) : kNaN;
    double reset_after = std::max(c.no_beat_reset_s, std::isfinite(rr_med) ? 1.6 * rr_med : 0.0);
    if (tp - last_t > reset_after) {      // sin ceguera: tras 2 s (o 1,6 RR) sin latidos el umbral se recalcula aquí
      double lt = local_thr(p);
      if (std::isfinite(lt)) thr = std::min(thr, lt);
      hist_e.clear();
    }
    if (!(e[p] >= thr)) continue;
    double dt = tp - last_t;
    if (dt < c.refractory_s) continue;
    size_t at;
    double amp = extreme(p, pol, &at);
    if (!(amp > 0)) continue;                                      // sin S de la polaridad dominante
    size_t at_op; double amp_op = extreme(p, -pol, &at_op);
    bool t_like = std::isfinite(rr_med) && dt < c.t_wave_rr_fraction * rr_med &&
                  (e[p] < c.t_wave_energy_fraction * last_e || amp_op > amp);
    if (t_like) continue;                                          // onda T (o artefacto lento) dentro del RR
    double off = (at > 0 && at + 1 < n) ? dsp::parabolic_offset(pol * bp[at - 1], pol * bp[at], pol * bp[at + 1]) : 0.0;
    EcgBeat b;
    b.t_girth = (at + off) / fs;
    b.amp_mv = amp;
    if (!beats.empty()) {
      double rr = b.t_girth - beats.back().t_girth;
      if (rr < c.refractory_s) continue;
      hist_rr.push_back(rr); if (hist_rr.size() > 8) hist_rr.erase(hist_rr.begin());
    }
    beats.push_back(b);
    double med_e = hist_e.empty() ? e[p] : median_v(hist_e);
    hist_e.push_back(std::min(e[p], 3.0 * med_e));                // un artefacto enorme no ciega al detector
    if (hist_e.size() > 8) hist_e.erase(hist_e.begin());
    thr = c.threshold_fraction * median_v(hist_e);
    last_t = b.t_girth; last_e = e[p];
  }
  return beats;
}

// ------------------------------------------------------------------ análisis sobre la serie RR
void analyse_rr(std::vector<EcgBeat> beats, const std::vector<double>& gt, const std::vector<double>& gv,
                const std::vector<std::pair<double, double>>& gaps_in, double t_begin, double t_end, const CardioConfig& c,
                CardioResult* r) {
  std::sort(beats.begin(), beats.end(), [](const EcgBeat& a, const EcgBeat& b) { return a.t < b.t; });
  std::vector<std::pair<double, double>> gaps = merge_intervals(gaps_in);
  const bool have_speed = !gt.empty() && gt.size() == gv.size();
  // 1. RR válidos
  for (size_t i = 1; i < beats.size(); i++) {
    double rr = beats[i].t - beats[i - 1].t;
    beats[i].rr = rr;
    beats[i].rr_valid = rr >= c.rr_min_s && rr <= c.rr_max_s && overlap(gaps, beats[i - 1].t, beats[i].t) <= 0;
  }
  for (size_t i = 1; i < beats.size(); i++) {
    if (!beats[i].rr_valid) continue;
    std::vector<double> nb;
    for (size_t j = (i > 4 ? i - 4 : 1); j < std::min(beats.size(), i + 5); j++) if (j != i && beats[j].rr_valid) nb.push_back(beats[j].rr);
    if (nb.size() < 3) continue;
    double m = median_v(nb);
    if (beats[i].rr < c.rr_local_lo * m || beats[i].rr > c.rr_local_hi * m) beats[i].rr_valid = false;
  }
  // intervalos de artefacto: huecos + RR no válidos
  std::vector<std::pair<double, double>> art = gaps;
  for (size_t i = 1; i < beats.size(); i++) if (!beats[i].rr_valid) art.push_back({beats[i - 1].t, beats[i].t});
  if (!beats.empty()) { art.push_back({t_begin, beats.front().t}); art.push_back({beats.back().t, t_end}); }
  art = merge_intervals(art);
  // los intervalos de borde no deben contar como artefacto si son cortos (< 1 RR máximo)
  for (auto& p : art) {
    if (!beats.empty() && p.second == beats.front().t && p.first == t_begin && p.second - p.first <= c.rr_max_s) p.second = p.first;
    if (!beats.empty() && p.first == beats.back().t && p.second == t_end && p.second - p.first <= c.rr_max_s) p.first = p.second;
  }
  art = merge_intervals(art);
  const double span = std::max(0.0, t_end - t_begin);
  r->duration_s = span;
  r->artifact = span > 0 ? std::min(1.0, overlap(art, t_begin, t_end) / span) : kNaN;

  // 2. ectopia: candidatos a revisar
  {
    std::vector<double> ref;   // RR válidos y no candidatos recientes
    for (size_t i = 1; i < beats.size();) {
      if (!beats[i].rr_valid) { ref.clear(); i++; continue; }
      if ((int)ref.size() >= c.premature_min_ref) {
        double m = median_v(std::vector<double>(ref.end() - std::min<size_t>(ref.size(), (size_t)c.premature_ref_beats), ref.end()));
        double hr_ref = 60.0 / m;
        double thr = (hr_ref > 100 ? c.premature_pct : hr_ref >= 60 ? c.premature_pct_60_100 : c.premature_pct_below_60) / 100.0;
        auto is_short = [&](size_t k) { return k < beats.size() && beats[k].rr_valid && 1.0 - beats[k].rr / m >= thr && 1.0 - beats[k].rr / m < 0.5; };
        if (is_short(i)) {
          size_t L = 0;
          while ((int)L < c.premature_return_beats && is_short(i + L)) L++;
          size_t ret = i + L;
          bool returns = ret < beats.size() && beats[ret].rr_valid && beats[ret].rr >= (1.0 - thr / 2) * m;
          if (returns) {
            for (size_t k = i; k < ret; k++) { beats[k].candidate = true; beats[k].run = (int)L; beats[k].ref_rr = m; }
            beats[ret].after_run = true;
            i = ret + 1;   // la pausa compensadora no entra en la referencia
            continue;
          }
        }
      }
      ref.push_back(beats[i].rr);
      if (ref.size() > 32) ref.erase(ref.begin());
      i++;
    }
  }
  // FC instantánea sin candidatos ni pausas: (t, lpm)
  std::vector<double> ht, hv;
  for (const auto& b : beats) if (b.rr_valid && !b.candidate && !b.after_run) { ht.push_back(b.t); hv.push_back(60.0 / b.rr); }
  {
    std::vector<double> rr;
    double s = 0; int k = 0;
    for (const auto& b : beats) if (b.rr_valid && !b.candidate && !b.after_run) rr.push_back(b.rr);
    for (const auto& b : beats) if (b.rr_valid) { s += b.rr; k++; }
    if (k) r->hr_mean = 60.0 * k / s;
    if (rr.size() >= 5) {
      std::sort(rr.begin(), rr.end());
      r->hr_peak = 60.0 / ((rr[0] + rr[1] + rr[2] + rr[3] + rr[4]) / 5.0);   // Navas de Solis 2026 [E]
    }
  }
  // FC suavizada (mediana de 5 latidos centrada)
  std::vector<double> hs(hv.size(), kNaN);
  {
    int h = c.hr_smooth_beats / 2;
    for (size_t i = 0; i < hv.size(); i++) {
      std::vector<double> w;
      for (long j = (long)i - h; j <= (long)i + h; j++) if (j >= 0 && j < (long)hv.size() && std::fabs(ht[j] - ht[i]) < 3.0) w.push_back(hv[j]);
      hs[i] = median_v(w);
    }
  }

  // 3. épocas de 5 s alineadas con el tiempo GNSS
  if (span > 0) {
    long k0 = (long)std::floor(t_begin / c.epoch_s), k1 = (long)std::ceil(t_end / c.epoch_s);
    size_t bi = 0;
    for (long k = k0; k < k1; k++) {
      HrEpoch ep; ep.t0 = k * c.epoch_s;
      double a = std::max(ep.t0, t_begin), b = std::min(ep.t0 + c.epoch_s, t_end);
      double s = 0; int cnt = 0;
      while (bi < beats.size() && beats[bi].t < ep.t0) bi++;
      for (size_t j = bi; j < beats.size() && beats[j].t < ep.t0 + c.epoch_s; j++) if (beats[j].rr_valid) { s += beats[j].rr; cnt++; }
      ep.rr = cnt;
      if (cnt) ep.hr = 60.0 * cnt / s;
      ep.artifact = b > a ? std::min(1.0, (overlap(art, a, b) + (c.epoch_s - (b - a))) / c.epoch_s) : 1.0;
      if (have_speed) { double cov; ep.speed = window_mean(gt, gv, ep.t0, ep.t0 + c.epoch_s, &cov); if (cov < 0.5) ep.speed = kNaN; }
      r->epochs.push_back(ep);
    }
  }
  auto epoch_ok = [&](const HrEpoch& e) { return e.rr >= 2 && e.artifact <= c.epoch_max_artifact && std::isfinite(e.hr); };
  for (const auto& e : r->epochs) if (epoch_ok(e) && (std::isnan(r->hr_epoch_max) || e.hr > r->hr_epoch_max)) r->hr_epoch_max = e.hr;

  // 4. fin del esfuerzo y fases
  double vmax = kNaN; size_t imax = 0;
  for (size_t i = 0; i < r->epochs.size(); i++) if (std::isfinite(r->epochs[i].speed) && (std::isnan(vmax) || r->epochs[i].speed > vmax)) { vmax = r->epochs[i].speed; imax = i; }
  double t_end_effort = kNaN;
  if (std::isfinite(vmax) && vmax >= 3.0) {
    for (size_t i = imax + 1; i < r->epochs.size(); i++)
      if (std::isfinite(r->epochs[i].speed) && r->epochs[i].speed < c.effort_end_fraction * vmax) { t_end_effort = r->epochs[i].t0; break; }
  }
  double t_hi_first = kNaN, t_hi_last = kNaN, t_hrmax_end = kNaN, hrmax_e = -1;
  for (const auto& e : r->epochs) {
    if (!epoch_ok(e)) continue;
    if (e.hr > c.max_phase_bpm) { if (std::isnan(t_hi_first)) t_hi_first = e.t0; t_hi_last = e.t0 + c.epoch_s; }
    if (e.hr > hrmax_e) { hrmax_e = e.hr; t_hrmax_end = e.t0 + c.epoch_s; }
  }
  if (std::isnan(t_end_effort)) t_end_effort = std::isfinite(t_hi_last) ? t_hi_last : t_hrmax_end;
  r->effort_end_t = t_end_effort;
  double bounds[PH_COUNT][2];
  for (auto& b : bounds) { b[0] = kNaN; b[1] = kNaN; }
  if (std::isfinite(t_end_effort) && span > 0) {
    double te = std::min(std::max(t_end_effort, t_begin), t_end);
    if (std::isfinite(t_hi_first) && t_hi_first < te) { bounds[PH_WARMUP][0] = t_begin; bounds[PH_WARMUP][1] = std::max(t_begin, t_hi_first); bounds[PH_MAX][0] = std::max(t_begin, t_hi_first); bounds[PH_MAX][1] = te; }
    else { bounds[PH_WARMUP][0] = t_begin; bounds[PH_WARMUP][1] = te; }
    bounds[PH_REC_EARLY][0] = te; bounds[PH_REC_EARLY][1] = std::min(t_end, te + c.early_recovery_s);
    bounds[PH_REC_LATE][0] = std::min(t_end, te + c.early_recovery_s); bounds[PH_REC_LATE][1] = t_end;
  } else if (span > 0) { bounds[PH_WARMUP][0] = t_begin; bounds[PH_WARMUP][1] = t_end; }
  for (int p = 0; p < PH_COUNT; p++) {
    CardioPhaseStats& ps = r->phases[p];
    ps.t0 = bounds[p][0]; ps.t1 = bounds[p][1];
    ps.duration_s = std::isfinite(ps.t0) && std::isfinite(ps.t1) ? std::max(0.0, ps.t1 - ps.t0) : 0.0;
  }
  for (auto& b : beats) {
    for (int p = PH_COUNT - 1; p >= 0; p--) {
      const CardioPhaseStats& ps = r->phases[p];
      if (ps.duration_s > 0 && b.t >= ps.t0 && b.t < ps.t1 + (p == PH_REC_LATE ? 1e-9 : 0)) { b.phase = p; break; }
    }
  }
  for (int p = 0; p < PH_COUNT; p++) {
    CardioPhaseStats& ps = r->phases[p];
    if (ps.duration_s <= 0) continue;
    ps.artifact = std::min(1.0, overlap(art, ps.t0, ps.t1) / ps.duration_s);
    for (const auto& b : beats) if (b.phase == p) { ps.beats++; if (b.candidate) { ps.candidates++; if (60.0 / b.ref_rr > 100) ps.candidates_hr100++; } }
    ps.interpretable = ps.artifact <= c.phase_artifact_gate && ps.beats >= 5;
  }
  if (std::isfinite(t_end_effort)) {
    for (size_t i = 0; i < ht.size(); i++) if (ht[i] >= t_end_effort && hs[i] < c.recovery_bpm) { r->below_120_after_s = ht[i] - t_end_effort; break; }
  }
  // recuperación a 1, 2, 4, 5, 10 y 15 min (KB recuperacion_fc_ventanas_min)
  for (double m : {1.0, 2.0, 4.0, 5.0, 10.0, 15.0}) {
    CardioResult::Recovery rc; rc.minute = m;
    if (std::isfinite(t_end_effort)) {
      double t = t_end_effort + 60.0 * m;
      if (t + 5.0 <= t_end + 1e-9 && overlap(art, t - 5, t + 5) <= 0.2 * 10.0) {
        double s = 0; int k = 0;
        for (size_t i = 0; i < ht.size(); i++) if (ht[i] >= t - 5 && ht[i] <= t + 5) { s += hv[i]; k++; }
        if (k >= 3) { rc.hr = s / k; rc.drop = r->hr_peak - rc.hr; }
      }
    }
    r->recovery.push_back(rc);
  }
  if (have_speed && std::isfinite(t_end_effort)) {
    double cov, v = window_mean(gt, gv, t_end_effort, t_end_effort + 600.0, &cov);
    if (std::isfinite(v) && cov >= 0.5) r->cooldown_class = v < 0.5 ? "PARADO" : v < 2.0 ? "PASO" : "TROTE";
  }

  // 5. V200 por el cruce de 200 lpm mantenido 10 s (Poinsard 2026)
  auto warmup_before = [&](double t) {
    if (!(t > t_begin)) return false;
    if (t - t_begin >= c.warmup_min_s) return true;
    if (!have_speed) return false;
    double d = 0;
    for (size_t i = 1; i < gt.size() && gt[i] <= t; i++) if (std::isfinite(gv[i]) && std::isfinite(gv[i - 1])) d += 0.5 * (gv[i] + gv[i - 1]) * (gt[i] - gt[i - 1]);
    return d >= c.warmup_min_m;
  };
  {
    V200Result& v = r->v200; v.method = V200_METHOD_CROSSING;
    double found = kNaN;
    for (size_t i = 0; i < hs.size() && std::isnan(found); i++) {
      if (!(hs[i] >= c.v200_bpm)) continue;
      bool ok = true; double last = ht[i];
      size_t j = i + 1;
      for (; j < hs.size() && ht[j] <= ht[i] + c.v200_hold_s; j++) {
        if (!(hs[j] >= c.v200_bpm) || ht[j] - ht[j - 1] > 1.0) { ok = false; break; }
        last = ht[j];
      }
      if (ok && last >= ht[i] + c.v200_hold_s - 0.5) found = ht[i];
    }
    if (std::isnan(found)) v.reason = "la FC no llega a 200 lpm mantenida 10 s";
    else {
      v.t_cross = found;
      v.warmup_ok = warmup_before(found);
      if (!have_speed) v.reason = "sin velocidad GNSS alineada";
      else {
        double cov, sp = window_mean(gt, gv, found, found + c.v200_hold_s, &cov);
        if (std::isfinite(sp) && cov >= 0.5) v.value = sp; else v.reason = "velocidad GNSS no utilizable en el cruce";
      }
    }
  }
  // regresión FC–velocidad sobre mesetas
  {
    V200Result& v = r->v200_regression; v.method = V200_METHOD_REGRESSION;
    std::vector<std::pair<double, double>> pts;   // (v, FC)
    std::vector<double> pt_t;
    if (have_speed) {
      size_t i = 0;
      while (i < gt.size()) {
        if (!(std::isfinite(gv[i]) && gv[i] >= c.plateau_min_speed)) { i++; continue; }
        double s = 0, s2 = 0; int k = 0; size_t j = i;
        for (; j < gt.size(); j++) {
          if (!std::isfinite(gv[j])) break;
          double ns = s + gv[j], ns2 = s2 + gv[j] * gv[j]; int nk = k + 1;
          double m = ns / nk, var = std::max(0.0, ns2 / nk - m * m);
          if (nk >= 5 && (std::sqrt(var) > c.plateau_cv * m || std::fabs(gv[j] - s / k) > c.plateau_cv * (s / k))) break;   // CV y escalón
          s = ns; s2 = ns2; k = nk;
        }
        size_t last = j > i ? j - 1 : i;
        if (gt[last] - gt[i] >= c.plateau_min_s) {
          double b = gt[last], a = gt[i] + c.plateau_discard_s;
          if (b - a >= c.plateau_avg_s) {
            double w0 = b - c.plateau_avg_s, cov;
            double sp = window_mean(gt, gv, w0, b, &cov);
            double hsum = 0; int hk = 0; double rrsum = 0;
            for (size_t q = 0; q < ht.size(); q++) if (ht[q] >= w0 && ht[q] <= b) { hsum += hv[q]; hk++; rrsum += 60.0 / hv[q]; }
            if (std::isfinite(sp) && cov >= 0.8 && hk >= 3 && rrsum >= 0.8 * c.plateau_avg_s) { pts.push_back({sp, hsum / hk}); pt_t.push_back(w0); }
          }
          i = last + 1;
        } else i++;
      }
    }
    v.points = (int)pts.size();
    if ((int)pts.size() < c.regression_min_points) v.reason = "menos de 3 mesetas de velocidad utilizables";
    else {
      double n = pts.size(), sx = 0, sy = 0, sxx = 0, sxy = 0, syy = 0;
      for (auto& p : pts) { sx += p.first; sy += p.second; sxx += p.first * p.first; sxy += p.first * p.second; syy += p.second * p.second; }
      double den = n * sxx - sx * sx;
      if (den <= 0) v.reason = "mesetas a la misma velocidad";
      else {
        v.slope = (n * sxy - sx * sy) / den; v.intercept = (sy - v.slope * sx) / n;
        double sst = syy - sy * sy / n, sse = 0;
        for (auto& p : pts) { double e = p.second - (v.intercept + v.slope * p.first); sse += e * e; }
        v.r2 = sst > 0 ? 1.0 - sse / sst : kNaN;
        double hlo = 1e9, hhi = -1e9; for (auto& p : pts) { hlo = std::min(hlo, p.second); hhi = std::max(hhi, p.second); }
        if (!(v.slope > 0)) v.reason = "pendiente FC–velocidad no positiva";
        else if (!(v.r2 >= c.regression_r2_min)) v.reason = "R² de la recta FC–velocidad < 0,90";
        else if (c.v200_bpm < hlo || c.v200_bpm > hhi) v.reason = "200 lpm fuera del rango de las mesetas (no se extrapola)";
        else {
          v.value = (c.v200_bpm - v.intercept) / v.slope;
          v.warmup_ok = warmup_before(*std::min_element(pt_t.begin(), pt_t.end()));   // antes de la primera meseta
        }
        // VHRmax por la regresión (sin extrapolar más de 2 lpm)
        if (v.slope > 0 && v.r2 >= c.regression_r2_min && std::isfinite(r->hr_peak) && r->hr_peak >= hlo && r->hr_peak <= hhi + 2.0) {
          r->vhrmax.value = (r->hr_peak - v.intercept) / v.slope; r->vhrmax.method = V200_METHOD_REGRESSION;
        }
      }
    }
  }
  if (std::isnan(r->vhrmax.value)) {
    double best = -1; for (const auto& e : r->epochs) if (epoch_ok(e) && std::isfinite(e.speed) && e.hr > best) { best = e.hr; r->vhrmax.value = e.speed; }
    if (std::isfinite(r->vhrmax.value)) r->vhrmax.method = "EPOCA_FC_MAXIMA";
    else r->vhrmax.reason = have_speed ? "sin épocas válidas con velocidad" : "sin velocidad GNSS alineada";
  }

  // 6. resumen de la ectopia (candidatos a revisar, nunca un diagnóstico)
  int complex_interp = 0, hr100_interp = 0;
  for (size_t i = 0; i < beats.size(); i++) {
    const EcgBeat& b = beats[i];
    if (!b.candidate) continue;
    r->candidates++;
    bool first_of_run = i == 0 || !beats[i - 1].candidate;
    bool interp = b.phase >= 0 && r->phases[b.phase].interpretable;
    bool hr100 = 60.0 / b.ref_rr > 100;
    if (interp && hr100) hr100_interp++;
    if (!first_of_run) continue;
    if (b.run <= 1) r->isolated++; else if (b.run == 2) r->pairs++; else if (b.run == 3) r->triplets++; else r->runs++;
    if (interp && hr100 && b.run >= 3) complex_interp++;
  }
  char tb[400];
  if (r->candidates == 0) r->ectopy_text = "sin latidos prematuros candidatos";
  else {
    snprintf(tb, sizeof(tb), "%d latidos prematuros candidatos (%d aislados, %d parejas, %d tripletes, %d rachas ≥ 4): candidatos a revisar "
             "con el ECG por un veterinario; no es un diagnóstico", r->candidates, r->isolated, r->pairs, r->triplets, r->runs);
    r->ectopy_text = tb;
  }
  if (complex_interp > 0 || hr100_interp > c.ectopy_tolerated) r->ectopy_level = "VIGILAR";
  r->beats = std::move(beats);
  int nb = 0; for (const auto& b : r->beats) if (b.rr_valid) nb++;
  if (nb < 10 || !std::isfinite(r->artifact)) r->quality = "NO_UTILIZABLE";
  else r->quality = r->artifact <= 0.05 ? "BUENA" : r->artifact <= 0.10 ? "UTILIZABLE" : r->artifact <= 0.30 ? "POBRE" : "NO_UTILIZABLE";
  if (r->phases[PH_MAX].duration_s <= 0 && nb >= 10) r->warnings.push_back("la FC no supera 185 lpm: sin fase MAXIMA");
  for (int p = 0; p < PH_COUNT; p++)
    if (r->phases[p].duration_s > 0 && !r->phases[p].interpretable)
      r->warnings.push_back(std::string("fase ") + cardio_phase_name(p) + " NO INTERPRETABLE (artefacto > 10 % o < 5 latidos)");
  if (std::isfinite(r->v200.value)) r->warnings.push_back("V200 NO VALIDADA: falta el error típico propio del caballo (≥ 3 pruebas comparables)");
  if (std::isfinite(r->v200.value) && !r->v200.warmup_ok) r->warnings.push_back("V200 con calentamiento corto (< 1000 m y < 10 min, WU1)");
}

// ------------------------------------------------------------------ sesión completa
CardioResult analyse_cardio(const Session& s, const ClockMap& chest_to_gnss, const std::vector<double>& gnss_t,
                            const std::vector<double>& gnss_v, const SyncConfig& sync, const CardioConfig& c) {
  CardioResult r;
  if (!c.enabled || s.ecg.empty()) return r;
  r.present = true;
  r.batches = (uint32_t)s.ecg.size(); r.duplicates = s.ecg_duplicates;
  const double per_us = s.ecg[0].period_us > 0 ? s.ecg[0].period_us : 1953.125;
  const double fs = 1e6 / per_us;
  r.fs_hz = fs;
  // reloj de la cincha → pecho → GNSS (un par por lote: su última muestra)
  std::vector<double> gx, cy;
  for (const auto& b : s.ecg) { gx.push_back((b.t0_us + (b.duv.size() - 1) * b.period_us) * 1e-6); cy.push_back(b.chest_us * 1e-6); }
  ClockMap map;
  if (!chest_to_gnss.pieces.empty()) map = compose_girth_map(gx, cy, chest_to_gnss, sync);
  r.aligned_gnss = !map.pieces.empty();
  double first_girth = gx.empty() ? 0 : s.ecg[0].t0_us * 1e-6;
  auto to_t = [&](double tg, double* out) {
    if (r.aligned_gnss) return map.map(tg, out);
    *out = tg - first_girth; return true;
  };
  // tramos continuos de muestras válidas
  std::vector<EcgBeat> beats;
  std::vector<std::pair<double, double>> gaps;
  std::vector<double> run; double run_t0 = 0, prev_end = kNaN, expected = kNaN;
  double t_begin = kNaN, t_end = kNaN;
  auto flush = [&]() {
    if (run.empty()) return;
    double run_t1 = run_t0 + (run.size() - 1) / fs;
    if (run.size() >= (size_t)(2.0 * fs)) {
      int pol = 0;
      std::vector<EcgBeat> bb = detect_beats(run, fs, c, &pol);
      if (pol) r.polarity = pol;
      for (auto& b : bb) {
        double tg = run_t0 + b.t_girth;
        if (tg < run_t0 + 0.1 || tg > run_t1 - 0.1) continue;   // bordes del filtro
        double t; if (!to_t(tg, &t)) continue;
        b.t_girth = tg; b.t = t; beats.push_back(b);
      }
    } else {
      double a, b; if (to_t(run_t0, &a) && to_t(run_t1, &b)) gaps.push_back({a, b});
    }
    run.clear();
  };
  for (const auto& b : s.ecg) {
    double t0 = b.t0_us * 1e-6, dt = b.period_us * 1e-6;
    if (std::isfinite(expected) && std::fabs(t0 - expected) > 0.5 * dt) {
      flush();
      double a, bb;
      if (std::isfinite(prev_end) && t0 > prev_end && to_t(prev_end, &a) && to_t(t0, &bb)) gaps.push_back({a, bb});
    }
    for (size_t i = 0; i < b.duv.size(); i++) {
      double t = t0 + i * dt;
      r.samples++;
      { double m; if (to_t(t, &m)) { if (std::isnan(t_begin) || m < t_begin) t_begin = m; if (std::isnan(t_end) || m > t_end) t_end = m; } }
      if (b.duv[i] == ECG_INVALID_DUV) {
        r.invalid_samples++;
        if (!run.empty()) { flush(); }
        double a, bb; if (to_t(t, &a) && to_t(t + dt, &bb)) gaps.push_back({a, bb});
        continue;
      }
      if (run.empty()) run_t0 = t;
      run.push_back(b.duv[i] * 1e-4);   // 0,1 µV → mV
    }
    expected = t0 + b.duv.size() * dt;
    prev_end = expected;
  }
  flush();
  if (!r.aligned_gnss) r.warnings.push_back("ECG sin alinear con el GNSS: tiempos en el reloj de la cincha, sin velocidad");
  if (std::isnan(t_begin)) return r;
  analyse_rr(beats, r.aligned_gnss ? gnss_t : std::vector<double>(), r.aligned_gnss ? gnss_v : std::vector<double>(), gaps, t_begin, t_end, c, &r);
  return r;
}

// ------------------------------------------------------------------ JSON
std::string cardio_json(const CardioResult& r, const CardioConfig& c, bool series) {
  std::ostringstream o;
  o << "{\"presente\":" << (r.present ? "true" : "false") << ",\"version\":\"" << CARDIO_VERSION << "\",\"algoritmo\":\"" << CARDIO_DETECTOR_ID << "\"";
  if (!r.present) { o << "}"; return o.str(); }
  auto v200 = [&](const V200Result& v) {
    std::ostringstream q;
    q << "{\"valor_m_s\":" << num(v.value) << ",\"metodo\":\"" << esc(v.method) << "\",\"validada\":false";
    if (v.method == V200_METHOD_CROSSING) q << ",\"fuente\":\"POINSARD_2026\",\"t_cruce_s\":" << num(v.t_cross) << ",\"fc_lpm\":" << num(c.v200_bpm) << ",\"mantenida_s\":" << num(c.v200_hold_s);
    if (v.method == V200_METHOD_REGRESSION) q << ",\"fuente\":\"VERMEULEN_EVANS_2006\",\"pendiente_lpm_por_m_s\":" << num(v.slope) << ",\"intercepto_lpm\":" << num(v.intercept)
                                              << ",\"r2\":" << num(v.r2) << ",\"mesetas\":" << v.points;
    q << ",\"calentamiento_suficiente\":" << (v.warmup_ok ? "true" : "false") << ",\"motivo\":" << (v.reason.empty() ? "null" : "\"" + esc(v.reason) + "\"") << "}";
    return q.str();
  };
  int valid = 0; for (const auto& b : r.beats) if (b.rr_valid) valid++;
  o << ",\"fuente\":\"CINCHA_MAX30003_FMT2\",\"lotes\":" << r.batches << ",\"lotes_duplicados\":" << r.duplicates << ",\"muestras\":" << r.samples
    << ",\"muestras_no_validas\":" << r.invalid_samples << ",\"fs_hz\":" << num(r.fs_hz) << ",\"alineada_gnss\":" << (r.aligned_gnss ? "true" : "false")
    << ",\"duracion_s\":" << num(r.duration_s) << ",\"polaridad_s\":" << r.polarity << ",\"latidos\":" << r.beats.size() << ",\"rr_validos\":" << valid
    << ",\"artefacto_pct\":" << num(std::isfinite(r.artifact) ? 100.0 * r.artifact : NAN) << ",\"calidad\":\"" << r.quality << "\""
    << ",\"fc_pico_lpm\":" << num(r.hr_peak) << ",\"fc_max_epoca_lpm\":" << num(r.hr_epoch_max) << ",\"fc_media_lpm\":" << num(r.hr_mean)
    << ",\"fin_esfuerzo_s\":" << num(r.effort_end_t) << ",\"fc_bajo_120_tras_s\":" << num(r.below_120_after_s)
    << ",\"vuelta_calma\":" << (r.cooldown_class.empty() ? "null" : "\"" + r.cooldown_class + "\"") << ",\"fases\":{";
  for (int p = 0; p < PH_COUNT; p++) {
    const CardioPhaseStats& ps = r.phases[p];
    o << (p ? "," : "") << "\"" << cardio_phase_name(p) << "\":{\"t0\":" << num(ps.t0) << ",\"t1\":" << num(ps.t1) << ",\"duracion_s\":" << num(ps.duration_s)
      << ",\"artefacto_pct\":" << num(std::isfinite(ps.artifact) ? 100.0 * ps.artifact : NAN) << ",\"interpretable\":" << (ps.interpretable ? "true" : "false")
      << ",\"latidos\":" << ps.beats << ",\"ectopicos_candidatos\":" << ps.candidates << ",\"ectopicos_candidatos_fc_mayor_100\":" << ps.candidates_hr100 << "}";
  }
  o << "},\"v200\":" << v200(r.v200) << ",\"v200_regresion\":" << v200(r.v200_regression)
    << ",\"vhrmax\":{\"valor_m_s\":" << num(r.vhrmax.value) << ",\"metodo\":" << (r.vhrmax.method.empty() ? "null" : "\"" + r.vhrmax.method + "\"")
    << ",\"fc_pico_lpm\":" << num(r.hr_peak) << ",\"validada\":false,\"motivo\":" << (r.vhrmax.reason.empty() ? "null" : "\"" + esc(r.vhrmax.reason) + "\"") << "}"
    << ",\"recuperacion\":[";
  for (size_t i = 0; i < r.recovery.size(); i++)
    o << (i ? "," : "") << "{\"min\":" << num(r.recovery[i].minute) << ",\"fc_lpm\":" << num(r.recovery[i].hr) << ",\"caida_lpm\":" << num(r.recovery[i].drop) << "}";
  o << "],\"ectopia\":{\"tipo\":\"CANDIDATO_A_REVISAR\",\"umbral_pct\":" << num(c.premature_pct) << ",\"candidatos\":" << r.candidates
    << ",\"aislados\":" << r.isolated << ",\"parejas\":" << r.pairs << ",\"tripletes\":" << r.triplets << ",\"rachas\":" << r.runs
    << ",\"nivel\":\"" << r.ectopy_level << "\",\"texto\":\"" << esc(r.ectopy_text) << "\",\"diagnostico\":false}";
  o << ",\"avisos\":[";
  for (size_t i = 0; i < r.warnings.size(); i++) o << (i ? "," : "") << "\"" << esc(r.warnings[i]) << "\"";
  o << "]";
  if (series) {
    o << ",\"epocas\":[";
    for (size_t i = 0; i < r.epochs.size(); i++) {
      const HrEpoch& e = r.epochs[i];
      o << (i ? "," : "") << "[" << num(e.t0) << "," << num(e.hr) << "," << num(e.speed) << "," << num(e.artifact) << "]";
    }
    o << "],\"latidos_rr\":[";
    bool first = true;
    for (const auto& b : r.beats) {
      if (!b.rr_valid) continue;
      o << (first ? "" : ",") << "[" << num(b.t) << "," << num(b.rr) << "," << (b.candidate ? 1 : 0) << "]"; first = false;
    }
    o << "]";
  }
  o << "}";
  return o.str();
}

}  // namespace avoeq
