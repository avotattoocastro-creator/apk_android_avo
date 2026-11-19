import XCTest
@testable import AVO_Horse

/// «Análisis motor» of a race (Core/RaceDeepEngine.swift): phases, rivals and head to head, earlier races (distance,
/// state of the track, hippodrome) and the state of the track stored in carreras.json. Synthetic races built in code.
final class RaceDeepEngineTests: XCTestCase {
    /// Runner with 4 sectors of 200 m (800 m race) and the given sector times.
    private func runner(_ name: String, _ times: [Double], finish: Int, redk: Double? = nil, ground: Double? = nil) -> RaceRunner {
        var cum: Double = 0
        var sectors: [RaceSector] = []
        for (k, t) in times.enumerated() {
            cum += t
            sectors.append(RaceSector(label: "S\(k)", fromM: Double(k) * 200, toM: Double(k + 1) * 200, cumulativeS: cum, sectorS: t,
                                      meanSpeedKmh: 200 / t * 3.6, strides: 30, position: nil))
        }
        return RaceRunner(number: finish, draw: finish, name: name, jockey: "J. \(name)", finish: finish, officialTimeS: cum,
                          maxSpeedKmh: nil, maxSpeedSector: "", fastest200S: times.min(), fastestSector: "", last600S: nil,
                          distanceVsWinnerM: ground, meanSpeedKmh: nil, redk: redk, sectors: sectors)
    }

    private func race(_ id: String, day: Int, distance: Double = 800, hippodrome: String = "PAU", going: RaceGoing? = nil,
                      runners: [RaceRunner], ours: String = "ZAKYNA", code: String = "ZAK") -> Race {
        var rs: [RaceRunner] = runners
        // positions per sector = order of the cumulative times
        for k in 0..<rs[0].sectors.count {
            let order: [Int] = rs.indices.sorted { rs[$0].sectors[k].cumulativeS < rs[$1].sectors[k].cumulativeS }
            for (p, i) in order.enumerated() { rs[i].sectors[k].position = p + 1 }
        }
        let date: Date = Date(timeIntervalSince1970: 1_790_000_000 + Double(day) * 86_400)
        return Race(id: id, hippodrome: hippodrome, raceName: "PRIX \(id)", category: "C2", distanceM: distance, date: date,
                    winnerRedk: nil, sourceFile: "", runners: rs, horseRecordCode: code, horseName: "Zakyna", ourRunnerName: ours,
                    importedAt: date, notes: "", isDemo: false, going: going?.rawValue)
    }

    /// Today: we finish 2.º, losing the race in the final.
    private func today(going: RaceGoing? = .goodToSoft) -> Race {
        race("HOY", day: 30, going: going, runners: [
            runner("AGANDJIR", [13.0, 12.6, 12.4, 12.5], finish: 1, redk: 63.1),
            runner("ZAKYNA", [12.8, 12.5, 12.6, 13.2], finish: 2, redk: 63.9, ground: 6),
            runner("CHAKIFA", [13.1, 12.7, 12.7, 12.9], finish: 3),
        ])
    }

    func testPhasesAndHeadline() throws {
        let r: Race = today()
        let rep: RaceDeepReport = RaceDeepEngine.analyze(race: r, ourIndex: try XCTUnwrap(r.ourIndex), allRaces: [r], report: nil)
        XCTAssertEqual(rep.phases.map { $0.name }, ["Salida", "Desarrollo", "Final"])
        let start: RaceDeepPhase = rep.phases[0]
        XCTAssertEqual(start.timeRank, 1, "fue el más rápido en la salida")
        let final: RaceDeepPhase = rep.phases[2]
        XCTAssertEqual(final.timeRank, 3)
        XCTAssertEqual(final.lostVsWinnerS ?? 0, (12.6 + 13.2) - (12.4 + 12.5), accuracy: 1e-9)
        XCTAssertTrue(rep.headline.hasPrefix("Terminó 2.º de 3"), rep.headline)
        XCTAssertTrue(rep.headline.contains("final"), rep.headline)
        XCTAssertEqual(rep.sectors.count, 4)
        XCTAssertEqual(rep.sectors[0].gapToLeaderS ?? -1, 0, accuracy: 1e-9)
        XCTAssertTrue(rep.conclusions.contains { $0.contains("Recorrió 6") }, "terreno de más")
        XCTAssertTrue(rep.nextTime.contains { $0.contains("final") })
    }

