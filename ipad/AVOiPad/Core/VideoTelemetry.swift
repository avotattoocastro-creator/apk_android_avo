import Foundation
import CoreGraphics
import UIKit

// Datos del entrenamiento sobre el vídeo de «Cámara» (docs/AVO_SYNC.md §7). El vídeo y el entrenamiento se juntan por la
// hora: UTC del fotograma (AVO SYNC o reloj del iPad) → t de la línea de tiempo del entrenamiento
// (t = t[0] + (UTC − utc0)). Los indicadores se dibujan con Core Graphics: el mismo dibujo sirve para el reproductor
// y para el vídeo exportado con los datos impresos.

/// Indicadores que se pueden mostrar sobre el vídeo (el usuario elige cuáles).
enum VideoGauge: String, CaseIterable, Identifiable, Codable {
    case speed, distance, route, compass, gait, accel, lateral, stride, imu, altitude, rtk, coords, pulse, clock, horse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .speed: return "Velocímetro"
        case .distance: return "Distancia (barra)"
        case .route: return "Recorrido"
        case .compass: return "Rumbo (brújula)"
        case .gait: return "Aire"
        case .accel: return "Aceleración"
        case .lateral: return "Aceleración lateral"
        case .stride: return "Tranco (frecuencia y longitud)"
        case .imu: return "IMU de la cincha"
        case .altitude: return "Altitud"
        case .rtk: return "Calidad GNSS (RTK)"
        case .coords: return "Coordenadas"
        case .pulse: return "Pulso"
        case .clock: return "Hora GPS"
        case .horse: return "Caballo y fecha"
        }
    }

    static let defaults: Set<VideoGauge> = [.speed, .distance, .route, .compass, .gait, .accel, .stride, .clock, .horse]

    /// Selección guardada (UserDefaults `video.gauges`).
    static func load() -> Set<VideoGauge> {
        guard let s = UserDefaults.standard.string(forKey: "video.gauges") else { return defaults }
        return Set(s.split(separator: ",").compactMap { VideoGauge(rawValue: String($0)) })
    }

    static func save(_ g: Set<VideoGauge>) {
        UserDefaults.standard.set(g.map { $0.rawValue }.sorted().joined(separator: ","), forKey: "video.gauges")
    }
}

/// Valores del entrenamiento en un instante.
struct VideoTelemetrySample {
    var inRange: Bool
    var speedKmh: Double = .nan
    var accelMs2: Double = .nan
    var lateralMs2: Double = .nan
    var distanceM: Double = .nan
    var altitudeM: Double = .nan
    var lat: Double = .nan
    var lon: Double = .nan
    var headingDeg: Double = .nan
    var rtk: String = "—"
    var gait: String = "—"
    var gaitCode: Int = -1
    var strideHz: Double = .nan
    var strideM: Double = .nan
    var imuValue: Double = .nan
}

/// Copia de solo lectura de las series del entrenamiento (segura para usar desde la cola de exportación).
final class VideoTelemetry {
    let sessionId: String
    let horse: String
    let dateText: String
    /// La hora del entrenamiento sale de la hora UTC del GNSS (si no, de la hora de inicio del reloj de pecho).
    let utcFromGnss: Bool
    let imuLabel: String
    let imuUnit: String
    let hasGirth: Bool
    let hasPulse: Bool = false   // ECG de la cincha (fmt 2) aún sin decodificar en el iPad
    let maxSpeedKmh: Double
    let totalDistanceM: Double
    let routeX: [Double]   // recorrido normalizado (0..1), para el mapa pequeño
    let routeY: [Double]

    private let t: [Double]
    private let speed: [Double]
    private let accel: [Double]
    private let lateral: [Double]
    private let distance: [Double]
    private let altitude: [Double]
    private let lat: [Double]
    private let lon: [Double]
    private let heading: [Double]
    private let solution: [GnssSolution]
    private let t0: Double
    private let utc0S: Double
    private let engineOffset: Double
    private let gaitT: [Double]
    private let gaitCode: [Int]
    private let girthT: [Double]
    private let cadenceHz: [Double]
    private let strideM: [Double]
    private let imuT: [Double]
    private let imuV: [Double]
    private let routeLat0: Double, routeLon0: Double, routeScaleX: Double, routeScaleY: Double, routeCos: Double

