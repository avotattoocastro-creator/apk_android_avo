// Host preview + checks for the V3.7.2 watch UI. Compiles the SAME ui_fb / ui_dash / ui_model
// code as the firmware, with a simulated CO5300 panel. Output: PPM images of what the rider sees.
// Scenario values are TEST INPUTS for the preview only; the firmware reads the live snapshot.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vector>
#include <string>
#include "ui_fb.h"
#include "ui_dash.h"
#include "ui_model.h"

static int failures = 0;
#define CHECK(c, msg) do { if (!(c)) { printf("FAIL: %s\n", msg); ++failures; } } while (0)

// Simulated panel in PHYSICAL orientation; checks the CO5300 even-alignment rule.
struct HostPanel : UiPanel {
  std::vector<uint16_t> phys = std::vector<uint16_t>(UiFb::W * UiFb::H, 0x1234);
  uint32_t pushes = 0, odd = 0;
  void push(int16_t x, int16_t y, const uint16_t* p, int16_t w, int16_t h) override {
    ++pushes;
    if ((x & 1) || (y & 1) || (w & 1) || (h & 1)) ++odd;
    for (int j = 0; j < h; ++j) memcpy(&phys[(y + j) * UiFb::W + x], &p[j * w], (size_t)w * 2);
  }
};

static void save_rider_view(const HostPanel& panel, bool rotated, const std::string& path) {
  FILE* f = fopen(path.c_str(), "wb");
  fprintf(f, "P6\n%d %d\n255\n", UiFb::W, UiFb::H);
  for (int y = 0; y < UiFb::H; ++y)
    for (int x = 0; x < UiFb::W; ++x) {
      // The panel is mounted upside down: the rider sees the physical image turned 180°.
      const int px = rotated ? UiFb::W - 1 - x : x, py = rotated ? UiFb::H - 1 - y : y;
      const uint16_t c = panel.phys[py * UiFb::W + px];
      const unsigned char rgb[3] = {(unsigned char)(((c >> 11) & 31) * 255 / 31),
                                    (unsigned char)(((c >> 5) & 63) * 255 / 63),
                                    (unsigned char)((c & 31) * 255 / 31)};
      fwrite(rgb, 1, 3, f);
    }
  fclose(f);
}

static const uint32_t NOW = 600000;

static AppSnapshot all_ok() {
  AppSnapshot s;
  s.ble.connected = true; s.ble.authorized = true;
  s.link.connected = true; s.link.last_rx_ms = NOW - 100; s.link.transport = 1; s.link.now_rssi = -46;
  s.girth.connected = true;
  for (int k = 0; k < 3; ++k) s.girth.last_batch_ms[k] = NOW - 200;
  s.gnss.have = true; s.gnss.rx_ms = NOW - 100;
  s.gnss.s.flags = 0x01 | 0x02 | (2 << 6); s.gnss.s.fix_type = 3; s.gnss.s.num_sv = 28;
  s.gnss.s.hacc_mm = 14; s.gnss.s.vacc_mm = 21;
  s.rtcm.flowing = true;
  s.storage.mounted = true; s.storage.rec = RecStatus::RECORDING;
  s.session.metrics.active_ms = (12 * 60 + 36) * 1000; s.storage.session_bytes = 1200000000ULL;
  s.storage.card_bytes = 32000000000ULL; s.storage.free_bytes = 30000000000ULL;
  s.power.pmu.online = true; s.power.pmu.batt_pct = 78; s.power.pmu.vbus = true; s.power.pmu.charging = true;
  s.sys.cpu_temp_c = 28.2f;
  return s;
}

static AppSnapshot nothing() {
  AppSnapshot s;
  s.power.pmu.online = true; s.power.pmu.batt_pct = 15;
  return s;
}

static AppSnapshot mixed() {
  AppSnapshot s = all_ok();
  s.ble.connected = false; s.ble.authorized = false; s.ble.claim_pending = true;
  s.girth.last_batch_ms[2] = NOW - 9000;              // one IMU silent
  s.gnss.s.flags = 0x01; s.gnss.s.num_sv = 17; s.gnss.s.hacc_mm = 1800; s.gnss.s.vacc_mm = 2600;
  s.rtcm.flowing = false;                             // autonomous -> blue
  s.storage.rec = RecStatus::IDLE;
  s.power.pmu.batt_pct = 42; s.power.pmu.vbus = false; s.power.pmu.charging = false;
  s.link.now_rssi = -71;
  return s;
}

