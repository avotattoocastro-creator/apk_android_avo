import Foundation

// Automatic analysis of a race video (trainer's request 09/11/2026: «Fase 2 en automático»), for races without the
// «Statistiques Tracking» PDF. App/RaceVideoModel.swift follows our jockey frame by frame (Vision) and measures the camera
// movement; this file turns those measurements into a speed profile, 200 m sectors, stride frequency and position, and
// builds a `Race` like the ones read from the tracking PDF, so the race card and the comparison with the trainings work
// the same way.
//
// How the speed is obtained (all values are ESTIMATES and are labelled as such):
//  • ground position of the jockey in the image = jockey position − camera pan (image registration between frames);
//  • relative speed = that displacement per second divided by the height of the jockey box (zoom-invariant: when the
//    camera zooms, both grow together) → «jockey heights per second»;
//  • absolute scale: the integral of the relative speed between the start and the finish must equal the official
//    distance, run in the official time of our horse (France Galop). One scale factor for the whole race.
//  • gaps (camera cuts, head-on views, jockey lost) are filled by interpolation and lower the coverage / confidence.
//  • stride frequency = vertical bounce of the jockey (autocorrelation, 1,6–3,2 Hz); strides = frequency × time.
//  • position = 1 + jockeys detected ahead of ours in the same frame (only side views with several jockeys).

/// One analysed frame.
struct RaceVideoSample: Codable, Equatable {
    /// Video time (s).
    var t: Double
    /// Scene cut (camera change) just before this frame.
    var cut: Bool
    /// Cumulative camera translation since the start of the video (px, image coordinates).
    var camX: Double
    var camY: Double
    /// Our jockey (px, top-left origin); nil = not found in this frame.
    var x: Double?
    var y: Double?
    var h: Double?
    /// Centres (px, image X) of the other jockeys detected in this frame (empty when detection did not run).
    var others: [Double]
    /// Width of the frame (px).
    var frameW: Double
}

/// Result shown on the page and saved with the race.
struct RaceVideoResult: Equatable {
    struct Point: Equatable, Identifiable {
        var t: Double          // since the start (s)
        var m: Double          // distance since the start (m)
        var kmh: Double
        var measured: Bool     // false = interpolated
        var id: Double { t }
    }
    var points: [Point] = []
    var sectors: [RaceSector] = []
    var startT: Double = 0
    var timeS: Double = 0
    var distanceM: Double = 0
    var maxKmh: Double? = nil
    var maxAtM: Double? = nil
    var strideHz: Double? = nil
    /// Share of the race time with a direct measurement (0…1).
    var coverage: Double = 0
    /// Share of the race time with a stride-frequency measurement (0…1).
    var strideCoverage: Double = 0
    /// Metres per «jockey height» found by the calibration (plausible 0,6–2,5).
    var scaleM: Double = 0
    /// 0…1, from the coverage and the plausibility of the scale.
    var confidence: Double = 0
    var warnings: [String] = []

    var confidenceText: String {
        confidence >= 0.7 ? "alta" : (confidence >= 0.45 ? "media" : "baja")
    }
}

enum RaceVideoAnalysis {
    static let gridHz: Double = 10

    // ------------------------------------------------------------------ public
    /// Automatic start: first moment from which our jockey keeps moving for 2 s (relative speed above 35 % of the
    /// typical race speed). Falls back to the first sample.
    static func autoStart(_ samples: [RaceVideoSample]) -> Double {
        let rel: [(t: Double, r: Double)] = relativeSpeeds(samples, sign: bestSign(samples))
        guard !rel.isEmpty else { return samples.first?.t ?? 0 }
        let sorted: [Double] = rel.map { $0.r }.sorted()
        let typical: Double = sorted[min(sorted.count - 1, sorted.count * 3 / 4)]
        if typical <= 0 { return rel[0].t }
        let thr: Double = typical * 0.35
        var i: Int = 0
        while i < rel.count {
            if rel[i].r >= thr {
                var j: Int = i
                var ok: Bool = true
                while j < rel.count && rel[j].t < rel[i].t + 2 {
                    if rel[j].r < thr * 0.6 { ok = false; break }
                    j += 1
                }
                if ok { return max(rel[i].t - 0.3, samples.first?.t ?? 0) }
            }
            i += 1
        }
        return rel[0].t
    }

