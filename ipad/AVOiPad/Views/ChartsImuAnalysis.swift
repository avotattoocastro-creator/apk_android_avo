import SwiftUI

// MARK: - Girth IMU analysis for the «Gráficas» page (lateral deviations, tilt and anomalies)
//
// Everything here runs off the main thread (called from ChartsModel.rebuild inside Task.detached). Inputs are the
// decoded samples of the session; nothing is invented: without girth data the result is empty and the page shows
// «Sin datos de cincha (IMU)».
//
// Sources, in order of preference:
//   1. fmt 1 (BNO085 fused, GIRTH 0.4.x): linear acceleration (gravity removed, Q8 m/s²) + game rotation vector
//      (Q14). The acceleration is rotated to the world frame of the game rotation vector (Z up). Its yaw drifts and has
//      an arbitrary origin, so the GNSS direction of travel is related to it through a slowly varying offset estimated
//      from the girth's own forward axis (see `headingOffsets`).
//   2. fmt 0 only (raw accelerometer): gravity is estimated with a 1 s moving average; tilt comes from that gravity
//      vector and the lateral acceleration is taken on the sensor lateral axis (approximation, nominal scale).
//
// Axis convention (as ImuTimeline.fuse): roll = rotation about the sensor x axis (lateral tilt of the horse),
// pitch = rotation about the sensor y axis (nose up/down). The mounting orientation on the horse is NOT verified, so
// the sign of the sensor-axis fallback may be inverted; with the GNSS heading, positive lateral = to the left of the
// direction of travel.

/// Point drawn on a chart (anomaly / sudden deviation).
struct SyncMarker: Identifiable {
    var id: Int
    var x: Double
    var y: Double
    var color: Color
}

/// One detected girth event (listed under the IMU charts; tapping it moves the shared cursor).
struct ChartsImuEvent: Identifiable, Equatable {
    var id: Int
    var t: Double
    /// «Desvío lateral», «Balanceo», «Cabeceo» or «Vertical».
    var kind: String
    /// Signed value at the peak.
    var value: Double
    /// |value − local median| at the peak.
    var deviation: Double
    var unit: String

    var text: String {
        TimeText.clock(t) + " · " + kind + " " + DotNetFormat.custom(value, "0.0", spanish: true) + " " + unit
    }
}

/// Result of the girth analysis.
struct ChartsImuResult {
    /// 0 no girth data, 1 fused (fmt 1), 2 raw only (fmt 0).
    var source: Int = 0
    var sensorName: String = ""
    var lateral: [SyncSource] = []
    var tilt: [SyncSource] = []
    /// Vertical acceleration and |a| without gravity («Más gráficas»).
    var vertical: [SyncSource] = []
    var lateralMarkers: [SyncMarker] = []
    var tiltMarkers: [SyncMarker] = []
    var lateralEvents: [ChartsImuEvent] = []
    var tiltEvents: [ChartsImuEvent] = []
    /// How the direction of travel was obtained (caption of the lateral chart).
    var headingNote: String = ""
    /// Primary-sensor series for the cursor readouts.
    var t: [Double] = []
    var lateralY: [Double] = []
    var rollY: [Double] = []
    var pitchY: [Double] = []
    var verticalY: [Double] = []
}

