# AVO GIRTH V0.4.x — cincha XIAO ESP32-C6 + BNO085

## Estado tras la prueba de 0.4.2 (31/10/2026, 16:51)
**PROBADO FÍSICAMENTE:**
- **Enlace con la espalda (BACK 3.13.11):**
  - re-emparejamiento automático con C0:B4 y estado CONFIRMADA;
  - la espalda confirma 1352 paquetes, 0 perdidos;
  - −60/−66 dBm con la antena interna.
- **IMU:** ~125 Hz, 0 muestras perdidas, 0 errores I²C, periodo estable de 7978 µs.

**Falta:** ver los datos de IMU en una sesión del pecho y en la app.

## 0.4.2 (31/10/2026) — tras la prueba de 0.4.1 en el hardware
- **Resultado de 0.4.1 (monitor del usuario):**
  - IMU estable, de 124,8 a 126,0 Hz, sin pérdidas del sensor, |acc| ≈ 9,9 m/s²;
  - la cincha seguía emparejada con la espalda antigua CD:24 (0 ACK de 128), así que la sesión del pecho salió
    sin datos de cincha;
  - en la cola se perdieron **12 046 muestras de una vez**: el monitor serie bloqueaba el bucle;
  - el periodo estimado oscilaba entre 8156 y 8639 µs (el real es ~7940 µs).
- **Correcciones de 0.4.2:**
  - el monitor serie ya no bloquea nunca (`setTxTimeoutMs(0)`);
  - el periodo de los lotes es la media desde el arranque (muestras contadas y tiempo transcurrido), estable;
  - **re-emparejamiento automático:** si la espalda guardada no da ningún ACK de radio en 30 s y otra espalda
    responde con WELCOME, la cincha pasa a esa espalda. La espalda solo da la bienvenida a la cincha que ya tiene
    aceptada o con su ventana de emparejamiento abierta, así que los dos lados están de acuerdo. Ya no hace falta
    pulsar BOOT en este caso.

## 0.4.1 (31/10/2026) — tras la primera prueba de 0.4.0 en el hardware
- **Resultado de 0.4.0 en la cincha (PROBADO FÍSICAMENTE, monitor serie del usuario):**
  - **IMU:** BNO085 en 0x4A a 400 kHz, INT a los 100 ms, SH-2 3.2.13 (pieza 10004148, build 6);
  - 124,8–126 Hz, sin muestras perdidas y sin errores I²C;
  - en reposo, acc (0,00, −3,98, 9,00) m/s² con |a| ≈ 9,84; aceleración lineal ≈ 0; cuaternión coherente con
    unos 24° de inclinación.
- **Enlace (log de 0.4.0):** la espalda guardada (AC:A7:04:06:CD:24) no da ningún ACK. Responde **otra** espalda,
  AC:A7:04:06:C0:B4. La cincha la ignora a propósito, porque solo acepta la espalda guardada. → En la cincha,
  BOOT 5 s para olvidar la antigua y emparejar con la actual.
- **Correcciones de 0.4.1:**
  - el BNO elige su periodo admitido más cercano: al pedir 100 Hz da ~125 Hz. 0.4.0 escribía 10 000 µs en los
    lotes; **0.4.1 usa el periodo real** sacado de las marcas de tiempo y muestra al arrancar los periodos que
    confirma el BNO;
  - ya no sale el mensaje «GPIO isr service is not installed» en el primer arranque.

Rama: `feature/girth-fw-0-4-0-bno085` (sale de `feature/avo-wifi-sync`). No toca `main`, la espalda, el pecho, las
particiones ni el mecanismo de actualización.

**Estado: COMPILADO / CI.** Pruebas de host 40/40 (simulación). **NO VERIFICADO** en el hardware: el BNO085 no se
declara operativo hasta ver muestras reales en el monitor, ni el enlace hasta ver la confirmación de la espalda.

## 1. Auditoría (31/10/2026)

