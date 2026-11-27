# Protocolo de pruebas de campo del PROTOTIPO para calibrar el motor

**Versión:** 1.0 (21/11/2026) · **Motor:** 2.0.0-dev27 (Training Analytics 1.1.0, KB-1 1.25.0) · **Estado:** protocolo
escrito, **sin ejecutar**. Nada de lo que describe está verificado con caballos reales.

**Para qué sirve:** convertir los umbrales de partida ([I]) de las reglas A7, A8 y A9 en números de la cuadra. Para
eso hace falta medir el **error típico (TE) propio** de cada métrica con trabajos repetidos, y registrar en cada sesión
las condiciones que cambian la medida (superficie, franja de playa, marea, going, temperatura, pesos).

Referencias: `equine-intelligence/docs/algoritmos/12_ENTRENAMIENTO.md` (ficha de campo),
`14_BASE_CIENTIFICA.md` (reglas), `knowledge/estudios/2026-11-18_estudio_ampliado_PSI_arabe.md` (fase 2 del plan de
validación), `2026-11-19_extra5_modeloB_signo_b_playa_franjas.md` (playa por franjas) y
`2026-11-20_2209_lesiones_arabes_turquia_repetibilidad_v200.md` (bloque RB1).

## 1. Equipo (solo PROTOTIPO)

| Pieza | Placa | Firmware |
|---|---|---|
| Pecho | Waveshare ESP32-S3 AMOLED 2.06" (caja REV D) | **3.7.10** (o la 3.7.11 si ya está instalada; anotar cuál) |
| Espalda | Heltec Wireless Stick Lite V3 + ZED-F9P + Pololu S7V8F3 (carcasa V2.2H Rev E.5) | **3.14.x** (o la 3.15.0; nunca la 4.0.0-dev de la espalda V4) |
| Cincha | XIAO ESP32-C6 + BNO085 + MAX30003 (cápsula REV 5.10) | **0.5.0** |
| App | iPad (ficha de campo y carreras previstas) | build de TestFlight con motor 2.0.0-dev27 |

- Ninguna pieza BETA (cincha PCB REV D, casco V5, DOCK V1, espalda V4) entra en estas pruebas.
- RTK: anotar en cada sesión si hubo **FIX** en el tramo de referencia. Sin FIX el tramo no cuenta para el TE.
- Antes de cada jornada: baterías cargadas, hora del pecho correcta, cincha en la misma posición (marca en la cincha).

## 2. Qué registrar en cada sesión

En el iPad, Análisis › **Valoración del entrenador** › **Ficha de campo**. Todo es opcional para el motor, pero en las
pruebas de calibración es **obligatorio** lo marcado con ●.

| Campo | Cómo | Para qué |
|---|---|---|
| ● Caballo y jinete | asignación de la sesión (Cuadra) | línea base propia |
| ● Tipo de sesión | TRABAJO · TRABAJO_REFERENCIA_1000 · CARRERA · TRIAL · DESCANSO_ACTIVO | TE (solo referencias), A4 (CARRERA/TRIAL) |
| ● Superficie | pista › superficie (playa, arena, hierba…) | comparables de A7/A8 |
| ● Franja de playa | ORILLA_FIRME · HUMEDA_PROFUNDA · SECA_PROFUNDA · TRANSICION | PL1: comparables por franja |
| ● Marea | hora (HH:MM, hora local) y tipo (BAJAMAR/PLEAMAR) de la marea de referencia | PL2 |
| Going | FIRME · BUENO_FIRME · BUENO · BUENO_BLANDO · BLANDO · PESADO (fuera de la playa) | GO1 |
| ● Temperatura y humedad | del móvil o estación más cercana, a la hora del trabajo | TC1–TC5, RB1 |
| ● Peso del jinete | con silla y equipo, en kg | PC1–PC4 |
| Peso del caballo | báscula, **por la mañana en ayunas** y nunca < 12 h tras un trabajo rápido | PE1–PE3 |
| ● RPE y estado | RPE 1–10 y BIEN/CANSADO/RARO/COJERA | sRPE, estado |
| ● Incidencia | tipo (TROPIEZO, CAIDA, ESPANTADA, COJERA, HERRAJE, EQUIPO, OTRA) y texto con el tramo | descartar la sesión del TE |
| Nota | lluvia de las últimas 24–48 h, viento, cambio de herraje, calentamiento distinto | PL2, WU3 |

