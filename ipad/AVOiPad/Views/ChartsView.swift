import SwiftUI
import UIKit
import Charts

// MARK: - Charts page (Windows Views/ChartsView.xaml, iPad layout requested by the trainer)

/// Synchronised scientific charts, full width and stacked in a vertical scroll. All charts share the x window, the cursor
/// and the selected range with the map. Order: speed · acceleration · girth lateral deviations · girth tilt/anomalies ·
/// «Más gráficas» · «Mostrar datos». No GNSS quality/altitude/hAcc/satellites here (GPS page).
/// Touch: tap/drag horizontally = cursor · hold then drag (or «Seleccionar rango») = range · pinch = zoom · vertical
/// swipe = scroll.
struct ChartsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let charts: ChartsModel = app.charts
        // trainer's sketch 08/11/2026: no page title, no «Seleccionar rango» (hold and drag selects) and no «VER» phase
        // buttons; zoom, tramo actions and playback on one row, then the overview bar
        VStack(alignment: .leading, spacing: 10) {
            if app.selected == nil {
                AvoCard { AvoNoData(text: "Selecciona un entrenamiento para ver las gráficas") }
                Spacer(minLength: 0)
            } else {
                ChartsToolbar(charts: charts)
                if app.hasRange && !charts.rangeStats.isEmpty {
                    ChartsRangeStrip(rows: charts.rangeStats)
                }
                ChartsOverviewBar(charts: charts)
                    .frame(height: 34)
                ScrollView(.vertical) {
                    ChartsStack(charts: charts)
                        .padding(.bottom, 24)
                }
                // while «Seleccionar rango» is on, a drag on a chart must select, never scroll
                .scrollDisabled(charts.rangeMode)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Avo.bg)
        .background(ChartsRangeWatcher())
        .onAppear {
            app.charts.rangeMode = false   // the toggle is gone on this page: hold and drag selects
            app.charts.pageShown()
        }
    }
}

/// Recomputes the range statistics shortly after the selection stops changing, and keeps the cursor visible while
/// playing with a zoomed window. Separate view so the charts do not re-render on every cursor/range change.
private struct ChartsRangeWatcher: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let key: String = "\(app.rangeStart)|\(app.rangeEnd)"
        Color.clear
            .task(id: key) {
                try? await Task.sleep(nanoseconds: 150_000_000)
                if Task.isCancelled { return }
                app.charts.refreshRangeStats()
            }
            .onChange(of: app.cursorTime) { _, t in
                if app.isPlaying { app.charts.follow(t) }
            }
    }
}

// MARK: Toolbar (zoom / pan · tramo actions · playback)

private struct ChartsToolbar: View {
    @Environment(AppModel.self) private var app
    let charts: ChartsModel
    @State private var csvURL: URL? = nil
    @State private var exporting: Bool = false

    var body: some View {
        // one row when it fits (iPad Pro 13 landscape), otherwise view controls and tramo actions on two rows
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                viewControls
                Spacer(minLength: 12)
                rangeActions
                Divider().frame(height: 22)
                SyncPlaybackBar(compact: true)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    viewControls
                    Spacer(minLength: 8)
                    SyncPlaybackBar(compact: true)
                }
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    rangeActions
                }
            }
        }
    }

    @ViewBuilder
    private var viewControls: some View {
        Button { charts.zoom(1.5) } label: { Image(systemName: "minus.magnifyingglass") }
            .buttonStyle(.avoSecondary).accessibilityLabel("Alejar")
        Button { charts.zoom(1 / 1.5) } label: { Image(systemName: "plus.magnifyingglass") }
            .buttonStyle(.avoSecondary).accessibilityLabel("Acercar")
        Button { charts.pan(-0.4) } label: { Image(systemName: "chevron.left") }
            .buttonStyle(.avoSecondary).disabled(!charts.isZoomed).accessibilityLabel("Desplazar a la izquierda")
        Button { charts.pan(0.4) } label: { Image(systemName: "chevron.right") }
            .buttonStyle(.avoSecondary).disabled(!charts.isZoomed).accessibilityLabel("Desplazar a la derecha")
        Button { charts.resetZoom() } label: { Image(systemName: "arrow.up.left.and.down.right.magnifyingglass") }
            .buttonStyle(.avoSecondary).disabled(!charts.isZoomed)
            .accessibilityLabel("Restablecer zoom")
            .accessibilityIdentifier("charts.resetZoom")
        if charts.building { ProgressView().controlSize(.small) }
    }

    @ViewBuilder
    private var rangeActions: some View {
        Button("Guardar como tramo") { app.segments.addFromRange() }
            .buttonStyle(.avoPrimary).disabled(!app.hasRange).fixedSize()
            .accessibilityIdentifier("charts.saveSegment")
        Button("Quitar selección") { charts.clearRange() }
            .buttonStyle(.avoSecondary).disabled(!app.hasRange).fixedSize()
            .accessibilityIdentifier("charts.clearRange")
        Button(exporting ? "Preparando…" : "Exportar CSV") { exportCsv() }
            .buttonStyle(.avoSecondary).disabled(exporting).fixedSize()
            .accessibilityIdentifier("charts.exportCsv")
        if let url = csvURL {
            ShareLink(item: url) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.avoSecondary)
            .accessibilityLabel("Compartir \(url.lastPathComponent)")
        }
    }

    private func exportCsv() {
        guard let s = app.selected else { return }
        let tl: SessionTimeline = s.timeline
        let t0: Double = app.hasRange ? min(app.rangeStart, app.rangeEnd) : -Double.infinity
        let t1: Double = app.hasRange ? max(app.rangeStart, app.rangeEnd) : Double.infinity
        let root: String = app.paths.root
        let name: String = SyncExportFiles.name("serie", s.session.sessionId, "csv")
        exporting = true
        Task.detached(priority: .userInitiated) {
            let data: Data = AnalysisExport.timelineCsvData(tl, t0: t0, t1: t1)
            let result: Result<URL, Error> = SyncExportFiles.write(data, root: root, name: name)
            await MainActor.run {
                exporting = false
                switch result {
                case .success(let url):
                    csvURL = url
                    app.status = "CSV preparado: \(url.lastPathComponent)"
                case .failure(let e):
                    app.log.error("exportar", e.localizedDescription, e)
                    app.show("Exportar CSV", e.localizedDescription, error: true)
                }
            }
        }
    }
}

/// Zoom, pan and range ("tramo") controls of the shared timeline, for pages other than «Gráficas» (Biomecánica).
struct SyncZoomBar: View {
    @Environment(AppModel.self) private var app
    let charts: ChartsModel

