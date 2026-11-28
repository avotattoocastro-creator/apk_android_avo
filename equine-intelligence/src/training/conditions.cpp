// Comparables por condiciones en la historia (TRAINING 1.7.0, KB 1.34.0, motor 2.0.0-dev41).
//  TC1  temperatura, humedad y WBGT de la ficha de campo; WBGT estimado con la aproximación del Bureau of Meteorology
//       de Australia si solo hay temperatura y humedad (supone sol y brisa ligera; tiende a sobrestimar) [E-r/I].
//  TC2  A9 (V200/VHRmax) y la cinética de la FC (CF2, RC1, FW1) solo con |ΔT| ≤ 5 °C [I].
//  TC3  «no comparable por calor» con WBGT ≥ 28 °C, o ≥ 30 °C con humedad ≥ 70 % [I]: el calor húmedo sube la FC
//       submáxima (≈ +12 lpm a 7 m/s, Hargreaves 1999 [E-r]) sin cambiar la FC de pico (Ebisuda 2023 [E]), así que la
//       V200 baja sin pérdida de forma. A9 no juzga esas sesiones; las de calor solo se comparan entre sí.
//  TC4  primeros 10 días de un periodo de calor = transición de aclimatación (Geor 1996 [E-r]; corte [I]).
//  PC2  A7 y A8 solo con |Δpeso del jinete con equipo| ≤ 3 kg y el mismo jinete si hay comparables suficientes [I].
//  PC3  peso cargado / peso corporal > 13 % = INFO (límite de los datos de Lee & Park 2011 [E]); no es un umbral de riesgo.
//  GO1  mismo estrato de going (FIRME = firme y bueno-firme; BUENO; BLANDO = bueno-blando y blando; PESADO) en A7, A8,
//       A9 y la cinética de la FC [I]; la zancada corta en blando no es fatiga (GO2).
// Sin el dato en alguna de las dos sesiones, la comparación se mantiene (análisis anteriores). Sin coeficiente de
// corrección (TC5, PC4). Todo SIN CALIBRAR: marcas INFO que nunca cambian el estado del caballo. No es un diagnóstico.
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
std::string surf_of(const SessionSummary& s) { return s.surface + "|" + s.beach_band; }
bool warmup_similar(double ref_m, double other_m, double pct) {
  if (!(pct > 0) || !std::isfinite(ref_m) || !std::isfinite(other_m) || !(ref_m > 0)) return true;
  return std::fabs(other_m - ref_m) <= pct / 100.0 * ref_m;
}

const char* const EV_TC3 = "TC3 [I] (estudio 20/11 13:12): calor húmedo sube la FC submáxima ≈ +12 lpm a 7 m/s (Hargreaves 1999 [E-r]) sin "
                           "cambiar la FC de pico (Ebisuda 2023 [E]); WBGT 28 °C = norma citada por Nomura 2019 [E-r]; corte sin calibrar";
const char* const EV_TC4 = "TC4 [I]: aclimatación al calor en unos 10 días (Geor 1996 [E-r]); 10–14 d sin calibrar";
const char* const EV_PC3 = "PC3 [I]: mejores tiempos con peso cargado / peso corporal ≈ 12–12,7 % y peor por encima en PSI de Corea "
                           "(Lee & Park 2011 [E]); 13 % solo informativo, no es un umbral de riesgo";

}  // namespace

double training_wbgt_estimate(double t, double rh) {
  if (!std::isfinite(t) || !std::isfinite(rh) || rh < 0 || rh > 100) return NAN;
  double e = rh / 100.0 * 6.105 * std::exp(17.27 * t / (237.7 + t));   // presión de vapor (hPa)
  return 0.567 * t + 0.393 * e + 3.94;
}

std::string training_going_stratum(const std::string& g) {
  if (g == "FIRME" || g == "BUENO_FIRME") return "FIRME";
  if (g == "BUENO") return "BUENO";
  if (g == "BUENO_BLANDO" || g == "BLANDO") return "BLANDO";
  if (g == "PESADO") return "PESADO";
  return "";
}

