# Algoritmo: análisis de curvas
**Versión:** 1.1.0 · **Código:** `src/gnss/kinematics.cpp` (`analyse_curves`, `fit_circle`) · **Pruebas:** `tests/test_kinematics.cpp`
**Detección:** épocas válidas = calidad ≥ UTILIZABLE, v ≥ 2 m/s, |κ| > 2σκ y radio ≥ 3 m. Entra con radio < 40 m y sale con
radio > 60 m o cambio de sentido (histéresis); huecos ≤ 0,6 s tolerados. Se acepta con duración ≥ 2 s, giro ≥ 30° y ≥ 50 % de épocas válidas.
**Por curva:** dirección, giro (∫ω dt), radio cinemático = mediana de 1/|κ| con dispersión 1,4826·MAD, radio geométrico y centro
por ajuste de círculo de Kåsa (si giro ≥ 45° y residuo < 20 % del radio), velocidades de entrada/salida/media/mínima,
aceleración lateral estimada media/máxima con incertidumbre, distancia y, con cincha, cadencia antes/durante/después y correlación entre ciclos.
**Comparación entre sesiones:** curvas con la misma dirección cuyos centros distan menos de la mitad del radio.
**Resultados (simulación):** recorrido con giro derecho R = 20 m (180°) y giro izquierdo R = 30 m (90°): 178° R 20,0 ± 0,5 m (geom. 20,0) y −87° R 30,0 ± 0,9 m;
sin curvas falsas a 1 m/s ni en 10 rectas con ruido.
**Limitaciones:** con FLOAT/sin RTK el ruido de rumbo aumenta y la curva se descarta; radios muy grandes se tratan como recta.
