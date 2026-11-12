import SwiftUI
import Observation

/// Words that identify GNSS/RTK quality texts. Used by the other pages to keep those data only on the «GPS» page.
enum GpsTerms {
    private static let words: [String] = ["GNSS", "RTK", "FIX", "FLOAT", "SATÉL", "SATEL", "HACC", "NTRIP", "DGNSS"]

    /// True when the text talks about GNSS/RTK quality (satellites, hAcc, FIX/FLOAT, NTRIP…).
    static func mentionsGnss(_ text: String) -> Bool {
        let u: String = text.uppercased()
        for w in words where u.contains(w) { return true }
        return false
    }
}

/// Continuous run of one GNSS solution type (quality strip of the «GPS» page).
struct GpsSolutionRun: Identifiable {
    let id: Int
    let t0: Double
    let t1: Double
    let solution: GnssSolution
}

/// One signal loss of the analysed part.
struct GpsLossRow: Identifiable {
    let id: Int
    let t0: Double
    let t1: Double
    let reason: String
    var durationS: Double { t1 - t0 }
}

/// Every GNSS datum of the selected training (rider's vest receiver), computed once per session/trim off the main thread.
/// Only measured values: anything missing stays NaN / empty and is shown as «Sin datos».
struct GpsSummary {
    var sessionId: String = ""
    var t0: Double = 0
    var t1: Double = 1
    var epochsReceived: Int = 0
    var epochsUsable: Int = 0
    var epochsWithoutSolution: Int = 0
    /// Percentage of received epochs (analysed part) per solution type.
    var distribution: [GnssSolution: Double] = [:]
    var satMedian: Double = .nan
    var satMin: Double = .nan
    var satMax: Double = .nan
    var hAccMedian: Double = .nan
    var hAccP95: Double = .nan
    var hAccMax: Double = .nan
    var speedAccMedian: Double = .nan
    var speedAccP95: Double = .nan
    var hasSpeedAcc: Bool = false
    var losses: [GpsLossRow] = []
    var lossTotalS: Double = 0
    var jumps: Int = 0
    var jumpTimes: [Double] = []
    var frequencyHz: Double = .nan
    var nominalDtS: Double = .nan
    var altMin: Double = .nan
    var altMax: Double = .nan
    var altMedian: Double = .nan
    var hasAltitude: Bool = false
    /// Reported (Doppler) vs derived (positions) speed agreement, km/h.
    var speedPairs: Int = 0
    var speedDiffMedianKmh: Double = .nan
    var speedDiffP95Kmh: Double = .nan
    var speedBiasKmh: Double = .nan
    var reportedMaxKmh: Double = .nan
    var derivedMaxKmh: Double = .nan
    var runs: [GpsSolutionRun] = []
    var sensorRows: [FeatureKV] = []
    var satSeries: [FeatureLineSeries] = []
    var hAccSeries: [FeatureLineSeries] = []
    var speedAccSeries: [FeatureLineSeries] = []
    var altSeries: [FeatureLineSeries] = []
    var speedSeries: [FeatureLineSeries] = []

    var hasData: Bool { epochsUsable > 0 }

    /// Value at quantile q (0…1) of the finite values, NaN when there are none.
    static func quantile(_ values: [Double], _ q: Double) -> Double {
        let a: [Double] = values.filter { $0.isFinite }.sorted()
        if a.isEmpty { return .nan }
        let pos: Double = min(max(q, 0), 1) * Double(a.count - 1)
        let lo: Int = Int(pos.rounded(.down))
        let hi: Int = min(lo + 1, a.count - 1)
        let f: Double = pos - Double(lo)
        return a[lo] + (a[hi] - a[lo]) * f
    }

