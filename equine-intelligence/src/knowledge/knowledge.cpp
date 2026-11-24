// AVO Base científica de la cuadra (KB-1). Ver include/avo_eq/knowledge.h y docs/algoritmos/14_BASE_CIENTIFICA.md.
#include "avo_eq/knowledge.h"
#include <algorithm>
#include <cstdio>
#include <sstream>
#include "avo_eq/json.h"

namespace avoeq {

namespace {
const double kNaN = std::nan("");
std::string num(double v) {
  if (std::isnan(v) || std::isinf(v)) return "null";
  char b[40]; snprintf(b, sizeof(b), "%.6g", v); return b;
}
std::string q(const std::string& s) { return "\"" + json::escape(s) + "\""; }
double median_of(std::vector<double> v) {
  if (v.empty()) return kNaN;
  std::sort(v.begin(), v.end());
  size_t n = v.size();
  return n % 2 ? v[n / 2] : 0.5 * (v[n / 2 - 1] + v[n / 2]);
}
bool has_kb(const KbDay& s) { return !std::isnan(s.bone_pct) && !std::isnan(s.band_m[0]); }
}  // namespace

bool kb_final_speed(const std::vector<double>& t, const std::vector<double>& d, double D, double* time_s, double* speed) {
  if (!(D > 0) || t.size() != d.size() || t.size() < 2) return false;
  size_t first = t.size(), last = t.size();
  for (size_t i = 0; i < t.size(); i++)
    if (!std::isnan(d[i]) && !std::isnan(t[i])) { if (first == t.size()) first = i; last = i; }
  if (first == t.size() || last == first) return false;
  const double d_end = d[last], t_end = t[last], target = d_end - D;
  if (target < d[first] - 1e-9) return false;
  for (size_t i = last; i > first; i--) {
    size_t j = i - 1;
    while (j > first && (std::isnan(d[j]) || std::isnan(t[j]))) j--;
    if (std::isnan(d[i]) || std::isnan(t[i]) || std::isnan(d[j]) || std::isnan(t[j])) continue;
    if (d[j] <= target && d[i] >= target) {
      double dd = d[i] - d[j];
      double ta = dd > 0 ? t[j] + (target - d[j]) / dd * (t[i] - t[j]) : t[i];
      if (!(t_end > ta)) return false;
      if (time_s) *time_s = t_end - ta;
      if (speed) *speed = D / (t_end - ta);
      return true;
    }
  }
  return false;
}

double bone_vertical_force_n_kg(double v) {
  const double v_peak = 2.1376 / (2 * 0.0535);   // 19,98 m/s
  if (v > v_peak) v = v_peak;
  return 2.778 + 2.1376 * v - 0.0535 * v * v;
}

double bone_stride_damage(double v, const BoneModelConfig& c) {
  if (std::isnan(v) || v <= 0 || v > c.max_speed || c.f_max_n_kg <= 0 || c.sn_b_mpa <= 0) return 0;
  double sigma = c.sigma_max_mpa * std::min(bone_vertical_force_n_kg(v), c.f_max_n_kg) / c.f_max_n_kg;
  return std::pow(10.0, (sigma - c.sn_a_mpa) / c.sn_b_mpa);   // 1 / Nf
}

double model_stride_frequency_hz(double v) { return 1.7052 + 0.0305 * v + 0.0004 * v * v; }

const char* kb_band_name(int b) {
  static const char* n[] = {"B1_TRABAJO", "B2_INTERMEDIA", "B3_ALTA"};
  return b >= 0 && b < KB_BANDS ? n[b] : "BAJO_TRABAJO";
}

int kb_speed_band(double v, const SpeedBandConfig& c) {
  if (std::isnan(v) || v < c.work_speed) return -1;
  if (std::isnan(c.race_pace)) return 0;
  if (v >= c.b3_lo()) return 2;
  if (v >= c.b2_lo()) return 1;
  return 0;
}

void KbSessionLoad::add(double dt_s, double dd_m, double v, const SpeedBandConfig& b, const BoneModelConfig& m) {
  if (std::isnan(v) || std::isnan(dt_s) || !(dt_s > 0)) return;
  double dd = std::isnan(dd_m) ? 0 : std::max(0.0, dd_m);
  int k = kb_speed_band(v, b);
  if (k >= 0) { band_m[k] += dd; band_s[k] += dt_s; }
  {  // CG2 (KB 1.30.0)
    double e[KB_CG_BANDS - 1];
    kb_cg_edges(b.cg_relative, b.race_pace, e);
    int g = kb_cg_band(v, e);
    if (g >= 0) { cg_band_m[g] += dd; cg_band_s[g] += dt_s; if (g >= KB_CG_HS_BAND) hs_m += dd; }
  }
  if (!std::isnan(b.race_pace)) {
    if (v > b.gallop_lo()) gallop_m += dd;
    else if (v >= b.canter_lo()) canter_m += dd;
  }
  if (v < m.low_min_speed || v > m.max_speed) return;
  double n = model_stride_frequency_hz(v) * dt_s, dmg = n * bone_stride_damage(v, m);
  if (v >= m.valid_min_speed) { strides += n; bone_fl += dmg; }
  else { strides_low += n; bone_fl_low += dmg; }
}

// ------------------------------------------------------------------ historia
// Días desde 1970-01-01 -> AAAA-MM-DD (algoritmo civil de H. Hinnant).
std::string kb_day_text(long z) {
  z += 719468;
  long era = (z >= 0 ? z : z - 146096) / 146097;
  long doe = z - era * 146097, yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
  long y = yoe + era * 400, doy = doe - (365 * yoe + yoe / 4 - yoe / 100), mp = (5 * doy + 2) / 153;
  long d = doy - (153 * mp + 2) / 5 + 1, m = mp < 10 ? mp + 3 : mp - 9;
  char b[48]; snprintf(b, sizeof(b), "%04ld-%02ld-%02ld", y + (m <= 2), m, d);
  return b;
}

KbStatus kb_evaluate(const std::vector<KbDay>& sessions, long at_day, long first_day, const KbRuleConfig& c) {
  KbStatus st;
  auto in = [](long d, long from, long to) { return d >= from && d <= to; };
  auto add = [](KbWindow* w, const KbDay& s) {
    if (!has_kb(s)) { w->missing++; return; }
    w->sessions++;
    for (int k = 0; k < KB_BANDS; k++) if (!std::isnan(s.band_m[k])) w->band_m[k] += s.band_m[k];
    if (!std::isnan(s.canter_m)) w->canter_m += s.canter_m;
    if (!std::isnan(s.gallop_m)) w->gallop_m += s.gallop_m;
    w->bone_pct += s.bone_pct;
  };
  long last_gallop = -1, first_kb = -1, return_start = -1;
  std::vector<long> gallop_days;   // días distintos con sesión rápida (A6C)
  bool verheyen = false;   // alguna sesión trae contadores de Verheyen (raza con v_carrera)
  for (const auto& s : sessions) {
    if (s.day > at_day) break;
    bool has = has_kb(s);
    if (has) { st.available = true; if (first_kb < 0) first_kb = s.day; if (!std::isnan(s.gallop_m)) verheyen = true; }
    if (in(s.day, at_day - 6, at_day)) add(&st.w7, s);
    if (in(s.day, at_day - 29, at_day)) add(&st.w30, s);
    if (in(s.day, at_day - 59, at_day - 30)) add(&st.prev30, s);
    if (in(s.day, at_day - 59, at_day)) add(&st.w60, s);
    if (has && in(s.day, at_day - 59, at_day) && !std::isnan(s.gallop_m) && s.gallop_m >= c.gallop_session_min_m && s.day != last_gallop)
      st.gallop_days_60d++;
    if (has && !std::isnan(s.gallop_m) && s.gallop_m >= c.gallop_session_min_m && s.day != last_gallop) {
      long ref = last_gallop >= 0 ? last_gallop : first_kb;
      long gap = s.day - ref;
      if (gap >= c.return_rest_days) { return_start = s.day; st.return_rest = (int)gap; }
      last_gallop = s.day;
      gallop_days.push_back(s.day);
    }
  }
  if (!st.available || !c.enabled) return st;
  st.days_since_gallop = last_gallop < 0 ? -1 : (int)(at_day - last_gallop);
  // A6C: cociente de días de galope de Choi & Parkin 2025 (sección 2.3): (g60/g90) + 1 con las ventanas de 60 y 90 días
  // que acaban en el último trabajo rápido [E]; el propio día del último trabajo rápido entra en las dos ventanas [I].
  if (last_gallop >= 0 && first_day <= last_gallop - 89) {
    int g60 = 0, g90 = 0;
    for (long d : gallop_days) {
      if (in(d, last_gallop - 59, last_gallop)) g60++;
      if (in(d, last_gallop - 89, last_gallop)) g90++;
    }
    st.gallop_days_60_last = g60; st.gallop_days_90_last = g90;
    if (g90 > 0) st.gallop_ratio = (double)g60 / g90 + 1.0;
  }
  char b[420];

  if (verheyen) {
    // A1 canter acumulado en 30 días
    double canter_km = st.w30.canter_m / 1000.0;
    if (canter_km > c.canter_30d_watch_km) {
      bool lim = canter_km > c.canter_30d_limit_km;
      snprintf(b, sizeof(b), "%.1f km de canter en 30 días (umbral de aviso %.0f km, de límite %.0f km)", canter_km, c.canter_30d_watch_km, c.canter_30d_limit_km);
      st.flags.push_back({"A1_CANTER_30D", "VIGILAR", lim ? "LIMITAR" : "AVISO", b,
                          "Verheyen 2006 (Bone, 1178 caballos): > 44 km de canter (≤ 14 m/s) en 30 días, más fracturas [E]; aviso al 90 % [I]"});
    }
    // A2 galope rápido acumulado en 30 días
    double gallop_km = st.w30.gallop_m / 1000.0;
    if (gallop_km > c.gallop_30d_limit_km) {
      snprintf(b, sizeof(b), "%.1f km de galope rápido en 30 días (más de %.0f km)", gallop_km, c.gallop_30d_limit_km);
      st.flags.push_back({"A2_GALOPE_30D", "VIGILAR", "LIMITAR", b, "Verheyen 2006: > 6 km de galope (> 14 m/s) en 30 días, más fracturas [E]"});
    }
    // A3 aumento brusco: 30 días frente a los 30 anteriores (solo con 60 días de historia)
    if (first_day <= at_day - 59 && st.w30.gallop_m >= c.ramp_min_m && st.prev30.gallop_m > 0) {
      double ratio = st.w30.gallop_m / st.prev30.gallop_m;
      if (ratio > c.ramp_ratio) {
        snprintf(b, sizeof(b), "galope rápido de los últimos 30 días %.2f veces el de los 30 anteriores (%.0f m frente a %.0f m)",
                 ratio, st.w30.gallop_m, st.prev30.gallop_m);
        st.flags.push_back({"A3_RAMPA", "VIGILAR", "LIMITAR", b,
                            "Estberg 1996 (California): +40 % de trabajo rápido en 2 meses, OR 3,9 de fractura catastrófica [E]; ventanas de 30 días [I]"});
      }
    }
    // A5/A6 vuelta tras un descanso largo sin trabajo rápido
    if (return_start >= 0 && at_day - return_start < c.return_window_days) {
      st.return_day = (int)(at_day - return_start);
      bool tendon = st.return_rest >= c.tendon_rest_days;
      snprintf(b, sizeof(b), "día %d de la vuelta al trabajo rápido tras %d días sin él: subir la distancia rápida poco a poco%s",
               st.return_day, st.return_rest, tendon ? "; considerar ecografía de los tendones flexores (TFDS)" : "");
      st.flags.push_back({tendon ? "A6_VUELTA_TENDON" : "A5_VUELTA_DESCANSO", "VIGILAR", "LIMITAR", b,
                          tendon ? "Choi & Parkin 2025: ≥ 90 días sin trabajo rápido, OR 3,10 de lesión del TFDS [E]; Carrier 1998 [E]"
                                 : "Carrier 1998: tras ≥ 60 días sin trabajo rápido, RR 71 de fractura de húmero en 10 días y 45 en 21 [E]"});
    }
    // A6B pocos días de galope en 60 días con el caballo en entrenamiento (con 60 días de historia)
    if (first_day <= at_day - 59 && st.w7.sessions > 0 && st.w60.canter_m > 0 && st.gallop_days_60d <= c.low_gallop_60d_max_days) {
      snprintf(b, sizeof(b), "%d días de galope rápido en los últimos 60 días (%d o menos): el tendón flexor pierde preparación; repartir el trabajo rápido",
               st.gallop_days_60d, c.low_gallop_60d_max_days);
      st.flags.push_back({"A6B_POCO_GALOPE_60D", "INFO", "AVISO", b,
                          "Choi & Parkin 2025 (Seúl, 101 casos): ≤ 2 días de galope en 60 días, OR 1,84 (IC 95 % 1,07–3,16) de tendinopatía del TFDS [E]; "
                          "día de galope = sesión rápida del motor [I]"});
    }
    // A6C cociente de galope bajo: el galope de los últimos 60 días es poco frente al de los 90 (frecuencia en descenso)
    if (!std::isnan(st.gallop_ratio) && st.gallop_ratio <= c.gallop_ratio_max + 1e-9 && st.w7.sessions > 0 &&
        st.days_since_gallop <= c.gallop_ratio_max_age_days) {
      snprintf(b, sizeof(b), "cociente de galope %.2f (%d días de galope en 60 d frente a %d en 90 d, hasta el último trabajo rápido; "
               "aviso con %.1f o menos): el galope se está espaciando; mantener la frecuencia o subirla poco a poco",
               st.gallop_ratio, st.gallop_days_60_last, st.gallop_days_90_last, c.gallop_ratio_max);
      st.flags.push_back({"A6C_COCIENTE_GALOPE", "INFO", "AVISO", b,
                          "Choi & Parkin 2025 (Seúl, 101 casos): (días de galope 60 d / 90 d) + 1 ≤ 1,6, OR 2,19 (IC 95 % 1,23–3,91) de "
                          "tendinopatía del TFDS [E]; día de galope = sesión rápida del motor y vigencia de 30 días [I]"});
    }
    // A4 carga baja antes de una carrera (KB 1.26.0): Morrice-West 2025 (Tasmania), carga muy baja antes de correr,
    // HR 2,89 frente a carga media [E]; allí «baja» = fatiga ósea acumulada < 0,25 en las 4 salidas previas. Aquí se
    // aproxima con días de sesión rápida en los 28 d previos (< 2) [I]. Se juzga el día de la carrera (sesión CARRERA o
    // TRIAL, o fecha prevista) y, por adelantado, cuando faltan ≤ prerace_warn_days y aún no se llega al mínimo [I].
    {
      std::vector<std::pair<long, bool>> races;   // día, prevista
      for (long d : c.planned_race_days) races.push_back({d, true});
      for (const auto& s : sessions) {
        if (s.day > at_day) break;
        if (s.race) races.push_back({s.day, false});
      }
      std::sort(races.begin(), races.end());
      long prev = -1;
      for (const auto& rc : races) {
        long R = rc.first;
        if (R == prev) continue;   // misma fecha prevista y corrida: una sola comprobación (gana la sesión, que va después)
        prev = R;
        if (R < at_day || R > at_day + c.prerace_days) continue;
        KbRaceCheck k; k.day = R; k.days_to = (int)(R - at_day);
        k.planned = true;
        for (const auto& o : races) if (o.first == R && !o.second) k.planned = false;
        long from = R - c.prerace_days, to = std::min(R - 1, at_day);
        k.covered = first_day <= from;
        for (long d : gallop_days) if (in(d, from, to)) k.fast_days++;
        for (const auto& s : sessions) { if (s.day > to) break; if (in(s.day, from, to) && !has_kb(s)) k.missing++; }
        bool due = k.days_to == 0 || k.days_to <= c.prerace_warn_days;
        if (k.covered && due && k.fast_days < c.prerace_min_fast_days) {
          k.flagged = true;
          if (k.days_to == 0)
            snprintf(b, sizeof(b), "carrera %s con %d días de trabajo rápido en los %d días previos (mínimo %d): carga baja antes de correr",
                     k.planned ? "prevista hoy" : "de hoy", k.fast_days, c.prerace_days, c.prerace_min_fast_days);
          else
            snprintf(b, sizeof(b), "carrera prevista en %d días con %d días de trabajo rápido en su ventana de %d días (mínimo %d): "
                     "planificar el trabajo rápido que falta sin juntarlo (≥ 72 h entre rápidos)",
                     k.days_to, k.fast_days, c.prerace_days, c.prerace_min_fast_days);
          st.flags.push_back({"A4_CARGA_BAJA_PRECARRERA", "INFO", "AVISO", b,
                              "Morrice-West 2025 (Tasmania): carga muy baja antes de correr, HR 2,89 frente a carga media [E]; allí "
                              "«baja» es fatiga ósea < 0,25 en las 4 salidas previas; el corte de 2 días rápidos en 28 d es [I]"});
        }
        st.races.push_back(k);
      }
    }
    // Informativo: ningún trabajo rápido en 30 días con canter
    if (first_day <= at_day - 29 && st.w30.gallop_m < c.gallop_session_min_m && st.w30.canter_m > 0)
      st.flags.push_back({"KB_SIN_RAPIDO_30D", "INFO", "AVISO", "sin trabajo rápido en 30 días: el hueso pierde estímulo; al volver, subirlo poco a poco",
                          "Morrice-West 2025: carga muy baja antes de correr, OR 2,89 frente a carga media [E]; aplicación al entrenamiento [I]"});
  }
  // KB-B fatiga ósea de 7 días frente a la mediana semanal propia
  std::vector<double> weeks;
  for (int w = 1; w <= 8; w++) {
    long to = at_day - 7 * w, from = to - 6;
    if (from < first_day) break;
    double sum = 0;
    for (const auto& s : sessions) if (in(s.day, from, to) && !std::isnan(s.bone_pct)) sum += s.bone_pct;
    weeks.push_back(sum);
  }
  if ((int)weeks.size() >= c.bone_min_weeks) {
    st.bone_weekly_median = median_of(weeks);
    if (st.bone_weekly_median > 0) {
      st.bone_ratio = st.w7.bone_pct / st.bone_weekly_median;
      if (st.bone_ratio > c.bone_week_ratio) {
        snprintf(b, sizeof(b), "fatiga ósea de los últimos 7 días %.2f veces la semana habitual del caballo (%.2f %% frente a %.2f %%)",
                 st.bone_ratio, st.w7.bone_pct, st.bone_weekly_median);
        st.flags.push_back({"KB_FATIGA_OSEA_7D", "VIGILAR", "AVISO", b,
                            "Morrice-West 2025 e ICRAV 2026: el riesgo sube con la acumulación rápida de fatiga ósea [E]; umbral 1,5 [I]"});
      }
    }
  }
  return st;
}

std::string kb_status_json(const KbStatus& s) {
  std::ostringstream o;
  auto win = [&](const KbWindow& w) {
    o << "{\"bandas_m\":[" << num(w.band_m[0]) << "," << num(w.band_m[1]) << "," << num(w.band_m[2]) << "],\"canter_m\":" << num(w.canter_m)
      << ",\"galope_rapido_m\":" << num(w.gallop_m) << ",\"fatiga_osea_pct\":" << num(w.bone_pct)
      << ",\"sesiones\":" << w.sessions << ",\"sesiones_sin_datos\":" << w.missing << "}";
  };
  o << "{\"base\":\"" << KNOWLEDGE_ID << "\",\"version\":\"" << KNOWLEDGE_VERSION << "\",\"disponible\":" << (s.available ? "true" : "false");
  if (s.available) {
    o << ",\"d7\":"; win(s.w7); o << ",\"d30\":"; win(s.w30); o << ",\"d30_anteriores\":"; win(s.prev30); o << ",\"d60\":"; win(s.w60);
    o << ",\"fatiga_osea_mediana_semanal_pct\":" << num(s.bone_weekly_median) << ",\"fatiga_osea_ratio_7d\":" << num(s.bone_ratio)
      << ",\"dias_sin_trabajo_rapido\":" << (s.days_since_gallop < 0 ? std::string("null") : std::to_string(s.days_since_gallop))
      << ",\"dias_galope_60d\":" << s.gallop_days_60d << ",\"cociente_galope\":";
    if (std::isnan(s.gallop_ratio)) o << "null";
    else o << "{\"valor\":" << num(s.gallop_ratio) << ",\"dias_galope_60d\":" << s.gallop_days_60_last << ",\"dias_galope_90d\":" << s.gallop_days_90_last << "}";
    if (!s.races.empty()) {
      o << ",\"carreras\":[";
      for (size_t i = 0; i < s.races.size(); i++) {
        const KbRaceCheck& k = s.races[i];
        o << (i ? "," : "") << "{\"fecha\":\"" << kb_day_text(k.day) << "\",\"origen\":\"" << (k.planned ? "PREVISTA" : "SESION")
          << "\",\"dias_hasta\":" << k.days_to << ",\"dias_rapidos_28d\":" << k.fast_days << ",\"sesiones_sin_datos\":" << k.missing
          << ",\"ventana_cubierta\":" << (k.covered ? "true" : "false") << ",\"aviso\":" << (k.flagged ? "true" : "false") << "}";
      }
      o << "]";
    }
    o << ",\"vuelta_descanso\":";
    if (s.return_day < 0) o << "null";
    else o << "{\"dia\":" << s.return_day << ",\"dias_sin_rapido_antes\":" << s.return_rest << "}";
  }
  // Las reglas A7/A8 (línea base propia) no dependen del bloque de carga: se escriben aunque no esté disponible.
  if (s.available || !s.flags.empty()) {
    o << ",\"reglas\":[";
    for (size_t i = 0; i < s.flags.size(); i++)
      o << (i ? "," : "") << "{\"regla\":" << q(s.flags[i].rule) << ",\"nivel\":" << q(s.flags[i].level) << ",\"accion\":" << q(s.flags[i].action)
        << ",\"texto\":" << q(s.flags[i].text) << ",\"evidencia\":" << q(s.flags[i].evidence) << "}";
    o << "]";
  }
  o << ",\"nota\":\"orientativo: reglas de la literatura con umbrales de partida, sin validar con la cuadra; la fatiga ósea es un índice relativo, no una probabilidad de lesión\"}";
  return o.str();
}

// ------------------------------------------------------------------ líneas base (KB 1.3.0)
KbRobustBaseline kb_robust_baseline(const std::vector<double>& x, int last_n) {
  KbRobustBaseline b;
  std::vector<double> v;
  for (size_t i = x.size(); i-- > 0;) {
    if (std::isnan(x[i]) || std::isinf(x[i])) continue;
    v.push_back(x[i]);
    if (last_n > 0 && (int)v.size() >= last_n) break;
  }
  b.n = (int)v.size();
  if (v.empty()) return b;
  b.median = median_of(v);
  std::vector<double> dev; dev.reserve(v.size());
  for (double a : v) dev.push_back(std::fabs(a - b.median));
  b.mad_s = KB_MAD_SCALE * median_of(dev);
  return b;
}

double kb_robust_z(double x, const KbRobustBaseline& b, double min_scale) {
  if (b.n < 3 || std::isnan(x) || std::isnan(b.median)) return kNaN;
  double s = std::isnan(b.mad_s) ? 0.0 : b.mad_s;
  if (min_scale > s) s = min_scale;
  if (!(s > 0)) return kNaN;
  return (x - b.median) / s;
}

double kb_shrink_mean(int n, double xbar, double sigma2_within, double mu_pop, double tau2_between) {
  if (n <= 0 || std::isnan(xbar)) return mu_pop;
  if (std::isnan(mu_pop) || !(tau2_between > 0)) return xbar;   // sin prior útil: solo el caballo
  if (!(sigma2_within > 0)) return xbar;                        // sin ruido: el dato propio manda
  double wp = n / sigma2_within, wq = 1.0 / tau2_between;
  return (wp * xbar + wq * mu_pop) / (wp + wq);
}

double kb_change_threshold(double te, int n, double swc) {
  double noise = (std::isnan(te) || te < 0) ? kNaN : 2.0 * te * (n > 0 ? std::sqrt(1.0 + 1.0 / n) : std::sqrt(2.0));
  if (std::isnan(noise)) return swc;
  if (std::isnan(swc)) return noise;
  return std::max(noise, swc);
}

KbCusumResult kb_cusum_upper(const std::vector<double>& z, const KbCusumConfig& c) {
  KbCusumResult r;
  r.s.reserve(z.size());
  double S = c.fir ? 0.5 * c.h : 0.0;
  int valid = 0;
  for (size_t i = 0; i < z.size(); i++) {
    if (!std::isnan(z[i]) && !std::isinf(z[i])) {
      S = std::max(0.0, S + z[i] - c.k);
      valid++;
      if (r.alarm_index < 0 && valid >= c.min_samples && S > c.h) r.alarm_index = (int)i;
    }
    r.s.push_back(S);
  }
  return r;
}


namespace {
// Fracción continua de la beta incompleta regularizada (método de Lentz).
double betacf(double a, double b, double x) {
  const double tiny = 1e-300;
  double qab = a + b, qap = a + 1, qam = a - 1, cc = 1, d = 1 - qab * x / qap;
  if (std::fabs(d) < tiny) d = tiny;
  d = 1 / d;
  double h = d;
  for (int m = 1; m <= 300; m++) {
    double m2 = 2.0 * m, aa = m * (b - m) * x / ((qam + m2) * (a + m2));
    d = 1 + aa * d; if (std::fabs(d) < tiny) d = tiny;
    cc = 1 + aa / cc; if (std::fabs(cc) < tiny) cc = tiny;
    d = 1 / d; h *= d * cc;
    aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2));
    d = 1 + aa * d; if (std::fabs(d) < tiny) d = tiny;
    cc = 1 + aa / cc; if (std::fabs(cc) < tiny) cc = tiny;
    d = 1 / d;
    double del = d * cc;
    h *= del;
    if (std::fabs(del - 1) < 1e-15) break;
  }
  return h;
}
double betai(double a, double b, double x) {
  if (x <= 0) return 0;
  if (x >= 1) return 1;
  double lbt = std::lgamma(a + b) - std::lgamma(a) - std::lgamma(b) + a * std::log(x) + b * std::log(1 - x);
  if (x < (a + 1) / (a + b + 2)) return std::exp(lbt) * betacf(a, b, x) / a;
  return 1 - std::exp(lbt) * betacf(b, a, 1 - x) / b;
}
// Cola superior de la t de Student: P(T > t) para t ≥ 0.
double t_upper(double t, double nu) { return 0.5 * betai(0.5 * nu, 0.5, nu / (nu + t * t)); }
}  // namespace

