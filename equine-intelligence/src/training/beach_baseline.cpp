// Línea base de la playa por franja (TRAINING 1.5.0, KB 1.32.0, motor 2.0.0-dev39): PL2–PL6 de la base científica.
//  PL2  registro del suelo (humedad TDR, lluvia 48 h, nota del jinete) y clase de humedad SECA / MEDIA / HUMEDA (cortes de
//       Pfau 2024 en tierra [E]; su uso en playa [I])
//  PL3  zancada y frecuencia con la velocidad como covariable y la franja como efecto fijo (pendiente común dentro de
//       franja; sin pares suficientes, la de Pfau 2024 [E]: +0,359 m y +0,018 Hz por m/s)
//  PL4  impactos atípicos de la cincha por km relativos a la mediana de su franja [I]
//  PL5  línea base por franja utilizable con ≥ 4 sesiones (4–6 [I]); A9 compara solo la misma franja (training.cpp)
//  PL6  marcas: rápido en orilla muy compactada, cambio de franja durante el galope y entre rápidos seguidos [E]/[I]
// Todo es descriptivo y SIN CALIBRAR: las marcas son INFO y nunca cambian el estado del caballo. No es una predicción
// de lesiones.
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <map>
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
BeachStat stat(const std::vector<double>& v) {
  BeachStat s; s.n = (int)v.size();
  if (v.empty()) return s;
  s.median = med(v);
  std::vector<double> d; for (double x : v) d.push_back(std::fabs(x - s.median));
  s.mad = med(d);
  return s;
}
const char* band_reading(const std::string& b) {
  if (b == "ORILLA_FIRME") return "la más parecida a la pista";
  if (b == "SECA_PROFUNDA") return "trabajo de fuerza: no comparar con la pista ni con la orilla";
  if (b == "HUMEDA_PROFUNDA") return "arena profunda: apoyo más largo y menos impacto";
  if (b == "TRANSICION") return "mezcla de suelos: comparar con cautela";
  return "";
}
std::string band_text(const std::string& b) {
  if (b == "ORILLA_FIRME") return "orilla firme";
  if (b == "HUMEDA_PROFUNDA") return "arena húmeda profunda";
  if (b == "SECA_PROFUNDA") return "arena seca profunda";
  if (b == "TRANSICION") return "transición";
  return b;
}
bool fast(const SessionSummary& s, const TrainingConfig& c) {
  return s.race.present && ((std::isfinite(s.race.kb_gallop_m) && s.race.kb_gallop_m >= c.kb.gallop_session_min_m) || s.race.fast_efforts > 0);
}
double impacts_km(const SessionSummary& s) {
  if (!s.race.present || !(s.race.dist_work_m >= 200)) return NAN;
  return s.race.impacts / (s.race.dist_work_m / 1000.0);
}

}  // namespace

std::string training_soil_class(double pct, const TrainingConfig& c) {
  if (!std::isfinite(pct)) return "";
  return pct <= c.beach.soil_dry_max_pct ? "SECA" : pct > c.beach.soil_wet_min_pct ? "HUMEDA" : "MEDIA";
}

