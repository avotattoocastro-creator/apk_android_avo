import Foundation

/// Cancellation flag shared with the native engine (C `const volatile int*`), heap allocated so it outlives the call.
final class EngineCancelFlag: @unchecked Sendable {
    let pointer: UnsafeMutablePointer<Int32>

    init() {
        pointer = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        pointer.initialize(to: 0)
    }

    deinit {
        pointer.deinitialize(count: 1)
        pointer.deallocate()
    }

    func cancel() { pointer.pointee = 1 }
    var isCancelled: Bool { pointer.pointee != 0 }
}

/// Access to the AVO Performance Equine (same C++17 code as Android, Windows and Python), linked statically
/// into the app and reached through the C API (avo_eq_c.h, bridging header). Strings are UTF-8. The native calls are
/// blocking: the async functions run them off the caller's thread. Cancellation sets a flag polled by the engine.
enum EquineEngine {
    private static let loadError: String? = {
        avo_eq_api_version() >= 2 ? nil : "versión de la API del motor no compatible"
    }()

    static var available: Bool { loadError == nil }
    static var unavailableReason: String? { loadError }

    static func version() -> String {
        guard available, let p = avo_eq_version() else { return "no disponible" }
        return String(cString: p)
    }

    // MARK: async (Task cancellation -> native flag)

    static func analyseJson(_ segments: [String], _ optionsJson: String) async throws -> String {
        try await run(segments, nil, optionsJson)
    }

    static func compareJson(_ a: [String], _ b: [String], _ optionsJson: String) async throws -> String {
        try await run(a, b, optionsJson)
    }

    private static func run(_ a: [String], _ b: [String]?, _ options: String) async throws -> String {
        let flag = EngineCancelFlag()
        if Task.isCancelled { flag.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let text = try EquineEngine.call(a, b, options, flag)
                        cont.resume(returning: text)
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            flag.cancel()
        }
    }

    // MARK: blocking (explicit flag)

    static func analyseJsonSync(_ segments: [String], _ optionsJson: String, cancel: EngineCancelFlag? = nil) throws -> String {
        try call(segments, nil, optionsJson, cancel ?? EngineCancelFlag())
    }

    static func compareJsonSync(_ a: [String], _ b: [String], _ optionsJson: String, cancel: EngineCancelFlag? = nil) throws -> String {
        try call(a, b, optionsJson, cancel ?? EngineCancelFlag())
    }

    static func invalidateCache(_ dir: String) -> Int {
        if !available { return -1 }
        return dir.withCString { (p: UnsafePointer<CChar>) -> Int in Int(avo_eq_cache_invalidate(p)) }
    }

    private static func call(_ a: [String], _ b: [String]?, _ options: String, _ flag: EngineCancelFlag) throws -> String {
        if !available { throw AvoError.invalidOperation(unavailableReason ?? "motor no disponible") }
        let ma: [UnsafeMutablePointer<CChar>?] = a.map { strdup($0) }
        let mb: [UnsafeMutablePointer<CChar>?] = (b ?? []).map { strdup($0) }
        defer {
            for p in ma { free(p) }
            for p in mb { free(p) }
        }
        let ca: [UnsafePointer<CChar>?] = ma.map { (p: UnsafeMutablePointer<CChar>?) -> UnsafePointer<CChar>? in
            p.map { UnsafePointer<CChar>($0) }
        }
        let cb: [UnsafePointer<CChar>?] = mb.map { (p: UnsafeMutablePointer<CChar>?) -> UnsafePointer<CChar>? in
            p.map { UnsafePointer<CChar>($0) }
        }
        let cancelPtr: UnsafePointer<Int32> = UnsafePointer<Int32>(flag.pointer)
        var json: UnsafeMutablePointer<CChar>? = nil
        let rc: Int32 = options.withCString { (opt: UnsafePointer<CChar>) -> Int32 in
            ca.withUnsafeBufferPointer { (abuf: UnsafeBufferPointer<UnsafePointer<CChar>?>) -> Int32 in
                if b != nil {
                    return cb.withUnsafeBufferPointer { (bbuf: UnsafeBufferPointer<UnsafePointer<CChar>?>) -> Int32 in
                        avo_eq_compare_ex(abuf.baseAddress, Int32(ca.count), bbuf.baseAddress, Int32(cb.count), opt, cancelPtr, &json)
                    }
                }
                return avo_eq_analyse_ex(abuf.baseAddress, Int32(ca.count), opt, cancelPtr, &json)
            }
        }
        defer { if let j = json { avo_eq_free(j) } }
        let text: String = json.map { String(cString: $0) } ?? ""
        withExtendedLifetime(flag) {}
        if rc == 4 { throw CancellationError() }
        if rc != 0 { throw AvoError.invalidData(errorOf(text)) }
        return text
    }

