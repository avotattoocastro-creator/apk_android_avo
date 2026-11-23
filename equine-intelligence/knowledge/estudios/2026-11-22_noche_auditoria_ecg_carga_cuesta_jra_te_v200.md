# Investigación nocturna 22/11/2026: auditoría de 12 fuentes (ECG, calor, tendón, carga y cinética) y tres temas nuevos

Los tres temas nuevos son:
- el error típico (TE) de la V200 en varias razas;
- la carga y la FC de campo en Asia, con la cuesta (坂路) de la JRA;
- la carga y la FC en América, Oceanía y África.

**Versiones:** KB-1 pasa de 1.27.0 a 1.28.0 y el motor de 2.0.0-dev29 a 2.0.0-dev30. Solo cambian los números de versión; la lógica del motor es la misma.

**Alcance:** PSI y árabes de carreras en **llano** (no raid). Sesión desatendida en la nube, de 04:08 a 05:45 (hora de Madrid).

**Etiquetas:**
- [E]: texto completo leído. Es una extracción hecha por WebFetch, no una copia literal.
- [E-r]: solo el resumen.
- [I]: inferencia nuestra.
- [I-raza]: dato trasladado desde otra raza.
- [NV]: sin verificar.

## Decisiones tomadas sin supervisión

1. **Rama.** No había PR de la KB abiertos: el único PR abierto es el #119, de la pasarela LTE. La rama `claude/kb-noche-2026-11-22` sale de `develop` (`daa2bb7`).
2. **Herramientas.** La shell no tiene salida a Internet. Todo se leyó con WebSearch y WebFetch, que trabajaron en cinco subagentes en paralelo:
   - dos de auditoría;
   - uno de TE de V200 en varias razas;
   - uno de Asia y el Golfo;
   - uno de América, Oceanía y África.
   PubMed y PMC devolvieron captcha a menudo. Wiley, journals.physiology.org y los PDF de J-STAGE dieron error o estaban bloqueados por robots. No se esquivó ningún bloqueo.
3. **Fuente excluida.** Esta noche se volvió a encontrar la cifra de Kobayashi (31 pares, r 0,88) en el mismo capítulo de libro alojado en veteriankey, un sitio de legalidad dudosa. Se mantiene la decisión del 21/11: **no se usa** y el original sigue en cola.
4. **Ningún pendiente del motor se implementa.** El TE de V200 de PSI o árabe sigue sin publicarse en un texto completo legal. Los datos de pendiente de la JRA son informes técnicos institucionales sin revisión por pares y con n de 4–5. Las reglas nuevas (PD1, TE2, RC1, FW1) quedan **PROPUESTA [I]**.
5. **Versiones.** Se suben KB-1 y el motor sin tocar la lógica, como en las noches anteriores de solo documentación. Las fixtures se regeneran solo por la cadena de versión.
6. **Datos de otras razas.** Los datos de trotones, de árabes que no son de carreras y de caballos de deporte llevan `raza_fuente` y la etiqueta [I-raza]. Ninguno pasa a umbral del motor.

---

## 1. Auditoría de fuentes (12 fuentes; 9 mejoradas)

| Fuente | Antes | Ahora | Resultado |
|---|---|---|---|
| ONDER_2022 | SIN_AUDITAR | **TEXTO_COMPLETO** (mdpi.com) | cifras confirmadas; superficie «sintética» ambigua; estación y edad |
| REEF_2014 | SIN_AUDITAR | **TEXTO_COMPLETO** (PMC4895474) | sin umbral numérico de prematuros; criterios de arritmia compleja |
| MARR_2020 | SIN_AUDITAR | **TEXTO_COMPLETO** (core.ac.uk) | **corrección:** son alteraciones del ritmo, no «causas» de bajo rendimiento; prevalencias por fase |
| IKEDA_2019 | RESUMEN | **TEXTO_COMPLETO** (PMC6920055) | OR confirmados; **solo univariables**, sin modelo multivariable |
| NOMURA_2019_GOLPE_CALOR | RESUMEN | **TEXTO_COMPLETO** (PMC6606451) | cifras confirmadas; **el WBGT 28–33 °C es una norma externa**, no un resultado del estudio |
| MORRICE_WEST_2020_PRACTICAS | SIN_AUDITAR | **TEXTO_COMPLETO** (manuscrito aceptado, minerva-access) | trabajos rápidos por semana y distancias por mes; P1 queda confirmada |
| GEORGOPOULOS_PARKIN_2017 | SIN_AUDITAR | **TEXTO_COMPLETO** (manuscrito aceptado, eprints Glasgow) | **corrección de población:** EE. UU. y Canadá (EID); OR por ventana de actividad |
| MUKAI_2007_JES | RESUMEN | RESUMEN (J-STAGE) | cifras confirmadas; el lactato se midió 10 min después de la carrera; FC del medio galope y de los cajones |
| YILDIRIM_2025 | RESUMEN | RESUMEN (+ TJVR hermano en texto completo) | precisiones por raza: **pico de PSI a 2–3 años**; fin de carrera 66,3 % en PSI |
| LANGSETMO_1997 | SIN_AUDITAR | RESUMEN | τ 10,0 y 20,7 s confirmados; retraso de 18,9 y 20,3 s |
| EVANS_1993 | SIN_AUDITAR | RESUMEN | **corrección de etiqueta:** la r −0,565 es de una prueba **en cinta**, según el resumen [E-r] |
| VERMEULEN_EVANS_2006 | RESUMEN | RESUMEN | ≤ 2 % confirmado; sigue sin TE; se cita como 2006 (publicado en 2007) |

### 1.1 Önder et al. 2022 (Animals 12:2630): árabes de carreras en Turquía [E]

