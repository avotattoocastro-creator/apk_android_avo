# Investigación nocturna 21/11/2026 — Auditoría de 20 fuentes (V200, carga ósea, tendón, ECG, IMU) y FCmax/V200/velocidad de árabes de llano con cobertura mundial

**KB-1 1.24.0 → 1.25.0 · motor 2.0.0-dev26 → 2.0.0-dev27 (solo versiones, sin cambios de lógica).**
Disciplina: PSI y árabes de carreras en **llano** (no raid). Ventana 04:08–05:45 (Madrid), sesión en la nube desatendida.

## Decisiones tomadas sin supervisión
1. No había PR de la KB abiertos (`claude/kb-*` todas fusionadas): la rama `claude/kb-noche-2026-11-21` sale de `develop` (09b0be0).
2. La shell de la nube no tiene salida a Internet (Europe PMC, OpenAlex, Unpaywall, Semantic Scholar, Crossref → sin conexión por el proxy). Todo se leyó con WebSearch + WebFetch (solo URLs devueltas por la búsqueda). PMC devuelve reCAPTCHA; no se esquivó.
3. WebFetch entrega una **extracción del texto completo hecha por la herramienta**, no una copia literal: se etiqueta [E] cuando la herramienta procesó el texto completo del editor o del repositorio, y se anota «extracción por la herramienta».
4. Se **descarta** una cifra de repetibilidad de V200 (Kobayashi, 31 pares, r 0,88) porque la única copia hallada es un capítulo de libro reproducido en un sitio de legalidad dudosa; queda en cola para leerla en el original.
5. **Ningún pendiente del motor se implementa esta noche:** no hay evidencia cerrada en texto completo de PSI/árabe que permita un cambio de lógica (el umbral VT1 de V200 sigue sin TE publicado de PSI/árabe). Solo se suben versiones.
6. Subagentes en paralelo (3 de auditoría, 1 Asia/Golfo/Turquía/Polonia, 1 novedades + Latinoamérica, 1 África/Nueva Zelanda/Hong Kong) con las mismas reglas.

## 1. Auditoría de fuentes (20 fuentes; 14 mejoradas)

### Lote 1 (12 fuentes; 7 mejoradas)

| Fuente | Antes | Ahora | Resultado |
|---|---|---|---|
| POINSARD_2026 (trotón francés) | RESUMEN | **TEXTO_COMPLETO** (mdpi.com) | ICC confirmados; **corrección del método de V200**; datos nuevos |
| KALISIAK_2012 (+ duplicado _POLJVS) | SIN_AUDITAR | **TEXTO_COMPLETO** (journals.pan.pl) | cifras confirmadas; errata del artículo detectada |
| PFAU_2024 | SIN_AUDITAR | **TEXTO_COMPLETO** (mdpi.com) | **corrección de población** |
| MORRICE_WEST_2021 | SIN_AUDITAR | **TEXTO_COMPLETO** (mdpi.com) | identificada (Animals 11:3130); **corrección**: no da km/semana |
| LEE_2019_KOREA | RESUMEN | **TEXTO_COMPLETO** (tesis, Univ. Nacional de Jeju) | cifras confirmadas y ampliadas |
| ICRAV_2026_HK | SIN_AUDITAR | **CONGRESO** | resumen 130413 leído |
| FRICK_2019 | RESUMEN (agregador) | RESUMEN (repositorio BORIS, Berna) | cifras confirmadas; n desglosado |
| MORRICE_WEST_2025 | AGREGADOR | AGREGADOR | **corrección de redacción** (HR 1,80 y referencia) |
| MARTIG_2013 | AGREGADOR | AGREGADOR (+ uso en texto OA de Morrice-West 2022) | curvas confirmadas; n = 23 muestras |
| GRAMKOW_EVANS_2006 | AGREGADOR | AGREGADOR | definición de VHRmax (extrapolación) [E-r] |
| VERHEYEN_2006 | RESUMEN | RESUMEN | sin texto completo legal; OR siguen [NV] |
| CARRIER_1998 | AGREGADOR | AGREGADOR | RR 71/45 (solo húmero) confirmados; DOI no existe en lo leído |

