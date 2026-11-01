import Foundation

// Races (carreras) imported from the France Galop / McLloyd «Statistiques Tracking» PDF. Stored in carreras.json
// (paths.root) with a copy of the PDF in paths.root/carreras/. Nothing here is invented: every value is transcribed from the
// PDF, and the derived values (stride length, positions per sector when missing) are computed from transcribed values.

/// One sector of the race (normally 200 m; the first one is the rest of the distance, e.g. DEP–1200 m in a 1400 m race).
struct RaceSector: Codable, Equatable, Identifiable {
    /// As in the PDF: "DEP - 1200m", "1200m - 1000m", …, "200m - ARR".
    var label: String
    /// Distance covered from the start at the beginning / end of the sector (m).
    var fromM: Double
    var toM: Double
    /// Time at the end of the sector since the start (s).
    var cumulativeS: Double
    /// Duration of the sector (s).
    var sectorS: Double
    /// Mean speed of the sector as printed in the PDF (km/h).
    var meanSpeedKmh: Double?
    /// Number of strides (foulées) in the sector.
    var strides: Int?
    /// Position in the race at the end of the sector.
    var position: Int?

    var id: String { label }
    var lengthM: Double { toM - fromM }

    /// Derived: sector length / strides (m).
    var strideLengthM: Double? {
        guard let n = strides, n > 0, lengthM > 0 else { return nil }
        return lengthM / Double(n)
    }

    /// Speed used by the charts and the analysis: the PDF value, or length / time when the PDF has none.
    var speedKmh: Double? {
        if let v = meanSpeedKmh, v.isFinite, v > 0 { return v }
        if sectorS > 0 && lengthM > 0 { return lengthM / sectorS * 3.6 }
        return nil
    }

    /// Short label for charts: "DEP–1200", "1200–1000", …, "200–ARR".
    var shortLabel: String {
        label.replacingOccurrences(of: "m", with: "").replacingOccurrences(of: " - ", with: "–")
    }

    /// Distance to the finish at the end of the sector (m) given the race distance.
    func remainingAtEnd(_ distanceM: Double) -> Double { max(0, distanceM - toM) }
}

/// One horse of the race (one row of the summary table + its own page).
struct RaceRunner: Codable, Equatable, Identifiable {
    /// Partant (saddle cloth number) and corde (draw).
    var number: Int?
    var draw: Int?
    var name: String
    var jockey: String
    /// Arrivée officielle.
    var finish: Int?
    var officialTimeS: Double?
    var maxSpeedKmh: Double?
    var maxSpeedSector: String
    var fastest200S: Double?
    var fastestSector: String
    var last600S: Double?
    /// «Parcouru vs. 1er»: metres more (+) or less (−) than the winner; nil for the winner (empty in the PDF).
    var distanceVsWinnerM: Double?
    var meanSpeedKmh: Double?
    /// Réduction kilométrique (s per km).
    var redk: Double?
    var sectors: [RaceSector]

    var id: String { name }
}

/// A race imported from the tracking PDF and linked to one horse of the Cuadra.
struct Race: Codable, Equatable, Identifiable {
    var id: String
    var hippodrome: String
    var raceName: String
    /// "C3", … (first part of the race line).
    var category: String
    var distanceM: Double
    var date: Date?
    /// «Redk du 1er» (s per km).
    var winnerRedk: Double?
    /// File name of the PDF copy in paths.root/carreras/.
    var sourceFile: String
    var runners: [RaceRunner]
    /// Our horse: Cuadra record and the runner name in the PDF.
    var horseRecordCode: String?
    var horseName: String?
    var ourRunnerName: String?
    var importedAt: Date
    var notes: String
    /// Demonstration race (capture mode): always shown with the DEMOSTRACIÓN mark.
    var isDemo: Bool

    var fieldSize: Int { runners.count }

    var ourIndex: Int? {
        guard let n = ourRunnerName else { return nil }
        return runners.firstIndex { $0.name == n }
    }
    var ourRunner: RaceRunner? { ourIndex.map { runners[$0] } }

    var winner: RaceRunner? {
        if let w = runners.first(where: { $0.finish == 1 }) { return w }
        return runners.filter { $0.officialTimeS != nil }.min { ($0.officialTimeS ?? 0) < ($1.officialTimeS ?? 0) }
    }

    /// Our gap to the winner (s), nil when unknown.
    var ourGapToWinnerS: Double? {
        guard let o = ourRunner?.officialTimeS, let w = winner?.officialTimeS else { return nil }
        return o - w
    }

