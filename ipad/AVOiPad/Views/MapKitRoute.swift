import SwiftUI
import UIKit
import MapKit

/// One-shot command for a map (zoom buttons, fit). A new `id` triggers it once.
struct RouteMapCommand: Equatable {
    enum Kind: Equatable { case none, zoomIn, zoomOut, fit }
    var id: Int = 0
    var kind: Kind = .none

    func next(_ kind: Kind) -> RouteMapCommand { RouteMapCommand(id: id + 1, kind: kind) }
}

/// Start / finish line of a training course drawn on the map (with an arrow in the counting direction).
struct MapCourseLine: Equatable, Identifiable {
    var id: String
    var title: String
    var colorHex: UInt32
    /// The line itself and, optionally, the arrow (shaft + two barbs), as (lat, lon) pairs.
    var line: [[Double]]
    var arrow: [[[Double]]] = []
}

/// MKPolyline of a course line (own colour and width).
final class CourseLineOverlay: MKPolyline {
    var color: UIColor = .white
    var width: CGFloat = 5
}

/// Label of a course line (title next to it).
final class CourseLabelAnnotation: MKPointAnnotation {
    var color: UIColor = .white
}

/// MKMapView wrapper = port of Windows Controls/MapControl.cs: Esri imagery / hybrid tiles cached on disk, offline vector
/// mode (dark grid, route only), coloured route, dimmed route outside the selected range, dashed signal losses, start/end
/// and session markers, cursor marker following the shared cursor, tap = nearest route point.
struct MapKitRoute: UIViewRepresentable {
    var data: RouteRenderData?
    var provider: MapProvider
    var tileCacheDir: String
    var cursorTime: Double
    var rangeStart: Double
    var rangeEnd: Double
    var showMarkers: Bool
    var fitPadding: UIEdgeInsets = UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40)
    var home: CLLocationCoordinate2D
    var command: RouteMapCommand = RouteMapCommand()
    /// Start / finish lines of the training (Análisis zones).
    var courseLines: [MapCourseLine] = []
    /// true = «Ajustar» gira el mapa para que el recorrido (la playa) quede en horizontal; false = norte arriba.
    var alignRoute: Bool = true
    /// Fixed marker at the maximum speed: time on the timeline and its label («Vmáx 51,1 km/h»).
    var vmaxTime: Double = .nan
    var vmaxLabel: String = ""
    var onTap: (Double) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> RouteMapView {
        let map = RouteMapView(frame: .zero)
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = .dark
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = true
        map.showsScale = true
        map.isRotateEnabled = true   // giro con dos dedos; «Ajustar» orienta el recorrido en horizontal
        map.isPitchEnabled = false
        map.backgroundColor = UIColor(red: 0x0B / 255.0, green: 0x0C / 255.0, blue: 0x10 / 255.0, alpha: 1)
        map.cameraZoomRange = MKMapView.CameraZoomRange(minCenterCoordinateDistance: 120)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.numberOfTapsRequired = 1
        map.addGestureRecognizer(tap)
        context.coordinator.map = map
        context.coordinator.lastCommandId = command.id
        context.coordinator.onTap = onTap
        context.coordinator.applyProvider(provider, cacheDir: tileCacheDir)
        context.coordinator.home = home
        context.coordinator.fitPadding = fitPadding
        context.coordinator.alignRoute = alignRoute
        map.pendingFit = { [weak coordinator = context.coordinator] in coordinator?.fit(animated: false) }
        return map
    }

    func updateUIView(_ map: RouteMapView, context: Context) {
        let c: Coordinator = context.coordinator
        c.onTap = onTap
        c.home = home
        c.fitPadding = fitPadding
        c.applyProvider(provider, cacheDir: tileCacheDir)
        c.applyRoute(data)
        c.applyMarkers(showMarkers)
        c.applyRange(rangeStart, rangeEnd)
        c.applyCursor(cursorTime)
        c.applyVmax(vmaxTime, vmaxLabel)
        c.applyCourseLines(courseLines)
        if c.alignRoute != alignRoute {
            c.alignRoute = alignRoute
            c.fit(animated: true)
        }
        if command.id != c.lastCommandId {
            c.lastCommandId = command.id
            switch command.kind {
            case .zoomIn: c.zoom(by: 0.5)
            case .zoomOut: c.zoom(by: 2)
            case .fit: c.fit(animated: true)
            case .none: break
            }
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        weak var map: RouteMapView?
        var onTap: ((Double) -> Void)?
        var home: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 43.45, longitude: -3.46)
        var fitPadding: UIEdgeInsets = UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40)
        var lastCommandId: Int = 0
        var alignRoute: Bool = true

        private var provider: MapProvider? = nil
        private var tileOverlays: [MKTileOverlay] = []
        private var routeOverlay: RouteOverlay? = nil
        private var routeRenderer: RouteOverlayRenderer? = nil
        private var dataId: UUID? = nil
        private var sessionKey: String? = nil
        private var data: RouteRenderData? = nil
        private var markerAnnotations: [RouteMarkerAnnotation] = []
        private var markersShown: Bool = true
        private var cursor: RouteMarkerAnnotation? = nil
        private var cursorIndex: Int = -2
        private var rangeLo: Double = .nan
        private var rangeHi: Double = .nan
        private var courseLines: [MapCourseLine] = []
        private var courseOverlays: [CourseLineOverlay] = []
        private var courseLabels: [CourseLabelAnnotation] = []

        // ------------------------------------------------------------ max speed marker
        private var vmax: VmaxAnnotation? = nil
        private var vmaxKey: String = ""

        func applyVmax(_ time: Double, _ label: String) {
            guard let map = map else { return }
            let i: Int = time.isFinite ? (data?.indexAt(time) ?? -1) : -1
            let key: String = "\(dataId?.uuidString ?? "")|\(i)|\(label)"
            if key == vmaxKey { return }
            vmaxKey = key
            if let v = vmax { map.removeAnnotation(v) }
            vmax = nil
            guard let d = data, i >= 0, i < d.points.count else { return }
            let a = VmaxAnnotation()
            a.coordinate = d.points[i].coordinate
            a.title = label
            vmax = a
            map.addAnnotation(a)
        }

        // ------------------------------------------------------------ course lines (start / finish)
        func applyCourseLines(_ lines: [MapCourseLine]) {
            guard let map = map, lines != courseLines else { return }
            courseLines = lines
            map.removeOverlays(courseOverlays)
            map.removeAnnotations(courseLabels)
            courseOverlays = []
            courseLabels = []
            for l in lines {
                let color = UIColor(red: CGFloat((l.colorHex >> 16) & 0xFF) / 255, green: CGFloat((l.colorHex >> 8) & 0xFF) / 255,
                                    blue: CGFloat(l.colorHex & 0xFF) / 255, alpha: 1)
                func poly(_ pts: [[Double]], _ width: CGFloat) {
                    let coords: [CLLocationCoordinate2D] = pts.filter { $0.count == 2 }.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) }
                    guard coords.count >= 2 else { return }
                    let o = CourseLineOverlay(coordinates: coords, count: coords.count)
                    o.color = color
                    o.width = width
                    courseOverlays.append(o)
                }
                poly(l.line, 5)
                for a in l.arrow { poly(a, 3) }
                if l.line.count >= 2, l.line[0].count == 2 {
                    let lab = CourseLabelAnnotation()
                    lab.coordinate = CLLocationCoordinate2D(latitude: l.line[0][0], longitude: l.line[0][1])
                    lab.title = l.title
                    lab.color = color
                    courseLabels.append(lab)
                }
            }
            for o in courseOverlays { map.addOverlay(o, level: .aboveLabels) }
            map.addAnnotations(courseLabels)
        }

        // ------------------------------------------------------------ base layer
        func applyProvider(_ p: MapProvider, cacheDir: String) {
            guard let map = map, p != provider else { return }
            provider = p
            map.removeOverlays(tileOverlays)
            var layers: [MKTileOverlay] = []
            switch p {
            case .esriSatellite:
                layers = [RouteEsriTileOverlay(layer: "World_Imagery", cacheDir: cacheDir)]
            case .esriHybrid:
                layers = [RouteEsriTileOverlay(layer: "World_Imagery", cacheDir: cacheDir),
                          RouteEsriTileOverlay(layer: "Reference/World_Transportation", cacheDir: cacheDir),
                          RouteEsriTileOverlay(layer: "Reference/World_Boundaries_and_Places", cacheDir: cacheDir)]
            case .vectorOffline:
                layers = [RouteOfflineGridOverlay()]
            }
            for (k, o) in layers.enumerated() { map.insertOverlay(o, at: k, level: .aboveLabels) }
            tileOverlays = layers
        }

        // ------------------------------------------------------------ route
        func applyRoute(_ d: RouteRenderData?) {
            guard let map = map else { return }
            if d?.id == dataId { return }
            dataId = d?.id
            data = d
            if let o = routeOverlay { map.removeOverlay(o) }
            routeOverlay = nil
            routeRenderer = nil
            map.removeAnnotations(markerAnnotations)
            markerAnnotations = []
            if let c = cursor { map.removeAnnotation(c) }
            cursor = nil
            cursorIndex = -2
            guard let d = d else {
                if sessionKey != nil || !map.didInitialFit {
                    sessionKey = nil
                    fit(animated: false)
                }
                return
            }
            let o = RouteOverlay(data: d)
            routeOverlay = o
            map.addOverlay(o, level: .aboveLabels)
            for m in d.markers {
                let a = RouteMarkerAnnotation(kind: m.kind == .start ? .start : (m.kind == .end ? .end : .marker))
                a.coordinate = m.coordinate
                a.title = m.title
                markerAnnotations.append(a)
            }
            if markersShown { map.addAnnotations(markerAnnotations) }
            // a new session fits the view; a new colour mode of the same session keeps the user's view
            if d.sessionKey != sessionKey || !map.didInitialFit {
                sessionKey = d.sessionKey
                fit(animated: false)
            }
            rangeLo = .nan
            rangeHi = .nan
        }

        func applyMarkers(_ show: Bool) {
            guard let map = map, show != markersShown else { return }
            markersShown = show
            if show { map.addAnnotations(markerAnnotations) } else { map.removeAnnotations(markerAnnotations) }
        }

        func applyRange(_ a: Double, _ b: Double) {
            let ranged: Bool = a.isFinite && b.isFinite && abs(b - a) > 0.5
            let lo: Double = ranged ? min(a, b) : .nan
            let hi: Double = ranged ? max(a, b) : .nan
            let same: Bool = (lo == rangeLo || (lo.isNaN && rangeLo.isNaN)) && (hi == rangeHi || (hi.isNaN && rangeHi.isNaN))
            if same { return }
            rangeLo = lo
            rangeHi = hi
            guard let d = data else { return }
            let chunks: [RouteChunk]? = ranged ? d.rangeChunks(lo, hi) : nil
            if let r = routeRenderer {
                r.setRange(chunks)
            } else if let o = routeOverlay {
                o.pendingRange = chunks
            }
        }

        func applyCursor(_ time: Double) {
            guard let map = map else { return }
            let i: Int = data?.indexAt(time) ?? -1
            if i == cursorIndex { return }
            cursorIndex = i
            guard let d = data, i >= 0, i < d.points.count else {
                if let c = cursor { map.removeAnnotation(c) }
                cursor = nil
                return
            }
            let coord: CLLocationCoordinate2D = d.points[i].coordinate
            // Follow the cursor chosen on the charts / time bar: centre the map on it keeping the zoom and rotation.
            // Not for the first cursor of a route (keeps «Ajustar») nor when the point was tapped on the map itself.
            let follow: Bool = cursor != nil && !tappedOnMap && map.didInitialFit
            tappedOnMap = false
            if follow { centre(map, on: coord) }
            if let c = cursor {
                c.coordinate = coord
            } else {
                let c = RouteMarkerAnnotation(kind: .cursor)
                c.coordinate = coord
                cursor = c
                map.addAnnotation(c)
            }
        }

        /// The last cursor change came from a tap on the route (the map must not jump).
        private var tappedOnMap: Bool = false

        /// Centre on `coord` without touching the zoom (camera altitude) or the heading. Short moves (playback, dragging
        /// the cursor) are not animated so the map keeps up; jumps are.
        private func centre(_ map: MKMapView, on coord: CLLocationCoordinate2D) {
            guard CLLocationCoordinate2DIsValid(coord) else { return }
            let here: CGPoint = map.convert(coord, toPointTo: map)
            let mid: CGPoint = CGPoint(x: map.bounds.midX, y: map.bounds.midY)
            let jump: CGFloat = hypot(here.x - mid.x, here.y - mid.y)
            if jump < 2 { return }
            let cam: MKMapCamera = map.camera.copy() as? MKMapCamera ?? map.camera
            cam.centerCoordinate = coord
            map.setCamera(cam, animated: jump > min(map.bounds.width, map.bounds.height) * 0.25)
        }

        // ------------------------------------------------------------ view
        func fit(animated: Bool) {
            guard let map = map else { return }
            if map.bounds.width < 10 || map.bounds.height < 10 { map.fitWanted = true; return }
            map.fitWanted = false
            map.didInitialFit = true
            if let d = data, !d.points.isEmpty {
                fitRotated(map, d, animated: animated)
            } else {
                // No route: the usual training area (Windows: Playa del Regatón at zoom 14.5).
                let region = MKCoordinateRegion(center: home, latitudinalMeters: 2200, longitudinalMeters: 2200)
                map.setRegion(region, animated: animated)
            }
        }

        private func clampedPadding(_ map: MKMapView) -> UIEdgeInsets {
            var p: UIEdgeInsets = fitPadding
            let w: CGFloat = map.bounds.width
            let h: CGFloat = map.bounds.height
            if p.left + p.right > w * 0.7 { p.left = 20; p.right = 20 }
            if p.top + p.bottom > h * 0.7 { p.top = 20; p.bottom = 20 }
            return p
        }

        /// Zoom keeping the current rotation (setVisibleMapRect would not respect the heading).
        func zoom(by factor: Double) {
            guard let map = map, let cam = map.camera.copy() as? MKMapCamera else { return }
            cam.centerCoordinateDistance = max(120, cam.centerCoordinateDistance * factor)
            map.setCamera(cam, animated: true)
        }

        /// Main direction of the route (principal axis of the positions, Web Mercator) as an angle from east towards
        /// south (radians), or nil when the route has no clear direction (round course, too few points).
        static func routeAxis(_ pts: [MKMapPoint]) -> Double? {
            let n: Int = pts.count
            if n < 3 { return nil }
            let step: Int = max(1, n / 3000)
            var sx: Double = 0, sy: Double = 0, k: Double = 0
            var i: Int = 0
            while i < n {
                let p: MKMapPoint = pts[i]
                if p.x.isFinite && p.y.isFinite { sx += p.x; sy += p.y; k += 1 }
                i += step
            }
            if k < 3 { return nil }
            let mx: Double = sx / k, my: Double = sy / k
            var cxx: Double = 0, cyy: Double = 0, cxy: Double = 0
            i = 0
            while i < n {
                let p: MKMapPoint = pts[i]
                if p.x.isFinite && p.y.isFinite {
                    let dx: Double = p.x - mx, dy: Double = p.y - my
                    cxx += dx * dx; cyy += dy * dy; cxy += dx * dy
                }
                i += step
            }
            let tr: Double = cxx + cyy
            let det: Double = cxx * cyy - cxy * cxy
            let disc: Double = sqrt(max(0, tr * tr / 4 - det))
            let l1: Double = tr / 2 + disc, l2: Double = tr / 2 - disc
            if l1 <= 0 || l1 < 1.6 * max(l2, 1e-9) { return nil }
            return 0.5 * atan2(2 * cxy, cxx - cyy)
        }

        /// Camera heading (degrees, 0 = north up) that puts the route axis horizontal, choosing the orientation that is
        /// closest to north up (the sea of the Regatón stays at the top).
        static func horizontalHeading(axis theta: Double) -> Double {
            // axis direction: east = cos θ, north = −sin θ → bearing β; screen-up = β − 90°
            let beta: Double = atan2(cos(theta), -sin(theta)) * 180 / .pi
            var h: Double = beta - 90
            while h > 90 { h -= 180 }
            while h <= -90 { h += 180 }
            return h < 0 ? h + 360 : h
        }

        /// Fit the route with a given heading: extent measured along / across the screen axes, padding kept, then the
        /// camera distance taken from an equivalent north-up rect.
        private func fitRotated(_ map: MKMapView, _ d: RouteRenderData, animated: Bool) {
            let theta: Double? = alignRoute ? Coordinator.routeAxis(d.points) : nil
            let heading: Double = theta.map { Coordinator.horizontalHeading(axis: $0) } ?? 0
            let hr: Double = heading * .pi / 180
            // screen right / down as Web Mercator vectors (x east, y south)
            let rx: Double = cos(hr), ry: Double = sin(hr)
            let dxv: Double = -sin(hr), dyv: Double = cos(hr)
            var uMin: Double = .infinity, uMax: Double = -.infinity, vMin: Double = .infinity, vMax: Double = -.infinity
            let c0: MKMapPoint = MKMapPoint(x: d.routeRect.midX, y: d.routeRect.midY)
            let step: Int = max(1, d.points.count / 4000)
            var i: Int = 0
            while i < d.points.count {
                let p: MKMapPoint = d.points[i]
                if p.x.isFinite && p.y.isFinite {
                    let ox: Double = p.x - c0.x, oy: Double = p.y - c0.y
                    let u: Double = ox * rx + oy * ry
                    let v: Double = ox * dxv + oy * dyv
                    uMin = min(uMin, u); uMax = max(uMax, u); vMin = min(vMin, v); vMax = max(vMax, v)
                }
                i += step
            }
            if !uMin.isFinite || !vMin.isFinite { return }
            let minSize: Double = 300 * MKMapPointsPerMeterAtLatitude(c0.coordinate.latitude)
            let w: Double = max(uMax - uMin, minSize), h: Double = max(vMax - vMin, minSize)
            let pad: UIEdgeInsets = clampedPadding(map)
            let bw: Double = Double(map.bounds.width), bh: Double = Double(map.bounds.height)
            let availW: Double = max(40, bw - Double(pad.left + pad.right))
            let availH: Double = max(40, bh - Double(pad.top + pad.bottom))
            let mpp: Double = max(w / availW, h / availH)
            // route centre in the rotated frame, shifted so the route sits inside the padded area
            let um: Double = (uMin + uMax) / 2 + Double(pad.right - pad.left) / 2 * mpp
            let vm: Double = (vMin + vMax) / 2 + Double(pad.bottom - pad.top) / 2 * mpp
            let centre = MKMapPoint(x: c0.x + um * rx + vm * dxv, y: c0.y + um * ry + vm * dyv)
            // camera distance of the equivalent north-up view
            let old: MKMapCamera? = map.camera.copy() as? MKMapCamera
            if let flat = map.camera.copy() as? MKMapCamera {
                flat.heading = 0
                flat.pitch = 0
                map.setCamera(flat, animated: false)
            }
            map.setVisibleMapRect(MKMapRect(x: centre.x - mpp * bw / 2, y: centre.y - mpp * bh / 2, width: mpp * bw, height: mpp * bh),
                                  animated: false)
            let distance: Double = map.camera.centerCoordinateDistance
            let target = MKMapCamera(lookingAtCenter: centre.coordinate, fromDistance: distance, pitch: 0, heading: heading)
            if animated, let o = old {
                map.setCamera(o, animated: false)
                map.setCamera(target, animated: true)
            } else {
                map.setCamera(target, animated: false)
            }
        }

        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard let map = map, let d = data, g.state == .ended else { return }
            let pt: CGPoint = g.location(in: map)
            let coord: CLLocationCoordinate2D = map.convert(pt, toCoordinateFrom: map)
            let mp: MKMapPoint = MKMapPoint(coord)
            let zoomScale: Double = map.bounds.width > 0 ? Double(map.bounds.width) / map.visibleMapRect.width : 1
            let maxD: Double = 44 / max(zoomScale, 1e-12)
            let i: Int = d.nearestIndex(to: mp, maxDistance: maxD)
            if i >= 0 && i < d.t.count {
                tappedOnMap = true
                onTap?(d.t[i])
            }
        }

        // ------------------------------------------------------------ delegate
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let o = overlay as? RouteOverlay {
                let r = RouteOverlayRenderer(overlay: o)
                if o === routeOverlay {
                    routeRenderer = r
                    if let pending = o.pendingRange { r.setRange(pending) }
                    else if rangeLo.isFinite && rangeHi.isFinite { r.setRange(o.data.rangeChunks(rangeLo, rangeHi)) }
                }
                return r
            }
            if let l = overlay as? CourseLineOverlay {
                let r = MKPolylineRenderer(polyline: l)
                r.strokeColor = l.color
                r.lineWidth = l.width
                r.lineCap = .round
                return r
            }
            if let t = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: t)
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let lab = annotation as? CourseLabelAnnotation {
                let reuse: String = "course.label"
                let v = (mapView.dequeueReusableAnnotationView(withIdentifier: reuse) as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: lab, reuseIdentifier: reuse)
                v.annotation = lab
                v.markerTintColor = lab.color
                v.glyphImage = UIImage(systemName: "flag.fill")
                v.titleVisibility = .visible
                v.displayPriority = .required
                return v
            }
            if let vm = annotation as? VmaxAnnotation {
                let reuse: String = "route.vmax"
                let v = (mapView.dequeueReusableAnnotationView(withIdentifier: reuse) as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: vm, reuseIdentifier: reuse)
                v.annotation = vm
                v.markerTintColor = UIColor(red: 1, green: 0x8A / 255.0, blue: 0, alpha: 1)
                v.glyphImage = UIImage(systemName: "bolt.fill")
                v.titleVisibility = .visible
                v.displayPriority = .required
                v.zPriority = .defaultSelected
                return v
            }
            guard let a = annotation as? RouteMarkerAnnotation else { return nil }
            let reuse: String = "route.\(a.kind.rawValue)"
            let v: MKAnnotationView = mapView.dequeueReusableAnnotationView(withIdentifier: reuse)
                ?? MKAnnotationView(annotation: a, reuseIdentifier: reuse)
            v.annotation = a
            v.canShowCallout = a.kind == .marker
            v.collisionMode = .circle
            v.displayPriority = .required
            let img: UIImage = RouteMarkerImages.image(a.kind, label: a.kind == .marker ? nil : a.title)
            v.image = img
            // the dot (left part of the image) sits on the coordinate
            v.centerOffset = CGPoint(x: img.size.width / 2 - RouteMarkerImages.dotRadius(a.kind) - 2, y: 0)
            v.zPriority = a.kind == .cursor ? .max : .defaultUnselected
            return v
        }
    }
}

