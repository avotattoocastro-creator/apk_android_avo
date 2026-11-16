import SwiftUI
import Charts

/// «Análisis visual» of a race (trainer's sketch 16/11/2026: full-screen window for a deep visual analysis of the race,
/// choosing which horses of the race to show and comparing them with our horse, its trainings and its other races).
/// Everything comes from the tracking PDF (sectors of every runner), the training efforts with splits (AVO Track Work)
/// and the other races of the same horse; nothing is invented: a series without a value at a sector simply has no point.
struct RaceDeepAnalysisView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let race: Race

    @State private var metric: DeepMetric = .speed
    @State private var shownRunners: Set<String> = []
    @State private var shownTrainings: Set<String> = []
    @State private var shownRaces: Set<String> = []
    @State private var selectedSector: String? = nil
    @State private var ready: Bool = false

    private var model: RacesModel { app.races }
    private var us: RaceRunner? { race.ourRunner }
    private var labels: [String] {
        let base: RaceRunner? = us ?? race.runners.max { $0.sectors.count < $1.sectors.count }
        return base?.sectors.map { $0.shortLabel } ?? []
    }
    private var candidates: [RaceTrainingCandidate] { model.splitCandidates(for: race) }
    private var otherRaces: [Race] {
        guard let code = race.horseRecordCode else { return [] }
        return model.racesOf(horse: code).filter { $0.id != race.id && $0.ourRunner != nil }
    }

    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: 0) {
                selector
                    .frame(width: 320)
                    .background(Avo.surface)
                Divider().overlay(Avo.line)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        metricBar
                        mainChart
                        sectorDetail
                        summaryTable
                        Text(metric.note)
                            .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                }
                .background(Avo.bg)
            }
            .navigationTitle("Análisis visual · \(race.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { dismiss() }.accessibilityIdentifier("deep.close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(race.hippodrome) · \(race.dateText) · \(race.distanceText)")
                        .font(.footnote).foregroundStyle(Avo.textDim)
                }
            }
        }
        .onAppear(perform: setup)
    }

    private func setup() {
        guard !ready else { return }
        ready = true
        if let u = us { shownRunners.insert(u.name) }
        if let w = race.winner { shownRunners.insert(w.name) }
        if shownRunners.isEmpty, let f = race.runners.first { shownRunners.insert(f.name) }
        let chosen: RaceTrainingCandidate? = candidates.first { $0.id == model.splitChoice[race.id] } ?? RaceTrainingSplits.defaultCandidate(candidates)
        if let c = chosen { shownTrainings.insert(c.id) }
        model.analyseSplitTrainings(race)
    }

    // ------------------------------------------------------------------ series
    private var series: [DeepSeries] {
        var out: [DeepSeries] = []
        let sorted: [RaceRunner] = race.runners.sorted { ($0.finish ?? 99) < ($1.finish ?? 99) }
        for r in sorted where shownRunners.contains(r.name) {
            out.append(runnerSeries(r))
        }
        for c in candidates where shownTrainings.contains(c.id) {
            out.append(trainingSeries(c))
        }
        for o in otherRaces where shownRaces.contains(o.id) {
            out.append(otherRaceSeries(o))
        }
        return out
    }

    private func color(of r: RaceRunner) -> Color {
        if r.name == us?.name { return Avo.red }
        if r.name == race.winner?.name { return Avo.blue }
        let idx: Int = race.runners.firstIndex { $0.name == r.name } ?? 0
        return DeepPalette.runner(idx)
    }

    private func runnerSeries(_ r: RaceRunner) -> DeepSeries {
        var v: [DeepMetric: [String: Double]] = [:]
        let best: Double = r.sectors.compactMap { $0.speedKmh }.max() ?? 0
        for (k, s) in r.sectors.enumerated() {
            let l: String = s.shortLabel
            if let x = s.speedKmh { v[.speed, default: [:]][l] = x; if best > 0 { v[.pctBest, default: [:]][l] = x / best * 100 } }
            if s.sectorS > 0 { v[.sectorTime, default: [:]][l] = s.sectorS }
            if let p = s.position { v[.position, default: [:]][l] = Double(p) }
            if let x = s.strideLengthM { v[.stride, default: [:]][l] = x }
            if let n = s.strides { v[.strides, default: [:]][l] = Double(n) }
            if let lead = race.runners.compactMap({ k < $0.sectors.count ? $0.sectors[k].cumulativeS : nil }).min() {
                v[.gapLeader, default: [:]][l] = s.cumulativeS - lead
            }
            if let u = us, k < u.sectors.count {
                v[.gapOurs, default: [:]][l] = s.cumulativeS - u.sectors[k].cumulativeS
            }
        }
        let isOurs: Bool = r.name == us?.name
        let place: String = RaceFormat.place(r.finish)
        return DeepSeries(id: "r:" + r.name, name: "\(place) \(r.name)", short: r.name, color: color(of: r), kind: .runner,
                          emphasis: isOurs, values: v)
    }

    private func trainingSeries(_ c: RaceTrainingCandidate) -> DeepSeries {
        var v: [DeepMetric: [String: Double]] = [:]
        if let u = us {
            let cmp: RaceSectorComparison = RaceTrainingSplits.compare(c, u)
            let best: Double = cmp.trainingBestKmh ?? 0
            for r in cmp.rows {
                if let x = r.trainingKmh { v[.speed, default: [:]][r.label] = x; if best > 0 { v[.pctBest, default: [:]][r.label] = x / best * 100 } }
                if let t = r.trainingS { v[.sectorTime, default: [:]][r.label] = t }
            }
        }
        let idx: Int = candidates.firstIndex { $0.id == c.id } ?? 0
        return DeepSeries(id: "t:" + c.id, name: "Entreno " + c.label, short: "Entreno " + (c.date.map { AvoTime.text($0, "dd/MM") } ?? ""),
                          color: DeepPalette.training(idx), kind: .training, emphasis: false, values: v)
    }

    /// Another race of the same horse, aligned by the distance to the finish (400–200 with 400–200, …).
    private func otherRaceSeries(_ o: Race) -> DeepSeries {
        var v: [DeepMetric: [String: Double]] = [:]
        var byRemaining: [Int: String] = [:]
        if let base = us ?? race.runners.first {
            for s in base.sectors { byRemaining[Int(s.remainingAtEnd(race.distanceM).rounded())] = s.shortLabel }
        }
        if let r = o.ourRunner {
            let best: Double = r.sectors.compactMap { $0.speedKmh }.max() ?? 0
            for s in r.sectors {
                guard let l = byRemaining[Int(s.remainingAtEnd(o.distanceM).rounded())] else { continue }
                if let x = s.speedKmh { v[.speed, default: [:]][l] = x; if best > 0 { v[.pctBest, default: [:]][l] = x / best * 100 } }
                if s.sectorS > 0 { v[.sectorTime, default: [:]][l] = s.sectorS }
                if let p = s.position { v[.position, default: [:]][l] = Double(p) }
                if let x = s.strideLengthM { v[.stride, default: [:]][l] = x }
                if let n = s.strides { v[.strides, default: [:]][l] = Double(n) }
            }
        }
        let idx: Int = otherRaces.firstIndex { $0.id == o.id } ?? 0
        return DeepSeries(id: "c:" + o.id, name: "Carrera \(o.dateText) · \(o.title) (\(o.finishText))", short: "Carrera " + o.dateText,
                          color: DeepPalette.race(idx), kind: .otherRace, emphasis: false, values: v)
    }

    // ------------------------------------------------------------------ left panel
    private var selector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                section("Caballos de la carrera") {
                    HStack(spacing: 6) {
                        quick("Mío + ganador") {
                            shownRunners = Set([us?.name, race.winner?.name].compactMap { $0 })
                        }
                        quick("Top 3") {
                            var s: Set<String> = Set(race.runners.filter { ($0.finish ?? 99) <= 3 }.map { $0.name })
                            if let u = us { s.insert(u.name) }
                            shownRunners = s
                        }
                        quick("Todos") { shownRunners = Set(race.runners.map { $0.name }) }
                        quick("Ninguno") { shownRunners = [] }
                    }
                    ForEach(race.runners.sorted { ($0.finish ?? 99) < ($1.finish ?? 99) }) { (r: RaceRunner) in
                        toggleRow(on: shownRunners.contains(r.name), color: color(of: r), dash: false,
                                  title: "\(RaceFormat.place(r.finish)) \(r.name)",
                                  subtitle: "\(RaceFormat.official(r.officialTimeS)) · \(r.jockey)",
                                  bold: r.name == us?.name) {
                            if shownRunners.contains(r.name) { shownRunners.remove(r.name) } else { shownRunners.insert(r.name) }
                        }
                    }
                }
                section("Mis entrenamientos (\(RaceTrainingSplits.windowDays) días antes)") {
                    if candidates.isEmpty {
                        Text("Sin trabajos con parciales en los \(RaceTrainingSplits.windowDays) días anteriores.")
                            .font(.caption).foregroundStyle(Avo.textDim)
                    }
                    ForEach(Array(candidates.enumerated()), id: \.element.id) { (item: (offset: Int, element: RaceTrainingCandidate)) in
                        let c: RaceTrainingCandidate = item.element
                        toggleRow(on: shownTrainings.contains(c.id), color: DeepPalette.training(item.offset), dash: true,
                                  title: c.label, subtitle: "\(c.fullSplits) parciales completos", bold: false) {
                            if shownTrainings.contains(c.id) { shownTrainings.remove(c.id) } else { shownTrainings.insert(c.id) }
                        }
                    }
                }
                section("Otras carreras de \(race.horseName ?? "mi caballo")") {
                    if otherRaces.isEmpty {
                        Text("No hay otras carreras importadas de este caballo.").font(.caption).foregroundStyle(Avo.textDim)
                    }
                    ForEach(Array(otherRaces.enumerated()), id: \.element.id) { (item: (offset: Int, element: Race)) in
                        let o: Race = item.element
                        toggleRow(on: shownRaces.contains(o.id), color: DeepPalette.race(item.offset), dash: true,
                                  title: "\(o.dateText) · \(o.title)", subtitle: "\(o.hippodrome) · \(o.distanceText) · \(o.finishText)",
                                  bold: false) {
                            if shownRaces.contains(o.id) { shownRaces.remove(o.id) } else { shownRaces.insert(o.id) }
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).tracking(0.7).foregroundStyle(Avo.silver)
            content()
        }
    }

    private func quick(_ t: String, _ action: @escaping () -> Void) -> some View {
        Button(t, action: action)
            .font(.caption2.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(Avo.textDim)
            .controlSize(.mini)
    }

    private func toggleRow(on: Bool, color: Color, dash: Bool, title: String, subtitle: String, bold: Bool,
                           _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .foregroundStyle(on ? color : Avo.textDim).font(.system(size: 17))
                DeepLineSample(color: color, dash: dash).frame(width: 22, height: 10).opacity(on ? 1 : 0.35)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(bold ? .callout.weight(.bold) : .callout).foregroundStyle(Avo.text).lineLimit(1)
                    Text(subtitle).font(.caption2).foregroundStyle(Avo.textDim).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // ------------------------------------------------------------------ main
    private var metricBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(DeepMetric.allCases) { (m: DeepMetric) in
                    Button {
                        metric = m
                    } label: {
                        Label(m.title, systemImage: m.icon)
                            .font(.callout.weight(m == metric ? .semibold : .regular))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .foregroundStyle(m == metric ? Color.white : Avo.text)
                            .background(m == metric ? Avo.red : Avo.surface2, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("deep.metric.\(m.rawValue)")
                }
            }
        }
    }

    private struct Point: Identifiable {
        var id: String
        var series: String
        var label: String
        var value: Double
    }

    private var mainChart: some View {
        let ss: [DeepSeries] = series.filter { $0.has(metric) }
        let missing: [DeepSeries] = series.filter { !$0.has(metric) }
        return AvoCard(title: metric.title, subtitle: metric.subtitle) {
            if ss.isEmpty {
                AvoNoData(text: series.isEmpty ? "Elige caballos, entrenamientos o carreras en la lista de la izquierda"
                                               : "Esta medida no existe para lo elegido")
            } else {
                Chart {
                    ForEach(ss) { (s: DeepSeries) in
                        ForEach(points(s)) { (p: Point) in
                            LineMark(x: .value("Tramo", p.label), y: .value(metric.unit, p.value), series: .value("Serie", s.id))
                                .foregroundStyle(s.color)
                                .lineStyle(StrokeStyle(lineWidth: s.emphasis ? 3.5 : 2, dash: s.kind.dash))
                                .interpolationMethod(.linear)
                            PointMark(x: .value("Tramo", p.label), y: .value(metric.unit, p.value))
                                .foregroundStyle(s.color)
                                .symbolSize(s.emphasis ? 60 : 26)
                        }
                    }
                    if metric == .gapOurs || metric == .gapLeader {
                        RuleMark(y: .value("0", 0.0)).foregroundStyle(Avo.textDim).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                    if metric == .pctBest {
                        RuleMark(y: .value("100", 100.0)).foregroundStyle(Avo.textDim).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                    if let sel = selectedSector {
                        RuleMark(x: .value("Tramo", sel)).foregroundStyle(Avo.silver.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 10))
                    }
                }
                .chartXScale(domain: labels)
                .chartYScale(domain: .automatic(includesZero: false, reversed: metric.reversed))
                .chartXSelection(value: $selectedSector)
                .chartXAxis {
                    AxisMarks { (v: AxisValue) in
                        AxisGridLine().foregroundStyle(Avo.line)
                        AxisValueLabel { if let s = v.as(String.self) { Text(s).font(.caption).foregroundStyle(Avo.textDim) } }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { (v: AxisValue) in
                        AxisGridLine().foregroundStyle(Avo.line)
                        AxisValueLabel { if let d = v.as(Double.self) { Text(metric.axis(d)).font(.caption).foregroundStyle(Avo.textDim) } }
                    }
                }
                .frame(height: 420)
                legend(ss)
                if !missing.isEmpty {
                    Text("Sin «\(metric.title.lowercased())»: " + missing.map { $0.short }.joined(separator: ", "))
                        .font(.caption2).foregroundStyle(Avo.textDim)
                }
                Text("Toca o arrastra sobre la gráfica para ver los valores de un tramo.").font(.caption2).foregroundStyle(Avo.textDim)
            }
        }
    }

    private func points(_ s: DeepSeries) -> [Point] {
        labels.compactMap { (l: String) -> Point? in
            guard let v = s.values[metric]?[l], v.isFinite else { return nil }
            return Point(id: s.id + "|" + l, series: s.id, label: l, value: v)
        }
    }

    private func legend(_ ss: [DeepSeries]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 4) {
            ForEach(ss) { (s: DeepSeries) in
                HStack(spacing: 6) {
                    DeepLineSample(color: s.color, dash: s.kind != .runner).frame(width: 22, height: 10)
                    Text(s.short).font(s.emphasis ? .caption.weight(.bold) : .caption).foregroundStyle(Avo.text).lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private var sectorDetail: some View {
        if let sel = selectedSector {
            let rows: [(DeepSeries, Double)] = series.compactMap { (s: DeepSeries) -> (DeepSeries, Double)? in
                guard let v = s.values[metric]?[sel] else { return nil }
                return (s, v)
            }
            .sorted { (a: (DeepSeries, Double), b: (DeepSeries, Double)) -> Bool in metric.better(a.1, b.1) }
            AvoCard(title: "Tramo \(sel) · \(metric.title)", subtitle: "Ordenado de mejor a peor") {
                if rows.isEmpty {
                    AvoNoData()
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { (item: (offset: Int, element: (DeepSeries, Double))) in
                            HStack(spacing: 8) {
                                Text("\(item.offset + 1).").font(.callout.monospacedDigit()).foregroundStyle(Avo.textDim).frame(width: 28, alignment: .trailing)
                                Circle().fill(item.element.0.color).frame(width: 10, height: 10)
                                Text(item.element.0.name).font(item.element.0.emphasis ? .callout.weight(.bold) : .callout)
                                    .foregroundStyle(Avo.text).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(metric.format(item.element.1)).font(.callout.monospacedDigit().weight(.semibold)).foregroundStyle(Avo.text)
                            }
                        }
                    }
                }
            }
        }
    }

    private var summaryTable: some View {
        let ss: [DeepSeries] = series.filter { $0.has(metric) }
        return AvoCard(title: "Tabla · \(metric.title)", subtitle: "Verde = mejor del tramo entre lo mostrado · rojo = peor") {
            if ss.isEmpty {
                AvoNoData()
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            Text("").frame(width: 230, alignment: .leading)
                            ForEach(labels, id: \.self) { (l: String) in
                                Text(l).font(.caption2.weight(.semibold)).foregroundStyle(Avo.textDim).frame(width: 84)
                            }
                        }
                        .padding(.vertical, 6)
                        Divider().overlay(Avo.line)
                        ForEach(ss) { (s: DeepSeries) in
                            HStack(spacing: 0) {
                                HStack(spacing: 6) {
                                    Circle().fill(s.color).frame(width: 9, height: 9)
                                    Text(s.short).font(s.emphasis ? .footnote.weight(.bold) : .footnote).foregroundStyle(Avo.text).lineLimit(1)
                                }
                                .frame(width: 230, alignment: .leading)
                                ForEach(labels, id: \.self) { (l: String) in
                                    cell(s, l, ss)
                                }
                            }
                            .padding(.vertical, 4)
                            .background(s.emphasis ? Avo.red.opacity(0.08) : Color.clear)
                        }
                    }
                }
            }
        }
    }

    private func cell(_ s: DeepSeries, _ l: String, _ all: [DeepSeries]) -> some View {
        let v: Double? = s.values[metric]?[l]
        let col: [Double] = all.compactMap { $0.values[metric]?[l] }
        var tint: Color = Avo.text
        if let x = v, col.count >= 2 {
            let best: Double = col.sorted { metric.better($0, $1) }.first ?? x
            let worst: Double = col.sorted { metric.better($0, $1) }.last ?? x
            if abs(x - best) < 1e-9 { tint = Avo.ok } else if abs(x - worst) < 1e-9 { tint = Avo.bad }
        }
        return Text(v.map { metric.format($0) } ?? "—")
            .font(.footnote.monospacedDigit().weight(tint == Avo.text ? .regular : .semibold))
            .foregroundStyle(v == nil ? Avo.textDim : tint)
            .frame(width: 84)
    }
}

// MARK: - model of the view

enum DeepSeriesKind {
    case runner, training, otherRace
    var dash: [CGFloat] {
        switch self {
        case .runner: return []
        case .training: return [6, 4]
        case .otherRace: return [2, 3]
        }
    }
}

struct DeepSeries: Identifiable {
    var id: String
    var name: String
    var short: String
    var color: Color
    var kind: DeepSeriesKind
    var emphasis: Bool
    var values: [DeepMetric: [String: Double]]
    func has(_ m: DeepMetric) -> Bool { !(values[m]?.isEmpty ?? true) }
}

enum DeepMetric: String, CaseIterable, Identifiable {
    case speed, pctBest, sectorTime, position, gapLeader, gapOurs, stride, strides

    var id: String { rawValue }
    var title: String {
        switch self {
        case .speed: return "Velocidad"
        case .pctBest: return "% de su mejor tramo"
        case .sectorTime: return "Tiempo del tramo"
        case .position: return "Posición"
        case .gapLeader: return "Distancia al primero"
        case .gapOurs: return "Diferencia con mi caballo"
        case .stride: return "Zancada"
        case .strides: return "Foulées"
        }
    }
    var icon: String {
        switch self {
        case .speed: return "speedometer"
        case .pctBest: return "chart.line.downtrend.xyaxis"
        case .sectorTime: return "stopwatch"
        case .position: return "list.number"
        case .gapLeader: return "flag.checkered"
        case .gapOurs: return "arrow.left.and.right"
        case .stride: return "ruler"
        case .strides: return "figure.equestrian.sports"
        }
    }
    var subtitle: String {
        switch self {
        case .speed: return "km/h de cada tramo de 200 m"
        case .pctBest: return "Velocidad de cada tramo / su mejor tramo: cómo mantiene la velocidad hasta la meta"
        case .sectorTime: return "Segundos de cada tramo (menos es mejor)"
        case .position: return "Puesto al final de cada tramo (1 = en cabeza)"
        case .gapLeader: return "Segundos detrás del caballo en cabeza al final de cada tramo (1 cuerpo ≈ 0,2 s)"
        case .gapOurs: return "Segundos respecto a mi caballo al final de cada tramo: por debajo de 0 va por delante de mi caballo"
        case .stride: return "Metros por zancada = longitud del tramo / foulées"
        case .strides: return "Número de foulées (zancadas) en cada tramo"
        }
    }
    var note: String {
        switch self {
        case .speed, .pctBest, .sectorTime:
            return "Líneas continuas: caballos de esta carrera · discontinuas: tus entrenamientos (playa, alineados desde la meta) · punteadas: otras carreras de tu caballo (alineadas por la distancia a la meta). Entrenamiento y carrera tienen superficie y ritmo distintos: compara la forma de las curvas, no los valores absolutos."
        case .position, .gapLeader, .gapOurs:
            return "Solo para los caballos de esta carrera (y la posición de tus otras carreras). Los entrenamientos no tienen rivales."
        case .stride, .strides:
            return "Zancada y foulées salen del tracker de la carrera; el primer tramo incluye la salida."
        }
    }
    var unit: String {
        switch self {
        case .speed: return "km/h"
        case .pctBest: return "%"
        case .sectorTime, .gapLeader, .gapOurs: return "s"
        case .position: return "puesto"
        case .stride: return "m"
        case .strides: return "foulées"
        }
    }
    /// Position upside down (1 at the top).
    var reversed: Bool { self == .position }
    /// a is better than b.
    func better(_ a: Double, _ b: Double) -> Bool {
        switch self {
        case .speed, .pctBest, .stride: return a > b
        case .sectorTime, .position, .gapLeader, .gapOurs, .strides: return a < b
        }
    }
    func format(_ v: Double) -> String {
        switch self {
        case .speed: return AvoFormat.f(v, 1) + " km/h"
        case .pctBest: return AvoFormat.f(v, 0) + " %"
        case .sectorTime: return AvoFormat.f(v, 2) + " s"
        case .position: return AvoFormat.f(v, 0) + ".º"
        case .gapLeader: return "+" + AvoFormat.f(max(0, v), 2) + " s"
        case .gapOurs: return (v > 0 ? "+" : (v < 0 ? "−" : "")) + AvoFormat.f(abs(v), 2) + " s"
        case .stride: return AvoFormat.f(v, 2) + " m"
        case .strides: return AvoFormat.f(v, 0)
        }
    }
    func axis(_ v: Double) -> String {
        switch self {
        case .position: return AvoFormat.f(v, 0) + ".º"
        case .pctBest: return AvoFormat.f(v, 0) + " %"
        case .stride: return AvoFormat.f(v, 1)
        default: return AvoFormat.f(v, abs(v) < 10 ? 1 : 0)
        }
    }
}

enum DeepPalette {
    private static let runners: [Color] = [
        Color(red: 0.95, green: 0.62, blue: 0.10), Color(red: 0.55, green: 0.78, blue: 0.25), Color(red: 0.70, green: 0.45, blue: 0.95),
        Color(red: 0.98, green: 0.45, blue: 0.70), Color(red: 0.40, green: 0.85, blue: 0.75), Color(red: 0.85, green: 0.80, blue: 0.20),
        Color(red: 0.60, green: 0.60, blue: 0.65), Color(red: 0.95, green: 0.40, blue: 0.25), Color(red: 0.30, green: 0.55, blue: 0.95),
        Color(red: 0.75, green: 0.55, blue: 0.40), Color(red: 0.50, green: 0.95, blue: 0.45), Color(red: 0.90, green: 0.70, blue: 0.95)]
    private static let trainings: [Color] = [Avo.cyan, Color(red: 0.10, green: 0.75, blue: 0.60), Color(red: 0.20, green: 0.55, blue: 0.85),
                                             Color(red: 0.45, green: 0.85, blue: 0.95)]
    private static let races: [Color] = [Color(red: 0.85, green: 0.35, blue: 0.85), Color(red: 1.0, green: 0.55, blue: 0.20),
                                         Color(red: 0.95, green: 0.85, blue: 0.30)]
    static func runner(_ i: Int) -> Color { runners[i % runners.count] }
    static func training(_ i: Int) -> Color { trainings[i % trainings.count] }
    static func race(_ i: Int) -> Color { races[i % races.count] }
}

/// Small line sample (solid or dashed) for the legend and the selector.
struct DeepLineSample: View {
    let color: Color
    let dash: Bool
    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            p.move(to: CGPoint(x: 0, y: size.height / 2))
            p.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: dash ? [4, 3] : []))
        }
    }
}
