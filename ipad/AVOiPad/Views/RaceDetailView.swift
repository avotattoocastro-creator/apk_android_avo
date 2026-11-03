import SwiftUI
import Charts

/// Race card («Ficha de la carrera»): header, result of our horse, the whole transcribed race, charts per 200 m sector and
/// «Análisis según los entrenamientos» (Core/RaceAnalysis.swift).
struct RaceDetailView: View {
    @Environment(AppModel.self) private var app
    @Bindable var model: RacesModel
    let race: Race
    @State private var notes: String = ""
    @State private var askDelete: Bool = false
    @State private var sectorRunner: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                topBar
                if race.isDemo {
                    Text("DEMOSTRACIÓN · carrera real de muestra enlazada a un caballo de demostración solo para las capturas")
                        .font(.caption.weight(.semibold)).foregroundStyle(Avo.warn)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Avo.warn.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Avo.warn, lineWidth: 1))
                }
                RaceHeaderCard(race: race)
                if let us = race.ourRunner {
                    RaceResultCard(race: race, us: us)
                } else {
                    AvoCard { AvoNoData(text: "El caballo no está identificado entre los participantes") }
                }
                RaceRunnersTable(race: race)
                RaceSectorsTable(race: race, runnerName: $sectorRunner)
                RaceChartsSection(race: race)
                if let us = race.ourRunner {
                    RaceTrainingSplitsCard(model: model, race: race, us: us)
                }
                analysis
                notesCard
            }
            .padding(20)
        }
        .background(Avo.bg)
        .onAppear { load() }
        .onChange(of: race.id) { (_: String, _: String) in load() }
        .alert("Eliminar carrera", isPresented: $askDelete) {
            Button("Cancelar", role: .cancel) {}
            Button("Eliminar", role: .destructive) { model.delete(race.id) }
        } message: {
            Text("¿Eliminar «\(race.title)» del \(race.dateText)? Se borra también la copia del PDF guardada en el iPad.")
        }
    }

    private func load() {
        notes = race.notes
        sectorRunner = race.ourRunnerName ?? race.runners.first?.name ?? ""
        model.requestReport(race)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                model.selectedRaceId = nil
            } label: {
                Label("Carreras", systemImage: "chevron.left")
            }
            .buttonStyle(.avoSecondary)
            .accessibilityIdentifier("race.back")
            VStack(alignment: .leading, spacing: 2) {
                Text(race.title).font(.title2.weight(.semibold)).foregroundStyle(Avo.text).lineLimit(1).minimumScaleFactor(0.6)
                Text("\(race.horseName ?? "—") · \(race.ourRunnerName ?? "—")").font(.footnote).foregroundStyle(Avo.textDim).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let p = model.pdfPath(race) {
                ShareLink(item: URL(fileURLWithPath: p)) {
                    Label("PDF", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.avoSecondary)
            }
            Button(role: .destructive) {
                askDelete = true
            } label: {
                Label("Eliminar", systemImage: "trash")
            }
            .buttonStyle(.avoSecondary)
            .foregroundStyle(Avo.bad)
        }
    }

    @ViewBuilder
    private var analysis: some View {
        if let rep = model.reports[race.id], let us = race.ourRunner {
            RaceAnalysisSection(race: race, us: us, report: rep)
        } else if race.ourRunner == nil {
            EmptyView()
        } else {
            AvoCard(title: "Análisis según los entrenamientos") {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Analizando la carrera y los entrenamientos del caballo…").font(.footnote).foregroundStyle(Avo.textDim)
                }
            }
            .onAppear { model.requestReport(race) }
        }
    }

    private var notesCard: some View {
        AvoCard(title: "Notas") {
            TextField("Notas de la carrera (estado de la pista, incidencias, herraje…)", text: $notes, axis: .vertical)
                .lineLimit(2...6)
                .padding(8)
                .background(Avo.surface2, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Avo.line, lineWidth: 1))
            HStack {
                Button("Guardar notas") { model.saveNotes(race.id, notes) }
                    .buttonStyle(.avoSecondary)
                    .disabled(notes == race.notes)
                Spacer()
                Text("Archivo: \(race.sourceFile) · importada \(AvoTime.text(race.importedAt))")
                    .font(.caption2).foregroundStyle(Avo.textDim).lineLimit(1)
            }
        }
    }
}

