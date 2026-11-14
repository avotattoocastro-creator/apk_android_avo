import SwiftUI
import Observation

/// Pages of the app (same ids as Windows MainViewModel.Page). "WatchWifi" replaces the Windows "Reloj USB" button.
enum Page: String, CaseIterable, Identifiable {
    case home = "Home", sessions = "Sessions", trainingList = "List", races = "Races", stable = "Stable", riders = "Riders", analysis = "Analysis", map = "Map",
         gps = "Gps", charts = "Charts", segments = "Segments", biomech = "Biomech", compare = "Compare", geofences = "Geofences",
         tides = "Tides", reports = "Reports", watchWifi = "WatchWifi", server = "Server", engine = "Engine",
         summary = "Summary", trackWork = "TrackWork", assistant = "Assistant",
         calendar = "Calendar", keyData = "KeyData", settings = "Settings"
    var id: String { rawValue }

    /// Pages of ONE training: shown in the top bar of the training (Análisis), not in the sidebar.
    /// «Mapa» is now the «Análisis» page itself (map, profile, time bar and zones).
    var isTrainingPage: Bool {
        switch self {
        case .analysis, .map, .summary, .gps, .charts, .trackWork, .assistant, .segments, .biomech, .compare, .tides, .reports, .engine, .keyData: return true
        default: return false
        }
    }
}

/// Shell model = port of windows/AVO.Windows/ViewModels/MainViewModel.cs (+ .Window.cs, favourites, playback, engine).
/// CONTRACT shared by every UI file (written in parallel): names below are fixed; feature state lives in the feature
/// models (one @Observable class per Windows MainViewModel.<Feature>.cs partial), created in init() with `app: self`.
@Observable
final class AppModel {
    // ---------------------------------------------------------------- services
    @ObservationIgnored let paths: AppPaths
    @ObservationIgnored let settings: AppSettings
    @ObservationIgnored let log: AppLog
    @ObservationIgnored var library: TrainingLibrary
    @ObservationIgnored var segmentStore: SegmentStore

    // ---------------------------------------------------------------- feature models (defined in their own files)
    @ObservationIgnored var charts: ChartsModel!          // MainViewModel.Charts.cs + map route (MapModel lives inside)
    @ObservationIgnored var map: MapModel!                // map provider, colour mode, route rebuild
    @ObservationIgnored var gps: GpsModel!                // «GPS» page: every GNSS/RTK datum of the vest (no map)
    @ObservationIgnored var segments: SegmentsModel!      // MainViewModel.Segments.cs
    @ObservationIgnored var compare: CompareModel!        // MainViewModel.Compare.cs
    @ObservationIgnored var biomech: BiomechModel!        // biomechanics page (girth IMU)
    @ObservationIgnored var environment: EnvironmentModel! // MainViewModel.Environment.cs (tides + weather)
    @ObservationIgnored var reports: ReportsModel!        // MainViewModel.Reports.cs
    @ObservationIgnored var stable: StableModel!          // MainViewModel.Stable.cs (Cuadra/Jinetes/Asignar)
    @ObservationIgnored var geofences: GeofencesModel!    // MainViewModel.Geofences.cs (+ Bluetooth send)
    @ObservationIgnored var watchWifi: WatchWifiModel!    // replaces MainViewModel.Usb.cs: download over the watch Wi-Fi
    @ObservationIgnored var trainingList: TrainingListModel! // «Listado»: table + filters + recovery of lost trainings
    @ObservationIgnored var races: RacesModel!            // «Carreras»: tracking PDFs of races + analysis vs trainings
    @ObservationIgnored var horseHistory: HorseHistoryModel! // «Historia del caballo» (AVO Training Analytics), full-screen cover
    @ObservationIgnored var corrections: CorrectionsModel!  // zones moved by the user (correcciones.json) for the engine
    @ObservationIgnored var franceGalop: FranceGalopModel! // France Galop: horse sheets / whole stable read in an in-app browser
    @ObservationIgnored var stretch: StretchModel!        // «Análisis del tramo» (full-screen) + stretches saved per horse
    @ObservationIgnored var trackWork: TrackWorkModel!    // «Trabajo en pista» (AVO Track Work): efforts, splits, best distances
    @ObservationIgnored var raceVideo: RaceVideoModel!     // «Analizar vídeo» de una carrera (seguimiento automático)
    @ObservationIgnored var assistant: AssistantModel!    // «Asistente IA»: Claude (API, clave en el Llavero) o modelo de Apple

