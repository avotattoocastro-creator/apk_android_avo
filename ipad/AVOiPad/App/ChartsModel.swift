import SwiftUI
import Observation

/// Key/value row of the statistics panels (Windows KeyValueRow).
struct SyncStatRow: Identifiable, Equatable {
    var key: String
    var value: String
    var id: String { key }
}

/// Full-resolution series of a chart (Windows ChartSeries). Never drawn directly: `ChartsModel.panel` reduces it with
/// LTTB for the visible window. `runId` splits the line at gaps (breaks) and at missing values (NaN).
struct SyncSource {
    var name: String
    var color: Color
    var width: CGFloat
    var dashed: Bool
    var x: [Double]
    var y: [Double]
    var runId: [Int]
    /// Optional ±1σ half width (same units as y): drawn as a band around the line.
    var sigma: [Double]?
    /// Fill of the band (nil = the red ±1σ of the speed chart).
    var sigmaColor: Color?

    init(name: String, color: Color, width: CGFloat = 1, dashed: Bool = false, x: [Double], y: [Double], breaks: [Bool]? = nil,
         sigma: [Double]? = nil, sigmaColor: Color? = nil) {
        self.name = name
        self.color = color
        self.width = width
        self.dashed = dashed
        let n: Int = min(x.count, y.count)
        self.x = n == x.count ? x : Array(x[0..<n])
        self.y = n == y.count ? y : Array(y[0..<n])
        self.sigma = sigma
        self.sigmaColor = sigmaColor
        var run: Int = 0
        var lastFinite: Bool = false
        var ids: [Int] = [Int](repeating: 0, count: n)
        for i in 0..<n {
            let f: Bool = y[i].isFinite && x[i].isFinite
            if f && i > 0 {
                var brk: Bool = false
                if let b = breaks, i < b.count { brk = b[i] }
                if !lastFinite || brk { run += 1 }
            }
            lastFinite = f
            ids[i] = run
        }
        self.runId = ids
    }
}

struct SyncPoint: Identifiable {
    var id: Int
    var x: Double
    var y: Double
}

struct SyncLine: Identifiable {
    var id: String
    var color: Color
    var width: CGFloat
    var dashed: Bool
    var points: [SyncPoint]
}

struct SyncSigma: Identifiable {
    var id: Int
    var x0: Double
    var x1: Double
    var lo: Double
    var hi: Double
    /// nil = default red ±1σ fill.
    var color: Color? = nil
}

/// Coloured strip at the bottom of a chart (Windows ChartBand: RTK quality, gait).
struct SyncBand: Identifiable {
    var id: Int
    var x0: Double
    var x1: Double
    var color: Color
    /// Strip drawn at the bottom of the plot: lane 0 is the lowest; height in points.
    var lane: Int = 0
    var height: CGFloat = 4
}

/// Draggable vertical handle on a chart (zones of the Análisis page): id, time (timeline seconds), colour and label.
struct SyncHandle: Identifiable {
    var id: Int
    var x: Double
    var color: Color
    var label: String
    /// 0 = lowest row of grips (phase limits); 1 = the row above (repetitions), so coincident limits stay reachable.
    var lane: Int = 0
}

/// Drawable content of one chart for the current window.
struct SyncPanel {
    var lines: [SyncLine] = []
    var sigma: [SyncSigma] = []
    /// Event markers (points) inside the window.
    var markers: [SyncMarker] = []
    var isEmpty: Bool {
        for l in lines where l.points.count > 1 { return false }
        return true
    }
}

enum SyncPanelId: String, CaseIterable {
    case speed, accel, imu, fusedAccel, orientation, cadence, altitude, precision, satellites
    /// Girth lateral acceleration perpendicular to the direction of travel (ChartsImuAnalysis).
    case lateral
    /// Girth roll / pitch with anomaly markers (ChartsImuAnalysis).
    case tilt
}

/// Port of MainViewModel.Charts.cs: synchronized charts (shared cursor, range and x window with the map), range
/// statistics and the session/GNSS panels. Heavy work (series building, girth analysis, LTTB) runs off the main thread.
/// The «Gráficas» page no longer shows GNSS quality/altitude/hAcc/satellites (they live on the GPS page), but the
/// series (`.altitude`, `.precision`, `.satellites`), `qualityBands` and `gnssStats` are still built for other pages.
@Observable
final class ChartsModel {
    unowned let app: AppModel