Además, en la hoja de la jornada (papel o nota del iPad): hora de inicio del calentamiento, versión de los tres
firmwares y número de serie de la cincha.

## 3. Trabajo de referencia de 1.000 m (fase 2 del plan de validación)

**Objetivo:** el TE propio de cada métrica, con `TE = DE(diferencias entre las dos repeticiones) / √2` (Hopkins [E]).

### 3.1 Diseño
- **Caballos:** 8–10 (anotar raza PSI o ÁRABE; si hay de las dos, cada raza es su propio grupo).
- **Repeticiones:** el mismo trabajo **2 veces en 3–7 días** por caballo. Si se puede, una 3.ª dentro de los 7 días:
  así el bloque cumple RB1 (≥ 3 sesiones con ≤ 7 d entre ellas).
- **Constante entre repeticiones:** el mismo tramo (mismos conos o puntos GNSS de salida y meta), la misma superficie y
  franja, el mismo calentamiento (mismo tiempo de paso y trote, ±20 %), el mismo jinete si es posible, y la misma
  consigna de velocidad.
- **Consigna de velocidad:** PSI con los últimos 600 m a 15,5–16,7 m/s; árabe al 93–100 % de su `v_ref` (14,5 m/s por
  defecto). El trabajo debe pasar por **14 y 16 m/s en PSI** y por **13 y 14 m/s en árabe** con al menos 3 s estables
  en cada una (son las velocidades de referencia de la zancada).
- **Ficha:** tipo de sesión **TRABAJO_REFERENCIA_1000** en las dos repeticiones. No hacer otro trabajo rápido entre las
  dos (≥ 72 h desde el último, RT1).

### 3.2 Procedimiento
1. Calentamiento fijo (por ejemplo 10 min de paso y 8 min de trote; anotar el que se use y repetirlo).
2. Canter de aproximación de 400 m.
3. Trabajo de 1.000 m con la consigna; los últimos 600 m son los que mide A8.
4. Vuelta a la calma al paso, **sin parar al caballo en los primeros 2 min** (recuperación de la FC a 60 y 120 s).
5. Ficha de campo completa en el iPad antes de 1 h.

### 3.3 Qué sale de cada repetición
| Métrica | Dónde la da el motor | Regla que calibra |
|---|---|---|
| V200 (velocidad a 200 lpm) | ECG de la cincha 0.5.0, regresión FC–velocidad (pendiente A9) | A9 |
| Velocidad de los últimos 600 m | `trabajo_pista.v_ultimos_600m` | A8 |
| Zancada a 14 y 16 m/s (PSI) / 13 y 14 m/s (árabe) | `trabajo_pista.referencia[].l_m` (métricas `TRABAJO.l_v1_m`, `TRABAJO.l_v2_m`) | A7 |
| Regularidad (correlación entre ciclos, CV de intervalos) | `aires.GALOPE` | desvíos de la línea base |
| Recuperación de la FC a 60 y 120 s | ECG de la cincha | RB1, A9 |

### 3.4 Criterios para que una repetición cuente
- RTK FIX durante todo el tramo de 1.000 m.
- Cincha sin saturaciones en el tramo (`trabajo_pista.eventos.saturacion = 0`) y ECG con < 10 % de latidos no interpretables.
- Sin incidencia (tipo NINGUNA o vacío) y la misma franja que la otra repetición.
- Velocidad media de los últimos 600 m a ±0,3 m/s de la otra repetición (si no, el jinete no repitió la consigna).

Las repeticiones que no cumplan se guardan, pero no entran en el TE; se anota por qué.

## 4. Playa de Laredo: franja y marea

No hay datos publicados de galope de carreras sobre playa: la medida propia es la única referencia. En la playa el suelo
cambia la zancada a igual velocidad más que el umbral de A7 (hasta 0,186 m en Pfau 2024 [E]), así que **cada franja
es una superficie distinta**.

