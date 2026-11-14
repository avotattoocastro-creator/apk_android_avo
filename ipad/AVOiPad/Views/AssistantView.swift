import SwiftUI

/// «Asistente IA»: conversación con Claude (o con el modelo de Apple del iPad) sobre el entrenamiento activo.
struct AssistantView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let a: AssistantModel = app.assistant
        VStack(alignment: .leading, spacing: 10) {
            toolbar(a)
            if !a.hasKey && !a.onDeviceAvailable {
                setupCard(a)
                Spacer(minLength: 0)
            } else {
                conversation(a)
                inputBar(a)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Avo.bg)
        .sheet(isPresented: Binding(get: { a.showSettings }, set: { a.showSettings = $0 })) {
            AssistantSettingsView().environment(app)
        }
    }

    // ---------------------------------------------------------------- top bar
    private func toolbar(_ a: AssistantModel) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").foregroundStyle(Avo.red)
            Text("Asistente IA").font(.headline).foregroundStyle(Avo.text)
            AvoPill(text: a.engineLabel, color: a.usesClaude ? Avo.cyan : (a.onDeviceAvailable ? Avo.ok : Avo.unknown))
            if a.usesClaude {
                Text("Este mes ~\(AssistantModel.usd(a.monthSpentUSD)) de \(AssistantModel.usd(a.monthLimitUSD))")
                    .font(.caption).foregroundStyle(a.limitReached ? Avo.bad : Avo.textDim)
            }
            Spacer(minLength: 0)
            if !a.turns.isEmpty {
                Button { a.clear() } label: { Label("Nueva conversación", systemImage: "square.and.pencil") }
                    .buttonStyle(.avoSecondary)
            }
            Button { a.showSettings = true } label: { Label("Ajustes", systemImage: "gearshape") }
                .buttonStyle(.avoSecondary)
                .accessibilityIdentifier("assistant.settings")
        }
    }

    // ---------------------------------------------------------------- setup
    private func setupCard(_ a: AssistantModel) -> some View {
        AvoCard(title: "Configurar el asistente", subtitle: "Claude analiza tus entrenamientos con los créditos de API de tu plan") {
            VStack(alignment: .leading, spacing: 8) {
                step(1, "En platform.claude.com › Claves de API, crea una clave (por ejemplo «avo-ipad»).")
                step(2, "Copia la clave y pégala en Ajustes del asistente. Se guarda cifrada en el Llavero de este iPad.")
                step(3, "Abre un entrenamiento y pregunta. Cada pregunta gasta unos céntimos de los créditos del mes.")
                if !OnDeviceAssistant.unavailableReason.isEmpty {
                    Text("Modelo de Apple sin conexión: " + OnDeviceAssistant.unavailableReason)
                        .font(.caption).foregroundStyle(Avo.textDim)
                }
                Button { a.showSettings = true } label: { Label("Abrir ajustes del asistente", systemImage: "key") }
                    .buttonStyle(.avoPrimary)
                    .padding(.top, 4)
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n)").font(.caption.weight(.bold)).foregroundStyle(.white)
                .frame(width: 20, height: 20).background(Avo.red, in: Circle())
            Text(text).font(.callout).foregroundStyle(Avo.text).fixedSize(horizontal: false, vertical: true)
        }
    }

    // ---------------------------------------------------------------- conversation
    private func conversation(_ a: AssistantModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if a.turns.isEmpty { emptyState(a) }
                    ForEach(a.turns) { (t: AssistantTurn) in
                        AssistantBubble(turn: t, streaming: a.busy && t.id == a.turns.last?.id,
                                        save: { a.saveReport(t.id) })
                            .id(t.id)
                    }
                    if !a.status.isEmpty {
                        HStack(spacing: 8) {
                            if a.busy { ProgressView().controlSize(.small) }
                            Text(a.status).font(.caption).foregroundStyle(Avo.textDim)
                        }
                        .id("status")
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: a.turns.last?.text.count ?? 0) { (_: Int, _: Int) in
                if let id = a.turns.last?.id { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func emptyState(_ a: AssistantModel) -> some View {
        AvoCard(title: "Pregunta sobre este entrenamiento",
                subtitle: a.usesClaude
                    ? "Claude recibe el análisis del motor, Trabajo en pista y la historia del caballo"
                    : "El modelo de Apple recibe el resumen de la sesión (análisis básico, sin conexión)") {
            if app.selected == nil {
                Text("Abre un entrenamiento para empezar.").font(.callout).foregroundStyle(Avo.textDim)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(AssistantModel.quickPrompts) { (q: AssistantQuickPrompt) in
                        Button { a.send(q.prompt) } label: {
                            Label(q.title, systemImage: q.icon).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.avoSecondary)
                        .disabled(a.busy)
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- input
    private func inputBar(_ a: AssistantModel) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Pregunta sobre el entrenamiento…", text: Binding(get: { a.input }, set: { a.input = $0 }), axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .foregroundStyle(Avo.text)
                .background(Avo.surface2, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Avo.line, lineWidth: 1))
                .onSubmit { a.send() }
                .disabled(app.selected == nil)
                .accessibilityIdentifier("assistant.input")
            if a.busy {
                Button { a.stop() } label: { Label("Detener", systemImage: "stop.fill") }
                    .buttonStyle(.avoSecondary)
            } else {
                Button { a.send() } label: { Label("Enviar", systemImage: "arrow.up") }
                    .buttonStyle(.avoPrimary)
                    .disabled(!a.canSend)
                    .opacity(a.canSend ? 1 : 0.5)
            }
        }
    }
}

/// Burbuja de un turno. El texto de Claude viene en Markdown: se interpreta el formato en línea (negritas, cursivas,
/// código) y se respetan los saltos de línea, las listas y los títulos tal cual.
private struct AssistantBubble: View {
    var turn: AssistantTurn
    var streaming: Bool
    var save: () -> Void

    var body: some View {
        let user: Bool = turn.role == .user
        HStack(alignment: .top) {
            if user { Spacer(minLength: 80) }
            VStack(alignment: .leading, spacing: 6) {
                if turn.text.isEmpty && streaming {
                    ProgressView().controlSize(.small)
                } else {
                    Text(rendered)
                        .font(.callout)
                        .foregroundStyle(turn.isError ? Avo.bad : Avo.text)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !turn.footer.isEmpty {
                    Text(turn.footer).font(.caption2).foregroundStyle(Avo.textDim)
                }
                if !user && !streaming && !turn.isError && !turn.text.isEmpty {
                    Button(action: save) {
                        Label(turn.savedId == nil ? "Guardar informe PDF" : "Ver informe PDF (guardado en la ficha)",
                              systemImage: turn.savedId == nil ? "square.and.arrow.down" : "doc.richtext")
                    }
                    .buttonStyle(.avoSecondary)
                    .padding(.top, 2)
                    .accessibilityIdentifier("assistant.saveReport")
                }
            }
            .padding(12)
            .background(user ? Avo.redSoft : Avo.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(user ? Avo.red.opacity(0.4) : Avo.line, lineWidth: 1))
            if !user { Spacer(minLength: 40) }
        }
    }

    private var rendered: AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: turn.text, options: opts)) ?? AttributedString(turn.text)
    }
}

/// Ajustes del asistente: clave de API (Llavero), modelo, modelo de Apple, límite de gasto del mes.
struct AssistantSettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var keyText: String = ""
    @State private var message: String = ""
    @State private var messageOk: Bool = true
    @State private var testing: Bool = false

    var body: some View {
        let a: AssistantModel = app.assistant
        NavigationStack {
            Form {
                Section {
                    if a.hasKey {
                        Label("Clave guardada en el Llavero de este iPad", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Avo.ok)
                    }
                    SecureField(a.hasKey ? "Pegar una clave nueva (sk-ant-…)" : "Pegar la clave (sk-ant-…)", text: $keyText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("assistant.key")
                    // Cada botón en su propia fila y con estilo «borderless»: en un Form, varios botones en la MISMA fila
                    // se disparan todos con un solo toque (en la compilación 33, «Probar conexión» también borraba la clave).
                    Button("Guardar clave") {
                        if let e = a.saveKey(keyText) { show(e, ok: false) } else { keyText = ""; show("Clave guardada.", ok: true) }
                    }
                    .buttonStyle(.borderless)
                    .disabled(keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if a.hasKey {
                        Button(testing ? "Probando…" : "Probar conexión") {
                            testing = true
                            Task { @MainActor in
                                let r = await a.testConnection()
                                testing = false
                                show(r.text, ok: r.ok)
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(testing)
                    }
                    if !message.isEmpty {
                        Text(message).font(.caption).foregroundStyle(messageOk ? Avo.ok : Avo.bad)
                    }
                    if a.hasKey {
                        Button("Borrar clave del iPad", role: .destructive) { a.removeKey(); show("Clave borrada del iPad.", ok: true) }
                            .buttonStyle(.borderless)
                    }
                } header: {
                    Text("Clave de API de Claude")
                } footer: {
                    Text("Créala en platform.claude.com › Claves de API. Solo se guarda en este iPad (Llavero, no se copia a iCloud) y nunca en el repositorio. Puedes revocarla en Console cuando quieras.")
                }

                Section {
                    Picker("Modelo", selection: Binding(get: { a.model }, set: { a.model = $0 })) {
                        ForEach(ClaudeModel.allCases) { (m: ClaudeModel) in Text(m.title).tag(m) }
                    }
                    Text(a.model.detail).font(.caption).foregroundStyle(.secondary)
                    Toggle("Usar el modelo de Apple del iPad (sin conexión, gratis)", isOn: Binding(get: { a.useOnDevice }, set: { a.useOnDevice = $0 }))
                        .disabled(!a.onDeviceAvailable)
                    if !a.onDeviceAvailable {
                        Text(OnDeviceAssistant.unavailableReason).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Modelo")
                } footer: {
                    Text("Sonnet 5.5 es el recomendado. Haiku 5.5 cuesta unas 20 veces menos y responde antes, con un análisis más sencillo. El modelo de Apple solo ve el resumen de la sesión.")
                }

                Section {
                    Stepper(value: Binding(get: { a.monthLimitUSD }, set: { a.monthLimitUSD = $0 }), in: 5...100, step: 5) {
                        Text("Límite del mes: \(AssistantModel.usd(a.monthLimitUSD))")
                    }
                    HStack {
                        Text("Gastado este mes (estimado)")
                        Spacer()
                        Text(AssistantModel.usd(a.monthSpentUSD)).foregroundStyle(a.limitReached ? Avo.bad : .secondary)
                    }
                    Button("Poner a cero el contador del mes") { a.resetMonthSpend() }
                } header: {
                    Text("Gasto")
                } footer: {
                    Text("Estimación hecha en el iPad con los precios de lista. El gasto real está en Claude Console › Gasto. Sin método de pago en Console, nunca se cobra más que los 100 $ de créditos mensuales del plan Max.")
                }
            }
            .navigationTitle("Asistente IA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } }
            }
        }
    }

    private func show(_ text: String, ok: Bool) {
        message = text
        messageOk = ok
    }
}
