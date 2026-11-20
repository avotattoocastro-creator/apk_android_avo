# Estudio horario 2026-11-20 12:10 UTC — playa por franjas (línea base) y parcial final de 200 m (A8)

**KB-1 1.14.0 · motor 2.0.0-dev16 · sin cambios de lógica, reglas ni umbrales.**

## Decisiones tomadas sin supervisión

1. **Encadenamiento.** La rama sale de `claude/kb-estudio-2026-11-20-1110` (PR #99, el único PR `claude/kb-*` abierto)
   para heredar la KB 1.13.0 y el motor 2.0.0-dev15.
2. **Temas elegidos.** Ninguno de los estudios de hoy (08:09, 09:09, 10:08, 11:10 ni el de la noche) los ha tratado.
   Los dos bloquean código:
   - **Línea base de la playa por franja.** Corresponde al pendiente PL1–PL6 y a la cola de Chateau 2011 y
     Crevier-Denoix 2011.
   - **Velocidad del parcial final.** Es el pendiente A8, que pide añadir el último parcial de 200 m y buscar un
     umbral apoyado en la variabilidad del propio caballo.
3. **Motor.** No se implementa ningún pendiente:
   - La playa por franja sigue sin cifras absolutas en texto completo.
   - Para el parcial de 200 m (A8), la unidad sí está cerrada en texto completo (Wong 2023, ya [E] en la KB), pero
     la variabilidad dentro del caballo es una cifra derivada [I] y no da tiempo a probarlo bien en esta franja de
     50 min.
   - Solo se suben las versiones.
4. **Investigación.** La hicieron 2 subagentes con un límite de unos 18 min cada uno. Varias webs denegaron el
   acceso: PMC, minerva-access y Europe PMC no respondieron a la petición de permiso, y findanexpert.unimelb aplica
   antibots. No se esquivó ninguna.

## Tema 1 — Playa por franjas

### Corrección de atribución (importante)

La KB tenía los dos artículos de 2011 mezclados en el parámetro `playa_franjas`. Según los resúmenes del editor, a
través del agregador madbarn [E-r]:

| Dato | Artículo correcto |
|---|---|
| Humedad del 19 % en la orilla firme frente al 13,5 % en la arena húmeda profunda; ensayo a 7 m/s; fuerza de reacción del suelo y cinemática del menudillo | **Crevier-Denoix et al. 2011**, EVJ Suppl 38:544–551, doi 10.1111/j.2042-3306.2010.00202.x, PMID 21059058 |
| Deceleración vertical del casco en el impacto: −59 % (húmeda profunda frente a firme, a 25 km/h) y −95 % (seca profunda frente a asfalto, a 15 km/h). Frenado: −50 % y −55 % | **Chateau et al. 2011**, EVJ Suppl 38:488–495 |

Las cifras de −59 % y −50 % son **deceleraciones del casco** (acelerómetro a 10 kHz), no fuerzas. El DOI
…00277.x que la KB asigna a Chateau 2011 no se ha confirmado [NV]. Se marca como provisional. Las dos fuentes son de
trotón francés con n = 4 [I-raza].

### Fuentes nuevas o ampliadas

| Fuente | País · raza · n | Cifras | Etiqueta |
|---|---|---|---|
| Crevier-Denoix N, Robin D, Pourcelot P et al. 2011, EVJ Suppl 38:544, doi 10.1111/j.2042-3306.2010.00202.x | Francia · trotón · 4 (3 en la cinemática) | En arena profunda: apoyo más largo, picos de fuerza vertical y longitudinal más bajos y más tardíos, mayor impulso propulsivo (posible carga añadida del TFDS). Cifras absolutas [NV] | [E-r] |
| Porzio E, …, Beccati F 2025, Vet Sci 12(11):1028, doi 10.3390/vetsci12111028 | EAU (Dubái) · 11 árabes y 7 angloárabes **de resistencia** · 18 | Arena profunda, 7 km a ≈ 21 km/h. A 20 km/h: frecuencia 1,77 ± 0,05 zancadas/s y longitud 3,14 ± 0,08 m. A la velocidad máxima (22,8 ± 1,3 km/h): 1,85 zancadas/s y 3,44 m. No hay control en suelo firme | [E] parcial (leído ~70 % del texto en MDPI); raid, no llano: [I-raza] solo como orden de magnitud |
| Graydon R et al. (Hobbs SJ) 2023, Biomechanics 3(3):343–361, doi 10.3390/biomechanics3030029 | Reino Unido/Europa · terreno de concurso completo · 9 recorridos | Humedad volumétrica observada 10–63 % (sonda Delta-T ML3, 60 mm). Firmeza con el OBST 13–151 g. Going Stick 5,87–11,9, abandonado en suelo firme. Son rangos observados: no hay cortes validados | [E] parcial |
| Crevier-Denoix N et al. 2013, diapositivas de la Académie Vétérinaire de France (qualif.avf.educagri.fr) | Francia · trotón · 3 | Pistas de arena, no playa. Dureza Clegg 2,25 kg; la pista B es ≈ 2,3 veces más dura que la A; ≈ 35 km/h | [E] |
| Morrice-West 2018, Animals 8:221 (ya en la KB) | Australia · PSI · 66 entrenadores | Se completa: arena en el 97 % del trabajo lento (media del 83,4 % de ese trabajo) y en el 33 % del trabajo rápido (media del 71,3 %) | [E] |

**No hallado [NV]:**

- Ningún estudio de FC, lactato o coste energético a igual velocidad en arena profunda frente a firme en caballos de
  carreras.
- Ningún dato de Laytown, Deauville, Pornichet, Cagnes ni Nueva Zelanda.
- No se han abierto las tesis de DUMAS/ENVA sobre la playa ni el informe UCLan *Ground and Going* 2024.

### Lectura para el motor [I]

- **PL1–PL6 se mantienen como diseño.** Sin cifras absolutas por franja no se pueden poner umbrales de zancada por
  franja. La regla vigente, «sesiones comparables = misma superficie anotada», ya separa la playa de la pista en A7 y
  A8.
- **V200 (A9).** Separar la playa de la pista se apoya solo en la biomecánica (apoyo más largo y más impulso en
  arena profunda) y no en un coste fisiológico medido. Sigue siendo una inferencia [I].
- **Registro en campo.** Se propone [I] anotar por sesión la humedad volumétrica con una sonda tipo ML3 si la cuadra
  la tiene. Si no, basta la franja y la nota del jinete. No hay cortes publicados para la playa.

## Tema 2 — Parcial final de 200 m (A8)

| Fuente | País · raza · n | Cifras | Etiqueta |
|---|---|---|---|
| Wong ASM et al. 2023, EVJ 55:194, doi 10.1111/evj.13581, PMC10084173 (ya [E] en la KB) | Australia · PSI · 584 caballos, 5.660 salidas | Sin cambios: HR 1,18 por cada −0,1 m/s y 1,11 por cada −10 cm en el último 200 m. Según el resumen, el modelo **no tiene en cuenta el intervalo entre salidas**. Hoy no se pudo releer el método (dispositivo, ajuste por distancia) | [E] previo; método [NV] en esta sesión |
| Morrice-West AV et al. 2020, EVJ, doi 10.1111/evj.13370 (manuscrito aceptado, minerva-access) | Australia (Tasmania) · PSI · 2.678 caballos, 25.259 salidas | StrideMASTER (GPS + acelerómetro) por parciales de 200 m. Media de todos los parciales: 16,63 ± 1,04 m/s, zancada de 7,08 ± 0,39 m y 28,32 ± 1,56 zancadas por 200 m. En la fase final, la velocidad explica el número de zancadas con R² 0,536. ICC del caballo: 0,658 en el número de zancadas y 0,655 en su duración. No da la DE del último parcial dentro del caballo | [E] |
| Legg KA, Gibson MJ, Gee EK, Rogers CW 2025, EVJ, doi 10.1111/evj.70003 (repositorio de Massey) | Nueva Zelanda · PSI · 437.506 salidas, 433 lesiones | Velocidad oficial del último 600 m: mediana 16,4 m/s (RIC 15,6–16,9); 16,7 en verano y 15,1 en invierno. En el modelo mixto (estado de pista, distancia, *rating*), ICC del caballo 0,15, varianza entre caballos 0,08 y residual 0,43. La relación lesión–velocidad es escasa. El artículo tiene incoherencias internas de signos e intervalos | [E] |
| Takahashi Y, Takahashi T, Mukai K, Ohmura H 2021, J Equine Vet Sci 101:103447, doi 10.1016/j.jevs.2021.103447 | Japón (JRA) · PSI · n [NV] | Unos 20 m antes de la meta, en 2.400 m sobre césped, de la 1.ª a la 2.ª vuelta: velocidad 17,3 → 16,0 m/s; frecuencia 2,34 → 2,21 zancadas/s; zancada 7,42 → 7,25 m | [E-r] |

**Cálculo propio [I], no publicado:**

- De Legg 2025 sale una DE residual dentro del caballo en el último 600 m de carrera de ≈ √0,43 ≈ 0,66 m/s, un CV de
  ≈ 4 % sobre 16,4 m/s, ya ajustada por pista, distancia y *rating*.
- Para comparar, el umbral de A8 (0,20 m/s) y la unidad del HR de Wong (0,1 m/s) quedan **muy por debajo del ruido de
  una sola carrera**. Sirven para leer una tendencia, no un valor aislado.
- Esto respalda el diseño actual de A8 (2 de las 3 últimas sesiones o un CUSUM sobre la línea base propia), pero
  conviene confirmarlo con datos de trabajo.
- En los trabajos de la cuadra (misma pista, mismo jinete) el ruido debería ser menor que en carrera [I]. El motor
  debe estimarlo por caballo: es el mismo criterio de «TE propio» que A9.

**No hallado [NV]:**

- Ningún estudio del «agari 3F» de la JRA asociado a lesión.
- Nada de Hong Kong, Corea, Francia ni Reino Unido sobre el parcial final y la lesión.
- Ningún dato de árabes.

### Lectura para el motor [I]

- **A8 no cambia.** El pendiente «añadir v del último 200 m» sigue abierto, con una condición añadida: mostrar el
  último 200 m solo junto a su dispersión propia (DE de las sesiones comparables) y no usarlo como umbral fijo.
- **Desaceleración de Takahashi 2021.** El último tramo baja ≈ 0,1–0,2 m de zancada y ≈ 1 m/s con la fatiga dentro
  de una carrera larga. Es otra razón para comparar siempre la misma distancia.

## Resumen

- **Playa:**
  - Se corrige la atribución: la humedad del 19 % y el 13,5 % es de Crevier-Denoix 2011 (doi …00202.x); el −59 % y
    el −50 % son deceleraciones del casco de Chateau 2011, cuyo DOI …00277.x se marca como no confirmado.
  - No hay cifras absolutas por franja ni un coste fisiológico medido. PL1–PL6 siguen como diseño.
  - Fuentes nuevas: Porzio 2025 (árabes de raid en arena de Dubái) y Graydon 2023 (instrumentos para medir el suelo).
- **Parcial final (A8):**
  - Morrice-West 2020 y Legg 2025 dan la escala de la velocidad final (16,4–16,6 m/s).
  - Cálculo propio [I]: el ruido entre carreras es de ≈ 0,66 m/s, con un CV de ≈ 4 %. A8 debe seguir trabajando por
    tendencia sobre la línea base propia, como ya hace.
  - Takahashi 2021 cuantifica la caída de la zancada con la fatiga en carrera.
  - No hay datos de árabes.
- **6 fuentes nuevas y 3 completadas o corregidas.** Sin cambios de lógica, reglas ni umbrales. KB 1.13.0 → 1.14.0,
  motor 2.0.0-dev15 → 2.0.0-dev16.
- Todo es documentación probada en local y en CI. Nada está verificado con caballos reales. La fatiga ósea no es una
  predicción de lesiones.
