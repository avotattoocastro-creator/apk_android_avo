import Foundation
import CryptoKit

// Training download over the authenticated Bluetooth link (READ_FILE), used when the watch Wi-Fi cannot be used
// (firmware without caps bit 11, Wi-Fi blocked by WifiBootGuard, refused, or the iPad did not join AVO_CHEST_XXXX).
// Port of the Android implementation (branch fix/chest-v373-readfile):
//   core/ble/Messages.kt (SessionListPage, FileChunk, Requests.readFile), core/ble/AvoClient.kt (listSessions, readChunk,
//   fileSha256), core/sync/Sync.kt (SessionDownload) and core/sync/ResilientDownload.kt; firmware side in
//   firmware/chest/V3_7_3_READFILE/README.md (storage.cpp op_read: at most 2048 B per answer, header offset + size + CRC-32;
//   3.7.3 also caps one answer to 16 notifications at the negotiated MTU).
//
// Protocol (BLE v1 framing, AvoBle.swift):
//   LIST_SESSIONS 0x40  req u16 page → u16 page, u8 n, n × {str24 id, u8 file_state, u16 segments, u64 total_bytes,
//                       u64 start_rtc_ms, u32 active_ms, u8 recording_now}, u8 more
//   READ_FILE     0x41  req str24 id, u16 segment (1…), u32 offset, u32 length → answer type FILE_DATA (0x46) on FILE_TX,
//                       same msg_id: u32 offset, u32 segment size, u32 CRC-32(data), data. NOT_FOUND after the last segment.
//   FILE_SHA256   0x42  req str24 id → 32 B SHA-256 of the concatenated segments (computed by the watch; can take seconds).
//   GET_STATUS    0x02  first bytes: u8 session state (2 recording, 3 paused), u8 geofence, u8 rec status.
// Segments are written to the same P00n.avr files as the Wi-Fi download (either transport continues the other's partial
// copy). The local file only grows by verified blocks at exactly its current length. Nothing is ever deleted on the watch
// (no MARK_UPLOADED / DELETE here).

// ---------------------------------------------------------------------------------------------------------- messages

/// One session in LIST_SESSIONS (Android WatchSessionEntry).
struct WatchSessionEntry: Equatable {
    /// WatchFileState: 0 unknown, 1 open / recording, 2 closed, 3 closed recovered, 4 uploaded.
    static let fileOpen = 1

    var id: String
    var state: Int
    var segments: Int
    var totalBytes: Int64
    var startRtcMs: Int64
    var activeMs: Int64
    var recordingNow: Bool

    /// Closed and not being recorded (Android SyncRules.canDownload).
    var ready: Bool { !recordingNow && state != WatchSessionEntry.fileOpen }

    /// Same row model as the Wi-Fi list (no etag over BLE).
    var remote: RemoteTraining {
        RemoteTraining(id: id, ready: ready, segments: segments, size: totalBytes, startRtcMs: startRtcMs, activeMs: activeMs, etag: "")
    }

    static func decode(_ r: LeReader) -> WatchSessionEntry {
        let id = r.str(24)
        let st = r.u8()
        let segs = r.u16()
        let total = r.u64()
        let start = r.u64()
        let active = r.u32()
        let rec = r.u8() != 0
        return WatchSessionEntry(id: id, state: st, segments: segs, totalBytes: total, startRtcMs: start, activeMs: active, recordingNow: rec)
    }

    func encode(_ w: LeWriter) {
        w.str(id, 24).u8(state).u16(segments).u64(totalBytes).u64(startRtcMs).u32(activeMs).u8(recordingNow ? 1 : 0)
    }
}

/// LIST_SESSIONS answer page (Android SessionListPage).
struct WatchSessionPage: Equatable {
    var page: Int
    var entries: [WatchSessionEntry]
    var more: Bool

