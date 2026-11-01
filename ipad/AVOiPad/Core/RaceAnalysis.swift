import Foundation

// «Análisis según los entrenamientos»: what the race itself says (fade in the final, ground lost, start) and what the
// horse's own trainings on this iPad say, combined into an honest counterfactual. Pure functions (unit tested).
// Training speeds are lower than race speeds, so the comparison uses RATIOS (speed kept at the end relative to the
// horse's own peak), never absolute speeds.

// MARK: - trainings

/// One fast work of a training: filtered speed above 40 km/h without a gap, over at least 200 m.
struct TrainingFastWork: Equatable {
    var sessionId: String
    var date: Date?
    var t0: Double
    var t1: Double
    var distanceM: Double
    /// Best 200 m (time-weighted mean of the filtered speed) inside the work, km/h.
    var peak200Kmh: Double
    /// Mean speed of the last 200 m of the work, km/h (only for works of at least 400 m).
    var last200Kmh: Double?
    /// last200 / peak200 (only for works of at least 400 m).
    var fade: Double?
}

/// What one training says about speed (sliding windows over the timeline distance with the filtered speed).
struct TrainingWorkSummary: Equatable {
    var sessionId: String
    var date: Date?
    var isDemo: Bool
    var best200Kmh: Double?
    var best400Kmh: Double?
    var best600Kmh: Double?
    var works: [TrainingFastWork]
}

enum TrainingWorkAnalyzer {
    static let fastKmh: Double = 40
    static let minWorkM: Double = 200
    static let fadeMinWorkM: Double = 400

    /// - Parameters: timeline arrays (t s, distance m, filtered speed m/s, break before each sample).
    static func analyze(sessionId: String, date: Date?, isDemo: Bool, t: [Double], distance: [Double], speedMs: [Double],
                        breaks: [Bool]) -> TrainingWorkSummary {
        let n: Int = min(t.count, distance.count, speedMs.count)
        var out = TrainingWorkSummary(sessionId: sessionId, date: date, isDemo: isDemo, best200Kmh: nil, best400Kmh: nil,
                                      best600Kmh: nil, works: [])
        if n < 2 { return out }
        let runs: [(Int, Int)] = continuousRuns(t: t, distance: distance, speed: speedMs, breaks: breaks, n: n)
        let integral: [Double] = speedIntegral(t: t, speed: speedMs, n: n)
        var b2: Double? = nil, b4: Double? = nil, b6: Double? = nil
        for (a, b) in runs {
            b2 = maxOpt(b2, bestWindowKmh(t, distance, integral, a, b, 200))
            b4 = maxOpt(b4, bestWindowKmh(t, distance, integral, a, b, 400))
            b6 = maxOpt(b6, bestWindowKmh(t, distance, integral, a, b, 600))
            // fast works inside the run
            let fast: Double = fastKmh / 3.6
            var i: Int = a
            while i <= b {
                if !(speedMs[i] > fast) { i += 1; continue }
                var j: Int = i
                while j + 1 <= b && speedMs[j + 1] > fast { j += 1 }
                let d: Double = distance[j] - distance[i]
                if d >= minWorkM, let peak = bestWindowKmh(t, distance, integral, i, j, 200) {
                    var last: Double? = nil
                    var fade: Double? = nil
                    if d >= fadeMinWorkM {
                        var k: Int = j
                        while k > i && distance[j] - distance[k] < 200 { k -= 1 }
                        if t[j] > t[k] {
                            let v: Double = (integral[j] - integral[k]) / (t[j] - t[k]) * 3.6
                            last = v
                            if peak > 0 { fade = min(1, v / peak) }
                        }
                    }
                    out.works.append(TrainingFastWork(sessionId: sessionId, date: date, t0: t[i], t1: t[j], distanceM: d,
                                                      peak200Kmh: peak, last200Kmh: last, fade: fade))
                }
                i = j + 1
            }
        }
        out.best200Kmh = b2
        out.best400Kmh = b4
        out.best600Kmh = b6
        return out
    }

    private static func maxOpt(_ a: Double?, _ b: Double?) -> Double? {
        guard let y = b else { return a }
        guard let x = a else { return y }
        return max(x, y)
    }

