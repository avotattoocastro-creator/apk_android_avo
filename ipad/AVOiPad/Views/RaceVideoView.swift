import SwiftUI
import AVFoundation
import PhotosUI
import Charts
import UniformTypeIdentifiers

/// Video picked in Photos (screen recordings live there), copied to a temporary file.
struct RaceMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { (m: RaceMovie) in
            SentTransferredFile(m.url)
        } importing: { (received: ReceivedTransferredFile) in
            let dst: URL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_" + received.file.lastPathComponent)
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.copyItem(at: received.file, to: dst)
            return RaceMovie(url: dst)
        }
    }
}

/// «Análisis automático del vídeo de la carrera» (App/RaceVideoModel.swift).
struct RaceVideoView: View {
    @Environment(AppModel.self) private var app
    @Bindable var model: RaceVideoModel
    @State private var photo: PhotosPickerItem? = nil
    @State private var pickingFile: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().overlay(Avo.line)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    RaceVideoStage(model: model)
                    RaceVideoProgress(model: model)
                }
                .padding(12)
                Divider().overlay(Avo.line)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        RaceVideoDataCard(model: model)
                        if let r = model.result {
                            RaceVideoResultCard(model: model, result: r)
                        } else if model.analysed {
                            AvoCard(title: "Falta para ver y guardar el resultado", subtitle: "El vídeo ya está analizado: no hace falta repetirlo") {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(model.missing, id: \.self) { (t: String) in
                                        Text("• " + t).font(.callout).foregroundStyle(Avo.warn).fixedSize(horizontal: false, vertical: true)
                                    }
                                    Text("Al rellenarlo aparece el resultado y el botón «Guardar en Carreras». El análisis se guarda en Carreras (ficha «VÍDEO» de la carrera, con la comparación con entrenamientos) y el vídeo en Archivos › AVO Horse › Carreras › Vídeos.")
                                        .font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .padding(14)
                }
                .frame(width: 420)
                .background(Avo.surface)
            }
        }
        .background(Avo.bg)
        .onChange(of: photo) { (_: PhotosPickerItem?, item: PhotosPickerItem?) in
            guard let item = item else { return }
            Task { @MainActor in
                model.status = "Cargando el vídeo de Fotos…"
                if let m = try? await item.loadTransferable(type: RaceMovie.self) {
                    model.openFile(m.url)
                } else {
                    model.status = "No se pudo cargar el vídeo de Fotos."
                }
                photo = nil
            }
        }
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: [UTType.movie], allowsMultipleSelection: false) { (res: Result<[URL], Error>) in
            if case .success(let urls) = res, let u = urls.first { model.openFile(u) }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { model.close() } label: { Label("Cerrar", systemImage: "xmark") }
                .buttonStyle(.avoSecondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("ANÁLISIS AUTOMÁTICO DEL VÍDEO").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(Avo.silver)
                Text(model.sourceLabel.isEmpty ? "Sin vídeo" : model.sourceLabel)
                    .font(.caption2).foregroundStyle(Avo.textDim).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            PhotosPicker(selection: $photo, matching: .videos) {
                Label("Fotos", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.avoSecondary)
            .disabled(model.running)
            Button { pickingFile = true } label: { Label("Archivos", systemImage: "folder") }
                .buttonStyle(.avoSecondary)
                .disabled(model.running)
            if model.videoCandidates.count > 1 {
                Menu {
                    ForEach(model.videoCandidates, id: \.self) { (u: String) in
                        Button(URL(string: u)?.lastPathComponent ?? u) { model.openURL(u) }
                    }
                } label: {
                    Label("Otra fuente", systemImage: "list.bullet")
                }
                .buttonStyle(.avoSecondary)
                .disabled(model.running)
            }
            Toggle("½ velocidad", isOn: $model.slow)
                .toggleStyle(.button)
                .disabled(model.running)
            Toggle("Pausa automática", isOn: $model.autoPause)
                .toggleStyle(.button)
            if model.running {
                if model.paused {
                    Button { model.resume() } label: { Label("Continuar", systemImage: "play.fill") }
                        .buttonStyle(.avoPrimary)
                } else {
                    Button { model.pause(waiting: false) } label: { Label("Pausar", systemImage: "pause.fill") }
                        .buttonStyle(.avoSecondary)
                }
                Button { model.finishNow() } label: { Label("Detener y calcular", systemImage: "stop.fill") }
                    .buttonStyle(.avoSecondary)
            } else {
                Button { model.start() } label: { Label("Analizar automáticamente", systemImage: "wand.and.stars") }
                    .buttonStyle(.avoPrimary)
                    .disabled(!model.hasVideo)
                    .accessibilityIdentifier("raceVideo.start")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Avo.headerBrush)
    }
}

// ---------------------------------------------------------------- video + overlay

private final class PlayerUIView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer?
    let version: Int

    func makeUIView(context: Context) -> PlayerUIView {
        let v = PlayerUIView()
        v.backgroundColor = .black
        v.playerLayer.videoGravity = .resizeAspect
        v.playerLayer.player = player
        return v
    }

    func updateUIView(_ v: PlayerUIView, context: Context) {
        if v.playerLayer.player !== player { v.playerLayer.player = player }
    }
}

