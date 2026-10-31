# AVO CHEST 3.7.6 GNSS QUALITY — informe de compatibilidad

Rama `feature/chest-v3-7-6-gnss-quality`, creada desde `feature/chest-usb-pc-sync` (3.7.5-usb1).
Integración prevista: `develop/avo-performance-horse`. **No se ha tocado `main`, el firmware de la espalda ni Android.**

Estado: **IMPLEMENTADO · COMPILADO EN CI · NO VERIFICADO en el reloj.**

## 1. Por qué Android muestra «Necesita espalda 3.9.0 y pecho 3.7.6 o posteriores.»

La tarjeta «Calidad GNSS» de Android (`HomeScreen.kt`, `GnssQualityCard`) muestra ese texto si
`telemetry.v3 == null` o si `q_flags & 1 == 0`.

Lo que pasa con la espalda 3.13.11 y el pecho 3.7.5-usb1:

| Tramo | Qué ocurre | Evidencia |
|---|---|---|
| Espalda 3.13.11 → pecho | Envía `STATUS` v3 de **108 B** cada segundo con `v3 = true`. | `avo_back_core.cpp`: `s.v3 = true` y `send_status()` cada 1000 ms en `fix/back-3-13-11-usb-pololu-off`. |
| Pecho 3.7.5-usb1 (decodificación) | Su `avo_payloads.cpp` es el de la 3.7.0-rc2: solo conoce v1 y v2. Lee 82 B e ignora los 26 B de calidad. | `decode_status` del ZIP RC2 no tiene bloque v3. |
| Pecho 3.7.5-usb1 → Android (BLE) | Envía `TELEMETRY` v2 de **83 B**. | `ble_service.cpp`: `uint8_t b[TELEMETRY_V2_LEN + 8]`. |
| Android | Con 83 B, `Telemetry.decode` deja `v3 = null` y aparece el aviso. | `Messages.kt`: `if (p.size < V3_LEN) return withV2`. |

**Causa raíz.** La 3.7.6-rc1 (`build-chest-v376.yml`, rama `feature/avo-wifi-sync`) ya reenviaba la calidad, pero se
compiló sobre la 3.7.5-rc5. La 3.7.5-usb1 se compiló después sobre la rc5, sin el parche 3.7.6. Por eso el reloj tiene
la descarga USB pero no la calidad GNSS.

La espalda está bien: transmite todo lo que Android necesita, así que no falta ningún dato ni hace falta ampliarla.

## 2. Qué hace la 3.7.6 GNSS QUALITY

Cadena de compilación (`.github/workflows/build-chest-v376-gnss-quality.yml`):

```
3.7.0-rc2 (ZIP) → 3.7.2 UI → 3.7.3 READFILE → 3.7.4 Wi-Fi → 3.7.5 RAM → 3.7.5-usb1
  → avo_payloads.{h,cpp} de firmware/back/V3_8_0   (idénticos byte a byte a los de la espalda 3.13.11)
  → V3_7_6_GNSS/tools/apply_v376.py                (TELEMETRY v3, ya existente)
  → V3_7_6_GNSS_QUALITY/tools/apply_v376_gq.py     (nuevo: frescura)
  → versión "3.7.6" / 0x030706
```

1. **Decodificación de `BackStatus` v3.** Se usa el mismo archivo que la espalda, sin escribir ninguna estructura nueva.
   - El cambio frente al del pecho es solo aditivo: el bloque v3 va después de los 82 B de v2.
   - Solo se acepta v3 si llegan los 26 B completos (`s->v3 = r.ok()`).
   - Con una espalda < 3.9.0, `v3 = false`.
2. **`TELEMETRY` v3 por BLE: 116 B.** Los primeros 83 B (v2) no cambian, así que una app que solo conozca v2 sigue
   funcionando. El formato es el de `apply_v376.py`, el mismo que Android ya decodifica (`Telemetry.V3_LEN = 116`).
   No hay UUID, mensaje ni canal BLE nuevo: es la misma notificación `TELEMETRY` por `CH_TELEM`.
3. **Frescura (nuevo).** El pecho conservaba para siempre el último `BackStatus`. Con la rc1, si la espalda se apagaba,
   Android habría seguido mostrando la última calidad como actual. Ahora:
   - `q_flags = 0` si el último `BackStatus` tiene más de 5 s. Android vuelve entonces a «sin datos de calidad».
   - `quality_age_s` suma la antigüedad del enlace, con saturación en 254; el valor 255 sigue significando «nunca».
