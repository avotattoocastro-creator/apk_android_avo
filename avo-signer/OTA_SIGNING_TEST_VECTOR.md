# AVO OTA signing interoperability — verified test vector

Date: 2026-10-22
Source: user-provided AVO_CHEST_SIGNED_OTA.zip, tested independently using Python cryptography.
This is a test vector, NOT an authorization to install firmware.

- schema: avo-ota-manifest-v1
- target: AVO_CHEST_WAVESHARE_ESP32S3
- version: 3.5.6
- kid: AVO_OTA_RECOVERABLE_P256_V1
- alg: ES256
- firmware bytes: 1344240
- firmware SHA-256: 1ca98b2dfe571de1355a9a8aba6f97b5cfa15972baeab4a18ea6b4f4de4c7b89
- Public SPKI DER base64: MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEKIADU/bALRoURAxF4ElSbDZkbDRxDxl8cP6YIm0xsmWG3fallhy29ynUhh/oZAOiasc7DAucXj7FrUr8LskriA==

Observed:
1. Original manifest.sig verifies with SHA256withECDSA and the public SPKI above.
2. SHA-256 of firmware.bin matches manifest.sha256.
3. Altering the signed manifest bytes rejects ECDSA verification (InvalidSignature).
4. Flipping one byte of firmware.bin produces a different SHA-256. The signature over the *unchanged manifest* still verifies: this proves the receiver MUST check BOTH signature AND firmware digest.

Receiver acceptance rules (must be implemented and tested on hardware):
- Reject missing/extra/duplicate ZIP members, oversized ZIP and firmware, and malformed JSON.
- Require exact schema, algorithm, target matching actual hardware, trusted pinned public key and known kid.
- Verify signature against the exact manifest.json bytes; do not reserialize JSON before verifying.
- Verify SHA-256 and byte count of firmware.bin against the authenticated manifest.
- Check minimum/allowed version to prevent rollback; define a signed rotation/revocation policy.
- Never begin flashing until all validation succeeds.
- Treat any verification or parsing error as rejection.
- Do not trust public keys delivered inside the OTA package itself.
- Signature encoding is ASN.1 DER ECDSA, not IEEE P1363 raw r||s.

Remaining external tests:
- Restore encrypted .avo-key on another Android device and verify its public SPKI is identical.
- Verify wrong password, corrupt backup, and changed firmware are rejected in the actual Android UI.
- Prove chest OTA bootloader/updater enforces the rules before writing flash.
- Verify OTA recovery on power loss and signed production APK distribution.
