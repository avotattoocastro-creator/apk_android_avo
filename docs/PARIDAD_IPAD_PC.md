# Paridad iPad ↔ PC (Windows)

**Regla del usuario (2026-11-13):** «El PC y el iPad tienen que ser idénticos variando el formato de iPad y de PC, pero los
datos, información y análisis tienen que tener la misma cantidad y calidad».

## Reglas
1. **Toda cifra sale del motor C++ (`MotorAVO Equine`, JSON `avo-equine-analysis`).** Swift y C# solo leen y dan formato,
   no calculan métricas propias.
2. **Las reglas de lectura son las mismas en las dos apps**: `ipad/AVOiPad/Core/KeyData.swift` ⇔
   `windows/AVO.Windows.Core/Analysis/KeyData.cs`. Si cambia una, cambia la otra en el mismo PR.
3. **Las pruebas usan el mismo JSON y los mismos valores esperados**: `ipad/AVOiPadTests/KeyDataTests.swift` ⇔
   `windows/AVO.Windows.SelfTest/KeyDataTests.cs`.
4. **Formato español** (coma decimal) y fechas en **Europe/Madrid**, con la semana empezando en lunes.
5. Lo que no tiene dato se muestra como «—» con el motivo; no se rellena con estimaciones.

## Datos clave (por sesión)
| Ficha | Origen en el JSON | Formato |
|---|---|---|
| V. máxima | `metricas.velocidad_maxima` × 3,6 | `0,0` km/h |
| Mejor 200 / 600 / 1000 m | mínimo `tiempo_s` en `trabajo_pista.trabajos.lista[].mejores` (±1 m); para 200 m, si no hay, `mejor_200m_s` | `0,00` s |
| Distancia | `metricas.distancia` / 1000 | `0,00` km |
| Duración | `metricas.duracion` | `m:ss` / `h:mm:ss` |
| FC máx., recuperación 2′ y 15′, FC final | ECG MAX30003 de la cincha REV 5.10 (aún no disponible) | «—» |
| Tranco máx. / frecuencia máx. | máximo `l_max_m` / `f_max_hz` de los trabajos | `0,00` m / Hz |
| Tranco / frecuencia a v. de referencia (×2) | mediana entre trabajos de `referencia[k].l_m` / `f_hz` (misma regla que `training.cpp`); velocidades en `trabajo_pista.perfil.v_referencia` | `0,00` m / Hz |
| Aires | `metricas.tiempo_<AIRE>` (PARADO, PASO, TROTE, GALOPE) y su porcentaje | `m:ss` · % |
| Calidad GNSS | aire dominante de `rtk.*_s`; % FIX = `fix_s / total_s` | etiqueta · % |

Las fichas se colocan en una rejilla de **6 columnas** («6 en línea»). En las fichas de **mejor 200/600/1000 m** guardamos
la ventana del motor (`mejores[].t0` + `tiempo_s`); al tocarlas se abre **Gráficas** con ese tramo seleccionado y ampliado.
El tiempo de la línea temporal es el tiempo del motor menos `engineOffsetS`.

## Parciales
- Salen de `trabajo_pista.trabajos.lista[].parciales`: tramo «desde–hasta m», tiempo `0,00` s y velocidad `0,0` km/h.
- La barra de cada parcial es proporcional a su velocidad respecto al parcial más rápido del trabajo, que se marca en rojo.
- La ventana de cada parcial empieza en el `t0` del trabajo más la suma de los parciales anteriores. Al tocarlo se abre en
  Gráficas.

## Navegador de sesiones
- Columna lateral (como el de Equimetre) con las sesiones agrupadas por día en Europe/Madrid, la más reciente arriba.
- Cabecera de cada día en el formato «SÁB 8 NOV 2025»; cada sesión se muestra como «HH:mm · caballo».
- Búsqueda por caballo que no distingue mayúsculas ni acentos. Se puede ocultar.

## Calendario
- Vistas de mes y de año. El mes se muestra en una cuadrícula de 6×7 que empieza en lunes. Al entrar por primera vez se
  abre el mes de la última sesión.
- Acumulados del periodo: número de sesiones, tiempo total, duración media, distancia y sesiones **con RTK FIX**
  (≥ 50 % del tiempo en FIX, contadas sobre las sesiones analizadas).
- Hay un filtro por caballo. Al tocar una sesión se abre su página de **Datos clave**.

## Matriz de paridad
| Función | iPad | PC |
|---|---|---|
| Calendario (mes/año, acumulados, filtro) | ✅ incremento 1 | ✅ incremento 1 |
| Datos clave | ✅ incremento 1 | ✅ incremento 1 |
| 6 por fila, tranco a v. de referencia, parciales, navegador, abrir en Gráficas | ✅ incremento 2 | ✅ incremento 2 |
| Eje de distancia en Gráficas (además del de tiempo) | pendiente | pendiente |
| Tabla de análisis con filtros | pendiente | pendiente |
| Comparar sesiones | existe | pendiente |
| Historia del caballo | existe | pendiente |
| Track Work / Carreras | existe | pendiente |
| Sesión de referencia y ficha de sesión | pendiente | pendiente |
