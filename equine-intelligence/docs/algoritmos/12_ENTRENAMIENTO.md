# 12 · AVO Training Analytics 1.2.0 — análisis de la historia de entrenamientos

Código: `include/avo_eq/training.h`, `src/training/training.cpp`, `src/capi/training_capi.cpp`.
Herramienta: `tools/training/avo_training_cli.cpp`. Pruebas: `tests/test_training.cpp` (13 casos, suite `entreno`).

**Objetivo:** comparar cada entrenamiento con la **historia del mismo caballo**, no con otros caballos.
Es la fase 1: estadística transparente, sin modelo entrenado. Es la base para las fases 2 (valoraciones del
entrenador como etiquetas) y 3 (modelos predictivos).

## Flujo en las aplicaciones
1. Después de cada análisis (`avo_eq_analyse_ex`), llamar a `avo_eq_training_summary(analisis, extra)` y guardar
   el resumen (`avo-training-session`, ~2 KB) junto a la sesión. `extra` aporta la fecha si el análisis no la
   tiene, la valoración del entrenador (RPE 0–10, estado, nota) y la pista.
2. Para ver la historia de un caballo: `avo_eq_training_analyse({"caballo", "sesiones": [{"resumen": …}, …]}, opciones)`.
   También acepta `analisis` completos o rutas (`ruta_resumen`, `ruta_analisis`).

El análisis de una sesión incluye ahora `sesion.inicio_utc`: la primera época GNSS con fecha y hora UTC resueltas,
o `null` si el receptor nunca las tuvo. Si es `null`, la aplicación pasa la fecha en `extra.fecha_utc`.

## 1. Resumen de sesión
Usa los segmentos de `rendimiento` del clasificador de referencia:
- **Tiempo y distancia** por aire: PASO, TROTE y GALOPE. El tiempo en movimiento suma también las transiciones.
- **Velocidad media** por aire, ponderada por duración. Se excluyen los segmentos con GNSS `NO_UTILIZABLE`.
- **Tranco, cadencia, correlación entre ciclos y CV de intervalos:** mediana ponderada por duración de los
  segmentos con calidad suficiente. Solo cuentan si el aire suma al menos `min_segundos_aire` (60 s); si no,
  quedan en `null`.
- **Distancia a alta velocidad** (> 11 m/s): se integra la serie de velocidad si la hay; si no, suma los
  segmentos con velocidad media por encima del umbral.
- **Aceleraciones** de la trayectoria GNSS (`cinematica`): sostenidas, frenadas y picos laterales, sin contar
  las de calidad `BAJA` o `NO_UTILIZABLE`. Son de la antena del jinete, no de la cincha.

## 1 bis. Ficha de campo (TRAINING 1.1.0, motor 2.0.0-dev28)
Campos opcionales de `extra` (y de cada entrada de la historia); el resumen los guarda con la misma forma. Los códigos
se pasan a mayúsculas; un valor no reconocido o fuera de rango se descarta con un aviso en el resumen.

| Clave | Valores |
|---|---|
| `tipo_sesion` | `TRABAJO`, `TRABAJO_REFERENCIA_1000`, `CARRERA`, `TRIAL`, `DESCANSO_ACTIVO` |
| `pista.franja` | `ORILLA_FIRME`, `HUMEDA_PROFUNDA`, `SECA_PROFUNDA`, `TRANSICION` (franja de playa, PL1) |
| `pista.going` | `FIRME`, `BUENO_FIRME`, `BUENO`, `BUENO_BLANDO`, `BLANDO`, `PESADO` (estratos de GO1) |
| `pista.marea` | `{"hora":"HH:MM", "tipo":"BAJAMAR"\|"PLEAMAR"}` (hora local de la marea de referencia) |
| `condiciones` | `temperatura_c` (−30–55), `humedad_pct` (0–100) |
| `pesos` | `jinete_kg` (30–150, con equipo), `caballo_kg` (150–1000, pesaje matinal en ayunas, PE1) |
| `incidencia` | `tipo` (`NINGUNA`, `TROPIEZO`, `CAIDA`, `ESPANTADA`, `COJERA`, `HERRAJE`, `EQUIPO`, `OTRA`) y `texto` (≤ 500 caracteres) |

Efectos en la historia: CARRERA y TRIAL cuentan como carrera para A4 y P3; con la franja anotada, A7/A8 solo comparan
la misma superficie y franja (PL1); la incidencia COJERA sube a REVISAR, CAIDA a VIGILAR y las demás solo se anotan
como motivo. El resto de campos se guarda para calibrar (going GO1, pesos PE1–PE3, temperatura TC, repetibilidad RB1).

