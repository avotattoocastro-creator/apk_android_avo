# AVO espalda · Rev E.7 · conectores magnéticos de 3 vías en lugar del reed (31/10/2026)

**Estado: diseñado y comprobado por software (CAD) · NO PROBADO.** Antes de imprimir la base y el soporte enteros, imprime las
**probetas** y comprueba el encaje.

La E.7 es la E.6 (contactos pogo) con los dos conectores magnéticos comerciales que has comprado, en lugar de los tornillos M2 y
los pines sueltos:

- **Cápsula (base):** va el conector **plano** (ovalado, 3 contactos).
- **Soporte del chaleco:** va el conector de **muelles** (orejas, 2 imanes y 3 pines). El soporte une **BAT** y **SYS**: la espalda
  se enciende al ponerla y queda a 0 V al quitarla (esquema de la E.6).
- **Base de carga** (opcional, necesita un segundo conector de muelles): BAT y GND al cargador, sin puente.

## 1. Qué se imprime
| Pieza | Fichero (STL en posición de impresión, cara inferior en la cama, **sin soportes**) |
|---|---|
| Probeta de la base (solo el suelo del cuello, X 2–17) | `STL/AVO_RevE7_PROBETA_CONECTOR_BASE.stl` |
| Probeta del soporte | `STL/AVO_RevE7_PROBETA_CONECTOR_SOPORTE.stl` |
| Probeta de la base de carga (con canal del cable) | `STL/AVO_RevE7_PROBETA_CONECTOR_BASE_CARGA.stl` |
| Base E.7 | `STL/AVO_RevE7_BASE_IMAN.stl` |
| Soporte del chaleco E.7 | `STL/AVO_RevE7_SOPORTE_IMAN.stl` |
| Base de carga E.7 | `STL/AVO_RevE7_BASE_CARGA_IMAN.stl` |

- **Sin cambios:** tapa E.5, cuna de la Heltec E.6, junta TPU y contraplaca. Tampoco se usa el tope del reed.
- **Voladizos:** 0 fuera de límite en las 6 piezas (`VALIDACION/voladizos_E7.json`).
- **Mallas:** cerradas, de un solo cuerpo, sin autointersecciones (`VALIDACION/validacion_E7.json`).

## 2. Dónde van y con qué medidas
Los dos conectores van centrados en **X 9, Y 0** (donde estaba el reed), con el eje largo a lo largo de Y.

**Conector plano, en la base:**
- Alojamiento ovalado de **15,3 × 6,5** (conector 15,0 × 6,2 + 0,15 por lado), desde el fondo hasta **Z 4,0**.
- Encima, un escalón a 45° que se estrecha 0,8 mm y sube al interior, por donde pasan las patas y los cables.
- La cara de contactos queda **enrasada con el fondo**.

**Conector de muelles, en el soporte:**
- **Ventana del cuerpo:** 14,9 × 5,8, que atraviesa la cara de apoyo.
- **Alojamiento de las orejas:** óvalo de 25,0 × 5,8, abierto por abajo hasta Z −1,4.
- **Membrana de 0,2 mm** entre los dos: se imprime para que el techo de las orejas sea un puente. **Córtala con un cúter** por la
  ventana antes de montar.
- La cara del cuerpo queda **0,2 mm por debajo** de la cara de apoyo. Así no sobresale aunque el cuerpo sea un poco más grueso, y
  con la cápsula puesta los muelles siguen apretados unos 1,3 mm de los 1,5.

**Medidas que has dado tú:**
- las puntas salen 1,5 mm;
- agujeros de Ø2,5 a 19,5 mm entre centros;
- imanes a ras.

**Medidas sacadas de las fotos (±0,3 mm), a comprobar con las probetas:**

| Medida | Valor usado | Si no coincide |
|---|---|---|
| Largo del conector plano | 15,0 (otra foto dio 16,5) | Si no entra en la probeta, dímelo y cambio `OVAL` |
| Ancho del conector plano | 6,2 | `OVAL` |
| Grueso del conector plano | ≤ 4,0 (escalón a Z 4,0) | Si es más grueso no queda a ras: `OVAL_LEDGE_Z` |
| Cuerpo del conector de muelles | 14,6 × 5,5 × 2,9 (sin pines) | `EAR_BODY` |
| Largo total con orejas | 24,7 | `EAR_LEN` |
| Grueso de las orejas | 1,7, a ras de la cara trasera | `EAR_T` |

