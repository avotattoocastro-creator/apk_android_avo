import SwiftUI
import UIKit
import MapKit
import Observation

/// Colour of the route (Windows Controls/MapControl.cs RouteColorMode, without `Single`, which is only used for comparisons).
enum RouteColorMode: String, CaseIterable, Identifiable {
    case speed = "Speed"
    case acceleration = "Acceleration"
    case gnssQuality = "GnssQuality"
    case gait = "Gait"

    var id: String { rawValue }

    /// Radio button text of the Windows map page.
    var title: String {
        switch self {
        case .speed: return "Velocidad"
        case .acceleration: return "Aceleración"
        case .gnssQuality: return "Calidad GNSS"
        case .gait: return "Aire (motor)"
        }
    }
}

/// Map page model = MainViewModel.cs (MapProvider, ColorMode, LegendTitle, TileCacheDir) + the route preparation that
/// Windows MapControl does in OnTracksChanged/DrawTrack. The coloured route is precomputed ONCE per session and colour
/// mode (`RouteRenderData`), off the main thread; drawing only culls and strokes ready-made paths.
@Observable
final class MapModel {
    unowned let app: AppModel

    /// Base layer, persisted in the settings (Windows MainViewModel.MapProvider setter).
    var provider: MapProvider {
        didSet {
            if provider == oldValue { return }
            app.settings.map = provider
            do { try app.settings.save(app.paths.settingsFile) } catch { app.log.warn("ajustes", error.localizedDescription, error) }
        }
    }

    var colorMode: RouteColorMode = .speed {
        didSet { if colorMode != oldValue { requestRoute() } }
    }

    /// «Inicio / final» check box of the Windows layers panel.
    var showMarkers: Bool = true

    /// Route ready to draw for the selected session and colour mode (nil = no route / still building).
    private(set) var route: RouteRenderData? = nil
    private(set) var building: Bool = false

    @ObservationIgnored private var cache: [RouteColorMode: RouteRenderData] = [:]
    @ObservationIgnored private var generation: Int = 0

    var legendTitle: String {
        switch colorMode {
        case .speed: return "Velocidad (km/h)"
        case .acceleration: return "Aceleración longitudinal (m/s²)"
        case .gnssQuality: return "Calidad GNSS"
        case .gait: return "Aire (motor AVO)"
        }
    }

    /// Windows TileCacheDir.
    var tileCacheDir: String { app.paths.tiles }

    /// Centre used when there is no route (Windows MapControl.HomeLatitude/HomeLongitude = training place of the settings).
    var home: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: app.settings.placeLatitude, longitude: app.settings.placeLongitude)
    }

    /// True when the gait colouring has engine data behind it.
    var hasGait: Bool {
        guard let s = app.selected, let e = s.engine else { return false }
        return e.hasImu
    }

    init(app: AppModel) {
        self.app = app
        self.provider = app.settings.map
    }

    func sessionChanged() {
        cache.removeAll()
        route = nil
        requestRoute()
    }

    func pageShown() {
        if route == nil { requestRoute() }
    }

    /// Builds (or takes from the cache) the route of the selected session in the current colour mode.
    func requestRoute() {
        generation += 1
        let gen: Int = generation
        guard let s = app.selected, s.timeline.count >= 2 else {
            route = nil
            building = false
            return
        }
        let mode: RouteColorMode = colorMode
        if let cached = cache[mode] {
            route = cached
            building = false
            return
        }
        building = true
        let tl: SessionTimeline = s.timeline
        let gait: [Int] = s.gaitByIndex
        let sessionKey: String = s.session.sessionId
        var markerTimes: [(t: Double, title: String)] = []
        if s.imu.aligned {
            for m in s.session.markers {
                let t: Double = Double(m.chestUs) / 1e6 - s.imu.offsetS
                markerTimes.append((t: t, title: "Marcador \(m.count) · \(m.sourceName)"))
            }
        }
        let markers: [(t: Double, title: String)] = markerTimes
        Task.detached(priority: .userInitiated) { [weak self] in
            let data: RouteRenderData = RouteRenderData.build(tl, mode: mode, gait: gait, sessionKey: sessionKey, markers: markers)
            await MainActor.run {
                guard let self = self, self.generation == gen else { return }
                self.cache[mode] = data
                self.route = data
                self.building = false
            }
        }
    }
}

