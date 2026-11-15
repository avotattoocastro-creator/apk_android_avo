import Foundation

/// Groups of data of the race card that can go into the «Informe PDF» (each card of the race card has a «PDF» check;
/// trainer 15/11/2026: «cada grupo de datos tiene que tener un check para que salga o no salga en el informe PDF»).
enum RacePdfSection: String, CaseIterable, Identifiable {
    case header, result, classification, sectors, speedChart, positionChart, strideChart, gapChart, training,
         verdict, raceFacts, trainingFacts, form, estimate, observations, method, notes

    var id: String { rawValue }
    var title: String {
        switch self {
        case .header: return "Datos de la carrera"
        case .result: return "Resultado"
        case .classification: return "Clasificación"
        case .sectors: return "Tramos"
        case .speedChart: return "Velocidad por tramo"
        case .positionChart: return "Posición en carrera"
        case .strideChart: return "Foulées y zancada"
        case .gapChart: return "Distancia al primero"
        case .training: return "Entrenamiento vs carrera"
        case .verdict: return "Conclusión"
        case .raceFacts: return "Lo que dice la carrera"
        case .trainingFacts: return "Lo que dicen sus entrenamientos"
        case .form: return "Forma antes de la carrera"
        case .estimate: return "Estimación"
        case .observations: return "Observaciones"
        case .method: return "Método"
        case .notes: return "Notas"
        }
    }
}

/// Data of the «Informe carrera vs entrenamiento» PDF (race card → «Informe PDF»): the race of our horse, its 200 m
/// sectors, the chosen training effort with splits side by side (RaceTrainingSplits) and «Análisis según los
/// entrenamientos» (RaceReport). Everything optional except the race: the report says what is missing.
struct RaceComparisonPdfData {
    var race: Race
    var us: RaceRunner
    var candidate: RaceTrainingCandidate?
    var comparison: RaceSectorComparison?
    var report: RaceReport?
    var notes: String
    var sections: Set<RacePdfSection> = Set(RacePdfSection.allCases)
    var createdAt: Date = Date()
}

extension ReportBuilder {
    static func raceComparisonPdf(_ d: RaceComparisonPdfData) -> Data {
        RaceComparisonPdfWriter(d).build()
    }
}

/// Same look as the training reports (dark band with the logo, red titles, «Datos clave» tiles, dark-header tables).
private final class RaceComparisonPdfWriter {
    let d: RaceComparisonPdfData
    let pdf: PdfDocument = PdfDocument()
    var y: Double = 0
    let m: Double = 40
    let w: Double = PdfDocument.a4Width - 80
    var page: Int = 0
    static let cyan: AvoRGB = (r: 0x2B, g: 0x86, b: 0x9B)

    init(_ d: RaceComparisonPdfData) {
        self.d = d
        pdf.title = "Informe carrera vs entrenamiento · " + d.race.title
    }

    // ------------------------------------------------------------------ page furniture
    func header() {
        pdf.newPage()
        page += 1
        let band: Double = ReportBuilder.headerBand
        pdf.fillRect(0, 0, pdf.width, band, ReportBuilder.dark)
        pdf.fillRect(0, band, pdf.width, 3, ReportBuilder.red)
        var lx: Double = m
        if let h = ReportLogo.head {
            let hh: Double = band - 14
            let hw: Double = hh * Double(h.width) / Double(h.height)
            pdf.image(h.jpeg, pixelWidth: h.width, pixelHeight: h.height, lx, 7, hw, hh)
            lx += hw + 8
        }
        if let t = ReportLogo.text {
            let th: Double = band - 26
            let tw: Double = th * Double(t.width) / Double(t.height)
            pdf.image(t.jpeg, pixelWidth: t.width, pixelHeight: t.height, lx, 13, tw, th)
        } else {
            pdf.text(lx, 26, "AVO PERFORMANCE HORSE", size: 16, bold: true, color: ReportBuilder.white)
        }
        pdf.text(pdf.width - m, 20, "Informe carrera vs entrenamiento", size: 11, bold: true, color: ReportBuilder.white, align: .right)
        pdf.text(pdf.width - m, 40, "\(d.race.title) · \(d.race.dateText)", size: 9, bold: false,
                 color: (r: 0xC9, g: 0xCB, b: 0xD1), align: .right)
        pdf.text(pdf.width - m, 56, "\(d.race.horseName ?? d.us.name) · \(d.race.hippodrome)", size: 8, bold: false,
                 color: (r: 0x9C, g: 0x9D, b: 0xA4), align: .right)
        y = band + 20
        if d.race.isDemo || d.race.isVideo || (d.candidate?.isDemo ?? false) || (d.report?.trainingDemo ?? false) {
            let txt: String = d.race.isVideo
                ? "CARRERA ANALIZADA DESDE VÍDEO: velocidades, parciales, zancadas y posiciones son ESTIMACIONES."
                : "INCLUYE DATOS DE DEMOSTRACIÓN — no corresponde íntegramente a medidas reales."
            pdf.fillRect(m, y - 8, w, 18, (r: 0xFF, g: 0xF1, b: 0xC9))
            pdf.text(m + 8, y - 4, txt, size: 8.5, bold: true, color: (r: 0x7A, g: 0x52, b: 0x00))
            y += 20
        }
        pdf.line(m, pdf.height - 34, pdf.width - m, pdf.height - 34, ReportBuilder.lineColor)
        pdf.text(m, pdf.height - 28,
                 "Entrenamiento en playa y carrera en pista: se comparan proporciones, no tiempos absolutos. Orientativo, no es un diagnóstico veterinario.",
                 size: 6.8, bold: false, color: ReportBuilder.dim)
        pdf.text(pdf.width - m, pdf.height - 28, "Página \(page)", size: 7, bold: false, color: ReportBuilder.dim, align: .right)
    }

