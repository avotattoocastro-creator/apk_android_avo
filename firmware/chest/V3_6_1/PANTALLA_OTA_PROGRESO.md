# AVO CHEST V3.6.1 — pantalla OTA de progreso

## Diseño aprobado
- Aplicar rotación global 180° junto con todas las demás pantallas (ver ORIENTACION_180.md).
- Fondo negro AMOLED.
- Título blanco, grande, centrado: **ACTUALIZANDO...**
- Barra horizontal ancha de progreso, verde/turquesa, pista gris oscura.
- Debajo, porcentaje blanco grande centrado: **NN %**.
- Mostrar **ACTUALIZACIÓN COMPLETADA** únicamente después de que el proceso de OTA haya finalizado correctamente; reiniciar de forma controlada.
- En caso de error mostrar **ERROR DE ACTUALIZACIÓN** y código o causa breve legible, sin mostrar éxito falso.

## Progreso real y seguridad
- El porcentaje debe calcularse con bytes OTA confirmados escritos / tamaño total autorizado, acotado a 0–99 % mientras no termine la validación.
- 100 % solo después de comprobar SHA-256 y finalizar correctamente la imagen y selección de partición de arranque; no afirmar que el firmware nuevo arrancó hasta confirmarlo tras el reinicio.
- Diferenciar fases cuando sea posible: VALIDANDO, RECIBIENDO, VERIFICANDO, REINICIANDO.
- No permitir que la UI bloquee BLE ni el flujo de chunks; limitar repintados y mantener watchdog operativo.
- Conservar la firma ES256, verificación de manifiesto, control de versión y protección de rollback.
- En un error, no reiniciar ciegamente ni perder una sesión de grabación.
- Probar valores 0, 1, 50, 99, 100, cancelación, fallo SHA, desconexión BLE y primer arranque.

## Estado
Requisito registrado. **Pendiente de implementación, compilación y verificación en reloj.** No usar esta especificación como prueba de que existe una OTA instalable.
