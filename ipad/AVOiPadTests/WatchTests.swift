import XCTest
@testable import AVO_Horse

/// Geofences / start-finish lines / watch protocol. Port of windows/AVO.Windows.SelfTest/WatchTests.cs. Codecs are checked
/// against vectors produced by the REAL chest firmware code (tools/watch-vectors, watch_vectors.json); the end-to-end flow
/// runs against a simulated watch (SimWatch.swift) over the same BLE framing. No Bluetooth hardware involved.
final class WatchTests: XCTestCase {
    private var dir: String = ""

    override func setUpWithError() throws {
        dir = (NSTemporaryDirectory() as NSString).appendingPathComponent("avo-watch-" + UUID().uuidString)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: dir)
    }

    private func vectors() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle(for: WatchTests.self).url(forResource: "watch_vectors", withExtension: "json"), "watch_vectors.json en el paquete de pruebas")
        return try XCTUnwrap(AvoJSON.object(try Data(contentsOf: url)))
    }

    private func hex(_ v: [String: Any], _ k: String) throws -> [UInt8] {
        let s = try XCTUnwrap(v[k] as? String)
        return try XCTUnwrap(AvoHex.bytes(s))
    }

    // ---------------------------------------------------------------- firmware vectors
    func testVectors() throws {
        let v = try vectors()
        let blob = try hex(v, "config")
        let c = try WatchConfig.decode(blob)
        XCTAssertTrue(c.horseName == "HORSE_001" && c.riderName == "RIDER_007" && c.activeMask == 5 && c.fenceCount == 3,
                      "Reloj: configuración del firmware decodificada (identidad y geocercas activas)")
        let f0 = try XCTUnwrap(c.fences[0]), f1 = try XCTUnwrap(c.fences[1]), f2 = try XCTUnwrap(c.fences[2])
        XCTAssertTrue(f0.type == .circle && f0.radiusCm == 15000 && f0.name == "Regaton" && f2.type == .polygon && f2.verts.count == 4
                      && f1.type == FenceType.none, "Reloj: círculo, hueco vacío y polígono como los guarda el firmware")
        XCTAssertTrue(c.lines[0].enabled && c.lines[0].aLatE7 == 434240000 && c.lines[2].enabled && !c.lines[1].enabled, "Reloj: líneas virtuales del firmware")
        XCTAssertEqual(c.encode(), blob, "Reloj: SET_CONFIG byte a byte igual que config_serialize() del firmware")
        let w = LeWriter()
        f2.encodeBody(w)
        XCTAssertEqual(w.toArray(), try hex(v, "fence_polygon"), "Reloj: geocerca SET_FENCE igual que fence_serialize()")
        let val = try XCTUnwrap(v["validate"] as? [String: Any])
        func vi(_ k: String) -> Int { (val[k] as? NSNumber)?.intValue ?? -1 }
        XCTAssertTrue(vi("ok_polygon") == 0 && f2.validate() == nil, "Reloj: polígono válido para el firmware y para el iPad")
        let bow = Fence(0, .polygon, "Lazo", vertices: [GeoE7(434250000, -34530000), GeoE7(434260000, -34510000), GeoE7(434260000, -34530000), GeoE7(434250000, -34510000)])
        let tiny = Fence(0, .polygon, "Mini", vertices: [GeoE7(434250000, -34530000), GeoE7(434250200, -34530000), GeoE7(434250200, -34529800)])
        let small = Fence(0, .circle, "C", center: GeoE7(434247000, -34519000), radiusCm: 400)
        XCTAssertTrue(vi("bowtie") != 0 && (bow.validate() ?? "").contains("corta"), "Reloj: polígono que se corta rechazado igual que validate_fence()")
        XCTAssertTrue(vi("tiny") != 0 && (tiny.validate() ?? "").contains("pequeña"), "Reloj: área mínima igual que validate_fence()")
        XCTAssertTrue(vi("small_circle") != 0 && (small.validate() ?? "").contains("radio"), "Reloj: radio mínimo igual que validate_fence()")
        XCTAssertEqual(BleFraming.build(MsgType.setActiveFences.rawValue, 0x1234, 0, 1, 0x01, 0, [5, 1]), try hex(v, "frag_set_active"),
                       "Reloj: fragmento BLE igual que ble_frag_build()")
        let key: [UInt8] = (0..<32).map { UInt8($0) }
        let pn: [UInt8] = (0..<16).map { UInt8(0xA0 + $0) }
        let wn: [UInt8] = (0..<16).map { UInt8(0x50 + $0) }
        XCTAssertEqual(AvoHex.lower(try WatchAuth.watchProof(key, pn, wn, "a0b1c2d3e4f5")), (v["watch_proof"] as? String ?? "").lowercased(),
                       "Reloj: prueba HMAC del reloj igual que avo_ble_auth")
        XCTAssertEqual(AvoHex.lower(try WatchAuth.phoneProof(key, wn, pn, "a0b1c2d3e4f5")), (v["phone_proof"] as? String ?? "").lowercased(),
                       "Reloj: prueba HMAC del iPad igual que avo_ble_auth")
        let cr: [Bool] = ((v["crosses"] as? [Any]) ?? []).map { (($0 as? NSNumber)?.intValue ?? 0) == 1 }
        XCTAssertEqual(cr.count, 4)
        let c1 = LineAnalysis.crosses(0, 0, 10, 0, 5, 3, 5, -3)
        let c2 = LineAnalysis.crosses(0, 0, 10, 0, 5, -3, 5, 3)
        XCTAssertTrue(c1.crosses == cr[0] && c2.crosses == cr[1] && LineAnalysis.crosses(0, 0, 10, 0, 1, 1, 9, 1).crosses == cr[2]
                      && LineAnalysis.crosses(0, 0, 10, 0, 15, 3, 15, -3).crosses == cr[3], "Líneas: mismo test de cruce que el reloj (avo_session.cpp)")
        XCTAssertTrue(c1.leftToRight && !c2.leftToRight, "Líneas: sentido del cruce (izquierda→derecha mirando de A a B)")
        XCTAssertEqual(Crc16.compute(Array("123456789".utf8)), 0x29B1, "Reloj: CRC-16/CCITT-FALSE")
    }

    func testFramingAndReassembly() throws {
        let payload: [UInt8] = (0..<600).map { UInt8($0 & 0xFF) }
        let frags = try BleFraming.fragment(MsgType.getConfig.rawValue, 77, payload, 100)
        XCTAssertEqual(frags.count, BleFraming.count(600, 100))
        let r = BleReassembler()
        var out: BleMessage? = nil
        for f in frags { if let m = r.feed(f) { out = m } }
        XCTAssertEqual(out?.payload, payload, "Reloj: fragmentos reensamblados en orden")
        var bad = frags[0]
        bad[bad.count - 1] ^= 0xFF
        XCTAssertNil(r.feed(bad))
        XCTAssertEqual(r.crcErrors, 1, "Reloj: fragmento con CRC erróneo descartado")
        let info = WatchInfo.decode(LeWriter().u8(1).u8(1).u16(1).u16(1).str("3.7.4-wifi", 16).str("a0b1", 16).u32(3).u16(247).u32(0x8FF).toArray())
        XCTAssertEqual(info?.supportsWifiSync, true, "Reloj: bit 11 de capacidades = descarga por Wi-Fi")
        XCTAssertEqual(info?.supportsAuth, true)
        XCTAssertNil(info?.authorized)
    }

    // ---------------------------------------------------------------- crossings of a recorded track
    private func track(_ pts: [(Double, Double)]) -> SessionTimeline {
        let s = TrainingSession()
        s.sessionId = "SINTETICA_LINEAS"
        let v = 4.0
        let t0 = Date(timeIntervalSince1970: 1792649700)   // 2026-10-22 06:15:00 UTC
        for (i, p) in pts.enumerated() {
            let itow: Int64 = 345_600_000 + Int64(i) * 1000
            s.track.append(TrackPoint(latitude: p.0, longitude: p.1, speedMs: v, accuracyM: 0.014, carrierSolution: 2, gpsWeekMs: itow,
                                      altitudeM: 52, elapsedSeconds: nil, fixType: 3, numSv: 26, diffSoln: true, speedAccMs: 0.05,
                                      velNorthMs: 0, velEastMs: v, headingDeg: 90, mslAltitudeM: 2.0, utcTime: t0.addingTimeInterval(Double(i)),
                                      chestUs: UInt64((i + 500) * 1_000_000)))
            s.gnssEpochs.append(GnssEpoch(gpsWeekMs: itow, solution: .rtkFix, numSv: 26, hAccM: 0.014, chestUs: 0))
            s.gnssSamples += 1
        }
        return SessionTimeline.build(s)
    }

    func testLines() throws {
        // line along the beach (west → east), crossings going north (right→left) and south (left→right)
        let line = PlanLine(enabled: true, name: "Meta", role: .startFinish, a: PlanPoint(43.42400, -3.45300), b: PlanPoint(43.42400, -3.45200),
                            direction: .leftToRight)
        let latN = 43.42403, latS = 43.42397, lon = -3.45290, d = 0.00002
        let tl = track([(latN, lon), (latS, lon + d), (latS, lon + 2 * d), (latN, lon + 3 * d), (latN, lon + 4 * d), (latS, lon + 5 * d),
                        (latS, lon + 6 * d), (latN, lon + 7 * d), (latN, lon + 8 * d), (latS, lon + 9 * d)])
        XCTAssertGreaterThanOrEqual(tl.count, 10, "Líneas: recorrido sintético")
        if tl.count < 10 { return }
        let all = LineAnalysis.detect(tl, line, 0)
        XCTAssertTrue(all.count == 5 && all.filter { $0.leftToRight }.count == 3, "Líneas: 5 cruces, 3 hacia el sur (izquierda→derecha)")
        XCTAssertTrue(all.filter { $0.counts }.allSatisfy { $0.leftToRight } && all.filter { $0.counts }.count == 3,
                      "Líneas: solo marcan los cruces en el sentido elegido")
        XCTAssertTrue(!all.isEmpty && abs(all[0].t - (tl.t[0] + 0.5)) < 0.02, "Líneas: hora del cruce interpolada entre épocas")
        let runs = LineAnalysis.runs([line], all)
        XCTAssertTrue(runs.count == 2 && runs.allSatisfy { $0.durationS > 0 }, "Líneas: vueltas entre cruces válidos de salida/meta")
        line.direction = .both
        XCTAssertTrue(LineAnalysis.detect(tl, line, 0).allSatisfy { $0.counts }, "Líneas: «ambos sentidos» marca todos (lo que hace el reloj)")
        let start = PlanLine(enabled: true, name: "Salida", role: .start, a: line.a, b: line.b, direction: .leftToRight)
        let fin = PlanLine(enabled: true, name: "Meta", role: .finish, a: PlanPoint(43.42390, -3.45281), b: PlanPoint(43.42410, -3.45281), direction: .both)
        let cs = LineAnalysis.detect(tl, start, 0) + LineAnalysis.detect(tl, fin, 1)
        XCTAssertTrue(LineAnalysis.runs([start, fin], cs).contains { $0.kind.hasPrefix("Salida → meta") }, "Líneas: tramo de salida a meta")
        // the same analysis on plain arrays (LineTrackData)
        let plain = LineTrackData(t: tl.t, lat: tl.lat, lon: tl.lon)
        XCTAssertEqual(LineAnalysis.detect(plain, line, 0).count, 5)
    }

    // ---------------------------------------------------------------- plan file
    func testPlan() throws {
        let path = AvoFiles.join(dir, "geocercas", "geocercas.json")
        let p = GeofencePlan.load(path)
        XCTAssertTrue(p.fences.count == 8 && p.lines.count == 4 && p.lines[0].role == .startFinish, "Geocercas: plan vacío con 8 huecos y 4 líneas del reloj")
        p.fences[0] = PlanFence(name: "Regatón", type: .circle, center: PlanPoint(43.4247, -3.4519), radiusM: 150)
        p.fences[3] = PlanFence(name: "Pista", type: .polygon, vertices: [PlanPoint(43.4250, -3.4530), PlanPoint(43.4260, -3.4530), PlanPoint(43.4260, -3.4510)],
                                active: false)
        p.lines[0] = PlanLine(enabled: true, name: "Salida / meta", role: .startFinish, a: PlanPoint(43.4240, -3.4525), b: PlanPoint(43.42405, -3.4520),
                              direction: .rightToLeft)
        XCTAssertTrue(p.problems().isEmpty && p.activeMask == 0x01, "Geocercas: plan válido y máscara de activas")
        try p.save(path)
        let q = GeofencePlan.load(path)
        XCTAssertTrue(q.fences[3]?.vertices.count == 3 && q.lines[0].direction == .rightToLeft && q.fences[0]?.name == "Regatón",
                      "Geocercas: se guarda y se vuelve a leer")
        XCTAssertTrue(q.fences[3]?.active == false && q.fences[0]?.radiusM == 150)
        q.fences[1] = PlanFence(name: "Nombre demasiado largo", center: PlanPoint(43.4, -3.4))
        q.lines[2] = PlanLine(enabled: true, name: "Meta", a: PlanPoint(43.4, -3.4))
        XCTAssertEqual(q.problems().count, 2, "Geocercas: nombre > 15 B y línea sin extremo B detectados antes de enviar")
        try Data("{ roto".utf8).write(to: URL(fileURLWithPath: path))
        let damaged = GeofencePlan.load(path)
        let copies = try FileManager.default.contentsOfDirectory(atPath: (path as NSString).deletingLastPathComponent)
            .filter { $0.hasPrefix("geocercas.json.danado-") }
        XCTAssertTrue(damaged.fences.allSatisfy { $0 == nil } && copies.count >= 1, "Geocercas: archivo dañado se conserva aparte")
    }

    /// geocercas.json as AVO Windows writes it (JsonStringEnumConverter, computed E7/LengthM/ActiveMask included) is read.
    func testPlanReadsWindowsJson() throws {
        let path = AvoFiles.join(dir, "geocercas.json")
        let json = """
        {"Version":1,"Fences":[{"Name":"Regatón","Type":"Circle","Center":{"Lat":43.4247,"Lon":-3.4519,"E7":{"LatE7":434247000,"LonE7":-34519000,"Lat":43.4247,"Lon":-3.4519,"Valid":true}},"RadiusM":150,"Vertices":[],"Active":true},null,null,null,null,null,null,null],
         "AutoEnabled":false,"Lines":[{"Enabled":true,"Name":"Salida / meta","Role":"StartFinish","A":{"Lat":43.424,"Lon":-3.4525},"B":{"Lat":43.42405,"Lon":-3.452},"Direction":"RightToLeft","LengthM":41.0}],
         "LastSent":"2026-10-30T12:00:00.1234567+01:00","LastSentTo":"AVO_1A2B","ActiveMask":1}
        """
        try Data(json.utf8).write(to: URL(fileURLWithPath: path))
        let p = GeofencePlan.load(path)
        XCTAssertEqual(p.fences[0]?.name, "Regatón")
        XCTAssertEqual(p.fences[0]?.type, .circle)
        XCTAssertFalse(p.autoEnabled)
        XCTAssertEqual(p.lines.count, 4, "faltan líneas: se completan con las de serie")
        XCTAssertEqual(p.lines[0].direction, .rightToLeft)
        XCTAssertEqual(p.lines[1].role, .start)
        XCTAssertEqual(p.lastSentTo, "AVO_1A2B")
        XCTAssertNotNil(p.lastSent)
    }

    // ---------------------------------------------------------------- simulated watch + full flow
    func testEndToEnd() async throws {
        let v = try vectors()
        // the watch's configuration plus a section this app does not know (tag 42): it must survive
        var baseCfg = try WatchConfig.decode(try hex(v, "config"))
        baseCfg.unknownSections = [ConfigSection(tag: 42, body: [1, 2, 3])]
        let watch = try SimWatch(baseCfg.encode())
        let client = AvoClient(watch, startMsgId: 100)
        watch.client = client
        let store = MemCredentialStore()
        let info = try await WatchAuthorizer.ensure(client, store, clientName: "AVO iPad", progress: nil, claimWaitMs: 5000, pollMs: 10)
        XCTAssertTrue(watch.authorized && store.d[SimWatch.dev] != nil && watch.polls >= 2 && info.deviceId == SimWatch.dev,
                      "Reloj: iPad autorizado con BOOT (misma reclamación que Android)")
        // second connection: the saved key is enough
        watch.authorized = false
        let polls = watch.polls
        let c2 = AvoClient(watch, startMsgId: 300)
        watch.client = c2
        _ = try await WatchAuthorizer.ensure(c2, store, clientName: "AVO iPad", progress: nil, claimWaitMs: 5000, pollMs: 10)
        XCTAssertTrue(watch.authorized && watch.polls == polls, "Reloj: reconexión con la clave guardada, sin volver a pulsar BOOT")

        let plan = GeofencePlan()
        plan.loadFrom(watch.config)
        XCTAssertTrue(plan.fences[0]?.name == "Regaton" && plan.fences[0]?.radiusM == 150 && plan.fences[2]?.vertices.count == 4 && plan.lines[0].enabled,
                      "Geocercas: «Leer del reloj» trae lo que tiene")
        plan.fences[0] = nil                                                                                 // delete slot 1
        plan.fences[4] = PlanFence(name: "Playa sur", type: .circle, center: PlanPoint(43.4230, -3.4500), radiusM: 80)
        plan.lines[1] = PlanLine(enabled: true, name: "Salida", role: .start, a: PlanPoint(43.4245, -3.4525), b: PlanPoint(43.4245, -3.4520),
                                 direction: .leftToRight)
        let rep = try await GeofenceSync.send(c2, plan)
        XCTAssertTrue(rep.verified && GeofenceSync.differences(plan, watch.config).isEmpty, "Envío: el reloj guarda exactamente geocercas, activas y líneas del plan")
        XCTAssertTrue(watch.config.fences[0]?.type == FenceType.none && watch.config.fences[4]?.name == "Playa sur" && watch.config.lines[1].enabled,
                      "Envío: hueco borrado, geocerca nueva y línea de salida")
        XCTAssertTrue(watch.config.unknownSections.contains { $0.tag == 42 } && watch.config.horseName == "HORSE_001",
                      "Envío: lo que no se toca (identidad, secciones desconocidas) se conserva")
        XCTAssertTrue(watch.setFences == 2 && watch.setConfigs == 1, "Envío: solo se envían los cambios (2 geocercas + 1 configuración)")
        let before = watch.setFences + watch.setConfigs + watch.setActives
        let again = try await GeofenceSync.send(c2, plan)
        XCTAssertTrue(again.verified && watch.setFences + watch.setConfigs + watch.setActives == before && again.steps[0].contains("ya tenía"),
                      "Envío: repetir no reescribe nada")
        plan.fences[5] = PlanFence(name: "Mal", type: .polygon, vertices: [PlanPoint(43.4250, -3.4530), PlanPoint(43.4260, -3.4510),
                                                                             PlanPoint(43.4260, -3.4530), PlanPoint(43.4250, -3.4510)])
        var refused = false
        do { _ = try await GeofenceSync.send(c2, plan) } catch let e as AvoError {
            if case .invalidOperation = e { refused = true }
        }
        XCTAssertTrue(refused && watch.setFences + watch.setConfigs + watch.setActives == before, "Envío: un plan inválido no se envía (nada a medias)")
        // without authorization the watch refuses configuration (AUTH_REQUIRED), as the firmware does
        watch.authorized = false
        plan.fences[5] = nil
        var authRefused = false
        do { _ = try await GeofenceSync.send(c2, plan) } catch let e as BleRequestError {
            authRefused = e.status == .authRequired
        }
        XCTAssertTrue(authRefused, "Envío: sin autorización el reloj no acepta cambios")
    }

    /// WIFI_SYNC over the BLE client: start answer parsed, refusal mapped, stop sent (BleWifiControl).
    func testWifiSyncOverBle() async throws {
        let v = try vectors()
        let watch = try SimWatch(try hex(v, "config"))
        let client = AvoClient(watch, startMsgId: 500)
        watch.client = client
        watch.authorized = true
        let info = try await client.getInfo()
        XCTAssertTrue(info.supportsWifiSync)
        let creds = LeWriter().u8(1).str("AVO_CHEST_1A2B", 33).str("Secreto12345678", 33).str(String(repeating: "f", count: 32), 33)
            .str("192.168.4.1", 16).bytes([1, 2, 3, 4, 5, 6]).u8(1).u16(80).u16(45).toArray()
        watch.wifiStartReply = (.ok, creds)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "avo-test-" + UUID().uuidString))
        let ctl = BleWifiControl(client: { client }, info: { info }, isRecording: { false }, bootGuard: WifiBootGuard(defaults))
        guard case .ok(let c) = try await ctl.start() else { return XCTFail("WIFI_SYNC(start) debería dar credenciales") }
        XCTAssertEqual(c.ssid, "AVO_CHEST_1A2B")
        XCTAssertEqual(c.port, 80)
        XCTAssertEqual(watch.wifiStarts, 1)
        await ctl.stop()
        XCTAssertEqual(watch.wifiStops, 1)
        watch.recording = true
        guard case .refused(let reason, let later) = try await ctl.start() else { return XCTFail("grabando debería rechazar") }
        XCTAssertTrue(reason == "grabando" && later)
        let st = try await client.wifiStatus()
        XCTAssertEqual(st.bytesSent, 1234)
        // firmware without bit 11 → unsupported (never by version number)
        var old = info
        old.caps = 0x0FF
        let ctlOld = BleWifiControl(client: { client }, info: { old }, isRecording: { false }, bootGuard: WifiBootGuard(defaults))
        guard case .unsupported = try await ctlOld.start() else { return XCTFail("sin bit 11 no hay Wi-Fi") }
    }
}