/// MKMapView that runs a pending fit once it has a size.
final class RouteMapView: MKMapView {
    var fitWanted: Bool = true
    var didInitialFit: Bool = false
    var pendingFit: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        if fitWanted && bounds.width >= 10 && bounds.height >= 10 {
            fitWanted = false
            let f = pendingFit
            DispatchQueue.main.async { f?() }
        }
    }
}

// MARK: - Route overlay + renderer

final class RouteOverlay: NSObject, MKOverlay {
    let data: RouteRenderData
    var pendingRange: [RouteChunk]? = nil

    init(data: RouteRenderData) { self.data = data }

    var coordinate: CLLocationCoordinate2D { MKMapPoint(x: data.bounds.midX, y: data.bounds.midY).coordinate }
    var boundingMapRect: MKMapRect { data.bounds }
}

/// Draws the precomputed chunks: black casing, then (with a range) the dimmed route and the highlighted range in colour,
/// otherwise the coloured route; signal losses dashed on top. Only chunks intersecting the tile are stroked.
final class RouteOverlayRenderer: MKOverlayRenderer {
    private let lock = NSLock()
    private var range: [RouteChunk]? = nil

    func setRange(_ chunks: [RouteChunk]?) {
        lock.lock()
        range = chunks
        lock.unlock()
        setNeedsDisplay()
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let o = overlay as? RouteOverlay else { return }
        let d: RouteRenderData = o.data
        lock.lock()
        let ranged: [RouteChunk]? = range
        lock.unlock()
        let k: CGFloat = 1 / max(zoomScale, 1e-12)
        let cull: MKMapRect = mapRect.insetBy(dx: -Double(12 * k), dy: -Double(12 * k))
        context.setLineCap(.round)
        context.setLineJoin(.round)

        func stroke(_ chunks: [RouteChunk], _ width: CGFloat, _ color: (Int) -> UIColor) {
            context.setLineWidth(width * k)
            for c in chunks where c.rect.intersects(cull) {
                context.setStrokeColor(color(c.key).cgColor)
                context.addPath(c.path)
                context.strokePath()
            }
        }

        let casingColor = UIColor(white: 0, alpha: 170.0 / 255.0)
        stroke(d.casing, 7.5) { (_: Int) -> UIColor in casingColor }
        let palette: [Int: UIColor] = d.palette
        if let r = ranged {
            let dim = UIColor(red: 0x93 / 255.0, green: 0x94 / 255.0, blue: 0x9B / 255.0, alpha: 0xB0 / 255.0)
            stroke(d.casing, 3.2) { (_: Int) -> UIColor in dim }
            stroke(r, 5) { (key: Int) -> UIColor in palette[key] ?? UIColor.systemBlue }
        } else {
            stroke(d.colored, 4.2) { (key: Int) -> UIColor in palette[key] ?? UIColor.systemBlue }
        }
        // signal losses: dashed, never interpolated as route
        if !d.gaps.isEmpty {
            context.saveGState()
            context.setLineDash(phase: 0, lengths: [6 * k, 5 * k])
            let lossColor = UIColor(red: 1, green: 0x39 / 255.0, blue: 0x45 / 255.0, alpha: 0.9)
            stroke(d.gaps, 2.2) { (_: Int) -> UIColor in lossColor }
            context.restoreGState()
        }
    }
}

