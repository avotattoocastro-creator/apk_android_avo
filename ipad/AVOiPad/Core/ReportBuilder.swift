import Foundation

/// Sections a report may include ([Flags] enum of the Windows app).
struct ReportSections: OptionSet, Equatable {
    let rawValue: Int
    init(rawValue: Int) { self.rawValue = rawValue }

    static let none: ReportSections = ReportSections(rawValue: 0)
    static let general: ReportSections = ReportSections(rawValue: 1)
    static let horseRider: ReportSections = ReportSections(rawValue: 2)
    static let dateDuration: ReportSections = ReportSections(rawValue: 4)
    static let map: ReportSections = ReportSections(rawValue: 8)
    static let gnssStats: ReportSections = ReportSections(rawValue: 16)
    static let speedAccel: ReportSections = ReportSections(rawValue: 32)
    static let charts: ReportSections = ReportSections(rawValue: 64)
    static let segments: ReportSections = ReportSections(rawValue: 128)
    static let biomechanics: ReportSections = ReportSections(rawValue: 256)
    static let comparison: ReportSections = ReportSections(rawValue: 512)
    static let tides: ReportSections = ReportSections(rawValue: 1024)
    static let notes: ReportSections = ReportSections(rawValue: 2048)
    static let all: ReportSections = ReportSections(rawValue: 4095)
}

/// Everything a report may contain. Missing parts are printed as «Sin datos» / «No disponible».
struct ReportData {
    var session: TrainingSession
    var timeline: SessionTimeline
    var engine: EquineAnalysis?
    var segments: [SegmentMetrics]
    var comparison: [SeriesAligner.SessionSummary]
    var tides: TidePrediction?
    var weather: WeatherModel?
    var notes: String
    var sections: ReportSections

    init(session: TrainingSession, timeline: SessionTimeline, engine: EquineAnalysis? = nil, segments: [SegmentMetrics] = [],
         comparison: [SeriesAligner.SessionSummary] = [], tides: TidePrediction? = nil, weather: WeatherModel? = nil,
         notes: String = "", sections: ReportSections = .all) {
        self.session = session
        self.timeline = timeline
        self.engine = engine
        self.segments = segments
        self.comparison = comparison
        self.tides = tides
        self.weather = weather
        self.notes = notes
        self.sections = sections
    }
}

enum ReportBuilder {
    static let ink: AvoRGB = (r: 0x10, g: 0x10, b: 0x14)
    static let dim: AvoRGB = (r: 0x5B, g: 0x5C, b: 0x63)
    static let red: AvoRGB = (r: 0xED, g: 0x12, b: 0x2A)
    static let lineColor: AvoRGB = (r: 0xD8, g: 0xD9, b: 0xDE)
    static let panel: AvoRGB = (r: 0xF3, g: 0xF3, b: 0xF5)
    static let dark: AvoRGB = (r: 0x10, g: 0x10, b: 0x14)
    static let blue: AvoRGB = (r: 0x3D, g: 0x9B, b: 0xFF)
    static let white: AvoRGB = (r: 0xFF, g: 0xFF, b: 0xFF)

    static func num(_ v: Double?, _ fmt: String, _ unit: String = "") -> String { TimeText.num(v, fmt, unit) }

    /// C# MadridTime.Format(utc, fmt) with .NET date patterns ("dddd" = full day name), es-ES, Europe/Madrid.
    static func madrid(_ utc: Date?, _ fmt: String = "dd/MM/yyyy HH:mm") -> String {
        guard let u = utc else { return "Sin fecha" }
        let pattern: String = fmt.replacingOccurrences(of: "dddd", with: "EEEE")
        let f: DateFormatter = AvoTime.formatter(pattern)
        f.calendar = Calendar(identifier: .gregorian)
        return f.string(from: u)
    }

    static func whole(_ d: ReportData) -> SegmentMetrics? {
        let tl: SessionTimeline = d.timeline
        if tl.count < 2 { return nil }
        let def = SegmentDefinition(name: "Sesión", t0: tl.t[0], t1: tl.t[tl.count - 1])
        return SegmentAnalyzer.compute(tl, def, engine: d.engine)
    }

    // ------------------------------------------------------------------------------------------------ PDF

    /// Complete PDF report (bytes).
    static func writePdf(_ d: ReportData) -> Data {
        let w = PdfReportWriter(d)
        return w.build()
    }

    static func writePdf(_ d: ReportData, to path: String) throws {
        try AvoFiles.writeAtomic(writePdf(d), to: path)
    }