    var dateText: String { date.map { AvoTime.text($0, "dd/MM/yyyy") } ?? "Sin fecha" }
    var title: String { raceName.isEmpty ? "Carrera" : raceName }
    var distanceText: String { AvoFormat.n0(distanceM) + " m" }
    var finishText: String {
        guard let r = ourRunner, let f = r.finish else { return "—" }
        return "\(f).º/\(fieldSize)"
    }
}

/// Text helpers of the race pages (Spanish decimal comma).
enum RaceFormat {
    /// 1 cuerpo ≈ 0,2 s (convención usada para convertir tiempo en cuerpos; se indica en la ficha).
    static let secondsPerLength: Double = 0.2

    /// 96.57 → "1'36\"57" (official French notation).
    static func official(_ s: Double?) -> String {
        guard let v = s, v.isFinite, v >= 0 else { return "—" }
        let cs: Int = Int((v * 100).rounded())
        return String(format: "%d'%02d\"%02d", cs / 6000, (cs / 100) % 60, cs % 100)
    }
    /// 13.26 → "13,26 s".
    static func seconds(_ s: Double?, _ decimals: Int = 2) -> String {
        guard let v = s, v.isFinite else { return "—" }
        return AvoFormat.f(v, decimals) + " s"
    }
    static func signedSeconds(_ s: Double?) -> String {
        guard let v = s, v.isFinite else { return "—" }
        return (v > 0 ? "+" : (v < 0 ? "−" : "")) + AvoFormat.f(abs(v), 2) + " s"
    }
    static func kmh(_ v: Double?, _ decimals: Int = 1) -> String {
        guard let x = v, x.isFinite else { return "—" }
        return AvoFormat.f(x, decimals) + " km/h"
    }
    static func metres(_ v: Double?, _ decimals: Int = 2) -> String {
        guard let x = v, x.isFinite else { return "—" }
        return AvoFormat.f(x, decimals) + " m"
    }
    static func signedMetres(_ v: Double?) -> String {
        guard let x = v, x.isFinite else { return "—" }
        return (x > 0 ? "+" : (x < 0 ? "−" : "")) + AvoFormat.f(abs(x), 2) + " m"
    }
    static func lengths(_ s: Double?) -> String {
        guard let v = s, v.isFinite else { return "—" }
        let l: Double = v / secondsPerLength
        return "≈ " + AvoFormat.f(l, 1) + (abs(l - 1) < 0.05 ? " cuerpo" : " cuerpos")
    }
    static func percent(_ ratio: Double?) -> String {
        guard let r = ratio, r.isFinite else { return "—" }
        return AvoFormat.f(r * 100, 0) + " %"
    }
    static func place(_ p: Int?) -> String { p.map { "\($0).º" } ?? "—" }
    static func positions(_ n: Int) -> String { n == 1 ? "1 posición" : "\(n) posiciones" }
}

/// Matching of a Cuadra horse with the runners of the PDF («Zakyna» ⊂ «ZAKYNA AL ZARAYAN»).
enum RaceNames {
    /// Upper case, without accents or punctuation, split in words; the word DEMO is ignored.
    static func tokens(_ s: String) -> [String] {
        let folded: String = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR")).uppercased()
        var clean: String = ""
        for ch in folded {
            if ch.isLetter || ch.isNumber { clean.append(ch) } else { clean.append(" ") }
        }
        return clean.split(separator: " ").map { String($0) }.filter { !$0.isEmpty && $0 != "DEMO" }
    }

    static func normalized(_ s: String) -> String { tokens(s).joined(separator: " ") }

    /// True when the words of one name are the first words of the other (or they are equal).
    static func matches(_ horse: String, _ runner: String) -> Bool {
        let a: [String] = tokens(horse)
        let b: [String] = tokens(runner)
        if a.isEmpty || b.isEmpty { return false }
        if a.count <= b.count { return Array(b.prefix(a.count)) == a }
        return Array(a.prefix(b.count)) == b
    }

    /// Indexes of the runners that match any of the names (name and code of the Cuadra record).
    static func candidates(_ names: [String], _ runners: [RaceRunner]) -> [Int] {
        var out: [Int] = []
        for (i, r) in runners.enumerated() {
            if names.contains(where: { matches($0, r.name) }) { out.append(i) }
        }
        return out
    }
}
