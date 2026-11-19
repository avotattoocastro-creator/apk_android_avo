# Estudio extra 3 (19/11/2026): restricciones del planificador semanal y ECG en ejercicio (detector de QRS y regla A11)

Etiquetas: **[E]** dato de la fuente leído en el texto completo (a través de un extractor automático: conviene cotejar
las tablas en el PDF antes de fijar umbrales en el código); **[E-r]** dato leído solo en el resumen (a menudo la ficha
de MadBarn, que avisa de que su resumen lo genera una IA); **[I]** inferencia propia de AVO; **[NV]** no verificado.
Este estudio **no** contiene datos de caballos de AVO: nada aquí está «verificado con caballos reales».

## Decisiones del estudio (trabajo sin supervisión, 16:12–17:05 UTC)

1. **Temas elegidos:** (1) restricciones del **planificador semanal** (capa 2, pendiente del motor sin estudiar todavía) y
   (2) **ECG en ejercicio**: detector de QRS, umbral de prematuridad, puerta de calidad y fases para la **regla A11**.
   La prevalencia de arritmias, V200 y el índice tendinoso ya se estudiaron (estudios del 18 y 19/11) y no se repiten.
   El tercer tema (árabes de carreras) se cubrió dentro de los dos anteriores: **no hay datos publicados** de programa
   semanal ni de ECG en ejercicio en árabes de carreras en llano.
2. **No se implementa ninguna regla nueva en el motor.** Los números del planificador que tienen evidencia describen la
   práctica habitual de los entrenadores, no umbrales de seguridad, y la forma de las restricciones es [I]; la A11
   necesita que el análisis traiga el ECG latido a latido, que hoy no trae. La evidencia no está cerrada.
3. Para mantener alineados el JSON y el código, la KB sube a **1.6.0** y se sube solo la constante
   `KNOWLEDGE_VERSION` (y `ENGINE_VERSION` a 2.0.0-dev8, porque el número sale en el análisis). Ninguna fórmula cambia.
4. Dos subagentes buscaron en paralelo (WebSearch/WebFetch); se citan solo fuentes que abrieron. Textos bloqueados:
   todo `pmc.ncbi.nlm.nih.gov` (reCAPTCHA: PMC6335521, PMC5126988, PMC12699123, PMC7891449), Europe PMC, Springer
   (Flethøj en PDF), OUP (Frick), Cambridge (Parker 2010), ResearchGate y HAL INRAE.

---

## 1. Planificador semanal: qué restricciones tienen respaldo

### 1.1 Cuántos trabajos rápidos por semana (práctica de los entrenadores)

| Fuente | Población | Cifra | Etiqueta |
|---|---|---|---|
| Morrice-West et al. 2020, *EVJ*, doi 10.1111/evj.13156 (manuscrito en minerva-access.unimelb.edu.au) | Encuesta a 66 entrenadores de Victoria (Australia), 1.720 PSI | Galopes rápidos (≥ 13,3 m/s) por semana: media 2,0 (IC 95 % 1,8–2,2) en ≥ 3 años; 1,7 (1,5–1,8) en 2 años. Por programa: 1,43 (volumen bajo), 1,98, 2,11 y 2,8 (volumen alto) | [E] |
| Ídem | Ídem | Distancia ≥ 13,3 m/s en maduros en forma: mediana 8.000 m/mes (IQR 6.400–12.000); por programa 4.800 / 8.000 / 12.800 / 19.200 m/mes | [E] |
| Ídem | Ídem | Trabajo lento: mediana 6 días/semana (5–7 en maduros; 4–7 en 2 años): normalmente un día libre | [E] |
| Ídem | Ídem | Bandas: paso < 10 m/s; «pace» 11,1–12,5 m/s; galope 13,3–14,3 / 14,4–15,4 / 15,5–16,7 / ≥ 16,8 m/s; «even time» = 13,33 m/s | [E] |
| Morrice-West et al. 2021, *Animals* 11:3130, doi 10.3390/ani11113130 | Mismos entrenadores, temporada 2016/17 | 7.500–15.000 m a ≥ 13,3 m/s antes del primer *trial* se asoció con más victorias; galope lento (13,3–14,3 m/s) > 12.500 m empeoró el rendimiento (p = 0,003) | [E] |
| Parkin et al. 2004, *EVJ* 36:513, doi 10.2746/0425164044877387 | Reino Unido, fracturas distales mortales | No galopar nada aumentó el riesgo; mínimo semanal propuesto 805–2.012 m | [E-r] |
| Parkin et al. 2005, *EVJ* 37:192, doi 10.2746/0425164054530641 | Fractura condilar lateral | Galope mínimo propuesto 201–1.609 m/semana | [E-r] |

