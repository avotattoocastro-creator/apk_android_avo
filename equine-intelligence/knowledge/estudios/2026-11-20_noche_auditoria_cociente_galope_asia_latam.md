# Investigación nocturna 20/11/2026: auditoría de fuentes, cociente de galope (A6C), Asia y Golfo, Latinoamérica y TFDS

**Inicio:** 04:08 (hora de Madrid) · **Autor:** Claude (tarea programada, sin supervisión) · **Base:** KB-1 1.8.0 → **1.9.0** ·
**Motor:** 2.0.0-dev10 → **2.0.0-dev11** (regla A6C nueva).

**Etiquetas:**
- **[E]** texto completo leído o fuente oficial.
- **[E-r]** solo resumen, agregador o acta.
- **[I]** inferencia o diseño propio.
- **[I-raza]** dato de otra raza, usado solo como método.
- **[NV]** sin verificar.

**Tipos de acceso:** TEXTO_COMPLETO, RESUMEN, AGREGADOR, CONGRESO, PREPRINT, COMERCIAL, PRENSA u OFICIAL. Las cifras
están parafraseadas; no se reproducen tablas completas.

## Decisiones tomadas sin supervisión
1. **Rama de partida:** el PR #89 (`claude/kb-estudio5-2026-11-19`) seguía sin fusionar, así que la rama
   `claude/kb-noche-2026-11-20` sale de él. No había rama de hoy.
2. **Auditoría:** se revisaron 11 fuentes que sostienen parámetros o reglas implementadas y que no tenían clasificación
   de acceso. Son Choi & Parkin 2025, Morrice-West 2020 y 2022, «Morrice-West 2023» (que en realidad es Wong 2023 en
   Front Vet Sci), Wong 2023 (EVJ), Witte 2006, Verheyen 2006, Carrier 1998, Estberg 1996, Schrurs 2024 y van Erck 2026.
3. **Temas nuevos:**
   - (a) la definición exacta del cociente de galope de Choi & Parkin, que era el pendiente de A6;
   - (b) cobertura de Asia y del Golfo para A9 (V200 y FC) y A11 (ECG);
   - (c) factores de riesgo del TFDS ligados a la carga, Latinoamérica y estudios publicados entre octubre y noviembre
     de 2026.
4. **Trabajo en paralelo:** cuatro subagentes. Dos hicieron la auditoría, uno cubrió Asia y el Golfo, y otro el TFDS,
   Latinoamérica y los estudios nuevos.
5. **Cambio del motor (el único de la noche):** se implementa la **regla A6C_COCIENTE_GALOPE**. La fórmula, las ventanas
   y la OR se leyeron en el texto completo de Choi & Parkin (sección 2.3 y tabla 2; PSI, Corea). Lo que es diseño
   propio se marca [I].
6. **No se cambia ninguna constante que ya estuviera implementada.** Las correcciones de la auditoría afectan a notas,
   atribuciones y evidencia. Dos de ellas (Verheyen y A8) quedan como pendientes, porque se apoyan solo en resúmenes o
   porque cambiarían una regla que ya funciona.
7. **Lectura descartada:** el subagente del TFDS leyó Ikeda 2019 en una copia que no era de J-STAGE ni de PMC. No se usa
   esa lectura: Ikeda conserva su clasificación anterior y su relectura desde J-STAGE pasa a la cola.
8. **Bloqueos:**
   - Desde la terminal no hay red: las API de Europe PMC, OpenAlex, Unpaywall y Semantic Scholar devuelven conexión
     rechazada.
   - PubMed y PMC piden reCAPTCHA de forma intermitente.
   - MDPI, Wiley y ResearchGate rechazan la lectura automática.
   - No se esquivó ningún bloqueo (ni caché, ni espejos) y no se usaron Sci-Hub ni LibGen.

---

## 1. Auditoría de fuentes

### 1.1 Choi & Parkin 2025: cociente de galope (A6, A6B y A6C)
Choi Y, Parkin T. *Equine Vet J* 2026;58(1):31–39 (en línea desde el 19/03/2025). doi 10.1111/evj.14493, PMID 40104935,
PMC12699112.
- **Contexto:** Corea del Sur (KRA, Seúl), artículo en inglés, PSI.
- **Acceso: TEXTO_COMPLETO** (PMC).
- **Diseño:** casos y controles, con 101 casos y 304 controles (319 eventos control) [E].

**Definición del cociente (sección 2.3, fórmula MathML) [E]:**
- Fórmula: (días de galope en los 60 días previos / días de galope en los 90 días previos) **+ 1**.
- El +1 va **fuera** de la fracción.
- Los recuentos son brutos: no se normalizan por la longitud de la ventana.
- Las dos ventanas están anidadas y terminan en la **fecha del último trabajo rápido**.
- El cociente va, por tanto, de 1 a 2. **≤ 1,6 equivale a g60/g90 ≤ 0,6** [I, álgebra].
- El artículo no dice cómo trata g90 = 0 ni cómo eligió el corte de 1,6 [E]. Con las ventanas acabadas en un trabajo
  rápido, g90 ≥ 1 siempre [I].

