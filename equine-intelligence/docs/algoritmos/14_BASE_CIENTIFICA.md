# 14 · Base científica de la cuadra (KB-1) 1.12.0

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
zancadas por época GNSS = f(v)·dt,  f(v) = 1,7052 + 0,0305·v + 0,0004·v² Hz [E, Witte 2006 fig. 5; reutilizada por Anwar 2026]
```
- Rango de cálculo de 12,57 a 21 m/s. **KB 1.9.0:** en Morrice-West 2022 son los criterios de exclusión de datos, no un
  rango validado [E]; la ecuación de fuerza se ajustó en Witte 2006 solo entre 9 y 17 m/s, y la saturación en el
  vértice (19,98 m/s) es elección nuestra [I]. Entre 4 y 12,57 m/s el daño se suma aparte en
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
| A2_GALOPE_30D | galope rápido > 6 km en 30 d | LIMITAR | Verheyen 2006 [E-r]; **KB 1.9.0:** el umbral publicado es conjunto con A1 y el galope acumulado fue protector en añojos: A1 y A2 por separado son derivadas [I] |
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
La regla A8 (caída frente a la línea base) sigue pendiente: no hay umbral publicado. **KB 1.9.0:** Wong 2023 (texto completo, Tasmania) usó el último parcial de 200 m de carrera (HR 1,18 por cada 0,1 m/s de caída); los 600 m en trabajo y el umbral de 0,20 m/s son [I]. **KB 1.10.0:** reconfirmado que el riesgo sube al **bajar** la velocidad absoluta del último 200 m a lo largo de las salidas del caballo (A8, que vigila la caída frente a la línea base, tiene el sentido correcto). El «Finishing Speed %» de Timeform (v final / v media frente al par de pista y distancia) no tiene umbrales publicados: en AVO será solo descriptivo con par propio [I]. Modelo óseo B: dt y solver siguen sin publicarse; f_BM(0) 0,61 y D*(0) 0 [E]; usar 0,911 (tabla 7) y no 0,852 (Discusión) del preprint de Anwar (estudio 2026-11-20 08:09).

## 3 ter. Pocos días de galope en 60 días (KB-1 1.2.0, regla A6B)
Choi & Parkin 2025 (EVJ 58:31–39, Seúl, 101 casos y 304 controles) [E]: en el modelo final, **≤ 2 días de galope en
los 60 días previos** (frente a 3–24) tiene OR 1,842 (IC 95 % 1,073–3,162) de tendinopatía del TFDS. La KRA solo
anota si el día fue de galope o de canter, sin velocidad ni distancia, así que «día de galope» = día con sesión rápida
del motor (≥ 100 m por encima de 0,838·v_carrera) es [I]. El estado lleva `dias_galope_60d`. Solo informa (INFO,
AVISO); no cambia el estado a VIGILAR.

**Regla A6C_COCIENTE_GALOPE (KB-1 1.9.0, motor 2.0.0-dev11).** Choi & Parkin 2025, sección 2.3 (fórmula leída en el
texto completo) [E]: cociente = (días de galope en los 60 d / días de galope en los 90 d) + 1, con el +1 fuera de la
fracción, recuentos brutos y las dos ventanas anidadas acabando en el **último trabajo rápido**. Va de 1 a 2; ≤ 1,6
(frente a > 1,6) tiene OR 2,190 (1,227–3,910) de tendinopatía del TFDS en el modelo final (tabla 2) [E]. ≤ 1,6 quiere decir
que menos del 60 % de los galopes de 90 días caen en los 60 últimos: el galope se está espaciando. En el motor [I]:
el día del último trabajo rápido entra en las dos ventanas; hace falta historia de 90 días antes de él, alguna sesión
en los últimos 7 días y que el último trabajo rápido sea de los últimos 30 días (`dias_vigencia_cociente_galope`).
Opciones: `cociente_galope_max` (1–2, por defecto 1,6). Salida: `cociente_galope {valor, dias_galope_60d,
dias_galope_90d}` o `null`. INFO · AVISO; es un factor asociado en casos y controles, no una predicción de lesión.

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

**Estudio extra 3 (KB-1 1.6.0, motor 2.0.0-dev8, sin cambios de lógica).** Dos especificaciones nuevas, **PENDIENTE**:
- **Planificador semanal (capa 2), restricciones P1–P6** (`reglas.PLANIFICADOR_RESTRICCIONES_P1_P6`): trabajos rápidos
  por semana según la práctica (≈ 2 en maduros, 1,7 en 2 años, Morrice-West 2020 [E]), día libre, carreras cada
  17–21 d, vuelta tras > 60 d, P75 propio de la distancia rápida de 60 d y descansos anuales. No hay evidencia publicada
  de los días entre trabajos rápidos ni datos de árabes de llano: esas partes son [I].
- **A11 y detector de QRS** (`reglas.A11_ECG.nota_1_6_0`): ancla en el pico S (Van Steenkiste 2020 [E], reposo),
  prematuro ≥ 5–6 % de acortamiento del RR (Navas de Solis 2026 [E]), fases con recuperación 0–2 min, puerta de calidad
  > 10 % no interpretable por fase y salida siempre como «candidato a revisar».
Detalle: `knowledge/estudios/2026-11-19_extra3_planificador_semanal_ecg_a11.md`.

**Estudio extra 4 (KB-1 1.7.0, motor 2.0.0-dev9, sin cambios de lógica ni de constantes).** Auditoría de acceso de 9
fuentes (campos `acceso`, `verificado_fecha`, `pais`, `idioma`, `raza_fuente` en `base_cientifica.json`):
- Morrice-West 2025 es de **Tasmania** y da **HR**; su «carga baja» es fatiga ósea acumulada < 0,25 en las 4 salidas
  previas, así que el corte de A4 (2 sesiones en 28 d) es [I].
- Carrier 1998 (A5): RR 71/45 **solo para fractura de húmero**. Estberg 1996 (A3): 35 frente a 25 furlongs entre
  caballos; la rampa propia es [I]. Martig 2013: σ0 134,2 confirmada (caso sin lesión avanzada).
- Vermeulen & Evans: «diferencia media ≤ 2 %», no CV. Frick 2019: −6,1/+5,4 % es canter en cinta; corte de
  recuperación 6 % (S 88 %, E 97 %).
- Índice tendinoso: sigue sin OR de árabes; edad 3–4 años con tres fuentes (Turquía, Qatar); la carga solo se asocia
  a la gravedad. A9: TE propio del caballo, nunca mezclar cinta y pista ([I-raza], trotones).
Detalle: `knowledge/estudios/2026-11-19_extra4_auditoria_fuentes_tendon_arabes_v200_trotones.md`.

**Estudio extra 5 (KB-1 1.8.0, motor 2.0.0-dev10, sin cambios de lógica).**
- **Modelo óseo B:** `modelo_B_constantes.b` se corrige a **−0,02** con S_v = a·√(1 − f)·[1 − b(1 − f)] (Anwar 2026,
  tabla 9, y Hitchens 2018 [E]); f_BM(0) = **0,61** sin entrenar (Pan 2025 [E]). Sigue PENDIENTE: el paso de integración
  no se publica y la tabla 4 de Anwar no se reproduce sin su código.
- **Playa por franja** (`reglas.PLAYA_LINEA_BASE_PL1_PL6`, PENDIENTE): en PSI al galope el suelo cambia la zancada hasta
  0,186 m a la misma velocidad (Pfau 2024 [E]), más que el umbral de A7, así que las comparables deben ser de la misma
  franja; registro de marea, lluvia, humedad y nota del jinete.
Detalle: `knowledge/estudios/2026-11-19_extra5_modeloB_signo_b_playa_franjas.md`.

**Estudio horario 20/11 09:09 (KB-1 1.11.0, motor 2.0.0-dev13, sin cambios de lógica).**
- **A11:** Flethøj 2016 [E] (árabes de raid, [I-raza]): los cortes 20/10/4 % son acortamientos del RR escalonados por FC
  (< 60, 60–100, > 100 lpm) y el 4 % en ejercicio sobredetecta; se mantiene ≥ 5–6 % con FC > 100 lpm y el pendiente
  añade 10 %/20 % [I] para FC baja (solo INFO) y la FC pico sin prematuros (Navas de Solis 2026 [E]).
- **A9:** sin texto completo nuevo; VHRmax < 14,5 m/s (Gramkow 2006 [E-r]) solo informativo; no hay V200 publicada en
  árabes de llano, así que en árabes A9 dependerá solo de la línea base propia.
Detalle: `knowledge/estudios/2026-11-20_0909_v200_a9_ecg_a11_umbrales.md`.

**Estudio horario 20/11 10:08 (KB-1 1.12.0, motor 2.0.0-dev14, sin cambios de lógica).**
- **Índice tendinoso:** las OR de Takahashi 2004 (*JAVMA*) y Lam 2007 (*AJVR*) siguen [NV] (AVMA 403 en la sesión). Solo
  se conoce el sentido de los factores [E-r], que confirma A6/A6B/A6C. Se proponen [I] dos entradas cualitativas: lesión o
  exploración tendinosa previa, y peso en carrera alto para la cuadra. No hay pesos numéricos.
- **Árabes de llano:** fuentes en texto completo de Polonia y Turquía con trabajo rápido a 12,5–13,9 m/s en 800 m,
  2 sesiones intensas por semana y ≈ 42 % de enfermedad dorsal del metacarpo a los 3 años. Esto respalda los cortes
  relativos por caballo. Sin zancada, FC de carrera ni V200 publicadas.
Detalle: `knowledge/estudios/2026-11-20_1008_tendon_or_arabes_llano.md`.

**Estudio horario 20/11 11:10 (KB-1 1.13.0, motor 2.0.0-dev15, sin cambios de lógica).**
- **Regreso tras layup (planificador):** la evidencia está en los primeros 10–21 d de trabajo rápido tras ≥ 60 d sin él
  y es de fractura de húmero. Carrier 1998, PMID 9604029, da RR 71 y 45 sin IC y su DOI no está confirmado. Choi 2026
  (Corea) da OR 13,5 (5,5–33,1) en los primeros 20 d tras un layup > 60 d. Las dos fuentes solo se han leído por
  resumen [E-r]. Se propone **P7**, una ventana de reincorporación de 21 d (prudente 30 d) [I], sin implementar. No es
  una predicción de lesión.
- **Sensores 2025–2026:** Poinsard 2026 da una repetibilidad baja de la V200 en campo (ICC 0,50, trotones), lo que
  apoya que A9 siga siendo informativa. Van den Broek 2025 mide el sesgo de la curva en la zancada (LZ −2,1 %), que es
  del orden de la señal de A8. Li 2026 (EVJ) sigue sin leerse. No hay datos nuevos de árabes de llano.
Detalle: `knowledge/estudios/2026-11-20_1110_regreso_layup_sensores_2025_2026.md`.

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
