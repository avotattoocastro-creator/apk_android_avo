import XCTest
@testable import AVO_Horse

/// CG1–CG3 (motor 2.0.0-dev34): «estado.carga_cg» de «avo-training-analysis». La fixture la escribió el motor
/// (avo_training_cli) con 20 sesiones de PSI: 400 m rápidos cada 2 días, ECG con 10 min a 120–125 y 1 min a 200–205 lpm.
final class TrainingLoadCgTests: XCTestCase {
    private func fixture(_ name: String) throws -> String {
        for b in [Bundle(for: TrainingLoadCgTests.self), Bundle.main] {
            if let u = b.url(forResource: name, withExtension: "json"), let d = try? Data(contentsOf: u) { return String(decoding: d, as: UTF8.self) }
        }
        throw XCTSkip("\(name).json no está en el paquete de pruebas")
    }

    func testEngineFixture() throws {
        let r: TrainingAnalysisResult = try TrainingAnalysisResult.parse(try fixture("cg_training_history_psi"))
        let cg: TrainingLoadCg = r.cargaCg
        XCTAssertTrue(cg.present && cg.available)
        XCTAssertEqual(cg.level, "INFO")
        XCTAssertFalse(cg.validated)
        XCTAssertEqual(cg.hrMax ?? 0, 225, accuracy: 1e-9)
        XCTAssertEqual(cg.hrMaxOrigin, "PROPIA_HISTORIA")
        XCTAssertEqual(cg.fastSessionsWithHr, 4)
        XCTAssertEqual(cg.hrMaxText, "225 lpm (propia, 4 trabajos rápidos)")
        XCTAssertEqual(cg.hrRestOrigin, "POR_DEFECTO")
        XCTAssertEqual(cg.externalLoad.total7d ?? 0, 1600, accuracy: 1e-9)
        XCTAssertEqual(cg.externalLoad.total30d ?? 0, 6000, accuracy: 1e-9)
        XCTAssertEqual(cg.externalLoad.ratio ?? 0, 1.17059, accuracy: 1e-4)
        XCTAssertEqual(cg.internalLoad.session ?? 0, 10.3786, accuracy: 1e-3)
        XCTAssertEqual(cg.externalLoad.sessionsWithData, 14)
        XCTAssertTrue(cg.externalLoad.reason.isEmpty)
        XCTAssertEqual(cg.bands.count, 6)
        XCTAssertEqual(cg.bands[0].limitsText, "< 10,0 m/s")
        XCTAssertEqual(cg.bands[2].limitsText, "13,3–14,4 m/s")
        XCTAssertEqual(cg.bands[5].limitsText, "≥ 16,8 m/s")
        XCTAssertEqual(cg.daily.count, 28)
        XCTAssertEqual(cg.scale, "ABSOLUTAS_PSI")
        XCTAssertEqual(TrainingLoadCg.bandTitle("RAPIDO_4"), "Rápido 4")
        // el bloque descriptivo no cambia el estado
        XCTAssertEqual(r.nivel, "NORMAL")
    }

    func testNullsAndMissingBlock() throws {
        let o: [String: Any] = try EngineJSON.root(#"""
            {"disponible":true,"nivel":"INFO","validado":false,"fc_referencia":{"fc_reposo_lpm":33,"fc_reposo_origen":"POR_DEFECTO",
            "fc_max_lpm":213,"fc_max_origen":"POR_DEFECTO","trabajos_rapidos_con_fc":1},"interna":{"sesion":null,"total_corto":0,
            "total_largo":0,"ewma_aguda":null,"ewma_cronica":null,"cociente":null,"monotonia":null,"strain":null,"sesiones_con_dato":0,
            "sesiones_sin_dato":5,"motivo":"historia menor de 28 días"},"externa":{"sesion":400,"total_corto":400,"total_largo":2000,
            "ewma_aguda":120,"ewma_cronica":40,"cociente":null,"monotonia":null,"strain":null,"sesiones_con_dato":5,"sesiones_sin_dato":0,
            "motivo":"historia menor de 28 días"},"bandas":{"escala":null,"bandas":[]},"diaria":[{"fecha":"2026-11-20","rapido_m":null,"trimp":null}],
            "notas":[],"nota":"x"}
            """#)
        let cg = TrainingLoadCg(o)
        XCTAssertNil(cg.internalLoad.ratio)
        XCTAssertNil(cg.externalLoad.ratio)
        XCTAssertEqual(cg.externalLoad.reason, "historia menor de 28 días")
        XCTAssertEqual(cg.internalLoad.sessionsWithoutData, 5)
        XCTAssertEqual(cg.hrMaxText, "213 lpm (por defecto, no propia)")
        XCTAssertNil(cg.daily.first?.fastM)
        XCTAssertTrue(cg.scale.isEmpty)
        // historia sin el bloque (motor anterior): no presente
        XCTAssertFalse(TrainingLoadCg(nil).present)
        XCTAssertFalse(TrainingLoadCg(nil).available)
    }
}
