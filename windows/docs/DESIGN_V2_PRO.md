# AVO Performance Horse — Windows Advanced Analysis V2 PRO · diseño, arquitectura y validación

Rama `feature/windows-advanced-analysis`. Referencias visuales: `AVO_WINDOWS_CONCEPTO_01.png` y `AVO_WINDOWS_CONCEPTO_02.png`
(paquete `AVO_WINDOWS_REFERENCIAS_UI_V1.zip`). Paleta: `app/.../ui/theme/Theme.kt` (Android), **no** el azul marino de V1.

## Sistema visual
- `AVO.Windows/Themes/AvoColors.xaml`: todos los colores de `AvoColors` de Android (fondo #030406, superficies #101014/#1A1B20,
  línea #2A2B31, rojo AVO #ED122A / #B71625 / #FF495A, azul #3D9BFF, cian #35D0E8, plata #C9CBD1, texto #F2F2F4/#9C9DA4,
  estados #52DD40 / #FFC42C / #FF3945 / #93949B), degradado de tarjeta de Android, escala de velocidad de Android
  (azul #2F6BFF → cian → amarillo → rojo), tipografía e iconos vectoriales propios (sin fuentes de iconos externas).
- `AvoControls.xaml`: estilos de botones, pestañas, navegación lateral, casillas, ComboBox oscuro completo, barras de
  desplazamiento, deslizador de reproducción, tablas virtualizadas (AvoDataTable), listas (AvoSegmentSelector).
- Componentes (`Controls/`): AvoCard, AvoMetricTile, AvoStatusIndicator, AvoChartPanel, AvoMapToolbar, AvoLegendItem,
  AvoKeyValue, SessionHeader (AvoSessionHeader), SignalChart, Sparkline, MapControl, HorseDiagram.
- Rojo AVO = selección, navegación activa y acciones principales; azul/cian = datos científicos.

## Correspondencia con las referencias
| Referencia | Vista | Estado |
|---|---|---|
| C02-1 / C01-1 Inicio | `HomeView` | Héroe con la imagen de marca AVO de Android (no hay foto autorizada de jinete en playa), acciones, métricas, tabla filtrable, caballos, sensores, importaciones, estado del sistema |
| C02-2 Vista principal | `AnalysisView` | Panel de sesión y capas, mapa satélite/híbrido con leyenda, zoom y ajuste, reproducción con velocidad, 4 métricas con minigráfica |
| C01-2 Mapa | `MapView` | Capa base, coloreado por velocidad/aceleración/calidad GNSS/aire, estadísticas, leyenda, tramos, calidad RTK, punto seleccionado, perfil sincronizado |
| C02-3 / C01-3 Gráficas | `ChartsView` | Velocidad (filtrada, reportada, derivada), aceleración longitudinal/lateral, IMU cincha, cadencia, altitud, hAcc; cursor, zoom, panorámica, selección y estadísticas del intervalo |
| C02-4 Tramos | `SegmentsView` | Índice, cabecera de métricas, mapa con tramo resaltado, perfil, métricas, renombrar/notas |
| C02-5 / C01-4 Biomecánica | `BiomechView` | Esquema de caballo con 3 IMU, índices exploratorios del motor, patrón de movimiento, cadencia, tabla de simetría y controles |
| C02-6 / C01-5 Comparativa | `CompareView` | Selección con colores, recorridos superpuestos, curvas alineadas por tiempo o distancia, tabla, comparación con el motor |
| C02-7 / C01-6 Mareas | `TidesView` | Condiciones, curva de marea del día con hora del entrenamiento, fuentes y tipo de dato |
| C02-8 / C01-7 Informes | `ReportsView` | Vista previa, PDF/HTML/CSV/GPX/JSON, opciones, notas |
| C01-8 Servidor | `ServerView` | Estado (no conectado), panel, descarga HTTPS verificada, biblioteca local |

**Desviaciones justificadas:** modelo 3D de caballo sustituido por un esquema 2D original (no hay recurso 3D autorizado);
la «simetría 94 %» de las maquetas no se reproduce porque el motor no produce una puntuación de simetría validada (se muestra
la asimetría temporal exploratoria tal cual); fotos de caballos y de playa sustituidas por la imagen de marca AVO; en
1366 px las pestañas superiores se ocultan (la navegación lateral sigue disponible) para no mostrar pestañas cortadas.

## Arquitectura
- `AVO.Windows.Core` (net10.0, sin WPF, advertencias = errores): importación segura, lectura RAW (GNSS_SAMPLE 85 B, IMU_SAMPLE,
  MARKER), `SessionTimeline` (velocidades, aceleraciones, distancia, pérdidas), `SpeedSmoother` (Kalman + RTS),
  `Downsampler` (LTTB solo para dibujo), tramos y `SegmentStore`, `SeriesAligner`, mareas IHM / Open-Meteo con caché,
  `MadridTime`, `PdfDocument` y `ReportBuilder`, exportaciones, biblioteca, registro, servidor (`IAvoServerClient`).
- Motor AVO Equine Intelligence 1.1.0 (C++, el mismo de Android) por P/Invoke (`avo_equine.dll`): aires, cadencia,
  regularidad, simetría exploratoria, eventos, curvas y comparación. Sin duplicar algoritmos en C#.
- `AVO.Windows` (WPF, MVVM): `MainViewModel` (parciales por área), `SessionItem`, vistas sin lógica de cálculo; todo el
  procesamiento pesado en `Task.Run`; cursor, selección y ventana X compartidos entre mapa y gráficas.

## Filtrado de velocidad (documentado)
Kalman de estado [v, a] con sacudida blanca (densidad 1,0 m²/s⁵) y medida = gSpeed con varianza max(sAcc, 0,05 m/s)²;
suavizado RTS; reinicio tras cada hueco (> 2,5 × periodo nominal). Evaluado con señal de prueba (8 Hz, ruido 0,05 m/s):
error medio de aceleración 0,09 m/s², sesgo < 0,001 m/s², σa ≈ 0,22 m/s². Las señales originales se pueden mostrar sin filtrar.
Aceleración «validada»: σa ≤ 0,8 m/s², solución ≥ DGNSS, sin huecos ni saltos de posición.

## Validación visual
CI ejecuta la aplicación publicada en modo `--capture` y genera 33 capturas reales (11 vistas × 1920×1080, 1366×768 y
2560×1440 al 150 %), además de PDF/HTML/CSV/GPX/JSON. Se publican como artefacto `AVO-Windows-V2-capturas` y en la rama
`ci/windows-visual-evidence`. Las capturas usan sesiones de **DEMOSTRACIÓN sintéticas** (`windows/tools/demo-fixtures`),
marcadas en todas las vistas; mareas y meteorología son datos reales de IHM y Open-Meteo consultados durante la ejecución.
No se afirma equivalencia exacta con las maquetas: composición, paleta y componentes siguen las referencias con las
desviaciones anteriores.
