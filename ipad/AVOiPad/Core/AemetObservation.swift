import Foundation

/// Tiempo MEDIDO en una estación oficial de AEMET cerca de la pista (petición del usuario 25/11/2026: «una base
/// meteorológica cercana de la playa con datos reales»). AEMET OpenData, observación convencional horaria.
///  - Limitación de AEMET: solo da las observaciones horarias de las últimas ~24 h. Por eso se consulta en cuanto se abre
///    el entrenamiento y lo medido se guarda en el iPad para siempre; si ya no está, se usa el modelo (Open-Meteo), marcado.
///  - Clave de API gratuita y personal (opendata.aemet.es): la pega el usuario en Configuración; se guarda en el Llavero,
///    nunca en el código (repositorio público).
///  - © AEMET: hay que citar a AEMET como autora (se muestra «AEMET <estación>»).
enum AemetConfig {
    static let keychainAccount: String = "aemet-api-key"
    static var apiKey: String? { AvoKeychain.read(keychainAccount) }

    struct Station {
        let idema: String
        let name: String
        let lat: Double
        let lon: Double
    }
    /// Estaciones costeras de AEMET cerca de las pistas de la cuadra (Laredo). Ficha AEMET: Treto 1096X, 10 m, junto a la
    /// ría del Asón; Castro Urdiales 1083L, 45 m. Se usa la más cercana a menos de `maxKm`.
    static let stations: [Station] = [
        Station(idema: "1096X", name: "Treto", lat: 43.3966, lon: -3.4697),
        Station(idema: "1083L", name: "Castro Urdiales", lat: 43.3947, lon: -3.2339),
    ]
    static let maxKm: Double = 25

    static func nearest(_ lat: Double, _ lon: Double) -> (Station, Double)? {
        stations.map { ($0, AemetConfig.km(lat, lon, $0.lat, $0.lon)) }.filter { $0.1 <= maxKm }.min { $0.1 < $1.1 }
    }

    static func km(_ a1: Double, _ o1: Double, _ a2: Double, _ o2: Double) -> Double {
        let r: Double = 6371, d2r: Double = .pi / 180
        let dlat: Double = (a2 - a1) * d2r, dlon: Double = (o2 - o1) * d2r
        let h: Double = sin(dlat / 2) * sin(dlat / 2) + cos(a1 * d2r) * cos(a2 * d2r) * sin(dlon / 2) * sin(dlon / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }
}

/// Una observación horaria medida (unidades ya convertidas).
struct AemetObservation: Codable, Equatable {
    var idema: String
    var station: String
    var distanceKm: Double
    var utc: Date
    var temperatureC: Double?
    var humidityPct: Double?
    var windKmh: Double?
    var windDirDeg: Double?
    var gustKmh: Double?
    var pressureHpa: Double?
    var precipMm: Double?

    /// Texto corto de procedencia (una línea, cabe donde estaba «Modelo, no medición»).
    var sourceLine: String {
        "Medido · AEMET \(station) (\(Int(distanceKm.rounded())) km)"
    }

    /// Lee un elemento del array «datos» de AEMET (fint en UTC, viento en m/s).
    static func parse(_ o: [String: Any], station: AemetConfig.Station, distanceKm: Double) -> AemetObservation? {
        guard let fint = o["fint"] as? String else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        guard let t = f.date(from: String(fint.prefix(19))) else { return nil }
        func num(_ k: String) -> Double? { (o[k] as? NSNumber)?.doubleValue ?? (o[k] as? String).flatMap { Double($0) } }
        return AemetObservation(idema: station.idema, station: station.name, distanceKm: distanceKm, utc: t,
                                temperatureC: num("ta"), humidityPct: num("hr"),
                                windKmh: num("vv").map { $0 * 3.6 }, windDirDeg: num("dv"),
                                gustKmh: num("vmax").map { $0 * 3.6 }, pressureHpa: num("pres"), precipMm: num("prec"))
    }
}

enum AemetError: Error, LocalizedError {
    case noKey, noStation, tooOld, http(Int), invalid
    var errorDescription: String? {
        switch self {
        case .noKey: return "Sin clave de AEMET (Configuración)"
        case .noStation: return "Sin estación de AEMET cerca de la pista"
        case .tooOld: return "AEMET solo guarda las últimas 24 h"
        case .http(let c): return "AEMET respondió \(c)"
        case .invalid: return "Respuesta de AEMET no válida"
        }
    }
}

/// Consulta y guarda (por sesión) la observación medida más cercana al inicio del entrenamiento.
struct AemetService {
    let cacheDir: String
    var session: URLSession = .shared

