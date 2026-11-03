# Contrato de la interfaz iPad (para escribir las vistas en paralelo)

Origen: `windows/AVO.Windows/` (WPF). Cada página de Windows es una vista SwiftUI con el mismo contenido, los mismos
textos en español y las mismas acciones, adaptada al iPad (táctil, horizontal y vertical, Split View).
Núcleo ya portado en `ipad/AVOiPad/Core/` y `ipad/AVOiPad/Engine/` (ver `ipad/PORTING.md`). Estilo: `Views/Theme.swift`
(`Avo.*` colores, `AvoCard`, `AvoMetric`, `AvoPill`, `.avoPrimary`, `.avoSecondary`, `AvoPageTitle`, `AvoNoData`).

## Modelo raíz `AppModel` (`App/AppModel.swift`, `@Observable`)
Propiedades fijas: ver el archivo. Las vistas lo leen con `@Environment(AppModel.self) private var app` y escriben con
`@Bindable var app = app` cuando necesitan enlaces.

Métodos que implementa el **agente de la estructura** (`App/AppModel+Shell.swift`) y que los demás pueden llamar:
- `func importFiles(_ paths: [String], restoring: Bool = false) async`
- `func importURLs(_ urls: [URL]) async` (copia con acceso de seguridad a la carpeta de la app y llama a importFiles)
- `func select(_ item: SessionItem?)` — cambia `selected`, reinicia cursor/rango/zoom y llama a `sessionChanged()` de todos los modelos
- `func notifySessionChanged()` — vuelve a llamar a `sessionChanged()` en todos los modelos (tras motor, recorte o asignación)
- `func runEngine(_ item: SessionItem, force: Bool) async`
- `func show(_ title: String, _ message: String, error: Bool = false)` (pone `alert`)
- `func setWindow(_ s: SessionItem, start: Double?, end: Double?)` (recorte útil, recortes.json)
- `func togglePlay()`, `func stopPlay()`
- `var sessionsView: [SessionItem]` (filtradas por búsqueda/favoritos, orden por fecha descendente)
- `var hasSession: Bool`, `var timelineStart: Double`, `var timelineEnd: Double`, `var hasRange: Bool`
- `var cursorIndex: Int` (-1 si no hay), `cursorText`, `cursorSpeed`, `cursorAccel`, `cursorAltitude`, `cursorDistance`,
  `cursorQuality`, `cursorPosition`, `cursorCadence`, `playbackText` (todas `String`, como en Windows)
- `func toggleFavorite(_ s: SessionItem)`
- `var engineInfo: String`, `engineAvailable: Bool`, `engineShort: String`

`SessionItem` (`App/SessionItem.swift`, `@Observable final class`, `Identifiable` por `id`) = port de `SessionItem.cs`:
`session`, `fullTimeline`, `timeline`, `imu`, `windowStart`, `windowEnd`, `isTrimmed`, `windowText`, `segmentDefs:
[SegmentDefinition]`, `engine: EquineAnalysis?`, `engineOffsetS`, `engineState`, `notes`, `isFavorite`, `isCompared`,
`compareColor: Color`, `importStatus`, `id`, `horse`, `rider`, `horseCode`, `riderCode`, `horseKnown`, `riderKnown`,
`identitySource`, `setIdentity(_:_:)`, `needsIdentity`, `start: Date?`, `dateText`, `dateTimeText`, `timeText`,
`distanceKmValue`, `distanceText`, `durationText`, `maxSpeedKmh`, `maxSpeedText`, `meanSpeedText`, `fixPercent`,
`fixText`, `hasGirth`, `girthText`, `kind`, `isSynthetic`, `integrity`, `discipline`, `summary`, `gaitByIndex: [Int]`,
`applyWindow(_:_:_:)`.

