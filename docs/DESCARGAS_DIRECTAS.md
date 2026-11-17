# Descargas directas (release fija `descargas`)

Cada archivo tiene un **enlace que no cambia** y siempre baja la última versión publicada:

```
https://github.com/avotattoocastro-creator/apk_android_avo/releases/download/descargas/<ARCHIVO>
```

A diferencia de los artefactos de Actions, no caducan y se descargan sin iniciar sesión (mientras el repositorio sea
público; si se privatiza, GitHub pedirá iniciar sesión).

**PROTOTIPO** = placas de desarrollo sin PCB propia (Waveshare, Heltec, XIAO). **BETA** = PCB propia. Las apps no
llevan etiqueta (regla del usuario, 17/11/2026).

| Archivo | Qué es | De dónde sale |
|---|---|---|
| `AVO_PECHO_PROTOTIPO_FW.zip` | Firmware del pecho | `AVO-CHEST-VX-Y-Z…` de mayor versión en `develop` (sin PREVIEW, RC, USB ni NOT-FOR-OTA) |
| `AVO_ESPALDA_PROTOTIPO_FW.zip` | Firmware de la espalda Heltec | `AVO-BACK-V3-…-HELTEC` (nunca la V4) |
| `AVO_CINCHA_PROTOTIPO_FW.zip` | Cincha XIAO + BNO085 | `AVO-GIRTH-V0-4-x-ESP32C6` |
| `AVO_CINCHA_PROTOTIPO_ECG_FW.zip` | Cincha XIAO + ECG MAX30003 | `AVO-GIRTH-V0-5-x-ESP32C6` |
| `AVO_CINCHA_BETA_FW.zip` | Cincha PCB REV D | `AVO-GIRTH-V0-6-x-ESP32C6` |
| `AVO_ESPALDA_BETA_V4_FW.zip`, `AVO_CASCO_BETA_FW.zip`, `AVO_DOCK_BETA_FW.zip` | Firmware de las BETA | Cuando haya artefacto vigente |
| `AVO_ANDROID.apk` · `AVO_TARJETAS.apk` | Apps Android | `AVO-Performance-Horse-V…-APK` de `develop` |
| `AVO_UPDATE.apk` | AVO Update | `AVO-Update-APK` |
| `AVO_WINDOWS.zip` | Windows V2 PRO x64 | `AVO-Windows-V2-PRO-x64` |
| `CAD_<PIEZA>_PROTOTIPO_*.zip` · `CAD_<PIEZA>_BETA_*.zip` | STEP, STL, 3MF, DXF y PDF de cada pieza | Carpeta del repositorio (ver `descargas.json`) |
| `VERSIONES.txt` · `manifiesto.json` | Versión, rama, commit y SHA-256 de cada archivo | Generados |

Los nombres antiguos sin etiqueta (`AVO_PECHO_FW.zip`, `CAD_CINCHA_REV5.zip`…) se retiran de la release (`retirar`).

**iOS / iPad:** solo por TestFlight. El `.ipa` no se publica nunca; el enlace público se pega en `ios.testflight_publico`.

## Cómo funciona

- Workflow `.github/workflows/publicar-descargas.yml` → `scripts/descargas/publicar.py`. **No compila nada ni modifica
  los workflows de compilación**: solo recoge sus artefactos.
- Se lanza con cada push a `develop/avo-performance-horse` y **espera a que terminen las compilaciones de ese commit**.
  Si este fichero está también en la rama por defecto del repositorio, además cada 6 h y con botón manual.
- Solo vuelve a subir lo que ha cambiado (id del artefacto o hash de la carpeta CAD).
- Si una entrada no encuentra nada, avisa y **conserva** el archivo anterior. Nunca borra descargas.
- Rechaza artefactos con `.jks`, `.keystore`, `.p12`, `.pfx`, `.p8`, `.pem`, `.key`, `.mobileprovision`, `.env` o `.ipa`.
- Rechaza un pecho con `-rc`/`-usb` en el nombre del binario (la OTA firmada no lo aceptaría) y una espalda 4.0.0.
- Lo que no sale de `develop` aparece marcado «⚠️ fuera de develop» en la release.
- El resumen de cada ejecución lista todos los artefactos disponibles, para ajustar los filtros de `descargas.json`.

**Estar en la release significa COMPILADO EN CI, no VERIFICADO en hardware real.**

## Pendiente

1. **CAD del pecho REV D y de la espalda V2.2H Rev E.5:** no están en el repositorio (se entregaron como ZIP en el
   chat). Subirlos a `hardware/chest/REV_D/` y `hardware/back/V2_2H_REV_E5/` y aparecerán solos.
2. **Cincha 0.4.x:** `build-girth-v040.yml` no se lanza con push a `develop`; el último artefacto (0.4.3, de
   `feature/avo-wifi-sync`) caduca el 30/12/2026. Ya copiado en la release no caduca, pero para versiones nuevas hay que
   añadir `develop` a ese workflow (cambio de CI pendiente de confirmar).
3. Casco V5 y DOCK: el CAD sale de sus ramas (`feature/back-v5-casco`, `claude/dock-cargador-v1`, PR #45) hasta que
   se integren; su firmware, cuando exista workflow.
4. Para tener el botón manual y la programación: poner `develop/avo-performance-horse` como rama por defecto del
   repositorio (`main` es histórica) o copiar este workflow a `main`.
