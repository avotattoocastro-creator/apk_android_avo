import Foundation

// «Análisis motor» of a race (trainer, 19/11/2026: «un análisis en profundidad de la carrera, teniendo en cuenta
// entrenamientos anteriores si los tiene, comprobando carreras anteriores si ha tenido mismos oponentes, misma distancia,
// estado de pista… con gráficas y de manera entendible por una persona normal»).
// Pure functions over what is already in the iPad (unit tested): the tracking PDF of this race, the other races imported
// (of this horse and of any other horse), the state of the track typed by the user and the analysis against the trainings
// (RaceReport, Core/RaceAnalysis.swift, whose trainings go through the AVO engine). Nothing is invented: a comparison
// without data says so. Orientative: it never replaces the trainer's judgement nor a veterinary examination.

// MARK: - state of the track

/// State of the track (France Galop scale, «terrain»), typed by the user on the race card (the tracking PDF has none).
enum RaceGoing: String, CaseIterable, Identifiable, Codable {
    case veryFirm = "TRES_LEGER"
    case firm = "LEGER"
    case goodToFirm = "BON_LEGER"
    case good = "BON"
    case goodToSoft = "BON_SOUPLE"
    case soft = "SOUPLE"
    case verySoft = "TRES_SOUPLE"
    case sticky = "COLLANT"
    case heavy = "LOURD"
    case veryHeavy = "TRES_LOURD"

    var id: String { rawValue }

    var french: String {
        switch self {
        case .veryFirm: return "Très léger"
        case .firm: return "Léger"
        case .goodToFirm: return "Bon léger"
        case .good: return "Bon"
        case .goodToSoft: return "Bon souple"
        case .soft: return "Souple"
        case .verySoft: return "Très souple"
        case .sticky: return "Collant"
        case .heavy: return "Lourd"
        case .veryHeavy: return "Très lourd"
        }
    }

    var spanish: String {
        switch self {
        case .veryFirm: return "Muy ligero"
        case .firm: return "Ligero"
        case .goodToFirm: return "Bueno-ligero"
        case .good: return "Bueno"
        case .goodToSoft: return "Bueno-blando"
        case .soft: return "Blando"
        case .verySoft: return "Muy blando"
        case .sticky: return "Pegajoso"
        case .heavy: return "Pesado"
        case .veryHeavy: return "Muy pesado"
        }
    }

    /// "Bueno-blando (Bon souple)".
    var label: String { "\(spanish) (\(french))" }

    /// 0 = firmest … 9 = heaviest.
    var softness: Int { RaceGoing.allCases.firstIndex(of: self) ?? 0 }

    /// Groups used to compare races: firm, good, soft, heavy.
    var group: String {
        switch softness {
        case 0...2: return "firme"
        case 3...4: return "bueno"
        case 5...7: return "blando"
        default: return "pesado"
        }
    }
}

extension Race {
    var goingValue: RaceGoing? { going.flatMap { RaceGoing(rawValue: $0) } }
}

// MARK: - report

struct RaceDeepSectorRow: Identifiable, Equatable {
    var index: Int
    var label: String
    var shortLabel: String
    /// Metres to the finish at the end of the sector.
    var remainingM: Double
    var ourSpeedKmh: Double?
    var winnerSpeedKmh: Double?
    /// Median of the other runners.
    var fieldSpeedKmh: Double?
    /// 1 = fastest of the field in this sector.
    var speedRank: Int?
    var position: Int?
    /// Our cumulative time − the best cumulative time at the end of the sector (s, ≥ 0).
    var gapToLeaderS: Double?
    var strideM: Double?
    var id: Int { index }
}

struct RaceDeepPhase: Identifiable, Equatable {
    var name: String
    var range: String
    var fromSector: Int
    var toSector: Int
    var positionStart: Int?
    var positionEnd: Int?
    var ourTimeS: Double
    var winnerTimeS: Double?
    var fieldMedianTimeS: Double?
    /// 1 = fastest of the field in this phase.
    var timeRank: Int?
    var fieldSize: Int
    /// Our time − the winner's time in this phase (s); nil when we are the winner.
    var lostVsWinnerS: Double?
    var sentence: String
    var id: String { name }
}

/// One race of a rival (with or without our horse).
struct RaceRivalRun: Identifiable, Equatable {
    var raceId: String
    var date: Date?
    var title: String
    var hippodrome: String
    var distanceM: Double
    var rivalPlace: Int?
    var fieldSize: Int
    /// Our horse ran this race too.
    var withUs: Bool
    var ourPlace: Int?
    /// Rival official time − our official time (s): positive = we were faster.
    var diffS: Double?
    var id: String { raceId }
}

