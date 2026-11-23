# Investigación nocturna 23/11/2026: auditoría de 9 fuentes (estadística del motor, ECG, fiabilidad de la FC, lesiones en Sudáfrica) y dos temas nuevos

Los temas nuevos son:
- **carga de entrenamiento** a partir de la FC y del GPS (TRIMP, ACWR, monotonía, bandas de velocidad) en varias razas;
- **edad, sexo y castración** como covariables de los índices del motor (prior poblacional μ_pop de V200, VHRmax, FCmax y velocidad);
- las **fórmulas humanas de referencia** de la carga (Banister, Edwards, Foster, Williams, Impellizzeri) y las **publicaciones de octubre–noviembre de 2026**.

**Versiones:** KB-1 pasa de 1.28.0 a 1.29.0 y el motor de 2.0.0-dev30 a 2.0.0-dev31. Solo cambian los números de versión y un comentario del CUSUM en `knowledge.h`; **la lógica del motor es la misma**.

**Alcance:** PSI y árabes de carreras en **llano** (no raid). Sesión desatendida en la nube, de 04:08 a 05:45 (hora de Madrid). Nada de lo que sigue está verificado con caballos reales ni con el hardware de AVO.

**Etiquetas:**
- [E]: texto completo leído (extracción de WebFetch, no copia literal).
- [E-r]: solo el resumen o la ficha.
- [I]: inferencia nuestra.
- [I-raza]: dato trasladado desde otra raza, con justificación.
- [NV]: sin verificar.

## Decisiones tomadas sin supervisión

