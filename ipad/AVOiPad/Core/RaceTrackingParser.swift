import Foundation
import PDFKit

/// Reader of the France Galop / McLloyd «Statistiques Tracking» PDF (one summary page with every runner, then one page per
/// runner with its 200 m sectors). The text extracted by PDFKit may come one value per line (table cells) or with a label
/// and its values on the same line: both are accepted. Values are taken by their label and pattern, never by a fixed line
/// number. Positions per sector are the rank of the cumulative times of every runner at the end of the sector (the
/// position chart of the PDF has no reliable text order).
enum RaceTrackingParser {
    static let unrecognised: String = "Formato de carrera no reconocido: se espera el PDF «Statistiques Tracking» (France Galop / McLloyd) con una página por caballo."

    // ------------------------------------------------------------------ entry points
    static func parse(url: URL) throws -> Race {
        guard let doc = PDFDocument(url: url) else { throw AvoError.invalidData(unrecognised) }
        var pages: [String] = []
        for i in 0..<doc.pageCount {
            let text: String = doc.page(at: i)?.string ?? ""
            pages.append(text)
        }
        return try parse(pages: pages, sourceFile: url.lastPathComponent)
    }

    /// Pure parser over the text of each page (unit tested).
    static func parse(pages: [String], sourceFile: String) throws -> Race {
        guard let first = pages.first, containsLabel(first, "Statistiques Tracking") else {
            throw AvoError.invalidData(unrecognised)
        }
        let header: RaceHeader = parseHeader(first)
        var runners: [RaceRunner] = []
        let summary: String = cleanLines(first).joined(separator: " ")
        for p in pages.dropFirst() {
            if let r = parseRunnerPage(p, distanceM: header.distanceM, summary: summary) { runners.append(r) }
        }
        if runners.isEmpty || header.distanceM <= 0 { throw AvoError.invalidData(unrecognised) }
        let n: Int = runners[0].sectors.count
        if runners.contains(where: { $0.sectors.count != n }) { throw AvoError.invalidData(unrecognised) }

        applySummary(first, &runners)
        computePositions(&runners)
        // finish order when a page has no «Rang d'arrivée»
        if runners.contains(where: { $0.finish == nil }) {
            let order: [Int] = runners.indices.sorted { (runners[$0].officialTimeS ?? .infinity) < (runners[$1].officialTimeS ?? .infinity) }
            for (k, i) in order.enumerated() where runners[i].finish == nil { runners[i].finish = k + 1 }
        }
        runners.sort { ($0.finish ?? 99) < ($1.finish ?? 99) }

        return Race(id: UUID().uuidString, hippodrome: header.hippodrome, raceName: header.raceName, category: header.category,
                    distanceM: header.distanceM, date: header.date, winnerRedk: header.winnerRedk, sourceFile: sourceFile,
                    runners: runners, horseRecordCode: nil, horseName: nil, ourRunnerName: nil, importedAt: Date(),
                    notes: "", isDemo: false)
    }

    // ------------------------------------------------------------------ header
    struct RaceHeader {
        var hippodrome: String = ""
        var raceName: String = ""
        var category: String = ""
        var distanceM: Double = 0
        var date: Date? = nil
        var winnerRedk: Double? = nil
    }

    static func parseHeader(_ page: String) -> RaceHeader {
        var h = RaceHeader()
        let lines: [String] = cleanLines(page)
        if let i = lines.firstIndex(where: { key($0) == key("Statistiques Tracking") }), i + 1 < lines.count {
            h.hippodrome = lines[i + 1]
        }
        // "C3 - PRIX JEAN LABORDE - 1400m"
        for l in lines {
            if key(l).hasPrefix("dep") || key(l).hasPrefix("tron") { continue }
            if let g = RaceRegex.groups(#"^(.+?)\s*-\s*(\d{3,5})\s*m$"#, l), !g[1].matches(#"\d+ ?m$"#) {
                let parts: [String] = g[1].components(separatedBy: " - ").map { $0.trimmed }.filter { !$0.isEmpty }
                if parts.count >= 2 && parts[0].count <= 4 {
                    h.category = parts[0]
                    h.raceName = parts.dropFirst().joined(separator: " - ")
                } else {
                    h.raceName = g[1].trimmed
                }
                h.distanceM = Double(g[2]) ?? 0
                break
            }
        }
        let joined: String = lines.joined(separator: " ")
        h.date = parseFrenchDate(joined)
        if let g = RaceRegex.groups(#"Redk du 1er\s*:?\s*(\d+)'(\d{2})"(\d{2})"#, joined) {
            h.winnerRedk = officialSeconds(g[1], g[2], g[3])
        }
        return h
    }

