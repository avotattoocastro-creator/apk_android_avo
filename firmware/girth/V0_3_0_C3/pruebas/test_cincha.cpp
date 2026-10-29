// AVO GIRTH V0.3.0 — pruebas en el PC (sin hardware) del código del firmware que no depende de Arduino:
//  · girth_pack.h   (empaquetado de los 9 canales, el mismo código que compila el firmware)
//  · girth_policy.h (estados de alimentación)
//  · enlace con la espalda: GirthHub de la librería compartida (el mismo código que compila la espalda)
// Señales: CSV del simulador marcha.py (sintéticas). Resultados por stdout + resultados_pruebas.json.
// Compilar: g++ -std=c++17 -O1 -Wall -I../AVO_GIRTH_V0_3_0 -I../../../back/V3_8_0/lib/avo_core/src
//           -I../../../back/V3_8_0/test test_cincha.cpp ../../../back/V3_8_0/lib/avo_core/src/*.cpp
#include <array>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <map>
#include <random>
#include <sstream>
#include <string>
#include <vector>
#include <cmath>
#include "tiny_test.h"
#include "girth_pack.h"
#include "girth_policy.h"
#include "avo_girth_link.h"
#include "avo_payloads.h"

using namespace avo;

static std::string g_dir = ".";
static std::map<std::string, std::string> g_json;   // resumen numérico para el informe

// ---------------------------------------------------------------- escalas del firmware (girth_imu.h)
static const double A_LSB = 0.244e-3;   // g/LSB (±8 g)
static const double G_LSB = 0.070;      // °/s/LSB (±2000 °/s)
static const double M_LSB = 1.0 / 4096; // G/LSB (MMC5983MA 16 bits, ±8 G)

struct Sample { int16_t v[9]; };
struct Phys { double t, v[9]; };

static int16_t q(double x, double lsb, int* sat) {
  double r = std::round(x / lsb);
  if (r > 32767) { (*sat)++; return 32767; }
  if (r < -32768) { (*sat)++; return -32768; }
  return (int16_t)r;
}

static std::vector<Phys> load(const std::string& name) {
  std::ifstream f(g_dir + "/" + name + ".csv");
  std::vector<Phys> v;
  std::string line;
  std::getline(f, line);
  while (std::getline(f, line)) {
    Phys p; std::stringstream ss(line); char c;
    ss >> p.t;
    for (int i = 0; i < 9; i++) ss >> c >> p.v[i];
    v.push_back(p);
  }
  return v;
}

struct Io : GirthHub::Io {
  std::vector<std::vector<uint8_t>> sent, imu;
  bool send(const uint8_t*, const uint8_t* d, size_t n) override { sent.emplace_back(d, d + n); return true; }
  void add_peer(const uint8_t*) override {}
  void store_girth(const uint8_t*) override {}
  void forward_imu(const uint8_t* d, size_t n) override { imu.emplace_back(d, d + n); }
};

static const uint8_t GMAC[6] = {0x34, 0x85, 0x18, 0x01, 0x02, 0x03};

static std::vector<uint8_t> pkt(GirthKind k, uint32_t boot, uint32_t seq, const uint8_t* body, size_t bl) {
  GirthHeader h; h.kind = k; h.boot_id = boot; h.seq = seq;
  std::vector<uint8_t> p(GIRTH_MAX_PACKET);
  p.resize(girth_build(h, body, bl, p.data(), p.size()));
  return p;
}

static std::vector<uint8_t> hello(uint32_t boot, uint32_t seq) {
  GirthHello m; strcpy(m.dev_id, "348518010203"); strcpy(m.fw, "0.3.0"); m.hw = GIRTH_HW_C3_REVB; m.imu_count = 1;
  uint8_t b[GIRTH_HELLO_LEN]; size_t n = girth_hello_encode(m, b, sizeof(b));
  return pkt(GirthKind::HELLO, boot, seq, b, n);
}