// MARK: - header and result

private struct RaceHeaderCard: View {
    let race: Race

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            AvoMetric(label: "Hipódromo", value: race.hippodrome.isEmpty ? "—" : race.hippodrome, icon: "mappin.and.ellipse")
            AvoMetric(label: "Carrera", value: race.category.isEmpty ? "—" : race.category, caption: race.raceName)
            AvoMetric(label: "Distancia", value: race.distanceText)
            AvoMetric(label: "Fecha", value: race.dateText, caption: "Europe/Madrid")
            AvoMetric(label: "Redk del 1.º", value: RaceFormat.official(race.winnerRedk), caption: "Reducción kilométrica")
            AvoMetric(label: "Participantes", value: String(race.fieldSize))
        }
    }
}

private struct RaceResultCard: View {
    let race: Race
    let us: RaceRunner

    var body: some View {
        let gap: Double? = race.ourGapToWinnerS
        AvoCard(title: "Resultado de \(race.horseName ?? us.name)", subtitle: "\(us.name) · jockey \(us.jockey.isEmpty ? "—" : us.jockey)") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                AvoMetric(label: "Puesto", value: race.finishText,
                          caption: us.number.map { "N.º \($0)" + (us.draw.map { " · cuerda \($0)" } ?? "") },
                          accent: us.finish == 1 ? Avo.ok : Avo.text)
                AvoMetric(label: "Tiempo oficial", value: RaceFormat.official(us.officialTimeS), caption: RaceFormat.seconds(us.officialTimeS))
                AvoMetric(label: "Al ganador", value: us.finish == 1 ? "Ganador" : RaceFormat.signedSeconds(gap),
                          caption: us.finish == 1 ? nil : RaceFormat.lengths(gap) + " (1 cuerpo ≈ 0,2 s)")
                AvoMetric(label: "Redk", value: RaceFormat.official(us.redk), caption: "Por km")
                AvoMetric(label: "V. máxima", value: RaceFormat.kmh(us.maxSpeedKmh, 2), caption: us.maxSpeedSector.isEmpty ? nil : "Tramo " + us.maxSpeedSector)
                AvoMetric(label: "V. media", value: RaceFormat.kmh(us.meanSpeedKmh))
                AvoMetric(label: "Mejor 200 m", value: RaceFormat.seconds(us.fastest200S), caption: us.fastestSector.isEmpty ? nil : "Tramo " + us.fastestSector)
                AvoMetric(label: "Últimos 600 m", value: RaceFormat.seconds(us.last600S))
                AvoMetric(label: "Recorrido vs 1.º", value: us.finish == 1 ? "—" : RaceFormat.signedMetres(us.distanceVsWinnerM),
                          caption: "«Parcouru vs. 1er»")
            }
        }
    }
}

// MARK: - transcribed tables

private enum RaceCols {
    static let finish: CGFloat = 46, number: CGFloat = 40, draw: CGFloat = 52, name: CGFloat = 170, jockey: CGFloat = 130,
               time: CGFloat = 78, gap: CGFloat = 70, redk: CGFloat = 66, vmax: CGFloat = 150, fast: CGFloat = 170,
               l600: CGFloat = 76, vs: CGFloat = 78, mean: CGFloat = 70
}

private struct RaceRunnersTable: View {
    let race: Race