// MARK: - Colours

extension SpeedScale {
    static func mapUIColor(_ c: AvoRGB, alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: alpha)
    }

    static func mapColor(_ c: AvoRGB) -> Color {
        Color(.sRGB, red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255, opacity: 1)
    }
}

// MARK: - Precomputed route geometry

/// One stroke-able piece of the route: a path (in coordinates relative to `RouteRenderData.origin`) with its bounding map
/// rectangle, used to cull pieces outside the tile being drawn.
struct RouteChunk {
    let key: Int
    let rect: MKMapRect
    let path: CGPath
}

/// Point shown over the route (start, end, session markers).
struct RouteMarker {
    enum Kind { case start, end, marker }
    let kind: Kind
    let coordinate: CLLocationCoordinate2D
    let title: String
}

/// Immutable, thread-safe route of one session in one colour mode (built in background).
final class RouteRenderData {
    let id: UUID = UUID()
    let sessionKey: String
    let mode: RouteColorMode
    /// Projected positions (Web Mercator map points), one per timeline sample.
    let points: [MKMapPoint]
    let t: [Double]
    /// Segment i-1 → i is drawn (no gap, no rejected jump).
    let drawable: [Bool]
    /// Colour key of segment i-1 → i.
    let keys: [Int]
    let palette: [Int: UIColor]
    /// Origin of the path coordinates (top-left of `bounds`).
    let origin: MKMapPoint
    /// Area covered by the route, inflated for the line widths.
    let bounds: MKMapRect
    /// Tight bounding box of the positions (for "fit").
    let routeRect: MKMapRect
    let colored: [RouteChunk]
    let casing: [RouteChunk]
    /// Signal losses (gaps between usable epochs), drawn dashed.
    let gaps: [RouteChunk]
    let markers: [RouteMarker]
    let maxSpeedKmh: Double

    private init(sessionKey: String, mode: RouteColorMode, points: [MKMapPoint], t: [Double], drawable: [Bool], keys: [Int],
                 palette: [Int: UIColor], origin: MKMapPoint, bounds: MKMapRect, routeRect: MKMapRect, colored: [RouteChunk],
                 casing: [RouteChunk], gaps: [RouteChunk], markers: [RouteMarker], maxSpeedKmh: Double) {
        self.sessionKey = sessionKey; self.mode = mode; self.points = points; self.t = t; self.drawable = drawable; self.keys = keys
        self.palette = palette; self.origin = origin; self.bounds = bounds; self.routeRect = routeRect; self.colored = colored
        self.casing = casing; self.gaps = gaps; self.markers = markers; self.maxSpeedKmh = maxSpeedKmh
    }

    static let bins: Int = 24
    static let maxChunkSegments: Int = 300

