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

## V3.10.6 — LED apagado al dormir y ZED a 1 s (2026-10-28)
- El LED blanco de la Heltec es el mismo pin que va al RX del ZED (GPIO35). Al dormir con el ZED en 3V3, el RX del ZED
  levantaba la línea y el LED quedaba encendido toda la noche. Ahora GPIO35 queda en LOW fijado durante el sueño.
- Retardo de encendido del ZED: 1 s (la prueba de 10 s de la 3.10.5 no cambió el bucle de arranque con el ZED en Vext,
  que se produce en el cargador de arranque, antes del firmware: es de hardware; arreglo propuesto, 470–1000 µF entre 3V3 y GND).
- Con el ZED en 3V3 la espalda duerme pero el ZED sigue encendido (~70 mA): la batería no dura dormida.

## V3.10.7 — ZED en reposo por software (2026-10-29)
Con el ZED en Vext la placa entra en bucle `POWERON` al arrancar (hardware, en el cargador de arranque). Sin piezas nuevas:
- **Cableado:** VCC del ZED otra vez en **3V3**; **INT** de la placa URTK1.2 (EXTINT del ZED) → **GPIO6** de la Heltec.
- Antes de dormir la Heltec manda `UBX-RXM-PMREQ` (duración 0 = hasta despertar, flags backup + force, despertar por
  EXTINT0). GPIO6 queda en HIGH fijado durante el sueño. Al arrancar o despertar, pulso LOW de 20 ms en GPIO6 → el ZED
  sale del reposo (conserva efemérides: arranque en caliente).
- Si el VCC del ZED va en Ve, se sigue cortando Vext como en la 3.10.4–3.10.6.
- Consumo del ZED en este reposo: el data sheet no lo da → medir. El LED PWR de la placa URTK1.2 sigue encendido
  (va directo al 3V3): para el mínimo consumo, quitar ese LED o su resistencia.
- **Sin INT conectado el ZED no se despierta** hasta quitar y volver a poner la batería.

## V3.10.8 — el ZED también despierta por su RX (2026-10-29)
Con la 3.10.7 el ZED se quedó en reposo al despertar la Heltec (app: «Sin GNSS», último dato GNSS hace 199 s): la orden
de reposo funcionó pero el pulso por INT no lo sacó (INT sin conectar o sin efecto).
- `UBX-RXM-PMREQ` con despertar por **UART RX + EXTINT0** (`wakeupSources` 0x28): **el cable INT ya no hace falta**.
- Justo después del último byte de la orden, GPIO35 (RX del ZED y LED blanco) pasa a LOW por la matriz GPIO, antes de que
  el ZED la procese, y queda fijado en LOW: ningún flanco mientras duerme y LED apagado.
- Al despertar, el UART vuelve a poner la línea en HIGH y manda 8 bytes 0xFF: esos flancos sacan al ZED del reposo.
- Si la cápsula estaba fuera del soporte al arrancar (UART aún sin abrir), se abre a 38400 para mandar la orden.
- Para sacar un ZED que se quedó dormido con la 3.10.7: quitar la batería 5 s una vez.

## V3.10.9 — reed desactivado (2026-10-29)
A petición del usuario, la espalda vuelve a funcionar como la 3.10.2: **no se duerme nunca** (el reed se ignora,
`AVO_REED_SLEEP 0` en el `.ino`; con 1 vuelve el comportamiento de la 3.10.3–3.10.8). Se mantienen el ahorro de la
3.10.2 y el despertar del ZED al arrancar (pulso en INT/GPIO6 + bytes 0xFF por su RX).
Un ZED que la 3.10.7 dejó en reposo solo acepta despertar por INT: sin ese cable hay que dejarlo sin corriente
(USB y batería fuera, 10 s).

## V3.11.0 — ZED con su propio regulador (Pololu S7V8F3) (2026-10-29)
El ZED deja de colgar del 3V3 de la Heltec: lo alimenta un **Pololu S7V8F3** (3,3 V, entrada 2,7–11,8 V, 11 × 17 × 3 mm)
desde la batería y la Heltec lo enciende y apaga por **SHDN**. Su arranque ya no hunde el 3V3 de la Heltec (sin bucle
`POWERON`) y dormida el ZED queda a 0 V con todos sus LEDs apagados (también PWR). Vuelve el sueño con el reed.
| S7V8F3 | Conexión |
|---|---|
| VIN | + de la batería |
| GND | GND |
| VOUT | 3V3 de la placa URTK1.2 (se quita el cable al 3V3 de la Heltec) |
| SHDN | GPIO6 de la Heltec (el pin INT del ZED queda **sin conectar**) |
- GPIO6 en LOW desde el arranque hasta confirmar el reed; HIGH al encender el ZED (50 ms de arranque suave del regulador);
  LOW fijado durante el sueño y en el modo carga.
