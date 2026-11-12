# Algoritmos: Gait Performance Engine y Event Detection Engine
**Versión:** 1.1.0 · **Código:** `src/core/performance.cpp` · **Pruebas:** `tests/test_capi_store.cpp`, `tests/test_gait_v2.cpp`, fixtures
**Rendimiento por aire.** Segmenta según el clasificador elegido (V1 por defecto, V2 opcional) **sin forzar aires**:
DESCONOCIDO, TRANSICION y DATOS_INSUFICIENTES se conservan; un tramo con < 50 % de GNSS utilizable y sin cincha válida pasa a
DATOS_INSUFICIENTES. Por tramo: duración, distancia (sin puentear huecos), velocidad media (ponderada en tiempo) y máxima,
aceleración/desaceleración máx (σ ≤ 0,8), cadencia media con σ (entre ventanas + dentro), CV de cadencia, CV de intervalos,
CV de amplitud, correlación entre ciclos, estabilidad espectral, tranco, fracción FIX/GNSS útil/IMU válida, calidad GNSS, IMU y de clasificación.
Agregados por aire y de sesión; la evolución temporal está en `series` / `series_cincha` (misma base de tiempo).
**Eventos.** Tipos: INICIO_MOVIMIENTO, PARADA (histéresis 0,6/0,3 m/s con 2 s de confirmación), ACELERACION/DESACELERACION_SOSTENIDA,
INICIO/FIN_CURVA, TRANSICION_AIRE (A → [transición] → B), CAMBIO_BRUSCO_CADENCIA (> max(0,15 Hz, 3σ) entre ventanas consecutivas),
PERDIDA_REGULARIDAD (correlación entre ciclos > 3 desviaciones robustas bajo la mediana), PERDIDA_CALIDAD_GNSS (FIX perdido ≥ 1 s o
hueco de épocas), PERDIDA_SINCRONIZACION (hueco de cincha ≥ 1 s mientras sigue el GNSS, o reinicio de reloj).
Cada evento: id `EV0001…`, tipo, inicio, fin, datos usados, calidad, motivo, algoritmo y versión. Los del mismo tipo a ≤ 1 s se fusionan.
**Limitaciones:** umbrales iniciales sin validar con caballos reales.
