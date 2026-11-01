import SwiftUI
import Observation

/// Girth IMU channel shown in the channel list.
struct BiomechChannelRow: Identifiable {
    let id: Int
    var name: String
    var samples: String
    var span: String
    var color: Color
    var fused: Bool
}

/// Signal drawn in the IMU window around the cursor.
enum BiomechWindowSignal: String, CaseIterable, Identifiable {
    case magnitude = "|a|"
    case axes = "Ejes x/y/z"
    case gyro = "Giro"
    var id: String { rawValue }
}

/// Biomechanics page = biomechanics parts of windows/AVO.Windows/ViewModels/MainViewModel.Segments.cs (RefreshBiomech,
/// RefreshImuWindow, MostMovement) and MainViewModel.Charts.cs (cadence series, gait bands, fused girth movement).
/// Every index comes from the AVO Equine Intelligence engine and is exploratory; without girth data nothing is computed.
@Observable
final class BiomechModel {
    unowned let app: AppModel

    var status: String = "Selecciona un entrenamiento."
    var metrics: [FeatureKV] = []
    var symmetryRows: [EngineSymmetryGroup] = []
    var symmetryControls: [String] = []
    /// imu_id values with data (0 central, 1 left, 2 right).
    var activeSensors: [Int] = []
    var symmetryHeadline: String = "—"
    var regularityHeadline: String = "—"
    var cadenceHeadline: String = "—"
    var strideHeadline: String = "—"
    var scaleNote: String = ImuTimeline.scaleNote
    var sampleRateText: String = "Sin datos"
    var alignmentText: String = "Sin datos"
    var channels: [BiomechChannelRow] = []
    var hasGirthRaw: Bool = false
    var hasBiomech: Bool = false
    var hasFused: Bool = false

    // IMU window around the cursor (±2 s)
    var windowSignal: BiomechWindowSignal = .magnitude { didSet { refreshImuWindow() } }
    var windowSensor: Int = 0 { didSet { refreshImuWindow() } }
    var imuWindowSeries: [FeatureLineSeries] = []
    var fusedAccelWindow: [FeatureLineSeries] = []
    var orientationWindow: [FeatureLineSeries] = []
    var imuWindowMin: Double = 0
    var imuWindowMax: Double = 4
    var windowCaption: String = ""

    // cadence per sensor (engine) on the session time axis
    var cadenceSeries: [FeatureLineSeries] = []
    var gaitBands: [FeatureBand] = []

    @ObservationIgnored private var movementCache: [String: Double] = [:]
    @ObservationIgnored private var lastWindowKey: String = ""

    init(app: AppModel) {
        self.app = app
    }

    // ------------------------------------------------------------------ contract
    func sessionChanged() {
        lastWindowKey = ""
        refreshBiomech()
    }

    func pageShown() {
        refreshBiomech()
    }

    /// Windows: the IMU window follows the cursor while the Biomech page is visible.
    func cursorChanged() {
        refreshImuWindow()
    }

    static func sensorColor(_ id: Int) -> Color {
        switch id {
        case 1: return Color(hex: 0x3D9BFF)
        case 0: return Color(hex: 0x52DD40)
        case 2: return Color(hex: 0xFFC42C)
        default: return Color(hex: 0x93949B)
        }
    }

