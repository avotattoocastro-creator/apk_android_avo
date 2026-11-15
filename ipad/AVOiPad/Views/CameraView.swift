import SwiftUI
import AVFoundation
import AVKit
import UIKit

/// Página «Cámara» (boceto del entrenador 14/11/2026: debajo de «Análisis»). Graba el entrenamiento con la hora GPS del
/// gadget AVO SYNC en cada fotograma (o con el reloj del iPad si no hay gadget) para juntarlo después con los datos del
/// caballo por la hora. Diseño y protocolo: docs/AVO_SYNC.md.
struct CameraView: View {
    @Environment(AppModel.self) private var app
    @State private var confirmDelete: CameraClip? = nil
    /// Panel desplegable de la derecha (AVO SYNC, grabación, vídeos). Boceto del entrenador 15/11/2026: la cámara ocupa
    /// todo el ancho y el panel se despliega desde el botón junto a la hora.
    @AppStorage("camera.panelOpen") private var panelOpen: Bool = false

    var body: some View {
        let m: CameraModel = app.camera
        GeometryReader { geo in
            let panelWidth: CGFloat = min(390, geo.size.width * 0.85)
            ZStack(alignment: .topTrailing) {
                previewArea(m, panelInset: panelOpen ? panelWidth : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if panelOpen {
                    drawer(m)
                        .frame(width: panelWidth)
                        .frame(maxHeight: .infinity)
                        .transition(.move(edge: .trailing))
                }
            }
            .onChange(of: geo.size) { (_: CGSize, _: CGSize) in m.updateRotation() }
        }
        .background(Color.black)
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            // la escena gira un poco después del aviso del dispositivo
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { m.updateRotation() }
        }
        // reproductor a pantalla completa (boceto del entrenador 15/11/2026)
        .fullScreenCover(item: Binding(get: { m.playing }, set: { m.playing = $0 })) { (c: CameraClip) in
            CameraClipPlayer(model: m, clipId: c.id).avoColorScheme()
        }
        .alert("¿Borrar el vídeo?",
               isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
               presenting: confirmDelete) { (c: CameraClip) in
            Button("Borrar", role: .destructive) { m.delete(c); confirmDelete = nil }
            Button("Cancelar", role: .cancel) { confirmDelete = nil }
        } message: { (c: CameraClip) in
            Text("Se borran \(c.videoURL.lastPathComponent) y su archivo de hora. No se puede deshacer.")
        }
    }

    // ------------------------------------------------------------------ vista previa
    @ViewBuilder
    private func previewArea(_ m: CameraModel, panelInset: CGFloat) -> some View {
        ZStack {
            Color.black
            switch m.access {
            case .granted:
                CameraPreview(session: m.recorder.session, angle: m.rotation)
            case .denied:
                VStack(spacing: 12) {
                    Image(systemName: "video.slash").font(.system(size: 40, weight: .light)).foregroundStyle(Avo.silver)
                    Text("La app no tiene permiso para usar la cámara.").foregroundStyle(Avo.text)
                    Button("Abrir Ajustes") {
                        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                    }
                    .buttonStyle(.avoSecondary)
                }
            case .noCamera:
                VStack(spacing: 12) {
                    Image(systemName: "video.slash").font(.system(size: 40, weight: .light)).foregroundStyle(Avo.silver)
                    Text("Este dispositivo no tiene cámara trasera.").foregroundStyle(Avo.textDim)
                }
            case .unknown:
                ProgressView()
            }
        }
        .overlay(alignment: .top) {
            if m.recording { recBadge(m).padding(.top, 14) }
        }
        .overlay(alignment: .topTrailing) {
            HStack(alignment: .top, spacing: 10) {
                clockBadge(m)
                panelButton(m)
            }
            .padding(.top, 14)
            .padding(.trailing, 14 + panelInset)
        }
        .overlay(alignment: .bottom) {
            recordButton(m).padding(.bottom, 24)
        }
        .overlay {
            if m.recording { Rectangle().stroke(Avo.red, lineWidth: 3).allowsHitTesting(false) }
        }
        .clipped()
    }

