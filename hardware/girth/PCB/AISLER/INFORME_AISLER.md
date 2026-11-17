# AVO GIRTH PCB REV B (ESP32-C3): paquete ODB++ para AISLER

| | |
|---|---|
| Diseño de partida | rama `feature/avo-girth-pcb`, commit `2a703697abf613d9128fc1a258e179d274a839ee`, placa `hardware/girth/PCB/out/C3/KiCad/AVO_GIRTH_PCB.kicad_pcb` (SHA-256 `b0064f31…f91b0`) |
| Rama de trabajo | `export/avo-girth-aisler`, derivada de ese commit. La rama `feature/avo-girth-pcb` y los ficheros entregados no se han tocado |
| Herramienta | KiCad **9.0.9** (imagen oficial `kicad/kicad:9.0`, GitHub Actions): `kicad-cli pcb export odb --units mm --precision 4 --compression zip` |
| **Fichero para subir a AISLER** | **`AVO_GIRTH_PCB_REV_B_AISLER_ODB.zip`** (ODB++ en ZIP, que es el formato que pide AISLER). SHA-256 `d3c662b20a068fd0c84dc8bd65da67e5fa56c3b11528d016734febb7cee3ed03` (CI de `779eefa`, run 40960122600) |
| Evidencias | `hardware/girth/PCB/AISLER/resultados_ci/` (CI `export-girth-aisler.yml`; el commit y la ejecución están en `ORIGEN.txt`) |
| Pedidos | ninguno |

## 1. Resultado

**El ODB++ es válido y reconoce 85 componentes para montar**, todos SMT y en la cara superior:

- tiene 98 componentes en total, uno por huella;
- 13 llevan el atributo `.no_pop` (no montar): **C5** (DNP del diseño), los puntos de prueba **TP1–TP8**, los pads del
  hilo de la bobina Qi **L1/L2** y los del reed **SW1/SW2**;
- la posición y el giro de cada componente coinciden **exactamente** (error 0,000 mm, 98/98 giros) con la placa REV B
  y con el CPL de JLCPCB entregado (85/85).

Hay que tener en cuenta **tres cosas antes de pedir** (sección 5):
1. **AISLER no tiene 1,0 mm en 4 capas** en su catálogo estándar, solo 0,8 y 1,6 mm.
2. **AISLER fabrica las PCB de 3 en 3**: 5 no es posible, serían 6 (o 3).
3. Las **4 ranuras metalizadas del USB-C J1** (0,6 mm de ancho) están por debajo del mínimo de AISLER (0,7 mm).

## 2. Qué se ha cambiado en la copia exportada (y qué no)

El ODB++ sale de una **copia** del proyecto (`AISLER/kicad/`), generada con `AISLER/preparar_aisler.py`. El CI vuelve a
ejecutar el script y comprueba que da exactamente los mismos ficheros (`resultados_ci/diferencias_copia.txt` vacío).

| Cambio | Motivo |
|---|---|
| TP1–TP8, L1, L2, SW1, SW2: atributos `dnp`, `exclude_from_pos_files` y `exclude_from_bom` (en la placa), y `dnp yes` + `in_bom no` (en el esquema) | El exportador ODB++ de KiCad 9 escribe **todas** las huellas en el fichero de componentes. Solo marca «no montar» (`.no_pop`) las que tienen DNP; los atributos «excluir de BOM/posiciones» no los usa (código fuente de KiCad 9.0: `pcbnew/pcb_io/odbpp/odb_component.cpp`). AISLER toma de ahí qué montar. Sin este cambio vería 97 piezas en vez de 85 |
| Cajetín de la placa: revisión «A» → «B» | La placa es la REV B; el cajetín arrastraba «A» desde la REV A |
| En las 85 piezas montadas, el campo **MPN** pasa a ser la referencia del fabricante y se añade **Manufacturer** | 77 de las 85 llevaban el valor en el MPN (p. ej. «100k»). AISLER busca las piezas por MPN. Los datos son los de la pieza LCSC de la BOM de JLCPCB, consultados el 2026-10-29 (`lcsc_piezas_2026-10-29.json`). La tabla de cambios está en `mpn_aplicados.csv`. «Value» y «LCSC» no cambian |

