# 14 · Base científica de la cuadra (KB-1) 1.5.0

Código: `include/avo_eq/knowledge.h`, `src/knowledge/knowledge.cpp`. Se calcula en Track Work (`src/racing/racing.cpp`,
bloque `trabajo_pista.base_cientifica`) y se evalúa en Training Analytics (`src/training/training.cpp`, bloques
`estado.base_cientifica` y `sesiones[].base_cientifica`). Pruebas: `tests/test_knowledge.cpp` (suite `kb`) y
`pista.base_cientifica_kb1` en `tests/test_racing.cpp`.

Fuentes, parámetros, nivel de evidencia y pendientes, en formato legible por máquina: `knowledge/base_cientifica.json`.
Estudios completos: `knowledge/estudios/`.

**Objetivo:** el «modelo de la cuadra» parte de lo publicado sobre PSI y árabe de carreras en llano, no de cero.
Cada caballo se sigue comparando consigo mismo (Training Analytics). KB-1 añade la carga que la literatura relaciona con
lesión y rendimiento, y reglas con su evidencia. Las etiquetas son **[E]** publicado, **[I]** inferencia propia y
**[NV]** sin verificar.

## 1. Fatiga del hueso subcondral por zancada (`SBFL_MORRICE_WEST_2022`)
```
F(v) = 2,778 + 2,1376·v − 0,0535·v²      N/kg; saturada en 24,13 por encima de 19,98 m/s [E; saturación I]
σ    = σ_max · F / 24,13                  MPa; σ_max = 90 por defecto (rango publicado 54–90) [E]
Nf   = 10^((σ0 − σ) / 14,1)               σ0 = 134,2 MPa (Martig 2013, curva de sensibilidad, R² 0,72) [E]
%SBFL = 100 · Σ 1/Nf                      regla de Miner, sin reparación [E]
zancadas por época GNSS = f(v)·dt,  f(v) = 1,7052 + 0,0305·v + 0,0004·v² Hz [E, Anwar 2026]
```
- Rango validado de 12,57 a 21 m/s (filtro de Morrice-West). Entre 4 y 12,57 m/s el daño se suma aparte en
  `pct_extrapolado_lento`, porque el modelo sobrestima el trabajo lento (calculado 1,2–3,3 % por canter frente a 0,41 %
  de mediana en Hong Kong).
- Huecos GNSS de más de 5 s no cuentan.
- **σ0 (estudio nocturno del 18/11):** 134,2 MPa es la curva in vitro de sensibilidad de Martig 2013, la que usa
  Morrice-West 2022 con Miner sin reparación; 139,0 MPa es la calibración in vivo de Pan 2025 para el modelo B (con
  reparación). El modelo A se queda en 134,2. Los 54–90 MPa son los niveles del ensayo de Martig, no un rango de σ_max.
- Es un **índice relativo de carga**, no una probabilidad de fractura. En árabes usa parámetros de PSI y la salida dice
  `calibrado: false`.

Valores de prueba (σ_max 90, σ0 134,2): 1.200 m a 16,7 m/s = **8,64 %** (publicado 9,34 % de media por carrera);
600 m a 16 m/s = 3,77 %; 2.000 m a 12 m/s = 3,27 % (extrapolado); σ_max 54 = 0,028 %; σ0 139,0 = 3,94 %.

## 2. Bandas relativas al ritmo de carrera
`v_carrera`: PSI 16,7 m/s [E, media de 25.259 salidas]; árabe 14,5 m/s [I, Gr1 de Longchamp 2024 a 14,70 m/s].
La opción `v_carrera_m_s` fija el ritmo propio de un caballo. GENERICO no tiene `v_carrera`: todo va a B1 y no hay
contadores de Verheyen.

