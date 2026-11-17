// Host harness for usb_sync.cpp (the same file that runs on the watch, built with -DAVO_HOST_TEST).
//
//   usb_host mksession <root> <id> <state 1..4> <start_rtc_ms> <size1> [size2 ...]
//       creates <root>/<id>/meta (avo::session_meta_write) and deterministic P00n.avr segments.
//   usb_host serve <root>
//       stdin = bytes from the PC, stdout = bytes to the PC. Extra harness-only lines:
//         "!REC 1" / "!REC 0"  simulate a recording starting/stopping
//         "!LOG"               prints a firmware-style log line (the PC must ignore it)
//       Each AVO1 answer is preceded by a log line, as can happen on the real port.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <string>
#include <vector>

#include "usb_sync.h"
#include "avo_raw.h"

static bool g_rec = false;
static std::string g_pending;   // bytes waiting to be read by the firmware

namespace usbsync {
namespace port {
int read_byte() {
  if (g_pending.empty()) return -1;
  int b = (unsigned char)g_pending[0];
  g_pending.erase(0, 1);
  return b;
}
void write(const char* data, size_t n) {
  fputs("[AVO] log line printed by another task\n", stdout);
  fwrite(data, 1, n, stdout);
  fflush(stdout);
}
bool recording() { return g_rec; }
bool usb_host() { return false; }
uint32_t ms() { static uint32_t t = 1000; return t += 10; }
void power(int* pct, bool* vbus, bool* sd) { *pct = 87; *vbus = true; *sd = true; }
const char* fw_version() { return "3.7.5-usb1"; }
const char* device_id() { return "a0b1c2d3e4f5"; }
void* alloc(size_t n) { return malloc(n); }
void yield() {}
}  // namespace port
}  // namespace usbsync

static int mksession(int argc, char** argv) {
  if (argc < 7) return 2;
  std::string dir = std::string(argv[2]) + "/" + argv[3];
  mkdir(argv[2], 0755);
  mkdir(dir.c_str(), 0755);
  avo::SessionMetaFile m;
  snprintf(m.session_id, sizeof(m.session_id), "%s", argv[3]);
  m.state = (avo::SessionFileState)atoi(argv[4]);
  m.start_rtc_ms = strtoull(argv[5], nullptr, 10);
  m.segments = (uint16_t)(argc - 6);
  m.active_ms = 60000;
  if (!avo::session_meta_write(dir.c_str(), &m)) return 3;
  uint32_t x = 2463534242u ^ (uint32_t)m.start_rtc_ms;
  for (int i = 6; i < argc; i++) {
    char p[512];
    snprintf(p, sizeof(p), "%s/P%03d.avr", dir.c_str(), i - 5);
    FILE* f = fopen(p, "wb");
    if (!f) return 4;
    long n = atol(argv[i]);
    for (long k = 0; k < n; k++) { x ^= x << 13; x ^= x >> 17; x ^= x << 5; fputc((int)(x & 0xFF), f); }
    fclose(f);
  }
  return 0;
}

int main(int argc, char** argv) {
  if (argc >= 2 && !strcmp(argv[1], "mksession")) return mksession(argc, argv);
  if (argc != 3 || strcmp(argv[1], "serve")) { fprintf(stderr, "usage: see source\n"); return 2; }
  usbsync::set_root(argv[2]);
  if (!usbsync::init()) return 5;
  char line[512];
  while (fgets(line, sizeof(line), stdin)) {
    if (!strncmp(line, "!REC ", 5)) { g_rec = line[5] == '1'; continue; }
    if (!strncmp(line, "!PC", 3)) {
      usbsync::PcStatus st;
      usbsync::pc_status(&st);
      printf("PCSTATUS %u %u %u %u %u\n", st.phase, st.pct, st.index, st.count, st.new_count);
      fflush(stdout);
      continue;
    }
    if (!strncmp(line, "!LOG", 4)) { fputs("[AVO NOW] paired with back\n", stdout); fflush(stdout); continue; }
    g_pending += line;
    while (!g_pending.empty()) usbsync::poll();
  }
  return 0;
}
