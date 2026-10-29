# AVO BACK V4 · integración de la URTK1.2 (u-blox ZED-F9P-01B-01)

## Qué se sabe de la placa y de dónde sale

| Dato | Valor | Fuente | Estado |
|---|---|---|---|
| PCB | 43,434 × 43,688 × 1,6 mm | plano usado desde la Rev B (`parametros_revB.json`) | verificada por plano |
| Agujeros | Ø3,2 en (2,667; 2,794), (40,767; 2,794), (2,667; 41,275), (40,767; 41,275) desde la esquina −X −Y | ídem | verificada por plano |
| J2 (SMA de canto) | canto +X, a 23,2 mm del canto −Y; centro a 0,8 mm sobre la cara inferior | ídem + adaptador en L de la Rev E | verificada por plano |
| J1 (USB-C) y J3 (GH 6 pines) | canto −X | foto del usuario (29/10/2026) | **posición estimada** |
| J6 (pila de respaldo, tipo ML/CR1220) | junto a J3, cara superior | foto del usuario | **altura sin medir** |
| J4 (u.FL) | canto +X, junto al SMA | foto del usuario | no se usa |
| Componentes en la cara inferior | ninguno visible | **solo hay foto de otra placa** (serigrafía distinta) | **sin verificar**: medir |
| Alimentación | 3V3 en el pad «3V3» (funciona: así la alimenta la espalda desde la 3.10.x) | historial de la espalda | probado en campo |

No hay documentación pública de la «URTK1.2». Las fotos del anuncio muestran dos serigrafías diferentes: la de la
cara de componentes (la que lleva escrito URTK1.2) y otra cara inferior con un pinout distinto
(GND, 5V, PPS, EVENT, PVT, RTK, ERR, RESET, EXT / TXD2, RXD2, GND, 3.3V, SDA, RXD3, TXD3, SCL). **Esa segunda foto es de
otra placa** (9 + 8 pads, frente a los 10 + 9 de la URTK1.2): no se ha usado para nada.

### Pads de la URTK1.2 (serigrafía de la cara de componentes, J2 hacia abajo en la foto)
- Columna izquierda (en la carcasa: canto −Y, de −X a +X): **GND · 3V3 · SDA · SCL · FENCE · RTK · PPS · RST · SAFE · INT**
- Columna derecha (en la carcasa: canto +Y, de −X a +X): **GND · 5V · 3V3 · TX2 · RX2 · CS · RX/MOSI · TX/MISO · SCK**
- J3 (GH 6): serigrafía legible **GND · NC · NC · TX1 · …** (el resto no se lee en la foto).

En el ZED-F9P, UART1 comparte pines con SPI (por eso «RX/MOSI» y «TX/MISO»); UART2 es la que usa hoy la espalda
(`puerto=UART2` en el monitor de la 3.8.0–3.11.0).

## Conexión con la placa V4: J4 (8 pads pasantes, paso 2,54) y mazo de 8 hilos
La placa V4 **no depende de la posición de los pads de la URTK1.2**: tiene 8 señales fijas en J4 y el mazo se hace
según el pinout verificado. Así un error de la foto no obliga a rehacer la PCB.

| J4 | Señal de la placa V4 | Pad de la URTK1.2 (serigrafía) | GPIO del ESP32-S3 | Notas |
|---|---|---|---|---|
| 1 | +3V3_ZED (RT9080, EN = GPIO10) | 3V3 (columna izquierda) | — | 0 V al dormir y en modo carga |
| 2 | GND | GND | — | |
| 3 | ZED_TX1_C → 330 Ω → GPIO5 | TX/MISO | 5 (RX) | UART1, reservada para RAW a alta velocidad |
| 4 | ZED_RX1 ← 1 kΩ ← GPIO6 | RX/MOSI | 6 (TX) | |
| 5 | ZED_TX2_C → 330 Ω → GPIO7 | TX2 | 7 (RX) | **UART2: la que usa el firmware** |
| 6 | ZED_RX2 ← 1 kΩ ← GPIO8 | RX2 | 8 (TX) | |
| 7 | ZED_PPS_C → 330 Ω → GPIO4 | PPS | 4 | marca de tiempo por interrupción |
| 8 | ZED_RST ← 1 kΩ ← GPIO9 | RST | 9 | solo se lleva a 0 (colector abierto) |

Las resistencias de 1 kΩ en serie limitan a ~3 mA por línea la alimentación parásita del ZED apagado a través de sus
entradas; además el firmware deja esas líneas a 0 mientras el ZED no tiene corriente.
No se conectan 5V (el ZED se alimenta a 3,3 V, como ahora), SDA/SCL, CS/SCK, FENCE, RTK, SAFE ni INT.

## Comprobaciones antes de hacer el mazo (con polímetro, URTK1.2 sin alimentar)
1. Continuidad **GND** de ambas columnas con la carcasa del SMA.
2. **3V3** de la columna izquierda con 3V3 de la derecha y con el pin VCC del ZED (pin 33 del módulo, si se llega).
3. **TX2/RX2 y TX/MISO**: con el ZED alimentado (3,3 V en 3V3), mirar con un adaptador USB-serie a 38400 bps que en
   TX2 y en TX/MISO salen tramas; RX2 y RX/MOSI son las entradas. Si se quiere comprobar contra el módulo, usar los
   números de pin de la hoja de datos del ZED-F9P-01B (UBX-17051259), no los de esta nota.
4. **PPS**: con fix 3D, un pulso por segundo (LED PPS de la placa parpadeando).
5. **Cara inferior**: medir la altura de lo que sobresalga (pines del SMA, patas de la pila, patillas del USB-C).
   La bandeja deja **1,2 mm** bajo la URTK1.2 (`RE["ZB"] − TRAY_Z1`): si algo sobresale más, se rebaja la bandeja.
6. **J1/J3/J6**: medir su posición y altura (el pisador del agujero −X −Y se ha apartado 1 mm del USB-C estimado).

## Firmware (BACK 4.0.0-dev1)
- ZED en UART2 (S3 UART1, GPIO7/8), detección automática de velocidad y puerto como en la 3.11.0.
- 8 Hz con GPS + GLONASS + Galileo + BeiDou, RTK fijo, modelo Airborne < 2 g (sin cambios respecto a la 3.8.0–3.11.0).
- Todo lo que envía el ZED se graba sin modificar en la microSD (`/AVO_nnnnnn.ubx`, abrible con u-center/RTKLIB).
- PPS: interrupción en el flanco de subida con `esp_timer` (resolución 1 µs); el monitor muestra periodo y desviación máxima.
- Pendiente (no hecho): activar UBX-RXM-RAWX/SFRBX por UART1 a 921600 para el registro RAW de posproceso.
