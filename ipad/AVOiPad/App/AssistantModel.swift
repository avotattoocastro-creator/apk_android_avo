import SwiftUI
import Observation

/// Turno de la conversación del Asistente IA.
struct AssistantTurn: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    var role: Role
    var text: String
    var isError: Bool = false
    /// «Claude Sonnet 5.5 · 12 400 tokens · ~0,031 $» o «Apple (en el iPad)».
    var footer: String = ""
}

/// Pregunta rápida (botones encima del cuadro de texto).
struct AssistantQuickPrompt: Identifiable {
    var id: String { title }
    var title: String
    var icon: String
    var prompt: String
}

/// «Asistente IA»: Claude (API, con la clave del Llavero) o el modelo de Apple del iPad analizan el entrenamiento activo.
/// Claude recibe el resumen de la sesión, el análisis del motor compactado (incluido «trabajo_pista») y los resúmenes de
/// las sesiones anteriores del mismo caballo. El contexto va en un bloque de sistema con caché, así que las preguntas
/// siguientes de la misma conversación cuestan mucho menos. El gasto estimado del mes se lleva en el iPad y se corta al
/// llegar al límite (además de los 100 $ de créditos de Claude Console, que son el tope real).
@Observable
final class AssistantModel {
    @ObservationIgnored unowned let app: AppModel
    @ObservationIgnored private var sessionId: String = ""
    @ObservationIgnored private var contextText: String = ""
    @ObservationIgnored private var contextSessionId: String = ""
    @ObservationIgnored private var task: Task<Void, Never>? = nil
    @ObservationIgnored private let defaults: UserDefaults = .standard

    var turns: [AssistantTurn] = []
    var input: String = ""
    var busy: Bool = false
    var status: String = ""
    var hasKey: Bool = false
    var showSettings: Bool = false
    var monthSpentUSD: Double = 0
    /// Tamaño del contexto de la última pregunta a Claude (caracteres), para mostrarlo.
    var contextChars: Int = 0

    var model: ClaudeModel = .sonnet {
        didSet { defaults.set(model.rawValue, forKey: Keys.model) }
    }
    var useOnDevice: Bool = false {
        didSet { defaults.set(useOnDevice, forKey: Keys.onDevice) }
    }
    var monthLimitUSD: Double = 50 {
        didSet { defaults.set(monthLimitUSD, forKey: Keys.limit) }
    }

    private enum Keys {
        static let model = "assistant.model"
        static let onDevice = "assistant.onDevice"
        static let limit = "assistant.monthLimitUSD"
        static func spent(_ month: String) -> String { "assistant.spentUSD." + month }
    }

    /// Respuesta máxima de Claude (tokens). Incluye el pensamiento adaptativo de los modelos 5.5 (activo por defecto):
    /// con 4096 el modelo podía gastarlo todo pensando y no escribir nada («respuesta cortada por longitud»).
    static let maxOutputTokens: Int = 16_000
    /// Tope del contexto para Claude (~60 000 tokens; queda por debajo del umbral de 100 000 de Haiku 5.5).
    static let maxContextChars: Int = 180_000
    /// Sesiones anteriores del caballo que se añaden como historia.
    static let historySessions: Int = 15

    static let quickPrompts: [AssistantQuickPrompt] = [
        AssistantQuickPrompt(title: "Explica la sesión", icon: "text.magnifyingglass",
                             prompt: "Explícame este entrenamiento: estructura, trabajos rápidos, lo más destacado y lo que habría que vigilar."),
        AssistantQuickPrompt(title: "Fatiga y recuperación", icon: "heart.text.square",
                             prompt: "Analiza la fatiga y la recuperación: caída de velocidad y de zancada entre series, últimos 200/400 m y recuperación hasta el paso."),
        AssistantQuickPrompt(title: "Compara con su historia", icon: "chart.line.uptrend.xyaxis",
                             prompt: "Compara esta sesión con las anteriores del mismo caballo. ¿Qué ha mejorado, qué ha empeorado y qué tendencias ves?"),
        AssistantQuickPrompt(title: "Zancada y cincha", icon: "figure.equestrian.sports",
                             prompt: "Analiza la zancada (frecuencia y longitud frente a la velocidad), la mano de galope, los giros y la VeDBA de la cincha."),
        AssistantQuickPrompt(title: "Próximo entrenamiento", icon: "calendar.badge.clock",
                             prompt: "Con estos datos y la carga reciente, ¿qué tipo de trabajo propondrías para la próxima sesión? Justifícalo con los datos."),
    ]

