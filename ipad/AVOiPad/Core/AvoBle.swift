import Foundation
import CryptoKit

// AVO BLE PROTOCOL v1 — Swift port of windows/AVO.Windows.Core/Watch/AvoBle.cs (itself a port of the Android app:
// core/ble/BleProtocol.kt, AvoClient.kt, Messages.kt, auth/WatchAuth.kt), which copies the chest firmware
// (src/ble_service.cpp, lib/avo_core/src/avo_ble_proto.*, avo_ble_auth.*). UUIDs, message types, layouts and checks are the
// ones the watch already implements, so the watch needs no change to be configured from the iPad.

enum AvoGatt {
    static let service = UUID(uuidString: "7a5e0001-4156-4f50-8e1f-3c0de5a1c0a3")!
    static let info = UUID(uuidString: "7a5e0002-4156-4f50-8e1f-3c0de5a1c0a3")!
    static let ctrlRx = UUID(uuidString: "7a5e0003-4156-4f50-8e1f-3c0de5a1c0a3")!   // write with response (encrypted)
    static let ctrlTx = UUID(uuidString: "7a5e0004-4156-4f50-8e1f-3c0de5a1c0a3")!   // notify: responses, events
    static let telem = UUID(uuidString: "7a5e0005-4156-4f50-8e1f-3c0de5a1c0a3")!    // notify: telemetry
    static let rtcm = UUID(uuidString: "7a5e0006-4156-4f50-8e1f-3c0de5a1c0a3")!
    static let fileTx = UUID(uuidString: "7a5e0007-4156-4f50-8e1f-3c0de5a1c0a3")!   // notify: FILE_DATA
    /// V3.4.2+: "AVO_XXXX"; V3.3: "AVO-XXXX".
    static let namePattern = "^AVO[_-][0-9A-F]{4}$"
    static func isWatchName(_ name: String?) -> Bool { (name ?? "").matches(namePattern) }
    static let preferredMtu = 247
}

enum MsgType: UInt8 {
    case getInfo = 0x01, getStatus = 0x02
    case authHello = 0x08, authProof = 0x09, claimBegin = 0x0A, claimResult = 0x0B, authRevoke = 0x0C
    case sessionCmd = 0x10
    case getConfig = 0x20, setConfig = 0x21, setFence = 0x22, getFence = 0x23, setActiveFences = 0x24
    case rtcm = 0x30, rtcmAck = 0x31
    /// V3.7.4: Wi-Fi download (1 start, 2 stop, 3 status, 4 regenerate password). Not in AVO Windows (it used USB).
    case wifiSync = 0x64
    case nack = 0x7E, ack = 0x7F, telemetry = 0x80, event = 0x81

    /// Name as the C# enum prints it (used in error messages).
    var name: String {
        switch self {
        case .getInfo: return "GetInfo"
        case .getStatus: return "GetStatus"
        case .authHello: return "AuthHello"
        case .authProof: return "AuthProof"
        case .claimBegin: return "ClaimBegin"
        case .claimResult: return "ClaimResult"
        case .authRevoke: return "AuthRevoke"
        case .sessionCmd: return "SessionCmd"
        case .getConfig: return "GetConfig"
        case .setConfig: return "SetConfig"
        case .setFence: return "SetFence"
        case .getFence: return "GetFence"
        case .setActiveFences: return "SetActiveFences"
        case .rtcm: return "Rtcm"
        case .rtcmAck: return "RtcmAck"
        case .wifiSync: return "WifiSync"
        case .nack: return "Nack"
        case .ack: return "Ack"
        case .telemetry: return "Telemetry"
        case .event: return "Event"
        }
    }
}

enum BleStatus: UInt8 {
    case ok = 0, badCrc = 1, badFormat = 2, unknownType = 3, busy = 4, notAllowed = 5, notFound = 6, tooLarge = 7, authRequired = 8
    case ioError = 9, stateConflict = 10, duplicate = 11, timeout = 12, verifyFailed = 13, unknown = 255
}

