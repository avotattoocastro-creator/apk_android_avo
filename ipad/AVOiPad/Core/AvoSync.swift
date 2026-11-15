import Foundation

// AVO SYNC v1: hora GPS para el vídeo del iPad (docs/AVO_SYNC.md).
// Un gadget BLE (GPS con PPS + ESP32-C3) da la hora UTC de los satélites; el iPad hace un intercambio tipo NTP cada
// segundo y guarda el desfase entre su reloj de alta resolución (mach_absolute_time, el mismo que usan los fotogramas de
// AVCaptureSession) y la hora GPS. El protocolo es NUEVO e independiente: no toca TELEMETRY v3, BackStatus v3, los lotes
// de la cincha, AVO1 ni .avr.
//
// Todo este archivo es lógica pura (sin CoreBluetooth ni AVFoundation) para poder probarlo en AVOiPadTests.

// MARK: - Reloj del iPad

/// Reloj de alta resolución del iPad en nanosegundos (dominio de `mach_absolute_time` y de `CMClockGetHostTimeClock`).
enum AvoHostClock {
    private static let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(max(info.numer, 1)), UInt64(max(info.denom, 1)))
    }()

    static func ticksToNs(_ ticks: UInt64) -> Int64 {
        Int64(bitPattern: ticks / timebase.denom * timebase.numer + (ticks % timebase.denom) * timebase.numer / timebase.denom)
    }

    static func nowNs() -> Int64 { ticksToNs(mach_absolute_time()) }

    /// Hora del sistema (Unix, ns). iOS la mantiene con NTP: sirve de reserva cuando no hay gadget (decenas de ms (E)).
    static func unixNowNs() -> Int64 { Int64((Date().timeIntervalSince1970 * 1e9).rounded()) }
}

// MARK: - Protocolo BLE AVO SYNC v1

enum AvoSyncProtocol {
    /// UUID del servicio GATT de AVO SYNC (generados el 15/11/2026; el firmware del gadget debe usar los mismos).
    static let serviceUUID = "09F575BC-1C6E-451D-8257-4EBF6B42E3CB"
    /// RX: escritura sin respuesta, del iPad al gadget.
    static let rxUUID = "F89FCE07-E7A8-4527-AF87-5320C18F48FD"
    /// TX: notificaciones, del gadget al iPad.
    static let txUUID = "0C80602B-9074-40F3-94B0-B99E280303A2"
    static let version: UInt8 = 1

    enum FrameType: UInt8 {
        case timeReq = 1, timeResp = 2, mark = 3, status = 4
    }

    /// Bits de `flags` en TIME_RESP y STATUS.
    struct Flags: OptionSet, Equatable {
        let rawValue: UInt8
        static let fix = Flags(rawValue: 1 << 0)
        static let timeValid = Flags(rawValue: 1 << 1)
        static let ppsLocked = Flags(rawValue: 1 << 2)
        static let holdover = Flags(rawValue: 1 << 3)
    }

    enum MarkKind: UInt16, Codable {
        case series = 1, lap = 2, end = 3
        var title: String {
            switch self {
            case .series: return "Inicio de serie"
            case .lap: return "Vuelta"
            case .end: return "Fin"
            }
        }
    }

    struct TimeResponse: Equatable {
        var seq: UInt16
        var flags: Flags
        var satellites: UInt8
        var t1HostNs: Int64
        var t2UtcNs: Int64
        var t3UtcNs: Int64
    }

    struct Mark: Equatable {
        var seq: UInt16
        var kind: UInt16
        var utcNs: Int64
    }

    struct Status: Equatable {
        var batteryMv: UInt16
        var batteryPercent: UInt8
        /// Tipo de fix del GPS (0 sin fix, 2 2D, 3 3D…).
        var fix: UInt8
        var satellites: UInt8
        var flags: Flags
        var hAccMm: UInt32
        var uptimeS: UInt32
    }

    enum Frame: Equatable {
        case timeResponse(TimeResponse)
        case mark(Mark)
        case status(Status)
    }

    /// TIME_REQ (16 B): ver u8 · tipo u8 · seq u16 · rsv u32 · t1_ns u64.
    static func encodeTimeRequest(seq: UInt16, t1HostNs: Int64) -> Data {
        var d = Data(capacity: 16)
        d.append(version)
        d.append(FrameType.timeReq.rawValue)
        d.appendLE(seq)
        d.appendLE(UInt32(0))
        d.appendLE(UInt64(bitPattern: t1HostNs))
        return d
    }

