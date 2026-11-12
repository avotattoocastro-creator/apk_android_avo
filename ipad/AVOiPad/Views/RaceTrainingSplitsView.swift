import SwiftUI
import Charts

/// Bar / line point of «Entrenamiento vs carrera, tramo a tramo».
private struct RaceSplitPoint: Identifiable {
    var id: String
    var label: String
    var series: String
    var value: Double
}

/// «Entrenamiento vs carrera, tramo a tramo» (race card): one training effort or course pass of the horse with splits
/// (AVO Track Work), by default the fastest by mean speed in the 60 days before the race, side by side with the 200 m
/// sectors of our horse in the race, aligned from the finish (Core/RaceAnalysis.swift, RaceTrainingSplits).
struct RaceTrainingSplitsCard: View {
    @Environment(AppModel.self) private var app
    @Bindable var model: RacesModel
    let race: Race
    let us: RaceRunner
    @State private var chosenId: String? = nil

    static let trainingSeries: String = "Entrenamiento (playa)"
    static let raceSeries: String = "Carrera (pista)"

    var body: some View {
        AvoCard(title: "Entrenamiento vs carrera, tramo a tramo",
                subtitle: "Un trabajo o pasada de \(race.horseName ?? "—") con parciales, frente a los tramos de 200 m de \(us.name) en esta carrera") {
            content
            Text("Los parciales del entrenamiento son en la playa (arena, p. ej. Playa del Regatón) y los de la carrera en la pista: superficie, peso, ritmo y rivales cambian. Compara proporciones (qué parte de la velocidad de carrera alcanza y cómo cae al final), no tiempos absolutos. Los tramos se alinean desde la meta: el último parcial completo del trabajo con el tramo 200–ARR.")
                .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { model.analyseSplitTrainings(race) }
        .accessibilityIdentifier("race.trainingSplits")
    }

    @ViewBuilder
    private var content: some View {
        if race.date == nil {
            AvoNoData(text: "Carrera sin fecha")
        } else if race.horseRecordCode == nil {
            AvoNoData(text: "Carrera sin caballo de la Cuadra")
        } else {
            let cands: [RaceTrainingCandidate] = model.splitCandidates(for: race)
            let pending: Int = model.splitPending(for: race)
            if pending > 0 {
                HStack(spacing: 8) {
                    if model.splitsAnalysing.contains(race.id) { ProgressView().controlSize(.small) }
                    Text("\(pending) entrenamiento(s) de los \(RaceTrainingSplits.windowDays) días anteriores todavía sin analizar con el motor.")
                        .font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    Button("Analizar") { model.analyseSplitTrainings(race) }
                        .buttonStyle(.avoSecondary)
                        .disabled(model.splitsAnalysing.contains(race.id))
                }
            }
            if let chosen = cands.first(where: { $0.id == chosenId }) ?? RaceTrainingSplits.defaultCandidate(cands) {
                picker(cands, chosen)
                comparison(chosen, RaceTrainingSplits.compare(chosen, us))
            } else {
                AvoNoData(text: "Sin trabajos con parciales completos en los \(RaceTrainingSplits.windowDays) días anteriores a la carrera")
            }
        }
    }

    private func picker(_ cands: [RaceTrainingCandidate], _ chosen: RaceTrainingCandidate) -> some View {
        let isDefault: Bool = chosen.id == RaceTrainingSplits.defaultCandidate(cands)?.id
        return HStack(spacing: 10) {
            Text("ENTRENAMIENTO").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim)
            Menu {
                ForEach(cands) { (c: RaceTrainingCandidate) in
                    Button {
                        chosenId = c.id
                    } label: {
                        if c.id == chosen.id {
                            Label(c.label, systemImage: "checkmark")
                        } else {
                            Text(c.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(chosen.label).foregroundStyle(Avo.text).lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption).foregroundStyle(Avo.textDim)
                }
                .font(.callout)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Avo.surface2, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Avo.line, lineWidth: 1))
            }
            .accessibilityIdentifier("race.trainingSplits.pick")
            if isDefault {
                Text("Por defecto: el más rápido por velocidad media").font(.caption2).foregroundStyle(Avo.textDim).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let s = app.sessions.first(where: { $0.id == chosen.sessionId }) {
                Button {
                    app.select(s)
                    app.trackWork.select(chosen.effort)
                    app.page = .trackWork
                } label: {
                    Label("Abrir", systemImage: "stopwatch")
                }
                .buttonStyle(.avoSecondary)
            }
        }
    }

    @ViewBuilder
    private func comparison(_ c: RaceTrainingCandidate, _ cmp: RaceSectorComparison) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
            AvoMetric(label: "% de la velocidad de carrera", value: RaceFormat.percent(cmp.meanPctOfRace),
                      caption: "Media de los tramos comparados")
            AvoMetric(label: "Caída en entrenamiento", value: RaceFormat.percent(cmp.trainingFade),
                      caption: "Último / mejor parcial: \(RaceFormat.kmh(cmp.trainingLastKmh)) / \(RaceFormat.kmh(cmp.trainingBestKmh))")
            AvoMetric(label: "Caída en carrera", value: RaceFormat.percent(cmp.raceFade),
                      caption: "Último / mejor tramo: \(RaceFormat.kmh(cmp.raceLastKmh)) / \(RaceFormat.kmh(cmp.raceBestKmh))")
            AvoMetric(label: "Parciales del entreno", value: String(c.fullSplits),
                      caption: cmp.trainingIsFurlong ? "Cada furlong (201 m)" : "Cada 200 m")
        }
        if cmp.rows.isEmpty {
            AvoNoData()
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    speedChart(cmp).frame(maxWidth: .infinity)
                    fadeChart(cmp).frame(maxWidth: .infinity)
                }
                .frame(minWidth: 860)
                VStack(alignment: .leading, spacing: 14) {
                    speedChart(cmp)
                    fadeChart(cmp)
                }
            }
            table(cmp)
        }
        if cmp.trainingPartialEndSkipped {
            Text("El último parcial del entrenamiento es más corto que \(cmp.trainingIsFurlong ? "un furlong" : "200 m") y no se compara.")
                .font(.caption2).foregroundStyle(Avo.textDim)
        }
        if cmp.trainingIsFurlong {
            Text("Este entrenamiento usa furlongs (201,168 m): la diferencia con 200 m es menor del 1 %.")
                .font(.caption2).foregroundStyle(Avo.textDim)
        }
    }

    private func points(_ cmp: RaceSectorComparison, normalized: Bool) -> [RaceSplitPoint] {
        var out: [RaceSplitPoint] = []
        for r in cmp.rows {
            if let v = r.trainingKmh {
                let y: Double? = normalized ? cmp.trainingBestKmh.map { v / $0 * 100 } : v
                if let yy = y, yy.isFinite { out.append(RaceSplitPoint(id: "t\(r.id)", label: r.label, series: RaceTrainingSplitsCard.trainingSeries, value: yy)) }
            }
            if let v = r.raceKmh {
                let y: Double? = normalized ? cmp.raceBestKmh.map { v / $0 * 100 } : v
                if let yy = y, yy.isFinite { out.append(RaceSplitPoint(id: "r\(r.id)", label: r.label, series: RaceTrainingSplitsCard.raceSeries, value: yy)) }
            }
        }
        return out
    }

    private func speedChart(_ cmp: RaceSectorComparison) -> some View {
        let pts: [RaceSplitPoint] = points(cmp, normalized: false)
        let labels: [String] = cmp.rows.map { $0.label }
        return VStack(alignment: .leading, spacing: 4) {
            Text("VELOCIDAD POR TRAMO (km/h)").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim)
            Chart(pts) { (p: RaceSplitPoint) in
                BarMark(x: .value("Tramo", p.label), y: .value("km/h", p.value))
                    .foregroundStyle(by: .value("Serie", p.series))
                    .position(by: .value("Serie", p.series))
                    .cornerRadius(2)
            }
            .chartForegroundStyleScale(domain: [RaceTrainingSplitsCard.trainingSeries, RaceTrainingSplitsCard.raceSeries],
                                       range: [Avo.cyan, Avo.red])
            .chartXScale(domain: labels)
            .chartLegend(position: .bottom, alignment: .leading)
            .chartXAxis {
                AxisMarks { (v: AxisValue) in
                    AxisValueLabel { if let s = v.as(String.self) { Text(s).font(.caption2).foregroundStyle(Avo.textDim) } }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { (v: AxisValue) in
                    AxisGridLine().foregroundStyle(Avo.line)
                    AxisValueLabel { if let d = v.as(Double.self) { Text(AvoFormat.f(d, 0)).font(.caption2).foregroundStyle(Avo.textDim) } }
                }
            }
            .frame(height: 220)
        }
    }

    private func fadeChart(_ cmp: RaceSectorComparison) -> some View {
        let pts: [RaceSplitPoint] = points(cmp, normalized: true)
        let labels: [String] = cmp.rows.map { $0.label }
        return VStack(alignment: .leading, spacing: 4) {
            Text("PERFIL DE CAÍDA (% DE SU MEJOR TRAMO)").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim)
            Chart {
                RuleMark(y: .value("Mejor", 100.0)).foregroundStyle(Avo.textDim).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                ForEach(pts) { (p: RaceSplitPoint) in
                    LineMark(x: .value("Tramo", p.label), y: .value("%", p.value), series: .value("Serie", p.series))
                        .foregroundStyle(by: .value("Serie", p.series))
                    PointMark(x: .value("Tramo", p.label), y: .value("%", p.value))
                        .foregroundStyle(by: .value("Serie", p.series))
                        .symbolSize(30)
                }
            }
            .chartForegroundStyleScale(domain: [RaceTrainingSplitsCard.trainingSeries, RaceTrainingSplitsCard.raceSeries],
                                       range: [Avo.cyan, Avo.red])
            .chartXScale(domain: labels)
            .chartYScale(domain: .automatic(includesZero: false))
            .chartLegend(position: .bottom, alignment: .leading)
            .chartXAxis {
                AxisMarks { (v: AxisValue) in
                    AxisValueLabel { if let s = v.as(String.self) { Text(s).font(.caption2).foregroundStyle(Avo.textDim) } }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { (v: AxisValue) in
                    AxisGridLine().foregroundStyle(Avo.line)
                    AxisValueLabel { if let d = v.as(Double.self) { Text(AvoFormat.f(d, 0) + " %").font(.caption2).foregroundStyle(Avo.textDim) } }
                }
            }
            .frame(height: 220)
        }
    }

    private func table(_ cmp: RaceSectorComparison) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    h("Tramo", 110); h("Entreno", 80); h("Entreno km/h", 100); h("Carrera", 80); h("Carrera km/h", 100); h("% carrera", 80)
                }
                .padding(.vertical, 5)
                Divider().overlay(Avo.line)
                ForEach(cmp.rows) { (r: RaceSectorComparisonRow) in
                    HStack(spacing: 8) {
                        c(r.label, 110)
                        c(RaceFormat.seconds(r.trainingS), 80)
                        c(RaceFormat.kmh(r.trainingKmh), 100)
                        c(RaceFormat.seconds(r.raceS), 80)
                        c(RaceFormat.kmh(r.raceKmh), 100)
                        c(RaceFormat.percent(r.pctOfRace), 80)
                    }
                    .font(.footnote.monospacedDigit()).foregroundStyle(Avo.text)
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private func h(_ t: String, _ w: CGFloat) -> some View {
        Text(t.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(Avo.textDim).frame(width: w, alignment: .leading)
    }

    private func c(_ t: String, _ w: CGFloat) -> some View {
        Text(t).lineLimit(1).frame(width: w, alignment: .leading)
    }
}
