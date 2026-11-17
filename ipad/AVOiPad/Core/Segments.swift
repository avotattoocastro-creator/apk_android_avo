import Foundation
import CryptoKit

/// Kind of a segment. Raw values are the names written by the Windows JSON (JsonStringEnumConverter).
enum SegmentKind: String, CaseIterable, Equatable {
    case manual = "Manual"
    case distance = "Distance"
    case speedBand = "SpeedBand"
    case engine = "Engine"
    case lines = "Lines"

    /// C# numeric value of the enum (accepted when reading JSON written with numbers).
    var intValue: Int {
        switch self {
        case .manual: return 0
        case .distance: return 1
        case .speedBand: return 2
        case .engine: return 3
        case .lines: return 4
        }
    }

    static func from(intValue: Int) -> SegmentKind? {
        for k in SegmentKind.allCases where k.intValue == intValue { return k }
        return nil
    }

    /// Case-insensitive parse (as System.Text.Json's JsonStringEnumConverter).
    static func parse(_ text: String) -> SegmentKind? {
        for k in SegmentKind.allCases where k.rawValue.lowercased() == text.lowercased() { return k }
        if let n = Int(text) { return from(intValue: n) }
        return nil
    }
}

/// User or automatic selection of a time interval of one session. Stored apart from the telemetry.
final class SegmentDefinition: Identifiable {
    var id: String = SegmentDefinition.newId()
    var name: String = ""
    var t0: Double = 0
    var t1: Double = 0
    var kind: SegmentKind = .manual
    var notes: String = ""
    var createdUtc: Date = Date()

    init() {}

    init(name: String, t0: Double, t1: Double, kind: SegmentKind = .manual, notes: String = "") {
        self.name = name
        self.t0 = t0
        self.t1 = t1
        self.kind = kind
        self.notes = notes
    }

    /// Guid.NewGuid().ToString("N")[..12]
    static func newId() -> String {
        let hex: String = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return String(hex.prefix(12))
    }
}

/// Metrics of a segment. nil = not available with the data present (shown as «Sin datos»).
struct SegmentMetrics: Equatable {
    var id: String
    var name: String
    var kind: SegmentKind
    var t0: Double
    var t1: Double
    var durationS: Double
    var distanceM: Double
    var maxSpeedKmh: Double?
    var meanSpeedKmh: Double?
    var maxAccel: Double?
    var maxDecel: Double?
    var speedChanges: Int
    var fixFraction: Double
    var floatOrBetterFraction: Double
    var meanHAccM: Double?
    var gapCount: Int
    var cadence: Double?
    var cycleCorrelation: Double?
    var intervalCv: Double?
    var observations: String
    var notes: String = ""
}

enum SegmentAnalyzer {
    /// Acceleration samples count as "validated" only with σa ≤ this value (m/s²), no gap/jump nearby and at least
    /// a DGNSS solution. The same band as the engine's USABLE quality (σ ≤ 0.8 m/s²).
    static let maxAccelSigma: Double = 0.8

    /// Speed bands used to count rhythm changes. They are speed bands, not gaits.
    static let speedBandEdgesMs: [Double] = [0.4, 2.2, 4.6]