**Tabla 2, modelo final [E]** (confirma las cifras que ya tenía la KB):

| Variable | Categoría (frente a la referencia) | OR (IC 95 %) | p | Casos / controles |
|---|---|---|---|---|
| Días de galope en 60 d | ≤ 2 (frente a 3–24) | 1,842 (1,073–3,162) | 0,03 | — |
| Periodos ≥ 90 d sin trabajo rápido en 365 d | 1–2 (frente a 0) | 3,098 (1,737–5,526) | < 0,001 | — |
| Cociente | ≤ 1,6 (frente a > 1,6) | 2,190 (1,227–3,910) | 0,008 | 46/99 (referencia 55/220) |

**Otras definiciones [E]:**
- **Trabajo rápido** = galope de entrenamiento, *trial* y carrera.
- La KRA anota galope o canter, sin distancia ni velocidad.
- La equivalencia «día de galope = sesión rápida del motor» es **[I]**.

**Pendiente:**
- La tabla S1 (univariable) no se leyó [NV].
- El artículo hermano Bennet & Parkin 2025 (PMC12699123) está bloqueado. Por el agregador solo se sabe: 3,85 millones de
  salidas en Norteamérica y 1,49 lesiones mortales por cada 1.000 salidas [E-r].

### 1.2 Morrice-West 2022: modelo óseo A (`fuerza_vertical`, `curva_sn`, `rango_validado_sbfl_m_s`)
*Sci Rep* 12:11528, doi 10.1038/s41598-022-14274-y.
- **Contexto:** Tasmania (Tasracing y StrideMaster), 25.234 salidas, PSI.
- **Acceso: TEXTO_COMPLETO** (nature.com; leído en torno al 77 %, métodos completos).

**Ecuaciones confirmadas [E]:**
- **Ecuación 1:** F = 2,778 + 2,1376·v − 0,0535·v² (N/kg). Está tomada de Witte 2006; los autores dicen que cambiaron el
  signo del término constante.
- **Ecuación 2:** escala con la carga del ensayo (90 MPa) dividida entre 24,13 N/kg.
- **Ecuaciones 4 y 5:** σ = 134,2 − 14,1·log10(Nf).
- Se cuenta un ciclo por zancada.

**Corrección del rango:** 12,57–21 m/s son **criterios de exclusión de datos**, no un rango validado [E]. El motor lo
sigue usando como rango de cálculo [I].

**Saturación:**
- El vértice de la parábola está en 19,98 m/s, con 24,13 N/kg [I, cálculo].
- El artículo asocia 24,13 a la velocidad máxima de 20,99 m/s [E-r].
- Saturar en el vértice es una elección nuestra [I].

### 1.3 Witte 2006: frecuencia de zancada y fuerza (`frecuencia_zancada_modelo`)
Witte TH, Hirst CV, Wilson AM. *J Exp Biol* 209:4389.
- **Contexto:** Reino Unido, 9 PSI.
- **Acceso: TEXTO_COMPLETO** (PDF del editor).

**Datos [E]:**
- **Frecuencia de zancada (figura 5):** f = 1,7052 + 0,0305·v + 0,0004·v². **La fórmula es de Witte**, no de Anwar
  2026, que solo la reutiliza.
- **Fuerza (figura 7):** b0 = −2,778.
- **Rango de velocidades:** 9 a 17 m/s, con un máximo de 17,3. Por encima de unos 17 m/s, tanto la frecuencia como la
  fuerza son extrapolaciones [I].

### 1.4 «Morrice-West 2023» es en realidad Wong et al. 2023, *Front Vet Sci* 10:1260554 (`bandas_fraccion_v_carrera`)
Wong ASM, Morrice-West AV, Hitchens PL, Whitton RC.
- **Contexto:** Victoria (Australia), PSI.
- **Acceso: TEXTO_COMPLETO.**
- **Corrección de autoría:** la primera autora es Wong.
- **Diseño:** encuesta a 66 entrenadores sobre el trabajo **previsto**, cruzada con las lesiones en día de carrera de
  2013–2017. El análisis es a nivel de entrenador [E].

**Bandas absolutas [E]:** 13,3–14,3, 14,4–15,4, 15,5–16,7 y ≥ 16,8 m/s.

**Efectos, en IRR por km al mes [E-r]:**

| Velocidad | Población | IRR (IC 95 %) |
|---|---|---|
| 15,5–16,7 m/s | potros de 2 años | 0,76 (0,64–0,90) |
| 15,5–16,7 m/s | adultos | 0,92 (0,86–0,98) |
| 13,3–14,3 m/s | **adultos** | 1,08 (1,02–1,14) |

- **Corrección:** el «13,3–14,3 m/s favorece la lesión» corresponde a **adultos**, no a potros de 2 años. La tabla
  estaba mal alineada en la lectura, así que la asignación se apoya en el texto de resultados.
