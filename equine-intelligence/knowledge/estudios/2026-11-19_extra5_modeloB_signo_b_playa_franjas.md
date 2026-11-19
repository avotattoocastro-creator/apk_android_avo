# Estudio extra 5 (19/11/2026): constantes pendientes del modelo óseo B y línea base de la playa por franja

**Inicio:** 23:31 UTC (`date -u`) · **Cierre previsto:** antes de las 00:31 UTC · **Autor:** Claude (a petición del
usuario: «lanza otro estudio ahora») · **Base:** KB-1 1.7.0 → **1.8.0** · **Motor:** 2.0.0-dev9 → **2.0.0-dev10**
(solo versiones).

Etiquetas: **[E]** dato leído en el texto completo (a través de un extractor automático: conviene cotejar tablas en el
PDF antes de fijar umbrales); **[E-r]** dato leído solo en el resumen (las fichas de MadBarn reproducen el resumen y
añaden otro generado por IA: solo se usan las cifras del resumen original); **[I]** inferencia propia; **[NV]** no
verificado. Nada de este estudio está **verificado con caballos reales**. La fatiga ósea del modelo B **no es una
predicción de lesiones**.

## Decisiones tomadas sin supervisión
1. **Rama** `claude/kb-estudio5-2026-11-19` (el nombre `kb-estudio4` ya lo usó el estudio extra 4), desde
   `develop/avo-performance-horse` actualizada (PR #85–#87 fusionados).
2. **Temas:** (a) **modelo óseo B**, que bloquea código por tres datos (signo de b, f_BM inicial, paso de
   integración) y la prueba de reproducción con la tabla 4 de Anwar; (b) **línea base de la playa por franja**, que el
   estudio extra 4 dejó sin hacer. Dos subagentes en paralelo con WebSearch/WebFetch.
3. **Motor sin cambios de lógica.** El signo de b y la f_BM inicial quedan cerrados en texto completo, pero el paso y el
   método de integración no se publican y la tabla 4 de Anwar no se puede reproducir sin su código (Zenodo bloqueado):
   no hay valores de referencia exactos para las pruebas. Se suben `KNOWLEDGE_VERSION` y `ENGINE_VERSION` para que el
   análisis declare la base revisada, como en los estudios extra 3 y 4.
4. **Corrección en la base:** `modelo_B_constantes.b` pasa de **+0,02 a −0,02**, con la convención de la ecuación 2 de
   Anwar escrita en la nota (ver 1.2). No afecta a ningún cálculo implementado (el modelo B sigue PENDIENTE).
5. **Bloqueos:** PMC12483640 (Pan 2025, JRSI) y Europe PMC; Zenodo 10.5281/zenodo.19173866 (código de Anwar) y
   10.5281/zenodo.16557014 (Pan); HTML de bioRxiv; texto completo de Chateau 2011 y Crevier-Denoix 2011 en Wiley;
   repositorio de UCLan (Holt 2014, Northrop 2016, Hernlund 2017); PubMed y HAL INRAE (captcha/anti-bots). Una copia del
   *Equine Surfaces White Paper* en un sitio de terceros no se descargó (robots.txt y autorización dudosa).

---

## 1. Modelo óseo B (Pan 2025 / Anwar 2026)

### 1.1 Fuentes leídas
- Anwar et al. 2026, preprint arXiv 2603.22680v1, versión HTML (apéndice A, tablas 1–4 y 9) — https://arxiv.org/html/2603.22680v1 [E].
- Pan et al. 2025, preprint bioRxiv 10.1101/2025.04.06.646486 (PDF) [E; las ecuaciones son imágenes y no salen en el texto extraído].
- Hitchens et al. 2018, *Biomech Model Mechanobiol* 17:877 (origen de a y b) — core.ac.uk/download/185522549.pdf [E].

### 1.2 Signo de b: cerrado
- En Anwar (ec. 2) b **solo aparece en el factor de superficie**: S_v = a·√(1 − f_BM)·[1 − b·(1 − f_BM)] [E].
  No está en la ecuación de formación.
- Tabla 9 de Anwar («Pan et al. 2025»): **b = −0,02**, adimensional [E].
- Hitchens 2018 (ec. 6): g(f) = b·f + 1 − b, idéntico a [1 − b(1 − f)], con **b = −0,02** explícito [E].
- El texto del preprint de Pan escribe «b = 0,02» sin signo [E], pero su ecuación es una imagen [NV]: lo más probable es
  que use el corchete [1 + b(1 − f)], equivalente. Con f = 0,61 la diferencia entre ambas lecturas en S_v es 1,6 % [I].
- **Decisión:** b = −0,02 con S_v = a·√(1 − f)·[1 − b(1 − f)], es decir, corchete = 1 + 0,02·(1 − f_BM).
- La formación **crece** con el estímulo (A_OBL, Hill creciente en ψ) y la resorción decrece (A_OCL) [E].

### 1.3 f_BM inicial: cerrada para el caso de referencia
| Fuente | f_BM(0) | Etiqueta |
|---|---|---|
| Pan 2025 (bioRxiv, figura 6 y resultados), caballo sin entrenar, D*(0) = 0 | **0,61** | [E] |
| Pan 2025, análisis de sensibilidad (figura 4) | 0,7 | [E] |
| Anwar 2026 | sin número; «sin entrenar y sin daño», D*(0) = 0 | [E] |
| Hitchens 2018 | 0,5 (sin entrenar), 0,8 (reposo > 4 semanas), 0,9 (entrenamiento intenso) | [E] |

Decisión: f_BM(0) = 0,61 para un caballo sin historia; para un caballo que llega ya en entrenamiento, el valor de
partida es [I] (rango 0,8–0,9 de Hitchens) hasta que AVO tenga su propio periodo de calentamiento del modelo.

### 1.4 Paso de integración: no publicado
Ninguna de las tres fuentes da dt ni el método [NV]; Hitchens 2018 dice que usó MATLAB R2015b sin nombrar el
*solver*. La unidad de tiempo es el día (entradas en ciclos/día y m/semana) [E]. Estimación propia [I]: df/dt ≲ 0,01/día
y reparación ≈ 0,03/día, así que Euler explícito con dt = 1 d sería estable; para comparar con las referencias, dt = 0,1 d
o RK4.

### 1.5 Ecuaciones y entradas (Anwar 2026, apéndice A) [E]
- df_BM/dt = (A_OBL − A_OCL)·α·S_v; ψ = σ²/(2E); E = E0·ε̇^γE·f_BM³.
- dD*/dt = D_f′ − D_r′; D_f′ = v_D(σ)·v_n; v_D = 10^((σ − σ0)/σ1)·E_nom/E;
  D_r′ = [A_OBL + (F_s − 1)·A_OCL]·α·S_v·D*/f_BM. D* = 1 es fallo local del modelo (no una lesión clínica).
- Entradas por velocidad s (m/s): F_g = 2,778 + 2,1376·s − 0,0535·s²; σ = σ_max·F_g/F_max (σ_max 90 MPa, F_max
  24,13 N/kg); ε̇ = 0,01548·s + 0,0004955·s²; f = 1,7052 + 0,0305·s + 0,0004·s²; v_n = d·f/s. Con varias velocidades
  en el día, σ y ε̇ toman el máximo y D_f′ se suma.
- E_nom = E0·0,9³·0,36^0,06 = 1714,1 MPa (Pan) [E]; comprobado: 2500 × 0,729 × 0,9405 = 1714,1 [I].
- Constantes de la tabla 9: coinciden con las ya guardadas en `modelo_B_constantes` salvo el signo de b.
  δ_B y δ_C figuran en MPa aunque ψ es una densidad de energía [E, sin corregir].

### 1.6 Valores de referencia disponibles (no exactos)
**Anwar 2026, tabla 4, cuarta preparación** [E]:

| Medida | Rápido y ligero | Moderado | Alto volumen |
|---|---|---|---|
| f_BM mín. / máx. | 0,858 / 0,926 | 0,864 / 0,931 | 0,867 / 0,935 |
| D* mín. / máx. | 0,401 / 0,813 | 0,460 / 0,913 | 0,517 / 1,016 |
| Daño formado / reparado (4.ª fase progresiva) | 0,236 / 0,184 | 0,374 / 0,236 | 0,512 / 0,288 |

Programas (tablas 1–3) [E]: progresivo de 63 / 69 / 73 días; distancia rápida total 5.300 / 11.400 / 18.700 m;
fase lenta desde 11,8 m/s con pasos de 2,0 m/s, rápida a 16,0 y 13,8 m/s; *race-fit* con 800 m/semana a 16,7 m/s.
Contradicciones internas de Anwar [E]: pre-entrenamiento de 4 semanas en el texto y 3 en la tabla 3 (caso de 2
descansos/año); daño máximo 0,852 en la discusión y 0,911 en la tabla 7.

**Pan 2025** (bioRxiv), programa típico desde f_BM = 0,61 [E]: f_BM ≈ 0,85 al final de la primera preparación;
D* ≈ 0,90 al final de la primera preparación de carrera tras 280,3 km; f_BM +0,053 por 100 d de entrenamiento y
−0,131 por 100 d de descanso. Sirven como **pruebas de tendencia**, no de igualdad numérica [I].

### 1.7 Qué falta para implementar
Código de Anwar (Zenodo 19173866) o la versión JRSI de Pan (PMC12483640) para fijar dt y reproducir la tabla 4 con
tolerancia. Mientras tanto, el modelo A (Morrice-West 2022, implementado) sigue siendo el único modelo de fatiga ósea.

---

## 2. Línea base de la playa por franja (Laredo)

### 2.1 Datos de playa (solo trotones, solo trote)
| Fuente | Cifra | Etiqueta |
|---|---|---|
| Chateau et al. 2011, *EVJ Suppl* 38:488, doi 10.1111/j.2042-3306.2010.00277.x (4 trotones; acelerómetro y herradura dinamométrica) | Arena húmeda profunda frente a orilla firme (25 km/h): deceleración vertical del casco ≈ −59 %, frenado longitudinal −50 %; arena seca profunda frente a asfalto (15 km/h): −95 % y −55 %; en lo blando, zancada más corta y más frecuente (sin valores absolutos en el resumen) | [E-r] |
| Crevier-Denoix et al. 2011, *EVJ Suppl* 38:544, doi 10.1111/j.2042-3306.2010.00202.x (4 trotones, 7 m/s) | Humedad 19 % en la orilla firme frente a 13,5 % en la húmeda profunda; en la profunda bajan Fz máx. y Fx máx. y el apoyo dura más | [E-r] |

Ya estaban en la base (`playa_franjas`); el texto completo sigue bloqueado.

### 2.2 Galope de PSI sobre suelos con distinta dureza y humedad
| Fuente | Cifra | Etiqueta |
|---|---|---|
| Pfau et al. 2024, *Sensors* 24:2441, doi 10.3390/s24082441 (12 PSI, ~16,5 m/s, pista de tierra, GNSS) | Dureza 22,3–61,2 g (blanda ≤ 26, dura ≥ 61); humedad 12,1–27,4 % (seca ≤ 13, media 13–19, húmeda > 19). Duro: 2,502 Hz y 6,597 m; medio: 2,459 Hz y 6,712 m. Diferencia máxima de zancada entre condiciones **0,186 m**; +0,018 Hz y +0,359 m por m/s; efecto de la humedad no monótono | [E] |
| Bruce, Pfau et al. 2026, *BMC Vet Res*, doi 10.1186/s12917-026-05376-0 (mismos 12 PSI) | Aceleración máxima del casco +19 % en suelo medio frente a blando; caña +16 a +54 % en medio o duro; la atenuación casco–caña no cambia | [E-r] |
| Setterbo et al. 2009, *AJVR* 70:1220, doi 10.2460/ajvr.70.10.1220 (3 PSI) | Aceleración del casco al aterrizar 28,5 g (sintético) frente a 42,9 g (césped); fuerza máxima 11,5 / 13,8 / 16,1 N/kg (sintético / tierra / césped) | [E-r] |
| Crevier-Denoix et al. 2013, *Vet J* 198 S1:e124, doi 10.1016/j.tvjl.2013.09.046 (5 caballos al galope) | La deceleración máxima en el impacto **no difirió** entre césped y sintético; sí el deslizamiento, el hundimiento y las fuerzas | [E-r] |
| Crevier-Denoix et al. 2009, *Bull Acad Vét France* 162(2) (programa Sequisol; core.ac.uk/download/15524665.pdf; 3 trotones a 9,7 m/s) | Arena fibrada encerada frente a arena triturada: deceleración 1.601 frente a 3.362 m/s²; fuerza en el TFDS 6.542 frente a 7.065 N; zancada 5,15 frente a 5,23 m; el penetrómetro solo orienta | [E] |
| Crevier-Denoix et al. 2013, diapositivas AVF (qualif.avf.educagri.fr) | Pista dura sin mantener frente a regada y gradeada: velocidad de carga vertical ≈ +17 %; serie de 6 potras PSI: 2 tendinitis del TFDS y 1 osteosclerosis en el lote de pista dura, ninguna en el blando (serie de casos mínima) | [E, gráficas poco legibles] |

Lectura [I]: Pfau 2024 muestra que el suelo cambia la zancada a la misma velocidad **más que el umbral de A7
(0,10 m)**: la regla A7 solo es válida con comparables de la **misma franja**, no solo de la misma «superficie playa».
Y el pico de aceleración por sí solo no separa suelos (Crevier-Denoix 2013): hace falta también la duración del apoyo.

### 2.3 Humedad y medida del suelo
- *Racing Surfaces White Paper*, Grayson-Jockey Club 2012 (grayson-jockeyclub.org, PDF) [E]: la humedad es la variable
  más importante; la resistencia al corte y la compactación tienen un máximo a humedad intermedia (sin valor numérico);
  cambiar de superficie trabajando a máxima intensidad es un riesgo documentado. Instrumentos: Clegg de 2,25 kg (mide
  sobre todo la base), penetrómetro (corregir por suelo y humedad), Going Stick sin respaldo publicado, sonda de
  humedad TDR recomendada.
- Holt et al. 2014, *Procedia Eng* 72:949, doi 10.1016/j.proeng.2014.06.160 [E-r]: en un sintético de picadero, el
  mejor equilibrio amortiguación–apoyo con 19,1 % de humedad (no es arena de playa).
- Brilli & Stark 2024, *Coastal Eng.* (VTechWorks) [E-r]: en arena de playa parcialmente saturada el penetrómetro
  dinámico necesita corrección por velocidad de penetración.

### 2.4 Uso de la playa y lesiones
- Morrice-West et al. 2018, *Animals* 8:221, doi 10.3390/ani8120221 [E]: el 12 % de 66 entrenadores de Victoria usa
  arena firme de playa y el 9 % arena blanda; no mide lesiones.
- **No se encontró** ningún estudio biomecánico, de FC ni de lesiones con caballos de carreras galopando en playa
  (Deauville, Pornichet, Cagnes, Laytown, Reino Unido) [NV].
- Árabes: solo Porzio et al. 2025, *Vet Sci* 12:1028, doi 10.3390/vetsci12111028 [E, parcial], caballos de **raid** en
  arena profunda del desierto (1,77 Hz y 3,14 m a 20 km/h): solo referencia, no población de AVO.

### 2.5 Especificación de la línea base de playa (no implementada)
| # | Propuesta | Base |
|---|---|---|
| PL1 | `superficie` de playa con **franja** obligatoria: orilla firme, húmeda profunda, seca profunda, transición; las comparables de A7/A8/A9 son de la misma franja | Diferencias de impacto y zancada [E-r]/[E]; uso como criterio [I] |
| PL2 | Registrar con cada sesión: hora respecto a la bajamar, lluvia 24–48 h, nota del jinete y, si se puede, 3–5 lecturas de humedad (TDR) y penetrómetro por franja del mismo operador; cortes provisionales de humedad ≤ 13 / 13–19 / > 19 % (Pfau 2024) | Instrumentos [E]; protocolo [I] |
| PL3 | Zancada y frecuencia con la velocidad como covariable (+0,359 m y +0,018 Hz por m/s en tierra) y franja como efecto fijo; sin comparar con la pista | [E] Pfau 2024; modelo [I] |
| PL4 | Umbrales de impacto de la cincha relativos a la franja; la orilla firme es la que más se parece a la pista y la seca profunda se trata como trabajo de fuerza | [E-r] Chateau 2011; [I] |
| PL5 | Relación FC–velocidad (V200) por franja, con 4–6 sesiones por caballo y franja antes de usarla; nunca mezclar playa profunda con orilla | Sin datos publicados [NV]; [I] |
| PL6 | Marcar trabajos rápidos en orilla muy compactada y cambios bruscos de franja durante un galope; guardar lesiones con la franja para un registro propio | [E] White Paper 2012; [I] |

---

## Resumen
- **Modelo óseo B:** signo de b **cerrado**: b = −0,02 con S_v = a·√(1 − f)·[1 − b(1 − f)] (Anwar 2026, tabla 9, y
  Hitchens 2018 [E]); la base tenía +0,02 y se corrige. **f_BM(0) = 0,61** para un caballo sin entrenar (Pan 2025 [E]).
  El paso y el método de integración **no se publican** y la tabla 4 no se puede reproducir sin el código de Zenodo
  (bloqueado): el modelo B sigue PENDIENTE, con pruebas de tendencia ya identificadas (Pan: f_BM ≈ 0,85 tras la
  primera preparación).
- **Playa:** solo hay datos de playa de trotones al trote; en PSI al galope, el suelo cambia la zancada hasta 0,186 m a
  la misma velocidad (Pfau 2024 [E]), más que el umbral de A7. Se proponen PL1–PL6: comparables por franja, registro de
  marea, lluvia y humedad, y V200 por franja. No hay datos publicados de galope de carreras ni de lesiones en playa.
- **Motor:** sin cambios de lógica; KB 1.8.0 y motor 2.0.0-dev10 solo por versión. Nada verificado con caballos reales.