    func ensure(_ h: Double) { if y + h > pdf.height - 50 { header() } }

    func title(_ t: String) {
        ensure(44)
        y += 8
        pdf.text(m, y, t.uppercased(), size: 11, bold: true, color: ReportBuilder.red)
        y += 16
        pdf.line(m, y, m + w, y, ReportBuilder.lineColor)
        y += 8
    }

    func sub(_ t: String) {
        ensure(30)
        pdf.text(m, y, t.uppercased(), size: 8, bold: true, color: ReportBuilder.dim)
        y += 13
    }

    func paragraph(_ text: String, size: Double = 9, bold: Bool = false, color: AvoRGB = ReportBuilder.ink) {
        let est: Double = Double(PdfDocument.lineCount(text, w, size: size, bold: bold)) * size * 1.3 + 4
        ensure(est)
        let used: Double = pdf.paragraph(m, y, w, text, size: size, bold: bold, color: color, leading: 1.3)
        y += used + 4
    }

    func bullets(_ items: [String], size: Double = 8.8) {
        for t in items {
            let est: Double = Double(PdfDocument.lineCount(t, w - 12, size: size, bold: false)) * size * 1.3 + 3
            ensure(est)
            pdf.circle(m + 3, y + 4, 1.6, ReportBuilder.red)
            let used: Double = pdf.paragraph(m + 12, y, w - 12, t, size: size, bold: false, color: ReportBuilder.ink, leading: 1.3)
            y += used + 3
        }
        y += 3
    }

    func keyValues(_ rows: [(k: String, v: String)]) {
        for row in rows {
            ensure(16)
            pdf.text(m, y, row.k, size: 9, bold: false, color: ReportBuilder.dim)
            let used: Double = pdf.paragraph(m + 200, y, w - 200, row.v, size: 9, bold: true, color: ReportBuilder.ink, leading: 1.25)
            y += max(14, used + 2)
        }
        y += 4
    }

    /// «Datos clave» tiles: figure, name and an optional small caption; wraps to new rows of up to `perRow`.
    func tiles(_ tiles: [(label: String, value: String, caption: String?)], perRow: Int = 4) {
        var i: Int = 0
        while i < tiles.count {
            let row = Array(tiles[i..<min(i + perRow, tiles.count)])
            ensure(66)
            let tw: Double = w / Double(perRow)
            for (k, t) in row.enumerated() {
                let x: Double = m + Double(k) * tw
                pdf.text(x + tw / 2, y + 6, t.value, size: 15, bold: false, color: ReportBuilder.ink, align: .center)
                pdf.text(x + tw / 2, y + 27, t.label.uppercased(), size: 6.5, bold: true, color: ReportBuilder.dim, align: .center)
                if let c = t.caption, !c.isEmpty {
                    var cell: [UInt16] = Array(c.utf16)
                    while cell.count > 3 && PdfDocument.measureText(String(decoding: cell, as: UTF16.self), 6.5, false) > tw - 8 { cell.removeLast(2) }
                    pdf.text(x + tw / 2, y + 38, String(decoding: cell, as: UTF16.self), size: 6.5, bold: false, color: ReportBuilder.dim, align: .center)
                }
                pdf.line(x + 6, y + 54, x + tw - 6, y + 54, ReportBuilder.lineColor, width: 0.5)
                if k < row.count - 1 { pdf.line(x + tw, y + 4, x + tw, y + 48, ReportBuilder.lineColor, width: 0.5) }
            }
            y += 62
            i += perRow
        }
    }

