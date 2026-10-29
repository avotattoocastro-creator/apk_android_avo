#include "avo_config.h"
#include "avo_bytes.h"
#include "avo_crc.h"
#include <string.h>

namespace avo {

enum : uint16_t {
  T_IDENTITY = 1, T_GEOPARAM = 2, T_FENCE = 3, T_DISPLAY = 4, T_RECORDING = 5, T_BLE = 6,
  T_TRAINING = 7, T_LINE = 8, T_UART = 9, T_POWER = 10,
};

void config_defaults(Config* c) { *c = Config(); }

template <typename T>
static int clampv(T* v, T lo, T hi) {
  if (*v < lo) { *v = lo; return 1; }
  if (*v > hi) { *v = hi; return 1; }
  return 0;
}

int config_validate(Config* c) {
  int k = 0;
  c->device_name[sizeof(c->device_name) - 1] = 0;
  c->horse_name[sizeof(c->horse_name) - 1] = 0;
  c->rider_name[sizeof(c->rider_name) - 1] = 0;
  k += clampv<uint8_t>(&c->auto_enabled, 0, 1);
  k += clampv<uint16_t>(&c->entry_confirm_s, 0, 60);
  k += clampv<uint16_t>(&c->exit_confirm_s, 0, 120);
  k += clampv<uint32_t>(&c->entry_margin_cm, 0, 10000);
  k += clampv<uint32_t>(&c->exit_margin_cm, 0, 10000);
  k += clampv<uint32_t>(&c->hacc_max_cm, 50, 5000);
  k += clampv<uint16_t>(&c->uncertainty_k_x100, 0, 300);
  if ((uint8_t)c->exit_action > 2) { c->exit_action = ExitAction::STOP_AND_SAVE; k++; }
  k += clampv<uint8_t>(&c->pre_s, 0, 60);
  k += clampv<uint8_t>(&c->post_s, 0, 60);
  k += clampv<uint16_t>(&c->rearm_timeout_s, 0, 3600);
  k += clampv<uint16_t>(&c->gnss_loss_ms, 500, 30000);
  k += clampv<uint16_t>(&c->resume_window_s, 0, 3600);
  k += clampv<uint8_t>(&c->fence_count, 0, AVO_MAX_FENCES);
  for (uint8_t i = 0; i < AVO_MAX_FENCES; i++) {
    c->fences[i].name[sizeof(c->fences[i].name) - 1] = 0;
    if (c->fences[i].n > AVO_MAX_VERTICES) { c->fences[i].n = 0; c->fences[i].type = FenceType::NONE; k++; }
    if ((uint8_t)c->fences[i].type > 2) { c->fences[i].type = FenceType::NONE; k++; }
  }
  k += clampv<uint8_t>(&c->brightness, 10, 255);
  k += clampv<uint16_t>(&c->screen_timeout_s, 0, 3600);
  k += clampv<uint16_t>(&c->flush_ms, 200, 5000);
  k += clampv<uint16_t>(&c->fsync_ms, 500, 10000);
  k += clampv<uint16_t>(&c->segment_mb, 16, 2048);
  k += clampv<uint32_t>(&c->nominal_rate_bps, 1000, 200000);
  k += clampv<uint16_t>(&c->series_speed_cms, 50, 2000);
  k += clampv<uint16_t>(&c->series_min_s, 1, 600);
  if (c->uart_baud != 115200 && c->uart_baud != 230400 && c->uart_baud != 460800 && c->uart_baud != 921600) {
    c->uart_baud = 921600; k++;
  }
  k += clampv<uint8_t>(&c->low_batt_pct, 5, 50);
  k += clampv<uint8_t>(&c->critical_batt_pct, 1, 20);
  if (c->critical_batt_pct >= c->low_batt_pct) { c->critical_batt_pct = (uint8_t)(c->low_batt_pct / 2); k++; }
  k += clampv<uint16_t>(&c->critical_batt_mv, 3200, 3800);
  return k;
}

static void w_fence_body(ByteWriter& w, const FenceDef& f) {
  w.u8(f.id); w.u8((uint8_t)f.type); w.str(f.name, 16); w.i32(f.center_lat_e7); w.i32(f.center_lon_e7);
  w.u32(f.radius_cm); w.u8(f.n);
  for (uint8_t i = 0; i < f.n && i < AVO_MAX_VERTICES; i++) { w.i32(f.lat_e7[i]); w.i32(f.lon_e7[i]); }
}

static bool r_fence_body(ByteReader& r, FenceDef* f) {
  *f = FenceDef();
  f->id = r.u8(); f->type = (FenceType)r.u8(); r.str(f->name, 16); f->center_lat_e7 = r.i32();
  f->center_lon_e7 = r.i32(); f->radius_cm = r.u32(); f->n = r.u8();
  if (f->n > AVO_MAX_VERTICES) return false;
  for (uint8_t i = 0; i < f->n; i++) { f->lat_e7[i] = r.i32(); f->lon_e7[i] = r.i32(); }
  return r.ok();
}

size_t fence_serialize(const FenceDef& f, uint8_t* out, size_t cap) {
  ByteWriter w(out, cap);
  w_fence_body(w, f);
  return w.ok() ? w.size() : 0;
}

bool fence_deserialize(const uint8_t* p, size_t n, FenceDef* f) {
  ByteReader r(p, n);
  return r_fence_body(r, f);
}

// Section helper: writes tag+len placeholder, body, then patches len.
class Section {
 public:
  Section(ByteWriter& w, uint16_t tag) : w_(w) { w_.u16(tag); at_ = w_.size(); w_.u16(0); }
  ~Section() { if (w_.ok()) put_u16(w_.data() + at_, (uint16_t)(w_.size() - at_ - 2)); }
 private:
  ByteWriter& w_;
  size_t at_;
};

size_t config_max_size() {
  return 16 + 8 * (4 + 31 + AVO_MAX_VERTICES * 8) + 512;
}

size_t config_serialize(const Config& c, uint8_t* out, size_t cap) {
  ByteWriter w(out, cap);
  w.bytes("AVOC", 4); w.u16(AVO_CONFIG_SCHEMA); w.u16(0);
  size_t len_at = w.size();
  w.u32(0);
  {
    Section s(w, T_IDENTITY);
    w.str(c.device_name, 20); w.u32(c.horse_id); w.str(c.horse_name, 24); w.u32(c.rider_id); w.str(c.rider_name, 24);
  }
  {
    Section s(w, T_GEOPARAM);
    w.u8(c.auto_enabled); w.u8(c.active_mask); w.u16(c.entry_confirm_s); w.u16(c.exit_confirm_s);
    w.u32(c.entry_margin_cm); w.u32(c.exit_margin_cm); w.u32(c.hacc_max_cm); w.u16(c.uncertainty_k_x100);
    w.u8((uint8_t)c.exit_action); w.u8(c.pre_s); w.u8(c.post_s); w.u16(c.rearm_timeout_s); w.u16(c.gnss_loss_ms);
    w.u16(c.resume_window_s); w.u8(c.fence_count);
  }
  for (uint8_t i = 0; i < c.fence_count && i < AVO_MAX_FENCES; i++) {
    Section s(w, T_FENCE);
    w.u8(i);
    w_fence_body(w, c.fences[i]);
  }
  {
    Section s(w, T_DISPLAY);
    w.u8(c.brightness); w.u16(c.screen_timeout_s); w.u8(c.dim_on_low_batt);
  }
  {
    Section s(w, T_RECORDING);
    w.u16(c.flush_ms); w.u16(c.fsync_ms); w.u16(c.segment_mb); w.u32(c.nominal_rate_bps);
  }
  { Section s(w, T_BLE); w.u8(c.ble_require_bond); }
  { Section s(w, T_TRAINING); w.u16(c.series_speed_cms); w.u16(c.series_min_s); }
  for (uint8_t i = 0; i < 4; i++) {
    Section s(w, T_LINE);
    const VirtualLine& l = c.lines[i];
    w.u8(i); w.u8(l.enabled); w.i32(l.a_lat_e7); w.i32(l.a_lon_e7); w.i32(l.b_lat_e7); w.i32(l.b_lon_e7);
  }
  { Section s(w, T_UART); w.u32(c.uart_baud); }
  { Section s(w, T_POWER); w.u8(c.low_batt_pct); w.u8(c.critical_batt_pct); w.u16(c.critical_batt_mv); }
  if (!w.ok()) return 0;
  put_u32(out + len_at, (uint32_t)(w.size() - len_at - 4));
  uint32_t crc = crc32(out, w.size());
  w.u32(crc);
  return w.ok() ? w.size() : 0;
}

ConfigLoad config_deserialize(const uint8_t* p, size_t n, Config* c) {
  config_defaults(c);
  if (n < 16) return ConfigLoad::TOO_SHORT;
  if (memcmp(p, "AVOC", 4) != 0) return ConfigLoad::BAD_MAGIC;
  uint16_t schema = get_u16(p + 4);
  uint32_t body = get_u32(p + 8);
  if ((size_t)body + 16 != n) return ConfigLoad::BAD_LENGTH;
  if (crc32(p, n - 4) != get_u32(p + n - 4)) return ConfigLoad::BAD_CRC;
  ByteReader r(p + 12, body);
  while (r.remaining() >= 4) {
    uint16_t tag = r.u16();
    uint16_t len = r.u16();
    if (len > r.remaining()) break;
    ByteReader s(r.cur(), len);
    r.skip(len);
    switch (tag) {
      case T_IDENTITY:
        if (s.remaining() >= 76) {
          s.str(c->device_name, 20); c->horse_id = s.u32(); s.str(c->horse_name, 24); c->rider_id = s.u32();
          s.str(c->rider_name, 24);
        }
        break;
      case T_GEOPARAM:
        if (s.remaining() >= 30) {
          c->auto_enabled = s.u8(); c->active_mask = s.u8(); c->entry_confirm_s = s.u16(); c->exit_confirm_s = s.u16();
          c->entry_margin_cm = s.u32(); c->exit_margin_cm = s.u32(); c->hacc_max_cm = s.u32();
          c->uncertainty_k_x100 = s.u16(); c->exit_action = (ExitAction)s.u8(); c->pre_s = s.u8(); c->post_s = s.u8();
          c->rearm_timeout_s = s.u16(); c->gnss_loss_ms = s.u16(); c->resume_window_s = s.u16(); c->fence_count = s.u8();
        }
        break;
      case T_FENCE: {
        uint8_t idx = s.u8();
        FenceDef f;
        if (idx < AVO_MAX_FENCES && r_fence_body(s, &f)) c->fences[idx] = f;
        break;
      }
      case T_DISPLAY:
        if (s.remaining() >= 4) { c->brightness = s.u8(); c->screen_timeout_s = s.u16(); c->dim_on_low_batt = s.u8(); }
        break;
      case T_RECORDING:
        if (s.remaining() >= 10) { c->flush_ms = s.u16(); c->fsync_ms = s.u16(); c->segment_mb = s.u16(); c->nominal_rate_bps = s.u32(); }
        break;
      case T_BLE:
        if (s.remaining() >= 1) c->ble_require_bond = s.u8();
        break;
      case T_TRAINING:
        if (s.remaining() >= 4) { c->series_speed_cms = s.u16(); c->series_min_s = s.u16(); }
        break;
      case T_LINE: {
        uint8_t i = s.u8();
        if (i < 4 && s.remaining() >= 17) {
          VirtualLine& l = c->lines[i];
          l.enabled = s.u8(); l.a_lat_e7 = s.i32(); l.a_lon_e7 = s.i32(); l.b_lat_e7 = s.i32(); l.b_lon_e7 = s.i32();
        }
        break;
      }
      case T_UART:
        if (s.remaining() >= 4) c->uart_baud = s.u32();
        break;
      case T_POWER:
        if (s.remaining() >= 4) { c->low_batt_pct = s.u8(); c->critical_batt_pct = s.u8(); c->critical_batt_mv = s.u16(); }
        break;
      default:
        break;  // unknown section from a newer schema: ignored
    }
  }
  config_validate(c);
  ConfigLoad res = ConfigLoad::OK;
  if (schema > AVO_CONFIG_SCHEMA) res = ConfigLoad::NEWER_SCHEMA_OK;
  else if (schema < AVO_CONFIG_SCHEMA) res = ConfigLoad::MIGRATED;  // older: defaults filled the gaps
  c->schema = AVO_CONFIG_SCHEMA;
  return res;
}

}  // namespace avo
