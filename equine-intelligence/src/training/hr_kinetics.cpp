// Cinética de la FC en la historia (TRAINING 1.6.0, KB 1.33.0, motor 2.0.0-dev40). Usa lo que el análisis de cada
// sesión saca del ECG de la cincha PROTOTIPO 0.5.x (cardio 1.2.0):
//  CF2  τ de recuperación de la FC (ajuste A + B·e^(−t/τ) de 60 a 600 s tras el esfuerzo): solo tendencia del propio
//       caballo, comparando la misma vuelta a la calma (WU4) y un calentamiento parecido (WU3). Sin valores de referencia:
//       en PSI no hay τ publicada con cifra que hayamos leído [NV]; ponis biexponencial (Rugh 1992 [E-r]); en PSI τ baja con
//       el entrenamiento y se relaciona con el VO2max (Hada 2007, resumen [E-r]).
//  RC1  THR100 (tiempo hasta FC < 100 lpm): tendencia propia; el corte de 200 s de la JRA es solo referencia [OFICIAL].
//  FW1  FC media del tramo fijo de trote del calentamiento a la misma velocidad (±0,3 m/s) y superficie: tendencia diaria
//       sustituta de la V200 (Yamanobe 1993 [E-r]).
//  WU3  comparables solo con calentamiento parecido (distancia ±20 %) [I]; la misma regla se aplica a A9 (training.cpp).
// Todo SIN CALIBRAR: las marcas son INFO y nunca cambian el estado del caballo. No es un diagnóstico.
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <sstream>
#include "avo_eq/json.h"
#include "avo_eq/training.h"

