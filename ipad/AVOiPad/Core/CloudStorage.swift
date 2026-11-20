import Foundation
import CryptoKit

/// Nube AVO (Cloud Storage for Firebase, plan Blaze), por REST y sin SDK. Mismo contrato que el Android
/// (core/.../cloud/CloudSync.kt) y Windows: `trainings/<CODIGO>/AVO_<id>.avo`, paquetes AVO-TRAINING-1 con el
/// metadato `sha256`. Solo el dueño de la tarjeta puede listar y descargar (firebase/storage.rules).
/// Documentación: docs/NUBE_SESIONES.md.
enum CloudConfig {
    static let bucket: String = "avo-performance-horse-7be14.firebasestorage.app"
    static let prefix: String = "trainings"
    static let maxBytes: Int64 = 40 * 1024 * 1024

    static func fileName(_ sessionId: String) -> String {
        let safe: String = String(sessionId.unicodeScalars.map { (c: Unicode.Scalar) -> Character in
            let ok: Bool = (c >= "A" && c <= "Z") || (c >= "a" && c <= "z") || (c >= "0" && c <= "9") || c == "_" || c == "-"
            return ok ? Character(c) : "_"
        }.prefix(130))
        return "AVO_" + safe + ".avo"
    }

    static func folder(_ code: String) -> String { prefix + "/" + code.uppercased() + "/" }

