import SwiftUI

/// Port of windows/AVO.Windows/Controls/HorseDiagram.cs: side view of a horse (X-ray style image owned by the user, asset
/// "horse_xray", transparent background) with the girth and the three girth IMUs (left, central, right) drawn on top.
/// Illustrative: not an anatomical measurement of the horse. Sensors without data are drawn hollow.
struct HorseDiagramView: View {
    /// imu_id values with data (0 central, 1 left, 2 right).
    var activeSensors: [Int]
    var highlight: Int = -1

    // Image and overlay coordinates are image pixels (1448 x 1086).
    private static let imgW: CGFloat = 1448
    private static let imgH: CGFloat = 1086

    /// Girth just behind the elbow, from the withers to the belly.
    private static let girth: [CGPoint] = [CGPoint(x: 592, y: 248), CGPoint(x: 636, y: 254), CGPoint(x: 626, y: 620), CGPoint(x: 580, y: 614)]

    private struct Sensor {
        let id: Int
        let pos: CGPoint
        let label: String
        let labelPos: CGPoint
    }

    private static let sensors: [Sensor] = [
        Sensor(id: 1, pos: CGPoint(x: 606, y: 450), label: "Izquierda", labelPos: CGPoint(x: 700, y: 700)),
        Sensor(id: 0, pos: CGPoint(x: 602, y: 600), label: "Central", labelPos: CGPoint(x: 170, y: 690)),
        Sensor(id: 2, pos: CGPoint(x: 612, y: 296), label: "Derecha (lado opuesto)", labelPos: CGPoint(x: 700, y: 120)),
    ]

    var body: some View {
        Canvas { (context: inout GraphicsContext, size: CGSize) in
            let s: CGFloat = min(size.width / HorseDiagramView.imgW, size.height / HorseDiagramView.imgH)
            if s <= 0 { return }
            let ox: CGFloat = (size.width - HorseDiagramView.imgW * s) / 2
            let oy: CGFloat = (size.height - HorseDiagramView.imgH * s) / 2
            func m(_ p: CGPoint) -> CGPoint { CGPoint(x: ox + p.x * s, y: oy + p.y * s) }

            // missing resource: the overlay is still drawn
            if UIImage(named: "horse_xray") != nil {
                let img = context.resolve(Image("horse_xray").interpolation(.high))
                context.draw(img, in: CGRect(x: ox, y: oy, width: HorseDiagramView.imgW * s, height: HorseDiagramView.imgH * s))
            }

            var girthPath = Path()
            girthPath.move(to: m(HorseDiagramView.girth[0]))
            for i in 1..<HorseDiagramView.girth.count { girthPath.addLine(to: m(HorseDiagramView.girth[i])) }
            girthPath.closeSubpath()
            context.fill(girthPath, with: .color(Color(red: 0xCC / 255.0, green: 0x1A / 255.0, blue: 0x2A / 255.0, opacity: 0x8C / 255.0)))
            context.stroke(girthPath, with: .color(Color(hex: 0xFF495A)), lineWidth: 1.2)

            // Labels are kept inside the drawn image (and the canvas): long texts such as
            // «Derecha (lado opuesto) · sin datos» are shifted left / down instead of being clipped at the card edge.
            let boundsMinX: CGFloat = max(ox, 0) + 2
            let boundsMaxX: CGFloat = min(ox + HorseDiagramView.imgW * s, size.width) - 2
            let boundsMinY: CGFloat = max(oy, 0) + 2
            let boundsMaxY: CGFloat = min(oy + HorseDiagramView.imgH * s, size.height) - 2
            let fontSize: CGFloat = max(10, min(13, 13 * s / 0.45))
            for sensor in HorseDiagramView.sensors {
                let c: Color = BiomechModel.sensorColor(sensor.id)
                let on: Bool = activeSensors.contains(sensor.id)
                let p: CGPoint = m(sensor.pos)
                let wanted: CGPoint = m(sensor.labelPos)
                let text = context.resolve(Text(sensor.label + (on ? "" : " · sin datos")).font(.system(size: fontSize)).foregroundColor(Avo.text))
                let maxTextW: CGFloat = max(boundsMaxX - boundsMinX - 10, 40)
                let ts: CGSize = text.measure(in: CGSize(width: maxTextW, height: 60))
                let boxW: CGFloat = ts.width + 10
                let boxH: CGFloat = ts.height + 6
                var bx: CGFloat = wanted.x - 5
                var by: CGFloat = wanted.y - 3
                if bx + boxW > boundsMaxX { bx = boundsMaxX - boxW }
                if bx < boundsMinX { bx = boundsMinX }
                if by + boxH > boundsMaxY { by = boundsMaxY - boxH }
                if by < boundsMinY { by = boundsMinY }
                let lp: CGPoint = CGPoint(x: bx + 5, y: by + 3)
                // leader line to the nearest horizontal end of the label box
                let anchorX: CGFloat = p.x <= bx ? bx : (p.x >= bx + boxW ? bx + boxW : bx + boxW / 2)
                let anchorY: CGFloat = p.y <= by ? by : (p.y >= by + boxH ? by + boxH : by + boxH / 2)
                var line = Path()
                line.move(to: p)
                line.addLine(to: CGPoint(x: anchorX, y: anchorY))
                context.stroke(line, with: .color(c.opacity(0xC0 / 255.0)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                let r: CGFloat = highlight == sensor.id ? 9 : 7
                let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
                context.fill(dot, with: .color(on ? c : Color(red: 0x10 / 255.0, green: 0x10 / 255.0, blue: 0x14 / 255.0, opacity: 0x99 / 255.0)))
                context.stroke(dot, with: .color(c), lineWidth: 2.4)
                if on {
                    let halo = Path(ellipseIn: CGRect(x: p.x - r - 4, y: p.y - r - 4, width: 2 * (r + 4), height: 2 * (r + 4)))
                    context.stroke(halo, with: .color(c.opacity(0x70 / 255.0)), lineWidth: 4)
                }
                let box = Path(roundedRect: CGRect(x: bx, y: by, width: boxW, height: boxH), cornerRadius: 4)
                context.fill(box, with: .color(Color(red: 0x10 / 255.0, green: 0x10 / 255.0, blue: 0x14 / 255.0, opacity: 0xD8 / 255.0)))
                context.stroke(box, with: .color(c), lineWidth: 1)
                context.draw(text, in: CGRect(x: lp.x, y: lp.y, width: ts.width, height: ts.height))
            }
            let note = context.resolve(Text("Imagen ilustrativa · cincha con 3 IMU").font(.system(size: 10)).foregroundColor(Avo.unknown))
            context.draw(note, at: CGPoint(x: 4, y: 2), anchor: .topLeading)
        }
        .accessibilityElement()
        .accessibilityLabel("Cincha con 3 IMU · sensores con datos: \(activeSensors.map { ImuTimeline.sensorName(UInt8(clamping: $0)) }.joined(separator: ", "))")
    }
}
