# Auditoría mecánica · AVO GIRTH PCB REV B en la cápsula REV 5.8.1

**Fecha:** 2026-10-29 · **Rama:** `audit/avo-girth-pcb-revb` (HEAD `82b9609`) · **Estado de la placa:** sin fabricar.

**Alcance:** encaje de la PCB de 65,5 × 43,5 × 1,0 mm (4 capas) en la cápsula, antes de fabricar el prototipo.

## Qué se ha revisado

**Herramienta:**
- `mecanica.py` (Python 3 con numpy, scipy y matplotlib) → `mecanica_salida.txt`, `plano_planta.png` y `corte_vertical.png`.
- trimesh y shapely no se pudieron instalar: el proxy bloquea PyPI con un 403. Por eso el script lee las STL, las corta por planos y lanza rayos con rutinas propias en numpy.
- Ejecución: unos 10 s con `python3 mecanica.py`.

**CAD de la cápsula:** se ha usado `hardware/girth/REV5` de esta rama.
- Su README la marca como **REV 5.8.1 (actual)**.
- Se ha comparado con la rama más nueva, `origin/feature/girth-rev5-8-1-curvas` (`7ab072a`, 2026-10-28):
  - `avo_girth_rev5.py` y todas las STL son idénticos;
  - solo cambian las fechas de los STEP y 3 renders.
- Las otras ramas (`girth-rev5-8-cierres`, `girth-rev5-7-cama`) son anteriores.
- Las piezas se han tomado en posición de montaje (`out/montaje/*.stl`) y las referencias de `out/ref_*.stl`.

**Placa:** se ha medido de forma independiente del `.py`:
- `out/C3/KiCad/AVO_GIRTH_PCB.kicad_pcb`: Edge.Cuts, huellas, patios, F.Fab y zonas;
- `out/C3/AVO_GIRTH_PCB_C3_GERBER_JLCPCB.zip`: Edge_Cuts, las 4 capas de cobre y el fichero `.gbrjob`.

Del `.py` solo se toman las alturas de huella (`FP[*].height`) y las constantes, para compararlas.

**Escenarios de altura:**
- **A**: como pide la PCB. La placa queda en z 7,80…8,80, con la cuna subida 0,6 mm.
- **B**: CAD 5.8.1 sin cambios. La placa apoya en la cuna medida, z 7,15…8,15.

**Niveles de validación:**
- **VMH**: verificado mediante herramienta (medido sobre STL, KiCad o Gerber por el script).
- **VPC**: verificado por cálculo (fórmula y datos indicados).
- **RD**: revisado documentalmente.
- **PVF**: pendiente de validación física.
- **NO VERIFICADO**: no se puede comprobar con los ficheros.

---

## Veredicto

**Con el CAD 5.8.1 la placa no se puede montar con la tapa cerrada.**

La placa en sí está bien: el contorno, las muescas, la ranura y la banda sin cobre coinciden entre KiCad, Gerber y el `.py`. El problema es la cápsula:
- La **tapa choca** con J2, U4 y U6 (y en A también con D13 y C25), hasta **2,50 mm** en A y 1,85 mm en B.
- En A, además, el **labio de la tapa invade la placa 0,55 mm**.
- Con la tapa levantada, la **junta TPU no se comprime** (le faltan 0,40 mm), así que **la cápsula no queda estanca**.
- Con la tapa actual, la **antena FPC no cabe** en la banda sin cobre. Ni siquiera quitando los postes cabe, porque la columna Ø7 del inserto M3 en (21; 20,5) también estorba.

Los cambios del README («Cambios mecánicos») van en la buena dirección, pero **les faltan cosas**: ver la tabla de la sección 3.

## 1. Resumen de comprobaciones