4. **Versión `3.7.6`, sin sufijo** (motivo en el apartado 5).

### Formato `TELEMETRY` v3 (bytes 83‥115, little-endian)

| Off | Tipo | Campo | Off | Tipo | Campo |
|---|---|---|---|---|---|
| 83 | u8 | `q_flags` (b0 espalda v3 fresca, b1 resumen NAV-SIG) | 96 | u8 | `quality_age_s` (255 = nunca) |
| 84 | u8 | `sv_tracked` | 97 | u8 | `quality_mon` (0 no pedido, 1 activo, 2 rechazado, 3 omitido) |
| 85 | u8 | `sv_used` | 98 | u16 | `fix_lost` |
| 86 | u8 | `sig_tracked` | 100 | u16 | `ttff_fix_s` (0xFFFF = aún no) |
| 87 | u8 | `sig_used` | 102 | u32 | `fixed_ms` |
| 88 | u8 | `sig_cr_used` | 106 | u32 | `float_ms` |
| 89 | u8 | `sig_corr` | 110 | u32 | `sacc_mm_s` (NAV-PVT actual) |
| 90 | u8 | `sig_l2` | 114 | u16 | `pdop_e2` (NAV-PVT actual) |
| 91 | u8 | `sig_l2_used` | | | |
| 92 | u8 | `sig_weak` | | | |
| 93‥95 | u8 ×3 | `cno_mean`, `cno_min`, `cno_max` | | | |

## 3. Archivos

**Nuevos** en `feature/chest-v3-7-6-gnss-quality`:
- `firmware/chest/V3_7_6_GNSS_QUALITY/tools/apply_v376_gq.py`: parche de frescura en `ble_service.cpp`.
- `firmware/chest/V3_7_6_GNSS_QUALITY/tests_test_gnss_quality_v376.py`: comprobaciones estáticas.
- `firmware/chest/V3_7_6_GNSS_QUALITY/host/gnss_quality_host.cpp`: prueba en PC con los codificadores reales.
- `firmware/chest/V3_7_6_GNSS_QUALITY/INFORME_COMPATIBILIDAD.md`: este informe.
- `.github/workflows/build-chest-v376-gnss-quality.yml`.
- Entrada en `docs/REGISTRO_DE_CAMBIOS.md`.

**Archivos del árbol compilado que cambian frente a la 3.7.5-usb1.** El CI lo comprueba con `diff -rq`, y falla si cambia
cualquier otro:
- `lib/avo_core/src/avo_payloads.{h,cpp}`: copia de la espalda (bloque v3).
- `lib/avo_core/src/avo_ble_proto.{h,cpp}`: campos y codificación v3.
- `AVO_CHEST_V3_5_0/src/ble_service.cpp`: relleno v3 con frescura y búfer de 116 B.
- `lib/avo_core/src/avo_version.h`: `3.7.6` / `0x030706`.

**Sin cambios** (el CI pasa antes y después las mismas pruebas de la usb1):
- grabación RAW y SD;
- sesiones y geocercas;
- UART/ESP-NOW (tramas, CRC, tamaños), NTRIP/RTCM y GNSS;
- pantallas, incluidas la de carga USB y «CONECTADO AL PC»;
- batería y apagado;
- OTA con ES256, clave fijada, anti-rollback y marcador de imagen;
- particiones;
- Wi-Fi y USB AVO1 (la transcripción de Windows es idéntica).

## 4. Pruebas

| Prueba | Resultado | Nivel |
|---|---|---|
| Todas las pruebas Python de la usb1 (UI, READFILE, Wi-Fi, RAM, USB con transcripción de Windows), `verify_source.py`, `verify_ota_interlock.py`, antes y después del parche | OK (local y CI) | CI |
| Solo cambian los archivos permitidos | OK | CI |
| `test_gnss_v376.py` y `test_gnss_quality_v376.py` | OK | CI |
| Host: el codificador de la espalda produce `BackStatus` v3 (108 B) y el pecho lo decodifica; v2 da `v3 = false`; una cola truncada no se acepta | OK | CI |
| Host: la `TELEMETRY` v3 del pecho es **idéntica byte a byte** al vector de `FirmwareVectorsTest.telemetryV3DecodesFirmwareEncoding` de Android | OK | CI |
| Compilación ESP32-S3 (arduino-esp32 3.3.12), imagen válida, cadena `3.7.6` y marcador OTA presentes | ver run en el registro | CI |
| Funcionamiento en el reloj con la espalda 3.13.11 | **NO VERIFICADO** | Pendiente de hardware |

