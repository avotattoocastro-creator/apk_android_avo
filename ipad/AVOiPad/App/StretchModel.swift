import Foundation
import Observation

/// «Análisis del tramo» (full-screen page) and the stretches saved on each horse. The page opens from the «Análisis
/// tramo» button of «Mapa» with the stretch selected on the charts (app.rangeStart / rangeEnd).
@Observable
final class StretchModel {
    @ObservationIgnored unowned let app: AppModel
    @ObservationIgnored let store: StretchStore
    @ObservationIgnored private var aiTask: Task<Void, Never>? = nil

    var visible: Bool = false
    var report: StretchReport? = nil
    @ObservationIgnored private(set) var session: SessionItem? = nil
    var t0: Double = .nan
    var t1: Double = .nan
    /// Saved stretch shown (opened from the horse's list), nil for a new one.
    var savedId: String? = nil
    var saveName: String = ""
    var message: String = ""
    var aiText: String = ""
    var aiBusy: Bool = false
    var aiStatus: String = ""
    var aiFooter: String = ""
    /// Bumped when the saved list changes (views of the horse refresh).
    var version: Int = 0
    /// Last AI analysis of each stretch analysed in this run of the app (session|t0|t1), so it survives closing the page
    /// and goes into the reports even when the stretch was not saved.
    @ObservationIgnored private var aiCache: [String: (sessionId: String, t0: Double, t1: Double, text: String)] = [:]
    /// PDF written by «Informe PDF», shown in the share sheet (Files, AirDrop, Mail…).
    var pdfFile: ExportedFile? = nil

    init(app: AppModel) {
        self.app = app
        store = StretchStore(root: app.paths.root)
    }

    // ---------------------------------------------------------------- open / close
    var canOpen: Bool { app.selected != nil && app.hasRange }

    /// Opens the page with the stretch selected now on the charts.
    func openCurrent() {
        guard let s = app.selected, app.hasRange else {
            message = "Selecciona antes un tramo en la gráfica (mantén pulsado y arrastra)."
            return
        }
        open(s, min(app.rangeStart, app.rangeEnd), max(app.rangeStart, app.rangeEnd), saved: nil)
    }

    /// Opens a saved stretch: selects its training (it must be loaded on the iPad) and the range.
    func openSaved(_ st: SavedStretch) {
        guard let s = app.sessions.first(where: { $0.id == st.sessionId }) else {
            app.fail(AvoError.invalidOperation("El entrenamiento de este tramo (\(st.sessionDate)) no está cargado en el iPad."))
            return
        }
        app.select(s)
        app.rangeStart = st.t0
        app.rangeEnd = st.t1
        app.charts.refreshRangeStats()
        open(s, st.t0, st.t1, saved: st)
    }

    private func open(_ s: SessionItem, _ a: Double, _ b: Double, saved: SavedStretch?) {
        stopAI()
        session = s
        t0 = a
        t1 = b
        savedId = saved?.id
        saveName = saved?.name ?? ""
        aiText = saved?.aiText ?? ""
        aiFooter = saved?.aiText.isEmpty == false ? "Análisis guardado con el tramo" : ""
        if aiText.isEmpty, let c = aiCache[StretchModel.key(s.id, a, b)] {
            aiText = c.text
            aiFooter = "Análisis IA anterior de este tramo"
        }
        aiStatus = ""
        message = ""
        report = StretchAnalyzer.compute(s.timeline, t0: a, t1: b, engine: s.engine, engineOffsetS: s.engineOffsetS,
                                         saved: otherSaved(s, excluding: saved?.id))
        visible = true
    }

    func close() {
        stopAI()
        visible = false
    }

    static func key(_ sid: String, _ a: Double, _ b: Double) -> String {
        sid + "|" + String(format: "%.1f", min(a, b)) + "|" + String(format: "%.1f", max(a, b))
    }