enum ChartsImuAnalysis {
    // ------------------------------------------------------------------ thresholds (documented, tunable)
    /// Light smoothing of the lateral acceleration: centred moving average of ±0.1 s (0.2 s window). Removes sensor
    /// noise but keeps a sideways jump (espantada lasts several tenths of a second).
    static let lateralSmoothHalfS: Double = 0.10
    /// Smoothing of the vertical acceleration: ±0.05 s.
    static let verticalSmoothHalfS: Double = 0.05
    /// Sliding window of the robust baseline (median and MAD): 20 s, evaluated in 2 s blocks. Long enough to contain
    /// many strides (the gait oscillation becomes part of the "normal" spread), short enough to follow gait changes.
    static let baselineWindowS: Double = 20
    static let baselineBlockS: Double = 2
    /// At most this many values (strided) are used to compute each window's median/MAD (cost bound).
    static let baselineMaxValues: Int = 800
    /// Lateral deviation: |a_lat − median| > max(5 · σ_MAD, 2.0 m/s²), σ_MAD = 1.4826 · MAD (≈ σ for Gaussian noise).
    static let lateralK: Double = 5
    static let lateralFloorMs2: Double = 2.0
    /// Roll / pitch: |angle − median| > max(5 · σ_MAD, 5°).
    static let tiltK: Double = 5
    static let tiltFloorDeg: Double = 5
    /// Vertical acceleration: |a_z − median| > max(6 · σ_MAD, 4 m/s²) (the gait itself oscillates strongly in z).
    static let verticalK: Double = 6
    static let verticalFloorMs2: Double = 4
    /// Exceedances closer than this are one event (peak = largest deviation).
    static let mergeGapS: Double = 1.0
    /// At most this many events per chart (the largest deviations), to keep long sessions readable.
    static let maxEvents: Int = 300
    /// GNSS direction of travel is used only with filtered speed ≥ 2 m/s (below it the course is noise).
    static let minHeadingSpeedMs: Double = 2.0
    /// Heading offset (game frame ↔ GNSS): circular mean of (course − girth yaw) over ±15 s, in 1 s blocks; valid
    /// with ≥ 20 samples and resultant length ≥ 0.5 (consistent offset).
    static let offsetHalfWindowS: Double = 15
    static let offsetMinSamples: Int = 20
    static let offsetMinResultant: Double = 0.5
    /// Raw fallback: gravity = moving average of ±0.5 s of the accelerometer.
    static let rawGravityHalfS: Double = 0.5
    static let g0: Double = 9.80665

    static let lateralColor: Color = Color(hex: 0x35D0E8)
    static let rollColor: Color = Color(hex: 0xFFC42C)
    static let pitchColor: Color = Color(hex: 0xA86BFF)
    static let verticalColor: Color = Color(hex: 0xED122A)
    static let markerColor: Color = Color(hex: 0xFF3945)

    // ------------------------------------------------------------------ entry point
    static func analyze(_ tl: SessionTimeline, _ imu: ImuTimeline, _ fusedRaw: [ImuFusedSample]) -> ChartsImuResult {
        if !imu.fused.isEmpty {
            let r: ChartsImuResult? = analyzeFused(tl, imu, fusedRaw)
            if let ok = r { return ok }
        }
        if !imu.channels.isEmpty { return analyzeRaw(imu) }
        return ChartsImuResult()
    }

    /// Central sensor (id 0) when present, otherwise the lowest id.
    static func primaryId(_ ids: [UInt8]) -> UInt8? {
        if ids.contains(0) { return 0 }
        return ids.sorted().first
    }

