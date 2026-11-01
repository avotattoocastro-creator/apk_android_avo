import SwiftUI

/// Cuadra (kind = .horse) and Jinetes (kind = .rider): port of windows/AVO.Windows/Views/StableView.xaml.
struct StableView: View {
    let kind: IdentityKind
    @Environment(AppModel.self) private var app

    var body: some View {
        let page: StableIdentityPage = app.stable.page(kind)
        VStack(alignment: .leading, spacing: 14) {
            header(page)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    StableListCard(page: page).frame(width: 330)
                    StableDetailPane(page: page)
                }
                .frame(minWidth: 760)
                VStack(alignment: .leading, spacing: 14) {
                    StableListCard(page: page).frame(maxHeight: 360)
                    StableDetailPane(page: page)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Avo.bg)
        .onAppear { app.stable.pageShown() }
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
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                AvoPageTitle(title: page.title, subtitle: "\(page.allRows.count) registrados · \(page.unknownText)")
                Spacer(minLength: 8)
                StableLinkCard().frame(maxWidth: 560)
            }
            VStack(alignment: .leading, spacing: 10) {
                AvoPageTitle(title: page.title, subtitle: "\(page.allRows.count) registrados · \(page.unknownText)")
                StableLinkCard()
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

    var body: some View {
        if !page.hasSelection {
            AvoCard {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: page.isHorse ? "list.bullet.rectangle" : "person.crop.rectangle")
                        .font(.system(size: 34)).foregroundStyle(Avo.red)
                    Text("Elige uno de la lista, crea uno nuevo o pega el enlace de su etiqueta")
                        .font(.headline).foregroundStyle(Avo.text)
                    Text("El iPad no tiene NFC: graba las etiquetas con el móvil Android o con Windows. Si copias el enlace avohorse://identity/… de una ficha (por ejemplo desde Windows o Android) y pulsas «Pegar enlace avohorse://…», se registra aquí. Si ya existe, no se sobrescribe. Los entrenamientos importados también registran el caballo y el jinete que traen.")
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
                        StableTrainingsCard(page: page, row: sel)
                    }
                }
            }
        }
    }
}

private struct StableEditorCard: View {
    let page: StableIdentityPage
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var p = page
        AvoCard(title: page.header) {
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
                            TextField("", text: $p.editBreed).modifier(StableFieldStyle())
                        }
                        field("AÑO DE NACIMIENTO") {
                            TextField("", text: $p.editYear).keyboardType(.numberPad).modifier(StableFieldStyle())
                        }
                    }
                }
                field("NOTAS") {
                    TextField("", text: $p.editNotes, axis: .vertical).lineLimit(2...5).modifier(StableFieldStyle())
                }
                Toggle("Activo (aparece al asignar entrenamientos)", isOn: $p.editActive).font(.footnote).tint(Avo.red)

                HStack(spacing: 8) {
                    Button("Guardar") { page.save() }
                        .buttonStyle(.avoPrimary)
                        .disabled(!page.canSave)
                        .accessibilityIdentifier("stable.save")
                    if !page.isNew && page.selected != nil {
                        Button {
                            UIPasteboard.general.string = page.uriText
                            page.message = "Enlace copiado: pégalo en la app Android o en Windows para grabar la etiqueta."
                        } label: {
                            Label("Copiar enlace avohorse://", systemImage: "link")
                        }
                        .buttonStyle(.avoSecondary)
                        Button("Eliminar", role: .destructive) { page.askDelete() }
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
                    Text("El iPad no tiene NFC: graba las etiquetas con el móvil Android o con Windows")
                        .font(.caption2).foregroundStyle(Avo.textDim)
                }
            }
        }
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
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
            AvoMetric(label: "Entrenamientos", value: String(row.count), caption: "Asignados o del archivo")
            AvoMetric(label: "Distancia", value: row.distanceText, caption: "Suma")
            AvoMetric(label: "Tiempo", value: row.totalTimeText, caption: "Suma")
            AvoMetric(label: "V. máxima", value: row.bestSpeedText, caption: "Filtrada")
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
                                StableTrainingRow(s: s, open: { app.stable.openTraining(s) },
                                                  assign: { app.stable.openAssign(s) })
                                Divider().overlay(Avo.line)
                            }
                        }
                    }
                }
            }
        }
    }
}

private enum StableCols {
    static let date: CGFloat = 130, name: CGFloat = 130, dist: CGFloat = 85, dur: CGFloat = 75, speed: CGFloat = 85,
               fix: CGFloat = 65, origin: CGFloat = 110, actions: CGFloat = 170
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
            cell("RTK FIX", StableCols.fix)
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
    let assign: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            cell(s.dateTimeText, StableCols.date)
            cell(s.horse, StableCols.name)
            cell(s.rider, StableCols.name)
            cell(s.distanceText, StableCols.dist)
            cell(s.durationText, StableCols.dur)
            cell(s.maxSpeedText, StableCols.speed)
            cell(s.fixText, StableCols.fix)
            HStack(spacing: 4) {
                if s.isSynthetic { AvoPill(text: "DEMOSTRACIÓN", color: Avo.warn) } else { Text(s.kind) }
            }
            .frame(width: StableCols.origin, alignment: .leading)
            HStack(spacing: 6) {
                Button("Abrir", action: open).buttonStyle(.avoSecondary)
                Button("Asignar", action: assign).buttonStyle(.avoSecondary)
            }
            .frame(width: StableCols.actions, alignment: .leading)
        }
        .font(.footnote).foregroundStyle(Avo.text)
        .padding(.vertical, 4)
    }
    private func cell(_ t: String, _ w: CGFloat) -> some View {
        Text(t).lineLimit(1).truncationMode(.tail).frame(width: w, alignment: .leading)
    }
}
