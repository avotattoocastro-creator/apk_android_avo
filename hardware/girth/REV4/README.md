# AVO GIRTH REV 4: cápsula estanca (objetivo IP67)

- **Fuente:** `avo_girth_rev4.py` (CadQuery). El CI («Build AVO GIRTH CAD») genera `out/` y comprueba un sólido por pieza y cero interferencias. Resultado actual: **8 piezas, ninguna interferencia**.
- **Base:** REV 3 (componentes reales y soporte de una pieza), con estos cambios.

## Qué cambia para que sea estanca
- **Ninguna abertura al exterior:**
  - el USB-C del C6 queda dentro;
  - sin ventana de LED;
  - sin tapón.
- **Junta en el cierre:**
  - la base tiene un reborde interior en su borde superior con una ranura de 1,4 × 1,0 mm;
  - la junta de TPU (sección de 1,2 × 1,4 mm) sobresale 0,4 mm;
  - la tapa apoya plástico contra plástico en el reborde, así que la junta queda comprimida siempre al 29 %, aprietes lo que aprietes los tornillos;
  - la ranura es continua todo alrededor.
- **Tornillos:** 2 × M2 × 10 desde abajo. Su agujero queda dentro de la junta, así que cada uno lleva una **junta tórica NBR 2 × 1 mm** bajo la cabeza, en el fondo del avellanado (Ø4,4), que sella el agujero.
- **Aro rojo:** queda por fuera de la junta; es solo estético.
- **Fondo:** sigue liso para la base Qi.

## Consecuencias
- **Programar por USB:** hay que quitar los 2 tornillos y abrir la tapa. Para evitarlo, el siguiente paso sería actualizar el firmware de la cincha por radio a través de la espalda.
- **LED del C6:** no se ve desde fuera. El estado se puede mostrar en la app.

## Impresión para estanqueidad (PETG)
- 5 perímetros, 6 capas arriba y abajo, 100 % de relleno en base y tapa, capa de 0,16–0,2 mm.
- Sin costuras en las caras de la junta: alinea la costura a una esquina trasera.
- **Junta:**
  - TPU 85A, impresa con su altura libre de 1,4 mm, 2 perímetros y relleno del 100 %;
  - alternativa: cordón de silicona de Ø1,5 mm pegado en la ranura.
- Opcional: barniz o resina epoxi fina por fuera de base y tapa para cerrar los poros.

## Prueba antes de usar
**IP67 es el objetivo de diseño; no está probado.** Para comprobarlo:
1. Cierra la cápsula con un papel absorbente dentro.
2. Sumérgela 30 min a 1 m de profundidad.
3. Ábrela y comprueba que el papel sigue seco.