    var body: some View {
        AvoCard(title: "Carrera completa (transcrita del PDF)", subtitle: "Resaltado: nuestro caballo") {
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        h("Lleg.", RaceCols.finish); h("N.º", RaceCols.number); h("Cuerda", RaceCols.draw); h("Caballo", RaceCols.name)
                        h("Jockey", RaceCols.jockey); h("Tiempo", RaceCols.time); h("Dif.", RaceCols.gap); h("Redk", RaceCols.redk)
                        h("V. máx (tramo)", RaceCols.vmax); h("Mejor 200 m (tramo)", RaceCols.fast); h("Últ. 600 m", RaceCols.l600)
                        h("vs 1.º", RaceCols.vs); h("V. media", RaceCols.mean)
                    }
                    .padding(.vertical, 6).padding(.horizontal, 6)
                    Divider().overlay(Avo.line)
                    ForEach(race.runners) { (r: RaceRunner) in
                        row(r)
                        Divider().overlay(Avo.line)
                    }
                }
            }
        }
    }

    private func row(_ r: RaceRunner) -> some View {
        let ours: Bool = r.name == race.ourRunnerName
        let w: Double? = race.winner?.officialTimeS
        let gap: Double? = (r.officialTimeS != nil && w != nil) ? (r.officialTimeS ?? 0) - (w ?? 0) : nil
        return HStack(spacing: 8) {
            c(RaceFormat.place(r.finish), RaceCols.finish, bold: true)
            c(r.number.map { String($0) } ?? "—", RaceCols.number)
            c(r.draw.map { "(\($0))" } ?? "—", RaceCols.draw)
            c(r.name, RaceCols.name, bold: ours)
            c(r.jockey.isEmpty ? "—" : r.jockey, RaceCols.jockey)
            c(RaceFormat.official(r.officialTimeS), RaceCols.time)
            c(r.finish == 1 ? "—" : RaceFormat.signedSeconds(gap), RaceCols.gap)
            c(RaceFormat.official(r.redk), RaceCols.redk)
            c(RaceFormat.kmh(r.maxSpeedKmh, 2) + (r.maxSpeedSector.isEmpty ? "" : " · " + r.maxSpeedSector), RaceCols.vmax)
            c(RaceFormat.seconds(r.fastest200S) + (r.fastestSector.isEmpty ? "" : " · " + r.fastestSector), RaceCols.fast)
            c(RaceFormat.seconds(r.last600S), RaceCols.l600)
            c(r.finish == 1 ? "—" : RaceFormat.signedMetres(r.distanceVsWinnerM), RaceCols.vs)
            c(RaceFormat.kmh(r.meanSpeedKmh), RaceCols.mean)
        }
        .padding(.vertical, 7).padding(.horizontal, 6)
        .background(ours ? Avo.redSoft : Color.clear, in: RoundedRectangle(cornerRadius: 6))
    }

    private func h(_ t: String, _ w: CGFloat) -> some View {
        Text(t.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(Avo.textDim).lineLimit(1).frame(width: w, alignment: .leading)
    }

    private func c(_ t: String, _ w: CGFloat, bold: Bool = false) -> some View {
        Text(t).font(bold ? .footnote.weight(.semibold).monospacedDigit() : .footnote.monospacedDigit()).foregroundStyle(Avo.text)
            .lineLimit(1).minimumScaleFactor(0.8).frame(width: w, alignment: .leading)
    }
}

private struct RaceSectorsTable: View {
    let race: Race
    @Binding var runnerName: String

