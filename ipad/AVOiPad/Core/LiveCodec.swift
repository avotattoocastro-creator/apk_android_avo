import Foundation

// LIVE desde el servidor (Actualizaciones 1, 19/11/2026). El Android sube a Firebase (`live/{owner}/{sid}`) la TELEMETRY
// del pecho (2 Hz) y esta pantalla la muestra en directo. Formato LIVE1 = core/.../live/LiveCodec.kt (mismos vectores de
// prueba) y docs/LIVE_SERVIDOR.md:
//   muestra = t_ms,latE7,lonE7,speed_mm_s,dist_cm,fix,carr,hacc_mm,num_sv,session
//   last    = "LIVE1," + muestra          s/{n} = "LIVE1," + muestra(;muestra)*

struct LiveSample: Equatable {
    var tMs: Int64
    var latE7: Int32
    var lonE7: Int32
    var speedMmS: Int32
    var distCm: Int64
    var fix: Int
    var carr: Int
    var hAccMm: Int64
    var numSv: Int
    var session: Int

    var t: Double { Double(tMs) / 1000.0 }
    var lat: Double { Double(latE7) / 1e7 }
    var lon: Double { Double(lonE7) / 1e7 }
    var speedMs: Double { Double(speedMmS) / 1000.0 }
    var distanceM: Double { Double(distCm) / 100.0 }
    /// Posición utilizable: fix 2D/3D y coordenadas distintas de 0.
    var hasPosition: Bool { fix >= 2 && (latE7 != 0 || lonE7 != 0) }
    /// 0 sin solución, 1 autónomo, 3 RTK FLOAT, 4 RTK FIX (`carrSoln` de NAV-PVT: 1 FLOAT, 2 FIX).
    var solution: GnssSolution {
        if fix < 2 { return .none }
        if carr == 2 { return .rtkFix }
        if carr == 1 { return .rtkFloat }
        return .autonomous
    }
}

enum LiveCodec {
    static let prefix: String = "LIVE1,"
    static let fields: Int = 10

    static func fieldsText(_ s: LiveSample) -> String {
        "\(s.tMs),\(s.latE7),\(s.lonE7),\(s.speedMmS),\(s.distCm),\(s.fix),\(s.carr),\(s.hAccMm),\(s.numSv),\(s.session)"
    }

    static func encode(_ s: LiveSample) -> String { prefix + fieldsText(s) }

    static func encodeChunk(_ list: [LiveSample]) -> String { prefix + list.map { fieldsText($0) }.joined(separator: ";") }

    /// `last` o un bloque `s/{n}`. Las muestras mal formadas se descartan (nunca lanza).
    static func decode(_ text: String?) -> [LiveSample] {
        guard let text = text, text.hasPrefix(prefix) else { return [] }
        var out: [LiveSample] = []
        for part in text.dropFirst(prefix.count).split(separator: ";", omittingEmptySubsequences: true) {
            let f: [Substring] = part.split(separator: ",", omittingEmptySubsequences: false)
            if f.count != fields { continue }
            var n: [Int64] = []
            for x in f { guard let v = Int64(x) else { break }; n.append(v) }
            if n.count != fields { continue }
            guard let lat = Int32(exactly: n[1]), let lon = Int32(exactly: n[2]), let sp = Int32(exactly: n[3]) else { continue }
            out.append(LiveSample(tMs: n[0], latE7: lat, lonE7: lon, speedMmS: sp, distCm: n[4], fix: Int(n[5]), carr: Int(n[6]),
                                  hAccMm: n[7], numSv: Int(n[8]), session: Int(n[9])))
        }
        return out
    }
}

/// Ficha de una sesión en directo (`live/{owner}/{sid}/meta`).
struct LiveMeta: Equatable {
    var horseName: String = ""
    var riderName: String = ""
    var breed: String = ""
    var startMs: Int64 = 0
    var state: String = ""
    var updatedMs: Int64 = 0
    var expiresMs: Int64 = 0

    init() {}

    init(json: [String: Any]) {
        horseName = json["horseName"] as? String ?? ""
        riderName = json["riderName"] as? String ?? ""
        breed = json["breed"] as? String ?? ""
        startMs = LiveMeta.int(json["startMs"])
        state = json["state"] as? String ?? ""
        updatedMs = LiveMeta.int(json["updatedMs"])
        expiresMs = LiveMeta.int(json["expiresMs"])
    }

    static func int(_ v: Any?) -> Int64 {
        if let n = v as? NSNumber { return n.int64Value }
        if let s = v as? String, let n = Int64(s) { return n }
        return 0
    }

    var isEnded: Bool { state == "END" }
    var stateText: String {
        switch state {
        case "IDLE": return "EN ESPERA"
        case "REC": return "GRABANDO"
        case "PAUSE": return "EN PAUSA"
        case "END": return "TERMINADA"
        default: return "—"
        }
    }
}

/// Estado completo de una sesión en directo reconstruido de los eventos del servidor (put/patch de Firebase).
/// Puro (sin red): se prueba con eventos de ejemplo.
struct LiveSessionState {
    var meta: LiveMeta = LiveMeta()
    var chunks: [Int: [LiveSample]] = [:]
    var last: LiveSample? = nil

    /// Todas las muestras ordenadas por tiempo, sin duplicados (bloques + la última si es más nueva).
    var samples: [LiveSample] {
        var all: [LiveSample] = chunks.keys.sorted().flatMap { chunks[$0] ?? [] }
        if let l = last, (all.last?.tMs ?? -1) < l.tMs { all.append(l) }
        var out: [LiveSample] = []
        out.reserveCapacity(all.count)
        for s in all where (out.last?.tMs ?? -1) < s.tMs { out.append(s) }
        return out
    }

