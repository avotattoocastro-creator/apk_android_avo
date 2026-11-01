import SwiftUI
import UIKit
import Charts

// MARK: - Charts page (Windows Views/ChartsView.xaml)

/// Synchronised scientific charts. All charts share the x window, the cursor and the selected range with the map.
/// Touch: tap/drag = cursor · hold then drag (or «Seleccionar rango») = range · pinch = zoom.
struct ChartsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let charts: ChartsModel = app.charts
        GeometryReader { geo in
            let wide: Bool = geo.size.width >= 900
            VStack(alignment: .leading, spacing: 10) {
                AvoPageTitle(title: "Gráficas",
                             subtitle: app.selected.map { $0.summary } ?? "Sin entrenamiento seleccionado · importa un archivo .avo o .avr")
                if app.selected == nil {
                    AvoCard { AvoNoData(text: "Selecciona un entrenamiento para ver las gráficas") }
                    Spacer(minLength: 0)
                } else if wide {
                    HStack(alignment: .top, spacing: 12) {
                        ChartsColumn(charts: charts)
                        ScrollView { ChartsSidePanel(charts: charts) }
                            .frame(width: 300)
                    }
                } else {
                    VStack(spacing: 10) {
                        ChartsColumn(charts: charts)
                            .frame(maxHeight: .infinity)
                        ScrollView { ChartsSidePanel(charts: charts) }
                            .frame(height: max(220, geo.size.height * 0.34))
                    }
                }
            }
            .padding(16)
        }
        .background(Avo.bg)
        .background(ChartsRangeWatcher())
        .onAppear { app.charts.pageShown() }
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

private struct ChartsColumn: View {
    @Environment(AppModel.self) private var app
    let charts: ChartsModel

    var body: some View {
        let d: ClosedRange<Double> = charts.domain
        VStack(spacing: 8) {
            ChartsToolbar(charts: charts)
            if charts.chartSpeed {
                SyncChartBox(title: "Velocidad (km/h)",
                             legend: [SyncLegend("Filtrada", Avo.red), SyncLegend("Reportada", Avo.blue), SyncLegend("Derivada", Avo.silver),
                                      SyncLegend("±1σ", Avo.red.opacity(0.35)), SyncLegend("Calidad RTK (banda)", Avo.ok)],
                             readout: { (a: AppModel) -> String in a.cursorSpeed + " km/h" }) {
                    SyncSignalChart(panel: charts.panel(.speed), domain: d, bands: charts.qualityBands, includeZero: true)
                }
                .frame(minHeight: 150, maxHeight: .infinity)
                .layoutPriority(1)
            }
            if charts.chartAccel {
                SyncChartBox(title: "Aceleración (m/s²)",
                             legend: [SyncLegend("Longitudinal", Avo.warn), SyncLegend("Lateral", Avo.cyan)],
                             readout: { (a: AppModel) -> String in a.cursorAccel + " m/s²" }) {
                    SyncSignalChart(panel: charts.panel(.accel), domain: d, includeZero: true, emptyText: "Sin aceleración validada")
                }
                .frame(minHeight: 110, maxHeight: .infinity)
            }
            if charts.chartImu && charts.hasImuRaw {
                SyncChartBox(title: charts.imuChartHeader,
                             legend: [SyncLegend("Izquierda", Avo.blue), SyncLegend("Central", Avo.ok), SyncLegend("Derecha", Avo.warn)]) {
                    SyncSignalChart(panel: charts.panel(.imu), domain: d, bands: charts.gaitBands, includeZero: false,
                                    emptyText: "Sin datos de cincha en esta sesión")
                }
                .frame(minHeight: 110, maxHeight: .infinity)
            }
            if charts.chartFused && charts.hasFused {
                HStack(spacing: 8) {
                    SyncChartBox(title: "Cincha · aceleración sin gravedad (m/s², ejes del mundo)",
                                 legend: [SyncLegend("Vertical", Avo.red), SyncLegend("Horizontal", Avo.cyan)]) {
                        SyncSignalChart(panel: charts.panel(.fusedAccel), domain: d, bands: charts.gaitBands, includeZero: true)
                    }
                    SyncChartBox(title: "Cincha · orientación (°)",
                                 legend: [SyncLegend("Balanceo", Avo.warn), SyncLegend("Cabeceo", ChartsModel.violet)]) {
                        SyncSignalChart(panel: charts.panel(.orientation), domain: d, includeZero: false)
                    }
                }
                .frame(minHeight: 110, maxHeight: .infinity)
            }
            let showCad: Bool = charts.chartCadence && charts.hasCadence
            let showAlt: Bool = charts.chartAltitude && charts.hasAltitude
            if showCad || showAlt {
                HStack(spacing: 8) {
                    if showCad {
                        SyncChartBox(title: "Cadencia (motor AVO, ciclos/min)",
                                     legend: [SyncLegend("Izquierda", Avo.blue), SyncLegend("Central", Avo.ok), SyncLegend("Derecha", Avo.warn)],
                                     readout: { (a: AppModel) -> String in a.cursorCadence }) {
                            SyncSignalChart(panel: charts.panel(.cadence), domain: d, bands: charts.gaitBands, includeZero: false,
                                            emptyText: "El motor no ha encontrado ciclos de marcha")
                        }
                    }
                    if showAlt {
                        SyncChartBox(title: "Altitud (m)", legend: [SyncLegend("GNSS (nivel medio del mar)", Avo.ok)],
                                     readout: { (a: AppModel) -> String in a.cursorAltitude + " m" }) {
                            SyncSignalChart(panel: charts.panel(.altitude), domain: d, includeZero: false)
                        }
                    }
                }
                .frame(minHeight: 100, maxHeight: .infinity)
            }
            if charts.chartPrecision {
                HStack(spacing: 8) {
                    SyncChartBox(title: "Precisión horizontal hAcc (m)", legend: [SyncLegend("hAcc reportada", ChartsModel.violet)]) {
                        SyncSignalChart(panel: charts.panel(.precision), domain: d, bands: charts.qualityBands, includeZero: true)
                    }
                    SyncChartBox(title: "Satélites", legend: [SyncLegend("Satélites usados", Avo.silver)]) {
                        SyncSignalChart(panel: charts.panel(.satellites), domain: d, includeZero: true)
                    }
                }
                .frame(minHeight: 100, maxHeight: .infinity)
            }
        }
    }
}

