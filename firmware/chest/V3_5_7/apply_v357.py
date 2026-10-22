#!/usr/bin/env python3
"""Apply CHEST V3.5.7 signed OTA receiver patch after V3.5.5 and V3.5.6."""
from pathlib import Path
p=Path("AVO_CHEST_V3_5_0/src")
core=Path("lib/avo_core/src")
def replace(path,old,new):
 s=path.read_text()
 assert s.count(old)==1, f"source mismatch: {path} {old[:45]}"
 path.write_text(s.replace(old,new))
replace(core/"avo_ble_proto.h","OTA_ABORT = 0x53,","OTA_ABORT = 0x53, OTA_AUTH = 0x54,")
replace(p/"services.h","namespace ota {\nbool begin","namespace ota {\nbool authenticate(const uint8_t*, size_t, const uint8_t*, size_t, char*, size_t);\nbool begin")
replace(p/"ble_service.cpp","    case BleMsg::OTA_BEGIN: {",'''    case BleMsg::OTA_AUTH: {
      uint16_t ml=r.u16(), sl=r.u16();
      if(!r.ok() || ml<30 || ml>2048 || sl<64 || sl>80 || r.remaining()!=(size_t)ml+sl) {
        respond(type,id,BleStatus::BAD_FORMAT); break;
      }
      const uint8_t* manifest=r.cur(); char err[64]={0};
      bool ok=ota::authenticate(manifest,ml,manifest+ml,sl,err,sizeof(err));
      respond(type,id,ok?BleStatus::OK:BleStatus::VERIFY_FAILED,(const uint8_t*)err,strlen(err));
      break;
    }
    case BleMsg::OTA_BEGIN: {''')
v=core/"avo_version.h"
s=v.read_text()
import re
s,n=re.subn(r'(#define AVO_FW_VERSION ")[^"]+(")',r'\g<1>3.5.7\2',s);assert n==1
s,n=re.subn(r'(#define AVO_FW_VERSION_NUM )0x[0-9A-Fa-f]+',r'\g<1>0x030507',s);assert n==1
v.write_text(s)
replace(p/"build_info.h",'"V3.5.6-USB-STATE-RESTORE"','"V3.5.7-SIGNED-OTA"')
ota=p/"ota.cpp"
replace(ota,"#include <mbedtls/sha256.h>","#include <mbedtls/sha256.h>\n#include <mbedtls/pk.h>\n#include <mbedtls/base64.h>\n#include <cJSON.h>")
replace(ota,"static bool s_active = false;",'''static bool s_active = false;
static bool s_authorized=false;
static uint32_t s_auth_size=0;
static uint8_t s_auth_sha[32];
static const char kPublicSpki[]="MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEKIADU/bALRoURAxF4ElSbDZkbDRxDxl8cP6YIm0xsmWG3fallhy29ynUhh/oZAOiasc7DAucXj7FrUr8LskriA==";
static void clear_auth() { s_authorized=false; s_auth_size=0; memset(s_auth_sha,0,32); }
static bool sha_hex(const char* s,uint8_t out[32]) {
 if(!s||strlen(s)!=64)return false;
 for(int i=0;i<32;i++) {
  auto nib=[](char c)->int { if(c>='0'&&c<='9')return c-'0'; if(c>='a'&&c<='f')return c-'a'+10; if(c>='A'&&c<='F')return c-'A'+10; return -1; };
  int a=nib(s[2*i]),b=nib(s[2*i+1]);if(a<0||b<0)return false;out[i]=(a<<4)|b;
 }return true;
}
static bool newer(const char* version) {
 unsigned a,b,c,x,y,z; char extra;
 if(!version || sscanf(version,"%u.%u.%u%c",&a,&b,&c,&extra)!=3)return false;
 if(sscanf(AVO_FW_VERSION,"%u.%u.%u%c",&x,&y,&z,&extra)!=3)return false;
 return a>x || (a==x&&(b>y||(b==y&&c>z)));
}
bool authenticate(const uint8_t* manifest,size_t ml,const uint8_t* sig,size_t sl,char* err,size_t el) {
 clear_auth();
 if(s_active||!manifest||!sig||ml<30||ml>2048||sl<64||sl>80){snprintf(err,el,"bad auth");return false;}
 uint8_t der[128],digest[32];size_t derlen=0;
 int rc=mbedtls_base64_decode(der,sizeof(der),&derlen,(const unsigned char*)kPublicSpki,strlen(kPublicSpki));
 mbedtls_pk_context pk;mbedtls_pk_init(&pk);
 if(rc==0)rc=mbedtls_pk_parse_public_key(&pk,der,derlen);
 if(rc==0)rc=mbedtls_sha256(manifest,ml,digest,0);
 if(rc==0)rc=mbedtls_pk_verify(&pk,MBEDTLS_MD_SHA256,digest,32,sig,sl);
 mbedtls_pk_free(&pk);
 if(rc!=0){snprintf(err,el,"signature invalid");return false;}
 if(memchr(manifest,0,ml)){snprintf(err,el,"NUL JSON");return false;}
 cJSON* j=cJSON_ParseWithLength((const char*)manifest,ml);
 if(!j){snprintf(err,el,"bad JSON");return false;}
 auto str=[&](const char* k)->const char* {cJSON* v=cJSON_GetObjectItemCaseSensitive(j,k);return cJSON_IsString(v)?v->valuestring:nullptr;};
 auto eq=[&](const char* k,const char* val)->bool {const char* x=str(k);return x&&strcmp(x,val)==0;};
 cJSON* size=cJSON_GetObjectItemCaseSensitive(j,"size");uint8_t sha[32];
 bool ok=eq("schema","avo-ota-manifest-v1")&&eq("alg","ES256")&&
 eq("kid","AVO_OTA_RECOVERABLE_P256_V1")&&eq("firmware","firmware.bin")&&
 eq("target","AVO_CHEST_WAVESHARE_ESP32S3")&&
 cJSON_IsNumber(size)&&size->valuedouble>=1024&&size->valuedouble<=6291456&&
 size->valuedouble==(double)size->valueint&&newer(str("version"))&&sha_hex(str("sha256"),sha);
 if(ok){s_auth_size=(uint32_t)size->valueint;memcpy(s_auth_sha,sha,32);s_authorized=true;}
 cJSON_Delete(j);
 if(!ok)snprintf(err,el,"manifest invalid");
 return ok;
}
''')
replace(ota,'  if (s_active) { snprintf(err, el, "ota already active"); return false; }','''  if (s_active) { snprintf(err, el, "ota already active"); return false; }
  if (!s_authorized || size!=s_auth_size || memcmp(sha,s_auth_sha,32)!=0) {
    snprintf(err,el,"signed manifest required");return false;
  }''')
replace(ota,"  s_size = size;","  clear_auth();\n  s_size = size;")
replace(ota,"void abort() {","void abort() {\n  clear_auth();")
print("V3.5.7 signed OTA receiver applied")
