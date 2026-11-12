# Auditoría del receptor Qi (U1) y del cargador Li-ion (U2) — AVO GIRTH REV B

Fecha: 2026-10-29. Alcance: bloques «Qi (U1)» y «cargador (U2)» de `hardware/girth/PCB/fuente/avo_girth_pcb.py`,
lista de piezas asociada y notas del diseñador (`DOCS/AJUSTE_QI.md`, `DOCS/ANALISIS_ELECTRICO.md`).
**Nada de esta auditoría está medido en una placa.** Todos los números salen de `calc_qi.py`
(salida en `calc_qi_salida.txt`), que toma como entradas los valores de las hojas de datos citadas abajo.

Niveles de comprobación:
- **[CÁLCULO]** VERIFICADO POR CÁLCULO: ecuación del fabricante aplicada a los valores del diseño (`calc_qi.py`).
- **[DOC]** REVISADO DOCUMENTALMENTE: conexión o valor contrastado con el texto del fabricante, sin cálculo.
- **[FÍSICO]** PENDIENTE DE VALIDACIÓN FÍSICA: solo se puede confirmar midiendo con la placa, la bobina y el transmisor.

## 0. Fuentes consultadas

| Id | Documento | URL |
|---|---|---|
| TI-RX | TI BQ51013B, hoja de datos SLUSB62D (rev. D, sep-2020) | https://www.ti.com/lit/ds/symlink/bq51013b.pdf |
| TI-CHG | TI BQ2407x (BQ24072/3/4/5/9), hoja de datos SLUS810N (oct-2021) | https://www.ti.com/lit/ds/symlink/bq24074.pdf |
| TI-EVM | TI bq51013xEVM-764 User's Guide, SLUUA44A | https://ti.com/lit/pdf/sluua44 |
| TI-E2E1 | TI E2E, «[FAQ] Schematic Checklist for Wireless Power RX» | https://e2e.ti.com/support/power-management-group/power-management/f/power-management-forum/925464/faq-schematic-checklist-for-wireless-power-rx |
| TI-E2E2 | TI E2E, «BQ51013B Ros1 and Ros2 values and purpose» | https://e2e.ti.com/support/power-management-group/power-management/f/power-management-forum/302422/bq51013b-ros1-and-ros2-values-and-purpose |
| MUR | Murata NCP15XH103F03RC, hoja de producto | https://static.chipdip.ru/lib/012/DOC013012218.pdf |
| TDK1 | TDK WR202010-18M8-ID, ficha de producto | https://product.tdk.com/en/search/wireless-charge/wireless-charge/rx-coil-module/info?part_no=WR202010-18M8-ID |
| TDK2 | TDK, catálogo de bobinas Rx | https://product.tdk.com/en/search/wireless-charge/wireless-charge/rx-coil-module/catalog |
| TDK3 | element14, WR202010-18M8-ID | https://my.element14.com/tdk/wr202010-18m8-id/charging-coil-11uh-5-20mm-dia/dp/2790526 |
| TDK4 | Mouser, WR202010-18M8-ID | https://www.mouser.com/en/ProductDetail/TDK/WR202010-18M8-ID?qs=XQXp6f9AQWCW9eeGp2b5GQ%3D%3D |
| TDK5 | JLCPCB, WR202010-18M8-ID (C3606542) | https://jlcpcb.com/partdetail/TDK-WR202010_18M8ID/C3606542 |

Limitaciones de acceso: el proxy de esta sesión bloquea la descarga directa de PDF (ti.com, mouser, lcsc, we-online,
alldatasheet). Las hojas se leyeron con una herramienta de lectura web que **extrae y resume** el PDF; las
ecuaciones con texto dañado se reconstruyeron y se comprobaron reproduciendo los ejemplos numéricos de TI
(C1 = 158,3 nF y C2 = 2,3 nF del §9.2.1.2.2; 58,7 % y 19,6 % de la red TS del §8.3.13). Antes de cerrar el diseño
conviene cotejar con el PDF original las tablas de umbrales (§7.5 de TI-RX y §8.5 de TI-CHG). La hoja de datos
de la celda LP403048 y el PDF completo de la bobina TDK (con dimensiones de la ferrita y Ls′) **no se pudieron
descargar**.

