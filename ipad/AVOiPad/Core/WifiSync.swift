import Foundation
import CryptoKit

// Training download over Wi-Fi (watch CHEST V3.7.4+, GET_INFO caps bit 11 = 0x800). Replaces the Windows "Reloj USB" flow,
// which iPadOS cannot do. Port of the Android 2.3-wifi implementation (branch feature/avo-wifi-sync):
// core/wifi/WifiSync.kt (WifiCredentials, WatchHttp, WifiDownloader), core/wifi/WifiSyncCoordinator.kt and the BLE /
// HTTP parts of app/wifi/AvoWifiSyncManager.kt. Protocol: firmware/chest/V3_7_4_WIFI/PROTOCOLO_WIFI.md.
//
// Segments are written to the same files as the BLE download (P001.avr, P002.avr…) in one folder per training; once the
// SHA-256 matches the watch, the folder is handed to the sink, which imports it as RAW segments.
// Joining the watch network (NEHotspotConfiguration) lives in App/WifiJoin.swift.

// ---------------------------------------------------------------------------------------------------------- BLE side

/// WIFI_SYNC (0x64) actions.
enum WifiSyncAction: UInt8 {
    case start = 1, stop = 2, status = 3, regeneratePassword = 4
}

/// Credentials that the watch returns to WIFI_SYNC(start) over authenticated BLE. Never stored on disk, never logged.
struct WifiCredentials: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    var ssid: String
    var password: String
    var token: String
    var ip: String
    var bssid: [UInt8]
    var channel: Int
    var port: Int
    var idleTimeoutS: Int

    var bssidText: String { bssid.map { String(format: "%02x", Int($0)) }.joined(separator: ":") }
    /// Never the password or the token.
    var description: String { "WifiCredentials(\(ssid), ch\(channel), \(ip):\(port))" }
    var debugDescription: String { description }

    /// u8 version=1, str33 ssid, str33 password, str33 token, str16 ip, 6 B bssid, u8 channel, u16 port, u16 idle_s.
    static func decode(_ p: [UInt8]) -> WifiCredentials? {
        let r = LeReader(p)
        if r.u8() != 1 { return nil }
        let ssid = r.str(33), pw = r.str(33), tok = r.str(33), ip = r.str(16)
        let bssid = r.bytes(6)
        let ch = r.u8(), port = r.u16(), idle = r.u16()
        if !r.ok || !ssid.hasPrefix("AVO_CHEST_") || pw.count < 8 || tok.count != 32 || ip.trimmed.isEmpty { return nil }
        return WifiCredentials(ssid: ssid, password: pw, token: tok, ip: ip, bssid: bssid, channel: ch, port: port, idleTimeoutS: idle)
    }
}

/// WIFI_SYNC(3) answer: u8 state, u8 last_stop, u32 starts, requests, bytes_sent, on_ms, completes, auth_failures.
struct WifiSyncStatus: Equatable {
    var state: Int
    var lastStop: Int
    var starts: Int64
    var requests: Int64
    var bytesSent: Int64
    var onMs: Int64
    var completes: Int64
    var authFailures: Int64

    static func decode(_ p: [UInt8]) -> WifiSyncStatus? {
        let r = LeReader(p)
        let st = r.u8(), ls = r.u8()
        let a = r.u32(), b = r.u32(), c = r.u32(), d = r.u32(), e = r.u32(), f = r.u32()
        if !r.ok { return nil }
        return WifiSyncStatus(state: st, lastStop: ls, starts: a, requests: b, bytesSent: c, onMs: d, completes: e, authFailures: f)
    }
}

extension AvoClient {
    /// Sends WIFI_SYNC(action) (state-changing: keeps its msg_id on retry). The answer is returned as is.
    func wifiSync(_ action: WifiSyncAction, timeoutMs: Int = 10_000) async throws -> BleMessage {
        try await request(.wifiSync, [action.rawValue], stateChanging: action != .status, timeoutMs: timeoutMs)
    }

    func wifiStatus() async throws -> WifiSyncStatus {
        let p = try await requestOk(.wifiSync, [WifiSyncAction.status.rawValue], timeoutMs: 4000)
        guard let s = WifiSyncStatus.decode(p) else { throw BleRequestError(.badFormat, "WIFI_SYNC(estado) ilegible") }
        return s
    }
}

// ---------------------------------------------------------------------------------------------------------- HTTP side

struct RemoteTraining: Equatable {
    var id: String
    var ready: Bool
    var segments: Int
    var size: Int64
    var startRtcMs: Int64
    var activeMs: Int64
    var etag: String
}

struct RemoteMeta: Equatable {
    var id: String
    var ready: Bool
    var rawFormat: Int
    var size: Int64
    var etag: String
    var segmentSizes: [Int64]
}

