// AVO CHEST V3.7.4 — training download over Wi-Fi.
//
// Design (docs: firmware/chest/V3_7_4_WIFI/PROTOCOLO_WIFI.md):
//  * SoftAP "AVO_CHEST_XXXX" WPA2 on the SAME channel as ESP-NOW (single radio): the back keeps sending
//    telemetry while the download runs. AP_STA mode; the STA interface is still the ESP-NOW one.
//  * Per-device random password (NVS "wifipw"), exchanged only over authenticated BLE. Never logged.
//  * 128-bit session token, new on every start, required in "Authorization: Bearer"; it dies with the AP.
//    After 5 failed authentications the AP is turned off.
//  * Read-only HTTP: list, metadata, SHA-256 and segment download with Range. Sessions in OPEN state
//    (recording or interrupted without recovery) are never served. Paths are built only from validated
//    identifiers (no arbitrary SD paths).
//  * Never during a recording: it refuses to turn on and, if a session starts, it turns off immediately.
//  * Automatic shutdown: no client 60 s, idle 45 s, maximum 15 min, low battery, client gone 20 s,
//    and when the app confirms the end (POST /api/v1/sync/complete with done=1).
#include "wifi_sync.h"

#include <Arduino.h>
#include <WiFi.h>
#include <esp_http_server.h>
#include <esp_random.h>
#include <esp_wifi.h>
#include <esp_heap_caps.h>
#include <mbedtls/sha256.h>
#include <sys/stat.h>
#include <dirent.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"

#include "app_state.h"
#include "services.h"
#include "sys_util.h"
#include "avo_core.h"
#include "avo_espnow_link.h"
#include "avo_raw.h"
#include "avo_blackbox.h"

#ifndef AVO_SD_MOUNT
#define AVO_SD_MOUNT "/sdcard"
#endif

using namespace avo;