    /// AI analyses of a training for the reports: saved stretches with AI text, then the ones analysed but not saved.
    func aiAnalyses(for s: SessionItem) -> [(title: String, text: String)] {
        var out: [(title: String, text: String)] = []
        var seen = Set<String>()
        if let code = s.horseCode, !code.isEmpty {
            let mine: [SavedStretch] = store.of(horse: code).filter { $0.sessionId == s.id && !$0.aiText.isEmpty }
            for st in mine.sorted(by: { $0.t0 < $1.t0 }) {
                let name: String = st.name.isEmpty ? "" : st.name + " · "
                out.append((title: "Tramo " + name + TimeText.clock(st.t0) + " – " + TimeText.clock(st.t1), text: st.aiText))
                seen.insert(StretchModel.key(s.id, st.t0, st.t1))
            }
        }
        let cached = aiCache.filter { $0.value.sessionId == s.id && !seen.contains($0.key) && !$0.value.text.isEmpty }
        for c in cached.values.sorted(by: { $0.t0 < $1.t0 }) {
            out.append((title: "Tramo " + TimeText.clock(c.t0) + " – " + TimeText.clock(c.t1), text: c.text))
        }
        return out
    }

    /// Keeps the finished AI text: cache, and the saved stretch when it is one.
    private func keepAI() {
        guard let s = session, !aiText.isEmpty else { return }
        aiCache[StretchModel.key(s.id, t0, t1)] = (sessionId: s.id, t0: min(t0, t1), t1: max(t0, t1), text: aiText)
        if let id = savedId, var st = store.items.first(where: { $0.id == id }) {
            st.aiText = aiText
            try? store.update(st)
            version += 1
        }
    }

    // ---------------------------------------------------------------- saved stretches
    func savedOf(horse code: String) -> [SavedStretch] {
        _ = version
        return store.of(horse: code)
    }

    /// Saved stretches of the same horse, for the comparison (the open one excluded).
    func otherSaved(_ s: SessionItem? = nil, excluding: String? = nil) -> [SavedStretch] {
        guard let code = (s ?? session)?.horseCode, !code.isEmpty else { return [] }
        return savedOf(horse: code).filter { $0.id != (excluding ?? savedId) }
    }

    var horseName: String { session?.horse ?? "" }
    var canSave: Bool { session?.horseCode?.isEmpty == false && report != nil }

    func save() {
        guard let s = session, let r = report, let code = s.horseCode, !code.isEmpty else {
            message = "Este entrenamiento no tiene caballo asignado: asígnalo antes (botón Asignar)."
            return
        }
        let m: SegmentMetrics = r.metrics
        var st = SavedStretch(horseCode: code, horseName: s.horse, sessionId: s.id, sessionDate: s.dateTimeText,
                              name: saveName.trimmingCharacters(in: .whitespacesAndNewlines), t0: t0, t1: t1,
                              durationS: m.durationS, distanceM: m.distanceM, meanKmh: m.meanSpeedKmh, maxKmh: m.maxSpeedKmh,
                              best200S: r.best200S, lastVsBestPct: r.lastVsBestPct,
                              splitsS: r.splits.filter { !$0.partial }.map { $0.durationS }, aiText: aiText)
        do {
            if let id = savedId {
                st.id = id
                try store.update(st)
                message = "Tramo actualizado en \(s.horse)."
            } else {
                try store.add(st)
                savedId = st.id
                message = "Tramo guardado en \(s.horse) · Cuadra › \(s.horse) › Tramos guardados."
            }
            version += 1
            app.log.info("tramos", "tramo guardado", ["caballo": code, "sesion": s.id, "t0": t0, "t1": t1])
        } catch {
            message = "No se pudo guardar el tramo: " + error.localizedDescription
        }
    }

    func delete(_ id: String) {
        do {
            try store.remove(id)
            if savedId == id { savedId = nil }
            version += 1
        } catch {
            app.fail(error)
        }
    }

