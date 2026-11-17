import Foundation

// AVO Training Analytics 1.0.0 (equine-intelligence/docs/algoritmos/12_ENTRENAMIENTO.md): models of the JSON formats
// «avo-training-session» (summary of one session) and «avo-training-analysis» (history of one horse), the trainer's
// rating (valoraciones.json) and the helpers that build the JSON passed to the engine. Decoding is tolerant: unknown keys
// are ignored and missing keys, nulls or wrong types become nil. Orientative, never a veterinary diagnosis.

// ------------------------------------------------------------------ trainer rating (valoraciones.json)

/// Track of the session («pista»: superficie + estado).
struct TrainingTrack: Codable, Equatable {
    var superficie: String?
    var estado: String?

    var isEmpty: Bool { (superficie ?? "").trimmed.isEmpty && (estado ?? "").trimmed.isEmpty }
}

/// Trainer's rating of one session (same keys as the engine: rpe 1–10, estado BIEN|CANSADO|RARO|COJERA, nota, pista).
struct TrainingRating: Codable, Equatable {
    var rpe: Int?
    var estado: String?
    var nota: String?
    var pista: TrainingTrack?
    var actualizado_utc: String?

    enum CodingKeys: String, CodingKey {
        case rpe, estado, nota, pista, actualizado_utc
    }

    static let states: [String] = ["BIEN", "CANSADO", "RARO", "COJERA"]
    static let surfaces: [String] = ["arena", "hierba", "playa", "pista fibra", "tierra", "arena mojada"]
    static let trackStates: [String] = ["blanda", "buena", "dura"]

    init(rpe: Int? = nil, estado: String? = nil, nota: String? = nil, pista: TrainingTrack? = nil, actualizado_utc: String? = nil) {
        self.rpe = rpe
        self.estado = estado
        self.nota = nota
        self.pista = pista
        self.actualizado_utc = actualizado_utc
    }

    /// Tolerant decoding: a wrong type in one key never discards the whole rating.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let i = try? c.decodeIfPresent(Int.self, forKey: .rpe) { rpe = i }
        else if let d = try? c.decodeIfPresent(Double.self, forKey: .rpe) { rpe = d.isFinite ? Int(d.rounded()) : nil }
        else { rpe = nil }
        estado = (try? c.decodeIfPresent(String.self, forKey: .estado)) ?? nil
        nota = (try? c.decodeIfPresent(String.self, forKey: .nota)) ?? nil
        pista = (try? c.decodeIfPresent(TrainingTrack.self, forKey: .pista)) ?? nil
        actualizado_utc = (try? c.decodeIfPresent(String.self, forKey: .actualizado_utc)) ?? nil
    }

    var isEmpty: Bool {
        rpe == nil && (estado ?? "").trimmed.isEmpty && (nota ?? "").trimmed.isEmpty && (pista?.isEmpty ?? true)
    }

    /// {"rpe","estado","nota"} for the engine (only the keys that are set; RPE outside 1–10 is not sent).
    var valoracionObject: [String: Any]? {
        var o: [String: Any] = [:]
        if let r = rpe, r >= 1 && r <= 10 { o["rpe"] = r }
        if let e = estado?.trimmed, !e.isEmpty { o["estado"] = e }
        if let n = nota?.trimmed, !n.isEmpty { o["nota"] = n }
        return o.isEmpty ? nil : o
    }

    var pistaObject: [String: Any]? {
        var o: [String: Any] = [:]
        if let s = pista?.superficie?.trimmed, !s.isEmpty { o["superficie"] = s }
        if let e = pista?.estado?.trimmed, !e.isEmpty { o["estado"] = e }
        return o.isEmpty ? nil : o
    }
}

/// paths.root/valoraciones.json: {"<session id>": TrainingRating}.
enum TrainingRatingStore {
    static func load(_ path: String) -> [String: TrainingRating] {
        guard let data = AvoFiles.read(path) else { return [:] }
        var d: Data = data
        if d.starts(with: [0xEF, 0xBB, 0xBF]) { d = Data(d.dropFirst(3)) }
        if let all = try? JSONDecoder().decode([String: TrainingRating].self, from: d) { return all }
        // one damaged entry must not lose the others
        guard let o = AvoJSON.object(d) else { return [:] }
        var out: [String: TrainingRating] = [:]
        for (k, v) in o {
            guard (v is [String: Any]), JSONSerialization.isValidJSONObject(v),
                  let vd = try? JSONSerialization.data(withJSONObject: v, options: []),
                  let r = try? JSONDecoder().decode(TrainingRating.self, from: vd) else { continue }
            out[k] = r
        }
        return out
    }