CondInfo training_condition_info(const SessionSummary& s, const TrainingConfig& c) {
  const auto& P = c.cond;
  CondInfo ci;
  if (std::isfinite(s.wbgt_c)) { ci.wbgt = s.wbgt_c; ci.wbgt_origin = "MEDIDO"; }
  else if (P.wbgt_estimate) {
    ci.wbgt = training_wbgt_estimate(s.temperature_c, s.humidity_pct);
    if (std::isfinite(ci.wbgt)) ci.wbgt_origin = "ESTIMADO_T_HR";
  }
  bool hot = false, known = false;
  if (std::isfinite(ci.wbgt)) { known = true; hot = ci.wbgt >= P.wbgt_heat_c; }
  if (std::isfinite(s.temperature_c)) {
    known = true;
    // ≥ 30 °C con humedad ≥ 70 %; sin humedad anotada, ≥ 30 °C cuenta como calor (prudente para A9) [I]
    if (s.temperature_c >= P.heat_temp_c && (!std::isfinite(s.humidity_pct) || s.humidity_pct >= P.heat_humidity_pct)) hot = true;
  }
  if (known) ci.heat = hot ? "CALOR" : "NORMAL";
  ci.going_stratum = training_going_stratum(s.going);
  if (std::isfinite(s.rider_kg) && std::isfinite(s.horse_kg) && s.horse_kg > 0) ci.cwbw_pct = 100.0 * s.rider_kg / s.horse_kg;
  return ci;
}

bool training_conditions_comparable(const SessionSummary& ref, const SessionSummary& z, CondUse use, const TrainingConfig& c, std::string* why) {
  const auto& P = c.cond;
  if (!P.enabled) return true;
  auto fail = [&](const char* w) { if (why) *why = w; return false; };
  CondInfo a = training_condition_info(ref, c), b = training_condition_info(z, c);
  if (use == CondUse::FC) {
    if (!a.heat.empty() && !b.heat.empty() && a.heat != b.heat) return fail("CALOR");
    if (std::isfinite(ref.temperature_c) && std::isfinite(z.temperature_c) && std::fabs(ref.temperature_c - z.temperature_c) > P.temp_match_c)
      return fail("TEMPERATURA");
  }
  if (P.going_strata && !a.going_stratum.empty() && !b.going_stratum.empty() && a.going_stratum != b.going_stratum) return fail("GOING");
  if (use == CondUse::MECANICA && std::isfinite(ref.rider_kg) && std::isfinite(z.rider_kg) && std::fabs(ref.rider_kg - z.rider_kg) > P.weight_match_kg)
    return fail("PESO");
  return true;
}

std::vector<size_t> training_comparables(const std::vector<SessionSummary>& ok, size_t i, CondUse use,
                                         const std::function<bool(const SessionSummary&)>& base, const TrainingConfig& c,
                                         int rider_min, CondCount* cnt) {
  CondCount k;
  std::vector<size_t> kept;
  for (size_t j = 0; j <= i && j < ok.size(); j++) {
    if (!base(ok[j])) continue;
    k.base++;
    std::string why;
    if (j == i || training_conditions_comparable(ok[i], ok[j], use, c, &why)) { kept.push_back(j); continue; }
    if (why == "TEMPERATURA") k.temperature++;
    else if (why == "CALOR") k.heat++;
    else if (why == "GOING") k.going++;
    else if (why == "PESO") k.weight++;
  }
  if (use == CondUse::MECANICA && rider_min > 0 && c.cond.enabled && c.cond.prefer_same_rider && i < ok.size() && !ok[i].rider.empty()) {
    std::vector<size_t> same;
    for (size_t j : kept) if (ok[j].rider == ok[i].rider) same.push_back(j);
    if ((int)same.size() >= rider_min && same.size() < kept.size()) {
      k.rider = (int)(kept.size() - same.size());
      kept = same;
      k.same_rider = true;
    } else if ((int)same.size() >= rider_min) k.same_rider = true;
  }
  k.kept = (int)kept.size();
  if (cnt) *cnt = k;
  return kept;
}

