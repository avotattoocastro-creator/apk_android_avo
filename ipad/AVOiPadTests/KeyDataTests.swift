import XCTest
@testable import AVO_Horse

/// Paridad iPad ↔ PC: el MISMO JSON y los MISMOS valores esperados que windows/AVO.Windows.SelfTest (KeyData).
final class KeyDataTests: XCTestCase {
    static let json: String = """
    {"formato":"avo-equine-analysis","metricas":[{"nombre":"distancia","valor":7840.4},{"nombre":"duracion","valor":2652},
    {"nombre":"velocidad_maxima","valor":18.0555},{"nombre":"tiempo_PASO","valor":2000},{"nombre":"tiempo_TROTE","valor":330},
    {"nombre":"tiempo_GALOPE","valor":322},{"nombre":"tiempo_en_curva","valor":50}],
    "rtk":{"total_s":2652,"fix_s":0,"float_s":0,"dgnss_s":2400,"gnss_s":252},
    "trabajo_pista":{"perfil":{"v_referencia":[14,16]},"trabajos":{"v_max":18.0555,"mejor_200m_s":11.36,"distancia_rapida_m":1600,"lista":[
    {"id":1,"tipo":"TRABAJO_RAPIDO","t0":10,"t1":110,"distancia_m":1600,"duracion_s":100,"v_max":18.0555,
    "parciales":[{"desde_m":0,"hasta_m":200,"tiempo_s":12.5,"v":16},{"desde_m":200,"hasta_m":400,"tiempo_s":11.36,"v":17.6056},{"desde_m":400,"hasta_m":600,"tiempo_s":12.0,"v":16.6667}],
    "mejores":[{"distancia_m":200,"tiempo_s":11.36,"t0":40},{"distancia_m":600,"tiempo_s":35.31,"t0":30},{"distancia_m":1000,"tiempo_s":60.42,"t0":20}],"l_max_m":7.3,"f_max_hz":2.36,
    "referencia":[{"v":14,"f_hz":2.2,"l_m":6.4},{"v":16,"f_hz":null,"l_m":null}]},
    {"id":2,"tipo":"GALOPE_TRABAJO","t0":300,"t1":380,"mejores":[{"distancia_m":200,"tiempo_s":12.1},{"distancia_m":600,"tiempo_s":37.0}],"l_max_m":6.9,
    "referencia":[{"v":14,"f_hz":2.0,"l_m":6.8},{"v":16,"f_hz":null,"l_m":null}]}]}}}
    """

    func testKeyDataFromEngineJson() {
        let k: KeyData = KeyData.from(json: Self.json)
        XCTAssertTrue(k.hasEngine)
        func v(_ id: String) -> String { k.tiles.first { $0.id == id }?.value ?? "?" }
        XCTAssertEqual(v("vmax"), "65,0")
        XCTAssertEqual(v("best200"), "11,36")
        XCTAssertEqual(k.best200S ?? 0, 11.36, accuracy: 0.006)   // Cuadra/Jinetes «Mejor 200 m»
        XCTAssertEqual(v("best600"), "35,31")
        XCTAssertEqual(v("workdist"), "1,60")
        let wd: KeyTile? = k.tiles.first { $0.id == "workdist" }
        XCTAssertTrue((wd?.t1 ?? 0) > (wd?.t0 ?? 0))   // opens the charts on the work, like Windows
        XCTAssertEqual(v("distance"), "7,84")
        XCTAssertEqual(v("duration"), "44:12")
        XCTAssertEqual(v("hrmax"), "—")
        XCTAssertEqual(v("lmax"), "7,30")
        XCTAssertEqual(v("fmax"), "2,36")
        XCTAssertEqual(k.gaits.map { $0.id }, ["PASO", "TROTE", "GALOPE"])
        XCTAssertEqual(k.qualityLabel, "DGNSS")
        XCTAssertEqual(k.fixShare ?? -1, 0, accuracy: 1e-9)
    }

