import SwiftUI
import Observation

/// Export formats of the Reports page (Windows ExportPdf/Html/Csv/Gpx/JsonCommand).
enum ReportExportKind: String, CaseIterable, Identifiable {
    case pdf, html, csv, gpx, json
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pdf: return "Informe PDF"
        case .html: return "HTML"
        case .csv: return "CSV"
        case .gpx: return "GPX"
        case .json: return "JSON"
        }
    }
    var icon: String {
        switch self {
        case .pdf: return "doc.richtext"
        case .html: return "doc.text"
        case .csv: return "tablecells"
        case .gpx: return "map"
        case .json: return "curlybraces"
        }
    }
}

/// Preview of the report: printable HTML (WKWebView) or the generated PDF (PDFKit).
enum ReportPreviewMode: String, CaseIterable, Identifiable {
    case html = "HTML"
    case pdf = "PDF"
    var id: String { rawValue }
}

/// File written to paths.root/exportaciones, offered to the share sheet (Files, AirDrop, Mail…).
struct ExportedFile: Identifiable, Equatable {
    let id: String
    var url: URL
    var name: String
    var kind: ReportExportKind
    var time: String
}

/// Port of windows/AVO.Windows/ViewModels/MainViewModel.Reports.cs (reports part; the server part lives in ServerView).
@Observable
final class ReportsModel {
    unowned let app: AppModel

    // sections (Windows defaults: everything except Comparativas; iPad: «Datos GPS» also off)
    var general: Bool = true { didSet { schedulePreview() } }
    var horseRider: Bool = true { didSet { schedulePreview() } }
    var date: Bool = true { didSet { schedulePreview() } }
    var map: Bool = true { didSet { schedulePreview() } }
    /// «Datos GPS» (GNSS/RTK statistics of the vest): off by default, the GPS data have their own page.
    var gnss: Bool = false { didSet { schedulePreview() } }
    var speed: Bool = true { didSet { schedulePreview() } }
    var charts: Bool = true { didSet { schedulePreview() } }
    var segments: Bool = true { didSet { schedulePreview() } }
    var biomech: Bool = true { didSet { schedulePreview() } }
    var compare: Bool = false { didSet { schedulePreview() } }
    var tides: Bool = true { didSet { schedulePreview() } }
    var notesSection: Bool = true { didSet { schedulePreview() } }
    var aiSection: Bool = true { didSet { schedulePreview() } }

    /// Notes of the selected session being edited (saved on «Guardar notas», focus loss or leaving the page).
    var notesDraft: String = ""
    var previewMode: ReportPreviewMode = .html { didSet { if oldValue != previewMode { schedulePreview() } } }
    var previewHtml: String = ""
    var previewPdf: Data? = nil
    var previewBusy: Bool = false
    var previewRows: [FeatureKV] = []
    var lastExport: ExportedFile? = nil
    var exports: [ExportedFile] = []
    /// Set after an export: RootView-independent share sheet presented by ReportsView.
    var shareFile: ExportedFile? = nil
    var exporting: Bool = false

    @ObservationIgnored private var previewRequest: Int = 0
    @ObservationIgnored private var notesFor: String? = nil

    init(app: AppModel) {
        self.app = app
    }

    var exportDir: String { AvoFiles.join(app.paths.root, "exportaciones") }

    // ------------------------------------------------------------------ satellite picture of the route
    @ObservationIgnored private var routeImage: RouteImage? = nil
    @ObservationIgnored private var routeImageFor: String = ""
    @ObservationIgnored private var routeImageBusy: Bool = false

    /// Makes (once per training) the satellite picture of the route for «Mapa del recorrido».
    @MainActor
    func ensureRouteImage() async {
        guard let s = app.selected, map else { return }
        if routeImageFor == s.id || routeImageBusy { return }
        routeImageBusy = true
        let im: RouteImage? = await RouteImageRenderer.render(s.timeline, widthPt: PdfDocument.a4Width - 80, heightPt: 280,
                                                             cacheDir: app.paths.tiles)
        routeImageBusy = false
        if app.selected?.id == s.id {
            routeImage = im
            routeImageFor = s.id
        }
    }

    var previewTitle: String {
        if let s = app.selected { return "Informe de entrenamiento · \(s.dateText)" }
        return "Informe de entrenamiento"
    }

    // ------------------------------------------------------------------ contract
    func sessionChanged() {
        loadNotes()
        refreshPreviewRows()
        if app.page == .reports { schedulePreview(immediate: true) }
    }

    func pageShown() {
        loadNotes()
        refreshPreviewRows()
        schedulePreview(immediate: true)
        loadExportList()
    }

