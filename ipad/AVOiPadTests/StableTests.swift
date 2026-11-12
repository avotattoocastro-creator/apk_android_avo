import XCTest
@testable import AVO_Horse

/// Cuadra / Jinetes / assignments and the NFC pieces kept on iPad (avohorse:// identity URI, NDEF, TLV). Port of
/// windows/AVO.Windows.SelfTest/StableTests.cs. The NTAG-through-PC/SC part is not ported (no NFC on iPad).
final class StableTests: XCTestCase {
    private var dir: String = ""

    override func setUpWithError() throws {
        dir = (NSTemporaryDirectory() as NSString).appendingPathComponent("avo-stable-" + UUID().uuidString)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: dir)
    }

    private func throwsInvalid(_ f: () throws -> Void) -> Bool {
        do { try f(); return false } catch let e as AvoError {
            if case .invalidData = e { return true }
            return false
        } catch { return false }
    }

    // ---------------------------------------------------------------- the URI the Android app writes (AvoNfc.kt)
    func testIdentityUri() throws {
        let h = try AvoIdentityTag.parse("avohorse://identity/horse/HORSE_001?v=2&name=Rayo%20de%20Luna&breed=PRE&birthYear=2015&notes=Ca%C3%B1a%20fina&active=true")
        XCTAssertTrue(h.kind == .horse && h.code == "HORSE_001" && h.name == "Rayo de Luna" && h.breed == "PRE" && h.birthYear == 2015
                      && h.notes == "Caña fina" && h.active, "NFC: etiqueta de caballo v2 (formato Android)")
        let r = try AvoIdentityTag.parse("avohorse://identity/rider/RIDER_007")
        XCTAssertTrue(r.kind == .rider && r.code == "RIDER_007" && r.name == "RIDER_007" && r.active && r.birthYear == nil,
                      "NFC: etiqueta antigua solo con identidad")
        let am = try AvoIdentityTag.parse("avohorse://identity/rider/R1?v=2&name=Ana+Mar%C3%ADa&active=false")
        XCTAssertTrue(am.name == "Ana María" && !am.active, "NFC: '+' es espacio y active=false")
        let old = try AvoIdentityTag.parse("avohorse://identity/horse/H1?v=2&birthYear=1850")
        XCTAssertTrue(old.birthYear == nil && old.name == "H1", "NFC: año fuera de rango se ignora")
        XCTAssertTrue(throwsInvalid { _ = try AvoIdentityTag.parse("avohorse://identity/horse/H1?v=3") }, "NFC: versión no compatible rechazada")
        XCTAssertTrue(throwsInvalid { _ = try AvoIdentityTag.parse("avohorse://identity/dog/H1") }, "NFC: tipo desconocido rechazado")
        XCTAssertTrue(throwsInvalid { _ = try AvoIdentityTag.parse("avohorse://identity/horse/" + String(repeating: "X", count: 24)) },
                      "NFC: código de más de 23 caracteres rechazado")
        XCTAssertTrue(throwsInvalid { _ = try AvoIdentityTag.parse("avohorse://identity/horse/%0A") }, "NFC: código con caracteres de control rechazado")
        XCTAssertTrue(throwsInvalid { _ = try AvoIdentityTag.parse("https://example.org/x") }, "NFC: etiqueta no AVO rechazada")
        let rec = IdentityRecord(code: "HORSE_001", name: "Rayo de Luna", breed: "PRE", birthYear: 2015, notes: "")
        XCTAssertEqual(AvoIdentityTag.buildUri(.horse, rec),
                       "avohorse://identity/horse/HORSE_001?v=2&name=Rayo%20de%20Luna&breed=PRE&birthYear=2015&notes=&active=true",
                       "NFC: URI idéntica a AvoNfc.horse() de Android")
        let odd = IdentityRecord(code: "R-9", name: "Ñandú & Co / ¿sí? 100%+", notes: "línea1\nlínea2", active: false)
        let back = try AvoIdentityTag.parse(AvoIdentityTag.buildUri(.rider, odd))
        XCTAssertTrue(back.name == odd.name && back.notes == odd.notes && !back.active && back.code == "R-9", "NFC: ida y vuelta con caracteres especiales")
        XCTAssertTrue(AvoIdentityTag.matchesCodePattern("HORSE_001") && !AvoIdentityTag.matchesCodePattern("HORSE 001"), "Código: patrón de la ficha")
    }

    // ---------------------------------------------------------------- NDEF
    func testNdefCodec() throws {
        let m = Ndef.uriMessage("avohorse://identity/rider/RIDER_007")
        let expect: [UInt8] = [0xD1, 0x01, 0x24, 0x55, 0x00] + Array("avohorse://identity/rider/RIDER_007".utf8)
        XCTAssertEqual(m, expect, "NDEF: registro URI corto como NdefRecord.createUri (sin abreviatura)")
        XCTAssertEqual(try Ndef.uris(m), ["avohorse://identity/rider/RIDER_007"], "NDEF: lectura del registro URI")
        let www = Ndef.uriMessage("https://www.avo.org")
        let wwwUris = try Ndef.uris(www)
        XCTAssertTrue(wwwUris == ["https://www.avo.org"] && www[4] == 0x02, "NDEF: abreviatura https://www.")
        let longUri = "avohorse://identity/horse/H1?v=2&notes=" + String(repeating: "a", count: 300)
        let lm = Ndef.uriMessage(longUri)
        let lmUris = try Ndef.uris(lm)
        XCTAssertTrue(lm[0] == 0xC1 && lmUris == [longUri], "NDEF: registro largo (>255 B)")
        // license card layout: identity URI, external record, AAR — the identity URI is found
        var multi: [UInt8] = []
        var u = Ndef.uriMessage("avohorse://identity/rider/RIDER_001")
        u[0] = 0x91                                                                   // MB | SR | TNF well-known (not ME)
        multi += u
        let lic: [UInt8] = Array("avoperformance.org:lic".utf8)
        multi += [0x14, UInt8(lic.count), 3]; multi += lic; multi += [1, 2, 3]        // SR | TNF external
        let aar: [UInt8] = Array("android.com:pkg".utf8)
        multi += [0x54, UInt8(aar.count), 2]; multi += aar; multi += Array("ab".utf8)  // ME | SR | TNF external
        XCTAssertEqual(try Ndef.uris(multi).first, "avohorse://identity/rider/RIDER_001", "NDEF: tarjeta con licencia (URI + registro externo + AAR)")
        XCTAssertThrowsError(try Ndef.parse(Array(m[0..<(m.count - 3)])), "NDEF: mensaje truncado rechazado")
        XCTAssertEqual(try Ndef.findMessageTlv([0x01, 0x03, 0xA0, 0x0C, 0x34, 0x03, 0x02, 0xAA, 0xBB, 0xFE]), [0xAA, 0xBB],
                       "TLV: salta Lock Control y encuentra NDEF")
        XCTAssertNil(try Ndef.findMessageTlv([0x00, 0xFE, 0x03, 0x01, 0x00]), "TLV: terminador antes del mensaje")
        let tlv = Ndef.messageTlv(m)
        XCTAssertTrue(tlv[0] == 0x03 && Int(tlv[1]) == m.count && tlv[2 + m.count] == 0xFE && tlv.count % 4 == 0,
                      "TLV: mensaje + terminador en páginas completas")
        // the identity record written by Windows/Android reads back through NDEF + parse
        let rec = IdentityRecord(code: "HORSE_014", name: "Duna", breed: "Hispano-árabe", birthYear: 2016, notes: "Cicatriz en la mano izquierda")
        let parsed = try AvoIdentityTag.parse(try Ndef.uris(Ndef.uriMessage(AvoIdentityTag.buildUri(.horse, rec)))[0])
        XCTAssertTrue(parsed.code == "HORSE_014" && parsed.name == "Duna" && parsed.breed == "Hispano-árabe" && parsed.birthYear == 2016,
                      "NDEF: ficha completa desde el mensaje")
    }

    // ---------------------------------------------------------------- Cuadra / Jinetes / assignments
    private func session(_ id: String, horseCode: String? = nil, horse: String? = nil, rider: String? = nil) -> TrainingSession {
        let s = TrainingSession()
        s.sessionId = id
        s.horseCode = horseCode
        if let h = horse { s.horse = h }
        if let r = rider { s.rider = r }
        return s
    }

    func testStore() throws {
        let path = (dir as NSString).appendingPathComponent("cuadra.json")
        let st = StableStore(path: path)
        let firstHorse = try st.nextCode(.horse), firstRider = try st.nextCode(.rider)
        XCTAssertTrue(firstHorse == "HORSE_001" && firstRider == "RIDER_001", "Cuadra: códigos HORSE_001 / RIDER_001")
        try st.add(.horse, IdentityRecord(code: "HORSE_001", name: "Rayo"))
        XCTAssertEqual(try st.nextCode(.horse), "HORSE_002", "Cuadra: siguiente código libre")
        XCTAssertThrowsError(try st.add(.horse, IdentityRecord(code: "horse_001", name: "Otro")), "Cuadra: código repetido rechazado") { e in
            XCTAssertTrue(e is StableError)
        }

        // a tag never overwrites the local record
        try st.update(.horse, "HORSE_001") { $0.notes = "nota local" }
        let imp = try st.importTag(try AvoIdentityTag.parse("avohorse://identity/horse/HORSE_001?v=2&name=Otro%20nombre"), uidHex: "04AA")
        XCTAssertTrue(!imp.created && imp.record.name == "Rayo" && imp.record.notes == "nota local" && st.find(.horse, "HORSE_001")?.nfcUid == "04AA",
                      "Cuadra: la etiqueta no sobrescribe la ficha (solo recuerda el UID)")
        let imp2 = try st.importTag(try AvoIdentityTag.parse("avohorse://identity/rider/RIDER_007?v=2&name=Antonio"), uidHex: "04BB")
        XCTAssertTrue(imp2.created && imp2.record.name == "Antonio" && imp2.record.origin == "NFC", "Jinetes: alta desde etiqueta")

        // trainings: code in the file, name only, nothing
        let withCode = session("S1", horseCode: "HORSE_001", horse: "HORSE_001", rider: "Antonio")
        let nameOnly = session("S2", horse: "Brisa", rider: "Sin identificar")
        let nothing = session("S3")
        let demo = session("DEMO_X", horseCode: "HORSE_D1", horse: "Demo")
        for s in [withCode, nameOnly, nothing, demo] { try st.registerFromTraining(s) }
        XCTAssertTrue(st.find(.horse, "HORSE_D1")?.demo == true && st.findByName(.horse, "Brisa")?.origin == "entrenamiento",
                      "Cuadra: caballos de los archivos registrados (demo marcado)")
        XCTAssertEqual(st.riders.filter { $0.name == "Antonio" }.count, 1, "Jinetes: un archivo con el mismo nombre no duplica")
        let a1 = st.apply(withCode)
        XCTAssertTrue(a1.horse.name == "Rayo" && a1.horse.code == "HORSE_001" && withCode.horse == "Rayo" && withCode.horseInFile == "HORSE_001",
                      "Asignación: código del archivo → nombre de la Cuadra")
        XCTAssertTrue(a1.rider.code == "RIDER_007" && withCode.rider == "Antonio", "Asignación: nombre del archivo → ficha del jinete")
        let a3 = st.apply(nothing)
        XCTAssertTrue(!a3.horse.known && !a3.rider.known && nothing.horse == StableStore.unknown, "Asignación: entrenamiento sin caballo ni jinete")
        try st.assign("S3", setHorse: true, horseCode: "HORSE_001", setRider: true, riderCode: "RIDER_007")
        let a3b = st.apply(nothing)
        XCTAssertTrue(a3b.horse.name == "Rayo" && a3b.rider.name == "Antonio" && a3b.horse.source == "asignado",
                      "Asignación: caballo y jinete asignados a un entrenamiento que venía sin ellos")
        let brisa = try XCTUnwrap(st.findByName(.horse, "Brisa"))
        try st.assign("S1", setHorse: true, horseCode: brisa.code, setRider: false, riderCode: nil)
        XCTAssertTrue(st.apply(withCode).horse.name == "Brisa" && st.apply(withCode).rider.name == "Antonio",
                      "Asignación: la del usuario manda sobre el archivo, y solo cambia lo elegido")
        try st.assign("S1", setHorse: true, horseCode: nil, setRider: false, riderCode: nil)
        XCTAssertTrue(st.apply(withCode).horse.name == "Rayo" && st.assignment("S1") == nil, "Asignación: vaciar vuelve a lo que dice el archivo")
        XCTAssertThrowsError(try st.assign("S2", setHorse: true, horseCode: "NO_EXISTE", setRider: false, riderCode: nil),
                             "Asignación: no se asigna un código que no está registrado") { e in
            XCTAssertTrue(e is StableError)
        }
        try st.update(.horse, "HORSE_001") { $0.name = "Rayo de Luna" }
        XCTAssertEqual(st.apply(nothing).horse.name, "Rayo de Luna", "Cuadra: renombrar se ve en sus entrenamientos")
        try st.remove(.horse, "HORSE_001")
        XCTAssertTrue(st.apply(nothing).horse.source.contains("eliminada") && st.apply(withCode).horse.name == "HORSE_001",
                      "Cuadra: eliminar no rompe los entrenamientos (vuelve el nombre del archivo)")

        // persistence and a damaged file
        let again = StableStore(path: path)
        XCTAssertTrue(again.riders.contains { $0.code == "RIDER_007" && $0.nfcUid == "04BB" } && again.assignment("S3")?.riderCode == "RIDER_007",
                      "Cuadra: se guarda y se vuelve a leer")
        try Data("{ roto".utf8).write(to: URL(fileURLWithPath: path))
        let broken = StableStore(path: path)
        let copies = try FileManager.default.contentsOfDirectory(atPath: dir).filter { $0.hasPrefix("cuadra.json.danado-") }
        XCTAssertTrue(broken.horses.isEmpty && copies.count == 1, "Cuadra: archivo dañado se conserva aparte, nunca se pierde en silencio")
        XCTAssertTrue(!StableStore.validCode("") && !StableStore.validCode("ÑÑÑÑÑÑÑÑÑÑÑÑ") && StableStore.validCode("HORSE_001"),
                      "Cuadra: validación del código (23 bytes, como el reloj)")
    }

    /// cuadra.json written by AVO Windows (System.Text.Json, PascalCase, DateTimeOffset with 7 decimals) is read as is,
    /// and what the iPad writes uses the same keys.
    func testWindowsCuadraJsonInterchange() throws {
        let path = (dir as NSString).appendingPathComponent("cuadra.json")
        let windows = """
        {
          "Version": 1,
          "Horses": [
            { "Code": "HORSE_001", "Name": "Rayo", "Breed": "PRE", "BirthYear": 2015, "Notes": "", "Active": true,
              "NfcUid": "04A1B2C3D4E5F6", "Origin": "NFC", "Demo": false, "Created": "2026-10-22T06:15:00.1234567+00:00" }
          ],
          "Riders": [
            { "Code": "RIDER_007", "Name": "Antonio", "Breed": "", "Notes": "", "Active": false, "Origin": "manual", "Demo": false,
              "Created": "2026-10-22T08:15:00+02:00" }
          ],
          "Assignments": { "S1": { "HorseCode": "HORSE_001", "Updated": "2026-10-23T10:00:00.5+00:00" } }
        }
        """
        try Data(windows.utf8).write(to: URL(fileURLWithPath: path))
        let st = StableStore(path: path)
        let h = try XCTUnwrap(st.find(.horse, "HORSE_001"))
        XCTAssertEqual(h.birthYear, 2015)
        XCTAssertEqual(h.nfcUid, "04A1B2C3D4E5F6")
        XCTAssertEqual(h.created.timeIntervalSince1970, 1792649700.123, accuracy: 0.002)
        let r = try XCTUnwrap(st.find(.rider, "RIDER_007"))
        XCTAssertFalse(r.active)
        XCTAssertEqual(r.created.timeIntervalSince1970, 1792649700, accuracy: 0.001)
        XCTAssertEqual(st.assignment("S1")?.horseCode, "HORSE_001")
        XCTAssertNil(st.assignment("S1")?.riderCode)
        // write and check the keys
        try st.update(.rider, "RIDER_007") { $0.notes = "nota" }
        let o = try XCTUnwrap(AvoJSON.object(try Data(contentsOf: URL(fileURLWithPath: path))))
        XCTAssertNotNil(o["Horses"] as? [Any])
        let riders = try XCTUnwrap(o["Riders"] as? [[String: Any]])
        XCTAssertEqual(riders[0]["Notes"] as? String, "nota")
        XCTAssertNil(riders[0]["BirthYear"], "null omitido como WhenWritingNull")
        XCTAssertNil(riders[0]["NfcUid"])
        let assign = try XCTUnwrap(o["Assignments"] as? [String: Any])
        let s1 = try XCTUnwrap(assign["S1"] as? [String: Any])
        XCTAssertEqual(s1["HorseCode"] as? String, "HORSE_001")
        XCTAssertNil(s1["RiderCode"])
        XCTAssertNotNil(StableJson.parseDate(s1["Updated"] as? String ?? ""))
    }
}