| # | Comprobación | Resultado (números de `mecanica_salida.txt`) | Nivel |
|---|---|---|---|
| 1 | Contorno de la placa | **65,500 × 43,500 mm** en KiCad y en Gerber. Desviación KiCad↔Gerber 0,0000 mm; .py↔KiCad 0,0010 mm. Esquinas R6,25, 8 muescas R3,60, ranura 1,60 × 3,40 en (−29,00; 4,60). Espesor 1,00 mm (KiCad y gbrjob), 4 capas, ENIG. Las 98 huellas están en F.Cu y su posición y giro coinciden con el `.py`. | VMH |
| 2 | Holgura lateral con la base | 0,148–0,150 mm a la pared interior en todo el perímetro, sin puntos dentro de material, en cortes a 3 alturas (A y B). | VMH |
| 3 | Muescas frente a tornillos y columnas | Las 8 muescas están centradas (error 0,00) en las 8 columnas. Holgura radial a la columna Ø5,60 de la base: **0,80 mm**. A la columna Ø7,00 de la tapa: **0,10 mm**, pero esta empieza en z 9,00, por encima de la cara superior de la placa (8,80 en A). | VMH |
| 4 | Ranura del cable de la batería | La cuna tiene el paso del cable en la pared −X, en **Y 7,95…14,90**; la ranura de la placa está en **Y 2,90…6,30**. El cable tiene que bajar por el pasillo entre la cuna y la pared: **2,11 mm** libres junto a la columna (−31,5; 10) y 6,31 mm a la altura de la ranura. Debajo de la ranura no hay nada hasta el suelo (z 2,60). J2 queda a 5,09 mm de la ranura. | VMH (el paso del conector JST por la ranura: **NO VERIFICADO**, no hay medidas de la clavija) |
| 5 | Apilado vertical | Techo de la tapa z **13,20** (= `Z_CEIL`). Batería z 2,65…6,95. Cuna z **7,15**. **A:** placa 7,80…8,80, libre encima 4,40 mm, bajo la placa 0,85 mm. **B:** placa 7,15…8,15, bajo la placa 0,20 mm. Lo más alto es J1, que llega a z 12,10 en A (1,10 mm de margen al techo); después J2 (1,45) y U4 (1,80). | VMH (alturas de `FP.height`; modelos 3D reales: **NO VERIFICADO**) |
| 6 | Piezas bajo postes y labio | **A:** J2 −2,50 · U4 −2,15 · U6 −1,00 · D13 −0,65 · C25 −0,15 mm, igual con el patio que con el cuerpo (F.Fab). Labio z 8,25 sobre 177,6 mm² de borde: **−0,55**. **B:** J2 −1,85 · U4 −1,50 · U6 −0,35 · D13 0,00. | VMH |
| 7 | USB-C (J1): abertura | **La cápsula no tiene abertura**: el rayo +X desde la boca atraviesa toda la pared (tapa en X 31,55). Hay que abrir la tapa para enchufar el cable. | VMH |
| 8 | USB-C (J1): acceso con la tapa quitada | Boca en X 29,80, a 2,95 mm del borde de la placa y a **3,10 mm** de la cara interior de la base. En A, el eje queda a z 10,45, solo **1,45 mm** por encima de la pared de la base (z 9,00). | VPC + **PVF** |
| 9 | USB-C (J1): patas del blindaje | Hueco bajo la placa: 0,85 mm (sobre la batería) y 0,65 mm (sobre la cuna, X 27,20) en A; **0,20 y 0,00 mm** en B. La longitud real de las patas es **NO VERIFICADO**. | VMH |
| 10 | Reed frente a SW1/SW2 | SW1 (−1,27; −17,80) y SW2 (1,27; −17,80) quedan justo encima del cuerpo del reed (Y −20,90…−17,70). El alojamiento del suelo llega a X ±8,15. Hay paso libre de Y −21,85 a −16,50 entre la cuna y la pared. Del extremo del reed al pad hay unos 7,8 mm en línea recta. | VMH |
| 11 | Bobina Qi frente a L1/L2 | Canal de los hilos: Y −6,00…−4,05, X −30,95…−10,00. Paso por la pared de la cuna: Y −6,50…−0,55. L1 (−28,60; −5,20) cae sobre el canal y L2 (−28,60; −2,00) sobre el paso de la cuna. Entre la bobina y la placa solo está la batería (a 0,35 mm de la bobina). Encima de la bobina hay 20 piezas, entre ellas U5, U7, U2 y U3. | VMH |
| 12 | Antena FPC frente a la banda sin cobre | Banda X −3,30…25,50, Y 12,60…22,75; ninguna pista, vía ni pad en las 4 capas de cobre. La FPC del CAD está en X −21…7, Y −7,5…−1,5: **0 mm² sobre la banda** y encima de U1, U2… Una FPC de 28 × 6 pegada al techo dentro de la banda **choca** con los postes (14; 15,5) y (−3; 16,5) y con la **columna Ø7 del inserto M3 (21; 20,5)**. No hay ninguna posición válida sin cambiar la tapa. | VMH |
| 13 | Imanes frente a U7 (MMC5983MA) | Distancias a U7: 26,8 mm (cápsula, −X+Y), 27,5 mm (soporte) y 30,6 mm (imanes del reed). Campo estimado: **406 µT** con la polaridad del README; **555 µT** con 3 imanes por esquina; **918 µT** en el peor caso, por encima de los ±800 µT del sensor. | VPC (modelo de dipolo, N35) + **PVF** |
| 14 | Imanes frente al reed | El imán de la cápsula más cercano está a 28,98 mm del reed; los del soporte, a 3,2–6,1 mm. | VMH (el disparo indebido es **PVF**) |
| 15 | Sujeción y vibración | La placa solo apoya en el anillo de la cuna: 155,8 mm², un 6,1 % de su superficie. Vano interior **51,2 × 30,9 mm** sobre la batería, con puntos a 15,6 mm del apoyo más cercano y voladizos de 5,7 mm en las esquinas. **Nada la aprieta desde arriba**: el labio queda a 0,10 mm (B) y los postes a 0,45 mm (A) o 1,10 mm (B). | VMH + **PVF** |
| 16 | Junta TPU y cierre | La junta va en una ranura de 1,4 mm (Y 22,80…24,20) y queda de Y 22,90…24,10 a z 8,00…9,00. La tapa asienta sobre la base a z 9,00 (tope rígido): compresión fija del 29 %, **siempre que la tapa asiente**. Con las interferencias de la fila 6 la tapa queda levantada 2,50 (A) o 1,85 mm (B) y la compresión pasa a **0** (**SIN SELLADO**). | VMH (estanqueidad: **PVF**) |

