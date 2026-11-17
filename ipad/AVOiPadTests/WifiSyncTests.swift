import XCTest
@testable import AVO_Horse

/// Wi-Fi download (replaces the Windows USB download on iPad). Mirrors the most important cases of the Android
/// core/wifi/WifiSyncTest.kt against SimWifiWatch (SimWatch.swift), plus the HTTP layer with a stubbed WatchHttpClient.
final class WifiSyncTests: XCTestCase {
    private var root: String = ""
    private var w: SimWifiWatch!
    private final class Saved { var d: [String: String] = [:] }
    private var saved = Saved()

    override func setUpWithError() throws {
        root = (NSTemporaryDirectory() as NSString).appendingPathComponent("avo-wifi-" + UUID().uuidString)
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        w = SimWifiWatch()
        saved = Saved()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: root)
    }

    private func dirFor(_ id: String) -> String { AvoFiles.join(root, id) }

    private func coordinator(connector: WifiConnector? = nil) -> WifiSyncCoordinator {
        let box = saved
        let r = root
        return WifiSyncCoordinator(control: w.control, connector: connector ?? w.connector, dirFor: { AvoFiles.join(r, $0) },
                                   sink: { id, _, sha, _ in box.d[id] = sha })
    }

    private func localBytes(_ id: String) -> Int64 {
        WifiDownloader.segFiles(dirFor(id)).reduce(Int64(0)) { $0 + AvoFiles.size($1) }
    }

    func testSmallFile() async throws {
        w.add("S0001", [3_700], seed: 1)
        let rep = try await coordinator().sync([("S0001", nil)])
        XCTAssertEqual(rep.verified, ["S0001"])
        XCTAssertEqual(saved.d["S0001"], w.sha("S0001"))
        XCTAssertEqual(w.starts, 1)
        XCTAssertEqual(w.stops, 1, "Wi-Fi apagado al terminar")
        XCTAssertTrue(w.completes.last?.hasSuffix(":true") ?? false, "confirmación final → el reloj apaga el Wi-Fi")
    }

    func testSeveralSegmentsWithOneActivation() async throws {
        w.add("S1301", [10_000], seed: 2)
        w.add("S1302", [200_000, 50_000], seed: 3)
        let rep = try await coordinator().sync([("S1301", nil), ("S1302", nil)])
        XCTAssertEqual(rep.verified, ["S1301", "S1302"])
        XCTAssertEqual(WifiDownloader.segFiles(dirFor("S1302")).map { AvoFiles.fileName($0) }, ["P001.avr", "P002.avr"])
        XCTAssertEqual(localBytes("S1302"), 250_000)
        XCTAssertEqual(try WifiDownloader.sha256(dirFor("S1302")), w.sha("S1302"))
        XCTAssertTrue(w.starts == 1 && w.stops == 1)
    }

    /// Wi-Fi cut halfway: the valid part is kept; the next pass only downloads what is missing (Range resume).
    func testResumeAfterCut() async throws {
        w.add("S0003", [600_000, 400_000], seed: 4)
        w.cutAfter = 450_000
        let c = coordinator()
        let r1 = try await c.sync([("S0003", nil)])
        XCTAssertTrue(r1.verified.isEmpty)
        XCTAssertEqual(w.stops, 1, "apagado incluso con error")
        let partial = localBytes("S0003")
        XCTAssertTrue(partial >= 400_000 && partial <= 460_000, "se conserva el avance válido (\(partial))")
        w.bytesServed = 0
        let r2 = try await c.sync([("S0003", nil)])
        XCTAssertEqual(r2.verified, ["S0003"])
        XCTAssertEqual(w.bytesServed, 1_000_000 - partial, "solo se descarga lo que falta")
        XCTAssertEqual(saved.d["S0003"], w.sha("S0003"))
    }

    /// App restarted (new coordinator): resumes from the files on disk.
    func testRestartResumesFromDisk() async throws {
        w.add("S0018", [500_000], seed: 5)
        w.cutAfter = 200_000
        _ = try await coordinator().sync([("S0018", nil)])
        w.bytesServed = 0
        let rep = try await coordinator().sync([("S0018", nil)])
        XCTAssertEqual(rep.verified, ["S0018"])
        XCTAssertTrue(w.bytesServed >= 290_000 && w.bytesServed <= 310_000)
    }

    /// The file changed on the watch during the download (etag / If-Match): mixed data is never verified, then it is repeated.
    func testEtagChangeDiscardsAndRepeats() async throws {
        w.add("S0006", [300_000, 300_000], seed: 6)
        w.modifyAfter = 100_000
        let c = coordinator()
        let r1 = try await c.sync([("S0006", nil)])
        XCTAssertFalse(r1.verified.contains("S0006"), "no se verifican datos mezclados")
        XCTAssertEqual(r1.failed["S0006"], "El fichero cambió; se repetirá")
        let r2 = try await c.sync([("S0006", nil)])
        XCTAssertEqual(r2.verified, ["S0006"])
        XCTAssertEqual(saved.d["S0006"], w.sha("S0006"), "contenido final = contenido actual del reloj")
    }

    func testShaMismatchRejected() async throws {
        w.add("S0007", [50_000], seed: 7)
        w.wrongSha = true
        let rep = try await coordinator().sync([("S0007", nil)])
        XCTAssertTrue(rep.verified.isEmpty)
        XCTAssertEqual(rep.failed["S0007"], "Huella SHA-256 distinta")
        XCTAssertTrue(saved.d.isEmpty)
        XCTAssertTrue(WifiDownloader.segFiles(dirFor("S0007")).isEmpty, "no queda nada sin verificar")
    }

    func testDuplicateAlreadyVerifiedNotDownloadedAgain() async throws {
        w.add("S0008", [80_000], seed: 8)
        let c = coordinator()
        _ = try await c.sync([("S0008", nil)])
        w.bytesServed = 0
        let rep = try await c.sync([("S0008", saved.d["S0008"])])
        XCTAssertEqual(rep.verified, ["S0008"])
        XCTAssertEqual(w.bytesServed, 0)
    }

    func testRecordingNeverStartsWifi() async throws {
        w.add("S0012", [1000], seed: 9)
        w.recording = true
        let c = coordinator()
        let rep = try await c.sync([("S0012", nil)])
        XCTAssertTrue(rep.verified.isEmpty)
        XCTAssertEqual(w.starts, 0)
        XCTAssertEqual(c.progress.state, .waiting)
    }

    /// Recording starts during the download (the watch answers 409 from then on): transfer stopped, Wi-Fi off, nothing saved.
    func testRecordingDuringDownloadStops() async throws {
        w.add("S012B", [500_000], seed: 10)
        let rep = try await coordinator(connector: WifiTestRecordingMidway(w.connector, w)).sync([("S012B", nil)])
        XCTAssertTrue(rep.verified.isEmpty)
        XCTAssertEqual(rep.failed["S012B"], "grabando")
        XCTAssertEqual(w.stops, 1)
        XCTAssertTrue(saved.d.isEmpty)
    }

    func testNoMicroSdAndLowBattery() async throws {
        w.add("S0009", [1000], seed: 11)
        w.sd = false
        let rep = try await coordinator().sync([("S0009", nil)])
        XCTAssertTrue(rep.verified.isEmpty && rep.fallbackBle.isEmpty)
        XCTAssertEqual(rep.failed["S0009"], "sin microSD")
        w.sd = true
        w.batteryPct = 10
        let rep2 = try await coordinator().sync([("S0009", nil)])
        XCTAssertEqual(rep2.failed["S0009"], "batería baja")
        XCTAssertEqual(w.starts, 0)
    }

    func testUnsupportedOrNotJoinedFallsBack() async throws {
        w.add("S0016", [5_000], seed: 12)
        w.connectFails = true
        let rep = try await coordinator().sync([("S0016", nil)])
        XCTAssertEqual(rep.fallbackBle, ["S0016"])
        XCTAssertEqual(w.stops, 1, "el Wi-Fi del reloj se apaga aunque el iPad no se una")
        w.connectFails = false
        w.wifiSupported = false
        let rep2 = try await coordinator().sync([("S0016", nil)])
        XCTAssertEqual(rep2.fallbackBle, ["S0016"])
    }

    func testCancelWhileConnecting() async throws {
        w.add("S0014", [1_000_000], seed: 13)
        let conn = WifiTestCancelOnConnect(w.connector)
        let c = coordinator(connector: conn)
        conn.c = c
        let rep = try await c.sync([("S0014", nil)])
        XCTAssertFalse(rep.verified.contains("S0014"))
        XCTAssertTrue(saved.d.isEmpty)
        XCTAssertEqual(c.progress.state, .cancelled)
        XCTAssertTrue(w.starts == 1 && w.stops == 1, "Wi-Fi siempre apagado")
    }

    func testRebootInvalidatesToken() async throws {
        w.add("S0017", [300_000], seed: 14)
        let r1 = try await coordinator(connector: WifiTestStaleToken(w.connector)).sync([("S0017", nil)])
        XCTAssertEqual(r1.failed["S0017"], "Token rechazado por el reloj")
        w.token = String(repeating: "c", count: 32)                 // reboot: new token on the next start
        let r2 = try await coordinator().sync([("S0017", nil)])
        XCTAssertEqual(r2.verified, ["S0017"])
    }

    func testSyncAvailableListsClosedTrainings() async throws {
        w.add("S2001", [20_000], seed: 15)
        w.add("S2002", [30_000], seed: 16)
        w.add("S2003", [40_000], seed: 17)
        w.open.insert("S2003")                                       // still recording / not closed: never served
        let rep = try await coordinator().syncAvailable { (t: RemoteTraining) -> String?? in
            if t.id == "S2002" { return nil }
            return .some(nil)
        }
        XCTAssertEqual(rep.verified, ["S2001"])
        XCTAssertEqual(Set(saved.d.keys), ["S2001"])
    }

    // ---------------------------------------------------------------- protocol pieces

    func testCredentialsDecodeAndNoSecretsInDescription() throws {
        let b = LeWriter().u8(1).str("AVO_CHEST_1A2B", 33).str("Secreto12345678", 33).str(String(repeating: "f", count: 32), 33)
            .str("192.168.4.1", 16).bytes([1, 2, 3, 4, 5, 6]).u8(1).u16(80).u16(45).toArray()
        let c = try XCTUnwrap(WifiCredentials.decode(b))
        XCTAssertEqual(c.ssid, "AVO_CHEST_1A2B")
        XCTAssertEqual(c.port, 80)
        XCTAssertEqual(c.idleTimeoutS, 45)
        XCTAssertEqual(c.bssidText, "01:02:03:04:05:06")
        XCTAssertFalse("\(c)".contains("Secreto"))
        XCTAssertFalse(String(describing: c).contains("fff"))
        XCTAssertNil(WifiCredentials.decode([2]))
    }

    func testJsonParsing() throws {
        let l = WatchHttpJson.parseList("""
        {"trainings":[{"id":"S1E8C_000150_001","state":2,"ready":true,"segments":2,"size":3700,"start_rtc_ms":1792368000000,"active_ms":4000,"etag":"0a0b0c0d"}]}
        """)
        XCTAssertEqual(l.count, 1)
        XCTAssertEqual(l.first?.id, "S1E8C_000150_001")
        XCTAssertEqual(l.first?.startRtcMs, 1792368000000)
        let m = try WatchHttpJson.parseMeta("""
        {"id":"S1","state":2,"ready":true,"raw_format":3,"size":30,"etag":"ab","segments":[10,20]}
        """)
        XCTAssertEqual(m.segmentSizes, [10, 20])
        XCTAssertEqual(m.rawFormat, 3)
        XCTAssertEqual(WatchHttpJson.parseSha("{\"sha256\":\"" + String(repeating: "AB", count: 32) + "\"}"), String(repeating: "ab", count: 32))
    }

    /// Stubbed HTTP layer (no URLSession): requests carry the token, Range and If-Match; status codes map to the logic errors.
    private final class StubClient: WatchHttpClient {
        var requests: [URLRequest] = []
        var status = 200
        var body = Data()
        var segment: [UInt8] = []
        func send(_ request: URLRequest) async throws -> (status: Int, body: Data) {
            requests.append(request)
            return (status, body)
        }
        func stream(_ request: URLRequest) async throws -> (status: Int, stream: WatchByteStream) {
            requests.append(request)
            return (status, BytesWatchStream(segment))
        }
    }

    func testUrlWatchHttpRequestsAndStatus() async throws {
        let creds = WifiCredentials(ssid: "AVO_CHEST_1A2B", password: "pw-123456789", token: String(repeating: "f", count: 32), ip: "192.168.4.1",
                                    bssid: [1, 2, 3, 4, 5, 6], channel: 1, port: 80, idleTimeoutS: 45)
        let stub = StubClient()
        let http = UrlWatchHttp(creds, client: stub)
        stub.body = Data("{\"trainings\":[]}".utf8)
        _ = try await http.list()
        let r0 = try XCTUnwrap(stub.requests.last)
        XCTAssertEqual(r0.url?.absoluteString, "http://192.168.4.1:80/api/v1/trainings")
        XCTAssertEqual(r0.value(forHTTPHeaderField: "Authorization"), "Bearer " + String(repeating: "f", count: 32))

        stub.status = 206
        stub.segment = [1, 2, 3]
        let s = try await http.openSegment("S0001", seg: 2, from: 1000, etag: "0a0b0c0d")
        let r1 = try XCTUnwrap(stub.requests.last)
        XCTAssertEqual(r1.url?.path, "/api/v1/trainings/S0001/segments/2")
        XCTAssertEqual(r1.value(forHTTPHeaderField: "Range"), "bytes=1000-")
        XCTAssertEqual(r1.value(forHTTPHeaderField: "If-Match"), "\"0a0b0c0d\"")
        let got = try await s.read(maxLength: 10)
        XCTAssertEqual(got, [1, 2, 3])

        // a server that ignores Range (200 with the whole segment): the first bytes are skipped
        stub.status = 200
        stub.segment = [9, 9, 7, 8]
        let whole = try await http.openSegment("S0001", seg: 1, from: 2, etag: "x")
        let rest = try await whole.read(maxLength: 10)
        XCTAssertEqual(rest, [7, 8])

        for (code, expected) in [(409, WatchHttpError.recording), (412, WatchHttpError.changed), (401, WatchHttpError.auth)] {
            stub.status = code
            do {
                _ = try await http.openSegment("S0001", seg: 1, from: 0, etag: "x")
                XCTFail("HTTP \(code) debería fallar")
            } catch let e as WatchHttpError {
                XCTAssertEqual(e, expected)
            }
        }
        stub.status = 409
        do {
            _ = try await http.metadata("S0001")
            XCTFail("409 mientras graba")
        } catch let e as WatchHttpError {
            XCTAssertEqual(e, .recording)
            XCTAssertEqual(e.localizedDescription, "El reloj está grabando")
        }
        stub.status = 200
        try await http.complete("S0001", sha256: "ab", done: true)
        let rc = try XCTUnwrap(stub.requests.last)
        XCTAssertEqual(rc.httpMethod, "POST")
        XCTAssertEqual(String(decoding: rc.httpBody ?? Data(), as: UTF8.self), "id=S0001&sha256=ab&done=1")
    }
}

