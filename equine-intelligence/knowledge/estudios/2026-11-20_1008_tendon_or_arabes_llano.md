# Estudio horario 2026-11-20 10:08 UTC — OR del TFDS (índice tendinoso) y árabes de carreras en llano

KB 1.11.0 → **1.12.0** · motor 2.0.0-dev13 → **2.0.0-dev14** · rama `claude/kb-estudio-2026-11-20-1008`,
encadenada sobre `claude/kb-estudio-2026-11-20-0909` (PR #96, abierto).

## Decisiones (sesión sin supervisión)

1. **Fecha comprobada:** 20/11/2026 en Madrid (10:08 UTC). Se ejecuta.
2. **Encadenamiento:** el único PR `claude/kb-*` abierto es el #96 (09:09). La rama sale de él y no se repiten sus temas
   (V200/A9 y umbrales de prematuro del ECG/A11), ni los del 08:09 (dt del modelo B, velocidad final relativa).
3. **Temas elegidos** (bloquean código y no se habían cerrado): (1) **índice tendinoso**, con las OR de Takahashi 2004
   y Lam 2007 que siguen en la cola; (2) **árabes de carreras en llano**: Nielsen 2006, Yildirim 2025 y publicaciones
   2024–2026.
4. **Dos subagentes en paralelo** con WebSearch/WebFetch y un límite de unos 18 min. No se esquivó ningún bloqueo.
5. **Motor:** ningún pendiente se cierra en texto completo. Solo se suben las versiones; no cambia la lógica, las
   reglas, los parámetros ni los umbrales.
6. **Las lecturas de los subagentes se clasifican con prudencia.** Las cifras de Ikeda 2019 que coinciden con las ya
   transcritas el 19/11 mantienen su etiqueta [E-r], porque esta sesión no puede asegurar la vía de lectura (la noche
   del 20/11 ya se descartó una copia no legal). Esa relectura sigue en la cola.

## Accesos denegados en la sesión (no esquivados)

| Recurso | Resultado |
|---|---|
| avmajournals.avma.org, doi.org, api.unpaywall.org, www.ebi.ac.uk (Europe PMC) | HTTP 403 del proxy |
| PubMed | páginas vacías o límite de peticiones |
| PMC | reCAPTCHA |
| Wiley (onlinelibrary, pdfdirect) y ScienceDirect | error de cliente, también para Yildirim 2025, que OpenAlex marca como de acceso abierto |
| Enlighten (Glasgow) para Lam 2007 *AJVR* | solo la ficha, sin PDF |

## 1. Índice tendinoso: OR del TFDS en PSI

| Fuente | País, n | Lo que se pudo leer | Etiqueta |
|---|---|---|---|
| Takahashi, Kasashima & Ueno 2004, *JAVMA* 225:90–93, doi 10.2460/javma.2004.225.90 (PMID 15239479) | Japón (JRA), lesiones de 2002; 515 casos y 951 controles emparejados por edad y mes de la última carrera | Solo el sentido del efecto: el riesgo sube con la **distancia media de carrera** y con el **peso corporal medio en carrera**; los machos y las hembras con experiencia de *steeplechase* tienen más riesgo que las hembras sin ella. **No hay ninguna OR legible** | [E-r]; OR [NV] |
| Lam, Parkin, Riggs & Morgan 2007, *EVJ* 39:143–148, doi 10.2746/042516407x159132 | Hong Kong, 1992–2004 | Descriptivo, sin OR: los retiros por tendón tienen una incidencia acumulada anual del **3,2 %** (14 % de los retiros), que sube del 2,3 % al 4,2 % en el periodo | [E-r] |
| Lam et al. 2007, *AJVR* 68:1188–1197, doi 10.2460/ajvr.68.11.1188 | Hong Kong, retiros de 1997 a 2004; 175 casos con 3 controles por caso; logística condicional con dos modelos de 8 variables | Este es el estudio que publica las OR, pero solo se leyó el sentido de los factores. Los casos eran **más viejos al importarse**, acumularon **más distancia de carrera poco después de importarse**, tenían **más exámenes veterinarios o ecográficos previos**, **menos salidas**, **más tiempo en entrenamiento** y **menor intensidad** de ejercicio en los 180 días previos | [E-r]; OR [NV] |
| Ikeda et al. 2019, *J Equine Sci* 30:93, PMC6920055 | Japón (Oi, arena); 292 casos y 584 controles | Coincide con la tabla del extra 2 (19/11). Dato nuevo: **macho frente a hembra 1,35 (1,00–1,81)**, univariable. Todas las OR siguen siendo univariables | [E-r] (vía de lectura sin confirmar) |
| Perkins, Reid & Morris 2005, *NZ Vet J* 53:184, doi 10.1080/00480169.2005.36503 | Nueva Zelanda | Las IRR por edad (6,76 a 4 años y 15,26 a ≥ 5 frente a 2 años) coinciden con lo que ya estaba en la KB desde la tesis de Massey | [E] (KB 19/11) |
| Choi & Parkin 2025, *EVJ* 58:31, doi 10.1111/evj.14493 | Corea (Seúl, arena) | El modelo multivariable coincide con la KB: entrenamiento frente a carrera 11,389; ≥ 41 días de canter en 180 d 1,837; ≤ 2 días de galope en 60 d 1,842; cociente ≤ 1,6 2,190 | [E] (KB 20/11) |

**Lectura [I].** Lam 2007 *AJVR* apunta en el mismo sentido que Choi & Parkin e Ikeda: **menos intensidad reciente**,
más tiempo en entrenamiento y menos salidas acompañan a la lesión. Esto refuerza A6, A6B y A6C, que ya están en el
motor. Takahashi añade dos factores que la app no recoge de forma estructurada: la distancia media de carrera y el
peso en carrera. Mientras no se lean las OR, **no se añade ningún peso numérico** al índice tendinoso, que sigue
siendo heurístico por bandas cualitativas. Las fuentes son todas de PSI; aplicarlas a árabes es [I-raza].

Dos posibles entradas cualitativas para el índice, propuestas como diseño [I] y sin implementar:

- **«lesión o exploración tendinosa previa»**, apoyada en el sentido del efecto en Lam 2007 *AJVR*;
- **«peso del caballo en carrera alto para su cuadra»**, apoyada en Takahashi 2004 e Ikeda 2019 (≥ 470 kg en PSI de
  arena, un corte que no vale para árabes).

## 2. Árabes de carreras en llano

| Fuente | País, n | Cifras | Etiqueta |
|---|---|---|---|
| Nielsen, Turner, Ventura, Woodward & O'Connor 2006, *EVJ Suppl* 36:128–132, doi 10.1111/j.2042-3306.2006.tb05528.x | EE. UU., vídeo de un hipódromo; ganador cronometrado por tramos (5 cronometradores, se descartan el tiempo más rápido y el más lento) | En 1.006 m, árabes y PSI alcanzan la velocidad máxima en el **tramo central** y la pierden en el **último**. El resumen no da cuánto se frenan ni la n | [E-r]; magnitud [NV] |
| Yildirim, Karaarslan & Erkan 2025, *EVJ*, doi 10.1111/evj.14457 (PMID 39777406) | Turquía (Şirinyer, Esmirna), 2018–2023; 553 lesiones musculoesqueléticas de PSI y árabes | 45,3 % fracturas, 40,3 % tendinosas y 9,8 % fisuras. El reparto por pista difiere entre carrera y entrenamiento (p < 0,0001). En carrera, la lesión estuvo en la **extremidad anterior en el 92,7 % de los árabes** (91,3 % en PSI). Picos de edad en árabes a los **3 y 4 años**, y fin de la carrera deportiva en el **46,4 %** de los árabes (66,3 % en PSI). El resumen no da OR por superficie | [E-r] (resumen secundario de Mad Barn); OR [NV] |
| Paksoy, Kırmızıgül, Ayvazoğlu & Yalçın 2025, *Acta Vet Brno* 94:97–103, doi 10.2754/avb202594020097 | Turquía (Şanlıurfa); 8 sementales árabes de 3,87 ± 1,12 años y 7 PSI | En 1.400 m (superficie no indicada) los árabes tardaron entre 1:38 y 1:48, es decir **≈ 13,0–14,3 m/s** [I, cálculo]. La cTnI pasó de 0,008 ± 0,002 a **0,165 ± 0,054 ng/ml** a los 30 min de la carrera. Pulso en reposo 42 ± 2 lpm. Sin FC de carrera ni lactato | [E] |
| Śniegucka, Soroko-Dubrovina, Zielińska & Dudek 2026, *Vet Sci* 13(7):695, doi 10.3390/vetsci13070695 | Polonia (Partynice, Breslavia), 2023–2024; 36 árabes de 3 años | **15 de 36 (≈ 42 %, cálculo)** desarrollaron enfermedad dorsal del metacarpo. Programa de **6 días por semana**: 1.000 m al trote y después **200–500 m de trabajo de velocidad**. La terapia láser no mejoró el resultado | [E] |
| *Antioxidants* 2024, 13(8):905, doi 10.3390/antiox13080905 (autores sin anotar) | Polonia (Służewiec); 14 árabes de 3 años | **2 sesiones intensas por semana**: unos 15 min de calentamiento, galope rápido de **800 m a 45–50 km/h (12,5–13,9 m/s)** y 40 min de caminador | [E] |
| *Genes* 2025, 16(4):431, doi 10.3390/genes16040431 (autores sin anotar) | Polonia (Polish Arabian Stud Book); 16 árabes de 2,5 años al empezar | El galope pasa de **200 a 1.200 m** en el séptimo mes, alargándose cada semana. El canter sube hasta **5.000 m** en un mes y luego baja a 2.500–3.000 m. La prueba antes de la temporada es un galope de ≤ 2.000 m, **200–400 m más largo** que la carrera prevista. Media de 6 salidas por caballo | [E] |
| Dąbrowska, …, Witkowska-Piłaszewicz 2026, *BMC Vet Res*, doi 10.1186/s12917-026-06055-w | Polonia (SGGW); 18 árabes en tres momentos: primer galope intenso, galope tras 6–10 semanas y carrera oficial | El lactato se aclaró menos tras la carrera que tras los dos galopes (p = 0,034). Los valores absolutos están en la tabla S4, sin leer | [E] (parcial); valores [NV] |
| Schurink et al. 2009, *Livest Sci* 125:97–100, doi 10.1016/j.livsci.2009.03.004 | Países Bajos (Duindigt); 380 actuaciones de 88 árabes en 52 carreras | La velocidad sube con la edad, tiende a bajar a los 7–9 años, cae al alargar la distancia y es mayor con 1–2 rivales a menos de un cuerpo en la llegada. Sin valores en el resumen | [E-r] |

**Sin datos publicados hallados para árabes de llano** (2024–2026): longitud o frecuencia de zancada, FC de carrera,
V200 y OR de lesión por superficie. No se buscó en el Golfo, Irán ni el Magreb en polaco y francés por el límite de
llamadas.

**Lectura [I] para el motor y el planificador.**

- La **velocidad de trabajo rápido en árabes de 3 años en Polonia** (12,5–13,9 m/s en 800 m) está **por debajo** del
  corte de trabajo rápido de PSI (≥ 13,3 m/s de Morrice-West). Esto respalda los cortes **relativos por caballo**
  que ya usa el motor frente a cualquier corte absoluto heredado de PSI.
- Lo publicado son **2 sesiones intensas por semana** (Służewiec) y **6 días de trabajo** con 200–500 m rápidos
  (Partynice). Encaja con P1 y P2 del planificador (estudio extra 3): pasa a ser práctica [E] en árabes polacos, no
  una regla de riesgo.
- La **incidencia de enfermedad dorsal del metacarpo** en árabes de 3 años (≈ 42 % en una cuadra) indica que la
  fatiga ósea es relevante también en árabes jóvenes. La fatiga ósea **nunca es una predicción de lesiones**.

## 3. Cambios en la KB (1.12.0)

- **Fuentes nuevas:** PAKSOY_2025, SNIEGUCKA_2026, ANTIOX_2024_SLUZEWIEC, GENES_2025_PASB, DABROWSKA_2026,
  SCHURINK_2009, NIELSEN_2006, TAKAHASHI_2004, LAM_2007_EVJ y LAM_2007_AJVR.
- **Fuentes completadas:** YILDIRIM_2025 (DOI, acceso y cifras) e IKEDA_2019 (macho frente a hembra; acceso).
- **Parámetros nuevos, solo informativos:** el trabajo rápido de árabes de 3 años en Polonia y la frecuencia
  semanal de trabajos intensos.
- **Sin reglas nuevas.**
- **Pendiente del índice tendinoso:** se añaden las dos entradas cualitativas propuestas.
- **Cola:** se añaden el PDF de Yildirim 2025, las OR de Takahashi y de Lam *AJVR* desde AVMA (dominio bloqueado),
  Nielsen 2006 completo y la tabla S4 de Dąbrowska 2026.

## Resumen

- **Índice tendinoso:** las OR de Takahashi 2004 (*JAVMA*) y Lam 2007 (*AJVR*) siguen sin leerse: AVMA, doi.org,
  Unpaywall y Europe PMC dieron 403 en la sesión. Solo se conoce el sentido de los factores: más distancia y peso en
  carrera (Takahashi); más edad al importarse y menos intensidad reciente (Lam). Eso confirma la dirección de
  A6/A6B/A6C, y no se añade ningún peso numérico.
- **Árabes de llano:** cuatro fuentes nuevas en texto completo, de Polonia y Turquía, describen la práctica:
  trabajos rápidos a 12,5–13,9 m/s, 2 sesiones intensas por semana, ≈ 42 % de enfermedad dorsal del metacarpo a los
  3 años y la cTnI tras 1.400 m. Siguen sin publicarse la zancada, la FC de carrera, la V200 y las OR por superficie.
- **Motor:** 2.0.0-dev14 solo con versiones, sin cambios de lógica, reglas, parámetros ni umbrales. Probado en local
  y en CI; nada verificado con caballos reales.