enum BleStatusText {
    static func es(_ s: BleStatus) -> String {
        switch s {
        case .ok: return "correcto"
        case .badCrc: return "CRC erróneo"
        case .badFormat: return "formato erróneo"
        case .unknownType: return "comando no soportado por el firmware"
        case .busy: return "ocupado"
        case .notAllowed: return "no permitido"
        case .notFound: return "no encontrado"
        case .tooLarge: return "demasiado grande"
        case .authRequired: return "autorización necesaria"
        case .ioError: return "error de E/S"
        case .stateConflict: return "estado incompatible"
        case .duplicate: return "duplicado (ya ejecutado)"
        case .timeout: return "tiempo agotado"
        case .verifyFailed: return "verificación fallida"
        case .unknown: return "desconocido"
        }
    }
    static func of(_ code: Int) -> BleStatus {
        guard code >= 0 && code <= 255 else { return .unknown }
        return BleStatus(rawValue: UInt8(code)) ?? .unknown
    }
}

/// CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF), as avo_crc.cpp.
enum Crc16 {
    static func compute<S: Sequence>(_ d: S) -> UInt16 where S.Element == UInt8 {
        var crc: Int = 0xFFFF
        for b in d {
            crc ^= Int(b) << 8
            for _ in 0..<8 {
                crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) & 0xFFFF : (crc << 1) & 0xFFFF
            }
        }
        return UInt16(crc)
    }
}

/// Little-endian writer with the firmware's fixed-width string rule (width-1 bytes max, NUL padded, UTF-8 safe).
final class LeWriter {
    private var buf: [UInt8] = []
    init() {}
    var size: Int { buf.count }
    @discardableResult func u8(_ v: Int) -> LeWriter { buf.append(UInt8(truncatingIfNeeded: v)); return self }
    @discardableResult func u16(_ v: Int) -> LeWriter {
        buf.append(UInt8(truncatingIfNeeded: v)); buf.append(UInt8(truncatingIfNeeded: v >> 8)); return self
    }
    @discardableResult func u32(_ v: Int64) -> LeWriter {
        for i in 0..<4 { buf.append(UInt8(truncatingIfNeeded: v >> (8 * Int64(i)))) }
        return self
    }
    @discardableResult func i32(_ v: Int) -> LeWriter { return u32(Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: v)))) }
    @discardableResult func u64(_ v: Int64) -> LeWriter {
        for i in 0..<8 { buf.append(UInt8(truncatingIfNeeded: v >> (8 * Int64(i)))) }
        return self
    }
    @discardableResult func bytes(_ d: [UInt8]) -> LeWriter { buf.append(contentsOf: d); return self }
    @discardableResult func str(_ s: String?, _ width: Int) -> LeWriter {
        let b: [UInt8] = Array((s ?? "").utf8)
        var l = min(b.count, width - 1)
        while l > 0 && l < b.count && (b[l] & 0xC0) == 0x80 { l -= 1 }      // never cut a UTF-8 sequence
        for i in 0..<width { buf.append(i < l ? b[i] : 0) }
        return self
    }
    func toArray() -> [UInt8] { buf }
}

/// Little-endian reader that never throws: on overrun it returns 0/"" and clears `ok` (C# LeReader).
final class LeReader {
    private let b: [UInt8]
    private let end: Int
    private(set) var pos: Int
    private(set) var ok: Bool = true

