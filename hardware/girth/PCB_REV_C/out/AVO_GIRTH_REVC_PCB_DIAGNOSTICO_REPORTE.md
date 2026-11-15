# AVO GIRTH · placa de la cincha · REV C (ESP32-C6 + BNO085 + MAX30003, ECG) — informe de diagnóstico

- Estado: **DISEÑO INCOMPLETO** — no fabricar: hay comprobaciones bloqueantes sin superar
- Commit: `c0208699ce36ef4af8e1540a8e1d45ab45fea9c0` · ejecución de CI: 43665163106
- Ruteado: SIN RUTEAR (Freerouting no entregó resultado)
- Placa: 40 × 26 mm (R2), 4 capas (F.Cu componentes, señal y relleno GND · In1.Cu GND macizo · In2.Cu señal + relleno +3V3 · B.Cu señal y relleno GND), 1,0 mm, ENIG, cobre exterior 1 oz
- Componentes: 87 en total, 68 para montar, 3 sin montar (DNP: C51, C54, R46), 16 a mano (pads de hilo y de prueba)
- Pistas: 160 · vías: 71 · ruteado INCOMPLETO (130 conexiones)

## Comprobaciones bloqueantes
| Comprobación | Resultado | Cantidad |
|---|---|---|
| DRC: errores | correcto | 0 |
| DRC: conexiones incompletas | **FALLA** | 130 |
| DRC: cortocircuitos | correcto | 0 |
| DRC: paridad esquema ↔ placa | correcto | 0 |
| ERC: errores | correcto | 0 |
| ERC: advertencias | correcto | 0 |


