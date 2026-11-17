import SwiftUI
import MapKit
import UIKit

/// Geocercas: port of windows/AVO.Windows/Views/GeofencesView.xaml (8 fence slots + 4 lines of the watch, edited on the map).
struct GeofencesView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let geo: GeofencesModel = app.geofences
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) {
                ScrollView {
                    GeoSideColumn(geo: geo)
                }
                .frame(width: 340)
                VStack(spacing: 12) {
                    GeoMapPanel(geo: geo).frame(minHeight: 340)
                    ScrollView {
                        VStack(spacing: 12) {
                            GeoEditorCard(geo: geo)
                            GeoCrossingsCard(geo: geo)
                        }
                    }
                    .frame(maxHeight: 380)
                }
            }
            .frame(minWidth: 820)
            ScrollView {
                VStack(spacing: 12) {
                    GeoMapPanel(geo: geo).frame(height: 420)
                    GeoEditorCard(geo: geo)
                    GeoSideColumn(geo: geo)
                    GeoCrossingsCard(geo: geo)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Avo.bg)
        .onAppear { geo.pageShown() }
        .alert(geo.confirm?.title ?? "",
               isPresented: Binding(get: { geo.confirm != nil }, set: { if !$0 { geo.answer(false) } }),
               presenting: geo.confirm) { c in
            Button("Cancelar", role: .cancel) { geo.answer(false) }
            Button(c.okLabel) { geo.answer(true) }
        } message: { c in
            Text(c.message)
        }
    }
}

// MARK: - left column

private struct GeoSideColumn: View {
    let geo: GeofencesModel

    var body: some View {
        @Bindable var g = geo
        VStack(alignment: .leading, spacing: 12) {
            AvoPageTitle(title: "Geocercas", subtitle: "Geocercas y líneas de salida y meta del reloj de pecho")

            AvoCard(title: "Reloj de pecho") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(geo.geoSummary).font(.footnote).foregroundStyle(Avo.text).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button {
                            Task { await geo.sendToWatch() }
                        } label: {
                            Label("Enviar al reloj", systemImage: "antenna.radiowaves.left.and.right")
                        }
                        .buttonStyle(.avoPrimary)
                        .disabled(geo.watchBusy)
                        .accessibilityIdentifier("geo.send")
                        Button("Leer del reloj") { Task { await geo.readFromWatch() } }
                            .buttonStyle(.avoSecondary)
                            .disabled(geo.watchBusy)
                            .accessibilityIdentifier("geo.read")
                        if geo.watchBusy { ProgressView().tint(Avo.red) }
                    }
                    Text(geo.watchLinkStatus).font(.caption).foregroundStyle(Avo.cyan).fixedSize(horizontal: false, vertical: true)
                    Toggle("Grabación automática al entrar en una geocerca activa", isOn: $g.geoAuto).font(.footnote).tint(Avo.red)
                    Text("Bluetooth del iPad, mismo formato que la app Android: el reloj no se modifica. La primera vez, el reloj pide pulsar BOOT para autorizar este iPad. Si el móvil está conectado al reloj, desconéctalo antes.")
                        .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                }
            }

            AvoCard(title: "Geocercas (8 huecos del reloj)") {
                VStack(spacing: 4) {
                    ForEach(0..<Fence.maxFences, id: \.self) { i in
                        GeoSlotRow(color: Color(hex: GeofencesModel.fenceColors[i]), number: "\(i + 1)",
                                   title: geo.fenceTitle(i), detail: geo.fenceDetail(i), problem: geo.fenceProblem(i),
                                   empty: geo.fence(i) == nil, selected: geo.selectedFence == i)
                            .contentShape(Rectangle())
                            .onTapGesture { geo.selectFence(i) }
                    }
                }
            }

            AvoCard(title: "Líneas de salida y meta (4 del reloj)") {
                VStack(spacing: 4) {
                    ForEach(0..<4, id: \.self) { i in
                        GeoSlotRow(color: Color(hex: geo.line(i).enabled ? GeofencesModel.lineOn : GeofencesModel.lineOff),
                                   number: "L\(i + 1)", title: geo.lineTitle(i), detail: geo.lineDetail(i),
                                   problem: geo.lineProblem(i), empty: !geo.line(i).enabled, selected: geo.selectedLine == i)
                            .contentShape(Rectangle())
                            .onTapGesture { geo.selectLine(i) }
                    }
                }
            }

            let problems: [String] = geo.geoProblems
            if !problems.isEmpty {
                AvoCard {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(problems, id: \.self) { p in
                            Label(p, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Avo.warn)
                        }
                    }
                }
            }
        }
    }
}