    /// Botón junto a la hora que despliega o recoge el panel.
    private func panelButton(_ m: CameraModel) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { panelOpen.toggle() }
        } label: {
            Image(systemName: panelOpen ? "chevron.right" : "slider.horizontal.3")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) {
                    // estado de AVO SYNC también con el panel recogido
                    Circle().fill(m.gpsTimeOK ? Avo.ok : (m.syncConnected ? Avo.warn : Avo.unknown))
                        .frame(width: 9, height: 9).padding(5)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(panelOpen ? "Recoger panel" : "Desplegar panel")
        .accessibilityIdentifier("camera.panel")
    }

    /// Panel desplegable sobre la imagen, a la derecha.
    private func drawer(_ m: CameraModel) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("CÁMARA").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(Avo.silver)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { panelOpen = false }
                } label: {
                    Image(systemName: "xmark").font(.callout.weight(.semibold)).foregroundStyle(Avo.text)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cerrar panel")
            }
            .padding(.horizontal, 14).padding(.top, 8)
            ScrollView { sidePanel(m).padding(14) }
        }
        .background(Avo.bg.opacity(0.94))
        .overlay(alignment: .leading) { Rectangle().fill(Avo.line).frame(width: 1) }
    }

    private func recBadge(_ m: CameraModel) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let s: Int = m.recordStartHostNs.map { Int((AvoHostClock.nowNs() - $0) / 1_000_000_000) } ?? 0
            HStack(spacing: 6) {
                Circle().fill(Avo.red).frame(width: 10, height: 10)
                Text(String(format: "REC %02d:%02d", s / 60, s % 60)).font(.system(.callout, design: .monospaced).weight(.bold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.black.opacity(0.55), in: Capsule())
        }
    }

    private func clockBadge(_ m: CameraModel) -> some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { _ in
            VStack(alignment: .trailing, spacing: 2) {
                Text(AvoSyncText.clock(m.nowUtcNs())).font(.system(.title3, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.white)
                Text(m.gpsTimeOK ? "HORA GPS · AVO SYNC" : "RELOJ DEL IPAD")
                    .font(.caption2.weight(.bold)).tracking(0.6)
                    .foregroundStyle(m.gpsTimeOK ? Avo.ok : Avo.warn)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityIdentifier("camera.clock")
    }

    private func recordButton(_ m: CameraModel) -> some View {
        Button { m.toggleRecording() } label: {
            ZStack {
                Circle().stroke(Color.white, lineWidth: 4).frame(width: 74, height: 74)
                if m.recording {
                    RoundedRectangle(cornerRadius: 6).fill(Avo.red).frame(width: 30, height: 30)
                } else {
                    Circle().fill(Avo.red).frame(width: 60, height: 60)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!m.running)
        .opacity(m.running ? 1 : 0.4)
        .accessibilityLabel(m.recording ? "Parar grabación" : "Grabar")
        .accessibilityIdentifier("camera.record")
    }

    // ------------------------------------------------------------------ panel lateral
    private func sidePanel(_ m: CameraModel) -> some View {
        VStack(spacing: 14) {
            syncCard(m)
            recordingCard(m)
            clipsCard(m)
        }
    }

    private func syncCard(_ m: CameraModel) -> some View {
        AvoCard(title: "AVO SYNC", subtitle: "Hora GPS para cada fotograma") {
            HStack(spacing: 8) {
                Circle().fill(m.gpsTimeOK ? Avo.ok : (m.syncConnected ? Avo.warn : Avo.unknown)).frame(width: 9, height: 9)
                Text(m.syncState.text).font(.callout).foregroundStyle(Avo.text).lineLimit(2)
                Spacer(minLength: 0)
            }
            if m.syncIdle {
                Button { m.connectSync() } label: { Label("Conectar AVO SYNC", systemImage: "antenna.radiowaves.left.and.right") }
                    .buttonStyle(.avoSecondary)
                    .accessibilityIdentifier("camera.sync.connect")
            } else {
                Button { m.disconnectSync() } label: { Label("Desconectar", systemImage: "xmark.circle") }
                    .buttonStyle(.avoSecondary)
            }
            if m.syncConnected {
                VStack(spacing: 6) {
                    kv("Hora GPS", m.syncFlags.contains(.holdover) ? "En retención (sin fix)"
                        : (m.syncFlags.contains(.timeValid) ? "Válida" : "Esperando satélites"),
                       color: m.syncFlags.contains(.timeValid) && !m.syncFlags.contains(.holdover) ? Avo.ok : Avo.warn)
                    kv("Satélites", "\(m.syncSatellites)")
                    kv("Precisión (E)", m.live.errorBoundNs.map { "± " + AvoSyncText.ms($0) } ?? "—")
                    kv("Retardo mínimo BLE", m.live.minDelayNs.map { AvoSyncText.ms($0) } ?? "—")
                    kv("Muestras", "\(m.live.accepted) válidas · \(m.live.rejected) descartadas")
                    if let s = m.syncStatus {
                        kv("Batería", "\(s.batteryPercent) % · \(s.batteryMv) mV")
                        kv("Precisión horizontal GPS", String(format: "%.1f m", Double(s.hAccMm) / 1000))
                    }
                }
            }
            if !m.gpsTimeOK {
                Text("Sin hora GPS, el vídeo se graba con el reloj del iPad (precisión de decenas de ms, estimada). Se puede juntar con el entrenamiento, pero con menos exactitud.")
                    .font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func recordingCard(_ m: CameraModel) -> some View {
        AvoCard(title: "Grabación", subtitle: "Cámara trasera · HEVC") {
            if !m.formats.isEmpty {
                HStack {
                    Text("Formato").font(.callout).foregroundStyle(Avo.silver)
                    Spacer()
                    Menu {
                        ForEach(m.formats) { (f: CameraFormat) in
                            Button { m.select(f) } label: {
                                if f == m.format { Label(f.title, systemImage: "checkmark") } else { Text(f.title) }
                            }
                        }
                    } label: {
                        Text(m.format?.title ?? "—").font(.callout.weight(.semibold))
                    }
                    .disabled(m.recording)
                }
            }
            HStack {
                Text("Caballo").font(.callout).foregroundStyle(Avo.silver)
                Spacer()
                Menu {
                    Button { m.recordHorse = nil } label: {
                        if m.recordHorse == nil { Label("Sin elegir", systemImage: "checkmark") } else { Text("Sin elegir") }
                    }
                    ForEach(m.horseOptions, id: \.self) { (h: String) in
                        Button { m.recordHorse = h } label: {
                            if m.recordHorse == h { Label(h, systemImage: "checkmark") } else { Text(h) }
                        }
                    }
                } label: {
                    Text(m.recordHorse ?? "Sin elegir").font(.callout.weight(.semibold)).lineLimit(1)
                }
                .disabled(m.recording)
            }
            Text("El vídeo se asocia solo al entrenamiento de ese caballo que coincida en hora; se puede cambiar al verlo.")
                .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            Text("Marcas").font(.caption.weight(.semibold)).foregroundStyle(Avo.silver).padding(.top, 2)
            HStack(spacing: 8) {
                markButton(m, .series, "Serie")
                markButton(m, .lap, "Vuelta")
                markButton(m, .end, "Fin")
            }
            if let lm = m.lastMark {
                Text("Última marca: \(lm)").font(.caption).foregroundStyle(Avo.textDim)
            }
            if let e = m.error {
                Text(e).font(.caption).foregroundStyle(Avo.bad).fixedSize(horizontal: false, vertical: true)
            }
            Text("Al salir de esta página la grabación se para y se guarda.")
                .font(.caption2).foregroundStyle(Avo.textDim)
        }
    }

    private func markButton(_ m: CameraModel, _ k: AvoSyncProtocol.MarkKind, _ title: String) -> some View {
        Button(title) { m.markNow(k) }
            .buttonStyle(.avoSecondary)
            .disabled(!m.recording)
            .opacity(m.recording ? 1 : 0.5)
    }

    private func clipsCard(_ m: CameraModel) -> some View {
        AvoCard(title: "Vídeos grabados", subtitle: "Se guardan en el iPad con su archivo de hora (.avosync.json)") {
            if m.clips.isEmpty {
                AvoNoData(text: "Todavía no hay vídeos")
            } else {
                VStack(spacing: 0) {
                    ForEach(m.clips) { (c: CameraClip) in
                        clipRow(m, c)
                        if c != m.clips.last { Divider().background(Avo.line) }
                    }
                }
            }
        }
    }

    private func clipRow(_ m: CameraModel, _ c: CameraClip) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(c.sync.map { MadridTime.format($0.startDate, "dd/MM/yyyy HH:mm:ss") } ?? c.name)
                    .font(.callout.weight(.semibold)).foregroundStyle(Avo.text).lineLimit(1)
                Text(m.training(c).map { "\($0.horse) · entreno \($0.timeText)" } ?? ((c.sync?.horse).map { "\($0) · sin entrenamiento" } ?? "Sin entrenamiento"))
                    .font(.caption).foregroundStyle(m.training(c) != nil ? Avo.ok : Avo.textDim).lineLimit(1)
                HStack(spacing: 6) {
                    if let s = c.sync {
                        Text(durationText(s.durationS)).font(.caption.monospacedDigit()).foregroundStyle(Avo.textDim)
                        Text("\(s.height >= 2160 ? "4K" : "\(min(s.width, s.height))p") · \(Int(s.fpsNominal)) fps")
                            .font(.caption).foregroundStyle(Avo.textDim)
                        if s.source == .avoSync {
                            AvoPill(text: s.errorBoundMs.map { String(format: "GPS ±%.0f ms", max($0, 1)) } ?? "GPS",
                                    color: s.holdover ? Avo.warn : Avo.ok)
                        } else {
                            AvoPill(text: "RELOJ IPAD", color: Avo.warn)
                        }
                    } else {
                        AvoPill(text: "SIN HORA", color: Avo.bad)
                    }
                }
            }
            Spacer(minLength: 4)
            Button { m.playing = c } label: { Image(systemName: "play.fill") }
                .buttonStyle(.avoSecondary)
                .accessibilityLabel("Reproducir")
            ShareLink(items: [c.videoURL] + (AvoFiles.exists(c.syncURL.path) ? [c.syncURL] : [])) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.avoSecondary)
            .accessibilityLabel("Compartir")
            Button { confirmDelete = c } label: { Image(systemName: "trash") }
                .buttonStyle(.avoSecondary)
                .disabled(m.recording)
                .accessibilityLabel("Borrar")
        }
        .padding(.vertical, 8)
    }

    private func kv(_ k: String, _ v: String, color: Color = Avo.text) -> some View {
        HStack {
            Text(k).font(.caption).foregroundStyle(Avo.textDim)
            Spacer()
            Text(v).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(color).multilineTextAlignment(.trailing)
        }
    }

    private func durationText(_ s: Double) -> String {
        let t = Int(s.rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

/// Vista previa de la cámara (AVCaptureVideoPreviewLayer).
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let angle: CGFloat

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.backgroundColor = .black
        v.previewLayer.session = session
        // la imagen ocupa todo el recuadro (boceto 15/11/2026); el vídeo grabado conserva el encuadre completo del sensor
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ v: PreviewView, context: Context) {
        if let c = v.previewLayer.connection, c.isVideoRotationAngleSupported(angle) {
            c.videoRotationAngle = angle
        }
    }
}

/// Reproductor a pantalla completa de un vídeo grabado: datos del entrenamiento asociado encima de la imagen (los mismos
/// que se imprimen al exportar), elección del entrenamiento y de los datos, recorte por delante y por detrás, exportar
/// con los datos y guardar en Fotos.
struct CameraClipPlayer: View {
    let model: CameraModel
    let clipId: String
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer? = nil
    @State private var videoT: Double = 0
    @State private var videoSize: CGSize = .zero
    @State private var telemetry: VideoTelemetry? = nil
    @State private var telemetryId: String? = nil
    @State private var gauges: Set<VideoGauge> = VideoGauge.load()
    @State private var dragA: Double? = nil
    @State private var dragB: Double? = nil

    private var clip: CameraClip? { model.clip(id: clipId) }

    var body: some View {
        VStack(spacing: 8) {
            if let c = clip, let s = c.sync {
                topBar(c, s)
                videoArea(c, s)
                trimBar(c, s)
            } else {
                HStack {
                    Spacer()
                    Button("Cerrar") { dismiss() }.buttonStyle(.avoSecondary)
                }
                Spacer()
                Text("Este vídeo no tiene archivo de hora (.avosync.json): no se puede juntar con un entrenamiento.")
                    .foregroundStyle(.white)
                Spacer()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            if player == nil, let c = clip {
                let p = AVPlayer(url: c.videoURL)
                player = p
                if let s = c.sync { p.seek(to: CMTime(seconds: s.trimmedRange.lowerBound, preferredTimescale: 600)) }
            }
        }
        .onDisappear { player?.pause() }
        .task { await loop() }
    }

    /// 30 veces por segundo: posición del vídeo, límites del recorte y entrenamiento asociado.
    private func loop() async {
        while !Task.isCancelled {
            if let p = player, let c = clip, let s = c.sync {
                let t = p.currentTime().seconds
                if t.isFinite { videoT = t }
                let r = s.trimmedRange
                if p.rate != 0 && t > r.upperBound { p.pause(); p.seek(to: CMTime(seconds: r.lowerBound, preferredTimescale: 600)) }
                else if p.rate != 0 && t < r.lowerBound - 0.1 { p.seek(to: CMTime(seconds: r.lowerBound, preferredTimescale: 600)) }
                if let ps = p.currentItem?.presentationSize, ps.width > 0, ps != videoSize { videoSize = ps }
                let item = model.training(c)
                if item?.id != telemetryId {
                    telemetryId = item?.id
                    telemetry = item.flatMap { VideoTelemetry($0) }
                }
            }
            try? await Task.sleep(nanoseconds: 33_000_000)
        }
    }

    // ------------------------------------------------------------------ barra superior
    private func topBar(_ c: CameraClip, _ s: AvoSyncVideoFile) -> some View {
        HStack(spacing: 10) {
            Button { player?.pause(); dismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(.avoSecondary)
                .accessibilityLabel("Cerrar")
            VStack(alignment: .leading, spacing: 2) {
                Text(MadridTime.format(s.startDate, "dd/MM/yyyy HH:mm:ss")).font(.headline).foregroundStyle(.white).lineLimit(1)
                Text(sourceText(s)).font(.caption).foregroundStyle(Color.white.opacity(0.7)).lineLimit(1)
            }
            Spacer(minLength: 6)
            trainingMenu(c)
            gaugesMenu()
            exportControls(c)
        }
    }

    private func trainingMenu(_ c: CameraClip) -> some View {
        let current = model.training(c)
        return Menu {
            Section("Entrenamiento del vídeo") {
                Button { model.associate(c, nil, auto: true) } label: {
                    Label("Automático (por la hora)", systemImage: c.sync?.trainingId == nil ? "checkmark" : "clock")
                }
                ForEach(model.candidates(c).prefix(15), id: \.id) { (it: SessionItem) in
                    Button { model.associate(c, it) } label: {
                        let mark: String = (c.sync?.trainingId == it.id) ? "checkmark" : (model.overlaps(c, it) ? "clock.badge.checkmark" : "calendar")
                        Label("\(it.horse) · \(it.dateTimeText) · \(it.distanceText)", systemImage: mark)
                    }
                }
                Button(role: .destructive) { model.associate(c, nil) } label: { Label("Ninguno", systemImage: "xmark") }
            }
            Section("Caballo del vídeo") {
                ForEach(model.horseOptions, id: \.self) { (h: String) in
                    Button { model.setHorse(c, h) } label: {
                        if c.sync?.horse == h { Label(h, systemImage: "checkmark") } else { Text(h) }
                    }
                }
            }
        } label: {
            Label(current.map { "\($0.horse) · \($0.dateTimeText)" } ?? "Sin entrenamiento", systemImage: "link")
                .lineLimit(1)
        }
        .buttonStyle(.avoSecondary)
    }

    private func gaugesMenu() -> some View {
        Menu {
            ForEach(VideoGauge.allCases) { (g: VideoGauge) in
                Button {
                    if gauges.contains(g) { gauges.remove(g) } else { gauges.insert(g) }
                    VideoGauge.save(gauges)
                } label: {
                    let title: String = g == .pulse && !(telemetry?.hasPulse ?? false) ? g.title + " (sin datos)" : g.title
                    if gauges.contains(g) { Label(title, systemImage: "checkmark") } else { Text(title) }
                }
            }
        } label: {
            Label("Datos", systemImage: "gauge.with.dots.needle.67percent")
        }
        .menuActionDismissBehavior(.disabled)
        .buttonStyle(.avoSecondary)
    }

    @ViewBuilder
    private func exportControls(_ c: CameraClip) -> some View {
        if model.exportingClipId == c.id, let p = model.exportProgress {
            HStack(spacing: 8) {
                ProgressView(value: p).frame(width: 110).tint(Avo.red)
                Text("\(Int(p * 100)) %").font(.caption.monospacedDigit()).foregroundStyle(.white)
                Button("Cancelar") { model.cancelExport() }.buttonStyle(.avoSecondary)
            }
        } else {
            Button { player?.pause(); model.export(c, gauges: gauges) } label: {
                Label("Exportar con datos", systemImage: "square.and.arrow.down.on.square")
            }
            .buttonStyle(.avoPrimary)
            .disabled(model.exportProgress != nil)
            if model.hasExport(c) {
                let url = model.exportURL(c)
                Button { model.saveToPhotos(url) } label: { Image(systemName: "photo.badge.arrow.down") }
                    .buttonStyle(.avoSecondary)
                    .accessibilityLabel("Guardar en Fotos")
                ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                    .buttonStyle(.avoSecondary)
                    .accessibilityLabel("Compartir vídeo con datos")
            }
        }
    }

    // ------------------------------------------------------------------ vídeo con los datos encima
    @ViewBuilder
    private func videoArea(_ c: CameraClip, _ s: AvoSyncVideoFile) -> some View {
        if let p = player {
            VideoPlayer(player: p) {
                GeometryReader { geo in
                    let rect: CGRect = videoSize.width > 0
                        ? AVMakeRect(aspectRatio: videoSize, insideRect: CGRect(origin: .zero, size: geo.size))
                        : CGRect(origin: .zero, size: geo.size)
                    let utcNs: Int64 = s.utcNs(videoTimeS: videoT)
                    let input = VideoOverlayRenderer.Input(
                        telemetry: telemetry,
                        sample: telemetry?.sample(utcS: Double(utcNs) / 1e9) ?? VideoTelemetrySample(inRange: false),
                        gauges: gauges, utcText: AvoSyncText.clock(utcNs),
                        timeSource: s.source == .avoSync ? "HORA GPS · AVO SYNC" : "RELOJ DEL IPAD")
                    Canvas { ctx, size in
                        ctx.withCGContext { cg in VideoOverlayRenderer.draw(cg, size: size, input) }
                    }
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let e = model.error {
                Text(e).font(.caption).foregroundStyle(Avo.bad).lineLimit(2)
            } else if let i = model.info {
                Text(i).font(.caption).foregroundStyle(Avo.ok).lineLimit(1)
            }
        } else {
            Spacer()
        }
    }

    // ------------------------------------------------------------------ recorte
    private func trimBar(_ c: CameraClip, _ s: AvoSyncVideoFile) -> some View {
        let d: Double = max(s.durationS, 0.1)
        let r = s.trimmedRange
        let a: Double = dragA ?? r.lowerBound
        let b: Double = dragB ?? r.upperBound
        return VStack(spacing: 6) {
            GeometryReader { geo in
                let w: CGFloat = geo.size.width
                let xa: CGFloat = CGFloat(a / d) * w
                let xb: CGFloat = CGFloat(b / d) * w
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18)).frame(height: 8)
                    Rectangle().fill(Avo.red.opacity(0.75)).frame(width: max(xb - xa, 2), height: 8).offset(x: xa)
                    // marcas
                    ForEach(s.marks.indices, id: \.self) { (i: Int) in
                        let tm: Double = Double(s.marks[i].utcNs - s.firstFrameUtcNs) / 1e9
                        Rectangle().fill(Avo.warn).frame(width: 2, height: 18).offset(x: CGFloat(tm / d) * w - 1)
                    }
                    // posición actual
                    Rectangle().fill(Color.white).frame(width: 2, height: 26).offset(x: CGFloat(min(max(videoT, 0), d) / d) * w - 1)
                    handle(x: xa, w: w, d: d) { v in dragA = min(v, b - 0.5) } end: {
                        if let v = dragA { model.setTrim(c, start: v, end: s.trimEndS) }
                        dragA = nil
                    }
                    handle(x: xb, w: w, d: d) { v in dragB = max(v, a + 0.5) } end: {
                        if let v = dragB { model.setTrim(c, start: s.trimStartS, end: v) }
                        dragB = nil
                    }
                }
                .frame(height: 34)
                .coordinateSpace(name: "trim")
                .contentShape(Rectangle())
                .onTapGesture { (p: CGPoint) in
                    let t = Double(p.x / w) * d
                    player?.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                }
            }
            .frame(height: 34)
            HStack(spacing: 8) {
                Button("Inicio aquí") { model.setTrim(c, start: videoT, end: s.trimEndS) }.buttonStyle(.avoSecondary)
                Button("Fin aquí") { model.setTrim(c, start: s.trimStartS, end: videoT) }.buttonStyle(.avoSecondary)
                Button("Quitar recorte") { model.setTrim(c, start: nil, end: nil) }
                    .buttonStyle(.avoSecondary)
                    .disabled(s.trimStartS == nil && s.trimEndS == nil)
                Text("\(clock(a)) – \(clock(b)) · \(clock(b - a))").font(.caption.monospacedDigit()).foregroundStyle(.white)
                Spacer()
                ForEach(s.marks.indices, id: \.self) { (i: Int) in
                    let mk: AvoSyncVideoFile.MarkEntry = s.marks[i]
                    Button(mk.kind.title) {
                        let t = Double(mk.utcNs - s.firstFrameUtcNs) / 1e9
                        player?.seek(to: CMTime(seconds: max(0, t), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                    }
                    .buttonStyle(.avoSecondary)
                }
            }
        }
    }

    private func handle(x: CGFloat, w: CGFloat, d: Double, change: @escaping (Double) -> Void, end: @escaping () -> Void) -> some View {
        RoundedRectangle(cornerRadius: 4).fill(Color.white)
            .frame(width: 14, height: 34)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Avo.red, lineWidth: 2))
            .offset(x: x - 7)
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("trim"))
                .onChanged { (g: DragGesture.Value) in
                    let v = Double(min(max(g.location.x, 0), w) / w) * d
                    change(v)
                    player?.seek(to: CMTime(seconds: v, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                }
                .onEnded { _ in end() })
    }

    private func clock(_ s: Double) -> String {
        let t = max(0, s)
        return String(format: "%d:%04.1f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60)).replacingOccurrences(of: ".", with: ",")
    }

    private func sourceText(_ s: AvoSyncVideoFile) -> String {
        switch s.source {
        case .avoSync:
            return "Hora GPS de AVO SYNC" + (s.errorBoundMs.map { String(format: " · ±%.1f ms (estimada)", $0) } ?? "")
                + (s.holdover ? " · hubo retención" : "")
        case .ipadClock:
            return "Reloj del iPad (sin AVO SYNC) · precisión de decenas de ms (estimada)"
        }
    }
}
