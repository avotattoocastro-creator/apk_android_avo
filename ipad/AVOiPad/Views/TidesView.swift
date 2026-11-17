import SwiftUI

/// Tides and conditions (Windows Views/TidesView.xaml). Prediction / model / measurement are always labelled; missing data is
/// shown as «Sin datos». Values of a reference port are never presented as measured at the beach.
struct TidesView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        let model: EnvironmentModel = app.environment
        ScrollView {
            // no session header (trainer's sketch 14/11/2026: the training bar already shows it)
            VStack(alignment: .leading, spacing: 12) {
                if hSize == .compact {
                    TidesConditionsCard(model: model)
                    TidesChartCard(model: model)
                    TidesSourceCards(model: model)
                    TidesOriginCard(model: model)
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        TidesConditionsCard(model: model).frame(width: 440)
                        TidesChartCard(model: model)
                    }
                    // the three cards with the same height (trainer's sketch 14/11/2026: «misma altura»)
                    HStack(alignment: .top, spacing: 12) {
                        TidesSourceCards(model: model).frame(maxHeight: .infinity)
                        TidesOriginCard(model: model).frame(width: 330).frame(maxHeight: .infinity)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                TidesWeatherHours(model: model)
            }
            .padding(16)
        }
        .background(Avo.bg)
        .onAppear { model.pageShown() }
    }
}

/// «Condiciones de la sesión»: six headline tiles.
private struct TidesConditionsCard: View {
    var model: EnvironmentModel
    var body: some View {
        AvoCard(title: "Condiciones de la sesión") {
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    AvoMetric(label: "Marea (predicción)", value: model.tideTrend,
                              caption: model.selectedPort.map { "Puerto de referencia: \($0.name)" } ?? "Sin puerto")
                    AvoMetric(label: "Altura de marea", value: model.tideHeadline, caption: "Sobre el cero hidrográfico")
                }
                GridRow {
                    AvoMetric(label: "Viento (modelo)", value: model.windHeadline, caption: "Open-Meteo")
                    AvoMetric(label: "Temperatura (modelo)", value: model.tempHeadline, caption: "Open-Meteo")
                }
                GridRow {
                    AvoMetric(label: "Presión (modelo)", value: model.pressureHeadline, caption: "Nivel del mar")
                    AvoMetric(label: "Oleaje (modelo)", value: model.waveHeadline, caption: "Altura significativa")
                }
                GridRow {
                    AvoMetric(label: "Coeficiente de marea", value: model.coefficientHeadline, caption: "Aproximado (70 · amplitud / amplitud media)",
                              accent: Avo.cyan)
                        .gridCellColumns(2)
                }
            }
        }
    }
}

private struct TidesChartCard: View {
    var model: EnvironmentModel
    var body: some View {
        FeatureChartPanel(title: "Gráfica de mareas del día (Europe/Madrid) · línea roja = hora del entrenamiento", minHeight: 280) {
            VStack(alignment: .leading, spacing: 6) {
                if model.loading {
                    HStack(spacing: 8) { ProgressView(); Text("Consultando…").font(.caption).foregroundStyle(Avo.textDim) }
                }
                FeatureLineChart(series: model.tideSeries, axis: .hourOfDay, xMin: model.tideXMin, xMax: model.tideXMax,
                                 markerX: model.tideMarker, bands: model.trainingBand, bandOpacity: 0.22,
                                 emptyText: "Sin datos de marea (consulta en línea desactivada, sin conexión o sin fecha)")
                if !model.trainingBand.isEmpty {
                    FeatureLegend(items: [(name: "Marea (predicción)", color: Avo.blue), (name: "Intervalo del entrenamiento", color: Avo.red)])
                }
            }
        }
    }
}

/// «Marea · fuente y valores» and «Meteorología y oleaje · fuente y valores».
private struct TidesSourceCards: View {
    @Environment(\.horizontalSizeClass) private var hSize
    var model: EnvironmentModel

    var body: some View {
        if hSize == .compact {
            VStack(spacing: 12) { tideCard; weatherCard }
        } else {
            HStack(alignment: .top, spacing: 12) {
                tideCard.frame(maxHeight: .infinity)
                weatherCard.frame(maxHeight: .infinity)
            }
        }
    }