## 2. Detalle y evidencias

### 2.1 Contorno y holguras laterales (VMH)
- El contorno de KiCad y el del Gerber son el mismo: área 2582,3 mm², caja X/Y ±32,75 / ±21,75.
- El `gbrjob` declara 65,60 × 43,60 porque incluye la línea de 0,1 mm.
- La holgura de 0,15 mm por lado deja la placa bien centrada por los cuatro lados.
- Si la placa sale de fábrica con una tolerancia de contorno peor de −0,15/+0,15, **roza**. Fresado típico de JLCPCB ±0,2 mm (dato externo): comprobar con la placa real (**PVF**).

### 2.2 Apilado vertical (VMH)

| Elemento | Z (mm) |
|---|---|
| Suelo | 2,60 |
| Batería (referencia) | 2,65…6,95 |
| Cara superior de la cuna (CAD) | **7,15** |
| Placa (A) | 7,80…8,80 |
| Labio de la tapa (CAD) | **8,25** |
| Postes de la tapa | 9,25 |
| Pared de la base y asiento de la tapa | 9,00 |
| Techo | 13,20 |

- El README dice «quedan 4,1 mm sobre la placa»: es la cifra neta (H_MAX = 4,40 − 0,30 de margen). Es coherente.
- En el escenario B la placa quedaría a solo **0,20 mm** de la batería. LP403048 es una celda de bolsa (*pouch*), así que cualquier hinchamiento la apoya en la placa y en las patas del USB-C. Ese margen tampoco cumple la intención del diseño (0,85 mm en A).