double kb_student_t_cdf(double t, double nu) {
  if (std::isnan(t) || !(nu > 0)) return kNaN;
  if (std::isinf(t)) return t > 0 ? 1.0 : 0.0;
  return t >= 0 ? 1.0 - t_upper(t, nu) : t_upper(-t, nu);
}

double kb_normal_quantile(double p) {
  if (std::isnan(p) || p < 0 || p > 1) return kNaN;
  if (p == 0) return -INFINITY;
  if (p == 1) return INFINITY;
  if (p > 0.5) return -kb_normal_quantile(1 - p);
  // Bisección sobre Φ(x) = erfc(−x/√2)/2 en la cola inferior (precisión relativa buena hasta p ≈ 1e-300).
  double lo = -40, hi = 0;
  for (int i = 0; i < 200; i++) {
    double mid = 0.5 * (lo + hi);
    if (0.5 * std::erfc(-mid / std::sqrt(2.0)) < p) lo = mid; else hi = mid;
  }
  return 0.5 * (lo + hi);
}

std::vector<double> kb_self_starting_z(const std::vector<double>& x) {
  std::vector<double> out(x.size(), kNaN);
  int n = 0;            // observaciones válidas ya acumuladas
  double mean = 0, m2 = 0;   // Welford
  for (size_t i = 0; i < x.size(); i++) {
    double v = x[i];
    if (std::isnan(v) || std::isinf(v)) continue;
    if (n >= 2) {
      double s = std::sqrt(m2 / (n - 1));
      if (s > 0) {
        int nn = n + 1;   // índice (1-based) de esta observación
        double tstat = std::sqrt((double)(nn - 1) / nn) * (v - mean) / s;
        double nu = nn - 2;
        // Usar la cola más pequeña para no perder precisión en los extremos.
        out[i] = tstat >= 0 ? -kb_normal_quantile(t_upper(tstat, nu)) : kb_normal_quantile(t_upper(-tstat, nu));
      }
    }
    n++;
    double d = v - mean;
    mean += d / n;
    m2 += d * (v - mean);
  }
  return out;
}