| Elemento | Encontrado en el repositorio |
|---|---|
| Firmware de cincha con código fuente | GIRTH **0.1.0** (`firmware/girth/V0_1_0`): solo enlace ESP-NOW, 0 IMU |
| Firmware de cincha instalado antes | GIRTH **0.2.0**: solo el binario (`AVO_GIRTH_V0_2_0_COMPLETO.bin`); **su código fuente no está en el repositorio** |
| Diagnóstico | 0.2.4-diag (`firmware/girth/DIAG_0_2_1`) |
| Otra cincha | 0.3.0 para la placa REV B con ESP32-C3 (otras ramas, otro IMU: LSM6/MMC5983MA); no aplica al XIAO |
| Espalda | 3.11.0 en `feature/avo-wifi-sync`; hasta **3.13.11** en `fix/back-3-13-11-usb-pololu-off`. El enlace con la cincha (`GirthHub`, enlace v1) existe desde **BACK 3.10.0** y es idéntico en 3.10.0–3.13.11. **BACK 3.8.2 no tiene enlace con la cincha.** |

### Causas identificadas

1. **BNO085 «NO RESPONDE» (0.2.0).** Sin el código de 0.2.0 no se puede señalar la línea exacta. Del binario se
   sabe que usaba el mismo cableado y niveles (PS0 bajo, CS alto, ADD bajo, `Wire.begin(23, 16)` a 400 kHz,
   dirección 0x4A, reset por GPIO1) con una biblioteca de tipo SparkFun. El 0.2.4-diag, con esos mismos niveles,
   ve INT bajar a los ~94 ms y el ACK en 0x4A, así que el montaje responde. Un ACK no prueba el protocolo SH-2, y
   0.2.0 no tenía recuperación: un fallo al arrancar dejaba «IMU: NO RESPONDE» y «muestras=0» para siempre.
   **Solución:** controlador SHTP/SH-2 propio y comprobable en el ordenador. El arranque solo cuenta como bueno si
   el BNO contesta la petición de identificación (0xF9 → 0xF8) y entrega muestras. Si falla, reintenta solo, con
   pausa creciente y a 100 kHz si 400 kHz falla.
2. **ESP-NOW «envios ok=37 fallo=74», «pings=0», «fw=?».** La proporción exacta 1:2 sale del propio código. Cada
   2 s se enviaba un HELLO por difusión, que cuenta siempre como «ok» porque no tiene ACK, y otro dirigido a la
   espalda guardada con 2 intentos, que fallaban los dos. Es decir: **la espalda guardada no dio ni un ACK de
   radio**.
   - Causa probable en el firmware: **0.2.0 seleccionaba la antena EXTERNA** (GPIO14 alto) sin antena conectada,
     y el RSSI medido fue de −96 dBm.
   - Otras causas posibles que el firmware no puede resolver: espalda apagada o dormida, espalda sin enlace con la
     cincha (versión < 3.10.0, por ejemplo 3.8.2) o una MAC guardada que ya no es la de la espalda.
   - **Solución:** antena interna por defecto. El monitor dice cuál de los casos se da: sin ACK, ACK sin
     bienvenida (la espalda está emparejada con otra cincha) u otra espalda que responde. Los contadores de envío
     ya no se confunden con la confirmación.
3. **Batería «0 mV» / «512 mV».** El divisor en GPIO5 (MTDI) **no está montado**. El 0 sale de la regla de 0.2.0
   (por debajo de 499 mV se escribe 0). Los 512 mV son el pin al aire, que flota.
   - **Solución:** fuera de 3,0–4,5 V se informa «no medida» y no se inventa ningún valor.
   - El divisor 1:2 (220 k / 220 k) es el previsto en la documentación, **sin verificar en la placa**. Se puede
     cambiar con la orden `bateria <divisor>`.

## 2. Qué hace 0.4.0

