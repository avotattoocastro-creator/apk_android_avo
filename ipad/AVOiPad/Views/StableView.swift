import SwiftUI
import PhotosUI

/// Cuadra (kind = .horse) and Jinetes (kind = .rider): port of windows/AVO.Windows/Views/StableView.xaml.
struct StableView: View {
    let kind: IdentityKind
    @Environment(AppModel.self) private var app

    var body: some View {
        let page: StableIdentityPage = app.stable.page(kind)
        VStack(alignment: .leading, spacing: 14) {
            // trainer's sketch 13/11/2026: one full-width row per horse / rider in a scrolling list; tapping one opens its
            // card on the whole page. Sketch 14/11/2026: no «‹ Cuadra» button above the card (it goes up to the top) and
            // an «X» at the top-right corner of the card to go back to the list
            if page.hasSelection {
                StableDetailPane(page: page)
            } else {
                // trainer's sketch 14/11/2026: no counts line; «Mostrar inactivos» and «France Galop» go into the
                // toolbar row of the list, right after the search
                StableFullList(page: page)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Avo.bg)
        .onAppear { app.stable.pageShown() }
        .raceImport(app.races) { (e: Error) in app.fail(e) }
        .alert(app.stable.confirm?.title ?? "",
               isPresented: Binding(get: { app.stable.confirm != nil }, set: { if !$0 { app.stable.confirm = nil } }),
               presenting: app.stable.confirm) { c in
            Button("Cancelar", role: .cancel) { app.stable.confirm = nil }
            Button(c.okLabel, role: c.destructive ? .destructive : nil) {
                app.stable.confirm = nil
                c.action()
            }
        } message: { c in
            Text(c.message)
        }
    }

    @ViewBuilder
    private func header(_ page: StableIdentityPage) -> some View {
        // the «El iPad no tiene NFC…» card was removed at the trainer's request (07/11/2026)
        HStack(alignment: .center, spacing: 12) {
            // no page title (trainer's sketch 14/11/2026); the counts stay visible in the list
            if !page.hasSelection {
                Text("\(page.allRows.count) registrados · \(page.unknownText)").font(.footnote).foregroundStyle(Avo.textDim)
            }
            Spacer(minLength: 8)
            if page.isHorse && !page.hasSelection {
                // whole stable from France Galop: open the trainer's page, link the horses, refresh them all
                Button {
                    app.franceGalop.open()
                } label: {
                    Label("France Galop", systemImage: "globe.europe.africa")
                }
                .buttonStyle(.avoPrimary)
                .accessibilityIdentifier("stable.franceGalopAll")
            }
        }
    }
}

/// Replaces the Windows NFC reader box: the iPad has no NFC, a copied avohorse:// link can be pasted instead.
private struct StableLinkCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle().fill(Avo.redSoft).frame(width: 34, height: 34)
                Image(systemName: "wave.3.right").font(.footnote.weight(.semibold)).foregroundStyle(Avo.redLight)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("El iPad no tiene NFC: graba las etiquetas con el móvil Android o con Windows")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Avo.text).fixedSize(horizontal: false, vertical: true)
                if !app.stable.linkLast.isEmpty {
                    Text(app.stable.linkLast).font(.caption)
                        .foregroundStyle(app.stable.linkLastOk ? Avo.ok : Avo.warn)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Para registrar una ficha desde otra app AVO, copia su enlace avohorse://identity/… y pégalo aquí.")
                        .font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            Button {
                app.stable.pasteLink()
            } label: {
                Label("Pegar enlace avohorse://…", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.avoSecondary)
            .accessibilityIdentifier("stable.pasteLink")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Avo.cardBrush, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Avo.line, lineWidth: 1))
    }
}

// MARK: - list