    var body: some View {
        @Bindable var c = charts
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Toggle(isOn: $c.rangeMode) { Label("Seleccionar tramo", systemImage: "arrow.left.and.right.square") }
                    .toggleStyle(.button).tint(Avo.red).fixedSize()
                Button { charts.zoom(1.5) } label: { Image(systemName: "minus.magnifyingglass") }
                    .buttonStyle(.avoSecondary).accessibilityLabel("Alejar")
                Button { charts.zoom(1 / 1.5) } label: { Image(systemName: "plus.magnifyingglass") }
                    .buttonStyle(.avoSecondary).accessibilityLabel("Acercar")
                Button { charts.pan(-0.4) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.avoSecondary).disabled(!charts.isZoomed).accessibilityLabel("Desplazar a la izquierda")
                Button { charts.pan(0.4) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.avoSecondary).disabled(!charts.isZoomed).accessibilityLabel("Desplazar a la derecha")
                Button { charts.resetZoom() } label: { Image(systemName: "arrow.up.left.and.down.right.magnifyingglass") }
                    .buttonStyle(.avoSecondary).disabled(!charts.isZoomed).accessibilityLabel("Restablecer zoom")
                Button {
                    let t: Double = app.cursorTime
                    if t.isFinite { charts.setViewport(t - 2, t + 2) }
                } label: { Label("Ver ±2 s del cursor", systemImage: "scope") }
                    .buttonStyle(.avoSecondary).disabled(!app.cursorTime.isFinite)
                    .accessibilityIdentifier("sync.zoomCursor")
                Divider().frame(height: 22)
                Button("Guardar como tramo") { app.segments.addFromRange() }
                    .buttonStyle(.avoPrimary).disabled(!app.hasRange).fixedSize()
                Button("Quitar selección") { charts.clearRange() }
                    .buttonStyle(.avoSecondary).disabled(!app.hasRange).fixedSize()
                SyncPlaybackBar(compact: true)
            }
            .padding(.vertical, 1)
        }
    }
}

/// Phase filter (Completo · Calentamiento · Trabajo · Enfriamiento) and the overview bar to scroll through the session.
struct ChartsNavigator: View {
    @Environment(AppModel.self) private var app
    let charts: ChartsModel

    var body: some View {
        let tw: TrackWorkResult? = app.selected?.engine?.trackWork
        let off: Double = app.selected?.engineOffsetS ?? 0
        let d: ClosedRange<Double> = charts.domain
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("VER").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim)
                phaseButton("Completo", nil, off, Avo.silver, active: !charts.isZoomed)
                phaseButton("Calentamiento", tw?.warmup, off, CorrectionsModel.warmupColor, active: isActive(tw?.warmup, off, d))
                phaseButton("Trabajo", tw?.work, off, CorrectionsModel.workColor, active: isActive(tw?.work, off, d))
                phaseButton("Enfriamiento", tw?.cooldown, off, CorrectionsModel.cooldownColor, active: isActive(tw?.cooldown, off, d))
                Spacer(minLength: 8)
                Text(charts.isZoomed ? "\(TimeText.clock(d.lowerBound)) – \(TimeText.clock(d.upperBound)) de \(TimeText.clock(charts.fullHi))"
                                     : "Toca la barra para acercar · arrastra el recuadro para moverte")
                    .font(.caption.monospacedDigit()).foregroundStyle(Avo.textDim).lineLimit(1).minimumScaleFactor(0.7)
            }
            ChartsOverviewBar(charts: charts)
                .frame(height: 34)
        }
    }

    private func range(_ p: TrackWorkPhase?, _ off: Double) -> (Double, Double)? {
        guard let p = p, p.present, p.t0.isFinite, p.t1.isFinite, p.t1 > p.t0 else { return nil }
        return (p.t0 - off, p.t1 - off)
    }

    private func isActive(_ p: TrackWorkPhase?, _ off: Double, _ d: ClosedRange<Double>) -> Bool {
        guard charts.isZoomed, let r = range(p, off) else { return false }
        return abs(d.lowerBound - max(r.0, charts.fullLo)) < 1 && abs(d.upperBound - min(r.1, charts.fullHi)) < 1
    }

    private func phaseButton(_ title: String, _ p: TrackWorkPhase?, _ off: Double, _ color: Color, active: Bool) -> some View {
        let r: (Double, Double)? = range(p, off)
        let enabled: Bool = p == nil ? true : r != nil
        return Button {
            if title == "Completo" { charts.resetZoom() } else if let r = r { charts.setViewport(r.0, r.1) }
        } label: {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
                Text(title).font(.callout.weight(active ? .semibold : .regular))
            }
            .foregroundStyle(active ? Avo.text : Avo.silver)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(active ? Avo.redSoft : Avo.surface2, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(active ? Avo.red : Avo.line, lineWidth: 1))
            .opacity(enabled ? 1 : 0.4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier("charts.phase.\(title)")
    }
}

/// Overview of the whole session: speed outline, phase / repetition strips, cursor and the visible window. Dragging the
/// window scrolls the charts; touching outside it moves the window there; without zoom, a touch zooms to a quarter of
/// the session around that point.
struct ChartsOverviewBar: View {
    @Environment(AppModel.self) private var app
    let charts: ChartsModel
    @State private var grab: Double? = nil