- Se mantiene la orden de reposo `UBX-RXM-PMREQ` antes de cortar: si el ZED sigue en 3V3 (sin el módulo), funciona como
  la 3.10.8.
- Consumo del S7V8F3 apagado: ~10 µA por voltio de entrada por su resistencia de 100 kΩ en SHDN (~40 µA a 4 V).

## V3.12.0 — contactos pogo, sin Qi ni reed (prototipo Rev E + Heltec) (2026-10-30)
Firmware para probar en el prototipo actual el sistema de alimentación de la espalda V4 REV B (guía de cableado y piezas:
`hardware/back/V4/DOCS/PROTOTIPO_POGO_REV_E.md`).
- La cápsula lleva 3 contactos en el fondo: **SYS** (entrada de la Heltec y del S7V8F3), **BAT** (+ de la celda, tras
  un fusible rearmable) y **GND**. El soporte del chaleco puentea SYS–BAT: la placa solo tiene corriente en el chaleco.
  La base de carga carga la celda entre BAT y GND con la Heltec apagada.
- `AVO_REED_SLEEP 0`: sin reed (GPIO7 queda libre). No hay sueño por soporte: quitar la cápsula = 0 V.
- **Emparejamiento sin abrir la cápsula:** poner y quitar la cápsula del soporte 3 veces seguidas, cada vez menos de
  4 s → emparejamiento abierto 120 s (contador `boots` en la NVS, se borra a los 4 s de funcionamiento). El PRG 3 s sigue.
- Monitor: `INTERRUPTOR: reed no usado (V3.12: contactos pogo …)`.

## V3.13.0 — Pololu en GPIO34 y carga por USB con todo dormido (2026-10-31)
Para la espalda con la Heltec, el Pololu S7V8F3 para el ZED y **sin Qi** (la batería se carga por el USB-C de la Heltec,
boca USB de la tapa Rev E.5).
| Señal | Conexión |
|---|---|
| SHDN del Pololu | **GPIO34** = pin 7 de la fila Ve·GND·12·RX·TX·33·**34**·35·36… (entre los cables del ZED en 33 y 35) |
| VIN / GND / VOUT del Pololu | + batería / GND / 3V3 de la URTK1.2 (sin cambios) |
| Detección del USB | pin **5V** de la Heltec ─ **10 kΩ** ─ **GPIO7** ─ **15 kΩ** ─ **GND** (≈ 3,0 V con USB, 0 V sin USB) |
- Con el USB conectado (1,5 s seguidos, o al arrancar): todo se duerme (ZED a 0 V por el Pololu, radio apagada, LoRa
  dormida, LED blanco apagado) y solo carga la batería (cargador TP4054 de la Heltec).
- Al desconectar el USB, GPIO7 baja a 0 V y despierta la placa (ext0): funciona normal y se enlaza con el reloj.
- **Modo taller** (monitor serie con el USB conectado): pulsar USER en los 3 s siguientes a enchufar o reiniciar. Instalar
  firmware con AVO Update funciona igual (la app reinicia la placa en el cargador de arranque).
- Sin el divisor en GPIO7 la espalda no se duerme con el USB (queda el modo carga de la 3.8.2 por tensión subiendo).
- Los 3 encendidos rápidos para emparejar solo cuentan arranques reales (no los despertares tras cargar).
- Monitor: `INTERRUPTOR: reed no usado | USB: CONECTADO/no (GPIO7 … mV) | GPS: Pololu SHDN GPIO34 ENCENDIDO/apagado`.

## V3.13.1 — comprobación del USB por temporizador (2026-10-31)
- Dormida por USB ya no se despierta por nivel en GPIO7 (con el divisor el pin queda cerca del umbral de entrada):
  se despierta cada 3 s, mide GPIO7 con el ADC al principio de `setup()` y vuelve a dormir si sigue el USB. ZED, LED y
  radio siguen apagados entre medias (pines fijados). Al quitar el USB arranca en ≤ 3 s.
