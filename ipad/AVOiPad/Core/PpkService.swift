import Foundation
import Compression
import CryptoKit

/// AVO PPK 1.0.0 en el iPad (motor 2.0.0-dev33, docs/PPK.md).
///  - Base: red ERGNSS del IGN, ficheros horarios a 1 s:
///    http://datos-geodesia.ign.es/ERGNSS/horario_1s/AAAAMMDD/HH/<EST>00ESP_R_AAAADDDHH00_01H_01S_MO.crx.gz (+ _01H_MN.rnx.gz)
///    (estructura comprobada por el usuario el 23/11/2026 con capturas; el servidor redirige https → http: excepción ATS
///    solo para datos-geodesia.ign.es en Info.plist, aprobada por el usuario).
///  - La app quita el gzip; el motor expande Hatanaka y calcula con RTKLIB.
///  - Nube: el resultado se guarda junto al entrenamiento como trainings/<CÓDIGO>/AVO_<id>.ppk.json, con el SHA-256 del
///    .avo de origen: la primera app que lo calcula lo sube y las demás lo reutilizan.
enum PpkConfig {
    static let version: String = "1.0.0"
    static let ignRoot: String = "http://datos-geodesia.ign.es/ERGNSS/horario_1s/"
    static let stationKey: String = "avo.ppk.estacion"
    static let maxJsonBytes: Int = 10 * 1024 * 1024

    /// Estación ERGNSS elegida (4 caracteres, p. ej. «SANT»); vacía = sin elegir.
    static var station: String {
        get { (UserDefaults.standard.string(forKey: stationKey) ?? "").uppercased() }
        set { UserDefaults.standard.set(newValue.uppercased(), forKey: stationKey) }
    }

    static func cloudFileName(_ sessionId: String) -> String {
        let avo: String = CloudConfig.fileName(sessionId)
        return String(avo.dropLast(4)) + ".ppk.json"
    }
}

/// Lo que necesita el PPK de una sesión (respuesta de avo_eq_ppk_need).
struct PpkNeed {
    var hasRaw: Bool
    var rawx: Int
    var start: Date?
    var end: Date?
    var lat: Double
    var lon: Double

    static func parse(_ json: String) -> PpkNeed? {
        guard let o = AvoJSON.object(Data(json.utf8)) else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func date(_ k: String) -> Date? {
            guard let s = AvoJSON.string(o, k), !s.isEmpty else { return nil }
            return iso.date(from: s) ?? ISO8601DateFormatter().date(from: s)
        }
        return PpkNeed(hasRaw: AvoJSON.bool(o, "tiene_rawx") ?? false, rawx: Int(AvoJSON.number(o, "rawx") ?? 0),
                       start: date("inicio_utc"), end: date("fin_utc"),
                       lat: AvoJSON.number(o, "lat") ?? 0, lon: AvoJSON.number(o, "lon") ?? 0)
    }

    /// Horas UTC (inicio de cada hora) que cubren la sesión.
    var hours: [Date] {
        guard let s = start, let e = end, e >= s else { return [] }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var h: Date = cal.dateInterval(of: .hour, for: s)?.start ?? s
        var out: [Date] = []
        while h <= e && out.count < 24 {
            out.append(h)
            h = h.addingTimeInterval(3600)
        }
        return out
    }
}

/// Resumen del resultado («avo-ppk») para la pantalla y los metadatos de la nube.
struct PpkSummary: Equatable {
    var epochs: Int
    var fix: Int
    var float: Int
    var pctFix: Double
    var base: String
    var baselineKm: Double
    var warnings: [String]

    static func parse(_ json: String) -> PpkSummary? {
        guard let o = AvoJSON.object(Data(json.utf8)), AvoJSON.string(o, "formato") == "avo-ppk" else { return nil }
        let r: [String: Any] = AvoJSON.dict(o, "resultado") ?? [:]
        let b: [String: Any] = AvoJSON.dict(o, "base") ?? [:]
        return PpkSummary(epochs: Int(AvoJSON.number(r, "epocas") ?? 0), fix: Int(AvoJSON.number(r, "fix") ?? 0),
                          float: Int(AvoJSON.number(r, "float") ?? 0), pctFix: AvoJSON.number(r, "pct_fix") ?? 0,
                          base: AvoJSON.string(b, "nombre") ?? "", baselineKm: AvoJSON.number(b, "linea_base_km") ?? 0,
                          warnings: (AvoJSON.array(o, "avisos") as? [String]) ?? [])
    }
}

