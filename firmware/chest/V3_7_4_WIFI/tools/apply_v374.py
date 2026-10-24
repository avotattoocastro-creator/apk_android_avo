#!/usr/bin/env python3
"""AVO CHEST V3.7.4 — training download over Wi-Fi.

Applied on top of the 3.7.3-rc1 tree (RC2 + UI 3.7.2 + READ_FILE 3.7.3). Run from the root of the tree.
Changes (only additions; the RAW format, recording, ESP-NOW and OTA are not touched):
  * lib/avo_core/src/avo_ble_proto.h: new message WIFI_SYNC = 0x64.
  * ble_service.cpp: capability b11 (Wi-Fi sync) in GET_INFO and the WIFI_SYNC handler
    (1 start → credentials, 2 stop, 3 status, 4 regenerate password).
  * app_main.cpp: wifisync::init() after BLE.
  * src/wifi_sync.{h,cpp}: copied by the workflow from firmware/chest/V3_7_4_WIFI/src.
"""
from pathlib import Path
import sys


def patch(path, old, new, count=1):
    p = Path(path)
    s = p.read_text()
    if s.count(old) != count:
        sys.exit(f"apply_v374: anchor not found ({s.count(old)}x) in {path}: {old[:60]!r}")
    p.write_text(s.replace(old, new))


SRC = "AVO_CHEST_V3_5_0/src"

patch("lib/avo_core/src/avo_ble_proto.h",
      "  BACK_LINK = 0x63,",
      "  WIFI_SYNC = 0x64,   // V3.7.4: u8 action (1 start AP -> credentials, 2 stop, 3 status, 4 regenerate password)\n  BACK_LINK = 0x63,")

patch(f"{SRC}/ble_service.cpp", '#include "services.h"\n', '#include "services.h"\n#include "wifi_sync.h"\n')

patch(f"{SRC}/ble_service.cpp",
      "      w.u32(0x000007FF);",
      "      // V3.7.4: b11 Wi-Fi download (WIFI_SYNC + HTTP /api/v1)\n      w.u32(0x00000FFF);")

patch(f"{SRC}/ble_service.cpp", "    case BleMsg::TIME_SET: {", r'''    case BleMsg::WIFI_SYNC: {
      uint8_t action = r.u8();
      if (!r.ok() || action < 1 || action > 4) { respond(type, id, BleStatus::BAD_FORMAT); break; }
      if (action == 1) {
        wifisync::Credentials c;
        wifisync::StartResult sr = wifisync::start(&c);
        if (sr != wifisync::StartResult::OK) {
          BleStatus st = sr == wifisync::StartResult::RECORDING ? BleStatus::STATE_CONFLICT
                       : sr == wifisync::StartResult::LOW_BATTERY ? BleStatus::NOT_ALLOWED
                       : sr == wifisync::StartResult::BUSY ? BleStatus::BUSY : BleStatus::IO_ERROR;
          uint8_t why = (uint8_t)sr;
          respond(type, id, st, &why, 1);
          break;
        }
        uint8_t b[180];
        ByteWriter w(b, sizeof(b));
        w.u8(1);                                   // credentials format version
        w.str(c.ssid, 33); w.str(c.password, 33); w.str(c.token, 33); w.str(c.ip, 16);
        w.bytes(c.bssid, 6); w.u8(c.channel); w.u16(c.port); w.u16((uint16_t)c.idle_timeout_s);
        respond(type, id, BleStatus::OK, b, w.size());
        memset(b, 0, sizeof(b));
        memset(&c, 0, sizeof(c));
      } else if (action == 2) {
        wifisync::stop(wifisync::StopReason::APP);
        respond(type, id, BleStatus::OK);
      } else if (action == 3) {
        wifisync::Stats s;
        wifisync::stats(&s);
        uint8_t b[40];
        ByteWriter w(b, sizeof(b));
        w.u8((uint8_t)s.state); w.u8((uint8_t)s.last_stop); w.u32(s.starts); w.u32(s.requests);
        w.u32(s.bytes_sent); w.u32(s.on_ms_total); w.u32(s.completes); w.u32(s.auth_failures);
        respond(type, id, BleStatus::OK, b, w.size());
      } else {
        respond(type, id, wifisync::regenerate_password() ? BleStatus::OK : BleStatus::STATE_CONFLICT);
      }
      break;
    }
    case BleMsg::TIME_SET: {''')

patch(f"{SRC}/app_main.cpp", '#include "services.h"\n', '#include "services.h"\n#include "wifi_sync.h"\n')
patch(f"{SRC}/app_main.cpp", '  boot_log("ble", ble_ok);\n',
      '  boot_log("ble", ble_ok);\n  bool wifi_ok = wifisync::init();   // V3.7.4: Wi-Fi download (AP off until the app asks for it)\n  boot_log("wifisync", wifi_ok);\n')

print("apply_v374: OK")