namespace avoeq {
namespace {

std::string num(double v, int dec = 3) {
  if (!std::isfinite(v)) return "null";
  char b[40]; snprintf(b, sizeof(b), "%.*f", dec, v);
  std::string s = b;
  if (s.find('.') != std::string::npos) { while (s.back() == '0') s.pop_back(); if (s.back() == '.') s.pop_back(); }
  if (s == "-0") s = "0";
  return s;
}
std::string q(const std::string& s) { return s.empty() ? "null" : "\"" + json::escape(s) + "\""; }

double med(std::vector<double> v) {
  if (v.empty()) return NAN;
  std::sort(v.begin(), v.end());
  size_t n = v.size();
  return n % 2 ? v[n / 2] : 0.5 * (v[n / 2 - 1] + v[n / 2]);
}
double mad_of(const std::vector<double>& v, double m) {
  std::vector<double> d; for (double x : v) d.push_back(std::fabs(x - m));
  return med(d);
}
bool warmup_similar(double ref_m, double other_m, double pct) {
  if (!(pct > 0) || !std::isfinite(ref_m) || !std::isfinite(other_m) || !(ref_m > 0)) return true;
  return std::fabs(other_m - ref_m) <= pct / 100.0 * ref_m;
}
std::string surf_of(const SessionSummary& s) { return (s.surface.empty() ? "sin anotar" : s.surface) + (s.beach_band.empty() ? "" : " · " + s.beach_band); }

const char* const EV_CF2 = "CF2 [I] (estudio 20/11 16:10): τ solo como tendencia propia; ponis biexponencial τ 15 y 455 s (Rugh 1992 [E-r]); "
                           "PSI: τ baja con el entrenamiento (Hada 2007 [E-r], sin cifra leída); umbral del 25 % sin calibrar";
const char* const EV_RC1 = "RC1 (JRA, informe técnico 134 [OFICIAL, sin revisión por pares]): THR100 como tendencia propia; 200 s solo referencia; "
                           "umbral del 25 % sin calibrar";
const char* const EV_FW1 = "FW1 (Yamanobe 1993 [E-r], n 5 PSI): la FC del calentamiento fijo baja con el entrenamiento; tramo y umbral de 8 lpm [I], "
                           "sin calibrar";

// Métrica de la sesión i frente a sus comparables anteriores.
HrKinMetric eval_metric(const std::vector<SessionSummary>& ok, size_t i, const TrainingConfig& c, const char* metric, const char* rule,
                        const char* unit, bool relative) {
  const auto& P = c.hrkin;
  const SessionSummary& s = ok[i];
  HrKinMetric m; m.metric = metric; m.rule = rule; m.unit = unit;
  auto get = [&](const SessionSummary& z) {
    if (m.rule == "CF2") return z.cardio.tau_s;
    if (m.rule == "RC1") return z.cardio.thr100_s;
    return z.cardio.fw_hr;
  };
  m.last = get(s);
  if (!std::isfinite(m.last)) return m;
  std::vector<double> x;
  for (size_t jj = i; jj-- > 0 && (int)x.size() < P.max_baseline;) {
    const SessionSummary& z = ok[jj];
    if (s.day - z.day > P.window_days) break;
    if (!z.cardio.present || !std::isfinite(get(z))) continue;
    if (z.surface != s.surface || z.beach_band != s.beach_band) continue;
    if (m.rule == "FW1") {
      if (!std::isfinite(z.cardio.fw_speed) || !std::isfinite(s.cardio.fw_speed) || std::fabs(z.cardio.fw_speed - s.cardio.fw_speed) > P.fw_speed_match_m_s) continue;
    } else {
      if (z.cardio.cooldown_class.empty() || z.cardio.cooldown_class != s.cardio.cooldown_class) continue;
      if (!warmup_similar(s.cardio.warmup_m, z.cardio.warmup_m, P.warmup_match_pct)) continue;
    }
    x.push_back(get(z));
  }
  m.n = (int)x.size();
  char b[160];
  if (m.rule == "FW1") snprintf(b, sizeof(b), "misma superficie «%s» y velocidad %.2f ± %.2f m/s", surf_of(s).c_str(), s.cardio.fw_speed, P.fw_speed_match_m_s);
  else snprintf(b, sizeof(b), "misma superficie «%s», vuelta a la calma %s y calentamiento ±%.0f %%", surf_of(s).c_str(),
                s.cardio.cooldown_class.empty() ? "sin clase" : s.cardio.cooldown_class.c_str(), P.warmup_match_pct);
  m.comparable = b;
  if (m.n < P.min_baseline) return m;
  m.baseline = med(x); m.mad = mad_of(x, m.baseline);
  if (relative) { if (m.baseline > 0) m.change = 100.0 * (m.last - m.baseline) / m.baseline; }
  else m.change = m.last - m.baseline;
  double thr = m.rule == "CF2" ? P.tau_rise_pct : m.rule == "RC1" ? P.thr100_rise_pct : P.fw_hr_rise_bpm;
  m.marked = std::isfinite(m.change) && m.change >= thr;
  return m;
}

}  // namespace

HrKinetics training_hr_kinetics(const std::vector<SessionSummary>& ok, long at, const TrainingConfig& c) {
  HrKinetics k;
  const auto& P = c.hrkin;
  if (!P.enabled) { k.reason = "desactivada por opción"; return k; }
  long last_i = -1;
  for (size_t i = 0; i < ok.size(); i++) {
    if (ok[i].day > at) break;
    if (ok[i].cardio.present) { k.ecg_sessions++; last_i = (long)i; }
  }
  if (last_i < 0) { k.reason = "ninguna sesión con ECG de la cincha"; return k; }
  const SessionSummary& s = ok[last_i];
  k.available = true;
  k.last_id = s.id; k.last_day = s.day; k.cooldown_class = s.cardio.cooldown_class;
  k.warmup_m = s.cardio.warmup_m; k.warmup_s = s.cardio.warmup_s;
  k.metrics.push_back(eval_metric(ok, last_i, c, "TAU_RECUPERACION", "CF2", "s", true));
  k.metrics.push_back(eval_metric(ok, last_i, c, "THR100", "RC1", "s", true));
  k.metrics.push_back(eval_metric(ok, last_i, c, "FC_TRAMO_FIJO", "FW1", "lpm", false));
  // marcas de las sesiones de los últimos marks_days días (cada una frente a sus comparables anteriores)
  char b[400];
  for (size_t i = 0; i < ok.size(); i++) {
    const SessionSummary& z = ok[i];
    if (z.day > at) break;
    if (!z.cardio.present || at - z.day > P.marks_days) continue;
    HrKinMetric tau = eval_metric(ok, i, c, "TAU_RECUPERACION", "CF2", "s", true);
    if (tau.marked) {
      snprintf(b, sizeof(b), "recuperación de la FC más lenta: τ %.0f s frente a %.0f s de mediana propia (%+.0f %%, %d sesiones con %s); "
               "puede deberse a calor, cansancio o a otra vuelta a la calma; sin calibrar", tau.last, tau.baseline, tau.change, tau.n, tau.comparable.c_str());
      k.marks.push_back({z.day, z.id, "CF2", b, EV_CF2});
    }
    HrKinMetric t1 = eval_metric(ok, i, c, "THR100", "RC1", "s", true);
    if (t1.marked) {
      snprintf(b, sizeof(b), "la FC tarda más en bajar de 100 lpm: %.0f s frente a %.0f s de mediana propia (%+.0f %%, %d sesiones con %s); sin calibrar",
               t1.last, t1.baseline, t1.change, t1.n, t1.comparable.c_str());
      k.marks.push_back({z.day, z.id, "RC1", b, EV_RC1});
    }
    HrKinMetric fw = eval_metric(ok, i, c, "FC_TRAMO_FIJO", "FW1", "lpm", false);
    if (fw.marked) {
      snprintf(b, sizeof(b), "FC del tramo fijo del calentamiento %.0f lpm, %+.0f lpm sobre su mediana propia (%.0f lpm, %d sesiones con %s); "
               "comprobar calor, excitación o la colocación de los electrodos; sin calibrar", fw.last, fw.change, fw.baseline, fw.n, fw.comparable.c_str());
      k.marks.push_back({z.day, z.id, "FW1", b, EV_FW1});
    }
  }
  if (std::isfinite(s.cardio.thr100_s) && s.cardio.thr100_s > 200)
    k.notes.push_back("THR100 por encima de 200 s: en la JRA se considera carga alta (referencia institucional, no una alerta)");
  if (!std::isfinite(s.cardio.tau_s))
    k.notes.push_back("sin τ en la última sesión: hace falta grabar ≥ 10 min tras el esfuerzo con el ECG puesto");
  if (!std::isfinite(s.cardio.fw_hr))
    k.notes.push_back("sin tramo fijo en la última sesión: ≥ 60 s de trote estable (3–6 m/s) antes del trabajo rápido");
  return k;
}

std::string training_hr_kinetics_json(const HrKinetics& k, const TrainingConfig& c) {
  const auto& P = c.hrkin;
  std::ostringstream o;
  o << "{\"reglas\":[\"CF2\",\"RC1\",\"FW1\",\"WU3\"],\"disponible\":" << (k.available ? "true" : "false")
    << ",\"nivel\":\"INFO\",\"validado\":false,\"motivo\":" << q(k.reason)
    << ",\"parametros\":{\"dias_ventana\":" << P.window_days << ",\"min_comparables\":" << P.min_baseline << ",\"max_comparables\":" << P.max_baseline
    << ",\"tau_subida_pct\":" << num(P.tau_rise_pct) << ",\"thr100_subida_pct\":" << num(P.thr100_rise_pct) << ",\"tramo_fijo_subida_lpm\":" << num(P.fw_hr_rise_bpm)
    << ",\"tramo_fijo_dif_v_m_s\":" << num(P.fw_speed_match_m_s) << ",\"calentamiento_dif_pct\":" << num(P.warmup_match_pct) << ",\"dias_marcas\":" << P.marks_days
    << ",\"etiquetas\":{\"tau_subida\":\"I\",\"thr100_subida\":\"I\",\"thr100_referencia_200_s\":\"OFICIAL\",\"tramo_fijo_subida\":\"I\",\"tramo_fijo_dif_v\":\"I\","
       "\"calentamiento_dif\":\"I\",\"min_comparables\":\"E-r\",\"ventana\":\"I\"}}"
    << ",\"sesiones_ecg\":" << k.ecg_sessions << ",\"ultima\":";
  if (!k.available) o << "null";
  else {
    o << "{\"id\":" << q(k.last_id) << ",\"fecha\":" << q(training_day_text(k.last_day)) << ",\"vuelta_calma\":" << q(k.cooldown_class)
      << ",\"calentamiento_m\":" << num(k.warmup_m, 0) << ",\"calentamiento_s\":" << num(k.warmup_s, 0) << ",\"metricas\":[";
    for (size_t i = 0; i < k.metrics.size(); i++) {
      const HrKinMetric& m = k.metrics[i];
      o << (i ? "," : "") << "{\"metrica\":" << q(m.metric) << ",\"regla\":" << q(m.rule) << ",\"unidad\":" << q(m.unit)
        << ",\"valor\":" << num(m.last, 1) << ",\"mediana\":" << num(m.baseline, 1) << ",\"mad\":" << num(m.mad, 1) << ",\"n\":" << m.n
        << ",\"cambio\":" << num(m.change, 1) << ",\"cambio_unidad\":" << (m.rule == "FW1" ? "\"lpm\"" : "\"%\"")
        << ",\"comparables\":" << q(m.comparable) << ",\"marcada\":" << (m.marked ? "true" : "false") << "}";
    }
    o << "]}";
  }
  o << ",\"marcas\":[";
  for (size_t i = 0; i < k.marks.size(); i++)
    o << (i ? "," : "") << "{\"fecha\":" << q(training_day_text(k.marks[i].day)) << ",\"id\":" << q(k.marks[i].id) << ",\"regla\":" << q(k.marks[i].rule)
      << ",\"nivel\":\"INFO\",\"texto\":" << q(k.marks[i].text) << ",\"evidencia\":" << q(k.marks[i].evidence) << "}";
  o << "],\"notas\":[";
  for (size_t i = 0; i < k.notes.size(); i++) o << (i ? "," : "") << q(k.notes[i]);
  o << "],\"nota\":\"tendencia del propio caballo, sin calibrar; no sube el estado ni es un diagnóstico\"}";
  return o.str();
}

}  // namespace avoeq