### 2.3 Elementos de la tapa sobre la placa (VMH)

| Elemento de la tapa (CAD 5.8.1) | Centro | z inferior | Choca en A | Choca en B |
|---|---|---|---|---|
| Labio perimetral (banda de 1,2 mm) | borde | 8,25 | **placa −0,55** | no (0,10) |
| Poste de la Qi | (−26,50; 6,70) | 9,25 | **J2** | **J2** |
| Poste de la Qi | (−11,50; 6,70) | 9,25 | **D13** | (0,00) |
| Poste del C6 | (9,86; −9,70) | 9,25 | **U4** | **U4** |
| Poste del C6 | (25,70; −9,70) | 9,25 | **U6** | **U6** |
| Poste de la cama | (17,0; −15,0) | 9,25 | **C25** | no |
| Postes de la cama | (−3; −18,9), (−17; −16), (14; 15,5), (−17; 16), (−3; 16,5) | 9,25 | no; ninguno apoya en la placa (0,45 mm) | no (1,10 mm) |
| Tope del USB del C6 | (17,70; 8,10), 5,8 × 3,8 | 12,51 | no (3,71 mm); ya no tiene función | no |
| Rebaje de la antena FPC (0,4 mm) | X −21,5…7,5, Y −8…−1 | 13,6 | en el sitio equivocado (ver 2.6) | |

- R11 y R45 quedan con **0,05 mm** de margen bajo los postes en A. Con postes nuevos, mantenerlos alejados.
- El centro del pad SW1 (pad de hilo) queda a unos 0,85 mm del borde del poste Ø2,4 en (−3; −18,9). Es un cálculo con las coordenadas de KiCad y del CAD. La altura de la soldadura del hilo es **NO VERIFICADO**.

### 2.4 USB-C J1 (VMH + VPC + PVF)
- No hay abertura en la cápsula, por diseño («USB-C dentro»): **para programar hay que abrir la tapa**.
- Con la tapa quitada, la boca queda 3,10 mm dentro de la pared de la base. La pared mide 3,6 mm (X 32,9…36,5) y su cara superior queda 1,45 mm por debajo del eje del USB.
- Por cálculo, entrando horizontalmente solo cabe un sobremoldeado de **≤ 2,9 mm de alto** (2 × 1,45), o uno cuyo frente quede a más de 6,7 mm de la boca.
- La carcasa metálica de una clavija USB-C ya mide unos 2,4–2,6 mm (especificación USB Type-C; dato externo).
- **Un cable normal seguramente no entra**: probar con el cable real, o usar uno acodado hacia arriba (**PVF**).
- Patas del blindaje: las de X 27,20 caen fuera de la cuna, sobre la base, a 0,65 mm en A. Las de X 23,02 caen sobre la batería, a 0,85 mm.
- La longitud de las patas no está en el repositorio: no hay modelo 3D del TYPE-C-31-M-12 ni en el STEP de la placa (**NO VERIFICADO**). Cortarlas a ras si sobresalen más de 0,5 mm.

### 2.5 Cables (VMH)
**Batería:**
- La pared −X de la cuna tiene dos huecos: Y −6,50…−0,55 (hilos de la bobina) y Y 7,95…14,90 (batería).
- Desde Y 7,95…14,90 hasta la ranura (Y 2,9…6,3) el cable baja por el pasillo exterior de la cuna. Su punto más estrecho es **2,11 mm**, junto a la columna (−31,5; 10). Cabe un cable de 2 hilos de JST SH.
- Que el conector pase por la ranura de 1,6 × 3,4 es **NO VERIFICADO**: las medidas de la clavija no están en el repositorio. Si no pasa, hay que crimpar después de pasar el cable.
- La posición real de las salidas de la celda es **NO VERIFICADO**: la batería de referencia es una caja.