## 2. Carga de entrenamiento
- **Carga externa (`AVO_TRAINING_LOAD_V1`)** = min_paso·1 + min_trote·3 + min_galope·6 + (m a alta velocidad / 100)·1.
  Es una **heurística configurable, sin validar** con datos fisiológicos (no hay pulsómetro). Sirve para comparar
  al caballo consigo mismo, no como medida absoluta.
- **Carga sRPE** (Foster) = RPE × minutos en movimiento. Solo se calcula si el entrenador anota el RPE. Las
  ventanas sRPE solo se dan cuando todas las sesiones de la ventana crónica tienen RPE.
- **Aguda** = suma de 7 días. **Crónica semanal** = suma de 28 días / 4.
- **ACWR** = (aguda / 1 semana) / crónica semanal. Solo se calcula si la historia cubre los 28 días.
  ACWR > 1,5: subida brusca (VIGILAR). ACWR < 0,8: descarga o parada (informativo).
- **Monotonía** (Foster) = media / desviación de la carga diaria de 7 días, con los días sin sesión a 0.
  Mayor que 2: VIGILAR. **Tensión** = aguda × monotonía.
- **Carga descriptiva CG1–CG3 (TRAINING 1.2.0, motor 2.0.0-dev34):** bloque `estado.carga_cg` con TRIMP recalculado
  desde el histograma de FC de cada sesión con una FC de referencia común (FM1), metros de trabajo rápido por bandas de
  Morrice-West, EWMA 7/28 d, cociente, monotonía y strain. Siempre INFO: **no** cambia el estado (a diferencia del ACWR
  de la carga heurística). Detalle, fórmulas y parámetros: ficha 14, §3 quinquies. Por sesión: `sesiones[].carga_cg`.

## 3. Línea base y desvíos
- Por aire y por métrica, se toma la **mediana y la MAD** de las sesiones anteriores de los últimos 60 días.
  Hacen falta al menos 4 sesiones; con menos, no se juzga.
- z = (valor − mediana) / max(1,4826·MAD, suelo). El suelo es el mayor entre un valor absoluto por métrica y el
  2 % de la mediana; evita alarmas cuando la historia es casi constante.
- |z| ≥ 2: VIGILAR. |z| ≥ 3: REVISAR. Solo suben el nivel los cambios en la dirección mala:
  - tranco y cadencia: en cualquier dirección;
  - correlación entre ciclos: solo si baja;
  - CV de intervalos: solo si sube.
- La **velocidad** es decisión del jinete: su desvío se informa, pero no sube el nivel.

## 4. Tendencias
Pendiente de **Theil-Sen** por semana en las últimas 8 semanas. Se calcula para cada métrica por aire, la carga
externa y la distancia, y hacen falta al menos 5 sesiones en 3 días distintos. Los percentiles 10 y 90 de las
pendientes por pares dan un intervalo aproximado:
- SUBE si p10 > 0;
- BAJA si p90 < 0;
- ESTABLE en otro caso.

## 5. Estado
`NORMAL | VIGILAR | REVISAR`, siempre con los motivos. Sube el nivel:
- la carga (ACWR o monotonía);
- los desvíos de la última sesión, si fue en los últimos 7 días;
- la valoración del entrenador: COJERA, COJO o DOLOR → REVISAR; CANSADO, RARO o MAL → VIGILAR.

Es **orientativo, no es un diagnóstico veterinario**, y no usa términos clínicos.

## 5 bis. Carreras previstas, A4 y base del planificador (TRAINING 1.1.0)
- Opción `carreras_previstas`: lista de fechas `AAAA-MM-DD` del caballo (en el iPad, Cuadra › Carreras previstas).
- **A4_CARGA_BAJA_PRECARRERA** (ficha 14): menos de 2 días con sesión rápida en los 28 d previos a la carrera →
  AVISO informativo en `base_cientifica.reglas` y comprobación en `base_cientifica.carreras[]`.
- `estado.planificador`: `dias_rapidos_7d`, `dias_desde_rapido`, `dias_entre_ultimos_rapidos`, `dias_desde_carrera`,
  `proxima_carrera` (`fecha`, `dias_hasta`, `dias_rapidos_28d`, `faltan_para_minimo`) y `pautas[]` (`regla`, `texto`,
  `evidencia`) con P1, RT1, A4 y P3. Nunca sube el estado; no es un plan automático.

