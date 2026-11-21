// Clock maps of a whole session: chest reception -> GNSS time, and girth acquisition -> GNSS time per IMU.
// reception_cutoff_s (chest clock, seconds) limits the pairs to those RECEIVED up to that instant, which is
// what a real-time analysis is allowed to know (no future information). < 0 = use everything (offline).
#pragma once
#include "avo_eq/sync.h"
#include "avo_eq/types.h"
#include "avo_eq/validation.h"

namespace avoeq {
void build_session_maps(const Session& s, const ValidationReport& v, const SyncConfig& c, double reception_cutoff_s,
                        ClockMap* chest_to_gnss, ClockMap girth_to_gnss[3]);
// girth acquisition (s) -> chest reception (s) pairs (one per batch) composed with chest -> GNSS. Used for every IMU
// and for the ECG of the girth 0.5.x (same girth clock, own batches).
ClockMap compose_girth_map(const std::vector<double>& girth_s, const std::vector<double>& chest_s, const ClockMap& chest_to_gnss,
                           const SyncConfig& c);
}
