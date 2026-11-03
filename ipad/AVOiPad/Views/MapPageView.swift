import SwiftUI
import UIKit
import MapKit

/// «Análisis» of one training (formerly «Mapa»): map with the layers panel, statistics, the training zones (phases,
/// repetitions, passes), legend, segments and selected point on the right; speed profile with the zone strips, time bar
/// and the zone buttons (start / finish lines, work limits, repetitions) at the bottom. The pages of the training are in
/// the training bar above (RootView.TrainingBar).
struct MapPageView: View {
    @Environment(AppModel.self) private var app
    @State private var command: RouteMapCommand = RouteMapCommand()
    @State private var showLayers: Bool = true

    var body: some View {
        GeometryReader { (geo: GeometryProxy) in
            let wide: Bool = geo.size.width >= 900
            VStack(alignment: .leading, spacing: 10) {
                if wide {
                    HStack(alignment: .top, spacing: 12) {
                        mapArea(wide: true)
                        ScrollView { MapSidePanel() }
                            .frame(width: 300)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    mapArea(wide: false)
                        .frame(maxHeight: .infinity)
                    ScrollView { MapSidePanel() }
                        .frame(height: max(200, geo.size.height * 0.28))
                }
                MapProfilePanel()
                    .frame(height: 170)
                ZoneToolbar()
            }
            .padding(12)
        }
        .background(Avo.bg)
        .onAppear { app.map.pageShown() }
    }

    private func mapArea(wide: Bool) -> some View {
        let model: MapModel = app.map
        return ZStack(alignment: .topLeading) {
            MapRouteContainer(command: command,
                              fitPadding: UIEdgeInsets(top: 40, left: showLayers && wide ? 230 : 40, bottom: 40, right: 70),
                              showCourse: true)
            if showLayers {
                MapLayersPanel(model: model, onClose: { showLayers = false })
                    .padding(12)
            } else {
                Button { showLayers = true } label: { Label("Capas", systemImage: "square.3.layers.3d") }
                    .buttonStyle(.avoSecondary)
                    .padding(12)
            }
            VStack(spacing: 6) {
                mapButton("plus", "Acercar") { command = command.next(.zoomIn) }
                mapButton("minus", "Alejar") { command = command.next(.zoomOut) }
                mapButton("arrow.up.left.and.arrow.down.right", "Ajustar recorrido") { command = command.next(.fit) }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            if model.provider != .vectorOffline {
                Text(RouteTileNet.attribution)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.black.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .allowsHitTesting(false)
            } else {
                Text("Modo vectorial sin conexión (sin teselas)")
                    .font(.caption2).foregroundStyle(Avo.unknown)
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .allowsHitTesting(false)
            }
            if model.route == nil {
                Group {
                    if model.building {
                        ProgressView("Preparando recorrido…").tint(Avo.text)
                    } else {
                        Text("Sin recorrido: importa o selecciona un entrenamiento")
                            .font(.callout).foregroundStyle(Color.white)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color(hex: 0x101014, alpha: 0.8), in: RoundedRectangle(cornerRadius: 5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Avo.line, lineWidth: 1))
    }

    private func mapButton(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).frame(width: 38, height: 38)
        }
        .foregroundStyle(Avo.text)
        .background(Color(hex: 0x101014, alpha: 0.9), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Avo.line, lineWidth: 1))
        .accessibilityLabel(label)
    }
}

/// The MKMapView with the live cursor/range (own view: cursor changes only update this one).
struct MapRouteContainer: View {
    @Environment(AppModel.self) private var app
    var command: RouteMapCommand
    var fitPadding: UIEdgeInsets
    /// nil = the map model's current route.
    var overrideRoute: RouteRenderData? = nil
    var useOverride: Bool = false
    /// Draw the start / finish lines of the training zones (Análisis page).
    var showCourse: Bool = false

    var body: some View {
        let model: MapModel = app.map
        MapKitRoute(data: useOverride ? overrideRoute : model.route,
                    provider: model.provider,
                    tileCacheDir: model.tileCacheDir,
                    cursorTime: app.cursorTime,
                    rangeStart: app.rangeStart,
                    rangeEnd: app.rangeEnd,
                    showMarkers: model.showMarkers,
                    fitPadding: fitPadding,
                    home: model.home,
                    command: command,
                    courseLines: showCourse ? app.corrections.mapLines(app.selected) : [],
                    onTap: { (t: Double) in app.cursorTime = t })
    }
}

/// «CAPA BASE» / «TRAZO» panel over the map.
private struct MapLayersPanel: View {
    let model: MapModel
    var onClose: () -> Void

    var body: some View {
        @Bindable var m = model
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("CAPA BASE").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark").font(.caption2) }
                    .foregroundStyle(Avo.textDim)
                    .accessibilityLabel("Ocultar capas")
            }
            radio("Satélite", model.provider == .esriSatellite) { model.provider = .esriSatellite }
            radio("Híbrido", model.provider == .esriHybrid) { model.provider = .esriHybrid }
            radio("Vectorial sin conexión", model.provider == .vectorOffline) { model.provider = .vectorOffline }
            Text("TRAZO").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim).padding(.top, 8)
            ForEach(RouteColorMode.allCases) { (mode: RouteColorMode) in
                radio(mode.title, model.colorMode == mode) { model.colorMode = mode }
            }
            Toggle("Inicio / final", isOn: $m.showMarkers)
                .font(.callout).tint(Avo.red).padding(.top, 6)
        }
        .padding(10)
        .frame(width: 200)
        .background(Color(hex: 0x101014, alpha: 0.9), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Avo.line, lineWidth: 1))
    }

    private func radio(_ text: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(on ? Avo.red : Avo.textDim)
                Text(text).font(.callout).foregroundStyle(Avo.text)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(on ? Avo.redSoft : Color.clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Right column of the map page.
private struct MapSidePanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model: MapModel = app.map
        VStack(alignment: .leading, spacing: 10) {
            AvoCard {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        stat("Distancia", app.selected?.distanceText ?? "—")
                        stat("Tiempo", app.selected?.durationText ?? "—")
                    }
                    GridRow {
                        stat("Vel. media", app.selected?.meanSpeedText ?? "—")
                        stat("Vel. máxima", app.selected?.maxSpeedText ?? "—")
                    }
                }
            }
            AvoCard(title: "Entrenamiento") {
                TrainingZonesCard()
            }
            AvoCard(title: model.legendTitle) {
                RouteLegendView(model: model)
            }
            AvoCard(title: "Análisis de tramos") {
                let rows: [SegmentMetrics] = app.segments.rows
                if rows.isEmpty {
                    Text("Sin tramos guardados").font(.caption).foregroundStyle(Avo.textDim)
                } else {
                    VStack(spacing: 2) {
                        ForEach(rows.prefix(30), id: \.id) { (r: SegmentMetrics) in
                            Button { app.segments.select(r.id) } label: {
                                HStack {
                                    Text(r.name).font(.caption).lineLimit(1).foregroundStyle(Avo.text)
                                    Spacer(minLength: 6)
                                    Text(TimeText.num(r.maxSpeedKmh, "0.0", " km/h", missing: "—"))
                                        .font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(Avo.text)
                                }
                                .padding(.vertical, 4).padding(.horizontal, 6)
                                .background(app.segments.selectedId == r.id ? Avo.redSoft : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Button("Gestionar tramos") { app.page = .segments }
                    .buttonStyle(.avoSecondary)
                    .padding(.top, 4)
            }
            AvoCard(title: "Punto seleccionado") {
                MapCursorRows()
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.caption2.weight(.semibold)).tracking(0.5).foregroundStyle(Avo.textDim)
            Text(value).font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundStyle(Avo.text)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
    }
}

/// Selected point (own view: re-renders with the cursor).
private struct MapCursorRows: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            SyncKeyValueRows(rows: [
                SyncStatRow(key: "Tiempo", value: app.cursorText),
                SyncStatRow(key: "Velocidad", value: app.cursorSpeed + " km/h"),
                SyncStatRow(key: "Distancia", value: app.cursorDistance + " km"),
                SyncStatRow(key: "Posición (chaleco)", value: app.cursorPosition),
            ])
        }
    }
}

/// Legend of the current colour mode.
struct RouteLegendView: View {
    let model: MapModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch model.colorMode {
            case .speed:
                gradient(Avo.speedScale)
                HStack {
                    Text("0").font(.caption2).foregroundStyle(Avo.textDim)
                    Spacer()
                    Text(model.route.map { TimeText.num($0.maxSpeedKmh, "0.0", " km/h") } ?? "")
                        .font(.caption2).foregroundStyle(Avo.textDim)
                }
                Text("Velocidad filtrada (Kalman + RTS), 24 tonos.").font(.caption2).foregroundStyle(Avo.textDim)
            case .acceleration:
                gradient(Avo.accelScale)
                HStack {
                    Text("−2 m/s² frenada").font(.caption2).foregroundStyle(Avo.textDim)
                    Spacer()
                    Text("0").font(.caption2).foregroundStyle(Avo.textDim)
                    Spacer()
                    Text("+2 m/s²").font(.caption2).foregroundStyle(Avo.textDim)
                }
                Text("Solo aceleración validada (incertidumbre ≤ 0,8 m/s², sin cortes); el resto en gris.")
                    .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            case .gait:
                items([("Parado", SpeedScale.gait(0)), ("Paso", SpeedScale.gait(1)), ("Trote", SpeedScale.gait(2)),
                       ("Galope", SpeedScale.gait(3)), ("Sin dato", SpeedScale.gait(-1))])
                if !model.hasGait {
                    Text("El aire necesita datos de cincha y el motor AVO: sin ellos todo el trazo queda gris.")
                        .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1).stroke(Color(hex: 0xFF3945), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .frame(width: 22, height: 2)
                Text("Tramo sin posición (sin interpolar)").font(.caption2).foregroundStyle(Avo.textDim)
            }
            Text("Posiciones de la antena del chaleco (jinete), no de un punto del caballo.")
                .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func gradient(_ stops: [Color]) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(LinearGradient(colors: stops, startPoint: .leading, endPoint: .trailing))
            .frame(height: 10)
    }

    private func items(_ list: [(String, AvoRGB)]) -> some View {
        let rows: [SyncLegend] = list.map { SyncLegend($0.0, SpeedScale.mapColor($0.1)) }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), alignment: .leading)], alignment: .leading, spacing: 4) {
            ForEach(rows) { (l: SyncLegend) in
                HStack(spacing: 5) {
                    Circle().fill(l.color).frame(width: 9, height: 9)
                    Text(l.text).font(.caption2).foregroundStyle(Avo.text)
                }
            }
        }
    }
}

