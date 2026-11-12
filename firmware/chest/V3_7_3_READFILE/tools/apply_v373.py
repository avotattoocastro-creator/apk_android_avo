#!/usr/bin/env python3
"""V3.7.3 — READ_FILE / FILE_DATA transmit robustness, on top of the 3.7.2-rc1 tree (run from the tree root, after apply_v372.py).

The 3.5.4 guarantee (READ_FILE answers at most 2048 bytes, offset + CRC-32 per chunk) is present unchanged in 3.7.x;
this patch adds what was still missing in the TRANSMIT path, where a reply could disappear silently:
  1. FILE_DATA replies wait up to 2 s for room in the BLE send buffer (was 500 ms, then dropped without trace).
  2. READ_FILE length additionally capped to 16 notifications at the negotiated MTU (no change at MTU >= 160:
     still 2048 B; only shrinks the reply when the MTU is small). Android already advances by the bytes received.
  3. While a download is active (READ_FILE in the last 1.5 s) the 2 Hz telemetry notifications are paused so the
     file reply does not compete for the notification buffers ("download mode" on the watch side).
  4. Counters in DIAG: notify_fail, tx_msgs, file_reads, file_drop (reply could not be queued), msg_abort
     (notification failed in the middle of a message).
Protocol, message formats, BLE UUIDs, NTRIP/RTCM, storage, OTA, partitions and signing are NOT changed.
"""
from pathlib import Path

def patch(path, old, new, count=1):
    p = Path(path)
    s = p.read_text()
    assert s.count(old) == count, f"{path}: expected {count} match(es) for:\n{old}"
    p.write_text(s.replace(old, new))

B = "AVO_CHEST_V3_5_0/src/ble_service.cpp"
patch(B, "static volatile uint16_t s_mtu = 23;\n",
      "static volatile uint16_t s_mtu = 23;\n"
      "// V3.7.3 READ_FILE transmit diagnostics and download mode\n"
      "static volatile uint32_t s_last_file_ms = 0;\n"
      "static volatile uint32_t s_file_reads = 0, s_file_drop = 0, s_msg_abort = 0;\n")
patch(B, "        if (!fl || !notify_frag(c, frag, fl)) break;\n",
      "        if (!fl || !notify_frag(c, frag, fl)) { s_msg_abort = s_msg_abort + 1; break; }\n")
patch(B, "    if (s_connected && is_authorized() && now - last_tel >= 500) {\n",
      "    // V3.7.3: telemetry paused while a file download is active (frees notification buffers for FILE_DATA)\n"
      "    if (s_connected && is_authorized() && now - last_tel >= 500 && (uint32_t)(now - s_last_file_ms) > 1500) {\n")
patch(B, "  queue_msg(ch, t, r.msg_id, BF_RESPONSE | (status ? BF_ERROR : 0), status, d, n, 500);\n",
      "  if (!queue_msg(ch, t, r.msg_id, BF_RESPONSE | (status ? BF_ERROR : 0), status, d, n, ch == CH_FILE ? 2000 : 500))\n"
      "    s_file_drop = s_file_drop + 1;   // V3.7.3: never lose a reply without trace\n")
patch(B, "      else if (type == BleMsg::READ_FILE) { q.op = storage::FileOp::READ; ok = sid(r, q.session_id); q.segment = r.u16(); q.offset = r.u32(); q.length = r.u32(); }\n",
      "      else if (type == BleMsg::READ_FILE) {\n"
      "        q.op = storage::FileOp::READ; ok = sid(r, q.session_id); q.segment = r.u16(); q.offset = r.u32(); q.length = r.u32();\n"
      "        // V3.7.3: at most 16 notifications per reply at the current MTU (2048 B cap of 3.5.4 still applies in storage)\n"
      "        size_t att = s_mtu > 3 ? s_mtu - 3 : 20;\n"
      "        uint32_t cap = att > BLE_FRAG_OVERHEAD ? (uint32_t)(att - BLE_FRAG_OVERHEAD) * 16u : 64u;\n"
      "        if (cap < 64u) cap = 64u;\n"
      "        if (q.length > cap) q.length = cap;\n"
      "        s_last_file_ms = sys::ms(); s_file_reads = s_file_reads + 1;\n"
      "      }\n")
patch(B, "keys=%u auth_fail=%lu mtu=%u\",\n",
      "keys=%u auth_fail=%lu mtu=%u notify_fail=%lu tx_msgs=%lu file_reads=%lu file_drop=%lu msg_abort=%lu\",\n")
patch(B, "                         (unsigned long)s->ble.auth_fail, (unsigned)s_mtu);\n",
      "                         (unsigned long)s->ble.auth_fail, (unsigned)s_mtu, (unsigned long)s->ble.notify_fail,\n"
      "                         (unsigned long)s->ble.tx_msgs, (unsigned long)s_file_reads, (unsigned long)s_file_drop, (unsigned long)s_msg_abort);\n")
print("V3.7.3 READ_FILE transmit patch applied")
