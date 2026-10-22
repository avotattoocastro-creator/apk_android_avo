#!/usr/bin/env python3
"""AVO CHEST V3.5.9: versioned, fail-closed signed OTA receiver."""
from pathlib import Path
p=Path("AVO_CHEST_V3_5_0/src")
core=Path("lib/avo_core/src")
def replace(path,old,new):
    s=path.read_text()
    assert s.count(old)==1, f"Unexpected V3.5.8 base in {path}: {old[:70]}"
    path.write_text(s.replace(old,new))
replace(core/"avo_version.h",'"3.5.8"','"3.5.9"')
replace(core/"avo_version.h","0x030508","0x030509")
replace(p/"build_info.h",'"V3.5.8-OTA-HARDENED"','"V3.5.9-OTA-DIAGNOSTICS"')
ota=p/"ota.cpp"
replace(ota,'if(rc!=0){snprintf(err,el,"signature invalid");return false;}',
            'if(rc!=0){snprintf(err,el,"signature invalid");return false;}')
replace(ota,'if(!ok)snprintf(err,el,"manifest invalid");',
            'if(!ok)snprintf(err,el,"manifest invalid: target/version/hash/size/kid");')
print("V3.5.9 patch applied")