    // ------------------------------------------------------------------ fmt 1 (fused)
    private static func analyzeFused(_ tl: SessionTimeline, _ imu: ImuTimeline, _ fusedRaw: [ImuFusedSample]) -> ChartsImuResult? {
        guard let pid = primaryId(imu.fused.map { $0.imuId }),
              let ch = imu.fused.first(where: { $0.imuId == pid }), ch.t.count >= 2 else { return nil }
        let tMin: Double = ch.t[0]
        let tMax: Double = ch.t[ch.t.count - 1]
        let off: Double = imu.offsetS
        // same samples as ImuTimeline.build (window = time range of the decoded channel), stable time order
        var picked: [(t: Double, s: ImuFusedSample, k: Int)] = []
        picked.reserveCapacity(ch.t.count)
        var k: Int = 0
        for f in fusedRaw where f.imuId == pid {
            let t: Double = f.timeS - off
            if t >= tMin && t <= tMax { picked.append((t: t, s: f, k: k)) }
            k += 1
        }
        picked.sort { (a: (t: Double, s: ImuFusedSample, k: Int), b: (t: Double, s: ImuFusedSample, k: Int)) -> Bool in
            if a.t != b.t { return a.t < b.t }
            return a.k < b.k
        }
        let n: Int = picked.count
        if n < 2 { return nil }

        var t: [Double] = [Double](repeating: 0, count: n)
        var wx: [Double] = [Double](repeating: .nan, count: n)
        var wy: [Double] = [Double](repeating: .nan, count: n)
        var wz: [Double] = [Double](repeating: .nan, count: n)
        var yaw: [Double] = [Double](repeating: .nan, count: n)
        var roll: [Double] = [Double](repeating: .nan, count: n)
        var pitch: [Double] = [Double](repeating: .nan, count: n)
        for i in 0..<n {
            let f: ImuFusedSample = picked[i].s
            t[i] = picked[i].t
            var x: Double = Double(f.qi) / 16384.0
            var y: Double = Double(f.qj) / 16384.0
            var z: Double = Double(f.qk) / 16384.0
            var w: Double = Double(f.qr) / 16384.0
            let qn: Double = (x * x + y * y + z * z + w * w).squareRoot()
            if qn < 1e-6 { continue }
            x /= qn; y /= qn; z /= qn; w /= qn
            let ax: Double = Double(f.lx) / 256.0
            let ay: Double = Double(f.ly) / 256.0
            let az: Double = Double(f.lz) / 256.0
            // v_world = R(q) · v_sensor (same matrix as ImuTimeline.fuse)
            let r00: Double = 1.0 - 2.0 * (y * y + z * z)
            let r01: Double = 2.0 * (x * y - z * w)
            let r02: Double = 2.0 * (x * z + y * w)
            let r10: Double = 2.0 * (x * y + z * w)
            let r11: Double = 1.0 - 2.0 * (x * x + z * z)
            let r12: Double = 2.0 * (y * z - x * w)
            let r20: Double = 2.0 * (x * z - y * w)
            let r21: Double = 2.0 * (y * z + x * w)
            let r22: Double = 1.0 - 2.0 * (x * x + y * y)
            wx[i] = r00 * ax + r01 * ay + r02 * az
            wy[i] = r10 * ax + r11 * ay + r12 * az
            wz[i] = r20 * ax + r21 * ay + r22 * az
            // forward axis of the girth (sensor x) in the horizontal plane; if it is nearly vertical use sensor y − 90°
            if (r00 * r00 + r10 * r10).squareRoot() >= 0.35 {
                yaw[i] = atan2(r10, r00)
            } else {
                yaw[i] = atan2(r11, r01) - Double.pi / 2
            }
            roll[i] = atan2(2.0 * (w * x + y * z), 1.0 - 2.0 * (x * x + y * y)) * 180.0 / Double.pi
            pitch[i] = asin(min(max(2.0 * (w * y - z * x), -1.0), 1.0)) * 180.0 / Double.pi
        }

        // direction of travel: GNSS course (game frame through the estimated offset) or the girth forward axis
        let course: [Double] = gnssCourseAt(tl, t)
        let offsets: [Double] = headingOffsets(t, course, yaw)
        var latRaw: [Double] = [Double](repeating: .nan, count: n)
        var usedGnss: Int = 0
        var finiteCount: Int = 0
        for i in 0..<n {
            guard wx[i].isFinite && wy[i].isFinite else { continue }
            var h: Double = yaw[i]
            if course[i].isFinite && offsets[i].isFinite {
                h = course[i] - offsets[i]
                usedGnss += 1
            }
            if !h.isFinite { continue }
            finiteCount += 1
            // horizontal component perpendicular to the heading; positive = left (Z up, right-handed)
            latRaw[i] = -sin(h) * wx[i] + cos(h) * wy[i]
        }
        let lateral: [Double] = movingAverage(t, latRaw, lateralSmoothHalfS)
        let vertical: [Double] = movingAverage(t, wz, verticalSmoothHalfS)
        let rollU: [Double] = unwrapDegrees(roll)

        var r = ChartsImuResult()
        r.source = 1
        r.sensorName = ImuTimeline.sensorName(pid)
        let pct: Double = finiteCount > 0 ? Double(usedGnss) / Double(finiteCount) * 100 : 0
        if usedGnss == 0 {
            r.headingNote = "Sin rumbo GNSS utilizable (velocidad < 2 m/s o sin posición): proyección sobre el eje lateral del sensor."
        } else {
            r.headingNote = "Proyección sobre el rumbo GNSS en el " + DotNetFormat.custom(pct, "0", spanish: true) +
                " % de las muestras (v ≥ 2 m/s); resto, eje lateral del sensor."
        }
        fill(&r, t: t, lateral: lateral, roll: rollU, pitch: pitch, vertical: vertical)

        // «Más gráficas»: vertical and |a| without gravity of every fused sensor (from ImuTimeline)
        var va: [SyncSource] = []
        let many: Bool = imu.fused.count > 1
        for f in imu.fused {
            let p: String = many ? f.name + " · " : ""
            let m: Int = min(f.verticalMs2.count, f.horizontalMs2.count)
            var mag: [Double] = [Double](repeating: .nan, count: m)
            for i in 0..<m {
                let v: Double = f.verticalMs2[i]
                let h: Double = f.horizontalMs2[i]
                if v.isFinite && h.isFinite { mag[i] = (v * v + h * h).squareRoot() }
            }
            va.append(SyncSource(name: p + "|a| sin gravedad", color: Color(hex: 0x35D0E8, alpha: 0.75), width: 1, x: f.t, y: mag))
            va.append(SyncSource(name: p + "Vertical (arriba +)", color: verticalColor, width: 1.2, x: f.t, y: f.verticalMs2))
        }
        r.vertical = va
        return r
    }

