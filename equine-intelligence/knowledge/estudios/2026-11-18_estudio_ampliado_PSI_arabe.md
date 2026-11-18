# Dosificar la velocidad construye caballos más rápidos

**Sí: el trabajo fuerte de cada semana debe ser más corto que la carrera.** Ningún ensayo ha comparado directamente un *breeze* corto con un trabajo a distancia de carrera, pero las tres líneas de evidencia más sólidas apuntan en la misma dirección. La primera es el hueso. En el modelo de fatiga subcondral de Melbourne, una carrera de PSI consume de media un **9,34 % de la vida a fatiga del hueso** a 90 MPa ([Morrice-West 2022](https://www.nature.com/articles/s41598-022-14274-y)). En Hong Kong, una carrera consume de mediana un **10,1 %** y un trabajo rápido un **3,21 %** ([ICRAV 2026](https://icrav-2025.p.asnevents.com.au/days/2026-03-26/abstract/130413)). Además, la formación ósea del modelo de Pan **se satura hacia los 36 ciclos diarios** ([Pan 2025, bioRxiv](https://www.biorxiv.org/content/10.1101/2025.04.06.646486v1.full)), así que cada zancada rápida de más añade daño sin añadir adaptación. La segunda es la epidemiología. **Dosis moderadas a 15,5–16,7 m/s protegen** (IRR 0,76 en potros de 2 años), mientras que el volumen a 13,3–14,3 m/s perjudica ([Morrice-West 2023](https://www.frontiersin.org/journals/veterinary-science/articles/10.3389/fvets.2023.1260554/pdf)). Pasar de 5 a 7 km rápidos en dos meses **multiplica por 3,9 el riesgo de fractura catastrófica** ([Estberg 1996](https://madbarn.com/research/high-speed-exercise-history-and-catastrophic-racing-fracture-in-thoroughbreds)). La tercera es la fisiología. A igual distancia, **seis repeticiones de 30 s mejoran un 29 % la distancia hasta el agotamiento, frente a un 4,5 % del trabajo continuo** ([Mukai 2026](https://madbarn.com/research/physiological-adaptations-to-6-weeks-of-high-intensity-interval-and-moderate-intensity-continuous-training-in-horses-a-randomized-crossover-study)). Y lo que predice ganar es **ser rápido en los últimos 600 m de un trabajo de 1 km**, no la velocidad a mitad del trabajo ([Schrurs 2024](https://madbarn.com/research/cardiovascular-fitness-and-stride-acceleration-in-race-pace-workouts-for-the-prediction-of-performance-in-thoroughbreds)).

Para AVO esto implica un motor con tres capas:

| Capa | Qué mide | Cómo |
|---|---|---|
| Carga | Lo que el caballo acumula | Metros y zancadas por banda de velocidad, y fatiga ósea acumulada por zancada |
| Respuesta | Si el caballo asimila la carga | Relación FC–velocidad (V200/VHRmax), velocidad final del trabajo y zancada a velocidad fija, siempre frente a la línea base propia |
| Seguridad | Si hay que frenar | Reglas duras ante vueltas tras parón, picos de carga en 30–60 días o ectopia en fase máxima |

El árabe de carreras corre a un **~87–92 % del ritmo del PSI**: el ganador del Gr1 de Longchamp en 2024 hizo los 2.000 m a **14,70 m/s** ([France Galop](https://www7.france-galop.com/Casaques/Tracking//20241006LON04_last_times_fr.pdf)). Casi no tiene literatura de entrenamiento, zancada ni lesión, así que la cuadra tendrá que construir esa base con sus propios datos. Ningún modelo publicado predice lesiones individuales con una sensibilidad útil. La app debe presentarse como una herramienta de dosificación y vigilancia, nunca como un oráculo.

*Nota de método.* Este estudio sustituye al informe anterior («base científica»). Muchos textos completos (PMC, Wiley/EVJ, MDPI) estaban bloqueados, así que varias cifras proceden de resúmenes reproducidos en agregadores (MadBarn, dvm360) o de resúmenes de congreso. Las etiquetas significan lo siguiente:

- **[E]** dato o ecuación publicada con fuente enlazada.
- **[I]** inferencia o diseño propio a partir de la evidencia.
- **[NV]** cifra o fórmula de conocimiento previo, sin verificar en esta investigación. No debe entrar en el código sin contrastarla.

Los cálculos de referencia que aparecen aquí se hicieron con las ecuaciones publicadas y se marcan como propios. Nada de este informe está verificado en el hardware de AVO.

## La semana fuerte corta, en números de fatiga ósea

La pregunta inicial se responde mejor con las ecuaciones de Morrice-West, porque convierten cada zancada en una fracción de vida a fatiga. La cadena es esta:

1. La velocidad da la fuerza vertical: `F = 2,778 + 2,1376·v − 0,0535·v²` N/kg, derivada de Witte 2006.
2. La fuerza da la tensión articular: `σ = σmax · F / 24,13`.
3. La curva S-N de Martig 2013 da los ciclos hasta el fallo: `Nf = 10^((134,2 − σ)/14,1)`.
4. El daño se suma por zancada con la regla de Miner, sin reparación ([Morrice-West 2022](https://www.nature.com/articles/s41598-022-14274-y)).

Si se aplica esa cadena con la frecuencia de zancada de Witte (`f = 1,7052 + 0,0305·v + 0,0004·v²`, la ec. 14 de [Anwar 2026](https://arxiv.org/html/2603.22680)), se obtienen los valores de la tabla. Son cálculos propios [I] sobre ecuaciones [E].

| Evento (PSI, σmax = 90 MPa) | Velocidad | Zancadas | %SBFL calculado |
|---|---|---|---|
| Carrera de 2.100 m (Chantilly, 4 años) | 16,04 m/s | ≈301 | **13,3 %** |
| Carrera de 1.200 m | 16,7 m/s | ≈167 | **8,6 %** (publicado: 9,34 % de media) |
| Trabajo de 1.000 m | 16,0 m/s | ≈144 | 6,3 % |
| *Breeze* de 600 m | 16,0 m/s | ≈86 | **3,8 %** (Hong Kong, trabajo rápido: 3,21 %) |
| Trabajo de 800 m | 15,0 m/s | ≈120 | 3,9 % |
| Canter de 2.000 m | 12,0 m/s | ≈355 | 3,3 % |
| Canter de 2.000 m | 10,0 m/s | ≈410 | 1,2 % |

La tabla dice tres cosas. **Repetir cada semana la distancia de carrera a ritmo de carrera equivale, para el hueso, a correr una vez por semana.** Un *breeze* de 600 m consume entre un tercio y un cuarto de lo que consume una carrera de media distancia, y el valor calculado coincide con la mediana observada en Hong Kong ([ICRAV 2026](https://icrav-2025.p.asnevents.com.au/days/2026-03-26/abstract/130413)). Y el canter de volumen tampoco sale gratis: con σmax = 90 MPa, 2 km a 12 m/s cuestan casi lo mismo que el *breeze*. Eso encaja con que el trabajo lento aporte el **29,1 % de la fatiga acumulada** en cada preparación, frente al **39,6 %** del trabajo rápido y solo el **17,8 %** de las carreras ([ICRAV 2026](https://icrav-2025.p.asnevents.com.au/days/2026-03-26/abstract/130413)).

Hay un punto de calibración que conviene no esconder. Hong Kong da una mediana de solo **0,41 %** por sesión de trabajo lento, muy por debajo del 1,2–3,3 % calculado. Es probable que sus sesiones lentas sean más lentas o más cortas, o que la ecuación de fuerza sobrestime la tensión a velocidad baja [I]. El índice absoluto, por tanto, no es fiable por debajo de unos 13 m/s, y conviene mostrarlo relativo a una carrera de referencia.

El modelo de Pan añade lo que el de Miner no tiene: adaptación y reparación. La formación ósea **se satura por encima de unos 36 ciclos al día** ([Pan 2025](https://www.biorxiv.org/content/10.1101/2025.04.06.646486v1.full)). Con zancadas de ≈7 m a 16 m/s, eso son unos **250 m de galope rápido** [I, cálculo propio]. A partir de ahí, cada zancada adicional solo suma daño. La conclusión explícita de Anwar et al. es la misma: **«lower-volume programmes with some high-speed training»** dan adaptación suficiente con menos daño ([Anwar 2026](https://arxiv.org/html/2603.22680)).

La epidemiología lo confirma con matices:

- En potros, el galope acumulado a alta velocidad fue **protector** y el canter acumulado aumentó el riesgo ([Verheyen 2006](https://madbarn.com/research/exercise-distance-and-speed-affect-the-risk-of-fracture-in-racehorses)).
- El riesgo de fractura sube con **más de 44 km de canter (≤14 m/s) o más de 6 km de galope (>14 m/s) en 30 días**, unos 7.700 y 880 ciclos respectivamente ([Verheyen, Bone 2006](https://www.sciencedirect.com/science/article/abs/pii/S8756328206005497)).
- La relación tiene forma de U. Frente a una carga media en las 4 salidas previas, la carga baja multiplicó el riesgo por **2,89** y la alta por **8,51** ([Morrice-West 2025](https://madbarn.com/research/the-impact-of-cumulative-bone-fatigue-on-musculoskeletal-injury-risk-in-racing-thoroughbreds)).

El trabajo fuerte corto es, por tanto, necesario y suficiente para el hueso, siempre que no desaparezca y que el canter del resto de la semana no se dispare.

### El argumento contrario

Un fondista podría necesitar trabajos largos para aprender a dosificar el esfuerzo y desarrollar su capacidad aeróbica. Los datos lo matizan sin negarlo. En Victoria, los sprinters trabajan con **menos carga que los stayers** ([Morrice-West 2020](https://www.pubmed.gov/31386764/)). Los entrenadores con más éxito acumulan **7,5–15 km de galope (≥13,3 m/s) antes del primer trial**, y el rendimiento cae cuando el galope lento (13,3–14,3 m/s) supera los **12,5 km** ([Morrice-West 2021](https://madbarn.com/research/association-of-thoroughbred-racehorse-workloads-and-rest-practices-with-trainer-success)).

En carrera, la estrategia óptima del modelo de control de Mercier y Aftalion, ajustado con GPS de France Galop a 10 Hz, es una salida fuerte pero no excesiva, una fase media constante y la menor caída final posible ([Mercier & Aftalion 2020](https://journals.plos.org/plosone/article?id=10.1371%2Fjournal.pone.0235024)). Esa capacidad de sostener la velocidad con la reserva anaeróbica baja es justo lo que mide la velocidad de los últimos 600 m de un trabajo de 1 km.

La síntesis defendible [I] tiene cuatro partes:

- La resistencia se construye con volumen a velocidad moderada, vigilado con un tope de 30 días.
- La adaptación ósea y la velocidad final se construyen con trabajos rápidos cortos, de 600–1.000 m y con los últimos 600 m a 15,5–16,7 m/s en el PSI.
- Las repeticiones con recuperación sustituyen al trabajo continuo largo cuando se busca capacidad anaeróbica.
- La distancia de carrera se reserva para las carreras y los trials.

## Lo que dice la evidencia, tema por tema

### Hueso: la velocidad de acumulación predice la lesión

El hueso subcondral del cóndilo metacarpiano acumula microdaño en función de la tensión por zancada y del número de ciclos. Lo que predice la lesión es **la velocidad a la que se acumula ese daño**, no solo el total:

- **HR 3,37** en una sola salida y **HR 1,80** a lo largo de la carrera deportiva cuando la acumulación es más rápida ([Morrice-West 2025](https://madbarn.com/research/the-impact-of-cumulative-bone-fatigue-on-musculoskeletal-injury-risk-in-racing-thoroughbreds)).
- En Hong Kong (5.215 caballos), tasas mayores de %SBFL en ventanas de 14, 30, 60, 90, 120, 180 y 365 días se asociaron a más lesiones, y **el quintil superior de carga aguda tuvo un HR superior a 5** ([ICRAV 2026](https://icrav-2025.p.asnevents.com.au/days/2026-03-26/abstract/130413)).
- En las carreras de Morrice-West, el efecto propio de cada caballo explica un **ICC de 0,37**, el estado de la pista *Good* frente a *Heavy 10* tiene un coeficiente de **2,37**, y las hembras acumulan más que los machos ([Morrice-West 2022](https://www.nature.com/articles/s41598-022-14274-y)).

El reposo es un arma de doble filo. En reposo, la superficie erosionada del cóndilo lateral sube de **0,24 a 0,85/mm** y la fracción de área ósea baja del **90,8 al 85,3 %** ([Holmes 2014](https://madbarn.com/research/thoroughbred-horses-in-race-training-have-lower-levels-of-subchondral-bone-remodelling-in-highly-loaded-regions-of-the-distal-metacarpus-compared-to-horses-resting-from-training)). Repara el daño, pero debilita el hueso durante un tiempo. Los modelos lo reflejan:

- En Pan, f_BM sube **0,053** en 100 días de entrenamiento y baja **0,131** en 100 días de reposo. Un reposo de 6,3 semanas no repara el daño por completo ([Pan 2025](https://www.biorxiv.org/content/10.1101/2025.04.06.646486v1.full)).
- En Anwar, los reposos de 4, 6 y 8 semanas dejan un D* máximo de **0,992, 0,833 y 0,713**. Con 1, 2 o 3 reposos al año, el D* máximo es de **1,543, 0,911 y 0,799**. Una fase de dos semanas a baja intensidad (*back-off*) empeora el resultado hasta **1,406** ([Anwar 2026](https://arxiv.org/html/2603.22680)).

De ahí sale una regla operativa: vigilar la **vuelta tras un parón**. Tras ≥2 meses sin trabajos rápidos, el riesgo relativo de fractura de húmero fue de **71 en los primeros 10 días** y de **45 en los primeros 21** ([Carrier 1998](https://madbarn.com/research/association-between-long-periods-without-high-speed-workouts-and-risk-of-complete-humeral-or-pelvic-fracture-in-thoroughbred-racehorses-54-cases-1991-1994)).

### Tendón: margen de seguridad mínimo y casi sin reparación

El tendón flexor digital superficial (TFDS) llega al galope a deformaciones de **hasta el 16,6 %**, cerca de su punto de rotura ([Thorpe, UCL](https://discovery.ucl.ac.uk/1376279/1/1376279.pdf)). Su núcleo alcanza **43–45 °C**, por encima de los 42,5 °C a los que mueren los fibroblastos ([Wilson & Goodship 1994](https://madbarn.com/research/exercise-induced-hyperthermia-as-a-possible-mechanism-for-tendon-degeneration)). Y la vida media de su colágeno es de unos **198 años**: en la práctica, el tendón adulto no se repara ([Thorpe](https://discovery.ucl.ac.uk/1376279/1/1376279.pdf)).

No existe un modelo de fatiga tendinosa calibrado como el óseo. Lo que sí hay son factores de riesgo de carga, de un caso-control de Seúl (101 casos; [Choi & Parkin 2025](https://pmc.ncbi.nlm.nih.gov/articles/PMC12699112/)):

| Factor | OR |
|---|---|
| Carrera o trial frente a galope de entrenamiento | **11,39** |
| 1–2 periodos de ≥90 días sin trabajo rápido en el último año | **3,10** |
| Cociente de días de galope 60 d / 90 d ≤ 1,6 | 2,19 |
| ≥41 días de canter en los 180 días previos | 1,84 |
| ≤2 días de galope en 60 días | 1,84 |

El aumento del área de sección y el edema peritendinoso en la ecografía predicen una lesión grave posterior. Es el único marcador de seguimiento validado ([Choi & Parkin, revisando Iimori 2022](https://pmc.ncbi.nlm.nih.gov/articles/PMC12699112/)). Esto pesa más en el árabe, cuya lesión dominante es tendinosa (ver la comparación PSI–árabe).

### Programas reales: poco volumen rápido y mucho criterio

Australia es el único país con programas cuantificados.

En **Victoria** (66 entrenadores), la mediana es de **8.000 m/mes de galope**. Los entrenadores se reparten en cuatro programas ([Morrice-West 2020](https://www.pubmed.gov/31386764/)):

| Programa | Galope mensual (mediana) | Entrenadores |
|---|---|---|
| Bajo | 4.800 m | 23 % |
| Medio | 8.000 m | 50 % |
| Medio con más alta velocidad | 12.800 m | 17 % |
| Alto volumen | 19.200 m | 9 % |

Los caballos de 3 años o más descansan dos veces al año, una media de **6,3 semanas**. Más de la mitad de los programas superan los umbrales de riesgo publicados.

En **Queensland**, los potros de 2 años hacen de mediana **≈440 m/semana a *three-quarter pace*** (≈13,4 m/s) y **≈160 m/semana de *track gallop*** (>15,5 m/s), en 0,5 días a la semana. La preparación dura 7 semanas, con hitos en las semanas 2, 4, 6, 8 y 11 (primera carrera). Solo el **31 %** llegó a correr ([Crawford 2021](https://www.mdpi.com/2076-2615/11/4/928)). En Japón, una carrera de 1.200 m a 15,9 m/s llevó la FC a **213,6 lpm** y el lactato a **22,5 mmol/L** a los 10 min ([Mukai 2007](https://www.jstage.jst.go.jp/article/jes/18/4/18_4_153/_article)).

Los experimentos de entrenamiento son escasos, pequeños y en cinta:

- **HIIT frente a continuo** (7 PSI, ensayo cruzado): seis semanas de 6 × 30 s al 100 % del VO2max subieron un **15 % la velocidad a FC máxima** frente a un 4,3 % del continuo con la misma distancia. El VO2max subió igual con ambos, un **13 %** ([Mukai 2026](https://madbarn.com/research/physiological-adaptations-to-6-weeks-of-high-intensity-interval-and-moderate-intensity-continuous-training-in-horses-a-randomized-crossover-study)).
- **Una sola sesión** de HIIT o SIT produce **22–24 mmol/L** de lactato y vacía un **33–34 %** del glucógeno ([Mukai 2023](https://www.frontiersin.org/journals/veterinary-science/articles/10.3389/fvets.2023.1241266/pdf)). Es tan exigente como una carrera.
- **Calentamiento:** uno corto e intenso (120 s al 100 % del VO2max y 10 min de pausa) acelera la cinética del VO2 y reduce el lactato inicial, aunque no cambia el tiempo hasta la fatiga ([Mukai 2011](https://madbarn.com/research/effects-of-three-warm-up-regimens-of-equal-distance-on-vo2-kinetics-during-supramaximal-exercise-in-thoroughbred-horses)).
- **Días entre salidas:** el éxito de los entrenadores mejora con intervalos más largos entre salidas **hasta unas 3 semanas** y empeora después ([Morrice-West 2021](https://madbarn.com/research/association-of-thoroughbred-racehorse-workloads-and-rest-practices-with-trainer-success)).

### Corazón: la forma es la recta FC–velocidad, y la ectopia es frecuente

El índice de campo mejor validado es la **regresión FC–velocidad sobre medias de 5 s** de un trabajo rápido habitual, sin necesidad de un test estandarizado. V200, VHRmax y HRmax se reproducen entre sesiones con **diferencias de ≤2 %**. VHRmax y V200 suben con el entrenamiento; **HRmax no cambia** ([Vermeulen & Evans 2006](https://www.researchgate.net/publication/51384035_Measurements_of_fitness_in_Thoroughbred_racehorses_using_field_studies_of_heart_rate_and_velocity_with_a_global_positioning_system)).

La VHRmax se correlacionó con las ganancias por salida (**r = 0,41**, n = 25). Los caballos con **VHRmax < 14,5 m/s** ganaron de media menos de 2.500 AUD por carrera ([Gramkow & Evans](https://madbarn.com/research/correlation-of-race-earnings-with-velocity-at-maximal-heart-rate-during-a-field-exercise-test-in-thoroughbred-racehorses)). La recuperación de FC a 1 min **no predijo** el resultado en 485 caballos (p = 0,21) ([Schrurs 2024](https://madbarn.com/research/cardiovascular-fitness-and-stride-acceleration-in-race-pace-workouts-for-the-prediction-of-performance-in-thoroughbreds)). Sí distingue estados de entrenamiento: el entrenamiento cambia la FC entre 0,5 y 5 min tras el test, y el desentrenamiento la de 40–60 min ([Foreman 1990](https://madbarn.com/research/standardized-exercise-test-and-daily-heart-rate-responses-of-thoroughbreds-undergoing-conventional-race-training-and-detraining/)). Los valores de cinta (V200 de 8–9 m/s al 10 % de pendiente, «<7 m/s anormal») no se trasladan a pista llana ([Hines 2018, vía ScienceDirect Topics](https://www.sciencedirect.com/topics/agricultural-and-biological-sciences/exercise-test)).

La arritmia de ejercicio es común en caballos aparentemente sanos. En 71 PSI de Hong Kong con 405 ECG de una derivación a 500 Hz ([Van Erck-Westergren 2026](https://academic.oup.com/jvim/article/40/2/aalag044/8539596)):

- El **57–70 %** tuvo ≥1 latido ectópico en la fase máxima.
- **Cada latido ectópico adicional en fase máxima** aumentó un **15 %** las odds de mal resultado (OR 1,15; IC95 1,04–1,28). Los latidos anchos, un 19 %.
- La FA paroxística apareció en el **0,8 %** de los registros con buen resultado frente al **4,1 %** con mal resultado.
- La repetibilidad intra-caballo fue baja (**ICC 0,39**) y no hubo correlación entre registros separados 1–4 días.

Otros datos relevantes:

- En Hong Kong, el **4,9 %** de los caballos tuvo FA tras una carrera. La odds fue **5,3 veces** mayor con un episodio previo ([Nath 2021](https://madbarn.com/research/incidence-recurrence-and-outcome-of-postrace-atrial-fibrillation-in-thoroughbred-horses)).
- En EE. UU., la muerte súbita asociada al ejercicio supone **~8 % de las muertes en carrera y ~18 % en entrenamiento**, más de la mitad probablemente de causa cardiaca ([HISA 2025](https://www.horseracingnation.com/news/HISA_announces_new_findings_on_exercise_associated_sudden_death_123)).
- El consenso ACVIM/ECEIM **no fija umbrales numéricos** de complejos prematuros aceptables. Considera que los PVC durante el ejercicio son «motivo de preocupación» ([Reef 2014](https://www.tierspital.uzh.ch/wp-content/uploads/2023/04/Reef-2014-4351-JVIM-Consensus-Statement-Equine-Athletes-with-Cardiovascular-Abnormalities.pdf)).
- Un ECG de una derivación en cincha (Equimetre) alcanzó una **kappa de 0,97** en la detección de arritmias, con un **0,25 % de artefacto** frente al 5 % de un Televet ([Ter Woort](https://madbarn.com/research/validation-of-an-equine-fitness-tracker-ecg-quality-and-arrhythmia-detection/)).

En **VFC**, la rMSSD en reposo bajó tras 14 semanas de entrenamiento, y el análisis por cambio mínimo relevante (SWC) individual es el enfoque propuesto ([Nyerges-Bohák 2021](https://journals.plos.org/plosone/article?id=10.1371%2Fjournal.pone.0259933)). En caballos con bajo rendimiento, la cojera se asoció a una **logRMSSD menor** en ejercicio submáximo y la arritmia a una **mayor** ([MadBarn, 180 PSI](https://madbarn.com/research/heart-rate-variability-during-high-speed-treadmill-exercise-and-recovery-in-thoroughbred-racehorses-presented-for-poor-performance)). Una VFC alta durante el esfuerzo es, por tanto, sospechosa, no una señal de buena forma.

### Zancada: sirve frente a uno mismo, no para comparar caballos

En el PSI, la frecuencia de zancada (SF) sube poco con la velocidad, de **2,02 Hz a 9 m/s a 2,41 Hz a 17 m/s**. El caballo gana velocidad alargando la zancada ([Witte 2006](https://cob.silverchair.com/jeb/article-pdf/209/21/4389/1541743/4389.pdf)). Ojo: los coeficientes cuadráticos del mismo artículo dan 2,34 Hz a 17 m/s, no 2,41, así que el texto y la figura no coinciden [NV].

En 25.259 salidas, la longitud de zancada (SL) media fue de **7,08 m a 16,63 m/s**, y la velocidad explica la mitad o menos de su variación ([Morrice-West 2020](https://madbarn.com/research/variation-in-gps-and-accelerometer-recorded-velocity-and-stride-parameters-of-galloping-thoroughbred-horses)). La señal de lesión es intraindividual: en los últimos 200 m, cada **0,1 m/s menos eleva el riesgo un 18 %** y cada **10 cm menos de zancada, un 11 %**. El descenso se acelera unas 6 carreras antes de la lesión ([Wong 2023](https://minerva-access.unimelb.edu.au/server/api/core/bitstreams/45ea7c0b-7de5-4213-961a-0750167243c1/content)). Entre caballos, la SL y la SF **no predicen el éxito**, pero sí distinguen sprinters (zancada más corta y frecuente) de stayers ([Schrurs 2022](https://madbarn.com/research/locomotory-profiles-in-thoroughbreds-peak-stride-length-and-frequency-in-training-and-association-with-race-outcomes)).

Con un acelerómetro de cincha, la **regularidad** (autocorrelación) se correlacionó **r = 0,79** con el rendimiento, pero **r = −0,47** con la velocidad, así que debe compararse a igual velocidad ([Barrey 2001](https://madbarn.com/research/locomotion-evaluation-for-racing-in-thoroughbreds)).

Varios factores de confusión cambian la SL tanto como un cambio real del caballo:

- **Superficie:** cambia la SL hasta **18,6 cm**, y la combinación sesión × calle hasta **32,7 cm** a igual velocidad ([Pfau 2024](https://pmc.ncbi.nlm.nih.gov/articles/PMC11054522/)).
- **Curva:** acorta la SL un **2,1 %** ([van den Broek 2025](https://madbarn.com/research/association-between-stride-parameters-and-racetrack-curvature-for-thoroughbred-chuckwagon-horses)).

En cuanto a la técnica de medida:

- La SF obtenida del GPS a 10 Hz tiene una precisión suficiente para detectar caídas de 10 cm ([Pfau 2022](https://madbarn.com/research/stride-frequency-derived-from-gps-speed-fluctuations-in-galloping-horses)).
- Un IMU comercial de cincha falló un **20,7 % en la SL zancada a zancada** ([Guyard 2023](https://mdpi.com/1424-8220/23/9/4196)).
- La mano de galope se clasificó al 100 %, pero con sensores en los anteriores ([Eerdekens 2021](https://pmc.ncbi.nlm.nih.gov/articles/PMC8532712)). El mejor sensor único de Serra Bragança solo llegó al **79,9 %** en la clasificación de aires ([Serra Bragança 2020](https://pmc.ncbi.nlm.nih.gov/articles/PMC7576586)).
- **No hay validación publicada de la detección de mano con un solo IMU de tronco** a galope de carrera.

La desviación del patrón de zancada sí discrimina riesgo. StrideSAFE asigna riesgos relativos de **18× (2–3 DE) a 950× (>5 DE)** frente al patrón ideal ([Wiggers, JAVMA 2024](https://avmajournals.avma.org/view/journals/javma/262/9/javma.24.02.0114.xml)). Pero en su cohorte de 28.481 salidas, la puntuación máxima solo acertó **~1 de cada 25** lesiones fatales ([dvm360, 2025](https://www.dvm360.com/view/biometric-sensors-may-help-identify-the-few-thoroughbreds-at-highest-risk-for-fatal-musculoskeletal-injury)). Un modelo CatBoost con datos de zancada tuvo una **sensibilidad de 0,00** para lesión ([Bogossian 2024](https://doaj.org/article/052082a0d2af496ca5912cf4c2600d3b)).

### Rendimiento: velocidad final, edad y genética

Los predictores con más respaldo en el PSI son la **velocidad en los últimos 600 m de un trabajo de 1 km** (p < 0,008; n = 485) y la **VHRmax** ([Schrurs 2024](https://madbarn.com/research/cardiovascular-fitness-and-stride-acceleration-in-race-pace-workouts-for-the-prediction-of-performance-in-thoroughbreds); [Gramkow & Evans](https://madbarn.com/research/correlation-of-race-earnings-with-velocity-at-maximal-heart-rate-during-a-field-exercise-test-in-thoroughbred-racehorses)).

Otros factores a tener en cuenta:

- **Edad:** la velocidad media sube hasta la primera mitad de los 4 años y luego se estabiliza. El peso llevado tiene un efecto pequeño ([Takahashi, JRA](https://www.jstage.jst.go.jp/article/jes/26/2/26_1506/_article)). Parte de la «mejora» de un caballo de 2 a 4 años es maduración, no entrenamiento.
- **Sexo:** los enteros tienen ratings IFHA significativamente mayores ([AAB 2023](https://aab.copernicus.org/articles/66/299/2023/)).
- **Genética:** el SNP g.66493737 de MSTN predice la distancia óptima: C:C ≈1.247 m, C:T ≈1.831 m y T:T ≈2.113 m ([Hill 2010](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC3091701/)).
- **Breeze-ups:** el tiempo de breeze determina el precio (unos 40.000–120.000 USD por segundo). El pedigrí explica el 50–80 % del precio pero solo el **3–6 % de las ganancias** ([Paulick Report](https://paulickreport.com/news/bloodstock/research-puts-numbers-behind-two-year-old-sales-trends), prensa sectorial).
- **Lactato:** el lactato post-test en cinta se correlacionó con el rating Timeform (**r = −0,68**) ([Veterian Key](https://veteriankey.com/exercise-testing-in-the-field/)). No encontré ningún trabajo que relacione las velocidades de entrenamiento por GPS con la valeur de France Galop.

### Salud: el bajo rendimiento rara vez es «falta de forma»

En los modelos experimentales de sobreentrenamiento (trotones), el único marcador fiable fue **la caída del rendimiento en un test estandarizado**, de un **14 a un 19 %** ([de Graaf-Roelfsema](https://pmc.ncbi.nlm.nih.gov/articles/PMC4062293/)). La acompañaron:

- **pérdida de peso sin caída de la ingesta**, que precedió unas 3 semanas a la caída de rendimiento (semana 28 frente a 31) ([Tyler 1998](https://madbarn.com/research/haematological-and-biochemical-responses-to-training-and-overtraining));
- **lactato máximo menor**, de 4,3 frente a 8,3 mmol/L ([de Graaf-Roelfsema](https://pmc.ncbi.nlm.nih.gov/articles/PMC4062293/));
- cambios de comportamiento: el caballo rehúsa, cambia de aire o se para.

El VO2max **no cae** en el sobreentrenamiento ([Tyler 1996](https://madbarn.com/research/changes-in-maximum-oxygen-uptake-during-prolonged-training-overtraining-and-detraining-in-horses)), y la hematología y la bioquímica en reposo no lo detectan. Un caballo con la recta FC–velocidad normal puede estar sobreentrenado: hay que mirar si sostiene la velocidad final y si alcanza su FC pico. Si la caída de rendimiento persiste tras 2–4 semanas de carga reducida, ya no es *overreaching*.

En 348 caballos derivados por bajo rendimiento, la causa más frecuente fue la **obstrucción dinámica de vías altas (42,5 %)**. Le siguieron las arritmias solas (9,5 %) y otras causas, y un 26 % quedó sin diagnóstico ([Martin 2000](https://madbarn.com/research/causes-of-poor-performance-of-horses-during-training-racing-or-showing-348-cases-1992-1996)). En la endoscopia en cinta de 600 PSI, el desplazamiento dorsal del paladar (DDSP) apareció en el 50 % de los afectados ([MadBarn](https://madbarn.com/research/dynamic-obstructions-of-the-equine-upper-respiratory-tract-part-1-observations-during-high-speed-treadmill-endoscopy-of-600-thoroughbred-racehorses)).

Otros problemas con cifras útiles:

- **EIPH** de grado >1: los caballos terminan más lejos del ganador ([Hinchcliff 2005](https://madbarn.com/research/association-between-exercise-induced-pulmonary-hemorrhage-and-performance-in-thoroughbred-racehorses)).
- **Rabdomiólisis por esfuerzo:** afecta al **4,9 %** de los PSI. Es más frecuente en potrancas de 2 años, **5,4 veces** más probable en caballos nerviosos y suele aparecer tras ≥1 día de descanso ([MacLeay 1999](https://madbarn.com/research/epidemiologic-analysis-of-factors-influencing-exertional-rhabdomyolysis-in-thoroughbreds)).
- **Glucógeno:** tras esfuerzos repetidos, la resíntesis es despreciable a las 24 h, y a las 72 h no siempre ha vuelto al basal ([MadBarn, trotones](https://madbarn.com/research/resynthesis-of-glycogen-in-skeletal-muscle-from-standardbred-trotters-after-repeated-bouts-of-exercise)).
- **Calor húmedo:** mantiene la FC elevada hasta 30 min después del esfuerzo ([Art 1995](https://madbarn.com/research/physiological-measurements-in-horses-after-strenuous-exercise-in-hot-humid-conditions)).
- **Transporte:** baja la RMSSD entre un 35 y un 40 % ([MadBarn](https://madbarn.com/research/cortisol-release-and-heart-rate-variability-in-horses-during-road-transport)).

## PSI frente a árabe de carreras: misma base aeróbica, menos techo

El único estudio comparativo directo, en cinta con caballos entrenados, sitúa la diferencia en la potencia máxima, no en la base aeróbica ([Prince et al., KER](https://ker.com/wp-content/uploads/Comparison-Of-The-Metabolic-Responses-Of-Trained-Arabian-And-Thoroughbred-Horses-During-Low-And-High-Intensity-Exerices.pdf)):

| Variable | PSI | Árabe |
|---|---|---|
| VO2max | 154 ml/kg/min | **129 ml/kg/min** (−16 %) |
| Velocidad al VO2max | 12,9 m/s | **11,8 m/s** |
| Capacidad anaeróbica (MAOD) | 88 ml O2/kg | 70 ml O2/kg |
| Tiempo de sprint | 149 s | 109 s |
| V200 | 9,76 m/s | **9,51 m/s** |
| VLa4 | 8,44 m/s | **8,27 m/s** |

El árabe también oxida más grasa a baja intensidad. Su V200 y su VLa4 son casi iguales a las del PSI.

El árabe debuta más tarde: en Polonia, a **≈3,3 años frente a 2,6** en el PSI, y corre más en su primera temporada (**5,8 frente a 3,3 salidas**) ([Sobczyńska 2010](https://pdfs.semanticscholar.org/3bff/f0a722fb82bfa12416ed7b014c6f2bd56cf2.pdf)). En Turquía (12.707 caballos), la heredabilidad de su velocidad fue de **0,29**. Es máxima en la primera carrera (0,529) y mínima en la décima (0,208) ([Önder 2022](https://pmc.ncbi.nlm.nih.gov/articles/PMC9559003)): con la experiencia, el entrenamiento y el ambiente pesan cada vez más. La superficie cambia mucho la velocidad media: **13,45 m/s en arena, 14,22 en sintética y 14,34 en hierba**.

La lesión dominante es distinta. En los árabes turcos, la lesión de tendón predomina a los 3–4 años y pone fin a la carrera deportiva con menos frecuencia (**46,4 % frente a 66,3 %** del PSI) ([Yildirim 2025](https://madbarn.com/research/distribution-of-race-and-training-related-musculoskeletal-injuries-by-track-and-location-in-thoroughbred-and-arabian-racehorses)).

En la parte autonómica, el grupo de Lublin encontró que los árabes con **mayor LF/HF** rindieron mejor ([Acta Vet Brno 2016](https://actavet.vfu.cz/media/pdf/actavet_2016085040355.pdf)). Las yeguas jóvenes muestran más carga simpática ([JASBB](https://czasopisma.up.lublin.pl/jasbb/article/view/4802)). El cortisol tras la carrera supera al del entrenamiento y tiende a subir a lo largo de la temporada ([Witkowska-Piłaszewicz 2021](https://scholars.uky.edu/en/publications/stress-response-after-race-and-endurance-training-sessions-and-co/)).

En árabes jóvenes, el entrenamiento guiado por lactato subió la V4 de **5,8 a 7,6 m/s en 6 semanas** ([Santos 2023](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC10252023/)). La V4 y la V200 se entrenan en semanas también en esta raza.

**No hay** en la literatura revisada datos de zancada de árabes a más de 14 m/s, programas de entrenamiento con distancias y velocidades, ni distancias acumuladas asociadas a lesión. Todos los estudios con Equimetre son de PSI ([Schrurs, PMC11083884](https://pmc.ncbi.nlm.nih.gov/articles/PMC11083884/)).

### Velocidades de referencia

| Referencia | Distancia | Media | Mejor 200 m | Pico / final | Fuente |
|---|---|---|---|---|---|
| PSI 2 años, Chantilly (PSF, GPS 10 Hz) | 1.300 m | **17,0 m/s** (76,5 s) | — | final en subida ≈2 % | [Mercier & Aftalion](https://journals.plos.org/plosone/article?id=10.1371%2Fjournal.pone.0235024) |
| PSI 3 años, Chantilly | 1.900 m | **16,3 m/s** (116,5 s) | — | — | ídem |
| PSI 4 años, Chantilly | 2.100 m | **16,0 m/s** (130,9 s) | — | — | ídem |
| PSI, carreras de Victoria y Tasmania (25.259 salidas) | varias | 16,63 m/s | — | últimos 200 m: 15,86 m/s | [Morrice-West 2020](https://madbarn.com/research/variation-in-gps-and-accelerometer-recorded-velocity-and-stride-parameters-of-galloping-thoroughbred-horses); [Wong 2023](https://minerva-access.unimelb.edu.au/server/api/core/bitstreams/45ea7c0b-7de5-4213-961a-0750167243c1/content) |
| PSI, JRA | 1.200 m | 15,9 m/s | — | FC pico 213,6 lpm | [Mukai 2007](https://www.jstage.jst.go.jp/article/jes/18/4/18_4_153/_article) |
| Árabe Gr1, Qatar Arabian World Cup, ParisLongchamp 2024 | 2.000 m | **14,70 m/s** (2'16"03) | 11,89 s = **16,82 m/s** | 63,47 km/h = 17,63 m/s; últimos 600 m en 36,92 s | [France Galop](https://www7.france-galop.com/Casaques/Tracking//20241006LON04_last_times_fr.pdf) |
| Árabe Gr1 yeguas de 4 años, Saint-Cloud 2025 (táctica) | 2.000 m | **13,92 m/s** (2'23"71) | 12,05 s = 16,60 m/s | 61,38 km/h = 17,05 m/s; 5 primeros en 0,61 s | [France Galop](https://www7.france-galop.com/Casaques/Tracking//20251003SAI04_last_times_fr.pdf) |
| Árabe, récord en Polonia 2024 | 1.600 m | 15,1 m/s (1:45,9) | — | últimos 500 m a 14,6 m/s | [polskiearaby](https://polskiearaby.com/?p=38229) |
| Árabe, Turquía (233.491 registros) | varias | arena 13,45 / hierba 14,34 m/s | — | — | [Önder 2022](https://pmc.ncbi.nlm.nih.gov/articles/PMC9559003) |

De estas referencias salen cuatro conclusiones. Los cálculos de velocidad son propios sobre los tiempos publicados [I].

1. **El árabe de Grupo corre a ≈88–92 % del ritmo del PSI de media distancia, y su final de 200 m (16,6–16,8 m/s) se acerca al ritmo medio del PSI.**
2. **Perfiles actuales de Track Work.** Los umbrales árabes (10/13/13,5 m/s) equivalen al 68/88/92 % de 14,7 m/s. Los del PSI (11/14,5/15 m/s) equivalen al 67/88/91 % de 16,5 m/s. **Son coherentes entre razas** si se expresan como porcentaje del ritmo de carrera, que es como deberían definirse [I].
3. **Comparación de zancada.** En el árabe conviene comparar la zancada a **13 y 14 m/s** en lugar de a 13 y 15. Los 15 m/s quedan por encima del ritmo medio de muchos árabes de nivel medio [I].
4. **Coincidencia de umbrales.** El umbral «rápido ≥14,5 m/s» del PSI coincide numéricamente con el corte de VHRmax de Gramkow (<14,5 m/s, bajo nivel). Son conceptos distintos y no deben mezclarse en pantalla.

### La playa de Laredo

No hay datos publicados de galope sobre arena de playa, ni seca ni mojada. El único dato cuantitativo comparable es el de Turquía, donde la arena de pista deja la velocidad media **≈0,9 m/s por debajo** de la hierba ([Önder 2022](https://pmc.ncbi.nlm.nih.gov/articles/PMC9559003)). En dirt, sintética y césped, la fuerza pico varía hasta un 29 % ([Setterbo 2009](https://madbarn.com/research/hoof-accelerations-and-ground-reaction-forces-of-thoroughbred-racehorses-measured-on-dirt-synthetic-and-turf-track-surfaces)).

Para la playa, el motor debe [I]:

- tratar «playa» como superficie propia, con línea base separada para la zancada, la FC a velocidad fija y la velocidad final;
- registrar la franja de arena (seca, húmeda o en la orilla) y la hora de marea;
- no trasladar a la playa los multiplicadores de σ de otras superficies.

## Especificación del motor MotorAVO Equine

La especificación está pensada para C++17 sin dependencias, con coste O(1) o O(n) por sesión, y es común a Android, Windows e iPad.

Convención de entrada:

- `v(t)`: velocidad RTK a 10–20 Hz.
- `a(t)`: aceleración de la cincha (en el prototipo, BNO085 a ±8 g; en la BETA, LSM6DSV16X a ±16 g).
- `RR`: intervalos RR del ECG de una derivación, cuando exista.

Todas las métricas nuevas pueden calcularse en el motor a partir del RAW `.avr` sin tocar `BackStatus v3`, `TELEMETRY v3` ni `AVO1` [I]. Si se decide transmitir alguna en vivo, el cambio de protocolo debe hacerse a la vez en el firmware y en las tres apps.

### Preprocesado, bandas y segmentación

**Velocidad de referencia por caballo** [I]: `v_ref = mediana(velocidad media de las 3 últimas carreras válidas)`. Por defecto, 16,5 m/s en el PSI y 14,5 m/s en el árabe. Con el tiempo se sustituye por el mejor tramo de 400 m del caballo.

**Bandas de velocidad del PSI** [E en sus cortes, I en la agrupación]:

| Banda | Velocidad | Base del corte |
|---|---|---|
| B0 | <6,7 m/s (paso y trote) | — |
| B1 | 6,7–11 m/s (canter lento) | — |
| B2 | 11–13,3 m/s (canter de trabajo) | — |
| B3 | 13,3–14,3 m/s (galope lento de Victoria) | [Morrice-West 2021](https://madbarn.com/research/association-of-thoroughbred-racehorse-workloads-and-rest-practices-with-trainer-success) |
| B4 | 14,3–15,5 m/s | — |
| B5 | 15,5–16,7 m/s (dosis protectora) | [Morrice-West 2023](https://www.frontiersin.org/journals/veterinary-science/articles/10.3389/fvets.2023.1260554/pdf) |
| B6 | >16,7 m/s | — |

El corte de 14 m/s de Verheyen se conserva como contador aparte: `D_>14`. La definición exacta de «canter ≤14 m/s» debe comprobarse en el original [NV]. En el árabe, las mismas bandas se definen como fracción de `v_ref` (B3 = 0,80–0,86·v_ref, etc.) [I].

**Segmentación** [I]: el motor separa tramos rectos y curvos por la curvatura de la trayectoria RTK, `κ = |dθ/ds|`, y marca un tramo como curva cuando su radio es menor de 150 m. Separa también los tramos estables, aquellos en los que `|dv/dt| < 0,3 m/s²` durante 5 s o más. Y descarta los 20–30 s iniciales para la FC.

**Bandera de calidad** [I]: un tramo solo es «comparable para la línea base» si coinciden la superficie, la recta, la mano y el tipo de trabajo.

### Carga externa, EWMA y monotonía

**Carga externa:**

```
D_b(ventana) = Σ metros en la banda b              (ventanas de 7, 30, 60 y 365 d)
N_b          = Σ zancadas en la banda b            (zancadas detectadas por IMU; si no hay, d·f(v)/v)
```

Los contadores de 30 días (`D_>14`, `D_B2`) se apoyan en Verheyen [E]. Los de 60 días se apoyan en Estberg [E].

**EWMA:**

```
EWMA_t = λ·carga_t + (1 − λ)·EWMA_{t−1},  con λ = 2/(N+1)
```

λ vale 0,25 para N = 7 y 0,069 para N = 28. Esta fórmula es de Williams 2017 y no se ha verificado aquí [NV]. Equivale a la recurrencia discreta de Banister, `g(n) = e^(−1/τ)·g(n−1) + ω(n)`, que sí está publicada ([Montmain, arXiv](https://arxiv.org/pdf/2609.26506)) [E en su forma, sin validación equina].

**ACWR:** se muestran las dos líneas por separado. Si se calcula un cociente, que sea **desacoplado** (la ventana crónica excluye la semana aguda) y solo informativo [I]. El ACWR clásico sufre un acoplamiento matemático espurio ([Lolli 2019](https://bjsm.bmj.com/content/53/15/921.abstract)). Su única aplicación equina (eventing) dio efectos contradictorios: OR **3,95** en la semana previa y **0,133** en la actual ([Prev Vet Med](https://www.sciencedirect.com/science/article/pii/S0167587719306932)). El ACWR de VeDBA de Track Work 1.0 queda como **indicador experimental**, no como alerta.

**Monotonía y strain** (Foster) [NV]: `monotonía = media diaria / DE diaria` sobre 7 días, con los ceros incluidos, y `strain = carga semanal · monotonía`. Son indicadores informativos.

**Banister** [E en su forma; uso con cautela]: se calcula con τ fijos y no se ajusta por caballo. Sus parámetros están mal condicionados ([Hellard 2006](https://coachsci.sdsu.edu/csa/vol161/hellard.htm)), y el componente de fatiga no mejora la predicción (p > 0,40) ([Marchal 2025](https://library.kab.ac.ug/Record/doaj-art-b0487c71f0ab4ccbbee98e52bad2c766/Description)). En pantalla debe aparecer como «carga crónica», nunca como «forma = fitness − fatiga».

### Fatiga ósea por zancada (modelo A, Morrice-West 2022)

Por cada zancada i con velocidad media `v_i` (RTK interpolado entre eventos de la IMU), se calcula [E, [Morrice-West 2022](https://www.nature.com/articles/s41598-022-14274-y)]:

```
F_i   = 2,778 + 2,1376·v_i − 0,0535·v_i²          [N/kg]
σ_i   = σmax · F_i / 24,13                         [MPa]
Nf_i  = 10^((σ0 − σ_i)/14,1),   σ0 = 134,2 MPa
SBFL  = 100 · Σ_i (1/Nf_i)                         [%]
```

Filtros de calidad publicados por zancada: velocidad de 12,57 a 21 m/s, SL de 5,3 a 9,2 m y duración de 0,37 a 0,49 s. Por debajo de 12,57 m/s, el motor puede integrar igualmente pero debe marcar el resultado como «extrapolado» [I].

`σmax` es configurable: 90 MPa por defecto en el PSI, con un rango publicado de 54 a 90 MPa [E]. En el árabe se usa el mismo valor marcado como «sin calibrar», y en la interfaz se muestra **relativo a la carrera de referencia del caballo** [I].

Hay cuatro avisos de implementación:

- **El máximo de la parábola** cae en **19,98 m/s** (F = 24,13 N/kg), no en los 20,99 m/s del texto. Por encima de 20 m/s, F debe saturarse en 24,13 [I, cálculo propio].
- **σ0** vale 134,2 MPa en Martig y Morrice-West. Una fila truncada de la tabla de Anwar da 139,0 [NV]. Con 139,0 MPa, la carrera de prueba baja del 8,6 al 3,9 %, así que conviene parametrizarlo.
- **Pendiente:** el daño se multiplica por 10 por cada 14,1 MPa, así que un ±17 % en σ por superficie cambia el resultado en órdenes de magnitud. Los multiplicadores de superficie de Setterbo (sintética ≈0,83, césped ≈1,17 frente a dirt) solo deberían usarse como categoría [I].
- **Pista:** el estado *Good* frente a *Heavy 10* entra en el modelo publicado como covariable, con un coeficiente de 2,37 [E].

**Pruebas unitarias** (cálculo propio con las ecuaciones publicadas; frecuencia por la ec. 14 de Anwar; tolerancia sugerida ±0,05 en puntos porcentuales):

| Caso | Entrada | σ (MPa) | Nf | Zancadas | SBFL esperado |
|---|---|---|---|---|---|
| T1 | 1.200 m a 16,7 m/s, σmax 90 | 87,86 | 1.935 | 167,1 | **8,64 %** (publicado: 9,34 % ± 1,64 de media) |
| T2 | igual que T1, σmax 54 | 52,71 | 6,01·10⁵ | 167,1 | 0,028 % (publicado a 54 MPa: 0,03 %) |
| T3 | 600 m a 16,0 m/s, σmax 90 | 86,84 | 2.284 | 86,1 | 3,77 % |
| T4 | 2.000 m a 12,0 m/s, σmax 90 | 77,30 | 10.849 | 354,8 | 3,27 % |
| T5 | igual que T1, σ0 = 139,0 | 87,86 | — | 167,1 | 3,94 % |
| T6 | v = 25 m/s | F saturada en 24,13 | — | — | sin valores negativos ni NaN |

### Modelo diario con adaptación y reparación (modelo B, Pan/Anwar)

El modelo trabaja con dos estados por caballo y paso de un día (Euler o RK4): la fracción de volumen óseo `f_BM` (al inicio, 0,61) y el daño `D*` (al inicio, 0; el valor 1 equivale a fallo). Las ecuaciones están publicadas [E, [Anwar 2026](https://arxiv.org/html/2603.22680); [Pan 2025](https://www.biorxiv.org/content/10.1101/2025.04.06.646486v1.full)]:

```
df_BM/dt = (A_OBL − A_OCL)·α·S_v
S_v      = a·√(1−f_BM)·[1 − b(1−f_BM)]
A_OBL    = A_OBLmin + (A_OBLmax − A_OBLmin)·ψ^γB/(δB^γB + ψ^γB)
A_OCL    = A_OCLmin + (A_OCLmax − A_OCLmin)·δC^γC/(δC^γC + ψ^γC)
ψ        = σ²/(2E);   E = E0·ε̇^γE·f_BM³;   ε̇ = 0,01548·s + 0,0004955·s²
dD*/dt   = Σ_i v_D(σ_i)·v_n,i − [A_OBL + (F_s−1)·A_OCL]·α·S_v·D*/f_BM
v_D(σ)   = 10^((σ−σ0)/σ1)·E_nom/E;   v_n = d·f/s
```

Para el estímulo y la rigidez se toman `σ = max_i σ_i` y `ε̇ = max_i ε̇_i` del día.

| Parámetro | Valor | Parámetro | Valor |
|---|---|---|---|
| α | 0,19 | b | −0,02 |
| a | 11,42 mm⁻¹ | E0 | 2.500 MPa |
| γE | 0,06 | A_OBLmin / A_OBLmax | 0,001094 / 0,00603 mm/d |
| δB | 7 MPa | γB | 1 |
| A_OCLmin / A_OCLmax | 0,001 / 0,00358 mm/d | δC | 1 MPa |
| γC | 2 | σ1 | 14,1 MPa |
| E_nom | 1.714,1 MPa | F_s | 5 |
| σmax | 90 MPa | F_max | 24,13 N/kg |

Hay dos inconsistencias que verificar antes de usarlo [NV]:

- σ0 (134,2 frente a 139,0 MPa).
- `E_nom` se calculó con f_BM = 0,9: `2500·0,9³·0,36^0,06 = 1.714,1` [comprobado]. Pero la condición inicial es f_BM = 0,61. Con 0,61, a 16 m/s, E ≈ 535 MPa y la corrección `E_nom/E ≈ 3,2` triplica el daño por ciclo [I, cálculo propio]. Hay que confirmar en el PDF qué región ósea representa cada valor.

Las pruebas de regresión deben reproducir los escenarios publicados de Anwar con sus programas de entrenamiento:

- programas progresivos: D* máximo de 0,813, 0,913 y 1,016;
- reposos de 4, 6 y 8 semanas: 0,992, 0,833 y 0,713;
- 1, 2 y 3 reposos al año: 1,543, 0,911 y 0,799.

Hacen falta las tablas 1 y 2 del PDF. Ojo: la discusión da **0,852** para 2 reposos al año y la tabla 7 da **0,911**.

En la app, el modelo B se usa **para comparar escenarios de reposo y volumen** («este plan acumula más daño que el anterior»). Nunca para dar una probabilidad de fractura [I].

### Índice tendinoso heurístico

No hay modelo de tendón calibrado, así que el índice es una composición explícita [I]:

```
T_carga = Σ_i (F_i/24,13)^m      con m configurable (hipótesis: alto, p. ej. 8–10) [NV]
T_term  = minutos continuos a ≥B3 por sesión                        (motivo: hipertermia del núcleo [E])
T_patrón = banderas de [E] Choi & Parkin 2025:
           cociente de días de galope 60d/90d ≤ 1,6;  ≤2 días de galope en 60 d;
           vuelta tras ≥90 d sin trabajo rápido;  ≥41 días de canter en 180 d
```

Cualquier bandera de T_patrón activa la recomendación «considerar ecografía de TFDS (área de sección y edema)», el único marcador validado ([PMC12699112](https://pmc.ncbi.nlm.nih.gov/articles/PMC12699112/)). Nunca da un diagnóstico.

### Relación FC–velocidad, recuperación y fases de la sesión

**V200 y VHRmax** [E: método de [Vermeulen & Evans 2006](https://www.researchgate.net/publication/51384035_Measurements_of_fitness_in_Thoroughbred_racehorses_using_field_studies_of_heart_rate_and_velocity_with_a_global_positioning_system)]. Se toman medias de 5 s de (v, FC) en tramos estables de trote y galope, se excluyen las aceleraciones y la FC menor de 110 lpm [I], y se ajusta por mínimos cuadrados la recta `FC = a + b·v`. Entonces:

```
V200   = (200 − a)/b
VHRmax = (HRmax_obs − a)/b
```

`HRmax_obs` es la FC más alta del caballo que se mantiene al menos 5 s en el historial reciente.

Requisitos de validez [I]:

- al menos 3 escalones de velocidad distintos;
- R² ≥ 0,9;
- rango de velocidad de 5 m/s o más.

Prueba unitaria [I]: con los puntos (5; 130), (8; 165), (11; 195) y (13; 215), la recta sale `b = 10,578`, `a = 78,401`, **V200 = 11,495 m/s** y **VHRmax(218) = 13,197 m/s**.

Interpretación:

- Un cambio de **≤2 % se considera ruido** [E].
- Un cambio real exige superar `max(√2·TE, SWC)` (ver las líneas base).
- HRmax no es un índice de forma, porque no cambia con el entrenamiento [E].

**Fases de la sesión** [E: [Van Erck-Westergren 2026](https://academic.oup.com/jvim/article/40/2/aalag044/8539596)]:

| Fase | Definición |
|---|---|
| Calentamiento | hasta la fase máxima |
| Máxima | FC estable por encima de 185 lpm |
| Recuperación rápida | tras la fase máxima |
| Recuperación lenta | FC por debajo de 120 lpm de forma sostenida |

**Recuperación** [I]: se guardan la FC a 1, 2, 5, 10 y 15 min tras el final del tramo más rápido, y el tiempo hasta bajar de 120 lpm. Se usa **solo como tendencia del propio caballo**, porque no predijo el resultado entre caballos [E: [Schrurs 2024](https://madbarn.com/research/cardiovascular-fitness-and-stride-acceleration-in-race-pace-workouts-for-the-prediction-of-performance-in-thoroughbreds)]. El motor anota la temperatura y la humedad, y no compara recuperaciones entre condiciones térmicas distintas [E: [Art 1995](https://madbarn.com/research/physiological-measurements-in-horses-after-strenuous-exercise-in-hot-humid-conditions)].

**HIIT** [E: [Mukai 2026](https://madbarn.com/research/physiological-adaptations-to-6-weeks-of-high-intensity-interval-and-moderate-intensity-continuous-training-in-horses-a-randomized-crossover-study)]: la «velocidad a FC máxima» del ensayo es el equivalente en cinta de VHRmax. Sirve para evaluar plantillas interválicas.

### ECG: ectopia, calidad y avisos

**Requisitos de señal:** muestreo de **≥500 SPS**, con precedente validado en el Equimetre a 500 Hz [E]. El MAX30003 de la cincha REV 5.10 y el ADS1292 de la PCB REV D deben configurarse al menos a ese ritmo [I]. La señal bruta se guarda siempre, porque el consenso exige almacenamiento y reproducción [E: [Reef 2014](https://www.tierspital.uzh.ch/wp-content/uploads/2023/04/Reef-2014-4351-JVIM-Consensus-Statement-Equine-Athletes-with-Cardiovascular-Abnormalities.pdf)].

**Calidad:** porcentaje de señal ruidosa por fase. La fase máxima se descarta si supera el **5 %** [E: Van Erck-Westergren 2026]. El detector de R debe tolerar la onda T grande del caballo [NV: no se halló un algoritmo equino específico].

**Definiciones operativas** [E: [Van Erck-Westergren 2026](https://academic.oup.com/jvim/article/40/2/aalag044/8539596)]:

```
RR_ref(i)       = mediana de los 8 RR normales previos            [I: la ventana es diseño propio]
prematuro       : RR_i < (1 − 0,04)·RR_ref                         [E: variación >4 %]
compensador     : RR_i + RR_{i+1} ≈ 2·RR_ref (tolerancia ±5 %)     [E: N-E-N = 2·RR; I: tolerancia]
doblete/triplete: 2/3 prematuros consecutivos
arritmia compleja: ≥5 despolarizaciones anormales consecutivas
sospecha FA paroxística: ≥6 RR irregularmente irregulares con QRS estrecho
                  (el CV de RR sucesivos supera un umbral a calibrar [I]) que se resuelve en la recuperación
morfología      : clasificar «ancho/estrecho» y «compensador/no compensador», nunca VPC/SVPC
```

Con una sola derivación no se distingue con fiabilidad el origen supraventricular del ventricular [E].

**Salidas por fase:** recuento de ectópicos, tasa por minuto en la fase máxima, dobletes y tripletes, latidos anchos y la bandera de sospecha de FA.

**Avisos** («revisión veterinaria», nunca diagnóstico) [I sobre la evidencia citada]:

| Nivel | Condición |
|---|---|
| Inmediato | Sospecha de FA; arritmia compleja; tripletes; ectopia durante el galope con FC desproporcionada |
| Tendencia | Tasa en fase máxima ≥3/min en ≥2 de las últimas 4 sesiones válidas, o subida sostenida del recuento en fase máxima (CUSUM) |

La tasa de ≥3/min aparece en el 10 % de los registros con buen resultado y en el 16 % con mal resultado [E]. El recuento en fase máxima tiene un OR de 1,15 por latido [E]. Un único registro no caracteriza al caballo (ICC 0,39) [E].

Tras una FA documentada, el motor bloquea los trabajos rápidos hasta el alta veterinaria. La recurrencia es alta: la odds de un nuevo episodio post-carrera es 5,3 veces mayor [E: [Nath 2021](https://madbarn.com/research/incidence-recurrence-and-outcome-of-postrace-atrial-fibrillation-in-thoroughbred-horses)].

### VFC en reposo y al ensillar

El protocolo [I sobre [Nyerges-Bohák 2021](https://journals.plos.org/plosone/article?id=10.1371%2Fjournal.pone.0259933)]:

1. Registro en reposo, a la misma hora y en día de descanso o antes de ensillar.
2. Al menos 5 min estacionarios de RR limpio, con corrección de artefactos al estilo Kubios: interpolar los RR que se desvíen más de un 20 % de la mediana local [I].
3. Salidas: `RMSSD = √(media(ΔRR²))`, SDNN y LF/HF.
4. La interpretación es solo frente al SWC propio (0,5·DE de la línea base [I]). Una bajada sostenida apunta a estrés o mala asimilación. Una subida fuera del SWC fue interpretada como posible mala adaptación en el estudio citado [E].

En los árabes, la LF/HF tiene un respaldo débil como correlato del rendimiento [E: Lublin]. El motor registra los viajes y aplica menos carga el día siguiente [I; transporte con RMSSD −35 a −40 %, E].

### Zancada: frecuencia, longitud, regularidad, fatiga, mano y desviación

**Frecuencia de zancada (doble vía):**

- **Vía GNSS** [E: [Pfau 2024](https://pmc.ncbi.nlm.nih.gov/articles/PMC11054522/)]: espectrograma de `v(t)` a 10 Hz con ventana Hamming de 64 muestras, FFT de 1.024 puntos y pico en la banda de 2 a 3 Hz.
- **Vía IMU** [I]: autocorrelación de la aceleración dorsoventral y longitudinal (ventana de 2 s) y detección de eventos por tranco.

Si las dos vías difieren en más de 0,05 Hz, el tramo se marca como «no fiable» [I].

**Longitud de zancada** [I]: integral de la velocidad RTK (o fusionada) entre dos eventos IMU consecutivos. Se publica **por tramos de 100–200 m**, no zancada a zancada, porque el error por zancada de los IMU comerciales es del 20,7 % [E: [Guyard 2023](https://mdpi.com/1424-8220/23/9/4196)]. Con GNSS a 10 Hz hay solo ~4 muestras por tranco, así que la IMU es imprescindible para el detalle dentro del tranco [I]. Se propone un EKF de error con estado [p, v, sesgo] que propague con la IMU a ≥100 Hz y corrija con RTK [I, no validado en caballos].

**Referencia de comparación** [I sobre Witte, E]:

```
SL(v) = v / f(v),   con f(v) = 1,7052 + 0,0305·v + 0,0004·v²
```

| Velocidad | f (Hz) | SL (m) |
|---|---|---|
| 13 m/s | 2,169 | 5,99 |
| 14 m/s | 2,211 | 6,33 |
| 15 m/s | 2,253 | 6,66 |
| 16 m/s | 2,296 | 6,97 |

Son puntos de partida provisionales del PSI. En el árabe, la curva debe ajustarse con los datos de la cuadra [I]. La comparación se hace a velocidad fija (PSI: 14 y 16 m/s; árabe: 13 y 14 m/s), en recta y sobre la misma superficie.

**Regularidad** [E: [Barrey 2001](https://madbarn.com/research/locomotion-evaluation-for-racing-in-thoroughbreds), I en la implementación]: `R = ρ_aDV(τ = T_tranco)`, el coeficiente de autocorrelación normalizado de la aceleración dorsoventral con un desfase de un tranco. Se compara solo dentro de la misma banda de velocidad, porque su correlación con la velocidad es de −0,47.

**Índice de fatiga** [E: [Parkes 2019](https://madbarn.com/research/the-effect-of-training-on-stride-duration-in-a-cohort-of-two-year-old-and-three-year-old-thoroughbred-racehorses), I en el uso]: pendiente de la duración de zancada (o de la SL) frente a la distancia acumulada en tramos de velocidad casi constante. La referencia en potros es de **+2,21 ms por cada 100 m**, y esa pendiente baja con las semanas de entrenamiento. Sustituye a la comparación entre la primera y la última serie.

**Mano de galope** (experimental, no validado) [I]: signo de la integral de las velocidades angulares de alabeo y guiñada y signo de la aceleración mediolateral en la fase del anterior guía, con votación por mayoría en ventanas de 2 s y contraste con la curvatura RTK. Hay que calibrar el signo según el lado de montaje de la cincha, y en la app debe aparecer como «experimental». Antes de activarlo, hay que validarlo con vídeo propio de 120–240 fps.

**Desviación del patrón propio** [I, inspirado en StrideSAFE, E]: un vector de rasgos por tramo (SF, SL, regularidad, picos dorsoventrales y longitudinales, y su relación) convertido en z-scores frente a la línea base del caballo a igual velocidad y superficie. La distancia es `‖z‖`. **Los umbrales de StrideSAFE en DE no son transferibles.** Se calibran con el TE propio.

**Saturación de la IMU** [I]:

- Prototipo (BNO085, ±8 g): un contador por eje y tranco de las muestras con `|a| ≥ 7,8 g`. Si más del 1 % de las muestras de un tramo saturan, los picos y la desviación de ese tramo quedan invalidados.
- BETA (LSM6DSV16X): configurar **±16 g y ODR ≥400–800 Hz** si se quieren picos de impacto y sacudida. Es el precedente de StrideSAFE (16 g, 800 Hz) y Xsens (±16 g) [E: [JAVMA 2024](https://avmajournals.avma.org/view/journals/javma/262/9/javma.24.02.0114.xml); [Sensors 2024](https://www.mdpi.com/1424-8220/24/24/8170)].

No hay picos publicados del tronco en g a 16–18 m/s, así que la cuadra debe medirlos con la BETA antes de decidir si ±8 g basta.

### Líneas base robustas, shrinkage, SWC y CUSUM

**Línea base** [I]: para cada caballo, métrica y contexto comparable, se toman las últimas N = 8–12 sesiones válidas y se calculan la mediana `m` y `MAD_s = 1,4826·mediana(|x − m|)`. Prueba: con los valores {6,9; 7,0; 7,1; 7,05; 6,95; 7,2; 6,85; 7,0}, la mediana es **7,0**, el MAD 0,075 y el **MAD_s 0,1112**.

**Shrinkage (arranque en frío)** [I, modelo normal-normal]:

```
μ* = (n·x̄/σ² + μ_pop/τ²) / (n/σ² + 1/τ²)
```

`μ_pop` y `τ²` son la media y la varianza de la cuadra para esa raza, edad y métrica. Prueba: con n = 3, x̄ = 10,0, σ² = 0,04, μ_pop = 9,6 y τ² = 0,09, sale **μ* = 9,9484**.

**Error típico y SWC** [E: [Hopkins, Sportscience](https://sportsci.org/jour/04/cjg.htm)]:

- `TE = DE(diferencias entre dos trabajos estandarizados repetidos con pocos días de separación) / √2`.
- `SWC = 0,2·DE entre caballos`.
- Un cambio cuenta como real cuando `|x − μ*| > max(√2·TE, SWC)`. Con TE = 0,15, el umbral de ruido es 0,212.
- Una anomalía es «fuerte» cuando el z robusto `(x − m)/MAD_s` supera 3 [I].

**CUSUM unilateral** para derivas lentas, como la caída de la SL, la subida de la FC de recuperación o la ectopia [I con valores típicos de control estadístico de procesos, no validados en caballos]:

```
S_t = max(0, S_{t−1} + z_t − k),  con k = 0,5 y h = 4
```

La alarma salta cuando `S_t > h`. Prueba: la serie z = {0,2; 1,2; 1,5; 0,8; 1,6; 1,4; 1,1} da S = {0; 0,7; 1,7; 2,0; 3,1; 4,0; 4,6}, y la **alarma salta en la 7.ª muestra**.

**Modelos mixtos** (efecto aleatorio por caballo, superficie y jinete): se ajustan offline en Windows y se exportan como priors (`μ_pop`, `τ²`) para el motor móvil [I].

### Índices de carrera a partir de los PDF de France Galop

**Índice de desaceleración final** [I sobre [Mercier & Aftalion](https://journals.plos.org/plosone/article?id=10.1371%2Fjournal.pone.0235024)]:

```
IDF = v_media(últimos 400 m) / v_media(carrera)
```

También se guarda la pendiente de los parciales de 200 m en los últimos 600 m. Prueba con AL GHADEER 2024: los últimos 400 m (11,89 + 12,51 = 24,40 s) dan 16,39 m/s frente a 14,70 m/s de media, así que **IDF = 1,115** [I, cálculo propio]. Es una carrera de final rápido, no de caída.

El motor corrige por hipódromo (curvas y pendiente), separa las carreras tácticas (parciales medios de más de 15 s por 200 m en el árabe) y relaciona el IDF y la valeur con la velocidad de los últimos 600 m del trabajo de referencia más reciente (≤14 días antes), siempre dentro de cada caballo [I]. Con suficientes caballos, de ahí sale una pendiente propia de puntos de valeur por m/s.

### Reglas de aviso

Estas reglas producen «revisar», «limitar» o «bloquear». Las de seguridad mandan sobre cualquier optimización.

| ID | Regla | Umbral por defecto | Etiqueta |
|---|---|---|---|
| A1 | Canter acumulado alto (PSI) | `D_B1+B2` (≤14 m/s) >40 km en 30 d: aviso; >44 km: limitar | [E] Verheyen; [I] aviso al 90 % |
| A2 | Galope rápido acumulado (PSI) | `D_>14` >6 km en 30 d: limitar | [E] Verheyen |
| A3 | Aumento brusco en 60 d | `D_>14`(60 d) >1,3–1,4 veces la media propia de 60 d de la temporada | [E] Estberg (+40 % → ×3,9); [I] corte |
| A4 | Carga demasiado baja antes de correr | Menos de 2 sesiones en ≥B4 en los 28 d previos a una carrera prevista | [E] Morrice-West 2025 (carga baja ×2,89); [I] corte |
| A5 | Vuelta tras un parón | ≥60 d sin ≥B4: «periodo de riesgo» de 21 d con progresión limitada de B4+ | [E] Carrier (RR 71 a 10 d, 45 a 21 d) |
| A6 | Retorno tendinoso | ≥90 d sin trabajo rápido, o cociente de días de galope 60/90 ≤1,6: aviso y sugerencia de ecografía | [E] Choi & Parkin |
| A7 | Caída de zancada | SL a velocidad de referencia ≥10 cm por debajo de la línea base en ≥2 de 3 sesiones comparables | [E] Wong (HR 1,11/10 cm); [I] extrapolado al entrenamiento |
| A8 | Caída de velocidad final | Últimos 600 m del trabajo de referencia ≥0,1–0,2 m/s por debajo de la línea base, superando √2·TE | [E] Wong (HR 1,18/0,1 m/s), Schrurs; [I] |
| A9 | Pérdida de forma o sobreentrenamiento | V200 o VHRmax por debajo de `max(√2·TE, SWC)` en ≥2 sesiones; si persiste ≥14 d con carga reducida, revisión veterinaria | [E] Vermeulen, de Graaf-Roelfsema; [I] |
| A10 | Peso | Bajada >2 % en 2–3 semanas con la ingesta normal | [E] Tyler (precede ~3 semanas); [I] umbral |
| A11 | ECG | Ver la tabla de avisos del ECG | [E]/[I] |
| A12 | Rabdomiólisis | Potranca joven y nerviosa con historial de «atado», tras ≥1 d de descanso: calentamiento largo y vigilancia | [E] MacLeay |
| A13 | Recuperación tras esfuerzo intenso | Menos de 48–72 h desde una carrera, un trial o un HIIT: bloquear ≥B4 | [E] glucógeno en trotones; [I] traslado |
| A14 | Saturación de la IMU | Más del 1 % de muestras ≥7,8 g en el tramo: invalidar métricas de pico | [I] |
| A15 | Desviación del patrón | ‖z‖ robusto >3 en ≥2 tramos de la sesión, o CUSUM > h | [I] |

## Marco de recomendación del plan semanal

El recomendador debe ser un **sistema de reglas más un planificador por restricciones**, explicable por diseño. El aprendizaje por refuerzo queda descartado: con 10–60 caballos no hay simulador validado de la respuesta equina, la función de recompensa es ambigua y los errores los pagan los animales [I sobre la revisión de recomendadores deportivos, [arXiv 2312.03785](https://arxiv.org/pdf/2312.03785)]. El razonamiento basado en casos («caballos parecidos en una situación parecida») tiene precedente explicable en maratón ([Smyth & Cunningham 2020](https://dl.acm.org/doi/fullHtml/10.1145/3383313.3412220)) y es la evolución natural cuando la cuadra acumule temporadas.

### Capa 1: reglas duras

Se evalúan antes que nada y no se pueden saltar sin una anotación firmada por el entrenador o el veterinario [I]:

- Las reglas A2, A5, A11 (nivel inmediato) y A13 bloquean el trabajo rápido.
- Cualquier `HorseEvent` veterinario abierto bloquea según su tipo.
- Entre dos trabajos ≥B4 hay al menos 48 h, y 72 h si uno fue una carrera, un trial o un HIIT.
- Nunca se programan HIIT en días consecutivos [I sobre el protocolo de 3 días/semana de [Mukai 2026](https://madbarn.com/research/physiological-adaptations-to-6-weeks-of-high-intensity-interval-and-moderate-intensity-continuous-training-in-horses-a-randomized-crossover-study)].
- Los reposos se planifican: al menos 2 al año o de 6 semanas o más en adultos [E-modelo: Anwar]. En los 2 años se prefieren reposos cortos y frecuentes, porque las alternativas tuvieron IRR de 2,36 a 4,02 [E: [Morrice-West 2023](https://www.frontiersin.org/journals/veterinary-science/articles/10.3389/fvets.2023.1260554/pdf)].

### Capa 2: planificador por restricciones

**Variables:** `d[día][banda]`, en metros, para 7 días y bandas de B0 a B6, más el tipo de sesión de cada día (descanso, paso, canter, rápido, HIIT, trial o carrera).

**Entradas del entrenador:**

- objetivo: fecha de carrera, distancia y superficie;
- fase: base, carga, mantenimiento, afinamiento o descarga;
- plantilla de microciclo;
- disponibilidad de pista o playa según la marea.

**Restricciones:** las reglas A1–A6 proyectadas sobre las ventanas de 30 y 60 días incluyendo la semana planificada, las reglas de la capa 1 y los límites por edad.

**Objetivo:** acercar la carga crónica de B4–B5 a la banda «media» de la cuadra y garantizar un estímulo mínimo semanal de alta velocidad. Ese mínimo son unas decenas de zancadas en B5, porque la formación ósea se satura hacia los 36 ciclos al día [E-modelo: Pan]. A la vez, se minimizan el SBFL semanal y la monotonía.

El espacio es pequeño (7 × 7) y se resuelve por enumeración de plantillas o con programación lineal entera en el dispositivo [I].

**Plantillas por defecto** [I; todas configurables, todas sujetas a las restricciones]:

| Perfil | Trabajo fuerte semanal | Segundo estímulo | Volumen | Control mensual |
|---|---|---|---|---|
| PSI adulto, preparación | 1 trabajo de 800–1.000 m con los últimos 600 m en B5 (≈3,8–6,3 % de SBFL) | 1 trabajo medio de ≤1.000 m en B3, o HIIT experimental de 6 × 30 s con 30 s suaves | Canter B1–B2 de 2–3 km en 3–4 días | `D_>14` ≤6 km en 30 d; galope total ≥13,3 m/s de 7,5–15 km hasta el trial |
| PSI 2 años | 0,5–1 *breeze* corto por semana (≤400 m en B5) desde la semana 4 de la preparación | *Three-quarter pace* de ≈400 m/semana | Preparaciones de unas 7 semanas | Patrón de Queensland [E] |
| Árabe de carreras | 1 trabajo de 800–1.000 m con los últimos 600 m al 93–100 % de `v_ref` | 1 trabajo medio al 80–86 % de `v_ref` | Canter al 68–80 % de `v_ref`; fase de base más larga por el debut tardío | Sin topes publicados: usar los del PSI escalados y vigilar A6 y A7 |
| Afinamiento | Último trabajo fuerte 5–7 d antes de la carrera, corto | — | Volumen −30 a −50 % | [NV]: no hay evidencia cuantificada sobre el último trabajo antes de la carrera |
| Entre carreras | 14–21 d entre salidas por defecto; aviso a partir de 28 d sin carrera ni trial dentro de la preparación | — | — | [E] asociación a nivel de entrenador: Morrice-West 2021 |

El galope total de 7,5–15 km hasta el trial procede de [Morrice-West 2021](https://madbarn.com/research/association-of-thoroughbred-racehorse-workloads-and-rest-practices-with-trainer-success). El patrón de los 2 años procede de [Crawford 2021](https://www.mdpi.com/2076-2615/11/4/928).

Dos reglas de adaptación basadas en el modelo de ritmo [I sobre Mercier & Aftalion]:

- Si el IDF de las carreras es bajo (caída final marcada), se propone repartir mejor el esfuerzo en el trabajo fuerte, con un primer parcial más lento, antes que añadir velocidad punta.
- Si el perfil de zancada es de sprinter (SF alta a velocidad fija y SL corta), se sugiere revisar la elección de distancia. El genotipo MSTN entra como dato previo opcional.

**Calentamiento antes del trabajo fuerte** [I sobre [Mukai 2011](https://madbarn.com/research/effects-of-three-warm-up-regimens-of-equal-distance-on-vo2-kinetics-during-supramaximal-exercise-in-thoroughbred-horses)]: unos 2 min de galope a ritmo de trabajo, controlado por GNSS, y unos 10 min de pausa activa.

### Capa 3: explicación y confianza

Cada recomendación lleva la regla que la generó, los números, la desviación respecto de la línea base y un nivel de confianza que depende de las semanas de datos comparables. Por ejemplo: «Galope >14 m/s en 30 d: 5,1 km de 6; con este plan, 5,9 km. V200 +1,2 % (ruido ±2 %). SL a 16 m/s: −4 cm, dentro del SWC. Confianza media: 6 sesiones comparables».

La interfaz debe distinguir siempre la evidencia [E] de los umbrales propios [I]. Y ninguna mejora de la V200 debe autorizar por sí sola una subida de la carga de alta velocidad: el corazón se adapta en semanas, y el hueso y el tendón en meses [I].

## Datos que conviene registrar y cómo validar con la cuadra

### Esquema de datos mínimo

| Entidad | Campos clave |
|---|---|
| `Session` | Fecha y hora; superficie (pista o playa: arena seca, húmeda u orilla; hora de marea); estado del terreno o penetrómetro si existe; sentido de giro; jinete y su peso; herraje; tipo de trabajo y plantilla; temperatura y humedad; transporte previo; RPE o comportamiento según el jinete (rehúsa, cambia de aire, ruido respiratorio); bandera «comparable para base»; saturación de la IMU; % de ruido del ECG |
| `HorseEvent` | Tipo (lesión musculoesquelética, tendón, cojera con grado AAEP, respiratoria, EIPH, cardiaca, rabdomiólisis, cólico, sistémica, herraje); región y lado; gravedad; días perdidos; diagnóstico veterinario; fuente; confirmación; pruebas (ecografía del TFDS con área de sección, endoscopia, gammagrafía o TC, CK/AST) |
| `RaceResult` | Fecha, hipódromo, distancia, superficie y terreno, cajón, peso, puesto, tiempo, parciales de 200 m y velocidad máxima (PDF de France Galop), valeur o rating |
| `Horse` | Raza, sexo, fecha de nacimiento, fecha de debut, MSTN opcional, peso corporal semanal, temperamento |
| Exposición | Días disponibles y no disponibles, como denominador de tasas por 1.000 días |

El esquema de eventos y exposición es diseño propio [I]. Se justifica porque la superficie, la pista y el jinete cambian la SL hasta 30 cm ([Pfau 2024](https://pmc.ncbi.nlm.nih.gov/articles/PMC11054522/)) y porque la falta de etiquetas estructuradas limita cualquier modelo futuro ([Bogossian 2024](https://doaj.org/article/052082a0d2af496ca5912cf4c2600d3b)).

### Plan de validación por fases

Todas las fases son diseño propio [I]. Cada una exige distinguir lo que se ha compilado en CI de lo que se ha verificado en hardware real.

**Fase 0: corrección numérica.** Se pasan las pruebas unitarias de este informe: SBFL de T1 a T6, V200, MAD, shrinkage, CUSUM e IDF. Después, la regresión del modelo B contra las tablas de Anwar, cuando se obtenga el PDF.

**Fase 1: validez técnica con el prototipo.** Se hacen cinco comprobaciones:

1. La SF por IMU frente a la SF por espectro RTK, con un objetivo de diferencia ≤0,05 Hz.
2. La SL por tramos frente a la distancia RTK entre conos.
3. La saturación del BNO085 a 15–17 m/s en recta, sobre pista y sobre playa.
4. La detección de mano frente a vídeo de 120–240 fps (al menos 200 tramos por mano y lado de montaje).
5. Cuando exista la cincha con ECG, la ectopia frente a la revisión manual de un veterinario o frente a un dispositivo de referencia.

**Fase 2: fiabilidad.** Se repite el trabajo de referencia de unos 1.000 m (mismo tramo, misma superficie y mismo calentamiento) dos veces en 3–7 días con 8–10 caballos. De ahí sale el TE propio de V200, VHRmax, la velocidad de los últimos 600 m, la SL a 14 y 16 m/s (13 y 14 en el árabe), la regularidad y la FC de recuperación. Esto fija los umbrales de A7–A9 con números de la cuadra.

**Fase 3: asociación con el rendimiento.** Se cruzan, dentro de cada caballo, la valeur o el puesto y el IDF de cada carrera con la última sesión de referencia (≤14 días antes), mediante un modelo mixto con efecto aleatorio por caballo, ajustado por edad (hasta unos 4,5 años en el PSI), sexo, superficie e hipódromo.

**Fase 4: seguridad.** Se registran D* y SBFL diarios con los desenlaces veterinarios, y se analizan con un modelo de Cox con covariables dependientes del tiempo o con un caso-control anidado. El rendimiento se mide con validación temporal y se reporta como PPV y número a cribar, no solo como AUC.

Una cuadra de 30 caballos tardará años en acumular eventos suficientes. Con la regla clásica de unos 10 eventos por predictor [NV], 64 lesiones solo dan para unos 6 predictores. La validación de lesiones requiere datos agregados y anonimizados entre cuadras, con consentimiento.

**Fase 5: calibración de la raza árabe.** Se ajustan las curvas f(v) y SL(v), los rangos de V200 y la `v_ref` por caballo, y se publican internamente como «referencias AVO árabe v1» con su n. Según la búsqueda, serían de los primeros datos de este tipo.

## Lo que la app no debe afirmar

La app no debe decir que **predice lesiones**. El mejor modelo de aprendizaje automático publicado tuvo sensibilidad 0 ([Bogossian 2024](https://doaj.org/article/052082a0d2af496ca5912cf4c2600d3b)). StrideSAFE, con 28.481 salidas, solo acierta una de cada 25 en su categoría de máximo riesgo, y se describe a sí mismo como una «luz de *check engine*» ([dvm360](https://www.dvm360.com/view/biometric-sensors-may-help-identify-the-few-thoroughbreds-at-highest-risk-for-fatal-musculoskeletal-injury)). El HKJC presenta sus perfiles de riesgo como ayuda para el veterinario, no como sustituto ([ICRAV 2026](https://icrav-2026.p.asnevents.com.au/days/2026-03-26/abstract/130165)).

El SBFL y el D* son **índices relativos de carga**, no probabilidades de fractura. Su valor absoluto depende de σmax y σ0, y no están calibrados en árabes.

La app no debe **diagnosticar** arritmias, FA, cojera, obstrucción de vías altas ni EIPH. Debe decir «latidos prematuros sospechosos», «ritmo irregular en recuperación» o «posible cambio locomotor: revisión veterinaria». Con una sola derivación no distingue el origen supraventricular del ventricular ([Van Erck-Westergren 2026](https://academic.oup.com/jvim/article/40/2/aalag044/8539596)).

Tampoco debe:

- **Clasificar caballos por SL o SF.** No predicen el éxito ([Schrurs 2022](https://madbarn.com/research/locomotory-profiles-in-thoroughbreds-peak-stride-length-and-frequency-in-training-and-association-with-race-outcomes)).
- **Hacer un ranking por recuperación de FC a 1 min.** No fue predictiva ([Schrurs 2024](https://madbarn.com/research/cardiovascular-fitness-and-stride-acceleration-in-race-pace-workouts-for-the-prediction-of-performance-in-thoroughbreds)).
- **Presentar el ACWR o el VeDBA como validados.**
- **Mostrar valores «de libro» como referencias clínicas.** HRmax de 210–240 lpm, V200 en pista de 9–11 m/s y VO2max de 140–200 son [NV].
- **Aplicar sin marcar al árabe los coeficientes del PSI** (Witte, Martig, Verheyen).
- **Prometer que el HIIT de cinta funciona igual en pista o en la playa.** Los ensayos tienen 7–8 caballos, se hicieron en cinta y no tienen datos de lesión.
- **Mostrar como «detectada» la mano de galope** hasta validarla.
- **Afirmar que una mejora de la V200 autoriza más velocidad.**

## Lagunas y fuentes a conseguir manualmente

Hay cuatro grupos de lagunas.

**Ecuaciones del modelo óseo.** Prioridad máxima, porque condicionan las ecuaciones del motor:

| Qué falta | Dónde buscarlo |
|---|---|
| Valor final de σ0 y región ósea de f_BM | PDF de [Anwar 2026 en RSOS](https://royalsocietypublishing.org/rsos/article/13/10/260818/483549/Balancing-training-load-rest-and-musculoskeletal) y de [Pan 2025 en JRSI](https://royalsocietypublishing.org/rsif/article/22/231/20250297/235676/A-mathematical-model-of-metacarpal-subchondral) |
| Tablas 1 y 2 de programas (para las pruebas de regresión) | PDF de Anwar 2026 |
| Curva S-N original, con su n y su R² | Martig 2013/2014 |
| Implementación de Hong Kong | ICRAV 2026 |
| Velocidad del máximo de la parábola de fuerza (19,98 frente a 20,99 m/s) | Morrice-West 2022 |

**Umbrales de carga.** Comprobar la definición exacta de canter y galope (≤14 y >14 m/s) en el texto completo de Verheyen, Bone 2006 (DOI 10.1016/j.bone.2006.05.025).

**Fisiología y rendimiento.** Textos completos de:

- Gramkow & Evans 2006 (V200, regresión completa);
- Schrurs 2024 (odds ratios y la «aceleración del tranco» del título);
- Kingston 2006 y Fonseca 2010 (índices de carga con GPS y FC);
- Mukai 2017 sobre desentrenamiento;
- Navas de Solis 2025 sobre muerte súbita (DOI 10.1002/evj.70166);
- el algoritmo de artefacto de ECG equino de PLoS One 2015 (e0140783);
- Hammond 2023 sobre VFC.

**Árabe de carreras, biomecánica y fuentes oficiales:**

- Parciales oficiales del Reino Unido (ARC), los EAU (Meydan, Abu Dhabi), Qatar y Polonia (Służewiec), y los programas AFAC e IFAHR 2026.
- La metodología pública de la valeur de France Galop y los datos de penetrómetro por carrera.
- El texto completo de Yildirim 2025 (lesiones en árabes por localización y pista).
- Los protocolos de entrenamiento de los estudios de Cracovia (TCAP, *Genes* 2025).
- Datos de MSTN en árabes puros.
- Picos de aceleración del tronco en g al galope rápido (figuras de Pfau 2006 y Witte 2004, Barrey 2001).
- Cualquier estudio de fuerza o zancada sobre arena de playa.

Esto último no existe en la literatura revisada: lo cubrirá mejor la medición propia en Laredo que cualquier búsqueda.

## Conclusión

Visto desde el hueso, la pregunta inicial ya no es «¿cuánta distancia?», sino «¿cuántas zancadas a qué carga, y con qué rapidez se acumulan?». Esa forma de plantearlo tiene una consecuencia práctica que la literatura no había hecho explícita. Con las ecuaciones publicadas, un *breeze* de 600 m cuesta lo mismo que 2 km de canter a 12 m/s, y unos 250 m rápidos ya saturan la señal de formación ósea del modelo. El riesgo está tanto en el canter de relleno como en el trabajo rápido, y el diseño semanal óptimo es corto y rápido en lo fuerte y vigilado en lo lento. AVO puede medir todo esto mejor que los estudios de referencia: tiene velocidad RTK por zancada, recuento de zancadas con IMU y, pronto, ECG en la cincha. Por eso la prioridad del motor no es inventar índices nuevos, sino implementar bien los publicados, con sus pruebas unitarias, y aprender el ruido propio de cada métrica.

Para el árabe, la ausencia de literatura es una oportunidad. Los umbrales actuales de Track Work son coherentes con el PSI si se expresan como fracción del ritmo de carrera. Pero las curvas de zancada, los rangos de V200, los topes de carga y el comportamiento sobre la arena de Laredo solo pueden salir de la cuadra. Si desde la primera semana se registran la superficie, los trabajos de referencia repetidos, las incidencias veterinarias estructuradas y los parciales de France Galop, en una o dos temporadas existirá la primera línea base longitudinal de árabes de carreras con GNSS, IMU y ECG. Será la base que permita convertir las [I] de este informe en [E] propias.
