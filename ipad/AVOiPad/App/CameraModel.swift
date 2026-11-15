import SwiftUI
import AVFoundation
import Observation
import UIKit

/// Formato de grabación ofrecido por la cámara trasera.
struct CameraFormat: Hashable, Identifiable {
    var width: Int
    var height: Int
    var fps: Int
    var id: String { "\(width)x\(height)@\(fps)" }
    var title: String { "\(height >= 2160 ? "4K" : "\(height)p") · \(fps) fps" }
}

/// Vídeo grabado en «Cámara» con su archivo auxiliar `.avosync.json`.
struct CameraClip: Identifiable, Equatable {
    var videoURL: URL
    var syncURL: URL
    var sync: AvoSyncVideoFile?
    var id: String { videoURL.path }
    var name: String { videoURL.deletingPathExtension().lastPathComponent }
}

// MARK: - Captura (AVFoundation, colas propias)

/// Sesión de captura y escritura del vídeo. Cada fotograma conserva su sello del reloj del iPad (`host_ns`), que es lo
/// que después se convierte en hora GPS con la recta de AVO SYNC.
final class CameraRecorder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "org.avoperformance.horse.camera.session")
    private let videoQueue = DispatchQueue(label: "org.avoperformance.horse.camera.video", qos: .userInteractive)
    private let output = AVCaptureVideoDataOutput()
    private var device: AVCaptureDevice?
    private var configured = false

    struct Result {
        var url: URL
        var width: Int
        var height: Int
        var frames: Int
        var firstHostNs: Int64
        var lastHostNs: Int64
        var error: String?
    }

    // estado de la grabación (solo en videoQueue)
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var pendingURL: URL?
    private var pendingTransform: CGAffineTransform = .identity
    private var firstHostNs: Int64 = 0
    private var lastHostNs: Int64 = 0
    private var frames: Int = 0
    private var dims: (Int, Int) = (0, 0)
    private var finishing: ((Result) -> Void)?

    /// Aviso (en la cola principal) cuando llega el primer fotograma de la grabación.
    var onRecordingStarted: ((Int64) -> Void)?

    static var hasCamera: Bool { backCamera() != nil }

    private static func backCamera() -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    /// Formatos 1080p y 4K a 30/60/120/240 fps que admite la cámara trasera.
    static func availableFormats() -> [CameraFormat] {
        guard let d = backCamera() else { return [] }
        var out: [CameraFormat] = []
        for (w, h) in [(1920, 1080), (3840, 2160)] {
            for fps in [30, 60, 120, 240] {
                let ok = d.formats.contains { f in
                    let dim = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
                    return Int(dim.width) == w && Int(dim.height) == h
                        && f.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= Double(fps) - 0.01 }
                }
                if ok { out.append(CameraFormat(width: w, height: h, fps: fps)) }
            }
        }
        return out
    }

    func configure(_ fmt: CameraFormat, completion: @escaping (String?) -> Void) {
        sessionQueue.async {
            let err = self.applyConfiguration(fmt)
            DispatchQueue.main.async { completion(err) }
        }
    }

    private func applyConfiguration(_ fmt: CameraFormat) -> String? {
        guard let d = CameraRecorder.backCamera() else { return "Este dispositivo no tiene cámara trasera." }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if !configured {
            session.sessionPreset = .inputPriority
            guard let input = try? AVCaptureDeviceInput(device: d), session.canAddInput(input) else {
                return "No se puede abrir la cámara."
            }
            session.addInput(input)
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: videoQueue)
            guard session.canAddOutput(output) else { return "No se puede preparar la salida de vídeo." }
            session.addOutput(output)
            device = d
            configured = true
        }
        let candidates = d.formats.filter { f in
            let dim = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            return Int(dim.width) == fmt.width && Int(dim.height) == fmt.height
                && f.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= Double(fmt.fps) - 0.01 }
        }
        // preferir 4:2:0 de rango de vídeo (420v), el que pide la salida
        let best = candidates.first {
            CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        } ?? candidates.first
        guard let f = best else { return "La cámara no admite \(fmt.title)." }
        do {
            try d.lockForConfiguration()
            d.activeFormat = f
            let dur = CMTime(value: 1, timescale: CMTimeScale(fmt.fps))
            d.activeVideoMinFrameDuration = dur
            d.activeVideoMaxFrameDuration = dur
            d.unlockForConfiguration()
        } catch {
            return "No se puede configurar la cámara: \(error.localizedDescription)"
        }
        return nil
    }

    func startRunning() {
        sessionQueue.async { if self.configured && !self.session.isRunning { self.session.startRunning() } }
    }

    func stopRunning() {
        sessionQueue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    /// Empieza a grabar en el siguiente fotograma. `rotation` en grados (0, 90, 180, 270), como `videoRotationAngle`.
    func startRecording(to url: URL, rotation: CGFloat) {
        videoQueue.async {
            self.pendingURL = url
            self.pendingTransform = CGAffineTransform(rotationAngle: rotation * .pi / 180)
            self.writer = nil
            self.writerInput = nil
            self.frames = 0
        }
    }

    func stopRecording(_ completion: @escaping (Result) -> Void) {
        videoQueue.async {
            self.pendingURL = nil
            guard let w = self.writer, let input = self.writerInput else {
                let r = Result(url: URL(fileURLWithPath: "/"), width: 0, height: 0, frames: 0, firstHostNs: 0, lastHostNs: 0,
                               error: "No llegó ningún fotograma de la cámara.")
                DispatchQueue.main.async { completion(r) }
                return
            }
            self.writer = nil
            self.writerInput = nil
            let r0 = Result(url: w.outputURL, width: self.dims.0, height: self.dims.1, frames: self.frames,
                            firstHostNs: self.firstHostNs, lastHostNs: self.lastHostNs, error: nil)
            input.markAsFinished()
            w.finishWriting {
                var r = r0
                if w.status != .completed { r.error = w.error?.localizedDescription ?? "No se pudo cerrar el vídeo." }
                DispatchQueue.main.async { completion(r) }
            }
        }
    }

    /// Sello del fotograma en el reloj del iPad (ns), pasando del reloj de la sesión al reloj del host.
    private func hostNs(_ pts: CMTime) -> Int64 {
        let host = CMClockGetHostTimeClock()
        var t = pts
        if let sync = session.synchronizationClock, sync !== host {
            t = CMSyncConvertTime(pts, from: sync, to: host)
        }
        return CMTimeConvertScale(t, timescale: 1_000_000_000, method: .roundHalfAwayFromZero).value
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if writer == nil, let url = pendingURL {
            guard let fd = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
            let dim = CMVideoFormatDescriptionGetDimensions(fd)
            dims = (Int(dim.width), Int(dim.height))
            try? FileManager.default.removeItem(at: url)
            guard let w = try? AVAssetWriter(outputURL: url, fileType: .mov) else { pendingURL = nil; return }
            let settings: [String: Any] = self.output.recommendedVideoSettings(forVideoCodecType: .hevc, assetWriterOutputFileType: .mov)
                ?? [AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: dims.0, AVVideoHeightKey: dims.1]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            input.transform = pendingTransform
            guard w.canAdd(input) else { pendingURL = nil; return }
            w.add(input)
            guard w.startWriting() else { pendingURL = nil; return }
            w.startSession(atSourceTime: pts)
            writer = w
            writerInput = input
            frames = 0
            firstHostNs = hostNs(pts)
            let first = firstHostNs
            DispatchQueue.main.async { self.onRecordingStarted?(first) }
        }
        guard let w = writer, let input = writerInput, w.status == .writing else { return }
        if input.isReadyForMoreMediaData && input.append(sampleBuffer) {
            frames += 1
            lastHostNs = hostNs(pts)
        }
    }
}

