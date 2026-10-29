## Microcontrolador
| | |
|---|---|
| Seleccionado | **ESP32-C3-MINI-1U-N4** (Espressif), chip ESP32-C3FN4, 4 MB de flash en el encapsulado, −40…85 °C |
| Código JLCPCB / LCSC | **C2911374** (pieza *Extended*, montaje SMT estándar) |
| Existencias y precio | ver la tabla de existencias de abajo (consulta del CI con fecha) |
| Alternativa | ESP32-C3-MINI-1U-H4 (C3013922): mismo módulo con chip de 105 °C y la misma memoria; el firmware sirve sin cambios |
| Antena | conector del módulo de 3.ª generación (W.FL / MHF III), como el C6-MINI-1U: la antena FPC no cambia |

**Por qué el C3:** es el único módulo Espressif con antena externa y el mismo tamaño (13,2 × 12,5 mm, huella con
los mismos pads) que JLCPCB tiene en existencias. El ESP32-S3-MINI-1U (C2980299) también está, pero mide
15,4 × 20,5 mm, consume más y cuesta más; no hace falta porque todas las funciones caben en el C3 con la IMU por I²C.
El C3 tiene 13 GPIO libres + USB: con el BNO085 por SPI habrían hecho falta 16.

## Diferencias frente a la REV A (ESP32-C6)
- MCU ESP32-C3 (RISC-V 160 MHz, Wi-Fi 4 + BLE 5) en lugar del C6 (Wi-Fi 6 + BLE 5 + 802.15.4): ESP-NOW igual.
- IMU: BNO085 (fusión en el chip, SPI, cristal, alimentación conmutada) → **LSM6DS3TR-C + MMC5983MA** por I²C. El
  protocolo de la cincha ya enviaba 9 ejes brutos (`IMU_FMT_9AXIS_I16`), así que la información que llega es la misma.
- Corte de batería: relé biestable G6KU (+ 2 × 220 µF, 9 transistores) → **enclavamiento con 2 MOSFET y 2 diodos**.
  Mismas funciones: encendido magnético, apagado remoto, consumo apagado < 1 µA, no se bloquea al cargar.
- R6/R7 a 3,3 kΩ (pieza *Basic*): carga 270 mA, entrada 462 mA.
- 81 piezas montadas (REV A: 104); 13 referencias *Extended* (REV A: 17).
- Contorno, capas, grosor, acabado, conectores (USB-C, batería, bobina, reed) y posiciones de los conectores: **sin
  cambios**. La tapa ya no necesita el rebaje del relé.

## Asignación de GPIO
Ver la tabla del README y `DOCS/ANALISIS_ELECTRICO.md` §4 (comprobada contra el símbolo y la hoja de Espressif).

## Firmware
`firmware/girth/V0_3_0_C3` (V0.3.0): compila en el CI para ESP32-C3 (imagen comprobada: chip id 5, particiones,
dos ranuras OTA). Diferencias con el firmware del C6 en `DIFERENCIAS_C6_C3.md` (dentro del zip). **No probado en
placa.** AVO Update todavía solo instala en el ESP32-C6: la primera carga se hace con esptool por USB.

## Riesgos eléctricos y mecánicos
- **Qi:** inductancia de la bobina sin medir; C1–C5 supuestos. Ajustar con la primera placa (`DOCS/AJUSTE_QI.md`).
- **Corte de batería:** calculado, no medido. Si Q11 tuviera un umbral alto y la celda estuviera baja, el impulso del
  reed podría quedarse corto: el arreglo es subir C40 (misma huella 0603).
- **Arranque del ESP32-C3 tras un reinicio:** el corte aguanta ~1,5 s; medir el tiempo real hasta PWR_HOLD.
- **IMU:** ejes y signos sin comprobar; el magnetómetro necesita calibración dentro de la cápsula (imanes).
- **BQ51013B:** 476 uds. en JLCPCB: es la pieza con menos existencias; reservarla si se va a tardar en pedir.
- **Mecánica:** cuna +0,6 mm, ranura del cable y postes de la tapa pendientes en el CAD de la cápsula.
- **Giro de las piezas:** el CPL sale de KiCad sin corregir; revisar la vista previa de JLCPCB.
