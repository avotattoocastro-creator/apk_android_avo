// AVO CHEST V3.7.2 — dashboard drawing. See ui_dash.h.
#include "ui_dash.h"
#include <stdio.h>
#include <string.h>
#include "ui_assets.h"

namespace dash {
using namespace ui_assets;

static const char* const TITLES[CARD_COUNT] = {
  "BLUETOOTH", "CHALECO", "ESPALDA", "CINCHA (IMU)", "GPS / RTK", "TARJETA SD", "BATERÍA"};
const char* title(int i) { return (i >= 0 && i < CARD_COUNT) ? TITLES[i] : ""; }

static const UiFont* const TITLE_FONTS[] = {&F_TITLE, &F_STATE};
static const UiFont* const STATE_FONTS[] = {&F_STATE, &F_SMALL};
static const UiFont* const RIGHT_FONTS[] = {&F_SMALL, &F_TINY};

static constexpr int X0 = MARGIN_X;
static constexpr int CW = UiFb::W - 2 * MARGIN_X;   // 394
static constexpr int ICON_CX = X0 + 31;
static constexpr int DIV_X = X0 + 61;
static constexpr int TEXT_X = X0 + 71;
static constexpr int BADGE_CX = X0 + CW - 26;
static constexpr int RIGHT_ICON_CX = 246;
static constexpr int RIGHT_TEXT_X = 268;
static constexpr int RIGHT_TEXT_END = BADGE_CX - 22;

static uint16_t mix(uint16_t a, uint16_t b, uint8_t t) {  // t=0 -> a, 255 -> b
  const uint32_t r = (((a >> 11) & 31) * (255 - t) + ((b >> 11) & 31) * t) / 255;
  const uint32_t g = (((a >> 5) & 63) * (255 - t) + ((b >> 5) & 63) * t) / 255;
  const uint32_t bl = ((a & 31) * (255 - t) + (b & 31) * t) / 255;
  return (uint16_t)((r << 11) | (g << 5) | bl);
}

static uint32_t fnv(uint32_t h, const void* p, size_t n) {
  const uint8_t* b = (const uint8_t*)p;
  while (n--) h = (h ^ *b++) * 16777619UL;
  return h;
}

uint32_t card_hash(int i, const Model& m) {
  const CardModel& c = m.card[i];
  uint32_t h = 2166136261UL;
  h = fnv(h, &c.color, sizeof c.color);
  h = fnv(h, &c.good, sizeof c.good);
  h = fnv(h, c.state, strlen(c.state) + 1);
  h = fnv(h, c.r1, strlen(c.r1) + 1);
  h = fnv(h, c.r2, strlen(c.r2) + 1);
  h = fnv(h, &c.right_icon, 1);
  h = fnv(h, &c.bars, 1);
  if (i == BATERIA) h = fnv(h, &m.batt, sizeof m.batt);
  return h;
}

static void left_icon(UiFb& fb, int i, int cy, const Model& m) {
  switch (i) {
    case BLUETOOTH: fb.iconCentered(I_BLUETOOTH, ICON_CX, cy, INK); break;
    case CHALECO: fb.iconCentered(I_VEST, ICON_CX, cy, INK); break;
    case ESPALDA: fb.iconCentered(I_BROADCAST, ICON_CX, cy, INK); break;
    case CINCHA: fb.iconCentered(I_HORSE, ICON_CX, cy, INK); break;
    case GPS: fb.iconCentered(I_SATELLITE, ICON_CX, cy, INK); break;
    case SD: fb.iconCentered(I_SDCARD, ICON_CX, cy, INK); break;
    case BATERIA: {
      // Battery outline with real fill level (no level drawn when unknown).
      const int bw = 44, bh = 26, bx = ICON_CX - bw / 2 - 2, by = cy - bh / 2;
      const uint16_t bg = m.card[BATERIA].color;
      fb.fillRoundRect(bx, by, bw, bh, 5, INK);
      fb.fillRoundRect(bx + 3, by + 3, bw - 6, bh - 6, 3, bg);
      fb.fillRoundRect(bx + bw, cy - 6, 5, 12, 2, INK);
      const int pct = m.batt.pct;
      if (pct >= 0) {
        const int segs = pct >= 75 ? 3 : pct >= 40 ? 2 : pct > 10 ? 1 : 0;
        for (int s = 0; s < segs; ++s) fb.fillRect(bx + 6 + s * 11, by + 6, 9, bh - 12, INK);
      }
      break;
    }
  }
}

static void right_icon(UiFb& fb, const CardModel& c, int cy) {
  switch (c.right_icon) {
    case RI_PHONE: fb.iconCentered(I_PHONE, RIGHT_ICON_CX, cy, INK); break;
    case RI_NODES: fb.iconCentered(I_NODES, RIGHT_ICON_CX, cy, INK); break;
    case RI_CROSSHAIRS: fb.iconCentered(I_CROSSHAIRS, RIGHT_ICON_CX, cy, INK); break;
    case RI_REC_DOT: fb.fillCircle(RIGHT_ICON_CX, cy, 12.5f, INK); fb.fillCircle(RIGHT_ICON_CX, cy, 10.5f, RED); break;  // blink: draw_rec_dot
    case RI_SIGNAL: {
      const uint16_t dim = mix(c.color, INK, 70);
      for (int k = 0; k < 4; ++k) {
        const int h = 8 + k * 6;
        fb.fillRoundRect(RIGHT_ICON_CX - 13 + k * 7, cy + 13 - h, 5, h, 1, k < c.bars ? INK : dim);
      }
      break;
    }
    default: break;
  }
}

void draw_card(UiFb& fb, int i, const Model& m) {
  const CardModel& c = m.card[i];
  const int top = card_top(i);
  const int cy = top + CARD_H / 2;
  // Clear the slot first so anti-aliased corners never blend with an old colour.
  fb.fillRect(X0 - 2, top - 2, CW + 4, CARD_H + 4, INK);
  fb.fillRoundRect(X0, top, CW, CARD_H, RADIUS, c.color);
  left_icon(fb, i, cy, m);
  fb.fillRect(DIV_X, top + 12, 2, CARD_H - 24, INK);

  const bool battery = i == BATERIA;
  const bool has_right_icon = c.right_icon != RI_NONE || (battery && m.batt.charging);
  const int title_max = (battery ? 300 : (has_right_icon ? RIGHT_ICON_CX - 20 : RIGHT_TEXT_X - 8)) - TEXT_X;
  fb.text(UiFb::fit(TITLE_FONTS, 2, TITLES[i], title_max), TEXT_X, top + 29, TITLES[i], INK);
  const int state_max = (battery ? 250 : RIGHT_TEXT_X - 6) - TEXT_X;
  fb.text(UiFb::fit(STATE_FONTS, 2, c.state, state_max), TEXT_X, top + 55, c.state, INK);

  if (battery) {
    char pct[8];
    if (m.batt.pct >= 0 && m.batt.pct <= 100) snprintf(pct, sizeof pct, "%d%%", m.batt.pct);
    else snprintf(pct, sizeof pct, "--%%");
    const int right = X0 + CW - 16;
    const int w = fb.textRight(F_BIG, right, top + 53, pct, INK);
    if (m.batt.charging) fb.iconCentered(I_BOLT, right - w - 24, cy, INK);
    return;
  }

  right_icon(fb, c, cy);
  const int rw = RIGHT_TEXT_END - RIGHT_TEXT_X;
  if (c.r2[0]) {
    fb.text(UiFb::fit(RIGHT_FONTS, 2, c.r1, rw), RIGHT_TEXT_X, top + 28, c.r1, INK);
    fb.text(UiFb::fit(RIGHT_FONTS, 2, c.r2, rw), RIGHT_TEXT_X, top + 52, c.r2, INK);
  } else if (c.r1[0]) {
    fb.text(UiFb::fit(RIGHT_FONTS, 2, c.r1, rw), RIGHT_TEXT_X, top + 40, c.r1, INK);
  }
  fb.fillCircle(BADGE_CX, cy, 16.5f, INK);
  fb.iconCentered(c.good ? I_CHECK : I_XMARK, BADGE_CX, cy, c.color);
}

bool rec_dot_active(const Model& m) { return m.card[SD].right_icon == RI_REC_DOT; }

void draw_rec_dot(UiFb& fb, const Model& m, bool on) {
  if (!rec_dot_active(m)) return;
  const int cy = card_top(SD) + CARD_H / 2;
  // 28x28 square, even-aligned, entirely inside the card: only these pixels are re-sent.
  fb.fillRect(RIGHT_ICON_CX - 14, cy - 14, 28, 28, m.card[SD].color);
  if (on) { fb.fillCircle(RIGHT_ICON_CX, cy, 12.5f, INK); fb.fillCircle(RIGHT_ICON_CX, cy, 10.5f, RED); }
}

bool card_text_fits(int i, const Model& m) {
  const CardModel& c = m.card[i];
  const bool battery = i == BATERIA;
  const bool has_right_icon = c.right_icon != RI_NONE || (battery && m.batt.charging);
  const int title_max = (battery ? 300 : (has_right_icon ? RIGHT_ICON_CX - 20 : RIGHT_TEXT_X - 8)) - TEXT_X;
  if (UiFb::textWidth(F_STATE, TITLES[i]) > title_max) return false;
  if (UiFb::textWidth(F_SMALL, c.state) > (battery ? 250 : RIGHT_TEXT_X - 6) - TEXT_X) return false;
  if (battery) return true;
  const int rw = RIGHT_TEXT_END - RIGHT_TEXT_X;
  return UiFb::textWidth(F_TINY, c.r1) <= rw && UiFb::textWidth(F_TINY, c.r2) <= rw;
}

void draw_dashboard(UiFb& fb, const Model& m) {
  fb.clear(INK);
  for (int i = 0; i < CARD_COUNT; ++i) draw_card(fb, i, m);
}

void draw_ota_progress(UiFb& fb, uint32_t pct, const char* percent_text) {
  if (pct > 99) pct = 99;
  fb.clear(INK);
  fb.textCenter(F_TITLE, UiFb::W / 2, 160, "ACTUALIZANDO...", WHITE);
  const int x = 30, y = 210, w = UiFb::W - 60, h = 28;
  fb.fillRoundRect(x, y, w, h, 14, rgb565(50, 50, 50));
  const int fw = (int)(w * pct / 100);
  if (fw >= 28) fb.fillRoundRect(x, y, fw, h, 14, GREEN);
  fb.textCenter(F_HUGE, UiFb::W / 2, 340, percent_text, WHITE);
  fb.textCenter(F_STATE, UiFb::W / 2, 410, "No apagues el reloj", rgb565(170, 170, 170));
}

void draw_ota_notice(UiFb& fb, bool ok, const char* line1, const char* line2) {
  fb.clear(INK);
  fb.textCenter(F_TITLE, UiFb::W / 2, 230, line1, ok ? GREEN : RED);
  fb.textCenter(F_STATE, UiFb::W / 2, 280, line2, WHITE);
}

static constexpr uint16_t TEAL = rgb565(32, 211, 154);
static constexpr uint16_t SOFT = rgb565(175, 180, 190);
static constexpr uint16_t TRACK = rgb565(40, 44, 52);

void draw_shutdown(UiFb& fb, uint8_t phase) {
  static const char* const STEPS[4] = {"Deteniendo sesión", "Cerrando archivos SD", "Guardando caja negra", "Apagando"};
  if (phase < 1) phase = 1;
  if (phase > 4) phase = 4;
  fb.clear(INK);
  fb.iconCentered(I_POWER, UiFb::W / 2, 140, SOFT);
  fb.textCenter(F_HEAD, UiFb::W / 2, 238, "APAGANDO...", WHITE);
  fb.textCenter(F_STATE, UiFb::W / 2, 284, "Guardando entrenamiento", SOFT);
  // Four segments = four real steps; a segment fills when its step is reached.
  const int x = 34, y = 318, w = UiFb::W - 68, h = 14, gap = 8;
  const int sw = (w - 3 * gap) / 4;
  for (int i = 0; i < 4; ++i)
    fb.fillRoundRect(x + i * (sw + gap), y, sw, h, 7, i < phase ? TEAL : TRACK);
  char step[48];
  snprintf(step, sizeof step, "%u/4  %s", (unsigned)phase, STEPS[phase - 1]);
  fb.textCenter(F_SMALL, UiFb::W / 2, 370, step, SOFT);
}

void draw_shutdown_failed(UiFb& fb) {
  fb.clear(INK);
  fb.iconCentered(I_WARN, UiFb::W / 2, 140, YELLOW);
  fb.textCenter(F_HEAD, UiFb::W / 2, 238, "NO SE PUDO GUARDAR", YELLOW);
  fb.textCenter(F_STATE, UiFb::W / 2, 284, "El reloj sigue encendido", WHITE);
  fb.textCenter(F_SMALL, UiFb::W / 2, 330, "Revisa la tarjeta SD y vuelve a apagar", SOFT);
}

void charge_label(const BatteryModel& b, const char** white, const char** green) {
  if (b.charging) { *white = "CARGANDO "; *green = "USB"; }
  else if (b.vbus && b.pct == 100) { *white = "CARGA "; *green = "COMPLETA"; }
  else { *white = "USB "; *green = "CONECTADO"; }
}

void draw_charging(UiFb& fb, const BatteryModel& b) {
  fb.clear(INK);
  const float cx = UiFb::W / 2.0f, cy = UiFb::H / 2.0f;
  const float ro = 188, ri = 166;
  fb.ring(cx, cy, ro, ri, 0, 360, TRACK);
  const bool known = b.pct >= 0 && b.pct <= 100;
  if (known && b.pct > 0) {
    const float end = b.pct * 3.6f;
    fb.arc(cx, cy, ro + 7, ri - 7, 0, end, GREEN, 40);   // soft glow
    fb.arc(cx, cy, ro, ri, 0, end, GREEN);
  }
  // Battery icon: white outline, green fill proportional to the real level, bolt when charging.
  const int bw = 118, bh = 58, bx = (int)cx - bw / 2 - 6, by = 118;
  fb.fillRoundRect(bx, by, bw, bh, 12, WHITE);
  fb.fillRoundRect(bx + 6, by + 6, bw - 12, bh - 12, 7, INK);
  fb.fillRoundRect(bx + bw + 2, by + 17, 10, bh - 34, 4, WHITE);
  if (known) {
    const int fw = (bw - 20) * (b.pct < 8 ? 8 : b.pct) / 100;
    fb.fillRoundRect(bx + 10, by + 10, fw, bh - 20, 5, b.pct <= 20 ? RED : GREEN);
  }
  if (b.charging) fb.iconCentered(I_BOLT_S, bx + bw / 2, by + bh / 2, WHITE);
  char value[8];
  if (known) snprintf(value, sizeof value, "%d%%", b.pct); else snprintf(value, sizeof value, "--%%");
  fb.textCenter(F_GIANT, (int)cx, 310, value, WHITE);
  const char *w, *g;
  charge_label(b, &w, &g);
  const int tw = UiFb::textWidth(F_TITLE, w) + UiFb::textWidth(F_TITLE, g);
  const int x = (int)cx - tw / 2;
  const int adv = fb.text(F_TITLE, x, 362, w, WHITE);
  fb.text(F_TITLE, x + adv, 362, g, b.charging || b.pct == 100 ? GREEN : SOFT);
}

}  // namespace dash