    /// Table with a dark header row; `highlight` rows get a light red band (our horse).
    func table(_ head: [String], _ cols: [Double], _ rows: [[String]], highlight: Set<Int> = [], size: Double = 7.5) {
        let total: Double = cols.reduce(0, +)
        let cw: [Double] = cols.map { $0 * w / total }
        func headRow() {
            ensure(34)
            pdf.fillRect(m, y, w, 16, ReportBuilder.dark)
            var x: Double = m + 4
            for i in 0..<head.count {
                pdf.text(x, y + 4, head[i], size: size, bold: true, color: ReportBuilder.white)
                x += cw[i]
            }
            y += 18
        }
        headRow()
        for (r, row) in rows.enumerated() {
            if y + 15 > pdf.height - 50 { header(); headRow() }
            if highlight.contains(r) {
                pdf.fillRect(m, y - 1, w, 14, (r: 0xFB, g: 0xE3, b: 0xE6))
            } else if r % 2 == 1 {
                pdf.fillRect(m, y - 1, w, 14, ReportBuilder.panel)
            }
            var x: Double = m + 4
            for i in 0..<min(head.count, row.count) {
                var cell: [UInt16] = Array(row[i].utf16)
                while cell.count > 3 && PdfDocument.measureText(String(decoding: cell, as: UTF16.self), size, false) > cw[i] - 6 {
                    cell.removeLast(2)
                }
                pdf.text(x, y + 2, String(decoding: cell, as: UTF16.self), size: size, bold: highlight.contains(r), color: ReportBuilder.ink)
                x += cw[i]
            }
            y += 14
        }
        y += 6
    }

    func legend(_ items: [(String, AvoRGB)]) {
        var x: Double = m
        for (t, c) in items {
            pdf.fillRect(x, y + 1, 8, 6, c)
            pdf.text(x + 11, y, t, size: 7.5, bold: false, color: ReportBuilder.dim)
            x += 14 + PdfDocument.measureText(t, 7.5, false) + 14
        }
        y += 14
    }

    // ------------------------------------------------------------------ charts
    /// Grouped bars per piece: training (cyan) and race (red), km/h.
    func barChart(_ cmp: RaceSectorComparison) {
        let h: Double = 150
        ensure(h + 40)
        sub("Velocidad por tramo (km/h)")
        let x0: Double = m + 24
        let cw: Double = w - 28
        pdf.fillRect(m, y, w, h, ReportBuilder.panel)
        var top: Double = 10
        for r in cmp.rows { top = max(top, r.trainingKmh ?? 0, r.raceKmh ?? 0) }
        top = (top / 10).rounded(.up) * 10
        func py(_ v: Double) -> Double { y + h - 16 - v / top * (h - 26) }
        var v: Double = 0
        while v <= top + 0.01 {
            pdf.line(x0, py(v), x0 + cw, py(v), ReportBuilder.lineColor, width: 0.4)
            pdf.text(m + 2, py(v) - 4, DotNetFormat.custom(v, "0", spanish: true), size: 6.5, bold: false, color: ReportBuilder.dim)
            v += 10
        }
        let n: Int = max(cmp.rows.count, 1)
        let slot: Double = cw / Double(n)
        let bw: Double = min(16, slot * 0.32)
        for (k, r) in cmp.rows.enumerated() {
            let cx: Double = x0 + slot * (Double(k) + 0.5)
            if let t = r.trainingKmh, t.isFinite {
                pdf.fillRect(cx - bw - 1, py(t), bw, py(0) - py(t), RaceComparisonPdfWriter.cyan)
            }
            if let c = r.raceKmh, c.isFinite {
                pdf.fillRect(cx + 1, py(c), bw, py(0) - py(c), ReportBuilder.red)
            }
            pdf.text(cx, y + h - 12, r.label, size: 6.3, bold: false, color: ReportBuilder.dim, align: .center)
        }
        y += h + 4
        legend([("Entrenamiento (playa)", RaceComparisonPdfWriter.cyan), ("Carrera (pista)", ReportBuilder.red)])
    }

