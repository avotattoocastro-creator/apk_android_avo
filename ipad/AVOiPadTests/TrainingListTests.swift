import XCTest
@testable import AVO_Horse

/// «Listado de entrenamientos»: geofence matching, filters and the scan for lost trainings (App/TrainingListModel.swift).
/// Synthetic files only (AVORAW1 headers written by the test).
final class TrainingListTests: XCTestCase {
    private var dir: String = ""

    override func setUpWithError() throws {
        dir = (NSTemporaryDirectory() as NSString).appendingPathComponent("avo_list_test_" + UUID().uuidString.replacingOccurrences(of: "-", with: ""))
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: dir)
    }

    // MARK: helpers

    /// A file with a valid AVORAW1 magic, session id at byte 12 and RTC start at byte 40, plus `extra` payload bytes.
    private func writeRaw(_ path: String, id: String, extra: Int = 64, fill: UInt8 = 7) throws {
        var b: [UInt8] = [UInt8](repeating: 0, count: 512 + extra)
        let magic: [UInt8] = [0x41, 0x56, 0x4F, 0x52, 0x41, 0x57, 0x31, 0x00]
        for i in 0..<8 { b[i] = magic[i] }
        let idBytes: [UInt8] = Array(id.utf8)
        for i in 0..<min(23, idBytes.count) { b[12 + i] = idBytes[i] }
        let rtc: UInt64 = 1_790_000_000_000
        for k in 0..<8 { b[40 + k] = UInt8((rtc >> (8 * UInt64(k))) & 0xFF) }
        b[8] = 1                    // version 1
        b[10] = 0x00; b[11] = 0x02  // header size 512
        let crc: UInt32 = ZipCRC32.compute(b, 0, 508)
        for k in 0..<4 { b[508 + k] = UInt8((crc >> (8 * UInt32(k))) & 0xFF) }
        for i in 512..<b.count { b[i] = fill }
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data(b).write(to: URL(fileURLWithPath: path))
    }

    private func path(_ parts: String...) -> String {
        var p: String = dir
        for x in parts { p = (p as NSString).appendingPathComponent(x) }
        return p
    }

    private func row(_ id: String, horse: String = "Rayo", rider: String = "Ana", discipline: String = "Playa", start: Date? = nil,
                     girth: Bool = false, fav: Bool = false, demo: Bool = false, fences: [Int]? = [], km: Double = 1, secs: Double = 600) -> TrainingListRow {
        TrainingListRow(id: id, start: start, startKey: start?.timeIntervalSince1970 ?? -1e12, dateTimeText: "", horse: horse, rider: rider,
                        discipline: discipline, durationS: secs, durationText: "", distanceKm: km, distanceText: "", maxSpeedKmh: 30,
                        maxSpeedText: "", hasGirth: girth, girthText: girth ? "Sí" : "No", fenceSlots: fences, fencesText: "",
                        origin: "Archivo", engineState: "", isFavorite: fav, favKey: fav ? 1 : 0, isSynthetic: demo, searchExtra: "")
    }

    // MARK: geofences

    func testCircleUsesHaversineRadius() {
        let f = TrainingListFence(slot: 0, name: "Pista", isCircle: true, centerLat: 36.5, centerLon: -6.2, radiusM: 100)
        // 0.0005° of latitude ≈ 55.6 m, 0.0012° ≈ 133 m
        XCTAssertTrue(f.contains(lat: 36.5005, lon: -6.2))
        XCTAssertFalse(f.contains(lat: 36.5012, lon: -6.2))
        XCTAssertFalse(f.contains(lat: .nan, lon: -6.2))
    }

    func testPointInPolygon() {
        let lat: [Double] = [36.0, 36.0, 36.01, 36.01]
        let lon: [Double] = [-6.0, -5.99, -5.99, -6.0]
        XCTAssertTrue(TrainingListGeo.pointInPolygon(lat: 36.005, lon: -5.995, vLat: lat, vLon: lon))
        XCTAssertFalse(TrainingListGeo.pointInPolygon(lat: 36.02, lon: -5.995, vLat: lat, vLon: lon))
        XCTAssertFalse(TrainingListGeo.pointInPolygon(lat: 36.005, lon: -5.98, vLat: lat, vLon: lon))
        // concave «L»: the notch is outside
        let lLat: [Double] = [0, 0, 1, 1, 2, 2]
        let lLon: [Double] = [0, 2, 2, 1, 1, 0]
        XCTAssertTrue(TrainingListGeo.pointInPolygon(lat: 0.5, lon: 1.5, vLat: lLat, vLon: lLon))
        XCTAssertFalse(TrainingListGeo.pointInPolygon(lat: 1.5, lon: 1.5, vLat: lLat, vLon: lLon))
        XCTAssertFalse(TrainingListGeo.pointInPolygon(lat: 0.5, lon: 0.5, vLat: [0, 1], vLon: [0, 1]))
    }

    func testVisitedFencesOfATrack() {
        let circle = TrainingListFence(slot: 3, name: "Círculo", isCircle: true, centerLat: 36.5, centerLon: -6.2, radiusM: 50)
        let square = TrainingListFence(slot: 1, name: "Cuadrado", isCircle: false,
                                       vLat: [36.0, 36.0, 36.01, 36.01], vLon: [-6.0, -5.99, -5.99, -6.0])
        let far = TrainingListFence(slot: 6, name: "Lejos", isCircle: true, centerLat: 40, centerLon: 0, radiusM: 500)
        let lat: [Double] = [0, 36.005, 36.2, 36.5001]
        let lon: [Double] = [0, -5.995, -6.1, -6.2]
        XCTAssertEqual(TrainingListGeo.visited(lat: lat, lon: lon, fences: [circle, square, far]), [1, 3])
        XCTAssertEqual(TrainingListGeo.visited(lat: [], lon: [], fences: [circle]), [])
    }

    func testSnapshotKeepsOnlyDefinedFences() {
        let plan = GeofencePlan()
        plan.fences[0] = PlanFence(name: "Playa", type: .circle, center: PlanPoint(36.5, -6.2), radiusM: 80)
        plan.fences[1] = PlanFence(name: "Incompleta", type: .polygon, vertices: [PlanPoint(36, -6), PlanPoint(36.1, -6)])
        plan.fences[2] = PlanFence(name: "", type: .polygon,
                                   vertices: [PlanPoint(36, -6), PlanPoint(36, -5.9), PlanPoint(36.1, -5.9)], active: false)
        plan.fences[4] = PlanFence(name: "Sin centro", type: .circle, center: nil, radiusM: 80)
        let s: [TrainingListFence] = TrainingListGeo.snapshot(plan)
        XCTAssertEqual(s.map { $0.slot }, [0, 2])
        XCTAssertEqual(s[1].name, "Geocerca 3")
        XCTAssertNotEqual(TrainingListGeo.signature(s), TrainingListGeo.signature([s[0]]))
    }

    // MARK: filters

    /// «Eliminar entrenamiento»: out of the list and the library, the user's own file untouched, remembered as deleted
    /// (the recovery scan will not bring it back) and imported again when the user opens the file on purpose.
    @MainActor
    func testDeleteTrainingRemovesItAndRemembersIt() async throws {
        var raw: Data? = nil
        for b in [Bundle(for: TrainingListTests.self), Bundle.main] {
            if raw == nil, let u = b.url(forResource: "synthetic_session", withExtension: "avo") { raw = try? Data(contentsOf: u) }
        }
        guard let data = raw else { throw XCTSkip("Falta synthetic_session.avo") }
        let tmp = (NSTemporaryDirectory() as NSString).appendingPathComponent("avo-del-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        let root = (tmp as NSString).appendingPathComponent("app")
        let userDir = (tmp as NSString).appendingPathComponent("usuario")
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: userDir, withIntermediateDirectories: true)
        let file = (userDir as NSString).appendingPathComponent("sesion.avr")
        try data.write(to: URL(fileURLWithPath: file))
        let app = AppModel(paths: AppPaths(root: root))
        await app.importFiles([file])
        XCTAssertEqual(app.sessions.count, 1, "Importado")
        guard let item = app.sessions.first else { return }
        let stored: String = app.library.entries.first?.storedPath ?? ""
        XCTAssertTrue(FileManager.default.fileExists(atPath: stored), "Copia en la biblioteca")
        app.deleteTraining(item)
        XCTAssertTrue(app.sessions.isEmpty, "Fuera de la lista")
        XCTAssertTrue(app.library.entries.isEmpty, "Fuera de la biblioteca")
        XCTAssertFalse(FileManager.default.fileExists(atPath: stored), "Copia de la biblioteca borrada")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file), "El archivo del usuario no se toca")
        XCTAssertTrue(app.loadDeleted().sessionIds.contains(item.id), "Recordado como eliminado")
        await app.importFiles([file])
        XCTAssertEqual(app.sessions.count, 1, "Abrirlo a propósito lo vuelve a importar")
        XCTAssertFalse(app.loadDeleted().sessionIds.contains(item.id), "Y deja de estar marcado como eliminado")
    }

    func testFilterLogic() {
        let cal: Calendar = TrainingListFilter.calendar
        let d1: Date = cal.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 9))!
        let d2: Date = cal.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 23, minute: 30))!
        let rows: [TrainingListRow] = [
            row("A", horse: "Rayo", rider: "Ana", start: d1, girth: true, fences: [0, 2]),
            row("B", horse: "Luna", rider: "Pedro", discipline: "Pista", start: d2, fav: true, fences: [1]),
            row("DEMO_X", horse: "Rayo", start: d2, demo: true, fences: nil),
            row("C", horse: "Luna", start: nil),
        ]
        func ids(_ f: TrainingListFilter) -> [String] { rows.filter { f.matches($0, calendar: cal) }.map { $0.id } }

        XCTAssertEqual(ids(TrainingListFilter()), ["A", "B", "DEMO_X", "C"])
        var f = TrainingListFilter()
        f.horse = "rayo"
        XCTAssertEqual(ids(f), ["A", "DEMO_X"])
        f.hideDemo = true
        XCTAssertEqual(ids(f), ["A"])

        f = TrainingListFilter(); f.rider = "Pedro"
        XCTAssertEqual(ids(f), ["B"])
        f = TrainingListFilter(); f.discipline = "Pista"
        XCTAssertEqual(ids(f), ["B"])
        f = TrainingListFilter(); f.onlyGirth = true
        XCTAssertEqual(ids(f), ["A"])
        f = TrainingListFilter(); f.onlyFavorites = true
        XCTAssertEqual(ids(f), ["B"])
        // geofence: pending (nil) never matches
        f = TrainingListFilter(); f.fence = 2
        XCTAssertEqual(ids(f), ["A"])
        f.fence = 1
        XCTAssertEqual(ids(f), ["B"])
        // dates: whole days, the «to» day included; trainings without date excluded
        f = TrainingListFilter(); f.from = cal.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 15))
        XCTAssertEqual(ids(f), ["B", "DEMO_X"])
        f = TrainingListFilter(); f.to = cal.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 1))
        XCTAssertEqual(ids(f), ["A", "B", "DEMO_X"])
        f.to = cal.date(from: DateComponents(year: 2026, month: 10, day: 24))
        XCTAssertEqual(ids(f), ["A"])
        // search
        f = TrainingListFilter(); f.search = "  ped "
        XCTAssertEqual(ids(f), ["B"])
        XCTAssertTrue(TrainingListFilter().isEmpty)
        XCTAssertFalse(f.isEmpty)
    }

    func testFilterRoundTripsAsJson() throws {
        var f = TrainingListFilter()
        f.horse = "Rayo"; f.fence = 3; f.from = Date(timeIntervalSince1970: 1_790_000_000); f.hideDemo = true
        let back: TrainingListFilter = try JSONDecoder().decode(TrainingListFilter.self, from: try JSONEncoder().encode(f))
        XCTAssertEqual(back, f)
    }

    func testSummary() {
        let rows: [TrainingListRow] = [row("A", km: 1.25, secs: 1800), row("B", km: 2.5, secs: 2700)]
        XCTAssertEqual(TrainingListFilter.summary(rows), "2 entrenamientos · 3,8 km · 01:15 total")
        XCTAssertEqual(TrainingListFilter.summary([row("A", km: 0, secs: 59)]), "1 entrenamiento · 0,0 km · 00:00 total")
    }

    // MARK: lost trainings

    func testScanFindsTrainingsAndSkipsDuplicates() throws {
        let root: String = path("raiz")
        let outside: String = path("fuera")
        let packDir: String = path("paquetes")
        // new single RAW + an identical copy elsewhere
        try writeRaw(path("raiz", "a", "nuevo.avr"), id: "SESS_A")
        try writeRaw(path("raiz", "a", "sub", "copia.avr"), id: "SESS_A")
        // already loaded by SHA, and by session id
        try writeRaw(path("raiz", "b", "cargado.avr"), id: "SESS_K", fill: 9)
        try writeRaw(path("raiz", "b", "mismo_id.avr"), id: "SESS_D", fill: 3)
        // damaged
        try Data([1, 2, 3, 4]).write(to: URL(fileURLWithPath: path("raiz", "roto.avr")))
        try Data("no es un zip".utf8).write(to: URL(fileURLWithPath: path("raiz", "roto.avo")))
        // complete segment folder, unfinished download, folder with a gap
        try writeRaw(path("raiz", "reloj", "descargas", "SESS_B", "P001.avr"), id: "SESS_B", fill: 1)
        try writeRaw(path("raiz", "reloj", "descargas", "SESS_B", "P002.avr"), id: "SESS_B", fill: 2)
        try writeRaw(path("raiz", "reloj", "descargas", "SESS_E", "P001.avr"), id: "SESS_E", fill: 4)
        try Data("etag".utf8).write(to: URL(fileURLWithPath: path("raiz", "reloj", "descargas", "SESS_E", ".wifi_etag")))
        try writeRaw(path("raiz", "hueco", "P001.avr"), id: "SESS_G", fill: 5)
        try writeRaw(path("raiz", "hueco", "P003.avr"), id: "SESS_G", fill: 6)
        // a real .avo package (built outside the scanned folder)
        try writeRaw((outside as NSString).appendingPathComponent("P001.avr"), id: "SESS_C", fill: 8)
        try AvoPackageWriter.write(target: path("raiz", "c", "paquete.avo"),
                                   meta: AvoPackageWriter.Meta(sessionId: "SESS_C", sha256: String(repeating: "0", count: 64),
                                                               watchDevice: "", watchFirmware: "", startRtcMs: 0, activeMs: 0),
                                   segments: [(outside as NSString).appendingPathComponent("P001.avr")])
        try Data([0]).write(to: URL(fileURLWithPath: path("raiz", "descarga.part")))
        try Data("x".utf8).write(to: URL(fileURLWithPath: path("raiz", "notas.txt")))
        // map tiles are never scanned
        try writeRaw(path("raiz", "teselas", "oculto.avr"), id: "SESS_T")

        let scan: TrainingRecoveryScan = TrainingRecovery.collect([root], maxDepth: 6, maxFiles: 2000)
        XCTAssertEqual(scan.files.count, 7)
        XCTAssertEqual(scan.segmentDirs.count, 3)
        XCTAssertEqual(scan.partials.count, 1)
        XCTAssertFalse(scan.limited)
        XCTAssertFalse(scan.files.contains(where: { $0.hasSuffix("oculto.avr") }))

        var known = TrainingRecoveryKnown()
        known.shas = [try TrainingLibrary.fileSha256(path("raiz", "b", "cargado.avr"))]
        known.sessionIds = ["SESS_D"]
        let items: [TrainingRecoveryItem] = TrainingRecovery.evaluate(scan, known: known, packDir: packDir)
        func status(_ name: String) -> TrainingRecoveryStatus? { items.first(where: { $0.name == name })?.status }

        let pending: [TrainingRecoveryItem] = items.filter { $0.status == .pending }
        XCTAssertEqual(pending.count, 3)                                  // nuevo.avr (or its copy), SESS_B/, paquete.avo
        XCTAssertEqual(items.filter { $0.name == "nuevo.avr" || $0.name == "copia.avr" }.map { $0.status.rawValue }.sorted(),
                       [TrainingRecoveryStatus.pending.rawValue, TrainingRecoveryStatus.duplicate.rawValue])
        XCTAssertEqual(status("cargado.avr"), .duplicate)
        XCTAssertEqual(status("mismo_id.avr"), .duplicate)
        XCTAssertEqual(status("roto.avr"), .damaged)
        XCTAssertEqual(status("roto.avo"), .damaged)
        XCTAssertEqual(status("paquete.avo"), .pending)
        XCTAssertEqual(status("SESS_B/"), .pending)
        XCTAssertEqual(status("SESS_E/"), .incomplete)
        XCTAssertEqual(status("hueco/"), .incomplete)
        XCTAssertEqual(status("descarga.part"), .incomplete)

        // the segment folder was packed as a valid AVO-TRAINING-1 package with both segments
        let packed: String = try XCTUnwrap(items.first(where: { $0.name == "SESS_B/" })?.importPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: packed))
        let s: TrainingSession = try TrainingImporter.importFile(packed, rawCacheDir: path("cache"))
        XCTAssertEqual(s.sessionId, "SESS_B")
        XCTAssertEqual(s.segments.count, 2)
        XCTAssertEqual(TrainingListModel.origin(ofFile: packed), "Recuperado")

        // a second pass with everything loaded finds nothing new (SHA-256 and session id)
        var all = TrainingRecoveryKnown()
        for it in pending {
            let p: String = try XCTUnwrap(it.importPath)
            all.shas.insert(try TrainingLibrary.fileSha256(p))
        }
        all.shas.insert(try WifiDownloader.sha256(path("raiz", "reloj", "descargas", "SESS_B")))
        all.sessionIds = ["SESS_A", "SESS_B", "SESS_C", "SESS_D"]
        all.shas.formUnion(known.shas)
        let again: [TrainingRecoveryItem] = TrainingRecovery.evaluate(TrainingRecovery.collect([root], maxDepth: 6, maxFiles: 2000),
                                                                      known: all, packDir: packDir)
        XCTAssertEqual(again.filter { $0.status == .pending }.count, 0)
    }

    func testScanLimitsDepthAndFileCount() throws {
        try writeRaw(path("r", "1", "2", "cerca.avr"), id: "SESS_N")
        try writeRaw(path("r", "1", "2", "3", "4", "lejos.avr"), id: "SESS_F")
        let shallow: TrainingRecoveryScan = TrainingRecovery.collect([path("r")], maxDepth: 2, maxFiles: 2000)
        XCTAssertEqual(shallow.files.map { AvoFiles.fileName($0) }, ["cerca.avr"])
        let deep: TrainingRecoveryScan = TrainingRecovery.collect([path("r")], maxDepth: 6, maxFiles: 2000)
        XCTAssertEqual(deep.files.count, 2)
        let limited: TrainingRecoveryScan = TrainingRecovery.collect([path("r")], maxDepth: 6, maxFiles: 1)
        XCTAssertTrue(limited.limited)
        XCTAssertEqual(limited.scanned, 1)
        // the same folder given twice is visited once
        XCTAssertEqual(TrainingRecovery.collect([path("r"), path("r", "1")], maxDepth: 6, maxFiles: 2000).files.count, 2)
    }

    func testCopyToInboxForExternalFolders() throws {
        try writeRaw(path("ext", "x.avr"), id: "SESS_X")
        let scan: TrainingRecoveryScan = TrainingRecovery.collect([path("ext")], maxDepth: 6, maxFiles: 2000)
        let items: [TrainingRecoveryItem] = TrainingRecovery.evaluate(scan, known: TrainingRecoveryKnown(), packDir: path("p"),
                                                                      copyInbox: path("entrada"))
        XCTAssertEqual(items.count, 1)
        let copy: String = try XCTUnwrap(items[0].tempCopy)
        XCTAssertEqual(items[0].importPath, copy)
        XCTAssertTrue(copy.hasPrefix(path("entrada")))
        XCTAssertEqual(try TrainingLibrary.fileSha256(copy), try TrainingLibrary.fileSha256(path("ext", "x.avr")))
    }
}