- **Cita:** Önder H, Şen U, Piwczyński D, Kolenda M, Drewka M, Abacı SH, Takma Ç, doi 10.3390/ani12192630.
- **Datos:** Jockey Club de Turquía, 2005–2016. 233.491 registros de velocidad; 13.764 caballos antes de la depuración y 12.707 después.
- **Velocidad por superficie:** 13,454 m/s (arena), 14,217 m/s («sintética») y 14,344 m/s (hierba). Las tres cifras quedan **confirmadas**.
- **Matiz:** el artículo llama a esa superficie «synthetic sand» en Resultados y «artificial grass» en Métodos. En la KB queda como «sintética (definición ambigua)».
- **Otros factores:**
  - Estación significativa (p 0,029), pero con diferencias de ≤ 0,02 m/s: 13,819–13,838 m/s.
  - Edad no significativa (p 0,160).
  - Heredabilidad de 0,294 ± 0,075 con el modelo L(2,2).
- **Parámetro:** `v_carrera_arabe_m_s` no cambia. Es una media de población en la que la distancia va mezclada.

### 1.2 Reef et al. 2014 (J Vet Intern Med 28:749–761): consenso ACVIM/ECEIM [E]

- **Cita:** doi 10.1111/jvim.12340.
- **Normal en reposo y justo después del ejercicio:**
  - La arritmia sinusal, el bloqueo AV de 2.º grado y el bloqueo sinoauricular son ritmos vagales. El bloqueo AV de 2.º grado debe desaparecer con el ejercicio.
  - Los CVP monomorfos ocasionales que desaparecen con el ejercicio, o que solo aparecen justo después, no suelen causar bajo rendimiento.
- **Arritmia ventricular compleja:** frecuencia > 120 lpm, multiformidad, acoplamiento corto, R sobre T o ≥ 3 CVP seguidos.
- **FA persistente:** cardiovertir o retirar al caballo si la FC media máxima pasa de 220 lpm en ejercicio máximo sostenido.
- **Recuento:** **no hay ningún umbral numérico** de prematuros en ejercicio o en recuperación. Esto confirma la nota de A11 («ninguna fuente fija un número aceptable»).
- **ECG en ejercicio:** a una intensidad igual o algo superior al trabajo habitual. No debe hacerse con taquicardia ventricular, arritmia compleja o insuficiencia cardíaca.
- **Consecuencia [I]:** la regla EC1 («revisar», nunca diagnóstico) y los niveles VIGILAR de A11 son coherentes con el consenso. El criterio de «compleja» de A11 coincide con Reef en los tripletes y las rachas.

### 1.3 Marr et al. 2020 (Equine Vet J, doi 10.1111/evj.13354): PSI con bajo rendimiento, Reino Unido e Irlanda [E]

- **Cita:** Marr CM, Franklin S, Garrod G, Wylie C, Smith L, Dukes-McEwan J, Bright J, Allen K. Volumen y páginas [NV].
- **Población:** 245 PSI con bajo rendimiento. 87 (35,5 %) no tenían ritmos ectópicos.
- **Despolarizaciones prematuras aisladas:** 110 caballos. El resumen da el 44,9 % y Resultados el 43,4 %, una incoherencia del propio artículo.
- **Ritmos complejos:** 48 caballos (19,6 %).
- **Por fase:**
  - Calentamiento: 8,2 %.
  - Galope: 24,9 %.
  - Recuperación: 50,6 %, con el 70,9 % de los aislados y el 93,8 % de los complejos. No hubo rachas en galope.
- **OR multivariables:**
  - Obstrucción de vías altas: 2,26 (1,16–4,39).
  - Prueba en cinta: 2,63.
  - Ritmo alterado en galope × cinta: 3,47.
  - Complejo × National Hunt: 2,77.
- **Carrera posterior:** el 82 % volvió a correr. El ritmo no se asoció con volver a correr.
- **CORRECCIÓN:** la fuente da porcentajes de **alteraciones del ritmo**, no de «causas» de bajo rendimiento. El 50,6 % de A11 queda **confirmado**.

### 1.4 Ikeda et al. 2019 (J Equine Sci 30:93–98): TFDS en Oi, Japón [E]

- **Diseño:** 292 casos y 584 controles, 2011–2015, carreras regionales de la TCK.
- **OR univariables, todos confirmados:**
  - Macho frente a hembra: 1,35 (1,00–1,81).
  - Castrado: 3,09 (1,40–6,84).
  - Pista «sloppy»: 1,69 (1,14–2,50).
  - Menos de 1.300 m: 1,45.
  - 470 kg o más: 1,55.
  - Pérdida de 5 kg o más: 1,59.
  - Menos de 4.000 m en las 3 últimas carreras: 1,40.
  - Menos de 8.000 m en las 6 últimas: 1,47.
  - 90 días o más sin correr: 1,75.
  - Llegar 10.º o peor: 2,50.
- **CORRECCIÓN (aclaración):** **no hay modelo multivariable.** Los autores lo descartan por el tamaño de la muestra. La KB ya los marcaba como univariables y «no usar como pesos», así que esto se refuerza.
- **Superficie:** «PSI en arena» es nuestra inferencia [I]. Oi es una pista de arena, pero el texto leído no lo dice.

### 1.5 Nomura et al. 2019 (J Equine Sci 30:17–23): golpe de calor en la JRA [E]

- **Cifras confirmadas:** 975.247 salidas y 387 casos (0,040 %). De mayo a septiembre, 352 casos en 409.908 salidas (0,086 %); el resto del año, 0,006 %.
- **Tendencia:** 0,080 % en 2015–2018 frente a 0,030 % en 1999–2014.
- **Máximo mensual:** 0,495 % (tabla 1). El resumen dice 0,459 %, una incoherencia del artículo; se usa la tabla.
- **WBGT medida en julio y agosto:** máximos diarios de 30,8 a 32,9 °C, con el 65–95 % del tiempo entre 28 y 33 °C.
- **CORRECCIÓN:** la franja de 28–33 °C de «riesgo moderado a alto» **es de normas australianas citadas en el artículo**. El estudio **no** relaciona la WBGT con la incidencia. El corte `no_comparable_WBGT_C` = 28 sigue siendo una decisión nuestra [I], basada en una norma externa citada [E].

### 1.6 Morrice-West et al. 2020 (Equine Vet J, doi 10.1111/evj.13156): prácticas en Victoria, Australia [E]

