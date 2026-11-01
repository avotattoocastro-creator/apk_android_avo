import SwiftUI

/// «Análisis» page = port of windows/AVO.Windows/Views/AnalysisView.xaml + SessionHeader.xaml: training data, GNSS
/// quality distribution and signal losses, cursor metrics with sparklines and playback, useful-window trim, engine
/// summary and the notes of the training (saved in paths.notes like Windows). The map itself is on the «Mapa» page.
struct AnalysisView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        GeometryReader { geo in
            let wide: Bool = geo.size.width >= 1000
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ShellSessionHeader()
                    if app.selected == nil {
                        AvoCard { AvoNoData(text: "Sin entrenamiento seleccionado") }
                    } else if wide {
                        HStack(alignment: .top, spacing: 12) {
                            AnalysisSessionCard().frame(width: 270)
                            VStack(spacing: 12) {
                                AnalysisPlaybackBar()
                                AnalysisGnssCard()
                                AnalysisLossesCard()
                            }
                            .frame(maxWidth: .infinity)
                            AnalysisTiles(columns: 1).frame(width: 250)
                        }
                        HStack(alignment: .top, spacing: 12) {
                            AnalysisEngineCard().frame(maxWidth: .infinity)
                            AnalysisNotesCard().frame(width: 380)
                        }
                    } else {
                        AnalysisPlaybackBar()
                        AnalysisTiles(columns: 2)
                        AnalysisSessionCard()
                        AnalysisGnssCard()
                        AnalysisLossesCard()
                        AnalysisEngineCard()
                        AnalysisNotesCard()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(Avo.bg)
    }
}

/// Left card «Entrenamiento» (session stats, girth, note about the trajectory).
private struct AnalysisSessionCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        AvoCard(title: "Entrenamiento") {
            ForEach(app.sessionStatsRows) { (r: ShellRow) in ShellKeyValue(key: r.key, value: r.value) }
            Divider().background(Avo.line).padding(.vertical, 4)
            Text("SENSORES").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim)
            ForEach(app.sensorStatusRows) { (r: ShellRow) in ShellKeyValue(key: r.key, value: r.value) }
            if let s = app.selected {
                Text("Cincha: \(s.girthText)").font(.caption).foregroundStyle(Avo.textDim).padding(.top, 4)
                if !s.identitySource.isEmpty {
                    Text(s.identitySource).font(.caption2).foregroundStyle(Avo.textDim)
                }
            }
            Text("La trayectoria es la del chaleco GNSS del jinete, no un punto anatómico del caballo.")
                .font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            Button {
                app.page = .map
            } label: {
                Label("Ver recorrido en el mapa", systemImage: "map")
            }
            .buttonStyle(.avoSecondary)
            .padding(.top, 4)
        }
    }
}

