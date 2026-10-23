# Validación y limitaciones — Equine Intelligence Engine 1.0.0-dev1

## Qué está validado (solo simulación)
| Prueba | Resultado |
|---|---|
| Pruebas unitarias C++ (ASan/UBSan) | 23 casos, 671 comprobaciones, 0 fallos |
| Mapa de relojes, deriva 50 ppm | deriva 49,9 ppm, error 0,029 ms |
| Cadencia, SNR ≥ 5 dB | error máx 0,088 Hz, 0 sin resultado |
| Ingesta AVO RAW v1 | reutiliza el lector de `avo_core` del firmware (mismo formato) |

## Qué NO está validado
- **Ninguna prueba física.** No hay sesiones reales con IMU: la cincha no existe en el hardware actual y el modelo de IMU es desconocido (bloqueado por inventario de hardware).
- Precisión GNSS frente a una referencia topográfica.
- Clasificación de aires con caballos reales; no hay modelo entrenado.

## Limitaciones conocidas
1. Sin PPS: alineación absoluta cincha↔GNSS con sesgo ≈ latencia mínima (≈5 ms en simulación).
2. Las métricas de simetría/regularidad son descriptivas; **no constituyen diagnóstico veterinario ni de cojera**.
3. Anomalías marcadas como **exploratorias**.
4. Fusión GNSS+IMU, rendimiento por aire y comparación de sesiones: pendientes.
