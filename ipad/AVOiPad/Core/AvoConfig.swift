import Foundation

// Port of windows/AVO.Windows.Core/Watch/AvoConfig.cs: geofence and AVOC configuration codecs, byte-exact with the chest
// firmware (avo_geo.h / avo_config.cpp) and the Android app (Fence.kt / WatchConfig.kt).
// C# FormatException → AvoError.invalidData(message).

enum FenceType: UInt8 {
    case none = 0
    case circle = 1
    case polygon = 2
    var jsonName: String {
        switch self {
        case .none: return "None"
        case .circle: return "Circle"
        case .polygon: return "Polygon"
        }
    }
    static func fromJson(_ s: String?) -> FenceType? {
        switch s {
        case "None": return FenceType.none
        case "Circle": return .circle
        case "Polygon": return .polygon
        default: return nil
        }
    }
}

struct GeoE7: Equatable, Hashable {
    var latE7: Int
    var lonE7: Int

    init(_ latE7: Int, _ lonE7: Int) { self.latE7 = latE7; self.lonE7 = lonE7 }
    init(latE7: Int, lonE7: Int) { self.latE7 = latE7; self.lonE7 = lonE7 }
    static let zero = GeoE7(0, 0)

    var lat: Double { Double(latE7) * 1e-7 }
    var lon: Double { Double(lonE7) * 1e-7 }
    /// C# (int)Math.Round(x * 1e7): banker's rounding.
    static func of(_ lat: Double, _ lon: Double) -> GeoE7 {
        GeoE7(GeoE7.round(lat * 1e7), GeoE7.round(lon * 1e7))
    }
    static func round(_ x: Double) -> Int {
        guard x.isFinite else { return 0 }
        let r = x.rounded(.toNearestOrEven)
        if r > Double(Int32.max) { return Int(Int32.max) }
        if r < Double(Int32.min) { return Int(Int32.min) }
        return Int(r)
    }
    var valid: Bool {
        latE7 >= -900000000 && latE7 <= 900000000 && lonE7 >= -1800000000 && lonE7 <= 1800000000 && !(latE7 == 0 && lonE7 == 0)
    }
}

/// Local equirectangular frame (avo_geo LocalFrame / Fence.kt LocalFrame), metres.
struct LocalFrame {
    static let r = 6371008.8
    static let deg = Double.pi / 180
    private let lat0: Double, lon0: Double, kx: Double, ky: Double

    init(_ g: GeoE7) {
        lat0 = g.lat
        lon0 = g.lon
        ky = LocalFrame.r * LocalFrame.deg
        kx = LocalFrame.r * LocalFrame.deg * cos(lat0 * LocalFrame.deg)
    }
    init(lat: Double, lon: Double) { self.init(GeoE7.of(lat, lon)) }

    func toXY(_ p: GeoE7) -> (x: Double, y: Double) { toXY(p.lat, p.lon) }
    func toXY(_ lat: Double, _ lon: Double) -> (x: Double, y: Double) {
        var dlon = lon - lon0
        if dlon > 180 { dlon -= 360 }
        if dlon < -180 { dlon += 360 }
        return (dlon * kx, (lat - lat0) * ky)
    }
    func toPoint(_ x: Double, _ y: Double) -> GeoE7 { GeoE7.of(lat0 + y / ky, lon0 + x / kx) }
}

/// Geofence exactly as the watch stores it (avo_geo.h FenceDef; Android Fence.kt).
struct Fence: Equatable {
    static let maxVertices = 24, maxFences = 8

    var id: Int
    var type: FenceType
    var name: String
    var center: GeoE7 = .zero
    var radiusCm: Int64 = 0
    var vertices: [GeoE7] = []

    init(_ id: Int, _ type: FenceType, _ name: String, center: GeoE7 = .zero, radiusCm: Int64 = 0, vertices: [GeoE7] = []) {
        self.id = id; self.type = type; self.name = name; self.center = center; self.radiusCm = radiusCm; self.vertices = vertices
    }

    var verts: [GeoE7] { vertices }

    func withId(_ slot: Int) -> Fence { var f = self; f.id = slot; return f }

    func encodeBody(_ w: LeWriter) {
        let n = min(verts.count, Fence.maxVertices)
        w.u8(id).u8(Int(type.rawValue)).str(name, 16).i32(center.latE7).i32(center.lonE7).u32(radiusCm).u8(n)
        for v in verts.prefix(Fence.maxVertices) { w.i32(v.latE7); w.i32(v.lonE7) }
    }

