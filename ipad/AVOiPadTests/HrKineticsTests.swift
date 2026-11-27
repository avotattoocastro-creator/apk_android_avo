import XCTest
@testable import AVO_Horse

/// Cinética de la FC en la historia (motor 2.0.0-dev40, CF2/RC1/FW1/WU3): «estado.cinetica_fc» de
/// «avo-training-analysis». La fixture la escribió el motor (avo_training_cli) con 5 sesiones de PSI en arena con
/// vuelta a la calma al paso: τ 80, 90, 100, 90 y 117 s; THR100 150, 160, 140, 150 y 180 s; FC del trote fijo a 4 m/s
/// 100, 102, 98, 100 y 109 lpm.
final class HrKineticsTests: XCTestCase {
    private func fixture(_ name: String) throws -> String {
        for b in [Bundle(for: HrKineticsTests.self), Bundle.main] {
            if let u = b.url(forResource: name, withExtension: "json"), let d = try? Data(contentsOf: u) { return String(decoding: d, as: UTF8.self) }
        }
        throw XCTSkip("\(name).json no está en el paquete de pruebas")
    }

    func testEngineFixture() throws {
        let r: TrainingAnalysisResult = try TrainingAnalysisResult.parse(try fixture("hrkin_training_history_psi"))
        let k: TrainingHrKinetics = r.cineticaFc
        XCTAssertTrue(k.present && k.available)
        XCTAssertEqual(k.level, "INFO")
        XCTAssertFalse(k.validated)
        XCTAssertEqual(k.ecgSessions, 5)
        XCTAssertEqual(k.lastId, "K4")
        XCTAssertEqual(k.cooldown, "PASO")
        XCTAssertEqual(k.metrics.count, 3)
        XCTAssertEqual(k.metrics[0].metric, "TAU_RECUPERACION")
        XCTAssertEqual(k.metrics[0].value ?? 0, 117, accuracy: 1e-9)
        XCTAssertEqual(k.metrics[0].median ?? 0, 90, accuracy: 1e-9)
        XCTAssertEqual(k.metrics[0].change ?? 0, 30, accuracy: 1e-9)
        XCTAssertTrue(k.metrics[0].marked)
        XCTAssertFalse(k.metrics[1].marked)
        XCTAssertEqual(k.metrics[2].changeUnit, "lpm")
        XCTAssertEqual(k.marks.count, 2)
        XCTAssertTrue(k.marks.contains { $0.rule == "FW1" && $0.sessionId == "K4" })
        XCTAssertEqual(TrainingHrKinetics.cooldownTitle("PASO"), "Al paso")
        XCTAssertTrue(k.metrics[0].changeText.hasPrefix("+30 %"))
        XCTAssertEqual(r.nivel, "NORMAL")
    }

    func testNullsAndMissingBlock() throws {
        let o: [String: Any] = try EngineJSON.root(#"""
            {"disponible":true,"nivel":"INFO","validado":false,"motivo":null,"sesiones_ecg":1,
            "ultima":{"id":"A","fecha":"2026-11-01","vuelta_calma":null,"calentamiento_m":null,"calentamiento_s":null,
            "metricas":[{"metrica":"TAU_RECUPERACION","regla":"CF2","unidad":"s","valor":null,"mediana":null,"mad":null,"n":0,
            "cambio":null,"cambio_unidad":"%","comparables":"x","marcada":false},
            {"metrica":"THR100","regla":"RC1","unidad":"s","valor":140,"mediana":null,"mad":null,"n":1,
            "cambio":null,"cambio_unidad":"%","comparables":"x","marcada":false}]},"marcas":[],"notas":["sin τ"]}
            """#)
        let k = TrainingHrKinetics(o)
        XCTAssertTrue(k.present && k.available)
        XCTAssertNil(k.warmupM)
        XCTAssertNil(k.metrics[0].value)
        XCTAssertEqual(k.metrics[0].valueText, KbText.noData)
        XCTAssertEqual(k.metrics[0].changeText, "Sin dato en la última sesión")
        XCTAssertEqual(k.metrics[1].changeText, "Pocas sesiones comparables (1)")
        XCTAssertEqual(TrainingHrKinetics.cooldownTitle(k.cooldown), KbText.noData)
        let none = TrainingHrKinetics(nil)
        XCTAssertFalse(none.present || none.available)
        XCTAssertTrue(none.metrics.isEmpty)
    }
}