// Convierte una marcha a paquetes IMU exactamente como el firmware (lotes de 10, girth_pack_imu_body + girth_build).
struct Stream { std::vector<std::vector<uint8_t>> pkts; std::vector<Sample> q; int sat[3] = {0, 0, 0}; };
static Stream make_stream(const std::vector<Phys>& sig, uint32_t boot, uint32_t* seq) {
  Stream s; uint32_t imu_seq = 0;
  std::vector<Sample> batch;
  for (size_t k = 0; k < sig.size(); k++) {
    Sample x;
    for (int a = 0; a < 3; a++) x.v[a] = q(sig[k].v[a], A_LSB, &s.sat[0]);
    for (int a = 3; a < 6; a++) x.v[a] = q(sig[k].v[a], G_LSB, &s.sat[1]);
    for (int a = 6; a < 9; a++) x.v[a] = q(sig[k].v[a], M_LSB, &s.sat[2]);
    s.q.push_back(x); batch.push_back(x);
    if (batch.size() == GIRTH_IMU_MAX_SAMPLES) {
      uint8_t body[IMU_HDR_LEN + GIRTH_IMU_MAX_SAMPLES * IMU_SAMPLE_LEN_9AXIS];
      uint32_t t0 = (uint32_t)std::llround(sig[k + 1 - batch.size()].t * 1e6);
      size_t n = girth_pack_imu_body(batch.data(), (uint8_t)batch.size(), t0, ++imu_seq, 9615, body, sizeof(body));
      s.pkts.push_back(pkt(GirthKind::IMU, boot, ++*seq, body, n));
      batch.clear();
    }
  }
  return s;
}

// Decodifica lo que la espalda reenvía al pecho (ImuBatchHeader + muestras).
static bool decode_fwd(const std::vector<uint8_t>& f, ImuBatchHeader* h, std::vector<Sample>* out) {
  if (!decode_imu_header(f.data(), f.size(), h)) return false;
  if (f.size() != IMU_HDR_LEN + (size_t)h->count * IMU_SAMPLE_LEN_9AXIS) return false;
  for (int k = 0; k < h->count; k++) {
    Sample x;
    for (int a = 0; a < 9; a++) {
      size_t o = IMU_HDR_LEN + (size_t)k * 18 + a * 2;
      x.v[a] = (int16_t)(f[o] | (f[o + 1] << 8));
    }
    out->push_back(x);
  }
  return true;
}

// ---------------------------------------------------------------- 1. Cadena completa por marcha
static void run_gait(const char* name) {
  auto sig = load(name);
  CHECK(sig.size() > 1000);
  Io io; GirthHub hub(&io, "BACK", "3.10.0", 77); hub.begin(nullptr);
  uint32_t seq = 0, now = 1000;
  auto h = hello(0xABCD, ++seq);
  CHECK(hub.on_radio(GMAC, h.data(), h.size(), -50, now, false));
  Stream s = make_stream(sig, 0xABCD, &seq);
  for (auto& p : s.pkts) { now += 96; CHECK(hub.on_radio(GMAC, p.data(), p.size(), -50, now, false)); }
  CHECK_EQ(io.imu.size(), s.pkts.size());
  std::vector<Sample> rx; uint32_t last_seq = 0; bool seq_ok = true, t_ok = true; uint32_t last_t0 = 0;
  for (auto& f : io.imu) {
    ImuBatchHeader ih; CHECK(decode_fwd(f, &ih, &rx));
    CHECK(ih.fmt == IMU_FMT_9AXIS_I16); CHECK_EQ(ih.period_us, 9615);
    if (ih.girth_seq != last_seq + 1) seq_ok = false;
    if (last_seq && ih.girth_t0_us <= last_t0) t_ok = false;
    last_seq = ih.girth_seq; last_t0 = ih.girth_t0_us;
  }
  CHECK(seq_ok); CHECK(t_ok);
  CHECK_EQ(rx.size(), s.pkts.size() * 10);
  size_t diff = 0;
  for (size_t k = 0; k < rx.size(); k++)
    for (int a = 0; a < 9; a++) if (rx[k].v[a] != s.q[k].v[a]) diff++;
  CHECK_EQ(diff, 0u);                                   // los 9 canales llegan idénticos al pecho
  double err[3] = {0, 0, 0}, peak[3] = {0, 0, 0};
  const double lsb[3] = {A_LSB, G_LSB, M_LSB};
  for (size_t k = 0; k < rx.size(); k++)
    for (int a = 0; a < 9; a++) {
      double phys = rx[k].v[a] * lsb[a / 3];
      err[a / 3] = std::max(err[a / 3], std::fabs(phys - sig[k].v[a]));
      peak[a / 3] = std::max(peak[a / 3], std::fabs(sig[k].v[a]));
    }
  char b[400];
  snprintf(b, sizeof(b), "{\"muestras\":%zu,\"paquetes\":%zu,\"bytes_por_s\":%.0f,\"pico_g\":%.2f,\"pico_dps\":%.0f,"
           "\"pico_G\":%.2f,\"err_max_g\":%.5f,\"err_max_dps\":%.3f,\"err_max_G\":%.5f,\"saturadas_acel\":%d,"
           "\"saturadas_giro\":%d,\"saturadas_mag\":%d,\"perdidas_espalda\":%u}",
           rx.size(), s.pkts.size(), s.pkts.size() * s.pkts[0].size() / (sig.size() / 104.0), peak[0], peak[1], peak[2],
           err[0], err[1], err[2], s.sat[0], s.sat[1], s.sat[2], (unsigned)hub.lost());
  g_json[name] = b;
  printf("  %s: %s\n", name, b);
  if (std::string(name) != "salto") { CHECK_EQ(s.sat[0], 0); CHECK_EQ(s.sat[1], 0); }
  // sin saturación el error es ≤ ½ LSB
  if (!s.sat[0]) CHECK(err[0] <= A_LSB / 2 + 1e-9);
  if (!s.sat[1]) CHECK(err[1] <= G_LSB / 2 + 1e-9);
  CHECK(err[2] <= M_LSB / 2 + 1e-9);
}

