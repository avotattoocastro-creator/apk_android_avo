import Foundation

// «Datos clave» y «Calendario» — paridad iPad ↔ PC (docs/PARIDAD_IPAD_PC.md).
// Las reglas son IDÉNTICAS a windows/AVO.Windows.Core/Analysis/KeyData.cs: todas las cifras salen del resultado del
// motor AVO Equine (el mismo para iPad y Windows), nunca de un cálculo propio de la app. Lo que el motor no da
// (pulso, recuperaciones) se muestra como «—» con el motivo; nunca se inventa.

/// One tile of «Datos clave».
struct KeyTile: Identifiable, Equatable {
    let id: String
    let label: String
    let value: String
    let unit: String
    let caption: String
    let available: Bool
    /// 0 = velocidad y tiempos, 1 = pulso, 2 = tranco.
    let group: Int
}

/// Time spent in one gait (engine metric `tiempo_<AIRE>`).
struct KeyGait: Identifiable, Equatable {
    let id: String
    let name: String
    let seconds: Double
    let share: Double
}

struct KeyData: Equatable {
    var tiles: [KeyTile] = []
    var gaits: [KeyGait] = []
    /// Fraction (0…1) of the session in RTK FIX, from the engine `rtk` block; nil without data.
    var fixShare: Double? = nil
    /// Dominant position quality: «RTK FIX», «RTK FLOAT», «DGNSS», «GNSS» or «Sin datos».
    var qualityLabel: String = "Sin datos"
    /// Seconds per solution (FIX, FLOAT, DGNSS, GNSS) for the quality bar.
    var qualitySeconds: [(label: String, seconds: Double)] = []
    var hasEngine: Bool = false

    static let ecgCaption: String = "Llega con el ECG de la cincha"
    static let girthCaption: String = "Necesita la cincha montada"
    static let noFastCaption: String = "Sin trabajo rápido detectado"

    static func == (a: KeyData, b: KeyData) -> Bool {
        a.tiles == b.tiles && a.gaits == b.gaits && a.fixShare == b.fixShare && a.qualityLabel == b.qualityLabel && a.hasEngine == b.hasEngine
    }

