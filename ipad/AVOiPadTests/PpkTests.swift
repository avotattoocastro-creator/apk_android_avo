import XCTest
@testable import AVO_Horse

/// AVO PPK 1.0.0 (docs/PPK.md): gzip de los ficheros del IGN, nombres y rutas del IGN, y lectura de las respuestas
/// del motor. El cálculo PPK se prueba en el motor (equine-intelligence/tests/test_ppk.cpp).
final class PpkTests: XCTestCase {
    /// gzip.compress(b"AVO PPK prueba\n" * 20, mtime=0) de Python.
    private let gz: [UInt8] = [0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0xFF, 0x73, 0x0C, 0xF3, 0x57, 0x08, 0x08,
                               0xF0, 0x56, 0x28, 0x28, 0x2A, 0x4D, 0x4D, 0x4A, 0xE4, 0x72, 0x1C, 0xE5, 0xE2, 0xE6, 0x02, 0x00,
                               0x31, 0xD1, 0xE7, 0xD7, 0x2C, 0x01, 0x00, 0x00]

    func testGzip() throws {
        let out: Data = try Gzip.decompress(Data(gz))
        XCTAssertEqual(String(decoding: out, as: UTF8.self), String(repeating: "AVO PPK prueba\n", count: 20))
        // dos miembros seguidos (como hace gzip con ficheros concatenados)
        let two: Data = try Gzip.decompress(Data(gz + gz))
        XCTAssertEqual(two.count, 600)
        XCTAssertThrowsError(try Gzip.decompress(Data("no es gzip".utf8)))
    }

    /// 27/11/2026: «gzip cortado» con la base real del IGN. El pie gzip decide si el miembro está completo.
    func testGzipTrailerAndTruncation() throws {
        XCTAssertEqual(Gzip.crc32(Data("123456789".utf8)), 0xCBF4_3926)
        let plain: Data = Data(String(repeating: "AVO PPK prueba\n", count: 20).utf8)
        XCTAssertTrue(Gzip.trailerMatches(gz, end: gz.count, data: plain))
        XCTAssertFalse(Gzip.trailerMatches(gz, end: gz.count, data: plain.dropLast()))
        XCTAssertThrowsError(try Gzip.decompress(Data(gz.dropLast(12))))   // descarga cortada: error, nunca datos a medias
    }

    func testIgnNamesAndFolders() {
        // 29/05/2026 09:00 UTC = día 149 (captura del servidor del IGN del 23/11/2026)
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 29; c.hour = 9
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let h: Date = cal.date(from: c)!
        XCTAssertEqual(IgnBase.stamp(h), "20261490900")
        XCTAssertEqual(IgnBase.hourFolder(h), "http://datos-geodesia.ign.es/ERGNSS/horario_1s/20260529/09/")
        XCTAssertEqual(PpkConfig.cloudFileName("S-2026_11"), "AVO_S-2026_11.ppk.json")
    }

    func testNeedAndSummaryFromEngine() {
        let need = PpkNeed.parse("{\"formato\":\"avo-ppk-necesita\",\"tiene_rawx\":true,\"rawx\":120,\"inicio_utc\":\"2005-04-01T23:59:47.000Z\",\"fin_utc\":\"2005-04-02T00:59:17.000Z\",\"lat\":35.1,\"lon\":139.5}")
        XCTAssertEqual(need?.hasRaw, true)
        XCTAssertEqual(need?.hours.count, 2)   // 23:00 y 00:00 UTC
        let s = PpkSummary.parse("{\"formato\":\"avo-ppk\",\"base\":{\"nombre\":\"0759\",\"linea_base_km\":3.33},\"resultado\":{\"epocas\":120,\"fix\":118,\"float\":2,\"pct_fix\":98.3},\"avisos\":[\"a\"]}")
        XCTAssertEqual(s?.fix, 118)
        XCTAssertEqual(s?.base, "0759")
        XCTAssertEqual(s?.warnings, ["a"])
        XCTAssertNil(PpkSummary.parse("{\"formato\":\"otro\"}"))
    }
}