## 5 ter. Planificador semanal, capa 2: la semana siguiente (TRAINING 1.3.0, motor 2.0.0-dev35)
`estado.planificador.semana_siguiente` propone los 7 días siguientes a la fecha de referencia. **Sin calibrar:** nunca
cambia el estado del caballo, no es una predicción de lesiones y el entrenador decide (`validado: false`). Código:
`src/training/planner.cpp`.

**Fase** (por orden): `REINCORPORACION_LENTA` si hace > 60 d (`base_cientifica.dias_descanso_vuelta`) del último rápido
(P4): 0 rápidos hasta llevar 28 d de trabajo lento en el bloque actual y después 1 rápido; `REINCORPORACION_RAPIDO`
durante los 21 d siguientes al primer rápido tras > 60 d sin él (P7): 1 rápido por semana (≥ 7 d entre rápidos);
`POTRO_2_ANOS` con edad de carreras 2 (DM1); `NORMAL` en otro caso. Con A1/A2/A3/A5 en LIMITAR, 1 rápido como mucho.
Edad = año de referencia − año de nacimiento (convenio del 1 de enero) o la opción `edad_anos`.

**Colocación** (determinista): carreras previstas → `CARRERA`; rápidos lo antes posible con ≥ 3 días desde el rápido o
la carrera anterior (RT1/P2), sin rápido en los 3 días previos ni en los 5 siguientes a una carrera; el día siguiente a
un rápido `SUAVE` (RT2) y el siguiente a una carrera `LIBRE`; un día `LIBRE` por semana (P2: el último día lento que no
precede a un rápido); el resto `LENTO`. Si no caben todos los rápidos, pauta P2.

**Distancias:** `rapido_ref_m` = mediana de metros rápidos (> 14 m/s en PSI, escalados en árabes) por día rápido en
60 d; tope `rapido_max_m` = 75 % de la mediana anterior en la vuelta (P4/P7 [I]) y 400 m en potros antes de 12 semanas de
preparación (DM1 [E/I]).

**Pautas (solo texto):** P5 media diaria de 60 d > P75 propio de esa media (≥ 180 d de historia) y también en los días
60–31 (no penaliza el último mes); P6 ≥ 183 d sin un hueco de ≥ 40 d sin sesiones; DM2 canter o rápido de 7/14/30 d
> 1,5 × media acumulada del bloque (≥ 28 d antes de la ventana; la de 30 d se omite si ya salta A3); DM3 canter del último
día rápido > mediana de los días lentos de 30 d; DM4 salto a ≥ 700 m sin haber pasado de 700 antes de 12 semanas;
aviso [I-raza] en árabes y aviso sin edad.

| Parámetro (`planificador.*`) | Defecto | Etiqueta |
|---|---|---|
| `rapidos_semana_maduro` / `rapidos_semana_2anos` | 2 / 2 | [E] práctica 2,0 y 1,7 (Morrice-West 2020); objetivo [I] |
| `dias_min_entre_rapidos` | 3 | [I] (sin evidencia directa; glucógeno 48–72 h [E-r]) |
| `dias_libres` | 1 | [E] práctica |
| `dias_sin_rapido_precarrera` / `dias_sin_rapido_poscarrera` | 3 / 5 | [I] |
| `p4_dias_lentos` / `p4_dias_hueco_bloque` | 28 / 14 | [E] 4,0 semanas (Morrice-West 2020) / [I] |
| `p7_dias_ventana` / `p7_fraccion_distancia` | 21 / 0,75 | [E-r] Carrier 1998 / [I] |
| `p5_dias` / `p5_percentil` / `p5_min_historia_dias` | 60 / 75 / 180 | [E-r] Estberg 1998 / [I] |
| `p6_descanso_min_dias` / `p6_intervalo_dias` | 40 / 183 | [E] 1,9–2,1 descansos de 6,3–6,6 sem / [I] |
| `dm1_rapido_max_m` | 400 | [E] Oliveira 2006 (n = 42) / [I] |
| `dm2_ratio`, `dm2_min_rapido_m`, `dm2_min_canter_m`, `dm2_min_historia_dias` | 1,5 / 200 / 2000 / 28 | [I] |
| `dm4_semanas` / `dm4_desde_m` / `dm4_hasta_m` | 12 / 500 / 700 | [E] Oliveira 2006 / [I] |
| `dias_horizonte` | 7 | — |
Opciones en la raíz: `fecha_nacimiento` (AAAA-MM-DD) y `edad_anos`; `planificador: false` lo desactiva.