    /// Profile, sectors and stride frequency between `start` and `start + timeS` (official time of our horse).
    static func analyze(_ samples: [RaceVideoSample], start: Double, timeS: Double, distanceM: Double) -> RaceVideoResult {
        var res = RaceVideoResult()
        res.startT = start
        res.timeS = timeS
        res.distanceM = distanceM
        guard timeS > 5, distanceM > 100, samples.count > 10 else {
            res.warnings.append("Faltan datos: distancia, tiempo oficial o vídeo analizado.")
            return res
        }
        let end: Double = start + timeS
        if let last = samples.last?.t, last < end - 1 {
            res.warnings.append("El vídeo termina \(fmt(end - last, 1)) s antes de la llegada: el final se ha completado por interpolación.")
        }
        // 1) relative speed (jockey heights / s) on a 10 Hz grid between start and finish
        let sign: Double = bestSign(samples)
        let rel: [(t: Double, r: Double)] = relativeSpeeds(samples, sign: sign).filter { $0.t >= start - 1 && $0.t <= end + 1 }
        let n: Int = Int((timeS * gridHz).rounded(.up)) + 1
        var grid: [Double] = Array(repeating: .nan, count: n)
        var measured: [Bool] = Array(repeating: false, count: n)
        for k in 0..<n {
            let t: Double = start + Double(k) / gridHz
            if let v = sampleAt(rel, t, maxGap: 0.35) { grid[k] = v; measured[k] = true }
        }
        let measuredCount: Int = measured.filter { $0 }.count
        res.coverage = Double(measuredCount) / Double(n)
        if measuredCount < 5 {
            res.warnings.append("No se pudo seguir al caballo durante la carrera (cobertura \(fmt(res.coverage * 100, 0)) %).")
            return res
        }
        // start: the horses leave the stalls standing; the first and last known values cover the edges
        fillGaps(&grid, startValue: grid.first(where: { $0.isFinite }) ?? 0)
        // 2) calibration: Σ r·dt = distance
        var integral: Double = 0
        for k in 0..<(n - 1) { integral += (grid[k] + grid[k + 1]) / 2 / gridHz }
        if integral <= 0 {
            res.warnings.append("Movimiento medido nulo: revisa la salida en el vídeo.")
            return res
        }
        let scale: Double = distanceM / integral
        res.scaleM = scale
        // 3) points (km/h, smoothed 1 s) and distance
        let smooth: [Double] = movingAverage(grid, Int(gridHz))
        var dist: Double = 0
        var pts: [RaceVideoResult.Point] = []
        for k in 0..<n {
            if k > 0 { dist += (grid[k - 1] + grid[k]) / 2 / gridHz * scale }
            pts.append(RaceVideoResult.Point(t: Double(k) / gridHz, m: min(dist, distanceM), kmh: smooth[k] * scale * 3.6,
                                             measured: measured[k]))
        }
        res.points = pts
        if let mx = pts.filter({ $0.measured && $0.t > 3 }).max(by: { $0.kmh < $1.kmh }) {
            res.maxKmh = mx.kmh
            res.maxAtM = mx.m
        }
        // 4) stride frequency (bounce of the jockey)
        let stride: [(t: Double, hz: Double)] = strideFrequency(samples, sign: sign, from: start, to: end)
        res.strideCoverage = min(1, Double(stride.count) * 1.0 / max(timeS, 1))
        if !stride.isEmpty {
            let hz: [Double] = stride.map { $0.hz }.sorted()
            res.strideHz = hz[hz.count / 2]
        }
        // 5) sectors (200 m from the finish, the first one is the rest: «DEP - 1200m» … «200m - ARR»)
        res.sectors = sectors(pts, distanceM: distanceM, timeS: timeS, stride: stride, start: start,
                              positions: positions(samples, sign: sign, from: start, to: end))
        // 6) confidence
        let plausible: Bool = scale >= 0.5 && scale <= 3.0
        if !plausible { res.warnings.append("Escala poco plausible (\(fmt(scale, 2)) m por altura de jinete): revisa la salida y el tiempo.") }
        if res.coverage < 0.5 { res.warnings.append("Solo se midió el \(fmt(res.coverage * 100, 0)) % de la carrera (cortes de cámara o vistas de frente).") }
        res.confidence = max(0, min(1, res.coverage * (plausible ? 1 : 0.5)))
        return res
    }

