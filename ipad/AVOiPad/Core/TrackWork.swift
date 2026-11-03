import Foundation

// «trabajo_pista» block of the engine result (AVO Track Work 1.0.0: training of racehorses, PSI / Arabian profiles;
// equine-intelligence/docs/algoritmos/13_TRABAJO_PISTA.md). Decoding is tolerant: missing keys, nulls or wrong types
// become nil (new fields) or NaN (fields kept with their original names for MapPageView / ChartsView / CorrectionsModel).
// Times are ENGINE seconds (GNSS time from the first epoch); the timeline of the app is `engine − engineOffsetS`.
// Everything is exploratory and NOT VERIFIED with real horses; lead (hand) and events are EXPERIMENTAL.

private typealias TWJ = EngineJSON

/// nil when NaN / infinite.
@inline(__always) private func twFinite(_ v: Double?) -> Double? {
    guard let x = v, x.isFinite else { return nil }
    return x
}

/// Breed profile actually used by the engine («perfil»).
struct TrackWorkProfile: Equatable {
    var breed: String = ""                 // GENERICO | PSI | ARABE
    var workSpeed: Double? = nil           // m/s: working canter from here
    var fastSpeed: Double? = nil           // m/s: FAST work when the max reaches this
    var highSpeed: Double? = nil           // m/s: high-speed distance (load)
    var referenceSpeeds: [Double] = []     // m/s: reference speeds of the stride (2)
    var strideFreqRange: [Double] = []     // Hz [min, max]
    var strideLengthRange: [Double] = []   // m [min, max]
    var splitM: Double? = nil              // 200 or 201.168 (furlong)

    init() {}

    init(_ o: [String: Any]?) {
        breed = TWJ.str(o, "raza")
        workSpeed = TWJ.num(o, "v_trabajo")
        fastSpeed = TWJ.num(o, "v_rapido")
        highSpeed = TWJ.num(o, "v_alta")
        referenceSpeeds = TWJ.doubles(o, "v_referencia")
        strideFreqRange = TWJ.doubles(o, "frecuencia_zancada_hz")
        strideLengthRange = TWJ.doubles(o, "longitud_zancada_m")
        splitM = TWJ.num(o, "parcial_m")
    }

    /// True when the splits are furlongs (201.168 m) instead of 200 m.
    var isFurlong: Bool { (splitM ?? 200) > 200.5 }
    var splitBasisText: String {
        guard let s = splitM else { return "Sin datos" }
        return isFurlong ? "furlong (" + AvoFormat.f(s, 1) + " m)" : AvoFormat.f(s, 0) + " m"
    }
}

/// Turning time and degrees to each hand (|yaw rate| ≥ 4 °/s).
struct TrackWorkTurns: Equatable {
    var leftS: Double? = nil
    var rightS: Double? = nil
    var leftDeg: Double? = nil
    var rightDeg: Double? = nil
    /// (left − right) / total time; nil without turning.
    var balance: Double? = nil

    init() {}

    init(_ o: [String: Any]?) {
        leftS = TWJ.num(o, "izquierda_s")
        rightS = TWJ.num(o, "derecha_s")
        leftDeg = TWJ.num(o, "izquierda_grados")
        rightDeg = TWJ.num(o, "derecha_grados")
        balance = TWJ.num(o, "equilibrio")
    }

    var totalS: Double { (leftS ?? 0) + (rightS ?? 0) }
}

