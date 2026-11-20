import SwiftUI
import Charts

/// «Análisis motor» of a race (trainer's sketch 19/11/2026, build 173: button next to «Informe PDF»). Full-screen,
/// plain-language reading of the race: what happened in each part, the rivals and the earlier meetings with them, the
/// earlier races of the horse (distance, state of the track, hippodrome) and its trainings, analysed with the current AVO
/// engine. The logic lives in Core/RaceDeepEngine.swift (unit tested); this view only draws it.
struct RaceEngineAnalysisView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let raceId: String

    @State private var started: Bool = false
    @State private var showMethod: Bool = false
    @State private var pdfFile: ExportedFile? = nil
    @State private var pdfError: String = ""

    private var model: RacesModel { app.races }
    private var race: Race? { model.race(raceId) }
    private var progress: String { model.engineProgress[raceId] ?? "" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let r = race, let rep = model.deepReport(r) {
                        if !progress.isEmpty { progressCard }
                        headlineCard(r, rep)
                        storyCard(rep)
                        HStack(alignment: .top, spacing: 14) {
                            positionChart(rep).frame(maxWidth: .infinity)
                            gapChart(rep).frame(maxWidth: .infinity)
                        }
                        speedChart(rep)
                        rivalsCard(rep)
                        historyCard(r, rep)
                        trainingsCard(rep)
                        conclusionsCard(rep)
                        methodCard(rep)
                    } else {
                        AvoCard { AvoNoData(text: "El caballo no está identificado entre los participantes de esta carrera.") }
                    }
                }
                .padding(18)
            }
            .background(Avo.bg)
            .navigationTitle("Análisis motor · \(race?.title ?? "Carrera")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { dismiss() }.accessibilityIdentifier("raceEngine.close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // trainer 20/11/2026: «Botón de informe PDF» on this screen
                    Button {
                        guard let r = race else { return }
                        do { pdfFile = try model.exportEnginePdf(r) } catch { pdfError = error.localizedDescription }
                    } label: {
                        Label("Informe PDF", systemImage: "doc.richtext")
                    }
                    .buttonStyle(.avoPrimary)
                    .disabled(race?.ourRunner == nil || !progress.isEmpty)
                    .accessibilityIdentifier("raceEngine.pdf")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let r = race { Task { @MainActor in await model.runEngineAnalysis(r, force: true) } }
                    } label: {
                        Label("Volver a analizar", systemImage: "arrow.clockwise")
                    }
                    .disabled(!progress.isEmpty || race == nil)
                    .accessibilityIdentifier("raceEngine.rerun")
                }
            }
        }
        .fullScreenCover(item: $pdfFile) { (f: ExportedFile) in
            PdfViewerSheet(file: f)
                .avoColorScheme()
        }
        .alert("Informe PDF", isPresented: Binding(get: { !pdfError.isEmpty }, set: { if !$0 { pdfError = "" } })) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(pdfError)
        }
        .onAppear {
            guard !started, let r = race else { return }
            started = true
            Task { @MainActor in await model.runEngineAnalysis(r, force: false) }
        }
    }

    // ------------------------------------------------------------------ cards
    private var progressCard: some View {
        AvoCard {
            HStack(spacing: 10) {
                ProgressView()
                Text(progress).font(.callout).foregroundStyle(Avo.text)
                Spacer()
            }
        }
    }

    private func headlineCard(_ r: Race, _ rep: RaceDeepReport) -> some View {
        AvoCard(title: "En una frase", subtitle: rep.subhead) {
            Text(rep.headline).font(.title3.weight(.semibold)).foregroundStyle(Avo.text).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 12) {
                AvoMetric(label: "Puesto", value: r.finishText)
                AvoMetric(label: "Tiempo", value: RaceFormat.official(r.ourRunner?.officialTimeS))
                AvoMetric(label: "Al ganador", value: r.ourGapToWinnerS.map { RaceFormat.seconds($0) } ?? "—",
                          caption: r.ourGapToWinnerS.map { RaceFormat.lengths($0) })
                AvoMetric(label: "Redk", value: RaceFormat.official(r.ourRunner?.redk), caption: "por km")
                goingPicker(r)
            }
            HStack(spacing: 8) {
                Circle().fill(confidenceColor(rep.confidence)).frame(width: 8, height: 8)
                Text("Confianza \(rep.confidence.rawValue.lowercased()): \(rep.confidenceReason).")
                    .font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func goingPicker(_ r: Race) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ESTADO DE LA PISTA").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.silver)
            Menu {
                Button("Sin indicar") { model.setGoing(r.id, nil) }
                ForEach(RaceGoing.allCases) { (g: RaceGoing) in
                    Button(g.label) { model.setGoing(r.id, g) }
                }
            } label: {
                Label(r.goingValue?.spanish ?? "Indicar…", systemImage: "cloud.rain")
                    .font(.callout.weight(.semibold)).foregroundStyle(Avo.red)
            }
            .accessibilityIdentifier("raceEngine.going")
            Text(r.goingValue?.french ?? "No viene en el PDF").font(.caption2).foregroundStyle(Avo.textDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func storyCard(_ rep: RaceDeepReport) -> some View {
        AvoCard(title: "Cómo fue la carrera", subtitle: "Salida, desarrollo y final, comparados con el ganador y con el resto") {
            ForEach(rep.phases) { (p: RaceDeepPhase) in
                HStack(alignment: .top, spacing: 10) {
                    Text(p.timeRank.map { "\($0).º" } ?? "—")
                        .font(.headline.monospacedDigit()).foregroundStyle(rankColor(p.timeRank, p.fieldSize))
                        .lineLimit(1).fixedSize()
                        .frame(minWidth: 52, alignment: .leading)
                    Text(p.sentence).font(.callout).foregroundStyle(Avo.text).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("El número de la izquierda es el puesto de rapidez en esa parte (1.º = el más rápido de todos).")
                .font(.caption2).foregroundStyle(Avo.textDim)
        }
    }

    // ------------------------------------------------------------------ charts
    private func positionChart(_ rep: RaceDeepReport) -> some View {
        let rows: [RaceDeepSectorRow] = rep.sectors.filter { $0.position != nil }
        return AvoCard(title: "Puesto en cada tramo", subtitle: "Arriba = en cabeza") {
            if rows.isEmpty {
                AvoNoData(text: "El PDF no trae posiciones")
            } else {
                Chart(rows) { (r: RaceDeepSectorRow) in
                    LineMark(x: .value("Tramo", r.shortLabel), y: .value("Puesto", r.position ?? 0))
                        .foregroundStyle(Avo.red).lineStyle(StrokeStyle(lineWidth: 3))
                    PointMark(x: .value("Tramo", r.shortLabel), y: .value("Puesto", r.position ?? 0))
                        .foregroundStyle(Avo.red)
                        .annotation(position: .top) { Text("\(r.position ?? 0).º").font(.caption2).foregroundStyle(Avo.text) }
                }
                .chartYScale(domain: .automatic(includesZero: false, reversed: true))
                .frame(height: 240)
            }
        }
    }

    private func gapChart(_ rep: RaceDeepReport) -> some View {
        let rows: [RaceDeepSectorRow] = rep.sectors.filter { $0.gapToLeaderS != nil }
        return AvoCard(title: "Distancia al primero", subtitle: "En cuerpos, al final de cada tramo (0 = en cabeza)") {
            if rows.isEmpty {
                AvoNoData(text: "Sin tiempos acumulados")
            } else {
                Chart(rows) { (r: RaceDeepSectorRow) in
                    BarMark(x: .value("Tramo", r.shortLabel), y: .value("Cuerpos", (r.gapToLeaderS ?? 0) / RaceFormat.secondsPerLength))
                        .foregroundStyle((r.gapToLeaderS ?? 0) < 0.01 ? Avo.ok : Avo.warn)
                        .annotation(position: .top) {
                            Text(AvoFormat.f((r.gapToLeaderS ?? 0) / RaceFormat.secondsPerLength, 1)).font(.caption2).foregroundStyle(Avo.text)
                        }
                }
                .frame(height: 240)
            }
        }
    }

    private struct SpeedPoint: Identifiable {
        var series: String
        var label: String
        var kmh: Double
        var id: String { series + label }
    }

    private func speedChart(_ rep: RaceDeepReport) -> some View {
        var pts: [SpeedPoint] = []
        for r in rep.sectors {
            if let v = r.ourSpeedKmh { pts.append(SpeedPoint(series: "Nuestro caballo", label: r.shortLabel, kmh: v)) }
            if let v = r.winnerSpeedKmh { pts.append(SpeedPoint(series: "Ganador", label: r.shortLabel, kmh: v)) }
            if let v = r.fieldSpeedKmh { pts.append(SpeedPoint(series: "Caballo medio", label: r.shortLabel, kmh: v)) }
        }
        let labels: [String] = rep.sectors.map { $0.shortLabel }
        return AvoCard(title: "Velocidad en cada tramo", subtitle: "Nuestro caballo, el ganador y el caballo medio (km/h)") {
            if pts.isEmpty {
                AvoNoData(text: "Sin velocidades por tramo")
            } else {
                Chart(pts) { (p: SpeedPoint) in
                    LineMark(x: .value("Tramo", p.label), y: .value("km/h", p.kmh), series: .value("Serie", p.series))
                        .foregroundStyle(by: .value("Serie", p.series))
                        .lineStyle(StrokeStyle(lineWidth: p.series == "Nuestro caballo" ? 3.5 : 2, dash: p.series == "Caballo medio" ? [5, 4] : []))
                    PointMark(x: .value("Tramo", p.label), y: .value("km/h", p.kmh))
                        .foregroundStyle(by: .value("Serie", p.series))
                }
                .chartForegroundStyleScale(["Nuestro caballo": Avo.red, "Ganador": Avo.ok, "Caballo medio": Avo.silver])
                .chartXScale(domain: labels)
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 280)
                speedTable(rep)
            }
        }
    }

    private func speedTable(_ rep: RaceDeepReport) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                GridRow {
                    Text("Tramo").bold()
                    ForEach(rep.sectors) { (r: RaceDeepSectorRow) in Text(r.shortLabel).bold() }
                }
                GridRow {
                    Text("Rapidez")
                    ForEach(rep.sectors) { (r: RaceDeepSectorRow) in
                        Text(r.speedRank.map { "\($0).º" } ?? "—").foregroundStyle(rankColor(r.speedRank, rep.rivals.count + 1))
                    }
                }
                GridRow {
                    Text("Zancada")
                    ForEach(rep.sectors) { (r: RaceDeepSectorRow) in Text(r.strideM.map { AvoFormat.f($0, 2) + " m" } ?? "—") }
                }
            }
            .font(.caption.monospacedDigit()).foregroundStyle(Avo.text)
        }
    }

    // ------------------------------------------------------------------ rivals
    private func rivalsCard(_ rep: RaceDeepReport) -> some View {
        AvoCard(title: "Rivales", subtitle: "Hoy y en las carreras anteriores del iPad") {
            Text(rep.rivalsText).font(.callout).foregroundStyle(Avo.text).fixedSize(horizontal: false, vertical: true)
            ForEach(rep.rivals) { (r: RaceRival) in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(RaceFormat.place(r.finish)).font(.callout.monospacedDigit().weight(.semibold)).frame(width: 36, alignment: .leading)
                        Text(r.name).font(.callout.weight(.semibold)).foregroundStyle(Avo.text)
                        Text(r.jockey).font(.caption).foregroundStyle(Avo.textDim)
                        Spacer()
                        if r.meetings > 0 {
                            Text("Cara a cara \(r.beatenByUs)–\(r.beatUs)").font(.caption.weight(.semibold))
                                .foregroundStyle(r.beatenByUs >= r.beatUs ? Avo.ok : Avo.bad)
                        }
                    }
                    Text(r.sentence).font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 44)
                }
                Divider().overlay(Avo.line)
            }
        }
    }

    // ------------------------------------------------------------------ history
    private func historyCard(_ r: Race, _ rep: RaceDeepReport) -> some View {
        AvoCard(title: "Sus carreras", subtitle: "Distancia, estado de la pista e hipódromo") {
            VStack(alignment: .leading, spacing: 6) {
                insight("ruler", rep.distanceText)
                insight("cloud.rain", rep.goingText)
                if !rep.hippodromeText.isEmpty { insight("mappin.and.ellipse", rep.hippodromeText) }
            }
            if rep.history.count > 1 {
                Chart(rep.history) { (e: RacePastEntry) in
                    PointMark(x: .value("Fecha", e.date ?? Date()), y: .value("Puesto medio", 1 - (e.relative ?? 1)))
                        .foregroundStyle(e.isCurrent ? Avo.red : (e.sameDistance ? Avo.cyan : Avo.silver))
                        .symbolSize(e.isCurrent ? 140 : 70)
                        .annotation(position: .top) { Text(RaceDeepEngine.placeText(e.place, e.fieldSize)).font(.caption2) }
                }
                .chartYScale(domain: 0...1.15)
                .chartYAxis {
                    AxisMarks(values: [0.0, 0.5, 1.0]) { (v: AxisValue) in
                        AxisGridLine().foregroundStyle(Avo.line)
                        AxisValueLabel {
                            if let d = v.as(Double.self) { Text(d >= 1 ? "Ganó" : (d <= 0 ? "Último" : "Mitad")).font(.caption2) }
                        }
                    }
                }
                .frame(height: 200)
                Text("Rojo: esta carrera · azul: misma distancia (±100 m) · gris: otras distancias.")
                    .font(.caption2).foregroundStyle(Avo.textDim)
            }
            ForEach(rep.history.reversed()) { (e: RacePastEntry) in
                HStack(spacing: 10) {
                    Text(e.date.map { AvoTime.text($0, "dd/MM/yy") } ?? "—").frame(width: 70, alignment: .leading)
                    Text(e.hippodrome).lineLimit(1).frame(width: 130, alignment: .leading)
                    Text(AvoFormat.n0(e.distanceM) + " m").frame(width: 70, alignment: .leading)
                        .foregroundStyle(e.sameDistance ? Avo.cyan : Avo.text)
                    Text(e.going?.spanish ?? "—").frame(width: 110, alignment: .leading)
                        .foregroundStyle(e.sameGoing ? Avo.cyan : Avo.textDim)
                    Text(RaceDeepEngine.placeText(e.place, e.fieldSize)).bold().frame(width: 50, alignment: .leading)
                    Text(RaceFormat.official(e.redk)).frame(width: 70, alignment: .leading)
                    Text(e.gapToWinnerS.map { $0 > 0.005 ? "+" + RaceFormat.seconds($0) : "Ganó" } ?? "—")
                    Spacer()
                    if e.isCurrent { Text("HOY").font(.caption2.weight(.bold)).foregroundStyle(Avo.red) }
                }
                .font(.caption.monospacedDigit()).foregroundStyle(Avo.text)
            }
            Text("Columnas: fecha, hipódromo, distancia, pista, puesto, reducción kilométrica y diferencia con el ganador.")
                .font(.caption2).foregroundStyle(Avo.textDim)
        }
    }

    private func insight(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(Avo.red).frame(width: 20)
            Text(text).font(.callout).foregroundStyle(Avo.text).fixedSize(horizontal: false, vertical: true)
        }
    }

    // ------------------------------------------------------------------ trainings
    private func trainingsCard(_ rep: RaceDeepReport) -> some View {
        AvoCard(title: "Entrenamientos antes de la carrera", subtitle: "Analizados con el motor \(EquineEngine.version())") {
            ForEach(Array(rep.trainingLines.enumerated()), id: \.offset) { (x: (offset: Int, element: String)) in
                insight("figure.equestrian.sports", x.element)
            }
            let works: [TrainingFastWork] = rep.trainingWorks.filter { $0.date != nil }
            if works.count >= 2 {
                Chart(Array(works.enumerated()), id: \.offset) { (x: (offset: Int, element: TrainingFastWork)) in
                    PointMark(x: .value("Fecha", x.element.date ?? Date()), y: .value("Mejor 200 m (km/h)", x.element.peak200Kmh))
                        .foregroundStyle(Avo.cyan)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 180)
                Text("Cada punto es un trabajo rápido: su mejor 200 m en km/h. En carrera siempre se va más rápido que en el entrenamiento.")
                    .font(.caption2).foregroundStyle(Avo.textDim)
            }
        }
    }

    // ------------------------------------------------------------------ conclusions
    private func conclusionsCard(_ rep: RaceDeepReport) -> some View {
        AvoCard(title: "Conclusiones", subtitle: "Lo importante, en pocas líneas") {
            ForEach(Array(rep.conclusions.enumerated()), id: \.offset) { (x: (offset: Int, element: String)) in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle().fill(Avo.red).frame(width: 6, height: 6)
                    Text(x.element).font(.callout).foregroundStyle(Avo.text).fixedSize(horizontal: false, vertical: true)
                }
            }
            if !rep.nextTime.isEmpty {
                Text("PARA LA PRÓXIMA (ORIENTATIVO)").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(Avo.silver).padding(.top, 6)
                ForEach(Array(rep.nextTime.enumerated()), id: \.offset) { (x: (offset: Int, element: String)) in
                    insight("arrow.forward.circle", x.element)
                }
            }
        }
    }

    private func methodCard(_ rep: RaceDeepReport) -> some View {
        AvoCard {
            Button {
                withAnimation { showMethod.toggle() }
            } label: {
                HStack {
                    Text("CÓMO SE CALCULA").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(Avo.silver)
                    Spacer()
                    Image(systemName: showMethod ? "chevron.up" : "chevron.down").foregroundStyle(Avo.red)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showMethod {
                ForEach(Array(rep.method.enumerated()), id: \.offset) { (x: (offset: Int, element: String)) in
                    Text("• " + x.element).font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // ------------------------------------------------------------------ colours
    private func rankColor(_ rank: Int?, _ field: Int) -> Color {
        guard let r = rank, field > 1 else { return Avo.text }
        if r == 1 { return Avo.ok }
        return r <= (field + 1) / 2 ? Avo.text : Avo.warn
    }

    private func confidenceColor(_ c: RaceConfidence) -> Color {
        switch c {
        case .high: return Avo.ok
        case .medium: return Avo.warn
        case .low: return Avo.bad
        }
    }
}
