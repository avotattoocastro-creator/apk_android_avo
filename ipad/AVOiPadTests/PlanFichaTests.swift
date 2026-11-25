import XCTest
@testable import AVO_Horse

/// Ficha del Calendario (boceto del entrenador 25/11/2026): recomendado frente a realizado, recomendaciones guardadas
/// (planes_recomendados.json) e informe PDF.
final class PlanFichaTests: XCTestCase {
    private func day(_ date: String, _ type: String, done: Bool = false, fast: Double? = nil, max: Double? = nil) -> WeekPlanDay {
        var d = WeekPlanDay(date: date, type: type, reason: done ? "realizado" : "propuesta", fastMaxM: max, rules: done ? [] : ["PLANIFICADOR_P1"])
        d.done = done
        d.doneFastM = fast
        return d
    }

    private func session() -> PlanFichaSession {
        PlanFichaSession(id: "S1", start: Date(timeIntervalSince1970: 1_795_000_000), rider: "Wilson", distanceKm: 7.15, durationS: 2400)
    }

    func testComparison() {
        var f = PlanFicha(horseKey: "H1", horseName: "POWER GOLD", day: "2026-11-26")
        XCTAssertTrue(f.comparison.isEmpty)          // sin entrenamiento: solo la recomendación
        XCTAssertNil(f.matches)
        f.recommended = day("2026-11-26", "RAPIDO", max: 600)
        f.sessions = [session()]
        f.realized = day("2026-11-26", "RAPIDO", done: true, fast: 550)
        XCTAssertEqual(f.matches, true)
        XCTAssertEqual(f.comparison.first, "Cumplido: se recomendaba trabajo rápido y se hizo.")
        XCTAssertTrue(f.comparison[1].contains("dentro del tope"))
        f.realized = day("2026-11-26", "RAPIDO", done: true, fast: 800)
        XCTAssertEqual(f.matches, false)
        XCTAssertTrue(f.comparison[1].contains("por encima del tope"))
        f.realized = day("2026-11-26", "LENTO", done: true, fast: 0)
        XCTAssertEqual(f.matches, false)
        XCTAssertTrue(f.comparison[0].hasPrefix("Se recomendaba trabajo rápido y no se hizo"))
        f.recommended = day("2026-11-26", "SUAVE")
        XCTAssertEqual(f.matches, true)
        f.recommended = day("2026-11-26", "LIBRE")
        XCTAssertEqual(f.matches, false)
        XCTAssertEqual(f.comparison[0], "Se entrenó en un día recomendado como libre.")
        f.recommended = nil
        XCTAssertEqual(f.comparison, ["Sin recomendación del planificador para ese día."])
    }

    func testRecommendationStoreKeepsPastDays() throws {
        let plan: WeekPlan = WeekPlan(try EngineJSON.root(#"""
            {"disponible":true,"fase":"NORMAL","semana_calendario":true,"rapidos_objetivo":2,"rapidos_propuestos":1,"rapidos_hechos":1,
             "dias":[{"fecha":"2026-11-23","tipo":"RAPIDO","motivo":"realizado","realizado":true,"reglas":[]},
                     {"fecha":"2026-11-25","tipo":"LENTO","motivo":"trabajo lento","realizado":false,"reglas":["PLANIFICADOR_P2"]},
                     {"fecha":"2026-11-26","tipo":"RAPIDO","motivo":"trabajo rápido","realizado":false,"rapido_max_m":600,"reglas":["PLANIFICADOR_P1"]}]}
            """#))
        var book: RecommendationStore.Book = [:]
        XCTAssertTrue(RecommendationStore.merge(&book, horseKey: "H1", plan: plan, today: "2026-11-25", now: Date(), engine: "2.0.0-dev38"))
        XCTAssertNil(book["H1"]?["2026-11-23"])                 // lo realizado no es una recomendación
        XCTAssertEqual(book["H1"]?["2026-11-26"]?.type, "RAPIDO")
        XCTAssertEqual(book["H1"]?["2026-11-26"]?.fastMaxM ?? 0, 600, accuracy: 1e-9)
        XCTAssertFalse(RecommendationStore.merge(&book, horseKey: "H1", plan: plan, today: "2026-11-25", now: Date(), engine: "x"))   // sin cambios
        // un día ya pasado no se sobrescribe aunque el plan nuevo lo cambie
        XCTAssertFalse(RecommendationStore.merge(&book, horseKey: "H1", plan: plan, today: "2026-11-27", now: Date(), engine: "x"))
        let path: String = NSTemporaryDirectory() + "planes_recomendados_test.json"
        RecommendationStore.save(book, to: path)
        XCTAssertEqual(RecommendationStore.load(path)["H1"]?["2026-11-25"]?.type, "LENTO")
        try? FileManager.default.removeItem(atPath: path)
    }

    func testPdfIsBuilt() {
        var f = PlanFicha(horseKey: "H1", horseName: "POWER GOLD", day: "2026-11-26")
        f.recommended = day("2026-11-26", "RAPIDO", max: 600)
        f.recommendedOrigin = "Recomendación actual del planificador"
        f.sessions = [session()]
        f.realized = day("2026-11-26", "RAPIDO", done: true, fast: 550)
        let data: Data = PlanFichaPdf.build(f).save()
        XCTAssertGreaterThan(data.count, 1000)
        XCTAssertEqual(String(decoding: data.prefix(5), as: UTF8.self), "%PDF-")
        XCTAssertEqual(PlanFichaPdf.fileName(f), "POWER_GOLD_2026-11-26_0000_Planificador.pdf")
        XCTAssertEqual(WeekPlansModel.shift("2026-11-01", -1), "2026-10-31")
    }
}