- **Franja:** elegir antes del trabajo y no cambiarla dentro del tramo de referencia. Si el tramo cruza de una franja a
  otra, anotar TRANSICION (esa sesión no se compara con las demás).
  - ORILLA_FIRME: arena compactada y húmeda junto al agua (la que deja la bajamar).
  - HUMEDA_PROFUNDA: arena mojada en la que el casco se hunde.
  - SECA_PROFUNDA: arena seca y suelta por encima de la línea de pleamar.
- **Marea:** anotar la hora de la **bajamar** más cercana (pantalla Mareas de la app). Para las referencias, trabajar en
  la misma ventana respecto a la bajamar en las dos repeticiones (por ejemplo, entre −1 h y +1 h), porque la anchura y
  la humedad de la orilla cambian con la marea.
- **Lluvia de las 24–48 h previas y viento fuerte:** en la nota.
- **Rápidos sobre orilla compactada y cambios bruscos de franja** dentro de una semana: anotarlos (PL6); son los casos
  que la base marca para revisar.
- Las primeras 4–6 sesiones en cada franja forman su línea base; hasta entonces A7/A8 no juzgan esa franja.
- **Motor 2.0.0-dev39 (PL2–PL6, `estado.playa`):** para calibrarlo hace falta, por caballo, ≥ 4 sesiones en cada franja
  usada (mínimo `min_sesiones_franja`), con la cincha y la espalda (zancada a las 2 velocidades de referencia y
  velocidades distintas entre sesiones: la pendiente propia pide ≥ 8 pares y DE de la velocidad ≥ 0,5 m/s). En la ficha:
  `humedad_suelo_pct` (3–5 lecturas con sonda TDR en la franja del trabajo, mismo operador), `lluvia_48h_mm` (AEMET
  Treto o pluviómetro de la cuadra) y `nota_suelo` del jinete. Con esos datos se ajustan los cortes de humedad (13/19 %),
  el de orilla compacta, el 70 % de franja dominante y el efecto de cada franja frente a la orilla firme.

## 5. Cómo se usan los datos para calibrar A7, A8 y A9

1. **Exportar** los resúmenes de sesión (`training_summary.json`) de las referencias y la ficha.
2. **TE por métrica, raza y superficie/franja:** `TE = DE(x₂ − x₁)/√2` con los pares válidos (8–10 caballos).
   SWC = 0,2 × DE entre caballos de la media de sus repeticiones.
3. **Umbral de cambio real:** `max(2·TE·√(1 + 1/n), SWC)` (`kb_change_threshold`), con n = sesiones de la línea base.
4. **A7 (zancada):** si el umbral calculado para `l_v1_m`/`l_v2_m` difiere del de partida (0,10 m), proponer el nuevo
   valor de `caida_zancada_m` por franja; si el TE de la playa es mayor que el de la pista, A7 se queda solo con el
   CUSUM en la playa hasta tener más sesiones.
5. **A8 (velocidad final):** lo mismo con `v_ultimos_600m` y `caida_v_600m` (partida 0,20 m/s). Si el TE es comparable
   a la variación de la consigna del jinete, A8 se queda en INFO.
6. **A9 (V200):** el TE propio y el umbral `max(√2·TE, SWC)` son los que faltan para implementarla (sigue PENDIENTE);
   solo con bloques RB1 y temperatura registrada.
7. **Base científica:** los TE y umbrales nuevos entran en `knowledge/base_cientifica.json` como hallazgo de la cuadra
   (fecha, caballos, sesiones), con nueva `KNOWLEDGE_VERSION`, sus pruebas y un PR propio. Nunca se cambia un umbral
   con menos de 8 caballos o sin los pares válidos.

## 6. Carreras previstas (A4) durante las pruebas

En la Cuadra, cada caballo con carrera o trial a la vista lleva sus **carreras previstas**. Con ellas la historia avisa
(A4, informativo) si en los 28 días previos hay menos de 2 días de trabajo rápido, y el planificador muestra los que
faltan. Las sesiones con tipo CARRERA o TRIAL cuentan como carrera. Es una pauta de la literatura con corte [I], no una
orden: el entrenador decide.

