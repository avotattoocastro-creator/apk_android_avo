import SwiftUI
import Observation
import CoreLocation

/// Row of the comparison table (Windows CompareRow).
struct CompareRow: Identifiable {
    let id: String
    var label: String
    var color: Color
    var date: String
    var distance: String
    var duration: String
    var meanSpeed: String
    var maxSpeed: String
    var maxAccel: String
    var cadence: String
}

/// Route of one compared session, split at gaps / rejected jumps (drawn with MapKit).
struct CompareTrack: Identifiable {
    let id: String
    var label: String
    var color: Color
    var runs: [[CLLocationCoordinate2D]]
}

/// Aligned series of one compared session at full resolution (common axis of the comparison). The drawn
/// `FeatureLineSeries` are rebuilt from it for the visible x window, so zooming in shows the real detail.
struct CompareRawSeries {
    var id: String
    var name: String
    var color: Color
    var x: [Double]
    var y: [Double]
    var unit: String
    var format: String
    var width: Double
    var dashed: Bool

    init(id: String, name: String, color: Color, x: [Double], y: [Double], unit: String, format: String = "0.0",
         width: Double = 1.3, dashed: Bool = false) {
        self.id = id
        self.name = name
        self.color = color
        self.x = x
        self.y = y
        self.unit = unit
        self.format = format
        self.width = width
        self.dashed = dashed
    }

    var lastX: Double { x.isEmpty ? 0 : x[x.count - 1] }

    /// Drawn series for x[lo..<hi] (reduced with LTTB for drawing only).
    func make(_ lo: Int, _ hi: Int) -> FeatureLineSeries {
        let a: Int = min(max(lo, 0), x.count)
        let b: Int = min(max(hi, a), min(x.count, y.count))
        let xs: [Double] = Array(x[a..<b])
        let ys: [Double] = Array(y[a..<max(a, min(b, y.count))])
        return FeatureLineSeries(id: id, name: name, color: color, x: xs, y: ys, unit: unit, format: format, width: width,
                                 dashed: dashed, maxPoints: 900)
    }
}

/// One row of the «Tramo seleccionado» card: the aligned range mapped back to one session's own timeline.
struct CompareRangeRow: Identifiable {
    let id: String
    var label: String
    var color: Color
    /// Session timeline times of the mapped interval (NaN when the session does not reach the range).
    var t0: Double
    var t1: Double
    var distance: String
    var duration: String
    var meanSpeed: String
    var maxSpeed: String
    var maxAccel: String
    var maxDecel: String
    var observations: String
}

/// Port of windows/AVO.Windows/ViewModels/MainViewModel.Compare.cs.
/// iPad additions: one shared x window (zoom) for every compare chart, a selected range on the aligned axis
/// (relative seconds or metres from the start) mapped back to each session, and «Guardar como tramo» for all of them.
@Observable
final class CompareModel {
    unowned let app: AppModel

    static let palette: [Color] = [
        Color(hex: 0x3D9BFF), Color(hex: 0xFFC42C), Color(hex: 0xED122A), Color(hex: 0x52DD40),
        Color(hex: 0x35D0E8), Color(hex: 0xA86BFF), Color(hex: 0xC9CBD1),
    ]

    var rows: [CompareRow] = []
    var tracks: [CompareTrack] = []
    /// Drawn series for the current x window (rebuilt from the raw aligned series after zoom / pan).
    var speedSeries: [FeatureLineSeries] = []
    var accelSeries: [FeatureLineSeries] = []
    /// Girth IMU comparisons (CompareImuSeries): lateral deviation and tilts; cadence from the engine.
    var lateralSeries: [FeatureLineSeries] = []
    var tiltSeries: [FeatureLineSeries] = []
    var cadenceSeries: [FeatureLineSeries] = []
    /// «fecha · caballo» of the compared sessions without girth IMU data.
    var imuMissing: [String] = []
    var imuSources: [String] = []
    var cadenceMissing: [String] = []
    var alignment: AlignmentMode = .relativeTime {
        didSet {
            if oldValue != alignment {
                // the aligned axis changes unit (s ↔ m): zoom and range no longer mean anything
                clearViewState()
                refresh()
            }
        }
    }
    var axis: FeatureAxis { alignment == .distance ? .kilometres : .clock }
    var verdict: String = "Marca dos o más entrenamientos para compararlos."
    var engineRows: [EngineDiffRow] = []
    var engineBusy: Bool = false
    var computing: Bool = false

