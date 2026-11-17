import Foundation

// Port of windows/AVO.Windows.Core/Watch/Geofences.cs: plan of geofences and start/finish lines (geocercas.json, same
// keys and string enums as the C# JsonSerializer with JsonStringEnumConverter), crossing analysis with direction,
// authorization of this iPad on the watch (BOOT claim) and sending the plan with the watch's own messages.

enum LineRole: Int, CaseIterable {
    case startFinish = 0, start = 1, finish = 2, checkpoint = 3
    var jsonName: String {
        switch self {
        case .startFinish: return "StartFinish"
        case .start: return "Start"
        case .finish: return "Finish"
        case .checkpoint: return "Checkpoint"
        }
    }
}

/// Which crossings count. Seen from A towards B: leftToRight = crossing from the left side to the right side.
/// The watch counts BOTH directions (avo_session.cpp crosses()); the direction is applied by the app when it analyses the
/// recorded track. Making the watch itself ignore the other direction needs a firmware change (not done).
enum LineDirection: Int, CaseIterable {
    case both = 0, leftToRight = 1, rightToLeft = 2
    var jsonName: String {
        switch self {
        case .both: return "Both"
        case .leftToRight: return "LeftToRight"
        case .rightToLeft: return "RightToLeft"
        }
    }
}

/// Reads a C# enum serialised by JsonStringEnumConverter (name, case-insensitive) or as a number.
enum PlanJson {
    static func enumIndex(_ v: Any?, _ names: [String]) -> Int? {
        if let s = v as? String {
            for (i, n) in names.enumerated() where n.caseInsensitiveCompare(s) == .orderedSame { return i }
            return nil
        }
        if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.intValue }
        return nil
    }
    static func double(_ o: [String: Any], _ k: String) -> Double? { AvoJSON.number(o, k) }
}

final class PlanPoint {
    var lat: Double = 0
    var lon: Double = 0
    init() {}
    init(_ lat: Double, _ lon: Double) { self.lat = lat; self.lon = lon }
    var e7: GeoE7 { GeoE7.of(lat, lon) }

    func json() -> [String: Any] {
        let e = e7
        // C# also serialises the read-only E7 property (ignored when reading)
        let e7o: [String: Any] = ["LatE7": e.latE7, "LonE7": e.lonE7, "Lat": e.lat, "Lon": e.lon, "Valid": e.valid]
        return ["Lat": lat, "Lon": lon, "E7": e7o]
    }
    static func from(_ v: Any?) throws -> PlanPoint? {
        guard let v = v, !(v is NSNull) else { return nil }
        guard let o = v as? [String: Any] else { throw AvoError.invalidData("punto") }
        return PlanPoint(AvoJSON.number(o, "Lat") ?? 0, AvoJSON.number(o, "Lon") ?? 0)
    }
}

final class PlanFence {
    var name: String = ""
    var type: FenceType = .circle
    var center: PlanPoint? = nil
    var radiusM: Double = 50
    var vertices: [PlanPoint] = []
    var active: Bool = true

    init() {}
    init(name: String, type: FenceType = .circle, center: PlanPoint? = nil, radiusM: Double = 50, vertices: [PlanPoint] = [],
         active: Bool = true) {
        self.name = name; self.type = type; self.center = center; self.radiusM = radiusM; self.vertices = vertices; self.active = active
    }

    /// The fence exactly as it will be written to the watch slot.
    func toWatch(_ slot: Int) -> Fence {
        if type == .circle {
            let r = (radiusM * 100).rounded(.toNearestOrEven)
            return Fence(slot, .circle, name.trimmed, center: center?.e7 ?? .zero, radiusCm: r.isFinite ? Int64(r) : 0)
        }
        return Fence(slot, .polygon, name.trimmed, center: .zero, radiusCm: 0, vertices: vertices.map { $0.e7 })
    }

