import Foundation
import CryptoKit

/// Per-user folders. Nothing is written next to the original training files.
struct AppPaths: Equatable {
    let root: String

    /// Application Support/AVO Performance Horse/iPad (Windows: %LOCALAPPDATA%\AVO Performance Horse\Windows).
    static var defaultRoot: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("AVO Performance Horse", isDirectory: true)
            .appendingPathComponent("iPad", isDirectory: true).path
    }

    init(root: String? = nil) { self.root = root ?? AppPaths.defaultRoot }

    var library: String { AvoFiles.join(root, "biblioteca") }
    var segments: String { AvoFiles.join(root, "tramos") }
    var analysis: String { AvoFiles.join(root, "analisis") }
    var environmentCache: String { AvoFiles.join(root, "entorno") }
    var tiles: String { AvoFiles.join(root, "teselas") }
    var logs: String { AvoFiles.join(root, "registros") }
    var notes: String { AvoFiles.join(root, "notas") }
    var settingsFile: String { AvoFiles.join(root, "ajustes.json") }
    var libraryIndex: String { AvoFiles.join(root, "biblioteca.json") }
}

/// Dates as System.Text.Json writes DateTimeOffset ("2026-11-01T10:00:00.1234567+00:00") and a tolerant parser.
enum DotNetDate {
    static func format(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSSxxx"
        return f.string(from: d)
    }

