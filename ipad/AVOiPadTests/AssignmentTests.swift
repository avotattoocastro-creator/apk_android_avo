import XCTest
import CryptoKit
@testable import AVO_Horse

/// AVO-ASSIGN-1 (docs/ASIGNACION_CABALLO.md): the assignment travels in the .avo manifest; the RAW never changes.
/// Port of windows/AVO.Windows.SelfTest/AssignmentTests.cs.
final class AssignmentTests: XCTestCase {
    private var dir: String = ""

    override func setUpWithError() throws {
        dir = (NSTemporaryDirectory() as NSString).appendingPathComponent("avo-asignacion-" + UUID().uuidString)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(atPath: dir) }

    private func path(_ parts: String...) -> String { parts.reduce(dir) { ($0 as NSString).appendingPathComponent($1) } }

    private func rawFixture() throws -> Data {
        for b in [Bundle(for: AssignmentTests.self), Bundle.main] {
            if let u = b.url(forResource: "synthetic_session", withExtension: "avo"), let d = try? Data(contentsOf: u) { return d }
        }
        throw XCTSkip("Falta la sesión de referencia synthetic_session.avo")
    }

    /// A package built like the Wi-Fi download: AvoPackageWriter from a RAW segment.
    private func package(_ name: String) throws -> String {
        let seg = path("seg_" + name, "P001.avr")
        try FileManager.default.createDirectory(atPath: (seg as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try rawFixture().write(to: URL(fileURLWithPath: seg))
        let target = path(name)
        try AvoPackageWriter.write(target: target, meta: AvoPackageWriter.Meta(sessionId: "SINTETICA_0001", sha256: String(repeating: "0", count: 64),
                                                                              watchDevice: "", watchFirmware: "", startRtcMs: 1_792_656_000_000, activeMs: 0),
                                   segments: [seg])
        return target
    }

    private func segmentShas(_ avo: String) throws -> [String] {
        let zip = try ZipReader(path: avo)
        return try zip.entries.filter { $0.fullName != "manifest.json" }.sorted { $0.fullName < $1.fullName }.map {
            $0.fullName + ":" + AvoHex.lower(SHA256.hash(data: Data(try zip.read($0, max: 50 * 1024 * 1024))))
        }
    }

    private func manifest(_ avo: String) throws -> [String: Any] {
        let zip = try ZipReader(path: avo)
        return try XCTUnwrap(AvoJSON.object(Data(try zip.read(try XCTUnwrap(zip.entry("manifest.json")), max: 16_384))))
    }

    func testDownloadPackageCarriesTheWatchIdentity() throws {
        let avo = try package("descarga.avo")
        let raw = AvoAssignment.rawHeaderIdentity(path("seg_descarga.avo", "P001.avr"))
        let m = try manifest(avo)
        XCTAssertEqual(AvoJSON.string(m, "horseName"), raw.horse ?? "", "El paquete del iPad ya no lleva el caballo en blanco")
        XCTAssertNil(m["asignacion"], "Sin reasignar no hay bloque")
    }

    func testRewriteKeepsTheRawAndWinsOnImport() throws {
        let avo = try package("p.avo")
        let before = try segmentShas(avo)
        let s0 = try TrainingImporter.importFile(avo, rawCacheDir: path("raw0"))
        let t1 = Date(timeIntervalSince1970: 1_794_520_800)   // 2026-11-12T22:00:00Z
        try AvoAssignment.write(avo, AvoAssignmentData(horseCode: "H_ZAKINA", horseName: "Zakina", riderCode: "AVO-A66T-F2E9", riderName: "Andoni Lezama",
                                                       updated: t1, app: "ipad"), rawHorse: s0.rawHorse, rawRider: s0.rawRider)
        XCTAssertEqual(try segmentShas(avo), before, "Reescribir el manifiesto no cambia ningún byte del RAW")
        let s1 = try TrainingImporter.importFile(avo, rawCacheDir: path("raw1"))
        XCTAssertEqual(s1.horse, "Zakina"); XCTAssertEqual(s1.horseCode, "H_ZAKINA"); XCTAssertEqual(s1.rider, "Andoni Lezama")
        XCTAssertEqual(s1.rawHorse, s0.rawHorse, "El valor de la cabecera RAW se conserva aparte")
        XCTAssertEqual(s1.fileAssignment?.app, "ipad"); XCTAssertEqual(s1.fileAssignment?.updated, t1)
        let m = try manifest(avo)
        XCTAssertEqual(AvoJSON.string(m, "horseName"), "Zakina", "Campos de primer nivel para lectores antiguos")
        let rawBlock = AvoJSON.dict(try XCTUnwrap(AvoJSON.dict(m, "asignacion")), "raw")
        XCTAssertEqual(rawBlock?["horseCode"] as? String, s0.rawHorse)
        // reassigning again keeps the RAW value, not the previous assignment
        try AvoAssignment.write(avo, AvoAssignmentData(horseCode: "H_MALWINA", horseName: "Malwina", riderCode: nil, riderName: "",
                                                       updated: t1.addingTimeInterval(3600), app: "ipad"), rawHorse: "OTRO", rawRider: nil)
        let raw2 = AvoJSON.dict(try XCTUnwrap(AvoJSON.dict(try manifest(avo), "asignacion")), "raw")
        XCTAssertEqual(raw2?["horseCode"] as? String, s0.rawHorse)
        XCTAssertEqual(try TrainingImporter.importFile(avo, rawCacheDir: path("raw2")).horse, "Malwina")
    }

    func testEngineOption() {
        XCTAssertEqual(AvoAssignment.engineOption(horseCode: "H_ZAKINA", horseName: "Zakina", riderCode: nil, riderName: StableStore.unknown),
                       "\"asignacion\":{\"horseCode\":\"H_ZAKINA\",\"horseName\":\"Zakina\"}")
        XCTAssertNil(AvoAssignment.engineOption(horseCode: nil, horseName: " ", riderCode: nil, riderName: nil))
    }

    func testLibraryKeepsTheOldHashAndStableAdoptsNewerAssignments() throws {
        let original = try package("original.avo")
        let lib = TrainingLibrary(AppPaths(root: path("app")))
        let first = lib.importFile(original, loadedSessionIds: [])
        let s = try XCTUnwrap(first.session)
        let oldSha = try XCTUnwrap(s.fileSha256)
        let newSha = try lib.writeAssignment(s.sessionId, AvoAssignmentData(horseCode: "H_ZAKINA", horseName: "Zakina", riderCode: nil, riderName: "",
                                                                           updated: Date(), app: "ipad"), rawHorse: s.rawHorse, rawRider: nil)
        XCTAssertTrue(newSha != nil && newSha != oldSha && lib.entries.first?.previousSha256.contains(oldSha) == true)
        let again = lib.importFile(original, loadedSessionIds: [s.sessionId])
        XCTAssertTrue(again.duplicate && again.session?.horse == "Zakina", "Reimportar el original es un duplicado y muestra la asignación")

        let st = StableStore(path: path("cuadra.json"))
        _ = try st.add(.horse, IdentityRecord(code: "H_ZAKINA", name: "Zakina"))
        _ = try st.add(.horse, IdentityRecord(code: "H_MALWINA", name: "Malwina"))
        try st.assign("S1", setHorse: true, horseCode: "H_ZAKINA", setRider: false, riderCode: nil)
        let older = TrainingSession(); older.sessionId = "S1"
        older.fileAssignment = AvoAssignmentData(horseCode: "H_MALWINA", horseName: "Malwina", riderCode: nil, riderName: "", updated: Date(timeIntervalSince1970: 0), app: "windows")
        XCTAssertFalse(try st.adoptFileAssignment(older), "Una asignación más antigua no pisa la del iPad")
        let newer = TrainingSession(); newer.sessionId = "S1"
        newer.fileAssignment = AvoAssignmentData(horseCode: "H_MALWINA", horseName: "Malwina", riderCode: nil, riderName: "", updated: Date().addingTimeInterval(300), app: "android")
        XCTAssertTrue(try st.adoptFileAssignment(newer))
        XCTAssertEqual(st.assignment("S1")?.horseCode, "H_MALWINA")
        let unknown = TrainingSession(); unknown.sessionId = "S2"
        unknown.fileAssignment = AvoAssignmentData(horseCode: "H_NUEVO", horseName: "Nueva", riderCode: nil, riderName: "", updated: Date(), app: "android")
        XCTAssertTrue(try st.adoptFileAssignment(unknown))
        XCTAssertEqual(st.find(.horse, "H_NUEVO")?.name, "Nueva", "El caballo asignado en otra app se da de alta")
    }
}
