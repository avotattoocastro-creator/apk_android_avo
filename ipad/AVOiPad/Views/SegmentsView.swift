import SwiftUI
import UIKit

/// Segment analysis (Windows Views/SegmentsView.xaml): index on the left, selected segment with map, speed profile and
/// metrics in the centre, metrics / observations / rename on the right.
struct SegmentsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model: SegmentsModel = app.segments
        GeometryReader { (geo: GeometryProxy) in
            let wide: Bool = geo.size.width >= 1000
            VStack(alignment: .leading, spacing: 10) {
                AvoPageTitle(title: "Tramos",
                             subtitle: app.selected.map { $0.summary } ?? "Sin entrenamiento seleccionado · importa un archivo .avo o .avr")
                if app.selected == nil {
                    AvoCard { AvoNoData(text: "Selecciona un entrenamiento para crear y analizar tramos") }
                    Spacer(minLength: 0)
                } else if wide {
                    HStack(alignment: .top, spacing: 12) {
                        SegmentsListPanel(model: model)
                            .frame(width: 290)
                        SegmentsCenter(model: model)
                        ScrollView { SegmentsRightPanel(model: model) }
                            .frame(width: 280)
                    }
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        SegmentsListPanel(model: model)
                            .frame(width: min(290, geo.size.width * 0.4))
                        ScrollView {
                            VStack(spacing: 10) {
                                SegmentsCenter(model: model)
                                    .frame(height: max(460, geo.size.height * 0.62))
                                SegmentsRightPanel(model: model)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Avo.bg)
        .onAppear { app.segments.pageShown() }
    }
}

// MARK: - Left: list + creation

private struct SegmentsListPanel: View {
    @Environment(AppModel.self) private var app
    let model: SegmentsModel
    @State private var confirmClear: Bool = false

    var body: some View {
        AvoCard(title: "Tramos", subtitle: "\(model.rows.count) guardados") {
            if model.rows.isEmpty {
                AvoNoData(text: "Sin tramos: créalos con los botones de abajo")
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(model.rows, id: \.id) { (r: SegmentMetrics) in
                        SegmentRowView(row: r, selected: model.selectedId == r.id)
                            .contentShape(Rectangle())
                            .onTapGesture { model.select(r.id) }
                            .listRowBackground(model.selectedId == r.id ? Avo.redSoft : Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) { model.delete(r.id) } label: { Label("Eliminar", systemImage: "trash") }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(maxHeight: .infinity)
            }
            Divider().overlay(Avo.line)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CREAR TRAMOS").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim)
                    wideButton("Desde la selección de las gráficas", "arrow.left.and.right") { model.addFromRange() }
                        .disabled(!app.hasRange)
                    HStack(spacing: 6) {
                        wideButton(model.pendingStart.isFinite ? "Crear hasta el cursor" : "Marcar inicio en el cursor", "mappin.and.ellipse") {
                            model.markFromCursor()
                        }
                        if model.pendingStart.isFinite {
                            Button { model.cancelMark() } label: { Image(systemName: "xmark") }
                                .buttonStyle(.avoSecondary)
                                .accessibilityLabel("Cancelar inicio marcado")
                        }
                    }
                    if model.pendingStart.isFinite {
                        Text("Inicio marcado en \(TimeText.clock(model.pendingStart))").font(.caption2).foregroundStyle(Avo.warn)
                    }
                    HStack(spacing: 6) {
                        wideButton("Automático por distancia", "ruler") { model.autoDistance() }
                        Menu {
                            ForEach(model.segmentLengths, id: \.self) { (v: Double) in
                                Button(DotNetFormat.custom(v, "0", spanish: true) + " m") { model.segmentLength = v }
                            }
                        } label: {
                            Text(DotNetFormat.custom(model.segmentLength, "0", spanish: true) + " m")
                                .font(.callout.monospacedDigit()).frame(minWidth: 62)
                        }
                        .buttonStyle(.avoSecondary)
                    }
                    wideButton("Automático por banda de velocidad", "speedometer") { model.autoSpeedBand() }
                    wideButton("Por aire (motor AVO · cincha)", "figure.equestrian.sports") { model.fromEngine() }
                        .disabled(!model.hasEngineGait)
                    wideButton("Borrar todos los tramos", "trash") { confirmClear = true }
                        .disabled(model.rows.isEmpty)
                    HStack(spacing: 6) {
                        wideButton("Exportar CSV", "tablecells") { model.exportCsv() }
                            .disabled(model.rows.isEmpty)
                        if let url = model.exportURL {
                            ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                                .buttonStyle(.avoPrimary)
                                .accessibilityLabel("Compartir CSV de tramos")
                        }
                    }
                    Text("Los tramos se guardan aparte; la telemetría original nunca se modifica. Las bandas de velocidad no son aires.")
                        .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxHeight: 340)
        }
        .frame(maxHeight: .infinity)
        .confirmationDialog("¿Borrar todos los tramos de este entrenamiento?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Borrar todos", role: .destructive) { model.clearAll() }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private func wideButton(_ text: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(text, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.avoSecondary)
    }
}

private struct SegmentRowView: View {
    let row: SegmentMetrics
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(row.name).font(.callout.weight(.semibold)).foregroundStyle(Avo.text).lineLimit(1)
                Spacer(minLength: 4)
                AvoPill(text: SegmentsModel.kindName(row.kind), color: selected ? Avo.red : Avo.silver)
            }
            Text("\(TimeText.clock(row.t0)) – \(TimeText.clock(row.t1)) · \(DotNetFormat.custom(row.distanceM, "0", spanish: true)) m")
                .font(.caption.monospacedDigit()).foregroundStyle(Avo.textDim)
            if !row.notes.isEmpty {
                Text(row.notes).font(.caption2).foregroundStyle(Avo.textDim).lineLimit(1)
            }
        }
    }
}

