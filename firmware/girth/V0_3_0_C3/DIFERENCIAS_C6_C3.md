# Firmware de la cincha: V0.1.0 (ESP32-C6) → V0.3.0 (placa REV B, ESP32-C3)

| | V0.1.0 · XIAO ESP32-C6 | V0.3.0 · placa REV B ESP32-C3-MINI-1U-N4 |
|---|---|---|
| Placa / FQBN | `esp32:esp32:XIAO_ESP32C6` | `esp32:esp32:esp32c3:CDCOnBoot=cdc,FlashSize=4M,PartitionScheme=default` |
| Núcleo | arduino-esp32 3.3.12 | arduino-esp32 3.3.12 (el mismo) |
| Chip en la imagen | id 13 (ESP32-C6) | id 5 (ESP32-C3); el CI lo comprueba |
| Radio | ESP-NOW, canal fijo `NOW_CHANNEL_DEFAULT`, Wi-Fi 6 / BLE 5 | ESP-NOW igual (Wi-Fi 4 / BLE 5): **mismo protocolo** `avo_girth_link.h` v1 |
| `GirthHello.hw` | 1 | **2** (placa REV B C3) — la espalda solo lo muestra |
| IMU | ninguna conectada (`imu_count = 0`) | **LSM6DS3TR-C (o LSM6DSV16X) + MMC5983MA** por I²C (GPIO6 SDA, GPIO2 SCL), 104 muestras/s (120 con el LSM6DSV16X) al ritmo del dato listo (INT1 → GPIO0), lotes de 10 en paquetes `IMU`; si falta el magnetómetro, mx my mz = 0 y el resto sigue |
| Formato IMU | — | `IMU_FMT_9AXIS_I16`: ax ay az (±8 g, 0,244 mg/LSB), gx gy gz (±2000 dps, 70 mdps/LSB), mx my mz (±8 G, 0,244 mG/LSB) |
| Batería en `STATUS` | 0 (sin medir) | **medida**: GPIO3 (ADC1_CH3), divisor 1:2 |
| LED | GPIO15, activo bajo (XIAO) | **GPIO8**, activo bajo (pin de arranque: el LED está apagado al arrancar) |
| BOOT | GPIO9 | GPIO9 (igual) |
| Consola | USB-Serial-JTAG | USB-Serial-JTAG (igual) + UART0 en los pads TP4/TP5 |
| Encendido | lo daba la placa XIAO / batería | **reed por flanco** o 5 V de carga; el firmware pone **PWR_HOLD (GPIO5) = 1** lo primero |
| Apagado | no había | fuera del soporte 3 s, batería < 3,30 V 10 s, orden remota (`GirthPing.flags` bit 1 = `GIRTH_PING_SHUTDOWN`) u orden `APAGAR` por USB |
| En la base Qi | — | fuera del soporte: sueño profundo hasta cerrar el reed o quitar la base |
| Diagnóstico | línea cada 2 s | línea cada 2 s + órdenes `DIAG` (I²C, IMU, entradas, batería), `APAGAR`, `OLVIDAR` |
| Instalación | AVO Update (solo ESP32-C6) | **esptool / Arduino por USB** (`AVO_GIRTH_V0_3_0_C3_COMPLETO.bin` en 0x0). AVO Update todavía solo acepta el C6 |

## Asignación de pines (placa REV B)
| GPIO | Uso | Notas |
|---|---|---|
| 0 | IMU_INT (INT1 del LSM6) | puede despertar |
| 1 | REED (LOW = cerrado) | puede despertar |
| 2 | I²C SCL | pin de arranque: la hoja del módulo pide 1 al arrancar; el pull-up I²C de 4,7 k lo garantiza |
| 3 | BAT_ADC | ADC1_CH3 |
| 4 | CHG_PG (LOW = hay 5 V) | puede despertar |
| 5 | PWR_HOLD | 1 = mantener el corte de batería cerrado; pull-down 100 k |
| 6 | I²C SDA | 4,7 k a 3,3 V |
| 7 | CHG_STAT (LOW = cargando) | pull-up 100 k |
| 8 | LED (activo bajo) | pin de arranque: 1 al arrancar (pull-up 10 k) |
| 9 | BOOT | pin de arranque: pull-up 10 k; a masa = modo descarga |
| 10 | QI_CHG (LOW = Qi entrega potencia) | |
| 18 / 19 | USB D− / D+ | programación y consola |
| 20 / 21 | RXD0 / TXD0 | pads TP5 / TP4 (registro de la ROM, recuperación) |

## Cambios en la librería compartida (`firmware/back/V3_8_0/lib/avo_core/src/avo_girth_link.h`)
Solo se añaden constantes y comentarios: `GIRTH_PING_SHUTDOWN` (bit 1 de `GirthPing.flags`) y `GIRTH_HW_*`.
El formato de los paquetes no cambia. **La espalda todavía no envía el bit de apagado**: hasta que se añada
en su firmware, el apagado remoto solo se puede probar desde la cincha (orden `APAGAR`).

## Estado
Compila en el CI (ver `out/`). **No se ha probado en la placa**: la compilación no demuestra que funcione.
Pendiente de la primera placa: comprobar las direcciones I²C, los signos de los ejes, el tiempo que el corte
sostiene la alimentación tras un reinicio y el consumo apagado.