    fileprivate static func drawRoute(_ pdf: PdfDocument, _ tl: SessionTimeline, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        pdf.fillRect(x, y, w, h, (r: 0xEC, g: 0xED, b: 0xF0))
        pdf.strokeRect(x, y, w, h, lineColor)
        var minLat: Double = Double.infinity
        var maxLat: Double = -Double.infinity
        var minLon: Double = Double.infinity
        var maxLon: Double = -Double.infinity
        for i in 0..<tl.count {
            minLat = min(minLat, tl.lat[i]); maxLat = max(maxLat, tl.lat[i])
            minLon = min(minLon, tl.lon[i]); maxLon = max(maxLon, tl.lon[i])
        }
        let zoom: Double = TileMath.fitZoom(minLat, minLon, maxLat, maxLon, w, h, padding: 24)
        let c0 = TileMath.latLonToPixel((minLat + maxLat) / 2, (minLon + maxLon) / 2, zoom)
        func p(_ i: Int) -> (x: Double, y: Double) {
            let q = TileMath.latLonToPixel(tl.lat[i], tl.lon[i], zoom)
            return (x: x + w / 2 + (q.x - c0.x), y: y + h / 2 + (q.y - c0.y))
        }
        let vmax: Double = max(0.1, Stats.maxFinite(tl.speedFiltered, fallback: 0.1))
        if tl.count > 1 {
            for i in 1..<tl.count {
                if tl.breakBefore[i] || tl.jumpBefore[i] { continue }
                let a = p(i - 1)
                let b = p(i)
                pdf.line(a.x, a.y, b.x, b.y, SpeedScale.color(tl.speedFiltered[i], vmax), width: 2.2)
            }
        }
        let s0 = p(0)
        let s1 = p(tl.count - 1)
        pdf.circle(s0.x, s0.y, 4.5, (r: 0x52, g: 0xDD, b: 0x40))
        pdf.circle(s1.x, s1.y, 4.5, red)
        pdf.text(s0.x + 7, s0.y - 5, "Inicio", size: 7.5, bold: true, color: ink)
        pdf.text(s1.x + 7, s1.y - 5, "Fin", size: 7.5, bold: true, color: ink)
        // scale bar
        let mpp: Double = TileMath.metersPerPixel((minLat + maxLat) / 2, zoom)
        let target: Double = mpp * 100
        let candidates: [Double] = [10, 20, 50, 100, 200, 500, 1000, 2000, 5000]
        var nice: Double = candidates[0]
        var bestDiff: Double = abs(candidates[0] - target)
        for v in candidates.dropFirst() where abs(v - target) < bestDiff { nice = v; bestDiff = abs(v - target) }
        let px: Double = nice / mpp
        pdf.fillRect(x + 12, y + h - 18, px, 3, ink)
        let label: String = nice >= 1000 ? DotNetFormat.custom(nice / 1000, "0", spanish: true) + " km" : DotNetFormat.custom(nice, "0", spanish: true) + " m"
        pdf.text(x + 12, y + h - 32, label, size: 7.5, bold: true, color: ink)
        pdf.text(x + w - 14, y + 10, "N", size: 10, bold: true, color: ink, align: .center)
        pdf.line(x + w - 14, y + 24, x + w - 14, y + 40, ink, width: 1.2)
    }

    fileprivate static func chart(_ pdf: PdfDocument, _ title: String, _ t: [Double], _ series: [[Double]], _ colors: [AvoRGB],
                                  _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ breaks: [Bool]) {
        pdf.text(x, y, title, size: 8.5, bold: true, color: ink)
        let top: Double = y + 14
        let ch: Double = h - 14
        pdf.fillRect(x, top, w, ch, (r: 0xF7, g: 0xF7, b: 0xF9))
        let t0: Double = t[0]
        let t1: Double = t[t.count - 1]
        var lo: Double = Double.infinity
        var hi: Double = -Double.infinity
        for s in series {
            lo = min(lo, Stats.minFinite(s, fallback: 0))
            hi = max(hi, Stats.maxFinite(s, fallback: 1))
        }
        if hi - lo < 1e-6 { hi += 1; lo -= 1 }
        let pad: Double = (hi - lo) * 0.08
        lo -= pad
        hi += pad
        for g in 0...4 {
            let gy: Double = top + ch * Double(g) / 4
            pdf.line(x, gy, x + w, gy, lineColor, width: 0.3)
            let label: String = DotNetFormat.custom(hi - (hi - lo) * Double(g) / 4, "0.#", spanish: true)
            pdf.text(x + 2, gy - (g == 0 ? -1 : 9), label, size: 6.5, bold: false, color: dim)
        }
        var si: Int = series.count - 1
        while si >= 0 {
            let idx: [Int] = Downsampler.lttb(t, series[si], 900)
            var pts: [(x: Double, y: Double)] = []
            pts.reserveCapacity(idx.count + 8)
            var prev: Int = -1
            for i in idx {
                if prev >= 0 {
                    var anyBreak: Bool = false
                    var k: Int = prev + 1
                    while k <= i { if breaks[k] { anyBreak = true; break }; k += 1 }
                    if anyBreak { pts.append((x: .nan, y: .nan)) }
                }
                pts.append((x: x + (t[i] - t0) / max(t1 - t0, 1e-6) * w, y: top + (hi - series[si][i]) / (hi - lo) * ch))
                prev = i
            }
            pdf.polyline(pts, colors[si], width: si == 0 ? 1.1 : 0.7)
            si -= 1
        }
        pdf.text(x + w, top + ch + 2, TimeText.clock(t1 - t0), size: 6.5, bold: false, color: dim, align: .right)
        pdf.text(x, top + ch + 2, "0:00", size: 6.5, bold: false, color: dim)
    }

