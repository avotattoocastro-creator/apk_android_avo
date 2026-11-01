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
                FeatureSessionHeader()
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
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 12) {
                            HStack(alignment: .top, spacing: 12) {
                                BiomechDiagramCard(model: model).frame(maxWidth: .infinity)
                                BiomechHeadlines(model: model).frame(maxWidth: .infinity)
                            }
                        }
                        BiomechEngineCard(model: model).frame(width: 310)
                    }
                }
                BiomechChannelsCard(model: model)
                BiomechWindowCharts(model: model)
                FeatureChartPanel(title: "Cadencia por sensor (ciclos/min)", readout: app.cursorCadence, minHeight: 190) {
                    FeatureLineChart(series: model.cadenceSeries, axis: .clock, xMin: app.chartXMin, xMax: app.chartXMax,
                                     cursorX: app.cursorTime, rangeStart: app.rangeStart, rangeEnd: app.rangeEnd,
                                     bands: model.gaitBands, emptyText: "Sin cadencia: requiere cincha y motor",
                                     onTapX: { (x: Double) in app.cursorTime = x })
                }
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
        .background(Avo.bg)
        .onAppear { model.pageShown() }
        .onChange(of: app.cursorTime) { model.cursorChanged() }
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
        AvoCard(title: "Cincha · posición de los sensores") {
            HorseDiagramView(activeSensors: model.activeSensors)
                .frame(minHeight: 240)
                .aspectRatio(1448.0 / 1086.0, contentMode: .fit)
                .accessibilityIdentifier("biomech.horse")
        }
    }
}

private struct BiomechHeadlines: View {
    var model: BiomechModel
    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                AvoMetric(label: "Asimetría temporal (exploratoria)", value: model.symmetryHeadline, unit: "%",
                          caption: "(d1 − d2)/(d1 + d2), grupos reproducibles", accent: Avo.cyan)
                AvoMetric(label: "Cadencia media", value: model.cadenceHeadline, unit: "ciclos/min",
                          caption: "Sensor central · ventanas válidas")
            }
            GridRow {
                AvoMetric(label: "Regularidad", value: model.regularityHeadline, caption: "Correlación entre ciclos (0–1)", accent: Avo.ok)
                AvoMetric(label: "Longitud de tranco", value: model.strideHeadline, unit: "m",
                          caption: "Velocidad / cadencia (estimación)")
            }
        }
    }
}

private struct BiomechEngineCard: View {
    var model: BiomechModel
    var body: some View {
        AvoCard(title: "Índices del motor por sensor") {
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
    var body: some View {
        AvoCard(title: "Canales de la cincha", subtitle: model.scaleNote) {
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

/// IMU window ±2 s around the cursor: |a| / axes / gyro and the fused girth movement (fmt 1).
private struct BiomechWindowCharts: View {
    @Environment(\.horizontalSizeClass) private var hSize
    var model: BiomechModel

    var body: some View {
        @Bindable var m = model
        VStack(alignment: .leading, spacing: 12) {
            FeatureChartPanel(title: title, minHeight: 190) {
                VStack(alignment: .leading, spacing: 8) {
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
                    FeatureLineChart(series: model.imuWindowSeries, axis: .number, xMin: model.imuWindowMin, xMax: model.imuWindowMax,
                                     emptyText: "Sin datos de cincha")
                    if !model.windowCaption.isEmpty {
                        Text(model.windowCaption).font(.caption2).foregroundStyle(Avo.textDim)
                    }
                }
            }
            if model.hasFused {
                if hSize == .compact {
                    fusedAccel
                    orientation
                } else {
                    HStack(alignment: .top, spacing: 12) { fusedAccel; orientation }
                }
            }
        }
    }

    private var title: String {
        switch model.windowSignal {
        case .magnitude: return "Patrón de movimiento · |a| cincha ±2 s del cursor (g)"
        case .axes: return "Aceleración por ejes · cincha ±2 s del cursor (g)"
        case .gyro: return "Velocidad de giro · cincha ±2 s del cursor (°/s)"
        }
    }

    private var fusedAccel: some View {
        FeatureChartPanel(title: "Movimiento de la cincha · aceleración sin gravedad (m/s²)", minHeight: 170) {
            FeatureLineChart(series: model.fusedAccelWindow, axis: .number, xMin: model.imuWindowMin, xMax: model.imuWindowMax,
                             includeZero: true, emptyText: "Sin datos")
        }
    }

    private var orientation: some View {
        FeatureChartPanel(title: "Balanceo y cabeceo de la cincha (°)", minHeight: 170) {
            FeatureLineChart(series: model.orientationWindow, axis: .number, xMin: model.imuWindowMin, xMax: model.imuWindowMax,
                             emptyText: "Sin datos")
        }
    }
}
