// AVO CHEST V3.7.5-usb1 — training download to the PC over the USB cable (protocol AVO1).
//
// The Windows app opens the watch's USB serial port (USB-Serial/JTAG, VID 303A / PID 1001), sends text commands
// that start with "AVO1 " and reads the answers, which always start with "#AVO1 ". Everything else on the port
// (the normal [AVO ...] log lines) is ignored by the PC. Read-only: it never writes, renames or deletes anything
// on the microSD. It does not serve anything while a recording is running.
// Protocol: firmware/chest/V3_7_5_USB/PROTOCOLO_USB.md
#pragma once
#include <stddef.h>
#include <stdint.h>

namespace usbsync {

static const uint32_t API = 1;
static const size_t MAX_READ = 4096;   // bytes per READ answer (one line, base64)

bool init();            // allocates the buffers (PSRAM); no task: poll() runs in the Arduino loop task
void poll();            // reads the pending USB bytes and answers complete commands; returns at once if idle

struct Stats { uint32_t commands, errors, bytes_sent, hellos; };
void stats(Stats* out);

// Test hook (host build only uses it): microSD root that holds the S... session folders.
void set_root(const char* root);

// Platform layer: implemented in usb_sync.cpp for the watch, and by the host harness in the tests.
namespace port {
int read_byte();                                // next byte from the PC, or -1 if there is none
void write(const char* data, size_t n);         // one call per complete line (keeps log lines out of it)
bool recording();                               // a session is being written to the microSD
void power(int* batt_pct, bool* vbus, bool* sd_mounted);
const char* fw_version();
const char* device_id();
void* alloc(size_t n);                          // PSRAM on the watch
void yield();                                   // lets other tasks run during long work
}  // namespace port

}  // namespace usbsync