private struct RaceVideoStage: View {
    @Bindable var model: RaceVideoModel
    @State private var stroke: [CGPoint] = []

    var body: some View {
        GeometryReader { (geo: GeometryProxy) in
            let rect: CGRect = fit(model.frameSize, geo.size)
            ZStack(alignment: .topLeading) {
                PlayerLayerView(player: model.player, version: model.playerVersion)
                if model.frameSize.width > 0 {
                    ForEach(Array(model.otherBoxes.enumerated()), id: \.offset) { (e: (offset: Int, element: CGRect)) in
                        box(e.element, rect, color: Color.white.opacity(0.55), width: 1)
                    }
                    if let t = model.targetBox {
                        box(t, rect, color: Avo.red, width: 3)
                        Text("TU CABALLO")
                            .font(.caption2.weight(.bold)).foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Avo.red, in: RoundedRectangle(cornerRadius: 3))
                            .position(x: rect.minX + (t.midX / model.frameSize.width) * rect.width,
                                      y: max(10, rect.minY + (t.minY / model.frameSize.height) * rect.height - 12))
                    }
                }
                if stroke.count > 1 {
                    Path { (p: inout Path) in p.addLines(stroke) }
                        .stroke(Avo.red, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
                if model.waitingSelection { selectionBanner }
                if !model.hasVideo {
                    VStack(spacing: 8) {
                        Image(systemName: "video.slash").font(.largeTitle).foregroundStyle(Avo.textDim)
                        Text("Sin vídeo: elige uno en Fotos o Archivos").foregroundStyle(Avo.textDim)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .contentShape(Rectangle())
            // circle (or box) the horse with the Pencil or a finger: the video pauses and the drawn area is followed
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .local)
                    .onChanged { (v: DragGesture.Value) in
                        if stroke.isEmpty {
                            stroke = [v.startLocation]
                            if model.running && !model.paused { model.pause(waiting: true) }
                        }
                        stroke.append(v.location)
                    }
                    .onEnded { (_: DragGesture.Value) in
                        let pts: [CGPoint] = stroke
                        stroke = []
                        let r: CGRect = fit(model.frameSize.width > 0 ? model.frameSize : CGSize(width: 16, height: 9), geo.size)
                        guard let n = RaceVideoStage.normalizedBounds(pts, in: r) else { return }
                        model.selectBox(n)
                    }
            )
            .simultaneousGesture(
                SpatialTapGesture(coordinateSpace: .local).onEnded { (v: SpatialTapGesture.Value) in
                    let p: CGPoint = v.location
                    let r: CGRect = fit(model.frameSize.width > 0 ? model.frameSize : CGSize(width: 16, height: 9), geo.size)
                    guard r.contains(p) else { return }
                    model.tapVideo(CGPoint(x: (p.x - r.minX) / r.width, y: (p.y - r.minY) / r.height))
                }
            )
        }
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var selectionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.targetBox == nil ? "Rodea a tu caballo con el Pencil o el dedo" : "Caballo marcado")
                .font(.headline).foregroundStyle(.white)
            Text(model.trackStatus).font(.footnote).foregroundStyle(.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button { model.resume() } label: { Label("Continuar", systemImage: "play.fill") }
                    .buttonStyle(.avoPrimary)
                    .disabled(model.targetBox == nil)
                Button { model.skipUntilCut() } label: { Label("No se ve: seguir", systemImage: "forward.fill") }
                    .buttonStyle(.avoSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: 520, alignment: .leading)
        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Avo.red, lineWidth: 1))
        .padding(12)
    }