### 1.1 Poinsard, Anson & Billat 2026 (Animals 16:1598) — trotón francés [E, I-raza]
- Domaine de Grosbois; Polar Team Pro (FC 1 Hz, GNSS 10 Hz); 60 caballos, 483 sesiones; subconjunto de repetibilidad 18 caballos, 36 bloques, 126 sesiones (≥ 3 sesiones con ≤ 7 d) — **confirmado**.
- Protocolo: calentamiento ~10 min, dos bloques de 2.000 m (B1, B2) con 4 min de recuperación activa; velocidades objetivo por edad (p. ej. 3 años 33,6/37,8 km/h).
- **CORRECCIÓN:** V150/V180/V200 **no** salen de una regresión FC–velocidad: son la velocidad en el **primer cruce** del umbral de FC mantenido ≥ 10 s (el cruce válido más temprano de B1 o B2). Nuestra nota anterior lo dejaba abierto.
- Estadística: modelos mixtos (REML), SEM = √(varianza residual), **MDC95 = 1,96·√2·SEM** → el parámetro `te_recuperacion_fc_lpm` = 26/2,77 ≈ 9,4 lpm queda **confirmado** como SEM (antes [I]).
- ICC ajustados (edad, sexo, temperatura; el ajuste por temperatura cambia < 0,01): V200 0,50 (0,28–0,66), V150 0,59 (0,39–0,73), coste cardíaco B1 0,67 (0,48–0,78), recuperación 60 s tras B1 0,60 — **confirmados**. **Nuevos:** coste B2 0,23 (pobre), recuperación tras B2 0,66 (0,47–0,78) con MDC95 22 lpm; ajustada por la velocidad durante la recuperación 0,69/0,68 (cada km/h sube la FC a 60 s 1,62/0,86 lpm).
- Tabla 3: V200 40,4 → 40,6 km/h (≈ 11,2 m/s; +0,3 ± 3,1, p 0,62) entre la primera y la última sesión del bloque; V200 +0,40 km/h por año de edad (p < 0,001).
- MDC/SEM de V200 solo en la tabla S2 (no accesible) → [NV].
- Transferencia: otra marcha (trote) y otro método de V200 → [I-raza]; ver regla MV1.

### 1.2 Kalisiak 2012 (Pol J Vet Sci 15:111) — PSI y árabe de llano, Służewiec [E]
- 2001–2006; 274 ecografías, 187 lesionados (158 PSI, 29 árabes) sobre ~1.100 caballos/año (718 PSI, 396 árabes). Sin OR ni tasa por raza (solo χ², Fisher, Mann-Whitney).
- Árabes: TFDS 24/29 (82,8 %); suspensor 5/29 — el artículo imprime 7,2 %, pero 5/29 = **17,2 %** (errata del artículo; nuestras cifras usaban el 82,8 %, que es correcto).
- Vuelta a competir: PSI 55/133 (41,4 %) frente a árabes 4/26 (15,4 %), sin contraste → parámetro `vuelta_carrera_tendon` confirmado.
- Potros más afectados que potrancas a 2 años (8,1 % frente a 4,1 %, p 0,004) y a 3 años (5,8 % frente a 2,4 %).

### 1.3 Pfau et al. 2024 (Sensors 24:2441) [E, I para PSI de carreras]
- Título real: preparación de la pista de tierra y velocidad/zancada al galope (Univ. Calgary, Calgary Stampede).
- **CORRECCIÓN de población:** 12 **PSI castrados de 8–15 años de outriders** de chuckwagon, un jinete; **no** son caballos de carreras en activo. Racelogic VBox 10 Hz.
- 16,48 m/s (Q1 15,86–Q3 17,10) — confirmado ≈ 16,5; zancada 6,69 m y 2,47 Hz; +0,359 m y +0,018 Hz por m/s.
- Diferencia máxima de longitud de zancada entre dureza × humedad 18,6 cm (la Discusión dice 18,3) — parámetro `zancada_superficie_variacion_m` 0,186 confirmado; entre sesión × calle hasta 32,7 cm.

### 1.4 Morrice-West et al. 2021 (Animals 11:3130, DOI 10.3390/ani11113130) — PSI, Victoria [E]
- 66 de 889 entrenadores (7,4 %), temporada 2016/17, cruzado con Racing Victoria. Bandas de galope: ≥ 13,3 m/s (lento 13,3–14,3; medio 14,4–15,4; alto 15,5–16,7; muy alto ≥ 16,8).
- **CORRECCIÓN:** no publica km por semana ni recuento de trabajos rápidos; las cargas van en metros por cada 1.000 m de cambio y los descansos por año.
- Relaciones en U invertida (óptimo intermedio): victorias frente a distancia de galope antes del trial IRR 1,09 (1,01–1,17); victorias frente a semanas entre salidas IRR 3,35 (1,02–11,06), término cuadrático 0,80; premios frente a descansos por año coef. 2,38 (0,70–4,05).
- `MORRICE_WEST_2021_INTERVALO` (core.ac.uk) es probablemente la misma obra [I].

### 1.5 Morrice-West et al. 2025 (Vet J 314:106502) — PSI, Tasmania [E-r, AGREGADOR]
- 405 caballos, 3.168 salidas, **71** primeras lesiones.
- **CORRECCIÓN de redacción:** el HR 1,80 (1,53–2,11) es de la ventana «carrera completa», no «por carrera». En la ventana de 4 salidas la categoría **media** (0,25–0,75) es la **referencia**: baja ×2,89 (p 0,005), alta ×8,51 → curva en U (la carga baja tampoco es segura). La regla A4 ya lo interpretaba así (baja = fatiga ósea < 0,25); solo cambia la nota.

