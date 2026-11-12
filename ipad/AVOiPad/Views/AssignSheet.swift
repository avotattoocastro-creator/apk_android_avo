import SwiftUI

/// «Caballo y jinete del entrenamiento»: port of the Assign overlay of windows/AVO.Windows/MainWindow.xaml.
/// Presented by RootView while `app.stable.assignVisible` is true. Only the metadata on this iPad changes (cuadra.json).
struct AssignSheet: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let st: StableModel = app.stable
        @Bindable var m = st
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Caballo y jinete del entrenamiento").font(.title2.weight(.semibold)).foregroundStyle(Avo.text)
                    if let t = st.assignTarget {
                        HStack(spacing: 6) {
                            Text("\(t.dateTimeText) · \(t.distanceText) · \(t.kind)").font(.footnote).foregroundStyle(Avo.textDim)
                            if t.isSynthetic { AvoPill(text: "DEMOSTRACIÓN", color: Avo.warn) }
                        }
                    }
                    Text(st.assignFileText).font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        AssignField(kind: .horse, text: $m.assignHorseText)
                        AssignField(kind: .rider, text: $m.assignRiderText)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        AssignField(kind: .horse, text: $m.assignHorseText)
                        AssignField(kind: .rider, text: $m.assignRiderText)
                    }
                }

                // NFC box of Windows → pasted link on the iPad
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "wave.3.right").foregroundStyle(Avo.cyan)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("El iPad no tiene NFC: graba las etiquetas con el móvil Android o con Windows").font(.footnote)
                            .foregroundStyle(Avo.text).fixedSize(horizontal: false, vertical: true)
                        if !st.linkLast.isEmpty {
                            Text(st.linkLast).font(.caption).foregroundStyle(st.linkLastOk ? Avo.ok : Avo.warn)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button {
                            st.pasteLink()
                        } label: {
                            Label("Pegar enlace avohorse://…", systemImage: "doc.on.clipboard")
                        }
                        .buttonStyle(.avoSecondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Avo.surface2, in: RoundedRectangle(cornerRadius: 6))

                if st.hasAssignOthers {
                    Toggle(st.assignOthersText, isOn: $m.assignAlsoUnknown).font(.footnote).tint(Avo.red)
                }
                Text(st.assignMessage).font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        clearButton(st)
                        Spacer()
                        cancelButton(st)
                        saveButton(st)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        clearButton(st)
                        HStack(spacing: 8) {
                            cancelButton(st)
                            saveButton(st)
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Avo.bg)
        .presentationDetents([.large])
        .interactiveDismissDisabled(false)
    }

    private func clearButton(_ st: StableModel) -> some View {
        Button("Vaciar (volver a lo del archivo)") { st.clearAssign() }
            .buttonStyle(.plain).font(.callout).foregroundStyle(Avo.textDim)
            .accessibilityIdentifier("assign.clear")
    }
    private func cancelButton(_ st: StableModel) -> some View {
        Button("Cancelar") { st.cancelAssign() }
            .buttonStyle(.avoSecondary)
            .accessibilityIdentifier("assign.cancel")
    }
    private func saveButton(_ st: StableModel) -> some View {
        Button("Guardar") { st.confirmAssign() }
            .buttonStyle(.avoPrimary)
            .accessibilityIdentifier("assign.save")
    }
}

/// Text field (name or code; created in the Cuadra/Jinetes if new) with suggestions and a picker of saved records.
private struct AssignField: View {
    let kind: IdentityKind
    @Binding var text: String
    @Environment(AppModel.self) private var app
    @FocusState private var focused: Bool

    var body: some View {
        let names: [String] = kind == .horse ? app.stable.horseNames : app.stable.riderNames
        let sugg: [String] = app.stable.suggestions(kind, text)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: kind == .horse ? "hare" : "person").font(.caption).foregroundStyle(Avo.silver)
                Text(kind == .horse ? "CABALLO" : "JINETE").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim)
            }
            HStack(spacing: 6) {
                TextField(kind == .horse ? "Nombre o código del caballo" : "Nombre o código del jinete", text: $text)
                    .focused($focused)
                    .autocorrectionDisabled()
                    .onChange(of: text) { _, v in if v.count > 120 { text = String(v.prefix(120)) } }
                    .accessibilityIdentifier(kind == .horse ? "assign.horse" : "assign.rider")
                if !text.isEmpty {
                    Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Avo.textDim) }
                        .buttonStyle(.plain)
                }
                Menu {
                    if names.isEmpty {
                        Text(kind == .horse ? "La Cuadra está vacía" : "No hay jinetes")
                    }
                    ForEach(names, id: \.self) { n in
                        Button(n) { text = n }
                    }
                } label: {
                    Image(systemName: "chevron.down.circle").foregroundStyle(Avo.silver)
                }
                .accessibilityLabel(kind == .horse ? "Elegir de la Cuadra" : "Elegir de Jinetes")
            }
            .padding(8)
            .background(Avo.surface2, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(focused ? Avo.red.opacity(0.7) : Avo.line, lineWidth: 1))

            if focused && !sugg.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sugg, id: \.self) { n in
                        Button {
                            text = n
                            focused = false
                        } label: {
                            Text(n).font(.footnote).foregroundStyle(Avo.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Avo.surface, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Avo.line, lineWidth: 1))
            }
            Text(kind == .horse ? "Si no existe, se crea en la Cuadra." : "Si no existe, se crea en Jinetes.")
                .font(.caption2).foregroundStyle(Avo.textDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