KbDriftResult kb_drift_down(const std::vector<double>& x, const KbDriftConfig& c) {
  KbDriftResult r;
  std::vector<double> v;
  for (double a : x) if (!std::isnan(a) && !std::isinf(a)) v.push_back(a);
  r.n = (int)v.size();
  if (v.empty()) return r;
  r.last = v.back();
  // Umbral frente a la mediana de las anteriores a las `recent` últimas.
  int recent = std::max(1, c.recent);
  if (!std::isnan(c.delta) && r.n > recent) {
    int end = r.n - recent, beg = std::max(0, end - 12);
    std::vector<double> base(v.begin() + beg, v.begin() + end);
    r.baseline_n = (int)base.size();
    if (r.baseline_n >= c.min_baseline) {
      r.baseline = median_of(base);
      r.drop = r.baseline - r.last;
      for (int i = end; i < r.n; i++) if (v[i] <= r.baseline - c.delta) r.hits++;
      r.delta_alarm = r.drop >= c.delta - 1e-12 && r.hits >= c.recent_hits;
    }
  }
  // CUSUM autoiniciado hacia abajo con exclusión de las sesiones en alarma.
  int acc = 0; double mean = 0, m2 = 0, S = 0;
  for (int i = 0; i < r.n; i++) {
    bool alarm = false;
    if (acc >= 2) {
      double sd = std::sqrt(m2 / (acc - 1));
      if (sd > 0) {
        int nn = acc + 1;
        double t = std::sqrt((double)(nn - 1) / nn) * (mean - v[i]) / sd;   // −x: caída = positivo
        double nu = nn - 2;
        double xi = t >= 0 ? -kb_normal_quantile(t_upper(t, nu)) : kb_normal_quantile(t_upper(-t, nu));
        S = std::max(0.0, S + xi - c.k);
        if (i + 1 > c.warmup && S > c.h) alarm = true;
      }
    }
    if (i == r.n - 1) { r.s = S; r.cusum_alarm = alarm; }
    // La base solo aprende de sesiones en control: con S > 0,8·h la sesión no entra [I]. Simulación propia (1.500
    // series normales, h 5, calentamiento 8): falsa alarma en 100 sesiones 11,4 % (sin exclusión 10,5 %; con h/2,
    // 23,7 %) y deriva de 3 DE detectada en ≤ 6 sesiones en el 91,5 % (sin exclusión 87,7 %).
    if (acc >= 2 && S > 0.8 * c.h) continue;
    acc++;
    double d = v[i] - mean; mean += d / acc; m2 += d * (v[i] - mean);
  }
  return r;
}