    var body: some View {
        GeometryReader { (geo: GeometryProxy) in
            let w: CGFloat = max(geo.size.width, 1)
            let h: CGFloat = geo.size.height
            let lo: Double = charts.fullLo
            let span: Double = max(charts.fullHi - charts.fullLo, 1e-6)
            let d: ClosedRange<Double> = charts.domain
            let x0: CGFloat = CGFloat((d.lowerBound - lo) / span) * w
            let x1: CGFloat = CGFloat((d.upperBound - lo) / span) * w
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6).fill(Avo.surface2)
                Canvas { (ctx: inout GraphicsContext, size: CGSize) in
                    // speed outline (filtered speed of the timeline, decimated)
                    if let tl = app.selected?.timeline, tl.count > 1 {
                        let n: Int = tl.count
                        let step: Int = max(1, n / 500)
                        var vmax: Double = 1
                        var k: Int = 0
                        while k < n { let v = tl.speedFiltered[k]; if v.isFinite && v > vmax { vmax = v }; k += step }
                        var path = Path()
                        var started: Bool = false
                        k = 0
                        while k < n {
                            let v: Double = tl.speedFiltered[k]
                            if v.isFinite {
                                let x: CGFloat = CGFloat((tl.t[k] - lo) / span) * size.width
                                let y: CGFloat = size.height - 9 - CGFloat(v / vmax) * (size.height - 14)
                                if started { path.addLine(to: CGPoint(x: x, y: y)) } else { path.move(to: CGPoint(x: x, y: y)); started = true }
                            } else {
                                started = false
                            }
                            k += step
                        }
                        ctx.stroke(path, with: .color(Avo.red.opacity(0.75)), lineWidth: 1)
                    }
                    // phases (bottom) and repetitions (above)
                    for b in app.corrections.bands(app.selected) {
                        let a: CGFloat = CGFloat((b.x0 - lo) / span) * size.width
                        let z: CGFloat = CGFloat((b.x1 - lo) / span) * size.width
                        ctx.fill(Path(CGRect(x: a, y: size.height - 4 - CGFloat(b.lane) * 5, width: max(1, z - a), height: 4)), with: .color(b.color))
                    }
                    if app.cursorTime.isFinite {
                        let cx: CGFloat = CGFloat((app.cursorTime - lo) / span) * size.width
                        ctx.fill(Path(CGRect(x: cx - 0.75, y: 0, width: 1.5, height: size.height)), with: .color(Color.white.opacity(0.9)))
                    }
                }
                if charts.isZoomed {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.white.opacity(0.10))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.85), lineWidth: 1.5))
                        .frame(width: max(x1 - x0, 10), height: h)
                        .offset(x: min(x0, w - max(x1 - x0, 10)))
                        .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Avo.line, lineWidth: 1))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { (v: DragGesture.Value) in
                        let t: Double = lo + Double(min(max(v.location.x, 0), w) / w) * span
                        let cur: ClosedRange<Double> = charts.domain
                        if !charts.isZoomed {
                            charts.setViewport(t - span / 8, t + span / 8)
                            grab = span / 8
                            return
                        }
                        let width: Double = cur.upperBound - cur.lowerBound
                        if grab == nil {
                            let ts: Double = lo + Double(min(max(v.startLocation.x, 0), w) / w) * span
                            grab = (ts >= cur.lowerBound && ts <= cur.upperBound) ? ts - cur.lowerBound : width / 2
                        }
                        let a: Double = t - (grab ?? width / 2)
                        charts.setViewport(a, a + width)
                    }
                    .onEnded { (_: DragGesture.Value) in grab = nil }
            )
            .accessibilityLabel("Barra de desplazamiento de las gráficas")
            .accessibilityIdentifier("charts.overview")
        }
    }
}

/// Statistics of the selected range in one horizontal strip (only while a range exists).
private struct ChartsRangeStrip: View {
    let rows: [SyncStatRow]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                Text("SELECCIÓN").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.red)
                ForEach(rows) { (r: SyncStatRow) in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.key).font(.caption2).foregroundStyle(Avo.textDim).lineLimit(1)
                        Text(r.value).font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(Avo.text).lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Avo.cardBrush, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Avo.line, lineWidth: 1))
    }
}

// MARK: Charts (full width, stacked)

/// Legends of the charts. Each entry is a switch (SyncChartBox chartId): `keys` match the series names of ChartsModel /
/// ChartsImuAnalysis, `sigma` the ±σ envelope and `marker` the point markers of that colour.
enum ChartsLegends {
    static let speed: [SyncLegend] = [SyncLegend("Filtrada", Avo.red, keys: ["Filtrada"]), SyncLegend("Reportada", Avo.blue, keys: ["Reportada"]),
                                      SyncLegend("Derivada", Avo.silver, keys: ["Derivada"]), SyncLegend("±1σ", Avo.red.opacity(0.35), sigma: true)]
    static let accel: [SyncLegend] = [SyncLegend("Longitudinal (validada)", Avo.warn, keys: ["Longitudinal"]),
                                      SyncLegend("Lateral", Avo.cyan, keys: ["Lateral"])]
    static let lateral: [SyncLegend] = [SyncLegend("Lateral (izquierda +)", ChartsImuAnalysis.lateralColor, keys: ["·Lateral·"]),
                                        SyncLegend("Umbral", ChartsImuAnalysis.lateralColor.opacity(0.3), keys: ["Umbral"]),
                                        SyncLegend("Desvío brusco", ChartsImuAnalysis.markerColor, marker: ChartsImuAnalysis.markerColor)]
    static let tilt: [SyncLegend] = [SyncLegend("Balanceo", ChartsImuAnalysis.rollColor, keys: ["Balanceo"]),
                                     SyncLegend("Cabeceo", ChartsImuAnalysis.pitchColor, keys: ["Cabeceo"]),
                                     SyncLegend("Anomalía", ChartsImuAnalysis.markerColor, marker: ChartsImuAnalysis.markerColor),
                                     SyncLegend("Salto vertical", ChartsImuAnalysis.jumpColor, marker: ChartsImuAnalysis.jumpColor)]
    static let vertical: [SyncLegend] = [SyncLegend("Vertical", ChartsImuAnalysis.verticalColor, keys: ["Vertical"]),
                                         SyncLegend("|a|", ChartsImuAnalysis.lateralColor, keys: ["|a|"])]
    static let sensors: [SyncLegend] = [SyncLegend("Izquierda", Avo.blue, keys: ["Izquierda"]), SyncLegend("Central", Avo.ok, keys: ["Central"]),
                                        SyncLegend("Derecha", Avo.warn, keys: ["Derecha"])]
}

private enum ChartsHeights {
    static let speed: CGFloat = 300
    static let main: CGFloat = 220
    /// IMU charts: plot + caption + event list.
    static let imu: CGFloat = 300
    static let more: CGFloat = 210
    static let placeholder: CGFloat = 96
}

struct ChartsStack: View {
    @Environment(AppModel.self) private var app
    let charts: ChartsModel
    /// Análisis: la velocidad ya está en el perfil de la línea de tiempo, encima.
    var skipSpeed: Bool = false

