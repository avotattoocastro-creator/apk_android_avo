# AVO BACK V3.8.0 — espalda (Heltec Wireless Stick Lite V3 + u-blox ZED-F9P) · máxima precisión RTK

**Estado:** compilado en CI, pruebas de ordenador correctas (23 casos, 159 comprobaciones con ZED simulado).
**NO VERIFICADO** en la espalda real.

## De dónde parte
Copia de la espalda del 23-10-2026 (app «AVO Update», MAC AC:A7:04:06:CD:24): **AVO BACK 3.5.0**,
`AVO_BACK_V3_5_0.ino` del paquete `firmware/chest/V3_5_4`, Arduino-ESP32 3.3.12 / ESP-IDF 5.5.5.
La copia completa de la app está en el móvil del usuario y sirve para volver atrás.

## Qué mejora (y por qué)
| Cambio | Motivo |
|---|---|
| **8 Hz con GPS+GLONASS+Galileo+BeiDou** (antes 10 Hz) | El data sheet del ZED-F9P (tabla 1) limita el RTK a **8 Hz con 4 constelaciones**, 10 Hz con 3 y 12 Hz con GPS+Galileo. A 10 Hz con 4 la V3.5.0 pedía más de lo que el receptor resuelve en RTK. 8 Hz con todos los satélites da el fix más robusto (bajo árboles, con el cuerpo del jinete tapando parte del cielo). |
| Si el pecho pide otro ritmo, se ajustan las constelaciones | 9–10 Hz → sin BeiDou; 11–12 Hz → GPS+Galileo; más de 12 Hz → 12. Las constelaciones solo se cambian cuando hace falta, porque el cambio reinicia el seguimiento. |
| **RTK fijo** (`CFG-NAVHPG-DGNSSMODE = 3`) explícito | Resolver ambigüedades enteras: precisión centimétrica, no solo float. |
| **Modelo dinámico Airborne <2g** | Sin restricciones de suelo ni de velocidad vertical: galope, cambios de aire, saltos. u-blox da sus prestaciones con modelos airborne. |
| Máscara de elevación 10° y CN0 mínimo por defecto, explícitos | Los satélites bajos son los que más rebote (multitrayecto) traen. |
| Perfil enviado en un **VALSET aparte** | Si un receptor con firmware antiguo lo rechaza, se reintenta reducido y, si no, la espalda funciona igual que la 3.5.0. Nada se graba en la flash del ZED (capa RAM). |
| RTCM al ZED también mientras se reconfigura | Antes se retenía durante CONFIGURE aunque la velocidad UART ya fuera conocida. |
| Wi-Fi sin ahorro de energía y a potencia máxima | La radio siempre escucha: las correcciones llegan sin espera añadida y con más alcance. |
| Espera de ACK de ESP-NOW 25 ms (antes 80 ms), cola de 48 paquetes | Un pecho que no contesta ya no frena el envío de posiciones; aguanta ráfagas de RTCM. |
| Monitor serie con búfer de 4 KB y bucle sin pausas cuando hay trabajo | Imprimir el estado ya no bloquea ~40 ms cada 2 s. |
| Marcador `AVO-BACK 3.8.0` | La app AVO Update lo identifica y no deja instalarlo en el pecho, ni el del pecho en la espalda. |

**No cambia:** el protocolo con el pecho (ESP-NOW enlace v1 + tramas AVO UART v1, emparejamiento, `BackStatus`).
El pecho ve la espalda igual que antes (versión «3.8.0» en CAPS).

## Instalar
- **Desde el móvil:** app AVO Update 2.1.0 → conectar la espalda por USB-C → Seleccionar firmware
  (`AVO_BACK_V3_8_0_firmware.bin` del artefacto de Actions) → Comprobar módulo → Instalar. Se escribe en el slot libre
  (app1); la 3.5.0 queda en app0 como respaldo.
- **Desde ordenador:** `build_back.sh` (arduino-cli, núcleo esp32 3.3.12, placa `heltec_wireless_stick_lite_V3`).

## Comprobar en el monitor serie (115200)
```
AVO BACK 3.8.0 — Heltec ...
  ZED: FUNCIONANDO baudios=230400 puerto=UART2 config=OK ritmo=8 Hz (medido 8.0 Hz) ...
  PRECISION: perfil=COMPLETO constelaciones=GPS+GLO+GAL+BDS modelo=7 RTK=fijo
  RTCM: ... ZED aplicadas=… rechazadas=0
```
Si aparece `perfil=RECHAZADO (receptor antiguo)`, actualizar el firmware del ZED-F9P a HPG 1.32 o posterior.

## V3.8.1 — batería de la espalda (2026-10-25)
- **Lectura de la batería:** se lee la tensión en GPIO1. El divisor se activa con GPIO37 (ADC_Ctrl) solo mientras se mide. Media de 16 lecturas cada 5 s, con suavizado.
- **Revisión de la placa:** se detecta al arrancar. En la V3/V3.1, ADC_Ctrl lleva pull-up y se activa con LOW; en la V3.2 (la de esta espalda, HTIT-WSL_V3 rev. 3.2) lleva transistor y se activa con HIGH. El monitor muestra `[AVO ESPALDA] bateria N mV (… placa …)` y una línea `BATERIA` cada 2 s.
- **Envío:** la tensión va al pecho en el campo que ya existía (`BackStatus.back_batt_mv`). La app calcula el %. No cambian el protocolo, la RTK, el ESP-NOW ni el emparejamiento.
- **Lecturas inválidas:** fuera de 2,5–4,6 V se envía 0 (desconocido), por ejemplo sin batería o con la polaridad equivocada.
- **Sin estado de carga:** la placa no tiene ninguna patilla que indique si está cargando.
- Divisor ×4,9 según el diseño de referencia de Heltec. **Sin verificar** en la espalda real: hay que comparar la tensión del monitor con la de un multímetro.

## V3.8.2 — modo carga (2026-10-25)
Con un cargador de pared, la placa no puede cargar la batería y a la vez alimentar el ZED-F9P y la radio. Tampoco tiene ninguna patilla que avise de que hay alimentación por USB, porque el USB va por un chip puente.

- **Entrar en el modo carga:**
  - mantener pulsado **USER 8 s** (a los 3 s se sigue abriendo el emparejamiento, como antes);
  - o **automáticamente**, si la tensión sube de forma continua (≥ 60 mV en 3 min, sin bajadas) después de 5 min encendida.
- **Durante el modo carga:**
  - se apagan ESP-NOW y el Wi-Fi, se cierra el UART del ZED y se corta Vext, de modo que el ZED se queda sin alimentación;
  - la CPU baja a 80 MHz;
  - el USB serie sigue activo, así que **AVO Update puede instalar firmware igual que siempre**;
  - el monitor muestra `MODO CARGA bateria N mV` cada 10 s.
- **Salir del modo carga** (el equipo se reinicia y vuelve a funcionar):
  - pulsar USER;
  - o automáticamente, si la tensión cae más de 120 mV desde el máximo, porque eso indica que se ha desconectado el cargador.
- Si con la carga conectada la tensión no llega a subir, la detección automática no se activará: en ese caso hay que usar el botón.
- **Sin verificar** en la espalda real.