    // ------------------------------------------------------------ series options (Windows ShowSpeed*/ShowLateral)
    var showSpeedReported: Bool = true { didSet { if showSpeedReported != oldValue { rebuild() } } }
    var showSpeedDerived: Bool = false { didSet { if showSpeedDerived != oldValue { rebuild() } } }
    var showSpeedFiltered: Bool = true { didSet { if showSpeedFiltered != oldValue { rebuild() } } }
    var showSigma: Bool = true { didSet { if showSigma != oldValue { rebuild() } } }
    var showLateral: Bool = true { didSet { if showLateral != oldValue { rebuild() } } }
    // ------------------------------------------------------------ visible charts (Windows Chart*)
    var chartSpeed: Bool = true
    var chartAccel: Bool = true
    var chartImu: Bool = true
    var chartFused: Bool = true
    var chartCadence: Bool = true
    var chartAltitude: Bool = true
    var chartPrecision: Bool = true
    /// «IMU cincha → Desvíos laterales».
    var chartLateral: Bool = true
    /// «IMU cincha → Inclinaciones / anomalías».
    var chartTilt: Bool = true
    /// Touch replacement of Windows Shift+drag: while on, dragging on a chart selects a range.
    var rangeMode: Bool = false

    // ------------------------------------------------------------ drawable content
    private(set) var panels: [SyncPanelId: SyncPanel] = [:]
    private(set) var qualityBands: [SyncBand] = []
    private(set) var gaitBands: [SyncBand] = []
    /// Legend entries switched off by the user, "chartId|legend text" (kept while the app runs, for every session).
    private(set) var hiddenLegend: Set<String> = []
    private(set) var hasImuRaw: Bool = false
    private(set) var hasFused: Bool = false
    private(set) var hasCadence: Bool = false
    private(set) var hasAltitude: Bool = false
    private(set) var building: Bool = false
    /// Full x extent of the session (seconds of the timeline).
    private(set) var fullLo: Double = 0
    private(set) var fullHi: Double = 1

    // ------------------------------------------------------------ panels
    private(set) var rangeStats: [SyncStatRow] = []
    private(set) var sessionStats: [SyncStatRow] = []
    private(set) var gnssStats: [SyncStatRow] = []
    private(set) var filterDescription: String = SpeedSmoother.Parameters().describe()
    private(set) var imuScaleNote: String = ImuTimeline.scaleNote
    private(set) var imuChartHeader: String = "IMU cincha · aceleración vertical z (g, escala nominal)"

    // ------------------------------------------------------------ girth analysis (ChartsImuAnalysis)
    /// 0 no girth data, 1 fused (fmt 1), 2 raw only (fmt 0).
    private(set) var imuSource: Int = 0
    private(set) var imuSensorName: String = ""
    private(set) var imuHeadingNote: String = ""
    private(set) var lateralEvents: [ChartsImuEvent] = []
    private(set) var tiltEvents: [ChartsImuEvent] = []
    /// The session has girth samples (fused or raw): the IMU charts are drawn, otherwise a placeholder.
    var hasGirthImu: Bool { hasFused || hasImuRaw }

    /// Points per drawn series (LTTB threshold).
    static let threshold: Int = 1500

    @ObservationIgnored private var sources: [SyncPanelId: [SyncSource]] = [:]
    @ObservationIgnored private var markerSources: [SyncPanelId: [SyncMarker]] = [:]
    /// Girth analysis cached per (timeline, imu) so toggling speed options does not recompute it.
    @ObservationIgnored private var imuCache: ChartsImuResult? = nil
    @ObservationIgnored private var imuCacheKey: String = ""
    /// Primary-sensor series for the cursor readouts (not observed: read when the cursor moves).
    @ObservationIgnored private var imuReadout: ChartsImuResult = ChartsImuResult()
    @ObservationIgnored private var generation: Int = 0
    @ObservationIgnored private var displayGeneration: Int = 0
    @ObservationIgnored private var displayTask: Task<Void, Never>? = nil
    @ObservationIgnored private var dirty: Bool = true

    init(app: AppModel) {
        self.app = app
    }

    func sessionChanged() {
        dirty = true
        rebuild()
    }

    func pageShown() {
        if dirty { rebuild() }
        refreshRangeStats()
    }

    func panel(_ id: SyncPanelId) -> SyncPanel { panels[id] ?? SyncPanel() }

    // ------------------------------------------------------------ legend switches
    func isHidden(_ chart: String, _ text: String) -> Bool { hiddenLegend.contains(chart + "|" + text) }

    func toggleLegend(_ chart: String, _ text: String) {
        let k: String = chart + "|" + text
        if hiddenLegend.contains(k) { hiddenLegend.remove(k) } else { hiddenLegend.insert(k) }
    }