Nota: el comentario de `avo_girth_pcb.py` cita «TI SLUSAF8 §9.2.2». El PDF actual del BQ51013B es **SLUSB62D**
(versión japonesa JAJSF16D, china ZHCSAH3D). Hay que corregir la referencia.

## 1. BQ51013B (U1)

### 1.1 Patillaje — [DOC]
Patillaje RHL según TI-RX §6: 1 PGND, 2 AC1, 3 BOOT1, 4 OUT, 5 CLAMP1, 6 COMM1, 7 CHG, 8 AD-EN, 9 AD, 10 EN1,
11 EN2, 12 ILIM, 13 TS/CTRL, 14 FOD, 15 COMM2, 16 CLAMP2, 17 BOOT2, 18 RECT, 19 AC2, 20 PGND y pad térmico a PGND.
**Coincide con la tabla de redes del diseño.**

### 1.2 Resonancia serie y paralelo — [CÁLCULO] + [FÍSICO]
Ecuaciones de TI-RX §9.2.1.2.2 (Ec. 6):
- C1 = 1 / ((2π·fS)²·Ls′), con fS = 100 kHz (+5 / −10 %, es decir, de 90 a 105 kHz)
- C2 = 1 / ((2π·fD)²·Ls − 1/C1), con fD = 1 MHz ± 10 %
- Ls′ es la inductancia medida a 1 V rms y 100 kHz en el útil de prueba WPC (escudo primario de ferrita PC44,
  separación de 3,4 mm). Ls es la inductancia en aire.
- Q = 2π·fD·Ls / R > 77 (Ec. 7). Condensadores de 25 V como mínimo.

| Comprobación | Resultado (`calc_qi_salida.txt` §1) |
|---|---|
| Ejemplo de TI reproducido | C1 = 158,3 nF y C2 = 2,34 nF (TI da 158,3 y 2,3): las ecuaciones son correctas |
| Supuesto del diseñador (Ls′ = 10 µH) | C1 requerido = 253,3 nF; con 247 nF, fS = 101,3 kHz (aritmética correcta) |
| Margen de C1 = 247 nF | fS cae en 90–105 kHz **solo si Ls′ está entre 9,30 y 12,66 µH** |
| C2 = 2,2 nF con C1 = 247 nF | fD = 1,205 / 1,078 / 0,984 MHz para Ls = 8 / 10 / 12 µH (con Ls = 8 µH queda fuera de ±10 %) |
| **Fórmula de C2 en `DOCS/AJUSTE_QI.md`** | Dice C2 = 1/((2π·1 MHz)²·(Ls − 1/((2π·100 kHz)²·C1))). Como 1/((2π·fS)²·C1) = Ls′, eso es 1/(ωD²·(Ls − Ls′)): **división por cero si Ls′ = Ls y valor negativo si Ls′ > Ls**, que es lo normal. Es incorrecta. La correcta es la de TI (arriba). |
| Tensión en C1 con 0,6 A rms (estimación del diseñador) | 3,9 V rms con 247 nF; 5,3 V rms con 180 nF. Los C0G de 50 V tienen margen de sobra |
| Conexión | C1 (tres en paralelo) de la bobina a AC1 y C2 entre AC1 y AC2: coincide con TI-RX Fig. 9-1 y TI-E2E1 punto 1 [DOC] |

Conclusión: los valores de C1–C5 dependen de una inductancia **que no se ha medido** y de una bobina sin
identificar. El procedimiento de `AJUSTE_QI.md` (medir sobre el transmisor OTOTEC apagado) es una aproximación
razonable, pero no es la definición de Ls′ de TI (útil WPC). Esta parte es **[FÍSICO]**.

### 1.3 R_ILIM, límite de corriente y FOD — [CÁLCULO] / [DOC]
TI-RX §8.3.4: RILIM = R1 + RFOD; IMAX = 262/RILIM; ILIM (límite físico) = KILIM/RILIM con KILIM = 303 / 314 / 321 A·Ω;
RILIM < 120 Ω se interpreta como cortocircuito y deja la salida enclavada.

