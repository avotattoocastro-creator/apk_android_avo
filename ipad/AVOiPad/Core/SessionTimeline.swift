import Foundation

/// Time-aligned analysis series of one session, derived from the original telemetry without modifying it.
/// t = seconds since the first usable GNSS epoch (GPS time of week, week roll-over handled).
/// Three speeds are kept apart on purpose:
///   speedReported  — gSpeed reported by the receiver (Doppler based), m/s;
///   speedDerived   — central difference of consecutive positions, m/s (noisier, independent check);
///   speedFiltered  — Kalman + Rauch–Tung–Striebel smoother of speedReported (see `SpeedSmoother`).
/// Accelerations are derived quantities with their own uncertainty, never measured directly by GNSS.
final class SessionTimeline {
    static let defaultGapFactor: Double = 2.5

    var count: Int { t.count }
    private(set) var t: [Double] = []
    private(set) var lat: [Double] = []
    private(set) var lon: [Double] = []
    private(set) var speedReported: [Double] = []
    private(set) var speedDerived: [Double] = []
    private(set) var speedFiltered: [Double] = []
    private(set) var speedFilteredSigma: [Double] = []
    private(set) var accelLong: [Double] = []
    private(set) var accelLongSigma: [Double] = []
    private(set) var accelLateral: [Double] = []
    private(set) var distance: [Double] = []
    private(set) var altitudeMsl: [Double] = []
    private(set) var hAcc: [Double] = []
    private(set) var speedAcc: [Double] = []
    private(set) var numSv: [Int] = []
    private(set) var solution: [GnssSolution] = []
    /// True when the sample starts after a gap (no interpolation across it).
    private(set) var breakBefore: [Bool] = []
    /// True when the step from the previous point was rejected as a position jump (excluded from distance).
    private(set) var jumpBefore: [Bool] = []
    private(set) var nominalDtS: Double = 0
    var losses: [SignalLoss] = []
    private(set) var itow0Ms: Int64 = 0
    private(set) var utc0: Date?
    /// utc0 in 100 ns ticks since 1970 (C# DateTimeOffset precision, used for exported time stamps).
    private(set) var utc0Ticks: Int64?
    var totalDistanceM: Double { distance.isEmpty ? 0 : distance[distance.count - 1] }
    var durationS: Double { t.count > 1 ? t[t.count - 1] - t[0] : 0 }
    private(set) var filterParameters: SpeedSmoother.Parameters = SpeedSmoother.Parameters()
    /// Where speedFiltered / accelLong come from: "app" (own SpeedSmoother) or "motor" (AVO Performance Equine 2.0 series).
    private(set) var kinematicsSource: String = "app"

    init() {}

    /// AVO Performance Equine 2.0 (F1b): the engine is the single kinematic truth. Its smoothed speed and acceleration (with
    /// their σ) replace the app filter wherever the engine has a sample within 0.5 s on both sides (engine time =
    /// timeline time + offsetS); elsewhere the app values stay. Only adopted when the engine covers most of the timeline
    /// and the app filter uses the engine default (jerk density 1 m²/s⁵), so a user-tuned filter is never overridden.
    /// Same rule as Windows SessionTimeline.AdoptEngineKinematics and Android. Returns the number of samples replaced.
    @discardableResult
    func adoptEngineKinematics(engineT et: [Double], speed: [Double], speedSigma: [Double], accel: [Double], accelSigma: [Double],
                               offsetS: Double) -> Int {
        let n: Int = t.count
        let m: Int = min(et.count, speed.count)
        if n == 0 || m < 2 || abs(filterParameters.jerkDensity - 1.0) > 1e-9 { return 0 }
        func at(_ a: [Double], _ j: Int) -> Double { j < a.count ? a[j] : .nan }
        var v: [Double] = speedFiltered, sv: [Double] = speedFilteredSigma, a: [Double] = accelLong, sa: [Double] = accelLongSigma
        var replaced: Int = 0
        var j: Int = 0
        for i in 0..<n {
            let te: Double = t[i] + offsetS
            while j + 1 < m && et[j + 1] <= te { j += 1 }
            if j + 1 >= m || et[j] > te { continue }
            let t0: Double = et[j], t1: Double = et[j + 1]
            if !(t1 > t0) || t1 - t0 > 0.5 { continue }
            let w: Double = (te - t0) / (t1 - t0)
            func lerp(_ x: [Double]) -> Double {
                let x0: Double = at(x, j), x1: Double = at(x, j + 1)
                return x0.isFinite && x1.isFinite ? x0 + w * (x1 - x0) : .nan
            }
            let vi: Double = lerp(speed)
            if !vi.isFinite { continue }
            v[i] = max(0, vi)
            let svi: Double = lerp(speedSigma); if svi.isFinite { sv[i] = svi }
            let ai: Double = lerp(accel); if ai.isFinite { a[i] = ai }
            let sai: Double = lerp(accelSigma); if sai.isFinite { sa[i] = sai }
            replaced += 1
        }
        if replaced < n / 2 { return 0 }   // the engine does not describe this timeline: keep the app values
        speedFiltered = v; speedFilteredSigma = sv; accelLong = a; accelLongSigma = sa
        kinematicsSource = "motor"
        return replaced
    }