    // ------------------------------------------------------------------------------------------------ HTML (printable)

    static func html(_ d: ReportData) -> String {
        func e(_ s: String?) -> String { DotNetText.htmlEncode(s ?? "—") }
        func kv(_ k: String, _ v: String) -> String {
            "<tr><td>\(DotNetText.htmlEncode(k))</td><td><b>\(DotNetText.htmlEncode(v))</b></td></tr>"
        }
        func tile(_ k: String, _ v: String) -> String {
            "<div class=\"tile\"><small>\(DotNetText.htmlEncode(k))</small><div>\(DotNetText.htmlEncode(v))</div></div>"
        }
        let s: TrainingSession = d.session
        let tl: SessionTimeline = d.timeline
        let wm0: SegmentMetrics? = whole(d)
        var sb: String = ""
        sb += "<!doctype html><html lang=\"es\"><head><meta charset=\"utf-8\"><title>AVO Performance Horse · Informe</title><style>"
        sb += "body{font:14px 'Segoe UI',Arial,sans-serif;color:#101014;margin:0}header{background:#101014;color:#fff;padding:22px 40px;border-bottom:4px solid #ED122A}"
        sb += "header b{font-size:34px;letter-spacing:2px}header span{color:#C9CBD1;margin-left:14px;font-weight:600}main{padding:10px 40px 40px}h2{color:#ED122A;font-size:15px;text-transform:uppercase;border-bottom:1px solid #D8D9DE;padding-bottom:6px;margin-top:28px}"
        sb += ".tiles{display:grid;grid-template-columns:repeat(4,1fr);gap:12px}.tile{background:#F3F3F5;border-left:4px solid #ED122A;padding:10px 14px}.tile small{color:#5B5C63;text-transform:uppercase;font-weight:700;font-size:11px}.tile div{font-size:24px;font-weight:700}"
        sb += "table{border-collapse:collapse;width:100%;font-size:12px}th{background:#101014;color:#fff;text-align:left;padding:6px}td{padding:5px 6px;border-bottom:1px solid #E4E4E8}.kv td:first-child{color:#5B5C63;width:38%}"
        sb += ".note{color:#5B5C63;font-size:12px}.demo{background:#FFF1C9;color:#7A5200;padding:8px 12px;font-weight:700;margin-top:12px}svg{background:#F3F3F5;width:100%;height:auto}@media print{header{-webkit-print-color-adjust:exact;print-color-adjust:exact}}</style></head><body>"
        sb += "<header><b>AVO</b><span>PERFORMANCE HORSE · Informe de entrenamiento</span><div style=\"float:right;text-align:right;color:#C9CBD1\">"
        sb += e(madrid(tl.utc0 ?? s.startedAt))
        sb += " (Europe/Madrid)<br>Sesión "
        sb += e(s.sessionId)
        sb += "</div></header><main>"
        if s.isSynthetic { sb += "<div class=\"demo\">DEMOSTRACIÓN — DATOS SINTÉTICOS. No corresponde a un entrenamiento medido.</div>" }
        sb += "<h2>Datos generales</h2><table class=\"kv\">"
        sb += kv("Caballo", s.horse)
        sb += kv("Jinete", s.rider)
        sb += kv("Fecha", madrid(tl.utc0 ?? s.startedAt, "dddd dd/MM/yyyy HH:mm"))
        sb += kv("Duración", TimeText.clock(tl.count > 1 ? tl.durationS : s.durationSeconds))
        sb += kv("Integridad", s.integrity)
        sb += "</table>"
        sb += "<div class=\"tiles\" style=\"margin-top:14px\">"
        let wholeKm: Double? = wm0.map { $0.distanceM / 1000 }
        let wholeFix: Double? = wm0.map { $0.fixFraction * 100 }
        sb += tile("Distancia", num(wholeKm, "0.00", " km"))
        sb += tile("Vel. media", num(wm0?.meanSpeedKmh, "0.0", " km/h"))
        sb += tile("Vel. máxima", num(wm0?.maxSpeedKmh, "0.0", " km/h"))
        sb += tile("RTK FIX", num(wholeFix, "0", " %"))
        sb += "</div>"
        if d.sections.contains(.map) && tl.count > 1 {
            sb += "<h2>Recorrido</h2>"
            sb += routeSvg(tl)
            sb += "<p class=\"note\">Posiciones del chaleco GNSS del jinete; color por velocidad filtrada (azul → cian → amarillo → rojo).</p>"
        }
        if d.sections.contains(.segments) && !d.segments.isEmpty {
            sb += "<h2>Tramos</h2><table><tr><th>Tramo</th><th>Inicio</th><th>Fin</th><th>Distancia</th><th>Duración</th><th>V. máx</th><th>V. media</th><th>Acel. máx</th><th>Desac. máx</th><th>RTK FIX</th><th>Observaciones</th></tr>"
            for m in d.segments {
                let cells: [String] = [
                    e(m.name), TimeText.clock(m.t0), TimeText.clock(m.t1), num(m.distanceM, "0", " m"), TimeText.clock(m.durationS),
                    num(m.maxSpeedKmh, "0.0", " km/h"), num(m.meanSpeedKmh, "0.0", " km/h"), num(m.maxAccel, "0.00", " m/s²"),
                    num(m.maxDecel, "0.00", " m/s²"), num(m.fixFraction * 100, "0", " %"), e(m.observations),
                ]
                sb += "<tr><td>"
                sb += cells.joined(separator: "</td><td>")
                sb += "</td></tr>"
            }
            sb += "</table>"
        }
        if d.sections.contains(.biomechanics) {
            sb += "<h2>Biomecánica</h2>"
            if let eng = d.engine, eng.hasImu {
                sb += "<table class=\"kv\">"
                sb += kv("Cadencia media", num(AnalysisForeignAPI.metric(eng, "cadencia_media_imu0"), "0", " ciclos/min"))
                sb += kv("Correlación entre ciclos", num(AnalysisForeignAPI.metric(eng, "correlacion_entre_ciclos_imu0"), "0.00"))
                sb += kv("Simetría (exploratoria)", eng.symmetryLabel)
                sb += "</table><p class=\"note\">Índices exploratorios de IMU sin calibrar; no son diagnóstico clínico.</p>"
            } else {
                sb += "<p>Sin datos de cincha: no se calculan cadencia, regularidad ni simetría.</p>"
            }
        }
        if d.sections.contains(.tides) && (d.tides != nil || d.weather != nil) {
            sb += "<h2>Mareas y entorno</h2><table class=\"kv\">"
            let t0: Date? = tl.utc0 ?? s.startedAt
            if let tp = d.tides, let u = t0 {
                let trend: String = AnalysisForeignAPI.tideTrend(tp, u) ?? "sin datos"
                let height: String = num(AnalysisForeignAPI.tideHeight(tp, u), "0.00", " m")
                let text: String = "\(height) · \(trend) · \(tp.port.name) (\(tp.source))"
                sb += kv("Marea (predicción)", text)
            }
            if let wm = d.weather, let u2 = t0, let h = AnalysisForeignAPI.weatherAt(wm, u2) {
                let p1: String = num(h.temperatureC, "0.0", " °C")
                let p2: String = num(h.windKmh, "0", " km/h")
                let p3: String = num(h.pressureHpa, "0", " hPa")
                let p4: String = num(h.waveHeightM, "0.0", " m")
                let text: String = "\(p1) · viento \(p2) · \(p3) · oleaje \(p4) (\(wm.source))"
                sb += kv("Meteorología (modelo)", text)
            }
            sb += "</table>"
        }
        if d.sections.contains(.notes) && !d.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sb += "<h2>Notas</h2><p>" + e(d.notes).replacingOccurrences(of: "\n", with: "<br>") + "</p>"
        }
        sb += "<p class=\"note\" style=\"margin-top:30px\">GNSS del chaleco del jinete; no es un punto anatómico del caballo. Generado por AVO Performance Horse — Windows Advanced Analysis V2 PRO.</p></main></body></html>"
        return sb
    }

    static func writeHtml(_ d: ReportData, to path: String) throws {
        try AvoFiles.writeAtomic(Data(html(d).utf8), to: path)
    }

    static func routeSvg(_ tl: SessionTimeline, _ w: Int = 900, _ h: Int = 420) -> String {
        var minLat: Double = Double.infinity
        var maxLat: Double = -Double.infinity
        var minLon: Double = Double.infinity
        var maxLon: Double = -Double.infinity
        for i in 0..<tl.count {
            minLat = min(minLat, tl.lat[i]); maxLat = max(maxLat, tl.lat[i])
            minLon = min(minLon, tl.lon[i]); maxLon = max(maxLon, tl.lon[i])
        }
        let wd: Double = Double(w)
        let hd: Double = Double(h)
        let zoom: Double = TileMath.fitZoom(minLat, minLon, maxLat, maxLon, wd, hd, padding: 24)
        let c0 = TileMath.latLonToPixel((minLat + maxLat) / 2, (minLon + maxLon) / 2, zoom)
        let vmax: Double = max(0.1, Stats.maxFinite(tl.speedFiltered, fallback: 0.1))
        func g(_ v: Double) -> String { DotNetFormat.custom(v, "0.#", spanish: false) }
        var sb: String = "<svg viewBox=\"0 0 \(w) \(h)\" xmlns=\"http://www.w3.org/2000/svg\">"
        if tl.count > 1 {
            for i in 1..<tl.count {
                if tl.breakBefore[i] || tl.jumpBefore[i] { continue }
                let a = TileMath.latLonToPixel(tl.lat[i - 1], tl.lon[i - 1], zoom)
                let b = TileMath.latLonToPixel(tl.lat[i], tl.lon[i], zoom)
                let c: AvoRGB = SpeedScale.color(tl.speedFiltered[i], vmax)
                let x1: String = g(wd / 2.0 + a.x - c0.x)
                let y1: String = g(hd / 2.0 + a.y - c0.y)
                let x2: String = g(wd / 2.0 + b.x - c0.x)
                let y2: String = g(hd / 2.0 + b.y - c0.y)
                let col: String = DotNetFormat.hex2(c.r) + DotNetFormat.hex2(c.g) + DotNetFormat.hex2(c.b)
                sb += "<line x1=\"\(x1)\" y1=\"\(y1)\" x2=\"\(x2)\" y2=\"\(y2)\" stroke=\"#\(col)\" stroke-width=\"3\" stroke-linecap=\"round\"/>"
            }
        }
        sb += "</svg>"
        return sb
    }
}