// MARK: - Annotations

/// Maximum speed of the training (fixed, orange marker with a bolt).
final class VmaxAnnotation: MKPointAnnotation {}

final class RouteMarkerAnnotation: MKPointAnnotation {
    enum Kind: String { case start, end, marker, cursor }
    let kind: Kind
    init(kind: Kind) {
        self.kind = kind
        super.init()
    }
}

enum RouteMarkerImages {
    private static var cache: [String: UIImage] = [:]

    static func dotRadius(_ kind: RouteMarkerAnnotation.Kind) -> CGFloat {
        switch kind {
        case .cursor: return 8
        case .marker: return 5
        default: return 7
        }
    }

    /// Dot on the left (Windows Marker: coloured circle with white ring) and optional label pill on the right.
    static func image(_ kind: RouteMarkerAnnotation.Kind, label: String?) -> UIImage {
        let key: String = kind.rawValue + "|" + (label ?? "")
        if let img = cache[key] { return img }
        let r: CGFloat = dotRadius(kind)
        let fill: UIColor
        let ring: UIColor
        let ringWidth: CGFloat
        switch kind {
        case .start: fill = UIColor(red: 0x52 / 255.0, green: 0xDD / 255.0, blue: 0x40 / 255.0, alpha: 1); ring = .white; ringWidth = 2
        case .end: fill = UIColor(red: 0xED / 255.0, green: 0x12 / 255.0, blue: 0x2A / 255.0, alpha: 1); ring = .white; ringWidth = 2
        case .marker: fill = UIColor(red: 0xFF / 255.0, green: 0xC4 / 255.0, blue: 0x2C / 255.0, alpha: 1); ring = .white; ringWidth = 1.5
        case .cursor: fill = .white; ring = UIColor(red: 0xED / 255.0, green: 0x12 / 255.0, blue: 0x2A / 255.0, alpha: 1); ringWidth = 3
        }
        let font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        var textSize: CGSize = .zero
        if let l = label { textSize = (l as NSString).size(withAttributes: [.font: font]) }
        let pad: CGFloat = 2
        let dotBox: CGFloat = 2 * r + 2 * pad
        let labelW: CGFloat = label == nil ? 0 : textSize.width + 12 + 4
        let height: CGFloat = max(dotBox, label == nil ? 0 : textSize.height + 4)
        let size = CGSize(width: dotBox + labelW, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        let img: UIImage = renderer.image { (ctx: UIGraphicsImageRendererContext) in
            let cg: CGContext = ctx.cgContext
            let dotRect = CGRect(x: pad, y: (height - 2 * r) / 2, width: 2 * r, height: 2 * r)
            cg.setFillColor(fill.cgColor)
            cg.fillEllipse(in: dotRect)
            cg.setStrokeColor(ring.cgColor)
            cg.setLineWidth(ringWidth)
            cg.strokeEllipse(in: dotRect.insetBy(dx: ringWidth / 2, dy: ringWidth / 2))
            if let l = label {
                let box = CGRect(x: dotBox + 4, y: (height - textSize.height - 4) / 2, width: textSize.width + 12, height: textSize.height + 4)
                let path = UIBezierPath(roundedRect: box, cornerRadius: 3)
                UIColor(red: 0x10 / 255.0, green: 0x10 / 255.0, blue: 0x14 / 255.0, alpha: 0xD8 / 255.0).setFill()
                path.fill()
                fill.setStroke()
                path.lineWidth = 1
                path.stroke()
                (l as NSString).draw(at: CGPoint(x: box.minX + 6, y: box.minY + 2), withAttributes: [.font: font, .foregroundColor: UIColor.white])
            }
        }
        cache[key] = img
        return img
    }
}

// MARK: - Tiles

/// Shared state of the tile loader (Windows MapControl: 6 parallel downloads, 60 consecutive failures = offline).
enum RouteTileNet {
    private static let lock = NSLock()
    private static var failuresValue: Int = 0
    static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.httpMaximumConnectionsPerHost = 6
        cfg.httpAdditionalHeaders = ["User-Agent": "AVO-Performance-Horse-iPad/2.0"]
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.urlCache = nil
        return URLSession(configuration: cfg)
    }()