    init?(_ item: SessionItem) {
        let tl: SessionTimeline = item.fullTimeline
        guard tl.count > 1, let u0 = tl.utc0 else { return nil }
        sessionId = item.id
        horse = item.horse
        dateText = item.dateTimeText
        utcFromGnss = item.session.track.first?.utcTime != nil
        t = tl.t; speed = tl.speedFiltered.map { $0 * 3.6 }; accel = tl.accelLong; lateral = tl.accelLateral
        distance = tl.distance; altitude = tl.altitudeMsl; lat = tl.lat; lon = tl.lon; solution = tl.solution
        t0 = tl.t[0]
        utc0S = u0.timeIntervalSince1970
        maxSpeedKmh = speed.filter { $0.isFinite }.max() ?? 0
        totalDistanceM = tl.totalDistanceM

        // rumbo a partir de las posiciones (el GNSS de la espalda): punto anterior → siguiente, si se ha movido > 0,5 m
        var h: [Double] = [Double](repeating: .nan, count: tl.count)
        var last: Double = .nan
        for i in 0..<tl.count {
            let a: Int = max(0, i - 1), b: Int = min(tl.count - 1, i + 1)
            let dy: Double = (tl.lat[b] - tl.lat[a]) * 111_320
            let dx: Double = (tl.lon[b] - tl.lon[a]) * 111_320 * cos(tl.lat[i] * .pi / 180)
            if (dx * dx + dy * dy).squareRoot() > 0.5 {
                var d: Double = atan2(dx, dy) * 180 / .pi
                if d < 0 { d += 360 }
                last = d
            }
            h[i] = last
        }
        heading = h

        // recorrido normalizado (máximo ~500 puntos)
        let la0: Double = tl.lat.min() ?? 0, la1: Double = tl.lat.max() ?? 0
        let lo0: Double = tl.lon.min() ?? 0, lo1: Double = tl.lon.max() ?? 0
        let c: Double = cos(((la0 + la1) / 2) * .pi / 180)
        let spanX: Double = max((lo1 - lo0) * c, 1e-9), spanY: Double = max(la1 - la0, 1e-9)
        let span: Double = max(spanX, spanY)
        routeLat0 = la0; routeLon0 = lo0; routeCos = c
        routeScaleX = span; routeScaleY = span
        let step: Int = max(1, tl.count / 500)
        var rx: [Double] = [], ry: [Double] = []
        var i: Int = 0
        while i < tl.count {
            rx.append(((tl.lon[i] - lo0) * c) / span)
            ry.append((tl.lat[i] - la0) / span)
            i += step
        }
        routeX = rx; routeY = ry

        engineOffset = item.engineOffsetS
        if let e = item.engine {
            gaitT = e.t; gaitCode = e.gaitCode.count == e.t.count ? e.gaitCode : []
            girthT = e.girthT; cadenceHz = e.girthCadenceHz; strideM = e.girthStrideM
        } else {
            gaitT = []; gaitCode = []; girthT = []; cadenceHz = []; strideM = []
        }
        hasGirth = item.hasGirth
        let imu: ImuTimeline = item.fullImu
        if let f = imu.fused.first, !f.t.isEmpty {
            imuT = f.t; imuV = f.verticalMs2; imuLabel = "Acel. vertical"; imuUnit = "m/s²"
        } else if let ch = imu.channels.first, !ch.t.isEmpty {
            imuT = ch.t; imuV = ch.accelMagnitudeG(); imuLabel = "|a| cincha"; imuUnit = "g"
        } else {
            imuT = []; imuV = []; imuLabel = "IMU"; imuUnit = ""
        }
    }

    /// t de la línea de tiempo del entrenamiento para una hora UTC (s desde 1970).
    func timelineT(utcS: Double) -> Double { t0 + (utcS - utc0S) }

