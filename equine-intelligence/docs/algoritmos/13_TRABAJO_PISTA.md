# 13 · AVO Track Work 1.0.0 — entrenamientos de caballos de carreras (perfiles PSI y árabe)

**Objetivo: analizar los ENTRENAMIENTOS (trabajo en pista), no las carreras.** El código interno se llama `racing`.

Código: `include/avo_eq/racing.h`, `src/racing/racing.cpp`. Pruebas: `tests/test_racing.cpp` (suite `pista`, 7 casos).
Bloque `trabajo_pista` del JSON `avo-equine-analysis`. Opciones de `avo_eq_analyse_ex`:
- `raza`: `GENERICO` (por defecto), `PSI` o `ARABE`;
- `parcial_m`: 200 por defecto (201.168 = furlong);
- `signo_mano`: 0 = autocalibrar, 1 o −1.

**Todo es exploratorio y NO VERIFICADO con caballos reales.** Los perfiles de raza son valores de partida.

## Perfiles de raza
| | GENERICO | PSI | ARABE |
|---|---|---|---|
| Galope de trabajo desde | 9 m/s | 11 m/s | 10 m/s |
| Trabajo RÁPIDO si la máxima llega a | 12 m/s | 14,5 m/s | 13 m/s |
| Alta velocidad (carga) | 11 m/s | 15 m/s | 13,5 m/s |
| Velocidades de referencia de la zancada | 10 y 12 m/s | 14 y 16 m/s | 13 y 15 m/s |
| Frecuencia de zancada plausible | 1,5–3,0 Hz | 1,6–2,9 Hz | 1,6–3,0 Hz |
| Longitud de zancada plausible | 2,5–9 m | 3–9 m | 3–8,5 m |

## A. Cincha en el marco del caballo (`IMU_HORSE_FRAME_V1`)
- **Escala:**
  - con la cincha GIRTH ≥ 0.4.3 (byte 15 de la cabecera = 1) se usan las unidades del BNO085: aceleración Q8 m/s² y giro Q9 rad/s;
  - si no, la aceleración se escala con la mediana de |a| (= 1 g) y el giro con la escala nominal del LSM6 (70 mdps/LSB). Queda avisado.
  - El motor guarda `Session::imu_units` y cuenta los lotes fusionados (formato 1), que todavía no se usan.
- **Vertical:** paso bajo de 0,25 Hz de la aceleración (gravedad). Aceleración dinámica = a − gravedad.
  - Vertical dinámica: proyección sobre la vertical.
  - **VeDBA:** |a dinámica|.
- **Eje de avance:** dirección principal (PCA) de la aceleración horizontal dinámica mientras el caballo se mueve. El eje lateral es vertical × avance.
- **Sentido del avance:** una aceleración sostenida inclina la gravedad estimada hacia el movimiento. Su componente sobre el eje se correlaciona con la aceleración longitudinal del GNSS; con |r| > 0,3 queda confirmado.
- **Giro sobre la vertical:** ω·vertical, suavizado a 1 Hz (+ = izquierda). No depende del eje de avance.
  - Se da el tiempo y los grados girando a cada mano (|giro| ≥ 4 °/s), total y por aire, y el índice de equilibrio (izquierda − derecha) / total.
- **Carga de la cincha:** VeDBA medio en movimiento, por aire, y la carga ∫VeDBA dt (g·min).
- **Saturación:** muestras en el límite del rango (±8 g).

## B. Zancadas en galope (`STRIDE_V1`)
1. En cada tramo de GALOPE de al menos 3 s se busca la frecuencia fundamental de la vertical dinámica, dentro del rango de la raza.
2. Se filtra con paso bajo a 1,6·f0. Cada zancada va de pico a pico, y solo se aceptan duraciones entre 0,6/f0 y 1,5/f0.
3. Por zancada se calcula:
   - duración y frecuencia;
   - pico vertical (g);
   - **desplazamiento vertical del tronco**: doble integración dentro de la zancada, quitando la media y la tendencia; se da pico a pico;
   - VeDBA y giro medio;
   - **rasgo lateral**: correlación lateral/vertical, entre 0,5 y 8 Hz;
   - velocidad GNSS y **longitud** = velocidad × duración (anulada si sale del rango plausible).

## C. Mano de galope (`LEAD_V1`, EXPERIMENTAL)
- Galopar a una mano o a la otra es una imagen especular. La vertical no cambia y la lateral cambia de signo, así que el rasgo lateral cambia de signo con la mano.
- Qué signo es la izquierda se calibra así:
  - **CURVAS** (por defecto): en las zancadas en curva se espera la mano de dentro. Se elige el signo que más coincide; hace falta un acuerdo ≥ 65 % y al menos 12 zancadas.
  - **OPCION:** el signo que se guardó (`signo` del resultado) se pasa como `signo_mano`. Así se puede usar en sesiones sin curvas o con un caballo que galopa por fuera.
- Se suaviza por mayoría de 5 zancadas, y una mano tiene que durar al menos 3 zancadas. Se dan los cambios de mano (eventos `CAMBIO_DE_MANO`) y el porcentaje de mano de fuera en curva.
- **Límite:** con la autocalibración, un caballo que galopa siempre por fuera en las curvas sale «por dentro». La prueba `lead_sign_option` lo documenta.