**Bobina:** el canal del suelo acaba en X −30,95 y L1/L2 están en X −28,60, encima del canal y del hueco de la cuna. Bien.

**Reed:** SW1 y SW2 están encima del alojamiento del reed (X ±8,15). Los hilos suben en vertical por el hueco Y −21,85…−16,50. Bien.

### 2.6 Antena FPC (VMH)
- En el cobre, la banda sin cobre está limpia: 0 trazos y 0 destellos en F.Cu, In1.Cu, In2.Cu y B.Cu, y ningún pad dentro.
- Ojo: la zona de KiCad **permite pads y huellas**. Si alguien coloca una pieza ahí, el DRC no la para.
- La banda llega hasta Y 22,75, pero el techo útil de la tapa acaba en Y **20,56** (pared interior).
- Con postes nuevos fuera de la banda:
  - una FPC de **28 × 6** en Y 12,6…18,6 sigue invadiendo la columna Ø7 del inserto M3 (21; 20,5), que baja hasta Y 17,0 (6,8 mm² de solape, VMH);
  - para que no la toque hace falta una FPC de **≤ 4,4 mm de ancho** (Y 12,6…17,0), o una de 6 mm que acabe en **X ≤ 17,5** (≤ 20,8 mm de largo) (VPC).
- La antena real no está definida en el repositorio: la de 28 × 6 × 0,3 es la referencia del CAD.
- Hueco antena–placa: 4,10 mm en A.
- La posición del conector W.FL/MHF III del módulo y el recorrido del cable coaxial son **NO VERIFICADO**: la huella no lo marca y el STEP del módulo es un ensamblaje que el script no resuelve.

### 2.7 Imanes y magnetómetro (VPC + PVF)
- Posiciones medidas en las STL:
  - 4 imanes de la cápsula en (±28,9; ±18,3), z 0,32…1,32;
  - 4 del soporte (2 apilados) en z −2,02…−0,02;
  - 3 del reed en X −5,1 / 0 / +5,1, Y −19,3.
- El sensor U7 está en (−5,0; 9,6), a z ≈ 9,30 (A). Le quedan cerca el imán de la cápsula (−28,9; 18,3), a 26,8 mm, y el del soporte, a 27,5 mm.
- Modelo de dipolo (hipótesis N35, Br 1,2 T, la misma que el README de REV 5):

  | Disposición | |B| en U7 |
  |---|---|
  | Diagonales opuestas, como pide el README | 308–406 µT |
  | Con 3 imanes por esquina, como admite el alojamiento | 465–555 µT |
  | Todos con la misma polaridad | 569 µT |
  | Todos con la misma polaridad y 3 por esquina | **918 µT**, por encima de ±800 µT (±8 G) del MMC5983MA (hoja de datos) |

- El README de REV 5 da unos 40 µT para el BNO **en el centro**. Esa cifra no vale para U7, que está 10 mm más cerca de la esquina −X+Y.
- Es un desvío fijo (*hard-iron*) mientras la cápsula esté en el soporte. Se calibra, pero **hay que respetar la polaridad y no apilar 3 imanes** en esa esquina.
- Medir con la placa real (**PVF**). Un imán de grado más alto (N52) sube el campo en un 20 % aproximadamente (proporcional a Br).
- El material de los tornillos M3 (acero o inoxidable) no está en el CAD (**NO VERIFICADO**). El más cercano a U7 está a unos 19 mm.

