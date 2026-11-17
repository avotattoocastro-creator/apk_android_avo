#pragma once   // included ONLY by ui_dash.cpp (needs its fonts, icons and colours)
// AVO CHEST V3.7.5-usb1 — "CONECTADO AL PC" screen. Appended to ui_dash.cpp by apply_v375_usb.py so it uses the
// same fonts, icons and colours (ui_assets.h is included only once). Values come only from the real USB state.
#include "ui_pc.h"

namespace dash {

static void pc_monitor(UiFb& fb, int cx, int top, uint16_t frame, uint16_t mark) {
  const int w = 150, h = 96;
  const int x = cx - w / 2;
  fb.fillRoundRect(x, top, w, h, 12, frame);                 // screen frame
  fb.fillRoundRect(x + 8, top + 8, w - 16, h - 22, 6, C_INK); // screen
  fb.fillRect(cx - 9, top + h, 18, 16, frame);                // neck
  fb.fillRoundRect(cx - 42, top + h + 14, 84, 10, 5, frame);  // foot
  (void)mark;
}

uint32_t pc_hash(const PcModel& pc, const BatteryModel& b) {
  uint32_t h = 2166136261u;
  const uint32_t v[7] = {(uint32_t)pc.phase, pc.index, pc.count, pc.pct, pc.new_count, (uint32_t)(b.pct + 1),
                         (uint32_t)(b.charging | (b.vbus << 1))};
  for (uint32_t x : v) h = (h ^ x) * 16777619u;
  return h;
}

void draw_pc(UiFb& fb, const PcModel& pc, const BatteryModel& b) {
  fb.clear(C_INK);
  const int cx = UiFb::W / 2;
  uint16_t accent = SOFT;
  switch (pc.phase) {
    case PcPhase::COMPARING: case PcPhase::DOWNLOADING: accent = C_BLUE; break;
    case PcPhase::SYNCED: accent = C_GREEN; break;
    case PcPhase::RECORDING: accent = C_YELLOW; break;
    case PcPhase::ERROR: accent = C_RED; break;
    default: break;
  }
  pc_monitor(fb, cx, 70, C_WHITE, accent);
  // Inside the monitor: what is happening, with an icon.
  if (pc.phase == PcPhase::SYNCED) fb.iconCentered(I_CHECK, cx, 70 + 8 + 37, C_GREEN);
  else if (pc.phase == PcPhase::ERROR || pc.phase == PcPhase::RECORDING) fb.iconCentered(I_WARN, cx, 70 + 8 + 37, accent);
  else fb.iconCentered(I_HORSE, cx, 70 + 8 + 37, accent);

  fb.textCenter(F_HEAD, cx, 262, "CONECTADO AL PC", C_WHITE);

  char line[48];
  switch (pc.phase) {
    case PcPhase::WAITING:
      fb.textCenter(F_STATE, cx, 310, "Abre AVO Windows", SOFT);
      fb.textCenter(F_SMALL, cx, 344, "para descargar los entrenamientos", SOFT);
      break;
    case PcPhase::COMPARING:
      fb.textCenter(F_STATE, cx, 310, "Comparando entrenamientos", C_BLUE);
      break;
    case PcPhase::DOWNLOADING: {
      if (pc.count) snprintf(line, sizeof line, "Descargando %u de %u", (unsigned)pc.index, (unsigned)pc.count);
      else snprintf(line, sizeof line, "Descargando");
      fb.textCenter(F_STATE, cx, 310, line, C_BLUE);
      const int x = 44, y = 330, w = UiFb::W - 88, h = 16;
      const unsigned p = pc.pct > 100 ? 100 : pc.pct;
      fb.fillRoundRect(x, y, w, h, 8, TRACK);
      const int fw = w * (int)p / 100;
      if (fw >= h) fb.fillRoundRect(x, y, fw, h, 8, C_BLUE);
      snprintf(line, sizeof line, "%u%%", p);
      fb.textCenter(F_SMALL, cx, 376, line, C_WHITE);
      break;
    }
    case PcPhase::SYNCED:
      if (pc.new_count == 1) snprintf(line, sizeof line, "1 entrenamiento nuevo en el PC");
      else if (pc.new_count) snprintf(line, sizeof line, "%u entrenamientos nuevos en el PC", (unsigned)pc.new_count);
      else snprintf(line, sizeof line, "Todo está ya en el PC");
      fb.textCenter(F_STATE, cx, 310, "Sincronizado", C_GREEN);
      fb.textCenter(F_SMALL, cx, 344, line, C_WHITE);
      break;
    case PcPhase::RECORDING:
      fb.textCenter(F_STATE, cx, 310, "Grabando: se descarga al terminar", C_YELLOW);
      break;
    case PcPhase::ERROR:
      fb.textCenter(F_STATE, cx, 310, "Descarga interrumpida", C_RED);
      fb.textCenter(F_SMALL, cx, 344, "Se reanuda al volver a conectar", SOFT);
      break;
  }

  // Battery at the bottom (the PC also charges the watch). Real PMIC value only.
  const bool known = b.pct >= 0 && b.pct <= 100;
  if (known) snprintf(line, sizeof line, "%d%%", b.pct); else snprintf(line, sizeof line, "--%%");
  const char* label = b.charging ? "  CARGANDO" : (b.vbus && b.pct == 100) ? "  CARGA COMPLETA" : "";
  const int tw = (b.charging ? I_BOLT_S.w + 8 : 0) + UiFb::textWidth(F_STATE, line) + UiFb::textWidth(F_SMALL, label);
  int x = cx - tw / 2;
  const int y = 440;
  if (b.charging) { fb.icon(I_BOLT_S, x, y - 27, C_GREEN); x += I_BOLT_S.w + 8; }
  x += fb.text(F_STATE, x, y, line, known && b.pct <= 20 ? C_RED : C_GREEN);
  fb.text(F_SMALL, x, y, label, SOFT);
}

}  // namespace dash
