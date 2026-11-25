// Planificador semanal, capa 2 (TRAINING 1.3.0, KB-1 1.31.0): propuesta orientativa de la semana.
// TRAINING 1.4.0 (25/11/2026, petición del usuario): por defecto, semana natural de LUNES a DOMINGO que contiene la fecha
// de referencia (hoy en las apps). Los días ya pasados muestran lo realizado según las sesiones y cuentan para la pauta
// (rápidos hechos, separaciones, día libre); se planifica el resto de la semana. Con «semana_calendario»: false, los 7 días
// siguientes a la referencia, como en 1.3.0.
// Reglas de la base científica: P1 (rápidos por semana), P2 (día libre y días lentos entre rápidos), P4 (cuatro semanas
// lentas tras > 60 d sin rápido), P5 (distancia rápida de 60 d frente al P75 propio), P6 (descansos anuales), P7 (ventana
// de reincorporación), RT1–RT3 (recuperación) y DM1–DM4 (potros de 2 años). Todo SIN CALIBRAR: pautas informativas que
// nunca cambian el estado del caballo; el entrenador decide. Nada de esto predice lesiones.
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <map>
#include <set>
#include <sstream>
#include "avo_eq/training.h"

namespace avoeq {
namespace {

const double kNaN = std::nan("");

std::string num(double v) {
  if (std::isnan(v) || std::isinf(v)) return "null";
  char b[48]; snprintf(b, sizeof(b), "%.6g", v); return b;
}
std::string q(const std::string& s) { return "\"" + json::escape(s) + "\""; }

double med(std::vector<double> v) {
  if (v.empty()) return kNaN;
  std::sort(v.begin(), v.end());
  size_t n = v.size();
  return n % 2 ? v[n / 2] : 0.5 * (v[n / 2 - 1] + v[n / 2]);
}
double pct(std::vector<double> v, double p) {   // interpolación lineal, p en [0, 1]
  if (v.empty()) return kNaN;
  std::sort(v.begin(), v.end());
  double x = p * (double)(v.size() - 1);
  size_t i = (size_t)std::floor(x);
  if (i + 1 >= v.size()) return v.back();
  return v[i] + (x - (double)i) * (v[i + 1] - v[i]);
}
int year_of(long day) { return std::atoi(kb_day_text(day).substr(0, 4).c_str()); }

const char* kEvP1 = "Morrice-West 2020: 2,0 rápidos/semana en maduros y 1,7 en 2 años (práctica) [E]; objetivo [I]";
const char* kEvP2 = "día libre semanal (práctica de entrenadores) [E]; ≥ 2 días lentos entre rápidos [I] (sin evidencia directa)";
const char* kEvRT = "glucógeno muscular 48–72 h tras el trabajo rápido [E-r]; pauta de 72 h y día siguiente suave [I]";
const char* kEvP4 = "Morrice-West 2020: 4,0 semanas de trabajo lento antes del primer trial tras el descanso [E]; "
                    "Carrier 1998: riesgo en los primeros 10–21 d de rápido tras ≥ 60 d sin él [E-r]; forma [I]";
const char* kEvRace = "intervalo de 17–21 d entre carreras (Morrice-West 2020/2021) [E]; días sin rápido alrededor de la carrera [I]";

}  // namespace

WeekPlan training_plan_week(const std::vector<SessionSummary>& ok, const std::vector<KbDay>& kbdays, long at, long first_day,
                            const KbStatus& kb, const TrainingConfig& c) {
  const auto& P = c.planner;
  const auto& kc = c.kb;
  WeekPlan w;
  // Ventana: semana natural (lunes–domingo) que contiene «at», o los horizon_days siguientes.
  bool session_today = false;
  for (const auto& s : ok) if (s.day == at) session_today = true;
  if (P.calendar_week) {
    long wd = ((at % 7) + 7 + 3) % 7;          // día 0 = 1970-01-01, jueves → 0 = lunes
    w.from_day = at - wd; w.to_day = w.from_day + 6;
    w.plan_from_day = session_today ? at + 1 : at;
    if (w.plan_from_day > w.to_day) { w.from_day += 7; w.to_day += 7; w.plan_from_day = w.from_day; }   // domingo ya entrenado
    w.calendar_week = true;
  } else { w.from_day = at + 1; w.to_day = at + P.horizon_days; w.plan_from_day = w.from_day; }
  if (!P.enabled) { w.reason = "planificador desactivado"; return w; }
  // metros rápidos y de canter por día (bloque de carga de la base científica)
  std::map<long, std::pair<double, double>> daily;   // día → (galope rápido m, canter m)
  bool any = false;
  for (const auto& d : kbdays) {
    if (d.day > at || std::isnan(d.bone_pct)) continue;
    any = true;
    auto& e = daily[d.day];
    if (!std::isnan(d.gallop_m)) e.first += d.gallop_m;
    if (!std::isnan(d.canter_m)) e.second += d.canter_m;
  }
  if (!any) { w.reason = "sin sesiones con el bloque de carga de la base científica (GNSS de trabajo en pista)"; return w; }
  w.available = true;
  std::vector<long> fast;
  for (const auto& e : daily) if (e.second.first >= kc.gallop_session_min_m) fast.push_back(e.first);
  std::set<long> session_days;
  std::vector<long> races;
  for (const auto& s : ok) if (s.day <= at) { session_days.insert(s.day); if (s.counts_as_race()) races.push_back(s.day); }
  for (const auto& s : ok) if (!s.race.breed.empty()) w.breed = s.race.breed;
  std::vector<long> planned;
  for (long d : kc.planned_race_days) if (d >= w.plan_from_day && d <= w.to_day) planned.push_back(d);
  std::vector<long> all_races = races;
  for (long d : kc.planned_race_days) if (d >= w.plan_from_day && std::find(races.begin(), races.end(), d) == races.end()) all_races.push_back(d);
  char b[480];

  // Edad de carreras: opción «edad_anos» o año de referencia − año de nacimiento (convenio del 1 de enero).
  if (P.has_birth) { w.age_years = year_of(at) - year_of(P.birth_day); w.age_origin = "FECHA_NACIMIENTO"; }
  else if (P.age_years >= 0) { w.age_years = P.age_years; w.age_origin = "EDAD_ANOS"; }
  const bool colt = w.age_years >= 0 && w.age_years <= 2;

  // Bloque de preparación actual: desde la primera sesión tras el último hueco ≥ p4_block_gap_days sin sesiones.
  long block_start = first_day, prev = -1;
  for (long d : session_days) { if (prev >= 0 && d - prev > P.p4_block_gap_days) block_start = d; prev = d; }
  w.prep_weeks = (int)((at - block_start) / 7);

  // Mediana propia de metros rápidos por día rápido (últimos 60 d) y antes de la vuelta (P7).
  {
    std::vector<double> m;
    for (long d : fast) if (d > at - 60) m.push_back(daily[d].first);
    w.fast_ref_m = med(m);
  }

  // Fase: reincorporación (P4/P7), potro (DM1) o normal.
  long last_fast = fast.empty() ? -1 : fast.back();
  bool long_gap = last_fast >= 0 ? at - last_fast > kc.return_rest_days : at - first_day >= kc.return_rest_days;
  for (size_t i = 0; i < fast.size(); i++) {
    long gap = i == 0 ? fast[0] - first_day : fast[i] - fast[i - 1];
    if (gap > kc.return_rest_days) w.return_fast_day = fast[i];
  }
  int target = colt ? P.fast_per_week_2y : P.fast_per_week_mature;
  int min_gap = P.min_days_between_fast;
  if (long_gap) {
    long restart = std::max(block_start, last_fast + 1);
    w.slow_days_done = (int)(at - restart + 1);
    w.phase = "REINCORPORACION_LENTA";
    if (w.slow_days_done < P.p4_slow_days) {
      target = 0;
      snprintf(b, sizeof(b), "%s sin trabajo rápido y %d de los %d días de trabajo lento de la pauta: semana sin rápidos",
               last_fast >= 0 ? (std::to_string(at - last_fast) + " días").c_str() : "toda la historia", w.slow_days_done, P.p4_slow_days);
    } else {
      target = 1; min_gap = 7;
      snprintf(b, sizeof(b), "%d días de trabajo lento tras > %d días sin rápido: se propone un solo rápido de distancia reducida",
               w.slow_days_done, kc.return_rest_days);
    }
    w.notes.push_back({"PLANIFICADOR_P4", b, kEvP4});
  } else if (w.return_fast_day >= 0 && at - w.return_fast_day < P.p7_window_days) {
    w.phase = "REINCORPORACION_RAPIDO";
    target = 1; min_gap = 7;
    snprintf(b, sizeof(b), "vuelta al trabajo rápido el %s (día %d de la ventana de %d): un solo rápido por semana, sin dos seguidos ni picos de canter",
             kb_day_text(w.return_fast_day).c_str(), (int)(at - w.return_fast_day) + 1, P.p7_window_days);
    w.notes.push_back({"PLANIFICADOR_P7", b, kEvP4});
  } else w.phase = colt ? "POTRO_2_ANOS" : "NORMAL";

  if (w.phase.compare(0, 15, "REINCORPORACION") == 0) {
    std::vector<double> m;
    long until = w.phase == "REINCORPORACION_RAPIDO" ? w.return_fast_day : at + 1;
    for (long d : fast) if (d < until && d >= until - 180) m.push_back(daily[d].first);
    double ref = med(m);
    if (!std::isnan(ref)) w.fast_max_m = std::round(P.p7_distance_fraction * ref);
  }
  if (colt && (w.prep_weeks < P.dm4_weeks)) {
    w.fast_max_m = std::isnan(w.fast_max_m) ? P.dm1_fast_max_m : std::min(w.fast_max_m, P.dm1_fast_max_m);
    snprintf(b, sizeof(b), "potro de %d años en la semana %d de preparación: trabajos rápidos cortos (≈ 200–%.0f m), 1–2 por semana, y menos canter el día de rápido (DM1, DM3)",
             w.age_years, w.prep_weeks + 1, P.dm1_fast_max_m);
    w.notes.push_back({"PLANIFICADOR_DM1", b, "Oliveira 2006 [E] (n = 42) y Boston & Nunamaker 2000 [E-r]: rápido corto acumulado poco a poco; cortes [I]; pauta de carga, nunca una predicción"});
  }
  // A1/A2 en LIMITAR: un solo rápido como mucho
  for (const auto& f : kb.flags)
    if (f.action == "LIMITAR" && target > 1) {
      target = 1; w.limited = true;
      w.notes.push_back({"PLANIFICADOR_LIMITAR", "la base científica pide limitar (" + f.rule + "): se propone un solo rápido esta semana", f.evidence});
      break;
    }
  w.fast_target = target;

  // Colocación. Días pasados de la semana: lo realizado. Días a planificar: carreras previstas, rápidos (lo antes posible
  // respetando las separaciones, contando los ya hechos) y días libres/suaves.
  const int H = (int)(w.to_day - w.from_day + 1);
  const int hp = (int)(w.plan_from_day - w.from_day);   // índice del primer día a planificar
  w.days.resize(H);
  for (int h = 0; h < H; h++) { w.days[h].day = w.from_day + h; w.days[h].type = "LENTO"; }
  for (int h = 0; h < hp; h++) {
    PlanDay& x = w.days[h];
    long d = x.day;
    x.done = true;
    bool race = false, sess = session_days.count(d) > 0;
    for (const auto& s : ok) if (s.day == d && s.counts_as_race()) race = true;
    auto it = daily.find(d);
    double g = it == daily.end() ? 0 : it->second.first;
    if (race) { x.type = "CARRERA"; x.reason = "realizado: carrera o trial"; }
    else if (g >= kc.gallop_session_min_m) {
      x.type = "RAPIDO"; w.fast_done++;
      snprintf(b, sizeof(b), "realizado: trabajo rápido (%.0f m de galope rápido)", g); x.reason = b;
    } else if (sess) { x.type = "LENTO"; x.reason = "realizado: entrenamiento sin trabajo rápido"; }
    else { x.type = "LIBRE"; x.reason = "sin entrenamiento registrado"; }
    x.rules = {};
  }
  for (long d : planned) {
    PlanDay& x = w.days[d - w.from_day];
    x.type = "CARRERA"; x.reason = "carrera prevista"; x.rules = {"PLANIFICADOR_P3"};
  }
  auto blocked = [&](long d, std::string* why) {
    for (long r : all_races) {
      if (r - d >= 1 && r - d <= P.prerace_no_fast_days) { *why = "carrera el " + kb_day_text(r); return true; }
      if (d - r >= 1 && d - r <= P.postrace_no_fast_days) { *why = "recuperación de la carrera del " + kb_day_text(r); return true; }
      if (d == r) { *why = "carrera"; return true; }
    }
    return false;
  };
  long prev_hard = last_fast;
  for (long r : races) prev_hard = std::max(prev_hard, r);
  const int remaining = std::max(0, target - w.fast_done);
  int placed = 0;
  for (int h = hp; h < H && placed < remaining; h++) {
    long d = w.from_day + h;
    std::string why;
    if (w.days[h].type == "CARRERA") { prev_hard = d; continue; }
    if (blocked(d, &why)) continue;
    if (prev_hard >= 0 && d - prev_hard < min_gap) continue;
    PlanDay& x = w.days[h];
    x.type = "RAPIDO"; x.fast_max_m = w.fast_max_m;
    x.rules = {"PLANIFICADOR_P1", "RECUPERACION_RT1"};
    if (colt) x.rules.push_back("PLANIFICADOR_DM1");
    if (w.phase.compare(0, 15, "REINCORPORACION") == 0) x.rules.push_back(w.phase == "REINCORPORACION_LENTA" ? "PLANIFICADOR_P4" : "PLANIFICADOR_P7");
    snprintf(b, sizeof(b), "trabajo rápido%s%s", std::isnan(w.fast_max_m) ? "" : (" de hasta " + num(w.fast_max_m) + " m").c_str(),
             colt ? "; ese día menos canter (DM3)" : "");
    x.reason = b;
    prev_hard = d; placed++;
  }
  w.fast_planned = placed;
  // día siguiente a un rápido: SUAVE (RT2); día siguiente a una carrera: LIBRE
  for (int h = hp; h < H; h++) {
    long d = w.from_day + h;
    if (w.days[h].type != "LENTO") continue;
    bool after_race = std::find(all_races.begin(), all_races.end(), d - 1) != all_races.end();
    bool after_fast = (h > 0 && w.days[h - 1].type == "RAPIDO") || (d - 1 == last_fast);
    if (after_race) { w.days[h].type = "LIBRE"; w.days[h].reason = "día siguiente a la carrera"; w.days[h].rules = {"RECUPERACION_RT2", "PLANIFICADOR_P2"}; }
    else if (after_fast) { w.days[h].type = "SUAVE"; w.days[h].reason = "día siguiente al trabajo rápido: paso o trote suave"; w.days[h].rules = {"RECUPERACION_RT2"}; }
  }
  int free_now = 0;
  for (const auto& x : w.days) if (x.type == "LIBRE") free_now++;   // los días pasados sin entrenamiento cuentan
  for (int h = H - 1; h >= hp && free_now < P.free_days; h--) {   // el último día lento que no precede a un rápido o carrera
    if (w.days[h].type != "LENTO") continue;
    if (h + 1 < H && (w.days[h + 1].type == "RAPIDO" || w.days[h + 1].type == "CARRERA")) continue;
    w.days[h].type = "LIBRE"; w.days[h].reason = "día libre de la semana"; w.days[h].rules = {"PLANIFICADOR_P2"}; free_now++;
  }
  for (int h = H - 1; h >= hp && free_now < P.free_days; h--)
    if (w.days[h].type == "SUAVE" || w.days[h].type == "LENTO") {
      w.days[h].type = "LIBRE"; w.days[h].reason = "día libre de la semana"; w.days[h].rules.push_back("PLANIFICADOR_P2"); free_now++;
    }
  for (auto& x : w.days)
    if (!x.done && x.type == "LENTO") { x.reason = "trabajo lento (paso, trote y canter suave)"; x.rules = {"PLANIFICADOR_P2"}; }
  if (w.fast_done > 0) {
    snprintf(b, sizeof(b), "%d de los %d rápidos de la pauta ya hechos esta semana: se planifica%s %d en los días que quedan",
             w.fast_done, target, remaining == 1 ? "" : "n", remaining);
    w.notes.push_back({"PLANIFICADOR_P1", b, kEvP1});
  }
  if (placed < remaining) {
    snprintf(b, sizeof(b), "solo cabe%s %d de los %d rápidos que faltan de la pauta en la semana por las separaciones (≥ %d días entre rápidos y días sin rápido alrededor de las carreras)",
             placed == 1 ? "" : "n", placed, remaining, min_gap);
    w.notes.push_back({"PLANIFICADOR_P2", b, std::string(kEvP1) + "; " + kEvP2 + "; " + kEvRT + "; " + kEvRace});
  }

  // P5: media diaria de distancia rápida en 60 d frente al P75 propio de esa media; no penaliza el último mes.
  if (at - first_day + 1 >= P.p5_min_history_days) {
    auto mean_win = [&](long from, long to) {   // media diaria (días sin sesión = 0)
      double s = 0;
      for (auto it = daily.lower_bound(from); it != daily.end() && it->first <= to; ++it) s += it->second.first;
      return s / (double)(to - from + 1);
    };
    std::vector<double> roll;
    for (long d = first_day + P.p5_window_days - 1; d < at; d++) roll.push_back(mean_win(d - P.p5_window_days + 1, d));
    if (roll.size() >= 30) {
      w.p5_p75_m = pct(roll, P.p5_percentile / 100.0);
      w.p5_mean_m = mean_win(at - P.p5_window_days + 1, at);
      double older = mean_win(at - P.p5_window_days + 1, at - 30);
      if (w.p5_mean_m > w.p5_p75_m && older > w.p5_p75_m) {
        snprintf(b, sizeof(b), "distancia rápida media de %d d de %.0f m/día, por encima de su P%.0f propio (%.0f m/día) también fuera del último mes: acumulación sostenida",
                 P.p5_window_days, w.p5_mean_m, P.p5_percentile, w.p5_p75_m);
        w.notes.push_back({"PLANIFICADOR_P5", b, "Estberg 1998 (60 d > P75) [E-r]; Hitchens 2018: el último mes no es riesgo y los meses 3–4 sí [E]; P75 propio [I]"});
      }
    }
  }
  // P6: descansos (huecos sin sesiones ≥ p6_break_min_days).
  {
    long last_break_end = -1, pv = -1;
    for (long d : session_days) { if (pv >= 0 && d - pv - 1 >= P.p6_break_min_days) last_break_end = d; pv = d; }
    if (last_break_end >= 0) w.days_since_break = (int)(at - last_break_end);
    long since = last_break_end >= 0 ? last_break_end : first_day;
    if (at - since >= P.p6_interval_days) {
      if (colt)
        snprintf(b, sizeof(b), "%ld días de trabajo sin un descanso registrado: en potros de 2 años la práctica con menos lesiones son descansos cortos y frecuentes",
                 (long)(at - since));
      else
        snprintf(b, sizeof(b), "%ld días de trabajo sin un descanso ≥ %d d registrado: la práctica son ~2 descansos al año de unas 6 semanas",
                 (long)(at - since), P.p6_break_min_days);
      w.notes.push_back({"PLANIFICADOR_P6", b, colt ? "Wong 2023 (Front Vet Sci): en 2 años, cortos y frecuentes [E]; corte [I]"
                                                    : "Morrice-West 2020: 1,9–2,1 descansos/año de 6,3–6,6 semanas [E]; Wong 2023 [E]; corte [I]"});
    }
  }
  // DM2–DM4: potros de 2 años.
  if (colt) {
    auto sum_win = [&](long from, long to, bool canter) {
      double s = 0;
      for (auto it = daily.lower_bound(from); it != daily.end() && it->first <= to; ++it) s += canter ? it->second.second : it->second.first;
      return s;
    };
    bool a3 = false;
    for (const auto& f : kb.flags) if (f.rule.compare(0, 2, "A3") == 0) a3 = true;
    for (int win : {7, 14, 30}) {
      if (win == 30 && a3) continue;   // ya lo dice A3 (rampa de 30 d)
      long ws = at - win + 1;
      long hist = ws - block_start;
      if (hist < P.dm2_min_history_days) continue;
      for (int k = 0; k < 2; k++) {
        bool canter = k == 1;
        double cur = sum_win(ws, at, canter) / win;
        double base = sum_win(block_start, ws - 1, canter) / (double)hist;
        double minv = canter ? P.dm2_min_canter_m : P.dm2_min_fast_m;
        if (sum_win(ws, at, canter) < minv || base <= 0 || cur / base <= P.dm2_ratio) continue;
        snprintf(b, sizeof(b), "%s de los últimos %d d: %.0f m/día, %.1f veces su media acumulada del bloque (%.0f m/día): subir por escalones",
                 canter ? "canter" : "trabajo rápido", win, cur, cur / base, base);
        w.notes.push_back({"PLANIFICADOR_DM2", b, "Verheyen 2005 [E-ag] y Crawford 2021 [E]: bloques súbitos de canter o rápido frente a acumulación gradual; corte [I]"});
      }
    }
    if (last_fast >= 0 && last_fast > at - 7) {
      std::vector<double> slow;
      for (const auto& e : daily) if (e.first > at - 30 && e.first <= at && e.second.first < kc.gallop_session_min_m) slow.push_back(e.second.second);
      double ms = med(slow);
      double fc = daily[last_fast].second;
      if (!std::isnan(ms) && slow.size() >= 3 && fc > ms) {
        snprintf(b, sizeof(b), "el día de rápido (%s) llevó %.0f m de canter, más que la mediana de los días lentos (%.0f m): reducir el canter ese día",
                 kb_day_text(last_fast).c_str(), fc, ms);
        w.notes.push_back({"PLANIFICADOR_DM3", b, "Boston & Nunamaker 2000 [E-r] (galope a ~11 m/s se asoció a más DMD y el breeze a menos); Verheyen 2005 [E-ag]; forma [I]"});
      }
    }
    if (w.prep_weeks < P.dm4_weeks) {
      double recent = 0, before = 0;
      for (long d : fast) {
        if (d < block_start) continue;
        if (d > at - 7) recent = std::max(recent, daily[d].first);
        else before = std::max(before, daily[d].first);
      }
      if (recent >= P.dm4_to_m && before < P.dm4_to_m) {
        snprintf(b, sizeof(b), "salto del trabajo rápido a %.0f m (antes como mucho %.0f m) en la semana %d de preparación: la pauta sube por escalones (≈ %.0f → %.0f m después de %d–16 semanas)",
                 recent, before, w.prep_weeks + 1, P.dm4_from_m, P.dm4_to_m, P.dm4_weeks);
        w.notes.push_back({"PLANIFICADOR_DM4", b, "Oliveira 2006 [E]: 10 de 19 casos en la fase de 700 m (n = 42, Brasil); cortes [I]; nunca una predicción"});
      }
    }
  }
  if (w.breed == "ARABE")
    w.notes.push_back({"PLANIFICADOR_ARABE", "árabe de carreras en llano: pautas extrapoladas del PSI, sin programa semanal publicado en árabes",
                       "[I-raza]; velocidades ya escaladas por el ritmo de carrera (bandas relativas de KB-1)"});
  if (w.age_years < 0)
    w.notes.push_back({"PLANIFICADOR_EDAD", "sin edad del caballo (opción «fecha_nacimiento» o «edad_anos»): no se aplican las pautas de potros de 2 años (DM1–DM4)", "[I]"});
  return w;
}

std::string training_week_plan_json(const WeekPlan& w, const TrainingConfig& c) {
  const auto& P = c.planner;
  std::ostringstream o;
  auto opt = [](int v) { return v < 0 ? std::string("null") : std::to_string(v); };
  o << "{\"disponible\":" << (w.available ? "true" : "false");
  if (!w.available) { o << ",\"motivo\":" << q(w.reason) << ",\"dias\":[],\"pautas\":[]}"; return o.str(); }
  o << ",\"desde\":" << q(kb_day_text(w.from_day)) << ",\"hasta\":" << q(kb_day_text(w.to_day)) << ",\"fase\":" << q(w.phase)
    << ",\"limitada\":" << (w.limited ? "true" : "false") << ",\"edad_anos\":" << opt(w.age_years)
    << ",\"edad_origen\":" << (w.age_origin.empty() ? std::string("null") : q(w.age_origin))
    << ",\"raza\":" << (w.breed.empty() ? std::string("null") : q(w.breed))
    << ",\"semana_calendario\":" << (w.calendar_week ? "true" : "false") << ",\"planifica_desde\":" << q(kb_day_text(w.plan_from_day))
    << ",\"rapidos_objetivo\":" << w.fast_target << ",\"rapidos_hechos\":" << w.fast_done << ",\"rapidos_propuestos\":" << w.fast_planned
    << ",\"dias_lentos_bloque\":" << opt(w.slow_days_done)
    << ",\"vuelta_rapido\":" << (w.return_fast_day < 0 ? std::string("null") : q(kb_day_text(w.return_fast_day)))
    << ",\"semanas_preparacion\":" << opt(w.prep_weeks) << ",\"rapido_ref_m\":" << num(w.fast_ref_m)
    << ",\"rapido_max_m\":" << num(w.fast_max_m) << ",\"p5_media_60d_m\":" << num(w.p5_mean_m) << ",\"p5_p75_m\":" << num(w.p5_p75_m)
    << ",\"dias_desde_descanso\":" << opt(w.days_since_break) << ",\"dias\":[";
  for (size_t i = 0; i < w.days.size(); i++) {
    const PlanDay& x = w.days[i];
    o << (i ? "," : "") << "{\"fecha\":" << q(kb_day_text(x.day)) << ",\"tipo\":" << q(x.type) << ",\"motivo\":" << q(x.reason)
      << ",\"realizado\":" << (x.done ? "true" : "false") << ",\"rapido_max_m\":" << num(x.fast_max_m) << ",\"reglas\":[";
    for (size_t k = 0; k < x.rules.size(); k++) o << (k ? "," : "") << q(x.rules[k]);
    o << "]}";
  }
  o << "],\"pautas\":[";
  for (size_t i = 0; i < w.notes.size(); i++)
    o << (i ? "," : "") << "{\"regla\":" << q(w.notes[i].rule) << ",\"texto\":" << q(w.notes[i].text) << ",\"evidencia\":" << q(w.notes[i].evidence) << "}";
  o << "],\"parametros\":{\"rapidos_semana_maduro\":" << P.fast_per_week_mature << ",\"rapidos_semana_2anos\":" << P.fast_per_week_2y
    << ",\"semana_calendario\":" << (P.calendar_week ? "true" : "false") << ",\"dias_min_entre_rapidos\":" << P.min_days_between_fast << ",\"dias_libres\":" << P.free_days
    << ",\"dias_sin_rapido_precarrera\":" << P.prerace_no_fast_days << ",\"dias_sin_rapido_poscarrera\":" << P.postrace_no_fast_days
    << ",\"p4_dias_lentos\":" << P.p4_slow_days << ",\"p7_dias_ventana\":" << P.p7_window_days << ",\"p7_fraccion_distancia\":" << num(P.p7_distance_fraction)
    << ",\"p5_dias\":" << P.p5_window_days << ",\"p5_percentil\":" << num(P.p5_percentile) << ",\"p6_descanso_min_dias\":" << P.p6_break_min_days
    << ",\"p6_intervalo_dias\":" << P.p6_interval_days << ",\"dm1_rapido_max_m\":" << num(P.dm1_fast_max_m) << ",\"dm2_ratio\":" << num(P.dm2_ratio)
    << ",\"dm4_semanas\":" << P.dm4_weeks << ",\"dm4_desde_m\":" << num(P.dm4_from_m) << ",\"dm4_hasta_m\":" << num(P.dm4_to_m)
    << ",\"etiquetas\":{\"rapidos_semana\":\"E (práctica) / I (objetivo)\",\"separaciones\":\"I\",\"p4_dias_lentos\":\"E\",\"p7\":\"E-r / I\","
       "\"p5\":\"E-r / I\",\"p6\":\"E / I\",\"dm1_dm4\":\"E (Oliveira 2006, n = 42) / I\",\"dm2\":\"I\"}}"
    << ",\"validado\":false,\"nota\":\"propuesta orientativa sin calibrar con datos propios; no sube el estado, no predice lesiones y el entrenador decide\"}";
  return o.str();
}

}  // namespace avoeq
