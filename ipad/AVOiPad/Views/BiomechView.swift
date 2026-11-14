import SwiftUI

/// Biomechanics (Windows Views/BiomechView.xaml). Every index comes from the AVO Equine Intelligence engine and is labelled
/// exploratory: uncalibrated IMU, no clinical diagnosis, no limb load. Without girth data nothing is computed.
struct BiomechView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        let model: BiomechModel = app.biomech
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.status)
                    .font(.footnote).foregroundStyle(Avo.text)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Avo.warn.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Avo.warn.opacity(0.4), lineWidth: 1))
                    .accessibilityIdentifier("biomech.status")
                if hSize == .compact {
                    BiomechDiagramCard(model: model)
                    BiomechHeadlines(model: model)
                    BiomechEngineCard(model: model)
                    BiomechChannelsCard(model: model)
                } else {
                    // trainer 14/11/2026 («misma medida»): four blocks of the same size, two equal columns and two
                    // rows of equal height: horse | figures, then «Canales de la cincha» | «Índices del motor por sensor»
                    VStack(spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            BiomechDiagramCard(model: model).frame(maxWidth: .infinity, maxHeight: .infinity)
                            BiomechHeadlines(model: model).frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        HStack(alignment: .top, spacing: 12) {
                            BiomechChannelsCard(model: model, fill: true).frame(maxWidth: .infinity, maxHeight: .infinity)
                            BiomechEngineCard(model: model).frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                BiomechWindowCharts(model: model)
                AvoCard(title: "Simetría exploratoria por sensor y aire (motor AVO)") {
                    FeatureTable(headers: ["IMU", "Aire", "Ventanas", "Trancos", "ln(A1/A2)", "Reproducible", "Asim. temporal", "Reproducible", "Similitud mitades"],
                                 widths: [50, 90, 70, 70, 80, 90, 100, 90, 120],
                                 rows: model.symmetryRows.map { (g: EngineSymmetryGroup) -> [String] in
                                     [String(g.imu), g.gait, String(g.windows), String(g.strides),
                                      BiomechView.fmt(g.logAmplitudeRatio, "0.000"), g.amplitudeReproducible ? "Sí" : "No",
                                      BiomechView.fmt(g.temporalAsymmetry, "0.000"), g.temporalReproducible ? "Sí" : "No",
                                      BiomechView.fmt(g.halfSimilarity, "0.00")]
                                 })
                }
            }
            .padding(16)
        }
        // while «Seleccionar tramo» is on, a drag on a chart selects instead of scrolling
        .scrollDisabled(app.charts.rangeMode)
        .background(Avo.bg)
        // the girth charts share the timeline window of «Gráficas» (its full extent comes from the charts model)
        .onAppear { model.pageShown(); app.charts.pageShown() }
    }

    /// DataGrid StringFormat on a double? (empty when null).
    static func fmt(_ v: Double?, _ f: String) -> String {
        guard let d = v, d.isFinite else { return "" }
        return DotNetFormat.custom(d, f, spanish: true)
    }
}

private struct BiomechDiagramCard: View {
    var model: BiomechModel
    var body: some View {
        AvoCard(title: "Cincha · posición de los sensores", fill: true) {
            HorseDiagramView(activeSensors: model.activeSensors)
                .aspectRatio(1448.0 / 1086.0, contentMode: .fit)
                .frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
                .accessibilityIdentifier("biomech.horse")
        }
    }
}

private struct BiomechHeadlines: View {
    var model: BiomechModel
    var body: some View {
        // same size for the four figures (two equal rows of two equal columns, «Datos clave» style)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                AvoMetric(label: "Asimetría temporal (exploratoria)", value: model.symmetryHeadline, unit: "%",
                          caption: "(d1 − d2)/(d1 + d2), grupos reproducibles", accent: Avo.cyan).frame(maxHeight: .infinity)
                AvoMetric(label: "Cadencia media", value: model.cadenceHeadline, unit: "ciclos/min",
                          caption: "Sensor central · ventanas válidas").frame(maxHeight: .infinity)
            }
            HStack(spacing: 0) {
                AvoMetric(label: "Regularidad", value: model.regularityHeadline, caption: "Correlación entre ciclos (0–1)", accent: Avo.ok)
                    .frame(maxHeight: .infinity)
                AvoMetric(label: "Longitud de tranco", value: model.strideHeadline, unit: "m",
                          caption: "Velocidad / cadencia (estimación)").frame(maxHeight: .infinity)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Avo.cardBrush, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Avo.line, lineWidth: 1))
    }
}