    // MARK: AVO Training Analytics 1.0.0 (avo_eq_training_summary / avo_eq_training_analyse)

    /// Small summary of ONE session («avo-training-session», ~2 KB) from the JSON of analyseJson. `extraJson` (may be nil)
    /// completes or corrects it: {"id","caballo","jinete","fecha_utc","valoracion":{…},"pista":{…}}. Fast and blocking.
    static func trainingSummary(analysisJson: String, extraJson: String?) throws -> String {
        if !available { throw AvoError.invalidOperation(unavailableReason ?? "motor no disponible") }
        var json: UnsafeMutablePointer<CChar>? = nil
        let rc: Int32 = analysisJson.withCString { (a: UnsafePointer<CChar>) -> Int32 in
            if let x = extraJson, !x.isEmpty {
                return x.withCString { (e: UnsafePointer<CChar>) -> Int32 in avo_eq_training_summary(a, e, &json) }
            }
            return avo_eq_training_summary(a, nil, &json)
        }
        defer { if let j = json { avo_eq_free(j) } }
        let text: String = json.map { String(cString: $0) } ?? ""
        if rc == 4 { throw CancellationError() }
        if rc != 0 { throw AvoError.invalidData(errorOf(text)) }
        return text
    }

    /// History of one horse («avo-training-analysis»). Runs off the caller's thread; Task cancellation sets the native flag.
    static func trainingAnalyse(inputJson: String, optionsJson: String?) async throws -> String {
        let flag = EngineCancelFlag()
        if Task.isCancelled { flag.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let text: String = try EquineEngine.trainingAnalyseSync(inputJson: inputJson, optionsJson: optionsJson, cancel: flag)
                        cont.resume(returning: text)
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            flag.cancel()
        }
    }

    static func trainingAnalyseSync(inputJson: String, optionsJson: String?, cancel: EngineCancelFlag? = nil) throws -> String {
        if !available { throw AvoError.invalidOperation(unavailableReason ?? "motor no disponible") }
        let flag: EngineCancelFlag = cancel ?? EngineCancelFlag()
        let cancelPtr: UnsafePointer<Int32> = UnsafePointer<Int32>(flag.pointer)
        var json: UnsafeMutablePointer<CChar>? = nil
        let rc: Int32 = inputJson.withCString { (i: UnsafePointer<CChar>) -> Int32 in
            if let o = optionsJson, !o.isEmpty {
                return o.withCString { (op: UnsafePointer<CChar>) -> Int32 in avo_eq_training_analyse(i, op, cancelPtr, &json) }
            }
            return avo_eq_training_analyse(i, nil, cancelPtr, &json)
        }
        defer { if let j = json { avo_eq_free(j) } }
        let text: String = json.map { String(cString: $0) } ?? ""
        withExtendedLifetime(flag) {}
        if rc == 4 { throw CancellationError() }
        if rc != 0 { throw AvoError.invalidData(errorOf(text)) }
        return text
    }

    private static func errorOf(_ json: String) -> String {
        guard let o = AvoJSON.object(Data(json.utf8)) else { return json }
        if let e = o["error"] { return (e as? String) ?? json }
        return json
    }