    /// - Parameter engineOffsetS: engine time = timeline time + offset (difference of the first GNSS epochs used by each).
    static func compute(_ tl: SessionTimeline, _ seg: SegmentDefinition, engine: EquineAnalysis? = nil, engineOffsetS: Double = 0) -> SegmentMetrics {
        let t0: Double = min(seg.t0, seg.t1)
        let t1: Double = max(seg.t0, seg.t1)
        var idx: [Int] = []
        for i in 0..<tl.count where tl.t[i] >= t0 && tl.t[i] <= t1 { idx.append(i) }
        if idx.count < 2 {
            return SegmentMetrics(id: seg.id, name: seg.name, kind: seg.kind, t0: t0, t1: t1, durationS: t1 - t0, distanceM: 0,
                                  maxSpeedKmh: nil, meanSpeedKmh: nil, maxAccel: nil, maxDecel: nil, speedChanges: 0,
                                  fixFraction: 0, floatOrBetterFraction: 0, meanHAccM: nil, gapCount: 0,
                                  cadence: nil, cycleCorrelation: nil, intervalCv: nil,
                                  observations: "Sin datos GNSS utilizables en el intervalo", notes: seg.notes)
        }
        let first: Int = idx[0]
        let last: Int = idx[idx.count - 1]
        let dist: Double = tl.distance[last] - tl.distance[first]
        let dur: Double = tl.t[last] - tl.t[first]
        var gaps: Int = 0
        for k in 1..<idx.count where tl.breakBefore[idx[k]] { gaps += 1 }
        var activeTime: Double = 0
        for k in 1..<idx.count where !tl.breakBefore[idx[k]] { activeTime += tl.t[idx[k]] - tl.t[idx[k - 1]] }
        let vmax: Double = Stats.maxFinite(idx.map { tl.speedFiltered[$0] })
        let mean: Double? = activeTime > 0 ? dist / activeTime * 3.6 : nil
        let valid: [Int] = idx.filter { accelValid(tl, $0) }
        var amax: Double? = valid.isEmpty ? nil : Stats.maxFinite(valid.map { tl.accelLong[$0] })
        var dmax: Double? = valid.isEmpty ? nil : Stats.minFinite(valid.map { tl.accelLong[$0] })
        // NaN compares false in C#, so a NaN max/min stays as it is (later shown as «Sin datos»).
        if let am = amax, am <= 0 { amax = nil }
        if let dm = dmax, dm >= 0 { dmax = nil }
        let changes: Int = countBandChanges(tl, idx)
        let fix: Double = Double(idx.filter { tl.solution[$0] == .rtkFix }.count) / Double(idx.count)
        let flt: Double = Double(idx.filter { tl.solution[$0] >= .rtkFloat }.count) / Double(idx.count)
        let haccValues: [Double] = idx.map { tl.hAcc[$0] }.filter { $0.isFinite }
        var hacc: Double? = nil
        if !haccValues.isEmpty {
            var sum: Double = 0
            for v in haccValues { sum += v }
            let h: Double = sum / Double(haccValues.count)
            if h.isFinite { hacc = h }
        }

        var cad: Double? = nil
        var corr: Double? = nil
        var cv: Double? = nil
        if let engine = engine, engine.hasImu, !engine.segments.isEmpty {
            // Duration-weighted average of engine performance segments overlapping the interval.
            var wsum: Double = 0
            var csum: Double = 0
            let e0: Double = t0 + engineOffsetS
            let e1: Double = t1 + engineOffsetS
            for es in engine.segments {
                let o: Double = min(es.t1, e1) - max(es.t0, e0)
                if o <= 0 || !o.isFinite { continue }
                if let f = es.cadenceHz, f.isFinite { csum += f * o; wsum += o }
            }
            if wsum > 0 { cad = csum / wsum * 60 }
            var corrs: [Double] = []
            var cvs: [Double] = []
            for e in engine.segments where min(e.t1, e1) - max(e.t0, e0) > 0 {
                if let c = e.cycleCorrelation, c.isFinite { corrs.append(c) }
                if let c = e.intervalCv, c.isFinite { cvs.append(c) }
            }
            if !corrs.isEmpty { corr = average(corrs) }
            if !cvs.isEmpty { cv = average(cvs) }
        }

        var obs: [String] = []
        if gaps > 0 { obs.append("\(gaps) pérdida(s) de señal GNSS") }
        if fix < 0.5 { obs.append("menos del 50 % en RTK FIX") }
        if Double(valid.count) < Double(idx.count) * 0.5 { obs.append("aceleración validada en menos de la mitad de las épocas") }
        if engine == nil || !(engine?.hasImu ?? false) { obs.append("sin datos de cincha: regularidad no disponible") }
        return SegmentMetrics(id: seg.id, name: seg.name, kind: seg.kind, t0: tl.t[first], t1: tl.t[last], durationS: dur, distanceM: dist,
                              maxSpeedKmh: vmax.isFinite ? vmax * 3.6 : nil, meanSpeedKmh: mean, maxAccel: amax, maxDecel: dmax,
                              speedChanges: changes, fixFraction: fix, floatOrBetterFraction: flt, meanHAccM: hacc, gapCount: gaps,
                              cadence: cad, cycleCorrelation: corr, intervalCv: cv,
                              observations: obs.isEmpty ? "Datos completos" : obs.joined(separator: "; "), notes: seg.notes)
    }

    private static func average(_ a: [Double]) -> Double {
        var s: Double = 0
        for v in a { s += v }
        return s / Double(a.count)
    }

    static func accelValid(_ tl: SessionTimeline, _ i: Int) -> Bool {
        tl.accelLong[i].isFinite && tl.accelLongSigma[i] <= maxAccelSigma && tl.solution[i] >= .dgnss &&
            !tl.breakBefore[i] && !(i + 1 < tl.count && tl.breakBefore[i + 1]) && !tl.jumpBefore[i]
    }

    private static func band(_ v: Double) -> Int {
        var b: Int = 0
        for e in speedBandEdgesMs where v >= e { b += 1 }
        return b
    }

