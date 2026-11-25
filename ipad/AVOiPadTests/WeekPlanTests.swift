import XCTest
@testable import AVO_Horse

/// Capa 2 del planificador (motor 2.0.0-dev35): «estado.planificador.semana_siguiente» de «avo-training-analysis».
/// La fixture la escribió el motor (avo_training_cli) con 42 sesiones diarias de un potro PSI nacido en 2024
/// (350 m rápidos cada 4 días) y una carrera prevista el 17/11/2026; referencia 11/11/2026.
final class WeekPlanTests: XCTestCase {
    private func fixture(_ name: String) throws -> String {
        for b in [Bundle(for: WeekPlanTests.self), Bundle.main] {
            if let u = b.url(forResource: name, withExtension: "json"), let d = try? Data(contentsOf: u) { return String(decoding: d, as: UTF8.self) }
        }
        throw XCTSkip("\(name).json no está en el paquete de pruebas")
    }

    func testEngineFixture() throws {
        let r: TrainingAnalysisResult = try TrainingAnalysisResult.parse(try fixture("plan_training_history_psi"))
        let w: WeekPlan = r.semanaSiguiente
        XCTAssertTrue(w.present && w.available)
        XCTAssertFalse(w.validated)
        XCTAssertEqual(w.from, "2026-11-12")
        XCTAssertEqual(w.to, "2026-11-18")
        XCTAssertEqual(w.phase, "POTRO_2_ANOS")
        XCTAssertEqual(w.phaseText, "Potro de 2 años")
        XCTAssertEqual(w.ageYears, 2)
        XCTAssertEqual(w.ageOrigin, "FECHA_NACIMIENTO")
        XCTAssertEqual(w.fastTarget, 2)
        XCTAssertEqual(w.fastPlanned, 1)
        XCTAssertEqual(w.fastText, "1 de 2 rápidos (no caben más)")
        XCTAssertEqual(w.fastMaxM ?? 0, 400, accuracy: 1e-9)
        XCTAssertEqual(w.fastRefM ?? 0, 350, accuracy: 1e-9)
        XCTAssertNil(w.p5MeanM)
        XCTAssertNil(w.daysSinceBreak)
        XCTAssertEqual(w.days.map { $0.type }, ["LENTO", "RAPIDO", "SUAVE", "LENTO", "LENTO", "CARRERA", "LIBRE"])
        XCTAssertEqual(w.days[1].fastMaxM ?? 0, 400, accuracy: 1e-9)
        XCTAssertNil(w.days[0].fastMaxM)
        XCTAssertEqual(w.days[1].typeText, "Rápido")
        XCTAssertEqual(w.days[6].rules, ["RECUPERACION_RT2", "PLANIFICADOR_P2"])
        XCTAssertEqual(w.notes.map { $0.rule }, ["PLANIFICADOR_DM1", "PLANIFICADOR_P2"])
        XCTAssertEqual(WeekPlan.ruleTitle("PLANIFICADOR_P4"), "P4")
        XCTAssertEqual(WeekPlan.ruleTitle("RECUPERACION_RT2"), "RT2")
        // la propuesta no cambia el estado
        XCTAssertEqual(r.nivel, "NORMAL")
    }

    func testMissingBlock() throws {
        let w = WeekPlan(nil)
        XCTAssertFalse(w.present || w.available)
        XCTAssertTrue(w.days.isEmpty)
        let off = WeekPlan(["disponible": false, "motivo": "planificador desactivado", "dias": [Any](), "pautas": [Any]()])
        XCTAssertTrue(off.present && !off.available)
        XCTAssertEqual(off.reason, "planificador desactivado")
    }

    func testHistoryOptionsBirthYear() throws {
        let opt: String = try XCTUnwrap(TrainingAnalytics.historyOptions(plannedRaces: [], birthYear: 2024))
        XCTAssertEqual(opt, #"{"fecha_nacimiento":"2024-01-01"}"#)
        XCTAssertNil(TrainingAnalytics.historyOptions(plannedRaces: [], birthYear: nil))
        XCTAssertNil(TrainingAnalytics.historyOptions(plannedRaces: [], birthYear: 1800))
    }
}
