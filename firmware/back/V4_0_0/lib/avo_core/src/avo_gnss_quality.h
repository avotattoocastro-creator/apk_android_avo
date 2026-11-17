// V3.9.0 GNSS quality from the ZED-F9P (u-blox F9 HPG Interface Description: UBX-NAV-SAT, UBX-NAV-SIG).
// Summaries only: what tells whether RTK can work (second-frequency signals, carrier phase in use,
// signal strength). Portable and host-tested.
#pragma once
#include <stdint.h>
#include <stddef.h>

namespace avo {

static const uint8_t UBX_ID_NAV_SAT = 0x35, UBX_ID_NAV_SIG = 0x43;

struct GnssQuality {
  // NAV-SAT
  uint8_t sv_tracked = 0;     // satellites with C/N0 > 0
  uint8_t sv_used = 0;        // satellites used in the navigation solution
  // NAV-SIG
  uint8_t sig_tracked = 0;    // signals with C/N0 > 0
  uint8_t sig_used = 0;       // pseudorange used in the solution
  uint8_t sig_cr_used = 0;    // carrier range used (what RTK needs)
  uint8_t sig_corr = 0;       // signals with corrections applied (pseudorange or carrier)
  uint8_t sig_l2 = 0;         // tracked signals on the second band (L2 / E5b / B2I): 0 = L1-only antenna
  uint8_t sig_l2_used = 0;
  uint8_t sig_weak = 0;       // tracked signals below 30 dBHz
  uint8_t cno_mean = 0;       // mean C/N0 (dBHz) of the signals used
  uint8_t cno_min = 0, cno_max = 0;
  bool have_sat = false, have_sig = false;
};

// True for first-band signals (L1 / E1 / B1 / L1OF). gnssId/sigId as in UBX-NAV-SIG.
bool gnss_sig_is_l1(uint8_t gnss_id, uint8_t sig_id);
// Fill the NAV-SAT part of q. False if the payload is malformed.
bool ubx_quality_nav_sat(const uint8_t* pl, size_t n, GnssQuality* q);
// Fill the NAV-SIG part of q. False if the payload is malformed.
bool ubx_quality_nav_sig(const uint8_t* pl, size_t n, GnssQuality* q);

}  // namespace avo