    init(_ b: [UInt8], start: Int = 0, end: Int? = nil) {
        self.b = b
        self.pos = start
        self.end = end ?? b.count
    }
    var remaining: Int { ok ? end - pos : 0 }
    private func room(_ n: Int) -> Bool {
        if !ok || n < 0 || pos + n > end { ok = false; return false }
        return true
    }
    func u8() -> Int {
        guard room(1) else { return 0 }
        let v = Int(b[pos]); pos += 1; return v
    }
    func i8() -> Int {
        guard room(1) else { return 0 }
        let v = Int(Int8(bitPattern: b[pos])); pos += 1; return v
    }
    func u16() -> Int {
        guard room(2) else { return 0 }
        let v = Int(b[pos]) | Int(b[pos + 1]) << 8; pos += 2; return v
    }
    func u32() -> Int64 {
        guard room(4) else { return 0 }
        let v = Int64(b[pos]) | Int64(b[pos + 1]) << 8 | Int64(b[pos + 2]) << 16 | Int64(b[pos + 3]) << 24
        pos += 4
        return v
    }
    func i32() -> Int { Int(Int32(truncatingIfNeeded: u32())) }
    func u64() -> Int64 {
        guard room(8) else { return 0 }
        var v: UInt64 = 0
        for i in 0..<8 { v |= UInt64(b[pos + i]) << (8 * UInt64(i)) }
        pos += 8
        return Int64(bitPattern: v)
    }
    func bytes(_ n: Int) -> [UInt8] {
        guard room(n) else { return [] }
        let r: [UInt8] = Array(b[pos..<(pos + n)]); pos += n; return r
    }
    func str(_ width: Int) -> String {
        guard room(width) else { return "" }
        var l = 0
        while l < width && b[pos + l] != 0 { l += 1 }
        let s = String(decoding: b[pos..<(pos + l)], as: UTF8.self)
        pos += width
        return s
    }
}

struct BleMessage: Equatable {
    var type: UInt8
    var msgId: UInt16
    var flags: UInt8
    var status: UInt8
    var payload: [UInt8]
    var isResponse: Bool { (flags & BleFraming.flagResponse) != 0 }
    var statusEnum: BleStatus { BleStatusText.of(Int(status)) }
}

/// One parsed fragment.
struct BleFrame: Equatable {
    var type: UInt8
    var msgId: UInt16
    var idx: Int
    var cnt: Int
    var flags: UInt8
    var status: UInt8
    var payload: [UInt8]
}

/// One application fragment per ATT write/notification: 10-byte header + payload + CRC-16 (avo_ble_proto).
enum BleFraming {
    static let version = 1, header = 10, overhead = 12, maxMessage = 4096
    static let flagAckReq: UInt8 = 0x01, flagResponse: UInt8 = 0x02, flagError: UInt8 = 0x04

    static func build(_ type: UInt8, _ msgId: UInt16, _ idx: Int, _ cnt: Int, _ flags: UInt8, _ status: UInt8, _ payload: [UInt8]) -> [UInt8] {
        precondition(cnt > 0 && idx < cnt, "fragment index out of range")
        let w = LeWriter().u8(version).u8(Int(type)).u16(Int(msgId)).u16(idx).u16(cnt).u8(Int(flags)).u8(Int(status)).bytes(payload)
        var body = w.toArray()
        let crc = Crc16.compute(body)
        body.append(UInt8(crc & 0xFF))
        body.append(UInt8(crc >> 8))
        return body
    }

    static func parse(_ p: [UInt8]) -> BleFrame? {
        if p.count < overhead { return nil }
        let want = Int(p[p.count - 2]) | Int(p[p.count - 1]) << 8
        if Int(Crc16.compute(p[0..<(p.count - 2)])) != want { return nil }
        let ver = Int(p[0]), idx = Int(p[4]) | Int(p[5]) << 8, cnt = Int(p[6]) | Int(p[7]) << 8
        if ver == 0 || cnt == 0 || idx >= cnt { return nil }
        return BleFrame(type: p[1], msgId: UInt16(p[2]) | UInt16(p[3]) << 8, idx: idx, cnt: cnt, flags: p[8], status: p[9],
                        payload: Array(p[header..<(p.count - 2)]))
    }

    /// Fragment count for an ATT payload size (MTU − 3), as ble_frag_count().
    static func count(_ len: Int, _ attPayload: Int) -> Int {
        let per = attPayload - overhead
        precondition(per > 0, "ATT payload too small")
        let c = (len + per - 1) / per
        return c == 0 ? 1 : c
    }

