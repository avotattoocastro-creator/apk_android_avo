# Algoritmo: motor de aceleración avanzada
**Versión:** 1.1.0 · **Código:** `src/gnss/gnss.cpp`, `src/gnss/kinematics.cpp` · **Pruebas:** `tests/test_kinematics.cpp`
**Fuente:** únicamente la **trayectoria GNSS** (antena en la espalda del jinete), etiqueta `TRAYECTORIA_GNSS`.
La aceleración de las IMU de la cincha (sin calibrar, otro cuerpo) **no se mezcla ni se presenta como equivalente**.

**Longitudinal.** Pendiente de mínimos cuadrados ponderados (peso 1/sAcc²) de la velocidad del receptor en ±0,5 s;
exige puntos a ambos lados (no extrapola) y ≥ 3 épocas. σ = √(Σw / det). Épocas con |a| > 15 m/s² se descartan como artefactos.

**Lateral estimada.** ω = (vN·dvE/dt − vE·dvN/dt) / v² ; a_lat = v·ω ; κ = ω / v.
Propagación de primer orden: σω = √(vN²σE² + vE²σN²)/v², σa_lat = √((ω σv)² + (v σω)²), σκ = √((σω/v)² + (ω σv/v²)²).
Solo con v ≥ 2 m/s.

**Eventos sostenidos.** Histéresis (entra con a ≥ 0,4 m/s² y a − σ > 0, sale con a < 0,2), huecos ≤ 0,4 s tolerados.
La ventana de derivación difumina los bordes: el evento se recorta a su **núcleo a media altura del pico** y su valor
medio es la **pendiente por mínimos cuadrados de la velocidad medida** en ese núcleo (no la media de pendientes); duración mínima 1,5 s.

**Picos.** Máximos locales con |a| ≥ 1 m/s² (lateral ≥ 2 m/s²) **y** |a| > 3σ, separados ≥ 1 s.

**Resultados (simulación):** rampa 2→6 m/s en 4 s: 1,00 m/s² (verdad 1,0), Δv 3,7 m/s; frenada 6→3 m/s en 2 s: −1,49 m/s² (verdad −1,5);
0 eventos falsos en 10 sesiones de 60 s con ruido de velocidad 0,10 m/s; con 25 % de épocas perdidas sigue detectando la aceleración;
curvatura en círculo R = 20 m: error máx 0,0027 1/m; a_lat error máx 0,037 m/s² (0,7 σ).
**Limitaciones:** cinemática del jinete; sin validación con referencia física.
