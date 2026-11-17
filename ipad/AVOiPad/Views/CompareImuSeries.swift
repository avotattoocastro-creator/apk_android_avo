import Foundation

/// Girth IMU series of one session resampled onto its GNSS timeline (one value per epoch), so they can be aligned with
/// `SeriesAligner` like the speed and the acceleration on the «Comparar» page. Only measured data: nil when the session
/// has no girth IMU (or it is not time-aligned with the timeline).
///
/// - Lateral deviation: horizontal linear acceleration perpendicular to the horse's longitudinal axis. With the fused
///   output (fmt 1, BNO085) the linear acceleration and the sensor X axis are both rotated to the world frame with the
///   game rotation vector, so the heading drift cancels; the sensor X axis is taken as the horse's longitudinal axis
///   (mounting not verified). Fallback (raw fmt 0): sensor Y axis minus its median (removes the static gravity part).
/// - Tilts: roll / pitch of the girth (fused quaternion; fallback: estimated from the accelerometer), shown relative to
///   the median of the training because the mounting is not calibrated.
enum CompareImuSeries {
    struct Result {
        var lateral: [Double]
        var roll: [Double]
        var pitch: [Double]
        var source: String
    }

    /// Preferred sensor: central (0) when present, otherwise the lowest id.
    private static func pick(_ ids: [UInt8]) -> UInt8? {
        if ids.contains(0) { return 0 }
        return ids.min()
    }

    static func build(session: TrainingSession, imu: ImuTimeline, timeline tl: SessionTimeline) -> Result? {
        if tl.count < 2 || !imu.aligned { return nil }
        let lo: Double = tl.t[0]
        let hi: Double = tl.t[tl.count - 1]
        let off: Double = imu.offsetS

        // fused (fmt 1)
        let fusedIds: [UInt8] = Array(Set(session.imuFused.map { $0.imuId })).sorted()
        if let id = pick(fusedIds) {
            var t: [Double] = []
            var lat: [Double] = []
            var roll: [Double] = []
            var pitch: [Double] = []
            for f in session.imuFused where f.imuId == id {
                let ts: Double = f.timeS - off
                if ts < lo - 1 || ts > hi + 1 { continue }
                let r = fuseLateral(f)
                t.append(ts); lat.append(r.lateral); roll.append(r.roll); pitch.append(r.pitch)
            }
            if t.count > 1 {
                let order: [Int] = Array(0..<t.count).sorted { (a: Int, b: Int) -> Bool in t[a] < t[b] || (t[a] == t[b] && a < b) }
                let ts: [Double] = order.map { t[$0] }
                let rollRel: [Double] = relative(order.map { roll[$0] })
                let pitchRel: [Double] = relative(order.map { pitch[$0] })
                return Result(lateral: perEpoch(tl, ts, order.map { lat[$0] }), roll: perEpoch(tl, ts, rollRel),
                              pitch: perEpoch(tl, ts, pitchRel),
                              source: "IMU fusionada (\(ImuTimeline.sensorName(id)))")
            }
        }

        // raw (fmt 0), already windowed and time-aligned by ImuTimeline
        let rawIds: [UInt8] = imu.channels.map { $0.imuId }
        if let id = pick(rawIds), let ch = imu.channels.first(where: { $0.imuId == id }), ch.t.count > 1 {
            let g: Double = 9.80665
            let ax: [Double] = ch.axisG("x")
            let ay: [Double] = ch.axisG("y")
            let az: [Double] = ch.axisG("z")
            let n: Int = min(ch.t.count, min(ax.count, min(ay.count, az.count)))
            var latRaw: [Double] = [Double](repeating: .nan, count: n)
            var roll: [Double] = [Double](repeating: .nan, count: n)
            var pitch: [Double] = [Double](repeating: .nan, count: n)
            for i in 0..<n {
                latRaw[i] = ay[i] * g
                roll[i] = atan2(ay[i], az[i]) * 180 / Double.pi
                pitch[i] = atan2(-ax[i], (ay[i] * ay[i] + az[i] * az[i]).squareRoot()) * 180 / Double.pi
            }
            let ts: [Double] = Array(ch.t.prefix(n))
            return Result(lateral: perEpoch(tl, ts, relative(latRaw)), roll: perEpoch(tl, ts, relative(roll)),
                          pitch: perEpoch(tl, ts, relative(pitch)),
                          source: "IMU sin fusionar (\(ImuTimeline.sensorName(id)), estimación del acelerómetro)")
        }
        return nil
    }

