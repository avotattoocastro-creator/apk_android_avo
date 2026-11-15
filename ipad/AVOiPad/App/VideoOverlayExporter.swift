import Foundation
import AVFoundation
import CoreImage
import UIKit

/// Exporta un vídeo de «Cámara» con los indicadores del entrenamiento impresos en la imagen (mismo dibujo que el
/// reproductor, `VideoOverlayRenderer`). Respeta el recorte. El original no se toca: el resultado va a `videos/exportados/`.
final class VideoOverlayExporter {
    private var session: AVAssetExportSession?
    private var timer: DispatchSourceTimer?

    func run(videoURL: URL, sync: AvoSyncVideoFile, telemetry: VideoTelemetry?, gauges: Set<VideoGauge>, out: URL,
             progress: @escaping (Double) -> Void, done: @escaping (String?) -> Void) {
        let asset = AVURLAsset(url: videoURL)
        let timeSource: String = sync.source == .avoSync ? "HORA GPS · AVO SYNC" : "RELOJ DEL IPAD"
        let lock = NSLock()
        var cacheKey: Int = Int.min
        var cacheImage: CIImage? = nil

        let comp = AVMutableVideoComposition(asset: asset) { (request: AVAsynchronousCIImageFilteringRequest) in
            let src: CIImage = request.sourceImage
            let ext: CGRect = src.extent
            let t: Double = request.compositionTime.seconds
            // el dibujo cambia como mucho 30 veces por segundo: se reutiliza entre fotogramas (vídeos a 120/240 fps)
            let key: Int = Int((t * 30).rounded(.down))
            lock.lock()
            var overlay: CIImage? = key == cacheKey ? cacheImage : nil
            lock.unlock()
            if overlay == nil {
                let utcNs: Int64 = sync.utcNs(videoTimeS: t)
                let sample: VideoTelemetrySample = telemetry?.sample(utcS: Double(utcNs) / 1e9) ?? VideoTelemetrySample(inRange: false)
                let input = VideoOverlayRenderer.Input(telemetry: telemetry, sample: sample, gauges: gauges,
                                                       utcText: AvoSyncText.clock(utcNs), timeSource: timeSource)
                let fmt = UIGraphicsImageRendererFormat()
                fmt.scale = 1
                fmt.opaque = false
                let img: UIImage = UIGraphicsImageRenderer(size: ext.size, format: fmt).image { ctx in
                    VideoOverlayRenderer.draw(ctx.cgContext, size: ext.size, input)
                }
                overlay = img.cgImage.map { CIImage(cgImage: $0).transformed(by: CGAffineTransform(translationX: ext.minX, y: ext.minY)) }
                lock.lock()
                cacheKey = key
                cacheImage = overlay
                lock.unlock()
            }
            request.finish(with: overlay.map { $0.composited(over: src) } ?? src, context: nil)
        }
        // 240 fps no hace falta para ver los datos y la exportación tarda mucho menos a 60
        let fps: Int32 = Int32(min(60, max(24, Int(sync.fpsNominal.rounded()))))
        comp.frameDuration = CMTime(value: 1, timescale: fps)

        guard let ex = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHEVCHighestQuality)
                ?? AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            done("este iPad no puede exportar el vídeo.")
            return
        }
        try? FileManager.default.removeItem(at: out)
        ex.outputURL = out
        ex.outputFileType = .mov
        ex.videoComposition = comp
        let r = sync.trimmedRange
        ex.timeRange = CMTimeRange(start: CMTime(seconds: r.lowerBound, preferredTimescale: 600),
                                   end: CMTime(seconds: r.upperBound, preferredTimescale: 600))
        session = ex

        let tm = DispatchSource.makeTimerSource(queue: .main)
        tm.schedule(deadline: .now(), repeating: .milliseconds(250))
        tm.setEventHandler { progress(Double(ex.progress)) }
        timer = tm
        tm.resume()

        ex.exportAsynchronously {
            DispatchQueue.main.async {
                self.timer?.cancel()
                self.timer = nil
                switch ex.status {
                case .completed: done(nil)
                case .cancelled:
                    try? FileManager.default.removeItem(at: out)
                    done("cancelada.")
                default:
                    try? FileManager.default.removeItem(at: out)
                    done(ex.error?.localizedDescription ?? "error desconocido.")
                }
            }
        }
    }

    func cancel() { session?.cancelExport() }
}
