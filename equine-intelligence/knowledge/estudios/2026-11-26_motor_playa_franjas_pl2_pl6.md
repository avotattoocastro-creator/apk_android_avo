# Motor nocturno 2026-11-26 — playa por franjas: línea base PL2–PL6 y A9 por franja

**KB-1 1.32.0 · motor 2.0.0-dev39 · TRAINING 1.5.0 · cambio de lógica (código nuevo con pruebas).**

## Decisiones tomadas sin supervisión

1. **Rama.** No había ningún PR `claude/kb-*` ni `claude/motor-*` abierto (los de las noches del 24 y el 25 ya estaban
   integrados en `develop`). La rama sale de `develop/avo-performance-horse` (motor 2.0.0-dev38).
2. **Qué se implementa.** El punto a) del orden de prioridad: **playa por franjas y marea, PL2–PL6**. La marea y la
   franja automática (AVO BEACH 1.0.0, dev36) y PL1 en A7/A8 (dev28) ya estaban hechos. Faltaban el registro del
   suelo, los comparables y la línea base por franja. Es lo que más ayuda al entrenador en Laredo con lo que ya graban
   los PROTOTIPOS (espalda RTK, cincha IMU y ECG 0.5.0, ficha de campo del iPad). Además, sin esto A9 (V200) mezclaba la
   orilla firme con la arena profunda.
3. **Evidencia.** No se ha hecho ninguna búsqueda nueva. Las cifras que se usan ya estaban en la KB, leídas en texto
   completo o en resumen y auditadas el 19, 20 y 21/11. Los umbrales sin fuente directa son parámetros [I], salen como
   INFO «sin calibrar» y no cambian el estado.
4. **Alcance en las apps.** Se añade la tarjeta en el iPad (historia del caballo) con sus pruebas. Faltan Android y
   Windows.

## Qué se implementó

Código en `src/training/beach_baseline.cpp`; la salida va en el bloque `estado.playa` de `avo-training-analysis`.

- **PL2. Registro del suelo.**
  - La ficha de campo acepta `pista.humedad_suelo_pct` (0–60), `lluvia_48h_mm` (0–500) y `nota_suelo` (DURO, NORMAL,
    BLANDO o PROFUNDO).
  - Clase de humedad: SECA si es ≤ 13 %, MEDIA si está entre 13 y 19 % y HUMEDA si pasa del 19 %.
  - Con ≥ 5 mm de lluvia en 48 h se pone la marca `PL2_LLUVIA_RECIENTE`.
- **PL3. Zancada con la velocidad como covariable y la franja como efecto fijo.**
  - Se usan los pares (v_ref, l, f) de las dos velocidades de referencia de cada sesión.
  - Pendiente común dentro de franja: `b = Σ_f Σ (v − v̄_f)(l − l̄_f) / Σ_f Σ (v − v̄_f)²`.
  - Zancada ajustada: `l*_f = l̄_f + b·(v_c − v̄_f)`, con `v_c` = mediana de todas las v.
  - Efecto de la franja: `l*_f − l*_ref`. La referencia es ORILLA_FIRME si es utilizable y, si no, la franja
    utilizable con más sesiones.
  - Lo mismo se hace con la frecuencia.
  - La pendiente propia solo se usa con ≥ 8 pares, una DE de la velocidad dentro de franja ≥ 0,5 m/s y un valor
    plausible (0–1 m por m/s). Si no se cumple, se usa la de Pfau 2024: +0,359 m y +0,018 Hz por m/s.
- **PL4. Impactos relativos a la franja.**
  - Se cuentan los impactos atípicos de la cincha por km de galope de trabajo.
  - La última sesión se divide por la mediana de su franja, solo si la franja tiene ≥ 4 sesiones.
- **PL5. Línea base por franja.**
  - Por franja: mediana y MAD de la zancada y la frecuencia, de los últimos 600 m, de la V200, de los impactos/km y de
    la humedad.
  - La franja es utilizable con ≥ 4 sesiones.
  - **A9 (V200) compara ahora solo con sesiones de la misma superficie y franja**, igual que A7/A8 desde dev28.
- **PL6. Marcas INFO de los últimos 14 días.**
  - `PL6_RAPIDO_ORILLA_COMPACTA`: rápido en orilla firme con una humedad ≤ 13 % o con la nota DURO.
  - `PL6_CAMBIO_FRANJA_EN_GALOPE`: la franja automática dominante cubre menos del 70 % del trabajo. Usa
    `entorno.franjas.trabajo_pct` de AVO BEACH, que ahora se guarda en el resumen como `pista.franja_trabajo_pct`.
  - `PL6_CAMBIO_FRANJA`: rápido en una franja distinta de la del rápido anterior, si fue hace ≤ 7 días.
- Además, `rapidos_orilla_firme_7d`.

### Ejemplo numérico (prueba `entreno.beach_baseline_pl3_pl6`, calculado a mano)

| Franja | Pares (v m/s; l m; f Hz) | v̄ | l̄ | l* a 14,5 m/s | Efecto |
|---|---|---|---|---|---|
| Orilla firme (5 ses.) | (14; 6,60; 2,12), (16; 7,30; 2,19) | 15 | 6,95 | 6,95 + 0,35·(−0,5) = 6,775 | 0 (referencia) |
| Seca profunda (4 ses.) | (13; 5,90; 2,15), (15; 6,60; 2,22) | 14 | 6,25 | 6,25 + 0,35·(0,5) = 6,425 | −0,35 m; +0,065 Hz |