    // ------------------------------------------------------------------ parsing (same rules as KeyData.cs)
    static func from(json: String) -> KeyData {
        guard let data = json.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              root["formato"] as? String == "avo-equine-analysis" else { return KeyData() }
        var k = KeyData()
        k.hasEngine = true

        var metrics: [String: Double] = [:]
        for m in (root["metricas"] as? [Any] ?? []) {
            guard let m = m as? [String: Any], let name = m["nombre"] as? String, let v = num(m, "valor") else { continue }
            metrics[name] = v
        }
        let tp = root["trabajo_pista"] as? [String: Any]
        let trabajos = tp?["trabajos"] as? [String: Any]
        let efforts: [[String: Any]] = (trabajos?["lista"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }

        func best(_ meters: Double) -> Double? {
            var b: Double? = nil
            for e in efforts {
                for x in (e["mejores"] as? [Any] ?? []) {
                    guard let x = x as? [String: Any], let d = num(x, "distancia_m"), abs(d - meters) < 1,
                          let t = num(x, "tiempo_s"), t > 0 else { continue }
                    if b == nil || t < b! { b = t }
                }
            }
            if b == nil && meters == 200, let t = num(trabajos, "mejor_200m_s"), t > 0 { b = t }
            return b
        }
        func maxOf(_ key: String) -> Double? {
            var m: Double? = nil
            for e in efforts { if let v = num(e, key), v > 0, m == nil || v > m! { m = v } }
            return m
        }

        var t: [KeyTile] = []
        let vmax: Double? = metrics["velocidad_maxima"]
        t.append(tile("vmax", "Velocidad máxima", vmax.map { $0 * 3.6 }, "0.0", "km/h", "Motor AVO", "Sin datos GNSS", 0))
        t.append(tile("best200", "Mejor 200 m", best(200), "0.00", "s", "Mejor tramo de 200 m", noFastCaption, 0))
        t.append(tile("best600", "Mejor 600 m", best(600), "0.00", "s", "Mejor tramo de 600 m", noFastCaption, 0))
        t.append(tile("best1000", "Mejor 1000 m", best(1000), "0.00", "s", "Mejor tramo de 1000 m", noFastCaption, 0))
        t.append(tile("distance", "Distancia", metrics["distancia"].map { $0 / 1000 }, "0.00", "km", "Toda la sesión", "Sin datos", 0))
        let dur: Double? = metrics["duracion"]
        t.append(KeyTile(id: "duration", label: "Duración", value: dur.map { TimeText.clock($0) } ?? "—", unit: "",
                         caption: dur == nil ? "Sin datos" : "Toda la sesión", available: dur != nil, group: 0))
        t.append(KeyTile(id: "hrmax", label: "Pulso máximo", value: "—", unit: "lpm", caption: ecgCaption, available: false, group: 1))
        t.append(KeyTile(id: "rec2", label: "Recuperación a 2 min", value: "—", unit: "lpm", caption: ecgCaption, available: false, group: 1))
        t.append(KeyTile(id: "rec15", label: "Recuperación a 15 min", value: "—", unit: "lpm", caption: ecgCaption, available: false, group: 1))
        t.append(KeyTile(id: "hrend", label: "Pulso al terminar", value: "—", unit: "lpm", caption: ecgCaption, available: false, group: 1))
        t.append(tile("lmax", "Tranco máximo", maxOf("l_max_m"), "0.00", "m", "En galope", girthCaption, 2))
        t.append(tile("fmax", "Frecuencia máxima", maxOf("f_max_hz"), "0.00", "tr/s", "En galope", girthCaption, 2))
        k.tiles = t

        // gaits: engine metrics tiempo_<AIRE> (AIRE in capitals), e.g. tiempo_PASO
        var g: [KeyGait] = []
        for name in metrics.keys.sorted(by: gaitOrder) where name.hasPrefix("tiempo_") {
            let code: String = String(name.dropFirst("tiempo_".count))
            guard !code.isEmpty, code == code.uppercased(), code.range(of: "^[A-Z_]+$", options: .regularExpression) != nil,
                  let s = metrics[name], s > 0 else { continue }
            g.append(KeyGait(id: code, name: gaitName(code), seconds: s, share: 0))
        }
        let total: Double = g.reduce(0) { $0 + $1.seconds }
        k.gaits = g.map { KeyGait(id: $0.id, name: $0.name, seconds: $0.seconds, share: total > 0 ? $0.seconds / total : 0) }

        // position quality: engine `rtk` block
        if let r = root["rtk"] as? [String: Any], let tot = num(r, "total_s"), tot > 0 {
            let parts: [(String, Double)] = [("RTK FIX", num(r, "fix_s") ?? 0), ("RTK FLOAT", num(r, "float_s") ?? 0),
                                             ("DGNSS", num(r, "dgnss_s") ?? 0), ("GNSS", num(r, "gnss_s") ?? 0)]
            k.qualitySeconds = parts.map { (label: $0.0, seconds: $0.1) }
            k.fixShare = (num(r, "fix_s") ?? 0) / tot
            if let top = parts.max(by: { $0.1 < $1.1 }), top.1 > 0 { k.qualityLabel = top.0 }
        }
        return k
    }

    // ------------------------------------------------------------------ helpers
    static func num(_ d: [String: Any]?, _ k: String) -> Double? {
        guard let n = d?[k] as? NSNumber, String(cString: n.objCType) != "c" else { return nil }
        let v: Double = n.doubleValue
        return v.isFinite ? v : nil
    }

    private static func tile(_ id: String, _ label: String, _ v: Double?, _ fmt: String, _ unit: String,
                             _ caption: String, _ missing: String, _ group: Int) -> KeyTile {
        if let v = v, v.isFinite {
            return KeyTile(id: id, label: label, value: DotNetFormat.custom(v, fmt, spanish: true), unit: unit,
                           caption: caption, available: true, group: group)
        }
        return KeyTile(id: id, label: label, value: "—", unit: unit, caption: missing, available: false, group: group)
    }

    static func gaitName(_ code: String) -> String {
        switch code {
        case "PARADO": return "Parado"
        case "PASO": return "Paso"
        case "TROTE": return "Trote"
        case "GALOPE": return "Galope"
        default: return code.prefix(1) + code.dropFirst().lowercased().replacingOccurrences(of: "_", with: " ")
        }
    }

    private static func gaitOrder(_ a: String, _ b: String) -> Bool {
        let order: [String] = ["tiempo_PARADO", "tiempo_PASO", "tiempo_TROTE", "tiempo_GALOPE"]
        let ia: Int = order.firstIndex(of: a) ?? 99, ib: Int = order.firstIndex(of: b) ?? 99
        return ia != ib ? ia < ib : a < b
    }

    // ------------------------------------------------------------------ cache (the analysis JSON can be large)
    private static var cache: [String: (length: Int, data: KeyData)] = [:]
    private static let cacheLock = NSLock()

    /// KeyData of a training, parsed once per engine result.
    static func cached(id: String, json: String) -> KeyData {
        cacheLock.lock()
        if let c = cache[id], c.length == json.utf8.count { cacheLock.unlock(); return c.data }
        cacheLock.unlock()
        let k: KeyData = from(json: json)
        cacheLock.lock()
        cache[id] = (json.utf8.count, k)
        cacheLock.unlock()
        return k
    }
}

// MARK: - Calendar (same rules as TrainingCalendar.cs)

struct CalendarEntry: Identifiable, Equatable {
    let id: String
    let start: Date
    let horse: String
    let durationS: Double
    let distanceKm: Double
    /// Fraction of the session in RTK FIX (engine); nil while the engine has not run.
    let fixShare: Double?
}

struct CalendarDay: Identifiable {
    let id: String
    let day: Int
    let inMonth: Bool
    let isToday: Bool
    let entries: [CalendarEntry]
}

struct CalendarSummary: Equatable {
    var count: Int = 0
    var durationS: Double = 0
    var distanceKm: Double = 0
    /// Sessions with at least 50 % of the time in RTK FIX.
    var rtkCount: Int = 0
    /// Sessions whose engine has run (the RTK count only covers these).
    var analysedCount: Int = 0

