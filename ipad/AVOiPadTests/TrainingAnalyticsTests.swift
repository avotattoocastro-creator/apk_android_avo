import XCTest
@testable import AVO_Horse

/// AVO Training Analytics 1.0.0 through the real C API (EquineEngine.trainingSummary / trainingAnalyse) with SYNTHETIC
/// session summaries, mirroring equine-intelligence/tests/test_training.cpp, and decoding into the Swift models.
final class TrainingAnalyticsTests: XCTestCase {
    /// 2026-02-16 (D0 of test_training.cpp) + days, as "AAAA-MM-DD".
    private func day(_ offset: Int) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let d0: Date = cal.date(from: DateComponents(year: 2026, month: 2, day: 16))!
        return TrainingAnalytics.dayText(cal.date(byAdding: .day, value: offset, to: d0)!)
    }

    private func gait(_ minutes: Double, speed: Double, stride: Double, cadence: Double, corr: Double, cv: Double) -> [String: Any] {
        let has: Bool = minutes > 0
        return ["duracion_s": minutes * 60, "distancia_m": minutes * 60 * speed,
                "velocidad_media": has ? speed : NSNull(), "velocidad_max": has ? speed * 1.1 : NSNull(),
                "longitud_tranco_m": has ? stride : NSNull(), "cadencia_hz": has ? cadence : NSNull(),
                "correlacion_ciclos": has ? corr : NSNull(), "cv_intervalos": has ? cv : NSNull()]
    }

    /// Same session as make() of test_training.cpp, as an «avo-training-session» object.
    private func summary(_ id: String, _ dayOffset: Int, _ walk: Double, _ trot: Double, _ canter: Double,
                         trotStride: Double = 2.4, trotCorr: Double = 0.90, canterSpeed: Double = 9.0) -> [String: Any] {
        [
            "formato": "avo-training-session", "version_formato": 1, "id": id, "caballo": "LUNA", "jinete": "",
            "fecha_utc": day(dayOffset), "tiempo_movimiento_s": (walk + trot + canter) * 60, "distancia_m": 0,
            "velocidad_max": NSNull(), "distancia_alta_velocidad_m": 0, "tiene_cincha": true,
            "aires": [
                "PASO": gait(walk, speed: 1.6, stride: 1.6, cadence: 0.95, corr: 0.88, cv: 0.05),
                "TROTE": gait(trot, speed: 3.6, stride: trotStride, cadence: 1.45, corr: trotCorr, cv: 0.04),
                "GALOPE": gait(canter, speed: canterSpeed, stride: 4.5, cadence: 1.9, corr: 0.85, cv: 0.05),
            ],
            "aceleraciones": ["sostenidas": 0, "frenadas_sostenidas": 0, "picos_laterales": 0],
            "calidad": ["gnss": "BUENA", "imu": "BUENA"],
            "valoracion": ["rpe": NSNull(), "estado": "", "nota": ""],
            "pista": ["superficie": "", "estado": ""],
            "avisos": [String](),
        ]
    }

    private func input(_ sessions: [[String: Any]], extra: [String: Any] = [:]) -> String {
        var list: [Any] = []
        for s in sessions {
            var e: [String: Any] = extra
            e["resumen"] = s
            list.append(e)
        }
        return String(decoding: AvoJSON.data(["caballo": "LUNA", "sesiones": list]), as: UTF8.self)
    }

    func testSteadyLoadComputesAcwr() async throws {
        var v: [[String: Any]] = []
        for w in 0..<6 {
            for d in [0, 1, 3, 4, 5] { v.append(summary("S\(w * 7 + d)", w * 7 + d, 15, 20, 5)) }
        }
        let json: String = try await EquineEngine.trainingAnalyse(inputJson: input(v), optionsJson: nil)
        let r: TrainingAnalysisResult = try TrainingAnalysisResult.parse(json)
        XCTAssertEqual(r.formato, "avo-training-analysis")
        XCTAssertEqual(r.sesionesUsadas, 30)
        XCTAssertEqual(r.sesiones.count, 30)
        XCTAssertEqual(r.sesiones[0].carga.externa ?? -1, 105, accuracy: 1e-9, "15·1 + 20·3 + 5·6")
        XCTAssertNil(r.sesiones[3].carga.acwr, "Sin 28 días de historia no hay ACWR")
        let acwr: Double = try XCTUnwrap(r.carga.acwr, "ACWR calculado")
        XCTAssertEqual(acwr, 1.0, accuracy: 0.12)
        XCTAssertEqual(r.nivel, "NORMAL")
        XCTAssertEqual(r.acwrOutOfBand, false)
        XCTAssertEqual(r.diasDesdeUltima, 0)
        XCTAssertEqual(r.cargaDiaria.count, 28)
        XCTAssertEqual(r.acwrHigh, 1.5, accuracy: 1e-9)
        XCTAssertEqual(r.acwrLow, 0.8, accuracy: 1e-9)
        XCTAssertFalse(r.nota.isEmpty, "Nota: orientativo, no es un diagnóstico")
        XCTAssertNotNil(r.lastSession?.resumen, "Cada sesión trae su resumen")
    }

    func testBaselineNeedsFourSessionsAndZFlags() async throws {
        var v: [[String: Any]] = []
        let strides: [Double] = [2.40, 2.42, 2.38, 2.41, 2.39, 2.40, 2.43, 2.37]
        for i in 0..<8 { v.append(summary("N\(i)", 2 * i, 15, 20, 5, trotStride: strides[i], trotCorr: 0.90 + 0.005 * Double(i % 3))) }
        v.append(summary("BAJO", 16, 15, 20, 5, trotStride: 2.10))      // z ≈ −6 → REVISAR
        v.append(summary("MEDIO", 18, 15, 20, 5, trotStride: 2.28))     // z ≈ −2,5 → VIGILAR
        let r: TrainingAnalysisResult = try TrainingAnalysisResult.parse(
            try await EquineEngine.trainingAnalyse(inputJson: input(v), optionsJson: nil))
        func session(_ id: String) -> TrainingSessionResult? { r.sesiones.first { $0.id == id } }

        // fewer than 4 previous sessions: no baseline, no deviation
        XCTAssertNil(session("N2")?.deviation("TROTE.longitud_tranco_m"))
        XCTAssertNotNil(session("N4")?.deviation("TROTE.longitud_tranco_m"), "Con 4 sesiones previas ya hay línea base")

        let low: TrainingDeviation = try XCTUnwrap(session("BAJO")?.deviation("TROTE.longitud_tranco_m"))
        XCTAssertEqual(low.nivel, "REVISAR")
        XCTAssertEqual(low.direccion, "MENOR")
        XCTAssertEqual(low.n, 8)
        XCTAssertEqual(low.flag, "REVISAR")
        XCTAssertLessThanOrEqual(low.z ?? 0, -3)
        XCTAssertEqual(session("BAJO")?.nivel, "REVISAR")

        let mid: TrainingDeviation = try XCTUnwrap(session("MEDIO")?.deviation("TROTE.longitud_tranco_m"))
        let z: Double = try XCTUnwrap(mid.z)
        XCTAssertTrue(abs(z) >= 2 && abs(z) < 3, "z = \(z)")
        XCTAssertEqual(mid.nivel, "VIGILAR")
        XCTAssertEqual(mid.flag, "VIGILAR")
        XCTAssertEqual(session("MEDIO")?.nivel, "VIGILAR")
        // the last session was today: the state of the horse goes up to VIGILAR, with the reason
        XCTAssertEqual(r.nivel, "VIGILAR")
        XCTAssertTrue(r.motivos.contains { $0.contains("TROTE.longitud_tranco_m") }, r.motivos.joined(separator: " | "))
        // speed is informative: never flagged by the Swift model
        if let sp = session("MEDIO")?.deviation("GALOPE.velocidad_media") { XCTAssertTrue(sp.isInformative && sp.flag == "NORMAL") }
    }

    func testTrainerRatingAndSrpe() async throws {
        var v: [[String: Any]] = []
        for i in 0..<5 { v.append(summary("S\(i)", i, 10, 20, 0)) }
        let r: TrainingAnalysisResult = try TrainingAnalysisResult.parse(
            try await EquineEngine.trainingAnalyse(inputJson: input(v, extra: ["valoracion": ["rpe": 5, "estado": "COJERA"]]), optionsJson: nil))
        XCTAssertEqual(r.sesiones.first?.carga.srpe ?? -1, 150, accuracy: 1e-9, "sRPE = RPE × minutos")
        XCTAssertEqual(r.nivel, "REVISAR", "COJERA → REVISAR")
        XCTAssertEqual(r.lastSession?.resumen?.estado, "COJERA")
        XCTAssertEqual(r.lastSession?.resumen?.rpe ?? -1, 5, accuracy: 1e-9)
    }

    func testSummaryWrapperAndErrors() async throws {
        let analysis: String = #"{"formato":"avo-equine-analysis","sesion":{"id":"Q","caballo":"LUNA","inicio_utc":null},"rendimiento":{"segmentos":[]}}"#
        let rating = TrainingRating(rpe: 7, estado: "BIEN", nota: "suelto", pista: TrainingTrack(superficie: "arena", estado: "buena"))
        let extra: String = TrainingAnalytics.extraJson(id: "Q", horse: "H0001", rider: "ANA", dateUtc: "2026-10-31T08:00:00Z", rating: rating)
        let text: String = try EquineEngine.trainingSummary(analysisJson: analysis, extraJson: extra)
        let s: TrainingSessionSummary = try TrainingSessionSummary.parse(text)
        XCTAssertEqual(s.id, "Q")
        XCTAssertEqual(s.caballo, "H0001", "La identidad estable de la Cuadra sustituye al nombre del archivo")
        XCTAssertEqual(s.jinete, "ANA")
        XCTAssertEqual(s.fechaUtc, "2026-10-31T08:00:00Z")
        XCTAssertEqual(s.rpe ?? -1, 7, accuracy: 1e-9)
        XCTAssertEqual(s.estado, "BIEN")
        XCTAssertEqual(s.nota, "suelto")
        XCTAssertEqual(s.superficie, "arena")
        XCTAssertEqual(s.estadoPista, "buena")

        // RPE outside 0–10 is not used
        let t2: String = try EquineEngine.trainingSummary(analysisJson: analysis, extraJson: #"{"fecha_utc":"2026-10-31","valoracion":{"rpe":12,"estado":"BIEN"}}"#)
        XCTAssertNil(try TrainingSessionSummary.parse(t2).rpe)

        XCTAssertThrowsError(try EquineEngine.trainingSummary(analysisJson: #"{"formato":"x"}"#, extraJson: nil))
        do {
            _ = try await EquineEngine.trainingAnalyse(inputJson: "{}", optionsJson: nil)
            XCTFail("Sin «sesiones» debe fallar")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        do {
            _ = try await EquineEngine.trainingAnalyse(inputJson: input([summary("A", 0, 10, 10, 0)]), optionsJson: #"{"dias_aguda":40}"#)
            XCTFail("Opciones no válidas deben fallar")
        } catch {
            XCTAssertFalse(error is CancellationError)
        }
        let cancel = EngineCancelFlag()
        cancel.cancel()
        XCTAssertThrowsError(try EquineEngine.trainingAnalyseSync(inputJson: input([summary("A", 0, 10, 10, 0)]), optionsJson: nil, cancel: cancel)) {
            XCTAssertTrue($0 is CancellationError)
        }
    }

    func testRatingStoreRoundTripAndTolerantDecoding() throws {
        let dir: String = AvoFiles.join(NSTemporaryDirectory(), "AVOTrainingTests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let file: String = AvoFiles.join(dir, "valoraciones.json")
        let r = TrainingRating(rpe: 6, estado: "CANSADO", nota: nil, pista: TrainingTrack(superficie: "playa", estado: "dura"))
        try TrainingRatingStore.save(["S1": r], to: file)
        XCTAssertEqual(TrainingRatingStore.load(file)["S1"], r)
        // unknown keys and wrong types do not lose the other entries
        try AvoFiles.writeAtomic(Data(#"{"A":{"rpe":"siete","estado":"RARO","otra":1},"B":{"rpe":4.0},"C":5}"#.utf8), to: file)
        let all: [String: TrainingRating] = TrainingRatingStore.load(file)
        XCTAssertEqual(all["A"]?.estado, "RARO")
        XCTAssertNil(all["A"]?.rpe)
        XCTAssertEqual(all["B"]?.rpe, 4)
        XCTAssertNil(all["C"])
        // tolerant model decoding: missing keys → nil, not an error
        let a = try XCTUnwrap(TrainingAnalysisResult(["formato": "avo-training-analysis"]))
        XCTAssertEqual(a.nivel, "NORMAL")
        XCTAssertNil(a.carga.acwr)
        XCTAssertTrue(a.sesiones.isEmpty)
        XCTAssertNil(TrainingAnalysisResult(["formato": "otra"]))
    }
}
