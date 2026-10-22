#!/usr/bin/env python3
"""AVO CHEST V3.6.0 base: version upgrade after verified V3.5.9 patch chain.
The seven-band UI must be implemented and reviewed before distribution.
"""
from pathlib import Path
p=Path("AVO_CHEST_V3_5_0/src")
core=Path("lib/avo_core/src")
def replace(file,old,new):
    source=file.read_text()
    assert source.count(old)==1, f"Unexpected V3.5.9 source in {file}: {old}"
    file.write_text(source.replace(old,new))
replace(core/"avo_version.h",'"3.5.9"','"3.6.0"')
replace(core/"avo_version.h","0x030509","0x030600")
replace(p/"build_info.h",'"V3.5.9-OTA-DIAGNOSTICS"','"V3.6.0-UI-INTEGRATION"')
# Fail closed: never publish this version as a release until seven-band UI,
# signed OTA packaging, and hardware acceptance are verified.
print("V3.6.0 version base applied; UI implementation pending")
