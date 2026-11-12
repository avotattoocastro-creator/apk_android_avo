import Foundation

/// RGB colour as used by the Windows core (C# `(byte r, byte g, byte b)` tuples).
typealias AvoRGB = (r: UInt8, g: UInt8, b: UInt8)

/// Largest-Triangle-Three-Buckets reduction used ONLY for drawing. Calculations always use the full-resolution arrays.
/// NaN values split the series into runs; each run is reduced independently so gaps stay visible.
enum Downsampler {
    static func lttb(_ x: [Double], _ y: [Double], _ threshold: Int) -> [Int] {
        let n: Int = min(x.count, y.count)
        if threshold <= 2 || n <= threshold {
            var all: [Int] = []
            for i in 0..<n where y[i].isFinite && x[i].isFinite { all.append(i) }
            return all
        }
        var runs: [(a: Int, b: Int)] = []
        var s: Int = -1
        for i in 0...n {
            let ok: Bool = i < n && y[i].isFinite && x[i].isFinite
            if ok && s < 0 { s = i }
            else if !ok && s >= 0 { runs.append((a: s, b: i - 1)); s = -1 }
        }
        var finite: Int = 0
        for r in runs { finite += r.b - r.a + 1 }
        if finite == 0 { return [] }
        var result: [Int] = []
        result.reserveCapacity(threshold + runs.count * 2)
        for run in runs {
            let a: Int = run.a
            let b: Int = run.b
            let len: Int = b - a + 1
            let budget: Int = max(2, Int((Double(threshold) * Double(len) / Double(finite)).rounded(.toNearestOrEven)))
            if len <= budget {
                for i in a...b { result.append(i) }
                continue
            }
            result.append(a)
            let every: Double = Double(len - 2) / Double(budget - 2)
            var prev: Int = a
            for k in 0..<(budget - 2) {
                let rangeStart: Int = a + 1 + Int((Double(k) * every).rounded(.down))
                let rangeEnd: Int = min(a + 1 + Int((Double(k + 1) * every).rounded(.down)), b)
                let nextStart: Int = rangeEnd
                let nextEnd: Int = min(a + 1 + Int((Double(k + 2) * every).rounded(.down)), b + 1)
                var avgX: Double = 0
                var avgY: Double = 0
                var cnt: Int = 0
                var j: Int = nextStart
                while j < nextEnd { avgX += x[j]; avgY += y[j]; cnt += 1; j += 1 }
                if cnt == 0 { avgX = x[b]; avgY = y[b] } else { avgX /= Double(cnt); avgY /= Double(cnt) }
                var best: Double = -1
                var bestIdx: Int = rangeStart
                j = rangeStart
                while j < rangeEnd {
                    let area: Double = abs((x[prev] - avgX) * (y[j] - y[prev]) - (x[prev] - x[j]) * (avgY - y[prev]))
                    if area > best { best = area; bestIdx = j }
                    j += 1
                }
                result.append(bestIdx)
                prev = bestIdx
            }
            result.append(b)
        }
        return Array(Set(result)).sorted()
    }
}

/// Girth IMU series aligned to the GNSS timeline. Values stay in LSB; physical units only through the nominal
/// scale of the declared sensor (not calibrated, axis orientation not verified on the horse).
final class ImuTimeline {
    /// Nominal LSM6DS3TR-C / LSM6DSV16X configuration of girth REV B (girth_imu.cpp): ±8 g, ±2000 dps.
    static let nominalAccelGPerLsb: Double = 0.000244
    static let nominalGyroDpsPerLsb: Double = 0.070
    static let scaleNote: String = "Escala nominal del sensor (±8 g, ±2000 °/s) sin calibrar; orientación de ejes no verificada en el caballo."
    /// BNO085 fixed point declared by GIRTH 0.4.3+ (header byte 15 = 1): acc Q8 m/s², gyro Q9 rad/s.
    static let bno085AccelGPerLsb: Double = 1.0 / (256.0 * 9.80665)
    static let bno085GyroDpsPerLsb: Double = 180.0 / Double.pi / 512.0
    static let bno085ScaleNote: String = "Unidades declaradas por la cincha (BNO085: aceleración en m/s² Q8, giro en rad/s Q9), " +
        "calibración dinámica del propio sensor; orientación de ejes no verificada en el caballo."
    static func scaleNoteFor(_ units: UInt8) -> String { units == 1 ? bno085ScaleNote : scaleNote }

