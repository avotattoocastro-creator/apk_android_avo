# Estudio horario 2026-11-20 13:12 UTC — temperatura ambiente y peso cargado como criterios de comparables

**KB-1 1.15.0 · motor 2.0.0-dev17 · sin cambios de lógica, reglas ni umbrales.**

## Decisiones tomadas sin supervisión

1. **Encadenamiento.** La rama sale de `claude/kb-estudio-2026-11-20-1210` (PR #101, el PR `claude/kb-*` abierto más
   reciente; también sigue abierto el #99, del que desciende). Hereda la KB 1.14.0 y el motor 2.0.0-dev16.
2. **Temas elegidos.** Los temas prioritarios de la lista (modelo B, tendón, V200/A9, ECG/A11, playa, planificador,
   velocidad final, cociente de galope, layup, parcial de 200 m) ya los han tratado los estudios de hoy y de la noche.
   Se eligen dos huecos sin tratar que afectan a las **líneas base y a los comparables** de A7, A8 y A9:
   - **Tema 1: temperatura, humedad y estación** frente a la FC submáxima, la V200 y la recuperación. Ningún estudio
     anterior lo trata; solo hay una línea sobre el calor húmedo (Art 1995) en el estudio ampliado del 18/11.
   - **Tema 2: peso cargado** (jinete + montura, peso de handicap) frente a la velocidad, la zancada y la FC. Ningún
     estudio anterior lo trata; afecta a la velocidad final relativa y al parcial final (A8).
3. **Motor.** No se implementa nada. Ninguno de los dos temas da un coeficiente en texto completo, y la recomendación
   (usar temperatura y peso como criterio de comparables) es un diseño [I] que exige campos en `Session` que el
   análisis todavía no recibe. Solo se suben las versiones.
4. **Investigación.** La hicieron 2 subagentes en paralelo (unos 9 min cada uno). PMC y PubMed quedaron bloqueados
   (la petición de permiso caducó, o captcha). No se esquivó ningún bloqueo. Las cifras de los agregadores se marcan
   [E-r] y se anota el acceso.

## Tema 1 — Temperatura, humedad y estación frente a la FC y la V200

### Lo que se ha leído

| Fuente | Raza / país | Acceso | Hallazgo |
|---|---|---|---|
| Hargreaves, Kronfeld & Naylor 1999, *EVJ* 31:314, doi 10.1111/j.2042-3306.1999.tb03823.x | NV (posibles árabes, sin confirmar) · EE. UU. | AGREGADOR | 10 caballos, 3 pruebas de campo en julio y 3 en septiembre. Tras 4 min a 7,0 m/s, la FC fue de 135 ± 1 lpm en calor y de 123 ± 1 lpm en fresco (P < 0,0001): **≈ +12 lpm, ≈ +10 %** [E-r]. No se han visto la temperatura ni la humedad [NV] |
| Schrurs, Dubois, Van Erck-Westergren & Gardner 2024, *Animals* 14:1342, doi 10.3390/ani14091342 | PSI · Australia | TEXTO COMPLETO (MDPI) | 485 caballos y 4.837 sesiones. Con ≥ 18 °C (934 sesiones) frente a ≤ 5 °C (954), la recuperación a 2 min fue de 124 frente a 128 lpm, **≈ 4 ± 2 lpm**, y algo más rápida en calor. Los autores la consideran biológicamente pequeña. La humedad (≥ 95 % frente a ≤ 67 %) no cambió nada. No dan coeficiente por °C ni estudian la V200 [E] |
| Poinsard, Anson & Billat 2026, *Animals* 16:1598, doi 10.3390/ani16111598 | trotón francés · Francia [I-raza] | TEXTO COMPLETO (≈ 64 % leído) | 60 caballos, 483 sesiones entre −1,6 y 23,1 °C. Añadir la temperatura como covariable apenas cambia el ICC del coste cardiaco, la FCR o la V150 (< 0,01). No dan el efecto sobre los valores absolutos de V200 [E] |
| Ebisuda, Mukai, …, Ohmura 2023, *Front Vet Sci* 10:1230212, doi 10.3389/fvets.2023.1230212 | PSI · Japón (JRA) | TEXTO COMPLETO (≈ 88 %) | En cinta, con WBGT de 12,5 °C frente a 29,5 °C, la FC de pico a 10,4 m/s fue de 213 frente a 214 lpm (p = 0,78). **La FC máxima no cambia con el calor** [E] |
| Ohmura, Ebisuda, Takahashi & Mukai 2025, *J Equine Sci* 36:19, doi 10.1294/jes.36.19 | PSI · Japón | RESUMEN | Con WBGT de 32–33 °C, enfriar antes del ejercicio no cambió la FC, el lactato ni el tiempo hasta el agotamiento [E-r] |
| Nomura et al. 2019, *J Equine Sci* 30:17, doi 10.1294/jes.30.17 | PSI · Japón | RESUMEN | En 975.247 participaciones hubo un 0,04 % de golpe de calor tras la carrera (0,086 % de mayo a septiembre). En verano, la mayoría de las carreras se corrieron con WBGT de 28–33 °C [E-r] |
| Geor, McCutcheon, Ecker & Lindinger 1995, *EVJ Suppl* 20:125, doi 10.1111/j.2042-3306.1995.tb05018.x | PSI · Canadá | AGREGADOR | La FC solo subió de forma significativa con calor **húmedo** (32–34 °C y 80–85 %), no con calor seco [E-r] |
| Geor, McCutcheon & Lindinger 1996, *EVJ Suppl* 22:63, doi 10.1111/j.2042-3306.1996.tb05033.x | PSI | AGREGADOR | Tras 10 días de exposición a 33–35 °C y 80–85 %, la FC al final del ejercicio ya era menor que el día 1: hay **aclimatación** [E-r] |
| Marlin et al. 1996, *EVJ Suppl* 22:70 (PMID 8894553) | varias · Reino Unido | AGREGADOR | El VO2 sube ≈ 5 % con calor seco y ≈ 14 % con calor húmedo. Con calor húmedo, solo 1 de 4 caballos terminó [E-r] |
| Art, Votion & Lekeux 1995, *EVJ Suppl* 20:120, doi 10.1111/j.2042-3306.1995.tb05017.x | trotón · Bélgica | RESUMEN | Con 30 °C y 75 % de humedad, la FC siguió elevada hasta 30 min después [E-r] |
| Art & Lekeux 1988, *Vet Rec* 123:295, doi 10.1136/vr.123.11.295 | ponis | AGREGADOR | Estratifican las condiciones por temperatura (°C) + humedad (%), con corte en 85 [E-r] |
| Arfuso et al. 2025, *Animals* 15:1436, doi 10.3390/ani15101436 | trotón · Italia | TEXTO COMPLETO (≈ 84 %) | Sin efecto del THI sobre la FC del que se informe; zona termoneutra citada de 5–25 °C [E] |
| Aclimatación al calor en PSI 2024, *Physiol Rep* (autores y DOI [NV]) | PSI · Japón | AGREGADOR | Aclimatarse a WBGT 29–30 °C mejora el tiempo en calor y el volumen sistólico [E-r] |

### Lectura para AVO

- **No hay ningún coeficiente publicado en lpm/°C** ni ningún cambio de V200, V4 o VHRmax por estación en caballos de
  carreras [NV].
- El efecto **no es lineal**. Entre unos −2 y 23 °C casi no influye en la reproducibilidad (Poinsard [E]) y la
  recuperación cambia unos 4 lpm (Schrurs [E]). Con calor húmedo (≥ 30 °C y humedad ≥ 75–85 %), la FC submáxima sube
  de forma clara (Geor 1995, Marlin 1996, Art 1995 [E-r]) y en el campo puede llegar a unos +12 lpm a 7 m/s
  (Hargreaves [E-r]).
- La FC de pico no cambia (Ebisuda [E]). Por eso el calor **sesga la V200 a la baja** (más FC a igual velocidad) y no
  la VHRmax. La magnitud en V200, de un 5–10 % en verano, es una **inferencia** [I] a partir del +10 % de FC.
- La **aclimatación** de unos 10 días cambia la respuesta, así que la primera semana de calor no es comparable con la
  siguiente (Geor 1996 [E-r]).
- **Árabes de carreras en llano:** no hay datos. Tampoco del Golfo, Turquía, Hong Kong ni Brasil.

### Propuesta (diseño [I], sin implementar)

- **TC1.** Guardar en `Session` la temperatura y la humedad (o el WBGT si existe), tomadas del móvil o de una estación
  meteorológica cercana.
- **TC2.** Para A9 (V200/VHRmax) y la recuperación, considerar comparables solo las sesiones con **|ΔT| ≤ 5 °C** (o
  |ΔWBGT| ≤ 3–4 °C) [I].
- **TC3.** Marcar **«no comparable por calor»** las sesiones con WBGT ≥ 28 °C, o con ≥ 30 °C y humedad ≥ 70 % [I].
  Así A9 no puede leer una caída de V200 causada por el calor como pérdida de forma. El corte de 28 °C sale de la
  distribución de Nomura y de los protocolos de cinta [I].
- **TC4.** Tratar como transición los primeros 10–14 días de una ola de calor [I].
- **TC5.** No usar ningún coeficiente de corrección hasta estimarlo con datos propios de AVO: modelo mixto por caballo
  con temperatura o WBGT como covariable.

## Tema 2 — Peso cargado frente a velocidad, zancada y FC

### Lo que se ha leído

| Fuente | Raza / país | Acceso | Hallazgo |
|---|---|---|---|
| Lee & Park 2011, *Arch Zootec* 60:281, redalyc 49520788055 | PSI · Corea | TEXTO COMPLETO | 155.656 tiempos de 8.197 caballos (Gwacheon 1994–2006), con la relación peso cargado/peso corporal (CW/BW) como efecto fijo. En 1000 m, los mejores tiempos salen con un CW/BW de ≈ 12,0–12,7 % y el tiempo sube por encima. No dan coeficiente en s/kg. **«1 kg ≈ 2 longitudes» es una premisa, no un resultado.** El % de victorias sube con el peso (9,7 % a 55 kg frente a 38,7 % a ≥ 60 kg) por el sesgo del handicap [E] |
| Bugislaus, Roehe, Uphaus & Kalm 2004, *Arch Tierz* 47:505 | PSI · Alemania | TEXTO COMPLETO | 47–74,5 kg. Dentro del caballo, el peso empeora el puesto (+0,049 por kg en √puesto). Entre caballos, el signo se invierte (−0,020), por la confusión entre handicap y calidad. Una corrección lineal fija sesga los valores genéticos [E] |
| Takahashi 2015, *J Equine Sci* 26:43, doi 10.1294/jes.26.43 | PSI · Japón (JRA) | TEXTO COMPLETO | ≈ 283.000 salidas. El efecto de subir el peso con la edad sobre la velocidad media es «pequeño» (54→57 kg) [E] |
| Morrice-West, Hitchens, …, Whitton (manuscrito aceptado, *EVJ*), minerva-access | PSI · Australia | TEXTO COMPLETO (manuscrito) | 25.259 salidas y 153.315 parciales de 200 m. Como efecto principal, el peso no cambia la zancada (−0,017 zancadas/200 m por 10 kg, p = 0,36). No está claro si es peso cargado o corporal [E/NV] |
| Schrurs, Dubois, Van Erck-Westergren & Gardner 2022, *PLoS ONE* 17:e0273310, doi 10.1371/journal.pone.0273310 | PSI · Australia y R. U. | TEXTO COMPLETO | 3.568 sesiones de trabajo y 103 jinetes. El sexo del jinete no cambia la velocidad (mejor 600 m, p = 0,07) ni la zancada en galope fuerte (7,62 ± 0,30 frente a 7,61 ± 0,28 m). No se registró el peso [E] |
| Pfau, Spence, Starke, Ferrari & Wilson 2009, *Science* 325:289, doi 10.1126/science.1174605 | PSI · R. U. | AGREGADOR | La postura agachada del jockey se asocia a tiempos un 5–7 % mejores [E-r] |
| Christensen et al. 2020, *Animals* 10:95, doi 10.3390/ani10010095 | caballos de silla · Dinamarca [I-raza] | TEXTO COMPLETO | Con +15–25 % sobre el peso del jinete (relación de 15,3 a 18,5 %), la FC no cambia a baja intensidad (p = 0,72) [E] |
| Stefánsdóttir et al. 2017, *Animal* (PMC5561439) | islandés [I-raza] | RESUMEN (PMC bloqueado) | Con relaciones del 20 al 35 %, la FC y el lactato suben de forma lineal. El paso a anaerobio llega hacia el 22,7 % (17,0–27,5 %) [E-r] |
| Binder, Grimes & Winterbotham 2020, *J Sports Econ* | PSI · EE. UU. | RESUMEN | La descarga de aprendiz (5–10 lb) da +0,7–1,5 pp de quedar «in the money», pero mezcla peso y habilidad [E-r] |
| Ekiz, Koçak & Demir 2005, *Turk J Vet Anim Sci* 29:543; Sobczyńska 2006, *Czech J Anim Sci* 51:523 | **árabes** · Turquía, Polonia | TEXTO COMPLETO | En árabes, el peso no está en el modelo (Ekiz) o es una covariable sin coeficiente publicado (Sobczyńska) [E] |

### Lectura para AVO

- **No hay ningún coeficiente válido de peso → velocidad** para PSI ni árabes al galope. Las equivalencias de
  «1 kg ≈ 1–2 longitudes» son una convención [E, Lee & Park].
- En carrera, el peso está **confundido con la calidad**: el handicap pone más peso a los mejores caballos. Por eso
  una corrección fija sesga [E, Bugislaus].
- En el trabajo de AVO, el peso lo cambia el jinete. La zancada apenas se ve afectada (Morrice-West, Schrurs [E]) y la
  FC sube con el peso solo a relaciones altas (≥ 20 %) y en otras razas [E-r, I-raza]. Un jockey de 50–60 kg sobre un
  PSI de 450–500 kg queda en ≈ 11–13 % [I].
- El estilo del jinete puede pesar más que unos kilos (Pfau 2009 [E-r]).

### Propuesta (diseño [I], sin implementar)

- **PC1.** Guardar en `Session` el jinete y su peso con la montura (peso cargado). Si hay un peso del caballo
  reciente, calcular el CW/BW.
- **PC2.** Para A8 (parcial final), A7 y la velocidad final relativa, considerar comparables solo las sesiones con
  **|Δpeso cargado| ≤ 3 kg** (≈ 0,6 % del peso corporal) y el **mismo jinete** si se puede [I]. Si no, bajar la
  confianza.
- **PC3.** Mostrar un aviso informativo si el CW/BW supera ≈ 13 % (límite de los datos coreanos [E]). No es un umbral
  de riesgo.
- **PC4.** Sin coeficiente de corrección hasta calibrarlo con datos propios: mismo caballo, distintos jinetes, misma
  pista y franja.

## Bloqueado o no encontrado

- PMC (PMC12504628 sobre capacidad de carga en cinta; PMC5561439; PMC8427666; PMC11126422) y PubMed 10454090 y
  28320488: la petición de permiso caducó o hubo captcha.
- Faltan el texto completo de Hargreaves 1999 (raza y condiciones), las cifras de FC de Geor 1995/1996 y Marlin 1996
  (Wiley), Oki 1994 (coeficientes) y la tabla S2 de Morrice-West.
- No se encontró ninguna V200 estacional en trotones (Couroucé, Leleu), nada de Hong Kong ni del Golfo sobre el calor,
  ningún dato de peso o temperatura en árabes de Francia, el Golfo o Polonia, ni Powell 2008 ni Matsuura.

## Resumen

- **Temperatura:** no hay coeficiente publicado. El calor húmedo (WBGT ≥ 28 °C, o ≥ 30 °C con humedad alta) sube la
  FC submáxima (≈ +12 lpm a 7 m/s [E-r]) sin cambiar la FC de pico [E], así que **la V200 baja en calor sin pérdida
  de forma**. Se propone TC1–TC5 [I]: temperatura como criterio de comparables de A9, con marca de «no comparable por
  calor» y transición de aclimatación.
- **Peso cargado:** no hay coeficiente válido. El peso está confundido con la calidad en carrera [E] y casi no cambia
  la zancada [E]. Se propone PC1–PC4 [I]: peso y jinete como criterio de comparables de A7/A8, sin corrección.
- **Árabes de carreras en llano:** sin datos en los dos temas.
- **Motor:** sin cambios de lógica, reglas ni umbrales. KB 1.14.0 → 1.15.0 y motor 2.0.0-dev16 → 2.0.0-dev17.
  Probado en local y CI; **NO VERIFICADO** con caballos reales.