- **Las fracciones 0,80 y 0,93 de la v_carrera no aparecen en el artículo [E].**
  - Son diseño nuestro: 13,3/16,7 ≈ 0,80 y 15,5/16,7 ≈ 0,93 [I].
  - El valor implementado no cambia; la evidencia ya figuraba como «I».

### 1.5 Wong et al. 2023, *EVJ* 55(2):194–204: base de A7 y A8
doi 10.1111/evj.13581, PMID 35477925.
- **Contexto:** Tasmania (no Victoria ni Hong Kong), PSI.
- **Acceso: TEXTO_COMPLETO** (manuscrito aceptado en minerva-access).
- **Muestra [E]:** 584 caballos (146 casos y 438 controles) y 5.660 salidas, de 2011 a 2016.
- **Solo se analiza el último parcial de 200 m de carrera [E]:** media de 15,86 m/s (DE 0,89) y zancada de 6,88 m
  (DE 0,34).

**Efectos a lo largo de las salidas sucesivas [E]:**

| Variable | HR (IC 95 %) |
|---|---|
| Velocidad, por cada 0,1 m/s de caída | 1,18 (1,09–1,28) |
| Zancada, por cada 10 cm de caída | 1,11 (1,02–1,21) |

- La frecuencia de zancada no se asocia con la lesión.
- La caída se acentúa unas 6 carreras antes de la lesión; solo aparece en una figura [E].

**Consecuencias:**
- **A7:** 0,10 m es la **unidad** del HR, no un umbral observado. El umbral es diseño [I]. La documentación ya lo decía.
- **A8:** el estudio no respalda la ventana de 600 m en trabajo. La fuente usa los 200 m finales de carrera. Los 600 m
  y el umbral de 0,20 m/s son **[I]**.
- Se añade un pendiente: calcular también la velocidad de los últimos 200 m. A8 no se cambia esta noche.

### 1.6 Morrice-West 2020, *EVJ* 52(2):273–280 (`v_carrera_psi_m_s`)
doi 10.1111/evj.13156, PMID 31386764.
- **Contexto:** Victoria.
- **Acceso: TEXTO_COMPLETO** (manuscrito aceptado en minerva-access).
- **Muestra [E]:** 66 entrenadores y 1.720 caballos.

**Datos [E]:**
- Galope rápido de 13,3 a 18,2 m/s, en las mismas franjas que el punto 1.4. La franja de ≥ 16,8 m/s se llama
  «*race speed gallops*», sin definirla.
- 1,7 galopes por semana a los 2 años y 2 por semana a partir de los 3.
- Mediana de 8.000 m al mes a ≥ 13,3 m/s (RIC 6.400–12.000).
- 2,3 semanas de media entre salidas.

**Corrección:** el artículo **no** da 16,7 m/s como velocidad de carrera; es el límite superior de una franja. El valor
sigue en el motor (se ajusta por caballo con `v_carrera_m_s`), pero su evidencia pasa a **[I]**.

### 1.7 Verheyen 2006, *Bone* 39:1322 (A1 y A2)
PMID 16926125.
- **Contexto:** Reino Unido, PSI.
- **Acceso: RESUMEN** (editor).

**Vías probadas sin texto completo:**
- ScienceDirect: de pago.
- Bristol y RVC: solo ficha.
- ResearchGate: error.
- Tesis de la RVC de 2005 (EThOS uk.bl.ethos.418001): EThOS caído.
- Informe HBLB Prj 699: es de National Hunt, no de llano.

**Datos del resumen [E-r]:**
- 1.178 caballos y 148 fracturas.
- Riesgo especialmente alto en los que **superaron a la vez** 44 km de canter (≤ 14 m/s) **y** 6 km de galope
  (> 14 m/s) en 30 días.
- En 335 caballos que empezaron de añojos, el canter acumulado sube el riesgo y el galope acumulado es **protector**.
- Los aumentos rápidos de distancia en un mes o menos suben el riesgo.

**Consecuencias:**
- A1 y A2 por separado son derivadas [I].
- La regla combinada sigue PENDIENTE hasta leer las OR del texto completo.
- No se cambia la lógica (la evidencia es solo del resumen), pero queda en `pendiente_motor`.
- No hay límite inferior del canter en lo leído: el 0,40·v_carrera sigue siendo [I].

### 1.8 Carrier 1998 (A5) y Estberg 1996 (A3)
- **Carrier:** JAVMA 212:1582–1587, PMID 9604029. Acceso: AGREGADOR.
  - Diseño case-crossover [E-r].
  - RR 71 a los 10 días y 45 a los 21, **solo para el húmero** [E-r].
  - El descanso se define como ausencia de trabajos **oficiales cronometrados**, no de GNSS [E-r].
  - El DOI sigue sin confirmar.