private struct GeoSlotRow: View {
    let color: Color
    let number: String
    let title: String
    let detail: String
    let problem: String?
    let empty: Bool
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(number).font(.caption.weight(.bold)).foregroundStyle(empty ? Avo.textDim : .white)
                .frame(width: 28, height: 28)
                .background(empty ? Avo.surface2 : color.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.footnote.weight(.semibold)).foregroundStyle(empty ? Avo.textDim : Avo.text).lineLimit(1)
                Text(detail).font(.caption2).foregroundStyle(Avo.textDim).lineLimit(2)
            }
            Spacer(minLength: 4)
            if let p = problem {
                Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Avo.warn)
                    .accessibilityLabel(p)
            }
        }
        .padding(6)
        .background(selected ? Avo.redSoft : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? Avo.red.opacity(0.6) : Color.clear, lineWidth: 1))
    }
}

// MARK: - map

private struct GeoMapPanel: View {
    let geo: GeofencesModel
    @Environment(AppModel.self) private var app

    var body: some View {
        let track: [CLLocationCoordinate2D] = GeoMapPanel.trackOf(app.selected)
        let home = CLLocationCoordinate2D(latitude: app.settings.placeLatitude, longitude: app.settings.placeLongitude)
        ZStack(alignment: .top) {
            GeoEditMap(geo: geo, rev: geo.rev, fitRequest: geo.fitRequest, selFence: geo.selectedFence ?? -1,
                       selLine: geo.selectedLine ?? -1, track: track, trackKey: app.selected?.id ?? "", home: home)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Avo.line, lineWidth: 1))
            HStack(spacing: 8) {
                Text(geo.geoHint).font(.footnote.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.black.opacity(0.65), in: Capsule())
                Spacer()
                Button {
                    geo.fitRequest += 1
                } label: {
                    Image(systemName: "scope").padding(8).background(Color.black.opacity(0.65), in: Circle())
                }
                .foregroundStyle(.white)
                .accessibilityLabel("Encuadrar")
            }
            .padding(10)
        }
    }

    static func trackOf(_ s: SessionItem?) -> [CLLocationCoordinate2D] {
        guard let s = s else { return [] }
        let tl = s.timeline
        let n: Int = tl.count
        if n < 2 { return [] }
        let step: Int = max(1, n / 4000)
        var out: [CLLocationCoordinate2D] = []
        out.reserveCapacity(n / step + 1)
        var i = 0
        while i < n {
            let la = tl.lat[i], lo = tl.lon[i]
            if la.isFinite && lo.isFinite && (la != 0 || lo != 0) { out.append(CLLocationCoordinate2D(latitude: la, longitude: lo)) }
            i += step
        }
        return out
    }
}

/// Esri World Imagery tiles (same source as Windows/Android). Own class name so it does not clash with the map page.
final class GeoTileOverlay: MKTileOverlay {
    static let template = "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"

    static func make() -> GeoTileOverlay {
        let t = GeoTileOverlay(urlTemplate: GeoTileOverlay.template)
        t.canReplaceMapContent = true
        t.minimumZ = 1
        t.maximumZ = 19
        return t
    }
}

private final class GeoPin: MKPointAnnotation {
    var glyph: String = ""
    var color: UIColor = .white
    var isLabel: Bool = false
}

private struct GeoStyle {
    var stroke: UIColor
    var fill: UIColor?
    var width: CGFloat
    var dash: [NSNumber]?
}

