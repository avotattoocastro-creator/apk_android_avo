# Estudio horario 2026-11-20 15:10 UTC — Árabes de llano (lactato, V4, tiempos de carrera) y novedades publicadas en 2026

## Decisiones tomadas sin supervisión

- **Encadenamiento:** había 4 PR `claude/kb-*` abiertos (#99, #101, #102, #104). La rama sale de la más reciente,
  `claude/kb-estudio-2026-11-20-1410` (PR #104), y hereda KB 1.16.0 y motor 2.0.0-dev18.
- **Temas elegidos** (ninguno cubierto hoy):
  - **T1:** datos fisiológicos de árabes de carreras en llano, que siguen pendientes en la cola. Se busca lactato,
    V4/V200, FC y tiempos de carrera, también en Polonia y Turquía.
  - **T2:** estudios publicados o con número de 2026 posteriores a la última fecha del `historial`.
- **Sin cambios de lógica del motor:** ninguna cifra nueva tiene la evidencia cerrada en texto completo para un umbral.
  Las de árabes son contexto (cinta, otra disciplina o una sola prueba) y las de 2026 son simulación o resumen. Solo
  suben las versiones (KB 1.17.0, motor 2.0.0-dev19).
- **Investigación:** se usaron 2 subagentes con WebSearch/WebFetch (~10 min cada uno).
- **Accesos denegados:** API de Europe PMC (403 del proxy), PubMed/PMC (reCAPTCHA), Wiley, Royal Society y BMC/Springer
  (permiso de la sesión sin respuesta). No se esquivaron con cachés ni espejos.
- **Cifras:** lo no leído queda como [NV]. Las velocidades calculadas aquí a partir de tiempos son [I].

## T1. Árabes de carreras en llano: lactato, V4 y tiempos

| Dato | Valor | Condiciones | Fuente | Etiqueta |
|---|---|---|---|---|
| Lactato justo después de un galope de 1.200 m | Tres grupos: 3,92 ± 1,14 mmol/L (24 pruebas), 10,3 ± 1,89 (18) y 16,3 ± 2,84 (11). Rango total ≈ 2,3–22 mmol/L | 36 árabes de carreras de 3–6 años, Polonia. 53 galopes de entrenamiento a 8–13 m/s en el hipódromo. Sin lactato en reposo ni a los 30 min | Kędzierski 2007, *Ann UMCS sec. DD* 62(2), [czasopisma.up.lublin.pl/mv/article/view/3544](https://czasopisma.up.lublin.pl/mv/article/view/3544) | [E] |
| Glicerol a los 30 min frente a lactato | r = 0,80 en el grupo de lactato alto | Mismo estudio | Kędzierski 2007 | [E] |
| Tiempo en 1.400 m | Árabes 1:38–1:48, es decir ≈ 13,0–14,3 m/s de media [I, calculado aquí]. PSI 1:25–1:30 | 8 sementales árabes de 3,9 ± 1,1 años, Turquía. Sin FC ni lactato de carrera | Paksoy et al. 2025, *Acta Vet Brno* 94:97, doi [10.2754/avb202594020097](https://doi.org/10.2754/avb202594020097) | [E] |
| V4 (velocidad a 4 mmol/L) y lactato por escalón | V4 8,0 m/s. Lactato: 1,7 en reposo, 3,5 a 6 m/s, 4,0 a 8 m/s, 6,2 a 9 m/s y 9,1 a 10 m/s. Recuperación: 13–15 mmol/L entre 1 y 5 min | 11 árabes adultos en cinta al 6 %, Brasil (disciplina no de carreras) | Thomassian et al. 2005, *Arch Vet Sci* 10(1):63, [core.ac.uk/download/328070186.pdf](https://core.ac.uk/download/328070186.pdf) | [E]; [I-raza] para el llano: árabes no de carreras |
| V200 y VLa4 en cinta | V200 9,51 ± 0,16 m/s y VLa4 8,27 ± 0,46 m/s (PSI 9,76 y 8,44). VO₂max 129 mL/kg/min | 5 capones árabes de 8–10 años en cinta al 3 % (no son de carreras) | Prince, Geor, Pagan et al., PDF de KER ([ker.com](https://ker.com/wp-content/uploads/Comparison-Of-The-Metabolic-Responses-Of-Trained-Arabian-And-Thoroughbred-Horses-During-Low-And-High-Intensity-Exerices.pdf)); año y revista [NV] | [E] del PDF; cita bibliográfica [NV] |
| Dąbrowska 2026 (*BMC Vet Res*, doi [10.1186/s12917-026-06055-w](https://doi.org/10.1186/s12917-026-06055-w)) | Diseño: 18 árabes; muestras en reposo, justo después y a los 30–40 min. El aclaramiento del lactato fue menor tras la carrera que tras los galopes. **Valores absolutos (tabla S4): [NV]** | Polonia (SGGW) | Solo reseña secundaria; BMC/Springer sin permiso en la sesión | [E-r] |

**Lectura para el motor [I]:**
- Tras un galope de 1.200 m, la dispersión del lactato en árabes es enorme (≈ 2–22 mmol/L). Un lactato aislado no
  sirve como umbral; si se registra, solo es comparable dentro del mismo caballo, a igual distancia y velocidad.
- La V200 de árabes en cinta (9,5 m/s) es parecida a la de los PSI del mismo estudio (9,8 m/s). Confirma el criterio ya
  vigente: **V200 solo frente a la línea base propia del caballo**, sin tabla por raza.
- La V200 de Piccione 2004 (610 m/min ≈ 10,2 m/s) es de campo y la de Prince es de cinta. No son comparables entre sí.
- Los tiempos de 1.400 m en Turquía (≈ 13–14 m/s de media) dan el primer orden de magnitud publicado de la velocidad
  de carrera de árabes de llano. Sirven para dejar un rango de **plausibilidad** de la velocidad (detección de
  artefactos GNSS), no un objetivo de rendimiento.

**Sin cifras útiles:** Grzędzicka 2023 (*Agriculture* y *Front Vet Sci*), Dąbrowska 2026 (*EVJ*, transcriptómica),
Witkowska-Piłaszewicz 2021 (cortisol), Janczarek 2016 (solo VFC), Gücüyener 2024 (solo resumen) y Ghadrdan Mashhadi
2018 (Irán, bioquímica).

**No encontrado:** FC máxima medida en galope o en carrera de árabes de llano, ni datos de Francia (AFAC), el Golfo o
el Magreb. La búsqueda en francés quedó sin hacer por tiempo.

## T2. Novedades publicadas en 2026

| Estudio | Lo relevante | Etiqueta |
|---|---|---|
| Anwar, Pan, Morrice-West, …, Hitchens 2026, *R Soc Open Sci* 13(10):260818 (preprint arXiv 2603.22680) | Modelo **in silico** de daño óseo D* (D* = 1 equivale a fallo). Con 2 descansos al año: 4 semanas → 0,992, 6 → 0,833, 8 → 0,713. Por número de descansos: 1 → 1,543, 2 → 0,911, 3 → 0,799. Sustituir el descanso por 4 semanas de trabajo suave → 0,946; 2 semanas → 1,406. Los autores advierten que no es evidencia clínica | [E] del preprint; versión RSOS [NV] (sin acceso). Coincide con el 0,911 que ya estaba en la KB |
| Espil, …, Stover, Uzal 2026, *J Vet Diagn Invest*, doi [10.1177/10406387261462107](https://doi.org/10.1177/10406387261462107) (en línea 12/08/2026) | California, 133 fracturas pélvicas catastróficas (1992–2018). Frente a los controles, los casos tuvieron más layups, un 31 % menos de tiempo de ejercicio y un 40 % menos de eventos desde el último layup. El 31,9 % tenía callo previo | [E-r]; OR [NV] |
| Hall, McSweeney, …, Bayly 2026, *JAVMA* 264(7), doi [10.2460/javma.25.08.0556](https://doi.org/10.2460/javma.25.08.0556) | StrideSAFE: 42.623 carreras. El 89 % de 53 fracturas cayó en el grupo «rojo», pero el VPP de una sola carrera es bajo (≈ 0,08–0,09). Con puntuación media > 3 en 3 salidas seguidas: VPP 0,74 y OR 133 (IC 23,5–753). Los recuentos no cuadran en la reseña | [E-r] (agregador MadBarn) |
| Legg, Gibson, Gee, Rogers, *EVJ* 58(4):925 (número de jul 2026, en línea 2025), doi [10.1111/evj.70003](https://doi.org/10.1111/evj.70003) | Nueva Zelanda, césped: 2,22 lesiones/1.000 salidas. La velocidad baja 0,089 m/s por cada 100 m más de distancia. Lesión frente a estado de pista r = −0,28 y frente a su CV r = 0,25 | [E] (PMC) |
| van Erck-Westergren et al. 2026, *J Vet Intern Med* 40(2), doi [10.1093/jvimsj/aalag044](https://doi.org/10.1093/jvimsj/aalag044) | Hong Kong: 405 ECG de ejercicio intenso. OR 1,15 por latido ectópico adicional (IC 1,04–1,28) para mala actuación posterior. La reseña da además una OR 1,8 (IC 0,86–3,81) con p = 0,02, incoherente | [E-r]; texto completo sigue en cola |
| Eamon, …, Pfau 2026, *Animals* 16(9):1361, doi [10.3390/ani16091361](https://doi.org/10.3390/ani16091361) | Chuckwagon (no llano). GNSS-IMU de 25 Hz: la asimetría de impulso al trote sube tras la carrera (31,7 → 38,0 %). Los autores dicen que 25 Hz limita la sensibilidad | [E]; [I-raza] por disciplina |
| Li et al., *EVJ*, doi 10.1002/evj.70360 | Solo se confirmó el título (fatiga con sensores y ML en caballos de deporte). Contenido [NV]. No confundir con Darbandi 2023 (*PLoS One*) | [NV] |

**Lectura para el motor [I]:**
- **Tendencia antes que valor aislado.** Hall 2026 apoya la regla de diseño ya vigente: una alerta de un solo día
  tiene VPP bajo. La persistencia en ≥ 3 sesiones es lo que concentra el riesgo. Se propone NV1: las alertas de
  locomoción (A7/A8) suben de severidad solo con persistencia en 3 sesiones comparables [I, sin implementar].
- **Regreso tras layup (P7).** Espil 2026 confirma en otra localización de fractura la señal de Choi 2026: el riesgo
  sube con menos trabajo desde el regreso. P7 se mantiene en diseño, ahora con dos fuentes [E-r].
- **Modelo B.** Anwar 2026 ya está publicado en RSOS. La KB ya tenía estas cifras del preprint. Falta comparar la
  tabla 7 publicada y el código de Zenodo, así que siguen pendientes. **D* es una carga acumulada modelada, nunca una
  predicción de lesión.**
- **A11 (ECG).** La OR por latido ectópico de van Erck-Westergren 2026 refuerza que A11 informe el recuento de
  ectópicos por fase, sin umbral nuevo hasta leer el texto completo.

## Cambios en la base (KB 1.17.0)

- **Fuentes nuevas (9):** Kędzierski 2007, Paksoy 2025, Thomassian 2005, Prince/KER, Dąbrowska 2026 (BMC, diseño),
  Espil 2026, Hall 2026, Legg 2026 y Eamon 2026.
- **Parámetros nuevos (2):**
  - `lactato_post_galope_arabe_llano`: solo contexto, sin umbral.
  - `velocidad_carrera_arabe_llano_1400m`: plausibilidad, [I] calculada de tiempos [E].
- **Pendiente nuevo:** NV1 (persistencia en 3 sesiones para subir severidad de A7/A8).
- **Cola:** tabla S4 de Dąbrowska 2026 y PMC12866905 desde un navegador; RSOS publicada de Anwar; texto completo de
  Hall 2026 y Espil 2026; Li 2026; búsqueda en francés de PA.

## Resumen

- **Árabes de llano:** primer lactato publicado tras galope de entrenamiento: ≈ 2–22 mmol/L tras 1.200 m a 8–13 m/s
  (Kędzierski 2007 [E]). Primer orden de magnitud de velocidad de carrera: ≈ 13–14 m/s de media en 1.400 m (Paksoy
  2025 [E], cálculo [I]). V200 y V4 en cinta de árabes no de carreras: 9,5 y 8,0–8,3 m/s [E]. La tabla S4 de
  Dąbrowska 2026 sigue [NV].
- **Novedades 2026:** Anwar ya publicado en RSOS (sin leer la versión final). Espil 2026 y Hall 2026 [E-r] apoyan dos
  diseños: riesgo al volver del layup y alertas por persistencia de varias sesiones.
- **Motor:** sin cambios de lógica, reglas ni umbrales; solo versiones (KB 1.16.0 → 1.17.0, motor dev18 → dev19). Todo
  probado solo en local y CI, **no verificado con caballos reales**. La fatiga ósea no es una predicción de lesiones.