- **Estberg:** PMID 8915427. Acceso: RESUMEN (Scilit).
  - 35 frente a 25 furlongs (unos 7,0 frente a 5,0 km) en 2 meses: riesgo 3,9 veces mayor (IC 2,1–7,1) [E-r].
  - Sin cambios respecto a la KB.

### 1.9 Schrurs 2024 y van Erck-Westergren 2026
- **Schrurs 2024** (*Animals* 14:1342, PMC11083884; Australia, PSI). Acceso: RESUMEN.
  - Vías bloqueadas: MDPI (permiso), PMC (reCAPTCHA), Worktribe y ResearchGate (error).
  - El rendimiento se predijo con el **tiempo** de los últimos 600 m hasta una meta virtual, clasificado de lento a
    rápido (p < 0,008) [E-r].
  - La recuperación de FC a 1 min no predijo el rendimiento (p = 0,21) [E-r].
  - **Las ventanas de 2 a 15 min no están en lo leído:** sus fuentes son Evans 1993 y el estudio extra; queda en la cola.
- **van Erck-Westergren 2026** (*JVIM* 40:aalag044; Hong Kong, PSI). Acceso: TEXTO_COMPLETO; se resume en el punto 2.2.

### 1.10 Resultado de la auditoría

| Fuente | Antes | Ahora | ¿Cambia la cifra? | Qué sostiene |
|---|---|---|---|---|
| Choi & Parkin 2025 | sin clasificar | **TEXTO_COMPLETO** | No; **fórmula del cociente cerrada** | A6, A6B, **A6C** |
| Morrice-West 2022 | sin clasificar | **TEXTO_COMPLETO** | No; 12,57–21 son criterios de exclusión | modelo A |
| Witte 2006 | sin clasificar | **TEXTO_COMPLETO** | No; la fórmula de frecuencia es de Witte, rango 9–17 m/s | frecuencia, fuerza |
| «Morrice-West 2023» | sin clasificar | **TEXTO_COMPLETO** | Atribución (Wong), IRR, adultos; 0,80/0,93 son [I] | bandas B1–B3 |
| Wong 2023 (EVJ) | sin clasificar | **TEXTO_COMPLETO** | Ámbito: Tasmania, 200 m de carrera; A8 en 600 m pasa a [I] | A7, A8 |
| Morrice-West 2020 | sin clasificar | **TEXTO_COMPLETO** | 16,7 m/s es límite de franja (evidencia → I) | v_carrera |
| van Erck 2026 | sin clasificar | **TEXTO_COMPLETO** | Nuevo umbral de prematuridad > 4 % y prevalencia | A11 |
| Verheyen 2006 | sin clasificar | RESUMEN | Umbral conjunto; galope protector en añojos | A1, A2 |
| Carrier 1998 | AGREGADOR | AGREGADOR | No; PMID confirmado, solo húmero | A5 |
| Estberg 1996 | RESUMEN | RESUMEN | No | A3 |
| Schrurs 2024 | sin clasificar | RESUMEN | Tiempo de 600 m categorizado; ventanas sin confirmar | A8, recuperación |

**Fuentes que pasan a texto completo: 7 de 11.** Las 4 que siguen bloqueadas están en `cola_investigacion` con las vías
ya probadas.

---

## 2. Asia y Golfo: A9 (V200 y FC) y A11 (ECG)

### 2.1 V200 y FC en PSI asiáticos
- **Corea:** Lee 2019 (*J Vet Clin* 36:62) y la tesis de Lee YW (Universidad de Jeju, en coreano).
  - Acceso: TEXTO_COMPLETO (tesis).
  - n = 11, protocolo de campo en arena (trote, canter y galope) [E].
  - Filtro de calidad: fuera las velocidades < 10 km/h y las FC más de 12 lpm por encima de la recta.
  - **V200 49,3 ± 4,3 km/h (13,7 m/s)**, VHRmax 57,4 ± 7,1 km/h y FCmáx 214 ± 11 lpm [E].
  - La V200 **no** se correlacionó con el rendimiento; la V140 y la VHRmax sí [E].
  - Sin repetibilidad.
  - El filtro de ±12 lpm es un buen candidato para limpiar la regresión FC–velocidad de A9 [I].
- **Japón (JRA):**
  - Kobayashi 2000 (AGREGADOR) [E-r]: V200 «reproducible» en condiciones constantes; sube un 11 % en 5 meses (de 623 a
    691 m/min); la afectan la pista y el jinete.
  - Kusunose 2002 (*J Equine Sci* 13:117), EquiPILOT fiable en pista [E-r]. Sin CV en el resumen; el PDF de J-STAGE
    no se pudo abrir (cola).
  - Mukai 2003 [E-r]: la FC submáxima es menor en los machos, una covariable para A9.
  - Mukai 2007 (carrera de 1.200 m) [E-r]: FC pico 213,6 lpm y lactato 22,5 mmol/L.
  - Hada 2007 [E-r]: la constante de tiempo de la recuperación baja con el entrenamiento; sin valores.
  - Mukai 2007 (desentrenamiento, n = 6) [E-r]: el VO2max por kg baja, pero el absoluto no cambia.
