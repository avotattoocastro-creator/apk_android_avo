import SwiftUI
import Charts

// Shared pieces of the Compare, Biomech, Tides and Reports pages (port of Controls/SignalChart.cs + AvoKeyValue +
// SessionHeader). Names are prefixed with "Feature" so they never collide with other UI files.

/// X axis format of a chart (Windows AxisFormat).
enum FeatureAxis {
    case clock, number, kilometres, hourOfDay

    func label(_ x: Double) -> String {
        if !x.isFinite { return "" }
        switch self {
        case .clock:
            return TimeText.clock(x)
        case .kilometres:
            return DotNetFormat.custom(x / 1000, "0.#", spanish: true) + " km"
        case .hourOfDay:
            let h: Int = Int((x / 3600).rounded(.down)) % 24
            let m: Int = Int(x.truncatingRemainder(dividingBy: 3600) / 60)
            return String(format: "%02d:%02d", max(h, 0), max(m, 0))
        case .number:
            return DotNetFormat.custom(x, "0.##", spanish: true)
        }
    }
}

/// One drawable point (already reduced with LTTB for drawing only).
struct FeaturePlotPoint: Identifiable {
    let id: Int
    let x: Double
    let y: Double
    /// Unique key of the continuous run (series id + run index): lines never cross a NaN or a signal loss.
    let run: String
}

/// Line series of a chart (Windows ChartSeries). The full arrays are reduced once, at creation, to `maxPoints`.
struct FeatureLineSeries: Identifiable {
    let id: String
    let name: String
    let color: Color
    let unit: String
    let format: String
    let width: Double
    let dashed: Bool
    let points: [FeaturePlotPoint]
    let xMin: Double
    let xMax: Double
    let yMin: Double
    let yMax: Double

    init(id: String? = nil, name: String, color: Color, x: [Double], y: [Double], breaks: [Bool]? = nil, unit: String = "",
         format: String = "0.0", width: Double = 1.3, dashed: Bool = false, maxPoints: Int = 900) {
        self.id = id ?? name
        self.name = name
        self.color = color
        self.unit = unit
        self.format = format
        self.width = width
        self.dashed = dashed
        let n: Int = min(x.count, y.count)
        let xs: [Double] = n == x.count ? x : Array(x.prefix(n))
        let ys: [Double] = n == y.count ? y : Array(y.prefix(n))
        let idx: [Int] = Downsampler.lttb(xs, ys, maxPoints)
        var pts: [FeaturePlotPoint] = []
        pts.reserveCapacity(idx.count)
        var run: Int = 0
        var prev: Int = -1
        var x0: Double = .infinity, x1: Double = -.infinity, y0: Double = .infinity, y1: Double = -.infinity
        let key: String = id ?? name
        for i in idx {
            if prev >= 0 {
                var broken: Bool = false
                var k: Int = prev + 1
                while k <= i {
                    if !ys[k].isFinite || !xs[k].isFinite { broken = true; break }
                    if let b = breaks, k < b.count, b[k] { broken = true; break }
                    k += 1
                }
                if broken { run += 1 }
            }
            pts.append(FeaturePlotPoint(id: pts.count, x: xs[i], y: ys[i], run: key + "#" + String(run)))
            x0 = min(x0, xs[i]); x1 = max(x1, xs[i]); y0 = min(y0, ys[i]); y1 = max(y1, ys[i])
            prev = i
        }
        self.points = pts
        self.xMin = x0
        self.xMax = x1
        self.yMin = y0
        self.yMax = y1
    }
}

/// Coloured vertical band (quality, gait, training interval).
struct FeatureBand: Identifiable {
    let id: Int
    let x0: Double
    let x1: Double
    let color: Color
}

/// Time-series chart with Swift Charts: NaN gaps, optional cursor, selection range, marker and bands. Tap = cursor.
struct FeatureLineChart: View {
    var series: [FeatureLineSeries]
    var axis: FeatureAxis = .clock
    var xMin: Double = .nan
    var xMax: Double = .nan
    var includeZero: Bool = false
    var cursorX: Double = .nan
    var rangeStart: Double = .nan
    var rangeEnd: Double = .nan
    var markerX: Double = .nan
    var bands: [FeatureBand] = []
    var bandOpacity: Double = 0.16
    var emptyText: String = "Sin datos"
    var onTapX: ((Double) -> Void)? = nil

    private var hasData: Bool {
        for s in series where !s.points.isEmpty { return true }
        return false
    }

