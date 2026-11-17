// Time synchronisation between clocks from (acquisition time, reception time) pairs.
// Reception = acquisition * (1 + drift) + offset + latency, latency >= 0 and variable.
// The line is fitted to the LOWER ENVELOPE (packets that suffered the least delay), not to the mean,
// so variable radio latency does not bias the offset. A clock restart (big jump) starts a new piece.
#pragma once
#include <cstdint>
#include <vector>

namespace avoeq {

struct ClockPiece {
  double x0 = 0, x1 = 0;          // validity range in the source clock (s)
  double offset = 0;              // y = offset + slope * x  (s)
  double slope = 1;
  double drift_ppm = 0;           // (slope - 1) * 1e6
  double envelope_sd_s = 0;       // scatter of the envelope points around the line (uncertainty of the map)
  double latency_median_s = 0, latency_p95_s = 0;   // reception delay above the envelope
  uint32_t pairs = 0, envelope_pairs = 0;
};

struct ClockMap {
  std::vector<ClockPiece> pieces;
  // Converts a source-clock time to the target clock using the piece that contains it.
  // Returns false when x is outside every piece (no extrapolation beyond 1 s).
  bool map(double x, double* y, double* sigma = nullptr) const;
  uint32_t resets() const { return pieces.empty() ? 0 : (uint32_t)pieces.size() - 1; }
};

struct SyncConfig {
  double envelope_quantile = 0.2;  // keep the 20 % lowest residuals at each iteration
  int iterations = 4;
  double reset_jump_s = 0.5;       // a jump of the source clock vs target larger than this = restart
  uint32_t min_pairs = 8;
};

// xs: acquisition times in the source clock, ys: reception times in the target clock (both seconds).
ClockMap fit_clock(const std::vector<double>& xs, const std::vector<double>& ys, const SyncConfig& c = SyncConfig());

}  // namespace avoeq
