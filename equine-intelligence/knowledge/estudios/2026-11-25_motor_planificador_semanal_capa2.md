# Motor nocturno 25/11/2026 — planificador semanal, capa 2 (semana siguiente)

**Base:** KB-1 1.31.0 · **Motor:** 2.0.0-dev35 (training 1.3.0) · **Rama:** `claude/motor-noche-2026-11-25`
**Validación:** pruebas locales (ASan/UBSan y Release) y CI; **NO VERIFICADO** con caballos reales. Propuesta orientativa
**sin calibrar**: nunca sube el estado del caballo, no predice lesiones y el entrenador decide.

## 1. Por qué esta pieza
- La playa por franjas (PL2–PL6, prioridad a) sigue sin datos: la ficha de campo aún no lleva lluvia de 24–48 h, humedad
  TDR ni penetrómetro, y los comparables por franja (PL1) ya están hechos. La carga (b) quedó hecha el 24/11 (CG1–CG3).
- El planificador (c) era la pieza grande pendiente con la evidencia **ya leída** (estudios extra 3 del 19/11, 20/11
  11:10, 19:08 y 20:08, auditoría del 22/11) y solo necesita lo que ya graban los PROTOTIPOS: metros rápidos y de canter
  de la espalda (GNSS RTK), fechas de las sesiones, carreras previstas y el año de nacimiento de la Cuadra del iPad.
  Desbloquea una tarjeta nueva en la historia del caballo (hecha en el iPad esta noche).

## 2. Qué se implementó (`src/training/planner.cpp`, `estado.planificador.semana_siguiente`)
Horizonte: los 7 días siguientes a la fecha de referencia. «Día rápido» = día con ≥ 100 m a > 14 m/s (PSI; escalado en
árabes), la misma definición que A1–A6. Bloque = sesiones desde el último hueco > 14 d sin sesiones [I].

| Regla | Implementación | Etiqueta |
|---|---|---|
| P1 | objetivo 2 rápidos/semana en maduros y en potros de 2 años | práctica 2,0 y 1,7 [E]; objetivo [I] |
| P2 | ≥ 3 días entre rápidos (≥ 2 días lentos en medio), un día LIBRE por semana; si no caben, pauta | día libre [E]; separación [I] |
| RT1–RT3 | colocación con ≥ 72 h; día siguiente SUAVE (LIBRE tras carrera); sin rápido 3 d antes y 5 d después de una carrera | [E-r] / [I] |
| P4 | > 60 d sin rápido: 0 rápidos hasta 28 d de trabajo lento en el bloque, luego 1 de ≤ 75 % de la mediana anterior | 4,0 semanas [E]; forma [I] |
| P7 | 21 d tras el primer rápido de la vuelta: 1 rápido por semana (≥ 7 d) con el mismo tope | [E-r] / [I] |
| P5 | media diaria de metros rápidos de 60 d > P75 propio (≥ 180 d de historia) y también en los días 60–31 | [E-r] / [I] |
| P6 | ≥ 183 d sin un hueco ≥ 40 d sin sesiones: pauta de descanso (en potros, «cortos y frecuentes») | [E] / [I] |
| DM1 | potros de 2 años antes de 12 semanas de bloque: tope de 400 m por rápido | [E] / [I] |
| DM2 | canter o rápido de 7/14/30 d > 1,5 × media acumulada del bloque (≥ 28 d antes de la ventana) | [I] |
| DM3 | canter del último día rápido > mediana de los días lentos de 30 d | [E-r] / [I] |
| DM4 | salto a ≥ 700 m sin haber pasado de 700 m antes de 12 semanas | [E] / [I] |
| LIMITAR | con A1/A2/A3/A5 en LIMITAR, un solo rápido | reglas ya implementadas |

Fórmulas:
- P5: m̄₆₀(t) = (1/60)·Σ_{d=t−59..t} rápido_m(d) (días sin sesión = 0); P75 = percentil 75 (interpolación lineal) de
  m̄₆₀ en todos los días de la historia anteriores a t con ventana completa (≥ 30 valores). Pauta si m̄₆₀(t) > P75 y
  (1/30)·Σ_{d=t−59..t−30} rápido_m(d) > P75.
- DM2: cociente = (Σ ventana / días) / (Σ bloque antes de la ventana / días del bloque antes de la ventana).
- Edad de carreras = año de referencia − año de nacimiento (convenio del 1 de enero del hemisferio norte).

Ejemplos numéricos (pruebas `tests/test_training.cpp`):
- Maduro con 600 m cada 4 días y referencia el día de un rápido (día 40): rápidos los días 43 y 46 →
  `SUAVE, LENTO, RAPIDO, SUAVE, LENTO, RAPIDO, LIBRE`; `rapido_ref_m` = 600.
- Vuelta: rápidos de 600 m hasta el día 28, parado 31–100, lento 101–110 → `REINCORPORACION_LENTA`, 10 de 28 días
  lentos, 0 rápidos, tope 0,75 × 600 = 450 m; con 30 días lentos, 1 rápido de 450 m el primer día; tras el rápido del
  día 131, el siguiente el 138 (7 d).