    /// Index ranges without gaps and with finite values.
    static func continuousRuns(t: [Double], distance: [Double], speed: [Double], breaks: [Bool], n: Int) -> [(Int, Int)] {
        var runs: [(Int, Int)] = []
        var start: Int = -1
        for i in 0..<n {
            let ok: Bool = t[i].isFinite && distance[i].isFinite && speed[i].isFinite
            let brk: Bool = i < breaks.count ? breaks[i] : false
            if !ok {
                if start >= 0 && i - 1 > start { runs.append((start, i - 1)) }
                start = -1
                continue
            }
            if start < 0 { start = i; continue }
            if brk || t[i] <= t[i - 1] {
                if i - 1 > start { runs.append((start, i - 1)) }
                start = i
            }
        }
        if start >= 0 && n - 1 > start { runs.append((start, n - 1)) }
        return runs
    }

    /// Cumulative ∫ v dt (trapezoids); steps with a non-finite value add nothing (they are outside the runs anyway).
    static func speedIntegral(t: [Double], speed: [Double], n: Int) -> [Double] {
        var out: [Double] = [Double](repeating: 0, count: n)
        if n < 2 { return out }
        for i in 1..<n {
            let dt: Double = t[i] - t[i - 1]
            let v: Double = (speed[i] + speed[i - 1]) / 2
            out[i] = out[i - 1] + (dt.isFinite && dt > 0 && v.isFinite ? v * dt : 0)
        }
        return out
    }

    /// Best time-weighted mean filtered speed over `lengthM` of timeline distance inside [a, b] (km/h).
    static func bestWindowKmh(_ t: [Double], _ distance: [Double], _ integral: [Double], _ a: Int, _ b: Int, _ lengthM: Double) -> Double? {
        if b <= a || distance[b] - distance[a] < lengthM { return nil }
        var best: Double? = nil
        var j: Int = a
        for i in a...b {
            if j < i { j = i }
            while j < b && distance[j] - distance[i] < lengthM { j += 1 }
            if distance[j] - distance[i] < lengthM { break }
            let dt: Double = t[j] - t[i]
            if dt <= 0 { continue }
            let v: Double = (integral[j] - integral[i]) / dt * 3.6
            if best == nil || v > best! { best = v }
        }
        return best
    }
}

// MARK: - report

enum RaceConfidence: String {
    case high = "Alta"
    case medium = "Media"
    case low = "Baja"
}

/// Everything the race card shows under «Análisis según los entrenamientos».
struct RaceReport {
    // race alone
    var ourFade: Double?
    var ourBestSpeedKmh: Double?
    var ourLastSpeedKmh: Double?
    var fieldMedianFade: Double?
    /// Final loss against the field-median fade (s, ≥ 0).
    var finalLossFieldS: Double?
    /// Final loss against the fade of its trainings (s, ≥ 0), when there are works with a fade.
    var finalLossTrainingS: Double?
    var groundLossS: Double?
    var startLossS: Double?
    var fieldMedianFirstS: Double?

    // trainings
    var trainingSessions: Int = 0
    var trainingFrom: Date?
    var trainingTo: Date?
    var trainingDemo: Bool = false
    var fastWorks: Int = 0
    var worksWithFade: Int = 0
    var best200Kmh: Double?
    var best400Kmh: Double?
    var best600Kmh: Double?
    var trainingFade: Double?
    /// best600 / best200 in training.
    var trainingSustain: Double?
    /// mean speed of the last 600 m / best sector speed in the race.
    var raceSustain: Double?
    /// recent (last 3 works) / earlier works, peak 200 m.
    var trendRatio: Double?
    var trendText: String = ""

    // counterfactual
    var referenceIsTraining: Bool = false
    var correctedTimeS: Double?
    var predictedPlace: Int?
    var placeLow: Int?
    var placeHigh: Int?
    var gainedPositions: Int = 0
    var verdict: String = ""
    var optimizedPositions: Int = 0
    var optimizedText: String = ""
    var confidence: RaceConfidence = .low
    var confidenceReason: String = ""
    var observations: [String] = []
    var method: [String] = []
}

enum RaceAnalysis {
    static let fadeLabel: String = "velocidad del último tramo / mejor tramo anterior"

    // ------------------------------------------------------------------ helpers on one runner
    static func speeds(_ r: RaceRunner) -> [Double?] { r.sectors.map { $0.speedKmh } }

    /// last-sector speed / best speed of the previous sectors.
    static func fade(_ r: RaceRunner) -> Double? {
        let v: [Double?] = speeds(r)
        guard v.count >= 2, let last = v[v.count - 1] else { return nil }
        let prev: [Double] = v.dropLast().compactMap { $0 }
        guard let best = prev.max(), best > 0 else { return nil }
        return last / best
    }

