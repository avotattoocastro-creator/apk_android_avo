import Foundation

/// «Informe PDF» of the «Análisis motor» of a race (trainer, 20/11/2026: PDF button on that screen). Same look as the
/// other AVO reports (dark band with the logo, red titles, tiles, dark-header tables) and the same content as the screen
/// (Core/RaceDeepEngine.swift): summary, the race part by part, charts, rivals, earlier races, trainings and conclusions.
struct RaceEnginePdfData {
    var race: Race
    var us: RaceRunner
    var report: RaceDeepReport
    var engineVersion: String
    var createdAt: Date = Date()
}

extension ReportBuilder {
    static func raceEnginePdf(_ d: RaceEnginePdfData) -> Data {
        RaceEnginePdfWriter(d).build()
    }
}

private final class RaceEnginePdfWriter {
    let d: RaceEnginePdfData
    let pdf: PdfDocument = PdfDocument()
    var y: Double = 0
    let m: Double = 40
    let w: Double = PdfDocument.a4Width - 80
    var page: Int = 0
    static let cyan: AvoRGB = (r: 0x2B, g: 0x86, b: 0x9B)
    static let green: AvoRGB = (r: 0x1F, g: 0x9D, b: 0x45)
    static let amber: AvoRGB = (r: 0xA8, g: 0x6F, b: 0x00)
    static let grey: AvoRGB = (r: 0x8A, g: 0x8C, b: 0x93)

    init(_ d: RaceEnginePdfData) {
        self.d = d
        pdf.title = "Análisis motor · " + d.race.title
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
        pdf.text(pdf.width - m, 20, "Análisis motor de la carrera", size: 11, bold: true, color: ReportBuilder.white, align: .right)
        pdf.text(pdf.width - m, 40, "\(d.race.title) · \(d.race.dateText)", size: 9, bold: false,
                 color: (r: 0xC9, g: 0xCB, b: 0xD1), align: .right)
        pdf.text(pdf.width - m, 56, "\(d.race.horseName ?? d.us.name) · \(d.race.hippodrome)", size: 8, bold: false,
                 color: (r: 0x9C, g: 0x9D, b: 0xA4), align: .right)
        y = band + 20
        if d.race.isDemo || d.race.isVideo {
            let txt: String = d.race.isVideo
                ? "CARRERA ANALIZADA DESDE VÍDEO: velocidades, parciales, zancadas y posiciones son ESTIMACIONES."
                : "INCLUYE DATOS DE DEMOSTRACIÓN — no corresponde íntegramente a medidas reales."
            pdf.fillRect(m, y - 8, w, 18, (r: 0xFF, g: 0xF1, b: 0xC9))
            pdf.text(m + 8, y - 4, txt, size: 8.5, bold: true, color: (r: 0x7A, g: 0x52, b: 0x00))
            y += 20
        }
        pdf.line(m, pdf.height - 34, pdf.width - m, pdf.height - 34, ReportBuilder.lineColor)
        pdf.text(m, pdf.height - 28, "Motor \(d.engineVersion) · Orientativo: ayuda a leer la carrera, no es un diagnóstico veterinario.",
                 size: 6.8, bold: false, color: ReportBuilder.dim)
        pdf.text(pdf.width - m, pdf.height - 28, "Página \(page)", size: 7, bold: false, color: ReportBuilder.dim, align: .right)
    }

    func ensure(_ h: Double) { if y + h > pdf.height - 50 { header() } }

    func title(_ t: String, keep: Double = 90) {
        ensure(44 + keep)
        y += 8
        pdf.text(m, y, t.uppercased(), size: 11, bold: true, color: ReportBuilder.red)
        y += 16
        pdf.line(m, y, m + w, y, ReportBuilder.lineColor)
        y += 8
    }

    func sub(_ t: String, keep: Double = 50) {
        ensure(30 + keep)
        pdf.text(m, y, t.uppercased(), size: 8, bold: true, color: ReportBuilder.dim)
        y += 13
    }

    func paragraph(_ text: String, size: Double = 9, bold: Bool = false, color: AvoRGB = ReportBuilder.ink) {
        if text.isEmpty { return }
        let est: Double = Double(PdfDocument.lineCount(text, w, size: size, bold: bold)) * size * 1.3 + 4
        ensure(est)
        let used: Double = pdf.paragraph(m, y, w, text, size: size, bold: bold, color: color, leading: 1.3)
        y += used + 4
    }

