# AVO GIRTH REV 5: cápsula estanca de 70 × 48 mm, 8 tornillos M3 y 4 + 4 imanes

**REV 5.7.1 (actual): corrección con la prueba impresa de la REV 5.7.**
- La foto del BNO montado mostraba sus pines desplazados ~1,1 mm hacia el USB respecto a los pads D0–D6.
  - **Causa:** la fila de pines está centrada en la placa (~1,2 mm a cada extremo); se había estimado desplazada 1,0 hacia VCC.
  - **Corrección:** BNO_PIN_OFF = 0,0; el BNO y su hueco bajan 1,0 mm hacia la antena. Los pines vuelven a quedar a la misma Y que D0–D6.
- **Taladros reales del BNO:** a 1,95 del borde −X y a 2,45 de los extremos.
  - Se quitan los dos tubos de la tapa, que caían sobre la pestaña −X.
  - El BNO queda sujeto por la pestaña −X, las paredes de los extremos y los puentes soldados al C6.
- **CI:** 1 sólido por pieza, interferencias: ninguna.

**REV 5.7: cama de la electrónica.**
- **Cama maciza:** la bandeja se rellena hasta la cara superior de los PCB (z 9,2) y queda dentro del labio de la tapa. El C6 y la Qi van en alojamientos a ras de la cama.
- **BNO085 hundido:**
  - su cara superior queda al mismo nivel que la del C6, y los 7 puentes se sueldan planos por arriba;
  - apoya en un reborde de 1 mm, con ventana debajo para las soldaduras;
  - ya no lleva tornillos M2.
- **Sujeción:**
  - **C6:** pestaña superior continua en el lado +X (0,6 sobre el PCB). Su columna derecha de pads queda debajo, sin usar.
  - **BNO:** pestaña en el lado −X (pared de 0,8 + 0,45 sobre el PCB), paredes en los extremos y dos tubos de la tapa (Ø4,2/2,6) que lo aprietan sobre el anillo de sus taladros.
  - **Orden de montaje:**
    1. el C6;
    2. el BNO;
    3. los puentes.
- **Canales de cables** (2,4 × 1,2 mm, con 0,8 de suelo sobre la batería):
  - superior: batería → Qi;
  - entre la Qi y el BNO: 2,2 mm, con topes de la Qi de 0,6;
  - inferior: batería, reed y VCC/GND del BNO.
  - Todo baja bajo el C6 por la ventana, hasta los pads de abajo: BAT+/−, MTCK, MTDI, 3V3 y GND.
- **Batería:** girada 180° en su cuna. Sus cables salen por −X/+Y y suben por el paso nuevo, en (−26; 13,2). Se quita el paso antiguo de (26; −13,9).
- **Hilos de la bobina:** la ranura queda abierta hasta el borde de la bandeja, para meterlos de lado sin desoldar la bobina.
- **Otros cambios:**
  - la Qi se desplaza 1 mm hacia −X;
  - el poste de la tapa de (−3; −16,5) pasa a (−3; −18,9);
  - los postes de la tapa apoyan en la cama.
- **Voladizos:** solo las caras inferiores de las dos pestañas (0,45–0,6 mm de vuelo); se imprimen sin soportes.
- **CI:** 1 sólido por pieza, interferencias: ninguna.
- Renders: `renders/cama.png`, `renders/cama_cables.png`, `renders/corte_pines.png` y `renders/cableado_bno_c6.png`.
- **(E) Pendiente de calibre:** el largo del BNO (25,2) y la posición de su fila de pines. Va encajado entre dos pestañas.

**REV 5.6: BNO085 pegado al ESP32-C6, pin con pad.**
- Posiciones tomadas de la huella oficial de Seeed (repositorio OSHW-XIAO-Series):
  - pads de la XIAO ESP32-C6 con paso de 2,54 mm, centrados;
  - D0 en el extremo del USB;
  - el USB-C sobresale 1,5 mm (antes estaba puesto 1,3).
- El BNO085 queda a 0,15 mm del borde −X del C6. Su fila de 10 pines está a la misma Y que la columna D0–D6.
- **Conexiones:** 7 puentes cortos de hilo de cobre estañado de Ø0,5 (el BNO va 0,5 mm más alto, sobre sus separadores). Sirven igual para I²C que para SPI; el modo lo elige el firmware con el nivel de GPIO0 en el reset.

  | BNO085 | XIAO | GPIO | I²C | SPI |
  |---|---|---|---|---|
  | PS0 + PS1 (puenteados en el BNO) | D0 | 0 | LOW | HIGH (PS0 = WAKE) |
  | RST | D1 | 1 | reset | reset |
  | INT | D2 | 2 | interrupción (LP) | interrupción (LP) |
  | CS | D3 | 21 | HIGH | CS |
  | AD0 | D4 | 22 | LOW = 0x4A | MOSI |
  | SDA | D5 | 23 | SDA | MISO |
  | SCL | D6 | 16 | SCL | SCK |
  | GND / VCC | GND / 3V3 | — | cable AWG30 | cable AWG30 |