    // ------------------------------------------------------------------ fmt 0 (raw accelerometer only)
    private static func analyzeRaw(_ imu: ImuTimeline) -> ChartsImuResult {
        guard let pid = primaryId(imu.channels.map { $0.imuId }),
              let ch = imu.channels.first(where: { $0.imuId == pid }), ch.t.count >= 2 else { return ChartsImuResult() }
        let t: [Double] = ch.t
        let n: Int = t.count
        let ax: [Double] = ch.axisG("x").map { $0 * g0 }
        let ay: [Double] = ch.axisG("y").map { $0 * g0 }
        let az: [Double] = ch.axisG("z").map { $0 * g0 }
        let gx: [Double] = movingAverage(t, ax, rawGravityHalfS)
        let gy: [Double] = movingAverage(t, ay, rawGravityHalfS)
        let gz: [Double] = movingAverage(t, az, rawGravityHalfS)
        var vert: [Double] = [Double](repeating: .nan, count: n)
        var lat: [Double] = [Double](repeating: .nan, count: n)
        var mag: [Double] = [Double](repeating: .nan, count: n)
        var roll: [Double] = [Double](repeating: .nan, count: n)
        var pitch: [Double] = [Double](repeating: .nan, count: n)
        for i in 0..<n {
            let gn: Double = (gx[i] * gx[i] + gy[i] * gy[i] + gz[i] * gz[i]).squareRoot()
            if !(gn > 1) { continue }
            // unit "up" (an accelerometer at rest reads +1 g upwards)
            let ux: Double = gx[i] / gn
            let uy: Double = gy[i] / gn
            let uz: Double = gz[i] / gn
            let lx: Double = ax[i] - gx[i]
            let ly: Double = ay[i] - gy[i]
            let lz: Double = az[i] - gz[i]
            let v: Double = lx * ux + ly * uy + lz * uz
            vert[i] = v
            mag[i] = (lx * lx + ly * ly + lz * lz).squareRoot()
            // sensor y axis made horizontal: e_y − (e_y·u) u
            let hx: Double = -uy * ux
            let hy: Double = 1 - uy * uy
            let hz: Double = -uy * uz
            let hn: Double = (hx * hx + hy * hy + hz * hz).squareRoot()
            if hn > 0.2 {
                // horizontal part of the linear acceleration projected on it
                let px: Double = lx - v * ux
                let py: Double = ly - v * uy
                let pz: Double = lz - v * uz
                lat[i] = (px * hx + py * hy + pz * hz) / hn
            }
            roll[i] = atan2(gy[i], gz[i]) * 180.0 / Double.pi
            pitch[i] = atan2(-gx[i], (gy[i] * gy[i] + gz[i] * gz[i]).squareRoot()) * 180.0 / Double.pi
        }
        var r = ChartsImuResult()
        r.source = 2
        r.sensorName = ImuTimeline.sensorName(pid)
        r.headingNote = "Sin datos fusionados (fmt 1): aproximación sobre el eje lateral del sensor con la gravedad estimada (media de 1 s), escala nominal."
        let latS: [Double] = movingAverage(t, lat, lateralSmoothHalfS)
        let vertS: [Double] = movingAverage(t, vert, verticalSmoothHalfS)
        fill(&r, t: t, lateral: latS, roll: unwrapDegrees(roll), pitch: pitch, vertical: vertS)
        r.vertical = [
            SyncSource(name: "|a| sin gravedad (aprox.)", color: Color(hex: 0x35D0E8, alpha: 0.75), width: 1, x: t, y: mag),
            SyncSource(name: "Vertical (aprox., arriba +)", color: verticalColor, width: 1.2, x: t, y: vertS),
        ]
        return r
    }