    func problem() -> String? {
        if name.trimmed.isEmpty { return "Pon un nombre" }
        if name.trimmed.utf8.count > 15 { return "Nombre: máximo 15 caracteres" }
        if type == .circle && center == nil { return "Toca el mapa para fijar el centro" }
        if type == .polygon && vertices.isEmpty { return "Toca el mapa para añadir vértices" }
        return toWatch(0).validate()
    }

    func json() -> [String: Any] {
        return [
            "Name": name, "Type": type.jsonName, "Center": center.map { $0.json() as Any } ?? NSNull(), "RadiusM": radiusM,
            "Vertices": vertices.map { $0.json() }, "Active": active,
        ]
    }
    static func from(_ v: Any?) throws -> PlanFence? {
        guard let v = v, !(v is NSNull) else { return nil }
        guard let o = v as? [String: Any] else { throw AvoError.invalidData("geocerca") }
        let f = PlanFence()
        f.name = AvoJSON.string(o, "Name") ?? ""
        if let t = o["Type"] {
            guard let i = PlanJson.enumIndex(t, ["None", "Circle", "Polygon"]), let ft = FenceType(rawValue: UInt8(truncatingIfNeeded: i)) else {
                throw AvoError.invalidData("tipo de geocerca")
            }
            f.type = ft
        }
        f.center = try PlanPoint.from(o["Center"])
        f.radiusM = AvoJSON.number(o, "RadiusM") ?? 50
        if let vs = o["Vertices"], !(vs is NSNull) {
            guard let arr = vs as? [Any] else { throw AvoError.invalidData("vértices") }
            var out: [PlanPoint] = []
            for x in arr { if let p = try PlanPoint.from(x) { out.append(p) } }
            f.vertices = out
        }
        f.active = AvoJSON.bool(o, "Active") ?? true
        return f
    }
}

final class PlanLine {
    var enabled: Bool = false
    var name: String = ""
    var role: LineRole = .startFinish
    var a: PlanPoint? = nil
    var b: PlanPoint? = nil
    var direction: LineDirection = .both

    init() {}
    init(enabled: Bool = false, name: String, role: LineRole = .startFinish, a: PlanPoint? = nil, b: PlanPoint? = nil,
         direction: LineDirection = .both) {
        self.enabled = enabled; self.name = name; self.role = role; self.a = a; self.b = b; self.direction = direction
    }

    func toWatch() -> VirtualLine {
        if enabled, let a = a, let b = b {
            return VirtualLine(enabled: true, aLatE7: a.e7.latE7, aLonE7: a.e7.lonE7, bLatE7: b.e7.latE7, bLonE7: b.e7.lonE7)
        }
        return VirtualLine(enabled: false, aLatE7: a?.e7.latE7 ?? 0, aLonE7: a?.e7.lonE7 ?? 0, bLatE7: b?.e7.latE7 ?? 0, bLonE7: b?.e7.lonE7 ?? 0)
    }

    var lengthM: Double {
        guard let a = a, let b = b else { return 0 }
        let p = LocalFrame(lat: a.lat, lon: a.lon).toXY(b.lat, b.lon)
        return (p.x * p.x + p.y * p.y).squareRoot()
    }

    func problem() -> String? {
        if !enabled { return nil }
        guard let a = a, let b = b else { return "Marca los dos extremos de la línea en el mapa" }
        if !a.e7.valid || !b.e7.valid { return "Extremos con coordenadas no válidas" }
        if lengthM < 2 { return "La línea es demasiado corta (mín. 2 m)" }
        if lengthM > 2000 { return "La línea es demasiado larga (máx. 2 km)" }
        return nil
    }