/// Girth in the horse frame (IMU_HORSE_FRAME_V1): VeDBA, turning, saturation.
struct TrackWorkGirth: Equatable {
    var available: Bool = false
    var scale: String = ""                 // BNO085 | GRAVEDAD_ESTIMADA | SIN_CINCHA
    var lsbPerG: Double? = nil
    var verticalQuality: Double? = nil     // 0..1
    var forwardConfirmed: Bool = false
    var seconds: Double? = nil
    var vedbaMeanG: Double? = nil          // mean |dynamic acceleration| while moving
    var vedbaLoadGmin: Double? = nil       // ∫VeDBA dt (g·min)
    var vedbaWalkG: Double? = nil
    var vedbaTrotG: Double? = nil
    var vedbaGallopG: Double? = nil
    var turns: TrackWorkTurns = TrackWorkTurns()
    var turnsWalk: TrackWorkTurns = TrackWorkTurns()
    var turnsTrot: TrackWorkTurns = TrackWorkTurns()
    var turnsGallop: TrackWorkTurns = TrackWorkTurns()
    var saturatedSamples: Int = 0

    init() {}

    init(_ o: [String: Any]?) {
        available = TWJ.bool(o, "disponible")
        scale = TWJ.str(o, "escala")
        lsbPerG = TWJ.num(o, "lsb_por_g")
        verticalQuality = TWJ.num(o, "calidad_vertical")
        forwardConfirmed = TWJ.bool(o, "sentido_avance_confirmado")
        seconds = TWJ.num(o, "segundos")
        vedbaMeanG = TWJ.num(o, "vedba_media_g")
        vedbaLoadGmin = TWJ.num(o, "carga_vedba_g_min")
        let va: [String: Any]? = TWJ.obj(o, "vedba_por_aire_g")
        vedbaWalkG = TWJ.num(va, "PASO")
        vedbaTrotG = TWJ.num(va, "TROTE")
        vedbaGallopG = TWJ.num(va, "GALOPE")
        turns = TrackWorkTurns(TWJ.obj(o, "giros"))
        let ga: [String: Any]? = TWJ.obj(o, "giros_por_aire")
        turnsWalk = TrackWorkTurns(TWJ.obj(ga, "PASO"))
        turnsTrot = TrackWorkTurns(TWJ.obj(ga, "TROTE"))
        turnsGallop = TrackWorkTurns(TWJ.obj(ga, "GALOPE"))
        saturatedSamples = TWJ.int(TWJ.num(o, "muestras_saturadas") ?? 0)
    }

    var scaleText: String {
        switch scale {
        case "BNO085": return "unidades del BNO085"
        case "GRAVEDAD_ESTIMADA": return "escala estimada por la gravedad"
        case "SIN_CINCHA": return "sin cincha"
        default: return scale.isEmpty ? "—" : scale
        }
    }
}

/// One gallop stride (STRIDE_V1).
struct TrackWorkStride: Equatable {
    var t0: Double
    var t1: Double
    var freqHz: Double?
    var speed: Double?          // m/s (GNSS)
    var lengthM: Double?        // nil outside the plausible range
    var vertPeakG: Double?
    var vertDispM: Double?
    var vedbaG: Double?
    var lateralFeature: Double?
    var yawDegS: Double?
    var lead: String            // IZQUIERDA | DERECHA | INDETERMINADA
    var inCurve: Bool
}

/// Summary of the gallop strides of the session.
struct TrackWorkStrides: Equatable {
    var count: Int = 0
    var freqMedianHz: Double? = nil
    var lengthMedianM: Double? = nil
    var vertDispMedianM: Double? = nil
    var vertPeakMedianG: Double? = nil
    var list: [TrackWorkStride] = []

    init() {}

    init(_ o: [String: Any]?) {
        count = TWJ.int(TWJ.num(o, "n") ?? 0)
        freqMedianHz = TWJ.num(o, "frecuencia_mediana_hz")
        lengthMedianM = TWJ.num(o, "longitud_mediana_m")
        vertDispMedianM = TWJ.num(o, "desplazamiento_vertical_mediano_m")
        vertPeakMedianG = TWJ.num(o, "pico_vertical_mediano_g")
        list = TWJ.objs(o, "lista").compactMap { (s: [String: Any]?) -> TrackWorkStride? in
            guard let s = s, let t0 = TWJ.num(s, "t0"), let t1 = TWJ.num(s, "t1") else { return nil }
            return TrackWorkStride(t0: t0, t1: t1, freqHz: TWJ.num(s, "f_hz"), speed: TWJ.num(s, "v"), lengthM: TWJ.num(s, "l_m"),
                                   vertPeakG: TWJ.num(s, "pico_v_g"), vertDispM: TWJ.num(s, "desp_v_m"), vedbaG: TWJ.num(s, "vedba_g"),
                                   lateralFeature: TWJ.num(s, "rasgo_lateral"), yawDegS: TWJ.num(s, "giro_deg_s"),
                                   lead: TWJ.str(s, "mano"), inCurve: TWJ.bool(s, "curva"))
        }
    }

