# Algoritmo: clasificación de aires (GAIT_CLASSIFIER_V1 y GAIT_CLASSIFIER_V2)
**Código:** `src/imu/gait_v1.cpp`, `src/imu/gait_v2.cpp`, `ml/avo_ml.py` · **Pruebas:** `tests/test_motion.cpp`, `tests/test_gait_v2.cpp`
**V1 (1.0.1, referencia, reglas sin cambios):** velocidad GNSS + frecuencia de ciclo con histéresis y duración mínima. Desde 1.1.0 solo recibe cadencias VALIDAS y busca la velocidad por búsqueda binaria.
**V2 (2.0.0):** pertenencias trapezoidales configurables por clase para velocidad, frecuencia y P(2f0)/P(f0) (hipótesis: dos oscilaciones
verticales del tronco por tranco al paso y al trote, una al galope; pendiente de confirmar con sensores en la cincha). Puntuación = media
geométrica ponderada con suelo 0,05 (un rasgo discrepante penaliza, no veta). Clase solo si puntuación ≥ 0,5 y margen ≥ 0,15; si no,
DESCONOCIDO; sin velocidad ni cadencia válida, DATOS_INSUFICIENTES; histéresis de 2 puntos fechada en el primer punto que la sostiene
(análisis offline); tramos < 4 s → TRANSICION. Admite un **modelo entrenado** (`load_centroid_model`, formato de `ml/avo_ml.py train`).
**Evaluación con los mismos datos:** `evaluate_gait` (confusión por tiempo, excluye transiciones y ±1 s de cada cambio).
En la sesión sintética etiquetada: V1 0,902, V2 0,967 (**sintético, no es exactitud real; no se declara V2 superior**).
Evidencias contradictorias → DESCONOCIDO en vez de forzar un aire.
**ML:** etiquetado (añadir, corregir, quitar intervalos con autor y fecha), dataset por caballo y sesión, evaluación dejando un caballo fuera
y por sesión. No se entrega ningún modelo entrenado: no hay datos reales etiquetados.
