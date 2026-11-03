import Foundation

/// «trabajo_pista» block of the engine result (AVO Track Work 1.0.0: training of racehorses, PSI / Arabian profiles).
/// Times are ENGINE seconds (GNSS time from the first epoch); the timeline of the app is `engine − engineOffsetS`.
struct TrackWorkPhase: Equatable {
    var present: Bool = false
    var t0: Double = .nan
    var t1: Double = .nan
    var durationS: Double = .nan
    var distanceM: Double = .nan
    var walkS: Double = 0
    var trotS: Double = 0
    var canterS: Double = 0
}

struct TrackWorkEffort: Identifiable, Equatable {
    var id: Int
    var kind: String            // GALOPE_TRABAJO | TRABAJO_RAPIDO | PASADA
    var t0: Double
    var t1: Double
    var durationS: Double
    var distanceM: Double
    var vmax: Double            // m/s
    var speedMean: Double       // m/s
    var fatiguePct: Double
    var last200S: Double
    var recoveryS: Double
    var manual: Bool
    var sectionals: [Double]    // seconds per split

    var kindText: String {
        switch kind {
        case "TRABAJO_RAPIDO": return "Trabajo rápido"
        case "GALOPE_TRABAJO": return "Galope de trabajo"
        case "PASADA": return "Pasada"
        default: return kind
        }
    }
}

struct TrackWorkResult: Equatable {
    var present: Bool = false
    var breed: String = ""
    var phaseBasis: String = ""          // VELOCIDAD | LINEAS | MANUAL
    var manualCorrections: Bool = false
    var warmup = TrackWorkPhase()
    var work = TrackWorkPhase()
    var cooldown = TrackWorkPhase()
    var efforts: [TrackWorkEffort] = []
    var passes: [TrackWorkEffort] = []
    var courseDefined: Bool = false
    var bestPassS: Double = .nan
    var reps: Int = 0
    var fastReps: Int = 0
    var vmaxDropPct: Double = .nan
    var recoveryMeanS: Double = .nan
    var warmupShort: Bool = false
    var warnings: [String] = []

    var phaseBasisText: String {
        switch phaseBasis {
        case "LINEAS": return "por líneas de salida y meta"
        case "MANUAL": return "corregidas a mano"
        case "VELOCIDAD": return "automáticas (velocidad RTK y cincha)"
        default: return phaseBasis
        }
    }

    static func parse(_ o: [String: Any]?) -> TrackWorkResult {
        typealias J = EngineJSON
        var r = TrackWorkResult()
        guard let o = o else { return r }
        r.present = true
        r.breed = J.str(J.obj(o, "perfil"), "raza")
        r.manualCorrections = J.bool(o, "correcciones_manuales")
        let fa = J.obj(o, "fases")
        r.phaseBasis = J.str(fa, "base")
        r.warmup = phase(J.obj(fa, "calentamiento"))
        r.work = phase(J.obj(fa, "trabajo"))
        r.cooldown = phase(J.obj(fa, "vuelta_a_la_calma"))
        r.efforts = J.objs(J.obj(o, "trabajos"), "lista").compactMap { effort($0) }
        let co = J.obj(o, "recorrido")
        r.courseDefined = co != nil
        r.passes = J.objs(co, "pasadas").compactMap { effort($0) }
        r.bestPassS = J.num(co, "mejor_pasada_s") ?? .nan
        let se = J.obj(o, "series")
        r.reps = J.int(J.num(se, "repeticiones") ?? 0)
        r.fastReps = J.int(J.num(se, "rapidas") ?? 0)
        r.vmaxDropPct = J.num(se, "caida_v_max_pct") ?? .nan
        r.recoveryMeanS = J.num(se, "recuperacion_media_s") ?? .nan
        r.warmupShort = J.bool(se, "calentamiento_corto")
        r.warnings = J.arr(o, "avisos").compactMap { $0 as? String }
        return r
    }

    private static func phase(_ p: [String: Any]?) -> TrackWorkPhase {
        typealias J = EngineJSON
        guard let p = p else { return TrackWorkPhase() }
        return TrackWorkPhase(present: true, t0: J.num(p, "t0") ?? .nan, t1: J.num(p, "t1") ?? .nan,
                              durationS: J.num(p, "duracion_s") ?? .nan, distanceM: J.num(p, "distancia_m") ?? .nan,
                              walkS: J.num(p, "paso_s") ?? 0, trotS: J.num(p, "trote_s") ?? 0, canterS: J.num(p, "galope_s") ?? 0)
    }

    private static func effort(_ e: [String: Any]?) -> TrackWorkEffort? {
        typealias J = EngineJSON
        guard let e = e, let t0 = J.num(e, "t0"), let t1 = J.num(e, "t1") else { return nil }
        let splits: [Double] = J.objs(e, "parciales").map { J.num($0, "tiempo_s") ?? .nan }
        return TrackWorkEffort(id: J.int(J.num(e, "id") ?? 0), kind: J.str(e, "tipo"), t0: t0, t1: t1,
                               durationS: J.num(e, "duracion_s") ?? .nan, distanceM: J.num(e, "distancia_m") ?? .nan,
                               vmax: J.num(e, "v_max") ?? .nan, speedMean: J.num(e, "v_media") ?? .nan,
                               fatiguePct: J.num(e, "indice_caida_pct") ?? .nan, last200S: J.num(e, "ultimos_200m_s") ?? .nan,
                               recoveryS: J.num(e, "recuperacion_hasta_paso_s") ?? .nan, manual: J.bool(e, "manual"),
                               sectionals: splits)
    }
}