    static func save(_ all: [String: TrainingRating], to path: String) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try AvoFiles.writeAtomic(try enc.encode(all), to: path)
    }
}

// ------------------------------------------------------------------ JSON for the engine

enum TrainingAnalytics {
    static let summaryFileName: String = "training_summary.json"

    /// extra_json of avo_eq_training_summary (and the same fields of each entry of avo_eq_training_analyse).
    static func extraObject(id: String, horse: String, rider: String, dateUtc: String?, rating: TrainingRating?) -> [String: Any] {
        var o: [String: Any] = ["id": id, "caballo": horse, "jinete": rider]
        if let d = dateUtc, !d.isEmpty { o["fecha_utc"] = d }
        if let r = rating {
            if let v = r.valoracionObject { o["valoracion"] = v }
            if let p = r.pistaObject { o["pista"] = p }
        }
        return o
    }

    static func extraJson(id: String, horse: String, rider: String, dateUtc: String?, rating: TrainingRating?) -> String {
        String(decoding: AvoJSON.data(extraObject(id: id, horse: horse, rider: rider, dateUtc: dateUtc, rating: rating)), as: UTF8.self)
    }

    /// One session of the history: the stored summary plus the current identity, date and rating (they win over the file).
    struct HistoryEntry {
        var id: String
        var summaryPath: String
        var horse: String
        var rider: String
        var dateUtc: String?
        var rating: TrainingRating?
    }

    /// input_json of avo_eq_training_analyse. Entries whose summary cannot be read are skipped (returned in `missing`).
    static func historyInput(horse: String, reference: String?, entries: [HistoryEntry]) -> (json: String, used: Int, missing: [String]) {
        var list: [Any] = []
        var missing: [String] = []
        for e in entries {
            guard let data = AvoFiles.read(e.summaryPath), let summary = AvoJSON.object(data),
                  (summary["formato"] as? String) == "avo-training-session" else {
                missing.append(e.id)
                continue
            }
            var o: [String: Any] = extraObject(id: e.id, horse: horse, rider: e.rider, dateUtc: e.dateUtc, rating: e.rating)
            o["resumen"] = summary
            list.append(o)
        }
        var root: [String: Any] = ["caballo": horse, "sesiones": list]
        if let r = reference, !r.isEmpty { root["fecha_referencia"] = r }
        return (String(decoding: AvoJSON.data(root), as: UTF8.self), list.count, missing)
    }

    /// "AAAA-MM-DD" of a date in UTC (the engine works with UTC days).
    static func dayText(_ d: Date, utc: Bool = true) -> String {
        AvoTime.formatter("yyyy-MM-dd", utc: utc).string(from: d)
    }

    /// Date of an "AAAA-MM-DD…" text (UTC midnight).
    static func day(_ s: String) -> Date? {
        if s.count < 10 { return nil }
        return AvoTime.formatter("yyyy-MM-dd", utc: true).date(from: String(s.prefix(10)))
    }

    // ---------------------------------------------------------------- metric names and directions
    static let gaits: [String] = ["PASO", "TROTE", "GALOPE"]
    static let metricKeys: [String] = ["velocidad_media", "longitud_tranco_m", "cadencia_hz", "correlacion_ciclos", "cv_intervalos"]

    static func gaitLabel(_ g: String) -> String {
        switch g {
        case "PASO": return "Paso"
        case "TROTE": return "Trote"
        case "GALOPE": return "Galope"
        case "TRABAJO": return "Trabajo en pista"
        case "CINCHA": return "Cincha"
        case "RECORRIDO": return "Recorrido"
        default: return g
        }
    }

    /// Prefixes of the AVO Track Work metrics of the history (docs/algoritmos/13_TRABAJO_PISTA.md).
    static let trackWorkPrefixes: [String] = ["TRABAJO", "CINCHA", "RECORRIDO"]

    /// True for the AVO Track Work metrics (TRABAJO.*, CINCHA.*, RECORRIDO.* and the VeDBA load).
    static func isTrackWorkMetric(_ metric: String) -> Bool {
        if metric == "carga_vedba" { return true }
        return trackWorkPrefixes.contains(split(metric).gait)
    }