## 6 bis. Carga de entrenamiento CG1–CG3 (motor 2.0.0-dev34)
Para calibrar la carga descriptiva (hoy con valores por defecto «no propios»):
- **FC de reposo:** 5 min con el caballo parado en el box o atado, con la cincha 0.5.0 puesta y el ECG en marcha antes de
  montar; anotar la mediana de la FC en la valoración (se pasará como `fc_reposo_lpm`). Repetir 3 días.
- **FC máxima propia:** basta con ≥ 3 trabajos rápidos con ECG `BUENA` o `UTILIZABLE` (el motor la toma sola, FM1);
  revisar en las épocas que el pico no sea un artefacto.
- **Cobertura:** que ≥ 80 % de cada sesión tenga FC válida (electrodos húmedos, cincha bien apretada); si no, la sesión
  no aporta TRIMP a la historia.
- **Continuidad:** ≥ 8 semanas seguidas con GNSS y ECG en todas las sesiones para ver cómo se mueve el cociente propio
  (con > 20 % de sesiones sin dato en 28 días el motor no lo calcula).
- Los coeficientes b y c del TRIMP no se pueden calibrar con el PROTOTIPO (harían falta prueba estándar y lactato).

## 6 ter. Planificador semanal, capa 2 (motor 2.0.0-dev35)
La historia propone la semana siguiente (`estado.planificador.semana_siguiente`) con separaciones y topes **sin
calibrar**. Para calibrarlos con el PROTOTIPO hace falta:
- **Registrar todas las sesiones**, también las lentas, con la espalda (GNSS RTK): el planificador deduce los descansos
  (P6) y el inicio del bloque (P4, DM1–DM4) de los días sin sesión; una sesión no grabada parece un día libre.
- **Año de nacimiento** de cada caballo en la Cuadra (el iPad lo pasa como `fecha_nacimiento`): sin él no se aplican
  las pautas de potros de 2 años.
- **Anotar la semana que hizo de verdad el entrenador** frente a la propuesta durante ≥ 8 semanas por caballo
  (rápidos por semana, días entre rápidos, días libres, distancia del rápido) para ajustar `rapidos_semana_*`,
  `dias_min_entre_rapidos`, `dias_sin_rapido_precarrera` y `dias_sin_rapido_poscarrera` a la práctica de la cuadra.
- **Vuelta de un descanso ≥ 60 d:** anotar cuándo vuelve el primer rápido y su distancia (P4/P7: 28 días lentos y
  75 % de la mediana anterior son [I]).
- **P5:** ≥ 180 días de historia continua para tener el P75 propio de la distancia rápida de 60 d.

## 6 quater. Cinética de la FC: calentamiento y recuperación (motor 2.0.0-dev40)
El motor calcula el calentamiento (WU2), la FC de un tramo fijo de trote (FW1), la τ de recuperación (CF2) y el THR100
(RC1), todo **sin calibrar**. Para calibrarlos con el PROTOTIPO (cincha 0.5.0 con ECG, espalda con GNSS RTK):
- **Tramo fijo:** el mismo calentamiento cada día, con ≥ 60 s seguidos de trote estable entre 3 y 6 m/s justo antes del
  trabajo rápido, en la misma superficie (y franja en la playa).
- **Recuperación:** dejar el ECG grabando **≥ 10 min** tras el último rápido, sin quitar la cincha, y hacer siempre la
  misma vuelta a la calma (al paso de la mano o montado); anotarla si cambia. Sin ≥ 5,5 min no hay τ.
- **Error típico propio:** ≥ 3 sesiones iguales en ≤ 7 días para ver cuánto varían τ, THR100 y la FC del tramo fijo de
  un día a otro; con eso se sustituirán el +25 % y los +8 lpm por defecto.
- **Temperatura:** anotar la temperatura en la ficha de campo; aún no es criterio de comparables (TC1 pendiente) y el
  calor alarga la recuperación.

## 7. Registro

Cada jornada se anota en `docs/REGISTRO_DE_CAMBIOS.md` (o en un informe de sesiones reales) con: fecha, caballos,
versiones de firmware, sesiones válidas y descartadas, y el nivel alcanzado. Hasta entonces todo lo de este protocolo es
**NO VERIFICADO** con caballos reales.
