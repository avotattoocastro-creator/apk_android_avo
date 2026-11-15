# AVO DOCK V1 · soporte de pared cargador (2 cascos + 2 cinchas)

**Estado (15/11/2026):**
- Diseño **IMPLEMENTADO**. La PCB y la caja se generan en el CI.
- Nada fabricado: **NO VERIFICADO** en hardware.
- Sin firmware todavía. Esta revisión solo cubre la PCB y la caja.

## Decisiones del usuario (15/11/2026)
| Tema | Decisión |
|---|---|
| Cinchas | Pogo de 3 contactos de la REV 5.9.1: 1 = +5 V · 2 = GND · 3 = MTCK (GPIO6 de la cápsula) |
| Cascos (BACK V5) | Pogo de 5 contactos: VBUS · D− · D+ · GND · AUX. Hub USB + ESP32-S3 en el soporte |
| 220 V | Módulo AC-DC certificado encapsulado en la PCB (Mean Well IRM-20-5) + USB-C de 5 V |
| Git | Rama corta `claude/dock-cargador-v1`, que sale de `develop/avo-performance-horse` |

## Qué hace
- **Carga** 2 cascos y 2 cinchas a la vez, con la red (230 V~) o con el USB-C de un PC.
  - Con red tiene prioridad la red. Con solo el USB-C, el firmware reparte la corriente según lo que anuncie el PC por CC (0,5 / 1,5 / 3 A).
- **Pantalla** IPS de 2,0" con la batería de las 4 cápsulas y su estado (cargando, completa, sin cápsula o fallo).
- **Modo PC** (USB-C conectado): el PC ve los 2 cascos a través del hub, igual que con su cable magnético. Además ve el propio soporte como puerto serie (CDC) para enlazarlo con la app y actualizarlo.
- **Modo autónomo** (sin PC): el ESP32-S3 hace de anfitrión USB, lee los entrenamientos de los cascos por el hub y los sirve a la app por **Wi-Fi** (descarga) y por **BLE** (estado y emparejamiento).

## Diagrama de bloques
```
230 V~ ─ prensaestopas M12 ─ fusible T1A ─ varistor ─ IRM-20-5 ─┐   (ZONA DE RED + FOSO 6,5 mm)
                                                                ├─ selector (PMOS, prioridad red) ─ 5V_SYS ─┬─ AMS1117 ─ 3V3
USB-C (PC) ─ PTC 1,5 A ─ ESD ──────────────────────── VBUS_PC ──┘                                           │
USB-C D± ─ TS3USB221 (U4) ─ hub USB2514B ─ DN1 ─ casco A (pogo 5)   DN2 ─ casco B   DN3 ─ U5 ─ ESP32-S3 (GPIO19/20)
                  └─────────── S3H (S3 anfitrión) ──────────────────────────────────┘
5V_SYS ─ TPS2553 + 50 mΩ + INA180 ─ ×4 ─ casco A · casco B · cincha A · cincha B
ESP32-S3: pantalla ST7789 (SPI) · pulsador · 4 ADC de corriente · ADC de 5V_SYS, VBUS, CC1/CC2 y red · línea MTCK de las cinchas · AUX de los cascos
```

## Puertos
| Puerto | Contactos | Límite (TPS2553) | Datos | Batería en pantalla |
|---|---|---|---|---|
| Casco A/B | VBUS · D− · D+ · GND · AUX | ≈ 1,0 A (R_ILIM 24,9 k) | USB del hub (velocidad completa) | por USB: el firmware BACK 5.x tiene que dar el % (dato nuevo, ver «Pendiente») |
| Cincha A/B | +5 V · GND · MTCK | ≈ 0,5 A (R_ILIM 49,9 k) | 1 hilo semidúplex por MTCK (1 k + 1 k en serie, 47 k a 3,3 V en el soporte) | por la línea MTCK (firmware GIRTH nuevo) |

- **Sin firmware en las cápsulas**, la pantalla muestra lo que mide el soporte con los INA180:
  - *cargando* (corriente de más de 30 mA);
  - *completa* (la corriente cae por debajo de unos 30 mA con la cápsula puesta);
  - *sin cápsula* (0 mA).
- **AUX del casco:** el soporte lo pone a 3,3 V por 1 k. El casco (GPIO40) sabe así que está en el soporte de pared y no en el casco del jinete.
- **MTCK de la cincha:** en el soporte la línea queda en alto (47 k), que es lo contrario del puente a GND del soporte del caballo.
  - Con el reposo activado, la GIRTH 0.6.0 se duerme a los 30 s.
  - Para hablar con ella, el soporte baja la línea (la despierta) y luego usa la línea como UART semidúplex.