**Ejemplo (prueba `planner_week_mature`):** maduro con rápido de 600 m cada 4 días y referencia el día de un rápido →
`SUAVE, LENTO, RAPIDO, SUAVE, LENTO, RAPIDO, LIBRE` (rápidos a +3 y +6 d). Potro de 2 años con carrera a +6 d → `SUAVE,
LENTO, LENTO, LENTO, LENTO, CARRERA, LIBRE` y pauta P2 (no cabe ningún rápido). Vuelta tras 82 d sin rápido con 10 d de
lento → semana sin rápidos y tope de 450 m (75 % de 600).

## Parámetros (opciones JSON)
| Opción | Defecto | Opción | Defecto |
|---|---|---|---|
| `factor_paso` / `factor_trote` / `factor_galope` | 1 / 3 / 6 | `dias_linea_base` | 60 |
| `alta_velocidad_m_s` / `factor_alta_velocidad` | 11 / 1 | `min_sesiones_linea_base` | 4 |
| `dias_aguda` / `dias_cronica` | 7 / 28 | `z_vigilar` / `z_revisar` | 2 / 3 |
| `acwr_alto` / `acwr_bajo` | 1,5 / 0,8 | `min_segundos_aire` | 60 |
| `monotonia_alta` | 2 | `dias_tendencia` / `min_sesiones_tendencia` | 56 / 5 |
| `dias_descanso_aviso` | 10 | | |

## Validación y límites
- **IMPLEMENTADO** y probado con datos sintéticos: fechas, resumen, carga estable (ACWR ≈ 1), pico de carga,
  desvío del tranco (z ≈ −6), dirección de la regularidad, valoración del entrenador, tendencia exacta de
  0,1 m/s por semana, duplicados y fechas futuras, API C y determinismo. Todo con ASan y UBSan.
- TRAINING 1.1.0: ficha de campo (ida y vuelta y valores no válidos), incidencias, A4 con fechas previstas y con
  sesión TRIAL, planificador (P1, P3, días que faltan) y comparables por franja, con ASan y UBSan.
- TRAINING 1.3.0: planificador de la semana siguiente (fase normal, potro con carrera, vuelta P4/P7, P5 con y sin el
  último mes, P6, DM2–DM4, árabes y opciones) con ASan y UBSan.
- **NO VERIFICADO** con sesiones reales. Los factores de carga y los umbrales son valores de partida y hay que
  ajustarlos con la historia real de cada cuadra.
- Las tendencias con pocas sesiones son orientativas. El intervalo p10–p90 no es un intervalo de confianza formal.

## Ampliación trabajo en pista (entrenamiento de caballos de carreras, ficha 13)
- Con el bloque `trabajo_pista` del análisis, el resumen guarda la raza, la carga VeDBA, la mano, los trabajos, las fases, las series, la recuperación, la zancada a las velocidades de referencia, el índice de caída y los eventos.
- La distancia a alta velocidad usa el umbral de la raza.
- La historia añade la carga VeDBA (aguda, crónica semanal y ACWR) y las líneas base y tendencias `TRABAJO.*` y `CINCHA.*`.
- Los impactos atípicos suben a VIGILAR.

## Base científica KB-1 (ficha 14)
- El resumen guarda `trabajo_pista.base_cientifica`. La historia añade `estado.base_cientifica` y `sesiones[].base_cientifica` con las ventanas de 7, 30 y 60 días y las reglas A1–A6 y de fatiga ósea. Las reglas VIGILAR suben el estado.

## ECG de la cincha: V200, VHRmax y ectopia (ficha 15, motor 2.0.0-dev29)
- El resumen guarda `cardio` (V200 y su método, V200 por regresión, VHRmax y su método, FC pico, recuperación a 1, 2, 4,
  5, 10 y 15 min y ectopia). Sin ECG utilizable no hay V200.
- Reglas: `A9_PERDIDA_FORMA` (V200/VHRmax bajo la línea base propia, misma superficie y método, TE por defecto del 3 %
  NO VALIDADO), `A9_V200_SALTO` (cambio > 5 % en ≤ 31 d: posible artefacto) y `A11_ECG` (candidatos a revisar, nunca un
  diagnóstico). Opciones en `base_cientifica`: `te_v200_pct`, `swc_v200_pct`, `salto_v200_pct`, `dias_salto_v200`.
