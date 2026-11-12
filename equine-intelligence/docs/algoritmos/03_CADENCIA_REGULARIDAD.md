# Algoritmo: cadencia y regularidad (IMU de la cincha)
**Versión:** 1.1.0 · **Código:** `src/imu/motion.cpp`, `src/dsp` · **Pruebas:** `tests/test_motion.cpp`, `tests/test_cadence.cpp`, `tools/scientific-bench`
**Objetivo:** frecuencia de ciclo de tranco y regularidad por ventanas de 6 s (paso 2 s).
**Matemática:** paso banda Butterworth 0,4–10 Hz de fase cero; autocorrelación **insesgada** (r(k)·N/(N−k)) suavizada; primer máximo
≥ 0,9 del mayor dentro de [0,6; 3,5] Hz con refinado parabólico; criterio relativo de subarmónico: se elige el retardo doble si
explica al menos la mitad de lo que el simple deja sin explicar (independiente de la escala y robusto al ruido).
**No se supone que la frecuencia dominante sea la cadencia**: se informa `dominante_hz` y el armónico que domina.
**Incertidumbre:** σf = √((σT/T²)² + (f²·¼/fs)²), σT = desviación de las duraciones de ciclo / √n.
**Estados:** VALIDA (única con cifra), PERIODICIDAD_DEBIL, AMBIGUA (autocorrelación e intervalos discrepan > max(3σ, 10 %) o potencia
en f/2 > 5× el suelo de ruido sin subarmónico elegido), INCIERTA (σf/f > 8 %), DATOS_INSUFICIENTES (pocos ciclos o > 10 % interpolado).
**Interpolación controlada:** huecos ≤ 0,25 s se rellenan linealmente en una copia derivada (nunca en el RAW) y se registra la fracción.
**Regularidad (métricas independientes, sin puntuación combinada):** CV de intervalos (temporal), CV de altura de pico (amplitud),
correlación de cada ciclo con la plantilla (similitud), correlación de los espectros de las dos mitades (estabilidad espectral).
**Rasgos espectrales:** potencia en k·f0 (k = 1…4), fracción armónica, energía por bandas 0,4–1,5 / 1,5–3 / 3–6 / 6–10 Hz, energía por eje.
**Pruebas (simulación):** frecuencia variable 0,9→1,5 Hz: 40/43 ventanas válidas, 0 fuera de 3σ; ruido por encima de la señal: 131/140
válidas y 0 erróneas; 2.º armónico dominante: 26 válidas, 26 con el pico espectral en 2·f0, 0 erróneas; 8 % de lotes perdidos: 23 válidas,
0 erróneas; cambio de aire dentro de la ventana: ninguna mezcla válida errónea; ruido sin periodicidad: 0 válidas; 50/100/200/400 Hz: 0 erróneas.
Banco: SNR ≥ 5 dB error máx 0,089 Hz.
**Limitaciones:** sin datos reales de cincha; amplitudes en LSB sin calibrar; **no es diagnóstico clínico ni de cojera**.
