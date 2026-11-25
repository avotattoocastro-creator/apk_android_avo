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
            errors[key] = nil
            computedDay = Self.today
        } catch is CancellationError {
            return
        } catch {
            errors[key] = error.localizedDescription
            names[key] = name
        }
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
