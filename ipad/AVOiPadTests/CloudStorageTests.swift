import XCTest
@testable import AVO_Horse

/// Nube AVO: mismas rutas que core/src/test/.../CloudSyncTest.kt y lectura de las respuestas de Firebase Storage.
final class CloudStorageTests: XCTestCase {
    func testFileNameSharedWithAndroid() {
        XCTAssertEqual(CloudConfig.fileName("S20261120_0001"), "AVO_S20261120_0001.avo")
        XCTAssertEqual(CloudConfig.fileName("a/b c."), "AVO_a_b_c_.avo")
        XCTAssertEqual(CloudConfig.fileName(String(repeating: "x", count: 400)).count, 4 + 130 + 4)
        XCTAssertEqual(CloudConfig.folder("avo-abcd-ef23"), "trainings/AVO-ABCD-EF23/")
    }

    func testParseMetadata() {
        let j: [String: Any] = ["name": "trainings/AVO-ABCD-EF23/AVO_S1.avo", "size": "2048", "updated": "2026-11-20T12:00:00Z",
                                "metadata": ["sha256": String(repeating: "A", count: 64), "sessionId": "S1", "horseName": "LEZAMA",
                                             "riderName": "Ana", "startRtcMs": "1763640000000", "distanceM": "3200"]]
        let it: CloudItem? = CloudItem.parse(j)
        XCTAssertEqual(it?.size, 2048)
        XCTAssertEqual(it?.sha256, String(repeating: "a", count: 64))
        XCTAssertEqual(it?.fileName, "AVO_S1.avo")
        XCTAssertEqual(it?.startRtcMs, 1763640000000)
        XCTAssertEqual(it?.distanceM, 3200)
        XCTAssertNil(CloudItem.parse(["name": "trainings/AVO-ABCD-EF23/otro.zip"]))
    }

    func testListNames() {
        let j: [String: Any] = ["items": [["name": "trainings/A/AVO_1.avo"], ["name": "trainings/A/x.txt"]], "prefixes": []]
        XCTAssertEqual(CloudItem.listNames(j), ["trainings/A/AVO_1.avo"])
        XCTAssertEqual(CloudItem.listNames([:]), [])
    }

    /// Mismo vector que CloudSyncTest.kt (Android) y CloudTests.cs (Windows).
    func testFingerprintSharedWithAndroid() {
        let a: String = CloudConfig.fingerprint(localSha256: "AB", horseCode: "HORSE_001", riderCode: "RIDER_001", horseName: "LEZAMA", riderName: "Ana")
        XCTAssertEqual(a, CloudConfig.fingerprint(localSha256: "ab", horseCode: "HORSE_001", riderCode: "RIDER_001", horseName: "LEZAMA", riderName: "Ana"))
        XCTAssertEqual(a, "a242c37ddf781698761028f9ea2c649f")
        XCTAssertNotEqual(a, CloudConfig.fingerprint(localSha256: "ab", horseCode: "HORSE_002", riderCode: "RIDER_001", horseName: "LEZAMA", riderName: "Ana"))
    }

    func testManifestIdentityPrefersAssignmentBlock() {
        let root: [String: Any] = ["format": "AVO-TRAINING-1", "sessionId": "S1", "sha256": "AB", "horseCode": "HORSE_001", "horseName": "VIEJO",
                                   "riderCode": "RIDER_001", "riderName": "Ana",
                                   "asignacion": ["version": 1, "horseCode": "H2", "horseName": "LEZAMA", "riderCode": "RIDER_001",
                                                  "riderName": "Ana", "actualizadoUtc": "2026-11-20T12:00:00Z", "app": "ipad"]]
        let id = CloudManifestIdentity.from(root)
        XCTAssertEqual(id.horseName, "LEZAMA")
        XCTAssertEqual(id.horseCode, "H2")
        XCTAssertEqual(id.rawSha256, "ab")
        XCTAssertEqual(id.assignedMs, 1_795_176_000_000)
    }
}