## Modelos de cada función
Cada uno es `@Observable final class XxxModel` en su propio archivo `App/XxxModel.swift`, con
`unowned let app: AppModel`, `init(app: AppModel)` (sin tocar otros modelos dentro de init) y **obligatoriamente**:
- `func sessionChanged()` — la sesión seleccionada, su recorte o su resultado del motor cambió
- `func pageShown()` — su página acaba de mostrarse
| Modelo | Origen Windows | Página(s) |
|---|---|---|
| `ChartsModel` | MainViewModel.Charts.cs | Charts |
| `MapModel` | MainViewModel.cs (MapProvider, ColorMode, LegendTitle) + MapControl.cs | Map |
| `SegmentsModel` | MainViewModel.Segments.cs | Segments |
| `CompareModel` | MainViewModel.Compare.cs | Compare |
| `BiomechModel` | partes de Biomech de MainViewModel*.cs | Biomech |
| `EnvironmentModel` | MainViewModel.Environment.cs | Tides |
| `ReportsModel` | MainViewModel.Reports.cs | Reports |
| `StableModel` | MainViewModel.Stable.cs (Cuadra, Jinetes, Asignar) | Stable, Riders + hoja Asignar |
| `GeofencesModel` | MainViewModel.Geofences.cs | Geofences |
| `WatchWifiModel` | sustituye MainViewModel.Usb.cs | WatchWifi |
| `TrainingListModel` | nuevo en iPad (sin equivalente Windows) | List («Listado»: tabla filtrable + buscar entrenamientos perdidos) |
| `RacesModel` | nuevo en iPad (sin equivalente Windows) | Races («Carreras»: PDF «Statistiques Tracking» de France Galop / McLloyd, `carreras.json` + copia del PDF en `carreras/`, análisis frente a los entrenamientos; también desde la ficha del caballo en Cuadra) |
| `TrackWorkModel` | nuevo en iPad (AVO Track Work 1.0.0) | «Trabajo en pista» (`Page.trackWork` = `TrackWork`, pestaña de la barra del entrenamiento junto a Análisis / Resumen / Gráficas, `tab.TrackWork`): estructura de la sesión, tabla de trabajos y pasadas (ordenable), detalle del seleccionado (parciales, mejores distancias, velocidad-distancia, zancada-velocidad, cincha, giros, eventos), mejores distancias de la sesión, cincha, recorrido y eventos. `select(_:)` pone `rangeStart`/`rangeEnd`/`cursorTime` (y la ventana de Gráficas) en el trabajo; `selectedKey` = `T<id>` (trabajo) o `P<id>` (pasada) |
| `HorseHistoryModel` | nuevo en iPad (AVO Training Analytics 1.0.0) | «Historia del caballo» (`HorseHistoryView`, pantalla completa desde RootView, no es página del menú): se abre desde la ficha del caballo en Cuadra y desde el nombre del caballo en Análisis; valoraciones del entrenador en `valoraciones.json` (`App/AppModel+Training.swift`) |

## Vistas (nombres fijos, cada una en `Views/<Nombre>.swift`)
`StartView`, `HomeView` (Entrenamientos), `AnalysisView`, `MapPageView`, `ChartsView`, `SegmentsView`, `BiomechView`,
`CompareView`, `GeofencesView`, `TidesView`, `ReportsView`, `WatchWifiView`, `ServerView`, `EngineView`, `TrainingListView`, `RacesView` (+ `RaceDetailView`, ficha de la carrera; importación compartida en `SharedRaceImport.swift`),
`TrackWorkView` (bloque «trabajo_pista» completo; modelo en `Core/TrackWork.swift`: `TrackWorkResult`, `TrackWorkEffort` con `splits`/`best`/zancada/mano, `TrackWorkGirth`, `TrackWorkLead`, `TrackWorkEvent`, `TrackWorkText`; el panel «Entrenamiento» de `MapPageView` queda como resumen con el botón «Ver trabajo en pista»), `RaceTrainingSplitsCard` (`Views/RaceTrainingSplitsView.swift`, bloque «Entrenamiento vs carrera, tramo a tramo» de la ficha de la carrera; alineación en `Core/RaceAnalysis.swift`, `RaceTrainingSplits`),
`StableView(kind: IdentityKind)` (Cuadra = caballos, Jinetes = jinetes), `AssignSheet` (hoja «Caballo y jinete del
entrenamiento», se presenta desde RootView cuando `app.stable.assignVisible` es true).
Componentes compartidos que necesites en más de una vista: en un archivo propio con nombre único
(`Views/Shared<Algo>.swift`), nunca en archivos de otro agente.

## Reglas
- Sin datos reales → «Sin datos» (`AvoNoData`), nunca valores inventados. Las sesiones DEMO llevan siempre la marca DEMOSTRACIÓN.
- Cálculos pesados fuera del hilo principal (`Task.detached`), resultados al modelo en `@MainActor`.
- Exportar = `ShareLink`/`fileExporter` con el archivo generado en `paths.root/exportaciones`.
- Identificadores de accesibilidad: botones del menú lateral `nav.<Page.rawValue>` (los pone RootView).
- AVO Track Work: sin cincha → «Requiere cincha»; sin líneas de salida y meta → «Requiere líneas de salida y meta»; mano de galope y
  eventos de la cincha siempre marcados EXPERIMENTAL. Los tiempos del motor son segundos del motor: tiempo de la app = motor − `engineOffsetS`.
- Swift 5, iOS 17, sin dependencias externas. No hay compilador en la sesión: código conservador, tipos explícitos.