    /// Fade profile: each series as % of its own best piece (dashed 100 %).
    func fadeChart(_ cmp: RaceSectorComparison) {
        let h: Double = 140
        ensure(h + 40)
        sub("Perfil de caída (% de su mejor tramo)")
        let x0: Double = m + 30
        let cw: Double = w - 34
        pdf.fillRect(m, y, w, h, ReportBuilder.panel)
        var vals: [Double] = []
        for r in cmp.rows {
            if let t = r.trainingKmh, let b = cmp.trainingBestKmh, b > 0 { vals.append(t / b * 100) }
            if let c = r.raceKmh, let b = cmp.raceBestKmh, b > 0 { vals.append(c / b * 100) }
        }
        var lo: Double = ((vals.min() ?? 80) / 10).rounded(.down) * 10
        lo = min(lo, 90)
        let hi: Double = 100
        func py(_ v: Double) -> Double { y + h - 16 - (v - lo) / (hi - lo) * (h - 26) }
        var v: Double = lo
        while v <= hi + 0.01 {
            pdf.line(x0, py(v), x0 + cw, py(v), ReportBuilder.lineColor, width: v == hi ? 0.9 : 0.4)
            pdf.text(m + 2, py(v) - 4, DotNetFormat.custom(v, "0", spanish: true) + " %", size: 6.5, bold: false, color: ReportBuilder.dim)
            v += 10
        }
        let n: Int = max(cmp.rows.count, 1)
        let slot: Double = cw / Double(n)
        var tp: [(x: Double, y: Double)] = []
        var rp: [(x: Double, y: Double)] = []
        for (k, r) in cmp.rows.enumerated() {
            let cx: Double = x0 + slot * (Double(k) + 0.5)
            if let t = r.trainingKmh, let b = cmp.trainingBestKmh, b > 0 { tp.append((x: cx, y: py(t / b * 100))) } else { tp.append((x: .nan, y: .nan)) }
            if let c = r.raceKmh, let b = cmp.raceBestKmh, b > 0 { rp.append((x: cx, y: py(c / b * 100))) } else { rp.append((x: .nan, y: .nan)) }
            pdf.text(cx, y + h - 12, r.label, size: 6.3, bold: false, color: ReportBuilder.dim, align: .center)
        }
        pdf.polyline(tp, RaceComparisonPdfWriter.cyan, width: 1.3)
        pdf.polyline(rp, ReportBuilder.red, width: 1.3)
        for p in tp where p.x.isFinite { pdf.circle(p.x, p.y, 2, RaceComparisonPdfWriter.cyan) }
        for p in rp where p.x.isFinite { pdf.circle(p.x, p.y, 2, ReportBuilder.red) }
        y += h + 4
        legend([("Entrenamiento (playa)", RaceComparisonPdfWriter.cyan), ("Carrera (pista)", ReportBuilder.red)])
    }

    /// Line chart over the race sectors (categorical x): one polyline per series; `reversed` puts 1 at the top (positions).
    func lineChart(_ caption: String, _ labels: [String], _ series: [(name: String, color: AvoRGB, values: [Double?])],
                   reversed: Bool = false, unit: String = "", decimals: Int = 1, step: Double? = nil) {
        let h: Double = 150
        ensure(h + 40)
        sub(caption)
        let x0: Double = m + 30
        let cw: Double = w - 34
        pdf.fillRect(m, y, w, h, ReportBuilder.panel)
        let all: [Double] = series.flatMap { $0.values.compactMap { $0 } }.filter { $0.isFinite }
        guard var lo = all.min(), var hi = all.max() else {
            pdf.text(m + 8, y + 8, "Sin datos", size: 8, bold: false, color: ReportBuilder.dim)
            y += h + 6
            return
        }
        if hi - lo < 1e-6 { lo -= 1; hi += 1 }
        let st: Double = step ?? max(((hi - lo) / 4 * 10).rounded(.up) / 10, 0.1)
        lo = (lo / st).rounded(.down) * st
        hi = (hi / st).rounded(.up) * st
        func py(_ v: Double) -> Double {
            let t: Double = (v - lo) / (hi - lo)
            return reversed ? y + 10 + t * (h - 26) : y + h - 16 - t * (h - 26)
        }
        var v: Double = lo
        while v <= hi + st * 0.01 {
            pdf.line(x0, py(v), x0 + cw, py(v), ReportBuilder.lineColor, width: 0.4)
            pdf.text(m + 2, py(v) - 4, DotNetFormat.custom(v, decimals == 0 ? "0" : "0.0", spanish: true) + unit, size: 6.3, bold: false,
                     color: ReportBuilder.dim)
            v += st
        }
        let n: Int = max(labels.count, 1)
        let slot: Double = cw / Double(n)
        for (k, l) in labels.enumerated() {
            pdf.text(x0 + slot * (Double(k) + 0.5), y + h - 12, l, size: 6.3, bold: false, color: ReportBuilder.dim, align: .center)
        }
        for s in series {
            var pts: [(x: Double, y: Double)] = []
            for k in 0..<labels.count {
                let cx: Double = x0 + slot * (Double(k) + 0.5)
                if k < s.values.count, let val = s.values[k], val.isFinite { pts.append((x: cx, y: py(val))) } else { pts.append((x: .nan, y: .nan)) }
            }
            pdf.polyline(pts, s.color, width: 1.3)
            for p in pts where p.x.isFinite { pdf.circle(p.x, p.y, 2, s.color) }
        }
        y += h + 4
        legend(series.map { ($0.name, $0.color) })
    }