    /// Strides inside [t0, t1] (engine seconds).
    func within(_ t0: Double, _ t1: Double) -> [TrackWorkStride] {
        list.filter { $0.t0 >= t0 - 1e-6 && $0.t1 <= t1 + 1e-6 }
    }
}

/// Lead (hand) of the gallop, LEAD_V1 (EXPERIMENTAL).
struct TrackWorkLead: Equatable {
    var experimental: Bool = true
    var calibration: String = ""           // CURVAS | OPCION | SIN_CALIBRAR | ""
    var sign: Double? = nil
    var curveAgreement: Double? = nil      // 0..1
    var leftStrides: Int = 0
    var rightStrides: Int = 0
    var changes: Int = 0
    var outsideInCurvePct: Double? = nil   // strides in curves on the outside lead

    init() {}

    init(_ o: [String: Any]?) {
        experimental = o?["experimental"] == nil ? true : TWJ.bool(o, "experimental")
        calibration = TWJ.str(o, "calibracion")
        sign = TWJ.num(o, "signo")
        curveAgreement = TWJ.num(o, "acuerdo_curvas")
        leftStrides = TWJ.int(TWJ.num(o, "zancadas_izquierda") ?? 0)
        rightStrides = TWJ.int(TWJ.num(o, "zancadas_derecha") ?? 0)
        changes = TWJ.int(TWJ.num(o, "cambios") ?? 0)
        outsideInCurvePct = TWJ.num(o, "mano_de_fuera_en_curva_pct")
    }

    var calibrationText: String {
        switch calibration {
        case "CURVAS": return "calibrada en las curvas"
        case "OPCION": return "signo fijado por opción"
        case "SIN_CALIBRAR": return "sin calibrar"
        default: return calibration.isEmpty ? "sin cincha" : calibration
        }
    }
}

/// One split (200 m or furlong) of an effort or pass.
struct TrackWorkSplit: Identifiable, Equatable {
    var id: Int                 // 0-based order
    var fromM: Double
    var toM: Double
    var timeS: Double?
    var speed: Double?          // m/s
    var cumulativeS: Double?    // time from the start of the effort to the end of this split

    var lengthM: Double { toM - fromM }
    /// Speed of the split: the engine value, or length / time.
    var speedMs: Double? {
        if let v = twFinite(speed), v > 0 { return v }
        if let t = twFinite(timeS), t > 0, lengthM > 0 { return lengthM / t }
        return nil
    }
    var speedKmh: Double? { speedMs.map { $0 * 3.6 } }
    /// True when it covers the whole basis (a last split up to the end or to the finish line can be shorter).
    func isFull(_ basisM: Double) -> Bool { lengthM >= basisM * 0.95 && lengthM <= basisM * 1.05 }
    var label: String { AvoFormat.f(fromM, 0) + "–" + AvoFormat.f(toM, 0) }
}

/// Best time over a distance inside an effort (or over the whole session).
struct TrackWorkBest: Identifiable, Equatable {
    var distanceM: Double
    var timeS: Double
    var t0: Double?             // engine seconds where it starts
    var effortKey: String = ""  // T<id> | P<id> (session best)
    var effortTitle: String = ""

