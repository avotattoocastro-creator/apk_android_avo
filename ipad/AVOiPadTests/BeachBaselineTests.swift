import XCTest
@testable import AVO_Horse

/// Línea base de la playa por franja (motor 2.0.0-dev39, PL2–PL6): «estado.playa» de «avo-training-analysis». La fixture
/// la escribió el motor (avo_training_cli) con 9 sesiones de PSI: 4 en seca profunda (13 m/s → 5,90 m; 15 → 6,60) y
/// 5 en orilla firme (14 → 6,60; 16 → 7,30); la última con humedad 11 %, nota DURO y el 60 % del trabajo en su franja.
final class BeachBaselineTests: XCTestCase {
    private func fixture(_ name: String) throws -> String {
        for b in [Bundle(for: BeachBaselineTests.self), Bundle.main] {
            if let u = b.url(forResource: name, withExtension: "json"), let d = try? Data(contentsOf: u) { return String(decoding: d, as: UTF8.self) }
        }
        throw XCTSkip("\(name).json no está en el paquete de pruebas")
    }

    func testEngineFixture() throws {
        let r: TrainingAnalysisResult = try TrainingAnalysisResult.parse(try fixture("beach_training_history_psi"))
        let p: TrainingBeachBaseline = r.playa
        XCTAssertTrue(p.present && p.available)
        XCTAssertEqual(p.level, "INFO")
        XCTAssertFalse(p.validated)
        XCTAssertEqual(p.beachSessions, 9)
        XCTAssertEqual(p.refBand, "ORILLA_FIRME")
        XCTAssertEqual(p.slopeOrigin, "PROPIA")
        XCTAssertEqual(p.slopeStride ?? 0, 0.35, accuracy: 1e-9)
        XCTAssertEqual(p.commonSpeed ?? 0, 14.5, accuracy: 1e-9)
        XCTAssertEqual(p.bands.count, 2)
        XCTAssertEqual(p.bands[0].band, "ORILLA_FIRME")
        XCTAssertEqual(p.bands[1].strideEffect ?? 0, -0.35, accuracy: 1e-9)
        XCTAssertEqual(p.bands[0].impactsKm.median ?? 0, 1.5, accuracy: 1e-9)
        XCTAssertNil(p.bands[0].v200.median)
        XCTAssertEqual(p.lastSoilClass, "SECA")
        XCTAssertEqual(p.lastImpactsRelative ?? 0, 2, accuracy: 1e-9)
        XCTAssertEqual(p.fastFirm7d, 3)
        XCTAssertEqual(p.marks.count, 4)
        XCTAssertTrue(p.marks.contains { $0.rule == "PL6_RAPIDO_ORILLA_COMPACTA" && $0.sessionId == "O4" })
        XCTAssertEqual(TrainingBeachBaseline.bandTitle("SECA_PROFUNDA"), "Seca profunda")
        XCTAssertEqual(TrainingBeachBaseline.soilTitle("SECA"), "Seca (≤ 13 %)")
        XCTAssertTrue(p.slopeText.hasSuffix("(propia)"))
    }

    func testNullsAndMissingBlock() throws {
        let o: [String: Any] = try EngineJSON.root(#"""
            {"disponible":false,"nivel":"INFO","validado":false,"motivo":"sin sesiones de playa con franja (anotada o automática) en la ventana",
            "sesiones_playa":0,"franja_referencia":null,"pl3":{"pendiente_zancada_m_por_m_s":0.359,"origen_pendiente":"PFAU_2024",
            "pares":0,"velocidad_comun_m_s":null},"franjas":[],"ultima_sesion":null,"rapidos_orilla_firme_7d":0,"marcas":[],"notas":[]}
            """#)
        let p = TrainingBeachBaseline(o)
        XCTAssertTrue(p.present)
        XCTAssertFalse(p.available)
        XCTAssertNil(p.commonSpeed)
        XCTAssertTrue(p.refBand.isEmpty && p.lastBand.isEmpty)
        XCTAssertNil(p.lastImpactsKm)
        XCTAssertEqual(TrainingBeachBaseline.soilTitle(p.lastSoilClass), KbText.noData)
        XCTAssertTrue(p.slopeText.hasSuffix("(Pfau 2024)"))
        // historia sin el bloque (motor anterior): no presente
        let none = TrainingBeachBaseline(nil)
        XCTAssertFalse(none.present || none.available)
        XCTAssertTrue(none.bands.isEmpty)
    }
}