private struct GeoEditMap: UIViewRepresentable {
    let geo: GeofencesModel
    let rev: Int
    let fitRequest: Int
    let selFence: Int
    let selLine: Int
    let track: [CLLocationCoordinate2D]
    let trackKey: String
    let home: CLLocationCoordinate2D

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        weak var map: MKMapView?
        var onTap: ((Double, Double) -> Void)?
        var builtKey: String = "-"
        var fitDone: Int = -1
        var styles: [ObjectIdentifier: GeoStyle] = [:]
        let tiles = GeoTileOverlay.make()

        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard let map = map, g.state == .ended else { return }
            let p = g.location(in: map)
            let c = map.convert(p, toCoordinateFrom: map)
            onTap?(c.latitude, c.longitude)
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { false }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let t = overlay as? MKTileOverlay { return MKTileOverlayRenderer(tileOverlay: t) }
            let st: GeoStyle = styles[ObjectIdentifier(overlay as AnyObject)] ?? GeoStyle(stroke: .white, fill: nil, width: 2, dash: nil)
            if let c = overlay as? MKCircle {
                let r = MKCircleRenderer(circle: c)
                r.strokeColor = st.stroke; r.fillColor = st.fill; r.lineWidth = st.width
                return r
            }
            if let p = overlay as? MKPolygon {
                let r = MKPolygonRenderer(polygon: p)
                r.strokeColor = st.stroke; r.fillColor = st.fill; r.lineWidth = st.width
                return r
            }
            if let l = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: l)
                r.strokeColor = st.stroke; r.lineWidth = st.width; r.lineDashPattern = st.dash
                r.lineCap = .round; r.lineJoin = .round
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let pin = annotation as? GeoPin else { return nil }
            let id = pin.isLabel ? "geo.label" : "geo.pin"
            let v = mapView.dequeueReusableAnnotationView(withIdentifier: id) ?? MKAnnotationView(annotation: pin, reuseIdentifier: id)
            v.annotation = pin
            v.image = pin.isLabel ? Coordinator.labelImage(pin.glyph, pin.color) : Coordinator.dotImage(pin.glyph, pin.color)
            v.centerOffset = pin.isLabel ? CGPoint(x: 0, y: -18) : .zero
            v.canShowCallout = false
            v.isEnabled = false        // taps go to the map (placing points)
            return v
        }

        static func dotImage(_ text: String, _ color: UIColor) -> UIImage {
            let size: CGFloat = text.isEmpty ? 12 : 22
            let r = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
            return r.image { _ in
                let rect = CGRect(x: 1, y: 1, width: size - 2, height: size - 2)
                color.setFill()
                UIBezierPath(ovalIn: rect).fill()
                UIColor.white.setStroke()
                let b = UIBezierPath(ovalIn: rect); b.lineWidth = 1.5; b.stroke()
                if !text.isEmpty {
                    let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 11), .foregroundColor: UIColor.black]
                    let s = (text as NSString).size(withAttributes: attrs)
                    (text as NSString).draw(at: CGPoint(x: (size - s.width) / 2, y: (size - s.height) / 2), withAttributes: attrs)
                }
            }
        }

        static func labelImage(_ text: String, _ color: UIColor) -> UIImage {
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: UIColor.white]
            let s = (text as NSString).size(withAttributes: attrs)
            let size = CGSize(width: ceil(s.width) + 12, height: ceil(s.height) + 6)
            let r = UIGraphicsImageRenderer(size: size)
            return r.image { _ in
                let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 5)
                UIColor.black.withAlphaComponent(0.7).setFill(); path.fill()
                color.setStroke(); path.lineWidth = 1; path.stroke()
                (text as NSString).draw(at: CGPoint(x: 6, y: 3), withAttributes: attrs)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.mapType = .satellite
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = true
        map.showsScale = true
        map.isRotateEnabled = false
        map.addOverlay(context.coordinator.tiles, level: .aboveLabels)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.numberOfTapsRequired = 1
        // single taps only: do not fire on the double tap that zooms
        for g in map.gestureRecognizers ?? [] {
            if let t = g as? UITapGestureRecognizer, t.numberOfTapsRequired == 2 { tap.require(toFail: t) }
        }
        tap.delegate = context.coordinator
        map.addGestureRecognizer(tap)
        context.coordinator.map = map
        map.setRegion(MKCoordinateRegion(center: home, latitudinalMeters: 1500, longitudinalMeters: 1500), animated: false)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let c = context.coordinator
        let model = geo
        c.onTap = { (lat: Double, lon: Double) in model.mapTap(lat: lat, lon: lon) }
        let key = "\(rev)|\(selFence)|\(selLine)|\(trackKey)|\(track.count)"
        if key != c.builtKey {
            c.builtKey = key
            rebuild(map, c)
        }
        if c.fitDone != fitRequest {
            c.fitDone = fitRequest
            fit(map)
        }
    }

    // ------------------------------------------------------------------ drawing
    private func rebuild(_ map: MKMapView, _ c: Coordinator) {
        let old: [MKOverlay] = map.overlays.filter { !($0 is MKTileOverlay) }
        map.removeOverlays(old)
        map.removeAnnotations(map.annotations)
        c.styles = [:]
        var pins: [GeoPin] = []

        func add(_ o: MKOverlay, _ st: GeoStyle) {
            c.styles[ObjectIdentifier(o as AnyObject)] = st
            map.addOverlay(o, level: .aboveLabels)
        }
        func pin(_ lat: Double, _ lon: Double, _ glyph: String, _ color: UIColor, label: Bool = false) {
            let p = GeoPin()
            p.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            p.glyph = glyph; p.color = color; p.isLabel = label
            pins.append(p)
        }

        // track of the open training (context for placing lines)
        if track.count > 1 {
            var pts = track
            add(MKPolyline(coordinates: &pts, count: pts.count), GeoStyle(stroke: UIColor(Avo.cyan).withAlphaComponent(0.85), fill: nil, width: 2, dash: nil))
        }

        // fences
        for i in 0..<Fence.maxFences {
            guard let f = geo.fence(i) else { continue }
            let sel: Bool = selFence == i
            let base = UIColor(Color(hex: GeofencesModel.fenceColors[i]))
            let alpha: CGFloat = f.active ? (sel ? 0x55 : 0x33) : 0x14
            let st = GeoStyle(stroke: sel ? .white : base, fill: base.withAlphaComponent(alpha / 255.0), width: sel ? 3.5 : 2.5, dash: nil)
            if f.type == .circle {
                guard let ctr = f.center else { continue }
                add(MKCircle(center: CLLocationCoordinate2D(latitude: ctr.lat, longitude: ctr.lon), radius: max(1, f.radiusM)), st)
                if sel { pin(ctr.lat, ctr.lon, "", base) }
                pin(ctr.lat, ctr.lon, "\(i + 1). \(f.name)", base, label: true)
            } else {
                var pts: [CLLocationCoordinate2D] = f.vertices.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                if pts.isEmpty { continue }
                if pts.count > 2 {
                    add(MKPolygon(coordinates: &pts, count: pts.count), st)
                } else if pts.count == 2 {
                    add(MKPolyline(coordinates: &pts, count: pts.count), st)
                }
                if sel || pts.count < 3 {
                    for (k, v) in f.vertices.enumerated() { pin(v.lat, v.lon, sel ? String(k + 1) : "", base) }
                }
                var la = 0.0, lo = 0.0
                for v in f.vertices { la += v.lat; lo += v.lon }
                pin(la / Double(f.vertices.count), lo / Double(f.vertices.count), "\(i + 1). \(f.name)", base, label: true)
            }
        }

        // lines (A/B ends, direction arrow)
        for i in 0..<4 {
            let l = geo.line(i)
            if l.a == nil && l.b == nil { continue }
            let sel: Bool = selLine == i
            let col = UIColor(Color(hex: l.enabled ? GeofencesModel.lineOn : GeofencesModel.lineOff))
            if let a = l.a { pin(a.lat, a.lon, "A", col) }
            if let b = l.b { pin(b.lat, b.lon, "B", col) }
            guard let a = l.a, let b = l.b else { continue }
            var pts: [CLLocationCoordinate2D] = [CLLocationCoordinate2D(latitude: a.lat, longitude: a.lon),
                                                 CLLocationCoordinate2D(latitude: b.lat, longitude: b.lon)]
            add(MKPolyline(coordinates: &pts, count: 2), GeoStyle(stroke: sel ? .white : col, fill: nil, width: sel ? 4 : 3, dash: nil))
            for var arrow in GeoEditMap.arrows(l) {
                add(MKPolyline(coordinates: &arrow, count: arrow.count), GeoStyle(stroke: sel ? .white : col, fill: nil, width: 2.5, dash: nil))
            }
            pin((a.lat + b.lat) / 2, (a.lon + b.lon) / 2, l.name.isEmpty ? "Línea \(i + 1)" : l.name, col, label: true)
        }
        map.addAnnotations(pins)
    }

    /// Arrow across the line showing which crossing counts (seen from A towards B, left → right = sense of the arrow).
    static func arrows(_ l: PlanLine) -> [[CLLocationCoordinate2D]] {
        guard let a = l.a, let b = l.b else { return [] }
        let fr = LocalFrame(lat: a.lat, lon: a.lon)
        let pb = fr.toXY(b.lat, b.lon)
        let len: Double = (pb.x * pb.x + pb.y * pb.y).squareRoot()
        if len < 0.5 { return [] }
        let ux = pb.x / len, uy = pb.y / len
        let rx = uy, ry = -ux                      // right-hand normal
        let k: Double = max(3, min(60, len * 0.3))
        let mx = pb.x / 2, my = pb.y / 2
        let p0 = (x: mx - rx * k / 2, y: my - ry * k / 2)
        let p1 = (x: mx + rx * k / 2, y: my + ry * k / 2)
        func pt(_ x: Double, _ y: Double) -> CLLocationCoordinate2D {
            let g = fr.toPoint(x, y)
            return CLLocationCoordinate2D(latitude: g.lat, longitude: g.lon)
        }
        func head(_ tip: (x: Double, y: Double), _ dx: Double, _ dy: Double) -> [CLLocationCoordinate2D] {
            let h = k * 0.35
            let bx = tip.x - dx * h, by = tip.y - dy * h
            let nx = -dy, ny = dx
            return [pt(bx + nx * h * 0.6, by + ny * h * 0.6), pt(tip.x, tip.y), pt(bx - nx * h * 0.6, by - ny * h * 0.6)]
        }
        var out: [[CLLocationCoordinate2D]] = [[pt(p0.x, p0.y), pt(p1.x, p1.y)]]
        switch l.direction {
        case .leftToRight: out.append(head(p1, rx, ry))
        case .rightToLeft: out.append(head(p0, -rx, -ry))
        case .both:
            out.append(head(p1, rx, ry))
            out.append(head(p0, -rx, -ry))
        }
        return out
    }

    private func fit(_ map: MKMapView) {
        var rect = MKMapRect.null
        func addPoint(_ lat: Double, _ lon: Double) {
            let p = MKMapPoint(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            rect = rect.union(MKMapRect(x: p.x, y: p.y, width: 0, height: 0))
        }
        for i in 0..<Fence.maxFences {
            guard let f = geo.fence(i) else { continue }
            if let c = f.center, f.type == .circle {
                let circle = MKCircle(center: CLLocationCoordinate2D(latitude: c.lat, longitude: c.lon), radius: max(1, f.radiusM))
                rect = rect.union(circle.boundingMapRect)
            }
            for v in f.vertices { addPoint(v.lat, v.lon) }
        }
        for i in 0..<4 {
            let l = geo.line(i)
            if let a = l.a { addPoint(a.lat, a.lon) }
            if let b = l.b { addPoint(b.lat, b.lon) }
        }
        for p in track { addPoint(p.latitude, p.longitude) }
        if rect.isNull {
            map.setRegion(MKCoordinateRegion(center: home, latitudinalMeters: 1500, longitudinalMeters: 1500), animated: true)
            return
        }
        let minSide: Double = 400 * MKMapPointsPerMeterAtLatitude(rect.origin.coordinate.latitude)
        if rect.size.width < minSide || rect.size.height < minSide {
            let cx = rect.midX, cy = rect.midY
            rect = MKMapRect(x: cx - minSide / 2, y: cy - minSide / 2, width: minSide, height: minSide)
        }
        map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 50, left: 30, bottom: 30, right: 30), animated: true)
    }
}