    var body: some View {
        let picked: RaceRunner? = race.runners.first(where: { (x: RaceRunner) -> Bool in x.name == runnerName })
        let r: RaceRunner? = picked ?? race.ourRunner ?? race.runners.first
        AvoCard(title: "Tramos de \(widthText)", subtitle: "Tiempos, velocidad media y foulées del PDF; zancada = longitud del tramo / foulées; posición = orden de los tiempos acumulados") {
            Picker("Caballo", selection: $runnerName) {
                ForEach(race.runners) { (x: RaceRunner) in
                    Text("\(RaceFormat.place(x.finish)) \(x.name)").tag(x.name)
                }
            }
            .pickerStyle(.menu)
            .tint(Avo.text)
            if let r = r {
                ShellTable(columns: [ShellTable.Column(title: "Tramo", width: 120), ShellTable.Column(title: "Acumulado", width: 90),
                                     ShellTable.Column(title: "Tiempo tramo", width: 100), ShellTable.Column(title: "V. media", width: 90),
                                     ShellTable.Column(title: "Foulées", width: 70), ShellTable.Column(title: "Zancada", width: 80),
                                     ShellTable.Column(title: "Posición", width: 70)],
                           rows: r.sectors.map { (s: RaceSector) -> [String] in
                               [s.label + (s.fromM == 0 && abs(s.lengthM - 200) > 0.5 ? " (\(Int(s.lengthM)) m)" : ""),
                                RaceFormat.official(s.cumulativeS), RaceFormat.seconds(s.sectorS), RaceFormat.kmh(s.meanSpeedKmh),
                                s.strides.map { String($0) } ?? "—", RaceFormat.metres(s.strideLengthM), RaceFormat.place(s.position)]
                           })
            } else {
                AvoNoData()
            }
        }
    }

    private var widthText: String {
        guard let s = race.runners.first?.sectors.last else { return "200 m" }
        return "\(Int(s.lengthM)) m"
    }
}

// MARK: - charts

struct RaceChartPoint: Identifiable {
    var series: String
    var order: Int
    var sector: String
    var value: Double
    var id: String { series + "|" + String(order) }
}

private struct RaceChartsSection: View {
    let race: Race