    var body: some View {
        let d: ClosedRange<Double> = charts.domain
        let empty: String = charts.building ? "Calculando…" : "Sin datos"
        LazyVStack(alignment: .leading, spacing: 10) {
            // 1. speed (no RTK quality strip on this page)
            if charts.chartSpeed && !skipSpeed {
                SyncChartBox(title: "Velocidad (km/h)", legend: ChartsLegends.speed,
                             readout: { (a: AppModel) -> String in a.cursorSpeed + " km/h" }, chartId: "speed") {
                    SyncSignalChart(panel: charts.panel(.speed, chart: "speed", legend: ChartsLegends.speed), domain: d, includeZero: true, emptyText: empty, scrollFriendly: true)
                }
                .frame(height: ChartsHeights.speed)
            }
            // 2. acceleration
            if charts.chartAccel {
                SyncChartBox(title: "Aceleración (m/s²)", legend: ChartsLegends.accel,
                             readout: { (a: AppModel) -> String in a.cursorAccel + " m/s²" }, chartId: "accel") {
                    SyncSignalChart(panel: charts.panel(.accel, chart: "accel", legend: ChartsLegends.accel), domain: d, includeZero: true,
                                    emptyText: charts.building ? "Calculando…" : "Sin aceleración validada", scrollFriendly: true)
                }
                .frame(height: ChartsHeights.main)
            }
            // 3. girth lateral deviations
            if charts.chartLateral {
                if charts.hasGirthImu {
                    SyncChartBox(title: "IMU cincha → Desvíos laterales (m/s²)", legend: ChartsLegends.lateral,
                                 readout: { (a: AppModel) -> String in a.charts.lateralReadout(a.cursorTime) }, chartId: "lateral") {
                        VStack(alignment: .leading, spacing: 4) {
                            SyncSignalChart(panel: charts.panel(.lateral, chart: "lateral", legend: ChartsLegends.lateral), domain: d, bands: charts.gaitBands, includeZero: true,
                                            emptyText: empty, scrollFriendly: true)
                            ChartsCaption(text: "Aceleración lateral de la cincha respecto a la dirección de avance; picos = desvíos bruscos (espantadas). Banda = mediana ± máx(5·MAD, 2 m/s²) en 20 s. " + charts.imuHeadingNote + sensorText)
                            ChartsEventList(events: charts.lateralEvents, noun: "desvíos",
                                            emptyText: charts.building ? "Calculando…" : "Sin desvíos por encima del umbral")
                        }
                    }
                    .frame(height: ChartsHeights.imu)
                } else {
                    ChartsNoGirth(title: "IMU cincha → Desvíos laterales")
                }
            }
            // 4. girth tilt / anomalies
            if charts.chartTilt {
                if charts.hasGirthImu {
                    SyncChartBox(title: "IMU cincha → Inclinaciones / anomalías (°)", legend: ChartsLegends.tilt,
                                 readout: { (a: AppModel) -> String in a.charts.tiltReadout(a.cursorTime) }, chartId: "tilt") {
                        VStack(alignment: .leading, spacing: 4) {
                            SyncSignalChart(panel: charts.panel(.tilt, chart: "tilt", legend: ChartsLegends.tilt), domain: d, bands: charts.gaitBands, includeZero: false,
                                            emptyText: empty, scrollFriendly: true)
                            ChartsCaption(text: "Balanceo (inclinación lateral) y cabeceo de la cincha. Puntos = saltos anómalos: ángulo fuera de mediana ± máx(5·MAD, 5°) o aceleración vertical fuera de mediana ± máx(6·MAD, 4 m/s²), ventana móvil de 20 s." + sensorText)
                            ChartsEventList(events: charts.tiltEvents, noun: "anomalías",
                                            emptyText: charts.building ? "Calculando…" : "Sin anomalías por encima del umbral")
                        }
                    }
                    .frame(height: ChartsHeights.imu)
                } else {
                    ChartsNoGirth(title: "IMU cincha → Inclinaciones / anomalías")
                }
            }
            // 5. more charts
            ChartsMoreCharts(charts: charts, domain: d)
            // data toggles at the end of the scroll
            ChartsDataToggles(charts: charts)
            ChartsNotes(charts: charts)
        }
    }

    private var sensorText: String {
        charts.imuSensorName.isEmpty ? "" : " Sensor analizado: " + charts.imuSensorName + "."
    }
}

private struct ChartsMoreCharts: View {
    @Environment(AppModel.self) private var app
    let charts: ChartsModel
    let domain: ClosedRange<Double>

    var body: some View {
        let d: ClosedRange<Double> = domain
        let empty: String = charts.building ? "Calculando…" : "Sin datos"
        let showVert: Bool = charts.chartFused && charts.hasGirthImu
        let showCad: Bool = charts.chartCadence
        let showRaw: Bool = charts.chartImu && charts.hasImuRaw && !charts.hasFused
        VStack(alignment: .leading, spacing: 10) {
        if showVert || showCad || showRaw {
            Text("MÁS GRÁFICAS").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(Avo.silver)
                .padding(.top, 6)
        }
        if showVert {
            SyncChartBox(title: charts.imuSource == 2 ? "Cincha · vertical y |a| (m/s², aproximación sin fusión)"
                                                       : "Cincha · vertical y |a| sin gravedad (m/s², ejes del mundo)",
                         legend: ChartsLegends.vertical,
                         readout: { (a: AppModel) -> String in a.charts.verticalReadout(a.cursorTime) }, chartId: "vertical") {
                SyncSignalChart(panel: charts.panel(.fusedAccel, chart: "vertical", legend: ChartsLegends.vertical), domain: d, bands: charts.gaitBands, includeZero: true,
                                emptyText: empty, scrollFriendly: true)
            }
            .frame(height: ChartsHeights.more)
        }
        if showCad {
            SyncChartBox(title: "Cadencia (motor AVO, ciclos/min) · banda = aire", legend: ChartsLegends.sensors,
                         readout: { (a: AppModel) -> String in a.cursorCadence }, chartId: "cadence") {
                SyncSignalChart(panel: charts.panel(.cadence, chart: "cadence", legend: ChartsLegends.sensors), domain: d, bands: charts.gaitBands, includeZero: false,
                                emptyText: charts.hasCadence ? "El motor no ha encontrado ciclos de marcha"
                                                             : "Sin cadencia del motor (requiere datos de cincha y análisis del motor)",
                                scrollFriendly: true)
            }
            .frame(height: charts.hasCadence ? ChartsHeights.more : ChartsHeights.placeholder)
        }
        if showRaw {
            SyncChartBox(title: charts.imuChartHeader, legend: ChartsLegends.sensors, chartId: "imu") {
                SyncSignalChart(panel: charts.panel(.imu, chart: "imu", legend: ChartsLegends.sensors), domain: d, bands: charts.gaitBands, includeZero: false,
                                emptyText: "Sin datos de cincha en esta sesión", scrollFriendly: true)
            }
            .frame(height: ChartsHeights.more)
        }
        }
    }
}

/// Compact placeholder of an IMU chart when the session has no girth data (keeps the same layout for every session).
private struct ChartsNoGirth: View {
    let title: String
    var body: some View {
        SyncChartBox(title: title) {
            Text("Sin datos de cincha (IMU)")
                .font(.footnote).foregroundStyle(Avo.textDim)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: ChartsHeights.placeholder)
    }
}