/// «Perfil de velocidad (km/h)» synchronised with the charts, plus playback.
private struct MapProfilePanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let charts: ChartsModel = app.charts
        SyncChartBox(title: "Perfil de velocidad (km/h)", legend: [],
                     readout: { (a: AppModel) -> String in a.cursorSpeed + " km/h" }) {
            VStack(spacing: 6) {
                SyncSignalChart(panel: charts.panel(.speed), domain: charts.domain, bands: app.corrections.bands(app.selected),
                                includeZero: true, emptyText: "Sin datos",
                                handles: app.corrections.handles(app.selected),
                                onHandle: { (id: Int, t: Double) in app.corrections.moveHandle(id, to: t) })
                SyncPlaybackBar(compact: false)
            }
        }
    }
}

// MARK: - Playback (Windows PlayCommand, PlaybackSpeeds, PlaybackText)

/// Play/pause, speed menu, scrubber over the timeline and «cursor / total» text.
struct SyncPlaybackBar: View {
    @Environment(AppModel.self) private var app
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Button { app.togglePlay() } label: {
                Image(systemName: app.isPlaying ? "pause.fill" : "play.fill").frame(width: 16)
            }
            .buttonStyle(.avoPrimary)
            .disabled(!app.hasSession)
            .accessibilityLabel(app.isPlaying ? "Pausa" : "Reproducir")
            .accessibilityIdentifier("playback.toggle")
            Menu {
                ForEach(app.playbackSpeeds, id: \.self) { (v: Double) in
                    Button {
                        app.playbackSpeed = v
                    } label: {
                        if v == app.playbackSpeed { Label(speedText(v), systemImage: "checkmark") } else { Text(speedText(v)) }
                    }
                }
            } label: {
                Text(speedText(app.playbackSpeed)).font(.callout.monospacedDigit()).frame(minWidth: 36)
            }
            .buttonStyle(.avoSecondary)
            .accessibilityLabel("Velocidad de reproducción")
            if !compact {
                PlaybackScrubber()
            }
            Text(app.playbackText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(Avo.textDim)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private func speedText(_ v: Double) -> String {
        DotNetFormat.custom(v, "0.#", spanish: true) + "×"
    }
}

private struct PlaybackScrubber: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let lo: Double = app.timelineStart
        let hi: Double = app.timelineEnd
        if app.hasSession && hi.isFinite && lo.isFinite && hi > lo {
            let binding: Binding<Double> = Binding<Double>(
                get: { () -> Double in
                    let t: Double = app.cursorTime
                    return t.isFinite ? min(max(t, lo), hi) : lo
                },
                set: { (v: Double) in app.cursorTime = v })
            Slider(value: binding, in: lo...hi)
                .tint(Avo.red)
                .accessibilityLabel("Posición de reproducción")
        } else {
            Slider(value: .constant(0), in: 0...1).disabled(true)
        }
    }
}