    static let frenchMonths: [String] = ["janvier", "fevrier", "mars", "avril", "mai", "juin", "juillet", "aout", "septembre",
                                         "octobre", "novembre", "decembre"]

    /// "jeudi 29 octobre 2026 - 00:00" → date (Europe/Paris = Europe/Madrid time zone).
    static func parseFrenchDate(_ text: String) -> Date? {
        let k: String = key(text)
        guard let g = RaceRegex.groups(#"(\d{1,2})(?:er)? ([a-z]+) (\d{4})(?: - (\d{1,2}):(\d{2}))?"#, k) else { return nil }
        guard let m = frenchMonths.firstIndex(of: g[2]) else { return nil }
        var c = DateComponents()
        c.day = Int(g[1])
        c.month = m + 1
        c.year = Int(g[3])
        c.hour = Int(g[4]) ?? 0
        c.minute = Int(g[5]) ?? 0
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = AvoTime.madrid
        return cal.date(from: c)
    }

    // ------------------------------------------------------------------ one runner page
    static let labels: [String] = ["Cheval", "Jockey", "Rang d'arrivée", "Temps de parcours", "Tronçon le plus rapide",
                                   "Vitesse maximale", "Vitesse moyenne", "Temps du tronçon", "Nombre de foulées", "Position",
                                   "en course", "Données de tracking", "Tronçons de 200m"]
    private static let labelKeys: [String] = labels.map { key($0) }.sorted { $0.count > $1.count }

    /// - Parameter summary: text of the summary page (the horse name is a value of this page that also appears there).
    static func parseRunnerPage(_ page: String, distanceM: Double, summary: String = "") -> RaceRunner? {
        let toks: [String] = tokens(page)
        guard toks.contains(where: { key($0) == key("Cheval") }) else { return nil }
        // 1) column groups (PDFKit order: per group of sectors, the label pairs, then cumulative/sector time pairs, speeds,
        //    strides, chart values); 2) rows by label (text extractors that keep table rows together)
        var secValues: [String] = []
        var cumValues: [String] = []
        var speedValues: [String] = []
        var strideValues: [String] = []
        if let c = columnGroups(page) {
            cumValues = c.cum; secValues = c.sec; speedValues = c.speeds; strideValues = c.strides
        } else {
            let sec = row(toks, "Temps du tronçon", isTime, count: nil, from: 0)
            secValues = sec.values
            cumValues = row(toks, "Temps de parcours", isTime, count: secValues.count, from: 0).values
            speedValues = row(toks, "Vitesse moyenne", isNumber, count: secValues.count, from: 0).values
            strideValues = row(toks, "Nombre de foulées", isInteger, count: secValues.count, from: 0).values
        }
        let n: Int = secValues.count
        if n < 2 { return nil }
        if cumValues.count != n { return nil }
        let speeds: (index: Int, values: [String]) = (0, speedValues)
        let strides: (index: Int, values: [String]) = (0, strideValues)
        let cum: (index: Int, values: [String]) = (0, cumValues)
        let sec: (index: Int, values: [String]) = (0, secValues)

        // sector geometry: the last n-1 sectors are `width` m, the first one is the rest of the distance
        let width: Double = sectorWidth(toks)
        if distanceM <= width * Double(n - 1) { return nil }
        var sectors: [RaceSector] = []
        for k in 0..<n {
            let fromRem: Double = k == 0 ? distanceM : width * Double(n - k)
            let toRem: Double = width * Double(n - 1 - k)
            let fromText: String = k == 0 ? "DEP" : "\(Int(fromRem))m"
            let toText: String = toRem <= 0 ? "ARR" : "\(Int(toRem))m"
            let spd: Double? = speeds.values.count == n ? number(speeds.values[k]) : nil
            let str: Int? = strides.values.count == n ? Int(strides.values[k]) : nil
            sectors.append(RaceSector(label: "\(fromText) - \(toText)", fromM: distanceM - fromRem, toM: distanceM - toRem,
                                      cumulativeS: timeSeconds(cum.values[k]) ?? .nan, sectorS: timeSeconds(sec.values[k]) ?? .nan,
                                      meanSpeedKmh: spd, strides: str, position: nil))
        }
        if sectors.contains(where: { !$0.cumulativeS.isFinite || !$0.sectorS.isFinite }) { return nil }

        // header values (between «Redk du 1er» and «Données de tracking»), labels removed
        let redkKey: String = key("Redk du 1er")
        let dataKey: String = key("Données de tracking")
        let redkIndex: Int? = toks.firstIndex(where: { (t: String) -> Bool in key(t).hasPrefix(redkKey) })
        let h0: Int = (redkIndex ?? -1) + 1
        let h1: Int = toks.firstIndex(where: { (t: String) -> Bool in key(t) == dataKey }) ?? toks.count
        var values: [String] = []
        if h0 < h1 {
            for t in toks[h0..<h1] where !labelKeys.contains(key(t)) { values.append(t) }
        }
        // PDFKit puts the header block («Cheval NAME», «Jockey …», «Rang d'arrivée 5»…) before «Redk du 1er»: read the
        // labelled lines directly and search the regexes over the whole page
        let pageLines: [String] = cleanLines(page)
        let joined: String = pageLines.joined(separator: " ")
        func labelled(_ label: String) -> String? {
            let lk: String = key(label) + " "
            for l in pageLines where key(l).hasPrefix(lk) {
                let v: String = String(l.dropFirst(label.count)).trimmed
                if !v.isEmpty { return v }
            }
            return nil
        }
        if values.isEmpty || !values.contains(where: { summary.isEmpty || summary.contains($0) }) {
            values = []
            if let v = labelled("Cheval") { values.append(v) }
            if let v = labelled("Jockey") { values.append(v) }
            if let v = labelled("Rang d'arrivée") { values.append(v) }
            if let v = labelled("Vitesse moyenne"), isNumber(v) { values.append(v) }
        }
        // horse name: an upper-case value (no dots: jockeys are «G. NAME») also present in the summary; else the first value
        let named: String? = values.first(where: { (v: String) -> Bool in
            v.matches(#"^[A-Z0-9][A-Z0-9 '\-ÀÂÄÇÉÈÊËÎÏÔÖÙÛÜ]*$"#) && !isNumber(v) && (summary.isEmpty || summary.contains(v))
        })
        let name: String = named ?? values.first ?? ""
        var r = RaceRunner(number: nil, draw: nil, name: name, jockey: "", finish: nil, officialTimeS: nil,
                           maxSpeedKmh: nil, maxSpeedSector: "", fastest200S: nil, fastestSector: "", last600S: nil,
                           distanceVsWinnerM: nil, meanSpeedKmh: nil, redk: nil, sectors: sectors)
        if r.name.isEmpty || isTime(r.name) || isNumber(r.name) { return nil }
        if let ni = values.firstIndex(of: name), ni + 1 < values.count {
            let j: String = values[ni + 1]
            if !isNumber(j) && !isTime(j) && !j.contains("redk") && !j.contains("(") { r.jockey = j }
        }
        if let g = RaceRegex.groups(#"(\d{1,2}:\d{2}\.\d{2})\s*redk\s*:\s*(\d+)'(\d{2})"(\d{2})"#, joined) {
            r.officialTimeS = timeSeconds(g[1])
            r.redk = officialSeconds(g[2], g[3], g[4])
        }
        if let g = RaceRegex.groups(#"(\d{1,2}:\d{2}\.\d{2})\s*\(tron[cç]on\s+([^)]+)\)"#, joined) {
            r.fastest200S = timeSeconds(g[1])
            r.fastestSector = g[2].trimmed
        }
        if let g = RaceRegex.groups(#"(?<![\d:.,])(\d{2,3},\d{1,2})\s*\(tron[cç]on\s+([^)]+)\)"#, joined) {
            r.maxSpeedKmh = number(g[1])
            r.maxSpeedSector = g[2].trimmed
        }
        let nums: [String] = values.filter { isNumber($0) }
        if let f = nums.first, let rank = Int(f), rank >= 1 && rank <= 40 { r.finish = rank }
        if nums.count >= 2, let last = nums.last { r.meanSpeedKmh = number(last) }
        if r.officialTimeS == nil { r.officialTimeS = sectors.last?.cumulativeS }
        // last 600 m from the sectors (replaced by the summary value when present)
        if let i = sectors.firstIndex(where: { abs(($0.toM) - (distanceM - 600)) < 0.5 }), let total = sectors.last?.cumulativeS {
            r.last600S = total - sectors[i].cumulativeS
        }
        return r
    }

    /// Sector table read by column groups: each group starts with its «DEP/1200m/…» labels; inside it the times come as
    /// (cumulative, sector) pairs and the first k numbers are the speeds, the next k the strides. Validated: the sector
    /// times must be the differences of the cumulative times.
    static func columnGroups(_ page: String) -> (cum: [String], sec: [String], speeds: [String], strides: [String])? {
        let lines: [String] = cleanLines(page)
        guard let start = lines.firstIndex(where: { (l: String) -> Bool in
            let k: String = key(l)
            return k.hasPrefix("troncons de") && !k.contains("dep")
        }) else { return nil }
        var groups: [(times: [String], nums: [String])] = []
        var prevLabel: Bool = false
        for l in lines[(start + 1)...] {
            if l.matches(#"^(DEP|ARR|\d{3,4} ?m)$"#) {
                if !prevLabel { groups.append((times: [], nums: [])) }
                prevLabel = true
                continue
            }
            prevLabel = false
            if groups.isEmpty { continue }
            if isTime(l) { groups[groups.count - 1].times.append(l) }
            else if isNumber(l) { groups[groups.count - 1].nums.append(l) }
        }
        var cum: [String] = [], sec: [String] = [], speeds: [String] = [], strides: [String] = []
        for g in groups {
            if g.times.isEmpty || g.times.count % 2 != 0 { return nil }
            let k: Int = g.times.count / 2
            for j in 0..<k {
                cum.append(g.times[2 * j])
                sec.append(g.times[2 * j + 1])
            }
            if g.nums.count >= 2 * k {
                speeds.append(contentsOf: g.nums[0..<k])
                strides.append(contentsOf: g.nums[k..<(2 * k)])
            }
        }
        if cum.count < 2 { return nil }
        // validation
        var prev: Double = 0
        for j in 0..<cum.count {
            guard let c = timeSeconds(cum[j]), let s = timeSeconds(sec[j]) else { return nil }
            if abs((c - prev) - s) > 0.06 { return nil }
            prev = c
        }
        if speeds.count != cum.count { speeds = [] }
        if strides.count != cum.count || !strides.allSatisfy({ isInteger($0) }) { strides = [] }
        return (cum, sec, speeds, strides)
    }

    private static func sectorWidth(_ toks: [String]) -> Double {
        for t in toks {
            if let g = RaceRegex.groups(#"^tron[cç]ons de (\d{2,4}) ?m$"#, key(t)), let w = Double(g[1]), w > 0 { return w }
        }
        return 200
    }

    // ------------------------------------------------------------------ summary page: number, draw, last 600 m, «Parcouru vs. 1er»
    static func applySummary(_ page: String, _ runners: inout [RaceRunner]) {
        let lines: [String] = cleanLines(page)
        for i in runners.indices {
            let name: String = runners[i].name
            let pattern: String = "^(?:(\\d{1,2}) )?" + NSRegularExpression.escapedPattern(for: name) + "(?: |$)"
            for (k, l) in lines.enumerated() {
                guard let g = RaceRegex.groups(pattern, l) else { continue }
                if let num = Int(g[1]) {
                    runners[i].number = num
                } else if k > 0, isInteger(lines[k - 1]) {
                    runners[i].number = Int(lines[k - 1])
                } else if k > 1, let d = RaceRegex.groups(#"^\((\d{1,2})\)$"#, lines[k - 1]), isInteger(lines[k - 2]) {
                    // PDFKit order: «3», «(6)», «LINO», «G. GUEDJ-GAY»
                    runners[i].number = Int(lines[k - 2])
                    runners[i].draw = Int(d[1])
                    if runners[i].jockey.isEmpty, k + 1 < lines.count, !isTime(lines[k + 1]), !isNumber(lines[k + 1]) {
                        runners[i].jockey = lines[k + 1]
                    }
                    break
                }
                if k + 1 < lines.count, let d = RaceRegex.groups(#"^\((\d{1,2})\)"#, lines[k + 1]) {
                    runners[i].draw = Int(d[1])
                    if runners[i].jockey.isEmpty {
                        let rest: String = String(lines[k + 1].dropFirst(d[0].count)).trimmed
                        if !rest.isEmpty && !isTime(rest) { runners[i].jockey = rest }
                        else if k + 2 < lines.count && !isTime(lines[k + 2]) && !isNumber(lines[k + 2]) { runners[i].jockey = lines[k + 2] }
                    }
                }
                break
            }
        }
        // official time, last 600 m and the optional distance vs the winner come together: 1'36"96 00:38.85 -0,68
        let joined: String = lines.joined(separator: " ")
        let all: [[String]] = RaceRegex.all(#"(\d+)'(\d{2})"(\d{2}) (\d{1,2}:\d{2}\.\d{2})(?: (-?\d+,\d+)(?![\d:]))?"#, joined)
        var used: Set<Int> = []
        for g in all {
            guard let official = officialSeconds(g[1], g[2], g[3]) else { continue }
            guard let i = runners.indices.first(where: { !used.contains($0) && abs((runners[$0].officialTimeS ?? -1) - official) < 0.006 }) else { continue }
            used.insert(i)
            if let l6 = timeSeconds(g[4]) { runners[i].last600S = l6 }
            if !g[5].isEmpty { runners[i].distanceVsWinnerM = number(g[5]) }
        }
    }

    /// Position at the end of each sector = 1 + runners with a smaller cumulative time.
    static func computePositions(_ runners: inout [RaceRunner]) {
        guard let n = runners.first?.sectors.count else { return }
        for k in 0..<n {
            let times: [Double] = runners.map { $0.sectors[k].cumulativeS }
            for i in runners.indices {
                let c: Double = times[i]
                var p: Int = 1
                for (j, o) in times.enumerated() where j != i && o < c - 0.005 { p += 1 }
                runners[i].sectors[k].position = p
            }
        }
    }

    // ------------------------------------------------------------------ tokens
    /// Lines of the page, trimmed, whitespace collapsed, typographic quotes normalised, empty lines removed.
    static func cleanLines(_ text: String) -> [String] {
        var t: String = text
        let replacements: [(String, String)] = [("\u{2019}", "'"), ("\u{2032}", "'"), ("\u{2018}", "'"), ("\u{201D}", "\""),
                                                 ("\u{201C}", "\""), ("\u{2033}", "\""), ("\u{00A0}", " "), ("\r", "\n")]
        for (a, b) in replacements {
            t = t.replacingOccurrences(of: a, with: b)
        }
        var out: [String] = []
        for raw in t.components(separatedBy: "\n") {
            let l: String = raw.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ").trimmed
            if !l.isEmpty { out.append(l) }
        }
        return out
    }

    /// One token per value: a line that starts with a known label is split into the label and its values.
    static func tokens(_ text: String) -> [String] {
        var out: [String] = []
        for line in cleanLines(text) {
            let k: String = key(line)
            var label: String? = nil
            for l in labelKeys where k == l || k.hasPrefix(l + " ") {
                label = l
                break
            }
            guard let lab = label, k != lab else { out.append(line); continue }
            // the label has the same number of characters after folding (accents removed, case changed)
            let head: String = String(line.prefix(lab.count))
            let rest: String = String(line.dropFirst(lab.count)).trimmed
            out.append(head)
            let parts: [String] = rest.components(separatedBy: " ").filter { !$0.isEmpty }
            if !parts.isEmpty && parts.allSatisfy({ isTime($0) || isNumber($0) }) {
                out.append(contentsOf: parts)
            } else if !rest.isEmpty {
                out.append(rest)
            }
        }
        return out
    }

    /// Values that follow a label (the first occurrence, from `from`, followed by at least `count` (or 3) matching values).
    static func row(_ toks: [String], _ label: String, _ ok: (String) -> Bool, count: Int?, from: Int) -> (index: Int, values: [String]) {
        let lk: String = key(label)
        var i: Int = max(0, from)
        while i < toks.count {
            if key(toks[i]) == lk {
                var vals: [String] = []
                var j: Int = i + 1
                while j < toks.count && ok(toks[j]) {
                    vals.append(toks[j])
                    j += 1
                }
                if let c = count {
                    if vals.count >= c { return (i, Array(vals.prefix(c))) }
                } else if vals.count >= 3 {
                    return (i, vals)
                }
            }
            i += 1
        }
        return (-1, [])
    }

    /// Case- and accent-insensitive comparison key with collapsed whitespace.
    static func key(_ s: String) -> String {
        let f: String = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR")).lowercased()
        return f.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).joined(separator: " ")
    }

    static func containsLabel(_ text: String, _ label: String) -> Bool { key(text).contains(key(label)) }

    // ------------------------------------------------------------------ values
    static func isTime(_ s: String) -> Bool { s.matches(#"^\d{1,2}:\d{2}\.\d{2}$"#) }
    static func isNumber(_ s: String) -> Bool { s.matches(#"^-?\d+(,\d+)?$"#) }
    static func isInteger(_ s: String) -> Bool { s.matches(#"^\d+$"#) }

    /// "01:39.99" → 99.99
    static func timeSeconds(_ s: String) -> Double? {
        let p: [String] = s.components(separatedBy: ":")
        guard p.count == 2, let m = Double(p[0]), let sec = Double(p[1]) else { return nil }
        return m * 60 + sec
    }
    /// 1'36"57 → 96.57
    static func officialSeconds(_ m: String, _ s: String, _ cs: String) -> Double? {
        guard let a = Double(m), let b = Double(s), let c = Double(cs) else { return nil }
        return a * 60 + b + c / 100
    }
    /// "55,91" → 55.91
    static func number(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")) }
}

/// Small NSRegularExpression helpers (groups as strings, "" for a group that did not take part).
enum RaceRegex {
    static func groups(_ pattern: String, _ s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let ns: NSString = s as NSString
        guard let m = re.firstMatch(in: s, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
        return strings(m, ns)
    }

    static func all(_ pattern: String, _ s: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let ns: NSString = s as NSString
        return re.matches(in: s, options: [], range: NSRange(location: 0, length: ns.length)).map { strings($0, ns) }
    }

    private static func strings(_ m: NSTextCheckingResult, _ ns: NSString) -> [String] {
        var out: [String] = []
        for i in 0..<m.numberOfRanges {
            let r: NSRange = m.range(at: i)
            out.append(r.location == NSNotFound ? "" : ns.substring(with: r))
        }
        return out
    }
}
