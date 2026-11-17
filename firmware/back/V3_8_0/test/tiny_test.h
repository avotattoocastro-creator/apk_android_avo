// Minimal self-contained test harness (no external dependencies).
#pragma once
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <vector>
#include <string>
#include <functional>

struct TT_Case { const char* suite; const char* name; std::function<void()> fn; };
inline std::vector<TT_Case>& tt_cases() { static std::vector<TT_Case> v; return v; }
inline int& tt_fail_count() { static int n = 0; return n; }
inline int& tt_check_count() { static int n = 0; return n; }
inline bool& tt_case_failed() { static bool b = false; return b; }

struct TT_Reg { TT_Reg(const char* s, const char* n, std::function<void()> f) { tt_cases().push_back({s, n, f}); } };

#define TT_CAT2(a, b) a##b
#define TT_CAT(a, b) TT_CAT2(a, b)
#define TEST(suite, name)                                                        \
  static void TT_CAT(tt_fn_, TT_CAT(suite, name))();                             \
  static TT_Reg TT_CAT(tt_reg_, TT_CAT(suite, name))(#suite, #name, TT_CAT(tt_fn_, TT_CAT(suite, name))); \
  static void TT_CAT(tt_fn_, TT_CAT(suite, name))()

#define CHECK(c)                                                                         \
  do {                                                                                   \
    tt_check_count()++;                                                                  \
    if (!(c)) { tt_case_failed() = true; fprintf(stderr, "  FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); } \
  } while (0)
#define CHECK_EQ(a, b)                                                                           \
  do {                                                                                           \
    tt_check_count()++;                                                                          \
    auto _a = (a); auto _b = (b);                                                                \
    if (!(_a == _b)) { tt_case_failed() = true; fprintf(stderr, "  FAIL %s:%d: %s == %s (%lld vs %lld)\n", __FILE__, __LINE__, #a, #b, (long long)_a, (long long)_b); } \
  } while (0)
#define CHECK_NEAR(a, b, eps)                                                                      \
  do {                                                                                             \
    tt_check_count()++;                                                                            \
    double _a = (a), _b = (b);                                                                     \
    if (fabs(_a - _b) > (eps)) { tt_case_failed() = true; fprintf(stderr, "  FAIL %s:%d: %s ~ %s (%.6f vs %.6f)\n", __FILE__, __LINE__, #a, #b, _a, _b); } \
  } while (0)

inline int tt_run_all(const char* filter) {
  int run = 0;
  for (auto& c : tt_cases()) {
    if (filter && !strstr(c.suite, filter)) continue;
    tt_case_failed() = false;
    c.fn();
    run++;
    if (tt_case_failed()) { tt_fail_count()++; printf("[FAIL] %s.%s\n", c.suite, c.name); }
    else printf("[ OK ] %s.%s\n", c.suite, c.name);
  }
  printf("\n%d test cases, %d checks, %d failed cases\n", run, tt_check_count(), tt_fail_count());
  return tt_fail_count() ? 1 : 0;
}