**Hueco importante:** ningún estudio accesible publica los **días entre trabajos rápidos**. Johnston et al. 2020
(*EVJ*, doi 10.1111/evj.13324, Hong Kong) los calcula, pero no publica el resultado [E]. Hitchens, Hill & Stover 2018
(*Front Vet Sci* 5:217, doi 10.3389/fvets.2018.00217) da, **sin ajustar**, OR 1,03 (1,00–1,06) por cada día más entre
trabajos [E]: si acaso, más espaciado se asoció con más riesgo. La separación mínima entre trabajos rápidos es [I].

### 1.2 Carga reciente frente a carga antigua

| Fuente | Cifra | Etiqueta |
|---|---|---|
| Hitchens et al. 2018 (California, PSI, multivariable) | Carreras por año: OR 3,14 (1,39–7,08) por duplicación. Distancia rápida del **último mes** OR 0,84 (0,76–0,93) por estadio (protectora); de los **meses 3–4** OR 1,07 (1,01–1,13) (riesgo) | [E] |
| Georgopoulos & Parkin 2017, *Prev Vet Med* 139:99, doi 10.1016/j.prevetmed.2016.12.006 (Norteamérica, 2,2 M salidas) | Salidas en los 30 d previos OR 0,713 (0,677–0,750) por salida; en 90–180 d OR 1,069 (1,053–1,085); meses desde la última salida OR 1,203 (1,169–1,239) | [E] |
| Estberg et al. 1998, *Prev Vet Med* 33:159, doi 10.1016/s0167-5877(97)00047-0 | Distancia diaria a alta velocidad en ventana móvil de 60 d > P75: en los 30 d siguientes, lesión catastrófica RR 4,2 (3,0–5,8) | [E-r] |
| Morrice-West et al., resumen ICRAV 2026 (Hong Kong, 5.215 caballos) | Fatiga subcondral consumida por evento: carrera 10,1 %, *trial* 8,19 %, trabajo rápido 3,21 %, lento 0,41 %; el trabajo rápido aporta el 39,6 % de la fatiga de una preparación | [E-r] |
| Hitchens et al. 2019, *Vet J* 245:29, doi 10.1016/j.tvjl.2018.11.014 (meta-análisis) | No combina descansos ni ejercicio rápido por heterogeneidad; solo edad (OR 1,19/año) y haber corrido antes (OR 0,69) | [E] |

Lectura para AVO [I]: el planificador no debe castigar la carga rápida del último mes (aparece como protectora); lo
que se asocia con riesgo es la **acumulación sostenida de 60–180 días** y la vuelta tras mucho tiempo parado. Encaja con
el modelo óseo A ya implementado y con A3/A5/A6B.

### 1.3 Descansos y vuelta al trabajo

| Fuente | Cifra | Etiqueta |
|---|---|---|
| Morrice-West 2020 | Maduros: 1,9 descansos/año (DE 0,7) de 6,3 semanas (IC 5,7–6,8); 2 años: 2,1 de 6,6 semanas. Tras el descanso: 60 % vuelve al plan habitual, 24 % prepara 2–4 semanas, 16 % > 4 semanas; primer *trial* a las 9,5 semanas (4,0 de trabajo lento) | [E] |
| Wong et al. 2023, *Front Vet Sci* 10:1260554, doi 10.3389/fvets.2023.1260554 | Maduros: descansos largos y frecuentes frente a largos e infrecuentes, IRR de lesión 0,58 (0,42–0,81). 2 años: frente a cortos y frecuentes, cortos e infrecuentes IRR 4,02 (1,70–9,53), largos e infrecuentes 2,36, largos y frecuentes 3,44. Programa de volumen alto: lesión catastrófica IRR 2,66 (1,17–6,09; solo 6 entrenadores). Asociación, no causalidad | [E] |
| Wong et al. 2023, *EVJ* 55:194, doi 10.1111/evj.13581 (Tasmania) | Más % de la carrera deportiva en descanso (> 60 d) redujo el riesgo de lesión (coef. −0,011) | [E] |
| Carrier et al. 1998, *JAVMA* 212:1582 (PMID 9604029) | Fractura de húmero tras volver de ≥ 2 meses sin trabajos rápidos: RR 71 en los primeros 10 d y 45 en 21 d | [E-r] (DOI no confirmado) |
| Perkins, Reid & Morris 2005, *N Z Vet J* 53:59, doi 10.1080/00480169.2005.36470 | 29 % del tiempo en descanso; primera salida ~68 d tras empezar; intervalo entre salidas mediana 17 d | [E-r] |

