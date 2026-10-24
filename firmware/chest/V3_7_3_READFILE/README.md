# AVO CHEST V3.7.3-rc1 — corrección de READ_FILE (descarga de entrenamientos)

**Estado:** compilado en CI, **NO VERIFICADO** en el reloj. **No apto para OTA** hasta comprobar en el reloj la firma,
las particiones y la recuperación; instalar por USB con AVO Update conservando el binario 3.7.2-rc1 de recuperación.

## Síntoma (24-10-2026)
`Sin respuesta del reloj (READ_FILE) en 384 kB tras 9 intentos (timeouts 40, fragmentos perdidos 0, CRC 0)` —
S1E8C_000009_001, 446,5 kB. Antes: 288 kB de 724,9 kB (S1E8C_000035_001) y «Escritura BLE fallida (estado 133)» a 22 kB.

## Comparación con V3.5.4 (SD FIX, verificado el 21-10-2026)
| Punto | V3.5.4 | V3.7.0-rc2 / 3.7.2-rc1 (actual) |
|---|---|---|
| `op_read` (storage.cpp): máx. 2048 B, cabecera offset + tamaño + CRC-32 | sí | **idéntico, sin regresión** |
| Fragmentación (`tx_task`) | por MTU | idéntica |
| Cola de respuestas de ficheros (`file_cb` → `queue_msg`) | espera 500 ms y **descarta sin rastro** | idéntica |
| Notificación fallida a mitad de mensaje | se aborta el resto **sin rastro** | idéntica |
| Telemetría 2 Hz durante la descarga | compite por los búferes de notificación | idéntica; **3.7.2 añade la nueva pantalla** (tarea UI, PSRAM, SPI) |
| Contadores en DIAG de notificaciones fallidas | no | no |

**Conclusión:** el límite de 2048 B de 3.5.4 sigue presente: no se perdió. El síntoma actual (ningún fragmento de la respuesta
llega al móvil, 0 huecos, 0 CRC) es el de una respuesta FILE_DATA que **no sale del reloj**: o la cola de envío BLE estaba llena más
de 500 ms y se descartó, o la primera notificación falló 50 veces seguidas. Ambos casos eran silenciosos y no se podían ver en DIAG.
La causa exacta (qué de los dos y por qué la cola o los búferes estaban llenos) **queda por confirmar en el reloj** con los contadores nuevos.

## Cambios de 3.7.3 (solo `ble_service.cpp`, protocolo sin cambios)
1. Las respuestas FILE_DATA esperan hasta 2 s a que haya sitio en la cola (antes 500 ms y descarte silencioso).
2. Con una descarga activa (READ_FILE en el último 1,5 s) se pausan las notificaciones de telemetría: modo descarga en el reloj.
3. READ_FILE limitado además a 16 notificaciones con la MTU negociada (con MTU ≥ 160 sigue siendo 2048 B).
4. DIAG añade `notify_fail`, `tx_msgs`, `file_reads`, `file_drop` (respuesta no encolada) y `msg_abort` (notificación fallida a mitad).

**No se ha tocado:** formato de mensajes, UUID, NTRIP/RTCM, ESP-NOW, GNSS, almacenamiento, OTA, firma, particiones, pantalla.

## Android (misma rama)
`core/sync/ResilientDownload.kt`: bloques de 2048 B, reintento del mismo offset (sin respuesta, ocupado, CRC, offset inesperado,
errores GATT como 133), espera de reconexión, reanudación desde lo descargado, nunca escribe un bloque fuera de orden ni duplicado
(`SessionDownload.append` exige offset = longitud local), y el error final incluye timeouts, fragmentos perdidos, CRC y respuestas tardías.
Pruebas en CI con un reloj simulado (`DownloadProtocolTest`): archivo pequeño, 446,5 kB, > 1 MB en 2 segmentos, MTU pequeña,
respuestas perdidas 20 veces en el mismo offset (caso real), fragmento perdido y error GATT, respuestas retrasadas tras el timeout,
pérdida temporal de BLE con reconexión, reanudación desde un offset intermedio, NTRIP activo, descargas consecutivas, SHA-256 completo,
y fallo permanente con diagnóstico.

## Validación física pendiente
1. Instalar 3.7.3-rc1 por USB. 2. Descargar S1E8C_000009_001 y S1E8C_000035_001 completas y verificar SHA-256 en la app.
3. Tras cada descarga, leer DIAG (Ajustes > Diagnóstico) y anotar `file_drop`, `msg_abort`, `notify_fail`. 4. Repetir con NTRIP activo.
