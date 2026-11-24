import Foundation

// Base científica KB-1 del motor (equine-intelligence/docs/algoritmos/14_BASE_CIENTIFICA.md, include/avo_eq/knowledge.h).
// Modelos tolerantes de los bloques que el motor ya calcula:
//  · por sesión: «trabajo_pista.base_cientifica» (bandas B1/B2/B3 con sus límites, Verheyen, fatiga ósea);
//  · en la historia: «estado.base_cientifica» y «sesiones[].base_cientifica» (ventanas de 7, 30 y 60 días, días sin
//    trabajo rápido, vuelta tras descanso, cociente de galope, ratio de fatiga ósea semanal y reglas activas).
// Un campo ausente o null queda en nil y la vista muestra «sin datos»: aquí no se calcula ni se estima nada.
// Orientativo: reglas de la literatura con umbrales de partida, sin validar con la cuadra. NO VERIFICADO con caballos.

private typealias KJ = EngineJSON

// ------------------------------------------------------------------ por sesión

/// Una banda de velocidad (B1 trabajo, B2 intermedia, B3 alta) con sus límites en m/s.
struct KbBand: Identifiable, Equatable {
    var id: Int
    var code: String            // B1_TRABAJO | B2_INTERMEDIA | B3_ALTA
    var vMin: Double?           // m/s
    var vMax: Double?           // m/s (nil en B3: sin límite superior)
    var distanceM: Double?
    var timeS: Double?

    var shortName: String {
        switch code {
        case "B1_TRABAJO": return "B1"
        case "B2_INTERMEDIA": return "B2"
        case "B3_ALTA": return "B3"
        default: return code
        }
    }

    var name: String {
        switch code {
        case "B1_TRABAJO": return "B1 · trabajo"
        case "B2_INTERMEDIA": return "B2 · intermedia"
        case "B3_ALTA": return "B3 · alta"
        default: return code
        }
    }

    /// «11,0–13,4 m/s», «≥ 15,5 m/s» o «sin datos» si falta el ritmo de carrera.
    var limitsText: String { KbText.range(vMin, vMax) }
}

/// Bloque «trabajo_pista.base_cientifica» de una sesión.
struct KbSessionBlock: Equatable {
    var present: Bool = false
    var base: String = ""                   // AVO_KB_1
    var version: String = ""
    var racePace: Double? = nil             // m/s (nil sin referencia: todo en B1 y sin Verheyen)
    var racePaceOrigin: String = ""         // RAZA | CABALLO | SIN_REFERENCIA
    var bands: [KbBand] = []
    var canterMinSpeed: Double? = nil       // m/s
    var gallopCut: Double? = nil            // m/s
    var canterM: Double? = nil
    var gallopM: Double? = nil
    var boneAlgorithm: String = ""
    var bonePct: Double? = nil              // rango validado
    var boneLowPct: Double? = nil           // extrapolado lento (4–12,57 m/s)
    var boneValidMinSpeed: Double? = nil
    var strides: Double? = nil
    var stridesLow: Double? = nil
    var calibrated: Bool? = nil             // false en árabe (parámetros de PSI)
    var boneNote: String = ""
    // CG2 (KB 1.30.0, motor 2.0.0-dev34): carga externa de la sesión en 6 bandas (Morrice-West 2020)
    var cgPresent: Bool = false
    var cgScale: String = ""                // ABSOLUTAS_PSI | RELATIVAS_V_CARRERA
    var cgBands: [KbBand] = []              // LENTO, MEDIO, RAPIDO_1…RAPIDO_4
    var cgFastSpeed: Double? = nil          // m/s desde la que cuenta el trabajo rápido
    var cgFastM: Double? = nil
    var cgNote: String = ""

    init() {}

