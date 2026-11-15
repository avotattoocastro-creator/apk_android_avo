# AVO GIRTH · montaje del sistema en la cincha (cápsula REV 6.2: aro de luz, estanca y con pestillos; funda de piel y electrodos ECG)

> **Estado: diseño · NO VERIFICADO en caballo real.** No se ha impreso, cosido ni montado nada. Los STEP no se han
> abierto en FreeCAD dentro de este entorno (no está instalado). Solo pasaron la comprobación automática de
> `fuente/verificar_step.py`. Ver «Limitaciones».

Fecha: 15/11/2026 · Rama: `feature/cincha-cad-montaje` · Arquitectura confirmada por el usuario: PCB REV D
(ESP32-C6-MINI-1U + LSM6DSV16X + MMC5983MA + ADS1292) sobre una celda de 1000 mAh, conectores pogo magnéticos de 3
contactos (carga y ECG) y dos electrodos de caucho conductor (más un tercero de referencia, opcional).

**REV 6.1 (15/11/2026, petición del usuario):** **aro de luz** con 4 LED SK6812SIDE-A (como el del casco V5) y
**todo estanco** (objetivo IP67: 1 m, 30 min; sudor, lluvia y manguera).
- La base entera es de PETG translúcido «natural» y hace de aro de luz.
- La tapa es plana, de PETG opaco.
- Una sola junta TPU 85A en ranura, con los tornillos fuera de la línea de estanqueidad.
- Bolsillo con 4 ventanas frente a la luz. **Descartado en la REV 6.2.**
- Empalmes de los electrodos soldados y encapsulados: sin JST.

Ver §3.1 y la sección **«Estanqueidad»** (§7).

**REV 6.2 (15/11/2026 18:34, decisión del usuario):** **sin bolsillo**. La cápsula va **expuesta**, en una zona con
mucho movimiento y vibración, y queda sujeta al soporte **solo por medios mecánicos**:
- **2 pestillos elásticos** de PETG, integrados en el soporte (lados cortos ±X). Encajan con clic en una **ranura
  exterior** de la base, sin atravesar la pared.
- **Seguro positivo:** detrás de cada pestillo, un seguro deslizante de TPU 95A con **retén de clic**. Con los seguros
  puestos, los pestillos no pueden abrirse.
- **Cerco de 4,5 mm**, con 0,25 mm de holgura.
- **4 tacos TPU 85A** de precarga.
- **Cordón de seguridad** Dyneema entre una **oreja maciza de la tapa** y el ala del soporte.
- La cápsula sigue siendo IP67 de diseño: la ranura exterior no atraviesa nada.

Ver §3.2 y la sección **«Retención»** (§8).

## 1. Qué hay en esta carpeta

| Ruta | Contenido |
|---|---|
| `out/STEP/AVO_CINCHA_MONTAJE_CONJUNTO_CURVADO.step` | **Conjunto completo** curvado sobre el tórax: cincha, funda, soporte con pestillos y seguros, cápsula, PCB, celda, antena, pogos, tornillería, electrodos, espuma y cables (92 sólidos en 8 subconjuntos) |
| `out/STEP/AVO_CINCHA_MONTAJE_CONJUNTO_RECTO.step` | El mismo conjunto con la cincha recta (tumbada, con la cara interior abajo) |
| `out/STEP/AVO_CINCHA_R6_2_CAPSULA_CONJUNTO.step`, `..._SOPORTE_CONJUNTO.step` | Subconjuntos de la cápsula y del soporte, en coordenadas locales |
| `out/STEP/REF_torax_caballo_seccion.step` | Sección del tórax de referencia (300 mm de largo) |
| `out/STEP/piezas/*.step` | Un STEP por pieza: impresas, PCB, celda, antena, electrodo, funda, cincha Decathlon y Horze (recta y curvada) |
| `out/STL/*.stl` | Piezas impresas, ya colocadas para imprimir |
| `out/PATRON/AVO_CINCHA_funda_piel_patron.{svg,dxf}` | Patrón plano 1:1 de la funda, en mm, con capas de corte, pliegue, costura, agujeros cada 4 mm, rebaje, taladros y marcas |
| `out/informe.json` | Medidas, volúmenes, longitudes de cable y comprobaciones |
| `out/AVO_CINCHA_MONTAJE.zip` | Todo lo anterior junto, para descargar |
| `renders/*.png` | Renders de comprobación (01–14; 12 = corte por los LED, 13 = corte por un pestillo, 14 = pestillo y seguro) |
| `fuente/` | Scripts que lo generan todo (ver §9) |

**Coordenadas.** En la cincha:
- u va a lo largo, con 0 en el centro (bajo el esternón) y + hacia el lado **izquierdo** del caballo;
- v va a lo ancho, con + hacia el canto **trasero** y − hacia los codos;
- w va hacia fuera, con 0 en la piel del caballo.

En el conjunto curvado: X+ = izquierda del caballo, Y+ = hacia la cabeza, Z+ = arriba.

## 2. Fuentes consultadas y medidas usadas

