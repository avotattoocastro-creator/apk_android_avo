# Algoritmo: mapa de relojes (cincha → pecho → GNSS)
**Versión:** 1.0.0-dev1 · **Código:** `src/synchronization` · **Pruebas:** `tests/test_sync.cpp`
**Objetivo:** convertir marcas de tiempo de un reloj de sensor a otro sin PPS.
**Matemática:** para cada par (t_emisor, t_llegada) la diferencia d = t_llegada − t_emisor = offset + deriva·t + latencia ≥ offset + deriva·t.
Se ajusta la **envolvente inferior** (recta por debajo de todos los puntos, mínimos por cubetas + mínimos cuadrados de esos mínimos).
Los reinicios del emisor (saltos hacia atrás) cortan el mapa en piezas; no se interpola entre piezas.
**Entradas:** pares de tiempos en µs. **Salida:** piezas {offset, deriva ppm, latencia mínima, residuo}.
**Parámetros:** tamaño de cubeta 1 s; mínimo 20 puntos por pieza.
**Resultados (sintéticos, deriva 50 ppm, latencia 2–15 ms):** deriva estimada 49,9 ppm; error del mapa 0,029 ms.
**Limitación principal:** sin PPS, el desfase absoluto queda sesgado por la **latencia mínima** del enlace (medido ≈5 ms entre cincha y GNSS en simulación). Las métricas relativas (cadencia, regularidad) no se ven afectadas; la alineación absoluta evento-posición sí (≈5 ms ≈ 2 cm a 4 m/s).