    func json() -> [String: Any] {
        return [
            "Enabled": enabled, "Name": name, "Role": role.jsonName, "A": a.map { $0.json() as Any } ?? NSNull(), "B": b.map { $0.json() as Any } ?? NSNull(),
            "Direction": direction.jsonName, "LengthM": lengthM,
        ]
    }
    static func from(_ v: Any?) throws -> PlanLine {
        guard let o = v as? [String: Any] else { throw AvoError.invalidData("línea") }
        let l = PlanLine()
        l.enabled = AvoJSON.bool(o, "Enabled") ?? false
        l.name = AvoJSON.string(o, "Name") ?? ""
        if let r = o["Role"] {
            guard let i = PlanJson.enumIndex(r, ["StartFinish", "Start", "Finish", "Checkpoint"]), let role = LineRole(rawValue: i) else {
                throw AvoError.invalidData("rol de línea")
            }
            l.role = role
        }
        l.a = try PlanPoint.from(o["A"])
        l.b = try PlanPoint.from(o["B"])
        if let d = o["Direction"] {
            guard let i = PlanJson.enumIndex(d, ["Both", "LeftToRight", "RightToLeft"]), let dir = LineDirection(rawValue: i) else {
                throw AvoError.invalidData("sentido de línea")
            }
            l.direction = dir
        }
        return l
    }
}

/// Geofences and lines prepared on the iPad (geocercas.json). Slots and indexes are the watch's: 8 fence slots (0–7), 4
/// virtual lines (0–3, line 0 is the one the watch uses to time laps). What is sent is exactly the watch format (SET_FENCE,
/// SET_ACTIVE_FENCES and the line sections of SET_CONFIG), the same messages the Android app sends.
final class GeofencePlan {
    var version: Int = 1
    var fences: [PlanFence?] = [PlanFence?](repeating: nil, count: Fence.maxFences)
    var autoEnabled: Bool = true
    var lines: [PlanLine] = GeofencePlan.defaultLines()
    var lastSent: Date? = nil
    var lastSentTo: String? = nil

    init() {}

    static func defaultLines() -> [PlanLine] {
        return [
            PlanLine(name: "Salida / meta", role: .startFinish),
            PlanLine(name: "Salida", role: .start),
            PlanLine(name: "Meta", role: .finish),
            PlanLine(name: "Control", role: .checkpoint),
        ]
    }

    var activeMask: Int {
        var m = 0
        for i in 0..<Fence.maxFences {
            if let f = fences[i], f.active { m |= 1 << i }
        }
        return m
    }

    func problems() -> [String] {
        var p: [String] = []
        for i in 0..<Fence.maxFences {
            if let e = fences[i]?.problem() { p.append("Geocerca \(i + 1): \(e)") }
        }
        for i in 0..<4 {
            if let e = lines[i].problem() { p.append("Línea \(i + 1) (\(lines[i].name)): \(e)") }
        }
        return p
    }

    static func load(_ path: String) -> GeofencePlan {
        guard let data = FileManager.default.contents(atPath: path) else { return GeofencePlan() }
        do {
            let p = try parse(data)
            while p.fences.count < Fence.maxFences { p.fences.append(nil) }
            if p.fences.count > Fence.maxFences { p.fences = Array(p.fences.prefix(Fence.maxFences)) }
            let def = GeofencePlan.defaultLines()
            while p.lines.count < 4 { p.lines.append(def[p.lines.count]) }
            if p.lines.count > 4 { p.lines = Array(p.lines.prefix(4)) }
            return p
        } catch {
            StableJson.keepDamaged(path)
            AppLog.current?.warn("geocercas", "geocercas.json dañado, se conserva una copia", error)
            return GeofencePlan()
        }
    }

