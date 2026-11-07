import SwiftUI
import UIKit
import MapKit

/// «Análisis» of one training: map at FULL WIDTH (statistics over the map, layers behind a small button), then the
/// timeline (speed profile with the zone strips, playback and zone buttons) and below ALL the charts of «Gráficas» in one
/// vertical scroll, sharing cursor, zoom and range. «Entreno 2» (training bar) turns the page into the comparison of
/// the active training (blue) with the second one (yellow): overlaid routes and aligned charts.
/// `mapOnly` = «Mapa» of the sidebar: the map fills the page, with the timeline below and no charts.
struct MapPageView: View {
    @Environment(AppModel.self) private var app
    @State private var command: RouteMapCommand = RouteMapCommand()
    @State private var showLayers: Bool = false
    /// Recorrido en horizontal (por defecto) o norte arriba; se recuerda entre sesiones.
    @AppStorage("map.alignRoute") private var alignRoute: Bool = true
    var mapOnly: Bool = false

    var body: some View {
        GeometryReader { (geo: GeometryProxy) in
            Group {
                if app.compare.isPaired {
                    pairedLayout(geo)
                } else if mapOnly {
                    // the trainer's sketch: map in the top half, the time bar, then the charts (scroll) in the bottom half
                    VStack(alignment: .leading, spacing: 8) {
                        mapArea(wide: true, playbackOnMap: false)
                            .frame(height: max(320, geo.size.height * 0.5))
                        SyncPlaybackBar(compact: false)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Avo.surface, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Avo.line, lineWidth: 1))
                            .accessibilityIdentifier("map.timeBar")
                        ScrollView(.vertical) {
                            VStack(alignment: .leading, spacing: 10) {
                                MapMetricPanel()
                                    .frame(height: max(280, geo.size.height * 0.36))
                                MapInfoCards(wide: geo.size.width >= 900)
                            }
                            .padding(.bottom, 16)
                        }
                        .scrollDisabled(app.charts.rangeMode)
                    }
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            mapArea(wide: true, playbackOnMap: true)
                                .frame(height: max(380, geo.size.height * 0.58))
                            MapProfilePanel()
                                .frame(height: 150)
                            ZoneToolbar()
                            ChartsNavigator(charts: app.charts)
                            ChartsStack(charts: app.charts, skipSpeed: true)
                            MapInfoCards(wide: geo.size.width >= 900)
                        }
                        .padding(.bottom, 24)
                    }
                    // while «Seleccionar rango» is on, a drag on a chart must select, never scroll
                    .scrollDisabled(app.charts.rangeMode)
                }
            }
            .padding(12)
        }
        .background(Avo.bg)
        .onAppear {
            app.map.pageShown()
            app.charts.pageShown()
        }
    }

    /// «Entreno 1 | Entreno 2»: overlaid routes and aligned charts of the two trainings.
    @ViewBuilder
    private func pairedLayout(_ geo: GeometryProxy) -> some View {
        let model: CompareModel = app.compare
        VStack(alignment: .leading, spacing: 10) {
            PairHeader(model: model)
            if mapOnly {
                CompareMap(model: model)
                    .frame(maxHeight: .infinity)
            } else {
                CompareChartToolbar(model: model)
                if model.hasRange { CompareRangeCard(model: model) }
                ScrollView(.vertical) {
                    CompareResults(model: model, mapHeight: max(380, geo.size.height * 0.55))
                        .padding(.bottom, 24)
                }
                .scrollDisabled(model.rangeMode)
            }
        }
    }

    private func mapArea(wide: Bool, playbackOnMap: Bool) -> some View {
        let model: MapModel = app.map
        return ZStack(alignment: .topLeading) {
            MapRouteContainer(command: command,
                              fitPadding: UIEdgeInsets(top: 76, left: 40, bottom: 84, right: 170),
                              showCourse: true, alignRoute: alignRoute)
            // top-right: Distancia · Vel. media · Tiempo · Vel. máx., one under the other
            MapStatsOverlay()
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            // top: data of the point under the cursor (and its phase), left of the statistics column
            MapCursorOverlay()
                .padding(.leading, 12)
                .padding(.top, 12)
                .padding(.trailing, 160)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Análisis: playback (play, speed, scrubber, time) over the bottom of the map, left of Capas and the zoom buttons.
            // «Mapa» has it as its own time bar between the map and the charts.
            if playbackOnMap {
            SyncPlaybackBar(compact: false)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color(hex: 0x101014, alpha: 0.86), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Avo.line, lineWidth: 1))
                .padding(.leading, 12)
                .padding(.trailing, 58 + 118)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            // bottom-right, next to the zoom buttons: Capas (the panel opens above it)
            Group {
                if showLayers {
                    MapLayersPanel(model: model, onClose: { showLayers = false })
                } else {
                    Button { showLayers = true } label: { Label("Capas", systemImage: "square.3.layers.3d") }
                        .buttonStyle(.avoSecondary)
                        .accessibilityIdentifier("map.layers")
                }
            }
            .padding(.trailing, 58)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            VStack(spacing: 6) {
                mapButton("plus", "Acercar") { command = command.next(.zoomIn) }
                mapButton("minus", "Alejar") { command = command.next(.zoomOut) }
                mapButton("arrow.up.left.and.arrow.down.right", "Ajustar recorrido") { command = command.next(.fit) }
                mapButton(alignRoute ? "location.north.line" : "arrow.left.and.right",
                          alignRoute ? "Norte arriba" : "Recorrido en horizontal") { alignRoute.toggle() }
            }
            .padding(.trailing, 12)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
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

/// Distance, mean speed, time and max speed of the active training, one under the other, top-right of the map.
private struct MapStatsOverlay: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            stat("Distancia", app.selected?.distanceText ?? "—")
            stat("Vel. media", app.selected?.meanSpeedText ?? "—")
            stat("Tiempo", app.selected?.durationText ?? "—")
            stat("Vel. máx.", app.selected?.maxSpeedText ?? "—")
        }
        .frame(minWidth: 108, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Color(hex: 0x101014, alpha: 0.82), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Avo.line, lineWidth: 1))
        .allowsHitTesting(false)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased()).font(.system(size: 9.5, weight: .semibold)).tracking(0.4).foregroundStyle(Avo.textDim)
            Text(value).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Avo.text)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
    }
}