// MARK: - Training zones (AVO Track Work + corrections)

/// Compact summary of the training zones (engine «trabajo_pista»): phases and counts. The full analysis (table of
/// efforts and passes, splits, best distances, stride, girth, events) is the «Trabajo en pista» page.
private struct TrainingZonesCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let s = app.selected, let e = s.engine {
                let tw: TrackWorkResult = e.trackWork
                if !tw.present {
                    Text("Este resultado del motor no trae el análisis del trabajo: vuelve a analizar el entrenamiento.")
                        .font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                } else {
                    phaseRow("Calentamiento", CorrectionsModel.warmupColor, tw.warmup)
                    phaseRow("Trabajo", CorrectionsModel.workColor, tw.work)
                    phaseRow("Vuelta a la calma", CorrectionsModel.cooldownColor, tw.cooldown)
                    Text("Fases \(tw.phaseBasisText)" + (tw.breed.isEmpty ? "" : " · perfil \(tw.breed)"))
                        .font(.caption2).foregroundStyle(Avo.textDim)
                    Text(countsText(tw))
                        .font(.caption).foregroundStyle(Avo.text).fixedSize(horizontal: false, vertical: true)
                    if let sel = app.trackWork.selected {
                        Text("Seleccionado: \(sel.title) · \(TrackWorkText.metres(sel.distanceOpt)) · máx \(TrackWorkText.kmh(sel.vmaxOpt))")
                            .font(.caption).foregroundStyle(Avo.cyan).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    if tw.warmupShort {
                        Label("Calentamiento corto antes del trabajo rápido", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(Avo.redLight)
                    }
                    Button {
                        app.page = .trackWork
                    } label: {
                        Label("Ver trabajo en pista", systemImage: "stopwatch")
                    }
                    .buttonStyle(.avoSecondary)
                    .accessibilityIdentifier("map.trackWork")
                }
            } else if let s = app.selected {
                Text(s.engineState).font(.caption).foregroundStyle(Avo.textDim)
            } else {
                Text("Sin entrenamiento").font(.caption).foregroundStyle(Avo.textDim)
            }
        }
    }

    private func countsText(_ tw: TrackWorkResult) -> String {
        if tw.efforts.isEmpty && tw.passes.isEmpty {
            return "Sin trabajos detectados. Márcalos con «Inicio / Fin repetición»."
        }
        var p: [String] = ["\(tw.efforts.count) trabajos (\(tw.fastReps) rápidos)"]
        if tw.courseDefined { p.append("\(tw.passes.count) pasadas") }
        if let b = tw.sessionBest200S { p.append("mejor 200 m " + TrackWorkText.seconds(b)) }
        return p.joined(separator: " · ")
    }

    private func phaseRow(_ name: String, _ color: Color, _ p: TrackWorkPhase) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(name).font(.caption).foregroundStyle(Avo.text)
            Spacer(minLength: 6)
            Text(p.present ? "\(TimeText.clock(p.durationS)) · \(AvoFormat.f(p.distanceM / 1000, 2)) km" : "—")
                .font(.caption.monospacedDigit()).foregroundStyle(Avo.text)
        }
    }
}