struct RaceRival: Identifiable, Equatable {
    var name: String
    var jockey: String
    var finish: Int?
    /// Rival official time − our official time today (s): positive = we were faster.
    var todayDiffS: Double?
    var runs: [RaceRivalRun]
    var meetings: Int { runs.filter { $0.withUs }.count }
    var beatenByUs: Int { runs.filter { $0.withUs && ($0.ourPlace ?? 99) < ($0.rivalPlace ?? 99) }.count }
    var beatUs: Int { runs.filter { $0.withUs && ($0.rivalPlace ?? 99) < ($0.ourPlace ?? 99) }.count }
    var sentence: String
    var id: String { name }
}

/// One race of our horse (the current one is marked).
struct RacePastEntry: Identifiable, Equatable {
    var raceId: String
    var date: Date?
    var title: String
    var hippodrome: String
    var distanceM: Double
    var going: RaceGoing?
    var place: Int?
    var fieldSize: Int
    /// (place − 1) / (field − 1): 0 = won, 1 = last.
    var relative: Double?
    var redk: Double?
    var gapToWinnerS: Double?
    var lastSectorKmh: Double?
    var sameDistance: Bool
    var sameGoing: Bool
    var sameHippodrome: Bool
    var isCurrent: Bool
    var id: String { raceId }
}

struct RaceDeepReport: Equatable {
    var headline: String = ""
    var subhead: String = ""
    var phases: [RaceDeepPhase] = []
    var sectors: [RaceDeepSectorRow] = []
    var rivals: [RaceRival] = []
    var rivalsText: String = ""
    /// Races of our horse, oldest first, including the current one (isCurrent).
    var history: [RacePastEntry] = []
    var distanceText: String = ""
    var goingText: String = ""
    var hippodromeText: String = ""
    var trainingLines: [String] = []
    var trainingWorks: [TrainingFastWork] = []
    var conclusions: [String] = []
    var nextTime: [String] = []
    var confidence: RaceConfidence = .low
    var confidenceReason: String = ""
    var method: [String] = []
}

// MARK: - engine

enum RaceDeepEngine {
    /// Same distance when within ± this (m).
    static let sameDistanceToleranceM: Double = 100

    /// - Parameters:
    ///   - race: the race; `ourIndex` our runner.
    ///   - allRaces: every race imported in the iPad (the current one may be included; it is skipped).
    ///   - report: analysis against the trainings (nil while it is being computed).
    static func analyze(race: Race, ourIndex: Int, allRaces: [Race], report: RaceReport?) -> RaceDeepReport {
        var out = RaceDeepReport()
        guard ourIndex >= 0 && ourIndex < race.runners.count else { return out }
        let us: RaceRunner = race.runners[ourIndex]
        let n: Int = us.sectors.count

        out.sectors = sectorRows(race, ourIndex)
        out.phases = phases(race, ourIndex)
        headline(race, ourIndex, &out)

        let previous: [Race] = allRaces.filter { $0.id != race.id && isBefore($0, race) }
        out.rivals = rivals(race, ourIndex, previous)
        out.rivalsText = rivalsSummary(out.rivals)
        out.history = history(race, ourIndex, allRaces)
        let past: [RacePastEntry] = out.history.filter { !$0.isCurrent }
        out.distanceText = distanceInsight(race, us, past)
        out.goingText = goingInsight(race, past)
        out.hippodromeText = hippodromeInsight(race, past)
        if let rep = report {
            out.trainingLines = trainingLines(rep)
            out.trainingWorks = rep.fastWorkList
        } else {
            out.trainingLines = ["Calculando el análisis de los entrenamientos…"]
        }
        conclusions(race, ourIndex, report, past, &out)
        confidence(race, us, report, past, n, &out)
        out.method = method
        return out
    }

    // ------------------------------------------------------------------ helpers
    static func isBefore(_ a: Race, _ b: Race) -> Bool {
        guard let db = b.date else { return true }
        guard let da = a.date else { return false }
        return da < db
    }

    static func median(_ v: [Double]) -> Double? {
        let m: Double = Stats.median(v)
        return m.isFinite ? m : nil
    }

    /// Our runner in another race: same Cuadra horse and its runner, or a runner with the same name.
    static func ourRunner(in r: Race, horseCode: String?, name: String) -> RaceRunner? {
        if let code = horseCode, let c = r.horseRecordCode, c.caseInsensitiveCompare(code) == .orderedSame, let u = r.ourRunner { return u }
        let key: String = RaceNames.normalized(name)
        return r.runners.first { RaceNames.normalized($0.name) == key }
    }

