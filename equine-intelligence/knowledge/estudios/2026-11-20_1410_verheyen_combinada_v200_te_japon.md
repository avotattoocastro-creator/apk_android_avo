# Estudio horario 2026-11-20 14:10 UTC — Regla combinada de Verheyen (A1+A2) y TE/cambio mensual de la V200 (fuentes japonesas y árabes)

**KB-1 1.15.0 → 1.16.0 · motor 2.0.0-dev17 → 2.0.0-dev18 · sin cambios de lógica, reglas ni umbrales en el código.**

## Decisiones tomadas sin supervisión

1. Rama encadenada desde `claude/kb-estudio-2026-11-20-1312` (PR #102, el `claude/kb-*` abierto más reciente; también
   siguen abiertos #101 y #99). No se repiten sus temas (temperatura, peso, playa, parcial final, layup, sensores,
   tendón, V200/A9 umbrales, ECG/A11, dt del modelo B, velocidad final relativa).
2. Temas elegidos (bloquean código):
   - **T1. Forma de la regla de Verheyen 2006** (pendientes «Regla combinada A1+A2» y «A1/A2 conjunto», cola 0 y 29).
     Ruta nueva: manuscritos aceptados y fuentes secundarias en texto completo, en vez del artículo (de pago).
   - **T2. TE por defecto y cambio mensual plausible de la V200** (pendiente V200/VHRmax; cola 13, 33 y 34):
     fuentes de la JRA en J-STAGE y cualquier V200 de árabes.
3. Dos subagentes en paralelo (~7 min cada uno). Se respetaron los bloqueos (J-STAGE robots, reCAPTCHA de PMC/PubMed,
   permisos no concedidos de Unpaywall, Europe PMC y Semantic Scholar); no se usaron espejos ni cachés.
4. **Motor:** no se implementa nada. La regla combinada se apoya en el resumen [E-r] y en fuentes secundarias; la
   magnitud (OR) sigue [NV]. Solo se suben versiones. Se deja **propuesta** la reordenación A1/A2 para cuando haya
   OR o decisión del usuario.

## T1. Regla combinada de Verheyen 2006 (Bone 39:1322, doi 10.1016/j.bone.2006.05.025)

| Fuente | Acceso | Qué aporta (parafraseado) | Etiqueta |
|---|---|---|---|
| Verheyen, Price, Lanyon & Wood 2006, resumen (agregador madbarn.com y ficha RVC Worktribe 1434504) | Resumen | 1178 PSI seguidos hasta 2 años, 148 fracturas. El riesgo sube sobre todo por encima de 44 km de canter en 30 d (≈ 7700 ciclos a canter y ≈ 880 a galope). En añojos (335 caballos, 56 fracturas) el canter acumulado aumenta el riesgo y el galope rápido acumulado lo **reduce** | [E-r] |
| Morrice-West et al., manuscrito aceptado (EVJ, doi 10.1111/evj.13156), minerva-access (Melbourne) | Texto completo del secundario | Describe el hallazgo de Verheyen como **interacción** canter × galope: riesgo con > 44 000 m/mes de canter **junto con** > 6000 m/mes de galope; canter ≤ 14 m/s y galope > 14 m/s; medias del Reino Unido 26,8 km/mes de canter y 2,8 km/mes de galope (rangos 0–82,4 y 0–17,7 km). Advierte que otras definiciones de canter (< 10 m/s) no son comparables | [E] del secundario / [I-secundaria] para Verheyen |
| Anwar, Pan, Morrice-West, Whitton, Hitchens et al., preprint arXiv 2603.22680 | Texto completo | Mismo resumen: > 44 km de canter (≤ 14 m/s) **en combinación con** 6 km de galope (≥ 14 m/s) por mes; sin OR | [I-secundaria] |
| Rosanowski, Chang, Stirk & Verheyen 2018 (EVJ, doi 10.1111/evj.12968), manuscrito aceptado en RVC Worktribe | Texto completo del secundario | Con Verheyen como coautora, lo resume como interacción entre ciclos de carga a canter y a galope; sin cifras | [I-secundaria] |
| Verheyen, Newton, Price & Wood 2006, Prev Vet Med 74:21 (doi 10.1016/j.prevetmed.2006.01.004; pelvis y tibia) | Resumen | Casos y controles con ventanas de 30 y 60 d. A 30 d el riesgo sube con el canter hasta un pico hacia ≈ 50 km y luego baja; a 60 d sin asociación | [E-r] |