// MARK: - editor

private struct GeoEditorCard: View {
    let geo: GeofencesModel

    var body: some View {
        @Bindable var g = geo
        AvoCard(title: "Edición") {
            VStack(alignment: .leading, spacing: 10) {
                Text(geo.geoHint).font(.footnote).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                if geo.editingFence {
                    fenceEditor(g)
                } else if geo.editingLine {
                    lineEditor(g)
                } else {
                    Text("Elige una geocerca o una línea.").font(.footnote).foregroundStyle(Avo.textDim)
                }
                if !geo.geoProblem.isEmpty {
                    Label(geo.geoProblem, systemImage: geo.geoProblemOk ? "checkmark.circle" : "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(geo.geoProblemOk ? Avo.ok : Avo.warn)
                }
            }
        }
    }

    @ViewBuilder
    private func fenceEditor(_ g: GeofencesModel) -> some View {
        @Bindable var b = g
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button("Círculo") { g.newFence(.circle) }.buttonStyle(.avoSecondary)
                Button("Polígono") { g.newFence(.polygon) }.buttonStyle(.avoSecondary)
                if g.editingPolygon { Button("Deshacer vértice") { g.undoVertex() }.buttonStyle(.avoSecondary) }
                if g.editingFenceShape {
                    Button("Borrar forma") { g.clearShape() }.buttonStyle(.avoSecondary)
                    Button("Vaciar hueco") { g.askDeleteFence() }.buttonStyle(.avoSecondary)
                }
            }
            if g.editingFenceShape {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NOMBRE (MÁX. 15)").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim)
                    TextField("", text: $b.fenceName)
                        .padding(8)
                        .background(Avo.surface2, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Avo.line, lineWidth: 1))
                }
                Toggle("Activa (grabación automática)", isOn: $b.fenceActive).font(.footnote).tint(Avo.red)
                if g.editingCircle {
                    let logBinding = Binding<Double>(get: { log10(max(5, g.fenceRadius)) },
                                                     set: { (v: Double) in g.fenceRadius = pow(10, v) })
                    HStack(spacing: 4) {
                        Text("RADIO: ").font(.caption2.weight(.semibold)).foregroundStyle(Avo.textDim)
                        Text(AvoFormat.f(g.fenceRadius, 0)).font(.callout.weight(.semibold)).foregroundStyle(Avo.text)
                        Text(" m (5 m – 5 km)").font(.caption).foregroundStyle(Avo.textDim)
                        Spacer()
                        Stepper("", value: $b.fenceRadius, in: 5...5000, step: 5).labelsHidden()
                    }
                    Slider(value: logBinding, in: log10(5.0)...log10(5000.0)).tint(Avo.red)
                }
            }
        }
    }

    @ViewBuilder
    private func lineEditor(_ g: GeofencesModel) -> some View {
        @Bindable var b = g
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NOMBRE").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim)
                TextField("", text: $b.lineName)
                    .padding(8)
                    .background(Avo.surface2, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Avo.line, lineWidth: 1))
            }
            HStack(spacing: 12) {
                Toggle("Línea activa", isOn: $b.lineEnabled).font(.footnote).tint(Avo.red).fixedSize()
                Spacer()
                Button("Borrar extremos") { g.clearShape() }.buttonStyle(.avoSecondary)
            }
            Text("USO").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim)
            Picker("Uso", selection: $b.lineRole) {
                ForEach(LineRole.allCases, id: \.self) { r in Text(GeofencesModel.roleLabel(r)).tag(r) }
            }
            .pickerStyle(.menu)
            Text("SENTIDO EN QUE MARCA (FLECHA DEL MAPA)").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim)
            Picker("Sentido", selection: $b.lineDirection) {
                ForEach(LineDirection.allCases, id: \.self) { d in Text(GeofencesModel.directionLabel(d)).tag(d) }
            }
            .pickerStyle(.segmented)
            Text("El reloj recibe la línea tal cual y cuenta los cruces en los dos sentidos (su firmware no guarda sentido; la línea 1 cronometra vueltas). El sentido elegido se aplica en este iPad al analizar el entrenamiento: los cruces al revés aparecen como «No marca».")
                .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - crossings

