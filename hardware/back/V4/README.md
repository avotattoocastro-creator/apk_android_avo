# AVO BACK V4 · espalda compacta (PCB propia + URTK1.2 + carcasa más corta)

Rediseño conjunto de la electrónica y la carcasa de la espalda de AVO Performance Horse.
**Estado: DISEÑADO Y COMPROBADO POR SOFTWARE · NO FABRICADO · NO VERIFICADO EN HARDWARE.**

**REV B (30/10/2026): sin Qi ni sensor Hall.** Alimentación por **3 contactos en el fondo** (tornillos M2 avellanados con
junta tórica): **SYS** y **BAT** en la cola, donde estaba el reed, y **GND** aparte.
- **Soporte del chaleco:** 2 pines con muelle unidos por un hilo puentean SYS–BAT. Al poner la cápsula se enciende; al
  quitarla queda a 0 V.
- **Base de carga:** cargador Li-ion externo entre BAT y GND, con la electrónica apagada.
- **USB-C:** se mantiene para el taller (datos y carga).
- **REV A** (con Qi y Hall, puerta superada) congelada en `PCB_REV_A_QI/`.
- **Probarlo antes en la espalda actual** (Rev E + Heltec): `DOCS/PROTOTIPO_POGO_REV_E.md` y `PROTOTIPO_POGO_REV_E6/`.

## Resultado
| Parámetro | Espalda actual (Rev E.5 + Heltec) | Nueva V4 | Diferencia |
|---|---|---|---|
| Longitud de la cápsula | 166,2 mm | **118,2 mm** | **−48,0 mm (−28,9 %)** |
| Anchura | 59,0 mm | 59,0 mm | 0 |
| Grosor de la cápsula | 17,1 mm | **17,1 mm** | **0** (no aumenta) |
| Grosor del conjunto (cápsula + soporte + tela + contraplaca) | 28,2 mm | 28,2 mm | 0 |
| Volumen exterior de la cápsula | 157,8 cm³ | 110,1 cm³ | −47,7 cm³ (−30,3 %) |
| Peso de las piezas impresas (macizas, PETG/TPU) | 208 g | ≈ 131 g | **≈ −77 g (−37 %)** |
| Peso de la electrónica | Heltec + Pololu + módulo Qi + cables | PCB V4 ≈ 9 g (estimado) | similar (sin medir) |
| Autonomía (2000 mAh) | ~8 h (estimada, 190–230 mA) | **≈ 7,8 h** (estimada, ≈ 230 mA) | ≥ 4 h exigidas |
| Consumo fuera del soporte | ZED sin cortar en algunas versiones (~70 mA) | **0 µA** (REV B: sin puente SYS–BAT la placa no tiene alimentación; solo el PCM de la celda) | |
| Placas | 3 (Heltec, URTK1.2, módulo Qi) + regulador Pololu | **2** (PCB V4 + URTK1.2) | −1 (−2 con el Pololu) |
| Cables entre placas | ZED (5–7 hilos), Qi, reed, batería, regulador | **1 mazo de 8 hilos** (URTK1.2 ↔ J4) + batería | |
| Carga | Qi (base inalámbrica) | **contactos BAT–GND** en la base de carga (REV B) · USB-C en el taller | |
| microSD | no | **sí** (SDMMC 4 bits) | |

**PCB REV B:** ruteada al 100 %; KiCad 9 en el CI (run 41048486880, `c1e0e26`): DRC 0, ERC 0, 0 conexiones incompletas,
puerta de fabricación superada → `PCB/out/FINAL/` (61 piezas montadas). Su STEP, montado en el CAD a Z 2,5, no interfiere
con ninguna pieza ni con los tornillos de contacto (`CAD/VALIDACION/verificacion_pcb_step_v4.json`).
**PCB REV A** (congelada): puerta superada en el CI (run 40971520610, `3f81b45`) → `PCB_REV_A_QI/out/FINAL/`.

Cotas y volúmenes medidos sobre el modelo B-Rep (no sobre fotos). Pesos: volumen × densidad (PETG 1,27, TPU 1,20 g/cm³),
como en la Rev E.

## Cómo se consigue (sin aumentar el grosor)
- **La URTK1.2 va encima de la batería**, donde estaba la Heltec, a la misma altura (Z 9,6). La L, la torre y la antena
  no cambian de cota.
- **La PCB va en la cola**, el tramo que la antena Q39 obliga a tener por detrás del eje de la L y que en la Rev E
  estaba casi vacío. Bolsillo en la base a Z 2,5 (REV A: bobina Qi debajo; REV B: suelo macizo con los contactos).
- **Un solo ESP32-S3** (no dos): misma funcionalidad, menos consumo y menos superficie (`DOCS/ARQUITECTURA_Y_CONSUMO.md`).
- **Sin sensor de soporte (REV B)**: el propio soporte cierra el circuito (puente SYS–BAT); REV A usaba un Hall soldado.
- **Regulador propio del ZED con EN**: corta físicamente receptor y antena, sin el reinicio de la BACK 3.10.4.

Estudio completo de las alternativas A–D: `DOCS/ESTUDIO_DISTRIBUCION.md`.

## Carpetas
| Carpeta | Contenido |
|---|---|
| `CAD/fuente/` | modelo paramétrico FreeCAD 1.0.2 (`avo_back_v4_freecad.py`), verificación, exportación, voladizos, renders, plano |
| `CAD/STL/` | piezas orientadas para imprimir **sin soportes** + `posicion_montaje/` + probetas |
| `CAD/STEP/` | sólidos B-Rep por pieza, conjunto montado y explosionado |
| `CAD/IMAGENES/`, `CAD/PLANOS/` | vistas, vista explosionada, plano de dimensiones (PDF) y comparativa con la Rev E.5 |
| `CAD/VALIDACION/` | interferencias, STEP/STL, voladizos, informe del modelo |
| `PCB/fuente/` | generador del proyecto KiCad REV B (piezas, redes, colocación), reparación de ruteado, puerta de fabricación |
| `PCB_REV_A_QI/` | placa REV A con Qi y Hall (congelada, puerta superada) |
| `PROTOTIPO_POGO_REV_E6/` | base, soporte y base de carga Rev E.6 para probar los contactos en la espalda actual (Heltec) |
| `PCB/kicad/` | proyecto KiCad 9 editable |
| `PCB/out/` | ERC/DRC, esquema PDF, renders y — si la puerta pasa — `FINAL/` (Gerber, taladros, BOM y CPL de JLCPCB, STEP) |
| `../../../firmware/back/V4_0_0/` | firmware 4.0.0-dev2 de la placa V4 REV B (`../V3_8_0`: BACK 3.12.0 para el prototipo Heltec) |
| `DOCS/` | arquitectura y consumo, integración GNSS, distribución, montaje y riesgos |

## Ejes y origen (CAD, PCB y STEP)
X 0 = cara del cuello, X+ hacia la cola · Y 0 = eje de la L · Z 0 = cara inferior de la cápsula. La PCB de KiCad está en
las mismas coordenadas (x = X, y = 100 − Y; el STEP se exporta con origen de usuario 0 × 100 mm).