    static func relative(_ place: Int?, _ field: Int) -> Double? {
        guard let p = place, field > 1 else { return place == nil ? nil : 0 }
        return Double(p - 1) / Double(field - 1)
    }

    /// "en cabeza", "en la primera mitad", "en la segunda mitad".
    static func relativeWords(_ r: Double) -> String {
        if r <= 0.2 { return "en cabeza" }
        if r <= 0.5 { return "en la primera mitad" }
        return "en la segunda mitad"
    }

    static func remaining(_ race: Race, _ m: Double) -> Int { Int(max(0, race.distanceM - m).rounded()) }

    /// "1.º/6".
    static func placeText(_ p: Int?, _ field: Int) -> String { p.map { "\($0).º/\(field)" } ?? "—" }

    // ------------------------------------------------------------------ sectors
    static func sectorRows(_ race: Race, _ ourIndex: Int) -> [RaceDeepSectorRow] {
        let us: RaceRunner = race.runners[ourIndex]
        let winner: RaceRunner? = race.winner
        var rows: [RaceDeepSectorRow] = []
        for (k, s) in us.sectors.enumerated() {
            let others: [Double] = race.runners.enumerated().filter { $0.offset != ourIndex }
                .compactMap { $0.element.sectors[safe: k]?.speedKmh }
            let all: [Double] = race.runners.compactMap { $0.sectors[safe: k]?.speedKmh }
            var rank: Int? = nil
            if let mine = s.speedKmh { rank = 1 + all.filter { $0 > mine + 0.0001 }.count }
            let cumul: [Double] = race.runners.compactMap { $0.sectors[safe: k]?.cumulativeS }.filter { $0 > 0 }
            var gap: Double? = nil
            if let best = cumul.min(), s.cumulativeS > 0 { gap = max(0, s.cumulativeS - best) }
            rows.append(RaceDeepSectorRow(index: k, label: s.label, shortLabel: s.shortLabel,
                                          remainingM: s.remainingAtEnd(race.distanceM), ourSpeedKmh: s.speedKmh,
                                          winnerSpeedKmh: winner?.sectors[safe: k]?.speedKmh, fieldSpeedKmh: median(others),
                                          speedRank: rank, position: s.position, gapToLeaderS: gap, strideM: s.strideLengthM))
        }
        return rows
    }

    // ------------------------------------------------------------------ phases (start, middle, final)
    /// Sector ranges of the phases: start = first sector, final = last two (normally the last 400 m), middle = the rest.
    static func phaseRanges(_ n: Int) -> [(String, Int, Int)] {
        if n <= 0 { return [] }
        if n == 1 { return [("Toda la carrera", 0, 0)] }
        if n == 2 { return [("Salida", 0, 0), ("Final", 1, 1)] }
        if n == 3 { return [("Salida", 0, 0), ("Desarrollo", 1, 1), ("Final", 2, 2)] }
        return [("Salida", 0, 0), ("Desarrollo", 1, n - 3), ("Final", n - 2, n - 1)]
    }

    static func phaseTime(_ r: RaceRunner, _ a: Int, _ b: Int) -> Double? {
        var t: Double = 0
        for k in a...b {
            guard let s = r.sectors[safe: k], s.sectorS > 0 else { return nil }
            t += s.sectorS
        }
        return t
    }

