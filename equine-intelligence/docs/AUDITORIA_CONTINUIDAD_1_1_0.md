# Auditoría de continuidad — Equine Intelligence Engine 1.0.0-dev1 → 1.1.0-dev1 (2026-10-24)

Punto de partida: rama `feature/avo-equine-intelligence-engine`, commit `3531a58`, CI 40027191410 (éxito).
`develop/avo-performance-horse` y `main` no se han modificado. La app Windows vigente estaba en `feature/windows-advanced-analysis`
(WPF .NET 10, CI en verde); se ha traído a esta rama para integrarla, sin crear una aplicación paralela.

## Problemas encontrados y corregidos
| # | Hallazgo | Evidencia | Corrección |
|---|---|---|---|
| 1 | La app (Kotlin) y el motor daban distancias distintas para el mismo fichero del firmware: 89,40 m frente a 87,00 m | `sample.avr`: la app puentea las épocas sin FIX, el motor no | Métrica `distancia_puenteada` con la regla de la app; prueba Kotlin que exige igualdad (±0,05 m) |
| 2 | JNI con `NewStringUTF`/`GetStringUTFChars` («modified UTF-8»): rutas o nombres con caracteres fuera del BMP se corrompen o abortan | — | Paso de `byte[]` UTF-8; prueba con ruta `sesión_🐎.avo` en JVM y emulador |
| 3 | API C sin opciones, sin cancelación, sin versión de API y errores en formatos distintos | `avo_eq_export_csv` devolvía texto de error sin JSON | API v2 (`analyse_ex`, `compare_ex`, `cache_invalidate`, códigos 0–5, error JSON) |
| 4 | Las series JSON no llevaban unidades ni aire/cadencia; imposible sincronizar gráficas | v1 solo `t`, `velocidad`, `aceleracion` | `series` + `unidades_series` + `series_cincha` + `itow_inicial_ms` |
| 5 | Clasificador de aires O(N·M) en la búsqueda de velocidad | — | Búsqueda binaria (30 min con 3 IMU: 2,4 s en Release) |
| 6 | Series IMU en `double` (7 × 8 B por muestra) | — | `float` (valores int16 exactos): mitad de memoria |
| 7 | **Cadencia el doble de la real** cuando domina el 2.º armónico | 28 de 28 ventanas erróneas (1,90 Hz con verdad 0,95) | Autocorrelación insesgada, criterio relativo de subarmónico, estado AMBIGUA por potencia en f/2 |
| 8 | Cadencia sin incertidumbre ni estado: cifras aparentemente precisas | — | σf por ventana y estados VALIDA / PERIODICIDAD_DEBIL / AMBIGUA / INCIERTA / DATOS_INSUFICIENTES |
| 9 | Con 8 % de lotes de radio perdidos no salía ninguna ventana de cadencia | 0 ventanas válidas | Interpolación controlada ≤ 0,25 s en copia derivada, con fracción interpolada y límite del 10 % |
| 10 | Media de aceleración sostenida sesgada por la ventana de derivación | 0,88 m/s² con verdad 1,0 | Núcleo a media altura + pendiente por mínimos cuadrados de la velocidad medida |
| 11 | El motor no estaba conectado a ninguna aplicación (solo fuentes de envoltorio) | — | Integración Android y Windows (ver abajo) |

## Matriz implementado / probado / integrado / validado físicamente
| Módulo | Implementado | Probado (simulación) | Integrado Android | Integrado Windows | Validado físicamente |
|---|---|---|---|---|---|
| Ingesta RAW / validación | sí | sí (+ fichero real del firmware) | sí | sí | **no** |
| Sincronización sin PPS | sí | sí | sí (dentro del motor) | sí | **no** (sin PPS, sesgo ≈ 5 ms) |
| GNSS, aceleración, curvas | sí | sí | sí | sí | **no** |
| Cadencia y regularidad | sí | sí (7 escenarios difíciles) | sí | sí | **no** (no hay cincha) |
| Aires V1 / V2 | sí | sí (sintético etiquetado) | sí | sí | **no** |
| Fusión OFFLINE / REALTIME | sí | sí (causalidad comprobada) | OFFLINE | OFFLINE | **no** |
| Rendimiento por aire, eventos | sí | sí | sí | sí | **no** |
| Simetría exploratoria | sí | sí | sí | sí (resumen) | **no** |
| Comparación de sesiones | sí | sí | sí | sí | **no** |
| Persistencia | sí | sí | sí | sí | — |
| JNI / P/Invoke | sí | JVM anfitriona + emulador (CI) / autopruebas Windows (CI) | — | — | **no probado en un teléfono real** |

## Bloqueos que requieren hardware
- No existe todavía la cincha con tres IMU ni se conoce el modelo de sensor, su rango, calibración ni orientación de montaje.
- No hay PPS: la alineación absoluta cincha↔GNSS tiene un sesgo de la latencia mínima del enlace.
- No hay sesiones reales etiquetadas por aire: no se puede entrenar ni validar ningún clasificador.
