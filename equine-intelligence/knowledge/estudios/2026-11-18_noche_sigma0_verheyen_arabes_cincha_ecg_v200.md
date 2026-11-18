# Investigación nocturna 18/11/2026: σ0, Verheyen, árabes, cincha, ECG y V200

**Base:** AVO_KB_1 1.0.0 → **1.1.0** · **Motor:** 2.0.0-dev2 → **2.0.0-dev3** · **Rama:** `claude/kb-noche-2026-11-18`
(sale de `claude/base-cientifica-cuadra`, PR #74, que sigue sin fusionar).

Etiquetas: **[E]** dato publicado leído en la fuente primaria o en su resumen; **[E-r]** resumen leído en un espejo
(MadBarn, índices), no en la editorial; **[I]** inferencia o cálculo propio; **[NV]** sin verificar.
Todas las cifras están parafraseadas; las citas literales son de pocas palabras.

## Decisiones de la noche (trabajo sin supervisión)

1. **Rama:** no había ramas `claude/kb-noche-*` ni PR nocturnos abiertos; el PR #74 (KB-1) sigue abierto, así que la
   rama de hoy sale de `claude/base-cientifica-cuadra`.
2. **Temas:** seis, por orden de bloqueo de código: σ0 y modelo B (Pan/Anwar); definición de canter de Verheyen 2006;
   velocidades de árabes de carreras; aceleraciones y zancada en la cincha; ECG en ejercicio (A11); V200 y últimos
   600 m (A8, A9). Se repartieron entre subagentes de investigación en paralelo; los textos completos que no se
   pudieron abrir se dicen en cada apartado.
3. **σ0 se queda en 134,2 MPa** en el modelo A (sin cambio de parámetro). Motivo en el apartado 1.
4. **Reglas A1 y A2 sin cambio en el código.** El resumen de Verheyen sugiere que los dos umbrales actúan juntos, pero
   sin el texto completo la evidencia no está cerrada (apartado 2).
5. **v_carrera del árabe se queda en 14,5 m/s.** Los datos nuevos lo sitúan entre el corredor medio y la élite; no se
   cambia hasta tener carreras propias de la cuadra (apartado 3).
6. **Pendiente del motor de esta noche (uno):** la **velocidad de los últimos 600 m** de cada trabajo, con la
   definición de Schrurs 2024 leída en el texto completo. Solo la métrica; la regla A8 sigue **PENDIENTE** porque no
   hay umbral publicado ni línea base de la cuadra.
7. No se tocan firmware, workflows, firmas, `Info.plist`, TestFlight ni contratos binarios. No hay informes de campo
   nuevos de los PROTOTIPOS en el repositorio desde el 17/11.

---

## 1. σ0 y el modelo óseo B (Pan 2025, Anwar 2026)

**Fuentes leídas:** Anwar et al. 2026 en arXiv ([2603.22680v1](https://arxiv.org/html/2603.22680v1)) y el preprint
de Pan et al. 2025 ([bioRxiv, PDF](https://www.biorxiv.org/content/10.1101/2025.04.06.646486.full.pdf)); en este
último las ecuaciones y la tabla 1 son imágenes, así que solo se tienen las cifras del texto. **No leídos:** versión
final de RSOS y de JRSI (PMC12483640, bloqueado) y el texto completo de Martig 2013 (solo el resumen).

### Origen de 134,2 y de 139,0
- **Martig et al. 2013** (Bone 57:392–398) [E-r, resumen en
  [MadBarn](https://madbarn.com/research/compressive-fatigue-life-of-subchondral-bone-of-the-metacarpal-condyle-in-thoroughbred-racehorses)]:
  - ensayo de compresión cíclica del hueso subcondral del cóndilo del MC3 a **54, 66, 78 y 90 MPa** (unas 5–6
    probetas por nivel);
  - curva principal **σ = 112,2 − 9,6·log10 Nf (R² 0,52)**;
  - curva de **sensibilidad**, sin los 3 caballos con más lesión subcondral: **σ = 134,2 − 14,1·log10 Nf (R² 0,72)**.
    De esta sale la Nf del motor;
  - medianas de ciclos hasta el fallo: unos 224.000 a 54 MPa y unos 4.000 a 90 MPa; módulo inicial E0 ≈ 2.500 MPa.
- **Pan et al. 2025** [E, preprint]: parten de 134,2 MPa, pero para reproducir los datos de fractura **suben σ0 a
  139,0 MPa**, lo que equivale a reducir un 54,5 % la tasa de formación de daño; lo atribuyen a que in vivo los tejidos
  de alrededor disipan parte de la carga.
- **Anwar et al. 2026, tabla 9** [E]: σ0 = 139,0 MPa (fuente Pan) y σ1 = 14,1 MPa (fuente Martig).
- Comprobación [I]: 10^(−4,8/14,1) = 0,457 → un 54 % menos de daño por ciclo. Cuadra.

**Conclusión.** 139,0 **no es una errata ni otra unidad**: es la calibración in vivo del modelo B (con adaptación y
reparación). 134,2 es la curva in vitro de sensibilidad, la que usa Morrice-West 2022 en el modelo A (Miner sin
reparación) con el que se publicó el 9,34 % de media por carrera. **Decisión:** el modelo A sigue con 134,2 por
coherencia con Morrice-West 2022; 139,0 se reserva para el modelo B. La opción `sigma0_mpa` ya permite comparar
(1.200 m a 16,7 m/s: 8,64 % con 134,2 y 3,94 % con 139,0, valores de prueba del motor). El estado [NV] de 139,0
pasa a **[E]**.

**Corrección:** el «rango 54–90 MPa» de `sigma_max_mpa` no es un rango de σ_max: son los **cuatro niveles del ensayo
de Martig** [E-r]. Pan usa σ_max = 90 MPa en entrenamiento rápido y carreras, y **30 MPa como aproximación del
reposo** [E, preprint]. Se corrige la nota en `base_cientifica.json` y en el comentario de `knowledge.h` (sin cambio de
cálculo).

### Ecuaciones del modelo B (apéndice A de Anwar, tomado de Pan) [E]
```
Adaptación:  df_BM/dt = (A_OBL − A_OCL)·α·S_v
             S_v = a·√(1−f_BM)·[1 − b·(1−f_BM)]
             A_OBL, A_OCL: funciones de Hill del estímulo ψ = σ²/(2E)
             E = E0·ε̇^γE·f_BM³
Daño:        dD*/dt = D'_f − D'_r
             D'_f = v_D(σ)·v_n,   v_D(σ) = 10^((σ−σ0)/σ1)·E_nom/E
             D'_r = [A_OBL + (F_s−1)·A_OCL]·α·S_v·D*/f_BM
Entrada:     F_g = 2,778 + 2,1376·s − 0,0535·s²;  σ = σ_max·F_g/24,13
             ε̇ = 0,01548·s + 0,0004955·s²;  f = 1,7052 + 0,0305·s + 0,0004·s²;  v_n = d·f/s
Constantes:  E_nom = 1.714,1 MPa; E0 = 2.500 MPa; α = 0,19; F_s = 5; γE = 0,06; a = 11,42 mm⁻¹; b = 0,02;
             γC = 2; δC = 1,0 MPa; A_OCL_min = 0,001 mm/día
```
- **Región ósea:** volumen de interés del **cóndilo lateral del MC3** (margen articular del cóndilo lateral medio en
  Pan) [E]; f_BM es su fracción de volumen óseo.
- **Faltan** [NV]: A_OBL_min/max, δ_B, γ_B y A_OCL_max (resto de la tabla 9 de Anwar y tabla 1 de Pan). **Sin ellos
  el modelo B no se puede implementar**: sigue en `pendiente_motor`.

### Resultados de reposo útiles para la capa 2 (planificador) [E, Anwar 2026]
| Escenario | Daño máximo D* |
|---|---|
| 2 reposos/año de 4 semanas | 0,992 |
| 2 reposos/año de 6 semanas | 0,833 |
| 2 reposos/año de 8 semanas | 0,713 |
| 1 reposo/año | 1,543 |
| 3 reposos/año | 0,799 |
| 1 reposo/año + bajada de intensidad de 4 semanas | 0,946 |

Anwar da 0,852 en la discusión y 0,911 en la tabla 7 para dos reposos al año: incoherencia del propio artículo [E].
Pan [E, preprint]: D* llega a ~0,90 al acabar la primera preparación; un reposo de ~6 semanas no repara del todo; la
f_BM sube ~0,05 en 100 días de entrenamiento y baja ~0,13 en 100 días de reposo; casi todo el daño viene de ≥13,8 m/s.
Son simulaciones de PSI: **índices relativos**, no predicción de lesiones.

## 2. Verheyen 2006: definición de canter y galope

**Texto completo no accesible** (ScienceDirect y PubMed sin respuesta, Europe PMC bloqueado por el proxy). Leído el
resumen completo en un índice ([ISC](https://search.isc.ac/inventory/10/496090.htm)) y contrastado con la
[ficha de Bristol](https://research-information.bris.ac.uk/en/publications/exercise-distance-and-speed-affect-the-risk-of-fracture-in-raceho/) (PMID 16926125).

- Cohorte de **1.178 PSI** con ejercicio diario registrado hasta 2 años y **148 fracturas** por ejercicio; estudio de
  casos y controles anidado [E].
- **Definiciones del resumen:** canter **≤ 14 m/s**, galope **> 14 m/s** [E]. **No hay límite inferior** del canter
  en el resumen ni se dice cómo se convertían a m/s los diarios de los entrenadores [NV].
- **Umbral:** el resumen habla de los caballos que superaron **44 km de canter y 6 km de galope** en 30 días [E].
  La conjunción «y» sugiere una **interacción** de ambas distancias y no dos umbrales independientes [I]. Equivalen a
  unos **7.700 ciclos de canter y 880 de galope** [E].
- En el subgrupo seguido desde *yearling* (335 caballos, 56 fracturas), el canter acumulado aumentó el riesgo y el
  **galope acumulado fue protector** [E]. Los aumentos bruscos en periodos de hasta un mes también lo aumentan [E].
- Estudios de la misma cohorte [E-r]: Verheyen & Wood 2004 (1,15 fracturas por 100 caballos-mes, 78 % entrenando);
  Verheyen et al. 2006 Prev Vet Med (pelvis y tibia: a 30 días el riesgo sube con el canter hasta un pico de ~50 km
  y baja después; a 60 días no hay asociación); Verheyen et al. 2005 (periostitis dorsometacarpiana en potros).
- Morrice-West 2020 (manuscrito aceptado) [NV]: volumen típico del Reino Unido de ~26,8 km/mes de canter y
  ~2,8 km/mes de galope; en Verheyen 2005 el corte sería **13,4 m/s**, no 14.

**Decisión.** El motor mantiene canter ≤ 14 m/s y galope > 14 m/s [E]. A1 (canter > 44 km → LIMITAR) y A2
(galope > 6 km → LIMITAR) siguen independientes: rebajarlos a AVISO cuando solo se cumple uno reduciría la cautela
sin evidencia cerrada. **Pendiente nuevo:** regla combinada A1+A2 y posible rebaja de los umbrales aislados, cuando se
lea el texto completo (ORs por categoría y cortes). El límite inferior del canter (0,40·v_carrera ≈ 6,7 m/s en PSI)
sigue siendo [I].

## 3. Árabes de carreras: velocidades de Gr1 PA

**Bloqueados:** PDF de tracking de France Galop (403 del proxy). Sustitutos: tracking de Equidia (datos de France Galop)
y parciales oficiales de Jour de Galop. Velocidades medias [I] = distancia oficial / tiempo oficial [E].

| Carrera | Fecha | Distancia | Tiempo [E] | Terreno [E] | v media [I] |
|---|---|---|---|---|---|
| Qatar Arabian World Cup Gr1 PA, Longchamp | 01/10/2023 | 2.000 m césped | 2:12.17 | bueno-blando | 15,13 m/s |
| QAWC Gr1 PA | 06/10/2024 | 2.000 m | 2:16.03 | muy blando | 14,70 m/s |
| QAWC Gr1 PA | 05/10/2025 | 2.000 m | 2:13.81 | muy blando | 14,95 m/s |
| Dubai Kahayla Classic Gr1 PA, Meydan | 30/03/2024 | 2.000 m arena | 2:13.87 | rápida | 14,94 m/s |
| Dubai Kahayla Classic | 05/04/2025 | 2.000 m arena | 2:12.65 | rápida | 15,08 m/s |
| Dubai Kahayla Classic | 28/03/2026 | 2.000 m arena | 2:17.32 | rápida | 14,56 m/s |
| UAE President's Cup Gr3 PA, Służewiec | 09/2025 | 2.000 m césped | 2:12.80 | — | 15,06 m/s |
| Derby árabe polaco, Służewiec | 07/2021 | **3.000 m** | 3:31.7 | blando | 14,17 m/s |

Fuentes: Sky Sports (resultados QAWC
[2023](https://www.skysports.com/racing/results/full-result/1184879/parislongchamp/01-10-2023/qatar-arabian-world-cup-arab-group-1),
[2024](https://www.skysports.com/racing/results/full-result/1264453/parislongchamp/06-10-2024/qatar-arabian-wold-cup-arab-group-1),
[2025](https://www.skysports.com/racing/results/full-result/1339672/parislongchamp/05-10-2025/qatar-arabian-world-cup-arab-group-1)
y Kahayla
[2024](https://www.skysports.com/racing/results/full-result/1221493/meydan/30-03-2024/race-1-dubai-kahayla-classic-group-1-dirt),
[2025](https://skysports.com/racing/results/full-result/1299441/meydan/05-04-2025/race-1-dubai-kahayla-classic-sponsored-by-zabeel-feed-arab-group-1-dirt),
[2026](https://www.skysports.com/racing/results/full-result/1357096/meydan/28-03-2026/race-1-dubai-kahayla-classic-sponsored-by-zabeel-feed-mill-arab-group-1-dirt)),
Equidia ([2023](https://www.equidia.fr/courses/2023-10-01/R1/C3), [2024](https://www.equidia.fr/courses/2024-10-06/R1/C4),
[2025](https://www.equidia.fr/courses/2025-10-05/R1/C4)),
[Gulf Today](https://www.gulftoday.ae/sport/2025/09/30/wathnan-racings-haseef-gallops-to-glory-at-uae-presidents-cup-in-warsaw),
[Polskie Araby](https://polskiearaby.com/en/races-sport/37732-the-arabian-derby-the-force-was-with-alsahr).

- **Parciales oficiales QAWC 2023** [E, [Jour de Galop](https://jourdegalop.com/2023/10/qawc-01-10-gb)]: los primeros
  1.000 m a ~14,3 m/s [I] y los últimos 200 m en 11,99 s (~16,7 m/s) [I]: final en aceleración progresiva.
- **Tracking del ganador** (Equidia; la página avisa de que no está sincronizado con el crono oficial) [E]:
  velocidad máxima 17,9 / 17,6 / 16,8 m/s (2023 / 2024 / 2025) y últimos 600 m a ~16,5 / 16,3 / 15,9 m/s [I].
- **Población** [E, [Önder et al. 2022, Animals 12:2630](https://mdpi.com/2076-2615/12/19/2630), Turquía,
  233.491 registros]: velocidad media de carrera de todos los participantes **14,34 m/s en césped**, 14,22 en arena
  sintética y 13,45 en arena.
- **Corrección:** los «14,2 m/s de las carreras polacas de 2.000 m» de la base 1.0.0 son en realidad del **Derby de
  3.000 m** (Alsahr 2021); en 2.000 m, Służewiec da ~14,7–15,1 m/s [I].
- No se encontraron datos de **frecuencia de zancada en árabes de carreras** [NV]; ni el programa AFAC/IFAHR 2026.

**Decisión [I].** Ganadores de Gr1 PA en 2.000 m: 14,6–15,1 m/s (mediana ~14,95); media de población en césped:
14,34 m/s. El 14,5 m/s por defecto queda entre ambos y sirve para un corredor medio; un árabe de élite debe usar
`v_carrera_m_s` ≈ 14,9. Sin cambio de código.

## 4. Cincha: aceleraciones del tronco y zancada

**Resultado principal:** **no hay ninguna fuente primaria accesible con picos de aceleración en g del tronco, la
cincha o el esternón a ≥ 12 m/s**. Witte 2004 y 2006 llevan los acelerómetros en el casco; Pfau 2006 y Barrey 2001 a
texto completo no se pudieron leer; PMC bloqueado por captcha.

- **Rangos usados por otros grupos [E]:** IMU en T4–T6 a **±10 g**, 250 Hz y filtro de 50 Hz (Parsons, Pfau & Wilson
  2008, [JEB 211:945](https://cob.silverchair.com/jeb/article-pdf/211/6/945/1265211/jeb006692p945.pdf));
  EquiMoves **±16 g** + ±400 g para impactos, hasta 1 kHz al galope ([Bosch 2018](https://www.mdpi.com/1424-8220/18/3/850));
  StrideSAFE en la manta a **±16 g** y 800 Hz ([WEVA 2024](https://wevaonline.org/wp-content/uploads/2024/12/2024-Christmas-Using-accelerometers-to-identify-a-high-risk-of-catastrophic-musculoskeletal-injury-in-three-racing-thoroughbreds.pdf)).
- **Desplazamiento dorsoventral de la cruz:** de ~185 mm a 7 m/s a ~83 mm a 17 m/s (Pfau 2006, vía tesis) [NV].
- **Frecuencia de zancada PSI [E]:** 2,02 Hz a 9 m/s y 2,41 Hz a 17 m/s según el texto de
  [Witte 2006](https://cob.silverchair.com/jeb/article-pdf/209/21/4389/1541743/4389.pdf) (el ajuste cuadrático da
  2,34 Hz: discrepancia ya anotada); 2,47 Hz (RIC 2,38–2,55) a 16,5 m/s ([Pfau 2024](https://mdpi.com/1424-8220/24/8/2441));
  velocistas 2,46 ± 0,08 y fondistas 2,34 ± 0,05 con Equimetre en cincha
  ([Schrurs 2022](https://nottingham-repository.worktribe.com/OutputFile/14319563)); en carrera 0,43 ± 0,02 s por
  zancada y 7,08 m a 16,6 m/s (Morrice-West 2020, resumen).
- **Precisión [E]:** frecuencia de zancada desde GPS a 10 Hz con sesgo de 0,003 Hz y ±0,027 Hz muestra a muestra frente
  a un IMU ([Pfau 2022](https://madbarn.com/research/stride-frequency-derived-from-gps-speed-fluctuations-in-galloping-horses)).
  iPhone en la cincha a 50 Hz con paso banda de 1–15 Hz ([Horan 2021](https://rvc-repository.worktribe.com/OutputFile/1557380)).
  Morrice-West 2022 descarta zancadas fuera de 0,37–0,49 s y 5,3–9,2 m [E].
- **Duty factor [E, Witte 2006]:** 0,27 / 0,29 (anterior / posterior) a 9 m/s y **0,18 / 0,22 a 17 m/s**; fuerza
  vertical pico estimada en el anterior a 17 m/s ~24,7 N/kg (22,6–26,0).

**Inferencia para el hardware [I]:** si a 17 m/s los apoyos casi no se solapan, la fuerza total en el pico ronda la de
un anterior (22,6–26 N/kg ≈ 2,3–2,7 g en el centro de masa), más la aceleración por el cabeceo en el esternón. Para la
dinámica del tronco y la zancada, **±8 g del BNO085 debería bastar**, pero los transitorios del impacto del casco a
través de la cincha no están medidos. Propuesta para la **BETA (LSM6DSV16X): ±16 g** (0,488 mg/LSB), como EquiMoves y
StrideSAFE. Para el **PROTOTIPO**: registrar ≥ 200 Hz y contar las muestras saturadas por sesión; si satura a
≥ 15 m/s, queda confirmado con datos propios. **NO VERIFICADO** con caballos. Es una recomendación de configuración
del firmware: esta noche no se toca el firmware.

## 5. ECG en ejercicio (regla A11)

**Texto completo de Van Erck-Westergren 2026 no accesible** (OUP sin respuesta). Por tanto **A11 no puede citar sus
definiciones operativas**; se cambia la fuente de las definiciones a Navas de Solis 2026, que sí se leyó completo.

- **Van Erck-Westergren et al. 2026, JVIM 40(2)** [E-r,
  [resumen](https://madbarn.com/research/cardiac-arrhythmias-during-intense-exercise-in-thoroughbred-racehorses-frequency-and-association-with-subsequent-race-performance)]:
  71 PSI de Hong Kong, ECG de una derivación vestible, 405 registros en los 21 días antes de 224 salidas; fases de
  calentamiento, máxima y recuperación rápida y lenta. Arritmias en el 73 % (antes de buen resultado) y el 81 % (antes
  de mal resultado); ectopia en la fase máxima 57 % frente a 70 %. **Cada latido ectópico adicional: OR 1,15
  (IC 95 % 1,04–1,28)**. La OR de «cualquier ectópico» (1,8; IC 0,86–3,81; P = 0,02) es incoherente en el resumen [NV].
- **Navas de Solis et al. 2026, EVJ** (doi 10.1002/evj.70166) [E,
  [PDF](https://wevaonline.org/wp-content/uploads/2026/07/2026-Aug-Equine-Veterinary-Journal-2026-Navas-de-Solis-Exercising-electrocardiograms-from-Thoroughbred-racehorses-with.pdf)]:
  11 PSI con muerte súbita asociada al ejercicio, 24 ECG con Equimetre.
  - **Prematuro:** RR al menos un **5 % más corto** que el RR anterior.
  - **Fases:** ejercicio (alta intensidad, con la aceleración), **recuperación temprana = primeros 2 min**, tardía hasta
    el final.
  - **Arritmia compleja:** prematuros multiformes, tripletes, rachas o FA.
  - Prematuros en el 70 % de los registros; arritmia compleja 15 % / 10 % / 25 % por fase; FA en 4 de 24; 3 de los 4
    ECG del día de la muerte con FA continua. Sin grupo control y sin frecuencia de muestreo publicada.
- **Consenso ACVIM/ECEIM, Reef et al. 2014** ([JVIM](https://pmc.ncbi.nlm.nih.gov/articles/PMC4895474)) [E]: **no
  fija un número aceptable** de prematuros en ejercicio; los ocasionales se consideran compatibles con el rendimiento
  normal; frecuencia ventricular > 120 lpm como rasgo de arritmia ventricular compleja; con FA, cardioversión si la FC
  máxima media en ejercicio supera 220 lpm; solo con equipos con almacenamiento y reproducción.
- **Prevalencia en sanos y en bajo rendimiento [E-r]:** Massie 2020 (Chuckwagon) arritmias en el 92 % de 52 ECG, casi
  todas aisladas; Marr 2021 (245 PSI con bajo rendimiento) 35,5 % sin ectopia, 44,9 % prematuros aislados, 19,6 %
  taquidisritmias complejas, la mitad detectadas en la recuperación.
- **Variación RR normal [E-r, Frick 2019]:** −6,1 % a +5,4 % al galope en sanos; en recuperación un acortamiento
  ≥ 6 % predice arritmia (sensibilidad 88 %, especificidad 97 %).
- **Calidad [E-r, Ter Woort 2023]:** trazado no interpretable si el artefacto supera el 10 % del ejercicio; con una
  derivación, κ 0,97 en detección y 0,93 en clasificación frente a la referencia.
- **Muestreo:** no se encontró una frecuencia mínima publicada para el ECG equino en ejercicio ni una validación de
  Pan-Tompkins en caballos [NV].

**Especificación propuesta para A11 [E/I]:** prematuro = RR ≥ 5 % más corto que el anterior [E, Navas], con bandera
«probable» entre 5 y 6 % porque la variación sana al galope llega al 6 % [I]; fases de Navas [E]; compleja =
multiformes, triplete, racha ≥ 3 o FA [E; racha I]; par aparte [I]; FA paroxística = RR irregularmente irregular sin P
≥ 30 s con vuelta a sinusal [I]; recuento por fase sin umbral de normalidad (OR por latido) [E]; no interpretable si
artefacto > 10 % [E-r]; ≥ 250 SPS y preferible 500 SPS (resolución RR de 2–4 ms a 220 lpm) [I]. **Sigue PENDIENTE**:
hay que leer Van Erck completo y validar el detector QRS con anotación manual de nuestros ECG.

## 6. V200, VHRmax, recuperación de FC y últimos 600 m (A8, A9)

- **Vermeulen & Evans 2006** [E-r,
  [resumen](https://madbarn.com/research/measurements-of-fitness-in-thoroughbred-racehorses-using-field-studies-of-heart-rate-and-velocity-with-a-global-positioning-system)]:
  FC y velocidad GPS **promediadas en 5 s** en trabajos habituales, regresión con trote y galope; diferencias medias
  test-retest **≤ 2 %** en V200, VHRmax y FCmax (no es un TE formal); V200 y VHRmax suben con el entrenamiento, FCmax
  no. Texto completo bloqueado (rango de la regresión y retraso de la FC sin confirmar).
- **Gramkow & Evans 2006** [E-r,
  [resumen](https://madbarn.com/research/correlation-of-race-earnings-with-velocity-at-maximal-heart-rate-during-a-field-exercise-test-in-thoroughbred-racehorses)]:
  25 PSI; VHRmax correlaciona con las ganancias por salida (r = 0,41); con VHRmax < 14,5 m/s ganaron de media
  menos de 2.500 AUD por salida. FCmax y velocidad máxima no correlacionan.
- **Schrurs et al. 2024, Animals 14:1342** [E, [texto completo](https://www.mdpi.com/2076-2615/14/9/1342/htm)]:
  485 PSI con Equimetre en la cincha. La **velocidad final** se define como la **media sobre los últimos 600 m** (o los
  tres últimos *furlongs*) y predice ganar; la velocidad puntual en la marca de 600 m **no** predice. La recuperación
  de FC a 1 min no predijo. Diferencia práctica de ~1–1,5 s por *furlong*. No da TE ni repetibilidad.
- **Árabes** [E, [Prince et al., KER](https://ker.com/wp-content/uploads/Comparison-Of-The-Metabolic-Responses-Of-Trained-Arabian-And-Thoroughbred-Horses-During-Low-And-High-Intensity-Exerices.pdf)]:
  en cinta, V200 de 9,76 m/s (PSI) y 9,51 m/s (árabe), sin diferencia significativa. No hay V200 de campo en árabes de
  carreras [NV].
- **Repetibilidad [E, [Poinsard 2026, Animals 16:1598](https://www.mdpi.com/2076-2615/16/11/1598), trotones]:** V200
  como primer cruce de 200 lpm sostenido 10 s, ICC 0,50; recuperación a 60 s con MDC95 de 22–26 lpm; limpieza de FC
  (< 25 o > 240 lpm, saltos > 7 lpm/s).
- **No hay SWC ni TE formal publicado** de V200 en caballos. TE ≈ 2 % por defecto es [I].

**Lo implementado esta noche (A8, solo la métrica).** La definición de Schrurs está cerrada [E]: media de los
últimos 600 m = 600 m / tiempo, con el tiempo interpolado sobre la distancia acumulada, no media de muestras. El motor
la calcula en cada trabajo de ≥ 600 m (`v_ultimos_600m`, `ultimos_600m_s`). **La regla A8 sigue PENDIENTE**: no hay
umbral publicado (0,1–0,2 m/s sigue siendo [I]), y necesita «trabajo de referencia» y superficie anotada.
V200/VHRmax (A9) sigue PENDIENTE hasta que el análisis lea el ECG; se deja la propuesta de algoritmo en
`pendiente_motor`.

---

## Resumen de la noche

- **σ0:** aclarado. 134,2 MPa es la curva de sensibilidad in vitro de Martig 2013 (la de Morrice-West 2022 y nuestro
  modelo A); 139,0 MPa es la calibración in vivo de Pan 2025 para el modelo B. El modelo A no cambia. El «rango
  54–90 MPa» eran los niveles del ensayo. Ecuaciones y casi todas las constantes del modelo B recogidas; faltan 5
  constantes de la adaptación para poder implementarlo.
- **Verheyen 2006:** confirmado ≤ 14 / > 14 m/s; el resumen sugiere que 44 km de canter y 6 km de galope actúan juntos.
  Sin texto completo no se cambian A1 ni A2.
- **Árabes:** tabla de 8 carreras con tiempos oficiales; élite en 2.000 m a 14,6–15,1 m/s, población turca en césped a
  14,34 m/s. El 14,2 m/s polaco era de 3.000 m (corregido). v_carrera 14,5 se mantiene.
- **Cincha:** sin picos publicados en g; ±16 g recomendado para la BETA y contador de saturación para el PROTOTIPO [I].
- **ECG:** definiciones operativas de Navas de Solis 2026 (prematuro ≥ 5 %, recuperación temprana 2 min, compleja);
  Van Erck 2026 solo en resumen (OR 1,15 por ectópico).
- **V200 y 600 m:** definición de Schrurs implementada como métrica (motor 2.0.0-dev3, KB 1.1.0); A8 y A9 siguen
  pendientes.
- **Validación:** pruebas locales con ASan/UBSan, 95 casos y 1.627 comprobaciones sin fallos. **NO VERIFICADO** con
  caballos reales.
- **Textos que hay que conseguir a mano:** Verheyen 2006 (Bone), Van Erck-Westergren 2026 (JVIM), Vermeulen & Evans
  2006 y Gramkow & Evans 2006 (Wiley), Martig 2013 (Bone), tabla 1 de Pan 2025 (JRSI) y tabla 9 completa de Anwar 2026,
  Pfau 2006 y Barrey 2001, y los PDF de tracking de France Galop.