    var id: String { AvoFormat.f(distanceM, 0) }
    var speedMs: Double? { timeS > 0 ? distanceM / timeS : nil }
    var speedKmh: Double? { speedMs.map { $0 * 3.6 } }
}

/// Stride frequency / length at one reference speed of the breed (only inside the measured range).
struct TrackWorkStrideReference: Equatable, Identifiable {
    var speed: Double?          // m/s
    var freqHz: Double?
    var lengthM: Double?
    var id: String { speed.map { AvoFormat.f($0, 1) } ?? "?" }
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
    // full block (nil when missing)
    var tToVmaxS: Double? = nil
    var distAbove90M: Double? = nil
    var accelMax: Double? = nil
    var last400S: Double? = nil
    var speedLast200: Double? = nil
    var speedLast400: Double? = nil
    var splits: [TrackWorkSplit] = []
    var best: [TrackWorkBest] = []
    var strideCount: Int = 0
    var freqAtVmaxHz: Double? = nil
    var lengthAtVmaxM: Double? = nil
    var freqMaxHz: Double? = nil
    var lengthMaxM: Double? = nil
    var freqFitA: Double? = nil      // f = a + b·v
    var freqFitB: Double? = nil
    var freqFitR: Double? = nil
    var lengthFitA: Double? = nil    // l = a + b·v
    var lengthFitB: Double? = nil
    var references: [TrackWorkStrideReference] = []
    var leadLeft: Int = 0
    var leadRight: Int = 0
    var leadChanges: Int = 0
    var pauseToNextS: Double? = nil
    var pauseSpeedMean: Double? = nil

    var kindText: String {
        switch kind {
        case "TRABAJO_RAPIDO": return "Trabajo rápido"
        case "GALOPE_TRABAJO": return "Galope de trabajo"
        case "PASADA": return "Pasada"
        default: return kind
        }
    }

    var isPass: Bool { kind == "PASADA" }
    /// Unique key in the session: T<id> for efforts, P<id> for course passes.
    var key: String { (isPass ? "P" : "T") + String(id) }
    var title: String { (isPass ? "Pasada " : "Trabajo ") + String(id) }

    var vmaxOpt: Double? { twFinite(vmax) }
    var speedMeanOpt: Double? { twFinite(speedMean) }
    var fatigueOpt: Double? { twFinite(fatiguePct) }
    var last200Opt: Double? { twFinite(last200S) }
    var recoveryOpt: Double? { twFinite(recoveryS) }
    var durationOpt: Double? { twFinite(durationS) }
    var distanceOpt: Double? { twFinite(distanceM) }

    /// Strides counted to each hand (nil without girth or without decided strides).
    var leadText: String? {
        if leadLeft + leadRight == 0 { return nil }
        let main: String = leadLeft >= leadRight ? "Izq." : "Dcha."
        return main + " \(leadLeft)/\(leadRight)" + (leadChanges > 0 ? " · \(leadChanges) camb." : "")
    }

    /// Full splits only (same length as the basis).
    func fullSplits(_ basisM: Double) -> [TrackWorkSplit] { splits.filter { $0.isFull(basisM) } }

    /// Best split speed (m/s) among the full splits.
    func bestSplitSpeed(_ basisM: Double) -> Double? { fullSplits(basisM).compactMap { $0.speedMs }.max() }
}

/// Event of the girth (EXPERIMENTAL): IMPACTO_ATIPICO | MOVIMIENTO_LATERAL_BRUSCO | CAMBIO_DE_MANO | SATURACION.
struct TrackWorkEvent: Identifiable, Equatable {
    var id: Int
    var type: String
    var t: Double?
    var value: Double?
    var detail: String

    var typeText: String {
        switch type {
        case "IMPACTO_ATIPICO": return "Impacto atípico"
        case "MOVIMIENTO_LATERAL_BRUSCO": return "Movimiento lateral brusco"
        case "CAMBIO_DE_MANO": return "Cambio de mano"
        case "SATURACION": return "Saturación de la cincha"
        default: return type
        }
    }