    /// ISO 8601 with zone ('Z' or ±hh:mm), any number of fractional digits. nil if invalid or without zone.
    static func parse(_ text: String) -> Date? {
        var s = text.trimmingCharacters(in: .whitespaces)
        // keep at most 3 fractional digits (ISO8601DateFormatter limit)
        if let dot = s.range(of: #"\.\d+"#, options: .regularExpression) {
            let frac = String(s[dot].dropFirst())
            let kept = String(frac.prefix(3))
            s.replaceSubrange(dot, with: "." + kept)
        }
        if let d = AvoTime.parseIso(s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for pattern in ["yyyy-MM-dd'T'HH:mmXXXXX", "yyyy-MM-dd HH:mm:ssXXXXX", "yyyy-MM-dd HH:mm:ss.SSSXXXXX", "yyyy-MM-dd HH:mmXXXXX"] {
            f.dateFormat = pattern
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}

/// Structured JSON-lines log (one file per day) for debugging. Never logs credentials or file contents.
final class AppLog {
    private let dir: String
    private let gate = NSLock()
    static var current: AppLog?

    init(_ dir: String) { self.dir = dir }

    func write(_ level: String, _ area: String, _ message: String, _ error: Error? = nil, _ data: Any? = nil) {
        AvoFiles.ensureDir(dir)
        var exceptionText = "null"
        if let e = error { exceptionText = AvoJSON.quote("\(type(of: e)): \(e.localizedDescription)") }
        var dataText = "null"
        if let d = data {
            if JSONSerialization.isValidJSONObject([d]),
               let encoded = try? JSONSerialization.data(withJSONObject: [d], options: [.withoutEscapingSlashes]) {
                let t = String(decoding: encoded, as: UTF8.self)
                dataText = String(t.dropFirst().dropLast())
            } else {
                dataText = AvoJSON.quote(String(describing: d))
            }
        }
        let line = "{\"ts\":\(AvoJSON.quote(DotNetDate.format(Date()))),\"nivel\":\(AvoJSON.quote(level)),\"area\":\(AvoJSON.quote(area)),"
            + "\"mensaje\":\(AvoJSON.quote(message)),\"excepcion\":\(exceptionText),\"datos\":\(dataText)}\n"
        let day = AvoTime.formatter("yyyyMMdd", utc: true).string(from: Date())
        let file = AvoFiles.join(dir, "avo-ipad-\(day).log")
        gate.lock()
        defer { gate.unlock() }
        let bytes = Data(line.utf8)
        if let h = FileHandle(forWritingAtPath: file) {
            defer { try? h.close() }
            do {
                _ = try h.seekToEnd()
                try h.write(contentsOf: bytes)
            } catch {}
        } else {
            try? bytes.write(to: URL(fileURLWithPath: file))
        }
    }

    func info(_ area: String, _ message: String, _ data: Any? = nil) { write("INFO", area, message, nil, data) }
    func warn(_ area: String, _ message: String, _ error: Error? = nil) { write("AVISO", area, message, error) }
    func error(_ area: String, _ message: String, _ error: Error? = nil) { write("ERROR", area, message, error) }
}

enum MapProvider: String, Codable, CaseIterable {
    case esriSatellite = "EsriSatellite"
    case esriHybrid = "EsriHybrid"
    case vectorOffline = "VectorOffline"
}

/// User settings (no secrets: NTRIP credentials, tokens or keys are never stored by the app).
/// JSON keys and enum text are the ones System.Text.Json writes on Windows (PascalCase, enum as string).
final class AppSettings: Codable {
    var map: MapProvider = .esriSatellite
    var placeLatitude: Double = TrainingPlace.regaton.latitude
    var placeLongitude: Double = TrainingPlace.regaton.longitude
    var placeName: String = TrainingPlace.regaton.name
    var tidePortId: String? = nil
    var onlineEnvironment: Bool = true
    var serverUrl: String = "https://live.avoperformance.org"
    var jerkDensity: Double = 1.0

    enum CodingKeys: String, CodingKey {
        case map = "Map"
        case placeLatitude = "PlaceLatitude"
        case placeLongitude = "PlaceLongitude"
        case placeName = "PlaceName"
        case tidePortId = "TidePortId"
        case onlineEnvironment = "OnlineEnvironment"
        case serverUrl = "ServerUrl"
        case jerkDensity = "JerkDensity"
    }

    init() {}

    /// Missing keys keep their defaults (System.Text.Json behaviour).
    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try c.decodeIfPresent(MapProvider.self, forKey: .map) { map = v }
        if let v = try c.decodeIfPresent(Double.self, forKey: .placeLatitude) { placeLatitude = v }
        if let v = try c.decodeIfPresent(Double.self, forKey: .placeLongitude) { placeLongitude = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .placeName) { placeName = v }
        tidePortId = try c.decodeIfPresent(String.self, forKey: .tidePortId)
        if let v = try c.decodeIfPresent(Bool.self, forKey: .onlineEnvironment) { onlineEnvironment = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .serverUrl) { serverUrl = v }
        if let v = try c.decodeIfPresent(Double.self, forKey: .jerkDensity) { jerkDensity = v }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(map, forKey: .map)
        try c.encode(placeLatitude, forKey: .placeLatitude)
        try c.encode(placeLongitude, forKey: .placeLongitude)
        try c.encode(placeName, forKey: .placeName)
        if let t = tidePortId { try c.encode(t, forKey: .tidePortId) } else { try c.encodeNil(forKey: .tidePortId) }
        try c.encode(onlineEnvironment, forKey: .onlineEnvironment)
        try c.encode(serverUrl, forKey: .serverUrl)
        try c.encode(jerkDensity, forKey: .jerkDensity)
    }

    static func load(_ file: String) -> AppSettings {
        guard let data = AvoFiles.read(file) else { return AppSettings() }
        var d = data
        if d.starts(with: [0xEF, 0xBB, 0xBF]) { d = d.dropFirst(3) }
        return (try? JSONDecoder().decode(AppSettings.self, from: Data(d))) ?? AppSettings()
    }

    func save(_ file: String) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let data = try enc.encode(self)
        try AvoFiles.writeAtomic(data, to: file)
    }
}

/// Entry of the local library index: the verified copy of each imported file (content addressed by SHA-256).
struct LibraryEntry: Codable, Equatable {
    var sha256: String = ""
    var sessionId: String = ""
    var originalName: String = ""
    var storedPath: String = ""
    var importedUtc: Date = Date(timeIntervalSince1970: 0)
    /// File SHA-256 before AVO-ASSIGN-1 rewrote the manifest: re-importing the original is still a duplicate.
    var previousSha256: [String] = []

