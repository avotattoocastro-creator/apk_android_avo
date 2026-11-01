import Foundation
import CryptoKit

/// Errors of the AVO core (C# InvalidDataException / FileNotFoundException / InvalidOperationException).
enum AvoError: Error, LocalizedError, Equatable {
    case invalidData(String)
    case notFound(String)
    case invalidOperation(String)

    var errorDescription: String? {
        switch self {
        case .invalidData(let m), .notFound(let m), .invalidOperation(let m): return m
        }
    }
    var message: String { errorDescription ?? "" }
}

enum AvoHex {
    static func lower<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        var s = ""
        for b in bytes { s += String(format: "%02x", b) }
        return s
    }
    static func upper<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 { lower(bytes).uppercased() }
    static func sha256(_ data: Data) -> String { lower(SHA256.hash(data: data)) }
    static func sha256(_ bytes: [UInt8]) -> String { lower(SHA256.hash(data: Data(bytes))) }
    /// Parses "a1b2…" into bytes, nil if not valid hex.
    static func bytes(_ hex: String) -> [UInt8]? {
        let chars = Array(hex.utf8)
        guard chars.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(chars.count / 2)
        var i = 0
        while i < chars.count {
            guard let hi = nibble(chars[i]), let lo = nibble(chars[i + 1]) else { return nil }
            out.append(hi << 4 | lo)
            i += 2
        }
        return out
    }
    private static func nibble(_ c: UInt8) -> UInt8? {
        switch c {
        case 48...57: return c - 48
        case 65...70: return c - 55
        case 97...102: return c - 87
        default: return nil
        }
    }
    static func isSha256(_ s: String?) -> Bool {
        guard let s = s, s.utf8.count == 64 else { return false }
        return s.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 70) || ($0 >= 97 && $0 <= 102) }
    }
}

/// Number formatting. `f` = Spanish UI (comma decimal, like es-ES on Windows); `inv` = invariant (CSV/JSON/GPX).
enum AvoFormat {
    static let es = Locale(identifier: "es_ES")
    static let invariant = Locale(identifier: "en_US_POSIX")

    static func f(_ x: Double, _ decimals: Int) -> String {
        guard x.isFinite else { return "—" }
        return String(format: "%.\(decimals)f", locale: es, x)
    }
    static func inv(_ x: Double, _ decimals: Int) -> String {
        guard x.isFinite else { return "" }
        return String(format: "%.\(decimals)f", locale: invariant, x)
    }
    /// Shortest round-trip invariant representation (C# double.ToString("R", InvariantCulture)).
    static func invR(_ x: Double) -> String {
        if x == x.rounded() && abs(x) < 1e15 { return String(Int64(x)) }
        return "\(x)"
    }
    /// Thousands separator in Spanish ("1.234").
    static func n0(_ x: Double) -> String {
        let nf = NumberFormatter()
        nf.locale = es
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 0
        nf.usesGroupingSeparator = true
        return nf.string(from: NSNumber(value: x)) ?? String(Int(x))
    }
}

