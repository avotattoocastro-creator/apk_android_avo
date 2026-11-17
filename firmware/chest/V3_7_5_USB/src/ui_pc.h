// AVO CHEST V3.7.5-usb1 — "CONECTADO AL PC" screen. Pure C++ (host preview + firmware).
// Shown instead of the charging screen ONLY while a USB host (PC) is on the cable. With a plain charger the
// charging screen of 3.7.2 is shown exactly as before.
#pragma once
#include <stdint.h>
#include "ui_fb.h"
#include "ui_dash.h"

namespace dash {

enum class PcPhase : uint8_t {
  WAITING = 0,      // PC on the cable, AVO Windows not talking yet
  COMPARING = 1,    // the app is reading the list / comparing with the PC
  DOWNLOADING = 2,  // index of count, pct of the current training
  SYNCED = 3,       // new_count trainings copied in this connection (0 = everything was already on the PC)
  RECORDING = 4,    // the watch is recording: nothing is sent
  ERROR = 5,        // the app reported a failure; it retries on the next connection
};

struct PcModel {
  PcPhase phase = PcPhase::WAITING;
  uint16_t index = 0, count = 0;
  uint8_t pct = 0;
  uint16_t new_count = 0;
};

void draw_pc(UiFb& fb, const PcModel& pc, const BatteryModel& b);
uint32_t pc_hash(const PcModel& pc, const BatteryModel& b);   // redraw only when something visible changes

}  // namespace dash