    static func weekDiffMs(_ itow: Int64, _ itow0: Int64) -> Int64 {
        var d: Int64 = itow - itow0
        if d < -302_400_000 { d += 604_800_000 }
        else if d > 302_400_000 { d -= 604_800_000 }
        return d
    }

    /// - Parameter timeBaseItowMs: GPS time of week that defines t = 0. Default: first usable epoch. A trimmed session passes the
    ///   time base of the full file, so cursor, segments and engine times keep the same meaning after trimming.
    static func build(_ session: TrainingSession, parameters: SpeedSmoother.Parameters? = nil, timeBaseItowMs: Int64? = nil) -> SessionTimeline {
        let p: SpeedSmoother.Parameters = parameters ?? SpeedSmoother.Parameters()
        let track: [TrackPoint] = session.track
        let n: Int = track.count
        if n == 0 {
            let empty = SessionTimeline()
            empty.filterParameters = p
            return empty
        }
        let itow0: Int64 = timeBaseItowMs ?? track[0].gpsWeekMs
        var t: [Double] = [Double](repeating: 0, count: n)
        var acc: Int64 = weekDiffMs(track[0].gpsWeekMs, itow0)
        for i in 0..<n {
            if i > 0 {
                let step: Int64 = weekDiffMs(track[i].gpsWeekMs, track[i - 1].gpsWeekMs)
                acc += step
            }
            t[i] = Double(acc) / 1000.0
        }
        var dts: [Double] = []
        dts.reserveCapacity(n)
        if n > 1 {
            for i in 1..<n {
                let d: Double = t[i] - t[i - 1]
                if d > 0 { dts.append(d) }
            }
        }
        let nominal: Double = dts.isEmpty ? 1.0 : Stats.median(dts)
        let gapLimit: Double = max(defaultGapFactor * nominal, nominal + 0.05)

        var lat: [Double] = [Double](repeating: 0, count: n)
        var lon: [Double] = [Double](repeating: 0, count: n)
        var vRep: [Double] = [Double](repeating: 0, count: n)
        var hAcc: [Double] = [Double](repeating: 0, count: n)
        var sAcc: [Double] = [Double](repeating: 0, count: n)
        var alt: [Double] = [Double](repeating: 0, count: n)
        var sv: [Int] = [Int](repeating: 0, count: n)
        var sol: [GnssSolution] = [GnssSolution](repeating: GnssSolution.none, count: n)
        var brk: [Bool] = [Bool](repeating: false, count: n)
        var jump: [Bool] = [Bool](repeating: false, count: n)
        for i in 0..<n {
            let q: TrackPoint = track[i]
            lat[i] = q.latitude; lon[i] = q.longitude; vRep[i] = q.speedMs; hAcc[i] = q.accuracyM
            sAcc[i] = q.speedAccMs; alt[i] = q.mslAltitudeM.isFinite ? q.mslAltitudeM : .nan
            sv[i] = q.numSv; sol[i] = q.solution
            brk[i] = i > 0 && (t[i] - t[i - 1] > gapLimit || t[i] - t[i - 1] <= 0)
        }

        // Distance with position-jump rejection (same rule family as the engine's validation: a step is implausible when it
        // exceeds 5 x (vmax*dt + 3*(hAcc1 + hAcc2) + 0.05 m)). Distance never bridges gaps.
        var dist: [Double] = [Double](repeating: 0, count: n)
        var stepD: [Double] = [Double](repeating: 0, count: n)
        if n > 1 {
            for i in 1..<n {
                let d: Double = Geo.haversineM(track[i - 1], track[i])
                let dt: Double = t[i] - t[i - 1]
                let vmax: Double = max(vRep[i], vRep[i - 1]) + 3 * max(finite(sAcc[i], 0.05), 0.05)
                let limit: Double = 5 * (vmax * max(dt, 0) + 3 * (finite(hAcc[i], 0) + finite(hAcc[i - 1], 0)) + 0.05)
                if brk[i] { dist[i] = dist[i - 1]; stepD[i] = .nan; continue }
                if d > limit { jump[i] = true; dist[i] = dist[i - 1]; stepD[i] = .nan; continue }
                stepD[i] = d
                dist[i] = dist[i - 1] + d
            }
        }

        // Speed derived from positions: central difference where both neighbours are continuous.
        var vDer: [Double] = [Double](repeating: 0, count: n)
        for i in 0..<n {
            var num: Double = 0
            var den: Double = 0
            if i > 0 && stepD[i].isFinite { num += stepD[i]; den += t[i] - t[i - 1] }
            if i + 1 < n && stepD[i + 1].isFinite { num += stepD[i + 1]; den += t[i + 1] - t[i] }
            vDer[i] = den > 0 ? num / den : .nan
        }

        let smooth: SpeedSmoother.Result = SpeedSmoother.smooth(t, vRep, sAcc, brk, p)

        // Lateral acceleration a_lat = v * omega, omega = (vN dvE/dt - vE dvN/dt) / v^2 (only for v >= 2 m/s, central differences).
        var aLat: [Double] = [Double](repeating: .nan, count: n)
        for i in 0..<n {
            aLat[i] = .nan
            if i == 0 || i == n - 1 || brk[i] || brk[i + 1] { continue }
            let a: TrackPoint = track[i - 1]
            let b: TrackPoint = track[i]
            let c: TrackPoint = track[i + 1]
            if !b.velNorthMs.isFinite || !a.velNorthMs.isFinite || !c.velNorthMs.isFinite { continue }
            let v: Double = (b.velNorthMs * b.velNorthMs + b.velEastMs * b.velEastMs).squareRoot()
            if v < 2 { continue }
            let dt: Double = t[i + 1] - t[i - 1]
            if dt <= 0 { continue }
            let dvn: Double = (c.velNorthMs - a.velNorthMs) / dt
            let dve: Double = (c.velEastMs - a.velEastMs) / dt
            let omega: Double = (b.velNorthMs * dve - b.velEastMs * dvn) / (v * v)
            let al: Double = v * omega
            aLat[i] = abs(al) <= 15 ? al : .nan
        }

        let tl = SessionTimeline()
        tl.t = t; tl.lat = lat; tl.lon = lon; tl.speedReported = vRep; tl.speedDerived = vDer; tl.speedFiltered = smooth.speed
        tl.speedFilteredSigma = smooth.speedSigma; tl.accelLong = smooth.accel; tl.accelLongSigma = smooth.accelSigma; tl.accelLateral = aLat
        tl.distance = dist; tl.altitudeMsl = alt; tl.hAcc = hAcc; tl.speedAcc = sAcc; tl.numSv = sv; tl.solution = sol
        tl.breakBefore = brk; tl.jumpBefore = jump
        tl.nominalDtS = nominal; tl.itow0Ms = itow0; tl.filterParameters = p
        let u0: Date? = track[0].utcTime ?? session.startedAt
        tl.utc0 = u0
        tl.utc0Ticks = u0.map { DotNetFormat.ticks($0) }

        // Signal-loss intervals: gaps between usable epochs plus received epochs without a valid solution.
        if n > 1 {
            for i in 1..<n where brk[i] {
                tl.losses.append(SignalLoss(t0: t[i - 1], t1: t[i], reason: "Sin épocas GNSS utilizables"))
            }
        }
        var invalidStart: Double? = nil
        for e in session.gnssEpochs {
            let te: Double = Double(weekDiffMs(e.gpsWeekMs, itow0)) / 1000.0
            if e.solution == GnssSolution.none {
                if invalidStart == nil { invalidStart = te }
            } else if let s0 = invalidStart {
                if te - s0 > nominal { tl.losses.append(SignalLoss(t0: s0, t1: te, reason: "Épocas sin solución válida")) }
                invalidStart = nil
            }
        }
        return tl
    }

