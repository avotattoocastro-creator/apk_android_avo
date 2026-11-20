import Foundation

/// State of the track of a race, found automatically (trainer, 20/11/2026: «que sea automático»).
/// 1) The tracking PDF: some carry it under the date («Lourd (4,7)», «Collant (4,4)»; e.g. Auteuil), flat races usually
///    do not. 2) The race page of Equidia (www.equidia.fr/courses/AAAA-MM-DD/R<n>/C<n>), which shows «Terrain Souple
///    3.5 à 05:00» for every race; the reunion is found by the hippodrome and the race by its name. Pure functions here
///    (unit tested); the requests are made by RacesModel.
enum RaceGoingLookup {
    /// France Galop labels, normalized, longest first («TRES SOUPLE» before «SOUPLE», «BON SOUPLE» before «BON»).
    private static let labels: [(String, RaceGoing)] = RaceGoing.allCases
        .map { (norm($0.french), $0) }
        .sorted { $0.0.count > $1.0.count }

    /// Upper case, no accents, letters and digits separated by single spaces.
    static func norm(_ s: String) -> String {
        let f: String = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR")).uppercased()
        var out: String = ""
        for ch in f {
            out.append(ch.isLetter || ch.isNumber ? ch : " ")
        }
        return out.split(separator: " ").joined(separator: " ")
    }

    /// «Bon souple», «BON SOUPLE 3,5», «Très lourd» → state (the text must START with a label, as a whole word).
    static func going(fromText text: String) -> RaceGoing? {
        let n: String = norm(text)
        for (label, g) in labels where n == label || n.hasPrefix(label + " ") {
            return g
        }
        return nil
    }

    /// A header line of the tracking PDF: «Lourd (4,7)» → (Lourd, 4.7). Nothing else on the line.
    static func goingLine(_ line: String) -> (going: RaceGoing, penetrometer: Double?)? {
        let l: String = line.trimmingCharacters(in: .whitespaces)
        guard l.count <= 30, let g = RaceRegex.groups(#"^([A-Za-zÀ-ÿ' ]+?)\s*\((\d+[,.]\d+)\)$"#, l) else { return nil }
        guard let going = going(fromText: g[1]), norm(g[1]) == norm(going.french) else { return nil }
        return (going, Double(g[2].replacingOccurrences(of: ",", with: ".")))
    }

    // ------------------------------------------------------------------ Equidia
    static func equidiaURL(day: String, reunion: Int, course: Int) -> URL? {
        URL(string: "https://www.equidia.fr/courses/\(day)/R\(reunion)/C\(course)")
    }

    /// Course number from the tracking PDF name: «20261118PAU02_last_times_fr.pdf» → 2.
    static func courseNumber(fromFile name: String) -> Int? {
        guard let g = RaceRegex.groups(#"(\d{8})[A-Za-z]{3}(\d{2})"#, name) else { return nil }
        return Int(g[2])
    }

    /// Visible text of an HTML page (scripts and styles removed, tags turned into spaces, spaces collapsed).
    static func pageText(_ html: String) -> String {
        var s: String = html
        for pattern in [#"(?is)<script\b.*?</script>"#, #"(?is)<style\b.*?</style>"#, #"(?s)<!--.*?-->"#, #"<[^>]+>"#] {
            s = s.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        let entities: [(String, String)] = [("&nbsp;", " "), ("&amp;", "&"), ("&#39;", "'"), ("&#x27;", "'"), ("&apos;", "'"),
                                            ("&quot;", "\""), ("&eacute;", "é"), ("&egrave;", "è"), ("&agrave;", "à")]
        for (a, b) in entities { s = s.replacingOccurrences(of: a, with: b) }
        return s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Heading of the race page: «R3 CHATEAUBRIANT C6 PRIX FRANCE GALOP» → (3, "CHATEAUBRIANT", 6).
    /// With `reunion`, the heading of that reunion (pages may also list other races of the day).
    static func heading(_ text: String, reunion: Int? = nil) -> (reunion: Int, hippodrome: String, course: Int)? {
        let n: String = norm(text) + " "
        for g in RaceRegex.all(#"\bR(\d{1,2}) ([A-Z][A-Z ]{1,40}?) C(\d{1,2}) "#, n) {
            guard let r = Int(g[1]), let c = Int(g[3]) else { continue }
            if reunion == nil || reunion == r { return (r, g[2], c) }
        }
        return nil
    }

    /// Same hippodrome: one name contains the other («BORDEAUX» / «BORDEAUX LE BOUSCAT»).
    static func sameHippodrome(_ a: String, _ b: String) -> Bool {
        let x: String = norm(a)
        let y: String = norm(b)
        guard x.count >= 3, y.count >= 3 else { return false }
        return x == y || x.hasPrefix(y + " ") || y.hasPrefix(x + " ") || x.contains(y) || y.contains(x)
    }

    /// True when the page text names this race (the name of the race, normalized, appears in it).
    static func namesRace(_ text: String, _ raceName: String) -> Bool {
        let r: String = norm(raceName)
        return r.count >= 4 && norm(text).contains(r)
    }

    /// «… Terrain Souple 3.5 à 05:00 …» → (Souple, 3.5). Only the capitalised field label «Terrain», so race comments
    /// such as «perdre du terrain» are ignored.
    static func goingFromEquidia(_ text: String) -> (going: RaceGoing, penetrometer: Double?)? {
        var search: Substring = Substring(text)
        while let r = search.range(of: "Terrain ") {
            let after: String = String(search[r.upperBound...].prefix(40))
            if let g = going(fromText: after) {
                var pen: Double? = nil
                if let p = RaceRegex.groups(#"^\D{0,25}?(\d+[.,]\d+)"#, after) {
                    pen = Double(p[1].replacingOccurrences(of: ",", with: "."))
                }
                return (g, pen)
            }
            search = search[r.upperBound...]
        }
        return nil
    }
}
