#!/usr/bin/env python3
"""AVO CHEST V3.6.1: version increment; fail closed until UI verified."""
from pathlib import Path
p=Path("AVO_CHEST_V3_5_0/src")
core=Path("lib/avo_core/src")
def change(file,old,new):
    s=file.read_text()
    assert s.count(old)==1, f"Unexpected source in {file}: {old}"
    file.write_text(s.replace(old,new))
change(core/"avo_version.h",'"3.6.0"','"3.6.1"')
change(core/"avo_version.h","0x030600","0x030601")
change(p/"build_info.h",'"V3.6.0-UI-INTEGRATION"','"V3.6.1-SEVEN-BAND-PENDING"')
raise SystemExit("V3.6.1 BLOCKED: seven-band UI not implemented or tested; do not publish unsigned/unfinished OTA")