| Magnitud | Valor |
|---|---|
| RILIM = 330 + 200 | 530 Ω (> 120 Ω) |
| IMAX | **494 mA** (coincide con el diseñador) |
| ILIM | 592 mA típicos; **566–612 mA** con la tolerancia de KILIM y resistencias del 1 % (supuesto). El «≈ 590 mA» del diseñador es correcto |
| VRECT objetivo (Tabla 8-1) | 7,08 / 6,28 / 5,53 / 5,11 V para 0–49 / 49–99 / 99–198 / > 198 mA |
| Pérdida del regulador lineal (VRECT − VOUT)·IOUT | ≤ 0,13 W, es decir, ΔTJ ≈ 5 °C con RθJA = 37,7 °C/W. TI no publica el RDS(on) del rectificador síncrono, así que la pérdida total de U1 **no se puede calcular** |

- R2 = RFOD = 200 Ω frente a los 196 Ω por defecto de TI. R3 = ROS = 20 kΩ **de RECT a FOD**: la conexión la
  confirma TI-E2E1 punto 8 y TI-E2E2 («ROS connected to RECT is recommended»). [DOC]
- TI-RX §9.2.1.2.6 y TI-E2E1 punto 9 recomiendan dejar **dos huellas para ROS y dos para RFOD** para el ajuste fino
  tras la calibración. El diseño tiene una de cada (hallazgo menor).
- Calibración FOD: según TI-E2E2 «There is no formula for the ROS and RFOD»; los valores salen de la calibración
  WPC con la herramienta de TI. **[FÍSICO]**

### 1.4 BOOT, CLAMP, COMM — [DOC]
| Pieza | Diseño | TI-RX §9.2.1.2.4 / TI-E2E1 | Estado |
|---|---|---|---|
| BOOT1/2 (C6, C9) | 10 nF 50 V a AC1/AC2 | 10 nF, ≥ 25 V | Correcto |
| CLAMP1/2 (C7, C10) | 470 nF 25 V a AC1/AC2 | 0,47 µF, ≥ 25 V | Correcto (25 V justo en el mínimo) |
| COMM1/2 (C8, C11) | 22 nF 50 V a AC1/AC2 (modulación capacitiva) | 22 nF (47 nF si falla la comunicación); TI-E2E1 sugiere ≈ 20 % de C1 | Correcto según la hoja. Representa el 8,9 % de C1 = 247 nF (el 20 % serían 49 nF) [CÁLCULO]. Dejar previsto el cambio a 47 nF (misma huella) |

Modulación resistiva (COMM a RECT por una resistencia; ≥ 12 Ω y ≤ 24 Ω por pin): no se usa. Para este tamaño, la
capacitiva es la que recomienda TI.

### 1.5 RECT y OUT — [DOC] / [FÍSICO]
- RECT: 2 × 10 µF 25 V 0603 + 100 nF. TI recomienda de 4,7 a 22 µF cerámicos de 16 V como mínimo; su ejemplo de 1 A
  usa 2 × 10 µF + 0,1 µF. **Correcto.** La pérdida de capacidad por la tensión continua (0603 a 5–7 V, hasta 15 V
  en la sobretensión) no se ha cuantificado porque falta la curva del fabricante. [FÍSICO]
- OUT (VIN5): C15 10 µF + C16 100 nF, como en el ejemplo de TI. Correcto. Ver el hallazgo H-10 sobre la suma con C18.

### 1.6 TS/CTRL con NTC NCP15XH103F03RC directa a GND — [CÁLCULO]
TI-RX §8.3.13 y §7.5: pull-up interno RTS de 20 kΩ (18–22 kΩ) a VTSB (2,2 V, polarización solo periódica);
VCOLD = 58,7 % (56,5–60,8 %) de VTSB → EPT 0x00; VHOT = 19,6 % (18,5–20,7 %) → EPT 0x03 (sobretemperatura).
Una NTC de 10 kΩ directa a GND **es válida** (descripción del pin; TI-E2E1 punto 7). Sin NTC se pone 10 kΩ fijo
(ratio 33,3 %, dentro de los umbrales en el peor caso).

La topología (RTS – TS – [(R1 + NTC) ∥ R3] – GND) se confirmó reproduciendo el ejemplo de TI (58,7 % a −10 °C y
19,6 % a 100 °C con β = 3380). NTC de Murata: R25 = 10 kΩ ± 1 %, B25/50 = 3380 K ± 1 % [MUR].