    var valueText: String {
        guard let v = twFinite(value) else { return "—" }
        switch type {
        case "IMPACTO_ATIPICO", "SATURACION": return AvoFormat.f(v, 2) + " g"
        case "MOVIMIENTO_LATERAL_BRUSCO": return AvoFormat.f(v, 0) + " °/s"
        case "CAMBIO_DE_MANO": return v > 0 ? "a izquierda" : "a derecha"
        default: return AvoFormat.f(v, 2)
        }
    }
}

/// Crossing of a start / finish line (course).
struct TrackWorkCrossing: Identifiable, Equatable {
    var id: Int
    var line: String            // SALIDA | META | SALIDA_META
    var t: Double?
    var direction: String       // IZQ_A_DCHA | DCHA_A_IZQ
    var counts: Bool
}

struct TrackWorkPhase: Equatable {
    var present: Bool = false
    var t0: Double = .nan
    var t1: Double = .nan
    var durationS: Double = .nan
    var distanceM: Double = .nan
    var walkS: Double = 0
    var trotS: Double = 0
    var canterS: Double = 0
    var stoppedS: Double = 0
}

struct TrackWorkResult: Equatable {
    var present: Bool = false
    var module: String = ""
    var version: String = ""
    var breed: String = ""
    var profile: TrackWorkProfile = TrackWorkProfile()
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
    // full block
    var girth: TrackWorkGirth = TrackWorkGirth()
    var strides: TrackWorkStrides = TrackWorkStrides()
    var lead: TrackWorkLead = TrackWorkLead()
    var strideDropPct: Double? = nil
    var sessionVmax: Double? = nil           // m/s
    var sessionBest200S: Double? = nil
    var distanceWorkM: Double? = nil         // working canter distance
    var distanceFastM: Double? = nil
    var courseName: String = ""
    var gateDistanceM: Double? = nil
    var insideFencePct: Double? = nil
    var crossings: [TrackWorkCrossing] = []
    var events: [TrackWorkEvent] = []
    var note: String = ""

    var phaseBasisText: String {
        switch phaseBasis {
        case "LINEAS": return "por líneas de salida y meta"
        case "MANUAL": return "corregidas a mano"
        case "VELOCIDAD": return "automáticas (velocidad RTK y cincha)"
        default: return phaseBasis
        }
    }

    /// Short basis for the header: velocidad / líneas / corregidas.
    var phaseBasisShort: String {
        switch phaseBasis {
        case "LINEAS": return "líneas"
        case "MANUAL": return "corregidas"
        case "VELOCIDAD": return "velocidad"
        default: return phaseBasis.isEmpty ? "—" : phaseBasis.lowercased()
        }
    }

    /// Split basis (m): 200 or 201.168.
    var splitBasisM: Double { profile.splitM ?? 200 }
    var bestPassOpt: Double? { twFinite(bestPassS) }
    var vmaxDropOpt: Double? { twFinite(vmaxDropPct) }
    var recoveryMeanOpt: Double? { twFinite(recoveryMeanS) }
    var hasGirth: Bool { girth.available }
    /// Crossings of the start / finish lines in the wrong direction (ignored; e.g. the warm-up going the other way).
    var ignoredCrossings: Int { crossings.filter { !$0.counts }.count }
    /// Efforts and passes, in that order (keys T<id> / P<id>).
    var allEfforts: [TrackWorkEffort] { efforts + passes }

    func effort(_ key: String) -> TrackWorkEffort? { allEfforts.first { $0.key == key } }

    /// Best pass by duration (the engine's «mejor_pasada_s»), or nil.
    var bestPass: TrackWorkEffort? {
        passes.filter { $0.durationOpt != nil }.min { ($0.durationOpt ?? 0) < ($1.durationOpt ?? 0) }
    }