    /// `Race` like the ones of the tracking PDF: our horse first (with sectors), the other runners of the page after.
    static func makeRace(_ r: RaceVideoResult, info: RaceVideoInfo, others: [RaceRunner]) -> Race {
        var us = RaceRunner(number: info.number, draw: nil, name: info.runnerName, jockey: "", finish: info.place,
                            officialTimeS: r.timeS, maxSpeedKmh: r.maxKmh.map { round1($0) },
                            maxSpeedSector: sectorLabel(r.sectors, atM: r.maxAtM), fastest200S: nil, fastestSector: "",
                            last600S: nil, distanceVsWinnerM: nil, meanSpeedKmh: round1(r.distanceM / r.timeS * 3.6),
                            redk: r.timeS / r.distanceM * 1000, sectors: r.sectors)
        let full: [RaceSector] = r.sectors.filter { abs($0.lengthM - 200) < 1 }
        if let best = full.min(by: { $0.sectorS < $1.sectorS }) {
            us.fastest200S = round2(best.sectorS)
            us.fastestSector = best.label
        }
        if let b = r.sectors.first(where: { abs((r.distanceM - $0.toM) - 600) < 1 }) {
            us.last600S = round2(r.timeS - b.cumulativeS)
        }
        var runners: [RaceRunner] = [us]
        for o in others where RaceNames.normalized(o.name) != RaceNames.normalized(info.runnerName) { runners.append(o) }
        return Race(id: "video-" + String(Int(Date().timeIntervalSince1970)), hippodrome: info.hippodrome,
                    raceName: info.raceName, category: "", distanceM: r.distanceM, date: info.date,
                    winnerRedk: info.winnerTimeS.map { $0 / r.distanceM * 1000 }, sourceFile: "",
                    runners: runners, horseRecordCode: info.horseCode, horseName: info.horseName,
                    ourRunnerName: info.runnerName, importedAt: Date(),
                    notes: notes(r), isDemo: false)
    }

    static func notes(_ r: RaceVideoResult) -> String {
        var t: String = "Carrera analizada automáticamente desde el VÍDEO (sin tracker): velocidades, parciales, zancadas y posiciones ESTIMADAS. "
        t += "Confianza \(r.confidenceText) · medido el \(fmt(r.coverage * 100, 0)) % de la carrera"
        if let hz = r.strideHz { t += " · frecuencia de zancada \(fmt(hz, 2)) Hz" }
        t += ". Escala calibrada con la distancia y el tiempo oficiales."
        if !r.warnings.isEmpty { t += " Avisos: " + r.warnings.joined(separator: " ") }
        return t
    }

    // ------------------------------------------------------------------ steps
    /// Camera-pan sign: the one that gives the smoothest ground speed (Vision's registration convention is not assumed).
    static func bestSign(_ samples: [RaceVideoSample]) -> Double {
        let a: [(t: Double, r: Double)] = relativeSpeeds(samples, sign: 1)
        let b: [(t: Double, r: Double)] = relativeSpeeds(samples, sign: -1)
        return roughness(a) <= roughness(b) ? 1 : -1
    }

    private static func roughness(_ v: [(t: Double, r: Double)]) -> Double {
        if v.count < 3 { return .infinity }
        var s: Double = 0
        var mean: Double = 0
        for i in 1..<v.count { s += abs(v[i].r - v[i - 1].r) }
        for x in v { mean += abs(x.r) }
        mean /= Double(v.count)
        return s / Double(v.count - 1) / max(mean, 1e-6)
    }