private struct GeoCrossingsCard: View {
    let geo: GeofencesModel

    var body: some View {
        AvoCard(title: geo.crossingsTitle) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Spacer()
                    Button("Crear tramos con estos tiempos") { geo.linesToSegments() }
                        .buttonStyle(.avoSecondary)
                        .disabled(!geo.canCreateSegments)
                        .accessibilityIdentifier("geo.segments")
                }
                if !geo.crossingsEmpty.isEmpty {
                    Text(geo.crossingsEmpty).font(.footnote).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                }
                if !geo.crossingRows.isEmpty {
                    VStack(spacing: 0) {
                        row(["Línea", "Hora", "Sentido", ""], header: true, counts: nil)
                        ForEach(geo.crossingRows) { c in
                            row([c.line, c.time, c.direction, c.countsText], header: false, counts: c.counts)
                            Divider().overlay(Avo.line)
                        }
                    }
                }
                if !geo.runRows.isEmpty {
                    VStack(spacing: 0) {
                        row(["Vuelta / tramo", "Inicio", "Tiempo", ""], header: true, counts: nil)
                        ForEach(geo.runRows) { r in
                            row([r.kind, r.start, r.duration, ""], header: false, counts: nil)
                            Divider().overlay(Avo.line)
                        }
                    }
                }
            }
        }
    }

    private func row(_ cols: [String], header: Bool, counts: Bool?) -> some View {
        HStack(spacing: 8) {
            Text(header ? cols[0].uppercased() : cols[0]).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
            Text(header ? cols[1].uppercased() : cols[1]).frame(width: 80, alignment: .leading)
            Text(header ? cols[2].uppercased() : cols[2]).frame(width: 170, alignment: .leading).lineLimit(1)
            Group {
                if let c = counts {
                    AvoPill(text: cols[3], color: c ? Avo.ok : Avo.warn)
                } else {
                    Text(cols[3])
                }
            }
            .frame(width: 80, alignment: .leading)
        }
        .font(header ? .caption2.weight(.semibold) : .footnote)
        .foregroundStyle(header ? Avo.textDim : Avo.text)
        .padding(.vertical, 5)
    }
}