    /// Options JSON with proper escaping.
    static func options(series: Bool = true, cacheDir: String? = nil, force: Bool = false, extra: String? = nil) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        var sb = "{\"series\":" + (series ? "true" : "false") + ",\"forzar\":" + (force ? "true" : "false")
        sb += ",\"procesado_utc\":" + AvoJSON.quote(f.string(from: Date()))
        if let c = cacheDir { sb += ",\"cache_dir\":" + AvoJSON.quote(c) }
        if let e = extra, !e.isEmpty { sb += "," + e }
        return sb + "}"
    }

    static func options(_ series: Bool, _ cacheDir: String?) -> String { options(series: series, cacheDir: cacheDir) }
}

// ------------------------------------------------------------------ result model (format avo-equine-analysis v2)
struct EngineQualityRow: Equatable {
    var dominio: String
    var nivel: String
    var motivos: String
}

struct EngineSegmentRow: Equatable {
    var id: Int
    var aire: String
    var desde: String
    var hasta: String
    var distancia: String
    var velocidadMedia: String
    var velocidadMax: String
    var cadencia: String
    var tranco: String
    var corrCiclos: String
    var cvIntervalos: String
    var calidadGnss: String
    var calidadImu: String
    var avisos: String
    var t0: Double = 0
    var t1: Double = 0
    var gaitCode: String = ""
    var cadenceHz: Double? = nil
    var cycleCorrelation: Double? = nil
    var intervalCv: Double? = nil
    var strideLengthM: Double? = nil
}

/// Exploratory symmetry group (one IMU, one gait) — EXPLORATORY_MOTION_SYMMETRY, never a clinical result.
struct EngineSymmetryGroup: Equatable {
    var imu: Int
    var gait: String
    var windows: Int
    var strides: Int
    var logAmplitudeRatio: Double?
    var amplitudeReproducible: Bool
    var temporalAsymmetry: Double?
    var temporalReproducible: Bool
    var halfSimilarity: Double?
}

struct EngineGaitRow: Equatable {
    var aire: String
    var tramos: Int
    var duracion: String
    var fraccionTiempo: String
    var distancia: String
    var velocidadMedia: String
    var cadencia: String
    var tranco: String
}

struct EngineCurveRow: Equatable {
    var id: Int
    var direccion: String
    var inicio: String
    var giro: String
    var radio: String
    var vEntrada: String
    var vSalida: String
    var lateralEstimada: String
    var cadencia: String
    var calidad: String
    var t0: Double = 0
}

struct EngineEventRow: Equatable {
    var id: String
    var tipo: String
    var inicio: String
    var fin: String
    var calidad: String
    var motivo: String
    var algoritmo: String
    var t0: Double = 0
}

struct EngineDiffRow: Equatable {
    var metrica: String
    var a: String
    var b: String
    var diferencia: String
    var comparable: String
    var contexto: String
}

struct EngineKvRow: Equatable {
    var metrica: String
    var valor: String
}