    /// Ground speed of our jockey in «jockey heights per second», per continuous stretch of video (no cut, jockey found),
    /// local linear fit over ±0,4 s; signed along the main direction of the run.
    static func relativeSpeeds(_ samples: [RaceVideoSample], sign: Double) -> [(t: Double, r: Double)] {
        var out: [(t: Double, r: Double)] = []
        var seg: [(t: Double, x: Double, h: Double)] = []
        func flush() {
            if seg.count >= 4 {
                for i in 0..<seg.count {
                    var sx: Double = 0, sxx: Double = 0, sy: Double = 0, sxy: Double = 0, nn: Double = 0
                    var hs: [Double] = []
                    for j in 0..<seg.count where abs(seg[j].t - seg[i].t) <= 0.4 {
                        let dt: Double = seg[j].t - seg[i].t
                        sx += dt; sxx += dt * dt; sy += seg[j].x; sxy += dt * seg[j].x; nn += 1
                        hs.append(seg[j].h)
                    }
                    let den: Double = nn * sxx - sx * sx
                    if nn < 3 || den <= 1e-9 { continue }
                    let slope: Double = (nn * sxy - sx * sy) / den
                    hs.sort()
                    let h: Double = hs[hs.count / 2]
                    if h > 2 { out.append((t: seg[i].t, r: slope / h)) }
                }
            }
            seg = []
        }
        for s in samples {
            if s.cut { flush() }
            guard let x = s.x, let h = s.h else { flush(); continue }
            seg.append((t: s.t, x: x + sign * s.camX, h: h))
        }
        flush()
        // main direction: sign of the median → speeds positive forwards
        let sorted: [Double] = out.map { $0.r }.sorted()
        let dir: Double = sorted.isEmpty ? 1 : (sorted[sorted.count / 2] >= 0 ? 1 : -1)
        return out.map { (t: $0.t, r: max(0, $0.r * dir)) }
    }

    /// Value at time t when a measurement exists within `maxGap` seconds (linear between neighbours).
    private static func sampleAt(_ v: [(t: Double, r: Double)], _ t: Double, maxGap: Double) -> Double? {
        if v.isEmpty { return nil }
        var lo: Int = 0
        var hi: Int = v.count - 1
        if t < v[0].t - maxGap || t > v[hi].t + maxGap { return nil }
        while hi - lo > 1 {
            let mid: Int = (lo + hi) / 2
            if v[mid].t <= t { lo = mid } else { hi = mid }
        }
        let a = v[lo]
        let b = v[hi]
        if abs(a.t - t) <= maxGap && abs(b.t - t) <= maxGap && b.t > a.t {
            return a.r + (b.r - a.r) * (t - a.t) / (b.t - a.t)
        }
        if abs(a.t - t) <= maxGap { return a.r }
        if abs(b.t - t) <= maxGap { return b.r }
        return nil
    }

    private static func fillGaps(_ g: inout [Double], startValue: Double) {
        var lastK: Int = -1
        for k in 0..<g.count where g[k].isFinite {
            if lastK < 0 {
                for j in 0..<k { g[j] = startValue * Double(j) / Double(max(k, 1)) }
            } else if k - lastK > 1 {
                for j in (lastK + 1)..<k {
                    g[j] = g[lastK] + (g[k] - g[lastK]) * Double(j - lastK) / Double(k - lastK)
                }
            }
            lastK = k
        }
        if lastK >= 0 && lastK < g.count - 1 { for j in (lastK + 1)..<g.count { g[j] = g[lastK] } }
        for k in 0..<g.count where !g[k].isFinite { g[k] = 0 }
    }

    private static func movingAverage(_ v: [Double], _ w: Int) -> [Double] {
        if v.isEmpty || w <= 1 { return v }
        var out: [Double] = []
        let half: Int = w / 2
        for i in 0..<v.count {
            let a: Int = max(0, i - half)
            let b: Int = min(v.count - 1, i + half)
            var s: Double = 0
            for j in a...b { s += v[j] }
            out.append(s / Double(b - a + 1))
        }
        return out
    }