    static func metricLabel(_ key: String) -> String {
        switch key {
        case "velocidad_media": return "Velocidad media"
        case "longitud_tranco_m": return "Tranco"
        case "cadencia_hz": return "Cadencia"
        case "correlacion_ciclos": return "Correlación entre ciclos"
        case "cv_intervalos": return "CV de intervalos"
        case "carga_externa": return "Carga externa"
        case "distancia_m": return "Distancia"
        // AVO Track Work
        case "f_v1_hz": return "Frecuencia de zancada a v. ref. 1"
        case "l_v1_m": return "Longitud de zancada a v. ref. 1"
        case "f_v2_hz": return "Frecuencia de zancada a v. ref. 2"
        case "l_v2_m": return "Longitud de zancada a v. ref. 2"
        case "mano_de_fuera_curva_pct": return "Mano de fuera en curva"
        case "indice_caida_pct": return "Índice de caída"
        case "v_max": return "Velocidad máxima"
        case "mejor_200m_s": return "Mejor 200 m"
        case "f_en_v_max_hz": return "Frecuencia a la máxima"
        case "l_en_v_max_m": return "Longitud a la máxima"
        case "desplazamiento_vertical_m": return "Desplazamiento vertical"
        case "vedba_galope_g": return "VeDBA en galope"
        case "recuperacion_hasta_paso_s": return "Recuperación hasta el paso"
        case "caida_entre_series_pct": return "Caída entre series"
        case "calentamiento_s": return "Calentamiento"
        case "mejor_pasada_s": return "Mejor pasada"
        case "v_media_mejor": return "Velocidad media de la mejor pasada"
        case "carga_vedba": return "Carga VeDBA"
        default: return key
        }
    }

    /// "TROTE.longitud_tranco_m" → ("TROTE", "longitud_tranco_m"); "carga_externa" → ("", "carga_externa").
    static func split(_ metric: String) -> (gait: String, key: String) {
        guard let dot = metric.firstIndex(of: ".") else { return ("", metric) }
        return (String(metric[metric.startIndex..<dot]), String(metric[metric.index(after: dot)...]))
    }

    static func fullLabel(_ metric: String) -> String {
        let p = split(metric)
        return p.gait.isEmpty ? metricLabel(p.key) : "\(gaitLabel(p.gait)) · \(metricLabel(p.key))"
    }

    /// Direction that raises the level: 0 both, +1 higher is worse, -1 lower is worse, nil informative (speed).
    static func worseDirection(_ key: String) -> Int? {
        switch key {
        case "longitud_tranco_m", "cadencia_hz": return 0
        case "correlacion_ciclos": return -1
        case "cv_intervalos": return 1
        // AVO Track Work: stride at the reference speed (length only when it drops) and outside lead in curves
        case "f_v1_hz", "f_v2_hz": return 0
        case "l_v1_m", "l_v2_m": return -1
        case "mano_de_fuera_curva_pct": return 1
        default: return nil
        }
    }

    /// Value in display units (speed km/h, cadence /min).
    static func format(_ key: String, _ v: Double?) -> String {
        guard let x = v, x.isFinite else { return "—" }
        switch key {
        case "velocidad_media": return AvoFormat.f(x * 3.6, 1) + " km/h"
        case "longitud_tranco_m": return AvoFormat.f(x, 2) + " m"
        case "cadencia_hz": return AvoFormat.f(x * 60, 1) + " /min"
        case "correlacion_ciclos": return AvoFormat.f(x, 3)
        case "cv_intervalos": return AvoFormat.f(x, 3)
        case "carga_externa": return AvoFormat.f(x, 0)
        case "distancia_m": return AvoFormat.f(x, 0) + " m"
        case "f_v1_hz", "f_v2_hz", "f_en_v_max_hz": return AvoFormat.f(x, 2) + " Hz"
        case "l_v1_m", "l_v2_m", "l_en_v_max_m": return AvoFormat.f(x, 2) + " m"
        case "desplazamiento_vertical_m": return AvoFormat.f(x, 3) + " m"
        case "mano_de_fuera_curva_pct", "indice_caida_pct", "caida_entre_series_pct": return AvoFormat.f(x, 1) + " %"
        case "v_max", "v_media_mejor": return AvoFormat.f(x * 3.6, 1) + " km/h"
        case "mejor_200m_s", "mejor_pasada_s": return AvoFormat.f(x, 2) + " s"
        case "recuperacion_hasta_paso_s": return AvoFormat.f(x, 0) + " s"
        case "calentamiento_s": return AvoFormat.f(x / 60, 1) + " min"
        case "vedba_galope_g": return AvoFormat.f(x, 3) + " g"
        case "carga_vedba": return AvoFormat.f(x, 2) + " g·min"
        default: return AvoFormat.f(x, 2)
        }
    }