    static func phases(_ race: Race, _ ourIndex: Int) -> [RaceDeepPhase] {
        let us: RaceRunner = race.runners[ourIndex]
        let winnerIndex: Int? = race.winner.flatMap { w in race.runners.firstIndex { $0.name == w.name } }
        var out: [RaceDeepPhase] = []
        for (name, a, b) in phaseRanges(us.sectors.count) {
            guard let mine = phaseTime(us, a, b) else { continue }
            let from: Double = us.sectors[a].fromM
            let to: Double = us.sectors[b].toM
            let range: String
            if a == 0 && remaining(race, to) == 0 { range = "\(Int(race.distanceM)) m" }
            else if a == 0 { range = "de la salida a falta de \(remaining(race, to)) m" }
            else if remaining(race, to) == 0 { range = "últimos \(remaining(race, from)) m" }
            else { range = "de \(remaining(race, from)) a \(remaining(race, to)) m de la meta" }
            let times: [Double] = race.runners.compactMap { phaseTime($0, a, b) }
            let rank: Int = 1 + times.filter { $0 < mine - 0.005 }.count
            let others: [Double] = race.runners.enumerated().filter { $0.offset != ourIndex }.compactMap { phaseTime($0.element, a, b) }
            let fieldMedian: Double? = median(others)
            var winnerTime: Double? = nil
            var lost: Double? = nil
            if let w = winnerIndex, w != ourIndex, let wt = phaseTime(race.runners[w], a, b) {
                winnerTime = wt
                lost = mine - wt
            }
            let posStart: Int? = a > 0 ? us.sectors[a - 1].position : nil
            let posEnd: Int? = us.sectors[b].position
            var s: String = "\(name) (\(range)): "
            if let p0 = posStart, let p1 = posEnd {
                if p1 < p0 { s += "pasó de \(p0).º a \(p1).º (ganó \(RaceFormat.positions(p0 - p1)))" }
                else if p1 > p0 { s += "pasó de \(p0).º a \(p1).º (perdió \(RaceFormat.positions(p1 - p0)))" }
                else { s += "mantuvo el \(p1).º puesto" }
            } else if let p1 = posEnd {
                s += b == us.sectors.count - 1 ? "terminó \(p1).º" : "iba \(p1).º al terminar esta parte"
            } else {
                s += "sin posición en el PDF"
            }
            s += "; fue el \(rank == 1 ? "más rápido" : "\(rank).º más rápido") de \(times.count)"
            if let l = lost {
                if l > 0.005 { s += " y le cedió \(RaceFormat.seconds(l)) al ganador (\(RaceFormat.lengths(l)))" }
                else if l < -0.005 { s += " y le sacó \(RaceFormat.seconds(-l)) al ganador" }
                else { s += " e hizo el mismo tiempo que el ganador" }
            } else if let m = fieldMedian {
                let d: Double = m - mine
                if abs(d) >= 0.005 { s += ", \(RaceFormat.seconds(abs(d))) " + (d > 0 ? "más rápido" : "más lento") + " que el caballo medio" }
            }
            out.append(RaceDeepPhase(name: name, range: range, fromSector: a, toSector: b, positionStart: posStart, positionEnd: posEnd,
                                     ourTimeS: mine, winnerTimeS: winnerTime, fieldMedianTimeS: fieldMedian, timeRank: rank,
                                     fieldSize: times.count, lostVsWinnerS: lost, sentence: s + "."))
        }
        return out
    }

    // ------------------------------------------------------------------ headline
    static func headline(_ race: Race, _ ourIndex: Int, _ out: inout RaceDeepReport) {
        let us: RaceRunner = race.runners[ourIndex]
        let field: Int = race.fieldSize
        var going: String = ""
        if let g = race.goingValue { going = " · pista \(g.spanish.lowercased())" }
        out.subhead = "\(race.hippodrome) · \(race.dateText) · \(race.distanceText)\(going) · \(field) participantes"
        guard let finish = us.finish else {
            out.headline = "Sin puesto de llegada en el PDF: solo se analiza el recorrido."
            return
        }
        if finish == 1 {
            var s: String = "Ganó la carrera"
            let others: [Double] = race.runners.enumerated().filter { $0.offset != ourIndex }.compactMap { $0.element.officialTimeS }
            if let o = us.officialTimeS, let second = others.min() {
                s += " por \(RaceFormat.seconds(second - o)) (\(RaceFormat.lengths(second - o)))"
            }
            s += "."
            if let best = out.phases.min(by: { ($0.timeRank ?? 99) < ($1.timeRank ?? 99) }), best.timeRank == 1 {
                s += " La ganó en: \(best.name.lowercased()) (\(best.range)), donde fue el más rápido."
            }
            out.headline = s
            return
        }
        var s: String = "Terminó \(finish).º de \(field)"
        if let g = race.ourGapToWinnerS { s += ", a \(RaceFormat.seconds(g)) del ganador (\(RaceFormat.lengths(g)))" }
        s += "."
        if let worst = out.phases.filter({ ($0.lostVsWinnerS ?? 0) > 0.05 }).max(by: { ($0.lostVsWinnerS ?? 0) < ($1.lostVsWinnerS ?? 0) }) {
            s += " Donde más perdió: \(worst.name.lowercased()) (\(worst.range)), \(RaceFormat.seconds(worst.lostVsWinnerS)) frente al ganador."
        }
        out.headline = s
    }

