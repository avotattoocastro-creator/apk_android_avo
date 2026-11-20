# Estudio horario 2026-11-20 20:08 UTC — Recuperación tras el trabajo rápido (glucógeno, CK/AST, intervalos) y pérdida de peso corporal (umbral del 2 %)

KB-1 1.21.0 → **1.22.0** · motor 2.0.0-dev23 → **2.0.0-dev24** · rama `claude/kb-estudio-2026-11-20-2008`, encadenada desde
`claude/kb-estudio-2026-11-20-1908` (PR #110, sin fusionar).

## Decisiones tomadas sin supervisión

1. Encadeno desde la rama de PR #110 (el estudio horario más reciente abierto) para heredar la KB 1.21.0 y el motor dev23.
2. Temas elegidos porque ningún estudio anterior los cubre (comprobado con `grep` en `estudios/`): (a) **curso temporal de
   la recuperación** tras un trabajo rápido o una carrera, que da base al planificador (P1–P7, DM1–DM4) y al cola «días entre
   trabajos rápidos»; (b) **pérdida de peso corporal** en carrera/entrenamiento, para auditar el umbral de diseño del 2 % que
   el estudio de 19:08 dejó como [I] en SO1–SO3.
3. Sin cambios de lógica en el motor: la evidencia en PSI de llano es casi toda de resumen o de otras razas. Solo se suben
   versiones. Dos reglas nuevas quedan como PROPUESTAS [I] (RT1–RT3 y PE1–PE3).
4. Las cifras de estudios primarios que solo conocemos a través de una revisión se marcan [NV] para el estudio primario.
5. Investigación con 2 subagentes en paralelo (≈ 15 min cada uno, WebSearch/WebFetch, sin sitios piratas ni espejos).

## Tema A — Recuperación tras el trabajo rápido o la carrera

### A.1 Glucógeno muscular

| Hallazgo | Población | Fuente | Etiqueta |
|---|---|---|---|
| Un esfuerzo máximo de 800–2.000 m consume ≈ 20–40 % del glucógeno; resíntesis lenta (≈ 0,6–1,5 mmol/kg p. h./h); reposición completa en 48–72 h y no recuperado a las 24 h | Revisión (PSI y trotones; cita a Snow, Davie, Hyyppä, Lacombe) | Jose-Cunilleras & Hinchcliff 2004, *Equine Comp Exerc Physiol* 1:23–32, doi:10.1079/ECEP20031 (PDF en ddd.uab.cat) | [E] revisión; primarios [NV] |
| Depleción ≈ 26–30 % en sesión de intervalos; resíntesis despreciable a las 24 h; basal a las 72 h; una segunda sesión a los 3 días no vuelve a basal a las 72 h | 6 trotones, Finlandia | Hyyppä, Räsänen & Pösö 1997, *Am J Vet Res* 58:162, PMID 9028482 | [E-r] [I-raza]: trotón, mismo metabolismo de glucógeno de fibras tipo II; esfuerzo más largo que un breeze |
| Con dieta rica en almidón, basal a las 72 h; con dieta baja/mixta, incompleta | 7 caballos en forma | Lacombe et al. 2004, *AJVR* 65:916, doi:10.2460/ajvr.2004.65.916 | [E-r] |
| Glucógeno bajo → −22 % de déficit de O₂ acumulado y −27 % de tiempo hasta la fatiga | 7 caballos | Lacombe et al. 2001, *J Appl Physiol* 91:1782 | [E-r] |
| **Discrepante:** tras ejercicio intenso en cinta, el glucógeno baja 15–27 % y vuelve al nivel previo a las 24 h | PSI, Japón | Minami et al. 2009, *J Equine Sci* 20:33, doi:10.1294/jes.20.33 | [E-r] (n y protocolo [NV]) |
| Pruebas repetidas cada 48 h: el glucógeno cae tras la 2.ª y 3.ª en caballos sin entrenar, no tras 8 semanas de acondicionamiento; CK y lactato a basal en 6–24 h | 10 PSI castrados, EE. UU. | Lungu et al. 2026, *J Anim Sci* 104:skag063, doi:10.1093/jas/skag063 | [E-r] |

**Lectura [I]:** el rango defendible es 48–72 h para reponer el glucógeno tras un esfuerzo rápido; el único dato en PSI que
dice 24 h (Minami 2009) es de resumen y en cinta. El acondicionamiento acorta la recuperación (Lungu 2026). Ninguna fuente
leída mide el glucógeno tras un breeze típico de 400–800 m en pista.

### A.2 CK y AST

| Hallazgo | Población | Fuente | Etiqueta |
|---|---|---|---|
| AST sube al terminar y sigue alta a 1 h; CK y LDH con pico a 1 h; valores a 24 h [NV] | 6 árabes de carreras de llano, 3–6 años, 1.250–1.400 m, Irán | Mami et al. 2019, *J Equine Vet Sci* 78:74, doi:10.1016/j.jevs.2019.04.007 | [E-r] (árabe de llano) |
| CK por encima del basal a 120 min; AST alta a 120 min; solo hasta 2 h, cifras en gráfica | 30 PSI machos, 1.200–2.000 m, Italia | Arfuso et al. 2022, *Antioxidants* 11:1176, doi:10.3390/antiox11061176 (PMC9220350) | [E] |
| Entrenamiento ordinario (galope corto): CK 468 → 509 (5 h) → 480 U/L (18 h), sin cambio significativo; AST 267 → 291 → 280 U/L | 25 árabes de carreras, Irán | Pourmohammad et al. 2019, *Turk J Vet Anim Sci* 43:791, doi:10.3906/vet-1905-82 | [E] (árabe de llano) |
| Más potras que potros superan 2× la CK a las 2 h; menos según avanza la temporada | 40 PSI 2–3 años, Reino Unido | Harris, Marlin & Gray 1998, *Vet J* 155:295, doi:10.1016/s1090-0233(05)80026-7 | [E-r] |

**Lectura [I]:** CK/AST alcanzan el pico en 1–6 h y suelen normalizarse en ≤ 24 h; no sirven para fijar la separación entre
trabajos rápidos y AVO no los mide. Solo contexto.

### A.3 Intervalos entre carreras/trabajos rápidos

| Hallazgo | Población | Fuente | Etiqueta |
|---|---|---|---|
| Lesión catastrófica: días entre carreras OR 0,99/día (0,98–1,00); días entre trabajos OR 1,03/día (1,00–1,06); ninguna queda en el modelo multivariable | PSI, California, 42 casos/95 controles | Hitchens, Hill & Stover 2018, *Front Vet Sci* 5:217, doi:10.3389/fvets.2018.00217 | [E] |
| Rendimiento por salida mejora hasta ≈ 3 semanas entre carreras y empeora después (término cuadrático) | 66 entrenadores, Victoria (Australia) | Morrice-West et al. 2021, *Animals* (core.ac.uk/download/491269454.pdf) | [E] (asignación de columnas de la tabla insegura → cifras TIR [NV]) |

No se encontró FC de reposo ni rendimiento a los días 1–3 tras un trabajo rápido en PSI [NV].

### A.4 Reglas propuestas para el planificador (RT1–RT3, [I], sin implementar)

- **RT1:** separación mínima de **72 h** entre dos trabajos rápidos (≤ 2 por semana) por defecto; 48 h solo en caballos
  acondicionados y como excepción explícita. Base: 48–72 h de reposición de glucógeno [E revisión / E-r]; el número exacto es diseño.
- **RT2:** el día siguiente a un trabajo rápido, solo trabajo suave (paso/trote/canter lento); coherente con P1–P6.
- **RT3:** entre carreras, no planificar otra carrera antes de ≈ 14 d sin aviso; el óptimo de ≈ 3 semanas de Victoria es de
  rendimiento, no de seguridad, y queda como contexto.

## Tema B — Pérdida de peso corporal y umbral del 2 %

| Hallazgo | Población | Fuente | Etiqueta |
|---|---|---|---|
| −2,71 ± 0,66 % justo tras la carrera (sin furosemida), −3,55 % con furosemida; a la mañana siguiente −1,24 % y −0,90 % | 30 trotones, carrera real, Kentucky | Coleman et al. 2002, *EVJ Suppl* 34:165, doi:10.1111/j.2042-3306.2002.tb05411.x | [E-r] [I-raza]: esfuerzo de carrera de duración similar |
| −3,5 kg por carrera (0,7 %); máximo −5,3 kg (1,0 %) a las 24 h; déficit sostenido ≈ 4,8 kg con carreras seguidas | 40 PSI castrados, carreras de carretas, Canadá | Warren & Whelen 2002, *EVJ Suppl* 34:173, doi:10.1111/j.2042-3306.2002.tb05413.x | [E-r] (PSI, no llano) |
| Sudor 19,2 L en calor seco frente a 11,7 L en frío; pérdidas 2–3× con calor y humedad | 6 PSI en cinta | McCutcheon & Geor 1996, *EVJ Suppl* 22:54, doi:10.1111/j.2042-3306.1996.tb05032.x | [E-r] |
| Transporte: 0,45–0,55 %/h; peso bajo 3–7 d; citando a Leadon 1994: < 10 kg sin efecto, ≥ 20 kg asociado a malos resultados | PSI transportados, Japón | Oikawa & Maeda 2011, *産業動物臨床医学雑誌* 2(4):205 (agriknowledge.affrc.go.jp) | [E] (OCR; Leadon 1994 [NV]) |
| Peso estacional (mínimo en verano en machos); ≈ +30 kg a lo largo de la carrera deportiva | 632.540 pesajes JRA 2002–2014 | Takahashi & Takahashi 2017, *BMC Vet Res* 13:257, doi:10.1186/s12917-017-1184-3 | [E-r] (amplitud [NV]) |
| Sobreentrenamiento: bajada significativa de peso desde la semana 28 sin menor ingesta; kg [NV] | 13 trotones | Tyler-McGowan et al. 1999, *EVJ Suppl* 30:621 | [E-r] [I-raza] |

No hay estudio de peso antes/después de una carrera de llano en PSI ni del error típico día a día del peso en caballos de
carreras; nada en árabes de llano [NV]. Endurance (Schott 1997, 3,6–4,9 %) se descarta por disciplina.

**Auditoría del 2 % [I]:** no está validado. Una carrera o un esfuerzo intenso con calor quitan de forma aguda ≈ 1–3,5 %;
a las 24 h queda ≈ 1–1,3 % por debajo. Medido tras el trabajo, el 2 % da falsos positivos.

Reglas propuestas (PE1–PE3, [I], sin implementar):
- **PE1:** usar solo pesajes en ayunas por la mañana y nunca en las 12 h siguientes a un trabajo rápido o carrera.
- **PE2:** AVISO si la caída es ≥ 2 % frente a la mediana de 7 d durante ≥ 3 mañanas seguidas; ALTO si ≥ 4 % (≈ 20 kg en un
  PSI de 475 kg, coherente con Leadon 1994 vía Oikawa [NV]).
- **PE3:** tras transporte, ventana de gracia de 3 d.
Todo esto es diseño hasta medir el error típico de la báscula y del caballo (≥ 10 mañanas).

## Fuentes bloqueadas

PMC5563038, PMC5688808, PMC5735309, PMC7696103 y PMC9545901 (reCAPTCHA o permiso no concedido); J-STAGE de Ohmura 2025;
link.springer.com; Cambridge (URL rechazada por el proxy); textos primarios de Snow & Harris 1991, Davie 1994–96 y Lacombe 1999.

## Resumen

- Glucógeno: 48–72 h para reponerse tras un esfuerzo rápido (revisión [E], Hyyppä [E-r], Lacombe [E-r]); Minami 2009 discrepa (24 h, [E-r]).
- CK/AST: pico 1–6 h, normal en ≤ 24 h, también en árabes de llano (Mami 2019, Pourmohammad 2019); no sirven para el planificador.
- Intervalos: sin efecto independiente en lesión catastrófica (Hitchens 2018 [E]); rendimiento óptimo ≈ 3 semanas entre carreras (Victoria).
- Peso: el 2 % de SO no está respaldado tal cual; propuestas PE1–PE3 (pesaje matinal, persistencia ≥ 3 d, ALTO ≥ 4 %).
- Propuestas RT1–RT3 y PE1–PE3 [I]; sin cambios de lógica; nada verificado con caballos reales.