/// Playback bar: play/pause, cursor slider, time and speed (Windows AnalysisView playback bar).
private struct AnalysisPlaybackBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        let lo: Double = app.timelineStart
        let hi: Double = app.timelineEnd > lo ? app.timelineEnd : lo + 1
        let cursor: Binding<Double> = Binding<Double>(
            get: { app.cursorTime.isFinite ? min(max(app.cursorTime, lo), hi) : lo },
            set: { app.cursorTime = $0 })
        HStack(spacing: 14) {
            Button {
                app.togglePlay()
            } label: {
                Image(systemName: app.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(Avo.text)
                    .background(Avo.surface2, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Avo.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(app.selected == nil)
            .accessibilityLabel("Reproducir / pausar")
            Slider(value: cursor, in: lo...hi)
                .disabled(app.selected == nil)
            Text(app.playbackText).font(.system(.callout, design: .monospaced).weight(.semibold)).foregroundStyle(Avo.text)
                .lineLimit(1).fixedSize()
            Picker("Velocidad de reproducción", selection: $app.playbackSpeed) {
                ForEach(app.playbackSpeeds, id: \.self) { (v: Double) in
                    Text("\(Int(v))×").tag(v)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Avo.cardBrush, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Avo.line, lineWidth: 1))
    }
}

/// GNSS quality: distribution of solutions (whole file) and receiver statistics.
private struct AnalysisGnssCard: View {
    @Environment(AppModel.self) private var app

    private static let order: [GnssSolution] = [.rtkFix, .rtkFloat, .dgnss, .autonomous, .none]

    var body: some View {
        AvoCard(title: "Calidad GNSS / RTK", subtitle: "Porcentaje de épocas recibidas por tipo de solución") {
            let dist: [GnssSolution: Double] = app.gnssDistribution
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(AnalysisGnssCard.order, id: \.self) { (k: GnssSolution) in
                        let p: Double = dist[k] ?? 0
                        Rectangle().fill(Avo.solution(k))
                            .frame(width: max(0, geo.size.width * CGFloat(p / 100)))
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 10)
            .background(Avo.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            HStack(spacing: 12) {
                ForEach(AnalysisGnssCard.order, id: \.self) { (k: GnssSolution) in
                    HStack(spacing: 5) {
                        Circle().fill(Avo.solution(k)).frame(width: 8, height: 8)
                        Text(GnssQuality.name(k)).font(.caption2).foregroundStyle(Avo.textDim).lineLimit(1)
                    }
                }
            }
            Divider().background(Avo.line)
            ForEach(app.gnssStatsRows) { (r: ShellRow) in ShellKeyValue(key: r.key, value: r.value) }
        }
    }
}

/// Signal losses of the analysed part (intervals without a usable GNSS solution).
private struct AnalysisLossesCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        AvoCard(title: "Pérdidas de señal") {
            if let s = app.selected, !s.timeline.losses.isEmpty {
                let losses: [SignalLoss] = s.timeline.losses
                ForEach(0..<losses.count, id: \.self) { (i: Int) in
                    let l: SignalLoss = losses[i]
                    Button {
                        app.cursorTime = l.t0
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle().fill(Avo.bad).frame(width: 7, height: 7)
                            Text("\(TimeText.clock(l.t0)) – \(TimeText.clock(l.t1))").font(.footnote.weight(.semibold)).foregroundStyle(Avo.text)
                            Text(TimeText.num(l.durationS, "0.0", " s")).font(.footnote).foregroundStyle(Avo.textDim)
                            Text(l.reason).font(.caption).foregroundStyle(Avo.textDim).lineLimit(2)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } else {
                AvoNoData(text: "Sin pérdidas de señal GNSS en la parte analizada")
            }
        }
    }
}

/// Right column: metric tiles at the cursor with sparklines (speed, acceleration, altitude, cadence).
private struct AnalysisTiles: View {
    @Environment(AppModel.self) private var app
    var columns: Int

    var body: some View {
        let grid: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: max(columns, 1))
        let s: SessionItem? = app.selected
        let tl: SessionTimeline? = s?.timeline
        let speed: [Double] = tl.map { ShellSparkline.decimate($0.speedFiltered.map { $0 * 3.6 }) } ?? []
        let accel: [Double] = tl.map { t in
            ShellSparkline.decimate((0..<t.count).map { (i: Int) -> Double in SegmentAnalyzer.accelValid(t, i) ? t.accelLong[i] : .nan })
        } ?? []
        let alt: [Double] = tl.map { ShellSparkline.decimate($0.altitudeMsl) } ?? []
        let engine: EquineAnalysis? = s?.engine
        let cadence: [Double] = AnalysisTiles.cadenceSeries(engine)
        let frac: Double? = cursorFraction()
        return LazyVGrid(columns: grid, spacing: 8) {
            tile("Velocidad (km/h)", app.cursorSpeed, "Filtrada en el cursor", speed, Avo.blue, frac)
            tile("Aceleración (m/s²)", app.cursorAccel, "Longitudinal validada", accel, Avo.red, frac)
            tile("Altitud (m)", app.cursorAltitude, "GNSS sobre el nivel medio del mar", alt, Avo.ok, frac)
            tile("Cadencia (ciclos/min)", app.cursorCadence, "Cincha · motor AVO (sin datos = —)", cadence, Avo.cyan, nil)
        }
    }

    /// Cadence (cycles/min) of the first girth IMU, as Windows CadenceAt uses.
    static func cadenceSeries(_ e: EquineAnalysis?) -> [Double] {
        guard let e = e, e.hasImu, let imu = e.girthImu.min() else { return [] }
        let n: Int = min(e.girthImu.count, e.girthCadenceHz.count)
        var out: [Double] = []
        for k in 0..<n where e.girthImu[k] == imu { out.append(e.girthCadenceHz[k] * 60) }
        return ShellSparkline.decimate(out)
    }

    private func cursorFraction() -> Double? {
        let lo: Double = app.timelineStart
        let hi: Double = app.timelineEnd
        guard app.selected != nil, app.cursorTime.isFinite, hi > lo else { return nil }
        return min(max((app.cursorTime - lo) / (hi - lo), 0), 1)
    }

    private func tile(_ label: String, _ value: String, _ caption: String, _ values: [Double], _ color: Color, _ frac: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim)
            Text(value).font(.system(size: 26, weight: .semibold, design: .rounded)).foregroundStyle(Avo.text)
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(caption).font(.caption2).foregroundStyle(Avo.textDim).lineLimit(2)
            ZStack {
                ShellSparkline(values: values, color: color)
                if let f = frac {
                    GeometryReader { geo in
                        Rectangle().fill(Avo.text.opacity(0.5)).frame(width: 1)
                            .position(x: geo.size.width * CGFloat(f), y: geo.size.height / 2)
                            .frame(height: geo.size.height)
                    }
                }
            }
            .frame(height: 44)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Avo.cardBrush, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Avo.line, lineWidth: 1))
    }
}

