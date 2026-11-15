# AVO GIRTH · montaje del sistema en la cincha (cápsula REV 6, funda de piel y electrodos ECG)

> **Estado: diseño · NO VERIFICADO en caballo real.** No se ha impreso, cosido ni montado nada. Los STEP no se han
> abierto en FreeCAD dentro de este entorno (no está instalado). Solo pasaron la comprobación automática de
> `fuente/verificar_step.py`. Ver «Limitaciones».

Fecha: 15/11/2026 · Rama: `feature/cincha-cad-montaje` · Arquitectura confirmada por el usuario: PCB REV D
(ESP32-C6-MINI-1U + LSM6DSV16X + MMC5983MA + ADS1292) sobre una celda de 1000 mAh, conectores pogo magnéticos de 3
contactos (carga y ECG) y dos electrodos de caucho conductor (más un tercero de referencia, opcional).

## 1. Qué hay en esta carpeta

| Ruta | Contenido |
|---|---|
| `out/STEP/AVO_CINCHA_MONTAJE_CONJUNTO_CURVADO.step` | **Conjunto completo** curvado sobre el tórax: cincha, funda, bolsillo, soporte, cápsula, PCB, celda, antena, pogos, tornillería, electrodos, espuma y cables (87 sólidos en 9 subconjuntos) |
| `out/STEP/AVO_CINCHA_MONTAJE_CONJUNTO_RECTO.step` | El mismo conjunto con la cincha recta (tumbada, con la cara interior abajo) |
| `out/STEP/AVO_CINCHA_R6_CAPSULA_CONJUNTO.step`, `..._SOPORTE_CONJUNTO.step` | Subconjuntos de la cápsula y del soporte, en coordenadas locales |
| `out/STEP/REF_torax_caballo_seccion.step` | Sección del tórax de referencia (300 mm de largo) |
| `out/STEP/piezas/*.step` | Un STEP por pieza: impresas, PCB, celda, antena, electrodo, funda, cincha Decathlon y Horze (recta y curvada) |
| `out/STL/*.stl` | Piezas impresas, ya colocadas para imprimir |
| `out/PATRON/AVO_CINCHA_funda_piel_patron.{svg,dxf}` | Patrón plano 1:1 de la funda, en mm, con capas de corte, pliegue, costura, agujeros cada 4 mm, rebaje, taladros y marcas |
| `out/informe.json` | Medidas, volúmenes, longitudes de cable y comprobaciones |
| `out/AVO_CINCHA_MONTAJE.zip` | Todo lo anterior junto, para descargar |
| `renders/*.png` | Renders de comprobación (01–11) |
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

### 3.1 Cápsula REV 6 (`AVO_CINCHA_R6_*`)
- **Exterior:** 59,4 × 54,5 × 14,7 mm, con las orejas de los 6 tornillos. Interior de 51 × 43,75 mm.
- **Base** (PETG negro, suelo de 1,7 mm):
  - celda 603450 apoyada en el suelo (z 1,7–7,7);
  - dos placas pogo en el lado −Y, una junto a otra, con la cara a ras del fondo:
    - **ECG** en x = −13, junto a los pads P4–P6;
    - **carga** en x = +13;
  - alrededor de cada placa, una copa de epoxi de 0,8 mm de pared y 5 mm de alto;
  - 6 alojamientos de inserto M2 × 4 (Ø3,2 × 4,5).
- **Tapa** (PETG rojo, techo de 1,8 mm):
  - la PCB **cuelga de la tapa** con 4 tornillos M2 × 5 ISO 7380 inox, roscados en guías de Ø1,75 de 4 columnas
    de Ø4,4 (caben en la zona libre de 2,2 mm de los taladros);
  - la cara B de la PCB apoya sobre la celda a través del **separador TPU 85A** de 1,2 mm, que deja huecos para las
    cabezas de los tornillos;
  - lengüeta de 1,0 mm que entra 1,9 mm en la base y centra la tapa;
  - **antena Molex pegada al techo** en un rebaje de 0,3 mm, fuera de la planta de la PCB (encima de los pogos),
    lejos del plano de masa;
  - ventana ciega Ø3,2 sobre el LED D1, con 0,6 mm de piel de PETG;
  - 6 avellanados para cabeza ISO 7380.
- **Junta** de TPU 85A, plana, de 0,8 mm, entre la base y la tapa. Cierre con **6 tornillos M2 × 8 ISO 7380 inox**
  en insertos M2 × 4.