    static var failures: Int {
        lock.lock(); defer { lock.unlock() }
        return failuresValue
    }
    static func failed() { lock.lock(); failuresValue += 1; lock.unlock() }
    static func succeeded() { lock.lock(); failuresValue = 0; lock.unlock() }

    static let attribution: String = "Imágenes: © Esri, Maxar, Earthstar Geographics y GIS User Community"
}

/// Esri ArcGIS tile layer with a disk cache in AppPaths.tiles (same layout as Windows: <layer>/<z>/<y>/<x>.<ext>, 30 days).
final class RouteEsriTileOverlay: MKTileOverlay {
    let layerName: String
    let cacheDir: String
    private let ext: String

    init(layer: String, cacheDir: String) {
        self.layerName = layer
        self.cacheDir = cacheDir
        self.ext = layer == "World_Imagery" ? "jpg" : "png"
        super.init(urlTemplate: nil)
        self.tileSize = CGSize(width: 256, height: 256)
        self.minimumZ = 1
        self.maximumZ = 22   // 20–22: enlarged from level 19 (overzoom)
        self.canReplaceMapContent = layer == "World_Imagery"
    }

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        let s: String = "https://server.arcgisonline.com/ArcGIS/rest/services/\(layerName)/MapServer/tile/\(path.z)/\(path.y)/\(path.x)"
        return URL(string: s) ?? URL(fileURLWithPath: "/")
    }

    private func file(_ path: MKTileOverlayPath) -> String {
        AvoFiles.join(cacheDir, layerName.replacingOccurrences(of: "/", with: "_"), String(path.z), String(path.y), "\(path.x).\(ext)")
    }

    /// Deepest zoom Esri serves for this layer; closer zooms enlarge a piece of a tile of this level so the
    /// satellite view never turns into an empty grid at maximum zoom.
    static let nativeMaxZ: Int = 19

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        if path.z > RouteEsriTileOverlay.nativeMaxZ {
            overzoom(path, parentZ: RouteEsriTileOverlay.nativeMaxZ, result: result)
            return
        }
        loadNative(path) { [weak self] (data: Data?, error: Error?) in
            // a missing tile at a deep level (no imagery there yet): enlarge the level above instead of a hole
            if data == nil, path.z >= 16, let self = self {
                self.overzoom(path, parentZ: path.z - 1, result: result)
            } else {
                result(data, error)
            }
        }
    }

    /// The tile `path` cut out of its ancestor at `parentZ` and scaled up to the tile size.
    private func overzoom(_ path: MKTileOverlayPath, parentZ: Int, result: @escaping (Data?, Error?) -> Void) {
        let k: Int = path.z - parentZ
        guard k > 0, k <= 8 else { result(nil, AvoError.invalidData("tesela fuera de rango")); return }
        var parent: MKTileOverlayPath = path
        parent.z = parentZ
        parent.x = path.x >> k
        parent.y = path.y >> k
        let n: Int = 1 << k
        let qx: Int = path.x & (n - 1)
        let qy: Int = path.y & (n - 1)
        let jpeg: Bool = ext == "jpg"
        loadNative(parent) { (data: Data?, error: Error?) in
            guard let d = data, let img = UIImage(data: d), let cg = img.cgImage else { result(nil, error); return }
            let side: CGFloat = CGFloat(cg.width) / CGFloat(n)
            let crop = CGRect(x: CGFloat(qx) * side, y: CGFloat(qy) * side, width: side, height: side).integral
            guard let piece = cg.cropping(to: crop) else { result(nil, error); return }
            let out = CGSize(width: 256, height: 256)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = jpeg
            let scaled: UIImage = UIGraphicsImageRenderer(size: out, format: format).image { (ctx: UIGraphicsImageRendererContext) in
                ctx.cgContext.interpolationQuality = .high
                UIImage(cgImage: piece).draw(in: CGRect(origin: .zero, size: out))
            }
            result(jpeg ? scaled.jpegData(compressionQuality: 0.9) : scaled.pngData(), nil)
        }
    }

    private func loadNative(_ path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let f: String = file(path)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: f),
           let modified = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < 30 * 86400,
           let data = AvoFiles.read(f), !data.isEmpty {
            result(data, nil)
            return
        }
        if RouteTileNet.failures > 60 {
            // offline: stop trying, the route is still drawn
            result(nil, AvoError.invalidOperation("sin conexión"))
            return
        }
        let url: URL = url(forTilePath: path)
        let task = RouteTileNet.session.dataTask(with: url) { (data: Data?, response: URLResponse?, error: Error?) in
            let status: Int = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let d = data, error == nil, status == 200, !d.isEmpty {
                RouteTileNet.succeeded()
                try? AvoFiles.writeAtomic(d, to: f)
                result(d, nil)
            } else {
                if error != nil { RouteTileNet.failed() }
                result(nil, error ?? AvoError.invalidData("tesela \(status)"))
            }
        }
        task.resume()
    }
}