### Conexiones incompletas
- Pad 13 [+1V8_ECG] of U6 on F.Cu ↔ Pad 1 [+1V8_ECG] of C43 on F.Cu
- Pad 5 [+1V8_ECG] of U7 on F.Cu ↔ Pad 1 [+1V8_ECG] of C41 on F.Cu
- Pad 5 [+1V8_ECG] of U7 on F.Cu ↔ Pad 1 [+1V8_ECG] of C43 on F.Cu
- Pad 22 [+1V8_ECG] of U6 on F.Cu ↔ Pad 13 [+1V8_ECG] of U6 on F.Cu
- Pad 1 [+1V8_ECG] of C42 on F.Cu ↔ Pad 22 [+1V8_ECG] of U6 on F.Cu
- Pad 1 [+3V3] of C40 on F.Cu ↔ Pad 3 [+3V3] of U7 on F.Cu
- Pad 3 [+3V3] of U7 on F.Cu ↔ Pad 1 [+3V3] of U7 on F.Cu
- Pad 4 [+3V3] of X1 on F.Cu ↔ Pad 1 [+3V3] of U7 on F.Cu
- Pad 4 [+3V3] of X1 on F.Cu ↔ Pad 1 [+3V3] of C55 on F.Cu
- Pad 2 [+3V3] of R47 on F.Cu ↔ Pad 19 [+3V3] of U6 on F.Cu
- Pad 2 [+3V3] of R47 on F.Cu ↔ Pad 1 [+3V3] of C30 on F.Cu
- Pad 1 [+3V3] of C44 on F.Cu ↔ Pad 1 [+3V3] of C55 on F.Cu
- Pad 1 [+3V3] of C32 on F.Cu ↔ Pad 2 [+3V3] of R22 on F.Cu
- Pad 1 [+3V3] of C32 on F.Cu ↔ Pad 1 [+3V3] of C44 on F.Cu
- Pad 1 [+3V3] of C45 on F.Cu ↔ Pad 1 [+3V3] of C31 on F.Cu
- Pad 1 [+3V3] of C45 on F.Cu ↔ Pad 1 [+3V3] of C30 on F.Cu
- Pad 1 [+3V3] of C30 on F.Cu ↔ Pad 2 [+3V3] of R22 on F.Cu
- Pad 1 [+3V3] of C22 on F.Cu ↔ Pad 1 [+3V3] of C44 on F.Cu
- Pad 3 [+3V3] of U5 on F.Cu ↔ Pad 2 [+3V3] of R22 on F.Cu
- Pad 3 [+3V3] of U5 on F.Cu ↔ Pad 28 [+3V3] of U5 on F.Cu
- Pad 5 [+3V3] of U3 on F.Cu ↔ Pad 2 [+3V3] of R21 on F.Cu
- Pad 5 [+3V3] of U3 on F.Cu ↔ Pad 2 [+3V3] of R31 on F.Cu
- Pad 2 [+3V3] of R31 on F.Cu ↔ Pad 1 [+3V3] of C22 on F.Cu
- Pad 2 [+3V3] of R24 on F.Cu ↔ Pad 2 [+3V3] of R31 on F.Cu
- Pad 2 [+3V3] of R27 on F.Cu ↔ Pad 2 [+3V3] of R24 on F.Cu
- Pad 2 [+3V3] of R27 on F.Cu ↔ Pad 2 [+3V3] of R12 on F.Cu
- Pad 2 [+3V3] of R29 on F.Cu ↔ Pad 2 [+3V3] of R30 on F.Cu
- Pad 2 [+3V3] of R29 on F.Cu ↔ Pad 2 [+3V3] of R25 on F.Cu
- Pad 2 [+3V3] of R30 on F.Cu ↔ Pad 1 [+3V3] of TP6 on F.Cu
- Pad 2 [+3V3] of R28 on F.Cu ↔ Pad 2 [+3V3] of R25 on F.Cu
- Pad 2 [+3V3] of R28 on F.Cu ↔ Pad 2 [+3V3] of R27 on F.Cu
- Pad 2 [+3V3] of R10 on F.Cu ↔ Pad 2 [+3V3] of R12 on F.Cu
- Pad 1 [+3V3] of R14 on F.Cu ↔ Pad 2 [+3V3] of R11 on F.Cu
- Pad 2 [+3V3] of R11 on F.Cu ↔ Pad 1 [+3V3] of C24 on F.Cu
- Pad 2 [+3V3] of R11 on F.Cu ↔ Pad 2 [+3V3] of R30 on F.Cu
- Pad 1 [+3V3] of C24 on F.Cu ↔ Pad 1 [+3V3] of C25 on F.Cu
- Pad 1 [+3V3] of C24 on F.Cu ↔ Pad 3 [+3V3] of U4 on F.Cu
- Pad 52 [GND] of U4 on F.Cu ↔ Pad 14 [GND] of U4 on F.Cu
- Pad 51 [GND] of U4 on F.Cu ↔ Via [GND] on F.Cu - B.Cu
- Pad 11 [GND] of U4 on F.Cu ↔ Pad 52 [GND] of U4 on F.Cu
- Track [GND] on F.Cu, length 0.0071 mm ↔ Pad 11 [GND] of U4 on F.Cu
- Pad 49 [GND] of U4 on F.Cu ↔ Via [GND] on F.Cu - B.Cu
- Pad 49 [GND] of U4 on F.Cu ↔ Via [GND] on F.Cu - B.Cu
- Via [GND] on F.Cu - B.Cu ↔ Pad 49 [GND] of U4 on F.Cu
- Via [GND] on F.Cu - B.Cu ↔ Pad 49 [GND] of U4 on F.Cu
- Via [GND] on F.Cu - B.Cu ↔ Pad 49 [GND] of U4 on F.Cu
- Via [GND] on F.Cu - B.Cu ↔ Pad 49 [GND] of U4 on F.Cu
- Via [GND] on F.Cu - B.Cu ↔ Pad 49 [GND] of U4 on F.Cu
- Via [GND] on F.Cu - B.Cu ↔ Pad 49 [GND] of U4 on F.Cu
- Pad 49 [GND] of U4 on F.Cu ↔ Via [GND] on F.Cu - B.Cu
- Pad 47 [GND] of U4 on F.Cu ↔ Pad 48 [GND] of U4 on F.Cu
- Pad 44 [GND] of U4 on F.Cu ↔ Track [GND] on F.Cu, length 0.0354 mm
- Pad 44 [GND] of U4 on F.Cu ↔ Pad 45 [GND] of U4 on F.Cu
- Pad 41 [GND] of U4 on F.Cu ↔ Pad 40 [GND] of U4 on F.Cu
- Pad 40 [GND] of U4 on F.Cu ↔ Pad 39 [GND] of U4 on F.Cu
- Pad 39 [GND] of U4 on F.Cu ↔ Pad 38 [GND] of U4 on F.Cu
- Pad 38 [GND] of U4 on F.Cu ↔ Pad 37 [GND] of U4 on F.Cu
- Pad 37 [GND] of U4 on F.Cu ↔ Pad 36 [GND] of U4 on F.Cu
- Pad 36 [GND] of U4 on F.Cu ↔ Pad 50 [GND] of U4 on F.Cu
- Via [GND] on F.Cu - B.Cu ↔ Pad 47 [GND] of U4 on F.Cu
- Via [GND] on F.Cu - B.Cu ↔ Pad 41 [GND] of U4 on F.Cu
- Pad 2 [VBAT] of U2 on F.Cu ↔ Pad 1 [VBAT] of C20 on F.Cu
- Pad 3 [VBAT] of U2 on F.Cu ↔ Pad 2 [VBAT] of U2 on F.Cu
- Pad 3 [VBAT] of U2 on F.Cu ↔ Pad 2 [VBAT] of F1 on F.Cu
- Pad 1 [VBAT] of TP7 on F.Cu ↔ Pad 1 [VBAT] of C20 on F.Cu
- Pad 2 [VBAT] of F1 on F.Cu ↔ Pad 1 [VBAT] of R32 on F.Cu
- Pad 2 [VBUS] of F2 on F.Cu ↔ Pad 13 [VBUS] of U2 on F.Cu
- Pad 13 [VBUS] of U2 on F.Cu ↔ Pad 1 [VBUS] of C18 on F.Cu
- Pad 1 [VBUS] of TP8 on F.Cu ↔ Pad 1 [VBUS] of C18 on F.Cu
- Pad 1 [VSYS] of U3 on F.Cu ↔ Pad 1 [VSYS] of C21 on F.Cu
- Pad 3 [VSYS] of U3 on F.Cu ↔ Pad 1 [VSYS] of U3 on F.Cu
- Pad 3 [VSYS] of U3 on F.Cu ↔ Pad 2 [VSYS] of R8 on F.Cu
- Pad 2 [VSYS] of R8 on F.Cu ↔ Pad 10 [VSYS] of U2 on F.Cu
- Pad 10 [VSYS] of U2 on F.Cu ↔ Pad 11 [VSYS] of U2 on F.Cu
- Pad 1 [VSYS] of C19 on F.Cu ↔ Pad 10 [VSYS] of U2 on F.Cu
- Pad 10 [BAT_ADC] of U4 on F.Cu ↔ Pad 1 [BAT_ADC] of R33 on F.Cu
- Pad 1 [BAT_ADC] of C34 on F.Cu ↔ Pad 10 [BAT_ADC] of U4 on F.Cu
- Pad 1 [BAT_ADC] of R33 on F.Cu ↔ Pad 2 [BAT_ADC] of R32 on F.Cu
- PTH pad 1 [BAT_IN] of J2 ↔ Pad 1 [BAT_IN] of F1 on F.Cu
- Pad 1 [BOOT] of TP2 on F.Cu ↔ Pad 1 [BOOT] of R12 on F.Cu
- Pad 1 [BOOT] of R12 on F.Cu ↔ Pad 23 [BOOT] of U4 on F.Cu
- Track [CHG_STAT] on F.Cu, length 0.5657 mm ↔ Pad 22 [CHG_STAT] of U4 on F.Cu
- Pad 1 [DET] of R21 on F.Cu ↔ Pad 2 [DET] of R20 on F.Cu
- Pad 15 [DET] of U4 on F.Cu ↔ Pad 1 [DET] of R21 on F.Cu
- Pad 2 [ECGN] of C54 on F.Cu ↔ Pad 7 [ECGN] of U6 on F.Cu
- Pad 7 [ECGN] of U6 on F.Cu ↔ Pad 2 [ECGN] of R41 on F.Cu
- Pad 7 [ECGN] of U6 on F.Cu ↔ Pad 1 [ECGN] of C53 on F.Cu
- Pad 2 [ECGP] of R40 on F.Cu ↔ Pad 1 [ECGP] of C54 on F.Cu
- Pad 2 [ECGP] of R40 on F.Cu ↔ Pad 6 [ECGP] of U6 on F.Cu
- Pad 1 [ECGP] of C54 on F.Cu ↔ Pad 1 [ECGP] of C52 on F.Cu
- Pad 15 [ECG_CS] of U6 on F.Cu ↔ Pad 30 [ECG_CS] of U4 on F.Cu
- Pad 1 [ECG_E_N] of R41 on F.Cu ↔ PTH pad 1 [ECG_E_N] of P6
- PTH pad 1 [ECG_E_P] of P4 ↔ Pad 1 [ECG_E_P] of R40 on F.Cu
- PTH pad 1 [ECG_E_REF] of P5 ↔ Pad 1 [ECG_E_REF] of R42 on F.Cu
- Pad 3 [ECG_FCLK] of X1 on F.Cu ↔ Pad 2 [ECG_FCLK] of R46 on F.Cu
- Pad 2 [ECG_FCLK] of R46 on F.Cu ↔ Pad 14 [ECG_FCLK] of U6 on F.Cu
- Pad 1 [ECG_FCLK_MCU] of R46 on F.Cu ↔ Pad 9 [ECG_FCLK_MCU] of U4 on F.Cu
- Pad 21 [ECG_INTB] of U6 on F.Cu ↔ Pad 1 [ECG_INTB] of R47 on F.Cu
- Pad 1 [ECG_INTB] of R47 on F.Cu ↔ Pad 16 [ECG_INTB] of U4 on F.Cu
- Pad 18 [ECG_MISO] of U6 on F.Cu ↔ Pad 26 [ECG_MISO] of U4 on F.Cu
- Pad 17 [ECG_MOSI] of U6 on F.Cu ↔ Pad 24 [ECG_MOSI] of U4 on F.Cu
- Pad 16 [ECG_SCK] of U6 on F.Cu ↔ Pad 25 [ECG_SCK] of U4 on F.Cu
- Pad 8 [EN] of U4 on F.Cu ↔ Pad 1 [EN] of R11 on F.Cu
- Pad 1 [EN] of C27 on F.Cu ↔ Pad 1 [EN] of TP1 on F.Cu
- Pad 1 [EN] of R11 on F.Cu ↔ Pad 1 [EN] of C27 on F.Cu
- Pad 1 [IMU_BOOTN] of R22 on F.Cu ↔ Pad 4 [IMU_BOOTN] of U5 on F.Cu
- Pad 1 [IMU_CS] of R25 on F.Cu ↔ Pad 18 [IMU_CS] of U5 on F.Cu
- Pad 27 [IMU_CS] of U4 on F.Cu ↔ Pad 1 [IMU_CS] of R25 on F.Cu
- Pad 15 [IMU_ENV_SCL] of U5 on F.Cu ↔ Pad 1 [IMU_ENV_SCL] of R27 on F.Cu
- Pad 16 [IMU_ENV_SDA] of U5 on F.Cu ↔ Pad 1 [IMU_ENV_SDA] of R28 on F.Cu
- Pad 14 [IMU_INT] of U5 on F.Cu ↔ Pad 1 [IMU_INT] of R31 on F.Cu
- Pad 5 [IMU_INT] of U4 on F.Cu ↔ Pad 14 [IMU_INT] of U5 on F.Cu
- Pad 6 [IMU_PS0] of U5 on F.Cu ↔ Pad 1 [IMU_PS0] of R23 on F.Cu
- Pad 12 [IMU_PS0] of U4 on F.Cu ↔ Pad 6 [IMU_PS0] of U5 on F.Cu
- Pad 11 [IMU_RST] of U5 on F.Cu ↔ Pad 1 [IMU_RST] of R24 on F.Cu
- Pad 13 [IMU_RST] of U4 on F.Cu ↔ Pad 11 [IMU_RST] of U5 on F.Cu
- Pad 17 [IMU_SA0] of U5 on F.Cu ↔ Pad 1 [IMU_SA0] of R26 on F.Cu
- Pad 1 [IMU_SA0] of R26 on F.Cu ↔ Pad 28 [IMU_SA0] of U4 on F.Cu
- Pad 1 [IMU_SCL] of R29 on F.Cu ↔ Pad 19 [IMU_SCL] of U5 on F.Cu
- Pad 31 [IMU_SCL] of U4 on F.Cu ↔ Pad 1 [IMU_SCL] of R29 on F.Cu
- Pad 20 [IMU_SDA] of U5 on F.Cu ↔ Pad 29 [IMU_SDA] of U4 on F.Cu
- Pad 1 [IMU_SDA] of R30 on F.Cu ↔ Pad 20 [IMU_SDA] of U5 on F.Cu
- Pad 2 [LED_A] of D1 on F.Cu ↔ Pad 2 [LED_A] of R14 on F.Cu
- Pad 20 [LED_K] of U4 on F.Cu ↔ Pad 1 [LED_K] of D1 on F.Cu
- Pad 1 [POGO_5V] of F2 on F.Cu ↔ Pad 1 [POGO_5V] of D2 on F.Cu
- PTH pad 1 [POGO_5V] of P1 ↔ Pad 1 [POGO_5V] of F2 on F.Cu
- Pad 1 [POGO_DET] of D3 on F.Cu ↔ PTH pad 1 [POGO_DET] of P3
- PTH pad 1 [POGO_DET] of P3 ↔ Pad 1 [POGO_DET] of R20 on F.Cu
- Pad 1 [USB_DM] of TP4 on F.Cu ↔ Pad 17 [USB_DM] of U4 on F.Cu
- Pad 1 [USB_DP] of TP5 on F.Cu ↔ Pad 18 [USB_DP] of U4 on F.Cu