/// HTTP errors with meaning for the logic (Kotlin WatchHttpException / AuthException / RecordingException / ChangedException).
enum WatchHttpError: Error, LocalizedError, Equatable {
    case auth
    case recording
    case changed
    case http(Int, String)

    var code: Int {
        switch self {
        case .auth: return 401
        case .recording: return 409
        case .changed: return 412
        case .http(let c, _): return c
        }
    }
    var errorDescription: String? {
        switch self {
        case .auth: return "Token rechazado por el reloj"
        case .recording: return "El reloj está grabando"
        case .changed: return "El fichero cambió en el reloj"
        case .http(_, let m): return m
        }
    }
    static func forStatus(_ code: Int) -> WatchHttpError {
        switch code {
        case 401: return .auth
        case 409: return .recording
        case 412: return .changed
        default: return .http(code, "HTTP \(code) del reloj")
        }
    }
}

/// Transfer cut or local I/O problem (Kotlin IOException).
struct WifiIoError: Error, LocalizedError {
    var message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Body of a segment being received. read returns at most maxLength bytes; an empty array means end of data.
protocol WatchByteStream: AnyObject {
    func read(maxLength: Int) async throws -> [UInt8]
    func close()
}

/// Watch HTTP API (UrlWatchHttp over URLSession on the watch network; fake in tests).
protocol WatchHttp: AnyObject {
    func list() async throws -> [RemoteTraining]
    func metadata(_ id: String) async throws -> RemoteMeta
    func sha256(_ id: String) async throws -> String
    /// Opens segment `seg` from byte `from` (Range). `etag` → If-Match: if it changed, WatchHttpError.changed.
    func openSegment(_ id: String, seg: Int, from: Int64, etag: String) async throws -> WatchByteStream
    func complete(_ id: String, sha256: String, done: Bool) async throws
}

/// JSON of the watch API (/api/v1).
enum WatchHttpJson {
    private static func i64(_ o: [String: Any], _ k: String) -> Int64 {
        guard let n = o[k] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return 0 }
        return n.int64Value
    }
    private static func str(_ o: [String: Any], _ k: String) -> String {
        if let s = o[k] as? String { return s }
        return ""
    }
    private static func bool(_ o: [String: Any], _ k: String) -> Bool { AvoJSON.bool(o, k) ?? false }

    static func parseList(_ data: Data) -> [RemoteTraining] {
        guard let o = AvoJSON.object(data), let arr = o["trainings"] as? [Any] else { return [] }
        var out: [RemoteTraining] = []
        for x in arr {
            guard let t = x as? [String: Any] else { continue }
            out.append(RemoteTraining(id: str(t, "id"), ready: bool(t, "ready"), segments: Int(i64(t, "segments")), size: i64(t, "size"),
                                      startRtcMs: i64(t, "start_rtc_ms"), activeMs: i64(t, "active_ms"), etag: str(t, "etag")))
        }
        return out
    }
    static func parseList(_ json: String) -> [RemoteTraining] { parseList(Data(json.utf8)) }

    static func parseMeta(_ data: Data) throws -> RemoteMeta {
        guard let o = AvoJSON.object(data) else { throw WifiIoError("Metadatos ilegibles del reloj") }
        var segs: [Int64] = []
        if let a = o["segments"] as? [Any] {
            for x in a {
                if let n = x as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { segs.append(n.int64Value) } else { segs.append(0) }
            }
        }
        return RemoteMeta(id: str(o, "id"), ready: bool(o, "ready"), rawFormat: Int(i64(o, "raw_format")), size: i64(o, "size"),
                          etag: str(o, "etag"), segmentSizes: segs)
    }
    static func parseMeta(_ json: String) throws -> RemoteMeta { try parseMeta(Data(json.utf8)) }

    static func parseSha(_ data: Data) -> String {
        guard let o = AvoJSON.object(data) else { return "" }
        return str(o, "sha256").lowercased()
    }
    static func parseSha(_ json: String) -> String { parseSha(Data(json.utf8)) }
}

/// The raw HTTP exchange, injectable for tests (URLSessionWatchHttpClient in the app).
protocol WatchHttpClient: AnyObject {
    /// Whole body (small JSON answers).
    func send(_ request: URLRequest) async throws -> (status: Int, body: Data)
    /// Streamed body (segments). The caller closes the stream.
    func stream(_ request: URLRequest) async throws -> (status: Int, stream: WatchByteStream)
}

/// URLSession for the watch network: no cache, no cellular (the watch is only reachable over its own Wi-Fi), short timeouts.
final class URLSessionWatchHttpClient: WatchHttpClient {
    let session: URLSession