    /// SET_FENCE request: u8 slot + body.
    func setFenceRequest(_ slot: Int) -> [UInt8] {
        let w = LeWriter().u8(slot)
        withId(slot).encodeBody(w)
        return w.toArray()
    }

    static func decodeBody(_ r: LeReader) -> Fence? {
        let id = r.u8()
        let rawType = r.u8()
        let name = r.str(16)
        let c = GeoE7(r.i32(), r.i32())
        let radius = r.u32()
        let n = r.u8()
        if n > maxVertices { return nil }
        var v: [GeoE7] = []
        v.reserveCapacity(n)
        for _ in 0..<n { v.append(GeoE7(r.i32(), r.i32())) }
        let type: FenceType = FenceType(rawValue: UInt8(truncatingIfNeeded: rawType)) ?? FenceType.none
        return r.ok ? Fence(id, type, name, center: c, radiusCm: radius, vertices: v) : nil
    }

    static func empty(_ slot: Int) -> Fence { Fence(slot, FenceType.none, "") }

    /// Same checks and limits as validate_fence() in the firmware (and Fence.validate() in Android). nil = valid.
    func validate() -> String? {
        switch type {
        case .circle:
            if !center.valid { return "Centro no válido" }
            if radiusCm < 500 || radiusCm > 500000 { return "El radio debe estar entre 5 m y 5 km" }
            return nil
        case .polygon:
            if verts.count < 3 { return "Un polígono necesita al menos 3 vértices" }
            if verts.count > Fence.maxVertices { return "Máximo \(Fence.maxVertices) vértices" }
            if !verts.allSatisfy({ $0.valid }) { return "Hay vértices con coordenadas no válidas" }
            let fr = LocalFrame(verts[0])
            let xy: [(x: Double, y: Double)] = verts.map { fr.toXY($0) }
            if xy.contains(where: { abs($0.x) > 10000 || abs($0.y) > 10000 }) { return "La geocerca es demasiado grande (máx. 10 km)" }
            let n = xy.count
            for i in 0..<n {
                let i2 = (i + 1) % n
                var j = i + 1
                while j < n {
                    let j2 = (j + 1) % n
                    if !(j == i2 || j2 == i) {
                        if Geo2.segmentsIntersect(xy[i], xy[i2], xy[j], xy[j2]) { return "El polígono se corta a sí mismo" }
                    }
                    j += 1
                }
            }
            var a2 = 0.0
            for i in 0..<n {
                let j = (i + 1) % n
                a2 += xy[i].x * xy[j].y - xy[j].x * xy[i].y
            }
            if abs(a2) / 2 < 25.0 { return "El área es demasiado pequeña (mín. 25 m²)" }
            return nil
        case .none:
            return "Sin tipo"
        }
    }

    /// Signed distance (m) to the boundary, negative inside, as the watch computes it.
    func signedDistanceM(_ lat: Double, _ lon: Double) -> Double {
        if type == .circle {
            let p = LocalFrame(center).toXY(lat, lon)
            return (p.x * p.x + p.y * p.y).squareRoot() - Double(radiusCm) / 100.0
        }
        if type != .polygon || verts.count < 3 { return Double.greatestFiniteMagnitude }
        let fr = LocalFrame(verts[0])
        let xy: [(x: Double, y: Double)] = verts.map { fr.toXY($0) }
        let pp = fr.toXY(lat, lon)
        let px = pp.x, py = pp.y
        var inside = false
        var dmin = Double.greatestFiniteMagnitude
        var j = xy.count - 1
        for i in 0..<xy.count {
            let xi = xy[i].x, yi = xy[i].y, xj = xy[j].x, yj = xy[j].y
            if (yi > py) != (yj > py) && px < (xj - xi) * (py - yi) / (yj - yi) + xi { inside = !inside }
            dmin = min(dmin, Geo2.segDist(px, py, xj, yj, xi, yi))
            j = i
        }
        return inside ? -dmin : dmin
    }

    /// Circle approximated by a polygon (drawing only).
    func outline(_ n: Int = 72) -> [GeoE7] {
        if type == .polygon { return verts }
        let fr = LocalFrame(center)
        let r = Double(radiusCm) / 100.0
        var out: [GeoE7] = []
        for i in 0..<n {
            let a = 2 * Double.pi * Double(i) / Double(n)
            out.append(fr.toPoint(r * cos(a), r * sin(a)))
        }
        return out
    }
}

