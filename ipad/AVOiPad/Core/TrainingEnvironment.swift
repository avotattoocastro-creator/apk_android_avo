import Foundation
import CryptoKit

/// Origin of an environmental value. Predictions and models are never shown as measurements.
enum DataKind: String, Codable {
    case prediccion = "Prediccion"
    case modelo = "Modelo"
    case medicion = "Medicion"
}

enum MadridTime {
    static var timeZone: TimeZone { AvoTime.madrid }

    static func format(_ utc: Date?, _ fmt: String = "dd/MM/yyyy HH:mm") -> String {
        guard let u = utc else { return "Sin fecha" }
        return AvoTime.formatter(fmt).string(from: u)
    }

    /// Abbreviation of the offset in force at that instant (CET / CEST).
    static func zoneLabel(_ utc: Date) -> String {
        AvoTime.madrid.isDaylightSavingTime(for: utc) ? "CEST (UTC+2)" : "CET (UTC+1)"
    }
}

/// Reference place of the usual training area. Coordinates are approximate and editable in the settings.
struct TrainingPlace: Equatable, Hashable {
    var name: String
    var latitude: Double
    var longitude: Double

    static let regaton = TrainingPlace(name: "Playa del Regatón, Laredo (Cantabria)", latitude: 43.4247, longitude: -3.4519)
}

struct TideExtreme: Equatable {
    var utc: Date
    var heightM: Double
    var high: Bool
}

struct TidePort: Equatable, Hashable {
    var id: String
    var name: String
    var latitude: Double
    var longitude: Double

    func distanceKmTo(_ lat: Double, _ lon: Double) -> Double {
        Geo.haversineM(latitude, longitude, lat, lon) / 1000
    }
}

struct TideCurvePoint: Equatable {
    var t: Date
    var h: Double
}

/// Official tide prediction of one reference port (never a measurement at the beach).
struct TidePrediction {
    var source: String
    var port: TidePort
    var kind: DataKind { .prediccion }
    var extremes: [TideExtreme]
    var portDistanceKm: Double? = nil

    /// Height between two extremes with cosine interpolation h = a + (b − a)(1 − cos πf)/2 (same as Android Tides.kt).
    func heightAt(_ utc: Date) -> Double? {
        if extremes.count < 2 { return nil }
        for i in 1..<extremes.count {
            let a = extremes[i - 1], b = extremes[i]
            if utc < a.utc || utc > b.utc { continue }
            let span = b.utc.timeIntervalSince(a.utc)
            if span <= 0 || span > 10 * 3600 { return nil }
            let f = utc.timeIntervalSince(a.utc) / span
            return a.heightM + (b.heightM - a.heightM) * (1 - cos(Double.pi * f)) / 2
        }
        return nil
    }

    /// "subiendo" / "bajando" at an instant, or nil outside the data.
    func trendAt(_ utc: Date) -> String? {
        if extremes.count < 2 { return nil }
        for i in 1..<extremes.count where utc >= extremes[i - 1].utc && utc <= extremes[i].utc {
            return extremes[i].high ? "subiendo" : "bajando"
        }
        return nil
    }

    /// Range (m) of the half-cycle containing the instant.
    func rangeAt(_ utc: Date) -> Double? {
        if extremes.count < 2 { return nil }
        for i in 1..<extremes.count where utc >= extremes[i - 1].utc && utc <= extremes[i].utc {
            return abs(extremes[i].heightM - extremes[i - 1].heightM)
        }
        return nil
    }

    /// Tide coefficient approximation used by Android: 70 · range / mean range, clamped 20–120. Needs ≥ 3 days of data.
    func coefficientAt(_ utc: Date) -> Double? {
        guard let r = rangeAt(utc), extremes.count >= 12 else { return nil }
        var ranges: [Double] = []
        for i in 1..<extremes.count { ranges.append(abs(extremes[i].heightM - extremes[i - 1].heightM)) }
        let mean = ranges.reduce(0, +) / Double(ranges.count)
        return mean > 0 ? Swift.min(120, Swift.max(20, 70 * r / mean)) : nil
    }

    func curve(from: Date, to: Date, step: TimeInterval) -> [TideCurvePoint] {
        var out: [TideCurvePoint] = []
        if step <= 0 { return out }
        var t = from
        while t <= to {
            if let h = heightAt(t) { out.append(TideCurvePoint(t: t, h: h)) }
            t = t.addingTimeInterval(step)
        }
        return out
    }
}

