# Estudio extra 19/11/2026: índice tendinoso, V200 y recuperación de FC, líneas base (CUSUM y shrinkage), playa y France Galop

**Base:** AVO_KB_1 1.2.0 → **1.3.0** · **Motor:** 2.0.0-dev4 → **2.0.0-dev5** · **Rama:** `claude/kb-estudio-2026-11-19`
(sale de `claude/kb-noche-2026-11-19`, PR #80, abierto y sin fusionar). Inicio: 08:45 UTC.

Etiquetas: **[E]** dato publicado leído en la fuente primaria; **[E-r]** dato publicado leído solo en el resumen
(PubMed reproducido en MadBarn o ficha del editor), no en el texto completo; **[I]** inferencia o cálculo propio;
**[NV]** sin verificar. Las cifras están parafraseadas; no hay citas literales largas.

## Decisiones del estudio (trabajo sin supervisión)

1. **Rama:** `claude/kb-estudio-2026-11-19` sale de la rama del PR #80, como se pidió. No se repiten sus temas
   (constantes del modelo B, tabla 2 de Choi & Parkin, Yildirim 2025, prevalencia de arritmias) ni los de los estudios
   del 17 y 18/11.
2. **Temas (cuatro, los que bloquean código):** (1) índice tendinoso con prioridad en árabes; (2) V200/VHRmax y
   recuperación de FC; (3) líneas base con shrinkage, TE/SWC y CUSUM; (4) línea base de la playa y datos de carrera de
   árabes en France Galop (IDF). Cuatro subagentes de investigación en paralelo y una quinta lectura independiente de
   verificación de las nueve cifras más importantes (todas confirmadas; matices en el texto).
3. **Pendiente del motor implementado (uno): las herramientas de línea base** (mediana + MAD_s, z robusto, shrinkage
   normal-normal, umbral de cambio real y CUSUM unilateral con FIR). Es el único tema con la evidencia cerrada: es
   matemática estándar y los ARL se han recalculado y coinciden con la tabla del NIST. **No se conecta a ninguna
   regla:** faltan TE propios por métrica y la superficie anotada. El resto (índice tendinoso, V200, IDF, playa) no
   tiene evidencia cerrada y queda en `pendiente_motor` con su propuesta.
4. No se tocan firmware, workflows, firmas, `Info.plist`, TestFlight ni contratos binarios. No hay informes de campo
   nuevos de los PROTOTIPOS.

---

## 1. Tendón flexor digital superficial (TFDS): qué se puede meter en un índice

### 1.1 Árabes de carreras

- **Polonia, Varsovia 2001–2006** — Kalisiak 2012, *Pol J Vet Sci* 15:111–118, doi 10.2478/v10181-011-0121-9 [E,
  texto completo]: de 187 caballos con lesión tendinosa ecográfica, **29 árabes y 158 PSI**; en árabes, TFDS en 24/29
  (**82,8 %**), todos en el anterior. **Vuelven a correr 4 de 26 árabes (15,4 %) frente a 55 de 133 PSI (41,4 %)**. En
  PSI, la vuelta baja del 51 % (lesión de 1–8 cm) al 10,5 % (≥ 13 cm). El 7,2 % de ligamento suspensor en árabes no
  cuadra con 5/29 (= 17,2 %): errata del original, no se usa.
- **Polonia 2000–2008** (Pieszka, Łuszczyński, Baranowska; revista sin confirmar) [NV]: lesiones de extremidad en
  ≈ 1,3 % de árabes frente a ≈ 2,3 % de PSI; sin desglose de tendón.
- **Qatar 2024–25** (póster de congreso, Pap 2026) [E-r]: el tendón explica el 40 % de los caballos que no volvieron a
  correr; sin desglose por raza.
- **No hay incidencia publicada de TFDS en árabes de llano por 1.000 salidas** (Francia, Emiratos ni Arabia) [I, tras
  la búsqueda]. Una tesis francesa (DUMAS) quedó bloqueada.
- **Consecuencia [I]:** el árabe se lesiona más del tendón (Yildirim 2025, ya en la base) y vuelve a correr mucho menos
  que el PSI. Para la cuadra pesa más evitar la lesión que gestionar la vuelta.

### 1.2 Factores de riesgo en PSI (dirección conocida, magnitud de PSI)

| Estudio | Hallazgo | Etiqueta |
|---|---|---|
| Perkins, Reid & Morris 2005, *NZ Vet J* 53:184 | 51 TFDS en 1.571 PSI; frente a 2 años, IRR 6,76 a los 4 años y 15,26 a ≥ 5; **sin asociación con la distancia de los 30 días previos**; más riesgo en preparaciones sin salidas | [E-r] (verificado) |
| Kasashima 2004, *EVJ* 36:346 | JRA: prevalencia de TFDS anterior 11,1 %; más a ≥ 3 años y en machos enteros | [E-r] |
| Reardon 2012, *Vet J* 195:325 (steeplechase) | 648 casos en 102.894 salidas; más riesgo con suelo firme, más edad, verano; menos con más salidas recientes | [E-r]; ≈ 6,3/1.000 salidas [I] |
| Reardon 2012, *EVJ* 44:564 (vallas) | Suelo firme, verano, edad al debut, **lesión previa del TFDS** | [E-r] |
| Lam 2007, *AJVR* 68:1188 (Hong Kong) | Los retirados por tendón habían trabajado a **menor** intensidad en los 180 d previos | [E-r]; OR bloqueadas |
| Ikeda 2019, *J Equine Sci* 30:93 | Pista embarrada, carrera más corta, mayor peso y bajada de peso | [E-r]; OR bloqueadas |

**Lectura de conjunto [I]:** Hong Kong, Reino Unido y Corea (Choi & Parkin) coinciden: el riesgo sube con el
**desentrenamiento y la reentrada**, no con «más kilómetros rápidos». Ningún estudio da una dosis-respuesta monótona
con la distancia a alta velocidad.

### 1.3 Biomecánica

- Deformación del TFDS in vivo al galope (Stephens 1989, *AJVR* 50:1089): **11,5 % y 16,6 %** en dos PSI montados
  (paso 3,1/7,6 %; trote 6,5/10,1 %), velocidad de deformación ≈ 200 %/s [E-r, verificado].
- Rotura ex vivo del TFDS de PSI: **25,3 ± 4,6 %** de deformación (n = 8), 121 MPa (Verkade, Back & Birch 2020, *EVJ*
  52:320, tabla 1) [E]. Margen de seguridad ≈ 1,5–2 [I].
- Fatiga de fascículos (Thorpe 2014, *Acta Biomater*): 1.800 ciclos al 10 % de deformación alargan el fascículo un
  5,5 % y suben la histéresis de 10,9 % a 16,8 % [E, manuscrito aceptado].
- **No hay curva S-N ni exponente de daño publicado para el tendón equino** [E: lo afirma Thorpe 2014; búsqueda].
  Por tanto, el término `T_carga = Σ(F/24,13)^m` del estudio ampliado **no tiene base** y se retira de la propuesta [I].

### 1.4 Marcadores ecográficos

- Beaumont 2025, *AJVR* 86(8), doi 10.2460/ajvr.24.09.0249 (**trotones franceses jóvenes**, no PSI) [E-r, verificado]:
  el área de sección (CSA) de tendones sanos sube **+6,8 %** a los 2 meses de entrenamiento; la de los que se lesionaron
  después, **+13 %**. Corte **≥ 9,84 %** (sensibilidad 100 %, especificidad 77,8 %; muestra muy pequeña).
- Avella 2009, *EVJ* 41:449 (National Hunt) [E-r]: la ecografía rutinaria **no predijo** las lesiones agudas.

### 1.5 Propuesta revisada del índice tendinoso (no implementada)

Bandas cualitativas, sin probabilidades [I]:

| Componente | Evidencia |
|---|---|
| Edad ≥ 3 años (árabe 3–4 años: grupo de más lesiones) | Perkins 2005, Kasashima 2004 [E-r]; Yildirim 2025 [E-r] |
| Reentrada tras ≥ 90 d y pocos días de galope en 60 d | A6 y A6B, ya en el motor (Choi & Parkin 2025) [E] |
| Lesión previa del TFDS | Reardon 2012 [E-r] |
| Suelo firme y verano (jun–sep) | Reardon 2012, Yildirim 2025 [E-r] |
| CSA ≥ +10 % en 2 meses (dato de ecografía introducido a mano) | Beaumont 2025 [E-r], validación débil |
| Fatiga en la sesión (caída de velocidad y zancada al final) | Butcher 2007, Thorpe 2014: plausible, **no validado** [I] |

Retirado: el exponente de carga y cualquier «Miner» del tendón. Falta: dónde guarda la app la lesión previa y la CSA, y
cómo se anota la firmeza del suelo. **Sigue PENDIENTE.**

---

## 2. V200, VHRmax y recuperación de la FC

### 2.1 Lo que sigue bloqueado
Vermeulen & Evans 2006 y Gramkow & Evans 2006 (EVJ Suppl 36) siguen sin texto completo (Wiley de pago). Gramkow usa
**trote y galope juntos** en la regresión [E-r]. La crónica de la AAEP 2005 (Vermeulen & Evans) da **+8 % de VHRmax y
+8,3 % de V200** tras 4 semanas de entrenamiento en 10 PSI [E-r, fuente secundaria]. El blog divulgativo de D. Evans
(autor de ambos) pide 5–6 galopes y FC submáxima a 8,3–12,5 m/s [E, divulgativo].

### 2.2 Retraso de la FC
- No hay una constante de tiempo de la FC en campo publicada para PSI [I, tras la búsqueda].
- En trabajo submáximo la FC hace un pico y se estabiliza a los **2–3 min**; en aceleración hasta el máximo no hay
  estado estable (Firshman 2010, revisión) [E-r]. Escalones de 3–5 min para estado estable (de Maré 2017) [E].
- PSI que galopa 400 m a 14,4 m/s: la FC media pasa de 125 a 201 lpm (Littlejohn & Snow 1988) [E-r]: en esfuerzos
  cortos la FC no llega a meseta.
- VO₂ (no FC): retraso ≈ 20 s y τ 10 s a 7 m/s, 20,7 s por encima del umbral de lactato (Langsetmo 1997) [E-r].
- En cinta, la regresión usa **los últimos 15 s de cada escalón** (Pagan et al., KER) [E].
- **Propuesta [I]:** usar solo mesetas de velocidad (CV < 5 %) de ≥ 30 s, descartar los primeros 20–30 s y promediar
  los últimos 15 s; no usar galopes cortos sin meseta para la recta.

### 2.3 Otras validaciones
- Kobayashi 2000, *EVJ Suppl* 30:159 [E-r]: 112 PSI de 2 años, V200 de ≈ 10,4 a 11,5 m/s en 5 meses.
- Poinsard 2026 (trotones, ya en la base): V200 = primer cruce de 200 lpm sostenido ≥ 10 s, **sin regresión**.
- **No hay SWC ni TE publicado de V200 en PSI de campo** [E: búsqueda negativa].

### 2.4 Recuperación
- Schrurs 2024 (ya en la base) da además **≈ 100 lpm a los 15 min** tras un galope fuerte [E].
- Evans, Harris & Snow 1993, *EVJ* 25:441 [E-r]: en cinta a 10 m/s, la **FC a los 4 min** correlaciona con el
  Timeform (r = −0,565); a 1, 3 y 5 min no.
- Witherington 1971, *EVJ* 3:99 [E-r]: tras carrera, FC media a los 3–5 min de 114 lpm; > 130 lpm en el 5,5 %.
- Recuperación biexponencial en ponis: fase rápida τ ≈ 15 s y lenta τ ≈ 455 s (Rugh 1992) [E-r].

### 2.5 Árabes de carreras
No hay V200 ni VHRmax de campo en árabes de llano. Alonso 2013 (5 árabes en cinta, no consta que fueran de carreras):
V200 7,4 → 7,8 m/s [E-r]. Janczarek 2016 (67 PA de Służewiec) solo da VFC [E].

**Decisión:** A9 sigue PENDIENTE. Se cierran como [E] la media de 5 s y la recta con trote + galope; el retraso, el R²
mínimo y el umbral de cambio siguen siendo [I]. Se añaden las ventanas de recuperación a 4 y 15 min.

---

## 3. Líneas base: robustez, shrinkage, TE/SWC y CUSUM (implementado como herramientas)

### 3.1 ARL del CUSUM (corrección de la base)
Cálculo propio con la cadena de Markov de Brook-Evans (300 estados, normal estándar) y contraste con la aproximación de
Siegmund y con la tabla del NIST/SEMATECH e-Handbook §6.3.2.3.1 [E]:

| δ (DE) | h = 4 | h = 4 con FIR h/2 | h = 5 | h = 5 con FIR |
|---|---|---|---|---|
| 0 (ARL0) | **335** (NIST 336) | 316 | **931** (NIST 930) | 896 |
| 0,5 | 26,7 | 20,2 | 38,0 | 28,7 |
| 1 | **8,4** | 5,3 | **10,4** | 6,3 |
| 2 | 3,3 | 2,0 | 4,0 | 2,4 |

- Los «168 y 465» que a veces se citan son del CUSUM **bilateral** (dos cartas): 336/2 y 930/2 [I, aritmética
  exacta]. El NIST da 30,0 para h = 5 y δ = 0,5; Markov y Siegmund dan 38: probable errata de la tabla [I].
- FIR (Lucas & Crosier 1982, arranque S0 = h/2) [NV: texto no leído; efecto calculado].
- **Falsas alarmas en la cuadra [I]:** 30 caballos × 4 métricas × 2 sentidos = 240 cartas; con h = 4, ≈ 0,7 falsas
  alarmas por jornada completa; con h = 5, ≈ 0,26. Al conectar el CUSUM a reglas, usar h = 5 o pedir confirmación.
- Con μ y σ estimados de pocas sesiones, el ARL0 real queda por debajo del nominal (Jones, Champ & Rigdon 2004, *J Qual
  Technol* 36:95) [E-r, sin cifras]; CUSUM autoiniciado de Hawkins 1987 [NV, no leído].

### 3.2 Robustez y shrinkage
- 1,4826 = 1/Φ⁻¹(0,75); el z modificado de Iglewicz & Hoaglin (0,6745·(x − m)/MAD) marca atípico con **|M| > 3,5**
  (NIST e-Handbook §1.3.5.17) [E]. El estudio ampliado usaba 3: se pasa a 3,5.
- Shrinkage normal-normal correcto (Efron & Morris 1975, *JASA* 70:311) [E] si σ² es la varianza **dentro** del
  caballo (TE²) y τ² la varianza verdadera **entre** caballos. Peso del dato propio = n·ICC/(1 + (n − 1)·ICC): con
  ICC 0,6, 0,60 (n = 1), 0,82 (n = 3) y 0,92 (n = 8) [cálculo]. El shrinkage solo pesa en las primeras 3–5 sesiones [I].
- **Umbral de cambio corregido [I]:** √2·TE es el ruido entre dos medidas sueltas; frente a la media de n sesiones es
  TE·√(1 + 1/n). Hopkins 2000 propone 1,5–2·TE [E]. Nuevo umbral: `max(2·TE·√(1 + 1/n), SWC)`.
- Los z del CUSUM se tipifican con la DE **dentro** del caballo, no con la DE de la cuadra [I].
- La ectopia (recuentos, fiabilidad pobre: Massie 2023) **no** va por CUSUM normal; necesita Poisson o regla de
  eventos [I].

### 3.3 Variabilidad publicada en caballos (para los TE por defecto)
- Recuperación de FC (trotones): MDC 26 lpm, ICC 0,60 (Poinsard 2026) [E-r] → TE ≈ 9,4 lpm si es un MDC95 [I].
- FC al galope en cinta (PSI): ICC 0,756; recuperación 30–120 s: ICC 0,42–0,60 (Davie 2026, *Animals* 16:2187) [E-r].
- Frecuencia de zancada GPS frente a IMU: precisión 0,0091 Hz por ensayo (Pfau 2022, *J Biomech* 145:111364) [E-r].
- Simetría con IMU al trote: ICC 0,73 diario y 0,65 semanal (Sepulveda Caviedes 2018, *EVJ* 50:513) [E-r].
- Motivo para buscar derivas lentas (Wong 2023, *EVJ* 55:194, 584 PSI) [E-r, verificado]: cada 10 cm menos de zancada,
  HR 1,11 (1,02–1,21) de lesión; cada 0,1 m/s menos, HR 1,18 (1,09–1,28); la caída se acelera en las ~6 carreras
  previas. Factor asociado, **no** predicción individual.
- No hay CUSUM publicado en caballos de carreras [I, tras la búsqueda]; en vacas lecheras, Veldhuis 2020 (*Front Vet
  Sci* 7:67) [E].

### 3.4 Lo implementado (motor 2.0.0-dev5, KB 1.3.0)
En `include/avo_eq/knowledge.h` / `src/knowledge/knowledge.cpp`:
`kb_robust_baseline` (mediana y MAD_s de las últimas N válidas), `kb_robust_z` (con suelo de escala), `kb_shrink_mean`,
`kb_change_threshold` y `kb_cusum_upper` (k 0,5, h 4 por defecto, FIR opcional, `min_samples`). Pruebas en
`tests/test_knowledge.cpp`: mediana 7,0 y MAD_s 0,1112; shrinkage 9,9484; CUSUM {0; 0,7; 1,7; 2,0; 3,1; 4,0; 4,6} con
alarma en la 7.ª; FIR y h = 5. **Ninguna regla las usa todavía** y la salida JSON del análisis no cambia (solo las
versiones).

---

## 4. Playa de Laredo y France Galop

### 4.1 Sí hay datos de playa (trotones, al trote)
Corrige el «no hay datos publicados» del estudio ampliado:
- **Chateau 2011**, *EVJ Suppl* 38:488, doi 10.1111/j.2042-3306.2010.00277.x [E-r, verificado]: 4 trotones en tres
  franjas de una misma playa. Impacto vertical **≈ 59 % menor en arena húmeda profunda que en la orilla húmeda firme**
  (25 km/h) y ≈ 95 % menor en arena seca profunda que en asfalto (15 km/h); frenado 50 % y 55 % menor. En lo blando,
  zancada más corta y más frecuente.
- **Crevier-Denoix 2011**, *EVJ Suppl* 38:544 [E-r, verificado]: humedad **19 %** en la franja firme y **13,5 %** en la
  profunda; 4 trotones a 7 m/s.
- Arena de picadero: humedad 17–21 % óptima, más tracción con más agua (Holt 2013, tesis) [E-r]; la resistencia a
  cizalla tiene un máximo a una humedad dada y las sondas TDR se alteran con la sal (Peterson 2012, *White Paper*
  Grayson-Jockey Club) [E].
- PSI a ≈ 16,5 m/s en tierra: dureza y humedad cambian la longitud de zancada hasta **0,186 m** (Pfau 2024, *Sensors*
  24:2441) [E-r], más que los 0,10 m asociados a lesión.
- Árabes de raid en arena profunda, a 20 km/h: SF 1,77 Hz y SL 3,14 m (Porzio 2025, *Vet Sci* 12:1028) [E]; solo
  referencia (raid, sin control).
- Önder 2022 (PMC9559003) [E, texto completo, verificado]: velocidades medias de árabes turcos 13,454 m/s en arena,
  14,217 en sintética y 14,344 en hierba. Los «≈ 0,9 m/s» de la base son la resta (0,89) [I]; se corrige la etiqueta.
- Galope de carreras en playa a 14–17 m/s: sin datos [NV].

### 4.2 France Galop publica parciales por 200 m y zancadas
- Aviso de France Galop (2/10/2020) [E]: informes de parciales y tracking (proveedor McLloyd) en Chantilly, Deauville y
  ParisLongchamp, y ficheros de Saint-Cloud. Un PDF por carrera
  (`www7.france-galop.com/Casaques/Tracking//AAAAMMDD{PISTA}{N}_last_times_fr.pdf`) con velocidad máxima, mejores
  200 m, últimos 600 m y, por caballo y tramo de 200 m, tiempo, km/h, posición y, en 2025, **«Nombre de foulées»**.
- Qatar Arabian Trophy des Pouliches 2025 (Saint-Cloud, 2.000 m), ganadora en 2'23"71 [E]: 400–200 m en 12,05 s con
  30 zancadas; 200 m–meta en 12,79 s con 31 [E] → **≈ 2,4–2,5 Hz y 6,5–6,7 m** [I]. Primer dato de frecuencia de
  zancada en árabes de carreras en la base. El tramo 600–400 m (27 zancadas, 2,06 Hz) es incoherente: error de conteo
  probable; tratar las zancadas con ±1 por tramo (3–4 %) [I].
- Comparación: PSI en el Arc 2025, 25 zancadas en 11,56 s → ≈ 2,16 Hz y 8,0 m [I].
- **IDF:** el dato existe y se puede calcular, pero solo hay PDF (sin API) y no se ha comprobado la cobertura de las
  carreras PA de provincias. Propuesta [I]: IDF = v(últimos 400 m)/v(carrera) (definición de la base) y, además,
  caída 400–200 → 200–meta (−5 % Al Ghadeer 2024, −6 % Subahiyah 2025). **Sigue PENDIENTE:** necesita un importador de
  PDF y el estado del terreno.

### 4.3 Línea base de la playa: qué registrar (propuesta, no implementada)
1. Franja por tramo: orilla firme mojada, húmeda suelta, seca profunda, transición [Chateau 2011 E-r → I].
2. Hora frente a bajamar y coeficiente de marea, horas desde la pleamar, lluvia de 24 h, viento; nota del jinete
   firme/media/blanda [I].
3. Línea base separada por franja para SF, SL, FC a velocidad fija y velocidad final; no mezclar con pista [I].
4. Umbral de zancada por encima de la variación debida al suelo (hasta 0,19 m, Pfau 2024) [I].
5. Opcional: deceleración vertical de la cincha como indicador de la dureza [I, sin validar].

---

## Resumen

- **Tendón:** sin dosis-respuesta ni curva de fatiga publicadas; el riesgo sube con edad, reentrada, lesión previa,
  suelo firme y verano. Los árabes vuelven a correr mucho menos (15 % frente a 41 %, Kalisiak 2012). Se retira el
  exponente de carga del índice; el índice sigue pendiente con componentes cualitativos.
- **V200:** cerrados la media de 5 s y la recta trote + galope; el retraso de la FC (≈ 20–30 s), el R² y el umbral
  siguen siendo inferencia. Recuperación a 4 min (r −0,57) y ≈ 100 lpm a 15 min como referencias. Sin V200 de campo en
  árabes de carreras.
- **Líneas base:** ARL recalculados (h = 4 → 335 unilateral; 168 era bilateral); z atípico a 3,5; umbral de cambio
  `max(2·TE·√(1 + 1/n), SWC)`. **Implementado** como herramientas del motor, sin conectar a reglas.
- **Playa:** Chateau y Crevier-Denoix 2011 dan datos reales de tres franjas de playa (trotones): la orilla es la franja
  dura. France Galop publica por 200 m y, desde 2025, zancadas: primer dato de frecuencia de zancada de árabes
  (≈ 2,4–2,5 Hz).
- **Motor:** KNOWLEDGE_VERSION 1.2.0 → 1.3.0; ENGINE_VERSION 2.0.0-dev4 → 2.0.0-dev5. Pruebas locales con ASan/UBSan:
  99 casos y 1.684 comprobaciones sin fallos; fixtures regeneradas (solo versiones). **NO VERIFICADO** con caballos
  reales. La fatiga ósea y el tendón son índices de carga, nunca predicciones de lesión.
- **Textos que hay que conseguir a mano:** Vermeulen & Evans 2006 y Gramkow & Evans 2006 (Wiley), Chateau 2011 y
  Crevier-Denoix 2011 completos (cifras de zancada en playa), Lam 2007 *AJVR* y Takahashi 2004 *JAVMA* (OR), Ikeda 2019
  (PMC6920055), Thorpe 2016, Hawkins 1987, Lucas & Crosier 1982, Hada 2007, la tesis francesa de DUMAS (A-2024-040) y
  Lejeune 1998.
