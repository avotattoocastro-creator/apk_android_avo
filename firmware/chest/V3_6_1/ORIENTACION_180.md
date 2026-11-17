# V3.6.1 — giro global de pantalla 180° (requisito confirmado)
El usuario solicita rotar **todas** las pantallas del reloj Waveshare ESP32-S3 Touch AMOLED 2.06" 180° respecto a la orientación actual. Incluye pantalla principal de siete franjas, círculo USB, arranque, ajustes, avisos y OTA.

## Implementación requerida
- Identificar la rotación actual en la inicialización Arduino_GFX y aplicar rotación de 180° a la pantalla completa **una sola vez** (normalmente índice de rotación actual + 2 módulo 4), no rotar individualmente widgets.
- Revisar anchura/altura y coordenadas reales tras rotación, sin asumir resolución de un mockup.
- Transformar también entrada táctil: x' = ancho-1-x, y' = alto-1-y, **solo si el controlador táctil no aplica ya la rotación**; verificar mediante pruebas en las cuatro esquinas. Evitar doble rotación.
- No rotar GNSS, datos de IMU ni otros sensores.
- Confirmar visualmente todas las pantallas y respuesta táctil en hardware.
- No publicar OTA V3.6.1 hasta implementar las siete franjas y el anillo de carga, compilar, firmar y validar el reinicio persistente.

**Estado:** requisito registrado; implementación y pruebas pendientes.