    /// Scale actually used for this session.
    private(set) var note: String = ImuTimeline.scaleNote
    private(set) var accelGPerLsb: Double = ImuTimeline.nominalAccelGPerLsb
    private(set) var gyroDpsPerLsb: Double = ImuTimeline.nominalGyroDpsPerLsb

    struct Channel {
        var imuId: UInt8
        var t: [Double]
        var ax: [Int16]
        var ay: [Int16]
        var az: [Int16]
        var gx: [Int16]
        var gy: [Int16]
        var gz: [Int16]
        var accelGPerLsb: Double = ImuTimeline.nominalAccelGPerLsb
        var gyroDpsPerLsb: Double = ImuTimeline.nominalGyroDpsPerLsb

        var name: String { ImuTimeline.sensorName(imuId) }

        func accelMagnitudeG() -> [Double] {
            var r: [Double] = [Double](repeating: 0, count: t.count)
            for i in 0..<r.count {
                let x: Double = Double(ax[i])
                let y: Double = Double(ay[i])
                let z: Double = Double(az[i])
                r[i] = (x * x + y * y + z * z).squareRoot() * accelGPerLsb
            }
            return r
        }
        /// axis: "x", "y" or anything else = z.
        func axisG(_ axis: Character) -> [Double] {
            let src: [Int16] = axis == "x" ? ax : (axis == "y" ? ay : az)
            let k: Double = accelGPerLsb
            return src.map { Double($0) * k }
        }
        func gyroDps(_ axis: Character) -> [Double] {
            let src: [Int16] = axis == "x" ? gx : (axis == "y" ? gy : gz)
            let k: Double = gyroDpsPerLsb
            return src.map { Double($0) * k }
        }
    }

    var channels: [Channel] = []

    /// Girth movement from the BNO085 fused output (IMU_SAMPLE fmt 1, GIRTH 0.4.x): linear acceleration (gravity
    /// removed) rotated to the world frame of the game rotation vector (Z up), and roll / pitch of the girth. The game
    /// rotation vector does not use the magnetometer, so the heading (yaw) drifts and is not shown.
    struct FusedChannel {
        var imuId: UInt8
        var t: [Double]
        var verticalMs2: [Double]
        var horizontalMs2: [Double]
        var rollDeg: [Double]
        var pitchDeg: [Double]
        var name: String { ImuTimeline.sensorName(imuId) }
    }
    var fused: [FusedChannel] = []

