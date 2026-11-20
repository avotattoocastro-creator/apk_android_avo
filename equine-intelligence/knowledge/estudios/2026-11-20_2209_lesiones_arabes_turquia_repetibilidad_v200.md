# Estudio horario 2026-11-20 22:09 UTC — Lesiones de árabes de llano en Turquía (serie Yıldırım) y repetibilidad de campo (Poinsard 2026)

**Base:** KB-1 1.23.0 → **1.24.0** · **Motor:** 2.0.0-dev25 → **2.0.0-dev26** (solo versiones; sin cambios de lógica)
**Rama:** `claude/kb-estudio-2026-11-20-2209`, encadenada desde `claude/kb-estudio-2026-11-20-2108` (PR #114, sin
fusionar; ya incluye la rama del PR #112).

## Decisiones tomadas sin supervisión

1. **Encadenamiento:** PR `claude/kb-*` abiertos: #112 (20:08) y #114 (21:08); #114 contiene a #112, así que la rama
   sale de #114 (KB 1.23.0, motor dev25).
2. **Temas** (no cubiertos por ningún estudio ni PR abierto, con prioridad «árabes de llano» y «auditoría de fuentes»):
   - **A. Lesiones de árabes de carreras en llano en Turquía:** la KB tenía el EVJ 2025 solo por resumen y el artículo
     de la misma serie en *Turkish J Vet Res* dos veces (duplicado) y como `SIN_AUDITAR` (regla AU1). Afecta al índice
     tendinoso (pendiente, prioritario en árabes de 3–4 años).
   - **B. Repetibilidad de campo de V200 y señales cortas (Poinsard 2026, MDPI de acceso abierto):** era la única
     fuente con ICC/MDC de campo y estaba como `RESUMEN`. Afecta a VT1–VT3 y A9.
3. **Acceso:** dos subagentes con WebFetch. En esta sesión desatendida **no se concedió permiso** a mdpi.com,
   pmc.ncbi.nlm.nih.gov, onlinelibrary.wiley.com, doi.org ni api.openalex.org; no se esquivó con cachés ni espejos.
   Solo se leyó en texto completo el PDF de DergiPark (TJVR). Lo demás queda [E-r] por fichas de terceros.
4. **Motor:** ninguna evidencia cerrada en texto completo que cambie un umbral; solo versiones.
5. **No se corrige** el ICC de V200 de Poinsard (0,50; 0,28–0,66) que ya estaba en la KB: los resúmenes vistos hoy no
   lo repiten, pero tampoco lo contradicen. Queda [E-r] y en cola el texto completo.

## Tema A — Lesiones de árabes de llano en Turquía

| Hallazgo | Población | Fuente | Etiqueta |
|---|---|---|---|
| Árabes, 216 lesiones: tendón 137 (63,7 %), fractura 42 (19,5 %), fisura 29 (13,5 %), desmitis 4 (1,9 %), rotura de tendón 2, chip 1; 102/216 (47,2 %) terminan la carrera deportiva | Hospital del hipódromo Şirinyer (Esmirna), 2018–2023 | Yıldırım & Karaarslan 2025, *Turk J Vet Res* 9(1):33–40, doi:10.47748/tjvr.1563380 ([PDF DergiPark](https://dergipark.org.tr/en/download/article-file/4272043)) | [E] |
| PSI, 337 lesiones: fractura 206 (61,5 %), tendón 86 (25,7 %), fisura 25 (7,5 %), chip 12, desmitis 5; 193 terminan la carrera | Misma serie | Misma fuente | [E] |
| Inconsistencias internas: tabla 1 da 208/43 fracturas frente a 206/42 en la tabla 2; un pie de figura dice 2018–2022; licencia CC BY-NC 4.0 en la cabecera y CC BY 4.0 al final | — | Misma fuente | [E] |
| El hospital atiende ≈ 20 % de los caballos de carreras; datos de un solo país; descriptivo, sin superficie ni carrera/entrenamiento (remite al EVJ) | — | Misma fuente | [E] |
| Población de árabes de carreras ×7,35 (426 → 3130) y sus carreras ×3,68 (811 → 2981) en el periodo analizado | TJC, 10 hipódromos, 1975–2022 | Misma fuente | [E] |
| 553 lesiones (= 337 + 216): fracturas 45,3 %, tendón 40,3 %, fisuras 9,8 %; pico jun–sep; distribución carrera/entrenamiento distinta según la pista en ambas razas (χ² 2×3 con Z post hoc, p < 0,0001) **sin OR ni IC**; anteriores 91,3 % PSI y 92,7 % árabes en carrera; carpo y distal; edad pico 2–3 años PSI y 3–4 árabes; fin de carrera 66,3 % PSI y 46,4 % árabes | Misma serie | Yıldırım, Karaarslan & Erkan 2025, *Equine Vet J*, doi:10.1111/evj.14457, PMID 39777406 (resumen vía [MadBarn](https://madbarn.com/research/distribution-of-race-and-training-related-musculoskeletal-injuries-by-track-and-location-in-thoroughbred-and-arabian-racehorses)) | [E-r] |
| Discrepancia de fin de carrera en árabes: 46,4 % (EVJ) frente a 102/216 = 47,2 % (TJVR) | — | Ambas | [I] (cálculo) |
| Tendinitis/peritendinitis de flexores metacarpianos: 118 caballos (56 árabes), 120 casos; sin asociación con raza, edad, sexo, altura ni peso; la pista no se estudia | Turquía | *J Res Vet Med*, año [NV] ([ficha AcarIndex](https://www.acarindex.com/journal-of-research-in-veterinary-medicine/turkiyede-yaris-atlarinda-tendinitis-ile-etiyolojik-faktorler-arasindaki-iliski-atlarla-iliskili-parametrelerin-etkisi-1081788)) | [E-r] |
| Pieszka, Łuszczyński & Baranowska (Polonia), frecuencias de lesiones PSI frente a árabes | — | [ficha](https://sanad.iau.ir/en/Article/1023289) sin resumen | [NV] |
| Incidencia por 1000 salidas, OR por superficie, TFDS frente a suspensor, sesamoideos/MC3, punto de la carrera y distancia en árabes | — | Texto completo del EVJ | [NV] |

**Lectura para AVO.**
- Las proporciones son de una **serie hospitalaria** (≈ 20 % de la población, sesgo de derivación): no son
  incidencias ni riesgos y no sirven como umbral [I].
- Confirman con texto completo lo que la KB ya decía por resumen: en árabes de llano domina el **tendón**; en PSI, la
  **fractura**. Refuerza que el índice tendinoso sea prioritario en árabes de 3–4 años.
- **TA1–TA2 (propuesta [I], sin implementar):** en árabes, el resumen de riesgo muestra antes el índice tendinoso que
  la fatiga ósea; en PSI, al revés. Es orden de presentación, no cambia umbrales. La fatiga ósea **nunca es una
  predicción de lesiones**, y el índice tendinoso tampoco.
- Auditoría (regla AU1): `YILDIRIM_KARAARSLAN_2025_TJVR` pasa de `SIN_AUDITAR` a `TEXTO_COMPLETO` y es la canónica;
  `YILDIRIM_KARAARSLAN_2025` se marca `duplicado_de`.

## Tema B — Repetibilidad de campo (Poinsard 2026)

| Hallazgo | Población | Fuente | Etiqueta |
|---|---|---|---|
| Identificadores: doi:10.3390/ani16111598, PMID 42278033, PMC13255733; publicado 24/05/2026; el título se centra en el **coste cardíaco** (FC/velocidad, latidos/m) como herramienta de control | Trotón francés | Poinsard, Anson & Billat 2026, *Animals* 16(11):1598 ([MDPI](https://www.mdpi.com/2076-2615/16/11/1598); resúmenes vía MadBarn —generado por IA— y Synapse) | [E-r] |
| Sesión: calentamiento + 2 bloques de 2000 m a intensidad creciente; Polar Team Pro | 60 caballos, 483 sesiones | Misma fuente | [E-r] |
| Subconjunto de repetibilidad: 18 caballos, 36 bloques, 126 sesiones; cada bloque ≥ 3 sesiones con ≤ 7 d entre ellas; ICC ajustado por temperatura | Trotón | Misma fuente | [E-r] |
| ICC: coste cardíaco bloque 1 0,67 (0,48–0,78); recuperación FC tras B1 0,60 (0,40–0,73), tras B2 0,66 (0,47–0,78); V150 0,59 (0,39–0,73); V180, velocidad de recuperación y coste del B2 «pobres» | Trotón | Misma fuente | [E-r] [I-raza] |
| MDC: coste cardíaco B1 0,04 latidos/m; recuperación FC tras B1 26 lpm | Trotón | Misma fuente | [E-r] |
| ICC de V200 0,50 (0,28–0,66) | Trotón | Ya en la KB (página del editor, estudio anterior) | [E-r], no reconfirmado hoy |
| Diferencias medias test-retest ≤ 2 % para VHRmax, V200 y FCmax (medias de 5 s, GPS); sin TE ni ICC | 12 PSI de 3–5 años | Vermeulen & Evans 2006, EVJ Suppl 36:113, doi:10.1111/j.2042-3306.2006.tb05525.x | [E-r] (ya en la KB) |
| Repetibilidad «aceptable» de las pruebas de campo, afectada por jinete/conductor, pista y clima | Revisión | De Mare et al. 2017, *Vlaams Diergeneeskd Tijdschr* 86:63 ([CORE](https://core.ac.uk/download/84042571.pdf)) | [E] (ya en la KB) |
| TE de V200 en m/s o CV en PSI o árabes | — | — | [NV] (no publicado o no accesible) |

**Lectura para AVO.**
- Sigue sin existir un TE publicado de V200 para PSI/árabes; el 3 % por defecto de VT1 continúa «no validado».
- El diseño de Poinsard da un **criterio práctico de bloque**: ≥ 3 sesiones en ≤ 7 d, con temperatura registrada, para
  estimar la repetibilidad propia. **RB1 (propuesta [I], sin implementar):** el TE propio de V200/V150/recuperación/
  coste cardíaco solo se calcula en esos bloques; fuera de ellos se marca «TE no propio»; como señal corta conviene
  preferir el coste cardíaco y la recuperación a 60 s antes que la V200 aislada. Los valores son de trotones
  [I-raza: misma fisiología cardiovascular de caballo atleta, distinto gesto y pista].
- `te_recuperacion_fc_lpm` = 9,4 lpm se mantiene (26 / (1,96·√2) si el MDC es un MDC95 [I]).

## Cambios en la base (KB 1.24.0)

- Fuentes nuevas (2): `TENDINITIS_TURQUIA_JRVM` (resumen), `PIESZKA_LIMB_INJURIES_TB_ARAB` (no accesible).
- Fuentes actualizadas (4): `YILDIRIM_KARAARSLAN_2025_TJVR` (TEXTO_COMPLETO, canónica), `YILDIRIM_KARAARSLAN_2025`
  (`duplicado_de`), `YILDIRIM_2025` (autores, PMID, método), `POINSARD_2026` (DOI, PMID, PMCID, diseño del bloque).
- Parámetros de referencia (2): `proporcion_tendon_lesiones_arabes_turquia` (0,637), `repetibilidad_campo_bloque_poinsard`.
- Reglas propuestas (2): `TENDON_ARABES_TA1_TA2`, `REPETIBILIDAD_BLOQUE_RB1`. Pendiente del motor: 1. Cola: 3.
- **Sin cambios de lógica, reglas implementadas, parámetros activos ni umbrales.** Nada verificado con caballos reales.

## Resumen

- En la serie turca (texto completo de TJVR), el **tendón** es el 63,7 % de las 216 lesiones de árabes de llano y la
  **fractura** el 61,5 % de las 337 de PSI; es una serie hospitalaria, no un riesgo. La superficie y el punto de la
  carrera siguen [NV] (EVJ sin acceso). Duplicado de la KB fusionado y fuente reclasificada.
- Poinsard 2026: diseño del bloque de repetibilidad (≥ 3 sesiones en ≤ 7 d) y señales más repetibles (coste cardíaco,
  recuperación de FC) [E-r]; sigue sin TE publicado de V200 en PSI/árabes.
- Propuestas TA1–TA2 y RB1 [I], sin implementar. Motor 2.0.0-dev26 solo por versión.
- Bloqueos de esta sesión: mdpi.com, PMC, Wiley, doi.org y OpenAlex sin permiso de red (sesión desatendida).