    // ------------------------------------------------------------------ sections / data
    func selectedSections() -> ReportSections {
        var r: ReportSections = .none
        if general { r.insert(.general) }
        if horseRider { r.insert(.horseRider) }
        if date { r.insert(.dateDuration) }
        if map { r.insert(.map) }
        if gnss { r.insert(.gnssStats) }
        if speed { r.insert(.speedAccel) }
        if charts { r.insert(.charts) }
        if segments { r.insert(.segments) }
        if biomech { r.insert(.biomechanics) }
        if compare { r.insert(.comparison) }
        if tides { r.insert(.tides) }
        if notesSection { r.insert(.notes) }
        if aiSection { r.insert(.ai) }
        return r
    }

    func buildReportData() -> ReportData? {
        guard let s = app.selected else { return nil }
        let defs: [SegmentDefinition] = s.segmentDefs.enumerated().sorted { (a: (offset: Int, element: SegmentDefinition), b: (offset: Int, element: SegmentDefinition)) -> Bool in
            a.element.t0 != b.element.t0 ? a.element.t0 < b.element.t0 : a.offset < b.offset
        }.map { $0.element }
        let metrics: [SegmentMetrics] = defs.map { SegmentAnalyzer.compute(s.timeline, $0, engine: s.engine, engineOffsetS: s.engineOffsetS) }
        var comparison: [SeriesAligner.SessionSummary] = []
        if compare {
            for x in app.sessions where x.isCompared {
                comparison.append(SeriesAligner.summarize("\(x.horse) · \(x.dateText)", x.timeline, x.engine, x.engineOffsetS))
            }
        }
        let env: EnvironmentModel = app.environment
        let envOk: Bool = env.loadedFor == s.id
        var d = ReportData(session: s.session, timeline: s.timeline, engine: s.engine, segments: metrics, comparison: comparison,
                           tides: envOk ? env.tides : nil, weather: envOk ? env.weather : nil, notes: s.notes, sections: selectedSections())
        if routeImageFor == s.id { d.routeImage = routeImage }
        d.aiSections = app.stretch.aiAnalyses(for: s)
        return d
    }

    private func refreshPreviewRows() {
        var rows: [FeatureKV] = []
        if let s = app.selected {
            rows.add("Caballo", s.horse)
            rows.add("Jinete", s.rider)
            rows.add("Disciplina", s.discipline)
            rows.add("Duración", s.durationText)
            rows.add("Distancia", s.distanceText)
            rows.add("Vel. máxima", s.maxSpeedText)
        }
        previewRows = rows
    }

    // ------------------------------------------------------------------ preview
    /// Regenerates the preview off the main thread; toggles in quick succession produce a single build.
    func schedulePreview(immediate: Bool = false) {
        if app.page != .reports && !immediate { return }
        previewRequest += 1
        let req: Int = previewRequest
        guard let data = buildReportData() else {
            previewHtml = ""
            previewPdf = nil
            previewBusy = false
            return
        }
        if map, let s = app.selected, routeImageFor != s.id, !routeImageBusy {
            // the preview is shown at once with the plain drawing and again when the satellite picture is ready
            Task { @MainActor [weak self] in
                await self?.ensureRouteImage()
                if self?.app.page == .reports { self?.schedulePreview(immediate: true) }
            }
        }
        let mode: ReportPreviewMode = previewMode
        previewBusy = true
        let model: ReportsModel = self
        Task.detached(priority: .userInitiated) {
            if !immediate { try? await Task.sleep(nanoseconds: 250_000_000) }
            let current: Int = await MainActor.run { model.previewRequest }
            if current != req { return }
            var html: String = ""
            var pdf: Data? = nil
            if mode == .html { html = ReportBuilder.html(data) } else { pdf = ReportBuilder.writePdf(data) }
            await MainActor.run {
                if model.previewRequest != req { return }
                if mode == .html { model.previewHtml = html } else { model.previewPdf = pdf }
                model.previewBusy = false
            }
        }
    }

    // ------------------------------------------------------------------ notes
    private func notesPath(_ s: SessionItem) -> String {
        let base: String = ((app.segmentStore.pathFor(s.id) as NSString).lastPathComponent as NSString).deletingPathExtension
        return AvoFiles.join(app.paths.notes, base + ".txt")
    }

    private func loadNotes() {
        guard let s = app.selected else {
            notesFor = nil
            if !notesDraft.isEmpty { notesDraft = "" }
            return
        }
        if notesFor == s.id { return }
        if s.notes.isEmpty, let data = AvoFiles.read(notesPath(s)) {
            s.notes = String(decoding: data, as: UTF8.self)
        }
        notesFor = s.id
        notesDraft = s.notes
    }

