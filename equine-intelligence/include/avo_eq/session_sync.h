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
}