    /// Best time of each distance (200…1600 m) over every effort and pass of the session.
    var sessionBest: [TrackWorkBest] {
        var out: [Double: TrackWorkBest] = [:]
        for e in allEfforts {
            for b in e.best where b.timeS > 0 {
                if let cur = out[b.distanceM], cur.timeS <= b.timeS { continue }
                var x: TrackWorkBest = b
                x.effortKey = e.key
                x.effortTitle = e.title
                out[b.distanceM] = x
            }
        }
        return out.keys.sorted().compactMap { out[$0] }
    }

    /// Events between t0 and t1 (engine seconds).
    func eventsBetween(_ t0: Double, _ t1: Double) -> [TrackWorkEvent] {
        events.filter { (e: TrackWorkEvent) -> Bool in
            guard let t = e.t else { return false }
            return t >= t0 && t <= t1
        }
    }

    var atypicalImpacts: Int { events.filter { $0.type == "IMPACTO_ATIPICO" }.count }

    static func parse(_ o: [String: Any]?) -> TrackWorkResult {
        typealias J = EngineJSON
        var r = TrackWorkResult()
        guard let o = o else { return r }
        r.present = true
        r.module = J.str(o, "modulo")
        r.version = J.str(o, "version")
        r.profile = TrackWorkProfile(J.obj(o, "perfil"))
        r.breed = r.profile.breed
        r.manualCorrections = J.bool(o, "correcciones_manuales")
        r.girth = TrackWorkGirth(J.obj(o, "cincha"))
        r.strides = TrackWorkStrides(J.obj(o, "zancadas"))
        r.lead = TrackWorkLead(J.obj(o, "mano"))
        let fa = J.obj(o, "fases")
        r.phaseBasis = J.str(fa, "base")
        r.warmup = phase(J.obj(fa, "calentamiento"))
        r.work = phase(J.obj(fa, "trabajo"))
        r.cooldown = phase(J.obj(fa, "vuelta_a_la_calma"))
        let tr = J.obj(o, "trabajos")
        r.efforts = J.objs(tr, "lista").compactMap { effort($0) }
        r.distanceWorkM = J.num(tr, "distancia_galope_trabajo_m")
        r.distanceFastM = J.num(tr, "distancia_rapida_m")
        r.sessionVmax = J.num(tr, "v_max")
        r.sessionBest200S = J.num(tr, "mejor_200m_s")
        let co = J.obj(o, "recorrido")
        r.courseDefined = co != nil
        r.passes = J.objs(co, "pasadas").compactMap { effort($0) }
        r.bestPassS = J.num(co, "mejor_pasada_s") ?? .nan
        r.courseName = J.str(co, "nombre")
        r.gateDistanceM = J.num(co, "distancia_salida_meta_m")
        r.insideFencePct = J.num(co, "dentro_geocerca_pct")
        var ci: Int = 0
        for c in J.objs(co, "cruces") {
            guard let c = c else { continue }
            r.crossings.append(TrackWorkCrossing(id: ci, line: J.str(c, "linea"), t: J.num(c, "t"), direction: J.str(c, "sentido"),
                                                 counts: J.bool(c, "cuenta")))
            ci += 1
        }
        let se = J.obj(o, "series")
        r.reps = J.int(J.num(se, "repeticiones") ?? 0)
        r.fastReps = J.int(J.num(se, "rapidas") ?? 0)
        r.vmaxDropPct = J.num(se, "caida_v_max_pct") ?? .nan
        r.strideDropPct = J.num(se, "caida_zancada_pct")
        r.recoveryMeanS = J.num(se, "recuperacion_media_s") ?? .nan
        r.warmupShort = J.bool(se, "calentamiento_corto")
        var ei: Int = 0
        for e in J.objs(o, "eventos") {
            guard let e = e else { continue }
            r.events.append(TrackWorkEvent(id: ei, type: J.str(e, "tipo"), t: J.num(e, "t"), value: J.num(e, "valor"), detail: J.str(e, "detalle")))
            ei += 1
        }
        r.warnings = J.arr(o, "avisos").compactMap { $0 as? String }
        r.note = J.str(o, "nota")
        return r
    }

