#!/usr/bin/env python3
"""V3.5.8: incremental hardening on the installed V3.5.7 receiver."""
from pathlib import Path
p=Path("AVO_CHEST_V3_5_0/src")
core=Path("lib/avo_core/src")
def change(file,old,new):
 s=file.read_text()
 assert s.count(old)==1, f"unexpected V3.5.7 base: {file}: {old[:70]}"
 file.write_text(s.replace(old,new))
change(core/"avo_version.h",'"3.5.7"','"3.5.8"')
change(core/"avo_version.h","0x030507","0x030508")
change(p/"build_info.h",'"V3.5.7-SIGNED-OTA"','"V3.5.8-OTA-HARDENED"')
ota=p/"ota.cpp"
change(ota,'if(s_active||!manifest||!sig||ml<30||ml>2048||sl<64||sl>80)',
       'if(s_active||!manifest||!sig||ml<30||ml>2048||sl<64||sl>80)')
change(ota,'cJSON* size=cJSON_GetObjectItemCaseSensitive(j,"size");uint8_t sha[32];',
'''cJSON* size=cJSON_GetObjectItemCaseSensitive(j,"size");uint8_t sha[32];
 // Reject duplicate security-sensitive fields: cJSON_GetObjectItemCaseSensitive
 // alone returns the first occurrence and would silently ignore duplicates.
 const char* required[]={"schema","alg","kid","firmware","target","version","size","sha256"};
 bool unique=true;
 for(const char* key:required) {
   int matches=0;
   for(cJSON* field=j->child;field;field=field->next)
     if(field->string && strcmp(field->string,key)==0)matches++;
   if(matches!=1){unique=false;break;}
 }''')
change(ota,'bool ok=eq("schema","avo-ota-manifest-v1")',
       'bool ok=cJSON_IsObject(j)&&unique&&eq("schema","avo-ota-manifest-v1")')
change(ota,'size->valuedouble==(double)size->valueint&&newer(str("version"))',
       'size->valuedouble==(double)size->valueint&&newer(str("version"))')
print("V3.5.8 OTA hardening applied")
