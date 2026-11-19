import SwiftUI

/// «Motor» page for trainers (trainer 14/11/2026: «algo legible y entendible, que cualquier entrenador pueda sacar
/// provecho»). Same results of the AVO Performance Equine engine (same C++ engine as Android and Windows), told in plain
/// words: a short reading of the training, time per gait, the phases, the key moments, the curves and how reliable the
/// data are. The original engine tables stay under «Detalle técnico», folded.
struct EngineView: View {
    @Environment(AppModel.self) private var app
    @State private var technical: Bool = false
    // «Botones» column (trainer's sketch 19/11/2026, build 173)
    @State private var busyText: String = ""
    @State private var resultText: String = ""
    @State private var askHorse: Bool = false
    @State private var askCache: Bool = false
    @State private var shareURL: URL? = nil

    var body: some View {
        GeometryReader { geo in
            let wide: Bool = geo.size.width >= 1000
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let e = engine {
                        HStack(alignment: .top, spacing: 12) {
                            readingCard(e).frame(maxWidth: .infinity)
                            actionsColumn(proxy)
                        }
                        gaitsCard(e)
                        if wide {
                            HStack(alignment: .top, spacing: 12) {
                                phasesCard(e).frame(maxWidth: .infinity)
                                momentsCard(e).frame(maxWidth: .infinity)
                            }
                            HStack(alignment: .top, spacing: 12) {
                                curvesCard(e).frame(maxWidth: .infinity)
                                reliabilityCard(e).frame(maxWidth: .infinity)
                            }
                        } else {
                            phasesCard(e)
                            momentsCard(e)
                            curvesCard(e)
                            reliabilityCard(e)
                        }
                        technicalFold(e).id("motor.technical")
                    } else {
                        HStack(alignment: .top, spacing: 12) {
                            AvoCard {
                                AvoNoData(text: app.selected.map { "El motor AVO todavía no ha analizado este entrenamiento · \($0.engineState)" }
                                          ?? "Elige un entrenamiento")
                            }
                            .frame(maxWidth: .infinity)
                            actionsColumn(proxy)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            }
        }
        .background(Avo.bg)
        .confirmationDialog("Reprocesar todo el caballo", isPresented: $askHorse, titleVisibility: .visible) {
            Button("Reprocesar \(horseSessions.count) entrenamientos") { reprocessHorse() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se pasa el motor \(EquineEngine.version()) por todos los entrenamientos de \(app.selected?.horse ?? "este caballo") en este iPad, uno detrás de otro. Puede tardar varios minutos.")
        }
        .confirmationDialog("Borrar caché del motor", isPresented: $askCache, titleVisibility: .visible) {
            Button("Borrar resultados guardados", role: .destructive) { deleteCache() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se borran los resultados del motor guardados en el iPad (no los entrenamientos, ni las correcciones, ni las valoraciones). Cada entrenamiento se vuelve a calcular la próxima vez que se analice.")
        }
        .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })) {
            if let u = shareURL { ReportsActivitySheet(url: u) }
        }
    }

    // ------------------------------------------------------------------ buttons column
    private var horseSessions: [SessionItem] { app.selected.map { app.sessionsOfSameHorse($0) } ?? [] }
    private var busy: Bool { !busyText.isEmpty }