    static func decode(_ p: [UInt8]) -> WatchSessionPage? {
        let r = LeReader(p)
        let page = r.u16()
        let n = r.u8()
        var list: [WatchSessionEntry] = []
        for _ in 0..<n { list.append(WatchSessionEntry.decode(r)) }
        let more = r.u8() != 0
        return r.ok ? WatchSessionPage(page: page, entries: list, more: more) : nil
    }
}

/// FILE_DATA payload (Android FileChunk).
struct WatchFileChunk: Equatable {
    var offset: Int64
    var fileSize: Int64
    var crc32: UInt32
    var data: [UInt8]

    static func decode(_ p: [UInt8]) -> WatchFileChunk? {
        if p.count < 12 { return nil }
        let r = LeReader(p)
        let off = r.u32(), size = r.u32(), crc = r.u32()
        return WatchFileChunk(offset: off, fileSize: size, crc32: UInt32(truncatingIfNeeded: crc), data: Array(p[12...]))
    }

    static func crc(_ data: [UInt8]) -> UInt32 { data.isEmpty ? 0 : ZipCRC32.compute(data, 0, data.count) }

    func encode() -> [UInt8] {
        LeWriter().u32(offset).u32(fileSize).u32(Int64(crc32)).bytes(data).toArray()
    }
}

/// The part of GET_STATUS needed here (Android WatchStatus: session, geofence, rec).
struct WatchStatusLite: Equatable {
    var session: Int
    var geofence: Int
    var rec: Int
    /// Android WatchSyncManager.watchRecording(): RECORDING (2) or PAUSED (3).
    var recording: Bool { session == 2 || session == 3 }

    static func decode(_ p: [UInt8]) -> WatchStatusLite? {
        if p.count < 3 { return nil }
        return WatchStatusLite(session: Int(p[0]), geofence: Int(p[1]), rec: Int(p[2]))
    }
}

/// Full GET_STATUS reply of the chest watch (same layout as Android core Messages.kt WatchStatus.decode):
/// session u8 · geofence u8 · rec u8 · sdMounted u8 · sdFree u64 · sessionId str24 · manual u8 · inhibited u8 ·
/// batteryPct i8 (<0 = unknown) · batteryMv u16 · vbus u8 · power u8 · backLink u8 · girth u8 · rtcmFlowing u8 · …
/// Only the fields the «Equipo conectado» window shows are kept; nothing else is interpreted here.
struct WatchStatusFull: Equatable {
    var batteryPct: Int?
    var batteryMv: Int
    var charging: Bool
    var backLink: Bool
    var girth: Bool
    var rtcmFlowing: Bool
    var sdMounted: Bool
    var recording: Bool

    static func decode(_ p: [UInt8]) -> WatchStatusFull? {
        var r = BinaryReaderLE(p)
        do {
            let session = Int(try r.u8())
            _ = try r.u8(); _ = try r.u8()
            let sd = try r.u8() != 0
            _ = try r.u64()
            _ = try r.take(24)
            _ = try r.u8(); _ = try r.u8()
            let pct = Int(Int8(bitPattern: try r.u8()))
            let mv = Int(try r.u16())
            let vbus = try r.u8() != 0
            _ = try r.u8()
            let back = try r.u8() != 0
            let girth = try r.u8() != 0
            let rtcm = try r.u8() != 0
            return WatchStatusFull(batteryPct: pct < 0 ? nil : pct, batteryMv: mv, charging: vbus, backLink: back, girth: girth,
                                   rtcmFlowing: rtcm, sdMounted: sd, recording: session == 2 || session == 3)
        } catch {
            return nil
        }
    }
}

enum BleFileRequests {
    static func listSessions(_ page: Int) -> [UInt8] { LeWriter().u16(page).toArray() }
    static func readFile(_ id: String, segment: Int, offset: Int64, length: Int) -> [UInt8] {
        LeWriter().str(id, 24).u16(segment).u32(offset).u32(Int64(length)).toArray()
    }
    static func sessionOnly(_ id: String) -> [UInt8] { LeWriter().str(id, 24).toArray() }
}