/// Data of the exact point under the cursor (tap on the route, the timeline or playback): time, distance, speed and
/// acceleration, over the bottom-left corner of the map. Own view: only this re-renders when the cursor moves.
private struct MapCursorOverlay: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let has: Bool = app.selected != nil && app.cursorTime.isFinite
        let rows: [SyncStatRow] = app.hasRange ? app.charts.rangeStats : []
        // One horizontal strip along the top of the map (the trainer's sketch): the selected stretch when there is one,
        // otherwise the point data and then the phase data.
        HStack(alignment: .center, spacing: 14) {
            if !rows.isEmpty {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(Avo.red.opacity(0.6)).frame(width: 10, height: 10)
                    Text("TRAMO").font(.system(size: 9.5, weight: .semibold)).tracking(0.5).foregroundStyle(Avo.textDim)
                }
                stat("Duración", value(rows, "Duración"), "")
                stat("Distancia", value(rows, "Distancia"), "")
                stat("Vel. media", value(rows, "Vel. media"), "")
                stat("Vel. máx.", value(rows, "Vel. máxima"), "")
                stat("Acel. máx.", value(rows, "Aceleración máx. validada"), "")
                stat("Frenada máx.", value(rows, "Frenada máx. validada"), "")
                Text(value(rows, "Inicio") + " – " + value(rows, "Fin"))
                    .font(.caption.monospacedDigit()).foregroundStyle(Avo.textDim).lineLimit(1)
            } else {
            HStack(spacing: 6) {
                Circle().fill(Avo.red).frame(width: 8, height: 8)
                Text("PUNTO").font(.system(size: 9.5, weight: .semibold)).tracking(0.5).foregroundStyle(Avo.textDim)
            }
            if has {
                stat("Tiempo", app.cursorText, "")
                stat("Distancia", app.cursorDistanceM, "m")
                stat("Velocidad", app.cursorSpeed, "km/h")
                stat("Aceleración", app.cursorAccel, "m/s²")
                if let ph = phase {
                    Rectangle().fill(Avo.line).frame(width: 1, height: 34)
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(ph.color).frame(width: 10, height: 10)
                        Text(ph.name.uppercased()).font(.system(size: 9.5, weight: .semibold)).tracking(0.5)
                            .foregroundStyle(Avo.textDim)
                    }
                    stat("Tiempo fase", ph.elapsed, "")
                    stat("Distancia fase", ph.distance, "m")
                    Text("de " + ph.total).font(.caption.monospacedDigit()).foregroundStyle(Avo.textDim).lineLimit(1)
                }
            } else {
                Text("Toca el recorrido o la línea de tiempo").font(.caption).foregroundStyle(Avo.textDim)
            }
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .minimumScaleFactor(0.7)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(hex: 0x101014, alpha: 0.86), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Avo.red.opacity(0.5), lineWidth: 1))
        .allowsHitTesting(false)
        .accessibilityIdentifier("map.cursorData")
    }

    /// Phase of the session (engine «trabajo_pista», with the manual corrections) that contains the cursor, with the
    /// time and distance since the start of that phase.
    private var phase: (name: String, color: Color, elapsed: String, distance: String, total: String)? {
        guard let s = app.selected, let tw = s.engine?.trackWork, tw.present, app.cursorTime.isFinite else { return nil }
        let tl: SessionTimeline = s.timeline
        let i: Int = app.cursorIndex
        guard i >= 0, i < tl.distance.count else { return nil }
        let off: Double = s.engineOffsetS
        let te: Double = app.cursorTime + off
        let list: [(String, Color, TrackWorkPhase)] = [("Calentamiento", CorrectionsModel.warmupColor, tw.warmup),
                                                        ("Trabajo", CorrectionsModel.workColor, tw.work),
                                                        ("Enfriamiento", CorrectionsModel.cooldownColor, tw.cooldown)]
        for (name, color, p) in list {
            guard p.present, p.t0.isFinite, p.t1.isFinite, te >= p.t0, te <= p.t1 else { continue }
            let i0: Int = tl.indexAt(p.t0 - off)
            guard i0 >= 0, i0 < tl.distance.count else { return nil }
            let dm: Double = tl.distance[i] - tl.distance[i0]
            let total: String = TimeText.clock(p.durationS.isFinite ? p.durationS : p.t1 - p.t0)
                + (p.distanceM.isFinite ? " · " + DotNetFormat.custom(p.distanceM, "0", spanish: true) + " m" : "")
            return (name, color, TimeText.clock(max(0, te - p.t0)),
                    dm.isFinite ? DotNetFormat.custom(max(0, dm), "0", spanish: true) : "—", total)
        }
        return nil
    }

    private func value(_ rows: [SyncStatRow], _ key: String) -> String {
        rows.first { $0.key == key }?.value ?? "—"
    }

    private func stat(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(0.4).foregroundStyle(Avo.textDim)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit()).foregroundStyle(Avo.text)
                    .lineLimit(1)
                if !unit.isEmpty && value != "—" { Text(unit).font(.caption2).foregroundStyle(Avo.textDim) }
            }
        }
        .frame(minWidth: 64, alignment: .leading)
    }
}