    // ------------------------------------------------------------------ series, bands and events of the primary sensor
    private static func fill(_ r: inout ChartsImuResult, t: [Double], lateral: [Double], roll: [Double], pitch: [Double],
                             vertical: [Double]) {
        r.t = t
        r.lateralY = lateral
        r.rollY = roll
        r.pitchY = pitch
        r.verticalY = vertical

        // lateral: local median line with the ±threshold band (drawn as the "sigma" envelope of that line)
        let lb = robustBaseline(t, lateral)
        let lThr: [Double] = threshold(lb.scale, lateralK, lateralFloorMs2)
        r.lateral = [
            SyncSource(name: "Umbral (mediana ± " + DotNetFormat.custom(lateralK, "0", spanish: true) + "·MAD)",
                       color: Color(hex: 0xC9CBD1, alpha: 0.55), width: 0.8, dashed: true, x: t, y: lb.median,
                       sigma: lThr, sigmaColor: Color(hex: 0x35D0E8, alpha: 0.13)),
            SyncSource(name: "Lateral", color: lateralColor, width: 1.2, x: t, y: lateral),
        ]
        let lEvents: [Int] = detect(t, lateral, lb.median, lThr)
        var lev: [ChartsImuEvent] = []
        var lmk: [SyncMarker] = []
        for i in lEvents {
            lev.append(ChartsImuEvent(id: lev.count, t: t[i], kind: "Desvío lateral", value: lateral[i],
                                      deviation: abs(lateral[i] - lb.median[i]), unit: "m/s²"))
            lmk.append(SyncMarker(id: lmk.count, x: t[i], y: lateral[i], color: markerColor))
        }
        r.lateralEvents = lev
        r.lateralMarkers = lmk

        // tilt: roll / pitch lines; anomalies of roll, pitch and vertical acceleration
        r.tilt = [
            SyncSource(name: "Balanceo (inclinación lateral)", color: rollColor, width: 1.2, x: t, y: roll),
            SyncSource(name: "Cabeceo (adelante/atrás)", color: pitchColor, width: 1.2, x: t, y: pitch),
        ]
        let rb = robustBaseline(t, roll)
        let pb = robustBaseline(t, pitch)
        let vb = robustBaseline(t, vertical)
        var cand: [ChartsImuEvent] = []
        var cmk: [SyncMarker] = []
        for i in detect(t, roll, rb.median, threshold(rb.scale, tiltK, tiltFloorDeg)) {
            cand.append(ChartsImuEvent(id: 0, t: t[i], kind: "Balanceo", value: roll[i], deviation: abs(roll[i] - rb.median[i]), unit: "°"))
            cmk.append(SyncMarker(id: 0, x: t[i], y: roll[i], color: markerColor))
        }
        for i in detect(t, pitch, pb.median, threshold(pb.scale, tiltK, tiltFloorDeg)) {
            cand.append(ChartsImuEvent(id: 0, t: t[i], kind: "Cabeceo", value: pitch[i], deviation: abs(pitch[i] - pb.median[i]), unit: "°"))
            cmk.append(SyncMarker(id: 0, x: t[i], y: pitch[i], color: markerColor))
        }
        for i in detect(t, vertical, vb.median, threshold(vb.scale, verticalK, verticalFloorMs2)) {
            cand.append(ChartsImuEvent(id: 0, t: t[i], kind: "Vertical", value: vertical[i],
                                       deviation: abs(vertical[i] - vb.median[i]), unit: "m/s²"))
            // the vertical jump is drawn on the roll line (same instant) so the marker stays inside the chart in degrees
            cmk.append(SyncMarker(id: 0, x: t[i], y: roll[i].isFinite ? roll[i] : 0, color: Color(hex: 0xFF8A3D)))
        }
        // order by time, ids
        let order: [Int] = Array(0..<cand.count).sorted { (a: Int, b: Int) -> Bool in
            if cand[a].t != cand[b].t { return cand[a].t < cand[b].t }
            return a < b
        }
        var tev: [ChartsImuEvent] = []
        var tmk: [SyncMarker] = []
        for j in order {
            var e: ChartsImuEvent = cand[j]
            e.id = tev.count
            tev.append(e)
            var m: SyncMarker = cmk[j]
            m.id = tmk.count
            tmk.append(m)
        }
        r.tiltEvents = tev
        r.tiltMarkers = tmk
    }

