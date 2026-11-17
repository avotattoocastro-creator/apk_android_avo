import SwiftUI

// Components of the shell pages (Analysis, Engine, Server, Home) that other pages may reuse.

/// Windows Views/SessionHeader.xaml: active training, DEMO badge, useful-window trim controls and engine state.
struct ShellSessionHeader: View {
    @Environment(AppModel.self) private var app
    /// Analysis page: «caballo · jinete · modalidad» goes to the right of the title row, with the horse name prominent.
    var horseOnRight: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                RoundedRectangle(cornerRadius: 2).fill(Avo.red).frame(width: 4, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.sessionHeaderTitle).font(.title3.weight(.semibold)).foregroundStyle(Avo.text)
                    if !horseOnRight || app.selected == nil {
                        Text(app.sessionHeaderSubtitle).font(.subheadline).foregroundStyle(Avo.textDim)
                    }
                }
                if app.selected?.isSynthetic == true {
                    Text("DEMOSTRACIÓN · DATOS SINTÉTICOS").font(.caption2.weight(.semibold)).foregroundStyle(Avo.warn)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Avo.warn.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Avo.warn, lineWidth: 1))
                }
                Spacer(minLength: 0)
                if horseOnRight, let s = app.selected {
                    // tap on the horse name: «Historia del caballo» (AVO Training Analytics)
                    Button {
                        app.horseHistory.open(for: s)
                    } label: {
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 8) {
                                Image(systemName: "figure.equestrian.sports").font(.title3).foregroundStyle(Avo.red)
                                Text(s.horse).font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(Avo.text)
                                    .lineLimit(1).minimumScaleFactor(0.6)
                                Image(systemName: "chart.line.uptrend.xyaxis").font(.callout).foregroundStyle(Avo.textDim)
                            }
                            Text("\(s.rider) · \(s.discipline) · Historia de entrenamientos").font(.callout).foregroundStyle(Avo.silver).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Caballo \(s.horse), jinete \(s.rider), \(s.discipline). Abrir historia de entrenamientos")
                    .accessibilityIdentifier("analysis.horseHistory")
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "flag").font(.caption).foregroundStyle(Avo.cyan)
                        Text(app.windowText).font(.caption.weight(.semibold)).foregroundStyle(Avo.text).padding(.trailing, 6)
                        Button("Inicio = cursor") { app.windowStartAtCursor() }.disabled(!app.canMarkWindow)
                        Button("Fin = cursor") { app.windowEndAtCursor() }.disabled(!app.canMarkWindow)
                        Button("Usar selección") { app.windowFromRange() }.disabled(app.selected == nil || !app.hasRange)
                        Button("Archivo completo") { app.windowReset() }.disabled(!app.isTrimmed)
                    }
                    .buttonStyle(.bordered).controlSize(.small).font(.caption)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Avo.surface2, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Avo.line, lineWidth: 1))
                    if let s = app.selected {
                        Text("Motor: \(s.engineState)").font(.caption).foregroundStyle(Avo.textDim)
                    }
                    Button("Reprocesar con el motor") {
                        if let s = app.selected { Task { @MainActor in await app.runEngine(s, force: true) } }
                    }
                    .buttonStyle(.avoSecondary)
                    .disabled(app.selected == nil)
                }
            }
        }
        .padding(.bottom, 4)
    }
}

/// Key/value line (Windows AvoKeyValue).
struct ShellKeyValue: View {
    var key: String
    var value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key).font(.footnote).foregroundStyle(Avo.textDim)
            Spacer(minLength: 8)
            Text(value).font(.footnote.weight(.semibold)).foregroundStyle(Avo.text).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 3)
    }
}

/// Status line with a coloured dot (Windows AvoStatusIndicator).
struct ShellStatusIndicator: View {
    var text: String
    var detail: String
    var state: AvoState
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(state.color).frame(width: 9, height: 9)
            Text(text).font(.footnote).foregroundStyle(Avo.text)
            Spacer(minLength: 8)
            Text(detail).font(.caption).foregroundStyle(Avo.textDim).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4)
    }
}

/// Simple read-only table (Windows AvoDataTable): fixed-width or flexible columns, horizontal scroll when narrow.
struct ShellTable: View {
    struct Column {
        var title: String
        var width: CGFloat? = nil
    }
    var columns: [Column]
    var rows: [[String]]
    var empty: String = "Sin datos"

    var body: some View {
        if rows.isEmpty {
            AvoNoData(text: empty)
        } else {
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    row(columns.map { $0.title }, header: true)
                    Divider().background(Avo.line)
                    ForEach(0..<rows.count, id: \.self) { (i: Int) in
                        row(rows[i], header: false)
                            .background(i % 2 == 1 ? Avo.surface2.opacity(0.45) : Color.clear)
                    }
                }
            }
        }
    }

    private func row(_ cells: [String], header: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(0..<columns.count, id: \.self) { (c: Int) in
                let text: String = c < cells.count ? cells[c] : ""
                Text(header ? text.uppercased() : text)
                    .font(header ? .caption2.weight(.semibold) : .footnote)
                    .foregroundStyle(header ? Avo.textDim : Avo.text)
                    .lineLimit(header ? 1 : 3)
                    .frame(width: columns[c].width ?? 180, alignment: .leading)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }
}

/// Small line chart of a series (Windows Sparkline). Non-finite values break the line.
struct ShellSparkline: View {
    var values: [Double]
    var color: Color

    var body: some View {
        GeometryReader { geo in
            let finite: [Double] = values.filter { $0.isFinite }
            if finite.count > 1, let lo = finite.min(), let hi = finite.max() {
                Path { p in
                    let n: Int = values.count
                    let span: Double = hi - lo > 1e-9 ? hi - lo : 1
                    var drawing: Bool = false
                    for i in 0..<n {
                        let v: Double = values[i]
                        if !v.isFinite { drawing = false; continue }
                        let x: CGFloat = geo.size.width * CGFloat(Double(i) / Double(max(n - 1, 1)))
                        let y: CGFloat = geo.size.height * CGFloat(1 - (v - lo) / span)
                        if drawing { p.addLine(to: CGPoint(x: x, y: y)) } else { p.move(to: CGPoint(x: x, y: y)); drawing = true }
                    }
                }
                .stroke(color, lineWidth: 1.4)
            }
        }
    }

    /// At most `count` points of a series (decimated by taking every k-th sample).
    static func decimate(_ v: [Double], _ count: Int = 240) -> [Double] {
        if v.count <= count { return v }
        let step: Double = Double(v.count) / Double(count)
        var out: [Double] = []
        out.reserveCapacity(count)
        for k in 0..<count { out.append(v[min(v.count - 1, Int(Double(k) * step))]) }
        return out
    }
}