/// Corrections made by the user to ONE training (stored in correcciones.json; the recorded data is never modified).
/// Times are absolute GPS time (iTOW, ms) so they do not depend on how the app or the engine count seconds.
struct TrainingLine: Codable, Equatable {
    var aLat: Double
    var aLon: Double
    var bLat: Double
    var bLon: Double
    /// AMBOS | IZQ_A_DCHA | DCHA_A_IZQ (seen from A towards B, as in geocercas.json)
    var direction: String
}

struct TrainingCorrection: Codable, Equatable {
    var works: [[Double]]? = nil          // [[itow0, itow1]] — nil = automatic detection
    var workStartItow: Double? = nil
    var workEndItow: Double? = nil
    var start: TrainingLine? = nil
    var finish: TrainingLine? = nil

    var isEmpty: Bool { works == nil && workStartItow == nil && workEndItow == nil && start == nil && finish == nil }

    /// Engine options (avo_eq_analyse_ex) for these corrections, without the surrounding braces.
    func optionsFragment() -> String {
        var parts: [String] = []
        if let w = works {
            let items: [String] = w.filter { $0.count == 2 }.map { "{\"itow0_ms\":\(Int64($0[0])),\"itow1_ms\":\(Int64($0[1]))}" }
            parts.append("\"trabajos_manuales\":[" + items.joined(separator: ",") + "]")
        }
        if workStartItow != nil || workEndItow != nil {
            var f: [String] = []
            if let a = workStartItow { f.append("\"inicio_trabajo_itow_ms\":\(Int64(a))") }
            if let b = workEndItow { f.append("\"fin_trabajo_itow_ms\":\(Int64(b))") }
            parts.append("\"fases_manuales\":{" + f.joined(separator: ",") + "}")
        }
        if start != nil || finish != nil {
            func line(_ l: TrainingLine) -> String {
                "{\"a\":[\(l.aLat),\(l.aLon)],\"b\":[\(l.bLat),\(l.bLon)],\"sentido\":\(AvoJSON.quote(l.direction))}"
            }
            var c: [String] = []
            if let s = start { c.append("\"salida\":" + line(s)) }
            if let f = finish { c.append("\"meta\":" + line(f)) }
            parts.append("\"recorrido\":{" + c.joined(separator: ",") + "}")
        }
        return parts.joined(separator: ",")
    }
}

/// Breed profile of the engine from the free text of the Cuadra («PSI», «Pura sangre inglés», «Árabe», «PRá»…).
enum TrackWorkBreed {
    static func engineName(_ breedText: String) -> String {
        let t = breedText.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES")).lowercased()
        if t.isEmpty { return "GENERICO" }
        if t.contains("trot") || t.contains("standardbred") || t.contains("cuarto de milla") || t.contains("quarter") { return "GENERICO" }
        if t.contains("psi") || t.contains("ingl") || t.contains("thoroughbred") || t.contains("english") || t.contains("aqps")
            || t.contains("pur-sang") { return "PSI" }
        if t.contains("arab") || t.contains("pra") { return "ARABE" }
        return "GENERICO"
    }
}


/// Turf racing breeds offered in the horse card (value stored as the text of «Breed», compatible with Android/Windows).
struct RacingBreed: Identifiable, Hashable {
    let label: String
    let group: String
    var id: String { label }
    var engineProfile: String { TrackWorkBreed.engineName(label) }

    static let all: [RacingBreed] = [
        RacingBreed(label: "Pura Sangre Inglés (PSI)", group: "Galope"),
        RacingBreed(label: "AQPS (Autre Que Pur-Sang)", group: "Galope"),
        RacingBreed(label: "Pura Sangre Árabe (PSA)", group: "Galope"),
        RacingBreed(label: "Anglo-Árabe (AA)", group: "Galope"),
        RacingBreed(label: "Cuarto de Milla de carreras", group: "Galope"),
        RacingBreed(label: "Trotón Francés", group: "Trote"),
        RacingBreed(label: "Standardbred (trotón americano)", group: "Trote"),
        RacingBreed(label: "Trotón escandinavo / sueco", group: "Trote"),
        RacingBreed(label: "Otra", group: "Otras"),
    ]
    static let groups: [String] = ["Galope", "Trote", "Otras"]

    /// Short explanation of the analysis profile the engine will use for this breed text.
    static func profileText(_ breedText: String) -> String {
        let t = breedText.lowercased()
        if t.contains("trot") || t.contains("standardbred") {
            return "Perfil genérico: el análisis de galope de trabajo no aplica a carreras al trote."
        }
        switch TrackWorkBreed.engineName(breedText) {
        case "PSI": return "Perfil PSI: galope de trabajo ≥ 11 m/s, trabajo rápido ≥ 14,5 m/s, alta velocidad > 15 m/s."
        case "ARABE": return "Perfil árabe: galope de trabajo ≥ 10 m/s, trabajo rápido ≥ 13 m/s, alta velocidad > 13,5 m/s."
        default: return breedText.trimmingCharacters(in: .whitespaces).isEmpty
            ? "Sin raza: se usa el perfil genérico (galope de trabajo ≥ 9 m/s)."
            : "Perfil genérico: galope de trabajo ≥ 9 m/s, trabajo rápido ≥ 12 m/s."
        }
    }
}