/// State of one PDF report being written (the local functions of C# ReportBuilder.WritePdf).
private final class PdfReportWriter {
    let d: ReportData
    let pdf: PdfDocument = PdfDocument()
    var y: Double = 0
    let m: Double = 40
    let w: Double
    var page: Int = 0

    init(_ d: ReportData) {
        self.d = d
        self.w = PdfDocument.a4Width - 2 * 40
        pdf.title = "Informe AVO " + d.session.sessionId
    }

    private var ink: AvoRGB { ReportBuilder.ink }
    private var dim: AvoRGB { ReportBuilder.dim }
    private var red: AvoRGB { ReportBuilder.red }

    func header() {
        pdf.newPage()
        page += 1
        pdf.fillRect(0, 0, pdf.width, 64, ReportBuilder.dark)
        pdf.fillRect(0, 64, pdf.width, 3, red)
        pdf.text(m, 16, "AVO", size: 26, bold: true, color: ReportBuilder.white)
        pdf.text(m + 62, 20, "PERFORMANCE HORSE", size: 11, bold: true, color: (r: 0xC9, g: 0xCB, b: 0xD1))
        pdf.text(m + 62, 35, "Informe de entrenamiento", size: 9, bold: false, color: (r: 0x9C, g: 0x9D, b: 0xA4))
        pdf.text(pdf.width - m, 22, ReportBuilder.madrid(d.timeline.utc0 ?? d.session.startedAt, "dd/MM/yyyy HH:mm") + " (Europe/Madrid)",
                 size: 9, bold: false, color: ReportBuilder.white, align: .right)
        pdf.text(pdf.width - m, 37, "Sesión " + d.session.sessionId, size: 8, bold: false, color: (r: 0x9C, g: 0x9D, b: 0xA4), align: .right)
        if d.session.isSynthetic {
            pdf.fillRect(m, 76, w, 18, (r: 0xFF, g: 0xF1, b: 0xC9))
            pdf.text(m + 8, 80, "DEMOSTRACIÓN — DATOS SINTÉTICOS. No corresponde a un entrenamiento medido.", size: 9, bold: true, color: (r: 0x7A, g: 0x52, b: 0x00))
            y = 104
        } else {
            y = 84
        }
        pdf.line(m, pdf.height - 34, pdf.width - m, pdf.height - 34, ReportBuilder.lineColor)
        pdf.text(m, pdf.height - 28, "GNSS del chaleco del jinete (no es un punto anatómico del caballo). IMU de cincha sin calibrar: índices exploratorios, no diagnósticos.",
                 size: 6.8, bold: false, color: dim)
        pdf.text(pdf.width - m, pdf.height - 28, "Página \(page)", size: 7, bold: false, color: dim, align: .right)
    }