    // ------------------------------------------------------------------ RefreshBiomech
    func refreshBiomech() {
        var rows: [FeatureKV] = []
        symmetryRows = []
        symmetryControls = []
        let s: SessionItem? = app.selected
        var ids: [Int] = []
        if let s = s {
            for c in s.imu.channels { ids.append(Int(c.imuId)) }
            for f in s.imu.fused where !ids.contains(Int(f.imuId)) { ids.append(Int(f.imuId)) }
        }
        activeSensors = ids
        symmetryHeadline = "—"; regularityHeadline = "—"; cadenceHeadline = "—"; strideHeadline = "—"
        hasGirthRaw = (s?.imu.channels.count ?? 0) > 0
        hasFused = (s?.imu.fused.count ?? 0) > 0
        hasBiomech = s?.engine?.hasImu ?? false
        scaleNote = s?.imu.note ?? ImuTimeline.scaleNote
        buildChannels(s)
        if s == nil {
            status = "Selecciona un entrenamiento."
        } else if let s = s, !s.hasGirth {
            status = "Sin datos de cincha en esta sesión: no se calcula ningún índice biomecánico."
        } else if let s = s, s.engine == nil {
            status = "Datos de cincha decodificados; el motor AVO todavía no ha terminado el análisis."
        } else if let e = s?.engine, !e.hasImu {
            status = "El motor no ha podido usar los datos de la cincha."
        } else if let e = s?.engine {
            var st: String = "\(e.fusionSummary). Índices exploratorios de IMU sin calibrar: no son diagnóstico clínico, carga de extremidad ni lesión."
            if e.metric("cadencia_media_imu0") == nil {
                st += " La cincha tiene datos, pero el motor no ha encontrado ciclos de marcha (paso, trote o galope): " +
                    "los índices aparecen con el caballo en movimiento al menos unos segundos seguidos."
            }
            status = st
            let none: String = "sin ciclos de marcha"
            let distinctIds: [Int] = Array(Set(e.girthImu)).sorted()
            for id in distinctIds {
                let n: String = ImuTimeline.sensorName(UInt8(clamping: id))
                rows.add("\(n) · cadencia", TimeText.num(e.metric("cadencia_media_imu\(id)"), "0", " ciclos/min", missing: none))
                rows.add("\(n) · correlación entre ciclos", TimeText.num(e.metric("correlacion_entre_ciclos_imu\(id)"), "0.000", "", missing: none))
                rows.add("\(n) · CV de intervalos", TimeText.num(e.metric("variabilidad_intervalos_imu\(id)"), "0.000", "", missing: none))
                rows.add("\(n) · CV de amplitud", TimeText.num(e.metric("regularidad_amplitud_cv_imu\(id)"), "0.000", "", missing: none))
                rows.add("\(n) · estabilidad espectral", TimeText.num(e.metric("estabilidad_espectral_imu\(id)"), "0.000", "", missing: none))
            }
            symmetryRows = e.symmetryGroups
            symmetryControls = e.symmetryControls
            cadenceHeadline = TimeText.num(e.metric("cadencia_media_imu0"), "0", "", missing: "—")
            regularityHeadline = TimeText.num(e.metric("correlacion_entre_ciclos_imu0"), "0.00", "", missing: "—")
            var strides: [Double] = []
            for seg in e.segments { if let d = seg.strideLengthM, d.isFinite { strides.append(d) } }
            strideHeadline = strides.isEmpty ? "—" : DotNetFormat.custom(strides.reduce(0, +) / Double(strides.count), "0.00", spanish: true)
            // Exploratory temporal asymmetry (d1 − d2)/(d1 + d2) of the engine, only from groups it marks reproducible.
            var rep: [Double] = []
            for g in e.symmetryGroups where g.temporalReproducible { if let v = g.temporalAsymmetry { rep.append(v) } }
            symmetryHeadline = rep.isEmpty ? "—" : DotNetFormat.custom(100 * Stats.median(rep), "+0.0;-0.0;0.0", spanish: true)
        }
        metrics = rows
        buildCadence(s)
        lastWindowKey = ""
        refreshImuWindow()
    }

    private func buildChannels(_ s: SessionItem?) {
        var list: [BiomechChannelRow] = []
        guard let s = s else {
            channels = []; sampleRateText = "Sin datos"; alignmentText = "Sin datos"
            return
        }
        for c in s.imu.channels {
            let span: Double = c.t.count > 1 ? c.t[c.t.count - 1] - c.t[0] : 0
            list.append(BiomechChannelRow(id: Int(c.imuId), name: c.name, samples: AvoFormat.n0(Double(c.t.count)) + " muestras",
                                          span: TimeText.clock(span), color: BiomechModel.sensorColor(Int(c.imuId)), fused: false))
        }
        for f in s.imu.fused {
            let span: Double = f.t.count > 1 ? f.t[f.t.count - 1] - f.t[0] : 0
            list.append(BiomechChannelRow(id: 100 + Int(f.imuId), name: f.name + " · movimiento (fmt 1)",
                                          samples: AvoFormat.n0(Double(f.t.count)) + " muestras", span: TimeText.clock(span),
                                          color: BiomechModel.sensorColor(Int(f.imuId)), fused: true))
        }
        channels = list
        let hz: Double = s.imu.sampleRateHz
        sampleRateText = hz > 0 ? DotNetFormat.custom(hz, "0.#", spanish: true) + " Hz (periodo declarado)" : "Sin datos"
        if s.imu.channels.isEmpty && s.imu.fused.isEmpty {
            alignmentText = "Sin datos"
        } else {
            alignmentText = s.imu.aligned
                ? "Alineada con GNSS · desfase " + DotNetFormat.custom(s.imu.offsetS, "0.000", spanish: true) + " s"
                : "Sin alinear con GNSS (sin marcas de tiempo del pecho)"
        }
        if !list.contains(where: { $0.id == windowSensor }), let first = s.imu.channels.first {
            windowSensor = Int(first.imuId)
        }
    }

