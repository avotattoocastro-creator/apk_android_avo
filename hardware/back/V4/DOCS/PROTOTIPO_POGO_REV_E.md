# Prototipo actual (Rev E.5 + Heltec) → contactos pogo · guía de adaptación (Rev E.6)

Objetivo: probar en la espalda que ya tenéis montada (Heltec Wireless Stick Lite V3 + URTK1.2 + Pololu S7V8F3 +
batería 654060) el sistema de alimentación de la V4 REV B **antes** de fabricar la placa propia:

- **Sin Qi y sin reed.** La cápsula lleva 3 contactos en el fondo: **BAT** (+ de la celda), **SYS** (entrada de la
  electrónica) y **GND**.
- **Soporte del chaleco:** dos pines con muelle unidos por un hilo puentean SYS y BAT → la espalda se enciende al ponerla
  y se queda a 0 V al quitarla.
- **Base de carga:** dos pines con muelle en BAT y GND conectados a un cargador Li-ion → carga con la electrónica apagada.

**Estado: diseñado y comprobado por software (CAD) · NO PROBADO.**

## 1. Qué se reimprime y qué se conserva
| Pieza | Acción | Fichero |
|---|---|---|
| Base | **reimprimir** (Rev E.6) | `PROTOTIPO_POGO_REV_E6/STL/AVO_RevE6_BASE_POGO.stl` |
| Cuna de la Heltec | **reimprimir** (Rev E.6, ver §1 b) | `PROTOTIPO_POGO_REV_E6/STL/AVO_RevE6_CUNA_HELTEC.stl` |
| Soporte del chaleco | **reimprimir** (Rev E.6) | `PROTOTIPO_POGO_REV_E6/STL/AVO_RevE6_SOPORTE_POGO.stl` |
| Base de carga | **nueva** (el mismo soporte con los pines en BAT y GND y sin puente; se usa sobre la mesa) | `PROTOTIPO_POGO_REV_E6/STL/AVO_RevE6_BASE_CARGA_POGO.stl` |
| Tapa E.5, junta TPU, contraplaca | **se conservan** (la Heltec queda a la misma altura: la tapa E.5 sirve tal cual) | — |
| Tope del reed | ya no hace falta | — |

Se imprimen igual que la Rev E (PETG, base, cuna y soportes con la cara inferior sobre la cama, **sin soportes**: 0 voladizos
fuera de límite en `VALIDACION/voladizos.json`). Los STL ya están en posición de impresión; los STEP, en posición de montaje.

### 1 b. Cuna de la Heltec E.6 (cambios pedidos el 30/10/2026)
- **Un solo pasacables centrado** (X 5,0–6,9 · Y −2,0–2,0) en lugar de las 2 ranuras del reed: por él suben los cables de los
  contactos del fondo.
- **Ventana bajo la Heltec ampliada** hacia el conector de batería SH1.25 (el «cuadrado» de la foto).
- **Pololu S7V8F3** (Pololu 2122: 16,51 × 11,43 mm; **espesor 1,0 mm**, medido por el usuario. Pololu da 0,1″ =
  2,54 mm sin aclarar qué incluye) en el sitio de la placa Qi, **a 1,0 mm del borde −Y**:
  - alojamiento de 11,83 × 16,91 mm (0,2 mm de holgura) rebajado **1,0 mm** en el refuerzo: su cara superior queda
    enrasada con el refuerzo (Z 11,2) y ya no hay marco por encima;
  - lado de los pines (SHDN, VIN, GND, VOUT) hacia la antena, con una salida de 9 mm para los hilos y un alivio de
    0,5 mm bajo las soldaduras.
