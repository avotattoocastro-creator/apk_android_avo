# Estudio extra 4 (19/11/2026) — Auditoría de fuentes del motor, índice tendinoso en árabes y V200/VHRmax con trotones

**Inicio:** 20:21 UTC (`date -u`) · **Cierre previsto:** antes de 21:51 UTC · **Autor:** Claude (tarea programada, sin
supervisión) · **Base:** KB-1 1.6.0 → **1.7.0** · **Motor:** 2.0.0-dev8 → **2.0.0-dev9** (solo versiones).

Etiquetas: **[E]** dato leído en el texto completo o en una fuente oficial · **[E-r]** dato leído solo en el resumen,
agregador o acta · **[I]** inferencia o cálculo propio · **[I-raza]** dato de otra raza usado solo como método, con la
justificación de la transferencia · **[NV]** sin verificar. Tipo de acceso: TEXTO_COMPLETO, RESUMEN, AGREGADOR, CONGRESO,
PREPRINT, COMERCIAL, PRENSA u OFICIAL.

## Decisiones tomadas sin supervisión
1. **Rama** `claude/kb-estudio4-2026-11-19` desde `claude/kb-estudio3-2026-11-19` (PR #85 abierto).
2. **Auditoría:** 8 fuentes que sostienen parámetros o reglas del motor y que solo se conocían por resumen o MadBarn:
   Martig 2013 (σ0), Morrice-West 2025 (A4, `KB_FATIGA_OSEA_7D`), Estberg 1996 y 1998 (A3, P5), Carrier 1998 (A5),
   Vermeulen & Evans 2006 y Gramkow & Evans 2006 (A9, `vhrmax_psi_corte_m_s`), Frick 2019 (`ecg_prematuro`) y Perkins
   2005 (índice tendinoso). Trabajo en paralelo con cuatro subagentes (dos de auditoría, uno de V200, uno de tendón).
3. **Temas nuevos:** (a) índice tendinoso con árabes del Golfo y de Turquía y comparativa con trotones; (b) V200/VHRmax
   con trotones (Leleu, Couroucé, SLU) como [I-raza]. La línea base de la playa queda para otro estudio (sin tiempo).
4. **Fuente descartada por legalidad:** un subagente leyó el capítulo de Couroucé-Malblanc & van Erck-Westergren
   («Exercise testing in the field», *Equine Sports Medicine and Surgery*, Elsevier) en veteriankey.com, que parece una
   copia no autorizada de un libro comercial. **No se usa ninguna cifra de esa lectura**; el capítulo pasa a la cola
   (libro original, COMERCIAL).
5. **Motor:** ninguna evidencia queda cerrada en texto completo para implementar un pendiente (solo Perkins 2005 y
   Çalışkan 2020 llegan a texto completo, y no dan un umbral de árabes). Se suben `KNOWLEDGE_VERSION` y `ENGINE_VERSION`
   para que el análisis declare la base revisada, sin cambios de lógica, como en el estudio extra 3.
6. **Correcciones** de redacción y de ámbito de cuatro fuentes (abajo): no cambian ninguna constante implementada, pero sí
   la nota de σ0 y la definición propuesta de A4 (PENDIENTE).

## Limitaciones de acceso (comunes a todas las búsquedas)
El proxy de la sesión rechazó las llamadas directas a las API de Europe PMC, OpenAlex, Unpaywall, Crossref y Semantic
Scholar (403 o conexión rechazada). PMC y PubMed devolvieron reCAPTCHA; DUMAS/HAL, ZORA y otros, comprobación antibots
(Anubis); ScienceDirect, Wiley/BEVA y ResearchGate rechazaron la lectura. **No se esquivó ningún bloqueo** (ni curl, ni
caché, ni espejos), y no se usó Sci-Hub ni LibGen. Por eso varias fuentes siguen en RESUMEN/AGREGADOR aunque el texto
completo exista (p. ej. Frick 2019 en PMC6335521).

---

## 1. Auditoría de fuentes

### 1.1 Martig et al. 2013 — σ0 = 134,2 MPa (`sigma0_mpa`, `curva_sn`)
Martig S, Lee PVS, Anderson GA, Whitton RC. *Bone* 2013;57(2):392–398. doi 10.1016/j.bone.2013.09.006, PMID 24063945.
Australia (Melbourne), inglés, PSI. **Acceso: AGREGADOR** (resumen en MadBarn) + texto completo que la cita (Morrice-West
2022, *Sci Rep*, ecuaciones 4 y 5).
- Ensayo de compresión cíclica *ex vivo* del hueso subcondral del cóndilo del MC3 a 54, 66, 78 y 90 MPa; medianas de
  ciclos hasta el fallo 223.603, 69.908, 13.204 y 4.001 [E-r].
- **Dos curvas** [E-r]: con todas las muestras σ = 112,2 − 9,6·log10(Nf), R² 0,52; **excluyendo los 3 caballos con más
  lesión subcondral** σ = 134,2 − 14,1·log10(Nf), R² 0,72 (p < 0,001). E₀ = 2.500 ± 494 MPa (n = 22).
- **Confirmación (sin cambio):** nuestra fórmula es algebraicamente correcta y es la que usa Morrice-West 2022; la nota
  de KB 1.2.0 ya decía que 134,2/14,1 excluye a los 3 caballos con lesión. Se precisa que es el caso **menos
  conservador** y que 112,2/9,6 es la alternativa para hueso con lesión previa [E-r]. Los 54–90 MPa son los niveles del ensayo; 90 MPa
  en el modelo es una carga de escalado supuesta [E, Morrice-West 2022].
- El valor implementado no cambia (σ0 134,2). Sin verificar: n total, frecuencia del ensayo y criterio de fallo [NV].
- Relacionado: Martig et al. 2014, *Equine Vet J* (revisión «Bone fatigue and its implications for injuries in
  racehorses», doi 10.1111/evj.12241, PMID 24528139): Wiley bloqueado. La tesis de S. Martig no aparece en minerva-access.

### 1.2 Morrice-West et al. 2025 — fatiga ósea acumulada (A4, `KB_FATIGA_OSEA_7D`)
Morrice-West AV, Wong ASM, Hitchens PL, Whitton RC. *Vet J* 2025;314:106502. doi 10.1016/j.tvjl.2025.106502,
PMID 41271082. **Acceso: AGREGADOR** (MadBarn).
- **Corrección de país: Tasmania**, no Victoria: 405 caballos, 3.168 salidas (2011–2016), 71 primeras lesiones
  musculoesqueléticas [E-r].
- **Son HR** (modelos de Cox), no OR [E-r]: una salida HR 3,37 (IC 95 % 1,01–11,22; p = 0,048); carrera deportiva HR
  1,80 (1,53–2,11). Coinciden con nuestras cifras, pero el IC de 3,37 es muy amplio.
- **Corrección importante para A4:** «carga baja ×2,89» y «alta ×8,51» frente a media no son un recuento de trabajos
  rápidos en 28 d, sino la **fatiga ósea acumulada en las 4 salidas previas**: baja < 0,25, media 0,25–0,75, alta
  ≥ 0,75 [E-r]. El resumen no aclara la unidad (fracción de vida a fatiga o cuantil) [NV]. Tiempo medio restringido sin
  lesión: 760 d (baja), 1.027 d (media), 405 d (alta) [E-r].
- Consecuencia: la regla A4 («< 2 sesiones rápidas en 28 d») es **[I]** en su forma, inspirada en la dirección del
  resultado, no una traslación del corte. Queda PENDIENTE hasta leer el texto completo.

### 1.3 Estberg et al. 1996 y 1998 — rampa de carga (A3, P5)
- **Estberg 1996:** Estberg L, Stover SM, Gardner IA, Drake CM, Johnson B, Ardans A. *Am J Vet Res* 57(11):1549–1555,
  doi 10.2460/ajvr.1996.57.11.1549, PMID 8915427. California, 64 casos (1991), un control por carrera. **Acceso:
  RESUMEN.** 35 frente a 25 furlongs de carrera + trabajo cronometrado en 2 meses → riesgo **3,9 veces (IC 2,1–7,1)**;
  0,6 frente a 0,5 furlong/día de media en 2 meses → 1,8 (1,4–2,6) [E-r].
- **Corrección de redacción:** «+40 % en 60 d → OR 3,9» cuadra (35/25 = 1,4), pero es una comparación de **valores
  absolutos entre caballos**, no un aumento relativo del mismo caballo. A3 (rampa propia) sigue siendo [I] en su forma.
  No hay umbral de velocidad: son trabajos oficiales cronometrados.
- **Estberg 1998:** *Prev Vet Med* 33:159–170, doi 10.1016/S0167-5877(97)00047-0, PMID 9500171. **Acceso: AGREGADOR.**
  Caso-cruzado con ventana de 60 d; expuesta si la tasa diaria de distancia a alta velocidad > P75; riesgo en los 30 d
  siguientes: lesión catastrófica **RR 4,2 (3,0–5,8)** (214 casos; 39 % en periodo de riesgo frente a 22 % de tiempo
  expuesto) y RR 4,8 (2,9–8,1) de baja ≥ 60 d [E-r]. Coincide.

### 1.4 Carrier et al. 1998 — vuelta tras descanso (A5, P4)
Carrier TK, Estberg L, Stover SM, Gardner IA, Johnson BJ, Read DH, Ardans AA. *JAVMA* 212(10):1582–1587, PMID 9604029.
California. **Acceso: AGREGADOR.** DOI **no confirmado** (no se usa uno supuesto).
- RR **71** (10 d) y **45** (21 d) tras ≥ 2 meses sin trabajos rápidos oficiales [E-r]: coincide.
- **Corrección de ámbito:** el RR es **solo para fractura de húmero**. Las de pelvis se asociaron a otros factores
  (hembras, más edad, ninguna baja o dos o más) [E-r]. A5 sigue siendo útil, pero su texto debe decir «húmero».

### 1.5 Vermeulen & Evans 2006 — método V200/VHRmax (A9)
Vermeulen AD, Evans DL. *Equine Vet J Suppl* 2006;(36):113–117. doi 10.1111/j.2042-3306.2006.tb05525.x, **PMID
17402404**. Australia (Sídney). **Acceso: RESUMEN**; además CONGRESO (Proc. Aust. Equine Sci. Symp. 2006) y PRENSA
(TheHorse.com, AAEP 2005).
- Medias de 5 s de velocidad y FC; regresión con trote y galope; fiabilidad en 12 PSI de 3–5 años; efecto del
  entrenamiento en 12 potros de 2 años (semanas 2 y 6): VHRmax y V200 suben (P < 0,01), HRmax no [E-r].
- **Correcciones:** el resumen dice «**diferencias medias** de 2 % o menos» entre días, no «CV ≤ 2 %». El «+8 % de
  VHRmax» procede **solo de la crónica de prensa de la AAEP 2005** (n = 10), no del artículo [PRENSA].
- Siguen sin verificar: rango de velocidades, R² y retraso de FC (texto de pago).

### 1.6 Gramkow & Evans 2006 — corte de VHRmax 14,5 m/s
Gramkow HL, Evans DL. *Equine Vet J Suppl* 2006;(36):118–122. doi 10.1111/j.2042-3306.2006.tb05526.x, PMID 17402405.
Australia. **Acceso: AGREGADOR / RESUMEN** (y resumen del simposio australiano 2006).
- Coinciden n = 25, r = 0,41 (P < 0,05) y VHRmax < 14,5 m/s → < 2.500 AUD por salida [E-r].
- **Matices:** la variable es la **raíz cuadrada de las ganancias máximas por salida**; galopes de prueba a 15–16 m/s;
  un solo entrenador; ≥ 6 salidas; sin correlación con HRmax ni Vmax [E-r]. (Algunas bases la fechan en 2007.)

### 1.7 Frick et al. 2019 — variación RR (A11, `ecg_prematuro`)
Frick L, Schwarzwald CC, Mitchell KJ. *J Vet Intern Med* 2019;33(1):212–224. doi 10.1111/jvim.15358, PMID 30520119,
**PMCID PMC6335521**. Suiza (Zúrich). Texto completo abierto (CC BY-NC) en PMC y BORIS, **bloqueado para la sesión**
(reCAPTCHA/antibots); **acceso conseguido: RESUMEN** (MEDLINE/DOAJ).
- n = 54 (13 sanos, 30 con arritmias, 11 de bajo rendimiento sin arritmias) [E-r].
- Sanos: −4,4 a +3,8 % al trote y **−6,1 a +5,4 % en la fase de canter de la prueba en cinta (HSET)** [E-r].
  **Corrección:** «canter en cinta», no «galope en pista».
- Recuperación: corte del **6 %** de acortamiento máximo del RR: **sensibilidad 88 %, especificidad 97 %, LR 26** [E-r].
  Refuerza el umbral 5–6 % de `ecg_prematuro`. El umbral para la fase de ejercicio no está en el resumen [NV].

### 1.8 Perkins, Reid & Morris 2005 — TFDS en Nueva Zelanda (índice tendinoso)
*N Z Vet J* 53(3):184–192, **doi 10.1080/00480169.2005.36503** (confirmado). Nueva Zelanda. **Acceso: TEXTO_COMPLETO**
equivalente: capítulo 8 (pp. 195–220) de la tesis doctoral de N. R. Perkins (Massey 2005, repositorio oficial MRO,
https://mro.massey.ac.nz/handle/10179/1580), con nota «Published as… N Z Vet J 53(3), 184–192».
- 1.571 caballos, 554.745 días; 51 TFDS y 48 del aparato suspensor (p. 203) [E].
- TFDS frente a 2 años (tabla 8.4): 4 años **IRR 6,76 (2,39–19,10)**; ≥ 5 años **IRR 15,26 (5,83–39,97)**; p < 0,001
  [E]. Suspensor (tabla 8.5): 2,91 (1,16–7,28) y 3,54 (1,45–8,64) [E].
- **Precisión:** la variable sin asociación es la **distancia corrida en carrera** en los 30 d previos (subconjunto con
  salidas; p = 0,4), no la distancia de entrenamiento [E]. Machos: TFDS IRR 1,74 (p = 0,09); más riesgo en
  preparaciones sin salidas [E].

### 1.9 Resultado de la auditoría

| Fuente | Antes | Ahora | ¿Cambia la cifra? | Qué sostiene |
|---|---|---|---|---|
| Martig 2013 | AGREGADOR | AGREGADOR (+ cita en texto completo) | No; confirmada (curva sin lesión, R² 0,72; alternativa 112,2/9,6, R² 0,52, ya documentada) | σ0, curva S-N |
| Morrice-West 2025 | AGREGADOR | AGREGADOR | Sí, de ámbito: **Tasmania**, **HR**, carga = fatiga ósea en 4 salidas (< 0,25 / ≥ 0,75) | A4 (PENDIENTE), fatiga 7 d |
| Estberg 1996 | AGREGADOR | RESUMEN | No; redacción: 35 frente a 25 furlongs (IC 2,1–7,1) | A3 |
| Estberg 1998 | cita de segunda mano | AGREGADOR | No (RR 4,2; 3,0–5,8) | P5 |
| Carrier 1998 | AGREGADOR | AGREGADOR | Sí, de ámbito: **solo húmero** | A5, P4 |
| Vermeulen & Evans 2006 | ResearchGate (ficha) | RESUMEN + CONGRESO + PRENSA | Sí: «diferencia media ≤ 2 %» (no CV); +8 % solo de prensa; PMID 17402404 | A9 |
| Gramkow & Evans 2006 | AGREGADOR | AGREGADOR | No; variable = √ganancias máximas por salida | `vhrmax_psi_corte_m_s` |
| Frick 2019 | AGREGADOR | RESUMEN (texto completo en PMC, bloqueado) | Matiz: canter en cinta; corte 6 % con S 88 %, E 97 %, LR 26 | `ecg_prematuro`, A11 |
| Perkins 2005 | AGREGADOR | **TEXTO_COMPLETO** (tesis Massey) | Matiz: distancia **en carrera**; IC añadidos | índice tendinoso |

**Fuentes mejoradas: 6 de 9** (Perkins a texto completo; Estberg 1996, Estberg 1998, Vermeulen, Frick y Martig con
acceso o ámbito confirmados y cifras cotejadas). Siguen bloqueadas y van a la cola: textos completos de Martig 2013,
Morrice-West 2025, Estberg 1998, Vermeulen 2006, Gramkow 2006, Frick 2019 (PMC desde un navegador) y el DOI de Carrier.

---

## 2. Índice tendinoso: árabes de carreras (Golfo, Turquía, Polonia) y comparativa con trotones

### 2.1 Árabes de carreras (datos propios de la raza)
- **Çalışkan GÜ, Seyrek-İntaş D, Çelimli N 2020a**, *J Res Vet Med* 39(1):34–44, doi 10.30782/jrvm.606021. Turquía,
  turco, PSI 62 y **árabes 56**. **TEXTO_COMPLETO** (DergiPark; se leyó la prosa, no todas las celdas de tablas):
  árabes con tendinitis 53/58 (91,4 %) y peritendinitis 5/58; PSI tendinitis 49/62 (79,0 %); diferencia entre razas
  p > 0,05 [E]. La tendinitis se concentra a los **3 años (27,5 %) y 4 años (30,0 %)**; árabes de 4 años 19/53 (35,8 %)
  [E]. 71,4 % de los árabes lesionados < 400 kg; sexo, altura y peso no significativos [E]. Sin OR ni CSA.
- **Çalışkan et al. 2020b**, *J Res Vet Med* 39(2):115–127, doi 10.30782/jrvm.606025 (misma cohorte: Veliefendi, Bursa,
  İzmir, Ankara, Adana). **TEXTO_COMPLETO.** Carga en los 3 meses previos: carreras 3,4 ± 2,9 (tendinitis) frente a
  2,6 ± 2,7 (peritendinitis); distancia 5.460,8 ± 4.562,7 m frente a 4.461,1 m; **sin asociación con la aparición**
  (p > 0,05) pero **correlación con la gravedad** (carreras rs 0,225; distancia rs 0,190; p < 0,05) [E]. Superficie:
  césped 42,5 %, arena 31,7 %, sin efecto significativo (todo el entrenamiento es en arena) [E]. Sin análisis por raza.
- **Çelimli N, tesis doctoral (Uludağ, 2000)**, YÖK Açık Bilim, handle 20.500.12812/693887. **RESUMEN.** 62 árabes
  (1–3, 4–6 y ≥ 7 años) y 15 PSI: **CSA del TFDS en árabes 62,1 ± 3,2 a 93,9 ± 3,8 mm²** (rango de medias entre grupos;
  sin asignar por edad en el resumen) [E-r]. Versión publicada: Çelimli, Seyrek-İntaş & Kaya 2004, *Equine Vet Educ*
  16(2):81–85, doi 10.1111/j.2042-3292.2004.tb00271.x (COMERCIAL, no leída). **Es la única línea base de CSA árabe.**
- **Pieszka M, Łuszczyński J, Baranowska A 2011**, *Iranian J Appl Anim Sci* 1(1):69–71. Polonia (Służewiec 2000–2008).
  **RESUMEN.** 4.042 PSI y 2.553 árabes; con lesión de extremidad 94 PSI y 32 árabes; más frecuente en PSI y en machos
  [E-r]. Cálculo propio ≈ 2,3 % frente a 1,3 % [I]. No separa el TFDS.
- **Pap MM 2026**, póster #59, 24.º ICRAV (Qatar Racing and Equestrian Club, Doha). **CONGRESO.** 46 % árabes y 54 % PSI;
  perfil de riesgo similar entre razas; más afectados 3–4 años; anterior derecha 52 %; los tendones son el 40 % de los
  caballos que no vuelven a correr [E-r]. **Única fuente del Golfo** encontrada; sin cifras del TFDS por raza.
- *Bulgarian J Vet Med* 2022 (tendón y rendimiento posterior en PSI y árabes; autoría no confirmada): engrosamiento del
  tendón → peor rendimiento (p = 0,01) y menos ganancias (p = 0,02) [AGREGADOR, E-r]; sin n.
- Dallas et al. 2013, *EVJ* 45(S44), doi 10.1111/evj.12145_23 (árabes de carreras, Reino Unido): solo título, bloqueado.

### 2.2 Trotones y otras razas [I-raza]
- **Bertuglia A et al. 2014**, *BMC Vet Res* 10:11, doi 10.1186/1746-6148-10-11. Italia, 356 **trotones**.
  TEXTO_COMPLETO: TFDS 0,84 lesiones/100 caballos-mes; suspensor + TFDS 38,3 % de todas las lesiones; la edad **no** fue
  factor; más carreras al año fue **protector** (p < 0,001) [E]. *Transferencia:* solo la dirección de «poca actividad →
  más riesgo» (coincide con A6B en PSI); la marcha y la carga del trote son distintas, así que no hay magnitud.
- **Crevier-Denoix N et al. 2017**, *AJVR* 78(11):1293–1304, doi 10.2460/ajvr.78.11.1293. Francia, **trotón francés**.
  RESUMEN: pista dura 3/6 con tendinopatía del TFDS en 4 meses frente a 0/6 en blanda [E-r]. *Transferencia:* dirección
  del factor «firmeza del suelo» (la mecánica del tendón a la carga es común); n muy pequeña.
- Dabbene et al. 2018 (*EVJ*, trotones, interferencias): mecanismo propio del trote, **no transferible**.
- **Secchi V et al. 2021**, *Animals* 11(3):795 (Italia, 20 **anglo-árabes** de carreras con TFDS): solo método de
  elastografía, sin riesgo [E].
- **PSI de Japón y Turquía:** Iimori M et al. 2022, *J Vet Med Sci* 84(2):261–265 (TEXTO_COMPLETO, 354 PSI): lesión
  grave posterior 25,7 % con CSA anormal, 28,3 % con CSA normal + edema peritendinoso, 4,9 % en controles; umbrales de
  CSA anormal por zona 1,20–1,46 cm²; mediana 140 d hasta la recaída [E]. Arıcan M et al. 2008, *Vet Bil Derg*
  24(2):19–26 (PSI): CSA zona 2 sanos 0,869 ± 0,453 cm² frente a tendinitis 0,625 ± 0,181 (n.s.) [E]. Oikawa &
  Kasashima 2002, *J Equine Sci* 13:41 (JRA): 1.100–1.200 tendinitis por 6.400–7.000 caballos [E-r].

### 2.3 Consecuencia para `TENDON_INDICE_HEURISTICO`
- **Sigue sin existir ninguna OR/IRR del TFDS en árabes** (Golfo, Turquía, Polonia, Francia, Reino Unido). El índice se
  mantiene **cualitativo y PENDIENTE**.
- Edad 3–4 años en árabes: ahora con **tres** fuentes coherentes (Yıldırım & Karaarslan 2025, Çalışkan 2020a texto
  completo, Pap 2026 Doha) [E/E-r].
- Carga acumulada de carreras: en árabes y PSI turcos se asocia a la **gravedad**, no a la aparición (Çalışkan 2020b) [E];
  en PSI neozelandeses la distancia en carrera de 30 d no se asocia (Perkins 2005) [E]. → No añadir un término de carga
  al índice; mantener reentrada y poco galope (A6/A6B) como en PSI.
- CSA ecográfica: si la cuadra registra ecografías de árabes, comparar con 62–94 mm² (Çelimli) [E-r] y el cambio
  relativo ≥ +10 % en 2 meses (Beaumont 2025) [E-r, trotón]; los umbrales absolutos japoneses (1,20–1,46 cm²) son de PSI
  y **no** se aplican al árabe [I].
- Firmeza del suelo: dirección [I-raza] de trotones (Crevier-Denoix 2017) y [E-r] de PSI (Ikeda 2019, pista
  encharcada); sin dato árabe.

---

## 3. V200 / VHRmax: trotones como método y PSI/árabes de otras regiones

### 3.1 Trotones [I-raza]
*Transferencia común:* la regresión FC–velocidad es un método cardiovascular independiente de la marcha; los **protocolos,
la variación con edad y entrenamiento y la sensibilidad al sobreentrenamiento** se trasladan; los **valores absolutos no**.
- **Leleu C, Cotrel C, Couroucé-Malblanc A 2005**, *Vet Rec* 156:339–342, doi 10.1136/vr.156.11.339. Francia, 223
  trotones; prueba de campo de 3 escalones; V4 y V200 asociadas a edad y nivel (P < 0,05), más a los 3–4 años [E-r].
- **Couroucé A, Chrétien M, Valette JP 2002**, *EVJ* 34:91–97, doi 10.2746/042516402776181141: 194 caballos, 1.105
  pruebas en 6 años; V200 aumenta con la edad y el entrenamiento [E-r, sin cifras].
- **Couroucé A et al. 2000**, *EVJ Suppl* 30:528–532: 3 × 3 min a 490/560/630 m/min; **sin diferencias entre pistas**;
  en cinta FC y lactato menores [E-r]. → No mezclar sesiones de cinta con pista en la línea base de V200 [I-raza].
- **Couroucé A 1999**, *Vet J* 157:112–122, doi 10.1053/tvjl.1998.0302: V200 «próxima a V4» en adultos [E-r].
- **Hamlin MJ, Shearman JP, Hopkins WG 2002**, *EVJ* 34:383–388, doi 10.2746/042516402776249146. Nueva Zelanda,
  trotones, 8 semanas de sobrecarga: últimos 1.200 m +4,0 % (IC 1,7–5,8), velocidad pico −6,9 % (4,7–8,9); **la V200
  bajó** (sin cifra en el resumen); sin cambio claro de FCmax ni de recuperación [E-r]. *Transferencia:* única prueba
  directa de que la V200 detecta pérdida de forma por sobrecarga (escenario de A9).
- **Ringmark S et al. 2015**, *Acta Vet Scand* 57:17, doi 10.1186/s13028-015-0107-1 (SLU, Suecia): reducir un 30 % la
  distancia de alta intensidad no cambió VLa4 pero sí la **FC de recuperación** (menor recuperación a 2 meses, P < 0,05)
  [E-r]. Ringmark 2013, *Animal* 7:746: FC post-ejercicio 81 → 73 lpm (RMSE 8) [E-r]. *Transferencia:* la recuperación de
  FC puede ser más sensible a la carga que el umbral de lactato.
- Leleu C, AVEF 2022 (IVIS, CONGRESO, francés): V4 y V200 máximas en el pico de forma y bajan con desentrenamiento o
  sobreentrenamiento (cualitativo) [E-r].

### 3.2 PSI y árabes de otras regiones
- **Lee YW et al. 2019**, *J Vet Clin* 36(1):62–67, doi 10.17555/jvc.2019.02.36.1.62. **Corea**, coreano, PSI 2–6 años,
  n = 11. RESUMEN + texto de la tesis de Lee YW (Jeju; año no confirmado): V200 **49,3 ± 4,3 km/h** (13,7 m/s), VHRmax
  **57,4 ± 7,1 km/h** (15,9 m/s), FCmax 214 ± 11 lpm (tabla 9) [E; conversión a m/s, I]. Clase alta frente a baja: V200
  50,6 frente a 47,8 km/h (p = 0,52), VHRmax 59,5 frente a 54,8 (p = 0,17) [E]. Método: descartar < 10 km/h y FC > 12 lpm
  sobre la tendencia; sesión trote 1.000 m + canter 900 m + galope 950 m [E].
- **Alonso JM et al. 2013**, *Ciência Rural* 43(4):722–728 (Redalyc). **Brasil**, portugués, **árabes** y criollos en
  cinta. TEXTO_COMPLETO: V200 de árabes 7,4 ± 0,5 → 7,8 ± 0,8 m/s tras el entrenamiento (+5 %); FC pico 221,6 → 226,0 lpm
  [E]. Es dato de raza árabe, pero **en cinta** (no comparable en valor absoluto con pista).
- **Fonseca RG, Kenny DA, Hill EW, Katz LM 2011**, *EVJ Suppl* 38:51–57, doi 10.1111/j.2042-3306.2010.00272.x. Irlanda,
  102 PSI, GPS + FC en entrenamiento rutinario: «ningún parámetro de velocidad cambió claramente con el entrenamiento»
  (incluye V200 y VHRmax) [E-r]. **Aviso para A9:** con datos de rutina el ruido puede tapar la señal.
- **Mukai K et al. 2007**, *J Equine Sci* 18:153–160, doi 10.1294/jes.18.153 (Japón): FC pico en carrera 213,6 ±
  1,7 lpm; 95 % del pico en **12,4 ± 1,8 s** a 15,9 m/s [E-r]. Apoya descartar los primeros 20–30 s de cada meseta.
  Mukai 2007, *EVJ Suppl* 36:210: 10 semanas de desentrenamiento bajan VO2max, gasto cardíaco y volumen sistólico [E-r].
- Foreman JH et al. 1990, *AJVR* 51:914: 5 semanas de desentrenamiento cambian la FC de recuperación a 40 y 60 min [E-r].
- Polonia (Janczarek, Kędzierski 2016): árabes de carreras con VFC y FC en reposo, **sin V200** [E-r].

### 3.3 Consecuencia para A9
- **No existe ningún TE/CV publicado de V200 en PSI ni en árabes** leído en texto legal. La única cifra de
  repetibilidad encontrada (r 0,88 entre días) procede de la copia descartada (decisión 4) y **no se usa**.
- La señal de entrenamiento publicada es +5 % (árabes en cinta, Alonso 2013 [E]) y P < 0,01 en potros de 2 años
  (Vermeulen [E-r]); en PSI adultos con datos de rutina puede no verse (Fonseca 2011 [E-r]).
- Se mantiene `max(√2·TE, SWC)` con **TE propio del caballo** (≥ 3 sesiones en una semana, como Poinsard 2026), mismas
  condiciones (pista, no cinta; jinete; temperatura) y ≥ 2 sesiones [I]. A9 sigue PENDIENTE (falta el ECG en el análisis).

---

## 4. Tabla de fuentes

| Cita | DOI / URL | País | Idioma | Raza | Acceso | Qué cifra sostiene |
|---|---|---|---|---|---|---|
| Martig 2013, Bone 57:392 | 10.1016/j.bone.2013.09.006 | Australia | en | PSI | AGREGADOR | σ0 134,2/14,1 (sin lesión, R² 0,72); 112,2/9,6 (R² 0,52) |
| Morrice-West 2025, Vet J 314:106502 | 10.1016/j.tvjl.2025.106502 | Australia (Tasmania) | en | PSI | AGREGADOR | HR 3,37 / 1,80; ×2,89 baja, ×8,51 alta (fatiga 4 salidas) |
| Estberg 1996, AJVR 57:1549 | 10.2460/ajvr.1996.57.11.1549 | EE. UU. | en | PSI | RESUMEN | 3,9 (2,1–7,1), 35 vs 25 furlongs |
| Estberg 1998, Prev Vet Med 33:159 | 10.1016/S0167-5877(97)00047-0 | EE. UU. | en | PSI | AGREGADOR | RR 4,2 (3,0–5,8) > P75 |
| Carrier 1998, JAVMA 212:1582 | PMID 9604029 | EE. UU. | en | PSI | AGREGADOR | RR 71 / 45, solo húmero |
| Vermeulen & Evans 2006 | 10.1111/j.2042-3306.2006.tb05525.x | Australia | en | PSI | RESUMEN | medias de 5 s; diferencia media ≤ 2 % |
| Gramkow & Evans 2006 | 10.1111/j.2042-3306.2006.tb05526.x | Australia | en | PSI | AGREGADOR | VHRmax < 14,5 m/s; r 0,41 |
| Frick 2019, JVIM 33:212 | 10.1111/jvim.15358 (PMC6335521) | Suiza | en | caballos de clínica, raza no verificada [NV] | RESUMEN | −6,1/+5,4 % canter; corte 6 % (S 88, E 97) |
| Perkins 2005, NZVJ 53:184 | 10.1080/00480169.2005.36503; mro.massey.ac.nz/handle/10179/1580 | Nueva Zelanda | en | PSI | TEXTO_COMPLETO | IRR 6,76 / 15,26 |
| Çalışkan 2020a, J Res Vet Med 39:34 | 10.30782/jrvm.606021 | Turquía | tr | árabe + PSI | TEXTO_COMPLETO | 91,4 % tendinitis árabes; 3–4 años |
| Çalışkan 2020b, J Res Vet Med 39:115 | 10.30782/jrvm.606025 | Turquía | tr | árabe + PSI | TEXTO_COMPLETO | carga → gravedad, no aparición |
| Çelimli 2000, tesis Uludağ | YÖK 20.500.12812/693887 | Turquía | tr | árabe | RESUMEN | CSA TFDS 62–94 mm² |
| Pieszka 2011, Iran J Appl Anim Sci 1:69 | — | Polonia | en | árabe + PSI | RESUMEN | lesiones de extremidad 32/2.553 árabes |
| Pap 2026, ICRAV póster 59 | — | Qatar | en | árabe + PSI | CONGRESO | 3–4 años; tendón 40 % de retiradas |
| Bertuglia 2014, BMC Vet Res 10:11 | 10.1186/1746-6148-10-11 | Italia | en | trotón [I-raza] | TEXTO_COMPLETO | 0,84/100 caballos-mes; actividad protectora |
| Crevier-Denoix 2017, AJVR 78:1293 | 10.2460/ajvr.78.11.1293 | Francia | en | trotón francés [I-raza] | RESUMEN | pista dura 3/6 vs 0/6 |
| Secchi 2021, Animals 11:795 | 10.3390/ani11030795 | Italia | en | anglo-árabe [I-raza] | TEXTO_COMPLETO | solo método (elastografía) |
| Iimori 2022, J Vet Med Sci 84:261 | jstage (J Vet Med Sci) | Japón | en | PSI | TEXTO_COMPLETO | CSA anormal 1,20–1,46 cm² |
| Arıcan 2008, Vet Bil Derg 24:19 | DergiPark | Turquía | tr | PSI | TEXTO_COMPLETO | CSA zona 2 0,869 / 0,625 cm² |
| Oikawa & Kasashima 2002, J Equine Sci 13:41 | 10.1294/jes.13.41 | Japón | en | PSI | RESUMEN | 1.100–1.200 tendinitis/año en JRA |
| Leleu 2005, Vet Rec 156:339 | 10.1136/vr.156.11.339 | Francia | en | trotón francés [I-raza] | RESUMEN | V200 y edad/nivel |
| Couroucé 2002, EVJ 34:91 | 10.2746/042516402776181141 | Francia | en | trotón francés [I-raza] | RESUMEN | V200 con edad y entrenamiento |
| Couroucé 2000, EVJ Suppl 30:528 | 10.1111/j.2042-3306.1999.tb05278.x | Francia | en | trotón francés [I-raza] | RESUMEN | pistas intercambiables; cinta ≠ pista |
| Couroucé 1999, Vet J 157:112 | 10.1053/tvjl.1998.0302 | Francia | en | trotón francés [I-raza] | RESUMEN | V200 ≈ V4 |
| Hamlin 2002, EVJ 34:383 | 10.2746/042516402776249146 | Nueva Zelanda | en | Standardbred [I-raza] | RESUMEN | V200 baja con sobrecarga |
| Ringmark 2015, Acta Vet Scand 57:17 | 10.1186/s13028-015-0107-1 | Suecia | en | Standardbred sueco [I-raza] | RESUMEN | recuperación FC sensible a la carga |
| Lee 2019, J Vet Clin 36:62 | 10.17555/jvc.2019.02.36.1.62 | Corea | ko | PSI | RESUMEN + tesis | V200 49,3 km/h; VHRmax 57,4 km/h |
| Alonso 2013, Ciência Rural 43:722 | Redalyc | Brasil | pt | árabe (cinta) | TEXTO_COMPLETO | V200 +5 % con entrenamiento |
| Fonseca 2011, EVJ Suppl 38:51 | 10.1111/j.2042-3306.2010.00272.x | Irlanda | en | PSI | RESUMEN | V200/VHRmax no cambian en rutina |
| Mukai 2007, J Equine Sci 18:153 | 10.1294/jes.18.153 | Japón | en | PSI | RESUMEN | 95 % de FC pico en 12,4 s |

## 5. Cobertura por regiones, idiomas y razas
- **Con resultado:** Australia (Melbourne, Sídney, Tasmania), EE. UU. (California), Nueva Zelanda (Massey), Suiza,
  Turquía (DergiPark, YÖK; turco), Polonia, Qatar (ICRAV), Italia, Francia (resúmenes), Japón (J-STAGE), Corea
  (koreascience; coreano), Brasil (Redalyc; portugués), Irlanda, Suecia (resúmenes).
- **Sin resultado útil:** EAU (Dubai Equine Hospital, CVRL, ERA, Meydan), Arabia Saudí (KFU, Qassim: solo camellos),
  Omán, Kuwait, Bahréin, búsquedas en árabe (solo divulgación y una serie siria de tratamiento sin factores de riesgo);
  Hong Kong (V200); Francia DUMAS/HAL (bloqueados, Anubis); Rusia y Kazajistán (solo caballos de deporte); Argentina,
  Perú, Chile; Corea (tendón: solo Choi & Parkin); Suecia SLU Epsilon (tendón); Sudáfrica (no se llegó a buscar).
- **Idiomas:** inglés, turco, coreano, portugués, francés, árabe (sin resultado), japonés (solo resúmenes).
- **Razas:** PSI, árabe de carreras, trotón francés, Standardbred (Italia, Nueva Zelanda, Suecia), anglo-árabe (método).
  Sin resultado: AQPS, Shagya, Akhal-Teké.

## 6. Resumen
- Auditadas 9 fuentes del motor; **6 mejoradas** (1 a texto completo). Cuatro correcciones de ámbito o redacción:
  Morrice-West 2025 (Tasmania, HR, carga = fatiga ósea), Carrier (solo húmero), Vermeulen
  (diferencia media, +8 % de prensa) y Frick (canter en cinta); Martig confirmada. **Ninguna constante implementada cambia.**
- Índice tendinoso: en árabes sigue sin OR/IRR; la edad de 3–4 años queda reforzada por tres fuentes y la carga
  acumulada solo se asocia a la gravedad. Se mantiene cualitativo y PENDIENTE.
- V200/VHRmax: los trotones confirman el método y su sensibilidad a la sobrecarga [I-raza]; no hay TE publicado legible
  para PSI ni árabes; A9 debe usar el TE propio del caballo.
- Todo es revisión bibliográfica y **probado solo en local o CI** (versiones); nada se ha **verificado con caballos
  reales**. La fatiga ósea es un índice de carga, **nunca una predicción de lesiones**.