private struct ChartsToolbar: View {
    @Environment(AppModel.self) private var app
    let charts: ChartsModel

    var body: some View {
        @Bindable var c = charts
        HStack(spacing: 8) {
            Toggle(isOn: $c.rangeMode) {
                Label("Seleccionar rango", systemImage: "arrow.left.and.right.square")
            }
            .toggleStyle(.button)
            .tint(Avo.red)
            .accessibilityIdentifier("charts.rangeMode")
            Divider().frame(height: 22)
            Button { charts.zoom(1.5) } label: { Image(systemName: "minus.magnifyingglass") }
                .buttonStyle(.avoSecondary).accessibilityLabel("Alejar")
            Button { charts.zoom(1 / 1.5) } label: { Image(systemName: "plus.magnifyingglass") }
                .buttonStyle(.avoSecondary).accessibilityLabel("Acercar")
            Button { charts.pan(-0.4) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.avoSecondary).disabled(!charts.isZoomed).accessibilityLabel("Desplazar a la izquierda")
            Button { charts.pan(0.4) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.avoSecondary).disabled(!charts.isZoomed).accessibilityLabel("Desplazar a la derecha")
            Button("Restablecer zoom") { charts.resetZoom() }
                .buttonStyle(.avoSecondary).disabled(!charts.isZoomed)
                .accessibilityIdentifier("charts.resetZoom")
            if charts.building { ProgressView().controlSize(.small) }
            Spacer(minLength: 8)
            SyncPlaybackBar(compact: true)
        }
    }
}

private struct ChartsSidePanel: View {
    @Environment(AppModel.self) private var app
    let charts: ChartsModel
    @State private var csvURL: URL? = nil
    @State private var exporting: Bool = false

    var body: some View {
        @Bindable var c = charts
        VStack(alignment: .leading, spacing: 10) {
            AvoCard(title: "Selección de tramo") {
                if !app.hasRange {
                    Text("Mantén pulsado y arrastra en una gráfica (o activa «Seleccionar rango» y arrastra) para seleccionar un intervalo.")
                        .font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                }
                SyncKeyValueRows(rows: charts.rangeStats)
                SyncFlowButtons {
                    Button("Guardar como tramo") { app.segments.addFromRange() }
                        .buttonStyle(.avoPrimary).disabled(!app.hasRange)
                    Button("Quitar selección") { charts.clearRange() }
                        .buttonStyle(.avoSecondary).disabled(!app.hasRange)
                    Button(exporting ? "Preparando…" : "Exportar CSV") { exportCsv() }
                        .buttonStyle(.avoSecondary).disabled(exporting)
                }
                if let url = csvURL {
                    ShareLink(item: url) {
                        Label("Compartir \(url.lastPathComponent)", systemImage: "square.and.arrow.up")
                            .font(.caption)
                    }
                }
            }
            AvoCard(title: "Mostrar datos") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Velocidad", isOn: $c.chartSpeed)
                    Toggle("Aceleración", isOn: $c.chartAccel)
                    Toggle(charts.hasImuRaw ? "IMU cincha" : "IMU cincha (sin datos)", isOn: $c.chartImu).disabled(!charts.hasImuRaw)
                    Toggle("Movimiento de la cincha (sin gravedad y orientación)", isOn: $c.chartFused).disabled(!charts.hasFused)
                    Toggle(charts.hasCadence ? "Cadencia (motor)" : "Cadencia (motor, sin datos)", isOn: $c.chartCadence).disabled(!charts.hasCadence)
                    Toggle(charts.hasAltitude ? "Altitud" : "Altitud (sin datos)", isOn: $c.chartAltitude).disabled(!charts.hasAltitude)
                    Toggle("Precisión GNSS", isOn: $c.chartPrecision)
                    Divider().overlay(Avo.line)
                    Text("VELOCIDAD").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim)
                    Toggle("Filtrada (Kalman + RTS)", isOn: $c.showSpeedFiltered)
                    Toggle("Banda ±1σ de la filtrada", isOn: $c.showSigma).disabled(!charts.showSpeedFiltered)
                    Toggle("Reportada por el receptor", isOn: $c.showSpeedReported)
                    Toggle("Derivada de posiciones", isOn: $c.showSpeedDerived)
                    Toggle("Aceleración lateral", isOn: $c.showLateral)
                    Button("Ver todo (restablecer zoom)") { charts.resetZoom() }
                        .buttonStyle(.avoSecondary).padding(.top, 4)
                }
                .font(.callout)
                .tint(Avo.red)
            }
            AvoCard(title: "Filtrado y unidades") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(charts.filterDescription)
                    Text("La señal original se conserva: la velocidad reportada y la derivada de posiciones se pueden mostrar sin filtrar. Las aceleraciones solo se muestran con σ ≤ 0,8 m/s², solución ≥ DGNSS y sin cortes.")
                    Text(charts.imuScaleNote)
                }
                .font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            }
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
    var id: String { text }
    init(_ text: String, _ color: Color) { self.text = text; self.color = color }
}