## Conexiones del ESP32-S3-MINI-1U-N8
| GPIO | Función | GPIO | Función |
|---|---|---|---|
| 0 | BOOT (TP2) | 17 / 18 | EN casco A / B |
| 1 / 2 | corriente casco A / B (INA180) | 19 / 20 | USB D− / D+ (por U5) |
| 4 / 5 | corriente cincha A / B | 21 / 47 | EN cincha A / B |
| 6 | 5V_SYS (divisor 1:2) | 33 / 34 | FAULT cascos / cinchas |
| 7 | VBUS del PC (divisor 1:2) | 35 / 36 | MTCK cincha A / B |
| 8 / 9 | CC1 / CC2 del USB-C | 37 | RESET_N del hub |
| 10 | red presente (divisor 1:2) | 38 | VBUS_DET del hub (forzado) |
| 11–16 | pantalla: MOSI, SCK, CS, DC, RST, BL | 39 | USB_SEL (0 = PC, 1 = autónomo) |
| 48 | pulsador | 40 / 41 | AUX casco A / B |

- **USB_SEL** tiene 100 k a GND, así que el soporte arranca en **modo PC**.
- El hub queda en marcha por defecto (10 k a 3,3 V en RESET_N).
- Con un firmware estropeado, el soporte se sigue programando desde el PC por el puerto 3 del hub, con el USB-Serial-JTAG del S3.

## Seguridad eléctrica (230 V)
- El aislamiento lo da el **IRM-20-5 certificado**: clase II, 3000 VAC de entrada a salida, con IEC/EN 62368-1.
- En la PCB:
  - **zona de red** en la esquina −X/+Y, con un **foso de 6,5 mm** sin cobre en las 4 capas (zona de exclusión de KiCad);
  - pistas de red de 1,0 mm, solo en F.Cu, con 2,5 mm entre L y N.
- El generador comprueba que ningún pad de MBTS cae en la zona de red ni en el foso.
- **Caja de clase II:** PETG, sin partes metálicas accesibles y sin tierra.
  - El cable es de 2 × 0,75 mm² con doble aislamiento.
  - Entra por un prensaestopas M12 y lleva una brida interior.
  - Los hilos de red se sueldan a J1/J2 y se fijan con brida.
- Fusible lento de 1 A en la fase y varistor de 275 VAC tras el fusible.
- **No es un producto certificado.** Para venderlo hace falta un ensayo CE (LVD/EMC). Como prototipo de taller, que lo monte y lo revise una persona cualificada.

## Caja (CAD)
- 200 × 190 × 55 mm, en 2 piezas de PETG:
  - **fondo** (z 0–35): ojales de cerradura para colgar, pilares de la PCB, prensaestopas, USB-C en el lateral derecho y rejillas;
  - **frente** (z 35–55): alojamientos, pantalla y pulsador.
- Las 2 piezas caben en la Centauri Carbon (256 × 256).
- **Cascos:** alojamiento de 57,0 × 57,0 × 6 mm.
  - 4 imanes Ø6 × 2 N52 frente a los de la cápsula, con 0,3 de piel.
  - Pogo de muelles de 5 contactos empotrado, con la cara a ras del fondo (E).
  - **Sin imán para el Hall:** el casco no se enciende al ponerlo. Lo despierta el VBUS.
- **Cinchas:** alojamiento de 70,6 × 53,6 × 5 mm.
  - Admite la REV 5.9.1 (70 × 51) y la REV 5.10 (70 × 53).
  - 4 × (2 × Ø5 × 1) imanes con la polaridad del soporte del caballo.
  - Pogo de 3 contactos del STEP real, a y = −19,95, a medio camino entre las dos revisiones.
- Cada alojamiento lleva una muesca para el dedo arriba. Las cápsulas cuelgan con el pogo abajo.

## Pendiente (antes de fabricar)
1. **Códigos LCSC** de TPS2553DBVR, INA180A2IDBVR, TS3USB221ADRCR, cristal de 24 MHz 3225, JST SM08B-GHS-TB y shunt de 50 mΩ 0805: buscarlos con un workflow de existencias.
2. **STEP real del pogo de 5 contactos** del casco: el alojamiento y la PCB del casco usan medidas estimadas.
3. **Módulo de pantalla:** confirmar las medidas del que se compre (vidrio, zona visible y orden de pines del cable).
4. **Firmware DOCK 0.1.0** (ESP-IDF ≥ 5.4, porque necesita hub en el anfitrión USB): pantalla, puertos, modos PC y autónomo, BLE y Wi-Fi.
5. **Contrato nuevo `DockStatus v1`** (BLE/Wi-Fi/CDC). Se define y se implementa **a la vez** en el firmware y en Android, Windows e iPad, como pide la norma de contratos.
6. **Firmware de las cápsulas:**
   - BACK 5.x: % de batería por USB y AUX = «en el soporte de pared»;
   - GIRTH 0.7: protocolo por MTCK y **montar el divisor de batería en GPIO5** (hoy no está montado).