    /// The panel without the lines / envelope / markers of the legend entries switched off in this chart.
    func panel(_ id: SyncPanelId, chart: String, legend: [SyncLegend]) -> SyncPanel {
        var p: SyncPanel = panel(id)
        let off: [SyncLegend] = legend.filter { isHidden(chart, $0.text) }
        if off.isEmpty { return p }
        for l in off {
            if l.sigma { p.sigma = [] }
            if let mc = l.marker { p.markers.removeAll { $0.color == mc } }
            if !l.sigma && l.marker == nil {
                let keys: [String] = l.keys.isEmpty ? [l.text] : l.keys
                p.lines.removeAll { (line: SyncLine) -> Bool in keys.contains { line.id.contains($0) } }
            }
        }
        return p
    }

    /// Current x window: zoom of the app (chartXMin/Max) or the whole session.
    var domain: ClosedRange<Double> {
        var lo: Double = app.chartXMin.isFinite ? app.chartXMin : fullLo
        var hi: Double = app.chartXMax.isFinite ? app.chartXMax : fullHi
        if !(hi > lo) { lo = fullLo; hi = fullHi }
        if !(hi > lo) { hi = lo + 1 }
        return lo...hi
    }

    var isZoomed: Bool { app.chartXMin.isFinite && app.chartXMax.isFinite }

    // ------------------------------------------------------------ rebuild (Windows RebuildCharts)
    struct BuildOptions {
        var reported: Bool
        var derived: Bool
        var filtered: Bool
        var sigma: Bool
        var lateral: Bool
    }

    struct BuildResult {
        var sources: [SyncPanelId: [SyncSource]] = [:]
        var markers: [SyncPanelId: [SyncMarker]] = [:]
        var qualityBands: [SyncBand] = []
        var gaitBands: [SyncBand] = []
    }

    func rebuild() {
        generation += 1
        displayGeneration += 1
        let gen: Int = generation
        dirty = false
        guard let s = app.selected, s.timeline.count >= 2 else {
            sources = [:]
            markerSources = [:]
            panels = [:]
            qualityBands = []
            imuSource = 0; imuSensorName = ""; imuHeadingNote = ""
            lateralEvents = []; tiltEvents = []
            imuReadout = ChartsImuResult()
            gaitBands = []
            hasImuRaw = false; hasFused = false; hasCadence = false; hasAltitude = false
            building = false
            fullLo = 0; fullHi = 1
            rangeStats = []
            refreshSessionPanels()
            return
        }
        let tl: SessionTimeline = s.timeline
        let imu: ImuTimeline = s.imu
        let engine: EquineAnalysis? = s.engine
        let offset: Double = s.engineOffsetS
        let fusedRaw: [ImuFusedSample] = imu.fused.isEmpty ? [] : s.session.imuFused
        let key: String = "\(s.id)|\(ObjectIdentifier(tl).hashValue)|\(ObjectIdentifier(imu).hashValue)|\(tl.count)|" +
            "\(tl.t[0])|\(tl.t[tl.count - 1])|\(fusedRaw.count)|\(imu.channels.count)|\(imu.fused.count)"
        let cached: ChartsImuResult? = key == imuCacheKey ? imuCache : nil
        let opts = BuildOptions(reported: showSpeedReported, derived: showSpeedDerived, filtered: showSpeedFiltered,
                                sigma: showSigma, lateral: showLateral)
        fullLo = tl.t[0]
        fullHi = tl.t[tl.count - 1] > tl.t[0] ? tl.t[tl.count - 1] : tl.t[0] + 1
        hasImuRaw = !imu.channels.isEmpty
        hasFused = !imu.fused.isEmpty
        hasCadence = engine?.hasImu == true && !(engine?.girthT.isEmpty ?? true)
        var alt: Bool = false
        for v in tl.altitudeMsl where v.isFinite { alt = true; break }
        hasAltitude = alt
        filterDescription = tl.filterParameters.describe()
        imuScaleNote = imu.note
        imuChartHeader = s.session.imuUnits == 1
            ? "IMU cincha · aceleración vertical z (g, unidades del BNO085)" : "IMU cincha · aceleración vertical z (g, escala nominal)"
        refreshSessionPanels()
        refreshRangeStats()
        let d: ClosedRange<Double> = domain
        let lo: Double = d.lowerBound
        let hi: Double = d.upperBound
        building = true
        Task.detached(priority: .userInitiated) { [weak self] in
            var work: BuildResult = ChartsModel.buildSources(tl, imu, engine, offset, opts)
            let girth: ChartsImuResult = cached ?? ChartsImuAnalysis.analyze(tl, imu, fusedRaw)
            ChartsModel.addImu(&work, girth)
            let built: BuildResult = work
            let shown: [SyncPanelId: SyncPanel] = ChartsModel.makePanels(built.sources, built.markers, lo, hi)
            await MainActor.run {
                guard let self = self, self.generation == gen else { return }
                self.sources = built.sources
                self.markerSources = built.markers
                self.qualityBands = built.qualityBands
                self.gaitBands = built.gaitBands
                self.panels = shown
                self.imuCache = girth
                self.imuCacheKey = key
                self.imuReadout = girth
                self.imuSource = girth.source
                self.imuSensorName = girth.sensorName
                self.imuHeadingNote = girth.headingNote
                self.lateralEvents = girth.lateralEvents
                self.tiltEvents = girth.tiltEvents
                self.building = false
            }
        }
    }

