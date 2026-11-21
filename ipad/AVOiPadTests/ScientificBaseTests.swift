import XCTest
@testable import AVO_Horse

/// Base científica KB-1 (pantalla «Base científica»): decodificación de los bloques que escribe el motor.
/// Fixtures copiadas de core/src/test/resources/equine/ (generadas con el motor 2.0.0-dev26, KB-1 1.24.0):
///  · kb_psi_analysis.json: entrenamiento SINTÉTICO de test_racing.cpp («race_session», 140 s, perfil PSI);
///  · kb_training_history_psi.json: historia SINTÉTICA de 34 sesiones (100 días) con A1, A2, A3 y fatiga ósea 7 d activas.
/// Solo verifican la cadena JSON → modelo, no la exactitud con caballos reales.
final class ScientificBaseTests: XCTestCase {
    private func fixture(_ name: String) throws -> [String: Any] {
        for b in [Bundle(for: ScientificBaseTests.self), Bundle.main] {
            if let u = b.url(forResource: name, withExtension: "json"), let d = try? Data(contentsOf: u), let o = AvoJSON.object(d) {
                return o
            }
        }
        throw XCTSkip("\(name).json no está en el paquete de pruebas")
    }

    func testSessionBlockFromEngine() throws {
        let root: [String: Any] = try fixture("kb_psi_analysis")
        let tw: TrackWorkResult = TrackWorkResult.parse(EngineJSON.obj(root, "trabajo_pista"))
        let kb: KbSessionBlock = tw.scientificBase
        XCTAssertTrue(kb.present)
        XCTAssertEqual(kb.base, "AVO_KB_1")
        XCTAssertEqual(kb.racePace ?? 0, 16.7, accuracy: 1e-9)
        XCTAssertEqual(kb.racePaceOrigin, "RAZA")
        XCTAssertEqual(kb.bands.map { $0.code }, ["B1_TRABAJO", "B2_INTERMEDIA", "B3_ALTA"])
        XCTAssertEqual(kb.bands[0].vMin ?? 0, 11, accuracy: 1e-9)
        XCTAssertEqual(kb.bands[1].vMin ?? 0, 0.80 * 16.7, accuracy: 1e-6)
        XCTAssertEqual(kb.bands[2].vMin ?? 0, 0.93 * 16.7, accuracy: 1e-6)
        XCTAssertNil(kb.bands[2].vMax)
        XCTAssertEqual(kb.bands[2].limitsText, "≥ 15,5 m/s")
        XCTAssertEqual(kb.bands[2].distanceM ?? 0, 681.676, accuracy: 1e-3)
        XCTAssertEqual(kb.canterM ?? 0, 341.075, accuracy: 1e-3)
        XCTAssertEqual(kb.gallopM ?? 0, 811.3, accuracy: 1e-3)
        XCTAssertEqual(kb.gallopCut ?? 0, 14, accuracy: 1e-9)
        XCTAssertEqual(kb.bonePct ?? 0, 5.76141, accuracy: 1e-5)
        XCTAssertEqual(kb.boneLowPct ?? 0, 0.160781, accuracy: 1e-6)
        XCTAssertEqual(kb.calibrated, true)
        // últimos 600 m del trabajo rápido
        XCTAssertEqual(tw.efforts.count, 1)
        XCTAssertEqual(tw.efforts[0].speedLast600 ?? 0, 16.0174, accuracy: 1e-4)
        XCTAssertNotNil(tw.efforts[0].last600S)
    }