- **Ninguna fuente asiática da el error típico ni el CV de la V200 [NV].** La mejor referencia sigue siendo australiana:
  Vermeulen & Evans 2006, con diferencia media ≤ 2 % [E-r].
- **Davie 2026** (*Animals* 16:2187; Australia, cinta, 64 PSI) [E-r]:
  - ICC de la FC media del galope: 0,756.
  - ICC de la recuperación: 0,42 a 30 s, 0,50 a 60 s, 0,60 a 90 s y 0,57 a 120 s.
  - La recuperación antes de los 90 s es poco fiable y en A9 solo debe ser informativa [I].

### 2.2 ECG en ejercicio
- **Hong Kong, van Erck-Westergren 2026** (TEXTO_COMPLETO) [E]:
  - Muestra: 71 caballos, 405 ECG analizables de 506; Equimetre a 500 Hz.
  - **Fases:** la fase máxima es FC estable > 185 lpm, con duración media de 122 s; la recuperación lenta empieza por
    debajo de 120 lpm.
  - Exclusión con más de un 5 % de ruido.
  - **Prematuro = variación del RR > 4 %.**
  - **Prevalencia** (grupo de buenos resultados / grupo de malos):
    - al menos 1 latido ectópico en la fase máxima: 57 / 70 %;
    - al menos 3: 25 / 35 %;
    - pares: 12 / 18 %; tripletes: 5 / 7 %;
    - FA paroxística: 0,8 / 4,1 %;
    - P90 del recuento: 5 / 10 latidos.
  - OR 1,15 (1,04–1,28) de mala actuación por cada latido ectópico [E-r]. La OR de «cualquier latido» es incoherente en
    la fuente, así que no se usa.
  - **Consecuencias para A11 [I]:**
    - Tolerar unos pocos latidos aislados en la fase máxima sin alerta.
    - El umbral de prematuridad pasa a ser > 4 % (Hong Kong) frente a ≥ 5–6 % (Navas de Solis y Frick): queda como
      opción.
    - A11 sigue PENDIENTE: falta validarlo con galope real.
- **Japón:**
  - Ohmura 2017, en japonés (TEXTO_COMPLETO) [E]: 123 FA en 404.090 salidas (0,03 %); 5,8 veces más en carreras
    > 2.400 m que en ≤ 1.200 m; el 92,7 % revierte en 24 h.
  - Kiryu 1992 [E-r]: 5 caballos con deceleración brusca en carrera. Los 5 tenían extrasístoles ventriculares de
    esfuerzo y 3 tenían FA.
- **Reino Unido:**
  - Ryan 2005 (EVJ 37:265): los autores son de Newmarket, **no** de Australia como se creía. Cifras [NV].
  - Jose-Cunilleras 2006 [E-r]: el 62,5 % de los PSI con bajo rendimiento tuvo latidos prematuros, sobre todo en el
    primer minuto de recuperación.
- **Turquía, PSI y árabes:** Paksoy 2025 [E-r]. La troponina I sube tras una carrera de 1.400 m en las dos razas (PSI
  0,142 ng/mL, árabe 0,165). Es el único dato comparativo PSI–árabe de la noche, y es cardiaco pero no de ECG.

### 2.3 Golfo y resto de Asia
- **Golfo:** no hay ningún estudio de V200 ni de ECG en ejercicio en árabes de carreras de los EAU, Qatar, Arabia Saudí
  u Omán. Se buscó en inglés y en árabe (معدل ضربات القلب الخيول العربية السباق); solo aparece literatura de raid, que
  se descarta.
- **China (CNKI y Wanfang), India, Singapur y Malasia:** nada abierto.
- **Raza de Jeju (Ryu 2023), [I-raza], solo como método:** la reserva de FC se correlaciona con el tiempo de carrera
  (r = −0,63). Los valores no se trasladan.

---

## 3. TFDS, Latinoamérica y estudios nuevos

### 3.1 Factores de riesgo del TFDS ligados a la carga
- **Takahashi 2004** (JAVMA; Japón, JRA; RESUMEN) [E-r]:
  - 515 casos y 951 controles.
  - El riesgo sube con la distancia media de carrera y con el peso.
  - Las OR no aparecen en el resumen [NV].
- **Lam 2007** (AJVR; Hong Kong; RESUMEN) [E-r]:
  - 175 casos y 525 controles.
  - Más riesgo con más edad al importarse, más distancia poco después de la importación, más tiempo de entrenamiento
    y **menor** intensidad en los 180 días previos (posible causalidad inversa).
  - OR [NV].
- **Lam 2007** (EVJ) [E-r]: retirada por tendón del 3,2 % anual; el 97 % de las lesiones son del miembro anterior.
- **Ikeda 2019** (ya en la KB): la lectura de esta noche no se usa (decisión 7).
- **Conclusión [I]:** Choi (Corea) y Ikeda (Japón) penalizan la vuelta tras un parón de 90 días o más y la poca carga
  reciente, no solo el exceso. Es coherente con A6, A6B y A6C.