/// Full-width list (trainer's sketch 13/11/2026): toolbar (nuevo, buscar, inactivos) and one wide row per record,
/// alternating colours like «Entrenamientos».
private struct StableFullList: View {
    let page: StableIdentityPage
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var p = page
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    page.startNew()
                } label: {
                    Label(page.newLabel, systemImage: "plus")
                }
                .buttonStyle(.avoPrimary)
                .accessibilityIdentifier("stable.new")
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Avo.textDim)
                    TextField("Buscar por nombre, código o raza", text: $p.search)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                .padding(8)
                .frame(maxWidth: 380)
                .background(Avo.surface2, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Avo.line, lineWidth: 1))
                Toggle("Mostrar inactivos", isOn: $p.showInactive).font(.footnote).tint(Avo.red).fixedSize()
                if page.isHorse {
                    // whole stable from France Galop: open the trainer's page, link the horses, refresh them all
                    Button { app.franceGalop.open() } label: { Label("France Galop", systemImage: "globe.europe.africa") }
                        .buttonStyle(.avoPrimary)
                        .accessibilityIdentifier("stable.franceGalopAll")
                }
                Spacer(minLength: 0)
            }
            if page.isEmpty {
                AvoNoData(text: page.emptyText)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(page.items.enumerated()), id: \.element.id) { (q: (offset: Int, element: StableIdentityRow)) in
                            StableWideRow(row: q.element)
                                .background(q.offset % 2 == 1 ? Avo.surface : Avo.bg)
                                .overlay(alignment: .bottom) { Rectangle().fill(Avo.line.opacity(0.6)).frame(height: 1) }
                                .contentShape(Rectangle())
                                .onTapGesture { page.choose(q.element) }
                        }
                    }
                }
                .overlay(Rectangle().stroke(Avo.line, lineWidth: 1))
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct StableWideRow: View {
    let row: StableIdentityRow
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(Avo.surface2).frame(width: 48, height: 48)
                if let img = IdentityPhotos.load(app.paths.root, row.code) {
                    Image(uiImage: img).resizable().scaledToFill().frame(width: 48, height: 48).clipShape(Circle())
                } else {
                    Text(row.initial).font(.system(size: 20, weight: .semibold)).foregroundStyle(Avo.silver)
                }
                Circle().stroke(Avo.line, lineWidth: 1).frame(width: 48, height: 48)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(row.name).font(.title3.weight(.semibold)).foregroundStyle(row.active ? Avo.text : Avo.textDim).lineLimit(1)
                    if row.isDemo { AvoPill(text: "DEMO", color: Avo.warn) }
                    if !row.active { AvoPill(text: "INACTIVO", color: Avo.unknown) }
                }
                Text(row.subtitle).font(.footnote).foregroundStyle(Avo.textDim).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(row.countText).font(.callout.monospacedDigit()).foregroundStyle(Avo.silver).frame(width: 150, alignment: .trailing)
            Text(row.distanceText).font(.callout.monospacedDigit()).foregroundStyle(Avo.silver).frame(width: 90, alignment: .trailing)
            if row.hasNfc {
                Image(systemName: "wave.3.right").font(.callout).foregroundStyle(Avo.cyan).accessibilityLabel("Tiene etiqueta NFC")
            }
            Image(systemName: "chevron.right").font(.callout).foregroundStyle(Avo.textDim)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .accessibilityIdentifier("stable.row.\(row.code)")
    }
}

private struct StableListCard: View {
    let page: StableIdentityPage

    var body: some View {
        @Bindable var p = page
        AvoCard(title: page.title) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    page.startNew()
                } label: {
                    Label(page.newLabel, systemImage: "plus")
                }
                .buttonStyle(.avoPrimary)
                .accessibilityIdentifier("stable.new")

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Avo.textDim)
                    TextField("Buscar por nombre, código o raza", text: $p.search)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                .padding(8)
                .background(Avo.surface2, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Avo.line, lineWidth: 1))

                Toggle("Mostrar inactivos", isOn: $p.showInactive).font(.footnote).tint(Avo.red)

                if page.isEmpty {
                    Text(page.emptyText).font(.footnote).foregroundStyle(Avo.textDim)
                        .fixedSize(horizontal: false, vertical: true).padding(.vertical, 8)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(page.items) { row in
                                StableRowView(row: row, selected: !page.isNew && page.selectedCode == row.code)
                                    .contentShape(Rectangle())
                                    .onTapGesture { page.choose(row) }
                            }
                        }
                    }
                    .frame(minHeight: 160)
                }
            }
        }
    }
}