ConditionsStatus training_conditions(const std::vector<SessionSummary>& ok, long at, const TrainingConfig& c) {
  ConditionsStatus k;
  const auto& P = c.cond;
  if (!P.enabled) { k.reason = "desactivada por opción"; return k; }
  long last_i = -1;
  for (size_t i = 0; i < ok.size(); i++) { if (ok[i].day > at) break; last_i = (long)i; }
  if (last_i < 0) { k.reason = "ninguna sesión hasta la fecha de referencia"; return k; }
  const SessionSummary& s = ok[last_i];
  k.available = true;
  k.last_id = s.id; k.last_day = s.day; k.rider = s.rider; k.going = s.going;
  k.temperature_c = s.temperature_c; k.humidity_pct = s.humidity_pct; k.rider_kg = s.rider_kg; k.horse_kg = s.horse_kg;
  k.info = training_condition_info(s, c);
  const auto& kc = c.kb;
  size_t li = (size_t)last_i;
  // recuento de comparables de la última sesión por regla (incluye la propia sesión)
  if (s.cardio.present && std::isfinite(s.cardio.v200) && !s.cardio.v200_method.empty()) {
    CondRule r; r.rule = "A9"; r.metric = "V200";
    training_comparables(ok, li, CondUse::FC, [&](const SessionSummary& z) {
      return z.cardio.present && surf_of(z) == surf_of(s) && z.cardio.v200_method == s.cardio.v200_method && std::isfinite(z.cardio.v200) &&
             warmup_similar(s.cardio.warmup_m, z.cardio.warmup_m, kc.v200_warmup_match_pct); }, c, 0, &r.count);
    k.rules.push_back(r);
  }
  int rider_min = kc.drift_min_baseline + 3;
  if (s.race.present && std::isfinite(s.race.sl_ref[0])) {
    CondRule r; r.rule = "A7"; r.metric = "ZANCADA_V_REF_1";
    training_comparables(ok, li, CondUse::MECANICA, [&](const SessionSummary& z) {
      return z.race.present && surf_of(z) == surf_of(s) && std::isfinite(z.race.sl_ref[0]); }, c, rider_min, &r.count);
    k.rules.push_back(r);
  }
  if (s.race.present && std::isfinite(s.race.v_last_600)) {
    CondRule r; r.rule = "A8"; r.metric = "V_ULTIMOS_600";
    training_comparables(ok, li, CondUse::MECANICA, [&](const SessionSummary& z) {
      return z.race.present && surf_of(z) == surf_of(s) && std::isfinite(z.race.v_last_600); }, c, rider_min, &r.count);
    k.rules.push_back(r);
  }
  if (s.cardio.present && std::isfinite(s.cardio.tau_s)) {
    CondRule r; r.rule = "CF2"; r.metric = "TAU_RECUPERACION";
    training_comparables(ok, li, CondUse::FC, [&](const SessionSummary& z) {
      return z.cardio.present && std::isfinite(z.cardio.tau_s) && s.day - z.day <= c.hrkin.window_days && surf_of(z) == surf_of(s) &&
             !z.cardio.cooldown_class.empty() && z.cardio.cooldown_class == s.cardio.cooldown_class &&
             warmup_similar(s.cardio.warmup_m, z.cardio.warmup_m, c.hrkin.warmup_match_pct); }, c, 0, &r.count);
    k.rules.push_back(r);
  }
  // TC4: día del periodo de calor de la última sesión
  auto acclim = [&](size_t i) {
    if (training_condition_info(ok[i], c).heat != "CALOR") return -1;
    long start = ok[i].day, prev = ok[i].day;
    for (size_t j = i; j-- > 0;) {
      if (training_condition_info(ok[j], c).heat != "CALOR") continue;
      if (prev - ok[j].day > P.heat_gap_days) break;
      start = prev = ok[j].day;
    }
    return (int)(ok[i].day - start + 1);
  };
  k.acclim_day = acclim(li);
  // marcas de los últimos marks_days días
  char b[420];
  for (size_t i = 0; i <= li; i++) {
    const SessionSummary& z = ok[i];
    if (at - z.day > P.marks_days) continue;
    CondInfo ci = training_condition_info(z, c);
    if (ci.heat == "CALOR") {
      if (std::isfinite(ci.wbgt))
        snprintf(b, sizeof(b), "sesión con calor (WBGT %.1f °C, %s; %s): la FC a igual velocidad sube y la V200 baja sin pérdida de forma; "
                 "A9 no la compara con sesiones frescas; sin calibrar", ci.wbgt, ci.wbgt_origin == "MEDIDO" ? "medido" : "estimado con T y humedad",
                 std::isfinite(z.temperature_c) ? (num(z.temperature_c, 1) + " °C").c_str() : "sin temperatura");
      else
        snprintf(b, sizeof(b), "sesión con calor (%.1f °C, humedad sin anotar): A9 no la compara con sesiones frescas; sin calibrar", z.temperature_c);
      k.marks.push_back({z.day, z.id, "TC3", b, EV_TC3});
      int d = acclim(i);
      if (d >= 1 && d <= P.acclim_days) {
        snprintf(b, sizeof(b), "día %d de un periodo de calor: el caballo aún se está aclimatando (≈ %d días); la FC puede ser más alta que "
                 "dentro de una semana con el mismo calor; sin calibrar", d, P.acclim_days);
        k.marks.push_back({z.day, z.id, "TC4", b, EV_TC4});
      }
    }
    if (std::isfinite(ci.cwbw_pct) && ci.cwbw_pct > P.cwbw_info_pct) {
      snprintf(b, sizeof(b), "peso del jinete con equipo %.1f kg sobre %.0f kg del caballo = %.1f %% (más del %.0f %%): solo informativo, "
               "no es un umbral de riesgo", z.rider_kg, z.horse_kg, ci.cwbw_pct, P.cwbw_info_pct);
      k.marks.push_back({z.day, z.id, "PC3", b, EV_PC3});
    }
  }
  if (!std::isfinite(s.temperature_c) && !std::isfinite(s.wbgt_c))
    k.notes.push_back("sin temperatura en la última sesión: A9 y la recuperación se comparan sin criterio de temperatura (TC1: anotarla en la ficha de campo)");
  else if (!std::isfinite(s.humidity_pct) && !std::isfinite(s.wbgt_c))
    k.notes.push_back("sin humedad en la última sesión: no se estima el WBGT; con ≥ 30 °C se trata como calor");
  if (!std::isfinite(s.rider_kg)) k.notes.push_back("sin peso del jinete con equipo: A7 y A8 se comparan sin criterio de peso (PC1)");
  if (s.rider.empty()) k.notes.push_back("sin jinete anotado: no se puede preferir el mismo jinete en A7 y A8 (PC2)");
  if (k.info.going_stratum.empty()) k.notes.push_back("sin going anotado: las comparables no se separan por estado del terreno (GO1)");
  if (k.info.wbgt_origin == "ESTIMADO_T_HR")
    k.notes.push_back("WBGT estimado con temperatura y humedad (aproximación del Bureau of Meteorology: supone sol y brisa ligera y tiende a "
                      "sobrestimar); un WBGT medido en la ficha lo sustituye");
  return k;
}