private struct ChartsCaption: View {
    let text: String
    var body: some View {
        Text(text).font(.caption2).foregroundStyle(Avo.textDim).lineLimit(3).fixedSize(horizontal: false, vertical: true)
    }
}

/// Count and list of detected events; tapping one moves the shared cursor there.
private struct ChartsEventList: View {
    @Environment(AppModel.self) private var app
    let events: [ChartsImuEvent]
    let noun: String
    let emptyText: String

    var body: some View {
        HStack(spacing: 8) {
            Text("\(events.count) \(noun)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(events.isEmpty ? Avo.textDim : ChartsImuAnalysis.markerColor)
                .fixedSize()
            if events.isEmpty {
                Text(emptyText).font(.caption2).foregroundStyle(Avo.textDim).lineLimit(1)
                Spacer(minLength: 0)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 6) {
                        ForEach(events) { (e: ChartsImuEvent) in
                            Button {
                                app.charts.focus(e.t)
                            } label: {
                                Text(e.text)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(Avo.text)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Avo.surface2, in: Capsule())
                                    .overlay(Capsule().stroke(ChartsImuAnalysis.markerColor.opacity(0.5), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Ir a " + e.text)
                        }
                    }
                }
            }
        }
        .frame(height: 26)
    }
}

// MARK: Bottom: data toggles and notes

private struct ChartsDataToggles: View {
    let charts: ChartsModel

    var body: some View {
        @Bindable var c = charts
        let cols: [GridItem] = [GridItem(.adaptive(minimum: 250, maximum: 420), spacing: 16, alignment: .leading)]
        AvoCard(title: "Mostrar datos") {
            VStack(alignment: .leading, spacing: 10) {
                Text("GRÁFICAS").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim)
                LazyVGrid(columns: cols, alignment: .leading, spacing: 8) {
                    Toggle("Velocidad", isOn: $c.chartSpeed)
                    Toggle("Aceleración", isOn: $c.chartAccel)
                    Toggle(charts.hasGirthImu ? "Desvíos laterales (cincha)" : "Desvíos laterales (sin datos)", isOn: $c.chartLateral)
                    Toggle(charts.hasGirthImu ? "Inclinaciones / anomalías" : "Inclinaciones (sin datos)", isOn: $c.chartTilt)
                    Toggle(charts.hasGirthImu ? "Vertical y |a| (cincha)" : "Vertical y |a| (sin datos)", isOn: $c.chartFused)
                        .disabled(!charts.hasGirthImu)
                    Toggle(charts.hasCadence ? "Cadencia (motor)" : "Cadencia (motor, sin datos)", isOn: $c.chartCadence)
                    Toggle(charts.hasImuRaw && !charts.hasFused ? "Canales brutos de la cincha" : "Canales brutos (solo fmt 0)",
                           isOn: $c.chartImu)
                        .disabled(!(charts.hasImuRaw && !charts.hasFused))
                }
                Divider().overlay(Avo.line)
                Text("VELOCIDAD Y ACELERACIÓN").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim)
                LazyVGrid(columns: cols, alignment: .leading, spacing: 8) {
                    Toggle("Filtrada (Kalman + RTS)", isOn: $c.showSpeedFiltered)
                    Toggle("Banda ±1σ de la filtrada", isOn: $c.showSigma).disabled(!charts.showSpeedFiltered)
                    Toggle("Reportada por el receptor", isOn: $c.showSpeedReported)
                    Toggle("Derivada de posiciones", isOn: $c.showSpeedDerived)
                    Toggle("Aceleración lateral", isOn: $c.showLateral)
                }
                Button("Ver todo (restablecer zoom)") { charts.resetZoom() }
                    .buttonStyle(.avoSecondary).padding(.top, 2)
            }
            .font(.callout)
            .tint(Avo.red)
        }
    }
}

private struct ChartsNotes: View {
    let charts: ChartsModel

    var body: some View {
        AvoCard(title: "Uso, filtrado y unidades") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Toca o arrastra en horizontal para mover el cursor; mantén pulsado y arrastra (o activa «Seleccionar rango») para seleccionar un tramo; pellizca para ampliar; desliza en vertical para desplazarte.")
                Text(charts.filterDescription)
                Text("La señal original se conserva: la velocidad reportada y la derivada de posiciones se pueden mostrar sin filtrar. Las aceleraciones solo se muestran con σ ≤ 0,8 m/s², solución ≥ DGNSS y sin cortes.")
                Text("Cincha: aceleración lineal (sin gravedad) girada a ejes del mundo con el cuaternión del BNO085; el lateral se proyecta sobre el rumbo GNSS cuando la velocidad es ≥ 2 m/s y, si no, sobre el eje lateral del sensor. Umbrales robustos (mediana ± k·MAD, ventana móvil de 20 s). Orientación de montaje no verificada en el caballo.")
                Text(charts.imuScaleNote)
            }
            .font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Shared chart components (used by Charts, Map and Segments pages)

/// Files written for sharing: `paths.root/exportaciones/<name>`.
enum SyncExportFiles {
    static func name(_ prefix: String, _ sessionId: String, _ ext: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Madrid")
        f.dateFormat = "yyyyMMdd_HHmmss"
        let sid: String = String(sessionId.filter { $0.isLetter || $0.isNumber }.prefix(12))
        return "AVO_\(prefix)_\(sid.isEmpty ? "sesion" : sid)_\(f.string(from: Date())).\(ext)"
    }

