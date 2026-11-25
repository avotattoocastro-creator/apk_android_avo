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

    /// Motor 2.0.0-dev37 (TRAINING 1.4.0): semana natural de lunes a domingo con lo realizado (boceto del entrenador 25/11/2026).
    func testCalendarWeekWithDoneDays() throws {
        let o: [String: Any] = try EngineJSON.root(#"""
            {"disponible":true,"desde":"2026-11-23","hasta":"2026-11-29","fase":"NORMAL","limitada":false,"edad_anos":3,
             "semana_calendario":true,"planifica_desde":"2026-11-25","rapidos_objetivo":2,"rapidos_hechos":1,"rapidos_propuestos":1,
             "dias":[{"fecha":"2026-11-23","tipo":"RAPIDO","motivo":"realizado: trabajo rápido (600 m de galope rápido)","realizado":true,"rapido_max_m":null,"reglas":[]},
                     {"fecha":"2026-11-24","tipo":"LIBRE","motivo":"sin entrenamiento registrado","realizado":true,"rapido_max_m":null,"reglas":[]},
                     {"fecha":"2026-11-25","tipo":"LENTO","motivo":"trabajo lento","realizado":false,"rapido_max_m":null,"reglas":["PLANIFICADOR_P2"]},
                     {"fecha":"2026-11-26","tipo":"RAPIDO","motivo":"trabajo rápido","realizado":false,"rapido_max_m":null,"reglas":["PLANIFICADOR_P1"]}],
             "pautas":[],"validado":false}
            """#)
        let w: WeekPlan = WeekPlan(o)
        XCTAssertTrue(w.calendarWeek)
        XCTAssertEqual(w.planFrom, "2026-11-25")
        XCTAssertEqual(w.fastDone, 1)
        XCTAssertEqual(w.fastText, "2 de 2 rápidos")
        XCTAssertEqual(w.fastCaption, "1 hecho · 1 propuesto · ≥ 72 h entre rápidos")
        XCTAssertEqual(w.days.map { $0.done }, [true, true, false, false])
        XCTAssertEqual(WeekPlan.weekdayShort("2026-11-23"), "lun")
        XCTAssertEqual(CalendarView.isoDay("2026-11-5"), "2026-11-05")
        XCTAssertEqual(CalendarView.isoDay("2026-1-25"), "2026-01-25")
        // análisis anteriores (dev35, 7 días siguientes): sin campos nuevos
        let old: WeekPlan = WeekPlan(try EngineJSON.root(#"{"disponible":true,"rapidos_objetivo":2,"rapidos_propuestos":1,"dias":[{"fecha":"2026-11-12","tipo":"LENTO"}]}"#))
        XCTAssertFalse(old.calendarWeek)
        XCTAssertEqual(old.fastDone, 0)
        XCTAssertFalse(old.days[0].done)
        XCTAssertEqual(old.fastCaption, "≥ 72 h entre rápidos")
    }
}
