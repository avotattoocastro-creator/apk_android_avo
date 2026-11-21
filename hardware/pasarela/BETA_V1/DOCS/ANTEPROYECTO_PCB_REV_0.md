# AVO PASARELA LTE BETA V1 · Anteproyecto de la PCB REV 0 (21/11/2026)

**Estado:** anteproyecto (componentes, colocación por bloques y medidas). **No hay esquema ni placa de KiCad todavía.**
Nada fabricado. Antes de generar archivos de fabricación o pedir la placa, se confirma con el usuario.

## Objetivo (decisiones del usuario, 21/11/2026)
- Kit completo sin móvil: **casco BACK V5 + cincha PCB REV D + pasarela LTE**. La pasarela hace lo que hoy hace el móvil
  en pista: cliente NTRIP, LIVE y subida de entrenamientos. El móvil queda para ver y analizar.
- La lleva el **jinete en el bolsillo o el cinturón, lejos del casco** (separa la antena LTE de la GNSS).
- **eSIM soldada (MFF2)** si no encarece mucho.
- Primero la PCB (medidas); la cápsula después.
- Antes, validar las funciones con una LilyGO como PROTOTIPO (regla de pruebas de campo del 17/11).

## Placa
- **54 × 32 mm**, esquinas R2, 4 capas, 1,0 mm, ENIG. Todo en la cara F; altura máxima 3,1 mm (módulo ESP32).
- Envolventes de bloque: 1188 de 1728 mm² (69 %). Margen para el ruteado en 4 capas.
- 2 taladros Ø2,2 (M2) en (±24, −13). La cápsula sujeta el lado de los módulos con nervios.
- Colocación: `colocacion_pcb_rev0.svg` (generada por `PCB/fuente/place_rev0.py`, que comprueba solapes, márgenes y
  taladros). Medidas para el CAD: `PCB/pcb_mecanica.json`.
- **Antenas en extremos opuestos:** la del ESP32 (PCB) a ras del canto izquierdo, sin cobre en ninguna capa bajo sus
  6 mm; el U.FL de LTE en el canto derecho, hacia una antena flexible pegada a la pared de la cápsula.

## Componentes elegidos
| Bloque | Pieza | Medida | Por qué |
|---|---|---|---|
| Micro | ESP32-S3-WROOM-1-**N16R8** (antena PCB) | 18 × 25,5 × 3,1 | Misma familia y memoria que el casco V5 (16 MB + 8 MB PSRAM): mismo firmware base, búferes para TLS y subidas. Antena integrada: sin conector ni antena de 2,4 GHz aparte |
| Módem | **Quectel EG800Q-EU** (LTE Cat 1 bis, JLC C19273720, Extended, rayos X) | 17,7 × 15,8 × 2,4 | El más pequeño de su clase. Bandas europeas B1/3/5/7/8/20/28 (B20 = 800 MHz, buena cobertura rural). Una sola antena. TLS, HTTP(S), MQTT y NTP en el propio módem |
| Alternativa | SIMCom A7670E (familia de las LilyGO) | 24 × 24 × 2,4 | +35 % de área (placa ≈ 58 × 32). Solo si se quiere el mismo juego de comandos AT que el prototipo |
| SIM | **eSIM MFF2** (DFN-8) | 6 × 5 | Sin bandeja ni junta extra: mejor para IP67 y vibración |
| Memoria | SPI NAND W25N02KV, 2 Gbit (256 MB) | 8 × 6 | Guarda las sesiones `.avr` (hasta 40 MB) antes de subirlas. Soldada: sin microSD |
| Niveles | TXS0108E | ≈ 4 × 5 (E) | Las E/S del módem son de 1,8 V (confirmar en su Hardware Design); 8 líneas: TX, RX, RTS, CTS, DTR, RI, STATUS, NET_STATUS |
| Encendido del módem | 2 NPN (PWRKEY, RESET_N) + PMOS de corte (Q1, ≤ 30 mΩ) | SOT-23 | Reinicio total si el módem se cuelga |
| Carga | BQ24072 (como el casco V5) | QFN 3 × 3 | Pogo de 5 V → batería |
| 3,3 V | **TPS63802 buck-boost** | 2 × 3 + bobina 2016 | Con LDO, a ≈ 3,5 V de batería y el pico del módem, el ESP32 se reiniciaría. El buck-boost mantiene 3,3 V |
| Medidor | MAX17048 (I²C 0x36) | 2 × 2 | Igual que el casco |
| Táctil | TTP223 + apagado total por EN | SOT-23-6 | Igual que el casco (pulsación larga) |
| Pogo | 5 contactos por hilos: VBUS, D−, D+, GND, AUX | — | Mismo que el casco: carga en el DOCK, programación y aprovisionamiento por USB |
| Protección | USBLC6-2SC6, PTC y TVS en VBUS, PTC 1812 en batería | — | Como el casco |
| Aviso | 1 LED RGB SK6812 2020 | 2 × 2 | Estado de LTE / NTRIP / subida |

