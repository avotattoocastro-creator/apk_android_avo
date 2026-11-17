# Algoritmo: análisis GNSS / RTK
**Versión:** 1.0.0-dev1 · **Código:** `src/gnss` · **Pruebas:** `tests/test_gnss.cpp`
**Objetivo:** velocidad, distancia y calidad RTK por época, sin inventar datos.
**Matemática:** posición ENU local; velocidad por pendiente de mínimos cuadrados ponderados (peso 1/sAcc²) en ventana bilateral; distancia sumando solo tramos con calidad suficiente.
**Entradas:** épocas UBX (lat/lon/alt, fixType, carrSoln, hAcc, sAcc, edad de corrección). **Unidades:** m, m/s, s.
**Banderas:** salto temporal, época duplicada, precisión insuficiente, sin FIX, corrección vieja (ver `validation.h`).
**Estados RTK:** NONE / FLOAT / FIXED, con porcentaje y tiempo hasta FIX.
**Limitaciones:** ZED-F9P a 8 Hz con 4 constelaciones; la velocidad en FLOAT se marca como calidad reducida; sin validación física frente a referencia.

## 2.0.0 (AVO Performance Equine) · F1 «una sola verdad cinemática»
- **Velocidad:** Kalman v-a + suavizado RTS sobre gSpeed (`src/gnss/smoother.cpp`, `avo_eq/smoother.h`).
  - Es el mismo modelo y los mismos valores por defecto que usaban las apps: sacudida 1 m²/s⁵, σv mínima 0,05 m/s,
    σv sin sAcc 0,15 m/s y σa inicial 2 m/s².
  - El filtro se reinicia en cada hueco o época no válida: no puentea datos.
- **Uso:** `GnssResult.speed` y `speed_sigma` son ahora la velocidad suavizada y su σ posterior. De ahí salen la velocidad
  máxima, el histograma de velocidades, la velocidad en curva, los umbrales y las distancias de trabajo de Trabajo en pista,
  las mejores distancias, los aires y la fusión.
- **Lo que no cambia:**
  - gSpeed se conserva en `speed_raw` / `speed_raw_sigma` y en la serie `velocidad_receptor`;
  - la aceleración sigue siendo la pendiente ponderada sobre gSpeed (hasta el paso siguiente de F1);
  - la distancia sigue siendo la haversine entre posiciones RTK.
- **Modo 1.x:** `GnssConfig.smooth_speed = false` devuelve el comportamiento anterior, para comparar.
- **Banco** (`gnss2.*`, simulación): galope constante de 14 m/s con ruido σ 0,3 m/s.
  - RMS: 0,310 m/s con gSpeed y 0,081 m/s con la suavizada.
  - Velocidad máxima: 14,91 m/s con gSpeed (inflada por el ruido) y 14,22 m/s con el motor 2.0.

### F1b
- **Aceleración longitudinal:** es el estado del mismo filtro Kalman v-a + RTS, con su σ (`GnssConfig.accel_from_smoother`;
  con `false` vuelve la pendiente ±0,5 s).
- **Series:** el motor exporta `sigma_velocidad` y `sigma_aceleracion` del filtro.
- **Apps:** iPad (`SessionTimeline.adoptEngineKinematics`) y Windows (`AdoptEngineKinematics`) adoptan la velocidad y la
  aceleración del motor, interpoladas entre muestras del motor separadas como mucho 0,5 s.
  - Solo lo hacen si el motor cubre más de la mitad de la línea de tiempo y la app usa la sacudida por defecto (1 m²/s⁵).
  - Barra, gráficas, Datos clave, Cuadra e informes muestran así las mismas cifras que el motor.
  - Android no tenía filtro propio: sus gráficas del motor reciben ya la serie suavizada.
