#include "eq_test.h"
#include <cstring>

namespace eqt {
std::vector<Case>& cases() { static std::vector<Case> c; return c; }
int failures = 0, checks = 0;
}

int main(int argc, char** argv) {
  const char* filter = argc > 1 ? argv[1] : nullptr;
  int failed_cases = 0, run = 0;
  for (auto& c : eqt::cases()) {
    if (filter && !strstr(c.suite, filter) && !strstr(c.name, filter)) continue;
    int before = eqt::failures;
    printf("[ .. ] %s.%s\n", c.suite, c.name);
    c.fn();
    run++;
    bool ok = eqt::failures == before;
    if (!ok) failed_cases++;
    printf("[%s] %s.%s\n", ok ? " OK " : "FALLO", c.suite, c.name);
  }
  printf("\n%d casos, %d comprobaciones, %d casos con fallos\n", run, eqt::checks, failed_cases);
  return failed_cases ? 1 : 0;
}
