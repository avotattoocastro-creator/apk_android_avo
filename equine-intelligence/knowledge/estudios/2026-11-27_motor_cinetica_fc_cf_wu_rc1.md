# Motor nocturno 27/11/2026 — Cinética de la FC: CF1, CF2, WU1–WU4, FW1 y RC1

**Motor:** 2.0.0-dev40 · **KB-1:** 1.33.0 · **Cardio:** 1.2.0 · **Training:** 1.6.0 · **Autor:** Claude (sesión nocturna, sin
supervisión) · **Estado:** IMPLEMENTADO, probado en local (ASan/UBSan) · **NO VERIFICADO** con caballos reales.

## 1. Por qué esto esta noche
La playa por franjas (a), la carga CG1–CG3 (b) y el planificador (c) ya estaban implementados (dev34–dev39). El siguiente
punto de la lista es (d): cinética de la FC, calentamiento y vuelta a la calma. Usa solo lo que ya graba el PROTOTIPO
(ECG de la cincha 0.5.0 + GNSS RTK de la espalda). Además da al entrenador tres números diarios que no dependen de llegar
a 200 lpm, cosa que la V200 sí necesita: la FC del calentamiento fijo, la τ de recuperación y el THR100. La temperatura y el peso
(TC/PC) se dejan para otra noche, porque necesitan antes la ficha de campo completa.

## 2. Qué se implementó
| Regla | Dónde | Cálculo | Etiqueta |
|---|---|---|---|
| CF1 | `cardio.cpp` (regresión de la V200) | meseta rápida (≥ 70 % de v máx o salto ≥ 3 m/s frente a los 10 s previos): descarte 30 s y duración ≥ 45 s | [E-r] τ VO2 / [I] cortes |
| WU2 | `cardio.cinetica.calentamiento` | inicio → primera época ≥ 60 % de v máx; duración, distancia, FC y v media; s con FC ≥ 120 lpm a < 1,7 m/s; aviso si ≥ 60 s | [E-r] 1000 m / [I] cortes |
| FW1 | `cardio.cinetica.tramo_fijo` | últimos 60 s seguidos a 3–6 m/s con CV ≤ 10 %: FC media | [E-r] idea / [I] tramo |
| CF2 | `cardio.cinetica.recuperacion_tau` | FC(t) = A + B·e^(−t/τ), épocas válidas de 60 a 600 s tras el esfuerzo; cobertura ≥ 60 %, R² ≥ 0,80 | [E-r] modelo / [I] ventana |
| RC1 | `cardio.cinetica.thr100` | s hasta mediana de 5 latidos < 100 lpm; 200 s solo como referencia | [OFICIAL] |
| WU3 | A9 y `estado.cinetica_fc` | comparables con distancia de calentamiento ±20 % | [I] |
| Historia | `estado.cinetica_fc` | τ, THR100 y FC del tramo fijo frente a la mediana de ≥ 3 comparables; marca INFO con +25 % / +8 lpm | [I] |

**Ajuste de τ.** Para cada τ, A y B salen por regresión lineal de la FC sobre x = e^(−t/τ). Se busca τ con 401 puntos
logarítmicos entre 5 y 900 s y se refina por sección áurea en el intervalo vecino. Se descarta el resultado si B ≤ 0,
si τ cae en un límite de la búsqueda o si R² < 0,80. Se omite el primer minuto porque en ponis la recuperación es
biexponencial, con una fase rápida de unos 15 s que dura menos de un minuto (Rugh 1992).

**Ejemplo (prueba con verdad analítica):** FC = 70 + 135·e^(−(t−760)/90) tras un galope a 205 lpm. El motor da
τ ≈ 90 s, asíntota ≈ 70 lpm y THR100 = 90·ln(135/30) = 135,4 s. En la historia, con τ de base de 80, 90, 100 y 90 s,
una sesión con τ 117 s sale a +30 % y se marca, siempre como INFO.

## 3. Fuentes (acceso de hoy; parafraseado)
| ID | Qué sostiene | Acceso 27/11 | Cifras usadas | Etiqueta |
|---|---|---|---|---|
| LANGSETMO_1997 (DOI 10.1152/jappl.1997.83.4.1235) | CF1: la cinética del VO2 es más lenta por encima del umbral | resumen releído (agregador) | τ 10,0 ± 0,9 s bajo el umbral (3 → 7 m/s), 20,7 ± 3,4 s sobre él (3 → 12,3 m/s); componente lento desde unos 136 s en 4 de 5 caballos | [E-r], [I-raza] (raza no leída [NV]) |
| RUGH_1992_PONIS (PMID 1643220) | CF2: modelo exponencial y omitir el primer minuto | resumen | biexponencial: τ 15 ± 2 s y 455 ± 78 s; con atropina, monoexponencial 174 ± 46 s | [E-r] [I-raza: ponis] |
| HADA_2007_EVJ_TAU (DOI 10.1111/j.2042-3306.2006.tb05530.x) | CF2 en PSI: τ como índice de forma propio | resumen | τ baja con 11 semanas de entrenamiento y se relaciona inversamente con el VO2max (r 0,43); **sin τ en segundos** | [E-r]; cifras [NV] |
| MUKAI_2010_EVJ_WARMUP (DOI 10.1111/j.2042-3306.2010.00227.x) | WU3: el calentamiento cambia la FC del trabajo | resumen | 9 PSI; calentamientos de igual distancia al 30, 60 o 100 % del VO2max; con el intenso, FC más alta en todo el sprint y VO2 más rápido. Un agregador lo fecha en 2011 (págs. 33–39): hay que comprobarlo | [E-r] |
| DE_MARE_2017_VDT | WU1: ≥ 1000 m de trote antes de la prueba | ya en KB (texto completo) | 1000 m | [E-r]; uso [I] |
| YAMANOBE_1993_JRA (DOI 10.11535/jes1977.1993.5) | FW1 | **no accesible hoy** (no se esquivó) | ninguna nueva; las de la KB del 22/11 no se han releído | [E-r] |
| JRA_HANEDA_134_THR100 | RC1 | **no accesible hoy** | 200 s, solo como referencia; no se ha releído | [OFICIAL] |

No se encontró ninguna τ de recuperación con cifra en árabes [NV].

## 4. Qué falta calibrar (protocolo de campo §6 quater)
- Todos los cortes [I]: +25 % de τ y THR100, +8 lpm del tramo fijo, ±20 % de calentamiento, 60 %/120 lpm/1,7 m/s de WU2 y
  70 %/3 m/s/30 s/45 s de CF1. Se sustituirán por el error típico propio (≥ 3 sesiones en ≤ 7 días, RB1).
- WU3 compara hoy por distancia, no por intensidad, y Mukai muestra que la intensidad también importa: falta la FC media
  del calentamiento como segundo criterio.
- TC1 (temperatura) y GO1 (going) como criterios de comparables de FW1, CF2 y RC1.
- Releer el informe 134 de la JRA y Yamanobe 1993 cuando sean accesibles. Buscar el texto completo de Hada 2007 para
  tener una τ de PSI de referencia; aun con ella, la regla seguiría siendo de tendencia propia.

## 5. Apps
- iPad, Android y Windows: falta dibujar `cardio.cinetica` (análisis) y `estado.cinetica_fc` (historia). Ningún contrato
  binario cambia: solo hay campos nuevos en el JSON del motor.