| Configuración | Frío (corta) | Caliente (corta) | Peor caso (todas las tolerancias sumadas) |
|---|---|---|---|
| **Diseño: NTC sola** | **−0,2 °C** | **45,2 °C** | frío −4,6…4,6 °C; caliente **39,9…51,2 °C** |
| Red del ejemplo de TI, valores E96 (R1 4,22 k en serie + R3 66,5 k en paralelo) | −10,1 °C | 99,3 °C | frío −18…−2 °C; caliente ≥ 72 °C |
| Red alternativa calculada (R1 2,43 k + R3 44,9 k) | −20,0 °C | 60,0 °C | frío −32…−10 °C; caliente 49,5…74,1 °C |

RT1 está a **3,8 mm de U1** (coordenadas POS). Con la NTC sola, el receptor envía «sobretemperatura» al transmisor
cuando la placa junto a U1 pasa de unos 45 °C (40 °C en el peor caso), algo que dentro de una cápsula cerrada al
sol o cargando puede ocurrir. El resultado serían cortes de carga intermitentes. Ver el hallazgo H-4. [FÍSICO]

### 1.7 AD / AD-EN y EN1 / EN2 — [DOC]
- EN1 = EN2 = 0 (pines 10 y 11 a GND; pull-down interno de 200 kΩ): según TI-RX Tablas 8-2 y 8-3, la entrada por cable
  tiene prioridad, el control del adaptador está activo y el **límite adaptativo de corriente de comunicación está
  activado**. No se envía EPT.
- AD = VBUS con 1 µF (C17), como pide TI. Umbral VAD-Pres = 3,6 V (3,5–3,8 V). Con adaptador, AD-EN baja a unos
  4,5 V por debajo de AD (VAD-Diff de 3 a 5 V) y enciende el PMOS. Sin adaptador, AD-EN sigue al mayor de OUT y AD
  y el PMOS queda apagado.
- Q1/Q2 (AO3401A, SOT-23: 1 G, 2 S, 3 D) con las fuentes unidas (AD_SRC) y drenadores a VBUS y VIN5: los diodos
  internos se oponen. Es la configuración de PMOS espalda con espalda de TI (el EVM usa el doble PFET CSD75205W1015,
  TI-EVM). **Correcto.** El valor máximo de Vgs del AO3401A no se ha contrastado (hoja no descargada); la tensión
  de puerta prevista es de −3 a −5 V (VAD-Diff).
- CHG (pin 7): drenador abierto con 100 kΩ a 3,3 V hacia GPIO10. Correcto (máximo absoluto de 20 V).
- **Conflicto**: TI-RX §8.3.11 dice del límite adaptativo de comunicación: «this requires the battery charger device
  to have input voltage regulation (weak adapter mode)». El BQ24072 solo regula la tensión de entrada (VIN-DPM
  4,35/4,5/4,63 V) con EN2 = 0 (modos USB100/USB500), no en el modo por resistencia ILIM que usa el diseño
  (TI-CHG §8.5 y descripción del VIN-DPM). Ver el hallazgo H-3.

## 2. BQ24072 (U2)

### 2.1 Patillaje y pines de configuración — [DOC]
Patillaje RGT16 (TI-CHG, Tabla 7-1): 1 TS, 2–3 BAT, 4 CE, 5 EN2, 6 EN1, 7 PGOOD, 8 VSS, 9 CHG, 10–11 OUT, 12 ILIM,
13 IN, 14 TMR, 15 TD, 16 ISET y pad a VSS. **Coincide con el diseño.**

| Pin | Diseño | Significado según TI-CHG | Estado |
|---|---|---|---|
| CE | GND | Carga habilitada (activo bajo; no dejarlo al aire) | Correcto |
| EN2 / EN1 | 1 (100 k a VSYS) / 0 (GND) | Límite de entrada fijado por RILIM; **sin VIN-DPM** | Funciona, pero ver H-3 |
| TMR | Abierto | Temporizadores internos: precarga 1800 s (30 min), carga rápida 18 000 s (5 h) | Correcto |
| TD | GND | Terminación habilitada (se lee al arrancar) | Correcto |
| ISET | 3,3 kΩ | Rango 590 Ω–8,9 kΩ; usar resistencia del 1 % | Correcto |
| ILIM | 3,3 kΩ | Rango 1,1–8 kΩ; si queda al aire, no carga | Correcto |
| PGOOD / CHG | 100 k a 3,3 V | Drenador abierto, pull-up de 1 a 100 kΩ | Correcto |
| IN / OUT / BAT | 1 µF (+ 10 µF de C15 en la misma red) / 10 µF / 10 µF | IN 1–10 µF; OUT y BAT 4,7–47 µF | Ver H-10 |

