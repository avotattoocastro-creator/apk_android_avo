import UIKit
import MapKit

/// Satellite picture of a route for the reports (trainer's request 08/11/2026): Esri World Imagery tiles (the map's tile
/// cache first, then the network), turned exactly like ReportBuilder.routeLayout (route horizontal, start on the left),
/// with the route coloured by speed, start / end, the maximum speed and its value, a scale bar and the north arrow.
/// nil when no tile could be obtained (no connection and nothing cached): the report then draws the route on a plain
/// background as before.
enum RouteImageRenderer {
    static func render(_ tl: SessionTimeline, widthPt: Double, heightPt: Double, from: Int = 0, to: Int? = nil,
                       cacheDir: String, scale: Double = 2) async -> RouteImage? {
        guard let L = ReportBuilder.routeLayout(tl, widthPt, heightPt, from: from, to: to) else { return nil }
        let cosT: Double = cos(L.theta)
        let sinT: Double = sin(L.theta)
        // output point → Web Mercator pixel at zoom L.z (inverse of the layout transform)
        func toZ(_ ox: Double, _ oy: Double) -> (x: Double, y: Double) {
            let u: Double = ((ox - widthPt / 2) / L.k + L.cx) * L.flip
            let v: Double = ((oy - heightPt / 2) / L.k + L.cy) * L.flip
            return (x: L.mx + u * cosT - v * sinT, y: L.my + u * sinT + v * cosT)
        }
        let corners: [(x: Double, y: Double)] = [toZ(0, 0), toZ(widthPt, 0), toZ(0, heightPt), toZ(widthPt, heightPt)]
        var minX: Double = .infinity, maxX: Double = -.infinity, minY: Double = .infinity, maxY: Double = -.infinity
        for c in corners { minX = min(minX, c.x); maxX = max(maxX, c.x); minY = min(minY, c.y); maxY = max(maxY, c.y) }
        // tile zoom with about one tile pixel per output pixel, at most 19 and at most ~80 tiles
        var zt: Int = Int((L.z + log2(max(L.k * scale, 1e-6))).rounded(.up))
        zt = min(19, max(3, zt))
        var tiles: [(x: Int, y: Int)] = []
        while true {
            let f: Double = pow(2, L.z - Double(zt)) * 256
            let x0: Int = Int(floor(minX / f)), x1: Int = Int(floor(maxX / f))
            let y0: Int = Int(floor(minY / f)), y1: Int = Int(floor(maxY / f))
            if (x1 - x0 + 1) * (y1 - y0 + 1) <= 80 || zt <= 3 {
                tiles = []
                for ty in y0...y1 { for tx in x0...x1 { tiles.append((x: tx, y: ty)) } }
                break
            }
            zt -= 1
        }
        let overlay = RouteEsriTileOverlay(layer: "World_Imagery", cacheDir: cacheDir)
        let z: Int = zt
        var images: [String: UIImage] = [:]
        await withTaskGroup(of: (String, UIImage?).self) { (group: inout TaskGroup<(String, UIImage?)>) in
            for t in tiles {
                group.addTask {
                    let path = MKTileOverlayPath(x: t.x, y: t.y, z: z, contentScaleFactor: 1)
                    let data: Data? = await withCheckedContinuation { (c: CheckedContinuation<Data?, Never>) in
                        overlay.loadTile(at: path) { (d: Data?, _: Error?) in c.resume(returning: d) }
                    }
                    return ("\(t.x)/\(t.y)", data.flatMap { UIImage(data: $0) })
                }
            }
            for await (k, im) in group { if let im = im { images[k] = im } }
        }
        if images.isEmpty { return nil }

        let size = CGSize(width: widthPt, height: heightPt)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let picture: UIImage = UIGraphicsImageRenderer(size: size, format: format).image { (ctx: UIGraphicsImageRendererContext) in
            let g: CGContext = ctx.cgContext
            g.setFillColor(UIColor(white: 0.85, alpha: 1).cgColor)
            g.fill(CGRect(origin: .zero, size: size))
            // tiles, in Mercator pixels at zoom L.z through the layout transform
            g.saveGState()
            g.translateBy(x: widthPt / 2, y: heightPt / 2)
            g.scaleBy(x: L.k, y: L.k)
            g.translateBy(x: -L.cx, y: -L.cy)
            g.scaleBy(x: L.flip, y: L.flip)
            g.rotate(by: -L.theta)
            g.translateBy(x: -L.mx, y: -L.my)
            g.interpolationQuality = .high
            let f: Double = pow(2, L.z - Double(z)) * 256
            for t in tiles {
                guard let im = images["\(t.x)/\(t.y)"] else { continue }
                // ~1.5 output pixels of overlap hide the seams between rotated tiles
                let o: Double = 1.5 / (L.k * scale)
                im.draw(in: CGRect(x: Double(t.x) * f - o, y: Double(t.y) * f - o, width: f + 2 * o, height: f + 2 * o))
            }
            g.restoreGState()
            g.setFillColor(UIColor(white: 0, alpha: 0.12).cgColor)
            g.fill(CGRect(origin: .zero, size: size))

            // route coloured by speed
            let first: Int = from
            let vmax: Double = max(0.1, Stats.maxFinite(tl.speedFiltered, fallback: 0.1))
            g.setLineCap(.round)
            g.setLineWidth(3)
            var prev: (x: Double, y: Double)? = nil
            for (k, q) in L.pts.enumerated() {
                let i: Int = first + k
                guard let q = q else { prev = nil; continue }
                if let a = prev, !(tl.breakBefore[i] || tl.jumpBefore[i]) {
                    let c: AvoRGB = SpeedScale.color(tl.speedFiltered[i], vmax)
                    g.setStrokeColor(UIColor(red: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1).cgColor)
                    g.move(to: CGPoint(x: a.x, y: a.y))
                    g.addLine(to: CGPoint(x: q.x, y: q.y))
                    g.strokePath()
                }
                prev = q
            }
            let valid: [(x: Double, y: Double)] = L.pts.compactMap { (q: (x: Double, y: Double)?) -> (x: Double, y: Double)? in q }
            if let s0 = valid.first, let s1 = valid.last {
                dot(g, s0, UIColor(red: 0.32, green: 0.87, blue: 0.25, alpha: 1))
                dot(g, s1, UIColor(red: 0.93, green: 0.07, blue: 0.16, alpha: 1))
                pill("Inicio", at: inside(CGPoint(x: s0.x + 8, y: s0.y - 18), "Inicio", widthPt, heightPt))
                pill("Fin", at: inside(CGPoint(x: s1.x + 8, y: s1.y + 4), "Fin", widthPt, heightPt))
            }
            let vi: Int = ReportBuilder.vmaxIndex(tl, from: from, to: to)
            if vi >= first, vi - first < L.pts.count, let q = L.pts[vi - first] {
                dot(g, q, UIColor(red: 1, green: 0.54, blue: 0, alpha: 1), r: 6)
                let label: String = ReportBuilder.vmaxLabel(tl, vi)
                let w: Double = Double((label as NSString).size(withAttributes: pillAttrs).width) + 12
                let px: Double = min(max(q.x - w / 2, 4), widthPt - w - 4)
                pill(label, at: CGPoint(x: px, y: max(q.y - 30, 4)), orange: true)
            }
            // scale bar and north arrow
            let target: Double = L.metersPerPoint * 100
            let candidates: [Double] = [10, 20, 50, 100, 200, 500, 1000, 2000, 5000]
            var nice: Double = candidates[0]
            for v in candidates where abs(v - target) < abs(nice - target) { nice = v }
            let bar: Double = nice / L.metersPerPoint
            let scaleText: String = nice >= 1000 ? DotNetFormat.custom(nice / 1000, "0", spanish: true) + " km"
                                                 : DotNetFormat.custom(nice, "0", spanish: true) + " m"
            g.setFillColor(UIColor(white: 0, alpha: 0.55).cgColor)
            g.fill(CGRect(x: 8, y: heightPt - 30, width: bar + 12, height: 24))
            g.setFillColor(UIColor.white.cgColor)
            g.fill(CGRect(x: 14, y: heightPt - 12, width: bar, height: 3))
            (scaleText as NSString).draw(at: CGPoint(x: 14, y: heightPt - 28), withAttributes: pillAttrs)
            let ax: Double = widthPt - 24, ay: Double = 30
            g.setFillColor(UIColor(white: 0, alpha: 0.55).cgColor)
            g.fillEllipse(in: CGRect(x: ax - 18, y: ay - 18, width: 36, height: 36))
            g.setStrokeColor(UIColor.white.cgColor)
            g.setLineWidth(2)
            g.move(to: CGPoint(x: ax - L.north.x * 9, y: ay - L.north.y * 9))
            g.addLine(to: CGPoint(x: ax + L.north.x * 9, y: ay + L.north.y * 9))
            g.strokePath()
            ("N" as NSString).draw(at: CGPoint(x: ax + L.north.x * 12 - 4, y: ay + L.north.y * 12 - 7), withAttributes: pillAttrs)
            ("Imágenes © Esri, Maxar, Earthstar Geographics" as NSString).draw(
                at: CGPoint(x: widthPt - 190, y: heightPt - 12),
                withAttributes: [.font: UIFont.systemFont(ofSize: 6), .foregroundColor: UIColor(white: 1, alpha: 0.85)])
        }
        guard let jpeg = picture.jpegData(compressionQuality: 0.82) else { return nil }
        return RouteImage(jpeg: jpeg, width: Int(widthPt * scale), height: Int(heightPt * scale))
    }