    func bullets(_ items: [String], size: Double = 8.8, dot: AvoRGB = ReportBuilder.red) {
        for t in items where !t.isEmpty {
            let est: Double = Double(PdfDocument.lineCount(t, w - 12, size: size, bold: false)) * size * 1.3 + 3
            ensure(est)
            pdf.circle(m + 3, y + 4, 1.6, dot)
            let used: Double = pdf.paragraph(m + 12, y, w - 12, t, size: size, bold: false, color: ReportBuilder.ink, leading: 1.3)
            y += used + 3
        }
        y += 3
    }

    func tiles(_ tiles: [(label: String, value: String, caption: String?)]) {
        ensure(66)
        let tw: Double = w / Double(max(1, tiles.count))
        var size: Double = 15
        while size > 8 && tiles.contains(where: { PdfDocument.measureText($0.value, size, false) > tw - 6 }) { size -= 0.5 }
        for (k, t) in tiles.enumerated() {
            let x: Double = m + Double(k) * tw
            pdf.text(x + tw / 2, y + 6 + (15 - size) * 0.5, t.value, size: size, bold: false, color: ReportBuilder.ink, align: .center)
            pdf.text(x + tw / 2, y + 27, t.label.uppercased(), size: 6.5, bold: true, color: ReportBuilder.dim, align: .center)
            if let c = t.caption, !c.isEmpty {
                pdf.text(x + tw / 2, y + 38, c, size: 6.5, bold: false, color: ReportBuilder.dim, align: .center)
            }
            pdf.line(x + 6, y + 54, x + tw - 6, y + 54, ReportBuilder.lineColor, width: 0.5)
            if k < tiles.count - 1 { pdf.line(x + tw, y + 4, x + tw, y + 48, ReportBuilder.lineColor, width: 0.5) }
        }
        y += 62
    }

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
        ensure(16)
        var x: Double = m
        for (t, c) in items {
            pdf.fillRect(x, y + 1, 8, 6, c)
            pdf.text(x + 11, y, t, size: 7.5, bold: false, color: ReportBuilder.dim)
            x += 14 + PdfDocument.measureText(t, 7.5, false) + 14
        }
        y += 14
    }

    // ------------------------------------------------------------------ charts
    /// Lines over the sectors. `reversed` puts the smallest value at the top (positions). Labels above our points.
    func lineChart(_ caption: String, _ labels: [String], _ series: [(name: String, color: AvoRGB, values: [Double?], width: Double)],
                   reversed: Bool, format: (Double) -> String, pointLabels: Bool) {
        let all: [Double] = series.flatMap { $0.values.compactMap { $0 } }
        guard labels.count >= 2, let lo0 = all.min(), let hi0 = all.max() else { return }
        let h: Double = 150
        ensure(h + 44)
        sub(caption)
        let pad: Double = max((hi0 - lo0) * 0.12, 0.5)
        let lo: Double = lo0 - pad
        let hi: Double = hi0 + pad
        let x0: Double = m + 30
        let cw: Double = w - 36
        pdf.fillRect(m, y, w, h, ReportBuilder.panel)
        let top: Double = y + 10
        let bottom: Double = y + h - 22
        func py(_ v: Double) -> Double {
            let f: Double = (v - lo) / max(hi - lo, 1e-9)
            return reversed ? top + f * (bottom - top) : bottom - f * (bottom - top)
        }
        func px(_ i: Int) -> Double { x0 + cw * (Double(i) + 0.5) / Double(labels.count) }
        for k in 0...3 {
            let v: Double = lo + (hi - lo) * Double(k) / 3
            let yy: Double = py(v)
            pdf.line(x0, yy, m + w - 4, yy, ReportBuilder.lineColor, width: 0.3)
            pdf.text(x0 - 4, yy - 3, format(v), size: 6.5, bold: false, color: ReportBuilder.dim, align: .right)
        }
        for (i, l) in labels.enumerated() {
            pdf.text(px(i), bottom + 6, l, size: 6.2, bold: false, color: ReportBuilder.dim, align: .center)
        }
        for s in series {
            var run: [(x: Double, y: Double)] = []
            for (i, v) in s.values.enumerated() {
                if let v = v { run.append((x: px(i), y: py(v))) } else if run.count > 1 { pdf.polyline(run, s.color, width: s.width); run = [] } else { run = [] }
            }
            if run.count > 1 { pdf.polyline(run, s.color, width: s.width) }
            for (i, v) in s.values.enumerated() {
                guard let v = v else { continue }
                pdf.circle(px(i), py(v), s.width > 1.5 ? 2.4 : 1.6, s.color)
            }
        }
        if pointLabels, let first = series.first {
            for (i, v) in first.values.enumerated() {
                guard let v = v else { continue }
                pdf.text(px(i), py(v) - 12, format(v), size: 6.8, bold: true, color: ReportBuilder.ink, align: .center)
            }
        }
        y += h + 4
        if series.count > 1 { legend(series.map { ($0.name, $0.color) }) } else { y += 4 }
    }

    /// Bars over the sectors with the value on top.
    func barChart(_ caption: String, _ labels: [String], _ values: [Double?], format: (Double) -> String) {
        guard labels.count >= 1 else { return }
        let h: Double = 140
        ensure(h + 34)
        sub(caption)
        let topV: Double = max(1, (values.compactMap { $0 }.max() ?? 1) * 1.15)
        let x0: Double = m + 8
        let cw: Double = w - 16
        pdf.fillRect(m, y, w, h, ReportBuilder.panel)
        let bottom: Double = y + h - 22
        let slot: Double = cw / Double(labels.count)
        for (i, l) in labels.enumerated() {
            let cx: Double = x0 + slot * (Double(i) + 0.5)
            pdf.text(cx, bottom + 6, l, size: 6.2, bold: false, color: ReportBuilder.dim, align: .center)
            guard let v = values[safe: i] ?? nil else { continue }
            let bh: Double = (bottom - y - 18) * v / topV
            pdf.fillRect(cx - slot * 0.3, bottom - bh, slot * 0.6, bh, v < 0.05 ? RaceEnginePdfWriter.green : RaceEnginePdfWriter.amber)
            pdf.text(cx, bottom - bh - 10, format(v), size: 6.8, bold: true, color: ReportBuilder.ink, align: .center)
        }
        pdf.line(x0, bottom, m + w - 8, bottom, ReportBuilder.lineColor, width: 0.5)
        y += h + 8
    }

    // ------------------------------------------------------------------ document
    func build() -> Data {
        let r: Race = d.race
        let us: RaceRunner = d.us
        let rep: RaceDeepReport = d.report
        header()

        title("En una frase", keep: 120)
        paragraph(rep.subhead, size: 8.5, color: ReportBuilder.dim)
        paragraph(rep.headline, size: 12, bold: true)
        tiles([
            ("Puesto", r.finishText, nil),
            ("Tiempo", RaceFormat.official(us.officialTimeS), nil),
            ("Al ganador", r.ourGapToWinnerS.map { RaceFormat.seconds($0) } ?? "—", r.ourGapToWinnerS.map { RaceFormat.lengths($0) }),
            ("Redk", RaceFormat.official(us.redk), "por km"),
            ("Pista", r.goingValue?.spanish ?? "Sin indicar", r.goingValue?.french),
        ])
        paragraph("Confianza \(rep.confidence.rawValue.lowercased()): \(rep.confidenceReason).", size: 8, color: ReportBuilder.dim)

        title("Cómo fue la carrera")
        bullets(rep.phases.map { ($0.timeRank.map { "[\($0).º en rapidez] " } ?? "") + $0.sentence })

        let labels: [String] = rep.sectors.map { $0.shortLabel }
        if rep.sectors.contains(where: { $0.position != nil }) {
            lineChart("Puesto en cada tramo (arriba = en cabeza)", labels,
                      [(name: "Puesto", color: ReportBuilder.red, values: rep.sectors.map { $0.position.map { Double($0) } }, width: 2)],
                      reversed: true, format: { "\(Int($0.rounded()))" }, pointLabels: true)
        }
        if rep.sectors.contains(where: { $0.gapToLeaderS != nil }) {
            barChart("Distancia al primero al final de cada tramo (cuerpos)", labels,
                     rep.sectors.map { $0.gapToLeaderS.map { $0 / RaceFormat.secondsPerLength } }, format: { AvoFormat.f($0, 1) })
        }
        if rep.sectors.contains(where: { $0.ourSpeedKmh != nil }) {
            lineChart("Velocidad en cada tramo (km/h)", labels, [
                (name: "Nuestro caballo", color: ReportBuilder.red, values: rep.sectors.map { $0.ourSpeedKmh }, width: 2.2),
                (name: "Ganador", color: RaceEnginePdfWriter.green, values: rep.sectors.map { $0.winnerSpeedKmh }, width: 1.2),
                (name: "Caballo medio", color: RaceEnginePdfWriter.grey, values: rep.sectors.map { $0.fieldSpeedKmh }, width: 1.2),
            ], reversed: false, format: { AvoFormat.f($0, 1) }, pointLabels: false)
            table(["Tramo", "Puesto", "Rapidez", "Al primero", "km/h", "Ganador", "Medio", "Zancada"],
                  [1.3, 0.8, 0.8, 1, 0.9, 0.9, 0.9, 0.9],
                  rep.sectors.map { (s: RaceDeepSectorRow) -> [String] in
                      [s.shortLabel, RaceFormat.place(s.position), RaceFormat.place(s.speedRank),
                       s.gapToLeaderS.map { AvoFormat.f($0 / RaceFormat.secondsPerLength, 1) + " c." } ?? "—",
                       s.ourSpeedKmh.map { AvoFormat.f($0, 1) } ?? "—", s.winnerSpeedKmh.map { AvoFormat.f($0, 1) } ?? "—",
                       s.fieldSpeedKmh.map { AvoFormat.f($0, 1) } ?? "—", s.strideM.map { AvoFormat.f($0, 2) + " m" } ?? "—"]
                  })
        }

        title("Rivales")
        paragraph(rep.rivalsText)
        table(["Lleg.", "Caballo", "Jockey", "Hoy", "Cara a cara", "Otras carreras"], [0.6, 2, 1.6, 1.1, 1, 1.8],
              rep.rivals.map { (v: RaceRival) -> [String] in
                  let today: String = v.todayDiffS.map { $0 > 0.005 ? "le ganamos " + RaceFormat.seconds($0) : ($0 < -0.005 ? "nos ganó " + RaceFormat.seconds(-$0) : "igual") } ?? "—"
                  let others: String = v.runs.filter { !$0.withUs }.prefix(4).map { RaceDeepEngine.placeText($0.rivalPlace, $0.fieldSize) }.joined(separator: ", ")
                  return [RaceFormat.place(v.finish), v.name, v.jockey, today, v.meetings > 0 ? "\(v.beatenByUs)–\(v.beatUs)" : "—",
                          others.isEmpty ? "—" : others]
              })

        title("Sus carreras")
        bullets([rep.distanceText, rep.goingText, rep.hippodromeText])
        let hist: [RacePastEntry] = Array(rep.history.reversed())
        table(["Fecha", "Hipódromo", "Distancia", "Pista", "Puesto", "Redk", "Al ganador"], [1, 1.6, 0.9, 1.2, 0.8, 0.9, 1],
              hist.map { (e: RacePastEntry) -> [String] in
                  [e.date.map { AvoTime.text($0, "dd/MM/yy") } ?? "—", e.hippodrome + (e.isCurrent ? " (hoy)" : ""),
                   AvoFormat.n0(e.distanceM) + " m", e.going?.spanish ?? "—", RaceDeepEngine.placeText(e.place, e.fieldSize),
                   RaceFormat.official(e.redk), e.gapToWinnerS.map { $0 > 0.005 ? "+" + RaceFormat.seconds($0) : "Ganó" } ?? "—"]
              }, highlight: Set(hist.indices.filter { hist[$0].isCurrent }))

        title("Entrenamientos antes de la carrera")
        bullets(rep.trainingLines, dot: RaceEnginePdfWriter.cyan)
        let works: [TrainingFastWork] = rep.trainingWorks.filter { $0.date != nil }
        if works.count >= 2 {
            lineChart("Mejor 200 m de cada trabajo rápido (km/h), del más antiguo al más reciente",
                      works.map { AvoTime.text($0.date, "dd/MM") },
                      [(name: "Mejor 200 m", color: RaceEnginePdfWriter.cyan, values: works.map { $0.peak200Kmh }, width: 1.6)],
                      reversed: false, format: { AvoFormat.f($0, 1) }, pointLabels: works.count <= 14)
        }

        title("Conclusiones")
        bullets(rep.conclusions)
        if !rep.nextTime.isEmpty {
            sub("Para la próxima (orientativo)", keep: 30)
            bullets(rep.nextTime, dot: RaceEnginePdfWriter.cyan)
        }
        if !r.notes.trimmed.isEmpty {
            title("Notas", keep: 30)
            paragraph(r.notes)
        }
        // trainer 20/11/2026: «Elimina del PDF el cómo se calcula» (the method stays only on the screen)
        return pdf.save()
    }
}
