import XCTest
import CryptoKit
@testable import AVO_Horse

/// Training download over Bluetooth (READ_FILE / FILE_SHA256), the fallback when the watch Wi-Fi cannot be used.
/// Mirrors the Android core/DownloadProtocolTest.kt (branch fix/chest-v373-readfile) against SimWatch (SimWatch.swift),
/// which answers like the chest firmware: at most 2048 B per FILE_DATA on FILE_TX, header offset + size + CRC-32,
/// NOT_FOUND after the last segment. No Bluetooth hardware involved; physical validation with the watch is pending.
final class BleDownloadTests: XCTestCase {
    private var root: String = ""

    override func setUpWithError() throws {
        root = (NSTemporaryDirectory() as NSString).appendingPathComponent("avo-ble-" + UUID().uuidString)
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: root)
    }

    private func dirFor(_ id: String) -> String { AvoFiles.join(root, "descargas", id) }

    /// Authorized simulated watch with the firmware configuration vector.
    private func makeWatch() throws -> SimWatch {
        let url = try XCTUnwrap(Bundle(for: BleDownloadTests.self).url(forResource: "watch_vectors", withExtension: "json"))
        let v = try XCTUnwrap(AvoJSON.object(try Data(contentsOf: url)))
        let blob = try XCTUnwrap(AvoHex.bytes(try XCTUnwrap(v["config"] as? String)))
        let w = try SimWatch(blob)
        w.client = AvoClient(w, startMsgId: 300)
        w.authorized = true
        return w
    }

    /// Instant pauses and short timeouts (the protocol is the same; only the waiting is shortened).
    private func fast() -> BleDownloadOptions {
        var o = BleDownloadOptions()
        o.readTimeoutMs = 60
        o.readRetries = 1
        o.reconnectWaitMs = 0
        o.statusIntervalS = 0
        o.maxFailures = 3
        o.pause = { (_: Int) async -> Void in }
        return o
    }

    private func clientOf(_ w: SimWatch) -> () -> AvoClient? {
        return { w.linkUp ? w.client : nil }
    }

    private func entry(_ w: SimWatch, _ id: String) async throws -> WatchSessionEntry {
        let c = try XCTUnwrap(w.client)
        let list = try await c.listSessions()
        return try XCTUnwrap(list.first { $0.id == id }, "\(id) en LIST_SESSIONS")
    }

    private func localSegments(_ id: String) -> [[UInt8]] {
        WifiDownloader.segFiles(dirFor(id)).map { [UInt8](FileManager.default.contents(atPath: $0) ?? Data()) }
    }

    private func localBytes(_ id: String) -> Int64 {
        WifiDownloader.segFiles(dirFor(id)).reduce(Int64(0)) { $0 + AvoFiles.size($1) }
    }

    // ---------------------------------------------------------------- full download + SHA-256
    func testFullDownloadWithShaMatch() async throws {
        let w = try makeWatch()
        let id = "S1E8C_000009_001"
        w.addBleSession(id, [5_000, 3_001], seed: 9)
        for i in 0..<11 { w.addBleSession(String(format: "S1E8C_%06d_001", 100 + i), [100], seed: UInt64(i)) }   // 12 sessions: 2 pages
        w.dropReads = [1]          // one answer never leaves the watch (the case seen on 3.7.2)
        w.corruptReads = [3]       // one block with a wrong CRC-32
        let all = try await XCTUnwrap(w.client).listSessions()
        XCTAssertEqual(all.count, 12, "LIST_SESSIONS: todas las páginas")
        let e = try await entry(w, id)
        XCTAssertTrue(e.ready && e.segments == 2 && e.totalBytes == 8_001)
        let dl = BleSessionDownloader(client: clientOf(w), options: fast())
        var last: Int64 = 0
        let r = try await dl.download(e, dir: dirFor(id)) { (b: Int64, _: Int64, _: Double, _: String?) in last = b }
        let expectedSha = AvoHex.lower(w.bleSha(id))
        XCTAssertEqual(r, .verified(sha256: expectedSha, bytes: 8_001), "BLE: descargado y verificado con FILE_SHA256 del reloj")
        XCTAssertEqual(localSegments(id), w.bleSessions[id] ?? [], "BLE: P001.avr y P002.avr idénticos a los del reloj")
        XCTAssertEqual(last, 8_001, "BLE: el progreso cuenta los bytes escritos")
        XCTAssertEqual(w.fileReads, 3 + 2 + 2, "BLE: bloques de 2048 B + un reintento por respuesta perdida y otro por CRC")
        XCTAssertEqual(w.shaRequests, 1)
        XCTAssertFalse(AvoFiles.exists(AvoFiles.join(dirFor(id), BleSessionDownloader.sizesFile)), "BLE: sin restos tras verificar")
        XCTAssertEqual(w.bleSessions[id]?.count, 2, "BLE: nada se borra en el reloj")
    }

    func testPassPackagesAndImportsLikeWifi() async throws {
        let w = try makeWatch()
        w.addBleSession("S0001", [4_100], seed: 1)
        w.addBleSession("S0002", [2_048, 10], seed: 2)
        w.addBleSession("S0003", [500], seed: 3)
        w.bleOpen = ["S0003"]                     // still open on the watch: not offered
        let shared = WatchWifiShared(folder: AvoFiles.join(root, "reloj"))
        shared.setWatch(device: SimWatch.dev, firmware: "3.7.6")
        let base = AvoFiles.join(root, "descargas")
        let sync = BleTrainingSync(client: clientOf(w), dirFor: { (id: String) -> String in AvoFiles.join(base, id) },
                                   sink: { (id: String, dir: String, sha: String, bytes: Int64) async throws -> Void in
                                       try shared.packageVerified(id: id, dir: dir, sha: sha, bytes: bytes, source: "ble-ipad")
                                   }, options: fast())
        var states: [WifiSyncProgress] = []
        sync.onProgress = { (p: WifiSyncProgress) in states.append(p) }
        let rep = try await sync.sync(ids: nil, listed: { (l: [WatchSessionEntry]) in shared.setRemote(l.map { $0.remote }) })
        XCTAssertEqual(Set(rep.verified), ["S0001", "S0002"], "BLE: «Descargar todo» baja los cerrados")
        XCTAssertTrue(rep.failed.isEmpty)
        XCTAssertEqual(shared.takeImports().count, 2, "BLE: cada entrenamiento verificado se empaqueta como .avo para importarlo")
        XCTAssertEqual(shared.downloaded("S0002")?.sha256, AvoHex.lower(w.bleSha("S0002")), "BLE: índice con la huella del reloj")
        XCTAssertTrue(states.contains { $0.state == .downloading && $0.viaBle && $0.label.hasPrefix("Descargando por Bluetooth (más lento)…") },
                      "BLE: la interfaz dice que se descarga por Bluetooth")
        XCTAssertTrue(states.allSatisfy { $0.viaBle })
    }

    // ---------------------------------------------------------------- resume
    func testResumeAfterCutMidSegment() async throws {
        let w = try makeWatch()
        let id = "S1E8C_000035_001"
        w.addBleSession(id, [10_000], seed: 35)
        let e = try await entry(w, id)
        w.disconnectAfterReads = 2                 // the link drops after 4096 B of a 10000 B segment
        do {
            _ = try await BleSessionDownloader(client: clientOf(w), options: fast()).download(e, dir: dirFor(id))
            XCTFail("sin enlace la descarga no puede terminar")
        } catch let err as BleDownloadError {
            XCTAssertTrue((err.errorDescription ?? "").contains("perdida"), err.errorDescription ?? "")
        }
        XCTAssertEqual(localBytes(id), 4_096, "BLE: lo recibido (bloques verificados) se conserva en disco")
        // reconnection: new link, new client
        w.linkUp = true
        w.client = AvoClient(w, startMsgId: 900)
        let before = w.readLog.count
        let r = try await BleSessionDownloader(client: clientOf(w), options: fast()).download(e, dir: dirFor(id))
        XCTAssertEqual(r, .verified(sha256: AvoHex.lower(w.bleSha(id)), bytes: 10_000))
        XCTAssertEqual(w.readLog[before].2, 4_096, "BLE: reanuda en el desplazamiento local, no desde cero")
        XCTAssertEqual(w.fileReads, 5, "BLE: ningún bloque se pide dos veces (2048 × 4 + 1808)")
        XCTAssertEqual(localSegments(id), w.bleSessions[id] ?? [])
    }

    // ---------------------------------------------------------------- integrity
    func testShaMismatchRejected() async throws {
        let w = try makeWatch()
        w.addBleSession("S0007", [3_000], seed: 7)
        w.wrongBleSha = true
        var sunk = 0
        let sync = BleTrainingSync(client: clientOf(w), dirFor: { [root] (id: String) -> String in AvoFiles.join(root, "descargas", id) },
                                   sink: { (_: String, _: String, _: String, _: Int64) async throws -> Void in sunk += 1 }, options: fast())
        let rep = try await sync.sync(ids: ["S0007"])
        XCTAssertTrue(rep.verified.isEmpty)
        XCTAssertEqual(rep.failed["S0007"], "Huella SHA-256 distinta", "BLE: huella distinta del reloj rechazada")
        XCTAssertEqual(sunk, 0, "BLE: nada se importa sin huella correcta")
        XCTAssertTrue(WifiDownloader.segFiles(dirFor("S0007")).isEmpty, "BLE: la copia local no válida se descarta")
        XCTAssertEqual(w.bleSessions["S0007"]?.count, 1, "BLE: el original del reloj no se toca")
    }

    // ---------------------------------------------------------------- recording
    func testRefusedWhileRecording() async throws {
        let w = try makeWatch()
        w.addBleSession("S0012", [9_000], seed: 12)
        w.recording = true
        let sync = BleTrainingSync(client: clientOf(w), dirFor: { [root] (id: String) -> String in AvoFiles.join(root, "descargas", id) },
                                   sink: { (_: String, _: String, _: String, _: Int64) async throws -> Void in }, options: fast())
        let rep = try await sync.sync(ids: ["S0012"])
        XCTAssertEqual(rep.failed["S0012"], "grabando", "BLE: con el reloj grabando no se descarga")
        XCTAssertEqual(w.fileReads, 0, "BLE: ni un READ_FILE mientras graba")
        XCTAssertEqual(sync.progress.state, .waiting)
        // starts recording in the middle of a download: stops, keeps what it has, resumes later
        w.recording = false
        let e = try await entry(w, "S0012")
        w.recordAfterReads = 2
        do {
            _ = try await BleSessionDownloader(client: clientOf(w), options: fast()).download(e, dir: dirFor("S0012"))
            XCTFail("debe parar al empezar a grabar")
        } catch let err as BleDownloadError {
            XCTAssertEqual(err, .recording)
        }
        XCTAssertEqual(localBytes("S0012"), 4_096)
        w.recording = false
        let r = try await BleSessionDownloader(client: clientOf(w), options: fast()).download(e, dir: dirFor("S0012"))
        XCTAssertEqual(r, .verified(sha256: AvoHex.lower(w.bleSha("S0012")), bytes: 9_000))
    }

    // ---------------------------------------------------------------- small pieces
    func testCodecsChunkSizeAndGuardReset() async throws {
        let w = try makeWatch()
        let c = try XCTUnwrap(w.client)
        let info = try await c.getInfo()
        XCTAssertEqual(BleDownloadOptions.chunkSize(info: nil, attPayload: 244), 2048)
        XCTAssertEqual(BleDownloadOptions.chunkSize(info: info, attPayload: 244), 2048)
        XCTAssertEqual(BleDownloadOptions.chunkSize(info: nil, attPayload: 100), 16 * 88 - 12, "3.7.3: 16 notificaciones por respuesta")
        let chunk = WatchFileChunk(offset: 4096, fileSize: 9000, crc32: WatchFileChunk.crc([1, 2, 3]), data: [1, 2, 3])
        XCTAssertEqual(WatchFileChunk.decode(chunk.encode()), chunk)
        XCTAssertEqual(BleFileRequests.readFile("S1", segment: 2, offset: 4096, length: 2048).count, 24 + 2 + 4 + 4)
        // «Volver a intentar el Wi-Fi»
        let suite = "avo-guard-" + UUID().uuidString
        let d = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite) }
        let g = WifiBootGuard(d)
        XCTAssertTrue(g.check(info))
        g.markAttempt(info)
        var rebooted = info
        rebooted.bootCount += 1
        XCTAssertFalse(g.check(rebooted), "guarda: reinicio al activar el Wi-Fi → bloqueado")
        XCTAssertEqual(g.blockedFirmware, info.firmware)
        g.reset()
        XCTAssertNil(g.blockedFirmware)
        XCTAssertTrue(g.check(rebooted), "guarda: tras «Volver a intentar el Wi-Fi» se puede probar otra vez")
        XCTAssertEqual(WatchWifiModel.pendingText("pendiente"), "Pendiente: se reanuda en la próxima descarga (lo ya recibido se conserva).",
                       "sin «Pendiente: Pendiente:»")
        XCTAssertEqual(WatchWifiModel.pendingText("ocupado"), "Pendiente: El reloj está ocupado; vuelve a intentarlo en unos segundos.")
    }
}