private struct StableRowView: View {
    let row: StableIdentityRow
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Avo.surface2).frame(width: 38, height: 38)
                Circle().stroke(Avo.line, lineWidth: 1).frame(width: 38, height: 38)
                Text(row.initial).font(.system(size: 16, weight: .semibold)).foregroundStyle(Avo.silver)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.name).font(.callout.weight(.semibold)).foregroundStyle(Avo.text).lineLimit(1)
                    if row.isDemo { AvoPill(text: "DEMO", color: Avo.warn) }
                }
                Text(row.subtitle).font(.caption).foregroundStyle(Avo.textDim).lineLimit(1)
                Text("\(row.countText) · \(row.distanceText)").font(.caption).foregroundStyle(Avo.textDim).lineLimit(1)
            }
            Spacer(minLength: 4)
            if row.hasNfc {
                Image(systemName: "wave.3.right").font(.caption).foregroundStyle(Avo.cyan)
                    .accessibilityLabel("Tiene etiqueta NFC")
            }
        }
        .padding(8)
        .background(selected ? Avo.redSoft : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? Avo.red.opacity(0.6) : Color.clear, lineWidth: 1))
    }
}

// MARK: - detail

private struct StableDetailPane: View {
    let page: StableIdentityPage
    @Environment(AppModel.self) private var app
    @State private var trainingsOpen: Bool = false
    @State private var stretchesOpen: Bool = false

    var body: some View {
        if !page.hasSelection {
            AvoCard {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: page.isHorse ? "list.bullet.rectangle" : "person.crop.rectangle")
                        .font(.system(size: 34)).foregroundStyle(Avo.red)
                    Text("Elige uno de la lista o crea uno nuevo")
                        .font(.headline).foregroundStyle(Avo.text)
                    Text("Los entrenamientos importados también registran el caballo y el jinete que traen.")
                        .font(.footnote).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    StableEditorCard(page: page)
                    if !page.isNew, let sel = page.selected {
                        StableTotals(row: sel)
                        // trainings and saved stretches first, each one folding (trainer's sketch 14/11/2026)
                        StableFold(title: "Entrenamientos de \(sel.name)", count: sel.count, open: $trainingsOpen) {
                            StableTrainingsCard(page: page, row: sel)
                        }
                        if page.isHorse {
                            StableFold(title: "Tramos guardados de \(sel.name)", count: nil, open: $stretchesOpen) {
                                StableStretchesCard(row: sel)
                            }
                        }
                        if page.isHorse {
                            Button {
                                app.horseHistory.open(horseKey: sel.code, name: sel.name)
                            } label: {
                                Label("Historia de entrenamientos", systemImage: "chart.line.uptrend.xyaxis")
                            }
                            .buttonStyle(.avoPrimary)
                            .disabled(sel.count == 0)
                            .accessibilityIdentifier("stable.horseHistory")
                            StableRacesCard(row: sel)
                            FranceGalopHorseCard(row: sel)
                        }
                    }
                }
            }
        }
    }
}

private struct StableEditorCard: View {
    let page: StableIdentityPage
    @Environment(AppModel.self) private var app

    @State private var photoItem: PhotosPickerItem? = nil
    @State private var photoVersion: Int = 0

