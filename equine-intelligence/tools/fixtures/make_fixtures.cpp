// Writes the SYNTHETIC reference session used by the Kotlin, C# and Android integration tests:
//   synthetic_session.avo  (AVO RAW v1, written with the chest's own writer)
// walk 1.5 m/s (0.95 Hz) -> trot 3.5 m/s (1.45 Hz) with a 180° right turn of R = 20 m -> straight.
// It is clearly synthetic (session id SINTETICA_*) and must never be presented as a real training.
#include <cstdio>
#include "raw_writer.h"
#include "synth.h"

static double f(double t) { return t < 43.2 ? 0.95 : 1.45; }
static double a1(double) { return 260; }
static double a2(double) { return 620; }

int main(int argc, char** argv) {
  const char* out = argc > 1 ? argv[1] : "synthetic_session.avo";
  avoeq::Session s; s.session_id = "SINTETICA_0001";
  s.gnss = synth::track({{43.2, 1.5, 0}, {20, 3.5, 0}, {synth::PI * 20 / 3.5, 3.5, 20}, {12, 3.5, 0}}, 8, nullptr, nullptr, 0.03);
  synth::ImuSpec sp; sp.offset_s = 5.0;
  s.imu = synth::imu_shape(88, f, a1, a2, sp, 0, 7, 30);
  if (!eqfix::write_raw(out, s)) { fprintf(stderr, "no se pudo escribir %s\n", out); return 1; }
  printf("%s: %zu épocas GNSS, %zu muestras IMU (SINTÉTICA)\n", out, s.gnss.size(), s.imu.size());
  return 0;
}