    init(_ o: [String: Any]?) {
        guard let o = o else { return }
        present = true
        base = KJ.str(o, "base")
        version = KJ.str(o, "version")
        racePace = KbText.finite(KJ.num(o, "v_carrera_m_s"))
        racePaceOrigin = KJ.str(o, "v_carrera_origen")
        var i: Int = 0
        for b in KJ.objs(o, "bandas") {
            guard let b = b else { continue }
            bands.append(KbBand(id: i, code: KJ.str(b, "banda"), vMin: KbText.finite(KJ.num(b, "v_min")), vMax: KbText.finite(KJ.num(b, "v_max")),
                                distanceM: KbText.finite(KJ.num(b, "distancia_m")), timeS: KbText.finite(KJ.num(b, "tiempo_s"))))
            i += 1
        }
        let vh = KJ.obj(o, "verheyen")
        canterMinSpeed = KbText.finite(KJ.num(vh, "canter_v_min"))
        gallopCut = KbText.finite(KJ.num(vh, "corte_galope_m_s"))
        canterM = KbText.finite(KJ.num(vh, "canter_m"))
        gallopM = KbText.finite(KJ.num(vh, "galope_rapido_m"))
        let fo = KJ.obj(o, "fatiga_osea")
        boneAlgorithm = KJ.str(fo, "algoritmo")
        bonePct = KbText.finite(KJ.num(fo, "pct"))
        boneLowPct = KbText.finite(KJ.num(fo, "pct_extrapolado_lento"))
        boneValidMinSpeed = KbText.finite(KJ.num(fo, "v_min_validada"))
        strides = KbText.finite(KJ.num(fo, "zancadas_estimadas"))
        stridesLow = KbText.finite(KJ.num(fo, "zancadas_lentas_estimadas"))
        if let fo = fo, fo["calibrado"] is NSNumber { calibrated = KJ.bool(fo, "calibrado") }
        boneNote = KJ.str(fo, "nota")
        if let cg = KJ.obj(o, "carga_externa") {
            cgPresent = true
            cgScale = KJ.str(cg, "escala")
            var k: Int = 0
            for b in KJ.objs(cg, "bandas") {
                guard let b = b else { continue }
                cgBands.append(KbBand(id: k, code: KJ.str(b, "banda"), vMin: KbText.finite(KJ.num(b, "v_min")), vMax: KbText.finite(KJ.num(b, "v_max")),
                                      distanceM: KbText.finite(KJ.num(b, "distancia_m")), timeS: KbText.finite(KJ.num(b, "tiempo_s"))))
                k += 1
            }
            cgFastSpeed = KbText.finite(KJ.num(cg, "v_rapido_m_s"))
            cgFastM = KbText.finite(KJ.num(cg, "rapido_m"))
            cgNote = KJ.str(cg, "nota")
        }
    }

    func band(_ code: String) -> KbBand? { bands.first { $0.code == code } }
    var hasRacePace: Bool { racePace != nil }

    var racePaceOriginText: String {
        switch racePaceOrigin {
        case "RAZA": return "ritmo de carrera de la raza"
        case "CABALLO": return "ritmo de carrera del caballo"
        case "SIN_REFERENCIA": return "sin ritmo de carrera de referencia"
        default: return racePaceOrigin
        }
    }
}

// ------------------------------------------------------------------ historia

/// Una ventana de la historia («d7», «d30», «d30_anteriores», «d60»).
struct KbWindow: Equatable {
    var present: Bool = false
    var bandsM: [Double?] = [nil, nil, nil]
    var canterM: Double? = nil
    var gallopM: Double? = nil
    var bonePct: Double? = nil
    var sessions: Int = 0
    var sessionsWithoutData: Int = 0

    init() {}

    init(_ o: [String: Any]?) {
        guard let o = o else { return }
        present = true
        let b: [Double] = KJ.doubles(o, "bandas_m")
        bandsM = (0..<3).map { $0 < b.count ? KbText.finite(b[$0]) : nil }
        canterM = KbText.finite(KJ.num(o, "canter_m"))
        gallopM = KbText.finite(KJ.num(o, "galope_rapido_m"))
        bonePct = KbText.finite(KJ.num(o, "fatiga_osea_pct"))
        sessions = KJ.int(KJ.num(o, "sesiones") ?? 0)
        sessionsWithoutData = KJ.int(KJ.num(o, "sesiones_sin_datos") ?? 0)
    }
}

/// Regla activa de la base científica.
struct KbRule: Identifiable, Equatable {
    var id: Int
    var rule: String        // A1_CANTER_30D …
    var level: String       // INFO | VIGILAR
    var action: String      // AVISO | LIMITAR
    var text: String
    var evidence: String

    var title: String { KbRule.title(rule) }
    var code: String { KbRule.code(rule) }
    var isLimit: Bool { action == "LIMITAR" }

