# Estudio horario 20/11/2026 19:08 UTC — DMD en potros de 2 años (planificador) y auditoría de las fuentes de sobreentrenamiento (A9/A10)

KB-1 1.20.0 → **1.21.0** · motor 2.0.0-dev22 → **2.0.0-dev23** · rama `claude/kb-estudio-2026-11-20-1908` (sale de
`claude/kb-estudio-2026-11-20-1809`, PR #109, sin fusionar).

## Decisiones (sesión desatendida)

1. **Encadenamiento:** el PR `claude/kb-*` abierto más reciente es el #109 (18:09); esta rama sale de él.
2. **Temas:** (A) enfermedad metacarpiana dorsal (DMD, «bucked shins») y carga en PSI de 2 años, que ningún estudio
   ni PR había tocado (0 menciones en la KB) y alimenta el planificador semanal (capa 2); (B) auditoría de las fuentes
   de sobreentrenamiento de A9/A10, que solo conocíamos por agregador (MadBarn) desde el estudio ampliado del 18/11.
   Se descartan el modelo B, V200 TE, ECG, playa y velocidad final porque los estudios de hoy los cubrieron y siguen
   bloqueados por accesos (Zenodo, Europe PMC REST).
3. **Motor:** sin cambios de lógica. La evidencia de DMD que daría reglas de carga (Verheyen 2005, Boston & Nunamaker
   2000) sigue solo en resumen o agregador; Crawford 2021 está en texto completo pero da HR por km acumulado, no un
   umbral. Solo se suben versiones.
4. **Accesos:** Europe PMC REST (`www.ebi.ac.uk`) devuelve 403 desde el proxy; varios permisos de WebFetch caducaron
   sin respuesta (PubMed 9644221, journals.physiology.org de Tyler 1996, doi.org de Verheyen 2005, PMC12699115,
   PMC7910838); PMC10000203 pide reCAPTCHA y `vuir.vu.edu.au` (Hamlin) bloquea con Anubis. No se esquivó ninguno.
5. Etiquetas: [E] texto completo, [E-r] resumen, [E-ag] solo agregador (equivale a [E-r] de segunda mano), [I]
   inferencia, [I-raza] otra raza, [NV] no verificado.

## A. DMD en PSI de 2 años y carga de entrenamiento

### A.1 Fuentes y cifras

| Fuente | Acceso | Cifras |
|---|---|---|
| Crawford KL et al. 2021, *Front Vet Sci* 8:698298, doi [10.3389/fvets.2021.698298](https://doi.org/10.3389/fvets.2021.698298), [PMC8593238](https://pmc.ncbi.nlm.nih.gov/articles/PMC8593238) — Australia (Queensland), PSI | [E] | 477 caballos, 936 preparaciones, 39 DMD (caso = ≥ 7 d perdidos; ≈ 8 % de caballos, ≈ 4 % por preparación [I] calculado). HR por km acumulado a «gallop» (15 m/s) 0,89 (0,82–0,97); por día acumulado de gallop 0,96 (0,92–0,99); preparación adicional 0,43 (0,30–0,61); días sin jinete (walker, natación) 0,89 (0,81–0,97); edad de inicio por mes 1,17 (1,07–1,28); macho 2,58 (1,20–5,56); 3/4 pace (13 m/s), pretraining y descanso previo no significativos. Válido solo dentro del rango observado (sesgo de supervivencia, según los autores). |
| Crawford KL et al. 2020, *Animals* 10:2046, doi [10.3390/ani10112046](https://doi.org/10.3390/ani10112046), PMC7694396 — Australia | [E] (lectura parcial) | 42 de 47 DMD (89 %) en 2 años; la DMD es el 41 % de las lesiones musculoesqueléticas a los 2 años frente al 5 % en mayores. |
| Verheyen KLP, Henley WE, Price JS, Wood JLN 2005, *Equine Vet J* 37:442–448, doi [10.2746/042516405774480085](https://doi.org/10.2746/042516405774480085) — Reino Unido, PSI | [E-ag] (MadBarn; RVC Worktribe 1435859 solo ficha) | 335 PSI de 13 cuadras, 4 235 caballo-mes, 79 primeros episodios, 1,87/100 caballo-mes (1,50–2,33). Más canter y más distancia rápida en periodos cortos (≤ 1 mes) → más riesgo; más distancia acumulada desde el inicio → menos riesgo. HR y cortes en km [NV]. |
| Boston RC, Nunamaker DM 2000, *Am J Vet Res* 61:602–608, doi [10.2460/ajvr.2000.61.602](https://doi.org/10.2460/ajvr.2000.61.602) — EE. UU., PSI 2 años | [E-r] | 226 potros, 56 casos (161 perdidos en el seguimiento). log-HR −4,2 ± 1,5 por milla semanal de breeze (~15–16 m/s, protector); +0,3 ± 0,1 por milla semanal de galope (~11 m/s, riesgo); jog sin efecto. Exposición media: breeze 0,15 ± 0,13 mi/sem (máx. 0,64), galope 4,47 ± 1,52 mi/sem. (La redacción de MadBarn invierte el signo; vale el resumen.) |
| Oliveira PR et al. 2006, *Braz J Vet Res Anim Sci* 43:233–241, doi [10.11606/issn.1678-4456.bjvras.2006.26504](https://doi.org/10.11606/issn.1678-4456.bjvras.2006.26504) — Brasil, portugués, PSI 2 años | [E] (sin tabla 1 ni figura 1) | 42 potros de 21–27 meses, arena, 16 semanas; 45 % de DMD (19/42), 78,9 % bilateral; trabajos de 200 → 700 m cada 15 d; los afectados fueron más rápidos en 500 y 700 m (p < 0,05) y 10/19 casos aparecieron en la fase de 700 m; proponen 200–400 m dos veces por semana. n pequeño. |
| Nunamaker 2002 (Milne Lecture, AAEP) y Moyer & Fisher 1992 vía dvm360; Cogger 2004–2008 vía ensayo de estudiante (Univ. Sydney) | [NV] (secundarias) | 70 % de DMD en PSI jóvenes; programa modificado 9,3 % en 5 años; pautas de Cogger e inicio a 30 frente a 28 meses. No se usan. |
| Yildirim 2025, *Equine Vet J*, doi 10.1111/evj.14457 — Turquía, PSI y árabe | [E-ag] | Sin desglose de DMD; en árabes predominan las lesiones de tendón. **Ningún dato de DMD en árabes de llano.** |

### A.2 Lectura

- Las tres fuentes con exposición medida coinciden en la **dirección**: la distancia rápida corta acumulada de forma
  gradual se asocia a menos DMD; los bloques grandes y súbitos de canter/galope largo, a más [E] Crawford, [E-r]
  Boston & Nunamaker, [E-ag] Verheyen.
- La edad de inicio es **contradictoria**: Crawford, inicio tardío → más riesgo [E]; Verheyen, sin efecto (citado por
  Crawford [E]); Cogger, al revés [NV]. No se usa como regla.
- No hay ningún umbral publicado legible en km por semana para 2 años; las cifras de exposición de Boston &
  Nunamaker (millas/semana) son medias, no límites.
- La DMD es una lesión por fatiga del hueso cortical: coherente con el modelo óseo A/B del motor, pero el motor **no
  predice** DMD.

### A.3 Propuesta para el planificador (DM1–DM4, todo [I], sin implementar)

- **DM1** (potros de 2 años, primera preparación): preferir trabajos rápidos cortos (≈ 200–400 m) 1–2 por semana
  desde las primeras semanas a un trabajo largo cada 1–2 semanas; coherente con P1. Base: Boston & Nunamaker [E-r],
  Oliveira [E], Verheyen [E-ag].
- **DM2:** aviso si la distancia de canter o rápida de 7/14/30 d sube bruscamente respecto a la media acumulada del
  propio caballo (relación agudo/crónico, cortes configurables) [I]; base Verheyen [E-ag] y Crawford [E]. Se integraría
  con A1/A2/A3 (rampa) sin duplicar alertas.
- **DM3:** en días de trabajo rápido, reducir el canter del día; no sustituir el trabajo rápido por volumen de galope
  largo. Base Boston & Nunamaker [E-r], Verheyen [E-ag].
- **DM4:** subir la distancia del trabajo rápido por escalones (aviso al pasar de ≈ 500 a ≥ 700 m a velocidad de
  carrera antes de ~12–16 semanas de preparación). Base Oliveira [E], n = 42.
- Perfil informativo (no alerta): macho, primera preparación, poca distancia rápida acumulada → sugerir palpación de
  cañas. Árabes: reglas solo apoyadas en PSI [I-raza], mostrarlo.

## B. Auditoría de las fuentes de sobreentrenamiento (A9 y A10)

| Cifra en la KB (estudio ampliado 18/11) | Resultado | Fuente y acceso |
|---|---|---|
| «Caída del rendimiento del 14–19 %» | **Corregida:** el 19 % se confirma como tiempo hasta la fatiga en test estandarizado en cinta tras 6 semanas de entrenamiento intensificado (trotones); **el 14 % no aparece** en ninguna fuente leída [NV] y se retira. | de Graaf-Roelfsema E et al. 2009, *Am J Physiol Regul Integr Comp Physiol* 297:R403, doi 10.1152/ajpregu.90778.2008, [PMC4062293](https://pmc.ncbi.nlm.nih.gov/articles/PMC4062293) [E]: 15,8 ± 2,1 frente a 19,2 ± 1,6 min; Wijnberg ID et al. 2008, *J Appl Physiol* 105:1746, doi 10.1152/japplphysiol.01272.2007 ([repositorio de Utrecht](https://dspace.library.uu.nl/handle/1874/22898)) [E]: 16,1 ± 2,3 frente a 19,8 ± 0,4 min, «19 %». Países Bajos, 10 trotones analizados. |
| La variable | **Precisada:** es tiempo hasta la fatiga, no V200. En Utrecht no se publica FC ni V200; el lactato del grupo intensificado fue **más bajo** (máx. 4,3 ± 2,2 frente a 8,3 ± 1,5 mmol/L) [E]. | Mismas |
| «El VO₂max no cae» | **Confirmada** [E-ag]: 117 → 151 ± 2 mL/kg/min en control y sobrecarga; desentreno 137 (6 sem) y 134 (12 sem). | Tyler CM et al. 1996, *J Appl Physiol* 81:2244, doi 10.1152/jappl.1996.81.5.2244 (Australia, 13 trotones; texto del editor sin permiso en la sesión) |
| V200 con sobrecarga | Sin cambio: baja «sustancialmente» sin %; últimos 1200 m +4,0 % (1,7–5,8) y velocidad pico −6,9 % (4,7–8,9); FCmax y FC de recuperación sin cambio claro [E-ag]. | Hamlin 2002 (ya en la KB, `HAMLIN_2002`) |
| Peso: «precede ~3 semanas (semana 28 frente a 31)» | **Confirmada** [E-r]; **año corregido** (1999, no 1998); la ingesta no bajó; la **magnitud** (kg o %) no está en el resumen [NV]. | Tyler-McGowan CM et al. 1999, *Equine Vet J Suppl* 30:621–625, doi 10.1111/j.2042-3306.1999.tb05297.x, [PubMed 10659331](https://pubmed.ncbi.nlm.nih.gov/10659331/) |
| Umbral de A10 «> 2 % en 2–3 semanas» | **Sin base publicada**: queda como diseño [I]. Contraejemplo [E]: en Utrecht el peso **subió** (392 ± 40 → 427 ± 44 kg) en ambos grupos (caballos jóvenes en crecimiento). | Wijnberg 2008 [E] |
| Sobreentreno sin caída de rendimiento | Nueva: tras 272 d de carga creciente, rendimiento sin caída pese a signos de pérdida de peso [E-ag]. | Bruin G et al. 1994, *J Appl Physiol* 76:1908, doi 10.1152/jappl.1994.76.5.1908 (Países Bajos, 7 caballos de carreras, raza [NV]) |
| Martin 2000: 42,5 % vías altas, 9,5 % arritmias, 26 % sin diagnóstico | **Confirmadas** por recuento [E-ag]+[I]: 148/348, 33/348 y 92/348 (73,5 % con diagnóstico). Con casos mixtos: vía aérea 48,9 %, arritmias 15,8 %. | Martin BB Jr et al. 2000, *JAVMA* 216:554, doi 10.2460/javma.2000.216.554 (EE. UU., razas mixtas) |
| Ningún marcador aislado | Confirmado [E-r]: «FC de ejercicio elevada» citada sin magnitud. | McGowan CM, Whitworth DJ 2008, *Comp Exerc Physiol* 5:57, doi 10.1017/S1478061508979202 |

### B.1 Propuesta (SO1–SO3, todo [I], sin implementar)

- **SO1 (A9):** el disparador es la **caída de V200** (Hamlin [E-ag]) o del rendimiento en el trabajo de referencia;
  VHRmax y FCmax solo como apoyo (no cambian de forma clara). Elevar severidad solo si coinciden dos señales (V200 o
  rendimiento, peso, comportamiento/apetito) — McGowan 2008 [E-r]. Umbral numérico de V200 sigue sin cifra publicada.
- **SO2:** si la VLa4 sube (o el lactato pico baja) a la vez que cae el rendimiento, marcar «sospechoso», no «mejor
  forma» (Utrecht [E], trotones [I-raza]).
- **SO3 (A10):** umbral de peso declarado heurístico; en potros en crecimiento (2 años) comparar contra la tendencia
  propia de ganancia, no contra el peso absoluto (Wijnberg [E]).
- Las cifras de sobreentrenamiento son de trotones en cinta [I-raza]: la fisiología cardiovascular se transfiere, los
  valores absolutos no. Nada de esto es diagnóstico.

## Pendiente de cola (añadido)

- Verheyen 2005 (EVJ 37:442) en texto completo: HR y cortes en km por ventana; PMC12699115 (hueso subcondral y trabajo
  de alta velocidad en 2 años); Nunamaker 1990 y Cogger 2006/2008 en la fuente; DMD en árabes de llano (no hallado).
- Tyler 1996 en journals.physiology.org (posible acceso libre) y Tyler-McGowan 1999 completo: kg perdidos y
  magnitud de la caída; Hamlin 2002 completo: % de V200; Golland 2003 (Vet J).

## Resumen

- **DMD:** en PSI de 2 años, la distancia rápida corta acumulada gradualmente se asocia a menos DMD (Crawford 2021
  [E]: HR 0,89 por km a 15 m/s; Boston & Nunamaker [E-r]) y los bloques grandes y súbitos de canter o galope largo, a
  más (Verheyen 2005 [E-ag]). Edad de inicio contradictoria. Propuestas DM1–DM4 [I] para el planificador, sin
  implementar. Sin datos de árabes.
- **Sobreentrenamiento:** se corrige la cifra «14–19 %» a **19 % (tiempo hasta la fatiga, trotones)**; se corrige el
  año de Tyler-McGowan (1999); VO₂max sin cambio y Martin 2000 confirmados; el umbral de peso del 2 % es diseño.
  Propuestas SO1–SO3 [I].
- Sin cambios de lógica; motor 2.0.0-dev23, KB 1.21.0. Probado solo en local/CI; NO VERIFICADO con caballos reales.
  La fatiga ósea nunca es una predicción de lesiones.
