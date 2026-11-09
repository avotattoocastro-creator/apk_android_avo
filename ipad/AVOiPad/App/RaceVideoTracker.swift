import Foundation
import CoreVideo
import CoreGraphics
import Vision

/// Colour signature of a jockey's silks: 12 hue bins for coloured pixels + black / grey / white.
struct SilkSignature: Equatable {
    static let bins: Int = 15
    var h: [Double] = Array(repeating: 0, count: SilkSignature.bins)

    var isEmpty: Bool { h.allSatisfy { $0 <= 0 } }

    static func bin(r: Double, g: Double, b: Double) -> Int {
        let mx: Double = max(r, max(g, b))
        let mn: Double = min(r, min(g, b))
        let v: Double = mx
        let s: Double = mx > 0 ? (mx - mn) / mx : 0
        if s < 0.28 || v < 0.18 {
            if v < 0.25 { return 12 }          // black
            if v > 0.78 { return 14 }          // white
            return 13                          // grey
        }
        var hue: Double
        let d: Double = mx - mn
        if mx == r { hue = (g - b) / d } else if mx == g { hue = 2 + (b - r) / d } else { hue = 4 + (r - g) / d }
        hue *= 60
        if hue < 0 { hue += 360 }
        return min(11, Int(hue / 30))
    }

    mutating func add(r: Double, g: Double, b: Double, weight: Double = 1) {
        h[SilkSignature.bin(r: r, g: g, b: b)] += weight
    }

    func normalized() -> SilkSignature {
        let s: Double = h.reduce(0, +)
        if s <= 0 { return self }
        var o = self
        o.h = h.map { $0 / s }
        return o
    }

    /// Histogram intersection (0…1).
    func similarity(_ o: SilkSignature) -> Double {
        let a: SilkSignature = normalized()
        let b: SilkSignature = o.normalized()
        var s: Double = 0
        for i in 0..<SilkSignature.bins { s += min(a.h[i], b.h[i]) }
        return s
    }

    /// From the colours read on the France Galop silk image («#RRGGBB», weight).
    static func from(colors: [(hex: String, w: Double)]) -> SilkSignature {
        var s = SilkSignature()
        for c in colors {
            var x: String = c.hex.trimmingCharacters(in: .whitespaces)
            if x.hasPrefix("#") { x.removeFirst() }
            guard x.count == 6, let v = UInt32(x, radix: 16) else { continue }
            s.add(r: Double((v >> 16) & 0xFF) / 255, g: Double((v >> 8) & 0xFF) / 255, b: Double(v & 0xFF) / 255, weight: c.w)
        }
        return s.normalized()
    }
}

/// Jockey box in a frame (pixels, top-left origin).
struct JockeyBox: Equatable {
    var rect: CGRect
    var score: Double = 0
}

/// What the tracker returns for one frame (sample for the analysis + boxes for the overlay).
struct RaceVideoFrameResult {
    var sample: RaceVideoSample
    var target: CGRect?
    var others: [CGRect]
    var frameSize: CGSize
    var status: String
}

/// Frame-by-frame work (Vision): scene cuts, camera movement, jockeys and our jockey. Runs on one serial queue.
final class RaceVideoTracker {
    /// Signature of our jockey: from the France Galop silks, then learned from the video once found.
    var silk: SilkSignature = SilkSignature()
    /// Point tapped by the trainer (normalised 0…1, top-left origin): choose / correct our jockey.
    var tap: CGPoint? = nil

    private var prev: CVPixelBuffer? = nil
    private var thumbPrev: [Double] = []
    private var camX: Double = 0
    private var camY: Double = 0
    private var frame: Int = 0
    private var tracker: VNTrackObjectRequest? = nil
    private var tracked: VNDetectedObjectObservation? = nil
    private var target: CGRect? = nil
    private var learned: Bool = false
    private var lastOthers: [CGRect] = []
    private let sequence = VNSequenceRequestHandler()

    func reset() {
        prev = nil
        thumbPrev = []
        camX = 0
        camY = 0
        frame = 0
        dropTarget()
        learned = false
        lastOthers = []
    }

    private func dropTarget() {
        tracker = nil
        tracked = nil
        target = nil
    }