    // ------------------------------------------------------------------ rivals and head to head
    static func rivals(_ race: Race, _ ourIndex: Int, _ previous: [Race]) -> [RaceRival] {
        let us: RaceRunner = race.runners[ourIndex]
        var out: [RaceRival] = []
        for (i, r) in race.runners.enumerated() where i != ourIndex {
            let key: String = RaceNames.normalized(r.name)
            var runs: [RaceRivalRun] = []
            for p in previous {
                guard let rv = p.runners.first(where: { RaceNames.normalized($0.name) == key }) else { continue }
                let mine: RaceRunner? = ourRunner(in: p, horseCode: race.horseRecordCode, name: us.name)
                var diff: Double? = nil
                if let a = rv.officialTimeS, let b = mine?.officialTimeS { diff = a - b }
                runs.append(RaceRivalRun(raceId: p.id, date: p.date, title: p.title, hippodrome: p.hippodrome, distanceM: p.distanceM,
                                         rivalPlace: rv.finish, fieldSize: p.fieldSize, withUs: mine != nil, ourPlace: mine?.finish,
                                         diffS: diff))
            }
            runs.sort { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            var today: Double? = nil
            if let a = r.officialTimeS, let b = us.officialTimeS { today = a - b }
            var rival = RaceRival(name: r.name, jockey: r.jockey, finish: r.finish, todayDiffS: today, runs: runs, sentence: "")
            rival.sentence = rivalSentence(rival, us)
            out.append(rival)
        }
        return out.sorted { ($0.finish ?? 99) < ($1.finish ?? 99) }
    }

    static func rivalSentence(_ r: RaceRival, _ us: RaceRunner) -> String {
        var s: String = ""
        if let d = r.todayDiffS {
            if d > 0.005 { s = "Hoy le ganamos por \(RaceFormat.seconds(d))." }
            else if d < -0.005 { s = "Hoy nos ganó por \(RaceFormat.seconds(-d))." }
            else { s = "Hoy, mismo tiempo." }
        }
        if r.meetings > 0 {
            s += " Antes de hoy: \(r.meetings) \(r.meetings == 1 ? "carrera juntos" : "carreras juntos"), "
                + "le ganamos \(r.beatenByUs) y nos ganó \(r.beatUs)."
        } else {
            s += " Sin carreras anteriores juntos en el iPad."
        }
        let alone: [RaceRivalRun] = r.runs.filter { !$0.withUs }
        if !alone.isEmpty {
            let places: String = alone.prefix(4).map { placeText($0.rivalPlace, $0.fieldSize) }.joined(separator: ", ")
            s += " Otras carreras suyas: \(places)."
        }
        return s.trimmed
    }

    static func rivalsSummary(_ rivals: [RaceRival]) -> String {
        let met: [RaceRival] = rivals.filter { $0.meetings > 0 }
        let known: Int = rivals.filter { !$0.runs.isEmpty }.count
        if known == 0 {
            return "No hay carreras anteriores de estos rivales en el iPad. Importa más PDF de carreras para comparar."
        }
        if met.isEmpty {
            return "No había corrido antes contra ninguno de estos rivales (en las carreras del iPad); \(known) de ellos tienen otras carreras importadas."
        }
        let won: Int = met.reduce(0) { $0 + $1.beatenByUs }
        let lost: Int = met.reduce(0) { $0 + $1.beatUs }
        let names: String = met.map { $0.name }.joined(separator: ", ")
        return "Ya se había enfrentado a \(met.count) de estos rivales (\(names)): en esos enfrentamientos quedó por delante \(won) "
            + "\(won == 1 ? "vez" : "veces") y por detrás \(lost)."
    }

    // ------------------------------------------------------------------ races of our horse
    static func history(_ race: Race, _ ourIndex: Int, _ allRaces: [Race]) -> [RacePastEntry] {
        let us: RaceRunner = race.runners[ourIndex]
        let going: RaceGoing? = race.goingValue
        var list: [RacePastEntry] = []
        for r in allRaces where r.id == race.id || isBefore(r, race) {
            let mine: RaceRunner? = r.id == race.id ? us : ourRunner(in: r, horseCode: race.horseRecordCode, name: us.name)
            guard let m = mine else { continue }
            var gap: Double? = nil
            if let o = m.officialTimeS, let w = r.winner?.officialTimeS { gap = o - w }
            let g: RaceGoing? = r.goingValue
            list.append(RacePastEntry(raceId: r.id, date: r.date, title: r.title, hippodrome: r.hippodrome, distanceM: r.distanceM,
                                      going: g, place: m.finish, fieldSize: r.fieldSize, relative: relative(m.finish, r.fieldSize),
                                      redk: m.redk, gapToWinnerS: gap, lastSectorKmh: m.sectors.last?.speedKmh,
                                      sameDistance: abs(r.distanceM - race.distanceM) <= sameDistanceToleranceM,
                                      sameGoing: going != nil && g?.group == going?.group,
                                      sameHippodrome: RaceNames.normalized(r.hippodrome) == RaceNames.normalized(race.hippodrome),
                                      isCurrent: r.id == race.id))
        }
        return list.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    static func meanRelative(_ l: [RacePastEntry]) -> Double? {
        let v: [Double] = l.compactMap { $0.relative }
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }

    static func places(_ l: [RacePastEntry]) -> String {
        l.map { placeText($0.place, $0.fieldSize) }.joined(separator: ", ")
    }

    static func distanceInsight(_ race: Race, _ us: RaceRunner, _ past: [RacePastEntry]) -> String {
        if past.isEmpty {
            return "No hay carreras anteriores de este caballo en el iPad. Importa sus PDF de tracking para comparar distancias."
        }
        let tol: Double = sameDistanceToleranceM
        let same: [RacePastEntry] = past.filter { $0.sameDistance }
        let shorter: [RacePastEntry] = past.filter { $0.distanceM < race.distanceM - tol }
        let longer: [RacePastEntry] = past.filter { $0.distanceM > race.distanceM + tol }
        var s: String = ""
        if same.isEmpty {
            s = "Es su primera carrera en \(race.distanceText) (±\(Int(tol)) m) de las que hay en el iPad."
        } else {
            s = "En \(race.distanceText) (±\(Int(tol)) m) había corrido \(same.count) \(same.count == 1 ? "vez" : "veces"): \(places(same))."
            let redks: [Double] = same.compactMap { $0.redk }
            if let today = us.redk, let best = redks.min() {
                if today < best - 0.005 {
                    s += " Hoy hizo su mejor reducción kilométrica a esta distancia (\(RaceFormat.official(today)), antes \(RaceFormat.official(best)))."
                } else {
                    s += " Su reducción kilométrica de hoy (\(RaceFormat.official(today))) es \(RaceFormat.seconds(today - best)) por km más lenta que su mejor a esta distancia (\(RaceFormat.official(best)))."
                }
            }
        }
        var bands: [(String, Double)] = []
        if let m = meanRelative(shorter) { bands.append(("más cortas", m)) }
        if let m = meanRelative(same) { bands.append(("esta distancia", m)) }
        if let m = meanRelative(longer) { bands.append(("más largas", m)) }
        if bands.count >= 2, let best = bands.min(by: { $0.1 < $1.1 }) {
            s += " Por puesto medio, sus mejores resultados han sido en \(best.0) (\(relativeWords(best.1)))."
        }
        if past.count < 3 { s += " Pocas carreras: tómalo como una pista, no como una conclusión." }
        return s
    }

    static func goingInsight(_ race: Race, _ past: [RacePastEntry]) -> String {
        guard let g = race.goingValue else {
            return "Falta el estado de la pista de esta carrera: indícalo arriba para comparar con sus otras carreras."
        }
        let known: [RacePastEntry] = past.filter { $0.going != nil }
        if past.isEmpty { return "Pista \(g.label). No hay carreras anteriores con las que comparar." }
        if known.isEmpty {
            return "Pista \(g.label). Sus otras \(past.count) carreras no tienen el estado de la pista: añádelo en cada una para compararlas."
        }
        let same: [RacePastEntry] = known.filter { $0.going?.group == g.group }
        var s: String = "Pista \(g.label). "
        if same.isEmpty {
            s += "Primera vez en pista de tipo «\(g.group)» entre las carreras con el estado anotado."
        } else {
            s += "En pista de tipo «\(g.group)» había corrido \(same.count) \(same.count == 1 ? "vez" : "veces"): \(places(same))."
        }
        var groups: [String: [RacePastEntry]] = [:]
        for e in known { groups[e.going?.group ?? "", default: []].append(e) }
        var means: [(String, Double)] = []
        for k in groups.keys.sorted() {
            if let m = meanRelative(groups[k] ?? []) { means.append((k, m)) }
        }
        if means.count >= 2, let best = means.min(by: { $0.1 < $1.1 }) {
            s += " Sus mejores puestos han sido en pista «\(best.0)» (\(relativeWords(best.1)))."
        }
        if past.count > known.count { s += " (\(past.count - known.count) carreras sin estado de pista anotado.)" }
        return s
    }

    static func hippodromeInsight(_ race: Race, _ past: [RacePastEntry]) -> String {
        let same: [RacePastEntry] = past.filter { $0.sameHippodrome }
        if race.hippodrome.isEmpty { return "" }
        if same.isEmpty { return "Primera carrera en \(race.hippodrome) de las que hay en el iPad." }
        return "En \(race.hippodrome) había corrido \(same.count) \(same.count == 1 ? "vez" : "veces"): \(places(same))."
    }

    // ------------------------------------------------------------------ trainings
    static func trainingLines(_ rep: RaceReport) -> [String] {
        var out: [String] = []
        if rep.trainingSessions == 0 {
            out.append("No hay entrenamientos de este caballo en el iPad antes de la carrera: el análisis se basa solo en las carreras.")
        } else {
            var s: String = "\(rep.trainingSessions) \(rep.trainingSessions == 1 ? "entrenamiento" : "entrenamientos") antes de la carrera"
            if let a = rep.trainingFrom, let b = rep.trainingTo {
                s += " (del \(AvoTime.text(a, "dd/MM/yyyy")) al \(AvoTime.text(b, "dd/MM/yyyy")))"
            }
            s += ", con \(rep.fastWorks) \(rep.fastWorks == 1 ? "trabajo rápido" : "trabajos rápidos") (más de 40 km/h)."
            if rep.trainingDemo { s += " Incluye DEMOSTRACIÓN (datos sintéticos)." }
            out.append(s)
            var bests: [String] = []
            if let v = rep.best200Kmh { bests.append("200 m a \(RaceFormat.kmh(v))") }
            if let v = rep.best400Kmh { bests.append("400 m a \(RaceFormat.kmh(v))") }
            if let v = rep.best600Kmh { bests.append("600 m a \(RaceFormat.kmh(v))") }
            if !bests.isEmpty { out.append("Lo más rápido en entrenamiento: " + bests.joined(separator: ", ") + ".") }
            if !rep.trendText.isEmpty { out.append(rep.trendText) }
            if let tf = rep.trainingFade, let f = rep.ourFade {
                out.append("Al final de sus trabajos conserva el \(RaceFormat.percent(tf)) de su punta; en la carrera conservó el \(RaceFormat.percent(f)).")
            }
        }
        if let f = rep.form {
            var s: String = "Forma el día de la carrera: \(f.level)"
            if let a = f.acwr { s += " · carga aguda/crónica (ACWR) \(AvoFormat.f(a, 2))" + (f.acwrOutOfBand ? " (fuera de banda)" : "") }
            if let d = f.daysSinceLast { s += " · \(d) \(d == 1 ? "día" : "días") desde el último entrenamiento" }
            out.append(s + ". Orientativo, no es un diagnóstico.")
        } else if !rep.formState.isEmpty {
            out.append("Forma antes de la carrera: \(rep.formState).")
        }
        if !rep.verdict.isEmpty { out.append("Si hubiera rematado como en sus entrenamientos: " + rep.verdict) }
        return out
    }

    // ------------------------------------------------------------------ conclusions
    static func conclusions(_ race: Race, _ ourIndex: Int, _ rep: RaceReport?, _ past: [RacePastEntry], _ out: inout RaceDeepReport) {
        let us: RaceRunner = race.runners[ourIndex]
        var c: [String] = [out.headline]
        var next: [String] = []
        if let best = out.phases.min(by: { ($0.timeRank ?? 99) < ($1.timeRank ?? 99) }), let r = best.timeRank, out.phases.count > 1 {
            c.append("Lo mejor: \(best.name.lowercased()) (\(best.range)), \(r == 1 ? "el más rápido" : "el \(r).º más rápido") de \(best.fieldSize).")
        }
        if let worst = out.phases.max(by: { ($0.timeRank ?? 0) < ($1.timeRank ?? 0) }), let r = worst.timeRank, r > (worst.fieldSize + 1) / 2,
           out.phases.count > 1 {
            c.append("Lo más flojo: \(worst.name.lowercased()) (\(worst.range)), el \(r).º de \(worst.fieldSize).")
            switch worst.name {
            case "Salida": next.append("La salida fue su parte más lenta: vale la pena trabajar la salida y la colocación en los primeros metros.")
            case "Final": next.append("El final fue su parte más lenta: conviene revisar la resistencia a ritmo de carrera en los últimos 400 m.")
            default: next.append("Perdió ritmo a mitad de carrera: revisar el ritmo de crucero y la colocación en el grupo.")
            }
        }
        if let d = us.distanceVsWinnerM, d > 5 {
            let s: Double? = RaceAnalysis.groundLoss(us)
            c.append("Recorrió \(RaceFormat.metres(d)) más que el ganador (≈ \(RaceFormat.seconds(s))): la colocación le costó tiempo.")
            next.append("Buscar un recorrido más corto (más pegado a la cuerda) si la carrera lo permite.")
        }
        let stride: [Double] = us.sectors.compactMap { $0.strideLengthM }
        if stride.count >= 3, let last = stride.last, let best = stride.dropLast().max(), last < best * 0.97 {
            c.append("Su zancada se acortó al final (\(RaceFormat.metres(last)) frente a \(RaceFormat.metres(best))): señal de cansancio.")
        }
        if !out.rivalsText.isEmpty && out.rivals.contains(where: { $0.meetings > 0 }) { c.append(out.rivalsText) }
        let same: [RacePastEntry] = past.filter { $0.sameDistance }
        if past.count >= 2 {
            let shorter: Double? = meanRelative(past.filter { $0.distanceM < race.distanceM - sameDistanceToleranceM })
            let longer: Double? = meanRelative(past.filter { $0.distanceM > race.distanceM + sameDistanceToleranceM })
            let here: Double? = meanRelative(same + out.history.filter { $0.isCurrent })
            if let h = here, let s = shorter, s < h - 0.2 { next.append("Por resultados, rinde mejor en distancias más cortas (confirmar con más carreras).") }
            if let h = here, let l = longer, l < h - 0.2 { next.append("Por resultados, rinde mejor en distancias más largas (confirmar con más carreras).") }
        }
        if let f = rep?.form, f.level == "VIGILAR" || f.level == "REVISAR" {
            c.append("Llegó a la carrera con la forma en \(f.level) según sus entrenamientos.")
            next.append("Revisar la carga de entrenamiento antes de la próxima carrera (orientativo; consultar con el veterinario si hay dudas).")
        }
        if let r = rep, r.trainingSessions == 0 {
            next.append("Grabar los entrenamientos con AVO para poder comparar la carrera con su preparación.")
        }
        if race.goingValue == nil { next.append("Anotar el estado de la pista en cada carrera para saber en qué terreno rinde mejor.") }
        out.conclusions = c.filter { !$0.isEmpty }
        out.nextTime = next
    }

    static func confidence(_ race: Race, _ us: RaceRunner, _ rep: RaceReport?, _ past: [RacePastEntry], _ n: Int,
                           _ out: inout RaceDeepReport) {
        var level: Int = 0
        var why: [String] = []
        let complete: Bool = n >= 3 && us.sectors.allSatisfy { $0.speedKmh != nil && $0.position != nil }
        why.append(complete ? "datos de la carrera completos (\(n) tramos)" : "datos de la carrera incompletos")
        if complete { level += 1 }
        why.append(past.isEmpty ? "sin carreras anteriores en el iPad" : "\(past.count) \(past.count == 1 ? "carrera anterior" : "carreras anteriores")")
        if past.count >= 3 { level += 1 }
        if let r = rep {
            why.append(r.trainingSessions == 0 ? "sin entrenamientos" : "\(r.trainingSessions) entrenamientos (\(r.confidence.rawValue.lowercased()) en su análisis)")
            if r.confidence != .low { level += 1 }
            if r.trainingDemo { level = 0; why.append("incluye DEMOSTRACIÓN") }
        }
        if race.isDemo || race.isVideo {
            level = 0
            why.append(race.isDemo ? "carrera de DEMOSTRACIÓN" : "carrera estimada desde vídeo")
        }
        out.confidence = level >= 3 ? .high : (level >= 2 ? .medium : .low)
        out.confidenceReason = why.joined(separator: "; ")
    }

    static let method: [String] = [
        "Tramos, tiempos, velocidades, zancadas y posiciones salen del PDF de tracking (France Galop / McLloyd). El caballo medio es la mediana de los demás participantes.",
        "Fases: salida = primer tramo; final = dos últimos tramos (normalmente los últimos 400 m); desarrollo = el resto. El puesto de cada fase ordena el tiempo de todos los caballos en esa parte.",
        "Carreras anteriores: las importadas en este iPad con fecha anterior. El caballo se reconoce por su ficha de la Cuadra o por su nombre; los rivales, por su nombre.",
        "Misma distancia = ±100 m. Puesto medio = (puesto − 1) / (participantes − 1): 0 es ganar y 1 es llegar el último. Con menos de 3 carreras las tendencias son solo una pista.",
        "Estado de la pista: escala de France Galop anotada a mano (el PDF no lo trae), agrupada en firme, bueno, blando y pesado.",
        "Entrenamientos: los de este caballo en el iPad antes de la carrera, analizados con el motor AVO actual (el resultado guardado solo se reutiliza si es de la misma versión del motor). 1 cuerpo ≈ 0,2 s.",
        "Todo es orientativo: ayuda al entrenador a leer la carrera, no sustituye su criterio ni un examen veterinario.",
    ]
}
