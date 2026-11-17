# Algoritmo: Sensor Fusion Engine (GNSS del jinete + IMU de la cincha)
**Versión:** 1.1.0 · **Código:** `src/fusion/fusion.cpp`, `src/synchronization/session_sync.cpp` · **Pruebas:** `tests/test_fusion.cpp`
**No es fusión inercial**: GNSS (espalda del jinete) e IMU (cincha) no son un cuerpo rígido. La fusión es **temporal**:
cada ventana de la cincha (6 s, paso 2 s) se asocia al estado GNSS del mismo intervalo a través de los mapas de reloj sin PPS.
**Por ventana:** t GNSS ± σt (envolvente del mapa), velocidad media de las épocas utilizables de la ventana con
σv = √((σ_sAcc/√n)² + (|a|·σt)²), aceleración de trayectoria, fracción GNSS cubierta, interpolación controlada solo entre épocas a ≤ 0,3 s,
cadencia **solo si la ventana es VALIDA**, longitud de tranco L = v/f con σL = L·√((σv/v)² + (σf/f)²), métricas de regularidad,
aire y trazabilidad (índices de épocas usadas, índice de ventana). Estados: OK, SIN_SINCRONIA (σt > 20 ms o sin mapa), HUECO_GNSS, SIN_CADENCIA.
**Relaciones:** cadencia–velocidad y tranco–velocidad por mínimos cuadrados ponderados (σ escalada por χ² reducido) y Spearman;
regularidad–velocidad solo por rangos (sin modelo), por aire y global.
**Modos:** `OFFLINE_ANALYSIS` (sesión completa, filtros de fase cero sobre la pieza, derivadas bilaterales).
`REALTIME_ANALYSIS`: cada resultado usa **solo lo recibido por el pecho hasta su instante**: mapas de reloj reajustados con pares recibidos
(cada ≤ 1,5 s), filtrado por ventana, GNSS recibido, pendiente unilateral de 1 s. **Comprobado** quitando todos los datos posteriores a un
corte: las 20 ventanas anteriores al corte son idénticas (`fusion.realtime_is_causal_truncation_invariant`).
**Resultados (simulación):** tranco al paso error máx 0,014 m; cadencia = 0,578 + 0,254·v (r 0,98) con paso→trote.
**Limitaciones:** sin PPS el sesgo absoluto (latencia mínima, ≈ 5 ms) no entra en σt; el modo tiempo real reprocesado sobre una sesión larga es costoso (reajustes de mapa).