BeachBaseline training_beach_baseline(const std::vector<SessionSummary>& all, long at, const TrainingConfig& c) {
  BeachBaseline B;
  const auto& P = c.beach;
  if (!P.enabled) { B.reason = "desactivada en las opciones"; return B; }
  std::vector<const SessionSummary*> ok;
  for (const auto& s : all) if (!s.beach_band.empty() && s.day <= at && s.day > at - P.window_days) ok.push_back(&s);
  B.beach_sessions = (int)ok.size();
  if (ok.empty()) { B.reason = "sin sesiones de playa con franja (anotada o automática) en la ventana"; return B; }
  B.available = true;

  // ---- por franja (PL5)
  static const char* kBands[] = {"ORILLA_FIRME", "HUMEDA_PROFUNDA", "SECA_PROFUNDA", "TRANSICION"};
  std::map<std::string, std::vector<const SessionSummary*>> by;
  for (auto* s : ok) by[s->beach_band].push_back(s);
  for (const char* name : kBands) {
    auto it = by.find(name);
    if (it == by.end()) continue;
    BeachBandBaseline F; F.band = name;
    std::vector<double> sl, sf, v6, v2, ik, so;
    for (auto* s : it->second) {
      F.sessions++;
      (s->beach_band_auto ? F.auto_n : F.manual_n)++;
      if (fast(*s, c)) F.fast_sessions++;
      F.last_day = std::max(F.last_day, s->day);
      if (s->race.present) {
        if (std::isfinite(s->race.sl_ref[0])) sl.push_back(s->race.sl_ref[0]);
        if (std::isfinite(s->race.sf_ref[0])) sf.push_back(s->race.sf_ref[0]);
        if (std::isfinite(s->race.v_last_600)) v6.push_back(s->race.v_last_600);
      }
      if (s->cardio.present && std::isfinite(s->cardio.v200)) v2.push_back(s->cardio.v200);
      double k = impacts_km(*s); if (std::isfinite(k)) ik.push_back(k);
      if (std::isfinite(s->soil_moisture_pct)) so.push_back(s->soil_moisture_pct);
    }
    F.stride = stat(sl); F.freq = stat(sf); F.v600 = stat(v6); F.v200 = stat(v2); F.impacts_km = stat(ik); F.soil = stat(so);
    F.usable = F.sessions >= P.min_sessions_band;
    B.bands.push_back(F);
  }

  // ---- PL3: pendiente común dentro de franja (efecto fijo de la franja) con los pares (v_ref, zancada, frecuencia)
  struct Pair { double v, sl, sf; };
  std::map<std::string, std::vector<Pair>> pairs;
  std::vector<double> all_v;
  for (auto* s : ok) {
    if (!s->race.present) continue;
    for (int k = 0; k < 2; k++)
      if (std::isfinite(s->race.ref_speed[k]) && std::isfinite(s->race.sl_ref[k]) && std::isfinite(s->race.sf_ref[k])) {
        pairs[s->beach_band].push_back({s->race.ref_speed[k], s->race.sl_ref[k], s->race.sf_ref[k]});
        all_v.push_back(s->race.ref_speed[k]);
      }
  }
  double sxx = 0, sxy = 0, sxf = 0; int np = 0;
  for (auto& F : B.bands) {
    auto& v = pairs[F.band];
    F.pairs = (int)v.size();
    if (v.empty()) continue;
    double mv = 0, ms = 0, mf = 0;
    for (auto& p : v) { mv += p.v; ms += p.sl; mf += p.sf; }
    mv /= v.size(); ms /= v.size(); mf /= v.size();
    F.v_mean = mv; F.sl_mean = ms; F.sf_mean = mf;
    for (auto& p : v) { sxx += (p.v - mv) * (p.v - mv); sxy += (p.v - mv) * (p.sl - ms); sxf += (p.v - mv) * (p.sf - mf); np++; }
  }
  B.pairs = np;
  B.slope_sl = P.slope_sl_prior; B.slope_sf = P.slope_sf_prior; B.slope_origin = "PFAU_2024";
  if (np >= P.min_pairs_own_slope && sxx / np >= P.min_speed_sd * P.min_speed_sd) {
    double bl = sxy / sxx, bf = sxf / sxx;
    if (bl >= 0 && bl <= 1.0 && bf >= -0.1 && bf <= 0.2) { B.slope_sl = bl; B.slope_sf = bf; B.slope_origin = "PROPIA"; }
    else B.notes.push_back("pendiente propia fuera de rango (zancada " + num(bl) + " m por m/s): se usa la de Pfau 2024");
  } else if (np > 0)
    B.notes.push_back("pocos pares o poca dispersión de velocidad dentro de franja para la pendiente propia: se usa la de Pfau 2024 (PSI en tierra, [E])");
  B.v_common = med(all_v);
  for (auto& F : B.bands)
    if (F.pairs > 0) { F.sl_adj = F.sl_mean + B.slope_sl * (B.v_common - F.v_mean); F.sf_adj = F.sf_mean + B.slope_sf * (B.v_common - F.v_mean); }
  // franja de referencia: ORILLA_FIRME si es utilizable; si no, la utilizable con más sesiones
  const BeachBandBaseline* ref = nullptr;
  for (auto& F : B.bands) if (F.band == "ORILLA_FIRME" && F.usable && F.pairs > 0) ref = &F;
  if (!ref) for (auto& F : B.bands) if (F.usable && F.pairs > 0 && (!ref || F.sessions > ref->sessions)) ref = &F;
  if (ref) {
    B.ref_band = ref->band;
    double rl = ref->sl_adj, rf = ref->sf_adj;
    for (auto& F : B.bands)
      if (F.usable && F.pairs > 0) { F.sl_effect_m = F.sl_adj - rl; F.sf_effect_hz = F.sf_adj - rf; }
  } else B.notes.push_back("ninguna franja con " + std::to_string(P.min_sessions_band) + " sesiones y zancada: sin efecto de franja (PL3)");

  // ---- última sesión de playa (PL2, PL4)
  const SessionSummary* last = ok.back();
  B.last_id = last->id; B.last_band = last->beach_band; B.last_day = last->day;
  B.last_soil_class = training_soil_class(last->soil_moisture_pct, c);
  B.last_impacts_km = impacts_km(*last);
  for (auto& F : B.bands)
    if (F.band == last->beach_band && F.usable && F.impacts_km.n >= P.min_sessions_band && F.impacts_km.median > 0 && std::isfinite(B.last_impacts_km))
      B.last_impacts_rel = B.last_impacts_km / F.impacts_km.median;
  for (auto* s : ok) if (s->day > at - 7 && s->beach_band == "ORILLA_FIRME" && fast(*s, c)) B.fast_firm_7d++;

  // ---- marcas PL2/PL6 (sesiones de los últimos marks_days días)
  char b[400];
  const SessionSummary* prev_fast = nullptr;
  for (auto* s : ok) {
    bool f = fast(*s, c);
    bool recent = s->day > at - P.marks_days;
    if (recent && f && s->beach_band == "ORILLA_FIRME") {
      bool soil = std::isfinite(s->soil_moisture_pct) && s->soil_moisture_pct <= P.compact_soil_max_pct;
      bool hard = s->ground_note == "DURO";
      if (soil || hard) {
        snprintf(b, sizeof(b), "trabajo rápido en orilla muy compactada (%s%s%s): más carga en el apoyo que en la orilla habitual; "
                 "marca informativa sin calibrar", soil ? ("humedad " + num(s->soil_moisture_pct, 1) + " %").c_str() : "",
                 soil && hard ? ", " : "", hard ? "el jinete la anota DURA" : "");
        B.marks.push_back({s->day, s->id, "PL6_RAPIDO_ORILLA_COMPACTA", b,
                           "White Paper de superficies 2012 [E]: la dureza sube con la compactación; corte de humedad ≤ 13 % (Pfau 2024 en tierra [E], en playa [I]); sin calibrar"});
      }
    }
    if (recent && f && s->beach_band_auto && std::isfinite(s->beach_band_pct) && s->beach_band_pct < P.band_pct_min) {
      snprintf(b, sizeof(b), "trabajo rápido repartido entre franjas (solo el %.0f %% en %s): cambio de suelo durante el galope; "
               "la sesión no es del todo comparable con su franja", s->beach_band_pct, band_text(s->beach_band).c_str());
      B.marks.push_back({s->day, s->id, "PL6_CAMBIO_FRANJA_EN_GALOPE", b,
                         "White Paper de superficies 2012 [E]: el cambio de superficie a máxima intensidad está documentado como problema; corte del 70 % [I]"});
    }
    if (f) {
      if (recent && prev_fast && prev_fast->beach_band != s->beach_band && s->day - prev_fast->day <= P.band_change_days) {
        snprintf(b, sizeof(b), "rápido en %s tras el de hace %ld días en %s: cambio brusco de franja; no comparar zancada, velocidad ni V200 "
                 "entre las dos sesiones", band_text(s->beach_band).c_str(), s->day - prev_fast->day, band_text(prev_fast->beach_band).c_str());
        B.marks.push_back({s->day, s->id, "PL6_CAMBIO_FRANJA", b, "Pfau 2024 [E]: el suelo cambia la zancada hasta 18,6 cm a igual velocidad; ventana de 7 días [I]"});
      }
      prev_fast = s;
    }
    if (recent && std::isfinite(s->rain_48h_mm) && s->rain_48h_mm >= P.rain_recent_mm) {
      snprintf(b, sizeof(b), "%.0f mm de lluvia en las 48 h anteriores: el suelo de la %s puede estar distinto del de sus comparables", s->rain_48h_mm, band_text(s->beach_band).c_str());
      B.marks.push_back({s->day, s->id, "PL2_LLUVIA_RECIENTE", b, "White Paper de superficies 2012 [E]: la humedad es la variable más importante del suelo; corte de 5 mm [I]"});
    }
  }
  int missing_soil = 0;
  for (auto* s : ok) if (!std::isfinite(s->soil_moisture_pct)) missing_soil++;
  if (missing_soil == (int)ok.size())
    B.notes.push_back("sin humedad del suelo anotada (PL2): la franja sola separa los suelos; anotar 3–5 lecturas de sonda TDR si la cuadra la tiene");
  return B;
}