- **Fuente leída:** manuscrito aceptado EVJ-GA-18-199.R3 (minerva-access). Volumen y páginas [NV].
- **Población:** 66 de 889 entrenadores y 1.720 caballos.
- **Trabajos rápidos por semana:** 1,7 (IC 1,5–1,8) a los 2 años y 2,0 (1,8–2,2) en mayores. Por clúster: 1,43, 1,98, 2,11 y 2,8.
- **Distancia rápida (≥ 13,3 m/s) por mes en caballos en forma:** mediana de 8.000 m (RIC 6.400–12.000).
  - Por edad: 6.400 m a los 2 años y 9.600 m de 3 a 5 años.
  - Por tipo de corredor: velocistas 8.000 m y fondistas 12.800 m.
- **Trabajo lento:** 60.000 m al mes a los 2 años y 73.200 m en adultos (n = 10 entrenadores). Nuestra conversión da unos 14–17 km por semana [I].
- **Preparación hasta el primer trial:** 10,5 semanas a los 2 años (4,6 lentas y 5,7 de galope) y 9,5 semanas a los 3 años o más.
- **Calendario:** 2,3 semanas entre salidas. Descansos: 2,1 al año de 6,6 semanas (2 años) y 1,9 de 6,3 semanas (adultos).
- **Consecuencia:**
  - **P1** (1–2 rápidos por semana a los 2 años y 2–3 en maduros) y **P6** (2 o más descansos al año de unas 6 semanas) pasan de [E-r] a **[E]**.
  - P3 (17–21 días entre carreras) es coherente con las 2,3 semanas.
  - Incongruencia del artículo: la suma de programas por clúster da 389, no 379.

### 1.7 Georgopoulos & Parkin 2017 (Prev Vet Med 139:99–104) [E]

- **CORRECCIÓN de población:** **EE. UU. y Canadá**, con datos de la Equine Injury Database del Jockey Club. 89 hipódromos, 2009–2014, 2.201.152 salidas en carrera y 4.558 fracturas (unas 2 por cada 1.000 salidas).
- **OR de superficie:** arena frente a sintética 1,33 (1,20–1,47); césped frente a sintética 1,28.
- **Otros OR:** lesiones previas 1,35; semental 1,47; cada mes desde la última salida 1,20 (1,17–1,24).
- **Modelo de carga** (caballos con 6 meses o más de actividad; OR por cada salida, contando carreras y workouts):

  | Ventana | OR (IC) |
  |---|---|
  | 0–30 días | 0,71 (0,68–0,75) |
  | 30–60 días | 0,95 |
  | 60–90 días | 1,06 (1,02–1,10) |
  | 90–180 días | 1,07 (1,05–1,09) |

  La actividad reciente protege y la acumulada de hace 2 a 6 meses aumenta el riesgo.
- **Consecuencia [I]:** apoya la lógica de P4/P7 (las semanas tras un hueco son de riesgo) y el uso de la carga acumulada a 60–180 días de A6C. No cambia ningún umbral.

### 1.8 Mukai et al. 2007 (J Equine Sci 18:153–160): FC en carrera en la JRA [E-r]

- **Cifras confirmadas del resumen:** 23 PSI, 1.200 m, FC pico 213,6 ± 1,7 lpm, 95 % del pico en 12,4 ± 1,8 s, 15,9 m/s.
- **Lactato:** 22,5 ± 0,6 mmol/L, medido **10 minutos después de la carrera** (detalle nuevo).
- **Cifras nuevas del resumen:** 194,0 ± 2,0 lpm en el medio galope hacia los cajones (≈ 91 % del pico) y 171,4 ± 5,3 lpm en los cajones. La FC sube con el jinete y en el paso subterráneo sin que aumente el esfuerzo.
- **Vías probadas:** el PDF de J-STAGE está bloqueado por robots y ResearchGate dio error. Sigue en RESUMEN.

### 1.9 Yıldırım, Karaarslan & Erkan 2025 (Equine Vet J, doi 10.1111/evj.14457) [E-r]

- **Hipódromo:** Şirinyer (Esmirna). El resumen no menciona otras pistas.
- **Cifras precisadas:**
  - El 92,7 % de lesiones en el miembro anterior en árabes (91,3 % en PSI) es **en carrera**.
  - **Pico de edad:** árabes a 3–4 años y **PSI a 2–3 años**.
  - Fin de carrera: 46,4 % en árabes y **66,3 % en PSI**.
- **Artículo hermano en texto completo** (Turk J Vet Res 9:33–40, DergiPark, [E], `YILDIRIM_KARAARSLAN_2025`): usa los mismos registros, con 337 lesiones en PSI y 216 en árabes. Da el fin de carrera como 57,27 % en PSI y 47,22 % en árabes.
- **Discrepancia entre las dos revistas** para el fin de carrera en PSI (66,3 % frente a 57,27 %). Puede deberse a una definición distinta [NV]. En la KB se mantienen las dos cifras, cada una con su revista.
- **Pendiente [NV]:** recuentos por superficie y por localización.

### 1.10 Langsetmo 1997, Evans 1993 y Vermeulen & Evans 2006 (solo resumen)

- **Langsetmo et al. 1997** (J Appl Physiol 83:1235–1241, Kansas State). τ1 del VO₂ de 10,0 ± 0,9 s por debajo del umbral de lactato (de 3 a 7 m/s) y de 20,7 ± 3,4 s por encima (de 3 a 12,3 m/s). Retraso de 18,9 y 20,3 s. Componente lento en 4 de 5 caballos. La raza no consta [NV]. `fc_retraso_s` queda confirmado [E-r].
- **Evans, Harris & Snow 1993** (EVJ 25:441–445):
  - Prueba de campo de 800 m con 26 PSI y prueba en cinta a 10 m/s y 5° con 14 PSI.
  - FC a los 4 min de la prueba en cinta frente al Timeform: r −0,565. Lactato a los 2–5 min: r −0,68.
  - La prueba de campo no se correlacionó con el rendimiento.
  - **CORRECCIÓN de etiqueta:** `recuperacion_fc_ventanas_min` citaba esta fuente como [E]; es [E-r], y en cinta. Las ventanas no cambian (solo tendencia del propio caballo).