    /// Catálogo de reglas del motor (KB-1 1.24.0), en el orden de la ficha 14.
    static let catalogue: [String] = ["A1_CANTER_30D", "A2_GALOPE_30D", "A3_RAMPA", "A5_VUELTA_DESCANSO", "A6_VUELTA_TENDON",
                                      "A6B_POCO_GALOPE_60D", "A6C_COCIENTE_GALOPE", "A7_CAIDA_ZANCADA", "A8_CAIDA_VELOCIDAD_FINAL",
                                      "KB_SIN_RAPIDO_30D", "KB_FATIGA_OSEA_7D"]

    static func code(_ r: String) -> String {
        if r.hasPrefix("KB_FATIGA_OSEA") { return "FO 7 d" }
        if r.hasPrefix("KB_SIN_RAPIDO") { return "SR 30 d" }
        return r.split(separator: "_").first.map(String.init) ?? r
    }

    static func title(_ r: String) -> String {
        switch r {
        case "A1_CANTER_30D": return "Canter acumulado en 30 días"
        case "A2_GALOPE_30D": return "Galope rápido acumulado en 30 días"
        case "A3_RAMPA": return "Subida brusca del trabajo rápido"
        case "A5_VUELTA_DESCANSO": return "Vuelta al trabajo rápido tras descanso"
        case "A6_VUELTA_TENDON": return "Vuelta tras descanso largo (≥ 90 días)"
        case "A6B_POCO_GALOPE_60D": return "Pocos días de galope en 60 días"
        case "A6C_COCIENTE_GALOPE": return "Cociente de galope bajo"
        case "A7_CAIDA_ZANCADA": return "Zancada más corta que su línea base"
        case "A8_CAIDA_VELOCIDAD_FINAL": return "Velocidad final más baja que su línea base"
        case "KB_SIN_RAPIDO_30D": return "Sin trabajo rápido en 30 días"
        case "KB_FATIGA_OSEA_7D": return "Fatiga ósea de 7 días"
        default: return r
        }
    }
}

/// Bloque «base_cientifica» de la historia (estado actual o de cada sesión).
struct KbHistoryStatus: Equatable {
    var present: Bool = false
    var base: String = ""
    var version: String = ""
    var available: Bool = false
    var d7 = KbWindow()
    var d30 = KbWindow()
    var prev30 = KbWindow()
    var d60 = KbWindow()
    var boneWeeklyMedianPct: Double? = nil
    var boneRatio7d: Double? = nil
    var daysWithoutFastWork: Int? = nil
    var gallopDays60d: Int? = nil
    var gallopRatio: Double? = nil
    var gallopRatioDays60: Int? = nil
    var gallopRatioDays90: Int? = nil
    var returnDay: Int? = nil
    var returnRestDays: Int? = nil
    var rules: [KbRule] = []
    var note: String = ""

    init() {}

    init(_ o: [String: Any]?) {
        guard let o = o else { return }
        present = true
        base = KJ.str(o, "base")
        version = KJ.str(o, "version")
        available = KJ.bool(o, "disponible")
        d7 = KbWindow(KJ.obj(o, "d7"))
        d30 = KbWindow(KJ.obj(o, "d30"))
        prev30 = KbWindow(KJ.obj(o, "d30_anteriores"))
        d60 = KbWindow(KJ.obj(o, "d60"))
        boneWeeklyMedianPct = KbText.finite(KJ.num(o, "fatiga_osea_mediana_semanal_pct"))
        boneRatio7d = KbText.finite(KJ.num(o, "fatiga_osea_ratio_7d"))
        daysWithoutFastWork = KJ.num(o, "dias_sin_trabajo_rapido").map { KJ.int($0) }
        gallopDays60d = KJ.num(o, "dias_galope_60d").map { KJ.int($0) }
        if let c = KJ.obj(o, "cociente_galope") {
            gallopRatio = KbText.finite(KJ.num(c, "valor"))
            gallopRatioDays60 = KJ.num(c, "dias_galope_60d").map { KJ.int($0) }
            gallopRatioDays90 = KJ.num(c, "dias_galope_90d").map { KJ.int($0) }
        }
        if let v = KJ.obj(o, "vuelta_descanso") {
            returnDay = KJ.num(v, "dia").map { KJ.int($0) }
            returnRestDays = KJ.num(v, "dias_sin_rapido_antes").map { KJ.int($0) }
        }
        var i: Int = 0
        for r in KJ.objs(o, "reglas") {
            guard let r = r else { continue }
            rules.append(KbRule(id: i, rule: KJ.str(r, "regla"), level: KJ.str(r, "nivel"), action: KJ.str(r, "accion"),
                                text: KJ.str(r, "texto"), evidence: KJ.str(r, "evidencia")))
            i += 1
        }
        note = KJ.str(o, "nota")
    }