    static func compute(sessionId: String, timeline tl: SessionTimeline, session: TrainingSession, girthText: String,
                        integrity: String) -> GpsSummary {
        var r = GpsSummary()
        r.sessionId = sessionId
        let n: Int = tl.count
        r.epochsUsable = n
        if n > 1 {
            r.t0 = tl.t[0]
            r.t1 = tl.t[n - 1]
        }

        // received epochs of the analysed part (the trim keeps the time base of the full file)
        var epochs: [GnssEpoch] = []
        if n > 1 {
            let lo: Double = tl.t[0] - 0.001
            let hi: Double = tl.t[n - 1] + 0.001
            for e in session.gnssEpochs {
                let te: Double = tl.timeOfItow(e.gpsWeekMs)
                if te >= lo && te <= hi { epochs.append(e) }
            }
        } else {
            epochs = session.gnssEpochs
        }
        r.epochsReceived = epochs.count
        r.epochsWithoutSolution = epochs.filter { $0.solution == GnssSolution.none }.count
        r.distribution = GnssQuality.distribution(epochs)

        if n > 0 {
            let sv: [Double] = tl.numSv.map { Double($0) }
            r.satMedian = Stats.median(sv)
            r.satMin = Stats.minFinite(sv)
            r.satMax = Stats.maxFinite(sv)
            let h: [Double] = tl.hAcc.filter { $0.isFinite && $0 > 0 }
            r.hAccMedian = Stats.median(h)
            r.hAccP95 = quantile(h, 0.95)
            r.hAccMax = Stats.maxFinite(h)
            let sa: [Double] = tl.speedAcc.filter { $0.isFinite && $0 > 0 }
            r.hasSpeedAcc = !sa.isEmpty
            r.speedAccMedian = Stats.median(sa)
            r.speedAccP95 = quantile(sa, 0.95)
            let alt: [Double] = tl.altitudeMsl.filter { $0.isFinite }
            r.hasAltitude = !alt.isEmpty
            r.altMin = Stats.minFinite(alt)
            r.altMax = Stats.maxFinite(alt)
            r.altMedian = Stats.median(alt)
        }
        var k: Int = 0
        for l in tl.losses {
            r.losses.append(GpsLossRow(id: k, t0: l.t0, t1: l.t1, reason: l.reason))
            r.lossTotalS += max(0, l.durationS)
            k += 1
        }
        for i in 0..<n where tl.jumpBefore[i] { r.jumpTimes.append(tl.t[i]) }
        r.jumps = r.jumpTimes.count
        r.nominalDtS = tl.nominalDtS > 0 ? tl.nominalDtS : .nan
        r.frequencyHz = tl.nominalDtS > 0 ? 1 / tl.nominalDtS : .nan

        // reported vs derived speed
        var diffs: [Double] = []
        var bias: Double = 0
        for i in 0..<n {
            let a: Double = tl.speedReported[i]
            let b: Double = tl.speedDerived[i]
            if !a.isFinite || !b.isFinite { continue }
            let d: Double = (b - a) * 3.6
            diffs.append(abs(d))
            bias += d
        }
        r.speedPairs = diffs.count
        if !diffs.isEmpty {
            r.speedDiffMedianKmh = Stats.median(diffs)
            r.speedDiffP95Kmh = quantile(diffs, 0.95)
            r.speedBiasKmh = bias / Double(diffs.count)
        }
        r.reportedMaxKmh = Stats.maxFinite(tl.speedReported) * 3.6
        r.derivedMaxKmh = Stats.maxFinite(tl.speedDerived) * 3.6

        // quality strip: runs of the same solution, split at gaps
        var runs: [GpsSolutionRun] = []
        if n > 0 {
            let step: Double = tl.nominalDtS > 0 ? tl.nominalDtS : 1
            var start: Int = 0
            for i in 1...n {
                let split: Bool = i == n || tl.breakBefore[i] || tl.solution[i] != tl.solution[start]
                if !split { continue }
                let end: Double = (i < n && !tl.breakBefore[i]) ? tl.t[i] : tl.t[i - 1] + step
                runs.append(GpsSolutionRun(id: runs.count, t0: tl.t[start], t1: end, solution: tl.solution[start]))
                start = i
            }
        }
        r.runs = runs

        // sensor information (GNSS/RTK receiver of the vest)
        var rows: [FeatureKV] = []
        let fixPct: Double = n > 0 ? tl.fractionAtLeast(.rtkFix, -Double.infinity, Double.infinity) * 100 : 0
        rows.add("GNSS/RTK chaleco", "\(session.gnssSamples) épocas · \(DotNetFormat.custom(fixPct, "0", spanish: true)) % FIX")
        rows.add("Épocas recibidas (parte analizada)", "\(r.epochsReceived)")
        rows.add("Épocas utilizables", "\(r.epochsUsable)")
        rows.add("Épocas sin solución válida", "\(r.epochsWithoutSolution)")
        rows.add("Muestras RTK FIX / FLOAT / otras (archivo)", "\(session.rtkFixCount) / \(session.rtkFloatCount) / \(session.gnssOtherCount)")
        rows.add("Muestras GNSS no utilizables (archivo)", "\(session.unusableGnssSamples)")
        rows.add("Cincha IMU", girthText)
        rows.add("Integridad", integrity)
        r.sensorRows = rows

        // charts
        if n > 1 {
            let x: [Double] = tl.t
            let brk: [Bool] = tl.breakBefore
            r.satSeries = [FeatureLineSeries(id: "sat", name: "Satélites", color: Avo.cyan, x: x, y: tl.numSv.map { Double($0) },
                                             breaks: brk, unit: "", format: "0", width: 1.4)]
            r.hAccSeries = [FeatureLineSeries(id: "hacc", name: "hAcc reportada", color: Avo.warn, x: x,
                                              y: tl.hAcc.map { (v: Double) -> Double in v.isFinite && v > 0 ? v : .nan },
                                              breaks: brk, unit: " m", format: "0.000", width: 1.3)]
            if r.hasSpeedAcc {
                r.speedAccSeries = [FeatureLineSeries(id: "sacc", name: "Precisión de velocidad", color: Avo.blue, x: x,
                                                      y: tl.speedAcc.map { (v: Double) -> Double in v.isFinite && v > 0 ? v * 3.6 : .nan },
                                                      breaks: brk, unit: " km/h", format: "0.00", width: 1.3)]
            }
            if r.hasAltitude {
                r.altSeries = [FeatureLineSeries(id: "alt", name: "Altitud MSL", color: Avo.ok, x: x, y: tl.altitudeMsl,
                                                 breaks: brk, unit: " m", format: "0.0", width: 1.4)]
            }
            r.speedSeries = [
                FeatureLineSeries(id: "vrep", name: "Reportada (Doppler)", color: Avo.blue, x: x, y: tl.speedReported.map { $0 * 3.6 },
                                  breaks: brk, unit: " km/h", format: "0.0", width: 1.4),
                FeatureLineSeries(id: "vder", name: "Derivada de posiciones", color: Avo.red, x: x, y: tl.speedDerived.map { $0 * 3.6 },
                                  breaks: brk, unit: " km/h", format: "0.0", width: 1.0),
            ]
        }
        return r
    }
}

