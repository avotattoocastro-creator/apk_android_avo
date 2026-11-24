import Foundation

/// CG1–CG3 (motor 2.0.0-dev34, KB-1 1.30.0): carga de entrenamiento descriptiva del bloque «estado.carga_cg» de
/// «avo-training-analysis». Siempre INFO: no cambia el estado y nunca es un riesgo ni un semáforo de lesión.
/// Ficha: equine-intelligence/docs/algoritmos/14_BASE_CIENTIFICA.md §3 quinquies. Los campos sin dato quedan nil.
struct CgSeriesStatus: Equatable {
    var session: Double?
    var total7d: Double?
    var total30d: Double?
    var ewmaAcute: Double?
    var ewmaChronic: Double?
    var ratio: Double?
    var monotony: Double?
    var strain: Double?
    var sessionsWithData: Int
    var sessionsWithoutData: Int
    /// Por qué falta el cociente (historia corta, sesiones sin dato…), vacío si hay cociente.
    var reason: String

    init(_ o: [String: Any]?) {
        typealias J = EngineJSON
        session = KbText.finite(J.num(o, "sesion"))
        total7d = KbText.finite(J.num(o, "total_corto"))
        total30d = KbText.finite(J.num(o, "total_largo"))
        ewmaAcute = KbText.finite(J.num(o, "ewma_aguda"))
        ewmaChronic = KbText.finite(J.num(o, "ewma_cronica"))
        ratio = KbText.finite(J.num(o, "cociente"))
        monotony = KbText.finite(J.num(o, "monotonia"))
        strain = KbText.finite(J.num(o, "strain"))
        sessionsWithData = J.int(J.num(o, "sesiones_con_dato") ?? 0)
        sessionsWithoutData = J.int(J.num(o, "sesiones_sin_dato") ?? 0)
        reason = J.str(o, "motivo")
    }

    var hasData: Bool { total30d != nil || ewmaChronic != nil }
}

struct CgBand: Identifiable, Equatable {
    var name: String
    var vMin: Double?
    var vMax: Double?
    var total7dM: Double?
    var total30dM: Double?
    var id: String { name }

    /// «≥ 16,8 m/s», «13,3–14,4 m/s» (límites de PSI; en árabes se escalan por v_carrera).
    var limitsText: String {
        switch (vMin, vMax) {
        case let (lo?, hi?): return lo <= 0 ? "< \(AvoFormat.f(hi, 1)) m/s" : "\(AvoFormat.f(lo, 1))–\(AvoFormat.f(hi, 1)) m/s"
        case let (lo?, nil): return "≥ \(AvoFormat.f(lo, 1)) m/s"
        default: return KbText.noData
        }
    }
}

struct CgDay: Identifiable, Equatable {
    var date: String
    var fastM: Double?
    var trimp: Double?
    var id: String { date }
}

struct TrainingLoadCg: Equatable {
    var present: Bool
    var available: Bool
    var level: String
    var validated: Bool
    var hrRest: Double?
    var hrRestOrigin: String
    var hrMax: Double?
    /// POR_DEFECTO | CABALLO | PROPIA_HISTORIA
    var hrMaxOrigin: String
    var fastSessionsWithHr: Int
    var internalLoad: CgSeriesStatus
    var externalLoad: CgSeriesStatus
    var scale: String
    var bands: [CgBand]
    var daily: [CgDay]
    var notes: [String]
    var note: String

    init(_ o: [String: Any]?) {
        typealias J = EngineJSON
        present = o != nil
        available = J.bool(o, "disponible")
        let l = J.str(o, "nivel")
        level = l.isEmpty ? "INFO" : l
        validated = J.bool(o, "validado")
        let f = J.obj(o, "fc_referencia")
        hrRest = KbText.finite(J.num(f, "fc_reposo_lpm"))
        hrRestOrigin = J.str(f, "fc_reposo_origen")
        hrMax = KbText.finite(J.num(f, "fc_max_lpm"))
        hrMaxOrigin = J.str(f, "fc_max_origen")
        fastSessionsWithHr = J.int(J.num(f, "trabajos_rapidos_con_fc") ?? 0)
        internalLoad = CgSeriesStatus(J.obj(o, "interna"))
        externalLoad = CgSeriesStatus(J.obj(o, "externa"))
        let b = J.obj(o, "bandas")
        scale = J.str(b, "escala")
        bands = J.objs(b, "bandas").map {
            CgBand(name: J.str($0, "banda"), vMin: KbText.finite(J.num($0, "v_min_psi")), vMax: KbText.finite(J.num($0, "v_max_psi")),
                   total7dM: KbText.finite(J.num($0, "total_corto_m")), total30dM: KbText.finite(J.num($0, "total_largo_m")))
        }
        daily = J.objs(o, "diaria").map {
            CgDay(date: J.str($0, "fecha"), fastM: KbText.finite(J.num($0, "rapido_m")), trimp: KbText.finite(J.num($0, "trimp")))
        }
        notes = J.arr(o, "notas").compactMap { $0 as? String }
        note = J.str(o, "nota")
    }

    /// FC máxima usada en el TRIMP con su origen, p. ej. «225 lpm (propia, 4 trabajos rápidos)».
    var hrMaxText: String {
        guard let m = hrMax else { return KbText.noData }
        switch hrMaxOrigin {
        case "PROPIA_HISTORIA": return "\(AvoFormat.f(m, 0)) lpm (propia, \(fastSessionsWithHr) trabajos rápidos)"
        case "CABALLO": return "\(AvoFormat.f(m, 0)) lpm (anotada)"
        default: return "\(AvoFormat.f(m, 0)) lpm (por defecto, no propia)"
        }
    }

    static func bandTitle(_ name: String) -> String {
        switch name {
        case "LENTO": return "Lento"
        case "MEDIO": return "Medio"
        case "RAPIDO_1": return "Rápido 1"
        case "RAPIDO_2": return "Rápido 2"
        case "RAPIDO_3": return "Rápido 3"
        case "RAPIDO_4": return "Rápido 4"
        default: return name
        }
    }
}
