import SwiftUI
import Charts

/// «Análisis del tramo»: full-screen page with the complete analysis of the selected stretch (StretchModel).
struct StretchAnalysisView: View {
    @Environment(AppModel.self) private var app
    @Bindable var model: StretchModel

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().overlay(Avo.line)
            if let r = model.report {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !model.message.isEmpty {
                            Text(model.message).font(.footnote).foregroundStyle(Avo.cyan)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        metrics(r)
                        profile(r)
                        HStack(alignment: .top, spacing: 14) {
                            splitsCard(r).frame(maxWidth: .infinity)
                            VStack(spacing: 14) {
                                observationsCard(r)
                                compareCard(r)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        aiCard
                    }
                    .padding(20)
                }
            } else {
                Spacer()
            }
        }
        .background(Avo.bg)
    }

    // ---------------------------------------------------------------- top bar
    private var topBar: some View {
        HStack(spacing: 12) {
            Button { model.close() } label: { Label("Cerrar", systemImage: "xmark") }
                .buttonStyle(.avoSecondary)
                .accessibilityIdentifier("stretch.close")
            VStack(alignment: .leading, spacing: 2) {
                Text("ANÁLISIS DEL TRAMO").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(Avo.silver)
                Text(title).font(.title2.weight(.semibold)).foregroundStyle(Avo.text).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            TextField("Nombre del tramo (opcional)", text: $model.saveName)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Avo.surface2, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Avo.line, lineWidth: 1))
                .frame(maxWidth: 260)
            Button {
                model.save()
            } label: {
                Label(model.savedId == nil ? "Guardar en \(model.horseName)" : "Actualizar tramo guardado",
                      systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.avoPrimary)
            .disabled(!model.canSave)
            .accessibilityIdentifier("stretch.save")
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Avo.headerBrush)
    }

    private var title: String {
        guard let s = model.session else { return "" }
        return "\(s.horse) · \(s.dateTimeText) · \(TimeText.clock(model.t0)) – \(TimeText.clock(model.t1))"
    }

    // ---------------------------------------------------------------- metrics
    private func metrics(_ r: StretchReport) -> some View {
        let m: SegmentMetrics = r.metrics
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
            AvoMetric(label: "Distancia", value: TimeText.num(m.distanceM, "0", " m"))
            AvoMetric(label: "Duración", value: TimeText.clock(m.durationS))
            AvoMetric(label: "Vel. media", value: TimeText.num(m.meanSpeedKmh, "0.0", " km/h"))
            AvoMetric(label: "Vel. máxima", value: TimeText.num(m.maxSpeedKmh, "0.0", " km/h"),
                      caption: "a los " + TimeText.num(r.vmaxAtM, "0", " m"))
            AvoMetric(label: "Mejor 200 m", value: TimeText.num(r.best200S, "0.00", " s"),
                      caption: r.best200Index.map { "parcial \($0)" })
            AvoMetric(label: "Último 200 m vs mejor", value: TimeText.num(r.lastVsBestPct, "+0.0;-0.0", " %"),
                      caption: "positivo = más lento", accent: (r.lastVsBestPct ?? 0) >= 8 ? Avo.warn : Avo.text)
            AvoMetric(label: "2.ª mitad vs 1.ª", value: TimeText.num(r.halvesPct, "+0.0;-0.0", " %"), caption: "velocidad media")
            AvoMetric(label: "Hasta 90 % Vmáx", value: TimeText.num(r.to90S, "0.0", " s"))
            AvoMetric(label: "Sobre 90 % Vmáx", value: TimeText.num(r.above90M, "0", " m"), caption: TimeText.num(r.above90S, "0.0", " s"))
            AvoMetric(label: "Acel. máx. validada", value: TimeText.num(m.maxAccel, "0.00", " m/s²"))
            AvoMetric(label: "Frenada máx. validada", value: TimeText.num(m.maxDecel, "0.00", " m/s²"))
            AvoMetric(label: "Regularidad parciales", value: TimeText.num(r.splitCvPct, "0.0", " %"), caption: "CV (menor = más regular)")
            AvoMetric(label: "Cadencia", value: TimeText.num(m.cadence, "0", " c/min"), caption: "motor AVO (cincha)")
            AvoMetric(label: "RTK FIX", value: TimeText.num(m.fixFraction * 100, "0", " %"),
                      caption: m.gapCount > 0 ? "\(m.gapCount) pérdidas de señal" : "sin pérdidas")
        }
    }

    // ---------------------------------------------------------------- speed profile with 200 m marks
    private func profile(_ r: StretchReport) -> some View {
        AvoCard(title: "Velocidad en el tramo", subtitle: "km/h frente a metros desde el inicio · líneas cada 200 m · punto naranja = velocidad máxima") {
            Chart {
                ForEach(r.splits) { (s: StretchSplit) in
                    RuleMark(x: .value("m", s.toM)).foregroundStyle(Avo.line).lineStyle(StrokeStyle(lineWidth: 0.6, dash: [3, 3]))
                }
                ForEach(r.samples) { (p: StretchSample) in
                    LineMark(x: .value("m", p.m), y: .value("km/h", p.kmh)).foregroundStyle(Avo.red)
                        .interpolationMethod(.linear)
                }
                if let vm = r.vmaxAtM, let v = r.metrics.maxSpeedKmh {
                    PointMark(x: .value("m", vm), y: .value("km/h", v)).foregroundStyle(MapVmaxMark.color).symbolSize(70)
                }
            }
            .chartYScale(domain: .automatic(includesZero: true))
            .chartXAxis {
                AxisMarks(values: .stride(by: 200)) { (v: AxisValue) in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4)).foregroundStyle(Avo.line)
                    AxisValueLabel { Text("\(v.as(Double.self).map { Int($0) } ?? 0) m").font(.caption2).foregroundStyle(Avo.textDim) }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { (_: AxisValue) in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4)).foregroundStyle(Avo.line)
                    AxisValueLabel().font(.caption2).foregroundStyle(Avo.textDim)
                }
            }
            .frame(height: 240)
        }
    }

    // ---------------------------------------------------------------- 200 m splits
    private func splitsCard(_ r: StretchReport) -> some View {
        AvoCard(title: "Desglose por tramos de 200 m", subtitle: "tiempo, velocidad media y máxima, aceleración media del parcial") {
            if r.splits.isEmpty {
                Text("El tramo es demasiado corto o no tiene distancia GNSS.").font(.footnote).foregroundStyle(Avo.textDim)
            } else {
                VStack(spacing: 0) {
                    row(["#", "Metros", "Tiempo", "Media", "Máx.", "Acel."], header: true, best: false)
                    ForEach(r.splits) { (s: StretchSplit) in
                        row(StretchAnalysisView.cells(s), header: false, best: s.index == r.best200Index)
                    }
                }
                if r.splits.contains(where: { $0.partial }) {
                    Text("* parcial final de menos de 200 m (no cuenta para el mejor 200 m).").font(.caption2).foregroundStyle(Avo.textDim)
                }
            }
        }
    }

    static func cells(_ s: StretchSplit) -> [String] {
        let n: String = String(s.index) + (s.partial ? "*" : "")
        let metres: String = TimeText.num(s.fromM, "0") + "–" + TimeText.num(s.toM, "0")
        let time: String = TimeText.num(s.durationS, "0.00", " s")
        let mean: String = TimeText.num(s.meanKmh, "0.0")
        let max: String = TimeText.num(s.maxKmh, "0.0")
        let acc: String = TimeText.num(s.accel, "+0.00;-0.00")
        return [n, metres, time, mean, max, acc]
    }

    static func observationList(_ r: StretchReport) -> [String] {
        var o: [String] = r.observations
        if r.metrics.observations != "Datos completos" { o.append("Datos: " + r.metrics.observations) }
        return o
    }

    private func row(_ cells: [String], header: Bool, best: Bool) -> some View {
        let widths: [CGFloat] = [34, 96, 80, 62, 62, 64]
        return HStack(spacing: 6) {
            ForEach(Array(cells.enumerated()), id: \.offset) { (i: Int, c: String) in
                Text(c)
                    .font(header ? .caption2.weight(.semibold) : .callout.monospacedDigit())
                    .foregroundStyle(header ? Avo.textDim : (best ? Avo.ok : Avo.text))
                    .frame(width: widths[min(i, widths.count - 1)], alignment: i == 0 ? .leading : .trailing)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .background(best ? Avo.ok.opacity(0.10) : Color.clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Avo.line).frame(height: header ? 1 : 0.5) }
    }

    // ---------------------------------------------------------------- observations / comparison
    private func observationsCard(_ r: StretchReport) -> some View {
        AvoCard(title: "Observaciones", subtitle: "calculadas con los datos del tramo") {
            ForEach(Array(StretchAnalysisView.observationList(r).enumerated()), id: \.offset) { (_: Int, o: String) in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(Avo.red).frame(width: 6, height: 6).padding(.top, 6)
                    Text(o).font(.footnote).foregroundStyle(Avo.text).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func compareCard(_ r: StretchReport) -> some View {
        let others: [SavedStretch] = model.otherSaved()
        return AvoCard(title: "Tramos guardados de \(model.horseName)", subtitle: "para comparar · se guardan con «Guardar en…»") {
            if others.isEmpty {
                Text("Todavía no hay otros tramos guardados de este caballo.").font(.footnote).foregroundStyle(Avo.textDim)
            } else {
                VStack(spacing: 0) {
                    cmpRow(["Tramo", "Dist.", "Media", "Máx.", "Mejor 200"], header: true, current: false)
                    cmpRow(["Este tramo", TimeText.num(r.metrics.distanceM, "0", " m"), TimeText.num(r.metrics.meanSpeedKmh, "0.0"),
                            TimeText.num(r.metrics.maxSpeedKmh, "0.0"), TimeText.num(r.best200S, "0.00", " s")], header: false, current: true)
                    ForEach(others.prefix(12)) { (o: SavedStretch) in
                        cmpRow([o.title, TimeText.num(o.distanceM, "0", " m"), TimeText.num(o.meanKmh, "0.0"),
                                TimeText.num(o.maxKmh, "0.0"), TimeText.num(o.best200S, "0.00", " s")], header: false, current: false)
                    }
                }
            }
        }
    }

    private func cmpRow(_ c: [String], header: Bool, current: Bool) -> some View {
        HStack(spacing: 6) {
            Text(c[0]).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
            ForEach(1..<c.count, id: \.self) { (i: Int) in Text(c[i]).frame(width: 74, alignment: .trailing) }
        }
        .font(header ? .caption2.weight(.semibold) : .caption.monospacedDigit())
        .foregroundStyle(header ? Avo.textDim : (current ? Avo.cyan : Avo.text))
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) { Rectangle().fill(Avo.line).frame(height: header ? 1 : 0.5) }
    }

    // ---------------------------------------------------------------- AI
    private var aiCard: some View {
        AvoCard(title: "Análisis completo IA y recomendaciones",
                subtitle: "con los datos de este tramo, del entrenamiento completo y de sus tramos guardados · motor: \(app.assistant.engineLabel)") {
            HStack(spacing: 10) {
                Button {
                    model.askAI()
                } label: {
                    Label(model.aiText.isEmpty ? "Analizar con IA" : "Volver a analizar", systemImage: "sparkles")
                }
                .buttonStyle(.avoPrimary)
                .disabled(model.aiBusy)
                .accessibilityIdentifier("stretch.ai")
                if model.aiBusy {
                    ProgressView().controlSize(.small)
                    Button("Detener") { model.stopAI() }.buttonStyle(.avoSecondary)
                }
                if !model.aiStatus.isEmpty {
                    Text(model.aiStatus).font(.caption).foregroundStyle(Avo.textDim).lineLimit(2)
                }
            }
            if !model.aiText.isEmpty {
                Text(LocalizedStringKey(model.aiText))
                    .font(.callout).foregroundStyle(Avo.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.aiFooter.isEmpty {
                Text(model.aiFooter + (model.savedId != nil ? " · pulsa «Actualizar tramo guardado» para guardarlo" : ""))
                    .font(.caption2).foregroundStyle(Avo.textDim)
            }
        }
    }
}
