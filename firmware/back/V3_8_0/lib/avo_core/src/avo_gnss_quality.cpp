#include "avo_gnss_quality.h"

namespace avo {

bool gnss_sig_is_l1(uint8_t g, uint8_t s) {
  switch (g) {
    case 0: return s == 0;                  // GPS L1C/A (3,4 = L2CL/L2CM)
    case 1: return true;                    // SBAS L1C/A
    case 2: return s <= 1;                  // Galileo E1C/E1B (5,6 = E5bI/E5bQ)
    case 3: return s <= 1 || s == 5;        // BeiDou B1I D1/D2, B1C (2,3 = B2I, 7 = B2a)
    case 5: return s <= 1;                  // QZSS L1C/A, L1S (4,5 = L2CM/L2CL)
    case 6: return s == 0;                  // GLONASS L1OF (2 = L2OF)
    default: return false;
  }
}

bool ubx_quality_nav_sat(const uint8_t* p, size_t n, GnssQuality* q) {
  if (n < 8) return false;
  uint8_t num = p[5];
  if (n < 8 + (size_t)num * 12) return false;
  uint8_t tr = 0, used = 0;
  for (uint8_t i = 0; i < num; i++) {
    const uint8_t* s = p + 8 + (size_t)i * 12;
    uint32_t flags = (uint32_t)s[8] | ((uint32_t)s[9] << 8) | ((uint32_t)s[10] << 16) | ((uint32_t)s[11] << 24);
    if (s[2] > 0) tr++;
    if (flags & (1u << 3)) used++;          // svUsed
  }
  q->sv_tracked = tr; q->sv_used = used; q->have_sat = true;
  return true;
}

bool ubx_quality_nav_sig(const uint8_t* p, size_t n, GnssQuality* q) {
  if (n < 8) return false;
  uint8_t num = p[5];
  if (n < 8 + (size_t)num * 16) return false;
  uint8_t tr = 0, used = 0, cr = 0, corr = 0, l2 = 0, l2u = 0, weak = 0, cmin = 255, cmax = 0;
  uint32_t csum = 0;
  for (uint8_t i = 0; i < num; i++) {
    const uint8_t* s = p + 8 + (size_t)i * 16;
    uint8_t g = s[0], sig = s[2], cno = s[6];
    uint16_t f = (uint16_t)(s[10] | (s[11] << 8));
    if (cno == 0) continue;
    tr++;
    bool pr_used = f & (1u << 3), cr_used = f & (1u << 4);
    bool corr_used = f & ((1u << 6) | (1u << 7));   // prCorrUsed | crCorrUsed
    bool l1 = gnss_sig_is_l1(g, sig);
    if (!l1) { l2++; if (pr_used) l2u++; }
    if (cno < 30) weak++;
    if (pr_used) {
      used++;
      csum += cno;
      if (cno < cmin) cmin = cno;
      if (cno > cmax) cmax = cno;
    }
    if (cr_used) cr++;
    if (corr_used) corr++;
  }
  q->sig_tracked = tr; q->sig_used = used; q->sig_cr_used = cr; q->sig_corr = corr;
  q->sig_l2 = l2; q->sig_l2_used = l2u; q->sig_weak = weak;
  q->cno_mean = used ? (uint8_t)(csum / used) : 0;
  q->cno_min = used ? cmin : 0;
  q->cno_max = cmax;
  q->have_sig = true;
  return true;
}

}  // namespace avo