- **Vermeulen & Evans 2006** (EVJ Suppl 36:113–117, publicado en línea en 2007). Diferencias medias ≤ 2 % en VHRmax, V200 y FCmax, confirmadas. Sigue sin TE. Stance Equitec cita un resumen de congreso relacionado (Evans, Gramkow & Vermeulen 2006, Proc Aust Equine Sci Symp): VHRmax frente al premio por salida, r 0,41, n 25 [E-r, CONGRESO].

---

## 2. Tema nuevo A: error típico (TE) de la V200 en varias razas (para VT1 / `v200_te_por_defecto`)

**Conclusión:** sigue **sin existir** un TE o CV de V200 publicado en texto completo legal para PSI o árabe de llano [NV]. El 3 % por defecto **se mantiene marcado como «no validado»**.

| Raza | Fuente | Método | Repetibilidad | Etiqueta |
|---|---|---|---|---|
| PSI (Australia) | Vermeulen & Evans 2006 | campo, GPS + Polar, medias de 5 s, regresión | diferencias medias ≤ 2 % (sesgo, no TE) | [E-r] |
| PSI (Australia) | Davie, Beavers & Denham 2026, Animals 16:2187 | cinta a 6°, 64 caballos, 823 galopes | ICC de la FC de galope a velocidad fija 0,756; recuperación 0,42 / 0,50 / 0,60 / 0,57 (30 / 60 / 90 / 120 s) | [E-r] (ya en la KB) |
| Trotón francés | Dubreucq, Chatard, Couroucé & Auvinet 1995, EVJ Suppl 18:108 | campo, 3 escalones de 3 min, 11 caballos con retest a 1 semana | Spearman > 0,79 para V200, V4, V2 y HR2; sin CV | [E-r], [I-raza] |
| Trotón francés | Couroucé et al. 1999, EVJ Suppl 30:528 | 5 caballos, pista de entrenamiento, hipódromo y cinta | sin diferencias entre pistas; la cinta da FC y lactato más bajos | [E-r], [I-raza] |
| Trotón francés | Poinsard 2026 | campo, primer cruce ≥ 10 s | ICC de V200 0,50 (ya [E] el 21/11); tabla S2 [NV] | [E], [I-raza] |
| Trotón (Australia) | Evans & Rose 1988, EVJ 20:94 | cinta, 6 caballos, 3 pruebas separadas ≥ 24 h | CV del VO₂max 1,4–9,0 %; FCmax ≤ 2,7 %; V200 «menos variable» sin cifra; VHRmax > 10 % | [E-r], [I-raza] |
| Mixto (EE. UU.) | Seeherman & Morris 1990, EVJ Suppl 9:20 | cinta, 6 caballos, 2 repeticiones | variabilidad < 5 % en la regresión FC–velocidad y en la FC pico | [E-r] |
| Árabe (Italia) | Piccione 2004 | campo, sin retest | DE entre caballos ≈ 4,3 % (610 ± 26 m/min) | [E] (ya en la KB) |

**Propuesta TE2 [I] (sin implementar):**
- Mantener el 3 % solo cuando coincidan la pista, la superficie, el jinete y la franja de temperatura (TC1), y la prueba tenga mesetas estables.
- Con sesiones de entrenamiento no estandarizadas, usar un **4–5 % por defecto**.
- Pasar al **TE propio** en cuanto haya 3 o más pruebas en bloque (RB1).

**Base de la propuesta:**
- Seeherman da < 5 % en cinta [E-r].
- Los ICC «moderados» de Poinsard (0,50) y de Davie (0,62–0,81 por galope) apuntan a más dispersión en condiciones reales [I-raza].

No se implementa porque ninguna de estas cifras es un TE de PSI o árabe en texto completo.

---

## 3. Tema nuevo B: Asia y el Golfo, con carga y FC de campo y la cuesta (坂路) de la JRA

### 3.1 Japón

**Artículos con revisión por pares:**
- **Kubo, Takagi, Murakami & Kai 1984** (Bull Equine Res Inst 21:39–45, japonés, doi 10.11535/jes1977.1984.39) [E-r]:
  - 6 machos PSI de 2 años.
  - FC máxima 233 ± 7 lpm, alcanzada a 700 m/min sostenidos.
  - Lactato máximo 24,5 ± 3,4 mmol/L en 1.600 m.
- **Yamanobe, Hiraga & Kubo 1993** (Bull Equine Res Inst 30:5–8, doi 10.11535/jes1977.1993.5) [E-r]:
  - 5 PSI de 3 años, 6 días por semana durante unos 4 meses.
  - FC durante un calentamiento fijo de 1.250 m a unos 400 m/min (6,7 m/s): bajó hasta el día 60 y después se estabilizó.
  - La V200 subió en paralelo. Correlación de |r| 0,765 (p < 0,001), negativa según la descripción.
  - Base de la propuesta **FW1**.
- **Hiraga, Kai, Kubo & Erickson 1995** (J Equine Sci 6:1–6, doi 10.1294/jes.6.1) [E-r]:
  - 11 PSI de 2 años, canter lento durante 8 semanas.
  - 3.200 a 4.800 m por día frente a 800 m por día: sin diferencias en VO₂peak (156 frente a 153 ml/kg/min), FC pico (224 frente a 227) ni lactato pico.
  - Más volumen lento no mejoró la capacidad aeróbica.
