import XCTest
@testable import AVO_Horse

/// Página «Demostración» (27/11/2026): tipos MIME del servidor interno y página de inicio.
final class DemoTests: XCTestCase {
    func testMimeTypesForModulesAndAssets() {
        // los módulos ES solo cargan con un tipo JavaScript
        XCTAssertTrue(DemoSchemeHandler.mime("js").hasPrefix("text/javascript"))
        XCTAssertTrue(DemoSchemeHandler.mime("HTML").hasPrefix("text/html"))
        XCTAssertEqual(DemoSchemeHandler.mime("webp"), "image/webp")
        XCTAssertEqual(DemoSchemeHandler.mime("jpg"), "image/jpeg")
        XCTAssertEqual(DemoSchemeHandler.mime("zip"), "application/zip")
    }

    func testStartPageMatchesBundledModels() {
        let u = DemoAssets.startURL
        XCTAssertEqual(u.scheme, DemoAssets.scheme)
        XCTAssertEqual(u.lastPathComponent, "index.html")
        XCTAssertEqual(u.pathComponents.dropFirst().first, DemoAssets.has3D ? "3d" : "2d")
    }
}