### 2.2 Corrientes — [CÁLCULO]
| Magnitud | Ecuación (TI-CHG) | Típica | Rango (K del fabricante, R ± 1 %) |
|---|---|---|---|
| ICHG | 890/RISET | **269,7 mA = 0,54 C** | 239–298 mA (hasta 0,60 C) |
| IPRECHG | 88/RISET | 26,7 mA | 21,0–32,4 mA |
| ITERM | ≈ 10 % de ICHG | 27,0 mA | 21,5–32,8 mA |
| IIN (modo ILIM) | 1525/RILIM (tramo 200–500 mA) | **462 mA** | **399–526 mA** |
| IIN en USB500 (alternativa) | — | 475 mA | 450–500 mA, con VIN-DPM |

- IIN máxima (526 mA) supera la IMAX del Qi (494 mA) pero no su ILIM mínima (566 mA): el Qi sigue en el tramo de
  VRECT = 5,11 V y no corta. Aceptable. [CÁLCULO]
- 0,54 C (0,60 C en el peor caso) para la LP403048 de 500 mAh: **no se ha podido contrastar** con la hoja de la celda.
  [FÍSICO / documento pendiente]

### 2.3 Camino de potencia, precarga y batería muy descargada — [DOC] / [FÍSICO]
- VO(REG) = VBAT + 225 mV si VBAT ≥ 3,2 V; 3,4 V (3,3–3,5 V) si VBAT < 3,2 V. VDPPM = VO(REG) − 100 mV.
  Suplemento desde la batería si VOUT ≤ VBAT − 40 mV.
- VLOWV = 3,0 V. Por debajo de VBAT(SC) = 1,8 V carga a 7,5 mA (de 4 a 11 mA) hasta superar ese umbral; luego
  precarga a 26,7 mA durante 30 min como máximo. Eso son **13,3 mAh (10,5 mAh mínimo)** antes de que salte la falta
  por temporizador (CHG parpadea). Si la celda no llega a 3,0 V en ese tiempo, la carga se detiene hasta que se
  retire y vuelva la entrada. [CÁLCULO + FÍSICO]
- Con la protección de la celda abierta, la precarga pasa por el diodo interno de Q10 (según el diseñador). El
  BQ24072 ve la tensión de la celda más la caída del diodo. No se ha modelado. [FÍSICO]
- Con VBAT < 3,2 V, VSYS = 3,4 V (3,3 V mínimo) alimenta el RT9080 de 3,3 V: el margen de caída es casi nulo. Queda
  fuera de este alcance, pero hay que comprobarlo con la hoja del RT9080. [FÍSICO]

### 2.4 TS con NTC NCP15XH103F03RC (β = 3380) — [CÁLCULO]
TI-CHG: ITS = 75 µA (72–78 µA); VHOT = 0,30 V (0,27–0,33 V); VCOLD = 2,1 V (2,0–2,2 V); referencia de TI con
103AT: de 0 a 50 °C.
- Umbrales en resistencia: 4,00 kΩ (caliente) y 28,0 kΩ (frío).
- Con la NCP15XH103: **carga entre 0,2 °C y 51,2 °C**; peor caso: frío de −2,2 a 2,6 °C, caliente de 46,5 a 56,4 °C.
  Con B25/80 = 3428 (valor de referencia), el umbral caliente queda en 50,8 °C. Frente a la ventana de 0 a 50 °C que
  TI da para la 103AT, la NCP15XH103 da prácticamente la misma: la sustitución es válida. La β de la 103AT no se
  ha descargado, así que no se ha calculado la diferencia exacta.
- **Pero RT2 está en la placa, a 3,9 mm de U2 y a 6,6 mm de U1, no en la celda** (13 mm hasta J2). Mide el
  calentamiento del propio cargador (hasta 0,61 W) y del receptor, no la temperatura de la batería. Ver H-4.

### 2.5 Disipación y regulación térmica — [CÁLCULO] / [FÍSICO]
P = (VIN − VOUT)·(ICHG + ISYS) + (VOUT − VBAT)·ICHG, con VIN = 5,0 V e ISYS = 25–45 mA (estimación del diseñador):