/// «Botones mod. zonas»: move the zones of the training with the time bar. Every change is saved (correcciones.json)
/// and the engine analyses the training again; «Restablecer» goes back to the automatic zones.
private struct ZoneToolbar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let c: CorrectionsModel = app.corrections
        let can: Bool = c.canEdit
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Text("ZONAS").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim)
                    zoneButton("Salida aquí", "flag", "zone.start") { c.setLine(finish: false) }.disabled(!can)
                    zoneButton("Meta aquí", "flag.checkered", "zone.finish") { c.setLine(finish: true) }.disabled(!can)
                    separator
                    zoneButton("Inicio trabajo", "arrow.right.to.line", "zone.workStart") { c.setWorkLimit(end: false) }.disabled(!can)
                    zoneButton("Fin trabajo", "arrow.left.to.line", "zone.workEnd") { c.setWorkLimit(end: true) }.disabled(!can)
                    separator
                    if c.pendingRepStart.isFinite {
                        Button { c.endRepetition() } label: { Label("Fin repetición", systemImage: "stop.circle") }
                            .buttonStyle(.avoPrimary).disabled(!can)
                            .accessibilityIdentifier("zone.repEnd")
                    } else {
                        zoneButton("Inicio repetición", "record.circle", "zone.repStart") { c.beginRepetition() }.disabled(!can)
                    }
                    zoneButton("Quitar repetición", "minus.circle", "zone.repRemove") { c.removeRepetitionAtCursor() }.disabled(!can)
                    separator
                    zoneButton("Restablecer", "arrow.counterclockwise", "zone.reset") { c.reset() }.disabled(!c.hasCorrections)
                }
                .padding(.vertical, 1)
            }
            HStack(spacing: 12) {
                legend("Calentamiento", CorrectionsModel.warmupColor)
                legend("Trabajo", CorrectionsModel.workColor)
                legend("Calma", CorrectionsModel.cooldownColor)
                legend("Rápido", CorrectionsModel.fastColor)
                legend("Galope", CorrectionsModel.canterColor)
                legend("Pasada", CorrectionsModel.passColor)
                Spacer(minLength: 8)
                Text(c.message.isEmpty ? c.summaryText : c.message)
                    .font(.caption).foregroundStyle(c.hasCorrections ? Avo.cyan : Avo.textDim)
                    .lineLimit(1).truncationMode(.tail)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Avo.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Avo.line, lineWidth: 1))
    }

    private var separator: some View { Rectangle().fill(Avo.line).frame(width: 1, height: 26) }

    private func zoneButton(_ title: String, _ icon: String, _ id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: icon) }
            .buttonStyle(.avoSecondary)
            .accessibilityIdentifier(id)
    }

    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 6)
            Text(text).font(.caption2).foregroundStyle(Avo.textDim)
        }
    }
}