enum Geo2 {
    static func segDist(_ px: Double, _ py: Double, _ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Double {
        let vx = bx - ax, vy = by - ay, l2 = vx * vx + vy * vy
        var t = l2 > 0 ? ((px - ax) * vx + (py - ay) * vy) / l2 : 0
        t = min(max(t, 0), 1)
        let dx = px - (ax + t * vx), dy = py - (ay + t * vy)
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func orient(_ p: (x: Double, y: Double), _ q: (x: Double, y: Double), _ r: (x: Double, y: Double)) -> Int {
        let v = (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
        return abs(v) < 1e-12 ? 0 : (v > 0 ? 1 : -1)
    }
    private static func onSeg(_ p: (x: Double, y: Double), _ q: (x: Double, y: Double), _ r: (x: Double, y: Double)) -> Bool {
        return min(p.x, q.x) - 1e-9 <= r.x && r.x <= max(p.x, q.x) + 1e-9 && min(p.y, q.y) - 1e-9 <= r.y && r.y <= max(p.y, q.y) + 1e-9
    }

    static func segmentsIntersect(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double),
                                  _ c: (x: Double, y: Double), _ d: (x: Double, y: Double)) -> Bool {
        let o1 = orient(a, b, c), o2 = orient(a, b, d), o3 = orient(c, d, a), o4 = orient(c, d, b)
        if o1 != o2 && o3 != o4 { return true }
        return (o1 == 0 && onSeg(a, b, c)) || (o2 == 0 && onSeg(a, b, d)) || (o3 == 0 && onSeg(c, d, a)) || (o4 == 0 && onSeg(c, d, b))
    }
}

/// Virtual line of the watch (avo_config.h VirtualLine): the watch counts crossings in BOTH directions; line 0 also times laps.
struct VirtualLine: Equatable {
    var enabled: Bool = false
    var aLatE7: Int = 0
    var aLonE7: Int = 0
    var bLatE7: Int = 0
    var bLonE7: Int = 0

    init(enabled: Bool = false, aLatE7: Int = 0, aLonE7: Int = 0, bLatE7: Int = 0, bLonE7: Int = 0) {
        self.enabled = enabled; self.aLatE7 = aLatE7; self.aLonE7 = aLonE7; self.bLatE7 = bLatE7; self.bLonE7 = bLonE7
    }
    var a: GeoE7 { GeoE7(aLatE7, aLonE7) }
    var b: GeoE7 { GeoE7(bLatE7, bLonE7) }
}

enum ExitAction: UInt8 { case stopAndSave = 0, pause = 1, `continue` = 2 }

/// Section of the configuration this app does not know: written back untouched.
struct ConfigSection: Equatable {
    var tag: Int
    var body: [UInt8]
}

/// AVO CONFIG SCHEMA v1 — byte-exact port of avo_config.cpp (and Android WatchConfig.kt):
/// "AVOC" | u16 schema | u16 0 | u32 body_len | TLV sections | u32 CRC-32. Always edited read-modify-write: the iPad changes
/// only what the user touched; unknown sections are written back untouched.
struct WatchConfig: Equatable {
    static let schema = 1
    private static let tIdentity = 1, tGeoParam = 2, tFence = 3, tDisplay = 4, tRecording = 5, tBle = 6, tTraining = 7,
                       tLine = 8, tUart = 9, tPower = 10

    var deviceName: String = "AVO-CHEST"
    var horseId: Int64 = 0
    var horseName: String = ""
    var riderId: Int64 = 0
    var riderName: String = ""
    var autoEnabled: Bool = true
    var activeMask: Int = 0x01
    var entryConfirmS: Int = 5
    var exitConfirmS: Int = 15
    var entryMarginCm: Int64 = 500
    var exitMarginCm: Int64 = 1500
    var hAccMaxCm: Int64 = 1000
    var uncertaintyKx100: Int = 100
    /// Raw byte as stored by the watch (kept as is so unknown values survive a read-modify-write).
    var exitActionRaw: Int = 0
    var preS: Int = 30
    var postS: Int = 15
    var rearmTimeoutS: Int = 0
    var gnssLossMs: Int = 3000
    var resumeWindowS: Int = 300
    var fenceCount: Int = 0
    var fences: [Fence?] = [Fence?](repeating: nil, count: Fence.maxFences)
    var brightness: Int = 180
    var screenTimeoutS: Int = 30
    var dimOnLowBatt: Bool = true
    var flushMs: Int = 1000
    var fsyncMs: Int = 2000
    var segmentMb: Int = 512
    var nominalRateBps: Int64 = 32000
    var bleRequireBond: Bool = true
    var seriesSpeedCms: Int = 400
    var seriesMinS: Int = 10
    var lines: [VirtualLine] = [VirtualLine(), VirtualLine(), VirtualLine(), VirtualLine()]
    var uartBaud: Int64 = 921600
    var lowBattPct: Int = 15
    var criticalBattPct: Int = 5
    var criticalBattMv: Int = 3450
    var unknownSections: [ConfigSection] = []
    var newerSchema: Bool = false

    init() {}

    var exitAction: ExitAction {
        get { ExitAction(rawValue: UInt8(truncatingIfNeeded: exitActionRaw)) ?? .stopAndSave }
        set { exitActionRaw = Int(newValue.rawValue) }
    }

    static func decode(_ p: [UInt8]) throws -> WatchConfig {
        if p.count < 16 { throw AvoError.invalidData("configuración demasiado corta") }
        if p[0] != UInt8(ascii: "A") || p[1] != UInt8(ascii: "V") || p[2] != UInt8(ascii: "O") || p[3] != UInt8(ascii: "C") {
            throw AvoError.invalidData("magic incorrecto")
        }
        let schemaV = Int(p[4]) | Int(p[5]) << 8
        let body = Int64(p[8]) | Int64(p[9]) << 8 | Int64(p[10]) << 16 | Int64(p[11]) << 24
        if body + 16 != Int64(p.count) { throw AvoError.invalidData("longitud incorrecta") }
        let n = p.count
        let want = UInt32(p[n - 4]) | UInt32(p[n - 3]) << 8 | UInt32(p[n - 2]) << 16 | UInt32(p[n - 1]) << 24
        if crc32(p[0..<(n - 4)]) != want { throw AvoError.invalidData("CRC incorrecto") }
        var c = WatchConfig()
        var fences = [Fence?](repeating: nil, count: Fence.maxFences)
        var lines: [VirtualLine] = [VirtualLine(), VirtualLine(), VirtualLine(), VirtualLine()]
        var unknown: [ConfigSection] = []
        let r = LeReader(p, start: 12, end: 12 + Int(body))
        while r.remaining >= 4 {
            let tag = r.u16(), len = r.u16()
            if len > r.remaining { break }
            let sec = r.bytes(len)
            let s = LeReader(sec)
            switch tag {
            case tIdentity where len >= 76:
                c.deviceName = s.str(20); c.horseId = s.u32(); c.horseName = s.str(24); c.riderId = s.u32(); c.riderName = s.str(24)
            case tGeoParam where len >= 30:
                c.autoEnabled = s.u8() != 0
                c.activeMask = s.u8()
                c.entryConfirmS = s.u16()
                c.exitConfirmS = s.u16()
                c.entryMarginCm = s.u32()
                c.exitMarginCm = s.u32()
                c.hAccMaxCm = s.u32()
                c.uncertaintyKx100 = s.u16()
                c.exitActionRaw = s.u8()
                c.preS = s.u8()
                c.postS = s.u8()
                c.rearmTimeoutS = s.u16()
                c.gnssLossMs = s.u16()
                c.resumeWindowS = s.u16()
                c.fenceCount = s.u8()
            case tFence:
                let idx = s.u8()
                if let f = Fence.decodeBody(s), idx < Fence.maxFences { fences[idx] = f }
            case tDisplay where len >= 4:
                c.brightness = s.u8(); c.screenTimeoutS = s.u16(); c.dimOnLowBatt = s.u8() != 0
            case tRecording where len >= 10:
                c.flushMs = s.u16(); c.fsyncMs = s.u16(); c.segmentMb = s.u16(); c.nominalRateBps = s.u32()
            case tBle where len >= 1:
                c.bleRequireBond = s.u8() != 0
            case tTraining where len >= 4:
                c.seriesSpeedCms = s.u16(); c.seriesMinS = s.u16()
            case tLine:
                let i = s.u8()
                if i < 4 && s.remaining >= 17 {
                    let en = s.u8() != 0
                    let alat = s.i32(), alon = s.i32(), blat = s.i32(), blon = s.i32()
                    lines[i] = VirtualLine(enabled: en, aLatE7: alat, aLonE7: alon, bLatE7: blat, bLonE7: blon)
                }
            case tUart where len >= 4:
                c.uartBaud = s.u32()
            case tPower where len >= 4:
                c.lowBattPct = s.u8(); c.criticalBattPct = s.u8(); c.criticalBattMv = s.u16()
            case tIdentity, tGeoParam, tDisplay, tRecording, tBle, tTraining, tUart, tPower:
                break   // too short: defaults
            default:
                unknown.append(ConfigSection(tag: tag, body: sec))
            }
        }
        c.fences = fences
        c.lines = lines
        c.unknownSections = unknown
        c.newerSchema = schemaV > schema
        return c
    }

    func encode() -> [UInt8] {
        let w = LeWriter()
        w.bytes(Array("AVOC".utf8)).u16(WatchConfig.schema).u16(0).u32(0)
        func section(_ tag: Int, _ body: (LeWriter) -> Void) {
            let b = LeWriter()
            body(b)
            let bytes = b.toArray()
            w.u16(tag).u16(bytes.count).bytes(bytes)
        }
        section(WatchConfig.tIdentity) { s in
            s.str(deviceName, 20).u32(horseId).str(horseName, 24).u32(riderId).str(riderName, 24)
        }
        section(WatchConfig.tGeoParam) { s in
            s.u8(autoEnabled ? 1 : 0).u8(activeMask).u16(entryConfirmS).u16(exitConfirmS).u32(entryMarginCm).u32(exitMarginCm)
            s.u32(hAccMaxCm).u16(uncertaintyKx100).u8(exitActionRaw).u8(preS).u8(postS).u16(rearmTimeoutS).u16(gnssLossMs)
            s.u16(resumeWindowS).u8(fenceCount)
        }
        let nf = min(fenceCount, Fence.maxFences)
        if nf > 0 {
            for i in 0..<nf {
                let f: Fence = (i < fences.count ? fences[i] : nil) ?? Fence.empty(i)
                section(WatchConfig.tFence) { s in
                    s.u8(i)
                    f.encodeBody(s)
                }
            }
        }
        section(WatchConfig.tDisplay) { s in s.u8(brightness).u16(screenTimeoutS).u8(dimOnLowBatt ? 1 : 0) }
        section(WatchConfig.tRecording) { s in s.u16(flushMs).u16(fsyncMs).u16(segmentMb).u32(nominalRateBps) }
        section(WatchConfig.tBle) { s in s.u8(bleRequireBond ? 1 : 0) }
        section(WatchConfig.tTraining) { s in s.u16(seriesSpeedCms).u16(seriesMinS) }
        for i in 0..<4 {
            let l: VirtualLine = i < lines.count ? lines[i] : VirtualLine()
            section(WatchConfig.tLine) { s in
                s.u8(i).u8(l.enabled ? 1 : 0).i32(l.aLatE7).i32(l.aLonE7).i32(l.bLatE7).i32(l.bLonE7)
            }
        }
        section(WatchConfig.tUart) { s in s.u32(uartBaud) }
        section(WatchConfig.tPower) { s in s.u8(lowBattPct).u8(criticalBattPct).u16(criticalBattMv) }
        for u in unknownSections where u.tag < 1 || u.tag > 10 {
            w.u16(u.tag).u16(u.body.count).bytes(u.body)
        }
        var raw = w.toArray()
        let bodyLen = raw.count - 12
        for i in 0..<4 { raw[8 + i] = UInt8(truncatingIfNeeded: bodyLen >> (8 * i)) }
        let crc = WatchConfig.crc32(raw)
        for i in 0..<4 { raw.append(UInt8(truncatingIfNeeded: crc >> (8 * UInt32(i)))) }
        return raw
    }

    /// Same ranges as config_validate() in the firmware (Spanish list of problems).
    func problems() -> [String] {
        var p: [String] = []
        if entryConfirmS < 0 || entryConfirmS > 60 { p.append("Tiempo de entrada fuera de 0–60 s") }
        if exitConfirmS < 0 || exitConfirmS > 120 { p.append("Tiempo de salida fuera de 0–120 s") }
        if entryMarginCm < 0 || entryMarginCm > 10000 { p.append("Margen de entrada fuera de 0–100 m") }
        if exitMarginCm < 0 || exitMarginCm > 10000 { p.append("Margen de salida fuera de 0–100 m") }
        if hAccMaxCm < 50 || hAccMaxCm > 5000 { p.append("Precisión mínima fuera de 0,5–50 m") }
        if preS < 0 || preS > 60 { p.append("Pre-grabación fuera de 0–60 s") }
        if postS < 0 || postS > 60 { p.append("Post-grabación fuera de 0–60 s") }
        if brightness < 10 || brightness > 255 { p.append("Brillo fuera de 10–255") }
        if ![115200, 230400, 460800, 921600].contains(uartBaud) { p.append("Velocidad UART no admitida") }
        return p
    }

    /// CRC-32 (IEEE, reflected, poly 0xEDB88320), as ChestUsbClient.Crc32 / the firmware.
    static func crc32<S: Sequence>(_ data: S) -> UInt32 where S.Element == UInt8 {
        var crc: UInt32 = 0xFFFFFFFF
        for b in data {
            crc ^= UInt32(b)
            for _ in 0..<8 { crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1 }
        }
        return ~crc
    }
}
