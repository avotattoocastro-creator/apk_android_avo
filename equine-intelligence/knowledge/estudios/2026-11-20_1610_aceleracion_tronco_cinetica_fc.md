# Estudio horario 2026-11-20 16:10 UTC — Aceleración del tronco a galope (saturación del IMU) y cinética de la FC (mesetas de V200 y recuperación)

## Decisiones tomadas sin supervisión

- **Encadenamiento:** hay 5 PR `claude/kb-*` abiertos (#99, #101, #102, #104 y #106). La rama sale de la más reciente,
  `claude/kb-estudio-2026-11-20-1510` (PR #106), y hereda KB 1.17.0 y motor 2.0.0-dev19.
- **Temas elegidos.** Ninguno está cubierto hoy por otro estudio ni por un PR abierto:
  - **T1:** picos de aceleración del tronco a galope de carrera (12–18 m/s) y si el BNO085 de la cincha (±8 g) satura.
    Viene de la cola («Picos de aceleración del tronco en g a ≥ 12 m/s») y del pendiente «Contador de muestras saturadas
    de la cincha».
  - **T2:** cinética de la FC. Cuánto tarda la FC en estabilizarse al cambiar de velocidad, lo que importa para las
    mesetas de la V200/A9 (parámetro `fc_retraso_s`, en PENDIENTE), y cómo cae tras el trabajo (constante de
    recuperación, Hada).
- **Sin cambios de lógica del motor.** Las cifras de T2 que afectarían al cálculo de las mesetas solo se conocen por
  resumen o por reseñas secundarias. Las de T1 no dan un pico en g del tronco en texto. Solo suben las versiones: KB
  1.18.0 y motor 2.0.0-dev20.
- **Investigación:** 2 subagentes con WebSearch/WebFetch, unos 9 min cada uno.
- **Accesos denegados, sin esquivarlos:** PubMed/PMC (reCAPTCHA), API de Europe PMC (403 del proxy), link.springer.com
  y scilit (sin permiso en la sesión), y el primer enlace de JEB (sin permiso; se leyó otra URL del mismo editor).
- **Etiquetas.** Las reseñas automáticas de madbarn.com se tratan como resumen secundario: **[E-r²]**, a verificar en la
  fuente. No valen para fijar umbrales.

## T1. Aceleración del tronco a galope y saturación a ±8 g

| Fuente | Sensor, posición y rango | Muestra | Lo que da | Etiqueta |
|---|---|---|---|---|
| Pfau, Witte & Wilson 2006, *J Exp Biol* 209:3742, doi [10.1242/jeb.02439](https://doi.org/10.1242/jeb.02439) | Xsens MT9 en la cruz (apófisis T4–T6), **±10 g**, 250 Hz | 7 PSI, galope de 7 a 17 m/s, 1.107 zancadas | Mínimo dorsoventral ≈ −10 m/s² (≈ −1 g, fase aérea), sin cambio con la velocidad. El máximo dorsoventral baja algo con la velocidad y el craneocaudal sube algo. Sin cifras en el texto: están en las figuras 8C y 9C, que no se pudieron leer | [E] texto; picos [NV] |
| Parsons, Pfau, Ferrari & Wilson 2008, *J Exp Biol* 211:945, doi [10.1242/jeb.006692](https://doi.org/10.1242/jeb.006692) | MT9 en T4–T6, ±10 g, 250 Hz, paso bajo de 50 Hz | 6 PSI, 9–12 m/s, en llano y en pendiente | Sin cifras de aceleración en el texto. Las escalas de las figuras son ±20 m/s² (dorsoventral) y ±25 m/s² (craneocaudal), unos ±2–2,5 g. **Son límites de escala, no picos medidos** | [E] (escala); pico [NV] |
| Witte, Hirst & Wilson 2006, *J Exp Biol* 209:4389, doi [10.1242/jeb.02518](https://doi.org/10.1242/jeb.02518) | ADXL150 de ±50 g en el **casco** | 9 PSI, hasta 17,3 m/s | No mide el tronco | [E] |
| McSweeney et al. 2026, *JAVMA* 264(1), doi [10.2460/javma.25.04.0268](https://doi.org/10.2460/javma.25.04.0268) | StrideSAFE en el sudadero (zona lumbar), **±16 g por eje**, 800 Hz | 11.834 PSI en carrera | Rango del sensor. Sin picos ni saturación | [E] |
| Walker et al. 2016, *J Biomech*, doi [10.1016/j.jbiomech.2016.08.026](https://doi.org/10.1016/j.jbiomech.2016.08.026) | Xsens MTw en el sacro, ±16 g | 6 PSI a galope | Solo desplazamientos | [E] |
| Fercher et al. 2024, *Sensors* 24:8170, doi [10.3390/s24248170](https://doi.org/10.3390/s24248170) | Xsens de ±16 g en la cincha (esternón caudal) y en las cañas, 1.000 Hz internos | 20 caballos de deporte, solo galope de trabajo | Impacto de 14,03 ± 0,93 g de magnitud triaxial, **pero en las cañas, no en el tronco**. Sin amplitudes del tronco en g | [E]; [I-raza] (deporte, no carreras) |
| Barrey et al. 2001, *EVJ Suppl* 33:99, doi [10.1111/j.2042-3306.2001.tb05369.x](https://doi.org/10.1111/j.2042-3306.2001.tb05369.x) | Acelerómetro en la cincha | 30 PSI, velocidad máxima media 15,26 m/s | El resumen no da picos en g | [E-r] |

**Lectura para AVO [I]:**
- **Movimiento del cuerpo (< 50 Hz): ±8 g muy probablemente basta.** El acelerómetro del tronco mide la fuerza del suelo
  dividida por la masa. Con los ±2–2,5 g de escala de Parsons 2008 (hasta 12 m/s) y un máximo dorsoventral que no crece
  hasta 17 m/s (Pfau 2006 [E]), lo esperable es un pico de unos 2,5–3,5 g, lejos de 8 g. Esa cifra es una inferencia:
  **no hay ningún pico del tronco en g publicado en texto a 16–18 m/s**.
- **Transitorios de impacto sin filtrar: sin datos [NV].** Pueden venir de golpes de la cápsula o de la cincha contra
  el esternón y de resonancias del montaje. Los grupos de referencia eligen rangos de ±10–16 g, lo que apunta a un
  margen prudente.
- **Recomendación:**
  - Mantener el pendiente del contador de muestras saturadas (`|a| ≥ 7,9 g` en cualquier eje) por sesión y por tramo.
    Si en campo aparece más de un 0,1 % de muestras saturadas en galope, invalidar los picos de ese tramo, como ya
    prevé el estudio ampliado del 18/11. El umbral del 0,1 % es diseño [I].
  - Revisar la fijación de la cápsula REV 5.9.1: un montaje suelto es el riesgo principal.
  - En la cincha BETA (LSM6DSV16X), configurar **±16 g** como los sensores de referencia. Pierde poca resolución y
    elimina la duda. No se toca el firmware en este estudio; queda anotado para la portación.
  - Nada de esto está verificado con caballos reales.

## T2. Cinética de la FC: mesetas para la V200 y recuperación

### Subida (al cambiar de velocidad)

| Dato | Valor | Condiciones | Fuente | Etiqueta |
|---|---|---|---|---|
| Tiempo hasta el 95 % de la FC pico en carrera | 12,4 ± 1,8 s; pico 213,6 ± 1,7 lpm, con 171 lpm en los cajones | 23 PSI, carrera de 1.200 m | Mukai et al. 2007, *J Equine Sci* 18:153, doi [10.1294/jes.18.153](https://doi.org/10.1294/jes.18.153) | [E-r] |
| Cinética del VO₂ (no de la FC) en un escalón | Bajo el umbral de lactato: τ1 10,0 ± 0,9 s con 18,9 s de retraso. Por encima: τ1 20,7 ± 3,4 s y componente lento hacia los 136 s | n = 5, cinta, de 3 a 7 o 12,3 m/s | Langsetmo et al. 1997, *J Appl Physiol* 83:1235 (ya en la KB) | [E-r] |
| Deriva de la FC a carga constante | Al 50 % del VO₂max baja de 188 (30 s) a 172 lpm (300 s), con un sobrepico inicial. Al 100 % sube de 204 a 221 lpm | 6 trotones, cinta, 5 min | Evans & Rose 1988, *J Comp Physiol B* 157:791, doi [10.1007/BF00691010](https://doi.org/10.1007/BF00691010) | [E-r²] |
| VO₂ estable | Hacia los 90 s, con escalones de ≥ 2 min | 8 PSI | Rose et al. 1990, *EVJ Suppl* 9:39 | [E-r²] |
| Gramkow & Evans 2006 y Vermeulen & Evans 2006 | El resumen no da tiempos de meseta. Las diferencias de V200 entre sesiones son ≤ 2 % | PSI, GPS con medias de 5 s | Ya en la KB | [E-r²]; cinética [NV] |

**Lectura [I]:**
- Con unos 19 s de retraso y τ ≈ 10 s, el tiempo medio de respuesta ronda los 30 s. Descartar 20–30 s al inicio de
  cada meseta es coherente y **confirma el criterio de `fc_retraso_s`**, que sigue siendo [I].
- Por encima del umbral de lactato, τ se duplica y aparece la deriva al alza. Una meseta corta y rápida sesga la V200.
  Se anota como propuesta (pendiente CF1): **30 s de descarte y meseta de ≥ 45–60 s cuando la velocidad está cerca de
  la de galope de trabajo o el salto de velocidad es grande**. No se implementa: solo hay resúmenes.

### Recuperación (tras el trabajo)

| Dato | Valor | Condiciones | Fuente | Etiqueta |
|---|---|---|---|---|
| Forma de la caída | **Biexponencial.** Fase rápida τ 15 ± 2 s durante unos 55 s y fase lenta τ 455 ± 78 s. Con atropina pasa a monoexponencial (τ 174 ± 46 s) | **Ponis**, cinta extenuante, FC de 209 lpm | Rugh et al. 1992, *Biomed Sci Instrum* 28:151 | [E-r²]; [I-raza] (ponis: única fuente con τ numéricas) |
| Constante de recuperación y entrenamiento | Baja tras 11 semanas de entrenamiento (n = 7) y se correlaciona de forma inversa con el VO₂max (r = 0,43). **Sin valores de τ en el resumen** | PSI, 2,5 min a 8 m/s con 10 % de pendiente | Hada et al. 2007, *EVJ Suppl* 36:141, doi [10.1111/j.2042-3306.2006.tb05530.x](https://doi.org/10.1111/j.2042-3306.2006.tb05530.x) | [E-r²]; τ [NV] |
| FC a 1, 5, 15 y 30 min | Tras 10 min a 7 m/s: 126 ± 14,5; 75,9 ± 12,9; 51,4 y 42,9 lpm. Hasta 64 lpm: 547 ± 297 s | 7 árabes en cinta al 3 %, no de carreras | Lindner et al. 2020, *Animals* 10:120, doi [10.3390/ani10010120](https://doi.org/10.3390/ani10010120) | [E]; [I-raza] (árabes no de carreras, cinta) |
| Curva de campo | Caída rápida unos 5 min y ≈ 100 lpm a los 15 min. Los caballos de carreras de grupo recuperan unos 5,5 lpm más a 1 min y 6,7 lpm más a 2 min. Ajustado por caballo, no predice la victoria (p = 0,21) | 485 PSI, 4.837 galopes | Schrurs et al. 2024, *Animals* 14:1342 (ya en la KB) | [E] |
| FC a 1 min tras el 3.er intervalo | En forma 113 ± 8; listos para correr 124 ± 2; sin forma 149 ± 9 lpm | 20 caballos de obstáculos (National Hunt) | Wilson & McGowan, repositorio LJMU; año [NV] | [E]; [I-raza] (obstáculos) |
| Reproducibilidad a 60 s | CCI 0,60–0,66; MDC95 de 22–26 lpm (≈ 20 %) | 18 trotones franceses, 126 sesiones | Poinsard et al. 2026, *Animals* 16:1598 (ya en la KB) | [E] |

**Lectura [I]:**
- **No hay una τ de recuperación medida en PSI publicada en texto legible.** La de Hada sigue [NV] y la única con cifras
  es de ponis. El motor **no debe ajustar ni mostrar una τ con valores de referencia**. Como mucho, puede mostrar la τ
  del propio caballo como tendencia (una exponencial sobre 1–10 min, sin el primer minuto). Queda como pendiente CF2.
- Un cambio aislado de la FC a 1 min menor de unos 20 lpm no es interpretable (MDC95 de Poinsard). Encaja con los
  parámetros vigentes: `te_recuperacion_fc_lpm` y la fiabilidad baja antes de 90 s (Davie 2026). La recuperación sigue
  siendo solo informativa en A9.
- La velocidad durante la recuperación (paso o trote) cambia la FC del primer minuto. Si se calcula, debería registrarse
  como covariable [I].

## Correcciones y avisos de la KB

- **Fraipont 2011/2012** trabajó con caballos de **resistencia**, no con trotones, según la revisión de De Mare et al.
  2017 [E-r]. No se usa como fuente de carreras.
- Rugh 1992, Evans & Rose 1988, Rose 1990, Hada 2007 y la parte de cinética de Vermeulen/Gramkow se conocen solo por
  reseñas automáticas de terceros ([E-r²]). Quedan en la cola para leerlos en la fuente.

## Resumen

- **T1:** no hay ningún pico de aceleración del tronco publicado en g a 16–18 m/s. Los sensores de referencia usan ±10–16
  g y las escalas de la cruz rondan los ±2–2,5 g. Se estima [I] que ±8 g basta para el movimiento del cuerpo, pero no
  para posibles golpes de montaje [NV]. El contador de saturación sigue siendo necesario y se propone ±16 g en la cincha
  BETA. Nada verificado en hardware real.
- **T2:** el descarte de 20–30 s al inicio de las mesetas es coherente con lo publicado (VO₂ con unos 19 s de retraso y
  τ de 10–21 s; FC de carrera al 95 % en unos 12 s). Se propone una meseta de ≥ 45–60 s cerca del galope de trabajo
  (CF1, [I]). La recuperación es biexponencial, pero solo hay τ numéricas en ponis; la de los PSI (Hada) sigue [NV]
  (CF2).
- **KB 1.18.0, motor 2.0.0-dev20, sin cambios de lógica, umbrales ni cifras vigentes.** Nuevas: 9 fuentes, 3
  parámetros de contexto, 2 pendientes (CF1 y CF2) y 3 entradas de cola. La fatiga ósea y estas métricas nunca son una
  predicción de lesiones.
