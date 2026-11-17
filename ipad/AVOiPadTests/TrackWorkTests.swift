import XCTest
@testable import AVO_Horse

/// AVO Track Work 1.0.0 («trabajo_pista»): decoding of the whole block (JSON produced by the real engine for the
/// synthetic sessions of equine-intelligence/tests/test_racing.cpp: «race_session_psi» with girth and an injected impact,
/// and «course_lines_like_laredo» with start / finish lines), the real engine on the bundled DEMO session with raza PSI,
/// and the alignment of training splits with the 200 m sectors of a race. SYNTHETIC data only.
final class TrackWorkTests: XCTestCase {
    /// racing_json of race_session(140 s, BNO085 units, impact at 50 s) with the PSI profile (stride list trimmed to 4).
    static let raceJson: String = #"""
        {"modulo":"AVO_TRACK_WORK","version":"1.0.0","perfil":{"raza":"PSI","v_trabajo":11,"v_rapido":14.5,"v_alta":15,"v_referencia":[14,16],"frecuencia_zancada_hz":[1.6,
        2.9],"longitud_zancada_m":[3,9],"parcial_m":200},"cincha":{"disponible":true,"escala":"BNO085","lsb_por_g":2510.5,"calidad_vertical":0.991118,"sentido_avance_confirmado":true,
        "segundos":136,"vedba_media_g":0.542248,"carga_vedba_g_min":1.21637,"vedba_por_aire_g":{"PASO":0.0724764,"TROTE":0.402914,"GALOPE":0.757466},"giros":{"izquierda_s":14.656,
        "derecha_s":10.032,"izquierda_grados":70.8932,"derecha_grados":84.5369,"equilibrio":0.187297},"giros_por_aire":{"PASO":{"izquierda_s":0,"derecha_s":0,"izquierda_grados":0,
        "derecha_grados":0,"equilibrio":null},"TROTE":{"izquierda_s":0,"derecha_s":0,"izquierda_grados":0,"derecha_grados":0,"equilibrio":null},"GALOPE":{"izquierda_s":14.656,
        "derecha_s":10.032,"izquierda_grados":70.8932,"derecha_grados":84.5369,"equilibrio":0.187297}},"muestras_saturadas":0,"fuente":"IMU_HORSE_FRAME_V1"},"zancadas":{"algoritmo":"STRIDE_V1",
        "n":195,"frecuencia_mediana_hz":2.35849,"longitud_mediana_m":6.62612,"desplazamiento_vertical_mediano_m":0.0915428,"pico_vertical_mediano_g":1.09208,"lista":[{"t0":13.1625,
        "t1":13.6345,"f_hz":2.11864,"v":9.00747,"l_m":4.25153,"pico_v_g":0.9321,"desp_v_m":0.0942788,"vedba_g":0.692085,"rasgo_lateral":-0.946707,"giro_deg_s":-0.110928,
        "mano":"DERECHA","curva":false},{"t0":33.0017,"t1":33.4497,"f_hz":2.23214,"v":11.6055,"l_m":5.19928,"pico_v_g":1.02332,"desp_v_m":0.0917623,"vedba_g":0.740207,
        "rasgo_lateral":0.732522,"giro_deg_s":0.0699574,"mano":"IZQUIERDA","curva":false},{"t0":33.4497,"t1":33.8977,"f_hz":2.23214,"v":11.9628,"l_m":5.35935,"pico_v_g":1.00646,
        "desp_v_m":0.092774,"vedba_g":0.751363,"rasgo_lateral":0.73385,"giro_deg_s":-0.0129871,"mano":"IZQUIERDA","curva":false},{"t0":33.8977,"t1":34.3457,"f_hz":2.23214,
        "v":12.2883,"l_m":5.50514,"pico_v_g":1.02702,"desp_v_m":0.0945697,"vedba_g":0.760995,"rasgo_lateral":0.745091,"giro_deg_s":-0.024486,"mano":"IZQUIERDA",
        "curva":false}]},"mano":{"algoritmo":"LEAD_V1","experimental":true,"calibracion":"CURVAS","signo":1,"acuerdo_curvas":1,"zancadas_izquierda":77,"zancadas_derecha":115,
        "cambios":2,"mano_de_fuera_en_curva_pct":0},"trabajos":{"algoritmo":"EFFORT_V1","distancia_galope_trabajo_m":902.531,"distancia_rapida_m":797.095,"v_max":17.0353,
        "mejor_200m_s":11.778,"lista":[{"id":1,"tipo":"TRABAJO_RAPIDO","t0":32.6,"t1":89.1,"duracion_s":56.5,"distancia_m":901.428,"v_media":15.9545,"v_max":17.0353,
        "t_hasta_v_max_s":34,"distancia_90_pct_m":704.792,"aceleracion_max":0.878325,"ultimos_200m_s":13.7638,"ultimos_400m_s":25.6812,"v_ultimos_200m":14.5309,
        "v_ultimos_400m":15.5756,"indice_caida_pct":14.7012,"parciales":[{"desde_m":0,"hasta_m":200,"tiempo_s":13.0675,"v":15.3051},{"desde_m":200,"hasta_m":400,
        "tiempo_s":11.7782,"v":16.9806},{"desde_m":400,"hasta_m":600,"tiempo_s":11.778,"v":16.9809},{"desde_m":600,"hasta_m":800,"tiempo_s":12.4452,"v":16.0705},
        {"desde_m":800,"hasta_m":901.428,"tiempo_s":7.43118,"v":13.649}],"mejores":[{"distancia_m":200,"tiempo_s":11.778,"t0":58.2},{"distancia_m":400,"tiempo_s":23.5561,
        "t0":46.4},{"distancia_m":600,"tiempo_s":35.455,"t0":39.1},{"distancia_m":800,"tiempo_s":48.5022,"t0":36.7}],"zancadas":135,"f_en_v_max_hz":2.45098,"l_en_v_max_m":6.94766,
        "f_max_hz":2.45098,"l_max_m":7.07898,"ajuste_f":{"a":1.75713,"b":0.0395654,"r":0.939735},"ajuste_l":{"a":1.5488,"b":0.320835},"referencia":[{"v":14,"f_hz":2.31105,
        "l_m":6.0405},{"v":16,"f_hz":2.39018,"l_m":6.68217}],"mano":{"izquierda":71,"derecha":64,"cambios":1},"recuperacion_hasta_paso_s":5.9,"pausa_hasta_siguiente_s":null,
        "v_media_pausa":null,"manual":false}]},"recorrido":null,"correcciones_manuales":false,"fases":{"base":"VELOCIDAD","calentamiento":{"t0":0,"t1":32.6,"duracion_s":32.6,
        "distancia_m":240.825,"parado_s":0,"paso_s":0,"trote_s":9.99959,"galope_s":19.6055},"trabajo":{"t0":32.6,"t1":89.1,"duracion_s":56.5,"distancia_m":901.428,
        "parado_s":0,"paso_s":0,"trote_s":0,"galope_s":56.5},"vuelta_a_la_calma":{"t0":89.1,"t1":139.9,"duracion_s":50.8,"distancia_m":121.909,"parado_s":0,"paso_s":33.9986,
        "trote_s":0,"galope_s":9.89103},"algoritmo":"SESSION_PHASES_V1"},"series":{"repeticiones":1,"rapidas":1,"caida_v_max_pct":null,"caida_zancada_pct":null,
        "recuperacion_media_s":5.9,"calentamiento_corto":true},"eventos":[{"tipo":"CAMBIO_DE_MANO","t":29.7458,"valor":1,"detalle":"a mano izquierda"},{"tipo":"IMPACTO_ATIPICO",
        "t":49.785,"valor":3.95547,"detalle":"pico vertical 3.96 g (habitual 1.09 g)"},{"tipo":"CAMBIO_DE_MANO","t":62.1285,"valor":-1,"detalle":"a mano derecha"}],
        "avisos":["calentamiento de 1 min antes del primer trabajo rápido (referencia 10 min)"],"nota":"entrenamiento de caballos de carreras; exploratorio, sin validar con caballos reales; perfiles de raza = valores de partida"}
        """#

    /// racing_json of the Laredo-like course (warm-up the other way, gallop SALIDA → META 1200 m) with the PSI profile.
    static let courseJson: String = #"""
        {"modulo":"AVO_TRACK_WORK","version":"1.0.0","perfil":{"raza":"PSI","v_trabajo":11,"v_rapido":14.5,"v_alta":15,"v_referencia":[14,16],"frecuencia_zancada_hz":[1.6,
        2.9],"longitud_zancada_m":[3,9],"parcial_m":200},"cincha":{"disponible":false,"escala":"SIN_CINCHA","lsb_por_g":null,"calidad_vertical":null,"sentido_avance_confirmado":false,
        "segundos":0,"vedba_media_g":null,"carga_vedba_g_min":null,"vedba_por_aire_g":{"PASO":null,"TROTE":null,"GALOPE":null},"giros":{"izquierda_s":0,"derecha_s":0,
        "izquierda_grados":0,"derecha_grados":0,"equilibrio":null},"giros_por_aire":{"PASO":{"izquierda_s":0,"derecha_s":0,"izquierda_grados":0,"derecha_grados":0,
        "equilibrio":null},"TROTE":{"izquierda_s":0,"derecha_s":0,"izquierda_grados":0,"derecha_grados":0,"equilibrio":null},"GALOPE":{"izquierda_s":0,"derecha_s":0,
        "izquierda_grados":0,"derecha_grados":0,"equilibrio":null}},"muestras_saturadas":0,"fuente":"IMU_HORSE_FRAME_V1"},"zancadas":{"algoritmo":"STRIDE_V1","n":0,
        "frecuencia_mediana_hz":null,"longitud_mediana_m":null,"desplazamiento_vertical_mediano_m":null,"pico_vertical_mediano_g":null,"lista":[]},"mano":{"algoritmo":"LEAD_V1",
        "experimental":true,"calibracion":"","signo":0,"acuerdo_curvas":null,"zancadas_izquierda":0,"zancadas_derecha":0,"cambios":0,"mano_de_fuera_en_curva_pct":null},
        "trabajos":{"algoritmo":"EFFORT_V1","distancia_galope_trabajo_m":1372.82,"distancia_rapida_m":1309.09,"v_max":16,"mejor_200m_s":12.514,"lista":[{"id":1,
        "tipo":"TRABAJO_RAPIDO","t0":366.6,"t1":453.4,"duracion_s":86.8,"distancia_m":1370.61,"v_media":15.7905,"v_max":16,"t_hasta_v_max_s":3.4,"distancia_90_pct_m":1311.98,
        "aceleracion_max":1.44,"ultimos_200m_s":13.0342,"ultimos_400m_s":25.5483,"v_ultimos_200m":15.3442,"v_ultimos_400m":15.6566,"indice_caida_pct":4.09876,"parciales":[{"desde_m":0,
        "hasta_m":200,"tiempo_s":13.0342,"v":15.3442},{"desde_m":200,"hasta_m":400,"tiempo_s":12.514,"v":15.982},{"desde_m":400,"hasta_m":600,"tiempo_s":12.514,
        "v":15.982},{"desde_m":600,"hasta_m":800,"tiempo_s":12.514,"v":15.982},{"desde_m":800,"hasta_m":1000,"tiempo_s":12.514,"v":15.982},{"desde_m":1000,"hasta_m":1200,
        "tiempo_s":12.514,"v":15.982},{"desde_m":1200,"hasta_m":1370.61,"tiempo_s":11.1955,"v":15.2394}],"mejores":[{"distancia_m":200,"tiempo_s":12.514,"t0":428.1},
        {"distancia_m":400,"tiempo_s":25.0281,"t0":413.4},{"distancia_m":600,"tiempo_s":37.5421,"t0":371.6},{"distancia_m":800,"tiempo_s":50.0562,"t0":388.4},{"distancia_m":1000,
        "tiempo_s":62.5702,"t0":375.8},{"distancia_m":1200,"tiempo_s":75.0843,"t0":373.7}],"zancadas":0,"f_en_v_max_hz":null,"l_en_v_max_m":null,"f_max_hz":null,
        "l_max_m":null,"ajuste_f":{"a":null,"b":null,"r":null},"ajuste_l":{"a":null,"b":null},"referencia":[{"v":14,"f_hz":null,"l_m":null},{"v":16,"f_hz":null,
        "l_m":null}],"mano":{"izquierda":0,"derecha":0,"cambios":0},"recuperacion_hasta_paso_s":6.2,"pausa_hasta_siguiente_s":null,"v_media_pausa":null,"manual":false}]},
        "recorrido":{"nombre":"Regaton","distancia_salida_meta_m":1200,"dentro_geocerca_pct":null,"mejor_pasada_s":75.0788,"cruces":[{"linea":"SALIDA","t":311.401,
        "sentido":"IZQ_A_DCHA","cuenta":false},{"linea":"SALIDA","t":368.677,"sentido":"DCHA_A_IZQ","cuenta":true},{"linea":"META","t":443.756,"sentido":"DCHA_A_IZQ",
        "cuenta":true},{"linea":"META","t":617.441,"sentido":"IZQ_A_DCHA","cuenta":false}],"pasadas":[{"id":1,"tipo":"PASADA","t0":368.677,"t1":443.756,"duracion_s":75.0788,
        "distancia_m":1198.65,"v_media":15.9653,"v_max":16,"t_hasta_v_max_s":1.32289,"distancia_90_pct_m":1195.48,"aceleracion_max":1.44,"ultimos_200m_s":12.514,
        "ultimos_400m_s":25.0281,"v_ultimos_200m":15.982,"v_ultimos_400m":15.982,"indice_caida_pct":0.112217,"parciales":[{"desde_m":0,"hasta_m":200,"tiempo_s":12.5929,
        "v":15.882},{"desde_m":200,"hasta_m":400,"tiempo_s":12.514,"v":15.982},{"desde_m":400,"hasta_m":600,"tiempo_s":12.514,"v":15.982},{"desde_m":600,"hasta_m":800,
        "tiempo_s":12.514,"v":15.982},{"desde_m":800,"hasta_m":1000,"tiempo_s":12.514,"v":15.982},{"desde_m":1000,"hasta_m":1198.65,"tiempo_s":12.4298,"v":15.982}],
        "mejores":[{"distancia_m":200,"tiempo_s":12.514,"t0":428.1},{"distancia_m":400,"tiempo_s":25.0281,"t0":413.4},{"distancia_m":600,"tiempo_s":37.5421,"t0":371.6},
        {"distancia_m":800,"tiempo_s":50.0562,"t0":388.4},{"distancia_m":1000,"tiempo_s":62.5702,"t0":375.8}],"zancadas":0,"f_en_v_max_hz":null,"l_en_v_max_m":null,
        "f_max_hz":null,"l_max_m":null,"ajuste_f":{"a":null,"b":null,"r":null},"ajuste_l":{"a":null,"b":null},"referencia":[{"v":14,"f_hz":null,"l_m":null},{"v":16,
        "f_hz":null,"l_m":null}],"mano":{"izquierda":0,"derecha":0,"cambios":0},"recuperacion_hasta_paso_s":15.8441,"pausa_hasta_siguiente_s":null,"v_media_pausa":null,
        "manual":false}]},"correcciones_manuales":false,"fases":{"base":"LINEAS","calentamiento":{"t0":0,"t1":368.677,"duracion_s":368.677,"distancia_m":1098.96,
        "parado_s":0,"paso_s":126,"trote_s":240,"galope_s":2.67711},"trabajo":{"t0":368.677,"t1":443.756,"duracion_s":75.0788,"distancia_m":1198.65,"parado_s":0,
        "paso_s":0,"trote_s":0,"galope_s":75.0788},"vuelta_a_la_calma":{"t0":443.756,"t1":809.9,"duracion_s":366.144,"distancia_m":746.906,"parado_s":0,"paso_s":346,
        "trote_s":0,"galope_s":18.2441},"algoritmo":"SESSION_PHASES_V1"},"series":{"repeticiones":1,"rapidas":1,"caida_v_max_pct":null,"caida_zancada_pct":null,
        "recuperacion_media_s":6.2,"calentamiento_corto":true},"eventos":[],"avisos":["sin datos de cincha: solo análisis GNSS de los trabajos","calentamiento de 6 min antes del primer trabajo rápido (referencia 10 min)"],
        "nota":"entrenamiento de caballos de carreras; exploratorio, sin validar con caballos reales; perfiles de raza = valores de partida"}
        """#

    private func block(_ json: String) throws -> TrackWorkResult {
        let o: [String: Any]? = AvoJSON.object(Data(json.utf8))
        XCTAssertNotNil(o, "JSON de prueba válido")
        return TrackWorkResult.parse(o)
    }

    // MARK: - decoding of the whole block

    func testParseFullBlockWithGirth() throws {
        let tw: TrackWorkResult = try block(TrackWorkTests.raceJson)
        XCTAssertTrue(tw.present)
        XCTAssertEqual(tw.module, "AVO_TRACK_WORK")
        XCTAssertEqual(tw.version, "1.0.0")
        // profile
        XCTAssertEqual(tw.breed, "PSI")
        XCTAssertEqual(tw.profile.fastSpeed ?? 0, 14.5, accuracy: 1e-9)
        XCTAssertEqual(tw.profile.referenceSpeeds, [14, 16])
        XCTAssertEqual(tw.splitBasisM, 200, accuracy: 1e-9)
        XCTAssertFalse(tw.profile.isFurlong)
        // girth: VeDBA, turning per hand, saturation
        XCTAssertTrue(tw.hasGirth)
        XCTAssertEqual(tw.girth.scale, "BNO085")
        XCTAssertEqual(tw.girth.vedbaGallopG ?? 0, 0.757466, accuracy: 1e-6)
        XCTAssertEqual(tw.girth.vedbaLoadGmin ?? 0, 1.21637, accuracy: 1e-6)
        XCTAssertEqual(tw.girth.turns.leftDeg ?? 0, 70.8932, accuracy: 1e-4)
        XCTAssertEqual(tw.girth.turns.rightS ?? 0, 10.032, accuracy: 1e-4)
        XCTAssertNil(tw.girth.turnsWalk.balance, "equilibrio null → nil")
        XCTAssertEqual(tw.girth.saturatedSamples, 0)
        // strides and lead (experimental)
        XCTAssertEqual(tw.strides.count, 195)
        XCTAssertEqual(tw.strides.list.count, 4)
        XCTAssertEqual(tw.strides.within(32.6, 89.1).count, 3, "Zancadas dentro del trabajo")
        XCTAssertEqual(tw.strides.list.first?.lead, "DERECHA")
        XCTAssertEqual(tw.lead.calibration, "CURVAS")
        XCTAssertEqual(tw.lead.changes, 2)
        XCTAssertEqual(tw.lead.outsideInCurvePct ?? -1, 0, accuracy: 1e-9)
        XCTAssertTrue(tw.lead.experimental)
        // effort with splits, best distances, stride at vmax and at the reference speeds
        XCTAssertEqual(tw.efforts.count, 1)
        let e: TrackWorkEffort = try XCTUnwrap(tw.efforts.first)
        XCTAssertEqual(e.key, "T1")
        XCTAssertEqual(e.kind, "TRABAJO_RAPIDO")
        XCTAssertEqual(e.vmax, 17.0353, accuracy: 1e-4)
        XCTAssertEqual(e.tToVmaxS ?? 0, 34, accuracy: 1e-9)
        XCTAssertEqual(e.distAbove90M ?? 0, 704.792, accuracy: 1e-3)
        XCTAssertEqual(e.last200S, 13.7638, accuracy: 1e-4)
        XCTAssertEqual(e.last400S ?? 0, 25.6812, accuracy: 1e-4)
        XCTAssertEqual(e.fatiguePct, 14.7012, accuracy: 1e-4)
        XCTAssertEqual(e.splits.count, 5)
        XCTAssertEqual(e.sectionals.count, 5, "Nombre antiguo (tiempos por parcial) se mantiene")
        XCTAssertTrue(e.splits[0].isFull(200))
        XCTAssertFalse(e.splits[4].isFull(200), "Último parcial (800–901 m) más corto")
        XCTAssertEqual(e.fullSplits(200).count, 4)
        XCTAssertEqual(e.splits[2].cumulativeS ?? 0, 13.0675 + 11.7782 + 11.778, accuracy: 1e-6)
        XCTAssertEqual(e.splits[1].speedKmh ?? 0, 16.9806 * 3.6, accuracy: 1e-6)
        XCTAssertEqual(e.best.map { $0.distanceM }, [200, 400, 600, 800])
        XCTAssertEqual(e.best[0].timeS, 11.778, accuracy: 1e-6)
        XCTAssertEqual(e.best[0].t0 ?? 0, 58.2, accuracy: 1e-6)
        XCTAssertEqual(e.freqAtVmaxHz ?? 0, 2.45098, accuracy: 1e-5)
        XCTAssertEqual(e.lengthAtVmaxM ?? 0, 6.94766, accuracy: 1e-5)
        XCTAssertEqual(e.freqFitB ?? 0, 0.0395654, accuracy: 1e-7)
        XCTAssertEqual(e.references.count, 2)
        XCTAssertEqual(e.references[1].speed ?? 0, 16, accuracy: 1e-9)
        XCTAssertEqual(e.references[1].freqHz ?? 0, 2.39018, accuracy: 1e-5)
        XCTAssertEqual(e.leadLeft, 71)
        XCTAssertEqual(e.leadChanges, 1)
        XCTAssertNotNil(e.leadText)
        XCTAssertEqual(e.recoveryS, 5.9, accuracy: 1e-9)
        XCTAssertNil(e.pauseToNextS, "pausa null → nil")
        // session structure
        XCTAssertEqual(tw.phaseBasis, "VELOCIDAD")
        XCTAssertEqual(tw.phaseBasisShort, "velocidad")
        XCTAssertTrue(tw.warmup.present && tw.work.present && tw.cooldown.present)
        XCTAssertEqual(tw.cooldown.walkS, 33.9986, accuracy: 1e-4)
        XCTAssertEqual(tw.reps, 1)
        XCTAssertNil(tw.vmaxDropOpt, "Una sola rápida: sin caída entre series")
        XCTAssertNil(tw.strideDropPct)
        XCTAssertEqual(tw.recoveryMeanOpt ?? 0, 5.9, accuracy: 1e-9)
        XCTAssertTrue(tw.warmupShort)
        XCTAssertEqual(tw.sessionVmax ?? 0, 17.0353, accuracy: 1e-4)
        XCTAssertEqual(tw.sessionBest200S ?? 0, 11.778, accuracy: 1e-6)
        // events (experimental) and warnings
        XCTAssertEqual(tw.events.count, 3)
        XCTAssertEqual(tw.atypicalImpacts, 1)
        XCTAssertEqual(tw.eventsBetween(e.t0, e.t1).count, 2, "Impacto y cambio de mano dentro del trabajo")
        XCTAssertEqual(tw.events[1].valueText, AvoFormat.f(3.95547, 2) + " g")
        XCTAssertEqual(tw.warnings.count, 1)
        // no course
        XCTAssertFalse(tw.courseDefined)
        XCTAssertTrue(tw.passes.isEmpty)
        XCTAssertNil(tw.bestPassOpt)
        XCTAssertEqual(tw.sessionBest.map { $0.distanceM }, [200, 400, 600, 800])
        XCTAssertEqual(tw.sessionBest.first?.effortKey, "T1")
    }

    func testParseCourseWithLines() throws {
        let tw: TrackWorkResult = try block(TrackWorkTests.courseJson)
        XCTAssertTrue(tw.courseDefined)
        XCTAssertEqual(tw.courseName, "Regaton")
        XCTAssertEqual(tw.phaseBasis, "LINEAS")
        XCTAssertEqual(tw.phaseBasisShort, "líneas")
        XCTAssertEqual(tw.gateDistanceM ?? 0, 1200, accuracy: 1e-6)
        XCTAssertNil(tw.insideFencePct, "Sin geocerca → nil")
        XCTAssertEqual(tw.crossings.count, 4)
        XCTAssertEqual(tw.ignoredCrossings, 2, "Cruces en sentido contrario ignorados")
        XCTAssertEqual(tw.passes.count, 1)
        let p: TrackWorkEffort = try XCTUnwrap(tw.passes.first)
        XCTAssertEqual(p.key, "P1")
        XCTAssertTrue(p.isPass)
        XCTAssertEqual(p.durationS, 75.0788, accuracy: 1e-4)
        XCTAssertEqual(tw.bestPassOpt ?? 0, 75.0788, accuracy: 1e-4)
        XCTAssertEqual(tw.bestPass?.key, "P1")
        XCTAssertEqual(p.splits.count, 6)
        XCTAssertEqual(tw.allEfforts.map { $0.key }, ["T1", "P1"])
        XCTAssertNotNil(tw.effort("P1"))
        // without girth: no stride, no lead, no VeDBA
        XCTAssertFalse(tw.hasGirth)
        XCTAssertNil(tw.girth.vedbaGallopG)
        XCTAssertNil(p.freqAtVmaxHz)
        XCTAssertNil(p.leadText)
        XCTAssertEqual(tw.lead.calibration, "")
        // best of the session: 1200 m only in the effort T1
        let best: [TrackWorkBest] = tw.sessionBest
        XCTAssertEqual(best.map { $0.distanceM }, [200, 400, 600, 800, 1000, 1200])
        XCTAssertEqual(best.last?.effortKey, "T1")
        XCTAssertEqual(best.last?.timeS ?? 0, 75.0843, accuracy: 1e-4)
    }

    func testTolerantDecoding() {
        let o: [String: Any] = [
            "perfil": "no es un objeto",
            "cincha": ["disponible": "sí", "vedba_media_g": "alta"] as [String: Any],
            "trabajos": ["lista": [["t0": 1, "t1": 20, "v_max": "rápido",
                                    "parciales": [["desde_m": 0, "hasta_m": 200, "tiempo_s": NSNull()] as [String: Any]] as [Any]] as [String: Any],
                                   ["t1": 5] as [String: Any], "basura"] as [Any]] as [String: Any],
            "recorrido": NSNull(),
            "series": ["calentamiento_corto": 1] as [String: Any],
            "eventos": [["tipo": "IMPACTO_ATIPICO", "t": NSNull()] as [String: Any]] as [Any],
        ]
        let tw: TrackWorkResult = TrackWorkResult.parse(o)
        XCTAssertTrue(tw.present)
        XCTAssertEqual(tw.breed, "")
        XCTAssertFalse(tw.hasGirth)
        XCTAssertNil(tw.girth.vedbaMeanG)
        XCTAssertEqual(tw.efforts.count, 1, "Trabajos sin t0/t1 o que no son objetos se ignoran")
        XCTAssertNil(tw.efforts.first?.vmaxOpt)
        XCTAssertNil(tw.efforts.first?.splits.first?.timeS)
        XCTAssertNil(tw.efforts.first?.splits.first?.speedMs)
        XCTAssertFalse(tw.courseDefined)
        XCTAssertFalse(tw.warmupShort, "Un número no es un booleano")
        XCTAssertEqual(tw.events.count, 1)
        XCTAssertTrue(tw.eventsBetween(0, 1e9).isEmpty, "Evento sin tiempo")
        XCTAssertFalse(TrackWorkResult.parse(nil).present)
    }

    func testSpeedOverDistance() {
        let t: [Double] = (0...20).map { Double($0) }
        let v: [Double] = t.map { $0 < 5 ? 2 : 10 }
        let pts = TrackWorkResult.speedOverDistance(t: t, speed: v, t0: 5, t1: 15)
        XCTAssertEqual(pts.count, 11)
        XCTAssertEqual(pts.first?.d ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(pts.last?.d ?? 0, 100, accuracy: 1e-9)
        XCTAssertTrue(TrackWorkResult.speedOverDistance(t: t, speed: v, t0: 30, t1: 40).isEmpty)
        XCTAssertEqual(TrackWorkResult.speedOverDistance(t: t, speed: v, t0: 0, t1: 20, maxPoints: 5).count, 5)
    }

    // MARK: - real engine on the bundled demo session, profile PSI

    func testEngineDemoSessionPsi() async throws {
        guard EquineEngine.available else { throw XCTSkip("Motor no disponible") }
        guard let demo = Bundle.main.url(forResource: "demo", withExtension: nil) else {
            throw XCTSkip("Sesiones de demostración no incluidas en la app")
        }
        let file: String = demo.appendingPathComponent("DEMO_REGATON_20261022.avr").path
        guard FileManager.default.fileExists(atPath: file) else { throw XCTSkip("Falta DEMO_REGATON_20261022.avr") }
        let cache: String = (NSTemporaryDirectory() as NSString).appendingPathComponent("avo_tw_" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(atPath: cache) }
        let json: String = try await EquineEngine.analyseJson([file], EquineEngine.options(series: true, cacheDir: cache, extra: "\"raza\":\"PSI\""))
        let a: EquineAnalysis = try EquineAnalysis.parse(json)
        XCTAssertTrue(json.contains("\"trabajo_pista\":{"), "Bloque trabajo_pista en el JSON del motor")
        let tw: TrackWorkResult = a.trackWork
        XCTAssertTrue(tw.present, "Bloque trabajo_pista decodificado")
        XCTAssertEqual(tw.module, "AVO_TRACK_WORK")
        XCTAssertEqual(tw.breed, "PSI", "Perfil PSI aplicado")
        XCTAssertEqual(tw.profile.workSpeed ?? 0, 11, accuracy: 1e-9)
        XCTAssertEqual(tw.profile.fastSpeed ?? 0, 14.5, accuracy: 1e-9)
        XCTAssertEqual(tw.profile.referenceSpeeds, [14, 16])
        XCTAssertFalse(tw.phaseBasis.isEmpty)
        if !a.hasImu { XCTAssertFalse(tw.girth.available, "Sin cincha en la sesión → sin cincha en Track Work") }
        if tw.girth.available { XCTAssertFalse(tw.girth.scale.isEmpty) }
        XCTAssertEqual(tw.reps, tw.efforts.count, "Repeticiones = trabajos (sin pasadas)")
        for e in tw.allEfforts {
            XCTAssertTrue(e.t1 > e.t0, "Trabajo \(e.key) con duración")
            XCTAssertEqual(e.splits.map { $0.id }, Array(0..<e.splits.count))
            if let last = e.splits.last, let cum = last.cumulativeS {
                let sum: Double = e.splits.compactMap { $0.timeS }.reduce(0, +)
                XCTAssertEqual(cum, sum, accuracy: 1e-6, "Tiempo acumulado = suma de parciales")
            }
            for b in e.best { XCTAssertTrue([200.0, 400, 600, 800, 1000, 1200, 1600].contains(b.distanceM), "Mejor distancia \(b.distanceM)") }
            if tw.hasGirth { XCTAssertEqual(e.references.count, 2) }
        }
        for b in tw.sessionBest { XCTAssertNotNil(tw.effort(b.effortKey)) }
    }

    // MARK: - training vs race, sector by sector

    private static func utc() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// 1400 m race: DEP–1200 … 200–ARR, 7 sectors of 200 m (times only: speed = 200 m / time).
    private static func runner() -> RaceRunner {
        let times: [Double] = [13.0, 11.8, 11.7, 11.9, 12.0, 12.3, 12.6]
        var sectors: [RaceSector] = []
        var cum: Double = 0
        for (k, t) in times.enumerated() {
            cum += t
            let from: Double = Double(k) * 200, to: Double = from + 200
            let a: String = k == 0 ? "DEP" : "\(Int(1400 - from))m"
            let b: String = k == times.count - 1 ? "ARR" : "\(Int(1400 - to))m"
            sectors.append(RaceSector(label: "\(a) - \(b)", fromM: from, toM: to, cumulativeS: cum, sectorS: t))
        }
        return RaceRunner(number: 3, draw: 2, name: "ZAKYNA AL ZARAYAN", jockey: "J", finish: 4, officialTimeS: cum,
                          maxSpeedSector: "", fastestSector: "", sectors: sectors)
    }

    func testTrainingVsRaceSectorAlignment() throws {
        let cal: Calendar = TrackWorkTests.utc()
        let raceDate: Date = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 14)))
        func day(_ d: Int) -> Date { cal.date(byAdding: .day, value: d, to: raceDate)! }
        let race: TrackWorkResult = try block(TrackWorkTests.raceJson)
        let course: TrackWorkResult = try block(TrackWorkTests.courseJson)
        let sources: [RaceTrainingSource] = [
            RaceTrainingSource(sessionId: "A", date: day(-10), isDemo: true, trackWork: race),
            RaceTrainingSource(sessionId: "B", date: day(-5), isDemo: true, trackWork: course),
            RaceTrainingSource(sessionId: "OLD", date: day(-70), isDemo: true, trackWork: course),     // outside 60 days
            RaceTrainingSource(sessionId: "AFTER", date: day(1), isDemo: true, trackWork: course),     // after the race
        ]
        let cands: [RaceTrainingCandidate] = RaceTrainingSplits.candidates(sources, raceDate: raceDate, calendar: cal)
        XCTAssertEqual(cands.map { $0.id }, ["B|T1", "B|P1", "A|T1"], "Solo los 60 días anteriores, más recientes primero")
        // default: fastest by mean speed with ≥ 2 full splits → the pass of session B (15,9653 m/s)
        let def: RaceTrainingCandidate = try XCTUnwrap(RaceTrainingSplits.defaultCandidate(cands))
        XCTAssertEqual(def.id, "B|P1")

        // effort A|T1: 4 full splits + a short last one (800–901 m) against the 7 sectors of the race, aligned from the finish
        let a: RaceTrainingCandidate = try XCTUnwrap(cands.first { $0.id == "A|T1" })
        let us: RaceRunner = TrackWorkTests.runner()
        let cmp: RaceSectorComparison = RaceTrainingSplits.compare(a, us)
        XCTAssertTrue(cmp.trainingPartialEndSkipped)
        XCTAssertFalse(cmp.trainingIsFurlong)
        XCTAssertEqual(cmp.rows.count, 7)
        XCTAssertEqual(cmp.rows.map { $0.label }, ["DEP–1200", "1200–1000", "1000–800", "800–600", "600–400", "400–200", "200–ARR"])
        XCTAssertNil(cmp.rows[0].trainingKmh, "El trabajo no cubre los primeros tramos")
        XCTAssertNil(cmp.rows[2].trainingS)
        // last row: training split 600–800 m (12,4452 s) vs race 200–ARR (12,6 s)
        let last: RaceSectorComparisonRow = try XCTUnwrap(cmp.rows.last)
        XCTAssertEqual(last.trainingS ?? 0, 12.4452, accuracy: 1e-6)
        XCTAssertEqual(last.trainingKmh ?? 0, 16.0705 * 3.6, accuracy: 1e-6)
        XCTAssertEqual(last.raceS ?? 0, 12.6, accuracy: 1e-9)
        XCTAssertEqual(last.raceKmh ?? 0, 200 / 12.6 * 3.6, accuracy: 1e-9)
        XCTAssertEqual(last.pctOfRace ?? 0, (16.0705 * 3.6) / (200 / 12.6 * 3.6), accuracy: 1e-9)
        // first compared row: training 0–200 m (13,0675 s) vs race 800–600
        XCTAssertEqual(cmp.rows[3].trainingS ?? 0, 13.0675, accuracy: 1e-6)
        XCTAssertEqual(cmp.rows[3].raceS ?? 0, 11.9, accuracy: 1e-9)
        // fade: last / best previous, in both
        XCTAssertEqual(cmp.trainingFade ?? 0, 16.0705 / 16.9809, accuracy: 1e-6)
        XCTAssertEqual(cmp.raceFade ?? 0, 11.7 / 12.6, accuracy: 1e-9)
        XCTAssertEqual(cmp.raceBestKmh ?? 0, 200 / 11.7 * 3.6, accuracy: 1e-9)
        let pcts: [Double] = cmp.rows.compactMap { $0.pctOfRace }
        XCTAssertEqual(pcts.count, 4)
        XCTAssertEqual(cmp.meanPctOfRace ?? 0, pcts.reduce(0, +) / 4, accuracy: 1e-12)

        // the pass (6 splits, the last of 198,65 m counts as full: within 5 %) covers 6 of the 7 sectors
        let p: RaceSectorComparison = RaceTrainingSplits.compare(def, us)
        XCTAssertFalse(p.trainingPartialEndSkipped)
        XCTAssertEqual(p.rows.compactMap { $0.trainingKmh }.count, 6)
        XCTAssertNil(p.rows[0].trainingKmh)
    }
}