    private var xDomain: ClosedRange<Double> {
        var lo: Double = xMin
        var hi: Double = xMax
        if !lo.isFinite || !hi.isFinite || hi <= lo {
            var a: Double = .infinity, b: Double = -.infinity
            for s in series where !s.points.isEmpty { a = min(a, s.xMin); b = max(b, s.xMax) }
            if !lo.isFinite { lo = a }
            if !hi.isFinite { hi = b }
        }
        if !lo.isFinite || !hi.isFinite { return 0...1 }
        if hi <= lo { hi = lo + 1 }
        return lo...hi
    }

    private var yDomain: ClosedRange<Double> {
        var a: Double = .infinity, b: Double = -.infinity
        for s in series where !s.points.isEmpty { a = min(a, s.yMin); b = max(b, s.yMax) }
        if !a.isFinite || !b.isFinite { return 0...1 }
        if includeZero { a = min(a, 0); b = max(b, 0) }
        if b - a < 1e-9 { a -= 1; b += 1 }
        let pad: Double = (b - a) * 0.06
        return (a - pad)...(b + pad)
    }

    var body: some View {
        if !hasData {
            AvoNoData(text: emptyText)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                chart
                if series.count > 1 { FeatureLegend(items: series.map { (name: $0.name, color: $0.color) }) }
            }
        }
    }

    private var chart: some View {
        let xd: ClosedRange<Double> = xDomain
        let yd: ClosedRange<Double> = yDomain
        let ax: FeatureAxis = axis
        return Chart {
            bandMarks(xd, yd)
            rangeMarks(xd, yd)
            ForEach(series) { (s: FeatureLineSeries) in
                ForEach(s.points) { (p: FeaturePlotPoint) in
                    LineMark(x: .value("x", p.x), y: .value("y", p.y), series: .value("serie", p.run))
                        .foregroundStyle(s.color)
                        .lineStyle(StrokeStyle(lineWidth: s.width, dash: s.dashed ? [5, 3] : []))
                        .interpolationMethod(.linear)
                }
            }
            ruleMarks()
        }
        .chartXScale(domain: xd)
        .chartYScale(domain: yd)
        .chartPlotStyle { plot in plot.clipped() }
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisGridLine().foregroundStyle(Avo.line)
                AxisValueLabel {
                    if let d = value.as(Double.self) { Text(ax.label(d)).font(.caption2).foregroundStyle(Avo.textDim) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                AxisGridLine().foregroundStyle(Avo.line)
                AxisValueLabel {
                    if let d = value.as(Double.self) { Text(DotNetFormat.custom(d, "0.##", spanish: true)).font(.caption2).foregroundStyle(Avo.textDim) }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .onTapGesture { (location: CGPoint) in
                        guard let tap = onTapX, let anchor = proxy.plotFrame else { return }
                        let frame: CGRect = geo[anchor]
                        if let v: Double = proxy.value(atX: location.x - frame.origin.x, as: Double.self) { tap(v) }
                    }
            }
        }
    }

    @ChartContentBuilder
    private func bandMarks(_ xd: ClosedRange<Double>, _ yd: ClosedRange<Double>) -> some ChartContent {
        ForEach(bands) { (b: FeatureBand) in
            RectangleMark(xStart: .value("x0", max(b.x0, xd.lowerBound)), xEnd: .value("x1", min(b.x1, xd.upperBound)),
                          yStart: .value("y0", yd.lowerBound), yEnd: .value("y1", yd.upperBound))
                .foregroundStyle(b.color.opacity(bandOpacity))
        }
    }

    @ChartContentBuilder
    private func rangeMarks(_ xd: ClosedRange<Double>, _ yd: ClosedRange<Double>) -> some ChartContent {
        if rangeStart.isFinite && rangeEnd.isFinite && rangeStart != rangeEnd {
            RectangleMark(xStart: .value("r0", max(min(rangeStart, rangeEnd), xd.lowerBound)),
                          xEnd: .value("r1", min(max(rangeStart, rangeEnd), xd.upperBound)),
                          yStart: .value("y0", yd.lowerBound), yEnd: .value("y1", yd.upperBound))
                .foregroundStyle(Avo.cyan.opacity(0.14))
        }
    }

    @ChartContentBuilder
    private func ruleMarks() -> some ChartContent {
        if markerX.isFinite {
            RuleMark(x: .value("marca", markerX)).foregroundStyle(Avo.red).lineStyle(StrokeStyle(lineWidth: 2))
        }
        if cursorX.isFinite {
            RuleMark(x: .value("cursor", cursorX)).foregroundStyle(Avo.text.opacity(0.8)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }
}

/// Colour legend under a chart.
struct FeatureLegend: View {
    var items: [(name: String, color: Color)]
    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<items.count, id: \.self) { (i: Int) in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(items[i].color).frame(width: 14, height: 4)
                    Text(items[i].name).font(.caption2).foregroundStyle(Avo.textDim).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Chart inside a card with header and optional readout (Windows AvoChartPanel).
struct FeatureChartPanel<Content: View>: View {
    var title: String
    var readout: String? = nil
    var minHeight: CGFloat = 190
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased()).font(.caption.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.silver).lineLimit(2)
                Spacer()
                if let r = readout, !r.isEmpty { Text(r).font(.caption.monospacedDigit()).foregroundStyle(Avo.cyan) }
            }
            content().frame(minHeight: minHeight)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Avo.cardBrush, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Avo.line, lineWidth: 1))
    }
}

