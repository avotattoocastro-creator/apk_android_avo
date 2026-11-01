import SwiftUI
import Charts

/// «GPS» page: every GNSS/RTK datum of the selected training, without a map (solution quality, satellites, reported
/// accuracies, signal losses, rejected jumps, frequency, epochs, altitude, reported vs derived speed and receiver
/// information). The positions are those of the rider's vest antenna, not of the horse.
struct GpsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        GeometryReader { geo in
            let wide: Bool = geo.size.width >= 900
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    AvoPageTitle(title: "Datos GPS",
                                 subtitle: app.selected.map { "Receptor GNSS/RTK del chaleco del jinete · \($0.summary)" }
                                    ?? "Sin entrenamiento seleccionado · importa un archivo .avo o .avr")
                    GpsAntennaNote()
                    if app.selected == nil {
                        AvoCard { AvoNoData(text: "Sin entrenamiento seleccionado") }
                    } else if let sum = app.gps.summary {
                        if sum.hasData || sum.epochsReceived > 0 {
                            GpsContent(summary: sum, wide: wide)
                        } else {
                            AvoCard { AvoNoData(text: "Este entrenamiento no tiene datos GPS") }
                        }
                    } else {
                        AvoCard {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Calculando los datos GPS…").font(.footnote).foregroundStyle(Avo.textDim)
                            }
                            .frame(maxWidth: .infinity, minHeight: 80)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(Avo.bg)
        .onAppear { app.gps.pageShown() }
        .onChange(of: app.selected?.id ?? "") { _, _ in app.gps.pageShown() }
    }
}

/// Where the positions come from.
private struct GpsAntennaNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "location.circle").font(.title3).foregroundStyle(Avo.cyan)
            Text("La trayectoria y todos estos datos son los de la antena GNSS del chaleco del jinete (receptor RTK), no un punto anatómico del caballo. La velocidad y la distancia del caballo se derivan de esta antena; los aires, la cadencia y la simetría vienen de la cincha.")
                .font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Avo.cardBrush, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Avo.line, lineWidth: 1))
    }
}

private struct GpsContent: View {
    let summary: GpsSummary
    let wide: Bool

    static let order: [GnssSolution] = [.rtkFix, .rtkFloat, .dgnss, .autonomous, .none]

    var body: some View {
        let sum: GpsSummary = summary
        let grid: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: wide ? 2 : 1)
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10, alignment: .top)], spacing: 10) {
                AvoMetric(label: "RTK FIX", value: GpsFmt.num(sum.distribution[.rtkFix], "0.0"), unit: "%",
                          caption: "De las épocas recibidas", accent: Avo.ok, icon: "scope")
                AvoMetric(label: "Satélites (mediana)", value: GpsFmt.num(sum.satMedian, "0"),
                          caption: "Mín. \(GpsFmt.num(sum.satMin, "0")) · máx. \(GpsFmt.num(sum.satMax, "0"))", icon: "dot.radiowaves.up.forward")
                AvoMetric(label: "hAcc reportada", value: GpsFmt.num(sum.hAccMedian, "0.000"), unit: "m",
                          caption: "Mediana · p95 \(GpsFmt.num(sum.hAccP95, "0.000", " m"))", icon: "scope")
                AvoMetric(label: "Frecuencia GNSS", value: GpsFmt.num(sum.frequencyHz, "0.#"), unit: "Hz",
                          caption: "Intervalo nominal \(GpsFmt.num(sum.nominalDtS, "0.000", " s"))", icon: "metronome")
                AvoMetric(label: "Épocas", value: "\(sum.epochsReceived)",
                          caption: "\(sum.epochsUsable) utilizables · \(sum.epochsWithoutSolution) sin solución", icon: "number")
                AvoMetric(label: "Pérdidas de señal", value: "\(sum.losses.count)",
                          caption: "Total \(TimeText.clock(sum.lossTotalS)) · \(sum.jumps) saltos descartados",
                          accent: sum.losses.isEmpty ? Avo.text : Avo.bad, icon: "antenna.radiowaves.left.and.right.slash")
            }
            GpsQualityCard(summary: sum)
            LazyVGrid(columns: grid, spacing: 12) {
                FeatureChartPanel(title: "Satélites usados en la solución",
                                  readout: "mediana \(GpsFmt.num(sum.satMedian, "0")) · mín. \(GpsFmt.num(sum.satMin, "0")) · máx. \(GpsFmt.num(sum.satMax, "0"))") {
                    GpsChart(series: sum.satSeries, includeZero: true, empty: "Sin datos de satélites")
                }
                FeatureChartPanel(title: "Precisión horizontal reportada (hAcc, m)",
                                  readout: "mediana \(GpsFmt.num(sum.hAccMedian, "0.000")) · p95 \(GpsFmt.num(sum.hAccP95, "0.000")) m") {
                    GpsChart(series: sum.hAccSeries, includeZero: true, empty: "Sin datos de hAcc")
                }
                FeatureChartPanel(title: "Precisión de velocidad reportada (km/h)",
                                  readout: sum.hasSpeedAcc ? "mediana \(GpsFmt.num(sum.speedAccMedian * 3.6, "0.00")) · p95 \(GpsFmt.num(sum.speedAccP95 * 3.6, "0.00")) km/h" : nil) {
                    GpsChart(series: sum.speedAccSeries, includeZero: true, empty: "El receptor no informa la precisión de velocidad (sAcc)")
                }
                FeatureChartPanel(title: "Altitud sobre el nivel medio del mar (m)",
                                  readout: sum.hasAltitude ? "mín. \(GpsFmt.num(sum.altMin, "0.0")) · máx. \(GpsFmt.num(sum.altMax, "0.0")) m" : nil) {
                    GpsChart(series: sum.altSeries, includeZero: false, empty: "Sin datos de altitud")
                }
            }
            GpsSpeedAgreementCard(summary: sum)
            LazyVGrid(columns: grid, spacing: 12) {
                GpsLossesCard(summary: sum)
                AvoCard(title: "Receptor GNSS/RTK y sensores") {
                    ForEach(sum.sensorRows) { (r: FeatureKV) in FeatureKeyValue(key: r.key, value: r.value) }
                    FeatureKeyValue(key: "Altitud MSL mediana", value: GpsFmt.num(sum.altMedian, "0.0", " m"))
                    FeatureKeyValue(key: "hAcc máxima", value: GpsFmt.num(sum.hAccMax, "0.000", " m"))
                }
            }
        }
    }
}

