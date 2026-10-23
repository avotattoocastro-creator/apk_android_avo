# AVO CHEST — Historical partition audit (received 2026-10-23)

Source: user-supplied `AVO-CHEST-HISTORICAL-PARTITION-AUDIT.zip`, containing `PARTITION_AUDIT.txt` and `SOURCE_INVENTORY.txt`.

**Provenance:** Historical V3.5.4 sources only. **NOT verified for V3.7.1-rc2 or for the connected watch.** Do not use these offsets for automatic flashing without reading and validating the target device's actual partition table and boot state.

Historical `AVO_CHEST_V3_5_0/partitions.csv`:

| Name | Type | Subtype | Offset | Size |
|---|---|---|---|---|
| nvs | data | nvs | 0x9000 | 0x5000 |
| otadata | data | ota | 0xE000 | 0x2000 |
| app0 | app | ota_0 | 0x10000 | 0x600000 |
| app1 | app | ota_1 | 0x610000 | 0x600000 |
| blackbox | data | 0x40 | 0xC10000 | 0x40000 |
| coredump | data | coredump | 0xC50000 | 0x10000 |

Historical build configuration: `espressif:esp32:esp32s3:FlashSize=16M,PSRAM=opi,PartitionScheme=custom,CDCOnBoot=cdc,USBMode=hwcdc,FlashMode=qio,CPUFreq=240`. Source notes GD25Q256 32 MB physical flash but only 16 MB mapped by this build setting.

## Mandatory write prerequisites

1. Confirm ROM download mode with valid decoded SLIP SYNC response and chip identification (not just a black display).
2. Read the connected device's flash partition table; verify MD5/checksum if present, alignment, overlaps, size and app OTA slots.
3. Determine current boot slot and choose an **inactive** slot; preserve active image, NVS, blackbox, coredump, bootloader, partition table and SD.
4. Validate selected ESP32-S3 application image, chip compatibility, image size, security configuration (secure boot / flash encryption), power and USB continuity.
5. Understand OTA selection: writing an inactive app image alone does not necessarily switch the boot partition. Explicitly implement and validate a safe otadata transition or use an approved bootloader-based recovery path, with rollback.
6. Implement verified flash writes, bounded retries, progress, final read-back/hash verification and an explicit user confirmation.
7. If any precondition is missing, **keep flash writes disabled**. No hard-coded `0x10000` or `0x610000` as a default write target.

The currently tested 14-byte response `C0 01 08 04 00 07 07 12 20 00 00 00 00 C0` is consistent with ROM SYNC but not sufficient alone to authorize writing.
