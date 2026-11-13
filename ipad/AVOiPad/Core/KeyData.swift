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
    /// Engine-time window of the figure (best tramos), to open it in «Gráficas»; nil when it has none.
    var t0: Double? = nil
    var t1: Double? = nil
}

/// One 200 m split of an effort (engine `trabajo_pista.trabajos.lista[].parciales`).
struct KeySplit: Identifiable, Equatable {
    let id: Int
    let label: String
    let timeText: String
    let speedText: String
    /// Speed relative to the fastest split of the effort (0…1), for the bar.
    let share: Double
    let fastest: Bool
    /// Engine-time window of the split.
    let t0: Double
    let t1: Double
}

/// One effort with its splits.
struct KeyEffort: Identifiable, Equatable {
    let id: Int
    let title: String
    let kind: String
    let summary: String
    let t0: Double
    let t1: Double
    let splits: [KeySplit]
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
    var efforts: [KeyEffort] = []
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
    static let noRefCaption: String = "Sin galope a esa velocidad"

    static func == (a: KeyData, b: KeyData) -> Bool {
        a.tiles == b.tiles && a.gaits == b.gaits && a.efforts == b.efforts && a.fixShare == b.fixShare && a.qualityLabel == b.qualityLabel && a.hasEngine == b.hasEngine
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

        /// Best time over `meters` among all efforts: (time, engine t0, effort number).
        func best(_ meters: Double) -> (time: Double, t0: Double?, effort: Int?)? {
            var b: (time: Double, t0: Double?, effort: Int?)? = nil
            for e in efforts {
                for x in (e["mejores"] as? [Any] ?? []) {
                    guard let x = x as? [String: Any], let d = num(x, "distancia_m"), abs(d - meters) < 1,
                          let t = num(x, "tiempo_s"), t > 0 else { continue }
                    if b == nil || t < b!.time { b = (t, num(x, "t0"), num(e, "id").map { Int($0) }) }
                }
            }
            if b == nil && meters == 200, let t = num(trabajos, "mejor_200m_s"), t > 0 { b = (t, nil, nil) }
            return b
        }
        func bestTile(_ id: String, _ meters: Double) -> KeyTile {
            let label: String = "Mejor \(Int(meters)) m"
            guard let b = best(meters) else {
                return KeyTile(id: id, label: label, value: "—", unit: "s", caption: noFastCaption, available: false, group: 0)
            }
            var t = KeyTile(id: id, label: label, value: DotNetFormat.custom(b.time, "0.00", spanish: true), unit: "s",
                            caption: b.effort.map { "Trabajo \($0) · ver en gráficas" } ?? "Mejor tramo de \(Int(meters)) m",
                            available: true, group: 0)
            if let a = b.t0 { t.t0 = a; t.t1 = a + b.time }
            return t
        }
        /// Stride at the breed reference speed k: median over the efforts of `referencia[k]` (same rule as the
        /// engine training summary, training.cpp).
        func reference(_ k: Int, _ key: String) -> Double? {
            var v: [Double] = []
            for e in efforts {
                guard let r = (e["referencia"] as? [Any]), r.count > k, let x = r[k] as? [String: Any],
                      let y = num(x, key), y > 0 else { continue }
                v.append(y)
            }
            return median(v)
        }
        func maxOf(_ key: String) -> Double? {
            var m: Double? = nil
            for e in efforts { if let v = num(e, key), v > 0, m == nil || v > m! { m = v } }
            return m
        }

        var t: [KeyTile] = []
        let vmax: Double? = metrics["velocidad_maxima"]
        t.append(tile("vmax", "Velocidad máxima", vmax.map { $0 * 3.6 }, "0.0", "km/h", "Motor AVO", "Sin datos GNSS", 0))
        t.append(bestTile("best200", 200))
        t.append(bestTile("best600", 600))
        t.append(bestTile("best1000", 1000))
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
        let refs: [Any] = ((tp?["perfil"] as? [String: Any])?["v_referencia"] as? [Any]) ?? []
        let hasStride: Bool = maxOf("l_max_m") != nil || maxOf("f_max_hz") != nil
        for r in 0..<2 {
            let v: Double? = refs.count > r ? (refs[r] as? NSNumber)?.doubleValue : nil
            let at: String = v.map { "a " + DotNetFormat.custom($0 * 3.6, "0", spanish: true) + " km/h" } ?? "a v. ref. \(r + 1)"
            let miss: String = hasStride ? noRefCaption : girthCaption
            t.append(tile("lref\(r + 1)", "Tranco " + at, reference(r, "l_m"), "0.00", "m", "Mediana de los trabajos", miss, 2))
            t.append(tile("fref\(r + 1)", "Frecuencia " + at, reference(r, "f_hz"), "0.00", "tr/s", "Mediana de los trabajos", miss, 2))
        }
        k.tiles = t

        // efforts with their 200 m splits
        for e in efforts {
            guard let id = num(e, "id"), let e0 = num(e, "t0") else { continue }
            var acc: Double = e0
            var raw: [(label: String, time: Double, v: Double, t0: Double)] = []
            for p in (e["parciales"] as? [Any] ?? []) {
                guard let p = p as? [String: Any], let a = num(p, "desde_m"), let b = num(p, "hasta_m"),
                      let ts = num(p, "tiempo_s"), ts > 0 else { continue }
                let v: Double = num(p, "v") ?? (b - a) / ts
                raw.append(("\(Int(a.rounded()))–\(Int(b.rounded())) m", ts, v, acc))
                acc += ts
            }
            if raw.isEmpty { continue }
            let vTop: Double = raw.map { $0.v }.max() ?? 0
            let splits: [KeySplit] = raw.indices.map { (i: Int) -> KeySplit in
                let r = raw[i]
                return KeySplit(id: i, label: r.label, timeText: DotNetFormat.custom(r.time, "0.00", spanish: true),
                         speedText: DotNetFormat.custom(r.v * 3.6, "0.0", spanish: true),
                         share: vTop > 0 ? r.v / vTop : 0, fastest: r.v == vTop, t0: r.t0, t1: r.t0 + r.time)
            }
            let fast: Bool = (e["tipo"] as? String) == "TRABAJO_RAPIDO"
            var parts: [String] = []
            if let d = num(e, "distancia_m") { parts.append(DotNetFormat.custom(d, "0", spanish: true) + " m") }
            if let d = num(e, "duracion_s") { parts.append(TimeText.clock(d)) }
            if let v = num(e, "v_max") { parts.append("máx. " + DotNetFormat.custom(v * 3.6, "0.0", spanish: true) + " km/h") }
            k.efforts.append(KeyEffort(id: Int(id), title: "Trabajo \(Int(id))", kind: fast ? "Trabajo rápido" : "Galope de trabajo",
                                       summary: parts.joined(separator: " · "), t0: e0, t1: num(e, "t1") ?? acc, splits: splits))
        }

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

    /// Median (mean of the two central values when the count is even); nil when empty.
    static func median(_ v: [Double]) -> Double? {
        if v.isEmpty { return nil }
        let s: [Double] = v.sorted()
        let n: Int = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
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

// MARK: - Session navigator (same rules as SessionNavigator in KeyData.cs)

struct NavGroup: Identifiable {
    let id: String
    let title: String
    let entries: [CalendarEntry]
}

enum SessionNavigator {
    static let monthShort: [String] = ["ENE", "FEB", "MAR", "ABR", "MAY", "JUN", "JUL", "AGO", "SEP", "OCT", "NOV", "DIC"]

    /// Sessions grouped by day (Europe/Madrid), newest first; `query` filters by horse (case and accents ignored).
    static func groups(_ all: [CalendarEntry], query: String = "") -> [NavGroup] {
        let cal = TrainingCalendar.calendar
        let q: String = query.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let list: [CalendarEntry] = all
            .filter { q.isEmpty || $0.horse.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains(q) }
            .sorted { $0.start > $1.start }
        var out: [NavGroup] = []
        for e in list {
            let c = cal.dateComponents([.year, .month, .day, .weekday], from: e.start)
            let key: String = "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
            if out.last?.id == key {
                let g: NavGroup = out.removeLast()
                out.append(NavGroup(id: key, title: g.title, entries: g.entries + [e]))
            } else {
                let wd: String = TrainingCalendar.weekdays[((c.weekday ?? 2) + 5) % 7]
                let title: String = "\(wd) \(c.day ?? 0) \(monthShort[max(0, min(11, (c.month ?? 1) - 1))]) \(c.year ?? 0)"
                out.append(NavGroup(id: key, title: title, entries: [e]))
            }
        }
        return out
    }

    /// «HH:mm · caballo» in Europe/Madrid.
    static func itemText(_ e: CalendarEntry) -> String {
        let c = TrainingCalendar.calendar.dateComponents([.hour, .minute], from: e.start)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0) + " · " + e.horse
    }
}