- **Sujetacables para 5 cables AWG30:**
  - **Borde −Y, junto a la Heltec:** 3 labios a 45° sobre el canal entre el refuerzo y la Heltec (X 21, 38 y 53). El de
    X 21 se movió desde X 24 para no tocar las láminas del botón USER de la tapa.
  - **Cuello:** 2 pinzas de dos postes con labio a 45°: una en el lado −Y (Y −7,5) y otra en el +Y (Y 14,5, junto al
    contacto GND). Los cables van a lo largo de Y. La pinza de Y −13,5 se ha quitado. No hay pinzas entre Y 0,9 y 13,3
    porque ahí entra la clavija del USB-C.
  - **Pinzas sobre el refuerzo (como la del cuello en Y −7,5)**, 4 nuevas en las posiciones marcadas 1–4. Dos postes
    de 0,8 mm con labio a 45°, canal de 2,3 mm, sobre la cara superior del refuerzo (Z 11,2):
    1. extremo de la antena, lado +Y (X 69,8–72,1; Y 11), cables a lo largo de Y;
    2. extremo de la antena, centro (X 69,8–72,1; Y −2), cables a lo largo de Y;
    3. entre el Pololu y la Heltec (Y −9,5 a −7,2; X 38), cables a lo largo de X;
    4. borde −Y junto al cuello (Y −18,8 a −16,5; X 14,5), cables a lo largo de X. Los hilos pasan por debajo de la
       varilla del botón USER de la tapa (queda 0,55 mm sobre el refuerzo en X < 12,75).
  - El canal del borde −Y y sus labios **se han quitado** (pedido del usuario).
  - **Borde +Y:** junto a las torres de la Heltec en X 30 y 46 hay una **torre exterior separada** (X 28,8–31,3 y
    45,2–47,3; Y 20,35–21,0). Entre cada pareja queda un pasacables de 0,8 mm de ancho y 4,6 mm de alto, con los 5 hilos uno encima de
    otro. Las torres exteriores están fuera de los clics de la base, que sujetan la bandeja en X 16–24 y 36–45.
- **Espesor de la Heltec**: las pestañas quedan 0,05 mm por encima de una placa de **1,8 mm**. Ese espesor sale del modelo
  3MF y **nunca se ha medido con calibre** (estaba en las pendientes de la Rev E). Si la placa real es más fina, la Heltec
  bailará: hay que medirla y cambiar `MCU["t"]`.
- **Heltec calzada 1,0 mm**: calzos en el extremo USB (a los dos lados del conector), en el extremo de la antena y bajo los
  apoyos de la tapa (X 28–30 y 46–48). **Pestañas 1,0 mm más altas.**
  - Para que la Heltec no suba respecto a la tapa (el USB-C quedaría a 0,5 mm del techo), **la batería baja 1,0 mm**: ya no
    hay bobina Qi debajo y apoya en el suelo de la base (1,4 mm).
  - La bandeja baja con ella y su refuerzo pasa de 1,2 a 2,2 mm, así que los pisadores de la tapa E.5 siguen apoyando igual.
  - Resultado: **la Heltec queda exactamente a la misma altura que en la E.5** (boca USB-C, apoyos y botón USER de la tapa
    E.5 sin cambios). Comprobado: 0 interferencias con la tapa E.5.
- **Más pestañas en los dos bordes**:
  - 3 de las guías laterales pasan a tener labio (0,5 mm sobre la placa). La guía del borde +Y en el lado USB y su torre
    exterior se han quitado: ahí están los pines 3V3 y GND de la Heltec donde se suelda el GPS;
  - 2 pestañas nuevas en el borde +Y (X 30 y 46).
- **Torres con pestaña también en el extremo USB**, iguales a las del extremo de la antena, entre el USB-C y los pulsadores
  laterales (Y −0,9 a 2,3 y 11,9 a 15,1). Su viga es de 1,1 mm para dejar entrar la clavija del cable USB-C.
- La bandeja empieza en X 3,5 (antes 3,0): al bajar 1 mm tocaba la pared interior del cuello de la tapa.

**Por qué hay que reimprimir la base:** el alojamiento del reed deja solo 1 mm de suelo y un tornillo avellanado necesita
≈ 2,5 mm (cabeza + junta). En la E.6 el fondo de ese alojamiento sube a 2,5 mm y cada contacto tiene:
- un avellanado de 90° y Ø4,1 desde fuera;
- un paso de Ø2,3;
- una ranura para la junta tórica en la cara interior;
- un alojamiento de Ø6,8 para el terminal y la tuerca.