/// «Vectorial sin conexión»: no tiles, dark background with a 64 px grid (Windows MapControl.DrawGrid).
final class RouteOfflineGridOverlay: MKTileOverlay {
    private static let tile: Data = {
        let size = CGSize(width: 256, height: 256)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let img: UIImage = UIGraphicsImageRenderer(size: size, format: format).image { (ctx: UIGraphicsImageRendererContext) in
            let cg: CGContext = ctx.cgContext
            cg.setFillColor(UIColor(red: 0x0B / 255.0, green: 0x0C / 255.0, blue: 0x10 / 255.0, alpha: 1).cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            cg.setStrokeColor(UIColor(red: 0xC9 / 255.0, green: 0xCB / 255.0, blue: 0xD1 / 255.0, alpha: 0x22 / 255.0).cgColor)
            cg.setLineWidth(1)
            var v: CGFloat = 0
            while v < 256 {
                cg.move(to: CGPoint(x: v + 0.5, y: 0)); cg.addLine(to: CGPoint(x: v + 0.5, y: 256))
                cg.move(to: CGPoint(x: 0, y: v + 0.5)); cg.addLine(to: CGPoint(x: 256, y: v + 0.5))
                v += 64
            }
            cg.strokePath()
        }
        return img.pngData() ?? Data()
    }()

    init() {
        super.init(urlTemplate: nil)
        self.tileSize = CGSize(width: 256, height: 256)
        self.canReplaceMapContent = true
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        result(RouteOfflineGridOverlay.tile, nil)
    }
}