![secciones](IMAGENES/E7_secciones_conectores.png)

## 3. Orden de los contactos
A lo largo de Y, en los dos conectores:

| Posición | Contacto | Lado de la cápsula |
|---|---|---|
| Y − | **BAT** (+ de la celda, tras el fusible) | lado del botón USER |
| Centro | **SYS** (entrada de la electrónica) | |
| Y + | **GND** | lado opuesto al botón |

SYS va en medio para que, si el sudor o el agua unen dos contactos vecinos, como mucho se encienda la espalda. BAT y GND, que
harían cortocircuito, quedan en los extremos.

## 4. Montaje
1. **Polaridad de los imanes.** Antes de pegar nada:
   - pon el conector de muelles en el soporte, sin pegar, con la membrana ya cortada;
   - acopla el conector plano encima y marca con rotulador qué extremo queda hacia el lado del botón USER (Y −).
   
   Si lo pegas girado, los imanes se repelen y el orden BAT/GND se invierte.
2. **Cables del conector plano.** Suelda 3 hilos de 24–26 AWG a sus patas **antes** de pegarlo: BAT, SYS y GND.
3. **Pegar el conector plano en la base:**
   - pon cinta de carrocero sobre un cristal o una superficie plana;
   - apoya la base con el fondo sobre la cinta y mete el conector desde fuera, con los contactos sobre la cinta;
   - echa epoxi por dentro alrededor del conector. El escalón lo sujeta y el epoxi sella el agujero;
   - espera a que cure y quita la cinta: la cara queda a ras.
4. **Pegar el conector de muelles en el soporte:**
   - **soporte del chaleco:** suelda un hilo corto entre las patas de **BAT y SYS** (las dos del lado del botón USER), sin tocar
     GND;
   - mételo desde abajo, con las orejas en su alojamiento, y pon epoxi en las orejas y sus agujeros;
   - unta el fondo de la cápsula con vaselina o pon cinta alrededor del conector plano y coloca la cápsula en el soporte. Los
     imanes suben el conector hasta el tope y lo centran con el de la cápsula mientras cura el epoxi.
5. **Base de carga:**
   - pega el conector igual que en el soporte, pero **sin puente**;
   - une BAT a **B+** del TP4056 y GND a **B−**, y deja SYS libre. El cable sale por el canal inferior hacia el cuello;
   - comprueba la polaridad con el polímetro **antes** de poner la cápsula.

## 5. Cableado (igual que la E.6)
```
 celda + (tras su PCM) ──[ fusible 1,5 A ]──► BAT del conector plano
 SYS del conector plano ───► + del conector de batería de la Heltec (JST 1,25)
 celda − ──┬──► − del conector de batería de la Heltec
           └──► GND del conector plano
 Sin cambios: Pololu (VIN en el 3V3 de la Heltec, SHDN en GPIO34), UART del ZED (RX GPIO35, TX GPIO33)
 Se quita el reed y su hilo a GPIO7.
```
- **Firmware:** no cambia. La 3.13.11 ya funciona sin reed (`AVO_REED_SLEEP 0`): tener corriente significa estar en el chaleco.
- **Consecuencia:** fuera del soporte la Heltec no tiene batería. Por USB-C funciona, pero **no carga la celda**. Para cargar, la
  cápsula tiene que estar en el soporte o en la base de carga.

## 6. Qué comprobar con las probetas
1. El conector plano entra en el alojamiento y queda a ras (o un poco hundido, nunca saliente).
2. Una vez cortada la membrana, el de muelles entra desde abajo y su cara queda unos 0,2 mm bajo la cara de apoyo.
3. Pon la probeta de la base sobre la del soporte, alineadas por los bordes en X 2 y X 17:
   - los imanes se atraen;
   - los 3 muelles bajan;
   - con el polímetro hay continuidad pin a pin.

## 7. Fuente
`fuente/avo_v22h_revE7_freecad.py` (FreeCAD 1.0.2; parámetros `OVAL*` y `EAR*`).

```
AVO_OUT=salida_E7 sh run_fc.sh avo_v22h_revE7_freecad.py
AVO_E7_CARGA=1 AVO_OUT=salida_E7_carga sh run_fc.sh avo_v22h_revE7_freecad.py
sh run_fc.sh e7_export.py
python3 voladizos.py E7/STL
```