/// Shared helpers of the environment parsers (C# JsonElement access).
enum EnvJSON {
    static func parse(_ json: String) throws -> Any {
        guard let data = json.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            throw AvoError.invalidData("Respuesta JSON no válida")
        }
        return o
    }

    /// String value, or the raw text of a number; "" otherwise.
    static func text(_ e: [String: Any], _ k: String) -> String {
        if let s = e[k] as? String { return s }
        if let n = e[k] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.stringValue }
        return ""
    }

    /// C# double.TryParse(text.Replace(',', '.'), NumberStyles.Float, Invariant) && IsFinite.
    static func dbl(_ e: [String: Any], _ k: String) -> Double? {
        parseDouble(text(e, k))
    }

    static func parseDouble(_ s: String) -> Double? {
        let t = s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return nil }
        for c in t.unicodeScalars {
            let ok = (c.value >= 48 && c.value <= 57) || c == "." || c == "-" || c == "+" || c == "e" || c == "E"
            if !ok { return nil }
        }
        guard let v = Double(t), v.isFinite else { return nil }
        return v
    }

    static let minuteUtc: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        f.isLenient = false
        return f
    }()
}

/// Parser and client of the Instituto Hidrográfico de la Marina API (the same public source used by Android).
enum IhmTides {
    static let api = "https://ideihm.covam.es/api-ihm/getmarea"
    static let sourceName = "Instituto Hidrográfico de la Marina (predicción oficial)"

    /// getlist: estaciones.puertos[] {id, puerto, lat, lon} (numbers may come as text).
    static func parsePorts(_ json: String) throws -> [TidePort] {
        let root = try EnvJSON.parse(json)
        var list: [TidePort] = []
        guard let r = root as? [String: Any], let e = r["estaciones"] as? [String: Any], let arr = e["puertos"] as? [Any] else { return list }
        for item in arr {
            guard let p = item as? [String: Any] else { continue }
            if let lat = EnvJSON.dbl(p, "lat"), let lon = EnvJSON.dbl(p, "lon") {
                list.append(TidePort(id: EnvJSON.text(p, "id"), name: EnvJSON.text(p, "puerto"), latitude: lat, longitude: lon))
            }
        }
        return list
    }

    /// gettide (month): mareas.datos.marea[] {fecha "yyyy-MM-dd", hora "HH:mm" UTC, altura (m, decimal comma allowed), tipo}.
    static func parseMonth(_ json: String) throws -> [TideExtreme] {
        let root = try EnvJSON.parse(json)
        var list: [TideExtreme] = []
        guard let r = root as? [String: Any], let m = r["mareas"] as? [String: Any], let datos = m["datos"] as? [String: Any],
              let raw = datos["marea"] else { return list }
        var items: [[String: Any]] = []
        if let a = raw as? [Any] { for x in a { if let o = x as? [String: Any] { items.append(o) } } }
        else if let o = raw as? [String: Any] { items.append(o) }
        for x in items {
            let fecha = EnvJSON.text(x, "fecha")
            var hora = EnvJSON.text(x, "hora")
            while hora.count < 5 { hora = "0" + hora }
            guard let t = EnvJSON.minuteUtc.date(from: "\(fecha)T\(hora)") else { continue }
            guard let h = EnvJSON.parseDouble(EnvJSON.text(x, "altura")) else { continue }
            list.append(TideExtreme(utc: t, heightM: h, high: EnvJSON.text(x, "tipo").lowercased().hasPrefix("plea")))
        }
        return stableSorted(list)
    }

    static func stableSorted(_ list: [TideExtreme]) -> [TideExtreme] {
        let indexed = list.enumerated().map { (i: $0.offset, e: $0.element) }
        return indexed.sorted { (a: (i: Int, e: TideExtreme), b: (i: Int, e: TideExtreme)) -> Bool in
            a.e.utc != b.e.utc ? a.e.utc < b.e.utc : a.i < b.i
        }.map { $0.e }
    }
}

/// Hourly weather / sea state of a numerical model (Open-Meteo archive and marine APIs) — a MODEL, not a measurement.
struct WeatherHour: Equatable {
    var utc: Date
    var temperatureC: Double?
    var windKmh: Double?
    var windGustKmh: Double?
    var windDirDeg: Double?
    var pressureHpa: Double?
    var humidityPct: Double?
    var waveHeightM: Double?
    var wavePeriodS: Double?
}