- **Hiraga et al. 1995** (J Equine Sci 6:55–60, doi 10.1294/jes.6.55) [E-r]: cinta al 0, 3, 6 y 10 % con 5 PSI de 2 años. La FC y el gasto cardíaco suben con la pendiente; el volumen sistólico no cambia.
- **Mukai et al. 2003** (J Equine Sci 14:93–96, doi 10.1294/jes.14.93) [E-r]: 20 PSI en canter submáximo en una pista de arena de 500 m. El sexo influye en la FC (p < 0,05); los caballos de clase «open» tienden a una FC más baja (p 0,11). Valores en lpm [NV].
- **Mukai et al. 2023** (Front Vet Sci 10:1241266) [E], cinta, 8 PSI. Lactato al final de cada tipo de sesión:

  | Sesión | Lactato (mmol/L) |
  |---|---|
  | Continua al 70 % del VO₂max | 8,5 ± 1,6 |
  | Intervalos de 6 × 30 s al 100 % | 22,0 ± 3,3 |
  | Sprints de 6 × 15 s al 120 % | 24,3 ± 2,3 |

  La temperatura en la arteria pulmonar llegó a 41,3 °C con los intervalos.
- **Mukai et al. 2026** (Physiol Rep 14:e70785) [E-r]: 7 PSI, 6 semanas. Los intervalos (HIIT) frente al trabajo continuo (MICT):
  - velocidad a FCmax: +15 % frente a +4,3 %;
  - velocidad al VO₂max: +9,8 % frente a +2,4 %;
  - VO₂max: unos +13 % en ambos.
- **Takahashi, Nomura, Mukai & Mizobe, ICRAV 2026** (resumen 129358) [E-r, CONGRESO]: cinco temporadas de la JRA. Lesión catastrófica 0,71 por cada 1.000 salidas y lesión no catastrófica 14,1 por cada 1.000. Los recuentos del resumen no cuadran.

**Informes técnicos institucionales de la JRA** (Hidaka y BTC; [E] leídos en japonés; **sin revisión por pares**, acceso OFICIAL):
- **Haneda, informe n.º 115 (2014), «坂路調教が心肺機能に与える影響»**, reeditado en el blog de la JRA en 2019:
  - Cinta (Hiraga 1995, n 5): la FC sube unos **4–6 lpm por cada 1 % de pendiente** a partir del canter. Cada 1 % acorta la V200 en 0,9–1,4 s por furlong.
  - Campo (n 4): V200 de 17,4 s por furlong en arena (≈ 11,5 m/s) frente a 20,2 s por furlong en la cuesta cubierta de viruta (≈ 9,9 m/s) [I: conversión].
  - Base de la propuesta **PD1**.
- **Haneda, informe n.º 141 (2016).** VLa4 (OBLA) tras galope en cuesta:
  - BTC: 11,4 m/s (52 potros).
  - Miho: 11,9 m/s antes del cambio de rastra del piso y **10,2 m/s después** (167 registros).
  - El estado del piso mueve la VLa4 en 1,7 m/s.
- **Haneda, informe n.º 134 (2015), «育成馬の体力評価法».** Define **THR100** (tiempo hasta que la FC baja de 100 lpm): ≤ 200 s indica una carga cardiorrespiratoria relativamente baja y > 200 s, una carga alta. Advierte que el GPS no es fiable en pista cubierta. Base de la propuesta **RC1**.
- **Tominari (blog JRA, 2021):** 5 potros en una cuesta de 1.000 m. Lactato de 5,7–12,3 mmol/L a unos 18 s por furlong y de 14,7–15,1 mmol/L a 15,5 s por furlong.
- **Blog JRA Hidaka (2010):** 1 potra, mismo ritmo en llano y en cuesta.
  - Llano: FC máxima 209 lpm y 70 s hasta bajar de 100 lpm.
  - Cuesta: FC máxima 227 lpm y 120 s hasta bajar de 100 lpm.
  - Es un caso aislado, solo ilustrativo.
- **Asano (clínica de Miho), BTC News n.º 85 (año [NV]):** 298 observaciones en granjas de descanso frente a 247 en el centro de entrenamiento.
  - V200: **11,2 frente a 11,9 m/s** (p < 0,05).
  - Velocidad máxima: 14,0 frente a 16,5 m/s.
  - Galope de 1.345 frente a 1.367 m.
  - Es la **primera referencia poblacional de V200 de campo en PSI en activo de la JRA** que tenemos [E, OFICIAL].
- **Shiose (JRA), BTC News n.º 80:** FC de 210–230 lpm en el trabajo rápido (追い切り). Un caballo de ejemplo tiene V200 de 10–12 m/s y VHRmax de 14–16 m/s. Recomienda VHRmax para comparar caballos. No da repetibilidad.
- **Fichas oficiales de la JRA:**
  - Cuesta de Ritto: 1.085 m y 32 m de desnivel, con tramos del 2,0 / 3,5 / 4,5 / 1,25 %.
  - Cuesta de Miho: 1.200 m y 33 m de desnivel.
  - Sirven como perfil de referencia para PD1.

### 3.2 Corea y Hong Kong

**Corea.** Choi & Parkin 2025 (TFDS) ya estaba en la KB [E]. La novedad es **Choi & Parkin 2026, JAVMA** (doi 10.2460/javma.26.04.0244) [E-r]: 138 casos y 580 controles de fractura de sesamoideos proximales, 2020–2025.
- Carrera o ensayo frente a entrenamiento: OR 17,41.
- 6 o más días de galope en la ventana de 120 a 180 días: OR 3,73 (1,50–9,27).
- 37 o más días de entrenamiento en pista en 180 días: OR 2,36.
- Primavera y verano: OR 1,74.

Es coherente con Georgopoulos 2017: la carga acumulada de hace 4 a 6 meses aumenta el riesgo [I].

**Hong Kong:**
- **Sun et al. 2019** (EVJ 51:77–82) [E-r]: 2,2 fracturas no catastróficas y 0,6 catastróficas por cada 1.000 salidas.
- **Klomp et al. 2014** (Pferdeheilkunde 30:403) [E-r]: natación en la HKJC con 52 caballos.
  - FC 178 ± 14 lpm, lactato 2,3 mmol/L.
  - Repetibilidad de la FC r 0,39 (no significativa) y ninguna relación con el rendimiento.
  - Lectura [I]: la natación es carga cardíaca moderada sin carga ósea.

### 3.3 Golfo, China, India y el Sudeste Asiático