**Por qué hay que reimprimir el soporte:** los 3 imanes del reed desaparecen y bajo SYS y BAT hay dos agujeros pasantes
de Ø2,05 para los pines. Por debajo, un canal de 1,6 × 1,4 lleva el hilo del puente.

Posiciones (coordenadas de la Rev E: X desde la cara del cuello, Y lateral):

| Contacto | Posición | Notas |
|---|---|---|
| BAT | (8,8; −4,0) | sitio del reed |
| SYS | (8,8; +4,0) | sitio del reed |
| GND | (8,8; +14,0) | lejos de BAT (18 mm) |

Se movieron de X 7 a X 8,8 porque en X 7 los alojamientos dejaban en el aire el faldón del cuello.

## 2. Material
| Cant. | Pieza | Nota |
|---|---|---|
| 3 | Tornillo M2 × 5 avellanado (ISO 10642 / DIN 965), **inox A2** | la cabeza queda enrasada con el fondo y es el contacto |
| 3 | Tuerca M2 (DIN 934) + arandela M2 | |
| 3 | Junta tórica 2 × 1 NBR | en la ranura interior, la aprieta el terminal |
| 3 | Terminal de ojal M2 (o arandela con el hilo soldado) | |
| 4 | Pin pogo Ø2,0 mm, largo ≥ 5,5 mm, carrera ≥ 1 mm, ≥ 1 A | 2 para el soporte del chaleco y 2 para la base de carga |
| 1 | Fusible rearmable 1,5 A (p. ej. 1206 SMD1206P150TF soldado en línea, o radial de 1,5 A) | entre la celda y BAT |
| 1 | Módulo cargador TP4056 **con protección** (USB-C, 1 A de serie; mejor 0,5 A cambiando R_PROG a 2,4 kΩ) | para la base de carga |
| — | Hilo 22–24 AWG, termorretráctil, epoxi | |
| 2 (opcional) | TVS 5 V (PESD5V0S1BA o SMF5.0A) | SYS–GND y BAT–GND junto a los contactos |

## 3. Desmontar
1. Abrir la cápsula y **desenchufar la batería**.
2. **Quitar la placa Qi y la bobina** (la base E.6 ya no tiene su alojamiento: la batería apoya en el suelo).
3. **Quitar el reed** y su hilo a GPIO7. GPIO7 queda sin conectar.
4. Pasar la Heltec, la URTK1.2, la bandeja y la batería a la base E.6.

## 4. Cableado nuevo
```
 celda + (cable rojo, tras su PCM) ──[ fusible 1,5 A ]──► contacto BAT
 contacto SYS ──┬──► + del conector de batería de la Heltec (JST 1,25 «BAT»)
                └──► VIN del Pololu S7V8F3
 celda − ──┬──► − del conector de batería de la Heltec
           ├──► GND del S7V8F3
           └──► contacto GND
 Sin cambios: VOUT del S7V8F3 → 3V3 de la URTK1.2 · SHDN del S7V8F3 → GPIO6 · UART del ZED como en la 3.11.0
 Opcional: TVS 5 V entre SYS y GND y entre BAT y GND, soldados en los terminales
```
- **Polaridad**: el contacto BAT lleva siempre la tensión de la celda (fusible incluido). Comprobar con el polímetro
  antes de cerrar.
- **Montaje de cada contacto:**
  1. Meter el tornillo desde fuera.
  2. Por dentro, poner la junta tórica en su ranura.
  3. Poner el terminal de ojal y la arandela.
  4. Apretar la tuerca con suavidad: aplasta la junta, no hay que forzar el PETG.
- Con USB en la Heltec y la cápsula en el chaleco, la Heltec carga la celda a través del puente. Fuera del chaleco, con
  USB, funciona desde el USB y el contacto SYS queda a la tensión de su cargador (≈ 4,2 V), lo que no causa ningún daño.

