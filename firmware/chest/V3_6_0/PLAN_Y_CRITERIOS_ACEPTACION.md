# AVO CHEST V3.6.0 — plan de integración y aceptación

Versión objetivo confirmada por el usuario: **3.6.0**. Rama: `develop/avo-performance-horse`. Base: V3.5.8 verificada en reloj, parches V3.5.9. No publicar como OTA instalable hasta completar los criterios.

## Pantalla normal: 7 franjas
- Tipografía NEGRA, grande y legible, siete franjas visibles simultáneamente en AMOLED 2.06"; distribución fiel a la referencia aprobada, adaptada a resolución real.
- Bluetooth: verde conectado / rojo desconectado.
- Chaleco: verde sistema correcto / rojo error.
- Espalda: verde ESP-NOW conectado / rojo sin enlace.
- Cincha 3 IMU: verde datos recientes de los tres sensores / rojo ausencia o error, sin inferir conexión por estado de espalda.
- GPS: rojo sin GNSS válido, azul GNSS autónomo sin NTRIP, verde correcciones NTRIP activas. Texto adicional de tipo real GNSS, DGNSS, RTK FLOAT, RTK FIX, satélites y precisión si están disponibles. Nunca equiparar NTRIP a FIX.
- SD: rojo ausente/error, verde montada y disponible, azul grabando; indicar estado real de sesión.
- Batería: porcentaje real grande; fondo verde >50%, amarillo 21–50%, rojo <=20%; estado de carga solo si detectable.

## Pantalla USB
- Fondo negro, anillo circular grande verde/turquesa proporcional a porcentaje real, porcentaje blanco grande en centro y «CARGANDO...» debajo; «CARGA COMPLETA» solo cuando corresponda.
- Mostrar automáticamente al conectar USB; al desconectar restaurar el estado de pantalla anterior; no interrumpir BLE/ESP-NOW, geocercas, SD, GNSS ni OTA; atenuar/apagar periódicamente para evitar burn-in AMOLED. Verificar capacidad real de PMU para distinguir USB de carga efectiva.

## Robustez
- Reconexión BLE/ESP-NOW sin bloqueos; watchdog de datos obsoletos.
- Persistencia de sesión y sincronización segura de SD al parar/apagar; no truncar datos.
- Diagnóstico visible/serial de errores y estados.
- OTA firmada ES256 fail-closed: comprobar destino, versión, hash, tamaño, key-id, boot partition y confirmación de arranque; preservar rollback y no permitir downgrade.
- App Android: preflight y transferencia deben admitir instalada 3.5.8 o 3.5.9 y destino 3.6.0, sin debilitar verificación de firma.

## Aceptación antes de distribución
1. Implementar firmware real (no solo esta especificación), comprobar resolución, textos y colores.
2. Compilar por GitHub Actions y verificar .bin, versión, tamaño/particiones, SHA-256 y logs.
3. Firmar ZIP con clave privada local de AVO Signer; incluir firmware.bin, manifest.json, manifest.sig; verificar firma con clave pública fijada.
4. Pruebas físicas en reloj: carga/desconexión, 7 estados, GNSS, BLE/ESP-NOW, SD, geocerca, OTA, apagado/reinicio y rollback.
5. Publicar enlace de descarga directa únicamente cuando exista artefacto verificado.

Estado inicial: PLAN APROBADO, no firmware compilado ni OTA disponible.