    static func write(_ data: Data, root: String, name: String) -> Result<URL, Error> {
        let dir: String = AvoFiles.join(root, "exportaciones")
        let path: String = AvoFiles.join(dir, name)
        do {
            try AvoFiles.writeAtomic(data, to: path)
            return .success(URL(fileURLWithPath: path))
        } catch {
            return .failure(error)
        }
    }
}

struct SyncLegend: Identifiable {
    var text: String
    var color: Color
    /// What the entry controls when it is switched off: lines whose name contains any key (the text when empty),
    /// the ±σ envelope, or the point markers of one colour.
    var keys: [String] = []
    var sigma: Bool = false
    var marker: Color? = nil
    var id: String { text }
    init(_ text: String, _ color: Color, keys: [String] = [], sigma: Bool = false, marker: Color? = nil) {
        self.text = text; self.color = color; self.keys = keys; self.sigma = sigma; self.marker = marker
    }
}

/// Windows AvoChartPanel: header, legend, cursor readout and the chart.
struct SyncChartBox<Content: View>: View {
    @Environment(AppModel.self) private var app
    var title: String
    var legend: [SyncLegend] = []
    var readout: ((AppModel) -> String)? = nil
    /// With an id, every legend entry is a switch that shows / hides its lines (ChartsModel.hiddenLegend).
    var chartId: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(title.uppercased()).font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.silver).lineLimit(1)
                ForEach(legend) { l in
                    if let cid = chartId {
                        let off: Bool = app.charts.isHidden(cid, l.text)
                        Button {
                            app.charts.toggleLegend(cid, l.text)
                        } label: {
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 1).fill(off ? Avo.textDim.opacity(0.4) : l.color).frame(width: 12, height: 3)
                                Text(l.text).font(.caption2).foregroundStyle(off ? Avo.textDim.opacity(0.5) : Avo.text)
                                    .strikethrough(off).lineLimit(1)
                            }
                            .padding(.horizontal, 6).padding(.vertical, 4)
                            .background(off ? Color.clear : Avo.surface2, in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Avo.line, lineWidth: 1))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel((off ? "Mostrar " : "Ocultar ") + l.text)
                        .accessibilityIdentifier("legend.\(cid).\(l.text)")
                    } else {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 1).fill(l.color).frame(width: 12, height: 3)
                            Text(l.text).font(.caption2).foregroundStyle(Avo.textDim).lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 4)
                if let r = readout { SyncReadout(text: r) }
            }
            content()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Avo.cardBrush, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Avo.line, lineWidth: 1))
    }
}

/// Cursor value, in its own view so only the text re-renders while the cursor moves.
struct SyncReadout: View {
    @Environment(AppModel.self) private var app
    let text: (AppModel) -> String
    var body: some View {
        Text(text(app)).font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(Avo.text).lineLimit(1)
    }
}

struct SyncKeyValueRows: View {
    var rows: [SyncStatRow]
    var body: some View {
        VStack(spacing: 5) {
            ForEach(rows) { r in
                HStack(alignment: .firstTextBaseline) {
                    Text(r.key).font(.caption).foregroundStyle(Avo.textDim)
                    Spacer(minLength: 8)
                    Text(r.value).font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(Avo.text).multilineTextAlignment(.trailing)
                }
            }
        }
    }
}

/// Buttons that wrap onto several lines.
struct SyncFlowButtons<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { content() }
            VStack(alignment: .leading, spacing: 6) { content() }
        }
    }
}

/// Chart of one panel with the shared cursor, range, zoom and coloured bands.
struct SyncSignalChart: View {
    var panel: SyncPanel
    var domain: ClosedRange<Double>
    var bands: [SyncBand] = []
    var includeZero: Bool = true
    var emptyText: String = "Sin datos"
    var zoomable: Bool = true
    /// The chart lives in a vertical ScrollView: touches are recognised together with the scroll and a mainly vertical
    /// swipe scrolls instead of moving the cursor.
    var scrollFriendly: Bool = false
    /// Draggable zone limits (Análisis page); `onHandle(id, time)` when one is dropped.
    var handles: [SyncHandle] = []
    var onHandle: ((Int, Double) -> Void)? = nil

    var body: some View {
        if panel.isEmpty {
            AvoNoData(text: emptyText)
                .frame(maxHeight: .infinity)
        } else {
            SyncChartPlot(panel: panel, domain: domain, bands: bands, includeZero: includeZero, zoomable: zoomable,
                          scrollFriendly: scrollFriendly, handles: handles, onHandle: onHandle)
        }
    }
}

/// The Swift Charts plot. Does not read the cursor: the cursor/range layer is a separate view in the overlay.
struct SyncChartPlot: View {
    let panel: SyncPanel
    let domain: ClosedRange<Double>
    let bands: [SyncBand]
    let includeZero: Bool
    let zoomable: Bool
    var scrollFriendly: Bool = false
    var handles: [SyncHandle] = []
    var onHandle: ((Int, Double) -> Void)? = nil

    static func clockLabel(_ value: AxisValue) -> String {
        guard let d = value.as(Double.self) else { return "" }
        return TimeText.clock(d)
    }

    var body: some View {
        Chart {
            ForEach(panel.sigma) { (s: SyncSigma) in
                RectangleMark(xStart: .value("t", s.x0), xEnd: .value("t", s.x1), yStart: .value("v", s.lo), yEnd: .value("v", s.hi))
                    .foregroundStyle(s.color ?? Avo.red.opacity(0.16))
            }
            ForEach(panel.lines) { (line: SyncLine) in
                ForEach(line.points) { (p: SyncPoint) in
                    LineMark(x: .value("t", p.x), y: .value("v", p.y), series: .value("serie", line.id))
                        .foregroundStyle(line.color)
                        .lineStyle(StrokeStyle(lineWidth: line.width, dash: line.dashed ? [4, 3] : []))
                        .interpolationMethod(.linear)
                }
            }
            ForEach(panel.markers) { (m: SyncMarker) in
                PointMark(x: .value("t", m.x), y: .value("v", m.y))
                    .foregroundStyle(m.color)
                    .symbolSize(40)
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: .automatic(includesZero: includeZero))
        .chartLegend(.hidden)
        .chartPlotStyle { (plot: ChartPlotContent) in plot.clipped() }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { (value: AxisValue) in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Avo.line)
                AxisValueLabel {
                    Text(SyncChartPlot.clockLabel(value)).font(.caption2).foregroundStyle(Avo.textDim)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { (_: AxisValue) in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Avo.line)
                AxisValueLabel().font(.caption2).foregroundStyle(Avo.textDim)
            }
        }
        .chartBackground { (proxy: ChartProxy) in
            SyncBandLayer(proxy: proxy, bands: bands)
        }
        .chartOverlay { (proxy: ChartProxy) in
            ZStack {
                SyncChartCursorLayer(proxy: proxy, domain: domain, zoomable: zoomable, scrollFriendly: scrollFriendly)
                if !handles.isEmpty {
                    SyncHandleLayer(proxy: proxy, domain: domain, handles: handles, onCommit: onHandle)
                }
            }
        }
        .environment(\.locale, Locale(identifier: "es_ES"))
    }
}

/// Draggable limits of the training zones: a grip at the bottom of the plot for each limit. Dragging moves the shared
/// cursor (map and readouts follow) and shows the time; dropping calls `onCommit(id, time)`. Only the grips take
/// touches: the rest of the chart keeps the cursor / range / zoom gestures.
struct SyncHandleLayer: View {
    @Environment(AppModel.self) private var app
    let proxy: ChartProxy
    let domain: ClosedRange<Double>
    let handles: [SyncHandle]
    var onCommit: ((Int, Double) -> Void)?

    @State private var dragId: Int? = nil
    @State private var dragT: Double = .nan