    private static func parse(_ data: Data) throws -> GeofencePlan {
        var d = data
        if d.starts(with: [0xEF, 0xBB, 0xBF]) { d = d.dropFirst(3) }
        let any = try JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed])
        if any is NSNull { return GeofencePlan() }
        guard let o = any as? [String: Any] else { throw AvoError.invalidData("geocercas.json") }
        let p = GeofencePlan()
        if let v = AvoJSON.number(o, "Version") { p.version = Int(v) }
        if let fs = o["Fences"], !(fs is NSNull) {
            guard let arr = fs as? [Any] else { throw AvoError.invalidData("Fences") }
            var out: [PlanFence?] = []
            for x in arr { out.append(try PlanFence.from(x)) }
            p.fences = out
        }
        p.autoEnabled = AvoJSON.bool(o, "AutoEnabled") ?? true
        if let ls = o["Lines"], !(ls is NSNull) {
            guard let arr = ls as? [Any] else { throw AvoError.invalidData("Lines") }
            var out: [PlanLine] = []
            for x in arr { out.append(try PlanLine.from(x)) }
            p.lines = out
        }
        if let s = AvoJSON.string(o, "LastSent") { p.lastSent = StableJson.parseDate(s) }
        p.lastSentTo = AvoJSON.string(o, "LastSentTo")
        return p
    }

    func save(_ path: String) throws {
        let root: [String: Any] = [
            "Version": version,
            "Fences": fences.map { (f: PlanFence?) -> Any in f.map { $0.json() as Any } ?? NSNull() },
            "AutoEnabled": autoEnabled,
            "Lines": lines.map { $0.json() },
            "LastSent": lastSent.map { StableJson.date($0) as Any } ?? NSNull(),
            "LastSentTo": lastSentTo.map { $0 as Any } ?? NSNull(),
            "ActiveMask": activeMask,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]))
            ?? Data("{}".utf8)
        try StableJson.writeAtomic(data, to: path)
    }

    /// Takes what the watch has (to edit it on the iPad). Directions and roles stay as they were on the iPad.
    func loadFrom(_ c: WatchConfig) {
        for i in 0..<Fence.maxFences {
            let f: Fence? = i < c.fences.count ? c.fences[i] : nil
            guard let w = f, w.type != FenceType.none else { fences[i] = nil; continue }
            let pf = PlanFence()
            pf.name = w.name
            pf.type = w.type
            pf.active = (c.activeMask >> i) & 1 == 1
            pf.center = w.type == .circle ? PlanPoint(w.center.lat, w.center.lon) : nil
            pf.radiusM = Double(w.radiusCm) / 100.0
            pf.vertices = w.verts.map { PlanPoint($0.lat, $0.lon) }
            fences[i] = pf
        }
        autoEnabled = c.autoEnabled
        for i in 0..<4 {
            let l = c.lines[i]
            lines[i].enabled = l.enabled
            lines[i].a = l.aLatE7 != 0 || l.aLonE7 != 0 ? PlanPoint(l.a.lat, l.a.lon) : nil
            lines[i].b = l.bLatE7 != 0 || l.bLonE7 != 0 ? PlanPoint(l.b.lat, l.b.lon) : nil
        }
    }
}

/// A crossing of a line found in a recorded track.
struct LineCrossing: Equatable {
    var line: Int
    var t: Double
    var leftToRight: Bool
    var counts: Bool
    var lat: Double
    var lon: Double
}

/// What the crossing analysis needs from a timeline (C# SessionTimeline: Count, T, Lat, Lon, BreakBefore, JumpBefore).
protocol LineTimeline {
    var count: Int { get }
    var t: [Double] { get }
    var lat: [Double] { get }
    var lon: [Double] { get }
    var breakBefore: [Bool] { get }
    var jumpBefore: [Bool] { get }
}

extension SessionTimeline: LineTimeline {}

/// Plain arrays (tests, or any track without a SessionTimeline).
struct LineTrackData: LineTimeline {
    var t: [Double]
    var lat: [Double]
    var lon: [Double]
    var breakBefore: [Bool]
    var jumpBefore: [Bool]
    var count: Int { t.count }

    init(t: [Double], lat: [Double], lon: [Double], breakBefore: [Bool]? = nil, jumpBefore: [Bool]? = nil) {
        self.t = t; self.lat = lat; self.lon = lon
        self.breakBefore = breakBefore ?? [Bool](repeating: false, count: t.count)
        self.jumpBefore = jumpBefore ?? [Bool](repeating: false, count: t.count)
    }
}