    func process(_ pb: CVPixelBuffer, t: Double) -> RaceVideoFrameResult {
        frame += 1
        let w: Double = Double(CVPixelBufferGetWidth(pb))
        let hgt: Double = Double(CVPixelBufferGetHeight(pb))
        let size = CGSize(width: w, height: hgt)
        // 1) scene cut
        let thumb: [Double] = RaceVideoTracker.thumbnail(pb)
        var cut: Bool = false
        if !thumbPrev.isEmpty && thumb.count == thumbPrev.count {
            var d: Double = 0
            for i in 0..<thumb.count { d += abs(thumb[i] - thumbPrev[i]) }
            cut = d / Double(thumb.count) > 0.16
        }
        thumbPrev = thumb
        if cut { dropTarget() }
        // 2) camera movement
        if !cut, let p = prev {
            let req = VNTranslationalImageRegistrationRequest(targetedCVPixelBuffer: pb, options: [:])
            let handler = VNImageRequestHandler(cvPixelBuffer: p, options: [:])
            if (try? handler.perform([req])) != nil, let o = req.results?.first as? VNImageTranslationAlignmentObservation {
                let tr: CGAffineTransform = o.alignmentTransform
                camX += Double(tr.tx)
                camY -= Double(tr.ty)       // Vision: origin bottom-left
            }
        }
        prev = pb
        // 3) jockeys (every 3rd frame, or every frame while looking for ours)
        var others: [CGRect] = []
        var detected: Bool = false
        if target == nil || tap != nil || frame % 3 == 0 {
            others = RaceVideoTracker.detectJockeys(pb, size)
            lastOthers = others
            detected = true
        }
        // 4) our jockey: follow, re-anchor on the detection, acquire by tap or by colours
        var status: String = ""
        if target != nil, let tr = tracker, let obs = tracked {
            tr.inputObservation = obs
            if (try? sequence.perform([tr], on: pb)) != nil, let r = tr.results?.first as? VNDetectedObjectObservation, r.confidence > 0.25 {
                tracked = r
                target = RaceVideoTracker.toPixels(r.boundingBox, size)
            } else {
                dropTarget()
            }
        }
        if let tp = tap, detected {
            let p = CGPoint(x: tp.x * w, y: tp.y * hgt)
            let best: CGRect? = others.min { RaceVideoTracker.dist($0, p) < RaceVideoTracker.dist($1, p) }
            if let b = best, RaceVideoTracker.dist(b, p) < max(b.height * 1.5, hgt * 0.08) {
                startTracking(b, pb, size)
                silk = RaceVideoTracker.signature(pb, b)
                learned = true
                status = "Jinete elegido: lo sigo y aprendo sus colores."
            } else {
                status = "No hay ningún jinete donde has tocado; toca justo encima del jinete."
            }
            tap = nil
        } else if let tg = target, detected {
            // re-anchor the tracker on the matching detection (keeps the box the size of a jockey)
            if let m = others.max(by: { RaceVideoTracker.iou($0, tg) < RaceVideoTracker.iou($1, tg) }), RaceVideoTracker.iou(m, tg) > 0.3 {
                startTracking(m, pb, size)
            }
        } else if target == nil && detected && !silk.isEmpty && !others.isEmpty {
            var scored: [(r: CGRect, s: Double)] = others.map { (r: $0, s: RaceVideoTracker.signature(pb, $0).similarity(silk)) }
            scored.sort { $0.s > $1.s }
            let second: Double = scored.count > 1 ? scored[1].s : 0
            let need: Double = learned ? 0.5 : 0.42
            if let b = scored.first, b.s >= need, b.s - second >= 0.06 || scored.count == 1 {
                startTracking(b.r, pb, size)
                if !learned {
                    // learn the real colours on the video (light, camera) from the first sure match
                    silk = RaceVideoTracker.signature(pb, b.r)
                    learned = true
                }
                status = "Jinete encontrado por los colores (\(Int(b.s * 100)) %)."
            }
        }
        if target == nil && status.isEmpty {
            status = silk.isEmpty ? "Toca a tu jinete en el vídeo para seguirlo." : "Buscando a tu jinete por los colores…"
        }
        let tg: CGRect? = target
        let otherCenters: [Double] = detected ? others.filter { o in tg.map { RaceVideoTracker.iou(o, $0) < 0.3 } ?? true }.map { Double($0.midX) } : []
        let sample = RaceVideoSample(t: t, cut: cut, camX: camX, camY: camY,
                                     x: tg.map { Double($0.midX) }, y: tg.map { Double($0.midY) }, h: tg.map { Double($0.height) },
                                     others: otherCenters, frameW: w)
        return RaceVideoFrameResult(sample: sample, target: tg, others: detected ? others : lastOthers, frameSize: size, status: status)
    }