struct WeatherModel {
    var source: String
    var kind: DataKind { .modelo }
    var latitude: Double
    var longitude: Double
    var hours: [WeatherHour]

    func at(_ utc: Date) -> WeatherHour? {
        var best: WeatherHour? = nil
        var bestMin = Double.greatestFiniteMagnitude
        for h in hours {
            let d = abs(h.utc.timeIntervalSince(utc)) / 60
            if d <= 45 && d < bestMin { bestMin = d; best = h }
        }
        return best
    }

    /// Parses Open-Meteo "hourly" objects (time in GMT, ISO without zone).
    static func parseHourly(_ weatherJson: String?, _ marineJson: String?) throws -> [WeatherHour] {
        var map: [Date: WeatherHour] = [:]
        if let wj = weatherJson {
            let root = try EnvJSON.parse(wj)
            if let r = root as? [String: Any], let h = r["hourly"] as? [String: Any], let times = h["time"] as? [Any] {
                for (i, tt) in times.enumerated() {
                    if let s = tt as? String, let t = EnvJSON.minuteUtc.date(from: s) {
                        map[t] = WeatherHour(utc: t, temperatureC: n(h, "temperature_2m", i), windKmh: n(h, "wind_speed_10m", i),
                                             windGustKmh: n(h, "wind_gusts_10m", i), windDirDeg: n(h, "wind_direction_10m", i),
                                             pressureHpa: n(h, "pressure_msl", i), humidityPct: n(h, "relative_humidity_2m", i),
                                             waveHeightM: nil, wavePeriodS: nil)
                    }
                }
            }
        }
        if let mj = marineJson {
            let root = try EnvJSON.parse(mj)
            if let r = root as? [String: Any], let h = r["hourly"] as? [String: Any], let times = h["time"] as? [Any] {
                for (i, tt) in times.enumerated() {
                    if let s = tt as? String, let t = EnvJSON.minuteUtc.date(from: s) {
                        var base = map[t] ?? WeatherHour(utc: t, temperatureC: nil, windKmh: nil, windGustKmh: nil, windDirDeg: nil,
                                                         pressureHpa: nil, humidityPct: nil, waveHeightM: nil, wavePeriodS: nil)
                        base.waveHeightM = n(h, "wave_height", i)
                        base.wavePeriodS = n(h, "wave_period", i)
                        map[t] = base
                    }
                }
            }
        }
        return map.keys.sorted().compactMap { map[$0] }
    }

    private static func n(_ hourly: [String: Any], _ key: String, _ i: Int) -> Double? {
        guard let arr = hourly[key] as? [Any], i < arr.count else { return nil }
        guard let num = arr[i] as? NSNumber, CFGetTypeID(num) != CFBooleanGetTypeID() else { return nil }
        let d = num.doubleValue
        return d.isFinite ? d : nil
    }
}

/// Cached HTTPS access to the public environment sources. Every response is cached on disk; offline use reads the
/// cache. Failures are reported, never replaced with invented values.
final class EnvironmentService {
    private let cacheDir: String
    private let http: URLSession

    init(cacheDir: String, session: URLSession? = nil) {
        self.cacheDir = cacheDir
        if let s = session {
            http = s
        } else {
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 25
            cfg.httpAdditionalHeaders = ["User-Agent": "AVO-Performance-Horse-iPad/1.0"]
            http = URLSession(configuration: cfg)
        }
    }

    private static let maxResponse = 8_000_000

