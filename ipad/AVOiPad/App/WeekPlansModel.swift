import SwiftUI
import Observation

/// Planificador semanal (motor 2.0.0-dev37, TRAINING 1.4.0) de los caballos de la Cuadra para la semana natural en curso
/// (lunes–domingo, a la fecha de hoy en Europe/Madrid). Lo usan el botón «Planificador semanal» de la Cuadra (hoja con la
/// semana de un caballo) y el «Calendario» (entrenamiento recomendado de cada día). Orientativo y sin calibrar: no cambia el
/// estado del caballo y el entrenador decide.
@Observable
final class WeekPlansModel {
    @ObservationIgnored unowned let app: AppModel
    @ObservationIgnored private var task: Task<Void, Never>? = nil

    /// Plan por clave de caballo (código de la Cuadra).
    var plans: [String: WeekPlan] = [:]
    var names: [String: String] = [:]
    var errors: [String: String] = [:]
    /// Día (AAAA-MM-DD) al que se calcularon los planes; se recalculan al cambiar de día.
    var computedDay: String = ""
    var loading: Bool = false
    var progressText: String = ""

    /// Recomendaciones guardadas (planes_recomendados.json) para comparar después con lo realizado.
    @ObservationIgnored private var bookLoaded: Bool = false
    @ObservationIgnored private var book: RecommendationStore.Book = [:]
    private var bookPath: String { AvoFiles.join(app.paths.root, "planes_recomendados.json") }

    // hoja «Planificador semanal» de un caballo
    var sheetVisible: Bool = false
    var sheetKey: String = ""
    var sheetName: String = ""

    init(app: AppModel) {
        self.app = app
    }

    static var today: String { AvoTime.formatter("yyyy-MM-dd").string(from: Date()) }

    /// Caballos con plan: activos, no de demostración y con al menos una sesión.
    var horses: [StableIdentityRow] {
        app.stable.horses.allRows.filter { !$0.isDemo && $0.active && $0.count > 0 }
    }

    // ---------------------------------------------------------------- hoja de un caballo
    @MainActor
    func open(horseKey: String, name: String) {
        sheetKey = horseKey
        sheetName = name
        sheetVisible = true
        if plans[horseKey] == nil || computedDay != Self.today { reloadOne(horseKey, name: name) }
    }

    @MainActor
    func close() { sheetVisible = false }