enum PpkError: Error, LocalizedError {
    case noRaw
    case noStation
    case notPublished(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noRaw: return "Este entrenamiento no tiene datos RAWX: hace falta grabarlo con la espalda 3.16.0 o posterior."
        case .noStation: return "Elige la estación base del IGN (la más cercana a la pista)."
        case .notPublished(let s): return "El IGN aún no ha publicado la base de \(s). Se publica al terminar cada hora: vuelve a intentarlo más tarde."
        case .failed(let s): return s
        }
    }
}

/// Descargas de la red ERGNSS del IGN.
enum IgnBase {
    private static func utcCalendar() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    static func hourFolder(_ hour: Date) -> String {
        let c = utcCalendar().dateComponents([.year, .month, .day, .hour], from: hour)
        return PpkConfig.ignRoot + String(format: "%04d%02d%02d/%02d/", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0)
    }

    /// Parte de fecha del nombre RINEX 3: AAAADDDHH00.
    static func stamp(_ hour: Date) -> String {
        let cal = utcCalendar()
        let c = cal.dateComponents([.year, .hour], from: hour)
        let doy: Int = cal.ordinality(of: .day, in: .year, for: hour) ?? 0
        return String(format: "%04d%03d%02d00", c.year ?? 0, doy, c.hour ?? 0)
    }

