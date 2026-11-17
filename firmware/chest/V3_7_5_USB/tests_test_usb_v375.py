#!/usr/bin/env python3
"""CHEST V3.7.5-usb1 — USB download to the PC (protocol AVO1).

Run from the prepared source tree (CI copies this file to tests/test_usb_v375.py and the host harness to
tests/usb_host.cpp). It:
  1. checks the patch is in place (init after Wi-Fi, poll in the loop task, nothing else touched);
  2. builds the REAL usb_sync.cpp + avo_core for the host and drives it like the Windows app does: list, compare,
     download in 4 KB blocks, CRC-32 per block, SHA-256 per training, plus the refusal cases;
  3. compares the answers with the transcript used by the Windows self-tests
     (windows/AVO.Windows.SelfTest/usb_transcript.json, path in AVO_USB_TRANSCRIPT). With AVO_USB_TRANSCRIPT_WRITE=1
     it rewrites that file instead.
"""
import base64
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

SRC = Path("AVO_CHEST_V3_5_0/src")
LIB = Path("lib/avo_core/src")
HERE = Path(__file__).resolve().parent
fails = []


def check(cond, msg):
    print(("OK   " if cond else "FAIL ") + msg)
    if not cond:
        fails.append(msg)


# ---------------------------------------------------------------- 1. static checks
app = (SRC / "app_main.cpp").read_text()
usb = (SRC / "usb_sync.cpp").read_text()
check('#include "usb_sync.h"' in app, "app_main includes usb_sync.h")
check(app.find("usbsync::init()") > app.find("wifisync::init()") > 0, "usbsync::init after wifisync::init")
check("usbsync::poll();\n  vTaskDelay(pdMS_TO_TICKS(10));" in app, "loop task polls USB every 10 ms")
check("xTaskCreate" not in usb, "no new task (runs in the loop task)")
check("MALLOC_CAP_SPIRAM" in usb, "buffers in PSRAM")
for bad in ("remove(", "unlink(", "rename(", "\"wb\"", "\"ab\"", "\"r+", "session_meta_write", "nvs_set"):
    check(bad not in usb, f"read-only: no {bad}")
check("SessionFileState::OPEN" in usb, "OPEN sessions are never served")
check(usb.count("port::recording()") >= 4, "every command refuses while recording")
check("port::write(s_out, n)" in usb and usb.count("port::write(") == 1, "one write() per answer line")
ui = (SRC / "ui.cpp").read_text()
check("if (usbsync::host_present()) render_pc(*snap, now);   // V3.7.5-usb1\n            else render_charging(*snap, now);" in ui,
      "PC screen only with a USB host; a charger keeps the 3.7.2 charging screen")
check('#include "ui_pc_draw.h"' in (SRC / "ui_dash.cpp").read_text(), "PC screen drawn with the dashboard fonts (ui_dash.cpp)")
check("Serial.isPlugged()" in usb, "PC detected by USB start-of-frame (a charger sends none)")

# ---------------------------------------------------------------- 2. host build
gxx = shutil.which("g++")
if not gxx:
    sys.exit("g++ not found")
work = Path(tempfile.mkdtemp(prefix="avo_usb_"))
harness = HERE / "usb_host.cpp"
if not harness.is_file():
    harness = HERE.parent / "host" / "usb_host.cpp"
exe = work / "usb_host"
cmd = [gxx, "-std=c++17", "-O1", "-Wall", "-Wextra", "-Werror", "-Wno-unused-parameter", "-DAVO_HOST_TEST",
       f"-I{SRC}", f"-I{LIB}", str(SRC / "usb_sync.cpp"), str(harness),
       str(LIB / "avo_raw.cpp"), str(LIB / "avo_crc.cpp"), str(LIB / "avo_sha256.cpp"), str(LIB / "avo_ring.cpp"),
       "-o", str(exe)]
r = subprocess.run(cmd, capture_output=True, text=True)
check(r.returncode == 0, "host build of usb_sync.cpp (-Wall -Werror)")
if r.returncode:
    print(r.stderr[:4000])
    sys.exit(1)