// ------------------------------------------------------------------ carga CG1–CG3 (KB 1.30.0)
double kb_trimp_delta(double hr, const KbTrimpConfig& c) {
  if (!std::isfinite(hr) || !(c.hr_max > c.hr_rest)) return NAN;
  double d = (hr - c.hr_rest) / (c.hr_max - c.hr_rest);
  return std::min(1.0, std::max(0.0, d));
}

void kb_trimp_add(KbTrimp* t, double dt_s, double hr, const KbTrimpConfig& c, std::vector<double>* hist) {
  if (!t || !(dt_s > 0) || !std::isfinite(hr) || hr <= 0) return;
  double d = kb_trimp_delta(hr, c);
  if (std::isnan(d)) return;
  double m = dt_s / 60.0;
  if (std::isnan(t->trimp)) { t->trimp = 0; t->trimp_unweighted = 0; }
  t->trimp += m * d * c.b * std::exp(c.c * d);
  t->trimp_unweighted += m * d;
  t->minutes += m;
  if (hr > c.zone1_bpm) t->s_above_z1 += dt_s;
  if (hr > c.zone2_bpm) t->s_above_z2 += dt_s;
  if (hr > c.hr_max) t->s_above_max += dt_s;
  if (hist) {
    if ((int)hist->size() != KB_HR_BINS) hist->assign(KB_HR_BINS, 0.0);
    int k = (int)std::floor(hr / KB_HR_BIN_BPM);
    k = std::min(KB_HR_BINS - 1, std::max(0, k));
    (*hist)[k] += dt_s;
  }
}