int main(int argc, char** argv) {
  const std::string out = argc > 1 ? argv[1] : ".";
  static uint16_t fbmem[UiFb::W * UiFb::H];
  static uint16_t line[UiFb::W * 16];
  UiFb fb;

  struct Scene { const char* name; int kind; AppSnapshot snap; };
  std::vector<Scene> scenes = {
    {"1_todo_correcto", 0, all_ok()}, {"2_sin_conexiones", 0, nothing()}, {"3_mixto", 0, mixed()},
    {"4_ota_63", 1, AppSnapshot()}, {"5_ota_verificada", 2, AppSnapshot()},
    {"6_apagando", 3, AppSnapshot()}, {"7_carga_85", 4, AppSnapshot()},
    {"8_apagado_fallido", 5, AppSnapshot()}, {"9_carga_completa", 6, AppSnapshot()}};

  for (auto& sc : scenes) {
    HostPanel panel;
    fb.attach(fbmem, line, sizeof(line) / 2, true);
    dash::Model m;
    switch (sc.kind) {
      case 0: ui_model::build(sc.snap, NOW, &m); dash::draw_dashboard(fb, m); break;
      case 1: dash::draw_ota_progress(fb, 63, "63%"); break;
      case 2: dash::draw_ota_notice(fb, true, "OTA VERIFICADA", "ESPERA REINICIO"); break;
      case 3: dash::draw_shutdown(fb, 2); break;
      case 4: { dash::BatteryModel b; b.pct = 85; b.charging = true; b.vbus = true; dash::draw_charging(fb, b); break; }
      case 5: dash::draw_shutdown_failed(fb); break;
      case 6: { dash::BatteryModel b; b.pct = 100; b.charging = false; b.vbus = true; dash::draw_charging(fb, b); break; }
    }
    const uint32_t sent = fb.flush(panel);
    CHECK(panel.odd == 0, "pushes must be even-aligned for the CO5300");
    CHECK(sent == (uint32_t)UiFb::W * UiFb::H, "full screen must be sent on first draw");
    // Rotation check: rider view must equal the logical framebuffer pixel by pixel.
    int mismatch = 0;
    for (int y = 0; y < UiFb::H; ++y)
      for (int x = 0; x < UiFb::W; ++x)
        if (panel.phys[(UiFb::H - 1 - y) * UiFb::W + (UiFb::W - 1 - x)] != fb.get(x, y)) ++mismatch;
    CHECK(mismatch == 0, "180-degree flush must map every pixel exactly");
    save_rider_view(panel, true, out + "/" + sc.name + ".ppm");

    if (sc.kind == 0) {
      for (int i = 0; i < dash::CARD_COUNT; ++i) {
        char msg[64]; snprintf(msg, sizeof msg, "%s: card %d text overflows its slot", sc.name, i);
        CHECK(dash::card_text_fits(i, m), msg);
      }
      // Partial update: change only the GPS card and check only that card is sent.
      dash::Model m2 = m;
      snprintf(m2.card[dash::GPS].r1, sizeof m2.card[dash::GPS].r1, "Sats: 31");
      int changed = 0;
      for (int i = 0; i < dash::CARD_COUNT; ++i)
        if (dash::card_hash(i, m2) != dash::card_hash(i, m)) { dash::draw_card(fb, i, m2); ++changed; }
      CHECK(changed == 1, "only one card hash must change");
      const uint32_t part = fb.flush(panel);
      CHECK(part > 0 && part < 410u * 80u, "partial update must send only one card strip");
      CHECK(panel.odd == 0, "partial pushes must be even-aligned");
    }
    printf("%-18s ok (pushes=%u)\n", sc.name, panel.pushes);
  }

  // Model rules (spec UI_7_FRANJAS): checked on the real builder.
  {
    dash::Model m;
    AppSnapshot s = all_ok();
    ui_model::build(s, NOW, &m);
    CHECK(m.card[dash::GPS].color == dash::C_GREEN, "RTK with NTRIP corrections must be green");
    CHECK(!strcmp(m.card[dash::GPS].state, "RTK FIX"), "RTK FIX state");
    CHECK(m.card[dash::SD].color == dash::C_YELLOW, "recording must be yellow");
    CHECK(!strcmp(m.card[dash::SD].r1, "00:12:36"), "recording time");
    CHECK(!strcmp(m.card[dash::BATERIA].state, "Cargando..."), "charging only when charger charges");
    s.rtcm.flowing = false; ui_model::build(s, NOW, &m);
    CHECK(m.card[dash::GPS].color == dash::C_BLUE, "no NTRIP -> blue");
    s.gnss.rx_ms = NOW - 5000; ui_model::build(s, NOW, &m);
    CHECK(m.card[dash::GPS].color == dash::C_RED && !m.card[dash::GPS].good, "stale GNSS never OK");
    s = all_ok(); s.link.last_rx_ms = NOW - 2500; ui_model::build(s, NOW, &m);
    CHECK(m.card[dash::ESPALDA].color == dash::C_RED, "stale back link -> red");
    CHECK(m.card[dash::CINCHA].color == dash::C_GREEN, "girth evaluated on its own data");
    s = all_ok(); s.power.pmu.batt_pct = 42; ui_model::build(s, NOW, &m);
    CHECK(m.card[dash::BATERIA].color == dash::C_YELLOW, "21-50% yellow");
    s.power.pmu.batt_pct = 20; ui_model::build(s, NOW, &m);
    CHECK(m.card[dash::BATERIA].color == dash::C_RED, "<=20% red");
    s.power.pmu.batt_pct = -1; ui_model::build(s, NOW, &m);
    CHECK(m.batt.pct == -1 && m.card[dash::BATERIA].color == dash::C_YELLOW, "unknown -> --% warning");
    s = all_ok(); s.power.pmu.charging = false; s.power.pmu.batt_pct = 100; ui_model::build(s, NOW, &m);
    CHECK(!strcmp(m.card[dash::BATERIA].state, "Carga completa"), "full charge text");
    s = all_ok(); s.girth.last_batch_ms[1] = 0; ui_model::build(s, NOW, &m);
    CHECK(m.card[dash::CINCHA].color == dash::C_RED && !strcmp(m.card[dash::CINCHA].r1, "2 IMU"), "2/3 IMU is not OK");
  }

  // Worst-case strings must still fit.
  {
    dash::Model m; AppSnapshot s = all_ok();
    s.gnss.s.num_sv = 199; s.gnss.s.hacc_mm = 99999; s.gnss.s.vacc_mm = 88888;
    s.link.now_rssi = -100; s.session.metrics.active_ms = 99u * 3600 * 1000 + 59000;
    s.storage.session_bytes = 999000000000ULL; s.sys.cpu_temp_c = 99.6f;
    ui_model::build(s, NOW, &m);
    for (int i = 0; i < dash::CARD_COUNT; ++i) {
      char msg[64]; snprintf(msg, sizeof msg, "worst case: card %d overflows", i);
      CHECK(dash::card_text_fits(i, m), msg);
    }
  }

  // Titles must fit their slot with the largest font (no fallback needed) for the normal states.
  {
    dash::Model m; ui_model::build(all_ok(), NOW, &m);
    static uint16_t mem[UiFb::W * UiFb::H]; static uint16_t ln[UiFb::W * 4];
    UiFb t; t.attach(mem, ln, UiFb::W * 4, true);
    dash::draw_dashboard(t, m);
    HostPanel p; t.flush(p);
    // Blink: only the dot square is re-sent, and the SD card around it is unchanged.
    for (int k = 0; k < 2; ++k) {
      dash::draw_rec_dot(t, m, k == 1);
      const uint32_t px = t.flush(p);
      CHECK(px > 0 && px <= 30u * 30u, "blink must send only the dot square");
      CHECK(p.odd == 0, "blink pushes even-aligned");
    }
    const int top = dash::card_top(dash::SD);
    CHECK(t.get(300, top + 10) == dash::C_YELLOW, "yellow card untouched by blink");
    dash::Model idle; AppSnapshot s = all_ok(); s.storage.rec = RecStatus::IDLE; ui_model::build(s, NOW, &idle);
    CHECK(!dash::rec_dot_active(idle), "no blinking dot when not recording");
  }

  printf(failures ? "\n%d CHECKS FAILED\n" : "\nALL HOST CHECKS PASSED (simulation, not hardware)\n", failures);
  return failures ? 1 : 0;
}