    func testSessionBlockWithoutRacePaceIsNoData() throws {
        // Bloque tal cual sale en synthetic_analysis.json (perfil GENERICO, sin ritmo de carrera) y raza árabe sin calibrar.
        let json: String = #"""
            {"modulo":"AVO_TRACK_WORK","perfil":{"raza":"ARABE"},"base_cientifica":{"base":"AVO_KB_1","version":"1.24.0","v_carrera_m_s":null,
            "v_carrera_origen":"SIN_REFERENCIA","bandas":[{"banda":"B1_TRABAJO","v_min":9,"v_max":null,"distancia_m":0,"tiempo_s":0},
            {"banda":"B2_INTERMEDIA","v_min":null,"v_max":null,"distancia_m":0,"tiempo_s":0},{"banda":"B3_ALTA","v_min":null,"v_max":null,
            "distancia_m":0,"tiempo_s":0}],"verheyen":{"canter_v_min":null,"corte_galope_m_s":null,"canter_m":null,"galope_rapido_m":null},
            "fatiga_osea":{"algoritmo":"SBFL_MORRICE_WEST_2022","pct":0,"pct_extrapolado_lento":0,"calibrado":false}},"trabajos":{"lista":[]}}
            """#
        let root: [String: Any] = try EngineJSON.root(json)
        let kb: KbSessionBlock = TrackWorkResult.parse(root).scientificBase
        XCTAssertTrue(kb.present)
        XCTAssertFalse(kb.hasRacePace)
        XCTAssertNil(kb.canterM)
        XCTAssertNil(kb.gallopM)
        XCTAssertEqual(KbText.metres(kb.canterM), "sin datos")
        XCTAssertEqual(kb.bands[1].limitsText, "sin datos")
        XCTAssertEqual(kb.bands[0].limitsText, "≥ 9,0 m/s")
        XCTAssertEqual(kb.calibrated, false)
        // sin bloque: no presente (análisis anteriores a KB-1)
        XCTAssertFalse(TrackWorkResult.parse(["modulo": "AVO_TRACK_WORK"]).scientificBase.present)
    }

    func testHistoryStatusAndRules() throws {
        let root: [String: Any] = try fixture("kb_training_history_psi")
        let data: Data = try JSONSerialization.data(withJSONObject: root)
        let r: TrainingAnalysisResult = try TrainingAnalysisResult.parse(String(decoding: data, as: UTF8.self))
        let kb: KbHistoryStatus = r.baseCientifica
        XCTAssertTrue(kb.present && kb.available)
        XCTAssertEqual(kb.version, "1.24.0")
        XCTAssertTrue(kb.d7.present && kb.d30.present && kb.prev30.present && kb.d60.present)
        XCTAssertGreaterThan(kb.d30.canterM ?? 0, 44_000)
        XCTAssertGreaterThan(kb.d30.gallopM ?? 0, 6_000)
        XCTAssertEqual(kb.daysWithoutFastWork, 0)
        XCTAssertNil(kb.returnDay)
        XCTAssertNotNil(kb.gallopRatio)
        XCTAssertNotNil(kb.gallopRatioDays60)
        XCTAssertNotNil(kb.boneRatio7d)
        XCTAssertEqual(Set(kb.rules.map { $0.rule }), ["A1_CANTER_30D", "A2_GALOPE_30D", "A3_RAMPA", "KB_FATIGA_OSEA_7D"])
        let a1: KbRule = try XCTUnwrap(kb.rule("A1_CANTER_30D"))
        XCTAssertEqual(a1.level, "VIGILAR")
        XCTAssertEqual(a1.action, "LIMITAR")
        XCTAssertTrue(a1.evidence.contains("Verheyen 2006"))
        XCTAssertEqual(a1.code, "A1")
        XCTAssertEqual(try XCTUnwrap(kb.rule("KB_FATIGA_OSEA_7D")).action, "AVISO")
        XCTAssertEqual(KbRule.code("KB_FATIGA_OSEA_7D"), "FO 7 d")
        // cada sesión trae su estado y el resumen compacto de carga
        XCTAssertEqual(r.sesiones.count, 34)
        let last: TrainingSessionResult = try XCTUnwrap(r.sesiones.last)
        XCTAssertTrue(last.baseCientifica.present)
        let load: KbSummaryLoad = try XCTUnwrap(last.resumen?.trabajoPista?.baseCientifica)
        // fixture: bandas_m [3200, 500, 0]; los 900 m son de galope rápido (> 14 m/s), por debajo de B3 (≥ 0,93 · 16,7 m/s)
        XCTAssertEqual(load.bandsM[0] ?? -1, 3200, accuracy: 1e-9)
        XCTAssertEqual(load.bandsM[1] ?? -1, 500, accuracy: 1e-9)
        XCTAssertEqual(load.bandsM[2] ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(load.bonePct ?? 0, 2.4, accuracy: 1e-9)
    }

    func testHistoryNullsStayNil() throws {
        let o: [String: Any] = try EngineJSON.root(#"""
            {"base":"AVO_KB_1","version":"1.24.0","disponible":true,"d7":{"bandas_m":[null,0,0],"canter_m":null,"galope_rapido_m":0,"fatiga_osea_pct":null,
            "sesiones":0,"sesiones_sin_datos":2},"fatiga_osea_mediana_semanal_pct":null,"fatiga_osea_ratio_7d":null,"dias_sin_trabajo_rapido":null,
            "dias_galope_60d":0,"cociente_galope":null,"vuelta_descanso":{"dia":3,"dias_sin_rapido_antes":95},"reglas":[{"regla":"A6_VUELTA_TENDON",
            "nivel":"VIGILAR","accion":"LIMITAR","texto":"día 3 de la vuelta","evidencia":"Choi & Parkin 2025"}]}
            """#)
        let kb: KbHistoryStatus = KbHistoryStatus(o)
        XCTAssertNil(kb.d7.bandsM[0])
        XCTAssertNil(kb.d7.canterM)
        XCTAssertEqual(kb.d7.sessionsWithoutData, 2)
        XCTAssertFalse(kb.d30.present)
        XCTAssertNil(kb.boneRatio7d)
        XCTAssertNil(kb.daysWithoutFastWork)
        XCTAssertEqual(KbText.days(kb.daysWithoutFastWork), "sin datos")
        XCTAssertNil(kb.gallopRatio)
        XCTAssertEqual(kb.returnDay, 3)
        XCTAssertEqual(kb.returnRestDays, 95)
        XCTAssertEqual(kb.rules.first?.title, "Vuelta tras descanso largo (≥ 90 días)")
        XCTAssertEqual(KbText.sentence("día 3 de la vuelta"), "Día 3 de la vuelta.")
        // historia sin bloque KB: no presente
        XCTAssertFalse(KbHistoryStatus(nil).present)
    }
}