    /// Slope per week in display units.
    static func formatSlope(_ key: String, _ v: Double?) -> String {
        guard let x = v, x.isFinite else { return "—" }
        let sign: String = x > 0 ? "+" : ""
        switch key {
        case "velocidad_media": return sign + AvoFormat.f(x * 3.6, 2) + " km/h/sem"
        case "longitud_tranco_m": return sign + AvoFormat.f(x, 3) + " m/sem"
        case "cadencia_hz": return sign + AvoFormat.f(x * 60, 2) + " /min/sem"
        case "carga_externa": return sign + AvoFormat.f(x, 1) + "/sem"
        case "distancia_m": return sign + AvoFormat.f(x, 0) + " m/sem"
        case "v_max", "v_media_mejor": return sign + AvoFormat.f(x * 3.6, 2) + " km/h/sem"
        case "mejor_200m_s", "mejor_pasada_s", "recuperacion_hasta_paso_s": return sign + AvoFormat.f(x, 2) + " s/sem"
        case "mano_de_fuera_curva_pct", "indice_caida_pct", "caida_entre_series_pct": return sign + AvoFormat.f(x, 2) + " %/sem"
        case "calentamiento_s": return sign + AvoFormat.f(x / 60, 2) + " min/sem"
        case "carga_vedba": return sign + AvoFormat.f(x, 2) + " g·min/sem"
        default: return sign + AvoFormat.f(x, 4) + "/sem"
        }
    }
}

// ------------------------------------------------------------------ «avo-training-session»

private typealias TJ = EngineJSON

struct TrainingGaitSummary: Equatable {
    var duracionS: Double?
    var distanciaM: Double?
    var velocidadMedia: Double?
    var velocidadMax: Double?
    var longitudTrancoM: Double?
    var cadenciaHz: Double?
    var correlacionCiclos: Double?
    var cvIntervalos: Double?

    init(_ o: [String: Any]?) {
        duracionS = TJ.num(o, "duracion_s")
        distanciaM = TJ.num(o, "distancia_m")
        velocidadMedia = TJ.num(o, "velocidad_media")
        velocidadMax = TJ.num(o, "velocidad_max")
        longitudTrancoM = TJ.num(o, "longitud_tranco_m")
        cadenciaHz = TJ.num(o, "cadencia_hz")
        correlacionCiclos = TJ.num(o, "correlacion_ciclos")
        cvIntervalos = TJ.num(o, "cv_intervalos")
    }

    var minutes: Double { (duracionS ?? 0) / 60 }

    func value(_ key: String) -> Double? {
        switch key {
        case "velocidad_media": return velocidadMedia
        case "longitud_tranco_m": return longitudTrancoM
        case "cadencia_hz": return cadenciaHz
        case "correlacion_ciclos": return correlacionCiclos
        case "cv_intervalos": return cvIntervalos
        default: return nil
        }
    }
}

struct TrainingSessionSummary: Equatable {
    var formato: String
    var version: String
    var id: String
    var caballo: String
    var jinete: String
    var fechaUtc: String?
    var tiempoMovimientoS: Double?
    var distanciaM: Double?
    var velocidadMax: Double?
    var distanciaAltaVelocidadM: Double?
    var tieneCincha: Bool?
    var paso: TrainingGaitSummary
    var trote: TrainingGaitSummary
    var galope: TrainingGaitSummary
    var aceleracionesSostenidas: Int?
    var frenadasSostenidas: Int?
    var picosLaterales: Int?
    var picoAceleracion: Double?
    var picoFrenada: Double?
    var calidadGnss: String?
    var calidadImu: String?
    var rpe: Double?
    var estado: String?
    var nota: String?
    var superficie: String?
    var estadoPista: String?
    var avisos: [String]
    /// «trabajo_pista» of the summary (AVO Track Work), nil for sessions analysed without it.
    var trabajoPista: TrainingTrackWorkSummary?

    static func parse(_ json: String) throws -> TrainingSessionSummary {
        let r = try TJ.root(json)
        if let err = r["error"] { throw AvoError.invalidData((err as? String) ?? "") }
        guard let s = TrainingSessionSummary(r) else { throw AvoError.invalidData("no es un resumen avo-training-session") }
        return s
    }

