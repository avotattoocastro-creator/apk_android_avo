import SwiftUI
import MapKit
import Charts

/// «LIVE» (boceto del entrenador 19/11/2026 sobre la captura de Análisis › Mapa): datos en tiempo real arriba, mapa
/// centrado que sigue al caballo, gráfica de velocidad en tiempo real sobre la parte baja del mapa, y debajo las gráficas
/// de pulso y aceleración. Sin panel de totales a la derecha y sin barra de pestañas. Datos: servidor (Firebase).
struct LiveView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m: LiveModel = app.live
        Group {
            if m.signedCode == nil && m.source != .simulation {
                LiveSignInView(model: m)
            } else {
                LiveDashboard(model: m)
            }
        }
        .background(Avo.bg)
        .onAppear { m.pageShown() }
        .onDisappear { m.pageHidden() }
    }
}

// MARK: - Entrar con la tarjeta AVO

private struct LiveSignInView: View {
    @Environment(AppModel.self) private var app
    let model: LiveModel
    @State private var link: String = ""
    @State private var code: String = ""
    @State private var key: String = ""
    @State private var localError: String? = nil
    @State private var scanning: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AvoPageTitle(title: "LIVE", subtitle: "Entrenamiento en directo desde el servidor AVO")
                AvoCard(title: "Entrar con tu tarjeta AVO") {
                    Text("El iPad recibe el directo por internet: el Android conectado al pecho lo sube mientras graba. Entra con la misma tarjeta AVO personal del Android, o con la tuya si el dueño te envía sus entrenamientos (invitación aceptada en Compartir).")
                        .font(.footnote).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                    Text("En el Android: Compartir › Mi cuenta › «Entrar en el iPad» muestra un código QR: pulsa «Escanear QR» y apunta la cámara. También puedes pegar el enlace o escribir el código y la clave.")
                        .font(.footnote).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                    Button("Escanear QR de la tarjeta") { localError = nil; scanning = true }
                        .buttonStyle(.avoPrimary)
                        .disabled(model.busy)
                        .padding(.top, 4)
                    Text("Enlace de la tarjeta").font(.caption.weight(.semibold)).foregroundStyle(Avo.silver).padding(.top, 6)
                    TextField("avohorse://identity/user/AVO-…", text: $link)
                        .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("o código y clave").font(.caption.weight(.semibold)).foregroundStyle(Avo.silver).padding(.top, 6)
                    HStack {
                        TextField("AVO-XXXX-XXXX", text: $code)
                            .textFieldStyle(.roundedBorder).textInputAutocapitalization(.characters).autocorrectionDisabled()
                            .frame(maxWidth: 220)
                        SecureField("Clave (32 caracteres)", text: $key)
                            .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    HStack {
                        Button(model.busy ? "Entrando…" : "Entrar") { submit() }
                            .buttonStyle(.avoPrimary)
                            .disabled(model.busy || (link.trimmingCharacters(in: .whitespaces).isEmpty && (code.isEmpty || key.isEmpty)))
                        Button("Simular con el entrenamiento abierto") { model.simulate() }
                            .buttonStyle(.avoSecondary)
                            .disabled(app.selected == nil)
                    }
                    .padding(.top, 6)
                    if let e = localError ?? model.error {
                        Text(e).font(.footnote).foregroundStyle(Avo.bad).fixedSize(horizontal: false, vertical: true)
                    }
                    Text("La tarjeta se guarda cifrada en el Llavero de este iPad. No se muestra ni se envía a ningún otro sitio.")
                        .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .sheet(isPresented: $scanning) {
            NavigationStack {
                QrScannerView(onCode: { text in
                    scanning = false
                    do {
                        let card: AvoUserCard = try AvoUserCard.parse(text)
                        Task { @MainActor in await model.signIn(card, save: true) }
                    } catch let e {
                        localError = "El QR no es de una tarjeta AVO: " + e.localizedDescription
                    }
                }, onError: { m in
                    scanning = false
                    localError = m
                })
                .ignoresSafeArea()
                .navigationTitle("Escanea el QR del Android")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { scanning = false } } }
            }
        }
    }

    private func submit() {
        localError = nil
        do {
            let card: AvoUserCard = link.trimmingCharacters(in: .whitespaces).isEmpty
                ? try AvoUserCard(code: code, name: "", secret: key)
                : try AvoUserCard.parse(link)
            Task { @MainActor in await model.signIn(card, save: true) }
        } catch let e {
            localError = e.localizedDescription
        }
    }
}

