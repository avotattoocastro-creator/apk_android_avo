# Estudio horario 20/11/2026 08:09 UTC: modelo óseo B (paso de integración, tablas 4 y 7) y velocidad final relativa / A8

**Inicio:** 08:09 UTC (09:09 en Madrid) · **Autor:** Claude (tarea programada, sin supervisión) · **Base:** KB-1 1.9.0 →
**1.10.0** · **Motor:** 2.0.0-dev11 → **2.0.0-dev12** (solo versiones; sin cambios de lógica).

**Etiquetas:** [E] texto completo leído · [E-r] solo resumen o agregador · [I] inferencia o diseño propio · [I-raza] otra
raza, solo como método · [NV] sin verificar. Las cifras están parafraseadas; no se reproducen tablas completas.

## Decisiones tomadas sin supervisión
1. **Rama de partida:** no había PR abiertos de `claude/kb-*` (el #92 de la noche ya está fusionado), así que la rama
   `claude/kb-estudio-2026-11-20-0809` sale de `develop/avo-performance-horse` (131734c8).
2. **Temas:** (a) modelo óseo B: paso de integración, código de Zenodo y comparación preprint/versión publicada de Anwar
   2026 (bloquea código); (b) velocidad final relativa propia de AVO y pendiente de A8 (último parcial de 200 m), con
   búsqueda de datos de árabes de llano. Ninguno de los dos está en un PR abierto.
3. **Dos subagentes en paralelo** con WebSearch/WebFetch (≈ 7–8 min cada uno).
4. **Motor:** no se implementa el v200 de A8. Requiere calcular un nuevo campo en `racing.cpp`/`training.cpp` y
   sacarlo en el JSON (cambian las salidas de las fixtures y lo leen las apps); no cabe con pruebas en esta hora. Solo se
   suben `KNOWLEDGE_VERSION` y `ENGINE_VERSION`.
5. **Comprobación de A8:** el subagente avisó de que «el HR 1,18 es por cada DESCENSO de 0,1 m/s». A8 ya está
   implementada como **caída** frente a la línea base propia (`kb_drift_down`), así que el sentido es correcto; no se
   cambia nada, solo se aclara la nota.
6. **Bloqueos:** WebFetch pidió permiso de procedencia (PROVENANCE_REQUIRED) para Zenodo (19173866 y API), PMC13641913,
   PMC12483640 y PMC7710124; sin nadie que lo apruebe, caducó. No se intentó esquivarlo por otras vías. GitHub: no hay
   repositorio público de los autores.

## 1. Modelo óseo B (Pan 2025 / Anwar 2026)

### 1.1 Paso de integración y método numérico: siguen [NV]
- **Anwar 2026, preprint arXiv 2603.22680v1** (Australia, PSI, CC BY; https://arxiv.org/html/2603.22680v1 y PDF) [E]:
  el texto no menciona paso temporal, solver, Euler, Python ni MATLAB; las ecuaciones remiten al apéndice A de Pan 2025.
  La ecuación de fracción ósea es df_BM/dt = (A_OBL − A_OCL)·α·S_v [E]. El código se declara en
  doi:10.5281/zenodo.19173866 [E]; su licencia es [NV].
- **Pan 2025, preprint bioRxiv** (10.1101/2025.04.06.646486, PDF) [E]: las simulaciones parten de **f_BM = 0,61 y
  D* = 0** (el análisis de sensibilidad, de f_BM = 0,7) [E]; las tasas van en mm/día y el tiempo en días [E]. No se
  menciona el solver y la información suplementaria está vacía [E].
- **Inferencia:** que las tasas sean diarias y la carga sea por día (ciclos·día⁻¹) apunta a una integración diaria
  (Euler explícito con dt = 1 d) [I], pero **no está publicado**. Se mantiene el bloqueo: sin el código de Zenodo no se
  fija dt.

### 1.2 Carga y calendario (Anwar 2026, preprint) [E]
- Carga diaria v_n = distancia × frecuencia de zancada / velocidad, en ciclos por día; el daño se suma por velocidad y la
  tensión se toma de la velocidad más rápida del día.
- Condición inicial descrita como «caballo sin entrenar y sin daño».
- Preparación = 52 semanas / nº de descansos al año (2 descansos → 26 semanas); descanso de 4 a 8 semanas.
- Constantes de la tabla 9: coinciden con las ya registradas en KB 1.8.0 (α 0,19; a 11,42 mm⁻¹; b −0,02; σ0 139,0 MPa;
  σ1 14,1 MPa; F_s 5; E0 2500 MPa…). **Ningún cambio.**

### 1.3 Tablas 4 y 7 del preprint (para validar la implementación cuando llegue el código) [E]
- **Tabla 4** (4.ª preparación; rápido y ligero / moderado / alto volumen): D* máximo ≈ 0,81 / 0,91 / 1,02; f_BM máximo
  ≈ 0,93 en los tres; canter a 7,5 m/s ≈ 126 / 138 / 146 km y galope de 11,8–16 m/s ≈ 8,9 / 16,6 / 26,0 km. Reproducirla
  exige las distancias diarias de la tabla 1 y el dt.
- **Tabla 7** (2.º año; 1 / 2 / 3 descansos al año): D* máximo ≈ 1,54 / 0,91 / 0,80.
- **Incoherencia interna nueva y concreta:** la Discusión da un D* máximo de 0,852 con 2 descansos, mientras la tabla 7 y
  la sección 3.4 dan 0,911 [E]. Hasta leer la versión publicada (RSOS 13:260818, PMC13641913), **se usa la tabla** y no
  la Discusión [I].

### 1.4 Qué falta
Código de Zenodo 19173866 (y 16557014 de Pan) y PMC13641913 desde un navegador con permisos. Sin cambios en el motor.

## 2. Velocidad final relativa y A8

### 2.1 Wong et al. 2023, EVJ 55(2):194–204 — reconfirmado [E]
Manuscrito aceptado en minerva-access (CC BY-NC), Tasmania, PSI, solo carreras (StrideMASTER, Tasracing; lesiones de
ARID). Caso-control de 146 casos y 438 controles (5.660 salidas). La velocidad del **último parcial de 200 m**, en valor
**absoluto**, se modela como trayectoria a lo largo de las salidas (modelo conjunto longitudinal + supervivencia):
HR 1,18 (1,09–1,28) por cada **descenso** de 0,1 m/s; zancada HR 1,11 (1,02–1,21) por cada 10 cm de descenso. No hay
umbral. Si el modelo ajusta por distancia o pista es [NV].
**Consecuencia:** A8 (caída frente a la línea base propia) tiene el sentido correcto; los 600 m en trabajo y 0,20 m/s
siguen siendo [I]. El pendiente de añadir el v200 se mantiene.

### 2.2 Finishing Speed % (definición) [E, fuente comercial]
- **Timeform** (Reino Unido, «An introduction to sectional timing, part 2»): FS % = v(parcial final) / v media de la
  carrera × 100. Lo que cuenta es la distancia al **par de la pista y la distancia**, no al 100 %. El par se obtiene de
  los parciales de las carreras rápidas de esa pista. Ejemplos de par: milla redonda de Ascot ≈ 101 %, Epsom ≈ 108 %,
  Beverley por debajo de 100 %. No hay umbrales numéricos.
- **At The Races** (Simon Rowlands): parcial final = últimos 2 f hasta la milla y 3 f en distancias mayores; grados de
  eficiencia A–F sin cortes publicados.
- **RaceiQ / Racing TV**: pares por pista (Epsom 6 f ≈ 103 %, 1m4f ≈ 112 %) y cinco bandas sin cortes numéricos.
- **Conclusión:** la velocidad final relativa es **descriptiva**; ninguna fuente publica un umbral ligado a lesión o
  fatiga [E]. Para AVO, el par debe salir de los datos propios por pista, distancia y superficie [I].

### 2.3 Estudios científicos de desaceleración final
- **Mercier & Aftalion 2020**, PLoS ONE (Francia, Chantilly PSF, GPS France Galop 10 Hz; PSI). PMC7710124 bloqueado; leído
  en arXiv 2006.10530 [E]: tres carreras (1300, 1900 y 2100 m), pico de velocidad a los 200–300 m, frenado final incluso
  en llano y gana el que menos desacelera; aporte anaeróbico 47 / 32 / 38 %. No cuantifica una velocidad final relativa.
- **Takahashi et al. 2021**, J Equine Vet Sci 101:103447 (Japón, JRA, 2400 m hierba; doi 10.1016/j.jevs.2021.103447)
  [E-r, agregador]: velocidad 17,3 → 16,0 m/s, frecuencia 2,34 → 2,21 zancadas/s y zancada 7,42 → 7,25 m entre la 1.ª y
  la 2.ª pasada cerca de la meta. Sin relación con lesión.
- **Wong et al. 2023, Front Vet Sci** 10:1260554: no usa parciales de carrera [E] (ya en la KB).

### 2.4 Árabes de carreras en llano
- **Nielsen et al. 2006**, EVJ Suppl 36:128–132 (EE. UU., árabes, 1006 m; doi 10.1111/j.2042-3306.2006.tb05528.x)
  [E-r]: corren más rápido en el tramo medio y **desaceleran en el tramo final**; la magnitud es [NV].
- **Önder et al. 2022**, Animals 12:2630 (Turquía, Jockey Club; ya en la KB): solo velocidad media de carrera, sin
  parciales [E].
- **France Galop, PDF de tracking** de la Coupe d'Europe des Chevaux Arabes (Longchamp, 2000 m, 14/05/2023;
  20230514LON03) [E, oficial]: ganador en 2:16,83, último 200 m en 12,91 s; el tracking no está sincronizado con el
  cronometraje oficial. **Cálculo propio** [I]: v final ≈ 15,49 m/s frente a v media ≈ 14,62 m/s → FS ≈ 106 %. Es un
  solo caballo y una carrera: no es un par.
- Reino Unido, Golfo y Polonia: no se encontraron estudios de parciales en árabes [NV].

## 3. Cambios en la KB 1.10.0
- Fuentes nuevas: `MERCIER_AFTALION_2020`, `TAKAHASHI_2021_JEVS`, `NIELSEN_2006_ARABES`, `ATR_SECTIONALS`,
  `RACEIQ_PAR`, `FG_TRACKING_ARABES_2023`; `TIMEFORM_FS_PCT`, `ANWAR_2026_ARXIV_V1` y `PAN_2025_PREPRINT` completadas con
  acceso, país, idioma, raza y fecha.
- Notas: A8 (sentido confirmado, variable absoluta y longitudinal), modelo B (f_BM 0,61 y D* 0, dt [NV], 0,911 frente a
  0,852), pendiente de la velocidad final relativa (par propio, sin umbral publicado).
- Cola: Zenodo y PMC13641913 desde navegador; Nielsen 2006 completo; árabes en los PDF de France Galop para un par propio.
- **Sin cambios de lógica, reglas, parámetros ni umbrales.**

## Resumen
- **Modelo óseo B:** el paso de integración sigue sin publicarse en los preprints leídos en texto completo (arXiv de
  Anwar y bioRxiv de Pan); todo apunta a pasos diarios, pero es [I]. Se confirman las condiciones iniciales (f_BM 0,61,
  D* 0) y las constantes, se anotan las tablas 4 y 7 como objetivo de validación y se documenta una incoherencia del
  preprint (D* máximo 0,911 en la tabla frente a 0,852 en la Discusión). Zenodo y PMC siguen bloqueados en la sesión.
- **Velocidad final relativa / A8:** Wong 2023 usa la velocidad absoluta del último 200 m de carrera como tendencia del
  propio caballo (riesgo al bajar); A8 ya tiene el sentido correcto. El «Finishing Speed %» de Timeform es v final /
  v media frente a un par por pista, sin umbrales; ninguna fuente científica da umbral de riesgo. En árabes solo hay
  desaceleración final descrita (Nielsen 2006, resumen) y los PDF de France Galop como datos para construir un par propio.
- **Motor:** 2.0.0-dev12 solo con versiones. Probado en local y en CI; nada verificado con caballos reales. La fatiga
  ósea nunca es una predicción de lesiones.