    private static func phase(_ p: [String: Any]?) -> TrackWorkPhase {
        typealias J = EngineJSON
        guard let p = p else { return TrackWorkPhase() }
        return TrackWorkPhase(present: true, t0: J.num(p, "t0") ?? .nan, t1: J.num(p, "t1") ?? .nan,
                              durationS: J.num(p, "duracion_s") ?? .nan, distanceM: J.num(p, "distancia_m") ?? .nan,
                              walkS: J.num(p, "paso_s") ?? 0, trotS: J.num(p, "trote_s") ?? 0, canterS: J.num(p, "galope_s") ?? 0,
                              stoppedS: J.num(p, "parado_s") ?? 0)
    }

    static func effort(_ e: [String: Any]?) -> TrackWorkEffort? {
        typealias J = EngineJSON
        guard let e = e, let t0 = J.num(e, "t0"), let t1 = J.num(e, "t1") else { return nil }
        var splits: [TrackWorkSplit] = []
        var cum: Double = 0
        var cumOk: Bool = true
        for (k, p) in J.objs(e, "parciales").enumerated() {
            let time: Double? = J.num(p, "tiempo_s")
            if let x = time, x.isFinite { cum += x } else { cumOk = false }
            splits.append(TrackWorkSplit(id: k, fromM: J.num(p, "desde_m") ?? .nan, toM: J.num(p, "hasta_m") ?? .nan, timeS: time,
                                         speed: J.num(p, "v"), cumulativeS: cumOk ? cum : nil))
        }
        let best: [TrackWorkBest] = J.objs(e, "mejores").compactMap { (b: [String: Any]?) -> TrackWorkBest? in
            guard let d = J.num(b, "distancia_m"), let t = J.num(b, "tiempo_s"), t > 0 else { return nil }
            return TrackWorkBest(distanceM: d, timeS: t, t0: J.num(b, "t0"))
        }
        let refs: [TrackWorkStrideReference] = J.objs(e, "referencia").map {
            TrackWorkStrideReference(speed: J.num($0, "v"), freqHz: J.num($0, "f_hz"), lengthM: J.num($0, "l_m"))
        }
        let af = J.obj(e, "ajuste_f"), al = J.obj(e, "ajuste_l"), mn = J.obj(e, "mano")
        var w = TrackWorkEffort(id: J.int(J.num(e, "id") ?? 0), kind: J.str(e, "tipo"), t0: t0, t1: t1,
                                durationS: J.num(e, "duracion_s") ?? .nan, distanceM: J.num(e, "distancia_m") ?? .nan,
                                vmax: J.num(e, "v_max") ?? .nan, speedMean: J.num(e, "v_media") ?? .nan,
                                fatiguePct: J.num(e, "indice_caida_pct") ?? .nan, last200S: J.num(e, "ultimos_200m_s") ?? .nan,
                                recoveryS: J.num(e, "recuperacion_hasta_paso_s") ?? .nan, manual: J.bool(e, "manual"),
                                sectionals: splits.map { $0.timeS ?? .nan })
        w.tToVmaxS = J.num(e, "t_hasta_v_max_s")
        w.distAbove90M = J.num(e, "distancia_90_pct_m")
        w.accelMax = J.num(e, "aceleracion_max")
        w.last400S = J.num(e, "ultimos_400m_s")
        w.speedLast200 = J.num(e, "v_ultimos_200m")
        w.speedLast400 = J.num(e, "v_ultimos_400m")
        w.splits = splits
        w.best = best
        w.strideCount = J.int(J.num(e, "zancadas") ?? 0)
        w.freqAtVmaxHz = J.num(e, "f_en_v_max_hz")
        w.lengthAtVmaxM = J.num(e, "l_en_v_max_m")
        w.freqMaxHz = J.num(e, "f_max_hz")
        w.lengthMaxM = J.num(e, "l_max_m")
        w.freqFitA = J.num(af, "a")
        w.freqFitB = J.num(af, "b")
        w.freqFitR = J.num(af, "r")
        w.lengthFitA = J.num(al, "a")
        w.lengthFitB = J.num(al, "b")
        w.references = refs
        w.leadLeft = J.int(J.num(mn, "izquierda") ?? 0)
        w.leadRight = J.int(J.num(mn, "derecha") ?? 0)
        w.leadChanges = J.int(J.num(mn, "cambios") ?? 0)
        w.pauseToNextS = J.num(e, "pausa_hasta_siguiente_s")
        w.pauseSpeedMean = J.num(e, "v_media_pausa")
        return w
    }