/// Crossing analysis of a recorded GNSS track, with the same geometry test as the watch (avo_session.cpp crosses()).
enum LineAnalysis {
    /// Firmware test: P and Q on different sides of AB and the segment PQ crossing the segment AB. Returns (crosses, leftToRight).
    static func crosses(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ px: Double, _ py: Double, _ qx: Double,
                        _ qy: Double) -> (crosses: Bool, leftToRight: Bool) {
        let sp = (bx - ax) * (py - ay) - (by - ay) * (px - ax)
        let sq = (bx - ax) * (qy - ay) - (by - ay) * (qx - ax)
        let pPos = sp >= 0, qPos = sq >= 0
        let ltr = pPos && !qPos
        if pPos == qPos { return (false, ltr) }
        let sa = (qx - px) * (ay - py) - (qy - py) * (ax - px)
        let sb = (qx - px) * (by - py) - (qy - py) * (bx - px)
        return ((sa >= 0) != (sb >= 0) || sa == 0 || sb == 0, ltr)
    }

    static func detect(_ tl: LineTimeline, _ line: PlanLine, _ index: Int) -> [LineCrossing] {
        var r: [LineCrossing] = []
        guard let la = line.a, let lb = line.b, tl.count >= 2 else { return r }
        let T = tl.t, Lat = tl.lat, Lon = tl.lon, br = tl.breakBefore, jp = tl.jumpBefore
        let fr = LocalFrame(lat: la.lat, lon: la.lon)
        let a = fr.toXY(la.lat, la.lon)
        let b = fr.toXY(lb.lat, lb.lon)
        for i in 1..<tl.count {
            if (i < br.count && br[i]) || (i < jp.count && jp[i]) { continue }
            if !Lat[i - 1].isFinite || !Lat[i].isFinite { continue }
            let p = fr.toXY(Lat[i - 1], Lon[i - 1])
            let q = fr.toXY(Lat[i], Lon[i])
            let c = crosses(a.x, a.y, b.x, b.y, p.x, p.y, q.x, q.y)
            if !c.crosses { continue }
            // time at the crossing: fraction along PQ where it meets AB
            let dx = q.x - p.x, dy = q.y - p.y, ex = b.x - a.x, ey = b.y - a.y
            let den = dx * ey - dy * ex
            let f: Double = abs(den) > 1e-12 ? min(max(((a.x - p.x) * ey - (a.y - p.y) * ex) / den, 0), 1) : 0.5
            let t = T[i - 1] + f * (T[i] - T[i - 1])
            let counts = line.direction == .both || (line.direction == .leftToRight) == c.leftToRight
            r.append(LineCrossing(line: index, t: t, leftToRight: c.leftToRight, counts: counts,
                                  lat: Lat[i - 1] + f * (Lat[i] - Lat[i - 1]), lon: Lon[i - 1] + f * (Lon[i] - Lon[i - 1])))
        }
        return r
    }

    struct Run: Equatable {
        var kind: String
        var t0: Double
        var t1: Double
        var durationS: Double { t1 - t0 }
    }

    /// Laps between consecutive counting crossings of each start/finish line, and start → finish runs (first counting crossing
    /// of a Salida line, then the next counting crossing of a Meta line). Only counting crossings (right direction) are used.
    static func runs(_ lines: [PlanLine], _ crossings: [LineCrossing]) -> [Run] {
        var runs: [Run] = []
        let ok: [LineCrossing] = crossings.filter { $0.counts }.sorted { $0.t < $1.t }
        for i in 0..<lines.count where lines[i].role == .startFinish {
            let mine = ok.filter { $0.line == i }
            if mine.count >= 2 {
                for k in 1..<mine.count { runs.append(Run(kind: "Vuelta \(k) (\(lines[i].name))", t0: mine[k - 1].t, t1: mine[k].t)) }
            }
        }
        var start: Double? = nil
        var n = 0
        for c in ok {
            guard c.line >= 0 && c.line < lines.count else { continue }
            let role = lines[c.line].role
            if role == .start {
                start = c.t
            } else if role == .finish, let s = start {
                n += 1
                runs.append(Run(kind: "Salida → meta \(n)", t0: s, t1: c.t))
                start = nil
            }
        }
        return runs.sorted { $0.t0 < $1.t0 }
    }
}