/// Solution quality: distribution bar with percentages and the quality strip over time.
private struct GpsQualityCard: View {
    @Environment(AppModel.self) private var app
    let summary: GpsSummary

    var body: some View {
        let sum: GpsSummary = summary
        AvoCard(title: "Calidad de la solución", subtitle: "Porcentaje de épocas recibidas por tipo de solución (parte analizada)") {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(GpsContent.order, id: \.self) { (k: GnssSolution) in
                        let p: Double = sum.distribution[k] ?? 0
                        Rectangle().fill(Avo.solution(k))
                            .frame(width: max(0, geo.size.width * CGFloat(p / 100)))
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 14)
            .background(Avo.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(GpsContent.order, id: \.self) { (k: GnssSolution) in
                    HStack(spacing: 6) {
                        Circle().fill(Avo.solution(k)).frame(width: 9, height: 9)
                        Text(GnssQuality.name(k)).font(.caption).foregroundStyle(Avo.textDim).lineLimit(1)
                        Text(GpsFmt.num(sum.distribution[k] ?? 0, "0.0", " %")).font(.caption.weight(.semibold)).foregroundStyle(Avo.text)
                    }
                }
            }
            Divider().background(Avo.line)
            Text("EVOLUCIÓN EN EL TIEMPO").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim)
            GpsQualityStrip(runs: sum.runs, t0: sum.t0, t1: sum.t1, cursor: app.cursorTime)
                .frame(height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Avo.line, lineWidth: 1))
            HStack {
                Text(TimeText.clock(sum.t0)).font(.caption2.monospacedDigit()).foregroundStyle(Avo.textDim)
                Spacer()
                Text("Los huecos (sin épocas utilizables) aparecen en rojo").font(.caption2).foregroundStyle(Avo.textDim)
                Spacer()
                Text(TimeText.clock(sum.t1)).font(.caption2.monospacedDigit()).foregroundStyle(Avo.textDim)
            }
        }
    }
}

/// Coloured strip of the solution type along the analysed part (gaps in the «no solution» colour), with the cursor.
private struct GpsQualityStrip: View {
    let runs: [GpsSolutionRun]
    let t0: Double
    let t1: Double
    let cursor: Double

    var body: some View {
        Canvas { (context: inout GraphicsContext, size: CGSize) in
            let span: Double = t1 - t0
            context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: size.height)),
                         with: .color(Avo.solution(GnssSolution.none).opacity(0.8)))
            if span <= 0 || runs.isEmpty { return }
            let w: Double = Double(size.width)
            for r in runs {
                let x0: Double = (r.t0 - t0) / span * w
                let x1: Double = (r.t1 - t0) / span * w
                let rect = CGRect(x: CGFloat(x0), y: 0, width: CGFloat(max(x1 - x0, 0.6)), height: size.height)
                context.fill(Path(rect), with: .color(Avo.solution(r.solution)))
            }
            if cursor.isFinite && cursor >= t0 && cursor <= t1 {
                let x: CGFloat = CGFloat((cursor - t0) / span * w)
                context.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)), with: .color(Avo.text))
            }
        }
        .accessibilityLabel("Calidad de la solución GNSS a lo largo del entrenamiento")
    }
}

