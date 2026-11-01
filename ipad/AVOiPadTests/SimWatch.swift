import Foundation
@testable import AVO_Horse

// Watch doubles for the tests. No hardware involved.
//  · SimWatch: BLE watch (port of the SimWatch nested in windows/AVO.Windows.SelfTest/WatchTests.cs), same message handling
//    rules as ble_service.cpp for the messages used here, over the same BLE framing.
//  · SimWifiWatch: replaces the USB simulator of windows/AVO.Windows.SelfTest/SimWatch.cs (USB is not available on iPad):
//    CHEST V3.7.4 Wi-Fi semantics (WIFI_SYNC start/stop, Range, If-Match/etag, token, 409 while recording, SHA over the
//    segments), as the Android FakeWatch of core/wifi/WifiSyncTest.kt.

/// Deterministic random bytes (SplitMix64) for test data.
struct WatchTestRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func bytes(_ n: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: n)
        var i = 0
        while i < n {
            var v = next()
            var k = 0
            while k < 8 && i < n { out[i] = UInt8(v & 0xFF); v >>= 8; i += 1; k += 1 }
        }
        return out
    }
}

/// Credentials store in memory (C# MemStore).
final class MemCredentialStore: WatchCredentialStore {
    var d: [String: WatchCredential] = [:]
    func get(_ deviceId: String) -> WatchCredential? { d[deviceId] }
    func save(_ c: WatchCredential) { d[c.deviceId] = c }
}

/// BLE watch double: answers through AvoClient.onNotification synchronously, like the C# test double.
final class SimWatch: AvoTransport {
    var client: AvoClient?
    var config: WatchConfig
    var blob: [UInt8]
    var keys: [(kid: [UInt8], key: [UInt8])] = []
    var authorized = false, claimOpen = false, bootPressed = false
    var polls = 0, setFences = 0, setConfigs = 0, setActives = 0
    static let dev = "a0b1c2d3e4f5"
    /// Capabilities in GET_INFO (0xFFF: auth, config, fences, Wi-Fi…).
    var caps: Int64 = 0xFFF
    var recording = false
    var wifiStarts = 0, wifiStops = 0
    /// Answer to WIFI_SYNC(start).
    var wifiStartReply: (BleStatus, [UInt8]) = (.ok, [])
    private var wn: [UInt8]?
    private var pn: [UInt8]?
    private var kidKey: [UInt8]?
    private let rx = BleReassembler()
    var attPayload: Int { 244 }

    init(_ blob: [UInt8]) throws {
        self.blob = blob
        self.config = try WatchConfig.decode(blob)
    }

    func writeCtrl(_ fragment: [UInt8]) async throws {
        if let m = rx.feed(fragment) { handle(m) }
    }

    private func reply(_ m: BleMessage, _ st: BleStatus, _ payload: [UInt8] = []) {
        let cnt = BleFraming.count(payload.count, attPayload), per = attPayload - BleFraming.overhead
        for i in 0..<cnt {
            let off = i * per
            let n = min(per, payload.count - off)
            let part: [UInt8] = n > 0 ? Array(payload[off..<(off + n)]) : []
            client?.onNotification(AvoGatt.ctrlTx, BleFraming.build(m.type, m.msgId, i, cnt, BleFraming.flagResponse, st.rawValue, part))
        }
    }

    private func store(_ c: WatchConfig) {
        blob = c.encode()
        config = (try? WatchConfig.decode(blob)) ?? c
    }