namespace wifisync {

static const char* ROOT = AVO_SD_MOUNT "/AVO";
static const uint32_t NO_CLIENT_MS = 60000, IDLE_MS = 45000, MAX_ON_MS = 15 * 60000, CLIENT_LEFT_MS = 20000;
static const int MIN_BATT_PCT = 15, STOP_BATT_PCT = 10, MAX_AUTH_FAIL = 5;
static const size_t CHUNK = 16 * 1024;
// rc2: minimum internal RAM to bring up AP + httpd next to BLE + ESP-NOW (internal estimate: ~45 KB)
// 3.7.5-rc3: Wi-Fi is already initialised for ESP-NOW (STA), so AP+HTTP costs less than a cold start. Thresholds
// lowered to fit the measured margin; a reboot while starting is still caught (NVS breadcrumb + app guard).
static const size_t MIN_INTERNAL_FREE = 20 * 1024, MIN_INTERNAL_BLOCK = 8 * 1024;
static const uint32_t WORKER_STACK = 6144;   // internal (it writes NVS: it cannot go in PSRAM)

static SemaphoreHandle_t s_mx = nullptr;
static volatile State s_state = State::OFF;
static Credentials s_cred = {};
static httpd_handle_t s_httpd = nullptr;
static uint32_t s_on_since = 0, s_last_activity = 0, s_client_left_at = 0;
static volatile uint32_t s_requests = 0, s_auth_fail = 0, s_bytes = 0, s_completes = 0, s_starts = 0, s_on_total = 0;
static volatile StopReason s_last_stop = StopReason::NONE;
static volatile bool s_stop_req = false;
static volatile StopReason s_stop_why = StopReason::NONE;
static uint8_t* s_buf = nullptr;   // PSRAM, CHUNK bytes

struct ShaCache { char id[24]; uint64_t total; uint8_t h[32]; bool valid; };
static ShaCache s_sha[4] = {};

// ------------------------------------------------------------------ helpers
static void lock() { xSemaphoreTake(s_mx, portMAX_DELAY); }
static void unlock() { xSemaphoreGive(s_mx); }
static void touch() { s_last_activity = sys::ms(); }

static void hex(const uint8_t* b, size_t n, char* out) {
  static const char* H = "0123456789abcdef";
  for (size_t i = 0; i < n; i++) { out[2 * i] = H[b[i] >> 4]; out[2 * i + 1] = H[b[i] & 15]; }
  out[2 * n] = 0;
}

static bool recording_now() {
  AppSnapshot* s = new AppSnapshot();
  appstate::get(s);
  bool rec = s->storage.rec == RecStatus::RECORDING;   // TEMP_BUFFER = pre-buffer in RAM, it does not write to SD
  delete s;
  return rec || storage::session_active();
}

static bool battery(int* pct, bool* vbus, bool* sd) {
  AppSnapshot* s = new AppSnapshot();
  appstate::get(s);
  *pct = s->power.pmu.batt_pct; *vbus = s->power.pmu.vbus; *sd = s->storage.mounted;
  delete s;
  return true;
}

static void load_or_make_password(char* out, size_t cap, bool regenerate) {
  size_t n = cap - 1;
  if (!regenerate && sys::nvs_get_blob("wifipw", out, &n) && n >= 16 && n < cap) { out[n] = 0; return; }
  static const char* A = "abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789";   // 54 symbols, ~115 bits with 20
  for (int i = 0; i < 20; i++) out[i] = A[esp_random() % 54];
  out[20] = 0;
  sys::nvs_set_blob("wifipw", out, 20);
}

// Session identifier: as written by the watch ("S" + hex/digits/_), no separators or "..".
static bool valid_id(const char* id) {
  size_t n = strlen(id);
  if (n < 2 || n > 23 || id[0] != 'S') return false;
  for (size_t i = 0; i < n; i++) {
    char c = id[i];
    if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' || c == '-')) return false;
  }
  return true;
}

struct SessionInfo {
  SessionMetaFile m;
  bool meta_ok;
  uint16_t segs;
  uint32_t sizes[64];
  uint64_t total;
  uint32_t etag;
};

static void seg_path(const char* id, uint16_t seg, char* out, size_t cap) {
  snprintf(out, cap, "%s/%s/P%03u.avr", ROOT, id, (unsigned)seg);
}

// Reads meta + real segment sizes. false if it does not exist.
static bool session_info(const char* id, SessionInfo* si) {
  char dir[96];
  snprintf(dir, sizeof(dir), "%s/%s", ROOT, id);
  struct stat st;
  if (stat(dir, &st) != 0) return false;
  si->meta_ok = session_meta_read(dir, &si->m);
  si->segs = 0; si->total = 0;
  uint32_t h = 2166136261u;
  for (uint16_t s = 1; s <= 64; s++) {
    char p[128];
    seg_path(id, s, p, sizeof(p));
    if (stat(p, &st) != 0) break;
    si->sizes[si->segs++] = (uint32_t)st.st_size;
    si->total += (uint64_t)st.st_size;
    h = (h ^ (uint32_t)st.st_size) * 16777619u;
    h = (h ^ s) * 16777619u;
  }
  if (si->meta_ok) { h = (h ^ (uint32_t)si->m.start_rtc_ms) * 16777619u; h = (h ^ (uint32_t)si->m.state) * 16777619u; }
  si->etag = h;
  return true;
}

static bool servable(const SessionInfo& si) {
  return si.meta_ok && si.m.state != SessionFileState::OPEN && si.segs > 0;
}

// ------------------------------------------------------------------ HTTP
static esp_err_t send_json(httpd_req_t* r, const char* status, const char* body) {
  httpd_resp_set_status(r, status);
  httpd_resp_set_type(r, "application/json");
  httpd_resp_set_hdr(r, "Cache-Control", "no-store");
  return httpd_resp_send(r, body, HTTPD_RESP_USE_STRLEN);
}

static esp_err_t err(httpd_req_t* r, const char* status, const char* code) {
  char b[96];
  snprintf(b, sizeof(b), "{\"error\":\"%s\"}", code);
  return send_json(r, status, b);
}

// Authentication + common guards. Returns true if the request may continue.
static bool guard(httpd_req_t* r) {
  s_requests++;
  touch();
  char auth[64] = {0};
  bool ok = httpd_req_get_hdr_value_str(r, "Authorization", auth, sizeof(auth)) == ESP_OK && strncmp(auth, "Bearer ", 7) == 0;
  if (ok) {
    // constant-time comparison
    const char* t = auth + 7;
    uint8_t diff = (uint8_t)(strlen(t) != 32);
    for (int i = 0; i < 32; i++) diff |= (uint8_t)(t[i] ^ s_cred.token[i]);
    ok = diff == 0 && s_cred.token[0];
  }
  if (!ok) {
    uint32_t f = ++s_auth_fail;
    err(r, "401 Unauthorized", "token");
    if (f >= MAX_AUTH_FAIL) { s_stop_why = StopReason::AUTH_FAIL; s_stop_req = true; }
    return false;
  }
  if (recording_now()) { err(r, "409 Conflict", "recording"); s_stop_why = StopReason::RECORDING; s_stop_req = true; return false; }
  return true;
}

// Extracts the id from "/api/v1/trainings/<id>[/...]" into out; returns the rest of the path.
static const char* parse_id(const char* uri, char* out, size_t cap) {
  const char* p = uri + strlen("/api/v1/trainings/");
  size_t n = 0;
  while (p[n] && p[n] != '/' && p[n] != '?' && n < cap - 1) { out[n] = p[n]; n++; }
  out[n] = 0;
  return p + n;
}

static esp_err_t h_status(httpd_req_t* r) {
  if (!guard(r)) return ESP_OK;
  int pct; bool vbus, sd;
  battery(&pct, &vbus, &sd);
  uint32_t now = sys::ms();
  char b[320];
  snprintf(b, sizeof(b),
           "{\"api\":1,\"fw\":\"%s\",\"device\":\"%s\",\"recording\":false,\"sd\":%s,\"battery_pct\":%d,\"vbus\":%s,"
           "\"idle_timeout_s\":%u,\"off_in_s\":%u,\"requests\":%u,\"bytes_sent\":%u,\"raw_format\":%u}",
           AVO_FW_VERSION, sys::device_id_hex(), sd ? "true" : "false", pct, vbus ? "true" : "false",
           (unsigned)(IDLE_MS / 1000), (unsigned)((MAX_ON_MS - (now - s_on_since)) / 1000), (unsigned)s_requests, (unsigned)s_bytes,
           (unsigned)RAW_FORMAT_VERSION);
  return send_json(r, "200 OK", b);
}

static esp_err_t h_list(httpd_req_t* r) {
  if (!guard(r)) return ESP_OK;
  DIR* d = opendir(ROOT);
  if (!d) return err(r, "503 Service Unavailable", "sd");
  httpd_resp_set_type(r, "application/json");
  httpd_resp_set_hdr(r, "Cache-Control", "no-store");
  httpd_resp_sendstr_chunk(r, "{\"trainings\":[");
  SessionInfo* si = (SessionInfo*)heap_caps_malloc(sizeof(SessionInfo), MALLOC_CAP_SPIRAM);
  bool first = true;
  struct dirent* e;
  while (si && (e = readdir(d)) != nullptr) {
    if (!valid_id(e->d_name) || !session_info(e->d_name, si)) continue;
    char b[320];
    snprintf(b, sizeof(b),
             "%s{\"id\":\"%s\",\"state\":%u,\"ready\":%s,\"segments\":%u,\"size\":%llu,\"start_rtc_ms\":%llu,\"active_ms\":%u,\"etag\":\"%08x\"}",
             first ? "" : ",", e->d_name, si->meta_ok ? (unsigned)si->m.state : 0, servable(*si) ? "true" : "false", (unsigned)si->segs,
             (unsigned long long)si->total, (unsigned long long)(si->meta_ok ? si->m.start_rtc_ms : 0),
             (unsigned)(si->meta_ok ? si->m.active_ms : 0), (unsigned)si->etag);
    httpd_resp_sendstr_chunk(r, b);
    first = false;
    touch();
  }
  closedir(d);
  if (si) heap_caps_free(si);
  httpd_resp_sendstr_chunk(r, "]}");
  return httpd_resp_sendstr_chunk(r, nullptr);
}

static esp_err_t h_metadata(httpd_req_t* r, const char* id) {
  SessionInfo* si = (SessionInfo*)heap_caps_malloc(sizeof(SessionInfo), MALLOC_CAP_SPIRAM);
  if (!si) return err(r, "500 Internal Server Error", "mem");
  if (!session_info(id, si)) { heap_caps_free(si); return err(r, "404 Not Found", "id"); }
  char b[1400];
  int n = snprintf(b, sizeof(b),
                   "{\"id\":\"%s\",\"state\":%u,\"ready\":%s,\"raw_format\":%u,\"size\":%llu,\"start_rtc_ms\":%llu,\"active_ms\":%u,\"etag\":\"%08x\",\"segments\":[",
                   id, si->meta_ok ? (unsigned)si->m.state : 0, servable(*si) ? "true" : "false", (unsigned)RAW_FORMAT_VERSION,
                   (unsigned long long)si->total, (unsigned long long)(si->meta_ok ? si->m.start_rtc_ms : 0),
                   (unsigned)(si->meta_ok ? si->m.active_ms : 0), (unsigned)si->etag);
  for (uint16_t i = 0; i < si->segs && n < (int)sizeof(b) - 32; i++) n += snprintf(b + n, sizeof(b) - n, "%s%u", i ? "," : "", (unsigned)si->sizes[i]);
  snprintf(b + n, sizeof(b) - n, "]}");
  heap_caps_free(si);
  return send_json(r, "200 OK", b);
}

static esp_err_t h_sha(httpd_req_t* r, const char* id) {
  SessionInfo* si = (SessionInfo*)heap_caps_malloc(sizeof(SessionInfo), MALLOC_CAP_SPIRAM);
  if (!si) return err(r, "500 Internal Server Error", "mem");
  if (!session_info(id, si)) { heap_caps_free(si); return err(r, "404 Not Found", "id"); }
  if (!servable(*si)) { heap_caps_free(si); return err(r, "409 Conflict", "open"); }
  uint8_t h[32];
  bool cached = false;
  for (auto& c : s_sha) if (c.valid && !strcmp(c.id, id) && c.total == si->total) { memcpy(h, c.h, 32); cached = true; }
  if (!cached) {
    mbedtls_sha256_context ctx;
    mbedtls_sha256_init(&ctx);
    mbedtls_sha256_starts(&ctx, 0);
    bool ok = true;
    for (uint16_t s = 1; s <= si->segs && ok; s++) {
      char p[128];
      seg_path(id, s, p, sizeof(p));
      FILE* f = fopen(p, "rb");
      if (!f) { ok = false; break; }
      size_t n;
      while ((n = fread(s_buf, 1, CHUNK, f)) > 0) { mbedtls_sha256_update(&ctx, s_buf, n); touch(); vTaskDelay(1); }
      fclose(f);
    }
    mbedtls_sha256_finish(&ctx, h);
    mbedtls_sha256_free(&ctx);
    if (!ok) { heap_caps_free(si); return err(r, "500 Internal Server Error", "io"); }
    static int slot = 0;
    ShaCache& c = s_sha[slot++ % 4];
    strncpy(c.id, id, sizeof(c.id) - 1); c.total = si->total; memcpy(c.h, h, 32); c.valid = true;
  }
  char hs[65], b[200];
  hex(h, 32, hs);
  snprintf(b, sizeof(b), "{\"id\":\"%s\",\"sha256\":\"%s\",\"size\":%llu,\"etag\":\"%08x\"}", id, hs, (unsigned long long)si->total, (unsigned)si->etag);
  heap_caps_free(si);
  return send_json(r, "200 OK", b);
}

// GET /api/v1/trainings/<id>/segments/<n> with optional Range: bytes=a- / bytes=a-b
static esp_err_t h_segment(httpd_req_t* r, const char* id, unsigned seg) {
  SessionInfo* si = (SessionInfo*)heap_caps_malloc(sizeof(SessionInfo), MALLOC_CAP_SPIRAM);
  if (!si) return err(r, "500 Internal Server Error", "mem");
  if (!session_info(id, si)) { heap_caps_free(si); return err(r, "404 Not Found", "id"); }
  if (!servable(*si)) { heap_caps_free(si); return err(r, "409 Conflict", "open"); }
  if (seg < 1 || seg > si->segs) { heap_caps_free(si); return err(r, "404 Not Found", "segment"); }
  uint32_t size = si->sizes[seg - 1], etag = si->etag;
  heap_caps_free(si);
  // If-Match: the client resumes only if the file is still the same
  char im[24] = {0};
  if (httpd_req_get_hdr_value_str(r, "If-Match", im, sizeof(im)) == ESP_OK) {
    char cur[12];
    snprintf(cur, sizeof(cur), "\"%08x\"", (unsigned)etag);
    if (strcmp(im, cur) != 0 && strcmp(im, cur + 1) != 0) return err(r, "412 Precondition Failed", "changed");
  }
  uint32_t from = 0, to = size ? size - 1 : 0;
  bool partial = false;
  char range[48] = {0};
  if (httpd_req_get_hdr_value_str(r, "Range", range, sizeof(range)) == ESP_OK && !strncmp(range, "bytes=", 6)) {
    char* end = nullptr;
    unsigned long a = strtoul(range + 6, &end, 10);
    if (end && *end == '-') {
      unsigned long b = end[1] ? strtoul(end + 1, nullptr, 10) : (unsigned long)to;
      if (a >= size || b < a) {
        char cr[40];
        snprintf(cr, sizeof(cr), "bytes */%u", (unsigned)size);
        httpd_resp_set_hdr(r, "Content-Range", cr);
        return err(r, "416 Range Not Satisfiable", "range");
      }
      from = a; to = b >= size ? size - 1 : b; partial = true;
    }
  }
  char p[128];
  seg_path(id, (uint16_t)seg, p, sizeof(p));
  FILE* f = fopen(p, "rb");
  if (!f) return err(r, "500 Internal Server Error", "io");
  if (fseek(f, (long)from, SEEK_SET) != 0) { fclose(f); return err(r, "500 Internal Server Error", "io"); }
  char cl[16], cr[64], et[12];
  uint32_t len = size ? to - from + 1 : 0;
  snprintf(cl, sizeof(cl), "%u", (unsigned)len);
  snprintf(et, sizeof(et), "\"%08x\"", (unsigned)etag);
  httpd_resp_set_status(r, partial ? "206 Partial Content" : "200 OK");
  httpd_resp_set_type(r, "application/octet-stream");
  httpd_resp_set_hdr(r, "Accept-Ranges", "bytes");
  httpd_resp_set_hdr(r, "ETag", et);
  if (partial) { snprintf(cr, sizeof(cr), "bytes %u-%u/%u", (unsigned)from, (unsigned)to, (unsigned)size); httpd_resp_set_hdr(r, "Content-Range", cr); }
  // Content-Length is set by the chunked API; it is also sent as X-Length for the client
  httpd_resp_set_hdr(r, "X-Length", cl);
  uint32_t left = len;
  esp_err_t rc = ESP_OK;
  while (left > 0) {
    if (s_stop_req || recording_now()) { rc = ESP_FAIL; break; }     // recording has priority
    size_t want = left > CHUNK ? CHUNK : left;
    size_t got = fread(s_buf, 1, want, f);
    if (got == 0) { rc = ESP_FAIL; break; }
    if (httpd_resp_send_chunk(r, (const char*)s_buf, got) != ESP_OK) { rc = ESP_FAIL; break; }
    left -= got;
    s_bytes += got;
    touch();
  }
  fclose(f);
  if (rc == ESP_OK) httpd_resp_send_chunk(r, nullptr, 0);
  return rc;
}

static esp_err_t h_trainings_sub(httpd_req_t* r) {
  if (!guard(r)) return ESP_OK;
  char id[24];
  const char* rest = parse_id(r->uri, id, sizeof(id));
  if (!valid_id(id)) return err(r, "400 Bad Request", "id");
  if (!*rest || !strcmp(rest, "/metadata")) return h_metadata(r, id);
  if (!strcmp(rest, "/sha256")) return h_sha(r, id);
  unsigned seg = 0;
  if (sscanf(rest, "/segments/%u", &seg) == 1) return h_segment(r, id, seg);
  return err(r, "404 Not Found", "path");
}

// POST /api/v1/sync/complete  body: id=<id>&sha256=<hex>&done=<0|1>
// Records the verified download (diagnostics) and, with done=1, turns the AP off when the response goes out.
// It does NOT modify or delete anything on the SD.
static esp_err_t h_complete(httpd_req_t* r) {
  if (!guard(r)) return ESP_OK;
  char body[200] = {0};
  int n = r->content_len < sizeof(body) - 1 ? httpd_req_recv(r, body, r->content_len) : -1;
  if (n < 0) return err(r, "400 Bad Request", "body");
  body[n] = 0;
  s_completes++;
  bool done = strstr(body, "done=1") != nullptr;
  send_json(r, "200 OK", done ? "{\"ok\":true,\"stopping\":true}" : "{\"ok\":true}");
  if (done) { s_stop_why = StopReason::DONE; s_stop_req = true; }
  return ESP_OK;
}

static httpd_handle_t start_http() {
  httpd_config_t c = HTTPD_DEFAULT_CONFIG();
  c.server_port = s_cred.port;
  c.max_open_sockets = 3;
  c.stack_size = 6144;
  c.task_priority = 3;                 // below storage/BLE/ESP-NOW
  c.core_id = 1;
  c.lru_purge_enable = true;
  c.recv_wait_timeout = 10;
  c.send_wait_timeout = 10;
  c.uri_match_fn = httpd_uri_match_wildcard;
  httpd_handle_t h = nullptr;
  if (httpd_start(&h, &c) != ESP_OK) return nullptr;
  static const httpd_uri_t u_status = {"/api/v1/status", HTTP_GET, h_status, nullptr};
  static const httpd_uri_t u_list = {"/api/v1/trainings", HTTP_GET, h_list, nullptr};
  static const httpd_uri_t u_sub = {"/api/v1/trainings/*", HTTP_GET, h_trainings_sub, nullptr};
  static const httpd_uri_t u_done = {"/api/v1/sync/complete", HTTP_POST, h_complete, nullptr};
  httpd_register_uri_handler(h, &u_status);
  httpd_register_uri_handler(h, &u_list);
  httpd_register_uri_handler(h, &u_sub);
  httpd_register_uri_handler(h, &u_done);
  return h;
}

// ------------------------------------------------------------------ AP
static void do_stop(StopReason why) {
  if (s_state == State::OFF) return;
  s_state = State::STOPPING;
  if (s_httpd) { httpd_stop(s_httpd); s_httpd = nullptr; }
  WiFi.softAPdisconnect(true);                         // back to STA (ESP-NOW)
  esp_wifi_set_channel(NOW_CHANNEL_DEFAULT, WIFI_SECOND_CHAN_NONE);
  memset(s_cred.token, 0, sizeof(s_cred.token));
  s_on_total += sys::ms() - s_on_since;
  s_last_stop = why;
  s_state = State::OFF;
  s_stop_req = false;
  bb::log(BbCode::SHUTDOWN, 0, 0x57, (uint32_t)why, "wifi off");
  Serial.printf("[AVO WIFI] off (%s), %u B served\n", stop_reason_text(why), (unsigned)s_bytes);
}

static StartResult do_start(Credentials* out) {
  if (recording_now()) return StartResult::RECORDING;
  int pct; bool vbus, sd;
  battery(&pct, &vbus, &sd);
  if (!sd) return StartResult::NO_SD;
  if (!vbus && pct >= 0 && pct < MIN_BATT_PCT) return StartResult::LOW_BATTERY;
  lock();
  if (s_state == State::READY || s_state == State::CLIENT) { touch(); if (out) *out = s_cred; unlock(); return StartResult::OK; }
  if (s_state != State::OFF) { unlock(); return StartResult::BUSY; }
  // rc2: Wi-Fi disabled after a reboot while starting the AP (see init) → never retry on its own
  uint32_t off = 0;
  if (sys::nvs_get_u32("wifi_off", &off) && off) { unlock(); return StartResult::RADIO_ERROR; }
  // rc2: enough internal memory for the AP + HTTP server (field 3.7.4-rc1: reboot when starting)
  size_t freeb = heap_caps_get_free_size(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
  size_t largest = heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
  Serial.printf("[AVO WIFI] start: internal=%u largest=%u\n", (unsigned)freeb, (unsigned)largest);
  if (freeb < MIN_INTERNAL_FREE || largest < MIN_INTERNAL_BLOCK) {
    bb::log(BbCode::SHUTDOWN, 1, 0x57, (uint32_t)freeb, "wifi: low internal RAM");
    unlock();
    return StartResult::RADIO_ERROR;
  }
  sys::nvs_set_u32("wifi_try", 1);       // breadcrumb: if we reboot before clearing it, the next boot disables Wi-Fi
  s_state = State::STARTING;
  const char* dev = sys::device_id_hex();
  snprintf(s_cred.ssid, sizeof(s_cred.ssid), "AVO_CHEST_%s", dev + strlen(dev) - 4);
  load_or_make_password(s_cred.password, sizeof(s_cred.password), false);
  uint8_t t[16];
  esp_fill_random(t, sizeof(t));
  hex(t, 16, s_cred.token);
  s_cred.channel = NOW_CHANNEL_DEFAULT;
  s_cred.port = 80;
  s_cred.idle_timeout_s = IDLE_MS / 1000;
  s_auth_fail = 0;
  WiFi.persistent(false);
  bool ok = WiFi.mode(WIFI_AP_STA) &&
            WiFi.softAPConfig(IPAddress(192, 168, 4, 1), IPAddress(192, 168, 4, 1), IPAddress(255, 255, 255, 0)) &&
            WiFi.softAP(s_cred.ssid, s_cred.password, s_cred.channel, 0, 1);
  if (ok) {
    esp_wifi_set_channel(NOW_CHANNEL_DEFAULT, WIFI_SECOND_CHAN_NONE);
    WiFi.softAPmacAddress(s_cred.bssid);
    snprintf(s_cred.ip, sizeof(s_cred.ip), "%s", WiFi.softAPIP().toString().c_str());
    s_httpd = start_http();
    ok = s_httpd != nullptr;
  }
  if (!ok) {
    sys::nvs_set_u32("wifi_try", 0);
    s_state = State::READY;   // so do_stop cleans everything
    do_stop(StopReason::ERROR);
    unlock();
    return StartResult::RADIO_ERROR;
  }
  sys::nvs_set_u32("wifi_try", 0);       // AP and server up without a reboot
  Serial.printf("[AVO WIFI] AP up: internal=%u largest=%u (cost %d B)\n",
                (unsigned)heap_caps_get_free_size(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT),
                (unsigned)heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT),
                (int)freeb - (int)heap_caps_get_free_size(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT));
  s_on_since = s_last_activity = sys::ms();
  s_client_left_at = 0;
  s_starts++;
  s_state = State::READY;
  if (out) *out = s_cred;
  unlock();
  bb::log(BbCode::SHUTDOWN, 0, 0x57, 0, "wifi on");
  Serial.printf("[AVO WIFI] AP %s ch%u on\n", s_cred.ssid, (unsigned)s_cred.channel);   // the password is never printed
  return StartResult::OK;
}

static SemaphoreHandle_t s_cmd = nullptr, s_done = nullptr, s_api = nullptr;
static TaskHandle_t s_worker = nullptr;
static void supervise(void*);
static StartResult s_res = StartResult::BUSY;
static Credentials s_res_cred = {};

StartResult start(Credentials* out) {
  if (!s_api || xSemaphoreTake(s_api, pdMS_TO_TICKS(100)) != pdTRUE) return StartResult::BUSY;
  xSemaphoreTake(s_done, 0);
  if (!s_worker) {
    // 3.7.5: the worker only exists while Wi-Fi is on (no RAM taken at boot)
    size_t lb = heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
    if (lb < WORKER_STACK + 1024 || xTaskCreatePinnedToCore(supervise, "wifisync", WORKER_STACK, nullptr, 2, &s_worker, 1) != pdPASS) {
      s_worker = nullptr;
      Serial.printf("[AVO WIFI] worker not created (largest internal=%u)\n", (unsigned)lb);
      xSemaphoreGive(s_api);
      return StartResult::RADIO_ERROR;
    }
  }
  xSemaphoreGive(s_cmd);
  StartResult r = StartResult::BUSY;
  if (xSemaphoreTake(s_done, pdMS_TO_TICKS(9000)) == pdTRUE) {
    r = s_res;
    if (r == StartResult::OK && out) *out = s_res_cred;
  }
  memset(&s_res_cred, 0, sizeof(s_res_cred));
  xSemaphoreGive(s_api);
  return r;
}

void stop(StopReason why) { lock(); do_stop(why); unlock(); }

bool regenerate_password() {
  lock();
  bool ok = s_state == State::OFF;
  if (ok) { char p[33]; load_or_make_password(p, sizeof(p), true); }
  unlock();
  return ok;
}

State state() { return s_state; }

bool set_enabled(bool on) { return sys::nvs_set_u32("wifi_off", on ? 0 : 1); }
bool enabled() { uint32_t off = 0; return !(sys::nvs_get_u32("wifi_off", &off) && off); }

void stats(Stats* o) {
  o->state = s_state; o->last_stop = s_last_stop; o->starts = s_starts; o->requests = s_requests;
  o->auth_failures = s_auth_fail; o->bytes_sent = s_bytes; o->completes = s_completes;
  o->on_ms_total = s_on_total + (s_state == State::OFF ? 0 : sys::ms() - s_on_since);
}

const char* stop_reason_text(StopReason r) {
  switch (r) {
    case StopReason::APP: return "app"; case StopReason::IDLE: return "idle"; case StopReason::NO_CLIENT: return "no client";
    case StopReason::MAX_TIME: return "max time"; case StopReason::RECORDING: return "recording"; case StopReason::LOW_BATTERY: return "low battery";
    case StopReason::CLIENT_LEFT: return "client left"; case StopReason::ERROR: return "error"; case StopReason::AUTH_FAIL: return "auth fail";
    case StopReason::DONE: return "done"; default: return "-";
  }
}

// Supervision: shutdown on inactivity/time/battery/recording. 1 s per loop, low priority.
static void supervise(void*) {
  for (;;) {
    if (xSemaphoreTake(s_cmd, pdMS_TO_TICKS(1000)) == pdTRUE) {
      s_res = do_start(&s_res_cred);
      xSemaphoreGive(s_done);
      continue;
    }
    if (s_state == State::OFF) {
      // AP off and no pending start → the task is deleted and returns its stack
      if (xSemaphoreTake(s_api, 0) == pdTRUE) {
        s_worker = nullptr;
        xSemaphoreGive(s_api);
        Serial.println("[AVO WIFI] worker finished");
        vTaskDelete(nullptr);
      }
      continue;
    }
    if (s_state != State::READY && s_state != State::CLIENT) continue;
    uint32_t now = sys::ms();
    StopReason why = StopReason::NONE;
    uint8_t clients = WiFi.softAPgetStationNum();
    if (clients > 0) { s_state = State::CLIENT; s_client_left_at = 0; }
    else if (s_state == State::CLIENT) { if (!s_client_left_at) s_client_left_at = now; }
    int pct; bool vbus, sd;
    battery(&pct, &vbus, &sd);
    if (s_stop_req) why = s_stop_why;
    else if (recording_now()) why = StopReason::RECORDING;
    else if (!vbus && pct >= 0 && pct < STOP_BATT_PCT) why = StopReason::LOW_BATTERY;
    else if (now - s_on_since > MAX_ON_MS) why = StopReason::MAX_TIME;
    else if (s_state == State::READY && now - s_on_since > NO_CLIENT_MS && s_requests == 0) why = StopReason::NO_CLIENT;
    else if (s_client_left_at && now - s_client_left_at > CLIENT_LEFT_MS) why = StopReason::CLIENT_LEFT;
    else if (now - s_last_activity > IDLE_MS) why = StopReason::IDLE;
    if (why != StopReason::NONE) {
      if (why == StopReason::DONE) vTaskDelay(pdMS_TO_TICKS(500));   // let the last response go out
      stop(why);
    }
  }
}

bool init() {
  uint32_t tried = 0;
  if (sys::nvs_get_u32("wifi_try", &tried) && tried) {
    // the previous boot rebooted while starting the AP: disable Wi-Fi (the app uses BLE) and record it
    sys::nvs_set_u32("wifi_off", 1);
    sys::nvs_set_u32("wifi_try", 0);
    bb::log(BbCode::SHUTDOWN, 2, 0x57, 0xDEAD, "wifi: reboot while starting AP, disabled");
    Serial.println("[AVO WIFI] previous AP start rebooted the watch: Wi-Fi disabled (WIFI_SYNC 5 re-enables)");
  }
  s_cmd = xSemaphoreCreateBinary();
  s_done = xSemaphoreCreateBinary();
  s_api = xSemaphoreCreateMutex();
  s_mx = xSemaphoreCreateMutex();
  s_buf = (uint8_t*)heap_caps_malloc(CHUNK, MALLOC_CAP_SPIRAM);
  return s_mx && s_buf && s_cmd && s_done && s_api;   // 3.7.5: no task at boot
}

}  // namespace wifisync
