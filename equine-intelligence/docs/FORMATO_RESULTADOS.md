# Formato de resultados y API — motor 1.1.0

## API C (versión 2) — `include/avo_eq/avo_eq_c.h`
| Función | Uso |
|---|---|
| `avo_eq_version()` / `avo_eq_api_version()` | "1.1.0-dev1" / 2 |
| `avo_eq_analyse_files(...)` | API 1, se mantiene |
| `avo_eq_analyse_ex(paths, n, opciones, cancel, &json)` | análisis con opciones, cancelación y persistencia |
| `avo_eq_compare_ex(a, na, b, nb, opciones, cancel, &json)` | comparación (`avo-equine-comparison`) |
| `avo_eq_cache_invalidate(dir)` | borra análisis de versiones antiguas |
| `avo_eq_free(p)` | libera cualquier texto devuelto |

Códigos: 0 ok · 1 entrada · 2 argumentos · 3 interno · 4 cancelado · 5 opciones. En error, `{"error":"…","codigo":N}`.
Opciones: `modo` (OFFLINE | TIEMPO_REAL), `series`, `procesado_utc`, `clasificador_rendimiento` (V1 | V2), `modelo_aires`,
`cache_dir`, `forzar`, `sensores_calibrados`; comparación: `seleccion_a`, `seleccion_b`, `mismo_recorrido`.
Textos UTF-8. JNI pasa `byte[]` UTF-8 (no «modified UTF-8»); C# usa `Marshal.PtrToStringUTF8`.

## JSON `avo-equine-analysis` versión 2
Se conservan **todas** las claves de la versión 1 (`sesion`, `parametros`, `metricas`, `rtk`, `aires`, `anomalias`, `calidad`, `series.t/velocidad/aceleracion`).
Añadidas: `aires.clasificador` y `segmentos[].codigo`; `procedencia` (huella, hash de parámetros, modo, `itow_inicial_ms`,
`algoritmos`, `unidades`, `tiene_cincha`, `tiene_gnss`); `advertencias`; `cinematica`; `curvas`; `aires_v2`; `rendimiento`
(`segmentos`, `por_aire`, `sesion`); `fusion` (estados y `relaciones`); `simetria` (`etiqueta`, `controles`, `grupos`,
`entre_sensores`); `eventos`; `cadencia_estado_ventanas`; con series: `series` (t, velocidad, sigmas, aceleración, lateral,
curvatura, distancia, lat, lon, calidad, aire) + `unidades_series` + `series_cincha` (por ventana: imu, t, σt, cadencia y σ, tranco,
regularidad, velocidad, estado). Con persistencia: `cache`, `fichero_resultado`.
Métricas nuevas: `distancia_puenteada` (regla del analizador Kotlin anterior, solo para comparar), `regularidad_amplitud_cv`,
`estabilidad_espectral`, `incertidumbre_media_ventana`, `ventanas_cadencia_validas`.
**Cambio de semántica:** `frecuencia_hz` de una ventana es 0 salvo estado VALIDA; GAIT_CLASSIFIER_V1 (1.0.1) solo recibe cadencias válidas.

## Análisis de entrenamientos (AVO Training Analytics 1.0.0) — ficha 12
API: `avo_eq_training_summary(analisis_json, extra_json, &json)` y `avo_eq_training_analyse(entrada_json, opciones_json, cancel, &json)`.
Mismos códigos de retorno; el texto se libera con `avo_eq_free`.
- **`avo-training-session` v1** (resumen de una sesión): `id`, `caballo`, `jinete`, `fecha_utc`, `tiempo_movimiento_s`,
  `distancia_m`, `velocidad_max`, `distancia_alta_velocidad_m`, `tiene_cincha`, `aires.{PASO,TROTE,GALOPE}`
  (`duracion_s`, `distancia_m`, `velocidad_media`, `velocidad_max`, `longitud_tranco_m`, `cadencia_hz`,
  `correlacion_ciclos`, `cv_intervalos`), `aceleraciones`, `calidad`, `valoracion` (`rpe`, `estado`, `nota`),
  `pista`, `avisos`.
- **`avo-training-analysis` v1** (historia): `caballo`, `fecha_referencia`, `sesiones_usadas`, `parametros`,
  `estado` (`nivel` NORMAL|VIGILAR|REVISAR, `motivos`, `dias_desde_ultima`, `carga`), `carga_diaria` (28 días),
  `lineas_base` (`metrica`, `mediana`, `mad`, `n`, `estado`), `tendencias` (`pendiente_semana`, `pendiente_p10`,
  `pendiente_p90`, `relativa_semana`, `n`, `direccion`), `sesiones[]` (`nivel`, `motivos`, `carga`, `desvios`, `resumen`),
  `avisos`.
- `carga`: `externa`, `srpe`, `aguda`, `cronica_semanal`, `acwr`, `aguda_srpe`, `cronica_semanal_srpe`, `acwr_srpe`,
  `monotonia`, `tension`, `dias_desde_anterior`.
- Métricas: `AIRE.velocidad_media`, `AIRE.longitud_tranco_m`, `AIRE.cadencia_hz`, `AIRE.correlacion_ciclos`,
  `AIRE.cv_intervalos`, más `carga_externa` y `distancia_m` en las tendencias.

`avo-equine-analysis` v2 añade `sesion.inicio_utc` (primera época GNSS con fecha y hora UTC, o `null`).

## Bloque `trabajo_pista` (AVO Track Work 1.0.0: entrenamiento de caballos de carreras) — ficha 13
Opciones de `avo_eq_analyse_ex`: `raza` (GENERICO | PSI | ARABE), `parcial_m` (200; 201.168 = furlong), `signo_mano` (0 | 1 | −1).
`trabajo_pista`:
- `modulo` = `AVO_TRACK_WORK`, `perfil`;
- `cincha`: `escala`, `lsb_por_g`, `calidad_vertical`, `sentido_avance_confirmado`, `vedba_media_g`, `carga_vedba_g_min`,
  `vedba_por_aire_g`, `giros`, `giros_por_aire`, `muestras_saturadas`;
- `zancadas`: medianas y `lista` con t0, t1, f_hz, v, l_m, pico_v_g, desp_v_m, vedba_g, rasgo_lateral, giro_deg_s, mano y curva;
- `mano`: `signo`, `calibracion`, `acuerdo_curvas`, zancadas por mano, `cambios`, `mano_de_fuera_en_curva_pct`;
- `trabajos`: distancias, `v_max`, `mejor_200m_s` y `lista` con, para cada trabajo: tipo, velocidades, `parciales`, `mejores`,
  últimos 200/400 m, `indice_caida_pct`, zancada a la máxima, `ajuste_f`, `ajuste_l`, `referencia`, mano,
  `recuperacion_hasta_paso_s`, `pausa_hasta_siguiente_s` y `v_media_pausa`;
- `fases`: `calentamiento`, `trabajo` y `vuelta_a_la_calma`, cada una con duración, distancia y segundos parado, al paso, al trote y al galope (`null` si no hay trabajos);
- `series`: `repeticiones`, `rapidas`, `caida_v_max_pct`, `caida_zancada_pct`, `recuperacion_media_s`, `calentamiento_corto`;
- `eventos`;
- `avisos`.

El resumen `avo-training-session` añade `trabajo_pista` (con `sesion`) y la carga de la historia añade `vedba`, `aguda_vedba`, `cronica_semanal_vedba` y `acwr_vedba`.