    init(app: AppModel) {
        self.app = app
        if let m = defaults.string(forKey: Keys.model).flatMap({ ClaudeModel(rawValue: $0) }) { model = m }
        useOnDevice = defaults.bool(forKey: Keys.onDevice)
        let l: Double = defaults.double(forKey: Keys.limit)
        if l > 0 { monthLimitUSD = l }
        hasKey = AvoKeychain.read() != nil
        monthSpentUSD = defaults.double(forKey: Keys.spent(AssistantModel.monthKey()))
    }

    // ---------------------------------------------------------------- contract
    func sessionChanged() {
        let id: String = app.selected?.id ?? ""
        if id != sessionId {
            sessionId = id
            stop()
            turns = []
            status = ""
            contextText = ""
            contextSessionId = ""
        }
    }

    func pageShown() {
        sessionChanged()
        hasKey = AvoKeychain.read() != nil
        monthSpentUSD = defaults.double(forKey: Keys.spent(AssistantModel.monthKey()))
    }

    // ---------------------------------------------------------------- state
    var onDeviceAvailable: Bool { OnDeviceAssistant.available }

    /// Motor que se usará en la próxima pregunta.
    var usesClaude: Bool { !useOnDevice && hasKey }

    var engineLabel: String {
        if usesClaude { return "Claude " + model.title }
        if onDeviceAvailable { return "Apple (en el iPad)" }
        return "Sin configurar"
    }