- **Por qué los 7 y no solo SDA/SCL:**
  - según SparkFun, el BNO08x no funciona de forma fiable sin INT y RST;
  - según Adafruit, su I²C da problemas con ESP32/ESP32-S3, y con los 7 puentes se puede pasar a SPI sin volver a soldar.
- **Cómo soldarlo (REV 5.7):**
  1. Pon un hilo plano por arriba, del pin del BNO al pad del XIAO (las dos caras están al mismo nivel).
  2. Suéldalo en los dos extremos.
  4. Comprueba con el polímetro que no hay continuidad entre puentes vecinos ni entre VCC y GND.
- **Cara inferior del XIAO:**
  - reed a MTCK (GPIO6) y a GND, para que despierte al C6;
  - divisor de la batería: BAT+ → 220 kΩ → MTDI (GPIO5) → 220 kΩ → GND;
  - antena FPC en el U.FL (GPIO3 LOW y GPIO14 HIGH).
- **Arranque del firmware en I²C:**
  1. mantener RST (D1) en LOW;
  2. poner D0 y D4 en LOW y D3 en HIGH;
  3. soltar RST;
  4. arrancar el bus con `Wire.begin(23, 16)`.
- **Arranque del firmware en SPI:**
  1. poner D0 en HIGH antes de soltar RST;
  2. arrancar con `SPI.begin(16, 23, 22, 21)`, en modo 3 y a ≤ 3 MHz.
- Para que la fila de pines quede frente a la columna D0–D6, el poste de presión del C6 en el extremo de la antena se aparta 0,2 mm del BNO.
- Esquema: `renders/cableado_bno_c6.png`. Vista 3D: `renders/bno_c6_pegados.png`.
- **(E) Pendiente de calibre:**
  - BNO_PIN_OFF = 1,0: desplazamiento del centro de la fila de pines hacia VCC;
  - BNO_PIN_IN = 1,3: distancia de los pines al borde;
  - comprobar que, con los componentes hacia arriba y los pines hacia el C6, PS0 queda en el extremo del USB.
- CI: 7 piezas + junta, 1 sólido cada una, **interferencias: ninguna**.

**REV 5.5:**
- **Cápsula de 73 × 51 × 15,5 mm** y soporte de 97,4 × 61,4 mm.
- **Paredes perimetrales macizas**, sin voladizos: 3,6 mm en la base y 4,95 mm en la tapa.
- **Tapa:**
  - lisa, de una sola pieza, con un chaflán de 45° en el borde superior;
  - 8 insertos roscados M3 (taladro Ø4,0 × 5 mm, columna Ø7);
  - inserto de hasta 5 mm de largo, metido con el soldador.
- **Base:**
  - chaflán de 45° en el borde inferior;
  - en cada avellanado de tornillo, una capa de sacrificio de 0,3 mm que se perfora con el propio tornillo;
  - el techo de las ranuras de anclaje sube a 45°;
  - los 4 imanes Ø5 × 1 de las esquinas quedan entre la cuna y la pared maciza.
- **Soporte:** la pestaña elástica baja hasta la cama por una ranura de la placa, y se quita el canal inferior de la cinta.
- **STL y STEP de cada pieza ya orientados para imprimir:** tapa y tirador boca abajo, el resto tal cual. La carpeta `out/montaje/` tiene las piezas en posición de montaje.
- **Comprobación de voladizos** sobre los STL:
  - solo quedan los puentes de las capas de sacrificio (se imprimen como puente);
  - y las caras inferiores del labio y del diente del soporte, de 0,7 a 0,9 mm.
  - **Imprimir con los soportes desactivados.**

**REV 5.3:** bobina Qi redonda Ø25 (nuevo receptor), alojada en un rebaje circular de Ø25,4 en el fondo.

**REV 5.2:** la tapa es una sola pieza con la cara superior lisa: sin panel rojo ni letras. Se imprime boca abajo sin soportes (todas las columnas y postes interiores son verticales). Las piezas rojas quedan en el aro y el tirador.

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
