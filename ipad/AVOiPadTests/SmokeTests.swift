import XCTest
@testable import AVO_Horse
final class SmokeTests: XCTestCase {
    func testEngineLinked() { XCTAssertGreaterThanOrEqual(avo_eq_api_version(), 2) }
    func testHaversine() { XCTAssertEqual(Geo.haversineM(43.0, -3.0, 43.001, -3.0), 111.2, accuracy: 0.5) }
    func testDemoBundled() { XCTAssertNotNil(Bundle.main.url(forResource: "demo", withExtension: nil)) }
}
