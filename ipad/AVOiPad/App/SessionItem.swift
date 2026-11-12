import SwiftUI
import Observation

/// One imported training with its derived (never persisted over the original) analysis objects.
/// Port of windows/AVO.Windows/ViewModels/SessionItem.cs.
@Observable
final class SessionItem: Identifiable {
    let session: TrainingSession
    /// Whole recording, never trimmed.
    let fullTimeline: SessionTimeline
    /// Analysed part: the whole recording or the start–end window chosen by the user (same time base).
    private(set) var timeline: SessionTimeline
    private(set) var imu: ImuTimeline
    private(set) var windowStart: Double? = nil
    private(set) var windowEnd: Double? = nil
    private let fullImu: ImuTimeline

    var segmentDefs: [SegmentDefinition] = []
    var engine: EquineAnalysis? = nil
    var engineState: String = "Pendiente"
    var notes: String = ""
    var isFavorite: Bool = false
    var isCompared: Bool = false
    var compareColor: Color = Color(hex: 0x3D9BFF)
    var importStatus: String = ""

    private(set) var horseCode: String? = nil
    private(set) var riderCode: String? = nil
    private(set) var horseKnown: Bool = false
    private(set) var riderKnown: Bool = false
    private(set) var identitySource: String = ""
    /// Bumped by setIdentity so views observing horse/rider (read from the session) refresh.
    private var identityVersion: Int = 0

    init(_ s: TrainingSession, _ tl: SessionTimeline, _ imu: ImuTimeline) {
        session = s
        fullTimeline = tl
        timeline = tl
        self.imu = imu
        fullImu = imu
    }

    var id: String { session.sessionId }

    var isTrimmed: Bool { windowStart != nil && windowEnd != nil }

    var windowText: String {
        let total: Double = fullTimeline.count > 1 ? fullTimeline.t[fullTimeline.count - 1] : 0
        if let a = windowStart, let b = windowEnd {
            return "Entrenamiento útil \(TimeText.clock(a)) – \(TimeText.clock(b)) de \(TimeText.clock(total))"
        }
        return "Archivo completo · \(TimeText.clock(total))"
    }

    /// Applies (or clears with nils) the useful window. Runs the analysis again on the filtered copy; the file is untouched.
    func applyWindow(_ start: Double?, _ end: Double?, _ p: SpeedSmoother.Parameters) {
        if let a = start, let b = end, b - a >= 5, fullTimeline.count > 1 {
            let ws: Double = max(a, fullTimeline.t[0])
            let we: Double = min(b, fullTimeline.t[fullTimeline.count - 1])
            let cut: TrainingSession = SessionWindow.apply(session, itow0: fullTimeline.itow0Ms, t0: ws, t1: we)
            let tl: SessionTimeline = SessionTimeline.build(cut, parameters: p, timeBaseItowMs: fullTimeline.itow0Ms)
            let im: ImuTimeline = ImuTimeline.build(cut, tl, t0: ws, t1: we)
            windowStart = ws
            windowEnd = we
            timeline = tl
            imu = im
        } else {
            windowStart = nil
            windowEnd = nil
            timeline = fullTimeline
            imu = fullImu
        }
    }

    /// engine time = timeline time + offset.
    var engineOffsetS: Double {
        guard let e0 = engine?.itow0Ms else { return 0 }
        return Double(SessionTimeline.weekDiffMs(timeline.itow0Ms, e0)) / 1000.0
    }

    /// Name shown (Cuadra/Jinetes when known, otherwise what the file carries).
    var horse: String { _ = identityVersion; return session.horse }
    var rider: String { _ = identityVersion; return session.rider }

    func setIdentity(_ h: ResolvedIdentity, _ r: ResolvedIdentity) {
        horseCode = h.code
        riderCode = r.code
        horseKnown = h.known
        riderKnown = r.known
        identitySource = "Caballo: \(h.source) · Jinete: \(r.source)"
        identityVersion += 1
    }

    var needsIdentity: Bool { !horseKnown || !riderKnown }