## 5. Instalación

**Procedimiento:** AVO Update por USB, el mismo con el que se instaló la 3.7.5-usb1. Pasos:
1. Descargar el artefacto `AVO-CHEST-V3-7-6-GNSS-QUALITY-UNVERIFIED` y comprobar el SHA-256 con `SHA256SUMS.txt`.
2. En AVO Update, *SELECCIONAR FIRMWARE BIN* → `AVO_CHEST_V3_7_6_GNSS_QUALITY.bin`.
3. *LEER RELOJ*, y después *INSTALAR FIRMWARE POR USB*.
4. Es una imagen de aplicación: no toca el bootloader, la tabla de particiones, NVS ni la tarjeta.

**OTA firmada: no sirve desde la 3.7.5-usb1, y no se ha forzado.** Hallazgo de la auditoría:
- `ota.cpp`, `version_cmp()`, exige que la versión instalada tenga la forma exacta `X.Y.Z`
  (`sscanf("%u.%u.%u%c") == 3`).
- Con una versión con sufijo (`3.7.5-usb1`, `3.7.0-rc2`…) la comparación devuelve −2. El reloj rechaza **cualquier**
  paquete firmado con «target/version/hash invalid».
- Comprobado en el PC con el código real: `3.7.6` frente a `3.7.5-usb1` da −2; frente a `3.7.5` da 1.
- No se ha cambiado la verificación. Esta versión se llama **`3.7.6` sin sufijo**, así que la próxima actualización
  firmada (`3.7.7` o posterior) desde ella sí pasará la comprobación.
- Si en el futuro se quiere la OTA firmada, el `firmware.bin` se firma con AVO Signer (clave `AVO_OTA_RECOVERABLE_P256_V1`,
  versión `3.7.6`), según `avo-signer/SECURITY_AND_FORMAT.md`.

**Vuelta atrás:** reinstalar `AVO_CHEST_V3_7_5_USB1_UNVERIFIED.bin` (run 41076422328) con AVO Update.

## 6. Verificación en Android (con hardware; aún no hecha)

APK: la actual, sin cambios. Ya decodifica la v3 (`Messages.kt`, `HomeScreen.kt`).

1. **Arranque.** Instalar la 3.7.6 y abrir el monitor serie de AVO Update. Deben aparecer `AVO-CHEST 3.7.6 ready`,
   `usbsync OK` y la línea `[AVO MEM] ready`. Anotar esa línea y compararla con la de la usb1.
2. **Versión.** En Android → Dispositivos, «Pecho» debe decir `3.7.6`.
3. **Calidad GNSS con la espalda 3.13.11 encendida y al aire libre.** En 2–3 s, la tarjeta «Calidad GNSS» debe cambiar.
   - Primero aparece «Esperando el resumen de señales del receptor».
   - Después, el diagnóstico con satélites, señales, L2 y C/N0.
   - Anotar los valores. Que sean plausibles: C/N0 entre 20 y 50 dB-Hz y `sv_used ≤ sv_tracked`.
4. **Si se queda en «Esperando el resumen de señales».** El pecho funciona: la espalda envía v3, pero sin resumen NAV-SIG
   (`quality_mon` 2 = el ZED lo rechaza, 3 = UART lenta). Es el problema conocido del ZED, no del pecho.
5. **Frescura.** Apagar la espalda. En ≤ 6 s la tarjeta debe volver a «Necesita espalda 3.9.0 y pecho 3.7.6».
   Al encenderla, debe recuperarse sola.
6. **Sin regresiones.** Comprobar:
   - una sesión completa con grabación, geocerca y descarga por BLE o Wi-Fi;
   - RTK con NTRIP (RTCM usado > 0);
   - la descarga a AVO Windows por USB y la pantalla «CONECTADO AL PC»;
   - con cargador, la pantalla de carga de siempre;
   - el apagado.
7. Registrar el resultado en `docs/REGISTRO_DE_CAMBIOS.md` como **PROBADO FÍSICAMENTE**, con versión, dispositivo y
   capturas o log. Hasta entonces, la 3.7.6 sigue **NO VERIFICADA**.

## 7. Android

**No necesita cambios:** el formato v3 ya está implementado y probado con el mismo vector.

Mejora opcional, no hecha: cuando el pecho envía v3 con `q_flags = 0` porque la espalda está apagada o es antigua,
el texto «Necesita espalda 3.9.0 y pecho 3.7.6» no es exacto. Se podría distinguir «sin datos recientes de la espalda».
Si se pide, se haría en una rama Android aparte.
