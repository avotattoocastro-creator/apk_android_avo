import Foundation

/// Cinética de la FC en la historia (motor 2.0.0-dev40, TRAINING 1.6.0, KB-1 1.33.0): bloque «estado.cinetica_fc» de
/// «avo-training-analysis» con CF2 (τ de recuperación), RC1 (THR100), FW1 (FC del tramo fijo del calentamiento) y WU3
/// (comparables con calentamiento parecido). Siempre INFO y sin calibrar: no cambia el estado del caballo y no es un
/// diagnóstico. Ficha: equine-intelligence/docs/algoritmos/15_ECG_V200.md §7 ter. Sin dato = nil.
struct HrKineticsMetric: Identifiable, Equatable {
    /// TAU_RECUPERACION | THR100 | FC_TRAMO_FIJO
    var metric: String
    var rule: String
    var unit: String
    var value: Double?
    var median: Double?
    var n: Int
    var change: Double?
    /// «%» o «lpm»
    var changeUnit: String
    var comparable: String
    var marked: Bool
    var id: String { metric }

    init(_ o: [String: Any]?) {
        typealias J = EngineJSON
        metric = J.str(o, "metrica")
        rule = J.str(o, "regla")
        unit = J.str(o, "unidad")
        value = KbText.finite(J.num(o, "valor"))
        median = KbText.finite(J.num(o, "mediana"))
        n = J.int(J.num(o, "n") ?? 0)
        change = KbText.finite(J.num(o, "cambio"))
        changeUnit = J.str(o, "cambio_unidad")
        comparable = J.str(o, "comparables")
        marked = J.bool(o, "marcada")
    }

    var title: String {
        switch metric {
        case "TAU_RECUPERACION": return "Recuperación (τ)"
        case "THR100": return "Tiempo hasta 100 lpm"
        case "FC_TRAMO_FIJO": return "FC del trote fijo"
        default: return metric
        }
    }

    /// «117 s» / «109 lpm» o «sin datos».
    var valueText: String { value.map { AvoFormat.f($0, 0) + " " + unit } ?? KbText.noData }

    /// «+30 % sobre su mediana (90 s, 4 ses.)» o el motivo de que no haya comparación.
    var changeText: String {
        guard value != nil else { return "Sin dato en la última sesión" }
        guard let c = change, let m = median else { return "Pocas sesiones comparables (\(n))" }
        let sign = c > 0 ? "+" : c < 0 ? "−" : ""
        let u = changeUnit == "%" ? " %" : " lpm"
        return sign + AvoFormat.f(abs(c), 0) + u + " sobre su mediana (" + AvoFormat.f(m, 0) + " " + unit + ", \(n) ses.)"
    }
}

struct HrKineticsMark: Identifiable, Equatable {
    var date: String
    var sessionId: String
    var rule: String
    var text: String
    var evidence: String
    var id: String { date + sessionId + rule }
}

struct TrainingHrKinetics: Equatable {
    var present: Bool
    var available: Bool
    var level: String
    var validated: Bool
    var reason: String
    var ecgSessions: Int
    var lastId: String
    var lastDate: String
    var cooldown: String
    var warmupM: Double?
    var warmupS: Double?
    var metrics: [HrKineticsMetric]
    var marks: [HrKineticsMark]
    var notes: [String]

    init(_ o: [String: Any]?) {
        typealias J = EngineJSON
        present = o != nil
        available = J.bool(o, "disponible")
        let l = J.str(o, "nivel")
        level = l.isEmpty ? "INFO" : l
        validated = J.bool(o, "validado")
        reason = J.str(o, "motivo")
        ecgSessions = J.int(J.num(o, "sesiones_ecg") ?? 0)
        let u = J.obj(o, "ultima")
        lastId = J.str(u, "id")
        lastDate = J.str(u, "fecha")
        cooldown = J.str(u, "vuelta_calma")
        warmupM = KbText.finite(J.num(u, "calentamiento_m"))
        warmupS = KbText.finite(J.num(u, "calentamiento_s"))
        metrics = J.objs(u, "metricas").map { HrKineticsMetric($0) }
        marks = J.objs(o, "marcas").map {
            HrKineticsMark(date: J.str($0, "fecha"), sessionId: J.str($0, "id"), rule: J.str($0, "regla"),
                           text: J.str($0, "texto"), evidence: J.str($0, "evidencia"))
        }
        notes = J.arr(o, "notas").compactMap { $0 as? String }
    }

    static func cooldownTitle(_ code: String) -> String {
        switch code {
        case "PARADO": return "Parado"
        case "PASO": return "Al paso"
        case "TROTE": return "Al trote"
        default: return KbText.noData
        }
    }
}