    func ensure(_ h: Double) { if y + h > pdf.height - 50 { header() } }

    func title(_ t: String) {
        ensure(40)
        y += 8
        pdf.text(m, y, t.uppercased(), size: 11, bold: true, color: red)
        y += 16
        pdf.line(m, y, m + w, y, ReportBuilder.lineColor)
        y += 8
    }

    func keyValues(_ rows: [(k: String, v: String)]) {
        for row in rows {
            ensure(16)
            pdf.text(m, y, row.k, size: 9, bold: false, color: dim)
            let used: Double = pdf.paragraph(m + 190, y, w - 190, row.v, size: 9, bold: true, color: ink, leading: 1.25)
            y += max(14, used + 2)
        }
        y += 4
    }

    func tiles(_ tiles: [(label: String, value: String)]) {
        ensure(56)
        let tw: Double = (w - 10 * Double(tiles.count - 1)) / Double(tiles.count)
        for i in 0..<tiles.count {
            let x: Double = m + Double(i) * (tw + 10)
            pdf.fillRect(x, y, tw, 48, ReportBuilder.panel)
            pdf.fillRect(x, y, 3, 48, red)
            pdf.text(x + 10, y + 8, tiles[i].label.uppercased(), size: 7.5, bold: true, color: dim)
            pdf.text(x + 10, y + 22, tiles[i].value, size: 15, bold: true, color: ink)
        }
        y += 58
    }