    func rule(_ code: String) -> KbRule? { rules.first { $0.rule == code } }
    /// Algo que enseñar: la carga está disponible o hay alguna regla (A7/A8 no dependen de la carga).
    var hasContent: Bool { available || !rules.isEmpty }
}

/// Resumen compacto de la base científica de una sesión dentro de la historia («resumen.trabajo_pista.base_cientifica»).
struct KbSummaryLoad: Equatable {
    var racePace: Double?
    var bandsM: [Double?]
    var canterM: Double?
    var gallopM: Double?
    var bonePct: Double?
    var boneLowPct: Double?

    init?(_ o: [String: Any]?) {
        guard let o = o else { return nil }
        racePace = KbText.finite(KJ.num(o, "v_carrera_m_s"))
        let b: [Double] = KJ.doubles(o, "bandas_m")
        bandsM = (0..<3).map { $0 < b.count ? KbText.finite(b[$0]) : nil }
        canterM = KbText.finite(KJ.num(o, "canter_m"))
        gallopM = KbText.finite(KJ.num(o, "galope_rapido_m"))
        bonePct = KbText.finite(KJ.num(o, "fatiga_osea_pct"))
        boneLowPct = KbText.finite(KJ.num(o, "fatiga_osea_lenta_pct"))
    }
}

// ------------------------------------------------------------------ textos

enum KbText {
    static let noData: String = "sin datos"
    static let boneDisclaimer: String = "Índice relativo, no es una probabilidad de lesión."
    static let uncalibrated: String = "Sin calibrar: fuera del PSI (árabes incluidos) se usan los parámetros de PSI."

    static func finite(_ v: Double?) -> Double? {
        guard let x = v, x.isFinite else { return nil }
        return x
    }

    static func ms(_ v: Double?, _ decimals: Int = 1) -> String {
        guard let x = finite(v) else { return noData }
        return AvoFormat.f(x, decimals) + " m/s"
    }

    static func metres(_ v: Double?) -> String {
        guard let x = finite(v) else { return noData }
        return AvoFormat.f(x, 0) + " m"
    }

    /// Metros por debajo de 10 km; por encima, km con un decimal.
    static func distance(_ v: Double?) -> String {
        guard let x = finite(v) else { return noData }
        return x >= 10_000 ? AvoFormat.f(x / 1000, 1) + " km" : AvoFormat.f(x, 0) + " m"
    }

    static func percent(_ v: Double?, _ decimals: Int = 2) -> String {
        guard let x = finite(v) else { return noData }
        return AvoFormat.f(x, decimals) + " %"
    }

    static func ratio(_ v: Double?, _ decimals: Int = 2) -> String {
        guard let x = finite(v) else { return noData }
        return AvoFormat.f(x, decimals)
    }

    static func days(_ v: Int?) -> String {
        guard let d = v else { return noData }
        return d == 1 ? "1 día" : "\(d) días"
    }

    /// Engine text as a sentence: first letter in capitals and a final full stop.
    static func sentence(_ t: String) -> String {
        guard let first = t.first else { return t }
        var out: String = String(first).uppercased() + String(t.dropFirst())
        if !out.hasSuffix(".") { out += "." }
        return out
    }

    static func range(_ lo: Double?, _ hi: Double?) -> String {
        switch (finite(lo), finite(hi)) {
        case let (l?, h?): return AvoFormat.f(l, 1) + "–" + AvoFormat.f(h, 1) + " m/s"
        case let (l?, nil): return "≥ " + AvoFormat.f(l, 1) + " m/s"
        case let (nil, h?): return "< " + AvoFormat.f(h, 1) + " m/s"
        default: return noData
        }
    }
}