**No cambia nada más.** El script compara la copia con el original quitando solo esos atributos, esos dos campos y el
cajetín, y salen **idénticos** en los 1307 elementos de la placa: huellas, pads, redes, posiciones, giros, pistas, vías,
zonas con su relleno, contorno y textos. El diseño eléctrico y las posiciones son los de la REV B.

## 3. Validación del fichero exportado

Todos los resultados de esta tabla son **VERIFICADOS MEDIANTE HERRAMIENTA**.

| Comprobación | Resultado | Evidencia (`resultados_ci/…`) |
|---|---|---|
| ERC de la copia | 0 errores, 0 avisos | `erc.rpt` |
| DRC con paridad y las reglas del diseño | 0 violaciones, 0 sin conectar, 0 errores de huella | `drc_reglas_diseno.rpt` |
| Estructura ODB++ | `matrix/matrix`, `misc/info`, `steps/pcb/{profile, stephdr, layers, eda/data, netlists/cadnet}`, `fonts`, `symbols`; 107 entradas | `contenido_zip.txt`, `validacion_odb.json` |
| Capas | 4 de cobre (F.CU, IN1.CU, IN2.CU, B.CU) + 3 dieléctricos, 2 de máscara, 2 de pasta, 2 de serigrafía, 2 de taladro (PTH y NPTH) y la de componentes | `validacion_odb.md` |
| Contorno | **65,500 × 43,500 mm** | `validacion_odb.md` |
| Taladros | 186: 184 metalizados (164 vías + 12 vías térmicas en los EPAD de U1/U2 de 0,3 mm, 4 pads de hilo de 0,8 mm y 4 ranuras de J1 de 0,6 mm) y 2 sin metalizar (J1, 0,65 mm) | `validacion_odb.md` |
| **Contraste con el Excellon de la misma placa** | los 186 taladros tienen pareja en la misma posición y con el mismo diámetro (las ranuras, por su centro) | `contraste_gerber_odb.md` |
| **Contraste con los Gerber de cobre** | pads ODB++ + pads de forma libre = flashes del Gerber: F.Cu 517 + 2 = 519; In1 184; In2 184; B.Cu 185 | `contraste_gerber_odb.md` |
| **Componentes reconocidos** | **98 en el fichero; 85 para montar** (`.comp_mount_type` = smt en los 85); **13 `.no_pop`**: C5, L1, L2, SW1, SW2, TP1–TP8 | `validacion_odb.md`, `componentes_odb.csv` |
| C5 es DNP | sí: `.no_pop` en el ODB++ y `dnp` en la placa (ya lo era en el diseño) | idem |
| Puntos de prueba y elementos externos fuera del montaje | sí: TP1–TP8, L1/L2 y SW1/SW2 son `.no_pop`. Ninguna pieza montada es de agujero pasante | idem |
| Posiciones y giros frente a la placa REV B | 98/98 iguales; error máx. 0,000000 mm (ODB++: x = x, y = −y, giro = −giro de KiCad) | `validacion_odb.json` |
| Frente al CPL de JLCPCB entregado | 85/85 en la misma posición y con el mismo giro; ninguna pieza del CPL falta ni está como no montar | idem |
| Posiciones de KiCad sin DNP (`kicad-cli pcb export pos --exclude-dnp`) | 85 filas | `posiciones_kicad_sin_dnp.csv` |
| MPN y fabricante | los 85 coinciden con la pieza LCSC de la BOM; las 85 llevan Manufacturer | `validacion_odb.json` (`mpn_frente_a_lcsc`) |
| Propiedades por componente | Value, MPN, Manufacturer, LCSC, Description, Datasheet | `validacion_odb.md` |
| Paquetes y redes | 24 paquetes en `eda/data`, 85 redes (el diseño tiene 84 con nombre), netlist `cadnet` | idem |

## 4. Placa frente a las reglas de AISLER (4 capas, 35 µm, ENIG)

