import SwiftUI
import Foundation

// Shell of the app = port of windows/AVO.Windows/ViewModels/MainViewModel.cs (import, selection, shared cursor, playback,
// engine, home, favourites) + MainViewModel.Window.cs (useful-window trim stored in recortes.json) + App.xaml.cs (start-up
// and the capture mode used by CI to take screenshots).

/// Non-observed state of the shell (stored in AppModel.shellState).
final class ShellState {
    /// Session ids marked as favourite (favoritos.json, sorted string array like Windows).
    var favorites: Set<String> = []
    /// Useful window per session id (recortes.json: {"id": {"Start": s, "End": e}} like System.Text.Json writes it).
    var windows: [String: ShellWindowEntry] = [:]
    var timer: Timer? = nil
    var lastTick: Date = Date()
    /// Engine runs are serialized (Windows SemaphoreSlim(1)).
    var engineBusy: Bool = false
    var started: Bool = false
    /// Trainer ratings per session id (valoraciones.json), loaded on first use (AppModel+Training.swift).
    var ratings: [String: TrainingRating]? = nil
    init() {}
}

/// recortes.json entry (C# record WindowEntry(double Start, double End)).
struct ShellWindowEntry: Codable, Equatable {
    var start: Double
    var end: Double
    enum CodingKeys: String, CodingKey {
        case start = "Start"
        case end = "End"
    }
}

/// Horse card of the home page (C# record HorseCard).
struct HomeHorseCard: Identifiable, Equatable {
    var name: String
    var sessions: Int
    var lastDate: String
    var bestSpeed: String
    var id: String { name }
}

/// Key/value row of the shell panels (C# KeyValueRow).
struct ShellRow: Identifiable, Hashable {
    var key: String
    var value: String
    var id: String { key }
}

extension AppModel {
    // ------------------------------------------------------------------ launch
    static let appVersion: String = "1.0.0"
    static let demoNamePattern: String = "^DEMO_[A-Za-z0-9_]{1,60}\\.avr$"

    static var isCaptureLaunch: Bool { ProcessInfo.processInfo.arguments.contains("-AVOCapture") }

    /// Creates the app model: a fresh temporary root in capture mode (CI screenshots), the user folder otherwise.
    static func launch() -> AppModel {
        if isCaptureLaunch {
            let root: String = AvoFiles.join(NSTemporaryDirectory(), "AVOCapture-" + UUID().uuidString)
            return AppModel(paths: AppPaths(root: root))
        }
        return AppModel()
    }