### 2.8 Sujeción y vibración (VMH + PVF)
- El CAD no muestra ningún elemento que **sujete** la placa. Abajo apoya solo en el anillo de la cuna (1 mm de pared). Arriba, el labio queda a 0,10 mm (B), o a 0,05–0,10 mm con los cambios 1 y 2 del README, y los postes no tocan.
- Resultado: la placa con el módulo y la batería debajo **puede vibrar** dentro de un juego de unas décimas. Con un caballo al trote o al galope eso es fatiga en las soldaduras de J1 y J2 y ruido en la IMU.
- Además, el vano interior de 51,2 × 30,9 mm no tiene apoyo intermedio: solo la batería, a 0,85 mm por debajo.
- Zonas del anillo de la cuna libres de piezas (con 1,5 mm de margen) y fuera de la banda de la antena, donde un poste puede apretar la placa **contra la cuna** sin flexarla:
  - X −26,6…−10,6, Y ≈ −16;
  - X −3,6…7,6, Y ≈ −16;
  - X 18,8…26,6, Y −16,4…−13,4;
  - X ≈ 26,2, Y 7…11;
  - X −26,6…−15,2, Y ≈ 16.

### 2.9 Junta (VMH + PVF)
- La geometría es correcta: junta de 1,2 mm en una ranura de 1,4 × 1,0, altura libre 1,4 mm y tope rígido a z 9,00, lo que da un 29 % de compresión.
- La placa no toca la junta: queda separada por la pared de 3,6 mm de la base.
- El riesgo para la estanqueidad está en las interferencias de la sección 2.3: si la tapa no asienta, la junta no trabaja.
- Las 8 entradas de tornillo atraviesan el fondo por dentro de la junta. Las sellan las juntas tóricas 3 × 1 bajo la cabeza, según el README de REV 5 (RD).
- IP67: no probado (**PVF**).

## 3. Desajustes y cambios de CAD necesarios

Para cada cambio, la última columna dice si está en el README de la PCB, en «Cambios mecánicos».

| # | Cambio en el CAD de la cápsula (REV 5.9 propuesta) | Evidencia | ¿En el README? |
|---|---|---|---|
| C1 | **Cuna +0,6 mm** (cara superior 7,15 → 7,75) | Escenario A sin apoyo (0,65 mm de hueco); B deja 0,20 mm a la batería y 0,00 mm a las patas del USB en X 27,2 | Sí (1). Correcto |
| C2 | **Labio de la tapa +0,6 mm** (cara inferior 8,25 → ≥ 8,85) | Invade 0,55 mm en 177,6 mm² | Sí (2). Correcto |
| C3 | **Quitar los 2 postes del C6** (9,86; −9,70) y (25,70; −9,70) | Chocan con U4 (−2,15) y U6 (−1,00) | Parcial: «postes de la tapa» (5) sin decir cuáles |
| C4 | **Quitar los 2 postes de la Qi** (−26,50; 6,70) y (−11,50; 6,70) | Chocan con J2 (−2,50) y D13 (−0,65) | Parcial (5) |
| C5 | **Quitar o mover los 6 postes de la cama**. Ninguno apoya en la placa; (17; −15) choca con C25 (−0,15); (14; 15,5) y (−3; 16,5) estorban a la antena | Ver 2.3 y 2.6 | Parcial (5) |
| C6 | **Postes nuevos que aprieten la placa contra el anillo de la cuna**, en las zonas libres de 2.8, a ras de la cara superior (z 8,80 con C1) | No hay sujeción vertical (2.8) | Parcial: pide que «apoyen en zonas libres», sin posiciones |
| C7 | **Quitar el tope del USB del C6** (17,7; 8,1) | Ya no tiene función (3,71 mm sobre la placa) | **No** |
| C8 | **Mover el rebaje de la antena** de X −21,5…7,5, Y −8…−1 a la banda (Y ≥ 12,6) | La antena del CAD queda sobre U1 y U2, fuera de la banda | Sí (4), sin mencionar el rebaje |
| C9 | **Antena dentro de la banda sin tocar la columna Ø7 (21; 20,5)**: FPC de ≤ 4,4 mm de ancho, o de 6 mm acabada en X ≤ 17,5, o mover la banda y la antena | Una de 28 × 6 no cabe (6,8 mm² de solape) | **No** |
| C10 | **Quitar la bandeja** del conjunto | Ocupa 1890 mm² del sitio de la placa (z 7,20…10,40) | Sí (6) |
| C11 | Rebaje del relé: no hace falta (no existe en 5.8.1) | | Sí (7). Correcto |
| C12 | **Acceso al USB-C**: decidir el procedimiento (cable acodado, sobremoldeado ≤ 2,9 mm, o sacar la placa) y probarlo | La boca está 3,1 mm dentro de una pared de 3,6 mm, con el eje 1,45 mm sobre ella | **No** |
| C13 | Cable de la batería: mover el paso de la cuna (Y 7,95…14,90) hacia la ranura (Y 2,9…6,3), o aceptar el pasillo de 2,11 mm junto a la columna (−31,5; 10) | 2.5 | Parcial (3: solo da la posición de la ranura) |
| C14 | Imanes: mantener las diagonales opuestas y como mucho 1 imán por esquina en la cápsula (el alojamiento admite 3) | 918 µT en el peor caso > rango de U7 | **No** |