    static func fragment(_ type: UInt8, _ msgId: UInt16, _ payload: [UInt8], _ attPayload: Int, flags: UInt8 = BleFraming.flagAckReq) throws -> [[UInt8]] {
        if payload.count > maxMessage { throw AvoError.invalidData("mensaje BLE de \(payload.count) B supera \(maxMessage) B") }
        if attPayload - overhead <= 0 { throw AvoError.invalidData("MTU demasiado pequeña") }
        let cnt = count(payload.count, attPayload), per = attPayload - overhead
        var r: [[UInt8]] = []
        r.reserveCapacity(cnt)
        for i in 0..<cnt {
            let off = i * per
            let n = min(per, payload.count - off)
            let part: [UInt8] = n > 0 ? Array(payload[off..<(off + n)]) : []
            r.append(build(type, msgId, i, cnt, flags, 0, part))
        }
        return r
    }
}

/// Reassembles notifications (fragments of one message arrive contiguously and in order).
final class BleReassembler {
    private final class Slot {
        var type: UInt8 = 0
        var id: UInt16 = 0
        var cnt: Int = 0
        var next: Int = 0
        var flags: UInt8 = 0
        var status: UInt8 = 0
        var buf: [UInt8] = []
    }
    private var slots: [Int: Slot] = [:]
    private let maxMessage: Int
    private(set) var crcErrors: Int = 0
    private(set) var gaps: Int = 0

    init(maxMessage: Int = 64 * 1024) { self.maxMessage = maxMessage }

    func feed(_ raw: [UInt8]) -> BleMessage? {
        guard let f = BleFraming.parse(raw) else { crcErrors += 1; return nil }
        let key = Int(f.type) << 16 | Int(f.msgId)
        if f.cnt == 1 {
            slots.removeValue(forKey: key)
            return BleMessage(type: f.type, msgId: f.msgId, flags: f.flags, status: f.status, payload: f.payload)
        }
        var s: Slot? = slots[key]
        if f.idx == 0 {
            let n = Slot()
            n.type = f.type; n.id = f.msgId; n.cnt = f.cnt; n.flags = f.flags; n.status = f.status
            slots[key] = n
            s = n
        }
        guard let slot = s, f.idx == slot.next, f.cnt == slot.cnt else {
            gaps += 1
            slots.removeValue(forKey: key)
            return nil
        }
        slot.buf.append(contentsOf: f.payload)
        if slot.buf.count > maxMessage { slots.removeValue(forKey: key); gaps += 1; return nil }
        slot.next += 1
        if slot.next < slot.cnt { return nil }
        slots.removeValue(forKey: key)
        return BleMessage(type: slot.type, msgId: slot.id, flags: slot.flags, status: slot.status, payload: slot.buf)
    }

    func reset() { slots.removeAll() }
}

/// GATT access implemented by the iPad Bluetooth layer (IosBleTransport) or by a test double (C# IAvoTransport).
protocol AvoTransport: AnyObject {
    /// Write with response on CTRL_RX (one fragment). Throws on failure.
    func writeCtrl(_ fragment: [UInt8]) async throws
    /// ATT payload size (negotiated MTU − 3).
    var attPayload: Int { get }
}

/// C# BleRequestException.
struct BleRequestError: Error, LocalizedError {
    var status: BleStatus
    var message: String
    init(_ status: BleStatus, _ message: String) { self.status = status; self.message = message }
    var errorDescription: String? { message }
}

enum AuthOutcome { case ok, unknownKey, rejected, locked, watchNotAuthentic, error }

/// Credential for one watch (key id 8 B + key 32 B), as the claim returns it.
struct WatchCredential: Equatable {
    var deviceId: String
    var keyId: [UInt8]
    var key: [UInt8]
}

struct WatchInfo: Equatable {
    var bleProto: Int
    var uartProto: Int
    var rawFormat: Int
    var configSchema: Int
    var firmware: String
    var deviceId: String
    var bootCount: Int64
    var mtu: Int
    var caps: Int64
    var authorized: Bool?
    var authKeys: Int?
    var claimPending: Bool?
    var authRequired: Bool?
    var buildFingerprint: String?

    var supportsAuth: Bool { (caps & 0x80) != 0 }
    var supportsConfig: Bool { (caps & 0x04) != 0 }
    var supportsFences: Bool { (caps & 0x08) != 0 }
    /// V3.7.4+: Wi-Fi download (WIFI_SYNC + HTTP /api/v1). Transport chosen by capability (bit 11), never by version.
    var supportsWifiSync: Bool { (caps & 0x800) != 0 }