/// Summary of the AVO Equine Intelligence Engine result for the session.
private struct AnalysisEngineCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        AvoCard(title: "Motor AVO Equine Intelligence", subtitle: app.engineInfo) {
            if let s = app.selected {
                ShellKeyValue(key: "Estado", value: s.engineState)
                if let e = s.engine {
                    ShellKeyValue(key: "Motor", value: e.engine)
                    if !e.mode.isEmpty { ShellKeyValue(key: "Modo", value: e.mode) }
                    ShellKeyValue(key: "Datos de cincha", value: e.hasImu ? "Sí (IMU de la cincha)" : "No: solo GNSS, sin aires ni regularidad")
                    if !e.classifier.isEmpty { ShellKeyValue(key: "Clasificador de aires", value: e.classifier) }
                    if !e.fusionSummary.isEmpty {
                        Text(e.fusionSummary).font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(0..<e.warnings.count, id: \.self) { (i: Int) in
                        Text(e.warnings[i]).font(.caption).foregroundStyle(Avo.warn).fixedSize(horizontal: false, vertical: true)
                    }
                    Text("POR AIRE").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim).padding(.top, 4)
                    ShellTable(columns: [
                        ShellTable.Column(title: "Aire", width: 110), ShellTable.Column(title: "Tramos", width: 60),
                        ShellTable.Column(title: "Duración", width: 80), ShellTable.Column(title: "Fracción", width: 70),
                        ShellTable.Column(title: "Distancia", width: 85), ShellTable.Column(title: "V. media", width: 85),
                        ShellTable.Column(title: "Cadencia", width: 85), ShellTable.Column(title: "Tranco", width: 70),
                    ], rows: e.perGait.map { (g: EngineGaitRow) -> [String] in
                        [g.aire, "\(g.tramos)", g.duracion, g.fraccionTiempo, g.distancia, g.velocidadMedia, g.cadencia, g.tranco]
                    }, empty: e.hasImu ? "Sin datos" : "Sin datos de cincha: el motor no clasifica aires")
                    Button("Ver resultados detallados del motor") { app.page = .engine }
                        .buttonStyle(.avoSecondary)
                } else {
                    AvoNoData(text: "Sin resultado del motor para este entrenamiento")
                }
            } else {
                AvoNoData()
            }
        }
    }
}

/// Notes of the training (Windows SessionNotes: saved to notas/<id>.txt on every change).
private struct AnalysisNotesCard: View {
    @Environment(AppModel.self) private var app
    @State private var text: String = ""
    @State private var loadedFor: String = ""

    var body: some View {
        AvoCard(title: "Notas del entrenamiento", subtitle: "Se guardan en este iPad, aparte del archivo original") {
            TextEditor(text: $text)
                .font(.callout)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 160)
                .background(Avo.surface2, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Avo.line, lineWidth: 1))
                .disabled(app.selected == nil)
        }
        .onAppear { load() }
        .onChange(of: app.selected?.id ?? "") { _, _ in load() }
        .onChange(of: text) { _, newValue in
            guard let s = app.selected, s.id == loadedFor, newValue != s.notes else { return }
            app.saveSessionNotes(s, newValue)
        }
    }

    private func load() {
        loadedFor = app.selected?.id ?? ""
        text = app.selected?.notes ?? ""
    }
}