- Al arrancar imprime el motivo de reinicio y de despertar (`arranque: motivo de reinicio N, despertar M`).
- **Sin el divisor 10 k / 15 k en GPIO7 la placa no puede saber que hay USB**: no se duerme. El reinicio que se ve al
  enchufar el USB a un móvil u ordenador es el del CP2102 (DTR/RTS al abrir el puerto), no el sueño.

## V3.13.2 — detección del USB también en GPIO20 (2026-10-31)
A petición del usuario, el divisor puede ir a **GPIO20** (pin 8 de la fila 5V·3V3·GND·47·48·0·26·**20**, junto al pin 5V):
- **5V ─ 10 kΩ ─ GPIO20 ─ 22 kΩ ─ GND** (≈ 2,7–3,0 V con USB y el pull-down interno). Se lee como entrada digital: GPIO20
  es ADC2, que no se puede leer con la radio encendida.
- GPIO20 es el D+ del USB propio del ESP32-S3 (sin conectar en esta placa, el USB-C va al CP2102): el firmware apaga ese
  USB y su pull-up para usarlo como entrada normal.
- GPIO7 con 10 kΩ / 15 kΩ sigue valiendo. El firmware mira los dos: vale cualquiera de las dos conexiones.

## V3.13.3 — corte por batería baja y USB solo en GPIO20 (2026-10-31)
- Monitor del usuario (02:05): batería **2954 mV** y `Brownout detector was triggered` al arrancar la radio, en bucle
  (`rst:0x3`, motivo 9). Ese era el «se duerme un segundo y vuelve a arrancar».
- **Corte por batería baja:** antes de encender la radio mide la batería en reposo; por debajo de **3,30 V** (y sin USB)
  se duerme con el ZED sin corriente y vuelve a mirar cada 60 s; arranca de nuevo por encima de **3,45 V**.
- USB solo por **GPIO20** (digital con pull-down; divisor 5V ─ 5,1 kΩ ─ GPIO20 ─ 10 kΩ ─ GND). La lectura por ADC de
  GPIO7 se quita: sin nada conectado flotaba y daba «USB conectado» al azar.
- Al arrancar imprime `bateria en reposo N mV | USB (GPIO20): ALTO = conectado / bajo = no detectado`.

## V3.13.4 — USB en GPIO20 también por ADC, umbral 1,0 V (2026-10-31)
- La entrada digital necesita ≈ 2,5 V y en la placa del usuario leía «bajo» con el USB conectado. Ahora GPIO20 también se
  mide con el ADC: más de **1,0 V** = USB. Si la lectura falla (ADC2 ocupado por la radio) decide la entrada digital y un
  fallo suelto no reinicia la cuenta de 1,5 s.
- El monitor muestra la tensión medida: `USB (GPIO20 … mV)` al arrancar y `GPIO20 ALTO/bajo, … mV` en el estado.

## V3.13.5 — el divisor del USB puede estar en cualquier pin libre de la fila del 5V (2026-10-31)
- Con la 3.13.4 GPIO20 medía 0,17 V con el USB conectado: no le llega el divisor (pin o soldadura distinta).
- Ahora vale un nivel alto en **GPIO20, 18, 21, 19, 47 o 48** (entrada con pull-down). GPIO26 no se toca (es la flash).
- Al arrancar imprime el nivel de cada uno: `USB, pines candidatos (1 = tension): GPIO20=… GPIO18=… …` y el pin que lo
  ha detectado (`conectado por GPIOn`).

## V3.13.6 — cables RX/TX del ZED probados en los dos sentidos (2026-10-31)
- Si el ZED no envía nada en 10 s desde que tiene corriente, la espalda cruza RX y TX (GPIO33 ↔ GPIO35) y vuelve a
  buscar; alterna cada 10 s hasta recibir datos. El orden que funciona se guarda en NVS (`zedswap`) para el siguiente
  arranque. Monitor: `el ZED no envia nada: pruebo los cables al reves …` / `el ZED responde con RX=GPIOx TX=GPIOy`.
- Con los cables cruzados el LED blanco (GPIO35) parpadea con los datos del ZED: es normal.