    private func startTracking(_ r: CGRect, _ pb: CVPixelBuffer, _ size: CGSize) {
        let obs = VNDetectedObjectObservation(boundingBox: RaceVideoTracker.toVision(r, size))
        let req = VNTrackObjectRequest(detectedObjectObservation: obs)
        req.trackingLevel = .accurate
        tracker = req
        tracked = obs
        target = r
    }

    // ------------------------------------------------------------------ Vision helpers
    static func detectJockeys(_ pb: CVPixelBuffer, _ size: CGSize) -> [CGRect] {
        let req = VNDetectHumanRectanglesRequest()
        req.upperBodyOnly = false
        let handler = VNImageRequestHandler(cvPixelBuffer: pb, options: [:])
        guard (try? handler.perform([req])) != nil, let res = req.results else { return [] }
        var out: [CGRect] = []
        for case let o as VNDetectedObjectObservation in res {
            let r: CGRect = toPixels(o.boundingBox, size)
            let hr: Double = Double(r.height / size.height)
            if hr >= 0.035 && hr <= 0.6 { out.append(r) }
        }
        return out
    }

    static func toPixels(_ b: CGRect, _ s: CGSize) -> CGRect {
        CGRect(x: b.minX * s.width, y: (1 - b.maxY) * s.height, width: b.width * s.width, height: b.height * s.height)
    }

    static func toVision(_ r: CGRect, _ s: CGSize) -> CGRect {
        let x: CGFloat = max(0, min(1, r.minX / s.width))
        let y: CGFloat = max(0, min(1, 1 - r.maxY / s.height))
        let w: CGFloat = max(0.001, min(1 - x, r.width / s.width))
        let h: CGFloat = max(0.001, min(1 - y, r.height / s.height))
        return CGRect(x: x, y: y, width: w, height: h)
    }

    static func iou(_ a: CGRect, _ b: CGRect) -> Double {
        let i: CGRect = a.intersection(b)
        if i.isNull || i.isEmpty { return 0 }
        let ai: Double = Double(i.width * i.height)
        let u: Double = Double(a.width * a.height + b.width * b.height) - ai
        return u > 0 ? ai / u : 0
    }

    static func dist(_ r: CGRect, _ p: CGPoint) -> Double {
        let dx: Double = Double(r.midX - p.x)
        let dy: Double = Double(r.midY - p.y)
        return (dx * dx + dy * dy).squareRoot()
    }

    // ------------------------------------------------------------------ pixels (BGRA)
    /// Colours of the silks: upper half of the box (jacket and cap), central 60 %.
    static func signature(_ pb: CVPixelBuffer, _ r: CGRect) -> SilkSignature {
        var s = SilkSignature()
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return s }
        let bpr: Int = CVPixelBufferGetBytesPerRow(pb)
        let w: Int = CVPixelBufferGetWidth(pb)
        let h: Int = CVPixelBufferGetHeight(pb)
        let p = base.assumingMemoryBound(to: UInt8.self)
        let x0: Int = max(0, Int(r.minX + r.width * 0.2))
        let x1: Int = min(w - 1, Int(r.maxX - r.width * 0.2))
        let y0: Int = max(0, Int(r.minY))
        let y1: Int = min(h - 1, Int(r.minY + r.height * 0.55))
        if x1 <= x0 || y1 <= y0 { return s }
        let step: Int = max(1, min(x1 - x0, y1 - y0) / 14)
        var y: Int = y0
        while y <= y1 {
            var x: Int = x0
            while x <= x1 {
                let o: Int = y * bpr + x * 4
                s.add(r: Double(p[o + 2]) / 255, g: Double(p[o + 1]) / 255, b: Double(p[o]) / 255)
                x += step
            }
            y += step
        }
        return s.normalized()
    }

    /// 48×27 grid of the frame (R, G, B in 0…1) for the scene-cut test.
    static func thumbnail(_ pb: CVPixelBuffer) -> [Double] {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return [] }
        let bpr: Int = CVPixelBufferGetBytesPerRow(pb)
        let w: Int = CVPixelBufferGetWidth(pb)
        let h: Int = CVPixelBufferGetHeight(pb)
        let p = base.assumingMemoryBound(to: UInt8.self)
        var out: [Double] = []
        out.reserveCapacity(48 * 27 * 3)
        for gy in 0..<27 {
            let y: Int = min(h - 1, (gy * 2 + 1) * h / 54)
            for gx in 0..<48 {
                let x: Int = min(w - 1, (gx * 2 + 1) * w / 96)
                let o: Int = y * bpr + x * 4
                out.append(Double(p[o + 2]) / 255)
                out.append(Double(p[o + 1]) / 255)
                out.append(Double(p[o]) / 255)
            }
        }
        return out
    }
}