Fuente: [AISLER, 4 Layer 35 µm ENIG Design Rules](https://community.aisler.net/t/4-layer-35-m-enig-design-rules/3733),
pasadas a reglas de KiCad en `aisler_4l.kicad_dru`. DRC con esas reglas: `resultados_ci/drc_reglas_aisler.rpt` (16
violaciones). **VERIFICADO MEDIANTE HERRAMIENTA**, salvo lo que se indica.

| Regla de AISLER | Placa | Estado |
|---|---|---|
| Pista y separación ≥ 125 µm | sin violaciones | cumple |
| Cobre al borde ≥ 300 µm | sin violaciones | cumple |
| Vías: taladro 0,25–0,45 mm, anillo ≥ 100 µm | 164 vías de 0,3 mm con anillo de 0,1 mm | cumple |
| Vías en pad (EPAD de U1/U2) | 0,3 mm, anillo ≥ 0,1 mm, tratadas como vías | cumple (como vías) |
| PTH de componente ≥ 0,5 mm, anillo ≥ 300 µm | pads de hilo de 0,8 mm y Ø1,5 mm | cumple |
| NPTH ≥ 0,5 mm; cobre a NPTH ≥ 250 µm | J1 de 0,65 mm | cumple |
| Taladro a taladro ≥ 300 µm | sin violaciones | cumple |
| Pad SMD ≥ 200 µm | los más pequeños miden 0,20 × 0,60 mm (4 pads) | cumple, en el límite (medido en el ODB++) |
| **Ranura metalizada: 0,7–2,6 mm de ancho, anillo ≥ 300 µm** | **4 ranuras del blindaje de J1 (USB-C HRO TYPE-C-31-M-12): 0,6 mm de ancho, anillo de 0,196 mm** | **NO CUMPLE** (8 violaciones) |
| Texto de serigrafía ≥ 0,8 mm de alto y trazo ≥ 0,15 mm | «BOBINA», «REED» y «+ BAT −»: 0,7 mm y 0,12 mm; «ANTENA FPC…» y «4 capas 1,0 mm · ENIG»: trazo de 0,12 mm | no cumple; estético (8 violaciones) |
| Línea de serigrafía ≥ 0,15 mm | 485 líneas de F.SilkScreen y 152 de B.SilkScreen miden 0,12 mm | no cumple; estético (medido en el ODB++, no en el DRC) |
| Ensamblaje: paso mín. 0,35 mm (activos) / 0,4 mm (pasivos); pieza mín. 0201 | paso mínimo 0,5 mm; piezas 0402 | cumple (REVISADO DOCUMENTALMENTE, [especificaciones de montaje](https://community.aisler.net/t/assembly-specifications/44)) |

## 5. Configuración del pedido en AISLER (preparada, no enviada)

| Parámetro | Lo pedido | En AISLER |
|---|---|---|
| Capas | 4 | sí (4 capas, 35 µm) |
| Acabado | ENIG | sí: el servicio de 4 capas es ENIG |
| **Espesor** | **1,0 mm** | **no está en el catálogo estándar:** 4 capas solo en **0,8 mm** y **1,6 mm** ([PCB Portfolio](https://community.aisler.net/t/pcb-portfolio/101)). Para 1,0 mm hay que pedírselo a AISLER (ruta «contact us»). El ODB++ no lleva el espesor; se elige en el pedido |
| **Cantidad de PCB** | **5** | AISLER fabrica en múltiplos de 3 ([PCB order quantity](https://community.aisler.net/t/pcb-order-quantity/3141)): **6** (o 3) |
| Montaje | 2 | mínimo 1 unidad: 2 es posible ([Assembly specifications](https://community.aisler.net/t/assembly-specifications/44)). Se entrega en panel salvo que se pida otra cosa |
| Cara de montaje | solo superior | 85 SMT en la cara superior; nada en la inferior |
| Piezas | 85 por placa (41 referencias distintas) | AISLER compra las piezas; el MPN y el fabricante ya van en el ODB++ |
| Sin montar | C5, TP1–TP8, L1, L2, SW1, SW2 | `.no_pop` en el ODB++. Según AISLER, el DNP **solo se lee en la primera subida** ([Transferring no-fit/variant info](https://community.aisler.net/t/transferring-no-fit-variant-info-from-design-tools/4309)); si se vuelve a subir, hay que repasar las exclusiones en su página de BOM |
| A mano, después del montaje | bobina Qi (L1/L2), reed (SW1/SW2), batería (J2 se monta; la celda va aparte) y antena FPC W.FL | — |

**Presupuesto:** no lo he podido obtener. AISLER solo calcula el precio al subir el fichero en su web y yo no tengo
acceso ni he hecho ninguna subida ni pedido: **NO VERIFICADO**. Con el ZIP se obtiene el precio en
aisler.net → «Upload» con 4 capas, ENIG, el espesor que se elija, 6 PCB y montaje de 2.

## 6. Limitaciones y decisiones pendientes

1. **Espesor de 1,0 mm (decisión necesaria).** Las opciones son pedir a AISLER una fabricación especial de 1,0 mm, o
   usar 0,8 o 1,6 mm.
   - Con 1,6 mm la placa crece 0,6 mm: en la cápsula 5.8.1 eso se come el margen de J1 hasta el techo, que en la
     auditoría mecánica era de 1,10 mm.
   - Con 0,8 mm cambia la rigidez y el apoyo.
   La cápsula y el estudio mecánico se hicieron para 1,0 mm.
2. **Ranuras de J1 (decisión necesaria).** La huella del USB-C (TYPE-C-31-M-12, biblioteca de KiCad) tiene ranuras de
   0,6 mm, por debajo de los 0,7 mm de AISLER. No la he cambiado porque es un cambio del diseño. Opciones:
   - confirmarlo con AISLER antes de pedir: pueden aceptarlo, fresarlo de otro modo o rechazarlo;
   - o hacer una revisión con ranuras de 0,7 mm y pads más anchos (también hay que comprobar que siga cuadrando con las
     patas del conector).
3. **Serigrafía** de 0,12 mm y textos de 0,7 mm: AISLER puede engrosarla o perderla. No afecta a la función.
4. **EPAD de U1 y U4.** Son pads de forma libre y en el ODB++ salen como superficies de cobre, no como pads, igual que
   en el Gerber (contrastado). Conviene comprobar en el visor de montaje de AISLER que esas piezas aparecen bien y con
   el pin 1 correcto. AISLER advierte de que las marcas de pin 1 a veces se importan mal desde ODB++.
5. **Giros y polaridades.** El ODB++ lleva los giros de KiCad sin corregir: son los de la huella y AISLER los
   interpreta desde el propio ODB++. Hay que **repasar la vista de montaje de AISLER** antes de confirmar (PENDIENTE DE
   VALIDACIÓN FÍSICA / en su web).
6. **Piezas.** Las MPN son las de la BOM de JLCPCB: resistencias UNI-ROYAL, Hubei KENTO, Changjing… Puede que AISLER
   no las tenga y proponga equivalentes; hay que revisar su BOM, sobre todo el NTC (Murata NCP15XH103F03RC) y los C0G
   de resonancia del Qi (C1–C4).
7. **Errores conocidos del exportador ODB++ de KiCad 9.** El fallo de vías ausentes cuando no hay otros taladros
   metalizados ([KiCad #20039](https://gitlab.com/kicad/code/kicad/-/issues/20039)) **no afecta**: las 164 vías están y
   coinciden con el Excellon.
8. **Lo que no he comprobado:** la importación real en AISLER (no se ha subido), su precio, su DFM y su interpretación
   de los atributos. Todo eso es **NO VERIFICADO** hasta subir el ZIP.

## 7. Ficheros

| Fichero | Qué es |
|---|---|
| `resultados_ci/AVO_GIRTH_PCB_REV_B_AISLER_ODB.zip` | **el ODB++ para subir a AISLER** |
| `resultados_ci/validacion_odb.md` / `.json`, `componentes_odb.csv` | validación del ZIP y lista de los 98 componentes (posición, giro, no_pop, montaje, Value, MPN, fabricante, LCSC, paquete) |
| `resultados_ci/contraste_gerber_odb.md`, `gerber_contraste/` | contraste con los Gerber/Excellon de la misma placa |
| `resultados_ci/erc.rpt`, `drc_reglas_diseno.rpt`, `drc_reglas_aisler.rpt` / `.json` | ERC y DRC (reglas del diseño y de AISLER) |
| `resultados_ci/comandos_y_salida.txt` | comandos de KiCad ejecutados y su salida |
| `kicad/` | copia del proyecto que se exporta (placa, esquema, proyecto, reglas de AISLER) |
| `preparar_aisler.py`, `preparar_salida.txt`, `mpn_aplicados.csv`, `posiciones_kicad_copia.csv` | cómo se hizo la copia y qué cambió |
| `validar_odb.py`, `comparar_gerber_odb.py`, `aisler_4l.kicad_dru` | validador, contraste y reglas de AISLER |