    /// Port of MapControl.DrawTrack colour keys (24 bins of the speed / acceleration scales, solution, gait).
    static func build(_ tl: SessionTimeline, mode: RouteColorMode, gait: [Int], sessionKey: String,
                      markers markerTimes: [(t: Double, title: String)]) -> RouteRenderData {
        let n: Int = tl.count
        var pts: [MKMapPoint] = [MKMapPoint](repeating: MKMapPoint(x: 0, y: 0), count: n)
        var minX: Double = Double.greatestFiniteMagnitude
        var minY: Double = Double.greatestFiniteMagnitude
        var maxX: Double = -Double.greatestFiniteMagnitude
        var maxY: Double = -Double.greatestFiniteMagnitude
        for i in 0..<n {
            let p: MKMapPoint = MKMapPoint(CLLocationCoordinate2D(latitude: tl.lat[i], longitude: tl.lon[i]))
            pts[i] = p
            if p.x < minX { minX = p.x }
            if p.x > maxX { maxX = p.x }
            if p.y < minY { minY = p.y }
            if p.y > maxY { maxY = p.y }
        }
        if n == 0 { minX = 0; minY = 0; maxX = 1; maxY = 1 }
        let routeRect: MKMapRect = MKMapRect(x: minX, y: minY, width: max(maxX - minX, 1), height: max(maxY - minY, 1))
        let margin: Double = max(routeRect.width, routeRect.height) * 0.05 + 2000
        let bounds: MKMapRect = routeRect.insetBy(dx: -margin, dy: -margin)
        let origin: MKMapPoint = bounds.origin

        var drawable: [Bool] = [Bool](repeating: false, count: n)
        var gapSeg: [Bool] = [Bool](repeating: false, count: n)
        for i in 1..<max(n, 1) {
            drawable[i] = !tl.breakBefore[i] && !tl.jumpBefore[i]
            gapSeg[i] = tl.breakBefore[i]
        }

        let vmax: Double = max(0.1, Stats.maxFinite(tl.speedFiltered, fallback: 0.1))
        let amax: Double = 2.0
        let binsM1: Double = Double(bins - 1)
        var keys: [Int] = [Int](repeating: 0, count: n)
        var palette: [Int: UIColor] = [:]
        for i in 0..<n {
            var key: Int = 0
            var rgb: AvoRGB = (r: 0x3D, g: 0x9B, b: 0xFF)
            switch mode {
            case .speed:
                let v: Double = tl.speedFiltered[i]
                let f: Double = v.isFinite ? min(max(v / vmax, 0), 1) : 0
                let b: Int = Int((f * binsM1).rounded(.toNearestOrEven))
                key = b
                rgb = SpeedScale.color(Double(b) / binsM1, 1)
            case .acceleration:
                let a: Double = SegmentAnalyzer.accelValid(tl, i) ? tl.accelLong[i] : 0
                let c: Double = a.isFinite ? min(max(a / amax, -1), 1) : 0
                let b: Int = Int(((c + 1) / 2 * binsM1).rounded(.toNearestOrEven))
                key = 100 + b
                rgb = SpeedScale.diverging(Double(b) / binsM1 * 2 - 1, 1)
            case .gnssQuality:
                key = 200 + tl.solution[i].rawValue
                rgb = SpeedScale.solution(tl.solution[i])
            case .gait:
                let code: Int = i < gait.count ? gait[i] : -1
                key = 300 + code
                rgb = SpeedScale.gait(code)
            }
            keys[i] = key
            if palette[key] == nil { palette[key] = SpeedScale.mapUIColor(rgb) }
        }

        let colored: [RouteChunk] = RouteRenderData.chunks(pts, origin: origin, include: { (i: Int) -> Bool in drawable[i] },
                                                           keyOf: { (i: Int) -> Int in keys[i] })
        let casing: [RouteChunk] = RouteRenderData.chunks(pts, origin: origin, include: { (i: Int) -> Bool in drawable[i] },
                                                          keyOf: { (_: Int) -> Int in 0 })
        let gaps: [RouteChunk] = RouteRenderData.chunks(pts, origin: origin, include: { (i: Int) -> Bool in gapSeg[i] },
                                                        keyOf: { (_: Int) -> Int in 0 })

        var markers: [RouteMarker] = []
        if n > 0 {
            markers.append(RouteMarker(kind: .start, coordinate: pts[0].coordinate, title: "Inicio"))
            markers.append(RouteMarker(kind: .end, coordinate: pts[n - 1].coordinate, title: "Fin"))
            for m in markerTimes where m.t.isFinite && m.t >= tl.t[0] - 1 && m.t <= tl.t[n - 1] + 1 {
                let i: Int = tl.indexAt(m.t)
                if i >= 0 { markers.append(RouteMarker(kind: .marker, coordinate: pts[i].coordinate, title: m.title)) }
            }
        }
        return RouteRenderData(sessionKey: sessionKey, mode: mode, points: pts, t: tl.t, drawable: drawable, keys: keys,
                               palette: palette, origin: origin, bounds: bounds, routeRect: routeRect, colored: colored,
                               casing: casing, gaps: gaps, markers: markers, maxSpeedKmh: vmax * 3.6)
    }

