# AVO Equine Intelligence Engine (1.0.0-dev1)
Motor de análisis único en C++17 para Android (JNI), Windows (DLL, P/Invoke) y Python (ctypes).
- Compilar y probar: `cmake -S . -B build -DAVO_EQ_SANITIZE=ON && cmake --build build && ./build/avo_eq_tests`
- Banco científico: `python3 tools/scientific-bench/bench.py --lib build/libavo_equine.so`
- ML (infraestructura): `python3 ml/avo_ml.py demo --out /tmp/d.jsonl` (datos SINTÉTICOS)
- Integraciones: `integrations/android`, `integrations/windows`
- Algoritmos: `docs/algoritmos/` · Validación y límites: `docs/VALIDACION_Y_LIMITACIONES.md`