    static func bestPreviousSpeed(_ r: RaceRunner) -> Double? {
        let prev: [Double] = speeds(r).dropLast().compactMap { $0 }
        return prev.max()
    }

    /// Seconds lost in the last sector compared with fading only to `reference` (same distance, speed × ratio).
    static func finalLoss(_ r: RaceRunner, reference: Double?) -> Double? {
        guard let ref = reference, ref > 0, let f = fade(r), let last = r.sectors.last else { return nil }
        if f >= ref { return 0 }
        let hypothetical: Double = last.sectorS * f / ref
        return max(0, last.sectorS - hypothetical)
    }

    /// Seconds of the extra ground (metres more than the winner at the final mean speed).
    static func groundLoss(_ r: RaceRunner) -> Double? {
        guard let d = r.distanceVsWinnerM else { return r.finish == 1 ? 0 : nil }
        if d <= 0 { return 0 }
        guard let v = r.sectors.last?.speedKmh, v > 0 else { return nil }
        return d / (v / 3.6)
    }

    static func median(_ v: [Double]) -> Double? {
        let m: Double = Stats.median(v)
        return m.isFinite ? m : nil
    }

    /// 1 + runners (other than `except`) with an official time smaller than `time`.
    static func place(of time: Double, among race: Race, except: Int) -> Int {
        var p: Int = 1
        for (i, r) in race.runners.enumerated() where i != except {
            if let o = r.officialTimeS, o < time - 0.005 { p += 1 }
        }
        return p
    }

    /// "entre 600 y 400 m", "entre 200 m y la meta", "en la salida (DEP–1200 m)".
    static func between(_ race: Race, _ k: Int) -> String {
        let s: RaceSector = race.runners[0].sectors[k]
        let fromRem: Double = race.distanceM - s.fromM
        let toRem: Double = race.distanceM - s.toM
        if k == 0 { return "en el primer tramo (salida – \(Int(toRem)) m)" }
        if toRem <= 0 { return "entre \(Int(fromRem)) m y la meta" }
        return "entre \(Int(fromRem)) y \(Int(toRem)) m"
    }