private struct BiomechEngineCard: View {
    var model: BiomechModel
    var body: some View {
        AvoCard(title: "Índices del motor por sensor", fill: true) {
            if model.metrics.isEmpty {
                AvoNoData()
            } else {
                VStack(spacing: 0) {
                    ForEach(model.metrics) { (r: FeatureKV) in FeatureKeyValue(key: r.key, value: r.value) }
                }
            }
            Text("CONTROLES DE SIMETRÍA").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim).padding(.top, 6)
            if model.symmetryControls.isEmpty {
                Text("Sin datos").font(.caption).foregroundStyle(Avo.textDim)
            } else {
                ForEach(0..<model.symmetryControls.count, id: \.self) { (i: Int) in
                    Text(model.symmetryControls[i]).font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(model.scaleNote).font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
        }
    }
}

/// Girth channels, sample rate and scale (decoded data, before the engine).
private struct BiomechChannelsCard: View {
    var model: BiomechModel
    var fill: Bool = false
    var body: some View {
        AvoCard(title: "Canales de la cincha", subtitle: model.scaleNote, fill: fill) {
            FeatureKeyValue(key: "Frecuencia de muestreo", value: model.sampleRateText)
            FeatureKeyValue(key: "Alineación con el chaleco", value: model.alignmentText)
            if model.channels.isEmpty {
                AvoNoData(text: "Sin datos de cincha")
            } else {
                ForEach(model.channels) { (c: BiomechChannelRow) in
                    HStack(spacing: 8) {
                        Circle().fill(c.color).frame(width: 9, height: 9)
                        Text(c.name).font(.footnote.weight(.medium)).foregroundStyle(Avo.text)
                        Spacer()
                        Text("\(c.samples) · \(c.span)").font(.caption.monospacedDigit()).foregroundStyle(Avo.textDim)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

/// Girth charts on the SHARED timeline of the training: same cursor, zoom, range («tramo»), phase filter and scroll bar
/// as «Análisis» and «Gráficas». Legends switch every line on/off. «Ver ±2 s del cursor» gives the detailed view.
private struct BiomechWindowCharts: View {
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var hSize
    var model: BiomechModel

    var body: some View {
        @Bindable var m = model
        let charts: ChartsModel = app.charts
        let d: ClosedRange<Double> = charts.domain
        let bands: [SyncBand] = app.corrections.bands(app.selected)
        let key: String = "\(d.lowerBound)|\(d.upperBound)|\(model.windowSignal.rawValue)|\(model.windowSensor)|\(app.selected?.id ?? "")|\(app.selected?.engine == nil)"
        VStack(alignment: .leading, spacing: 12) {
            // trainer's sketch 14/11/2026: no zoom / tramo buttons and no «VER» phase row; the overview bar stays
            ChartsOverviewBar(charts: charts).frame(height: 34)
            SyncChartBox(title: title, legend: model.legendMain, chartId: "bio.main.\(model.windowSignal.rawValue)") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Picker("Señal", selection: $m.windowSignal) {
                            ForEach(BiomechWindowSignal.allCases) { (s: BiomechWindowSignal) in Text(s.rawValue).tag(s) }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 320)
                        if model.windowSignal != .magnitude && model.channels.filter({ !$0.fused }).count > 1 {
                            Picker("Sensor", selection: $m.windowSensor) {
                                ForEach(model.channels.filter { !$0.fused }) { (c: BiomechChannelRow) in Text(c.name).tag(c.id) }
                            }
                            .pickerStyle(.menu)
                        }
                        Spacer()
                    }
                    SyncSignalChart(panel: charts.filtered(model.panelMain, chart: "bio.main.\(model.windowSignal.rawValue)", legend: model.legendMain),
                                    domain: d, bands: bands, includeZero: false, emptyText: "Sin datos de cincha", scrollFriendly: true)
                }
            }
            .frame(height: 300)
            if model.hasFused {
                if hSize == .compact {
                    fusedAccel(d, bands).frame(height: 240)
                    orientation(d, bands).frame(height: 240)
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        fusedAccel(d, bands)
                        orientation(d, bands)
                    }
                    .frame(height: 260)
                }
            }
            SyncChartBox(title: "Cadencia por sensor (ciclos/min)", legend: model.legendCadence,
                         readout: { (a: AppModel) -> String in a.cursorCadence }, chartId: "bio.cadence") {
                SyncSignalChart(panel: charts.filtered(model.panelCadence, chart: "bio.cadence", legend: model.legendCadence),
                                domain: d, bands: bands, includeZero: false, emptyText: "Sin cadencia: requiere cincha y motor", scrollFriendly: true)
            }
            .frame(height: 220)
        }
        .task(id: key) {
            try? await Task.sleep(nanoseconds: 40_000_000)
            if Task.isCancelled { return }
            await model.refreshPanels(d.lowerBound, d.upperBound)
        }
    }

    private var title: String {
        switch model.windowSignal {
        case .magnitude: return "Patrón de movimiento · |a| de la cincha (g)"
        case .axes: return "Aceleración por ejes · cincha (g)"
        case .gyro: return "Velocidad de giro · cincha (°/s)"
        }
    }

    private func fusedAccel(_ d: ClosedRange<Double>, _ bands: [SyncBand]) -> some View {
        SyncChartBox(title: "Movimiento de la cincha · aceleración sin gravedad (m/s²)", legend: model.legendFused, chartId: "bio.fused") {
            SyncSignalChart(panel: app.charts.filtered(model.panelFused, chart: "bio.fused", legend: model.legendFused),
                            domain: d, bands: bands, includeZero: true, emptyText: "Sin datos", scrollFriendly: true)
        }
    }

    private func orientation(_ d: ClosedRange<Double>, _ bands: [SyncBand]) -> some View {
        SyncChartBox(title: "Balanceo y cabeceo de la cincha (°)", legend: model.legendOrient, chartId: "bio.orient") {
            SyncSignalChart(panel: app.charts.filtered(model.panelOrient, chart: "bio.orient", legend: model.legendOrient),
                            domain: d, bands: bands, includeZero: false, emptyText: "Sin datos", scrollFriendly: true)
        }
    }
}
