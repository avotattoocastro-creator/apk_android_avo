import XCTest
import Compression
@testable import AVO_Horse

// Port of the Windows self-tests (windows/AVO.Windows.SelfTest/V2Tests.cs) that exercise the analysis and report core:
// SessionTimeline / SpeedSmoother, Downsampler, ImuTimeline, SegmentAnalyzer / SegmentStore, SeriesAligner, TileMath /
// SpeedScale, ReportBuilder / PdfDocument and AnalysisExport. Synthetic data only, clearly marked (SINTETICA_*).

// MARK: - Helpers shared with other agents' code (adjust here if their API names differ)

/// TrainingImporter.Import(path, rawCacheDir) of the Windows core.
private func importSession(_ path: String, rawCacheDir: String? = nil) throws -> TrainingSession {
    return try TrainingImporter.`import`(path, rawCacheDir: rawCacheDir)
}

/// Deterministic generator (the C# test uses System.Random(7); only statistics are asserted).
private struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z: UInt64 = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func nextDouble() -> Double { Double(next() >> 11) / Double(UInt64(1) << 53) }
}

final class AnalysisAndReportsTests: XCTestCase {
    private var dir: String = ""

    override func setUpWithError() throws {
        dir = (NSTemporaryDirectory() as NSString).appendingPathComponent("avo_ipad_test_" + UUID().uuidString.replacingOccurrences(of: "-", with: ""))
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: dir)
    }

    private static let utcBase: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 22; c.hour = 6; c.minute = 15; c.second = 0
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)!
    }()

    /// Straight eastward run at hz Hz for secs seconds, speed(t) m/s, optional GNSS gap [gapFrom, gapTo).
    private func straight(_ hz: Double, _ secs: Double, _ speed: (Double) -> Double, gapFrom: Double = -1, gapTo: Double = -1,
                          carrier: Int = 2) -> TrainingSession {
        let s = TrainingSession()
        s.sessionId = "SINTETICA_PRUEBA"
        let lat0: Double = 43.4247
        let lon0: Double = -3.4519
        var x: Double = 0
        let n: Int = Int(secs * hz)
        for i in 0..<n {
            let t: Double = Double(i) / hz
            let v: Double = speed(t)
            if !(t >= gapFrom && t < gapTo) {
                let lon: Double = lon0 + x / (111320.0 * cos(lat0 * Double.pi / 180))
                let itow: Int64 = 345_600_000 + Int64((t * 1000).rounded(.toNearestOrEven))
                let utc: Date = Date(timeIntervalSince1970: AnalysisAndReportsTests.utcBase.timeIntervalSince1970 + t)
                let p = TrackPoint(latitude: lat0, longitude: lon, speedMs: v, accuracyM: 0.014, carrierSolution: carrier, gpsWeekMs: itow,
                                   altitudeM: 52, elapsedSeconds: nil, fixType: 3, numSv: 26, diffSoln: true, speedAccMs: 0.05,
                                   velNorthMs: 0, velEastMs: v, headingDeg: 90, mslAltitudeM: 2.0, utcTime: utc,
                                   chestUs: UInt64((t + 500) * 1e6))
                s.track.append(p)
                s.gnssEpochs.append(GnssEpoch(gpsWeekMs: itow, solution: carrier == 2 ? .rtkFix : .rtkFloat, numSv: 26, hAccM: 0.014, chestUs: 0))
                s.gnssSamples += 1
            }
            x += v / hz
        }
        return s
    }

    private func mean(_ values: [Double]) -> Double {
        var s: Double = 0
        for v in values { s += v }
        return values.isEmpty ? .nan : s / Double(values.count)
    }

    // MARK: - Timeline, Kalman + RTS, gaps, jumps, window

    func testTimelineAndFilter() {
        // constant acceleration 0.5 m/s² from 2 to 10 m/s with Gaussian noise 0.05 m/s on the reported speed
        var rng = SplitMix64(seed: 7)
        func noise() -> Double {
            let u1: Double = rng.nextDouble()
            let u2: Double = rng.nextDouble()
            return (-2 * log(1 - u1)).squareRoot() * cos(2 * Double.pi * u2)
        }
        let s = straight(8, 16, { 2 + 0.5 * $0 })
        for i in 0..<s.track.count { s.track[i].speedMs += 0.05 * noise() }
        let tl = SessionTimeline.build(s)
        XCTAssertTrue(tl.count == s.track.count && abs(tl.durationS - Double(s.track.count - 1) / 8.0) < 1e-9, "Línea temporal: épocas y duración")
        let mid: [Int] = Array(16..<(tl.count - 16))
        let accErr: Double = mean(mid.map { abs(tl.accelLong[$0] - 0.5) })
        let accBias: Double = mean(mid.map { tl.accelLong[$0] - 0.5 })
        XCTAssertTrue(abs(accBias) < 0.03 && accErr < 0.12, "Kalman+RTS: aceleración sin sesgo (sesgo \(accBias), error medio \(accErr) m/s²)")
        let rmsRaw: Double = mean(mid.map { pow(tl.speedReported[$0] - (2 + 0.5 * tl.t[$0]), 2) }).squareRoot()
        let rmsF: Double = mean(mid.map { pow(tl.speedFiltered[$0] - (2 + 0.5 * tl.t[$0]), 2) }).squareRoot()
        XCTAssertTrue(rmsF < rmsRaw, "Kalman+RTS reduce el ruido (\(rmsRaw) → \(rmsF) m/s) y conserva la señal original")
        XCTAssertTrue(mid.allSatisfy { abs(tl.speedDerived[$0] - (2 + 0.5 * tl.t[$0])) < 0.2 }, "Velocidad derivada de posiciones coherente")
        let expected: Double = 2 * tl.durationS + 0.25 * tl.durationS * tl.durationS
        XCTAssertTrue(abs(tl.totalDistanceM - expected) < 0.01 * expected, "Distancia geodésica (\(tl.totalDistanceM) m, teórica \(expected) m)")

        // 6 s gap: no bridging, loss interval, filter restart
        let g = straight(8, 60, { _ in 5 }, gapFrom: 20, gapTo: 26)
        let tg = SessionTimeline.build(g)
        XCTAssertTrue(tg.breakBefore.filter { $0 }.count == 1 && tg.losses.count == 1 && abs(tg.losses[0].durationS - 6.125) < 0.01,
                      "Pérdida de señal detectada (6 s) sin interpolar")
        XCTAssertTrue(abs(tg.totalDistanceM - 5 * (60 - 6 - 2 * 0.125)) < 1.0, "La distancia no puentea huecos (\(tg.totalDistanceM) m)")
        // position jump
        let j = straight(8, 20, { _ in 4 })
        j.track[80].latitude += 0.01
        let tj = SessionTimeline.build(j)
        XCTAssertTrue(tj.jumpBefore.filter { $0 }.count >= 1 && tj.totalDistanceM < 4 * 20 + 1, "Salto de posición (1,1 km) descartado de la distancia")
        XCTAssertTrue(SegmentAnalyzer.accelValid(tl, tl.count / 2), "Aceleración validada con RTK FIX y σ pequeña")
        // useful window (start/end chosen by the user): same time base, only that part analysed, original untouched
        let full = SessionTimeline.build(g)
        let cut = SessionWindow.apply(g, itow0: full.itow0Ms, t0: 30, t1: 50)
        let tw = SessionTimeline.build(cut, parameters: nil, timeBaseItowMs: full.itow0Ms)
        let expectedWindow: Double = 5 * 20 * (6371008.8 * Double.pi / 180 / 111320)
        XCTAssertTrue(abs(tw.t[0] - 30) < 0.13 && abs(tw.t[tw.count - 1] - 50) < 0.13 && abs(tw.totalDistanceM - expectedWindow) < 1.5
                      && g.track.count == full.count && cut.track.count < g.track.count,
                      "Inicio y fin del entrenamiento útil: 30–50 s, \(tw.totalDistanceM) m, misma base de tiempo, original intacto")
        XCTAssertEqual(SessionTimeline.weekDiffMs(1000, 604_799_000), 2000, "Cambio de semana GPS en iTOW")
        // filter on large dataset: performance target 1 h at 8 Hz < 1.5 s
        let big = straight(8, 3600, { 3 + sin($0 / 30) })
        let start = Date()
        let tb = SessionTimeline.build(big)
        let ms: Double = Date().timeIntervalSince(start) * 1000
        XCTAssertTrue(tb.count == 28800 && ms < 1500, "Rendimiento: línea temporal de 1 h a 8 Hz en \(Int(ms)) ms (< 1500 ms)")
    }

    // MARK: - LTTB

    func testDownsampling() {
        let x: [Double] = (0..<100_000).map { Double($0) }
        var y: [Double] = x.map { sin($0 / 500) + ($0 == 50_000 ? 10 : 0) }
        y[70_000] = .nan
        let idx: [Int] = Downsampler.lttb(x, y, 1000)
        XCTAssertTrue(idx.count <= 1010 && idx[0] == 0 && idx[idx.count - 1] == 99_999, "LTTB: \(idx.count) puntos, conserva extremos")
        XCTAssertTrue(idx.contains(50_000), "LTTB conserva el pico (solo visualización)")
        XCTAssertTrue(!idx.contains(70_000) && idx.contains(69_999) && idx.contains(70_001), "LTTB respeta los huecos (NaN)")
    }

    // MARK: - Segments and persistent store

    func testSegmentsAndStore() throws {
        let s = straight(8, 400, { t in t < 100 ? 1.5 : (t < 200 ? 3.6 : (t < 300 ? 7 : 1.4)) })
        let tl = SessionTimeline.build(s)
        let byDist = SegmentAnalyzer.byDistance(tl, 500)
        XCTAssertTrue(byDist.count == Int((tl.totalDistanceM / 500).rounded(.up)) && byDist.allSatisfy { $0.kind == .distance },
                      "Tramos automáticos de 500 m (\(byDist.count))")
        let bands = SegmentAnalyzer.bySpeedBand(tl)
        XCTAssertEqual(bands.count, 4, "Tramos por banda de velocidad (\(bands.count): \(bands.map { $0.name }.joined(separator: ", ")))")
        let m = SegmentAnalyzer.compute(tl, SegmentDefinition(name: "galope", t0: 210, t1: 290))
        XCTAssertTrue(abs(m.distanceM - 7 * 80) < 2 && abs((m.maxSpeedKmh ?? 0) - 25.2) < 0.5 && abs((m.meanSpeedKmh ?? 0) - 25.2) < 0.3,
                      "Métricas de tramo (distancia, v. máx, v. media)")
        XCTAssertTrue(m.fixFraction == 1 && m.cadence == nil && m.observations.contains("sin datos de cincha"),
                      "Tramo sin cincha: regularidad no disponible, sin inventar")
        let whole = SegmentAnalyzer.compute(tl, SegmentDefinition(name: "", t0: 0, t1: 400))
        XCTAssertTrue(whole.speedChanges == 3 && (whole.maxAccel ?? 0) > 0 && (whole.maxDecel ?? 0) < 0,
                      "Cambios de ritmo (\(whole.speedChanges)) y aceleración/frenada validadas")
        let store = SegmentStore((dir as NSString).appendingPathComponent("tramos"))
        try store.save("SINTETICA_PRUEBA", [SegmentDefinition(name: "Tramo 1", t0: 1, t1: 2, kind: .manual, notes: "nota")])
        let back = store.load("SINTETICA_PRUEBA")
        XCTAssertTrue(back.count == 1 && back[0].name == "Tramo 1" && back[0].notes == "nota", "Tramos guardados y recuperados (JSON versionado)")
        XCTAssertEqual(store.load("OTRA").count, 0, "Tramos de otra sesión no se mezclan")
        // File layout identical to Windows: PascalCase keys, enum names, 24 hex upper-case characters of SHA-256 as file name.
        let path: String = store.pathFor("SINTETICA_PRUEBA")
        let name: String = (path as NSString).lastPathComponent
        let stem: String = String(name.prefix(24))
        XCTAssertTrue(name.count == 29 && name.hasSuffix(".json") && stem.allSatisfy { "0123456789ABCDEF".contains($0) },
                      "Nombre de archivo de tramos como en Windows")
        let text: String = String(decoding: FileManager.default.contents(atPath: path) ?? Data(), as: UTF8.self)
        XCTAssertTrue(text.contains("\"Schema\": \"avo-windows-segments\"") && text.contains("\"Kind\": \"Manual\"") && text.contains("\"T0\": 1,"),
                      "JSON de tramos con las claves de Windows")
    }

    // MARK: - Comparison alignment

    func testAlignment() {
        let a = SessionTimeline.build(straight(8, 100, { _ in 4 }))
        let b = SessionTimeline.build(straight(4, 80, { _ in 5 }, gapFrom: 30, gapTo: 40))
        let al = SeriesAligner.align([a, b], { $0.speedFiltered }, .relativeTime, 1)
        XCTAssertTrue(al.axis.count == 100 && al.values[0].count == 100 && al.values.count == 2, "Alineación por tiempo: rejilla común con frecuencias distintas")
        XCTAssertTrue(al.values[1][35].isNaN && abs(al.values[1][20] - 5) < 0.05 && al.values[1][90].isNaN, "Sin interpolar a través de huecos ni más allá del final")
        let ad = SeriesAligner.align([a, b], { $0.speedFiltered }, .distance, 5)
        XCTAssertTrue(ad.axis.count > 70 && abs(ad.values[0][20] - 4) < 0.05, "Alineación por distancia recorrida")
    }

    // MARK: - Map geometry and colour scales

    func testGeometry() {
        let px = TileMath.latLonToPixel(43.4247, -3.4519, 15)
        let ll = TileMath.pixelToLatLon(px.x, px.y, 15)
        XCTAssertTrue(abs(ll.lat - 43.4247) < 1e-9 && abs(ll.lon + 3.4519) < 1e-9, "Web Mercator: ida y vuelta")
        let z: Double = TileMath.fitZoom(43.42, -3.46, 43.43, -3.44, 1000, 700)
        XCTAssertTrue(z > 13 && z < 17, "Ajuste de zoom al recorrido")
        let c0 = SpeedScale.color(0, 10)
        let c1 = SpeedScale.color(10, 10)
        let c2 = SpeedScale.color(3.3, 10)
        XCTAssertTrue(c0 == (0x2F, 0x6B, 0xFF) && c1 == (0xED, 0x12, 0x2A) && c2 == (0x35, 0xD0, 0xE8),
                      "Escala de velocidad idéntica a Android (azul → cian → amarillo → rojo)")
    }

    // MARK: - Girth IMU series (ImuTimeline)

    func testImuNominalScaleAndNames() {
        XCTAssertTrue(abs(Double(Int16(4100)) * ImuTimeline.nominalAccelGPerLsb - 1.0004) < 1e-3 && ImuTimeline.sensorName(1) == "Izquierda",
                      "Escala nominal ±8 g y asignación de sensores")
    }

    /// GIRTH 0.4.3+: header byte 15 = 1 declares BNO085 units (acc Q8 m/s², gyro Q9 rad/s); fmt 1 carries linear
    /// acceleration and quaternion. A session without the byte keeps the nominal scale. (The C# test builds the session
    /// through the RAW importer; here the decoded session is built directly — the decoding is tested with the importer.)
    func testImuBno085Units() {
        let s = TrainingSession()
        s.sessionId = "SINTETICA_BNO"
        s.imuUnits = 1
        s.imuPeriodUs = 9615
        s.imu = [
            ImuRawSample(imuId: 0, timeS: 3.0 - 0.009615, ax: 0, ay: 0, az: 2511, gx: 512, gy: 0, gz: 0, mx: 16, my: 0, mz: 0),
            ImuRawSample(imuId: 0, timeS: 3.0, ax: 256, ay: 0, az: 2511, gx: 0, gy: 0, gz: 0, mx: 16, my: 0, mz: 0),
        ]
        s.imuFused = [
            ImuFusedSample(imuId: 0, timeS: 3.0 - 0.009615, lx: 128, ly: 0, lz: 0, qi: 0, qj: 0, qk: 0, qr: 16384),
            ImuFusedSample(imuId: 0, timeS: 3.0, lx: 128, ly: 0, lz: 0, qi: 0, qj: 0, qk: 0, qr: 16384),
        ]
        s.imuFusedBatches = 1
        let imu = ImuTimeline.build(s, SessionTimeline.build(s))
        XCTAssertTrue(imu.note == ImuTimeline.bno085ScaleNote && abs(2511 * imu.accelGPerLsb - 1.0) < 1e-3 && abs(512 * imu.gyroDpsPerLsb - 57.2958) < 1e-3,
                      "Escala BNO085: 2511 LSB = 1 g, 512 LSB = 1 rad/s = 57,3 °/s")
        XCTAssertTrue(imu.channels.count == 1 && imu.channels[0].t.count == 2, "Serie cruda de la cincha")
        XCTAssertTrue(imu.fused.count == 1 && imu.fused[0].t.count == 2 && abs(imu.fused[0].verticalMs2[0]) < 1e-9
                      && abs(imu.fused[0].horizontalMs2[0] - 0.5) < 1e-9,
                      "Movimiento de la cincha: aceleración lineal 0,5 m/s² en x con cuaternión identidad = 0,5 horizontal, 0 vertical")
        let up = ImuTimeline.fuse(0, 256, 0, 11585, 0, 0, 11585)   // 90° about x: the sensor y axis points up
        XCTAssertTrue(abs(up.up - 1.0) < 1e-3 && up.horizontal < 1e-3 && abs(up.rollDeg - 90) < 0.1 && abs(up.pitchDeg) < 0.1,
                      "Cuaternión → ejes del mundo: con 90° de balanceo, y del sensor = vertical")
        let tilt = ImuTimeline.fuse(0, 0, 0, 1170, -804, -59, 16322)   // monitor 0.4.2 at rest: quat 0.0714 -0.0491 -0.0036 0.9962
        XCTAssertTrue(abs(tilt.rollDeg - 8.2) < 0.3 && abs(tilt.pitchDeg + 5.6) < 0.3, "Balanceo y cabeceo de la cincha en reposo (≈8,2° y −5,6°)")
        let old = TrainingSession()
        XCTAssertEqual(ImuTimeline.build(old, SessionTimeline.build(old)).accelGPerLsb, ImuTimeline.nominalAccelGPerLsb,
                       "Sin unidades declaradas: escala nominal como antes")
    }

    // MARK: - .NET-compatible formatting used by every export

    func testDotNetFormatting() {
        XCTAssertEqual(DotNetFormat.custom(25.2, "0.0", spanish: true), "25,2")
        XCTAssertEqual(DotNetFormat.custom(2.675, "0.00", spanish: false), "2.68")
        XCTAssertEqual(DotNetFormat.custom(-0.001, "0.00", spanish: false), "0.00")
        XCTAssertEqual(DotNetFormat.custom(1.0, "0.##", spanish: true), "1")
        XCTAssertEqual(DotNetFormat.custom(0.505, "0.0#", spanish: true), "0,51")
        XCTAssertEqual(DotNetFormat.custom(-0.0123, "+0.000;-0.000", spanish: false), "-0.012")
        XCTAssertEqual(DotNetFormat.custom(12345.678, "#,##0.0", spanish: true), "12.345,7")
        XCTAssertEqual(DotNetFormat.roundTrip(1.0), "1")
        XCTAssertEqual(DotNetFormat.roundTrip(0.125), "0.125")
        XCTAssertEqual(DotNetFormat.roundTrip(0.0001), "0.0001")
        XCTAssertEqual(DotNetFormat.roundTrip(0.00001), "1E-05")
        XCTAssertEqual(DotNetFormat.roundTrip(1e15), "1E+15")
        XCTAssertEqual(DotNetFormat.round(2.345, 2), 2.34, accuracy: 1e-12)
        XCTAssertEqual(DotNetJsonWriter.quote("Ó \"x\" <a>"), "\"\\u00D3 \\u0022x\\u0022 \\u003Ca\\u003E\"")
        XCTAssertEqual(DotNetText.htmlEncode("á<b>"), "&#225;&lt;b&gt;")
        XCTAssertEqual(TimeText.clock(59.99), "00:59")
        XCTAssertEqual(TimeText.clock(3725), "1:02:05")
        XCTAssertEqual(TimeText.num(nil, "0.0", " km"), "Sin datos")
        XCTAssertEqual(SpeedSmoother.Parameters().describe(),
                       "Kalman v-a + suavizado RTS · densidad de sacudida 1 m²/s⁵ · σv mín. 0,05 m/s · σv sin sAcc 0,15 m/s")
    }

    // MARK: - Reports and exports

    func testExports() throws {
        let s = straight(8, 120, { 3 + $0 / 40 }, gapFrom: 60, gapTo: 63)
        s.horse = "Rayo"; s.rider = "Antonio"
        let tl = SessionTimeline.build(s)
        let segs: [SegmentMetrics] = [SegmentAnalyzer.compute(tl, SegmentDefinition(name: "T1", t0: 10, t1: 50))]
        let data = ReportData(session: s, timeline: tl, segments: segs, notes: "Arena compacta.\nSegunda línea con acentos: ñ á é.")
        let pdfPath: String = (dir as NSString).appendingPathComponent("r.pdf")
        try ReportBuilder.writePdf(data, to: pdfPath)
        let bytes: [UInt8] = [UInt8](FileManager.default.contents(atPath: pdfPath) ?? Data())
        let head: String = String(decoding: bytes.prefix(8), as: UTF8.self)
        let tailText: String = String(decoding: bytes.suffix(16), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(head == "%PDF-1.4" && tailText.hasSuffix("%%EOF"), "PDF: cabecera y final")

        let startxref: Int = lastIndex(of: Array("startxref".utf8), in: bytes)
        XCTAssertTrue(startxref > 0)
        let afterStart: String = String(decoding: bytes[(startxref + 10)...], as: UTF8.self)
        let xref: Int = Int(afterStart.components(separatedBy: "\n")[0]) ?? -1
        XCTAssertTrue(xref > 0 && xref < bytes.count)
        let xrefLines: [String] = String(decoding: bytes[xref...], as: UTF8.self).components(separatedBy: "\n")
        let count: Int = Int(xrefLines[1].components(separatedBy: " ")[1]) ?? 0
        var offsetsOk: Bool = true
        if count > 1 {
            for i in 1..<count {
                let off: Int = Int(xrefLines[2 + i].prefix(10)) ?? -1
                let expected: [UInt8] = Array("\(i) 0 obj".utf8)
                offsetsOk = offsetsOk && off >= 0 && off + expected.count <= bytes.count && Array(bytes[off..<(off + expected.count)]) == expected
            }
        }
        XCTAssertTrue(offsetsOk && count > 6, "PDF: tabla xref válida (\(count - 1) objetos)")

        let st: Int = firstIndex(of: Array("stream\n".utf8), in: bytes, from: 0) + 7
        let en: Int = firstIndex(of: Array("\nendstream".utf8), in: bytes, from: st)
        XCTAssertTrue(st > 7 && en > st)
        let content: String = inflateZlib(Array(bytes[st..<en])).map { String(UnicodeScalar($0)) }.joined()
        XCTAssertTrue(content.contains("BT /F2") && content.contains("Informe de entrenamiento") && content.contains("DEMOSTRACI\\323N"),
                      "PDF: contenido comprimido con texto WinAnsi (Ó)")
        XCTAssertEqual(PdfDocument.measureText("AVO", 10, true), Double(722 + 667 + 778) / 100.0, accuracy: 1e-9, "PDF: métricas Helvetica-Bold")

        let html: String = ReportBuilder.html(data)
        XCTAssertTrue(html.contains("DEMOSTRACIÓN") && html.contains("<svg") && html.contains("Arena compacta"), "HTML imprimible con mapa SVG y notas")

        let csv: String = (dir as NSString).appendingPathComponent("t.csv")
        try AnalysisExport.timelineCsv(tl, csv)
        var csvData: Data = FileManager.default.contents(atPath: csv) ?? Data()
        XCTAssertTrue(csvData.starts(with: [0xEF, 0xBB, 0xBF]), "CSV con BOM UTF-8 (como Windows)")
        csvData = csvData.dropFirst(3)
        var rows: [String] = String(decoding: csvData, as: UTF8.self).components(separatedBy: "\r\n")
        if rows.last == "" { rows.removeLast() }
        XCTAssertTrue(rows.count == tl.count + 1 && rows[0].contains("velocidad_filtrada_ms") && rows.filter { $0.hasSuffix(";1;0") }.count == 1,
                      "CSV con unidades, valores originales y marca de corte")

        let gpx: String = (dir as NSString).appendingPathComponent("t.gpx")
        try AnalysisExport.gpx(s, tl, gpx)
        let counter = GpxCounter()
        let parser = XMLParser(data: FileManager.default.contents(atPath: gpx) ?? Data())
        parser.shouldProcessNamespaces = true
        parser.delegate = counter
        XCTAssertTrue(parser.parse(), "GPX bien formado")
        XCTAssertTrue(counter.trkpt == tl.count && counter.trkseg == 2 && counter.time > 0 && counter.namespaceOk,
                      "GPX 1.1 con hora UTC y segmento nuevo tras el hueco")

        let json: String = AnalysisExport.json(s, tl, segs, nil, true)
        let root = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
        let tramos = root?["tramos"] as? [[String: Any]]
        XCTAssertTrue((root?["formato"] as? String) == AnalysisExport.jsonFormat && (root?["version_formato"] as? Int) == 1
                      && tramos?.count == 1 && (tramos?[0]["cadencia_trancos_min"] is NSNull),
                      "JSON versionado: ausencias como null, no como cifras")
    }

    // MARK: - Demonstration sessions (bundle folder "demo"; skipped when absent)

    func testDemoSessions() throws {
        guard let demo = Bundle.main.url(forResource: "demo", withExtension: nil) else {
            throw XCTSkip("Carpeta demo no incluida en el paquete; pruebas con sesiones de demostración omitidas")
        }
        let file: String = demo.appendingPathComponent("DEMO_REGATON_20261022.avr").path
        guard FileManager.default.fileExists(atPath: file) else {
            throw XCTSkip("DEMO_REGATON_20261022.avr no está en demo/; pruebas omitidas")
        }
        let start = Date()
        let s = try importSession(file)
        let tl = SessionTimeline.build(s)
        let imu = ImuTimeline.build(s, tl)
        let ms: Double = Date().timeIntervalSince(start) * 1000
        XCTAssertTrue(s.isSynthetic && s.horse.contains("demo") && imu.channels.count == 3 && abs(imu.sampleRateHz - 104) < 0.1,
                      "Demostración: 3 IMU a 104 Hz, marcada como sintética")
        XCTAssertTrue(ms < 5000, "Rendimiento: importar + series de 20 min con 3 IMU en \(Int(ms)) ms (< 5000 ms)")
        let fixFraction: Double = tl.fractionAtLeast(.rtkFix, 0, 1e9)
        XCTAssertTrue(tl.losses.contains(where: { $0.durationS > 5 && $0.durationS < 8 }) && fixFraction > 0.8 && fixFraction < 1,
                      "Demostración: pérdida de 6 s y periodos FLOAT/autónomos detectados")
        XCTAssertTrue(abs(imu.offsetS - 500) < 0.05 && imu.aligned, "Alineación reloj pecho → GNSS (\(imu.offsetS) s)")
        var year: Int = 0
        if let u = tl.utc0 {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "UTC")!
            year = cal.component(.year, from: u)
        }
        XCTAssertTrue(year == 2026 && ReportBuilder.madrid(tl.utc0, "HH:mm") == "08:15", "Hora UTC del receptor → 08:15 Europe/Madrid")
        let vmax: Double = Stats.maxFinite(tl.speedFiltered) * 3.6
        XCTAssertTrue(vmax > 38 && vmax < 44, "Velocidad máxima de la demostración (galope ~41 km/h)")
        // Engine part of the C# test (EquineEngine.Available) is covered by the engine tests, not here.
    }

    // MARK: - byte helpers

    private func firstIndex(of pattern: [UInt8], in bytes: [UInt8], from: Int) -> Int {
        if pattern.isEmpty || bytes.count < pattern.count { return -1 }
        var i: Int = max(0, from)
        while i + pattern.count <= bytes.count {
            if bytes[i] == pattern[0] && Array(bytes[i..<(i + pattern.count)]) == pattern { return i }
            i += 1
        }
        return -1
    }

    private func lastIndex(of pattern: [UInt8], in bytes: [UInt8]) -> Int {
        if pattern.isEmpty || bytes.count < pattern.count { return -1 }
        var i: Int = bytes.count - pattern.count
        while i >= 0 {
            if bytes[i] == pattern[0] && Array(bytes[i..<(i + pattern.count)]) == pattern { return i }
            i -= 1
        }
        return -1
    }

    /// zlib (RFC 1950) → bytes, using Compression's raw DEFLATE decoder.
    private func inflateZlib(_ z: [UInt8]) -> [UInt8] {
        guard z.count > 6 else { return [] }
        let raw: [UInt8] = Array(z[2..<(z.count - 4)])
        var out: [UInt8] = [UInt8](repeating: 0, count: max(raw.count * 40, 1 << 20))
        let n: Int = raw.withUnsafeBufferPointer { (src: UnsafeBufferPointer<UInt8>) -> Int in
            out.withUnsafeMutableBufferPointer { (dst: inout UnsafeMutableBufferPointer<UInt8>) -> Int in
                guard let d = dst.baseAddress, let s = src.baseAddress else { return 0 }
                return compression_decode_buffer(d, dst.count, s, src.count, nil, COMPRESSION_ZLIB)
            }
        }
        return Array(out[0..<n])
    }
}

/// Counts GPX elements (namespace-aware, as XDocument.Descendants(ns + name)).
private final class GpxCounter: NSObject, XMLParserDelegate {
    var trkpt: Int = 0
    var trkseg: Int = 0
    var time: Int = 0
    var namespaceOk: Bool = true

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let gpxNs: Bool = namespaceURI == "http://www.topografix.com/GPX/1/1"
        if elementName == "trkpt" { if gpxNs { trkpt += 1 } else { namespaceOk = false } }
        if elementName == "trkseg" && gpxNs { trkseg += 1 }
        if elementName == "time" && gpxNs { time += 1 }
    }
}