    // ------------------------------------------------------------------ the report
    static func analyze(race: Race, ourIndex: Int, trainings: [TrainingWorkSummary]) -> RaceReport {
        var rep = RaceReport()
        guard ourIndex >= 0 && ourIndex < race.runners.count else { return rep }
        let us: RaceRunner = race.runners[ourIndex]
        let others: [RaceRunner] = race.runners.enumerated().filter { $0.offset != ourIndex }.map { $0.element }
        let n: Int = us.sectors.count

        // ---------------- a) race alone
        rep.ourFade = fade(us)
        rep.ourBestSpeedKmh = bestPreviousSpeed(us)
        rep.ourLastSpeedKmh = us.sectors.last?.speedKmh
        rep.fieldMedianFade = median(others.compactMap { fade($0) })
        rep.finalLossFieldS = finalLoss(us, reference: rep.fieldMedianFade)
        rep.groundLossS = groundLoss(us)
        if n > 0 {
            rep.fieldMedianFirstS = median(others.compactMap { $0.sectors.first?.sectorS })
            if let m = rep.fieldMedianFirstS, let mine = us.sectors.first?.sectorS { rep.startLossS = mine - m }
        }

        // ---------------- b) trainings
        rep.trainingSessions = trainings.count
        let dates: [Date] = trainings.compactMap { $0.date }
        rep.trainingFrom = dates.min()
        rep.trainingTo = dates.max()
        rep.trainingDemo = trainings.contains { $0.isDemo }
        let works: [TrainingFastWork] = trainings.flatMap { $0.works }.sorted { (a: TrainingFastWork, b: TrainingFastWork) -> Bool in
            let da: Double = a.date?.timeIntervalSince1970 ?? 0
            let db: Double = b.date?.timeIntervalSince1970 ?? 0
            return da != db ? da < db : a.t0 < b.t0
        }
        rep.fastWorks = works.count
        let fades: [Double] = works.compactMap { $0.fade }
        rep.worksWithFade = fades.count
        rep.trainingFade = median(fades)
        rep.best200Kmh = trainings.compactMap { $0.best200Kmh }.max()
        rep.best400Kmh = trainings.compactMap { $0.best400Kmh }.max()
        rep.best600Kmh = trainings.compactMap { $0.best600Kmh }.max()
        if let b2 = rep.best200Kmh, let b6 = rep.best600Kmh, b2 > 0 { rep.trainingSustain = b6 / b2 }
        if let l6 = us.last600S, l6 > 0, let best = us.sectors.compactMap({ $0.speedKmh }).max(), best > 0 {
            rep.raceSustain = (600 / l6 * 3.6) / best
        }
        if works.count >= 4 {
            let recent: [Double] = works.suffix(3).map { $0.peak200Kmh }
            let earlier: [Double] = works.dropLast(3).map { $0.peak200Kmh }
            let mr: Double = recent.reduce(0, +) / Double(recent.count)
            let me: Double = earlier.reduce(0, +) / Double(earlier.count)
            if me > 0 {
                let r: Double = mr / me
                rep.trendRatio = r
                let pct: String = AvoFormat.f(abs(r - 1) * 100, 1) + " %"
                if r > 1.015 { rep.trendText = "En mejora: sus 3 últimos trabajos rápidos son un \(pct) más rápidos (mejor 200 m) que los anteriores." }
                else if r < 0.985 { rep.trendText = "A la baja: sus 3 últimos trabajos rápidos son un \(pct) más lentos (mejor 200 m) que los anteriores." }
                else { rep.trendText = "Estable: sus 3 últimos trabajos rápidos están a ±1,5 % de los anteriores (mejor 200 m)." }
            }
        } else if works.count > 0 {
            rep.trendText = "Tendencia no calculada: hacen falta al menos 4 trabajos rápidos (hay \(works.count))."
        }
        if let tf = rep.trainingFade { rep.finalLossTrainingS = finalLoss(us, reference: tf) }

        // ---------------- c) counterfactual
        let useTraining: Bool = rep.trainingFade != nil && rep.ourFade != nil && (rep.trainingFade ?? 0) > (rep.ourFade ?? 1)
        rep.referenceIsTraining = useTraining
        let finalLossUsed: Double = (useTraining ? rep.finalLossTrainingS : rep.finalLossFieldS) ?? 0
        let ground: Double = rep.groundLossS ?? 0
        if let official = us.officialTimeS {
            let corrected: Double = official - finalLossUsed - ground
            rep.correctedTimeS = corrected
            let band: Double = max(0.1, 0.25 * (finalLossUsed + ground))
            let p: Int = place(of: corrected, among: race, except: ourIndex)
            rep.predictedPlace = p
            rep.placeLow = place(of: corrected - band, among: race, except: ourIndex)
            rep.placeHigh = place(of: corrected + band, among: race, except: ourIndex)
            let finish: Int = us.finish ?? place(of: official, among: race, except: ourIndex)
            let what: String = useTraining ? "Con un final como en sus entrenamientos" : "Con un final como la mediana del campo"
            if finish == 1 {
                rep.verdict = "Ganó la carrera: no hay puestos que recuperar."
                if let second = others.compactMap({ $0.officialTimeS }).min() {
                    rep.verdict += " Margen sobre el 2.º: \(RaceFormat.seconds(second - official)) (\(RaceFormat.lengths(second - official)))."
                }
            } else if p < finish {
                rep.gainedPositions = finish - p
                let range: String = (rep.placeLow ?? p) != (rep.placeHigh ?? p)
                    ? " (entre \(rep.placeLow ?? p).º y \(rep.placeHigh ?? p).º con ±\(AvoFormat.f(band, 2)) s)" : ""
                rep.verdict = "\(what) y sin el terreno de más, habría terminado \(p).º\(range): habría ganado \(RaceFormat.positions(finish - p))."
            } else {
                let ahead: [Double] = race.runners.enumerated().filter { $0.offset != ourIndex && ($0.element.finish ?? 99) == finish - 1 }
                    .compactMap { $0.element.officialTimeS }
                let target: Double? = ahead.first ?? others.compactMap { $0.officialTimeS }.filter { $0 < official }.max()
                if let tgt = target {
                    rep.verdict = "No habría cambiado el puesto: con la corrección le faltaron \(RaceFormat.seconds(corrected - tgt)) para el \(finish - 1).º "
                        + "(\(RaceFormat.seconds(official - tgt)) de diferencia real, \(RaceFormat.lengths(official - tgt)))."
                } else {
                    rep.verdict = "No habría cambiado el puesto."
                }
            }
            // reverse: positions we did better than predicted
            var optimized: Int = 0
            var reasons: [String] = []
            if let k400 = us.sectors.firstIndex(where: { abs((race.distanceM - $0.toM) - 400) < 0.5 }), let p400 = us.sectors[k400].position,
               p400 > finish {
                optimized = max(optimized, p400 - finish)
                reasons.append("ganó \(RaceFormat.positions(p400 - finish)) en los últimos 400 m (\(p400).º a 400 m → \(finish).º en la meta)")
            }
            if let tf = rep.trainingFade, let f = rep.ourFade, f > tf, let last = us.sectors.last {
                let expected: Double = official + (last.sectorS * f / tf - last.sectorS)
                let pe: Int = place(of: expected, among: race, except: ourIndex)
                if pe > finish {
                    optimized = max(optimized, pe - finish)
                    reasons.append("en carrera cayó menos (\(RaceFormat.percent(1 - f))) que en sus entrenamientos (\(RaceFormat.percent(1 - tf))); con su caída habitual habría sido \(pe).º")
                } else {
                    reasons.append("en carrera cayó menos (\(RaceFormat.percent(1 - f))) que en sus entrenamientos (\(RaceFormat.percent(1 - tf))), sin cambio de puesto")
                }
            }
            rep.optimizedPositions = optimized
            if optimized > 0 {
                rep.optimizedText = "Hemos optimizado \(RaceFormat.positions(optimized)): " + reasons.joined(separator: "; ") + "."
            } else if !reasons.isEmpty {
                rep.optimizedText = "Aspecto positivo: " + reasons.joined(separator: "; ") + "."
            }
        } else {
            rep.verdict = "Sin tiempo oficial del caballo: no se puede estimar."
        }

        // ---------------- confidence
        let complete: Bool = us.sectors.allSatisfy { $0.speedKmh != nil && $0.strides != nil }
            && (us.distanceVsWinnerM != nil || us.finish == 1) && race.runners.count >= 4
        var level: Int = rep.worksWithFade >= 5 ? 2 : (rep.fastWorks >= 2 ? 1 : 0)
        var why: [String] = []
        if trainings.isEmpty {
            why.append("sin entrenamientos anteriores a la carrera en el iPad: solo datos de la carrera")
        } else {
            why.append("\(rep.fastWorks) trabajo(s) rápido(s) (> 40 km/h, ≥ 200 m), \(rep.worksWithFade) con caída medible (≥ 400 m)")
        }
        if !complete {
            level = max(0, level - 1)
            why.append("datos de la carrera incompletos (velocidades, foulées o distancia recorrida)")
        }
        if rep.trainingDemo { level = 0; why.append("incluye entrenamientos de DEMOSTRACIÓN (datos sintéticos)") }
        rep.confidence = level == 2 ? .high : (level == 1 ? .medium : .low)
        rep.confidenceReason = why.joined(separator: "; ")

        rep.observations = observations(race: race, ourIndex: ourIndex, report: rep)
        rep.method = [
            "Caída en el final = \(fadeLabel) (velocidades medias del PDF por tramo). La mediana del campo se calcula con los demás caballos.",
            "Tiempo perdido en el final = tiempo del último tramo − tiempo que habría hecho con la caída de referencia (misma distancia, velocidad × caída de referencia / caída propia). Solo se cuenta si cayó más que la referencia.",
            "Tiempo perdido por terreno = «Parcouru vs. 1er» (metros de más que el ganador) / velocidad media de su último tramo. Solo si es positivo.",
            "Referencia del final: la caída de sus trabajos rápidos de entrenamiento (> 40 km/h, ≥ 400 m: últimos 200 m / mejor 200 m del trabajo) si es mejor que la de la carrera; si no, la mediana del campo.",
            "Los entrenamientos son más lentos que la carrera: se comparan proporciones (caída, velocidad sostenida respecto a su propia punta), nunca velocidades absolutas.",
            "Puesto estimado = tiempo oficial corregido comparado con los tiempos oficiales de los demás. El margen ± es el 25 % de la corrección (mínimo 0,1 s).",
            "Posiciones por tramo = orden de los tiempos acumulados de todos los caballos al final de cada tramo. 1 cuerpo ≈ 0,2 s.",
            "Confianza: Alta con ≥ 5 trabajos con caída medible y datos completos; Media con ≥ 2 trabajos rápidos; Baja en otro caso o con datos de demostración.",
        ]
        return rep
    }

