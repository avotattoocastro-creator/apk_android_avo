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


## Estado de implementación — 22/10/2026 (rama unificada)

Este documento conserva los **requisitos**, no es un certificado de cumplimiento. La app Android está en versión **1.9**, `versionCode 11`. Los cambios de mareas incluyen `TidesScreen.kt` con indicador vertical, curvas, tablas por día, datos de modelo Open-Meteo Marine/Weather y un lector opcional de la tabla astronómica de Santander. La tabla oficial se usa solo si hay datos recientes que superen el análisis; **no está comprobado que el lector funcione con el HTML actual ni que la precisión sea equivalente a Tu Marea Pro**. Santander es referencia regional, no una medición local de El Regatón. Las alturas del modelo se refieren al nivel medio y las oficiales al cero del puerto: no mezclarlas.

`TrainingMarineEntity` conserva instantáneas marítimas, y `WatchSyncManager` intenta asociar previsiones a sesiones recientes cuando se sincronizan. No hay prueba física completa de estas funciones ni de los requisitos de captura al final, histórico y servidor. Los requisitos pendientes de esta especificación (caché, ubicación configurable, amplitud, amanecer, presión, historial, comparativas, exportación completa y pruebas de NFC) **no deben marcarse como entregados sin evidencia**.

El desarrollo del firmware de pecho y AVO Signer está centralizado en `develop/avo-performance-horse`. CHEST V3.5.6 es la última fuente integrada; V3.5.7 con recepción de firma OTA no está validado. Consultar el README raíz para versiones y criterios de aceptación.
