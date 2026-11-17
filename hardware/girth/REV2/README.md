# AVO GIRTH REV 2: caja de la cincha y soporte, fiel al concepto REV 0

- **Fuente:** `avo_girth_rev2.py` (CadQuery). El CI («Build AVO GIRTH CAD») genera `out/` y comprueba que cada pieza sea un único sólido y que no haya interferencias. Resultado actual: **8 piezas, 1 sólido cada una, interferencias: ninguna**.
- **Respecto a REV 1:**
  - fuera las colas de milano y las costillas aplastables; el fondo de la cápsula queda liso para la base Qi;
  - aspecto del concepto (`REV0/out_hero.png`): aro rojo entre base y tapa, panel rojo arriba con AVO / GIRTH en relieve, cerco alrededor de la cápsula, pasadores de cinta en los extremos y tirador rojo en el extremo +X.
- **Piezas.** Cada pieza se imprime de un solo color, sin cambio de filamento:

| Pieza | Material | Orientación |
|---|---|---|
| base | PETG negro | fondo en la cama |
| tapa | PETG negro | boca abajo |
| bandeja | PETG (cualquiera) | plana |
| soporte | PETG negro | placa en la cama |
| aro rojo | PETG rojo | plano |
| panel rojo | PETG rojo | plano, logo arriba |
| tirador rojo | PETG rojo | de lado |
| tapón USB | TPU 95A | — |

  Las 3 piezas rojas caben en una sola impresión.
- **Anclaje:**
  - cerco con la silueta de la cápsula, holgura de **0,12 mm por lado**: no se mueve en X ni en Y;
  - **extremo −X:** el labio del cerco entra 0,6 mm en una ranura de la base;
  - **extremo +X:** el tramo del cerco es una pestaña elástica de 1,6 mm con diente. La cara inferior del diente es horizontal, así que tirar de la cápsula hacia arriba (galope) no abre la pestaña;
  - holgura vertical del labio y del diente: 0,10 mm.
- **Poner y quitar:**
  - **poner:** inclinar la cápsula, meter el extremo −X bajo el labio y bajar el extremo +X hasta el clic;
  - **quitar:** tirar del tirador rojo hacia fuera y levantar el extremo +X.
- **Montaje:**
  - bobina Qi pegada en su rebaje;
  - batería en su cuna;
  - reed en su canal;
  - bandeja con el C6, la placa Qi y el BNO085;
  - antena FPC en la tapa;
  - aro rojo sobre la base;
  - tapa cerrada con 2 × M2 × 10 desde abajo;
  - panel rojo y tirador rojo pegados con cianoacrilato;
  - 2 imanes Ø6 × 2 en el soporte.
- **Cinta:** de 50 mm, por los 2 pasos de 3,6 × 52 mm entre la placa y los pasadores, cosida a la cincha.
- **Provisional (pendiente de calibre y probetas):**
  - holguras de 0,12 y 0,10;
  - taladros del BNO085;
  - LED del C6;
  - fuerza de la pestaña;
  - cierre del reed.
  - El GIRTH del concepto es gris; aquí va en relieve rojo, del mismo filamento que el panel (se puede pintar).