- **Árabes:** sigue sin haber OR publicadas de TFDS.

### 3.2 Latinoamérica (datos propios de cada población)
- **Argentina:**
  - Zambruno 2020 (JAVMA; RESUMEN) [E-r]: 283.193 salidas. La fenilbutazona antes de la carrera tiene OR 1,45 de lesión
    musculoesquelética.
  - Tesis MVM de Zambruno 2017 (Glasgow; TEXTO_COMPLETO, leído a medias) [E]:
    - entre 1,43 y 1,98 lesiones por cada 1.000 salidas;
    - césped frente a arena: OR 0,63 (0,50–0,79);
    - OR 1,06 por cada 100 m de distancia;
    - OR 1,07 por cada 10 kg de peso;
    - OR 0,87 por cada parón.
- **Uruguay:** Bimson 2022 (RESUMEN) [E-r]. 0,42 lesiones catastróficas por cada 1.000 salidas; el riesgo es mayor
  cuanto más tiempo pasa desde la carrera anterior.
- **Brasil:**
  - Berkman 2015 (Cidade Jardim; TEXTO_COMPLETO) [E]:
    - el entrenamiento superó la distancia de carrera en un 24,7 % (grupo de distancia corta) y un 40 % (larga);
    - el grupo de larga tuvo menor FC pico (p = 0,005) y mayor V200 (p = 0,012).
  - Watanabe 2006 (árabes en cinta; no consta que sean de carreras) [E]: lactato de 4,0 mmol/L a 8 m/s con un 6 % de
    pendiente.
- **Chile:** Trujillo 2012 (memoria de título; RESUMEN) usa FC45, V200 y recuperación, sin cifras [E-r].
- **México, Perú y Colombia:** no se encontraron estudios con cifras.

### 3.3 Estudios publicados entre el 1/10 y el 20/11/2026
- **Anwar et al. 2026** (*R Soc Open Sci* 13:260818, 7/10/2026) es la versión publicada del preprint del modelo B.
  - Leído en el preprint (CC BY), con acceso PREPRINT [E]. Daño máximo D* según el galope semanal:

    | Galope semanal | D* máximo |
    |---|---|
    | 1.733 m | 0,753 |
    | 2.667 m | 0,893 |
    | 3.787 m | 1,077 |
    | 4.720 m | 1,196 |

  - Dos descansos al año de 4, 6 u 8 semanas dan 0,992, 0,833 y 0,713 [E].
  - Bajar la carga solo 2 semanas, en lugar de descansar, acaba en fallo [E].
  - Falta comparar con la versión publicada antes de usar estas cifras (cola).
  - Es un modelo, **no una predicción de lesiones**.
- **Schild 2026** (J Vet Diagn Invest; California) [E-r]: 72 roturas del ligamento sesamoideo distal. Frente a los
  controles, más parón y menos trabajo rápido en el año previo.
- **Mizobe & Mita 2026** (JEVS; JRA) [E-r]: fracturas en pista de viruta en cuesta frente a llana, IRR 0,359.

---

## 4. Cambio del motor: regla A6C_COCIENTE_GALOPE
- **Fórmula:**
  - g60 y g90 = días distintos con sesión rápida en los 60 y 90 días que acaban en el último trabajo rápido, incluido
    ese día [E, el día de cierre es I];
  - cociente = g60/g90 + 1.
- **Condiciones para avisar:**
  - al menos 90 días de historia antes del último trabajo rápido;
  - alguna sesión en los últimos 7 días;
  - último trabajo rápido de hace 30 días o menos [I], porque A5 y A6 ya cubren las vueltas tras un parón;
  - cociente ≤ 1,6: **INFO · AVISO**.
- **Opciones:** `base_cientifica.cociente_galope_max` (1–2) y `dias_vigencia_cociente_galope` (1–365).
- **Salida JSON:** `cociente_galope {valor, dias_galope_60d, dias_galope_90d}`, o `null` si no se puede calcular.
- **Prueba nueva:** `kb.rule_gallop_ratio_60_90`, con valores de referencia calculados a mano:
  - galopes concentrados al principio: g60 = 3 y g90 = 8, cociente 1,375 → avisa;
  - galope cada 6 días: 10 y 15, cociente 1,667 → no avisa (sí avisa con un corte de 1,7);
  - sin 90 días de historia: `null`;
  - vigencia: a los 22 días avisa y a los 36 no; con 40 días de vigencia vuelve a avisar.
- **Validación:** pruebas locales con ASan y UBSan: 103 casos y 1.744 comprobaciones sin fallos. Release y
  `check_fixtures.py` en verde tras `--update`; las únicas diferencias son las versiones (los fixtures no tienen 90 días
  de historia).