    init() {
        let c = URLSessionConfiguration.ephemeral
        c.allowsCellularAccess = false
        c.waitsForConnectivity = false
        c.timeoutIntervalForRequest = 20
        c.timeoutIntervalForResource = 15 * 60
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.urlCache = nil
        c.httpMaximumConnectionsPerHost = 1      // the watch accepts one client (max_conn = 1)
        session = URLSession(configuration: c)
    }

    deinit { session.invalidateAndCancel() }

    func send(_ request: URLRequest) async throws -> (status: Int, body: Data) {
        let (d, r) = try await session.data(for: request)
        return ((r as? HTTPURLResponse)?.statusCode ?? 0, d)
    }

    func stream(_ request: URLRequest) async throws -> (status: Int, stream: WatchByteStream) {
        let (bytes, r) = try await session.bytes(for: request)
        return ((r as? HTTPURLResponse)?.statusCode ?? 0, AsyncBytesStream(bytes))
    }
}

/// Pull-style reader over URLSession.AsyncBytes.
final class AsyncBytesStream: WatchByteStream {
    private var it: URLSession.AsyncBytes.AsyncIterator
    private let task: URLSessionDataTask

    init(_ bytes: URLSession.AsyncBytes) {
        self.task = bytes.task
        self.it = bytes.makeAsyncIterator()
    }

    func read(maxLength: Int) async throws -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(max(0, maxLength))
        while out.count < maxLength {
            guard let b = try await it.next() else { break }
            out.append(b)
        }
        return out
    }

    func close() { task.cancel() }
}

/// In-memory stream (tests and the skip wrapper).
final class BytesWatchStream: WatchByteStream {
    private let data: [UInt8]
    private var pos: Int = 0
    init(_ data: [UInt8]) { self.data = data }
    func read(maxLength: Int) async throws -> [UInt8] {
        let n = min(maxLength, data.count - pos)
        if n <= 0 { return [] }
        let r: [UInt8] = Array(data[pos..<(pos + n)])
        pos += n
        return r
    }
    func close() {}
}

/// Drops the first `skip` bytes (server ignored Range and answered 200 with the whole segment).
final class SkippingWatchStream: WatchByteStream {
    private let inner: WatchByteStream
    private var skip: Int64
    init(_ inner: WatchByteStream, skip: Int64) { self.inner = inner; self.skip = skip }
    func read(maxLength: Int) async throws -> [UInt8] {
        while skip > 0 {
            let chunk = try await inner.read(maxLength: Int(min(Int64(64 * 1024), skip)))
            if chunk.isEmpty { return [] }
            skip -= Int64(chunk.count)
        }
        return try await inner.read(maxLength: maxLength)
    }
    func close() { inner.close() }
}

/// Watch HTTP API over a WatchHttpClient (Kotlin NetworkWatchHttp). Bearer token on every request.
final class UrlWatchHttp: WatchHttp {
    private let creds: WifiCredentials
    private let client: WatchHttpClient

    init(_ creds: WifiCredentials, client: WatchHttpClient = URLSessionWatchHttpClient()) {
        self.creds = creds
        self.client = client
    }

    private func path(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    }

    func request(_ path: String, method: String = "GET", timeout: TimeInterval = 20) -> URLRequest {
        let host = creds.ip.trimmed
        let url = URL(string: "http://\(host):\(creds.port)\(path)") ?? URL(string: "http://192.168.4.1")!
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        r.httpMethod = method
        r.setValue("Bearer \(creds.token)", forHTTPHeaderField: "Authorization")
        r.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        return r
    }

    private func text(_ p: String) async throws -> Data {
        let (status, body) = try await client.send(request(p))
        if status != 200 { throw WatchHttpError.forStatus(status) }
        return body
    }

    func list() async throws -> [RemoteTraining] { WatchHttpJson.parseList(try await text("/api/v1/trainings")) }
    func metadata(_ id: String) async throws -> RemoteMeta { try WatchHttpJson.parseMeta(try await text("/api/v1/trainings/\(path(id))/metadata")) }
    func sha256(_ id: String) async throws -> String { WatchHttpJson.parseSha(try await text("/api/v1/trainings/\(path(id))/sha256")) }

    func openSegment(_ id: String, seg: Int, from: Int64, etag: String) async throws -> WatchByteStream {
        var r = request("/api/v1/trainings/\(path(id))/segments/\(seg)", timeout: 15)
        r.setValue("bytes=\(from)-", forHTTPHeaderField: "Range")
        r.setValue("\"\(etag)\"", forHTTPHeaderField: "If-Match")
        let (status, stream) = try await client.stream(r)
        if status != 200 && status != 206 {
            stream.close()
            throw WatchHttpError.forStatus(status)
        }
        if status == 200 && from > 0 { return SkippingWatchStream(stream, skip: from) }
        return stream
    }