    var body: some View {
        let us: RaceRunner? = race.ourRunner
        let win: RaceRunner? = race.winner
        let ourName: String = us?.name ?? "Nuestro caballo"
        let showWinner: Bool = win != nil && win?.name != us?.name
        let winName: String = "Ganador (\(win?.name ?? "—"))"
        let medName: String = "Mediana del campo"
        VStack(alignment: .leading, spacing: 14) {
            Text("GRÁFICAS POR TRAMO").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(Avo.silver)
            if let u = us {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        speedCard(u, win, showWinner, ourName, winName, medName)
                        positionCard(u, win, showWinner, ourName, winName)
                    }
                    .frame(minWidth: 860)
                    VStack(alignment: .leading, spacing: 14) {
                        speedCard(u, win, showWinner, ourName, winName, medName)
                        positionCard(u, win, showWinner, ourName, winName)
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        strideCard(u, win, showWinner, ourName, winName)
                        gapCard(u)
                    }
                    .frame(minWidth: 860)
                    VStack(alignment: .leading, spacing: 14) {
                        strideCard(u, win, showWinner, ourName, winName)
                        gapCard(u)
                    }
                }
            } else {
                AvoNoData(text: "Sin caballo identificado: no hay gráficas")
            }
        }
    }

    private func series(_ r: RaceRunner, _ name: String, _ f: (RaceSector) -> Double?) -> [RaceChartPoint] {
        var out: [RaceChartPoint] = []
        for (k, s) in r.sectors.enumerated() {
            if let v = f(s), v.isFinite { out.append(RaceChartPoint(series: name, order: k, sector: s.shortLabel, value: v)) }
        }
        return out
    }

    private func medianSpeeds(_ name: String) -> [RaceChartPoint] {
        guard let first = race.runners.first else { return [] }
        var out: [RaceChartPoint] = []
        for k in 0..<first.sectors.count {
            let others: [Double] = race.runners.filter { $0.name != race.ourRunnerName }.compactMap { k < $0.sectors.count ? $0.sectors[k].speedKmh : nil }
            if let m = RaceAnalysis.median(others) {
                out.append(RaceChartPoint(series: name, order: k, sector: first.sectors[k].shortLabel, value: m))
            }
        }
        return out
    }

    private func speedCard(_ u: RaceRunner, _ w: RaceRunner?, _ showW: Bool, _ ourName: String, _ winName: String, _ medName: String) -> some View {
        var pts: [RaceChartPoint] = series(u, ourName) { $0.speedKmh }
        var names: [String] = [ourName]
        var colors: [Color] = [Avo.red]
        if showW, let w = w {
            pts += series(w, winName) { $0.speedKmh }
            names.append(winName)
            colors.append(Avo.blue)
        }
        pts += medianSpeeds(medName)
        names.append(medName)
        colors.append(Avo.silver)
        return AvoCard(title: "Velocidad por tramo", subtitle: "km/h · nuestro caballo, ganador y mediana del campo") {
            RaceLineChart(points: pts, names: names, colors: colors, reversed: false, unit: "km/h")
        }
    }

    private func positionCard(_ u: RaceRunner, _ w: RaceRunner?, _ showW: Bool, _ ourName: String, _ winName: String) -> some View {
        var pts: [RaceChartPoint] = series(u, ourName) { $0.position.map { Double($0) } }
        var names: [String] = [ourName]
        var colors: [Color] = [Avo.red]
        if showW, let w = w {
            pts += series(w, winName) { $0.position.map { Double($0) } }
            names.append(winName)
            colors.append(Avo.blue)
        }
        return AvoCard(title: "Posición en carrera", subtitle: "Al final de cada tramo (1 = en cabeza)") {
            RaceLineChart(points: pts, names: names, colors: colors, reversed: true, unit: ".º")
        }
    }

    private func strideCard(_ u: RaceRunner, _ w: RaceRunner?, _ showW: Bool, _ ourName: String, _ winName: String) -> some View {
        var counts: [RaceChartPoint] = series(u, ourName) { $0.strides.map { Double($0) } }
        var lengths: [RaceChartPoint] = series(u, ourName) { $0.strideLengthM }
        var names: [String] = [ourName]
        var colors: [Color] = [Avo.red]
        if showW, let w = w {
            counts += series(w, winName) { $0.strides.map { Double($0) } }
            lengths += series(w, winName) { $0.strideLengthM }
            names.append(winName)
            colors.append(Avo.blue)
        }
        return AvoCard(title: "Foulées y zancada", subtitle: "Número de foulées (barras) y longitud de zancada en m (líneas)") {
            Chart(counts) { (p: RaceChartPoint) in
                BarMark(x: .value("Tramo", p.sector), y: .value("Foulées", p.value))
                    .foregroundStyle(by: .value("Caballo", p.series))
                    .position(by: .value("Caballo", p.series))
            }
            .chartForegroundStyleScale(domain: names, range: colors)
            .chartLegend(position: .bottom, alignment: .leading)
            .chartYScale(domain: .automatic(includesZero: true))
            .frame(height: 150)
            RaceLineChart(points: lengths, names: names, colors: colors, reversed: false, unit: "m")
            Text("La zancada del primer tramo incluye la salida (tramo de \(Int(u.sectors.first?.lengthM ?? 0)) m): compárala con cautela.")
                .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func gapCard(_ u: RaceRunner) -> some View {
        var pts: [RaceChartPoint] = []
        for (k, s) in u.sectors.enumerated() {
            let lead: Double? = race.runners.compactMap { k < $0.sectors.count ? $0.sectors[k].cumulativeS : nil }.min()
            if let l = lead { pts.append(RaceChartPoint(series: u.name, order: k, sector: s.shortLabel, value: s.cumulativeS - l)) }
        }
        return AvoCard(title: "Distancia al primero", subtitle: "Segundos detrás del caballo en cabeza al final de cada tramo (1 cuerpo ≈ 0,2 s)") {
            Chart(pts) { (p: RaceChartPoint) in
                BarMark(x: .value("Tramo", p.sector), y: .value("s", p.value))
                    .foregroundStyle(Avo.red.gradient)
                    .annotation(position: .top) {
                        Text(AvoFormat.f(p.value, 2)).font(.caption2).foregroundStyle(Avo.textDim)
                    }
            }
            .chartLegend(.hidden)
            .frame(height: 190)
        }
    }
}

/// Line chart over the sectors (categorical x), one line per series, colours fixed by series name.
private struct RaceLineChart: View {
    let points: [RaceChartPoint]
    let names: [String]
    let colors: [Color]
    let reversed: Bool
    let unit: String

    var body: some View {
        if points.isEmpty {
            AvoNoData()
        } else {
            Chart(points) { (p: RaceChartPoint) in
                LineMark(x: .value("Tramo", p.sector), y: .value(unit, p.value))
                    .foregroundStyle(by: .value("Serie", p.series))
                    .interpolationMethod(.linear)
                PointMark(x: .value("Tramo", p.sector), y: .value(unit, p.value))
                    .foregroundStyle(by: .value("Serie", p.series))
                    .symbolSize(28)
            }
            .chartForegroundStyleScale(domain: names, range: colors)
            .chartYScale(domain: .automatic(includesZero: false, reversed: reversed))
            .chartLegend(position: .bottom, alignment: .leading)
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(Avo.line)
                    AxisValueLabel {
                        if let s = value.as(String.self) { Text(s).font(.caption2).foregroundStyle(Avo.textDim) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Avo.line)
                    AxisValueLabel {
                        if let d = value.as(Double.self) {
                            Text(AvoFormat.f(d, unit == ".º" ? 0 : 1) + (unit == ".º" ? ".º" : "")).font(.caption2).foregroundStyle(Avo.textDim)
                        }
                    }
                }
            }
            .frame(height: 210)
        }
    }
}