    private static func threshold(_ scale: [Double], _ k: Double, _ floor: Double) -> [Double] {
        scale.map { (s: Double) -> Double in s.isFinite ? max(k * s, floor) : .nan }
    }

    // ------------------------------------------------------------------ robust statistics
    /// Median and σ_MAD (1.4826 · MAD) over a centred sliding window of `baselineWindowS`, evaluated per block of
    /// `baselineBlockS` (every sample of a block shares its block's values). Samples must be sorted by time.
    static func robustBaseline(_ t: [Double], _ y: [Double]) -> (median: [Double], scale: [Double]) {
        let n: Int = min(t.count, y.count)
        var med: [Double] = [Double](repeating: .nan, count: n)
        var sc: [Double] = [Double](repeating: .nan, count: n)
        if n == 0 { return (median: med, scale: sc) }
        // block boundaries
        var starts: [Int] = [0]
        var blockT0: Double = t[0]
        for i in 1..<max(n, 1) where t[i] - blockT0 >= baselineBlockS {
            starts.append(i)
            blockT0 = t[i]
        }
        let nb: Int = starts.count
        let half: Int = max(1, Int((baselineWindowS / 2 / baselineBlockS).rounded(.up)))
        for b in 0..<nb {
            let a0: Int = starts[max(0, b - half)]
            let a1: Int = (b + half + 1 < nb) ? starts[b + half + 1] : n
            let len: Int = a1 - a0
            let stride: Int = max(1, len / baselineMaxValues)
            var vals: [Double] = []
            vals.reserveCapacity(len / stride + 1)
            var i: Int = a0
            while i < a1 {
                if y[i].isFinite { vals.append(y[i]) }
                i += stride
            }
            if vals.count < 5 { continue }
            vals.sort()
            let m: Double = sortedMedian(vals)
            var dev: [Double] = vals.map { abs($0 - m) }
            dev.sort()
            let s: Double = 1.4826 * sortedMedian(dev)
            let e: Int = b + 1 < nb ? starts[b + 1] : n
            for j in starts[b]..<e {
                med[j] = m
                sc[j] = s
            }
        }
        return (median: med, scale: sc)
    }

    private static func sortedMedian(_ a: [Double]) -> Double {
        if a.isEmpty { return .nan }
        let c: Int = a.count
        return c % 2 == 1 ? a[c / 2] : (a[c / 2 - 1] + a[c / 2]) / 2
    }