    func complete(_ id: String, sha256: String, done: Bool) async throws {
        var r = request("/api/v1/sync/complete", method: "POST")
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.httpBody = Data("id=\(id)&sha256=\(sha256)&done=\(done ? 1 : 0)".utf8)
        let (status, _) = try await client.send(r)
        if status != 200 { throw WatchHttpError.forStatus(status) }
    }
}

// ---------------------------------------------------------------------------------------------------------- download

/// States of the synchronization (a single owner: WifiSyncCoordinator).
enum WifiSyncState: Equatable {
    case idle, discovering, wifiStarting, connecting, downloading, verifying, completed, cleanup, paused, waiting, cancelled, error

    var texto: String {
        switch self {
        case .idle: return ""
        case .discovering: return "Buscando entrenamientos…"
        case .wifiStarting: return "Conectando con el reloj…"
        case .connecting: return "Conectando con el reloj…"
        case .downloading: return "Descargando"
        case .verifying: return "Verificando…"
        case .completed: return "Entrenamiento guardado ✓"
        case .cleanup: return ""
        case .paused: return "En pausa"
        case .waiting: return "Pendiente de conexión"
        case .cancelled: return "Cancelado"
        case .error: return "Error"
        }
    }
}

/// Result per training.
enum DownloadResult: Equatable {
    case verified(sha256: String, bytes: Int64)
    case alreadyLocal
    case notReady
    case mismatch(local: String, remote: String)
    case cancelled
}

/// Resumable download of a training. Never loads whole files into memory: copies in 64 KB blocks and only counts bytes
/// already written (the progress is real). Before reusing local data it checks the file version (etag): if the watch file
/// changed, it discards the partial copy.
final class WifiDownloader {
    private let http: WatchHttp
    private let dirFor: (String) -> String
    private let cancelled: () -> Bool
    static let blockSize = 64 * 1024

    init(_ http: WatchHttp, dirFor: @escaping (String) -> String, cancelled: @escaping () -> Bool = { false }) {
        self.http = http
        self.dirFor = dirFor
        self.cancelled = cancelled
    }

    /// onProgress(confirmed bytes, total).
    func download(_ id: String, knownLocalSha: String? = nil, onProgress: (Int64, Int64) -> Void = { _, _ in }) async throws -> DownloadResult {
        let meta = try await http.metadata(id)
        if !meta.ready { return .notReady }
        let dir = dirFor(id)
        AvoFiles.ensureDir(dir)
        let etagFile = AvoFiles.join(dir, ".wifi_etag")
        let fm = FileManager.default
        // Different version from the one partially downloaded → start again (do not mix data from two files)
        if let d = fm.contents(atPath: etagFile) {
            let prev = String(decoding: d, as: UTF8.self).trimmed
            if prev != meta.etag { WifiDownloader.deleteSegments(dir) }
        }
        // A local segment bigger than the remote one or the wrong number of segments → inconsistent, discarded
        for f in WifiDownloader.segFiles(dir) {
            let name = AvoFiles.fileName(f)
            let n = Int(name.sub(1, 3)) ?? 0
            if n < 1 || n > meta.segmentSizes.count || AvoFiles.size(f) > meta.segmentSizes[n - 1] { try? fm.removeItem(atPath: f) }
        }
        try Data(meta.etag.utf8).write(to: URL(fileURLWithPath: etagFile))
        let total: Int64 = meta.segmentSizes.reduce(0, +)
        // Already complete and verified locally with the same content: nothing to download (duplicate)
        if let known = knownLocalSha, WifiDownloader.localBytes(dir, meta) == total,
           try WifiDownloader.sha256(dir) == known.lowercased() {
            return .alreadyLocal
        }
        var confirmed = WifiDownloader.localBytes(dir, meta)
        onProgress(confirmed, total)
        for (i, size) in meta.segmentSizes.enumerated() {
            let seg = i + 1
            let f = WifiDownloader.segFile(dir, seg)
            var have: Int64 = fm.fileExists(atPath: f) ? max(0, AvoFiles.size(f)) : 0
            if have >= size { continue }
            if cancelled() { return .cancelled }
            do {
                let stream = try await http.openSegment(id, seg: seg, from: have, etag: meta.etag)
                defer { stream.close() }
                if !fm.fileExists(atPath: f) { fm.createFile(atPath: f, contents: nil) }
                guard let fh = FileHandle(forUpdatingAtPath: f) else { throw WifiIoError("No se puede escribir \(AvoFiles.fileName(f))") }
                defer { try? fh.close() }
                try fh.seek(toOffset: UInt64(have))
                try fh.truncate(atOffset: UInt64(have))
                while have < size {
                    if cancelled() {
                        try? fh.synchronize()
                        return .cancelled
                    }
                    let want = Int(min(Int64(WifiDownloader.blockSize), size - have))
                    let chunk = try await stream.read(maxLength: want)
                    if chunk.isEmpty { break }
                    try fh.write(contentsOf: Data(chunk))
                    have += Int64(chunk.count)
                    confirmed += Int64(chunk.count)
                    onProgress(confirmed, total)
                }
                try fh.synchronize()   // what is counted is on disk
            } catch let e as WatchHttpError where e == .changed {
                WifiDownloader.deleteSegments(dir)
                try? fm.removeItem(atPath: etagFile)
                throw e
            }
            if have < size { throw WifiIoError("Conexión cortada en el segmento \(seg) (\(have) de \(size) B)") }
        }
        let local = try WifiDownloader.sha256(dir)
        let remote = try await http.sha256(id)
        if local != remote {
            WifiDownloader.deleteSegments(dir)
            try? fm.removeItem(atPath: etagFile)
            return .mismatch(local: local, remote: remote)
        }
        try? fm.removeItem(atPath: etagFile)
        return .verified(sha256: local, bytes: total)
    }