// MARK: - Pantalla en directo

private struct LiveDashboard: View {
    let model: LiveModel

    var body: some View {
        VStack(spacing: 8) {
            LiveTopBar(model: model)
            if model.source == .server && model.activeSessions.count > 1 { LiveHorsePicker(model: model) }
            LiveDataStrip(model: model)
            GeometryReader { geo in
                VStack(spacing: 8) {
                    ZStack(alignment: .bottom) {
                        LiveMap(model: model)
                        LiveSpeedOverlay(model: model)
                            .frame(height: max(110, geo.size.height * 0.62 * 0.36))
                            .padding(10)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .frame(height: geo.size.height * 0.62)
                    LivePulseChart()
                        .frame(height: (geo.size.height * 0.38 - 8) / 2)
                    LiveAccelChart(model: model)
                        .frame(height: (geo.size.height * 0.38 - 8) / 2)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// Selector de caballo cuando hay más de un directo a la vez (boceto del entrenador 20/11/2026).
private struct LiveHorsePicker: View {
    let model: LiveModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.activeSessions) { (r: LiveSessionRef) in
                    let on: Bool = model.current?.id == r.id
                    Button { model.open(r) } label: {
                        HStack(spacing: 6) {
                            Circle().fill(r.meta.state == "REC" ? Avo.red : (r.meta.state == "PAUSE" ? Avo.warn : Avo.ok)).frame(width: 8, height: 8)
                            Text(r.meta.horseName.isEmpty ? r.sid : r.meta.horseName).font(.subheadline.weight(.semibold)).lineLimit(1)
                            if !r.meta.riderName.isEmpty { Text("· \(r.meta.riderName)").font(.caption).foregroundStyle(Avo.textDim).lineLimit(1) }
                            Text(r.meta.stateText).font(.caption2.weight(.bold)).foregroundStyle(Avo.textDim)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .foregroundStyle(Avo.text)
                        .background(on ? Avo.red.opacity(0.16) : Avo.surface, in: Capsule())
                        .overlay(Capsule().stroke(on ? Avo.red : Avo.line, lineWidth: on ? 1.5 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct LiveTopBar: View {
    @Environment(AppModel.self) private var app
    let model: LiveModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            HStack(spacing: 10) {
                Circle().fill(dotColor(ctx.date)).frame(width: 10, height: 10)
                Text("LIVE").font(.headline.weight(.heavy)).tracking(1.5).foregroundStyle(Avo.text)
                if model.source == .simulation { AvoPill(text: "SIMULACIÓN", color: Avo.warn) }
                if let c = model.current {
                    Text(c.meta.horseName.isEmpty ? "Caballo sin asignar" : c.meta.horseName)
                        .font(.headline).foregroundStyle(Avo.text).lineLimit(1)
                    if !c.meta.riderName.isEmpty { Text("· \(c.meta.riderName)").font(.subheadline).foregroundStyle(Avo.textDim).lineLimit(1) }
                    AvoPill(text: model.state.meta.stateText, color: model.state.meta.isEnded ? Avo.unknown : Avo.ok)
                    if c.owner != model.signedCode && model.source == .server {
                        Text("de \(c.ownerName)").font(.caption).foregroundStyle(Avo.textDim).lineLimit(1)
                    }
                }
                if model.current == nil, let msg = model.message {
                    Text(msg).font(.caption).foregroundStyle(Avo.textDim).lineLimit(2)
                }
                Spacer(minLength: 8)
                if let a = model.ageSeconds(ctx.date), a > 5, model.source == .server, !model.state.meta.isEnded {
                    Text("Sin datos desde hace \(Int(a)) s").font(.caption.weight(.semibold)).foregroundStyle(Avo.warn)
                }
                if let e = model.error { Text(e).font(.caption).foregroundStyle(Avo.bad).lineLimit(1) }
                Menu {
                    if model.available.isEmpty { Text("Sin directos ahora") }
                    ForEach(model.available) { (r: LiveSessionRef) in
                        Button("\(r.meta.horseName.isEmpty ? r.sid : r.meta.horseName) · \(r.ownerName) · \(r.meta.stateText)") { model.open(r) }
                    }
                    Divider()
                    Button("Actualizar lista") { Task { @MainActor in await model.refresh() } }
                    Button("Simular con el entrenamiento abierto") { model.simulate() }.disabled(app.selected == nil)
                    if model.isLive { Button("Parar", role: .destructive) { model.stop() } }
                    if model.signedCode != nil { Button("Salir de la cuenta \(model.signedCode ?? "")", role: .destructive) { model.signOut() } }
                } label: {
                    Label("Directos", systemImage: "dot.radiowaves.left.and.right")
                }
                .buttonStyle(.avoSecondary)
            }
        }
        .padding(.top, 4)
    }

    private func dotColor(_ now: Date) -> Color {
        guard model.isLive else { return Avo.unknown }
        if model.state.meta.isEnded { return Avo.unknown }
        if let a = model.ageSeconds(now), a > 5 { return Avo.warn }
        return Avo.red
    }
}

/// L1: franja de datos en tiempo real.
private struct LiveDataStrip: View {
    let model: LiveModel

    var body: some View {
        let s: LiveSample? = model.latest
        let ser: LiveSeries = model.series
        let v: Double? = ser.speedKmh.last
        let a: Double? = ser.accel.last
        HStack(spacing: 0) {
            cell("TIEMPO", s.map { LiveFormat.clock($0.t) } ?? "—")
            cell("DISTANCIA", s.map { LiveFormat.distance($0.distanceM) } ?? "—")
            cell("VELOCIDAD", v.map { LiveFormat.num($0, 1) + " km/h" } ?? "—", accent: Avo.red)
            cell("ACELERACIÓN", a.map { LiveFormat.num($0, 2) + " m/s²" } ?? "—")
            cell("AIRE", s == nil ? "—" : ser.gait.rawValue, accent: Avo.cyan)
            cell("TIEMPO AIRE", s.map { LiveFormat.clock(max(0, $0.t - ser.gaitSince)) } ?? "—")
            cell("DIST. AIRE", s.map { LiveFormat.distance(max(0, $0.distanceM - ser.gaitStartDistanceM)) } ?? "—")
            cell("GNSS", s.map { LiveFormat.gnss($0) } ?? "—", accent: s.map { LiveFormat.gnssColor($0) } ?? Avo.textDim)
        }
        .padding(.vertical, 8)
        .background(Avo.cardBrush, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Avo.line, lineWidth: 1))
    }

    private func cell(_ label: String, _ value: String, accent: Color = Avo.text) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.caption2.weight(.semibold)).tracking(0.8).foregroundStyle(Avo.textDim).lineLimit(1)
            Text(value).font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(accent).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }
}

/// L3: mapa centrado que sigue al caballo (si el usuario lo mueve, deja de seguir hasta «Centrar»).
private struct LiveMap: View {
    let model: LiveModel
    @State private var position: MapCameraPosition = .automatic
    @State private var follow: Bool = true
    @State private var distance: Double = 700

    var body: some View {
        let pts: [CLLocationCoordinate2D] = LiveMap.track(model.samples)
        Map(position: $position) {
            if pts.count > 1 {
                MapPolyline(coordinates: pts).stroke(Color(hex: 0x35D0E8), lineWidth: 4)
            }
            if let p = pts.last {
                Annotation("", coordinate: p) {
                    ZStack {
                        Circle().fill(Avo.red.opacity(0.3)).frame(width: 30, height: 30)
                        Circle().fill(Avo.red).frame(width: 14, height: 14).overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
            }
        }
        .mapStyle(.imagery(elevation: .flat))
        .mapControls { MapCompass(); MapScaleView() }
        .onMapCameraChange(frequency: .onEnd) { ctx in
            if position.positionedByUser { follow = false } else { distance = ctx.camera.distance }
        }
        .onChange(of: model.samples.count) { _, _ in recenter(pts) }
        .onAppear { recenter(pts) }
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 8) {
                Button { follow = true; recenter(pts) } label: {
                    Label(follow ? "Siguiendo" : "Centrar", systemImage: follow ? "location.fill" : "location")
                }
                .buttonStyle(.avoSecondary)
                Button { follow = false; fitAll(pts) } label: { Label("Ver todo", systemImage: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(.avoSecondary)
            }
            .padding(10)
        }
        .overlay {
            if pts.isEmpty { Text("Esperando posición…").font(.callout.weight(.semibold)).foregroundStyle(.white).padding(8).background(.black.opacity(0.5), in: Capsule()) }
        }
    }

    static func track(_ s: [LiveSample]) -> [CLLocationCoordinate2D] {
        let valid: [LiveSample] = s.filter { $0.hasPosition }
        let step: Int = max(1, valid.count / 3000)
        var out: [CLLocationCoordinate2D] = []
        out.reserveCapacity(valid.count / step + 1)
        for (i, x) in valid.enumerated() where i % step == 0 || i == valid.count - 1 {
            out.append(CLLocationCoordinate2D(latitude: x.lat, longitude: x.lon))
        }
        return out
    }

    private func recenter(_ pts: [CLLocationCoordinate2D]) {
        guard follow, let p = pts.last else { return }
        withAnimation(.easeInOut(duration: 0.4)) {
            position = .camera(MapCamera(centerCoordinate: p, distance: min(max(distance, 250), 4000)))
        }
    }

    private func fitAll(_ pts: [CLLocationCoordinate2D]) {
        guard !pts.isEmpty else { return }
        var r = MKMapRect.null
        for c in pts { let mp = MKMapPoint(c); r = r.union(MKMapRect(x: mp.x, y: mp.y, width: 1, height: 1)) }
        let padX: Double = max(r.size.width * 0.15, 200), padY: Double = max(r.size.height * 0.15, 200)
        withAnimation { position = .rect(r.insetBy(dx: -padX, dy: -padY)) }
    }
}

/// L4: velocidad en tiempo real sobre la parte baja del mapa.
private struct LiveSpeedOverlay: View {
    let model: LiveModel

    var body: some View {
        let pts: [LivePoint] = LivePoint.make(model.series.t, model.series.speedKmh)
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("VELOCIDAD").font(.caption2.weight(.bold)).tracking(1).foregroundStyle(.white)
                Spacer()
                if let v = model.series.speedKmh.last { Text(LiveFormat.num(v, 1) + " km/h").font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(.white) }
            }
            if pts.count > 1 {
                Chart(pts) { (p: LivePoint) in
                    AreaMark(x: .value("t", p.t), y: .value("km/h", p.v))
                        .foregroundStyle(LinearGradient(colors: [Avo.red.opacity(0.45), Avo.red.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("t", p.t), y: .value("km/h", p.v)).foregroundStyle(Avo.red).lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { v in
                    AxisGridLine().foregroundStyle(.white.opacity(0.15))
                    AxisValueLabel { if let s = v.as(Double.self) { Text(LiveFormat.clock(s)).foregroundStyle(.white.opacity(0.8)) } }
                } }
                .chartYAxis { AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(.white.opacity(0.15)); AxisValueLabel().foregroundStyle(.white.opacity(0.8))
                } }
                .chartYScale(domain: 0...max(20, (model.series.speedKmh.max() ?? 0) * 1.1))
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(8)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// L5: pulso en tiempo real. Aún no llega en directo (necesita la cincha con ECG y TELEMETRY v4).
private struct LivePulseChart: View {
    var body: some View {
        AvoCard(title: "Pulso", subtitle: "lpm · tiempo real", padding: 10, fill: true) {
            VStack(spacing: 4) {
                Image(systemName: "heart.slash").font(.title3).foregroundStyle(Avo.textDim)
                Text("Sin pulso en directo: llegará con la cincha con ECG (REV 5.10) y un cambio de protocolo del pecho.")
                    .font(.caption).foregroundStyle(Avo.textDim).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// L6: aceleración longitudinal en tiempo real (derivada de la velocidad GNSS; la de la IMU no llega en directo).
private struct LiveAccelChart: View {
    let model: LiveModel

    var body: some View {
        let pts: [LivePoint] = LivePoint.make(model.series.t, model.series.accel)
        AvoCard(title: "Aceleración", subtitle: "m/s² · tiempo real · calculada de la velocidad GNSS", padding: 10, fill: true) {
            if pts.count > 1 {
                Chart {
                    RuleMark(y: .value("0", 0.0)).foregroundStyle(Avo.line)
                    ForEach(pts) { (p: LivePoint) in
                        LineMark(x: .value("t", p.t), y: .value("m/s²", p.v)).foregroundStyle(Avo.blue).lineStyle(StrokeStyle(lineWidth: 1.6))
                    }
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 8)) { v in
                    AxisGridLine(); AxisValueLabel { if let s = v.as(Double.self) { Text(LiveFormat.clock(s)) } }
                } }
                .chartYScale(domain: -6.0...6.0)
            } else {
                AvoNoData(text: "Esperando datos…")
            }
        }
    }
}

struct LivePoint: Identifiable {
    let id: Int
    let t: Double
    let v: Double

    /// Como mucho ~1200 puntos por gráfica (las sesiones largas se diezman).
    static func make(_ t: [Double], _ v: [Double]) -> [LivePoint] {
        let n: Int = min(t.count, v.count)
        guard n > 0 else { return [] }
        let step: Int = max(1, n / 1200)
        var out: [LivePoint] = []
        var i: Int = 0
        while i < n { out.append(LivePoint(id: i, t: t[i], v: v[i])); i += step }
        if (n - 1) % step != 0 { out.append(LivePoint(id: n - 1, t: t[n - 1], v: v[n - 1])) }
        return out
    }
}

enum LiveFormat {
    static func clock(_ s: Double) -> String {
        let x: Int = Int(max(0, s).rounded(.down))
        return x >= 3600 ? String(format: "%d:%02d:%02d", x / 3600, (x / 60) % 60, x % 60) : String(format: "%02d:%02d", x / 60, x % 60)
    }

    static func num(_ v: Double, _ d: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.minimumFractionDigits = d; f.maximumFractionDigits = d
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.\(d)f", v)
    }

    static func distance(_ m: Double) -> String { m >= 1000 ? num(m / 1000, 2) + " km" : "\(Int(m.rounded())) m" }

    static func gnss(_ s: LiveSample) -> String {
        switch s.solution {
        case .rtkFix: return "RTK FIX"
        case .rtkFloat: return "RTK FLOAT"
        case .none: return "SIN FIX"
        default: return "GNSS · \(s.numSv) sat"
        }
    }

    static func gnssColor(_ s: LiveSample) -> Color {
        switch s.solution {
        case .rtkFix: return Avo.ok
        case .rtkFloat: return Avo.cyan
        case .none: return Avo.bad
        default: return Avo.warn
        }
    }
}
