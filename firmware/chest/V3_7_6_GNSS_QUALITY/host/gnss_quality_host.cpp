// AVO CHEST V3.7.6 GNSS QUALITY — host checks of the real encoders/decoders (no hardware).
// Built in CI against the PATCHED tree:
//   g++ -std=c++17 -I lib/avo_core/src host/gnss_quality_host.cpp lib/avo_core/src/avo_payloads.cpp
//       lib/avo_core/src/avo_ble_proto.cpp ... -o gq && ./gq
//  1. BackStatus v3 written by the back encoder (same avo_payloads.cpp as BACK 3.13.11) decodes on the chest.
//  2. A v2 BackStatus (82 bytes, BACK < 3.9.0) decodes with v3 = false (→ q_flags = 0, no fake quality).
//  3. A truncated v3 tail is rejected as v3 (v2 fields kept).
//  4. TELEMETRY v3 is 116 bytes and is byte-identical to the vector Android decodes in
//     core/src/test/kotlin/.../FirmwareVectorsTest.kt (telemetryV3DecodesFirmwareEncoding).
//  5. The v2 prefix (83 bytes) is unchanged, so apps that only know v2 keep working.
#include <cstdio>
#include <cstring>
#include <string>
#include "avo_payloads.h"
#include "avo_ble_proto.h"

using namespace avo;

static int fails = 0;
static void check(bool c, const char* m) {
  std::printf("%s %s\n", c ? "  ok  " : "  FAIL", m);
  if (!c) fails++;
}

static std::string hex(const uint8_t* b, size_t n) {
  static const char* d = "0123456789abcdef";
  std::string s;
  for (size_t i = 0; i < n; i++) { s += d[b[i] >> 4]; s += d[b[i] & 15]; }
  return s;
}

int main() {
  // ---- 1. back v3 → chest
  BackStatus st;
  st.v2 = true; st.v3 = true;
  st.sv_tracked = 31; st.sv_used = 27; st.sig_tracked = 58; st.sig_used = 50; st.sig_cr_used = 44; st.sig_corr = 48;
  st.sig_l2 = 26; st.sig_l2_used = 22; st.sig_weak = 5; st.cno_mean = 41; st.cno_min = 28; st.cno_max = 49;
  st.quality_age_s = 1; st.quality_mon = 1; st.fix_lost = 3; st.ttff_fix_s = 95; st.fixed_ms = 600000; st.float_ms = 45000;
  uint8_t b[BACK_STATUS_V3_LEN + 8];
  size_t n = encode_status(st, b, sizeof(b));
  check(n == BACK_STATUS_V3_LEN && BACK_STATUS_V3_LEN == 108, "BackStatus v3 = 108 bytes (82 v2 + 26 quality)");
  BackStatus r;
  check(decode_status(b, n, &r) && r.v2 && r.v3, "chest decodes the back's v3 status");
  check(r.sv_tracked == 31 && r.sig_l2 == 26 && r.cno_mean == 41 && r.quality_age_s == 1 && r.quality_mon == 1 &&
        r.fix_lost == 3 && r.ttff_fix_s == 95 && r.fixed_ms == 600000 && r.float_ms == 45000, "v3 fields round-trip");

  // ---- 2. older back (v2 only)
  BackStatus v2 = st; v2.v3 = false;
  uint8_t b2[BACK_STATUS_V3_LEN + 8];
  size_t n2 = encode_status(v2, b2, sizeof(b2));
  BackStatus r2;
  check(n2 == BACK_STATUS_V2_LEN && decode_status(b2, n2, &r2) && r2.v2 && !r2.v3, "v2 status (old back) → v3 = false");

  // ---- 3. truncated v3 tail
  BackStatus r3;
  check(decode_status(b, BACK_STATUS_V3_LEN - 1, &r3) && r3.v2 && !r3.v3, "truncated v3 tail is not taken as v3");

  // ---- 4. TELEMETRY v3 == Android vector
  Telemetry t;
  t.session_state = 0; t.gf_state = 0; t.rec_status = 0; t.fix_type = 0; t.carr_soln = 1; t.num_sv = 27; t.hacc_mm = 140u;
  t.lat_e7 = 433800123; t.lon_e7 = -32170456; t.gspeed_mm_s = 0; t.distance_cm = 0u; t.active_ms = 0u; t.batt_pct = -1;
  t.link_connected = 0; t.girth_connected = 0; t.rtcm_flowing = 0; t.ring_fill_permille = 0u; t.dropped_records = 0u;
  t.pending_ms = 0u; t.inhibited = 0; t.gnss_flags = 0; t.corr_age_code = 0; t.sd_mounted = 0; t.pps_state = 255;
  t.back_batt_mv = 0u; t.time_source = 0; t.back_status_valid = 0; t.rtcm_to_back_bytes = 0u; t.rxm_rtcm_used = 0u;
  t.power_level = 3; t.vbus = 0; t.batt_mv = 0u; t.gnss_age_ms = 4294967295u; t.vacc_mm = 0u; t.link_age_ms = 4294967295u;
  t.manual = 0; t.girth_present = 0; t.girth_lost = 0u;
  t.q_flags = 3; t.sv_tracked = 31; t.sv_used = 27; t.sig_tracked = 58; t.sig_used = 50; t.sig_cr_used = 44; t.sig_corr = 48;
  t.sig_l2 = 26; t.sig_l2_used = 22; t.sig_weak = 5; t.cno_mean = 41; t.cno_min = 28; t.cno_max = 49; t.quality_age_s = 1;
  t.quality_mon = 1; t.fix_lost = 3u; t.ttff_fix_s = 95u; t.fixed_ms = 600000u; t.float_ms = 45000u; t.sacc_mm_s = 62u;
  t.pdop_e2 = 118u;
  uint8_t tb[TELEMETRY_V3_LEN + 8];
  size_t tl = encode_telemetry(t, tb, sizeof(tb));
  const char* android =
      "00000000011b8c000000bb43db19281e15fe000000000000000000000000ff0000000000000000000000000000000000ff00000000000000000000"
      "000003000000ffffffff00000000ffffffff000000000000031f1b3a322c301a1605291c31010103005f00c0270900c8af00003e0000007600";
  check(tl == 116 && TELEMETRY_V3_LEN == 116, "TELEMETRY v3 = 116 bytes (Android Telemetry.V3_LEN)");
  check(hex(tb, tl) == android, "TELEMETRY v3 bytes == Android FirmwareVectorsTest vector");
  if (hex(tb, tl) != android) std::printf("  got      %s\n  expected %s\n", hex(tb, tl).c_str(), android);

  // ---- 5. v2 prefix unchanged
  Telemetry t0 = t;
  t0.q_flags = 0; t0.sv_tracked = 0;
  uint8_t tb0[TELEMETRY_V3_LEN + 8];
  size_t tl0 = encode_telemetry(t0, tb0, sizeof(tb0));
  check(tl0 == tl && std::memcmp(tb, tb0, TELEMETRY_V2_LEN) == 0, "first 83 bytes (v2) do not depend on v3 fields");

  std::printf("\ngnss_quality_host: %s\n", fails ? "FAILED" : "ALL OK");
  return fails ? 1 : 0;
}