extension AvoClient {
    func watchStatus() async throws -> WatchStatusLite {
        guard let s = WatchStatusLite.decode(try await requestOk(.getStatus, timeoutMs: 4000)) else {
            throw BleRequestError(.badFormat, "GET_STATUS ilegible")
        }
        return s
    }

    /// All pages of LIST_SESSIONS.
    func listSessions() async throws -> [WatchSessionEntry] {
        var out: [WatchSessionEntry] = []
        var page = 0
        while page < 200 {
            guard let p = WatchSessionPage.decode(try await requestOk(.listSessions, BleFileRequests.listSessions(page), timeoutMs: 8000)) else {
                throw BleRequestError(.badFormat, "Lista de sesiones ilegible")
            }
            out.append(contentsOf: p.entries)
            if !p.more { break }
            page += 1
        }
        return out
    }

    /// One READ_FILE. nil at the end of the segments (NOT_FOUND). Checks offset and CRC-32 of the block.
    func readChunk(_ id: String, segment: Int, offset: Int64, length: Int, timeoutMs: Int = 8000, retries: Int = 3) async throws -> WatchFileChunk? {
        let m = try await request(.readFile, BleFileRequests.readFile(id, segment: segment, offset: offset, length: length),
                                  timeoutMs: timeoutMs, retries: retries)
        if m.statusEnum == .notFound { return nil }
        if m.statusEnum != .ok { throw BleRequestError(m.statusEnum, "READ_FILE: " + BleStatusText.es(m.statusEnum)) }
        guard let c = WatchFileChunk.decode(m.payload) else { throw BleRequestError(.badFormat, "Bloque de fichero ilegible") }
        if c.offset != offset { throw BleRequestError(.badFormat, "Desplazamiento inesperado") }
        if WatchFileChunk.crc(c.data) != c.crc32 { throw BleRequestError(.badCrc, "CRC del bloque incorrecto") }
        if c.data.isEmpty && offset < c.fileSize { throw BleRequestError(.badFormat, "Bloque vacío") }
        return c
    }

    /// SHA-256 of all segments computed by the watch.
    func fileSha256(_ id: String, timeoutMs: Int = 120_000) async throws -> [UInt8] {
        let m = try await request(.fileSha256, BleFileRequests.sessionOnly(id), timeoutMs: timeoutMs, retries: 1)
        if m.statusEnum != .ok { throw BleRequestError(m.statusEnum, "FILE_SHA256: " + BleStatusText.es(m.statusEnum)) }
        if m.payload.count < 32 { throw BleRequestError(.badFormat, "SHA-256 ilegible") }
        return Array(m.payload[0..<32])
    }
}

// ---------------------------------------------------------------------------------------------------------- download

enum BleDownloadError: Error, LocalizedError, Equatable {
    /// The watch is recording (GET_STATUS or READ_FILE answered STATE_CONFLICT): stop, keep what was received.
    case recording
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .recording: return "El reloj está grabando"
        case .failed(let m): return m
        }
    }
}

struct BleDownloadOptions {
    /// Requested bytes per READ_FILE (the firmware answers at most 2048 B; shorter answers are fine).
    var chunk: Int = 2048
    /// Failed attempts of the SAME block before giving up (Android ResilientDownload: 8).
    var maxFailures: Int = 8
    var readTimeoutMs: Int = 8000
    /// Retries inside AvoClient.request (new msg_id each time: READ_FILE is read-only).
    var readRetries: Int = 3
    var reconnectWaitMs: Int = 3000
    var shaTimeoutMs: Int = 120_000
    /// GET_STATUS every this many seconds during a download (0 = before every block). Negative = never.
    var statusIntervalS: Double = 15
    /// Pause between attempts (injectable for tests).
    var pause: (Int) async -> Void = { (ms: Int) async -> Void in
        try? await Task.sleep(nanoseconds: UInt64(max(0, ms)) * 1_000_000)
    }

    init() {}