    init?(_ o: [String: Any]?) {
        guard let o = o, TJ.str(o, "formato") == "avo-training-session" else { return nil }
        formato = TJ.str(o, "formato")
        version = TJ.str(o, "version")
        id = TJ.str(o, "id")
        caballo = TJ.str(o, "caballo")
        jinete = TJ.str(o, "jinete")
        let f: String = TJ.str(o, "fecha_utc")
        fechaUtc = f.isEmpty ? nil : f
        tiempoMovimientoS = TJ.num(o, "tiempo_movimiento_s")
        distanciaM = TJ.num(o, "distancia_m")
        velocidadMax = TJ.num(o, "velocidad_max")
        distanciaAltaVelocidadM = TJ.num(o, "distancia_alta_velocidad_m")
        tieneCincha = AvoJSON.bool(o, "tiene_cincha")
        let a = TJ.obj(o, "aires")
        paso = TrainingGaitSummary(TJ.obj(a, "PASO"))
        trote = TrainingGaitSummary(TJ.obj(a, "TROTE"))
        galope = TrainingGaitSummary(TJ.obj(a, "GALOPE"))
        let ac = TJ.obj(o, "aceleraciones")
        aceleracionesSostenidas = TJ.num(ac, "sostenidas").map { TJ.int($0) }
        frenadasSostenidas = TJ.num(ac, "frenadas_sostenidas").map { TJ.int($0) }
        picosLaterales = TJ.num(ac, "picos_laterales").map { TJ.int($0) }
        picoAceleracion = TJ.num(ac, "pico_aceleracion_m_s2")
        picoFrenada = TJ.num(ac, "pico_frenada_m_s2")
        let q = TJ.obj(o, "calidad")
        calidadGnss = TrainingSessionSummary.opt(TJ.str(q, "gnss"))
        calidadImu = TrainingSessionSummary.opt(TJ.str(q, "imu"))
        let v = TJ.obj(o, "valoracion")
        rpe = TJ.num(v, "rpe")
        estado = TrainingSessionSummary.opt(TJ.str(v, "estado"))
        nota = TrainingSessionSummary.opt(TJ.str(v, "nota"))
        let p = TJ.obj(o, "pista")
        superficie = TrainingSessionSummary.opt(TJ.str(p, "superficie"))
        estadoPista = TrainingSessionSummary.opt(TJ.str(p, "estado"))
        avisos = TJ.arr(o, "avisos").compactMap { $0 as? String }
        trabajoPista = TrainingTrackWorkSummary(TJ.obj(o, "trabajo_pista"))
    }

    private static func opt(_ s: String) -> String? { s.isEmpty ? nil : s }

    func gait(_ g: String) -> TrainingGaitSummary {
        switch g {
        case "PASO": return paso
        case "TROTE": return trote
        default: return galope
        }
    }
}

/// «trabajo_pista» of one session summary (AVO Track Work): what the history uses (best pass, fatigue, recovery, VeDBA).
struct TrainingTrackWorkSummary: Equatable {
    var raza: String
    var cargaVedbaGmin: Double?
    var vedbaGalopeG: Double?
    var galopeGirandoIzquierdaS: Double?
    var galopeGirandoDerechaS: Double?
    var manoCalibracion: String
    var manoIzquierda: Int
    var manoDerecha: Int
    var manoCambios: Int
    var manoDeFueraCurvaPct: Double?
    var trabajos: Int
    var trabajosRapidos: Int
    var vMax: Double?
    var mejor200S: Double?
    var distanciaRapidaM: Double?
    var distanciaGalopeTrabajoM: Double?
    var indiceCaidaPct: Double?
    var fEnVMaxHz: Double?
    var lEnVMaxM: Double?
    var desplazamientoVerticalM: Double?
    var impactosAtipicos: Int
    var lateralesBruscos: Int
    var saturacion: Int
    var calentamientoS: Double?
    var vueltaCalmaS: Double?
    var repeticiones: Int
    var rapidas: Int
    var caidaVMaxPct: Double?
    var caidaZancadaPct: Double?
    var recuperacionMediaS: Double?
    var calentamientoCorto: Bool
    var recorrido: String
    var pasadas: Int
    var mejorPasadaS: Double?
    var vMediaMejor: Double?
    var indiceCaidaMejorPct: Double?