    func table(_ head: [String], _ cols: [Double], _ rows: [[String]]) {
        var total: Double = 0
        for c in cols { total += c }
        let scale: Double = w / total
        let cw: [Double] = cols.map { $0 * scale }
        func headRow() {
            ensure(18)
            pdf.fillRect(m, y, w, 16, ReportBuilder.dark)
            var x: Double = m + 4
            for i in 0..<head.count {
                pdf.text(x, y + 4, head[i], size: 7.5, bold: true, color: ReportBuilder.white)
                x += cw[i]
            }
            y += 18
        }
        headRow()
        var r: Int = 0
        for row in rows {
            if y + 15 > pdf.height - 50 { header(); headRow() }
            if r % 2 == 1 { pdf.fillRect(m, y - 1, w, 14, ReportBuilder.panel) }
            r += 1
            var x: Double = m + 4
            var i: Int = 0
            while i < head.count && i < row.count {
                var cell: [UInt16] = Array(row[i].utf16)
                while cell.count > 3 && PdfDocument.measureText(String(decoding: cell, as: UTF16.self), 7.5, false) > cw[i] - 6 {
                    cell.removeLast(2)
                }
                pdf.text(x, y + 2, String(decoding: cell, as: UTF16.self), size: 7.5, bold: false, color: ink)
                x += cw[i]
                i += 1
            }
            y += 14
        }
        y += 6
    }