    enum CodingKeys: String, CodingKey {
        case sha256 = "Sha256"
        case sessionId = "SessionId"
        case originalName = "OriginalName"
        case storedPath = "StoredPath"
        case importedUtc = "ImportedUtc"
        case previousSha256 = "PreviousSha256"
    }

    init(sha256: String = "", sessionId: String = "", originalName: String = "", storedPath: String = "", importedUtc: Date = Date(timeIntervalSince1970: 0)) {
        self.sha256 = sha256; self.sessionId = sessionId; self.originalName = originalName
        self.storedPath = storedPath; self.importedUtc = importedUtc
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sha256 = try c.decodeIfPresent(String.self, forKey: .sha256) ?? ""
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId) ?? ""
        originalName = try c.decodeIfPresent(String.self, forKey: .originalName) ?? ""
        storedPath = try c.decodeIfPresent(String.self, forKey: .storedPath) ?? ""
        if let t = try c.decodeIfPresent(String.self, forKey: .importedUtc) {
            guard let d = DotNetDate.parse(t) else {
                throw DecodingError.dataCorruptedError(forKey: .importedUtc, in: c, debugDescription: "Fecha inválida")
            }
            importedUtc = d
        }
        previousSha256 = try c.decodeIfPresent([String].self, forKey: .previousSha256) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !previousSha256.isEmpty { try c.encode(previousSha256, forKey: .previousSha256) }
        try c.encode(sha256, forKey: .sha256)
        try c.encode(sessionId, forKey: .sessionId)
        try c.encode(originalName, forKey: .originalName)
        try c.encode(storedPath, forKey: .storedPath)
        try c.encode(DotNetDate.format(importedUtc), forKey: .importedUtc)
    }
}

struct ImportOutcome {
    var session: TrainingSession?
    var file: String
    var status: String
    var duplicate: Bool
    var error: String?
}

/// Imports .avo/.avr files into a local library: validates first (TrainingImporter), then copies the file unchanged into
/// the library (name = SHA-256) so the original stays untouched and the session survives if the source is moved.
/// Duplicates are detected by file SHA-256 and by session id.
final class TrainingLibrary {
    private let paths: AppPaths
    private(set) var entries: [LibraryEntry]

    init(_ paths: AppPaths) {
        self.paths = paths
        if let data = AvoFiles.read(paths.libraryIndex),
           let list = try? JSONDecoder().decode([LibraryEntry].self, from: data) {
            entries = list
        } else {
            entries = []
        }
    }

    convenience init(paths: AppPaths) { self.init(paths) }

