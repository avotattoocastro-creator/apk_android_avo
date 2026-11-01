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
    var fix: String
    var cadence: String
}

/// Route of one compared session, split at signal losses / rejected jumps (drawn with MapKit).
struct CompareTrack: Identifiable {
    let id: String
    var label: String
    var color: Color
    var runs: [[CLLocationCoordinate2D]]
}

/// Port of windows/AVO.Windows/ViewModels/MainViewModel.Compare.cs.
@Observable
final class CompareModel {
    unowned let app: AppModel

    static let palette: [Color] = [
        Color(hex: 0x3D9BFF), Color(hex: 0xFFC42C), Color(hex: 0xED122A), Color(hex: 0x52DD40),
        Color(hex: 0x35D0E8), Color(hex: 0xA86BFF), Color(hex: 0xC9CBD1),
    ]

    var rows: [CompareRow] = []
    var tracks: [CompareTrack] = []
    var speedSeries: [FeatureLineSeries] = []
    var accelSeries: [FeatureLineSeries] = []
    var alignment: AlignmentMode = .relativeTime {
        didSet { if oldValue != alignment { refresh() } }
    }
    var axis: FeatureAxis { alignment == .distance ? .kilometres : .clock }
    var verdict: String = "Marca dos o más entrenamientos para compararlos."
    var engineRows: [EngineDiffRow] = []
    var engineBusy: Bool = false
    var computing: Bool = false

    @ObservationIgnored private var request: Int = 0
    @ObservationIgnored private var coloredCount: Int = -1

    init(app: AppModel) {
        self.app = app
    }

    // ------------------------------------------------------------------ contract
    func sessionChanged() {
        assignColorsIfNeeded()
        if app.page == .compare { refresh() }
    }

    func pageShown() {
        assignColorsIfNeeded()
        refresh()
    }

    // ------------------------------------------------------------------ colours / selection
    /// Windows AssignCompareColors: palette by date (newest first); with nothing marked, the three newest are compared.
    func assignColors() {
        let ordered: [SessionItem] = CompareModel.byDateDescending(app.sessions)
        var k: Int = 0
        for s in ordered {
            s.compareColor = CompareModel.palette[k % CompareModel.palette.count]
            k += 1
        }
        if !app.sessions.contains(where: { $0.isCompared }) {
            for s in ordered.prefix(3) { s.isCompared = true }
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
    }

    private struct Output {
        var rows: [CompareRow]
        var tracks: [CompareTrack]
        var speed: [FeatureLineSeries]
        var accel: [FeatureLineSeries]
    }

    func refresh() {
        let picked: [SessionItem] = CompareModel.byDateDescending(app.sessions.filter { $0.isCompared && $0.timeline.count > 1 })
        let inputs: [Input] = picked.map { (s: SessionItem) -> Input in
            Input(id: s.id, label: "\(s.horse) · \(s.rider)", summaryLabel: s.summary, color: s.compareColor, dateText: s.dateText,
                  dateTimeText: s.dateTimeText, timeline: s.timeline, engine: s.engine, offset: s.engineOffsetS)
        }
        let mode: AlignmentMode = alignment
        request += 1
        let req: Int = request
        if inputs.isEmpty {
            rows = []; tracks = []; speedSeries = []; accelSeries = []
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
                model.speedSeries = out.speed
                model.accelSeries = out.accel
                model.computing = false
                if model.verdict.hasPrefix("Marca") || model.verdict.hasPrefix("Comparando") {
                    model.verdict = "\(inputs.count) entrenamientos alineados por \(mode == .distance ? "distancia recorrida" : "tiempo relativo"). " +
                        "Las series no se interpolan a través de pérdidas de señal. La correspondencia espacial se comprueba con el motor (botón «Comparar con el motor»)."
                }
            }
        }
    }

    private static func compute(_ inputs: [Input], _ mode: AlignmentMode) -> Output {
        var rows: [CompareRow] = []
        var tracks: [CompareTrack] = []
        for s in inputs {
            let m: SeriesAligner.SessionSummary = SeriesAligner.summarize(s.summaryLabel, s.timeline, s.engine, s.offset)
            rows.append(CompareRow(id: s.id, label: s.label, color: s.color, date: s.dateTimeText,
                                   distance: TimeText.num(m.distanceKm, "0.00", " km"), duration: TimeText.clock(m.durationS),
                                   meanSpeed: TimeText.num(m.meanSpeedKmh, "0.0", " km/h"), maxSpeed: TimeText.num(m.maxSpeedKmh, "0.0", " km/h"),
                                   maxAccel: TimeText.num(m.maxAccel, "0.00", " m/s²"), fix: TimeText.num(m.fixPercent, "0", " %"),
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
        var speed: [FeatureLineSeries] = []
        var accel: [FeatureLineSeries] = []
        for (i, s) in inputs.enumerated() {
            if i < sp.values.count {
                let y: [Double] = sp.values[i].map { $0 * 3.6 }
                speed.append(FeatureLineSeries(id: s.id, name: s.dateText, color: s.color, x: sp.axis, y: y, unit: "km/h", width: 1.3))
            }
            if i < ac.values.count {
                accel.append(FeatureLineSeries(id: s.id, name: s.dateText, color: s.color, x: ac.axis, y: ac.values[i], unit: "m/s²",
                                               format: "0.00", width: 1.1))
            }
        }
        return Output(rows: rows, tracks: tracks, speed: speed, accel: accel)
    }

    /// Route split at gaps and rejected jumps, thinned to ≤ 1500 points for drawing.
    private static func routeRuns(_ tl: SessionTimeline) -> [[CLLocationCoordinate2D]] {
        var runs: [[CLLocationCoordinate2D]] = []
        let n: Int = tl.count
        if n < 2 { return runs }
        let every: Int = max(1, n / 1500)
        var cur: [CLLocationCoordinate2D] = []
        for i in 0..<n {
            let split: Bool = i > 0 && (tl.breakBefore[i] || tl.jumpBefore[i])
            if split {
                if cur.count > 1 { runs.append(cur) }
                cur = []
            }
            let la: Double = tl.lat[i]
            let lo: Double = tl.lon[i]
            if !la.isFinite || !lo.isFinite { continue }
            if i % every == 0 || i == n - 1 || split { cur.append(CLLocationCoordinate2D(latitude: la, longitude: lo)) }
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