    private static func finite(_ v: Double, _ fallback: Double) -> Double { v.isFinite ? v : fallback }

    /// C# Array.BinarySearch (returns the index, or the bitwise complement of the insertion point).
    static func binarySearch(_ a: [Double], _ value: Double) -> Int {
        var lo: Int = 0
        var hi: Int = a.count - 1
        while lo <= hi {
            let i: Int = lo + ((hi - lo) >> 1)
            let v: Double = a[i]
            if v == value { return i }
            if v < value || (v.isNaN && !value.isNaN) { lo = i + 1 } else { hi = i - 1 }
        }
        return ~lo
    }

    /// Index of the sample nearest to time (binary search), or -1 if empty.
    func indexAt(_ time: Double) -> Int {
        if t.isEmpty { return -1 }
        var i: Int = SessionTimeline.binarySearch(t, time)
        if i >= 0 { return i }
        i = ~i
        if i <= 0 { return 0 }
        if i >= t.count { return t.count - 1 }
        return time - t[i - 1] <= t[i] - time ? i - 1 : i
    }

    /// Index of the sample nearest to cumulative distance d.
    func indexAtDistance(_ d: Double) -> Int {
        if distance.isEmpty { return -1 }
        var i: Int = SessionTimeline.binarySearch(distance, d)
        if i >= 0 { return i }
        i = ~i
        return min(max(i, 0), distance.count - 1)
    }

