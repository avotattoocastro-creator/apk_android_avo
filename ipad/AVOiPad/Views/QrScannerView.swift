import SwiftUI
import AVFoundation

/// Escáner de códigos QR con la cámara del iPad (AVFoundation). Se usa para entrar con la tarjeta AVO: el Android
/// muestra el QR del enlace `avohorse://identity/user/…` en Compartir › Mi cuenta › «Entrar en el iPad».
struct QrScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> QrScannerController {
        let c = QrScannerController()
        c.onCode = onCode
        c.onError = onError
        return c
    }

    func updateUIViewController(_ uiViewController: QrScannerController, context: Context) {}
}

final class QrScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    var onError: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var done: Bool = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
                DispatchQueue.main.async { ok ? self?.configure() : self?.onError?("Sin permiso para usar la cámara (Ajustes › AVO)") }
            }
        default: onError?("Sin permiso para usar la cámara (Ajustes › AVO)")
        }
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            onError?("No hay cámara disponible")
            return
        }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { onError?("La cámara no puede leer códigos QR"); return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        let p = AVCaptureVideoPreviewLayer(session: session)
        p.videoGravity = .resizeAspectFill
        p.frame = view.bounds
        view.layer.addSublayer(p)
        preview = p
        let s = session
        DispatchQueue.global(qos: .userInitiated).async { s.startRunning() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
        if let c = preview?.connection, c.isVideoRotationAngleSupported(0) {
            let angle: CGFloat
            switch view.window?.windowScene?.interfaceOrientation {
            case .landscapeLeft: angle = 180
            case .landscapeRight: angle = 0
            case .portraitUpsideDown: angle = 270
            default: angle = 90
            }
            if c.isVideoRotationAngleSupported(angle) { c.videoRotationAngle = angle }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let s = session
        DispatchQueue.global(qos: .userInitiated).async { if s.isRunning { s.stopRunning() } }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !done, let m = metadataObjects.first as? AVMetadataMachineReadableCodeObject, let text = m.stringValue else { return }
        done = true
        onCode?(text)
    }
}
