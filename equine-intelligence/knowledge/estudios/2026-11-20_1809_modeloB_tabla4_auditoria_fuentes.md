# Estudio horario 20/11/2026 18:09 UTC: modelo óseo B (tabla 4 y signo de b) y auditoría de las fuentes de la KB

**Base:** KB-1 1.19.0 → **1.20.0** · motor 2.0.0-dev21 → **2.0.0-dev22** · rama `claude/kb-estudio-2026-11-20-1809`
(sale de `claude/kb-estudio-2026-11-20-1709`, PR #108, el `claude/kb-*` abierto más reciente).

## Decisiones tomadas sin supervisión

1. **Encadenamiento:** había 7 PR `claude/kb-*` abiertos (#99 a #108). La rama sale del más reciente, el #108 (17:09).
2. **T1: modelo óseo B (Pan 2025 / Anwar 2026).** Es el pendiente que más bloquea el código. Se probaron rutas nuevas:
   - la API REST de Zenodo;
   - el `fullTextXML` de Europe PMC;
   - el HTML de arXiv.
3. **T2: auditoría de la integridad de las fuentes de la KB.** El subagente de sensores 2026 (Li 2026, Hall 2026, Espil
   2026) no aportó nada nuevo respecto a los estudios de las 11:10 y las 15:10: todo se quedó sin acceso o ya estaba en
   la KB. Por eso el tiempo se dedicó a la prioridad «auditoría de fuentes», aplicada a la propia base.
4. **Permisos.** En esta sesión desatendida no se concedió el permiso de WebFetch para:
   - `zenodo.org/api`;
   - `ebi.ac.uk` (Europe PMC);
   - `pmc.ncbi.nlm.nih.gov`.

   Wiley, SAGE y PubMed devolvieron error. No se esquivó ningún bloqueo: ni curl, ni caché, ni espejos. Un espejo de
   terceros de arXiv (deeppaper) fue rechazado y no se insistió.
5. **Motor:** solo cambian las versiones. El dt y el solver del modelo B siguen [NV], así que no hay nada cerrado en
   texto completo que se pueda programar.
6. Se usaron 2 subagentes en paralelo, de unos 7 min cada uno, y su trabajo se revisó en el hilo principal.

## T1. Modelo óseo B: lo nuevo y lo que sigue abierto

| Dato | Valor | Fuente | Etiqueta |
|---|---|---|---|
| Unidad temporal | Día: tasas en mm/día y ciclos en día⁻¹; los ciclos por día salen de la velocidad y la distancia diarias (ap. A.3–A.4, ec. 14–15 y 17) | Anwar et al., arXiv [2603.22680v1](https://arxiv.org/html/2603.22680v1) | [E] (ya en la KB 1.10.0; reconfirmado) |
| Paso del integrador y método numérico | No figuran en el preprint de Anwar ni en el bioRxiv de Pan | Zenodo [10.5281/zenodo.19173866](https://doi.org/10.5281/zenodo.19173866) / [16557014](https://doi.org/10.5281/zenodo.16557014) | [NV] |
| Licencia y lenguaje del código | El preprint es CC BY 4.0; el código no se ha visto | Ídem | [E] preprint / [NV] código |
| **Tabla 4 exacta** (preparación final; programas rápido-ligero, moderado y alto volumen) | f_BM mín. 0,858 / 0,864 / 0,867<br>f_BM máx. 0,926 / 0,931 / 0,935<br>D* mín. 0,401 / 0,460 / 0,517<br>D* máx. 0,813 / 0,913 / 1,016<br>canter a 7,5 m/s: 126 / 138 / 146 km<br>trabajo a 11,8–16 m/s: 8,9 / 16,6 / 26,0 km<br>daño formado: 0,236 / 0,374 / 0,512<br>daño reparado: 0,184 / 0,236 / 0,288 | Anwar, preprint v1, tabla 4 | [E] |
| 0,911 frente a 0,852 | 0,911 aparece en las tablas 7 y 8 y en el §3.4; 0,852 solo en la Discusión. Es una incoherencia interna del preprint, no un cambio de versión. Se mantiene 0,911 | Ídem | [E] |
| Signo de b | Anwar (tabla 9) da b = −0,02; el bioRxiv de Pan escribe «b = 0,02» sin signo (ecuaciones en imagen) | Pan, bioRxiv [10.1101/2025.04.06.646486](https://www.biorxiv.org/content/10.1101/2025.04.06.646486.full.pdf); Anwar, tabla 9 | [E] (lectura parcial de Pan) |
| Condiciones iniciales | f_BM = 0,61 y D* = 0 en las simulaciones (0,7 en el análisis de sensibilidad) | Pan, bioRxiv | [E] (ya en la KB) |
| Versión de RSOS (13:260818, PMC13641913) | No se pudo abrir. No se sabe si corrige la tabla 4 o la 7 | doi 10.1098/rsos.260818 | [NV] |

**Lectura para el motor [I]:**
- La tabla 4 se guarda entera como vector de validación. Es el parámetro `modelo_b_tabla4_anwar_preprint`, con estado
  `VALIDACION`.
- Cuando se conozca el dt, la implementación del modelo B tendrá que reproducir esa tabla con una tolerancia que
  habrá que fijar, por ejemplo ±2 % en D* máx. [I].
- No se programa nada hasta tener el código de Zenodo y la comparación con la versión de RSOS.
- El signo de b es una incertidumbre pequeña: un 1,6 % en S_v con f = 0,61, calculado en la KB 1.8.0. Se resolverá con
  el código.
- La fatiga ósea es un índice de carga y **nunca una predicción de lesiones**.

## T2. Auditoría de la integridad de las fuentes de la KB

Se hizo un recorrido automático de las 221 entradas de `fuentes`, agrupando por DOI (o por el DOI contenido en la URL) y
comprobando los campos obligatorios (`acceso`, `verificado_fecha`, `pais`, `idioma`, `raza_fuente`).

**Hallazgos [E]** (sobre la propia base):
- **15 obras aparecen más de una vez.** Son 13 por DOI, más Pan 2025 y Anwar 2026 con URL de preprint. En total, 17
  entradas sobran.
- **Algunas duplicadas tienen un `acceso` incoherente** entre sus entradas:

  | Obra | Una entrada | Otra entrada |
  |---|---|---|
  | McSweeney 2025/2026 (JAVMA 10.2460/javma.25.04.0268) | `AGREGADOR` | `TEXTO_COMPLETO` |
  | Schrurs 2024 | `RESUMEN` (dos entradas) | `TEXTO_COMPLETO` |
  | Paksoy 2025 | `RESUMEN` | `TEXTO_COMPLETO` |
  | Kobayashi 2000 | `AGREGADOR` | `RESUMEN` |
  | Hada 2006/2007 | `AGREGADOR` | `RESUMEN` |
  | Takahashi 2021 | `AGREGADOR` | `RESUMEN` |
  | Dąbrowska 2026 | `TEXTO_COMPLETO_PARCIAL` | `RESUMEN` |

  Otros pares tienen el mismo `acceso` y solo duplican la referencia: Morrice-West 2020 (EVJ 13156), Choi & Parkin
  2025, Ikeda 2019, Mukai 2007, Nielsen 2006 y Legg 2025/2026.
- **52 fuentes no tienen alguno de los campos obligatorios.** En 49 de ellas falta el propio `acceso`. Son sobre todo
  entradas antiguas, anteriores a la KB 1.5, como `PAN_2025`, `ANWAR_2026`, `PFAU_2022`, `NIST_CUSUM` y
  `FRANCE_GALOP_2024_LON`.

**Correcciones aplicadas (sin borrar ninguna entrada, porque las reglas y los estudios citan los id):**
- En cada duplicado se añade `duplicado_de` con el id canónico, que es el de mejor acceso, y una `nota_auditoria`.
- Los campos que faltaban se completan como `acceso: SIN_AUDITAR` y `[NV]`. Así queda explícito y no se presenta como
  verificado lo que no se ha releído.
- `PAN_2025` y `ANWAR_2026` se clasifican como `PREPRINT` (Australia, PSI), porque sí se leyeron hoy.
- Se propone el pendiente AU1 [I]: las reglas nuevas citan la fuente canónica, y ninguna fuente `SIN_AUDITAR` puede
  servir de base a un cambio de lógica. Habrá una prueba al empaquetar la KB.

**Otras correcciones menores:**
- Li 2026 (EVJ 10.1002/evj.70360) es probablemente una revisión sobre caballos de deporte, según el título en PubMed
  43035340 [E-r]. No es aplicable a PSI ni a árabes de llano hasta leerla.
- Hall 2026 (StrideSAFE) [E-r, agregador]: 23 caballos con fractura condilar (54 carreras) más 31 con fractura
  sesamoidea (90 carreras) suman 54, pero la reseña habla de 53 fracturas. La explicación probable es un caballo con
  las dos lesiones [I].
- Espil 2026 (fracturas pélvicas, California, 1992–2018) [E-r]: es una serie de necropsias, no un estudio de sensores.
  No hay datos nuevos sobre los que ya tenía la KB.
- No hay árabes en ninguno de estos tres estudios.
- No se hallaron estudios de sensores en árabes de llano publicados entre septiembre y noviembre de 2026. La búsqueda
  fue rápida y no es concluyente [NV].

## Cola y pendientes añadidos
- **Cola:** reclasificar a mano las fuentes `SIN_AUDITAR`, empezando por las citadas por reglas `IMPLEMENTADO`.
- **Cola:** Zenodo y Europe PMC por API desde una sesión con permiso de WebFetch, para cerrar dt, solver, licencia,
  lenguaje y el signo de b.
- **Cola:** Li 2026, para confirmar que es una revisión y ver si incluye PSI o árabes de llano.
- **Pendiente:**
  - AU1, descrito arriba.
  - En el modelo B se añade la tabla 4 como vector de validación y el signo de b por confirmar.

## Resumen
- **Lógica:** sin cambios.
- **Modelo óseo B:** sigue bloqueado por el dt y el solver, que no están publicados en el texto y no se han podido
  leer en Zenodo por falta de permiso.
- **Tabla 4:** la del preprint de Anwar queda como vector de validación exacto.
- **0,911 frente a 0,852:** se confirma que es una incoherencia interna del preprint.
- **Signo de b:** se anota que difiere entre Pan y Anwar.
- **Auditoría de fuentes:**
  - Hay 15 obras duplicadas (17 entradas marcadas con `duplicado_de`) y 7 de ellas tienen un `acceso` incoherente
    entre sus entradas.
  - Hay 52 fuentes con campos obligatorios ausentes, que ahora figuran como `SIN_AUDITAR` o `[NV]`.
  - Se propone AU1.
- **Validación:** pruebas locales y CI; nada se ha verificado con caballos reales.