    /// Decodifica una notificación del gadget. nil si la versión, el tipo o el tamaño no son los de v1.
    static func decode(_ data: Data) -> Frame? {
        let b = [UInt8](data)
        guard b.count >= 2, b[0] == version, let type = FrameType(rawValue: b[1]) else { return nil }
        switch type {
        case .timeResp:
            guard b.count == 32 else { return nil }
            return .timeResponse(TimeResponse(seq: b.u16(2), flags: Flags(rawValue: b[4]), satellites: b[5],
                                              t1HostNs: Int64(bitPattern: b.u64(8)),
                                              t2UtcNs: Int64(bitPattern: b.u64(16)),
                                              t3UtcNs: Int64(bitPattern: b.u64(24))))
        case .mark:
            guard b.count == 16 else { return nil }
            return .mark(Mark(seq: b.u16(2), kind: b.u16(4), utcNs: Int64(bitPattern: b.u64(8))))
        case .status:
            guard b.count == 16 else { return nil }
            return .status(Status(batteryMv: b.u16(2), batteryPercent: b[4], fix: b[5], satellites: b[6],
                                  flags: Flags(rawValue: b[7]), hAccMm: b.u32(8), uptimeS: b.u32(12)))
        case .timeReq:
            return nil
        }
    }

    // Codificadores del lado del gadget: solo para pruebas y para el simulador de la app.
    static func encodeTimeResponse(_ r: TimeResponse) -> Data {
        var d = Data(capacity: 32)
        d.append(version); d.append(FrameType.timeResp.rawValue); d.appendLE(r.seq)
        d.append(r.flags.rawValue); d.append(r.satellites); d.appendLE(UInt16(0))
        d.appendLE(UInt64(bitPattern: r.t1HostNs)); d.appendLE(UInt64(bitPattern: r.t2UtcNs)); d.appendLE(UInt64(bitPattern: r.t3UtcNs))
        return d
    }

    static func encodeMark(_ m: Mark) -> Data {
        var d = Data(capacity: 16)
        d.append(version); d.append(FrameType.mark.rawValue); d.appendLE(m.seq); d.appendLE(m.kind); d.appendLE(UInt16(0))
        d.appendLE(UInt64(bitPattern: m.utcNs))
        return d
    }

    static func encodeStatus(_ s: Status) -> Data {
        var d = Data(capacity: 16)
        d.append(version); d.append(FrameType.status.rawValue); d.appendLE(s.batteryMv); d.append(s.batteryPercent)
        d.append(s.fix); d.append(s.satellites); d.append(s.flags.rawValue); d.appendLE(s.hAccMm); d.appendLE(s.uptimeS)
        return d
    }
}

extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ v: T) {
        var le = v.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
}

private extension Array where Element == UInt8 {
    func u16(_ i: Int) -> UInt16 { UInt16(self[i]) | UInt16(self[i + 1]) << 8 }
    func u32(_ i: Int) -> UInt32 { (0..<4).reduce(UInt32(0)) { $0 | UInt32(self[i + $1]) << (8 * UInt32($1)) } }
    func u64(_ i: Int) -> UInt64 { (0..<8).reduce(UInt64(0)) { $0 | UInt64(self[i + $1]) << (8 * UInt64($1)) } }
}

// MARK: - Estimación del desfase reloj del iPad → hora GPS

/// Una muestra del intercambio tipo NTP. `offset` = UTC − reloj del iPad.
struct AvoSyncSample: Codable, Equatable {
    var hostNs: Int64
    var offsetNs: Int64
    var delayNs: Int64

    enum CodingKeys: String, CodingKey {
        case hostNs = "host_ns", offsetNs = "offset_ns", delayNs = "delay_ns"
    }

    /// t1 y t4 en el reloj del iPad; t2 y t3 en UTC del gadget.
    init(t1: Int64, t2: Int64, t3: Int64, t4: Int64) {
        offsetNs = ((t2 - t1) + (t3 - t4)) / 2
        delayNs = (t4 - t1) - (t3 - t2)
        hostNs = t1 + (t4 - t1) / 2
    }

    init(hostNs: Int64, offsetNs: Int64, delayNs: Int64) {
        self.hostNs = hostNs
        self.offsetNs = offsetNs
        self.delayNs = delayNs
    }
}