    /// Bounding box of the stroke inside the video rectangle, normalised 0…1 (top-left origin).
    static func normalizedBounds(_ pts: [CGPoint], in r: CGRect) -> CGRect? {
        guard pts.count >= 2, r.width > 0, r.height > 0 else { return nil }
        var minX: CGFloat = .greatestFiniteMagnitude, minY: CGFloat = .greatestFiniteMagnitude
        var maxX: CGFloat = -.greatestFiniteMagnitude, maxY: CGFloat = -.greatestFiniteMagnitude
        for p in pts {
            minX = min(minX, p.x); minY = min(minY, p.y); maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        let a: CGRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).intersection(r)
        if a.isNull || a.width < 8 || a.height < 8 { return nil }
        return CGRect(x: (a.minX - r.minX) / r.width, y: (a.minY - r.minY) / r.height, width: a.width / r.width, height: a.height / r.height)
    }

    private func fit(_ video: CGSize, _ box: CGSize) -> CGRect {
        guard video.width > 0, video.height > 0, box.width > 0, box.height > 0 else { return CGRect(origin: .zero, size: box) }
        let s: CGFloat = min(box.width / video.width, box.height / video.height)
        let w: CGFloat = video.width * s
        let h: CGFloat = video.height * s
        return CGRect(x: (box.width - w) / 2, y: (box.height - h) / 2, width: w, height: h)
    }

    private func box(_ b: CGRect, _ rect: CGRect, color: Color, width: CGFloat) -> some View {
        let sx: CGFloat = rect.width / max(model.frameSize.width, 1)
        let sy: CGFloat = rect.height / max(model.frameSize.height, 1)
        return Rectangle()
            .stroke(color, lineWidth: width)
            .frame(width: b.width * sx, height: b.height * sy)
            .position(x: rect.minX + b.midX * sx, y: rect.minY + b.midY * sy)
    }
}

private struct RaceVideoProgress: View {
    @Bindable var model: RaceVideoModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.running || model.analysed {
                ProgressView(value: model.progress).tint(Avo.red)
            }
            if !model.status.isEmpty {
                Text(model.status).font(.footnote).foregroundStyle(Avo.text).fixedSize(horizontal: false, vertical: true)
            }
            if !model.trackStatus.isEmpty {
                Text(model.trackStatus).font(.footnote).foregroundStyle(Avo.cyan).fixedSize(horizontal: false, vertical: true)
            }
            Text("Rodea a tu caballo con el Pencil o el dedo (el vídeo se pausa) y pulsa «Continuar». Si lo pierde en un cambio de cámara, el vídeo se pausa solo para que lo vuelvas a marcar; con «No se ve» sigue sin él hasta el siguiente cambio.")
                .font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// ---------------------------------------------------------------- official data

private struct RaceVideoDataCard: View {
    @Environment(AppModel.self) private var app
    @Bindable var model: RaceVideoModel