    /// Cadence per sensor (engine, ciclos/min, only "OK" windows) and gait bands, on the session time axis.
    private func buildCadence(_ s: SessionItem?) {
        var cad: [FeatureLineSeries] = []
        var bands: [FeatureBand] = []
        if let s = s, let e = s.engine, e.hasImu {
            let off: Double = s.engineOffsetS
            for seg in e.segments {
                let code: Int
                switch seg.gaitCode {
                case "STOPPED": code = 0
                case "WALK": code = 1
                case "TROT": code = 2
                case "CANTER_GALLOP": code = 3
                default: code = -1
                }
                let rgb: AvoRGB = SpeedScale.gait(code)
                bands.append(FeatureBand(id: bands.count, x0: seg.t0 - off, x1: seg.t1 - off,
                                         color: Color(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)))
            }
            let n: Int = min(e.girthT.count, min(e.girthImu.count, min(e.girthCadenceHz.count, e.girthStatus.count)))
            if n > 0 {
                let ids: [Int] = Array(Set(e.girthImu.prefix(n))).sorted()
                for id in ids {
                    var idx: [Int] = []
                    for k in 0..<n where e.girthImu[k] == id && e.girthT[k].isFinite { idx.append(k) }
                    idx.sort { (a: Int, b: Int) -> Bool in e.girthT[a] < e.girthT[b] || (e.girthT[a] == e.girthT[b] && a < b) }
                    let x: [Double] = idx.map { e.girthT[$0] - off }
                    let y: [Double] = idx.map { e.girthStatus[$0] == "OK" ? e.girthCadenceHz[$0] * 60 : Double.nan }
                    cad.append(FeatureLineSeries(id: "cad\(id)", name: ImuTimeline.sensorName(UInt8(clamping: id)),
                                                 color: BiomechModel.sensorColor(id), x: x, y: y, unit: "ciclos/min", format: "0", width: 1.4))
                }
            }
        }
        cadenceSeries = cad
        gaitBands = bands
    }

    // ------------------------------------------------------------------ RefreshImuWindow
    /// Girth signal in a 4 s window around the cursor: movement pattern of the three sensors (Windows: |a| in nominal g).
    /// Without a cursor (or outside the girth data) the window goes to the moment of most movement of the girth.
    func refreshImuWindow() {
        guard let s = app.selected, !(s.imu.channels.isEmpty && s.imu.fused.isEmpty) else {
            clearWindow()
            return
        }
        // reference time base: first raw channel, else first fused channel
        let refT: [Double]
        var movementKey: String = s.id
        if let ch0 = s.imu.channels.first { refT = ch0.t; movementKey += "#raw" } else { refT = s.imu.fused[0].t; movementKey += "#fused" }
        if refT.isEmpty { clearWindow(); return }
        let tMin: Double = refT[0]
        let tMax: Double = refT[refT.count - 1]
        let cursor: Double = app.cursorTime
        var c: Double
        if cursor.isFinite && cursor >= tMin && cursor <= tMax {
            c = cursor
        } else if let cached = movementCache[movementKey] {
            c = cached
        } else {
            c = mostMovement(s)
            movementCache[movementKey] = c
        }
        let half: Double = min(2, (tMax - tMin) / 2)
        c = min(max(c, tMin + half), tMax - half)
        let a: Double = c - 2
        let b: Double = c + 2
        let key: String = "\(s.id)|\(a)|\(windowSignal.rawValue)|\(windowSensor)"
        if key == lastWindowKey { return }
        lastWindowKey = key
        imuWindowMin = 0
        imuWindowMax = 4
        windowCaption = "Ventana " + TimeText.clock(a) + " – " + TimeText.clock(b) + (cursor.isFinite && cursor >= tMin && cursor <= tMax
            ? " · centrada en el cursor" : " · momento de mayor movimiento de la cincha (sin cursor sobre los datos)")

        var list: [FeatureLineSeries] = []
        switch windowSignal {
        case .magnitude:
            for ch in s.imu.channels {
                let r = BiomechModel.window(ch.t, a, b)
                if r.count < 4 { continue }
                var x: [Double] = []
                var y: [Double] = []
                x.reserveCapacity(r.count); y.reserveCapacity(r.count)
                for i in r.lo..<r.hi {
                    x.append(ch.t[i] - a)
                    let ax: Double = Double(ch.ax[i]), ay: Double = Double(ch.ay[i]), az: Double = Double(ch.az[i])
                    y.append((ax * ax + ay * ay + az * az).squareRoot() * ch.accelGPerLsb)
                }
                list.append(FeatureLineSeries(id: "mag\(ch.imuId)", name: ch.name, color: BiomechModel.sensorColor(Int(ch.imuId)),
                                              x: x, y: y, unit: "g", format: "0.00", width: 1.4))
            }
        case .axes, .gyro:
            if let ch = s.imu.channels.first(where: { Int($0.imuId) == windowSensor }) ?? s.imu.channels.first {
                let r = BiomechModel.window(ch.t, a, b)
                if r.count >= 4 {
                    let x: [Double] = (r.lo..<r.hi).map { ch.t[$0] - a }
                    let gyro: Bool = windowSignal == .gyro
                    let k: Double = gyro ? ch.gyroDpsPerLsb : ch.accelGPerLsb
                    let srcs: [(String, [Int16], Color)] = gyro
                        ? [("x", ch.gx, Avo.red), ("y", ch.gy, Avo.ok), ("z", ch.gz, Avo.blue)]
                        : [("x", ch.ax, Avo.red), ("y", ch.ay, Avo.ok), ("z", ch.az, Avo.blue)]
                    for (axis, src, color) in srcs {
                        let y: [Double] = (r.lo..<r.hi).map { Double(src[$0]) * k }
                        list.append(FeatureLineSeries(id: "\(axis)\(ch.imuId)", name: "\(ch.name) · \(axis)", color: color, x: x, y: y,
                                                      unit: gyro ? "°/s" : "g", format: gyro ? "0" : "0.00", width: 1.2))
                    }
                }
            }
        }
        imuWindowSeries = list

        // girth movement (BNO085 fused output, fmt 1) in the same window
        var fa: [FeatureLineSeries] = []
        var fo: [FeatureLineSeries] = []
        let many: Bool = s.imu.fused.count > 1
        for f in s.imu.fused {
            let r = BiomechModel.window(f.t, a, b)
            if r.count < 4 { continue }
            let p: String = many ? f.name + " · " : ""
            let x: [Double] = (r.lo..<r.hi).map { f.t[$0] - a }
            fa.append(FeatureLineSeries(id: "v\(f.imuId)", name: p + "Vertical (arriba +)", color: Avo.red, x: x,
                                        y: Array(f.verticalMs2[r.lo..<r.hi]), unit: "m/s²", format: "0.00", width: 1.2))
            fa.append(FeatureLineSeries(id: "h\(f.imuId)", name: p + "Horizontal", color: Avo.cyan, x: x,
                                        y: Array(f.horizontalMs2[r.lo..<r.hi]), unit: "m/s²", format: "0.00", width: 1))
            fo.append(FeatureLineSeries(id: "r\(f.imuId)", name: p + "Balanceo (lateral)", color: Avo.warn, x: x,
                                        y: Array(f.rollDeg[r.lo..<r.hi]), unit: "°", format: "0.0", width: 1.2))
            fo.append(FeatureLineSeries(id: "p\(f.imuId)", name: p + "Cabeceo (adelante/atrás)", color: Color(hex: 0xA86BFF), x: x,
                                        y: Array(f.pitchDeg[r.lo..<r.hi]), unit: "°", format: "0.0", width: 1.2))
        }
        fusedAccelWindow = fa
        orientationWindow = fo
    }