    /// Speed (m/s) against distance (m) inside [t0, t1] (engine seconds) from the engine series (t, speed), integrating
    /// the speed with trapezoids; at most `maxPoints` points. Empty when the series do not cover the effort.
    static func speedOverDistance(t: [Double], speed: [Double], t0: Double, t1: Double, maxPoints: Int = 400) -> [(d: Double, v: Double)] {
        let n: Int = min(t.count, speed.count)
        if n < 2 || !(t1 > t0) { return [] }
        var out: [(d: Double, v: Double)] = []
        var d: Double = 0
        var prevT: Double = .nan
        var prevV: Double = .nan
        for i in 0..<n {
            let ti: Double = t[i], vi: Double = speed[i]
            if !(ti >= t0 && ti <= t1) || !vi.isFinite { continue }
            if prevT.isFinite && prevV.isFinite {
                let dt: Double = ti - prevT
                if dt > 0 && dt < 5 { d += (vi + prevV) / 2 * dt }
            }
            out.append((d: d, v: vi))
            prevT = ti
            prevV = vi
        }
        if out.count <= maxPoints || maxPoints < 2 { return out }
        let step: Double = Double(out.count - 1) / Double(maxPoints - 1)
        var thin: [(d: Double, v: Double)] = []
        for k in 0..<maxPoints { thin.append(out[min(out.count - 1, Int((Double(k) * step).rounded()))]) }
        return thin
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

/// Text of the Track Work values (Spanish decimal comma); "—" when missing. Never invents a value.
enum TrackWorkText {
    static func seconds(_ v: Double?, _ decimals: Int = 2) -> String {
        guard let x = v, x.isFinite else { return "—" }
        return AvoFormat.f(x, decimals) + " s"
    }
    /// m/s → km/h.
    static func kmh(_ ms: Double?, _ decimals: Int = 1) -> String {
        guard let x = ms, x.isFinite else { return "—" }
        return AvoFormat.f(x * 3.6, decimals) + " km/h"
    }
    static func metres(_ v: Double?, _ decimals: Int = 0) -> String {
        guard let x = v, x.isFinite else { return "—" }
        return AvoFormat.f(x, decimals) + " m"
    }
    static func percent(_ v: Double?, _ decimals: Int = 1) -> String {
        guard let x = v, x.isFinite else { return "—" }
        return AvoFormat.f(x, decimals) + " %"
    }
    static func hertz(_ v: Double?) -> String {
        guard let x = v, x.isFinite else { return "—" }
        return AvoFormat.f(x, 2) + " Hz"
    }
    static func g(_ v: Double?, _ decimals: Int = 2) -> String {
        guard let x = v, x.isFinite else { return "—" }
        return AvoFormat.f(x, decimals) + " g"
    }
    static func minutes(_ s: Double?) -> String {
        guard let x = s, x.isFinite else { return "—" }
        return AvoFormat.f(x / 60, 1) + " min"
    }
    static func clock(_ s: Double?) -> String {
        guard let x = s, x.isFinite else { return "—" }
        return TimeText.clock(x)
    }
}
