# Estudio horario 2026-11-20 21:08 UTC — Estado del terreno (going) como criterio de comparables y calentamiento / vuelta a la calma

**Base:** KB-1 1.22.0 → **1.23.0** · **Motor:** 2.0.0-dev24 → **2.0.0-dev25** (solo versiones; sin cambios de lógica)
**Rama:** `claude/kb-estudio-2026-11-20-2108`, encadenada desde `claude/kb-estudio-2026-11-20-2008` (PR #112, sin fusionar).

## Decisiones tomadas sin supervisión

1. **Encadenamiento:** el único PR `claude/kb-*` abierto era el #112 (20:08); la rama sale de él para heredar la KB 1.22.0
   y el motor dev24.
2. **Temas:** los pendientes que bloquean código (dt del modelo B, Zenodo, Verheyen, Choi & Parkin, ECG) llevan más de
   diez estudios bloqueados por las mismas webs (reCAPTCHA de PMC, Wiley, Zenodo sin permiso); repetirlos no aporta. Se
   eligen dos temas **no cubiertos** que afectan a criterios de comparables ya implementados o pendientes:
   - **A. Going / firmeza de la pista** (césped, tierra, sintética): la KB solo lo trataba para la playa (PL1–PL6) y como
     campo libre de `Session`. Afecta a A7/A8 (velocidad y zancada comparables) y a la carga ósea.
   - **B. Calentamiento y vuelta a la calma:** afecta a A9 (V200), a CF1–CF2 (cinética y recuperación de la FC) y a la
     segmentación de la sesión.
3. **Motor:** ningún pendiente con evidencia cerrada en texto completo para este tema; solo se suben versiones.
4. **Etiquetas:** las cifras [E] se leyeron en texto completo legal (PLOS, MDPI, Frontiers, Nature, repositorios RVC,
   Melbourne, UCLan, DergiPark, CORE) por un subagente con WebFetch; conviene cotejarlas con el PDF antes de usarlas como
   umbral. Las fuentes ya presentes en la KB se reutilizan por su id (regla AU1).

## Tema A — Estado del terreno (going)

| Hallazgo | Población | Fuente | Etiqueta |
|---|---|---|---|
| Muerte en el día de carrera, referencia Good/Standard: Good to firm OR 1,29 (1,02–1,63); Hard/Firm OR 1,40 (0,90–2,16, ns); Good to soft 0,81 y Soft/heavy 0,80 (ns); all-weather frente a césped OR 1,52 (1,19–1,95); 0,76 muertes/1000 salidas | PSI llano, Gran Bretaña 2000–2013, 806.764 salidas, 610 muertes | Rosanowski, Chang, Stirk & Verheyen 2018, *PLoS ONE* 13:e0194299, doi:10.1371/journal.pone.0194299 | [E] |
| Fractura distal en césped, referencia Good: Soft/heavy OR 0,64 (0,43–0,95); Good to firm OR 1,31 (1,04–1,65) en todas las salidas; all-weather OR 1,62 | Misma cohorte, 624 fracturas | Rosanowski et al. 2018, *EVJ*, doi:10.1111/evj.12968 (id `ROSANOWSKI_2018_AAM`) | [E] |
| Fracturas mortales/1000 salidas: tierra 1,79, sintética 1,15 (RR 0,64), césped 1,50 (RR 0,84); «off dirt» RR 1,05 (ns); «off turf» RR 0,50 (13 casos, impreciso) | PSI, EE. UU. y Canadá 2009–2014, 2,36 M salidas | Peterson et al. 2021, *Sustainability* 13:539 (id `PETERSON_2021_SUSTAINABILITY`) | [E] (texto con incoherencias de n) |
| Firm 2/Good 3 frente a Good 4: lesión del caballo OR 1,27 (1,14–1,41), muerte OR 1,73 (1,12–2,67) | PSI llano, Victoria, 213.569 salidas 2014–2018 | Morrice-West et al. 2025, *Front Vet Sci*, doi:10.3389/fvets.2024.1481016 (id `MORRICE_WEST_2024_PREPARACION`) | [E] |
| A igual velocidad, más zancadas por 200 m cuanto más blando (frente a sintética): Good 4 +0,05; Soft 5 +0,08; Soft 7 +0,29; Heavy 8 +0,44; Heavy 10 +0,64; −1,13 zancadas/200 m por m/s | PSI, Tasmania, 25.259 salidas, GPS + acelerómetro | Morrice-West et al., *EVJ*, doi:10.1111/evj.13370 (id `MORRICE_WEST_2020_VARIACION`) | [E] (manuscrito de autor) |
| Vida a fatiga subcondral consumida por salida (90 MPa): Good 3 10,0 %; Soft 5 9,5 %; Heavy 10 7,4 %; sintética 9,0 %: en blando pesa más la menor velocidad que el mayor número de zancadas | Misma población | Morrice-West et al. 2022, *Sci Rep* 12:11528 (id `MORRICE_WEST_2022`) | [E] |
| Índice de penetrómetro: verano mediana 4 y 16,7 m/s; invierno 10 y 15,1 m/s; relación cuadrática negativa velocidad–índice | PSI llano, Nueva Zelanda, 437.506 salidas | Legg et al. 2025, *EVJ*, doi:10.1111/evj.70003 (id `LEGG_2025_NZ`) | [E-r] |
| La amortiguación medida explica ≈ 82 % de la *going allowance* por tiempos; > ≈ 10 kN más firme no da más velocidad; GoingStick medio en llano: Firm 8,5 … Heavy 5,5; el going oficial coincide con el deducido del rendimiento solo en el 51 % en llano; CV entre puntos de un hipódromo 14,4 % | PSI, Gran Bretaña 2023–2024, 283 registros | Northrop, Hobbs et al. 2024, «Ground and Going Study», informe para The Racing Foundation (UCLan eprint 53458) | [E] |
| Artículo asociado: velocidad sube con la firmeza hasta ≈ 10 kN y luego se estabiliza | 50 reuniones, césped GB | Hobbs et al. 2024, *J Equine Vet Sci*, doi:10.1016/j.jevs.2024.105211 | [NV] (solo nota de prensa) |
| Pista de tierra a 16,5 m/s: longitud de zancada 6,60 (dura) a 6,71 m (media); diferencia máxima 18,6 cm; +0,36 m y +0,018 Hz por m/s | 12 PSI (*outriders*, no de carreras), Calgary | Pfau et al. 2024, *Sensors* 24:2441, doi:10.3390/s24082441 | [E] [I-raza: misma raza, otro uso] |
| GoingStick: penetración r = 0,41 con la amortiguación; cizalla sin correlación y 53/404 lecturas en el tope; humedad volumétrica r = −0,63 | Parcelas de césped, Michigan State | Schmitt et al. 2024, *Animals* 14:38, doi:10.3390/ani14010038 | [E] |
| Árabes de llano, Turquía: velocidad media 14,45 m/s en césped (847 carreras) frente a 13,52 m/s en tierra (2.240); la humedad no se cuantifica | 60 árabes, 3.087 registros 2007–2016 | Yıldırım 2019, *Kocatepe Vet J* 12:1, doi:10.30607/kvj.450350 | [E] (árabe de llano; diferencia calculada [I]) |
| JRA: en tierra las fracturas suben al empeorar el estado; en césped tienden a bajar | PSI JRA | Maeda, Hanada & Oikawa 2016 (id `MAEDA_2016_JRA`) | [E-r] |
| No existe una corrección oficial publicada en s/furlong; Timeform (privado) estima el going diario con 6–7 carreras | — | Timeform, «Computer Timefigures explained» | [E] (fuente comercial, no científica) |

**Lectura [I]:** la diferencia entre goings o superficies (≈ 0,9 m/s en árabes entre césped y tierra; ≈ 1,6 m/s entre
estaciones en Nueva Zelanda) supera con mucho los cambios de forma que AVO quiere detectar. El going oficial es poco fiable
(51 %) y el GoingStick tiene CV ≈ 14 % dentro de un hipódromo. Terreno firme = más riesgo (OR 1,3–1,7) y más fatiga ósea
por salida; terreno blando = zancada más corta a igual velocidad, que no es fatiga. Ningún dato de going en árabes de llano
de Polonia, Francia ni el Golfo [NV].

### Reglas propuestas (GO1–GO4, [I], sin implementar)

- **GO1:** comparables de A7/A8 solo dentro de la misma superficie (césped / tierra / sintética / playa por franja) y del
  mismo estrato de going (firme–bueno-firme / bueno / bueno-blando–blando / pesado); sin going registrado, confianza baja.
- **GO2:** zancada siempre a igual velocidad, con el going como covariable (modelo longitud ~ velocidad + going); una
  zancada más corta en blando o pesado no dispara aviso de fatiga ni de cojera.
- **GO3:** no confiar en la etiqueta oficial; guardar la descripción oficial y, si existe, penetración (no cizalla) del
  GoingStick o penetrómetro; a futuro estimar un going efectivo del propio caballo en un tramo de referencia.
- **GO4:** en terreno firme/bueno-firme, avisar de que una mejora de tiempos no implica mejor forma y sí más carga ósea
  (contexto para el modelo óseo; **nunca** predicción de lesiones).

## Tema B — Calentamiento y vuelta a la calma

| Hallazgo | Población | Fuente | Etiqueta |
|---|---|---|---|
| Calentamiento 5 min al 50 % VO₂max + 5 min al paso: aporte aeróbico 79,3 % frente a 72,4 % y menor déficit de O₂ (34,7 frente a 47,3 mL O₂eq/kg); sin cambio en el tiempo de carrera | 13 trotones, cinta, Australia | Tyler, Hodgson & Rose 1996, *EVJ* 28:117, doi:10.1111/j.2042-3306.1996.tb01602.x | [E-r] [I-raza] |
| 10 min al 50 % o 7 min + intervalos: constante de tiempo rápida del VO₂ −30 %; VO₂ pico igual; déficit de O₂ 65 y 63 frente a 82 mL/kg | 6 trotones, cinta | Geor, McCutcheon & Hinchcliff 2000, *AJVR* 61:638, doi:10.2460/ajvr.2000.61.638 | [E-r] [I-raza] |
| 1 min al 70 % o al 115 %, 10 min antes: VO₂ mayor y menos lactato en los primeros 60 s; más tiempo hasta la fatiga con el moderado que sin calentar | 11 caballos (grupo JRA), cinta | Mukai et al. 2008, *AJVR* 69:690, doi:10.2460/ajvr.69.5.690 | [E-r] (raza [NV]) |
| Igual distancia de calentamiento a 30/60/100 % VO₂max: el intenso da VO₂ inicial mayor y **FC mayor durante todo el sprint**; sin diferencia de tiempo | 9 PSI entrenados, cinta, JRA | Mukai et al. 2010, *EVJ Suppl* 38:33, doi:10.1111/j.2042-3306.2010.00227.x | [E-r] |
| El ejercicio previo mejora ≈ 2–3 % el rendimiento en ejercicio severo; protocolo óptimo sin definir | Revisión | Burnley & Jones 2005, *Equine Comp Exerc Physiol* 2:135, doi:10.1079/ECP200561 | [E-r] |
| FC sube al pasar por el túnel y al montar sin más ejercicio; 194 lpm en el galope hacia los cajones; 171 lpm en cajones | 23 PSI, carrera real JRA | Mukai et al. 2007 (id `MUKAI_2007_JES_CARRERA`) | [E-r] |
| Tests de campo estandarizan el calentamiento: PSI 1000 m de trote (Kobayashi 1999; Davie & Evans 2000); trotones 10 min a 300–350 m/min | Revisión de tests | de Mare et al. 2017, *Vlaams Diergeneeskd Tijdschr* 86 (core.ac.uk/download/84042571.pdf) | [E] (neerlandés) |
| Encuesta: trotones calientan más que PSI; en PSI la frecuencia respiratoria a 15 min es mayor tras el calentamiento corto; FC a 15 min mayor tras el largo (66 frente a 55 lpm, trotones) | 9 entrenadores PSI + 8 trotones, Suecia | Jansson 2005, *Equine Comp Exerc Physiol* 2:219, doi:10.1079/ecp200572 | [E-r] |
| Vuelta a la calma: trote 15 min + paso 15 min o paso 30 min bajan el lactato más rápido que estar de pie; FC distinta a 10 min, igual a 20–30 min | 5 trotones, cinta | Lovell & Rose 1995, *EVJ Suppl* 18:188, doi:10.1111/j.2042-3306.1995.tb04916.x | [E-r] [I-raza] |
| 30 min al paso frente a 90 min de pie tras carrera simulada: lactato y ácido-base vuelven antes; la mayoría de índices basales a 60 min | 6 PSI, cinta | Hubbell et al. 1997, *AJVR* 58:1003 (PMID 9285005) | [E-r] |
| 10 min de recuperación: pasiva, paso, trote lento, trote rápido (65–70 % FCmáx); FC y lactato bajan más cuanto más intensa; los entrenadores recuperan al 40–50 % FCmáx | 37 trotones, campo, Francia | Dahl, Cotrel & Leleu 2006, *EVJ Suppl* 36:102, doi:10.1111/j.2042-3306.2006.tb05522.x | [E-r] [I-raza] |
| 10 min al paso frente a vibración o parado: lactato igual (p = 0,35); FC mayor al paso | 8 mestizos, cinta, Brasil | Carvalho et al. 2025, *Front Vet Sci* 12:1538195, doi:10.3389/fvets.2025.1538195 | [E] (parcial) |
| Práctica: «algunos minutos» de paso o caminador antes; ≈ 15 min de caminador y manguera después | Cuadras de Queensland | Mactaggart & Phillips 2023, *Animals* 13:282, doi:10.3390/ani13020282 | [E] (parcial) |

**Lectura [I]:** casi toda la evidencia es de cinta y de trotones; en PSI solo la JRA (Mukai 2008/2010, Hubbell 1997). No se
ha publicado el efecto del calentamiento sobre la V200 de campo [NV], pero Mukai 2010 muestra que un calentamiento más
intenso **sube la FC a igual esfuerzo**, es decir, desplaza la relación FC–velocidad: un calentamiento distinto contamina A9.
La vuelta a la calma activa mantiene la FC más alta pero acelera el aclarado del lactato, así que la recuperación de la FC
(CF2) solo es comparable con la misma clase de vuelta a la calma. Nada en árabes de llano [NV].

### Reglas propuestas (WU1–WU4, [I], sin implementar)

- **WU1:** una meseta solo cuenta para V200 si antes hubo ≥ 1000 m o ≥ 10 min de paso/trote (estándar de los tests de PSI);
  las anteriores se marcan «sin calentar».
- **WU2:** detectar la fase de calentamiento (inicio hasta el primer tramo ≥ 10 m/s o FC ≥ 80 % de la máxima durante ≥ 15 s)
  y guardar duración, distancia por aire y FC media; marcar la FC alta sin velocidad (excitación, Mukai 2007).
- **WU3:** comparar V200 y recuperación de la FC solo entre sesiones con calentamiento parecido (diferencia ≤ 20 % en
  duración o distancia; el 20 % es diseño).
- **WU4:** la recuperación de la FC empieza cuando la velocidad baja del 50 % del pico; los primeros 10 min se clasifican en
  parado / paso / trote y solo se compara dentro de la misma clase.

## Fuentes bloqueadas o no conseguidas

PMC5048355 y PMC10967340 (reCAPTCHA); PMC12699123 y PubMed 31386764 (permiso caducado); PDF de Hobbs 2024 en
knowledge.lancashire.ac.uk (permiso caducado); Cambridge (Jansson 2005); Parkin 2004 sin PDF en Enlighten; Ely 2009 no
localizado; Hong Kong (humedad del césped y lesiones) no localizado.

## Resumen

- **Going:** terreno firme = más riesgo (OR 1,29–1,73, Rosanowski 2018 y Morrice-West 2025 [E]) y más fatiga ósea por salida
  (Morrice-West 2022 [E]); blando = más zancadas a igual velocidad (Morrice-West [E]); el going oficial solo acierta el 51 %
  (Northrop 2024 [E]); árabes 14,45 m/s en césped frente a 13,52 en tierra (Yıldırım 2019 [E]). Propuesta GO1–GO4 [I].
- **Calentamiento:** acelera la cinética del VO₂ y sube la FC a igual esfuerzo (Mukai 2010 en PSI [E-r]); sin datos de su
  efecto en la V200 de campo [NV]. Vuelta a la calma activa: lactato más rápido, FC más alta. Propuesta WU1–WU4 [I].
- Sin cambios de lógica; nada probado en CI más allá de versiones y **nada verificado con caballos reales**.
