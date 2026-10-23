# Algoritmo: cadencia y regularidad (IMU)
**Versión:** 1.0.0-dev1 · **Código:** `src/imu/motion.cpp`, `src/dsp` · **Pruebas:** `tests/test_motion.cpp`, `tools/scientific-bench`
**Objetivo:** frecuencia de ciclo de tranco y regularidad por ventanas de 6 s.
**Matemática:** filtro paso banda Butterworth 0,5–8 Hz de fase cero (filtfilt); autocorrelación normalizada suavizada; máximo dentro de [fmin, fmax] con refinado parabólico y comprobación de subarmónico (detecta ciclo completo frente a medio ciclo).
Regularidad: CV de intervalos entre picos, CV de amplitudes, correlación media entre ciclos consecutivos, relación medio ciclo.
**Entradas:** IMU 9 ejes uniformemente muestreada; huecos cortan la serie (no se interpola).
**Banco (sintético, 10 semillas):** SNR ≥ 5 dB error máx 0,088 Hz, sin fallos; a 0 dB degrada (se informa).
**Limitaciones:** **sin datos reales**: la cincha y el modelo de IMU no existen todavía en el hardware actual. Sin calibración de orientación del sensor. Las métricas de regularidad son descriptivas; **no son diagnóstico de cojera ni clínico**.