    /// Lower-case hex SHA-256 of a file, streamed in 1 MB chunks.
    static func fileSha256(_ path: String) throws -> String {
        guard let h = FileHandle(forReadingAtPath: path) else { throw AvoError.notFound("No existe el archivo") }
        defer { try? h.close() }
        var hasher = SHA256()
        while true {
            let chunk: Data = try h.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return AvoHex.lower(hasher.finalize())
    }

    func importFile(_ path: String, loadedSessionIds: [String]) -> ImportOutcome {
        `import`(path, loadedSessionIds: loadedSessionIds)
    }

    func `import`(_ path: String, loadedSessionIds: [String]) -> ImportOutcome {
        var created: String? = nil
        do {
            let sha = try TrainingLibrary.fileSha256(path)
            if let existing = entries.first(where: { ($0.sha256 == sha || $0.previousSha256.contains(sha)) && AvoFiles.exists($0.storedPath) }) {
                let again = try TrainingImporter.importFile(existing.storedPath)
                again.fileSha256 = sha
                again.sourcePath = path
                again.sourceName = existing.originalName
                return ImportOutcome(session: again, file: path, status: "Ya estaba en la biblioteca (mismo SHA-256)", duplicate: true, error: nil)
            }
            try FileManager.default.createDirectory(atPath: paths.library, withIntermediateDirectories: true)
            let ext = (path as NSString).pathExtension.lowercased()
            let stored = AvoFiles.join(paths.library, ext.isEmpty ? sha : sha + "." + ext)
            if !AvoFiles.exists(stored) {
                try FileManager.default.copyItem(atPath: path, toPath: stored)
                created = stored
            }
            if try TrainingLibrary.fileSha256(stored) != sha {
                throw AvoError.invalidData("La copia de la biblioteca no coincide con el original")
            }
            let session = try TrainingImporter.importFile(stored)
            session.fileSha256 = sha
            session.sourcePath = path
            session.sourceName = AvoFiles.fileName(path)
            let dupId = loadedSessionIds.contains(session.sessionId) || entries.contains(where: { $0.sessionId == session.sessionId })
            entries.removeAll(where: { $0.sha256 == sha })
            entries.append(LibraryEntry(sha256: sha, sessionId: session.sessionId, originalName: AvoFiles.fileName(path),
                                        storedPath: stored, importedUtc: Date()))
            try saveIndex()
            created = nil
            return ImportOutcome(session: session, file: path,
                                 status: dupId ? "Importado (otra copia de una sesión ya existente)" : "Importado y verificado",
                                 duplicate: dupId, error: nil)
        } catch {
            if let c = created { try? FileManager.default.removeItem(atPath: c) }
            return ImportOutcome(session: nil, file: path, status: "Rechazado", duplicate: false, error: error.localizedDescription)
        }
    }

    /// AVO-ASSIGN-1: writes the assignment into the library copy of a session (.avo only; .avr files have no manifest).
    /// The RAW segments do not change; the file SHA-256 does, so the old one is kept for duplicate detection.
    /// Returns the new file SHA-256, or nil if the session has no .avo in the library.
    @discardableResult
    func writeAssignment(_ sessionId: String, _ a: AvoAssignmentData, rawHorse: String?, rawRider: String?) throws -> String? {
        guard let i = entries.firstIndex(where: { $0.sessionId == sessionId && AvoFiles.exists($0.storedPath)
                                                  && $0.storedPath.lowercased().hasSuffix(".avo") }) else { return nil }
        try AvoAssignment.write(entries[i].storedPath, a, rawHorse: rawHorse, rawRider: rawRider)
        let sha = try TrainingLibrary.fileSha256(entries[i].storedPath)
        if sha != entries[i].sha256 {
            if !entries[i].previousSha256.contains(entries[i].sha256) { entries[i].previousSha256.append(entries[i].sha256) }
            entries[i].sha256 = sha
            try saveIndex()
        }
        return sha
    }

    func storedFiles() -> [String] { entries.filter { AvoFiles.exists($0.storedPath) }.map { $0.storedPath } }

    func remove(_ sha: String) {
        entries.removeAll(where: { $0.sha256 == sha })
        try? saveIndex()
    }

    private func saveIndex() throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try AvoFiles.writeAtomic(try enc.encode(entries), to: paths.libraryIndex)
    }
}

// ------------------------------------------------------------------------------------------------ AVO server
enum ServerState: String, Codable {
    case notConfigured = "NotConfigured"
    case contractPending = "ContractPending"
    case connected = "Connected"
    case error = "Error"
}

struct RemoteSession: Equatable {
    var id: String
    var horse: String
    var rider: String
    var start: Date?
    var sha256: String?
    var sizeBytes: Int64?
}

/// C# NotSupportedException of the server client.
struct ServerNotSupportedError: Error, LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

/// HTTP failure (C# HttpRequestException).
struct ServicesHttpError: Error, LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