(E) = estimado; el resto, de la hoja de datos.

## Alimentación
```
Pogo 5 V ─ PTC ─ TVS ─ BQ24072 ─ VSYS ─ TPS63802 ─ 3V3 (ESP32, NAND, niveles, medidor)
Batería ─ PTC 1812 ─┬─ BQ24072 (BAT)
                    └─ Q1 PMOS ─ VBAT_MÓDEM (220 µF + 2 × 100 µF + 100 nF + 33 pF + 10 pF + TVS)
```
- El módem va **directo a la batería**, no por la salida del cargador: necesita **≥ 2 A** de pico en transmisión.
- Corte por batería baja en firmware a 3,4 V (el módem trabaja de 3,3 a 4,3 V).

## Conexiones del ESP32-S3 (propuesta)
| GPIO | Función | GPIO | Función |
|---|---|---|---|
| 1 | BAT_ADC | 17 / 18 | UART1 TX / RX al módem |
| 2 | TOUCH_SENSE | 15 / 16 | RTS / CTS (control de flujo para subidas largas) |
| 4 | MODEM_PWRKEY (NPN) | 19 / 20 | USB D− / D+ (pogo) |
| 5 | MODEM_RESET (NPN) | 21 | MODEM_PWR_EN (Q1) |
| 6 | MODEM_STATUS | 38 / 39 | PGOOD / CHG del cargador |
| 7 | MODEM_RI (despertar) | 40 | ALRT del medidor |
| 8 | MODEM_DTR | 41 / 42 | I²C SDA / SCL |
| 10–13 | SPI NAND (CS, MOSI, SCK, MISO) | 46 | POWER_HOLD |
| 14 | VBUS_DET | 47 / 48 | LED / POGO_AUX |

Libres de PSRAM octal (35–37) y de la flash (26–32). Se revisa pin a pin al hacer el esquema.

## Funciones y contratos
- **Fase 1, sin cambios de contrato:** la pasarela se conecta al casco (o al pecho del PROTOTIPO) por BLE **como el
  móvil**: lee `TELEMETRY v3`, envía el GGA al caster y escribe el RTCM3 con crédito y CRC-24Q. LIVE: solo GPS a
  Realtime Database.
- **Fase 2, con cambio de contrato** (firmware + Android + Windows + iPad a la vez): subida del `.avr` a una ruta nueva
  de Storage y generación del `.avo` en el servidor con el motor C++. Caballo y jinete desde las apps (`assignedMs`).
- **Credenciales:** el token de la tarjeta y la cuenta NTRIP se cargan por USB (pogo) y se guardan cifrados en la NVS.
  Nunca en el código ni en el repositorio.

## Estimaciones (NO VERIFICADAS; se miden con la LilyGO)
- **Datos:** la prueba del 02/11 recibió 1,1 MB de RTCM en ≈ 7 min → **≈ 9–10 MB/h** de NTRIP; LIVE ≈ 1 MB/h. Con
  2 h de pista al día, ≈ 0,7 GB/mes por kit. Subidas por Wi-Fi en la cuadra; por LTE sumarían hasta 40 MB por sesión.