### 1.6 Martig et al. 2013 (Bone 57:392) — PSI [E-r + texto OA de terceros]
- Autores: Martig S, Lee PV, Anderson GA, Whitton RC. Curvas 134,2 − 14,1·log10(Nf) (R² 0,72) y 112,2 − 9,6·log10(Nf) (R² 0,52) **confirmadas**; usadas tal cual en Morrice-West 2022 (Sci Rep, texto completo OA).
- Nuevo: 23 muestras (6/6/5/6 a 54/66/78/90 MPa); mediana de ciclos 223.603 / 69.908 / 13.204 / 4.001; módulo inicial 2.500 ± 494 MPa.
- Nota de coherencia: el vértice de la parábola de fuerza da 24,13 N/kg; Morrice-West 2022 lo sitúa a 20,99 m/s según la extracción y nuestra KB a 19,98 m/s (−b/2a = 2,1376/0,107 = 19,98) → nuestro valor es el aritméticamente correcto; se mantiene.

### 1.7 Resto
- **Gramkow & Evans 2006** (EVJ Suppl 36:118–122): VHRmax = extrapolación de la regresión lineal FC–velocidad (trote + galope) hasta la FCmax de cada caballo [E-r]; n 25, un entrenador, ≥ 6 salidas. Cifras confirmadas.
- **Frick 2019** (JVIM 33:212): 54 caballos (13 sanos, 30 con arritmias, 11 bajo rendimiento sin arritmias); −4,4/+3,8 % (trote), −6,1/+5,4 % (canter), corte 6 % en recuperación (S 88 %, E 97 %, LR 26) confirmados [E-r]; razas y velocidades [NV].
- **Verheyen 2006** (Bone 39:1322): 13 entrenadores, 1998–2000 [E-r]; la tesis (Univ. of London, 2005) solo está en papel en el RVC. OR por categoría siguen [NV] → la regla combinada VC1 sigue PROPUESTA.
- **Carrier 1998** (JAVMA 212:1582): RR 71 (10 d) y 45 (21 d), solo húmero [E-r].
- **ICRAV 2026, resumen 130413** [CONGRESO]: 5.215 caballos (2010–2021), 3.092 con lesión; %SBFL mediano por evento: carrera 10,1 %, ensayo 8,19 %, trabajo rápido 3,21 %, lento 0,41 %; HR > 5 para el quintil superior de la tasa aguda (valor exacto [NV]). El país de la población no se reconfirmó.


### Lote 2 (8 fuentes `SIN_AUDITAR` o de resumen citadas por reglas; 7 mejoradas)

| Fuente | Antes | Ahora | Resultado |
|---|---|---|---|
| TER_WOORT_2023 (+ duplicado _2022) | SIN_AUDITAR | **TEXTO_COMPLETO** (PMC10078706, sin reCAPTCHA esta vez) | métricas reales: κ, no sensibilidad/especificidad |
| NAVAS_DE_SOLIS_2026 | SIN_AUDITAR | **TEXTO_COMPLETO** (PDF en WEVA) | serie de casos **sin controles** |
| PARSONS_2008 | SIN_AUDITAR | **TEXTO_COMPLETO** (JEB, libre) | **autoría corregida** (falta Ferrari M); duplicado de PARSONS_2008_PENDIENTE |
| VERKADE_2020 | SIN_AUDITAR | **TEXTO_COMPLETO** (manuscrito aceptado, UCL) | **corrección**: estudio mecánico ex vivo, no epidemiológico |
| VAN_STEENKISTE_2020_QRS | SIN_AUDITAR | **TEXTO_COMPLETO** (Nature, OA) | cifras de detección de QRS |
| BEAUMONT_2025 | SIN_AUDITAR | RESUMEN (agregador + prensa) | regla de los autores ≥ 10 % en 2 meses |
| TRACHSEL_2011 | SIN_AUDITAR | AGREGADOR | año probablemente 2010; concordancia en ejercicio muy baja |
| HAMLIN_2002 | RESUMEN | RESUMEN | % de V200 sigue [NV] |