| VBAT | Modo | P (ISYS = 45 mA) | ΔTJ con θJA = 44,5 °C/W |
|---|---|---|---|
| 2,9 V | precarga | 0,13 W | 6 °C |
| **3,0 V** | **rápida** | **0,61 W** | **27 °C** |
| 3,7 V | rápida | 0,40 W | 18 °C |
| 4,2 V | rápida | 0,24 W | 11 °C |

TJ(REG) = 125 °C solo se alcanzaría con unos 98 °C de ambiente en la placa JEDEC. La placa real es pequeña y va
cerrada, y U1 y U2 están a 10 mm, así que la θJA efectiva será mayor. Lo que limitará antes es el umbral caliente de
las NTC de placa (45 °C en el Qi y 51 °C en el cargador), no la regulación térmica del chip. [FÍSICO]

## 3. Bobina comercial propuesta: TDK WR202010-18M8-ID — [CÁLCULO] + [FÍSICO]

| Dato | Valor | Fuente |
|---|---|---|
| Forma | Redonda Ø20,0 mm, grosor ≤ 0,88 mm, 0,58 g: cabe en la huella de Ø25 | TDK1 |
| L | 11 µH ± 5 % a 100 kHz | TDK1, TDK3 |
| Rdc | 0,40 Ω (catálogo TDK, máx. element14) / 0,35 Ω (Mouser, JLCPCB) | TDK2, TDK3, TDK4, TDK5 |
| Clase | «Small Power (1W-3W)»; TDK la marca como «WPC compliant: NO» | TDK1 |
| Corriente | Mouser cita «0,5 a 0,6 A» de salida (texto comercial) | TDK4 |
| Disponibilidad | JLCPCB C3606542 (*Extended*); Mouser sin existencias y 10 semanas de plazo | TDK5, TDK4 |
| **Ls′** | **No publicado** | — |

- Q (Ec. 7 de TI) = 2π·1 MHz·11 µH / 0,40 Ω = **173 > 77**. Cumple.
- Potencia pedida: 5 V × 462 mA = 2,31 W, dentro de la clase de 1 a 3 W.
- Como no hay Ls′, se acota con las relaciones Ls′/Ls de las bobinas de la Tabla 9-1 de TI (de 1,20 a 1,45; la
  NuCurrent de Ø25 mm da 1,29). **Es un supuesto y hay que medirlo.**

| Caso | Ls′ | C1 requerido | fS con el C1 actual (247 nF) | C2 requerido |
|---|---|---|---|---|
| Ls′ = Ls (cota inferior) | 11,0 µH | 230 nF | 96,6 kHz (dentro) | 2,33 nF |
| Ls′/Ls = 1,20 | 13,2 µH | 192 nF | 88,1 kHz (**fuera**) | 2,33 nF |
| Ls′/Ls = 1,29 | 14,2 µH | 178 nF | 84,9 kHz (**fuera**) | 2,33 nF |
| Ls′/Ls = 1,45 | 16,0 µH | 159 nF | 80,2 kHz (**fuera**) | 2,34 nF |

Combinaciones C0G propuestas (comprobadas con Ls ± 5 % y C ± 5 %; todas dentro de 90–105 kHz y 0,9–1,1 MHz):

| Opción | C1 (C1 + C2 + C3, 1206 C0G 50 V) | fS | C2 (C4 + C5) | fD |
|---|---|---|---|---|
| A: Ls′ ≈ Ls | 100 + 100 + 33 nF = 233 nF | 99,4 kHz (94,7–104,6) | 2,2 nF + 330 pF | 0,959 MHz |
| **B: Ls′/Ls ≈ 1,29 (por defecto)** | **100 + 47 + 33 nF = 180 nF** | 99,4 kHz (94,7–104,7) | **2,2 nF + 100 pF** | 1,007 MHz |
| C: Ls′/Ls ≈ 1,45 | 100 + 47 + 15 nF = 162 nF | 99,0 kHz (94,3–104,2) | 2,2 nF + 100 pF | 1,008 MHz |

Valores C0G que hay que buscar en existencias de JLCPCB: 100 nF, 47 nF, 33 nF y 15 nF en 1206 a 50 V; 2,2 nF en 0805;
100 pF y 330 pF en 0603. C2 apenas cambia en los tres casos porque depende de Ls, no de Ls′.

