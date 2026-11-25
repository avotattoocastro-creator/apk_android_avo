// AVO BEACH 1.0.0 (motor 2.0.0-dev36, 25/11/2026): marea del entrenamiento y franja de playa AUTOMÁTICA por tramo.
// Petición del usuario (25/11/2026): «tomar en cuenta el estado de la marea y la zona por la que pasan los caballos».
//
// Entradas (opciones del análisis, todas opcionales):
//  - "marea": {"curva": [[unix_s, altura_m], …], "fuente": "IHM …"}   predicción de marea del puerto (la app la tiene)
//  - "playa": {"linea_seca": {"a":[lat,lon], "b":[lat,lon]},          pie de la duna / paseo (cota de las pleamares vivas)
//              "linea_bajamar": {"a":[lat,lon], "b":[lat,lon]},       orilla en una bajamar viva
//              "altura_seca_m": 4.6, "altura_bajamar_m": 0.4,         alturas de marea de esas dos líneas (m, cero hidrográfico)
//              "orilla_m": 40}                                        anchura de la «orilla firme» desde el agua
// Modelo [I] (sin validar): perfil de playa lineal entre las dos líneas. Con la altura de marea h, la orilla está a
//   x_agua = L·(h_seca − h)/(h_seca − h_bajamar) de la línea seca (L = distancia entre líneas). La arena que cubrió la
//   última pleamar (h_pleamar de las 13 h anteriores) llega hasta x_mojada. Para cada época en movimiento:
//   x ≥ x_agua − orilla_m → ORILLA_FIRME · x ≥ x_mojada → TRANSICION · resto → SECA_PROFUNDA.
//   HUMEDA_PROFUNDA no se asigna nunca de forma automática (necesita al jinete: arena húmeda blanda).
// La franja anotada a mano en la ficha de campo manda siempre sobre la automática.
#pragma once
#include <cmath>
#include <cstdint>
#include <string>
#include <utility>
#include <vector>
#include "avo_eq/types.h"

namespace avoeq {

struct BeachLine { bool set = false; double a_lat = 0, a_lon = 0, b_lat = 0, b_lon = 0; };

struct BeachConfig {
  std::vector<std::pair<double, double>> tide;   // (unix s, altura m), ordenada
  std::string tide_source;
  BeachLine dry, low;
  double h_dry = 4.6, h_low = 0.4, shore_m = 40;
  bool any() const { return !tide.empty() || dry.set || low.set; }
};

enum class BeachBand : uint8_t { ORILLA_FIRME = 0, TRANSICION = 1, SECA_PROFUNDA = 2, NONE = 3 };
const char* beach_band_code(BeachBand b);

struct BeachResult {
  bool present = false;            // hay algo que contar (marea y/o franjas)
  // marea
  bool tide = false;
  std::string tide_source;
  double tide_start_m = NAN, tide_work_m = NAN, last_high_m = NAN;
  int tide_trend = 0;              // +1 subiendo, −1 bajando, 0 desconocido (en el inicio del trabajo)
  double tide_phase_pct = NAN;     // % de la subida (o bajada) entre la bajamar y la pleamar que rodean el trabajo
  std::string tide_level;          // BAJA | MEDIA | ALTA (tercio de la altura entre la bajamar y la pleamar del ciclo)
  // franjas
  bool bands = false;
  double dist_m[3] = {0, 0, 0}, work_m[3] = {0, 0, 0};
  std::string work_band;           // franja con más metros en los trabajos (o en movimiento si no hay trabajos)
  double work_band_pct = NAN;      // % de esos metros en la franja dominante
  bool mixed = false;              // dominante < 70 %
  std::vector<uint8_t> band;       // por época (BeachBand), para las series
  std::vector<std::string> warnings;
};

struct Analysis;
// Unix time (s) of every GNSS epoch from the NAV-PVT date/time of the first epoch with valid date and time; NaN if none.
std::vector<double> gnss_unix_s(const Session& s, const std::vector<double>& t);
BeachResult analyse_beach(const Session& s, const Analysis& a, const BeachConfig& c);
double tide_at(const std::vector<std::pair<double, double>>& curve, double unix_s);
// «entorno» block of the analysis JSON.
std::string beach_json(const BeachResult& r);
static const char* const BEACH_VERSION = "1.0.0";

}  // namespace avoeq