- **NO VERIFICADO con caballos reales.** Es un factor asociado en un estudio de casos y controles, no una predicción de
  lesiones.

---

## 5. TABLA DE FUENTES

| Cita | DOI / URL | País | Idioma | Raza | Acceso | Qué sostiene |
|---|---|---|---|---|---|---|
| Choi & Parkin 2025, EVJ 58:31 | 10.1111/evj.14493 · PMC12699112 | Corea | en | PSI | TEXTO_COMPLETO | A6C (fórmula, OR 2,19); A6B; A6 |
| Bennet & Parkin 2025, EVJ | 10.1111/evj.14503 | EE. UU. y Canadá | en | PSI | AGREGADOR | contexto; cola |
| Morrice-West 2022, Sci Rep 12:11528 | 10.1038/s41598-022-14274-y | Australia (Tasmania) | en | PSI | TEXTO_COMPLETO | F(v), σ0, 12,57–21 m/s (exclusión) |
| Witte 2006, JEB 209:4389 | cob.silverchair.com (PDF del editor) | Reino Unido | en | PSI | TEXTO_COMPLETO | frecuencia de zancada; F(v) 9–17 m/s |
| Wong 2023, Front Vet Sci 10:1260554 | 10.3389/fvets.2023.1260554 | Australia (Victoria) | en | PSI | TEXTO_COMPLETO | bandas absolutas; IRR |
| Wong 2023, EVJ 55:194 | 10.1111/evj.13581 | Australia (Tasmania) | en | PSI | TEXTO_COMPLETO | A7 (HR 1,11/10 cm), A8 (HR 1,18/0,1 m/s, 200 m) |
| Morrice-West 2020, EVJ 52:273 | 10.1111/evj.13156 | Australia (Victoria) | en | PSI | TEXTO_COMPLETO | v_carrera (límite de franja) |
| Verheyen 2006, Bone 39:1322 | 10.1016/j.bone.2006.05.025 | Reino Unido | en | PSI | RESUMEN | A1, A2 (umbral conjunto) |
| Carrier 1998, JAVMA 212:1582 | PMID 9604029 | EE. UU. | en | PSI | AGREGADOR | A5 (húmero) |
| Estberg 1996, AJVR 57:1549 | 10.2460/ajvr.1996.57.11.1549 | EE. UU. | en | PSI | RESUMEN | A3 |
| Schrurs 2024, Animals 14:1342 | 10.3390/ani14091342 | Australia | en | PSI | RESUMEN | A8 (tiempo de 600 m) |
| van Erck-Westergren 2026, JVIM 40:aalag044 | 10.1093/jvimsj/aalag044 | Hong Kong | en | PSI | TEXTO_COMPLETO | A11 (> 4 %, fases, prevalencia) |
| Lee YW, tesis (Jeju) | repositorio de la Universidad de Jeju | Corea | ko | PSI | TEXTO_COMPLETO | A9 (V200 13,7 m/s, filtro ±12 lpm) |
| Kobayashi 2000, EVJ Suppl 30:159 | 10.1111/j.2042-3306.1999.tb05208.x | Japón | en | PSI | AGREGADOR | A9 (+11 % en 5 meses) |
| Kusunose 2002, J Equine Sci 13:117 | 10.1294/jes.13.117 | Japón | en | PSI | RESUMEN | A9 (fiabilidad) |
| Mukai 2003, J Equine Sci 14:93 | 10.1294/jes.14.93 | Japón | en | PSI | RESUMEN | A9 (sexo) |
| Mukai 2007, J Equine Sci 18:153 | 10.1294/jes.18.153 | Japón | en | PSI | RESUMEN | FC y lactato en carrera |
| Hada 2007, EVJ Suppl 36:141 | 10.1111/j.2042-3306.2006.tb05530.x | Japón | en | PSI | AGREGADOR | A9 (constante de recuperación) |
| Mukai 2007, EVJ Suppl 36:210 | 10.1111/j.2042-3306.2006.tb05541.x | Japón | en | PSI | AGREGADOR | desentrenamiento |
| Kiryu 1992, Jpn J Equine Sci 2:21 | 10.1294/jes1990.2.21 | Japón | en | PSI | RESUMEN | A11 (clínico) |
| Ohmura 2017, J Jpn Vet Med Assoc 70:270 | jvma-vet.jp | Japón | ja | PSI | TEXTO_COMPLETO | A11 (FA 0,03 %) |
| Ryu 2023, J Vet Clin 40:464 | 10.17555/jvc.2023.40.6.464 | Corea | en | caballo de Jeju | RESUMEN | [I-raza] método de reserva de FC |
| Paksoy 2025, Acta Vet Brno 94:97 | 10.2754/avb202594020097 | Turquía | en | PSI y árabe | RESUMEN | comparación cardiaca entre razas |
| Ryan 2005, EVJ 37:265 | 10.2746/0425164054530713 | Reino Unido | en | PSI | RESUMEN (cifras NV) | A11 (cola) |
| Davie 2026, Animals 16:2187 | 10.3390/ani16142187 | Australia | en | PSI | RESUMEN | A9 (ICC de la recuperación) |
| Jose-Cunilleras 2006, EVJ Suppl 36:163 | — | Reino Unido | en | PSI | AGREGADOR | A11 |
| Takahashi 2004, JAVMA 225:90 | 10.2460/javma.2004.225.90 | Japón | en | PSI | RESUMEN | índice tendinoso (dirección) |
| Lam 2007, AJVR 68:1188 | 10.2460/ajvr.68.11.1188 | Hong Kong | en | PSI | RESUMEN | índice tendinoso (dirección) |
| Lam 2007, EVJ 39:143 | 10.2746/042516407X159132 | Hong Kong | en | PSI | RESUMEN | tasa base del tendón |
| Zambruno 2020, JAVMA 257:642 | 10.2460/javma.257.6.642 | Argentina | en | PSI | RESUMEN | lesión (Argentina) |
| Zambruno 2017, tesis (Glasgow) | theses.gla.ac.uk/8585 | Argentina | en | PSI | TEXTO_COMPLETO | lesión por superficie, distancia y peso |
| Bimson 2022, JEVS 117:104074 | 10.1016/j.jevs.2022.104074 | Uruguay | en | PSI | RESUMEN | lesión catastrófica |
| Berkman 2015, Ciência Rural 45:1268 | 10.1590/0103-8478cr20140403 | Brasil | pt/en | PSI | TEXTO_COMPLETO | V200 y FC pico por distancia |
| Watanabe 2006, Arq Bras Med Vet Zootec 58:320 | SciELO | Brasil | pt | árabe (no consta de carreras) | TEXTO_COMPLETO | lactato en cinta |
| Anwar 2026, RSOS 13:260818 | 10.1098/rsos.260818 · arXiv 2603.22680 | Australia | en | PSI | PREPRINT | modelo B (D* por volumen y descanso) |
| Schild 2026, J Vet Diagn Invest | 10.1177/10406387261493577 | EE. UU. | en | PSI y Cuarto de Milla | RESUMEN | ligamento sesamoideo distal |
| Mizobe & Mita 2026, JEVS | 10.1016/j.jevs.2026.106157 | Japón | en | PSI | RESUMEN | superficie y pendiente |

