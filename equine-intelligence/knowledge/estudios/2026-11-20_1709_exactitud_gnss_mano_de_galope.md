# Estudio horario 20/11/2026 17:09 UTC: exactitud del GNSS/IMU a galope y mano de galope en curva

**Base:** KB-1 1.18.0 → **1.19.0** · motor 2.0.0-dev20 → **2.0.0-dev21** · rama `claude/kb-estudio-2026-11-20-1709`
(sale de `claude/kb-estudio-2026-11-20-1610`, PR #107, el `claude/kb-*` abierto más reciente).

## Decisiones tomadas sin supervisión

1. **Encadenamiento:** había 6 PR `claude/kb-*` abiertos (#99 a #107). La rama sale del más reciente (#107, 16:10).
2. **Temas.** Ningún estudio anterior trataba dos temas que el motor ya usa sin respaldo explícito. Por eso se eligieron
   en lugar de volver a temas bloqueados (Verheyen, Takahashi y Lam, Zenodo), que ya se intentaron varias veces hoy sin
   acceso nuevo:
   - **T1:** exactitud de la velocidad, la distancia y la zancada medidas con GNSS e IMU a galope. Afecta a V200, A8
     (último parcial de 200 m), la velocidad final relativa y la línea base de la playa.
   - **T2:** mano de galope, cambios de mano y curvas: si son detectables con la cincha y si tienen relación con lesiones.
3. **Motor:** solo se cambian las versiones. La evidencia de T1 no da cifras de RTK a galope y la de T2 no da ninguna
   exactitud de detección publicada, así que no hay nada cerrado en texto completo para programar. Se dejan dos
   pendientes de diseño [I]: GN1 (calidad de la velocidad GNSS) y ML1 (mano de galope experimental).
4. **Agregadores.** Varias cifras se leyeron solo en fichas de madbarn.com, que son resúmenes secundarios. Se etiquetan
   [E-r] y no se usan en el código. PMC y PubMed devolvieron reCAPTCHA, `katalog.lib.cas.cz` usa el anti-bot Anubis y la
   API de Europe PMC no respondió. No se intentó esquivar ningún bloqueo. Tampoco se usó Scribd, que aloja copias no
   autorizadas.
5. Investigación hecha con 2 subagentes en paralelo (unos 15 min cada uno) y revisada en el hilo principal.

## T1. Exactitud de la velocidad, la distancia y la zancada con GNSS e IMU a galope

| Dato | Valor | Condiciones | Fuente | Etiqueta |
|---|---|---|---|---|
| Sistema de seguimiento en carrera (TurfTrax) | Velocidad dentro de ±0,15 m/s; posición ±11 cm longitudinal y ±64 cm lateral | PSI en carrera frente a GPS topográfico; n [NV] | Spence, Tan & Wilson 2008, *EVJ* 40:680, doi [10.2746/042516408X330338](https://doi.org/10.2746/042516408X330338) (Reino Unido) | [E-r] |
| Especificación de France Galop | Error de posición ≤ 25 cm durante > 98 % del tiempo; todos los sistemas candidatos eran GNSS RTK. **No publica la exactitud lograda** | Prueba con coches y después con carreras simuladas | Blache et al. 2019, *Ann Telecommun* 74:287, doi [10.1007/s12243-018-0685-9](https://doi.org/10.1007/s12243-018-0685-9) (Francia) | [E-r] |
| Frecuencia de zancada sacada de las oscilaciones de la velocidad GPS a 10 Hz | Sesgo de unos 0,003 Hz frente a la IMU y precisión por tramo de 100 m de unos 0,009 Hz | 12 PSI a ≈ 16,5 m/s; IMU de referencia a 120 Hz | Pfau et al. 2022, *J Biomech* 145:111364 (ya en la KB como `PFAU_2022`) | [E-r] (ficha de agregador) |
| GPS a 10 Hz en curvas cerradas | **Infraestima la velocidad** (solo cualitativo). La frecuencia de zancada se calcula como 1/duración, desde la IMU | 40 PSI de 2–3 años; IMU a 300 Hz | Parkes, Weller, Pfau & Witte 2019, *Animals* 9:466, doi [10.3390/ani9070466](https://doi.org/10.3390/ani9070466) (Reino Unido) | [E] |
| GPS a 1 Hz con filtro | Velocidad inexacta en aceleraciones y frenadas rápidas, por lo que se descartaron esas zancadas | 9 PSI en Polytrack, 5.642 zancadas; contactos en el casco validados con placa de fuerzas (2,3 ms en el apoyo y 3,5 ms en el despegue) | Witte, Hirst & Wilson 2006 (ya en la KB como `WITTE_2006`) | [E] |
| GPS frente a cronómetro | El GPS da menos velocidad en cada intervalo y la diferencia crece con la velocidad (sin cifras en el resumen) | 19 caballos en arena, raza [NV] | Lindner & Brand 2019, *J Equine Vet Sci* 84:102871, doi [10.1016/j.jevs.2019.102871](https://doi.org/10.1016/j.jevs.2019.102871) (Alemania) | [E-r] (agregador); [I-raza] |
| Velocidad solo con una IMU (pomo, SVM) | RMSE de 0,43 m/s (≈ 5 % a 5,8 m/s) | 58 caballos de salto, galope de trabajo | Schmutz et al. 2020, *Sensors* 20:518, doi [10.3390/s20020518](https://doi.org/10.3390/s20020518) (Francia) | [E]; [I-raza] (sirve como orden de magnitud del método) |
| GNSS comercial ≈ 20 Hz + IMU frente a captura óptica | Velocidad por zancada con sesgo de −0,81 m/s (−15 %) y longitud de −59 cm | 11 warmblood en círculo, trote y galope | Guyard et al. 2023, *Sensors* 23:4196, doi [10.3390/s23094196](https://doi.org/10.3390/s23094196) (Suiza) | [E]; [I-raza] (sirve para ver el efecto del círculo) |
| Distancia con GPS a 1 y 5 Hz | Error de estimación del 1,3–3,1 % en recta y del 1,8–6,9 % con giros; a 1 Hz, hasta −11 % en giros de 180° | Humanos, ≤ 8 m/s | Portas et al. 2010, *IJSPP* 5:448 (Reino Unido) | [E]; [I-raza] (otra especie: ilustra el error en curva) |
| GPS a 10 Hz frente a radar | Sobrestima la velocidad máxima en 0,11 m/s (≈ 1 %); CCI 0,99 | Velocistas humanos, 60 m | Thome et al. 2023, *J Strength Cond Res* 37:2438, doi [10.1519/JSC.0000000000004567](https://doi.org/10.1519/JSC.0000000000004567) (Australia) | [E-r]; [I-raza] (otra especie) |
| Rango de plausibilidad en carrera | 12,6–21 m/s, longitud de zancada de 5,3–9,2 m y duración de 0,37–0,49 s. **StrideMASTER sin validación independiente publicada** | 2.678 PSI, GPS + GLONASS a 5 Hz | Morrice-West et al. 2020, *EVJ* doi 10.1111/evj.13370 (ya en la KB como `MORRICE_WEST_2020_VARIACION`) | [E] |
| Equimetre | Se usa sin validación publicada de la zancada | 421 PSI | Schrurs et al. 2022, *Animals* 12:3269 | [E] |

**Fuentes no leídas:** Witte & Wilson 2004 (*J Biomech* 37:1891) y 2005 (*J Biomech* 38:1717). Las fichas del RVC no
tienen ni resumen ni PDF. No se encontraron Hebenbrock 2006 ni ninguna validación independiente de Equimetre o Equinity
a galope [NV].

**Lectura para el motor [I]:**
- **No hay ninguna cifra publicada de RTK a galope.** La mejor referencia publicada es ±0,15 m/s (TurfTrax), y la
  especificación de France Galop es de 25 cm de posición. El objetivo propuesto para AVO es un error ≤ 0,15 m/s (≤ 1 %) a
  15–18 m/s en recta, **por demostrar en campo** con fotocélulas cada 200 m. La ficha del prototipo de la espalda no
  cambia: nada está verificado en hardware.
- **La curva y la aceleración degradan la velocidad.** Esto lo indican fuentes de caballos [E] y de humanos [I-raza]. Se
  propone GN1: marcar con menor confianza los tramos con radio < 200 m o con |a longitudinal| alta, no usarlos como
  mesetas de V200 y comparar los parciales de 200 m (A8) solo entre tramos de la misma geometría.
- **Longitud de zancada = velocidad GNSS × duración (IMU).** Con un 1 % de error en la velocidad y 2–3 ms en la
  duración, el error es de ≈ ±1–1,5 % (unos 7–10 cm sobre 7 m) [I]. Es del mismo orden que la unidad de 10 cm de Wong
  2023, así que **solo debe compararse promediada por tramos de ≥ 100–200 m**, nunca zancada a zancada.
- **Frecuencia de zancada.** La IMU es la fuente principal. La oscilación de la velocidad GNSS a 10 Hz sirve como
  comprobación cruzada entre la espalda y la cincha (Pfau 2022 [E-r]).
- La velocidad solo con la IMU (RMSE de 0,25–0,43 m/s en otras razas) sirve como relleno durante cortes de pocos
  segundos, nunca como dato de V200.

## T2. Mano de galope, cambios de mano y curvas

| Dato | Valor | Condiciones | Fuente | Etiqueta |
|---|---|---|---|---|
| Mano incorrecta en curva | **18,6 %** de las zancadas (359 de 1.931; 164 en recta y 195 en curva). La mano se identificó por la secuencia de apoyos de acelerómetros en los cascos | 7 PSI en pista antihoraria, 6–13,7 m/s, radios de 20 a > 120 m (> 200 m cuenta como recta); se pidió a los jinetes no cambiar de mano | Parkes, Pfau, Weller & Witte 2020, *PLoS One* 15:e0244105, doi [10.1371/journal.pone.0244105](https://doi.org/10.1371/journal.pone.0244105) (Reino Unido) | [E] |
| Fracción de apoyo en curva | Con la mano correcta, el miembro interior (el que lidera) apoya una fracción mayor de la zancada. Con la mano incorrecta no hay diferencia entre interior y exterior. Baja un 0,61 % por cada 1 m/s² de aceleración centrípeta | Igual que la fila anterior | Parkes 2020 | [E] |
| Fracturas por mano y sentido de la pista | Mano izquierda 0,930 frente a derecha 0,819 por 1.000 salidas (**RR 1,14**). En las dos curvas más cerradas, RR de la mano derecha 1,18 y 1,16 | EE. UU. y Canadá, todas las pistas antihorarias; 2.356.427 salidas, 2009–2014. Los autores avisan de inconsistencias en su tabla 4 | Peterson et al. 2021, *Sustainability* 13:539, doi [10.3390/su13020539](https://doi.org/10.3390/su13020539) (EE. UU.) | [E] |
| Fractura en la mano que lidera | 66 % (44 de 67) de las fracturas de mano ocurrieron en la mano que lideraba | Reino Unido, 59 hipódromos, 1999–2001; vídeo de 109 fracturas distales mortales | Parkin et al. 2006, *Prev Vet Med* 74:44, doi [10.1016/j.prevetmed.2006.01.006](https://doi.org/10.1016/j.prevetmed.2006.01.006) (Reino Unido) | [E-r] (agregador) |
| Fracturas en el cambio de mano | Más frecuentes en el momento del cambio de mano, en las curvas 3.ª y 4.ª y en la recta final (solo cualitativo) | JRA, revisión | Maeda, Hanada & Oikawa 2016, *J Equine Sci* 27:81, doi [10.1294/jes.27.81](https://doi.org/10.1294/jes.27.81) (Japón) | [E-r] |
| Mano en la salida | Derecha en el 91 % de los PSI y el 88 % de los **árabes** | EE. UU., 6.313 caballos. Tesis de máster no publicada | Williams 2002 (CSU San Marcos), conocida por un divulgador (ker.com) | [E-r²]; no usable en el código |
| Asimetría al trote según el sentido de entrenamiento | Más caballos con asimetría izquierda en la cabeza en Hong Kong (pista horaria) que en Singapur (antihoraria), con diferencias de 2–3,5 mm | 307 PSI, IMU en la nuca y la pelvis | Forbes et al. 2024, *Animals* 14:1086, doi [10.3390/ani14071086](https://doi.org/10.3390/ani14071086) (Hong Kong/Singapur) | [E] |
| Clasificación del galope izquierdo y derecho | 96,7 % de exactitud global en la clasificación de aires, con el galope de cada mano como clase. **Usa 7 IMU** (nuca, cruz, pelvis y cañas), no una sola en el tronco | Varias razas, 200 Hz | Serra Bragança et al. 2020, *Sci Rep*, doi [10.1038/s41598-020-73215-9](https://doi.org/10.1038/s41598-020-73215-9) (Países Bajos) | [E]; [I-raza] |
| Mano y riesgo en los modelos de zancada | Wong 2023 y StrideSAFE no tratan la mano como variable; Morrice-West 2022 lo reconoce como limitación | — | Ya en la KB | [E] |

**No hallado [NV]:** ninguna exactitud publicada de detección de la mano o de los cambios con un solo sensor en el
tronco o la cincha. Tampoco hay cambios de mano por carrera o por curva cuantificados en carreras de PSI o árabes, ni
ninguna OR/HR de lesión por cambio de mano. Faltó tiempo para buscar en Hill/Stover (California), la JRA y el HKJC.

**Lectura para el motor [I]:**
- La mano solo puede entrar como **métrica experimental** (ML1) hasta validarla con vídeo a ≥ 120 fps. La señal
  propuesta es la fase del balanceo lateral y de la guiñada respecto al pico vertical de cada zancada (la BNO085 da unas
  43 muestras por zancada a 100 Hz). Como dato a priori se usa el signo de la curvatura de la trayectoria RTK.
- Si se valida, se informaría del **% de zancadas en mano incorrecta en curva** y del % del tiempo en cada mano, separando
  la recta de la curva, junto con el sentido y el radio de la pista. Se presentaría como «carga posiblemente asimétrica»,
  **nunca como riesgo de lesión**: la asociación con fracturas es descriptiva, de nivel poblacional y con datos de
  pistas antihorarias de EE. UU.
- El sentido de la pista (horario o antihorario) debería guardarse como campo de la sesión o de la pista, y ser un
  criterio más de comparables (la asimetría del trote cambia según el sentido, Forbes 2024 [E]).
- No se toca ningún contrato binario: los datos de la IMU que ya llegan bastan para un análisis fuera de línea.

## Cambios en la KB (1.19.0)

- **Fuentes nuevas (14):** Spence 2008, Blache 2019, Parkes 2019, Lindner & Brand 2019, Schmutz 2020, Guyard 2023,
  Portas 2010, Thome 2023, Parkes 2020, Peterson 2021, Parkin 2006, Maeda 2016, Forbes 2024 y Serra Bragança 2020.
- **Parámetros de contexto (3):** exactitud de referencia de la velocidad en carrera (±0,15 m/s), rango de plausibilidad
  de la zancada en carrera (Morrice-West) y proporción de zancadas en mano incorrecta en curva (18,6 %).
- **Pendientes (2):** GN1 y ML1, ambos [I] y sin implementar.
- **Cola (3):** Witte & Wilson 2004/2005; detección de la mano con un solo sensor en el tronco y cambios de mano en
  carrera (JRA, HKJC y California); Parkin 2006 y Lindner & Brand 2019 en texto completo.
- **Sin cambios de lógica, reglas, umbrales ni cifras vigentes.**

## Resumen

- **T1:** no hay exactitud publicada de RTK a galope. La referencia es ±0,15 m/s en carrera (TurfTrax, [E-r]) y France
  Galop exige 25 cm de posición. Las curvas y las aceleraciones degradan la velocidad GNSS. La longitud de zancada
  arrastra un error de ≈ 1–1,5 % [I], así que solo se compara por tramos de ≥ 100–200 m. Se propone GN1.
- **T2:** el 18,6 % de las zancadas en curva va en mano incorrecta, y con ella el miembro interior pierde su mayor apoyo
  (Parkes 2020 [E]). En pistas antihorarias se fractura más la mano izquierda (RR 1,14, Peterson 2021 [E]). No hay
  ninguna exactitud publicada de detección con un solo sensor en el tronco, así que se propone ML1 como métrica
  experimental.
- **KB 1.19.0, motor 2.0.0-dev21, solo documentación.** Probado únicamente en local y en CI; **nada verificado con
  caballos reales**. Ni la fatiga ósea ni la mano de galope son una predicción de lesiones.
