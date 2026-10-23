// avo_eq_cli — analyse an AVO RAW session from the command line (Windows / Linux / macOS).
//   avo_eq_cli SESSION.avo [SEGMENT2.avo ...] [--out DIR] [--series]
// Writes analysis.json, gnss.csv, aires.csv, cadencia.csv in DIR (default: current directory).
#include <cstdio>
#include <ctime>
#include <fstream>
#include <string>
#include <vector>
#include "avo_eq/engine.h"
#include "avo_eq/ingestion.h"

int main(int argc, char** argv) {
  std::vector<std::string> files;
  std::string out = ".";
  bool series = false;
  for (int i = 1; i < argc; i++) {
    std::string a = argv[i];
    if (a == "--out" && i + 1 < argc) out = argv[++i];
    else if (a == "--series") series = true;
    else files.push_back(a);
  }
  if (files.empty()) { fprintf(stderr, "uso: avo_eq_cli SESION.avo [...] [--out DIR] [--series]\n"); return 2; }
  avoeq::Session s; std::string err;
  if (!avoeq::ingest_raw(files, &s, &err)) { fprintf(stderr, "error: %s\n", err.c_str()); return 1; }
  char when[32]; std::time_t now = std::time(nullptr); std::strftime(when, sizeof(when), "%Y-%m-%dT%H:%M:%SZ", std::gmtime(&now));
  avoeq::EngineConfig c;
  avoeq::Analysis a = avoeq::analyse(s, c, when);
  auto put = [&](const char* name, const std::string& data) { std::ofstream f(out + "/" + name, std::ios::binary); f << data; };
  put("analysis.json", avoeq::to_json(a, s, c, series));
  put("gnss.csv", avoeq::gnss_csv(a));
  put("aires.csv", avoeq::gait_csv(a));
  put("cadencia.csv", avoeq::cadence_csv(a));
  printf("sesión %s: %zu épocas GNSS, %zu muestras IMU -> %s/analysis.json\n", s.session_id.c_str(), s.gnss.size(), s.imu.size(), out.c_str());
  return 0;
}