    private func actionsColumn(_ proxy: ScrollViewProxy) -> some View {
        let hasSel: Bool = app.selected != nil
        let hasResult: Bool = !(engine?.rawJson.isEmpty ?? true)
        return VStack(alignment: .leading, spacing: 8) {
            actionButton("Reprocesar", "arrow.clockwise", primary: true, enabled: hasSel && !busy, id: "motor.reprocess") {
                guard let s = app.selected else { return }
                busyText = "Reprocesando…"
                resultText = ""
                Task { @MainActor in
                    await app.runEngine(s, force: true)
                    busyText = ""
                    resultText = s.engineState
                }
            }
            actionButton("Reprocesar caballo", "arrow.triangle.2.circlepath", enabled: hasSel && !busy && !horseSessions.isEmpty,
                         id: "motor.reprocessHorse") { askHorse = true }
            actionButton("Exportar JSON", "square.and.arrow.up", enabled: hasResult && !busy, id: "motor.exportJson") {
                guard let s = app.selected else { return }
                do {
                    shareURL = try app.exportEngineJson(s)
                    resultText = "JSON guardado en Exportados"
                } catch {
                    resultText = error.localizedDescription
                }
            }
            actionButton(technical ? "Ocultar detalle" : "Detalle técnico", "tablecells", enabled: engine != nil, id: "motor.technicalButton") {
                withAnimation(.easeInOut(duration: 0.2)) { technical.toggle() }
                if technical {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        withAnimation { proxy.scrollTo("motor.technical", anchor: .top) }
                    }
                }
            }
            actionButton("Borrar caché", "trash", destructive: true, enabled: !busy, id: "motor.deleteCache") { askCache = true }
            if busy {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(busyText).font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                }
            } else if !resultText.isEmpty {
                Text(resultText).font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            }
            Text("Motor \(EquineEngine.version())").font(.caption2).foregroundStyle(Avo.textDim).lineLimit(2)
        }
        .padding(12)
        .frame(width: 210, alignment: .topLeading)
        .background(Avo.cardBrush, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Avo.line, lineWidth: 1))
    }

    private func actionButton(_ title: String, _ icon: String, primary: Bool = false, destructive: Bool = false, enabled: Bool,
                              id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.avoSecondary)
        .foregroundStyle(destructive ? Avo.bad : (primary ? Avo.red : Avo.text))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityIdentifier(id)
    }

    private func reprocessHorse() {
        let list: [SessionItem] = horseSessions
        guard !list.isEmpty else { return }
        resultText = ""
        busyText = "Reprocesando 0 de \(list.count)…"
        Task { @MainActor in
            let ok: Int = await app.reprocess(list) { (done: Int, total: Int) in
                busyText = "Reprocesando \(min(done + 1, total)) de \(total)…"
            }
            busyText = ""
            resultText = "\(ok) de \(list.count) entrenamientos reprocesados con el motor actual"
        }
    }

    private func deleteCache() {
        let n: Int = app.deleteEngineCache()
        resultText = n == 1 ? "1 resultado borrado" : "\(n) resultados borrados"
    }

    private var engine: EquineAnalysis? { app.selected?.engine }

    // ------------------------------------------------------------------ reading
    private func readingCard(_ e: EquineAnalysis) -> some View {
        let lines: [String] = EngineReading.summary(e)
        return AvoCard(title: "Lectura del entrenamiento", subtitle: "Lo que el motor AVO ve en este entrenamiento, en pocas líneas") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<lines.count, id: \.self) { (i: Int) in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(Avo.red).frame(width: 6, height: 6)
                        Text(lines[i]).font(.callout).foregroundStyle(Avo.text).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------ gaits
    private func gaitsCard(_ e: EquineAnalysis) -> some View {
        let shares: [EngineReading.GaitShare] = EngineReading.gaitShares(e)
        let total: Double = max(shares.reduce(0) { $0 + $1.seconds }, 1)
        return AvoCard(title: "Tiempo en cada aire") {
            if shares.isEmpty {
                AvoNoData(text: "Sin aires clasificados")
            } else {
                GeometryReader { g in
                    HStack(spacing: 2) {
                        ForEach(shares) { (s: EngineReading.GaitShare) in
                            Rectangle().fill(EngineReading.color(s.gait))
                                .frame(width: max(2, (g.size.width - CGFloat(shares.count * 2)) * CGFloat(s.seconds / total)))
                        }
                    }
                }
                .frame(height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                HStack(spacing: 0) {
                    ForEach(shares) { (s: EngineReading.GaitShare) in
                        VStack(spacing: 4) {
                            HStack(spacing: 6) {
                                Circle().fill(EngineReading.color(s.gait)).frame(width: 9, height: 9)
                                Text(s.gait.uppercased()).font(.caption.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.silver)
                            }
                            Text(TimeText.clock(s.seconds)).font(.title3).foregroundStyle(Avo.text)
                            Text("\(Int((s.seconds / total * 100).rounded())) % · \(EngineReading.km(s.meters))").font(.caption).foregroundStyle(Avo.textDim)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    // ------------------------------------------------------------------ phases
    private func phasesCard(_ e: EquineAnalysis) -> some View {
        AvoCard(title: "Fases del entrenamiento", subtitle: "Cada cambio de aire, en orden") {
            if e.segments.isEmpty {
                AvoNoData(text: "Sin fases")
            } else {
                VStack(spacing: 0) {
                    ForEach(0..<e.segments.count, id: \.self) { (i: Int) in
                        let r: EngineSegmentRow = e.segments[i]
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 2).fill(EngineReading.color(r.aire)).frame(width: 4, height: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.aire).font(.callout.weight(.semibold)).foregroundStyle(Avo.text)
                                Text("\(r.desde) → \(r.hasta) · \(TimeText.clock(max(0, r.t1 - r.t0)))").font(.caption.monospacedDigit()).foregroundStyle(Avo.textDim)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(r.distancia).font(.callout.monospacedDigit()).foregroundStyle(Avo.text)
                                Text("media \(r.velocidadMedia)").font(.caption.monospacedDigit()).foregroundStyle(Avo.textDim)
                            }
                        }
                        .padding(.vertical, 6)
                        .overlay(alignment: .bottom) { Rectangle().fill(Avo.line).frame(height: 1) }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------ key moments
    private func momentsCard(_ e: EquineAnalysis) -> some View {
        let items: [EngineReading.Moment] = EngineReading.moments(e)
        return AvoCard(title: "Momentos clave", subtitle: "Cambios de aire, paradas, frenadas y curvas, con su minuto") {
            if items.isEmpty {
                AvoNoData(text: "Sin momentos destacados")
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { (m: EngineReading.Moment) in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(m.time).font(.callout.monospacedDigit().weight(.semibold)).foregroundStyle(Avo.text).frame(width: 52, alignment: .leading)
                            Image(systemName: m.icon).font(.caption).foregroundStyle(m.color).frame(width: 18)
                            Text(m.text).font(.callout).foregroundStyle(Avo.text).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 6)
                        .overlay(alignment: .bottom) { Rectangle().fill(Avo.line).frame(height: 1) }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------ curves
    private func curvesCard(_ e: EquineAnalysis) -> some View {
        AvoCard(title: "Curvas", subtitle: "Giros detectados en el recorrido") {
            if e.curves.isEmpty {
                AvoNoData(text: "Sin curvas detectadas")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<e.curves.count, id: \.self) { (i: Int) in
                        let c: EngineCurveRow = e.curves[i]
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: c.direccion.uppercased().hasPrefix("IZQ") ? "arrow.turn.up.left" : "arrow.turn.up.right")
                                .foregroundStyle(Avo.cyan).frame(width: 20)
                            Text(EngineReading.curveText(c)).font(.callout).foregroundStyle(Avo.text).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------ reliability
    private func reliabilityCard(_ e: EquineAnalysis) -> some View {
        let rows: [EngineQualityRow] = e.quality.filter { !GpsTerms.mentionsGnss($0.dominio) }
        return AvoCard(title: "¿Cuánto fiarse de estos datos?") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(0..<rows.count, id: \.self) { (i: Int) in
                    let q: (name: String, text: String, color: Color) = EngineReading.quality(rows[i])
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(q.color).frame(width: 10, height: 10).padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(q.name).font(.callout.weight(.semibold)).foregroundStyle(Avo.text)
                            Text(q.text).font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------ technical (folded)
    private func technicalFold(_ e: EquineAnalysis) -> some View {
        AvoCard {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { technical.toggle() }
            } label: {
                HStack {
                    Text("DETALLE TÉCNICO").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(Avo.silver)
                    Text(app.engineInfo).font(.caption2).foregroundStyle(Avo.textDim).lineLimit(1)
                    Spacer()
                    Text(technical ? "Ocultar" : "Desplegar").font(.caption.weight(.semibold)).foregroundStyle(Avo.red)
                    Image(systemName: technical ? "chevron.up" : "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Avo.red)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if technical {
                Button("Reprocesar con el motor") {
                    if let s = app.selected { Task { @MainActor in await app.runEngine(s, force: true) } }
                }
                .buttonStyle(.avoSecondary)
                ShellTable(columns: [
                    ShellTable.Column(title: "#", width: 30), ShellTable.Column(title: "Aire", width: 90),
                    ShellTable.Column(title: "Desde", width: 60), ShellTable.Column(title: "Hasta", width: 60),
                    ShellTable.Column(title: "Distancia", width: 75), ShellTable.Column(title: "V. media", width: 80),
                    ShellTable.Column(title: "Cadencia", width: 80), ShellTable.Column(title: "Tranco", width: 65),
                    ShellTable.Column(title: "IMU", width: 160),
                ], rows: e.segments.map { (r: EngineSegmentRow) -> [String] in
                    ["\(r.id)", r.aire, r.desde, r.hasta, r.distancia, r.velocidadMedia, r.cadencia, r.tranco, r.calidadImu]
                })
                ShellTable(columns: [
                    ShellTable.Column(title: "Dominio", width: 110), ShellTable.Column(title: "Nivel", width: 100),
                    ShellTable.Column(title: "Motivos", width: 380),
                ], rows: e.quality.filter { !GpsTerms.mentionsGnss($0.dominio) }.map { [$0.dominio, $0.nivel, $0.motivos] })
                ShellTable(columns: [
                    ShellTable.Column(title: "Id", width: 60), ShellTable.Column(title: "Tipo", width: 170),
                    ShellTable.Column(title: "Inicio", width: 60), ShellTable.Column(title: "Fin", width: 60),
                    ShellTable.Column(title: "Motivo", width: 300),
                ], rows: e.events.filter { !GpsTerms.mentionsGnss($0.tipo) && !GpsTerms.mentionsGnss($0.motivo) }
                    .map { [$0.id, $0.tipo, $0.inicio, $0.fin, $0.motivo] })
            }
        }
    }
}

/// Plain-language reading of the engine result (no new figures: everything comes from the engine rows).
enum EngineReading {
    struct GaitShare: Identifiable {
        var id: String { gait }
        let gait: String
        var seconds: Double
        var meters: Double
    }

    struct Moment: Identifiable {
        let id: String
        let time: String
        let text: String
        let icon: String
        let color: Color
    }

    static func color(_ gait: String) -> Color {
        switch gait.lowercased() {
        case "parado": return Avo.textDim
        case "paso": return Avo.cyan
        case "trote": return Avo.warn
        case "galope": return Avo.red
        default: return Avo.silver
        }
    }

    /// «694 m» / «1083 m» → metres.
    static func meters(_ text: String) -> Double {
        let digits: String = text.filter { $0.isNumber || $0 == "," || $0 == "." }.replacingOccurrences(of: ",", with: ".")
        let v: Double = Double(digits) ?? 0
        return text.lowercased().contains("km") ? v * 1000 : v
    }

    static func km(_ m: Double) -> String {
        m >= 1000 ? DotNetFormat.custom(m / 1000, "0.00", spanish: true) + " km" : "\(Int(m.rounded())) m"
    }

    /// Time and distance per gait, in the order paso → trote → galope → parado → others.
    static func gaitShares(_ e: EquineAnalysis) -> [GaitShare] {
        var map: [String: GaitShare] = [:]
        for r in e.segments where r.t1 > r.t0 {
            var s: GaitShare = map[r.aire] ?? GaitShare(gait: r.aire, seconds: 0, meters: 0)
            s.seconds += r.t1 - r.t0
            s.meters += meters(r.distancia)
            map[r.aire] = s
        }
        let order: [String] = ["paso", "trote", "galope", "parado"]
        return map.values.sorted {
            let a: Int = order.firstIndex(of: $0.gait.lowercased()) ?? 9
            let b: Int = order.firstIndex(of: $1.gait.lowercased()) ?? 9
            return a != b ? a < b : $0.gait < $1.gait
        }
    }

    static func summary(_ e: EquineAnalysis) -> [String] {
        var out: [String] = []
        let shares: [GaitShare] = gaitShares(e)
        let total: Double = shares.reduce(0) { $0 + $1.seconds }
        if total > 0 {
            let parts: [String] = shares.map { "\($0.gait.lowercased()) \(TimeText.clock($0.seconds))" }
            out.append("Reparto del entrenamiento: " + parts.joined(separator: ", ") + ".")
        }
        let gallops: [EngineSegmentRow] = e.segments.filter { $0.aire.lowercased() == "galope" && $0.t1 > $0.t0 }
        if gallops.isEmpty {
            out.append("No se detecta ningún tramo a galope.")
        } else if let longest = gallops.max(by: { ($0.t1 - $0.t0) < ($1.t1 - $1.t0) }) {
            let n: Int = gallops.count
            out.append("\(n == 1 ? "Un tramo" : "\(n) tramos") a galope; el más largo dura \(TimeText.clock(longest.t1 - longest.t0)) "
                       + "(\(longest.desde) → \(longest.hasta)), \(longest.distancia) a \(longest.velocidadMedia) de media.")
        }
        let stops: Int = e.events.filter { $0.tipo.uppercased() == "PARADA" }.count
        if stops > 0 { out.append(stops == 1 ? "Se para una vez." : "Se para \(stops) veces.") }
        let brakes: Int = e.events.filter { $0.tipo.uppercased().hasPrefix("DESACELERACION") }.count
        if brakes > 0 { out.append(brakes == 1 ? "Una frenada sostenida." : "\(brakes) frenadas sostenidas.") }
        if !e.curves.isEmpty {
            let left: Int = e.curves.filter { $0.direccion.uppercased().hasPrefix("IZQ") }.count
            let right: Int = e.curves.count - left
            out.append("\(e.curves.count) \(e.curves.count == 1 ? "curva" : "curvas"): \(left) a la izquierda y \(right) a la derecha.")
        }
        let imu: EngineQualityRow? = e.quality.first { $0.dominio.uppercased() == "IMU" }
        if let q = imu, q.nivel.uppercased().contains("NO_UTILIZABLE") {
            out.append("Sin cincha: los aires salen de la velocidad GPS (aproximados); cadencia, tranco y simetría no se calculan.")
        }
        out.append("Resultados orientativos para el entrenamiento: no son un diagnóstico veterinario.")
        return out
    }

    static func moments(_ e: EquineAnalysis) -> [Moment] {
        var out: [Moment] = []
        for r in e.events {
            if GpsTerms.mentionsGnss(r.tipo) || GpsTerms.mentionsGnss(r.motivo) { continue }
            let tipo: String = r.tipo.uppercased()
            var text: String = r.tipo.replacingOccurrences(of: "_", with: " ").capitalized
            var icon: String = "circle.fill"
            var tint: Color = Avo.silver
            if tipo == "FIN_CURVA" { continue }
            if tipo.hasPrefix("TRANSICION") {
                let parts: [String] = r.motivo.components(separatedBy: "->").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                if parts.count == 2 {
                    text = "Pasa de \(parts[0]) a \(parts[1])"
                    tint = EngineReading.color(parts[1])
                } else {
                    text = "Cambio de aire: \(r.motivo)"
                }
                icon = "arrow.left.arrow.right"
            } else if tipo == "PARADA" {
                text = "Se para"; icon = "stop.circle"; tint = Avo.textDim
            } else if tipo.hasPrefix("INICIO_MOVIMIENTO") {
                text = "Arranca"; icon = "play.circle"; tint = Avo.ok
            } else if tipo.hasPrefix("DESACELERACION") {
                text = "Frena de forma sostenida (\(r.inicio) → \(r.fin))"; icon = "arrow.down.right.circle"; tint = Avo.warn
            } else if tipo == "INICIO_CURVA" {
                text = r.motivo.uppercased().contains("IZQUIERDA") ? "Entra en curva a la izquierda" : "Entra en curva a la derecha"
                icon = "arrow.turn.up.left"; tint = Avo.cyan
            }
            out.append(Moment(id: r.id, time: r.inicio, text: text, icon: icon, color: tint))
        }
        return out
    }

    static func curveText(_ c: EngineCurveRow) -> String {
        let side: String = c.direccion.uppercased().hasPrefix("IZQ") ? "izquierda" : "derecha"
        let turn: String = c.giro.replacingOccurrences(of: "-", with: "")
        var s: String = "\(c.inicio) · curva a la \(side), giro de \(turn), radio \(c.radio)"
        if !c.lateralEstimada.isEmpty && c.lateralEstimada != "—" { s += ", fuerza lateral \(c.lateralEstimada)" }
        return s + "."
    }

    /// Friendly name, plain explanation and traffic-light colour of one quality domain.
    static func quality(_ r: EngineQualityRow) -> (name: String, text: String, color: Color) {
        let n: String = r.nivel.uppercased()
        let color: Color = n.contains("NO_UTILIZABLE") || n.contains("MALA") ? Avo.bad
            : n.contains("BUENA") ? Avo.ok
            : n.contains("UTILIZABLE") || n.contains("ACEPTABLE") ? Avo.warn
            : Avo.textDim
        switch r.dominio.uppercased() {
        case "IMU":
            return ("Cincha", n.contains("NO_UTILIZABLE") ? "No hay datos de la cincha en este entrenamiento: aires aproximados por velocidad, sin cadencia ni tranco."
                    : "Datos de la cincha disponibles (\(r.nivel.lowercased())).", color)
        case "TIEMPO":
            return ("Sincronización", n.contains("BUENA") ? "Los relojes de los equipos van bien sincronizados: los tiempos son fiables."
                    : "Sincronización \(r.nivel.lowercased()): los tiempos pueden tener algún desfase.", color)
        case "INTEGRIDAD":
            return ("Archivo", n.contains("BUENA") ? "El archivo está completo y sin datos dañados."
                    : "El archivo tiene datos dañados o incompletos (\(r.nivel.lowercased())).", color)
        case "CALIBRACION":
            return ("Calibración de sensores", "Sensores sin calibrar en el caballo: las cifras de la cincha son orientativas; velocidad y distancia no se ven afectadas.", color)
        case "ALGORITMO":
            return ("Cálculos del motor", "Umbrales aún sin validar con entrenamientos etiquetados: úsalo como orientación, no como diagnóstico.", color)
        default:
            return (r.dominio.capitalized, r.motivos, color)
        }
    }
}