    @MainActor
    func reloadOne(_ key: String, name: String) {
        task?.cancel()
        task = Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.loading = true
            await self.compute(key, name: name)
            self.loading = false
            self.progressText = ""
        }
    }

    // ---------------------------------------------------------------- todos (calendario)
    /// Calcula el plan de cada caballo activo si no está hecho hoy (o si `force`).
    @MainActor
    func loadAll(force: Bool = false) {
        let day: String = Self.today
        if !force && computedDay == day && !plans.isEmpty { return }
        if loading { return }
        task?.cancel()
        let list: [StableIdentityRow] = horses
        task = Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.loading = true
            if self.computedDay != day { self.plans = [:]; self.errors = [:] }
            var k: Int = 0
            for h in list {
                if Task.isCancelled { break }
                k += 1
                self.progressText = "Planificando \(h.name) (\(k)/\(list.count))…"
                await self.compute(h.code, name: h.name)
            }
            self.computedDay = day
            self.loading = false
            self.progressText = ""
        }
    }

    @MainActor
    private func compute(_ key: String, name: String) async {
        do {
            let r: (result: TrainingAnalysisResult, missing: Int) = try await app.analyseHorseHistory(key, reference: Self.today)
            if Task.isCancelled { return }
            plans[key] = r.result.semanaSiguiente
            names[key] = name
            remember(key, r.result.semanaSiguiente)
            errors[key] = nil
            computedDay = Self.today
        } catch is CancellationError {
            return
        } catch {
            errors[key] = error.localizedDescription
            names[key] = name
        }
    }

    // ---------------------------------------------------------------- recomendaciones guardadas
    @MainActor
    private func ensureBook() {
        if bookLoaded { return }
        book = RecommendationStore.load(bookPath)
        bookLoaded = true
    }

    @MainActor
    private func remember(_ key: String, _ plan: WeekPlan) {
        ensureBook()
        if RecommendationStore.merge(&book, horseKey: key, plan: plan, today: Self.today, now: Date(), engine: app.engineShort) {
            RecommendationStore.save(book, to: bookPath)
        }
    }

    @MainActor
    func saved(_ key: String, _ day: String) -> SavedRecommendation? {
        ensureBook()
        return book[key]?[day]
    }

    // ---------------------------------------------------------------- ficha de un caballo y un día
    /// Lo recomendado (guardado o, si no, recalculado con los datos hasta la víspera) y lo realizado ese día.
    @MainActor
    func ficha(horseKey key: String, name: String, day: String) async -> PlanFicha {
        var f = PlanFicha(horseKey: key, horseName: name, day: day)
        f.engine = app.engineShort
        let dayFmt: DateFormatter = AvoTime.formatter("yyyy-MM-dd")
        f.sessions = app.historySessions(key).filter { (s: SessionItem) -> Bool in
            guard let d = s.start else { return false }
            return dayFmt.string(from: d) == day
        }.compactMap { (s: SessionItem) -> PlanFichaSession? in
            guard let d = s.start else { return nil }
            let e: CalendarEntry? = app.calendarEntries.first { $0.id == s.id }
            return PlanFichaSession(id: s.id, start: d, rider: s.rider, distanceKm: e?.distanceKm ?? 0, durationS: e?.durationS ?? 0)
        }.sorted { $0.start < $1.start }
        // recomendado
        if let r = saved(key, day) {
            f.recommended = r.asDay
            f.phase = r.phase
            f.recommendedOrigin = "Recomendación guardada el \(AvoTime.text(r.savedAt, "dd/MM/yyyy HH:mm")) (motor \(r.engine))"
        } else if day >= Self.today, let p = plans[key], let d = p.days.first(where: { $0.date == day && !$0.done }) {
            f.recommended = d
            f.phase = p.phase
            f.recommendedOrigin = "Recomendación actual del planificador"
        } else if let prev = Self.shift(day, -1) {
            do {
                // la víspera: el día pedido es el primero que se planifica (semana natural o, si cae fuera, 7 días siguientes)
                var r = try await app.analyseHorseHistory(key, reference: prev)
                var d: WeekPlanDay? = r.result.semanaSiguiente.days.first { $0.date == day && !$0.done }
                if d == nil {
                    r = try await app.analyseHorseHistory(key, reference: prev, calendarWeek: false)
                    d = r.result.semanaSiguiente.days.first { $0.date == day && !$0.done }
                }
                if let d = d {
                    f.recommended = d
                    f.phase = r.result.semanaSiguiente.phase
                    f.recommendedOrigin = "Recalculada con el motor con los datos hasta la víspera (no se había guardado)"
                }
            } catch {
                f.error = error.localizedDescription
            }
        }
        // realizado (el motor a ese día: tipo de día y metros de galope rápido)
        if f.hasRealized {
            do {
                let r = try await app.analyseHorseHistory(key, reference: day)
                f.realized = r.result.semanaSiguiente.days.first { $0.date == day && $0.done }
            } catch {
                f.error = error.localizedDescription
            }
        }
        return f
    }

    /// AAAA-MM-DD ± días.
    static func shift(_ day: String, _ delta: Int) -> String? {
        let f: DateFormatter = AvoTime.formatter("yyyy-MM-dd")
        guard let d = f.date(from: day), let n = Calendar(identifier: .gregorian).date(byAdding: .day, value: delta, to: d) else { return nil }
        return f.string(from: n)
    }

    // ---------------------------------------------------------------- consulta por día
    /// Día de la semana de cada caballo con plan (propuesto o realizado) para la fecha AAAA-MM-DD.
    func items(on day: String) -> [WeekPlanItem] {
        var out: [WeekPlanItem] = []
        for (key, plan) in plans where plan.available {
            if let d = plan.days.first(where: { $0.date == day }) { out.append(WeekPlanItem(key: key, name: names[key] ?? key, day: d)) }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// Un día del plan de un caballo (Calendario).
struct WeekPlanItem: Identifiable {
    let key: String
    let name: String
    let day: WeekPlanDay
    var id: String { key + "|" + day.date }
}
