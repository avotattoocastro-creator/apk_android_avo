import SwiftUI
import UniformTypeIdentifiers

/// «PPK» (Motor): posición poscalculada de la espalda con la base del IGN (docs/PPK.md).
/// Elige la estación ERGNSS (se recuerda), calcula, y muestra el resultado. El resultado se sube a la nube junto al
/// entrenamiento para que el Android y Windows no tengan que repetirlo.
struct PpkSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let item: SessionItem

    @State private var station: String = PpkConfig.station
    @State private var stations: [String] = []
    @State private var busy: String = ""
    @State private var message: String = ""
    @State private var summary: PpkSummary? = nil
    @State private var need: PpkNeed? = nil
    @State private var importing: Bool = false
    @State private var task: Task<Void, Never>? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Entrenamiento") {
                    if let n = need {
                        Text("\(n.rawx) épocas RAWX · \(hoursText(n))")
                    } else if busy.isEmpty {
                        Text(message.isEmpty ? "Comprobando si tiene datos RAWX…" : message).foregroundStyle(.secondary)
                    }
                }
                if let s = summary {
                    Section("Resultado") {
                        LabeledContent("FIX", value: String(format: "%.0f %%", s.pctFix))
                        LabeledContent("Épocas", value: "\(s.epochs) (FIX \(s.fix), FLOAT \(s.float))")
                        LabeledContent("Base", value: s.base.isEmpty ? "—" : s.base)
                        LabeledContent("Distancia a la base", value: String(format: "%.1f km", s.baselineKm))
                        ForEach(s.warnings, id: \.self) { w in Text(w).font(.footnote).foregroundStyle(.secondary) }
                    }
                }
                Section {
                    HStack {
                        TextField("Código (4 letras)", text: $station)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        if !stations.isEmpty {
                            Menu("Lista del IGN") {
                                ForEach(stations, id: \.self) { s in Button(s) { station = s } }
                            }
                        }
                    }
                    Button("Ver estaciones disponibles a esa hora") { loadStations() }
                        .disabled(need == nil || !busy.isEmpty)
                } header: {
                    Text("Estación base ERGNSS del IGN")
                } footer: {
                    Text("Elige la más cercana a la pista (mejor a menos de 20–30 km). Se recuerda para los próximos entrenamientos. El IGN publica cada hora al terminarla.")
                }
                Section {
                    Button(summary == nil ? "Calcular PPK" : "Recalcular PPK") { run(manual: []) }
                        .disabled(need == nil || !busy.isEmpty || station.trimmingCharacters(in: .whitespaces).count != 4)
                    Button("Importar la base a mano (RINEX de Archivos)") { importing = true }
                        .disabled(need == nil || !busy.isEmpty)
                    if !busy.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(busy).font(.footnote).foregroundStyle(.secondary)
                        }
                        Button("Cancelar", role: .cancel) { task?.cancel() }
                    } else if !message.isEmpty && need != nil {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("PPK · \(item.session.horse)")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { dismiss() } } }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType.data], allowsMultipleSelection: true) { (res: Result<[URL], Error>) in
            guard case .success(let urls) = res, !urls.isEmpty else { return }
            var copies: [String] = []
            let dir: String = AvoFiles.join(app.ppkStore.baseDir, "importados")
            AvoFiles.ensureDir(dir)
            for u in urls {
                let access: Bool = u.startAccessingSecurityScopedResource()
                defer { if access { u.stopAccessingSecurityScopedResource() } }
                let target: String = AvoFiles.join(dir, u.lastPathComponent)
                try? FileManager.default.removeItem(atPath: target)
                if (try? FileManager.default.copyItem(atPath: u.path, toPath: target)) != nil { copies.append(target) }
            }
            if !copies.isEmpty { run(manual: copies) }
        }
        .task { await load() }
        .onDisappear { task?.cancel() }
    }

    private func hoursText(_ n: PpkNeed) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "dd/MM HH:mm"
        guard let s = n.start, let e = n.end else { return "" }
        return f.string(from: s) + "–" + String(f.string(from: e).suffix(5)) + " UTC"
    }

    @MainActor
    private func load() async {
        summary = app.ppkSummary(item)
        do {
            need = try await app.ppkNeed(item)
            if summary == nil {
                // ¿ya lo calculó otra app? (nube); no descarga la base todavía
                if let s = try? await app.runPpk(item, station: "", progress: { busy = $0 }) { summary = s }
                busy = ""
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func loadStations() {
        guard let h = need?.hours.first else { return }
        busy = "Leyendo la lista del IGN…"
        Task { @MainActor in
            do {
                stations = try await IgnBase.stations(h)
                message = stations.isEmpty ? "El IGN aún no tiene datos de esa hora." : "\(stations.count) estaciones con datos a esa hora."
            } catch {
                message = error.localizedDescription
            }
            busy = ""
        }
    }

    private func run(manual: [String]) {
        let sta: String = station.trimmingCharacters(in: .whitespaces).uppercased()
        if manual.isEmpty { PpkConfig.station = sta }
        message = ""
        task = Task { @MainActor in
            do {
                summary = try await app.runPpk(item, station: sta, manualBase: manual, recalc: summary != nil || !manual.isEmpty,
                                               progress: { busy = $0 })
                message = "PPK listo. Guardado en el iPad y, si el entrenamiento está en tu nube, también allí."
            } catch is CancellationError {
                message = "Cancelado"
            } catch {
                message = error.localizedDescription
            }
            busy = ""
        }
    }
}
