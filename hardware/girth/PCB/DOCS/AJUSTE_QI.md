# Ajuste de la bobina Qi (C1–C5) — hacerlo ANTES de pedir las placas

La bobina Ø25 mm sale de un receptor barato y su inductancia **no se conoce**. El BQ51013B solo funciona bien
si el condensador serie (C1 + C2 + C3) resuena con la bobina a **100 kHz** y el paralelo (C4 + C5) a **1 MHz**
(TI, *Receiver Coil Tuning Guide*).

## Valores montados por defecto (supuesto Ls′ ≈ 10 µH)
| Ref. | Valor | Función |
|---|---|---|
| C1, C2 | 100 nF C0G 50 V (1206) | serie |
| C3 | 47 nF C0G 50 V (1206) | serie → total 247 nF |
| C4 | 2,2 nF C0G 50 V (0805) | paralelo |
| C5 | sin montar (0603) | ajuste fino del paralelo |

## Cómo medir la bobina (tres opciones, de mejor a peor)
1. **Medidor LCR a 100 kHz** (1 V):
   - **Ls′**: bobina **dentro de la cápsula, con la batería encima**, apoyada sobre el cargador OTOTEC
     **apagado** (su ferrita cuenta). Es la que manda para C1.
   - **Ls**: bobina sola, lejos de metales.
2. **Copiar el receptor viejo**: los condensadores en serie con la bobina en la placa Qi de 18 × 15 ya están
   calculados para esa bobina. Mide su capacidad total (desoldados) → ese es tu C1 total.
3. **Resonancia con generador**: condensador conocido Cx en paralelo con la bobina, barrer frecuencia y buscar el
   pico: L = 1 / ((2π·f)²·Cx).

## Fórmulas
- C1 (total serie) = 1 / ((2π · 100 kHz)² · Ls′)
- C2 (total paralelo) = 1 / ((2π · 1 MHz)² · (Ls − 1 / ((2π · 100 kHz)² · C1)))

| Ls′ | C1 total | Combinación (1206 C0G) |
|---|---|---|
| 8 µH | 317 nF | 100 + 100 + 100 nF (+ 22 nF) |
| 10 µH | 253 nF | **100 + 100 + 47 nF** (montado) |
| 12 µH | 211 nF | 100 + 100 nF + 10 nF |
| 14 µH | 181 nF | 100 + 47 + 33 nF |
| 16 µH | 158 nF | 100 + 47 + 10 nF |

Cambia los valores en `fuente/avo_girth_pcb.py` (C1–C5) y vuelve a generar: el CI regenera BOM y CPL.
Si ya tienes las placas, son condensadores 1206/0805 fáciles de cambiar a mano.

## Corriente de salida del receptor
R1 + R2 = 330 + 200 = 530 Ω → I_MAX = 262 / 530 ≈ 494 mA (límite duro ≈ 590 mA). R3 = 20 kΩ (R_OS, de RECT a FOD).
R2 y R3 son los valores por defecto de TI hasta calibrar la detección de objetos extraños (FOD); TI pide montarlos
aunque no se calibre.
