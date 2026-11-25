import SwiftUI

/// Petición de ficha desde el Calendario: caballo y día.
struct PlanFichaRequest: Identifiable {
    let horseKey: String
    let horseName: String
    let day: String
    var id: String { horseKey + "|" + day }
}

/// Ficha del entrenamiento de un caballo en un día (boceto del entrenador 25/11/2026): lo recomendado por el planificador
/// y, si ya entrenó, lo realizado y la comparación, con «Informe PDF» para enviarla o guardarla. Orientativa y sin
/// calibrar: el entrenador decide.
struct PlanFichaView: View {
    @Environment(AppModel.self) private var app
    let request: PlanFichaRequest
    let close: () -> Void
    let openSession: (String) -> Void

    @State private var ficha: PlanFicha? = nil
    @State private var pdfURL: URL? = nil
    @State private var pdfError: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let f = ficha {
                        content(f)
                    } else {
                        AvoCard {
                            HStack(spacing: 10) {
                                ProgressView().controlSize(.small)
                                Text("Preparando la ficha con el motor…").font(.callout).foregroundStyle(Avo.textDim)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Avo.bg)
            .navigationTitle("\(request.horseName) · \(PlanFichaText.dayTitle(request.day))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { close() } }
                ToolbarItem(placement: .primaryAction) {
                    if let u = pdfURL {
                        ShareLink(item: u) { Label("Enviar PDF", systemImage: "square.and.arrow.up") }
                    } else {
                        Button { makePdf() } label: { Label("Informe PDF", systemImage: "doc.richtext") }
                            .disabled(ficha == nil)
                    }
                }
            }
        }
        .task(id: request.id) {
            ficha = await app.weekPlans.ficha(horseKey: request.horseKey, name: request.horseName, day: request.day)
        }
        .accessibilityIdentifier("calendar.ficha")
    }