    var body: some View {
        GeometryReader { (geo: GeometryProxy) in
            let plot: CGRect = proxy.plotFrame.map { geo[$0] } ?? CGRect(origin: .zero, size: geo.size)
            ZStack(alignment: .topLeading) {
                if let id = dragId, let h = handles.first(where: { $0.id == id }), let x = xOf(dragT, plot) {
                    Rectangle().fill(h.color).frame(width: 2, height: plot.height).position(x: x, y: plot.midY)
                        .allowsHitTesting(false)
                    Text("\(h.label) · \(TimeText.clock(dragT))")
                        .font(.caption2.weight(.semibold)).foregroundStyle(Color.black)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(h.color, in: RoundedRectangle(cornerRadius: 4))
                        .fixedSize()
                        .position(x: min(max(x, plot.minX + 70), plot.maxX - 70), y: plot.minY + 12)
                        .allowsHitTesting(false)
                }
                ForEach(handles) { (h: SyncHandle) in
                    let t: Double = dragId == h.id ? dragT : h.x
                    if let x = xOf(t, plot), x >= plot.minX - 1, x <= plot.maxX + 1 {
                        grip(h, active: dragId == h.id)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                            .gesture(drag(h, plot))
                            .position(x: x, y: plot.maxY - 14 - CGFloat(h.lane) * 30)
                            .accessibilityLabel(h.label)
                            .accessibilityIdentifier("zone.handle.\(h.id)")
                    }
                }
            }
            .coordinateSpace(name: "zone.handles")
        }
    }

    private func grip(_ h: SyncHandle, active: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(h.color.opacity(active ? 1 : 0.9))
                .frame(width: active ? 12 : 10, height: active ? 30 : 24)
            RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.6), lineWidth: 1)
                .frame(width: active ? 12 : 10, height: active ? 30 : 24)
            VStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { (_: Int) in Rectangle().fill(Color.black.opacity(0.55)).frame(width: 5, height: 1) }
            }
        }
    }

    private func xOf(_ t: Double, _ plot: CGRect) -> CGFloat? {
        guard t.isFinite, let p = proxy.position(forX: t) else { return nil }
        return plot.minX + p
    }

    private func timeAt(_ x: CGFloat, _ plot: CGRect) -> Double {
        let v: Double = proxy.value(atX: x - plot.minX, as: Double.self) ?? domain.lowerBound
        return min(max(v, domain.lowerBound), domain.upperBound)
    }

    private func drag(_ h: SyncHandle, _ plot: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("zone.handles"))
            .onChanged { (v: DragGesture.Value) in
                if dragId != h.id {
                    dragId = h.id
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                dragT = timeAt(v.location.x, plot)
                app.cursorTime = dragT
            }
            .onEnded { (v: DragGesture.Value) in
                let t: Double = timeAt(v.location.x, plot)
                dragId = nil
                dragT = .nan
                if abs(v.translation.width) >= 2 { onCommit?(h.id, t) }
            }
    }
}

/// Coloured strip at the bottom of the plot area (Windows SignalChart bands, 4 px).
struct SyncBandLayer: View {
    let proxy: ChartProxy
    let bands: [SyncBand]

    var body: some View {
        GeometryReader { (geo: GeometryProxy) in
            let plot: CGRect = proxy.plotFrame.map { geo[$0] } ?? CGRect(origin: .zero, size: geo.size)
            Canvas { (ctx: inout GraphicsContext, _: CGSize) in
                for b in bands {
                    guard let p0 = proxy.position(forX: b.x0), let p1 = proxy.position(forX: b.x1) else { continue }
                    let x0: CGFloat = max(plot.minX + p0, plot.minX)
                    let x1: CGFloat = min(plot.minX + p1, plot.maxX)
                    if x1 <= x0 { continue }
                    let y: CGFloat = plot.maxY - b.height - CGFloat(b.lane) * (b.height + 2)
                    ctx.fill(Path(CGRect(x: x0, y: y, width: x1 - x0, height: b.height)), with: .color(b.color))
                }
            }
            .allowsHitTesting(false)
        }
    }
}

/// Two-finger horizontal pan on top of a SwiftUI chart. The view only adds a UIPanGestureRecognizer (2 touches) that
/// recognises together with everything else and does not cancel touches, so one-finger cursor / range drags and the
/// pinch zoom keep working.
struct TwoFingerPan: UIViewRepresentable {
    var onBegan: () -> Void
    var onChanged: (CGFloat) -> Void
    var onEnded: () -> Void
    var onPencilDoubleTap: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let v = UIView(frame: .zero)
        v.backgroundColor = .clear
        let g = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        g.minimumNumberOfTouches = 2
        g.maximumNumberOfTouches = 2
        g.cancelsTouchesInView = false
        g.delaysTouchesBegan = false
        g.delaysTouchesEnded = false
        g.delegate = context.coordinator
        v.addGestureRecognizer(g)
        let pencil = UIPencilInteraction()
        pencil.delegate = context.coordinator
        v.addInteraction(pencil)
        context.coordinator.parent = self
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) { context.coordinator.parent = self }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate, UIPencilInteractionDelegate {
        var parent: TwoFingerPan?
        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) { parent?.onPencilDoubleTap?() }
        @objc func pan(_ g: UIPanGestureRecognizer) {
            switch g.state {
            case .began: parent?.onBegan()
            case .changed: parent?.onChanged(g.translation(in: g.view).x)
            case .ended, .cancelled, .failed: parent?.onEnded()
            default: break
            }
        }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
        /// Only mostly-horizontal two-finger moves; vertical ones are left to the page scroll.
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let p = g as? UIPanGestureRecognizer else { return true }
            let v: CGPoint = p.velocity(in: p.view)
            return abs(v.x) >= abs(v.y)
        }
    }
}

/// Cursor line, selected range and touch handling of a chart. Reads the shared cursor/range itself so moving the cursor
/// never re-renders the chart marks.
struct SyncChartCursorLayer: View {
    @Environment(AppModel.self) private var app
    let proxy: ChartProxy
    let domain: ClosedRange<Double>
    let zoomable: Bool
    var scrollFriendly: Bool = false

    @State private var dragBegan: Date? = nil
    @State private var dragStart: CGPoint = .zero
    /// 0 undecided (tap), 1 cursor, 2 range, 3 vertical swipe (scroll, ignored).
    @State private var dragMode: Int = 0
    @State private var anchorT: Double = .nan
    @State private var pinchBase: ClosedRange<Double>? = nil
    @State private var panBase: ClosedRange<Double>? = nil