    /// Block size for this link: 2048 B, or less when 16 notifications at the negotiated MTU cannot carry it (3.7.3 cap).
    static func chunkSize(info: WatchInfo?, attPayload: Int) -> Int {
        var att = attPayload
        if let m = info?.mtu, m > 23 { att = min(att, m - 3) }
        let per = att - BleFraming.overhead
        if per <= 0 { return 128 }
        return max(128, min(2048, 16 * per - 12))
    }
}

/// Bytes/s over the last few seconds.
final class TransferSpeed {
    private var samples: [(t: TimeInterval, b: Int64)] = []
    private let window: TimeInterval
    private let now: () -> TimeInterval

    init(window: TimeInterval = 6, now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.window = window
        self.now = now
    }

    func reset() { samples = [] }

    /// Records the confirmed byte count and returns the current speed (0 until there are two samples).
    @discardableResult func add(_ bytes: Int64) -> Double {
        let t = now()
        samples.append((t, bytes))
        while samples.count > 2, let f = samples.first, t - f.t > window { samples.removeFirst() }
        return value
    }

    var value: Double {
        guard let a = samples.first, let b = samples.last, b.t - a.t > 0.2 else { return 0 }
        return Double(max(0, b.b - a.b)) / (b.t - a.t)
    }
}

/// Resumable, verifiable download of ONE watch session over READ_FILE (Android SessionDownload + ResilientDownload).
/// - Blocks of `options.chunk`; each block is checked (CRC-32 + exact offset) and appended only if its offset equals the
///   local length, so nothing is written twice or out of order. Each block is flushed to disk before it counts.
/// - Transient failures (no answer, busy, bad CRC, unexpected offset, GATT/link errors, link lost) retry the SAME offset
///   with growing pauses; the client is read again on every attempt (the link may be replaced).
/// - Resumes from what is already on disk (from either transport); known segment sizes are kept in `.ble_sizes`.
/// - At the end the SHA-256 of the local segments must equal FILE_SHA256 from the watch; if not, the local copy is deleted.
final class BleSessionDownloader {
    private let client: () -> AvoClient?
    private let options: BleDownloadOptions
    private let cancelled: () -> Bool
    private(set) var retries: Int = 0
    private(set) var reads: Int = 0
    private var lastStatus: TimeInterval = 0

    init(client: @escaping () -> AvoClient?, options: BleDownloadOptions = BleDownloadOptions(), cancelled: @escaping () -> Bool = { false }) {
        self.client = client
        self.options = options
        self.cancelled = cancelled
    }

    typealias Progress = (_ bytes: Int64, _ total: Int64, _ bytesPerSecond: Double, _ message: String?) -> Void

    static let sizesFile = ".ble_sizes"

    // ------------------------------------------------------------------ local state
    static func loadSizes(_ dir: String) -> [Int: Int64] {
        guard let d = AvoFiles.read(AvoFiles.join(dir, sizesFile)), let o = AvoJSON.object(d) else { return [:] }
        var out: [Int: Int64] = [:]
        for (k, v) in o {
            if let n = Int(k), let x = v as? NSNumber { out[n] = x.int64Value }
        }
        return out
    }

    static func saveSizes(_ dir: String, _ sizes: [Int: Int64]) {
        var o: [String: Any] = [:]
        for (k, v) in sizes { o[String(k)] = NSNumber(value: v) }
        try? AvoFiles.writeAtomic(AvoJSON.data(o), to: AvoFiles.join(dir, sizesFile))
    }

    /// Bytes on disk in segments 1…hint.
    static func localBytes(_ dir: String, hint: Int) -> Int64 {
        var sum: Int64 = 0
        for s in 1...max(1, hint) {
            let f = WifiDownloader.segFile(dir, s)
            if AvoFiles.exists(f) { sum += max(0, AvoFiles.size(f)) }
        }
        return sum
    }