    static func decode(_ p: [UInt8]) -> WatchInfo? {
        let r = LeReader(p)
        let bp = r.u8(), up = r.u8(), rf = r.u16(), cs = r.u16()
        let fw = r.str(16), dev = r.str(16)
        let boot = r.u32()
        let mtu = r.u16()
        let caps = r.u32()
        if !r.ok { return nil }
        var a: Bool? = nil, cp: Bool? = nil, req: Bool? = nil
        var k: Int? = nil
        var fp: String? = nil
        if r.remaining >= 4 { a = r.u8() != 0; k = r.u8(); cp = r.u8() != 0; req = r.u8() != 0 }
        if r.remaining >= 32 { fp = r.str(32) }
        return WatchInfo(bleProto: bp, uartProto: up, rawFormat: rf, configSchema: cs, firmware: fw, deviceId: dev, bootCount: boot,
                         mtu: mtu, caps: caps, authorized: a, authKeys: k, claimPending: cp, authRequired: req, buildFingerprint: fp)
    }
}

/// Application authorization (firmware V3.4.4, avo_ble_auth.cpp).
enum WatchAuth {
    /// 16 random bytes from the system CSPRNG.
    static func nonce() -> [UInt8] {
        let k = SymmetricKey(size: .bits128)
        return k.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> [UInt8] in Array(raw) }
    }

    private static func proof(_ tag: String, _ key: [UInt8], _ a: [UInt8], _ b: [UInt8], _ devId: String) throws -> [UInt8] {
        if key.count != 32 || a.count != 16 || b.count != 16 { throw AvoError.invalidData("tamaños de autorización") }
        var dev = [UInt8](repeating: 0, count: 12)
        let d: [UInt8] = Array(devId.utf8)        // ASCII device id (hex)
        for i in 0..<min(12, d.count) { dev[i] = d[i] }
        var msg: [UInt8] = Array(tag.utf8)
        msg.append(contentsOf: a)
        msg.append(contentsOf: b)
        msg.append(contentsOf: dev)
        let mac = HMAC<SHA256>.authenticationCode(for: msg, using: SymmetricKey(data: key))
        return Array(mac)
    }

    /// watch_proof = HMAC-SHA256(K, "AVOW" | pn | wn | dev_id)
    static func watchProof(_ key: [UInt8], _ phoneNonce: [UInt8], _ watchNonce: [UInt8], _ devId: String) throws -> [UInt8] {
        try proof("AVOW", key, phoneNonce, watchNonce, devId)
    }
    /// phone_proof = HMAC-SHA256(K, "AVOP" | wn | pn | dev_id)
    static func phoneProof(_ key: [UInt8], _ watchNonce: [UInt8], _ phoneNonce: [UInt8], _ devId: String) throws -> [UInt8] {
        try proof("AVOP", key, watchNonce, phoneNonce, devId)
    }

    /// C# CryptographicOperations.FixedTimeEquals.
    static func fixedTimeEquals(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        if a.count != b.count { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count { diff |= a[i] ^ b[i] }
        return diff == 0
    }
}

// ---------------------------------------------------------------------------------------------------------- async helpers

/// One-shot result that may arrive before or after someone waits for it (C# TaskCompletionSource). Thread safe.
final class AvoOneShot<T> {
    private let lock = NSLock()
    private var cont: CheckedContinuation<T, Error>?
    private var result: Result<T, Error>?
    private var done = false

    init() {}

    var isDone: Bool { lock.lock(); defer { lock.unlock() }; return done }

    /// First call wins; later calls are ignored.
    func resolve(_ r: Result<T, Error>) {
        lock.lock()
        if done { lock.unlock(); return }
        done = true
        if let c = cont {
            cont = nil
            lock.unlock()
            c.resume(with: r)
        } else {
            result = r
            lock.unlock()
        }
    }
    func succeed(_ v: T) { resolve(.success(v)) }
    func fail(_ e: Error) { resolve(.failure(e)) }