    private static func scale(_ v: [Double], _ k: Double) -> [Double] { v.map { $0 * k } }

    /// Girth analysis → panels `.lateral`, `.tilt` and `.fusedAccel` (vertical and |a|, also for raw-only sessions).
    static func addImu(_ r: inout BuildResult, _ g: ChartsImuResult) {
        r.sources[.lateral] = g.lateral
        r.sources[.tilt] = g.tilt
        r.markers[.lateral] = g.lateralMarkers
        r.markers[.tilt] = g.tiltMarkers
        if !g.vertical.isEmpty { r.sources[.fusedAccel] = g.vertical }
    }

    static func sensorColor(_ id: Int) -> Color {
        switch id {
        case 1: return Color(hex: 0x3D9BFF)
        case 0: return Color(hex: 0x52DD40)
        case 2: return Color(hex: 0xFFC42C)
        default: return Color(hex: 0x93949B)
        }
    }

    static let violet: Color = Color(hex: 0xA86BFF)

    static func buildSources(_ tl: SessionTimeline, _ imu: ImuTimeline, _ engine: EquineAnalysis?, _ offset: Double,
                             _ o: BuildOptions) -> BuildResult {
        var r = BuildResult()
        let brk: [Bool] = tl.breakBefore
        // speed
        var sp: [SyncSource] = []
        if o.reported {
            sp.append(SyncSource(name: "Reportada", color: Color(hex: 0x3D9BFF, alpha: 0xA0 / 255.0), width: 1,
                                 x: tl.t, y: scale(tl.speedReported, 3.6), breaks: brk))
        }
        if o.derived {
            sp.append(SyncSource(name: "Derivada de posiciones", color: Avo.silver, width: 1, dashed: true,
                                 x: tl.t, y: scale(tl.speedDerived, 3.6), breaks: brk))
        }
        if o.filtered {
            sp.append(SyncSource(name: "Filtrada (Kalman RTS)", color: Avo.red, width: 1.6, x: tl.t, y: scale(tl.speedFiltered, 3.6),
                                 breaks: brk, sigma: o.sigma ? scale(tl.speedFilteredSigma, 3.6) : nil))
        }
        r.sources[.speed] = sp
        // acceleration: only validated samples (σ ≤ 0.8 m/s², ≥ DGNSS, no gaps)
        var validAccel: [Double] = [Double](repeating: .nan, count: tl.count)
        for i in 0..<tl.count where SegmentAnalyzer.accelValid(tl, i) { validAccel[i] = tl.accelLong[i] }
        var ac: [SyncSource] = [SyncSource(name: "Longitudinal (validada)", color: Avo.warn, width: 1.3, x: tl.t, y: validAccel, breaks: brk)]
        if o.lateral {
            ac.append(SyncSource(name: "Lateral (v·ω, v ≥ 2 m/s)", color: Avo.cyan, width: 1, x: tl.t, y: tl.accelLateral, breaks: brk))
        }
        r.sources[.accel] = ac
        var hasAlt: Bool = false
        for v in tl.altitudeMsl where v.isFinite { hasAlt = true; break }
        r.sources[.altitude] = hasAlt
            ? [SyncSource(name: "Altitud GNSS (nivel medio del mar)", color: Avo.ok, width: 1.2, x: tl.t, y: tl.altitudeMsl, breaks: brk)] : []
        r.sources[.precision] = [SyncSource(name: "hAcc reportada", color: violet, width: 1.2, x: tl.t, y: tl.hAcc, breaks: brk)]
        r.sources[.satellites] = [SyncSource(name: "Satélites", color: Avo.silver, width: 1.2, x: tl.t, y: tl.numSv.map { Double($0) }, breaks: brk)]

        // quality bands (contiguous runs) + signal losses
        var qb: [SyncBand] = []
        var start: Int = 0
        if tl.count > 0 {
            for i in 1...tl.count {
                if i == tl.count || tl.solution[i] != tl.solution[start] || tl.breakBefore[i] {
                    let c: Color = SpeedScale.mapColor(SpeedScale.solution(tl.solution[start]))
                    qb.append(SyncBand(id: qb.count, x0: tl.t[start], x1: tl.t[min(i, tl.count - 1)], color: c))
                    start = i
                }
            }
        }
        for l in tl.losses { qb.append(SyncBand(id: qb.count, x0: l.t0, x1: l.t1, color: Color(hex: 0xFF3945))) }
        r.qualityBands = qb

        // gait bands from the engine
        var gb: [SyncBand] = []
        if let e = engine, e.hasImu {
            for seg in e.segments {
                var code: Int = -1
                switch seg.gaitCode {
                case "STOPPED": code = 0
                case "WALK": code = 1
                case "TROT": code = 2
                case "CANTER_GALLOP": code = 3
                default: code = -1
                }
                gb.append(SyncBand(id: gb.count, x0: seg.t0 - offset, x1: seg.t1 - offset, color: SpeedScale.mapColor(SpeedScale.gait(code))))
            }
        }
        r.gaitBands = gb

        // girth IMU: vertical axis z (nominal scale, not calibrated)
        var im: [SyncSource] = []
        for ch in imu.channels {
            im.append(SyncSource(name: ch.name, color: sensorColor(Int(ch.imuId)), width: 1, x: ch.t, y: ch.axisG("z")))
        }
        r.sources[.imu] = im
        // girth movement (BNO085 fused output)
        var fa: [SyncSource] = []
        var fo: [SyncSource] = []
        let many: Bool = imu.fused.count > 1
        for f in imu.fused {
            let p: String = many ? f.name + " · " : ""
            fa.append(SyncSource(name: p + "Vertical (arriba +)", color: Avo.red, width: 1.2, x: f.t, y: f.verticalMs2))
            fa.append(SyncSource(name: p + "Horizontal", color: Avo.cyan, width: 1, x: f.t, y: f.horizontalMs2))
            fo.append(SyncSource(name: p + "Balanceo (lateral)", color: Avo.warn, width: 1.2, x: f.t, y: f.rollDeg))
            fo.append(SyncSource(name: p + "Cabeceo (adelante/atrás)", color: violet, width: 1.2, x: f.t, y: f.pitchDeg))
        }
        r.sources[.fusedAccel] = fa
        r.sources[.orientation] = fo
        // engine cadence per girth sensor
        var cad: [SyncSource] = []
        if let e = engine, e.hasImu, !e.girthT.isEmpty {
            let n: Int = min(e.girthT.count, e.girthImu.count)
            let ids: [Int] = Array(Set(e.girthImu.prefix(n))).sorted()
            for id in ids {
                var idx: [Int] = []
                for k in 0..<n where e.girthImu[k] == id && e.girthT[k].isFinite { idx.append(k) }
                idx.sort { (a: Int, b: Int) -> Bool in
                    if e.girthT[a] != e.girthT[b] { return e.girthT[a] < e.girthT[b] }
                    return a < b
                }
                let x: [Double] = idx.map { e.girthT[$0] - offset }
                let y: [Double] = idx.map { (k: Int) -> Double in
                    let ok: Bool = k < e.girthStatus.count && e.girthStatus[k] == "OK" && k < e.girthCadenceHz.count
                    return ok ? e.girthCadenceHz[k] * 60 : .nan
                }
                cad.append(SyncSource(name: ImuTimeline.sensorName(UInt8(clamping: id)), color: sensorColor(id), width: 1.4, x: x, y: y))
            }
        }
        r.sources[.cadence] = cad
        return r
    }