    /// Next (segment, offset) to request, nil when every segment is complete according to the known sizes.
    static func position(_ dir: String, hint: Int, sizes: [Int: Int64]) -> (Int, Int64)? {
        for s in 1...max(1, hint) {
            let f = WifiDownloader.segFile(dir, s)
            let have: Int64 = AvoFiles.exists(f) ? max(0, AvoFiles.size(f)) : 0
            if let known = sizes[s] {
                if have == known { continue }
                if have > known { try? FileManager.default.removeItem(atPath: f); return (s, 0) }
            }
            return (s, have)
        }
        return nil
    }

    /// Appends a verified block at exactly the current end of `f` and flushes it.
    static func append(_ f: String, offset: Int64, data: [UInt8]) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: f) { fm.createFile(atPath: f, contents: nil) }
        guard let h = FileHandle(forUpdatingAtPath: f) else { throw WifiIoError("No se puede escribir \(AvoFiles.fileName(f))") }
        defer { try? h.close() }
        let end = try h.seekToEnd()
        if end != UInt64(max(0, offset)) { throw WifiIoError("Bloque fuera de orden en \(AvoFiles.fileName(f)) (\(offset) ≠ \(end))") }
        try h.write(contentsOf: Data(data))
        try h.synchronize()
    }

    // ------------------------------------------------------------------ download
    func download(_ e: WatchSessionEntry, dir: String, knownLocalSha: String? = nil, onProgress: Progress = { _, _, _, _ in }) async throws -> DownloadResult {
        if !e.ready { return .notReady }
        AvoFiles.ensureDir(dir)
        let hint = max(1, e.segments)
        // stale segments beyond the watch's count would change the hash
        for f in WifiDownloader.segFiles(dir) {
            let n = Int(AvoFiles.fileName(f).sub(1, 3)) ?? 0
            if n < 1 || n > hint { try? FileManager.default.removeItem(atPath: f) }
        }
        var sizes = BleSessionDownloader.loadSizes(dir)
        for k in Array(sizes.keys) where k > hint { sizes.removeValue(forKey: k) }
        let total = e.totalBytes
        var got = BleSessionDownloader.localBytes(dir, hint: hint)
        if let known = knownLocalSha, got == total, try WifiDownloader.sha256(dir) == known.lowercased() { return .alreadyLocal }
        let speed = TransferSpeed()
        speed.add(got)
        onProgress(got, total, 0, nil)
        lastStatus = 0
        do {
            var pos: (Int, Int64)? = BleSessionDownloader.position(dir, hint: hint, sizes: sizes)
            while let here = pos {
                let seg: Int = here.0, off: Int64 = here.1
                if cancelled() { return .cancelled }
                try await checkRecording()
                let chunk = try await readBlock(e.id, seg, off, got: got, total: total, speed: speed, onProgress)
                guard let c = chunk else {
                    // NOT_FOUND: no such segment (or nothing at this offset of a segment whose size was unknown)
                    if off > 0 && seg < hint {
                        sizes[seg] = off
                        BleSessionDownloader.saveSizes(dir, sizes)
                        pos = (seg + 1, 0)
                        continue
                    }
                    if seg == 1 && off == 0 { throw BleDownloadError.failed("El reloj no encuentra el entrenamiento \(e.id)") }
                    let last = off > 0 ? seg : seg - 1
                    for f in WifiDownloader.segFiles(dir) where (Int(AvoFiles.fileName(f).sub(1, 3)) ?? 0) > last {
                        try? FileManager.default.removeItem(atPath: f)
                    }
                    pos = nil
                    break
                }
                if let old = sizes[seg], old != c.fileSize {
                    // the segment changed on the watch: start that segment again (never mix two versions)
                    try? FileManager.default.removeItem(atPath: WifiDownloader.segFile(dir, seg))
                    sizes[seg] = c.fileSize
                    BleSessionDownloader.saveSizes(dir, sizes)
                    got = BleSessionDownloader.localBytes(dir, hint: hint)
                    pos = (seg, 0)
                    continue
                }
                if sizes[seg] == nil {
                    sizes[seg] = c.fileSize
                    BleSessionDownloader.saveSizes(dir, sizes)
                }
                if off > c.fileSize {
                    try? FileManager.default.removeItem(atPath: WifiDownloader.segFile(dir, seg))
                    got = BleSessionDownloader.localBytes(dir, hint: hint)
                    pos = (seg, 0)
                    continue
                }
                var data = c.data
                let room = Int(c.fileSize - off)
                if data.count > room { data = Array(data[0..<room]) }
                if !data.isEmpty {
                    try BleSessionDownloader.append(WifiDownloader.segFile(dir, seg), offset: off, data: data)
                    got += Int64(data.count)
                }
                let end = off + Int64(data.count)
                onProgress(got, total, speed.add(got), nil)
                if end < c.fileSize { pos = (seg, end) } else if seg < hint { pos = (seg + 1, 0) } else { pos = nil }
            }
            if cancelled() { return .cancelled }
            onProgress(got, total, speed.value, "Verificando huella SHA-256 con el reloj…")
            let local = try WifiDownloader.sha256(dir)
            let remoteBytes: [UInt8] = try await remoteSha(e.id)
            let remote = AvoHex.lower(remoteBytes)
            if local != remote {
                WifiDownloader.deleteSegments(dir)
                try? FileManager.default.removeItem(atPath: AvoFiles.join(dir, BleSessionDownloader.sizesFile))
                return .mismatch(local: local, remote: remote)
            }
            try? FileManager.default.removeItem(atPath: AvoFiles.join(dir, BleSessionDownloader.sizesFile))
            return .verified(sha256: local, bytes: BleSessionDownloader.localBytes(dir, hint: hint))
        } catch is CancellationError {
            return .cancelled
        }
    }

    private func checkRecording() async throws {
        if options.statusIntervalS < 0 { return }
        let now = Date().timeIntervalSince1970
        if lastStatus > 0 && now - lastStatus < options.statusIntervalS { return }
        lastStatus = now
        guard let c = client() else { return }
        // an unreadable status does not stop the download: READ_FILE itself answers STATE_CONFLICT while recording
        if let s = try? await c.watchStatus(), s.recording { throw BleDownloadError.recording }
    }

    private static let transient: [BleStatus] = [.timeout, .busy, .badCrc, .badFormat]

    private func readBlock(_ id: String, _ seg: Int, _ off: Int64, got: Int64, total: Int64, speed: TransferSpeed,
                           _ onProgress: Progress) async throws -> WatchFileChunk? {
        var failures = 0
        while true {
            if cancelled() { throw CancellationError() }
            try Task.checkCancellation()
            guard let c = client() else {
                failures += 1
                retries += 1
                if failures > options.maxFailures { throw BleDownloadError.failed("Conexión Bluetooth con el reloj perdida en \(got / 1024) kB") }
                onProgress(got, total, 0, "Esperando reconexión con el reloj…")
                await options.pause(options.reconnectWaitMs)
                continue
            }
            var why = ""
            do {
                reads += 1
                return try await c.readChunk(id, segment: seg, offset: off, length: options.chunk,
                                             timeoutMs: options.readTimeoutMs, retries: options.readRetries)
            } catch is CancellationError {
                throw CancellationError()
            } catch let e as BleRequestError {
                if e.status == .stateConflict { throw BleDownloadError.recording }
                if e.status == .authRequired { throw BleDownloadError.failed("El reloj pide de nuevo la autorización: vuelve a conectar por Bluetooth.") }
                if !BleSessionDownloader.transient.contains(e.status) { throw BleDownloadError.failed(e.message) }
                why = e.message
            } catch {
                why = error.localizedDescription      // GATT write / link error: same block again
            }
            failures += 1
            retries += 1
            if failures > options.maxFailures {
                let le = c.linkErrors
                throw BleDownloadError.failed("\(why) en \(got / 1024) kB tras \(failures) intentos (fragmentos perdidos \(le.gaps), CRC \(le.crc), respuestas tardías \(c.lateResponses))")
            }
            onProgress(got, total, speed.value, "Reintentando bloque (\(failures)/\(options.maxFailures))…")
            await options.pause(min(8000, 1000 << min(failures - 1, 4)))
        }
    }

    private func remoteSha(_ id: String) async throws -> [UInt8] {
        var failures = 0
        while true {
            if cancelled() { throw CancellationError() }
            guard let c = client() else {
                failures += 1
                if failures > 3 { throw BleDownloadError.failed("Conexión Bluetooth perdida antes de verificar la huella") }
                await options.pause(options.reconnectWaitMs)
                continue
            }
            do {
                return try await c.fileSha256(id, timeoutMs: options.shaTimeoutMs)
            } catch is CancellationError {
                throw CancellationError()
            } catch let e as BleRequestError where e.status == .stateConflict {
                throw BleDownloadError.recording
            } catch {
                failures += 1
                if failures > 3 { throw BleDownloadError.failed("El reloj no dio la huella SHA-256: " + error.localizedDescription) }
                await options.pause(1000)
            }
        }
    }
}