    /// Bars per sector (one series), with the value on top.
    func bars(_ caption: String, _ labels: [String], _ values: [Double?], color: AvoRGB, decimals: Int = 2) {
        let h: Double = 130
        ensure(h + 30)
        sub(caption)
        let x0: Double = m + 6
        let cw: Double = w - 12
        pdf.fillRect(m, y, w, h, ReportBuilder.panel)
        let top: Double = max(values.compactMap { $0 }.max() ?? 1, 0.01) * 1.15
        let n: Int = max(labels.count, 1)
        let slot: Double = cw / Double(n)
        let bw: Double = min(26, slot * 0.55)
        for (k, l) in labels.enumerated() {
            let cx: Double = x0 + slot * (Double(k) + 0.5)
            if k < values.count, let v = values[k], v.isFinite {
                let bh: Double = max(0, v / top * (h - 34))
                pdf.fillRect(cx - bw / 2, y + h - 16 - bh, bw, bh, color)
                pdf.text(cx, y + h - 26 - bh, AvoFormat.f(v, decimals), size: 6.5, bold: false, color: ReportBuilder.ink, align: .center)
            }
            pdf.text(cx, y + h - 12, l, size: 6.3, bold: false, color: ReportBuilder.dim, align: .center)
        }
        y += h + 8
    }

    static let blue: AvoRGB = (r: 0x2F, g: 0x6F, b: 0xD0)
    static let grey: AvoRGB = (r: 0x55, g: 0x57, b: 0x5E)

    func raceCharts() {
        let r: Race = d.race
        let u: RaceRunner = d.us
        let sec: Set<RacePdfSection> = d.sections
        let want: Bool = sec.contains(.speedChart) || sec.contains(.positionChart) || sec.contains(.strideChart) || sec.contains(.gapChart)
        guard want, !u.sectors.isEmpty else { return }
        title("Gráficas por tramo")
        let labels: [String] = u.sectors.map { $0.shortLabel }
        let win: RaceRunner? = r.winner.flatMap { $0.name == u.name ? nil : $0 }
        let ourName: String = u.name
        let winName: String = "Ganador (\(win?.name ?? "—"))"
        func vals(_ x: RaceRunner, _ f: (RaceSector) -> Double?) -> [Double?] {
            (0..<labels.count).map { k in k < x.sectors.count ? f(x.sectors[k]) : nil }
        }
        if sec.contains(.speedChart) {
            var series: [(name: String, color: AvoRGB, values: [Double?])] = [(name: ourName, color: ReportBuilder.red, values: vals(u) { $0.speedKmh })]
            if let w0 = win { series.append((name: winName, color: RaceComparisonPdfWriter.blue, values: vals(w0) { $0.speedKmh })) }
            let med: [Double?] = (0..<labels.count).map { k in
                RaceAnalysis.median(r.runners.filter { $0.name != u.name }.compactMap { k < $0.sectors.count ? $0.sectors[k].speedKmh : nil })
            }
            series.append((name: "Mediana del campo", color: RaceComparisonPdfWriter.grey, values: med))
            lineChart("Velocidad por tramo (km/h) · nuestro caballo, ganador y mediana del campo", labels, series)
        }
        if sec.contains(.positionChart) {
            var series: [(name: String, color: AvoRGB, values: [Double?])] = [(name: ourName, color: ReportBuilder.red, values: vals(u) { $0.position.map { Double($0) } })]
            if let w0 = win { series.append((name: winName, color: RaceComparisonPdfWriter.blue, values: vals(w0) { $0.position.map { Double($0) } })) }
            lineChart("Posición en carrera al final de cada tramo (1 = en cabeza)", labels, series, reversed: true, unit: ".º", decimals: 0, step: 1)
        }
        if sec.contains(.strideChart) {
            var series: [(name: String, color: AvoRGB, values: [Double?])] = [(name: ourName, color: ReportBuilder.red, values: vals(u) { $0.strideLengthM })]
            if let w0 = win { series.append((name: winName, color: RaceComparisonPdfWriter.blue, values: vals(w0) { $0.strideLengthM })) }
            lineChart("Longitud de zancada (m) = longitud del tramo / foulées", labels, series, unit: " m", decimals: 1)
        }
        if sec.contains(.gapChart) {
            let gaps: [Double?] = (0..<labels.count).map { k in
                guard k < u.sectors.count, let lead = r.runners.compactMap({ k < $0.sectors.count ? $0.sectors[k].cumulativeS : nil }).min() else { return nil }
                return u.sectors[k].cumulativeS - lead
            }
            bars("Distancia al primero (s detrás del caballo en cabeza; 1 cuerpo ≈ 0,2 s)", labels, gaps, color: ReportBuilder.red)
        }
    }

