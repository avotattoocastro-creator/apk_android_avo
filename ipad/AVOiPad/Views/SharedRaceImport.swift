import SwiftUI
import UniformTypeIdentifiers

/// «Añadir carrera»: PDF picker + sheet to confirm the horse of the Cuadra and its name in the race. Attached to the
/// «Carreras» page and to the Cuadra page (horse card), see RacesModel.startImport(horseCode:).
struct RaceImportModifier: ViewModifier {
    @Bindable var model: RacesModel
    let onError: (Error) -> Void

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $model.showImporter, allowedContentTypes: [UTType.pdf], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let u = urls.first { Task { @MainActor in await model.importPDF(u) } }
                case .failure(let error):
                    onError(error)
                }
            }
            .sheet(isPresented: Binding(get: { model.pending != nil }, set: { if !$0 { model.cancelPending() } })) {
                RaceConfirmSheet(model: model)
                    .avoColorScheme()
            }
    }
}

extension View {
    func raceImport(_ model: RacesModel, onError: @escaping (Error) -> Void) -> some View {
        modifier(RaceImportModifier(model: model, onError: onError))
    }
}

/// Sheet «Confirmar carrera»: which horse of the Cuadra ran, and which runner of the PDF it is.
struct RaceConfirmSheet: View {
    @Bindable var model: RacesModel

    var body: some View {
        NavigationStack {
            Form {
                if let p = model.pending {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.race.title).font(.headline).foregroundStyle(Avo.text)
                            Text("\(p.race.hippodrome) · \(p.race.category) · \(p.race.distanceText) · \(p.race.dateText) · \(p.race.runners.count) participantes")
                                .font(.footnote).foregroundStyle(Avo.textDim)
                        }
                        Text(p.message).font(.footnote).foregroundStyle(Avo.cyan).fixedSize(horizontal: false, vertical: true)
                    }
                    Section("Caballo de la Cuadra") {
                        if p.horseFixed {
                            Text(model.horseName(p.horseCode)).foregroundStyle(Avo.text)
                        } else if model.horses.isEmpty {
                            Text("No hay caballos en la Cuadra: crea la ficha del caballo y vuelve a añadir la carrera.")
                                .font(.footnote).foregroundStyle(Avo.warn)
                        } else {
                            Picker("Caballo", selection: horseBinding) {
                                Text("Elegir…").tag("")
                                ForEach(model.horses, id: \.code) { (h: IdentityRecord) in
                                    Text(h.demo ? "\(h.name) · DEMO" : h.name).tag(h.code)
                                }
                            }
                        }
                    }
                    Section("Nombre en la carrera") {
                        Picker("Participante", selection: runnerBinding) {
                            Text("Elegir…").tag("")
                            ForEach(p.race.runners) { (r: RaceRunner) in
                                Text("\(r.finish.map { "\($0).º" } ?? "—") · \(r.name)\(r.number.map { " (n.º \($0))" } ?? "")").tag(r.name)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }
            }
            .navigationTitle("Añadir carrera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { model.cancelPending() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { model.confirmPending() }
                        .disabled((model.pending?.horseCode ?? "").isEmpty || (model.pending?.runnerName ?? "").isEmpty)
                }
            }
        }
    }

    private var horseBinding: Binding<String> {
        Binding<String>(get: { model.pending?.horseCode ?? "" }, set: { (v: String) in
            guard var p = model.pending else { return }
            p.horseCode = v.isEmpty ? nil : v
            if let s = model.suggestedRunner(p.race, horseCode: p.horseCode) { p.runnerName = s }
            model.pending = p
        })
    }

    private var runnerBinding: Binding<String> {
        Binding<String>(get: { model.pending?.runnerName ?? "" }, set: { (v: String) in
            model.pending?.runnerName = v.isEmpty ? nil : v
        })
    }
}