- b = 0,70 m / 2 m/s = 0,35 m por m/s. Es propia: 18 pares y DE de v = 1 m/s.
- Con la pendiente de Pfau (0,359) salen 6,7705 y 6,4295 m.
- Impactos de la orilla: 1; 1,5; 1,5; 2 y 3 /km, con mediana 1,5 y MAD 0,5. La última sesión (3/km) es × 2,0 de su
  franja.

Salida (extracto):

```json
"playa": {"disponible": true, "nivel": "INFO", "validado": false, "sesiones_playa": 9, "franja_referencia": "ORILLA_FIRME",
  "pl3": {"pendiente_zancada_m_por_m_s": 0.35, "origen_pendiente": "PROPIA", "pares": 18, "velocidad_comun_m_s": 14.5},
  "franjas": [{"franja": "SECA_PROFUNDA", "sesiones": 4, "linea_base_utilizable": true, "zancada_ajustada_m": 6.425,
               "efecto_zancada_m": -0.35, "efecto_frecuencia_hz": 0.065, "...": "..."}],
  "ultima_sesion": {"franja": "ORILLA_FIRME", "clase_humedad": "SECA", "impactos_por_km": 3, "impacto_relativo_franja": 2},
  "marcas": [{"regla": "PL6_RAPIDO_ORILLA_COMPACTA", "nivel": "INFO", "texto": "trabajo rápido en orilla muy compactada (humedad 11 %, …)"}]}
```

## Parámetros y etiquetas

| Opción `playa.*` | Defecto | Etiqueta | Base |
|---|---|---|---|
| `pendiente_zancada_previa_m_por_m_s` | 0,359 | [E] | Pfau 2024 (PSI outriders en tierra, texto completo) |
| `pendiente_frecuencia_previa_hz_por_m_s` | 0,018 | [E] | Pfau 2024 |
| `min_pares_pendiente_propia`, `dispersion_v_min_m_s` | 8; 0,5 m/s | [I] | diseño |
| `min_sesiones_franja` | 4 | [I] | PL5: de 4 a 6 sesiones por franja, sin dato publicado [NV] |
| `humedad_seca_max_pct`, `humedad_humeda_min_pct` | 13; 19 % | [E] en tierra / [I] en playa | Pfau 2024; Crevier-Denoix 2011 (19 % en orilla firme y 13,5 % en húmeda profunda, trotón) [E-r] |
| `humedad_compacta_max_pct` | 13 % | [I] | White Paper 2012: la dureza sube con la compactación [E], sin corte |
| `franja_dominante_min_pct` | 70 % | [I] | White Paper 2012: el cambio de superficie a máxima intensidad está documentado [E] |
| `dias_cambio_franja` | 7 | [I] | diseño |
| `lluvia_reciente_mm` | 5 mm | [I] | White Paper 2012: la humedad es la variable más importante [E], sin corte |
| `dias_ventana`, `dias_marcas` | 180; 14 | [I] | diseño |

## Fuentes

| Fuente | Qué se usa | Etiqueta | DOI / URL |
|---|---|---|---|
| Pfau T, Bruce OL, Sawatsky A, Leguillette R, Edwards WB 2024, *Sensors* 24:2441 | Pendientes de +0,359 m y +0,018 Hz por m/s; diferencia de zancada de hasta 18,6 cm según el suelo a igual velocidad; cortes de humedad en tierra | [E] (12 PSI castrados de outriders, no de carreras en activo: transferencia [I]) | doi 10.3390/s24082441 |
| Crevier-Denoix N et al. 2011, *EVJ* Suppl 38:544 | Humedad del 19 % en la orilla firme frente al 13,5 % en la húmeda profunda (trotón, n = 4) | [E-r] [I-raza] | doi 10.1111/j.2042-3306.2010.00202.x |
| Chateau H et al. 2011, *EVJ* Suppl 38:488 | Deceleración del casco −59 % en húmeda profunda frente a firme; justifica PL4 por franja | [E-r] [I-raza] | DOI sin confirmar [NV] |
| Racing Surfaces White Paper, Grayson-Jockey Club 2012 | La humedad es la variable más importante; problemas al cambiar de superficie a máxima intensidad; instrumentos (TDR, penetrómetro) | [E] oficial | https://grayson-jockeyclub.org/resources/White_Paper_04272012.pdf |

## Qué falta calibrar (protocolo de campo, §4)

- ≥ 4 sesiones por caballo en cada franja de Laredo, con espalda RTK y cincha. Las velocidades de referencia tienen que
  variar entre sesiones para la pendiente propia.
- Humedad con sonda TDR (3–5 lecturas, mismo operador) y lluvia de 48 h en la ficha. Así se ajustan los cortes de 13 y
  19 %, el de orilla compacta y el 70 % de franja dominante.
- TE propio por franja (pares de referencia de 1.000 m en la misma franja), para que A7/A8/A9 tengan umbral propio en la
  playa.
- Mejoras del cálculo:
  - PL3 con la velocidad de cada zancada (hoy usa las 2 velocidades de referencia).
  - PL4 con picos de impacto en g (hoy usa el recuento de impactos atípicos).
  - El penetrómetro (PL2).
  - Un registro propio de incidencias por franja (PL6).

## Validación

- **Probado en local:** 4 pruebas nuevas en `test_training.cpp` (PL3–PL6 con valores a mano, pendiente previa y
  opciones, caso sin datos y ficha PL2 con ida y vuelta por JSON, A9 por franja). Todo pasa con ASan/UBSan.
- **NO VERIFICADO** con caballos reales. Las marcas son informativas, no son un diagnóstico ni una predicción de
  lesiones, y no cambian el estado del caballo.