    // ------------------------------------------------------------------ content
    func build() -> Data {
        let r: Race = d.race
        let u: RaceRunner = d.us
        header()

        let sec: Set<RacePdfSection> = d.sections
        // 1. race
        if sec.contains(.header) || sec.contains(.result) { title("Carrera") }
        if sec.contains(.header) { keyValues([(k: "Carrera", v: "\(r.title)\(r.category.isEmpty ? "" : " · " + r.category)"),
                   (k: "Hipódromo · fecha", v: "\(r.hippodrome.isEmpty ? "—" : r.hippodrome) · \(r.dateText)"),
                   (k: "Distancia · participantes", v: "\(r.distanceText) · \(r.fieldSize)"),
                   (k: "Caballo", v: "\(r.horseName ?? "—") (\(u.name))"),
                   (k: "Jockey", v: u.jockey.isEmpty ? "—" : u.jockey)]) }
        let gap: Double? = r.ourGapToWinnerS
        if sec.contains(.result) { tiles([(label: "Puesto", value: r.finishText, caption: u.number.map { "N.º \($0)" + (u.draw.map { " · cuerda \($0)" } ?? "") }),
               (label: "Tiempo oficial", value: RaceFormat.official(u.officialTimeS), caption: RaceFormat.seconds(u.officialTimeS)),
               (label: "Al ganador", value: u.finish == 1 ? "Ganador" : RaceFormat.signedSeconds(gap),
                caption: u.finish == 1 ? nil : RaceFormat.lengths(gap)),
               (label: "V. máxima", value: RaceFormat.kmh(u.maxSpeedKmh, 2), caption: u.maxSpeedSector.isEmpty ? nil : "Tramo " + u.maxSpeedSector),
               (label: "Mejor 200 m", value: RaceFormat.seconds(u.fastest200S), caption: u.fastestSector.isEmpty ? nil : "Tramo " + u.fastestSector),
               (label: "Últimos 600 m", value: RaceFormat.seconds(u.last600S), caption: nil),
               (label: "V. media", value: RaceFormat.kmh(u.meanSpeedKmh), caption: nil),
               (label: "Recorrido vs 1.º", value: u.finish == 1 ? "—" : RaceFormat.signedMetres(u.distanceVsWinnerM), caption: "«Parcouru vs. 1er»")]) }

        // 2. sectors of our horse
        if sec.contains(.sectors) && !u.sectors.isEmpty {
            title("Tramos de \(u.name)")
            let rows: [[String]] = u.sectors.map { (s: RaceSector) -> [String] in
                [s.label, RaceFormat.official(s.cumulativeS), RaceFormat.seconds(s.sectorS), RaceFormat.kmh(s.meanSpeedKmh),
                 s.strides.map { String($0) } ?? "—", RaceFormat.metres(s.strideLengthM), RaceFormat.place(s.position)]
            }
            table(["Tramo", "Acumulado", "Tramo", "Velocidad", "Foulées", "Zancada", "Posición"], [1.6, 1, 0.9, 1.1, 0.8, 0.9, 0.8], rows)
        }

        // 3. result table of the field (compact)
        if sec.contains(.classification) && r.runners.count > 1 {
            title("Clasificación")
            let ours: Set<Int> = Set(r.runners.indices.filter { r.runners[$0].name == u.name })
            let rows: [[String]] = r.runners.map { (x: RaceRunner) -> [String] in
                let g: Double? = {
                    guard let t = x.officialTimeS, let w0 = r.runners.compactMap({ $0.officialTimeS }).min() else { return nil }
                    return t - w0
                }()
                return [RaceFormat.place(x.finish), x.number.map { String($0) } ?? "—", x.name, x.jockey,
                        RaceFormat.official(x.officialTimeS), x.finish == 1 ? "—" : RaceFormat.signedSeconds(g),
                        RaceFormat.kmh(x.maxSpeedKmh), RaceFormat.seconds(x.fastest200S)]
            }
            table(["Lleg.", "N.º", "Caballo", "Jockey", "Tiempo", "Dif.", "V. máx", "Mejor 200"], [0.6, 0.5, 2.1, 1.6, 1, 0.9, 1, 0.9],
                  rows, highlight: ours, size: 7)
        }

        // charts of the race
        raceCharts()

        // 4. training vs race
        if !sec.contains(.training) {
        } else if let c = d.candidate, let cmp = d.comparison {
            title("Entrenamiento vs carrera, tramo a tramo")
            keyValues([(k: "Entrenamiento comparado", v: c.label),
                       (k: "Parciales del entrenamiento", v: "\(c.fullSplits) · " + (cmp.trainingIsFurlong ? "cada furlong (201 m)" : "cada 200 m"))])
            tiles([(label: "% de la velocidad de carrera", value: RaceFormat.percent(cmp.meanPctOfRace), caption: "Media de los tramos comparados"),
                   (label: "Caída en entrenamiento", value: RaceFormat.percent(cmp.trainingFade),
                    caption: "\(RaceFormat.kmh(cmp.trainingLastKmh)) / \(RaceFormat.kmh(cmp.trainingBestKmh))"),
                   (label: "Caída en carrera", value: RaceFormat.percent(cmp.raceFade),
                    caption: "\(RaceFormat.kmh(cmp.raceLastKmh)) / \(RaceFormat.kmh(cmp.raceBestKmh))"),
                   (label: "Parciales del entreno", value: String(c.fullSplits), caption: nil)])
            if !cmp.rows.isEmpty {
                barChart(cmp)
                fadeChart(cmp)
                let rows: [[String]] = cmp.rows.map { (x: RaceSectorComparisonRow) -> [String] in
                    [x.label, RaceFormat.seconds(x.trainingS), RaceFormat.kmh(x.trainingKmh), RaceFormat.seconds(x.raceS),
                     RaceFormat.kmh(x.raceKmh), RaceFormat.percent(x.pctOfRace)]
                }
                table(["Tramo", "Entreno", "Entreno km/h", "Carrera", "Carrera km/h", "% carrera"], [1.2, 1, 1.1, 1, 1.1, 0.9], rows)
            }
            if cmp.trainingPartialEndSkipped {
                paragraph("El último parcial del entrenamiento es más corto que \(cmp.trainingIsFurlong ? "un furlong" : "200 m") y no se compara.",
                          size: 7.5, color: ReportBuilder.dim)
            }
            paragraph("Los parciales del entrenamiento son en la playa y los de la carrera en la pista: superficie, peso, ritmo y rivales cambian. "
                      + "Se comparan proporciones (qué parte de la velocidad de carrera alcanza y cómo cae al final), no tiempos absolutos. "
                      + "Los tramos se alinean desde la meta: el último parcial completo del trabajo con el tramo 200–ARR.",
                      size: 7.5, color: ReportBuilder.dim)
        } else {
            title("Entrenamiento vs carrera, tramo a tramo")
            paragraph("Sin trabajos con parciales completos en los \(RaceTrainingSplits.windowDays) días anteriores a la carrera: no hay comparación tramo a tramo.",
                      size: 9, color: ReportBuilder.dim)
        }

        // 5. analysis
        let anySec: Bool = !sec.isDisjoint(with: [.verdict, .raceFacts, .trainingFacts, .form, .estimate, .observations, .method])
        if !anySec {
        } else if let rep = d.report {
            title("Análisis según los entrenamientos · confianza \(rep.confidence.rawValue)")
            if sec.contains(.verdict) {
                if !rep.verdict.isEmpty { paragraph(rep.verdict, size: 10, bold: true) }
                if !rep.optimizedText.isEmpty { paragraph(rep.optimizedText, size: 9) }
                if !rep.confidenceReason.isEmpty {
                    paragraph("Confianza \(rep.confidence.rawValue): \(rep.confidenceReason).", size: 8, color: ReportBuilder.dim)
                }
            }
            if sec.contains(.raceFacts) {
            sub("Lo que dice la carrera")
            keyValues([(k: "Caída en el final (conserva)",
                        v: "\(RaceFormat.percent(rep.ourFade)) · \(RaceFormat.kmh(rep.ourBestSpeedKmh)) → \(RaceFormat.kmh(rep.ourLastSpeedKmh))"),
                       (k: "Mediana del campo (conserva)", v: RaceFormat.percent(rep.fieldMedianFade)),
                       (k: "Perdido en el final vs mediana", v: RaceFormat.seconds(rep.finalLossFieldS)),
                       (k: "Perdido por terreno de más", v: groundText(rep)),
                       (k: "Salida vs mediana del campo", v: RaceFormat.signedSeconds(rep.startLossS)),
                       (k: "Últimos 600 m vs su mejor tramo", v: RaceFormat.percent(rep.raceSustain))])
            }
            if sec.contains(.trainingFacts) {
            sub("Lo que dicen sus entrenamientos")
            if rep.trainingSessions == 0 {
                paragraph("Sin entrenamientos anteriores a la carrera en el iPad: el análisis usa solo la carrera (mediana del campo como referencia).",
                          size: 8.5, color: ReportBuilder.dim)
            } else {
                keyValues([(k: "Entrenamientos",
                            v: "\(rep.trainingSessions) · \(AvoTime.text(rep.trainingFrom, "dd/MM/yyyy")) – \(AvoTime.text(rep.trainingTo, "dd/MM/yyyy"))"),
                           (k: "Trabajos rápidos (> 40 km/h, ≥ 200 m)", v: String(rep.fastWorks)),
                           (k: "Mejor 200 / 400 / 600 m sostenido",
                            v: "\(RaceFormat.kmh(rep.best200Kmh)) / \(RaceFormat.kmh(rep.best400Kmh)) / \(RaceFormat.kmh(rep.best600Kmh))"),
                           (k: "600 m sostenido / mejor 200 m", v: RaceFormat.percent(rep.trainingSustain)),
                           (k: "Caída en sus trabajos (conserva)",
                            v: rep.worksWithFade > 0 ? "\(RaceFormat.percent(rep.trainingFade)) en \(rep.worksWithFade) trabajo(s) ≥ 400 m" : "Sin trabajos ≥ 400 m")])
                if !rep.trendText.isEmpty { paragraph(rep.trendText, size: 8.5) }
            }
            }
            if sec.contains(.form), let f = rep.form {
                sub("Forma antes de la carrera (orientativo, no es un diagnóstico veterinario)")
                keyValues([(k: "Estado", v: "\(f.level) · \(f.sessionsUsed) sesiones · referencia \(f.reference)"),
                           (k: "ACWR (aguda / crónica)",
                            v: (f.acwr.map { AvoFormat.f($0, 2) } ?? "— (menos de 28 días)") + " · banda \(AvoFormat.f(f.acwrLow, 1))–\(AvoFormat.f(f.acwrHigh, 1))"),
                           (k: "Carga aguda 7 d / crónica semanal",
                            v: "\(f.acute.map { AvoFormat.f($0, 0) } ?? "—") / \(f.chronicWeekly.map { AvoFormat.f($0, 0) } ?? "—")"),
                           (k: "Monotonía", v: f.monotony.map { AvoFormat.f($0, 2) } ?? "—"),
                           (k: "Días desde el último entrenamiento", v: f.daysSinceLast.map { String($0) } ?? "—")])
                if !f.reasons.isEmpty { bullets(f.reasons, size: 8) }
            }
            if sec.contains(.estimate) {
            sub(rep.referenceIsTraining ? "Estimación (final con la caída de sus entrenamientos y sin el terreno de más)"
                                        : "Estimación (final con la caída de la mediana del campo y sin el terreno de más)")
            let range: String? = {
                guard let a = rep.placeLow, let b = rep.placeHigh else { return nil }
                return a == b ? "Margen ±: sin cambio" : "Margen ±: \(a).º–\(b).º"
            }()
            tiles([(label: "Tiempo oficial", value: RaceFormat.official(u.officialTimeS), caption: nil),
                   (label: "Tiempo corregido", value: RaceFormat.official(rep.correctedTimeS),
                    caption: rep.correctedTimeS.flatMap { c in u.officialTimeS.map { "−" + AvoFormat.f($0 - c, 2) + " s" } }),
                   (label: "Puesto real", value: r.finishText, caption: nil),
                   (label: "Puesto estimado", value: rep.predictedPlace.map { "\($0).º" } ?? "—", caption: range),
                   (label: "Perdido en el final",
                    value: RaceFormat.seconds(rep.referenceIsTraining ? rep.finalLossTrainingS : rep.finalLossFieldS),
                    caption: rep.referenceIsTraining ? "vs sus entrenamientos" : "vs mediana del campo")], perRow: 5)
            }
            if sec.contains(.observations) && !rep.observations.isEmpty {
                sub("Observaciones")
                bullets(rep.observations)
            }
            if sec.contains(.method) && !rep.method.isEmpty {
                sub("Método")
                for (k, t) in rep.method.enumerated() { paragraph("\(k + 1). \(t)", size: 7.2, color: ReportBuilder.dim) }
            }
        } else {
            title("Análisis según los entrenamientos")
            paragraph("El análisis todavía no estaba calculado al crear el informe.", size: 9, color: ReportBuilder.dim)
        }

        // 6. notes
        let notes: String = d.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if sec.contains(.notes) && !notes.isEmpty {
            title("Notas")
            paragraph(notes)
        }
        ensure(16)
        y += 6
        pdf.text(m, y, "Generado con AVO Performance Horse el \(AvoTime.text(d.createdAt, "dd/MM/yyyy HH:mm")) (Europe/Madrid)"
                 + (r.sourceFile.isEmpty ? "" : " · fuente: " + r.sourceFile), size: 7, bold: false, color: ReportBuilder.dim)
        return pdf.save()
    }

    private func groundText(_ rep: RaceReport) -> String {
        guard let dd = d.us.distanceVsWinnerM else { return d.us.finish == 1 ? "Ganador" : "Sin dato" }
        if dd <= 0 { return "0 s (\(RaceFormat.signedMetres(dd)))" }
        return "\(RaceFormat.seconds(rep.groundLossS)) (\(RaceFormat.signedMetres(dd)))"
    }
}
