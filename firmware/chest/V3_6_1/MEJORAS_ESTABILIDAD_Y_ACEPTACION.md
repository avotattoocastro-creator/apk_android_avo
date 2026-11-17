# AVO CHEST V3.6.1 — mejoras adicionales aprobadas

El usuario confirma incluir estas mejoras en V3.6.1, además de la pantalla principal de 7 franjas, pantalla circular de carga USB, pantalla de progreso OTA y giro global de 180° (incluido táctil si corresponde).

## 1. Recuperación OTA segura
- Mantener verificación de firma ES256 y hash SHA-256, manifiesto con destino, versión y tamaño, y protección contra downgrade.
- Verificar partición de arranque, estado de rollback y confirmación del primer arranque; no declarar éxito permanente hasta superar comprobaciones de salud.
- Ante fallo de transferencia o validación, preservar la versión anterior arrancable.
- No aceptar OTA durante grabación o cierre de archivos.

## 2. Reconexión BLE y ESP-NOW
- Reconexión automática con backoff, sin bucles bloqueantes.
- Separar conexión de recepción de datos frescos; detectar pérdida de telemetría por timeout.
- Recuperar enlace espalda y cincha sin falsear estados.

## 3. Batería y protección AMOLED
- Alertas al 20 % y 10 %.
- Atenuar o apagar periódicamente la pantalla durante carga para reducir burn-in, manteniendo BLE y grabación.
- Mostrar porcentaje real y distinguir USB presente de carga efectiva si la PMU lo permite.

## 4. Grabaciones recuperables
- Flush/sincronización periódica de datos SD sin bloquear tareas críticas.
- Al detener sesión o apagar, finalizar y cerrar archivos correctamente.
- Recuperar archivos de sesión interrumpida con metadatos de recuperación; evitar duplicados.
- Proteger geocercas y grabación automática de oscilaciones GNSS.

## 5. Diagnóstico de GNSS y sensores
- Indicar pérdida de satélites, calidad GNSS real, NTRIP conectado y correcciones efectivas por separado.
- Distinguir autónomo, DGNSS, RTK FLOAT y RTK FIX sin inventar estados.
- Detectar datos antiguos de cincha (3 IMU), fallo de ESP-NOW y errores SD.

## 6. Autocomprobación de arranque
- Comprobar pantalla, batería/PMU, microSD, BLE y comunicación con espalda sin bloquear indefinidamente el arranque.
- Mostrar fallos reales en las franjas y diagnóstico serial.

## 7. Pantalla de apagado seguro
- Fondo negro, título grande «APAGANDO...», subtítulo «Guardando entrenamiento» y barra de fases reales.
- Detener recepción de nuevas muestras, vaciar buffers, sincronizar/cerrar SD y solo después ordenar corte de alimentación.
- Si falla el guardado, mostrar error y evitar indicar un apagado seguro inexistente.
- No presentar progreso simulado como progreso real.

## Criterios de entrega obligatorios
1. Implementar todo en código ejecutable, no solo documentos o cambios de versión.
2. Verificar visualmente 7 franjas, carga circular, progreso OTA, apagado y giro 180° en el Waveshare real.
3. Compilar con GitHub Actions y validar binario, versión, particiones y SHA-256.
4. Crear ZIP OTA con firmware.bin, manifest.json y manifest.sig firmado mediante AVO Signer, y verificar ES256.
5. Instalar desde V3.6.0, reiniciar, apagar/encender y confirmar V3.6.1 persistente; comprobar rollback ante fallos.
6. Grabar una sesión real, probar geocerca, GNSS, BLE/ESP-NOW y recuperación SD.

**Estado de este documento:** requisitos confirmados; no implica que las mejoras estén programadas, compiladas o probadas. No publicar ZIP final hasta cumplir criterios.
