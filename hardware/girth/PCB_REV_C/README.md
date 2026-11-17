# AVO GIRTH · PCB de la cincha REV C (ECG) — 15/11/2026

PCB propia y compacta de la cincha, como la del casco V5: sustituye al XIAO ESP32-C6, al módulo GY-BNO08X y al
módulo CJMCU-30003 por los mismos chips soldados en una sola placa.

**Estado:** ver `out/AVO_GIRTH_REVC_PCB_REPORTE.md` (puerta superada) o `out/AVO_GIRTH_REVC_PCB_DIAGNOSTICO_REPORTE.md`.
**No fabricada. No verificada en hardware.**

## Placa
- **40 × 26 mm**, esquinas R2, 4 capas, **1,0 mm**, ENIG. 4 taladros Ø2,2 (tornillos M2 a la tapa) en (±17,8, ±10,8).
- **Todos los componentes en la cara F** (hacia la tapa, altura máx. 2,6 mm). La cara B apoya sobre la batería.
- In1 = GND macizo · F, In2 y B = señales · rellenos GND en F y B, +3V3 en In2.
- Arquitectura y GPIO: `DOCS/INFORME_PCB_REV_C.md`.

## Bloques
- **ESP32-C6-MINI-1U-N4** (13,2 × 12,5), antena FPC en el U.FL hacia el canto +X. Mismos GPIO que el XIAO: el
  firmware **AVO GIRTH 0.5.0** funciona sin cambios.
- **BNO085** soldado, por I²C (0x4A), cristal de 32,768 kHz, en el centro de la placa.
- **MAX30003** con 1,8 V propio (RT9080-18), oscilador MEMS SiT1533 en FCLK, filtros de entrada en los electrodos.
- **Cargador BQ24072** (247 mA para la LP403048 de 500 mAh), PTC en la batería y en el contacto de 5 V, 3,3 V RT9080-33.
- **Pogos por hilos** (pads pasantes): carga P1 5V · P2 GND · P3 DET; electrodos P4 ECG + · P5 REF · P6 ECG −;
  batería J2 + · J6 −.
- **Programación:** pads TP4 (D−), TP5 (D+), TP8 (5 V), TP3 (GND), TP2 (BOOT), TP1 (EN): USB nativo del C6 con una
  pinza de pogo-pins, la primera vez. Después, por radio.

## Fuente
`fuente/avo_girth_revc_pcb.py` (piezas y redes) → `fuente/place_revc.py` (colocación) → `fuente/build.py` (placa de
colocación + esquema) → CI `build-girth-pcb-revc.yml` (Freerouting, DRC/ERC, puerta, ficheros JLCPCB). Las huellas del
MAX30003 y del SiT1533 salen de EasyEDA/LCSC (`easyeda-fp-girth-revc.yml`); la del BNO085 coincide con la de EasyEDA.

## Pendiente antes de pedir
- **MAX30003CTI+** y **BNO085** sin existencias en JLCPCB el 15/11/2026: Global Sourcing o piezas enviadas.
- Código JLCPCB del ESP32-C6-MINI-1U-N4 (el C7558096 de la REV A sale sin existencias): ver `out_stock`.
- Cápsula REV 6 (más pequeña) en FreeCAD alrededor de esta placa y de la LP403048.