    @ViewBuilder
    private func content(_ f: PlanFicha) -> some View {
        // recomendado
        AvoCard(title: "Entrenamiento recomendado", subtitle: f.recommendedOrigin.isEmpty ? "Planificador del motor · sin calibrar" : f.recommendedOrigin) {
            if let r = f.recommended {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(r.typeText).font(.title2.weight(.semibold)).foregroundStyle(PlanFichaText.color(r.type))
                    Text(KbText.sentence(r.reason)).font(.callout).foregroundStyle(Avo.text).fixedSize(horizontal: false, vertical: true)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                    AvoMetric(label: "Distancia rápida", value: r.fastMaxM.map { "hasta \(KbText.metres($0))" } ?? (r.type == "RAPIDO" ? "Sin tope propio" : "—"))
                    AvoMetric(label: "Fase", value: PlanFichaText.phase(f.phase))
                    AvoMetric(label: "Pautas", value: r.rules.isEmpty ? "—" : r.rules.map { WeekPlan.ruleTitle($0) }.joined(separator: " · "))
                }
            } else {
                AvoNoData(text: f.error.map { "No se pudo calcular: \($0)" } ?? "Sin recomendación del planificador para ese día")
            }
        }
        // realizado
        if f.hasRealized {
            AvoCard(title: "Realizado", subtitle: "\(f.sessions.count) entrenamiento\(f.sessions.count == 1 ? "" : "s") ese día · toca uno para abrirlo") {
                if let d = f.realized {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(d.typeText).font(.title2.weight(.semibold)).foregroundStyle(Avo.ok)
                        Text(KbText.sentence(d.reason)).font(.callout).foregroundStyle(Avo.text).fixedSize(horizontal: false, vertical: true)
                    }
                }
                ForEach(f.sessions) { (s: PlanFichaSession) in
                    Button { openSession(s.id) } label: {
                        HStack(spacing: 10) {
                            Text(AvoTime.text(s.start, "HH:mm")).font(.callout.monospacedDigit()).foregroundStyle(Avo.textDim)
                            Text(s.rider.isEmpty ? "Sin jinete" : s.rider).font(.callout).foregroundStyle(Avo.text)
                            Spacer()
                            Text(PlanFichaText.session(s)).font(.caption.monospacedDigit()).foregroundStyle(Avo.silver)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Avo.textDim)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            AvoCard(title: "Recomendado frente a realizado", subtitle: "Orientativo · el entrenador decide") {
                HStack(spacing: 8) {
                    if let m = f.matches {
                        AvoPill(text: m ? "SEGÚN LO RECOMENDADO" : "DISTINTO DE LO RECOMENDADO", color: m ? Avo.ok : Avo.warn)
                    }
                    Spacer()
                }
                ForEach(Array(f.comparison.enumerated()), id: \.offset) { (p: (offset: Int, element: String)) in
                    Text("• " + p.element).font(.callout).foregroundStyle(Avo.text).fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if request.day < WeekPlansModel.today {
            AvoCard(title: "Realizado") { AvoNoData(text: "Sin entrenamiento registrado ese día") }
        }
        if let e = pdfError {
            Text(e).font(.caption).foregroundStyle(Avo.warn)
        }
        if let u = pdfURL {
            Text("Informe guardado: \(u.lastPathComponent) (también en Archivos › AVO Horse › Informes)").font(.caption2).foregroundStyle(Avo.textDim)
        }
        Text("Propuesta del planificador sin calibrar con datos propios: no cambia el estado del caballo, no predice lesiones y el entrenador decide.")
            .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
    }

    private func makePdf() {
        guard let f = ficha else { return }
        do {
            let dir: String = AvoFiles.join(app.paths.root, "exportaciones")
            AvoFiles.ensureDir(dir)
            let path: String = AvoFiles.join(dir, PlanFichaPdf.fileName(f))
            try PlanFichaPdf.build(f).save(to: path)
            pdfURL = URL(fileURLWithPath: path)
            pdfError = nil
        } catch {
            pdfError = "No se pudo crear el PDF: \(error.localizedDescription)"
        }
    }
}

/// Textos comunes de la ficha (vista y PDF).
enum PlanFichaText {
    static func dayTitle(_ day: String) -> String {
        guard let d = AvoTime.formatter("yyyy-MM-dd").date(from: day) else { return day }
        return AvoTime.formatter("EEEE d 'de' MMMM yyyy").string(from: d)
    }

    static func phase(_ p: String) -> String {
        switch p {
        case "NORMAL": return "Semana normal"
        case "POTRO_2_ANOS": return "Potro de 2 años"
        case "REINCORPORACION_LENTA": return "Vuelta al trabajo: fase lenta"
        case "REINCORPORACION_RAPIDO": return "Vuelta al trabajo rápido"
        default: return p.isEmpty ? "—" : p
        }
    }

    static func session(_ s: PlanFichaSession) -> String {
        DotNetFormat.custom(s.distanceKm, "0.00", spanish: true) + " km · " + TimeText.clock(s.durationS)
    }

    static func color(_ t: String) -> Color {
        switch t {
        case "RAPIDO": return Avo.red
        case "CARRERA": return Avo.warn
        case "LIBRE": return Avo.ok
        default: return Avo.text
        }
    }
}

/// Informe PDF de la ficha (mismo estilo que los informes de AVO: banda oscura con el logo y línea roja).
enum PlanFichaPdf {
    /// «Caballo_AAAA-MM-DD_0000_Planificador.pdf»: la sincronización con Archivos lo deja en Informes › caballo.
    static func fileName(_ f: PlanFicha) -> String {
        let safe: String = f.horseName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: " ", with: "_")
        return "\(safe)_\(f.day)_0000_Planificador.pdf"
    }

    static func build(_ f: PlanFicha) -> PdfDocument {
        let pdf: PdfDocument = PdfDocument()
        pdf.title = "Planificador AVO · \(f.horseName) · \(f.day)"
        pdf.newPage()
        let m: Double = 40
        let w: Double = pdf.width - 2 * m
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
        pdf.text(pdf.width - m, 20, f.hasRealized ? "RECOMENDADO FRENTE A REALIZADO" : "ENTRENAMIENTO RECOMENDADO", size: 11, bold: true,
                 color: ReportBuilder.white, align: .right)
        pdf.text(pdf.width - m, 40, "\(f.horseName) · \(PlanFichaText.dayTitle(f.day))", size: 9, color: (r: 0xC9, g: 0xCB, b: 0xD1), align: .right)
        var y: Double = band + 30
        func section(_ title: String) {
            y += 6
            pdf.text(m, y, title.uppercased(), size: 10, bold: true, color: ReportBuilder.red)
            y += 6
            pdf.line(m, y, m + w, y, ReportBuilder.dim, width: 0.4)
            y += 16
        }
        func kv(_ k: String, _ v: String) {
            pdf.text(m, y, k, size: 9.5, color: ReportBuilder.dim)
            y = pdf.paragraph(m + 150, y, w - 150, v, size: 9.5, color: ReportBuilder.ink) + 4
        }
        section("Entrenamiento recomendado")
        if let r = f.recommended {
            kv("Tipo de día", r.typeText)
            kv("Indicación", KbText.sentence(r.reason))
            kv("Distancia rápida", r.fastMaxM.map { "hasta " + KbText.metres($0) } ?? (r.type == "RAPIDO" ? "sin tope propio" : "—"))
            kv("Fase", PlanFichaText.phase(f.phase))
            kv("Pautas", r.rules.isEmpty ? "—" : r.rules.map { WeekPlan.ruleTitle($0) }.joined(separator: " · "))
            kv("Origen", f.recommendedOrigin)
        } else {
            kv("Recomendación", "Sin recomendación del planificador para ese día")
        }
        if f.hasRealized {
            section("Realizado")
            if let d = f.realized {
                kv("Tipo de día", d.typeText)
                kv("Detalle", KbText.sentence(d.reason))
            }
            for s in f.sessions {
                kv(AvoTime.text(s.start, "HH:mm") + (s.rider.isEmpty ? "" : " · " + s.rider), PlanFichaText.session(s))
            }
            section("Recomendado frente a realizado")
            if let mt = f.matches {
                pdf.text(m, y, mt ? "SEGÚN LO RECOMENDADO" : "DISTINTO DE LO RECOMENDADO", size: 10.5, bold: true,
                         color: mt ? (r: 0x1F, g: 0x9D, b: 0x55) : (r: 0xD9, g: 0x82, b: 0x1E))
                y += 18
            }
            for c in f.comparison {
                y = pdf.paragraph(m, y, w, "• " + c, size: 9.5, color: ReportBuilder.ink) + 3
            }
        }
        y += 14
        y = pdf.paragraph(m, y, w, "Propuesta del planificador del motor AVO Performance Equine \(f.engine), sin calibrar con datos propios: no cambia el estado del caballo, no predice lesiones y el entrenador decide.",
                          size: 8, color: ReportBuilder.dim)
        _ = pdf.paragraph(m, y + 2, w, "Generado el \(AvoTime.text(Date(), "dd/MM/yyyy HH:mm")) (Europe/Madrid).", size: 8, color: ReportBuilder.dim)
        return pdf
    }
}
