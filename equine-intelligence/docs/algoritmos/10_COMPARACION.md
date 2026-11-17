# Algoritmo: Session Comparison Engine
**Versión:** 1.1.0 · **Código:** `src/core/compare.cpp` · **Pruebas:** `tests/test_compare.cpp`
**Selecciones:** sesión, tiempo, distancia acumulada, posición (círculo), aire, evento. Estadísticas por selección.
**Comparabilidad explícita:** selecciones vacías, RTK FIX < 50 %, aire dominante distinto o velocidades > 15 % distintas marcan como
«no comparable» las métricas afectadas, con el motivo.
**Mismo recorrido:** la sesión B se proyecta sobre la polilínea de A (marco ENU de A, búsqueda global para el primer punto y local
después, que preserva el avance). Comparable si la separación lateral mediana ≤ tolerancia (3 m con RTK, 5 m si no), p90 ≤ 2×,
cobertura ≥ 80 % y avance monótono ≥ 90 %. Perfiles en una malla de 2 m de la distancia de A: velocidad A/B y diferencia de tiempo acumulada.
Nunca se compara por índice de muestra.
**Patrón (DTW):** forma del perfil de velocidad en 100 puntos de distancia propia, banda de Sakoe-Chiba 10 %; se etiqueta como
comparación **no espacial**. **Curvas equivalentes** por dirección y distancia entre centros.
**Resultados (simulación):** mismo recorrido a 3,0 y 3,3 m/s: Δv 0,302 m/s, Δt −4,95 s; desplazado 40 m: no comparable; paso frente a galope: cadencia no comparable.