    /// Nombres de fichero del índice HTML de una carpeta horaria.
    static func listFiles(_ hour: Date, session: URLSession = .shared) async throws -> [String] {
        guard let u = URL(string: hourFolder(hour)) else { return [] }
        var r = URLRequest(url: u)
        r.timeoutInterval = 60
        let (data, resp) = try await session.data(for: r)
        let code: Int = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { return [] }
        if !(200...299).contains(code) { throw PpkError.failed("IGN: el servidor respondió \(code)") }
        let html: String = String(decoding: data, as: UTF8.self)
        guard let re = try? NSRegularExpression(pattern: "href=\"([A-Za-z0-9_.]+\\.(?:crx|rnx)\\.gz)\"") else { return [] }
        let ns = html as NSString
        return re.matches(in: html, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }

    /// Estaciones con observación a 1 s en esa hora (código de 4 caracteres), ordenadas.
    static func stations(_ hour: Date) async throws -> [String] {
        let files: [String] = try await listFiles(hour)
        let set = Set(files.filter { $0.hasSuffix("_01H_01S_MO.crx.gz") }.map { String($0.prefix(4)).uppercased() })
        return set.sorted()
    }

    /// Descarga (sin gzip) la observación y la navegación de `station` para cada hora. Devuelve las rutas RINEX.
    static func download(station: String, hours: [Date], into dir: String, session: URLSession = .shared) async throws -> [String] {
        AvoFiles.ensureDir(dir)
        var out: [String] = []
        let sta: String = station.uppercased()
        for h in hours {
            let files: [String] = try await listFiles(h, session: session)
            let stamp: String = stamp(h)
            let obs: String? = files.first { $0.uppercased().hasPrefix(sta) && $0.contains("_R_" + stamp) && $0.hasSuffix("_01H_01S_MO.crx.gz") }
            guard let o = obs else {
                let f = DateFormatter()
                f.timeZone = TimeZone(identifier: "UTC")
                f.dateFormat = "dd/MM/yyyy HH:00 'UTC'"
                if h.addingTimeInterval(3 * 3600) > Date() { throw PpkError.notPublished(f.string(from: h)) }
                throw PpkError.failed("El IGN no tiene datos de \(sta) a las \(f.string(from: h)). Elige otra estación.")
            }
            let nav: String? = files.first { $0.uppercased().hasPrefix(sta) && $0.contains("_R_" + stamp) && $0.hasSuffix("_01H_MN.rnx.gz") }
            for name in [o, nav].compactMap({ $0 }) {
                let target: String = AvoFiles.join(dir, String(name.dropLast(3)))
                if FileManager.default.fileExists(atPath: target) { out.append(target); continue }
                guard let u = URL(string: hourFolder(h) + name) else { continue }
                var done: Bool = false
                var skip: Bool = false
                for attempt in 0..<2 {   // 27/11/2026: una descarga cortada se repite una vez, sin caché
                    var r = URLRequest(url: u)
                    r.timeoutInterval = 300
                    if attempt > 0 { r.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData; try await Task.sleep(nanoseconds: 2_000_000_000) }
                    let (data, resp) = try await session.data(for: r)
                    let code: Int = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    if !(200...299).contains(code) {
                        if name == o { throw PpkError.failed("IGN: \(name) respondió \(code)") }
                        skip = true   // navegación: sin ella el PPK solo funciona si la sesión trae SFRBX (espalda < 3.16.2)
                        break
                    }
                    // 27/11/2026: descomprime el motor (mismo código en todas las apps, comprueba CRC-32/ISIZE de cada miembro)
                    do { try EquineEngine.gunzip(data, to: target); done = true; break } catch {
                        if attempt == 1 {
                            throw PpkError.failed("La base del IGN (\(name)) no se pudo descomprimir: \(error.localizedDescription) (\(data.count) B). Vuelve a intentarlo en unos minutos.")
                        }
                    }
                }
                if skip { continue }
                guard done else { continue }
                out.append(target)
            }
        }
        return out
    }
}

/// gzip (RFC 1952) con el framework Compression (deflate en bruto). Varios miembros seguidos se concatenan.
enum Gzip {
    static func decompress(_ data: Data) throws -> Data {
        var out = Data()
        var pos: Int = 0
        let bytes = [UInt8](data)
        while pos + 18 <= bytes.count {
            guard bytes[pos] == 0x1F, bytes[pos + 1] == 0x8B, bytes[pos + 2] == 8 else {
                if out.isEmpty { throw PpkError.failed("El fichero de la base no es gzip") }
                break
            }
            let flg: UInt8 = bytes[pos + 3]
            var p: Int = pos + 10
            if flg & 0x04 != 0 {   // FEXTRA
                guard p + 2 <= bytes.count else { throw PpkError.failed("gzip cortado") }
                p += 2 + Int(bytes[p]) + Int(bytes[p + 1]) << 8
            }
            if flg & 0x08 != 0 { while p < bytes.count && bytes[p] != 0 { p += 1 }; p += 1 }   // FNAME
            if flg & 0x10 != 0 { while p < bytes.count && bytes[p] != 0 { p += 1 }; p += 1 }   // FCOMMENT
            if flg & 0x02 != 0 { p += 2 }                                                     // FHCRC
            guard p < bytes.count else { throw PpkError.failed("gzip cortado") }
            let (member, used, ended) = try inflate(Array(bytes[p...]))
            let next: Int = nextMember(bytes, from: p, used: used, size: member.count)
            if !ended {
                // 27/11/2026: el framework Compression puede consumir toda la entrada sin devolver END aunque el flujo esté
                // completo. Se da por bueno si el pie del miembro (CRC-32 + ISIZE) coincide con lo descomprimido.
                guard trailerMatches(bytes, end: next, data: member) else { throw PpkError.failed("gzip cortado") }
            }
            out.append(member)
            pos = next
        }
        if out.isEmpty { throw PpkError.failed("gzip vacío") }
        return out
    }

    /// Inicio del miembro siguiente. El framework Compression puede dar por consumida toda la entrada aunque el flujo
    /// deflate acabe antes, así que `used` no es fiable: se acepta p + used + 8 si ahí empieza una cabecera gzip y, si no,
    /// se busca la siguiente cabecera 1F 8B 08 cuyo ISIZE previo (4 bytes LE) coincide con el tamaño descomprimido.
    static func nextMember(_ b: [UInt8], from p: Int, used: Int, size: Int) -> Int {
        func isHeader(_ q: Int) -> Bool { q >= 0 && q + 3 <= b.count && b[q] == 0x1F && b[q + 1] == 0x8B && b[q + 2] == 8 }
        let direct: Int = p + used + 8   // CRC32 + ISIZE
        if isHeader(direct) { return direct }
        let isize: UInt32 = UInt32(truncatingIfNeeded: size)
        var q: Int = p + 8
        while q + 3 <= b.count {
            if isHeader(q) {
                let v: UInt32 = UInt32(b[q - 4]) | UInt32(b[q - 3]) << 8 | UInt32(b[q - 2]) << 16 | UInt32(b[q - 1]) << 24
                if v == isize { return q }
            }
            q += 1
        }
        return b.count   // último miembro
    }

