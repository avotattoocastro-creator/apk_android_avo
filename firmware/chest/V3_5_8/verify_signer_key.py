#!/usr/bin/env python3
"""Validate AVO Signer public-key export against the CHEST V3.5.7 pinned key.

Usage:
 python3 verify_signer_key.py public-key-export.json

This tool never needs a private key. Do not install V3.5.8 until it passes.
"""
import base64, json, sys
PINNED_SPKI = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEKIADU/bALRoURAxF4ElSbDZkbDRxDxl8cP6YIm0xsmWG3fallhy29ynUhh/oZAOiasc7DAucXj7FrUr8LskriA=="
PINNED_KID = "AVO_OTA_RECOVERABLE_P256_V1"

def verify(payload):
    kid=payload.get("kid")
    key=payload.get("public_key_spki_base64",payload.get("spki_der_base64"))
    if payload.get("alg")!="ES256":
        raise ValueError("Signer algorithm must be ES256")
    if kid!=PINNED_KID:
        raise ValueError(f"Key ID mismatch: signer={kid!r}, chest={PINNED_KID!r}")
    if not isinstance(key,str) or base64.b64decode(key,validate=True)!=base64.b64decode(PINNED_SPKI):
        raise ValueError("PUBLIC KEY MISMATCH: signer cannot authorize OTA on installed CHEST V3.5.7")
    return True

if __name__=="__main__":
    if len(sys.argv)!=2:sys.exit("Usage: verify_signer_key.py exported-public-key.json")
    try:
        verify(json.load(open(sys.argv[1],encoding="utf-8")))
    except (ValueError,KeyError) as e:
        sys.exit("BLOCK OTA: "+str(e))
    print("OK: AVO Signer public key matches installed CHEST V3.5.7")