    var body: some View {
        AvoCard(title: "Datos oficiales", subtitle: "Leídos de France Galop; corrígelos si hace falta") {
            VStack(alignment: .leading, spacing: 8) {
                field("Carrera") { TextField("Nombre de la carrera", text: $model.raceName) }
                field("Distancia (m)") { TextField("1400", text: $model.distanceText).keyboardType(.numberPad) }
                field("Tiempo del ganador") { TextField("p. ej. 2'25\"30", text: $model.winnerTimeText) }
                field("Caballo (Cuadra)") {
                    Picker("", selection: $model.horseCode) {
                        Text("Sin elegir").tag("")
                        ForEach(app.races.horses, id: \.code) { (h: IdentityRecord) in Text(h.name).tag(h.code) }
                    }
                    .pickerStyle(.menu)
                }
                field("En la carrera") { runnerField }
                if (model.ourPlace ?? 1) != 1 {
                    field("Cuerpos tras el 1.º") { TextField("p. ej. 2,5", text: $model.lengthsText).keyboardType(.decimalPad) }
                }
                HStack {
                    Text("Tiempo de tu caballo").font(.caption).foregroundStyle(Avo.textDim)
                    Spacer()
                    Text(RaceFormat.official(model.ourTimeS)).font(.callout.weight(.semibold).monospacedDigit()).foregroundStyle(Avo.text)
                }
                if model.needsLengths {
                    Text("Falta la distancia al ganador (cuerpos): sin ella se usa el tiempo del ganador.")
                        .font(.caption).foregroundStyle(Avo.warn).fixedSize(horizontal: false, vertical: true)
                }
                colors
            }
        }
    }

    @ViewBuilder
    private var runnerField: some View {
        if model.runners.isEmpty {
            TextField("Nombre del caballo en la carrera", text: $model.runnerName)
        } else {
            Picker("", selection: $model.runnerName) {
                Text("Elige…").tag("")
                ForEach(model.runners) { (r: RaceVideoRunner) in
                    Text((r.place.map { "\($0).º " } ?? "") + r.name + (r.number.map { " · N.º \($0)" } ?? "")).tag(r.name)
                }
            }
            .pickerStyle(.menu)
        }
    }

    @ViewBuilder
    private var colors: some View {
        let hex: [String] = model.ourColors
        if !hex.isEmpty {
            HStack(spacing: 6) {
                Text("Colores del jinete").font(.caption).foregroundStyle(Avo.textDim)
                ForEach(hex, id: \.self) { (h: String) in
                    RoundedRectangle(cornerRadius: 3).fill(RaceVideoDataCard.color(h)).frame(width: 18, height: 18)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Avo.line, lineWidth: 1))
                }
            }
        } else if !model.runnerName.isEmpty {
            Text("Sin colores del jinete: toca a tu jinete en el vídeo para que lo siga.")
                .font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
        }
    }

    static func color(_ hex: String) -> Color {
        var x: String = hex
        if x.hasPrefix("#") { x.removeFirst() }
        let v: UInt32 = UInt32(x, radix: 16) ?? 0
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.caption).foregroundStyle(Avo.textDim).frame(width: 130, alignment: .leading)
            content()
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// ---------------------------------------------------------------- result

private struct RaceVideoResultCard: View {
    @Bindable var model: RaceVideoModel
    let result: RaceVideoResult