// ---------------------------------------------------------------------------------------------------------- pass

/// A pass of BLE downloads (the Bluetooth counterpart of WifiSyncCoordinator): reads LIST_SESSIONS, refuses while the
/// watch records, downloads and verifies each training, then hands the P00n.avr folder to `sink` (same as Wi-Fi).
/// Progress uses WifiSyncProgress with viaBle = true. One pass at a time.
final class BleTrainingSync {
    private let client: () -> AvoClient?
    private let dirFor: (String) -> String
    private let sink: WifiSyncCoordinator.VerifiedSink
    private let options: BleDownloadOptions
    private let log: (String) -> Void
    private let lock = NSLock()
    private var running = false
    private var cancelRequested = false
    private var _progress = WifiSyncProgress(viaBle: true)
    /// Called on every progress change (background thread: hop to the main actor in the UI).
    var onProgress: ((WifiSyncProgress) -> Void)?

    init(client: @escaping () -> AvoClient?, dirFor: @escaping (String) -> String, sink: @escaping WifiSyncCoordinator.VerifiedSink,
         options: BleDownloadOptions = BleDownloadOptions(), log: @escaping (String) -> Void = { _ in }) {
        self.client = client
        self.dirFor = dirFor
        self.sink = sink
        self.options = options
        self.log = log
    }