## V3.13.7 — recuperación del GPS (2026-10-31)
Rama `fix/back-3-13-7-gps` (derivada de `develop/avo-performance-horse`). Auditoría completa en
`docs/AUDITORIA_GNSS_3_9_0_vs_3_13_6.md`.
- Pines fijos **RX=GPIO33 / TX=GPIO35** (UART1); sin intercambio automático (se borra `zedswap`).
- Al arrancar, **antes de la radio**: ciclo de corriente del ZED por GPIO34 (0 → 500 ms → 1), 1,5 s, UART1 y **solo
  escucha** en todos los baudios (bytes, B/s, UBX y NMEA válidos); si no oye nada, un flanco 0xFF y otra vuelta.
  Después se activa ESP-NOW y `ZedManager` configura UBX, RTK y 8 Hz como en la 3.9.0.
- Sin UBX-RXM-PMREQ al dormir (el Pololu corta la corriente).
- Monitor: línea `GNSS:` con B/s, UBX, NMEA, NAV-PVT y GPIO34 (alimentación **solicitada**, tensión no medida);
  `GPS NO VERIFICADO (sin NAV-PVT)` mientras no lleguen NAV-PVT.

## V3.13.8 — GPS UART PIN FIX (2026-10-31)
Rama `fix/back-3-13-8-gps-uart` (desde `fix/back-3-13-7-gps`). Cableado físico confirmado por el usuario:
| Cable | Origen | Destino Heltec | Uso en el firmware |
|---|---|---|---|
| Blanco | RX del ZED-F9P | GPIO33 | **TX** de UART1 |
| Verde | TX del ZED-F9P | GPIO35 | **RX** de UART1 |
| Amarillo | SHDN del Pololu S7V8F3 | GPIO34 | encendido del GPS |
- `HardwareSerial ZED(1); ZED.begin(baud, SERIAL_8N1, 35, 33)` en todas las aperturas (diagnóstico, encendido y
  cargador de reserva). Sin intercambio automático.
- **GPIO35 / LED blanco:** el firmware no tiene código de LED. GPIO35 ya no se configura como salida, no se escribe ni se
  fija al dormir (antes, como TX, se fijaba a LOW). Al dormir se fija a LOW el **GPIO33** (TX). El LED, conectado por
  hardware a GPIO35, se ve encendido mientras la línea TX del ZED está en reposo (ALTO) y parpadea con sus datos: es
  normal y no lo controla el firmware.
- **USB:** solo GPIO20 como entrada digital con pull-down, 4 de 5 lecturas en ALTO. Sin ADC2. El monitor dice
  `USB GPIO20=HIGH/LOW`. Si con el USB conectado sigue en LOW, la señal física no llega a GPIO20 (medido 0,16–0,17 V):
  **no está resuelto**.
- Monitor: `AVO BACK V3.13.8`, `GNSS UART1: RX=GPIO35 TX=GPIO33`, `POLOLU: SHDN GPIO34=HIGH` y cada 2 s
  `GNSS: bytes recibidos=… | UBX validos=… | NMEA validos=… | NAV-PVT=… | estado=…`.

## V3.13.8 DIAGNÓSTICO — Pololu siempre encendido (2026-10-31)
Rama `diag/back-3-13-8-pololu-libre`, binario `AVO_BACK_V3_13_8_DIAG_POLOLU_firmware.bin`. **No es una versión de ahorro.**
- `AVO_POLOLU_FREE 1`: GPIO34 se libera de cualquier hold y queda como `INPUT` sin pull-up ni pull-down; nunca se escribe
  ni se fija (ni despierta, ni dormida, ni en modo carga). El SHDN del Pololu queda en ALTO por su propia resistencia de
  100 kΩ a VIN: el GPS tiene la alimentación **solicitada** siempre, también en sueño profundo y cargando.
- UART1 RX=35 / TX=33 y el diagnóstico de bytes de la 3.13.8 sin cambios.
- Monitor: `POLOLU: SHDN LIBRE — GPIO34 EN ALTA IMPEDANCIA`, `GPS: alimentacion permanente solicitada`, `UART1: RX=35 TX=33`,
  `GNSS: bytes recibidos=…`.
- Con GPIO34 suelto, el pull-up del Pololu sube el pin hacia la tensión de la batería (hasta 4,2 V) a través de 100 kΩ:
  unos µA por el diodo de protección del ESP32-S3. Para una prueba corta no es un problema; si se deja así, poner
  100 kΩ de SHDN a GND (el pin queda ≤ 2,1 V y el Pololu sigue encendido).