    /// «Ocultar entrenamientos sin recorrido (0 km)»: hides them from the list and leaves them out of the comparison.
    var hideEmpty: Bool = true {
        didSet { if oldValue != hideEmpty { refresh() } }
    }

    // ---- shared x window (aligned axis: relative s or distance m). NaN = whole comparison.
    var xMin: Double = .nan
    var xMax: Double = .nan
    /// End of the aligned axis (longest compared session).
    private(set) var fullHi: Double = 0
    let fullLo: Double = 0

    // ---- selected range on the aligned axis (NaN = none)
    var rangeStart: Double = .nan
    var rangeEnd: Double = .nan
    /// «Seleccionar rango»: a drag on a chart selects (and the page does not scroll).
    var rangeMode: Bool = false
    var rangeRows: [CompareRangeRow] = []
    /// Selected part of each compared route (map highlight).
    var rangeTracks: [CompareTrack] = []
    var rangeMessage: String = ""

    @ObservationIgnored private var request: Int = 0
    @ObservationIgnored private var coloredCount: Int = -1
    @ObservationIgnored private var comparedIds: [String] = []
    @ObservationIgnored private var rawSpeed: [CompareRawSeries] = []
    @ObservationIgnored private var rawAccel: [CompareRawSeries] = []
    @ObservationIgnored private var rawLateral: [CompareRawSeries] = []
    @ObservationIgnored private var rawTilt: [CompareRawSeries] = []
    @ObservationIgnored private var rawCadence: [CompareRawSeries] = []

    init(app: AppModel) {
        self.app = app
    }

    // ------------------------------------------------------------------ contract
    func sessionChanged() {
        assignColorsIfNeeded()
        if pairId != nil {
            // «Entreno 2» de Análisis: el entreno 1 es siempre el activo
            setPair(pairId)
            return
        }
        if app.page == .compare { refresh() }
    }

    // ------------------------------------------------------------------ «Entreno 1 | Entreno 2» (Análisis)
    /// Segundo entrenamiento elegido en la barra del entrenamiento. nil = Análisis de un solo entrenamiento.
    /// Con pareja, la comparación contiene SOLO el entrenamiento activo (azul) y este (amarillo).
    var pairId: String? = nil

    var pairSession: SessionItem? {
        guard let id = pairId else { return nil }
        return app.sessions.first { $0.id == id }
    }

    var isPaired: Bool { pairSession != nil && app.selected != nil }

    static let pairColors: (first: Color, second: Color) = (Color(hex: 0x3D9BFF), Color(hex: 0xFFC42C))

    func setPair(_ id: String?) {
        guard let id = id, let first = app.selected, id != first.id,
              let second = app.sessions.first(where: { $0.id == id }) else {
            pairId = nil
            return
        }
        pairId = id
        for s in app.sessions { s.isCompared = s.id == first.id || s.id == second.id }
        assignColorsIfNeeded()
        first.compareColor = CompareModel.pairColors.first
        second.compareColor = CompareModel.pairColors.second
        refresh()
    }

    func pageShown() {
        assignColorsIfNeeded()
        refresh()
    }

    // ------------------------------------------------------------------ colours / selection
    /// A session «sin recorrido»: shown as 0,00 km.
    static func hasRoute(_ s: SessionItem) -> Bool { s.distanceKmValue >= 0.005 }

    /// Sessions shown in the list (all, or only those with a route).
    func listed(_ all: [SessionItem]) -> [SessionItem] {
        if !hideEmpty { return all }
        return all.filter { CompareModel.hasRoute($0) }
    }

    /// Windows AssignCompareColors: palette by date (newest first); with nothing marked, the three newest are compared
    /// (with «Ocultar entrenamientos sin recorrido», the three newest with a route).
    func assignColors() {
        let ordered: [SessionItem] = CompareModel.byDateDescending(app.sessions)
        var k: Int = 0
        for s in ordered {
            s.compareColor = CompareModel.palette[k % CompareModel.palette.count]
            k += 1
        }
        if !app.sessions.contains(where: { $0.isCompared }) {
            let candidates: [SessionItem] = hideEmpty ? ordered.filter { CompareModel.hasRoute($0) } : ordered
            for s in candidates.prefix(3) { s.isCompared = true }
        }
        coloredCount = app.sessions.count
    }