- **Pila en z (mm):**

  | Pieza | z |
  |---|---|
  | Suelo | 0–1,7 |
  | Celda | 1,7–7,7 |
  | Separador | 7,7–8,9 |
  | PCB | 8,9–9,9 |
  | Componentes | hasta 12,5 |
  | Aire | 0,4 |
  | Techo | 12,9–14,7 |

- **Hilos** (silicona AWG 28):
  - contactos del pogo del ECG → P4 (ECG+), P5 (REF) y P6 (ECG−);
  - contactos del pogo de carga → P1 (5 V), P2 (GND) y P3 (DET);
  - celda → J2/J6, sin conector, como pide la REV D.

### 3.2 Soporte (`AVO_CINCHA_R6_soporte`, PETG)
- 80 × 75 × 10,5 mm: cama de 8 mm y cerco de 2,5 mm que abraza la cápsula con 0,3 mm de holgura.
- Lleva los **dos conectores de pines** (carga + ECG):
  - cara a ras de la cama;
  - orejas sujetas con 2 tornillos M2 × 4 cada uno, en guías de Ø1,6;
  - hueco abierto por abajo para soldar las colas.
- En el conector de **carga**, un puente 2–3 (DET): la cápsula sabe que está montada, igual que en la REV 5.9.
- Ala de 2,5 mm con **4 tornillos de Chicago de Ø5**, que lo fijan al panel exterior de la funda. Se puede
  desmontar.
- La cápsula se saca del soporte para cargarla en una base con otro conector de pines.

### 3.3 Funda de piel
Funda de 800 mm de largo que envuelve la parte central de la cincha. Se corta de **una sola pieza** (patrón A) que,
en este orden, forma:
1. panel exterior;
2. pliegue delantero;
3. panel interior;
4. pliegue trasero;
5. solapa de 30 mm, que cierra sobre el panel exterior con **velcro de coser de 25 mm**.

La solapa se interrumpe donde está el bolsillo.

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
- **Bolsillo:** tapa con ventana de 40 × 28 sobre la tapa roja, fuelle cosido al panel exterior y lengüeta con
  broche de presión de 15 mm.
- **Ventana de 40 mm** en el pliegue delantero para la pestaña de la anilla D central de la cincha.
- **Trabillas** (pasadores) de 25 mm en los dos extremos.

### 3.4 Cables
- El cable moldeado de cada electrodo Vialta se corta y se le quita la banana.
- Recorrido: por el canal delantero, sube por encima de la cincha y llega a un **empalme JST-SH de 3 vías**
  (SHR-03V-S y su pareja de cable), dentro de la funda, bajo la ranura de 14 × 7 del panel exterior.
- Un rabillo de 3 hilos sube por la ranura hasta las colas del conector de pines del ECG.
- Correspondencia: contactos 1/2/3 del pogo → P4/P5/P6 de la PCB.

| Cable | Longitud | Conexión |
|---|---|---|
| ECG+ | 210 mm | contacto 1 → P4 |
| REF | 163 mm | contacto 2 → P5 (RLD, por R43 de 100 kΩ) |
| ECG− | 282 mm | contacto 3 → P6 |