    static func segFile(_ dir: String, _ seg: Int) -> String { AvoFiles.join(dir, String(format: "P%03d.avr", seg)) }

    /// P001.avr, P002.avr… sorted (the RAW segments to import).
    static func segFiles(_ dir: String) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return names.filter { $0.matches("^P[0-9]{3}\\.avr$") }.sorted().map { AvoFiles.join(dir, $0) }
    }

    static func deleteSegments(_ dir: String) {
        for f in segFiles(dir) { try? FileManager.default.removeItem(atPath: f) }
    }

    static func localBytes(_ dir: String, _ m: RemoteMeta) -> Int64 {
        var sum: Int64 = 0
        for (i, size) in m.segmentSizes.enumerated() {
            let f = segFile(dir, i + 1)
            if FileManager.default.fileExists(atPath: f) { sum += min(max(0, AvoFiles.size(f)), size) }
        }
        return sum
    }

    /// Same calculation as the watch: SHA-256 of the concatenated segments in order (P001, P002… until one is missing).
    static func sha256(_ dir: String) throws -> String {
        var h = SHA256()
        var s = 1
        while true {
            let f = segFile(dir, s)
            if !FileManager.default.fileExists(atPath: f) { break }
            guard let fh = FileHandle(forReadingAtPath: f) else { throw WifiIoError("No se puede leer \(AvoFiles.fileName(f))") }
            defer { try? fh.close() }
            while true {
                let d = try fh.read(upToCount: blockSize) ?? Data()
                if d.isEmpty { break }
                h.update(data: d)
            }
            s += 1
        }
        return AvoHex.lower(h.finalize())
    }
}

// ---------------------------------------------------------------------------------------------------------- coordinator

/// Answer of the watch to WIFI_SYNC(start).
enum WifiStartResult {
    case ok(WifiCredentials)
    /// The watch refuses: recording, low battery, no SD, busy or radio error.
    case refused(reason: String, retryLater: Bool)
    case unsupported
}

/// Watch control over BLE (BleWifiControl over AvoClient; fake in tests).
protocol WatchWifiControl: AnyObject {
    func start() async throws -> WifiStartResult
    func stop() async
    func recording() -> Bool
}

/// The joined watch network and the HTTP API reachable through it.
protocol WifiLink: AnyObject {
    var http: WatchHttp { get }
    func close() async
}

/// Connection to the watch network (NEHotspotConfiguration in the app). nil = not obtained (rejected/timeout).
protocol WifiConnector: AnyObject {
    func connect(_ creds: WifiCredentials) async -> WifiLink?
}

struct WifiSyncProgress: Equatable {
    var state: WifiSyncState = .idle
    var sessionId: String? = nil
    var bytes: Int64 = 0
    var total: Int64 = 0
    var done: Int = 0
    var pending: Int = 0
    var message: String? = nil

    var percent: Int { total > 0 ? Int(min(100, max(0, bytes * 100 / total))) : 0 }
    /// Simple text for Entrenamientos.
    var label: String {
        switch state {
        case .downloading: return "Descargando · \(percent) %"
        case .idle, .cleanup: return ""
        default: return message ?? state.texto
        }
    }
}

/// Result of a pass. fallbackBle = ids that must go another way (Wi-Fi unavailable or rejected).
struct WifiSyncReport: Equatable {
    var verified: [String]
    var failed: [String: String]
    var fallbackBle: [String]
    var skipped: Bool = false
}