/// JSON helpers mirroring the C# JsonElement accessors used by the engine result parsers.
enum EngineJSON {
    static func num(_ e: [String: Any]?, _ k: String) -> Double? {
        guard let e = e, let n = e[k] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.doubleValue
    }
    static func str(_ e: [String: Any]?, _ k: String) -> String { (e?[k] as? String) ?? "" }
    static func bool(_ e: [String: Any]?, _ k: String) -> Bool {
        guard let e = e, let n = e[k] as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return false }
        return n.boolValue
    }
    static func obj(_ e: [String: Any]?, _ k: String) -> [String: Any]? { e?[k] as? [String: Any] }
    static func arr(_ e: [String: Any]?, _ k: String) -> [Any] { (e?[k] as? [Any]) ?? [] }
    static func objs(_ e: [String: Any]?, _ k: String) -> [[String: Any]?] { arr(e, k).map { $0 as? [String: Any] } }
    static func doubles(_ e: [String: Any]?, _ k: String) -> [Double] {
        arr(e, k).map { (x: Any) -> Double in
            if let n = x as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.doubleValue }
            return .nan
        }
    }
    static func strings(_ e: [String: Any]?, _ k: String, _ sep: String = "; ") -> String {
        arr(e, k).map { ($0 as? String) ?? "" }.joined(separator: sep)
    }
    /// C# (int) cast of a double, without trapping on non-finite or huge values.
    static func int(_ d: Double) -> Int {
        if !d.isFinite || d >= 2_147_483_648 || d <= -2_147_483_649 { return Int(Int32.min) }
        return Int(d)
    }
    static func int64(_ d: Double) -> Int64 {
        if !d.isFinite || d >= 9.2e18 || d <= -9.2e18 { return Int64.min }
        return Int64(d)
    }
    static func root(_ json: String) throws -> [String: Any] {
        guard let r = AvoJSON.object(Data(json.utf8)) else { throw AvoError.invalidData("resultado JSON no válido") }
        return r
    }
    /// .NET custom format "0.##…" in es-ES (decimal comma, trailing zeros removed).
    static func esTrim(_ v: Double, _ maxDecimals: Int) -> String {
        ExportService.trimmed(v, maxDecimals, decimalComma: true)
    }
}

final class EquineAnalysis {
    private(set) var engine: String = ""
    private(set) var sessionId: String = ""
    private(set) var cache: String?
    private(set) var mode: String = ""
    private(set) var hasImu: Bool = false
    private(set) var itow0Ms: Int64?
    private(set) var warnings: [String] = []
    private(set) var metrics: [String: Double] = [:]
    private(set) var quality: [EngineQualityRow] = []
    private(set) var segments: [EngineSegmentRow] = []
    private(set) var perGait: [EngineGaitRow] = []
    private(set) var curves: [EngineCurveRow] = []
    private(set) var events: [EngineEventRow] = []
    private(set) var classifier: String = ""
    private(set) var symmetryLabel: String = ""
    private(set) var symmetryAllowed: Bool = false
    private(set) var symmetryControls: [String] = []
    private(set) var fusionSummary: String = ""
    private(set) var t: [Double] = []
    private(set) var speed: [Double] = []
    private(set) var accel: [Double] = []
    private(set) var latAccel: [Double] = []
    private(set) var gaitCode: [Int] = []
    private(set) var girthImu: [Int] = []
    private(set) var girthT: [Double] = []
    private(set) var girthCadenceHz: [Double] = []
    private(set) var girthStatus: [String] = []
    private(set) var girthStrideM: [Double] = []
    private(set) var girthCycleCorrelation: [Double] = []
    private(set) var girthIntervalCv: [Double] = []
    private(set) var girthAmplitudeCv: [Double] = []
    private(set) var girthSpectralStability: [Double] = []
    private(set) var symmetryGroups: [EngineSymmetryGroup] = []
    private(set) var symmetryWindows: Int = 0
    private(set) var rawJson: String = ""
    /// «trabajo_pista»: phases, efforts, course passes and corrections (AVO Track Work, Core/TrackWork.swift).
    private(set) var trackWork: TrackWorkResult = TrackWorkResult()

    private init() {}

    func metric(_ name: String) -> Double? {
        guard let v = metrics[name], v.isFinite else { return nil }
        return v
    }

    private static func f(_ v: Double?, _ decimals: Int, _ unit: String = "") -> String {
        guard let d = v, d.isFinite else { return "—" }
        return AvoFormat.f(d, decimals) + unit
    }

    private static func time(_ s: Double) -> String {
        guard s.isFinite else { return "—" }
        let m = EngineJSON.int(s / 60)
        let r = EngineJSON.int(s.truncatingRemainder(dividingBy: 60))
        return "\(m):" + (r < 0 ? "-" + String(format: "%02d", -r) : String(format: "%02d", r))
    }

    private static func times(_ v: Double?, _ k: Double) -> Double? { v.map { $0 * k } }

