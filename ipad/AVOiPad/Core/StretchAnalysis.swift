import Foundation

// «Análisis del tramo»: complete analysis of the stretch selected on the charts (trainer's request 08/11/2026):
// metrics, 200 m splits, speed profile, acceleration to the top speed, fade, data quality, comparison with the stretches
// saved for the same horse and observations computed from the data. The AI analysis (Claude) is in StretchModel.
// Only measured data: nothing is estimated or invented; a value that cannot be computed is nil («Sin datos»).

/// One 200 m split of the stretch (the last one may be partial).
struct StretchSplit: Identifiable, Equatable {
    var index: Int
    var fromM: Double
    var toM: Double
    var t0: Double
    var t1: Double
    var meanKmh: Double?
    var maxKmh: Double?
    /// Mean acceleration over the split (speed at the end − speed at the start) / duration, m/s².
    var accel: Double?
    var partial: Bool
    var id: Int { index }
    var lengthM: Double { toM - fromM }
    var durationS: Double { t1 - t0 }
}

/// Speed sample of the stretch for the profile chart (seconds since the start of the stretch, km/h, metres).
struct StretchSample: Identifiable, Equatable {
    var id: Int
    var s: Double
    var kmh: Double
    var m: Double
}

struct StretchReport {
    var metrics: SegmentMetrics
    var splits: [StretchSplit]
    var samples: [StretchSample]
    /// Fastest full 200 m split (seconds) and its index.
    var best200S: Double?
    var best200Index: Int?
    /// Last full split vs the fastest one (% slower, positive = slower).
    var lastVsBestPct: Double?
    /// Mean speed of the second half of the distance vs the first half (%; negative = slowed down).
    var halvesPct: Double?
    /// Coefficient of variation of the full-split mean speeds (%), regularity of the rhythm.
    var splitCvPct: Double?
    /// Seconds and metres from the start of the stretch to the top speed.
    var vmaxAtS: Double?
    var vmaxAtM: Double?
    /// Seconds from the start until 90 % of the top speed.
    var to90S: Double?
    /// Time and distance at or above 90 % of the top speed.
    var above90S: Double?
    var above90M: Double?
    var observations: [String]

    /// Text for the AI context and for saving (one block, Spanish).
    func contextText() -> String {
        var t: String = ""
        let m: SegmentMetrics = metrics
        t += "Tramo: \(TimeText.clock(m.t0)) – \(TimeText.clock(m.t1)) del entrenamiento\n"
        t += "Duración \(TimeText.clock(m.durationS)) · distancia \(TimeText.num(m.distanceM, "0")) m · vel. media \(TimeText.num(m.meanSpeedKmh, "0.0", " km/h")) · vel. máx. \(TimeText.num(m.maxSpeedKmh, "0.0", " km/h"))\n"
        t += "Aceleración máx. validada \(TimeText.num(m.maxAccel, "0.00", " m/s²")) · frenada máx. \(TimeText.num(m.maxDecel, "0.00", " m/s²")) · cambios de ritmo \(m.speedChanges)\n"
        t += "Vmáx a los \(TimeText.num(vmaxAtS, "0.0", " s")) / \(TimeText.num(vmaxAtM, "0", " m")) del inicio · 90 % de Vmáx a los \(TimeText.num(to90S, "0.0", " s")) · por encima del 90 %: \(TimeText.num(above90S, "0.0", " s")) y \(TimeText.num(above90M, "0", " m"))\n"
        t += "Mejor 200 m \(TimeText.num(best200S, "0.00", " s")) · último 200 m frente al mejor \(TimeText.num(lastVsBestPct, "+0.0;-0.0", " %")) · 2.ª mitad frente a 1.ª \(TimeText.num(halvesPct, "+0.0;-0.0", " %")) · CV parciales \(TimeText.num(splitCvPct, "0.0", " %"))\n"
        t += "RTK FIX \(TimeText.num(m.fixFraction * 100, "0", " %")) · pérdidas de señal \(m.gapCount) · cadencia \(TimeText.num(m.cadence, "0", " ciclos/min")) · regularidad \(TimeText.num(m.cycleCorrelation, "0.00"))\n"
        t += "Parciales de 200 m (desde, tiempo, vel. media, vel. máx., aceleración media):\n"
        for s in splits {
            t += "  \(TimeText.num(s.fromM, "0"))–\(TimeText.num(s.toM, "0")) m\(s.partial ? " (parcial)" : ""): \(TimeText.num(s.durationS, "0.00", " s")), \(TimeText.num(s.meanKmh, "0.0", " km/h")), máx \(TimeText.num(s.maxKmh, "0.0", " km/h")), \(TimeText.num(s.accel, "+0.00;-0.00", " m/s²"))\n"
        }
        if !observations.isEmpty { t += "Observaciones calculadas: " + observations.joined(separator: " ") + "\n" }
        return t
    }
}

enum StretchAnalyzer {
    static let splitM: Double = 200

