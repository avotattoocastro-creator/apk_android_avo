import Foundation

/// Comparables por condiciones en la historia (motor 2.0.0-dev41, TRAINING 1.7.0, KB-1 1.34.0): bloque
/// «estado.condiciones» de «avo-training-analysis» con TC1–TC4 (temperatura, calor por WBGT y aclimatación), PC1–PC3
/// (peso del jinete, mismo jinete y peso cargado relativo) y GO1 (estrato de going). Solo filtra las sesiones con las que
/// se compara A7, A8, A9 y la cinética de la FC. Siempre INFO y sin calibrar: no cambia el estado del caballo y no es un
/// diagnóstico. Ficha: equine-intelligence/docs/algoritmos/12_ENTRENAMIENTO.md. Sin dato = nil.
struct ConditionsRuleCount: Identifiable, Equatable {
    var rule: String
    var metric: String
    var base: Int
    var kept: Int
    var temperature: Int
    var heat: Int
    var going: Int
    var weight: Int
    var otherRider: Int
    var sameRider: Bool
    var id: String { rule + metric }

    init(_ o: [String: Any]?) {
        typealias J = EngineJSON
        rule = J.str(o, "regla")
        metric = J.str(o, "metrica")
        base = J.int(J.num(o, "sesiones_base") ?? 0)
        kept = J.int(J.num(o, "sesiones_comparables") ?? 0)
        let x = J.obj(o, "excluidas")
        temperature = J.int(J.num(x, "temperatura") ?? 0)
        heat = J.int(J.num(x, "calor") ?? 0)
        going = J.int(J.num(x, "going") ?? 0)
        weight = J.int(J.num(x, "peso") ?? 0)
        otherRider = J.int(J.num(x, "otro_jinete") ?? 0)
        sameRider = J.bool(o, "mismo_jinete")
    }

    var title: String {
        switch rule {
        case "A9": return "V200 (A9)"
        case "A7": return "Zancada (A7)"
        case "A8": return "Últimos 600 m (A8)"
        case "CF2": return "Recuperación τ (CF2)"
        default: return rule
        }
    }

    /// «3 de 11 sesiones» (incluye la última).
    var valueText: String { "\(kept) de \(base) sesiones" }

    /// «fuera: 8 por calor, 1 por peso» o «sin exclusiones».
    var excludedText: String {
        var p: [String] = []
        if temperature > 0 { p.append("\(temperature) por temperatura") }
        if heat > 0 { p.append("\(heat) por calor") }
        if going > 0 { p.append("\(going) por going") }
        if weight > 0 { p.append("\(weight) por peso") }
        if otherRider > 0 { p.append("\(otherRider) de otro jinete") }
        return p.isEmpty ? "Sin exclusiones" : "Fuera: " + p.joined(separator: ", ")
    }
}

struct ConditionsMark: Identifiable, Equatable {
    var date: String
    var sessionId: String
    var rule: String
    var text: String
    var evidence: String
    var id: String { date + sessionId + rule }
}

struct TrainingConditions: Equatable {
    var present: Bool
    var available: Bool
    var level: String
    var validated: Bool
    var reason: String
    var lastId: String
    var lastDate: String
    var temperatureC: Double?
    var humidityPct: Double?
    var going: String
    var rider: String
    var riderKg: Double?
    var horseKg: Double?
    var wbgt: Double?
    /// MEDIDO | ESTIMADO_T_HR | ""
    var wbgtOrigin: String
    /// CALOR | NORMAL | ""
    var heat: String
    /// FIRME | BUENO | BLANDO | PESADO | ""
    var goingStratum: String
    var carriedPct: Double?
    var heatDay: Int?
    var rules: [ConditionsRuleCount]
    var marks: [ConditionsMark]
    var notes: [String]

    init(_ o: [String: Any]?) {
        typealias J = EngineJSON
        present = o != nil
        available = J.bool(o, "disponible")
        let l = J.str(o, "nivel")
        level = l.isEmpty ? "INFO" : l
        validated = J.bool(o, "validado")
        reason = J.str(o, "motivo")
        let u = J.obj(o, "ultima")
        lastId = J.str(u, "id")
        lastDate = J.str(u, "fecha")
        temperatureC = KbText.finite(J.num(u, "temperatura_c"))
        humidityPct = KbText.finite(J.num(u, "humedad_pct"))
        going = J.str(u, "going")
        rider = J.str(u, "jinete")
        riderKg = KbText.finite(J.num(u, "peso_jinete_kg"))
        horseKg = KbText.finite(J.num(u, "peso_caballo_kg"))
        let c = J.obj(u, "condiciones")
        wbgt = KbText.finite(J.num(c, "wbgt_c"))
        wbgtOrigin = J.str(c, "wbgt_origen")
        heat = J.str(c, "calor")
        goingStratum = J.str(c, "estrato_going")
        carriedPct = KbText.finite(J.num(c, "peso_cargado_pct"))
        heatDay = J.num(u, "dia_periodo_calor").map { J.int($0) }
        rules = J.objs(u, "comparables").map { ConditionsRuleCount($0) }
        marks = J.objs(o, "marcas").map {
            ConditionsMark(date: J.str($0, "fecha"), sessionId: J.str($0, "id"), rule: J.str($0, "regla"),
                           text: J.str($0, "texto"), evidence: J.str($0, "evidencia"))
        }
        notes = J.arr(o, "notas").compactMap { $0 as? String }
    }

    /// «31 °C · 75 %» o «sin datos».
    var weatherText: String {
        guard let t = temperatureC else { return KbText.noData }
        return AvoFormat.f(t, 0) + " °C" + (humidityPct.map { " · " + AvoFormat.f($0, 0) + " %" } ?? "")
    }

    /// «34,7 °C (estimado)» / «27 °C (medido)» o «sin datos».
    var wbgtText: String {
        guard let w = wbgt else { return KbText.noData }
        return AvoFormat.f(w, 1) + " °C" + (wbgtOrigin == "MEDIDO" ? " (medido)" : " (estimado)")
    }

    var heatText: String {
        switch heat {
        case "CALOR": return heatDay.map { "Calor · día \($0)" } ?? "Calor"
        case "NORMAL": return "Sin calor"
        default: return KbText.noData
        }
    }

    static func stratumTitle(_ code: String) -> String {
        switch code {
        case "FIRME": return "Firme"
        case "BUENO": return "Bueno"
        case "BLANDO": return "Blando"
        case "PESADO": return "Pesado"
        default: return KbText.noData
        }
    }

    /// «62 kg · 13,8 % del caballo» o «sin datos».
    var weightText: String {
        guard let r = riderKg else { return KbText.noData }
        return AvoFormat.f(r, 0) + " kg" + (carriedPct.map { " · " + AvoFormat.f($0, 1) + " % del caballo" } ?? "")
    }
}
