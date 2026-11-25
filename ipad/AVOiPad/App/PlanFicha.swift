import Foundation

/// Recomendación del planificador guardada en el iPad (planes_recomendados.json) para poder compararla después con lo
/// realizado (boceto del entrenador 25/11/2026). Se guarda cada vez que la app calcula la semana de un caballo: la última
/// propuesta hecha ANTES del día es la que vale. Los días ya pasados no se sobrescriben.
struct SavedRecommendation: Codable, Equatable {
    var date: String            // AAAA-MM-DD
    var type: String            // RAPIDO | LENTO | SUAVE | LIBRE | CARRERA
    var reason: String
    var fastMaxM: Double?
    var rules: [String]
    var phase: String
    var savedAt: Date
    var engine: String

    var asDay: WeekPlanDay { WeekPlanDay(date: date, type: type, reason: reason, fastMaxM: fastMaxM, rules: rules) }
}

/// planes_recomendados.json: clave del caballo → fecha → recomendación.
enum RecommendationStore {
    typealias Book = [String: [String: SavedRecommendation]]

    static func load(_ path: String) -> Book {
        guard let d = FileManager.default.contents(atPath: path) else { return [:] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode(Book.self, from: d)) ?? [:]
    }

    static func save(_ book: Book, to path: String) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let d = try? enc.encode(book) else { return }
        try? d.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    /// Añade los días del plan que aún no han pasado (`today` o después). Devuelve si cambió algo.
    static func merge(_ book: inout Book, horseKey: String, plan: WeekPlan, today: String, now: Date, engine: String) -> Bool {
        guard plan.available else { return false }
        var changed: Bool = false
        var mine: [String: SavedRecommendation] = book[horseKey] ?? [:]
        for d in plan.days where !d.done && d.date >= today {
            let r = SavedRecommendation(date: d.date, type: d.type, reason: d.reason, fastMaxM: d.fastMaxM, rules: d.rules,
                                        phase: plan.phase, savedAt: now, engine: engine)
            if let old = mine[d.date], old.type == r.type, old.reason == r.reason, old.fastMaxM == r.fastMaxM { continue }
            mine[d.date] = r
            changed = true
        }
        if changed { book[horseKey] = mine }
        return changed
    }
}

/// Una sesión hecha ese día por el caballo (para la ficha).
struct PlanFichaSession: Identifiable, Equatable {
    let id: String
    let start: Date
    let rider: String
    let distanceKm: Double
    let durationS: Double
}

/// Ficha de un caballo y un día: lo recomendado por el planificador y, si ya entrenó, lo realizado y la comparación.
struct PlanFicha: Identifiable, Equatable {
    var id: String { horseKey + "|" + day }
    let horseKey: String
    let horseName: String
    let day: String
    var recommended: WeekPlanDay? = nil
    /// «Guardada el …» o «Recalculada con el motor (datos hasta la víspera)».
    var recommendedOrigin: String = ""
    var phase: String = ""
    var realized: WeekPlanDay? = nil
    var sessions: [PlanFichaSession] = []
    var engine: String = ""
    var error: String? = nil

    var hasRealized: Bool { !sessions.isEmpty }

    /// Comparación de lo recomendado con lo realizado (frases para la ficha y el PDF). Orientativa: el entrenador decide.
    var comparison: [String] {
        guard hasRealized else { return [] }
        guard let rec = recommended else { return ["Sin recomendación del planificador para ese día."] }
        let doneType: String = realized?.type ?? "LENTO"
        let fast: Double? = realized?.doneFastM
        var out: [String] = []
        switch (rec.type, doneType) {
        case ("RAPIDO", "RAPIDO"):
            out.append("Cumplido: se recomendaba trabajo rápido y se hizo.")
        case ("RAPIDO", _):
            out.append("Se recomendaba trabajo rápido y no se hizo (\(WeekPlan.typeTitle(doneType).lowercased())).")
        case (_, "RAPIDO"):
            out.append("Se hizo trabajo rápido en un día recomendado como \(WeekPlan.typeTitle(rec.type).lowercased()).")
        case ("LIBRE", _):
            out.append("Se entrenó en un día recomendado como libre.")
        case ("CARRERA", "CARRERA"):
            out.append("Carrera prevista y realizada.")
        default:
            out.append("Cumplido: día \(WeekPlan.typeTitle(rec.type).lowercased()) y entrenamiento sin trabajo rápido.")
        }
        if let f = fast, f > 0 {
            if let mx = rec.fastMaxM, rec.type == "RAPIDO" {
                out.append(f > mx ? "Galope rápido \(KbText.metres(f)), por encima del tope recomendado de \(KbText.metres(mx))."
                                  : "Galope rápido \(KbText.metres(f)), dentro del tope recomendado de \(KbText.metres(mx)).")
            } else {
                out.append("Galope rápido hecho: \(KbText.metres(f)).")
            }
        }
        return out
    }

    /// true si lo realizado coincide con el tipo recomendado (para el color de la ficha).
    var matches: Bool? {
        guard hasRealized, let rec = recommended else { return nil }
        let d: String = realized?.type ?? "LENTO"
        if rec.type == "RAPIDO" { return d == "RAPIDO" && (rec.fastMaxM == nil || (realized?.doneFastM ?? 0) <= (rec.fastMaxM ?? .infinity)) }
        if rec.type == "LIBRE" { return false }
        return d != "RAPIDO"
    }
}