    /// Pie gzip del miembro que acaba en `end`: CRC-32 (4 B LE) + ISIZE (4 B LE) igual a los datos descomprimidos.
    static func trailerMatches(_ b: [UInt8], end: Int, data: Data) -> Bool {
        let t: Int = end - 8
        guard t >= 0, end <= b.count else { return false }
        func le(_ q: Int) -> UInt32 { UInt32(b[q]) | UInt32(b[q + 1]) << 8 | UInt32(b[q + 2]) << 16 | UInt32(b[q + 3]) << 24 }
        return le(t) == crc32(data) && le(t + 4) == UInt32(truncatingIfNeeded: data.count)
    }

    private static let crcTable: [UInt32] = (0..<256).map { (i: Int) -> UInt32 in
        var c: UInt32 = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    /// CRC-32 (ISO-HDLC, el de gzip).
    static func crc32(_ d: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        d.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for x in raw { c = crcTable[Int((c ^ UInt32(x)) & 0xFF)] ^ (c >> 8) }
        }
        return c ^ 0xFFFF_FFFF
    }

    /// Deflate en bruto; devuelve los datos, los bytes de entrada consumidos y si el flujo terminó (END).
    private static func inflate(_ src: [UInt8]) throws -> (Data, Int, Bool) {
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw PpkError.failed("No se pudo iniciar la descompresión")
        }
        defer { compression_stream_destroy(stream) }
        let chunk: Int = 1 << 20
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer { dst.deallocate() }
        var out = Data()
        var used: Int = 0
        var ended: Bool = false
        try src.withUnsafeBufferPointer { (sb: UnsafeBufferPointer<UInt8>) in
            guard let base = sb.baseAddress else { return }
            stream.pointee.src_ptr = base
            stream.pointee.src_size = sb.count
            while true {
                stream.pointee.dst_ptr = dst
                stream.pointee.dst_size = chunk
                let st: compression_status = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                out.append(dst, count: chunk - stream.pointee.dst_size)
                if st == COMPRESSION_STATUS_END { ended = true; break }
                if st != COMPRESSION_STATUS_OK { throw PpkError.failed("Datos gzip dañados") }
                if stream.pointee.dst_size != 0 && stream.pointee.src_size == 0 { break }   // sin END: lo decide el pie gzip
            }
            used = sb.count - stream.pointee.src_size
        }
        return (out, used, ended)
    }
}

/// Resultados PPK guardados en el iPad (uno por sesión).
struct PpkStore {
    let dir: String

    init(paths: AppPaths) { dir = AvoFiles.join(paths.root, "ppk") }

    func path(_ sessionId: String) -> String { AvoFiles.join(dir, PpkConfig.cloudFileName(sessionId)) }
    var baseDir: String { AvoFiles.join(dir, "base_ign") }

    func load(_ sessionId: String) -> String? {
        guard let d = FileManager.default.contents(atPath: path(sessionId)) else { return nil }
        let s = String(decoding: d, as: UTF8.self)
        return PpkSummary.parse(s) != nil ? s : nil
    }

    func save(_ sessionId: String, _ json: String) throws {
        AvoFiles.ensureDir(dir)
        try Data(json.utf8).write(to: URL(fileURLWithPath: path(sessionId)), options: .atomic)
    }
}

/// Nube AVO: el resultado PPK junto al .avo (trainings/<CÓDIGO>/AVO_<id>.ppk.json).
extension AvoCloudClient {
    private static func ppkURL(_ path: String, media: Bool) -> URL? {
        var allowed: CharacterSet = .alphanumerics
        allowed.insert(charactersIn: "-._~")
        let enc: String = path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
        return URL(string: "https://firebasestorage.googleapis.com/v0/b/\(CloudConfig.bucket)/o/\(enc)" + (media ? "?alt=media" : ""))
    }