## 4. Qué no se puede simular con fiabilidad

| Aspecto | Motivo |
|---|---|
| Comunicación WPC (ASK por COMM) | El nivel de modulación que ve el transmisor depende del acoplamiento k, del demodulador del transmisor concreto (OTOTEC, sin documentación) y de C_COMM. No hay modelo del transmisor ni del firmware del BQ51013B |
| Calibración FOD (RFOD, ROS) | TI: «There is no formula». Se calibra con el transmisor de referencia WPC y la herramienta de TI, con la cápsula final (batería, metales, imanes) |
| Alineación y acoplamiento | k depende de la distancia, del desplazamiento lateral, de la ferrita del transmisor y del grosor de la cápsula. Una bobina de Ø20 sobre un transmisor de bobina mayor tiene k bajo y muy sensible al centrado. Hace falta modelo de campo 3D más medida |
| Interacción con el transmisor | El lazo de control (paquetes de error, cambio de frecuencia de 110 a 205 kHz) y los tiempos de EPT y reintento son propios del transmisor. VRECT real según la carga y el punto de trabajo del transmisor |
| Eficiencia | Faltan el RDS(on) del rectificador, la ESR real de C1 y de la bobina a la frecuencia de trabajo, las pérdidas por corrientes inducidas en la batería y la eficiencia del transmisor |
| Térmica | θJA es de placa JEDEC; la placa real es pequeña, cerrada, con la celda y la bobina encima y calentamiento por corrientes inducidas. Solo vale la medida con termopar o cámara térmica |
| Batería muy descargada | Depende del circuito de protección de la celda, de la curva de la LP403048 y del diodo de Q10 |

## 5. Hallazgos

No se ha encontrado ningún fallo **crítico** (error de patillaje, conexión que dañe una pieza o valor fuera del
rango absoluto). Los hallazgos son los siguientes:

