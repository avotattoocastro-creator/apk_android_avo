# AVO CHEST V3.6.1 — release gate (NO PUBLICAR)

## Requisitos bloqueantes
- [ ] Implementar interfaz de siete franjas con telemetría fresca, estados de GNSS, cincha, BLE, ESP-NOW, SD y batería.
- [ ] Implementar orientación 180° de display y calibración de touch sin doble rotación.
- [ ] Implementar pantalla OTA con porcentaje de bytes confirmados y validación final.
- [ ] Implementar apagado seguro que cierre SD antes de cortar alimentación.
- [ ] Implementar reconexión BLE/ESP-NOW con timeout y backoff.
- [ ] Implementar recuperación de grabaciones interrumpidas sin duplicados.
- [ ] Implementar diagnóstico de GNSS/IMU/SD y autocomprobación al arranque.
- [ ] Implementar avisos batería y protección AMOLED.
- [ ] Verificar que el render de carga circular no sale de los límites reales.
- [ ] Compilar el firmware completo en CI con tests y sin marcadores de simulación.
- [ ] Crear ZIP OTA ES256 firmado y verificar firma, hash y manifest.
- [ ] Verificar físicamente actualización desde V3.6.0, reinicio, power-cycle y persistencia V3.6.1.
- [ ] Probar BLE/NTRIP, ESP-NOW, cincha 3 IMU, geocerca, SD y grabación real.

**Regla:** Ningún archivo debe denominarse FINAL/VERIFICADO hasta que todas las comprobaciones estén satisfechas. Un resultado de CI no equivale a verificación física.

## Estado observado
El parche apply_v361.py modifica versión y geometría de carga, pero exige marcadores de implementación de UI aún ausentes; la compilación de lanzamiento está bloqueada. El archivo fuente ZIP original no está disponible como árbol editable mediante los conectores usados en esta sesión. No se ha ejecutado ninguna prueba física.
