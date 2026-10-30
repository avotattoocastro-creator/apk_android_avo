# AVO BACK V4 · espalda compacta (PCB propia + URTK1.2 + carcasa más corta)

Rediseño conjunto de la electrónica y la carcasa de la espalda de AVO Performance Horse.
**Estado: DISEÑADO Y COMPROBADO POR SOFTWARE · NO FABRICADO · NO VERIFICADO EN HARDWARE.**

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
| Consumo dormida | ZED sin cortar en algunas versiones (~70 mA) | ≈ 45 µA (ZED, antena y microSD a 0 V) | |
| Placas | 3 (Heltec, URTK1.2, módulo Qi) + regulador Pololu | **2** (PCB V4 + URTK1.2) | −1 (−2 con el Pololu) |
| Cables entre placas | ZED (5–7 hilos), Qi, reed, batería, regulador | **1 mazo de 8 hilos** (URTK1.2 ↔ J4) + 2 hilos de la bobina | |
| microSD | no | **sí** (SDMMC 4 bits) | |

**PCB REV A:** ruteada al 100 %; KiCad 9 en el CI (run 40971520610, `3f81b45`): DRC 0, ERC 0, 0 conexiones incompletas,
puerta de fabricación superada → `PCB/out/FINAL/`. El STEP de esa placa, montado en el CAD a Z 2,5, no interfiere con
ninguna pieza (`CAD/VALIDACION/verificacion_pcb_step_v4.json`).

Cotas y volúmenes medidos sobre el modelo B-Rep (no sobre fotos). Pesos: volumen × densidad (PETG 1,27, TPU 1,20 g/cm³),
como en la Rev E.

## Cómo se consigue (sin aumentar el grosor)
- **La URTK1.2 va encima de la batería**, donde estaba la Heltec, a la misma altura (Z 9,6). La L, la torre y la antena
  no cambian de cota.
- **La PCB va en la cola**, el tramo que la antena Q39 obliga a tener por detrás del eje de la L y que en la Rev E
  estaba casi vacío. Bolsillo en la base a Z 2,5, bobina Qi debajo.
- **Un solo ESP32-S3** (no dos): misma funcionalidad, menos consumo y menos superficie (`DOCS/ARQUITECTURA_Y_CONSUMO.md`).
- **Hall soldado en la PCB** en lugar del reed de vidrio: la PCB baja 2 mm y caben componentes bajo la L.
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
| `PCB/fuente/` | generador del proyecto KiCad (piezas, redes, colocación), reparación de ruteado, puerta de fabricación |
| `PCB/kicad/` | proyecto KiCad 9 editable |
| `PCB/out/` | ERC/DRC, esquema PDF, renders y — si la puerta pasa — `FINAL/` (Gerber, taladros, BOM y CPL de JLCPCB, STEP) |
| `../../../firmware/back/V4_0_0/` | firmware 4.0.0-dev1 de la placa V4 |
| `DOCS/` | arquitectura y consumo, integración GNSS, distribución, montaje y riesgos |

## Ejes y origen (CAD, PCB y STEP)
X 0 = cara del cuello, X+ hacia la cola · Y 0 = eje de la L · Z 0 = cara inferior de la cápsula. La PCB de KiCad está en
las mismas coordenadas (x = X, y = 100 − Y; el STEP se exporta con origen de usuario 0 × 100 mm).