    /// Two-finger sideways scroll of the zoomed window: finger moves right → earlier times (like a map).
    private func panBy(_ dx: CGFloat, _ plot: CGRect) {
        guard app.charts.isZoomed, let b = panBase, plot.width > 1 else { return }
        let w: Double = b.upperBound - b.lowerBound
        let dt: Double = -Double(dx / plot.width) * w
        app.charts.setViewport(b.lowerBound + dt, b.upperBound + dt, refresh: false)
    }

    var body: some View {
        GeometryReader { (geo: GeometryProxy) in
            let plot: CGRect = proxy.plotFrame.map { geo[$0] } ?? CGRect(origin: .zero, size: geo.size)
            ZStack(alignment: .topLeading) {
                // two fingers sideways = scroll the zoomed window (UIKit: SwiftUI on iPadOS 17 has no two-finger drag)
                // also: Apple Pencil double tap (side of the pencil) = remove the selected stretch
                if zoomable {
                    TwoFingerPan(onBegan: { panBase = domain },
                                 onChanged: { (dx: CGFloat) in panBy(dx, plot) },
                                 onEnded: { panBase = nil; app.charts.scheduleDisplay(delayMs: 0) },
                                 onPencilDoubleTap: { clearRangeIfAny() })
                }
                if scrollFriendly {
                    // recognised together with the ScrollView pan so vertical swipes still scroll the page
                    Color.clear
                        .contentShape(Rectangle())
                        .simultaneousGesture(dragGesture(plot))
                        .simultaneousGesture(pinchGesture(), including: zoomable ? .all : .subviews)
                } else {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(dragGesture(plot))
                        .simultaneousGesture(pinchGesture(), including: zoomable ? .all : .subviews)
                }
                rangeView(plot).allowsHitTesting(false)
                cursorView(plot).allowsHitTesting(false)
            }
            // double tap with a finger on the chart = remove the selected stretch
            .simultaneousGesture(TapGesture(count: 2).onEnded { clearRangeIfAny() })
        }
    }

    private func clearRangeIfAny() {
        guard app.rangeStart.isFinite || app.rangeEnd.isFinite else { return }
        app.charts.clearRange()
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func timeAt(_ x: CGFloat, _ plot: CGRect) -> Double {
        let v: Double? = proxy.value(atX: x - plot.minX, as: Double.self)
        let t: Double = v ?? domain.lowerBound
        return min(max(t, domain.lowerBound), domain.upperBound)
    }

    private func xOf(_ t: Double, _ plot: CGRect) -> CGFloat? {
        guard t.isFinite, let p = proxy.position(forX: t) else { return nil }
        return plot.minX + p
    }

    @ViewBuilder
    private func rangeView(_ plot: CGRect) -> some View {
        if app.rangeStart.isFinite && app.rangeEnd.isFinite,
           let a = xOf(min(app.rangeStart, app.rangeEnd), plot), let b = xOf(max(app.rangeStart, app.rangeEnd), plot) {
            let x0: CGFloat = max(a, plot.minX)
            let x1: CGFloat = min(b, plot.maxX)
            if x1 > x0 {
                Rectangle()
                    .fill(Avo.red.opacity(0.14))
                    .overlay(Rectangle().stroke(Avo.red.opacity(0.55), lineWidth: 1))
                    .frame(width: x1 - x0, height: plot.height)
                    .position(x: (x0 + x1) / 2, y: plot.midY)
            }
        }
    }

    @ViewBuilder
    private func cursorView(_ plot: CGRect) -> some View {
        if let x = xOf(app.cursorTime, plot), x >= plot.minX - 0.5, x <= plot.maxX + 0.5 {
            Rectangle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 1.5, height: plot.height)
                .position(x: x, y: plot.midY)
        }
    }

    private func dragGesture(_ plot: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { (v: DragGesture.Value) in
                let t: Double = timeAt(v.location.x, plot)
                // a gesture cancelled by the scroll view may never call onEnded: a new start point = a new gesture
                if dragBegan != nil && v.startLocation != dragStart {
                    dragBegan = nil
                    dragMode = 0
                }
                if dragBegan == nil {
                    dragBegan = v.time
                    dragStart = v.startLocation
                    anchorT = timeAt(v.startLocation.x, plot)
                    dragMode = app.charts.rangeMode ? 2 : 0
                    // inside a scroll view the cursor moves on tap-up / horizontal drag, not on touch-down
                    if dragMode == 0 && !scrollFriendly { app.cursorTime = anchorT }
                }
                if dragMode == 0 {
                    let dx: CGFloat = abs(v.translation.width)
                    let dy: CGFloat = abs(v.translation.height)
                    if scrollFriendly && dy > 10 && dy > dx {
                        dragMode = 3
                    } else if dx > 8 {
                        let held: TimeInterval = v.time.timeIntervalSince(dragBegan ?? v.time)
                        dragMode = held > 0.45 ? 2 : 1
                        if dragMode == 2 { UISelectionFeedbackGenerator().selectionChanged() }
                    }
                }
                if dragMode == 1 {
                    app.cursorTime = t
                    // zoomed: dragging the cursor against an edge scrolls the window that way
                    if app.charts.isZoomed {
                        if v.location.x >= plot.maxX - 14 { app.charts.pan(0.03) }
                        else if v.location.x <= plot.minX + 14 { app.charts.pan(-0.03) }
                    }
                } else if dragMode == 2 {
                    app.rangeStart = anchorT
                    app.rangeEnd = t
                }
            }
            .onEnded { (v: DragGesture.Value) in
                let t: Double = timeAt(v.location.x, plot)
                if dragMode == 0 {
                    app.cursorTime = t
                } else if dragMode == 2 {
                    if abs(t - anchorT) <= 0.5 { app.rangeStart = .nan; app.rangeEnd = .nan }
                    app.charts.refreshRangeStats()
                }
                dragBegan = nil
                dragMode = 0
            }
    }

    private func pinchGesture() -> some Gesture {
        MagnifyGesture()
            .onChanged { (v: MagnifyGesture.Value) in
                if pinchBase == nil { pinchBase = domain }
                guard let b = pinchBase else { return }
                let f: Double = 1.0 / max(Double(v.magnification), 0.05)
                let ax: Double = min(max(Double(v.startAnchor.x), 0), 1)
                let at: Double = b.lowerBound + ax * (b.upperBound - b.lowerBound)
                app.charts.setViewport(at - (at - b.lowerBound) * f, at + (b.upperBound - at) * f, refresh: false)
            }
            .onEnded { (_: MagnifyGesture.Value) in
                pinchBase = nil
                app.charts.scheduleDisplay(delayMs: 0)
            }
    }
}