### 1.4 Intervalo entre carreras

Morrice-West 2020: media 2,3 semanas (IC 2,1–2,4) [E]. Morrice-West 2021: mejor rendimiento al alargar el intervalo
hasta ~3 semanas y peor después; óptimo discutido 2,5–3 semanas [E]. Hitchens 2018: días entre carreras OR 0,99
(0,98–1,00), sin ajustar [E].

### 1.5 Árabes de carreras en llano

No se encontró ningún estudio primario con programa semanal ni frecuencia de trabajos rápidos en árabes de carreras en
llano (lo publicado es raid o bioquímica). Toda restricción para árabes es extrapolación del PSI [I], con las
velocidades absolutas ya escaladas por el ritmo de carrera (bandas relativas de KB-1).

### 1.6 Restricciones propuestas para la capa 2 (no implementadas)

| # | Restricción | Base |
|---|---|---|
| P1 | Semana activa: 1–2 trabajos rápidos en 2 años y 2–3 en maduros; nunca 0 en semana activa | Práctica [E] (Morrice-West 2020); «0 es peor» [E-r] (Parkin 2004/2005); forma [I] |
| P2 | Al menos un día libre por semana; ≥ 2 días de trabajo lento o paso entre trabajos rápidos | Día libre [E] (práctica); separación [I] (sin evidencia directa) |
| P3 | Intervalo entre carreras objetivo 17–21 d; aviso por debajo de 14 d | [E] Morrice-West 2020/2021, Hitchens 2018; mínimo rígido [I] |
| P4 | Tras > 60 d sin trabajo rápido: ~4 semanas de trabajo lento, y 21 d con un solo trabajo rápido semanal de distancia reducida (refuerza A5) | Duración [E]; riesgo 10–21 d [E-r] (Carrier 1998); forma [I] |
| P5 | Aviso si la distancia rápida diaria media de 60 d supera el P75 **propio** del caballo; sin penalizar el último mes | [E] Hitchens 2018, Georgopoulos 2017; [E-r] Estberg 1998; P75 propio [I] |
| P6 | ≥ 2 descansos al año de ~6 semanas en maduros; cortos y frecuentes en 2 años | [E] Morrice-West 2020, Wong 2023; árabes [I] |

Nada de esto predice lesiones: son límites de prudencia para proponer una semana, que el entrenador decide.

---

## 2. ECG en ejercicio: detector de QRS y regla A11

### 2.1 Detector de QRS en el caballo

- **Van Steenkiste, van Loon & Crevecoeur 2020**, *Sci Rep* 10:186, doi 10.1038/s41598-019-57025-2 [E]: 15 caballos,
  26.440 latidos anotados por 2 cardiólogos, 500 Hz, derivaciones I y II, Holter (**reposo, no carrera**). Detectan el
  **pico S** (onda dominante en el caballo) con wavelet estacionaria (Symlet 4) y umbral adaptativo: **VPP 99,1 %,
  sensibilidad 98,0 %**. Pan-Tompkins sin adaptar: **VPP 81,5 %, sensibilidad 91,5 %**, con falsos positivos sobre todo
  por **ondas T altas**; los falsos negativos del detector propio venían del periodo ciego tras un artefacto grande.
  Clasificación de latidos: APC sensibilidad 73,2 % (43,3 % sin *transfer learning*), VPC 97,1 %, artefacto 87,8 %.
- **Alexeenko et al. 2026**, *Sci Rep* 16:13357, doi 10.1038/s41598-026-41281-0 [E]: detector propio en C++ sin
  validación publicada; tiras de 60 s válidas si ningún RR se desvía > 30 % de la media. El artículo tiene
  incoherencias internas en el número de caballos y de casos [NV para esas cifras].