    // ------------------------------------------------------------ window reduction
    /// First index with a[i] >= v.
    static func lowerBound(_ a: [Double], _ v: Double) -> Int {
        var lo: Int = 0
        var hi: Int = a.count
        while lo < hi {
            let m: Int = (lo + hi) >> 1
            if a[m] < v { lo = m + 1 } else { hi = m }
        }
        return lo
    }

    /// First index with a[i] > v.
    static func upperBound(_ a: [Double], _ v: Double) -> Int {
        var lo: Int = 0
        var hi: Int = a.count
        while lo < hi {
            let m: Int = (lo + hi) >> 1
            if a[m] <= v { lo = m + 1 } else { hi = m }
        }
        return lo
    }

    static func makePanels(_ sources: [SyncPanelId: [SyncSource]], _ lo: Double, _ hi: Double) -> [SyncPanelId: SyncPanel] {
        makePanels(sources, [:], lo, hi)
    }

    static func makePanels(_ sources: [SyncPanelId: [SyncSource]], _ markers: [SyncPanelId: [SyncMarker]], _ lo: Double,
                           _ hi: Double) -> [SyncPanelId: SyncPanel] {
        var out: [SyncPanelId: SyncPanel] = [:]
        for (id, list) in sources {
            var p: SyncPanel = makePanel(list, lo, hi, threshold: threshold)
            if let mk = markers[id] {
                p.markers = mk.filter { (m: SyncMarker) -> Bool in m.x >= lo && m.x <= hi && m.y.isFinite }
            }
            out[id] = p
        }
        return out
    }