    /// UTC instant of a sample (utc0 + t[index] - t[0]), tick precision.
    func utcTicksAt(_ index: Int) -> Int64? {
        guard let u = utc0Ticks, index >= 0, index < t.count else { return nil }
        return DotNetFormat.addSeconds(u, t[index] - t[0])
    }

    func utcAt(_ index: Int) -> Date? {
        guard let ticks = utcTicksAt(index) else { return nil }
        return DotNetFormat.date(ticks: ticks)
    }

    /// Seconds since the first GNSS epoch for a GPS time of week (ms).
    func timeOfItow(_ itow: Int64) -> Double { Double(SessionTimeline.weekDiffMs(itow, itow0Ms)) / 1000.0 }

    /// Fraction (0..1) of samples in [t0,t1] with the given minimum solution.
    func fractionAtLeast(_ minimum: GnssSolution, _ t0: Double, _ t1: Double) -> Double {
        var total: Int = 0
        var ok: Int = 0
        for i in 0..<t.count {
            if t[i] < t0 || t[i] > t1 { continue }
            total += 1
            if solution[i] >= minimum { ok += 1 }
        }
        return total > 0 ? Double(ok) / Double(total) : 0
    }
}

/// Kalman filter + Rauch–Tung–Striebel smoother of the reported ground speed. Model: state [v, a], constant-acceleration
/// with white jerk (spectral density `Parameters.jerkDensity`, m²/s⁵). Measurement z = gSpeed with
/// variance max(sAcc, minSpeedSigma)², where sAcc is the speed accuracy reported by the receiver (fallbackSpeedSigma when
/// unavailable). The filter restarts after every gap, so it never interpolates through missing data.
/// Effects: removes measurement noise of the Doppler speed and yields a longitudinal acceleration with its 1-sigma
/// uncertainty; it smooths short real peaks (about 1/3 s at the defaults). The unfiltered speed is always kept.
enum SpeedSmoother {
    struct Parameters: Equatable {
        var jerkDensity: Double = 1.0
        var minSpeedSigma: Double = 0.05
        var fallbackSpeedSigma: Double = 0.15
        var initialAccelSigma: Double = 2.0