Las longitudes son las del modelo, todas < 40 cm. Se recomienda añadir 30 mm de reserva.
- **Trenzado:** REF y ECG− van trenzados en el tramo común, del soporte a u = −125.
- El cable de ECG+ se puede trenzar con un hilo de retorno unido a REF solo en el extremo del soporte. Hace de guarda.
- **Interpretación del pedido «JST-SH/PH hacia P4/P5/P6».** El JST no va soldado a la PCB, que está dentro de la
  cápsula estanca. Va al conector de pines del soporte, y el pogo lleva cada contacto a P4–P6. Así la cápsula
  se sigue pudiendo sacar para cargarla.

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
| 6 | Insertos térmicos M2 × 4 | ruthex (70 uds.) | 6 | 8,38 $ el juego |
| 7 | Tornillos inox ISO 7380 M2 × 8 (6), M2 × 5 (4), M2 × 4 (4) | Kit M2 inox | 14 | ≈ 6 € |
| 8 | Hilo de silicona AWG 28 (3 colores) | — | 1 m | ≈ 3 € |
| 9 | Epoxi transparente 5 min (copas de los pogos) + silicona neutra | — | 1 | ≈ 6 € |
| 10 | Filamento PETG (≈ 48 cm³ ≈ 62 g) y TPU 85A (≈ 2 cm³) | — | — | ≈ 2 € |
| 11 | Electrodo Vialta PG980/51 60 × 85 | Vialta | 2 | 2 × 11,58 € = 23,16 € |
| 12 | (opcional) electrodo pequeño para REF/RLD, ≈ 40 × 60 | Vialta u otro de caucho | 1 | ≈ 8 € (ESTIMADO) |
| 13 | Empalme JST-SH 1,0 mm, 3 vías, macho-hembra con cable | AliExpress | 1–2 | ≈ 3 € |
| 14 | Piel de curtido vegetal 2,0 mm (≈ 0,35 m²) + retal de 1,2 mm para el canal | Tandy / guarnicionería | 1 | ≈ 45 € (≈ 12–15 £/ft²) |
| 15 | Velcro de coser 25 mm (gancho + rizo) | mercería | 0,7 m | ≈ 3 € |
| 16 | Tornillos de Chicago Ø5 (juego de 30, 5 × 15 mm) | [ManoMano](https://www.manomano.es/p/30-juegos-de-tornillos-de-encuadernacion-chicago-tornillos-de-encuadernacion-niquelados-5-mm-x-15-mm-tono-plateado-84620168) | 4 | ≈ 8 € |
| 17 | Broche de presión de 15 mm (latón/inox) | mercería | 1 | ≈ 1 € |
| 18 | Hilo encerado de poliéster de 0,8 mm + 2 agujas de guarnicionero | — | 1 | ≈ 7 € |
| 19 | Espuma EVA o neopreno de 2–3 mm (A4) | — | 1 | ≈ 3 € |
| — | **Total (con la cincha Decathlon y el electrodo REF)** | | | **≈ 190 €** |
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
| Base | PETG | Fondo sobre la cama | 0,2 mm, 4 perímetros, 30 % gyroid. Copas y alojamientos de insertos sin soportes |
| Tapa | PETG rojo | **Boca abajo** (techo sobre la cama) | 0,2 mm, 4 perímetros. Las columnas de la PCB y la lengüeta quedan hacia arriba |
| Soporte | PETG | Ala sobre la cama | 0,2 mm, 4 perímetros, 40 %. El rebaje de las orejas queda abierto por arriba |
| Junta | TPU 85A | Plana | 0,2 mm, 100 %, lento (≤ 20 mm/s) |
| Separador | TPU 85A | Plano | 0,2 mm, 100 % |

Holguras: 0,3 mm cápsula–soporte, 0,15 mm en el cuerpo de los pines, 0,2 mm en la placa pogo y la lengüeta.
**Imprimir primero una base y un soporte de prueba** y comprobar los pogos y los insertos con el calibre.

## 6. Montaje paso a paso

**Cápsula**
1. Insertos M2 × 4 en los 6 alojamientos de la base, con la punta térmica a 220 °C, enrasados.
2. Placas pogo en sus ventanas, desde dentro, con la cara a ras del fondo. **Mirar la orientación:** contacto 1 en
   el lado −X de cada placa.
3. Soldar 3 hilos AWG 28 de 40 mm a cada placa. Llenar las copas con epoxi hasta tapar las colas. Dejar curar 24 h.
4. Prueba de estanqueidad del fondo: base sola, con el epoxi curado, 10 min en agua. Secar.
5. Pegar la antena Molex en el rebaje del techo de la tapa (adhesivo propio). Conectar el U.FL al módulo **antes** de
   atornillar la PCB.
6. Atornillar la PCB a las 4 columnas de la tapa con M2 × 5 ISO 7380, sin pasarse de apriete (la rosca es en PETG).
7. Soldar los hilos:
   - placa ECG → P4/P5/P6;
   - placa de carga → P1/P2/P3;
   - celda → J2 (+) y J6 (−).
   Comprobar la polaridad antes de soldar el −.
8. Separador TPU sobre la celda. Junta sobre la base. Cerrar con 6 M2 × 8, apretando en cruz.

**Soporte**

9. Conectores de pines en sus alojamientos, con 2 M2 × 4 cada uno.
   - Conector de **carga**: puente entre los contactos 2 y 3.
   - Conector del **ECG**: rabillo de 3 hilos con la mitad del JST-SH.
10. Sellar las colas con silicona neutra (el soporte va contra la piel del panel exterior).

**Funda**

11. Cortar el patrón A, B1, B2, C1–C3 y D1–D2 (`out/PATRON/*.dxf`, 1:1, comprobar la escala con el texto de 7 mm).
12. Rebajar a 1,0 mm las franjas marcadas en naranja alrededor de las ventanas. Abrir las ventanas, la ranura del cable
    (14 × 7), la ventana de la anilla D y los 4 taladros de Ø5.
13. Coser los canales C1–C3 por el lado carne del pliegue delantero (líneas de costura a 4 mm).
14. Para cada electrodo:
    - presentarlo por el lado carne sobre su ventana;
    - coser el perímetro con punto de guarnicionero por el solape de 5 mm (agujeros a 4 mm);
    - pegar detrás la espuma EVA con cola de contacto, solo por los bordes.
15. Coser el velcro: rizo en el panel exterior, gancho en el lado carne de la solapa.
16. Coser el bolsillo: el fuelle B2 al panel exterior por la marca verde, y la tapa B1 al fuelle por 3 lados. La
    lengüeta queda libre, con el broche.
17. Fijar el soporte al panel exterior con los 4 tornillos de Chicago (con una gota de fijador de roscas suave).

**Cables**

18. Cortar la banana de cada electrodo y recortar el cable:
    - ECG+ ≈ 240 mm;
    - REF ≈ 190 mm;
    - ECG− ≈ 310 mm.
19. Trenzar REF con ECG− en el tramo común. Crimpar los 3 en la otra mitad del JST-SH: 1 = ECG+, 2 = REF, 3 = ECG−.
20. Pasar los cables por los canales y conectar el JST bajo la ranura.

**Colocación**

21. Meter la cincha en la funda, con la anilla D por su ventana. Cerrar el velcro y pasar las trabillas.
22. Cápsula en el soporte (los imanes de los pogos la centran) y cerrar la tapa del bolsillo.

**Comprobaciones antes del caballo** (todas **pendientes**)
- Continuidad electrodo → contacto del pogo de la cápsula (< 2 kΩ con el caucho húmedo).
- Aislamiento entre electrodos con la funda seca (> 10 MΩ).
- DET = 0 con la cápsula en el soporte.
- Radio: RSSI con la espalda a 1 m, con la cápsula dentro del bolsillo.
- ECG en reposo con los electrodos y el pelo mojados, como pide Polar Equine.

## 7. Notas sobre la funda de piel

- **Curtido vegetal frente a cromo.**
  - El **vegetal** se puede rebajar, moldear y coser con canto limpio. Mantiene la forma (bolsillo, canales) y es
    el habitual en guarnicionería. Con el sudor se oscurece y se endurece si no se engrasa.
  - El **cromo** es más blando y aguanta mejor el agua, pero se deforma más. Además puede llevar restos de cromo
    (VI), que es alérgeno de contacto y está limitado en la UE.
  - Recomendado: **vegetal de 2,0 mm (≈ 5 oz)** para el cuerpo, con acabado graso (aceite de pie de buey + cera) por
    las dos caras. Y vegetal de 1,2 mm para los canales.
- **Grosor.** Con 2,0 mm el bolsillo y el soporte se sujetan bien. Alrededor de los electrodos hay que rebajar a
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

## 8. Limitaciones (leer antes de fabricar)

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
8. **Altura.** Unos 45 mm sobre la piel del caballo en el centro de la cincha, bajo el esternón (≈ 31 mm sobre la
   cara exterior de la cincha: soporte 8 + cápsula 14,7 + funda y bolsillo). El conector de pines (7,5 mm) es lo que más suma. Valorar si molesta al caballo al plegar los
   brazos en el salto.
9. **Cables:**
   - van sin apantallar (los del electrodo Vialta) y solo se trenzan;
   - si hay ruido de movimiento, pasar a cable ECG apantallado (§3.5).
10. **Sellado.** IP no calculado. Solo una junta plana de TPU con 6 M2 (prueba de inmersión pendiente).

## 9. Cómo regenerar

```bash
cd hardware/girth/CINCHA_MONTAJE/fuente
python3 avo_cincha_montaje.py      # STEP + STL + informe (≈ 1 min)
python3 patron_funda.py            # patrón SVG/DXF
python3 render.py                  # renders PNG (≈ 2,5 min)
python3 verificar_step.py ../out/STEP/*.step ../out/STEP/piezas/*.step
```
Solo necesitan Python 3 con numpy, OpenCV (`cv2`) y Pillow.