    /// Clears the window only when needed: assigning to an observed property always notifies the views, and the view calls
    /// this on every cursor change (NaN cursor compares unequal to itself).
    private func clearWindow() {
        lastWindowKey = ""
        if !imuWindowSeries.isEmpty { imuWindowSeries = [] }
        if !fusedAccelWindow.isEmpty { fusedAccelWindow = [] }
        if !orientationWindow.isEmpty { orientationWindow = [] }
        if !windowCaption.isEmpty { windowCaption = "" }
    }

    /// [lo, hi) of the samples with a ≤ t < b (C# Array.BinarySearch insertion points).
    private static func window(_ t: [Double], _ a: Double, _ b: Double) -> (lo: Int, hi: Int, count: Int) {
        let lo: Int = lowerBound(t, a)
        let hi: Int = lowerBound(t, b)
        return (lo: lo, hi: max(hi, lo), count: max(hi - lo, 0))
    }

    private static func lowerBound(_ t: [Double], _ v: Double) -> Int {
        var lo: Int = 0
        var hi: Int = t.count
        while lo < hi {
            let mid: Int = (lo + hi) / 2
            if t[mid] < v { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// Time of the largest deviation of |a| from its median (the most visible movement of the girth).
    private func mostMovement(_ s: SessionItem) -> Double {
        if let ch = s.imu.channels.first {
            let mag: [Double] = ch.accelMagnitudeG()
            if mag.isEmpty { return 0 }
            let med: Double = Stats.median(mag)
            var best: Double = -1
            var k: Int = mag.count / 2
            for i in 0..<mag.count {
                let d: Double = abs(mag[i] - med)
                if d > best { best = d; k = i }
            }
            return ch.t[k]
        }
        if let f = s.imu.fused.first, !f.t.isEmpty {
            var best: Double = -1
            var k: Int = f.t.count / 2
            for i in 0..<f.verticalMs2.count where f.verticalMs2[i].isFinite {
                let d: Double = abs(f.verticalMs2[i])
                if d > best { best = d; k = i }
            }
            return f.t[min(k, f.t.count - 1)]
        }
        return 0
    }
}