    // ---------------------------------------------------------------- state (names = MainViewModel, lowerCamel)
    /// «Análisis» (map + charts) is hidden for now (trainer's sketch 14/11/2026): asking for it opens «Resumen», the first
    /// tab of the training.
    var page: Page = .home {
        didSet {
            if page == .analysis { page = .summary; return }
            if oldValue != page { onPageChanged() }
        }
    }
    /// A training has been opened (list, calendar, dashboard…): unlocks Mapa / Análisis / Biomecánica in the sidebar.
    var trainingOpened: Bool = false
    /// Library restored and «AVO Horse» checked: «INICIAR» of the start screen is enabled.
    var startReady: Bool = false
    var sessions: [SessionItem] = []
    var importLog: [ImportLogRow] = []
    var status: String = "Listo · importa un entrenamiento .avo o .avr"
    var busy: Bool = false
    /// PDF shown over any page (Informe IA, informe completo from Cuadra) with «Compartir».
    var pdfViewer: ExportedFile? = nil
    var progress: Double = 0
    var demoState: String = ""
    var search: String = ""
    var onlyFavorites: Bool = false
    var selected: SessionItem? = nil
    var cursorTime: Double = .nan
    var rangeStart: Double = .nan
    var rangeEnd: Double = .nan
    var chartXMin: Double = .nan
    var chartXMax: Double = .nan
    var isPlaying: Bool = false
    var playbackSpeed: Double = 1   // 1× by default (trainer 14/11/2026)
    let playbackSpeeds: [Double] = [1, 2, 5, 10, 20, 60]
    /// Alert shown by RootView (Windows IDialogs.Show).
    var alert: AppAlert? = nil
    /// Capture mode (CI screenshots): demo sessions imported, engine run, then `captureReady` = true.
    var captureMode: Bool = false
    var captureReady: Bool = false
    /// Set to true to present the .avo/.avr file importer of RootView (Windows ImportCommand).
    var showImporter: Bool = false
    /// Non-observed shell state (favourites, windows, playback timer, engine gate): see AppModel+Shell.swift.
    @ObservationIgnored var shellState: ShellState = ShellState()

    init(paths: AppPaths = AppPaths()) {
        self.paths = paths
        AvoFiles.ensureDir(paths.root)
        self.log = AppLog(paths.logs)
        AppLog.current = log
        self.settings = AppSettings.load(paths.settingsFile)
        self.library = TrainingLibrary(paths)
        self.segmentStore = SegmentStore(paths.segments)
        self.charts = ChartsModel(app: self)
        self.map = MapModel(app: self)
        self.gps = GpsModel(app: self)
        self.segments = SegmentsModel(app: self)
        self.compare = CompareModel(app: self)
        self.biomech = BiomechModel(app: self)
        self.environment = EnvironmentModel(app: self)
        self.reports = ReportsModel(app: self)
        self.stable = StableModel(app: self)
        self.geofences = GeofencesModel(app: self)
        self.watchWifi = WatchWifiModel(app: self)
        self.trainingList = TrainingListModel(app: self)
        self.races = RacesModel(app: self)
        self.horseHistory = HorseHistoryModel(app: self)
        self.corrections = CorrectionsModel(app: self)
        self.trackWork = TrackWorkModel(app: self)
        self.assistant = AssistantModel(app: self)
        self.raceVideo = RaceVideoModel(app: self)
        self.stretch = StretchModel(app: self)
        self.franceGalop = FranceGalopModel(app: self)
        initShell()
    }
}

struct AppAlert: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var isError: Bool = false
}

struct ImportLogRow: Identifiable {
    let id = UUID()
    var time: String
    var file: String
    var result: String
    var ok: Bool
}