    /// LTTB of every source over [lo, hi] (plus one sample on each side so lines reach the edges).
    static func makePanel(_ list: [SyncSource], _ lo: Double, _ hi: Double, threshold: Int) -> SyncPanel {
        var p = SyncPanel()
        for (si, s) in list.enumerated() {
            let n: Int = s.x.count
            if n == 0 { continue }
            var a: Int = lowerBound(s.x, lo) - 1
            var b: Int = upperBound(s.x, hi)
            a = max(0, a)
            b = min(n - 1, b)
            if b < a { continue }
            let xs: [Double] = Array(s.x[a...b])
            let ys: [Double] = Array(s.y[a...b])
            let idx: [Int] = Downsampler.lttb(xs, ys, threshold)
            var current: [SyncPoint] = []
            var currentRun: Int = -1
            func closeLine() {
                if !current.isEmpty {
                    p.lines.append(SyncLine(id: "\(si)·\(s.name)·\(currentRun)", color: s.color, width: s.width, dashed: s.dashed, points: current))
                }
                current = []
            }
            for k in idx {
                let i: Int = a + k
                let run: Int = s.runId[i]
                if run != currentRun { closeLine(); currentRun = run }
                current.append(SyncPoint(id: i, x: s.x[i], y: s.y[i]))
            }
            closeLine()
            if let sig = s.sigma, sig.count >= n {
                var env: [SyncSigma] = sigmaEnvelope(s, sig, a, b, buckets: 300, idBase: si * 1_000_000)
                if let c = s.sigmaColor {
                    for k in 0..<env.count { env[k].color = c }
                }
                p.sigma.append(contentsOf: env)
            }
        }
        return p
    }

    /// ±σ envelope in buckets (min(y−σ), max(y+σ)), never across a gap.
    static func sigmaEnvelope(_ s: SyncSource, _ sig: [Double], _ a: Int, _ b: Int, buckets: Int, idBase: Int) -> [SyncSigma] {
        var out: [SyncSigma] = []
        let len: Int = b - a + 1
        if len < 2 { return out }
        let step: Int = max(1, len / max(buckets, 1))
        var i0: Int = -1
        var run: Int = -1
        var lo: Double = .infinity
        var hi: Double = -.infinity
        var lastI: Int = -1
        func emit(_ endX: Double) {
            if i0 >= 0 && lo.isFinite && hi.isFinite && endX > s.x[i0] {
                out.append(SyncSigma(id: idBase + out.count, x0: s.x[i0], x1: endX, lo: lo, hi: hi))
            }
            i0 = -1; lo = .infinity; hi = -.infinity
        }
        var i: Int = a
        while i <= b {
            let y: Double = s.y[i]
            let sg: Double = sig[i]
            if !(y.isFinite && sg.isFinite) { i += 1; continue }
            if i0 >= 0 && (s.runId[i] != run || i - i0 >= step) {
                emit(s.runId[i] == run ? s.x[i] : s.x[lastI])
            }
            if i0 < 0 { i0 = i; run = s.runId[i] }
            lo = min(lo, y - sg)
            hi = max(hi, y + sg)
            lastI = i
            i += 1
        }
        if lastI >= 0 { emit(s.x[lastI]) }
        return out
    }

    /// Recomputes the drawn points for the current window (after zoom/pan), debounced.
    func scheduleDisplay(delayMs: UInt64 = 120) {
        displayTask?.cancel()
        displayTask = Task { @MainActor [weak self] in
            if delayMs > 0 { try? await Task.sleep(nanoseconds: delayMs * 1_000_000) }
            if Task.isCancelled { return }
            self?.refreshDisplay()
        }
    }

    func refreshDisplay() {
        displayGeneration += 1
        let gen: Int = displayGeneration
        let src: [SyncPanelId: [SyncSource]] = sources
        let mk: [SyncPanelId: [SyncMarker]] = markerSources
        if src.isEmpty { return }
        let d: ClosedRange<Double> = domain
        let lo: Double = d.lowerBound
        let hi: Double = d.upperBound
        Task.detached(priority: .userInitiated) { [weak self] in
            let shown: [SyncPanelId: SyncPanel] = ChartsModel.makePanels(src, mk, lo, hi)
            await MainActor.run {
                guard let self = self, self.displayGeneration == gen else { return }
                self.panels = shown
            }
        }
    }

