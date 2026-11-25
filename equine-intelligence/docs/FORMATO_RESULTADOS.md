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

## Bloque `cardio` (AVO Cardio 1.0.0, motor 2.0.0-dev29) — ficha 15
Siempre presente. Sin ECG en el RAW: `{"presente":false,"version","algoritmo"}`. Con el ECG de la cincha 0.5.x:
`fuente` (`CINCHA_MAX30003_FMT2`), `lotes`, `lotes_duplicados`, `muestras`, `muestras_no_validas`, `fs_hz`, `alineada_gnss`,
`duracion_s`, `polaridad_s`, `latidos`, `rr_validos`, `artefacto_pct`, `calidad` (BUENA | UTILIZABLE | POBRE | NO_UTILIZABLE),
`fc_pico_lpm`, `fc_max_epoca_lpm`, `fc_media_lpm`, `fin_esfuerzo_s`, `fc_bajo_120_tras_s`, `vuelta_calma`;
`fases.{CALENTAMIENTO,MAXIMA,RECUPERACION_0_2MIN,RECUPERACION_TARDIA}` (`t0`, `t1`, `duracion_s`, `artefacto_pct`,
`interpretable`, `latidos`, `ectopicos_candidatos`, `ectopicos_candidatos_fc_mayor_100`); `v200` (método `CRUCE_200_10S`,
`t_cruce_s`, `validada: false`, `calentamiento_suficiente`, `motivo`), `v200_regresion` (método `REGRESION_FC_VELOCIDAD`,
pendiente, intercepto, `r2`, `mesetas`), `vhrmax` (`metodo`), `recuperacion[]` (`min` 1, 2, 4, 5, 10, 15; `fc_lpm`,
`caida_lpm`), `ectopia` (`tipo: CANDIDATO_A_REVISAR`, `umbral_pct`, `candidatos`, `aislados`, `parejas`, `tripletes`,
`rachas`, `nivel` INFO | VIGILAR, `texto`, `diagnostico: false`), `avisos`. Con series: `epocas` ([t0, FC, v, artefacto]
cada 5 s) y `latidos_rr` ([t, RR, candidato]). Tiempos en s GNSS desde la primera época.

**Cardio 1.1.0 (motor 2.0.0-dev34, KB 1.30.0):** `carga_interna` (CG1, descriptiva): `regla` `CG1`, `algoritmo`
`TRIMP_BANISTER_EQUINO_CG1`, `validado: false`, `trimp` y `trimp_sin_ponderar` (UA; `null` con ECG NO_UTILIZABLE),
`minutos_con_fc`, `cobertura_pct`, `cobertura_baja` (< 80 %), `s_mas_180`, `s_mas_200`, `s_sobre_fc_max`,
`fc_reposo_lpm`/`fc_reposo_origen` y `fc_max_lpm`/`fc_max_origen` (POR_DEFECTO | CABALLO), `b`, `c`, `etiquetas`
(`formula`, `coeficientes`, `fc_reposo`, `fc_max`), `histograma_fc` (`ancho_lpm` 5, `s`: [[límite inferior lpm, segundos], …]
solo intervalos con tiempo) y `nota`. Opciones nuevas de `avo_eq_analyse_ex`: `fc_reposo_lpm` (20–60) y `fc_max_lpm` (150–260).

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

**Training 1.2.0 (motor 2.0.0-dev34):** el resumen añade `trabajo_pista.base_cientifica.bandas_cg_m` (6), `rapido_m`,
`escala_cg` y `cardio.trimp`, `cardio.trimp_cobertura_pct`, `cardio.histograma_fc`. La historia añade
`estado.carga_cg` (CG1–CG3, `nivel` siempre INFO, `validado: false`): `parametros` (con `etiquetas`), `fc_referencia`
(`fc_reposo_lpm`, `fc_reposo_origen`, `fc_max_lpm`, `fc_max_origen` POR_DEFECTO | CABALLO | PROPIA_HISTORIA,
`trabajos_rapidos_con_fc`), `interna` y `externa` (`sesion`, `total_corto` 7 d, `total_largo` 30 d, `ewma_aguda`,
`ewma_cronica`, `cociente`, `monotonia`, `strain`, `sesiones_con_dato`, `sesiones_sin_dato`, `motivo`), `bandas`
(`escala`, `bandas[]`: `banda`, `v_min_psi`, `v_max_psi`, `total_corto_m`, `total_largo_m`), `diaria` (28 días:
`fecha`, `rapido_m`, `trimp`), `notas`, `nota`; y `sesiones[].carga_cg` (`trimp` recalculado, `rapido_m`). Opción
`carga_cg` (true/false u objeto; ficha 14, §3 quinquies).

