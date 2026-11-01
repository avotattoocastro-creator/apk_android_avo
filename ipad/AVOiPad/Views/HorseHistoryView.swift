import SwiftUI
import Charts

/// «Historia del caballo»: AVO Training Analytics 1.0.0 over every session of one horse (App/HorseHistoryModel.swift).
/// State NORMAL / VIGILAR / REVISAR with reasons (orientative, not a diagnosis), load per day or week with acute / chronic
/// load and ACWR, monotony and strain, last session against its own baseline, 8-week trends and the list of sessions.
struct HorseHistoryView: View {
    @Environment(AppModel.self) private var app
    @Bindable var model: HorseHistoryModel

    /// Categorical order of the load components (validated for the dark surface: CVD ΔE ≥ 9, contrast ≥ 3:1).
    static let partColors: [Color] = [Color(hex: 0x3987E5), Color(hex: 0xD95926), Color(hex: 0x199E70), Color(hex: 0x9085E9)]

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().overlay(Avo.line)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if model.isDemoHorse {
                        Text("DEMOSTRACIÓN · caballo de demostración: la historia usa sesiones SINTÉTICAS")
                            .font(.caption.weight(.semibold)).foregroundStyle(Avo.warn)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Avo.warn.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Avo.warn, lineWidth: 1))
                    }
                    if let e = model.errorText {
                        AvoCard(title: "Error") {
                            Text(e).font(.footnote).foregroundStyle(Avo.bad).fixedSize(horizontal: false, vertical: true)
                            Button("Reintentar") { model.reload() }.buttonStyle(.avoSecondary)
                        }
                    }
                    if let r = model.result {
                        content(r)
                    } else if model.loading {
                        AvoCard {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text(model.progressText).font(.footnote).foregroundStyle(Avo.textDim)
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .background(Avo.bg)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                model.close()
            } label: {
                Label("Cerrar", systemImage: "xmark")
            }
            .buttonStyle(.avoSecondary)
            .accessibilityIdentifier("history.close")
            VStack(alignment: .leading, spacing: 2) {
                Text("Historia del caballo").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(Avo.silver)
                Text(model.horseName).font(.title2.weight(.semibold)).foregroundStyle(Avo.text).lineLimit(1)
            }
            Spacer(minLength: 8)
            if model.loading && model.result != nil {
                ProgressView().controlSize(.small)
                Text(model.progressText).font(.caption).foregroundStyle(Avo.textDim).lineLimit(1)
            }
            Button {
                model.reload()
            } label: {
                Label("Actualizar", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.avoSecondary)
            .disabled(model.loading)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Avo.headerBrush)
    }

    @ViewBuilder
    private func content(_ r: TrainingAnalysisResult) -> some View {
        stateCard(r)
        if r.sesiones.isEmpty {
            AvoCard { AvoNoData(text: "Sin sesiones con fecha y resumen para este caballo") }
        } else {
            loadCard(r)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    acwrCard(r).frame(maxWidth: .infinity)
                    monotonyCard(r).frame(width: 320)
                }
                .frame(minWidth: 860)
                VStack(alignment: .leading, spacing: 14) {
                    acwrCard(r)
                    monotonyCard(r)
                }
            }
            if !model.srpeBars.isEmpty { srpeCard }
            baselineCard(r)
            trendsCard
            sessionsCard
        }
        if !r.avisos.isEmpty {
            AvoCard(title: "Avisos del análisis") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(r.avisos.enumerated()), id: \.offset) { (item: (offset: Int, element: String)) in
                        Text("· " + item.element).font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- state
    private func stateCard(_ r: TrainingAnalysisResult) -> some View {
        let color: Color = HorseHistoryModel.levelColor(r.nivel)
        return AvoCard(title: "Estado a \(dayText(r.fechaReferencia))",
                       subtitle: "\(r.sesionesUsadas) sesiones · \(r.algoritmoCarga) · AVO Training Analytics \(r.version)") {
            HStack(alignment: .center, spacing: 12) {
                Label(r.nivel, systemImage: levelIcon(r.nivel))
                    .font(.title3.weight(.bold)).foregroundStyle(color)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.6), lineWidth: 1))
                    .accessibilityIdentifier("history.level")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Orientativo: no es un diagnóstico veterinario.")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Avo.text)
                    Text("Compara al caballo consigo mismo. La carga externa es una heurística sin validar con datos fisiológicos.")
                        .font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                }
            }
            if r.motivos.isEmpty {
                Text("Sin motivos de aviso.").font(.footnote).foregroundStyle(Avo.textDim)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(r.motivos.enumerated()), id: \.offset) { (item: (offset: Int, element: String)) in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(color).frame(width: 6, height: 6)
                            Text(item.element).font(.footnote).foregroundStyle(Avo.text).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                AvoMetric(label: "ACWR", value: num(r.carga.acwr, 2),
                          caption: "Banda \(AvoFormat.f(r.acwrLow, 1))–\(AvoFormat.f(r.acwrHigh, 1))",
                          accent: (r.acwrOutOfBand ?? false) ? Avo.warn : Avo.text)
                AvoMetric(label: "Aguda 7 d", value: num(r.carga.aguda, 0), caption: "Suma de carga externa")
                AvoMetric(label: "Crónica 28 d", value: num(r.carga.cronicaSemanal, 0), caption: "Media semanal")
                AvoMetric(label: "Monotonía", value: num(r.carga.monotonia, 2), caption: "Alta > \(AvoFormat.f(r.monotonyHigh, 1))")
                AvoMetric(label: "Días sin sesión", value: r.diasDesdeUltima.map { String($0) } ?? "—", caption: "Desde la última")
            }
            if missingText != nil {
                Text(missingText ?? "").font(.caption).foregroundStyle(Avo.warn).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var missingText: String? {
        model.missing > 0 ? "\(model.missing) sesión(es) sin resumen (sin segmentos RAW o error del motor): no se usan." : nil
    }

    // ---------------------------------------------------------------- load chart
    private func loadCard(_ r: TrainingAnalysisResult) -> some View {
        let bars: [HorseLoadBar] = model.loadBars
        let lines: [HorseLinePoint] = model.loadLines
        let names: [String] = HorseHistoryModel.loadParts + ["Aguda 7 d", "Crónica 28 d"]
        let colors: [Color] = HorseHistoryView.partColors + [Avo.text, Avo.silver]
        let unit: Calendar.Component = model.byWeek ? .weekOfYear : .day
        return AvoCard(title: "Carga externa", subtitle: model.byWeek
                       ? "Por semana, apilada por aire + metros a alta velocidad · líneas: aguda 7 d y crónica 28 d (por semana)"
                       : "Por día, apilada por aire + metros a alta velocidad · líneas: aguda 7 d y crónica 28 d (media diaria = /7)") {
            Picker("Agrupar", selection: $model.byWeek) {
                Text("Día").tag(false)
                Text("Semana").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 240)
            if bars.isEmpty {
                AvoNoData()
            } else {
                Chart {
                    ForEach(bars) { (b: HorseLoadBar) in
                        BarMark(x: .value("Fecha", b.date, unit: unit), y: .value("Carga", b.value))
                            .foregroundStyle(by: .value("Serie", b.part))
                            .cornerRadius(2)
                    }
                    ForEach(lines) { (p: HorseLinePoint) in
                        LineMark(x: .value("Fecha", p.date), y: .value("Carga", p.value), series: .value("Línea", p.series))
                            .foregroundStyle(by: .value("Serie", p.series))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: p.series == "Crónica 28 d" ? [5, 3] : []))
                            .interpolationMethod(.monotone)
                    }
                }
                .chartForegroundStyleScale(domain: names, range: colors)
                .chartLegend(position: .bottom, alignment: .leading)
                .chartXAxis { dateAxis }
                .chartYAxis { valueAxis(0) }
                .frame(height: 240)
            }
            Text("Carga = min paso × \(AvoFormat.f(r.param("factor_paso", 1), 1)) + min trote × \(AvoFormat.f(r.param("factor_trote", 3), 1)) + min galope × \(AvoFormat.f(r.param("factor_galope", 6), 1)) + (m > \(AvoFormat.f(r.param("alta_velocidad_m_s", 11), 0)) m/s / 100) × \(AvoFormat.f(r.param("factor_alta_velocidad", 1), 1)).")
                .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
        }
    }

    // ---------------------------------------------------------------- ACWR
    private func acwrCard(_ r: TrainingAnalysisResult) -> some View {
        let pts: [HorseLinePoint] = model.acwrPoints
        let lo: Double = r.acwrLow, hi: Double = r.acwrHigh
        return AvoCard(title: "ACWR (aguda / crónica)", subtitle: "Banda \(AvoFormat.f(lo, 1))–\(AvoFormat.f(hi, 1)): por encima, subida brusca (VIGILAR); por debajo, descarga o parada (informativo). Necesita 28 días de historia.") {
            if pts.isEmpty || model.dateDomain == nil {
                AvoNoData(text: "Sin ACWR: la historia todavía no cubre 28 días")
            } else {
                let dom: ClosedRange<Date> = model.dateDomain ?? (Date()...Date())
                Chart {
                    RectangleMark(xStart: .value("Desde", dom.lowerBound), xEnd: .value("Hasta", dom.upperBound),
                                  yStart: .value("Bajo", lo), yEnd: .value("Alto", hi))
                        .foregroundStyle(Avo.silver.opacity(0.08))
                    RuleMark(y: .value("Alto", hi)).foregroundStyle(Avo.textDim).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    RuleMark(y: .value("Bajo", lo)).foregroundStyle(Avo.textDim).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    ForEach(pts) { (p: HorseLinePoint) in
                        LineMark(x: .value("Fecha", p.date), y: .value("ACWR", p.value), series: .value("Línea", p.series))
                            .foregroundStyle(by: .value("Serie", p.series))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: p.series == "ACWR sRPE" ? [5, 3] : []))
                        PointMark(x: .value("Fecha", p.date), y: .value("ACWR", p.value))
                            .foregroundStyle(by: .value("Serie", p.series))
                            .symbolSize(30)
                    }
                }
                .chartForegroundStyleScale(domain: ["ACWR", "ACWR sRPE"], range: [HorseHistoryView.partColors[0], HorseHistoryView.partColors[1]])
                .chartXScale(domain: dom)
                .chartLegend(position: .bottom, alignment: .leading)
                .chartXAxis { dateAxis }
                .chartYAxis { valueAxis(1) }
                .frame(height: 210)
            }
        }
    }

    private func monotonyCard(_ r: TrainingAnalysisResult) -> some View {
        AvoCard(title: "Monotonía y tensión", subtitle: "Últimos 7 días, días sin sesión = 0") {
            ShellKeyValue(key: "Monotonía (media / desviación)", value: num(r.carga.monotonia, 2))
            ShellKeyValue(key: "Umbral de aviso", value: "> " + AvoFormat.f(r.monotonyHigh, 1))
            ShellKeyValue(key: "Tensión (aguda × monotonía)", value: num(r.carga.tension, 0))
            ShellKeyValue(key: "Carga del día de referencia", value: num(r.carga.externa, 0))
            ShellKeyValue(key: "ACWR sRPE", value: num(r.carga.acwrSrpe, 2))
            Text("La monotonía alta (cargas muy parecidas todos los días) sube el nivel a VIGILAR.")
                .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var srpeCard: some View {
        let pts: [HorseLinePoint] = model.srpeBars
        let unit: Calendar.Component = model.byWeek ? .weekOfYear : .day
        return AvoCard(title: "Carga sRPE", subtitle: "RPE del entrenador × minutos en movimiento, solo sesiones valoradas") {
            Chart(pts) { (p: HorseLinePoint) in
                BarMark(x: .value("Fecha", p.date, unit: unit), y: .value("sRPE", p.value))
                    .foregroundStyle(HorseHistoryView.partColors[3])
                    .cornerRadius(2)
            }
            .chartXAxis { dateAxis }
            .chartYAxis { valueAxis(0) }
            .frame(height: 160)
        }
    }

    // ---------------------------------------------------------------- baseline of the last session
    private func baselineCard(_ r: TrainingAnalysisResult) -> some View {
        let rows: [HorseBaselineRow] = model.baselineRows
        let last: TrainingSessionResult? = r.lastSession
        return AvoCard(title: "Última sesión frente a su línea base",
                       subtitle: "\(last.map { dayText($0.fecha) } ?? "—") · mediana y MAD de sus sesiones anteriores de 60 días (≥ 4) · z = (valor − mediana) / escala robusta · solo se marca el sentido malo; la velocidad es informativa") {
            if rows.isEmpty {
                AvoNoData()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            head("Métrica", 210); head("Valor", 100); head("Mediana", 100); head("MAD", 90); head("z", 60); head("Estado", 300)
                        }
                        .padding(.vertical, 6)
                        Divider().overlay(Avo.line)
                        ForEach(rows) { (row: HorseBaselineRow) in
                            HStack(spacing: 8) {
                                cell(row.label, 210)
                                cell(row.value, 100)
                                cell(row.median, 100)
                                cell(row.mad, 90)
                                cell(row.z, 60)
                                HStack(spacing: 6) {
                                    if row.flag == "VIGILAR" || row.flag == "REVISAR" {
                                        AvoPill(text: row.flag, color: HorseHistoryModel.levelColor(row.flag))
                                    } else {
                                        Text(row.flagText).foregroundStyle(row.flag == "NORMAL" ? Avo.text : Avo.textDim).lineLimit(2)
                                    }
                                }
                                .frame(width: 300, alignment: .leading)
                            }
                            .font(.footnote).foregroundStyle(Avo.text)
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- trends
    private var trendsCard: some View {
        let list: [TrainingTrend] = model.trends
        return AvoCard(title: "Tendencias de 8 semanas",
                       subtitle: "Pendiente de Theil-Sen por semana · SUBE si p10 > 0, BAJA si p90 < 0 · hacen falta ≥ 5 sesiones en 3 días distintos") {
            if list.isEmpty {
                AvoNoData()
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 8)], spacing: 8) {
                    ForEach(list) { (t: TrainingTrend) in
                        let key: String = TrainingAnalytics.split(t.metrica).key
                        HStack(spacing: 8) {
                            Image(systemName: t.arrow).font(.callout.weight(.bold))
                                .foregroundStyle(t.hasData ? Avo.cyan : Avo.unknown).frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(TrainingAnalytics.fullLabel(t.metrica)).font(.footnote.weight(.semibold)).foregroundStyle(Avo.text).lineLimit(1)
                                Text(t.hasData ? "\(t.direccion) · \(TrainingAnalytics.formatSlope(key, t.pendienteSemana)) · \(t.n) sesiones"
                                               : "Sin datos suficientes (\(t.n) sesiones)")
                                    .font(.caption2).foregroundStyle(Avo.textDim).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(8)
                        .background(Avo.surface2, in: RoundedRectangle(cornerRadius: 7))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- sessions
    private var sessionsCard: some View {
        let rows: [HorseSessionRow] = model.sessionRows
        return AvoCard(title: "Sesiones", subtitle: "Toca una sesión para abrirla en Análisis") {
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        head("Fecha", 130); head("Paso", 70); head("Trote", 70); head("Galope", 70); head("Distancia", 85)
                        head("Alta vel.", 80); head("Carga", 60); head("RPE", 45); head("Estado", 90); head("Nivel", 90)
                    }
                    .padding(.vertical, 6)
                    Divider().overlay(Avo.line)
                    ForEach(rows) { (row: HorseSessionRow) in
                        Button {
                            model.openSession(row.id)
                        } label: {
                            HStack(spacing: 8) {
                                HStack(spacing: 4) {
                                    Text(row.date).lineLimit(1)
                                    if row.demo { AvoPill(text: "DEMO", color: Avo.warn) }
                                }
                                .frame(width: 130, alignment: .leading)
                                cell(row.walkMin, 70); cell(row.trotMin, 70); cell(row.canterMin, 70); cell(row.distance, 85)
                                cell(row.highSpeed, 80); cell(row.load, 60); cell(row.rpe, 45); cell(row.trainerState, 90)
                                HStack {
                                    AvoPill(text: row.level, color: HorseHistoryModel.levelColor(row.level))
                                }
                                .frame(width: 90, alignment: .leading)
                            }
                            .font(.footnote).foregroundStyle(Avo.text)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!row.loaded)
                        Divider().overlay(Avo.line)
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- helpers
    private var dateAxis: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 6)) { value in
            AxisGridLine().foregroundStyle(Avo.line)
            AxisValueLabel {
                if let d = value.as(Date.self) {
                    Text(AvoTime.formatter("dd/MM", utc: true).string(from: d)).font(.caption2).foregroundStyle(Avo.textDim)
                }
            }
        }
    }

    private func valueAxis(_ decimals: Int) -> some AxisContent {
        AxisMarks(position: .leading) { value in
            AxisGridLine().foregroundStyle(Avo.line)
            AxisValueLabel {
                if let d = value.as(Double.self) {
                    Text(AvoFormat.f(d, decimals)).font(.caption2).foregroundStyle(Avo.textDim)
                }
            }
        }
    }

    private func head(_ t: String, _ w: CGFloat) -> some View {
        Text(t.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(Avo.textDim).frame(width: w, alignment: .leading)
    }

    private func cell(_ t: String, _ w: CGFloat) -> some View {
        Text(t).lineLimit(1).truncationMode(.tail).frame(width: w, alignment: .leading)
    }

    private func num(_ v: Double?, _ decimals: Int) -> String {
        guard let x = v, x.isFinite else { return "—" }
        return AvoFormat.f(x, decimals)
    }

    private func dayText(_ s: String) -> String {
        guard let d = TrainingAnalytics.day(s) else { return s.isEmpty ? "—" : s }
        return AvoTime.formatter("dd/MM/yyyy", utc: true).string(from: d)
    }

    private func levelIcon(_ l: String) -> String {
        switch l {
        case "REVISAR": return "exclamationmark.octagon.fill"
        case "VIGILAR": return "exclamationmark.triangle.fill"
        default: return "checkmark.circle.fill"
        }
    }
}