    /// Called at the end of AppModel.init: favourites, windows, then restores the library (or runs the capture mode).
    func initShell() {
        initFavorites()
        initWindows()
        captureMode = AppModel.isCaptureLaunch
        log.info("app", "Inicio", ["version": AppModel.appVersion, "motor": EquineEngine.available ? EquineEngine.version() : "no disponible"])
        if shellState.started { return }
        shellState.started = true
        let capture: Bool = captureMode
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if capture {
                await self.runCapture()
            } else {
                await self.restoreLibrary()
                self.startDocumentsSync()
            }
        }
    }

    // ------------------------------------------------------------------ navigation
    /// Called by `page.didSet`: tells the feature model of the page that it is visible.
    func onPageChanged() {
        switch page {
        case .stable, .riders: stable?.pageShown()
        case .map: map?.pageShown()
        case .analysis: map?.pageShown(); charts?.pageShown()
        case .charts: charts?.pageShown()
        case .segments: segments?.pageShown()
        case .biomech: biomech?.pageShown()
        case .compare: compare?.pageShown()
        case .geofences: geofences?.pageShown()
        case .tides: environment?.pageShown()
        case .reports: reports?.pageShown()
        case .watchWifi: watchWifi?.pageShown()
        case .gps: gps?.pageShown()
        case .trainingList: trainingList?.pageShown()
        case .races: races?.pageShown()
        case .trackWork: trackWork?.pageShown()
        case .assistant: assistant?.pageShown()
        case .home, .sessions, .server, .engine, .summary: break
        }
    }

    /// Analysis pages without any training: show a clear «import / demo» panel instead of empty widgets.
    var showEmptyState: Bool {
        if !sessions.isEmpty { return false }
        switch page {
        case .home, .sessions, .trainingList, .races, .server, .engine, .stable, .riders, .geofences, .watchWifi: return false
        default: return true
        }
    }

    func show(_ title: String, _ message: String, error: Bool = false) {
        alert = AppAlert(title: title, message: message, isError: error)
    }

    /// Windows MainViewModel.Fail.
    func fail(_ error: Error) {
        log.error("ui", error.localizedDescription, error)
        status = "Error: " + error.localizedDescription
        show("AVO Performance Horse", error.localizedDescription, error: true)
    }

    // ------------------------------------------------------------------ engine info
    var engineInfo: String {
        EquineEngine.available ? "Motor AVO Equine \(EquineEngine.version())" : "Motor no disponible: " + (EquineEngine.unavailableReason ?? "")
    }
    var engineAvailable: Bool { EquineEngine.available }
    var engineShort: String { EquineEngine.available ? EquineEngine.version() : "No disponible" }
    var engineIndicator: AvoState { EquineEngine.available ? .ok : .error }

    // ------------------------------------------------------------------ favourites & filter
    private var favoritesFile: String { AvoFiles.join(paths.root, "favoritos.json") }

    private func initFavorites() {
        guard let data = AvoFiles.read(favoritesFile) else { return }
        var d: Data = data
        if d.starts(with: [0xEF, 0xBB, 0xBF]) { d = Data(d.dropFirst(3)) }
        if let list = try? JSONDecoder().decode([String].self, from: d) {
            shellState.favorites = Set(list)
        } else {
            log.warn("favoritos", "favoritos.json no válido")
        }
    }

    func toggleFavorite(_ s: SessionItem) {
        s.isFavorite = !s.isFavorite
        if s.isFavorite { shellState.favorites.insert(s.id) } else { shellState.favorites.remove(s.id) }
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.withoutEscapingSlashes]
            let data: Data = try enc.encode(shellState.favorites.sorted())
            try AvoFiles.writeAtomic(data, to: favoritesFile)
        } catch {
            log.warn("favoritos", error.localizedDescription, error)
        }
    }

    private func matchesFilter(_ s: SessionItem) -> Bool {
        if onlyFavorites && !s.isFavorite { return false }
        let q: String = search.trimmed
        if q.isEmpty { return true }
        let fields: [String] = [s.horse, s.rider, s.horseCode ?? "", s.riderCode ?? "", s.id, s.dateText, s.discipline, s.kind]
        for f in fields where f.localizedCaseInsensitiveContains(q) { return true }
        return false
    }

    /// Sessions filtered by search / favourites, newest first (Windows SessionsView).
    var sessionsView: [SessionItem] {
        AppModel.byDateDescending(sessions.filter { matchesFilter($0) })
    }

    static func byDateDescending(_ list: [SessionItem]) -> [SessionItem] {
        list.sorted { (a: SessionItem, b: SessionItem) -> Bool in
            let da: Date = a.start ?? Date.distantPast
            let db: Date = b.start ?? Date.distantPast
            return da > db
        }
    }

    // ------------------------------------------------------------------ selection
    var hasSession: Bool { selected != nil }

    func select(_ item: SessionItem?) {
        if selected === item { return }
        selected = item
        stopPlay()
        if let s = item, s.timeline.count > 0 { cursorTime = s.timeline.t[0] } else { cursorTime = .nan }
        rangeStart = .nan
        rangeEnd = .nan
        chartXMin = .nan
        chartXMax = .nan
        notifySessionChanged()
        if let s = item, s.engine == nil {
            Task { @MainActor [weak self] in await self?.runEngine(s, force: false) }
        }
    }

    /// Calls sessionChanged() on every feature model (after a selection, a trim, an engine result or an assignment).
    func notifySessionChanged() {
        charts?.sessionChanged()
        map?.sessionChanged()
        gps?.sessionChanged()
        segments?.sessionChanged()
        compare?.sessionChanged()
        biomech?.sessionChanged()
        environment?.sessionChanged()
        reports?.sessionChanged()
        stable?.sessionChanged()
        geofences?.sessionChanged()
        watchWifi?.sessionChanged()
        trainingList?.sessionChanged()
        races?.sessionChanged()
        trackWork?.sessionChanged()
        assistant?.sessionChanged()
    }

    var timelineStart: Double {
        guard let s = selected, s.timeline.count > 1 else { return 0 }
        return s.timeline.t[0]
    }
    var timelineEnd: Double {
        guard let s = selected, s.timeline.count > 1 else { return 1 }
        return s.timeline.t[s.timeline.count - 1]
    }
    var hasRange: Bool { rangeStart.isFinite && rangeEnd.isFinite && abs(rangeEnd - rangeStart) > 0.5 }

    func resetZoom() { chartXMin = .nan; chartXMax = .nan }
    func clearRange() { rangeStart = .nan; rangeEnd = .nan }

    // ------------------------------------------------------------------ shared cursor texts
    var cursorIndex: Int {
        guard let s = selected, cursorTime.isFinite, s.timeline.count > 0 else { return -1 }
        let i: Int = s.timeline.indexAt(cursorTime)
        return i >= 0 && i < s.timeline.count ? i : -1
    }

    private func cursorValue(_ f: (SessionTimeline, Int) -> Double, _ fmt: String) -> String {
        let i: Int = cursorIndex
        guard i >= 0, let s = selected else { return "—" }
        let v: Double = f(s.timeline, i)
        return v.isFinite ? DotNetFormat.custom(v, fmt, spanish: true) : "—"
    }

    var cursorText: String {
        if selected == nil || !cursorTime.isFinite { return "—" }
        return TimeText.clock(cursorTime)
    }
    var cursorSpeed: String { cursorValue({ tl, i in tl.speedFiltered[i] * 3.6 }, "0.0") }
    var cursorAccel: String { cursorValue({ tl, i in SegmentAnalyzer.accelValid(tl, i) ? tl.accelLong[i] : .nan }, "0.00") }
    var cursorAltitude: String { cursorValue({ tl, i in tl.altitudeMsl[i] }, "0.0") }
    var cursorDistance: String { cursorValue({ tl, i in tl.distance[i] / 1000 }, "0.00") }
    /// Distance from the start at the cursor, in metres (map overlay «Punto del cursor»).
    var cursorDistanceM: String { cursorValue({ tl, i in tl.distance[i] }, "0") }
    var cursorQuality: String {
        let i: Int = cursorIndex
        guard i >= 0, let s = selected else { return "—" }
        let tl: SessionTimeline = s.timeline
        return "\(GnssQuality.name(tl.solution[i])) · \(tl.numSv[i]) sat · hAcc \(DotNetFormat.custom(tl.hAcc[i], "0.000", spanish: true)) m"
    }
    var cursorPosition: String {
        let i: Int = cursorIndex
        guard i >= 0, let s = selected else { return "—" }
        return "\(AvoFormat.inv(s.timeline.lat[i], 6)), \(AvoFormat.inv(s.timeline.lon[i], 6))"
    }
    var cursorCadence: String {
        guard let s = selected, let e = s.engine, e.hasImu, cursorTime.isFinite else { return "—" }
        let f: Double = e.cadenceAt(cursorTime + s.engineOffsetS)
        return f.isFinite ? DotNetFormat.custom(f * 60, "0", spanish: true) : "—"
    }
    var playbackText: String {
        if selected == nil { return "00:00 / 00:00" }
        return "\(cursorText) / \(TimeText.clock(timelineEnd))"
    }

    // ------------------------------------------------------------------ playback (50 ms timer)
    func togglePlay() {
        if isPlaying { stopPlay(); return }
        guard let s = selected, s.timeline.count > 0 else { return }
        if !cursorTime.isFinite || cursorTime >= timelineEnd - 0.5 { cursorTime = s.timeline.t[0] }
        shellState.lastTick = Date()
        isPlaying = true
        shellState.timer?.invalidate()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.playbackTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        shellState.timer = timer
    }

    func stopPlay() {
        shellState.timer?.invalidate()
        shellState.timer = nil
        if isPlaying { isPlaying = false }
    }

    private func playbackTick() {
        let now: Date = Date()
        let dt: Double = now.timeIntervalSince(shellState.lastTick) * playbackSpeed
        shellState.lastTick = now
        let next: Double = (cursorTime.isFinite ? cursorTime : 0) + dt
        if next >= timelineEnd {
            cursorTime = timelineEnd
            stopPlay()
            return
        }
        cursorTime = next
    }

    // ------------------------------------------------------------------ import
    @MainActor
    func restoreLibrary() async {
        let files: [String] = library.storedFiles()
        if !files.isEmpty { await importFiles(files, restoring: true) }
    }

    @MainActor
    func importFiles(_ paths: [String], restoring: Bool = false) async {
        var seen: Set<String> = []
        var list: [String] = []
        for p in paths where !seen.contains(p.lowercased()) {
            seen.insert(p.lowercased())
            list.append(p)
        }
        if list.isEmpty { return }
        busy = true
        var ok: Int = 0
        var bad: Int = 0
        var dup: Int = 0
        var k: Int = 0
        var lastImported: SessionItem? = nil
        var imported: [SessionItem] = []
        let lib: TrainingLibrary = library
        let store: SegmentStore = segmentStore
        let jerk: Double = settings.jerkDensity
        let notesDir: String = self.paths.notes
        let timeFormatter: DateFormatter = AvoTime.formatter("HH:mm")
        for f in list {
            k += 1
            status = "Validando \(AvoFiles.fileName(f)) (\(k)/\(list.count))…"
            progress = Double(k) / Double(list.count)
            let loaded: [String] = sessions.map { $0.id }
            let outcome: ImportOutcome = await Task.detached(priority: .userInitiated) { () -> ImportOutcome in
                lib.importFile(f, loadedSessionIds: loaded)
            }.value
            guard let session = outcome.session else {
                bad += 1
                importLog.insert(ImportLogRow(time: timeFormatter.string(from: Date()), file: AvoFiles.fileName(f),
                                              result: "Rechazado: " + (outcome.error ?? ""), ok: false), at: 0)
                log.warn("import", "\(AvoFiles.fileName(f)) rechazado: \(outcome.error ?? "")")
                continue
            }
            if sessions.contains(where: { $0.session.fileSha256 != nil && $0.session.fileSha256 == session.fileSha256 }) {
                dup += 1
                continue
            }
            let window: ShellWindowEntry? = shellState.windows[session.sessionId]
            let item: SessionItem = await Task.detached(priority: .userInitiated) { () -> SessionItem in
                AppModel.buildItem(session, jerk: jerk, window: window, store: store, notesDir: notesDir)
            }.value
            item.importStatus = outcome.status
            if let same = sessions.firstIndex(where: { $0.id == item.id }) {
                sessions.remove(at: same)
                dup += 1
            }
            sessions.append(item)
            item.isFavorite = shellState.favorites.contains(item.id)
            lastImported = item
            imported.append(item)
            ok += 1
            if !restoring { forgetDeleted(sha: session.fileSha256, sessionId: item.id) }
            if !restoring || importLog.count < 8 {
                importLog.insert(ImportLogRow(time: timeFormatter.string(from: Date()), file: session.sourceName,
                                              result: outcome.status + (item.isSynthetic ? " · DEMOSTRACIÓN" : ""), ok: true), at: 0)
            }
            log.info("import", outcome.status, ["id": item.id, "sha": session.fileSha256 ?? ""])
        }
        busy = false
        progress = 0
        status = "Importación: \(ok) aceptados, \(bad) rechazados, \(dup) duplicados · \(sessions.count) sesiones"
        assignCompareColors()
        if !imported.isEmpty { stable?.registerImported(imported) }
        if !restoring, let last = lastImported {
            select(last)                                   // what the user just opened
            if page == .home || page == .sessions { page = .analysis }
        }
        if selected == nil, let newest = AppModel.byDateDescending(sessions).first { select(newest) }
        if bad > 0 && !restoring {
            show("Importación", "\(bad) archivo(s) rechazados. Consulta «Estado de importaciones» en Entrenamientos.", error: true)
        }
    }

    /// Files opened from Files, AirDrop, Share or the document picker: copied (with security-scoped access) into the
    /// app folder, imported into the library (which keeps its own verified copy) and the temporary copy removed.
    @MainActor
    func importURLs(_ urls: [URL]) async {
        let inbox: String = AvoFiles.join(paths.root, "entrada")
        var copied: [String] = []
        var folders: [URL] = []
        for url in urls {
            if url.hasDirectoryPath { folders.append(url); continue }
            let result: (path: String?, error: String?) = await Task.detached(priority: .userInitiated) { () -> (path: String?, error: String?) in
                AppModel.copyIn(url, inbox: inbox)
            }.value
            if let p = result.path {
                copied.append(p)
            } else {
                importLog.insert(ImportLogRow(time: AvoTime.formatter("HH:mm").string(from: Date()), file: url.lastPathComponent,
                                              result: "Rechazado: " + (result.error ?? "no se pudo leer"), ok: false), at: 0)
                log.warn("import", "No se pudo copiar \(url.lastPathComponent): \(result.error ?? "")")
            }
        }
        if !copied.isEmpty { await importFiles(copied) }
        for p in copied { try? FileManager.default.removeItem(atPath: (p as NSString).deletingLastPathComponent) }
        for f in folders { await importFolder(f) }
    }

    /// Windows ImportFolderCommand: every .avo/.avr of the folder (top level, at most 200).
    @MainActor
    func importFolder(_ folder: URL) async {
        let inbox: String = AvoFiles.join(paths.root, "entrada")
        let copied: [String] = await Task.detached(priority: .userInitiated) { () -> [String] in
            let access: Bool = folder.startAccessingSecurityScopedResource()
            defer { if access { folder.stopAccessingSecurityScopedResource() } }
            let names: [URL] = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            let files: [URL] = names.filter { (u: URL) -> Bool in
                let e: String = u.pathExtension.lowercased()
                return e == "avo" || e == "avr"
            }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            var out: [String] = []
            for u in files.prefix(200) {
                if let p = AppModel.copyIn(u, inbox: inbox).path { out.append(p) }
            }
            return out
        }.value
        if copied.isEmpty {
            status = "La carpeta no contiene archivos .avo ni .avr"
            return
        }
        await importFiles(copied)
        for p in copied { try? FileManager.default.removeItem(atPath: (p as NSString).deletingLastPathComponent) }
    }

    /// Copies one file into inbox/<uuid>/<name> keeping its name (shown in the import log).
    static func copyIn(_ url: URL, inbox: String) -> (path: String?, error: String?) {
        let access: Bool = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let dir: String = AvoFiles.join(inbox, UUID().uuidString)
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let name: String = url.lastPathComponent.isEmpty ? "entrenamiento.avo" : url.lastPathComponent
            let target: String = AvoFiles.join(dir, name)
            try FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: target))
            return (target, nil)
        } catch {
            try? FileManager.default.removeItem(atPath: dir)
            return (nil, error.localizedDescription)
        }
    }

    /// Builds the analysis objects of one session (off the main thread).
    static func buildItem(_ s: TrainingSession, jerk: Double, window: ShellWindowEntry?, store: SegmentStore,
                                      notesDir: String) -> SessionItem {
        let p = SpeedSmoother.Parameters(jerkDensity: jerk)
        let tl: SessionTimeline = SessionTimeline.build(s, parameters: p)
        let imu: ImuTimeline = ImuTimeline.build(s, tl)
        let item = SessionItem(s, tl, imu)
        if let w = window { item.applyWindow(w.start, w.end, p) }
        item.segmentDefs = store.load(s.sessionId)
        let notes: String = notesPath(store: store, notesDir: notesDir, sessionId: s.sessionId)
        if let data = AvoFiles.read(notes) { item.notes = String(decoding: data, as: UTF8.self) }
        return item
    }

    /// notas/<same name as the segments file>.txt (Windows NotesPath).
    static func notesPath(store: SegmentStore, notesDir: String, sessionId: String) -> String {
        let base: String = ((store.pathFor(sessionId) as NSString).lastPathComponent as NSString).deletingPathExtension
        return AvoFiles.join(notesDir, base + ".txt")
    }

    func notesPath(_ s: SessionItem) -> String {
        AppModel.notesPath(store: segmentStore, notesDir: paths.notes, sessionId: s.id)
    }

    /// Windows SessionNotes setter: keeps the text in the item and writes it (UTF-8 without BOM) to paths.notes.
    func saveSessionNotes(_ s: SessionItem, _ text: String) {
        s.notes = text
        do {
            AvoFiles.ensureDir(paths.notes)
            try AvoFiles.writeAtomic(Data(text.utf8), to: notesPath(s))
        } catch {
            log.warn("notas", error.localizedDescription, error)
        }
    }

    private static let comparePalette: [Color] = [
        Color(hex: 0x3D9BFF), Color(hex: 0xFFC42C), Color(hex: 0xED122A), Color(hex: 0x52DD40),
        Color(hex: 0x35D0E8), Color(hex: 0xA86BFF), Color(hex: 0xC9CBD1),
    ]

    /// Windows AssignCompareColors (MainViewModel.Compare.cs).
    func assignCompareColors() {
        let ordered: [SessionItem] = AppModel.byDateDescending(sessions)
        for (k, s) in ordered.enumerated() { s.compareColor = AppModel.comparePalette[k % AppModel.comparePalette.count] }
        if !sessions.contains(where: { $0.isCompared }) {
            for s in ordered.prefix(3) { s.isCompared = true }
        }
    }

    // ------------------------------------------------------------------ demo (bundled, synthetic)
    /// Folder "demo" bundled with the app (DEMO_*.avr written by windows/tools/demo-fixtures).
    var bundledDemoFiles: [String] {
        guard let dir = Bundle.main.url(forResource: "demo", withExtension: nil) else { return [] }
        let names: [String] = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0.matches(AppModel.demoNamePattern) }.sorted().map { AvoFiles.join(dir.path, $0) }
    }

    /// «Cargar demostración»: imports the SYNTHETIC demonstration sessions bundled with the app (clearly labelled demo).
    @MainActor
    func loadDemo() async {
        let files: [String] = bundledDemoFiles
        if files.isEmpty {
            demoState = "No se pudo cargar la demostración: esta compilación no incluye las sesiones de demostración."
            log.warn("demo", "Sin carpeta demo en el paquete de la app")
            return
        }
        demoState = "Importando \(files.count) sesiones de demostración…"
        await importFiles(files)
        demoState = "Sesiones de demostración cargadas (DATOS SINTÉTICOS)."
    }

    // ------------------------------------------------------------------ engine
    @MainActor
    func runEngine(_ item: SessionItem, force: Bool) async {
        if !EquineEngine.available { item.engineState = "Motor no disponible"; return }
        if item.session.rawSegmentPaths.isEmpty { item.engineState = "Sin segmentos RAW"; return }
        while shellState.engineBusy {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        shellState.engineBusy = true
        defer { shellState.engineBusy = false }
        if item.engine != nil && !force { return }
        item.engineState = "Analizando…"
        if item === selected { status = "Motor AVO analizando \(item.id)…" }
        let dir: String = engineDir(item.id)
        let segs: [String] = item.session.rawSegmentPaths
        do {
            // breed profile of the horse + zones corrected by the user (CorrectionsModel), part of the engine parameters
            let options: String = EquineEngine.options(series: true, cacheDir: dir, force: force, extra: corrections.engineOptions(item))
            let json: String = try await EquineEngine.analyseJson(segs, options)
            let analysis: EquineAnalysis = try await Task.detached(priority: .userInitiated) { () -> EquineAnalysis in
                try EquineAnalysis.parse(json)
            }.value
            item.engine = analysis
            item.engineState = analysis.cache == "ACIERTO" ? "Resultado guardado reutilizado" : "Calculado"
            // AVO Training Analytics: small per-session summary next to the analysis (AppModel+Training.swift)
            await writeTrainingSummary(item, analysisJson: json)
            if item === selected {
                status = "Motor \(analysis.engine): \(item.engineState)"
                notifySessionChanged()
            }
        } catch {
            item.engineState = "Error del motor: " + error.localizedDescription
            log.error("motor", error.localizedDescription, error)
        }
    }

    /// Folder of the engine results of one session (paths.analysis/<id with safe characters>).
    func engineDir(_ id: String) -> String {
        var safe: String = ""
        for c in id {
            if c.isLetter || c.isNumber || c == "-" || c == "_" { safe.append(c) } else { safe.append("_") }
        }
        return AvoFiles.join(paths.analysis, safe)
    }

    /// Waits for the engine of every loaded session (used by the capture mode).
    @MainActor
    func runEngineForAll() async {
        for s in sessions { await runEngine(s, force: false) }
    }

    // ------------------------------------------------------------------ useful window (MainViewModel.Window.cs)
    private var windowsFile: String { AvoFiles.join(paths.root, "recortes.json") }

    private func initWindows() {
        guard let data = AvoFiles.read(windowsFile) else { return }
        var d: Data = data
        if d.starts(with: [0xEF, 0xBB, 0xBF]) { d = Data(d.dropFirst(3)) }
        if let w = try? JSONDecoder().decode([String: ShellWindowEntry].self, from: d) {
            shellState.windows = w
        } else {
            log.warn("recortes", "recortes.json no válido")
        }
    }

    var windowText: String { selected?.windowText ?? "—" }
    var isTrimmed: Bool { selected?.isTrimmed ?? false }
    var canMarkWindow: Bool { (selected?.fullTimeline.count ?? 0) > 1 && cursorTime.isFinite }

    /// «Inicio = cursor»
    func windowStartAtCursor() {
        guard let s = selected, canMarkWindow else { return }
        let end: Double = s.windowEnd ?? s.fullTimeline.t[s.fullTimeline.count - 1]
        setWindow(s, start: cursorTime, end: end)
    }
    /// «Fin = cursor»
    func windowEndAtCursor() {
        guard let s = selected, canMarkWindow else { return }
        let start: Double = s.windowStart ?? s.fullTimeline.t[0]
        setWindow(s, start: start, end: cursorTime)
    }
    /// «Usar selección»
    func windowFromRange() {
        guard let s = selected, hasRange else { return }
        setWindow(s, start: min(rangeStart, rangeEnd), end: max(rangeStart, rangeEnd))
    }
    /// «Archivo completo»
    func windowReset() {
        guard let s = selected, s.isTrimmed else { return }
        setWindow(s, start: nil, end: nil)
    }

    func setWindow(_ s: SessionItem, start: Double?, end: Double?) {
        if let a = start, let b = end, b - a < 5 {
            status = "El fin debe quedar al menos 5 s después del inicio: mueve el cursor y vuelve a marcar."
            return
        }
        stopPlay()
        s.applyWindow(start, end, SpeedSmoother.Parameters(jerkDensity: settings.jerkDensity))
        if s.isTrimmed, let ws = s.windowStart, let we = s.windowEnd {
            shellState.windows[s.id] = ShellWindowEntry(start: ws, end: we)
        } else {
            shellState.windows.removeValue(forKey: s.id)
        }
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.withoutEscapingSlashes]
            try AvoFiles.writeAtomic(try enc.encode(shellState.windows), to: windowsFile)
        } catch {
            log.warn("recortes", error.localizedDescription, error)
        }
        status = s.isTrimmed ? s.windowText + " (el archivo original no se modifica)" : "Se analiza el archivo completo"
        if s === selected {
            rangeStart = .nan
            rangeEnd = .nan
            chartXMin = .nan
            chartXMax = .nan
            if cursorTime.isFinite && s.timeline.count > 1 {
                cursorTime = min(max(cursorTime, s.timeline.t[0]), s.timeline.t[s.timeline.count - 1])
            }
            notifySessionChanged()
        } else {
            compare?.sessionChanged()
        }
    }

    // ------------------------------------------------------------------ home
    var sessionCount: Int { sessions.count }
    var totalDistanceText: String {
        var sum: Double = 0
        for s in sessions where !s.isSynthetic { sum += s.distanceKmValue }
        return DotNetFormat.custom(sum, "0.0", spanish: true) + " km"
    }
    var demoDistanceText: String {
        var sum: Double = 0
        for s in sessions where s.isSynthetic { sum += s.distanceKmValue }
        return DotNetFormat.custom(sum, "0.0", spanish: true) + " km"
    }
    var hasDemo: Bool { sessions.contains(where: { $0.isSynthetic }) }
    var bestSpeedText: String {
        if sessions.isEmpty { return "—" }
        var best: Double = -Double.infinity
        for s in sessions { best = max(best, s.maxSpeedKmh) }
        return DotNetFormat.custom(best, "0.0", spanish: true) + " km/h"
    }
    var recentSessions: [SessionItem] { Array(AppModel.byDateDescending(sessions).prefix(6)) }

    /// Horses with most trainings (at most 8), like Windows RefreshHome.
    var horses: [HomeHorseCard] {
        var groups: [String: [SessionItem]] = [:]
        var order: [String] = []
        for s in sessions {
            if groups[s.horse] == nil { order.append(s.horse) }
            groups[s.horse, default: []].append(s)
        }
        let sorted: [String] = order.enumerated().sorted { (a: (offset: Int, element: String), b: (offset: Int, element: String)) -> Bool in
            let ca: Int = groups[a.element]?.count ?? 0
            let cb: Int = groups[b.element]?.count ?? 0
            return ca != cb ? ca > cb : a.offset < b.offset
        }.map { $0.element }
        var cards: [HomeHorseCard] = []
        for name in sorted.prefix(8) {
            let list: [SessionItem] = groups[name] ?? []
            var last: Date? = nil
            var best: Double = -Double.infinity
            for s in list {
                if let d = s.start, last == nil || d > last! { last = d }
                best = max(best, s.maxSpeedKmh)
            }
            cards.append(HomeHorseCard(name: name, sessions: list.count,
                                       lastDate: last.map { MadridTime.format($0, "dd/MM/yyyy") } ?? "—",
                                       bestSpeed: DotNetFormat.custom(best.isFinite ? best : 0, "0.0", spanish: true) + " km/h"))
        }
        return cards
    }

    // ------------------------------------------------------------------ session panels (Windows RefreshSessionPanels)
    var sessionHeaderTitle: String {
        guard let s = selected else { return "Sin entrenamiento seleccionado" }
        return "Entrenamiento \(s.dateTimeText)"
    }
    var sessionHeaderSubtitle: String {
        guard let s = selected else { return "Importa un archivo .avo o .avr" }
        return "\(s.horse) · \(s.rider) · \(s.discipline)"
    }
    var engineStateText: String { selected?.engineState ?? "—" }

    var sessionStatsRows: [ShellRow] {
        guard let s = selected else { return [] }
        var rows: [ShellRow] = []
        rows.append(ShellRow(key: "Caballo", value: s.horse))
        rows.append(ShellRow(key: "Jinete", value: s.rider))
        rows.append(ShellRow(key: "Modalidad", value: s.discipline))
        rows.append(ShellRow(key: "Fecha", value: s.dateTimeText))
        rows.append(ShellRow(key: "Zona horaria", value: s.start.map { "Europe/Madrid · " + MadridTime.zoneLabel($0) } ?? "—"))
        rows.append(ShellRow(key: "Duración", value: s.durationText))
        rows.append(ShellRow(key: "Distancia", value: s.distanceText))
        rows.append(ShellRow(key: "Datos", value: s.kind))
        return rows
    }

    /// Percentage of received epochs per GNSS solution (whole file, as Windows).
    var gnssDistribution: [GnssSolution: Double] {
        guard let s = selected else { return [:] }
        return GnssQuality.distribution(s.session.gnssEpochs)
    }

    var gnssStatsRows: [ShellRow] {
        guard let s = selected else { return [] }
        let tl: SessionTimeline = s.timeline
        let dist: [GnssSolution: Double] = GnssQuality.distribution(s.session.gnssEpochs)
        func pct(_ k: GnssSolution) -> String { DotNetFormat.custom(dist[k] ?? 0, "0.0", spanish: true) + " %" }
        var rows: [ShellRow] = []
        rows.append(ShellRow(key: "RTK FIX", value: pct(.rtkFix)))
        rows.append(ShellRow(key: "RTK FLOAT", value: pct(.rtkFloat)))
        rows.append(ShellRow(key: "DGNSS", value: pct(.dgnss)))
        rows.append(ShellRow(key: "Autónomo", value: pct(.autonomous)))
        rows.append(ShellRow(key: "Sin solución válida", value: pct(.none)))
        rows.append(ShellRow(key: "Satélites (mediana)",
                             value: tl.count > 0 ? DotNetFormat.custom(Stats.median(tl.numSv.map { Double($0) }), "0", spanish: true) : "—"))
        rows.append(ShellRow(key: "hAcc reportada (mediana)",
                             value: tl.count > 0 ? DotNetFormat.custom(Stats.median(tl.hAcc), "0.000", spanish: true) + " m" : "—"))
        var lossSum: Double = 0
        for l in tl.losses { lossSum += l.durationS }
        rows.append(ShellRow(key: "Pérdidas de señal", value: "\(tl.losses.count) · \(TimeText.clock(lossSum))"))
        rows.append(ShellRow(key: "Saltos descartados", value: "\(tl.jumpBefore.filter { $0 }.count)"))
        rows.append(ShellRow(key: "Frecuencia GNSS",
                             value: tl.nominalDtS > 0 ? DotNetFormat.custom(1 / tl.nominalDtS, "0.#", spanish: true) + " Hz" : "—"))
        return rows
    }

    var sensorStatusRows: [ShellRow] {
        guard let s = selected else { return [] }
        return [
            ShellRow(key: "Cincha IMU", value: s.girthText),
            ShellRow(key: "Marcadores", value: "\(s.session.markers.count)"),
            ShellRow(key: "Integridad", value: s.integrity),
        ]
    }

    // ------------------------------------------------------------------ settings
    func saveSettings() {
        do { try settings.save(paths.settingsFile) } catch { log.warn("ajustes", error.localizedDescription, error) }
    }

    // ------------------------------------------------------------------ capture mode (CI screenshots)
    @MainActor
    private func runCapture() async {
        captureMode = true
        await loadDemo()
        await runEngineForAll()
        await races.importDemoForCapture()   // sample race linked to the DEMO horse (DEMOSTRACIÓN)
        let regaton: [SessionItem] = AppModel.byDateDescending(sessions.filter { $0.id.hasPrefix("DEMO_REGATON") })
        let main: SessionItem? = regaton.first(where: { $0.id == "DEMO_REGATON_20261022" })
            ?? regaton.first(where: { $0.hasGirth }) ?? regaton.first ?? AppModel.byDateDescending(sessions).first
        if let m = main {
            select(m)
            let tl: SessionTimeline = m.timeline
            if tl.count > 1 {
                let t0: Double = tl.t[0]
                rangeStart = t0 + tl.durationS * 0.50
                rangeEnd = t0 + tl.durationS * 0.66
                cursorTime = t0 + tl.durationS * 0.58
            }
            notifySessionChanged()
        }
        page = .home
        captureReady = true
        log.info("captura", "Listo", ["sesiones": sessions.count])
    }
}