| Banda | Fracción | PSI | Árabe |
|---|---|---|---|
| B1 trabajo | v_trabajo – 0,80 | 11 – 13,36 m/s | 10 – 11,6 m/s |
| B2 intermedia | 0,80 – 0,93 | 13,36 – 15,53 | 11,6 – 13,49 |
| B3 alta | ≥ 0,93 | ≥ 15,53 | ≥ 13,49 |
| Canter (Verheyen) | 0,40 – 0,838 | 6,7 – 14 | 5,8 – 12,2 |
| Galope rápido (Verheyen) | > 0,838 | > 14 | > 12,2 |

El corte de 14 m/s es de Verheyen 2006 en PSI [E]; su escalado al árabe es [I]. La zancada del árabe se compara ahora a
**13 y 14 m/s** (antes 13 y 15): 15 m/s queda por encima del ritmo de muchos árabes [I].

## 3. Reglas sobre la historia
| Regla | Umbral por defecto | Acción | Evidencia |
|---|---|---|---|
| A1_CANTER_30D | canter > 40 km en 30 d (aviso) / > 44 km (límite) | AVISO / LIMITAR | Verheyen 2006 [E]; aviso al 90 % [I] |
| A2_GALOPE_30D | galope rápido > 6 km en 30 d | LIMITAR | Verheyen 2006 [E] |
| A3_RAMPA | galope rápido 30 d > 1,4 × los 30 d anteriores (≥ 1 km; 60 d de historia) | LIMITAR | Estberg 1996, OR 3,9 [E]; ventanas [I] |
| A5_VUELTA_DESCANSO | primera sesión rápida tras ≥ 60 d sin ella: 21 d vigilados | LIMITAR | Carrier 1998, RR 71 a 10 d [E] |
| A6_VUELTA_TENDON | igual tras ≥ 90 d: sugiere ecografía del TFDS | LIMITAR | Choi & Parkin 2025, OR 3,10 [E] |
| A6B_POCO_GALOPE_60D | ≤ 2 días con sesión rápida en los 60 d previos, con sesiones en los últimos 7 d (60 d de historia) | AVISO (INFO) | Choi & Parkin 2025, OR 1,84 (1,07–3,16) de TFDS [E]; día de galope = sesión rápida [I] |
| KB_FATIGA_OSEA_7D | fatiga ósea 7 d > 1,5 × mediana semanal propia (≥ 4 semanas) | AVISO | Morrice-West 2025, Hong Kong [E]; umbral [I] |
| KB_SIN_RAPIDO_30D | canter sin trabajo rápido en 30 d | AVISO (INFO) | Morrice-West 2025 [E]; aplicación [I] |

Sesión rápida = al menos 100 m de galope rápido. Las reglas VIGILAR suben el estado a VIGILAR y añaden el motivo
«base científica (regla, acción): …». Nunca diagnostican.

Opciones de Training Analytics (`base_cientifica`: `true`/`false` u objeto): `activa`, `canter_30d_aviso_km`,
`canter_30d_limite_km`, `galope_30d_limite_km`, `rampa_ratio`, `rampa_min_m`, `galope_sesion_min_m`,
`fatiga_osea_ratio`, `dias_descanso_vuelta`, `dias_ventana_vuelta`, `dias_descanso_tendon`, `semanas_min_fatiga_osea`, `dias_galope_60d_max` (0–24, por defecto 2).
Opciones del análisis de sesión: `v_carrera_m_s` (8–20), `sigma_max_mpa` (30–120), `sigma0_mpa` (100–180).

Los análisis anteriores sin el bloque cuentan como «sesiones sin datos» y no se juzgan.

## 3 bis. Velocidad de los últimos 600 m (KB-1 1.1.0)
`kb_final_speed(t, d, 600)`: 600 m divididos por el tiempo de los últimos 600 m de cada trabajo, con el tiempo
interpolado sobre la distancia acumulada (Schrurs 2024 [E], «average speed over the last 600 m»; la velocidad puntual
en la marca de 600 m no predice). Sale en `trabajo_pista.trabajos.lista[].v_ultimos_600m` y `ultimos_600m_s`, solo en
trabajos de al menos 600 m. Valor de prueba: 1.000 m a 14 m/s + 400 m a 17 m/s → 37,815 s y 15,867 m/s.
La regla A8 (caída frente a la línea base) sigue pendiente: no hay umbral publicado.