    /// Huella de lo empaquetado (igual que CloudSync.fingerprint del Android y CloudConfig.Fingerprint de Windows).
    static func fingerprint(localSha256: String, horseCode: String?, riderCode: String?, horseName: String, riderName: String) -> String {
        let s: String = [localSha256.lowercased(), horseCode ?? "", riderCode ?? "", horseName, riderName].joined(separator: "\u{1f}")
        return SHA256.hash(data: Data(s.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

/// Un entrenamiento guardado en la nube.
struct CloudItem: Identifiable, Equatable {
    var name: String          // ruta completa en el bucket
    var size: Int64
    var updated: String
    var sha256: String
    var sessionId: String
    var horseName: String
    var riderName: String
    var startRtcMs: Int64
    var distanceM: Double?
    var horseCode: String = ""
    var riderCode: String = ""
    /// Cuándo se eligió el caballo/jinete (ms UTC; 0 = nunca a mano). Gana el más reciente entre apps.
    var assignedMs: Int64 = 0
    var fp: String = ""
    var id: String { name }
    var fileName: String { String(name.split(separator: "/").last ?? Substring(name)) }

    /// Metadatos de un objeto (respuesta JSON de `GET /v0/b/<bucket>/o/<ruta>`).
    static func parse(_ j: [String: Any]) -> CloudItem? {
        guard let name = j["name"] as? String, name.hasSuffix(".avo") else { return nil }
        let m: [String: Any] = j["metadata"] as? [String: Any] ?? [:]
        let size: Int64 = Int64(j["size"] as? String ?? "") ?? (j["size"] as? NSNumber)?.int64Value ?? 0
        return CloudItem(name: name, size: size, updated: j["updated"] as? String ?? "",
                         sha256: (m["sha256"] as? String ?? "").lowercased(), sessionId: m["sessionId"] as? String ?? "",
                         horseName: m["horseName"] as? String ?? "", riderName: m["riderName"] as? String ?? "",
                         startRtcMs: Int64(m["startRtcMs"] as? String ?? "") ?? 0,
                         distanceM: Double(m["distanceM"] as? String ?? ""),
                         horseCode: m["horseCode"] as? String ?? "", riderCode: m["riderCode"] as? String ?? "",
                         assignedMs: Int64(m["assignedMs"] as? String ?? "") ?? 0, fp: m["fp"] as? String ?? "")
    }

    /// Nombres de la respuesta de listado (`{"items":[{"name":…}], "nextPageToken":…}`).
    static func listNames(_ j: [String: Any]) -> [String] {
        ((j["items"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }.filter { $0.hasSuffix(".avo") }
    }
}

final class AvoCloudClient {
    private let session: URLSession
    private let token: () async throws -> String

    init(token: @escaping () async throws -> String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    private static func objectURL(_ path: String, media: Bool = false) -> URL? {
        var allowed: CharacterSet = .alphanumerics
        allowed.insert(charactersIn: "-._~")
        let enc: String = path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
        return URL(string: "https://firebasestorage.googleapis.com/v0/b/\(CloudConfig.bucket)/o/\(enc)" + (media ? "?alt=media" : ""))
    }

    private func request(_ url: URL) async throws -> URLRequest {
        var r = URLRequest(url: url)
        r.setValue("Firebase " + (try await token()), forHTTPHeaderField: "Authorization")
        r.timeoutInterval = 120
        return r
    }

    private static func check(_ resp: URLResponse, _ what: String) throws {
        let code: Int = (resp as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200...299: return
        case 401, 403: throw LiveFirebaseError("Nube: sin permiso para \(what). ¿Están publicadas las reglas de Storage (firebase/storage.rules)?")
        case 404: throw LiveFirebaseError("Nube: no encontrado (\(what)). ¿Está activado Storage en la consola de Firebase?")
        default: throw LiveFirebaseError("Nube: el servidor respondió \(code) (\(what))")
        }
    }

    /// Mis entrenamientos en la nube, del más reciente al más antiguo.
    func list(code: String) async throws -> [CloudItem] {
        var names: [String] = []
        var pageToken: String? = nil
        repeat {
            var c = URLComponents(string: "https://firebasestorage.googleapis.com/v0/b/\(CloudConfig.bucket)/o")!
            var q: [URLQueryItem] = [URLQueryItem(name: "prefix", value: CloudConfig.folder(code)), URLQueryItem(name: "delimiter", value: "/")]
            if let t = pageToken { q.append(URLQueryItem(name: "pageToken", value: t)) }
            c.queryItems = q
            let (data, resp) = try await session.data(for: try await request(c.url!))
            try AvoCloudClient.check(resp, "listar la nube")
            let j: [String: Any] = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            names += CloudItem.listNames(j)
            pageToken = j["nextPageToken"] as? String
        } while pageToken != nil && names.count < 5000
        var out: [CloudItem] = []
        for n in names {
            guard let u = AvoCloudClient.objectURL(n) else { continue }
            let (data, resp) = try await session.data(for: try await request(u))
            try AvoCloudClient.check(resp, n)
            if let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let it = CloudItem.parse(j) { out.append(it) }
        }
        return out.sorted { ($0.startRtcMs, $0.updated) > ($1.startRtcMs, $1.updated) }
    }

    /// Metadatos de un entrenamiento de la nube, o nil si no está.
    func item(code: String, sessionId: String) async throws -> CloudItem? {
        let path: String = CloudConfig.folder(code) + CloudConfig.fileName(sessionId)
        guard let u = AvoCloudClient.objectURL(path) else { return nil }
        let (data, resp) = try await session.data(for: try await request(u))
        if (resp as? HTTPURLResponse)?.statusCode == 404 { return nil }
        try AvoCloudClient.check(resp, path)
        return ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]).flatMap { CloudItem.parse($0) }
    }

    /// Sube (o reemplaza) un .avo con sus metadatos (subida «multipart» de Firebase Storage).
    func upload(fileAt path: String, code: String, sessionId: String, metadata: [String: String]) async throws {
        let data: Data = try Data(contentsOf: URL(fileURLWithPath: path))
        if Int64(data.count) > CloudConfig.maxBytes { throw LiveFirebaseError("Nube: archivo de más de 40 MB") }
        let name: String = CloudConfig.folder(code) + CloudConfig.fileName(sessionId)
        var meta: [String: String] = metadata
        meta["sha256"] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let json: [String: Any] = ["name": name, "contentType": "application/octet-stream", "metadata": meta]
        let boundary: String = "avo" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Type: application/json; charset=utf-8\r\n\r\n".utf8))
        body.append(try JSONSerialization.data(withJSONObject: json))
        body.append(Data("\r\n--\(boundary)\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--".utf8))
        var c = URLComponents(string: "https://firebasestorage.googleapis.com/v0/b/\(CloudConfig.bucket)/o")!
        c.queryItems = [URLQueryItem(name: "name", value: name)]
        var r: URLRequest = try await request(c.url!)
        r.httpMethod = "POST"
        r.setValue("multipart", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        r.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        r.timeoutInterval = 600
        let (_, resp) = try await session.upload(for: r, from: body)
        try AvoCloudClient.check(resp, "subir " + CloudConfig.fileName(sessionId))
    }

    /// Descarga un .avo a [targetDirectory] y comprueba su SHA-256 con el de la nube. Devuelve la ruta del archivo.
    func download(_ item: CloudItem, targetDirectory: String) async throws -> String {
        if item.size > CloudConfig.maxBytes { throw LiveFirebaseError("Nube: archivo de más de 40 MB") }
        guard let u = AvoCloudClient.objectURL(item.name, media: true) else { throw LiveFirebaseError("Ruta no válida") }
        let (tmp, resp) = try await session.download(for: try await request(u))
        defer { try? FileManager.default.removeItem(at: tmp) }
        try AvoCloudClient.check(resp, item.fileName)
        let data: Data = try Data(contentsOf: tmp)
        let sha: String = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if !item.sha256.isEmpty && sha != item.sha256 { throw LiveFirebaseError("Nube: el SHA-256 de \(item.fileName) no coincide; descarga descartada") }
        try FileManager.default.createDirectory(atPath: targetDirectory, withIntermediateDirectories: true)
        let target: String = (targetDirectory as NSString).appendingPathComponent(item.fileName)
        if FileManager.default.fileExists(atPath: target) { try FileManager.default.removeItem(atPath: target) }
        try data.write(to: URL(fileURLWithPath: target), options: .atomic)
        return target
    }
}

/// Identidad escrita en el manifiesto de un .avo (para la huella y los metadatos al volver a subirlo).
struct CloudManifestIdentity: Equatable {
    var sessionId: String
    var rawSha256: String
    var horseCode: String
    var horseName: String
    var riderCode: String
    var riderName: String
    var assignedMs: Int64

    static func read(_ avoPath: String) throws -> CloudManifestIdentity {
        let zip = try ZipReader(path: avoPath)
        guard let m = zip.entry("manifest.json") else { throw AvoError.invalidData("Falta manifest.json") }
        var mb = try zip.read(m, max: 16_384)
        if mb.count >= 3 && mb[0] == 0xEF && mb[1] == 0xBB && mb[2] == 0xBF { mb.removeFirst(3) }
        guard let root = AvoJSON.object(Data(mb)) else { throw AvoError.invalidData("Manifiesto no válido") }
        return from(root)
    }

    /// Prioridad AVO-ASSIGN-1: bloque «asignacion» y, si falta, los campos de primer nivel.
    static func from(_ root: [String: Any]) -> CloudManifestIdentity {
        let a: AvoAssignmentData? = AvoAssignment.read(root)
        func top(_ k: String) -> String { (AvoJSON.string(root, k) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        let ms: Int64 = a.map { Int64(($0.updated.timeIntervalSince1970 * 1000).rounded()) } ?? 0
        return CloudManifestIdentity(sessionId: top("sessionId"), rawSha256: top("sha256").lowercased(),
                                     horseCode: a?.horseCode ?? top("horseCode"), horseName: (a?.horseName).flatMap { $0.isEmpty ? nil : $0 } ?? top("horseName"),
                                     riderCode: a?.riderCode ?? top("riderCode"), riderName: (a?.riderName).flatMap { $0.isEmpty ? nil : $0 } ?? top("riderName"),
                                     assignedMs: ms)
    }

    var fingerprint: String {
        CloudConfig.fingerprint(localSha256: rawSha256, horseCode: horseCode.isEmpty ? nil : horseCode,
                                riderCode: riderCode.isEmpty ? nil : riderCode, horseName: horseName, riderName: riderName)
    }
}