std::string training_condition_info_json(const CondInfo& ci) {
  std::ostringstream o;
  o << "{\"wbgt_c\":" << num(ci.wbgt, 1) << ",\"wbgt_origen\":" << q(ci.wbgt_origin) << ",\"calor\":" << q(ci.heat)
    << ",\"estrato_going\":" << q(ci.going_stratum) << ",\"peso_cargado_pct\":" << num(ci.cwbw_pct, 1) << "}";
  return o.str();
}

std::string training_conditions_json(const ConditionsStatus& k, const TrainingConfig& c) {
  const auto& P = c.cond;
  std::ostringstream o;
  o << "{\"reglas\":[\"TC1\",\"TC2\",\"TC3\",\"TC4\",\"PC1\",\"PC2\",\"PC3\",\"GO1\"],\"disponible\":" << (k.available ? "true" : "false")
    << ",\"activa\":" << (P.enabled ? "true" : "false") << ",\"nivel\":\"INFO\",\"validado\":false,\"motivo\":" << q(k.reason)
    << ",\"parametros\":{\"temperatura_dif_c\":" << num(P.temp_match_c) << ",\"wbgt_calor_c\":" << num(P.wbgt_heat_c)
    << ",\"calor_temperatura_c\":" << num(P.heat_temp_c) << ",\"calor_humedad_pct\":" << num(P.heat_humidity_pct)
    << ",\"wbgt_estimado\":" << (P.wbgt_estimate ? "true" : "false") << ",\"dias_aclimatacion\":" << P.acclim_days
    << ",\"dias_corte_calor\":" << P.heat_gap_days << ",\"peso_dif_kg\":" << num(P.weight_match_kg)
    << ",\"mismo_jinete\":" << (P.prefer_same_rider ? "true" : "false") << ",\"peso_cargado_info_pct\":" << num(P.cwbw_info_pct)
    << ",\"estrato_going\":" << (P.going_strata ? "true" : "false") << ",\"dias_marcas\":" << P.marks_days
    << ",\"etiquetas\":{\"temperatura_dif\":\"I\",\"wbgt_calor\":\"E-r/I\",\"calor_temperatura_humedad\":\"E-r/I\",\"wbgt_estimado\":\"E-r/I\","
       "\"dias_aclimatacion\":\"E-r/I\",\"dias_corte_calor\":\"I\",\"peso_dif\":\"I\",\"mismo_jinete\":\"I\",\"peso_cargado_info\":\"E/I\","
       "\"estrato_going\":\"I\"}}"
    << ",\"ultima\":";
  if (!k.available) o << "null";
  else {
    o << "{\"id\":" << q(k.last_id) << ",\"fecha\":" << q(training_day_text(k.last_day)) << ",\"temperatura_c\":" << num(k.temperature_c, 1)
      << ",\"humedad_pct\":" << num(k.humidity_pct, 0) << ",\"going\":" << q(k.going) << ",\"jinete\":" << q(k.rider)
      << ",\"peso_jinete_kg\":" << num(k.rider_kg, 1) << ",\"peso_caballo_kg\":" << num(k.horse_kg, 0)
      << ",\"condiciones\":" << training_condition_info_json(k.info)
      << ",\"dia_periodo_calor\":" << (k.acclim_day < 0 ? std::string("null") : std::to_string(k.acclim_day)) << ",\"comparables\":[";
    for (size_t i = 0; i < k.rules.size(); i++) {
      const CondRule& r = k.rules[i];
      const CondCount& n = r.count;
      o << (i ? "," : "") << "{\"regla\":" << q(r.rule) << ",\"metrica\":" << q(r.metric) << ",\"sesiones_base\":" << n.base
        << ",\"sesiones_comparables\":" << n.kept << ",\"excluidas\":{\"temperatura\":" << n.temperature << ",\"calor\":" << n.heat
        << ",\"going\":" << n.going << ",\"peso\":" << n.weight << ",\"otro_jinete\":" << n.rider << "},\"mismo_jinete\":"
        << (n.same_rider ? "true" : "false") << "}";
    }
    o << "]}";
  }
  o << ",\"marcas\":[";
  for (size_t i = 0; i < k.marks.size(); i++)
    o << (i ? "," : "") << "{\"fecha\":" << q(training_day_text(k.marks[i].day)) << ",\"id\":" << q(k.marks[i].id) << ",\"regla\":" << q(k.marks[i].rule)
      << ",\"nivel\":\"INFO\",\"texto\":" << q(k.marks[i].text) << ",\"evidencia\":" << q(k.marks[i].evidence) << "}";
  o << "],\"notas\":[";
  for (size_t i = 0; i < k.notes.size(); i++) o << (i ? "," : "") << q(k.notes[i]);
  o << "],\"nota\":\"solo filtra las sesiones comparables (las sesiones incluyen la evaluada); sin coeficiente de corrección y sin calibrar; "
       "no sube el estado ni es un diagnóstico\"}";
  return o.str();
}

}  // namespace avoeq