    var startUtcS: Double { utc0S }
    var endUtcS: Double { utc0S + ((t.last ?? t0) - t0) }

    /// Posición normalizada (0..1) en el mapa pequeño.
    func routePoint(lat la: Double, lon lo: Double) -> (Double, Double) {
        (((lo - routeLon0) * routeCos) / routeScaleX, (la - routeLat0) / routeScaleY)
    }

    private static func lowerIndex(_ a: [Double], _ x: Double) -> Int {
        var lo = 0, hi = a.count
        while lo < hi { let m = (lo + hi) / 2; if a[m] < x { lo = m + 1 } else { hi = m } }
        return lo
    }

    /// Interpolación lineal; NaN fuera de rango o si el hueco es > maxGap s.
    private static func interp(_ ts: [Double], _ v: [Double], _ x: Double, maxGap: Double = 2) -> Double {
        let n = min(ts.count, v.count)
        guard n > 0 else { return .nan }
        let j = lowerIndex(ts, x)
        if j <= 0 { return abs(ts[0] - x) <= maxGap / 2 ? v[0] : .nan }
        if j >= n { return abs(ts[n - 1] - x) <= maxGap / 2 ? v[n - 1] : .nan }
        let a = ts[j - 1], b = ts[j]
        if b - a > maxGap { return .nan }
        let w = b > a ? (x - a) / (b - a) : 0
        let va = v[j - 1], vb = v[j]
        if !va.isFinite { return vb }
        if !vb.isFinite { return va }
        return va + w * (vb - va)
    }

    private static func nearest(_ ts: [Double], _ x: Double, maxGap: Double) -> Int? {
        guard !ts.isEmpty else { return nil }
        let j = lowerIndex(ts, x)
        var best: Int? = nil
        var bd: Double = .infinity
        for k in [j - 1, j] where k >= 0 && k < ts.count {
            let d = abs(ts[k] - x)
            if d < bd { bd = d; best = k }
        }
        return bd <= maxGap ? best : nil
    }

    static func gaitName(_ c: Int) -> String {
        switch c {
        case 0: return "Parado"
        case 1: return "Paso"
        case 2: return "Trote"
        case 3: return "Galope"
        default: return "—"
        }
    }

    func sample(utcS: Double) -> VideoTelemetrySample {
        let x = timelineT(utcS: utcS)
        guard let first = t.first, let lastT = t.last, x >= first - 1, x <= lastT + 1 else {
            return VideoTelemetrySample(inRange: false)
        }
        var s = VideoTelemetrySample(inRange: true)
        s.speedKmh = VideoTelemetry.interp(t, speed, x)
        s.accelMs2 = VideoTelemetry.interp(t, accel, x)
        s.lateralMs2 = VideoTelemetry.interp(t, lateral, x)
        s.distanceM = VideoTelemetry.interp(t, distance, x)
        s.altitudeM = VideoTelemetry.interp(t, altitude, x)
        s.lat = VideoTelemetry.interp(t, lat, x)
        s.lon = VideoTelemetry.interp(t, lon, x)
        if let i = VideoTelemetry.nearest(t, x, maxGap: 2) {
            s.headingDeg = heading[i]
            s.rtk = GnssQuality.name(solution[i])
        }
        let te = x + engineOffset
        if !gaitCode.isEmpty, let i = VideoTelemetry.nearest(gaitT, te, maxGap: 0.5) {
            s.gaitCode = gaitCode[i]
            s.gait = VideoTelemetry.gaitName(gaitCode[i])
        }
        s.strideHz = VideoTelemetry.interp(girthT, cadenceHz, te, maxGap: 3)
        s.strideM = VideoTelemetry.interp(girthT, strideM, te, maxGap: 3)
        if let i = VideoTelemetry.nearest(imuT, x, maxGap: 0.2) {
            // media de ±0,1 s para que el número se pueda leer
            var sum = 0.0, n = 0
            var k = i
            while k >= 0 && imuT[i] - imuT[k] <= 0.1 { if imuV[k].isFinite { sum += imuV[k]; n += 1 }; k -= 1 }
            k = i + 1
            while k < imuT.count && imuT[k] - imuT[i] <= 0.1 { if imuV[k].isFinite { sum += imuV[k]; n += 1 }; k += 1 }
            s.imuValue = n > 0 ? sum / Double(n) : .nan
        }
        return s
    }
}