root = work / "AVO"
SESSIONS = [  # id, state, start_rtc_ms, segment sizes
    ("S20261025_101500", 2, 1792923300000, [5000, 300]),   # CLOSED, two segments
    ("S20261026_090000", 1, 1793005200000, [2048]),        # OPEN (interrupted): never served
    ("S20261027_180000", 4, 1793124000000, [4096]),        # UPLOADED: still served (read-only)
]
for sid, st, t0, sizes in SESSIONS:
    rr = subprocess.run([str(exe), "mksession", str(root), sid, str(st), str(t0)] + [str(s) for s in sizes])
    check(rr.returncode == 0, f"mksession {sid}")
(root / "notasession").mkdir()
(root / "S..evil").mkdir()


def card_state():
    return sorted((str(f.relative_to(root)), f.stat().st_size, f.stat().st_mtime_ns) for f in root.rglob("*"))


before = card_state()


class Watch:
    def __init__(self):
        self.p = subprocess.Popen([str(exe), "serve", str(root)], stdin=subprocess.PIPE, stdout=subprocess.PIPE)

    def raw(self, line):
        self.p.stdin.write(line.encode() + b"\n")
        self.p.stdin.flush()

    def ask(self, line, until=None):
        """Sends a command; returns (raw stdout bytes, list of #AVO1 lines) up to the final answer line."""
        self.raw(line)
        raw, lines = b"", []
        while True:
            l = self.p.stdout.readline()
            if not l:
                raise RuntimeError("harness closed")
            raw += l
            s = l.decode().rstrip("\n")
            if not s.startswith("#AVO1 "):
                continue
            lines.append(s[6:])
            if until is None or lines[-1].startswith(until) or lines[-1].startswith("ERR"):
                return raw, lines

    def close(self):
        self.p.stdin.close()
        self.p.wait(5)


w = Watch()
transcript = []


def ask(cmd, until=None, record=True):
    raw, lines = w.ask(cmd, until)
    if record:
        transcript.append({"cmd": cmd, "out": raw.decode()})
    return lines


# ---------------------------------------------------------------- 3. happy path (what the PC app does)
hello = ask("AVO1 HELLO")[-1]
check(hello.startswith("HELLO "), "HELLO answers")
h = json.loads(hello[6:])
check(h["api"] == 1 and h["name"] == "AVO-CHEST" and h["fw"] == "3.7.5-usb1" and h["max_read"] == 4096 and not h["recording"],
      "HELLO: api, name, fw, max_read, not recording")

lst = ask("AVO1 LIST", "END")
check(lst[-1] == "END 3", f"LIST ends with END 3 (got {lst[-1]})")
items = {json.loads(x[2:])["id"]: json.loads(x[2:]) for x in lst if x.startswith("T ")}
check(set(items) == {s[0] for s in SESSIONS}, "LIST: only valid S... folders")
check(items["S20261026_090000"]["ready"] is False, "OPEN session listed as not ready")
check(items["S20261025_101500"]["sizes"] == [5000, 300] and items["S20261025_101500"]["size"] == 5300, "LIST: sizes per segment")

for sid, st, t0, sizes in SESSIONS:
    it = items[sid]
    if not it["ready"]:
        continue
    sha = json.loads(ask(f"AVO1 SHA {sid}")[-1][4:])
    data = b""
    for seg, size in enumerate(sizes, 1):
        off = 0
        while off < size:
            want = min(4096, size - off)   # same block sizes as the Windows client (ChestSync.Download)
            d = ask(f"AVO1 READ {sid} {seg} {off} {want} {it['etag']}")[-1].split(" ")
            check(d[0] == "DATA" and int(d[1]) == seg and int(d[2]) == off, f"{sid} seg {seg} off {off}: DATA header")
            chunk = base64.b64decode(d[5])
            check(len(chunk) == int(d[3]) and zlib.crc32(chunk) == int(d[4], 16), f"{sid} seg {seg} off {off}: length + CRC-32")
            data += chunk
            off += len(chunk)
    on_disk = b"".join((root / sid / f"P{i:03d}.avr").read_bytes() for i in range(1, len(sizes) + 1))
    check(data == on_disk, f"{sid}: downloaded bytes equal the microSD")
    check(hashlib.sha256(data).hexdigest() == sha["sha256"] and sha["size"] == len(data), f"{sid}: SHA-256 of the watch matches")

