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
  - BNO085 girado en el extremo −X, con sus 2 taladros reales;
  - placa Qi en el centro;
  - ESP32-C6 girado en el extremo +X, con el USB-C hacia +Y, dentro.
- **Reed** en el centro del lado −Y. El imán de la cápsula más cercano queda a unos 21 mm. Antes de cerrar, comprueba con el reed en la mano que esos imanes no lo activan.
- **Soporte:** 94,4 × 58,4 mm, el mismo diseño de una pieza, con las 4 cavidades para los imanes Ø5 × 1.

## Impresión y prueba
- **Impresión:** igual que REV 4.
  - Base y tapa: 5 perímetros, 6 capas arriba y abajo y relleno al 100 %.
  - Junta: TPU 85A a su altura libre de 1,4 mm.
- **IP67 no está probado.** Para comprobarlo: papel absorbente dentro, 30 min sumergida a 1 m, y el papel tiene que salir seco.