    /// Called on page show / session change: the shell assigns nothing, so colours follow the list of loaded sessions.
    func assignColorsIfNeeded() {
        if coloredCount != app.sessions.count { assignColors() }
    }

    func toggle(_ s: SessionItem) {
        s.isCompared.toggle()
        refresh()
    }

    /// OrderByDescending(s => s.Start): stable, sessions without date last.
    static func byDateDescending(_ list: [SessionItem]) -> [SessionItem] {
        let indexed: [(i: Int, s: SessionItem)] = list.enumerated().map { (i: $0.offset, s: $0.element) }
        let sorted = indexed.sorted { (a: (i: Int, s: SessionItem), b: (i: Int, s: SessionItem)) -> Bool in
            let da: Date? = a.s.start
            let db: Date? = b.s.start
            if let x = da, let y = db {
                if x != y { return x > y }
                return a.i < b.i
            }
            if da != nil && db == nil { return true }
            if da == nil && db != nil { return false }
            return a.i < b.i
        }
        return sorted.map { $0.s }
    }

    // ------------------------------------------------------------------ comparison
    private struct Input {
        var id: String
        var label: String
        var summaryLabel: String
        var color: Color
        var dateText: String
        var dateTimeText: String
        var timeline: SessionTimeline
        var engine: EquineAnalysis?
        var offset: Double
        var session: TrainingSession
        var imu: ImuTimeline
    }

    private struct Output {
        var rows: [CompareRow]
        var tracks: [CompareTrack]
        var speed: [CompareRawSeries]
        var accel: [CompareRawSeries]
        var lateral: [CompareRawSeries]
        var tilt: [CompareRawSeries]
        var cadence: [CompareRawSeries]
        var imuMissing: [String]
        var imuSources: [String]
        var cadenceMissing: [String]
    }

    func refresh() {
        let hide: Bool = hideEmpty
        let picked: [SessionItem] = CompareModel.byDateDescending(app.sessions.filter { (s: SessionItem) -> Bool in
            s.isCompared && s.timeline.count > 1 && (!hide || CompareModel.hasRoute(s))
        })
        let ids: [String] = picked.map { $0.id }
        if ids != comparedIds {
            // another set of sessions: the old window / range belong to a different axis length
            comparedIds = ids
            clearViewState()
        }
        let inputs: [Input] = picked.map { (s: SessionItem) -> Input in
            Input(id: s.id, label: "\(s.horse) · \(s.rider)", summaryLabel: s.summary, color: s.compareColor, dateText: s.dateText,
                  dateTimeText: s.dateTimeText, timeline: s.timeline, engine: s.engine, offset: s.engineOffsetS,
                  session: s.session, imu: s.imu)
        }
        let mode: AlignmentMode = alignment
        request += 1
        let req: Int = request
        if inputs.isEmpty {
            rows = []; tracks = []
            rawSpeed = []; rawAccel = []; rawLateral = []; rawTilt = []; rawCadence = []
            speedSeries = []; accelSeries = []
            lateralSeries = []; tiltSeries = []; cadenceSeries = []; imuMissing = []; imuSources = []; cadenceMissing = []
            fullHi = 0
            rangeRows = []; rangeTracks = []
            computing = false
            return
        }
        computing = true
        let model: CompareModel = self
        Task.detached(priority: .userInitiated) {
            let out: Output = CompareModel.compute(inputs, mode)
            await MainActor.run {
                if model.request != req { return }
                model.rows = out.rows
                model.tracks = out.tracks
                model.rawSpeed = out.speed
                model.rawAccel = out.accel
                model.rawLateral = out.lateral
                model.rawTilt = out.tilt
                model.rawCadence = out.cadence
                model.imuMissing = out.imuMissing
                model.imuSources = out.imuSources
                model.cadenceMissing = out.cadenceMissing
                model.updateFullRange()
                model.rebuildVisible()
                model.refreshRangeStats()
                model.computing = false
                if model.verdict.hasPrefix("Marca") || model.verdict.hasPrefix("Comparando") {
                    model.verdict = "\(inputs.count) entrenamientos alineados por \(mode == .distance ? "distancia recorrida" : "tiempo relativo"). " +
                        "Las series no se interpolan a través de huecos sin datos. La correspondencia espacial se comprueba con el motor (botón «Comparar con el motor»)."
                }
            }
        }
    }

