import SwiftUI
import UniformTypeIdentifiers

/// «Listado de entrenamientos»: every training loaded on the iPad in a dense, sortable table (a list of rows in compact
/// width), with filters and «Buscar entrenamientos perdidos» (App/TrainingListModel.swift).
struct TrainingListView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        TrainingListContent(model: app.trainingList)
    }
}

private struct TrainingListContent: View {
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Bindable var model: TrainingListModel
    @State private var sortOrder: [KeyPathComparator<TrainingListRow>] = [KeyPathComparator(\TrainingListRow.startKey, order: .reverse)]
    @State private var selection: String? = nil
    /// Training waiting for the «Eliminar» confirmation.
    @State private var pendingDelete: SessionItem? = nil
    /// Filters folded away by default (trainer's sketch 13/11/2026: «desplegable»).
    @State private var showFilters: Bool = false

    var body: some View {
        let rows: [TrainingListRow] = model.rows.sorted(using: sortOrder)
        VStack(alignment: .leading, spacing: 0) {
            if !app.sessions.isEmpty {
                toolbar(rows)
                if showFilters { filtersBar }
            }
            Rectangle().fill(Avo.line).frame(height: 1)
            if app.sessions.isEmpty {
                emptyState
            } else if rows.isEmpty {
                VStack(spacing: 10) {
                    AvoNoData(text: "Ningún entrenamiento cumple los filtros")
                    Button("Limpiar filtros") { model.clearFilters() }.buttonStyle(.avoSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if sizeClass == .compact {
                compactList(rows)
            } else {
                table(rows)
            }
        }
        .background(Avo.bg)
        .onAppear {
            selection = app.selected?.id
            model.refreshCaches()
        }
        .onChange(of: app.sessions.count) { (_: Int, _: Int) in model.refreshCaches() }
        .onChange(of: selection) { (_: String?, new: String?) in
            if let id = new, let s = model.item(id), s !== app.selected { app.select(s) }
        }
        .fileImporter(isPresented: $model.pickingFolder, allowedContentTypes: [UTType.folder], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let u = urls.first { Task { @MainActor in await model.scanFolder(u) } }
            case .failure(let error):
                app.fail(error)
            }
        }
        .sheet(isPresented: Binding(get: { model.report != nil }, set: { if !$0 { model.report = nil } })) {
            if let r = model.report {
                TrainingRecoverySheet(report: r) { model.report = nil }
                    .avoColorScheme()
            }
        }
    }

    // ------------------------------------------------------------------ toolbar
    /// Trainer's sketch 13/11/2026: no title or summary; the filters fold into «Filtros» and the maintenance buttons
    /// (buscar perdidos, carpeta, exportar, copiar) moved to «Configuración».
    private func toolbar(_ rows: [TrainingListRow]) -> some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showFilters.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text("Filtros")
                    if !model.filter.isEmpty {
                        Text("activos").font(.caption.weight(.semibold)).foregroundStyle(Avo.warn)
                    }
                    Image(systemName: showFilters ? "chevron.up" : "chevron.down").font(.caption2)
                }
            }
            .buttonStyle(.avoSecondary)
            .accessibilityIdentifier("list.filters")
            if rows.count != app.sessions.count {
                Text("\(rows.count) de \(app.sessions.count)").font(.footnote.monospacedDigit()).foregroundStyle(Avo.textDim)
            }
            if model.computing { ProgressView().controlSize(.mini) }
            Spacer(minLength: 8)
            Button {
                app.showImporter = true
            } label: {
                Label("Abrir", systemImage: "folder")
            }
            .buttonStyle(.avoPrimary)
            .disabled(app.busy)
            .accessibilityIdentifier("list.open")
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // ------------------------------------------------------------------ filters
    private var filtersBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Avo.textDim)
                        TextField("Buscar", text: $model.filter.search)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(Avo.text)
                        if !model.filter.search.isEmpty {
                            Button { model.filter.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Avo.textDim) }
                                .buttonStyle(.plain)
                        }
                    }
                    .font(.callout)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .frame(width: 220)
                    .background(Avo.surface2, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Avo.line, lineWidth: 1))
                    stringMenu("Caballo", all: "Todos los caballos", value: $model.filter.horse, options: model.horseOptions)
                    stringMenu("Jinete", all: "Todos los jinetes", value: $model.filter.rider, options: model.riderOptions)
                    stringMenu("Modalidad", all: "Todas", value: $model.filter.discipline, options: model.disciplineOptions)
                    fenceMenu
                }
                .padding(.horizontal, 20)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    dateControl("Desde", value: $model.filter.from)
                    dateControl("Hasta", value: $model.filter.to)
                    TrainingListChip(title: "Hoy", on: model.isQuick(1)) { model.setQuick(1) }
                    TrainingListChip(title: "7 días", on: model.isQuick(7)) { model.setQuick(7) }
                    TrainingListChip(title: "30 días", on: model.isQuick(30)) { model.setQuick(30) }
                    TrainingListChip(title: "Todo", on: model.isQuick(nil)) { model.setQuick(nil) }
                    Rectangle().fill(Avo.line).frame(width: 1, height: 22)
                    TrainingListChip(title: "Solo con cincha", icon: "sensor", on: model.filter.onlyGirth) { model.filter.onlyGirth.toggle() }
                    TrainingListChip(title: "Solo favoritos", icon: "star.fill", on: model.filter.onlyFavorites) { model.filter.onlyFavorites.toggle() }
                    TrainingListChip(title: "Ocultar DEMO", icon: "eye.slash", on: model.filter.hideDemo) { model.filter.hideDemo.toggle() }
                    Button {
                        model.clearFilters()
                    } label: {
                        Label("Limpiar filtros", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .buttonStyle(.avoSecondary)
                    .disabled(model.filter.isEmpty)
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.bottom, 10)
    }

    private func menuLabel(_ title: String, _ value: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title + ":").foregroundStyle(Avo.textDim)
            Text(value).fontWeight(.semibold).foregroundStyle(active ? Avo.text : Avo.silver).lineLimit(1)
            Image(systemName: "chevron.down").font(.caption2).foregroundStyle(Avo.textDim)
        }
        .font(.callout)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(active ? Avo.redSoft : Avo.surface2, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(active ? Avo.red : Avo.line, lineWidth: 1))
    }

    private func stringMenu(_ title: String, all: String, value: Binding<String>, options: [String]) -> some View {
        Menu {
            Picker(title, selection: value) {
                Text(all).tag("")
                ForEach(options, id: \.self) { (o: String) in Text(o).tag(o) }
            }
        } label: {
            menuLabel(title, value.wrappedValue.isEmpty ? all : value.wrappedValue, active: !value.wrappedValue.isEmpty)
        }
    }

    private var fenceMenu: some View {
        Menu {
            Picker("Geocerca", selection: $model.filter.fence) {
                Text("Todas").tag(-1)
                ForEach(model.fences, id: \.slot) { (f: TrainingListFence) in
                    Text("\(f.slot + 1). \(f.name)").tag(f.slot)
                }
            }
        } label: {
            menuLabel("Geocerca", model.filter.fence >= 0 ? model.fenceName(model.filter.fence)
                      : (model.fences.isEmpty ? "Sin geocercas" : "Todas"), active: model.filter.fence >= 0)
        }
        .disabled(model.fences.isEmpty && model.filter.fence < 0)
    }

    @ViewBuilder
    private func dateControl(_ title: String, value: Binding<Date?>) -> some View {
        if let d = value.wrappedValue {
            HStack(spacing: 4) {
                Text(title + ":").font(.callout).foregroundStyle(Avo.textDim)
                DatePicker(title, selection: Binding(get: { d }, set: { value.wrappedValue = $0 }), displayedComponents: .date)
                    .labelsHidden()
                    .environment(\.timeZone, AvoTime.madrid)
                Button { value.wrappedValue = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Avo.textDim) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Quitar fecha \(title.lowercased())")
            }
            .padding(.leading, 10).padding(.trailing, 6).padding(.vertical, 2)
            .background(Avo.redSoft, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Avo.red, lineWidth: 1))
        } else {
            Button {
                value.wrappedValue = TrainingListFilter.calendar.startOfDay(for: Date())
            } label: {
                Label("\(title): cualquiera", systemImage: "calendar")
            }
            .buttonStyle(.avoSecondary)
        }
    }

    // ------------------------------------------------------------------ table (regular width)
    /// Trainer's sketches 13/11/2026: square rows (no rounded selection), alternating row colours, a neutral selection
    /// (lighter row + red bar on the left) instead of the red / wine tint, bigger «Abrir». Columns sort on tap.
    private func table(_ rows: [TrainingListRow]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: 48)
                sortHeader("Fecha y hora", \TrainingListRow.startKey, flex: 1.3)
                sortHeader("Caballo", \TrainingListRow.horse, flex: 1.4)
                sortHeader("Jinete", \TrainingListRow.rider, flex: 1.2)
                sortHeader("Distancia", \TrainingListRow.distanceKm, flex: 0.8)
                sortHeader("Vel. máx.", \TrainingListRow.maxSpeedKmh, flex: 0.8)
                Text("Abrir").font(.footnote.weight(.semibold)).foregroundStyle(Avo.textDim).frame(width: 72)
            }
            .padding(.vertical, 8)
            .background(Avo.surface)
            .overlay(alignment: .bottom) { Rectangle().fill(Avo.line).frame(height: 1) }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { (p: (offset: Int, element: TrainingListRow)) in
                        tableRow(p.element, odd: p.offset % 2 == 1)
                    }
                }
            }
        }
        .alert("¿Eliminar este entrenamiento?",
               isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
               presenting: pendingDelete) { (s: SessionItem) in
            Button("Eliminar", role: .destructive) {
                app.deleteTraining(s)
                pendingDelete = nil
            }
            Button("Cancelar", role: .cancel) { pendingDelete = nil }
        } message: { (s: SessionItem) in
            Text("\(s.dateTimeText) · \(s.horse) · \(s.distanceText)\n\nSe borrarán del iPad el entrenamiento y todo lo calculado con él: análisis del motor, zonas corregidas, valoración, tramos y notas. Los archivos que tengas en Archivos no se tocan. No se puede deshacer.")
        }
        .font(.callout)
        .background(Avo.bg)
        .accessibilityIdentifier("list.table")
    }

    private func sortHeader<V: Comparable>(_ title: String, _ key: KeyPath<TrainingListRow, V>, flex: CGFloat = 1) -> some View {
        let active: Bool = (sortOrder.first?.keyPath as AnyKeyPath?) == (key as AnyKeyPath)
        let ascending: Bool = sortOrder.first?.order == .forward
        return Button {
            sortOrder = [KeyPathComparator(key, order: active && !ascending ? .forward : .reverse)]
        } label: {
            HStack(spacing: 4) {
                Text(title).font(.footnote.weight(.semibold))
                if active { Image(systemName: ascending ? "chevron.up" : "chevron.down").font(.caption2) }
            }
            .foregroundStyle(active ? Avo.text : Avo.textDim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func tableRow(_ r: TrainingListRow, odd: Bool) -> some View {
        let on: Bool = selection == r.id
        return HStack(spacing: 0) {
            Button {
                model.toggleFavorite(r.id)
            } label: {
                Image(systemName: r.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(r.isFavorite ? Avo.warn : Avo.textDim)
                    .frame(width: 48, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(r.isFavorite ? "Quitar de favoritos" : "Marcar como favorito")
            HStack(spacing: 6) {
                Text(r.dateTimeText).monospacedDigit().foregroundStyle(Avo.text).lineLimit(1)
                if r.isSynthetic { AvoPill(text: "DEMO", color: Avo.warn) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(r.horse).fontWeight(.semibold).foregroundStyle(Avo.text).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(r.rider).foregroundStyle(Avo.silver).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(r.distanceText).monospacedDigit().foregroundStyle(Avo.text).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(r.maxSpeedText).monospacedDigit().foregroundStyle(Avo.text).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                model.open(r.id)
            } label: {
                Image(systemName: "chevron.right.circle.fill").font(.system(size: 30)).foregroundStyle(Avo.red)
                    .frame(width: 72, height: 52)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Abrir en Análisis")
        }
        .frame(minHeight: 56)
        .background(on ? Avo.surface2 : (odd ? Avo.surface : Avo.bg))
        .overlay(alignment: .leading) { if on { Rectangle().fill(Avo.red).frame(width: 4) } }
        .overlay(alignment: .bottom) { Rectangle().fill(Avo.line.opacity(0.6)).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture { selection = r.id }
        .contextMenu { rowMenu(r.id) }
        .accessibilityIdentifier("list.row.\(r.id)")
    }

    @ViewBuilder
    private func rowMenu(_ id: String) -> some View {
        Button {
            model.open(id)
        } label: {
            Label("Abrir en Análisis", systemImage: "waveform.path.ecg")
        }
        Button {
            model.toggleFavorite(id)
        } label: {
            Label((model.item(id)?.isFavorite ?? false) ? "Quitar de favoritos" : "Marcar como favorito", systemImage: "star")
        }
        Button {
            if let s = model.item(id) { app.stable.openAssign(s) }
        } label: {
            Label("Asignar caballo y jinete", systemImage: "figure.equestrian.sports")
        }
        Button {
            if let s = model.item(id) { Task { @MainActor in await app.exportTrainingsAndReport([s]) } }
        } label: {
            Label("Exportar a AVO Horse", systemImage: "square.and.arrow.up")
        }
        Divider()
        Button(role: .destructive) {
            pendingDelete = model.item(id)
        } label: {
            Label("Eliminar entrenamiento…", systemImage: "trash")
        }
    }

    static func originColor(_ o: String) -> Color {
        switch o {
        case "Wi-Fi": return Avo.cyan
        case "Bluetooth": return Avo.blue
        case "Demo": return Avo.warn
        case "Recuperado": return Avo.ok
        default: return Avo.silver
        }
    }

    // ------------------------------------------------------------------ list (compact width)
    private func compactList(_ rows: [TrainingListRow]) -> some View {
        List(rows) { (r: TrainingListRow) in
            Button {
                model.open(r.id)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: r.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(r.isFavorite ? Avo.warn : Avo.textDim)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(r.dateTimeText).font(.callout.weight(.semibold)).monospacedDigit().foregroundStyle(Avo.text)
                            if r.isSynthetic { AvoPill(text: "DEMOSTRACIÓN", color: Avo.warn) }
                        }
                        Text("\(r.horse) · \(r.rider)").font(.footnote).foregroundStyle(Avo.silver).lineLimit(1)
                        Text("\(r.distanceText) · \(r.maxSpeedText)")
                            .font(.caption).monospacedDigit().foregroundStyle(Avo.textDim).lineLimit(1)
                    }
                    Image(systemName: "chevron.right.circle.fill").font(.system(size: 28)).foregroundStyle(Avo.red)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(r.id == app.selected?.id ? Avo.redSoft : Avo.surface)
            .swipeActions(edge: .trailing) {
                Button {
                    model.toggleFavorite(r.id)
                } label: {
                    Label("Favorito", systemImage: r.isFavorite ? "star.slash" : "star")
                }
                .tint(Avo.warn)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Avo.bg)
    }

    // ------------------------------------------------------------------ empty state
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "list.bullet.rectangle").font(.system(size: 34)).foregroundStyle(Avo.red)
            Text("No hay entrenamientos en el iPad").font(.title3.weight(.semibold)).foregroundStyle(Avo.text)
                .padding(.top, 12).padding(.bottom, 6)
            Text("Abre un archivo .avo o .avr, descárgalo del reloj por Wi-Fi o busca entrenamientos que estén en la memoria del iPad (por ejemplo, copiados en Archivos › En mi iPad › AVO Horse) y no se hayan cargado.")
                .font(.footnote).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { emptyButtons }
                VStack(alignment: .leading, spacing: 10) { emptyButtons }
            }
            .padding(.top, 18)
        }
        .padding(28)
        .frame(maxWidth: 620, alignment: .leading)
        .background(Avo.cardBrush, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Avo.line, lineWidth: 1))
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var emptyButtons: some View {
        Button {
            app.showImporter = true
        } label: {
            Label("Abrir", systemImage: "folder")
        }
        .buttonStyle(.avoPrimary)
        Button {
            app.page = .watchWifi
        } label: {
            Label("Reloj Wi-Fi", systemImage: "wifi")
        }
        .buttonStyle(.avoSecondary)
        Button {
            Task { @MainActor in await model.scanDevice() }
        } label: {
            Label("Buscar perdidos", systemImage: "arrow.triangle.2.circlepath")
        }
        .buttonStyle(.avoSecondary)
        .disabled(model.scanning || app.busy)
    }
}

/// Toggle chip of the filters bar.
private struct TrainingListChip: View {
    var title: String
    var icon: String? = nil
    var on: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let i = icon { Image(systemName: i).font(.caption) }
                Text(title)
            }
            .font(.callout.weight(on ? .semibold : .regular))
            .foregroundStyle(on ? Avo.text : Avo.silver)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(on ? Avo.redSoft : Avo.surface2, in: Capsule())
            .overlay(Capsule().stroke(on ? Avo.red : Avo.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Result of «Buscar entrenamientos perdidos».
struct TrainingRecoverySheet: View {
    var report: TrainingRecoveryReport
    var close: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(report.summary).font(.callout.weight(.semibold)).foregroundStyle(Avo.text)
                        Text("Dónde: \(report.folder)").font(.caption).foregroundStyle(Avo.textDim)
                        if report.limited {
                            Text("Se alcanzó el límite de archivos: la búsqueda no revisó todo.").font(.caption).foregroundStyle(Avo.warn)
                        }
                    }
                    .listRowBackground(Avo.surface)
                }
                if report.items.isEmpty {
                    Section {
                        Text("No se encontró ningún archivo .avo, .avr ni carpeta de segmentos fuera de la biblioteca.")
                            .font(.footnote).foregroundStyle(Avo.textDim)
                            .listRowBackground(Avo.surface)
                    }
                }
                ForEach([TrainingRecoveryStatus.recovered, .incomplete, .damaged, .duplicate], id: \.rawValue) { (st: TrainingRecoveryStatus) in
                    let list: [TrainingRecoveryItem] = report.items.filter { $0.status == st }
                    if !list.isEmpty {
                        Section {
                            ForEach(list) { (it: TrainingRecoveryItem) in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: TrainingRecoverySheet.icon(st)).foregroundStyle(TrainingRecoverySheet.color(st))
                                        .padding(.top, 2)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(it.name).font(.callout.weight(.semibold)).foregroundStyle(Avo.text).lineLimit(1)
                                        Text(it.reason).font(.caption).foregroundStyle(Avo.silver)
                                        Text(it.path).font(.caption2).foregroundStyle(Avo.textDim).lineLimit(1).truncationMode(.middle)
                                    }
                                }
                                .listRowBackground(Avo.surface)
                            }
                        } header: {
                            Text("\(TrainingRecoverySheet.sectionTitle(st)) (\(list.count))").foregroundStyle(Avo.silver)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Avo.bg)
            .navigationTitle("Entrenamientos perdidos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { close() }
                }
            }
        }
    }

    static func sectionTitle(_ s: TrainingRecoveryStatus) -> String {
        switch s {
        case .recovered: return "Recuperados"
        case .incomplete: return "Incompletos"
        case .damaged: return "Dañados o rechazados"
        case .duplicate: return "Duplicados (ya cargados)"
        case .pending: return "Pendientes"
        }
    }

    static func icon(_ s: TrainingRecoveryStatus) -> String {
        switch s {
        case .recovered: return "checkmark.circle.fill"
        case .incomplete: return "hourglass"
        case .damaged: return "exclamationmark.triangle.fill"
        case .duplicate: return "doc.on.doc"
        case .pending: return "clock"
        }
    }

    static func color(_ s: TrainingRecoveryStatus) -> Color {
        switch s {
        case .recovered: return Avo.ok
        case .incomplete: return Avo.warn
        case .damaged: return Avo.bad
        case .duplicate: return Avo.textDim
        case .pending: return Avo.cyan
        }
    }
}
