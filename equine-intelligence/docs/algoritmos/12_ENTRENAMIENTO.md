# 12 · AVO Training Analytics 1.0.0 — análisis de la historia de entrenamientos

Código: `include/avo_eq/training.h`, `src/training/training.cpp`, `src/capi/training_capi.cpp`.
Herramienta: `tools/training/avo_training_cli.cpp`. Pruebas: `tests/test_training.cpp` (10 casos, suite `entreno`).

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
- **NO VERIFICADO** con sesiones reales. Los factores de carga y los umbrales son valores de partida y hay que
  ajustarlos con la historia real de cada cuadra.
- Las tendencias con pocas sesiones son orientativas. El intervalo p10–p90 no es un intervalo de confianza formal.
