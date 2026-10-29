// Host tests of the AVO BACK V4 board helpers (pairing gesture, PPS statistics, SD FIFO, battery scale).
#include "tiny_test.h"
#include "avo_board_v4.h"

using namespace avo::v4;

TEST(v4, pair_gesture_three_placements_within_window) {
  PairGesture g;
  g.reset(true);
  uint32_t t = 1000;
  // off / on three times, 1 s apart
  int fired = 0;
  for (int k = 0; k < 3; k++) {
    fired += g.update(t, false); t += 500;
    fired += g.update(t, true); t += 500;
  }
  CHECK_EQ(fired, 1);
}

TEST(v4, pair_gesture_too_slow_does_not_fire) {
  PairGesture g;
  g.reset(true);
  uint32_t t = 0;
  int fired = 0;
  for (int k = 0; k < 3; k++) {
    fired += g.update(t, false); t += 2500;
    fired += g.update(t, true); t += 2500;     // 3 placements over > 8 s
  }
  CHECK_EQ(fired, 0);
}

TEST(v4, pair_gesture_staying_on_support_never_fires) {
  PairGesture g;
  g.reset(true);
  int fired = 0;
  for (uint32_t t = 0; t < 60000; t += 100) fired += g.update(t, true);
  CHECK_EQ(fired, 0);
}

TEST(v4, pps_jitter_and_alive) {
  PpsStats s;
  uint64_t t = 5000000;
  s.edge(t);
  for (int i = 0; i < 10; i++) { t += 1000000 + (i % 2 ? 7 : -3); s.edge(t); }
  CHECK_EQ(s.count, 11u);
  CHECK_EQ(s.max_dev_us, 7);
  CHECK(s.alive(t + 1500000));
  CHECK(!s.alive(t + 2500000));
  t += 3000000; s.edge(t);                      // lost pulses: not counted as jitter
  CHECK_EQ(s.max_dev_us, 7);
}

TEST(v4, fifo_keeps_order_and_counts_drops) {
  ByteFifo<16> f;
  uint8_t in[20], out[20];
  for (int i = 0; i < 20; i++) in[i] = (uint8_t)i;
  CHECK_EQ(f.push(in, 10), 10u);
  CHECK_EQ(f.pop(out, 4), 4u);
  CHECK_EQ(out[0], 0); CHECK_EQ(out[3], 3);
  CHECK_EQ(f.push(in + 10, 10), 9u);            // 15 usable bytes, 6 used → 9 fit, 1 dropped
  CHECK_EQ(f.dropped(), 1u);
  size_t n = f.pop(out, 20);
  CHECK_EQ(n, 15u);
  CHECK_EQ(out[0], 4); CHECK_EQ(out[5], 9); CHECK_EQ(out[6], 10); CHECK_EQ(out[14], 18);
}

TEST(v4, battery_scale) {
  CHECK_EQ(battery_mv_from_adc(1900), 3800);
  CHECK_EQ(battery_mv_from_adc(100), 0);        // no battery / wrong reading
  CHECK_EQ(battery_mv_from_adc(2400), 0);       // 4.8 V: not a 1-cell Li-ion
}

TEST(v4, pins_do_not_collide_and_avoid_strapping_and_flash) {
  const int pins[] = {PIN_HALL, PIN_BAT_ADC, PIN_ZED_PPS, PIN_ZED_TX1, PIN_S3_TX1, PIN_ZED_TX2, PIN_S3_TX2, PIN_ZED_RST,
                      PIN_ZED_EN, PIN_LED, PIN_SD_CLK, PIN_SD_CMD, PIN_SD_D0, PIN_SD_D1, PIN_SD_D2, PIN_SD_D3, PIN_SD_CD,
                      PIN_SD_PWR_N, PIN_CHG_PG, PIN_CHG_STAT, PIN_QI_CHG};
  const int n = sizeof(pins) / sizeof(pins[0]);
  for (int i = 0; i < n; i++) {
    for (int j = i + 1; j < n; j++) CHECK(pins[i] != pins[j]);
    CHECK(pins[i] != 0 && pins[i] != 3 && pins[i] != 45 && pins[i] != 46);   // strapping pins
    CHECK(!(pins[i] >= 26 && pins[i] <= 32));                                // in-package flash
    CHECK(pins[i] != 19 && pins[i] != 20);                                    // native USB
  }
  CHECK(PIN_HALL <= 21);                                                      // RTC GPIO: ext0 wake-up
}
