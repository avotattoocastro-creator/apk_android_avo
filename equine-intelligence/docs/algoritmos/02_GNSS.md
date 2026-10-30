# Algoritmo: análisis GNSS / RTK
**Versión:** 1.0.0-dev1 · **Código:** `src/gnss` · **Pruebas:** `tests/test_gnss.cpp`
**Objetivo:** velocidad, distancia y calidad RTK por época, sin inventar datos.
**Matemática:** posición ENU local; velocidad por pendiente de mínimos cuadrados ponderados (peso 1/sAcc²) en ventana bilateral; distancia sumando solo tramos con calidad suficiente.
**Entradas:** épocas UBX (lat/lon/alt, fixType, carrSoln, hAcc, sAcc, edad de corrección). **Unidades:** m, m/s, s.
**Banderas:** salto temporal, época duplicada, precisión insuficiente, sin FIX, corrección vieja (ver `validation.h`).
**Estados RTK:** NONE / FLOAT / FIXED, con porcentaje y tiempo hasta FIX.
**Limitaciones:** ZED-F9P a 8 Hz con 4 constelaciones; la velocidad en FLOAT se marca como calidad reducida; sin validación física frente a referencia.
