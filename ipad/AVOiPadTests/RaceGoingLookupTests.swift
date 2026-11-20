import XCTest
@testable import AVO_Horse

/// State of the track found automatically (Core/RaceGoingLookup.swift): header line of the tracking PDF and race page of
/// Equidia (texts copied from real pages: Auteuil 31/03/2024 «Lourd (4,7)», Châteaubriant 24/07/2021 «Terrain Souple 3.5»).
final class RaceGoingLookupTests: XCTestCase {
    func testLabels() {
        XCTAssertEqual(RaceGoingLookup.going(fromText: "Bon souple"), .goodToSoft)
        XCTAssertEqual(RaceGoingLookup.going(fromText: "BON SOUPLE 3,5"), .goodToSoft)
        XCTAssertEqual(RaceGoingLookup.going(fromText: "Très souple"), .verySoft)
        XCTAssertEqual(RaceGoingLookup.going(fromText: "Souple"), .soft)
        XCTAssertEqual(RaceGoingLookup.going(fromText: "Bon"), .good)
        XCTAssertEqual(RaceGoingLookup.going(fromText: "Très lourd"), .veryHeavy)
        XCTAssertNil(RaceGoingLookup.going(fromText: "PSF STANDARD"))
        XCTAssertNil(RaceGoingLookup.going(fromText: "Bonjour"))
    }

    func testPdfHeaderLine() throws {
        let l = try XCTUnwrap(RaceGoingLookup.goingLine("Lourd (4,7)"))
        XCTAssertEqual(l.going, .heavy)
        XCTAssertEqual(l.penetrometer ?? 0, 4.7, accuracy: 1e-9)
        XCTAssertEqual(RaceGoingLookup.goingLine("Collant (4,4)")?.going, .sticky)
        XCTAssertEqual(RaceGoingLookup.goingLine("Bon souple (3,6)")?.going, .goodToSoft)
        XCTAssertNil(RaceGoingLookup.goingLine("Redk du 1er: 1'18\"84"))
        XCTAssertNil(RaceGoingLookup.goingLine("Bon pour la course (3,6)"))

        let page: String = """
        Statistiques Tracking
        AUTEUIL
        C1 - PRIX TURCO - 3500m
        dimanche 31 mars 2024 - 13:23
        Lourd (4,7)
        Redk du 1er: 1'18"84
        """
        let h = RaceTrackingParser.parseHeader(page)
        XCTAssertEqual(h.going, .heavy)
        XCTAssertEqual(h.penetrometer ?? 0, 4.7, accuracy: 1e-9)
        XCTAssertEqual(h.distanceM, 3500)
        let flat = RaceTrackingParser.parseHeader("Statistiques Tracking\nPAU\nC2 - PRIX GUY DE WATRIGANT - 2000m\nmercredi 18 novembre 2026 - 00:00\nRedk du 1er: 1'07\"10")
        XCTAssertNil(flat.going)
    }

    func testEquidiaPage() throws {
        let html: String = """
        <html><head><style>.x{}</style><script>var a="Terrain Lourd";</script></head><body>
        <h1><b>R3</b> CHATEAUBRIANT <b>C6</b> PRIX FRANCE GALOP</h1><p>HANDICAP CATEG DIVISE - CLASSE 4</p>
        <ul><li>Distance : 1950 M</li></ul><div>Discipline</div><div>Plat</div><div>Terrain</div><div>Souple</div>
        <div>3.5 à 04:00</div><p>PEINTRE FRANCAIS - Après avoir galopé en épaisseur, n&#39;a pu perdre du terrain bon.</p>
        </body></html>
        """
        let text: String = RaceGoingLookup.pageText(html)
        XCTAssertFalse(text.contains("<"))
        let h = try XCTUnwrap(RaceGoingLookup.heading(text, reunion: 3))
        XCTAssertEqual(h.hippodrome, "CHATEAUBRIANT")
        XCTAssertEqual(h.course, 6)
        XCTAssertNil(RaceGoingLookup.heading(text, reunion: 4))
        XCTAssertTrue(RaceGoingLookup.namesRace(text, "PRIX FRANCE GALOP"))
        XCTAssertFalse(RaceGoingLookup.namesRace(text, "PRIX GUY DE WATRIGANT"))
        let g = try XCTUnwrap(RaceGoingLookup.goingFromEquidia(text))
        XCTAssertEqual(g.going, .soft, "el script con «Terrain Lourd» se ignora")
        XCTAssertEqual(g.penetrometer ?? 0, 3.5, accuracy: 1e-9)
    }

    func testFileAndHippodrome() {
        XCTAssertEqual(RaceGoingLookup.courseNumber(fromFile: "20261118PAU02_last_times_fr.pdf"), 2)
        XCTAssertNil(RaceGoingLookup.courseNumber(fromFile: "carrera.pdf"))
        XCTAssertTrue(RaceGoingLookup.sameHippodrome("BORDEAUX", "Bordeaux-Le Bouscat"))
        XCTAssertTrue(RaceGoingLookup.sameHippodrome("PAU", "PAU"))
        XCTAssertFalse(RaceGoingLookup.sameHippodrome("PAU", "TOULOUSE"))
        XCTAssertEqual(RaceGoingLookup.equidiaURL(day: "2026-11-18", reunion: 1, course: 2)?.absoluteString,
                       "https://www.equidia.fr/courses/2026-11-18/R1/C2")
    }
}
