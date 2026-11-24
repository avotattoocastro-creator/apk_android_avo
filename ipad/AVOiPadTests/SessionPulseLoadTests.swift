import XCTest
@testable import AVO_Horse

/// Pulso (bloque `cardio` del motor, ECG de la cincha 0.5.x) en «Parámetros clave» y carga externa CG2 de la sesión
/// (motor 2.0.0-dev34). JSON SINTÉTICO con la forma de equine-intelligence/docs/FORMATO_RESULTADOS.md.
final class SessionPulseLoadTests: XCTestCase {
    static let cardio: String = """
    {"presente":true,"calidad":"BUENA","fc_pico_lpm":221,"fc_max_epoca_lpm":214,"fin_esfuerzo_s":120,
    "recuperacion":[{"min":1,"fc_lpm":160,"caida_lpm":54},{"min":2,"fc_lpm":128,"caida_lpm":86}],
    "epocas":[[110,212,16.1,0],[115,214,15.0,0],[120,205,9.0,0],[125,190,6.0,0]],
    "carga_interna":{"regla":"CG1","validado":false,"trimp":37.4,"cobertura_pct":96.2}}
    """

    private func pulse(_ cardioJson: String) -> [KeyTile] {
        let json: String = "{\"formato\":\"avo-equine-analysis\",\"metricas\":[],\"cardio\":\(cardioJson)}"
        return KeyData.from(json: json).tiles.filter { $0.group == 1 }
    }

    func testPulseTilesFromEngineCardio() {
        let t: [KeyTile] = pulse(Self.cardio)
        func v(_ id: String) -> KeyTile? { t.first { $0.id == id } }
        XCTAssertEqual(t.map { $0.id }, ["hrmax", "rec2", "hrend", "trimp"])
        XCTAssertEqual(v("hrmax")?.value, "214")          // máxima por épocas de 5 s, no el pico de un latido
        XCTAssertEqual(v("hrmax")?.caption, "ECG buena")
        XCTAssertEqual(v("rec2")?.value, "128")
        XCTAssertEqual(v("rec2")?.caption, "Baja 86 lpm en 2 min")
        XCTAssertEqual(v("hrend")?.value, "205")          // época que contiene fin_esfuerzo_s = 120
        XCTAssertEqual(v("trimp")?.value, "37")
        XCTAssertEqual(v("trimp")?.unit, "UA")
        XCTAssertTrue(v("trimp")?.caption.contains("sin validar") ?? false)
        XCTAssertTrue(t.allSatisfy { $0.available })
    }

    func testPulseWithoutOrUnusableEcgStaysEmpty() {
        let none: [KeyTile] = pulse(#"{"presente":false,"version":"1.1.0"}"#)
        XCTAssertTrue(none.allSatisfy { !$0.available && $0.value == "—" && $0.caption == KeyData.ecgCaption })
        let bad: [KeyTile] = pulse(#"{"presente":true,"calidad":"NO_UTILIZABLE","fc_max_epoca_lpm":250}"#)
        XCTAssertTrue(bad.allSatisfy { !$0.available && $0.value == "—" })
        XCTAssertEqual(bad.first?.caption, "ECG de la cincha no utilizable")
    }

    func testExternalLoadBandsOfTheSession() throws {
        let o: [String: Any] = try EngineJSON.root(#"""
            {"base":"AVO_KB_1","version":"1.30.0","v_carrera_m_s":16.7,"bandas":[],
             "carga_externa":{"regla":"CG2","escala":"ABSOLUTAS_PSI","v_rapido_m_s":13.3,"rapido_m":1450,
              "bandas":[{"banda":"LENTO","v_min":0,"v_max":10,"distancia_m":2100,"tiempo_s":420},
                        {"banda":"MEDIO","v_min":10,"v_max":13.3,"distancia_m":900,"tiempo_s":75},
                        {"banda":"RAPIDO_1","v_min":13.3,"v_max":14.4,"distancia_m":400,"tiempo_s":29},
                        {"banda":"RAPIDO_2","v_min":14.4,"v_max":15.5,"distancia_m":450,"tiempo_s":30},
                        {"banda":"RAPIDO_3","v_min":15.5,"v_max":16.8,"distancia_m":600,"tiempo_s":37},
                        {"banda":"RAPIDO_4","v_min":16.8,"v_max":null,"distancia_m":0,"tiempo_s":0}]}}
            """#)
        let kb: KbSessionBlock = KbSessionBlock(o)
        XCTAssertTrue(kb.cgPresent)
        XCTAssertEqual(kb.cgScale, "ABSOLUTAS_PSI")
        XCTAssertEqual(kb.cgBands.map { $0.code }, ["LENTO", "MEDIO", "RAPIDO_1", "RAPIDO_2", "RAPIDO_3", "RAPIDO_4"])
        XCTAssertEqual(kb.cgFastM ?? -1, 1450, accuracy: 1e-9)
        XCTAssertEqual(kb.cgFastSpeed ?? -1, 13.3, accuracy: 1e-9)
        XCTAssertNil(kb.cgBands[5].vMax)
        XCTAssertEqual(TrainingLoadCg.bandTitle(kb.cgBands[2].code), "Rápido 1")
        // un análisis anterior a dev34 no trae carga_externa
        XCTAssertFalse(KbSessionBlock(try EngineJSON.root(#"{"base":"AVO_KB_1","version":"1.24.0","bandas":[]}"#)).cgPresent)
    }
}
