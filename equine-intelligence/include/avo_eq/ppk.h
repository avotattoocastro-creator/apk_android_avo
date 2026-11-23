// AVO PPK 1.0.0 (motor 2.0.0-dev33, 23/11/2026) — post-processed kinematic positioning of the back GNSS.
//
// Rover: UBX-RXM-RAWX + RXM-SFRBX of the ZED-F9P stored in the .avr session
//   - PROTOTYPE back (Heltec) >= 3.16.0: GNSS_UBX_FRAG frames (0x12), joined here (avo_ubx_frag.h)
//   - BETA back (casco V5): whole GNSS_UBX frames (0x11) written to its own microSD (same contract, no radio limit)
// Base: RINEX 3 observation files of a reference station (IGN ERGNSS hourly 1 s files: gzip + Hatanaka; the app
//   removes the gzip layer, the engine expands Hatanaka). Navigation data: from the rover SFRBX and, if given, from
//   RINEX navigation files.
// Solver: RTKLIB demo5 (src/ppk/rtklib, BSD 2-clause), kinematic RTK, forward and backward passes combined.
#pragma once
#include <cstdint>
#include <string>
#include <vector>

namespace avoeq {

// Expands a Hatanaka-compressed RINEX 3 observation file (CRINEX 3.0, Hatanaka 2008) into plain RINEX.
// Returns false with *error set when the text is not CRINEX 3 or is damaged.
bool crx_to_rnx(const std::string& crx, std::string* rnx, std::string* error);
bool is_crinex(const std::string& head);

struct PpkRoverStats {
  uint32_t frag_frames = 0, frag_incomplete = 0, frag_bad = 0;   // GNSS_UBX_FRAG pieces joined / lost / bad
  uint32_t whole_frames = 0;                                     // GNSS_UBX (0x11) RXM frames (BETA casco)
  uint32_t rawx = 0, sfrbx = 0;                                  // UBX messages in the stream
  uint64_t bytes = 0;
};
// Extracts the verbatim UBX stream (RXM-RAWX / RXM-SFRBX, in recording order) from the .avr segments.
bool ppk_extract_ubx(const std::vector<std::string>& segments, std::vector<uint8_t>* ubx, PpkRoverStats* st, std::string* error);

struct PpkOptions {
  double elev_min_deg = 15.0;
  int freqs = 2;                  // 1 = L1, 2 = L1 + L2/E5b
  bool glonass_ar = false;        // GLONASS ambiguity resolution (inter-channel biases of mixed receivers: off)
  bool fix_and_hold = true;
  double ar_ratio = 3.0;
  double max_age_s = 30.0;        // base epoch used up to this time difference (30 s daily files still work)
  bool combine = true;            // forward + backward
  bool have_base_xyz = false;
  double base_xyz[3] = {0, 0, 0}; // ECEF (m); otherwise APPROX POSITION XYZ of the base RINEX header
  std::string work_dir;           // where expanded RINEX copies are written (default: next to the input)
};

struct PpkEpoch {
  int week = 0;
  double tow_s = 0;               // GPS time of week (s): aligns with iTOW of NAV-PVT
  int64_t utc_ms = 0;
  double lat_deg = 0, lon_deg = 0, h_m = 0;   // ellipsoidal height
  int q = 0;                      // 1 FIX, 2 FLOAT, 5 SINGLE (RTKLIB codes), 0 none
  int ns = 0;
  double sdn = 0, sde = 0, sdu = 0;           // 1-sigma (m)
  double ratio = 0;
  double age_s = 0;
  double vn = 0, ve = 0, vu = 0;              // m/s, from consecutive positions of the same quality (0 if unknown)
};

struct PpkResult {
  PpkRoverStats rover;
  uint32_t rover_epochs = 0, base_epochs = 0, nav_eph = 0;
  std::string base_name;
  double base_llh[3] = {0, 0, 0};
  double baseline_km = 0;
  uint32_t fix = 0, flt = 0, single = 0;
  std::vector<PpkEpoch> epochs;
  std::vector<std::string> warnings;
  std::string first_utc, last_utc;
};

// Rover information only (no base): what base data the app has to download.
struct PpkNeed {
  bool has_raw = false;
  std::string start_utc, end_utc;   // ISO-8601, from the first and last RAWX epoch
  double lat_deg = 0, lon_deg = 0;  // approximate (single point solution of the rover)
  uint32_t rawx = 0;
};
bool ppk_need(const std::vector<uint8_t>& ubx, PpkNeed* need);

// rover_ubx: verbatim UBX bytes. base_files: RINEX 3 observation (plain or Hatanaka) and optional navigation files.
bool ppk_solve(const std::vector<uint8_t>& rover_ubx, const std::vector<std::string>& base_files, const PpkOptions& o,
               PpkResult* r, std::string* error, const volatile int* cancel = nullptr);

// Same solver with the rover in RINEX (other receivers, tests against reference data, files converted elsewhere).
bool ppk_solve_rinex_rover(const std::vector<std::string>& rover_files, const std::vector<std::string>& base_files,
                           const PpkOptions& o, PpkResult* r, std::string* error, const volatile int* cancel = nullptr);

std::string ppk_result_json(const PpkResult& r, bool with_epochs);

}  // namespace avoeq