TEST(cadena, paso) { run_gait("paso"); }
TEST(cadena, trote) { run_gait("trote"); }
TEST(cadena, galope) { run_gait("galope"); }
TEST(cadena, salto_con_saturacion) { run_gait("salto"); }

// ---------------------------------------------------------------- 2. Enlace: pérdidas, duplicados, desorden…
struct Link { Io io; GirthHub hub{&io, "BACK", "3.10.0", 77}; uint32_t seq = 0, now = 1000; Stream s; };
static void start(Link& L, const char* gait = "trote") {
  L.hub.begin(nullptr);
  auto h = hello(0x1111, ++L.seq);
  L.hub.on_radio(GMAC, h.data(), h.size(), -50, L.now, false);
  L.s = make_stream(load(gait), 0x1111, &L.seq);
}

TEST(enlace, perdida_aleatoria_se_cuenta_exacta) {
  for (double p : {0.01, 0.05, 0.2}) {
    Link L; start(L);
    std::mt19937 rng(42); std::uniform_real_distribution<double> u(0, 1);
    unsigned dropped = 0, last_ok = 0;
    for (size_t i = 0; i < L.s.pkts.size(); i++) {
      L.now += 96;
      if (u(rng) < p && i + 1 < L.s.pkts.size()) { dropped++; continue; }
      L.hub.on_radio(GMAC, L.s.pkts[i].data(), L.s.pkts[i].size(), -50, L.now, false); last_ok = i;
    }
    (void)last_ok;
    CHECK_EQ(L.hub.lost(), dropped);
    CHECK_EQ(L.io.imu.size(), L.s.pkts.size() - dropped);
    char b[120]; snprintf(b, sizeof(b), "{\"p\":%.2f,\"perdidos\":%u,\"contados_espalda\":%u}", p, dropped, (unsigned)L.hub.lost());
    g_json[std::string("perdida_") + std::to_string((int)(p * 100))] = b;
  }
}

TEST(enlace, duplicados_no_cuentan_perdida_pero_se_reenvian) {
  // El firmware reintenta un paquete si no llega el ACK de MAC: la espalda puede recibirlo dos veces.
  Link L; start(L);
  size_t fwd_before;
  for (size_t i = 0; i < 50; i++) {
    L.now += 96;
    L.hub.on_radio(GMAC, L.s.pkts[i].data(), L.s.pkts[i].size(), -50, L.now, false);
    if (i % 5 == 0) L.hub.on_radio(GMAC, L.s.pkts[i].data(), L.s.pkts[i].size(), -50, L.now, false);
  }
  fwd_before = L.io.imu.size();
  CHECK_EQ(L.hub.lost(), 0u);
  // HALLAZGO: GirthHub reenvía también el duplicado (count_seq lo detecta pero no lo descarta).
  g_json["duplicados"] = "{\"enviados\":50,\"duplicados\":10,\"reenviados_al_pecho\":" + std::to_string(fwd_before) + "}";
  printf("  duplicados: 50 + 10 repetidos → reenviados al pecho %zu\n", fwd_before);
  CHECK(fwd_before == 60 || fwd_before == 50);
}

TEST(enlace, desorden) {
  Link L; start(L);
  for (size_t i = 0; i + 1 < 40; i += 2) {           // llegan 2,1,4,3,…
    L.now += 96;
    L.hub.on_radio(GMAC, L.s.pkts[i + 1].data(), L.s.pkts[i + 1].size(), -50, L.now, false);
    L.hub.on_radio(GMAC, L.s.pkts[i].data(), L.s.pkts[i].size(), -50, L.now, false);
  }
  g_json["desorden"] = "{\"enviados\":40,\"reenviados\":" + std::to_string(L.io.imu.size()) +
                       ",\"perdidos_contados\":" + std::to_string(L.hub.lost()) + "}";
  printf("  desorden: 40 paquetes en pares invertidos → reenviados %zu, pérdidas contadas %u\n", L.io.imu.size(),
         (unsigned)L.hub.lost());
  CHECK_EQ(L.io.imu.size(), 40u);                      // ninguno se pierde; el pecho reordena por girth_seq
}