1. **Rama.** Había un PR de la KB abierto sin fusionar (#124, `claude/kb-noche-2026-11-22`). La rama `claude/kb-noche-2026-11-23` sale de esa rama (`91ab2c2`), como pide la tarea. Si el #124 se fusiona primero, este PR solo añade lo de hoy.
2. **Herramientas.** La shell no tiene salida a Internet (el proxy rechaza `www.ebi.ac.uk`). Todo se leyó con WebSearch y WebFetch, en cuatro subagentes: auditoría; carga (TRIMP/ACWR); edad y sexo (los tres en paralelo); y fórmulas de carga con novedades de 2026. WebFetch solo aceptó URL aparecidas en resultados de búsqueda: las API de Unpaywall, OpenAlex, Semantic Scholar y `fullTextXML` de Europe PMC **no se pudieron probar** por esa regla (no por denegación del editor). PMC devolvió reCAPTCHA siempre. No se esquivó ningún bloqueo ni se usó ningún sitio pirata.
3. **Auditoría centrada en el código del motor.** Se eligieron primero las fuentes `SIN_AUDITAR` que sostienen funciones ya IMPLEMENTADAS (`kb_robust_z`, `kb_cusum_upper`, `kb_self_starting_z`, `kb_change_threshold`, `kb_shrink_mean`) y después cuatro fuentes de parámetros de ECG, FC y lesiones que seguían por resumen.
4. **Ningún pendiente del motor se implementa.** Las correcciones de la auditoría no cambian ningún valor que use el código: los ARL del NIST difieren en una unidad de los nuestros (336 frente a 335 y 930 frente a 931, dentro del redondeo de la cadena de Markov), y el ICC corregido de Davie (0,451) está en un parámetro PENDIENTE que el código no usa. El único TRIMP/ACWR equino publicado es de caballos de **completo**, no de carreras: no se convierte en lógica del motor.
5. **Comentario del CUSUM.** Se corrige el comentario de `kb_cusum_upper` en `include/avo_eq/knowledge.h`: la tabla del NIST es del CUSUM **unilateral** (336 / 930) y los 168 / 465 bilaterales son un cálculo nuestro (≈ ARL0/2), no del NIST.
6. **Versiones.** Se suben KB-1 y el motor sin tocar la lógica, como en las noches anteriores de solo documentación. Las fixtures cambian solo por la cadena de versión.
7. **Otras razas.** Los datos de trotones, warmblood, caballos de completo, Cuarto de Milla y árabes no de carreras llevan `raza_fuente` y [I-raza]. Ninguno pasa a umbral del motor.

---

## 1. Auditoría de fuentes (9 fuentes; 8 mejoradas, 1 sigue por resumen)

### 1.1 NIST_CUSUM — NIST/SEMATECH e-Handbook §6.3.2.3.1 y §1.3.5.17
- **Acceso:** SIN_AUDITAR → **OFICIAL** (texto completo leído) [E]. EE. UU., inglés; no aplica raza.
- **CUSUM:** la tabla de ARL con k = 0,5 es para un CUSUM **unilateral** con un solo límite h; para vigilar subidas y bajadas el manual propone dos cartas unilaterales y **no da ningún ARL bilateral** [E].
  - Desplazamiento 0: h = 4 → **336**; h = 5 → **930** [E]. Nosotros teníamos 335 y 931 (cálculo propio por cadena de Markov de Brook-Evans); la diferencia es de una unidad y no cambia nada [I].
  - Desplazamiento 1σ: h = 4 → 8,38; h = 5 → 10,4 [E]: confirman nuestros 8,4 y 10,4.
  - Resto de la tabla leída (h = 4 / h = 5): 0,25σ 74,2 / 140; 0,75σ 13,3 / 17,0; 1,5σ 4,75 / 5,75; 2σ 3,34 / 4,01; 3σ 2,19 / 2,57 [E]. El valor de 0,5σ con h = 5 se extrajo como 30,0, que no encaja con la serie (cabría esperar del orden de 38): **[NV]**, revisar a mano antes de usarlo.
  - Columna de Shewhart: 371 con desplazamiento 0 y 44,0 con 1σ [E].
  - **Corrección:** los 168 / 465 que figuraban como «bilaterales» en la KB son derivados nuestros; no salen del NIST.
- **z modificado (§1.3.5.17):** M = 0,6745·(x − mediana)/MAD y posibles atípicos con |M| > 3,5, atribuido a Iglewicz y Hoaglin [E]. Confirma `linea_base_robusta` (1,4826·MAD es la forma equivalente: 1/1,4826 = 0,6745).

### 1.2 LOMBARD_HAWKINS_ARXIV_1904_00340
- **Acceso:** SIN_AUDITAR → **PREPRINT** (texto completo de arXiv leído) [E]. Sudáfrica (Univ. de Johannesburgo) y EE. UU. (Univ. de Minnesota); inglés; no aplica raza.
- **Corrección del título:** «CUSUM Average Run Length: Conditional or Unconditional?». No es un artículo «sobre el CUSUM autoiniciado», sino sobre qué ARL usar; la transformación autoiniciada aparece como herramienta.
- **Transformación confirmada** [E]: W_n = (X_n − media_{n−1})/s_{n−1}; U_n = Φ⁻¹(F_{n−2}(W_n·√((n−1)/n))), con F_{n−2} la t de Student de n − 2 grados de libertad. Coincide con `kb_self_starting_z`.
- **ARL** [E]: defienden el ARL **incondicional**; con datos normales los U_n son N(0,1) independientes y el ARL en control coincide con el de parámetros conocidos. Si los datos no son normales, recomiendan CUSUM de rangos secuenciales (Hawkins y Deng 2010). DOI de revista: **[NV]**.
- **Consecuencia [I]:** nuestras métricas de caballo (V200, FC a velocidad fija) pueden tener colas; el CUSUM autoiniciado sobre datos no normales puede dar más falsas alarmas. Queda como nota en la herramienta (sin regla todavía).

### 1.3 BOSCH_2018 — EquiMoves, Sensors 18(3):850
- **Acceso:** SIN_AUDITAR → **TEXTO_COMPLETO** (MDPI OA) [E]. Países Bajos (Utrecht), inglés. **Raza: 7 yeguas warmblood** de 10–21 años [E].
- **Sensor** [E]: dos acelerómetros fusionados, ±16 g y **±400 g**; giroscopio ±2000 °/s; 200 Hz con hasta 39 nodos y hasta 1 kHz con menos nodos (8 nodos a 1 kHz para el galope); validación a 200 Hz.
- **Validación** [E]: paso y trote en suelo frente a Qualisys de 18 cámaras; ±2,3° sagital, −8,8/+8,1° coronal; simetría del tronco ±5 mm (±2 mm en cruz y sacro). **No hay validación en galope**.
- **Efecto en la KB:** `rango_acelerometro_cincha` sigue igual (±16 g en la BETA es coherente), pero se anota que EquiMoves añade un canal de ±400 g para impactos, y que su validación es de warmblood a paso y trote [I-raza].

### 1.4 HOPKINS_2000 — Sports Med 30:1–15
- **Acceso:** SIN_AUDITAR → **TEXTO_COMPLETO** (PDF del autor en sportsci.org) [E]. Nueva Zelanda, inglés; humanos (no aplica raza).
- **Confirmado** [E]: TE = DE de las diferencias test-retest / √2; expresarlo como CV en % con logaritmos si el error crece con la media; cambio real en un individuo ≈ **1,5–2,0·TE** (probabilidades ≈ 6:1 a 12:1); el TE debe salir de un estudio corto sin cambio verdadero; estudios de fiabilidad con unos 50 sujetos y ≥ 3 pruebas; el ICC depende de la heterogeneidad de la muestra.
- **Efecto:** `umbral_cambio_real` (max(2·TE·√(1 + 1/n), SWC)) queda sostenido por texto completo en su parte 2·TE; el factor √(1 + 1/n) sigue siendo cálculo nuestro [I].
- **Dato útil:** la crítica al ICC aplica a Davie 2026 (ICC dependiente de la mezcla de caballos): para el motor importa el CV intraindividual, no el ICC [I].

### 1.5 EFRON_MORRIS_1975 — J Am Stat Assoc 70:311–319
- **Acceso:** SIN_AUDITAR → **TEXTO_COMPLETO** (copia docente en McGill) [E]. EE. UU., inglés; no aplica raza.
- **Confirmado** [E]: estimador de Stein hacia la media global y, con varianzas desiguales (§3), peso B_i = D_i/(A + D_i), es decir, varianza dentro frente a dentro + entre: la misma forma que `kb_shrink_mean`.
- Ejemplo de béisbol (18 jugadores, 45 turnos): la extracción dio peso propio 0,209; la cifra que suele citarse es 0,212 → **[NV]** (no la usa el motor). Error cuadrático 17,56 (MV) frente a 5,01 (Stein) [E].

### 1.6 MUKAI_2007_JES — J Equine Sci 18:153–160
- **Acceso:** sigue en **RESUMEN** [E-r]. Japón (JRA, Nakayama), inglés, PSI. La ficha de J-STAGE es FREE ACCESS (CC BY-NC-ND 4.0), pero el PDF volvió a estar bloqueado por robots.
- **Corrección importante:** los «±» del resumen son **error estándar (EE)**, no desviación típica. FC pico 213,6 ± 1,7 lpm (EE, n = 23) equivale a una DE entre caballos de ≈ 1,7·√23 ≈ **8,2 lpm** [I, cálculo]. Las demás cifras (12,4 ± 1,8 s al 95 % del pico; lactato 22,5 ± 0,6 mmol/L a los 10 min; 15,9 m/s; 194,0 ± 2,0 lpm = 91,1 % en el medio galope; 171,4 ± 5,3 en los cajones) se confirman como EE [E-r].
- **Dato nuevo** [E-r]: la FC sube en el pasillo subterráneo y al montar el jinete sin aumento de esfuerzo (componente emocional previo a la carrera).
- **Vías probadas:** J-STAGE `_pdf` y `_pdf/-char/en` (robots), `_pdf/-char/ja` (permiso de la herramienta), ResearchGate (error), BVB (resumen), Semantic Scholar/CiNii/OpenAlex (sin URL utilizable). Sigue en cola (descarga manual legal).

### 1.7 FRICK_2019 — J Vet Intern Med 33:212–224
- **Acceso:** RESUMEN → **TEXTO_COMPLETO** (OUP, que ahora publica JVIM; CC BY-NC) [E]. Suiza (Zúrich), inglés.
- **Razas** [E]: 45 warmblood, **4 PSI, 3 árabes**, 1 Cuarto de Milla y 1 poni; 11 ± 5 años. `raza_fuente` pasa de «no verificada» a «mixto (83 % warmblood)».
- **Cifras confirmadas** [E]: 54 caballos (13 sanos, 30 con arritmias, 11 con bajo rendimiento); variación RR en sanos −4,4/+3,8 % al trote y −6,1/+5,4 % al canter; corte de recuperación 6 % (Youden): S 88 % (IC 68–97), E 97 % (IC 83–100), LR 26.
- **Protocolo** [E]: cinta con 6 % de pendiente, 2 escalones de trote y 3–4 de canter (+≈1 m/s), 120 s y luego 90 s; fin con FC > 200 o lactato > 4 mmol/L; velocidad pico mediana 8 m/s (5–11); ECG a 500 Hz revisado a mano.
- **Cortes adicionales** [E]: recuperación 4,1 % (S 100 %, E 80 %) y 6,3 % (S 88 %, E 100 %); canter 11 % (S 88 %, E 98 %, LR 40) y 6,5 % (S 100 %, E 59 %); trote 5,7 % (S 83 %, E 85 %).
- **Transferencia [I-raza]:** velocidades de cinta muy inferiores al galope de carreras; el umbral del 5 % de `ecg_prematuro` se mantiene, y el 11 % en canter se anota como corte de alta especificidad, no como umbral del motor.
- Discrepancia del diseño (prospectivo en el resumen, retrospectivo en la extracción) → **[NV]**.

### 1.8 SPARGO_2019_JSAVA — J S Afr Vet Assoc 90:a1640
- **Acceso:** RESUMEN → **TEXTO_COMPLETO** (PDF en CORE y ficha AOSIS; CC BY 4.0) [E]. Sudáfrica (Gauteng), inglés, PSI.
- **Confirmado** [E]: 1998–2012; 114 eutanasias por lesión catastrófica en 203.965 salidas = **0,56 por 1.000** (0,6 redondeado); sesamoideos proximales y suspensor distal 55,26 %; fracturas biaxiales 74,47 % (35 de 47).
- **Corrección:** el 73,6 % NO es de los caballos: es el 73,58 % de las **53 extremidades disecadas o radiografiadas**. Sobre los 114 caballos, anterior izquierdo 54,39 % (62/114) y anterior derecho 28,95 % [E].
- **Datos nuevos** [E]: por hipódromo, Turffontein (césped) 0,66 / 1.000, Newmarket 0,53, Vaal (césped y arena) 0,51, Gosforth Park 0,34; todos en sentido horario; rango anual 0,29 (2006) a 0,99 (2004). No analiza factores de riesgo. Solo contexto poblacional; nunca predicción individual.

### 1.9 DAVIE_2026 — Animals 16(14):2187
- **Acceso:** RESUMEN → **TEXTO_COMPLETO** (MDPI cargó esta vez) [E]. Australia (Melbourne y Ballina), inglés, PSI en forma de 3–8 años.
- **Confirmado** [E]: 64 caballos, 823 galopes en cinta; ICC de la FC de galope 0,756 (0,621–0,809 según el test).
- **Corrección:** el resumen y la tabla 3 no coinciden para la recuperación a 30 s: resumen 0,421, **tabla 3 0,451**; 60 s 0,504 → 0,502; 90 s 0,595; 120 s 0,571 [E]. Se adopta la tabla 3.
- **Datos nuevos** [E]: CV intraindividual de la FC de galope ≈ **2,7 %** y de la FC de recuperación 5,5–6,2 %; con todos los datos ≈ 5,8 % y 8,4–9,3 %; lactato ICC 0,415 y CV ≈ 25 % intraindividual. Sin TE, MDC ni SWC [NV].
- **Protocolo** [E]: 5 tests en cinta a 6° de pendiente: 3 × 1 min, 2 × 2 min, 3 × 2 min y 1 × 3 min a 8 m/s, y 3 × 1 min a 10 m/s, con 5 min de recuperación entre galopes.
- **Consecuencia [I]:** el CV intraindividual del 2,7 % de la FC a velocidad fija en cinta es el mejor dato de PSI para el ruido día a día de la FC a velocidad dada; en pista (GNSS, suelo, viento) será mayor. Coherente con el TE por defecto del 3 % de la V200 marcado «no validado» (VT1); no se cambia.

---

## 2. Tema nuevo A: carga de entrenamiento con FC y GPS (TRIMP, ACWR, monotonía, bandas)

**Conclusión:** no existe ningún TRIMP ni ningún ACWR validado en PSI ni en árabes de carreras en llano. El único estudio equino que calcula ambos es de caballos de **completo** (Países Bajos). En PSI la carga bien definida es **externa**: distancia por bandas de velocidad, ya presente en la KB (Verheyen 2006, Morrice-West 2020, Wong 2023).

### 2.1 PSI (ya en la KB; solo se reconfirma)
- Verheyen 2006 [E-r]: umbral conjunto > 44 km a canter (≤ 14 m/s) **y** > 6 km a galope (> 14 m/s) en 30 días; sin OR leídos (sigue en cola).
- Morrice-West 2020, EVJ 10.1111/evj.13156 (manuscrito aceptado) [E]: bandas < 10 m/s (lento), 11,1–12,5 m/s («pace»), ≥ 13,3 m/s en sub-bandas 13,3–14,3 / 14,4–15,4 / 15,5–16,7 / ≥ 16,8 m/s; galope mediano 8.000 m/mes (RIC 6.400–12.000) en adultos en forma de carrera; el ACWR se menciona pero **no se calcula**.
- Wong 2023, Front Vet Sci [E]: misma definición de «fast work» (≥ 13,3 m/s); sin FC ni ACWR.
- Kingston 2007 (NZ) [E-r]: GPS + FC diarios en 19 PSI de 3 años; respuestas de FC distintas al mismo trabajo; sin métrica de carga.
- Davie, Beavers y Denham 2025, JEVS 149:105567 (revisión) [E]: propone distribución piramidal (70–80 % del volumen bajo el umbral de lactato); sin zonas de FC equinas ni TRIMP.

### 2.2 Caballos de completo — el único TRIMP/ACWR equino [I-raza]
**Munsters, Kingma, van den Broek y Sloet van Oldruitenborgh-Oosterbaan 2020, Prev Vet Med 179:105010** (OA) [E]:
- 58 caballos de completo (CCI2*–5*), 94 temporadas, ≈ 2.300 sesiones, 64 lesiones no traumáticas.
- Carga externa: distancia GPS a 6,6–9,5 m/s (HS) y > 9,5 m/s (SS).
- Carga interna (iTRIMP): duración × ΔFC × b·e^(c·ΔFC) (forma de Banister), con b y c ajustados por caballo con una prueba estándar de 4 × 1.000 m y lactato. Publican b = 1,53 ± 0,42 y c = 0,01 ± 0,04 (c inverosímil o mal informado [I]); FC de reposo **supuesta** 30 lpm y FC máxima **supuesta** 220 lpm.
- ACWR: agudo 1 semana, crónico 4 semanas, EWMA acoplado; λ no publicados.
- Resultado: el ACWR de **distancia HS** de la semana anterior se asoció a lesión (OR ≈ 3,95; IC 1,39–12,50); el ACWR **interno (iTRIMP) no** fue significativo. Valores por sesión: 62,9 ± 29,4 min; FC media 114 ± 13 lpm; iTRIMP-HS 11,9 ± 17,1 UA. El total interno publicado (6,4 UA) es menor que sus partes: incoherencia del artículo [E].
- **Transferibilidad:** baja. Velocidades del completo (HS desde 6,6 m/s) muy inferiores a las de carreras; FC máxima supuesta (220) por debajo de la de PSI y trotones (≈ 213–231 lpm); deporte con otro patrón de lesión. Solo vale como **método**.

### 2.3 Trotones [I-raza]
- Hamlin, Shearman y Hopkins 2002 (NZ, Standardbred) [E-r]: 8 semanas de sobrecarga → últimos 1.200 m 4,0 % más lentos y velocidad pico −6,9 %; bajan V200 y peso; FCmax y recuperación sin cambio claro.
- Tyler 1996 (Australia, Standardbred) [E-r]: el sobreentrenamiento apareció a las 31 semanas sin bajar el VO₂max; sí bajó el peso.
- Flyrin y Hägglund 2021, tesina SLU (Suecia, sueco) [E]: 32 trotones con Polar; tiempo > 180 y > 200 lpm en cuesta ≈ 500 s y ≈ 379 s; FC máxima en entrenamiento: sementales 231, castrados 224, yeguas 220 lpm. Sin TRIMP.
- Leleu 2022, AVEF (Francia) [CONGRESO]: V200 y V4 para el seguimiento; sin zonas numéricas.
- Nyerges-Bohák 2021, PLoS One (Hungría, PSI y trotones) [E-r]: rMSSD en reposo baja tras 14 semanas; usa el SWC para señalar posible mala adaptación.

### 2.4 Otros
- Valle 2013, CEP 9:93 (Italia, warmblood de completo) [E]: carga como % de la FC pico (190–228 lpm) y gasto energético; recuperación (%FC pico) del final a 180 s: doma 57→37 %, salto 59→41 %, cross 92→53 %.
- Kirsch 2022 (Alemania, salto) [E]: V140, V170, VLa2, VLa4; sin TRIMP.
- Porzio 2025 (Italia, árabes y angloárabes de endurance) [E]: VFC y zancada en arena; sin índice de carga. Solo método.
- Árabes de carreras: Janczarek 2016 (Polonia) solo VFC [E-r]. Golfo, China, Corea: nada sobre carga [NV].
- **Fórmulas humanas** (monotonía y strain de Foster, EWMA λ = 2/(N + 1), zonas de Edwards): **no leídas esta noche → [NV]**; en caballos no hay ninguna aplicación publicada de monotonía o strain.

### 2.5 Qué no existe
- TRIMP validado en PSI o árabes (ni Banister, ni Edwards, ni Lucia, ni equino).
- ACWR validado en carreras (PSI, árabe o trotón).
- Zonas de FC equinas validadas para carreras; solo umbrales prácticos (V200, > 180 / > 200 lpm, VLa4).
- sRPE, monotonía o strain de Foster en caballos.
- Comparación entre razas de un índice de carga.

### 2.6 Fórmulas humanas de referencia (plantilla de CG1–CG3) y novedades de octubre–noviembre de 2026
Ningún original se leyó completo (PubMed/PMC con reCAPTCHA; libros sin versión abierta); las fórmulas se confirman en fuentes secundarias legales en texto completo:
- **TRIMP de Banister** (Morton, Fitz-Clarke y Banister 1990, J Appl Physiol 69:1171; vía Sanders 2016, manuscrito aceptado en Hull, y Matomäki 2024, JYX): TRIMP = D(min)·ΔFC·0,64·e^(1,92·ΔFC), ΔFC = (FC − FC_reposo)/(FC_máx − FC_reposo); en mujeres el exponente es 1,67 y el multiplicador 0,86 solo aparece en un blog sin cita → [NV]. Para caballos solo vale la forma, no los coeficientes [I-raza].
- **Zonas de Edwards** (1993; vía Sanders 2016): 50–59 / 60–69 / 70–79 / 80–89 / 90–100 % de FCmax con pesos 1–5.
- **Foster 1998** (MSSE 30:1164) [E-r]: monotonía = media diaria / DE semanal; strain = carga semanal × monotonía; corroborado por Anderson 2003 (CORE). DE muestral o poblacional y días de descanso [NV].
- **Williams 2017** (BJSM 51:209; vía Hamlin 2019, Front Physiol 10:34, OA): EWMA_hoy = carga·λ + (1 − λ)·EWMA_ayer, λ = 2/(N + 1), N = 7 y 28 (λ 0,25 y ≈ 0,069 [cálculo]).
- **Impellizzeri 2020** (IJSPP 15:907) [E-r]: no hay pruebas que apoyen usar el ACWR para gestionar cargas o reducir lesiones; problemas de los ratios, definiciones ambiguas y relación inconsistente con la lesión. Refuerza CG3: el cociente solo es descriptivo y se muestran aguda y crónica por separado.

Novedades (búsqueda no exhaustiva; nada nuevo en árabes, J-STAGE, Corea, Hong Kong ni Latinoamérica):
- Anwar et al. 2026 se publicó el 07/10/2026 en R Soc Open Sci 13(10):260818 (ya en la KB como `ANWAR_2026_RSOS`); la web de la revista dio error y las cifras siguen siendo las del preprint [E] (daño máximo normalizado 1,543 / 0,911 / 0,799 con 1 / 2 / 3 descansos al año) sin comparar con la versión publicada [NV].
- Mizobe y Mita 2026 (JEVS 106157, JRA; ya en la KB): fracturas de entrenamiento menos frecuentes en la pista en cuesta, IRR 0,359 (0,329–0,392) [E-r], reconfirmado.
- Pinetzki et al. 2026 (Front Vet Sci, Alemania, 30 PSI de 18–24 meses): conducta tras el pre-entrenamiento con monitores de actividad; no aporta carga [E parcial].
- Poinsard 2026 (trotones; ya en la KB) y Takahashi, Pfau et al. (AJVR, 921 PSI en Japón; ya en la KB) reconfirmados por resumen.

---

## 3. Tema nuevo B: edad, sexo y castración como covariables

**Conclusión:** la **edad** tiene un efecto grande y bien documentado sobre la V200 y la velocidad de carrera entre los 2 y los 4 años; el **sexo** tiene un efecto pequeño en velocidad de carrera (≈ 0,3–1 %) y no hay **ningún** dato publicado de V200, VHRmax o VLa4 comparados por sexo dentro del PSI o del árabe de carreras.

### 3.1 PSI — Japón (JRA)
- Kobayashi, Kuribara y Amada 2000 (ya en la KB) [E-r]: V200 623 ± 55 → 691 ± 64 m/min en 5 meses en potros de 2 años (**+11 %**); sin análisis por sexo.
- Shiose, BTC News 80 (JRA, japonés; divulgativo) [OFICIAL]: FC máxima individual de 210 a 230 lpm; por eso recomienda VHRmax para comparar entre caballos.
- Blog de la JRA en Hidaka 2019 y 2021 (Haneda; japonés) [OFICIAL]: la V200 de los potros sube de febrero a abril; en 236 potros, la V200 del final de la doma solo separa a los que ganan ≥ 2 carreras y la relación es **más clara en hembras que en machos** (sin cifras por sexo).
- Massie et al. 2024, BMC Vet Res 20:159 (Miyazaki; 4 machos y 6 hembras de 20–23 meses) [E]: FC máxima 221 ± 8 → 226 ± 7 lpm; velocidad máxima 13,3 ± 0,5 → 16,0 ± 0,6 m/s; últimos 400 m 30,9 → 26,1 s; **sin efecto del sexo** (n muy pequeño).
- Takahashi 2015, J Equine Sci 26:43 (ya en la KB) [E, figuras sin leer]: la velocidad de carrera sube hasta el primer semestre de los 4 años (el tramo más rápido de marzo a noviembre de los 3 años) y luego se mantiene; ≈ 17,1 m/s en césped a 1.400 m y ≈ 16,6 m/s a 1.800 m. Diferencia por sexo solo en figuras [NV].
- Oki, Sasaki y Willham 1994, J Anim Breed Genet 111:128 [E-r]: hembras más rápidas en césped, machos en arena (salvo 1.200 m); confusión con la descarga de peso sin resolver.
- JRA, normas de peso (負担重量) [OFICIAL]: hembras 2 kg de descarga a los 3 años (1 kg a los 2 años de octubre a diciembre); **castrados = machos**; los de 3 años descargan 7–10 kg en enero frente a los mayores y 1–2 kg en diciembre.

### 3.2 PSI — EE. UU., Europa, Australia
- Gramm y Marksteiner 2010, J Equine Sci 21:73 (EE. UU., 274 machos, Beyer) [E]: edad pico 4,45 años; de los 2 años al pico, +22,2 puntos (≈ 10 cuerpos en velocidad).
- Sobotková et al. 2023, Arch Anim Breed 66:299 (6.216 PSI de élite, rating IFHA ≥ 115) [E]: machos enteros 117,85; castrados 117,17; yeguas 117,13 (**castrados ≈ yeguas**); muestra truncada a la élite.
- Schrurs et al. 2022, CEP 18:185 (Australia y Francia, 509 PSI) [E-r]: los mayores tienen menor FC a los 15 min y FC pico más baja a casi todas las intensidades (solo en la cohorte australiana).
- Schrurs et al. 2024 (ya en la KB) [E]: FC pico ≈ 200–210 lpm sin diferencias por edad entre 2 y 10 años; los machos enteros ganan con más probabilidad (OR solo en figura [NV]).
- Katz et al. 2023, Vet J 106041 (Irlanda, 41 añojos) [E-r]: VO₂pico por kg mayor en hembras (121,5 frente a 111,9 mL/kg/min; P = 0,03); VO₂ absoluto sin diferencia.
- Entin 2002 (APS, nota de prensa) [PRENSA]: machos ≈ 1 % más rápidos.
- BHA, Racing Victoria y QREC [OFICIAL]: descarga de hembras de 5 lb (BHA, PSI), 4 lb (BHA, árabes, con castrados sin descarga), 2 kg (Racing Victoria, hándicaps mixtos) y 2 kg (QREC); BHA: 5–6 cuerpos por segundo en llano.

### 3.3 Árabe de carreras
- Taçyıldız, Yılmaz y Kaygısız 2026, KSÜ Tarım ve Doğa Derg 29(4):1067 (Turquía, turco; 493 árabes, 11.366 carreras) [E]: machos 13,86 ± 0,01 m/s y hembras 13,86 ± 0,01 m/s (**sin diferencia**); por edad 2 a 13,68, 3 a 14,01, 4 a 13,80, 5 a 13,87, 6 a 13,93, 7 a 13,81, 8 a 13,69, 10 a 13,21 m/s (confundido con la distancia [I]).
- Yıldırım 2019, Kocatepe Vet J (ya en la KB) [E]: efecto del sexo no significativo en las tablas (césped 14,46 / 14,42; arena 13,52 / 13,52 m/s); edad significativa (arena: 3 años 13,78 → 8+ años 13,24 m/s).
- Schurink 2009 (Países Bajos, ya en la KB) [E-r]: la velocidad sube con la edad hasta ≈ 6 años.
- Sobczyńska 2010, Arch Tierz 53:639 (Polonia) [E-r]: edad media al primer arranque PSI 933 días (≈ 2,6 años) y árabes ≈ 1.199 días (≈ 3,3 años).
- QREC, programa 2025–26 (Qatar) [OFICIAL]: en árabes, los de 4 años llevan **5–6 kg menos** que los de 5 o más (p. ej. 56 frente a 62 kg en maiden); en PSI la diferencia es de 0,5–1,5 kg. Indica maduración ≈ 1 año más tardía en el árabe [I].
- Santos et al. 2023, Animals 13:1800 (Brasil; 12 árabes de 28 meses, no de carreras) [E] [I-raza]: tras 6 semanas en cinta, V2 5,2 → 6,7 m/s y V4 5,8 → 7,6 m/s (≈ +31 %).

### 3.4 Otras razas [I-raza]
- Leleu, Cotrel y Barrey 2004, ECEP 1:107 (trotón francés, 143 caballos de 2 a 5+ años) [E]: la V200 difiere entre todos los grupos de edad y sube con ella (r = 0,47; valores solo en figura [NV]); zancada a 11,6 m/s con diferencias de 2–4 % y no monótonas.
- Walker 2009 (Standardbred, yeguas de 4–29 años) [E-r]: el VO₂max cae con la edad, con quiebre a 18–20 años (fuera de la edad de carreras).
- Arias 2006 (Colombia, PSI a 2.005 m de altitud) [E]: FCmax 241 ± 4,8 lpm, V200 8,44 m/s: no sirve como prior (altitud y nivel).
- Ohmura y Jones 2017, J Equine Sci 28:99 (PSI) [E-r]: la FC en reposo baja con la edad; mínimo en caballos de carreras de 3–7 años (32,9 ± 3,5 lpm).
- Corea, Oh 2009 (KoreaScience) [E]: el sexo es significativo en modelos genéticos de tiempos, sin cifras útiles.

### 3.5 Conversión de las descargas de peso a velocidad [I]
- Sexo: 3–5 lb en 1 milla ≈ 1,5–2 cuerpos ≈ 0,3 s en ≈ 97 s ≈ **0,3–0,4 %** de velocidad; 2 kg en 1.600 m ≈ 0,4–0,5 %. Coherente con el ≈ 1 % de Entin y con la diferencia nula en árabes turcos.
- Edad: 3 frente a 4 años en primavera, 8 lb (BHA) o 7–9 kg (JRA) ≈ 1–2 %; menos del 0,3 % en diciembre.

### 3.6 Qué no existe
- V200, VHRmax o VLa4 comparados por sexo, o castrado frente a entero, dentro de PSI o árabe de carreras.
- Estudio longitudinal de la FCmax frente a la edad (lpm por año) en PSI de 2–5 años.
- Efecto de la castración sobre el rendimiento con texto completo legal.
- V200 de campo por edad o sexo en árabes de carreras.

---

## 4. Reglas propuestas (todas PROPUESTA [I], sin implementar)

- **CG1 — carga interna por sesión (TRIMP equino individualizado) solo descriptiva.** ΔFC = (FC − FC_reposo)/(FC_máx − FC_reposo) con FC de reposo y máxima **del propio caballo** (no 30/220 fijos); TRIMP = Σ Δt·ΔFC·b·e^(c·ΔFC)/60 con b = 0,64 y c = 1,92 (plantilla de Banister usada por Munsters; [NV] en esta sesión) marcados «no validados en equinos»; guardar también la versión sin ponderar y el tiempo > 180 y > 200 lpm.
- **CG2 — carga externa por bandas de velocidad.** < 10 / 10–13,3 / 13,3–14,3 / 14,4–15,4 / 15,5–16,7 / ≥ 16,8 m/s para PSI, con totales «≤ 14 / > 14 m/s» (Verheyen) y «≥ 13,3 m/s» (Morrice-West, Wong) por sesión, 7 d y 30 d; en árabes, bandas relativas a su velocidad de carrera (`bandas_fraccion_v_carrera`) [I-raza].
- **CG3 — agudo/crónico solo como «cambio relativo de carga».** EWMA 7/28 d de la distancia ≥ 13,3 m/s y del TRIMP por separado; nunca como riesgo ni semáforo de lesión; nota obligatoria de que no hay validación en carreras.
- **ES1 — prior μ_pop estratificado por edad y raza, no por sexo.** PSI 2 / 3 / 4+ años; árabes 3 / 4 / 5+ años; en 2 años, τ² × 1,5–2 y menos contracción (la V200 sube ≈ +11 % en 5 meses).
- **ES2 — sexo solo como covariable pequeña de la velocidad de carrera y de los parciales.** Hembras −0,4 % (0–1 %); castrados como machos en peso oficial y como hembras en élite; ningún efecto de sexo en V200, VHRmax, FCmax ni VLa4.
- **ES3 — prior de FCmax común sin sexo.** Media ≈ 215–226 lpm y DE entre caballos ≈ 8 lpm (Mukai 2007, EE → DE ≈ 8,2; Massie 2024 ± 7–9) marcada «no propia»; coherente con FM1 (210–215 «no propia»).

---

## 5. Tabla de fuentes

| Cita | DOI / URL | País | Idioma | Raza | Acceso | Qué cifra sostiene |
|---|---|---|---|---|---|---|
| NIST/SEMATECH e-Handbook §6.3.2.3.1 y §1.3.5.17 | itl.nist.gov/div898/handbook/pmc/section3/pmc3231.htm | EE. UU. | en | no aplica | OFICIAL | ARL0 336 / 930 unilateral; z modificado > 3,5 |
| Lombard F, Hawkins DM 2019, arXiv 1904.00340 | arxiv.org/pdf/1904.00340 | Sudáfrica y EE. UU. | en | no aplica | PREPRINT | U_n autoiniciado; ARL incondicional |
| Bosch S et al. 2018, Sensors 18:850 | 10.3390/s18030850 | Países Bajos | en | warmblood (7 yeguas) | TEXTO_COMPLETO | ±16 g y ±400 g; 200 Hz–1 kHz |
| Hopkins WG 2000, Sports Med 30:1 | statistics.sportsci.org/resource/stats/Hopkins_SportsMed_rely_00.pdf | Nueva Zelanda | en | humanos | TEXTO_COMPLETO | TE; cambio real 1,5–2·TE |
| Efron B, Morris C 1975, JASA 70:311 | 10.1080/01621459.1975.10479864 | EE. UU. | en | no aplica | TEXTO_COMPLETO | peso B_i = D_i/(A + D_i) |
| Mukai K et al. 2007, J Equine Sci 18:153 | 10.1294/jes.18.153 | Japón | en | PSI | RESUMEN | FC pico 213,6 ± 1,7 (EE) |
| Frick L et al. 2019, JVIM 33:212 | 10.1111/jvim.15358 (academic.oup.com/jvim/article/33/1/212/8447902) | Suiza | en | mixto (45 WB, 4 PSI, 3 árabes) | TEXTO_COMPLETO | RR −6,1/+5,4 %; corte 6 % |
| Spargo KE et al. 2019, JSAVA 90:a1640 | core.ac.uk/download/201190064.pdf | Sudáfrica | en | PSI | TEXTO_COMPLETO | 0,56/1.000; 73,6 % de 53 extremidades |
| Davie AJ et al. 2026, Animals 16:2187 | 10.3390/ani16142187 | Australia | en | PSI | TEXTO_COMPLETO | ICC 0,756; recuperación 0,451–0,595; CV 2,7 % |
| Munsters CCBM et al. 2020, Prev Vet Med 179:105010 | 10.1016/j.prevetmed.2020.105010 | Países Bajos | en | completo (warmblood) | TEXTO_COMPLETO | iTRIMP; ACWR HS OR 3,95 |
| Morrice-West AV et al. 2020, EVJ | 10.1111/evj.13156 | Australia | en | PSI | TEXTO_COMPLETO (AAM) | bandas de velocidad; 8.000 m/mes |
| Wong ASM et al. 2023, Front Vet Sci | 10.3389/fvets.2023.1260554 | Australia | en | PSI | TEXTO_COMPLETO | fast work ≥ 13,3 m/s |
| Davie AJ, Beavers R, Denham J 2025, JEVS 149:105567 | 10.1016/j.jevs.2025.105567 | Australia | en | PSI (revisión) | TEXTO_COMPLETO | modelo piramidal 70–80 % |
| Valle E et al. 2013, CEP 9:93 | 10.3920/CEP12028 | Italia | en | warmblood de completo | TEXTO_COMPLETO | recuperación %FC pico por disciplina |
| Flyrin M, Hägglund A 2021, tesina SLU | stud.epsilon.slu.se/17336 | Suecia | sv | trotón | TEXTO_COMPLETO | > 180 / > 200 lpm; FCmax por sexo |
| Kirsch K et al. 2022, Front Physiol | 10.3389/fphys.2021.818381 | Alemania | en | caballo de salto | TEXTO_COMPLETO | V140, V170, VLa4 |
| Nyerges-Bohák Z et al. 2021, PLoS One | 10.1371/journal.pone.0259933 | Hungría | en | PSI y trotón | RESUMEN | rMSSD y SWC |
| Massie S et al. 2024, BMC Vet Res 20:159 | 10.1186/s12917-024-03997-x | Japón y Canadá | en | PSI | TEXTO_COMPLETO | FCmax 221–226; sin efecto del sexo |
| Gramm M, Marksteiner R 2010, J Equine Sci 21:73 | 10.1294/jes.21.73 | EE. UU. | en | PSI | TEXTO_COMPLETO | edad pico 4,45 años |
| Sobotková E et al. 2023, Arch Anim Breed 66:299 | 10.5194/aab-66-299-2023 | internacional | en | PSI | TEXTO_COMPLETO | castrados ≈ yeguas |
| Oki H et al. 1994, J Anim Breed Genet 111:128 | 10.1111/j.1439-0388.1994.tb00446.x | Japón | en | PSI | RESUMEN | sexo según superficie |
| Katz LM et al. 2023, Vet J | 10.1016/j.tvjl.2023.106041 | Irlanda y EE. UU. | en | PSI (añojos) | RESUMEN | VO₂pico/kg hembras > machos |
| Entin P 2002, APS | eurekalert.org/news-releases/529662 | EE. UU. | en | PSI | PRENSA | machos ≈ 1 % más rápidos |
| JRA, 負担重量 | jra.go.jp/keiba/rules/weight.html | Japón | ja | PSI | OFICIAL | descargas por sexo y edad |
| JRA Hidaka, blog 2019 y 2021 | blog.jra.jp/shiryoushitsu/2021/01/v200-091c.html | Japón | ja | PSI | OFICIAL | V200 de potros; relación más clara en hembras |
| BHA, Performance figures | britishhorseracing.com/regulation/performance-figures/ | Reino Unido | en | PSI | OFICIAL | 5 lb hembras; 5–6 cuerpos/s |
| BHA, Regulations for Arabian Horseracing 2024 | britishhorseracing.com (PDF 2024) | Reino Unido | en | árabe | OFICIAL | 4 lb hembras; castrados sin descarga |
| QREC, Racing Season Program 2025-26 | qrec.gov.qa/pdf/2025-2026-Racing-Season-Program/en.pdf | Qatar | en | árabe y PSI | OFICIAL | árabes de 4 años 5–6 kg menos |
| Racing Victoria, Handicapping | racingvictoria.com.au/racing/handicapping | Australia | en | PSI | OFICIAL | hembras 2 kg |
| Taçyıldız SŞI et al. 2026, KSÜ Tarım ve Doğa Derg 29:1067 | 10.18016/ksutarimdoga.vi.1634951 | Turquía | tr | árabe de carreras | TEXTO_COMPLETO | 13,86 = 13,86 m/s; velocidad por edad |
| Sobczyńska M 2010, Arch Tierz 53:639 | 10.5194/aab-53-639-2010 | Polonia | en | PSI y árabe | RESUMEN | primer arranque 933 / 1.199 días |
| Santos MM et al. 2023, Animals 13:1800 | 10.3390/ani13111800 | Brasil | en | árabe (no de carreras) | TEXTO_COMPLETO | V2 y V4 a 28 meses |
| Leleu C, Cotrel C, Barrey E 2004, ECEP 1:107 | 10.1079/ECEP200312 | Francia | en | trotón francés | TEXTO_COMPLETO | V200 sube con la edad (r 0,47) |
| Walker A et al. 2009, CEP 6:177 | 10.1017/S1755254010000073 | EE. UU. | en | Standardbred | RESUMEN | VO₂max y edad |
| Morton RH, Fitz-Clarke JR, Banister EW 1990, J Appl Physiol 69:1171 (vía Sanders 2016) | hull-repository.worktribe.com/OutputFile/443111 | Nueva Zelanda y Canadá | en | humanos | RESUMEN (secundaria en texto completo) | TRIMP 0,64·e^(1,92·ΔFC) |
| Edwards S 1993, The Heart Rate Monitor Book (vía Sanders 2016) | hull-repository.worktribe.com/OutputFile/443111 | EE. UU. | en | humanos | RESUMEN (secundaria) | zonas 50–100 % con pesos 1–5 |
| Foster C 1998, MSSE 30:1164 | sponet.de/sponet/Record/4001707 | EE. UU. | en | humanos | RESUMEN | monotonía y strain |
| Williams S et al. 2017, BJSM 51:209 (vía Hamlin 2019) | 10.3389/fphys.2019.00034 | Reino Unido | en | humanos | RESUMEN (secundaria en texto completo) | EWMA λ = 2/(N + 1) |
| Impellizzeri FM et al. 2020, IJSPP 15:907 | 10.1123/ijspp.2019-0864 | Australia | en | humanos | RESUMEN | crítica del ACWR |
| Pinetzki L et al. 2026, Front Vet Sci 13 | 10.3389/fvets.2026.1927282 | Alemania | en | PSI | TEXTO_COMPLETO (parcial) | conducta tras el pre-entrenamiento |
| Ohmura H, Jones JH 2017, J Equine Sci 28:99 | 10.1294/jes.28.99 | Japón y EE. UU. | en | PSI | RESUMEN | FC en reposo 32,9 lpm a 3–7 años |

## 6. Resultado de la auditoría

| Fuente | Antes | Después | Cambio de cifras |
|---|---|---|---|
| NIST_CUSUM | SIN_AUDITAR | OFICIAL | ARL0 336 / 930 (nuestros 335 / 931 por Markov); 168/465 son nuestros |
| LOMBARD_HAWKINS_ARXIV_1904_00340 | SIN_AUDITAR | PREPRINT | título corregido; transformación confirmada |
| BOSCH_2018 | SIN_AUDITAR | TEXTO_COMPLETO | añade ±400 g; raza warmblood |
| HOPKINS_2000 | SIN_AUDITAR | TEXTO_COMPLETO | 1,5–2·TE confirmado |
| EFRON_MORRIS_1975 | SIN_AUDITAR | TEXTO_COMPLETO | forma del estimador confirmada |
| MUKAI_2007_JES | RESUMEN | RESUMEN | los ± son EE (DE ≈ 8,2 lpm) |
| FRICK_2019 | RESUMEN | TEXTO_COMPLETO | razas y protocolo; cortes extra |
| SPARGO_2019_JSAVA | RESUMEN | TEXTO_COMPLETO | 73,6 % es de 53 extremidades; 0,56/1.000 |
| DAVIE_2026 | RESUMEN | TEXTO_COMPLETO | ICC 30 s 0,421 → 0,451; CV 2,7 % |

**8 de 9 fuentes mejoradas** (5 SIN_AUDITAR reclasificadas, 3 RESUMEN → TEXTO_COMPLETO). Ningún valor que use el código cambia. Sigue en cola: Mukai 2007 (PDF de J-STAGE por descarga manual).

## 7. Cobertura

- **Regiones:** Japón (JRA, J-STAGE, blog de Hidaka, normas de peso), Corea (KoreaScience), Qatar (QREC), Turquía (DergiPark), Polonia, Países Bajos, Suiza, Suecia (SLU), Francia, Hungría, Italia, Alemania, Reino Unido e Irlanda (BHA), EE. UU., Brasil, Colombia, Australia y Nueva Zelanda, Sudáfrica. Sin datos útiles en China ni en literatura en árabe del Golfo.
- **Idiomas:** inglés, japonés, turco, sueco, portugués, español, coreano; búsquedas sin resultado en chino y árabe.
- **Razas:** PSI, árabe de carreras, árabe no de carreras (Brasil) y de endurance (método), angloárabe, trotón (Standardbred, francés, sueco), warmblood (completo, salto, clínica), Cuarto de Milla (Frick, Carvalho), ponis. Todas las no PSI/árabe llevan `raza_fuente` e [I-raza].

## 8. Resumen

La auditoría deja con texto completo u oficial las cinco fuentes estadísticas que sostienen funciones ya implementadas del motor (z robusto, CUSUM, CUSUM autoiniciado, umbral de cambio real y contracción), y corrige tres detalles de fuentes de parámetros: los ARL bilaterales eran nuestros, los ± de Mukai 2007 son EE, el 73,6 % de Spargo es de las extremidades disecadas y el ICC a 30 s de Davie es 0,451. Los dos temas nuevos concluyen que no hay TRIMP ni ACWR validados en caballos de carreras (solo en completo, y allí solo la carga externa a alta velocidad se asoció a lesión), y que el prior poblacional debería estratificarse por edad y raza, no por sexo. Las fórmulas humanas de plantilla (TRIMP de Banister, zonas de Edwards, monotonía de Foster, EWMA de Williams) quedan confirmadas en fuentes secundarias legales, y la crítica de Impellizzeri 2020 refuerza que el cociente agudo/crónico sea solo descriptivo. No cambia la lógica del motor; las reglas CG1–CG3 y ES1–ES3 quedan PROPUESTA [I].