    private var tideCard: some View {
        AvoCard(title: "Marea · fuente y valores", fill: hSize != .compact) {
            if model.tideRows.isEmpty {
                AvoNoData()
            } else {
                VStack(spacing: 0) { ForEach(model.tideRows) { (r: FeatureKV) in FeatureKeyValue(key: r.key, value: r.value) } }
            }
            Text("PLEAMARES Y BAJAMARES DEL DÍA").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim).padding(.top, 8)
            if model.tideEvents.isEmpty {
                Text("Sin datos").font(.caption).foregroundStyle(Avo.textDim)
            } else {
                VStack(spacing: 0) { ForEach(model.tideEvents) { (r: FeatureKV) in FeatureKeyValue(key: r.key, value: r.value) } }
            }
        }
    }

    private var weatherCard: some View {
        AvoCard(title: "Meteorología y oleaje · fuente y valores", fill: hSize != .compact) {
            if model.weatherRows.isEmpty {
                AvoNoData()
            } else {
                VStack(spacing: 0) { ForEach(model.weatherRows) { (r: FeatureKV) in FeatureKeyValue(key: r.key, value: r.value) } }
            }
        }
    }
}

/// «Origen de los datos»: training place, reference port, online switch, refresh, status and the data-origin note.
private struct TidesOriginCard: View {
    @Environment(AppModel.self) private var app
    var model: EnvironmentModel
    @State private var editingPlace: Bool = false

    var body: some View {
        @Bindable var m = model
        AvoCard(title: "Origen de los datos", fill: true) {
            Text("ZONA DE ENTRENAMIENTO").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.settings.placeName).font(.callout).foregroundStyle(Avo.text)
                    Text("\(DotNetFormat.custom(app.settings.placeLatitude, "0.0000", spanish: true)), \(DotNetFormat.custom(app.settings.placeLongitude, "0.0000", spanish: true))")
                        .font(.caption2.monospacedDigit()).foregroundStyle(Avo.textDim)
                }
                Spacer()
                Button(editingPlace ? "Cerrar" : "Editar") { editingPlace.toggle() }.buttonStyle(.avoSecondary)
            }
            if editingPlace {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Nombre de la zona", text: $m.placeName).textFieldStyle(.roundedBorder)
                    HStack {
                        TextField("Latitud", value: $m.placeLatitude, format: .number.precision(.fractionLength(4)))
                            .keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder)
                        TextField("Longitud", value: $m.placeLongitude, format: .number.precision(.fractionLength(4)))
                            .keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Button("Guardar zona") { model.savePlace(); editingPlace = false }.buttonStyle(.avoPrimary)
                        Button("Playa del Regatón") { model.resetPlace(); editingPlace = false }.buttonStyle(.avoSecondary)
                    }
                    Text("Se usa cuando la sesión no tiene posición; los puertos se ordenan por distancia a la sesión.")
                        .font(.caption2).foregroundStyle(Avo.textDim)
                }
            }
            Text("PUERTO DE REFERENCIA (IHM)").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim).padding(.top, 6)
            if model.ports.isEmpty {
                Text("Sin datos").font(.caption).foregroundStyle(Avo.textDim)
            } else {
                Picker("Puerto de referencia (IHM)", selection: Binding<String>(
                    get: { model.selectedPortId ?? "" },
                    set: { (v: String) in if !v.isEmpty { model.choosePort(v) } })) {
                    ForEach(model.ports, id: \.id) { (p: TidePort) in
                        Text("\(p.name) · \(DotNetFormat.custom(p.distanceKmTo(app.settings.placeLatitude, app.settings.placeLongitude), "0", spanish: true)) km").tag(p.id)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("tides.port")
            }
            Toggle("Consultar fuentes en línea (IHM, Open-Meteo)", isOn: $m.onlineEnvironment)
                .tint(Avo.red)
                .accessibilityIdentifier("tides.online")
            Button {
                Task { await model.load(force: true) }
            } label: {
                Text("Actualizar datos de entorno").frame(maxWidth: .infinity)
            }
            .buttonStyle(.avoPrimary)
            .disabled(model.loading)
            // the explanatory texts are gone (trainer's sketch 14/11/2026); the status only shows while loading or on a problem
            if model.loading || model.status.hasPrefix("Parcial") || model.status.hasPrefix("Consulta en línea desactivada") {
                Text(model.status).font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Hourly model table of the training day; hours overlapping the training are highlighted.
private struct TidesWeatherHours: View {
    var model: EnvironmentModel
    var body: some View {
        AvoCard(title: "Meteorología por horas (modelo Open-Meteo)", subtitle: "Horas en Europe/Madrid · resaltadas las del entrenamiento") {
            FeatureTable(headers: ["Hora", "Temperatura", "Viento", "Rachas", "Dirección", "Presión", "Humedad", "Oleaje", "Periodo"],
                         widths: [55, 90, 80, 80, 90, 85, 75, 70, 65],
                         rows: model.weatherHours.map { (h: WeatherHourRow) -> [String] in
                             [h.hour, h.temperature, h.wind, h.gust, h.direction, h.pressure, h.humidity, h.wave, h.period]
                         },
                         highlighted: Set(model.weatherHours.filter { $0.inTraining }.map { $0.id }))
        }
    }
}