    private func handle(_ m: BleMessage) {
        guard let t = MsgType(rawValue: m.type) else { reply(m, .unknownType); return }
        let open = t == .getInfo || t == .authHello || t == .authProof || t == .claimBegin || t == .claimResult
        if !authorized && !open { reply(m, .authRequired); return }
        let r = LeReader(m.payload)
        switch t {
        case .getInfo:
            let w = LeWriter().u8(1).u8(1).u16(1).u16(1).str("3.7.6", 16).str(SimWatch.dev, 16).u32(42).u16(247).u32(caps)
            w.u8(authorized ? 1 : 0).u8(keys.count).u8(claimOpen ? 1 : 0).u8(1).str("sim", 32)
            reply(m, .ok, w.toArray())
        case .authHello:
            let kid = r.bytes(8)
            pn = r.bytes(16)
            guard let k = keys.first(where: { $0.kid == kid }) else { reply(m, .notFound); return }
            kidKey = k.key
            let n = WatchAuth.nonce()
            wn = n
            let proof = (try? WatchAuth.watchProof(k.key, pn ?? [], n, SimWatch.dev)) ?? []
            reply(m, .ok, n + proof)
        case .authProof:
            let pp = r.bytes(32)
            if let key = kidKey, let w = wn, let p = pn, let expected = try? WatchAuth.phoneProof(key, w, p, SimWatch.dev) {
                authorized = pp == expected
            } else {
                authorized = false
            }
            reply(m, authorized ? .ok : .authRequired)
        case .claimBegin:
            claimOpen = true
            reply(m, .ok, [60, 0])
        case .claimResult:
            if !claimOpen { reply(m, .notFound); return }
            polls += 1
            if polls >= 2 { bootPressed = true }                 // the user presses BOOT on the second poll
            if !bootPressed { reply(m, .busy); return }
            let kid = WatchAuth.nonce().prefix(8)
            let key = WatchAuth.nonce() + WatchAuth.nonce()
            keys.append((Array(kid), key))
            claimOpen = false
            reply(m, .ok, Array(kid) + key)
        case .getConfig:
            reply(m, .ok, blob)
        case .setConfig:
            if let c = try? WatchConfig.decode(m.payload) {
                store(c)
                setConfigs += 1
                reply(m, .ok, [0, 0])
            } else {
                reply(m, .badFormat, [1])
            }
        case .setFence:
            let slot = r.u8()
            guard let f = Fence.decodeBody(r), slot < 8 else { reply(m, .badFormat); return }
            if f.type != FenceType.none && f.validate() != nil { reply(m, .badFormat, [1]); return }
            var c = config
            c.fences[slot] = f.withId(slot)
            c.fenceCount = max(config.fenceCount, slot + 1)
            store(c)
            setFences += 1
            reply(m, .ok)
        case .setActiveFences:
            var c = config
            c.activeMask = r.u8()
            c.autoEnabled = r.u8() != 0
            store(c)
            setActives += 1
            reply(m, .ok)
        case .wifiSync:
            switch r.u8() {
            case 1:
                if recording { reply(m, .stateConflict); return }
                wifiStarts += 1
                reply(m, wifiStartReply.0, wifiStartReply.1)
            case 2:
                wifiStops += 1
                reply(m, .ok)
            case 3:
                let w = LeWriter().u8(1).u8(0).u32(Int64(wifiStarts)).u32(7).u32(1234).u32(5000).u32(1).u32(0)
                reply(m, .ok, w.toArray())
            default:
                reply(m, .badFormat)
            }
        default:
            reply(m, .unknownType)
        }
    }
}

/// Simulated chest watch with Wi-Fi download (CHEST V3.7.4 HTTP semantics). Same knobs as the Android FakeWatch.
final class SimWifiWatch {
    var order: [String] = []
    var sessions: [String: [[UInt8]]] = [:]
    var open: Set<String> = []
    var token = String(repeating: "a", count: 32)
    var recording = false
    var sd = true
    var batteryPct = 80
    var bleUp = true
    var wifiSupported = true
    var apOn = false
    var starts = 0, stops = 0
    var bytesServed: Int64 = 0
    /// Cuts the connection after serving this many bytes (once).
    var cutAfter: Int64 = -1
    /// Modifies the file after serving this many bytes (once).
    var modifyAfter: Int64 = -1
    var wrongSha = false
    var connectFails = false
    var completes: [String] = []

    func add(_ id: String, _ sizes: [Int], seed: UInt64) {
        var r = WatchTestRandom(seed: seed)
        if sessions[id] == nil { order.append(id) }
        sessions[id] = sizes.map { r.bytes($0) }
    }

    /// Version of the file: changes with sizes AND content (Android: contentHashCode).
    func etag(_ id: String) -> String {
        var h: UInt32 = 2166136261
        for (i, s) in (sessions[id] ?? []).enumerated() {
            h = (h ^ UInt32(truncatingIfNeeded: s.count)) &* 16777619
            h = (h ^ UInt32(i + 1)) &* 16777619
            var c: UInt32 = 1
            for b in s { c = c &* 31 &+ UInt32(b) }
            h = (h ^ c) &* 16777619
        }
        return String(format: "%08x", h)
    }

    func sha(_ id: String) -> String {
        var all: [UInt8] = []
        for s in sessions[id] ?? [] { all.append(contentsOf: s) }
        return AvoHex.sha256(all)
    }

    final class Http: WatchHttp {
        let w: SimWifiWatch
        let tok: String
        init(_ w: SimWifiWatch, _ tok: String) { self.w = w; self.tok = tok }