**Training 1.4.0 (motor 2.0.0-dev37):** `semana_siguiente` añade `semana_calendario` (bool), `planifica_desde`
(AAAA-MM-DD) y `rapidos_hechos`; cada día de `dias` añade `realizado` (bool: día pasado, lo hecho según las sesiones) y, desde 2.0.0-dev38, `rapido_hecho_m` (metros de galope rápido hechos ese día; `null` sin datos de carga). Con la
semana natural (por defecto) `desde`/`hasta` son el lunes y el domingo. Opción `planificador.semana_calendario` (true/false).

**Training 1.3.0 (motor 2.0.0-dev35):** `estado.planificador` añade `semana_siguiente` (capa 2 del planificador,
`validado: false`, nunca cambia el estado): `disponible` (y `motivo` si no lo está), `desde`, `hasta`, `fase` (NORMAL |
POTRO_2_ANOS | REINCORPORACION_LENTA | REINCORPORACION_RAPIDO), `limitada`, `edad_anos`, `edad_origen`
(FECHA_NACIMIENTO | EDAD_ANOS | null), `raza`, `rapidos_objetivo`, `rapidos_propuestos`, `dias_lentos_bloque`,
`vuelta_rapido`, `semanas_preparacion`, `rapido_ref_m`, `rapido_max_m`, `p5_media_60d_m`, `p5_p75_m`,
`dias_desde_descanso`, `dias[]` (`fecha`, `tipo` RAPIDO | LENTO | SUAVE | LIBRE | CARRERA, `motivo`, `rapido_max_m`,
`reglas[]`), `pautas[]` (`regla`, `texto`, `evidencia`), `parametros` (con `etiquetas`) y `nota`. Campos sin dato:
`null`. Opciones nuevas: `planificador` (true/false u objeto), `fecha_nacimiento`, `edad_anos` (ficha 12, §5 ter).

`avo-equine-analysis` v2 añade `sesion.inicio_utc` (primera época GNSS con fecha y hora UTC, o `null`).

## Bloque `trabajo_pista` (AVO Track Work 1.0.0: entrenamiento de caballos de carreras) — ficha 13
Opciones de `avo_eq_analyse_ex`: `raza` (GENERICO | PSI | ARABE), `parcial_m` (200; 201.168 = furlong), `signo_mano` (0 | 1 | −1),
`recorrido` ({`nombre`, `salida` / `meta` / `salida_meta`: {`a`, `b`: [lat, lon], `sentido`}, `geocerca`: [[lat, lon], …]}) o `plan_geocercas` (objeto de `geocercas.json`).
`trabajo_pista`:
- `modulo` = `AVO_TRACK_WORK`, `perfil`;
- `cincha`: `escala`, `lsb_por_g`, `calidad_vertical`, `sentido_avance_confirmado`, `vedba_media_g`, `carga_vedba_g_min`,
  `vedba_por_aire_g`, `giros`, `giros_por_aire`, `muestras_saturadas`;
- `base_cientifica.carga_externa` (KB 1.30.0, CG2): `regla`, `escala` (ABSOLUTAS_PSI | RELATIVAS_V_CARRERA), `etiqueta`,
  `bandas[]` (`banda` LENTO…RAPIDO_4, `v_min`, `v_max`, `distancia_m`, `tiempo_s`), `v_rapido_m_s`, `rapido_m`, `nota`;
- `zancadas`: medianas y `lista` con t0, t1, f_hz, v, l_m, pico_v_g, desp_v_m, vedba_g, rasgo_lateral, giro_deg_s, mano y curva;
- `mano`: `signo`, `calibracion`, `acuerdo_curvas`, zancadas por mano, `cambios`, `mano_de_fuera_en_curva_pct`;
- `trabajos`: distancias, `v_max`, `mejor_200m_s` y `lista` con, para cada trabajo: tipo, velocidades, `parciales`, `mejores`,
  últimos 200/400 m, `indice_caida_pct`, zancada a la máxima, `ajuste_f`, `ajuste_l`, `referencia`, mano,
  `recuperacion_hasta_paso_s`, `pausa_hasta_siguiente_s` y `v_media_pausa`;
- `recorrido` (`null` sin líneas): `nombre`, `distancia_salida_meta_m`, `dentro_geocerca_pct`, `mejor_pasada_s`, `cruces` (línea, t, sentido, cuenta) y `pasadas` (mismo formato que los trabajos, con tipo `PASADA`);
- `fases`: `base` (`VELOCIDAD` o `LINEAS`), `calentamiento`, `trabajo` y `vuelta_a_la_calma`, cada una con duración, distancia y segundos parado, al paso, al trote y al galope (`null` si no hay trabajos);
- `series`: `repeticiones`, `rapidas`, `caida_v_max_pct`, `caida_zancada_pct`, `recuperacion_media_s`, `calentamiento_corto`;
- `eventos`;
- `avisos`.

El resumen `avo-training-session` añade `trabajo_pista` (con `sesion`) y la carga de la historia añade `vedba`, `aguda_vedba`, `cronica_semanal_vedba` y `acwr_vedba`.