/// IDLE → DISCOVERING → WIFI_STARTING → CONNECTING → DOWNLOADING → VERIFYING → COMPLETED → CLEANUP (→ IDLE) with WAITING
/// (retry later), CANCELLED, ERROR and PAUSED. A single pass at a time (a second one is not queued: it returns skipped).
/// The Wi-Fi of the watch is always turned off when finishing, even with errors.
final class WifiSyncCoordinator {
    /// sink(id, folder with P00n.avr, sha256, bytes): import the verified training (RAW segments).
    typealias VerifiedSink = (String, String, String, Int64) async throws -> Void

    private let control: WatchWifiControl
    private let connector: WifiConnector
    private let dirFor: (String) -> String
    private let sink: VerifiedSink
    private let log: (String) -> Void
    private let lock = NSLock()
    private var running = false
    private var cancelRequested = false
    private var _paused = false
    private var _progress = WifiSyncProgress()
    /// Called on every progress change (background thread: hop to the main actor in the UI).
    var onProgress: ((WifiSyncProgress) -> Void)?

    init(control: WatchWifiControl, connector: WifiConnector, dirFor: @escaping (String) -> String, sink: @escaping VerifiedSink,
         log: @escaping (String) -> Void = { _ in }) {
        self.control = control
        self.connector = connector
        self.dirFor = dirFor
        self.sink = sink
        self.log = log
    }