- **Ter Woort et al. 2023** (EVJ 55:336, doi 10.1111/evj.13565) [E]: Francia y Australia, 49 caballos (41 PSI de carreras, 3 trotones, 5 de salto). Equimetre frente a Televet: detección de arritmias κ 0,97 (1,0 sin 2 casos con ruido), clasificación κ 0,93; artefacto en ejercicio 0,25 % frente a 5 % (P < 0,001); 3 frente a 9 ECG no diagnósticos (> 10 % de artefacto); arritmias en 21/38 caballos (55 %), sobre todo en la recuperación (11 casos); alta intensidad 48 ± 4,2 km/h y 210 ± 12 lpm. **No publica sensibilidad, especificidad ni % de ECG legible por fase** [NV].
- **Navas de Solis et al. 2026** (EVJ, doi 10.1002/evj.70166) [E]: 11 PSI con muerte súbita asociada al ejercicio, 24 ECG de ejercicio (Australia, Francia, Reino Unido, EE. UU.); alguna arritmia en ejercicio 70 %; compleja en ejercicio 15 %, en recuperación temprana 10 % y tardía 25 %; FA 17 %; FC pico mediana 216–218 lpm. **Sin controles:** no da prevalencia ni riesgo.
- **Trachsel et al. 2010/2011** (EVJ Suppl 38:208) [E-r, warmblood, I-raza]: concordancia en la detección de arritmias 92,6–97 % en reposo, pero **20 % intraobservador y 0–13 % entre observadores durante el ejercicio**.
- **Van Steenkiste et al. 2020** (Sci Rep 10:186) [E]: ECG equino a 500 Hz; detector de QRS por wavelets sensibilidad 98,0 % y VPP 99,1 % (Pan-Tompkins 91,5 % / 81,5 %); raza [NV].
- **Parsons et al. 2008** (JEB 211:945) [E]: 6 PSI de National Hunt; IMU de 6 GDL en T4–T6, ±10 g a 250 Hz; 9–12 m/s; 1.113 zancadas; cabeceo 12,9° (llano) y 16,7° (pendiente) a 9 m/s; sin aceleraciones pico numéricas [NV].
- **Verkade et al. 2020** (EVJ 52:320, doi 10.1111/evj.13169) [E]: ensayo mecánico de TFDS de 12 warmblood, 12 frisones y 8 PSI (sin árabes): módulo PSI 596 ± 100 frente a warmblood 397 ± 87 MPa (P 0,009); deformación última 25,3 frente a 32,6 %. **No da OR ni prevalencia de rotura**: su cita en la KB se corrige.
- **Beaumont et al. 2025** (AJVR 86(8)) [E-r, trotón francés, I-raza]: 12 trotones de 3 años; CSA del TFDS sano +6,8 % a 2 meses; en los que luego se lesionaron +13 % (D0→M2) y +27,9 % (M2→M4); regla de los autores: sospechar daño si sube ≥ 10 % en 2 meses (coherente con el índice tendinoso, que ya usa «CSA ≥ +10 % en 2 meses»); el corte 9,84 % (S 100 %, E 77,8 %) solo aparece en prensa [NV].
- **Hamlin et al. 2002** (EVJ 34:383) [E-r, trotón, Nueva Zelanda]: tiempo de los últimos 1.200 m +4,0 % (1,7–5,8), velocidad pico −6,9 % (4,7–8,9); el % de caída de V200 sigue [NV].

## 2. Investigación nueva

### 2.1 FCmax y V200 en árabes de carreras de llano; repetibilidad de V200 (cola 11, VT1)
- **Polonia — Janczarek et al. 2016** (Annales UMCS EE 34(2), en polaco) [E]: 15 árabes de llano de 3 años y 15 PSI de 2 años, Polar RS800CX + GPS. En el galope de prueba los árabes registraron **211,2 ± 6,6 lpm a 15,75 m/s** (machos) y **212,3 ± 5,1 lpm a 15,65 m/s** (hembras); PSI 209,3/213,3 lpm a ~16,7 m/s. No dice si es media del tramo o pico (el medio galope de los machos, 208 lpm, supera a la «szpryca», 202 → probablemente media) → **cota inferior** de la FCmax de árabes de llano [I].
- **Japón — Mukai et al. 2007** (J Equine Sci 18:153) [E-r]: pico en carrera 213,6 ± 1,7 lpm (PSI, n 23).
- **Corea — Lee 2019 / tesis** [E]: FCmax en galope 214 ± 11 lpm; V200 13,7 m/s por regresión con datos de galope en arena.
- **Repetibilidad de V200 en PSI/árabes:** ningún estudio japonés, coreano, polaco, turco, del Golfo ni francés da CV, ICC o error típico. El VT1 (TE por defecto 3 % «no validado») sigue sin fuente propia de PSI/árabe.
- **Heterogeneidad de métodos** [E de cada fuente, I la conclusión]: V200 coreana (regresión con galope) 13,7 m/s; japonesa en potros 10,4–11,5 m/s; trotones por primer cruce ≈ 11,2 m/s; árabes y angloárabes en pista de hierba (Piccione 2004, prueba triangular) 9,7–10,2 m/s. Los protocolos dan valores no intercambiables → propuesta **MV1**.
- Piccione 2004 reconfirmado: árabes de 6–8 años y angloárabes de 2–4 años entrenados en pista de galope; **no consta que corran carreras de llano** → sigue [I-raza/población].

### 2.2 Velocidades de árabes de llano (Turquía, Brasil) [E]
- Paksoy & Ünal 2010 (en turco): ganadores árabes de 3 años 14,69 (1.200 m), 14,76 (1.400 m), 14,61 (1.600 m) y 13,92 m/s (1.800 m); PSI 15,5–15,7.
- Duru 2017 (en turco): 8.321 árabes, 35.929 carreras: 14,45 m/s (1.000 m) a 13,74 m/s (2.400 m); repetibilidad de la velocidad 0,07.
- Siqueira 2024 (Brasil): 30 árabes de llano; galope rápido 13–18 m/s en 1.000–1.200 m; lento 6–8 m/s.

