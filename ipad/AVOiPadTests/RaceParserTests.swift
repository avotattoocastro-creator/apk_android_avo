import XCTest
import PDFKit
@testable import AVO_Horse

/// «Carreras»: parser of the France Galop / McLloyd «Statistiques Tracking» PDF (real sample of Bordeaux, 29/10/2026),
/// matching of the Cuadra horse with the runners and the race analysis (Core/RaceAnalysis.swift).
final class RaceParserTests: XCTestCase {
    private func fixtureURL() throws -> URL {
        let bundles: [Bundle] = [Bundle(for: RaceParserTests.self), Bundle.main]
        for b in bundles {
            if let u = b.url(forResource: "20261029BOU03_last_times_fr", withExtension: "pdf") { return u }
        }
        for b in bundles {
            if let u = b.url(forResource: "demo_race_20261029BOU03", withExtension: "pdf") { return u }
        }
        throw XCTSkip("Falta el PDF de muestra 20261029BOU03_last_times_fr.pdf")
    }

    private func sample() throws -> Race { try RaceTrackingParser.parse(url: try fixtureURL()) }

    private func runner(_ race: Race, _ name: String) throws -> RaceRunner {
        try XCTUnwrap(race.runners.first { $0.name == name }, "Participante \(name)")
    }

    /// Diagnostics: writes the PDFKit text of every page (the order differs from pdftotext) to AVO_SHOTS for CI review.
    func testDumpPdfKitText() throws {
        guard let dir = ProcessInfo.processInfo.environment["AVO_SHOTS"], !dir.isEmpty else { throw XCTSkip("sin AVO_SHOTS") }
        let doc = try XCTUnwrap(PDFDocument(url: try fixtureURL()))
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for i in 0..<doc.pageCount {
            let t: String = doc.page(at: i)?.string ?? ""
            try? t.write(toFile: (dir as NSString).appendingPathComponent("pdfkit_page\(i + 1).txt"), atomically: true, encoding: .utf8)
        }
    }

    /// Same race from the text that PDFKit produced on the iPad simulator (column groups, header block first).
    func testParsesPdfKitTextOrder() throws {
        var pages: [String] = []
        for i in 1...7 {
            guard let u = Bundle(for: RaceParserTests.self).url(forResource: "race_pdfkit_page\(i)", withExtension: "txt") else {
                throw XCTSkip("faltan los textos PDFKit de muestra")
            }
            pages.append(try String(contentsOf: u, encoding: .utf8))
        }
        let race: Race = try RaceTrackingParser.parse(pages: pages, sourceFile: "muestra.pdf")
        XCTAssertEqual(race.runners.count, 6)
        let z = try runner(race, "ZAKYNA AL ZARAYAN")
        XCTAssertEqual(z.finish, 5)
        XCTAssertEqual(z.jockey, "R. DUBORD")
        XCTAssertEqual(z.officialTimeS ?? 0, 99.99, accuracy: 0.001)
        XCTAssertEqual(z.sectors.map { $0.sectorS }, [17.80, 13.39, 13.56, 13.54, 13.26, 13.39, 15.02])
        XCTAssertEqual(z.sectors.compactMap { $0.strides }, [37, 31, 30, 32, 30, 30, 32])
        XCTAssertEqual(z.sectors.compactMap { $0.meanSpeedKmh }, [49.9, 53.9, 53, 53.8, 55, 53.8, 47.8])
        XCTAssertEqual(z.sectors.compactMap { $0.position }, [5, 4, 4, 4, 6, 5, 5])
        XCTAssertEqual(z.number, 6)
        XCTAssertEqual(z.draw, 3)
        XCTAssertEqual(z.distanceVsWinnerM ?? 0, 1.54, accuracy: 0.001)
        let lino = try runner(race, "LINO")
        XCTAssertEqual(lino.finish, 1)
        XCTAssertEqual(lino.officialTimeS ?? 0, 96.57, accuracy: 0.001)
    }