    func testBestWindowsReferenceStrideAndSplits() {
        let k: KeyData = KeyData.from(json: Self.json)
        func t(_ id: String) -> KeyTile? { k.tiles.first { $0.id == id } }
        XCTAssertEqual(t("best600")?.t0 ?? -1, 30, accuracy: 1e-9)
        XCTAssertEqual(t("best600")?.t1 ?? -1, 65.31, accuracy: 1e-9)
        XCTAssertEqual(t("best600")?.caption, "Trabajo 1 · ver en gráficas")
        XCTAssertEqual(k.tiles.filter { $0.group == 0 }.count, 6)
        XCTAssertEqual(k.tiles.filter { $0.group == 1 }.map { $0.id }, ["hrmax", "rec2", "hrend"])
        XCTAssertEqual(k.tiles.filter { $0.group == 2 }.map { $0.id }, ["lmax", "fmax", "lref1", "fref1", "lref2"])
        XCTAssertEqual(t("lref1")?.label, "Tranco a 50 km/h")
        XCTAssertEqual(t("lref1")?.value, "6,60")
        XCTAssertEqual(t("fref1")?.value, "2,10")
        XCTAssertEqual(t("lref2")?.label, "Tranco a 58 km/h")
        XCTAssertEqual(t("lref2")?.value, "—")
        XCTAssertEqual(t("lref2")?.caption, "Sin galope a esa velocidad")
        XCTAssertEqual(k.efforts.count, 1)
        let e: KeyEffort = k.efforts[0]
        XCTAssertEqual(e.kind, "Trabajo rápido")
        XCTAssertEqual(e.summary, "1600 m · 01:40 · máx. 65,0 km/h")
        XCTAssertEqual(e.splits.map { $0.label }, ["0–200 m", "200–400 m", "400–600 m"])
        XCTAssertEqual(e.splits.map { $0.timeText }, ["12,50", "11,36", "12,00"])
        XCTAssertEqual(e.splits.map { $0.speedText }, ["57,6", "63,4", "60,0"])
        XCTAssertEqual(e.splits.map { $0.fastest }, [false, true, false])
        XCTAssertEqual(e.splits[1].t0, 22.5, accuracy: 1e-9)
        XCTAssertEqual(e.splits[1].t1, 33.86, accuracy: 1e-9)
    }

    func testSessionNavigator() {
        let d = Date(timeIntervalSince1970: 1_762_590_000)
        let e: [CalendarEntry] = [
            CalendarEntry(id: "a", start: d, horse: "Zakina", durationS: 0, distanceKm: 0, fixShare: nil),
            CalendarEntry(id: "b", start: d.addingTimeInterval(3600), horse: "Maalwina", durationS: 0, distanceKm: 0, fixShare: nil),
            CalendarEntry(id: "c", start: d.addingTimeInterval(-86400), horse: "Árabe Test", durationS: 0, distanceKm: 0, fixShare: nil),
        ]
        let g: [NavGroup] = SessionNavigator.groups(e)
        XCTAssertEqual(g.map { $0.title }, ["SÁB 8 NOV 2025", "VIE 7 NOV 2025"])
        XCTAssertEqual(g[0].entries.map { $0.id }, ["b", "a"])
        XCTAssertEqual(SessionNavigator.itemText(g[0].entries[0]), "10:20 · Maalwina")
        XCTAssertEqual(SessionNavigator.groups(e, query: "arabe").flatMap { $0.entries }.map { $0.id }, ["c"])
    }