/// Time-series chart synchronised with the shared cursor (tap = move the cursor).
private struct GpsChart: View {
    @Environment(AppModel.self) private var app
    let series: [FeatureLineSeries]
    let includeZero: Bool
    let empty: String

    var body: some View {
        FeatureLineChart(series: series, axis: .clock, includeZero: includeZero, cursorX: app.cursorTime,
                         emptyText: empty, onTapX: { (t: Double) in app.cursorTime = t })
    }
}

/// Reported (Doppler) vs derived (positions) speed.
private struct GpsSpeedAgreementCard: View {
    let summary: GpsSummary

    var body: some View {
        let sum: GpsSummary = summary
        FeatureChartPanel(title: "Velocidad reportada frente a derivada de posiciones (km/h)",
                          readout: sum.speedPairs > 0 ? "diferencia mediana \(GpsFmt.num(sum.speedDiffMedianKmh, "0.00")) km/h" : nil,
                          minHeight: 200) {
            VStack(alignment: .leading, spacing: 8) {
                GpsChart(series: sum.speedSeries, includeZero: true, empty: "Sin datos de velocidad")
                    .frame(minHeight: 180)
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                    GridRow {
                        kv("Épocas comparadas", "\(sum.speedPairs)")
                        kv("Diferencia mediana", GpsFmt.num(sum.speedDiffMedianKmh, "0.00", " km/h"))
                        kv("Diferencia p95", GpsFmt.num(sum.speedDiffP95Kmh, "0.00", " km/h"))
                    }
                    GridRow {
                        kv("Sesgo (derivada − reportada)", GpsFmt.num(sum.speedBiasKmh, "+0.00;-0.00;0.00", " km/h"))
                        kv("Máx. reportada", GpsFmt.num(sum.reportedMaxKmh, "0.0", " km/h"))
                        kv("Máx. derivada", GpsFmt.num(sum.derivedMaxKmh, "0.0", " km/h"))
                    }
                }
                Text("La velocidad reportada es la Doppler del receptor; la derivada sale de posiciones consecutivas (más ruidosa) y sirve de comprobación independiente.")
                    .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func kv(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k.uppercased()).font(.caption2.weight(.semibold)).tracking(0.4).foregroundStyle(Avo.textDim).lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(v).font(.footnote.weight(.semibold).monospacedDigit()).foregroundStyle(Avo.text)
        }
    }
}

/// Signal losses (tap = cursor) and rejected position jumps.
private struct GpsLossesCard: View {
    @Environment(AppModel.self) private var app
    let summary: GpsSummary

    var body: some View {
        let sum: GpsSummary = summary
        AvoCard(title: "Pérdidas de señal y saltos", subtitle: "Intervalos sin solución GNSS utilizable (nunca se interpolan)") {
            if sum.losses.isEmpty {
                Text("Sin pérdidas de señal en la parte analizada").font(.footnote).foregroundStyle(Avo.textDim)
                    .padding(.vertical, 6)
            } else {
                ForEach(sum.losses.prefix(80)) { (l: GpsLossRow) in
                    Button {
                        app.cursorTime = l.t0
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle().fill(Avo.bad).frame(width: 7, height: 7)
                            Text("\(TimeText.clock(l.t0)) – \(TimeText.clock(l.t1))").font(.footnote.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Avo.text)
                            Text(TimeText.num(l.durationS, "0.0", " s")).font(.footnote).foregroundStyle(Avo.textDim)
                            Text(l.reason).font(.caption).foregroundStyle(Avo.textDim).lineLimit(2)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if sum.losses.count > 80 {
                    Text("… y \(sum.losses.count - 80) más").font(.caption2).foregroundStyle(Avo.textDim)
                }
            }
            Divider().background(Avo.line)
            FeatureKeyValue(key: "Saltos de posición descartados", value: "\(sum.jumps)")
            if !sum.jumpTimes.isEmpty {
                Text(sum.jumpTimes.prefix(30).map { TimeText.clock($0) }.joined(separator: " · ")
                     + (sum.jumpTimes.count > 30 ? " …" : ""))
                    .font(.caption2.monospacedDigit()).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            }
            Text("Un salto es un paso entre dos posiciones físicamente imposible: se excluye de la distancia.")
                .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Number formatting with «Sin datos» for missing values.
enum GpsFmt {
    static func num(_ v: Double?, _ fmt: String, _ unit: String = "") -> String {
        TimeText.num(v, fmt, unit, missing: "Sin datos")
    }
}