## 6. Cobertura por regiones, idiomas y razas
- **Regiones:**
  - Asia: Japón, Corea y Hong Kong (con datos); China, India, Singapur y Malasia (sin resultados abiertos).
  - Oriente Medio: Turquía (con datos); EAU, Qatar, Arabia Saudí y Omán (sin estudios).
  - Oceanía: Australia (Tasmania y Victoria).
  - Europa: Reino Unido.
  - América del Norte: EE. UU. y Canadá.
  - América del Sur: Argentina, Uruguay, Brasil y Chile (con datos); México, Perú y Colombia (sin cifras).
- **Idiomas buscados o leídos:** inglés, español, portugués, japonés, coreano, árabe y chino (este último sin
  resultados).
- **Razas:**
  - PSI: casi todo.
  - Árabe de carreras: Paksoy 2025 (cardiaco, comparativo con el PSI). Sigue sin haber V200, ECG en ejercicio ni OR de
    tendón en árabes de carreras.
  - Árabe en cinta: Watanabe 2006, sin confirmar que sean de carreras.
  - Otras, solo como método [I-raza]: caballo de Jeju y Cuarto de Milla (Schild).
- **No se usó ningún dato de otra raza para un umbral del motor.**

## 7. Resumen
1. **Regla nueva A6C.** El cociente de galope de Choi & Parkin queda cerrado en el texto completo: (g60/g90) + 1, con
   las ventanas acabadas en el último trabajo rápido; ≤ 1,6 tiene OR 2,19. Implementado como aviso informativo en el
   motor 2.0.0-dev11.
2. **Auditoría de 11 fuentes; 7 pasan a texto completo.** No cambia ninguna constante implementada, pero sí su
   evidencia o su ámbito:
   - «Morrice-West 2023» es Wong 2023;
   - las bandas 0,80 y 0,93 son diseño propio;
   - 12,57–21 m/s son criterios de exclusión;
   - 16,7 m/s es un límite de franja;
   - la fórmula de frecuencia de zancada es de Witte;
   - el umbral de Verheyen es conjunto y el galope acumulado fue protector en añojos;
   - A8 se apoya en los 200 m finales de carrera (Wong), así que los 600 m son [I].
3. **ECG en Hong Kong:** se acepta como normal una variación del RR > 4 % y entre el 57 y el 70 % de los ECG con al
   menos un latido ectópico en la fase máxima. A11 deberá tolerar latidos aislados.
4. **V200:** en Asia no hay error típico publicado. La recuperación de FC es poco fiable antes de los 90 s (Davie 2026).
5. **Árabes de carreras del Golfo:** siguen sin series de V200, ECG ni tendón.
