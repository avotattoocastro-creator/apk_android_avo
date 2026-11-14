import SwiftUI

/// «Valoración del entrenador» of the selected session (Análisis): RPE 1–10, estado BIEN/CANSADO/RARO/COJERA, nota and
/// pista (superficie, estado). Stored in paths.root/valoraciones.json by session id; regenerates the training summary.
struct TrainingRatingCard: View {
    @Environment(AppModel.self) private var app
    /// Stretch to the height of the row (Resumen: same height as the engine card, sketch 14/11/2026).
    var fill: Bool = false
    @State private var loadedId: String = ""
    @State private var rpe: Int = 0
    @State private var estado: String = ""
    @State private var nota: String = ""
    @State private var superficie: String = ""
    @State private var pistaEstado: String = ""
    @State private var message: String = ""
    @State private var saving: Bool = false

    var body: some View {
        let s: SessionItem? = app.selected
        AvoCard(title: "Valoración del entrenador",
                subtitle: "Se guarda en este iPad y entra en la historia del caballo (carga sRPE y estado)", fill: fill) {
            if let s = s {
                VStack(alignment: .leading, spacing: 10) {
                    label("ESFUERZO PERCIBIDO (RPE 1–10)")
                    Picker("RPE", selection: $rpe) {
                        Text("—").tag(0)
                        ForEach(1...10, id: \.self) { (v: Int) in Text(String(v)).tag(v) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("rating.rpe")

                    label("ESTADO DEL CABALLO")
                    Picker("Estado", selection: $estado) {
                        Text("—").tag("")
                        ForEach(TrainingRating.states, id: \.self) { (v: String) in Text(v).tag(v) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("rating.state")

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            label("PISTA · SUPERFICIE")
                            Picker("Superficie", selection: $superficie) {
                                Text("—").tag("")
                                ForEach(surfaceOptions, id: \.self) { (v: String) in Text(v).tag(v) }
                            }
                            .pickerStyle(.menu)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            label("PISTA · ESTADO")
                            Picker("Estado de la pista", selection: $pistaEstado) {
                                Text("—").tag("")
                                ForEach(trackOptions, id: \.self) { (v: String) in Text(v).tag(v) }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    label("NOTA")
                    TextField("Observaciones del entrenador", text: $nota, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(8)
                        .background(Avo.surface2, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Avo.line, lineWidth: 1))

                    HStack(spacing: 8) {
                        Button("Guardar valoración") { save(s) }
                            .buttonStyle(.avoPrimary)
                            .disabled(saving)
                            .accessibilityIdentifier("rating.save")
                        Button("Borrar") {
                            rpe = 0; estado = ""; nota = ""; superficie = ""; pistaEstado = ""
                            save(s)
                        }
                        .buttonStyle(.avoSecondary)
                        .disabled(saving)
                        if saving { ProgressView().controlSize(.small) }
                        Spacer(minLength: 0)
                    }
                    if !message.isEmpty {
                        Text(message).font(.caption).foregroundStyle(Avo.cyan).fixedSize(horizontal: false, vertical: true)
                    }
                    Text("COJERA → REVISAR; CANSADO o RARO → VIGILAR en la historia. Orientativo, no es un diagnóstico veterinario.")
                        .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                }
                .onAppear { load(s) }
                .onChange(of: s.id) { (_: String, _: String) in load(s) }
            } else {
                AvoNoData(text: "Sin entrenamiento seleccionado")
            }
        }
    }

    /// Known options plus a stored value that is not in the list (never lose what was saved).
    private var surfaceOptions: [String] {
        var l: [String] = TrainingRating.surfaces
        if !superficie.isEmpty && !l.contains(superficie) { l.append(superficie) }
        return l
    }
    private var trackOptions: [String] {
        var l: [String] = TrainingRating.trackStates
        if !pistaEstado.isEmpty && !l.contains(pistaEstado) { l.append(pistaEstado) }
        return l
    }

    private func label(_ t: String) -> some View {
        Text(t).font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim)
    }

    private func load(_ s: SessionItem) {
        loadedId = s.id
        let r: TrainingRating? = app.rating(for: s.id)
        rpe = r?.rpe.map { min(max($0, 0), 10) } ?? 0
        estado = r?.estado ?? ""
        nota = r?.nota ?? ""
        superficie = r?.pista?.superficie ?? ""
        pistaEstado = r?.pista?.estado ?? ""
        message = r?.actualizado_utc.map { "Guardada " + AvoTime.text(AvoTime.parseIso($0)) } ?? ""
    }

    private func save(_ s: SessionItem) {
        let track = TrainingTrack(superficie: superficie.isEmpty ? nil : superficie, estado: pistaEstado.isEmpty ? nil : pistaEstado)
        let r = TrainingRating(rpe: rpe >= 1 ? rpe : nil, estado: estado.isEmpty ? nil : estado,
                               nota: nota.trimmed.isEmpty ? nil : nota.trimmed, pista: track.isEmpty ? nil : track)
        saving = true
        Task { @MainActor in
            let err: String? = await app.saveRating(s, r.isEmpty ? nil : r)
            saving = false
            if let e = err {
                message = "No se pudo guardar: " + e
            } else {
                message = r.isEmpty ? "Valoración borrada." : "Valoración guardada."
                app.status = "Valoración del entrenador guardada · \(s.horse) \(s.dateTimeText)"
            }
        }
    }
}