| Id | Gravedad | Hallazgo | Corrección | Nivel |
|---|---|---|---|---|
| H-1 | **Mayor** (bloquea la puesta en marcha, no la fabricación de la PCB) | C1 = 247 nF solo resuena en 90–105 kHz si Ls′ = 9,30–12,66 µH. La bobina no está identificada ni medida. Con una bobina comercial con ferrita, lo normal es Ls′ > Ls y fS acaba en 80–88 kHz | Fijar una bobina con hoja de datos (propuesta: TDK WR202010-18M8-ID). Medir Ls y Ls′ con un medidor LCR a 100 kHz y 1 V. Montar por defecto la opción B (100 + 47 + 33 nF; 2,2 nF + 100 pF) y ajustar con la medida | CÁLCULO + FÍSICO |
| H-2 | **Mayor** (documentación que lleva a un ajuste erróneo) | La fórmula de C2 de `DOCS/AJUSTE_QI.md` equivale a 1/(ωD²·(Ls − Ls′)): da división por cero o un valor negativo | Sustituirla por C2 = 1/((2π·fD)²·Ls − 1/C1) (TI-RX Ec. 6) | CÁLCULO |
| H-3 | **Mayor** | EN1 = EN2 = 0 en U1 activa el límite adaptativo de comunicación, que según TI exige un cargador con regulación de la tensión de entrada. El BQ24072 en modo ILIM (EN2 = 1) no la tiene. Riesgo de que VIN5 caiga y la comunicación falle en los escalones de carga | Opción recomendada: BQ24072 en USB500 (EN1 = 1 a VSYS, EN2 = 0 a GND): 450–500 mA con VIN-DPM de 4,5 V. Mantener R7 montada (sin ILIM no carga). Opción alternativa: EN2 de U1 a 1, que desactiva el límite pero da prioridad a la carga inalámbrica sobre el USB | DOC + FÍSICO |
| H-4 | **Mayor** | Las dos NTC están en la placa, junto a U1 (3,8 mm) y U2 (3,9 mm), y no en la celda. Ventanas: Qi de −0,2 a 45,2 °C (corte caliente de 39,9 a 51,2 °C en el peor caso); cargador de 0,2 a 51,2 °C. Ninguna protege la celda, y la del Qi puede cortar la carga por el calor propio de la placa | Cargador: llevar la NTC a la celda (conector de 3 hilos o celda con NTC) o, como mínimo, colocar RT2 lejos de U1/U2 y junto a la batería. Qi: añadir la red R1/R3 (4,22 k + 66,5 k E96 → −10/99 °C, o 2,43 k + 44,9 k → −20/60 °C), o usar 10 kΩ fijo. Medir la temperatura de la placa cargando dentro de la cápsula | CÁLCULO + FÍSICO |
| H-5 | Menor | Una sola huella para ROS y otra para RFOD; TI recomienda dos de cada para la calibración FOD | Añadir una huella 0402 sin montar en paralelo con R2 y otra con R3 | DOC |
| H-6 | Menor | C_COMM = 22 nF es el 8,9 % de C1; TI-E2E1 sugiere ≈ 20 % y la hoja de datos admite 47 nF si falla la comunicación | Mantener 22 nF (valor de la hoja) y tener 47 nF previstos para la prueba con el transmisor | CÁLCULO + FÍSICO |
| H-7 | Menor | ICHG = 0,54 C (0,60 C en el peor caso) sin contrastar con la hoja de la LP403048 | Conseguir la hoja de la celda. Si su carga estándar es 0,5 C, subir RISET a 3,6 kΩ (247 mA = 0,49 C nominales) | CÁLCULO + documento pendiente |
| H-8 | Menor | Referencia «SLUSAF8» del comentario del código; el PDF actual es SLUSB62D | Corregir el comentario | DOC |
| H-9 | Info | Precarga de 26,7 mA con temporizador de 30 min: solo 13,3 mAh antes de la falta. Batería muy descargada a través del diodo de Q10 | Probar la recuperación con la celda en protección | FÍSICO |
| H-10 | Info | En VIN5 hay C15 (10 µF) + C18 (1 µF) = 11 µF; el BQ24072 pide de 1 a 10 µF en IN (por la corriente de arranque USB) y el BQ51013B pide 10 µF en OUT | Aceptable (el USB entra por los PMOS). Si se quiere cumplir la letra de ambas hojas, bajar C15 a 4,7 µF y comprobar la estabilidad del Qi | DOC |
| H-11 | Info | VSYS = 3,4 V con VBAT < 3,2 V alimenta el RT9080 de 3,3 V con margen casi nulo | Comprobar la caída del RT9080 con su hoja | FÍSICO |
| H-12 | Info | Disipación del BQ24072 de hasta 0,61 W (ΔTJ de 27 °C en placa JEDEC) al empezar la carga rápida | Medir con cámara térmica junto con H-4 | CÁLCULO + FÍSICO |

Comprobaciones correctas: patillaje de U1 y U2; IMAX = 494 mA e ILIM = 566–612 mA; RFOD y ROS por defecto con ROS
de RECT a FOD; BOOT, CLAMP y COMM; RECT y OUT; conexión de AD, AD-EN y de los PMOS espalda con espalda; CHG; CE, TD,
TMR, ISET e ILIM del BQ24072; IIN (399–526 mA) por debajo de la ILIM del Qi; sustitución de la 103AT por la
NCP15XH103 (ventana de 0,2 a 51,2 °C frente a los 0–50 °C de referencia de TI); tensión de los condensadores de resonancia.

## 6. Resumen de los problemas más graves
1. **Resonancia sin base física (H-1, H-2):** C1 = 247 nF solo vale para Ls′ = 9,3–12,7 µH, y la fórmula de C2 del
   documento de ajuste está mal. Con una bobina comercial como la TDK WR202010-18M8-ID, fS caería a 80–88 kHz salvo
   que Ls′ ≈ Ls. Hay que fijar la bobina, medir Ls y Ls′ y montar por defecto 100 + 47 + 33 nF y 2,2 nF + 100 pF.
2. **Límite adaptativo de comunicación frente al cargador sin VIN-DPM (H-3):** se resuelve pasando el BQ24072 a
   USB500 (EN1 = 1, EN2 = 0) o poniendo EN2 = 1 en el BQ51013B.
3. **NTC en la placa y no en la celda (H-4):** la batería no tiene protección térmica real, y el Qi cortará por
   sobretemperatura a unos 45 °C de placa junto a U1.
4. Todo lo que depende del transmisor (comunicación, FOD, alineación, eficiencia, temperatura) **queda pendiente de
   validación física**.