    init?(_ o: [String: Any]?) {
        guard let o = o else { return nil }
        raza = TJ.str(o, "raza")
        cargaVedbaGmin = TJ.num(o, "carga_vedba_g_min")
        vedbaGalopeG = TJ.num(o, "vedba_galope_g")
        galopeGirandoIzquierdaS = TJ.num(o, "galope_girando_izquierda_s")
        galopeGirandoDerechaS = TJ.num(o, "galope_girando_derecha_s")
        let m = TJ.obj(o, "mano")
        manoCalibracion = TJ.str(m, "calibracion")
        manoIzquierda = TJ.int(TJ.num(m, "izquierda") ?? 0)
        manoDerecha = TJ.int(TJ.num(m, "derecha") ?? 0)
        manoCambios = TJ.int(TJ.num(m, "cambios") ?? 0)
        manoDeFueraCurvaPct = TJ.num(m, "mano_de_fuera_en_curva_pct")
        trabajos = TJ.int(TJ.num(o, "trabajos") ?? 0)
        trabajosRapidos = TJ.int(TJ.num(o, "trabajos_rapidos") ?? 0)
        vMax = TJ.num(o, "v_max")
        mejor200S = TJ.num(o, "mejor_200m_s")
        distanciaRapidaM = TJ.num(o, "distancia_rapida_m")
        distanciaGalopeTrabajoM = TJ.num(o, "distancia_galope_trabajo_m")
        indiceCaidaPct = TJ.num(o, "indice_caida_pct")
        fEnVMaxHz = TJ.num(o, "f_en_v_max_hz")
        lEnVMaxM = TJ.num(o, "l_en_v_max_m")
        desplazamientoVerticalM = TJ.num(o, "desplazamiento_vertical_m")
        let ev = TJ.obj(o, "eventos")
        impactosAtipicos = TJ.int(TJ.num(ev, "impactos_atipicos") ?? 0)
        lateralesBruscos = TJ.int(TJ.num(ev, "laterales_bruscos") ?? 0)
        saturacion = TJ.int(TJ.num(ev, "saturacion") ?? 0)
        let se = TJ.obj(o, "sesion")
        calentamientoS = TJ.num(se, "calentamiento_s")
        vueltaCalmaS = TJ.num(se, "vuelta_a_la_calma_s")
        repeticiones = TJ.int(TJ.num(se, "repeticiones") ?? 0)
        rapidas = TJ.int(TJ.num(se, "rapidas") ?? 0)
        caidaVMaxPct = TJ.num(se, "caida_v_max_pct")
        caidaZancadaPct = TJ.num(se, "caida_zancada_pct")
        recuperacionMediaS = TJ.num(se, "recuperacion_media_s")
        calentamientoCorto = TJ.bool(se, "calentamiento_corto")
        let rc = TJ.obj(o, "recorrido")
        recorrido = TJ.str(rc, "nombre")
        pasadas = TJ.int(TJ.num(rc, "pasadas") ?? 0)
        mejorPasadaS = TJ.num(rc, "mejor_pasada_s")
        vMediaMejor = TJ.num(rc, "v_media_mejor")
        indiceCaidaMejorPct = TJ.num(rc, "indice_caida_mejor_pct")
    }
}

// ------------------------------------------------------------------ «avo-training-analysis»

struct TrainingLoad: Equatable {
    var externa: Double?
    var srpe: Double?
    var aguda: Double?
    var cronicaSemanal: Double?
    var acwr: Double?
    var agudaSrpe: Double?
    var cronicaSemanalSrpe: Double?
    var acwrSrpe: Double?
    var monotonia: Double?
    var tension: Double?
    var diasDesdeAnterior: Int?
    /// VeDBA load of the girth (g·min, AVO Track Work) with its own acute / chronic / ACWR.
    var vedba: Double?
    var agudaVedba: Double?
    var cronicaSemanalVedba: Double?
    var acwrVedba: Double?

    init(_ o: [String: Any]?) {
        externa = TJ.num(o, "externa")
        srpe = TJ.num(o, "srpe")
        aguda = TJ.num(o, "aguda")
        cronicaSemanal = TJ.num(o, "cronica_semanal")
        acwr = TJ.num(o, "acwr")
        agudaSrpe = TJ.num(o, "aguda_srpe")
        cronicaSemanalSrpe = TJ.num(o, "cronica_semanal_srpe")
        acwrSrpe = TJ.num(o, "acwr_srpe")
        monotonia = TJ.num(o, "monotonia")
        tension = TJ.num(o, "tension")
        diasDesdeAnterior = TJ.num(o, "dias_desde_anterior").map { TJ.int($0) }
        vedba = TJ.num(o, "vedba")
        agudaVedba = TJ.num(o, "aguda_vedba")
        cronicaSemanalVedba = TJ.num(o, "cronica_semanal_vedba")
        acwrVedba = TJ.num(o, "acwr_vedba")
    }
}

