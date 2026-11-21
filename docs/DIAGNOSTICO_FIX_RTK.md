# Diagnóstico «¿por qué no hay RTK FIX?» (21/11/2026)

Decisión del usuario (21/11 00:47): «añade todas las lecturas necesarias, hasta en la apk, hasta que consigamos averiguar
por qué no llega el FIX; una vez solucionado simplificamos datos en el apk». Es **temporal**: cuando se encuentre la causa
se recorta la tarjeta de la app (los campos del firmware pueden quedarse).

## Cadena
Espalda **3.15.0** → `BackStatus v4` (ESP-NOW) → pecho **3.7.11** → texto `DIAG_GET` → Android **2.16-fixdiag-dev1**
(Inicio › tarjeta «¿Por qué no hay RTK FIX? (diagnóstico)», cada 5 s con el reloj conectado).

## BackStatus v4 (130 B = v3 de 108 B + 22 B, little-endian)
| Campo | Tipo | Origen | Desconocido |
|---|---|---|---|
| `rf_ant_status` | u8 | UBX-MON-RF bloque L1 `antStatus` (0 inicio, 1 desconocido, 2 OK, 3 corto, 4 abierta) | 255 |
| `rf_ant_power` | u8 | `antPower` (0 apagada, 1 encendida, 2 desconocida) | 255 |
| `rf_jam_state` | u8 | `flags` b0-1 L1 (0 desconocido, 1 OK, 2 aviso, 3 crítico) | 255 |
| `rf_jam_l1`, `rf_jam_l2` | u8 ×2 | `jamInd` (0-255) | 255 |
| `rf_agc_l1`, `rf_agc_l2` | u8 ×2 | `agcCnt` en % de 8191 | 255 |
| `rf_noise_l1`, `rf_noise_l2` | u16 ×2 | `noisePerMS` | 65535 |
| `rf_age_s` | u8 | segundos desde el último MON-RF (sondeo cada 5 s) | 255 |
| `rtcm_types` | u16 | familias RTCM en las correcciones (ventana 30-60 s) | — |
| `rtcm_used_types` | u16 | familias usadas por el receptor (UBX-RXM-RTCM `msgUsed = 2`) | — |
| `base_id` | u16 | estación de referencia (1005/1006) | 65535 |
| `base_dist_dam` | u16 | distancia base ↔ espalda en decámetros (1005/1006 + NAV-PVT 3D) | 65535 |
| `dyn_model` | u8 | `CFG-NAVSPG-DYNMODEL` enviado | 255 |
| `gnss_set` | u8 | constelaciones: b0 GPS, b1 GLONASS, b2 Galileo, b3 BeiDou | — |

Bits de familias (`RtcmTypeBit`, iguales en C++ y Kotlin): b0 1005/1006 · b1 GPS MSM · b2 GLONASS MSM · b3 Galileo MSM ·
b4 BeiDou MSM · b5 QZSS MSM · b6 SBAS MSM · b7 1230 · b8 1001-1004 · b9 1009-1012 · b10 1007/1008/1033 · b11 efemérides ·
b12 MSM7 · b13 MSM4 · b14 MSM5/6 · b15 MSM1-3.

Vector compartido (los 22 bytes añadidos): `02 01 01 0C 22 37 42 50 00 5A 00 03 1F 10 0F 10 D3 07 D2 04 07 0F`
(antena OK, alimentada, interferencia OK, jam 12/34, AGC 55/66 %, ruido 80/90, hace 3 s, tipos 0x101F, usados 0x100F,
base 2003 a 12,34 km, modelo 7 aire < 2 g, GPS+GLO+GAL+BDS). Prueba: `firmware/back/V3_8_0/test/test_espnow.cpp`
(`fixdiag.*`); Kotlin: `core/src/test/.../GnssFixDiagTest.kt`.

## Claves nuevas en DIAG_GET (pecho 3.7.11, solo con espalda v4)
`rf_ant rf_pwr rf_jam rf_jam1 rf_jam2 rf_agc1 rf_agc2 rf_noise1 rf_noise2 rf_age rtcm_types rtcm_used base_id base_dam dyn
gnss_set sv sv_used sig sig_used sig_cr sig_corr sig_l2 sig_l2_used cno cno_min cno_max fix_lost ttff_fix fixed_s float_s`.
El texto pasa a un búfer estático de 2048 B.

## Compatibilidad
| Espalda \ Pecho | 3.7.10 | 3.7.11 |
|---|---|---|
| 3.14.7 (v3) | como hasta ahora | como hasta ahora; la app avisa de que faltan datos |
| 3.15.0 (v4) | v3 leído, el resto se ignora (sin corrupción) | diagnóstico completo |

## Qué mira la app (y qué significa)
- **Antena abierta / en corto / interferencia crítica** → hardware o entorno RF.
- **C/N₀ media < 35 dBHz** o **0 señales con fase de portadora** → cielo tapado, antena tapada o sin plano de masa.
- **Sin segunda banda (L2/E5b/B2)** → antena de una banda o dañada.
- **Sin 1005/1006**, **solo mensajes antiguos**, **solo MSM1-3** o **ninguna corrección usada** → punto de montaje NTRIP.
- **Base a más de 35 km** (aviso > 20 km) → elegir otro punto de montaje o una red VRS.

## Estado
IMPLEMENTADO · pruebas de host de la espalda (59 casos) y del pecho (estáticas + gnss_quality_host) en local · CI: ver PR ·
**NO VERIFICADO** en hardware.