| Dato | Valor usado | Fuente / estado |
|---|---|---|
| Perímetro torácico de un caballo de 500 kg | 185 cm | Tabla de [OMAFRA (Ontario)](https://www.ontario.ca/page/estimating-body-weight-horses): 500 kg ↔ 73 in (185 cm); fórmula peso = perímetro² × longitud / 11 900 |
| Perímetro / anchura de pecho / profundidad (PSI) | 192,1 / 48,0 / 75,5 cm | Yeguas PSI húngaras ([Hrčak](https://hrcak.srce.hr/file/158292)); otro estudio da 184 cm de perímetro en caballos de 161 cm ([USAMV 2024](https://www.animalsciencejournal.usamv.ro/pdf/2024/issue_2/Art41.pdf)) |
| Sección del tórax del modelo | Superelipse de 480 × 692 mm, n = 2,15, perímetro **188 cm** | **ESTIMADO** a partir de lo anterior. Radio bajo el esternón ≈ 341 mm; ≈ 195 mm a 10 cm del centro |
| Largo de la cincha | 110 cm (punta a punta de hebilla) | Tallas de catálogo: Horze Comfort Leather Girth Long 110–145 cm ([horze.eu](https://horze.eu/products/comfort-leather-girth-long-black)); Decathlon 85–145 cm ([decathlon.ch](https://decathlon.ch/en/p/sangle-equitation-synthetique-cheval-et-poney-100-noire/_/R-p-300241)) |
| Ancho de la cincha de tela (Decathlon, foto del usuario) | 110 mm, 8 mm de grosor, cinta central de 50 mm | **ESTIMADO** por la foto: Decathlon no publica ni el ancho ni el grueso |
| Cincha anatómica de cuero (Horze, foto del usuario) | 120 mm en el centro, 85 mm en el recorte del codo, 70 mm en las puntas, 10 mm de grosor | **ESTIMADO**. Horze no da anchos; una cincha de cuero comparable mide 11 cm ([Kramer Naira](https://www.kramer.co.uk/Horse/Saddles-Saddle-Accessories/Leather-Girth-Naira)) |
| Hebillas | Rodillo inox, luz 25 × 14 mm, varilla de 4–5 mm | [pethardware](https://www.pethardware.com/en/roller-buckles/girth-buckle-373/index.md); Horze usa rodillo inox |
| Elásticos y correas | 2 por punta, 25 mm de ancho | ESTIMADO (estándar de 1") |
| Anilla D central | Varilla Ø5, lado recto de 38 mm | ESTIMADO. Decathlon menciona una «central ring» |
| Conector pogo magnético de 3 contactos | Placa: cara 15,5 × 4,65, reborde 17,1 × 6,25, 3,5 de alto, paso 2,3. Pines: cuerpo 15,5 × 4,65 × 6, orejas 25 × 5,5, tornillos a 19,5 | **Medido** del STEP real del usuario (`hardware/girth/REV5/ref/pogo_3pin_assembly.step`). Mismo producto: [eBay, 3 polos, paso 2,3](https://www.ebay.de/itm/397361911743) |
| PCB | 46 × 30 × 1,0, 4 taladros M2 en (±20,8, ±12,8), componentes ≤ 2,6 mm en la cara F | `hardware/girth/PCB_REV_D` (rama `feature/girth-pcb-rev-d`, `piezas.json` copiado en `fuente/datos/`) |
| Celda | LiPo 603450, 1000 mAh, 6 × 34 × 50 mm | `PCB_REV_D/DOCS/CONSUMO_BATERIA.md`; ejemplo de celda de 6 × 34 × 50 mm ([Ormix](https://ormix.lv/en/product/35488)) |
| Antena | Molex 146153-0050, 35 × 9 × 0,1 mm, coaxial Ø1,13, MHF1 (U.FL), 3,2 dBi a 2,4 GHz con cable de 50 mm | [Hoja de datos (Farnell)](https://www.farnell.com/datasheets/3764461.pdf), [RS 1461530100](https://docs.rs-online.com/e418/A700000007613197.pdf) |
| Inserto térmico M2 | ruthex M2 × 4: Ø3,6 exterior, pared mínima 1,3 | [3DJake](https://www.3djake.com/ruthex/threaded-insert-m2-70-pieces) |
| Electrodo principal | Vialta PG980/51: caucho conductor de 60 × 85 mm, cable rojo moldeado con banana hembra de 4 mm. Grosor de 2 mm **ESTIMADO** | Elegido por el usuario (9,57 € + IVA). La ficha no se encontró en la web |
| Colocación de los electrodos | Detrás del codo, a ambos lados; el de referencia en el lado derecho | [Polar Equine](https://support.polar.com/en/using-the-polar-equine-heart-rate-monitor): mojar los electrodos y el pelo. Banda textil con electrodos de 4 cm detrás de cada codo y tierra a la derecha ([McCrae et al., Animals 2022](https://www.mdpi.com/2076-2615/12/23/3254)) |
| Piel de curtido vegetal | Vaqueta, 1,4–1,5 mm, piezas de 11–15 ft², 168,80 £ | [Tandy Leather EU](https://tandyleather.eu/en-gb/products/traditional-spanish-veg-tan-vaqueta-oiled-side) (referencia de precio) |

## 3. Diseño

### 3.1 Cápsula REV 6.2 (`AVO_CINCHA_R6_2_*`)

**Medidas.** Exterior de 62,9 × 60,1 × 15,5 mm, con las orejas de los 6 tornillos, y 64,7 mm de fondo en la tapa con
la oreja del cordón. Interior de 51 × 43,75 mm.

**REV 6.2 en la cápsula:**
- **Ranura exterior** de 1,2 mm de hondo, de z = 5,0 a 6,4, en todo el contorno de la base, para los ganchos de los
  pestillos. Deja 2,8 mm de pared: no la atraviesa.
- **Chaflán de entrada** de 0,8 mm en el canto inferior.
- **Oreja maciza** en la tapa (+Y, 12 × 7 mm, R3), con un agujero vertical de Ø3,2 para el cordón de seguridad. Está
  **fuera** de la junta.

**Base = aro de luz** (`AVO_CINCHA_R6_2_base_aro_luz_PETG_translucido`): PETG translúcido «natural», de una pieza, 100 % de relleno.
- Paredes de **4,0 mm**, de z = 0 a z = 13,0. Rodean la PCB a la altura de los LED:
  - la luz nace a z = 10,9;
  - la lente queda a 0,34 mm del canto de la PCB (y = ±14,66);
  - sale por los **dos lados largos** (±Y), a través de 2,8 mm de aire (+Y) o de 11,6 mm (−Y, por encima de las copas de los pogos), y de la pared de 4 mm, que la difunde.
- Suelo de 1,7 mm. Las dos placas pogo (carga y ECG) van con la cara a ras del fondo, en copas de epoxi.
- **Ranura de la junta** en el canto superior: 1,9 de ancho × 1,2 de hondo, a 1,05–2,95 mm del hueco.
- 6 orejas macizas por fuera de la ranura con **insertos M2 × 4 ciegos**: agujeros de Ø3,2 × 5 que no llegan al interior; quedan 0,65 mm hasta la ranura.

**Tapa** (`AVO_CINCHA_R6_2_tapa_PETG_opaco`): plana, de 2,5 mm, PETG opaco rojo.
- Apoya en el canto de la base con **tope duro**, así que la compresión de la junta la fija la geometría.
- Lleva una lengüeta de centrado de 1,0 × 1,2 dentro del hueco.
- **4 columnas** de Ø4,4 sujetan la PCB con 4 tornillos M2 × 5 ISO 7380 (guías **ciegas**, con 1,5 mm de piel por encima).
- Rebaje de 0,3 mm para la antena Molex 146153, fuera de la planta de la PCB.
- 6 avellanados para la cabeza ISO 7380 + arandela DIN 433.
- Ya no lleva la ventana del LED D1: el aro hace de indicador.

**Junta:** una sola, desmontable. TPU 85A impreso, sección de 1,2 × 1,6, en la ranura de 1,9 × 1,2.
- Compresión: **25 %** (de 1,6 a 1,2).
- Llenado de la ranura: 84 %.
- En el conjunto se dibuja comprimida.

**Cierre:** 6 tornillos **M2 × 6 ISO 7380 inox con arandela DIN 433 inox**.
- Los tornillos están **fuera** de la línea de la junta: sus agujeros no son camino de entrada de agua.
- Las arandelas reparten la carga sobre el PETG.

**Pila en z (mm):**

| Pieza | z |
|---|---|
| Suelo | 0–1,7 |
| Celda | 1,7–7,7 |
| Separador TPU | 7,7–8,9 |
| PCB | 8,9–9,9 |
| LED | 9,9–11,9 (centro de la luz en 10,9) |
| Componentes | hasta 12,5 |
| Ranura | 11,8–13,0 |
| Tapa | 13,0–15,5 |

**PCB:** REV D integrada en develop (ADS1292 en TQFP-32), más los **4 LED SK6812SIDE-A** de la rama `feature/girth-pcb-rev-d-aro`. Cotas del 15/11, corregidas:

| LED | Posición | Lente hacia |
|---|---|---|
| D10 | (−15; +13,30) | +Y |
| D11 | (+14; +13,30) | +Y |
| D12 | (+14; −13,30) | −Y |
| D13 | (−15; −13,30) | −Y |

**Hilos** (silicona AWG 28):
- contactos del pogo del ECG → P4 (ECG+), P5 (REF) y P6 (ECG−);
- contactos del pogo de carga → P1 (5 V), P2 (GND) y P3 (DET);
- celda → J2/J6.

**Por qué la base entera es translúcida (y no un aro aparte).** La prioridad absoluta es la estanqueidad. La Centauri
Carbon tiene una sola extrusora, así que no puede hacer una pieza bicolor con la banda translúcida integrada.
- **Pegar un aro translúcido entre dos piezas opacas** crea una o dos uniones nuevas de 220 mm de perímetro. Una unión
  pegada en PETG impreso (capas, contracción del epoxi, ciclos de temperatura y sudor) es un camino de fuga más, y no se
  revisa ni se cambia como una junta.
- **Imprimir la base de una sola pieza en translúcido** deja la única unión desmontable donde ya estaba (base–tapa,
  por encima de la PCB). La banda de luz es la propia pared, sin costuras.
- **Lo que se pierde:**
  - toda la base brilla, incluido el fondo. En la REV 6.2 el cerco del soporte tapa los 3,8 mm de abajo y el resto queda a la vista;
  - el PETG natural deja ver un poco el interior.

Si se quiere más difusión, se puede lijar la cara interior de la pared o pintarla con barniz mate translúcido.

### 3.2 Soporte REV 6.2 (`AVO_CINCHA_R6_2_soporte_pestillos_PETG`, PETG opaco)

**Medidas.** 89,6 × 82,6 mm; ala de 2,5 mm; cama a z = 8; cerco hasta z = 12,5; contrafuertes hasta z = 19. Todo
queda por debajo de la tapa de la cápsula, que llega a z = 24,2.

**Cerco** de 2 mm de grueso y **4,5 mm de alto**:
- abraza la cápsula con **0,25 mm de holgura**;
- el contorno no es redondo (orejas de los tornillos), así que también impide el giro;
- solo se corta en los ±X, donde pasan los pestillos y los seguros;
- tapa la cápsula hasta su z = 3,8. La banda de los LED (lados ±Y, centro a z = 10,9) queda **libre**.

**4 tacos de precarga** de TPU 85A (Ø3 × 1,85 libres, en alojamientos de Ø3 × 1,0):
- la cápsula apoya en ellos a 0,7 mm sobre la cama, comprimiéndolos 0,15 mm;
- empujan la base contra los ganchos, de modo que no queda ningún juego vertical;
- los pines del pogo trabajan comprimidos 0,8 mm de su 1,1 de recorrido.

**2 pestillos**, de una pieza con el soporte, en los lados cortos ±X (cálculo en §8):
- **viga** de 1,2 × 12 mm de sección y 12,9 mm de largo, desde la raíz (z = 0,8), con radio escalonado en la raíz;
- arranca del fondo de un hueco del cuerpo, que tiene 2 desagües de Ø1,4;
- **gancho** con la cara inferior plana; entra **0,9 mm** en la ranura exterior de la base y tiene la rampa de
  entrada arriba;
- encima, **pulsador** de 4,2 × 13,2 mm (R1,5), rebajado entre la cápsula y el contrafuerte.

**Contrafuerte** de 2,6 mm, que protege el pestillo de golpes y roces. Lleva la **muesca del retén** del seguro.

**2 seguros deslizantes** de TPU 95A (`AVO_CINCHA_R6_2_seguro_izq/der_TPU95A`):
- barra de 1,3 × 5,2 × 19,7 mm que entra a lo largo de Y en el hueco de 1,6 mm entre la viga y el contrafuerte;
- 0,15 mm de holgura por lado (arena); el pestillo solo puede abrirse 0,3 mm, frente a 0,9 de enganche;
- un **resalte de Ø1,2** encaja con **clic** en la muesca: no lo mueve la vibración;
- un tope final;
- cabeza redondeada con un agujero de Ø1,5 para sacarlo con un gancho o atarlo con un hilo al cordón.

**Cordón de seguridad** (Dyneema Ø1,5): de la oreja de la tapa al anclaje de Ø3,2 del ala del soporte (en +Y).
- Si todo falla, la cápsula no se pierde.
- Se ata con un nudo de pescador doble o con un casquillo de crimpar.

**Conectores de pines** (carga + ECG):
- cara a ras de la cama;
- orejas con 2 tornillos M2 × 4 cada uno;
- colas **encapsuladas** con silicona neutra o resina (REV 6.1);
- puente 2–3 (DET) en el conector de carga.

**Fijación a la funda:** ala con **4 tornillos de Chicago de Ø5**.

**Por qué este seguro.** El cerrojo deslizante en el hueco detrás de la viga es la forma más sencilla de lograr un
**bloqueo positivo**:
- con el seguro dentro, la viga no puede doblarse hacia fuera, y la retención pasa a depender de la resistencia
  del gancho y de la viga, no de su elasticidad;
- el retén de clic lo sujeta frente a la vibración;
- queda dentro del contorno, así que no se engancha;
- con guantes se saca tirando de la cabeza con la uña o con un gancho.

Alternativas descartadas:
- **Pieza de TPU encajada a presión:** solo la sujeta la fricción.
- **Pasador R metálico:** sobresale y se engancha.
- **Cierre por giro:** necesita más altura y deja rendijas que se llenan de barro.

### 3.3 Funda de piel
Funda de 800 mm de largo que envuelve la parte central de la cincha. Se corta de **una sola pieza** (patrón A) que,
en este orden, forma:
1. panel exterior;
2. pliegue delantero;
3. panel interior;
4. pliegue trasero;
5. solapa de 30 mm, que cierra sobre el panel exterior con **velcro de coser de 25 mm**.

La solapa se interrumpe donde está el soporte. **REV 6.2: el bolsillo se ha eliminado.** Ya no hay piezas B1/B2,
broche ni ventanas de luz: la cápsula queda a la vista, sujeta por los pestillos.

Holguras:
- 7 mm en el canto delantero: es el canal del cable;
- 1 mm en el trasero;
- 4 mm sobre la cincha: paso del cable hasta la ranura del soporte.

Elementos:
- **Ventanas de los electrodos** en el panel interior:
  - 75 × 50 mm para ECG+ y ECG−, 50 × 30 mm para REF;
  - alrededor, la piel se **rebaja a 1,0 mm** en una franja de 6 mm, para que el electrodo quede solo 1 mm por
    dentro de la superficie;
  - costura perimetral en el solape de 5 mm, a 2,5 mm de la ventana;
  - detrás, **espuma EVA/neopreno de 2,5 mm**, que empuja el electrodo contra la piel del caballo.
- **Posiciones:**

  | Electrodo | u | v |
  |---|---|---|
  | ECG+ (izquierda, hacia la punta del corazón) | +190 | −20 |
  | REF (derecha, opcional, 60 × 40) | −150 | −20 |
  | ECG− (derecha, más alto) | −280 | −20 |

- **Canal cosido del cable:** tiras de piel de 1,2 mm cosidas por dentro del pliegue delantero, en 3 tramos (C1–C3).
  Dejan huecos donde salen los cables hacia los electrodos.
- **Ventana de 40 mm** en el pliegue delantero para la pestaña de la anilla D central de la cincha.
- **Trabillas** (pasadores) de 25 mm en los dos extremos.

### 3.4 Cables
- El cable moldeado de cada electrodo Vialta se corta y se le quita la banana.
- Recorrido: por el canal delantero, sube por encima de la cincha y llega a un **empalme soldado**, dentro de la funda,
  bajo la ranura de 14 × 7 del panel exterior.
  - Cada hilo lleva su termorretráctil fino.
  - Encima, un termorretráctil **con adhesivo 3:1** de Ø6 × 30 mm común a los tres.
  - **REV 6.1: sin JST.** Un conector abierto se llena de sudor.
- Un rabillo de 3 hilos sube por la ranura hasta las colas del conector de pines del ECG, que van encapsuladas.
- Correspondencia: contactos 1/2/3 del pogo → P4/P5/P6 de la PCB.

| Cable | Longitud | Conexión |
|---|---|---|
| ECG+ | 210 mm | contacto 1 → P4 |
| REF | 163 mm | contacto 2 → P5 (RLD, por R43 de 100 kΩ) |
| ECG− | 282 mm | contacto 3 → P6 |

Las longitudes son las del modelo, todas < 40 cm. Se recomienda añadir 30 mm de reserva.
- **Trenzado:** REF y ECG− van trenzados en el tramo común, del soporte a u = −125.
- El cable de ECG+ se puede trenzar con un hilo de retorno unido a REF solo en el extremo del soporte. Hace de guarda.
- **Unión con P4/P5/P6.** Los cables no entran en la cápsula estanca. Se empalman al rabillo del conector de pines del
  soporte, y el pogo del ECG lleva cada contacto a P4–P6. Así la cápsula se sigue pudiendo sacar para cargarla.

### 3.5 Alternativa de electrodo (documentada, no modelada)
- **Material:** lámina de caucho de silicona conductora POTUBI (Amazon.es, 20,51 €, 200 × 100 × 2 mm, ≈ 200 Ω·cm),
  recortada a 60 × 85 o 50 × 50 mm. Si se encuentra en **0,5–1 mm**, mejor: se adapta más y tiene menos resistencia
  en serie.
- **Conexión:** broche macho de 4 mm remachado, con la tapa del remache por la cara de la piel sellada con silicona
  neutra. Por dentro, arandela inox de 10–15 mm.
- **Cable:** ECG apantallado con broche hembra de 4 mm hasta la cápsula.
- **Variante:** chapa inox 316 de 0,3 mm pegada con silicona conductora por detrás.
- El montaje en la funda es el mismo (ventana, rebaje, EVA).

## 4. Lista de materiales (BOM) — precios aproximados, IVA incluido salvo indicación

| # | Pieza | Ref. / proveedor | Cant. | Precio aprox. |
|---|---|---|---|---|
| 1 | Cincha de tela con elásticos | Decathlon Fouganza (foto del usuario) | 1 | 14,50 € |
| 1b | (alternativa) cincha de cuero anatómica 110 cm | Horze Comfort Leather Girth Long | 1 | 79,95–84,49 € |
| 2 | PCB REV D montada | JLCPCB, ver `PCB_REV_D` | 1 | ≈ 20 € (ESTIMADO, lote de 5) |
| 3 | Celda LiPo 603450 1000 mAh con PCM y cables | p. ej. Ormix ACCU-LP603450 | 1 | ≈ 9,90 € |
| 4 | Antena Molex 146153-0050 (U.FL, 50 mm) | RS / Farnell / Mouser | 1 | ≈ 2,40 € (RS: 16,03 £ + IVA las 8) |
| 5 | Conector pogo magnético 3 contactos, paso 2,3 (par) | eBay / AliExpress | 3 pares (2 sistema + 1 base de carga) | ≈ 15 € |
| 6 | Insertos térmicos M2 × 4 (ciegos) | ruthex (70 uds.) | 6 | 8,38 $ el juego |
| 7 | Tornillos inox ISO 7380 M2 × 6 (6), M2 × 5 (4), M2 × 4 (4) + **arandelas DIN 433 M2 inox (6)** | Kit M2 inox | 20 | ≈ 7 € |
| 8 | Hilo de silicona AWG 28 (3 colores) | — | 1 m | ≈ 3 € |
| 9 | **Epoxi de colada** transparente de 24 h, sin disolvente (p. ej. resina de colada 1:1; copas de los pogos y barniz interior opcional) | ferretería / Amazon | 1 juego | ≈ 10 € |
| 9b | **Silicona neutra** (oxima/alcoxi, no acética: no ataca el cobre) para encapsular las colas del soporte | ferretería | 1 cartucho pequeño | ≈ 5 € |
| 9c | **Termorretráctil con adhesivo 3:1** Ø6 y Ø3 (empalme de los cables) | — | 0,2 m | ≈ 3 € |
| 10 | **PETG translúcido «natural»** (base, ≈ 15 cm³ ≈ 19 g), PETG opaco (tapa y soporte, ≈ 44 cm³ ≈ 56 g), TPU 85A (junta y separador, ≈ 2 cm³) | bobinas de 1 kg | — | ≈ 3 € de material (bobina de PETG natural ≈ 20 €) |
| 10b | Junta de repuesto TPU 85A impresa (2 uds.) | — | 2 | ≈ 0,1 € |
| 11 | Electrodo Vialta PG980/51 60 × 85 | Vialta | 2 | 2 × 11,58 € = 23,16 € |
| 12 | (opcional) electrodo pequeño para REF/RLD, ≈ 40 × 60 | Vialta u otro de caucho | 1 | ≈ 8 € (ESTIMADO) |
| 13 | (eliminado en REV 6.1: el empalme JST se sustituye por soldadura + termorretráctil con adhesivo) | — | — | — |
| 14 | Piel de curtido vegetal 2,0 mm (≈ 0,35 m²) + retal de 1,2 mm para el canal | Tandy / guarnicionería | 1 | ≈ 45 € (≈ 12–15 £/ft²) |
| 15 | Velcro de coser 25 mm (gancho + rizo) | mercería | 0,7 m | ≈ 3 € |
| 16 | Tornillos de Chicago Ø5 (juego de 30, 5 × 15 mm) | [ManoMano](https://www.manomano.es/p/30-juegos-de-tornillos-de-encuadernacion-chicago-tornillos-de-encuadernacion-niquelados-5-mm-x-15-mm-tono-plateado-84620168) | 4 | ≈ 8 € |
| 17 | (eliminado en REV 6.2: broche del bolsillo) | — | — | — |
| 17b | **Cordón Dyneema / UHMWPE Ø1,5 mm** (≥ 100 kg) + 2 casquillos de crimpar de aluminio | pesca / náutica | 0,3 m | ≈ 4 € |
| 17c | **Filamento TPU 95A** (2 seguros) y TPU 85A (tacos, junta, separador) | — | ≈ 3 g | ≈ 0,2 € |
| 18 | Hilo encerado de poliéster de 0,8 mm + 2 agujas de guarnicionero | — | 1 | ≈ 7 € |
| 19 | Espuma EVA o neopreno de 2–3 mm (A4) | — | 1 | ≈ 3 € |
| 20 | Papel indicador de agua (o pañuelo de papel) y bomba de vacío manual con recipiente (ensayo, §7) | — | 1 | ≈ 15 € (opcional) |
| 21 | Dinamómetro de 25 kg o peso de 10 kg con gancho (ensayo de tirón, §8.4) | — | 1 | ≈ 10 € (opcional) |
| — | **Total (con la cincha Decathlon y el electrodo REF, sin los ensayos)** | | | **≈ 200 €** |
| — | Alternativa: lámina POTUBI + broches de 4 mm + arandelas inox | Amazon.es | — | 20,51 € + ≈ 10 € |

Herramientas que no entran en el total:
- pinzas de costura de 4 mm;
- rebajador de piel;
- sacabocados de 5 mm;
- cúter;
- soldador;
- punta para insertos térmicos.

## 5. Impresión (Elegoo Centauri Carbon)

| Pieza | Material | Orientación | Ajustes |
|---|---|---|---|
| **Base (aro de luz)** | **PETG translúcido natural** | Fondo sobre la cama | Ver «Impresión estanca» (§7.3) |
| Tapa | PETG opaco (rojo) | **Boca abajo** (cara superior sobre la cama) | §7.3. Columnas y lengüeta hacia arriba |
| Soporte con pestillos | PETG opaco | Ala sobre la cama | **0,15 mm**, 5 perímetros, 100 % en un radio de 6 mm alrededor de los pestillos (modificador). 250–255 °C y ventilador ≤ 30 % para que las capas peguen bien (la viga trabaja a flexión entre capas). Sin soportes: los ganchos salen 1,3 mm en voladizo con rampa |
| Seguros (×2) | TPU 95A | Planos | 0,15 mm, 100 %, lento. Comprobar que el resalte sale redondo |
| Tacos (×4) | TPU 85A | De pie | 100 %. Se meten a presión en sus alojamientos |
| Junta | TPU 85A | Plana | 0,2 mm, 100 %, ≤ 20 mm/s, sin retracciones largas. 3 líneas de 0,4 mm |
| Separador | TPU 85A | Plano | 0,2 mm, 100 % |

Holguras:
- 0,3 mm entre la cápsula y el soporte;
- 0,15 mm en el cuerpo de los pines;
- 0,2 mm en la placa pogo y la lengüeta;
- ranura de la junta de 1,9, para una junta de 1,2.

**Imprimir primero una base y un soporte de prueba** y comprobar los pogos, los insertos y la junta con el calibre.

## 6. Montaje paso a paso

**Cápsula**
1. Insertos M2 × 4 en los 6 alojamientos de la base, con la punta térmica a 220 °C, enrasados con el canto. **No
   apretar de más:** son ciegos y no deben abombar el fondo.
2. Placas pogo en sus ventanas, desde dentro, con la cara a ras del fondo. **Mirar la orientación:** contacto 1 en
   el lado −X de cada placa.
3. Soldar 3 hilos AWG 28 de 40 mm a cada placa. Desengrasar con alcohol isopropílico y llenar las copas con **epoxi de
   colada** hasta tapar las colas 1 mm. Dejar curar 24 h.
4. **Ensayo 1** (base sola): vacío o inmersión (§7.4). Si hay burbujas, repasar con epoxi.
5. Pegar la antena Molex en el rebaje de la tapa (adhesivo propio). Conectar el U.FL al módulo **antes** de atornillar
   la PCB.
6. Atornillar la PCB a las 4 columnas de la tapa con M2 × 5 ISO 7380, sin pasarse de apriete (la rosca es en PETG).
7. Soldar los hilos:
   - placa ECG → P4/P5/P6;
   - placa de carga → P1/P2/P3;
   - celda → J2 (+) y J6 (−).
   Comprobar la polaridad antes de soldar el −. Llevar los hilos del pogo del ECG por debajo de la PCB, sin tapar la
   lente de D13.
8. Separador TPU sobre la celda. **Junta limpia y seca en la ranura**, sin retorcerla y con el punto de inicio de la
   impresión en una esquina. Cerrar con 6 M2 × 6 + arandela, apretando en cruz hasta el tope (≈ 0,15 N·m: la
   tapa toca el canto y la compresión queda en el 25 %).
9. **Ensayo 2** (cápsula cerrada, con la electrónica): §7.4.

**Soporte**

10. Conectores de pines en sus alojamientos, con 2 M2 × 4 cada uno.
    - Conector de **carga**: puente entre los contactos 2 y 3.
    - Conector del **ECG**: rabillo de 3 hilos de 60 mm.
11. **Encapsular** el hueco inferior de los dos conectores con silicona neutra (o epoxi de colada) hasta enrasar.
    Quedan tapados las colas, el puente y la salida del rabillo. Curar 24 h.

**Funda**

12. Cortar el patrón A, C1–C3 y D1–D2 (`out/PATRON/*.dxf`, 1:1, comprobar la escala con el texto de 7 mm).
13. Rebajar a 1,0 mm las franjas marcadas en naranja alrededor de las ventanas. Abrir:
    - las ventanas de los electrodos;
    - la ranura del cable (14 × 7);
    - la ventana de la anilla D;
    - los 4 taladros de Ø5.
14. Coser los canales C1–C3 por el lado carne del pliegue delantero (líneas de costura a 4 mm).
15. Para cada electrodo:
    - presentarlo por el lado carne sobre su ventana;
    - coser el perímetro por el solape de 5 mm;
    - pegar detrás la espuma EVA, solo por los bordes.
16. Coser el velcro: rizo en el panel exterior, gancho en el lado carne de la solapa.
17. (REV 6.2: ya no hay bolsillo.)
18. Meter los 4 tacos TPU 85A a presión en sus alojamientos de la cama. Fijar el soporte al panel exterior con los 4 tornillos de Chicago (con una gota de fijador de roscas suave).

**Cables**

19. Cortar la banana de cada electrodo y recortar el cable:
    - ECG+ ≈ 240 mm;
    - REF ≈ 190 mm;
    - ECG− ≈ 310 mm.
20. Trenzar REF con ECG− en el tramo común.
21. **Empalme estanco** con el rabillo del soporte (1 = ECG+, 2 = REF, 3 = ECG−):
    - soldar cada hilo con su termorretráctil fino;
    - encima, un termorretráctil **con adhesivo** de Ø6 × 30 mm;
    - calentar hasta que el adhesivo salga por los dos extremos.
22. Pasar los cables por los canales.

**Colocación**

23. Meter la cincha en la funda, con la anilla D por su ventana. Cerrar el velcro y pasar las trabillas.
24. Atar el **cordón de seguridad**: oreja de la tapa → anclaje del ala del soporte, con un largo libre de unos 40 mm.
25. **Poner la cápsula** (§8.3): apretar hasta oír los dos clics y meter los dos seguros hasta su clic.

**Comprobaciones antes del caballo** (todas **pendientes**)
- Continuidad electrodo → contacto del pogo de la cápsula (< 2 kΩ con el caucho húmedo).
- Aislamiento entre electrodos con la funda seca (> 10 MΩ).
- DET = 0 con la cápsula en el soporte.
- Radio: RSSI con la espalda a 1 m, con la cápsula montada.
- Aro de luz visible por los dos lados largos, por encima del cerco.
- Ensayos de retención de §8.4.
- ECG en reposo con los electrodos y el pelo mojados, como pide Polar Equine.

## 7. Estanqueidad (objetivo IP67: sumergida 1 m, 30 min; sudor, lluvia y manguera)

> **NO VERIFICADO.** El IP67 es el objetivo del diseño, no un resultado. Solo vale con el ensayo de §7.4 hecho en cada
> cápsula montada.

### 7.1 Principio
1. **Una sola línea de estanqueidad desmontable:**
   - junta TPU 85A en ranura, entre la base y la tapa;
   - compresión del 25 %, fijada por el **tope duro** de la tapa sobre el canto;
   - **todo lo atornillado queda fuera** de la línea de la junta.
2. **El resto de la envolvente es continuo o sellado para siempre:**
   - pared de la base de una sola pieza (el aro de luz no añade uniones);
   - placas pogo pegadas con epoxi;
   - insertos y guías ciegos.
3. **Nada pasa a través de la cápsula:** sin USB, sin pulsadores, sin ventanas de LED y sin tornillos pasantes. La
   antena va dentro, y la carga y el ECG van por contactos planos.
4. **Fuera de la cápsula,** todo lo que tiene cobre va encapsulado o con termorretráctil con adhesivo: colas de los
   conectores del soporte y empalmes de los electrodos. La piel no es estanca, ni hace falta.

### 7.2 Puntos de entrada de agua y cómo se sella cada uno

| # | Punto | Riesgo | Cómo se sella (REV 6.1 / 6.2) | Se comprueba con |
|---|---|---|---|---|
| 1 | Unión base–tapa (220 mm de perímetro) | Alto | Junta TPU 85A de 1,2 × 1,6 en ranura de 1,9 × 1,2 (25 % de compresión, 84 % de llenado). Tope duro. Canto y ranura sin costuras de impresión | Ensayo 2 (§7.4); cambiar la junta si se aplasta |
| 2 | 6 tornillos del cierre | Nulo | Fuera de la junta: los agujeros de la tapa y los insertos de la base no comunican con el interior. Insertos **ciegos** con 0,65 mm de PETG hasta la ranura. Arandela DIN 433 bajo la cabeza para repartir la carga | Inspección y ensayo 2 |
| 3 | 2 ventanas de las placas pogo en el fondo | Alto | Placa con reborde apoyado por dentro + **copa de epoxi de colada** que cubre el reborde y las colas (1 mm por encima) | Ensayo 1 (base sola) |
| 4 | Contactos de la placa pogo (metal–plástico del propio conector) | Medio | Los cubre el mismo epoxi por dentro | Ensayo 1 |
| 5 | Paredes y fondo de PETG impreso (porosidad entre capas) | Medio | 100 % de relleno, ≥ 4 perímetros (≥ 1,6 mm de pared continua), sobreextrusión del 3–5 %, PETG seco. Opcional: barniz de epoxi fino por dentro | Ensayo 1 y 2 |
| 6 | Guías de los tornillos de la PCB en la tapa | Nulo | **Ciegas**: 1,5 mm de PETG por encima | Inspección |
| 7 | Rebaje de la antena | Nulo | Por dentro; no atraviesa | — |
| 8 | Aro de luz | Nulo | Es la propia pared de la base: sin uniones | — |
| 9 | USB / pulsadores / ventilación | — | **No hay** (programación inicial por los pads de prueba con la cápsula abierta; después por radio) | — |
| 10 | Colas de los conectores del soporte (fuera de la cápsula) | Medio (corrosión) | Encapsulado con silicona neutra o epoxi, enrasado | Inspección; aislamiento > 10 MΩ en seco |
| 11 | Pines con muelle del soporte y contactos expuestos | Bajo | Contactos dorados; aclarar con agua dulce y **secar antes de cargar** (5 V expuestos con PTC y TVS en la PCB) | Inspección |
| 12 | Empalme de los cables de los electrodos | Medio | Soldadura + termorretráctil fino + termorretráctil **con adhesivo** 3:1 común (sin JST) | Aislamiento > 10 MΩ tras 30 min en agua |
| 13 | Electrodo Vialta (cable moldeado) | Bajo | Sellado de fábrica | — |
| 14 | **Ranura exterior de los pestillos (REV 6.2)** | Nulo | Es un rebaje **exterior** de 1,2 mm en una pared de 4,0 (quedan 2,8 macizos). No hay agujeros | Inspección; ensayo 2 |
| 15 | **Oreja del cordón en la tapa (REV 6.2)** | Nulo | Maciza, **fuera** de la junta; su agujero no comunica con el interior | Inspección |
| 16 | **Mecanismo de los pestillos y seguros** (fuera de la cápsula) | — (no es estanco ni hace falta) | Rendijas ≥ 0,3 mm y desagües de Ø1,4 en el fondo de cada hueco: se lavan con manguera | Lavado y prueba de cierre tras barro |

### 7.3 Impresión estanca en PETG (base y tapa)
- **Material:** PETG seco (4 h a 65 °C antes de imprimir). Natural para la base y opaco para la tapa.
- **Ajustes:**
  - 0,2 mm de capa;
  - boquilla de 0,4 mm;
  - **≥ 4 perímetros** (5 en la base, que con 4 mm de pared queda casi maciza);
  - **100 % de relleno** rectilíneo;
  - 5 capas arriba y 5 abajo;
  - **flujo al 103–105 %** (sobreextrusión ligera);
  - ventilador al 30–40 % (mejor unión entre capas);
  - 240–250 °C, cama a 80 °C;
  - velocidad de pared exterior ≤ 60 mm/s.
- **Costuras:** costura **alineada** y colocada en una oreja de tornillo, **nunca en la ranura de la junta ni en el
  canto de apoyo**. Sin «wipe» sobre el canto.
- **Translúcido:** 100 % de relleno y velocidad baja dan una pared más homogénea y difunden mejor. Evitar
  «ironing» en las paredes.
- **Opcional:** barniz interior de epoxi de colada diluido (o barniz de poliuretano) con pincel, sin tocar la ranura ni el
  canto. Sella poros, pero también deja pasar algo menos de luz en la base.
- **Comprobar** que la ranura y el canto salen lisos (lija 600 en seco si hay granos). La junta no debe ir pegada.

### 7.4 Ensayo de estanqueidad (en cada cápsula)
1. **Ensayo 1, base sola** (con los pogos ya pegados y curados):
   - Llenar la base de agua con unas gotas de lavavajillas y dejarla 30 min sobre papel absorbente, o meterla vacía en
     agua con el borde fuera.
   - Mirar si moja por fuera o si entra agua por el fondo y las paredes.
2. **Ensayo 2, cápsula cerrada con electrónica**, en dos pasos:
   - **Vacío / burbujas:**
     - cápsula en un recipiente con agua, dentro de un bote de vacío (bomba manual de envasado al vacío) a −0,3 bar
       durante 2 min;
     - un hilo continuo de burbujas indica una fuga (las primeras burbujas sueltas son aire pegado);
     - marcar el punto.
   - **Inmersión 1 m, 30 min:**
     - con un trozo de **papel indicador de agua** (o pañuelo de papel seco) dentro, en lugar de la celda o junto a ella;
     - cápsula a 1 m de profundidad (cubo alto o piscina) 30 min;
     - secar por fuera, abrir sobre papel seco y mirar el indicador y la ranura.
3. **Ensayo de manguera** (IPX5 orientativo): chorro a 3 m durante 3 min sobre todos los lados, con la cápsula en el
   soporte. Abrir y revisar.
4. **Criterios:**
   - aceptar si el indicador está seco y no hay hilo de burbujas;
   - repetir tras 10 ciclos de apertura y cierre, y tras 20 sesiones;
   - cambiar la junta si queda marcada más de un 10 % de su alto o si se abre más de 20 veces.
5. **Mantenimiento:**
   - aclarar el sudor con agua dulce después de cada uso, sobre todo los contactos;
   - no usar disolventes;
   - guardar la cápsula seca.

## 8. Retención de la cápsula (REV 6.2)

> **Cálculo de diseño, NO VERIFICADO.** Hipótesis:
> - PETG impreso: E ≈ 2,0 GPa; resistencia en el plano de capa ≈ 40 MPa; **entre capas ≈ 25 MPa** (bien impreso);
>   deformación admisible ≤ 2–2,5 % en el plano y ≤ 1,2 % entre capas.
> - Cápsula ≈ 65 g con la celda.
> - Fórmulas de viga en voladizo (Bayer / Covestro, *snap-fit design*).

### 8.1 Requisitos
- ≥ **100 N** de tirón vertical y ≥ 50 N lateral o de giro.
- Margen ≥ 3 frente a choques de 30–50 g: 50 g × 0,065 kg × 9,81 = **32 N**, y × 3 = **96 N** ≤ 100 N.
- Bloqueo positivo, con el seguro sujeto por clic.
- Nada que se enganche.
- Holguras de 0,3–0,4 mm.
- 2000 ciclos de puesta y retirada.

### 8.2 Cálculo del pestillo
Viga en voladizo vertical: t = 1,2 mm (flexión), b = 12 mm, L = 12,9 mm desde la raíz, con el radio escalonado en la
raíz.

| Magnitud | Fórmula | Valor |
|---|---|---|
| Momento de inercia | I = b·t³/12 | 1,73 mm⁴ |
| Flecha para pasar el gancho | δ = enganche 0,9 + holgura 0,2 | 1,1 mm |
| **Deformación en la raíz al poner** | ε = 3·t·δ / (2·L²) | **1,19 %** (≤ 2–2,5 % en el plano; ≤ 1,2 % entre capas) |
| Fuerza para doblar la viga | F = 3·E·I·δ / L³ | 5,3 N |
| Fuerza para meter, por pestillo (rampa de 45°, μ = 0,3) | F·(1 + μ)/(1 − μ) | 9,9 N → ≈ 20 N los dos + ≈ 15–20 N de los tacos |
| Fuerza en el pulsador para soltar (momento en la punta, brazo ≈ 2 mm) | M = 2·E·I·δ/L² ≈ 46 N·mm | ≈ 23 N por pulsador |
| Deformación al soltar (momento) | ε = t·δ / L² | 0,8 % |
| **Retención sin seguro** (el tirón abre el gancho por momento; e = t/2 + 0,55 = 1,15 mm) | P = 2·E·I·0,9 / (L²·e) | **≈ 32 N por gancho → ≈ 65 N** (menos la precarga) |
| Flexión del gancho (en el plano de capa; h = 1,3, brazo 0,75) | σ = 6·P·0,75 / (b·h²) = 0,22·P | 40 MPa con P ≈ 180 N por gancho |
| **Raíz de la viga con el seguro puesto** (tracción + el 50 % del momento excéntrico; el otro 50 % lo toma el seguro, estimado) | σ = P/(b·t) + 0,5·P·e·6/(b·t²) = 0,27·P | 25 MPa con **P ≈ 93 N por gancho** |
| **Retención con seguro** | 2 × 93 − precarga (≈ 20 N) | **≈ 165 N** ≥ 100 N (≈ 5 veces el choque de 50 g) |
| Lateral / giro | Lo toma el cerco de 2 × 4,5 mm: σ = 6·F·h/(L·t²) con F = 50 N, h = 4,5, L = 55 | ≈ 6 MPa (≪ 25) |

**Fatiga (2000 ciclos).**
- Al poner, la raíz trabaja al 1,19 % de deformación entre capas (≈ 24 MPa, cerca del límite).
- El ensayo de §8.4 lo tiene que confirmar.
- Si se agrieta, pasar a t = 1,0 mm (ε = 1,0 %, retención con seguro ≈ 140 N) o imprimir el soporte en PETG-CF.
- El contrafuerte limita la flecha a 1,6 mm (ε = 1,7 %): el pestillo no se puede doblar de más al soltar.

### 8.3 Uso (con guantes)
**Poner la cápsula:**
1. Sacar los dos seguros: tirar de su cabeza a lo largo del lado corto (con la uña o con un gancho).
2. Presentar la cápsula con la oreja del cordón hacia +Y. Solo entra de una forma.
3. Apretar con la palma en el centro de la tapa hasta oír **los dos clics**.
4. Meter los dos seguros hasta su **clic**: su cabeza queda enrasada con el contrafuerte.
5. Comprobar tirando de la cápsula hacia arriba: no debe moverse nada.

**Quitarla** (para cargar):
1. Sacar los dos seguros.
2. Apretar **los dos pulsadores a la vez** hacia la cincha (≈ 2,5 kg cada uno) y levantar la cápsula. Si hay barro,
   aclarar antes con la manguera.

El cordón de seguridad se puede dejar atado mientras se carga, o soltar el casquillo.

### 8.4 Ensayos (en cada soporte nuevo; **pendientes**)
1. **Tirón:**
   - cápsula montada con los seguros;
   - colgar un **peso de 10 kg** (≈ 98 N) de la oreja de la tapa durante 1 min, o tirar con un dinamómetro hasta
     ≥ 100 N;
   - **aceptar** si no se suelta y no quedan marcas blancas en las raíces;
   - repetirlo **sin seguros** hasta que se suelte y anotar la fuerza (calculado: ≈ 65 N).
2. **Lateral y giro:** 5 kg colgados de lado y un par de 1,5 N·m. No debe moverse más de 0,1 mm (medir con un
   comparador o mirar el ECG en reposo: sin picos).
3. **Vibración:**
   - **1 h en una lijadora orbital** (sin lija), con el soporte atornillado a una tabla y la cápsula en marcha
     enviando IMU y ECG;
   - o **1 h al trote** con la cincha puesta;
   - **aceptar** si no hay huecos en los lotes, picos de ECG por movimiento, seguros desplazados ni polvo blanco de
     desgaste.
4. **Caída:**
   - **1,5 m sobre suelo duro** (hormigón), 3 veces, con la cápsula montada en el soporte atornillado a un trozo de
     funda;
   - **aceptar** si no se suelta, no hay grietas y pasa luego el ensayo de estanqueidad (§7.4).
5. **Ciclos:** **2000 puestas y retiradas**, revisando las raíces cada 250. Si aparece una marca blanca o una grieta,
   el soporte se rechaza.
6. **Barro y arena:** meter el soporte en barro, aclarar con manguera y comprobar que la cápsula entra, encaja y se
   suelta igual.

## 9. Notas sobre la funda de piel

- **Curtido vegetal frente a cromo.**
  - El **vegetal** se puede rebajar, moldear y coser con canto limpio. Mantiene la forma (canales, soporte) y es
    el habitual en guarnicionería. Con el sudor se oscurece y se endurece si no se engrasa.
  - El **cromo** es más blando y aguanta mejor el agua, pero se deforma más. Además puede llevar restos de cromo
    (VI), que es alérgeno de contacto y está limitado en la UE.
  - Recomendado: **vegetal de 2,0 mm (≈ 5 oz)** para el cuerpo, con acabado graso (aceite de pie de buey + cera) por
    las dos caras. Y vegetal de 1,2 mm para los canales.
- **Grosor.** Con 2,0 mm el soporte se sujeta bien. Alrededor de los electrodos hay que rebajar a
  1,0 mm, porque con 2 mm el electrodo quedaría 2 mm por dentro y perdería contacto.
- **Costura.** Punto de guarnicionero a mano, hilo de poliéster encerado de 0,8 mm, pinzas de 4 mm, a 4 mm del
  canto. No usar hilo de algodón, que el sudor pudre.
- **ECG y sudor.**
  - La piel seca aísla. Empapada de sudor salino conduce algo.
  - Los centros de los electrodos están a 13 cm (REF–ECG−) y 47 cm (ECG+–ECG−), así que la fuga por la piel mojada es
    pequeña frente a la impedancia del ADS1292. Aun así, conviene encerar bien la cara interior entre ventanas.
  - Los cantos de las ventanas se sellan con tinte de cantos.
  - Lavar los electrodos de caucho con agua después de cada uso (la sal reseca el caucho y sube la resistencia).
- **Limpieza.** Jabón de glicerina y engrase. La funda se quita de la cincha (velcro + trabillas) para lavar la
  cincha de tela.

## 10. Limitaciones (leer antes de fabricar)

1. **Nada está verificado físicamente**: ni impresión, ni costura, ni ajuste en una cincha real, ni ECG en un caballo.
2. **Medidas de la cincha y del tórax ESTIMADAS.** No hay ficha con anchos ni gruesos (§2), y el tórax es una
   superelipse. **Medir la cincha real** (ancho, grueso, posición de la anilla D) y cambiar `P` en
   `avo_cincha_montaje.py` antes de cortar la piel.
3. **Electrodo Vialta:**
   - el grosor (2 mm) y la posición del cable moldeado son estimados, porque no se encontró la ficha;
   - el electrodo pequeño de REF es genérico.
4. **STEP poliédrico.** Lo genera un núcleo propio (no había CadQuery/OCP ni FreeCAD en el entorno):
   - caras planas y arcos en facetas; las piezas curvadas, trianguladas;
   - todas las piezas son sólidos cerrados (`verificar_step.py`: 0 aristas mal cosidas y todos los vértices en su
     plano);
   - **no se ha abierto en FreeCAD/SolidWorks aquí**: hay que comprobarlo al abrirlo;
   - para editar, cambiar los parámetros de los scripts.
5. **Comprobaciones del modelo:**
   - **sin cálculo automático de interferencias** entre piezas: las holguras salen de la aritmética del diseño;
   - los electrodos y su espuma se curvan con la cincha;
   - el soporte y la cápsula son rígidos sobre una cincha de radio ≈ 340 mm: flecha de ≈ 1,3 mm en 60 mm, que absorbe
     la piel.
6. **PCB modelada a partir de `piezas.json`:**
   - el módulo ESP32-C6-MINI-1U va como caja de 13,2 × 12,5 × 2,4;
   - el resto, cajas por huella;
   - el U.FL y la salida del coaxial alrededor del canto +X de la PCB tienen **posición aproximada**.
7. **Antena:** ≈ 5 mm por encima del borde de la celda y a ≈ 3 mm del canto de la PCB. La ganancia real será 1–2 dB menor que en la hoja
   de datos (lo dice Molex). Comprobar el RSSI.
8. **Altura.** Unos 46 mm sobre la piel del caballo en el centro de la cincha, bajo el esternón (≈ 32 mm sobre la
   cara exterior de la cincha: soporte 8 + tacos 0,7 + cápsula 15,5 + panel exterior). El conector de pines (7,5 mm) es lo que más suma. Valorar si molesta al caballo al plegar los
   brazos en el salto.
9. **Cables:**
   - van sin apantallar (los del electrodo Vialta) y solo se trenzan;
   - si hay ruido de movimiento, pasar a cable ECG apantallado (§3.5).
10. **Estanqueidad (REV 6.1):**
    - IP67 es el **objetivo**, sin ensayar (§7);
    - la junta de TPU 85A impresa y la porosidad del PETG impreso son los puntos que más dependen de la impresora;
    - si el ensayo 2 falla en la junta, alternativa: junta de cordón de silicona de Ø1,5 (juego de juntas tóricas
      cortadas y pegadas con cianoacrilato) en la misma ranura.
11. **Aro de luz (REV 6.1):**
    - los LED son del cambio de PCB en curso (`feature/girth-pcb-rev-d-aro`), con las cotas del 15/11;
    - toda la base brilla, y el fondo la deja ver un poco por el soporte;
    - el reparto de la luz en la pared **no está simulado**: hay que probarlo
      con una base impresa;
    - los hilos del pogo del ECG pasan cerca de la lente de D13: llevarlos por debajo de la PCB.
12. **Soporte encapsulado:** con silicona o resina, los conectores de pines del soporte ya no se pueden desmontar sin
    romperla.
13. **Pestillos (REV 6.2):**
    - van impresos de pie, así que la flexión de la viga carga **entre capas**. Por eso la deformación se limita al
      1,19 % y se dan ajustes de impresión (§5), pero la fatiga a 2000 ciclos **hay que ensayarla** (§8.4);
    - el reparto del momento entre la raíz y el seguro (50 %) es una estimación;
    - las fuerzas para meter y para soltar dependen de cómo salga la rampa impresa y de la fricción.
14. **Cápsula expuesta:** sin bolsillo, la tapa roja y la base translúcida quedan a la vista y pueden recibir golpes
    directos. El cerco, los contrafuertes y el cordón protegen frente a la pérdida, no frente al impacto. Se ensaya con
    la caída de §8.4.
15. **Oreja del cordón:** sobresale 4,6 mm del contorno de la base, en la parte alta del lado +Y. Tiene radio R3, pero
    hay que vigilar que no se enganche.

## 11. Cómo regenerar

```bash
cd hardware/girth/CINCHA_MONTAJE/fuente
python3 avo_cincha_montaje.py      # STEP + STL + informe (≈ 1 min)
python3 patron_funda.py            # patrón SVG/DXF
python3 render.py                  # renders PNG (≈ 2,5 min)
python3 verificar_step.py ../out/STEP/*.step ../out/STEP/piezas/*.step
```
Solo necesitan Python 3 con numpy, OpenCV (`cv2`) y Pillow.