/// Deviation of one metric of a session from its own baseline (median and MAD of the previous 60 days).
struct TrainingDeviation: Identifiable, Equatable {
    var metrica: String
    var valor: Double?
    var lineaBase: Double?
    var mad: Double?
    var z: Double?
    var n: Int
    /// NORMAL | VIGILAR | REVISAR by |z| alone (whatever the direction).
    var nivel: String
    /// MAYOR | MENOR
    var direccion: String?

    var id: String { metrica }

    init(_ o: [String: Any]?) {
        metrica = TJ.str(o, "metrica")
        valor = TJ.num(o, "valor")
        lineaBase = TJ.num(o, "linea_base")
        mad = TJ.num(o, "mad")
        z = TJ.num(o, "z")
        n = TJ.int(TJ.num(o, "n") ?? 0)
        let l: String = TJ.str(o, "nivel")
        nivel = l.isEmpty ? "NORMAL" : l
        let d: String = TJ.str(o, "direccion")
        direccion = d.isEmpty ? nil : d
    }

    var key: String { TrainingAnalytics.split(metrica).key }
    var gait: String { TrainingAnalytics.split(metrica).gait }
    /// Speed is the rider's choice: its deviation is reported but never raises the level.
    var isInformative: Bool { TrainingAnalytics.worseDirection(key) == nil }
    /// Deviation in the bad direction for this metric.
    var isWorse: Bool {
        guard let w = TrainingAnalytics.worseDirection(key), let zz = z else { return false }
        return w == 0 || (w > 0 && zz > 0) || (w < 0 && zz < 0)
    }
    /// What the engine used to raise the level of the session (VIGILAR / REVISAR), or NORMAL.
    var flag: String { (nivel != "NORMAL" && isWorse) ? nivel : "NORMAL" }
}

struct TrainingBaseline: Identifiable, Equatable {
    var metrica: String
    var mediana: Double?
    var mad: Double?
    var n: Int
    /// DISPONIBLE | INSUFICIENTE
    var estado: String
    var id: String { metrica }

    init(_ o: [String: Any]?) {
        metrica = TJ.str(o, "metrica")
        mediana = TJ.num(o, "mediana")
        mad = TJ.num(o, "mad")
        n = TJ.int(TJ.num(o, "n") ?? 0)
        estado = TJ.str(o, "estado")
    }
}

struct TrainingTrend: Identifiable, Equatable {
    var metrica: String
    var pendienteSemana: Double?
    var pendienteP10: Double?
    var pendienteP90: Double?
    var relativaSemana: Double?
    var n: Int
    /// SUBE | BAJA | ESTABLE | SIN_DATOS
    var direccion: String
    var id: String { metrica }

    init(_ o: [String: Any]?) {
        metrica = TJ.str(o, "metrica")
        pendienteSemana = TJ.num(o, "pendiente_semana")
        pendienteP10 = TJ.num(o, "pendiente_p10")
        pendienteP90 = TJ.num(o, "pendiente_p90")
        relativaSemana = TJ.num(o, "relativa_semana")
        n = TJ.int(TJ.num(o, "n") ?? 0)
        let d: String = TJ.str(o, "direccion")
        direccion = d.isEmpty ? "SIN_DATOS" : d
    }

    var hasData: Bool { direccion != "SIN_DATOS" }
    var arrow: String {
        switch direccion {
        case "SUBE": return "arrow.up.right"
        case "BAJA": return "arrow.down.right"
        case "ESTABLE": return "arrow.right"
        default: return "minus"
        }
    }
}

struct TrainingSessionResult: Identifiable, Equatable {
    var id: String
    var fecha: String
    var nivel: String
    var motivos: [String]
    var carga: TrainingLoad
    var desvios: [TrainingDeviation]
    var resumen: TrainingSessionSummary?

    init(_ o: [String: Any]?) {
        id = TJ.str(o, "id")
        fecha = TJ.str(o, "fecha")
        let l: String = TJ.str(o, "nivel")
        nivel = l.isEmpty ? "NORMAL" : l
        motivos = TJ.arr(o, "motivos").compactMap { $0 as? String }
        carga = TrainingLoad(TJ.obj(o, "carga"))
        desvios = TJ.objs(o, "desvios").map { TrainingDeviation($0) }
        resumen = TrainingSessionSummary(TJ.obj(o, "resumen"))
    }

    var date: Date? { TrainingAnalytics.day(fecha) }
    func deviation(_ metric: String) -> TrainingDeviation? { desvios.first { $0.metrica == metric } }
}

struct TrainingDailyLoad: Identifiable, Equatable {
    var fecha: String
    var carga: Double
    var id: String { fecha }
    var date: Date? { TrainingAnalytics.day(fecha) }
}