    private static let pillAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 9), .foregroundColor: UIColor.white]

    /// Moves a label so it stays inside the picture (it goes to the left of the point near the right edge).
    private static func inside(_ p: CGPoint, _ text: String, _ w: Double, _ h: Double) -> CGPoint {
        let s: CGSize = (text as NSString).size(withAttributes: pillAttrs)
        let pw: Double = Double(s.width) + 12, ph: Double = Double(s.height) + 6
        var x: Double = Double(p.x)
        if x + pw > w - 4 { x = x - pw - 16 }
        return CGPoint(x: max(4, x), y: min(max(4, Double(p.y)), h - ph - 4))
    }

    private static func dot(_ g: CGContext, _ p: (x: Double, y: Double), _ color: UIColor, r: Double = 5) {
        g.setFillColor(UIColor.white.cgColor)
        g.fillEllipse(in: CGRect(x: p.x - r - 1.5, y: p.y - r - 1.5, width: 2 * r + 3, height: 2 * r + 3))
        g.setFillColor(color.cgColor)
        g.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
    }

    private static func pill(_ text: String, at p: CGPoint, orange: Bool = false) {
        let s: CGSize = (text as NSString).size(withAttributes: pillAttrs)
        let r = CGRect(x: p.x, y: p.y, width: s.width + 12, height: s.height + 6)
        let bg: UIColor = orange ? UIColor(red: 1, green: 0.54, blue: 0, alpha: 0.95) : UIColor(white: 0, alpha: 0.65)
        bg.setFill()
        UIBezierPath(roundedRect: r, cornerRadius: 5).fill()
        (text as NSString).draw(at: CGPoint(x: p.x + 6, y: p.y + 3), withAttributes: pillAttrs)
    }
}
