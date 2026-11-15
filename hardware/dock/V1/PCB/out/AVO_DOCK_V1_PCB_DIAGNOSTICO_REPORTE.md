# AVO DOCK V1 · soporte de pared cargador (2 cascos + 2 cinchas) · REV A — informe de diagnóstico

- Estado: **DISEÑO INCOMPLETO** — no fabricar: hay comprobaciones bloqueantes sin superar
- Commit: `ca07540d165b3b0749d615a79011c045c52de24a` · ejecución de CI: 43775448748
- Ruteado: Freerouting 1.9.0 sobre la placa de colocación (sin reparar)
- Placa: 130 × 76 mm (R3), 4 capas (F.Cu componentes y señal · In1.Cu GND · In2.Cu señal + relleno +3V3 · B.Cu plano GND, sin pistas), 1,6 mm, ENIG, cobre exterior 1 oz · zona de red 230 V con foso de 6,5 mm
- Componentes: 157 en total, 128 para montar, 0 sin montar (DNP: —), 29 a mano (pads de hilo y de prueba)
- Pistas: 1564 · vías: 261 · ruteado INCOMPLETO (12 conexiones)

## Comprobaciones bloqueantes
| Comprobación | Resultado | Cantidad |
|---|---|---|
| DRC: errores | correcto | 0 |
| DRC: conexiones incompletas | **FALLA** | 12 |
| DRC: cortocircuitos | correcto | 0 |
| DRC: paridad esquema ↔ placa | correcto | 0 |
| ERC: errores | correcto | 0 |
| ERC: advertencias | correcto | 0 |


### Conexiones incompletas
- Track [+3V3] on F.Cu, length 0.0612 mm ↔ Track [+3V3] on F.Cu, length 0.3000 mm
- Pad 36 [+3V3] of U6 on F.Cu ↔ Track [+3V3] on F.Cu, length 0.0849 mm
- Pad 1 [VBUS_PC] of TP9 on F.Cu ↔ Pad 5 [VBUS_PC] of U1 on F.Cu
- Pad 6 [HUB_DN3_DM] of U6 on F.Cu ↔ Pad 2 [HUB_DN3_DM] of U5 on F.Cu
- Pad 1 [HUB_LOCALPWR] of R24 on F.Cu ↔ Pad 28 [HUB_LOCALPWR] of U6 on F.Cu
- Pad 34 [HUB_PLLFILT] of U6 on F.Cu ↔ Pad 1 [HUB_PLLFILT] of C28 on F.Cu
- Pad 31 [HUB_UP_DP] of U6 on F.Cu ↔ Pad 8 [HUB_UP_DP] of U4 on F.Cu
- Pad 8 [S3_DP_R] of U5 on F.Cu ↔ Pad 2 [S3_DP_R] of R15 on F.Cu
- Pad A4 [VBUS_C_RAW] of J3 on F.Cu ↔ Track [VBUS_C_RAW] on F.Cu, length 1.8968 mm
- Pad A4 [VBUS_C_RAW] of J3 on F.Cu ↔ Pad A9 [VBUS_C_RAW] of J3 on F.Cu
- Track [XTAL_I] on F.Cu, length 0.3375 mm ↔ Pad 33 [XTAL_I] of U6 on F.Cu
- Track [XTAL_O] on F.Cu, length 0.6583 mm ↔ Pad 32 [XTAL_O] of U6 on F.Cu

## Advertencias de DRC (no bloqueantes)
- silk_edge_clearance: 8
- silk_overlap: 6
- silk_over_copper: 5

## Lista de materiales y posiciones
- Piezas montadas sin número LCSC: F1, RV1, PS1, C4, U4, U5, Y1, U10, R40, R48, U14, U11, R41, R49, U15, U12, R42, R50, U16, U13, R43, R51, U17, J4
- Los ficheros BOM y CPL se generan desde la misma lista que el esquema y la placa (`kicad/piezas.json`).
- Revisar el giro de cada pieza en la vista previa de JLCPCB: el CPL sale de KiCad sin correcciones.

## Modelo 3D (STEP y renders, no afecta a la fabricación)
- Modelos de la librería de KiCad 9.0.0 descargados: 18; sin descargar: Connector_USB.3dshapes/USB_C_Receptacle_HRO_TYPE-C-31-M-12.step, Fuse.3dshapes/Fuse_Littelfuse_372_D8.50mm.step
- ESP32-S3-MINI-1U: modelo de Espressif (`fuente/3d`). Pads de hilo/prueba: sin modelo 3D.

## Diseño de la REV A (texto fijo)
- Arquitectura, conexiones del ESP32-S3, puertos y seguridad eléctrica: `hardware/dock/V1/DOCS/ARQUITECTURA.md`.
- **Selector de alimentación:**
  - con red: Q1 y Q1B (AO3401A en paralelo) conducen y Q2 queda apagado;
  - sin red: conduce Q2 desde el USB-C;
  - el diodo interno de cada PMOS impide alimentar el IRM al revés y devolver corriente al PC.
- **Puertos:** TPS2553 con el EN en el S3 (100 k a GND: apagados al arrancar) → shunt de 50 mΩ → contacto, con INA180A2 (× 50; 1 A = 2,5 V).
- **Hub USB2514B** configurado por patillas: CFG_SEL = 00, LOCAL_PWR = 1, NON_REM = 00, puerto 4 desactivado. La potencia de los puertos la manda el S3, no PRTPWR.

## Estado de fabricación
- Diseño verificado por software (KiCad 9 en el CI): **no**
- Apto para solicitar prototipos: **no**
- Validado físicamente: **no** (no se ha fabricado ni medido ninguna placa)

## Limitaciones pendientes (ver README)
- Red 230 V: IRM-20-5, fusible, varistor y bornes de hilo se montan a mano (sin LCSC). Foso de 6,5 mm sin cobre en las 4 capas entre la zona de red y la MBTS: comprobar las distancias en el visor de Gerber antes de pedir.
- El aislamiento reforzado lo da el IRM-20-5 certificado (3000 VAC); la caja debe ser de clase II (sin partes metálicas accesibles) y el cable de red con brida dentro de la caja.
- Piezas sin código LCSC en esta revisión (TPS2553, INA180A2, TS3USB221, cristal de 24 MHz, JST-GH, shunts de 50 mΩ): buscarlas con el workflow de existencias antes de pedir.
- Patillaje del USB2514B-I/M2 (QFN-36 heredado, almohadilla 3,7 mm) según DS00001692: revisar con la hoja de la versión SQFN si se compra esa.
- USB entre el hub y los cascos a velocidad completa (12 Mbit/s, USB nativo del ESP32-S3): sin control de impedancia.
- Pogo de 5 contactos del casco: el modelo real sigue pendiente (STEP).
- Nada de esto se ha fabricado ni medido: no es un prototipo validado.