enum AvoTime {
    static let madrid: TimeZone = TimeZone(identifier: "Europe/Madrid") ?? .current
    static func formatter(_ pattern: String, utc: Bool = false) -> DateFormatter {
        let f = DateFormatter()
        f.locale = AvoFormat.es
        f.timeZone = utc ? TimeZone(identifier: "UTC") : madrid
        f.dateFormat = pattern
        return f
    }
    static func text(_ date: Date?, _ pattern: String = "dd/MM/yyyy HH:mm") -> String {
        guard let date = date else { return "Sin fecha" }
        return formatter(pattern).string(from: date)
    }
    static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
    static func isoFrac(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
    static func parseIso(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
    static func fromUnixMs(_ ms: Double) -> Date { Date(timeIntervalSince1970: ms / 1000.0) }
    static func unixMs(_ d: Date) -> Int64 { Int64((d.timeIntervalSince1970 * 1000.0).rounded()) }
    /// hh:mm:ss like C# TimeSpan.ToString(@"hh\:mm\:ss") (hours modulo 24, as in C#).
    static func hms(_ seconds: Double) -> String {
        let s = Int(max(seconds, 0).rounded(.down))
        return String(format: "%02d:%02d:%02d", (s / 3600) % 24, (s / 60) % 60, s % 60)
    }
}

/// Little-endian reader over a byte array (C# BinaryPrimitives / BinaryReader).
struct BinaryReaderLE {
    let bytes: [UInt8]
    var offset: Int

    init(_ bytes: [UInt8], offset: Int = 0) { self.bytes = bytes; self.offset = offset }

    var remaining: Int { bytes.count - offset }

    mutating func u8() throws -> UInt8 {
        guard offset + 1 <= bytes.count else { throw AvoError.invalidData("Fin de datos inesperado") }
        defer { offset += 1 }
        return bytes[offset]
    }
    mutating func u16() throws -> UInt16 {
        guard offset + 2 <= bytes.count else { throw AvoError.invalidData("Fin de datos inesperado") }
        defer { offset += 2 }
        return BinaryReaderLE.u16(bytes, offset)
    }
    mutating func i16() throws -> Int16 { Int16(bitPattern: try u16()) }
    mutating func u32() throws -> UInt32 {
        guard offset + 4 <= bytes.count else { throw AvoError.invalidData("Fin de datos inesperado") }
        defer { offset += 4 }
        return BinaryReaderLE.u32(bytes, offset)
    }
    mutating func i32() throws -> Int32 { Int32(bitPattern: try u32()) }
    mutating func u64() throws -> UInt64 {
        guard offset + 8 <= bytes.count else { throw AvoError.invalidData("Fin de datos inesperado") }
        defer { offset += 8 }
        return BinaryReaderLE.u64(bytes, offset)
    }
    mutating func i64() throws -> Int64 { Int64(bitPattern: try u64()) }
    mutating func f32() throws -> Float { Float(bitPattern: try u32()) }
    mutating func f64() throws -> Double { Double(bitPattern: try u64()) }
    mutating func take(_ n: Int) throws -> [UInt8] {
        guard n >= 0, offset + n <= bytes.count else { throw AvoError.invalidData("Fin de datos inesperado") }
        defer { offset += n }
        return Array(bytes[offset..<offset + n])
    }

    static func u16(_ b: [UInt8], _ o: Int) -> UInt16 { UInt16(b[o]) | UInt16(b[o + 1]) << 8 }
    static func i16(_ b: [UInt8], _ o: Int) -> Int16 { Int16(bitPattern: u16(b, o)) }
    static func u32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
    }
    static func i32(_ b: [UInt8], _ o: Int) -> Int32 { Int32(bitPattern: u32(b, o)) }
    static func u64(_ b: [UInt8], _ o: Int) -> UInt64 { UInt64(u32(b, o)) | UInt64(u32(b, o + 4)) << 32 }
    static func i64(_ b: [UInt8], _ o: Int) -> Int64 { Int64(bitPattern: u64(b, o)) }
    static func f32(_ b: [UInt8], _ o: Int) -> Float { Float(bitPattern: u32(b, o)) }
    static func f64(_ b: [UInt8], _ o: Int) -> Double { Double(bitPattern: u64(b, o)) }
}

/// Little-endian writer (C# BinaryPrimitives.Write*).
struct BinaryWriterLE {
    var bytes: [UInt8] = []
    mutating func u8(_ v: UInt8) { bytes.append(v) }
    mutating func u16(_ v: UInt16) { bytes.append(UInt8(v & 0xFF)); bytes.append(UInt8(v >> 8)) }
    mutating func i16(_ v: Int16) { u16(UInt16(bitPattern: v)) }
    mutating func u32(_ v: UInt32) { for i in 0..<4 { bytes.append(UInt8((v >> (8 * UInt32(i))) & 0xFF)) } }
    mutating func i32(_ v: Int32) { u32(UInt32(bitPattern: v)) }
    mutating func u64(_ v: UInt64) { for i in 0..<8 { bytes.append(UInt8((v >> (8 * UInt64(i))) & 0xFF)) } }
    mutating func i64(_ v: Int64) { u64(UInt64(bitPattern: v)) }
    mutating func f32(_ v: Float) { u32(v.bitPattern) }
    mutating func f64(_ v: Double) { u64(v.bitPattern) }
    mutating func append(_ b: [UInt8]) { bytes.append(contentsOf: b) }
}

/// Safe access to JSONSerialization output (C# JsonElement.TryGetProperty patterns).
enum AvoJSON {
    static func object(_ data: Data) -> [String: Any]? {
        var d = data
        if d.starts(with: [0xEF, 0xBB, 0xBF]) { d = d.dropFirst(3) }
        return (try? JSONSerialization.jsonObject(with: d, options: [])) as? [String: Any]
    }
    static func string(_ o: [String: Any], _ k: String) -> String? { o[k] as? String }
    /// Finite number only (bools are not numbers).
    static func number(_ o: [String: Any], _ k: String) -> Double? {
        guard let n = o[k] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let d = n.doubleValue
        return d.isFinite ? d : nil
    }
    static func bool(_ o: [String: Any], _ k: String) -> Bool? {
        guard let n = o[k] as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
        return n.boolValue
    }
    static func dict(_ o: [String: Any], _ k: String) -> [String: Any]? { o[k] as? [String: Any] }
    static func array(_ o: [String: Any], _ k: String) -> [Any]? { o[k] as? [Any] }
    /// Serialises with sorted keys disabled and no escaping of slashes, pretty if asked.
    static func data(_ value: Any, pretty: Bool = false) -> Data {
        var opts: JSONSerialization.WritingOptions = [.withoutEscapingSlashes]
        if pretty { opts.insert(.prettyPrinted) }
        return (try? JSONSerialization.data(withJSONObject: value, options: opts)) ?? Data("{}".utf8)
    }
    /// JSON string literal with escaping (C# JsonSerializer.Serialize(string)).
    static func quote(_ s: String) -> String {
        let d = (try? JSONSerialization.data(withJSONObject: [s], options: [.withoutEscapingSlashes])) ?? Data("[\"\"]".utf8)
        let t = String(decoding: d, as: UTF8.self)
        return String(t.dropFirst().dropLast())
    }
}

/// Atomic file helpers (write to .tmp + replace), as in the Windows app.
enum AvoFiles {
    static func ensureDir(_ path: String) {
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }
    static func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }
    static func read(_ path: String) -> Data? { FileManager.default.contents(atPath: path) }
    static func writeAtomic(_ data: Data, to path: String) throws {
        ensureDir((path as NSString).deletingLastPathComponent)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
    static func join(_ parts: String...) -> String {
        var p = parts[0]
        for x in parts.dropFirst() { p = (p as NSString).appendingPathComponent(x) }
        return p
    }
    static func fileName(_ path: String) -> String { (path as NSString).lastPathComponent }
    static func ext(_ path: String) -> String { "." + (path as NSString).pathExtension.lowercased() }
    static func size(_ path: String) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.int64Value ?? -1
    }
    static func list(_ dir: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).sorted().map { join(dir, $0) }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { i >= 0 && i < count ? self[i] : nil }
}

extension String {
    /// C# string[a..b] style helpers.
    func sub(_ from: Int, _ length: Int? = nil) -> String {
        let chars = Array(self)
        let a = Swift.max(0, Swift.min(from, chars.count))
        let b = length.map { Swift.min(chars.count, a + Swift.max(0, $0)) } ?? chars.count
        return String(chars[a..<b])
    }
    func matches(_ pattern: String) -> Bool { range(of: pattern, options: .regularExpression) != nil }
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