/// Contract the app needs from the AVO server. No implementation talks to live.avoperformance.org yet because no
/// endpoint, authentication scheme or response format has been documented or validated (core/server/ServerApi.kt is
/// "ON HOLD"). Endpoints must not be invented: see windows/docs/SERVIDOR_CONTRATO_PENDIENTE.md.
protocol AvoServerClient {
    var state: ServerState { get }
    var statusText: String { get }
    func listSessions() async throws -> [RemoteSession]
    func download(_ session: RemoteSession, targetDirectory: String, progress: ((Double) -> Void)?) async throws -> String
}
typealias IAvoServerClient = AvoServerClient

final class PendingContractServerClient: AvoServerClient {
    init() {}
    var state: ServerState { .contractPending }
    var statusText: String {
        "No conectado: el servidor AVO no tiene todavía un contrato de API validado (sesiones, autenticación y descargas). Disponible: abrir el panel web y descargar manualmente un .avo por HTTPS."
    }
    func listSessions() async throws -> [RemoteSession] { throw ServerNotSupportedError(message: statusText) }
    func download(_ session: RemoteSession, targetDirectory: String, progress: ((Double) -> Void)?) async throws -> String {
        throw ServerNotSupportedError(message: statusText)
    }
}

/// Manual HTTPS download of a .avo package with a size limit and progress reporting.
enum HttpsDownloader {
    static let maxBytes: Int64 = 100 * 1024 * 1024

    static func downloadAvo(_ url: URL, targetDirectory: String, progress: ((Double) -> Void)? = nil,
                            session: URLSession? = nil) async throws -> String {
        if url.scheme?.lowercased() != "https" { throw AvoError.invalidData("Solo se admiten enlaces HTTPS") }
        if !url.path.lowercased().hasSuffix(".avo") { throw AvoError.invalidData("El enlace debe apuntar a un archivo .avo") }
        let http: URLSession
        if let s = session {
            http = s
        } else {
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 120
            http = URLSession(configuration: cfg)
        }
        try FileManager.default.createDirectory(atPath: targetDirectory, withIntermediateDirectories: true)
        let name = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let temp = AvoFiles.join(targetDirectory, name + ".part")
        defer { if AvoFiles.exists(temp) { try? FileManager.default.removeItem(atPath: temp) } }
        let (bytes, response) = try await http.bytes(for: URLRequest(url: url))
        if let r = response as? HTTPURLResponse, !(200...299).contains(r.statusCode) {
            throw ServicesHttpError(message: "Respuesta HTTP \(r.statusCode)")
        }
        let len = response.expectedContentLength
        if len > maxBytes { throw AvoError.invalidData("Archivo de más de 100 MB") }
        guard FileManager.default.createFile(atPath: temp, contents: nil),
              let output = FileHandle(forWritingAtPath: temp) else {
            throw AvoError.invalidOperation("No se puede crear el archivo temporal")
        }
        var total: Int64 = 0
        var buffer: [UInt8] = []
        buffer.reserveCapacity(65_536)
        do {
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count == 65_536 {
                    total += Int64(buffer.count)
                    if total > maxBytes { throw AvoError.invalidData("La descarga excede 100 MB") }
                    try output.write(contentsOf: buffer)
                    buffer.removeAll(keepingCapacity: true)
                    if len > 0 { progress?(Double(total) / Double(len)) }
                }
            }
            if !buffer.isEmpty {
                total += Int64(buffer.count)
                if total > maxBytes { throw AvoError.invalidData("La descarga excede 100 MB") }
                try output.write(contentsOf: buffer)
                if len > 0 { progress?(Double(total) / Double(len)) }
            }
            try output.close()
        } catch {
            try? output.close()
            throw error
        }
        let dest = AvoFiles.join(targetDirectory, name + ".avo")
        try FileManager.default.moveItem(atPath: temp, toPath: dest)
        return dest
    }
}