/// Recta `offset(host) = offsetAtRef + slope · (host − refHost)` que absorbe la deriva del reloj del iPad.
struct AvoSyncFit: Codable, Equatable {
    var refHostNs: Int64
    var offsetAtRefNs: Int64
    /// Deriva relativa (adimensional; 1e-6 = 1 ppm).
    var slope: Double

    enum CodingKeys: String, CodingKey {
        case refHostNs = "ref_host_ns", offsetAtRefNs = "offset_at_ref_ns", slope
    }

    func offset(atHostNs h: Int64) -> Int64 {
        offsetAtRefNs + Int64((slope * Double(h - refHostNs)).rounded())
    }

    func utcNs(hostNs h: Int64) -> Int64 { h + offset(atHostNs: h) }
}

/// Filtro de menor retardo por ventanas + recta por mínimos cuadrados (docs/AVO_SYNC.md §4.2).
struct AvoSyncEstimator {
    /// Duración de cada ventana: de cada una se queda la muestra de menor retardo.
    var windowNs: Int64 = 10_000_000_000
    /// Ventanas que entran en la recta (30 × 10 s = 5 min).
    var maxWindows: Int = 30
    /// Muestras con más retardo que esto se descartan (BLE muy cargado).
    var maxDelayNs: Int64 = 250_000_000

    private(set) var windows: [AvoSyncSample] = []
    private(set) var current: AvoSyncSample? = nil
    private(set) var accepted: Int = 0
    private(set) var rejected: Int = 0

    init() {}

    mutating func reset() {
        windows.removeAll(); current = nil; accepted = 0; rejected = 0
    }

    mutating func add(_ s: AvoSyncSample) {
        guard s.delayNs >= 0, s.delayNs <= maxDelayNs else { rejected += 1; return }
        accepted += 1
        if let c = current, c.hostNs / windowNs != s.hostNs / windowNs {
            windows.append(c)
            if windows.count > maxWindows { windows.removeFirst(windows.count - maxWindows) }
            current = s
        } else if let c = current {
            if s.delayNs < c.delayNs { current = s }
        } else {
            current = s
        }
    }

    /// Muestras usadas: los mínimos de las ventanas cerradas y la mejor de la ventana en curso.
    var points: [AvoSyncSample] {
        var p = windows
        if let c = current { p.append(c) }
        return p
    }

    var hasEstimate: Bool { !points.isEmpty }

    /// Recta de ajuste. Con una sola muestra, desfase constante.
    var fit: AvoSyncFit? {
        let p = points
        guard let last = p.last else { return nil }
        if p.count < 3 { return AvoSyncFit(refHostNs: last.hostNs, offsetAtRefNs: last.offsetNs, slope: 0) }
        let ref = last.hostNs
        let base = p.map { $0.offsetNs }.min() ?? 0
        let xs = p.map { Double($0.hostNs - ref) }
        let ys = p.map { Double($0.offsetNs - base) }
        let n = Double(p.count)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        var sxx = 0.0, sxy = 0.0
        for i in 0..<p.count { sxx += (xs[i] - mx) * (xs[i] - mx); sxy += (xs[i] - mx) * (ys[i] - my) }
        var slope = sxx > 0 ? sxy / sxx : 0
        // la deriva real de un cristal es de decenas de ppm: una pendiente mayor es ruido, no deriva
        if abs(slope) > 200e-6 { slope = 0 }
        let intercept = my - slope * mx
        return AvoSyncFit(refHostNs: ref, offsetAtRefNs: base + Int64(intercept.rounded()), slope: slope)
    }

    /// Menor retardo de ida y vuelta visto en las muestras usadas.
    var minDelayNs: Int64? { points.map { $0.delayNs }.min() }

    /// Dispersión (RMS) de las muestras respecto a la recta.
    var spreadNs: Int64? {
        guard let f = fit else { return nil }
        let p = points
        guard p.count >= 2 else { return nil }
        let s = p.reduce(0.0) { acc, x in
            let r = Double(x.offsetNs - f.offset(atHostNs: x.hostNs))
            return acc + r * r
        }
        return Int64((s / Double(p.count)).squareRoot().rounded())
    }