## 3 ter. Pocos días de galope en 60 días (KB-1 1.2.0, regla A6B)
Choi & Parkin 2025 (EVJ 58:31–39, Seúl, 101 casos y 304 controles) [E]: en el modelo final, **≤ 2 días de galope en
los 60 días previos** (frente a 3–24) tiene OR 1,842 (IC 95 % 1,073–3,162) de tendinopatía del TFDS. La KRA solo
anota si el día fue de galope o de canter, sin velocidad ni distancia, así que «día de galope» = día con sesión rápida
del motor (≥ 100 m por encima de 0,838·v_carrera) es [I]. El estado lleva `dias_galope_60d`. Solo informa (INFO,
AVISO); no cambia el estado a VIGILAR.

## 3 quater. Herramientas de línea base (KB-1 1.3.0, estudio extra del 19/11)
Funciones de `knowledge.h` para comparar a cada caballo consigo mismo. **Todavía no las usa ninguna regla** (faltan el
TE propio de cada métrica y la superficie anotada, incluida la playa por franja); la salida JSON no cambia.

| Función | Qué hace | Evidencia |
|---|---|---|
| `kb_robust_baseline(x, 12)` | mediana y MAD_s = 1,4826·MAD de las últimas 12 válidas (NaN se saltan) | 1,4826 = 1/Φ⁻¹(0,75) [E] |
| `kb_robust_z(x, b, min_scale)` | (x − m)/max(MAD_s, min_scale); atípico si > 3,5 (`KB_ROBUST_Z_OUTLIER`) | z modificado de Iglewicz & Hoaglin (NIST) [E] |
| `kb_shrink_mean(n, x̄, σ², μ_pop, τ²)` | media encogida hacia la cuadra (σ² dentro del caballo, τ² verdadera entre caballos) | Efron & Morris 1975 [E] |
| `kb_change_threshold(TE, n, SWC)` | max(2·TE·√(1 + 1/n), SWC) | 1,5–2·TE de Hopkins 2000 [E]; √(1 + 1/n) [cálculo] |
| `kb_cusum_upper(z, {k, h, fir, min_samples})` | S_t = max(0, S_{t−1} + z_t − k), alarma si S_t > h | ARL recalculados = NIST [E]; uso en caballos [I] |

ARL con k = 0,5 (unilateral): h = 4 → ARL0 ≈ 335 y ARL1(δ = 1) ≈ 8,4; h = 5 → 931 y 10,4; FIR (S0 = h/2) baja el ARL1
a 5,3 con h = 4. Los 168/465 son del CUSUM bilateral. Con muchas cartas (caballos × métricas × sentidos) usar h = 5 [I].
Valores de prueba: {6,9; 7,0; 7,1; 7,05; 6,95; 7,2; 6,85; 7,0} → mediana 7,0 y MAD_s 0,1112; shrinkage (n 3, x̄ 10,
σ² 0,04, μ_pop 9,6, τ² 0,09) = 9,9484; CUSUM de {0,2; 1,2; 1,5; 0,8; 1,6; 1,4; 1,1} → alarma en la 7.ª muestra.

**CUSUM autoiniciado (KB-1 1.4.0, estudio extra 2 del 19/11).** Con μ y σ estimadas de 5–20 sesiones, el CUSUM con
h = 4/5 no tiene el ARL0 nominal por caballo (simulación propia: con 10 sesiones y h = 4 el P10 del ARL0 es 23).
`kb_self_starting_z(x)` tipifica cada sesión frente a las anteriores (Hawkins 1987: ξ = Φ⁻¹(T_{n−2}(√((n−1)/n)·V)),
V = (x_n − x̄_{n−1})/s_{n−1}, n ≥ 3) y sus ξ se pasan a `kb_cusum_upper` con k = 0,5, h = 5 y `min_samples` 8–10 [I];
ARL0 339/930 con h = 4/5 (simulación propia). Prueba: {10,0; 10,4; 9,8; 10,9; 10,1; 12,0} → ξ_6 = 2,3292 (scipy).