### 2.3 América Latina (datos propios por país)
- **Brasil:** Kowal 2006 (Río, n 20, cinta 6°) lactato 3,82 (6 m/s), 7,70 (8 m/s), 16,1 mmol/L (10 m/s), FC final 205–237 lpm [E; cinta inclinada ≠ pista, I]; Kowal 2008 gasometría (pH 7,17); Mello 2012 (potros, lactato 1,2–2,8 mmol/L tras el trabajo); Pereira 2013 (n 416, periostitis del MC3 46 %); Berkman 2015 ya en la KB (tablas por leer).
- **Argentina:** Britos (UNLP, resumen) 557 PSI con dolor de menudillo, 31,7 % fractura de sesamoideos [CONGRESO].
- **Uruguay:** Bimson 2022 (ya en la KB). **México:** Servín 2012 (UNAM) 15,7–15,9 m/s en 1.106–1.307 m. **Venezuela:** Morales 2009, 55,1 % de las catastróficas en sesamoideos. **Colombia:** Arias 2016 (CK). **Chile y Perú:** sin cifras de FC/lactato accesibles.

### 2.4 Novedades (desde el 20/11)
Ningún estudio original nuevo del 15 al 21/11 con cifras de entrenamiento o telemetría en PSI/árabes. De octubre–noviembre: Edling 2026 (EVJ, FA paroxística, n 7, molecular); biomarcadores CCL3:CCL5 (JAVMA, PRENSA: identifica el 84 % de las lesiones fatales con sangre **tomada tras la lesión**: no predictivo); HISA 2.º trimestre 2026 [OFICIAL]: 1,01 muertes por 1.000 salidas y 0,43 por 1.000 trabajos. Anwar 2026 (RSOS), Schild 2026 y Mizobe 2026 ya estaban en la KB.


### 2.5 África, Nueva Zelanda y Hong Kong (poblaciones propias)
- **Sudáfrica (Gauteng):** Cilliers 2009 (tesis MMedVet, Pretoria) [E, leída en parte]: 55 lesiones catastróficas en 103.603 salidas (0,53 por 1.000); riesgo con **< 1 semana entre carreras**, peso llevado > 59 kg y machos enteros; going, distancia y edad sin efecto. Spargo 2019 (JSAVA 90:a1640) [E-r]: 0,6 por 1.000 salidas (1998–2012); sesamoideos proximales y suspensor distal 55,3 %. Morley 2015 [E]: HPIE ≥ grado 1 en el 68 % de 886 endoscopias; sin HPIE OR de ganar 2,3 (1,4–3,7). **Sin datos de carga de entrenamiento (km/semana, FC) en Sudáfrica.**
- **Nueva Zelanda:** Perkins 2005 (tesis de Massey) [E, en parte]: 68,3 ± 32,5 d hasta la primera salida; mediana 17 d (13–23) entre salidas (2 años 20; ≥ 5 años 14). Legg 2021 [E]: descanso entre preparaciones 161 d, preparación 64 d, ~13 semanas al año sin entrenar frente a 6,3 en Australia. Bolwell 2017 [E-r]: 0,72 lesiones musculoesqueléticas por 1.000 salidas. Km por semana y trabajos rápidos de NZ siguen sin leer (Kingston 2007, Bolwell 2010/2012, en cola).
- **Hong Kong:** Sun 2016 (MPhil, Queensland) [E, en parte]: 0,6 catastróficas y 2,2 no catastróficas por 1.000 salidas; 0,08 y 0,85 por 10.000 días de entrenamiento. Johnston 2020 (EVJ) [E]: 1,7 % de 5.180 importados con fractura por estrés en 12 meses (húmero ~42 %).
- **Magreb, Egipto, Kenia, Zimbabue, Mauricio, Singapur, Malasia:** sin datos de fisiología de ejercicio de PSI o árabes de llano (solo bioquímica en Argelia, prensa en Marruecos y Singapur, casuística sin denominador en Malasia).

## 3. Propuestas [I] (sin implementar)
- **MV1 — método de V200 como atributo:** cada V200 guarda su método (regresión FC–velocidad de AVO, primer cruce ≥ 10 s, cinta); comparables y TE solo dentro del mismo método. El ICC 0,50 de Poinsard (cruce, trotones) no se aplica sin más a la V200 por regresión de AVO.
- **FM1 — FCmax por defecto:** 210–215 lpm (PSI y árabe de llano) solo para expresar % de FCmax hasta tener la FC pico propia (máximo de ≥ 3 trabajos rápidos), con la marca «FCmax no propia»; nunca 220 − edad.
- **EC1 — arritmias en galope:** las arritmias detectadas en el tramo de galope se presentan como «revisar por un veterinario», nunca como diagnóstico, y se da prioridad a la ventana de recuperación (0–15 min), donde aparecen más (Ter Woort 2023, Navas de Solis 2026) y la lectura es más fiable (Trachsel: 0–20 % de concordancia en ejercicio).
- **Contexto poblacional:** incidencias de lesión catastrófica de 0,4–0,7 por 1.000 salidas (Sudáfrica, Hong Kong, Uruguay) y 1,01 muertes por 1.000 en EE. UU. (HISA 2026, T2) solo como contexto; definiciones distintas entre países.
- La fatiga ósea sigue siendo un indicador de carga, **no una predicción de lesiones**.