/// Where credentials for each watch live (iPad: Keychain, see KeychainCredentialStore; tests: memory). Never in the repository.
protocol WatchCredentialStore: AnyObject {
    func get(_ deviceId: String) -> WatchCredential?
    func save(_ c: WatchCredential)
}

/// Authorization of this iPad on the watch with the same procedure as the Android app (key + BOOT-button claim).
enum WatchAuthorizer {
    static func ensure(_ c: AvoClient, _ store: WatchCredentialStore, clientName: String, progress: ((String) -> Void)? = nil,
                       claimWaitMs: Int = 65000, pollMs: Int = 1000) async throws -> WatchInfo {
        let info = try await c.getInfo()
        if !info.supportsAuth || info.authRequired == false { return info }
        if let cred = store.get(info.deviceId) {
            progress?("Comprobando la autorización de este iPad…")
            let o = try await c.authenticate(cred)
            if o == .ok { return info }
            if o == .watchNotAuthentic {
                throw BleRequestError(.verifyFailed, "El reloj no demostró conocer la clave (posible suplantación). No se envía nada.")
            }
            if o == .locked { throw BleRequestError(.busy, "Demasiados intentos de autorización; espera un minuto y vuelve a probar.") }
        }
        progress?("Este iPad no está autorizado en el reloj: pulsa BOOT en el reloj (tienes 60 s)…")
        let st = try await c.claimBegin(clientName)
        if st == .authRequired { throw BleRequestError(st, "El reloj exige emparejamiento Bluetooth antes de autorizar (vuelve a conectar).") }
        if st != .ok { throw BleRequestError(st, "El reloj no aceptó iniciar la autorización: " + BleStatusText.es(st)) }
        let until = Date().addingTimeInterval(Double(claimWaitMs) / 1000.0)
        while Date() < until {
            try await Task.sleep(nanoseconds: UInt64(max(0, pollMs)) * 1_000_000)
            let res = try await c.claimResult(info.deviceId)
            if res.status == .busy { continue }
            if res.status == .ok, let nc = res.credential {
                store.save(nc)
                let o = try await c.authenticate(nc)
                if o != .ok { throw BleRequestError(.authRequired, "Autorización recibida pero el reloj no la acepta: \(o)") }
                progress?("iPad autorizado en el reloj.")
                return info
            }
            if res.status == .timeout { throw BleRequestError(res.status, "No se pulsó BOOT a tiempo. Vuelve a intentarlo.") }
            throw BleRequestError(res.status, "Autorización fallida: " + BleStatusText.es(res.status))
        }
        throw BleRequestError(.timeout, "No se pulsó BOOT a tiempo. Vuelve a intentarlo.")
    }
}

struct SyncReport {
    var steps: [String]
    var verified: Bool
    var after: WatchConfig
}

/// Sends a plan with the watch's own messages and reads the configuration back to check it.
enum GeofenceSync {
    private static func body(_ f: Fence?, _ slot: Int) -> [UInt8] {
        let w = LeWriter()
        let use: Fence
        if let f = f, f.type != FenceType.none { use = f.withId(slot) } else { use = Fence.empty(slot) }
        use.encodeBody(w)
        return w.toArray()
    }

    static func sameFence(_ a: Fence?, _ b: Fence?, _ slot: Int) -> Bool {
        let ea = a == nil || a?.type == FenceType.none
        let eb = b == nil || b?.type == FenceType.none
        if ea || eb { return ea == eb }
        return body(a, slot) == body(b, slot)
    }