    func build() -> Data {
        let num = ReportBuilder.num
        header()
        let s: TrainingSession = d.session
        let tl: SessionTimeline = d.timeline
        let whole: SegmentMetrics? = ReportBuilder.whole(d)
        let sec: ReportSections = d.sections

        if sec.contains(.general) || sec.contains(.horseRider) || sec.contains(.dateDuration) {
            title("Datos generales")
            var rows: [(k: String, v: String)] = []
            if sec.contains(.horseRider) { rows.append((k: "Caballo", v: s.horse)); rows.append((k: "Jinete", v: s.rider)) }
            if sec.contains(.dateDuration) {
                rows.append((k: "Fecha y hora", v: ReportBuilder.madrid(tl.utc0 ?? s.startedAt, "dddd dd/MM/yyyy HH:mm")))
                rows.append((k: "Duración", v: TimeText.clock(tl.count > 1 ? tl.durationS : s.durationSeconds)))
            }
            if sec.contains(.general) {
                rows.append((k: "Archivo", v: s.sourceName)); rows.append((k: "Integridad", v: s.integrity))
                if !s.discipline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { rows.append((k: "Modalidad", v: s.discipline)) }
            }
            keyValues(rows)
            tiles([
                (label: "Distancia", value: num(whole.map { $0.distanceM / 1000 }, "0.00", " km")),
                (label: "Vel. media", value: num(whole?.meanSpeedKmh, "0.0", " km/h")),
                (label: "Vel. máxima", value: num(whole?.maxSpeedKmh, "0.0", " km/h")),
                (label: "RTK FIX", value: num(whole.map { $0.fixFraction * 100 }, "0", " %")),
            ])
        }

        if sec.contains(.map) && tl.count > 1 {
            title("Mapa del recorrido (velocidad filtrada)")
            ensure(300)
            ReportBuilder.drawRoute(pdf, tl, m, y, w, 280)
            y += 288
            pdf.text(m, y, "Escala de velocidad azul → cian → amarillo → rojo (igual que Android). Posiciones del chaleco GNSS del jinete.", size: 7.5, bold: false, color: dim)
            y += 14
        }

        if sec.contains(.gnssStats) {
            title("Calidad GNSS / RTK")
            let dist: [GnssSolution: Double] = GnssQuality.distribution(s.gnssEpochs)
            var lossSum: Double = 0
            for l in tl.losses { lossSum += l.durationS }
            let jumps: Int = tl.jumpBefore.filter { $0 }.count
            keyValues([
                (k: "Épocas recibidas", v: String(s.gnssSamples)),
                (k: "RTK FIX", v: num(dist[.rtkFix] ?? 0, "0.0", " %")),
                (k: "RTK FLOAT", v: num(dist[.rtkFloat] ?? 0, "0.0", " %")),
                (k: "DGNSS", v: num(dist[.dgnss] ?? 0, "0.0", " %")),
                (k: "Autónomo", v: num(dist[.autonomous] ?? 0, "0.0", " %")),
                (k: "Sin solución válida", v: num(dist[GnssSolution.none] ?? 0, "0.0", " %")),
                (k: "Satélites (mediana)", v: tl.count > 0 ? DotNetFormat.custom(Stats.median(tl.numSv.map { Double($0) }), "0", spanish: true) : "Sin datos"),
                (k: "Precisión horizontal reportada (mediana)", v: tl.count > 0 ? num(Stats.median(tl.hAcc), "0.000", " m") : "Sin datos"),
                (k: "Pérdidas de señal", v: "\(tl.losses.count) intervalos · \(TimeText.clock(lossSum))"),
                (k: "Saltos de posición descartados", v: String(jumps)),
            ])
            y += pdf.paragraph(m, y, w, "La precisión horizontal es la estimada por el receptor (hAcc), no un error verificado. RTK FIX no garantiza por sí mismo precisión centimétrica ni un error de velocidad determinado.",
                               size: 7.5, bold: false, color: dim)
        }

        if sec.contains(.speedAccel), let wh = whole {
            title("Velocidades y aceleraciones")
            keyValues([
                (k: "Velocidad máxima (filtrada)", v: num(wh.maxSpeedKmh, "0.0", " km/h")),
                (k: "Velocidad máxima reportada (sin filtrar)", v: num(Stats.maxFinite(tl.speedReported) * 3.6, "0.0", " km/h")),
                (k: "Velocidad media en movimiento", v: num(wh.meanSpeedKmh, "0.0", " km/h")),
                (k: "Aceleración máxima validada", v: num(wh.maxAccel, "0.00", " m/s²")),
                (k: "Desaceleración máxima validada", v: num(wh.maxDecel, "0.00", " m/s²")),
                (k: "Cambios de banda de velocidad", v: String(wh.speedChanges)),
                (k: "Filtro", v: tl.filterParameters.describe()),
            ])
        }

        if sec.contains(.charts) && tl.count > 1 {
            title("Gráficas")
            ensure(150)
            ReportBuilder.chart(pdf, "Velocidad (km/h) — filtrada (rojo) y reportada (gris)", tl.t,
                                [tl.speedFiltered.map { $0 * 3.6 }, tl.speedReported.map { $0 * 3.6 }],
                                [red, (r: 0xA0, g: 0xA1, b: 0xA8)], m, y, w, 120, tl.breakBefore)
            y += 136
            ensure(150)
            ReportBuilder.chart(pdf, "Aceleración longitudinal (m/s²)", tl.t, [tl.accelLong], [ReportBuilder.blue], m, y, w, 110, tl.breakBefore)
            y += 126
            if tl.altitudeMsl.contains(where: { $0.isFinite }) {
                ensure(140)
                ReportBuilder.chart(pdf, "Altitud GNSS sobre el nivel del mar (m)", tl.t, [tl.altitudeMsl], [(r: 0x52, g: 0xDD, b: 0x40)], m, y, w, 90, tl.breakBefore)
                y += 106
            }
        }

        if sec.contains(.segments) {
            title("Tramos")
            if d.segments.isEmpty {
                pdf.text(m, y, "No hay tramos guardados para esta sesión.", size: 9, bold: false, color: dim)
                y += 16
            } else {
                let head: [String] = ["Tramo", "Inicio", "Fin", "Dist.", "Dur.", "V. máx", "V. media", "Acel. máx", "Desac. máx", "FIX"]
                let cols: [Double] = [120, 40, 40, 44, 40, 44, 46, 44, 46, 32]
                var rows: [[String]] = []
                for sm in d.segments {
                    rows.append([
                        sm.name, TimeText.clock(sm.t0), TimeText.clock(sm.t1), num(sm.distanceM, "0", " m"), TimeText.clock(sm.durationS),
                        num(sm.maxSpeedKmh, "0.0", ""), num(sm.meanSpeedKmh, "0.0", ""), num(sm.maxAccel, "0.00", ""), num(sm.maxDecel, "0.00", ""),
                        num(sm.fixFraction * 100, "0", "%"),
                    ])
                }
                table(head, cols, rows)
                pdf.text(m, y, "Velocidades en km/h, aceleraciones en m/s² (solo épocas validadas).", size: 7.5, bold: false, color: dim)
                y += 12
            }
        }

        if sec.contains(.biomechanics) {
            title("Biomecánica (cincha)")
            if let e = d.engine, e.hasImu {
                let symmetry: String = (e.symmetryLabel.isEmpty ? "—" : e.symmetryLabel) + (e.symmetryAllowed ? " (exploratoria)" : " (no concluyente)")
                keyValues([
                    (k: "Cadencia media", v: num(AnalysisForeignAPI.metric(e, "cadencia_media_imu0"), "0", " ciclos/min")),
                    (k: "Correlación entre ciclos", v: num(AnalysisForeignAPI.metric(e, "correlacion_entre_ciclos_imu0"), "0.00", "")),
                    (k: "Variabilidad de intervalos (CV)", v: num(AnalysisForeignAPI.metric(e, "variabilidad_intervalos_imu0"), "0.000", "")),
                    (k: "Estabilidad espectral", v: num(AnalysisForeignAPI.metric(e, "estabilidad_espectral_imu0"), "0.00", "")),
                    (k: "Simetría", v: symmetry),
                ])
                y += pdf.paragraph(m, y, w, "Índices calculados por el motor AVO Equine Intelligence a partir de IMU sin calibrar. Son estimaciones exploratorias: no son diagnóstico clínico, carga de extremidad ni lesión.",
                                   size: 7.5, bold: false, color: dim)
            } else {
                y += pdf.paragraph(m, y, w, "Sin datos de cincha en esta sesión: no se calculan cadencia, regularidad ni simetría. Ningún valor se estima sin datos.",
                                   size: 9, bold: false, color: dim)
            }
        }

        if sec.contains(.comparison) && !d.comparison.isEmpty {
            title("Comparativa")
            let head: [String] = ["Entrenamiento", "Distancia", "Duración", "V. media", "V. máx", "Acel. máx", "FIX", "Cadencia"]
            let cols: [Double] = [150, 50, 50, 50, 50, 50, 40, 50]
            var rows: [[String]] = []
            for c in d.comparison {
                rows.append([
                    c.label, num(c.distanceKm, "0.00", " km"), TimeText.clock(c.durationS), num(c.meanSpeedKmh, "0.0", ""), num(c.maxSpeedKmh, "0.0", ""),
                    num(c.maxAccel, "0.00", ""), num(c.fixPercent, "0", "%"), num(c.cadence, "0", ""),
                ])
            }
            table(head, cols, rows)
        }

        if sec.contains(.tides) {
            title("Mareas y entorno")
            let t0: Date? = tl.utc0 ?? s.startedAt
            if d.tides == nil && d.weather == nil {
                pdf.text(m, y, "No disponible: no se consultaron fuentes de mareas ni meteorología.", size: 9, bold: false, color: dim)
                y += 16
            }
            if let tp = d.tides, let ut = t0 {
                keyValues([
                    (k: "Fuente", v: tp.source), (k: "Tipo de dato", v: "Predicción (no medición)"),
                    (k: "Puerto de referencia", v: tp.port.name + " · a " + num(tp.portDistanceKm, "0.0", " km") + " de la zona de entrenamiento"),
                    (k: "Altura al inicio", v: num(AnalysisForeignAPI.tideHeight(tp, ut), "0.00", " m (cero hidrográfico)")),
                    (k: "Tendencia", v: AnalysisForeignAPI.tideTrend(tp, ut) ?? "Sin datos"),
                    (k: "Coeficiente aproximado", v: num(AnalysisForeignAPI.tideCoefficient(tp, ut), "0", "")),
                ])
            }
            if let wm = d.weather, let ut2 = t0 {
                let h: WeatherHour? = AnalysisForeignAPI.weatherAt(wm, ut2)
                var wind: String = num(h?.windKmh, "0", " km/h")
                if let wd = h?.windDirDeg { wind += " (" + DotNetFormat.custom(wd, "0", spanish: true) + "°)" }
                keyValues([
                    (k: "Fuente", v: wm.source), (k: "Tipo de dato", v: "Modelo numérico (no medición)"),
                    (k: "Temperatura", v: num(h?.temperatureC, "0.0", " °C")), (k: "Viento", v: wind),
                    (k: "Presión", v: num(h?.pressureHpa, "0", " hPa")), (k: "Oleaje", v: num(h?.waveHeightM, "0.0", " m")),
                ])
            }
            y += pdf.paragraph(m, y, w, "Las mareas son predicciones de un puerto de referencia y no mediciones en la playa. Las comparaciones con el rendimiento son exploratorias y no demuestran relaciones causales.",
                               size: 7.5, bold: false, color: dim)
        }

        if sec.contains(.notes) && !d.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            title("Notas y observaciones")
            y += pdf.paragraph(m, y, w, d.notes, size: 9.5)
        }
        return pdf.save()
    }
}