    // ------------------------------------------------------------------ shared x window (zoom / pan)
    private func clearViewState() {
        xMin = .nan
        xMax = .nan
        rangeStart = .nan
        rangeEnd = .nan
        rangeRows = []
        rangeTracks = []
        rangeMessage = ""
    }

    private func updateFullRange() {
        var hi: Double = 0
        for list in [rawSpeed, rawAccel, rawLateral, rawTilt, rawCadence] {
            for r in list { hi = max(hi, r.lastX) }
        }
        fullHi = hi
        if isZoomed && (xMin >= fullHi || xMax > fullHi * 1.0001) {
            xMin = .nan
            xMax = .nan
        }
    }

    var isZoomed: Bool { xMin.isFinite && xMax.isFinite }

    /// Current x window: the zoom or the whole comparison.
    var domain: ClosedRange<Double> {
        var lo: Double = xMin.isFinite ? xMin : fullLo
        var hi: Double = xMax.isFinite ? xMax : fullHi
        if !lo.isFinite { lo = 0 }
        if !hi.isFinite || hi <= lo { hi = lo + 1 }
        return lo...hi
    }

    /// Smallest window: 5 s or 20 m.
    private var minWidth: Double { alignment == .distance ? 20 : 5 }

    /// Sets the shared x window, clamped to the comparison; the whole comparison resets the zoom (NaN).
    func setViewport(_ lo: Double, _ hi: Double, rebuild: Bool = true) {
        let full: Double = fullHi - fullLo
        guard full > 0, lo.isFinite, hi.isFinite, hi > lo else { return }
        var w: Double = hi - lo
        if w >= full * 0.999 {
            xMin = .nan
            xMax = .nan
        } else {
            w = max(w, min(minWidth, full))
            let a: Double = min(max(lo, fullLo), fullHi - w)
            xMin = a
            xMax = a + w
        }
        if rebuild { rebuildVisible() }
    }

    /// factor > 1 zooms out, < 1 zooms in; centred on the selected range when it is visible, otherwise on the window.
    func zoom(_ factor: Double) {
        let d: ClosedRange<Double> = domain
        var c: Double = (d.lowerBound + d.upperBound) / 2
        if hasRange {
            let m: Double = (rangeStart + rangeEnd) / 2
            if m >= d.lowerBound && m <= d.upperBound { c = m }
        }
        setViewport(c - (c - d.lowerBound) * factor, c + (d.upperBound - c) * factor)
    }

    func pan(_ fraction: Double) {
        if !isZoomed { return }
        let d: ClosedRange<Double> = domain
        let w: Double = d.upperBound - d.lowerBound
        setViewport(d.lowerBound + w * fraction, d.upperBound + w * fraction)
    }

    func resetZoom() {
        xMin = .nan
        xMax = .nan
        rebuildVisible()
    }

    /// Zooms the shared window to the selected range (with a small margin).
    func zoomToRange() {
        if !hasRange { return }
        let a: Double = min(rangeStart, rangeEnd)
        let b: Double = max(rangeStart, rangeEnd)
        let m: Double = (b - a) * 0.1
        setViewport(a - m, b + m)
    }

    /// «07:30 – 12:10» / «0,40 – 1,25 km» of the current window.
    var domainText: String {
        let d: ClosedRange<Double> = domain
        return "\(axisText(d.lowerBound)) – \(axisText(d.upperBound))"
    }

    func axisText(_ v: Double) -> String {
        if alignment == .distance { return DotNetFormat.custom(v / 1000, "0.00", spanish: true) + " km" }
        return TimeText.clock(v)
    }

    /// Rebuilds the drawn series for the current window (whole arrays when not zoomed).
    func rebuildVisible() {
        speedSeries = visible(rawSpeed)
        accelSeries = visible(rawAccel)
        lateralSeries = visible(rawLateral)
        tiltSeries = visible(rawTilt)
        cadenceSeries = visible(rawCadence)
    }

