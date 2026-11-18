# 14 · Base científica de la cuadra (KB-1) 1.0.0

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
Nf   = 10^((σ0 − σ) / 14,1)               σ0 = 134,2 MPa (Martig 2013) [E]
%SBFL = 100 · Σ 1/Nf                      regla de Miner, sin reparación [E]
zancadas por época GNSS = f(v)·dt,  f(v) = 1,7052 + 0,0305·v + 0,0004·v² Hz [E, Anwar 2026]
```
- Rango validado de 12,57 a 21 m/s (filtro de Morrice-West). Entre 4 y 12,57 m/s el daño se suma aparte en
  `pct_extrapolado_lento`, porque el modelo sobrestima el trabajo lento (calculado 1,2–3,3 % por canter frente a 0,41 %
  de mediana en Hong Kong).
- Huecos GNSS de más de 5 s no cuentan.
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
| KB_FATIGA_OSEA_7D | fatiga ósea 7 d > 1,5 × mediana semanal propia (≥ 4 semanas) | AVISO | Morrice-West 2025, Hong Kong [E]; umbral [I] |
| KB_SIN_RAPIDO_30D | canter sin trabajo rápido en 30 d | AVISO (INFO) | Morrice-West 2025 [E]; aplicación [I] |

Sesión rápida = al menos 100 m de galope rápido. Las reglas VIGILAR suben el estado a VIGILAR y añaden el motivo
«base científica (regla, acción): …». Nunca diagnostican.

Opciones de Training Analytics (`base_cientifica`: `true`/`false` u objeto): `activa`, `canter_30d_aviso_km`,
`canter_30d_limite_km`, `galope_30d_limite_km`, `rampa_ratio`, `rampa_min_m`, `galope_sesion_min_m`,
`fatiga_osea_ratio`, `dias_descanso_vuelta`, `dias_ventana_vuelta`, `dias_descanso_tendon`, `semanas_min_fatiga_osea`.
Opciones del análisis de sesión: `v_carrera_m_s` (8–20), `sigma_max_mpa` (30–120), `sigma0_mpa` (100–180).

Los análisis anteriores sin el bloque cuentan como «sesiones sin datos» y no se juzgan.

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