    static func compute(_ tl: SessionTimeline, t0 a: Double, t1 b: Double, engine: EquineAnalysis?, engineOffsetS: Double,
                        saved: [SavedStretch] = []) -> StretchReport {
        let t0: Double = min(a, b)
        let t1: Double = max(a, b)
        let seg = SegmentDefinition(name: "Tramo", t0: t0, t1: t1)
        let m: SegmentMetrics = SegmentAnalyzer.compute(tl, seg, engine: engine, engineOffsetS: engineOffsetS)
        var idx: [Int] = []
        for i in 0..<tl.count where tl.t[i] >= t0 && tl.t[i] <= t1 && tl.distance[i].isFinite { idx.append(i) }
        var report = StretchReport(metrics: m, splits: [], samples: [], observations: [])
        guard idx.count >= 2 else {
            report.observations = ["Sin datos GNSS utilizables en el tramo."]
            return report
        }
        let first: Int = idx[0]
        let d0: Double = tl.distance[first]
        let ts0: Double = tl.t[first]
        func kmh(_ i: Int) -> Double? {
            let v: Double = tl.speedFiltered[i]
            return v.isFinite ? v * 3.6 : nil
        }
        // speed profile (at most ~1500 points)
        let step: Int = max(1, idx.count / 1500)
        var samples: [StretchSample] = []
        var k: Int = 0
        while k < idx.count {
            let i: Int = idx[k]
            if let v = kmh(i) { samples.append(StretchSample(id: k, s: tl.t[i] - ts0, kmh: v, m: tl.distance[i] - d0)) }
            k += step
        }
        report.samples = samples

        // time at which the distance reaches `target` (linear interpolation between samples)
        func timeAt(_ target: Double) -> Double? {
            for k in 1..<idx.count {
                let p: Int = idx[k - 1], q: Int = idx[k]
                let dp: Double = tl.distance[p] - d0, dq: Double = tl.distance[q] - d0
                if dp <= target && dq >= target {
                    if dq - dp < 1e-9 { return tl.t[q] }
                    return tl.t[p] + (target - dp) / (dq - dp) * (tl.t[q] - tl.t[p])
                }
            }
            return nil
        }
        func speedAt(_ t: Double) -> Double? {
            let i: Int = tl.indexAt(t)
            guard i >= 0, i < tl.count else { return nil }
            let v: Double = tl.speedFiltered[i]
            return v.isFinite ? v : nil
        }
        let total: Double = tl.distance[idx[idx.count - 1]] - d0
        var splits: [StretchSplit] = []
        var from: Double = 0
        var n: Int = 1
        while from < total - 0.5 {
            let to: Double = min(from + splitM, total)
            let partial: Bool = to - from < splitM - 0.5
            if partial && to - from < 20 { break }
            guard let ta = (from == 0 ? ts0 : timeAt(from)), let tb = timeAt(to), tb > ta else { break }
            var vmax: Double = -.infinity
            for i in idx where tl.t[i] >= ta && tl.t[i] <= tb { if let v = kmh(i), v > vmax { vmax = v } }
            var acc: Double? = nil
            if let va = speedAt(ta), let vb = speedAt(tb) { acc = (vb - va) / (tb - ta) }
            splits.append(StretchSplit(index: n, fromM: from, toM: to, t0: ta, t1: tb,
                                       meanKmh: (to - from) / (tb - ta) * 3.6, maxKmh: vmax.isFinite ? vmax : nil,
                                       accel: acc, partial: partial))
            from = to
            n += 1
        }
        report.splits = splits
        let full: [StretchSplit] = splits.filter { !$0.partial }
        if let best = full.min(by: { $0.durationS < $1.durationS }) {
            report.best200S = best.durationS
            report.best200Index = best.index
            if let last = full.last, full.count >= 2 { report.lastVsBestPct = (last.durationS / best.durationS - 1) * 100 }
        }
        let speeds: [Double] = full.compactMap { $0.meanKmh }
        if speeds.count >= 3 {
            let mean: Double = speeds.reduce(0, +) / Double(speeds.count)
            let varc: Double = speeds.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(speeds.count - 1)
            if mean > 0 { report.splitCvPct = varc.squareRoot() / mean * 100 }
        }
        if total >= 100, let tm = timeAt(total / 2) {
            let tEnd: Double = tl.t[idx[idx.count - 1]]
            let v1: Double = (total / 2) / (tm - ts0)
            let v2: Double = (total / 2) / (tEnd - tm)
            if v1 > 0 && v2.isFinite { report.halvesPct = (v2 / v1 - 1) * 100 }
        }
        // top speed: where, how long to reach 90 %, time / distance above 90 %
        var bi: Int = -1
        var bv: Double = -.infinity
        for i in idx { if let v = kmh(i), v > bv { bv = v; bi = i } }
        if bi >= 0 {
            report.vmaxAtS = tl.t[bi] - ts0
            report.vmaxAtM = tl.distance[bi] - d0
            let thr: Double = bv * 0.9
            if let i90 = idx.first(where: { (kmh($0) ?? -1) >= thr }) { report.to90S = tl.t[i90] - ts0 }
            var tAbove: Double = 0, dAbove: Double = 0
            for k in 1..<idx.count {
                let p: Int = idx[k - 1], q: Int = idx[k]
                if tl.breakBefore[q] { continue }
                if (kmh(p) ?? -1) >= thr && (kmh(q) ?? -1) >= thr {
                    tAbove += tl.t[q] - tl.t[p]
                    dAbove += tl.distance[q] - tl.distance[p]
                }
            }
            report.above90S = tAbove
            report.above90M = dAbove
        }
        report.observations = observations(report, saved: saved)
        return report
    }

