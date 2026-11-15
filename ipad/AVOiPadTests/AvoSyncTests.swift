import XCTest
@testable import AVO_Horse

/// AVO SYNC v1: tramas, cálculo del desfase y archivo .avosync.json (docs/AVO_SYNC.md). Pruebas simuladas: no sustituyen a
/// la prueba con el gadget y el LED grabado a 240 fps.
final class AvoSyncTests: XCTestCase {
    func testFrameSizesAndRoundTrip() {
        let req = AvoSyncProtocol.encodeTimeRequest(seq: 7, t1HostNs: 123_456_789_012)
        XCTAssertEqual(req.count, 16)
        XCTAssertEqual([UInt8](req.prefix(4)), [1, 1, 7, 0])

        let r = AvoSyncProtocol.TimeResponse(seq: 7, flags: [.fix, .timeValid, .ppsLocked], satellites: 14,
                                             t1HostNs: 123_456_789_012, t2UtcNs: 1_763_200_000_000_000_000,
                                             t3UtcNs: 1_763_200_000_000_050_000)
        let rd = AvoSyncProtocol.encodeTimeResponse(r)
        XCTAssertEqual(rd.count, 32)
        XCTAssertEqual(AvoSyncProtocol.decode(rd), .timeResponse(r))

        let m = AvoSyncProtocol.Mark(seq: 3, kind: 2, utcNs: 1_763_200_001_000_000_000)
        let md = AvoSyncProtocol.encodeMark(m)
        XCTAssertEqual(md.count, 16)
        XCTAssertEqual(AvoSyncProtocol.decode(md), .mark(m))

        let s = AvoSyncProtocol.Status(batteryMv: 3912, batteryPercent: 78, fix: 3, satellites: 12, flags: [.fix, .timeValid],
                                       hAccMm: 1450, uptimeS: 3600)
        let sd = AvoSyncProtocol.encodeStatus(s)
        XCTAssertEqual(sd.count, 16)
        XCTAssertEqual(AvoSyncProtocol.decode(sd), .status(s))

        // versión, tipo o tamaño ajenos a v1 se ignoran
        var bad = rd; bad[0] = 2
        XCTAssertNil(AvoSyncProtocol.decode(bad))
        XCTAssertNil(AvoSyncProtocol.decode(rd.prefix(31)))
        XCTAssertNil(AvoSyncProtocol.decode(req))
    }

    func testSampleOffsetAndDelaySymmetric() {
        // reloj del iPad = UTC − 1000 s; 4 ms de ida, 1 ms en el gadget, 4 ms de vuelta
        let off: Int64 = 1_000_000_000_000
        let t1: Int64 = 5_000_000_000
        let t2 = t1 + off + 4_000_000
        let t3 = t2 + 1_000_000
        let t4 = t3 - off + 4_000_000
        let s = AvoSyncSample(t1: t1, t2: t2, t3: t3, t4: t4)
        XCTAssertEqual(s.offsetNs, off)
        XCTAssertEqual(s.delayNs, 8_000_000)
    }

    func testEstimatorKeepsMinimumDelayAndFitsDrift() {
        var e = AvoSyncEstimator()
        let off0: Int64 = 1_700_000_000_000_000_000
        let drift = 20e-6    // 20 ppm
        var rng = SystemRandomNumberGenerator()
        // 10 minutos, una muestra por segundo; retardo asimétrico aleatorio (la ida tarda más que la vuelta)
        for i in 0..<600 {
            let host = Int64(i) * 1_000_000_000 + 50_000_000_000
            let trueOff = off0 + Int64(drift * Double(host))
            let up = Int64.random(in: 1_000_000...40_000_000, using: &rng)
            let down: Int64 = 1_000_000
            let t1 = host
            let t2 = t1 + up + trueOff
            let t3 = t2 + 200_000
            let t4 = t3 - trueOff + down
            e.add(AvoSyncSample(t1: t1, t2: t2, t3: t3, t4: t4))
        }
        // una muestra con 1 s de retardo se descarta
        e.add(AvoSyncSample(hostNs: 700_000_000_000, offsetNs: off0, delayNs: 1_000_000_000))
        XCTAssertEqual(e.rejected, 1)
        XCTAssertEqual(e.points.count, 31)   // 30 ventanas cerradas + la ventana en curso
        let f = try! XCTUnwrap(e.fit)
        let host: Int64 = 640_000_000_000
        let expected = off0 + Int64(drift * Double(host))
        // con el filtro de menor retardo el error queda por debajo de 5 ms aunque haya muestras de hasta 40 ms
        XCTAssertLessThan(abs(f.offset(atHostNs: host) - expected), 5_000_000)
        XCTAssertNotNil(e.errorBoundNs)
    }

    func testVideoFileRoundTripAndTimeOfFrame() throws {
        let fit = AvoSyncFit(refHostNs: 1_000_000_000, offsetAtRefNs: 1_763_200_000_000_000_000, slope: 0)
        let f = AvoSyncVideoFile(video: "AVO_VIDEO_20261115_101500.mov", width: 1920, height: 1080, fpsNominal: 60,
                                 codec: "hevc", frames: 600, firstFrameHostNs: 2_000_000_000, lastFrameHostNs: 11_983_333_333,
                                 source: .avoSync, firstFrameUtcNs: fit.utcNs(hostNs: 2_000_000_000), errorBoundMs: 2.5,
                                 minDelayMs: 3, spreadMs: 1, holdover: false, fit: fit,
                                 samples: [AvoSyncSample(hostNs: 1_000_000_000, offsetNs: 1_763_200_000_000_000_000, delayNs: 3_000_000)],
                                 marks: [.init(kind: .series, utcNs: 1_763_200_003_000_000_000)],
                                 systemClockStart: .init(hostNs: 2_000_000_000, unixNs: 1_763_200_002_010_000_000),
                                 systemClockEnd: .init(hostNs: 12_000_000_000, unixNs: 1_763_200_012_010_000_000),
                                 gadgetName: "AVO SYNC", appVersion: "1.0.0 (test)")
        let data = try AvoSyncVideoFile.encode(f)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"first_frame_utc_ns\""))
        XCTAssertTrue(json.contains("\"avo_sync\""))
        let back = try AvoSyncVideoFile.decode(data)
        XCTAssertEqual(back, f)
        // fotograma a 1 s del primero
        XCTAssertEqual(back.utcNs(videoTimeS: 1), 1_763_200_000_000_000_000 + 3_000_000_000)
        XCTAssertEqual(back.durationS, 9.983333333, accuracy: 1e-6)
    }
}