## TABLA DE FUENTES

| Cita | DOI / URL | País | Idioma | Raza (raza_fuente) | Acceso | Cifra que sostiene |
|---|---|---|---|---|---|---|
| Poinsard, Anson & Billat 2026, Animals 16:1598 | 10.3390/ani16111598 · mdpi.com/2076-2615/16/11/1598 | Francia | en | trotón francés [I-raza] | TEXTO_COMPLETO | ICC V200 0,50; SEM recuperación 9,4 lpm; V200 por cruce ≥ 10 s |
| Kalisiak 2012, Pol J Vet Sci 15:111 | 10.2478/v10181-011-0121-9 · journals.pan.pl | Polonia | en | PSI y árabe de llano | TEXTO_COMPLETO | TFDS 82,8 % en árabes; vuelta 15,4 % frente a 41,4 % |
| Pfau et al. 2024, Sensors 24:2441 | 10.3390/s24082441 · mdpi.com/1424-8220/24/8/2441 | Canadá | en | PSI outriders 8–15 años | TEXTO_COMPLETO | 18,6 cm de zancada por suelo |
| Morrice-West et al. 2021, Animals 11:3130 | 10.3390/ani11113130 · mdpi.com/2076-2615/11/11/3130 | Australia | en | PSI | TEXTO_COMPLETO | bandas de galope; U invertida |
| Lee YW 2019 (J Vet Clin 36:62) y tesis | 10.17555/jvc.2019.02.36.1.62 · mslib.jejunu.ac.kr | Corea | ko/en | PSI | TEXTO_COMPLETO (tesis) | FCmax 214 lpm; V200 13,7 m/s |
| ICRAV 2026, resumen 130413 | icrav-2025.p.asnevents.com.au/…/130413 | [NV] | en | PSI | CONGRESO | %SBFL por evento |
| Frick, Schwarzwald & Mitchell 2019, JVIM 33:212 | 10.1111/jvim.15358 · boris.unibe.ch/124563 | Suiza | en | [NV] | RESUMEN | corte 6 % RR |
| Morrice-West et al. 2025, Vet J 314:106502 | 10.1016/j.tvjl.2025.106502 · madbarn | Australia | en | PSI | AGREGADOR | HR 2,89 / 8,51; regla A4 |
| Martig et al. 2013, Bone 57:392 | 10.1016/j.bone.2013.09.006 · madbarn + nature.com/articles/s41598-022-14274-y | Australia | en | PSI | AGREGADOR (+ OA de terceros) | curva S-N |
| Gramkow & Evans 2006, EVJ Suppl 36:118 | 10.1111/j.2042-3306.2006.tb05526.x · madbarn | Australia | en | PSI | AGREGADOR | VHRmax < 14,5 m/s |
| Verheyen et al. 2006, Bone 39:1322 | 10.1016/j.bone.2006.05.025 · research-information.bris.ac.uk | Reino Unido | en | PSI | RESUMEN | A1/A2, VC1 |
| Carrier et al. 1998, JAVMA 212:1582 | PMID 9604029 · madbarn | EE. UU. | en | PSI | AGREGADOR | P7 reincorporación |
| Janczarek et al. 2016, Annales UMCS EE 34(2) | czasopisma.up.lublin.pl/jasbb/article/download/946/696/2409 | Polonia | pl | árabe de llano y PSI | TEXTO_COMPLETO | FCmax ≥ 211–212 lpm en árabes |
| Mukai et al. 2007, J Equine Sci 18:153 | 10.1294/jes.18.153 · jstage | Japón | en | PSI | RESUMEN | pico en carrera 213,6 lpm |
| Piccione et al. 2004, Vet Med Czech 49:291 | 10.17221/5707-VETMED | Italia | en | árabe y angloárabe [I-raza] | TEXTO_COMPLETO | V200 9,7–10,2 m/s |
| Paksoy & Ünal 2010, Lalahan 50(2):91 | dergipark.org.tr/…/544405 | Turquía | tr | árabe de llano | TEXTO_COMPLETO | 13,9–14,8 m/s en carrera |
| Duru 2017, Iğdır Üniv. 7(4):289 | dergipark.org.tr/…/419911 | Turquía | tr | árabe de llano | TEXTO_COMPLETO | 13,74–14,45 m/s; repetibilidad 0,07 |
| Siqueira et al. 2024, Ciência Rural 54(10) | scielo.br/j/cr/a/ZbjKCSMXgqRBHy4935ckGry | Brasil | en | árabe de llano | TEXTO_COMPLETO | galope rápido 13–18 m/s |
| Kowal et al. 2006, Rev Bras Ciênc Vet 13:13 | 10.4322/rbcv.2014.259 | Brasil | pt | PSI | TEXTO_COMPLETO | lactato por velocidad (cinta 6°) |
| Kowal et al. 2008, Rev Bras Ciênc Vet 15:21 | 10.4322/rbcv.2014.190 | Brasil | pt | PSI | TEXTO_COMPLETO | gasometría |
| Mello 2012, tesis UFRRJ | [NV] | Brasil | pt | PSI | TEXTO_COMPLETO | velocidades del programa |
| Pereira et al. 2013, Ciência Rural 43(7) | 10.1590/S0103-84782013000700023 | Brasil | pt | PSI | TEXTO_COMPLETO | casuística |
| Britos et al., UNLP (SEDICI) | [NV] | Argentina | es | PSI | CONGRESO | 31,7 % sesamoideos |
| Servín 2012, tesis UNAM | [NV] | México | es | PSI | TEXTO_COMPLETO | 15,7–15,9 m/s |
| Morales et al. 2009, RIVEP 20(2) | [NV] | Venezuela | es | PSI | TEXTO_COMPLETO | catastróficas |
| Arias et al., Rev Colomb Cienc Pecu 17(2) | 10.17533/udea.rccp.323933 | Colombia | es | PSI | RESUMEN | CK |
| Edling et al. 2026, EVJ | 10.1002/evj.70347 | Reino Unido / Hong Kong | en | PSI | AGREGADOR | — |
| CCL3:CCL5, JAVMA 02/10/2026 | [NV] (Paulick Report) | EE. UU. | en | PSI | PRENSA | — (no predictivo) |
| HISA, 2.º trimestre 2026 | [NV] | EE. UU. | en | PSI | OFICIAL | 1,01/1.000 salidas |
| ter Woort et al. 2023, EVJ 55:336 | 10.1111/evj.13565 · pmc.ncbi.nlm.nih.gov/articles/PMC10078706 | Francia / Australia | en | 41 PSI + trotones + salto | TEXTO_COMPLETO | κ 0,97; artefacto 0,25 % |
| Navas de Solis et al. 2026, EVJ | 10.1002/evj.70166 · wevaonline.org (PDF) | EE. UU. / Australia | en | PSI | TEXTO_COMPLETO | arritmias en muerte súbita (sin controles) |
| Trachsel et al. 2010, EVJ Suppl 38:208 | 10.1111/j.2042-3306.2010.00172.x · madbarn | Suiza | en | warmblood [I-raza] | AGREGADOR | concordancia 0–20 % en ejercicio |
| Van Steenkiste et al. 2020, Sci Rep 10:186 | 10.1038/s41598-019-57025-2 | Bélgica | en | [NV] | TEXTO_COMPLETO | QRS S 98 %, VPP 99,1 % |
| Parsons, Pfau, Ferrari & Wilson 2008, JEB 211:945 | 10.1242/jeb.006692 | Reino Unido | en | PSI (National Hunt) | TEXTO_COMPLETO | IMU ±10 g a 250 Hz |
| Verkade, Back & Birch 2020, EVJ 52:320 | 10.1111/evj.13169 · discovery-pp.ucl.ac.uk | NL / BE / UK | en | warmblood, frisón, PSI | TEXTO_COMPLETO | módulo del TFDS por raza |
| Beaumont et al. 2025, AJVR 86(8) | 10.2460/ajvr.24.09.0249 · madbarn | Francia | en | trotón francés [I-raza] | RESUMEN | CSA ≥ +10 % en 2 meses |
| Hamlin, Shearman & Hopkins 2002, EVJ 34:383 | 10.2746/042516402776249146 · madbarn | Nueva Zelanda | en | trotón [I-raza] | RESUMEN | sobrecarga: −6,9 % velocidad pico |
| Cilliers 2009, tesis, Univ. Pretoria | repository.up.ac.za | Sudáfrica | en | PSI | TEXTO_COMPLETO (parcial) | 0,53/1.000 salidas; < 1 semana entre carreras |
| Spargo et al. 2019, JSAVA 90:a1640 | repository.up.ac.za | Sudáfrica | en | PSI | RESUMEN | 0,6/1.000 salidas |
| Morley et al. 2015 (HPIE) | repository.up.ac.za 2263/45416 | Sudáfrica | en | PSI | TEXTO_COMPLETO | HPIE 68 % |
| Perkins 2005, tesis, Massey | mro.massey.ac.nz | Nueva Zelanda | en | PSI | TEXTO_COMPLETO (parcial) | 17 d entre salidas; 68 d a la 1.ª salida |
| Legg et al. 2021, Animals | pmc.ncbi.nlm.nih.gov/articles/PMC8532836 | Nueva Zelanda | en | PSI | TEXTO_COMPLETO | descanso 161 d; preparación 64 d |
| Bolwell et al. 2017, Animals 7:62 | mdpi.com/2076-2615/7/8/62 | Nueva Zelanda | en | PSI | RESUMEN | 0,72/1.000 salidas |
| Sun 2016, MPhil, Univ. Queensland | core.ac.uk/download/83972568.pdf | Hong Kong | en | PSI | TEXTO_COMPLETO (parcial) | 0,6/1.000 salidas |
| Johnston et al. 2020, EVJ | 10.1111/evj.13324 · pure.ed.ac.uk | Hong Kong | en | PSI | TEXTO_COMPLETO | 1,7 % fractura por estrés |