/// Key / value row (Windows AvoKeyValue).
struct FeatureKeyValue: View {
    var key: String
    var value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(key).font(.footnote).foregroundStyle(Avo.textDim)
            Spacer(minLength: 8)
            Text(value).font(.footnote.weight(.medium)).foregroundStyle(Avo.text).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 3)
    }
}

/// Key / value pair stored by the models.
struct FeatureKV: Identifiable, Equatable {
    let id: Int
    let key: String
    let value: String
}

extension Array where Element == FeatureKV {
    mutating func add(_ key: String, _ value: String) { append(FeatureKV(id: count, key: key, value: value)) }
}

/// Active training header (Windows SessionHeader: title, subtitle, DEMO badge, engine state).
struct FeatureSessionHeader: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(Avo.red).frame(width: 4, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                if let s = app.selected {
                    Text("Entrenamiento \(s.dateTimeText)").font(.title3.weight(.semibold)).foregroundStyle(Avo.text)
                    Text("\(s.horse) · \(s.rider) · \(s.discipline)").font(.footnote).foregroundStyle(Avo.textDim)
                } else {
                    Text("Sin entrenamiento seleccionado").font(.title3.weight(.semibold)).foregroundStyle(Avo.text)
                    Text("Importa un archivo .avo o .avr").font(.footnote).foregroundStyle(Avo.textDim)
                }
            }
            if let s = app.selected, s.isSynthetic {
                AvoPill(text: "DEMOSTRACIÓN · DATOS SINTÉTICOS", color: Avo.warn)
            }
            Spacer(minLength: 8)
            if let s = app.selected {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(s.windowText).font(.caption.weight(.semibold)).foregroundStyle(Avo.text).lineLimit(1)
                    Text("Motor: \(s.engineState)").font(.caption2).foregroundStyle(Avo.textDim).lineLimit(1)
                }
            }
        }
        .padding(.bottom, 4)
    }
}

/// Simple table with fixed column widths that scrolls horizontally on narrow screens (Windows DataGrid).
struct FeatureTable: View {
    var headers: [String]
    var widths: [CGFloat]
    var rows: [[String]]
    var colors: [Color?] = []
    var highlighted: Set<Int> = []
    var emptyText: String = "Sin datos"

    var body: some View {
        if rows.isEmpty {
            AvoNoData(text: emptyText)
        } else {
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    row(headers, header: true, index: -1)
                    Divider().background(Avo.line)
                    ForEach(0..<rows.count, id: \.self) { (i: Int) in
                        row(rows[i], header: false, index: i)
                    }
                }
            }
        }
    }

    private func row(_ cells: [String], header: Bool, index: Int) -> some View {
        HStack(spacing: 0) {
            if !colors.isEmpty {
                Group {
                    if index >= 0, index < colors.count, let c = colors[index] {
                        RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 10, height: 10)
                    } else {
                        Color.clear.frame(width: 10, height: 10)
                    }
                }
                .frame(width: 18, alignment: .leading)
            }
            ForEach(0..<cells.count, id: \.self) { (k: Int) in
                Text(cells[k])
                    .font(header ? .caption2.weight(.semibold) : .caption)
                    .foregroundStyle(header ? Avo.textDim : Avo.text)
                    .lineLimit(2)
                    .frame(width: k < widths.count ? widths[k] : 90, alignment: .leading)
                    .padding(.trailing, 6)
            }
        }
        .padding(.vertical, 5)
        .background(index >= 0 && highlighted.contains(index) ? Avo.red.opacity(0.12) : Color.clear)
    }
}