// MARK: - Dibujo de los indicadores

/// Dibuja los indicadores sobre un fotograma de tamaño `size` (origen arriba a la izquierda).
enum VideoOverlayRenderer {
    struct Input {
        var telemetry: VideoTelemetry?
        var sample: VideoTelemetrySample
        var gauges: Set<VideoGauge>
        var utcText: String
        var timeSource: String
    }

    static func draw(_ cg: CGContext, size: CGSize, _ input: Input) {
        UIGraphicsPushContext(cg)
        defer { UIGraphicsPopContext() }
        let w = size.width, h = size.height
        let u: CGFloat = min(w, h) / 1080   // unidad: 1 en un vídeo de 1080 de alto
        let g = input.gauges
        let s = input.sample

        if g.contains(.clock) {
            text(input.utcText, CGPoint(x: w - 40 * u, y: h - 92 * u), size: 40 * u, weight: .semibold, align: .right, mono: true)
            text(input.timeSource, CGPoint(x: w - 40 * u, y: h - 42 * u), size: 20 * u, weight: .bold, align: .right,
                 color: input.timeSource.hasPrefix("HORA GPS") ? UIColor(red: 0.32, green: 0.87, blue: 0.25, alpha: 1)
                                                              : UIColor(red: 1, green: 0.77, blue: 0.17, alpha: 1))
        }
        guard let tel = input.telemetry else {
            text("Sin entrenamiento asociado", CGPoint(x: 40 * u, y: h - 70 * u), size: 28 * u, weight: .semibold)
            return
        }
        if g.contains(.horse) {
            text(tel.horse, CGPoint(x: w - 40 * u, y: 40 * u + (g.contains(.compass) ? 300 * u : 0)), size: 34 * u,
                 weight: .bold, align: .right)
            text(tel.dateText, CGPoint(x: w - 40 * u, y: 82 * u + (g.contains(.compass) ? 300 * u : 0)), size: 22 * u,
                 weight: .regular, align: .right, color: UIColor(white: 1, alpha: 0.85))
        }
        if !s.inRange {
            text("Fuera del entrenamiento", CGPoint(x: w / 2, y: h - 80 * u), size: 30 * u, weight: .semibold, align: .center)
            return
        }
        if g.contains(.distance) { distanceBar(cg, w: w, u: u, tel: tel, s: s) }
        if g.contains(.route) { route(cg, u: u, tel: tel, s: s, coords: g.contains(.coords)) }
        else if g.contains(.coords), s.lat.isFinite {
            text(coordText(s.lat, s.lon), CGPoint(x: 40 * u, y: 150 * u), size: 28 * u, weight: .semibold)
        }
        if g.contains(.compass) { compass(cg, center: CGPoint(x: w - 170 * u, y: 170 * u), r: 120 * u, heading: s.headingDeg, u: u) }
        if g.contains(.speed) {
            speedometer(cg, center: CGPoint(x: w / 2, y: h - 120 * u), r: 210 * u, value: s.speedKmh,
                        maxV: max(40, ceil(tel.maxSpeedKmh / 10) * 10), u: u)
        }
        // recuadros de datos, abajo a la izquierda, de abajo arriba
        var rows: [(String, String)] = []
        if g.contains(.gait) { rows.append(("AIRE", s.gait)) }
        if g.contains(.accel) { rows.append(("ACELERACIÓN", num(s.accelMs2, 1, "m/s²", signed: true))) }
        if g.contains(.lateral) { rows.append(("LATERAL", num(s.lateralMs2, 1, "m/s²", signed: true))) }
        if g.contains(.stride) {
            rows.append(("TRANCO", s.strideHz.isFinite ? num(s.strideHz * 60, 0, "/min") + (s.strideM.isFinite ? " · " + num(s.strideM, 2, "m") : "") : "—"))
        }
        if g.contains(.imu) { rows.append((tel.imuLabel.uppercased(), num(s.imuValue, 1, tel.imuUnit))) }
        if g.contains(.altitude) { rows.append(("ALTITUD", num(s.altitudeM, 1, "m"))) }
        if g.contains(.rtk) { rows.append(("GNSS", s.rtk)) }
        if g.contains(.pulse) { rows.append(("PULSO", tel.hasPulse ? "—" : "sin datos")) }
        var y = h - 40 * u
        for (k, v) in rows.reversed() {
            y -= 58 * u
            tile(cg, CGRect(x: 40 * u, y: y, width: 360 * u, height: 50 * u), k, v, u: u)
        }
    }

