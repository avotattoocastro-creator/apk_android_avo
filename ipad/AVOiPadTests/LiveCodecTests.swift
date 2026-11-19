import XCTest
@testable import AVO_Horse

/// LIVE1 (mismos vectores que core/src/test/.../LiveCodecTest.kt) y reconstrucción de la sesión a partir de los eventos
/// del flujo de Firebase.
final class LiveCodecTests: XCTestCase {
    let line: String = "LIVE1,1500,434190000,-34540000,15200,250000,3,0,180,31,2"

    func testVectorSharedWithAndroid() {
        let s: [LiveSample] = LiveCodec.decode(line)
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s[0].tMs, 1500)
        XCTAssertEqual(s[0].latE7, 434190000)
        XCTAssertEqual(s[0].lonE7, -34540000)
        XCTAssertEqual(s[0].speedMmS, 15200)
        XCTAssertEqual(s[0].distCm, 250000)
        XCTAssertEqual(s[0].numSv, 31)
        XCTAssertEqual(LiveCodec.encode(s[0]), line)
        XCTAssertTrue(s[0].hasPosition)
        XCTAssertEqual(s[0].solution, .autonomous)
        var b = s[0]; b.tMs = 2000
        XCTAssertEqual(LiveCodec.encodeChunk([s[0], b]),
                       "LIVE1,1500,434190000,-34540000,15200,250000,3,0,180,31,2;2000,434190000,-34540000,15200,250000,3,0,180,31,2")
    }

    func testMalformedIsDiscarded() {
        XCTAssertEqual(LiveCodec.decode(nil).count, 0)
        XCTAssertEqual(LiveCodec.decode("hola").count, 0)
        XCTAssertEqual(LiveCodec.decode("LIVE1,1,2,3,4,5,6,7,8,9,10;1,2,3;x,2,3,4,5,6,7,8,9,10").count, 1)
        XCTAssertEqual(LiveCodec.decode("LIVE1,1,99999999999,3,4,5,6,7,8,9,10").count, 0)
    }

    func testStreamEvents() {
        var st = LiveSessionState()
        // primer put con todo el nodo (los bloques llegan como lista porque las claves son 0…n)
        st.apply(event: "put", path: "/", data: [
            "meta": ["horseName": "POWER GOLD", "riderName": "Andoni", "startMs": NSNumber(value: 1000), "state": "REC",
                     "updatedMs": NSNumber(value: 2000), "expiresMs": NSNumber(value: 9000)],
            "s": ["LIVE1,0,434190000,-34540000,1000,0,3,0,500,20,2;500,434190010,-34540010,2000,100,3,0,500,20,2"],
            "last": "LIVE1,500,434190010,-34540010,2000,100,3,0,500,20,2",
        ] as [String: Any])
        XCTAssertEqual(st.meta.horseName, "POWER GOLD")
        XCTAssertEqual(st.samples.count, 2)
        st.apply(event: "put", path: "/last", data: "LIVE1,1000,434190020,-34540020,3000,250,3,2,20,25,2")
        XCTAssertEqual(st.samples.count, 3)
        XCTAssertEqual(st.samples.last?.solution, .rtkFix)
        st.apply(event: "put", path: "/s/1", data: "LIVE1,1000,434190020,-34540020,3000,250,3,2,20,25,2")
        XCTAssertEqual(st.samples.count, 3)   // sin duplicados
        st.apply(event: "patch", path: "/meta", data: ["state": "END", "updatedMs": NSNumber(value: 3000)] as [String: Any])
        XCTAssertTrue(st.meta.isEnded)
        XCTAssertEqual(st.meta.horseName, "POWER GOLD")
    }

    func testSeriesGaitNeedsThreeSeconds() {
        var s: [LiveSample] = []
        for i in 0..<40 {
            let v: Int32 = i < 10 ? 1500 : 10000   // 5,4 km/h (paso) y luego 36 km/h (galope)
            s.append(LiveSample(tMs: Int64(i * 500), latE7: 434190000, lonE7: -34540000, speedMmS: v, distCm: Int64(i * 300),
                                fix: 3, carr: 0, hAccMm: 300, numSv: 20, session: 2))
        }
        let r: LiveSeries = LiveSeries.build(s)
        XCTAssertEqual(r.gait, .canter)
        XCTAssertEqual(r.speedKmh.count, 40)
        XCTAssertGreaterThan(r.accel.max() ?? 0, 1)
        XCTAssertGreaterThanOrEqual(r.gaitSince, 4.5)
    }

    func testUserCardLink() throws {
        let c = try AvoUserCard.parse("avohorse://identity/user/AVO-ABCD-EFGH?v=1&name=Ana%20Ruiz&k=0123456789abcdef0123456789abcdef")
        XCTAssertEqual(c.code, "AVO-ABCD-EFGH")
        XCTAssertEqual(c.name, "Ana Ruiz")
        XCTAssertEqual(c.email, "avo-abcd-efgh@avo-cards.app")
        XCTAssertThrowsError(try AvoUserCard.parse("avohorse://identity/user/AVO-ABCD-EFG0?v=1&name=x&k=0123456789abcdef0123456789abcdef"))
        XCTAssertThrowsError(try AvoUserCard(code: "AVO-ABCD-EFGH", name: "", secret: "corta"))
        let m = try AvoUserCard(code: " avo-abcd-efgh ", name: "", secret: "0123 4567 89AB CDEF 0123 4567 89ab cdef")
        XCTAssertEqual(m.secret, "0123456789abcdef0123456789abcdef")
    }
}
