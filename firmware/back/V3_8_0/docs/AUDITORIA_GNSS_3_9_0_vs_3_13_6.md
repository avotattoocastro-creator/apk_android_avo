# Auditoría GNSS — BACK 3.9.0 frente a 3.13.6 y cambios de la 3.13.7

Fuentes comparadas (código real del repositorio):
- **3.9.0**: commit `5c8bd11` (25/10/2026), `firmware/back/V3_8_0/AVO_BACK_V3_8_0/AVO_BACK_V3_8_0.ino` (333 líneas).
- **3.13.6**: commit `a1c3ea1` (31/10/2026, rama `feature/avo-back-v4`), mismo archivo (775 líneas).
- Biblioteca `lib/avo_core`: entre ambas cambian `avo_ubx_zed.*` (lectura de MON-VER y NAV-SAT/NAV-SIG por separado,
  3.10.1) y `avo_back_core.*` (cincha, 3.10.0). **La búsqueda de baudios y la configuración del ZED (`ZedManager`) son
  las mismas**: candidatos 38400, 115200, 230400, 460800, 921600, 9600; poll MON-VER, UBX activado a ciegas en UART1/2,
  sondeo de puerto, VALSET de RTK y 8 Hz; reintento cada 10 s si no contesta.

## 1. Diferencias reales en la cadena alimentación → ZED → UART

| Punto | 3.9.0 | 3.13.6 |
|---|---|---|
| Alimentación del ZED | Del 3V3 fijo de la Heltec (o Vext encendido en `setup`): tiene corriente desde el arranque | Regulador Pololu S7V8F3 desde la batería, SHDN en **GPIO34**; se enciende desde `loop()` 1 s después del arranque |
| Antes del UART | Nada | `vext_on_soft()` (PWM 200 ms en GPIO36, sin uso con el Pololu) + GPIO34 alto + 50 ms |
| Apertura del UART | `ZED.begin(38400, 8N1, RX=33, TX=35)` en `setup()` | Igual, pero 50 ms después de dar corriente (el ZED tarda ~1 s en arrancar; la búsqueda empieza antes y reintenta) |
| Bytes al abrir | Ninguno | 8 × 0xFF (para despertar de un reposo por software) |
| Instancia | `HardwareSerial ZED(1)` = UART1 | Igual |
| `zed_set_baud` / `zed_write` | Siempre | Solo si `s_zed_on` |
| Pines RX/TX | Fijos 33/35 | **Variables**: se intercambian cada 10 s si no llega nada y el orden se guarda en NVS (`zedswap`) |
| Antes de dormir | No duerme | Orden **UBX-RXM-PMREQ** (reposo por software, despertar por flanco en RX/EXTINT), TX fijado a LOW, GPIO34 a LOW con hold |
| Al despertar | — | Liberación de holds de 33/35/34/36/37 y LoRa |
| Otros pines tocados | — | GPIO7, 18, 19, 20, 21, 47, 48 como entradas con pull-down (detección de USB), registros del USB-Serial-JTAG (pad y pull-up de D+/D−) |
| Radio | Wi-Fi/ESP-NOW en `setup` a la vez que el ZED | Igual, el ZED se enciende 1 s después |

## 2. Hallazgos
1. **Intercambio automático de RX/TX (3.13.6)**: con el cableado correcto, si el ZED tardaba en hablar o no tenía
   corriente, la espalda cruzaba los pines y guardaba en NVS el orden. Puede dejar la placa en el orden equivocado en
   arranques siguientes. **Eliminado** en 3.13.7, se borra la clave `zedswap`.
2. **PMREQ antes de dormir**: si el corte por GPIO34 no llega a quitar la corriente al ZED (cable de SHDN, VIN o
   VOUT), el ZED queda en reposo por software y no contesta hasta ver un flanco en su RX. Con el Pololu el PMREQ no
   aporta nada. **Eliminado** en 3.13.7; además al arrancar se hace un ciclo de corriente limpio (GPIO34 a 0 durante 500 ms).
