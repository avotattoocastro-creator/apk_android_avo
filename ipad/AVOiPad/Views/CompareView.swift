import SwiftUI
import MapKit

/// Training comparison (Windows Views/CompareView.xaml): sessions to compare on the left; on the right ONE vertical scroll
/// with full-width blocks: overlaid routes, aligned speed, validated acceleration, girth IMU (lateral deviation, tilts),
/// engine cadence, comparative statistics and the engine comparison of two sessions.
struct CompareView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        let model: CompareModel = app.compare
        VStack(alignment: .leading, spacing: 12) {
            AvoPageTitle(title: "Comparar entrenamientos",
                         subtitle: "Series alineadas por tiempo relativo o distancia; sin interpolar a través de huecos sin datos")
            if hSize == .compact {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        CompareSessionPicker(model: model)
                        CompareResults(model: model)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    ScrollView { CompareSessionPicker(model: model) }
                        .frame(width: 300)
                    ScrollView { CompareResults(model: model) }
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .background(Avo.bg)
        .onAppear { model.pageShown() }
    }
}

/// «Entrenamientos a comparar» card: list with check boxes and colour, alignment, actions and verdict.
private struct CompareSessionPicker: View {
    @Environment(AppModel.self) private var app
    var model: CompareModel

    var body: some View {
        @Bindable var m = model
        AvoCard(title: "Entrenamientos a comparar") {
            if app.sessionsView.isEmpty {
                AvoNoData(text: "Sin entrenamientos importados")
            } else {
                VStack(spacing: 2) {
                    ForEach(app.sessionsView) { (s: SessionItem) in
                        Button {
                            model.toggle(s)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: s.isCompared ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(s.isCompared ? Avo.red : Avo.textDim)
                                RoundedRectangle(cornerRadius: 2).fill(s.compareColor).frame(width: 4, height: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(s.dateTimeText).font(.callout.weight(.semibold)).foregroundStyle(Avo.text)
                                        if s.isSynthetic { AvoPill(text: "DEMOSTRACIÓN", color: Avo.warn) }
                                    }
                                    Text("\(s.horse) · \(s.distanceText) · \(s.kind)").font(.caption).foregroundStyle(Avo.textDim).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("compare.session.\(s.id)")
                    }
                }
            }
            Divider().background(Avo.line)
            Text("ALINEAR SERIES POR").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim)
            Picker("Alinear series por", selection: $m.alignment) {
                Text("Tiempo relativo").tag(AlignmentMode.relativeTime)
                Text("Distancia").tag(AlignmentMode.distance)
            }
            .pickerStyle(.segmented)
            Button("Actualizar comparación") { model.refresh() }
                .buttonStyle(.avoSecondary)
                .frame(maxWidth: .infinity)
            Text("La comparación con el motor AVO está al final de los resultados.")
                .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CompareResults: View {
    @Environment(AppModel.self) private var app
    var model: CompareModel

    private var empty: String { model.computing ? "Calculando…" : "Marca entrenamientos para compararlos" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1) overlaid routes
            CompareMap(model: model).frame(height: 320)
            // 2) speed
            FeatureChartPanel(title: "Velocidad comparada (km/h)", minHeight: 240) {
                FeatureLineChart(series: model.speedSeries, axis: model.axis, includeZero: true, emptyText: empty)
            }
            // 3) validated acceleration
            FeatureChartPanel(title: "Aceleración longitudinal validada (m/s²)", minHeight: 220) {
                FeatureLineChart(series: model.accelSeries, axis: model.axis, includeZero: true, emptyText: empty)
            }
            // 4) girth IMU
            FeatureChartPanel(title: "IMU cincha → Desvíos laterales (m/s²)", minHeight: 220) {
                VStack(alignment: .leading, spacing: 6) {
                    FeatureLineChart(series: model.lateralSeries, axis: model.axis, includeZero: true,
                                     emptyText: model.computing ? "Calculando…" : "Sin datos de cincha (IMU)")
                        .frame(minHeight: 200)
                    Text("Aceleración horizontal perpendicular al eje longitudinal del caballo (eje X de la cincha, montaje no verificado), media por época. Positivo = hacia la izquierda.")
                        .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                    imuNotes
                }
            }
            FeatureChartPanel(title: "IMU cincha → Inclinaciones (°)", minHeight: 220) {
                VStack(alignment: .leading, spacing: 6) {
                    FeatureLineChart(series: model.tiltSeries, axis: model.axis, includeZero: true,
                                     emptyText: model.computing ? "Calculando…" : "Sin datos de cincha (IMU)")
                        .frame(minHeight: 200)
                    Text("Inclinación lateral (línea continua) y longitudinal (discontinua) de la cincha respecto a la mediana de cada entrenamiento.")
                        .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                    imuNotes
                }
            }
            // 5) engine cadence
            if !model.cadenceSeries.isEmpty {
                FeatureChartPanel(title: "Cadencia (motor, ciclos/min)", minHeight: 220) {
                    VStack(alignment: .leading, spacing: 6) {
                        FeatureLineChart(series: model.cadenceSeries, axis: model.axis, includeZero: false, emptyText: "Sin datos")
                            .frame(minHeight: 200)
                        if !model.cadenceMissing.isEmpty {
                            Text("Sin cadencia del motor: " + model.cadenceMissing.joined(separator: " · "))
                                .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            AvoCard(title: "Estadísticas comparativas") {
                FeatureTable(headers: ["Entrenamiento", "Fecha", "Distancia", "Duración", "V. media", "V. máx", "Acel. máx", "Cadencia"],
                             widths: [190, 120, 85, 75, 85, 85, 90, 80],
                             rows: model.rows.map { (r: CompareRow) -> [String] in
                                 [r.label, r.date, r.distance, r.duration, r.meanSpeed, r.maxSpeed, r.maxAccel, r.cadence]
                             },
                             colors: model.rows.map { (r: CompareRow) -> Color? in r.color },
                             emptyText: "Marca entrenamientos para compararlos")
            }
            CompareEngineCard(model: model)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var imuNotes: some View {
        if !model.imuMissing.isEmpty {
            Text("Sin datos de cincha (IMU): " + model.imuMissing.joined(separator: " · "))
                .font(.caption2).foregroundStyle(Avo.warn).fixedSize(horizontal: false, vertical: true)
        }
        if !model.imuSources.isEmpty {
            Text(model.imuSources.joined(separator: " · "))
                .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Engine comparison of the first two marked sessions (button, verdict and differences), at the bottom of the results.
private struct CompareEngineCard: View {
    var model: CompareModel

    var body: some View {
        AvoCard(title: "Comparación con el motor AVO") {
            Button {
                Task { await model.compareWithEngine() }
            } label: {
                HStack {
                    if model.engineBusy { ProgressView().tint(.white) }
                    Text("Comparar con el motor (2 sesiones)")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.avoPrimary)
            .disabled(model.engineBusy)
            .accessibilityIdentifier("compare.engine")
            Text(model.verdict).font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            let engineRows: [EngineDiffRow] = model.engineRows.filter { (r: EngineDiffRow) -> Bool in
                !GpsTerms.mentionsGnss(r.metrica)
            }
            if !engineRows.isEmpty {
                Divider().background(Avo.line)
                FeatureTable(headers: ["Métrica (motor)", "A", "B", "Diferencia", "Comparable", "Contexto"],
                             widths: [200, 90, 90, 90, 90, 280],
                             rows: engineRows.map { (r: EngineDiffRow) -> [String] in
                                 [r.metrica, r.a, r.b, r.diferencia, r.comparable, r.contexto]
                             })
            }
        }
    }
}

/// «Recorridos superpuestos»: every compared route in its comparison colour.
private struct CompareMap: View {
    @Environment(AppModel.self) private var app
    var model: CompareModel
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        ZStack(alignment: .topLeading) {
            if model.tracks.isEmpty {
                Avo.surface
                AvoNoData(text: "Marca entrenamientos para compararlos").frame(maxHeight: .infinity)
            } else {
                Map(position: $position) {
                    ForEach(model.tracks) { (t: CompareTrack) in
                        ForEach(0..<t.runs.count, id: \.self) { (k: Int) in
                            MapPolyline(coordinates: t.runs[k]).stroke(t.color, lineWidth: 3)
                        }
                    }
                }
                .mapStyle(app.settings.map == .vectorOffline ? MapStyle.standard : MapStyle.imagery)
            }
            Text("Recorridos superpuestos")
                .font(.callout.weight(.semibold)).foregroundStyle(Avo.text)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Avo.bg.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
                .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Avo.line, lineWidth: 1))
        .onChange(of: model.tracks.map { $0.id }) { position = .automatic }
    }
}