// MARK: - Modelo de la página «Cámara»

/// Página «Cámara» (boceto del entrenador 14/11/2026, debajo de «Análisis»): graba vídeo del entrenamiento con la hora GPS
/// del gadget AVO SYNC, o con el reloj del iPad si no hay gadget, y guarda `.mov` + `.avosync.json` en `videos/`.
@Observable
final class CameraModel {
    unowned let app: AppModel

    enum Access { case unknown, granted, denied, noCamera }

    var access: Access = .unknown
    var formats: [CameraFormat] = []
    var format: CameraFormat? = nil
    var running = false
    var recording = false
    var recordStartHostNs: Int64? = nil
    var rotation: CGFloat = 0
    var error: String? = nil
    var clips: [CameraClip] = []
    var playing: CameraClip? = nil

    // AVO SYNC
    var syncState: AvoSyncLink.State = .off
    var syncFlags: AvoSyncProtocol.Flags = []
    var syncSatellites: Int = 0
    var syncStatus: AvoSyncProtocol.Status? = nil
    var lastMark: String? = nil
    /// Recta para la pantalla (últimos 5 min).
    var live = AvoSyncEstimator()
    /// Todas las muestras desde la conexión, para el archivo del vídeo (hasta 2 h de ventanas).
    var full: AvoSyncEstimator = {
        var e = AvoSyncEstimator()
        e.maxWindows = 720
        return e
    }()

    @ObservationIgnored let recorder = CameraRecorder()
    @ObservationIgnored private var link: AvoSyncLink? = nil
    @ObservationIgnored private var recMarks: [AvoSyncVideoFile.MarkEntry] = []
    @ObservationIgnored private var recHoldover = false
    @ObservationIgnored private var recSystemStart = AvoSyncVideoFile.ClockPair(hostNs: 0, unixNs: 0)
    @ObservationIgnored private var recURL: URL? = nil
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(app: AppModel) {
        self.app = app
    }