/// «avo-training-analysis»: state of the horse at the reference date, loads, baselines, trends and every session.
struct TrainingAnalysisResult: Equatable {
    var formato: String
    var version: String
    var algoritmoCarga: String
    var caballo: String
    var fechaReferencia: String
    var sesionesUsadas: Int
    var parametros: [String: Double]
    /// NORMAL | VIGILAR | REVISAR
    var nivel: String
    var motivos: [String]
    var diasDesdeUltima: Int?
    var carga: TrainingLoad
    var nota: String
    var cargaDiaria: [TrainingDailyLoad]
    var lineasBase: [TrainingBaseline]
    var tendencias: [TrainingTrend]
    var sesiones: [TrainingSessionResult]
    var avisos: [String]

    static func parse(_ json: String) throws -> TrainingAnalysisResult {
        let r = try TJ.root(json)
        if let err = r["error"] { throw AvoError.invalidData((err as? String) ?? "") }
        guard let a = TrainingAnalysisResult(r) else { throw AvoError.invalidData("no es un resultado avo-training-analysis") }
        return a
    }

    init?(_ o: [String: Any]?) {
        guard let o = o, TJ.str(o, "formato") == "avo-training-analysis" else { return nil }
        formato = TJ.str(o, "formato")
        version = TJ.str(o, "version")
        algoritmoCarga = TJ.str(o, "algoritmo_carga")
        caballo = TJ.str(o, "caballo")
        fechaReferencia = TJ.str(o, "fecha_referencia")
        sesionesUsadas = TJ.int(TJ.num(o, "sesiones_usadas") ?? 0)
        var p: [String: Double] = [:]
        if let po = TJ.obj(o, "parametros") {
            for (k, _) in po { if let v = TJ.num(po, k) { p[k] = v } }
        }
        parametros = p
        let e = TJ.obj(o, "estado")
        let l: String = TJ.str(e, "nivel")
        nivel = l.isEmpty ? "NORMAL" : l
        motivos = TJ.arr(e, "motivos").compactMap { $0 as? String }
        diasDesdeUltima = TJ.num(e, "dias_desde_ultima").map { TJ.int($0) }
        carga = TrainingLoad(TJ.obj(e, "carga"))
        nota = TJ.str(e, "nota")
        cargaDiaria = TJ.objs(o, "carga_diaria").map { TrainingDailyLoad(fecha: TJ.str($0, "fecha"), carga: TJ.num($0, "carga") ?? 0) }
        lineasBase = TJ.objs(o, "lineas_base").map { TrainingBaseline($0) }
        tendencias = TJ.objs(o, "tendencias").map { TrainingTrend($0) }
        sesiones = TJ.objs(o, "sesiones").map { TrainingSessionResult($0) }
        avisos = TJ.arr(o, "avisos").compactMap { $0 as? String }
    }

    func param(_ k: String, _ fallback: Double) -> Double { parametros[k] ?? fallback }
    var acwrHigh: Double { param("acwr_alto", 1.5) }
    var acwrLow: Double { param("acwr_bajo", 0.8) }
    var monotonyHigh: Double { param("monotonia_alta", 2) }
    var lastSession: TrainingSessionResult? { sesiones.last }
    func trend(_ metric: String) -> TrainingTrend? { tendencias.first { $0.metrica == metric } }
    func baseline(_ metric: String) -> TrainingBaseline? { lineasBase.first { $0.metrica == metric } }

    /// ACWR outside [acwr_bajo, acwr_alto] (nil when it cannot be computed yet).
    var acwrOutOfBand: Bool? {
        guard let a = carga.acwr else { return nil }
        return a > acwrHigh || a < acwrLow
    }

    /// External load split by component (AVO_TRAINING_LOAD_V1 with the factors of the result).
    func loadParts(_ s: TrainingSessionSummary) -> [(name: String, value: Double)] {
        let hsFactor: Double = param("factor_alta_velocidad", 1)
        return [
            ("Paso", s.paso.minutes * param("factor_paso", 1)),
            ("Trote", s.trote.minutes * param("factor_trote", 3)),
            ("Galope", s.galope.minutes * param("factor_galope", 6)),
            ("Alta velocidad", (s.distanciaAltaVelocidadM ?? 0) / 100 * hsFactor),
        ]
    }

    static func levelRank(_ l: String) -> Int { l == "REVISAR" ? 2 : (l == "VIGILAR" ? 1 : 0) }
}
