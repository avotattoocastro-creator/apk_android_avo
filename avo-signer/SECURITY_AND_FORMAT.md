# AVO Signer Android V0.1 — Prototype

Standalone Android application to sign AVO Chest firmware offline using an Android Keystore EC P-256 private key.

## Usage
1. Install debug APK from the GitHub Actions artifact, after build validation.
2. Enable Android PIN/password or biometrics.
3. Generate a signing key **once**. The app refuses to overwrite an existing key.
4. Export public key JSON and store it safely. **Pin its SPKI bytes** in the OTA verifier; never trust a key merely because it is supplied with a ZIP.
5. Check hardware protection with the diagnostic button. Hardware protection depends on the Android device.
6. Select a trusted AVO Chest firmware BIN, enter its version, authenticate, sign and save the OTA ZIP.

## Package
- `firmware.bin` — firmware bytes
- `manifest.json` — exact UTF-8 JSON bytes signed with SHA256withECDSA
- `manifest.sig` — ASN.1 DER-encoded ECDSA signature

Manifest fields: schema, target, version, firmware, size, sha256, alg, kid. The verifier must verify the **exact manifest bytes**, compare SHA-256 and length of the BIN, enforce target/version/anti-rollback, and check the signature against a **pre-pinned** public key. Reject duplicate ZIP entries, path traversal, unexpected sizes and unknown formats.

## Security boundaries
- This is an experimental debug APK, **not yet a production OTA trust chain**.
- Android Keystore private keys cannot be exported. If the phone is lost/reset, the key is lost. Plan a separate pre-authorized recovery key before enforcing signatures.
- Authentication is device credential based (PIN/password/pattern, may vary by device), not a guaranteed Face ID/Touch ID-equivalent biometric-only flow.
- Android app verification is not sufficient to prevent bypass if the watch accepts unsigned OTA. Add signature enforcement to watch firmware before enabling mandatory signed updates.
- No firmware is uploaded to any external server by this app.
- APK built with a CI debug key is for testing; release distribution requires controlled Android app signing.
