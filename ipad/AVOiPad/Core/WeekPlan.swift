import Foundation

/// Capa 2 del planificador semanal (motor 2.0.0-dev35, KB-1 1.31.0): propuesta orientativa de la semana siguiente del
/// bloque «estado.planificador.semana_siguiente» de «avo-training-analysis» (P1, P2, P4–P7, RT1–RT3 y DM1–DM4).
/// Sin calibrar: nunca cambia el estado del caballo ni es una predicción; el entrenador decide.
/// Ficha: equine-intelligence/docs/algoritmos/12_ENTRENAMIENTO.md §5 ter. Los campos sin dato quedan nil.
struct WeekPlanDay: Identifiable, Equatable {
    var date: String
    /// RAPIDO | LENTO | SUAVE | LIBRE | CARRERA
    var type: String
    var reason: String
    var fastMaxM: Double?
    var rules: [String]
    /// Día ya pasado de la semana: lo realizado según las sesiones (motor 2.0.0-dev37), no una propuesta.
    var done: Bool
    var id: String { date }

    init(_ o: [String: Any]?) {
        typealias J = EngineJSON
        date = J.str(o, "fecha")
        type = J.str(o, "tipo")
        reason = J.str(o, "motivo")
        fastMaxM = KbText.finite(J.num(o, "rapido_max_m"))
        rules = J.arr(o, "reglas").compactMap { $0 as? String }
        done = J.bool(o, "realizado")
    }

    var typeText: String { WeekPlan.typeTitle(type) }
}

struct WeekPlanNote: Identifiable, Equatable {
    var rule: String
    var text: String
    var evidence: String
    var id: String { rule + "|" + text }
}

struct WeekPlan: Equatable {
    var present: Bool
    var available: Bool
    var reason: String
    var from: String
    var to: String
    /// NORMAL | POTRO_2_ANOS | REINCORPORACION_LENTA | REINCORPORACION_RAPIDO
    var phase: String
    var limited: Bool
    var ageYears: Int?
    var ageOrigin: String
    var fastTarget: Int
    var fastPlanned: Int
    /// Rápidos ya hechos en los días pasados de la semana (semana natural, motor 2.0.0-dev37).
    var fastDone: Int
    var calendarWeek: Bool
    /// Primer día planificado (AAAA-MM-DD): hoy si aún no hay sesión, si no mañana.
    var planFrom: String
    var fastRefM: Double?
    var fastMaxM: Double?
    var p5MeanM: Double?
    var p5P75M: Double?
    var daysSinceBreak: Int?
    var days: [WeekPlanDay]
    var notes: [WeekPlanNote]
    var validated: Bool
    var note: String

    init(_ o: [String: Any]?) {
        typealias J = EngineJSON
        present = o != nil
        available = J.bool(o, "disponible")
        reason = J.str(o, "motivo")
        from = J.str(o, "desde")
        to = J.str(o, "hasta")
        phase = J.str(o, "fase")
        limited = J.bool(o, "limitada")
        ageYears = J.num(o, "edad_anos").map { J.int($0) }
        ageOrigin = J.str(o, "edad_origen")
        fastTarget = J.int(J.num(o, "rapidos_objetivo") ?? 0)
        fastPlanned = J.int(J.num(o, "rapidos_propuestos") ?? 0)
        fastDone = J.int(J.num(o, "rapidos_hechos") ?? 0)
        calendarWeek = J.bool(o, "semana_calendario")
        planFrom = J.str(o, "planifica_desde")
        fastRefM = KbText.finite(J.num(o, "rapido_ref_m"))
        fastMaxM = KbText.finite(J.num(o, "rapido_max_m"))
        p5MeanM = KbText.finite(J.num(o, "p5_media_60d_m"))
        p5P75M = KbText.finite(J.num(o, "p5_p75_m"))
        daysSinceBreak = J.num(o, "dias_desde_descanso").map { J.int($0) }
        days = J.objs(o, "dias").map { WeekPlanDay($0) }
        notes = J.objs(o, "pautas").map { WeekPlanNote(rule: J.str($0, "regla"), text: J.str($0, "texto"), evidence: J.str($0, "evidencia")) }
        validated = J.bool(o, "validado")
        note = J.str(o, "nota")
    }

    var phaseText: String {
        switch phase {
        case "NORMAL": return "Semana normal"
        case "POTRO_2_ANOS": return "Potro de 2 años"
        case "REINCORPORACION_LENTA": return "Vuelta al trabajo: fase lenta"
        case "REINCORPORACION_RAPIDO": return "Vuelta al trabajo rápido"
        default: return phase.isEmpty ? KbText.noData : phase
        }
    }

    /// «2 de 2 rápidos» (hechos + propuestos) o «1 de 2 rápidos (no caben más)».
    var fastText: String {
        let total: Int = fastDone + fastPlanned
        let base: String = "\(total) de \(fastTarget) rápido\(fastTarget == 1 ? "" : "s")"
        return total < fastTarget ? base + " (no caben más)" : base
    }

    /// «1 hecho · 1 propuesto» (semana natural) o «≥ 72 h entre rápidos».
    var fastCaption: String {
        guard calendarWeek else { return "≥ 72 h entre rápidos" }
        return "\(fastDone) hecho\(fastDone == 1 ? "" : "s") · \(fastPlanned) propuesto\(fastPlanned == 1 ? "" : "s") · ≥ 72 h entre rápidos"
    }

    /// Día de la semana corto de una fecha AAAA-MM-DD («lun», «mar»…), en Europe/Madrid.
    static func weekdayShort(_ day: String) -> String {
        let f: DateFormatter = AvoTime.formatter("yyyy-MM-dd")
        guard let d = f.date(from: String(day.prefix(10))) else { return "" }
        return AvoTime.formatter("EEE").string(from: d).replacingOccurrences(of: ".", with: "")
    }

    static func typeTitle(_ t: String) -> String {
        switch t {
        case "RAPIDO": return "Rápido"
        case "LENTO": return "Lento"
        case "SUAVE": return "Suave"
        case "LIBRE": return "Libre"
        case "CARRERA": return "Carrera"
        default: return t
        }
    }

    /// Nombre corto de la regla para la interfaz («PLANIFICADOR_P4» → «P4», «RECUPERACION_RT2» → «RT2»).
    static func ruleTitle(_ r: String) -> String {
        if let i = r.lastIndex(of: "_") { return String(r[r.index(after: i)...]) }
        return r
    }
}