    /// Aplica un evento `put` o `patch` del flujo de Firebase en `path` (relativo a la sesión).
    mutating func apply(event: String, path: String, data: Any?) {
        let parts: [String] = path.split(separator: "/").map(String.init)
        if event == "put" && parts.isEmpty {
            self = LiveSessionState()
            if let d = data as? [String: Any] { merge(d) }
            return
        }
        if event == "patch" {
            if let d = data as? [String: Any] {
                for (k, v) in d { apply(event: "put", path: path + "/" + k, data: v) }
            }
            return
        }
        // put en una ruta concreta
        switch parts.first ?? "" {
        case "last":
            last = (data as? String).flatMap { LiveCodec.decode($0).last }
        case "meta":
            if parts.count == 1 {
                meta = LiveMeta(json: data as? [String: Any] ?? [:])
            } else {
                var j: [String: Any] = [:]
                j["horseName"] = meta.horseName; j["riderName"] = meta.riderName; j["breed"] = meta.breed
                j["startMs"] = NSNumber(value: meta.startMs); j["state"] = meta.state
                j["updatedMs"] = NSNumber(value: meta.updatedMs); j["expiresMs"] = NSNumber(value: meta.expiresMs)
                j[parts[1]] = data
                meta = LiveMeta(json: j)
            }
        case "s":
            if parts.count == 1 {
                chunks = [:]
                mergeChunks(data)
            } else if let i = Int(parts[1]) {
                if let text = data as? String { chunks[i] = LiveCodec.decode(text) } else { chunks.removeValue(forKey: i) }
            }
        default:
            break
        }
    }

    private mutating func merge(_ d: [String: Any]) {
        if let m = d["meta"] as? [String: Any] { meta = LiveMeta(json: m) }
        if let l = d["last"] as? String { last = LiveCodec.decode(l).last }
        mergeChunks(d["s"])
    }

    /// Firebase devuelve los bloques como diccionario {"0": …} o como lista [ … ] si las claves son 0…n.
    private mutating func mergeChunks(_ v: Any?) {
        if let dict = v as? [String: Any] {
            for (k, x) in dict { if let i = Int(k), let text = x as? String { chunks[i] = LiveCodec.decode(text) } }
        } else if let arr = v as? [Any] {
            for (i, x) in arr.enumerated() { if let text = x as? String { chunks[i] = LiveCodec.decode(text) } }
        }
    }
}

/// Aire por velocidad (directo): umbrales genéricos con histéresis, porque en directo no hay IMU de la cincha.
/// Paso < 8 km/h · trote 8–20 · galope 20–45 · rápido > 45 km/h. Solo orientativo (el análisis completo lo hace el motor).
enum LiveGait: String {
    case stopped = "PARADO", walk = "PASO", trot = "TROTE", canter = "GALOPE", fast = "RÁPIDO"

    static func of(speedMs v: Double) -> LiveGait {
        let k: Double = v * 3.6
        if k < 1.5 { return .stopped }
        if k < 8 { return .walk }
        if k < 20 { return .trot }
        if k < 45 { return .canter }
        return .fast
    }
}

/// Series derivadas para la pantalla LIVE (velocidad suavizada, aceleración longitudinal y aire con su tramo actual).
struct LiveSeries {
    var t: [Double] = []
    var speedKmh: [Double] = []
    var accel: [Double] = []
    var gait: LiveGait = .stopped
    var gaitSince: Double = 0
    var gaitStartDistanceM: Double = 0

    static func build(_ s: [LiveSample]) -> LiveSeries {
        var r = LiveSeries()
        guard !s.isEmpty else { return r }
        let n: Int = s.count
        r.t = s.map { $0.t }
        // media móvil de 3 muestras (1,5 s a 2 Hz) para la velocidad
        var v: [Double] = s.map { $0.speedMs }
        if n >= 3 {
            var sm: [Double] = v
            for i in 1..<(n - 1) { sm[i] = (v[i - 1] + v[i] + v[i + 1]) / 3.0 }
            v = sm
        }
        r.speedKmh = v.map { $0 * 3.6 }
        // aceleración longitudinal = dv/dt sobre ±1 muestra, limitada a ±10 m/s² (cortes del enlace)
        var a: [Double] = Array(repeating: 0, count: n)
        if n >= 2 {
            for i in 0..<n {
                let i0: Int = max(0, i - 1), i1: Int = min(n - 1, i + 1)
                let dt: Double = r.t[i1] - r.t[i0]
                a[i] = dt > 0.2 && dt < 5 ? max(-10, min(10, (v[i1] - v[i0]) / dt)) : 0
            }
        }
        r.accel = a
        // aire actual: cambia cuando la banda nueva se mantiene ≥ 3 s
        var cur: LiveGait = LiveGait.of(speedMs: v[0])
        var since: Double = r.t[0]
        var sinceD: Double = s[0].distanceM
        var cand: LiveGait = cur
        var candT: Double = r.t[0]
        var candD: Double = s[0].distanceM
        for i in 1..<n {
            let g: LiveGait = LiveGait.of(speedMs: v[i])
            if g == cur { cand = cur; continue }
            if g != cand { cand = g; candT = r.t[i]; candD = s[i].distanceM }
            if r.t[i] - candT >= 3 { cur = cand; since = candT; sinceD = candD }
        }
        r.gait = cur
        r.gaitSince = since
        r.gaitStartDistanceM = sinceD
        return r
    }
}
