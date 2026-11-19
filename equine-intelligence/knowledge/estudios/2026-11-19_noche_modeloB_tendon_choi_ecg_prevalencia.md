# Investigación nocturna 19/11/2026: constantes del modelo B, tendón (Choi & Parkin), lesiones de árabes y prevalencia de arritmias

**Base:** AVO_KB_1 1.1.0 → **1.2.0** · **Motor:** 2.0.0-dev3 → **2.0.0-dev4** · **Rama:** `claude/kb-noche-2026-11-19`
(sale de `develop/avo-performance-horse`; el PR nocturno anterior, #75, ya está fusionado).

Etiquetas: **[E]** dato publicado leído en la fuente primaria; **[E-r]** resumen leído en un espejo (MadBarn,
citedrive) o extracto automático de la página, no texto literal; **[I]** inferencia o cálculo propio; **[NV]** sin
verificar. Las cifras están parafraseadas; las citas literales son de pocas palabras.

## Decisiones de la noche (trabajo sin supervisión)

1. **Rama:** no hay PR nocturnos abiertos (`claude/kb-noche-2026-11-18` → PR #75, fusionado); la rama sale de
   `develop`. No existía la rama de hoy.
2. **Temas (cuatro):** constantes del modelo óseo B (bloquea código); Choi & Parkin 2025 completo (definición pendiente
   de A6); Yildirim 2025 (lesiones de árabes); prevalencia de prematuros en caballos sanos (A11). Más la búsqueda de
   estudios publicados desde el 18/11. Repartidos entre subagentes de investigación en paralelo, con una segunda lectura
   de verificación de las cifras usadas en el código.
3. **Modelo B: no se implementa.** Ya están las cinco constantes que faltaban, pero hay una **discrepancia de signo en
   b** (+0,02 frente a −0,02 según la lectura) y **no se publican** la f_BM inicial ni el paso de integración. Evidencia
   no cerrada (apartado 1).
4. **Pendiente del motor de esta noche (uno): regla A6B** «≤ 2 días de galope en 60 días» de Choi & Parkin 2025, con OR,
   IC y categoría de referencia confirmados en el texto completo. Solo **INFO / AVISO**; no sube el estado a VIGILAR.
   El cociente de galope 60/90 d **no** se implementa: su definición es ambigua (apartado 2).
5. **A11 (ECG) sigue PENDIENTE:** no hay un número aceptable publicado de prematuros; se anotan las cifras de sanos
   como expectativas del detector.
6. No hay informes de campo nuevos de los PROTOTIPOS desde el 17/11. No se tocan firmware, workflows, firmas,
   `Info.plist`, TestFlight ni contratos binarios.

---

## 1. Modelo óseo B: las cinco constantes que faltaban

**Fuente:** Anwar et al. 2026, R Soc Open Sci 13:260818, versión arXiv
[2603.22680v1](https://arxiv.org/html/2603.22680v1), tabla 9 y apéndice A.1. Dos lecturas independientes coinciden en
los valores, pero las dos son extractos automáticos de la página (la parte literal llegó hasta la tabla 8), así que se
etiquetan **[E-r]** hasta cotejarlas con el PDF o con la tabla 1 de Pan 2025 (PMC12483640, que no se pudo abrir).

| Constante | Valor | Unidad | Etiqueta |
|---|---|---|---|
| A_OBL_min | 0,001094 | mm/día | [E-r] |
| A_OBL_max | 0,00603 | mm/día | [E-r] |
| δ_B | 7 | MPa | [E-r] |
| γ_B | 1 | — | [E-r] |
| A_OCL_max | 0,00358 | mm/día | [E-r] |
| A_OCL_min · δ_C · γ_C | 0,001 · 1 · 2 | mm/día · MPa · — | [E] (coinciden con Pan 2025) |

Funciones de Hill del estímulo ψ = σ²/(2E) (apéndice A.1) [E-r]:
```
A_OBL = A_OBL_min + (A_OBL_max − A_OBL_min) · ψ^γB / (δ_B^γB + ψ^γB)      (formación: sube con ψ)
A_OCL = A_OCL_min + (A_OCL_max − A_OCL_min) · δ_C^γC / (δ_C^γC + ψ^γC)    (resorción: baja con ψ)
```
- Con γ_B = 1 la formación es una curva de Michaelis-Menten, no sigmoide [I].
- Pan 2025 (preprint, [PDF](https://www.biorxiv.org/content/10.1101/2025.04.06.646486.full.pdf)) [E]: δ_C = 1,0 MPa se
  elige entre el ψ de reposo (σ = 30 MPa, ψ ≈ 0,31) y el de carrera (σ = 90 MPa, ψ ≈ 2,36); γ_C = 2 para que sea
  sigmoide; A_OCL_max se ajustó a series de fracción de volumen óseo, y el valor de la literatura (0,011 mm/día) les
  pareció demasiado alto.
- **Discrepancia [NV]:** una lectura de la tabla 9 da **b = −0,02** y la anterior (y la base 1.1.0) **b = +0,02**. El
  signo cambia la forma de S_v = a·√(1−f_BM)·[1 − b·(1−f_BM)]. Hay que resolverlo en el PDF.
- **No publicado** en lo leído [NV]: f_BM inicial (solo «caballo sin entrenar y sin daño», es decir D*(0) = 0 [E]) y el
  paso o método de integración.
- Referencia de contraste [E, tabla 4 de Anwar]: f_BM máxima 0,926 / 0,931 / 0,935 y daño máximo 0,813 / 0,913 /
  1,016 en los programas «rápido y ligero», «moderado» y «alto volumen». Servirá de valor de prueba cuando se
  implemente.

**Decisión.** `modelo_B_constantes` se completa en la base, pero sigue **PENDIENTE** en el motor hasta resolver el
signo de b y la f_BM inicial (con la tabla 4 como prueba de reproducción).

## 2. Choi & Parkin 2025: tendinopatía del TFDS (Seúl)

**Fuente:** Choi Y, Parkin T. *Equine Vet J* 2025;58(1):31–39, doi 10.1111/evj.14493, texto completo en
[PMC12699112](https://pmc.ncbi.nlm.nih.gov/articles/PMC12699112/) [E]. Casos y controles retrospectivo, 2015–2019:
**101 casos y 304 controles** (420 eventos); prevalencia ≈ 1,8 % de 5.714 caballos con trabajo rápido [E].

- **Trabajo rápido** = galope de entrenamiento, *trial* o carrera. La KRA solo anota si el día fue de **galope o de
  canter**; **no hay velocidad ni distancia** (los autores lo dan como limitación) [E].
- **Descansos:** periodos de ≥ 60, ≥ 90 y ≥ 180 días sin trabajo rápido **dentro de los 365 días previos** [E].
- **Modelo multivariable final (tabla 2), siete variables** [E; ORs redondeados confirmados en el texto literal, cifras
  con tres decimales de la tabla en extracto E-r]:

| Variable (referencia) | OR | IC 95 % |
|---|---|---|
| *Trial* o carrera (frente a galope) | 11,389 | 5,183–25,026 |
| Jockey (frente a jinete de pista) | 0,352 | 0,151–0,821 |
| Grado 6 o sin grado (frente a 1–5) | 2,835 | 1,639–4,904 |
| ≥ 41 días de canter en 180 d (frente a ≤ 40) | 1,837 | 1,065–3,168 |
| **≤ 2 días de galope en 60 d (frente a 3–24)** | **1,842** | **1,073–3,162** |
| 1–2 periodos ≥ 90 d sin trabajo rápido en 365 d (frente a ninguno) | 3,098 | 1,737–5,526 |
| Cociente de galope ≤ 1,6 (frente a > 1,6) | 2,190 | 1,227–3,910 |

- **Cociente de galope:** días de galope en 60 d divididos por días de galope en 90 d (también 180 y 365), «ajustado
  sumando 1» [E]. La posición del +1 (fuera del cociente o en numerador y denominador) no queda clara en las lecturas
  [NV]: no se implementa, y el pendiente de A6 sigue abierto.
- Edad, sexo y distancia corrida no entraron en el modelo final [E]. Pronóstico: 95 de 101 casos no volvieron a correr
  [E].

**Implementado esta noche: regla A6B_POCO_GALOPE_60D.** Si en los 60 días previos hay **≤ 2 días con sesión rápida**,
el caballo está en entrenamiento (alguna sesión en los últimos 7 días, con canter en los 60) y hay 60 días de
historia, se emite un aviso informativo. Umbral y OR [E]; equivalencia «día de galope de la KRA = sesión rápida del
motor» [I] (la KRA no da velocidad); exigir sesiones en la última semana para no avisar a caballos parados [I]. Opción
`dias_galope_60d_max` (0–24, por defecto 2). Es un factor asociado en un estudio de casos y controles, **no una
predicción de lesión**.

## 3. Yildirim et al. 2025: lesiones de PSI y árabes (Turquía)

**Texto completo no accesible** (Wiley de pago). Resumen [E-r,
[MadBarn](https://madbarn.com/research/distribution-of-race-and-training-related-musculoskeletal-injuries-by-track-and-location-in-thoroughbred-and-arabian-racehorses)]
y artículo hermano con la misma serie [E, Yıldırım & Karaarslan, *Turk J Vet Res* 2025;9(1):33–40,
[PDF](https://dergipark.org.tr/en/download/article-file/4272043)]:

- 553 lesiones musculoesqueléticas en Şirinyer (İzmir), 2018–2023: **337 en PSI y 216 en árabes** [E].
- **Árabes:** lesión de tendón 137 (63,7 %), fracturas 42 (19,5 %), fisuras 29 [E]; las de tendón, sobre todo a los
  3 años (78) y 4 años (47) [E]; ≈ 48 % en el primer año de carreras [E].
- **PSI:** fracturas 206 (61,5 %), tendón 86 (25,7 %) [E].
- Miembros anteriores en carrera: 91,3 % (PSI) y 92,7 % (árabes) [E-r]. Las fracturas dominan en el PSI sobre todo en
  arena; las lesiones de tendón son frecuentes en árabes en las dos superficies [E-r]. Sin cifras por superficie.
- Fin de la carrera deportiva: 57,3 % (PSI) y 47,2 % (árabes) en el artículo turco [E]; el resumen de MadBarn da 66,3 %
  y 46,4 % [E-r]: incoherencia, vale el artículo.

**Consecuencia [I]:** en el árabe de carreras el **tendón** pesa más que el hueso. Refuerza A6/A6B y el «índice
tendinoso heurístico» de `pendiente_motor` para árabes de 3–4 años. La fatiga ósea del modelo A (calibrada en PSI) no
cubre el riesgo principal del árabe.

## 4. Prevalencia de arritmias en caballos sanos (expectativas para A11)

Todo en resumen [E-r] salvo Marr 2020 (texto completo). No se pudieron abrir Ryan 2005 (PubMed), Wiley ni PMC6335521.

| Estudio | Caballos | Ejercicio | Recuperación | Recuentos |
|---|---|---|---|---|
| Buhl, Meldgaard & Barbesgaard 2011, EVJ Suppl 38:196 (saltadores sanos) | 34 (6 excluidos por calidad) | supraventriculares 89 %; ventriculares 18 % | 54 % y 7 % | < 9 supraventriculares y < 2 ventriculares por caballo; máx. 13 en ejercicio y 41 en recuperación |
| Barbesgaard, Buhl & Meldgaard 2011, EVJ Suppl 38:202 (doma) | 21 | supraventriculares 28,6 % | 61,9 % (1 h) | la mayoría ≤ 3 |
| Massie et al. 2023, Vet J 106040 (PSI de chuckwagon) | 52 (40 pareados) | ventriculares 17,5 % | 20–22,5 % | ventriculares: mediana 0; 0–4 en entrenamiento y 0–8 en competición; mala repetibilidad por tipo |
| Slack et al. 2015, EVJ 47:398 (trotones, tras la carrera) | 1.816 (8.657 ECG) | — | FA 0,11 %; taquiarritmia ventricular 0,06 % | — |
| Marr et al. 2020, EVJ (245 PSI con bajo rendimiento, sin controles) [E, [PDF](https://core.ac.uk/download/333648061.pdf)] | 245 | galope 24,9 % | 50,6 % | aisladas 44,9 %; complejas 19,6 %; ECG a 500 Hz |

- **Ninguna fuente propone un número aceptable** de prematuros (coincide con el consenso de Reef 2014) [E-r].
- **Expectativa para el detector [I]:** en un caballo sano, de 0 a ~9 supraventriculares por prueba y algún ventricular
  aislado; la recuperación tiene una prevalencia igual o mayor que el ejercicio, así que se cuenta por fase.
- Kapusniak et al. 2026, EVJ doi 10.1002/evj.70205 [E-r,
  [resumen](https://madbarn.com/research/validation-of-a-smart-textile-electrocardiographic-monitoring-device-in-racehorses-during-high-speed-exercise/)]:
  50 caballos al galope, textil frente a Televet; registros sin artefacto 76 % frente a 37 %; FC máxima ICC 0,995;
  arritmias en 43 de 50 (86 %); concordancia de clasificación κ 0,96.
- Marr 2020 cita 500 Hz como «baja» frecuencia de muestreo entre sus limitaciones [E]: apoya los ≥ 500 SPS preferidos
  para la cincha [I].

## 5. Estudios publicados desde el 18/11/2026

No se encontró ningún artículo revisado por pares publicado entre el 1 y el 19/11/2026 sobre carga, hueso, GPS, FC,
zancada o ECG en caballos de carreras en llano (PubMed y Wiley estaban bloqueados; búsqueda incompleta). Lo más
reciente: la versión final de Anwar et al. 2026 en RSOS 13(10):260818 (octubre de 2026) y Kapusniak et al. 2026
(junio). Li et al., EVJ doi 10.1002/evj.70360 (fatiga en caballos de deporte con sensores y ML) no se pudo abrir [NV].

---

## Resumen de la noche

- **Modelo B:** constantes A_OBL_min/max, δ_B, γ_B y A_OCL_max recogidas de la tabla 9 de Anwar 2026 [E-r]. No se
  implementa: signo de b dudoso y sin f_BM inicial publicada. La tabla 4 de Anwar queda como prueba de reproducción.
- **Tendón (Choi & Parkin 2025, texto completo):** tabla 2 recogida; **regla nueva A6B** (≤ 2 días de galope en 60 d,
  OR 1,84) en el motor como aviso informativo. El cociente 60/90 d sigue pendiente por ambigüedad.
- **Árabes (Yildirim 2025):** en árabes predominan las lesiones de tendón (64 %) frente a las fracturas (20 %); en PSI
  al revés.
- **ECG:** sin número aceptable publicado; expectativas de 0–9 supraventriculares por prueba en sanos; contar por fase.
- **Motor:** `KNOWLEDGE_VERSION` 1.1.0 → 1.2.0, `ENGINE_VERSION` 2.0.0-dev3 → 2.0.0-dev4; campo nuevo
  `dias_galope_60d` en el estado de la base científica.
- **Validación:** pruebas locales con ASan/UBSan, 96 casos y 1.638 comprobaciones sin fallos; fixtures regeneradas
  (solo cambian las versiones). **NO VERIFICADO** con caballos reales.
- **Textos que hay que conseguir a mano:** PDF de Anwar 2026 (tabla 9: signo de b), tabla 1 de Pan 2025 (JRSI),
  Yildirim 2025 (Wiley), Ryan 2005, Verheyen 2006 y Van Erck-Westergren 2026.
