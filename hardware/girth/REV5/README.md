# AVO GIRTH REV 5: cápsula estanca de 70 × 48 mm, 8 tornillos M3 y 4 + 4 imanes

- **Fuente:** `avo_girth_rev5.py` (CadQuery). El CI («Build AVO GIRTH CAD») genera `out/`. Resultado actual: **8 piezas, 1 sólido cada una, interferencias: ninguna**.
- **Base:** REV 4 (estanca, sin aberturas, junta TPU), con lo que pidió el usuario.

## Cambios
- **8 tornillos M3 × 9–10** desde abajo, repartidos junto a las esquinas: 2 en cada lado largo y 2 en cada extremo.
  - Cada uno lleva una **junta tórica NBR 3 × 1** bajo la cabeza, en un avellanado de Ø5,9 × 3,7 mm, que sella el agujero.
  - Roscan en un agujero piloto de Ø2,5 en la tapa (3,6 mm de rosca con M3 × 9).
- **4 imanes de neodimio Ø5 × 1** en las esquinas del fondo de la cápsula, por dentro y bajo 0,3 mm de piel.
  - Otros **4 iguales enfrentados en el soporte**. Al montarlos, hay que poner las caras de distinta polaridad enfrentadas.
- **Cápsula de 70 × 48 × 15,5 mm** (antes 64 × 46): es lo mínimo para que los 8 M3 queden dentro de la junta sin tocar la batería.
- **Interior redistribuido:**
  - **BNO085 en el centro**, para que su magnetómetro quede lo más lejos posible de los imanes (~35 mm de las esquinas);
  - placa Qi en el extremo −X;
  - ESP32-C6 girado en el extremo +X, con el USB-C hacia +Y, dentro.
- **Sujeción del ESP32-C6:**
  - **en X y en Y:** un marco en los 4 costados, con 0,15 mm de holgura y 1,2 mm de pared. Su altura es la del PCB (1,0 mm), así que queda a ras de la cara superior y los cables soldados a los pads laterales salen por encima;
  - **hacia abajo:** apoya en rebordes de 1 mm; debajo queda una ventana para los cables soldados por la cara inferior;
  - **hacia arriba:** 2 postes de la tapa aprietan el extremo de la antena y un tope de la tapa aprieta el conector USB-C. Las esquinas del lado USB tienen los botones R/B, por eso no se aprieta ahí.
- **Imán del reed (soporte):** 1 × Ø5 × 1, en lugar de 2 × Ø6 × 2. Queda a ~1 mm del reed, así que lo activa con mucho margen, y en el BNO da ~180 µT en lugar de ~1000 µT.

## Polaridad de los imanes de las esquinas (importante para el magnetómetro)
- Cada pareja (imán de la cápsula y el del soporte debajo) se coloca de modo que **se atraigan**.
- **Las diagonales llevan polaridad contraria:**
  - esquinas (+X,+Y) y (−X,−Y): norte hacia arriba;
  - esquinas (+X,−Y) y (−X,+Y): sur hacia arriba.
- **Efecto en el BNO (estimado con un modelo de dipolo, N35):**
  - con esta disposición, los 8 imanes dan ~40 µT en el BNO;
  - con todos iguales darían ~250 µT;
  - como referencia, el campo de la Tierra es de 25–65 µT.
- **Lo que queda es un desvío fijo**, porque los imanes se mueven con el sensor. El BNO085 lo compensa con su calibración dinámica: calibra con la cápsula puesta en el soporte.
- **Para la marcha:** el vector de rotación de juego (`Game Rotation Vector`, solo acelerómetro y giroscopio) no usa el magnetómetro y no le afecta ningún imán.
- **Reed** en el centro del lado −Y. El imán de la cápsula más cercano queda a unos 21 mm. Antes de cerrar, comprueba con el reed en la mano que esos imanes no lo activan.
- **Soporte:** 94,4 × 58,4 mm, el mismo diseño de una pieza, con las 4 cavidades para los imanes Ø5 × 1.

## Impresión y prueba
- **Impresión:** igual que REV 4.
  - Base y tapa: 5 perímetros, 6 capas arriba y abajo y relleno al 100 %.
  - Junta: TPU 85A a su altura libre de 1,4 mm.
- **IP67 no está probado.** Para comprobarlo: papel absorbente dentro, 30 min sumergida a 1 m, y el papel tiene que salir seco.