    var body: some View {
        @Bindable var p = page
        AvoCard(title: page.header) {
            VStack(alignment: .leading, spacing: 10) {
            // trainer's sketch 14/11/2026: photo on the left, the data on its right
            HStack(alignment: .top, spacing: 16) {
                photoBox
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        nameField(p)
                        codeField(p)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        nameField(p)
                        codeField(p)
                    }
                }
                if page.isHorse {
                    HStack(alignment: .top, spacing: 16) {
                        field("RAZA") {
                            VStack(alignment: .leading, spacing: 6) {
                                Menu {
                                    ForEach(RacingBreed.groups, id: \.self) { (g: String) in
                                        Section(g) {
                                            ForEach(RacingBreed.all.filter { $0.group == g }) { (b: RacingBreed) in
                                                Button {
                                                    p.editBreed = b.label == "Otra" ? "" : b.label
                                                } label: {
                                                    if p.editBreed == b.label { Label(b.label, systemImage: "checkmark") } else { Text(b.label) }
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(p.editBreed.isEmpty ? "Elegir raza…" : p.editBreed)
                                            .foregroundStyle(p.editBreed.isEmpty ? Avo.textDim : Avo.text).lineLimit(1)
                                        Spacer(minLength: 4)
                                        Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(Avo.textDim)
                                    }
                                    .modifier(StableFieldStyle())
                                }
                                if !RacingBreed.all.contains(where: { $0.label == p.editBreed }) {
                                    TextField("Otra raza (escribe)", text: $p.editBreed).modifier(StableFieldStyle())
                                }
                                Text(RacingBreed.profileText(p.editBreed)).font(.caption2).foregroundStyle(Avo.textDim)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        field("AÑO DE NACIMIENTO") {
                            TextField("", text: $p.editYear).keyboardType(.numberPad).modifier(StableFieldStyle())
                        }
                    }
                }
                field("NOTAS") {
                    TextField("", text: $p.editNotes, axis: .vertical).lineLimit(2...5).modifier(StableFieldStyle())
                }
            }
            }
                Toggle("Activo (aparece al asignar entrenamientos)", isOn: $p.editActive).font(.footnote).tint(Avo.red)

                // the three buttons the same width AND height, one line each (trainer 14/11/2026: «misma medida alto»)
                HStack(spacing: 8) {
                    Button { page.save() } label: { Text("Guardar").lineLimit(1).frame(width: 230, height: 30) }
                        .buttonStyle(.avoPrimary)
                        .disabled(!page.canSave)
                        .accessibilityIdentifier("stable.save")
                    if !page.isNew && page.selected != nil {
                        Button {
                            UIPasteboard.general.string = page.uriText
                            page.message = "Enlace copiado: pégalo en la app Android o en Windows para grabar la etiqueta."
                        } label: {
                            Label("Copiar enlace", systemImage: "link").lineLimit(1).frame(width: 230, height: 30)
                        }
                        .buttonStyle(.avoSecondary)
                        Button(role: .destructive) { page.askDelete() } label: { Text("Eliminar").lineLimit(1).frame(width: 230, height: 30) }
                            .buttonStyle(.avoSecondary)
                            .foregroundStyle(Avo.bad)
                    }
                }
                if !page.message.isEmpty {
                    Text(page.message).font(.caption).foregroundStyle(Avo.cyan).fixedSize(horizontal: false, vertical: true)
                }
                if !page.isNew {
                    Text(page.tagText + (page.originText.isEmpty ? "" : "  ·  " + page.originText))
                        .font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        // «Salir» (trainer's sketch 14/11/2026): X at the top-right corner of the card, back to the list
        .overlay(alignment: .topTrailing) {
            Button { page.backToList() } label: {
                Image(systemName: "xmark.circle.fill").font(.title2).symbolRenderingMode(.hierarchical).foregroundStyle(Avo.red)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(4)
            .accessibilityLabel("Salir")
            .accessibilityIdentifier("stable.back")
        }
    }

    private var photoCode: String { page.isNew ? "" : (page.selected?.code ?? "") }

    /// Photo of the horse / rider: tap to choose one from Fotos; long press to remove it.
    private var photoBox: some View {
        let img: UIImage? = { _ = photoVersion; return IdentityPhotos.load(app.paths.root, photoCode) }()
        return PhotosPicker(selection: $photoItem, matching: .images) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Avo.surface2)
                if let img = img {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: page.isHorse ? "camera" : "person.crop.square").font(.system(size: 30, weight: .light))
                        Text(photoCode.isEmpty ? "Guarda primero para añadir foto" : "Añadir foto")
                            .font(.caption).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(Avo.textDim)
                    .padding(8)
                }
            }
            .frame(width: 190, height: 230)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Avo.line, lineWidth: 1))
        }
        .disabled(photoCode.isEmpty)
        .contextMenu {
            if img != nil {
                Button(role: .destructive) {
                    IdentityPhotos.remove(app.paths.root, photoCode)
                    photoVersion += 1
                } label: { Label("Quitar foto", systemImage: "trash") }
            }
        }
        .onChange(of: photoItem) { (_: PhotosPickerItem?, item: PhotosPickerItem?) in
            guard let item = item else { return }
            let code: String = photoCode
            Task { @MainActor in
                if let data = try? await item.loadTransferable(type: Data.self) {
                    IdentityPhotos.save(app.paths.root, code, data)
                    photoVersion += 1
                }
                photoItem = nil
            }
        }
        .accessibilityIdentifier("stable.photo")
    }

