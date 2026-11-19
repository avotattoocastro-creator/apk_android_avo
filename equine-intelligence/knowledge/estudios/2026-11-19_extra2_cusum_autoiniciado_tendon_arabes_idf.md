# Estudio extra 2 (19/11/2026): CUSUM con pocas sesiones, tendón en árabes e «IDF» de France Galop

Etiquetas: **[E]** dato de la fuente (texto completo), **[E-r]** dato de la fuente leído solo en el resumen o en una
transcripción automática, **[I]** inferencia o cálculo propio, **[NV]** no verificado o bloqueado.
Todo lo de este estudio está probado en local (pruebas y simulación); **nada está verificado con caballos reales**.
La carga tendinosa y la fatiga ósea son índices de carga, **nunca predicciones de lesión**.

## Decisiones del estudio (trabajo sin supervisión)

- Inicio 11:33 UTC; límite de 1 h (cierre a las 12:18, publicación antes de las 12:33).
- Temas elegidos de `cola_investigacion` y `pendiente_motor`, sin repetir lo ya estudiado: (1) efecto de estimar μ y σ
  con pocas sesiones en el CUSUM (Hawkins 1987, Jones, Champ & Rigdon 2004), para conectar las líneas base a Training
  Analytics; (2) OR del TFDS de Ikeda 2019 y datos nuevos de árabes; (3) definición del IDF de France Galop.
- Investigación con tres subagentes en paralelo. Las cifras transcritas por un lector web automático llevan [E-r]
  aunque el texto sea completo: hay que cotejarlas con el PDF antes de usarlas en reglas.
- Pendiente del motor elegido: **tipificación autoiniciada de Hawkins** (herramienta, sin conectar a reglas). Es
  matemática cerrada y comprobada con simulación propia; no depende de ninguna constante equina.
- No se toca firmware, contratos binarios, workflows, firmas, `Info.plist` ni TestFlight.

## 1. CUSUM cuando la línea base sale de 5–20 sesiones

### 1.1 Qué dice la literatura