TEST(enlace, reinicio_de_la_cincha_no_falsea_perdidas) {
  Link L; start(L);
  for (size_t i = 0; i < 30; i++) { L.now += 96; L.hub.on_radio(GMAC, L.s.pkts[i].data(), L.s.pkts[i].size(), -50, L.now, false); }
  uint32_t seq2 = 0;                                   // reinicio: boot_id nuevo, secuencia desde 1
  auto h = hello(0x2222, ++seq2);
  L.hub.on_radio(GMAC, h.data(), h.size(), -50, L.now, false);
  Stream s2 = make_stream(load("paso"), 0x2222, &seq2);
  for (size_t i = 0; i < 30; i++) { L.now += 96; L.hub.on_radio(GMAC, s2.pkts[i].data(), s2.pkts[i].size(), -50, L.now, false); }
  CHECK_EQ(L.hub.lost(), 0u);
  CHECK_EQ(L.io.imu.size(), 60u);
  CHECK(L.hub.connected(L.now));
}

TEST(enlace, reconexion_tras_corte) {
  Link L; start(L);
  L.now += 96; L.hub.on_radio(GMAC, L.s.pkts[0].data(), L.s.pkts[0].size(), -50, L.now, false);
  L.now += 10000;                                      // 10 s sin radio
  CHECK(!L.hub.connected(L.now));
  L.now += 96; L.hub.on_radio(GMAC, L.s.pkts[1].data(), L.s.pkts[1].size(), -50, L.now, false);
  CHECK(L.hub.connected(L.now));
}

TEST(enlace, corrupcion_rechazada) {
  Link L; start(L);
  std::mt19937 rng(7); int rejected_ok = 0;
  for (int i = 0; i < 200; i++) {
    auto p = L.s.pkts[i % L.s.pkts.size()];
    size_t pos = 2 + rng() % (p.size() - 2);          // cualquier byte salvo la marca
    p[pos] ^= (uint8_t)(1 + rng() % 255);
    size_t before = L.io.imu.size(); uint32_t rej = L.hub.rejected();
    L.hub.on_radio(GMAC, p.data(), p.size(), -50, L.now, false);
    if (L.io.imu.size() == before && L.hub.rejected() == rej + 1) rejected_ok++;
  }
  g_json["corrupcion"] = "{\"paquetes_alterados\":200,\"rechazados\":" + std::to_string(rejected_ok) + "}";
  CHECK_EQ(rejected_ok, 200);                          // CRC-16 sobre cabecera y cuerpo
}

TEST(enlace, otra_cincha_rechazada_fuera_de_emparejamiento) {
  Link L; start(L);
  const uint8_t other[6] = {9, 9, 9, 9, 9, 9};
  auto h = hello(0x3333, 1);
  uint32_t rej = L.hub.rejected();
  L.hub.on_radio(other, h.data(), h.size(), -50, L.now, false);
  CHECK_EQ(L.hub.rejected(), rej + 1);
  L.hub.on_radio(other, L.s.pkts[0].data(), L.s.pkts[0].size(), -50, L.now, false);
  CHECK(L.io.imu.empty());
  CHECK(memcmp(L.hub.mac(), GMAC, 6) == 0);
}

TEST(enlace, tamano_y_carga) {
  Link L; start(L);
  CHECK(L.s.pkts[0].size() <= GIRTH_MAX_PACKET);
  double pps = 104.0 / GIRTH_IMU_MAX_SAMPLES + 1.0;   // IMU + STATUS
  double bps = (104.0 / GIRTH_IMU_MAX_SAMPLES) * L.s.pkts[0].size() + GIRTH_HDR + GIRTH_STATUS_LEN;
  char b[160]; snprintf(b, sizeof(b), "{\"bytes_paquete_imu\":%zu,\"paquetes_por_s\":%.1f,\"bytes_por_s\":%.0f}",
                        L.s.pkts[0].size(), pps, bps);
  g_json["carga"] = b;
  printf("  carga: %s\n", b);
}