        init(jerkDensity: Double = 1.0, minSpeedSigma: Double = 0.05, fallbackSpeedSigma: Double = 0.15, initialAccelSigma: Double = 2.0) {
            self.jerkDensity = jerkDensity
            self.minSpeedSigma = minSpeedSigma
            self.fallbackSpeedSigma = fallbackSpeedSigma
            self.initialAccelSigma = initialAccelSigma
        }

        /// Interpolated with the current culture of the Windows app (es-ES).
        func describe() -> String {
            "Kalman v-a + suavizado RTS · densidad de sacudida \(DotNetFormat.custom(jerkDensity, "0.##", spanish: true)) m²/s⁵ · σv mín. \(DotNetFormat.custom(minSpeedSigma, "0.###", spanish: true)) m/s · σv sin sAcc \(DotNetFormat.custom(fallbackSpeedSigma, "0.###", spanish: true)) m/s"
        }
    }

    struct Result {
        var speed: [Double]
        var speedSigma: [Double]
        var accel: [Double]
        var accelSigma: [Double]
    }

    static func smooth(_ t: [Double], _ z: [Double], _ sAcc: [Double], _ breakBefore: [Bool], _ p: Parameters) -> Result {
        let n: Int = t.count
        var v: [Double] = [Double](repeating: 0, count: n)
        var a: [Double] = [Double](repeating: 0, count: n)
        var sv: [Double] = [Double](repeating: 0, count: n)
        var sa: [Double] = [Double](repeating: 0, count: n)
        if n == 0 { return Result(speed: v, speedSigma: sv, accel: a, accelSigma: sa) }
        var start: Int = 0
        for i in 1...n {
            if i == n || breakBefore[i] {
                runPiece(t, z, sAcc, p, start, i, &v, &a, &sv, &sa)
                start = i
            }
        }
        return Result(speed: v, speedSigma: sv, accel: a, accelSigma: sa)
    }