## 5. Soporte del chaleco y base de carga
- **Soporte del chaleco (E.6):**
  1. Soldar un hilo corto entre las colas de los dos pines.
  2. Meter los pines desde abajo por los agujeros SYS/BAT, de forma que la punta sobresalga **0,8 mm** por encima de la
     cara de apoyo.
  3. Pegar con epoxi.
  4. Dejar el hilo en el canal inferior.
- **Base de carga (E.6 carga):**
  1. Montar los pines en BAT y GND igual que en el soporte, pero sin puente.
  2. Unir BAT a **B+** del TP4056 y GND a **B−**.
  3. Alimentar el TP4056 con 5 V por USB.
  4. Comprobar la polaridad con el polímetro **antes** de poner la cápsula.
- La cápsula se sujeta en los dos con los mismos imanes de la Rev E.

## 6. Firmware: BACK 3.12.0
CI de esta rama: run **41044381974** (`2750d3c`, éxito), artefacto **AVO-BACK-V3-12-0-HELTEC**. Instalar con AVO Update
o esptool **con la tapa abierta**. Cambios respecto a la 3.11.0:
- **Sin reed** (`AVO_REED_SLEEP 0`): tener corriente significa estar en el chaleco; quitar la cápsula = 0 V.
- **Emparejar sin abrir:** poner y quitar la cápsula del soporte **3 veces seguidas, menos de 4 s cada vez** → se abre
  el emparejamiento durante 120 s. El botón PRG 3 s sigue funcionando.
- Monitor: `INTERRUPTOR: reed no usado (V3.12: contactos pogo …)`.

## 7. Pruebas (en este orden)
| # | Prueba | Cómo | Correcto si |
|---|---|---|---|
| 1 | Continuidad | polímetro con la tapa abierta | BAT ↔ + de la celda (a través del fusible) · SYS ↔ + de la Heltec y VIN del S7V8F3 · GND ↔ − de la celda · SYS y BAT **sin** continuidad entre ellos |
| 2 | Apagada fuera del soporte | tensión en SYS y corriente de la celda | 0 V en SYS; corriente ≈ la del PCM de la celda (µA) |
| 3 | Encendido en el chaleco | poner la cápsula en el soporte E.6 con el monitor USB | arranca, `INTERRUPTOR: reed no usado`, ZED a 1 s, enlace con el pecho |
| 4 | Apagado | quitar la cápsula | la Heltec se apaga al instante (LED apagado, 0 V en SYS) |
| 5 | Emparejar | 3 apoyos rápidos | `3 encendidos rapidos: emparejamiento abierto 120 s` |
| 6 | Carga | cápsula en la base de carga | LED de carga del TP4056; la Heltec apagada; la tensión de la celda sube |
| 7 | Estanqueidad | 1 m, 30 min, papel secante dentro | seco junto a los 3 contactos |
| 8 | Vibración / campo | al galope, con el pecho mostrando el estado de la espalda | **sin reinicios**: un corte del contacto de unos milisegundos reinicia la Heltec |

## 8. Riesgos a vigilar
- **Rebote del contacto al galope:** es el riesgo principal del encendido por puente. Si aparecen reinicios, hay dos
  soluciones: pines con más presión (más carrera, 1,5–2 mm), o un condensador de 470–1000 µF en SYS–GND dentro de la
  cápsula para sostener cortes breves.
- **Sudor y suciedad:** BAT y GND no están juntos (18 mm) y un puente SYS–BAT por sudor solo enciende la espalda.
  Después de cada uso conviene limpiar los contactos con agua dulce y secarlos.
- **Corrosión:** inox A2 contra pines dorados. Si aumenta la resistencia de contacto, hay que cambiar los tornillos por
  latón dorado.
- **Celda sin PCM o PCM débil:** el fusible protege el contacto BAT, pero la celda debe llevar PCM. La 654060 lo trae.
