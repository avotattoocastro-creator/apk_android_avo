import SwiftUI

/// «Valoración del entrenador» of the selected session (Análisis): RPE 1–10, estado BIEN/CANSADO/RARO/COJERA, nota,
/// pista (superficie, estado) and the «Ficha de campo» (Training Analytics 1.1.0: tipo de sesión, franja de playa, marea,
/// going, temperatura, humedad, pesos e incidencia; docs/PROTOCOLO_PRUEBAS_CAMPO_PROTOTIPO.md). Stored in
/// paths.root/valoraciones.json by session id; regenerates the training summary.
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
    @State private var fichaOpen: Bool = false
    @State private var tipoSesion: String = ""
    @State private var franja: String = ""
    @State private var going: String = ""
    @State private var mareaHora: String = ""
    @State private var mareaTipo: String = ""
    @State private var temperatura: String = ""
    @State private var humedad: String = ""
    @State private var pesoJinete: String = ""
    @State private var pesoCaballo: String = ""
    @State private var incidenciaTipo: String = ""
    @State private var incidenciaTexto: String = ""
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

                    DisclosureGroup(isExpanded: $fichaOpen) {
                        fieldSheet
                    } label: {
                        label("FICHA DE CAMPO (tipo, playa, marea, going, tiempo, pesos, incidencia)")
                    }
                    .tint(Avo.textDim)
                    .accessibilityIdentifier("rating.fieldSheet")

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
                            clearSheet()
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

    // ------------------------------------------------------------------ ficha de campo
    private var fieldSheet: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                codePicker("TIPO DE SESIÓN", TrainingFieldSheet.sessionTypes, $tipoSesion)
                codePicker("FRANJA DE PLAYA", TrainingFieldSheet.beachBands, $franja)
                codePicker("GOING / TERRENO", TrainingFieldSheet.goings, $going)
            }
            HStack(alignment: .top, spacing: 12) {
                numberField("MAREA · HORA (HH:MM)", "07:42", $mareaHora, keyboard: .numbersAndPunctuation)
                codePicker("MAREA · TIPO", TrainingFieldSheet.tideTypes, $mareaTipo)
                numberField("TEMPERATURA (°C)", "14,5", $temperatura)
                numberField("HUMEDAD (%)", "80", $humedad)
            }
            HStack(alignment: .top, spacing: 12) {
                numberField("PESO JINETE CON EQUIPO (kg)", "56", $pesoJinete)
                numberField("PESO CABALLO EN AYUNAS (kg)", "480", $pesoCaballo)
                codePicker("INCIDENCIA", TrainingFieldSheet.incidentTypes, $incidenciaTipo)
            }
            TextField("Incidencia: qué pasó y en qué tramo", text: $incidenciaTexto, axis: .vertical)
                .lineLimit(1...3)
                .padding(8)
                .background(Avo.surface2, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Avo.line, lineWidth: 1))
            Text("CARRERA y TRIAL cuentan como carrera para la regla A4. La franja separa las líneas base de la playa (A7/A8). Incidencia COJERA → REVISAR; CAÍDA → VIGILAR.")
                .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }

    private func codePicker(_ title: String, _ codes: [String], _ value: Binding<String>) -> some View {
        var list: [String] = codes
        if !value.wrappedValue.isEmpty && !list.contains(value.wrappedValue) { list.append(value.wrappedValue) }
        return VStack(alignment: .leading, spacing: 4) {
            label(title)
            Picker(title, selection: value) {
                Text("—").tag("")
                ForEach(list, id: \.self) { (v: String) in Text(TrainingFieldSheet.label(v)).tag(v) }
            }
            .pickerStyle(.menu)
        }
    }

    private func numberField(_ title: String, _ hint: String, _ value: Binding<String>,
                             keyboard: UIKeyboardType = .decimalPad) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            label(title)
            TextField(hint, text: value)
                .keyboardType(keyboard)
                .frame(maxWidth: 150)
                .padding(6)
                .background(Avo.surface2, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Avo.line, lineWidth: 1))
        }
    }

    private static func parseNumber(_ t: String) -> Double? {
        let s: String = t.trimmed.replacingOccurrences(of: ",", with: ".")
        guard !s.isEmpty, let d = Double(s), d.isFinite else { return nil }
        return d
    }

    private static func numberText(_ d: Double?) -> String {
        guard let v = d, v.isFinite else { return "" }
        if v == v.rounded() { return String(Int(v)) }
        return String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
    }

    private func clearSheet() {
        tipoSesion = ""; franja = ""; going = ""; mareaHora = ""; mareaTipo = ""; temperatura = ""; humedad = ""
        pesoJinete = ""; pesoCaballo = ""; incidenciaTipo = ""; incidenciaTexto = ""
    }

    private func loadSheet(_ f: TrainingFieldSheet?) {
        tipoSesion = f?.tipo_sesion ?? ""
        franja = f?.franja ?? ""
        going = f?.going ?? ""
        mareaHora = f?.marea_hora ?? ""
        mareaTipo = f?.marea_tipo ?? ""
        temperatura = TrainingRatingCard.numberText(f?.temperatura_c)
        humedad = TrainingRatingCard.numberText(f?.humedad_pct)
        pesoJinete = TrainingRatingCard.numberText(f?.peso_jinete_kg)
        pesoCaballo = TrainingRatingCard.numberText(f?.peso_caballo_kg)
        incidenciaTipo = f?.incidencia_tipo ?? ""
        incidenciaTexto = f?.incidencia_texto ?? ""
        fichaOpen = !(f?.isEmpty ?? true)
    }

    private var fieldSheetValue: TrainingFieldSheet {
        func opt(_ s: String) -> String? { s.trimmed.isEmpty ? nil : s.trimmed }
        return TrainingFieldSheet(tipo_sesion: opt(tipoSesion), franja: opt(franja), going: opt(going), marea_hora: opt(mareaHora),
                                  marea_tipo: opt(mareaTipo), temperatura_c: TrainingRatingCard.parseNumber(temperatura),
                                  humedad_pct: TrainingRatingCard.parseNumber(humedad),
                                  peso_jinete_kg: TrainingRatingCard.parseNumber(pesoJinete),
                                  peso_caballo_kg: TrainingRatingCard.parseNumber(pesoCaballo),
                                  incidencia_tipo: opt(incidenciaTipo), incidencia_texto: opt(incidenciaTexto))
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
        loadSheet(r?.ficha)
        message = r?.actualizado_utc.map { "Guardada " + AvoTime.text(AvoTime.parseIso($0)) } ?? ""
    }

    private func save(_ s: SessionItem) {
        let track = TrainingTrack(superficie: superficie.isEmpty ? nil : superficie, estado: pistaEstado.isEmpty ? nil : pistaEstado)
        let f: TrainingFieldSheet = fieldSheetValue
        let r = TrainingRating(rpe: rpe >= 1 ? rpe : nil, estado: estado.isEmpty ? nil : estado,
                               nota: nota.trimmed.isEmpty ? nil : nota.trimmed, pista: track.isEmpty ? nil : track,
                               ficha: f.isEmpty ? nil : f)
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