    var progress: WifiSyncProgress { lock.lock(); defer { lock.unlock() }; return _progress }
    var busy: Bool { lock.lock(); defer { lock.unlock() }; return running }
    func cancel() { lock.lock(); cancelRequested = true; lock.unlock() }
    var isCancelRequested: Bool { lock.lock(); defer { lock.unlock() }; return cancelRequested }

    /// Sync critical sections (NSLock is not used directly from async functions).
    private func tryStart() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if running { return false }
        running = true
        cancelRequested = false
        return true
    }
    private func endRun() { lock.lock(); running = false; lock.unlock() }

    private func publish(_ p: WifiSyncProgress) {
        var q = p
        q.viaBle = true
        lock.lock(); _progress = q; lock.unlock()
        onProgress?(q)
    }

    private func set(_ s: WifiSyncState, _ id: String? = nil, done: Int, pending: Int, msg: String? = nil) {
        publish(WifiSyncProgress(state: s, sessionId: id, bytes: 0, total: 0, done: done, pending: pending, message: msg))
    }

    /// The trainings on the watch (LIST_SESSIONS).
    func list() async throws -> [WatchSessionEntry] {
        guard let c = client() else { throw WifiIoError("Sin conexión Bluetooth con el reloj") }
        return try await c.listSessions()
    }

    /// ids: the trainings to download (nil = every closed one `want` accepts). knownSha: SHA already verified locally.
    func sync(ids: [String]?, want: @escaping (WatchSessionEntry) -> Bool = { _ in true }, knownSha: [String: String] = [:],
              listed: (([WatchSessionEntry]) -> Void)? = nil) async throws -> WifiSyncReport {
        if !tryStart() { return WifiSyncReport(verified: [], failed: [:], fallbackBle: [], skipped: true) }
        defer { endRun() }

        var verified: [String] = []
        var failed: [String: String] = [:]
        guard let c = client() else { throw WifiIoError("Sin conexión Bluetooth con el reloj: vuelve a conectar.") }
        set(.discovering, done: 0, pending: ids?.count ?? 0, msg: "Leyendo la lista del reloj por Bluetooth…")
        if let s = try? await c.watchStatus(), s.recording {
            set(.waiting, done: 0, pending: ids?.count ?? 0, msg: "Pendiente: el reloj está grabando")
            for id in ids ?? [] { failed[id] = "grabando" }
            if ids == nil { failed["*"] = "grabando" }
            return WifiSyncReport(verified: [], failed: failed, fallbackBle: [])
        }
        let all = try await c.listSessions()
        listed?(all)
        var todo: [WatchSessionEntry] = []
        if let ids = ids {
            for id in ids {
                if let e = all.first(where: { $0.id == id }) { todo.append(e) } else { failed[id] = "ya no está en el reloj" }
            }
        } else {
            todo = all.filter { $0.ready && want($0) }
        }
        let count = todo.count
        let dl = BleSessionDownloader(client: client, options: options, cancelled: { [weak self] in self?.isCancelRequested ?? true })
        log("ble: \(count) entrenamiento(s) por Bluetooth")
        for (n, e) in todo.enumerated() {
            if isCancelRequested { failed[e.id] = "pendiente"; continue }
            if !e.ready { failed[e.id] = e.recordingNow ? "grabando" : "sesión abierta en el reloj"; continue }
            set(.downloading, e.id, done: n, pending: count)
            let r: DownloadResult
            do {
                r = try await dl.download(e, dir: dirFor(e.id), knownLocalSha: knownSha[e.id]) { [weak self] (b: Int64, t: Int64, bps: Double, m: String?) in
                    guard let self = self else { return }
                    var p = self.progress
                    p.state = .downloading
                    p.sessionId = e.id
                    p.bytes = b
                    p.total = t
                    p.bytesPerSecond = bps
                    p.message = m
                    self.publish(p)
                }
            } catch BleDownloadError.recording {
                failed[e.id] = "grabando"
                set(.waiting, e.id, done: n, pending: count, msg: "Pendiente: el reloj está grabando")
                break
            } catch {
                // the link is probably gone: stop here, the rest stays pending (partial data is kept)
                failed[e.id] = error.localizedDescription
                log("ble: \(e.id) \(error.localizedDescription)")
                break
            }
            switch r {
            case .verified(let sha, let bytes):
                set(.verifying, e.id, done: n, pending: count)
                try await sink(e.id, dirFor(e.id), sha, bytes)
                verified.append(e.id)
                set(.completed, e.id, done: n + 1, pending: count)
            case .alreadyLocal:
                verified.append(e.id)
            case .notReady:
                failed[e.id] = "sesión abierta en el reloj"
            case .mismatch:
                failed[e.id] = "Huella SHA-256 distinta"
            case .cancelled:
                failed[e.id] = "pendiente"
                set(.cancelled, e.id, done: n, pending: count)
            }
        }
        for e in todo where !verified.contains(e.id) && failed[e.id] == nil { failed[e.id] = "pendiente" }
        let cancelled = isCancelRequested
        let allOk = !todo.isEmpty && verified.count == todo.count
        set(cancelled ? .cancelled : (allOk ? .completed : (failed.isEmpty ? .idle : .waiting)), done: verified.count, pending: count,
            msg: allOk ? "Entrenamiento guardado ✓" : nil)
        return WifiSyncReport(verified: verified, failed: failed, fallbackBle: [])
    }
}
