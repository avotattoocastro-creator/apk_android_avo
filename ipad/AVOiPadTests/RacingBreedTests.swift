import XCTest
@testable import AVO_Horse

/// Breed dropdown of the horse card → Track Work engine profile.
final class RacingBreedTests: XCTestCase {
    func testEngineProfiles() {
        XCTAssertEqual(TrackWorkBreed.engineName("Pura Sangre Inglés (PSI)"), "PSI")
        XCTAssertEqual(TrackWorkBreed.engineName("AQPS (Autre Que Pur-Sang)"), "PSI")
        XCTAssertEqual(TrackWorkBreed.engineName("Pura Sangre Árabe (PSA)"), "ARABE")
        XCTAssertEqual(TrackWorkBreed.engineName("Anglo-Árabe (AA)"), "ARABE")
        XCTAssertEqual(TrackWorkBreed.engineName("Cuarto de Milla de carreras"), "GENERICO")
        XCTAssertEqual(TrackWorkBreed.engineName("Trotón Francés"), "GENERICO")
        XCTAssertEqual(TrackWorkBreed.engineName("Standardbred (trotón americano)"), "GENERICO")
        XCTAssertEqual(TrackWorkBreed.engineName(""), "GENERICO")
        XCTAssertEqual(TrackWorkBreed.engineName("psi"), "PSI")      // free text kept from Android/Windows
        XCTAssertEqual(TrackWorkBreed.engineName("Árabe"), "ARABE")
    }

    func testEveryListedBreedHasAProfileText() {
        for b in RacingBreed.all { XCTAssertFalse(RacingBreed.profileText(b.label).isEmpty) }
        XCTAssertTrue(RacingBreed.profileText("Trotón Francés").contains("trote"))
    }
}