    /// Lateral linear acceleration (m/s², positive to the left of the sensor X axis) and roll / pitch (degrees).
    private static func fuseLateral(_ f: ImuFusedSample) -> (lateral: Double, roll: Double, pitch: Double) {
        var x: Double = Double(f.qi) / 16384.0
        var y: Double = Double(f.qj) / 16384.0
        var z: Double = Double(f.qk) / 16384.0
        var w: Double = Double(f.qr) / 16384.0
        let nq: Double = (x * x + y * y + z * z + w * w).squareRoot()
        if nq < 1e-6 { return (lateral: .nan, roll: .nan, pitch: .nan) }
        x /= nq; y /= nq; z /= nq; w /= nq
        let ax: Double = Double(f.lx) / 256.0
        let ay: Double = Double(f.ly) / 256.0
        let az: Double = Double(f.lz) / 256.0
        let r00: Double = 1.0 - 2.0 * (y * y + z * z)
        let r01: Double = 2.0 * (x * y - z * w)
        let r02: Double = 2.0 * (x * z + y * w)
        let r10: Double = 2.0 * (x * y + z * w)
        let r11: Double = 1.0 - 2.0 * (x * x + z * z)
        let r12: Double = 2.0 * (y * z - x * w)
        let wx: Double = r00 * ax + r01 * ay + r02 * az
        let wy: Double = r10 * ax + r11 * ay + r12 * az
        // sensor X axis in the world frame, projected on the horizontal plane
        let fx: Double = r00
        let fy: Double = r10
        let fn: Double = (fx * fx + fy * fy).squareRoot()
        let lateral: Double = fn < 0.2 ? .nan : (fx * wy - fy * wx) / fn
        let roll: Double = atan2(2.0 * (w * x + y * z), 1.0 - 2.0 * (x * x + y * y)) * 180.0 / Double.pi
        let pitch: Double = asin(min(max(2.0 * (w * y - z * x), -1.0), 1.0)) * 180.0 / Double.pi
        return (lateral: lateral, roll: roll, pitch: pitch)
    }

    /// Values minus their median (NaN stays NaN).
    private static func relative(_ v: [Double]) -> [Double] {
        let m: Double = Stats.median(v)
        if !m.isFinite { return v }
        return v.map { $0.isFinite ? $0 - m : .nan }
    }

    /// Mean of the IMU samples around each timeline epoch (half the interval to each neighbour, at most one nominal step;
    /// nothing across gaps). `ts` must be ascending. NaN where no sample falls in the interval.
    static func perEpoch(_ tl: SessionTimeline, _ ts: [Double], _ v: [Double]) -> [Double] {
        let n: Int = tl.count
        var out: [Double] = [Double](repeating: .nan, count: n)
        let m: Int = min(ts.count, v.count)
        if n == 0 || m == 0 { return out }
        let step: Double = tl.nominalDtS > 0 ? tl.nominalDtS : 0.1
        var j: Int = 0
        for i in 0..<n {
            let ti: Double = tl.t[i]
            let prevHalf: Double = (i > 0 && !tl.breakBefore[i]) ? min((ti - tl.t[i - 1]) / 2, step) : step / 2
            let nextHalf: Double = (i + 1 < n && !tl.breakBefore[i + 1]) ? min((tl.t[i + 1] - ti) / 2, step) : step / 2
            let a: Double = ti - prevHalf
            let b: Double = ti + nextHalf
            while j < m && ts[j] < a { j += 1 }
            var k: Int = j
            var sum: Double = 0
            var cnt: Int = 0
            while k < m && ts[k] < b {
                if v[k].isFinite { sum += v[k]; cnt += 1 }
                k += 1
            }
            if cnt > 0 { out[i] = sum / Double(cnt) }
        }
        return out
    }

    /// Engine cadence (cycles/min, first girth IMU) per timeline epoch: nearest engine value within 1.5 s.
    static func cadence(_ e: EquineAnalysis?, offset: Double, timeline tl: SessionTimeline) -> [Double]? {
        guard let e = e, e.hasImu, let imu = e.girthImu.min(), tl.count > 1 else { return nil }
        let nE: Int = min(e.girthT.count, min(e.girthImu.count, e.girthCadenceHz.count))
        var pairs: [(t: Double, v: Double)] = []
        for k in 0..<nE where e.girthImu[k] == imu && e.girthT[k].isFinite && e.girthCadenceHz[k].isFinite {
            pairs.append((t: e.girthT[k] - offset, v: e.girthCadenceHz[k] * 60))
        }
        if pairs.isEmpty { return nil }
        pairs.sort { (a: (t: Double, v: Double), b: (t: Double, v: Double)) -> Bool in a.t < b.t }
        var out: [Double] = [Double](repeating: .nan, count: tl.count)
        var j: Int = 0
        for i in 0..<tl.count {
            let ti: Double = tl.t[i]
            while j + 1 < pairs.count && pairs[j + 1].t <= ti { j += 1 }
            var best: Int = j
            if j + 1 < pairs.count && abs(pairs[j + 1].t - ti) < abs(pairs[j].t - ti) { best = j + 1 }
            if abs(pairs[best].t - ti) <= 1.5 { out[i] = pairs[best].v }
        }
        return out
    }
}
