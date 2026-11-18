# AVO BACK V5 CASCO · PROTOTIPO A (URTK1.2 por tiras de pines)

**Decisión del usuario (18/11/2026):** antes de pagar la BETA con el ZED-F9P soldado (`../V5_CASCO`, REV B, ≈ 500 € por
el mínimo de 2 placas montadas), se prueba un **casco prototipo** con la misma electrónica pero con el GNSS en una placa
**URTK1.2** (ZED-F9P-04B, la misma del prototipo de la espalda) soldada encima. Si las pruebas son buenas se aprueba
este prototipo o se pasa a la REV B con el ZED integrado como BETA final.

**Estado:** NO VERIFICADO. Diseño en CI; nada fabricado ni impreso. Las cotas de la URTK1.2 salen del plano del anuncio
(y de `../V4/DOCS/INTEGRACION_GNSS.md`): **hay que medirlas con calibre antes de pedir** (ver «Comprobaciones»).

## Qué cambia frente a la REV B (`../V5_CASCO`)

| | REV B (BETA) | PROTOTIPO A |
|---|---|---|
| GNSS | ZED-F9P soldado (LGA), RF de antena en la placa | **URTK1.2** soldada sobre la cara B con 2 tiras de pines (9 + 10, paso 2,54, plástico 2,5 mm) |
| Antena | sobre la cara B de la PCB (plano 51 × 51) | sobre la URTK1.2, encima de una **placa de masa de 52 × 52 × 0,8** (cobre macizo), al U.FL J4 de la URTK1.2 |
| PCB | 51 × 51, tornillos a ±22 | **56 × 56, tornillos a ±24,5** (la URTK1.2 tapaba los de ±22) |
| Cápsula | 56,4 × 56,4 × 24,7 | **61,4 × 61,4 × ≈ 32,1** (≈ 35,6 sobre el casco) — estimado; el CI da la cifra exacta |
| Arranque en caliente del ZED | V_BCKP desde el carril siempre encendido | pila de respaldo de la URTK1.2 (J6) |
| Piezas quitadas | — | U1, R70, C71, L70, R71, D4, J5, C62, C64, C65 y el paso del coaxial H5 |
| Colocación | microSD a la derecha, pogo en el canto inferior | **WROOM en el centro-izquierda, microSD abajo en el centro (tarjeta por el canto inferior, entre D15 y D14), pogo en el canto SUPERIOR** (copa del pogo en la franja +Y del suelo de la cápsula) |
| LED y masa de la antena | 7 LED | **8 LED alineados** (D15/D14 bajo D10/D11; D17/D12 y D16/D13 a la misma altura) · **4 pines de masa J12–J15** en las esquinas, junto a la URTK1.2, soldados a la placa de masa |
| Resto | | igual: ESP32-S3-WROOM-1U-N16R8, cargador, táctil, anillo (**8 LED**: D14 vuelve, a la derecha de la salida de la tarjeta), MAX17048, LSM6DSV16X, microSD, pogo, Hall |

Firmware: **sin cambios de GPIO** (UART1 GPIO5/6, UART2 GPIO3/8, PPS GPIO7, RST GPIO9, ZED_EN GPIO10). El 3,3 V de la
URTK1.2 lo da el RT9080 (se apaga con ZED_EN), como el prototipo de la espalda desde la 3.10.x; 5V sin conectar.

## Conexiones de las tiras (marco de la URTK1.2, vista desde sus componentes)

| Tira | Pines | A la placa |
|---|---|---|
| J10 (9) | GND · 5V · 3V3 · TX2 · RX2 · CS · RX/MOSI · TX/MISO · SCK | GND · — · +3V3_ZED · GPIO3 (330 Ω) · GPIO8 (1 kΩ) · — · GPIO6 (1 kΩ) · GPIO5 (330 Ω) · — |
| J11 (10) | GND · 3V3 · SDA · SCL · FENCE · RTK · PPS · RST · SAFE · INT | GND · +3V3_ZED · — · — · — · — · GPIO7 (330 Ω) · GPIO9 (1 kΩ) · TP13 · — |

«—» = pad aislado: solo sujeta (más soldaduras contra la vibración del galope).

## Montaje
1. Desoldar el SMA J2 de la URTK1.2 (no cabe en la cápsula); la antena va a su U.FL **J4**.
2. Tiras de pines con el plástico **entre** las dos placas; soldar primero a la PCB, luego la URTK1.2 encima
   (componentes hacia arriba). Cortar las puntas a ras por las dos caras (≤ 1,5 mm en la cara F, a ras arriba).
3. Pines de masa J12–J15 (tira larga o hilo de cobre de 1 mm, ≥ 12 mm) soldados en la PCB. Kapton sobre el blindaje
   del ZED y placa de masa encima (los recortes dejan libres J1, J3, J4, J6 y las tiras), con los 4 pines soldados a
   sus pads de las esquinas.
4. Antena Taoglas AHP2258 sobre la placa de masa, en el cuadrado serigrafiado, con su cable al U.FL J4.

## Precauciones (revisión independiente 18/11)
- **Kapton** sobre la cara B de la PCB bajo la URTK1.2: las patas de J1, J6 y del SMA quitado apoyarían en la máscara
  sobre el plano de masa.
- **No conectar el USB-C (J1) de la URTK1.2 montada**: su LDO alimentaría +3V3_ZED con el ZED apagado por ZED_EN.
- **Pila J6:** usar la que pida la placa (si J6 se carga desde 3V3, una ML1220 recargable; nunca una CR1220).
- Pines de masa J12–J15: taladro 1,2 mm (pin de tira de 0,64 o hilo de cobre de hasta 1 mm).

## Comprobaciones antes de pedir nada (con la URTK1.2 en la mano)
- **Lo más importante:** medir CADA fila por separado: distancia del primer pin al canto del USB-C (supuesto 12,827 mm)
  y cuál es su pin GND. Si una fila empezara desde el otro canto, se desplazaría 2,54 mm y todas sus redes quedarían
  mal. Medidas de la placa (43,434 × 43,688) y distancia entre filas (40,64).
- Diámetro, altura y posición del portapilas J6 (el CAD supone Ø13 × 5 mm).
- Que **J4 llegue al ZED** con J2 quitado (continuidad / prueba con la antena).
- Altura del portapilas J6 con pila, de J1 (USB-C) y de J3, y lo que sobresale por debajo (debe ser < 2,5 mm).
- Versión del ZED en u-center (MON-VER): **ZED-F9P-04B**.

## Ficheros
- `PCB/fuente/` — generador (copia de la REV B con las diferencias marcadas «PROTOTIPO A»); las librerías grandes
  (`lib_easyeda`, `3d`, `hojas`) son enlaces a las de `../V5_CASCO/PCB/fuente`.
- `PCB/fuente/placa_masa.py` → `PCB/PLACA_MASA/`: Gerber y taladros de la placa de masa (2 capas, 0,8 mm) y su
  geometría para el CAD.
- `CAD/avo_casco_v5p.py` — cápsula; CI `build-back-v5p-cad.yml`. PCB: CI `build-back-v5p-pcb.yml`.