    // ---------------------------------------------------------------- parser
    func testParsesHeaderAndRunners() throws {
        let race: Race = try sample()
        XCTAssertEqual(race.hippodrome, "BORDEAUX")
        XCTAssertEqual(race.category, "C3")
        XCTAssertEqual(race.raceName, "PRIX JEAN LABORDE")
        XCTAssertEqual(race.distanceM, 1400, accuracy: 0.001)
        XCTAssertEqual(race.winnerRedk ?? 0, 68.97, accuracy: 0.001, "Redk du 1er 1'08\"97")
        let d: Date = try XCTUnwrap(race.date)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = AvoTime.madrid
        let c: DateComponents = cal.dateComponents([.year, .month, .day], from: d)
        XCTAssertEqual(c.year, 2026)
        XCTAssertEqual(c.month, 10)
        XCTAssertEqual(c.day, 29)
        XCTAssertEqual(race.runners.count, 6)
        XCTAssertEqual(race.runners.map { $0.name }, ["LINO", "ALLIE SAINT LON", "BIANCA DE GHAZAL", "AS MAADIN", "ZAKYNA AL ZARAYAN", "MAMAMIA HIPOLYTE"],
                       "Orden de llegada")

        let lino: RaceRunner = try runner(race, "LINO")
        XCTAssertEqual(lino.finish, 1)
        XCTAssertEqual(lino.officialTimeS ?? 0, 96.57, accuracy: 0.001, "1'36\"57")
        XCTAssertEqual(lino.number, 3)
        XCTAssertEqual(lino.draw, 6)
        XCTAssertEqual(lino.jockey, "G. GUEDJ-GAY")
        XCTAssertNil(lino.distanceVsWinnerM, "El ganador no tiene «Parcouru vs. 1er»")
        XCTAssertEqual(lino.maxSpeedKmh ?? 0, 59.40, accuracy: 0.001)
        XCTAssertEqual(lino.last600S ?? 0, 38.68, accuracy: 0.001)
        XCTAssertEqual(race.winner?.name, "LINO")

        let allie: RaceRunner = try runner(race, "ALLIE SAINT LON")
        XCTAssertEqual(allie.distanceVsWinnerM ?? 0, -0.68, accuracy: 0.001)
        XCTAssertEqual(try runner(race, "MAMAMIA HIPOLYTE").distanceVsWinnerM ?? 0, 4.62, accuracy: 0.001)
    }

    func testParsesZakynaSectors() throws {
        let race: Race = try sample()
        let z: RaceRunner = try runner(race, "ZAKYNA AL ZARAYAN")
        XCTAssertEqual(z.finish, 5)
        XCTAssertEqual(z.officialTimeS ?? 0, 99.99, accuracy: 0.001)
        XCTAssertEqual(z.number, 6)
        XCTAssertEqual(z.draw, 3)
        XCTAssertEqual(z.jockey, "R. DUBORD")
        XCTAssertEqual(z.redk ?? 0, 71.42, accuracy: 0.001)
        XCTAssertEqual(z.fastest200S ?? 0, 13.26, accuracy: 0.001)
        XCTAssertEqual(z.fastestSector, "600m - 400m")
        XCTAssertEqual(z.maxSpeedKmh ?? 0, 55.91, accuracy: 0.001)
        XCTAssertEqual(z.maxSpeedSector, "DEP - 1200m")
        XCTAssertEqual(z.meanSpeedKmh ?? 0, 52.3, accuracy: 0.001)
        XCTAssertEqual(z.last600S ?? 0, 41.68, accuracy: 0.001)
        XCTAssertEqual(z.distanceVsWinnerM ?? 0, 1.54, accuracy: 0.001, "Parcouru vs 1er +1,54 m")

        XCTAssertEqual(z.sectors.count, 7)
        let times: [Double] = [17.80, 13.39, 13.56, 13.54, 13.26, 13.39, 15.02]
        let speeds: [Double] = [49.9, 53.9, 53, 53.8, 55, 53.8, 47.8]
        let strides: [Int] = [37, 31, 30, 32, 30, 30, 32]
        let positions: [Int] = [5, 4, 4, 4, 6, 5, 5]
        let cumulative: [Double] = [17.80, 31.19, 44.76, 58.30, 71.57, 84.97, 99.99]
        for k in 0..<7 {
            let s: RaceSector = z.sectors[k]
            XCTAssertEqual(s.sectorS, times[k], accuracy: 0.001, "Tiempo del tramo \(k)")
            XCTAssertEqual(s.cumulativeS, cumulative[k], accuracy: 0.001, "Acumulado \(k)")
            XCTAssertEqual(s.meanSpeedKmh ?? 0, speeds[k], accuracy: 0.001, "Velocidad \(k)")
            XCTAssertEqual(s.strides, strides[k], "Foulées \(k)")
            XCTAssertEqual(s.position, positions[k], "Posición \(k)")
        }
        XCTAssertEqual(z.sectors.map { $0.label }, ["DEP - 1200m", "1200m - 1000m", "1000m - 800m", "800m - 600m", "600m - 400m", "400m - 200m", "200m - ARR"])
        XCTAssertEqual(z.sectors[0].lengthM, 200, accuracy: 0.001, "Primer tramo = distancia − 1200 m")
        XCTAssertEqual(z.sectors[0].strideLengthM ?? 0, 200.0 / 37.0, accuracy: 0.0001)
        XCTAssertEqual(z.sectors[6].strideLengthM ?? 0, 6.25, accuracy: 0.0001)
    }

