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

## V3.10.2 — ahorro de batería (2026-10-28)
Consumo estimado de la espalda funcionando: ~190–230 mA (ESP32-S3 con la radio siempre escuchando, ZED-F9P y antena
activa). Con la 654060 de 2000 mAh, unas 8 h. Esta versión quita lo que se puede quitar sin tocar el RTK ni el enlace:

| Cambio | Ahorro estimado | Riesgo |
|---|---|---|
| CPU a **160 MHz** (antes 240) | ~10 mA | Ninguno: UART, ESP-NOW y el bucle GNSS/RTCM van sobrados. |
| **Radio LoRa SX1262 dormida** (SetSleep en frío por SPI: NSS 8, SCK 9, MOSI 10, MISO 11, RST 12, BUSY 13) | ~0,6 mA | Ninguno: no se usa. Tras encender, se quedaba en espera. |
| **Potencia de envío ESP-NOW adaptativa** (`lib/avo_core/src/avo_tx_power.*`) | 2–5 mA (los envíos son ~3 % del tiempo) | Bajo: vuelve al máximo al instante. |

Potencia adaptativa:
- Niveles 11 dBm, 15 dBm y el máximo de antes (petición 84 = 21 dBm, el S3 la limita a su máximo).
- Cada segundo toma el **peor RSSI** recibido del pecho y de la cincha emparejada. Suponiendo que el otro emite a ~20 dBm,
  elige el nivel más bajo que deja **−62 dBm** en el otro extremo (25–30 dB por encima de la sensibilidad a 1 Mbit/s).
  Con el pecho a −50 dBm usa 11 dBm; a −55, 15 dBm; por debajo de −58, el máximo.
- **Subir es inmediato.** Un envío fallido, un segundo sin paquetes del pecho o el enlace caído → máximo durante 15 s.
- **Bajar** es de nivel en nivel y solo tras 10 s seguidos en los que todos los segundos permitían el nivel más bajo.
- Arranca al máximo los primeros 15 s, igual que antes (emparejamiento y primer contacto).
- Pruebas en ordenador: `power.*` (4 casos).

Monitor serie: línea nueva `AHORRO: CPU 160 MHz | LoRa dormida | potencia radio N dBm` y un aviso
`potencia de radio N dBm (peor RSSI …)` cada vez que cambia.

**No cambia:** protocolo, emparejamiento, RTK, ritmo GNSS, modo carga ni la lectura de la batería.
**Sin verificar** en la espalda real. Ganancia total estimada: ~13–16 mA, un 6–8 % más de duración (≈ +30–40 min con 2000 mAh).

## V3.10.3 — encendido y apagado con el reed del soporte (2026-10-28)
El reed ya **no corta la batería** (el de 14 mm se soldó con el pico de corriente al conectar). Ahora solo avisa a la Heltec:

| Conexión | De | A |
|---|---|---|
| Batería | BAT+ / BAT− de la batería | conector de batería de la Heltec (SH1.25), **directo**, sin interruptor |
| Carga Qi | salida **BAT** de la placa Qi (o TP4056 si la placa solo da 5 V) | BAT+ / BAT− de la batería |
| Reed | una pata | **GPIO7** de la Heltec |
| Reed | otra pata | **GND** |
| ZED-F9P | alimentación (VCC 3,3 V del módulo) | **Vext** de la Heltec (**no** el 3V3 fijo) |
| ZED-F9P | GND, TX → GPIO33, RX ← GPIO35 | sin cambios |
| Pin 5 V de la Heltec | — | sin conectar (la Qi no alimenta la Heltec) |

Funcionamiento:
- **Cápsula en el soporte** (imanes cerca, reed cerrado, GPIO7 a GND): funciona normal.
- **Fuera del soporte 3 s** (reed abierto): corta Vext (ZED y antena a 0 V), pone en alta impedancia los pines del ZED, apaga
  la radio, mantiene Vext, ADC_Ctrl y la LoRa fijados durante el sueño (`gpio_hold_en`) y entra en **sueño profundo**.
  Se despierta al cerrar el reed (`ext0`, GPIO7 en LOW) y vuelve a enlazar con el pecho.
- **Al encender con la cápsula fuera del soporte:** espera 3 s y se duerme. Si se pulsa **USER** en esos 3 s entra en
  **MODO TALLER** (ignora el reed hasta reiniciar), para trabajar en la mesa sin el soporte.
- **Sin reed conectado** el GPIO7 queda en alto (pull-up) y la espalda se dormiría: o se conecta el reed, o se puentea
  GPIO7 a GND, o se usa el modo taller.
- La carga Qi no la despierta: carga la batería directamente mientras duerme.
- AVO Update instala el firmware igual aunque esté dormida (reinicia la placa en el cargador de la ROM).

Consumo dormida estimado (sin medir): 25–60 µA (ESP32-S3 en sueño profundo, regulador y cargador de la Heltec, protección de
la batería). Con 2000 mAh pesa más la autodescarga de la LiPo (2–3 %/mes): unos 3–5 % al mes en total.
Monitor serie: línea `INTERRUPTOR: reed CERRADO/ABIERTO`, y `A DORMIR (…)` al apagarse.
**Sin verificar** en la espalda real. Pruebas de ordenador: `reed.*` (2 casos).

## V3.10.4 — arranque suave de Vext (2026-10-28)
Con la 3.10.3 y el ZED pasado de 3V3 a Vext, la espalda se reiniciaba sin parar (`rst:0x1 (POWERON)` en bucle, sin llegar
a imprimir nada). Causa: la 3.10.3 apaga Vext al arrancar y lo vuelve a encender de golpe; el ZED (condensadores de entrada
+ antena activa) se conecta de una vez al 3V3 en marcha, el 3V3 cae y el ESP32-S3 se reinicia por falta de tensión.
- Vext se enciende ahora con PWM a 40 kHz cuyo tiempo encendido sube de 0,4 % a 100 % en ~200 ms; después queda en LOW fijo.
- Se usa al arrancar y al despertar. El apagado (dormir, modo carga) no cambia.
- **Sin verificar** en la espalda. Si aun así se reinicia al encender el ZED, volver el ZED al 3V3 y avisar.

## V3.10.5 — prueba: el ZED se enciende 10 s después de arrancar (2026-10-28)
Con la 3.10.3/3.10.4 y el VCC del ZED en Ve, la espalda no arrancaba si el ZED estaba conectado desde el principio; conectando
el cable de Ve a mano con la placa ya en marcha, sí funcionaba. Para probarlo sin tocar cables:
- al arrancar o despertar, Vext queda apagado y los pines del ZED como entradas durante **10 s** (`VEXT_DELAY_MS`);
- después se enciende Vext con el arranque suave de la 3.10.4 y se abre el UART del ZED;
- monitor: `el ZED se enciende dentro de 10 s`, la línea `GPS: sin corriente, se enciende en N s` y `Vext encendido: el ZED tiene corriente`.
**Prueba**, no versión definitiva: si funciona, se ajusta el retardo (probablemente bastan 1–2 s).