Con C1, C2, C3–C5 (y C6) y C7 el apilado cierra en el escenario A. Lo más alto, J1, queda a 1,10 mm del techo y la junta vuelve al 29 %. Esto es una deducción a partir de los números de este informe: hay que confirmarlo regenerando el CAD y repitiendo `mecanica.py` con la REV nueva.

## 4. Pendiente de validación física
1. Contorno real de la placa frente a la holgura de 0,15 mm por lado.
2. Longitud de las patas del blindaje de J1 bajo la placa (hueco de 0,65–0,85 mm en A).
3. Enchufar el cable USB-C real con la tapa quitada.
4. Pasar el conector de la batería por la ranura de 1,6 × 3,4 mm, y polaridad.
5. Campo en U7 con los imanes montados (polaridad y número por esquina) y saturación del MMC5983MA.
6. Que el reed no se dispare con los imanes de la cápsula (a 29 mm).
7. Vibración: juego vertical de la placa con los postes nuevos.
8. IP67: 1 m durante 30 min.
9. Hueco real entre la batería y la placa, con la celda cargada (hinchamiento).

## 5. Observaciones documentales (RD)
- `AVO_GIRTH_PCB_C3_REPORTE.md` (línea 149) y `fuente/gate.py` (línea 165) dicen «U.FL / MHF I». El README y `DOCS/INFORME_REV_B.md` dicen «W.FL / MHF III». El correcto es el segundo para el C3-MINI-1U: corregir el texto de la puerta.
- El `gbrjob` declara `"Revision": "A"`, pero la placa es la REV B.
- El README de la PCB (cambio 1) da la cuna a z 7,75, mientras que `Z_PCB_BOTTOM` = 7,80. Los 0,05 mm de diferencia son coherentes como holgura, pero conviene escribir una sola cifra.

## 6. Ficheros
- `hardware/girth/PCB/AUDITORIA_REV_B/mecanica/mecanica.py`: el script.
- `hardware/girth/PCB/AUDITORIA_REV_B/mecanica/mecanica_salida.txt`: su salida completa.
- `hardware/girth/PCB/AUDITORIA_REV_B/mecanica/plano_planta.png`: planta con:
  - el hueco entre la tapa y la placa (A);
  - los patios que chocan, en rojo;
  - los postes, las columnas y la banda de la antena;
  - la bobina, el reed y los imanes.
- `hardware/girth/PCB/AUDITORIA_REV_B/mecanica/corte_vertical.png`: cortes en Y −9,7 (postes del C6 sobre U4 y U6) y Y 6,7 (poste de la Qi sobre J2).