- **Golfo:** **sin datos** de FC, lactato o carga de árabes de llano. Se buscó en árabe y en inglés: Emirates Racing Authority, Dubai Equine Hospital, Meydan, QREC y el Jockey Club de Arabia Saudí.
- **Al Mheiri 2023** (tesis MPhil, Liverpool, Dubái) [E-r]: estudio cualitativo con 5 preparadores y 3 veterinarios. No da cifras de carga.
- **China:** solo aparecen estudios del caballo Yili (no PSI).
- **India, Singapur y Malasia:** cero estudios.

---

## 4. Tema nuevo C: América, Oceanía y África (carga habitual y FC)

**Nueva Zelanda:**
- **Kingston, Soppet, Rogers & Firth 2007** (EVJ Suppl 36:106–109) [E-r, AGREGADOR]: 19 PSI de 3 años durante 4 meses.
  - La velocidad media del GPS coincide con el cronómetro; la velocidad pico del GPS es mayor.
  - La respuesta de FC al mismo trabajo es distinta en cada caballo.
  - Km por semana [NV].
- **Bolwell, Russell & Rogers 2010** (Comp Exerc Physiol 7:37) [E-r]: encuesta a 55 entrenadores. Por la tesis de Tanner 2011 (Massey) [E, cita secundaria]:
  - galope desde las semanas 7–11;
  - medio galope a 12,5–14,2 m/s;
  - 6 días por semana;
  - unas 12 semanas hasta el trial.

**Chile** (tesis de la Universidad de Chile, solo las fichas; el PDF está bloqueado por Anubis):
- **Trujillo 2012** [E-r]: 14 potros PSI en el Club Hípico de Santiago, con FC a 45 km/h y V200. Cifras [NV].
- **Bravo 2009** [E-r]: 32 PSI. La recuperación de la FC de 30 a 300 s tras la meta fue más rápida en los de buen rendimiento. La FCmax y la FC a 45 km/h no se diferenciaron.

**Colombia:** **Arias, Gaviria & Vélez 2006** (Rev CES Med Vet Zootec 1(2), hipódromo Los Comuneros) [E]: 20 PSI, prueba de 800 m.
- FCmax 241 ± 4,8 lpm.
- Recuperación: 117 lpm a los 3 min, 93 a los 5 y 67 a los 7.
- V200 de 8,4 m/s, con un protocolo submáximo que no es comparable.

**Brasil:**
- **Berkman 2015** (ya en la KB): las tablas son imágenes y sus valores siguen [NV].
- **Mello 2012** (tesis UFRRJ) [E]: escalones de 4, 6, 10 y 12 m/s en potros PSI; lactato después del ejercicio de 1,9–2,8 mmol/L.
- **Watanabe 2006** [E], ya en la KB: VLa4 de unos 8 m/s en árabes en cinta.
- **Siqueira 2024** [E], ya en la KB: plantilla semanal de árabes de llano. Se confirma.

**Argentina, Uruguay, Perú y México:** nada de FC o GPS en PSI de carreras.

**EE. UU. y Canadá:**
- **AAEP, nota de prensa del 21/04/2026** (sensores biométricos en potros de 2 años en *breezes*) [PRENSA]:
  - bandera amarilla o roja: OR 2,2 de lesión;
  - lesión previa: OR 27,9;
  - la lesión llega en una mediana del 6.º breeze.
  - Pendiente del artículo revisado.
- Mc Sweeney 2026 y Eamon 2026 ya estaban en la KB.
- **Kapusniak et al. 2026** (EVJ, doi 10.1002/evj.70205) [E-r]: 25 PSI y 25 trotones.
  - FCmax 217,8 ± 10,1 lpm con ECG textil, frente a Televet con ICC 0,995.
  - Registros sin artefactos: 76 % frente a 37 %.
  - Arritmias en 43 de 50 caballos.
  - Interesa al ECG de la cincha.

**Sudáfrica:** **Hartwigsen et al. 2026** (JSAVA 97:10–18) [E]: PSI de 3 años en Gauteng, 6 días por semana con 1 trabajo rápido semanal de 800 m en arena.

**Novedades de noviembre de 2026:** **Li, Yan & Chen**, EVJ, 15/11/2026 (PubMed 43035340) [E-r]. Es una revisión de alcance sobre sensores portátiles y aprendizaje automático para la fatiga en **caballos de deporte**. Resuelve en parte el punto 70 de la cola: es una revisión y no consta que incluya PSI o árabes de llano [NV]. Fuera de esto, el listado de MadBarn del 15/09 al 15/11/2026 no trae ningún estudio de campo nuevo con PSI o árabes de carreras.

---

## 5. Reglas propuestas (todas PROPUESTA [I], sin implementar)

- **PD1 (pendiente).**
  - Las sesiones en cuesta no son comparables con las de llano para A7/A8/A9: se comparan solo dentro del mismo perfil de pendiente.
  - Como orientación, la FC sube unos 4–6 lpm por cada 1 % a igual velocidad (JRA, informe institucional, cinta con n 5).
  - El desnivel saldría de la altitud del RTK de la espalda (PROTOTIPO), con el campo «cuesta» en la ficha de campo.
  - No se aplica ninguna corrección numérica a la V200 hasta tener una fuente revisada o datos propios.
- **TE2.** TE por defecto de V200 según las condiciones: 3 % si son iguales y 4–5 % si no son estandarizadas, hasta tener el TE propio (≥ 3 pruebas).
- **RC1.** THR100 (tiempo hasta FC < 100 lpm) solo como métrica informativa de la tendencia del propio caballo. El corte de 200 s de la JRA se muestra como referencia institucional, no como alerta.
- **FW1.** La FC media en un tramo fijo de calentamiento (velocidad estable, misma superficie y mismo perfil) sirve como sustituto diario de la tendencia de V200 (Yamanobe 1993, |r| 0,765 [E-r]). Solo como tendencia, con los criterios de comparables de TC1 y GO1.

---

## 6. Tabla de fuentes

