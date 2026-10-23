// AVO CHEST V3.7.2 — seven-card dashboard and special screens drawn on UiFb.
// Pure C++ (host preview + firmware). Values come ONLY from the live snapshot (ui_model.cpp).
#pragma once
#include <stdint.h>
#include "ui_fb.h"

namespace dash {

// Card colours (RGB565), chosen close to the approved reference.
constexpr uint16_t C_GREEN  = rgb565(104, 232, 92);
constexpr uint16_t C_BLUE   = rgb565(34, 190, 245);
constexpr uint16_t C_YELLOW = rgb565(255, 236, 40);
constexpr uint16_t C_RED    = rgb565(244, 64, 64);
constexpr uint16_t C_GREY   = rgb565(120, 120, 120);
constexpr uint16_t C_INK    = 0x0000;
constexpr uint16_t C_WHITE  = 0xFFFF;

enum Card : uint8_t { BLUETOOTH = 0, CHALECO, ESPALDA, CINCHA, GPS, SD, BATERIA, CARD_COUNT };
enum RightIcon : uint8_t { RI_NONE = 0, RI_PHONE, RI_SIGNAL, RI_NODES, RI_CROSSHAIRS, RI_REC_DOT };

struct CardModel {
  uint16_t color = C_RED;
  bool good = false;
  char state[28] = {0};   // second line, left
  char r1[28] = {0};      // right column, line 1
  char r2[28] = {0};      // right column, line 2
  uint8_t right_icon = RI_NONE;
  int8_t bars = -1;       // RI_SIGNAL: 0..4
};

struct BatteryModel {
  int pct = -1;           // -1 unknown
  bool charging = false;  // PMIC charger actually charging
  bool vbus = false;
};

struct Model {
  CardModel card[CARD_COUNT];
  BatteryModel batt;
};

// Layout (logical, portrait as seen by the rider).
constexpr int MARGIN_X = 8;
constexpr int TOP = 9;
constexpr int CARD_H = 64;
constexpr int CARD_GAP = 6;
constexpr int RADIUS = 20;
inline int card_top(int i) { return TOP + i * (CARD_H + CARD_GAP); }

const char* title(int i);
// True if every text of card i fits its slot (smallest font included); used by host checks.
bool card_text_fits(int i, const Model& m);
uint32_t card_hash(int i, const Model& m);
void draw_card(UiFb& fb, int i, const Model& m);
void draw_dashboard(UiFb& fb, const Model& m);  // all cards + background
// SD recording: only the red dot blinks (the yellow card is not redrawn). No-op if not recording.
bool rec_dot_active(const Model& m);
void draw_rec_dot(UiFb& fb, const Model& m, bool on);

void draw_ota_progress(UiFb& fb, uint32_t pct, const char* percent_text);
void draw_ota_notice(UiFb& fb, bool ok, const char* line1, const char* line2);
// Controlled shutdown with REAL phases (AppSnapshot::power.shutdown_phase):
// 1 stopping session, 2 closing SD files, 3 saving black box, 4 power off.
void draw_shutdown(UiFb& fb, uint8_t phase);
// SD files could not be closed: firmware cancelled the power-off.
void draw_shutdown_failed(UiFb& fb);
// USB charging screen: ring + battery + percentage from the PMIC (no guessed values).
void draw_charging(UiFb& fb, const BatteryModel& b);
// "CARGANDO USB" / "CARGA COMPLETA" / "USB CONECTADO"; second part is drawn in green.
void charge_label(const BatteryModel& b, const char** white, const char** green);

}  // namespace dash