/// «GPS» page model: all the GNSS/RTK data of the selected training, without a map. The other pages no longer show
/// GNSS quality; it lives only here.
@Observable
final class GpsModel {
    unowned let app: AppModel

    private(set) var summary: GpsSummary? = nil
    private(set) var computing: Bool = false

    @ObservationIgnored private var generation: Int = 0
    @ObservationIgnored private var computedKey: String = ""

    init(app: AppModel) {
        self.app = app
    }

    // ------------------------------------------------------------------ contract
    func sessionChanged() {
        computedKey = ""
        if app.page == .gps {
            refresh()
        } else {
            generation += 1
            summary = nil
            computing = false
        }
    }

    func pageShown() {
        refresh()
    }

    // ------------------------------------------------------------------ computation
    func refresh() {
        guard let s = app.selected else {
            generation += 1
            summary = nil
            computing = false
            computedKey = ""
            return
        }
        let key: String = s.id + "|" + s.windowText
        if key == computedKey && summary != nil { return }
        computedKey = key
        generation += 1
        let gen: Int = generation
        computing = true
        let tl: SessionTimeline = s.timeline
        let session: TrainingSession = s.session
        let id: String = s.id
        let girth: String = s.girthText
        let integrity: String = s.integrity
        Task.detached(priority: .userInitiated) { [weak self] in
            let r: GpsSummary = GpsSummary.compute(sessionId: id, timeline: tl, session: session, girthText: girth, integrity: integrity)
            await MainActor.run {
                guard let self = self, self.generation == gen else { return }
                self.summary = r
                self.computing = false
            }
        }
    }
}