| Cita | DOI / URL | País | Idioma | Raza | Acceso | Qué cifra sostiene |
|---|---|---|---|---|---|---|
| Önder et al. 2022, Animals 12:2630 | 10.3390/ani12192630 | Turquía | en | árabe de carreras | TEXTO_COMPLETO | velocidad por superficie 13,45 / 14,22 / 14,34 m/s |
| Reef et al. 2014, JVIM 28:749 | 10.1111/jvim.12340 | internacional | en | caballos atletas | TEXTO_COMPLETO | criterios de arritmia compleja; sin umbral de recuento |
| Marr et al. 2020, EVJ | 10.1111/evj.13354 | Reino Unido e Irlanda | en | PSI | TEXTO_COMPLETO | 50,6 % en recuperación; 19,6 % complejas |
| Ikeda et al. 2019, J Equine Sci 30:93 | 10.1294/jes.30.93 | Japón (Oi) | en | PSI | TEXTO_COMPLETO | OR univariables del TFDS |
| Nomura et al. 2019, J Equine Sci 30:17 | 10.1294/jes.30.17 | Japón (JRA) | en | PSI | TEXTO_COMPLETO | 0,040 / 0,086 %; WBGT 28–33 °C (norma externa) |
| Morrice-West et al. 2020, EVJ | 10.1111/evj.13156 | Australia | en | PSI | TEXTO_COMPLETO (manuscrito aceptado) | 1,7 / 2,0 rápidos por semana; 8.000 m al mes |
| Georgopoulos & Parkin 2017, Prev Vet Med 139:99 | 10.1016/j.prevetmed.2016.12.006 | EE. UU. y Canadá | en | PSI | TEXTO_COMPLETO (manuscrito aceptado) | OR por ventana de actividad |
| Mukai et al. 2007, J Equine Sci 18:153 | 10.1294/jes.18.153 | Japón | en | PSI | RESUMEN | FC pico 213,6; 194 en el medio galope |
| Yıldırım et al. 2025, EVJ | 10.1111/evj.14457 | Turquía | en | PSI y árabe | RESUMEN | pico de PSI a 2–3 años; fin de carrera 66,3 / 46,4 % |
| Langsetmo et al. 1997, J Appl Physiol 83:1235 | 10.1152/jappl.1997.83.4.1235 | EE. UU. | en | [NV] | RESUMEN | τ 10,0 / 20,7 s |
| Evans, Harris & Snow 1993, EVJ 25:441 | 10.1111/j.2042-3306.1993.tb02987.x | [NV] | en | PSI | RESUMEN | r −0,565 (cinta, 4 min) |
| Vermeulen & Evans 2006, EVJ Suppl 36:113 | 10.1111/j.2042-3306.2006.tb05525.x | Australia | en | PSI | RESUMEN | ≤ 2 % |
| Dubreucq et al. 1995, EVJ Suppl 18:108 | 10.1111/j.2042-3306.1995.tb04900.x | Francia | en | trotón francés | RESUMEN | Spearman > 0,79 [I-raza] |
| Couroucé et al. 1999, EVJ Suppl 30:528 | 10.1111/j.2042-3306.1999.tb05278.x | Francia | en | trotón francés | RESUMEN | igualdad entre pistas [I-raza] |
| Evans & Rose 1988, EVJ 20:94 | 10.1111/j.2042-3306.1988.tb01467.x | Australia | en | trotón | RESUMEN | CV de FCmax ≤ 2,7 % [I-raza] |
| Seeherman & Morris 1990, EVJ Suppl 9:20 | 10.1111/j.2042-3306.1990.tb04729.x | EE. UU. | en | mixto | RESUMEN | < 5 % (cinta) |
| Kubo et al. 1984, Bull Equine Res Inst 21:39 | 10.11535/jes1977.1984.39 | Japón | ja | PSI | RESUMEN | FCmax 233; lactato 24,5 |
| Yamanobe et al. 1993, Bull Equine Res Inst 30:5 | 10.11535/jes1977.1993.5 | Japón | ja | PSI | RESUMEN | FC de calentamiento frente a V200, \|r\| 0,765 |
| Hiraga et al. 1995a, J Equine Sci 6:1 | 10.1294/jes.6.1 | Japón | en | PSI | RESUMEN | volumen lento sin efecto aeróbico |
| Hiraga et al. 1995b, J Equine Sci 6:55 | 10.1294/jes.6.55 | Japón | en | PSI | RESUMEN | FC frente a pendiente (cinta) |
| Mukai et al. 2003, J Equine Sci 14:93 | 10.1294/jes.14.93 | Japón | en | PSI | RESUMEN | el sexo influye en la FC submáxima |
| Mukai et al. 2023, Front Vet Sci 10:1241266 | 10.3389/fvets.2023.1241266 | Japón | en | PSI | TEXTO_COMPLETO | lactato por tipo de sesión |
| Mukai et al. 2026, Physiol Rep 14:e70785 | 10.14814/phy2.70785 | Japón | en | PSI | RESUMEN | HIIT frente a MICT |
| Takahashi et al., ICRAV 2026, 129358 | icrav-2025.p.asnevents.com.au | Japón | en | PSI | CONGRESO | 0,71 / 14,1 por 1.000 salidas |
| Haneda, JRA, informe 115 | blog.jra.jp/shiryoushitsu/2019/11/post-e23a.html | Japón | ja | PSI | OFICIAL | 4–6 lpm por cada 1 % de pendiente |
| Haneda, JRA, informe 141 | blog.jra.jp/shiryoushitsu/2020/05/no14.html | Japón | ja | PSI | OFICIAL | VLa4 en cuesta 11,9 frente a 10,2 m/s |
| Haneda, JRA, informe 134 | blog.jra.jp/shiryoushitsu/2020/02/post-8c41.html | Japón | ja | PSI | OFICIAL | THR100 de 200 s |
| Tominari, blog JRA 2021 | blog.jra.jp/shiryoushitsu/2021/07/post-027b.html | Japón | ja | PSI | OFICIAL | lactato frente al ritmo en cuesta |
| Asano, BTC News n.º 85 | b-t-c.or.jp/img/pdf/btcn/btcn85/btcn085-02.pdf | Japón | ja | PSI | OFICIAL | V200 de 11,9 m/s en activo |
| Shiose, BTC News n.º 80 | b-t-c.or.jp/img/pdf/btcn/btcn80/btcn080-03.pdf | Japón | ja | PSI | OFICIAL | FC de 210–230 lpm en el trabajo rápido |
| Choi & Parkin 2026, JAVMA (sesamoideos) | 10.2460/javma.26.04.0244 | Corea | en | PSI | RESUMEN | OR 3,73 por galope a 120–180 días |
| Sun et al. 2019, EVJ 51:77 | 10.1111/evj.12953 | Hong Kong | en | PSI | RESUMEN | 2,2 / 0,6 por 1.000 salidas |
| Klomp et al. 2014, Pferdeheilkunde 30:403 | — | Hong Kong | en | PSI | RESUMEN | natación: FC 178, r 0,39 |
| Al Mheiri 2023, tesis, Liverpool | livrepository.liverpool.ac.uk/3170000 | EAU | en | PSI y árabe | RESUMEN | sin cifras |
| Kingston et al. 2007, EVJ Suppl 36:106 | 10.1111/j.2042-3306.2006.tb05523.x | Nueva Zelanda | en | PSI | AGREGADOR | velocidad pico del GPS mayor que la del cronómetro |
| Bolwell et al. 2010, Comp Exerc Physiol 7:37 | 10.1017/S1755254010000103 | Nueva Zelanda | en | PSI | RESUMEN | proporción de potros de 2 años en trabajo |
| Tanner 2011, tesis, Massey | mro.massey.ac.nz | Nueva Zelanda | en | PSI | TEXTO_COMPLETO (cita secundaria) | medio galope 12,5–14,2 m/s |
| Trujillo 2012, tesis, U. de Chile | repositorio.uchile.cl/handle/2250/131606 | Chile | es | PSI | RESUMEN | FC a 45 km/h (cifras [NV]) |
| Bravo 2009, tesis, U. de Chile | repositorio.uchile.cl/handle/2250/131317 | Chile | es | PSI | RESUMEN | recuperación de 30–300 s |
| Arias, Gaviria & Vélez 2006, Rev CES | redalyc.org/pdf/3214/321428499003.pdf | Colombia | es | PSI | TEXTO_COMPLETO | FCmax 241; recuperación a 3, 5 y 7 min |
| Mello 2012, tesis, UFRRJ | — | Brasil | pt | PSI | TEXTO_COMPLETO | escalones de potros |
| AAEP, nota de prensa 21/04/2026 | aaep.org | EE. UU. | en | PSI | PRENSA | OR 2,2 por bandera; 6.º breeze |
| Hartwigsen et al. 2026, JSAVA 97:10 | 10.36303/JSAVA.724 | Sudáfrica | en | PSI | TEXTO_COMPLETO | 1 rápido de 800 m por semana |
| Li, Yan & Chen 2026, EVJ (revisión) | PubMed 43035340 | China | en | caballos de deporte | RESUMEN | revisión de sensores de fatiga |