**Conclusiones T1**

- Tres fuentes independientes (dos del grupo de Melbourne y una con la propia autora) coinciden: el hallazgo es una
  **combinación/interacción**, no dos umbrales separados [I-secundaria, consistente con el resumen E-r].
- El galope rápido acumulado es **protector** en añojos [E-r]: A2 aislada (galope > 6 km en 30 d como LIMITAR) no
  tiene base como alarma independiente [I].
- A1 aislada (canter > 44 km/30 d) tiene apoyo propio: el resumen del Bone lo destaca y el estudio de pelvis/tibia
  sitúa el pico hacia 50 km en 30 d [E-r].
- El corte de velocidad es **14 m/s** (canter ≤ 14, galope > 14) según el secundario [E del secundario]. Hay que
  comprobar que A1/A2 del motor usan ese corte y no otro (13,4 m/s aparece en Verheyen 2005 según el estudio de la
  noche del 18/11).
- Siguen [NV]: OR por categoría e IC; si 44/6 km son cortes de categoría o valores ilustrativos de la interacción; si
  la ventana es exactamente 30 d (el resumen dice 30 d; los secundarios, «mes»).

**Propuesta VC1–VC4 [I] (no implementada):**
- **VC1.** Regla principal LIMITAR: canter (≤ 14 m/s) > 44 km **y** galope (> 14 m/s) > 6 km en 30 d móviles.
- **VC2.** A1 aislada: se queda en AVISO a 40 km y deja de ser LIMITAR por sí sola a 44 km salvo con VC1.
- **VC3.** A2 aislada: baja a INFO (el galope acumulado es protector en añojos).
- **VC4.** Texto de la app: «patrón asociado a más riesgo en una cohorte del Reino Unido», nunca predicción de lesión.
- Implementar cuando el usuario lo apruebe o se lean las OR; cambia la severidad de alertas existentes.

## T2. TE por defecto y cambio mensual de la V200

| Fuente | Acceso | Cifras (parafraseadas) | Etiqueta |
|---|---|---|---|
| Kobayashi, Kuribara & Amada 2000, EVJ Suppl 30:159 (doi 10.1111/j.2042-3306.1999.tb05208.x), Japón, PSI de 2 años en campo | Resumen | V200 media de 623 ± 55 a 691 ± 64 m/min tras 5 meses de entrenamiento (P < 0,05); n ambiguo en el resumen | [E-r] |
| Vermeulen & Evans 2006, EVJ Suppl 36:113 (doi 10.1111/j.2042-3306.2006.tb05525.x), Australia, PSI con GPS | Resumen | Fiabilidad (n = 12, 3–5 años): diferencias medias ≤ 2 % entre pruebas para VHRmax, V200 y FCmax. Entrenamiento (n = 12, 2 años): V200 y VHRmax suben (P < 0,01), FCmax no cambia. Sin CV ni TE numérico | [E-r] |
| Piccione et al. 2004, Vet Med Czech 49:291 (PDF oficial de la revista), Italia | PDF oficial leído con texto algo dañado | **Árabes** de 6–8 años (n = 10): V200 610 ± 26 m/min; angloárabes de 2–4 años (n = 10): 583 ± 31 m/min (P < 0,01); VLa4 551 ± 40 y 532 ± 39 m/min. Disciplina exacta (carreras de llano o no) por confirmar | [E] (cifras) / [NV] (disciplina) |
| Mukai et al. 2007, J Equine Sci 18:153 (doi 10.1294/jes.18.153), JRA, carrera de 1200 m | Resumen | n = 23; FC pico 213,6 ± 1,7 lpm; 12,4 ± 1,8 s hasta el 95 % de la FC pico; lactato 22,5 ± 0,6 mmol/L a 15,9 m/s | [E-r] |
| Hada et al. 2006, EVJ Suppl 36:141 (doi 10.1111/j.2042-3306.2006.tb05530.x), JRA, cinta | Resumen | La constante T de recuperación cambia con atropina/propranolol (tono autonómico); con 11 semanas de entrenamiento T se correlaciona con VO₂max (r = 0,43, n = 7). Sin valores de T | [E-r] |
| Ohmura et al. 2002, EVJ 34:634 (doi 10.2746/042516402776180142) | Sin resumen | V200 en potros JRA: sin cifras legibles | [NV] |
| Kusunose & Takahashi 2002, J Equine Sci 13:117 (doi 10.1294/jes.13.117) | Resumen | Fiabilidad de EquiPILOT solo cualitativa; sin error numérico | [E-r] |
| Ikeda et al. 2019, J Equine Sci 30:93 (doi 10.1294/jes.30.93), carreras NAR (TCK) | Resumen | Factores del TFDS: pista *sloppy*, puesto ≥ 10.º, carrera corta, más peso, pérdida de peso, cambio corto de distancia; OR sin números | [E-r] (OR [NV]) |

