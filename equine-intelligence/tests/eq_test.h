// Minimal test framework (no external dependency). Every check prints its numbers on failure.
#pragma once
#include <cmath>
#include <cstdio>
#include <functional>
#include <string>
#include <vector>

namespace eqt {
struct Case { const char* suite; const char* name; std::function<void()> fn; };
std::vector<Case>& cases();
extern int failures, checks;
struct Reg { Reg(const char* s, const char* n, std::function<void()> f) { cases().push_back({s, n, f}); } };
}  // namespace eqt

#define EQ_TEST(s, n) static void s##_##n(); static eqt::Reg reg_##s##_##n(#s, #n, s##_##n); static void s##_##n()
#define CHECK(c) do { eqt::checks++; if (!(c)) { eqt::failures++; printf("    FALLO %s:%d: %s\n", __FILE__, __LINE__, #c); } } while (0)
#define CHECK_NEAR(a, b, tol) do { eqt::checks++; double _a = (a), _b = (b); if (!(std::fabs(_a - _b) <= (tol))) { eqt::failures++; \
  printf("    FALLO %s:%d: %s = %.6g, esperado %.6g ± %.3g\n", __FILE__, __LINE__, #a, _a, _b, (double)(tol)); } } while (0)
#define REPORT(...) printf("    " __VA_ARGS__)
