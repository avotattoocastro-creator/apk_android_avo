// AVO CHEST V3.7.2 — see ui_model.h. Rules: firmware/chest/V3_5_9/UI_7_FRANJAS_ESPECIFICACION.md
#include "ui_model.h"
#include <stdio.h>
#include <string.h>
#include <ctype.h>

namespace ui_model {
using namespace dash;

static void set(char* dst, size_t n, const char* src) { snprintf(dst, n, "%s", src ? src : ""); }

static void fmt_bytes(char* dst, size_t n, uint64_t b, const char* suffix) {
  if (b >= 1000ULL * 1000 * 1000) snprintf(dst, n, "%.1f GB%s", b / 1e9, suffix);
  else if (b >= 1000ULL * 1000) snprintf(dst, n, "%.0f MB%s", b / 1e6, suffix);
  else snprintf(dst, n, "%.0f KB%s", b / 1e3, suffix);
}

// "H 1.4 V 2.1 cm" / "H 1.8 V 2.6 m": one unit for both values so it fits the card.
static void fmt_accuracy(char* dst, size_t n, uint32_t h_mm, uint32_t v_mm) {
  const uint32_t mx = h_mm > v_mm ? h_mm : v_mm;
  auto num = [](char* o, size_t k, uint32_t mm, bool cm) {
    const double v = cm ? mm / 10.0 : mm / 1000.0;
    if (v < 10) snprintf(o, k, "%.1f", v); else snprintf(o, k, "%.0f", v);
  };
  const bool cm = mx < 1000;
  char h[12], v[12];
  num(h, sizeof h, h_mm, cm);
  if (v_mm) { num(v, sizeof v, v_mm, cm); snprintf(dst, n, "H %s V %s %s", h, v, cm ? "cm" : "m"); }
  else snprintf(dst, n, "H %s %s", h, cm ? "cm" : "m");
}

void build(const AppSnapshot& s, uint32_t now, Model* m) {
  *m = Model();
  auto fresh = [now](uint32_t t, uint32_t max_age) { return t != 0 && (uint32_t)(now - t) < max_age; };

  // 1. BLUETOOTH
  {
    CardModel& c = m->card[BLUETOOTH];
    const bool ok = s.ble.connected && s.ble.authorized;
    c.good = ok;
    c.color = ok ? GREEN : RED;
    set(c.state, sizeof c.state, ok ? "Conectado" : s.ble.claim_pending ? "PULSA BOOT" :
        s.ble.connected ? "Sin autorizar" : "Sin enlace");
    if (s.ble.connected) { c.right_icon = RI_PHONE; set(c.r1, sizeof c.r1, "AVO APP"); }
  }

  const bool back = s.link.connected && fresh(s.link.last_rx_ms, 2000);
  const bool sd_ok = s.storage.mounted && !s.storage.write_errors && s.storage.rec != RecStatus::REC_ERROR;

  // 2. CHALECO (this unit)
  {
    CardModel& c = m->card[CHALECO];
    c.good = back && sd_ok;
    c.color = c.good ? GREEN : RED;
    set(c.state, sizeof c.state, c.good ? "Sistema OK" : !back ? "Sin espalda" : "Revisar SD");
    snprintf(c.r1, sizeof c.r1, "V%s", AVO_FW_VERSION);
    for (char* p = c.r1; *p; ++p) *p = (char)toupper((unsigned char)*p);
    if (s.sys.cpu_temp_c > 1.0f && s.sys.cpu_temp_c < 125.0f)
      snprintf(c.r2, sizeof c.r2, "Temp %d°C", (int)(s.sys.cpu_temp_c + 0.5f));
  }

  // 3. ESPALDA
  {
    CardModel& c = m->card[ESPALDA];
    c.good = back;
    c.color = back ? GREEN : RED;
    set(c.state, sizeof c.state, back ? "Conectada" : s.link.now_pairing ? "Emparejando..." : "Sin enlace");
    if (back && s.link.transport == 1 && s.link.now_rssi < 0) {
      const int r = s.link.now_rssi;
      c.right_icon = RI_SIGNAL;
      c.bars = (int8_t)(r >= -55 ? 4 : r >= -65 ? 3 : r >= -75 ? 2 : 1);
      snprintf(c.r1, sizeof c.r1, "RSSI %d dBm", r);
    } else if (back && s.link.transport == 0) {
      set(c.r1, sizeof c.r1, "Cable UART");
    } else if (!back) {
      set(c.r1, sizeof c.r1, "SIN SEÑAL");
    }
  }

  // 4. CINCHA (IMU): three IMUs with recent batches; never inferred from the back link.
  {
    CardModel& c = m->card[CINCHA];
    int live = 0;
    if (s.girth.connected)
      for (int k = 0; k < 3; ++k) if (fresh(s.girth.last_batch_ms[k], 3000)) ++live;
    const bool ok = live == 3;
    c.good = ok;
    c.color = ok ? GREEN : RED;
    set(c.state, sizeof c.state, ok ? "Conectada" : live ? "Datos parciales" : s.girth.connected ? "Sin datos" : "Desconectada");
    c.right_icon = live ? RI_NODES : RI_NONE;
    if (live) {
      snprintf(c.r1, sizeof c.r1, "%d IMU", live);
      set(c.r2, sizeof c.r2, ok ? "Datos OK" : "Revisar");
    } else set(c.r1, sizeof c.r1, "SIN IMU");
  }

  // 5. GPS / RTK: red no GNSS, blue autonomous, green when NTRIP corrections are really applied.
  {
    CardModel& c = m->card[GPS];
    const bool gps = s.gnss.have && fresh(s.gnss.rx_ms, 3000) && s.gnss.s.gnss_fix_ok();
    const uint8_t carr = gps ? s.gnss.s.carr_soln() : 0;
    const bool corrected = gps && s.rtcm.flowing && (carr > 0 || s.gnss.s.diff_soln());
    c.good = gps;
    c.color = !gps ? RED : corrected ? GREEN : BLUE;
    set(c.state, sizeof c.state, !gps ? "Sin GPS" : carr == 2 ? "RTK FIX" : carr == 1 ? "RTK FLOAT" :
        s.gnss.s.diff_soln() ? "DGNSS" : s.gnss.s.fix_type == 2 ? "GNSS 2D" : "GNSS 3D");
    if (gps) {
      c.right_icon = RI_CROSSHAIRS;
      snprintf(c.r1, sizeof c.r1, "Sats: %u", (unsigned)s.gnss.s.num_sv);
      if (s.gnss.s.hacc_mm) fmt_accuracy(c.r2, sizeof c.r2, s.gnss.s.hacc_mm, s.gnss.s.vacc_mm);
    } else set(c.r1, sizeof c.r1, "SIN DATOS");
  }

  // 6. TARJETA SD: red absent/error, yellow recording, green available.
  {
    CardModel& c = m->card[SD];
    const bool rec = s.storage.rec == RecStatus::RECORDING || s.storage.rec == RecStatus::TEMP_BUFFER;
    c.good = sd_ok;
    c.color = !sd_ok ? RED : rec ? YELLOW : GREEN;
    if (!s.storage.mounted) { set(c.state, sizeof c.state, "Sin tarjeta"); set(c.r1, sizeof c.r1, "REVISAR"); }
    else if (!sd_ok) { set(c.state, sizeof c.state, "ERROR"); set(c.r1, sizeof c.r1, "REVISAR"); }
    else if (rec) {
      set(c.state, sizeof c.state, "Grabando...");
      c.right_icon = RI_REC_DOT;
      const uint32_t t = s.session.metrics.active_ms / 1000;
      snprintf(c.r1, sizeof c.r1, "%02lu:%02lu:%02lu", (unsigned long)(t / 3600), (unsigned long)(t / 60 % 60), (unsigned long)(t % 60));
      if (s.storage.session_bytes) fmt_bytes(c.r2, sizeof c.r2, s.storage.session_bytes, "");
    } else {
      set(c.state, sizeof c.state, "Disponible");
      set(c.r1, sizeof c.r1, "LISTA");
      if (s.storage.card_bytes) fmt_bytes(c.r2, sizeof c.r2, s.storage.free_bytes, " libres");
    }
  }

  // 7. BATERÍA: green >50, yellow 21–50, red <=20, unknown -> warning colour and '--%'.
  {
    CardModel& c = m->card[BATERIA];
    const int pct = s.power.pmu.online ? s.power.pmu.batt_pct : -1;
    m->batt.pct = (pct >= 0 && pct <= 100) ? pct : -1;
    m->batt.charging = s.power.pmu.online && s.power.pmu.charging;
    m->batt.vbus = s.power.pmu.online && s.power.pmu.vbus;
    c.color = m->batt.pct < 0 ? YELLOW : m->batt.pct > 50 ? GREEN : m->batt.pct > 20 ? YELLOW : RED;
    c.good = m->batt.pct > 20;
    set(c.state, sizeof c.state, m->batt.charging ? "Cargando..." :
        (m->batt.vbus && m->batt.pct == 100) ? "Carga completa" : m->batt.vbus ? "USB conectado" :
        m->batt.pct < 0 ? "Sin lectura" : "En uso");
  }
}

}  // namespace ui_model