    var canSend: Bool {
        !busy && app.selected != nil && (usesClaude || onDeviceAvailable)
            && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var limitReached: Bool { monthSpentUSD >= monthLimitUSD }

    static func monthKey(_ d: Date = Date()) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "Europe/Madrid") ?? .current, from: d)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    static func usd(_ v: Double) -> String {
        v < 0.01 && v > 0 ? "<0,01 $" : AvoFormat.f(v, 2) + " $"
    }

    // ---------------------------------------------------------------- key
    /// Guarda la clave en el Llavero. Devuelve un error legible o nil.
    func saveKey(_ raw: String) -> String? {
        let k: String = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ClaudeClient.looksLikeKey(k) { return "No parece una clave de API de Claude (empieza por sk-ant-)." }
        if !AvoKeychain.write(k) { return "No se pudo guardar la clave en el Llavero." }
        hasKey = AvoKeychain.read() == k
        if !hasKey { return "La clave no se pudo leer del Llavero después de guardarla." }
        useOnDevice = false   // con clave, el asistente pasa a usar Claude
        app.log.info("asistente", "Clave de API guardada en el Llavero")
        return nil
    }

    func removeKey() {
        AvoKeychain.delete()
        hasKey = false
        app.log.info("asistente", "Clave de API borrada del Llavero")
    }

    /// Prueba la clave con una petición mínima. Devuelve el texto para la interfaz.
    @MainActor
    func testConnection() async -> (ok: Bool, text: String) {
        guard let key = AvoKeychain.read() else { return (false, "No hay clave guardada.") }
        do {
            let r = try await ClaudeClient(apiKey: key).test(model: model)
            addSpend(r.usage.costUSD(model))
            return (true, "Conexión correcta con \(model.title): «\(r.text.trimmingCharacters(in: .whitespacesAndNewlines))»")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    func addSpend(_ usd: Double) {
        let k: String = Keys.spent(AssistantModel.monthKey())
        monthSpentUSD = defaults.double(forKey: k) + usd
        defaults.set(monthSpentUSD, forKey: k)
    }

    func resetMonthSpend() {
        defaults.set(0.0, forKey: Keys.spent(AssistantModel.monthKey()))
        monthSpentUSD = 0
    }

    // ---------------------------------------------------------------- conversation
    func clear() {
        stop()
        turns = []
        status = ""
    }

    func stop() {
        task?.cancel()
        task = nil
        if busy { busy = false; status = "Detenido" }
    }

    func send(_ preset: String? = nil) {
        let text: String = (preset ?? input).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy, let s = app.selected else { return }
        if usesClaude && limitReached {
            status = "Límite de gasto del mes alcanzado (\(AssistantModel.usd(monthLimitUSD))). Súbelo en Ajustes del asistente."
            return
        }
        if !usesClaude && !onDeviceAvailable {
            showSettings = true
            return
        }
        if preset == nil { input = "" }
        turns.append(AssistantTurn(role: .user, text: text))
        turns.append(AssistantTurn(role: .assistant, text: ""))
        busy = true
        task = Task { @MainActor [weak self] in
            guard let self = self else { return }
            if self.usesClaude {
                await self.askClaude(s)
            } else {
                await self.askOnDevice(s, question: text)
            }
            self.busy = false
            self.task = nil
        }
    }

    @MainActor
    private func askClaude(_ s: SessionItem) async {
        guard let key = AvoKeychain.read() else { fail("No hay clave de API guardada."); return }
        status = "Preparando los datos del entrenamiento…"
        let context: String = await buildContext(s)
        if Task.isCancelled { return }
        contextChars = context.count
        let m: ClaudeModel = model
        let system: [[String: Any]] = [
            ["type": "text", "text": AssistantModel.instructions],
            ["type": "text", "text": context, "cache_control": ["type": "ephemeral"]],
        ]
        // historial: todos los turnos menos el último (la respuesta vacía en curso) y sin los de error
        var messages: [[String: Any]] = []
        for t in turns.dropLast() where !t.isError && !t.text.isEmpty {
            messages.append(["role": t.role == .user ? "user" : "assistant", "content": t.text])
        }
        status = "Claude \(m.title) está analizando…"
        do {
            for try await ev in ClaudeClient(apiKey: key).stream(model: m, system: system, messages: messages,
                                                                  maxTokens: AssistantModel.maxOutputTokens) {
                if Task.isCancelled { break }
                switch ev {
                case .text(let t):
                    appendToLast(t)
                case .done(let stop, let usage):
                    let cost: Double = usage.costUSD(m)
                    addSpend(cost)
                    var footer: String = "Claude \(m.title) · \(usage.totalTokens.formatted()) tokens · ~\(AssistantModel.usd(cost))"
                    if usage.cacheRead > 0 { footer += " · contexto en caché" }
                    if stop == "max_tokens" { footer += " · respuesta cortada por longitud" }
                    if stop == "refusal" { footer += " · Claude no ha respondido a esta petición" }
                    setLastFooter(footer)
                    status = ""
                    app.log.info("asistente", "Respuesta de Claude", ["modelo": m.rawValue, "tokens": usage.totalTokens,
                                                                      "coste_usd": cost, "sesion": s.id])
                }
            }
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            fail(error.localizedDescription)
            app.log.warn("asistente", "Claude: " + error.localizedDescription, error)
        }
    }

    @MainActor
    private func askOnDevice(_ s: SessionItem, question: String) async {
        status = "El modelo de Apple está pensando…"
        var ctx: String = header(s)
        if await app.ensureTrainingSummary(s), let d = AvoFiles.read(app.trainingSummaryPath(s.id)) {
            ctx += "\nResumen de la sesión (JSON):\n" + AssistantJSON.compact(String(decoding: d, as: UTF8.self), dropKeys: [], maxArray: 8)
        }
        if ctx.count > OnDeviceAssistant.maxContextChars { ctx = String(ctx.prefix(OnDeviceAssistant.maxContextChars)) }
        let instructions: String = "Eres el asistente de AVO Performance Horse. Explicas en español, de forma breve y clara, "
            + "los datos de un entrenamiento de un caballo de carreras. Usa solo los datos que se te dan; si algo no está, dilo. "
            + "No hagas diagnósticos veterinarios.\n\nDatos:\n" + ctx
        do {
            let r: String = try await OnDeviceAssistant.respond(instructions: instructions, prompt: question)
            if Task.isCancelled { return }
            appendToLast(r)
            setLastFooter("Apple (en el iPad) · sin coste · análisis básico")
            status = ""
        } catch {
            if Task.isCancelled { return }
            fail(error.localizedDescription)
        }
    }

    private func appendToLast(_ t: String) {
        guard let i = turns.indices.last else { return }
        turns[i].text += t
    }

    private func setLastFooter(_ f: String) {
        guard let i = turns.indices.last else { return }
        turns[i].footer = f
    }

    private func fail(_ message: String) {
        if let i = turns.indices.last, turns[i].role == .assistant, turns[i].text.isEmpty {
            turns[i].text = message
            turns[i].isError = true
        } else {
            turns.append(AssistantTurn(role: .assistant, text: message, isError: true))
        }
        status = ""
    }

    // ---------------------------------------------------------------- context
    private func header(_ s: SessionItem) -> String {
        let key: String = app.horseKey(s)
        let breed: String = app.stable.store.find(.horse, key)?.breed ?? ""
        var h: String = "Caballo: \(s.horse)"
        if !breed.isEmpty { h += " · raza: \(breed)" }
        h += "\nJinete: \(s.rider)\nFecha (hora de Madrid): \(s.dateTimeText)\n\(s.windowText)\nMotor: \(s.engineState)"
        if s.isSynthetic { h += "\nATENCIÓN: sesión de DEMOSTRACIÓN (datos sintéticos)." }
        return h + "\n"
    }

    /// Contexto de la sesión para Claude (se reutiliza mientras no cambie la sesión ni su análisis).
    @MainActor
    private func buildContext(_ s: SessionItem) async -> String {
        let engineJson: String = s.engine?.rawJson ?? ""
        let signature: String = s.id + "#" + String(engineJson.count)
        if contextSessionId == signature && !contextText.isEmpty { return contextText }

        var parts: [String] = ["# Entrenamiento activo\n" + header(s)]
        if await app.ensureTrainingSummary(s), let d = AvoFiles.read(app.trainingSummaryPath(s.id)) {
            parts.append("# Resumen de la sesión (avo-training-session, AVO Training Analytics)\n"
                         + AssistantJSON.compact(String(decoding: d, as: UTF8.self), dropKeys: []))
        }
        let analysis: String = engineJson
        if !analysis.isEmpty {
            let compact: String = await Task.detached(priority: .userInitiated) { () -> String in
                AssistantJSON.compact(analysis)
            }.value
            parts.append("# Análisis completo del motor AVO Equine (compactado: sin series temporales; listas largas resumidas)\n" + compact)
        } else {
            parts.append("# Análisis del motor\nNo hay análisis del motor en memoria para esta sesión.")
        }

        // historia: sesiones anteriores del mismo caballo con resumen ya calculado (no se lanza el motor para ellas)
        let previous: [SessionItem] = app.historySessions(app.horseKey(s), until: s.start)
            .filter { $0.id != s.id }
            .sorted { ($0.start ?? .distantPast) > ($1.start ?? .distantPast) }
        var history: [String] = []
        for p in previous.prefix(AssistantModel.historySessions) {
            guard let d = AvoFiles.read(app.trainingSummaryPath(p.id)) else { continue }
            history.append("## \(p.dateTimeText) (id \(p.id))\n" + AssistantJSON.compact(String(decoding: d, as: UTF8.self), dropKeys: [], maxArray: 12))
        }
        if history.isEmpty {
            parts.append("# Historia del caballo\nNo hay resúmenes de sesiones anteriores de este caballo en el iPad.")
        } else {
            parts.append("# Historia del caballo: \(history.count) sesiones anteriores, de la más reciente a la más antigua\n"
                         + history.joined(separator: "\n"))
        }

        var text: String = parts.joined(separator: "\n\n")
        if text.count > AssistantModel.maxContextChars {
            text = String(text.prefix(AssistantModel.maxContextChars)) + "\n[… datos recortados por tamaño]"
        }
        contextText = text
        contextSessionId = signature
        return text
    }

    static let instructions: String = """
    Eres el analista de rendimiento de AVO Performance Horse, un sistema de telemetría para caballos de carreras \
    (Pura Sangre Inglés, árabes y trotones) que entrenan sobre todo en la playa del Regatón (Laredo).

    Datos que recibes (en el bloque siguiente, en JSON):
    - Chaleco GPS RTK (velocidad, distancia, parciales) y cincha con IMU BNO085 (zancada, cadencia, VeDBA, giros, mano de galope).
    - «Resumen de la sesión»: AVO Training Analytics (tiempo y distancia por aire, carga, valoración RPE del entrenador).
    - «Análisis completo del motor»: incluye «trabajo_pista» (fases calentamiento/trabajo/calma, trabajos y pasadas \
    con parciales cada 200 m o furlong, mejores distancias, v. máx., últimos 200/400 m, índice de caída, recuperación, \
    zancada a las velocidades de referencia de la raza, cincha y mano), rendimiento, eventos, simetría y calidad GNSS.
    - «Historia del caballo»: resúmenes de sesiones anteriores para comparar y ver tendencias.
    Unidades: velocidades en m/s salvo que el campo diga km/h (1 m/s = 3,6 km/h); distancias en metros; tiempos en segundos.

    Cómo respondes:
    - En español, claro y directo, para un entrenador. Empieza por la conclusión y después los datos que la apoyan.
    - Usa SOLO los datos recibidos. Cita las cifras concretas (con unidades, velocidades también en km/h). \
    Si un dato falta o la calidad GNSS es mala, dilo en vez de suponer.
    - Los umbrales y perfiles de raza del motor son valores de partida sin validar con caballos reales, y la mano de \
    galope es experimental: trátalos con prudencia.
    - Diferencia lo que es una observación de los datos de lo que es una hipótesis.
    - No haces diagnósticos veterinarios: si ves señales preocupantes (asimetrías, caídas bruscas, impactos atípicos), \
    recomienda que lo revise el veterinario.
    - Formato: párrafos cortos y listas breves; tablas solo si comparan varias sesiones o trabajos.
    """
}