## Resultado de la auditoría
- 20 fuentes auditadas; **14 mejoradas** (10 a TEXTO_COMPLETO, 1 a CONGRESO, 1 a resumen de repositorio institucional, 2 de `SIN_AUDITAR` a RESUMEN/AGREGADOR) y 6 confirmadas sin mejora de acceso.
- **Cifras corregidas o reinterpretadas:** método de V200 de Poinsard (cruce, no regresión); población de Pfau 2024 (outriders, no PSI de carreras); HR 1,80 de Morrice-West 2025 (carrera completa) y categoría media como referencia; Morrice-West 2021 sin km/semana; Verkade 2020 es mecánico y no da OR por raza; Parsons 2008 lleva a Ferrari M como coautor; Ter Woort 2023 publica κ y no sensibilidad/especificidad; errata 5/29 = 17,2 % en Kalisiak (no afectaba a nuestras cifras). Ninguna corrección cambia un umbral implementado.
- **Confirmadas:** ICC de Poinsard (V200, V150, coste B1, recuperación), SEM de recuperación 9,4 lpm (pasa de [I] a [E]), curvas de Martig, cifras de Kalisiak, Frick, Gramkow & Evans, Carrier, Lee.
- **Siguen bloqueadas:** Verheyen 2006 (OR), Morrice-West 2025 y Martig 2013 (texto completo), tabla S2 de Poinsard, Kobayashi 2000 original, Hamlin 2002 (% de V200), Beaumont 2025 (texto completo) (cola).
- Vías probadas: editor (MDPI, PAN, ScienceDirect, Wiley), PMC (reCAPTCHA), Europe PMC/OpenAlex/Unpaywall/Semantic Scholar (sin red desde la shell; sin URL en búsquedas), Bristol Pure, RVC Worktribe, minerva-access, BORIS, ISC, ResearchGate (error), UC Davis VORL, eScholarship, J-STAGE (PDF denegado), DergiPark, SciELO, Redalyc, SEDICI, DUMAS (antibots, no esquivado).