    var body: some View {
        AvoCard(title: "Resultado estimado", subtitle: "Confianza \(result.confidenceText) · medido el \(pct(result.coverage)) de la carrera") {
            VStack(alignment: .leading, spacing: 10) {
                tiles
                startSlider
                if !result.points.isEmpty { RaceVideoSpeedChart(points: result.points) }
                sectorsTable
                ForEach(result.warnings, id: \.self) { (w: String) in
                    Text("• " + w).font(.caption).foregroundStyle(Avo.warn).fixedSize(horizontal: false, vertical: true)
                }
                Button { model.save() } label: {
                    Label("Guardar en Carreras y comparar con entrenamientos", systemImage: "flag.checkered")
                }
                .buttonStyle(.avoPrimary)
                .disabled(!model.canSave)
                .accessibilityIdentifier("raceVideo.save")
                Text("Se guarda como carrera «VÍDEO» (valores estimados) y se abre su ficha con la comparación con los entrenamientos.")
                    .font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func pct(_ v: Double) -> String { AvoFormat.f(v * 100, 0) + " %" }

    private var tiles: some View {
        let full: [RaceSector] = result.sectors.filter { abs($0.lengthM - 200) < 1 }
        let best: Double? = full.map { $0.sectorS }.min()
        let last: RaceSector? = result.sectors.last
        let hz: String = result.strideHz.map { AvoFormat.f($0, 2) + " Hz" } ?? "—"
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            tile("Vel. máxima", RaceFormat.kmh(result.maxKmh))
            tile("Mejor 200 m", RaceFormat.seconds(best))
            tile("Últimos 200 m", RaceFormat.seconds(last?.sectorS))
            tile("Zancada", hz)
            tile("Long. zancada", strideLength)
            tile("Escala", AvoFormat.f(result.scaleM, 2) + " m")
        }
    }

    private var strideLength: String {
        guard let hz = result.strideHz, hz > 0, result.timeS > 0 else { return "—" }
        let v: Double = result.distanceM / result.timeS
        return AvoFormat.f(v / hz, 2) + " m"
    }

    private func tile(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(Avo.textDim)
            Text(v).font(.callout.weight(.semibold).monospacedDigit()).foregroundStyle(Avo.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Avo.surface2, in: RoundedRectangle(cornerRadius: 6))
    }

    private var startSlider: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Salida en el vídeo").font(.caption).foregroundStyle(Avo.textDim)
                Spacer()
                Text(TimeText.clock(model.startT)).font(.caption.monospacedDigit()).foregroundStyle(Avo.text)
            }
            Slider(value: $model.startT, in: 0...max(model.duration, 1), step: 0.1)
            Text("Detectada automáticamente cuando el caballo arranca; muévela si el vídeo empieza con la salida ya dada.")
                .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sectorsTable: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("PARCIAL").frame(maxWidth: .infinity, alignment: .leading)
                Text("TIEMPO").frame(width: 58, alignment: .trailing)
                Text("KM/H").frame(width: 50, alignment: .trailing)
                Text("ZANC.").frame(width: 44, alignment: .trailing)
                Text("POS.").frame(width: 36, alignment: .trailing)
            }
            .font(.caption2.weight(.semibold)).foregroundStyle(Avo.textDim)
            ForEach(result.sectors) { (s: RaceSector) in
                HStack(spacing: 6) {
                    Text(s.shortLabel).frame(maxWidth: .infinity, alignment: .leading)
                    Text(AvoFormat.f(s.sectorS, 2)).frame(width: 58, alignment: .trailing)
                    Text(s.meanSpeedKmh.map { AvoFormat.f($0, 1) } ?? "—").frame(width: 50, alignment: .trailing)
                    Text(s.strides.map { String($0) } ?? "—").frame(width: 44, alignment: .trailing)
                    Text(s.position.map { "\($0).º" } ?? "—").frame(width: 36, alignment: .trailing)
                }
                .font(.caption.monospacedDigit()).foregroundStyle(Avo.text)
            }
        }
    }
}

private struct RaceVideoSpeedChart: View {
    let points: [RaceVideoResult.Point]

    var body: some View {
        Chart {
            ForEach(points) { (p: RaceVideoResult.Point) in
                LineMark(x: .value("Distancia", p.m), y: .value("km/h", p.kmh))
                    .foregroundStyle(Avo.red)
                    .interpolationMethod(.monotone)
            }
            ForEach(points.filter { !$0.measured }) { (p: RaceVideoResult.Point) in
                PointMark(x: .value("Distancia", p.m), y: .value("km/h", p.kmh))
                    .foregroundStyle(Avo.textDim.opacity(0.5))
                    .symbolSize(6)
            }
        }
        .chartXAxisLabel("m desde la salida")
        .chartYAxisLabel("km/h")
        .frame(height: 170)
    }
}