    /// Changes of speed band lasting at least 3 s (hysteresis against flicker at the edges).
    static func countBandChanges(_ tl: SessionTimeline, _ idx: [Int]) -> Int {
        var changes: Int = 0
        var current: Int = -1
        var candidate: Int = -1
        var since: Double = 0
        for i in idx {
            let v: Double = tl.speedFiltered[i]
            if !v.isFinite { continue }
            let b: Int = band(v)
            if current < 0 { current = b; continue }
            if b == current { candidate = -1; continue }
            if b != candidate { candidate = b; since = tl.t[i]; continue }
            if tl.t[i] - since >= 3 { changes += 1; current = b; candidate = -1 }
        }
        return changes
    }

    /// Consecutive segments of fixed distance (default 500 m), restarting after gaps.
    static func byDistance(_ tl: SessionTimeline, _ lengthM: Double = 500) -> [SegmentDefinition] {
        var list: [SegmentDefinition] = []
        if tl.count < 2 || lengthM <= 0 { return list }
        var start: Int = 0
        for i in 1..<tl.count {
            if tl.breakBefore[i] { start = i; continue }
            if tl.distance[i] - tl.distance[start] >= lengthM || i == tl.count - 1 {
                if tl.t[i] - tl.t[start] > 0 {
                    let name: String = DotNetFormat.custom(tl.distance[start] / 1000, "0.0#", spanish: true) + "–" +
                        DotNetFormat.custom(tl.distance[i] / 1000, "0.0#", spanish: true) + " km"
                    list.append(SegmentDefinition(name: name, t0: tl.t[start], t1: tl.t[i], kind: .distance))
                }
                start = i
            }
        }
        return list
    }

    private static let bandNames: [String] = ["Parado", "Velocidad baja", "Velocidad media", "Velocidad alta"]

    /// Automatic segmentation by speed band of the filtered speed, minimum duration minS (default 10 s).
    /// Labels are speed bands, explicitly not gaits (gait needs the girth IMU and the engine).
    static func bySpeedBand(_ tl: SessionTimeline, _ minS: Double = 10) -> [SegmentDefinition] {
        var raw: [(band: Int, t0: Double, t1: Double)] = []
        var cur: Int = -1
        var ts: Double = 0
        var tp: Double = 0
        for i in 0..<tl.count {
            let v: Double = tl.speedFiltered[i]
            if !v.isFinite { continue }
            let b: Int = band(v)
            if cur < 0 { cur = b; ts = tl.t[i] }
            else if b != cur || tl.breakBefore[i] { raw.append((band: cur, t0: ts, t1: tp)); cur = b; ts = tl.t[i] }
            tp = tl.t[i]
        }
        if cur >= 0 { raw.append((band: cur, t0: ts, t1: tp)) }
        // merge short pieces into the previous one
        var merged: [(band: Int, t0: Double, t1: Double)] = []
        for r in raw {
            if !merged.isEmpty && (r.t1 - r.t0 < minS || merged[merged.count - 1].band == r.band) {
                let m = merged[merged.count - 1]
                merged[merged.count - 1] = (band: m.t1 - m.t0 >= r.t1 - r.t0 ? m.band : r.band, t0: m.t0, t1: r.t1)
            } else {
                merged.append(r)
            }
        }
        var out: [SegmentDefinition] = []
        for (k, m) in merged.enumerated() {
            let name: String = "\(k + 1). \(bandNames[min(max(m.band, 0), 3)])"
            out.append(SegmentDefinition(name: name, t0: m.t0, t1: m.t1, kind: .speedBand))
        }
        return out
    }

    /// Engine performance segments (gait classification of the engine; only meaningful with girth data).
    static func fromEngine(_ engine: EquineAnalysis, _ engineOffsetS: Double = 0) -> [SegmentDefinition] {
        var out: [SegmentDefinition] = []
        for s in engine.segments where s.t0.isFinite && s.t1.isFinite && s.t1 > s.t0 {
            out.append(SegmentDefinition(name: "\(s.id). \(s.aire)", t0: s.t0 - engineOffsetS, t1: s.t1 - engineOffsetS, kind: .engine))
        }
        return out
    }
}

/// Persistent per-session segment store (JSON, schema avo-windows-segments v1). Never touches the telemetry.
/// Same file names and JSON keys (PascalCase, enum names as strings, indented) as the Windows app.
final class SegmentStore {
    static let schema: String = "avo-windows-segments"
    static let version: Int = 1
    private let dir: String

    init(_ directory: String) { dir = directory }

    func pathFor(_ sessionId: String) -> String {
        let hash: String = AvoHex.upper(SHA256.hash(data: Data(sessionId.utf8)))
        return (dir as NSString).appendingPathComponent(String(hash.prefix(24)) + ".json")
    }

