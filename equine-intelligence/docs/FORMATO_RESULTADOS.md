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
