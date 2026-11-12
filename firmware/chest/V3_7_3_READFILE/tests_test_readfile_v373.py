#!/usr/bin/env python3
"""Static checks of the V3.7.3 READ_FILE fix on the assembled tree (run from the tree root)."""
from pathlib import Path
s = Path("AVO_CHEST_V3_5_0/src/storage.cpp").read_text()
b = Path("AVO_CHEST_V3_5_0/src/ble_service.cpp").read_text()
# 3.5.4 guarantees still in place (not modified by 3.7.3)
assert "uint32_t len = r.length > 2048 ? 2048 : r.length;" in s, "READ_FILE 2048 B cap missing"
assert "put_u32(buf + 8, crc32(buf + 12, got));" in s and "put_u32(buf, r.offset);" in s, "offset/CRC header missing"
# 3.7.3 additions
assert "ch == CH_FILE ? 2000 : 500" in b, "FILE_DATA queue wait"
assert "s_file_drop = s_file_drop + 1" in b and "s_msg_abort = s_msg_abort + 1" in b, "drop counters"
assert "(uint32_t)(now - s_last_file_ms) > 1500" in b, "telemetry pause during downloads"
assert "if (q.length > cap) q.length = cap;" in b, "MTU-aware cap"
assert "file_reads=%lu file_drop=%lu msg_abort=%lu" in b, "DIAG counters"
# untouched areas
for k in ["OTA_AUTH", "RTCM", "AVO_FILE_TX_UUID"]:
    assert k in b
print("V3.7.3 READ_FILE: comprobaciones estáticas correctas")