    private func nameField(_ p: StableIdentityPage) -> some View {
        @Bindable var b = p
        return field("NOMBRE") {
            TextField("", text: $b.editName).modifier(StableFieldStyle())
                .accessibilityIdentifier("stable.name")
        }
    }

    private func codeField(_ p: StableIdentityPage) -> some View {
        let binding = Binding<String>(get: { p.editCode },
                                      set: { (v: String) in p.editCode = String(v.uppercased().prefix(23)) })
        return field("CÓDIGO (RELOJ Y ETIQUETA NFC)") {
            TextField("", text: binding)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .disabled(!p.codeEditable)
                .foregroundStyle(p.codeEditable ? Avo.text : Avo.textDim)
                .modifier(StableFieldStyle())
        }
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StableFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(8)
            .background(Avo.surface2, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Avo.line, lineWidth: 1))
    }
}

private struct StableTotals: View {
    let row: StableIdentityRow

    var body: some View {
        // one row of 6, «Datos clave» style (trainer 14/11/2026; «Mejor 200 m» added between V. máxima and Último)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 6), spacing: 0) {
            AvoMetric(label: "Entrenamientos", value: String(row.count), caption: "Asignados o del archivo")
            AvoMetric(label: "Distancia", value: row.distanceText, caption: "Suma")
            AvoMetric(label: "Tiempo", value: row.totalTimeText, caption: "Suma")
            AvoMetric(label: "V. máxima", value: row.bestSpeedText, caption: "Filtrada")
            AvoMetric(label: "Mejor 200 m", value: row.best200Text, caption: "Motor AVO")
            AvoMetric(label: "Último", value: row.lastDateText, caption: "Europe/Madrid")
        }
    }
}

private struct StableTrainingsCard: View {
    let page: StableIdentityPage
    let row: StableIdentityRow
    @Environment(AppModel.self) private var app

    var body: some View {
        AvoCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    Text("ENTRENAMIENTOS DE \(row.name.uppercased())")
                        .font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(Avo.silver)
                    Spacer()
                    Button("Asignar a los \(page.unknownCount) sin \(page.singular)") { page.askAssignUnknown() }
                        .buttonStyle(.avoSecondary)
                        .disabled(page.unknownCount == 0)
                }
                let list: [SessionItem] = page.trainings
                if list.isEmpty {
                    Text("Sin entrenamientos todavía. Asígnalos desde «Entrenamientos» (botón Asignar) o con el botón de arriba.")
                        .font(.footnote).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            StableTrainingHeader()
                            ForEach(list) { s in
                                StableTrainingRow(s: s, open: { app.stable.openTraining(s) })
                                Divider().overlay(Avo.line)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// «Tramos guardados» of the horse: stretches saved from «Análisis tramo» for later comparisons (App/StretchModel.swift).
private struct StableStretchesCard: View {
    let row: StableIdentityRow
    @Environment(AppModel.self) private var app

    var body: some View {
        let list: [SavedStretch] = app.stretch.savedOf(horse: row.code)
        AvoCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("TRAMOS GUARDADOS DE \(row.name.uppercased())")
                    .font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(Avo.silver)
                if list.isEmpty {
                    Text("Sin tramos guardados. En «Mapa», selecciona un tramo en la gráfica, pulsa «Análisis tramo» y «Guardar en \(row.name)».")
                        .font(.footnote).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: 8) {
                        Text("ENTRENAMIENTO · TRAMO").frame(maxWidth: .infinity, alignment: .leading)
                        Text("DIST.").frame(width: 70, alignment: .trailing)
                        Text("TIEMPO").frame(width: 64, alignment: .trailing)
                        Text("MEDIA").frame(width: 64, alignment: .trailing)
                        Text("MÁX.").frame(width: 64, alignment: .trailing)
                        Text("MEJOR 200").frame(width: 80, alignment: .trailing)
                        Spacer().frame(width: 150)
                    }
                    .font(.caption2.weight(.semibold)).foregroundStyle(Avo.textDim)
                    ForEach(list) { (s: SavedStretch) in
                        StableStretchRow(s: s)
                        Divider().overlay(Avo.line)
                    }
                }
            }
        }
    }
}

/// One saved stretch of the horse (own view: keeps the type checker fast in Release builds).
private struct StableStretchRow: View {
    let s: SavedStretch
    @Environment(AppModel.self) private var app