| Fuente | Hallazgo | Etiqueta |
|---|---|---|
| Jones, Champ & Rigdon 2004, *J Qual Technol* 36:95, doi 10.1080/00224065.2004.11980254 | Distribución de la longitud de racha del CUSUM con μ y σ estimadas; el ARL0 real se aleja del nominal con Fase I pequeña | [NV] texto bloqueado (Taylor & Francis); no se cita ninguna cifra suya |
| Saleh, Zwetsloot, Mahmoud & Woodall 2016, *Qual Eng* 28:402, doi 10.1080/08982112.2016.1144072 | Hace falta mucha Fase I para controlar el ARL0 **condicional**; proponen ajustar h por *bootstrap* a costa de detectar más tarde | [E-r]; tablas no accesibles |
| Keefe, Woodall & Jones-Farmer 2015, *Qual Eng*, doi 10.1080/08982112.2015.1065323 | En los gráficos autoiniciados el ARL0 condicional varía, pero mucho menos que con Fase I estimada | [E-r] (resumen) |
| Hawkins 1987, *The Statistician* 36:299 (descrito por van Zyl & Lombard 2018, *S Afr Stat J* 52:93, §2.6, [PDF](https://www.journals.ac.za/sasj/article/download/5153/3218)) | Desde la 3.ª observación: V = (x_n − x̄_{n−1})/s_{n−1}; ξ = Φ⁻¹(T_{n−2}(√((n−1)/n)·V)); bajo control los ξ son N(0, 1) independientes y se usan las mismas k y h | [E-r] (original no leído) |
| Lombard & Hawkins ([arXiv 1904.00340](https://arxiv.org/abs/1904.00340)) | Con calentamiento ≥ 3 y reinicio tras cada alarma, el ARL **incondicional** es el nominal; sustituir estimaciones exige Fase I «desmesuradamente grande» | [E] |
| Sands et al. 2017, *IJSPP* 12(S2):63, doi 10.1123/ijspp.2016-0405 | El control estadístico de procesos como pilar de la monitorización del deportista (marco, sin CUSUM cuantificado) | [E-r] |
| Lacina 2020, tesis de máster, Virginia Tech | Gráficos de Shewhart sobre GPS de 28 futbolistas: **no predijeron lesiones** | [E-r] |

No se encontró ningún CUSUM ni gráfico de control publicado en caballos [NV, búsqueda incompleta].

### 1.2 Simulación propia (k = 0,5; μ y σ estimadas con media y DE de m sesiones normales)

ARL0 condicional por cadena de Markov de Brook-Evans (150 estados; con parámetros conocidos da 335,3 y 930,6);
5.000 réplicas de Fase I, semilla 20261119 [I, cálculo propio]:

| m | h | P10 | P25 | Mediana | P(ARL0 < 0,8·nominal) |
|---|---|---|---|---|---|
| 5 | 4 | 10 | 27 | 164 | 0,55 |
| 10 | 4 | 23 | 56 | 234 | 0,52 |
| 10 | 5 | 33 | 98 | 593 | 0,53 |
| 20 | 4 | 44 | 90 | 275 | 0,49 |
| 20 | 5 | 72 | 179 | 727 | 0,51 |
| 50 | 4 | 83 | 150 | 314 | 0,45 |

- Con m = 10 y h = 4, **uno de cada diez caballos** tendría una falsa alarma cada ≤ 23 sesiones, en vez de cada 335 [I].
- Con mediana y MAD es peor (m = 10: P10 = 11 con h = 4) [I]: la MAD rinde poco con n pequeño.
- Para garantizar P10 ≥ 0,8·335 con plug-in haría falta h ≈ 6 con m = 50 y h ≈ 8,3 con m = 20; con m ≤ 10 no basta
  ni h = 12 [I].
- **Autoiniciado de Hawkins, simulación propia** (20.000 réplicas, semilla 42): ARL0 = 338,8 (h = 4) y 929,9 (h = 5),
  iguales al nominal [I].

### 1.3 Consecuencia para Training Analytics (A7, A8, A9)

1. Con menos de ~50 sesiones por caballo y métrica, **no** usar el CUSUM con μ y σ fijas como si su ARL0 fuera
   335/931 [I].
2. Usar la tipificación autoiniciada (`kb_self_starting_z`) y después `kb_cusum_upper` con k = 0,5, h = 5 (muchas
   cartas a la vez) y `min_samples` = 8–10 de calentamiento sin alarmas [I].
3. No actualizar la línea base con sesiones en alarma y reiniciar tras una alarma [I].
4. Sin cuantificar: el efecto del shrinkage hacia la cuadra sobre el ARL0, la autocorrelación entre sesiones y las
   colas pesadas. Supuestos: normalidad e independencia [I].
5. El z robusto con mediana/MAD sigue siendo útil para marcar atípicos sueltos (|z| > 3,5), no para alimentar el CUSUM
   con n pequeño [I].

### 1.4 Implementado (motor 2.0.0-dev6, KB 1.4.0)

- `kb_self_starting_z(x)`: ξ de Hawkins sesión a sesión (NaN en las dos primeras válidas, en entradas NaN y con
  s = 0), con media y varianza acumuladas (Welford).
- Auxiliares `kb_student_t_cdf` (beta incompleta por fracción continua) y `kb_normal_quantile` (bisección sobre
  `erfc`), cotejadas con scipy 1.18 (error < 1e-8).
- Prueba `kb.baseline_self_starting_cusum` en `tests/test_knowledge.cpp`. **Sin conectar a ninguna regla.**

## 2. Tendón flexor digital superficial (TFDS): OR de Ikeda 2019 y datos nuevos de árabes

### 2.1 Ikeda et al. 2019, *J Equine Sci* 30:93 (PSI, hipódromo de Oi, arena; 292 casos y 584 controles)

Texto completo en [PMC6920055](https://pmc.ncbi.nlm.nih.gov/articles/PMC6920055); **todas las OR son univariables**
(sin regresión múltiple por el tamaño de muestra). Transcripción automática [E-r]:

| Factor | Comparación | OR (IC 95 %) |
|---|---|---|
| Pista | encharcada frente a estándar | 1,69 (1,14–2,50) |
| Distancia de la carrera | < 1.300 m frente a ≥ 1.300 m | 1,45 (1,09–1,93) |
| Puesto | 10.º o peor frente a 1.º–9.º | 2,50 (1,88–3,34) |
| Peso en carrera | ≥ 470 kg frente a < 470 kg | 1,55 (1,17–2,06) |
| Cambio de peso | pérdida ≥ 5 kg | 1,59 (1,08–2,34) |
| Sexo | castrado frente a hembra | 3,09 (1,40–6,84) |
| Distancia en las 3 últimas carreras | < 4.000 m frente a ≥ 4.000 m | 1,40 (1,01–1,94) |
| Distancia en las 6 últimas carreras | < 8.000 m frente a ≥ 8.000 m | 1,47 (1,03–2,08) |
| Días desde la carrera anterior | ≥ 90 frente a < 90 | 1,75 (1,05–2,92) |

Edad sin diferencia (4,0 ± 1,4 frente a 3,8 ± 1,3 años). Lectura [I]: igual que Choi & Parkin 2025, **poca carga
reciente y la vuelta tras ≥ 90 días** aumentan el riesgo; refuerza A6 y A6B, que ya están en el motor. Ninguna OR se
convierte en peso del índice: son univariables, en PSI y en arena japonesa.

Takahashi 2004 (*JAVMA* 225:90; JRA, 515 casos) y Lam 2007 (*AJVR* 68:1188; Hong Kong): solo resumen, sin OR [NV];
dirección: más distancia media de carrera, más peso y steeplechase (Takahashi); menos intensidad en los 180 d previos
(Lam) [E-r].

### 2.2 Árabes de carreras: cifras nuevas

| Fuente | Hallazgo | Etiqueta |
|---|---|---|
| Kalisiak 2012, *Pol J Vet Sci* 15:111, [PDF](https://journals.pan.pl//Content/99014/PDF/15_paper.pdf) (Varsovia 2001–2006; ≈ 396 árabes/año) | El TFDS es el 82,8 % de las lesiones tendinosas de árabes (24/29) frente al 92,0 % en PSI; 100 % en anteriores; sin diferencia por sexo en árabes; vida deportiva ≈ 2 años (PSI ≈ 3) | [E-r] |
| Kalisiak 2012 | Desmitis del suspensor en árabes «7,2 %» con 5 casos (5/29 = 17,2 %): probable errata | [NV] |
| Yıldırım & Karaarslan 2025, *Turk J Vet Res* 9:33, [PDF](https://dergipark.org.tr/en/download/article-file/4272043) (İzmir, 2018–2022) | Lesiones de tendón en árabes por edad: 78 a los 3 años, 47 a los 4 y 12 a ≥ 5 (pico a los 3); 51 de 137 terminaron la vida deportiva | [E-r]; no separa el TFDS |
| Çalışkan et al. 2020, *J Equine Vet Sci* 87:102931 (Turquía; 56 árabes y 62 PSI) | Vuelta a correr 70 % en total; 64,4 % con engrosamiento del tendón frente a 86,7 % sin él; raza, edad y sexo sin asociación | [E-r] (resumen; no separa por raza) |

Sin estudios de TFDS en árabes de EAU, Qatar, Francia ni Reino Unido, y **ningún** estudio que relacione carga o
velocidad acumulada con el TFDS en árabes [NV, búsqueda incompleta]. Aplicar a árabes las asociaciones de carga de
PSI es extrapolación [I].

### 2.3 Efecto sobre el índice tendinoso pendiente

Se mantiene la propuesta de bandas cualitativas del estudio extra 1. Cambios [I]: (a) el pico de edad en árabes es a
los **3 años** (más que a los 4); (b) la vuelta tras ≥ 90 días y la poca carga reciente quedan apoyadas por dos
estudios independientes (Corea, Japón); (c) el engrosamiento del tendón en la ecografía es el dato manual más útil
para el pronóstico. El índice **no** se implementa: faltan en la app la lesión previa, la ecografía y la firmeza del
suelo.

## 3. «IDF» de France Galop: no existe como métrica oficial

- No aparece «indice de décélération finale» ni «IDF» en france-galop.com, Equidia ni en los PDF de tracking de
  2021, 2023, 2024, 2025 y enero de 2026 [E-r, búsqueda del subagente]. **Corrige la base**: el «IDF» del pendiente
  era una métrica supuesta; si el motor la necesita será una **métrica propia de AVO** [I].
- Qué publican los PDF de tracking (McLloyd, Longines): por caballo, tramos de 200 m con tiempo, velocidad media,
  posición y, en 2025, número de *foulées*; velocidad máxima, tramo más rápido, «derniers 600 m» y *redk* (réduction
  kilométrique = tiempo por km; 119,31 s / 1,85 km = 1'04"49 en el PDF de Big Log, 14/09/2025) [E-r, comprobación I].
  El propio PDF avisa de que los tiempos del tracking no están sincronizados con el cronometraje oficial [E-r].
- Cobertura: ParisLongchamp desde el Arc de 2019; Chantilly y Deauville en noviembre de 2019; despliegue nacional en
  enero de 2021 (objetivo de 44 hipódromos), según [France Galop](https://www.france-galop.com/en/content/national-rollout-mclloyd-tracking-system-french-premium-courses) [E-r]. Las carreras PA
  (Qatar Arabian World Cup) tienen tracking [E-r].
- **Métrica de referencia publicada:** Finishing Speed % de Timeform = 100·(velocidad del tramo final)/(velocidad
  media de la carrera); últimos 2 furlongs hasta la milla y 3 en distancias mayores; lo útil es el «par» de cada pista
  (p. ej. ≈ 101 % en la milla de Ascot, ≈ 108 % en el Derby de Epsom), no el 100 %
  ([Timeform](https://www.timeform.com/horse-racing/features/sectionals/an_introduction_to_sectional_timing_part_2)) [E-r].
- Qatar Arabian World Cup (2.000 m, ParisLongchamp), Al Ghadeer [E-r, transcripción de los PDF 20231001LON03 y
  20241006LON04]: 2'12"17 en 2023 (máxima 64,4 km/h en 400–200) y 2'16"03 en 2024 (máxima 63,5 km/h). Cálculo propio
  [I]: últimos 600 m ≈ 109–110 % de la velocidad media; los últimos 200 m, entre −2 % y −5 % respecto a los 200 m
  anteriores.
- Zancadas: el subagente lee 28 *foulées* en los últimos 200 m del Arc de 2025 (≈ 7,1 m), y la KB 1.3.0 recogía
  ≈ 8,0 m en el mismo PDF; además hay recuentos imposibles (11, 13 o 36 en 200 m) en otros PDF → **[NV]**, revisar a
  mano antes de usar recuentos de zancadas de France Galop.

Propuesta para el pendiente (no implementada) [I]: renombrar «IDF de France Galop» a **velocidad final relativa de
AVO** = v(últimos 600 m o 400 m)/v media del trabajo, con «par» propio por pista y superficie (playa por franja), y
comparar con la carrera solo a título informativo.

## Resumen

- **CUSUM:** con 5–20 sesiones, el CUSUM con μ y σ estimadas no tiene el ARL0 nominal: con m = 10 y h = 4 el 10 % de
  los caballos tendría una falsa alarma cada ≤ 23 sesiones (simulación propia). La tipificación autoiniciada de
  Hawkins recupera el ARL0 nominal (339/930, simulación propia). **Implementada** como herramienta del motor
  (`kb_self_starting_z`), sin conectar a reglas. Jones 2004 y las tablas de Saleh 2016 siguen bloqueadas.
- **Tendón:** OR univariables de Ikeda 2019 (pista encharcada 1,69; vuelta tras ≥ 90 d 1,75; poca distancia reciente
  1,40–1,47; castrados 3,09). En árabes, el TFDS es el 83 % de las tendinopatías (Kalisiak) y el pico de lesiones de
  tendón está a los 3 años (Yıldırım & Karaarslan 2025). Ningún dato de carga en árabes. El índice sigue sin
  implementar.
- **IDF:** France Galop no publica ningún IDF; se propone una métrica propia (velocidad final relativa con par por
  pista), con la Finishing Speed % de Timeform como referencia. Recuentos de zancadas de France Galop a revisar.
- **Motor:** KNOWLEDGE_VERSION 1.3.0 → 1.4.0; ENGINE_VERSION 2.0.0-dev5 → 2.0.0-dev6. Probado en local con
  ASan/UBSan; fixtures regeneradas (solo cambian las versiones). **NO VERIFICADO** con caballos reales.
- **Textos que hay que conseguir a mano:** Jones, Champ & Rigdon 2004; Saleh et al. 2016 (tablas); Hawkins 1987;
  Takahashi 2004 y Lam 2007 (OR); PDF de la QAWC 2025 (`20251005LON04`, probable); revisar a mano las OR de Ikeda 2019
  y los recuentos de *foulées* del Arc de 2025.