    static func gaitText(_ code: String) -> String {
        switch code {
        case "STOPPED": return "Parado"
        case "WALK": return "Paso"
        case "TROT": return "Trote"
        case "CANTER_GALLOP": return "Galope"
        case "TRANSITION": return "Transición"
        case "UNKNOWN": return "Desconocido"
        case "INSUFFICIENT_DATA": return "Datos insuficientes"
        default: return code
        }
    }

    static func parse(_ json: String) throws -> EquineAnalysis {
        typealias J = EngineJSON
        let r = try J.root(json)
        if let err = r["error"] { throw AvoError.invalidData((err as? String) ?? "") }
        if J.str(r, "formato") != "avo-equine-analysis" { throw AvoError.invalidData("no es un resultado del motor AVO") }
        let a = EquineAnalysis()
        a.rawJson = json
        a.engine = J.str(r, "motor")
        a.sessionId = J.str(J.obj(r, "sesion"), "id")
        let c = J.str(r, "cache")
        a.cache = c.isEmpty ? nil : c
        let p = J.obj(r, "procedencia")
        a.mode = J.str(p, "modo")
        a.hasImu = J.bool(p, "tiene_cincha")
        a.itow0Ms = J.num(p, "itow_inicial_ms").map { J.int64($0) }
        a.warnings = J.arr(r, "advertencias").map { ($0 as? String) ?? "" }
        for m in J.objs(r, "metricas") {
            if let v = J.num(m, "valor") { a.metrics[J.str(m, "nombre")] = v }
        }
        for q in J.objs(r, "calidad") {
            a.quality.append(EngineQualityRow(dominio: J.str(q, "dominio"), nivel: J.str(q, "nivel"), motivos: J.strings(q, "motivos")))
        }
        let perf = J.obj(r, "rendimiento")
        a.classifier = J.str(perf, "clasificador")
        for s in J.objs(perf, "segmentos") {
            let t0 = J.num(s, "t0") ?? .nan, t1 = J.num(s, "t1") ?? .nan
            let cadence: String
            if let fz = J.num(s, "cadencia_media_hz") { cadence = f(fz * 60, 0, " /min") }
            else { cadence = a.hasImu ? "—" : "SIN DATOS DE CINCHA" }
            var row = EngineSegmentRow(id: J.int(J.num(s, "id") ?? 0), aire: gaitText(J.str(s, "codigo")), desde: time(t0), hasta: time(t1),
                                       distancia: f(J.num(s, "distancia_m"), 0, " m"),
                                       velocidadMedia: f(times(J.num(s, "velocidad_media"), 3.6), 1, " km/h"),
                                       velocidadMax: f(times(J.num(s, "velocidad_max"), 3.6), 1, " km/h"),
                                       cadencia: cadence, tranco: f(J.num(s, "longitud_tranco_m"), 2, " m"),
                                       corrCiclos: f(J.num(s, "correlacion_ciclos"), 2), cvIntervalos: f(J.num(s, "cv_intervalos"), 3),
                                       calidadGnss: J.str(s, "calidad_gnss"), calidadImu: J.str(s, "calidad_imu"), avisos: J.strings(s, "avisos"))
            row.t0 = t0
            row.t1 = t1
            row.gaitCode = J.str(s, "codigo")
            row.cadenceHz = J.num(s, "cadencia_media_hz")
            row.cycleCorrelation = J.num(s, "correlacion_ciclos")
            row.intervalCv = J.num(s, "cv_intervalos")
            row.strideLengthM = J.num(s, "longitud_tranco_m")
            a.segments.append(row)
        }
        for g in J.objs(perf, "por_aire") {
            a.perGait.append(EngineGaitRow(aire: gaitText(J.str(g, "codigo")), tramos: J.int(J.num(g, "segmentos") ?? 0),
                                           duracion: time(J.num(g, "duracion_s") ?? .nan),
                                           fraccionTiempo: f(times(J.num(g, "fraccion_tiempo"), 100), 0, " %"),
                                           distancia: f(J.num(g, "distancia_m"), 0, " m"),
                                           velocidadMedia: f(times(J.num(g, "velocidad_media"), 3.6), 1, " km/h"),
                                           cadencia: f(times(J.num(g, "cadencia_media_hz"), 60), 0, " /min"),
                                           tranco: f(J.num(g, "longitud_tranco_m"), 2, " m")))
        }
        for c2 in J.objs(J.obj(r, "curvas"), "lista") {
            let t0 = J.num(c2, "t0") ?? .nan
            var row = EngineCurveRow(id: J.int(J.num(c2, "id") ?? 0), direccion: J.str(c2, "direccion"), inicio: time(t0),
                                     giro: f(J.num(c2, "giro_deg"), 0, "°"),
                                     radio: "\(f(J.num(c2, "radio_m"), 1)) ± \(f(J.num(c2, "radio_sigma_m"), 1)) m",
                                     vEntrada: f(times(J.num(c2, "v_entrada"), 3.6), 1, " km/h"),
                                     vSalida: f(times(J.num(c2, "v_salida"), 3.6), 1, " km/h"),
                                     lateralEstimada: "\(f(J.num(c2, "a_lateral_media"), 2)) ± \(f(J.num(c2, "a_lateral_sigma"), 2)) m/s²",
                                     cadencia: f(times(J.num(c2, "cadencia_durante_hz"), 60), 0, " /min"), calidad: J.str(c2, "calidad"))
            row.t0 = t0
            a.curves.append(row)
        }
        for e in J.objs(r, "eventos") {
            let t0 = J.num(e, "t0") ?? .nan
            var row = EngineEventRow(id: J.str(e, "id"), tipo: J.str(e, "tipo"), inicio: time(t0), fin: time(J.num(e, "t1") ?? .nan),
                                     calidad: J.str(e, "calidad"), motivo: J.str(e, "motivo"),
                                     algoritmo: "\(J.str(e, "algoritmo")) \(J.str(e, "version"))")
            row.t0 = t0
            a.events.append(row)
        }
        let fu = J.obj(r, "fusion")
        a.fusionSummary = "Fusión \(J.str(fu, "modo")): \(AvoFormat.f(J.num(fu, "ventanas_ok") ?? 0, 0)) de \(AvoFormat.f(J.num(fu, "ventanas") ?? 0, 0)) ventanas · incertidumbre temporal \(f(J.num(fu, "incertidumbre_temporal_mediana_ms"), 1, " ms"))"
        let sy = J.obj(r, "simetria")
        a.symmetryLabel = J.str(sy, "etiqueta")
        a.symmetryAllowed = J.bool(sy, "conclusiones_permitidas")
        for x in J.objs(sy, "controles") {
            a.symmetryControls.append("\(J.str(x, "control")): \(J.str(x, "estado")) — \(J.str(x, "motivo"))")
        }
        a.symmetryWindows = J.int(J.num(sy, "ventanas_usadas") ?? 0)
        for g in J.objs(sy, "grupos") {
            let la = J.obj(g, "log_cociente_amplitud"), ta = J.obj(g, "asimetria_temporal"), hm = J.obj(g, "similitud_mitades")
            a.symmetryGroups.append(EngineSymmetryGroup(imu: J.int(J.num(g, "imu") ?? 0), gait: J.str(g, "aire"),
                                                        windows: J.int(J.num(g, "ventanas") ?? 0), strides: J.int(J.num(g, "trancos") ?? 0),
                                                        logAmplitudeRatio: J.num(la, "mediana"), amplitudeReproducible: J.bool(la, "reproducible"),
                                                        temporalAsymmetry: J.num(ta, "mediana"), temporalReproducible: J.bool(ta, "reproducible"),
                                                        halfSimilarity: J.num(hm, "mediana")))
        }
        if let se = J.obj(r, "series") {
            a.t = J.doubles(se, "t")
            a.speed = J.doubles(se, "velocidad")
            a.accel = J.doubles(se, "aceleracion")
            a.latAccel = J.doubles(se, "aceleracion_lateral")
            a.gaitCode = J.doubles(se, "aire").map { $0.isFinite ? J.int($0) : -1 }
        }
        if let gi = J.obj(r, "series_cincha") {
            a.girthImu = J.doubles(gi, "imu").map { J.int($0) }
            a.girthT = J.doubles(gi, "t")
            a.girthCadenceHz = J.doubles(gi, "cadencia_hz")
            a.girthStatus = J.arr(gi, "estado").map { ($0 as? String) ?? "" }
            a.girthStrideM = J.doubles(gi, "longitud_tranco_m")
            a.girthCycleCorrelation = J.doubles(gi, "correlacion_ciclos")
            a.girthIntervalCv = J.doubles(gi, "cv_intervalos")
            a.girthAmplitudeCv = J.doubles(gi, "cv_amplitud")
            a.girthSpectralStability = J.doubles(gi, "estabilidad_espectral")
        }
        a.trackWork = TrackWorkResult.parse(J.obj(r, "trabajo_pista"))
        return a
    }