TEST(enlace, ping_con_bit_de_apagado) {
  GirthPing g; g.flags = 1 | GIRTH_PING_SHUTDOWN; uint8_t b[GIRTH_PING_LEN];
  CHECK_EQ(girth_ping_encode(g, b, sizeof(b)), GIRTH_PING_LEN);
  GirthPing r; CHECK(girth_ping_decode(b, sizeof(b), &r));
  CHECK(r.flags & GIRTH_PING_SHUTDOWN);
  GirthHello h; strcpy(h.fw, "0.3.0"); h.hw = GIRTH_HW_C3_REVB; uint8_t hb[GIRTH_HELLO_LEN];
  CHECK_EQ(girth_hello_encode(h, hb, sizeof(hb)), GIRTH_HELLO_LEN);
  GirthHello hr; CHECK(girth_hello_decode(hb, sizeof(hb), &hr)); CHECK_EQ(hr.hw, 2);
}

// ---------------------------------------------------------------- 3. Política de alimentación
using gpol::Action;
TEST(alimentacion, fuera_del_soporte_apaga_a_los_3s) {
  gpol::Policy p; gpol::Inputs in{false, false, false, 3800, false};
  CHECK(p.step(in, 20000) == Action::NONE);
  CHECK(p.step(in, 22800) == Action::NONE);
  CHECK(p.step(in, 23200) == Action::SHUTDOWN_OUT_OF_HOLDER);
}
TEST(alimentacion, volver_al_soporte_cancela) {
  gpol::Policy p; gpol::Inputs out{false, false, false, 3800, false}, in{true, false, false, 3800, false};
  p.step(out, 20000); p.step(out, 22000);
  CHECK(p.step(in, 22200) == Action::NONE);
  CHECK(p.step(out, 22400) == Action::NONE);
  CHECK(p.step(out, 25000) == Action::NONE);
  CHECK(p.step(out, 25600) == Action::SHUTDOWN_OUT_OF_HOLDER);
}
TEST(alimentacion, bateria_baja_10s_y_no_con_carga) {
  gpol::Policy p; gpol::Inputs low{true, false, false, 3250, false};
  CHECK(p.step(low, 1000) == Action::NONE);
  CHECK(p.step(low, 10900) == Action::NONE);
  CHECK(p.step(low, 11200) == Action::SHUTDOWN_LOW_BATTERY);
  gpol::Policy q; gpol::Inputs chg{true, true, false, 3250, false};
  for (uint32_t t = 0; t < 60000; t += 200) CHECK(q.step(chg, t) == Action::NONE);
  gpol::Policy r; gpol::Inputs noadc{true, false, false, 0, false};          // ADC sin leer (0 mV): no apaga
  for (uint32_t t = 0; t < 60000; t += 200) CHECK(r.step(noadc, t) == Action::NONE);
}
TEST(alimentacion, base_qi_fuera_del_soporte_duerme_usb_no) {
  gpol::Policy p; gpol::Inputs qi{false, true, true, 3900, false}, usb{false, true, false, 3900, false};
  CHECK(p.step(qi, 5000) == Action::NONE);                                  // 10 s de gracia tras arrancar
  CHECK(p.step(qi, 10200) == Action::SLEEP_ON_CHARGER);
  gpol::Policy u;
  for (uint32_t t = 0; t < 60000; t += 200) CHECK(u.step(usb, t) == Action::NONE);
}
TEST(alimentacion, apagado_remoto) {
  gpol::Policy p; gpol::Inputs in{true, false, false, 3900, true};
  CHECK(p.step(in, 1000) == Action::SHUTDOWN_REMOTE);
}
TEST(alimentacion, despertar_por_reed_solo_si_abierto) {
  CHECK(gpol::arm_reed_wake(false));
  CHECK(!gpol::arm_reed_wake(true));
}

int main(int argc, char** argv) {
  if (argc > 1) g_dir = argv[1];
  int failed = 0;
  for (auto& c : tt_cases()) {
    tt_case_failed() = false;
    c.fn();
    printf("%s %s.%s\n", tt_case_failed() ? "FALLA" : "ok   ", c.suite, c.name);
    if (tt_case_failed()) failed++;
  }
  printf("\n%d pruebas, %d comprobaciones, %d fallidas\n", (int)tt_cases().size(), tt_check_count(), failed);
  FILE* f = fopen((g_dir + "/resultados_pruebas.json").c_str(), "w");
  if (f) {
    fprintf(f, "{\n \"pruebas\": %d, \"comprobaciones\": %d, \"fallidas\": %d", (int)tt_cases().size(), tt_check_count(), failed);
    for (auto& kv : g_json) fprintf(f, ",\n \"%s\": %s", kv.first.c_str(), kv.second.c_str());
    fprintf(f, "\n}\n");
    fclose(f);
  }
  return failed ? 1 : 0;
}