    static func sameLine(_ a: VirtualLine, _ b: VirtualLine) -> Bool {
        a.enabled == b.enabled && (!a.enabled || (a.aLatE7 == b.aLatE7 && a.aLonE7 == b.aLonE7 && a.bLatE7 == b.bLatE7 && a.bLonE7 == b.bLonE7))
    }

    /// Differences between the plan and a configuration (empty = the watch has exactly the plan).
    static func differences(_ plan: GeofencePlan, _ c: WatchConfig) -> [String] {
        var d: [String] = []
        for i in 0..<Fence.maxFences where !sameFence(plan.fences[i]?.toWatch(i), c.fences[i], i) { d.append("geocerca \(i + 1)") }
        if (c.activeMask & 0xFF) != plan.activeMask { d.append("geocercas activas") }
        if c.autoEnabled != plan.autoEnabled { d.append("grabación automática") }
        for i in 0..<4 where !sameLine(plan.lines[i].toWatch(), c.lines[i]) { d.append("línea \(i + 1)") }
        return d
    }

    static func send(_ c: AvoClient, _ plan: GeofencePlan, progress: ((String) -> Void)? = nil) async throws -> SyncReport {
        let problems = plan.problems()
        if !problems.isEmpty { throw AvoError.invalidOperation("No se envía: " + problems.joined(separator: "; ")) }
        var steps: [String] = []
        let cur = try WatchConfig.decode(try await c.getConfig())
        // 1. fences, one slot at a time (SET_FENCE: the watch validates with validate_fence())
        for i in 0..<Fence.maxFences {
            let want: Fence? = plan.fences[i]?.toWatch(i)
            if sameFence(want, cur.fences[i], i) { continue }
            if want == nil && (cur.fences[i] == nil || cur.fences[i]?.type == FenceType.none) { continue }
            progress?("Geocerca \(i + 1)…")
            let m = try await c.setFence((want ?? Fence.empty(i)).setFenceRequest(i))
            if m.statusEnum != .ok {
                throw BleRequestError(m.statusEnum, "El reloj rechazó la geocerca \(i + 1): \(BleStatusText.es(m.statusEnum))")
            }
            if let w = want { steps.append("Geocerca \(i + 1) «\(w.name)» enviada") } else { steps.append("Geocerca \(i + 1) borrada") }
        }
        // 2. active fences + automatic recording
        if (cur.activeMask & 0xFF) != plan.activeMask || cur.autoEnabled != plan.autoEnabled {
            progress?("Geocercas activas…")
            let st = try await c.setActiveFences(plan.activeMask, auto: plan.autoEnabled)
            if st != .ok { throw BleRequestError(st, "El reloj rechazó las geocercas activas: " + BleStatusText.es(st)) }
            steps.append("Geocercas activas actualizadas")
        }
        // 3. lines: read-modify-write of the whole configuration read NOW (so nothing else is overwritten)
        var now = try WatchConfig.decode(try await c.getConfig())
        let lines: [VirtualLine] = (0..<4).map { plan.lines[$0].toWatch() }
        if (0..<4).contains(where: { !sameLine(lines[$0], now.lines[$0]) }) {
            progress?("Líneas de salida y meta…")
            now.lines = lines
            let m = try await c.setConfig(now.encode())
            if m.statusEnum != .ok { throw BleRequestError(m.statusEnum, "El reloj rechazó las líneas: " + BleStatusText.es(m.statusEnum)) }
            steps.append("Líneas enviadas")
        }
        // 4. verification
        progress?("Comprobando lo que ha guardado el reloj…")
        let after = try WatchConfig.decode(try await c.getConfig())
        let diff = differences(plan, after)
        if steps.isEmpty { steps.append("El reloj ya tenía exactamente estas geocercas y líneas") }
        if !diff.isEmpty { steps.append("Diferencias tras enviar: " + diff.joined(separator: ", ")) }
        return SyncReport(steps: steps, verified: diff.isEmpty, after: after)
    }
}