    private static func runPiece(_ t: [Double], _ z: [Double], _ sAcc: [Double], _ p: Parameters, _ i0: Int, _ i1: Int,
                                 _ vOut: inout [Double], _ aOut: inout [Double], _ svOut: inout [Double], _ saOut: inout [Double]) {
        let m: Int = i1 - i0
        if m <= 0 { return }
        // Forward pass storage: filtered and predicted states/covariances (2x2 symmetric: [p00, p01, p11]), flattened.
        var xf: [Double] = [Double](repeating: 0, count: m * 2)
        var pf: [Double] = [Double](repeating: 0, count: m * 3)
        var xp: [Double] = [Double](repeating: 0, count: m * 2)
        var pp: [Double] = [Double](repeating: 0, count: m * 3)
        var x0: Double = z[i0].isFinite ? z[i0] : 0
        var x1: Double = 0
        let r0: Double = sigma(sAcc[i0], p)
        var p00: Double = r0 * r0
        var p01: Double = 0
        var p11: Double = p.initialAccelSigma * p.initialAccelSigma
        for k in 0..<m {
            let i: Int = i0 + k
            if k > 0 {
                let dt: Double = max(t[i] - t[i - 1], 1e-3)
                // predict
                let nx0: Double = x0 + dt * x1
                let nx1: Double = x1
                let q: Double = p.jerkDensity
                let q00: Double = q * dt * dt * dt / 3
                let q01: Double = q * dt * dt / 2
                let q11: Double = q * dt
                let n00: Double = p00 + 2 * dt * p01 + dt * dt * p11 + q00
                let n01: Double = p01 + dt * p11 + q01
                let n11: Double = p11 + q11
                x0 = nx0; x1 = nx1; p00 = n00; p01 = n01; p11 = n11
            }
            xp[k * 2] = x0; xp[k * 2 + 1] = x1; pp[k * 3] = p00; pp[k * 3 + 1] = p01; pp[k * 3 + 2] = p11
            let zi: Double = z[i]
            if zi.isFinite {
                let r: Double = sigma(sAcc[i], p)
                let rr: Double = r * r
                let s: Double = p00 + rr
                let k0: Double = p00 / s
                let k1: Double = p01 / s
                let y: Double = zi - x0
                x0 += k0 * y; x1 += k1 * y
                let u00: Double = (1 - k0) * p00
                let u01: Double = (1 - k0) * p01
                let u11: Double = p11 - k1 * p01
                p00 = u00; p01 = u01; p11 = u11
            }
            xf[k * 2] = x0; xf[k * 2 + 1] = x1; pf[k * 3] = p00; pf[k * 3 + 1] = p01; pf[k * 3 + 2] = p11
        }
        // RTS backward pass
        var sx0: Double = xf[(m - 1) * 2]
        var sx1: Double = xf[(m - 1) * 2 + 1]
        var s00: Double = pf[(m - 1) * 3]
        var s01: Double = pf[(m - 1) * 3 + 1]
        var s11: Double = pf[(m - 1) * 3 + 2]

        func store(_ k: Int) {
            vOut[i0 + k] = max(0, sx0)
            aOut[i0 + k] = sx1
            svOut[i0 + k] = max(0, s00).squareRoot()
            saOut[i0 + k] = max(0, s11).squareRoot()
        }
        store(m - 1)
        var k: Int = m - 2
        while k >= 0 {
            let i: Int = i0 + k + 1
            let dt: Double = max(t[i] - t[i - 1], 1e-3)
            // C = Pf F^T Pp(k+1)^-1
            let f00: Double = pf[k * 3]
            let f01: Double = pf[k * 3 + 1]
            let f11: Double = pf[k * 3 + 2]
            // Pf F^T with F = [[1, dt],[0, 1]]: [[f00 + dt f01, f01],[f01 + dt f11, f11]]
            let a00: Double = f00 + dt * f01
            let a01: Double = f01
            let a10: Double = f01 + dt * f11
            let a11: Double = f11
            let q00: Double = pp[(k + 1) * 3]
            let q01: Double = pp[(k + 1) * 3 + 1]
            let q11: Double = pp[(k + 1) * 3 + 2]
            let det: Double = q00 * q11 - q01 * q01
            if abs(det) < 1e-18 {
                sx0 = xf[k * 2]; sx1 = xf[k * 2 + 1]; s00 = f00; s01 = f01; s11 = f11
                store(k)
                k -= 1
                continue
            }
            let inv00: Double = q11 / det
            let inv01: Double = -q01 / det
            let inv11: Double = q00 / det
            let c00: Double = a00 * inv00 + a01 * inv01
            let c01: Double = a00 * inv01 + a01 * inv11
            let c10: Double = a10 * inv00 + a11 * inv01
            let c11: Double = a10 * inv01 + a11 * inv11
            let d0: Double = sx0 - xp[(k + 1) * 2]
            let d1: Double = sx1 - xp[(k + 1) * 2 + 1]
            let nx0: Double = xf[k * 2] + c00 * d0 + c01 * d1
            let nx1: Double = xf[k * 2 + 1] + c10 * d0 + c11 * d1
            // Ps = Pf + C (Ps(k+1) - Pp(k+1)) C^T
            let e00: Double = s00 - q00
            let e01: Double = s01 - q01
            let e11: Double = s11 - q11
            let g00: Double = c00 * e00 + c01 * e01
            let g01: Double = c00 * e01 + c01 * e11
            let g10: Double = c10 * e00 + c11 * e01
            let g11: Double = c10 * e01 + c11 * e11
            let n00: Double = f00 + g00 * c00 + g01 * c01
            let n01: Double = f01 + g00 * c10 + g01 * c11
            let n11: Double = f11 + g10 * c10 + g11 * c11
            sx0 = nx0; sx1 = nx1; s00 = n00; s01 = n01; s11 = n11
            store(k)
            k -= 1
        }
    }