    var durationText: String {
        let m: Int = Int((durationS / 60).rounded())
        return m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min"
    }
    var meanText: String {
        count == 0 ? "—" : "\(Int((durationS / Double(count) / 60).rounded())) min"
    }
    var distanceText: String { DotNetFormat.custom(distanceKm, "0.00", spanish: true) + " km" }
    var rtkText: String { analysedCount == 0 ? "—" : "\(rtkCount) de \(analysedCount)" }
}

enum TrainingCalendar {
    static let monthNames: [String] = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto",
                                       "septiembre", "octubre", "noviembre", "diciembre"]
    static let weekdays: [String] = ["LUN", "MAR", "MIÉ", "JUE", "VIE", "SÁB", "DOM"]

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = AvoTime.madrid
        c.firstWeekday = 2
        return c
    }

    /// (year, month) of a date in Europe/Madrid.
    static func yearMonth(_ d: Date) -> (year: Int, month: Int) {
        let c = calendar.dateComponents([.year, .month], from: d)
        return (c.year ?? 2026, c.month ?? 1)
    }

    static func entries(in year: Int, _ month: Int?, _ all: [CalendarEntry]) -> [CalendarEntry] {
        all.filter { (e: CalendarEntry) -> Bool in
            let ym = yearMonth(e.start)
            return ym.year == year && (month == nil || ym.month == month!)
        }
    }

    /// 42 cells (6 weeks, Monday first) of a month in Europe/Madrid.
    static func monthGrid(year: Int, month: Int, entries: [CalendarEntry], today: Date) -> [CalendarDay] {
        let cal = calendar
        guard let first = cal.date(from: DateComponents(year: year, month: month, day: 1)) else { return [] }
        let weekday: Int = cal.component(.weekday, from: first)          // 1 = Sunday … 7 = Saturday
        let lead: Int = (weekday + 5) % 7                                  // days before the 1st, Monday first
        guard let gridStart = cal.date(byAdding: .day, value: -lead, to: first) else { return [] }
        let todayKey = cal.dateComponents([.year, .month, .day], from: today)
        var byDay: [String: [CalendarEntry]] = [:]
        for e in entries {
            let c = cal.dateComponents([.year, .month, .day], from: e.start)
            byDay["\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)", default: []].append(e)
        }
        var out: [CalendarDay] = []
        for i in 0..<42 {
            guard let d = cal.date(byAdding: .day, value: i, to: gridStart) else { continue }
            let c = cal.dateComponents([.year, .month, .day], from: d)
            let key: String = "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
            out.append(CalendarDay(id: key, day: c.day ?? 0, inMonth: c.month == month,
                                   isToday: c.year == todayKey.year && c.month == todayKey.month && c.day == todayKey.day,
                                   entries: (byDay[key] ?? []).sorted { $0.start < $1.start }))
        }
        return out
    }

    static func summary(_ entries: [CalendarEntry]) -> CalendarSummary {
        var s = CalendarSummary()
        for e in entries {
            s.count += 1
            s.durationS += max(0, e.durationS)
            s.distanceKm += max(0, e.distanceKm)
            if let f = e.fixShare {
                s.analysedCount += 1
                if f >= 0.5 { s.rtkCount += 1 }
            }
        }
        return s
    }
}