    // ------------------------------------------------------------ zoom / pan (Windows wheel, drag, double click)
    /// Sets the x window, clamped to the session; the whole session resets the zoom (NaN), as Windows.
    func setViewport(_ lo: Double, _ hi: Double, refresh: Bool = true) {
        let full: Double = fullHi - fullLo
        guard full > 0, lo.isFinite, hi.isFinite, hi > lo else { return }
        var w: Double = hi - lo
        if w >= full * 0.999 {
            app.chartXMin = .nan
            app.chartXMax = .nan
        } else {
            w = max(w, max(full * 1e-4, 2.0))
            let a: Double = min(max(lo, fullLo), fullHi - w)
            app.chartXMin = a
            app.chartXMax = a + w
        }
        if refresh { scheduleDisplay() }
    }

    func zoom(_ factor: Double, at center: Double? = nil) {
        let d: ClosedRange<Double> = domain
        var c: Double = center ?? (d.lowerBound + d.upperBound) / 2
        if let t = center, !t.isFinite { c = (d.lowerBound + d.upperBound) / 2 }
        if center == nil, app.cursorTime.isFinite, app.cursorTime >= d.lowerBound, app.cursorTime <= d.upperBound { c = app.cursorTime }
        setViewport(c - (c - d.lowerBound) * factor, c + (d.upperBound - c) * factor)
    }

    func pan(_ fraction: Double) {
        let d: ClosedRange<Double> = domain
        let w: Double = d.upperBound - d.lowerBound
        if !isZoomed { return }
        setViewport(d.lowerBound + w * fraction, d.upperBound + w * fraction)
    }

    func resetZoom() {
        app.chartXMin = .nan
        app.chartXMax = .nan
        scheduleDisplay(delayMs: 0)
    }

    /// Keeps the cursor visible while playing with a zoomed window.
    func follow(_ t: Double) {
        guard isZoomed, t.isFinite else { return }
        let d: ClosedRange<Double> = domain
        if t < d.lowerBound || t > d.upperBound {
            let w: Double = d.upperBound - d.lowerBound
            setViewport(t - w * 0.1, t + w * 0.9)
        }
    }

    /// Moves the shared cursor to `t` (event list) and centres the zoomed window on it when it is outside.
    func focus(_ t: Double) {
        guard t.isFinite else { return }
        app.cursorTime = t
        if isZoomed {
            let d: ClosedRange<Double> = domain
            if t < d.lowerBound || t > d.upperBound {
                let w: Double = d.upperBound - d.lowerBound
                setViewport(t - w / 2, t + w / 2)
            }
        }
    }

    // ------------------------------------------------------------ cursor readouts of the girth charts
    func lateralReadout(_ t: Double) -> String {
        let r: ChartsImuResult = imuReadout
        let v: Double = ChartsImuAnalysis.valueAt(r.t, r.lateralY, t)
        return v.isFinite ? DotNetFormat.custom(v, "0.0", spanish: true) + " m/s²" : "—"
    }

    func tiltReadout(_ t: Double) -> String {
        let r: ChartsImuResult = imuReadout
        let a: Double = ChartsImuAnalysis.valueAt(r.t, r.rollY, t)
        let b: Double = ChartsImuAnalysis.valueAt(r.t, r.pitchY, t)
        if !a.isFinite && !b.isFinite { return "—" }
        let ra: String = a.isFinite ? DotNetFormat.custom(a, "0.0", spanish: true) + "°" : "—"
        let pb: String = b.isFinite ? DotNetFormat.custom(b, "0.0", spanish: true) + "°" : "—"
        return "Bal. " + ra + " · Cab. " + pb
    }

    func verticalReadout(_ t: Double) -> String {
        let r: ChartsImuResult = imuReadout
        let v: Double = ChartsImuAnalysis.valueAt(r.t, r.verticalY, t)
        return v.isFinite ? DotNetFormat.custom(v, "0.0", spanish: true) + " m/s²" : "—"
    }

    func clearRange() {
        app.rangeStart = .nan
        app.rangeEnd = .nan
        rangeStats = []
    }

    // ------------------------------------------------------------ statistics (Windows RefreshRangeStats / RefreshSessionPanels)
    func refreshRangeStats() {
        guard let s = app.selected, app.hasRange else { rangeStats = []; return }
        let seg = SegmentDefinition(name: "Selección", t0: app.rangeStart, t1: app.rangeEnd)
        let m: SegmentMetrics = SegmentAnalyzer.compute(s.timeline, seg, engine: s.engine, engineOffsetS: s.engineOffsetS)
        rangeStats = ChartsModel.metricRows(m)
    }