        private func guardOk() throws {
            if !w.apOn { throw WifiIoError("red del reloj no disponible") }
            if tok != w.token { throw WatchHttpError.auth }
            if w.recording { throw WatchHttpError.recording }
        }

        func list() async throws -> [RemoteTraining] {
            try guardOk()
            return w.order.map { id in
                let s = w.sessions[id] ?? []
                return RemoteTraining(id: id, ready: !w.open.contains(id), segments: s.count, size: s.reduce(0) { $0 + Int64($1.count) },
                                      startRtcMs: 1, activeMs: 1, etag: w.etag(id))
            }
        }

        func metadata(_ id: String) async throws -> RemoteMeta {
            try guardOk()
            guard let s = w.sessions[id] else { throw WatchHttpError.http(404, "id") }
            return RemoteMeta(id: id, ready: !w.open.contains(id), rawFormat: 1, size: s.reduce(0) { $0 + Int64($1.count) },
                              etag: w.etag(id), segmentSizes: s.map { Int64($0.count) })
        }

        func sha256(_ id: String) async throws -> String {
            try guardOk()
            return w.wrongSha ? String(repeating: "0", count: 64) : w.sha(id)
        }

        func openSegment(_ id: String, seg: Int, from: Int64, etag: String) async throws -> WatchByteStream {
            try guardOk()
            if etag != w.etag(id) { throw WatchHttpError.changed }
            guard let data = w.sessions[id]?[seg - 1] else { throw WatchHttpError.http(404, "seg") }
            return SegStream(w, id, seg, data, Int(from))
        }

        func complete(_ id: String, sha256: String, done: Bool) async throws {
            try guardOk()
            w.completes.append("\(id):\(done)")
            if done { w.apOn = false }
        }
    }

    final class SegStream: WatchByteStream {
        let w: SimWifiWatch
        let id: String
        let seg: Int
        let data: [UInt8]
        var pos: Int
        init(_ w: SimWifiWatch, _ id: String, _ seg: Int, _ data: [UInt8], _ from: Int) {
            self.w = w; self.id = id; self.seg = seg; self.data = data; self.pos = from
        }
        func read(maxLength: Int) async throws -> [UInt8] {
            if !w.apOn { throw WifiIoError("Wi-Fi caído") }
            if w.cutAfter >= 0 && w.cutAfter <= w.bytesServed { w.cutAfter = -1; w.apOn = false; throw WifiIoError("Wi-Fi caído") }
            if w.modifyAfter >= 0 && w.modifyAfter <= w.bytesServed {
                w.modifyAfter = -1
                var copy = data
                copy[0] = copy[0] &+ 1
                w.sessions[id]?[seg - 1] = copy
            }
            let n = min(maxLength, 8192, data.count - pos)
            if n <= 0 { return [] }
            let out: [UInt8] = Array(data[pos..<(pos + n)])
            pos += n
            w.bytesServed += Int64(n)
            return out
        }
        func close() {}
    }

    final class Control: WatchWifiControl {
        let w: SimWifiWatch
        init(_ w: SimWifiWatch) { self.w = w }
        func start() async throws -> WifiStartResult {
            if !w.bleUp { throw WifiIoError("BLE desconectado") }
            if !w.wifiSupported { return .unsupported }
            if w.recording { return .refused(reason: "grabando", retryLater: true) }
            if !w.sd { return .refused(reason: "sin microSD", retryLater: true) }
            if w.batteryPct < 15 { return .refused(reason: "batería baja", retryLater: true) }
            w.starts += 1
            w.apOn = true
            return .ok(WifiCredentials(ssid: "AVO_CHEST_ABCD", password: "pw-123456789", token: w.token, ip: "192.168.4.1",
                                       bssid: [0, 0, 0, 0, 0, 0], channel: 1, port: 80, idleTimeoutS: 45))
        }
        func stop() async { w.stops += 1; w.apOn = false }
        func recording() -> Bool { w.recording }
    }

    final class Link: WifiLink {
        let http: WatchHttp
        init(_ http: WatchHttp) { self.http = http }
        func close() async {}
    }

    final class Connector: WifiConnector {
        let w: SimWifiWatch
        init(_ w: SimWifiWatch) { self.w = w }
        func connect(_ creds: WifiCredentials) async -> WifiLink? {
            if w.connectFails || !w.apOn { return nil }
            return Link(Http(w, creds.token))
        }
    }

    lazy var control: Control = Control(self)
    lazy var connector: Connector = Connector(self)
}