3. **GPIO35 = LED blanco y TX del ZED**: en marcha ningún código lo usa como LED (solo el UART). Al dormir se fija a LOW
   (LED apagado, sin alimentar el ZED por su RX). Sin conflicto en funcionamiento.
4. **Monitor serie y GNSS**: `Serial` es UART0 (GPIO43/44, puente CP2102); el ZED usa UART1 en 33/35. Sin conflicto.
   El texto `puerto=UART0` del monitor era el puerto **del ZED** sin detectar (0 = desconocido), no la UART del ESP32;
   en 3.13.7 dice `puerto del ZED=?`.
5. **Holds y ahorro**: los holds se liberan al arrancar antes de usar los pines; la CPU a 160 MHz no afecta a los baudios
   (reloj del UART independiente). La LoRa dormida no comparte pines con el ZED.
6. **Registros de campo (31/10, 3.13.4–3.13.6)**: `UBX=0 NMEA=0` a 230400 y 38400, es decir, **ni un byte** del ZED
   (un ZED de fábrica envía NMEA a 38400 cada segundo aunque nadie le hable). Eso apunta a que **no tiene tensión** o a que
   su TX no llega a GPIO33, no a la configuración. También: batería 2,95–3,46 V y brownout al arrancar la radio.

## 3. GPIO34 y tensiones
- El S7V8F3 lleva **100 kΩ de SHDN a VIN** (batería, hasta 4,2 V).
- Con GPIO34 en salida (ALTO 3,3 V o BAJO) la tensión del pin la fija el ESP32: correcto. Con GPIO34 en alta impedancia
  (≈ 0,3 s del cargador de arranque tras un reinicio) la resistencia lleva el pin hacia la batería: ≈ 3 µA por el diodo
  de protección hacia 3V3 (4,2 − 3,3 − 0,6 V)/100 kΩ. No daña en la práctica, pero queda fuera del máximo absoluto
  (VDD + 0,3 V). **Recomendado**: 100 kΩ de SHDN a GND (divisor 100 k/100 k → SHDN ≤ 2,1 V con el pin suelto, sigue por
  encima del umbral de encendido de 1,2 V). El firmware no puede medir esa tensión.

## 4. Lo que hace la 3.13.7
- Pines fijos RX=GPIO33, TX=GPIO35 (UART1, `HardwareSerial ZED(1)`).
- Antes de la radio: GPIO34 = 0 (500 ms) → GPIO34 = 1 (alimentación **solicitada**) → 1,5 s → UART1 → **solo escucha**
  a 38400, 9600, 115200, 230400, 460800 y 921600 (2,2 s / 1,3 s cada uno), contando bytes, bytes/s, UBX válidos/malos y
  NMEA válidos. Si no oye nada, envía 8 × 0xFF (flanco, no es configuración) y repite una vez. No apaga el GPS.
- Después arranca ESP-NOW; la configuración UBX/RTK/8 Hz la hace `ZedManager` como en 3.9.0.
- Monitor cada 2 s: `GNSS: UART1 RX=GPIO33 TX=GPIO35 | N B/s | UBX validos | NMEA validos | NAV-PVT | GPIO34=1
  (alimentacion SOLICITADA, tension no medida) | GPS NO VERIFICADO (sin NAV-PVT)` mientras no haya NAV-PVT.
- Al arrancar: motivo de reinicio (9 = brownout) y batería en reposo. El detector de brownout **no** se toca.
- Se mantienen: ahorro de la 3.10.2, corte por batería baja (3,30 V / 3,45 V, sin cambios), detección de USB, cincha,
  emparejamiento.

## 5. Limitaciones
- Ningún firmware puede comprobar la tensión del ZED: «GPIO34 = 1» es la orden, no la medida.
- Si el diagnóstico dice `SIN DATOS DEL ZED en ningun baudio`, el problema es de hardware: medir VOUT del Pololu (3,3 V),
  VIN (batería), GND común y continuidad del TX del ZED a GPIO33.
- El GPS solo se da por recuperado cuando el monitor muestre **NAV-PVT > 0**.