    /// GNSS seconds of a track point (GPS time of week in ms).
    func timeOf(_ gpsWeekMs: Int64) -> Double? {
        guard let t0 = itow0Ms else { return nil }
        var d = gpsWeekMs &- t0
        if d < -302_400_000 { d += 604_800_000 }
        return Double(d) / 1000.0
    }

    /// Array.BinarySearch: index of a match, or ~(insertion point) when absent (ascending array).
    private static func binarySearch(_ a: [Double], _ x: Double) -> Int {
        var lo = 0, hi = a.count - 1
        while lo <= hi {
            let mid = lo + (hi - lo) / 2
            if a[mid] == x { return mid }
            if a[mid] < x { lo = mid + 1 } else { hi = mid - 1 }
        }
        return ~lo
    }

    func gnssAt(_ values: [Double], _ time: Double, maxDt: Double = 0.3) -> Double {
        if t.isEmpty { return .nan }
        var i = EquineAnalysis.binarySearch(t, time)
        if i < 0 {
            i = ~i
            if i > 0 && (i == t.count || abs(t[i - 1] - time) < abs(t[i] - time)) { i -= 1 }
        }
        i = Swift.min(Swift.max(i, 0), t.count - 1)
        return abs(t[i] - time) <= maxDt && i < values.count ? values[i] : .nan
    }