    /// Groups consecutive drawable segments of the same key into paths of at most `maxChunkSegments` segments.
    static func chunks(_ pts: [MKMapPoint], origin: MKMapPoint, include: (Int) -> Bool, keyOf: (Int) -> Int) -> [RouteChunk] {
        final class Open {
            let path: CGMutablePath = CGMutablePath()
            var last: Int = -2
            var count: Int = 0
            var minX: Double = Double.greatestFiniteMagnitude
            var minY: Double = Double.greatestFiniteMagnitude
            var maxX: Double = -Double.greatestFiniteMagnitude
            var maxY: Double = -Double.greatestFiniteMagnitude
            func extend(_ p: MKMapPoint) {
                if p.x < minX { minX = p.x }
                if p.x > maxX { maxX = p.x }
                if p.y < minY { minY = p.y }
                if p.y > maxY { maxY = p.y }
            }
        }
        var out: [RouteChunk] = []
        var open: [Int: Open] = [:]
        func flush(_ key: Int, _ o: Open) {
            if o.count == 0 { return }
            let rect: MKMapRect = MKMapRect(x: o.minX, y: o.minY, width: max(o.maxX - o.minX, 1), height: max(o.maxY - o.minY, 1))
            out.append(RouteChunk(key: key, rect: rect, path: o.path.copy() ?? o.path))
        }
        let n: Int = pts.count
        if n < 2 { return out }
        for i in 1..<n {
            if !include(i) { continue }
            let key: Int = keyOf(i)
            var o: Open
            if let existing = open[key] { o = existing } else { o = Open(); open[key] = o }
            if o.count >= maxChunkSegments {
                flush(key, o)
                o = Open()
                open[key] = o
            }
            let a: MKMapPoint = pts[i - 1]
            let b: MKMapPoint = pts[i]
            if o.last != i - 1 {
                o.path.move(to: CGPoint(x: a.x - origin.x, y: a.y - origin.y))
                o.extend(a)
            }
            o.path.addLine(to: CGPoint(x: b.x - origin.x, y: b.y - origin.y))
            o.extend(b)
            o.last = i
            o.count += 1
        }
        for key in open.keys.sorted() {
            if let o = open[key] { flush(key, o) }
        }
        return out
    }

    /// Highlighted part of the route for a selected range [lo, hi] (Windows: only the range keeps its colours).
    func rangeChunks(_ lo: Double, _ hi: Double) -> [RouteChunk] {
        let tt: [Double] = t
        let dr: [Bool] = drawable
        let ks: [Int] = keys
        return RouteRenderData.chunks(points, origin: origin, include: { (i: Int) -> Bool in
            dr[i] && tt[i] >= lo && tt[i] <= hi
        }, keyOf: { (i: Int) -> Int in ks[i] })
    }

    /// Index of the sample nearest to time (binary search), -1 if empty.
    func indexAt(_ time: Double) -> Int {
        if t.isEmpty || !time.isFinite { return -1 }
        var i: Int = SessionTimeline.binarySearch(t, time)
        if i >= 0 { return i }
        i = ~i
        if i <= 0 { return 0 }
        if i >= t.count { return t.count - 1 }
        return time - t[i - 1] <= t[i] - time ? i - 1 : i
    }

    /// Nearest sample to a map point within `maxDistance` map points (-1 if none).
    func nearestIndex(to p: MKMapPoint, maxDistance: Double) -> Int {
        var best: Int = -1
        var bestD: Double = maxDistance * maxDistance
        for i in 0..<points.count {
            let dx: Double = points[i].x - p.x
            let dy: Double = points[i].y - p.y
            let d: Double = dx * dx + dy * dy
            if d < bestD { bestD = d; best = i }
        }
        return best
    }
}