    /// One fused sample: lin = linear acceleration in sensor axes (Q8 m/s²), q = (i, j, k, real) in Q14.
    /// Returns world-up and horizontal linear acceleration (m/s²) and roll / pitch (degrees).
    static func fuse(_ lx: Int16, _ ly: Int16, _ lz: Int16, _ qi: Int16, _ qj: Int16, _ qk: Int16, _ qr: Int16)
        -> (up: Double, horizontal: Double, rollDeg: Double, pitchDeg: Double) {
        var x: Double = Double(qi) / 16384.0
        var y: Double = Double(qj) / 16384.0
        var z: Double = Double(qk) / 16384.0
        var w: Double = Double(qr) / 16384.0
        let n: Double = (x * x + y * y + z * z + w * w).squareRoot()
        if n < 1e-6 { return (up: .nan, horizontal: .nan, rollDeg: .nan, pitchDeg: .nan) }
        x /= n; y /= n; z /= n; w /= n
        let ax: Double = Double(lx) / 256.0
        let ay: Double = Double(ly) / 256.0
        let az: Double = Double(lz) / 256.0
        // v_world = R(q) · v_sensor
        let r00: Double = 1.0 - 2.0 * (y * y + z * z)
        let r01: Double = 2.0 * (x * y - z * w)
        let r02: Double = 2.0 * (x * z + y * w)
        let r10: Double = 2.0 * (x * y + z * w)
        let r11: Double = 1.0 - 2.0 * (x * x + z * z)
        let r12: Double = 2.0 * (y * z - x * w)
        let r20: Double = 2.0 * (x * z - y * w)
        let r21: Double = 2.0 * (y * z + x * w)
        let r22: Double = 1.0 - 2.0 * (x * x + y * y)
        let wx: Double = r00 * ax + r01 * ay + r02 * az
        let wy: Double = r10 * ax + r11 * ay + r12 * az
        let wz: Double = r20 * ax + r21 * ay + r22 * az
        let rollY: Double = 2.0 * (w * x + y * z)
        let rollX: Double = 1.0 - 2.0 * (x * x + y * y)
        let roll: Double = atan2(rollY, rollX) * 180.0 / Double.pi
        let sinPitch: Double = min(max(2.0 * (w * y - z * x), -1.0), 1.0)
        let pitch: Double = asin(sinPitch) * 180.0 / Double.pi
        return (up: wz, horizontal: (wx * wx + wy * wy).squareRoot(), rollDeg: roll, pitchDeg: pitch)
    }

    /// Chest-to-GNSS offset used (s): t_gnss = t_chest - offset. Median of (chest time - GNSS time) over GNSS records.
    private(set) var offsetS: Double = 0
    private(set) var aligned: Bool = false
    private(set) var sampleRateHz: Double = 0

    init() {}

    /// imu_id convention in avo_payloads.h: 0 central, 1 left, 2 right.
    static func sensorName(_ id: UInt8) -> String {
        switch id {
        case 0: return "Central"
        case 1: return "Izquierda"
        case 2: return "Derecha"
        default: return "IMU \(id)"
        }
    }

    static func build(_ s: TrainingSession, _ gnss: SessionTimeline, t0: Double = -Double.infinity, t1: Double = Double.infinity) -> ImuTimeline {
        var offset: Double = 0
        var isAligned: Bool = false
        if gnss.count > 0 {
            var diffs: [Double] = []
            for p in s.track where p.chestUs > 0 {
                diffs.append(Double(p.chestUs) / 1e6 - gnss.timeOfItow(p.gpsWeekMs))
            }
            if !diffs.isEmpty { offset = Stats.median(diffs); isAligned = true }
        }
        let bno: Bool = s.imuUnits == 1
        let tl = ImuTimeline()
        tl.offsetS = offset
        tl.aligned = isAligned
        tl.sampleRateHz = s.imuPeriodUs > 0 ? 1e6 / Double(s.imuPeriodUs) : 0
        tl.note = scaleNoteFor(s.imuUnits)
        tl.accelGPerLsb = bno ? bno085AccelGPerLsb : nominalAccelGPerLsb
        tl.gyroDpsPerLsb = bno ? bno085GyroDpsPerLsb : nominalGyroDpsPerLsb

        // raw (fmt 0): group by sensor, window, stable order by time
        let rawGroups: [UInt8: [ImuRawSample]] = Dictionary(grouping: s.imu, by: { $0.imuId })
        for key in rawGroups.keys.sorted() {
            let g: [ImuRawSample] = rawGroups[key] ?? []
            let inWindow: [ImuRawSample] = g.filter { $0.timeS - offset >= t0 && $0.timeS - offset <= t1 }
            let a: [ImuRawSample] = stableSortedByTime(inWindow, { $0.timeS })
            if a.isEmpty { continue }
            tl.channels.append(Channel(imuId: key, t: a.map { $0.timeS - offset }, ax: a.map { $0.ax }, ay: a.map { $0.ay },
                                       az: a.map { $0.az }, gx: a.map { $0.gx }, gy: a.map { $0.gy }, gz: a.map { $0.gz },
                                       accelGPerLsb: tl.accelGPerLsb, gyroDpsPerLsb: tl.gyroDpsPerLsb))
        }
        // fused (fmt 1)
        let fusedGroups: [UInt8: [ImuFusedSample]] = Dictionary(grouping: s.imuFused, by: { $0.imuId })
        for key in fusedGroups.keys.sorted() {
            let g: [ImuFusedSample] = fusedGroups[key] ?? []
            let inWindow: [ImuFusedSample] = g.filter { $0.timeS - offset >= t0 && $0.timeS - offset <= t1 }
            let a: [ImuFusedSample] = stableSortedByTime(inWindow, { $0.timeS })
            if a.isEmpty { continue }
            let n: Int = a.count
            var t: [Double] = [Double](repeating: 0, count: n)
            var up: [Double] = [Double](repeating: 0, count: n)
            var hz: [Double] = [Double](repeating: 0, count: n)
            var roll: [Double] = [Double](repeating: 0, count: n)
            var pitch: [Double] = [Double](repeating: 0, count: n)
            for i in 0..<n {
                let f: ImuFusedSample = a[i]
                t[i] = f.timeS - offset
                let r = fuse(f.lx, f.ly, f.lz, f.qi, f.qj, f.qk, f.qr)
                up[i] = r.up; hz[i] = r.horizontal; roll[i] = r.rollDeg; pitch[i] = r.pitchDeg
            }
            tl.fused.append(FusedChannel(imuId: key, t: t, verticalMs2: up, horizontalMs2: hz, rollDeg: roll, pitchDeg: pitch))
        }
        return tl
    }