    func cadenceAt(_ time: Double, maxDt: Double = 1.5) -> Double {
        if girthT.isEmpty { return .nan }
        guard let imu = girthImu.min() else { return .nan }
        var best = Double.nan, bd = Double.greatestFiniteMagnitude
        let n = Swift.min(girthT.count, Swift.min(girthImu.count, girthCadenceHz.count))
        for k in 0..<n where girthImu[k] == imu && girthT[k].isFinite && abs(girthT[k] - time) < bd {
            bd = abs(girthT[k] - time)
            best = girthCadenceHz[k]
        }
        return bd <= maxDt ? best : .nan
    }

    func gaitAt(_ time: Double) -> Int {
        if t.isEmpty || gaitCode.count != t.count { return -1 }
        var i = EquineAnalysis.binarySearch(t, time)
        if i < 0 { i = Swift.min(Swift.max(~i - 1, 0), t.count - 1) }
        return abs(t[i] - time) <= 0.5 ? gaitCode[i] : -1
    }
}

enum EquineComparisonRows {
    /// Rows of an avo-equine-comparison result plus a one-line verdict with the reasons.
    static func parse(_ json: String) throws -> (rows: [EngineDiffRow], verdict: String) {
        typealias J = EngineJSON
        let r = try J.root(json)
        if let err = r["error"] { throw AvoError.invalidData((err as? String) ?? "") }
        func n(_ e: [String: Any]?, _ k: String) -> String {
            guard let v = J.num(e, k) else { return "—" }
            return J.esTrim(v, 3)
        }
        func required<T>(_ e: [String: Any]?, _ k: String, _ type: T.Type) throws -> T {
            guard let v = e?[k] as? T else { throw AvoError.invalidData("Falta \(k) en el resultado de la comparación") }
            return v
        }
        func requiredBool(_ e: [String: Any]?, _ k: String) throws -> Bool {
            guard let e = e, let v = AvoJSON.bool(e, k) else { throw AvoError.invalidData("Falta \(k) en el resultado de la comparación") }
            return v
        }
        let diffs = try required(r, "diferencias", [Any].self)
        var rows: [EngineDiffRow] = []
        for item in diffs {
            guard let d = item as? [String: Any] else { throw AvoError.invalidData("Diferencia no válida en la comparación") }
            rows.append(EngineDiffRow(metrica: try required(d, "metrica", String.self), a: n(d, "a"), b: n(d, "b"),
                                      diferencia: n(d, "diferencia"), comparable: try requiredBool(d, "comparable") ? "sí" : "no",
                                      contexto: try required(d, "contexto", String.self)))
        }
        let reasons = try required(r, "motivos", [Any].self).map { ($0 as? String) ?? "" }.joined(separator: "; ")
        let route = try required(r, "recorrido", [String: Any].self)
        var routeText = ""
        if try requiredBool(route, "intentado") {
            if try requiredBool(route, "comparable") {
                routeText = " · mismo recorrido: Δv \(n(route, "diferencia_velocidad_media")) m/s, Δt \(n(route, "diferencia_tiempo_total_s")) s"
            } else {
                routeText = " · recorrido no comparable: " + ((route["motivo"] as? String) ?? "")
            }
        }
        let verdict = (try requiredBool(r, "comparable") ? "Comparables" : "No comparables") + (reasons.isEmpty ? "" : " — " + reasons) + routeText
        return (rows, verdict)
    }
}

