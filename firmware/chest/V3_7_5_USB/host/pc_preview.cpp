// Host preview of the V3.7.5-usb1 "CONECTADO AL PC" screen. Compiles the SAME ui_fb / ui_dash (+ ui_pc_draw.h)
// code as the firmware with a simulated panel and writes PPM images as the rider sees them.
// Values are TEST INPUTS for the preview only; the firmware shows the live USB and battery state.
#include <stdio.h>
#include <string.h>
#include <string>
#include <vector>
#include "ui_fb.h"
#include "ui_dash.h"
#include "ui_pc.h"

static int failures = 0;
#define CHECK(c, msg) do { if (!(c)) { printf("FAIL: %s\n", msg); ++failures; } } while (0)

struct HostPanel : UiPanel {
  std::vector<uint16_t> phys = std::vector<uint16_t>(UiFb::W * UiFb::H, 0x1234);
  uint32_t odd = 0;
  void push(int16_t x, int16_t y, const uint16_t* p, int16_t w, int16_t h) override {
    if ((x & 1) || (y & 1) || (w & 1) || (h & 1)) ++odd;
    for (int j = 0; j < h; ++j) memcpy(&phys[(y + j) * UiFb::W + x], &p[j * w], (size_t)w * 2);
  }
};

static void save(const HostPanel& panel, const std::string& path) {
  FILE* f = fopen(path.c_str(), "wb");
  fprintf(f, "P6\n%d %d\n255\n", UiFb::W, UiFb::H);
  for (int y = 0; y < UiFb::H; ++y)
    for (int x = 0; x < UiFb::W; ++x) {
      const uint16_t c = panel.phys[(UiFb::H - 1 - y) * UiFb::W + (UiFb::W - 1 - x)];   // panel mounted 180°
      const unsigned char rgb[3] = {(unsigned char)(((c >> 11) & 31) * 255 / 31), (unsigned char)(((c >> 5) & 63) * 255 / 63),
                                    (unsigned char)((c & 31) * 255 / 31)};
      fwrite(rgb, 1, 3, f);
    }
  fclose(f);
}

int main(int argc, char** argv) {
  const std::string out = argc > 1 ? argv[1] : ".";
  static uint16_t fbmem[UiFb::W * UiFb::H];
  static uint16_t line[UiFb::W * 4];
  UiFb fb;
  struct Scene { const char* name; dash::PcPhase ph; uint16_t i, n; uint8_t pct; uint16_t nw; int batt; bool chg; };
  const std::vector<Scene> scenes = {
    {"pc_1_esperando_app", dash::PcPhase::WAITING, 0, 0, 0, 0, 78, true},
    {"pc_2_comparando", dash::PcPhase::COMPARING, 0, 0, 0, 0, 78, true},
    {"pc_3_descargando", dash::PcPhase::DOWNLOADING, 2, 5, 42, 0, 79, true},
    {"pc_4_sincronizado", dash::PcPhase::SYNCED, 0, 0, 0, 5, 80, true},
    {"pc_5_ya_estaba_todo", dash::PcPhase::SYNCED, 0, 0, 0, 0, 100, false},
    {"pc_6_interrumpida", dash::PcPhase::ERROR, 0, 0, 0, 0, 81, true},
    {"pc_7_grabando", dash::PcPhase::RECORDING, 0, 0, 0, 0, 15, true},
  };
  for (const auto& sc : scenes) {
    HostPanel panel;
    fb.attach(fbmem, line, sizeof(line) / 2, true);
    dash::PcModel pc; pc.phase = sc.ph; pc.index = sc.i; pc.count = sc.n; pc.pct = sc.pct; pc.new_count = sc.nw;
    dash::BatteryModel b; b.pct = sc.batt; b.charging = sc.chg; b.vbus = true;
    dash::draw_pc(fb, pc, b);
    fb.flush(panel);
    CHECK(panel.odd == 0, "even-aligned pushes (CO5300)");
    // Nothing drawn outside the visible (rounded) area of the watch window.
    int outside = 0;
    for (int y = 0; y < UiFb::H; ++y)
      for (int x = 0; x < UiFb::W; ++x)
        if (fb.get(x, y) != dash::C_INK && !dash::inside_visible((float)x, (float)y, 0)) ++outside;
    CHECK(outside == 0, (std::string(sc.name) + ": pixels outside the visible area").c_str());
    save(panel, out + "/" + sc.name + ".ppm");
  }
  // The charging screen used with a plain charger is the untouched 3.7.2 one (reference image).
  {
    HostPanel panel;
    fb.attach(fbmem, line, sizeof(line) / 2, true);
    dash::BatteryModel b; b.pct = 78; b.charging = true; b.vbus = true;
    dash::draw_charging(fb, b);
    fb.flush(panel);
    save(panel, out + "/cargador_sin_pc_igual_que_antes.ppm");
  }
  printf("%s\n", failures ? "PC PREVIEW: FAILED" : "PC PREVIEW: OK");
  return failures ? 1 : 0;
}
