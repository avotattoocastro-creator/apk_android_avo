import XCTest
@testable import AVO_Horse

/// Paridad iPad ↔ PC: el MISMO JSON y los MISMOS valores esperados que windows/AVO.Windows.SelfTest (KeyData).
final class KeyDataTests: XCTestCase {
    static let json: String = """
    {"formato":"avo-equine-analysis","metricas":[{"nombre":"distancia","valor":7840.4},{"nombre":"duracion","valor":2652},
    {"nombre":"velocidad_maxima","valor":18.0555},{"nombre":"tiempo_PASO","valor":2000},{"nombre":"tiempo_TROTE","valor":330},
    {"nombre":"tiempo_GALOPE","valor":322},{"nombre":"tiempo_en_curva","valor":50}],
    "rtk":{"total_s":2652,"fix_s":0,"float_s":0,"dgnss_s":2400,"gnss_s":252},
    "trabajo_pista":{"trabajos":{"v_max":18.0555,"mejor_200m_s":11.36,"lista":[
    {"id":1,"t0":10,"t1":110,"mejores":[{"distancia_m":200,"tiempo_s":11.36},{"distancia_m":600,"tiempo_s":35.31},{"distancia_m":1000,"tiempo_s":60.42}],"l_max_m":7.3,"f_max_hz":2.36},
    {"id":2,"t0":300,"t1":380,"mejores":[{"distancia_m":200,"tiempo_s":12.1},{"distancia_m":600,"tiempo_s":37.0}],"l_max_m":6.9}]}}}
    """

    func testKeyDataFromEngineJson() {
        let k: KeyData = KeyData.from(json: Self.json)
        XCTAssertTrue(k.hasEngine)
        func v(_ id: String) -> String { k.tiles.first { $0.id == id }?.value ?? "?" }
        XCTAssertEqual(v("vmax"), "65,0")
        XCTAssertEqual(v("best200"), "11,36")
        XCTAssertEqual(v("best600"), "35,31")
        XCTAssertEqual(v("best1000"), "60,42")
        XCTAssertEqual(v("distance"), "7,84")
        XCTAssertEqual(v("duration"), "44:12")
        XCTAssertEqual(v("hrmax"), "—")
        XCTAssertEqual(v("lmax"), "7,30")
        XCTAssertEqual(v("fmax"), "2,36")
        XCTAssertEqual(k.gaits.map { $0.id }, ["PASO", "TROTE", "GALOPE"])
        XCTAssertEqual(k.qualityLabel, "DGNSS")
        XCTAssertEqual(k.fixShare ?? -1, 0, accuracy: 1e-9)
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
}
