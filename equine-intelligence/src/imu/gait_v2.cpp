// GAIT_CLASSIFIER_V2 — configurable feature scoring (fuzzy memberships, weighted geometric mean), explicit
// UNKNOWN / INSUFFICIENT_DATA / TRANSITION, hysteresis, minimum segment duration and an optional trained model.
// No claim of superiority over V1: both are evaluated on the same data with evaluate_gait().
#include "avo_eq/json.h"
#include "avo_eq/motion.h"
#include "avo_eq/dsp.h"
#include <algorithm>
#include <cmath>
#include <map>

namespace avoeq {

static const char* V2_VERSION = "2.0.0";

double Trapezoid::at(double x) const {
  if (a == -1 && b == -1 && c == -1 && d == -1) return 0;           // feature not applicable to the class
  if (std::isnan(x)) return 0;
  if (x <= a || x >= d) return (x <= a && a == b && x >= a) ? 1 : (x >= d && c == d && x <= d) ? 1 : 0;
  if (x < b) return (x - a) / (b - a);
  if (x <= c) return 1;
  return (d - x) / (d - c);
}

std::vector<GaitFeatures> gait_features(const GnssResult& g, const CadenceResult* cad, const ClockMap* map, double step_s) {
  std::vector<GaitFeatures> out;
  bool sorted = std::is_sorted(g.t.begin(), g.t.end());
  auto speed_at = [&](double t, double* sig) {
    std::vector<double> v;
    size_t i = sorted ? (size_t)(std::lower_bound(g.t.begin(), g.t.end(), t - 1.0) - g.t.begin()) : 0;
    for (; i < g.t.size(); i++) {
      if (sorted && g.t[i] > t + 1.0) break;
      if (std::fabs(g.t[i] - t) <= 1.0 && !std::isnan(g.speed[i]) && g.quality[i] <= (uint8_t)Quality::POOR) v.push_back(g.speed[i]);
    }
    if (v.size() < 3) { *sig = NAN; return (double)NAN; }
    *sig = dsp::stddev(v) / std::sqrt((double)v.size());
    return dsp::median(v);
  };
  bool imu = cad && map && !cad->windows.empty() && !map->pieces.empty();
  if (imu) {
    for (const auto& w : cad->windows) {
      double tg;
      if (!map->map(w.t_mid, &tg)) continue;
      GaitFeatures f; f.t = tg;
      f.speed = speed_at(tg, &f.speed_sigma);
      if (w.status == CadenceStatus::VALID) {
        f.f0 = w.freq_hz; f.f0_sigma = w.uncertainty_hz; f.strength = w.strength;
        if (w.harmonic_ratio[1] >= 0) f.h2h1 = w.harmonic_ratio[1];
        if (w.half_cycle_ratio > -1) f.half_cycle_ratio = w.half_cycle_ratio;
        if (w.interval_cv >= 0) f.interval_cv = w.interval_cv;
        if (w.cycle_corr >= 0) f.cycle_corr = w.cycle_corr;
        f.rms = w.rms;
      }
      out.push_back(f);
    }
  }
  if (out.empty() && !g.t.empty()) {
    for (double t = g.t.front(); t <= g.t.back(); t += step_s) {
      GaitFeatures f; f.t = t; f.speed = speed_at(t, &f.speed_sigma);
      out.push_back(f);
    }
  }
  std::sort(out.begin(), out.end(), [](const GaitFeatures& a, const GaitFeatures& b) { return a.t < b.t; });
  return out;
}

// ------------------------------------------------------------------ trained model (nearest centroid)
namespace {
struct CentroidModel : GaitModel {
  std::string name;
  std::vector<std::string> feats;
  std::vector<double> mu, sd;
  std::map<int, std::vector<double>> cent;   // class index 0..3
  std::string id() const override { return name; }
  bool feature(const GaitFeatures& f, const std::string& k, double* v) const {
    if (k == "v_gnss") *v = f.speed; else if (k == "f_ciclo") *v = f.f0; else if (k == "fuerza") *v = f.strength;
    else if (k == "cv_intervalos") *v = f.interval_cv; else if (k == "corr_ciclos") *v = f.cycle_corr;
    else return false;
    return true;
  }
  bool scores(const GaitFeatures& f, double out[4]) const override {
    std::vector<double> z(feats.size());
    int present = 0;
    for (size_t i = 0; i < feats.size(); i++) {
      double v; if (!feature(f, feats[i], &v)) return false;
      if (std::isnan(v)) v = mu[i]; else present++;        // same imputation as ml/avo_ml.py
      z[i] = (v - mu[i]) / sd[i];
    }
    if (present == 0) return false;
    for (int k = 0; k < 4; k++) {
      auto it = cent.find(k);
      if (it == cent.end()) { out[k] = 0; continue; }
      double d2 = 0; for (size_t i = 0; i < z.size(); i++) d2 += (z[i] - it->second[i]) * (z[i] - it->second[i]);
      out[k] = std::exp(-0.5 * d2 / (double)z.size());
    }
    return true;
  }
};
}  // namespace

std::unique_ptr<GaitModel> load_centroid_model(const std::string& text, std::string* err) {
  json::Value v;
  if (!json::parse(text, &v, err)) return nullptr;
  if (v["tipo"].str() != "centroide_mas_cercano") { if (err) *err = "tipo de modelo no soportado"; return nullptr; }
  std::unique_ptr<CentroidModel> m(new CentroidModel());
  for (auto& f : v["rasgos"].a) m->feats.push_back(f.str());
  for (auto& x : v["media"].a) m->mu.push_back(x.num());
  for (auto& x : v["desv"].a) m->sd.push_back(x.num(1) > 1e-12 ? x.num(1) : 1);
  if (m->feats.empty() || m->mu.size() != m->feats.size() || m->sd.size() != m->feats.size()) { if (err) *err = "modelo incompleto"; return nullptr; }
  const char* names[4] = {"PARADO", "PASO", "TROTE", "GALOPE"};
  for (int k = 0; k < 4; k++) {
    const json::Value& c = v["centroides"][names[k]];
    if (c.type != json::Value::ARR) continue;
    std::vector<double> cc; for (auto& x : c.a) cc.push_back(x.num());
    if (cc.size() != m->feats.size()) { if (err) *err = "centroide con dimensión distinta"; return nullptr; }
    m->cent[k] = cc;
  }
  if (m->cent.size() < 2) { if (err) *err = "el modelo necesita al menos dos clases"; return nullptr; }
  for (auto& f : m->feats) { double d; GaitFeatures probe; if (!m->feature(probe, f, &d)) { if (err) *err = "rasgo desconocido: " + f; return nullptr; } }
  m->name = "centroide_mas_cercano(" + std::to_string(m->cent.size()) + " clases, entrenado " + v["entrenado_con"]["fecha"].str("?") + ")";
  return std::unique_ptr<GaitModel>(m.release());
}

// ------------------------------------------------------------------ classifier
GaitResult classify_gait_v2(const GnssResult& g, const CadenceResult* cad, const ClockMap* map, const GaitV2Config& c, const GaitModel* model) {
  GaitResult r;
  r.classifier = GAIT_V2_ID; r.version = V2_VERSION;
  r.algorithm = model ? "modelo entrenado: " + model->id() : "puntuación por pertenencias configurables (velocidad, frecuencia de ciclo, armónicos) + histéresis";
  std::vector<GaitFeatures> fs = gait_features(g, cad, map, c.step_s);
  struct Pt { double t; Gait g; double conf; std::string basis; };
  std::vector<Pt> pts;
  for (const auto& f : fs) {
    Pt p{f.t, Gait::INSUFFICIENT_DATA, 0, ""};
    bool hv = !std::isnan(f.speed), hf = !std::isnan(f.f0), hh = !std::isnan(f.h2h1);
    double sc[4] = {0, 0, 0, 0};
    bool scored = false;
    if (model && model->scores(f, sc)) { scored = true; p.basis = "modelo"; }
    else if (hv || hf) {
      for (int k = 0; k < 4; k++) {
        double lg = 0, ws = 0;
        if (hv) { lg += c.w_speed * std::log(std::max(c.floor, c.speed[k].at(f.speed))); ws += c.w_speed; }
        if (hf) { lg += c.w_freq * std::log(std::max(c.floor, c.freq[k].at(f.f0))); ws += c.w_freq; }
        if (hh && k > 0) { lg += c.w_harm * std::log(std::max(c.floor, c.harm[k].at(f.h2h1))); ws += c.w_harm; }
        else if (hh && k == 0) { lg += c.w_harm * std::log(c.floor); ws += c.w_harm; }   // a periodic gait signal contradicts "stopped"
        sc[k] = ws > 0 ? std::exp(lg / ws) : 0;
      }
      scored = true;
      p.basis = std::string(hv ? "velocidad" : "") + (hf ? (hv ? "+frecuencia" : "frecuencia") : "") + (hh ? "+armónicos" : "");
    }
    if (scored) {
      int best = 0, second = -1;
      for (int k = 1; k < 4; k++) if (sc[k] > sc[best]) best = k;
      for (int k = 0; k < 4; k++) if (k != best && (second < 0 || sc[k] > sc[second])) second = k;
      double margin = sc[best] - (second >= 0 ? sc[second] : 0);
      p.conf = sc[best];
      p.g = (sc[best] >= c.min_score && margin >= c.min_margin) ? (Gait)best : Gait::UNKNOWN;
      if (p.g == Gait::UNKNOWN) p.basis += " (puntuación o margen insuficiente)";
    } else p.basis = "sin velocidad GNSS ni cadencia válida";
    pts.push_back(p);
  }
  // hysteresis over the decided states (UNKNOWN and INSUFFICIENT_DATA are states too)
  std::vector<Pt> acc;
  if (!pts.empty()) {
    Gait cur = pts[0].g, cand = cur; int cnt = 0;
    for (auto p : pts) {
      if (p.g == cur) cnt = 0;
      else if (p.g == cand) { if (++cnt >= c.confirm_points) { cur = cand; cnt = 0; } }
      else { cand = p.g; cnt = 1; if (c.confirm_points <= 1) { cur = cand; cnt = 0; } }
      p.g = cur; acc.push_back(p);
    }
  }
  // segments
  std::vector<std::pair<double, int>> conf;   // sum, count per segment
  std::map<std::string, int> bases; std::vector<std::map<std::string, int>> segb;
  for (size_t i = 0; i < acc.size(); i++) {
    double t_next = i + 1 < acc.size() ? acc[i + 1].t : acc[i].t;
    if (r.segments.empty() || r.segments.back().gait != acc[i].g) {
      GaitSegment s; s.gait = acc[i].g; s.t0 = acc[i].t; s.t1 = t_next;
      r.segments.push_back(s); conf.push_back({0, 0}); segb.push_back({});
    } else r.segments.back().t1 = t_next;
    conf.back().first += acc[i].conf; conf.back().second++;
    segb.back()[acc[i].basis]++;
  }
  for (size_t k = 0; k < r.segments.size(); k++) {
    auto& s = r.segments[k];
    s.confidence = conf[k].second ? conf[k].first / conf[k].second : 0;
    int bestn = -1; for (auto& b : segb[k]) if (b.second > bestn) { bestn = b.second; s.basis = b.first; }
    if (s.gait == Gait::UNKNOWN || s.gait == Gait::INSUFFICIENT_DATA) s.quality = Quality::UNKNOWN;
    else s.quality = s.confidence >= 0.75 ? Quality::GOOD : s.confidence >= 0.5 ? Quality::USABLE : Quality::POOR;
    if ((int)s.gait <= 3 && s.t1 - s.t0 < c.min_segment_s) { s.gait = Gait::TRANSITION; s.basis = "segmento más corto que la duración mínima"; s.quality = Quality::POOR; }
  }
  std::vector<GaitSegment> merged;
  for (auto& s : r.segments) {
    if (!merged.empty() && merged.back().gait == s.gait) {
      double d0 = merged.back().t1 - merged.back().t0, d1 = s.t1 - s.t0;
      merged.back().confidence = (merged.back().confidence * d0 + s.confidence * d1) / std::max(1e-9, d0 + d1);
      merged.back().t1 = s.t1;
    } else merged.push_back(s);
  }
  r.segments = merged;
  for (int k = 0; k <= 6; k++) {
    double tsum = 0;
    for (auto& s : r.segments) if ((int)s.gait == k) tsum += s.t1 - s.t0;
    if (tsum <= 0) continue;
    Metric m; m.name = std::string("tiempo_") + gait_name((Gait)k); m.unit = "s"; m.value = tsum; m.algorithm = r.algorithm; m.version = r.version;
    m.quality = Quality::USABLE; m.warnings.push_back("pertenencias iniciales sin validar con caballos reales");
    r.metrics.push_back(m);
  }
  return r;
}

// ------------------------------------------------------------------ evaluation
double GaitEvaluation::recall(Gait g) const {
  double row = 0; for (int p = 0; p < 7; p++) row += confusion[(int)g][p];
  return row > 0 ? confusion[(int)g][(int)g] / row : -1;
}
double GaitEvaluation::precision(Gait g) const {
  double col = 0; for (int t = 0; t < 7; t++) col += confusion[t][(int)g];
  return col > 0 ? confusion[(int)g][(int)g] / col : -1;
}

GaitEvaluation evaluate_gait(const std::vector<GaitSegment>& pred, const std::vector<GaitSegment>& truth, double guard, double step) {
  GaitEvaluation e;
  auto at = [](const std::vector<GaitSegment>& v, double t) -> const GaitSegment* {
    for (auto& s : v) if (t >= s.t0 && t < s.t1) return &s;
    return nullptr;
  };
  if (truth.empty()) return e;
  for (double t = truth.front().t0; t < truth.back().t1; t += step) {
    const GaitSegment* tr = at(truth, t);
    if (!tr || tr->gait == Gait::TRANSITION || t - tr->t0 < guard || tr->t1 - t < guard) continue;
    const GaitSegment* p = at(pred, t);
    Gait pg = p ? p->gait : Gait::INSUFFICIENT_DATA;
    e.confusion[(int)tr->gait][(int)pg] += step;
    e.evaluated_s += step;
    if (pg == tr->gait) e.agree_s += step;
  }
  return e;
}

}  // namespace avoeq