    // ---------------------------------------------------------------- PDF report
    /// «Informe PDF»: the whole analysis (figures, route, speed, 200 m splits, observations, comparison and the AI text if
    /// there is one) in exportaciones/AVO_tramo_<session>_<hhmmss>.pdf, then the share sheet.
    func exportPdf() {
        guard let s = session, let r = report else { return }
        if aiBusy {
            message = "Espera a que termine el análisis IA para que entre en el informe PDF."
            return
        }
        message = "Preparando el informe PDF (imagen de satélite del tramo)…"
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let tl: SessionTimeline = s.timeline
            let i0: Int = tl.indexAt(r.metrics.t0)
            let i1: Int = tl.indexAt(r.metrics.t1)
            var image: RouteImage? = nil
            if i0 >= 0 && i1 > i0 {
                image = await RouteImageRenderer.render(tl, widthPt: PdfDocument.a4Width - 80, heightPt: 230, from: i0, to: i1,
                                                        cacheDir: self.app.paths.tiles, distanceMarks: true)
            }
            self.writePdf(s, r, image)
        }
    }

    private func writePdf(_ s: SessionItem, _ r: StretchReport, _ image: RouteImage?) {
        var data = StretchPdfData(session: s.session, timeline: s.timeline, report: r, horse: s.horse, rider: s.rider,
                                  dateText: s.dateTimeText, name: saveName.trimmingCharacters(in: .whitespacesAndNewlines),
                                  others: otherSaved(s), aiText: aiText)
        data.routeImage = image
        let dir: String = AvoFiles.join(app.paths.root, "exportaciones")
        AvoFiles.ensureDir(dir)
        let name: String = ExportNaming.name(s, ExportNaming.rangeKind(r.metrics.t0, r.metrics.t1, label: saveName), "pdf")
        let path: String = AvoFiles.join(dir, name)
        do {
            try AvoFiles.writeAtomic(ReportBuilder.stretchPdf(data), to: path)
            pdfFile = ExportedFile(id: path, url: URL(fileURLWithPath: path), name: name, kind: .pdf,
                                   time: MadridTime.format(Date(), "dd/MM/yyyy HH:mm"))
            message = "Informe PDF creado: " + name
        } catch {
            message = "No se pudo crear el PDF: " + error.localizedDescription
        }
    }

    // ---------------------------------------------------------------- AI analysis
    var aiReady: Bool { app.assistant.usesClaude || app.assistant.onDeviceAvailable }

    func stopAI() {
        aiTask?.cancel()
        aiTask = nil
        aiBusy = false
    }

    static let aiQuestion: String = """
    Haz un análisis ULTRA completo de este tramo para el entrenador, en español y con estos apartados:
    1. Resumen (3–4 líneas con lo más importante).
    2. Ritmo y parciales de 200 m: cómo se repartió el esfuerzo, mejor y peor parcial, regularidad.
    3. Aceleración y velocidad máxima: cuánto tardó en llegar a su punta, cuánto la mantuvo.
    4. Fatiga y final del tramo: caída en los últimos 200 m y en la segunda mitad.
    5. Comparación con sus tramos guardados y con el resto del entrenamiento (si hay datos).
    6. Calidad de los datos (RTK, pérdidas de señal) y qué conclusiones son fiables.
    7. Recomendaciones concretas para los próximos entrenamientos (tipo de trabajo, distancias, ritmos), justificadas con los números.
    Usa solo los datos dados; si falta algo, dilo. No hagas diagnósticos veterinarios.
    """

    func askAI() {
        guard let s = session, let r = report, !aiBusy else { return }
        let a: AssistantModel = app.assistant
        if a.usesClaude && a.limitReached {
            aiStatus = "Límite de gasto del mes alcanzado (\(AssistantModel.usd(a.monthLimitUSD))). Súbelo en «Asistente IA» › Ajustes."
            return
        }
        guard aiReady else {
            aiStatus = "Configura la IA en «Asistente IA» › Ajustes (clave de Claude o modelo de Apple)."
            return
        }
        aiText = ""
        aiFooter = ""
        aiBusy = true
        aiTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            let ctx: String = await self.context(s, r)
            if Task.isCancelled { return }
            if a.usesClaude, let key = AvoKeychain.read() {
                await self.askClaude(key: key, context: ctx)
            } else {
                await self.askOnDevice(context: ctx)
            }
            self.aiBusy = false
            self.aiTask = nil
            self.keepAI()
        }
    }

    @MainActor
    private func context(_ s: SessionItem, _ r: StretchReport) async -> String {
        aiStatus = "Preparando los datos del tramo…"
        var t: String = "Caballo: \(s.horse) · Jinete: \(s.rider) · Entrenamiento: \(s.dateTimeText) · \(s.discipline)\n"
        t += "Entrenamiento completo: \(s.distanceText), \(s.durationText), vel. máx. \(s.maxSpeedText)\n\n"
        t += r.contextText()
        let others: [SavedStretch] = otherSaved(s)
        if !others.isEmpty {
            t += "\nTramos guardados de este caballo (fecha, nombre, distancia, tiempo, vel. media, vel. máx., mejor 200 m, último 200 m frente al mejor):\n"
            for o in others.prefix(30) {
                t += "  \(o.sessionDate) \(o.name): \(TimeText.num(o.distanceM, "0")) m, \(TimeText.clock(o.durationS)), \(TimeText.num(o.meanKmh, "0.0", " km/h")), máx \(TimeText.num(o.maxKmh, "0.0", " km/h")), mejor 200 \(TimeText.num(o.best200S, "0.00", " s")), final \(TimeText.num(o.lastVsBestPct, "+0.0;-0.0", " %"))\n"
            }
        }
        if await app.ensureTrainingSummary(s), let d = AvoFiles.read(app.trainingSummaryPath(s.id)) {
            var j: String = AssistantJSON.compact(String(decoding: d, as: UTF8.self))
            if j.count > 60_000 { j = String(j.prefix(60_000)) }
            t += "\nResumen del entrenamiento completo calculado por el motor AVO (JSON):\n" + j + "\n"
        }
        return t
    }

    @MainActor
    private func askClaude(key: String, context: String) async {
        let a: AssistantModel = app.assistant
        let m: ClaudeModel = a.model
        let system: [[String: Any]] = [
            ["type": "text", "text": AssistantModel.instructions],
            ["type": "text", "text": "Datos del tramo seleccionado:\n" + context],
        ]
        let messages: [[String: Any]] = [["role": "user", "content": StretchModel.aiQuestion]]
        aiStatus = "Claude \(m.title) está analizando el tramo (primero piensa; puede tardar 1–2 minutos)…"
        do {
            // long, complete answer: room for thinking + ~10 000 tokens of text; medium effort bounds the thinking
            for try await ev in ClaudeClient(apiKey: key).stream(model: m, system: system, messages: messages,
                                                                  maxTokens: 32_000, effort: "medium") {
                if Task.isCancelled { break }
                switch ev {
                case .text(let t):
                    if aiText.isEmpty { aiStatus = "Claude \(m.title) está escribiendo…" }
                    aiText += t
                case .done(let stop, let usage):
                    let cost: Double = usage.costUSD(m)
                    a.addSpend(cost)
                    aiFooter = "Claude \(m.title) · \(usage.totalTokens.formatted()) tokens · ~\(AssistantModel.usd(cost))"
                        + (stop == "max_tokens" ? " · respuesta cortada por longitud" : "")
                    aiStatus = ""
                }
            }
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            aiStatus = "Claude: " + error.localizedDescription
        }
    }

    @MainActor
    private func askOnDevice(context: String) async {
        aiStatus = "El modelo de Apple está analizando el tramo…"
        var ctx: String = context
        if ctx.count > OnDeviceAssistant.maxContextChars { ctx = String(ctx.prefix(OnDeviceAssistant.maxContextChars)) }
        let instructions: String = "Eres el asistente de AVO Performance Horse. Explicas en español los datos de un tramo de "
            + "entrenamiento de un caballo de carreras. Usa solo estos datos; si algo no está, dilo. No hagas diagnósticos "
            + "veterinarios.\n\nDatos:\n" + ctx
        do {
            let r: String = try await OnDeviceAssistant.respond(instructions: instructions, prompt: StretchModel.aiQuestion)
            if Task.isCancelled { return }
            aiText = r
            aiFooter = "Apple (en el iPad) · sin coste · análisis básico"
            aiStatus = ""
        } catch {
            if Task.isCancelled { return }
            aiStatus = error.localizedDescription
        }
    }
}
