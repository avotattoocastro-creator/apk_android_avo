import Foundation

enum ExportService {
    /// Line ending of the Windows writer (StreamWriter.WriteLine on Windows), kept so files are byte-compatible.
    private static let nl = "\r\n"

    static func exportCsv(_ training: TrainingSession, _ fileName: String) throws {
        var text = "tiempo_gps_ms;latitud;longitud;velocidad_kmh;precision_horizontal_m;rtk;altitud_m" + nl
        for p in training.track {
            let fields: [String] = [String(p.gpsWeekMs), num(p.latitude, 7), num(p.longitude, 7), num(p.speedKmh, 3),
                                    num(p.accuracyM, 3), p.rtkName, num(p.altitudeM, 3)]
            text += fields.joined(separator: ";") + nl
        }
        var data = Data([0xEF, 0xBB, 0xBF])   // UTF-8 with BOM, as on Windows (Excel)
        data.append(Data(text.utf8))
        try AvoFiles.writeAtomic(data, to: fileName)
    }

    static func exportGpx(_ training: TrainingSession, _ fileName: String) throws {
        let escaped = xmlEscape(training.sessionId)
        var text = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" + nl
        text += "<gpx version=\"1.1\" creator=\"AVO Performance Horse iPad\" xmlns=\"http://www.topografix.com/GPX/1/1\">" + nl
        text += "<trk><name>\(escaped)</name><trkseg>" + nl
        for p in training.track {
            text += "<trkpt lat=\"\(num(p.latitude, 7))\" lon=\"\(num(p.longitude, 7))\"><ele>\(num(p.altitudeM, 3))</ele></trkpt>" + nl
        }
        text += "</trkseg></trk></gpx>" + nl
        try AvoFiles.writeAtomic(Data(text.utf8), to: fileName)
    }

    static func renderReport(_ s: TrainingSession) -> String {
        func esc(_ x: String?) -> String { htmlEncode(x ?? "—") }
        var h = """
            <!doctype html><html lang="es"><head><meta charset="utf-8" />
            <title>AVO Performance Horse | Informe</title>
            <style>body{font:16px 'Segoe UI',sans-serif;color:#132539;margin:36px}header{border-bottom:4px solid #1587d1;padding:12px 0}h1{font-size:30px}h2{color:#0f76be;margin-top:36px}.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}article{background:#ecf6fc;padding:20px;border-radius:8px}b{display:block;font-size:24px}.note{font-size:13px;color:#566}table{border-collapse:collapse;width:100%}td,th{padding:10px;text-align:left;border-bottom:1px solid #ddd}</style>
            </head><body>
            """
        h += "<header><h1>AVO PERFORMANCE HORSE</h1><p>Informe de entrenamiento · \(esc(s.dateText))</p></header>"
        h += "<h2>\(esc(s.horse)) / \(esc(s.rider))</h2><p>Sesión: \(esc(s.sessionId)) · Archivo: \(esc(s.sourceName))</p>"
        h += "<div class='grid'>"
        h += "<article>Distancia<b>\(AvoFormat.f(s.distanceM / 1000, 2)) km</b></article>"
        h += "<article>Duración<b>\(Analytics.duration(s.durationSeconds))</b></article>"
        h += "<article>Velocidad máxima<b>\(AvoFormat.f(s.maxSpeedKmh, 1)) km/h</b></article>"
        h += "<article>Velocidad media<b>\(AvoFormat.f(s.meanSpeedKmh, 1)) km/h</b></article>"
        h += "<article>GNSS utilizable<b>\(s.gnssSamples - s.unusableGnssSamples)</b></article>"
        h += "<article>RTK FIX<b>\(AvoFormat.f(s.fixPercent, 1)) %</b></article></div>"
        h += "<h2>Calidad e integridad</h2><p>\(esc(s.integrity)) · \(s.segments.count) segmentos · \(s.invalidFrames) tramas rechazadas</p>"
        h += "<h2>Cincha e IMU</h2><p>\(s.totalImuBatches) lotes / \(s.totalImuSamples) muestras registradas. Sin estimar simetría sin calibración validada.</p>"
        let observed: String? = s.marineObservedAt.map { DotNetDate.format($0) }
        h += "<h2>Condiciones marinas</h2><p>Fuente: \(esc(s.marineSource)) · Tipo: \(esc(s.marineKind)) · Hora de referencia: \(esc(observed))</p>"
        h += "<p>Altura: \(format(s.tideHeightM, "m")) · Viento: \(format(s.windKmh, "km/h")) · Olas: \(format(s.waveHeightM, "m")) · \(esc(s.marineNotes))</p>"
        h += "<h2>Tramos de 500 m</h2><table><tr><th>Tramo</th><th>Distancia</th><th>Tiempo</th><th>V. media</th><th>V. máxima</th></tr>"
        for x in Analytics.sections(s) {
            h += "<tr><td>\(x.index)</td><td>\(AvoFormat.f(x.distanceM, 0)) m</td><td>\(Analytics.duration(x.durationS))</td>"
                + "<td>\(AvoFormat.f(x.averageSpeedKmh, 1)) km/h</td><td>\(AvoFormat.f(x.maximumSpeedKmh, 1)) km/h</td></tr>"
        }
        h += "</table><p class='note'>El mapa, la trayectoria y las conclusiones deben revisarse junto a la calidad GNSS/RTK. Distancias derivadas de GNSS de jinete, no del centro de masas del caballo.</p></body></html>"
        return h
    }

