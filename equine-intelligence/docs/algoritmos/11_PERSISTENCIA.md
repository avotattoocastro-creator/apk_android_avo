# Persistencia de resultados derivados
**Versión:** 1.1.0 · **Código:** `src/core/store.cpp` · **Pruebas:** `tests/test_capi_store.cpp`, prueba JNI, autopruebas Windows
- Los RAW solo se leen (huella FNV-1a 64 de tamaño + contenido de cada segmento). Comprobado que no cambian.
- Un fichero por (huella de entrada, hash de parámetros): `analisis_<huella>_<parámetros>.json`, escritura atómica (tmp + rename). Sin duplicados.
- Se reutiliza (ACIERTO) solo si coinciden versión del motor, versión de **cada** algoritmo, huella y parámetros; si no, se recalcula
  y reemplaza (RECALCULADO). `forzar` recalcula. `avo_eq_cache_invalidate` borra análisis de otras versiones.
- Cada resultado guarda: id de sesión, motor, algoritmos con versión, hash de parámetros y parámetros principales, fecha de
  procesado, modo, resultados, calidad, referencias temporales (`itow_inicial_ms`, unidades) y advertencias.
- Android: `files/equine/<sesión>/` (fuera de la carpeta de los RAW). Windows: `%LOCALAPPDATA%\AVO Performance Horse\Windows\analisis\<sesión>`.