## D. Trabajos del entrenamiento (`EFFORT_V1`, solo GNSS)
- Un trabajo es un tramo con velocidad ≥ v_trabajo, que admite bajadas de hasta 3 s y dura al menos 10 s. Es `TRABAJO_RAPIDO` si la máxima llega a v_rápido; si no, es `GALOPE_TRABAJO`.
- De cada trabajo se calcula:
  - distancia, duración y velocidad media;
  - **velocidad máxima** (media de 1 s) y tiempo hasta alcanzarla;
  - distancia por encima del 90 % de la máxima;
  - aceleración máxima;
  - **parciales** cada 200 m, o cada furlong;
  - **mejores** 200, 400, 600, 800, 1000, 1200 y 1600 m;
  - últimos 200 y 400 m;
  - **índice de caída** = (máxima − velocidad media de los últimos 200 m) / máxima. Solo si el trabajo mide 400 m o más.
- **Con cincha**, también:
  - frecuencia y longitud de zancada a la velocidad máxima (zancadas a ≥ 95 % de la máxima);
  - máximas (percentil 95);
  - rectas f = a + b·v y l = c + d·v;
  - **frecuencia y longitud a las velocidades de referencia**, solo dentro del rango medido. Es lo que permite comparar sesiones con trabajos distintos.
- Para toda la sesión: distancia de galope de trabajo, distancia rápida, máxima y mejor 200 m.

## F. Estructura del entrenamiento (`SESSION_PHASES_V1`)
- **Fases:**
  - **calentamiento:** desde el inicio hasta el primer trabajo;
  - **trabajo:** desde el primer trabajo hasta el último;
  - **vuelta a la calma:** desde el último trabajo hasta el final.
  - De cada fase se dan la duración, la distancia y el tiempo parado, al paso, al trote y al galope.
- **Por trabajo:**
  - **recuperación hasta el paso:** tiempo desde el final hasta bajar de 2,2 m/s y mantenerse 5 s;
  - **pausa hasta la siguiente repetición** y su velocidad media.
- **Series:**
  - repeticiones y repeticiones rápidas;
  - **caída de la velocidad máxima** y **de la longitud de zancada** entre la primera y la última repetición rápida;
  - recuperación media.
- **Calentamiento corto:** aviso si el primer trabajo rápido empieza antes de 10 min (`warmup_min_s`, valor de partida).

## E. Eventos de la cincha (EXPERIMENTAL)
- `IMPACTO_ATIPICO`: pico vertical de una zancada por encima de mediana + 6·MAD de la sesión y de 1,5 g. Puede ser un tropiezo o una mala pisada.
- `MOVIMIENTO_LATERAL_BRUSCO`: en ventanas de 1 s, pico lateral por encima de mediana + 6·MAD y de 1 g, junto con un giro de más de 30 °/s. Puede ser una espantada o un quiebro.
- `SATURACION`: episodios fuera de ±8 g.

## Historia de entrenamientos (ficha 12)
El resumen de sesión (`avo-training-session`) añade el bloque `trabajo_pista`, con `sesion` (calentamiento, vuelta a la calma, repeticiones, caídas, recuperación y calentamiento corto). La distancia a alta velocidad usa el umbral de la raza.

La historia incluye:
- **Carga VeDBA** con su propia ACWR (ACWR > 1,5 → VIGILAR).
- **Líneas base y tendencias** de:
  - `TRABAJO.f_v1_hz`, `l_v1_m`, `f_v2_hz` y `l_v2_m` (zancada a las velocidades de referencia);
  - `mano_de_fuera_curva_pct`;
  - `indice_caida_pct`, `v_max`, `mejor_200m_s`, `f_en_v_max_hz`, `l_en_v_max_m` y `desplazamiento_vertical_m`;
  - `CINCHA.vedba_galope_g`;
  - `TRABAJO.recuperacion_hasta_paso_s`, `TRABAJO.caida_entre_series_pct` y `TRABAJO.calentamiento_s` (informativas).
- **Métricas que suben el nivel:** la zancada a la velocidad de referencia (la longitud solo si baja) y la mano de fuera en curva (solo si sube). Las demás son informativas.
- Los impactos atípicos suben a VIGILAR.

## Validación
- Sesión sintética con física conocida:
  - trote, galope a 9 m/s, aceleración a 17 m/s, 30 s a 17 m/s, caída a 14,5 m/s y parada;
  - curva a la derecha de 60 m de radio y curva a la izquierda de 200 m;
  - mano derecha, izquierda y derecha;
  - cincha girada 170° y 35°, deriva del reloj de 40 ppm y latencia variable.
- Resultados:
  - máxima 17,04 m/s;
  - frecuencia a la máxima 2,451 Hz (real 2,43), longitud 6,95 m (real 7,0);
  - pendiente de la frecuencia 0,0396 (real 0,04);
  - mano 100 % en curvas y 2 cambios detectados de 2;
  - giros de 71° y 85° (reales 73° y 86°);
  - impacto inyectado detectado;
  - mañana de entrenamiento sintética (calentamiento de 4 min, 2 repeticiones a 16 y 15 m/s con paseo entre ellas y vuelta a la calma): repeticiones, caída del 6,24 % (real 6,25 %), recuperación de 6,5 s (real 6,1 s), fases y aviso de calentamiento corto;
  - cadena análisis → resumen → historia.
- **NO VERIFICADO** con caballos reales:
  - falta comprobar el rasgo de la mano con sesiones etiquetadas (vídeo), los rangos de zancada por raza y los umbrales de los eventos;
  - el eje de avance por PCA supone que la oscilación longitudinal del tronco domina la lateral.