    /// Descarga el PPK de la nube si existe y corresponde al .avo `avoSha256` (vacío = no comprobar). nil si no hay.
    func downloadPpk(code: String, sessionId: String, avoSha256: String) async throws -> String? {
        let tk: String = try await token()
        let path: String = CloudConfig.folder(code) + PpkConfig.cloudFileName(sessionId)
        guard let mu = AvoCloudClient.ppkURL(path, media: false), let du = AvoCloudClient.ppkURL(path, media: true) else { return nil }
        var r = URLRequest(url: mu)
        r.setValue("Firebase " + tk, forHTTPHeaderField: "Authorization")
        let (md, mresp) = try await URLSession.shared.data(for: r)
        let code1: Int = (mresp as? HTTPURLResponse)?.statusCode ?? 0
        if code1 == 404 { return nil }
        if !(200...299).contains(code1) { throw LiveFirebaseError("Nube: el servidor respondió \(code1) (PPK)") }
        let meta: [String: Any] = AvoJSON.dict(AvoJSON.object(md) ?? [:], "metadata") ?? [:]
        let src: String = (AvoJSON.string(meta, "avo_sha256") ?? "").lowercased()
        if !avoSha256.isEmpty && !src.isEmpty && src != avoSha256.lowercased() { return nil }   // de otra versión del .avo: recalcular
        var d = URLRequest(url: du)
        d.setValue("Firebase " + tk, forHTTPHeaderField: "Authorization")
        let (data, dresp) = try await URLSession.shared.data(for: d)
        let code2: Int = (dresp as? HTTPURLResponse)?.statusCode ?? 0
        if !(200...299).contains(code2) { return nil }
        let sha: String = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if let want = AvoJSON.string(meta, "sha256"), !want.isEmpty, want.lowercased() != sha { return nil }
        let s = String(decoding: data, as: UTF8.self)
        return PpkSummary.parse(s) != nil ? s : nil
    }

    /// Sube el PPK junto al .avo (mismas reglas de dueño que el .avo; firebase/storage.rules).
    func uploadPpk(json: String, code: String, sessionId: String, avoSha256: String) async throws {
        let tk: String = try await token()
        let data = Data(json.utf8)
        if data.count > PpkConfig.maxJsonBytes { throw LiveFirebaseError("Nube: PPK de más de 10 MB") }
        let s: PpkSummary? = PpkSummary.parse(json)
        let name: String = CloudConfig.folder(code) + PpkConfig.cloudFileName(sessionId)
        let meta: [String: String] = [
            "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            "avo_sha256": avoSha256.lowercased(), "sessionId": sessionId, "ppk_version": PpkConfig.version,
            "base": s?.base ?? "", "pct_fix": String(format: "%.1f", s?.pctFix ?? 0), "app": "ipad"]
        let head: [String: Any] = ["name": name, "contentType": "application/json", "metadata": meta]
        let boundary: String = "avo" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Type: application/json; charset=utf-8\r\n\r\n".utf8))
        body.append(try JSONSerialization.data(withJSONObject: head))
        body.append(Data("\r\n--\(boundary)\r\nContent-Type: application/json\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--".utf8))
        var c = URLComponents(string: "https://firebasestorage.googleapis.com/v0/b/\(CloudConfig.bucket)/o")!
        c.queryItems = [URLQueryItem(name: "name", value: name)]
        var r = URLRequest(url: c.url!)
        r.httpMethod = "POST"
        r.setValue("Firebase " + tk, forHTTPHeaderField: "Authorization")
        r.setValue("multipart", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        r.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        r.timeoutInterval = 300
        let (_, resp) = try await URLSession.shared.upload(for: r, from: body)
        let code2: Int = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code2 == 401 || code2 == 403 { throw LiveFirebaseError("Nube: sin permiso para subir el PPK. ¿Están publicadas las reglas de Storage nuevas (firebase/storage.rules)?") }
        if !(200...299).contains(code2) { throw LiveFirebaseError("Nube: el servidor respondió \(code2) (subir PPK)") }
    }
}