    private var subtitle: String {
        var t: String = s.name.isEmpty ? "" : s.name + " · "
        t += TimeText.clock(s.t0) + " – " + TimeText.clock(s.t1)
        if !s.aiText.isEmpty { t += " · con análisis IA" }
        return t
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(s.sessionDate).font(.callout.weight(.semibold)).foregroundStyle(Avo.text)
                Text(subtitle).font(.caption).foregroundStyle(Avo.textDim).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            numbers
            actions
        }
        .padding(.vertical, 4)
    }

    private var numbers: some View {
        HStack(spacing: 8) {
            Text(TimeText.num(s.distanceM, "0", " m")).frame(width: 70, alignment: .trailing)
            Text(TimeText.clock(s.durationS)).frame(width: 64, alignment: .trailing)
            Text(TimeText.num(s.meanKmh, "0.0")).frame(width: 64, alignment: .trailing)
            Text(TimeText.num(s.maxKmh, "0.0")).frame(width: 64, alignment: .trailing)
            Text(TimeText.num(s.best200S, "0.00", " s")).frame(width: 80, alignment: .trailing)
        }
        .font(.callout.monospacedDigit()).foregroundStyle(Avo.text)
    }

    private var actions: some View {
        HStack(spacing: 6) {
            Button("Abrir") { app.stretch.openSaved(s) }.buttonStyle(.avoSecondary)
            Button(role: .destructive) { app.stretch.delete(s.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.avoSecondary).foregroundStyle(Avo.bad)
                .accessibilityLabel("Borrar tramo")
        }
        .frame(width: 150, alignment: .trailing)
    }
}

/// «Carreras» of the horse (race card on tap) and «Añadir carrera» (tracking PDF, App/RacesModel.swift).
private struct StableRacesCard: View {
    let row: StableIdentityRow
    @Environment(AppModel.self) private var app

    var body: some View {
        let list: [Race] = app.races.racesOf(horse: row.code)
        AvoCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    Text("CARRERAS DE \(row.name.uppercased())")
                        .font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(Avo.silver)
                    Spacer()
                    if app.races.busy { ProgressView().controlSize(.small) }
                    Button {
                        app.races.startImport(horseCode: row.code)
                    } label: {
                        Label("Añadir carrera", systemImage: "flag.checkered")
                    }
                    .buttonStyle(.avoPrimary)
                    .disabled(app.races.busy)
                    .accessibilityIdentifier("stable.addRace")
                }
                if list.isEmpty {
                    Text("Sin carreras. Pulsa «Añadir carrera» y elige el PDF «Statistiques Tracking» de la carrera: se busca a \(row.name) entre los participantes, se transcribe la carrera y se analiza con sus entrenamientos.")
                        .font(.footnote).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(list) { (r: Race) in
                        RaceRowView(race: r)
                            .contentShape(Rectangle())
                            .onTapGesture { app.races.open(r) }
                    }
                }
            }
        }
    }
}

private enum StableCols {
    static let date: CGFloat = 130, name: CGFloat = 130, dist: CGFloat = 85, dur: CGFloat = 75, speed: CGFloat = 85,
               origin: CGFloat = 110, actions: CGFloat = 520
}

private struct StableTrainingHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            cell("Fecha", StableCols.date)
            cell("Caballo", StableCols.name)
            cell("Jinete", StableCols.name)
            cell("Distancia", StableCols.dist)
            cell("Duración", StableCols.dur)
            cell("V. máx", StableCols.speed)
            cell("Origen", StableCols.origin)
            cell("", StableCols.actions)
        }
        .font(.caption2.weight(.semibold)).foregroundStyle(Avo.textDim)
        .padding(.vertical, 6)
    }
    private func cell(_ t: String, _ w: CGFloat) -> some View { Text(t.uppercased()).frame(width: w, alignment: .leading) }
}