    /// Facts read from the numbers (no veterinary judgement); the AI turns them into recommendations.
    static func observations(_ r: StretchReport, saved: [SavedStretch]) -> [String] {
        var o: [String] = []
        let m: SegmentMetrics = r.metrics
        if let p = r.lastVsBestPct {
            if p >= 8 { o.append("El último 200 m es un \(fmt(p, "0.0")) % más lento que el mejor: caída clara al final del tramo.") }
            else if p >= 3 { o.append("El último 200 m es un \(fmt(p, "0.0")) % más lento que el mejor: ligera caída al final.") }
            else { o.append("El último 200 m se mantiene a menos del 3 % del mejor: sin caída apreciable.") }
        }
        if let h = r.halvesPct {
            if h > 2 { o.append("Segunda mitad un \(fmt(h, "0.0")) % más rápida que la primera (parcial negativo, progresivo).") }
            else if h < -5 { o.append("Segunda mitad un \(fmt(-h, "0.0")) % más lenta que la primera.") }
        }
        if let cv = r.splitCvPct {
            o.append(cv < 3 ? "Ritmo muy regular entre parciales (CV \(fmt(cv, "0.0")) %)." :
                     cv < 7 ? "Ritmo con variaciones moderadas entre parciales (CV \(fmt(cv, "0.0")) %)." :
                     "Ritmo irregular entre parciales (CV \(fmt(cv, "0.0")) %).")
        }
        if let s = r.to90S, let ds = r.vmaxAtS {
            o.append("Alcanza el 90 % de su velocidad máxima a los \(fmt(s, "0.0")) s y la máxima a los \(fmt(ds, "0.0")) s del inicio del tramo.")
        }
        if m.fixFraction < 0.5 { o.append("Menos del 50 % del tramo en RTK FIX: las distancias y parciales tienen menos precisión.") }
        if m.gapCount > 0 { o.append("\(m.gapCount) pérdida(s) de señal GNSS dentro del tramo.") }
        // the horse's saved stretches of a similar length (±25 %)
        let similar: [SavedStretch] = saved.filter { abs($0.distanceM - m.distanceM) <= m.distanceM * 0.25 && $0.meanKmh != nil }
        if let mean = m.meanSpeedKmh, !similar.isEmpty {
            let best: SavedStretch = similar.max { ($0.meanKmh ?? 0) < ($1.meanKmh ?? 0) }!
            let d: Double = (mean / (best.meanKmh ?? mean) - 1) * 100
            o.append("Frente a su mejor tramo guardado de distancia parecida (\(best.title), \(fmt(best.meanKmh ?? 0, "0.0")) km/h): \(fmt(d, "+0.0;-0.0")) % de velocidad media.")
        }
        return o
    }

    static func fmt(_ v: Double, _ f: String) -> String { DotNetFormat.custom(v, f, spanish: true) }
}

// MARK: - Saved stretches (per horse)

/// A stretch saved on a horse for later comparisons («Tramos guardados» of the horse in Cuadra).
struct SavedStretch: Codable, Identifiable, Equatable {
    var id: String = SegmentDefinition.newId()
    var horseCode: String
    var horseName: String
    var sessionId: String
    var sessionDate: String
    var name: String
    var t0: Double
    var t1: Double
    var savedAt: Date = Date()
    var durationS: Double
    var distanceM: Double
    var meanKmh: Double?
    var maxKmh: Double?
    var best200S: Double?
    var lastVsBestPct: Double?
    var splitsS: [Double] = []
    var aiText: String = ""
    var notes: String = ""

    var title: String { name.isEmpty ? sessionDate : name + " · " + sessionDate }
}

/// tramos_guardados.json in the app folder (never next to the original training files).
final class StretchStore {
    private let file: String
    private(set) var items: [SavedStretch] = []

    init(root: String) {
        file = AvoFiles.join(root, "tramos_guardados.json")
        load()
    }

    func load() {
        guard let d = AvoFiles.read(file) else { items = []; return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        items = (try? dec.decode([SavedStretch].self, from: d)) ?? []
    }

    func save() throws {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try AvoFiles.writeAtomic(try enc.encode(items), to: file)
    }

    func add(_ s: SavedStretch) throws {
        items.append(s)
        try save()
    }

    func update(_ s: SavedStretch) throws {
        if let i = items.firstIndex(where: { $0.id == s.id }) { items[i] = s; try save() }
    }

    func remove(_ id: String) throws {
        items.removeAll { $0.id == id }
        try save()
    }

    func of(horse code: String) -> [SavedStretch] {
        items.filter { $0.horseCode == code }.sorted { $0.savedAt > $1.savedAt }
    }
}
