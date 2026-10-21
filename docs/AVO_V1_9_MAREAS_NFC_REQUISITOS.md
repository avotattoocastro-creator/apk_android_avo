# AVO PERFORMANCE HORSE — MAREAS (requisitos recuperados 21/10/2026)

Estado: especificación de integración; no equivale a implementación funcional ni a APK.

## Pantalla de mareas
- Pantalla propia en Android, inspirada funcionalmente en Tu Marea Pro sin copiar interfaz ni datos propietarios.
- Ubicación configurable, predeterminado playa del Regatón, Laredo (Cantabria).
- Horas de pleamar y bajamar, altura estimada, coeficiente y amplitud, tendencia subiendo/bajando y tiempo restante al próximo extremo.
- Gráfica interactiva por horas, calendario de días, fases lunares, amanecer/atardecer.
- Viento (dirección/racha), oleaje (altura, período y dirección), temperatura ambiente/agua, presión y precipitación.
- Mostrar proveedor, estación o punto de predicción, actualización y zona horaria Europe/Madrid.
- Diferenciar inequívocamente PREDICCIÓN astronómica, MODELO meteorológico y MEDICIÓN de mareógrafo; nunca presentar estimaciones como tiempo real medido.
- Estado sin conexión: último dato en caché con antigüedad; no inventar valores ni horarios.

## Vinculación con entrenamientos
- Capturar instantánea al inicio y fin: posición/ubicación, hora, altura estimada, tendencia, tiempo desde pleamar/bajamar, coeficiente/amplitud, viento, oleaje y origen/calidad de cada dato.
- Añadir metadatos opcionales a entrenamientos existentes sin alterar telemetría original.
- Exportar/importar metadatos en .avo; mantener compatibilidad con sesiones antiguas y no inventar datos ausentes.
- Mostrar marea junto a gráficas de velocidad y aceleración, comparar creciente/vaciante y correlacionar con firmeza de arena si hay medidas.
- Resolver datos en segundo plano cuando haya conexión; reintentar y conservar estado pendiente si no se dispone de red.
- Persistencia local y sincronización con servidor según esquema versionado.

## Validaciones
- Fuentes y licencia verificadas; API/endpoint documentado y disponible, gestión de errores y límites.
- Casos de uso con huso horario, cambios de horario de verano, ausencia de cobertura, GPS impreciso y sesión cruzando pleamar.
- Tests de serialización .avo, migración de base de datos y visualización sin datos.

## NFC global
- Cuando AVO está abierta, ReaderMode de la actividad; pantalla de gestión permite escribir.
- Con otra app abierta, registrar ACTION_NDEF_DISCOVERED para URI avohorse://identity/horse|rider/{code} y procesar onCreate/onNewIntent.
- Validar esquema/host/ruta/código y existencia local; no cambiar identidad durante grabación; sincronizar por BLE o dejar pendiente.
- Mostrar confirmación o error. Sin prometer lectura con pantalla apagada.