    private func install(_ c: CheckedContinuation<T, Error>) {
        lock.lock()
        if let r = result {
            result = nil
            lock.unlock()
            c.resume(with: r)
        } else {
            cont = c
            lock.unlock()
        }
    }

    /// Waits for the result; task cancellation resolves it with CancellationError.
    func value() async throws -> T {
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<T, Error>) in self.install(c) }
        } onCancel: {
            self.fail(CancellationError())
        }
    }

    /// Waits at most timeoutMs; on timeout it resolves with `onTimeout`.
    func value(timeoutMs: Int, onTimeout: @escaping () -> Result<T, Error>) async throws -> T {
        let timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, timeoutMs)) * 1_000_000)
            if Task.isCancelled { return }
            self?.resolve(onTimeout())
        }
        defer { timer.cancel() }
        return try await value()
    }
}

/// Async mutual exclusion in FIFO order (C# SemaphoreSlim(1, 1)).
final class AvoAsyncGate {
    private let lock = NSLock()
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init() {}

    func acquire() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            self.enqueue(c)
        }
    }
    private func enqueue(_ c: CheckedContinuation<Void, Never>) {
        lock.lock()
        if !busy {
            busy = true
            lock.unlock()
            c.resume()
        } else {
            waiters.append(c)
            lock.unlock()
        }
    }
    func release() {
        lock.lock()
        if waiters.isEmpty {
            busy = false
            lock.unlock()
        } else {
            let c = waiters.removeFirst()
            lock.unlock()
            c.resume()
        }
    }
}

/// Request/response engine (same rules as AvoClient.kt): one request in flight; responses matched by msg_id; state-changing
/// commands keep their msg_id on retry so the watch answers DUPLICATE instead of executing twice.
final class AvoClient {
    private let t: AvoTransport
    private let ctrl = BleReassembler()
    private let other = BleReassembler()
    private let lock = NSLock()
    private var pending: [UInt16: AvoOneShot<BleMessage?>] = [:]
    private let gate = AvoAsyncGate()
    private var next: Int
    private var late: Int = 0
    /// Unsolicited messages (telemetry, events). Called on the transport's notification thread.
    var unsolicited: ((BleMessage) -> Void)?
    var lateResponses: Int { lock.lock(); defer { lock.unlock() }; return late }

    init(_ t: AvoTransport, startMsgId: Int? = nil) {
        self.t = t
        self.next = (startMsgId ?? Int.random(in: 1..<0x7000)) & 0x7FFF
    }

    private func newId() -> UInt16 {
        lock.lock(); defer { lock.unlock() }
        next = (next + 1) & 0x7FFF
        if next == 0 { next = 1 }
        return UInt16(next)
    }

    private func setPending(_ id: UInt16, _ s: AvoOneShot<BleMessage?>) { lock.lock(); pending[id] = s; lock.unlock() }
    private func removePending(_ id: UInt16) { lock.lock(); pending.removeValue(forKey: id); lock.unlock() }

    /// Feed every notification here, with the characteristic it came from.
    func onNotification(_ characteristic: UUID, _ value: [UInt8]) {
        lock.lock()
        let m: BleMessage? = (characteristic == AvoGatt.ctrlTx ? ctrl : other).feed(value)
        guard let msg = m else { lock.unlock(); return }
        if msg.isResponse {
            let slot = pending.removeValue(forKey: msg.msgId)
            if slot == nil { late += 1 }
            lock.unlock()
            slot?.succeed(msg)
        } else {
            lock.unlock()
            unsolicited?(msg)
        }
    }

    func onDisconnected() {
        lock.lock()
        ctrl.reset(); other.reset()
        let all = Array(pending.values)
        pending.removeAll()
        lock.unlock()
        for p in all { p.fail(BleRequestError(.timeout, "Conexión perdida")) }
    }