    // ------------------------------------------------------------------ observations
    static func observations(race: Race, ourIndex: Int, report rep: RaceReport) -> [String] {
        var out: [String] = []
        let us: RaceRunner = race.runners[ourIndex]
        let n: Int = us.sectors.count
        // positions lost / gained between marks
        if n >= 2 {
            for k in 1..<n {
                guard let a = us.sectors[k - 1].position, let b = us.sectors[k].position, a != b else { continue }
                let d: Int = abs(b - a)
                let word: String = d == 1 ? "puesto" : "puestos"
                out.append((b > a ? "Perdió" : "Ganó") + " \(d) \(word) \(between(race, k)) (\(a).º → \(b).º).")
            }
        }
        // last sector speed in the field
        if let mine = us.sectors.last?.speedKmh {
            let all: [Double] = race.runners.compactMap { $0.sectors.last?.speedKmh }.sorted(by: >)
            let rank: Int = 1 + all.filter { $0 > mine + 0.0001 }.count
            let label: String = us.sectors.last.map { $0.label } ?? ""
            var s: String = "Último tramo (\(label)) a \(RaceFormat.kmh(mine)), "
            if rank == all.count && all.count > 1 { s += "el más lento del campo." }
            else if rank == 1 { s += "el más rápido del campo." }
            else { s += "el \(rank).º más rápido de \(all.count)." }
            out.append(s)
        }
        if let f = rep.ourFade, let best = rep.ourBestSpeedKmh, let last = rep.ourLastSpeedKmh {
            var s: String = "Caída en el final: \(RaceFormat.kmh(best)) → \(RaceFormat.kmh(last)) (conserva el \(RaceFormat.percent(f)))"
            if let m = rep.fieldMedianFade { s += " frente al \(RaceFormat.percent(m)) de la mediana del campo" }
            s += "."
            if let l = rep.finalLossFieldS, l > 0.005 { s += " Coste: \(RaceFormat.seconds(l)) respecto a la mediana." }
            out.append(s)
        }
        // stride at the end vs the winner, and its own stride change
        if let mine = us.sectors.last?.strideLengthM {
            if let w = race.winner, w.name != us.name, let ws = w.sectors.last?.strideLengthM {
                let cmp: String = mine < ws - 0.005 ? "más corta" : (mine > ws + 0.005 ? "más larga" : "igual")
                out.append("Zancada al final \(cmp): \(RaceFormat.metres(mine)) frente a \(RaceFormat.metres(ws)) del ganador.")
            }
            if n >= 3 {
                let mid: [Double] = us.sectors.dropFirst().dropLast().compactMap { $0.strideLengthM }
                if let best = mid.max(), best > 0, mine < best * 0.97 {
                    out.append("Su zancada se acortó al final: \(RaceFormat.metres(mine)) frente a \(RaceFormat.metres(best)) en su mejor tramo.")
                }
            }
        }
        if let sl = rep.startLossS, let m = rep.fieldMedianFirstS, let mine = us.sectors.first?.sectorS {
            if abs(sl) >= 0.05 {
                out.append("Salida: \(RaceFormat.seconds(mine)) en el primer tramo, \(RaceFormat.signedSeconds(sl)) respecto a la mediana del campo (\(RaceFormat.seconds(m))).")
            }
        }
        if let d = us.distanceVsWinnerM {
            if d > 0 {
                out.append("Recorrió \(RaceFormat.metres(d)) más que el ganador (≈ \(RaceFormat.seconds(rep.groundLossS)) a su velocidad final).")
            } else if d < 0 {
                out.append("Recorrió \(RaceFormat.metres(-d)) menos que el ganador: no perdió terreno.")
            }
        }
        if let v = us.maxSpeedKmh {
            out.append("Velocidad máxima \(RaceFormat.kmh(v, 2))" + (us.maxSpeedSector.isEmpty ? "." : " en el tramo \(us.maxSpeedSector)."))
        }
        if let ts = rep.trainingSustain, let rs = rep.raceSustain {
            out.append("En entrenamiento sostiene en 600 m el \(RaceFormat.percent(ts)) de su mejor 200 m; en la carrera, los últimos 600 m fueron al \(RaceFormat.percent(rs)) de su mejor tramo.")
        }
        if let tf = rep.trainingFade, let f = rep.ourFade {
            out.append("Caída en sus trabajos rápidos (mediana de \(rep.worksWithFade)): conserva el \(RaceFormat.percent(tf)); en la carrera, el \(RaceFormat.percent(f)).")
        }
        return out
    }
}
