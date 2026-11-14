import XCTest
import CryptoKit
import Compression
@testable import AVO_Horse

/// Port of the Windows self-tests (Program.cs and V2Tests.cs) that exercise RawReader, TrainingImporter, ZipReader,
/// Services, MarineMetadata, ExportService, TrainingEnvironment and EquineEngine. Synthetic data only, clearly marked.
final class ImportAndServicesTests: XCTestCase {
    private var dir: String = ""

    override func setUpWithError() throws {
        dir = (NSTemporaryDirectory() as NSString).appendingPathComponent("avo_ipad_test_" + UUID().uuidString.replacingOccurrences(of: "-", with: ""))
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: dir)
    }

    // MARK: - byte helpers (independent of the app code)

    private static func crc32(_ b: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for x in b {
            crc ^= UInt32(x)
            for _ in 0..<8 { crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static func crc8(_ b: ArraySlice<UInt8>) -> UInt8 {
        var crc: UInt8 = 0
        for c in b {
            crc ^= c
            for _ in 0..<8 { crc = (crc & 0x80) != 0 ? (crc << 1) ^ 7 : crc << 1 }
        }
        return crc
    }

    private static func w16(_ b: inout [UInt8], _ o: Int, _ v: UInt16) { b[o] = UInt8(v & 0xFF); b[o + 1] = UInt8(v >> 8) }
    private static func w32(_ b: inout [UInt8], _ o: Int, _ v: UInt32) { for i in 0..<4 { b[o + i] = UInt8((v >> (8 * UInt32(i))) & 0xFF) } }
    private static func w64(_ b: inout [UInt8], _ o: Int, _ v: UInt64) { for i in 0..<8 { b[o + i] = UInt8((v >> (8 * UInt64(i))) & 0xFF) } }

    private static func sha(_ b: [UInt8]) -> String { SHA256.hash(data: Data(b)).map { String(format: "%02x", $0) }.joined() }

    /// UART frame (A5 5A ... CRC-8 header, CRC-32 tail) around a payload.
    private static func uart(_ type: UInt8, _ payload: [UInt8]) -> [UInt8] {
        var f = [UInt8](repeating: 0, count: 19 + payload.count)
        f[0] = 0xA5; f[1] = 0x5A; f[3] = type; f[5] = 2
        w16(&f, 8, UInt16(payload.count))
        f[14] = crc8(f[2..<14])
        for (i, x) in payload.enumerated() { f[15 + i] = x }
        w32(&f, f.count - 4, crc32(Array(f[2..<(15 + payload.count)])))
        return f
    }

    /// GNSS_SAMPLE frame (Program.cs Frame).
    private static func gnssFrame(_ gpsTimeMs: UInt32, _ latE7: Int32, _ lonE7: Int32, _ speedMmS: Int32) -> [UInt8] {
        var s = [UInt8](repeating: 0, count: 85)
        w32(&s, 0, gpsTimeMs)
        w16(&s, 4, 2026)
        s[6] = 10; s[7] = 22
        s[20] = 3; s[21] = 0x81; s[24] = 17
        w32(&s, 25, UInt32(bitPattern: lonE7))
        w32(&s, 29, UInt32(bitPattern: latE7))
        w32(&s, 33, 2500)
        w32(&s, 41, 450)
        w32(&s, 61, UInt32(bitPattern: speedMmS))
        s[84] = 10
        return uart(0x10, s)
    }

    private static func header(_ id: String, rtcMs: UInt64? = nil, horse: String? = nil, rider: String? = nil) -> [UInt8] {
        var h = [UInt8](repeating: 0, count: 512)
        let magic: [UInt8] = Array("AVORAW1".utf8) + [0]
        for i in 0..<8 { h[i] = magic[i] }
        w16(&h, 8, 1); w16(&h, 10, 512)
        for (i, c) in Array(id.utf8).enumerated() { h[12 + i] = c }
        if let r = rtcMs { w64(&h, 40, r) }
        if let x = horse { for (i, c) in Array(x.utf8).enumerated() { h[124 + i] = c } }
        if let x = rider { for (i, c) in Array(x.utf8).enumerated() { h[152 + i] = c } }
        w32(&h, 508, crc32(Array(h[0..<508])))
        return h
    }

    /// RAW file with one block (V2Tests.Raw / Program.cs BuildRaw).
    private static func raw(_ id: String, rtcMs: UInt64? = nil, horse: String? = nil, rider: String? = nil,
                            _ recs: [(type: UInt8, chestUs: UInt64, data: [UInt8])]) -> [UInt8] {
        var body: [UInt8] = []
        for r in recs {
            var rec = [UInt8](repeating: 0, count: 12)
            rec[0] = r.type
            w16(&rec, 2, UInt16(r.data.count))
            w64(&rec, 4, r.chestUs)
            body += rec + r.data
        }
        var block = [UInt8](repeating: 0, count: 36)
        w32(&block, 0, 0x424F_5641); w32(&block, 4, 1); w32(&block, 8, UInt32(body.count))
        w16(&block, 12, UInt16(recs.count)); w16(&block, 14, 2)
        w32(&block, 28, crc32(body))
        w32(&block, 32, crc32(Array(block[0..<32])))
        return header(id, rtcMs: rtcMs, horse: horse, rider: rider) + block + body
    }

    private static func buildRaw(_ id: String = "DEMO_INTEGRATION_001") -> [UInt8] {
        raw(id, rtcMs: 1_792_656_000_000, horse: "Rayo", rider: "Antonio", [
            (type: 1, chestUs: 1_234_567, data: gnssFrame(100_000, 434_135_000, -34_920_000, 8200)),
            (type: 1, chestUs: 2_234_567, data: gnssFrame(101_000, 434_135_500, -34_919_700, 11200)),
        ])
    }

    private static func imu(_ imuId: UInt8, _ fmt: UInt8, _ samples: [[Int16]]) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: 24 + samples.count * 18)
        p[1] = imuId; p[2] = UInt8(samples.count); p[3] = fmt
        w16(&p, 12, 9615)
        for i in 0..<samples.count { for k in 0..<9 { w16(&p, 24 + i * 18 + 2 * k, UInt16(bitPattern: samples[i][k])) } }
        return p
    }

    // MARK: - minimal ZIP writer for fixtures (stored, or raw deflate via Compression)

    private static func deflate(_ data: [UInt8]) -> [UInt8]? {
        if data.isEmpty { return nil }
        let cap = data.count + 1024
        var out = [UInt8](repeating: 0, count: cap)
        let n = out.withUnsafeMutableBufferPointer { (dst: inout UnsafeMutableBufferPointer<UInt8>) -> Int in
            data.withUnsafeBufferPointer { (src: UnsafeBufferPointer<UInt8>) -> Int in
                compression_encode_buffer(dst.baseAddress!, cap, src.baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        return n > 0 ? Array(out[0..<n]) : nil
    }

    private static func zip(_ entries: [(name: String, data: [UInt8])], deflated: Bool = false, corruptCrc: Bool = false) -> [UInt8] {
        var out: [UInt8] = []
        var central: [UInt8] = []
        for e in entries {
            let name = Array(e.name.utf8)
            var crc = ZipCRC32.compute(e.data)   // table version: the 51 MB fixture is too slow bit by bit in Debug
            if corruptCrc { crc ^= 1 }
            var method: UInt16 = 0
            var body = e.data
            if deflated, let d = deflate(e.data) { method = 8; body = d }
            let offset = UInt32(out.count)
            var lh = [UInt8](repeating: 0, count: 30)
            w32(&lh, 0, 0x0403_4B50); w16(&lh, 4, 20); w16(&lh, 6, 0x0800); w16(&lh, 8, method)
            w16(&lh, 10, 0); w16(&lh, 12, 0x21); w32(&lh, 14, crc)
            w32(&lh, 18, UInt32(body.count)); w32(&lh, 22, UInt32(e.data.count))
            w16(&lh, 26, UInt16(name.count)); w16(&lh, 28, 0)
            out += lh + name + body
            var ch = [UInt8](repeating: 0, count: 46)
            w32(&ch, 0, 0x0201_4B50); w16(&ch, 4, 20); w16(&ch, 6, 20); w16(&ch, 8, 0x0800); w16(&ch, 10, method)
            w16(&ch, 12, 0); w16(&ch, 14, 0x21); w32(&ch, 16, crc)
            w32(&ch, 20, UInt32(body.count)); w32(&ch, 24, UInt32(e.data.count))
            w16(&ch, 28, UInt16(name.count)); w32(&ch, 42, offset)
            central += ch + name
        }
        let cdOffset = UInt32(out.count)
        out += central
        var eocd = [UInt8](repeating: 0, count: 22)
        w32(&eocd, 0, 0x0605_4B50)
        w16(&eocd, 8, UInt16(entries.count)); w16(&eocd, 10, UInt16(entries.count))
        w32(&eocd, 12, UInt32(central.count)); w32(&eocd, 16, cdOffset)
        return out + eocd
    }

    private static func manifest(_ id: String, _ hashes: [String: String], segments: Int? = nil, extra: [String: Any] = [:]) -> [UInt8] {
        var m: [String: Any] = ["format": "AVO-TRAINING-1", "sessionId": id, "horseName": "Rayo", "riderName": "Antonio",
                                "segments": segments ?? hashes.count, "segmentHashes": hashes]
        for (k, v) in extra { m[k] = v }
        let d = try! JSONSerialization.data(withJSONObject: m, options: [])
        return [UInt8](d)
    }

    private func write(_ name: String, _ bytes: [UInt8]) throws -> String {
        let p = (dir as NSString).appendingPathComponent(name)
        try Data(bytes).write(to: URL(fileURLWithPath: p))
        return p
    }

    private func path(_ name: String) -> String { (dir as NSString).appendingPathComponent(name) }

    private func rejects(_ p: String) -> Bool {
        do {
            _ = try TrainingImporter.importFile(p, rawCacheDir: path("rawcache"))
            return false
        } catch let e as AvoError {
            if case .invalidData = e { return true }
            return false
        } catch {
            return false
        }
    }

    private static func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    // MARK: - Program.cs: RAW, .avo, exports, marine metadata, corrupt and torn files

    func testRawAvoExportsAndMarine() throws {
        let raw = Self.buildRaw()
        let avr = try write("segment0.avr", raw)
        let standalone = try TrainingImporter.importFile(avr)
        XCTAssertEqual(standalone.sessionId, "DEMO_INTEGRATION_001", "Cabecera AVR real / sessionId")
        XCTAssertTrue(standalone.horse == "Rayo" && standalone.rider == "Antonio", "Caballo y jinete de cabecera RAW")
        XCTAssertTrue(standalone.track.count == 2 && standalone.rtkFixCount == 2, "Tramas UART GNSS y estado RTK FIX")
        XCTAssertTrue(standalone.maxSpeedKmh > 40 && standalone.distanceM > 0, "Velocidad GNSS y distancia geodésica")
        XCTAssertTrue(standalone.segments[0].cleanClose && !standalone.segments[0].truncated, "CRC bloque y cierre limpio")
        XCTAssertEqual(standalone.durationSeconds, 1, "Tiempo iTOW GNSS")
        XCTAssertEqual(standalone.horseCode, "Rayo")
        XCTAssertEqual(standalone.horseInFile, "Rayo")

        let man = Self.manifest("DEMO_INTEGRATION_001", ["segment0.avr": Self.sha(raw)], segments: 1,
                                extra: ["sha256": String(repeating: "f", count: 64), "startRtcMs": 1_792_656_000_000, "distanceM": 1234.0])
        for deflated in [false, true] {
            let avo = try write(deflated ? "training_deflate.avo" : "training.avo",
                                Self.zip([(name: "manifest.json", data: man), (name: "segments/segment0.avr", data: raw)], deflated: deflated))
            let session = try TrainingImporter.importFile(avo, rawCacheDir: path("raw"))
            XCTAssertTrue(session.integrity.contains("SHA-256") && session.track.count == 2, "ZIP AVO-TRAINING-1 y SHA-256 segmento")
            XCTAssertTrue(session.distanceM != 1234 && session.hasRawTelemetry, "Se prioriza distancia calculada del RAW sobre resumen declarado")
            XCTAssertEqual(session.sha256, String(repeating: "f", count: 64))
            XCTAssertEqual(session.rawSegmentPaths.count, 1)

            let csv = path("export.csv"), gpx = path("export.gpx"), html = path("report.html")
            try ExportService.exportCsv(session, csv)
            try ExportService.exportGpx(session, gpx)
            try ExportService.exportHtml(session, html)
            let csvText = try String(contentsOfFile: csv, encoding: .utf8)
            XCTAssertTrue(csvText.components(separatedBy: .newlines).filter { !$0.isEmpty }.count == 3 && csvText.contains("FIX"), "Exportación CSV")
            let gpxText = try String(contentsOfFile: gpx, encoding: .utf8)
            XCTAssertTrue(gpxText.contains("<trkpt") && !gpxText.contains("434"), "Exportación GPX con coordenadas")
            XCTAssertTrue(try String(contentsOfFile: html, encoding: .utf8).contains("AVO PERFORMANCE HORSE"), "Informe HTML imprimible")

            let marine = path("marine.json")
            try Data(#"{"source":"Estación de referencia / modelo de prueba","kind":"modelo","timestamp":"2026-10-22T10:15:00+02:00","tideHeightM":1.5,"windKmh":12}"#.utf8)
                .write(to: URL(fileURLWithPath: marine))
            try MarineMetadata.loadJson(session, marine)
            XCTAssertTrue(session.tideHeightM == 1.5 && session.marineKind == "modelo", "Marea y procedencia explícitas")
            XCTAssertEqual(session.marineObservedAt, Self.utc(2026, 10, 22, 8, 15))
            try Data(#"{"source":"sin datos","kind":"inventado","timestamp":"2026-10-22T10:15:00+02:00"}"#.utf8).write(to: URL(fileURLWithPath: marine))
            XCTAssertThrowsError(try MarineMetadata.loadJson(session, marine), "Rechazo de tipo de marea inventado")
            try Data(#"{"source":"x","kind":"modelo","timestamp":"2026-10-22T10:15:00"}"#.utf8).write(to: URL(fileURLWithPath: marine))
            XCTAssertThrowsError(try MarineMetadata.loadJson(session, marine)) { e in
                XCTAssertEqual((e as? AvoError)?.message, "La hora marina debe contener zona horaria")
            }
        }

        var broken = raw
        broken[508] ^= 0x10
        _ = try write("segment0.avr", broken)
        XCTAssertTrue(rejects(avr), "Rechazo de cabecera con CRC corrupto")
        _ = try write("segment0.avr", Array(raw[0..<(raw.count - 9)]))
        let partial = try TrainingImporter.importFile(avr)
        XCTAssertTrue(partial.segments[0].truncated && partial.integrity.contains("parcial"), "Bloque incompleto señalado, no interpretado")
    }

    // MARK: - ZIP reader

    func testZipReaderCrcAndBounds() throws {
        let payload = [UInt8](repeating: 7, count: 100_000) + Array("AVO".utf8)
        let ok = Self.zip([(name: "a.bin", data: payload)], deflated: true)
        let zr = try ZipReader(bytes: ok)
        XCTAssertEqual(zr.entries.count, 1)
        XCTAssertEqual(zr.entries[0].method, 8, "Entrada deflate")
        XCTAssertEqual(try zr.read(zr.entries[0], max: 200_000), payload, "Inflado raw deflate")
        XCTAssertThrowsError(try zr.read(zr.entries[0], max: 50_000), "Límite de descompresión")
        let bad = try ZipReader(bytes: Self.zip([(name: "a.bin", data: payload)], corruptCrc: true))
        XCTAssertThrowsError(try bad.read(bad.entries[0], max: 200_000), "CRC-32 incorrecto rechazado")
        XCTAssertThrowsError(try ZipReader(bytes: Array("no es un zip".utf8)), "Archivo que no es ZIP")
        XCTAssertEqual(ZipCRC32.compute(Array("123456789".utf8)), 0xCBF4_3926, "CRC-32 de referencia")
    }

    // MARK: - V2Tests.RawImuDecoding / RawImuBno085Units (importer part)

    func testRawImuDecoding() throws {
        let s1: [Int16] = [10, -20, 4096, 70, -70, 140, 1, 2, 3], s2: [Int16] = [11, -21, 4100, 71, -71, 141, 4, 5, 6]
        let truncated = Array(Self.imu(0, 0, [s1])[0..<30])
        let raw = Self.raw("SINTETICA_IMU", [
            (type: 1, chestUs: 2_000_000, data: Self.uart(0x20, Self.imu(2, 0, [s1, s2]))),
            (type: 1, chestUs: 2_100_000, data: Self.uart(0x20, Self.imu(1, 7, [s1]))),
            (type: 1, chestUs: 2_200_000, data: Self.uart(0x20, truncated)),
            (type: 5, chestUs: 2_300_000, data: [0, 3, 0, 0, 0]),
        ])
        let s = try TrainingImporter.importFile(try write("imu.avr", raw))
        XCTAssertTrue(s.imu.count == 2 && s.imu[0].imuId == 2 && s.imu[1].az == 4100 && s.imu[0].gz == 140 && s.imu[1].mz == 6,
                      "IMU_SAMPLE fmt 0: 9 ejes int16 decodificados (LSB)")
        XCTAssertTrue(abs(s.imu[1].timeS - 2.0) < 1e-9 && abs(s.imu[0].timeS - (2.0 - 0.009615)) < 1e-9 && s.imuPeriodUs == 9615,
                      "Tiempos IMU: reloj del pecho y periodo nominal")
        XCTAssertTrue(s.imuOpaqueBatches == 1 && s.invalidFrames == 1, "Formato IMU desconocido conservado como opaco; lote truncado rechazado")
        XCTAssertTrue(s.markers.count == 1 && s.markers[0].count == 3 && s.markers[0].sourceName == "Botón", "Registro MARKER binario (origen + contador)")
    }

    func testRawImuBno085Units() throws {
        let s1: [Int16] = [0, 0, 2511, 512, 0, 0, 16, 0, 0], s2: [Int16] = [256, 0, 2511, 0, 0, 0, 16, 0, 0]
        var b0 = Self.imu(0, 0, [s1, s2])
        b0[15] = 1
        var b1 = [UInt8](repeating: 0, count: 24 + 2 * 14)
        b1[1] = 0; b1[2] = 2; b1[3] = 1; b1[15] = 1
        Self.w16(&b1, 12, 7978)
        let f: [Int16] = [128, 0, 0, 0, 0, 0, 16384]
        for i in 0..<2 { for k in 0..<7 { Self.w16(&b1, 24 + i * 14 + 2 * k, UInt16(bitPattern: f[k])) } }
        let raw = Self.raw("SINTETICA_BNO", [(type: 1, chestUs: 3_000_000, data: Self.uart(0x20, b0)),
                                             (type: 1, chestUs: 3_000_000, data: Self.uart(0x20, b1))])
        let s = try TrainingImporter.importFile(try write("imu_bno.avr", raw))
        XCTAssertTrue(s.imuUnits == 1 && s.imu.count == 2 && s.imuOpaqueBatches == 0, "Cincha 0.4.3: unidades del BNO085 declaradas en la cabecera")
        XCTAssertTrue(s.imuFusedBatches == 1 && s.imuFused.count == 2 && s.imuFused[0].lx == 128 && s.imuFused[1].qr == 16384,
                      "IMU fmt 1: aceleración lineal y cuaternión decodificados")
    }

    // MARK: - V2Tests.ImporterSecurity

    func testImporterSecurity() throws {
        let raw = Self.raw("SINTETICA_ZIP", [(type: 5, chestUs: 1, data: [0, 1, 0, 0, 0])])
        let sha = Self.sha(raw)
        XCTAssertTrue(rejects(try write("slip.avo", Self.zip([(name: "manifest.json", data: Self.manifest("SINTETICA_ZIP", ["../evil.avr": sha])),
                                                             (name: "segments/../evil.avr", data: raw)]))), "ZIP con ruta arbitraria (../) rechazado")
        XCTAssertTrue(rejects(try write("hash.avo", Self.zip([(name: "manifest.json", data: Self.manifest("SINTETICA_ZIP", ["P001.avr": String(repeating: "0", count: 64)])),
                                                             (name: "segments/P001.avr", data: raw)]))), "SHA-256 de segmento incorrecto rechazado")
        XCTAssertTrue(rejects(try write("count.avo", Self.zip([(name: "manifest.json", data: Self.manifest("SINTETICA_ZIP", ["P001.avr": sha], segments: 2)),
                                                              (name: "segments/P001.avr", data: raw)]))), "Número de segmentos inconsistente rechazado (sesión incompleta)")
        XCTAssertTrue(rejects(try write("nomanifest.avo", Self.zip([(name: "segments/P001.avr", data: raw), (name: "segments/P002.avr", data: raw)]))),
                      "ZIP sin manifest.json rechazado")
        let big = [UInt8](repeating: 0, count: 51 * 1024 * 1024)
        XCTAssertTrue(rejects(try write("bomb.avo", Self.zip([(name: "manifest.json", data: Self.manifest("SINTETICA_ZIP", ["P001.avr": sha])),
                                                             (name: "segments/P001.avr", data: big)], deflated: true))),
                      "Segmento descomprimido > 50 MB rechazado (protección ZIP)")
        let ok = try write("ok.avo", Self.zip([(name: "manifest.json", data: [0xEF, 0xBB, 0xBF] + Self.manifest("SINTETICA_ZIP", ["P001.avr": sha])),
                                               (name: "segments/P001.avr", data: raw)]))
        let s = try TrainingImporter.importFile(ok, rawCacheDir: path("rawcache"))
        XCTAssertTrue(s.sessionId == "SINTETICA_ZIP" && s.isSynthetic && s.integrity.contains("SHA-256"), "Paquete válido (con BOM) importado y marcado como sintético")
        XCTAssertTrue(rejects(try write("x.exe", raw)), "Extensión no admitida rechazada")
    }

    // MARK: - V2Tests.Library

    func testLibrary() throws {
        let paths = AppPaths(root: path("app"))
        let lib = TrainingLibrary(paths)
        let raw = Self.raw("SINTETICA_LIB", [(type: 5, chestUs: 1, data: [0, 1, 0, 0, 0])])
        let f = try write("lib.avr", raw)
        let before = try TrainingLibrary.fileSha256(f)
        XCTAssertEqual(before, Self.sha(raw))
        let a = lib.importFile(f, loadedSessionIds: [])
        let b = TrainingLibrary(paths).importFile(f, loadedSessionIds: ["SINTETICA_LIB"])
        XCTAssertTrue(a.session != nil && !a.duplicate && b.duplicate && b.session?.sessionId == "SINTETICA_LIB",
                      "Biblioteca: duplicado detectado por SHA-256 (también tras reiniciar)")
        XCTAssertTrue(try TrainingLibrary.fileSha256(f) == before && FileManager.default.fileExists(atPath: (paths.library as NSString).appendingPathComponent(before + ".avr")),
                      "Original intacto y copia verificada en la biblioteca")
        let bad = try write("bad.avr", Array(raw[0..<100]))
        let c = lib.importFile(bad, loadedSessionIds: [])
        let badSha = try TrainingLibrary.fileSha256(bad)
        XCTAssertTrue(c.session == nil && c.error != nil && !FileManager.default.fileExists(atPath: (paths.library as NSString).appendingPathComponent(badSha + ".avr")),
                      "Archivo truncado rechazado sin dejar copia")
        // index written with the Windows (PascalCase) keys
        let index = try String(contentsOfFile: paths.libraryIndex, encoding: .utf8)
        XCTAssertTrue(index.contains("\"Sha256\"") && index.contains("\"ImportedUtc\""), "Índice de la biblioteca compatible con Windows")
        XCTAssertEqual(TrainingLibrary(paths).entries.count, 1)
    }

    // MARK: - V2Tests.TidesWeatherAndTime

    func testTidesWeatherAndTime() throws {
        let ports = #"{"estaciones":{"puertos":[{"id":"21","puerto":"Santander","lat":"43.4613","lon":"-3.7914"},{"id":"99","puerto":"Sin coordenadas","lat":"","lon":""}]}}"#
        let p = try IhmTides.parsePorts(ports)
        XCTAssertTrue(p.count == 1 && p[0].name == "Santander" && abs(p[0].distanceKmTo(43.4247, -3.4519) - 27.6) < 2, "IHM: lista de puertos (coordenadas en texto)")
        let month = #"{"mareas":{"datos":{"marea":[{"fecha":"2026-10-22","hora":"02:10","altura":"4,10","tipo":"pleamar"},{"fecha":"2026-10-22","hora":"08:25","altura":"0,90","tipo":"bajamar"},{"fecha":"2026-10-22","hora":"14:40","altura":"4,00","tipo":"pleamar"}]}}}"#
        let ex = try IhmTides.parseMonth(month)
        XCTAssertTrue(ex.count == 3 && ex[0].high && !ex[1].high && abs(ex[0].heightM - 4.1) < 1e-9 && ex[0].utc == Self.utc(2026, 10, 22, 2, 10),
                      "IHM: pleamar/bajamar en UTC y coma decimal")
        let tp = TidePrediction(source: IhmTides.sourceName, port: p[0], extremes: ex)
        let midT = ex[0].utc.addingTimeInterval(ex[1].utc.timeIntervalSince(ex[0].utc) / 2)
        XCTAssertTrue(abs((tp.heightAt(midT) ?? -99) - 2.5) < 1e-6 && tp.trendAt(midT) == "bajando", "Interpolación coseno entre extremos y tendencia")
        XCTAssertTrue(tp.heightAt(ex[0].utc.addingTimeInterval(-3 * 3600)) == nil && tp.kind == .prediccion, "Fuera de los datos: «Sin datos»; tipo = predicción")
        let w = #"{"hourly":{"time":["2026-10-22T06:00","2026-10-22T07:00"],"temperature_2m":[14.2,null],"wind_speed_10m":[12,13],"pressure_msl":[1018,1018.4]}}"#
        let sea = #"{"hourly":{"time":["2026-10-22T06:00"],"wave_height":[0.8],"wave_period":[9]}}"#
        let hours = try WeatherModel.parseHourly(w, sea)
        let wm = WeatherModel(source: "prueba", latitude: 0, longitude: 0, hours: hours)
        let h = wm.at(Self.utc(2026, 10, 22, 6, 20))
        XCTAssertTrue(hours.count == 2 && h != nil && h?.temperatureC == 14.2 && h?.waveHeightM == 0.8 && hours[1].temperatureC == nil,
                      "Open-Meteo: valores nulos quedan «Sin datos»")
        XCTAssertTrue(wm.at(Self.utc(2026, 10, 22, 12, 0)) == nil && wm.kind == .modelo, "Sin hora cercana: no se inventa; tipo = modelo")
        XCTAssertEqual(MadridTime.format(Self.utc(2026, 7, 1, 10, 0), "HH:mm"), "12:00", "Europe/Madrid verano (UTC+2)")
        XCTAssertEqual(MadridTime.format(Self.utc(2026, 1, 15, 10, 0), "HH:mm"), "11:00", "Europe/Madrid invierno (UTC+1)")
        let before = Self.utc(2026, 10, 25, 0, 30), after = Self.utc(2026, 10, 25, 1, 30)
        XCTAssertTrue(MadridTime.format(before, "HH:mm") == "02:30" && MadridTime.format(after, "HH:mm") == "02:30"
                      && MadridTime.zoneLabel(before) != MadridTime.zoneLabel(after), "Cambio de hora 25/10/2026: misma hora local con zonas distintas")
        XCTAssertEqual(MadridTime.format(Self.utc(2026, 10, 22, 22, 30), "dd/MM HH:mm"), "23/10 00:30", "Sesión que cruza medianoche local")
    }

    // MARK: - V2Tests.ServerAndNetwork

    func testServerAndNetwork() async throws {
        FailingURLProtocol.calls = 0
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [FailingURLProtocol.self]
        let env = EnvironmentService(cacheDir: path("env"), session: URLSession(configuration: cfg))
        var threw = false
        do { _ = try await env.ports() } catch { threw = true }
        XCTAssertTrue(threw && FailingURLProtocol.calls == 1, "Sin red y sin copia local: error informado, ningún dato inventado")

        var ns = false
        do { _ = try await PendingContractServerClient().listSessions() } catch is ServerNotSupportedError { ns = true }
        XCTAssertTrue(ns && PendingContractServerClient().state == .contractPending, "Servidor: contrato pendiente, sin endpoints inventados")

        var http = false, ext = false
        do { _ = try await HttpsDownloader.downloadAvo(URL(string: "http://example.org/a.avo")!, targetDirectory: dir) }
        catch let e as AvoError { if case .invalidData = e { http = true } }
        do { _ = try await HttpsDownloader.downloadAvo(URL(string: "https://example.org/a.exe")!, targetDirectory: dir) }
        catch let e as AvoError { if case .invalidData = e { ext = true } }
        XCTAssertTrue(http && ext, "Descarga manual: solo HTTPS y archivos .avo")

        let settings = AppSettings()
        let sf = path("ajustes.json")
        try settings.save(sf)
        let stext = try String(contentsOfFile: sf, encoding: .utf8)
        XCTAssertTrue(stext.range(of: "password", options: .caseInsensitive) == nil && stext.range(of: "token", options: .caseInsensitive) == nil
                      && AppSettings.load(sf).map == .esriSatellite, "Ajustes sin secretos (NTRIP, tokens) y recuperables")
        XCTAssertTrue(stext.contains("\"Map\"") && stext.contains("EsriSatellite") && stext.contains("\"PlaceName\""), "Ajustes con las claves de Windows")
        try Data(#"{"Map":"EsriHybrid","JerkDensity":2.5}"#.utf8).write(to: URL(fileURLWithPath: sf))
        let loaded = AppSettings.load(sf)
        XCTAssertTrue(loaded.map == .esriHybrid && loaded.jerkDensity == 2.5 && loaded.placeName == TrainingPlace.regaton.name, "Ajustes parciales de Windows")
    }

    // MARK: - Program.cs: AVO Equine Intelligence Engine on the SYNTHETIC reference session

    private func syntheticFixture() -> [UInt8]? {
        let bundles = [Bundle(for: ImportAndServicesTests.self), Bundle.main]
        for b in bundles {
            if let u = b.url(forResource: "synthetic_session", withExtension: "avo"), let d = try? Data(contentsOf: u) { return [UInt8](d) }
        }
        return nil
    }

    func testEquineEngine() async throws {
        XCTAssertTrue(EquineEngine.available, EquineEngine.unavailableReason ?? "")
        XCTAssertTrue(EquineEngine.version().hasPrefix("2.0.0"), "Versión del motor " + EquineEngine.version())
        guard let synthetic = syntheticFixture() else { throw XCTSkip("Falta la sesión de referencia synthetic_session.avo") }
        let avo2 = try write("sintetica.avo", Self.zip([
            (name: "manifest.json", data: Self.manifest("SINTETICA_0001", ["P001.avr": Self.sha(synthetic)], extra: ["horseName": "PRUEBA", "riderName": "", "startRtcMs": 1_792_656_000_000])),
            (name: "segments/P001.avr", data: synthetic),
        ], deflated: true))
        let s2 = try TrainingImporter.importFile(avo2, rawCacheDir: path("raw"))
        XCTAssertTrue(s2.rawSegmentPaths.count == 1 && FileManager.default.fileExists(atPath: s2.rawSegmentPaths[0]), "Copia RAW verificada para el motor")
        let cache = path("analisis")
        let r1 = try EquineAnalysis.parse(try await EquineEngine.analyseJson(s2.rawSegmentPaths, EquineEngine.options(series: true, cacheDir: cache)))
        XCTAssertTrue(r1.sessionId == "SINTETICA_0001" && r1.cache == "CALCULADO", "Análisis del motor con persistencia")
        XCTAssertTrue(r1.hasImu && r1.segments.contains(where: { $0.aire == "Paso" }) && r1.segments.contains(where: { $0.aire == "Trote" }), "Rendimiento por aire")
        XCTAssertTrue(r1.curves.count == 1 && !r1.events.isEmpty && !r1.quality.isEmpty, "Curvas, eventos y calidad")
        let tp = s2.track[s2.track.count * 3 / 4]
        let t3 = r1.timeOf(tp.gpsWeekMs) ?? .nan
        XCTAssertTrue(abs(r1.gnssAt(r1.speed, t3) - tp.speedMs) < 0.05, "Series del motor sincronizadas con el recorrido")
        XCTAssertTrue(abs(r1.cadenceAt(t3) - 1.45) < 0.05, "Cadencia de la cincha en el instante seleccionado")
        let r2 = try EquineAnalysis.parse(try EquineEngine.analyseJsonSync(s2.rawSegmentPaths, EquineEngine.options(series: true, cacheDir: cache)))
        XCTAssertEqual(r2.cache, "ACIERTO", "Reapertura sin recalcular")
        let r3 = try EquineAnalysis.parse(try await EquineEngine.analyseJson(s2.rawSegmentPaths, EquineEngine.options(series: true, cacheDir: cache, force: true)))
        XCTAssertEqual(r3.cache, "RECALCULADO", "Reprocesamiento forzado")

        let flag = EngineCancelFlag()
        flag.cancel()
        XCTAssertThrowsError(try EquineEngine.analyseJsonSync(s2.rawSegmentPaths, "{}", cancel: flag), "Cancelación del análisis") { e in
            XCTAssertTrue(e is CancellationError)
        }
        let paths = s2.rawSegmentPaths
        let task = Task { () async throws -> String in
            withUnsafeCurrentTask { (t: UnsafeCurrentTask?) -> Void in t?.cancel() }
            return try await EquineEngine.analyseJson(paths, "{}")
        }
        var cancelled = false
        do { _ = try await task.value } catch is CancellationError { cancelled = true }
        XCTAssertTrue(cancelled, "Cancelación del análisis desde la tarea Swift")

        let cmp = try EquineComparisonRows.parse(try await EquineEngine.compareJson(s2.rawSegmentPaths, s2.rawSegmentPaths, "{\"mismo_recorrido\":true}"))
        XCTAssertTrue(!cmp.rows.isEmpty && cmp.verdict.hasPrefix("Comparables"), "Comparación de sesiones: " + cmp.verdict)
        var inputError = false
        do { _ = try await EquineEngine.analyseJson([path("no_existe.avr")], "{}") }
        catch let e as AvoError { if case .invalidData = e { inputError = true } }
        XCTAssertTrue(inputError, "Error de entrada informado")
        let copy = try Data(contentsOf: URL(fileURLWithPath: s2.rawSegmentPaths[0]))
        XCTAssertEqual(Self.sha([UInt8](copy)), Self.sha(synthetic), "El RAW no se modifica")
    }

    // MARK: - V2Tests.DemoSessions (importer and engine part; timeline checks live with the analysis tests)

    func testDemoSessions() async throws {
        guard let demo = Bundle.main.url(forResource: "demo", withExtension: nil) else {
            throw XCTSkip("Sesiones de demostración no incluidas en la app")
        }
        let file = demo.appendingPathComponent("DEMO_REGATON_20261022.avr").path
        guard FileManager.default.fileExists(atPath: file) else { throw XCTSkip("Falta DEMO_REGATON_20261022.avr") }
        let start = Date()
        let s = try TrainingImporter.importFile(file)
        let ms = Date().timeIntervalSince(start) * 1000
        XCTAssertTrue(s.isSynthetic && s.horse.contains("demo") && s.totalImuSamples > 0, "Demostración marcada como sintética, con cincha")
        #if DEBUG
        let limit = 20_000.0
        #else
        let limit = 5_000.0
        #endif
        XCTAssertLessThan(ms, limit, "Rendimiento: importar 20 min con 3 IMU en \(Int(ms)) ms")
        if EquineEngine.available {
            let e = try EquineAnalysis.parse(try await EquineEngine.analyseJson([file], EquineEngine.options(series: true, cacheDir: path("eng"))))
            XCTAssertTrue(e.hasImu && e.segments.contains(where: { $0.gaitCode == "CANTER_GALLOP" }) && e.segments.contains(where: { $0.gaitCode == "WALK" }),
                          "Motor: aires de la demostración (paso … galope)")
            // AVO Track Work: training block and the zones corrected by hand (CorrectionsModel → engine options)
            XCTAssertTrue(e.trackWork.present, "Motor: bloque trabajo_pista")
            if let i0 = e.itow0Ms, let last = e.t.last, last > 90 {
                var c = TrainingCorrection()
                let a: Double = Double(i0) + last / 3 * 1000
                c.works = [[a, a + 30_000]]
                c.workStartItow = a - 10_000
                c.start = TrainingLine(aLat: 43.40, aLon: -3.43, bLat: 43.401, bLon: -3.43, direction: "DCHA_A_IZQ")
                c.finish = TrainingLine(aLat: 43.41, aLon: -3.43, bLat: 43.411, bLon: -3.43, direction: "DCHA_A_IZQ")
                let frag: String = c.optionsFragment()
                XCTAssertTrue(frag.contains("\"trabajos_manuales\"") && frag.contains("\"fases_manuales\"") && frag.contains("\"recorrido\""), frag)
                let m = try EquineAnalysis.parse(try await EquineEngine.analyseJson([file], EquineEngine.options(series: false, cacheDir: path("eng2"), extra: frag)))
                XCTAssertTrue(m.trackWork.manualCorrections && m.trackWork.efforts.count == 1 && (m.trackWork.efforts.first?.manual ?? false),
                              "Corrección manual de repeticiones")
                XCTAssertEqual(m.trackWork.efforts.first?.durationS ?? 0, 30, accuracy: 0.05, "Repetición de 30 s")
                XCTAssertEqual(m.trackWork.phaseBasis, "MANUAL", "Fase de trabajo corregida a mano")
                XCTAssertTrue(m.trackWork.courseDefined, "Salida y meta enviadas al motor (el recorrido necesita las dos)")
            }
            // start line drawn on the map: A west, B east, counted moving north (DCHA_A_IZQ) -> the arrow points north
            let ml = CorrectionsModel.mapLine(TrainingLine(aLat: 43.40, aLon: -3.4303, bLat: 43.40, bLon: -3.4297, direction: "DCHA_A_IZQ"),
                                              id: "salida", title: "Salida", color: 0x30A46C)
            XCTAssertEqual(ml.arrow.count, 3, "Flecha del sentido de la línea")
            XCTAssertGreaterThan(ml.arrow[0][1][0], 43.40 + 10 / 111_320.0, "La flecha apunta al lado por el que se cruza (norte)")
            XCTAssertEqual(ml.arrow[0][1][1], -3.43, accuracy: 1e-6, "Flecha en el centro de la línea")
            XCTAssertTrue(CorrectionsModel.mapLine(TrainingLine(aLat: 43.40, aLon: -3.4303, bLat: 43.40, bLon: -3.4297, direction: "AMBOS"),
                                                   id: "m", title: "Meta", color: 0).arrow.isEmpty, "Sin flecha si cuentan los dos sentidos")
            XCTAssertEqual(TrackWorkBreed.engineName("Pura Sangre Inglés"), "PSI")
            XCTAssertEqual(TrackWorkBreed.engineName("Árabe"), "ARABE")
            XCTAssertEqual(TrackWorkBreed.engineName("Hispano-bretón"), "GENERICO")
        }
    }
}

/// URLProtocol that fails every request (C# FailingHandler).
final class FailingURLProtocol: URLProtocol {
    static var calls = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        FailingURLProtocol.calls += 1
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}