    /// Indices of the peaks of the events where |y − median| > thr. Exceedances closer than `mergeGapS` are merged;
    /// at most `maxEvents` (largest deviations), returned in time order.
    static func detect(_ t: [Double], _ y: [Double], _ median: [Double], _ thr: [Double]) -> [Int] {
        let n: Int = min(t.count, y.count, median.count, thr.count)
        var peaks: [(i: Int, d: Double)] = []
        var curI: Int = -1
        var curD: Double = 0
        var lastT: Double = -Double.infinity
        for i in 0..<n {
            let v: Double = y[i]
            let m: Double = median[i]
            let th: Double = thr[i]
            guard v.isFinite && m.isFinite && th.isFinite else { continue }
            let d: Double = abs(v - m)
            if d <= th { continue }
            if curI >= 0 && t[i] - lastT > mergeGapS {
                peaks.append((i: curI, d: curD))
                curI = -1
            }
            if curI < 0 || d > curD { curI = i; curD = d }
            lastT = t[i]
        }
        if curI >= 0 { peaks.append((i: curI, d: curD)) }
        if peaks.count > maxEvents {
            peaks.sort { (a: (i: Int, d: Double), b: (i: Int, d: Double)) -> Bool in a.d > b.d }
            peaks = Array(peaks.prefix(maxEvents))
        }
        return peaks.map { $0.i }.sorted()
    }

    // ------------------------------------------------------------------ helpers
    /// Centred moving average over ±halfS seconds, ignoring NaN (NaN where the window has no finite value or the
    /// sample itself is NaN). Samples sorted by time.
    static func movingAverage(_ t: [Double], _ y: [Double], _ halfS: Double) -> [Double] {
        let n: Int = min(t.count, y.count)
        var out: [Double] = [Double](repeating: .nan, count: n)
        if n == 0 { return out }
        var pre: [Double] = [Double](repeating: 0, count: n + 1)
        var cnt: [Int] = [Int](repeating: 0, count: n + 1)
        for i in 0..<n {
            let f: Bool = y[i].isFinite
            pre[i + 1] = pre[i] + (f ? y[i] : 0)
            cnt[i + 1] = cnt[i] + (f ? 1 : 0)
        }
        var lo: Int = 0
        var hi: Int = 0
        for i in 0..<n {
            if !y[i].isFinite { continue }
            while lo < i && t[lo] < t[i] - halfS { lo += 1 }
            if hi < i { hi = i }
            while hi + 1 < n && t[hi + 1] <= t[i] + halfS { hi += 1 }
            let c: Int = cnt[hi + 1] - cnt[lo]
            if c > 0 { out[i] = (pre[hi + 1] - pre[lo]) / Double(c) }
        }
        return out
    }

    /// Removes the ±180° jumps of an angle series and shifts it so its median lies in (−180, 180].
    static func unwrapDegrees(_ a: [Double]) -> [Double] {
        var out: [Double] = a
        var shift: Double = 0
        var prev: Double = .nan
        for i in 0..<out.count {
            let v: Double = a[i]
            if !v.isFinite { continue }
            if prev.isFinite {
                let d: Double = v - prev
                if d > 180 { shift -= 360 } else if d < -180 { shift += 360 }
            }
            prev = v
            out[i] = v + shift
        }
        let m: Double = Stats.median(out)
        if m.isFinite {
            var k: Double = 0
            while m + k > 180 { k -= 360 }
            while m + k <= -180 { k += 360 }
            if k != 0 { out = out.map { $0 + k } }
        }
        return out
    }

    private static func wrapPi(_ a: Double) -> Double {
        var x: Double = a
        while x > Double.pi { x -= 2 * Double.pi }
        while x <= -Double.pi { x += 2 * Double.pi }
        return x
    }