- P5: 200 m cada 4 días los 100 primeros días y después 200 + 6·(d − 100) m: la ventana 140–199 tiene 15 rápidos que
  suman 15·200 + 6·(40 + 44 + … + 96) = 3 000 + 6 120 = 9 120 m → 152 m/día, por encima de su P75. Con el mismo volumen
  concentrado en el último mes, no hay pauta.
- DM2: canter 1 000 m/día y 2 500 m/día la última semana → 7 d: ×2,5; 14 d: (7·1 000 + 7·2 500)/14 = 1 750 → ×1,75.

## 3. Evidencia de esta noche
No hizo falta leer fuentes nuevas: todas las cifras salen de fuentes ya auditadas en la KB. Una búsqueda de control
sobre días entre trabajos rápidos no dio ningún estudio nuevo con un intervalo publicado (sigue el hueco del estudio
extra 3: Johnston 2020 lo calcula pero no lo publica; Hitchens 2018 da OR 1,03 por día más, sin ajustar). Por eso la
separación sigue siendo [I] y configurable.

## 4. Fuentes

| ID | Cita | DOI / URL | Raza | Acceso | Qué sostiene | Etiqueta |
|---|---|---|---|---|---|---|
| MORRICE_WEST_2020_PRACTICAS | Morrice-West AV et al. 2020, EVJ (prácticas de entrenadores) | 10.1111/evj.13156 | PSI | texto completo (AAM) | 2,0 / 1,7 rápidos por semana; 1,9–2,1 descansos de 6,3–6,6 semanas; 4,0 semanas de lento antes del primer trial | E |
| WONG_2023_DESCANSOS | Wong ASM et al. 2023, Front Vet Sci 10:1260554 | 10.3389/fvets.2023.1260554 | PSI | texto completo | descansos largos y frecuentes (maduros), cortos y frecuentes (2 años) | E |
| CARRIER_1998 | Carrier TK et al. 1998, JAVMA 212:1582 (PMID 9604029) | PMID 9604029 (ficha en MadBarn) | PSI | agregador | riesgo en los 10–21 d de rápido tras ≥ 2 meses sin él (húmero) | E-r |
| ESTBERG_1998 | Estberg L et al. 1998, Prev Vet Med 33:159 | 10.1016/S0167-5877(97)00047-0 | PSI | agregador | 60 d > P75 de distancia a alta velocidad | E-r |
| HITCHENS_2018_CALIFORNIA | Hitchens PL, Hill AE, Stover SM 2018, Front Vet Sci 5:217 | 10.3389/fvets.2018.00217 | PSI | texto completo | último mes protector, meses 3–4 de riesgo; OR 1,03 por día entre trabajos | E |
| OLIVEIRA_2006_DMD_BR | Oliveira PR et al. 2006, Braz J Vet Res Anim Sci 43:233 | 10.11606/issn.1678-4456.bjvras.2006.26504 | PSI 2 años | texto completo | escalones 200 → 700 m, 10/19 casos en la fase de 700 m, propuesta 200–400 m | E |
| BOSTON_NUNAMAKER_2000 | Boston RC, Nunamaker DM 2000, AJVR 61:602 | 10.2460/ajvr.2000.61.602 | PSI 2 años | resumen | breeze protector, galope a ~11 m/s de riesgo | E-r |
| VERHEYEN_2005_DMD | Verheyen KLP et al. 2005, EVJ 37:442 | 10.2746/042516405774480085 | PSI | agregador | bloques cortos de canter y rápido | E-ag |
| CRAWFORD_2021_DMD | Crawford KL et al. 2021, Front Vet Sci 8:698298 | 10.3389/fvets.2021.698298 | PSI | texto completo | acumulación gradual de galope protectora | E |

Nota: Carrier 1998 y Estberg 1998 constan en la KB con acceso AGREGADOR; se mantiene su etiqueta [E-r] de la KB y no
sostienen ningún umbral duro (solo la forma de P4/P7 y P5, ambas [I] y configurables). Auditarlas en texto completo un
domingo.

## 5. Qué falta calibrar (PROTOTIPO, `docs/PROTOCOLO_PRUEBAS_CAMPO_PROTOTIPO.md` §6 ter)
- Todas las sesiones grabadas con la espalda (también las lentas): los días sin sesión cuentan como libres o descanso.
- Año de nacimiento en la Cuadra; sin él no se aplican DM1–DM4.
- ≥ 8 semanas por caballo comparando la propuesta con lo que hizo el entrenador para ajustar separaciones, días
  alrededor de la carrera y topes; vueltas de descansos ≥ 60 d con la distancia del primer rápido; ≥ 180 d continuos para P5.
- Árabes de llano: sin programa semanal publicado [I-raza].
- Apps: iPad hecho (tarjeta «Semana siguiente» en la historia); Android y Windows pendientes.