    var progress: WifiSyncProgress { lock.lock(); defer { lock.unlock() }; return _progress }
    var busy: Bool { lock.lock(); defer { lock.unlock() }; return running }
    var paused: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _paused }
        set { lock.lock(); _paused = newValue; lock.unlock() }
    }
    func cancel() { lock.lock(); cancelRequested = true; lock.unlock() }
    private var isCancelRequested: Bool { lock.lock(); defer { lock.unlock() }; return cancelRequested }

    private func tryStart() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if running { return false }
        running = true
        cancelRequested = false
        return true
    }
    private func finish(_ p: WifiSyncProgress) {
        lock.lock()
        _progress = p
        running = false
        lock.unlock()
        onProgress?(p)
    }
    private func publish(_ p: WifiSyncProgress) {
        lock.lock(); _progress = p; lock.unlock()
        onProgress?(p)
    }
    private func set(_ s: WifiSyncState, _ id: String? = nil, done: Int? = nil, pending: Int? = nil, msg: String? = nil) {
        let cur = progress
        publish(WifiSyncProgress(state: s, sessionId: id, bytes: 0, total: 0, done: done ?? cur.done, pending: pending ?? cur.pending, message: msg))
    }

    /// Mutable state of one pass (shared between the body and the cleanup).
    private final class Pass {
        var verified: [String] = []
        var failed: [String: String] = [:]
        var started = false
        var link: WifiLink? = nil
    }

    /// pending: (id, SHA already verified locally or nil if not downloaded).
    func sync(_ pending: [(String, String?)]) async throws -> WifiSyncReport {
        if pending.isEmpty { return WifiSyncReport(verified: [], failed: [:], fallbackBle: []) }
        return try await run(ids: pending.map { $0.0 }) { _ in pending }
    }

    /// Lists the trainings on the watch once connected and downloads the closed ones `want` accepts
    /// (want returns nil to skip, or .some(local SHA or nil) to download).
    func syncAvailable(_ want: @escaping (RemoteTraining) -> String??) async throws -> WifiSyncReport {
        return try await run(ids: nil) { http in
            var out: [(String, String?)] = []
            for t in try await http.list() where t.ready {
                if let w = want(t) { out.append((t.id, w)) }
            }
            return out
        }
    }

    private func run(ids fixedIds: [String]?, _ provider: @escaping (WatchHttp) async throws -> [(String, String?)]) async throws -> WifiSyncReport {
        if !tryStart() { return WifiSyncReport(verified: [], failed: [:], fallbackBle: [], skipped: true) }
        let pass = Pass()
        var ids: [String] = fixedIds ?? []
        var result: Result<WifiSyncReport, Error>
        do {
            let rep = try await body(pass, &ids, fixedIds == nil, provider)
            result = .success(rep)
        } catch {
            result = .failure(error)
        }
        // cleanup: always (Kotlin finally)
        set(.cleanup)
        if let l = pass.link { await l.close() }
        if pass.started { await control.stop() }
        let last = progress
        let cancelled = isCancelRequested
        let allOk = !ids.isEmpty && pass.verified.count == ids.count
        let state: WifiSyncState = cancelled ? .cancelled : (allOk ? .completed : (!pass.failed.isEmpty ? .waiting : .idle))
        let msg: String? = allOk ? "Entrenamiento guardado ✓" : (!pass.failed.isEmpty ? "Pendiente de conexión" : last.message)
        finish(WifiSyncProgress(state: state, sessionId: nil, bytes: 0, total: 0, done: pass.verified.count, pending: ids.count, message: msg))
        return try result.get()
    }

    private func startOrRefused() async -> WifiStartResult {
        do {
            return try await control.start()
        } catch {
            return .refused(reason: error.localizedDescription, retryLater: true)
        }
    }

    private func body(_ pass: Pass, _ ids: inout [String], _ discover: Bool,
                      _ provider: (WatchHttp) async throws -> [(String, String?)]) async throws -> WifiSyncReport {
        if paused {
            set(.paused)
            return WifiSyncReport(verified: [], failed: [:], fallbackBle: [], skipped: true)
        }
        if control.recording() {
            set(.waiting, msg: "Pendiente: el reloj está grabando")
            for id in ids { pass.failed[id] = "grabando" }
            return WifiSyncReport(verified: [], failed: pass.failed, fallbackBle: [])
        }
        set(.wifiStarting, pending: ids.count)
        let s: WifiStartResult = await startOrRefused()
        let creds: WifiCredentials
        switch s {
        case .ok(let c):
            creds = c
        case .unsupported:
            log("wifi: firmware sin Wi-Fi → BLE")
            return WifiSyncReport(verified: [], failed: [:], fallbackBle: ids)
        case .refused(let reason, let retryLater):
            log("wifi: rechazado (\(reason))")
            set(.waiting, msg: "Pendiente de conexión")
            if retryLater {
                for id in ids { pass.failed[id] = reason }
                return WifiSyncReport(verified: [], failed: pass.failed, fallbackBle: [])
            }
            return WifiSyncReport(verified: [], failed: [:], fallbackBle: ids)
        }
        pass.started = true
        set(.connecting, pending: ids.count)
        guard let link = await connector.connect(creds) else {
            log("wifi: el iPad no conectó con la red del reloj")
            return WifiSyncReport(verified: [], failed: [:], fallbackBle: ids)
        }
        pass.link = link
        var pending: [(String, String?)]
        if discover {
            set(.discovering)
            do { pending = try await provider(link.http) } catch {
                log("wifi: lista \(error.localizedDescription)")
                set(.waiting, msg: "Pendiente de conexión")
                return WifiSyncReport(verified: [], failed: ["*": error.localizedDescription], fallbackBle: [])
            }
            ids = pending.map { $0.0 }
            if ids.isEmpty { return WifiSyncReport(verified: [], failed: [:], fallbackBle: []) }
        } else {
            pending = try await provider(link.http)
        }
        let dl = WifiDownloader(link.http, dirFor: dirFor, cancelled: { [weak self] in
            guard let self = self else { return true }
            return self.isCancelRequested || self.control.recording()
        })
        for (n, p) in pending.enumerated() {
            let id = p.0, localSha = p.1
            if isCancelRequested { set(.cancelled); break }
            if control.recording() { set(.waiting, msg: "Pendiente: el reloj está grabando"); pass.failed[id] = "grabando"; break }
            set(.downloading, id, done: n, pending: ids.count)
            let r: DownloadResult
            do {
                r = try await dl.download(id, knownLocalSha: localSha) { [weak self] b, t in
                    guard let self = self else { return }
                    var cur = self.progress
                    cur.state = .downloading
                    cur.sessionId = id
                    cur.bytes = b
                    cur.total = t
                    self.publish(cur)
                }
            } catch let e as WatchHttpError {
                switch e {
                case .recording:
                    pass.failed[id] = "grabando"
                case .auth:
                    pass.failed[id] = e.localizedDescription
                case .changed:
                    pass.failed[id] = "El fichero cambió; se repetirá"
                    continue
                case .http:
                    pass.failed[id] = e.localizedDescription
                    log("wifi: \(id) \(e.localizedDescription)")
                }
                break
            } catch is CancellationError {
                cancel()
                set(.cancelled)
                break
            } catch {
                pass.failed[id] = error.localizedDescription
                log("wifi: \(id) \(error.localizedDescription)")
                break
            }
            switch r {
            case .verified(let sha, let bytes):
                set(.verifying, id, done: n, pending: ids.count)
                try await sink(id, dirFor(id), sha, bytes)
                try? await link.http.complete(id, sha256: sha, done: false)
                pass.verified.append(id)
                set(.completed, id, done: n + 1, pending: ids.count)
            case .alreadyLocal:
                pass.verified.append(id)
            case .notReady:
                pass.failed[id] = "sesión abierta en el reloj"
            case .mismatch:
                pass.failed[id] = "Huella SHA-256 distinta"
            case .cancelled:
                if control.recording() { pass.failed[id] = "grabando" }
                set(.cancelled)
            }
            if case .cancelled = r { break }
        }
        if pass.verified.count == ids.count, let last = ids.last {
            try? await link.http.complete(last, sha256: "", done: true)
        }
        // what did not finish (interruption) is left for the next pass; partial data is kept
        var failed = pass.failed
        for id in ids where !pass.verified.contains(id) && failed[id] == nil { failed[id] = "pendiente" }
        return WifiSyncReport(verified: pass.verified, failed: failed, fallbackBle: [])
    }
}

