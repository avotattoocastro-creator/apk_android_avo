import XCTest
@testable import AVO_Horse

/// Comparables por condiciones en la historia (motor 2.0.0-dev41, TC1–TC4, PC1–PC3, GO1): «estado.condiciones» de
/// «avo-training-analysis». La fixture la escribió el motor con 11 sesiones de PSI en arena (going BUENO, jinete ANA):
/// 8 a 12 °C y 60 % con V200 ≈ 15 m/s y 3 a 31 °C y 75 % (WBGT estimado 34,7 °C) con V200 13,8 m/s; en la última,
/// 62 kg de jinete sobre 450 kg (13,8 %).
final class ConditionsTests: XCTestCase {
    private func fixture(_ name: String) throws -> String {
        for b in [Bundle(for: ConditionsTests.self), Bundle.main] {
            if let u = b.url(forResource: name, withExtension: "json"), let d = try? Data(contentsOf: u) { return String(decoding: d, as: UTF8.self) }
        }
        throw XCTSkip("\(name).json no está en el paquete de pruebas")
    }

    func testEngineFixture() throws {
        let r: TrainingAnalysisResult = try TrainingAnalysisResult.parse(try fixture("cond_training_history_psi"))
        let k: TrainingConditions = r.condiciones
        XCTAssertTrue(k.present && k.available)
        XCTAssertEqual(k.level, "INFO")
        XCTAssertFalse(k.validated)
        XCTAssertEqual(k.lastId, "C10")
        XCTAssertEqual(k.temperatureC ?? 0, 31, accuracy: 1e-9)
        XCTAssertEqual(k.wbgt ?? 0, 34.7, accuracy: 1e-9)
        XCTAssertEqual(k.wbgtOrigin, "ESTIMADO_T_HR")
        XCTAssertEqual(k.heat, "CALOR")
        XCTAssertEqual(k.heatDay, 5)
        XCTAssertEqual(k.goingStratum, "BUENO")
        XCTAssertEqual(k.carriedPct ?? 0, 13.8, accuracy: 1e-9)
        let a9 = try XCTUnwrap(k.rules.first { $0.rule == "A9" })
        XCTAssertEqual(a9.base, 11)
        XCTAssertEqual(a9.kept, 3)
        XCTAssertEqual(a9.heat, 8)
        XCTAssertEqual(a9.excludedText, "Fuera: 8 por calor")
        let a7 = try XCTUnwrap(k.rules.first { $0.rule == "A7" })
        XCTAssertEqual(a7.kept, 1)
        XCTAssertEqual(a7.weight, 10)
        XCTAssertTrue(k.marks.contains { $0.rule == "PC3" && $0.sessionId == "C10" })
        XCTAssertTrue(k.marks.contains { $0.rule == "TC4" })
        XCTAssertTrue(k.heatText.hasPrefix("Calor"))
        XCTAssertEqual(TrainingConditions.stratumTitle("BLANDO"), "Blando")
        XCTAssertEqual(r.nivel, "NORMAL")   // nunca sube el estado
    }

    func testNullsAndMissingBlock() throws {
        let o: [String: Any] = try EngineJSON.root(#"""
            {"disponible":true,"nivel":"INFO","validado":false,"motivo":null,
            "ultima":{"id":"A","fecha":"2026-11-01","temperatura_c":null,"humedad_pct":null,"going":null,"jinete":null,
            "peso_jinete_kg":null,"peso_caballo_kg":null,
            "condiciones":{"wbgt_c":null,"wbgt_origen":null,"calor":null,"estrato_going":null,"peso_cargado_pct":null},
            "dia_periodo_calor":null,"comparables":[]},"marcas":[],"notas":["sin temperatura"]}
            """#)
        let k = TrainingConditions(o)
        XCTAssertTrue(k.present && k.available)
        XCTAssertNil(k.temperatureC)
        XCTAssertNil(k.wbgt)
        XCTAssertNil(k.heatDay)
        XCTAssertEqual(k.weatherText, KbText.noData)
        XCTAssertEqual(k.wbgtText, KbText.noData)
        XCTAssertEqual(k.heatText, KbText.noData)
        XCTAssertEqual(k.weightText, KbText.noData)
        XCTAssertEqual(TrainingConditions.stratumTitle(k.goingStratum), KbText.noData)
        XCTAssertTrue(k.rules.isEmpty)
        let none = TrainingConditions(nil)
        XCTAssertFalse(none.present || none.available)
    }
}
