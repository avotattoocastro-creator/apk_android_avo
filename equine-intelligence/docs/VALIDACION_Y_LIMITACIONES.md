# Validación y limitaciones — Equine Intelligence Engine 1.1.0-dev1

**Todos los resultados son de simulación o de ficheros de prueba.** No hay validación física con las tres IMU ni con referencias
topográficas o etiquetas de aire reales. Nada de lo que sigue es una precisión demostrada sobre caballos.

## Pruebas automatizadas
| Conjunto | Resultado |
|---|---|
| C++ con ASan/UBSan (Linux) y MSVC (Windows) | 61 casos, 938 comprobaciones, 0 fallos |
| Banco científico (cadencia, SNR ≥ 5 dB) | error máx 0,089 Hz, 0 sin resultado |
| Cadena RAW → motor → JSON (fixtures) | regenerados por CI y comparados (tolerancia relativa 1e-6) |
| Kotlin (`core`) | resultado v2 del motor; distancia igual a la del analizador anterior (±0,05 m) |
| JNI en JVM anfitriona | 10 comprobaciones: UTF-8, persistencia (CALCULADO → ACIERTO), cancelación, errores, comparación, RAW intacto |
| Android en emulador (CI) | `EquineEngineDeviceTest`: .so empaquetada, sesión completa, persistencia, cancelación |
| Windows (CI) | autopruebas: importación .avo → copia RAW verificada → DLL → modelo C#, sincronía con el recorrido, cancelación, comparación |

## Resultados de simulación destacados
| Prueba | Resultado |
|---|---|
| Aceleración sostenida 1,0 m/s² / frenada −1,5 m/s² | 1,00 / −1,49 m/s² |
| Falsos eventos con ruido 0,10 m/s (10 × 60 s) | 0 |
| Curvas R 20 m y 30 m | 20,0 ± 0,5 m y 30,0 ± 0,9 m; giro 178° / −87° |
| Cadencia con 2.º armónico dominante | 0 ventanas erróneas (antes 28/28) |
| Ruido por encima de la señal | 0 ventanas válidas erróneas |
| Tranco al paso (1,5 m/s, 0,95 Hz) | error máx 0,014 m |
| Tiempo real | idéntico al quitar los datos posteriores (20/20 ventanas) |
| Simetría: asimetría temporal −0,10 / retardo entre sensores 20 ms | −0,101 / 20,1 ms |
| Mismo recorrido a 3,0 y 3,3 m/s | Δv 0,302 m/s, Δt −4,95 s |
| Aires en sesión sintética etiquetada | V1 0,902 · V2 0,967 (sintético; sin superioridad declarada) |
| Sesión de 30 min, 3 IMU a 100 Hz | 2,4 s en Release |

## Limitaciones conocidas
1. Sin PPS: sesgo absoluto ≈ latencia mínima del enlace (≈ 5 ms en simulación, ≈ 2 cm a 4 m/s); no se incluye en σt.
2. IMU sin calibrar y con orientación desconocida: amplitudes en LSB; vertical solo estimada por la gravedad; entre sensores solo tiempos.
3. Umbrales de aires, eventos y curvas iniciales; V2 usa una hipótesis armónica pendiente de confirmar con sensores en la cincha.
4. Simetría y regularidad son descriptores de la señal: **no constituyen diagnóstico veterinario ni de cojera**. Anomalías exploratorias.
5. El modo tiempo real reprocesado sobre sesiones largas es costoso (reajuste de mapas); la app usa el modo offline.
6. La app Android no se ha probado en un teléfono físico con el motor; la app Windows no se ha abierto en un equipo real (solo CI).
7. ML: infraestructura sin modelo entrenado; las cifras de la demo sintética no son exactitud real.