    /// Windows SessionNotes setter: stored on the session and in notas/<id>.txt (UTF-8 without BOM).
    func saveNotes() {
        guard let s = app.selected, notesFor == s.id else { return }
        if s.notes == notesDraft { return }
        s.notes = notesDraft
        do {
            AvoFiles.ensureDir(app.paths.notes)
            try AvoFiles.writeAtomic(Data(notesDraft.utf8), to: notesPath(s))
        } catch {
            app.log.warn("notas", error.localizedDescription, error)
        }
        if notesSection { schedulePreview() }
    }

    // ------------------------------------------------------------------ export
    private var rangeT0: Double {
        app.hasRange ? min(app.rangeStart, app.rangeEnd) : -Double.infinity
    }
    private var rangeT1: Double {
        app.hasRange ? max(app.rangeStart, app.rangeEnd) : Double.infinity
    }

    /// Writes AVO_<id>.<ext> in paths.root/exportaciones and opens the share sheet (save to Files, AirDrop, Mail…).
    @MainActor
    func export(_ kind: ReportExportKind) async {
        saveNotes()
        if kind == .pdf || kind == .html { await ensureRouteImage() }
        guard let data = buildReportData() else {
            app.show("Exportar", "Selecciona un entrenamiento.")
            return
        }
        guard let item = app.selected else { return }
        // «<Caballo>_<fecha>_<hora>_Completo» (CSV and GPX of a selected interval: «…_Tramo_<inicio>-<fin>»)
        let ranged: Bool = app.hasRange && (kind == .csv || kind == .gpx)
        let what: String = ranged ? ExportNaming.rangeKind(app.rangeStart, app.rangeEnd) : "Completo"
        let name: String = ExportNaming.name(item, what, kind.rawValue)
        let dir: String = exportDir
        let path: String = AvoFiles.join(dir, name)
        let t0: Double = rangeT0
        let t1: Double = rangeT1
        exporting = true
        app.busy = true
        defer { exporting = false; app.busy = false }
        do {
            try await Task.detached(priority: .userInitiated) { () throws -> Void in
                AvoFiles.ensureDir(dir)
                switch kind {
                case .pdf: try ReportBuilder.writePdf(data, to: path)
                case .html: try ReportBuilder.writeHtml(data, to: path)
                case .csv: try AnalysisExport.timelineCsv(data.timeline, path, t0: t0, t1: t1)
                case .gpx: try AnalysisExport.gpx(data.session, data.timeline, path, t0: t0, t1: t1)
                case .json: try AnalysisExport.writeJson(data.session, data.timeline, data.segments, data.engine, true, to: path)
                }
            }.value
            let file = ExportedFile(id: path + "|" + String(Date().timeIntervalSince1970), url: URL(fileURLWithPath: path), name: name,
                                    kind: kind, time: AvoTime.text(Date(), "HH:mm"))
            lastExport = file
            exports.removeAll { $0.url == file.url }
            exports.insert(file, at: 0)
            app.status = "Exportado: " + path
            app.log.info("exportar", "Exportado", ["archivo": name])
            shareFile = file
        } catch {
            let msg: String = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            app.log.error("ui", msg, error)
            app.status = "Error: " + msg
            app.show("AVO Performance Horse", msg, error: true)
        }
    }

    /// Files already in exportaciones (newest first), so earlier exports can be shared again.
    func loadExportList() {
        let dir: String = exportDir
        var list: [(ExportedFile, Date)] = []
        for p in AvoFiles.list(dir) {
            let ext: String = (p as NSString).pathExtension.lowercased()
            guard let kind = ReportExportKind(rawValue: ext) else { continue }
            let full: String = p.hasPrefix("/") ? p : AvoFiles.join(dir, p)
            let attrs = try? FileManager.default.attributesOfItem(atPath: full)
            let modified: Date = (attrs?[.modificationDate] as? Date) ?? Date.distantPast
            list.append((ExportedFile(id: full, url: URL(fileURLWithPath: full), name: (full as NSString).lastPathComponent, kind: kind,
                                      time: AvoTime.text(modified, "dd/MM HH:mm")), modified))
        }
        list.sort { (a: (ExportedFile, Date), b: (ExportedFile, Date)) -> Bool in a.1 > b.1 }
        exports = Array(list.prefix(20)).map { $0.0 }
        if lastExport == nil { lastExport = exports.first }
    }
}