    func testEveryRunnerConsistent() throws {
        let race: Race = try sample()
        for r in race.runners {
            XCTAssertEqual(r.sectors.count, 7, r.name)
            let sum: Double = r.sectors.reduce(0) { $0 + $1.sectorS }
            XCTAssertEqual(sum, r.officialTimeS ?? 0, accuracy: 0.06, "Suma de tramos = tiempo oficial (\(r.name))")
            XCTAssertEqual(r.sectors.last?.position, r.finish, "Posición en la meta = llegada (\(r.name))")
        }
    }

    func testRejectsOtherPdfText() {
        XCTAssertThrowsError(try RaceTrackingParser.parse(pages: ["Factura n.º 12", "Total 34,50 €"], sourceFile: "otro.pdf")) { (e: Error) in
            XCTAssertTrue((e as? AvoError)?.message.contains("Formato de carrera no reconocido") ?? false, e.localizedDescription)
        }
        XCTAssertThrowsError(try RaceTrackingParser.parse(pages: ["Statistiques Tracking\nBORDEAUX"], sourceFile: "vacio.pdf"))
    }

    func testCodableRoundTrip() throws {
        var race: Race = try sample()
        race.horseRecordCode = "HORSE_007"
        race.ourRunnerName = "ZAKYNA AL ZARAYAN"
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let back: [Race] = try dec.decode([Race].self, from: try enc.encode([race]))
        XCTAssertEqual(back.first?.runners, race.runners)
        XCTAssertEqual(back.first?.ourRunner?.finish, 5)
    }

    // ---------------------------------------------------------------- matching
    func testHorseMatching() throws {
        XCTAssertTrue(RaceNames.matches("Zakyna", "ZAKYNA AL ZARAYAN"))
        XCTAssertTrue(RaceNames.matches("Zakýna", "ZAKYNA AL ZARAYAN"), "Sin acentos")
        XCTAssertTrue(RaceNames.matches("zakyna al-zarayan", "ZAKYNA AL ZARAYAN"), "Sin puntuación")
        XCTAssertFalse(RaceNames.matches("Zak", "ZAKYNA AL ZARAYAN"), "Por palabras completas")
        XCTAssertFalse(RaceNames.matches("Al Zarayan", "ZAKYNA AL ZARAYAN"), "Prefijo de palabras")
        XCTAssertTrue(RaceNames.matches("Rayo (demo)", "RAYO"), "La palabra DEMO se ignora")
        let race: Race = try sample()
        let c: [Int] = RaceNames.candidates(["Zakyna", "HORSE_001"], race.runners)
        XCTAssertEqual(c.count, 1)
        XCTAssertEqual(race.runners[c[0]].name, "ZAKYNA AL ZARAYAN")
        XCTAssertTrue(RaceNames.candidates(["Rayo"], race.runners).isEmpty)
    }

    // ---------------------------------------------------------------- analysis
    func testAnalysisWithoutTrainings() throws {
        let race: Race = try sample()
        let idx: Int = try XCTUnwrap(race.runners.firstIndex { $0.name == "ZAKYNA AL ZARAYAN" })
        let rep: RaceReport = RaceAnalysis.analyze(race: race, ourIndex: idx, trainings: [])
        XCTAssertEqual(rep.ourFade ?? 0, 47.8 / 55.0, accuracy: 0.001)
        XCTAssertEqual(rep.fieldMedianFade ?? 0, 53.0 / 58.2, accuracy: 0.002, "Mediana del campo ≈ 0,91")
        let loss: Double = try XCTUnwrap(rep.finalLossFieldS)
        XCTAssertTrue(loss > 0.4 && loss < 0.75, "Pérdida en el final \(loss)")
        XCTAssertEqual(rep.groundLossS ?? 0, 1.54 / (47.8 / 3.6), accuracy: 0.001)
        XCTAssertEqual(rep.startLossS ?? 0, 17.80 - 17.56, accuracy: 0.001)
        XCTAssertEqual(rep.predictedPlace, 5)
        XCTAssertEqual(rep.gainedPositions, 0)
        XCTAssertFalse(rep.referenceIsTraining)
        XCTAssertTrue(rep.verdict.lowercased().contains("no habría cambiado el puesto"), rep.verdict)
        XCTAssertTrue(rep.verdict.contains("4.º"), rep.verdict)
        XCTAssertEqual(rep.confidence, .low)
        XCTAssertEqual(rep.trainingSessions, 0)
        XCTAssertEqual(rep.optimizedPositions, 1, "6.º a 400 m → 5.º en la meta")
        XCTAssertTrue(rep.observations.contains { $0.contains("Perdió 2 puestos entre 600 y 400 m") }, rep.observations.joined(separator: "\n"))
        XCTAssertTrue(rep.observations.contains { $0.contains("Zancada al final más corta") }, rep.observations.joined(separator: "\n"))
    }