    var videosDir: String { AvoFiles.join(app.paths.root, "videos") }

    /// Sin enlace ni búsqueda en curso: se muestra «Conectar AVO SYNC».
    var syncIdle: Bool {
        switch syncState {
        case .off, .unavailable: return true
        default: return false
        }
    }

    var syncConnected: Bool { if case .connected = syncState { return true } else { return false } }

    /// Hay hora GPS utilizable: gadget conectado, hora válida y al menos una muestra.
    var gpsTimeOK: Bool { syncConnected && syncFlags.contains(.timeValid) && live.hasEstimate }

    // ------------------------------------------------------------------ página
    func pageShown() {
        loadClips()
        if access != .noCamera { prepareCamera() }   // también tras volver de Ajustes con el permiso dado
        if observers.isEmpty { observeInterruptions() }
    }

    /// Al salir de la página se cierra la grabación (se guarda) y se apaga la cámara para ahorrar batería.
    func pageHidden() {
        if recording { stopRecording() }
        recorder.stopRunning()
        running = false
    }

    private func prepareCamera() {
        guard CameraRecorder.hasCamera else { access = .noCamera; return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            access = .granted
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async {
                    self.access = ok ? .granted : .denied
                    if ok && self.app.page == .camera { self.configureAndRun() }
                }
            }
        default:
            access = .denied
        }
    }

    private func configureAndRun() {
        if formats.isEmpty {
            formats = CameraRecorder.availableFormats()
            let saved = UserDefaults.standard.string(forKey: "camera.format")
            format = formats.first { $0.id == saved }
                ?? formats.first { $0.width == 1920 && $0.fps == 60 }
                ?? formats.first
        }
        guard let f = format else { error = "La cámara no ofrece 1080p ni 4K."; return }
        updateRotation()
        recorder.configure(f) { err in
            self.error = err
            if err == nil {
                self.recorder.startRunning()
                self.running = true
            }
        }
    }

    func select(_ f: CameraFormat) {
        guard !recording, f != format else { return }
        format = f
        UserDefaults.standard.set(f.id, forKey: "camera.format")
        recorder.configure(f) { err in self.error = err }
    }

    /// Ángulo de giro según la orientación de la pantalla (cámara trasera; 0 = horizontal con el botón a la derecha).
    func updateRotation() {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        switch scene?.interfaceOrientation {
        case .portrait: rotation = 90
        case .landscapeLeft: rotation = 180
        case .portraitUpsideDown: rotation = 270
        default: rotation = 0
        }
    }

    private func observeInterruptions() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: recorder.session, queue: .main) { [weak self] _ in
            guard let self = self, self.recording else { return }
            self.stopRecording()
            self.error = "La cámara se interrumpió (otra app o multitarea): el vídeo se ha guardado hasta ese momento."
        })
        observers.append(nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self, self.recording else { return }
            self.stopRecording()
        })
    }

    // ------------------------------------------------------------------ AVO SYNC
    func connectSync() {
        if link == nil {
            let l = AvoSyncLink()
            l.onState = { [weak self] s in
                guard let self = self else { return }
                if case .connected = s, !self.syncConnected { self.live.reset(); self.full.reset() }
                self.syncState = s
            }
            l.onSample = { [weak self] sample, flags, sats in
                guard let self = self else { return }
                self.syncFlags = flags
                self.syncSatellites = Int(sats)
                if flags.contains(.holdover) && self.recording { self.recHoldover = true }
                guard flags.contains(.timeValid) else { return }
                self.live.add(sample)
                self.full.add(sample)
            }
            l.onMark = { [weak self] m in self?.addMark(kind: m.kind, utcNs: m.utcNs) }
            l.onStatus = { [weak self] s in self?.syncStatus = s }
            link = l
        }
        link?.start()
    }

    func disconnectSync() {
        link?.stop()
        syncStatus = nil
        syncFlags = []
    }

    /// Hora UTC de ahora (ns) con la mejor fuente: AVO SYNC si hay hora GPS; si no, reloj del sistema.
    func nowUtcNs() -> Int64 {
        if gpsTimeOK, let f = live.fit { return f.utcNs(hostNs: AvoHostClock.nowNs()) }
        return AvoHostClock.unixNowNs()
    }

    /// Marca manual desde el iPad (la del botón del gadget llega por BLE con su propia hora).
    func markNow(_ kind: AvoSyncProtocol.MarkKind) {
        addMark(kind: kind.rawValue, utcNs: nowUtcNs())
    }

    private func addMark(kind: UInt16, utcNs: Int64) {
        let k = AvoSyncProtocol.MarkKind(rawValue: kind) ?? .series
        lastMark = "\(k.title) · \(AvoSyncText.clock(utcNs))"
        if recording { recMarks.append(.init(kind: k, utcNs: utcNs)) }
    }

    // ------------------------------------------------------------------ grabación
    func toggleRecording() {
        if recording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        guard running, !recording else { return }
        AvoFiles.ensureDir(videosDir)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Madrid")
        f.dateFormat = "yyyyMMdd_HHmmss"
        let url = URL(fileURLWithPath: AvoFiles.join(videosDir, "AVO_VIDEO_\(f.string(from: Date())).mov"))
        recURL = url
        recMarks = []
        recHoldover = syncFlags.contains(.holdover)
        recSystemStart = .init(hostNs: AvoHostClock.nowNs(), unixNs: AvoHostClock.unixNowNs())
        updateRotation()
        recorder.onRecordingStarted = { [weak self] first in self?.recordStartHostNs = first }
        recorder.startRecording(to: url, rotation: rotation)
        recording = true
        error = nil
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func stopRecording() {
        guard recording else { return }
        recording = false
        UIApplication.shared.isIdleTimerDisabled = false
        let marks = recMarks
        let holdover = recHoldover
        let sysStart = recSystemStart
        let fmt = format
        recorder.stopRecording { r in
            self.recordStartHostNs = nil
            if let e = r.error, r.frames == 0 {
                self.error = e
                if let u = self.recURL { try? FileManager.default.removeItem(at: u) }
                return
            }
            if let e = r.error { self.error = e }
            self.writeSyncFile(r, format: fmt, marks: marks, holdover: holdover, systemStart: sysStart)
            self.loadClips()
        }
    }

    private func writeSyncFile(_ r: CameraRecorder.Result, format: CameraFormat?, marks: [AvoSyncVideoFile.MarkEntry],
                               holdover: Bool, systemStart: AvoSyncVideoFile.ClockPair) {
        let sysEnd = AvoSyncVideoFile.ClockPair(hostNs: AvoHostClock.nowNs(), unixNs: AvoHostClock.unixNowNs())
        let useGps = gpsTimeOK && full.fit != nil
        let fit = useGps ? full.fit : nil
        // reloj del sistema: media de las dos lecturas (inicio y fin) para no depender de un ajuste de NTP a mitad
        let sysOffset = ((systemStart.unixNs - systemStart.hostNs) + (sysEnd.unixNs - sysEnd.hostNs)) / 2
        let firstUtc = fit?.utcNs(hostNs: r.firstHostNs) ?? (r.firstHostNs + sysOffset)
        let samples = useGps ? full.points.filter { $0.hostNs >= r.firstHostNs - 600_000_000_000 && $0.hostNs <= r.lastHostNs + 600_000_000_000 } : []
        let file = AvoSyncVideoFile(
            video: r.url.lastPathComponent, width: r.width, height: r.height,
            fpsNominal: Double(format?.fps ?? 0), codec: "hevc", frames: r.frames,
            firstFrameHostNs: r.firstHostNs, lastFrameHostNs: r.lastHostNs,
            source: useGps ? .avoSync : .ipadClock, firstFrameUtcNs: firstUtc,
            errorBoundMs: useGps ? full.errorBoundNs.map { Double($0) / 1e6 } : nil,
            minDelayMs: useGps ? full.minDelayNs.map { Double($0) / 1e6 } : nil,
            spreadMs: useGps ? full.spreadNs.map { Double($0) / 1e6 } : nil,
            holdover: holdover, fit: fit, samples: samples, marks: marks,
            systemClockStart: systemStart, systemClockEnd: sysEnd,
            gadgetName: useGps ? { if case .connected(let n) = syncState { return n } else { return nil } }() : nil,
            appVersion: "\(AppModel.appVersion) (\(AppModel.buildNumber))")
        let path = r.url.deletingPathExtension().path + ".avosync.json"
        do {
            try AvoFiles.writeAtomic(try AvoSyncVideoFile.encode(file), to: path)
        } catch {
            self.error = "El vídeo se guardó, pero no su archivo de hora (.avosync.json): \(error.localizedDescription)"
        }
    }

    // ------------------------------------------------------------------ vídeos guardados
    func loadClips() {
        let dir = URL(fileURLWithPath: videosDir)
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        clips = urls.filter { $0.pathExtension.lowercased() == "mov" }
            .map { v in
                let s = v.deletingPathExtension().appendingPathExtension("avosync.json")
                let sync = (try? Data(contentsOf: s)).flatMap { try? AvoSyncVideoFile.decode($0) }
                return CameraClip(videoURL: v, syncURL: s, sync: sync)
            }
            .sorted { $0.name > $1.name }
    }

    func delete(_ c: CameraClip) {
        try? FileManager.default.removeItem(at: c.videoURL)
        try? FileManager.default.removeItem(at: c.syncURL)
        if playing == c { playing = nil }
        loadClips()
    }
}