    /// Stride frequency every second from the vertical bounce of the jockey (heights), autocorrelation 1,6–3,2 Hz.
    static func strideFrequency(_ samples: [RaceVideoSample], sign: Double, from: Double, to: Double) -> [(t: Double, hz: Double)] {
        let fs: Double = 25
        var out: [(t: Double, hz: Double)] = []
        var seg: [(t: Double, y: Double)] = []
        func flush() {
            defer { seg = [] }
            guard seg.count >= 20, let t0 = seg.first?.t, let t1 = seg.last?.t, t1 - t0 >= 2 else { return }
            // uniform 25 Hz resampling
            var u: [Double] = []
            var j: Int = 0
            var t: Double = t0
            while t <= t1 {
                while j < seg.count - 2 && seg[j + 1].t < t { j += 1 }
                let a = seg[j], b = seg[j + 1]
                u.append(b.t > a.t ? a.y + (b.y - a.y) * (t - a.t) / (b.t - a.t) : a.y)
                t += 1 / fs
            }
            // high-pass: minus 0,6 s moving average
            let base: [Double] = movingAverage(u, Int(fs * 0.6))
            let hp: [Double] = zip(u, base).map { $0 - $1 }
            let win: Int = Int(fs * 2.5)
            let minLag: Int = Int(fs / 3.2)
            let maxLag: Int = Int(fs / 1.6) + 1
            var start: Int = 0
            while start + win + maxLag < hp.count {
                var e0: Double = 0
                for i in start..<(start + win) { e0 += hp[i] * hp[i] }
                if e0 > 1e-9 {
                    var ac: [Double] = []
                    for lag in (minLag - 1)...(maxLag + 1) {
                        var s: Double = 0
                        for i in start..<(start + win) { s += hp[i] * hp[i + lag] }
                        ac.append(s / e0)
                    }
                    var best: Int = 1
                    for k in 1..<(ac.count - 1) where ac[k] > ac[best] { best = k }
                    if best > 0 && best < ac.count - 1 && ac[best] > 0.3 && ac[best] >= ac[best - 1] && ac[best] >= ac[best + 1] {
                        // parabolic refinement of the peak
                        let den: Double = ac[best - 1] - 2 * ac[best] + ac[best + 1]
                        let off: Double = abs(den) > 1e-9 ? 0.5 * (ac[best - 1] - ac[best + 1]) / den : 0
                        let lag: Double = Double(best + minLag - 1) + off
                        let hz: Double = fs / lag
                        let tc: Double = t0 + (Double(start) + Double(win) / 2) / fs
                        if hz >= 1.6 && hz <= 3.2 && tc >= from && tc <= to { out.append((t: tc, hz: hz)) }
                    }
                }
                start += Int(fs)
            }
        }
        for s in samples where s.t >= from - 2 && s.t <= to + 2 {
            if s.cut { flush() }
            guard let y = s.y, let h = s.h, h > 2 else { flush(); continue }
            seg.append((t: s.t, y: (y + sign * s.camY) / h))
        }
        flush()
        return out
    }

    /// Estimated position (1 = leading) when several jockeys are seen side-on: 1 + jockeys ahead of ours.
    static func positions(_ samples: [RaceVideoSample], sign: Double, from: Double, to: Double) -> [(t: Double, p: Int)] {
        let rel: [(t: Double, r: Double)] = relativeSpeeds(samples, sign: sign)
        // image direction of the run: sign of the raw image ground displacement
        var dirSum: Double = 0
        var prev: RaceVideoSample? = nil
        for s in samples {
            if let p = prev, !s.cut, let x0 = p.x, let x1 = s.x { dirSum += (x1 + sign * s.camX) - (x0 + sign * p.camX) }
            prev = s
        }
        let dir: Double = dirSum >= 0 ? 1 : -1
        var out: [(t: Double, p: Int)] = []
        for s in samples where s.t >= from && s.t <= to && s.others.count >= 1 {
            guard let x = s.x, let h = s.h else { continue }
            // only while running side-on (measured speed available)
            guard let r = sampleAt(rel, s.t, maxGap: 0.3), r > 0.5 else { continue }
            let ahead: Int = s.others.filter { ($0 - x) * dir > h * 0.4 }.count
            out.append((t: s.t, p: 1 + ahead))
        }
        return out
    }