    /// GNSS direction of travel (radians, counter-clockwise from east, local ENU) at every IMU time: central difference
    /// of positions (never across a gap) where the filtered speed is ≥ 2 m/s and the nearest GNSS sample is ≤ 1 s away.
    static func gnssCourseAt(_ tl: SessionTimeline, _ t: [Double]) -> [Double] {
        let m: Int = tl.count
        var out: [Double] = [Double](repeating: .nan, count: t.count)
        if m < 3 { return out }
        var course: [Double] = [Double](repeating: .nan, count: m)
        let mPerDeg: Double = 111_320.0
        for i in 1..<(m - 1) {
            if tl.breakBefore[i] || tl.breakBefore[i + 1] { continue }
            let v: Double = tl.speedFiltered[i]
            guard v.isFinite, v >= minHeadingSpeedMs else { continue }
            let la0: Double = tl.lat[i - 1], la1: Double = tl.lat[i + 1]
            let lo0: Double = tl.lon[i - 1], lo1: Double = tl.lon[i + 1]
            guard la0.isFinite, la1.isFinite, lo0.isFinite, lo1.isFinite else { continue }
            let dn: Double = (la1 - la0) * mPerDeg
            let de: Double = (lo1 - lo0) * mPerDeg * cos(tl.lat[i] * Double.pi / 180)
            if (dn * dn + de * de).squareRoot() < 0.3 { continue }
            course[i] = atan2(dn, de)
        }
        var j: Int = 0
        for k in 0..<t.count {
            let x: Double = t[k]
            while j + 1 < m && abs(tl.t[j + 1] - x) <= abs(tl.t[j] - x) { j += 1 }
            if abs(tl.t[j] - x) <= 1.0 { out[k] = course[j] }
        }
        return out
    }

    /// Offset between the GNSS course and the girth forward yaw (game frame), per sample: circular mean of
    /// (course − yaw) over ±`offsetHalfWindowS`. NaN where it cannot be estimated reliably.
    static func headingOffsets(_ t: [Double], _ course: [Double], _ yaw: [Double]) -> [Double] {
        let n: Int = t.count
        var out: [Double] = [Double](repeating: .nan, count: n)
        if n == 0 { return out }
        let t0: Double = t[0]
        let nb: Int = max(1, Int(((t[n - 1] - t0) / 1.0).rounded(.down)) + 1)
        var sc: [Double] = [Double](repeating: 0, count: nb)
        var ss: [Double] = [Double](repeating: 0, count: nb)
        var cn: [Int] = [Int](repeating: 0, count: nb)
        var any: Bool = false
        for i in 0..<n where course[i].isFinite && yaw[i].isFinite {
            let b: Int = min(nb - 1, max(0, Int((t[i] - t0).rounded(.down))))
            let d: Double = wrapPi(course[i] - yaw[i])
            sc[b] += cos(d); ss[b] += sin(d); cn[b] += 1
            any = true
        }
        if !any { return out }
        var pc: [Double] = [Double](repeating: 0, count: nb + 1)
        var ps: [Double] = [Double](repeating: 0, count: nb + 1)
        var pn: [Int] = [Int](repeating: 0, count: nb + 1)
        for b in 0..<nb { pc[b + 1] = pc[b] + sc[b]; ps[b + 1] = ps[b] + ss[b]; pn[b + 1] = pn[b] + cn[b] }
        let h: Int = Int(offsetHalfWindowS)
        var blockOffset: [Double] = [Double](repeating: .nan, count: nb)
        for b in 0..<nb {
            let a0: Int = max(0, b - h)
            let a1: Int = min(nb, b + h + 1)
            let c: Int = pn[a1] - pn[a0]
            if c < offsetMinSamples { continue }
            let x: Double = pc[a1] - pc[a0]
            let y: Double = ps[a1] - ps[a0]
            if (x * x + y * y).squareRoot() / Double(c) < offsetMinResultant { continue }
            blockOffset[b] = atan2(y, x)
        }
        for i in 0..<n {
            let b: Int = min(nb - 1, max(0, Int((t[i] - t0).rounded(.down))))
            out[i] = blockOffset[b]
        }
        return out
    }

    /// Value of a series at time `x` (nearest sample within 0.5 s), for the cursor readouts.
    static func valueAt(_ t: [Double], _ y: [Double], _ x: Double) -> Double {
        let n: Int = min(t.count, y.count)
        if n == 0 || !x.isFinite { return .nan }
        let i: Int = ChartsModel.lowerBound(t, x)
        var best: Int = -1
        var bd: Double = .infinity
        for k in [i - 1, i] where k >= 0 && k < n {
            let d: Double = abs(t[k] - x)
            if d < bd { bd = d; best = k }
        }
        return best >= 0 && bd <= 0.5 ? y[best] : .nan
    }
}