enum EquineSection {
    /// Statistics of section "a" of a comparison result (used to analyse a selected interval of one session).
    static func parseA(_ json: String) throws -> [EngineKvRow] {
        let r = try EngineJSON.root(json)
        if let err = r["error"] { throw AvoError.invalidData((err as? String) ?? "") }
        guard let a = r["a"] as? [String: Any] else { throw AvoError.invalidData("Falta la sección a en el resultado") }
        /// decimals < 0 means the .NET "0.##" format (up to 2 decimals, trimmed).
        func n(_ k: String, _ scale: Double = 1, _ decimals: Int = -1, _ unit: String = "") -> String {
            guard let v = EngineJSON.num(a, k) else { return "—" }
            let x = v * scale
            return (decimals < 0 ? EngineJSON.esTrim(x, 2) : AvoFormat.f(x, decimals)) + unit
        }
        return [
            EngineKvRow(metrica: "Duración", valor: n("duracion_s", 1, 1, " s")),
            EngineKvRow(metrica: "Distancia", valor: n("distancia_m", 1, 1, " m")),
            EngineKvRow(metrica: "Velocidad media", valor: n("velocidad_media", 3.6, 1, " km/h")),
            EngineKvRow(metrica: "Velocidad máxima", valor: n("velocidad_max", 3.6, 1, " km/h")),
            EngineKvRow(metrica: "Cadencia", valor: n("cadencia_hz", 60, 0, " /min")),
            EngineKvRow(metrica: "Correlación entre ciclos", valor: n("correlacion_ciclos")),
            EngineKvRow(metrica: "CV intervalos", valor: n("cv_intervalos", 1, 3)),
            EngineKvRow(metrica: "RTK FIX", valor: n("fraccion_fix", 100, 0, " %")),
            EngineKvRow(metrica: "Eventos", valor: n("eventos", 1, 0)),
            EngineKvRow(metrica: "Aire dominante", valor: EquineAnalysis.gaitText((a["aire_dominante"] as? String) ?? "")),
        ]
    }
}