    static func exportHtml(_ s: TrainingSession, _ path: String) throws {
        try AvoFiles.writeAtomic(Data(renderReport(s).utf8), to: path)
    }

    // MARK: - helpers

    /// Invariant fixed-point ("F7" / "F3"); C# prints "NaN" for non-finite values.
    private static func num(_ x: Double, _ decimals: Int) -> String {
        x.isFinite ? AvoFormat.inv(x, decimals) : (x.isNaN ? "NaN" : (x > 0 ? "Infinity" : "-Infinity"))
    }

    /// C# value.ToString("0.##", Invariant) + " " + suffix, or "No disponible".
    private static func format(_ value: Double?, _ suffix: String) -> String {
        guard let v = value else { return "No disponible" }
        return ExportService.trimmed(v, 2, decimalComma: false) + " " + suffix
    }

    /// Custom .NET format "0.##…" (up to `maxDecimals`, trailing zeros removed).
    static func trimmed(_ v: Double, _ maxDecimals: Int, decimalComma: Bool) -> String {
        guard v.isFinite else { return v.isNaN ? "NaN" : (v > 0 ? "∞" : "-∞") }
        var s = AvoFormat.inv(v, maxDecimals)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return decimalComma ? s.replacingOccurrences(of: ".", with: ",") : s
    }

    /// System.Security.SecurityElement.Escape.
    static func xmlEscape(_ s: String) -> String {
        var o = ""
        for c in s {
            switch c {
            case "<": o += "&lt;"
            case ">": o += "&gt;"
            case "\"": o += "&quot;"
            case "'": o += "&apos;"
            case "&": o += "&amp;"
            default: o.append(c)
            }
        }
        return o
    }

    /// System.Net.WebUtility.HtmlEncode: &lt; &gt; &amp; &quot; &#39;, and U+00A0–U+00FF / astral characters as &#N;.
    static func htmlEncode(_ s: String) -> String {
        var o = ""
        for u in s.unicodeScalars {
            switch u {
            case "<": o += "&lt;"
            case ">": o += "&gt;"
            case "&": o += "&amp;"
            case "\"": o += "&quot;"
            case "'": o += "&#39;"
            default:
                if (u.value >= 0xA0 && u.value <= 0xFF) || u.value > 0xFFFF { o += "&#\(u.value);" }
                else { o.unicodeScalars.append(u) }
            }
        }
        return o
    }
}
