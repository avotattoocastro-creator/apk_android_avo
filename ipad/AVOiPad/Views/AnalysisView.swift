import SwiftUI
import Charts

/// «Análisis» page = port of windows/AVO.Windows/Views/AnalysisView.xaml + SessionHeader.xaml, focused on the HORSE:
/// training data, cursor metrics with sparklines and playback, useful-window trim, «Análisis del caballo» (gaits, speed
/// zones, effort, validated accelerations, curves, gait quality from the girth), engine summary and notes. The GNSS/RTK
/// quality lives only on the «GPS» page; the map itself is on the «Mapa» page.
struct AnalysisView: View {
    @Environment(AppModel.self) private var app
    @State private var horse: HorseSummary? = nil

    var body: some View {
        GeometryReader { geo in
            let wide: Bool = geo.size.width >= 1000
            ScrollView {
                // «Resumen» in the Equimetre style (trainer 14/11/2026: «Así quiero resumen»): head of the training,
                // then «Parámetros clave» (the «Datos clave» figures) as a folding section, then the horse analysis.
                // The map with playback is now its own tab («Mapa»).
                VStack(alignment: .leading, spacing: 14) {
                    if app.selected == nil {
                        AvoCard { AvoNoData(text: "Sin entrenamiento seleccionado") }
                    } else {
                        SummaryHero()
                        SummaryFold(title: "Parámetros clave") { KeyDataView(embedded: true) }
                        SummaryFold(title: "Análisis del caballo") { AnalysisHorseSection(summary: horse, wide: wide) }
                        if wide {
                            // same height (trainer's sketch 14/11/2026: «misma altura»)
                            HStack(alignment: .top, spacing: 12) {
                                AnalysisEngineCard(fill: true).frame(maxWidth: .infinity, maxHeight: .infinity)
                                TrainingRatingCard(fill: true).frame(width: 420).frame(maxHeight: .infinity)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        } else {
                            AnalysisEngineCard()
                            TrainingRatingCard()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(Avo.bg)
        .task(id: horseKey) { await computeHorse() }
    }

    /// Changes with the session, its trim and the engine result.
    private var horseKey: String {
        guard let s = app.selected else { return "" }
        return "\(s.id)|\(s.windowText)|\(s.engineState)|\(s.engine == nil ? 0 : 1)"
    }

    @MainActor
    private func computeHorse() async {
        let key: String = horseKey
        guard let s = app.selected else { horse = nil; return }
        if horse?.key != key { horse = nil }
        let tl: SessionTimeline = s.timeline
        let engine: EquineAnalysis? = s.engine
        let off: Double = s.engineOffsetS
        let r: HorseSummary = await Task.detached(priority: .userInitiated) { () -> HorseSummary in
            HorseSummary.compute(key: key, timeline: tl, engine: engine, engineOffsetS: off)
        }.value
        if Task.isCancelled { return }
        if horseKey == key { horse = r }
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
            Button {
                app.page = .analysis
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

/// Right column: metric tiles at the cursor with sparklines (speed, acceleration, effort, cadence).
private struct AnalysisTiles: View {
    @Environment(AppModel.self) private var app
    var columns: Int
    var horse: HorseSummary?

    var body: some View {
        let grid: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: max(columns, 1))
        let s: SessionItem? = app.selected
        let tl: SessionTimeline? = s?.timeline
        let speed: [Double] = tl.map { ShellSparkline.decimate($0.speedFiltered.map { $0 * 3.6 }) } ?? []
        let accel: [Double] = tl.map { t in
            ShellSparkline.decimate((0..<t.count).map { (i: Int) -> Double in SegmentAnalyzer.accelValid(t, i) ? t.accelLong[i] : .nan })
        } ?? []
        let dist: [Double] = horse?.distanceSparkline ?? []
        let engine: EquineAnalysis? = s?.engine
        let cadence: [Double] = AnalysisTiles.cadenceSeries(engine)
        let frac: Double? = cursorFraction()
        return LazyVGrid(columns: grid, spacing: 8) {
            tile("Velocidad (km/h)", app.cursorSpeed, "Filtrada en el cursor", speed, Avo.blue, frac)
            tile("Aceleración (m/s²)", app.cursorAccel, "Longitudinal validada", accel, Avo.red, frac)
            tile("Esfuerzo · tiempo en movimiento", horse.map { TimeText.clock($0.movingS) } ?? "—",
                 horse.map { "Parado \(TimeText.clock($0.stoppedS)) · \($0.efforts.count) esfuerzos > 25 km/h · distancia acumulada" }
                    ?? "Calculando…", dist, Avo.ok, frac)
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

/// Summary of the AVO Performance Equine result for the session.
private struct AnalysisEngineCard: View {
    @Environment(AppModel.self) private var app
    var fill: Bool = false

    var body: some View {
        AvoCard(title: "Motor AVO Performance Equine", subtitle: app.engineInfo, fill: fill) {
            if let s = app.selected {
                ShellKeyValue(key: "Estado", value: s.engineState)
                if let e = s.engine {
                    ShellKeyValue(key: "Motor", value: e.engine)
                    if !e.mode.isEmpty { ShellKeyValue(key: "Modo", value: e.mode) }
                    ShellKeyValue(key: "Datos de cincha", value: e.hasImu ? "Sí (IMU de la cincha)" : "No: sin aires ni regularidad")
                    if !e.classifier.isEmpty { ShellKeyValue(key: "Clasificador de aires", value: e.classifier) }
                    if !e.fusionSummary.isEmpty {
                        Text(e.fusionSummary).font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                    }
                    let warnings: [String] = e.warnings.filter { (w: String) -> Bool in !GpsTerms.mentionsGnss(w) }
                    ForEach(0..<warnings.count, id: \.self) { (i: Int) in
                        Text(warnings[i]).font(.caption).foregroundStyle(Avo.warn).fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Los aires por tiempo, distancia y cadencia están en «Análisis del caballo».")
                        .font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
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

// MARK: - Análisis del caballo

/// Share of time of one gait (engine performance segments clipped to the analysed part).
struct HorseGaitShare: Identifiable {
    let id: String
    let name: String
    let seconds: Double
    let fraction: Double
    let color: Color
}

/// Time and distance inside one band of the filtered speed.
struct HorseSpeedZone: Identifiable {
    let id: Int
    let range: String
    let gaitHint: String
    let seconds: Double
    let meters: Double
    let color: Color
}

/// One effort: filtered speed above 25 km/h for more than 10 s without a gap.
struct HorseEffortBout: Identifiable {
    let id: Int
    let t0: Double
    let t1: Double
    let maxKmh: Double
    let meters: Double
    /// Time since the end of the previous effort (NaN for the first one).
    let recoveryBeforeS: Double
    var durationS: Double { t1 - t0 }
}

/// Horse-centred summary of the analysed part, built only from measured data (timeline + engine). Never invents values:
/// missing quantities stay NaN / empty and are shown as «Sin datos».
struct HorseSummary {
    var key: String = ""
    var totalDistanceM: Double = 0
    var movingS: Double = 0
    var stoppedS: Double = 0
    var zones: [HorseSpeedZone] = []
    var zoneTotalS: Double = 0
    var efforts: [HorseEffortBout] = []
    var meanRecoveryS: Double = .nan
    var maxAccel: Double = .nan
    var maxDecel: Double = .nan
    var accelEvents: Int = 0
    var brakeEvents: Int = 0
    var validAccelFraction: Double = 0
    var hasEngine: Bool = false
    var hasImu: Bool = false
    var gaits: [HorseGaitShare] = []
    var curves: Int = 0
    var curvesLeft: Int = 0
    var curvesRight: Int = 0
    var maxLateral: Double = .nan
    var distanceSparkline: [Double] = []

    static let movingThresholdKmh: Double = 1
    static let effortThresholdKmh: Double = 25
    static let effortMinS: Double = 10
    static let accelThreshold: Double = 1.5
    /// Speed bands (km/h) with the approximate gait they usually correspond to (speed bands, not engine gaits).
    static let zoneEdges: [Double] = [7, 15, 25, 35]
    static let zoneRanges: [String] = ["< 7 km/h", "7–15 km/h", "15–25 km/h", "25–35 km/h", "> 35 km/h"]
    static let zoneHints: [String] = ["paso (aprox.)", "trote (aprox.)", "galope lento (aprox.)", "galope (aprox.)", "sprint (aprox.)"]
    static let zoneColors: [Color] = [Color(hex: 0x3D9BFF), Color(hex: 0x35D0E8), Color(hex: 0xFFC42C), Color(hex: 0xFF7A2C), Color(hex: 0xED122A)]
    static let gaitOrder: [String] = ["STOPPED", "WALK", "TROT", "CANTER_GALLOP", "TRANSITION", "UNKNOWN", "INSUFFICIENT_DATA"]

    static func gaitColor(_ code: String) -> Color {
        let c: Int
        switch code {
        case "STOPPED": c = 0
        case "WALK": c = 1
        case "TROT": c = 2
        case "CANTER_GALLOP": c = 3
        default: c = -1
        }
        let rgb: AvoRGB = SpeedScale.gait(c)
        return Color(.sRGB, red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255, opacity: 1)
    }

    static func zoneIndex(_ kmh: Double) -> Int {
        var z: Int = 0
        for e in zoneEdges where kmh >= e { z += 1 }
        return z
    }

    /// First number of an engine text such as «0,84 ± 0,12 m/s²» (nil when it is «—»).
    static func leadingNumber(_ text: String) -> Double? {
        let head: String = text.components(separatedBy: " ± ").first ?? ""
        let clean: String = head.replacingOccurrences(of: "\u{00A0}", with: "").replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard let v = Double(clean), v.isFinite else { return nil }
        return v
    }

    static func compute(key: String, timeline tl: SessionTimeline, engine: EquineAnalysis?, engineOffsetS off: Double) -> HorseSummary {
        var r = HorseSummary()
        r.key = key
        let n: Int = tl.count
        r.totalDistanceM = tl.totalDistanceM
        var v: [Double] = [Double](repeating: .nan, count: n)
        for i in 0..<n { v[i] = tl.speedFiltered[i] * 3.6 }

        // speed zones, moving / stopped time (gaps without data are left out)
        var zs: [Double] = [Double](repeating: 0, count: zoneRanges.count)
        var zm: [Double] = [Double](repeating: 0, count: zoneRanges.count)
        if n > 1 {
            for i in 1..<n {
                if tl.breakBefore[i] { continue }
                let dt: Double = tl.t[i] - tl.t[i - 1]
                if !(dt > 0) { continue }
                let a: Double = v[i - 1]
                let b: Double = v[i]
                let vm: Double
                if a.isFinite && b.isFinite { vm = (a + b) / 2 } else if b.isFinite { vm = b } else if a.isFinite { vm = a } else { continue }
                let dd: Double = tl.distance[i] - tl.distance[i - 1]
                let z: Int = zoneIndex(vm)
                zs[z] += dt
                zm[z] += dd.isFinite ? max(dd, 0) : 0
                if vm < movingThresholdKmh { r.stoppedS += dt } else { r.movingS += dt }
            }
        }
        var zones: [HorseSpeedZone] = []
        var total: Double = 0
        for k in 0..<zoneRanges.count {
            total += zs[k]
            zones.append(HorseSpeedZone(id: k, range: zoneRanges[k], gaitHint: zoneHints[k], seconds: zs[k], meters: zm[k], color: zoneColors[k]))
        }
        r.zones = zones
        r.zoneTotalS = total

        // efforts: > 25 km/h for more than 10 s, never across a gap
        var bouts: [HorseEffortBout] = []
        var start: Int = -1
        var last: Int = -1
        var vmax: Double = 0
        func close() {
            if start < 0 || last < start { return }
            let dur: Double = tl.t[last] - tl.t[start]
            if dur > effortMinS {
                let prevEnd: Double = bouts.last?.t1 ?? .nan
                let rec: Double = prevEnd.isFinite ? tl.t[start] - prevEnd : .nan
                bouts.append(HorseEffortBout(id: bouts.count + 1, t0: tl.t[start], t1: tl.t[last], maxKmh: vmax,
                                             meters: max(0, tl.distance[last] - tl.distance[start]), recoveryBeforeS: rec))
            }
        }
        for i in 0..<n {
            let above: Bool = v[i].isFinite && v[i] > effortThresholdKmh
            if start >= 0 && (tl.breakBefore[i] || !above) {
                close()
                start = -1
            }
            if above {
                if start < 0 { start = i; vmax = v[i] }
                last = i
                vmax = max(vmax, v[i])
            }
        }
        if start >= 0 { close() }
        r.efforts = bouts
        let recs: [Double] = bouts.map { $0.recoveryBeforeS }.filter { $0.isFinite }
        if !recs.isEmpty { r.meanRecoveryS = recs.reduce(0, +) / Double(recs.count) }

        // validated accelerations / braking (same rule as the segments: SegmentAnalyzer.accelValid)
        var valid: Int = 0
        var inAccel: Bool = false
        var inBrake: Bool = false
        var amax: Double = -Double.infinity
        var dmin: Double = Double.infinity
        for i in 0..<n {
            let ok: Bool = SegmentAnalyzer.accelValid(tl, i)
            let a: Double = ok ? tl.accelLong[i] : .nan
            if ok {
                valid += 1
                if a > amax { amax = a }
                if a < dmin { dmin = a }
            }
            let up: Bool = ok && a > accelThreshold
            let down: Bool = ok && a < -accelThreshold
            if up && !inAccel { r.accelEvents += 1 }
            if down && !inBrake { r.brakeEvents += 1 }
            inAccel = up
            inBrake = down
        }
        if amax.isFinite && amax > 0 { r.maxAccel = amax }
        if dmin.isFinite && dmin < 0 { r.maxDecel = dmin }
        r.validAccelFraction = n > 0 ? Double(valid) / Double(n) : 0

        // engine: gaits (only with girth data) and curves
        if let e = engine {
            r.hasEngine = true
            r.hasImu = e.hasImu
            let lo: Double = n > 1 ? tl.t[0] : -Double.infinity
            let hi: Double = n > 1 ? tl.t[n - 1] : Double.infinity
            if e.hasImu {
                var secs: [String: Double] = [:]
                for seg in e.segments {
                    let a: Double = max(seg.t0 - off, lo)
                    let b: Double = min(seg.t1 - off, hi)
                    if !(b > a) { continue }
                    let code: String = seg.gaitCode.isEmpty ? "UNKNOWN" : seg.gaitCode
                    secs[code, default: 0] += b - a
                }
                var sum: Double = 0
                for (_, x) in secs { sum += x }
                var codes: [String] = gaitOrder.filter { secs[$0] != nil }
                for c in secs.keys.sorted() where !codes.contains(c) { codes.append(c) }
                var shares: [HorseGaitShare] = []
                for c in codes {
                    let x: Double = secs[c] ?? 0
                    shares.append(HorseGaitShare(id: c, name: EquineAnalysis.gaitText(c), seconds: x,
                                                 fraction: sum > 0 ? x / sum : 0, color: gaitColor(c)))
                }
                r.gaits = shares
            }
            var lat: Double = -Double.infinity
            for c in e.curves {
                let tc: Double = c.t0 - off
                if tc.isFinite && (tc < lo || tc > hi) { continue }
                r.curves += 1
                let d: String = c.direccion.uppercased()
                if d.hasPrefix("IZQ") { r.curvesLeft += 1 } else if d.hasPrefix("DER") { r.curvesRight += 1 }
                if let x = leadingNumber(c.lateralEstimada) { lat = max(lat, abs(x)) }
            }
            if lat.isFinite { r.maxLateral = lat }
        }
        r.distanceSparkline = ShellSparkline.decimate(tl.distance.map { $0 / 1000 })
        return r
    }
}

/// «Análisis del caballo»: gaits, speed zones, effort, validated accelerations, curves and gait quality from the girth.
private struct AnalysisHorseSection: View {
    @Environment(AppModel.self) private var app
    let summary: HorseSummary?
    let wide: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("ANÁLISIS DEL CABALLO").font(.callout.weight(.bold)).tracking(1).foregroundStyle(Avo.text)
                Text("Solo datos medidos · «Sin datos» cuando falta la fuente").font(.caption2).foregroundStyle(Avo.textDim)
                Spacer(minLength: 0)
            }
            if let h = summary {
                HorseGaitCard(summary: h)
                if wide {
                    // three equal columns across the whole page
                    // trainer's sketch 14/11/2026 («misma medida alto»): the three columns end at the same height
                    HStack(alignment: .top, spacing: 12) {
                        HorseZonesCard(summary: h, fill: true).frame(maxWidth: .infinity, maxHeight: .infinity)
                        HorseEffortCard(summary: h, fill: true).frame(maxWidth: .infinity, maxHeight: .infinity)
                        VStack(spacing: 12) {
                            HorseAccelCard(summary: h)
                            HorseCurvesCard(summary: h, fill: true).frame(maxHeight: .infinity)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    HorseZonesCard(summary: h)
                    HorseEffortCard(summary: h)
                    HorseAccelCard(summary: h)
                    HorseCurvesCard(summary: h)
                }
                HorseGirthCard(summary: h)
            } else {
                AvoCard {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Calculando el análisis del caballo…").font(.footnote).foregroundStyle(Avo.textDim)
                    }
                    .frame(maxWidth: .infinity, minHeight: 60)
                }
            }
        }
    }
}

/// Compact value tile used inside the horse cards.
private struct HorseTile: View {
    var label: String
    var value: String
    var caption: String? = nil
    var accent: Color = Avo.text

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(.caption2.weight(.semibold)).tracking(0.5).foregroundStyle(Avo.textDim)
                .lineLimit(2).minimumScaleFactor(0.8)
            Text(value).font(.system(size: 21, weight: .semibold, design: .rounded)).foregroundStyle(accent)
                .lineLimit(1).minimumScaleFactor(0.5)
            if let c = caption {
                Text(c).font(.caption2).foregroundStyle(Avo.textDim).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Avo.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Avo.line, lineWidth: 1))
    }
}

private enum HorseFmt {
    static func num(_ v: Double?, _ fmt: String, _ unit: String = "") -> String { TimeText.num(v, fmt, unit, missing: "Sin datos") }
    static func pct(_ part: Double, _ total: Double) -> String {
        total > 0 ? DotNetFormat.custom(100 * part / total, "0", spanish: true) + " %" : "Sin datos"
    }
    static func km(_ m: Double) -> String { DotNetFormat.custom(m / 1000, "0.00", spanish: true) + " km" }
    /// Biomech headlines use «—» for missing values.
    static func headline(_ s: String, _ unit: String = "") -> String {
        s == "—" || s.isEmpty ? "Sin datos" : s + unit
    }
}

private let horseGrid: [GridItem] = [GridItem(.adaptive(minimum: 130), spacing: 8, alignment: .top)]

/// Aires: stacked bar of the time per gait + engine table per gait.
private struct HorseGaitCard: View {
    @Environment(AppModel.self) private var app
    let summary: HorseSummary

    var body: some View {
        let h: HorseSummary = summary
        AvoCard(title: "Aires", subtitle: "Clasificación del motor AVO con la cincha · tiempo de cada aire en la parte analizada") {
            if !h.hasEngine {
                AvoNoData(text: "Sin resultado del motor AVO para este entrenamiento")
            } else if !h.hasImu {
                AvoNoData(text: "Sin datos de cincha: el motor no clasifica aires (paso, trote, galope)")
            } else if h.gaits.isEmpty {
                AvoNoData(text: "El motor no ha encontrado tramos de marcha en la parte analizada")
            } else {
                GeometryReader { geo in
                    HStack(spacing: 1) {
                        ForEach(h.gaits) { (g: HorseGaitShare) in
                            Rectangle().fill(g.color)
                                .frame(width: max(0, (geo.size.width - CGFloat(max(h.gaits.count - 1, 0))) * CGFloat(g.fraction)))
                        }
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: 18)
                .background(Avo.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 6) {
                    ForEach(h.gaits) { (g: HorseGaitShare) in
                        HStack(spacing: 6) {
                            Circle().fill(g.color).frame(width: 9, height: 9)
                            Text(g.name).font(.caption).foregroundStyle(Avo.textDim).lineLimit(1)
                            Text("\(DotNetFormat.custom(g.fraction * 100, "0", spanish: true)) % · \(TimeText.clock(g.seconds))")
                                .font(.caption.weight(.semibold)).foregroundStyle(Avo.text).lineLimit(1)
                        }
                    }
                }
                if let e = app.selected?.engine, !e.perGait.isEmpty {
                    ShellTable(columns: [
                        ShellTable.Column(title: "Aire", width: 110), ShellTable.Column(title: "Tiempo", width: 75),
                        ShellTable.Column(title: "Fracción", width: 70), ShellTable.Column(title: "Distancia", width: 85),
                        ShellTable.Column(title: "V. media", width: 85), ShellTable.Column(title: "Cadencia", width: 85),
                        ShellTable.Column(title: "Tranco", width: 70), ShellTable.Column(title: "Tramos", width: 60),
                    ], rows: e.perGait.map { (g: EngineGaitRow) -> [String] in
                        [g.aire, g.duracion, g.fraccionTiempo, g.distancia, g.velocidadMedia, g.cadencia, g.tranco, "\(g.tramos)"]
                    })
                    Text("Tabla del motor AVO (sesión analizada por el motor).").font(.caption2).foregroundStyle(Avo.textDim)
                }
            }
        }
    }
}

/// Speed zones of the filtered speed (bands, approximate gait labels).
private struct HorseZonesCard: View {
    let summary: HorseSummary
    var fill: Bool = false

    var body: some View {
        let h: HorseSummary = summary
        AvoCard(title: "Zonas de velocidad", subtitle: "Velocidad filtrada · tiempo y distancia por banda (aire aproximado)", fill: fill) {
            if h.zoneTotalS <= 0 {
                AvoNoData(text: "Sin datos de velocidad")
            } else {
                Chart(h.zones) { (z: HorseSpeedZone) in
                    BarMark(x: .value("Minutos", z.seconds / 60), y: .value("Zona", z.range))
                        .foregroundStyle(z.color)
                        .annotation(position: .trailing, alignment: .leading) {
                            Text(HorseFmt.pct(z.seconds, h.zoneTotalS)).font(.caption2.weight(.semibold)).foregroundStyle(Avo.text)
                        }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(Avo.line)
                        AxisValueLabel {
                            if let d = value.as(Double.self) {
                                Text(DotNetFormat.custom(d, "0.#", spanish: true) + " min").font(.caption2).foregroundStyle(Avo.textDim)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let s = value.as(String.self) { Text(s).font(.caption2).foregroundStyle(Avo.textDim) }
                        }
                    }
                }
                .chartLegend(.hidden)
                .frame(height: 170)
                ForEach(h.zones) { (z: HorseSpeedZone) in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2).fill(z.color).frame(width: 10, height: 10)
                        Text(z.range).font(.caption.weight(.semibold)).foregroundStyle(Avo.text).lineLimit(1).fixedSize()
                        Spacer(minLength: 4)
                        Text(TimeText.clock(z.seconds)).font(.caption.monospacedDigit()).foregroundStyle(Avo.text)
                            .lineLimit(1).fixedSize()
                        Text(HorseFmt.km(z.meters)).font(.caption.monospacedDigit()).foregroundStyle(Avo.textDim)
                            .lineLimit(1).fixedSize().frame(minWidth: 62, alignment: .trailing)
                    }
                }
                Text("Las bandas son de velocidad, no aires medidos: el aire real lo da el motor con la cincha.")
                    .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Effort: distance, moving vs stopped time, efforts above 25 km/h and recoveries.
private struct HorseEffortCard: View {
    @Environment(AppModel.self) private var app
    let summary: HorseSummary
    var fill: Bool = false

    var body: some View {
        let h: HorseSummary = summary
        AvoCard(title: "Esfuerzo", subtitle: "Parado = velocidad < 1 km/h · esfuerzo = más de 25 km/h durante más de 10 s", fill: fill) {
            LazyVGrid(columns: horseGrid, spacing: 8) {
                HorseTile(label: "Distancia total", value: HorseFmt.km(h.totalDistanceM))
                HorseTile(label: "En movimiento", value: TimeText.clock(h.movingS), caption: HorseFmt.pct(h.movingS, h.movingS + h.stoppedS))
                HorseTile(label: "Parado", value: TimeText.clock(h.stoppedS), caption: HorseFmt.pct(h.stoppedS, h.movingS + h.stoppedS))
                HorseTile(label: "Esfuerzos", value: "\(h.efforts.count)", caption: "> 25 km/h · > 10 s", accent: h.efforts.isEmpty ? Avo.text : Avo.red)
                HorseTile(label: "Recuperación media", value: h.meanRecoveryS.isFinite ? TimeText.clock(h.meanRecoveryS) : "Sin datos",
                          caption: "Entre esfuerzos")
            }
            if h.efforts.isEmpty {
                Text("Ningún esfuerzo por encima de 25 km/h durante más de 10 s.").font(.caption).foregroundStyle(Avo.textDim)
            } else {
                VStack(spacing: 0) {
                    ForEach(h.efforts.prefix(40)) { (b: HorseEffortBout) in
                        Button {
                            app.cursorTime = b.t0
                            app.rangeStart = b.t0
                            app.rangeEnd = b.t1
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("#\(b.id)").font(.caption.weight(.semibold)).foregroundStyle(Avo.red).lineLimit(1).fixedSize()
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(TimeText.clock(b.t0) + " · " + TimeText.num(b.durationS, "0", " s") + " · máx " + TimeText.num(b.maxKmh, "0.0", " km/h"))
                                        .font(.caption.monospacedDigit()).foregroundStyle(Avo.text).lineLimit(1).minimumScaleFactor(0.8)
                                    Text(TimeText.num(b.meters, "0", " m") + " · " + (b.recoveryBeforeS.isFinite ? "recuperación " + TimeText.clock(b.recoveryBeforeS) : "primer esfuerzo"))
                                        .font(.caption2).foregroundStyle(Avo.textDim).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().background(Avo.line)
                    }
                }
            }
        }
    }
}

/// Validated accelerations and braking (SegmentAnalyzer.accelValid).
private struct HorseAccelCard: View {
    let summary: HorseSummary
    var fill: Bool = false

    var body: some View {
        let h: HorseSummary = summary
        AvoCard(title: "Aceleraciones y frenadas", subtitle: "Solo aceleración longitudinal validada (incertidumbre ≤ 0,8 m/s², sin cortes)", fill: fill) {
            LazyVGrid(columns: horseGrid, spacing: 8) {
                HorseTile(label: "Aceleración máx.", value: HorseFmt.num(h.maxAccel, "0.00", " m/s²"), accent: Avo.ok)
                HorseTile(label: "Frenada máx.", value: HorseFmt.num(h.maxDecel, "0.00", " m/s²"), accent: Avo.red)
                HorseTile(label: "Aceleraciones", value: "\(h.accelEvents)", caption: "> 1,5 m/s²")
                HorseTile(label: "Frenadas", value: "\(h.brakeEvents)", caption: "< −1,5 m/s²")
            }
            Text("Muestras con aceleración validada: \(DotNetFormat.custom(h.validAccelFraction * 100, "0", spanish: true)) %")
                .font(.caption2).foregroundStyle(Avo.textDim)
        }
    }
}

/// Curves detected by the engine.
private struct HorseCurvesCard: View {
    let summary: HorseSummary
    var fill: Bool = false

    var body: some View {
        let h: HorseSummary = summary
        AvoCard(title: "Curvas", subtitle: "Detectadas por el motor AVO en la parte analizada", fill: fill) {
            if !h.hasEngine {
                AvoNoData(text: "Sin resultado del motor AVO")
            } else {
                LazyVGrid(columns: horseGrid, spacing: 8) {
                    HorseTile(label: "Curvas", value: "\(h.curves)")
                    HorseTile(label: "A la izquierda", value: "\(h.curvesLeft)")
                    HorseTile(label: "A la derecha", value: "\(h.curvesRight)")
                    HorseTile(label: "Lateral máx.", value: HorseFmt.num(h.maxLateral, "0.00", " m/s²"), caption: "Estimada (media por curva)")
                }
            }
        }
    }
}

/// Cadence, stride length, regularity and asymmetry from the engine (girth only).
private struct HorseGirthCard: View {
    @Environment(AppModel.self) private var app
    let summary: HorseSummary

    var body: some View {
        let h: HorseSummary = summary
        let b: BiomechModel = app.biomech
        AvoCard(title: "Marcha (cincha)", subtitle: "Índices del motor AVO con la IMU de la cincha · exploratorios, no diagnóstico clínico") {
            if h.hasImu {
                LazyVGrid(columns: horseGrid, spacing: 8) {
                    HorseTile(label: "Cadencia", value: HorseFmt.headline(b.cadenceHeadline, " /min"), caption: "Sensor central")
                    HorseTile(label: "Longitud de tranco", value: HorseFmt.headline(b.strideHeadline, " m"), caption: "Velocidad / cadencia")
                    HorseTile(label: "Regularidad", value: HorseFmt.headline(b.regularityHeadline), caption: "Correlación entre ciclos (0–1)")
                    HorseTile(label: "Asimetría temporal", value: HorseFmt.headline(b.symmetryHeadline, " %"), caption: "Grupos reproducibles")
                }
                Button("Ver biomecánica") { app.page = .biomech }
                    .buttonStyle(.avoSecondary)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(Avo.warn)
                    Text("Sin datos de cincha: conecta la cincha para cadencia, tranco y simetría.")
                        .font(.footnote).foregroundStyle(Avo.text).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 6)
            }
        }
    }
}


/// Route of the training on the satellite map, synced with the playback cursor (tap = move the cursor there).
private struct AnalysisRouteMap: View {
    @Environment(AppModel.self) private var app
    @State private var command: RouteMapCommand = RouteMapCommand()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MapRouteContainer(command: command, fitPadding: UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30))
            HStack(spacing: 6) {
                Button { command = command.next(.fit) } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 34, height: 34)
                }
                .accessibilityLabel("Ajustar recorrido")
                Button { app.page = .analysis } label: {
                    Image(systemName: "map").frame(width: 34, height: 34)
                }
                .accessibilityLabel("Abrir en Mapa")
            }
            .foregroundStyle(Avo.text)
            .background(Color(hex: 0x101014, alpha: 0.9), in: RoundedRectangle(cornerRadius: 7))
            .padding(10)
            if app.map.route == nil {
                ProgressView().controlSize(.small).padding(14).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Avo.line, lineWidth: 1))
        .onAppear { app.map.pageShown() }
    }
}
