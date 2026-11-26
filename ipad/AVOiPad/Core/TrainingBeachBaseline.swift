import Foundation

/// Línea base de la playa por franja (motor 2.0.0-dev39, TRAINING 1.5.0, KB-1 1.32.0): bloque «estado.playa» de
/// «avo-training-analysis» con PL2–PL6. Siempre INFO y sin calibrar: no cambia el estado del caballo y no es una
/// predicción de lesiones. Ficha: equine-intelligence/docs/algoritmos/13_TRABAJO_PISTA.md §PL2–PL6. Sin dato = nil.
struct BeachStatValue: Equatable {
    var median: Double?
    var mad: Double?
    var n: Int

    init(_ o: [String: Any]?) {
        median = KbText.finite(EngineJSON.num(o, "mediana"))
        mad = KbText.finite(EngineJSON.num(o, "mad"))
        n = EngineJSON.int(EngineJSON.num(o, "n") ?? 0)
    }
}

struct BeachBandStatus: Identifiable, Equatable {
    var band: String
    var reading: String
    var sessions: Int
    var fastSessions: Int
    var last: String
    var usable: Bool
    var stride: BeachStatValue
    var freq: BeachStatValue
    var v600: BeachStatValue
    var v200: BeachStatValue
    var impactsKm: BeachStatValue
    var soil: BeachStatValue
    var strideAdjusted: Double?
    var strideEffect: Double?
    var freqEffect: Double?
    var id: String { band }

    init(_ o: [String: Any]?) {
        typealias J = EngineJSON
        band = J.str(o, "franja")
        reading = J.str(o, "lectura")
        sessions = J.int(J.num(o, "sesiones") ?? 0)
        fastSessions = J.int(J.num(o, "rapidas") ?? 0)
        last = J.str(o, "ultima")
        usable = J.bool(o, "linea_base_utilizable")
        stride = BeachStatValue(J.obj(o, "zancada_ref_m"))
        freq = BeachStatValue(J.obj(o, "frecuencia_ref_hz"))
        v600 = BeachStatValue(J.obj(o, "v_ultimos_600m_m_s"))
        v200 = BeachStatValue(J.obj(o, "v200_m_s"))
        impactsKm = BeachStatValue(J.obj(o, "impactos_por_km"))
        soil = BeachStatValue(J.obj(o, "humedad_suelo_pct"))
        strideAdjusted = KbText.finite(J.num(o, "zancada_ajustada_m"))
        strideEffect = KbText.finite(J.num(o, "efecto_zancada_m"))
        freqEffect = KbText.finite(J.num(o, "efecto_frecuencia_hz"))
    }

    /// «−0,35 m» frente a la franja de referencia; «sin datos» si la franja no es utilizable.
    var strideEffectText: String {
        guard let e = strideEffect else { return KbText.noData }
        return (e > 0 ? "+" : e < 0 ? "−" : "") + AvoFormat.f(abs(e), 2) + " m"
    }
}

struct BeachMarkStatus: Identifiable, Equatable {
    var date: String
    var sessionId: String
    var rule: String
    var text: String
    var evidence: String
    var id: String { date + sessionId + rule }
}

struct TrainingBeachBaseline: Equatable {
    var present: Bool
    var available: Bool
    var level: String
    var validated: Bool
    var reason: String
    var beachSessions: Int
    var refBand: String
    var slopeStride: Double?
    /// PROPIA | PFAU_2024
    var slopeOrigin: String
    var commonSpeed: Double?
    var bands: [BeachBandStatus]
    var lastBand: String
    var lastSoilClass: String
    var lastImpactsKm: Double?
    var lastImpactsRelative: Double?
    var fastFirm7d: Int
    var marks: [BeachMarkStatus]
    var notes: [String]

    init(_ o: [String: Any]?) {
        typealias J = EngineJSON
        present = o != nil
        available = J.bool(o, "disponible")
        let l = J.str(o, "nivel")
        level = l.isEmpty ? "INFO" : l
        validated = J.bool(o, "validado")
        reason = J.str(o, "motivo")
        beachSessions = J.int(J.num(o, "sesiones_playa") ?? 0)
        refBand = J.str(o, "franja_referencia")
        let p = J.obj(o, "pl3")
        slopeStride = KbText.finite(J.num(p, "pendiente_zancada_m_por_m_s"))
        slopeOrigin = J.str(p, "origen_pendiente")
        commonSpeed = KbText.finite(J.num(p, "velocidad_comun_m_s"))
        bands = J.objs(o, "franjas").map { BeachBandStatus($0) }
        let u = J.obj(o, "ultima_sesion")
        lastBand = J.str(u, "franja")
        lastSoilClass = J.str(u, "clase_humedad")
        lastImpactsKm = KbText.finite(J.num(u, "impactos_por_km"))
        lastImpactsRelative = KbText.finite(J.num(u, "impacto_relativo_franja"))
        fastFirm7d = J.int(J.num(o, "rapidos_orilla_firme_7d") ?? 0)
        marks = J.objs(o, "marcas").map {
            BeachMarkStatus(date: J.str($0, "fecha"), sessionId: J.str($0, "id"), rule: J.str($0, "regla"),
                            text: J.str($0, "texto"), evidence: J.str($0, "evidencia"))
        }
        notes = J.arr(o, "notas").compactMap { $0 as? String }
    }

    static func bandTitle(_ code: String) -> String {
        switch code {
        case "ORILLA_FIRME": return "Orilla firme"
        case "HUMEDA_PROFUNDA": return "Húmeda profunda"
        case "SECA_PROFUNDA": return "Seca profunda"
        case "TRANSICION": return "Transición"
        default: return code
        }
    }

    static func soilTitle(_ code: String) -> String {
        switch code {
        case "SECA": return "Seca (≤ 13 %)"
        case "MEDIA": return "Media (13–19 %)"
        case "HUMEDA": return "Húmeda (> 19 %)"
        default: return KbText.noData
        }
    }

    /// Pendiente de la zancada con su origen: «0,35 m por m/s (propia)» o «0,359 m por m/s (Pfau 2024)».
    var slopeText: String {
        guard let s = slopeStride else { return KbText.noData }
        return AvoFormat.f(s, 3) + " m por m/s" + (slopeOrigin == "PROPIA" ? " (propia)" : " (Pfau 2024)")
    }
}
