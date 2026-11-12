import SwiftUI
import UIKit
import MapKit
import Charts

/// Training comparison (Windows Views/CompareView.xaml): sessions to compare on the left; on the right a fixed toolbar
/// (shared zoom / range of every compare chart) and ONE vertical scroll with full-width blocks: overlaid routes, aligned
/// speed, validated acceleration, girth IMU (lateral deviation, tilts), engine cadence, comparative statistics and the
/// engine comparison of two sessions.
/// Touch on the charts: pinch = zoom (all charts) · horizontal drag = pan when zoomed · hold then drag (or «Seleccionar
/// rango») = range · double tap = reset zoom · vertical swipe = scroll.
struct CompareView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        let model: CompareModel = app.compare
        VStack(alignment: .leading, spacing: 12) {
            AvoPageTitle(title: "Comparar entrenamientos",
                         subtitle: "Series alineadas por tiempo relativo o distancia; sin interpolar a través de huecos sin datos")
            if hSize == .compact {
                VStack(alignment: .leading, spacing: 10) {
                    CompareChartToolbar(model: model)
                    if model.hasRange { CompareRangeCard(model: model) }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            CompareSessionPicker(model: model)
                            CompareResults(model: model)
                        }
                    }
                    // while «Seleccionar rango» is on, a drag on a chart must select, never scroll
                    .scrollDisabled(model.rangeMode)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    ScrollView { CompareSessionPicker(model: model) }
                        .frame(width: 300)
                    VStack(alignment: .leading, spacing: 10) {
                        CompareChartToolbar(model: model)
                        if model.hasRange { CompareRangeCard(model: model) }
                        ScrollView { CompareResults(model: model).padding(.bottom, 24) }
                            .scrollDisabled(model.rangeMode)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Avo.bg)
        .onAppear { model.pageShown() }
    }
}

/// «Entrenamientos a comparar» card: filter, list with check boxes and colour, alignment, actions and verdict.
private struct CompareSessionPicker: View {
    @Environment(AppModel.self) private var app
    var model: CompareModel