    private static func sectors(_ pts: [RaceVideoResult.Point], distanceM: Double, timeS: Double,
                                stride: [(t: Double, hz: Double)], start: Double,
                                positions: [(t: Double, p: Int)]) -> [RaceSector] {
        // remaining distances at the end of each sector: 1200, 1000, …, 200, 0
        var rem: [Double] = []
        var r: Double = (distanceM - 1).rounded(.down)
        r = (r / 200).rounded(.down) * 200
        while r > 0 { rem.append(r); r -= 200 }
        rem.append(0)
        func timeAt(_ m: Double) -> Double {
            if m >= distanceM - 0.01 { return timeS }
            for k in 1..<pts.count where pts[k].m >= m {
                let a = pts[k - 1], b = pts[k]
                return b.m > a.m ? a.t + (b.t - a.t) * (m - a.m) / (b.m - a.m) : b.t
            }
            return timeS
        }
        var out: [RaceSector] = []
        var fromM: Double = 0
        var fromT: Double = 0
        for (i, re) in rem.enumerated() {
            let toM: Double = distanceM - re
            let toT: Double = timeAt(toM)
            let a: String = i == 0 ? "DEP" : "\(Int(distanceM - fromM))m"
            let b: String = re <= 0 ? "ARR" : "\(Int(re))m"
            let dur: Double = max(toT - fromT, 0.01)
            // strides: mean frequency of the sector × duration, when half of the sector has a frequency
            let inSector: [Double] = stride.filter { $0.t - start >= fromT && $0.t - start <= toT }.map { $0.hz }
            var strides: Int? = nil
            if !inSector.isEmpty && Double(inSector.count) >= dur * 0.5 {
                let mean: Double = inSector.reduce(0, +) / Double(inSector.count)
                strides = Int((mean * dur).rounded())
            }
            // position at the end of the sector: median of the estimates of the last 1,5 s
            let ps: [Int] = positions.filter { $0.t - start >= toT - 1.5 && $0.t - start <= toT + 0.3 }.map { $0.p }.sorted()
            out.append(RaceSector(label: a + " - " + b, fromM: fromM, toM: toM, cumulativeS: round2(toT), sectorS: round2(dur),
                                  meanSpeedKmh: round1((toM - fromM) / dur * 3.6), strides: strides,
                                  position: ps.isEmpty ? nil : ps[ps.count / 2]))
            fromM = toM
            fromT = toT
        }
        return out
    }

    private static func sectorLabel(_ s: [RaceSector], atM m: Double?) -> String {
        guard let x = m else { return "" }
        return s.first(where: { x >= $0.fromM && x <= $0.toM })?.label ?? ""
    }

    static func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
    static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
    static func fmt(_ v: Double, _ d: Int) -> String { AvoFormat.f(v, d) }

    // ------------------------------------------------------------------ official data from the page text
    /// «1'36"57», «1'36''57», «1:36.57», «1'36\"5» → seconds.
    static func parseTime(_ s: String) -> Double? {
        let t: String = s.replacingOccurrences(of: "''", with: "\"").replacingOccurrences(of: "″", with: "\"")
            .replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "′", with: "'").trimmingCharacters(in: .whitespaces)
        let patterns: [String] = [#"(\d{1,2})\s*'\s*(\d{1,2})\s*"\s*(\d{1,2})"#, #"(\d{1,2}):(\d{2})[\.,](\d{1,2})"#]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p),
                  let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)), m.numberOfRanges == 4 else { continue }
            func g(_ i: Int) -> String { Range(m.range(at: i), in: t).map { String(t[$0]) } ?? "" }
            guard let mi = Double(g(1)), let se = Double(g(2)) else { continue }
            let fr: String = g(3)
            let frac: Double = (Double(fr) ?? 0) / (fr.count == 1 ? 10 : 100)
            return mi * 60 + se + frac
        }
        if let v = Double(t.replacingOccurrences(of: ",", with: ".")), v > 20, v < 600 { return v }
        return nil
    }

    /// First distance between 800 and 7000 m in the text («1 400 mètres», «2100m», «Distance : 1.600 m»).
    static func parseDistance(_ text: String) -> Double? {
        guard let re = try? NSRegularExpression(pattern: #"(\d[\d\s \.]{2,6}\d|\d{3,4})\s?(?:m\b|mètres|metres)"#) else { return nil }
        for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let r = Range(m.range(at: 1), in: text) else { continue }
            let digits: String = text[r].filter { $0.isNumber }
            if let v = Double(digits), v >= 800, v <= 7000 { return v }
        }
        return nil
    }
}

/// What the trainer confirms before saving (prefilled from the France Galop page).
struct RaceVideoInfo: Equatable {
    var raceName: String = ""
    var hippodrome: String = ""
    var date: Date? = nil
    var horseCode: String? = nil
    var horseName: String? = nil
    var runnerName: String = ""
    var number: Int? = nil
    var place: Int? = nil
    var winnerTimeS: Double? = nil
}