# PC screen: the app reports its progress; the watch keeps it for the "CONECTADO AL PC" screen.
check(ask("AVO1 PROGRESS 2 1 2 50 0")[-1] == "OK PROGRESS", "PROGRESS accepted")
w.raw("!PC")
st = w.p.stdout.readline().decode().split()
check(st[:6] == ["PCSTATUS", "2", "50", "1", "2", "0"], f"PC screen state: downloading 1 of 2, 50 % ({st})")

# ---------------------------------------------------------------- 4. refusals and robustness (not in the transcript)
e = items["S20261025_101500"]["etag"]
check(ask("AVO1 READ S20261025_101500 1 0 4096 deadbeef", record=False)[-1] == "ERR READ changed", "wrong etag → changed")
check(ask("AVO1 READ S20261025_101500 1 5000 10 " + e, record=False)[-1] == "ERR READ range", "offset past the end → range")
check(ask("AVO1 READ S20261025_101500 3 0 10 " + e, record=False)[-1] == "ERR READ segment", "missing segment → segment")
check(ask("AVO1 READ S20261026_090000 1 0 10 " + items["S20261026_090000"]["etag"], record=False)[-1] == "ERR READ open",
      "OPEN session → open")
check(ask("AVO1 SHA S20261026_090000", record=False)[-1] == "ERR SHA open", "SHA of OPEN session → open")
check(ask("AVO1 SHA ../../etc", record=False)[-1] == "ERR SHA id", "path traversal → id")
check(ask("AVO1 SHA S..evil", record=False)[-1] == "ERR SHA id", "dots in id → id")
d = ask("AVO1 READ S20261025_101500 2 100 99999 " + e, record=False)[-1].split(" ")
check(d[0] == "DATA" and int(d[3]) == 200, "READ is clamped to the end of the segment")
check(ask("AVO1 FORMAT", record=False)[-1] == "ERR FORMAT cmd", "unknown command → cmd")
check(ask("AVO1 PROGRESS 9 0 0 0 0", record=False)[-1] == "ERR PROGRESS cmd", "PROGRESS with an unknown phase → cmd")
check(ask("AVO1 PROGRESS 2 1 2 101 0", record=False)[-1] == "ERR PROGRESS cmd", "PROGRESS over 100 % → cmd")
w.raw("hello this is not for the watch")
w.raw("AVO1 " + "X" * 400)          # too long: dropped
w.raw("!LOG")
check(ask("AVO1 HELLO", record=False)[-1].startswith("HELLO "), "noise, an over-long line and log lines do not break it")
w.raw("!REC 1")
check(json.loads(ask("AVO1 HELLO", record=False)[-1][6:])["recording"] is True, "HELLO reports recording")
check(ask("AVO1 LIST", "END", record=False)[-1] == "ERR LIST recording", "LIST refused while recording")
check(ask(f"AVO1 READ S20261025_101500 1 0 10 {e}", record=False)[-1] == "ERR READ recording", "READ refused while recording")
w.raw("!REC 0")
check(ask("AVO1 LIST", "END", record=False)[-1] == "END 3", "LIST works again after the recording")
w.close()
check(card_state() == before, "nothing created, changed or deleted on the card")

# ---------------------------------------------------------------- 5. transcript shared with the Windows self-tests
tp = os.environ.get("AVO_USB_TRANSCRIPT")
doc = {"comment": "Generated by firmware/chest/V3_7_5_USB/tests_test_usb_v375.py from the real usb_sync.cpp. Do not edit.",
       "exchanges": transcript}
if tp and os.environ.get("AVO_USB_TRANSCRIPT_WRITE") == "1":
    Path(tp).write_text(json.dumps(doc, indent=1) + "\n")
    print(f"transcript written: {tp} ({len(transcript)} exchanges)")
elif tp:
    old = json.loads(Path(tp).read_text())
    norm = lambda ex: [(x["cmd"], sorted(x["out"].splitlines())) for x in ex]   # readdir order is not fixed
    check(norm(old["exchanges"]) == norm(transcript), "Windows transcript is identical to the firmware answers")
shutil.rmtree(work, ignore_errors=True)

print(f"\nUSB 3.7.5-usb1: {'ALL OK' if not fails else str(len(fails)) + ' FAILED'}")
sys.exit(1 if fails else 0)
