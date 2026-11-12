import XCTest
@testable import AVO_Horse

/// Asistente IA: compactación del JSON del motor que se manda a Claude, coste estimado, forma de la clave y contexto
/// con la sesión de DEMOSTRACIÓN. No llama a la API (en CI no hay clave).
final class AssistantTests: XCTestCase {
    private func parse(_ s: String) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }

    func testCompactDropsSeriesAndSummarisesLongLists() throws {
        let numbers: String = (0..<100).map { String(Double($0) + 0.123456) }.joined(separator: ",")
        let objects: String = (0..<50).map { "{\"i\":\($0)}" }.joined(separator: ",")
        let json: String = "{\"series\":{\"t\":[1,2,3]},\"v\":12.3456789,\"ok\":true,\"n\":7,"
            + "\"lista\":[\(numbers)],\"objs\":[\(objects)],\"corta\":[1.11111,2]}"
        let o: [String: Any] = try parse(AssistantJSON.compact(json))
        XCTAssertNil(o["series"])
        XCTAssertEqual(o["v"] as? Double, 12.346)
        XCTAssertEqual(o["ok"] as? Bool, true)
        XCTAssertEqual(o["n"] as? Int, 7)
        let lista = try XCTUnwrap((o["lista"] as? [String: Any])?["_lista_resumida"] as? [String: Any])
        XCTAssertEqual(lista["n"] as? Int, 100)
        XCTAssertEqual(lista["min"] as? Double, 0.123)
        let objs = try XCTUnwrap(o["objs"] as? [Any])
        XCTAssertEqual(objs.count, 24)
        let omitted = try XCTUnwrap(objs.first { ($0 as? [String: Any])?["_omitidos"] != nil } as? [String: Any])
        XCTAssertEqual(omitted["_omitidos"] as? Int, 50 - 23)
        XCTAssertEqual((o["corta"] as? [Any])?.count, 2)
    }

    func testInvalidJsonGivesEmptyText() {
        XCTAssertEqual(AssistantJSON.compact("no es json"), "")
    }

    func testCostEstimate() {
        let u = ClaudeUsage(input: 1_000_000, output: 100_000, cacheWrite: 0, cacheRead: 0)
        XCTAssertEqual(u.costUSD(.sonnet), 3.0, accuracy: 1e-9)
        XCTAssertEqual(u.costUSD(.haiku), 0.15, accuracy: 1e-9)
        XCTAssertEqual(u.totalTokens, 1_100_000)
    }

    func testKeyShape() {
        XCTAssertFalse(ClaudeClient.looksLikeKey("hola"))
        XCTAssertFalse(ClaudeClient.looksLikeKey("sk-ant- con espacios y bastante larga para pasar el tamaño"))
        XCTAssertTrue(ClaudeClient.looksLikeKey("  sk-ant-api03-" + String(repeating: "a", count: 40) + "\n"))
    }

    func testErrorMessages() {
        XCTAssertTrue(ClaudeError.from(status: 401, body: Data()).message.contains("clave"))
        let credit = Data(#"{"type":"error","error":{"type":"invalid_request_error","message":"Your credit balance is too low"}}"#.utf8)
        XCTAssertTrue(ClaudeError.from(status: 400, body: credit).message.contains("créditos"))
    }

    func testStreamUsageMerge() {
        var u = ClaudeClient.usage(["input_tokens": 1200, "cache_creation_input_tokens": 30000, "cache_read_input_tokens": 0, "output_tokens": 1],
                                   into: ClaudeUsage())
        u = ClaudeClient.usage(["output_tokens": 640], into: u)
        XCTAssertEqual(u.input, 1200)
        XCTAssertEqual(u.cacheWrite, 30000)
        XCTAssertEqual(u.output, 640)
    }
}