## 7. Resultado de la auditoría

- **Fuentes auditadas:** 12. Mejoran su acceso 9: siete pasan a TEXTO_COMPLETO y dos (Langsetmo 1997, Evans 1993) de SIN_AUDITAR a RESUMEN; Mukai 2007, Yıldırım 2025 y Vermeulen 2006 siguen en RESUMEN con cifras reconfirmadas.
- **Correcciones:**
  - Marr 2020: porcentajes de alteraciones del ritmo, no de causas.
  - Georgopoulos 2017: la población es de Norteamérica.
  - Nomura 2019: el WBGT es una norma externa.
  - Evans 1993: [E] pasa a [E-r], y la prueba es en cinta.
  - Ikeda 2019: sin multivariables.
  - Yıldırım 2025: pico de PSI a 2–3 años y fin de carrera de los PSI.
- **Ninguna cifra que use el motor cambia de valor.**

## 8. Cobertura

- **Regiones:**
  - Europa: Francia, Reino Unido, Irlanda, Italia y Turquía.
  - Asia: Japón (JRA y TCK), Corea, Hong Kong y China (sin datos útiles); India, Singapur y Malasia sin datos.
  - Golfo: EAU, Qatar y Arabia Saudí, sin datos de carreras de llano.
  - América: EE. UU., Canadá, Brasil, Chile y Colombia; Argentina, Uruguay, Perú y México sin datos.
  - Oceanía: Australia y Nueva Zelanda.
  - África: Sudáfrica.
- **Idiomas:** español, inglés, japonés, portugués, francés, árabe, coreano, chino, turco y polaco. En árabe, coreano, chino, turco y polaco las búsquedas no dieron resultados útiles.
- **Razas:**
  - PSI;
  - árabe de carreras (Turquía y Brasil);
  - angloárabe (Piccione, ya en la KB);
  - trotón francés, Standardbred y trotón australiano en cinta [I-raza];
  - caballos de deporte (revisión de Li 2026);
  - PSI de *chuckwagon* (ya en la KB).

## 9. Resumen

- **Auditoría:** se leyó el texto completo legal de siete fuentes que sostienen reglas (A11, P1/P6, calor y TFDS). Hay seis precisiones o correcciones y ningún valor del motor cambia.
- **TE de V200:** sigue sin cifra publicada de PSI o árabe; se propone TE2.
- **Asia:**
  - La JRA aporta la primera V200 poblacional de campo en PSI en activo (11,9 m/s), en un informe institucional.
  - Aporta el efecto de la pendiente sobre la FC (4–6 lpm por cada 1 %) y la métrica THR100. Con ellas se proponen PD1 y RC1.
  - Corea añade la ventana de 120 a 180 días para las fracturas de sesamoideos.
- **Golfo:** sigue sin datos de árabes de llano.
- **Motor:** ningún cambio de lógica. KB-1 pasa a 1.28.0 y el motor a 2.0.0-dev30.
- **Validación:** todo esto está probado en local o en CI, **no verificado con caballos reales**.
- **Fatiga ósea:** sigue sin ser una predicción de lesiones.