- **Zucca et al. 2003**, *Vet Res Commun* 27 supl. 1:811 [E-r]: el software de Holter humano necesitó revisión manual.
  **Delecave Dias et al. 2026**, *EVJ*, doi 10.1002/evj.70223 [E-r]: un parche comercial marcó más prematuros falsos
  que Televet (sin cifras en el resumen).

### 2.2 Calidad del registro en ejercicio

| Fuente | Cifra | Etiqueta |
|---|---|---|
| Ter Woort et al. 2022, *EVJ* 55:336, doi 10.1111/evj.13565 (49 caballos, 29 de carreras > 40 km/h) | Registro excluido si > 10 % de artefacto; artefacto en ejercicio 5 % (Televet) frente a 0,25 % (Equimetre); kappa 0,97 detección y 0,93 clasificación | [E-r] |
| Kapusniak et al. 2026, *EVJ*, doi 10.1002/evj.70205 (25 PSI + 25 trotones, 123 sesiones) | 12 % de registros no diagnósticos; sesiones sin artefacto 76 % (textil) frente a 37 % (Televet); FC máx. sesgo −0,15 lpm, ICC 0,995; discrepancias de clasificación todas por artefacto | [E-r] |
| Trachsel et al. 2011, *EVJ Suppl* 38:208, doi 10.1111/j.2042-3306.2010.00172.x (10 caballos en cinta) | Acuerdo entre observadores en la clase y el momento del evento: reposo 92,6–96 %; **ejercicio 0–13 %**; recuperación 0–5 min 18–23 % | [E-r] |
| Marr et al. 2020, *EVJ*, doi 10.1111/evj.13354 (core.ac.uk) | 500 Hz, derivación II base-ápex modificada (o el canal con menos artefacto); el ECG no diagnóstico se excluye sin definición formal | [E] |

### 2.3 Umbral de prematuridad

| Fuente | Criterio | Etiqueta |
|---|---|---|
| Navas de Solis et al. 2026, *EVJ*, doi 10.1002/evj.70166 (11 PSI con muerte súbita, 24 ECG) | Prematuro si el RR es **≥ 5 % más corto** que el anterior; R corregidas a mano; FC pico = media de los 5 RR más cortos sin prematuros: mediana 216 lpm (200–237) | [E] |
| Frick, Schwarzwald & Mitchell 2019, *JVIM* 33:212, doi 10.1111/jvim.15358 (54 caballos en cinta) | Variación de RR en sanos −6,1 % a +5,4 % al galope; en la recuperación, acortamiento > 6 % frente al ciclo anterior: sensibilidad 88 %, especificidad 97 % | [E-r] |
| Flethøj et al. 2016, *BMC Vet Res* 12:266, doi 10.1186/s12917-016-0894-2 (caballos de resistencia) | Umbral según FC: 20 % (< 60 lpm), 10 % (60–100), 4 % (> 100) | [E-r], símbolo mal transcrito en el resumen: [NV] hasta leer el PDF |

Consecuencia de muestreo [I]: a 220 lpm el RR dura ~273 ms y un 5–6 % son 14–16 ms. A 250 SPS (4 ms por muestra) eso
son 3–4 muestras: justo; con 250 SPS hay que interpolar el pico. Se mantiene «preferible 500 SPS» (Marr 2020 y Van
Steenkiste 2020 usan 500 Hz [E]).

### 2.4 En qué fase aparecen los ectópicos

- **Marr 2020** [E] (245 PSI con bajo rendimiento, cinta): caballos con cualquier alteración del ritmo en
  calentamiento 8,2 %, galope 24,9 %, **recuperación 50,6 %**; de los 48 con ritmos complejos, el 93,8 % en la recuperación.
- **Jose-Cunilleras et al. 2007**, *EVJ Suppl* 36:163, doi 10.1111/j.2042-3306.2006.tb05534.x [E-r] (88 PSI): los
  prematuros se concentran en el **primer minuto** de la recuperación.
- **Navas de Solis 2026** [E]: recuperación temprana = primeros 2 min; prematuros en ejercicio mediana 2 (0–23) y en
  recuperación temprana mediana 2 (0–77).