    /// Cota de error estimada (E): la mitad del menor retardo (asimetría máxima del enlace) más la dispersión.
    var errorBoundNs: Int64? {
        guard let d = minDelayNs else { return nil }
        return d / 2 + (spreadNs ?? 0)
    }
}

// MARK: - Archivo auxiliar .avosync.json

/// Se guarda junto a cada vídeo: con él la app sabe la hora GPS de cada fotograma
/// (`UTC del fotograma = host_ns del fotograma + offset(host_ns)`, y el fotograma 0 está en `first_frame_host_ns`).
struct AvoSyncVideoFile: Codable, Equatable {
    enum Source: String, Codable {
        /// Hora GPS del gadget AVO SYNC.
        case avoSync = "avo_sync"
        /// Sin gadget: reloj del sistema del iPad (NTP de iOS). Precisión de decenas de ms (E).
        case ipadClock = "reloj_ipad"
    }

    struct ClockPair: Codable, Equatable {
        var hostNs: Int64
        var unixNs: Int64
        enum CodingKeys: String, CodingKey { case hostNs = "host_ns", unixNs = "unix_ns" }
    }

    struct MarkEntry: Codable, Equatable {
        var kind: AvoSyncProtocol.MarkKind
        var utcNs: Int64
        enum CodingKeys: String, CodingKey { case kind, utcNs = "utc_ns" }
    }

    var format: String = "avosync"
    var version: Int = 1
    var video: String
    var width: Int
    var height: Int
    var fpsNominal: Double
    var codec: String
    var frames: Int
    var firstFrameHostNs: Int64
    var lastFrameHostNs: Int64
    var source: Source
    /// Hora UTC (ns desde 1970, sin segundos intercalares) del primer fotograma con la mejor fuente disponible.
    var firstFrameUtcNs: Int64
    /// Cota de error estimada (E) de la hora, en ms. nil con el reloj del iPad (no se puede medir).
    var errorBoundMs: Double?
    var minDelayMs: Double?
    var spreadMs: Double?
    /// El gadget estuvo «en retención» (sin fix) en algún momento de la grabación.
    var holdover: Bool
    var fit: AvoSyncFit?
    var samples: [AvoSyncSample]
    var marks: [MarkEntry]
    var systemClockStart: ClockPair
    var systemClockEnd: ClockPair
    var gadgetName: String?
    var appVersion: String

    enum CodingKeys: String, CodingKey {
        case format, version, video, width, height, codec, frames, source, holdover, fit, samples, marks
        case fpsNominal = "fps_nominal"
        case firstFrameHostNs = "first_frame_host_ns"
        case lastFrameHostNs = "last_frame_host_ns"
        case firstFrameUtcNs = "first_frame_utc_ns"
        case errorBoundMs = "error_bound_ms"
        case minDelayMs = "min_delay_ms"
        case spreadMs = "spread_ms"
        case systemClockStart = "system_clock_start"
        case systemClockEnd = "system_clock_end"
        case gadgetName = "gadget_name"
        case appVersion = "app_version"
    }

    var durationS: Double { Double(lastFrameHostNs - firstFrameHostNs) / 1e9 }

    /// Hora UTC de un instante del vídeo (segundos desde el primer fotograma).
    func utcNs(videoTimeS t: Double) -> Int64 {
        let host = firstFrameHostNs + Int64((t * 1e9).rounded())
        if let f = fit, source == .avoSync { return f.utcNs(hostNs: host) }
        return systemClockStart.unixNs + (host - systemClockStart.hostNs)
    }

    var startDate: Date { Date(timeIntervalSince1970: Double(firstFrameUtcNs) / 1e9) }

    static func encode(_ f: AvoSyncVideoFile) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(f)
    }

    static func decode(_ data: Data) throws -> AvoSyncVideoFile {
        try JSONDecoder().decode(AvoSyncVideoFile.self, from: data)
    }
}

/// Texto «14:05:09.123» de una hora UTC en ns, en hora de Madrid.
enum AvoSyncText {
    static func clock(_ utcNs: Int64) -> String {
        let d = Date(timeIntervalSince1970: Double(utcNs) / 1e9)
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.timeZone = TimeZone(identifier: "Europe/Madrid")
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: d)
    }

    static func ms(_ ns: Int64) -> String {
        let v = Double(ns) / 1e6
        return v < 10 ? String(format: "%.1f ms", v) : String(format: "%.0f ms", v)
    }
}