    func testCounterfactualWithTrainingsGainsPositions() throws {
        let race: Race = try sample()
        let idx: Int = try XCTUnwrap(race.runners.firstIndex { $0.name == "MAMAMIA HIPOLYTE" })
        var works: [TrainingFastWork] = []
        for k in 0..<6 {
            works.append(TrainingFastWork(sessionId: "S\(k)", date: Date(timeIntervalSince1970: 1_790_000_000 + Double(k) * 86_400), t0: 0, t1: 40,
                                          distanceM: 600, peak200Kmh: 50, last200Kmh: 49.5, fade: 0.99))
        }
        let summary = TrainingWorkSummary(sessionId: "S", date: Date(timeIntervalSince1970: 1_790_000_000), isDemo: false, best200Kmh: 50,
                                          best400Kmh: 49.6, best600Kmh: 49.2, works: works)
        let rep: RaceReport = RaceAnalysis.analyze(race: race, ourIndex: idx, trainings: [summary])
        XCTAssertTrue(rep.referenceIsTraining)
        XCTAssertEqual(rep.fastWorks, 6)
        XCTAssertEqual(rep.trainingFade ?? 0, 0.99, accuracy: 0.0001)
        XCTAssertEqual(rep.predictedPlace, 5)
        XCTAssertEqual(rep.gainedPositions, 1)
        XCTAssertTrue(rep.verdict.contains("habría ganado 1 posición"), rep.verdict)
        XCTAssertEqual(rep.confidence, .high)
    }

    func testTrainingWorkAnalyzer() {
        // 0–20 s at 8 m/s, 20–80 s at 14 m/s (50,4 km/h), 80–100 s at 12 m/s (43,2 km/h), then 5 m/s; 10 Hz
        var t: [Double] = []
        var v: [Double] = []
        var d: [Double] = []
        var dist: Double = 0
        var i: Int = 0
        while Double(i) * 0.1 <= 130 {
            let tt: Double = Double(i) * 0.1
            let speed: Double = tt < 20 ? 8 : (tt < 80 ? 14 : (tt < 100 ? 12 : 5))
            if i > 0 { dist += (speed + v[i - 1]) / 2 * 0.1 }
            t.append(tt)
            v.append(speed)
            d.append(dist)
            i += 1
        }
        let b: [Bool] = [Bool](repeating: false, count: t.count)
        let s: TrainingWorkSummary = TrainingWorkAnalyzer.analyze(sessionId: "X", date: nil, isDemo: false, t: t, distance: d, speedMs: v, breaks: b)
        XCTAssertEqual(s.works.count, 1)
        let w: TrainingFastWork = s.works[0]
        XCTAssertEqual(w.distanceM, 14 * 60 + 12 * 20, accuracy: 3)
        XCTAssertEqual(w.peak200Kmh, 50.4, accuracy: 0.1)
        XCTAssertEqual(w.last200Kmh ?? 0, 43.2, accuracy: 0.3)
        XCTAssertEqual(w.fade ?? 0, 43.2 / 50.4, accuracy: 0.01)
        XCTAssertEqual(s.best200Kmh ?? 0, 50.4, accuracy: 0.1)
        XCTAssertEqual(s.best600Kmh ?? 0, 50.4, accuracy: 0.1)
        // a gap splits the work
        var b2: [Bool] = b
        b2[500] = true
        let s2: TrainingWorkSummary = TrainingWorkAnalyzer.analyze(sessionId: "X", date: nil, isDemo: false, t: t, distance: d, speedMs: v, breaks: b2)
        XCTAssertEqual(s2.works.count, 2)
    }
}