**Reglas A7 y A8 aplicadas (KB-1 1.5.0, motor 2.0.0-dev7).** `kb_drift_down(x, {delta, k, h, warmup})` juzga la última
sesión frente a las **comparables** (mismo `superficie` anotado; sin anotar es otra superficie) y Training Analytics
añade sus avisos a `base_cientifica.reglas` de la sesión (y al estado si la sesión es de los últimos 7 días):

| Regla | Métrica | Umbral | Nivel |
|---|---|---|---|
| `A7_CAIDA_ZANCADA` | `TRABAJO.l_v1_m`, `l_v2_m` (zancada a la velocidad de referencia) | ≥ 0,10 m bajo la mediana de las ≤ 12 anteriores (≥ 5) en la última y en 2 de las 3 últimas, **o** CUSUM autoiniciado | VIGILAR · AVISO |
| `A8_CAIDA_VELOCIDAD_FINAL` | `v_ultimos_600m` del trabajo rápido más veloz | ≥ 0,20 m/s, mismo criterio | INFO · AVISO; VIGILAR si umbral y CUSUM a la vez |

Evidencia: Wong 2023 (HR 1,11 por 10 cm menos de zancada) y Schrurs 2024 (últimos 600 m) [E]; umbrales, 2 de 3 y CUSUM
[I]. CUSUM: k 0,5, h 5, sin alarmas en las 8 primeras comparables; las sesiones con S > 0,8·h no entran en la base
(simulación propia: falsa alarma 11,4 % en 100 sesiones; deriva de 3 DE detectada en ≤ 6 sesiones el 91,5 %).
Opciones (`base_cientifica`): `reglas_linea_base`, `caida_zancada_m`, `caida_v_600m`, `cusum_h`,
`cusum_calentamiento`, `sesiones_min_linea_base`. A9 (V200) sigue pendiente: el análisis no trae el ECG.

## 4. Ciclo semanal de mejora (durante las pruebas de campo del PROTOTIPO)
1. **Estudio de la semana:** revisión de la `cola_investigacion` de `base_cientifica.json` y de estudios nuevos. Se
   guarda en `knowledge/estudios/AAAA-MM-DD_<tema>.md` con fuentes y etiquetas [E]/[I]/[NV].
2. **Datos de campo:** lo aprendido de las sesiones reales del PROTOTIPO (ruido, saturación de la cincha, umbrales
   que saltan de más o de menos) entra como hallazgo de la cuadra, con fecha y sesiones.
3. **Base:** se actualizan `parametros`, `reglas`, `pendiente_motor` e `historial`, y sube `version` (y
   `KNOWLEDGE_VERSION` si cambia el código).
4. **Motor:** cada pendiente implementado lleva sus pruebas con valores de referencia. Rama corta `claude/kb-<tema>`,
   PR a `develop` con registro de cambios y tabla de estado.
5. **Primera versión oficial:** la base que llegue a ella se congela con su versión y la tabla de errores medida con la
   cuadra (fases 0–2 del plan de validación del estudio ampliado).

## Validación y límites
- **IMPLEMENTADO** y probado con datos sintéticos con ASan/UBSan: valores de referencia del modelo óseo, bandas,
  contadores, reglas, ida y vuelta por JSON, opciones y cadena análisis → resumen → historia.
- **NO VERIFICADO** con caballos reales. Los umbrales son de partida y se ajustan con la cuadra.
- La frecuencia de zancada es la del modelo. Usar la medida por la cincha queda pendiente.