    var body: some View {
        @Bindable var m = model
        let all: [SessionItem] = app.sessionsView
        let list: [SessionItem] = model.listed(all)
        AvoCard(title: "Entrenamientos a comparar") {
            Toggle(isOn: $m.hideEmpty) {
                Text("Ocultar entrenamientos sin recorrido (0 km)").font(.caption).foregroundStyle(Avo.text)
            }
            .tint(Avo.red)
            .accessibilityIdentifier("compare.hideEmpty")
            if model.hideEmpty && all.count > list.count {
                Text("\(all.count - list.count) ocultos sin recorrido; no se incluyen en la comparación.")
                    .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            }
            if all.isEmpty {
                AvoNoData(text: "Sin entrenamientos importados")
            } else if list.isEmpty {
                AvoNoData(text: "Ningún entrenamiento con recorrido")
            } else {
                VStack(spacing: 2) {
                    ForEach(list) { (s: SessionItem) in
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

// MARK: Toolbar (shared zoom / pan / range of every compare chart)

struct CompareChartToolbar: View {
    var model: CompareModel

    private var rangeBinding: Binding<Bool> {
        Binding(get: { model.rangeMode }, set: { (v: Bool) in model.rangeMode = v })
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                controls
                Spacer(minLength: 8)
                info
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    controls
                    Spacer(minLength: 0)
                }
                info
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        Toggle(isOn: rangeBinding) {
            Label("Seleccionar rango", systemImage: "arrow.left.and.right.square")
        }
        .toggleStyle(.button)
        .tint(Avo.red)
        .fixedSize()
        .accessibilityIdentifier("compare.rangeMode")
        Divider().frame(height: 22)
        Button { model.zoom(1.5) } label: { Text("−").font(.headline).frame(minWidth: 18) }
            .buttonStyle(.avoSecondary).accessibilityLabel("Alejar")
            .accessibilityIdentifier("compare.zoomOut")
        Button { model.zoom(1 / 1.5) } label: { Text("+").font(.headline).frame(minWidth: 18) }
            .buttonStyle(.avoSecondary).accessibilityLabel("Acercar")
            .accessibilityIdentifier("compare.zoomIn")
        Button { model.pan(-0.4) } label: { Text("◀").frame(minWidth: 18) }
            .buttonStyle(.avoSecondary).disabled(!model.isZoomed).accessibilityLabel("Desplazar a la izquierda")
        Button { model.pan(0.4) } label: { Text("▶").frame(minWidth: 18) }
            .buttonStyle(.avoSecondary).disabled(!model.isZoomed).accessibilityLabel("Desplazar a la derecha")
        Button("Restablecer zoom") { model.resetZoom() }
            .buttonStyle(.avoSecondary).disabled(!model.isZoomed).fixedSize()
            .accessibilityIdentifier("compare.resetZoom")
    }

    private var info: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(model.isZoomed ? "Ventana \(model.domainText)" : "Vista completa · \(model.domainText)")
                .font(.caption.monospacedDigit()).foregroundStyle(Avo.cyan).lineLimit(1)
            Text("Pellizca para ampliar · doble toque restablece · mantén pulsado y arrastra para seleccionar")
                .font(.caption2).foregroundStyle(Avo.textDim).lineLimit(1)
        }
    }
}

// MARK: «Tramo seleccionado»

struct CompareRangeCard: View {
    var model: CompareModel

    var body: some View {
        let reached: Int = model.rangeRows.filter { $0.t0.isFinite }.count
        let by: String = model.alignment == .distance ? "distancia desde el inicio" : "tiempo relativo"
        let subtitle: String = model.rangeText + " · alineado por " + by
        AvoCard(title: "Tramo seleccionado",
                subtitle: subtitle,
                padding: 12) {
            FeatureTable(headers: ["Entrenamiento", "Distancia", "Duración", "V. media", "V. máx", "Acel. máx", "Frenada máx", "Observaciones"],
                         widths: [190, 80, 70, 80, 80, 85, 90, 300],
                         rows: model.rangeRows.map { (r: CompareRangeRow) -> [String] in
                             [r.label, r.distance, r.duration, r.meanSpeed, r.maxSpeed, r.maxAccel, r.maxDecel, r.observations]
                         },
                         colors: model.rangeRows.map { (r: CompareRangeRow) -> Color? in r.color },
                         emptyText: "Calculando…")
            HStack(spacing: 8) {
                Button("Guardar como tramo en los \(reached) entrenamientos") { model.saveRangeAsSegments() }
                    .buttonStyle(.avoPrimary).disabled(reached == 0).fixedSize()
                    .accessibilityIdentifier("compare.saveSegments")
                Button("Ampliar al tramo") { model.zoomToRange() }
                    .buttonStyle(.avoSecondary).fixedSize()
                Button("Quitar selección") { model.clearRange() }
                    .buttonStyle(.avoSecondary).fixedSize()
                    .accessibilityIdentifier("compare.clearRange")
                Spacer(minLength: 0)
            }
            if !model.rangeMessage.isEmpty {
                Text(model.rangeMessage).font(.caption2).foregroundStyle(Avo.ok).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: Results column

struct CompareResults: View {
    @Environment(AppModel.self) private var app
    var model: CompareModel
    /// Altura del mapa de recorridos (página Comparar 340; Análisis con «Entreno 2», más grande).
    var mapHeight: CGFloat = 340

    private var empty: String { model.computing ? "Calculando…" : "Marca entrenamientos para compararlos" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1) overlaid routes (a Map inside a ScrollView needs an explicit height)
            CompareMap(model: model)
                .frame(maxWidth: .infinity)
                .frame(height: mapHeight)
            // 2) speed
            FeatureChartPanel(title: "Velocidad comparada (km/h)", minHeight: 240) {
                CompareChart(model: model, series: model.speedSeries, includeZero: true, emptyText: empty)
            }
            // 3) validated acceleration
            FeatureChartPanel(title: "Aceleración longitudinal validada (m/s²)", minHeight: 220) {
                CompareChart(model: model, series: model.accelSeries, includeZero: true, emptyText: empty)
            }
            // 4) girth IMU
            FeatureChartPanel(title: "IMU cincha → Desvíos laterales (m/s²)", minHeight: 220) {
                VStack(alignment: .leading, spacing: 6) {
                    CompareChart(model: model, series: model.lateralSeries, includeZero: true,
                                 emptyText: model.computing ? "Calculando…" : "Sin datos de cincha (IMU)")
                        .frame(minHeight: 200)
                    Text("Aceleración horizontal perpendicular al eje longitudinal del caballo (eje X de la cincha, montaje no verificado), media por época. Positivo = hacia la izquierda.")
                        .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                    imuNotes
                }
            }
            FeatureChartPanel(title: "IMU cincha → Inclinaciones (°)", minHeight: 220) {
                VStack(alignment: .leading, spacing: 6) {
                    CompareChart(model: model, series: model.tiltSeries, includeZero: true,
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
                        CompareChart(model: model, series: model.cadenceSeries, includeZero: false, emptyText: "Sin datos")
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

// MARK: Chart with the shared x window and range

/// Line chart of the comparison: x domain = the shared window of CompareModel, so every chart zooms together.
private struct CompareChart: View {
    var model: CompareModel
    var series: [FeatureLineSeries]
    var includeZero: Bool
    var emptyText: String

    private var hasData: Bool {
        for s in series where !s.points.isEmpty { return true }
        return false
    }

    var body: some View {
        if !hasData {
            AvoNoData(text: emptyText)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                plot.frame(minHeight: 170)
                if series.count > 1 { FeatureLegend(items: series.map { (name: $0.name, color: $0.color) }) }
            }
        }
    }

    /// Y range of the points inside the window (so a zoom also rescales the values).
    private func yDomain(_ xd: ClosedRange<Double>) -> ClosedRange<Double> {
        var a: Double = .infinity
        var b: Double = -.infinity
        for s in series {
            for p in s.points where p.x >= xd.lowerBound && p.x <= xd.upperBound {
                if p.y < a { a = p.y }
                if p.y > b { b = p.y }
            }
        }
        if !a.isFinite || !b.isFinite {
            for s in series where !s.points.isEmpty { a = min(a, s.yMin); b = max(b, s.yMax) }
        }
        if !a.isFinite || !b.isFinite { return 0...1 }
        if includeZero { a = min(a, 0); b = max(b, 0) }
        if b - a < 1e-9 { a -= 1; b += 1 }
        let pad: Double = (b - a) * 0.06
        return (a - pad)...(b + pad)
    }

    private var plot: some View {
        let xd: ClosedRange<Double> = model.domain
        let yd: ClosedRange<Double> = yDomain(xd)
        let ax: FeatureAxis = model.axis
        let m: CompareModel = model
        return Chart {
            ForEach(series) { (s: FeatureLineSeries) in
                ForEach(s.points) { (p: FeaturePlotPoint) in
                    LineMark(x: .value("x", p.x), y: .value("y", p.y), series: .value("serie", p.run))
                        .foregroundStyle(s.color)
                        .lineStyle(StrokeStyle(lineWidth: s.width, dash: s.dashed ? [5, 3] : []))
                        .interpolationMethod(.linear)
                }
            }
        }
        .chartXScale(domain: xd)
        .chartYScale(domain: yd)
        .chartPlotStyle { plot in plot.clipped() }
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisGridLine().foregroundStyle(Avo.line)
                AxisValueLabel {
                    if let d = value.as(Double.self) { Text(ax.label(d)).font(.caption2).foregroundStyle(Avo.textDim) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                AxisGridLine().foregroundStyle(Avo.line)
                AxisValueLabel {
                    if let d = value.as(Double.self) { Text(DotNetFormat.custom(d, "0.##", spanish: true)).font(.caption2).foregroundStyle(Avo.textDim) }
                }
            }
        }
        .chartOverlay { (proxy: ChartProxy) in
            CompareTouchLayer(proxy: proxy, model: m)
        }
    }
}

/// Selected range and touch handling of a compare chart (same interaction as «Gráficas»): pinch = zoom of all the
/// charts, horizontal drag = pan when zoomed, hold then drag (or «Seleccionar rango») = range, double tap = reset zoom,
/// mainly vertical swipe = scroll of the page.
private struct CompareTouchLayer: View {
    let proxy: ChartProxy
    let model: CompareModel

    @State private var dragBegan: Date? = nil
    @State private var dragStart: CGPoint = .zero
    /// 0 undecided, 1 pan, 2 range, 3 vertical swipe (scroll, ignored).
    @State private var dragMode: Int = 0
    @State private var anchorX: Double = .nan
    @State private var panBase: ClosedRange<Double>? = nil
    @State private var pinchBase: ClosedRange<Double>? = nil

    var body: some View {
        GeometryReader { (geo: GeometryProxy) in
            let plot: CGRect = proxy.plotFrame.map { geo[$0] } ?? CGRect(origin: .zero, size: geo.size)
            ZStack(alignment: .topLeading) {
                // recognised together with the ScrollView pan so vertical swipes still scroll the page
                Color.clear
                    .contentShape(Rectangle())
                    .simultaneousGesture(dragGesture(plot))
                    .simultaneousGesture(pinchGesture())
                    .simultaneousGesture(TapGesture(count: 2).onEnded { model.resetZoom() })
                rangeView(plot).allowsHitTesting(false)
            }
        }
    }

    private func valueAt(_ x: CGFloat, _ plot: CGRect) -> Double {
        let d: ClosedRange<Double> = model.domain
        let v: Double? = proxy.value(atX: x - plot.minX, as: Double.self)
        let t: Double = v ?? d.lowerBound
        return min(max(t, d.lowerBound), d.upperBound)
    }

    private func xOf(_ t: Double, _ plot: CGRect) -> CGFloat? {
        guard t.isFinite, let p = proxy.position(forX: t) else { return nil }
        return plot.minX + p
    }

    @ViewBuilder
    private func rangeView(_ plot: CGRect) -> some View {
        if model.rangeStart.isFinite && model.rangeEnd.isFinite,
           let a = xOf(min(model.rangeStart, model.rangeEnd), plot), let b = xOf(max(model.rangeStart, model.rangeEnd), plot) {
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

    private func dragGesture(_ plot: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { (v: DragGesture.Value) in
                // a gesture cancelled by the scroll view may never call onEnded: a new start point = a new gesture
                if dragBegan != nil && v.startLocation != dragStart {
                    dragBegan = nil
                    dragMode = 0
                }
                if dragBegan == nil {
                    dragBegan = v.time
                    dragStart = v.startLocation
                    anchorX = valueAt(v.startLocation.x, plot)
                    panBase = model.domain
                    dragMode = model.rangeMode ? 2 : 0
                }
                if dragMode == 0 {
                    let dx: CGFloat = abs(v.translation.width)
                    let dy: CGFloat = abs(v.translation.height)
                    if dy > 10 && dy > dx {
                        dragMode = 3
                    } else if dx > 8 {
                        let held: TimeInterval = v.time.timeIntervalSince(dragBegan ?? v.time)
                        dragMode = held > 0.45 ? 2 : 1
                        if dragMode == 2 { UISelectionFeedbackGenerator().selectionChanged() }
                    }
                }
                if dragMode == 1 {
                    if model.isZoomed, let b = panBase, plot.width > 0 {
                        let w: Double = b.upperBound - b.lowerBound
                        let shift: Double = -Double(v.translation.width / plot.width) * w
                        model.setViewport(b.lowerBound + shift, b.upperBound + shift, rebuild: false)
                    }
                } else if dragMode == 2 {
                    model.setRange(anchorX, valueAt(v.location.x, plot))
                }
            }
            .onEnded { (_: DragGesture.Value) in
                if dragMode == 2 {
                    model.finishRange()
                } else if dragMode == 1 {
                    model.rebuildVisible()
                }
                dragBegan = nil
                dragMode = 0
                panBase = nil
            }
    }

    private func pinchGesture() -> some Gesture {
        MagnifyGesture()
            .onChanged { (v: MagnifyGesture.Value) in
                if pinchBase == nil { pinchBase = model.domain }
                guard let b = pinchBase else { return }
                let f: Double = 1.0 / max(Double(v.magnification), 0.05)
                let ax: Double = min(max(Double(v.startAnchor.x), 0), 1)
                let at: Double = b.lowerBound + ax * (b.upperBound - b.lowerBound)
                model.setViewport(at - (at - b.lowerBound) * f, at + (b.upperBound - at) * f, rebuild: false)
            }
            .onEnded { (_: MagnifyGesture.Value) in
                pinchBase = nil
                model.rebuildVisible()
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

/// «Recorridos superpuestos»: every compared route in its comparison colour; the selected range is highlighted on each
/// route. Buttons: fit all, zoom in / out and fit the selected range.
struct CompareMap: View {
    @Environment(AppModel.self) private var app
    var model: CompareModel
    @State private var position: MapCameraPosition = .automatic
    @State private var region: MKCoordinateRegion? = nil

    /// Explícito: los `@State` privados harían privado el inicializador por miembros (se usa también en Análisis).
    init(model: CompareModel) { self.model = model }

    var body: some View {
        let dim: Double = model.rangeTracks.isEmpty ? 1.0 : 0.4
        ZStack(alignment: .topLeading) {
            if model.tracks.isEmpty {
                Avo.surface
                AvoNoData(text: "Marca entrenamientos para compararlos").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Map(position: $position) {
                    ForEach(model.tracks) { (t: CompareTrack) in
                        ForEach(0..<t.runs.count, id: \.self) { (k: Int) in
                            MapPolyline(coordinates: t.runs[k]).stroke(t.color.opacity(dim), lineWidth: 3)
                        }
                    }
                    ForEach(model.rangeTracks) { (t: CompareTrack) in
                        ForEach(0..<t.runs.count, id: \.self) { (k: Int) in
                            MapPolyline(coordinates: t.runs[k]).stroke(Color.white, lineWidth: 8)
                        }
                    }
                    ForEach(model.rangeTracks) { (t: CompareTrack) in
                        ForEach(0..<t.runs.count, id: \.self) { (k: Int) in
                            MapPolyline(coordinates: t.runs[k]).stroke(t.color, lineWidth: 5)
                        }
                    }
                }
                .mapStyle(app.settings.map == .vectorOffline ? MapStyle.standard : MapStyle.imagery)
                .onMapCameraChange(frequency: .onEnd) { (ctx: MapCameraUpdateContext) in
                    region = ctx.region
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text("Recorridos superpuestos")
                .font(.callout.weight(.semibold)).foregroundStyle(Avo.text)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Avo.bg.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
                .padding(10)
            if !model.tracks.isEmpty {
                HStack {
                    Spacer(minLength: 0)
                    VStack(spacing: 6) {
                        mapButton("arrow.up.left.and.arrow.down.right", "Ajustar recorridos") { fit(model.tracks) }
                        mapButton("plus", "Acercar mapa") { zoomMap(0.5) }
                        mapButton("minus", "Alejar mapa") { zoomMap(2) }
                        if !model.rangeTracks.isEmpty {
                            mapButton("scope", "Ajustar al tramo seleccionado") { fit(model.rangeTracks) }
                        }
                    }
                    .padding(10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Avo.line, lineWidth: 1))
        .onAppear { fit(model.tracks) }
        .onChange(of: model.tracks.map { $0.id }) { fit(model.tracks) }
    }

    private func mapButton(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Avo.text)
                .frame(width: 36, height: 36)
                .background(Avo.bg.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Avo.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func fit(_ list: [CompareTrack]) {
        guard let r = CompareMap.bounds(list) else {
            position = .automatic
            return
        }
        region = r
        withAnimation { position = .region(r) }
    }

    private func zoomMap(_ factor: Double) {
        guard let r = region ?? CompareMap.bounds(model.tracks) else { return }
        let lat: Double = min(max(r.span.latitudeDelta * factor, 0.0002), 120)
        let lon: Double = min(max(r.span.longitudeDelta * factor, 0.0002), 240)
        let z = MKCoordinateRegion(center: r.center, span: MKCoordinateSpan(latitudeDelta: lat, longitudeDelta: lon))
        region = z
        withAnimation { position = .region(z) }
    }

    /// Bounding region of the routes with a margin.
    static func bounds(_ list: [CompareTrack]) -> MKCoordinateRegion? {
        var minLa: Double = 90
        var maxLa: Double = -90
        var minLo: Double = 180
        var maxLo: Double = -180
        var any: Bool = false
        for t in list {
            for run in t.runs {
                for c in run {
                    if !c.latitude.isFinite || !c.longitude.isFinite { continue }
                    minLa = min(minLa, c.latitude); maxLa = max(maxLa, c.latitude)
                    minLo = min(minLo, c.longitude); maxLo = max(maxLo, c.longitude)
                    any = true
                }
            }
        }
        if !any { return nil }
        let center = CLLocationCoordinate2D(latitude: (minLa + maxLa) / 2, longitude: (minLo + maxLo) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((maxLa - minLa) * 1.35, 0.0008),
                                    longitudeDelta: max((maxLo - minLo) * 1.35, 0.0008))
        return MKCoordinateRegion(center: center, span: span)
    }
}