/// Cards that were in the right column (training zones, legend, segments, selected point), now after the charts.
private struct MapInfoCards: View {
    @Environment(AppModel.self) private var app
    var wide: Bool

    var body: some View {
        let model: MapModel = app.map
        let cards = Group {
            AvoCard(title: "Entrenamiento") { TrainingZonesCard() }
            AvoCard(title: model.legendTitle) { RouteLegendView(model: model) }
            AvoCard(title: "Punto seleccionado") { MapCursorRows() }
        }
        if wide {
            HStack(alignment: .top, spacing: 10) { cards }
        } else {
            VStack(alignment: .leading, spacing: 10) { cards }
        }
    }
}

/// «Entreno 1 (azul) · Entreno 2 (amarillo)» over the comparison of the Análisis page.
private struct PairHeader: View {
    @Environment(AppModel.self) private var app
    var model: CompareModel

    var body: some View {
        HStack(spacing: 14) {
            if let a = app.selected { item("Entreno 1", a, CompareModel.pairColors.first) }
            if let b = model.pairSession { item("Entreno 2", b, CompareModel.pairColors.second) }
            Spacer(minLength: 0)
            Button { model.setPair(nil) } label: { Label("Quitar entreno 2", systemImage: "xmark") }
                .buttonStyle(.avoSecondary)
        }
    }

    private func item(_ title: String, _ s: SessionItem, _ color: Color) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 14, height: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased()).font(.caption2.weight(.semibold)).tracking(0.5).foregroundStyle(Avo.textDim)
                Text("\(s.dateTimeText) · \(s.horse) · \(s.distanceText)").font(.callout.weight(.semibold)).foregroundStyle(Avo.text)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Avo.surface2, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(color.opacity(0.6), lineWidth: 1))
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
    /// Playa / recorrido en horizontal (true) o norte arriba (false).
    var alignRoute: Bool = true

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
                    alignRoute: alignRoute,
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

/// «Perfil de velocidad (km/h)» synchronised with the charts (playback is over the map).
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
            }
        }
    }
}

// MARK: - «Mapa»: one big chart with a metric selector (the trainer's sketch)