    func testCalendarGridStartsOnMonday() {
        // noviembre de 2026 empieza en domingo: la rejilla empieza el lunes 26 de octubre
        let days: [CalendarDay] = TrainingCalendar.monthGrid(year: 2026, month: 11, entries: [], today: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(days.count, 42)
        XCTAssertEqual(days.first?.day, 26)
        XCTAssertEqual(days.first?.inMonth, false)
        XCTAssertEqual(days[6].day, 1)
        XCTAssertEqual(days[6].inMonth, true)
    }

    func testCalendarSummary() {
        let d = Date(timeIntervalSince1970: 1_762_590_000)
        let e: [CalendarEntry] = [
            CalendarEntry(id: "a", start: d, horse: "Zakina", durationS: 2640, distanceKm: 7.84, fixShare: 0),
            CalendarEntry(id: "b", start: d, horse: "Maalwina", durationS: 3480, distanceKm: 8.60, fixShare: 0.8),
            CalendarEntry(id: "c", start: d, horse: "Maalwina", durationS: 1800, distanceKm: 6.04, fixShare: nil),
        ]
        let s: CalendarSummary = TrainingCalendar.summary(e)
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s.durationText, "2 h 12 min")
        XCTAssertEqual(s.distanceText, "22,48 km")
        XCTAssertEqual(s.rtkText, "1 de 2")
    }

    func testDashboardSummary() {
        let d = Date(timeIntervalSince1970: 1_762_590_000)          // sábado 8 nov 2025 09:20 (Madrid)
        let e: [CalendarEntry] = [
            CalendarEntry(id: "a", start: d, horse: "Zakina", durationS: 2640, distanceKm: 7.84, fixShare: 0),
            CalendarEntry(id: "b", start: d.addingTimeInterval(3600), horse: "Sin caballo", durationS: 3480, distanceKm: 8.60, fixShare: 0.8),
            CalendarEntry(id: "c", start: d.addingTimeInterval(-86400), horse: "Maalwina", durationS: 1800, distanceKm: 6.04, fixShare: nil),
            CalendarEntry(id: "e", start: d.addingTimeInterval(-8 * 86400), horse: "Zakina", durationS: 600, distanceKm: 1.0, fixShare: 0.9),
        ]
        let s: DashboardSummary = DashboardSummary.from(e, today: d.addingTimeInterval(7200), latest: 3)
        XCTAssertEqual(s.trainings, 4)
        XCTAssertEqual(s.thisWeek, 3)
        XCTAssertEqual(s.pending, 2)
        XCTAssertEqual(s.latest.map { $0.id }, ["b", "a", "c"])
        let c: DashCard = s.latest[0]
        XCTAssertEqual(c.dayText, "SÁB 8 NOV")
        XCTAssertEqual(c.timeText, "10:20")
        XCTAssertEqual(c.distanceText, "8,60 km")
        XCTAssertEqual(c.durationText, "58 min")
        XCTAssertEqual(c.quality, "RTK FIX")
        XCTAssertEqual(s.latest.map { $0.quality }, ["RTK FIX", "Sin FIX", "Sin analizar"])
    }

    func testCalendarWeek() {
        let d = Date(timeIntervalSince1970: 1_762_590_000)          // sábado 8 nov 2025 09:20 (Madrid)
        let monday: Date = TrainingCalendar.weekStart(d)
        XCTAssertEqual(TrainingCalendar.weekTitle(monday), "3 – 9 nov 2025")
        let e: [CalendarEntry] = [
            CalendarEntry(id: "a", start: d, horse: "Zakina", durationS: 0, distanceKm: 0, fixShare: nil),
            CalendarEntry(id: "b", start: d.addingTimeInterval(-3600), horse: "Maalwina", durationS: 0, distanceKm: 0, fixShare: nil),
            CalendarEntry(id: "c", start: d.addingTimeInterval(7 * 86400), horse: "Otra semana", durationS: 0, distanceKm: 0, fixShare: nil),
        ]
        let w: [CalendarDay] = TrainingCalendar.weekGrid(start: monday, entries: e, today: d)
        XCTAssertEqual(w.map { $0.day }, [3, 4, 5, 6, 7, 8, 9])
        XCTAssertEqual(w[5].entries.map { $0.id }, ["b", "a"])
        XCTAssertTrue(w[5].isToday)
        XCTAssertEqual(w.flatMap { $0.entries }.count, 2)
        let late: Date = TrainingCalendar.weekStart(Date(timeIntervalSince1970: 1_761_900_000))   // 31 oct 2025
        XCTAssertEqual(TrainingCalendar.weekTitle(late), "27 oct – 2 nov 2025")
    }
}