    /// LINQ OrderBy (stable) by a time key.
    private static func stableSortedByTime<T>(_ items: [T], _ key: (T) -> Double) -> [T] {
        let idx: [Int] = Array(0..<items.count)
        let sortedIdx: [Int] = idx.sorted { (i: Int, j: Int) -> Bool in
            let a: Double = key(items[i])
            let b: Double = key(items[j])
            if a < b { return true }
            if b < a { return false }
            return i < j
        }
        return sortedIdx.map { items[$0] }
    }
}

/// Speed colour scale shared with Android (TrainingDetailScreen.kt): blue #2F6BFF → cyan #35D0E8 (0.33) →
/// yellow #FFC42C (0.66) → red #ED122A (1.0), linear RGB interpolation over f = clamp(v / vmax).
enum SpeedScale {
    private static let stops: [(f: Double, r: UInt8, g: UInt8, b: UInt8)] = [
        (f: 0.0, r: 0x2F, g: 0x6B, b: 0xFF), (f: 0.33, r: 0x35, g: 0xD0, b: 0xE8),
        (f: 0.66, r: 0xFF, g: 0xC4, b: 0x2C), (f: 1.0, r: 0xED, g: 0x12, b: 0x2A),
    ]

    private static func lerp(_ a: UInt8, _ b: UInt8, _ u: Double) -> UInt8 {
        DotNetFormat.byteRound(Double(a) + (Double(b) - Double(a)) * u)
    }

    static func color(_ value: Double, _ max: Double) -> AvoRGB {
        let f: Double = max > 0 && value.isFinite ? Swift.min(Swift.max(value / max, 0), 1) : 0
        for i in 1..<stops.count {
            if f <= stops[i].f {
                let a = stops[i - 1]
                let b = stops[i]
                let u: Double = (f - a.f) / (b.f - a.f)
                return (r: lerp(a.r, b.r, u), g: lerp(a.g, b.g, u), b: lerp(a.b, b.b, u))
            }
        }
        let last = stops[stops.count - 1]
        return (r: last.r, g: last.g, b: last.b)
    }