/// Windows AvoChartPanel: header, legend, cursor readout and the chart.
struct SyncChartBox<Content: View>: View {
    var title: String
    var legend: [SyncLegend] = []
    var readout: ((AppModel) -> String)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(title.uppercased()).font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.silver).lineLimit(1)
                ForEach(legend) { l in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1).fill(l.color).frame(width: 12, height: 3)
                        Text(l.text).font(.caption2).foregroundStyle(Avo.textDim).lineLimit(1)
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

    var body: some View {
        if panel.isEmpty {
            AvoNoData(text: emptyText)
                .frame(maxHeight: .infinity)
        } else {
            SyncChartPlot(panel: panel, domain: domain, bands: bands, includeZero: includeZero, zoomable: zoomable)
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

    static func clockLabel(_ value: AxisValue) -> String {
        guard let d = value.as(Double.self) else { return "" }
        return TimeText.clock(d)
    }

    var body: some View {
        Chart {
            ForEach(panel.sigma) { (s: SyncSigma) in
                RectangleMark(xStart: .value("t", s.x0), xEnd: .value("t", s.x1), yStart: .value("v", s.lo), yEnd: .value("v", s.hi))
                    .foregroundStyle(Avo.red.opacity(0.16))
            }
            ForEach(panel.lines) { (line: SyncLine) in
                ForEach(line.points) { (p: SyncPoint) in
                    LineMark(x: .value("t", p.x), y: .value("v", p.y), series: .value("serie", line.id))
                        .foregroundStyle(line.color)
                        .lineStyle(StrokeStyle(lineWidth: line.width, dash: line.dashed ? [4, 3] : []))
                        .interpolationMethod(.linear)
                }
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
            SyncChartCursorLayer(proxy: proxy, domain: domain, zoomable: zoomable)
        }
        .environment(\.locale, Locale(identifier: "es_ES"))
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
                    ctx.fill(Path(CGRect(x: x0, y: plot.maxY - 4, width: x1 - x0, height: 4)), with: .color(b.color))
                }
            }
            .allowsHitTesting(false)
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

    @State private var dragBegan: Date? = nil
    /// 0 undecided (tap), 1 cursor, 2 range.
    @State private var dragMode: Int = 0
    @State private var anchorT: Double = .nan
    @State private var pinchBase: ClosedRange<Double>? = nil

    var body: some View {
        GeometryReader { (geo: GeometryProxy) in
            let plot: CGRect = proxy.plotFrame.map { geo[$0] } ?? CGRect(origin: .zero, size: geo.size)
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(dragGesture(plot))
                    .simultaneousGesture(pinchGesture(), including: zoomable ? .all : .subviews)
                rangeView(plot).allowsHitTesting(false)
                cursorView(plot).allowsHitTesting(false)
            }
        }
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
                if dragBegan == nil {
                    dragBegan = v.time
                    anchorT = timeAt(v.startLocation.x, plot)
                    dragMode = app.charts.rangeMode ? 2 : 0
                    if dragMode == 0 { app.cursorTime = anchorT }
                }
                if dragMode == 0 && abs(v.translation.width) > 8 {
                    let held: TimeInterval = v.time.timeIntervalSince(dragBegan ?? v.time)
                    dragMode = held > 0.45 ? 2 : 1
                    if dragMode == 2 { UISelectionFeedbackGenerator().selectionChanged() }
                }
                if dragMode == 1 {
                    app.cursorTime = t
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