KbTrimp kb_trimp_from_histogram(const std::vector<double>& h, const KbTrimpConfig& c) {
  KbTrimp t;
  for (size_t k = 0; k < h.size() && (int)k < KB_HR_BINS; k++)
    if (h[k] > 0) kb_trimp_add(&t, h[k], (k + 0.5) * KB_HR_BIN_BPM, c, nullptr);
  return t;
}

const char* kb_cg_band_name(int k) {
  static const char* const n[KB_CG_BANDS] = {"LENTO", "MEDIO", "RAPIDO_1", "RAPIDO_2", "RAPIDO_3", "RAPIDO_4"};
  return k >= 0 && k < KB_CG_BANDS ? n[k] : "";
}

void kb_cg_edges(bool relative, double race_pace, double out[KB_CG_BANDS - 1]) {
  double f = relative && std::isfinite(race_pace) && race_pace > 0 ? race_pace / KB_CG_PSI_PACE : 1.0;
  for (int k = 0; k < KB_CG_BANDS - 1; k++) out[k] = KB_CG_EDGES_PSI[k] * f;
}

int kb_cg_band(double v, const double e[KB_CG_BANDS - 1]) {
  if (!std::isfinite(v) || v < 0) return -1;
  int k = 0;
  while (k < KB_CG_BANDS - 1 && v >= e[k]) k++;
  return k;
}

double kb_ewma_lambda(int n) { return n > 0 ? 2.0 / (n + 1.0) : 1.0; }

void kb_ewma(const std::vector<double>& daily, int na, int nc, double* acute, double* chronic) {
  double la = kb_ewma_lambda(na), lc = kb_ewma_lambda(nc), a = 0, c = 0;
  for (double x : daily) { double l = std::isfinite(x) ? x : 0.0; a = la * l + (1 - la) * a; c = lc * l + (1 - lc) * c; }
  if (acute) *acute = daily.empty() ? NAN : a;
  if (chronic) *chronic = daily.empty() ? NAN : c;
}

bool kb_foster(const std::vector<double>& w, double* monotony, double* strain) {
  if (w.empty()) return false;
  double sum = 0; for (double x : w) sum += std::isfinite(x) ? x : 0.0;
  double mean = sum / w.size(), var = 0;
  for (double x : w) { double l = std::isfinite(x) ? x : 0.0; var += (l - mean) * (l - mean); }
  double sd = std::sqrt(var / w.size());
  if (!(sd > 1e-9) || !(mean > 0)) return false;
  if (monotony) *monotony = mean / sd;
  if (strain) *strain = sum * mean / sd;
  return true;
}

}  // namespace avoeq