// ---------------------------------------------------------------- connector wrappers used by the tests

/// Sets recording = true on the watch after 100 kB of a segment (Android t12b).
final class WifiTestRecordingMidway: WifiConnector {
    let inner: WifiConnector
    let w: SimWifiWatch
    init(_ inner: WifiConnector, _ w: SimWifiWatch) { self.inner = inner; self.w = w }
    final class Http: WatchHttp {
        let h: WatchHttp
        let w: SimWifiWatch
        init(_ h: WatchHttp, _ w: SimWifiWatch) { self.h = h; self.w = w }
        func list() async throws -> [RemoteTraining] { try await h.list() }
        func metadata(_ id: String) async throws -> RemoteMeta { try await h.metadata(id) }
        func sha256(_ id: String) async throws -> String { try await h.sha256(id) }
        func complete(_ id: String, sha256: String, done: Bool) async throws { try await h.complete(id, sha256: sha256, done: done) }
        func openSegment(_ id: String, seg: Int, from: Int64, etag: String) async throws -> WatchByteStream {
            let inner = try await h.openSegment(id, seg: seg, from: from, etag: etag)
            return S(inner, w)
        }
    }
    final class S: WatchByteStream {
        let s: WatchByteStream
        let w: SimWifiWatch
        var n = 0
        init(_ s: WatchByteStream, _ w: SimWifiWatch) { self.s = s; self.w = w }
        func read(maxLength: Int) async throws -> [UInt8] {
            if n > 100_000 { w.recording = true }
            let r = try await s.read(maxLength: maxLength)
            n += r.count
            return r
        }
        func close() { s.close() }
    }
    final class L: WifiLink {
        let http: WatchHttp
        init(_ http: WatchHttp) { self.http = http }
        func close() async {}
    }
    func connect(_ creds: WifiCredentials) async -> WifiLink? {
        guard let l = await inner.connect(creds) else { return nil }
        return L(Http(l.http, w))
    }
}

/// The user cancels while the iPad joins the watch network.
final class WifiTestCancelOnConnect: WifiConnector {
    let inner: WifiConnector
    weak var c: WifiSyncCoordinator?
    init(_ inner: WifiConnector) { self.inner = inner }
    func connect(_ creds: WifiCredentials) async -> WifiLink? {
        let l = await inner.connect(creds)
        c?.cancel()
        return l
    }
}

/// Connects with a stale token (the watch rebooted).
final class WifiTestStaleToken: WifiConnector {
    let inner: WifiConnector
    init(_ inner: WifiConnector) { self.inner = inner }
    func connect(_ creds: WifiCredentials) async -> WifiLink? {
        var c = creds
        c.token = String(repeating: "b", count: 32)
        return await inner.connect(c)
    }
}