    private func visible(_ list: [CompareRawSeries]) -> [FeatureLineSeries] {
        let zoomed: Bool = isZoomed
        let d: ClosedRange<Double> = domain
        // margin on both sides so a pinch / pan in progress does not show empty borders
        let pad: Double = (d.upperBound - d.lowerBound) * 0.25
        return list.map { (r: CompareRawSeries) -> FeatureLineSeries in
            if !zoomed || r.x.count < 2 { return r.make(0, r.x.count) }
            let i0: Int = max(0, CompareModel.firstIndex(r.x, atLeast: d.lowerBound - pad) - 1)
            let i1: Int = min(r.x.count, CompareModel.firstIndex(r.x, atLeast: d.upperBound + pad) + 1)
            return r.make(i0, i1)
        }
    }

    /// First index with x[i] >= v in an increasing array (x.count when none).
    static func firstIndex(_ x: [Double], atLeast v: Double) -> Int {
        var lo: Int = 0
        var hi: Int = x.count
        while lo < hi {
            let mid: Int = (lo + hi) / 2
            if x[mid] < v { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    // ------------------------------------------------------------------ selected range
    var hasRange: Bool {
        rangeStart.isFinite && rangeEnd.isFinite && abs(rangeEnd - rangeStart) >= (alignment == .distance ? 2 : 0.5)
    }

    /// While dragging (cheap: no statistics).
    func setRange(_ a: Double, _ b: Double) {
        let lo: Double = fullLo
        let hi: Double = max(fullHi, fullLo + 1)
        rangeStart = min(max(a, lo), hi)
        rangeEnd = min(max(b, lo), hi)
    }

    /// End of the drag: too short = no range; otherwise statistics and map highlight.
    func finishRange() {
        if !hasRange {
            rangeStart = .nan
            rangeEnd = .nan
        }
        rangeMessage = ""
        refreshRangeStats()
    }

    func clearRange() {
        rangeStart = .nan
        rangeEnd = .nan
        rangeRows = []
        rangeTracks = []
        rangeMessage = ""
    }

    /// «01:10–02:05» or «0,35–0,80 km» of the selected range.
    var rangeText: String {
        if !hasRange { return "" }
        let a: Double = min(rangeStart, rangeEnd)
        let b: Double = max(rangeStart, rangeEnd)
        if alignment == .distance {
            return DotNetFormat.custom(a / 1000, "0.00", spanish: true) + "–" + DotNetFormat.custom(b / 1000, "0.00", spanish: true) + " km"
        }
        return TimeText.clock(a) + "–" + TimeText.clock(b)
    }

    /// Compared sessions (same order as the charts).
    var comparedSessions: [SessionItem] {
        var out: [SessionItem] = []
        for id in comparedIds {
            if let s = app.sessions.first(where: { $0.id == id }) { out.append(s) }
        }
        return out
    }

    /// Maps the aligned interval [a, b] to the session's own timeline times. Time alignment: same relative seconds from
    /// the first epoch; distance alignment: same distance from the start. nil when the session does not reach it.
    func sessionInterval(_ tl: SessionTimeline, _ a: Double, _ b: Double) -> (t0: Double, t1: Double)? {
        let n: Int = tl.count
        if n < 2 || !(b > a) { return nil }
        if alignment == .relativeTime {
            let start: Double = tl.t[0]
            let end: Double = tl.t[n - 1]
            let t0: Double = max(start + a, start)
            let t1: Double = min(start + b, end)
            if !(t1 > t0) { return nil }
            return (t0: t0, t1: t1)
        }
        var i0: Int = -1
        for i in 0..<n where tl.distance[i].isFinite && tl.distance[i] >= a {
            i0 = i
            break
        }
        if i0 < 0 { return nil }
        var i1: Int = i0
        var i: Int = i0
        while i < n {
            let d: Double = tl.distance[i]
            if d.isFinite {
                if d > b { break }
                i1 = i
            }
            i += 1
        }
        if i1 <= i0 { return nil }
        let t0: Double = tl.t[i0]
        let t1: Double = tl.t[i1]
        if !(t1 > t0) { return nil }
        return (t0: t0, t1: t1)
    }

    /// Statistics of the selected range for each compared session and the highlighted part of each route.
    func refreshRangeStats() {
        if !hasRange {
            rangeRows = []
            rangeTracks = []
            return
        }
        let a: Double = min(rangeStart, rangeEnd)
        let b: Double = max(rangeStart, rangeEnd)
        var rowsOut: [CompareRangeRow] = []
        var tracksOut: [CompareTrack] = []
        for s in comparedSessions {
            let tl: SessionTimeline = s.timeline
            let label: String = "\(s.dateTimeText) · \(s.horse)"
            guard let iv = sessionInterval(tl, a, b) else {
                rowsOut.append(CompareRangeRow(id: s.id, label: label, color: s.compareColor, t0: .nan, t1: .nan,
                                               distance: "—", duration: "—", meanSpeed: "—", maxSpeed: "—", maxAccel: "—",
                                               maxDecel: "—", observations: "El entrenamiento no llega a este tramo"))
                continue
            }
            let seg = SegmentDefinition(name: "", t0: iv.t0, t1: iv.t1)
            let m: SegmentMetrics = SegmentAnalyzer.compute(tl, seg, engine: s.engine, engineOffsetS: s.engineOffsetS)
            let dist: String = m.distanceM >= 1000 ? TimeText.num(m.distanceM / 1000, "0.00", " km") : TimeText.num(m.distanceM, "0", " m")
            rowsOut.append(CompareRangeRow(id: s.id, label: label, color: s.compareColor, t0: iv.t0, t1: iv.t1,
                                           distance: dist, duration: TimeText.clock(m.durationS),
                                           meanSpeed: TimeText.num(m.meanSpeedKmh, "0.0", " km/h"),
                                           maxSpeed: TimeText.num(m.maxSpeedKmh, "0.0", " km/h"),
                                           maxAccel: TimeText.num(m.maxAccel, "0.00", " m/s²"),
                                           maxDecel: TimeText.num(m.maxDecel, "0.00", " m/s²"),
                                           observations: m.observations))
            let runs: [[CLLocationCoordinate2D]] = CompareModel.routeRuns(tl, t0: iv.t0, t1: iv.t1)
            if !runs.isEmpty {
                tracksOut.append(CompareTrack(id: s.id + ".range", label: label, color: s.compareColor, runs: runs))
            }
        }
        rangeRows = rowsOut
        rangeTracks = tracksOut
    }

    /// «Guardar como tramo en los N entrenamientos»: appends a manual SegmentDefinition (the range mapped to each
    /// session) and saves it with the segment store, as the «Tramos» page does. The telemetry is never modified.
    func saveRangeAsSegments() {
        if !hasRange {
            rangeMessage = "Selecciona un tramo en una gráfica (mantén pulsado y arrastra, o «Seleccionar rango»)"
            return
        }
        let a: Double = min(rangeStart, rangeEnd)
        let b: Double = max(rangeStart, rangeEnd)
        let name: String = "Comparación " + rangeText
        let notes: String = "Creado en «Comparar» (alineado por \(alignment == .distance ? "distancia" : "tiempo relativo"), \(rangeText))"
        var saved: Int = 0
        var skipped: Int = 0
        var failed: [String] = []
        for s in comparedSessions {
            guard let iv = sessionInterval(s.timeline, a, b), iv.t1 - iv.t0 > 0.5 else {
                skipped += 1
                continue
            }
            s.segmentDefs.append(SegmentDefinition(name: name, t0: iv.t0, t1: iv.t1, kind: .manual, notes: notes))
            do {
                try app.segmentStore.save(s.session.sessionId, s.segmentDefs)
                saved += 1
            } catch {
                app.log.error("tramos", error.localizedDescription, error)
                failed.append(s.dateTimeText)
            }
        }
        var msg: String = "Tramo «\(name)» guardado en \(saved) entrenamiento\(saved == 1 ? "" : "s")"
        if skipped > 0 { msg += " · \(skipped) no llega\(skipped == 1 ? "" : "n") a este tramo" }
        if !failed.isEmpty { msg += " · no se pudo guardar en " + failed.joined(separator: ", ") }
        msg += " (la telemetría original no se modifica)"
        rangeMessage = msg
        app.status = msg
        app.notifySessionChanged()
    }

    private static func compute(_ inputs: [Input], _ mode: AlignmentMode) -> Output {
        var rows: [CompareRow] = []
        var tracks: [CompareTrack] = []
        for s in inputs {
            let m: SeriesAligner.SessionSummary = SeriesAligner.summarize(s.summaryLabel, s.timeline, s.engine, s.offset)
            rows.append(CompareRow(id: s.id, label: s.label, color: s.color, date: s.dateTimeText,
                                   distance: TimeText.num(m.distanceKm, "0.00", " km"), duration: TimeText.clock(m.durationS),
                                   meanSpeed: TimeText.num(m.meanSpeedKmh, "0.0", " km/h"), maxSpeed: TimeText.num(m.maxSpeedKmh, "0.0", " km/h"),
                                   maxAccel: TimeText.num(m.maxAccel, "0.00", " m/s²"),
                                   cadence: TimeText.num(m.cadence, "0", " /min")))
            tracks.append(CompareTrack(id: s.id, label: s.summaryLabel, color: s.color, runs: routeRuns(s.timeline)))
        }
        let step: Double = mode == .distance ? 5 : 1
        let tls: [SessionTimeline] = inputs.map { $0.timeline }
        let sp: SeriesAligner.Aligned = SeriesAligner.align(tls, { (t: SessionTimeline) -> [Double] in t.speedFiltered }, mode, step)
        let ac: SeriesAligner.Aligned = SeriesAligner.align(tls, { (t: SessionTimeline) -> [Double] in
            var v: [Double] = [Double](repeating: .nan, count: t.count)
            for i in 0..<t.count where SegmentAnalyzer.accelValid(t, i) { v[i] = t.accelLong[i] }
            return v
        }, mode, step)
        var speed: [CompareRawSeries] = []
        var accel: [CompareRawSeries] = []
        for (i, s) in inputs.enumerated() {
            if i < sp.values.count {
                let y: [Double] = sp.values[i].map { $0 * 3.6 }
                speed.append(CompareRawSeries(id: s.id, name: s.dateText, color: s.color, x: sp.axis, y: y, unit: "km/h", width: 1.3))
            }
            if i < ac.values.count {
                accel.append(CompareRawSeries(id: s.id, name: s.dateText, color: s.color, x: ac.axis, y: ac.values[i], unit: "m/s²",
                                               format: "0.00", width: 1.1))
            }
        }
        // girth IMU (resampled per epoch, then aligned like the speed) and engine cadence
        var imuMissing: [String] = []
        var imuSources: [String] = []
        var cadenceMissing: [String] = []
        var imuByTl: [ObjectIdentifier: CompareImuSeries.Result] = [:]
        var cadByTl: [ObjectIdentifier: [Double]] = [:]
        var imuTls: [SessionTimeline] = []
        var imuInputs: [Input] = []
        var cadTls: [SessionTimeline] = []
        var cadInputs: [Input] = []
        for s in inputs {
            let tag: String = "\(s.dateText) · \(s.label)"
            if let r = CompareImuSeries.build(session: s.session, imu: s.imu, timeline: s.timeline) {
                imuByTl[ObjectIdentifier(s.timeline)] = r
                imuTls.append(s.timeline)
                imuInputs.append(s)
                imuSources.append("\(s.dateText): \(r.source)")
            } else {
                imuMissing.append(tag)
            }
            if let c = CompareImuSeries.cadence(s.engine, offset: s.offset, timeline: s.timeline) {
                cadByTl[ObjectIdentifier(s.timeline)] = c
                cadTls.append(s.timeline)
                cadInputs.append(s)
            } else {
                cadenceMissing.append(tag)
            }
        }
        var lateral: [CompareRawSeries] = []
        var tilt: [CompareRawSeries] = []
        if !imuTls.isEmpty {
            func pickImu(_ t: SessionTimeline, _ f: (CompareImuSeries.Result) -> [Double]) -> [Double] {
                guard let r = imuByTl[ObjectIdentifier(t)] else { return [] }
                return f(r)
            }
            let la: SeriesAligner.Aligned = SeriesAligner.align(imuTls, { (t: SessionTimeline) -> [Double] in
                pickImu(t, { $0.lateral })
            }, mode, step)
            let ro: SeriesAligner.Aligned = SeriesAligner.align(imuTls, { (t: SessionTimeline) -> [Double] in
                pickImu(t, { $0.roll })
            }, mode, step)
            let pi: SeriesAligner.Aligned = SeriesAligner.align(imuTls, { (t: SessionTimeline) -> [Double] in
                pickImu(t, { $0.pitch })
            }, mode, step)
            for (i, s) in imuInputs.enumerated() {
                if i < la.values.count {
                    lateral.append(CompareRawSeries(id: s.id + ".lat", name: s.dateText, color: s.color, x: la.axis, y: la.values[i],
                                                     unit: "m/s²", format: "0.00", width: 1.1))
                }
                if i < ro.values.count {
                    tilt.append(CompareRawSeries(id: s.id + ".roll", name: s.dateText + " · lateral", color: s.color, x: ro.axis,
                                                  y: ro.values[i], unit: "°", format: "0.0", width: 1.2))
                }
                if i < pi.values.count {
                    tilt.append(CompareRawSeries(id: s.id + ".pitch", name: s.dateText + " · longitudinal", color: s.color, x: pi.axis,
                                                  y: pi.values[i], unit: "°", format: "0.0", width: 1.0, dashed: true))
                }
            }
        }
        var cadence: [CompareRawSeries] = []
        if !cadTls.isEmpty {
            let ca: SeriesAligner.Aligned = SeriesAligner.align(cadTls, { (t: SessionTimeline) -> [Double] in
                cadByTl[ObjectIdentifier(t)] ?? []
            }, mode, step)
            for (i, s) in cadInputs.enumerated() where i < ca.values.count {
                cadence.append(CompareRawSeries(id: s.id + ".cad", name: s.dateText, color: s.color, x: ca.axis, y: ca.values[i],
                                                 unit: "/min", format: "0", width: 1.2))
            }
        }
        return Output(rows: rows, tracks: tracks, speed: speed, accel: accel, lateral: lateral, tilt: tilt, cadence: cadence,
                      imuMissing: imuMissing, imuSources: imuSources, cadenceMissing: cadenceMissing)
    }

    /// Route split at gaps and rejected jumps, thinned to ≤ 1500 points for drawing.
    /// With t0/t1: only the epochs inside [t0, t1] (selected range highlight).
    private static func routeRuns(_ tl: SessionTimeline, t0: Double = -Double.infinity, t1: Double = Double.infinity) -> [[CLLocationCoordinate2D]] {
        var runs: [[CLLocationCoordinate2D]] = []
        let n: Int = tl.count
        if n < 2 { return runs }
        var first: Int = 0
        var last: Int = n - 1
        if t0.isFinite || t1.isFinite {
            first = n
            last = -1
            for i in 0..<n where tl.t[i] >= t0 && tl.t[i] <= t1 {
                if i < first { first = i }
                last = i
            }
            if last <= first { return runs }
        }
        let every: Int = max(1, (last - first + 1) / 1500)
        var cur: [CLLocationCoordinate2D] = []
        for i in first...last {
            let split: Bool = i > first && (tl.breakBefore[i] || tl.jumpBefore[i])
            if split {
                if cur.count > 1 { runs.append(cur) }
                cur = []
            }
            let la: Double = tl.lat[i]
            let lo: Double = tl.lon[i]
            if !la.isFinite || !lo.isFinite { continue }
            if (i - first) % every == 0 || i == last || split { cur.append(CLLocationCoordinate2D(latitude: la, longitude: lo)) }
        }
        if cur.count > 1 { runs.append(cur) }
        return runs
    }

    // ------------------------------------------------------------------ engine comparison
    /// Windows EngineCompareCommand: the first two marked sessions, same-route check requested.
    @MainActor
    func compareWithEngine() async {
        let picked: [SessionItem] = Array(app.sessions.filter { $0.isCompared }.prefix(2))
        if picked.count < 2 { verdict = "El motor compara dos sesiones: marca dos."; return }
        if !EquineEngine.available { verdict = EquineEngine.unavailableReason ?? "Motor no disponible"; return }
        let a: [String] = picked[0].session.rawSegmentPaths
        let b: [String] = picked[1].session.rawSegmentPaths
        verdict = "Comparando con el motor AVO…"
        engineBusy = true
        defer { engineBusy = false }
        do {
            let opts: String = EquineEngine.options(series: false, cacheDir: nil, force: false, extra: "\"mismo_recorrido\":true")
            let json: String = try await EquineEngine.compareJson(a, b, opts)
            let parsed = try EquineComparisonRows.parse(json)
            engineRows = parsed.rows
            verdict = parsed.verdict
        } catch {
            let msg: String = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            app.log.error("ui", msg, error)
            app.status = "Error: " + msg
            verdict = "Error: " + msg
            app.show("AVO Performance Horse", msg, error: true)
        }
    }
}
