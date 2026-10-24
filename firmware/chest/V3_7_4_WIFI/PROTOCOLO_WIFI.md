# CHEST V3.7.4-wifi-rc1 — Training download over Wi-Fi

Base: 3.7.3-rc1 (RC2 + UI 3.7.2 + READ_FILE 3.7.3). The RAW format, recording, ESP-NOW, OTA and partitions are not touched. **BIN marked UNVERIFIED: not validated on hardware and not suitable for OTA until it is checked physically.**

## Architecture

```
Android ──BLE (authenticated)──► CHEST: WIFI_SYNC(start) → SSID, password, token, BSSID
Android ──Wi-Fi (WifiNetworkSpecifier, no Internet)──► SoftAP AVO_CHEST_XXXX ch.1 ──HTTP /api/v1──► microSD (read only)
CHEST ◄──ESP-NOW ch.1──► BACK (keeps working: same channel, AP_STA mode)
```

- **One radio, one channel.** The ESP32-S3 has a single 2.4 GHz radio. The AP goes on the ESP-NOW channel (`NOW_CHANNEL_DEFAULT` = 1) in AP_STA mode, so the back link does not change channel. When the AP is turned off the channel is restored. BLE coexists through the IDF software coexistence; some throughput is lost while there is Wi-Fi traffic.
- **Recording takes priority.** The AP does not start if there is a recording (`STATE_CONFLICT`). If a session starts, every HTTP request answers 409 and the supervisor turns the AP off within ≤ 1 s. A transfer in progress is cut between 16 KB blocks.

## BLE: `WIFI_SYNC` = 0x64 (authenticated only)

Capability: bit 11 (`0x800`) of `GET_INFO.caps`. The app chooses the transport by capability, never by version number.

| action | Response |
|---|---|
| 1 start | `OK`: u8 version=1, str33 ssid, str33 password, str33 token, str16 ip, 6 B bssid, u8 channel, u16 port, u16 idle_s. Errors: `STATE_CONFLICT` recording · `NOT_ALLOWED` battery < 15 % without charger · `BUSY` · `IO_ERROR` (payload 3 = no microSD, 4 = radio) |
| 2 stop | `OK` |
| 3 status | u8 state, u8 last_stop, u32 starts, requests, bytes_sent, on_ms, completes, auth_failures |
| 4 regenerate password | `OK` / `STATE_CONFLICT` if the AP is on |

## Security

- WPA2 with a random 20-character per-device password (≈115 bits), generated on first use and kept in NVS (`wifipw`). It is only sent over authenticated BLE and is never printed in logs.
- 128-bit **session token**, new on every start and gone when the AP turns off (a watch reboot invalidates it). `Authorization: Bearer <token>` is required on every request and compared in constant time. After 5 failures the AP turns off.
- One client only (`max_conn = 1`). Read-only server: it never writes, deletes or rewrites anything on the SD.
- Paths built only from validated identifiers (`S[A-Za-z0-9_-]{1,22}`) and segment numbers. There is no generic file access.

## HTTP API (port 80)

| Method / route | Description |
|---|---|
| `GET /api/v1/status` | fw, device, sd, battery, idle timeout, bytes served, raw_format |
| `GET /api/v1/trainings` | list: id, state, `ready` (closed), segments, size, start_rtc_ms, active_ms, etag |
| `GET /api/v1/trainings/{id}` or `/metadata` | metadata + sizes per segment + etag |
| `GET /api/v1/trainings/{id}/sha256` | SHA-256 of the concatenated segments (same calculation as BLE `FILE_SHA256`) |
| `GET /api/v1/trainings/{id}/segments/{n}` | segment `P00n.avr`; `Range: bytes=a-[b]` → 206 + `Content-Range`; `If-Match: "etag"` → 412 if it changed |
| `POST /api/v1/sync/complete` | `id=…&sha256=…&done=0/1`: record; `done=1` turns the AP off after answering |

- **Never served:** sessions in `OPEN` state (recording or interrupted without recovery) return 409.
- **Note on the brief:** a training is several `P00n.avr` files. It is downloaded per segment, which keeps the same local format as BLE and lets either transport continue the other one's partial download.

## Automatic shutdown

| Condition | Time |
|---|---|
| No client connects | 60 s |
| No requests | 45 s |
| Client disconnected | 20 s |
| Maximum time on | 15 min |
| Battery < 10 % without charger | immediate |
| Recording starts | ≤ 1 s |
| End confirmed (`done=1`) | 0.5 s |

Diagnostics: `WIFI_SYNC(3)` and the black box (code `SHUTDOWN` arg 0x57 "wifi on/off").

## Android (2.3-wifi-dev1)

- **`AvoWifiSyncManager` + `core/wifi`** (`WifiSyncCoordinator`, `WifiDownloader`).
  - States: IDLE → WIFI_STARTING → CONNECTING → DOWNLOADING → VERIFYING → COMPLETED → CLEANUP, plus WAITING, PAUSED, CANCELLED and ERROR.
  - Only one pass at a time.
- **Connection.** `WifiNetworkSpecifier` (SSID + WPA2 + BSSID) without `NET_CAPABILITY_INTERNET`, and HTTP with `Network.openConnection`, so the phone's default network is not changed.
  - **The first time, Android shows its mandatory dialog.** After it is approved, the system remembers the approval for that SSID/BSSID and later connections are automatic.
  - This cannot be avoided without root, so it is not promised.
- **Download.** 64 KB blocks written straight to the `P00n.avr` segments (same files as BLE). Progress counts bytes already written (`fsync`).
  - Resuming checks the etag.
  - SHA-256 is checked against the watch and the training is saved only if it matches.
  - The original on the watch is never deleted.
- **Triggers:**
  - end of training (RECORDING → idle);
  - reconnection to the watch;
  - «Descargar todo» (now works even with automatic download off);
  - opening Entrenamientos when something is pending.
- **BLE fallback** when the firmware has no b11, Android does not connect, or the command is not supported. NTRIP to the watch is paused during the download.

## Tests

- **Automated (CI):**
  - `core/wifi/WifiSyncTest`: 24 cases covering scenarios 1–20 from the brief plus RAW/BLE compatibility, credentials and JSON. They use a simulated watch with the 3.7.4 HTTP semantics.
  - Firmware: `tests/test_wifi_v374.py` (19 static checks) + compilation of the BIN.
- **Physical (pending — none has been run):**
  1. Firmware: flash by USB with AVO Update (not by automatic OTA). Check the boot with `wifisync OK` in the serial port.
  2. Telemetry from the back while the AP is on: no gaps in ESP-NOW during a 5 MB download.
  3. First download: the Android dialog appears **only once**; the second training connects without a dialog.
  4. Real speed (expected > 300 kB/s) and phone/watch battery during the download.
  5. Cut Wi-Fi halfway (move away from the watch): it resumes from the confirmed byte; the SHA matches.
  6. Start a recording halfway: the download stops in ≤ 1 s, the recording is not affected, and it is downloaded when the recording ends.
  7. 15 min with no activity: the AP turns off (it disappears from the list of networks).
  8. NTRIP/RTK goes back to FIX after the download.
  9. Android 10, 12, 14 and 15/16 (Xiaomi): connection behaviour and dialog.
