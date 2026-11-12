# AVO GIRTH REV 3: interior ajustado a los componentes reales y soporte de una sola pieza

- **Fuente:** `avo_girth_rev3.py` (CadQuery). El CI («Build AVO GIRTH CAD») genera `out/` y comprueba que cada pieza sea un único sólido y que no haya interferencias entre piezas ni con los componentes de referencia.
  - **Resultado actual:** 8 piezas, 1 sólido cada una, interferencias: **ninguna**.
- **Aspecto:** el del concepto REV 0, igual que REV 2: aro y panel rojos, logo en relieve y tirador rojo.

## Cambios respecto a REV 2

### BNO085 (GY, HanOaki, 25,8 × 15,5)
- Los 2 taladros están en el lado largo **opuesto a los 10 pines**, uno en cada extremo. En REV 2 estaban en diagonal.
- 2 postes M2 en los taladros, 2 apoyos junto a los pines y 2 topes en los extremos.
- Los pines miran hacia el C6.

### ESP32-C6 (formato XIAO, 21 × 18)
- El borde del PCB hace tope a 0,4 mm de la pared, con el USB-C hacia fuera. El conector queda a ~1,1 mm de la cara exterior, con un rebaje de 0,6 mm para la funda del cable. En REV 2 quedaba hundido 3,3 mm y el cable no llegaba a entrar.
- La bandeja tiene una ventana bajo el C6 para soldar cables por debajo.
- Los lados con pads quedan libres para soldar.
- Las escuadras van en el extremo de la antena y 2 postes de la tapa sujetan el PCB, apartados del U.FL y de la antena cerámica.

### Placa Qi (18 × 15)
- Marco con huecos para los hilos de la bobina (−X) y la salida (+X).
- 2 postes de la tapa la sujetan.

### Batería
- Cuna cerrada que impide que se deslice en X, con un hueco en +X/−Y para los cables del PCM.
- Paso de cables en la bandeja.

### Bobina Qi
- Canal en el fondo para sus hilos, que suben junto a la pared −X.

### Reed
- Desplazado a x = 6 para que sus patas suban fuera de la placa Qi.

### Soporte
- **Una sola pieza compacta de 88,4 × 58,4 mm:**
  - pasos de cinta **cerrados** de 52 × 3,6 mm;
  - bordes redondeados;
  - canal de 0,4 mm por debajo para la cinta;
  - sin barras ni patas sueltas.
- **Mismo anclaje que REV 2:**
  - cerco a 0,12 mm por lado;
  - labio en −X;
  - pestaña elástica con diente en +X y tirador rojo.

## Medidas que hay que confirmar con calibre
Las marcadas (E) en el código son estimaciones hechas sobre la foto del anuncio:
- posición del LED, del U.FL y de la antena del C6, y cuánto sobresale el USB-C;
- distancia de los taladros del BNO al borde (2,6 mm);
- espesor de la bobina Qi.

Si alguna no coincide, se cambia el número en el script y el CI regenera todo.

## Impresión
| Pieza | Material | Orientación |
|---|---|---|
| base | PETG negro | fondo en la cama |
| tapa | PETG negro | boca abajo |
| bandeja | PETG | plana |
| soporte | PETG negro | placa en la cama |
| aro, panel, tirador | PETG rojo | en una sola impresión |
| tapón USB | TPU 95A | — |

## Montaje
- **Cables:** corta el conector JST de la batería y suelda los cables.
- **BNO085:** atorníllalo con 2 × M2 × 4 de rosca chapa.
- **Tapa:** ciérrala con 2 × M2 × 10 desde abajo.
- **Pegado (cianoacrilato):** panel y tirador.
- **Imanes:** 2 × Ø6 × 2 en el soporte.
