import XCTest
@testable import AVO_Horse

/// Tiempo medido de AEMET (25/11/2026): elección de estación y lectura de una observación horaria.
final class AemetTests: XCTestCase {
    func testNearestStationForLaredoBeach() {
        // Playa del Regatón (Laredo): Treto (1096X) a unos 4–5 km
        let n = AemetConfig.nearest(43.4180, -3.4330)
        XCTAssertEqual(n?.0.idema, "1096X")
        XCTAssertLessThan(n?.1 ?? 99, 6)
        XCTAssertNil(AemetConfig.nearest(40.4168, -3.7038))   // Madrid: ninguna a menos de 25 km
    }

    func testParseObservation() {
        let o: [String: Any] = ["idema": "1096X", "fint": "2026-11-23T09:00:00+0000", "ta": 12.4, "hr": 81.0, "vv": 2.5, "dv": 180.0,
                                "vmax": 5.0, "pres": 1018.2, "prec": 0.0]
        let st = AemetConfig.stations[0]
        let m = AemetObservation.parse(o, station: st, distanceKm: 4.4)
        XCTAssertEqual(m?.temperatureC, 12.4)
        XCTAssertEqual(m?.windKmh ?? 0, 9.0, accuracy: 0.01)   // 2,5 m/s
        XCTAssertEqual(m?.sourceLine, "Medido · AEMET Treto (4 km)")
        XCTAssertEqual(m.map { Int($0.utc.timeIntervalSince1970) }, 1795424400)
    }
}