    func request(_ type: MsgType, _ payload: [UInt8] = [], stateChanging: Bool = false, timeoutMs: Int = 3000,
                 retries: Int = 2) async throws -> BleMessage {
        await gate.acquire()
        defer { gate.release() }
        var id = newId()
        var attempt = 0
        while true {
            let slot = AvoOneShot<BleMessage?>()
            setPending(id, slot)
            do {
                for f in try BleFraming.fragment(type.rawValue, id, payload, t.attPayload) { try await t.writeCtrl(f) }
                let got: BleMessage? = try await slot.value(timeoutMs: timeoutMs, onTimeout: { .success(nil) })
                removePending(id)
                if let m = got {
                    if m.statusEnum == .badCrc && attempt < retries { attempt += 1; continue }
                    return m
                }
                try Task.checkCancellation()
                if attempt >= retries { throw BleRequestError(.timeout, "Sin respuesta del reloj (\(type.name))") }
                if !stateChanging { id = newId() }
                attempt += 1
            } catch {
                removePending(id)
                throw error
            }
        }
    }

    func requestOk(_ type: MsgType, _ payload: [UInt8] = [], stateChanging: Bool = false, timeoutMs: Int = 3000) async throws -> [UInt8] {
        let m = try await request(type, payload, stateChanging: stateChanging, timeoutMs: timeoutMs)
        if m.statusEnum != .ok { throw BleRequestError(m.statusEnum, "\(type.name): \(BleStatusText.es(m.statusEnum))") }
        return m.payload
    }

    func getInfo() async throws -> WatchInfo {
        guard let i = WatchInfo.decode(try await requestOk(.getInfo)) else { throw BleRequestError(.badFormat, "GET_INFO ilegible") }
        return i
    }

    /// HMAC challenge-response in both directions (the iPad also checks that the watch knows the key).
    func authenticate(_ cred: WatchCredential) async throws -> AuthOutcome {
        let pn = WatchAuth.nonce()
        let m = try await request(.authHello, cred.keyId + pn)
        switch m.statusEnum {
        case .ok: break
        case .notFound: return .unknownKey
        case .busy: return .locked
        default: return .error
        }
        if m.payload.count < 48 { return .error }
        let wn: [UInt8] = Array(m.payload[0..<16])
        let wp: [UInt8] = Array(m.payload[16..<48])
        guard let expected = try? WatchAuth.watchProof(cred.key, pn, wn, cred.deviceId) else { return .error }
        if !WatchAuth.fixedTimeEquals(wp, expected) { return .watchNotAuthentic }
        guard let mine = try? WatchAuth.phoneProof(cred.key, wn, pn, cred.deviceId) else { return .error }
        let r = try await request(.authProof, mine)
        switch r.statusEnum {
        case .ok: return .ok
        case .busy: return .locked
        case .authRequired: return .rejected
        default: return .error
        }
    }

    /// Starts the BOOT-button claim: the watch shows "PULSA BOOT" for 60 s.
    func claimBegin(_ clientName: String) async throws -> BleStatus {
        try await request(.claimBegin, LeWriter().str(clientName, 24).toArray(), stateChanging: true).statusEnum
    }

    /// Polls CLAIM_RESULT: ok → credential; busy → still waiting for BOOT.
    func claimResult(_ deviceId: String) async throws -> (status: BleStatus, credential: WatchCredential?) {
        let m = try await request(.claimResult)
        if m.statusEnum == .ok && m.payload.count >= 40 {
            return (.ok, WatchCredential(deviceId: deviceId, keyId: Array(m.payload[0..<8]), key: Array(m.payload[8..<40])))
        }
        return (m.statusEnum, nil)
    }

    func getConfig() async throws -> [UInt8] { try await requestOk(.getConfig, timeoutMs: 5000) }
    func setConfig(_ blob: [UInt8]) async throws -> BleMessage { try await request(.setConfig, blob, stateChanging: true, timeoutMs: 8000) }
    func setFence(_ request: [UInt8]) async throws -> BleMessage { try await self.request(.setFence, request, stateChanging: true, timeoutMs: 8000) }
    func setActiveFences(_ mask: Int, auto: Bool) async throws -> BleStatus {
        try await request(.setActiveFences, [UInt8(truncatingIfNeeded: mask), auto ? 1 : 0], stateChanging: true).statusEnum
    }
}