// MARK: - Centre: header metrics, map, speed

private struct SegmentsCenter: View {
    @Environment(AppModel.self) private var app
    let model: SegmentsModel
    @State private var command: RouteMapCommand = RouteMapCommand()

    var body: some View {
        let m: SegmentMetrics? = model.selected
        VStack(spacing: 10) {
            AvoCard {
                Text(m?.name ?? "Selecciona o crea un tramo")
                    .font(.headline).foregroundStyle(Avo.text).lineLimit(1)
                HStack(spacing: 12) {
                    metric("Distancia", m.map { DotNetFormat.custom($0.distanceM, "0", spanish: true) + " m" } ?? "—")
                    metric("Duración", m.map { TimeText.clock($0.durationS) } ?? "—")
                    metric("Vel. media", m.map { TimeText.num($0.meanSpeedKmh, "0.0", " km/h") } ?? "—")
                    metric("Vel. máxima", m.map { TimeText.num($0.maxSpeedKmh, "0.0", " km/h") } ?? "—")
                }
            }
            ZStack(alignment: .topTrailing) {
                MapRouteContainer(command: command, fitPadding: UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30))
                Button { command = command.next(.fit) } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 34, height: 34)
                }
                .foregroundStyle(Avo.text)
                .background(Color(hex: 0x101014, alpha: 0.9), in: RoundedRectangle(cornerRadius: 7))
                .padding(10)
                .accessibilityLabel("Ajustar recorrido")
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Avo.line, lineWidth: 1))
            .frame(minHeight: 220, maxHeight: .infinity)
            SyncChartBox(title: "Velocidad en el tramo (km/h)", legend: [SyncLegend("Filtrada", Avo.blue)],
                         readout: { (a: AppModel) -> String in a.cursorSpeed + " km/h" }) {
                if let seg = m, seg.t1 > seg.t0 {
                    SyncSignalChart(panel: model.speedPanel, domain: seg.t0...seg.t1, includeZero: true,
                                    emptyText: "Sin datos GNSS en el tramo", zoomable: false)
                } else {
                    AvoNoData(text: "Selecciona un tramo")
                }
            }
            .frame(height: 190)
        }
        .onAppear { app.map.pageShown() }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.caption2.weight(.semibold)).tracking(0.5).foregroundStyle(Avo.textDim)
            Text(value).font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundStyle(Avo.text)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Right: metrics, observations, rename

private struct SegmentsRightPanel: View {
    @Environment(AppModel.self) private var app
    let model: SegmentsModel
    @State private var confirmDelete: Bool = false

    var body: some View {
        @Bindable var m = model
        VStack(alignment: .leading, spacing: 10) {
            AvoCard(title: "Métricas del tramo") {
                if model.detail.isEmpty { AvoNoData(text: "Selecciona un tramo") } else { SyncKeyValueRows(rows: model.detail) }
            }
            AvoCard(title: "Observaciones") {
                Text(model.observations.isEmpty ? "—" : model.observations)
                    .font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            }
            AvoCard(title: "Identificar y renombrar") {
                Text("NOMBRE").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim)
                TextField("Nombre del tramo", text: $m.segmentName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.selected == nil)
                Text("TIPO").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim)
                Picker("Tipo", selection: $m.segmentKind) {
                    ForEach(SegmentKind.allCases, id: \.self) { (k: SegmentKind) in
                        Text(SegmentsModel.kindName(k)).tag(k)
                    }
                }
                .pickerStyle(.menu)
                .tint(Avo.text)
                .disabled(model.selected == nil)
                Text("NOTAS").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim)
                TextEditor(text: $m.segmentNotes)
                    .frame(height: 72)
                    .scrollContentBackground(.hidden)
                    .background(Avo.surface2, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Avo.line, lineWidth: 1))
                    .disabled(model.selected == nil)
                HStack(spacing: 6) {
                    Button("Guardar") { model.saveSelected() }
                        .buttonStyle(.avoPrimary)
                        .disabled(model.selected == nil)
                    Button("Eliminar") { confirmDelete = true }
                        .buttonStyle(.avoSecondary)
                        .disabled(model.selected == nil)
                }
                Text("«Guardar» aplica también la selección actual de las gráficas como nuevos límites del tramo.")
                    .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            }
        }
        .confirmationDialog("¿Eliminar este tramo?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) { model.deleteSelected() }
            Button("Cancelar", role: .cancel) {}
        }
    }
}