## Cobertura por regiones, idiomas y razas
- **Regiones:** Europa (Francia, Polonia, Reino Unido, Suiza, Italia, Turquía); Asia (Japón: J-STAGE/CiNii; Corea: KCI/koreascience, tesis de Jeju; Hong Kong: ICRAV/HKJC); Golfo (EAU, Qatar, Arabia Saudí, Omán, Arab Journals Platform: **cero estudios** de FC/V200 en árabes de llano; solo raid); América (EE. UU., Canadá, Brasil, Argentina, Uruguay, Chile, Perú, México, Colombia, Venezuela); Oceanía (Australia: Victoria y Tasmania; Nueva Zelanda: Massey); África (Sudáfrica: Pretoria, Stellenbosch, JSAVA; Argelia; Marruecos, Egipto, Kenia, Zimbabue y Mauricio sin datos); Sudeste asiático (Singapur, Malasia: solo prensa o casuística).
- **Idiomas:** español, inglés, francés, polaco, turco, portugués, japonés, coreano, árabe, italiano, afrikáans.
- **Razas:** PSI; árabe de carreras de llano (Polonia, Turquía, Brasil); angloárabe (Italia) [I-raza]; trotón francés (Poinsard, Beaumont) y Standardbred (Hamlin) [I-raza]; warmblood y frisón (Trachsel, Verkade) solo como método; árabe de raid y sedentario (descartados como umbral).

## Resumen
La auditoría mejora 14 de 20 fuentes y corrige siete descripciones, la más relevante para el motor: la V200 de Poinsard 2026 se calcula por **primer cruce de 200 lpm mantenido 10 s**, no por regresión, de modo que su ICC (0,50) no se puede trasladar sin más a la V200 por regresión de AVO (propuesta MV1). La FCmax de árabes de llano de 3 años en galope de prueba es ≥ 211–212 lpm (Polonia, texto completo), en línea con los 213–214 lpm de PSI en Japón y Corea (propuesta FM1). Los textos de ECG confirman que la lectura de arritmias en pleno galope es poco fiable y que la recuperación es la ventana útil (propuesta EC1). África, Nueva Zelanda y Hong Kong aportan incidencias y estructura de preparaciones, pero ninguna carga de entrenamiento con FC. No existe todavía un error típico publicado de V200 en PSI ni en árabes, por lo que VT1 sigue «no validado». Todo es documentación y versiones: **probado en local** (pruebas del motor), **no verificado con caballos reales**.