Correcciones de referencias de la cola: Ohmura 2002 y Hada (2006, no 2007) son de **EVJ**, no de J-STAGE.

**Conclusiones T2 [I salvo indicación]**
- No hay TE ni CV numérico publicado legible de la V200 en PSI ni árabes. Con «diferencias medias ≤ 2 %» (sesgo, no
  TE) se propone un **TE por defecto provisional del 3 % de la V200** (≈ 18–20 m/min), marcado «por defecto, no
  validado», hasta tener el TE propio (≥ 3 pruebas estables).
- Kobayashi 2000: +68 m/min (+11 %) en 5 meses en potros, ≈ 2 %/mes de media. En adultos entrenados será menor.
  Un cambio > 4–5 % en un mes merece aviso de posible artefacto (protocolo, superficie, calibración de FC), no de forma.
- **Primer dato de V200 en árabes** en la KB: 610 ± 26 m/min en adultos (Italia) [E], del orden de los PSI jóvenes
  japoneses; no sirve de referencia de carreras de llano hasta confirmar la disciplina.
- T de recuperación: solo informativa (r moderada, n pequeño, sin valores de referencia) [E-r].

**Propuesta VT1–VT3 [I] (no implementada):** VT1 TE por defecto 3 % con marca; VT2 aviso de artefacto con |ΔV200| > 5 %
en ≤ 31 d; VT3 mostrar la V200 de árabes de Piccione solo como contexto, sin percentiles.

## Bloqueado o no encontrado
- Verheyen 2006 en texto completo: RVC Worktribe sin PDF; Unpaywall y Semantic Scholar sin permiso en la sesión;
  OpenAlex, CORE y Bristol Pure no probados por tiempo.
- J-STAGE: PDF de Ikeda 2019 y Kusunose 2002 denegados (robots / permiso caducado). PMC6920055, PMC11629100 y PubMed
  17402402 con reCAPTCHA; Europe PMC sin permiso. Wiley (EVJ Suppl) de pago.
- Sin estudios de V200 ni recuperación en árabes de carreras en llano (Golfo, Turquía, Polonia, Francia).

## Resumen
- **Verheyen:** el hallazgo es una interacción canter (≤ 14 m/s) > 44 km × galope (> 14 m/s) > 6 km en 30 d, con
  galope protector en añojos (resumen [E-r] + 3 secundarios). Se propone VC1–VC4 (regla combinada como LIMITAR, A1
  aislada como AVISO, A2 aislada a INFO); **no implementado**: OR [NV] y cambia severidades.
- **V200:** sin TE publicado; TE por defecto 3 % [I], cambio plausible ≈ 2 %/mes en potros [E-r], aviso de artefacto
  > 5 %/mes [I]. Primera V200 de árabes adultos: 610 ± 26 m/min [E], disciplina [NV].
- **Motor:** sin cambios de lógica. Probado en local y CI; **NO VERIFICADO** con caballos reales. La carga ósea nunca
  es una predicción de lesiones.