// MARK: - analysis

private struct RaceAnalysisSection: View {
    let race: Race
    let us: RaceRunner
    let report: RaceReport

    var body: some View {
        let rep: RaceReport = report
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(Avo.red).frame(width: 4, height: 28)
                Text("Análisis según los entrenamientos").font(.title3.weight(.semibold)).foregroundStyle(Avo.text)
                Spacer(minLength: 8)
                AvoPill(text: "Confianza \(rep.confidence.rawValue)", color: confidenceColor(rep.confidence))
            }
            // verdict
            AvoCard(title: "Conclusión") {
                Text(rep.verdict).font(.headline).foregroundStyle(Avo.text).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("race.verdict")
                if !rep.optimizedText.isEmpty {
                    Label(rep.optimizedText, systemImage: rep.optimizedPositions > 0 ? "arrow.up.circle.fill" : "checkmark.circle")
                        .font(.callout).foregroundStyle(rep.optimizedPositions > 0 ? Avo.ok : Avo.cyan)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Confianza \(rep.confidence.rawValue): \(rep.confidenceReason).")
                    .font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    raceCard(rep)
                    trainingCard(rep)
                }
                .frame(minWidth: 860)
                VStack(alignment: .leading, spacing: 14) {
                    raceCard(rep)
                    trainingCard(rep)
                }
            }
            RaceFormCard(report: rep, horseName: race.horseName ?? "—", raceDate: race.dateText)
            estimateCard(rep)
            AvoCard(title: "Observaciones") {
                if rep.observations.isEmpty {
                    AvoNoData()
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(rep.observations.enumerated()), id: \.offset) { (item: (offset: Int, element: String)) in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Circle().fill(Avo.red).frame(width: 6, height: 6)
                                Text(item.element).font(.footnote).foregroundStyle(Avo.text).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            AvoCard(title: "Método") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(rep.method.enumerated()), id: \.offset) { (item: (offset: Int, element: String)) in
                        Text("\(item.offset + 1). \(item.element)").font(.caption2).foregroundStyle(Avo.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func confidenceColor(_ c: RaceConfidence) -> Color {
        switch c {
        case .high: return Avo.ok
        case .medium: return Avo.warn
        case .low: return Avo.bad
        }
    }

    private func raceCard(_ rep: RaceReport) -> some View {
        AvoCard(title: "Lo que dice la carrera", subtitle: "Solo datos del PDF") {
            ShellKeyValue(key: "Caída en el final (conserva)", value: "\(RaceFormat.percent(rep.ourFade)) · \(RaceFormat.kmh(rep.ourBestSpeedKmh)) → \(RaceFormat.kmh(rep.ourLastSpeedKmh))")
            ShellKeyValue(key: "Mediana del campo (conserva)", value: RaceFormat.percent(rep.fieldMedianFade))
            ShellKeyValue(key: "Perdido en el final vs mediana", value: RaceFormat.seconds(rep.finalLossFieldS))
            ShellKeyValue(key: "Perdido por terreno de más", value: groundText(rep))
            ShellKeyValue(key: "Salida vs mediana del campo", value: RaceFormat.signedSeconds(rep.startLossS))
            ShellKeyValue(key: "Últimos 600 m vs su mejor tramo", value: RaceFormat.percent(rep.raceSustain))
        }
    }

    private func groundText(_ rep: RaceReport) -> String {
        guard let d = us.distanceVsWinnerM else { return us.finish == 1 ? "Ganador" : "Sin dato" }
        if d <= 0 { return "0 s (\(RaceFormat.signedMetres(d)))" }
        return "\(RaceFormat.seconds(rep.groundLossS)) (\(RaceFormat.signedMetres(d)))"
    }

    private func trainingCard(_ rep: RaceReport) -> some View {
        AvoCard(title: "Lo que dicen sus entrenamientos", subtitle: "Entrenamientos de \(race.horseName ?? "—") en este iPad anteriores a la carrera") {
            if rep.trainingSessions == 0 {
                Text("Sin entrenamientos de \(race.horseName ?? "este caballo") anteriores al \(race.dateText) en este iPad: el análisis usa solo la carrera (la mediana del campo como referencia).")
                    .font(.footnote).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            } else {
                ShellKeyValue(key: "Entrenamientos", value: "\(rep.trainingSessions) · \(AvoTime.text(rep.trainingFrom, "dd/MM/yyyy")) – \(AvoTime.text(rep.trainingTo, "dd/MM/yyyy"))")
                ShellKeyValue(key: "Trabajos rápidos (> 40 km/h, ≥ 200 m)", value: String(rep.fastWorks))
                ShellKeyValue(key: "Mejor 200 / 400 / 600 m sostenido",
                              value: "\(RaceFormat.kmh(rep.best200Kmh)) / \(RaceFormat.kmh(rep.best400Kmh)) / \(RaceFormat.kmh(rep.best600Kmh))")
                ShellKeyValue(key: "600 m sostenido / mejor 200 m", value: RaceFormat.percent(rep.trainingSustain))
                ShellKeyValue(key: "Caída en sus trabajos (conserva, mediana)",
                              value: rep.worksWithFade > 0 ? "\(RaceFormat.percent(rep.trainingFade)) en \(rep.worksWithFade) trabajo(s) ≥ 400 m" : "Sin trabajos ≥ 400 m")
                if !rep.trendText.isEmpty {
                    Text(rep.trendText).font(.caption).foregroundStyle(Avo.silver).fixedSize(horizontal: false, vertical: true)
                }
                if rep.trainingDemo {
                    AvoPill(text: "INCLUYE DEMOSTRACIÓN · DATOS SINTÉTICOS", color: Avo.warn)
                }
                Text("Los entrenamientos son más lentos que la carrera: se comparan proporciones, no velocidades absolutas.")
                    .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func estimateCard(_ rep: RaceReport) -> some View {
        AvoCard(title: "Estimación", subtitle: rep.referenceIsTraining ? "Final con la caída de sus entrenamientos y sin el terreno de más"
                                                                      : "Final con la caída de la mediana del campo y sin el terreno de más") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                AvoMetric(label: "Tiempo oficial", value: RaceFormat.official(us.officialTimeS))
                AvoMetric(label: "Tiempo corregido", value: RaceFormat.official(rep.correctedTimeS),
                          caption: rep.correctedTimeS.flatMap { c in us.officialTimeS.map { "−" + AvoFormat.f($0 - c, 2) + " s" } })
                AvoMetric(label: "Puesto real", value: race.finishText)
                AvoMetric(label: "Puesto estimado", value: rep.predictedPlace.map { "\($0).º" } ?? "—",
                          caption: rangeText(rep),
                          accent: rep.gainedPositions > 0 ? Avo.warn : Avo.text)
                AvoMetric(label: "Perdido en el final", value: RaceFormat.seconds(rep.referenceIsTraining ? rep.finalLossTrainingS : rep.finalLossFieldS),
                          caption: rep.referenceIsTraining ? "vs sus entrenamientos" : "vs mediana del campo")
            }
        }
    }

    private func rangeText(_ rep: RaceReport) -> String? {
        guard let a = rep.placeLow, let b = rep.placeHigh else { return nil }
        return a == b ? "Margen ±: sin cambio" : "Margen ±: entre \(a).º y \(b).º"
    }
}

/// «Forma antes de la carrera»: state of the horse at the race date from the history of its trainings (AVO Training
/// Analytics, fecha_referencia = day of the race). Orientative, never a veterinary diagnosis.
private struct RaceFormCard: View {
    let report: RaceReport
    let horseName: String
    let raceDate: String

    var body: some View {
        AvoCard(title: "Forma antes de la carrera",
                subtitle: "Historia de entrenamientos de \(horseName) hasta el \(raceDate) · orientativo, no es un diagnóstico veterinario") {
            if let f = report.form {
                let color: Color = HorseHistoryModel.levelColor(f.level)
                HStack(spacing: 10) {
                    AvoPill(text: f.level, color: color)
                    Text("\(f.sessionsUsed) sesiones · referencia \(f.reference)").font(.caption).foregroundStyle(Avo.textDim)
                    if f.demo { AvoPill(text: "DEMOSTRACIÓN", color: Avo.warn) }
                }
                ShellKeyValue(key: "ACWR (aguda / crónica)",
                              value: (f.acwr.map { AvoFormat.f($0, 2) } ?? "— (menos de 28 días)") + " · banda \(AvoFormat.f(f.acwrLow, 1))–\(AvoFormat.f(f.acwrHigh, 1))")
                ShellKeyValue(key: "Carga aguda 7 d / crónica semanal",
                              value: "\(f.acute.map { AvoFormat.f($0, 0) } ?? "—") / \(f.chronicWeekly.map { AvoFormat.f($0, 0) } ?? "—")")
                ShellKeyValue(key: "Monotonía", value: f.monotony.map { AvoFormat.f($0, 2) } ?? "—")
                ShellKeyValue(key: "Días desde el último entrenamiento", value: f.daysSinceLast.map { String($0) } ?? "—")
                if !f.reasons.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(f.reasons.enumerated()), id: \.offset) { (item: (offset: Int, element: String)) in
                            Text("· " + item.element).font(.caption).foregroundStyle(Avo.text).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if !f.trends.isEmpty {
                    Text("TENDENCIAS DE 8 SEMANAS").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim).padding(.top, 4)
                    ForEach(f.trends) { (t: TrainingTrend) in
                        HStack(spacing: 6) {
                            Image(systemName: t.arrow).font(.caption.weight(.bold)).foregroundStyle(Avo.cyan).frame(width: 16)
                            Text(TrainingAnalytics.fullLabel(t.metrica)).font(.footnote).foregroundStyle(Avo.text)
                            Spacer(minLength: 6)
                            Text("\(t.direccion) · \(TrainingAnalytics.formatSlope(TrainingAnalytics.split(t.metrica).key, t.pendienteSemana))")
                                .font(.caption).foregroundStyle(Avo.textDim)
                        }
                    }
                }
            } else if !report.formState.isEmpty {
                Text(report.formState).font(.footnote).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Analizando la historia de entrenamientos…").font(.footnote).foregroundStyle(Avo.textDim)
                }
            }
        }
    }
}