- **IMU (tarea propia, por la interrupción INT).**
  - Cada 10 ms (100 Hz): acelerómetro (con gravedad, Q8 m/s²), giroscopio (Q9 rad/s), magnetómetro (Q4 µT),
    aceleración lineal sin gravedad (Q8 m/s²) y game rotation vector (cuaternión Q14). El cuaternión no usa el
    magnetómetro, así que los imanes no lo desvían.
  - El reloj de muestreo lo marca el acelerómetro. Cada muestra lleva la hora del ESP32 en el instante de medida:
    flanco de INT menos el retardo que informa el BNO.
  - Cuenta muestras, muestras perdidas por el sensor (huecos en la secuencia), muestras perdidas en la cola,
    frecuencia real y precisión (0–3).
- **Envío a la espalda (enlace v1 sin cambios).** Cada 100 ms salen dos lotes con el mismo número de lote y la
  misma marca de tiempo:
  - **fmt 0:** ax ay az gx gy gz mx my mz, 18 B por muestra. La espalda, el pecho y la app ya lo entienden.
  - **fmt 1 (nuevo):** lx ly lz qi qj qk qr, 14 B por muestra. La espalda lo reenvía tal cual. La app y el motor de
    análisis todavía no lo leen: la app lo ignora y el motor lo cuenta como «registro no válido» hasta que se
    añada.
  - Un hueco de tiempo cierra el lote, para que t0 + i × periodo siga siendo cierto.
- **Confirmación.** El enlace solo está «CONFIRMADO» si llega el PING de la espalda (cada 1 s). El PING dice
  cuántos paquetes de la cincha ha aceptado la espalda y cuántos ha detectado como perdidos.
- **Reposo** (desactivado por defecto). Con `reposo on`: si GPIO6 (contacto 3 del pogo) está alto 30 s, el ESP32
  duerme con el BNO en reset y despierta cuando GPIO6 baja. Está desactivado por defecto porque el contacto aún
  no está cableado, y un pin al aire haría que no despertara nunca.
- **Se conserva el emparejamiento** (mismo espacio NVS «avogirth»). BOOT 5 s olvida la espalda.

## 3. Pruebas

| Prueba | Resultado |
|---|---|
| Host: parser SH-2 (valores, marcas de tiempo, huecos, informes desconocidos o cortados, reset, identificación, intervalos) | 40/40 OK (simulación) |
| Host: ida y vuelta por el `GirthHub` real de la espalda (emparejar, reenviar fmt 0 y fmt 1, pérdidas, PING) | incluido en 40/40 (simulación) |
| Host: biblioteca de enlace de la espalda | OK (sin cambios) |
| Compilación ESP32-C6 (arduino-esp32 3.3.12) e imagen (cargador C6, particiones de siempre, ota_0 0x10000, marca 0.4.0 AVO-GIRTH) | OK en CI |
| BNO085 real, enlace real, batería, reposo, consumo | **PENDIENTE (hardware)** |

## 4. Prueba en el hardware (lo que hay que enviar)

1. Espalda con **BACK ≥ 3.10.0** (ver «CINCHA:» en su monitor), encendida, fuera de reposo y con el pecho
   encendido para que reenvíe la IMU.
2. Instalar `out/AVO_GIRTH_V0_4_0_COMPLETO.bin` con AVO Update.
3. Abrir el monitor de la cincha 60 s y enviar **las 3 líneas** `[AVO CINCHA 0.4.0]` de un mismo ciclo y la línea
   `IMU: BNO085 en 0x4A ... SH-2 x.y.z` del arranque. Si aparece «último error», enviarlo también.
4. Mover la cincha a mano 10 s y enviar otra vez la línea IMU.
5. En la espalda, enviar la línea `CINCHA:` (paquetes, perdidos, IMU reenviados).

**Para dar la IMU por buena:** ~100 Hz, «muestras» creciendo, acc ≈ 9,8 m/s² en reposo y lin ≈ 0.

**Para dar el enlace por bueno:** «CONFIRMADA», «la espalda confirma N paquetes» creciendo y «perdidos» bajo.