    func testHeadToHeadAndHistory() throws {
        let earlier: Race = race("ANT", day: 10, going: .soft, runners: [
            runner("ZAKYNA", [12.9, 12.6, 12.5, 12.6], finish: 1, redk: 63.5),
            runner("AGANDJIR", [13.0, 12.7, 12.6, 12.7], finish: 2),
        ])
        let longer: Race = race("LARGA", day: 20, distance: 1600, hippodrome: "BORDEAUX", runners: [
            runner("OTRO", [13.0, 12.7, 12.6, 12.7], finish: 1),
            runner("ZAKYNA", [13.1, 12.8, 12.9, 13.0], finish: 2),
        ])
        let other: Race = race("SIN", day: 15, runners: [
            runner("CHAKIFA", [13.0, 12.7, 12.6, 12.7], finish: 4),
            runner("X", [12.0, 12.0, 12.0, 12.0], finish: 1),
        ], ours: "X", code: "OTRO")
        let future: Race = race("FUT", day: 40, runners: [runner("ZAKYNA", [12, 12, 12, 12], finish: 1)])
        let r: Race = today()
        let all: [Race] = [earlier, longer, other, future, r]
        let rep: RaceDeepReport = RaceDeepEngine.analyze(race: r, ourIndex: try XCTUnwrap(r.ourIndex), allRaces: all, report: nil)

        let ag: RaceRival = try XCTUnwrap(rep.rivals.first { $0.name == "AGANDJIR" })
        XCTAssertEqual(ag.meetings, 1)
        XCTAssertEqual(ag.beatenByUs, 1)
        XCTAssertEqual(ag.beatUs, 0)
        XCTAssertTrue(rep.rivalsText.contains("AGANDJIR"), rep.rivalsText)
        let ch: RaceRival = try XCTUnwrap(rep.rivals.first { $0.name == "CHAKIFA" })
        XCTAssertEqual(ch.meetings, 0)
        XCTAssertEqual(ch.runs.count, 1, "carrera de CHAKIFA sin nuestro caballo")

        XCTAssertEqual(rep.history.map { $0.raceId }, ["ANT", "LARGA", "HOY"], "sin carreras posteriores")
        XCTAssertTrue(rep.history[0].sameDistance)
        XCTAssertFalse(rep.history[1].sameDistance)
        XCTAssertFalse(rep.history[0].sameGoing, "souple (blando) y bon souple (bueno) no son el mismo grupo")
        XCTAssertEqual(rep.history[0].going, .soft)
        XCTAssertTrue(rep.distanceText.contains("1.º/2"), rep.distanceText)
        XCTAssertTrue(rep.hippodromeText.contains("PAU"), rep.hippodromeText)
    }

    func testGoingGroupsAndMissingGoing() throws {
        XCTAssertEqual(RaceGoing.good.group, "bueno")
        XCTAssertEqual(RaceGoing.goodToSoft.group, "bueno")
        XCTAssertEqual(RaceGoing.soft.group, "blando")
        XCTAssertEqual(RaceGoing.veryHeavy.group, "pesado")
        XCTAssertEqual(RaceGoing.allCases.count, 10)
        let r: Race = today(going: nil)
        let rep: RaceDeepReport = RaceDeepEngine.analyze(race: r, ourIndex: try XCTUnwrap(r.ourIndex), allRaces: [r], report: nil)
        XCTAssertTrue(rep.goingText.contains("Falta el estado de la pista"))
        XCTAssertTrue(rep.distanceText.contains("No hay carreras anteriores"))
        XCTAssertEqual(rep.confidence, .low)
    }

    func testWinnerHeadline() throws {
        let r: Race = race("GAN", day: 5, runners: [
            runner("ZAKYNA", [12.8, 12.5, 12.4, 12.5], finish: 1),
            runner("B", [12.9, 12.6, 12.6, 12.8], finish: 2),
        ])
        let rep: RaceDeepReport = RaceDeepEngine.analyze(race: r, ourIndex: try XCTUnwrap(r.ourIndex), allRaces: [r], report: nil)
        XCTAssertTrue(rep.headline.hasPrefix("Ganó la carrera por 0,70 s"), rep.headline)
        XCTAssertNil(rep.phases[0].lostVsWinnerS)
    }

    /// carreras.json of earlier builds (without «going») still loads, and the new field round-trips.
    func testGoingCodableCompatibility() throws {
        var r: Race = today(going: nil)
        let enc: JSONEncoder = JSONEncoder()
        var obj: [String: Any] = try XCTUnwrap(JSONSerialization.jsonObject(with: try enc.encode(r)) as? [String: Any])
        obj.removeValue(forKey: "going")
        let old: Data = try JSONSerialization.data(withJSONObject: obj)
        XCTAssertNil(try JSONDecoder().decode(Race.self, from: old).going)
        r.going = RaceGoing.heavy.rawValue
        let back: Race = try JSONDecoder().decode(Race.self, from: try enc.encode(r))
        XCTAssertEqual(back.goingValue, .heavy)
    }
}
