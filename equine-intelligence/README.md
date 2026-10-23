# AVO Equine Intelligence Engine (1.1.0-dev1)
Motor de análisis único en C++17 para Android (JNI), Windows (DLL, P/Invoke) y Python (ctypes), integrado en las dos aplicaciones.

| Módulo | Código | Ficha |
|---|---|---|
| Ingesta AVO RAW v1 (lector del firmware), validación | `src/ingestion`, `src/validation` | 01, 02 |
| Sincronización de relojes sin PPS | `src/synchronization` | 01 |
| GNSS, aceleración avanzada, curvas | `src/gnss` | 02, 05, 06 |
| Cadencia, regularidad, rasgos espectrales | `src/imu/motion.cpp` | 03 |
| Aires GAIT_CLASSIFIER_V1 / V2 + modelo entrenado | `src/imu/gait_v1.cpp`, `gait_v2.cpp` | 04 |
| Fusión GNSS + IMU (OFFLINE / REALTIME) | `src/fusion` | 07 |
| Rendimiento por aire y eventos | `src/core/performance.cpp` | 08 |
| Simetría exploratoria | `src/imu/symmetry.cpp` | 09 |
| Comparación de sesiones | `src/core/compare.cpp` | 10 |
| Persistencia de resultados | `src/core/store.cpp` | 11 |
| API C v2, JSON v2 | `src/capi`, `src/core/engine.cpp` | `docs/FORMATO_RESULTADOS.md` |

## Compilar y probar
```
cmake -S . -B build -DAVO_EQ_SANITIZE=ON && cmake --build build && ./build/avo_eq_tests     # 61 casos
python3 tools/scientific-bench/bench.py --lib build/libavo_equine.so                           # banco científico
python3 tools/fixtures/check_fixtures.py build/avo_eq_cli                                      # cadena RAW -> JSON de Kotlin/Android/Windows
build/avo_eq_cli SESION.avr --out salida --series                                              # analizar una sesión
```
## Integraciones
- **Android** (`app/`): `engine/AvoEquine.kt` (JNI, UTF-8, cancelación), `engine/EquineEngine.kt` (flujo real: descarga → análisis en
  segundo plano → resultados guardados en `files/equine/<sesión>` → pantalla), pestaña **Motor** y gráficas sincronizadas en
  `TrainingDetailScreen`, comparación avanzada en `CompareScreen`. NDK: arm64-v8a, armeabi-v7a, x86_64. Modelo Kotlin: `core/.../engine/EquineResult.kt`.
- **Windows** (`windows/`): `AVO.Windows.Core/EquineEngine.cs` (P/Invoke + modelo), pestaña **Motor AVO** en la aplicación WPF existente
  (gráficas con la selección del recorrido, intervalos, aires, curvas, eventos, calidad, comparación, exportación JSON/CSV, reprocesado).
- **Pruebas de cadena:** `integrations/android/host-test` (JNI en JVM), `app/src/androidTest` (emulador), `windows/AVO.Windows.SelfTest`.

Validación y límites: `docs/VALIDACION_Y_LIMITACIONES.md` · Auditoría: `docs/AUDITORIA_CONTINUIDAD_1_1_0.md`.
**Todos los resultados numéricos proceden de simulación; no hay validación física con las tres IMU.**