private struct StableTrainingRow: View {
    let s: SessionItem
    let open: () -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 8) {
            cell(s.dateTimeText, StableCols.date)
            cell(s.horse, StableCols.name)
            cell(s.rider, StableCols.name)
            cell(s.distanceText, StableCols.dist)
            cell(s.durationText, StableCols.dur)
            cell(s.maxSpeedText, StableCols.speed)
            HStack(spacing: 4) {
                if s.isSynthetic { AvoPill(text: "DEMOSTRACIÓN", color: Avo.warn) } else { Text(s.kind) }
            }
            .frame(width: StableCols.origin, alignment: .leading)
            StableTrainingActions(s: s, open: open)
                .frame(width: StableCols.actions, alignment: .leading)
        }
        .font(.footnote).foregroundStyle(Avo.text)
        .padding(.vertical, 4)
    }
    private func cell(_ t: String, _ w: CGFloat) -> some View {
        Text(t).lineLimit(1).truncationMode(.tail).frame(width: w, alignment: .leading)
    }
}

/// Buttons of a training in the horse sheet (trainer's sketch 09/11/2026): Abrir · Tramo (saved stretches of the training)
/// · Análisis IA (saved «Informes IA» of the Asistente IA) · Informe completo (PDF of «Informes»).
private struct StableTrainingActions: View {
    let s: SessionItem
    let open: () -> Void
    @Environment(AppModel.self) private var app
    @State private var building: Bool = false

    var body: some View {
        let stretches: [SavedStretch] = stretchesOfTraining
        let reports: [SavedAIReport] = app.assistant.reportsOf(s)
        HStack(spacing: 6) {
            Button("Abrir", action: open).buttonStyle(.avoSecondary)
            stretchButton(stretches)
            reportButton(reports)
            Button {
                building = true
                Task { @MainActor in
                    await app.reports.openFullReport(s)
                    building = false
                }
            } label: {
                if building { ProgressView().controlSize(.small) } else { Label("Informe completo", systemImage: "doc.richtext") }
            }
            .buttonStyle(.avoSecondary)
            .disabled(building)
        }
    }

    private var stretchesOfTraining: [SavedStretch] {
        _ = app.stretch.version
        guard let code = s.horseCode, !code.isEmpty else { return [] }
        return app.stretch.savedOf(horse: code).filter { $0.sessionId == s.id }.sorted { $0.t0 < $1.t0 }
    }

    @ViewBuilder
    private func stretchButton(_ list: [SavedStretch]) -> some View {
        if list.count > 1 {
            Menu {
                ForEach(list) { (st: SavedStretch) in
                    Button((st.name.isEmpty ? "" : st.name + " · ") + TimeText.clock(st.t0) + " – " + TimeText.clock(st.t1)) {
                        app.stretch.openSaved(st)
                    }
                }
            } label: {
                Label("Tramo (\(list.count))", systemImage: "ruler")
            }
            .buttonStyle(.avoSecondary)
        } else {
            Button { if let st = list.first { app.stretch.openSaved(st) } } label: { Label("Tramo", systemImage: "ruler") }
                .buttonStyle(.avoSecondary)
                .disabled(list.isEmpty)
                .opacity(list.isEmpty ? 0.45 : 1)
        }
    }

    @ViewBuilder
    private func reportButton(_ list: [SavedAIReport]) -> some View {
        if list.count > 1 {
            Menu {
                ForEach(list) { (r: SavedAIReport) in
                    Button(r.menuTitle) { app.assistant.openReport(r) }
                }
            } label: {
                Label("Análisis IA (\(list.count))", systemImage: "sparkles")
            }
            .buttonStyle(.avoSecondary)
        } else {
            Button { if let r = list.first { app.assistant.openReport(r) } } label: { Label("Análisis IA", systemImage: "sparkles") }
                .buttonStyle(.avoSecondary)
                .disabled(list.isEmpty)
                .opacity(list.isEmpty ? 0.45 : 1)
        }
    }
}

/// Folding section of the card (trainer's sketch 14/11/2026: «Ocultar / Desplegar»).
private struct StableFold<Content: View>: View {
    let title: String
    let count: Int?
    @Binding var open: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { open.toggle() }
            } label: {
                HStack {
                    Text(title.uppercased()).font(.caption.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.silver)
                    if let n = count { Text("\(n)").font(.caption.monospacedDigit()).foregroundStyle(Avo.textDim) }
                    Spacer()
                    Label(open ? "Ocultar" : "Desplegar", systemImage: open ? "chevron.up" : "chevron.down")
                        .font(.callout.weight(.semibold)).foregroundStyle(Avo.red)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Avo.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Avo.line, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open { content() }
        }
    }
}