    private func cachePath(_ sessionId: String) -> String {
        let safe: String = String(sessionId.map { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" ? $0 : "_" }.prefix(120))
        return AvoFiles.join(cacheDir, "aemet_" + safe + ".json")
    }

    func cached(_ sessionId: String) -> AemetObservation? {
        guard let d = FileManager.default.contents(atPath: cachePath(sessionId)) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        return try? dec.decode(AemetObservation.self, from: d)
    }

    private func save(_ sessionId: String, _ o: AemetObservation) {
        AvoFiles.ensureDir(cacheDir)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        if let d = try? enc.encode(o) { try? d.write(to: URL(fileURLWithPath: cachePath(sessionId)), options: .atomic) }
    }

    /// Medida guardada o, si el entrenamiento es de las últimas 24 h, la de AEMET (y se guarda).
    func observation(sessionId: String, start: Date, lat: Double, lon: Double) async throws -> AemetObservation {
        if let c = cached(sessionId) { return c }
        guard let near = AemetConfig.nearest(lat, lon) else { throw AemetError.noStation }
        let st: AemetConfig.Station = near.0, km: Double = near.1
        if Date().timeIntervalSince(start) > 23 * 3600 { throw AemetError.tooOld }
        guard let key = AemetConfig.apiKey, !key.isEmpty else { throw AemetError.noKey }
        // 1) AEMET OpenData devuelve primero un enlace temporal («datos») y después los datos
        guard let u = URL(string: "https://opendata.aemet.es/opendata/api/observacion/convencional/datos/estacion/" + st.idema) else {
            throw AemetError.invalid
        }
        var r = URLRequest(url: u)
        r.setValue(key, forHTTPHeaderField: "api_key")
        r.timeoutInterval = 30
        let (d1, resp1) = try await session.data(for: r)
        let c1: Int = (resp1 as? HTTPURLResponse)?.statusCode ?? 0
        if !(200...299).contains(c1) { throw AemetError.http(c1) }
        guard let o1 = AemetService.json(d1) as? [String: Any], let link = o1["datos"] as? String, let u2 = URL(string: link) else {
            throw AemetError.invalid
        }
        var r2 = URLRequest(url: u2)
        r2.timeoutInterval = 30
        let (d2, resp2) = try await session.data(for: r2)
        let c2: Int = (resp2 as? HTTPURLResponse)?.statusCode ?? 0
        if !(200...299).contains(c2) { throw AemetError.http(c2) }
        guard let arr = AemetService.json(d2) as? [[String: Any]] else { throw AemetError.invalid }
        let obs: [AemetObservation] = arr.compactMap { AemetObservation.parse($0, station: st, distanceKm: km) }
        // la hora medida más cercana al inicio, como mucho a 40 min
        guard let best = obs.min(by: { abs($0.utc.timeIntervalSince(start)) < abs($1.utc.timeIntervalSince(start)) }),
              abs(best.utc.timeIntervalSince(start)) <= 40 * 60, best.temperatureC != nil || best.windKmh != nil else {
            throw AemetError.tooOld
        }
        save(sessionId, best)
        return best
    }

    /// AEMET sirve el JSON en ISO-8859-15 a veces: se decodifica como UTF-8 y, si falla, como Latin-1.
    static func json(_ d: Data) -> Any? {
        if let o = try? JSONSerialization.jsonObject(with: d) { return o }
        guard let s = String(data: d, encoding: .isoLatin1) else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(s.utf8))
    }
}
