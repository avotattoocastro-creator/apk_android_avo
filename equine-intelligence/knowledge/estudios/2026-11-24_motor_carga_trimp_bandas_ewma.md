# Motor nocturno 24/11/2026 — carga de entrenamiento CG1–CG3 y FC máxima FM1

**Base:** KB-1 1.30.0 · **Motor:** 2.0.0-dev34 (cardio 1.1.0, training 1.2.0) · **Rama:** `claude/motor-noche-2026-11-24`
**Validación:** pruebas locales y CI; **NO VERIFICADO** con caballos reales. Solo descriptivo: nunca un riesgo ni una
predicción de lesiones, nunca sube el estado del caballo (nivel INFO).

## 1. Por qué esta pieza
Las reglas CG1–CG3 quedaron PROPUESTA el 23/11 con la evidencia ya leída (estudio
`2026-11-23_noche_auditoria_estadistica_trimp_acwr_edad_sexo.md`). Con los datos que ya graban los PROTOTIPOS (GNSS RTK
de la espalda y ECG de la cincha 0.5.0) se puede dar al entrenador una carga interna y externa por sesión y su
evolución semanal, que hoy solo existe como heurística por aires. La playa por franjas (PL2–PL6) necesita campos de
la ficha que aún no se rellenan (lluvia 24–48 h, humedad TDR, penetrómetro), así que se deja para otra noche.

## 2. Qué se implementó

### CG1 · carga interna por sesión (cardio 1.1.0)
- ΔFC = (FC − FC_reposo)/(FC_máx − FC_reposo), recortado a [0, 1] [I].
- TRIMP = Σ Δt(min) · ΔFC · b · e^(c·ΔFC), con b = 0,64 y c = 1,92: plantilla de Banister para varones (Morton,
  Fitz-Clarke y Banister 1990 [E-r], leída en una secundaria); **coeficientes sin validar en caballos [NV]**. Munsters
  2020 ajustó b y c por caballo en completo con prueba estándar y lactato [I-raza]; aquí no es posible.
- Además: versión sin ponderar (Σ Δt·ΔFC), segundos por encima de 180 y 200 lpm (cortes de los trotones de Flyrin y
  Hägglund 2021 [E, otra raza]), segundos por encima de la FC máxima, cobertura de FC válida e **histograma de FC**
  de 5 lpm.
- FC de reposo por defecto 33 lpm (Ohmura y Jones 2017: 32,9 ± 3,5 lpm en caballos de carreras de 3–7 años [E-r]);
  FC máxima por defecto 213 lpm (FM1: 210–215 lpm [I]; Janczarek 2016 en árabes ≥ 211–212 lpm [E]). Las dos salen
  marcadas `POR_DEFECTO` hasta que la app pase las del caballo.
- Ejemplo a mano: 10 min a 123 lpm → ΔFC 0,5 → 10 · 0,5 · 0,64 · e^0,96 = 8,357 UA.

### FM1 · FC máxima propia (historia)
Máximo de la FC pico de ≥ 3 trabajos rápidos con ECG BUENA o UTILIZABLE [I]. Todas las sesiones de la historia se
recalculan desde su histograma con esa FC de referencia, para que los TRIMP sean comparables entre sí.

### CG2 · carga externa por bandas (análisis y historia)
Bandas de Morrice-West 2020 [E] (texto completo, manuscrito aceptado): < 10, 10–13,3, 13,3–14,4, 14,4–15,5,
15,5–16,8 y ≥ 16,8 m/s (los cortes publicados 13,3–14,3 / 14,4–15,4 / 15,5–16,7 se cierran en el siguiente valor);
«trabajo rápido» ≥ 13,3 m/s, la misma definición que Wong 2023 [E]. En árabes se escalan por v_carrera/16,7 [I-raza]
(con 14,5 m/s: 8,68 / 11,55 / 12,50 / 13,46 / 14,59 m/s). Totales de 7 y 30 días.

### CG3 · agudo/crónico, monotonía y strain (historia)
- EWMA_d = λ·carga_d + (1 − λ)·EWMA_(d−1), λ = 2/(N + 1) con N = 7 (0,25) y N = 28 (2/29 ≈ 0,069) (Williams 2017
  [E-r], vía Hamlin 2019). La inicialización (EWMA = 0 el día antes del primero) es nuestra [I]: no se pudo leer
  Williams 2017 en texto completo esta noche.
- Por separado para los metros rápidos y para el TRIMP. Cociente aguda/crónica solo con ≥ 28 días de historia y ≤ 20 %
  de sesiones sin dato en la ventana crónica [I]; si no, `null` con el motivo.