- **Alexeenko 2026** [E], definición de caso: ≥ 5 prematuros y/o ≥ 1 pareja, triplete o taquicardia, con FC > 180 lpm o
  en la deceleración (~2 min tras el pico). Marr 2020 [E] usa la misma estructura (aislados frente a complejos;
  taquicardia ≥ 4 seguidos, con una incoherencia interna «> 4»).

### 2.5 Árabes

Sin estudios de ECG con ectopia en ejercicio en árabes de carreras en llano. Janczarek et al. 2016 (*Acta Vet Brno*
85:355, doi 10.2754/avb201685040355) [E] solo estudia VFC con Polar en 67 árabes en entrenamiento de carreras.

### 2.6 Especificación revisada de A11 y del detector (no implementada)

| Parámetro | Propuesta | Base |
|---|---|---|
| Ancla del detector | Pico S (o |QRS| máximo), wavelet o filtro adaptativo; rechazo de T con periodo refractario (~150 ms a FC alta); **no cegar** tras artefacto | [E] Van Steenkiste 2020; refractario [I] |
| Objetivo de validación | VPP ≥ 99 % y sensibilidad ≥ 98 % frente a anotación manual **en galope real** de la cincha PROTOTIPO REV 5.10 | Cifras de reposo [E]; exigencia en galope [I] |
| Muestreo | 500 SPS preferible; 250 SPS con interpolación del pico | [E] / [I] |
| Prematuro | ≥ 6 % más corto que la mediana de los 8 RR previos con FC > 100 lpm (≥ 5 % frente al anterior en Navas de Solis); 10–20 % por debajo de 100 lpm | [E] / [E-r] / [I] |
| Puerta de calidad | Ventanas de 5–10 s no interpretables si no hay QRS en > 2 s, FC fuera de 25–250 lpm o clasificadas como artefacto; si > 10 % de una fase no es interpretable, A11 no se evalúa en esa fase | 10 % [E-r] (Ter Woort); resto [I] |
| Fases | Calentamiento, pico (FC > 180), deceleración + recuperación temprana (0–2 min), recuperación tardía; la recuperación temprana pesa igual o más que el pico | [E] Marr, Navas de Solis, Alexeenko; peso [I] |
| Niveles | Aislado: INFO; ≥ 5 prematuros o ≥ 1 pareja/triplete: VIGILAR; racha ≥ 4 o sospecha de FA: revisión veterinaria | Estructura [E] (Alexeenko, Marr); niveles [I] |
| Salida | Siempre «candidato a revisar» con la tira de ECG adjunta, nunca diagnóstico (acuerdo entre observadores en ejercicio 0–13 %) | [E-r] Trachsel 2011 |

---

## Resumen

- **Planificador semanal:** hay evidencia [E] de la práctica habitual (≈ 2 trabajos rápidos/semana en PSI maduros,
  1,7 en 2 años; ~8 km/mes a ≥ 13,3 m/s; un día libre; ~2 descansos/año de ~6 semanas; carreras cada 2,3 semanas,
  óptimo 2,5–3) y de que la carga reciente protege mientras la acumulada en 60–180 d y la vuelta tras parar se asocian
  con riesgo. **No hay evidencia publicada sobre los días entre trabajos rápidos** ni ningún dato de árabes de llano:
  esas restricciones son [I]. Se proponen seis restricciones P1–P6, sin implementar.
- **ECG / A11:** el único detector equino validado (Van Steenkiste 2020, en reposo) logra VPP 99,1 % y sensibilidad
  98,0 % anclando en la onda S; Pan-Tompkins sin adaptar falla con ondas T altas. El umbral de prematuro publicado en
  ejercicio es 5–6 % de acortamiento del RR (Navas de Solis 2026 [E], Frick 2019 [E-r]); la mitad de las alteraciones
  aparecen en la recuperación (Marr 2020 [E]); el acuerdo entre cardiólogos en ejercicio es muy bajo, así que A11 solo
  puede marcar «candidatos a revisar». Falta validar el detector con galope real anotado.
- **Motor:** sin cambios de lógica; KB 1.6.0 y motor 2.0.0-dev8 solo por versión. Nada de esto se ha verificado con
  caballos reales.
- **Para leer cuando se pueda:** PMC12699123 (Norteamérica 2009–2023, días desde la última carrera y el último trabajo),
  Flethøj 2016 en PDF (signo del umbral), Frick 2019 completo, Carrier 1998 y Estberg 1998 en PubMed.
