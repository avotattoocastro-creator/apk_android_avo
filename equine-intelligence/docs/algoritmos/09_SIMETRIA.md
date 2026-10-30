# Algoritmo: Symmetry Analysis Engine — EXPLORATORY_MOTION_SYMMETRY
**Versión:** 1.1.0 · **Código:** `src/imu/symmetry.cpp` · **Pruebas:** `tests/test_symmetry.cpp`
Describe **diferencias de la señal de la cincha**, no el estado del caballo. Sin vocabulario clínico (comprobado por prueba).
**Por ventana válida** (cadencia VALIDA, correlación entre ciclos ≥ 0,8, saturación ≤ 0,5 %, sin muestras interpoladas):
segmentación en trancos (picos a un periodo); segundo apoyo = máximo entre el 25 % y el 75 % del tranco;
- amplitud: ln(A1/A2) con amplitudes pico–valle (independientes de la línea base del filtro);
- temporal: (d1 − d2)/(d1 + d2);
- similitud de mitades: correlación de ambas mitades remuestreadas;
- energía: fracción en el eje alineado con la gravedad media (**vertical estimada**) y cociente de los otros dos (ejes horizontales sin identificar);
- entre sensores (IMU 1 y 2): retardo por correlación cruzada (y fracción de ciclo); amplitudes entre sensores **bloqueadas sin calibración**.
**Agregación** por IMU y aire: mediana, IQR, consistencia de signo; «reproducible» solo con ≥ 5 ventanas, ≥ 80 % del mismo signo y
|mediana| > 2·(IQR/1,349)/√n.
**Controles que bloquean o avisan:** CALIBRACION, ORIENTACION, SATURACION, MOVIMIENTO_IRREGULAR, TIEMPO_ENTRE_SENSORES (σt > 10 ms).
**Resultados (simulación):** ln(A1/A2) 0,428 frente a 0,357 real (sesgo del paso banda sobre pulsos: es un descriptor de la señal, no una
amplitud física); asimetría temporal −0,101 (real −0,100); retardo entre sensores 20,1 ms (real 20 ms); saturación e irregularidad bloquean.
**Limitaciones:** sin IMU reales, sin calibración ni orientación conocidas.