    // ------------------------------------------------------------------ piezas
    private static func num(_ v: Double, _ dec: Int, _ unit: String, signed: Bool = false) -> String {
        guard v.isFinite else { return "—" }
        let f = String(format: "%\(signed ? "+" : "").\(dec)f", v).replacingOccurrences(of: ".", with: ",")
        return unit.isEmpty ? f : f + " " + unit
    }

    static func coordText(_ la: Double, _ lo: Double) -> String {
        func dms(_ v: Double, _ p: String, _ n: String) -> String {
            let a = abs(v); let d = Int(a); let mf = (a - Double(d)) * 60; let m = Int(mf); let sec = (mf - Double(m)) * 60
            return String(format: "%d° %02d' %04.1f\" %@", d, m, sec, v >= 0 ? p : n)
        }
        return dms(la, "N", "S") + "  " + dms(lo, "E", "O")
    }

    private static func text(_ s: String, _ p: CGPoint, size: CGFloat, weight: UIFont.Weight, align: NSTextAlignment = .left,
                             color: UIColor = .white, mono: Bool = false) {
        let font: UIFont = mono ? UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : UIFont.systemFont(ofSize: size, weight: weight)
        let shadow = NSShadow()
        shadow.shadowColor = UIColor(white: 0, alpha: 0.85)
        shadow.shadowBlurRadius = max(2, size * 0.12)
        shadow.shadowOffset = .zero
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .shadow: shadow]
        let str = NSAttributedString(string: s, attributes: attrs)
        let sz = str.size()
        var x = p.x
        if align == .right { x -= sz.width } else if align == .center { x -= sz.width / 2 }
        str.draw(at: CGPoint(x: x, y: p.y - sz.height / 2))
    }

    private static func tile(_ cg: CGContext, _ r: CGRect, _ k: String, _ v: String, u: CGFloat) {
        cg.setFillColor(UIColor(white: 0, alpha: 0.45).cgColor)
        cg.addPath(UIBezierPath(roundedRect: r, cornerRadius: 10 * u).cgPath)
        cg.fillPath()
        text(k, CGPoint(x: r.minX + 16 * u, y: r.midY), size: 18 * u, weight: .bold, color: UIColor(white: 1, alpha: 0.75))
        text(v, CGPoint(x: r.maxX - 16 * u, y: r.midY), size: 28 * u, weight: .semibold, align: .right, mono: true)
    }

    private static func distanceBar(_ cg: CGContext, w: CGFloat, u: CGFloat, tel: VideoTelemetry, s: VideoTelemetrySample) {
        let x0 = w * 0.28, x1 = w * 0.72, y = 70 * u
        let total = max(tel.totalDistanceM, 1)
        text("0,0 km", CGPoint(x: x0, y: y - 34 * u), size: 24 * u, weight: .semibold, align: .center)
        text(String(format: "%.1f km", total / 1000).replacingOccurrences(of: ".", with: ","), CGPoint(x: x1, y: y - 34 * u),
             size: 24 * u, weight: .semibold, align: .center)
        cg.setStrokeColor(UIColor(white: 1, alpha: 0.9).cgColor)
        let ticks = 50
        for i in 0...ticks {
            let x = x0 + (x1 - x0) * CGFloat(i) / CGFloat(ticks)
            let len: CGFloat = i % 5 == 0 ? 22 * u : 12 * u
            cg.setLineWidth(i % 5 == 0 ? 2.5 * u : 1.5 * u)
            cg.move(to: CGPoint(x: x, y: y - len / 2)); cg.addLine(to: CGPoint(x: x, y: y + len / 2)); cg.strokePath()
        }
        let f = s.distanceM.isFinite ? CGFloat(min(max(s.distanceM / total, 0), 1)) : 0
        let mx = x0 + (x1 - x0) * f
        cg.setFillColor(UIColor(red: 0.93, green: 0.07, blue: 0.16, alpha: 1).cgColor)
        cg.fillEllipse(in: CGRect(x: mx - 11 * u, y: y - 11 * u, width: 22 * u, height: 22 * u))
        text(num(s.distanceM.isFinite ? s.distanceM / 1000 : .nan, 2, "km"), CGPoint(x: mx, y: y + 36 * u), size: 26 * u,
             weight: .bold, align: .center, mono: true)
    }

    private static func route(_ cg: CGContext, u: CGFloat, tel: VideoTelemetry, s: VideoTelemetrySample, coords: Bool) {
        let box = CGRect(x: 40 * u, y: 150 * u, width: 340 * u, height: 260 * u)
        if coords, s.lat.isFinite { text(coordText(s.lat, s.lon), CGPoint(x: box.minX, y: box.minY - 18 * u), size: 24 * u, weight: .semibold) }
        let n = min(tel.routeX.count, tel.routeY.count)
        guard n > 1 else { return }
        let side = min(box.width, box.height)
        func pt(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: box.minX + CGFloat(x) * side, y: box.minY + side - CGFloat(y) * side + (box.height - side) / 2)
        }
        cg.setLineCap(.round); cg.setLineJoin(.round)
        let path = CGMutablePath()
        path.move(to: pt(tel.routeX[0], tel.routeY[0]))
        for i in 1..<n { path.addLine(to: pt(tel.routeX[i], tel.routeY[i])) }
        cg.addPath(path); cg.setStrokeColor(UIColor(white: 0, alpha: 0.5).cgColor); cg.setLineWidth(8 * u); cg.strokePath()
        cg.addPath(path); cg.setStrokeColor(UIColor(red: 1, green: 0.77, blue: 0.17, alpha: 1).cgColor); cg.setLineWidth(4.5 * u); cg.strokePath()
        let st = pt(tel.routeX[0], tel.routeY[0])
        cg.setFillColor(UIColor(red: 0.32, green: 0.87, blue: 0.25, alpha: 1).cgColor)
        cg.fillEllipse(in: CGRect(x: st.x - 8 * u, y: st.y - 8 * u, width: 16 * u, height: 16 * u))
        if s.lat.isFinite {
            let (x, y) = tel.routePoint(lat: s.lat, lon: s.lon)
            let p = pt(x, y)
            cg.setFillColor(UIColor.white.cgColor)
            cg.fillEllipse(in: CGRect(x: p.x - 12 * u, y: p.y - 12 * u, width: 24 * u, height: 24 * u))
            cg.setFillColor(UIColor(red: 0.93, green: 0.07, blue: 0.16, alpha: 1).cgColor)
            cg.fillEllipse(in: CGRect(x: p.x - 8 * u, y: p.y - 8 * u, width: 16 * u, height: 16 * u))
        }
    }

    private static func compass(_ cg: CGContext, center c: CGPoint, r: CGFloat, heading: Double, u: CGFloat) {
        let hd = heading.isFinite ? heading : 0
        cg.setFillColor(UIColor(white: 0, alpha: 0.3).cgColor)
        cg.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        cg.setStrokeColor(UIColor(white: 1, alpha: 0.9).cgColor)
        // la rosa gira: el rumbo del caballo queda arriba
        for d in stride(from: 0, to: 360, by: 10) {
            let a = (Double(d) - hd - 90) * .pi / 180
            let len: CGFloat = d % 30 == 0 ? 18 * u : 9 * u
            cg.setLineWidth(d % 30 == 0 ? 3 * u : 1.5 * u)
            cg.move(to: CGPoint(x: c.x + (r - len) * CGFloat(cos(a)), y: c.y + (r - len) * CGFloat(sin(a))))
            cg.addLine(to: CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a))))
            cg.strokePath()
        }
        for (d, l) in [(0, "N"), (90, "E"), (180, "S"), (270, "O")] {
            let a = (Double(d) - hd - 90) * .pi / 180
            text(l, CGPoint(x: c.x + (r - 40 * u) * CGFloat(cos(a)), y: c.y + (r - 40 * u) * CGFloat(sin(a))), size: 26 * u,
                 weight: .bold, align: .center, color: d == 0 ? UIColor(red: 1, green: 0.29, blue: 0.35, alpha: 1) : .white)
        }
        // flecha del rumbo
        cg.setFillColor(UIColor(red: 0.93, green: 0.07, blue: 0.16, alpha: 0.95).cgColor)
        cg.move(to: CGPoint(x: c.x, y: c.y - r * 0.62))
        cg.addLine(to: CGPoint(x: c.x + r * 0.2, y: c.y + r * 0.3))
        cg.addLine(to: CGPoint(x: c.x, y: c.y + r * 0.15))
        cg.addLine(to: CGPoint(x: c.x - r * 0.2, y: c.y + r * 0.3))
        cg.closePath(); cg.fillPath()
        text(heading.isFinite ? String(format: "%.0f°", hd) : "—", CGPoint(x: c.x, y: c.y), size: 34 * u, weight: .bold, align: .center)
    }

    private static func speedometer(_ cg: CGContext, center c: CGPoint, r: CGFloat, value: Double, maxV: Double, u: CGFloat) {
        // arco de 240°: 0 abajo a la izquierda, máximo abajo a la derecha
        let a0 = 150.0, sweep = 240.0
        func ang(_ v: Double) -> Double { (a0 + sweep * min(max(v / maxV, 0), 1)) * .pi / 180 }
        cg.setFillColor(UIColor(white: 0, alpha: 0.3).cgColor)
        cg.fillEllipse(in: CGRect(x: c.x - r - 10 * u, y: c.y - r - 10 * u, width: 2 * r + 20 * u, height: 2 * r + 20 * u))
        cg.setStrokeColor(UIColor(white: 1, alpha: 0.95).cgColor)
        let major = 10.0
        let steps = Int(maxV / major * 5)
        for i in 0...steps {
            let v = maxV * Double(i) / Double(steps)
            let a = ang(v)
            let isMajor = i % 5 == 0
            let len: CGFloat = isMajor ? 28 * u : 14 * u
            cg.setLineWidth(isMajor ? 4 * u : 2 * u)
            cg.move(to: CGPoint(x: c.x + (r - len) * CGFloat(cos(a)), y: c.y + (r - len) * CGFloat(sin(a))))
            cg.addLine(to: CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a))))
            cg.strokePath()
            if isMajor {
                text(String(format: "%.0f", v), CGPoint(x: c.x + (r - 58 * u) * CGFloat(cos(a)), y: c.y + (r - 58 * u) * CGFloat(sin(a))),
                     size: 26 * u, weight: .semibold, align: .center)
            }
        }
        text("km/h", CGPoint(x: c.x, y: c.y - r * 0.35), size: 26 * u, weight: .semibold, align: .center)
        if value.isFinite {
            let a = ang(value)
            cg.setStrokeColor(UIColor(red: 0.93, green: 0.07, blue: 0.16, alpha: 1).cgColor)
            cg.setLineWidth(7 * u); cg.setLineCap(.round)
            cg.move(to: CGPoint(x: c.x + 20 * u * CGFloat(cos(a)), y: c.y + 20 * u * CGFloat(sin(a))))
            cg.addLine(to: CGPoint(x: c.x + (r - 22 * u) * CGFloat(cos(a)), y: c.y + (r - 22 * u) * CGFloat(sin(a))))
            cg.strokePath()
        }
        text(value.isFinite ? String(format: "%.0f", value) : "—", CGPoint(x: c.x, y: c.y + r * 0.42), size: 76 * u,
             weight: .heavy, align: .center, mono: true)
    }
}