    /// Start of the recording (date of the training; not moved by the useful-window trim).
    var start: Date? { fullTimeline.utc0 ?? session.startedAt }
    var dateText: String { MadridTime.format(start, "dd/MM/yyyy") }
    var dateTimeText: String { MadridTime.format(start, "dd/MM/yyyy HH:mm") }
    var timeText: String { MadridTime.format(start, "HH:mm") }

    var distanceKmValue: Double {
        timeline.count > 1 ? timeline.totalDistanceM / 1000 : (session.declaredDistanceM ?? 0) / 1000
    }
    var distanceText: String { DotNetFormat.custom(distanceKmValue, "0.00", spanish: true) + " km" }
    var durationText: String { TimeText.clock(timeline.count > 1 ? timeline.durationS : session.durationSeconds) }
    var maxSpeedKmh: Double {
        timeline.count > 0 ? Stats.maxFinite(timeline.speedFiltered, fallback: 0) * 3.6 : session.maxSpeedKmh
    }
    var maxSpeedText: String { DotNetFormat.custom(maxSpeedKmh, "0.0", spanish: true) + " km/h" }

    /// Time (timeline seconds) and value (km/h) of the maximum filtered speed: fixed marker on the map and the speed chart.
    /// Cached per timeline (it is read on every cursor move of the map).
    var maxSpeedPoint: (t: Double, kmh: Double)? {
        let n: Int = timeline.count
        if let c = maxSpeedCache, c.n == n { return c.value }
        var best: Int = -1
        var bv: Double = -.infinity
        let v: [Double] = timeline.speedFiltered
        for i in 0..<min(n, v.count) where v[i].isFinite && v[i] > bv { bv = v[i]; best = i }
        let value: (t: Double, kmh: Double)? = best >= 0 ? (timeline.t[best], bv * 3.6) : nil
        maxSpeedCache = (n, value)
        return value
    }
    @ObservationIgnored private var maxSpeedCache: (n: Int, value: (t: Double, kmh: Double)?)? = nil
    var meanSpeedText: String {
        if timeline.count < 2 { return "Sin datos" }
        let seg = SegmentDefinition(name: "", t0: timeline.t[0], t1: timeline.t[timeline.count - 1])
        let m: SegmentMetrics = SegmentAnalyzer.compute(timeline, seg)
        return SessionItem.textOf(m.meanSpeedKmh, "0.0", " km/h")
    }
    var fixPercent: Double {
        timeline.count > 0 ? timeline.fractionAtLeast(.rtkFix, -Double.infinity, Double.infinity) * 100 : 0
    }
    var fixText: String { DotNetFormat.custom(fixPercent, "0", spanish: true) + " %" }
    var hasGirth: Bool { imu.channels.count > 0 || session.totalImuSamples > 0 }
    var girthText: String {
        if imu.channels.count > 0 {
            return "\(imu.channels.count)/3 IMU · \(DotNetFormat.custom(imu.sampleRateHz, "0", spanish: true)) Hz"
        }
        if session.totalImuSamples > 0 { return "\(session.totalImuSamples) muestras (formato no decodificado)" }
        return "Sin datos de cincha"
    }
    var kind: String { session.isSynthetic ? "DEMOSTRACIÓN" : "Medido" }
    var isSynthetic: Bool { session.isSynthetic }
    var integrity: String { session.integrity }
    var discipline: String { session.discipline.trimmed.isEmpty ? "Playa" : session.discipline }
    var summary: String { "\(horse) · \(dateTimeText) · \(distanceText)" }

    /// Gait code (engine) for each timeline index; -1 when unknown or without engine/girth.
    var gaitByIndex: [Int] {
        let tl: SessionTimeline = timeline
        var r: [Int] = [Int](repeating: -1, count: tl.count)
        guard let e = engine, e.hasImu else { return r }
        let off: Double = engineOffsetS
        for i in 0..<r.count { r[i] = e.gaitAt(tl.t[i] + off) }
        return r
    }

    static func textOf(_ v: Double?, _ fmt: String, _ unit: String = "") -> String { TimeText.num(v, fmt, unit) }
}