// ---------------------------------------------------------------------------------------------------------- BLE control

/// Protection against reboot loops (Android AvoWifiSyncManager guard): before each WIFI_SYNC(start) the watch boot counter
/// is saved. If on reconnecting the counter went up (the watch rebooted while turning Wi-Fi on), Wi-Fi is disabled for that
/// firmware and the download goes another way. It is re-enabled on its own when the firmware version changes.
final class WifiBootGuard {
    private let d: UserDefaults
    init(_ defaults: UserDefaults = UserDefaults(suiteName: "avo_wifi_guard") ?? .standard) { d = defaults }

    var blockedFirmware: String? { d.string(forKey: "blocked_fw") }

    func check(_ info: WatchInfo?) -> Bool {
        guard let info = info else { return false }
        let fwBlocked = d.string(forKey: "blocked_fw")
        if let b = fwBlocked, b == info.firmware { return false }
        if fwBlocked != nil { d.removeObject(forKey: "blocked_fw") }      // new firmware: try again
        let attFw = d.string(forKey: "attempt_fw")
        let attBoot: Int64 = (d.object(forKey: "attempt_boot") as? NSNumber)?.int64Value ?? -1
        if let a = attFw, a == info.firmware, attBoot >= 0, info.bootCount > attBoot {
            d.set(info.firmware, forKey: "blocked_fw")
            d.removeObject(forKey: "attempt_fw")
            d.removeObject(forKey: "attempt_boot")
            NSLog("[WIFI] el reloj se reinició al activar el Wi-Fi (arranque \(attBoot) → \(info.bootCount)): Wi-Fi desactivado para \(info.firmware)")
            return false
        }
        return true
    }
    func markAttempt(_ info: WatchInfo?) {
        guard let info = info else { return }
        d.set(info.firmware, forKey: "attempt_fw")
        d.set(NSNumber(value: info.bootCount), forKey: "attempt_boot")
    }
    func clearAttempt() {
        d.removeObject(forKey: "attempt_fw")
        d.removeObject(forKey: "attempt_boot")
    }
    var paused: Bool {
        get { d.bool(forKey: "paused") }
        set { d.set(newValue, forKey: "paused") }
    }
}

/// WIFI_SYNC over the authenticated AvoClient (control object of Android AvoWifiSyncManager).
final class BleWifiControl: WatchWifiControl {
    private let client: () -> AvoClient?
    private let info: () -> WatchInfo?
    private let isRecording: () -> Bool
    let bootGuard: WifiBootGuard

    /// client/info: the current authenticated connection and its GET_INFO; isRecording: session state from telemetry.
    init(client: @escaping () -> AvoClient?, info: @escaping () -> WatchInfo?, isRecording: @escaping () -> Bool = { false },
         bootGuard: WifiBootGuard = WifiBootGuard()) {
        self.client = client
        self.info = info
        self.isRecording = isRecording
        self.bootGuard = bootGuard
    }

    /// Firmware with Wi-Fi download (by capability bit 11, never by version number) and without a reboot history.
    var supported: Bool { (info()?.supportsWifiSync ?? false) && bootGuard.check(info()) }

    func start() async throws -> WifiStartResult {
        if !supported { return .unsupported }
        guard let c = client() else { throw WifiIoError("Sin conexión con el reloj") }
        bootGuard.markAttempt(info())
        let m = try await c.wifiSync(.start, timeoutMs: 10_000)
        if m.statusEnum != .ok { bootGuard.clearAttempt() }   // clean refusal: the watch is still on
        switch m.statusEnum {
        case .ok:
            if let cr = WifiCredentials.decode(m.payload) { return .ok(cr) }
            return .refused(reason: "credenciales ilegibles", retryLater: false)
        case .stateConflict: return .refused(reason: "grabando", retryLater: true)
        case .notAllowed: return .refused(reason: "batería baja", retryLater: true)
        case .busy: return .refused(reason: "ocupado", retryLater: true)
        case .unknownType: return .unsupported
        default:
            if m.payload.first == 3 { return .refused(reason: "sin microSD", retryLater: true) }
            return .refused(reason: "radio del reloj", retryLater: false)
        }
    }

    func stop() async {
        guard let c = client() else { return }
        _ = try? await c.wifiSync(.stop, timeoutMs: 4000)
    }

    func recording() -> Bool { isRecording() }
}