- **Consumo:** ESP32 con BLE ≈ 35–50 mA + módem conectado con flujo continuo ≈ 40–80 mA → **≈ 80–135 mA**. Con una
  batería de ≈ 1200 mAh (603450, 50 × 34 × 6), **≈ 7,5–12 h**.
- **Cápsula (orientativa):** ≈ 58 × 38 × 15 mm con la batería debajo de la placa.

## eSIM: coste
- Un chip MFF2 cuesta algo más que una SIM de plástico, pero ahorra el portatarjetas y la junta. La diferencia por
  unidad es de unos pocos euros: no es un problema.
- **Lo que sí hay que decidir es el operador:** una MFF2 normal queda ligada a su proveedor. Una **MFF2 eUICC** (perfil
  remoto, SGP.32) permite cambiar de operador sin tocar la placa. Hace falta una tarifa de ≈ 1 GB/mes por kit (las de
  500 MB para 10 años no llegan).

## Riesgos
1. **BLE a través del cuerpo:** del bolsillo al casco hay ≈ 1 m y el cuerpo del jinete atenúa 2,4 GHz. Se mide con la
   LilyGO antes de cerrar la placa. Plan B: WROOM-1U con antena FPC.
2. **Antena LTE pequeña:** con una placa de 54 mm, la banda de 800 MHz rinde poco con antena de chip. Por eso se usa una
   antena flexible en la pared de la cápsula. Hay que elegirla y ajustar la red en pi.
3. **Existencias en JLC** del EG800Q, la eSIM y el TPS63802: no se pudieron consultar desde esta sesión. Se comprueban
   con `stock_jlc.py` en el CI antes de cerrar la BOM.
4. **Comandos AT distintos** entre la LilyGO (SIMCom) y el EG800Q (Quectel): el firmware tendrá una capa de módem para
   cambiar solo el controlador.

## Pendiente de decidir
- Módem: EG800Q-EU (recomendado) o A7670E.
- Proveedor y tipo de eSIM (con o sin eUICC).
- ¿Vibrador para avisos al jinete? (≈ 4 mm de diámetro; cabe en la franja inferior)

## REV 1 (21/11/2026, 11:11–11:21): Cat 4 + pantalla AMOLED (decisiones del usuario)
- **Módem Cat 4** para subir a velocidad parecida a la del móvil: **SIMCom SIM7600E-H** (LCC 30 × 30, LCSC C5338795,
  Cat 4 150/50 Mbit/s). El Quectel EG25-G no está en LCSC/JLC. Mismos comandos AT que las LilyGO T-SIM7600.
- Conexión **USB** entre ESP32-S3 y módem (conmutador TS3USB221A: en el DOCK el USB va al pogo, fuera va al módem).
  Techo real ≈ 8 Mbit/s (USB *full speed* del S3): ≈ 40–60 s para 40 MB (estimado).
- **ESP32-S3-WROOM-1U-N16R8** (como el casco) con antena FPC de 2,4 GHz por U.FL.
- **Pantalla AMOLED 2,06" 410 × 502 (CO5300 + táctil)** en la cara B, la misma del pecho PROTOTIPO.
- Todo sellado: solo el pogo de 5 contactos por fuera.
- Placa **60 × 40 × 1,0 mm**, 4 capas. Colocación: `out/PRESUPUESTO/*_COLOCACION.svg`.
- **Paquete solo para presupuesto** (`PCB/fuente/presupuesto_rev1.py` → `out/PRESUPUESTO/`): Gerber de contorno de 4
  capas sin pistas, BOM con códigos LCSC (127 piezas, 37 referencias) y CPL con posiciones aproximadas. **NO FABRICAR.**
- Fuera de JLC: eSIM (la da el operador), panel AMOLED y su conector FPC, antenas y batería.
- Siguiente: huellas EasyEDA en el CI (`easyeda-fp-pasarela.yml`, solo en esta rama) → esquema → ruteado y DRC/ERC.

## Siguiente paso
Con el visto bueno: esquema y placa en KiCad 9 con el mismo flujo que el casco y la cincha (Python → Freerouting en el
CI → DRC, ERC y paridad → puerta de fabricación). Después, la cápsula en FreeCAD.