    private static func sigma(_ sAcc: Double, _ p: Parameters) -> Double {
        sAcc.isFinite && sAcc > 0 ? max(sAcc, p.minSpeedSigma) : p.fallbackSpeedSigma
    }
}

enum Stats {
    static func median(_ values: [Double]) -> Double {
        let a: [Double] = values.filter { $0.isFinite }.sorted()
        if a.isEmpty { return .nan }
        return a.count % 2 == 1 ? a[a.count / 2] : (a[a.count / 2 - 1] + a[a.count / 2]) / 2
    }

    static func maxFinite(_ values: [Double], fallback: Double = .nan) -> Double {
        var m: Double = -Double.infinity
        for v in values where v.isFinite && v > m { m = v }
        return m == -Double.infinity ? fallback : m
    }

    static func minFinite(_ values: [Double], fallback: Double = .nan) -> Double {
        var m: Double = Double.infinity
        for v in values where v.isFinite && v < m { m = v }
        return m == Double.infinity ? fallback : m
    }
}

/// Useful part of a training chosen by the user (start and end inside the whole recording). The original file is never
/// modified: a filtered copy of the decoded data is analysed with the time base of the full file.
enum SessionWindow {
    static func apply(_ s: TrainingSession, itow0: Int64, t0: Double, t1: Double) -> TrainingSession {
        func inWindow(_ itow: Int64) -> Bool {
            let t: Double = Double(SessionTimeline.weekDiffMs(itow, itow0)) / 1000.0
            return t >= t0 && t <= t1
        }
        let c = TrainingSession()
        c.sessionId = s.sessionId; c.sha256 = s.sha256; c.horse = s.horse; c.rider = s.rider; c.horseCode = s.horseCode
        c.riderCode = s.riderCode; c.horseInFile = s.horseInFile; c.riderInFile = s.riderInFile; c.identityApplied = s.identityApplied
        c.rawHorse = s.rawHorse; c.rawRider = s.rawRider; c.fileAssignment = s.fileAssignment
        c.startedAt = s.startedAt; c.sourceName = s.sourceName
        c.integrity = s.integrity; c.hasRawTelemetry = s.hasRawTelemetry; c.declaredDistanceM = s.declaredDistanceM
        c.declaredDurationS = s.declaredDurationS
        c.declaredMaxSpeedMs = s.declaredMaxSpeedMs; c.totalImuSamples = s.totalImuSamples; c.totalImuBatches = s.totalImuBatches
        c.invalidFrames = s.invalidFrames
        c.markerCount = s.markerCount; c.imuPeriodUs = s.imuPeriodUs; c.imuOpaqueBatches = s.imuOpaqueBatches; c.imuUnits = s.imuUnits
        c.imuFusedBatches = s.imuFusedBatches; c.fileSha256 = s.fileSha256
        c.sourcePath = s.sourcePath; c.declaredCanonicalSha256 = s.declaredCanonicalSha256; c.discipline = s.discipline
        c.track = s.track.filter { inWindow($0.gpsWeekMs) }
        c.gnssEpochs = s.gnssEpochs.filter { inWindow($0.gpsWeekMs) }
        c.gnssSamples = c.gnssEpochs.count
        c.rtkFixCount = c.track.filter { $0.carrierSolution == 2 }.count
        c.rtkFloatCount = c.track.filter { $0.carrierSolution == 1 }.count
        c.gnssOtherCount = c.track.count - c.rtkFixCount - c.rtkFloatCount
        c.unusableGnssSamples = c.gnssSamples - c.track.count
        c.imu = s.imu            // clipped to the window by ImuTimeline.build
        c.imuFused = s.imuFused
        c.markers = s.markers
        c.segments = s.segments
        c.rawSegmentPaths = s.rawSegmentPaths
        return c
    }
}