## Advertencias de DRC (no bloqueantes)
- silk_over_copper: 6
- via_dangling: 4
- silk_overlap: 3

## Lista de materiales y posiciones
- Piezas montadas sin número LCSC: ninguna
- Los ficheros BOM y CPL se generan desde la misma lista que el esquema y la placa (`kicad/piezas.json`).
- Revisar el giro de cada pieza en la vista previa de JLCPCB: el CPL sale de KiCad sin correcciones.

## Modelo 3D (STEP y renders, no afecta a la fabricación)
- Modelos de la librería de KiCad 9.0.0 descargados: 10; sin descargar: Package_DFN_QFN.3dshapes/VQFN-16-1EP_3x3mm_P0.5mm_EP1.68x1.68mm.step
- ESP32-C6-MINI-1U: modelo de Espressif (`fuente/3d`). MAX30003 y SiT1533: modelos de EasyEDA/LCSC. BNO085 y pads de hilo/prueba: sin modelo 3D.

## Estado de fabricación
- Diseño verificado por software (KiCad 9 en el CI): **no**
- Apto para solicitar prototipos: **no**
- Validado físicamente: **no** (no se ha fabricado ni medido ninguna placa)

## Limitaciones pendientes (ver README)
- MAX30003CTI+ sin existencias en LCSC el 15/11/2026: pedirlo por Global Sourcing de JLCPCB o enviarlo (Mouser/DigiKey).
- MAX30003: rango comercial 0–70 °C (hoja de ADI); suficiente para el entrenamiento, no para frío extremo.
- BNO085 por I²C (0x4A) con los mismos GPIO que el XIAO: el firmware 0.5.0 sirve sin cambios; ejes de la placa a comprobar.
- Oscilador SiT1533 con la huella de EasyEDA/LCSC: si falta, montar R46 (0 Ω) y el firmware genera el reloj en GPIO4.
- Electrodos: 49,9 kΩ en serie + 1 nF C0G; paso alto analógico ≈ 3,5 Hz (C50 100 nF C0G); C51 1 µF sin montar para 0,35 Hz.
- Primera programación por los pads TP4/TP5 (USB nativo) con pinza de pogo-pins; después por radio.
- Pogos de 3 contactos y batería LP403048 por hilos; cápsula REV 6 (más pequeña) pendiente de CAD.
- Nada de esto se ha fabricado ni medido: no es un prototipo validado.