- Monotonía de Foster 1998 [E-r] = media diaria de 7 días / DE (días sin sesión = 0; DE poblacional [NV]);
  strain = carga de 7 días × monotonía.
- Impellizzeri 2020 [E-r]: el cociente no tiene apoyo para gestionar cargas ni lesiones; por eso aguda y crónica se
  muestran siempre por separado y el bloque no cambia el estado. Munsters 2020 [I-raza]: en completo solo el cociente
  de la distancia a alta velocidad de la semana previa se asoció a lesión (OR ≈ 3,95), el interno no.
- Ejemplo a mano: 400 m rápidos cada 2 días durante 40 días → aguda 171,4 m/día, crónica 181,8 m/día, cociente 0,943.

## 3. Verificación de evidencia de esta noche
Se intentó cerrar dos [NV] (definición exacta de la DE de Foster y la inicialización del EWMA de Williams 2017). PMC
devolvió un reCAPTCHA y SciSpace quedó denegado por los permisos de la sesión; no se buscó ningún rodeo. Los dos
puntos siguen [NV]/[I] y son parámetros configurables.

## 4. Fuentes

| ID | Cita | DOI / URL | Raza | Acceso | Qué sostiene | Etiqueta |
|---|---|---|---|---|---|---|
| MORRICE_WEST_EVJ_13156_AAM | Morrice-West AV et al. 2020, EVJ | 10.1111/evj.13156 | PSI | texto completo (AAM) | bandas de velocidad, ≥ 13,3 m/s | E |
| WONG_2023 | Wong ASM et al. 2023, EVJ 55:194 | 10.1111/evj.13581 | PSI | texto completo | «fast work» ≥ 13,3 m/s | E |
| MUNSTERS_2020_ACWR | Munsters CCBM et al. 2020, Prev Vet Med 179:105010 | 10.1016/j.prevetmed.2020.105010 | completo | texto completo | iTRIMP y ACWR equinos | I-raza |
| MORTON_BANISTER_1990_TRIMP | Morton RH, Fitz-Clarke JR, Banister EW 1990, J Appl Physiol 69:1171 | hull-repository.worktribe.com/OutputFile/443111 | humanos | resumen (secundaria) | forma del TRIMP, 0,64 y 1,92 | E-r / NV |
| OHMURA_JONES_2017_FC_REPOSO | Ohmura H, Jones JH 2017, J Equine Sci 28:99 | 10.1294/jes.28.99 | PSI | resumen | FC de reposo 32,9 lpm | E-r |
| JANCZAREK_2016_UMCS_FC | Janczarek I et al. 2016, Annales UMCS EE 34(2) | czasopisma.up.lublin.pl/jasbb/article/download/946/696/2409 | árabe | texto completo | FCmax ≥ 211–212 lpm | E |
| FLYRIN_HAGGLUND_2021_SLU | Flyrin M, Hägglund A 2021, SLU | stud.epsilon.slu.se/17336/ | trotón | texto completo | tiempo > 180 y > 200 lpm | E (otra raza) |
| WILLIAMS_2017_EWMA | Williams S et al. 2017, BJSM 51:209 (vía Hamlin 2019) | 10.3389/fphys.2019.00034 | humanos | resumen (secundaria) | EWMA, λ = 2/(N + 1) | E-r |
| FOSTER_1998_MONOTONIA | Foster C 1998, MSSE 30:1164 | sponet.de/sponet/Record/4001707 | humanos | resumen | monotonía y strain | E-r |
| IMPELLIZZERI_2020_ACWR | Impellizzeri FM et al. 2020, IJSPP 15:907 | 10.1123/ijspp.2019-0864 | humanos | resumen | el cociente no sirve para lesiones | E-r |

## 5. Qué falta calibrar (PROTOTIPO, `docs/PROTOCOLO_PRUEBAS_CAMPO_PROTOTIPO.md` §6 bis)
- FC de reposo propia (5 min parado con la cincha 0.5.0, 3 días); FC máxima propia con ≥ 3 trabajos rápidos.
- Cobertura mínima del 80 % con sesiones reales (electrodos, artefactos a galope).
- ≥ 8 semanas seguidas con GNSS y ECG para ver la dispersión del cociente propio.
- b y c en equinos (prueba estándar con lactato): fuera del alcance del PROTOTIPO.
- Pendiente de las apps: iPad (tarjeta en Training Analytics), Android y Windows.