std::string training_beach_json(const BeachBaseline& B, const TrainingConfig& c) {
  const auto& P = c.beach;
  std::ostringstream o;
  auto st = [&](const BeachStat& s, int dec) {
    return "{\"mediana\":" + num(s.median, dec) + ",\"mad\":" + num(s.mad, dec) + ",\"n\":" + std::to_string(s.n) + "}";
  };
  o << "{\"reglas\":[\"PL2\",\"PL3\",\"PL4\",\"PL5\",\"PL6\"],\"disponible\":" << (B.available ? "true" : "false")
    << ",\"nivel\":\"INFO\",\"validado\":false,\"motivo\":" << q(B.reason)
    << ",\"parametros\":{\"dias_ventana\":" << P.window_days << ",\"min_sesiones_franja\":" << P.min_sessions_band
    << ",\"pendiente_zancada_previa_m_por_m_s\":" << num(P.slope_sl_prior) << ",\"pendiente_frecuencia_previa_hz_por_m_s\":" << num(P.slope_sf_prior)
    << ",\"min_pares_pendiente_propia\":" << P.min_pairs_own_slope << ",\"dispersion_v_min_m_s\":" << num(P.min_speed_sd)
    << ",\"humedad_seca_max_pct\":" << num(P.soil_dry_max_pct) << ",\"humedad_humeda_min_pct\":" << num(P.soil_wet_min_pct)
    << ",\"humedad_compacta_max_pct\":" << num(P.compact_soil_max_pct) << ",\"franja_dominante_min_pct\":" << num(P.band_pct_min)
    << ",\"dias_cambio_franja\":" << P.band_change_days << ",\"lluvia_reciente_mm\":" << num(P.rain_recent_mm) << ",\"dias_marcas\":" << P.marks_days
    << ",\"etiquetas\":{\"pendientes_previas\":\"E\",\"min_sesiones_franja\":\"I\",\"cortes_humedad\":\"I\",\"humedad_compacta\":\"I\","
       "\"franja_dominante_min\":\"I\",\"dias_cambio_franja\":\"I\",\"lluvia_reciente\":\"I\",\"impacto_relativo\":\"I\",\"efecto_fijo_franja\":\"I\"}}"
    << ",\"sesiones_playa\":" << B.beach_sessions << ",\"franja_referencia\":" << q(B.ref_band)
    << ",\"pl3\":{\"pendiente_zancada_m_por_m_s\":" << num(B.slope_sl) << ",\"pendiente_frecuencia_hz_por_m_s\":" << num(B.slope_sf, 4)
    << ",\"origen_pendiente\":" << q(B.slope_origin) << ",\"pares\":" << B.pairs << ",\"velocidad_comun_m_s\":" << num(B.v_common, 2) << "}"
    << ",\"franjas\":[";
  for (size_t i = 0; i < B.bands.size(); i++) {
    const BeachBandBaseline& F = B.bands[i];
    o << (i ? "," : "") << "{\"franja\":" << q(F.band) << ",\"lectura\":" << q(band_reading(F.band)) << ",\"sesiones\":" << F.sessions
      << ",\"automaticas\":" << F.auto_n << ",\"anotadas\":" << F.manual_n << ",\"rapidas\":" << F.fast_sessions
      << ",\"ultima\":" << (F.last_day < 0 ? std::string("null") : q(training_day_text(F.last_day)))
      << ",\"linea_base_utilizable\":" << (F.usable ? "true" : "false")
      << ",\"zancada_ref_m\":" << st(F.stride, 3) << ",\"frecuencia_ref_hz\":" << st(F.freq, 3) << ",\"v_ultimos_600m_m_s\":" << st(F.v600, 2)
      << ",\"v200_m_s\":" << st(F.v200, 2) << ",\"impactos_por_km\":" << st(F.impacts_km, 2) << ",\"humedad_suelo_pct\":" << st(F.soil, 1)
      << ",\"pares\":" << F.pairs << ",\"zancada_ajustada_m\":" << num(F.sl_adj) << ",\"frecuencia_ajustada_hz\":" << num(F.sf_adj)
      << ",\"efecto_zancada_m\":" << num(F.sl_effect_m) << ",\"efecto_frecuencia_hz\":" << num(F.sf_effect_hz) << "}";
  }
  o << "],\"ultima_sesion\":";
  if (B.last_day < 0) o << "null";
  else o << "{\"id\":" << q(B.last_id) << ",\"fecha\":" << q(training_day_text(B.last_day)) << ",\"franja\":" << q(B.last_band)
         << ",\"clase_humedad\":" << q(B.last_soil_class) << ",\"impactos_por_km\":" << num(B.last_impacts_km, 2)
         << ",\"impacto_relativo_franja\":" << num(B.last_impacts_rel, 2) << "}";
  o << ",\"rapidos_orilla_firme_7d\":" << B.fast_firm_7d << ",\"marcas\":[";
  for (size_t i = 0; i < B.marks.size(); i++) {
    const BeachMark& m = B.marks[i];
    o << (i ? "," : "") << "{\"fecha\":" << q(training_day_text(m.day)) << ",\"id\":" << q(m.id) << ",\"regla\":" << q(m.rule)
      << ",\"nivel\":\"INFO\",\"texto\":" << q(m.text) << ",\"evidencia\":" << q(m.evidence) << "}";
  }
  o << "],\"notas\":[";
  for (size_t i = 0; i < B.notes.size(); i++) o << (i ? "," : "") << q(B.notes[i]);
  o << "],\"nota\":\"línea base de la playa por franja sin calibrar: descriptiva, no cambia el estado y no es una predicción de lesiones\"}";
  return o.str();
}

}  // namespace avoeq