/// Metrics of the «Mapa» chart. The girth ones only appear when the session has girth IMU data, cadence when the engine has it.
enum MapMetric: String, CaseIterable, Identifiable {
    case speed, accel, lateral, tilt, vertical, cadence
    var id: String { rawValue }
    var title: String {
        switch self {
        case .speed: return "Velocidad"
        case .accel: return "Aceleración"
        case .lateral: return "Lateral"
        case .tilt: return "Inclinación"
        case .vertical: return "Vertical"
        case .cadence: return "Cadencia"
        }
    }
    var unit: String {
        switch self {
        case .speed: return "km/h"
        case .accel, .lateral, .vertical: return "m/s²"
        case .tilt: return "°"
        case .cadence: return "ciclos/min"
        }
    }
    var panelId: SyncPanelId {
        switch self {
        case .speed: return .speed
        case .accel: return .accel
        case .lateral: return .lateral
        case .tilt: return .tilt
        case .vertical: return .fusedAccel
        case .cadence: return .cadence
        }
    }
}

/// Chart under the map of «Mapa»: tabs Velocidad / Aceleración / … , the chart with the zone strips and handles, and the
/// zone buttons, all in one card. Same cursor, zoom and range as every other chart.
private struct MapMetricPanel: View {
    @Environment(AppModel.self) private var app
    @AppStorage("map.metric") private var metricRaw: String = MapMetric.speed.rawValue

    private func available(_ charts: ChartsModel) -> [MapMetric] {
        var out: [MapMetric] = [.speed, .accel]
        if charts.hasGirthImu { out += [.lateral, .tilt, .vertical] }
        if charts.hasCadence { out.append(.cadence) }
        return out
    }

    var body: some View {
        let charts: ChartsModel = app.charts
        let list: [MapMetric] = available(charts)
        let metric: MapMetric = list.first { $0.rawValue == metricRaw } ?? .speed
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(list) { (m: MapMetric) in
                            let on: Bool = m == metric
                            Button {
                                metricRaw = m.rawValue
                            } label: {
                                Text(m.title)
                                    .font(.callout.weight(on ? .semibold : .regular))
                                    .foregroundStyle(on ? Color.white : Avo.text)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(on ? Avo.red : Avo.surface2, in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(on ? Avo.red : Avo.line, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("map.metric.\(m.rawValue)")
                        }
                    }
                }
                Spacer(minLength: 6)
                Text(metric.unit).font(.caption2).foregroundStyle(Avo.textDim)
                SyncReadout(text: { (a: AppModel) -> String in MapMetricPanel.readout(metric, a) })
            }
            SyncSignalChart(panel: charts.panel(metric.panelId), domain: charts.domain,
                            bands: app.corrections.bands(app.selected),
                            includeZero: metric != .tilt && metric != .cadence,
                            emptyText: charts.building ? "Calculando…" : "Sin datos",
                            handles: app.corrections.handles(app.selected),
                            onHandle: { (id: Int, t: Double) in app.corrections.moveHandle(id, to: t) })
                .frame(maxHeight: .infinity)
            // with zoom: overview bar of the whole session; drag its window to scroll sideways (also two fingers on the chart)
            if charts.isZoomed {
                HStack(spacing: 8) {
                    ChartsOverviewBar(charts: charts)
                        .frame(height: 28)
                    Button { charts.resetZoom() } label: { Label("Completo", systemImage: "arrow.left.and.right") }
                        .buttonStyle(.avoSecondary)
                        .accessibilityIdentifier("map.zoomReset")
                }
            }
            ZoneToolbar(embedded: true)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Avo.cardBrush, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Avo.line, lineWidth: 1))
        .accessibilityIdentifier("map.metricPanel")
    }

    static func readout(_ m: MapMetric, _ a: AppModel) -> String {
        switch m {
        case .speed: return a.cursorSpeed + " km/h"
        case .accel: return a.cursorAccel + " m/s²"
        case .lateral: return a.charts.lateralReadout(a.cursorTime)
        case .tilt: return a.charts.tiltReadout(a.cursorTime)
        case .vertical: return a.charts.verticalReadout(a.cursorTime)
        case .cadence: return a.cursorCadence
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
    /// Inside another card (MapMetricPanel): no own background or border.
    var embedded: Bool = false

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
        .padding(.horizontal, embedded ? 0 : 10).padding(.vertical, embedded ? 0 : 8)
        .background(embedded ? Color.clear : Avo.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(embedded ? Color.clear : Avo.line, lineWidth: 1))
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