    func load(_ sessionId: String) -> [SegmentDefinition] {
        let p: String = pathFor(sessionId)
        guard let data = AvoFiles.read(p), let root = AvoJSON.object(data) else { return [] }
        let schema: String = AvoJSON.string(root, "Schema") ?? SegmentStore.schema
        let version: Int = Int(AvoJSON.number(root, "Version") ?? Double(SegmentStore.version))
        let sid: String = AvoJSON.string(root, "SessionId") ?? ""
        if schema != SegmentStore.schema || version > SegmentStore.version || sid != sessionId { return [] }
        var out: [SegmentDefinition] = []
        for item in AvoJSON.array(root, "Segments") ?? [] {
            guard let o = item as? [String: Any] else { continue }
            let d = SegmentDefinition()
            if let v = AvoJSON.string(o, "Id") { d.id = v }
            if let v = AvoJSON.string(o, "Name") { d.name = v }
            let t0: Double = AvoJSON.number(o, "T0") ?? 0
            let t1: Double = AvoJSON.number(o, "T1") ?? 0
            d.t0 = t0
            d.t1 = t1
            if let k = o["Kind"] as? String, let kind = SegmentKind.parse(k) { d.kind = kind }
            else if let n = AvoJSON.number(o, "Kind"), let kind = SegmentKind.from(intValue: Int(n)) { d.kind = kind }
            if let v = AvoJSON.string(o, "Notes") { d.notes = v }
            if let v = AvoJSON.string(o, "CreatedUtc"), let date = DotNetFormat.parseIsoDate(v) { d.createdUtc = date }
            if d.t0.isFinite && d.t1.isFinite { out.append(d) }
        }
        return out
    }

    /// JSON text exactly as System.Text.Json writes the FileModel (WriteIndented, JsonStringEnumConverter).
    static func serialize(_ sessionId: String, _ segments: [SegmentDefinition]) throws -> String {
        var j = DotNetJsonWriter(indented: true)
        j.writeStartObject()
        j.writeString("Schema", schema)
        j.writeNumber("Version", version)
        j.writeString("SessionId", sessionId)
        j.writeStartArray("Segments")
        for s in segments {
            if !s.t0.isFinite || !s.t1.isFinite { throw AvoError.invalidData("Tramo con tiempos no válidos: \(s.name)") }
            j.writeStartObject()
            j.writeString("Id", s.id)
            j.writeString("Name", s.name)
            j.writeNumber("T0", s.t0)
            j.writeNumber("T1", s.t1)
            j.writeString("Kind", s.kind.rawValue)
            j.writeString("Notes", s.notes)
            j.writeString("CreatedUtc", DotNetFormat.jsonDateTimeOffset(s.createdUtc))
            j.writeEndObject()
        }
        j.writeEndArray()
        j.writeEndObject()
        return j.text
    }

    func save(_ sessionId: String, _ segments: [SegmentDefinition]) throws {
        AvoFiles.ensureDir(dir)
        let text: String = try SegmentStore.serialize(sessionId, segments)
        try AvoFiles.writeAtomic(Data(text.utf8), to: pathFor(sessionId))
    }
}

enum TimeText {
    /// C# TimeSpan h:mm:ss (≥ 1 h) or mm:ss; "—" when not finite.
    static func clock(_ seconds: Double) -> String {
        if !seconds.isFinite { return "—" }
        let ticks: Int64 = Int64(max(0, seconds) * 1e7)
        let totalSeconds: Int64 = ticks / 10_000_000
        let h: Int64 = (totalSeconds / 3600) % 24
        let m: Int64 = (totalSeconds / 60) % 60
        let s: Int64 = totalSeconds % 60
        if Double(ticks) / 36_000_000_000.0 >= 1 {
            return String(format: "%ld:%02ld:%02ld", Int(h), Int(m), Int(s))
        }
        return String(format: "%02ld:%02ld", Int(m), Int(s))
    }

    /// C# `d.ToString(fmt, es-ES) + unit`, or `missing` when nil / not finite. `fmt` is a .NET custom format ("0.00", "0.0#", "0").
    static func num(_ v: Double?, _ fmt: String, _ unit: String = "", missing: String = "Sin datos") -> String {
        guard let d = v, d.isFinite else { return missing }
        return DotNetFormat.custom(d, fmt, spanish: true) + unit
    }

    /// Integer overload (C# int widened to double?).
    static func num(_ v: Int, _ fmt: String, _ unit: String = "", missing: String = "Sin datos") -> String {
        num(Double(v), fmt, unit, missing: missing)
    }
}