    private func cached(_ url: String, maxAge: TimeInterval) async throws -> String {
        AvoFiles.ensureDir(cacheDir)
        let hex = AvoHex.upper(SHA256.hash(data: Data(url.utf8)))
        let file = AvoFiles.join(cacheDir, String(hex.prefix(32)) + ".json")
        if AvoFiles.exists(file),
           let attrs = try? FileManager.default.attributesOfItem(atPath: file),
           let modified = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < maxAge,
           let data = AvoFiles.read(file) {
            return String(decoding: data, as: UTF8.self)
        }
        do {
            guard let u = URL(string: url) else { throw AvoError.invalidData("URL no válida") }
            let (bytes, response) = try await http.bytes(for: URLRequest(url: u))
            if let r = response as? HTTPURLResponse, !(200...299).contains(r.statusCode) {
                throw ServicesHttpError(message: "Respuesta HTTP \(r.statusCode)")
            }
            if response.expectedContentLength > Int64(EnvironmentService.maxResponse) {
                throw AvoError.invalidData("Respuesta demasiado grande")
            }
            var body = Data()
            for try await b in bytes {
                body.append(b)
                if body.count > EnvironmentService.maxResponse { throw AvoError.invalidData("Respuesta demasiado grande") }
            }
            let text = String(decoding: body, as: UTF8.self)
            _ = try EnvJSON.parse(text)
            try? AvoFiles.writeAtomic(Data(text.utf8), to: file)
            return text
        } catch {
            // stale cache is better than nothing; the age is shown by the caller
            if AvoFiles.exists(file), let data = AvoFiles.read(file) { return String(decoding: data, as: UTF8.self) }
            throw error
        }
    }

    private static func escapeData(_ s: String) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? s
    }

    func ports() async throws -> [TidePort] {
        try IhmTides.parsePorts(try await cached("\(IhmTides.api)?request=getlist&format=json", maxAge: 7 * 86_400))
    }

    func tides(_ port: TidePort, aroundUtc: Date, placeLat: Double, placeLon: Double) async throws -> TidePrediction {
        let ym = AvoTime.formatter("yyyyMM", utc: true)
        ym.locale = Locale(identifier: "en_US_POSIX")
        let current = ym.string(from: aroundUtc)
        var months: [String] = []
        for d in [aroundUtc.addingTimeInterval(-20 * 86_400), aroundUtc, aroundUtc.addingTimeInterval(20 * 86_400)] {
            let m = ym.string(from: d)
            if !months.contains(m) { months.append(m) }
        }
        var all: [TideExtreme] = []
        for m in months {
            do {
                let url = "\(IhmTides.api)?request=gettide&id=\(EnvironmentService.escapeData(port.id))&month=\(m)&format=json"
                all.append(contentsOf: try IhmTides.parseMonth(try await cached(url, maxAge: 30 * 86_400)))
            } catch {
                if error is CancellationError || Task.isCancelled { throw error }
                if m == current { throw error }
            }
        }
        var seen = Set<Date>()
        var unique: [TideExtreme] = []
        for x in all where !seen.contains(x.utc) { seen.insert(x.utc); unique.append(x) }
        return TidePrediction(source: IhmTides.sourceName, port: port, extremes: IhmTides.stableSorted(unique),
                              portDistanceKm: port.distanceKmTo(placeLat, placeLon))
    }

    func weather(_ lat: Double, _ lon: Double, utc: Date) async throws -> WeatherModel {
        let dayF = AvoTime.formatter("yyyy-MM-dd", utc: true)
        dayF.locale = Locale(identifier: "en_US_POSIX")
        let day = dayF.string(from: utc)
        let la = AvoFormat.inv(lat, 4), lo = AvoFormat.inv(lon, 4)
        let recent = Date().timeIntervalSince(utc) < 5 * 86_400
        let vars = "temperature_2m,wind_speed_10m,wind_gusts_10m,wind_direction_10m,pressure_msl,relative_humidity_2m"
        let wurl = recent
            ? "https://api.open-meteo.com/v1/forecast?latitude=\(la)&longitude=\(lo)&hourly=\(vars)&past_days=5&forecast_days=1&timezone=GMT"
            : "https://archive-api.open-meteo.com/v1/archive?latitude=\(la)&longitude=\(lo)&start_date=\(day)&end_date=\(day)&hourly=\(vars)&timezone=GMT"
        let murl = "https://marine-api.open-meteo.com/v1/marine?latitude=\(la)&longitude=\(lo)&hourly=wave_height,wave_period&start_date=\(day)&end_date=\(day)&timezone=GMT"
        let age: TimeInterval = recent ? 3600 : 30 * 86_400
        var w: String? = nil
        var m: String? = nil
        do { w = try await cached(wurl, maxAge: age) } catch { w = nil }
        do { m = try await cached(murl, maxAge: age) } catch { m = nil }
        if w == nil && m == nil { throw ServicesHttpError(message: "Open-Meteo no disponible y sin copia local") }
        return WeatherModel(source: "Open-Meteo (modelo meteorológico y de oleaje)", latitude: lat, longitude: lon,
                            hours: try WeatherModel.parseHourly(w, m))
    }
}