    static func metricRows(_ m: SegmentMetrics) -> [SyncStatRow] {
        var r: [SyncStatRow] = []
        r.append(SyncStatRow(key: "Inicio", value: TimeText.clock(m.t0)))
        r.append(SyncStatRow(key: "Fin", value: TimeText.clock(m.t1)))
        r.append(SyncStatRow(key: "Duración", value: TimeText.clock(m.durationS)))
        r.append(SyncStatRow(key: "Distancia", value: TimeText.num(m.distanceM / 1000, "0.00", " km")))
        r.append(SyncStatRow(key: "Vel. media", value: TimeText.num(m.meanSpeedKmh, "0.0", " km/h")))
        r.append(SyncStatRow(key: "Vel. máxima", value: TimeText.num(m.maxSpeedKmh, "0.0", " km/h")))
        r.append(SyncStatRow(key: "Aceleración máx. validada", value: TimeText.num(m.maxAccel, "0.00", " m/s²")))
        r.append(SyncStatRow(key: "Frenada máx. validada", value: TimeText.num(m.maxDecel, "0.00", " m/s²")))
        r.append(SyncStatRow(key: "Cambios de ritmo", value: String(m.speedChanges)))
        // RTK FIX moved to the GPS page
        r.append(SyncStatRow(key: "Cadencia (motor)", value: TimeText.num(m.cadence, "0", " ciclos/min")))
        r.append(SyncStatRow(key: "Regularidad (correlación ciclos)", value: TimeText.num(m.cycleCorrelation, "0.00")))
        return r
    }

    func refreshSessionPanels() {
        var ss: [SyncStatRow] = []
        var gs: [SyncStatRow] = []
        guard let s = app.selected else { sessionStats = []; gnssStats = []; return }
        let tl: SessionTimeline = s.timeline
        ss.append(SyncStatRow(key: "Caballo", value: s.horse))
        ss.append(SyncStatRow(key: "Jinete", value: s.rider))
        ss.append(SyncStatRow(key: "Modalidad", value: s.discipline))
        ss.append(SyncStatRow(key: "Fecha", value: s.dateTimeText))
        ss.append(SyncStatRow(key: "Zona horaria", value: s.start.map { "Europe/Madrid · " + MadridTime.zoneLabel($0) } ?? "—"))
        ss.append(SyncStatRow(key: "Duración", value: s.durationText))
        ss.append(SyncStatRow(key: "Distancia", value: s.distanceText))
        ss.append(SyncStatRow(key: "Datos", value: s.kind))
        let dist: [GnssSolution: Double] = GnssQuality.distribution(s.session.gnssEpochs)
        func pct(_ k: GnssSolution) -> String { DotNetFormat.custom(dist[k] ?? 0, "0.0", spanish: true) + " %" }
        gs.append(SyncStatRow(key: "RTK FIX", value: pct(.rtkFix)))
        gs.append(SyncStatRow(key: "RTK FLOAT", value: pct(.rtkFloat)))
        gs.append(SyncStatRow(key: "DGNSS", value: pct(.dgnss)))
        gs.append(SyncStatRow(key: "Autónomo", value: pct(.autonomous)))
        gs.append(SyncStatRow(key: "Sin solución válida", value: pct(.none)))
        gs.append(SyncStatRow(key: "Satélites (mediana)",
                              value: tl.count > 0 ? DotNetFormat.custom(Stats.median(tl.numSv.map { Double($0) }), "0", spanish: true) : "—"))
        gs.append(SyncStatRow(key: "hAcc reportada (mediana)",
                              value: tl.count > 0 ? DotNetFormat.custom(Stats.median(tl.hAcc), "0.000", spanish: true) + " m" : "—"))
        var lossSum: Double = 0
        for l in tl.losses { lossSum += l.durationS }
        gs.append(SyncStatRow(key: "Pérdidas de señal", value: "\(tl.losses.count) · \(TimeText.clock(lossSum))"))
        gs.append(SyncStatRow(key: "Saltos descartados", value: String(tl.jumpBefore.filter { $0 }.count)))
        gs.append(SyncStatRow(key: "Frecuencia GNSS",
                              value: tl.nominalDtS > 0 ? DotNetFormat.custom(1 / tl.nominalDtS, "0.#", spanish: true) + " Hz" : "—"))
        sessionStats = ss
        gnssStats = gs
    }
}