    /// Diverging scale for accelerations: blue (braking) → grey (0) → red (accelerating).
    static func diverging(_ value: Double, _ maxAbs: Double) -> AvoRGB {
        let f: Double = maxAbs > 0 && value.isFinite ? Swift.min(Swift.max(value / maxAbs, -1), 1) : 0
        let mid: AvoRGB = (r: 0x93, g: 0x94, b: 0x9B)
        let end: AvoRGB = f >= 0 ? (r: 0xED, g: 0x12, b: 0x2A) : (r: 0x3D, g: 0x9B, b: 0xFF)
        let u: Double = abs(f)
        return (r: lerp(mid.r, end.r, u), g: lerp(mid.g, end.g, u), b: lerp(mid.b, end.b, u))
    }

    /// Colours of the GNSS solution states (Android AvoColors.rtk).
    static func solution(_ s: GnssSolution) -> AvoRGB {
        switch s {
        case .rtkFix: return (r: 0x52, g: 0xDD, b: 0x40)
        case .rtkFloat: return (r: 0xFF, g: 0xC4, b: 0x2C)
        case .dgnss: return (r: 0x3D, g: 0x9B, b: 0xFF)
        case .autonomous: return (r: 0xC9, g: 0xCB, b: 0xD1)
        default: return (r: 0xFF, g: 0x39, b: 0x45)
        }
    }

    /// Gait colours of Android: stopped #6E6F76, walk #3D9BFF, trot #FFC42C, canter/gallop #ED122A.
    static func gait(_ code: Int) -> AvoRGB {
        switch code {
        case 0: return (r: 0x6E, g: 0x6F, b: 0x76)
        case 1: return (r: 0x3D, g: 0x9B, b: 0xFF)
        case 2: return (r: 0xFF, g: 0xC4, b: 0x2C)
        case 3: return (r: 0xED, g: 0x12, b: 0x2A)
        default: return (r: 0x93, g: 0x94, b: 0x9B)
        }
    }
}

/// Web Mercator (EPSG:3857) tile mathematics for the map control.
enum TileMath {
    static let tileSize: Int = 256

    /// Global pixel coordinates at a zoom level.
    static func latLonToPixel(_ lat: Double, _ lon: Double, _ zoom: Double) -> (x: Double, y: Double) {
        let scale: Double = Double(tileSize) * pow(2, zoom)
        let x: Double = (lon + 180.0) / 360.0 * scale
        let s: Double = sin(min(max(lat, -85.05112878), 85.05112878) * Double.pi / 180)
        let y: Double = (0.5 - log((1 + s) / (1 - s)) / (4 * Double.pi)) * scale
        return (x: x, y: y)
    }

    static func pixelToLatLon(_ x: Double, _ y: Double, _ zoom: Double) -> (lat: Double, lon: Double) {
        let scale: Double = Double(tileSize) * pow(2, zoom)
        let lon: Double = x / scale * 360.0 - 180.0
        let n: Double = Double.pi - 2 * Double.pi * y / scale
        let lat: Double = 180.0 / Double.pi * atan(sinh(n))
        return (lat: lat, lon: lon)
    }

    /// Metres per pixel at a latitude.
    static func metersPerPixel(_ lat: Double, _ zoom: Double) -> Double {
        cos(lat * Double.pi / 180) * 2 * Double.pi * 6378137 / (Double(tileSize) * pow(2, zoom))
    }

    /// Largest zoom (≤ maxZoom) at which the bounding box fits in the viewport with padding.
    static func fitZoom(_ minLat: Double, _ minLon: Double, _ maxLat: Double, _ maxLon: Double, _ width: Double, _ height: Double,
                        padding: Double = 40, maxZoom: Double = 19) -> Double {
        var z: Double = maxZoom
        while z >= 1 {
            let a = latLonToPixel(maxLat, minLon, z)
            let b = latLonToPixel(minLat, maxLon, z)
            if abs(b.x - a.x) <= width - 2 * padding && abs(b.y - a.y) <= height - 2 * padding { return z }
            z -= 0.25
        }
        return 1
    }
}
