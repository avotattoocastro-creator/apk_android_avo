import SwiftUI
import Charts

/// «Trabajo en pista» of one training (AVO Track Work 1.0.0, engine block «trabajo_pista»): breed profile and phase
/// basis, session structure (warm-up / work / cool-down), summary of the series, table of efforts and course passes
/// (sortable; tapping one selects it in the whole app), detail of the selected one (splits, best distances, speed over
/// distance, stride against speed, girth, turning, events), best distances of the session, girth, course and events.
/// Values come only from the engine result: «Sin datos», «Requiere cincha» or «Requiere líneas de salida y meta» otherwise.
struct TrackWorkView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let s = app.selected {
                    if s.isSynthetic {
                        Text("DEMOSTRACIÓN · sesión sintética: los valores no son de un caballo real")
                            .font(.caption.weight(.semibold)).foregroundStyle(Avo.warn)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Avo.warn.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Avo.warn, lineWidth: 1))
                    }
                    if let e = s.engine {
                        if e.trackWork.present {
                            TrackWorkContent(tw: e.trackWork, item: s)
                        } else {
                            AvoCard(title: "Trabajo en pista") {
                                AvoNoData(text: "Este resultado del motor no trae el análisis del trabajo en pista: vuelve a analizar el entrenamiento.")
                                Button("Volver a analizar") { Task { @MainActor in await app.runEngine(s, force: true) } }
                                    .buttonStyle(.avoSecondary)
                            }
                        }
                    } else {
                        AvoCard(title: "Trabajo en pista") {
                            AvoNoData(text: s.engineState.isEmpty ? "Sin análisis del motor" : s.engineState)
                        }
                    }
                } else {
                    AvoCard { AvoNoData(text: "Sin entrenamiento") }
                }
            }
            .padding(20)
        }
        .background(Avo.bg)
        .onAppear { app.trackWork.pageShown() }
    }
}

private struct TrackWorkContent: View {
    @Environment(AppModel.self) private var app
    let tw: TrackWorkResult
    let item: SessionItem

    var body: some View {
        let model: TrackWorkModel = app.trackWork
        // the profile / phase-basis card is gone (trainer's sketch 14/11/2026)
        TrackWorkStructureCard(tw: tw, offset: item.engineOffsetS)
        TrackWorkSummaryTiles(tw: tw)
        TrackWorkEffortsTable(tw: tw, offset: item.engineOffsetS)
        if let sel = model.selected {
            TrackWorkEffortDetail(tw: tw, effort: sel, offset: item.engineOffsetS)
        }
        TrackWorkSessionBestCard(tw: tw)
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) {
                TrackWorkGirthCard(tw: tw).frame(maxWidth: .infinity)
                TrackWorkCourseCard(tw: tw, offset: item.engineOffsetS).frame(maxWidth: .infinity)
            }
            .frame(minWidth: 900)
            VStack(alignment: .leading, spacing: 14) {
                TrackWorkGirthCard(tw: tw)
                TrackWorkCourseCard(tw: tw, offset: item.engineOffsetS)
            }
        }
        TrackWorkEventsCard(tw: tw, events: tw.events, offset: item.engineOffsetS,
                            title: "Eventos de la cincha", subtitle: "EXPERIMENTAL · impactos atípicos, movimientos laterales bruscos, cambios de mano y saturación")
        if !tw.note.isEmpty {
            Text("AVO Track Work \(tw.version) · \(tw.note)")
                .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - header

private struct TrackWorkHeaderCard: View {
    @Environment(AppModel.self) private var app
    let tw: TrackWorkResult
    let item: SessionItem

    var body: some View {
        let model: TrackWorkModel = app.trackWork
        let breedText: String = model.horseBreedText
        let wanted: String = model.horseProfile
        let p: TrackWorkProfile = tw.profile
        AvoCard(title: "Trabajo en pista", subtitle: "AVO Track Work \(tw.version.isEmpty ? "—" : tw.version) · exploratorio, NO VERIFICADO con caballos reales · \(item.horse)") {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    profileBlock(breedText, p).frame(maxWidth: .infinity, alignment: .leading)
                    basisBlock.frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 10) {
                    profileBlock(breedText, p)
                    basisBlock
                }
            }
            if !tw.breed.isEmpty && wanted != tw.breed {
                HStack(spacing: 8) {
                    Label("La ficha del caballo pide el perfil \(wanted), pero este análisis usó \(tw.breed).", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(Avo.warn).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    Button("Volver a analizar") { Task { @MainActor in await app.runEngine(item, force: true) } }
                        .buttonStyle(.avoSecondary)
                }
            }
            if !tw.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(tw.warnings.enumerated()), id: \.offset) { (w: (offset: Int, element: String)) in
                        Label(w.element, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(Avo.warn).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func profileBlock(_ breedText: String, _ p: TrackWorkProfile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PERFIL DE RAZA").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim)
            HStack(spacing: 8) {
                AvoPill(text: tw.breed.isEmpty ? "—" : tw.breed, color: Avo.cyan)
                Text(breedText.trimmed.isEmpty ? "Sin raza en la ficha del caballo (Cuadra)" : breedText)
                    .font(.callout.weight(.semibold)).foregroundStyle(Avo.text).lineLimit(1)
            }
            Text(RacingBreed.profileText(breedText)).font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            Text("Usado: galope de trabajo ≥ \(TrackWorkText.kmh(p.workSpeed, 0)) · rápido ≥ \(TrackWorkText.kmh(p.fastSpeed, 0)) · alta velocidad > \(TrackWorkText.kmh(p.highSpeed, 0)) · zancada de referencia a \(refText(p))")
                .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var basisBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("BASE DE LAS FASES").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim)
            HStack(spacing: 8) {
                AvoPill(text: tw.phaseBasisShort.uppercased(), color: tw.phaseBasis == "MANUAL" ? Avo.warn : (tw.phaseBasis == "LINEAS" ? Avo.ok : Avo.cyan))
                Text("Fases \(tw.phaseBasisText)").font(.callout).foregroundStyle(Avo.text).lineLimit(2)
            }
            Text("Parciales cada \(tw.profile.splitBasisText) · \(tw.hasGirth ? "con cincha (\(tw.girth.scaleText))" : "sin cincha: solo GNSS")")
                .font(.caption).foregroundStyle(Avo.textDim)
            if tw.manualCorrections {
                Text("Zonas corregidas a mano en Análisis (correcciones.json).").font(.caption).foregroundStyle(Avo.cyan)
            }
        }
    }

    private func refText(_ p: TrackWorkProfile) -> String {
        if p.referenceSpeeds.isEmpty { return "—" }
        return p.referenceSpeeds.map { TrackWorkText.kmh($0, 0) }.joined(separator: " y ")
    }
}

// MARK: - session structure

private struct TrackWorkPhaseBar: Identifiable {
    var id: Int
    var row: String
    var x0: Double
    var x1: Double
    var color: Color
}

private struct TrackWorkStructureCard: View {
    let tw: TrackWorkResult
    let offset: Double

    var body: some View {
        let bars: [TrackWorkPhaseBar] = makeBars()
        AvoCard(title: "Estructura de la sesión", subtitle: "Calentamiento hasta el primer trabajo, trabajo hasta el último y vuelta a la calma · minutos del entrenamiento") {
            if bars.isEmpty {
                AvoNoData(text: "Sin fases")
            } else {
                Chart(bars) { (b: TrackWorkPhaseBar) in
                    BarMark(xStart: .value("Inicio", b.x0), xEnd: .value("Fin", b.x1), y: .value("Fila", b.row), height: .fixed(18))
                        .foregroundStyle(b.color)
                        .cornerRadius(3)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 8)) { (v: AxisValue) in
                        AxisGridLine().foregroundStyle(Avo.line)
                        AxisValueLabel {
                            if let d = v.as(Double.self) { Text(AvoFormat.f(d, 0) + " min").font(.caption2).foregroundStyle(Avo.textDim) }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { (v: AxisValue) in
                        AxisValueLabel { if let s = v.as(String.self) { Text(s).font(.caption2).foregroundStyle(Avo.textDim) } }
                    }
                }
                .frame(height: 90)
            }
            // the three phase boxes with the same size, centred (trainer's sketch 14/11/2026: «todos iguales de medida y centrados»)
            HStack(alignment: .top, spacing: 10) {
                phaseBox("Calentamiento", CorrectionsModel.warmupColor, tw.warmup).frame(maxWidth: .infinity, maxHeight: .infinity)
                phaseBox("Trabajo", CorrectionsModel.workColor, tw.work).frame(maxWidth: .infinity, maxHeight: .infinity)
                phaseBox("Vuelta a la calma", CorrectionsModel.cooldownColor, tw.cooldown).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func makeBars() -> [TrackWorkPhaseBar] {
        var out: [TrackWorkPhaseBar] = []
        func add(_ row: String, _ t0: Double, _ t1: Double, _ c: Color) {
            let a: Double = t0 - offset, b: Double = t1 - offset
            guard a.isFinite, b.isFinite, b > a else { return }
            out.append(TrackWorkPhaseBar(id: out.count, row: row, x0: a / 60, x1: b / 60, color: c))
        }
        if tw.warmup.present { add("Fases", tw.warmup.t0, tw.warmup.t1, CorrectionsModel.warmupColor) }
        if tw.work.present { add("Fases", tw.work.t0, tw.work.t1, CorrectionsModel.workColor) }
        if tw.cooldown.present { add("Fases", tw.cooldown.t0, tw.cooldown.t1, CorrectionsModel.cooldownColor) }
        for e in tw.efforts {
            add("Trabajos", e.t0, e.t1, e.kind == "TRABAJO_RAPIDO" ? CorrectionsModel.fastColor : CorrectionsModel.canterColor)
        }
        for p in tw.passes { add("Pasadas", p.t0, p.t1, CorrectionsModel.passColor) }
        return out
    }

    private func phaseBox(_ name: String, _ color: Color, _ p: TrackWorkPhase) -> some View {
        VStack(alignment: .center, spacing: 6) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
                Text(name.uppercased()).font(.caption.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.silver)
            }
            Text(p.present ? TrackWorkText.clock(p.durationS) : "Sin datos").font(.title2.monospacedDigit()).foregroundStyle(Avo.text)
            if p.present {
                Text(TrackWorkText.metres(p.distanceM)).font(.callout.monospacedDigit()).foregroundStyle(Avo.text)
                Text("paso \(TrackWorkText.minutes(p.walkS)) · trote \(TrackWorkText.minutes(p.trotS)) · galope \(TrackWorkText.minutes(p.canterS))"
                     + (p.stoppedS > 0 ? " · parado \(TrackWorkText.minutes(p.stoppedS))" : ""))
                    .font(.caption2.monospacedDigit()).foregroundStyle(Avo.textDim).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Avo.surface2, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - summary tiles

private struct TrackWorkSummaryTiles: View {
    let tw: TrackWorkResult

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
            AvoMetric(label: "Repeticiones", value: String(tw.reps), caption: "Trabajos de galope ≥ \(TrackWorkText.kmh(tw.profile.workSpeed, 0))")
            AvoMetric(label: "Rápidas", value: String(tw.fastReps), caption: "Máxima ≥ \(TrackWorkText.kmh(tw.profile.fastSpeed, 0))")
            if tw.courseDefined {
                AvoMetric(label: "Mejor pasada", value: TrackWorkText.seconds(tw.bestPassOpt),
                          caption: tw.bestPass.map { "\($0.title) · media \(TrackWorkText.kmh($0.speedMeanOpt))" } ?? "Sin pasadas salida → meta")
            } else {
                AvoMetric(label: "Mejor pasada", value: "—", caption: "Requiere líneas de salida y meta")
            }
            AvoMetric(label: "Caída v. máx 1.ª→última", value: TrackWorkText.percent(tw.vmaxDropOpt),
                      caption: tw.fastReps >= 2 ? "Entre la 1.ª y la última rápida" : "Hacen falta 2 repeticiones rápidas")
            if tw.hasGirth {
                AvoMetric(label: "Caída de zancada", value: TrackWorkText.percent(tw.strideDropPct),
                          caption: tw.fastReps >= 2 ? "Longitud a la máxima, 1.ª→última" : "Hacen falta 2 repeticiones rápidas")
            } else {
                AvoMetric(label: "Caída de zancada", value: "—", caption: "Requiere cincha")
            }
            AvoMetric(label: "Recuperación media", value: TrackWorkText.seconds(tw.recoveryMeanOpt, 0), caption: "Hasta volver al paso tras las rápidas")
            AvoMetric(label: "Calentamiento", value: tw.warmup.present ? TrackWorkText.clock(tw.warmup.durationS) : "—",
                      caption: tw.warmupShort ? "CORTO antes del trabajo rápido (ref. 10 min)" : (tw.warmup.present ? "Antes del primer trabajo" : "Sin datos"),
                      accent: tw.warmupShort ? Avo.warn : Avo.text)
            AvoMetric(label: "Vel. máx sesión", value: TrackWorkText.kmh(tw.sessionVmax), caption: "Media de 1 s")
            AvoMetric(label: "Mejor 200 m", value: TrackWorkText.seconds(tw.sessionBest200S), caption: "De todos los trabajos")
            AvoMetric(label: "Galope de trabajo", value: TrackWorkText.metres(tw.distanceWorkM), caption: "Rápido: \(TrackWorkText.metres(tw.distanceFastM))")
        }
    }
}

// MARK: - table of efforts and passes

private struct TrackWorkEffortsTable: View {
    @Environment(AppModel.self) private var app
    let tw: TrackWorkResult
    let offset: Double

    var body: some View {
        let model: TrackWorkModel = app.trackWork
        let rows: [TrackWorkEffort] = model.sorted(tw.allEfforts)
        AvoCard(title: "Trabajos y pasadas", subtitle: "Toca una fila para seleccionarla: el mapa y las gráficas la siguen · toca una cabecera para ordenar") {
            if rows.isEmpty {
                AvoNoData(text: "Sin trabajos detectados (galope ≥ \(TrackWorkText.kmh(tw.profile.workSpeed, 0)) durante ≥ 10 s). Márcalos en Análisis con «Inicio / Fin repetición».")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            Group {
                                head("Tipo", 170, .type); head("Inicio", 64, .start); head("Duración", 72, .duration); head("Distancia", 80, .distance)
                                head("V. máx", 84, .vmax); head("V. media", 84, .mean)
                            }
                            Group {
                                head("Últ. 200", 70, .last200); head("Últ. 400", 70, .last400)
                                head("Caída", 64, .fatigue); head("Recup.", 64, .recovery); head("Mano", 120, .lead)
                            }
                        }
                        .padding(.vertical, 6)
                        Divider().overlay(Avo.line)
                        ForEach(rows, id: \.key) { (e: TrackWorkEffort) in row(e, selected: model.selectedKey == e.key) }
                    }
                }
                .accessibilityIdentifier("trackwork.table")
            }
            if !tw.courseDefined {
                Text("Pasadas salida → meta: requiere líneas de salida y meta (Análisis: «Salida aquí» / «Meta aquí»).")
                    .font(.caption2).foregroundStyle(Avo.textDim)
            }
        }
    }

    private func head(_ t: String, _ w: CGFloat, _ c: TrackWorkSortColumn) -> some View {
        let model: TrackWorkModel = app.trackWork
        let on: Bool = model.sortColumn == c
        return Button {
            model.sort(by: c)
        } label: {
            HStack(spacing: 3) {
                Text(t.uppercased()).font(.caption2.weight(.semibold))
                if on { Image(systemName: model.ascending ? "chevron.up" : "chevron.down").font(.caption2) }
            }
            .foregroundStyle(on ? Avo.text : Avo.textDim)
            .frame(width: w, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func row(_ e: TrackWorkEffort, selected: Bool) -> some View {
        let color: Color = e.isPass ? CorrectionsModel.passColor : (e.kind == "TRABAJO_RAPIDO" ? CorrectionsModel.fastColor : CorrectionsModel.canterColor)
        return Button {
            app.trackWork.select(e)
        } label: {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
                    Text("\(e.id). \(e.kindText)" + (e.manual ? " · a mano" : "")).lineLimit(1)
                }
                .frame(width: 170, alignment: .leading)
                Group {
                    cell(TrackWorkText.clock(e.t0 - offset), 64)
                    cell(TrackWorkText.clock(e.durationOpt), 72)
                    cell(TrackWorkText.metres(e.distanceOpt), 80)
                    cell(TrackWorkText.kmh(e.vmaxOpt), 84)
                    cell(TrackWorkText.kmh(e.speedMeanOpt), 84)
                }
                Group {
                    cell(TrackWorkText.seconds(e.last200Opt), 70)
                    cell(TrackWorkText.seconds(e.last400S), 70)
                    cell(TrackWorkText.percent(e.fatigueOpt, 0), 64)
                    cell(TrackWorkText.seconds(e.recoveryOpt, 0), 64)
                    cell(e.leadText ?? (tw.hasGirth ? "—" : "Sin cincha"), 120)
                }
            }
            .font(.footnote.monospacedDigit()).foregroundStyle(Avo.text)
            .padding(.vertical, 6).padding(.horizontal, 4)
            .background(selected ? Avo.redSoft : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("trackwork.effort.\(e.key)")
    }

    private func cell(_ t: String, _ w: CGFloat) -> some View {
        Text(t).lineLimit(1).minimumScaleFactor(0.8).frame(width: w, alignment: .leading)
    }
}

// MARK: - detail of one effort / pass

private struct TrackWorkSplitBar: Identifiable {
    var id: Int
    var label: String
    var value: Double
    var full: Bool
}

private struct TrackWorkXY: Identifiable {
    var id: Int
    var x: Double
    var y: Double
}

private struct TrackWorkEffortDetail: View {
    @Environment(AppModel.self) private var app
    let tw: TrackWorkResult
    let effort: TrackWorkEffort
    let offset: Double

    var body: some View {
        let e: TrackWorkEffort = effort
        VStack(alignment: .leading, spacing: 14) {
            AvoCard(title: "\(e.title) · \(e.kindText)",
                    subtitle: "\(TrackWorkText.clock(e.t0 - offset)) – \(TrackWorkText.clock(e.t1 - offset))" + (e.manual ? " · límites puestos a mano" : "")) {
                HStack(spacing: 8) {
                    Button { app.trackWork.showOnMap() } label: { Label("Ver en el mapa", systemImage: "map") }.buttonStyle(.avoSecondary)
                    Button { app.trackWork.showOnCharts() } label: { Label("Ver en gráficas", systemImage: "chart.xyaxis.line") }.buttonStyle(.avoSecondary)
                    Spacer(minLength: 8)
                    Button { app.trackWork.clearSelection() } label: { Label("Cerrar", systemImage: "xmark") }.buttonStyle(.avoSecondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                    AvoMetric(label: "Distancia", value: TrackWorkText.metres(e.distanceOpt), caption: "Duración \(TrackWorkText.clock(e.durationOpt))")
                    AvoMetric(label: "V. máx", value: TrackWorkText.kmh(e.vmaxOpt), caption: "A los \(TrackWorkText.seconds(e.tToVmaxS, 1)) del inicio")
                    AvoMetric(label: "V. media", value: TrackWorkText.kmh(e.speedMeanOpt))
                    AvoMetric(label: "> 90 % de la máx", value: TrackWorkText.metres(e.distAbove90M), caption: "Distancia")
                    AvoMetric(label: "Acel. máx", value: e.accelMax.map { AvoFormat.f($0, 2) } ?? "—", unit: e.accelMax == nil ? "" : "m/s²")
                    AvoMetric(label: "Últimos 200 m", value: TrackWorkText.seconds(e.last200Opt), caption: TrackWorkText.kmh(e.speedLast200))
                    AvoMetric(label: "Últimos 400 m", value: TrackWorkText.seconds(e.last400S), caption: TrackWorkText.kmh(e.speedLast400))
                    AvoMetric(label: "Índice de caída", value: TrackWorkText.percent(e.fatigueOpt),
                              caption: e.fatigueOpt == nil ? "Requiere un trabajo ≥ 400 m" : "(máx − últimos 200) / máx")
                    AvoMetric(label: "Recuperación", value: TrackWorkText.seconds(e.recoveryOpt, 0),
                              caption: e.recoveryOpt == nil ? "No volvió al paso antes del final" : "Hasta el paso (5 s)")
                    AvoMetric(label: "Pausa hasta la siguiente", value: TrackWorkText.clock(e.pauseToNextS),
                              caption: e.pauseToNextS == nil ? "Última repetición" : "Media \(TrackWorkText.kmh(e.pauseSpeedMean))")
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    splitsCard.frame(maxWidth: .infinity)
                    bestCard.frame(width: 360)
                }
                .frame(minWidth: 900)
                VStack(alignment: .leading, spacing: 14) {
                    splitsCard
                    bestCard
                }
            }
            speedCard
            strideCard
            girthCard
            TrackWorkEventsCard(tw: tw, events: tw.eventsBetween(e.t0, e.t1 + (e.recoveryOpt ?? 0)), offset: offset,
                                title: "Eventos de \(e.title.lowercased())", subtitle: "EXPERIMENTAL · durante el trabajo y la recuperación")
        }
        .accessibilityIdentifier("trackwork.detail")
    }

    // ---------------------------------------------------------------- splits
    private var splitsCard: some View {
        let m: TrackWorkModel = app.trackWork
        let bySpeed: Binding<Bool> = Binding<Bool>(get: { m.splitsBySpeed }, set: { (v: Bool) in m.splitsBySpeed = v })
        let basis: Double = tw.splitBasisM
        let yLabel: String = m.splitsBySpeed ? "km/h" : "s"
        let bars: [TrackWorkSplitBar] = effort.splits.compactMap { (s: TrackWorkSplit) -> TrackWorkSplitBar? in
            let v: Double? = m.splitsBySpeed ? s.speedKmh : s.timeS
            guard let x = v, x.isFinite else { return nil }
            return TrackWorkSplitBar(id: s.id, label: s.label, value: x, full: s.isFull(basis))
        }
        return AvoCard(title: "Parciales cada \(tw.profile.splitBasisText)", subtitle: "Desde el inicio del trabajo · gris = tramo final más corto (no comparable)") {
            if effort.splits.isEmpty {
                AvoNoData(text: "Sin parciales (trabajo de menos de \(tw.profile.splitBasisText))")
            } else {
                Picker("Ver", selection: bySpeed) {
                    Text("Tiempo (s)").tag(false)
                    Text("Velocidad (km/h)").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
                Chart(bars) { (b: TrackWorkSplitBar) in
                    BarMark(x: .value("Tramo", b.label), y: .value(yLabel, b.value))
                        .foregroundStyle(b.full ? Avo.cyan : Avo.unknown)
                        .cornerRadius(2)
                        .annotation(position: .top) {
                            Text(AvoFormat.f(b.value, m.splitsBySpeed ? 1 : 2)).font(.caption2).foregroundStyle(Avo.textDim)
                        }
                }
                .chartXAxis {
                    AxisMarks { (v: AxisValue) in
                        AxisValueLabel { if let s = v.as(String.self) { Text(s).font(.caption2).foregroundStyle(Avo.textDim) } }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { (v: AxisValue) in
                        AxisGridLine().foregroundStyle(Avo.line)
                        AxisValueLabel { if let d = v.as(Double.self) { Text(AvoFormat.f(d, 0)).font(.caption2).foregroundStyle(Avo.textDim) } }
                    }
                }
                .frame(height: 190)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) { h("Tramo (m)", 110); h("Tiempo", 80); h("Acumulado", 90); h("km/h", 80) }
                        .padding(.vertical, 4)
                    Divider().overlay(Avo.line)
                    ForEach(effort.splits) { (s: TrackWorkSplit) in
                        HStack(spacing: 8) {
                            c(s.label + (s.isFull(basis) ? "" : " (parcial)"), 110)
                            c(TrackWorkText.seconds(s.timeS), 80)
                            c(TrackWorkText.seconds(s.cumulativeS), 90)
                            c(s.speedKmh.map { AvoFormat.f($0, 1) } ?? "—", 80)
                        }
                        .font(.footnote.monospacedDigit()).foregroundStyle(s.isFull(basis) ? Avo.text : Avo.textDim)
                        .padding(.vertical, 3)
                    }
                }
            }
        }
    }

    private var bestCard: some View {
        AvoCard(title: "Mejores distancias", subtitle: "Dentro de este trabajo") {
            if effort.best.isEmpty {
                AvoNoData(text: "Sin datos (trabajo de menos de 200 m)")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) { h("Distancia", 80); h("Tiempo", 80); h("km/h", 64); h("Desde", 64) }.padding(.vertical, 4)
                    Divider().overlay(Avo.line)
                    ForEach(effort.best) { (b: TrackWorkBest) in
                        HStack(spacing: 8) {
                            c(TrackWorkText.metres(b.distanceM), 80)
                            c(TrackWorkText.seconds(b.timeS), 80)
                            c(b.speedKmh.map { AvoFormat.f($0, 1) } ?? "—", 64)
                            c(TrackWorkText.clock(b.t0.map { $0 - offset }), 64)
                        }
                        .font(.footnote.monospacedDigit()).foregroundStyle(Avo.text)
                        .padding(.vertical, 3)
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- speed over distance
    private var speedCard: some View {
        let curve: [TrackWorkCurvePoint] = app.trackWork.speedCurve(effort)
        let vmaxK: Double? = effort.vmaxOpt.map { $0 * 3.6 }
        let maxD: Double = max(curve.last?.distanceM ?? 0, 1)
        return AvoCard(title: "Velocidad a lo largo del trabajo",
                       subtitle: "km/h frente a metros desde el inicio · línea: máxima · franja: ≥ 90 % de la máxima (\(TrackWorkText.metres(effort.distAbove90M)))") {
            if curve.count < 2 {
                AvoNoData(text: "Sin serie de velocidad del motor para este trabajo")
            } else {
                Chart {
                    if let v = vmaxK {
                        RectangleMark(xStart: .value("Desde", 0.0), xEnd: .value("Hasta", maxD),
                                      yStart: .value("90 %", v * 0.9), yEnd: .value("Máx", v))
                            .foregroundStyle(Avo.red.opacity(0.12))
                        RuleMark(y: .value("V. máx", v))
                            .foregroundStyle(Avo.red)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .annotation(position: .top, alignment: .leading) {
                                Text("máx " + AvoFormat.f(v, 1) + " km/h").font(.caption2).foregroundStyle(Avo.redLight)
                            }
                    }
                    ForEach(curve) { (p: TrackWorkCurvePoint) in
                        LineMark(x: .value("Distancia", p.distanceM), y: .value("Velocidad", p.speedKmh))
                            .foregroundStyle(Avo.cyan)
                            .interpolationMethod(.monotone)
                    }
                }
                .chartXScale(domain: 0...maxD)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 8)) { (v: AxisValue) in
                        AxisGridLine().foregroundStyle(Avo.line)
                        AxisValueLabel { if let d = v.as(Double.self) { Text(AvoFormat.f(d, 0) + " m").font(.caption2).foregroundStyle(Avo.textDim) } }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { (v: AxisValue) in
                        AxisGridLine().foregroundStyle(Avo.line)
                        AxisValueLabel { if let d = v.as(Double.self) { Text(AvoFormat.f(d, 0)).font(.caption2).foregroundStyle(Avo.textDim) } }
                    }
                }
                .frame(height: 220)
            }
        }
    }

    // ---------------------------------------------------------------- stride against speed
    private var strideCard: some View {
        let strides: [TrackWorkStride] = tw.strides.within(effort.t0, effort.t1)
        return AvoCard(title: "Zancada frente a velocidad",
                       subtitle: "Cada punto es una zancada de galope · recta ajustada · en rojo, los valores a las velocidades de referencia del perfil \(tw.breed)") {
            if !tw.hasGirth {
                AvoNoData(text: "Requiere cincha")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    AvoMetric(label: "Zancadas", value: String(effort.strideCount))
                    AvoMetric(label: "Frecuencia a la máx", value: TrackWorkText.hertz(effort.freqAtVmaxHz), caption: "Máxima (p95) \(TrackWorkText.hertz(effort.freqMaxHz))")
                    AvoMetric(label: "Longitud a la máx", value: TrackWorkText.metres(effort.lengthAtVmaxM, 2), caption: "Máxima (p95) \(TrackWorkText.metres(effort.lengthMaxM, 2))")
                    ForEach(effort.references) { (r: TrackWorkStrideReference) in
                        AvoMetric(label: "A \(TrackWorkText.kmh(r.speed, 0))", value: TrackWorkText.hertz(r.freqHz),
                                  caption: r.freqHz == nil && r.lengthM == nil ? "Fuera del rango medido" : "Longitud \(TrackWorkText.metres(r.lengthM, 2))",
                                  accent: Avo.redLight)
                    }
                }
                if strides.isEmpty {
                    AvoNoData(text: "Sin zancadas de galope en este trabajo")
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            strideChart(strides, freq: true).frame(maxWidth: .infinity)
                            strideChart(strides, freq: false).frame(maxWidth: .infinity)
                        }
                        .frame(minWidth: 760)
                        VStack(spacing: 12) {
                            strideChart(strides, freq: true)
                            strideChart(strides, freq: false)
                        }
                    }
                }
            }
        }
    }

    private func strideChart(_ strides: [TrackWorkStride], freq: Bool) -> some View {
        var pts: [TrackWorkXY] = []
        for (i, s) in strides.enumerated() {
            guard let v = s.speed, v.isFinite else { continue }
            let y: Double? = freq ? s.freqHz : s.lengthM
            guard let yy = y, yy.isFinite else { continue }
            pts.append(TrackWorkXY(id: i, x: v * 3.6, y: yy))
        }
        var refs: [TrackWorkXY] = []
        for (i, r) in effort.references.enumerated() {
            guard let v = r.speed else { continue }
            let y: Double? = freq ? r.freqHz : r.lengthM
            guard let yy = y, yy.isFinite else { continue }
            refs.append(TrackWorkXY(id: i, x: v * 3.6, y: yy))
        }
        let xs: [Double] = pts.map { $0.x } + refs.map { $0.x }
        let lo: Double = (xs.min() ?? 0) - 2
        let hi: Double = max((xs.max() ?? 1) + 2, lo + 1)
        var fit: [TrackWorkXY] = []
        let a: Double? = freq ? effort.freqFitA : effort.lengthFitA
        let b: Double? = freq ? effort.freqFitB : effort.lengthFitB
        if let aa = a, let bb = b, aa.isFinite, bb.isFinite, let x0 = pts.map({ $0.x }).min(), let x1 = pts.map({ $0.x }).max(), x1 > x0 {
            fit = [TrackWorkXY(id: 0, x: x0, y: aa + bb * x0 / 3.6), TrackWorkXY(id: 1, x: x1, y: aa + bb * x1 / 3.6)]
        }
        let unit: String = freq ? "Hz" : "m"
        return VStack(alignment: .leading, spacing: 4) {
            Text(freq ? "FRECUENCIA (Hz)" : "LONGITUD (m)").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim)
            if pts.isEmpty {
                AvoNoData(text: freq ? "Sin frecuencia de zancada" : "Sin longitud (fuera del rango plausible o sin GNSS)")
            } else {
                Chart {
                    ForEach(pts) { (p: TrackWorkXY) in
                        PointMark(x: .value("Velocidad", p.x), y: .value(unit, p.y))
                            .foregroundStyle(Avo.cyan.opacity(0.55))
                            .symbolSize(16)
                    }
                    ForEach(fit) { (p: TrackWorkXY) in
                        LineMark(x: .value("Velocidad", p.x), y: .value(unit, p.y))
                            .foregroundStyle(Avo.silver)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    }
                    ForEach(refs) { (p: TrackWorkXY) in
                        RuleMark(x: .value("Referencia", p.x))
                            .foregroundStyle(Avo.red.opacity(0.35))
                        PointMark(x: .value("Velocidad", p.x), y: .value(unit, p.y))
                            .foregroundStyle(Avo.red)
                            .symbolSize(110)
                            .annotation(position: .top) {
                                Text(AvoFormat.f(p.y, 2) + " " + unit).font(.caption2.weight(.semibold)).foregroundStyle(Avo.redLight)
                            }
                    }
                }
                .chartXScale(domain: lo...hi)
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { (v: AxisValue) in
                        AxisGridLine().foregroundStyle(Avo.line)
                        AxisValueLabel { if let d = v.as(Double.self) { Text(AvoFormat.f(d, 0) + " km/h").font(.caption2).foregroundStyle(Avo.textDim) } }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { (v: AxisValue) in
                        AxisGridLine().foregroundStyle(Avo.line)
                        AxisValueLabel { if let d = v.as(Double.self) { Text(AvoFormat.f(d, freq ? 2 : 1)).font(.caption2).foregroundStyle(Avo.textDim) } }
                    }
                }
                .frame(height: 200)
            }
        }
    }

    // ---------------------------------------------------------------- girth and turning of this effort
    private var girthCard: some View {
        let strides: [TrackWorkStride] = tw.strides.within(effort.t0, effort.t1)
        var leftS: Double = 0, rightS: Double = 0
        var vedba: [Double] = []
        var disp: [Double] = []
        var peak: [Double] = []
        for s in strides {
            let d: Double = s.t1 - s.t0
            if let y = s.yawDegS, y.isFinite {
                if y >= 4 { leftS += d } else if y <= -4 { rightS += d }
            }
            if let v = s.vedbaG, v.isFinite { vedba.append(v) }
            if let v = s.vertDispM, v.isFinite { disp.append(v) }
            if let v = s.vertPeakG, v.isFinite { peak.append(v) }
        }
        let vedbaMean: Double? = vedba.isEmpty ? nil : vedba.reduce(0, +) / Double(vedba.count)
        let dispMedian: Double? = TrackWorkEffortDetail.median(disp)
        let peakMedian: Double? = TrackWorkEffortDetail.median(peak)
        return AvoCard(title: "Cincha y giros en este trabajo", subtitle: "Calculado con las zancadas del trabajo · mano: EXPERIMENTAL") {
            if !tw.hasGirth {
                AvoNoData(text: "Requiere cincha")
            } else if strides.isEmpty {
                AvoNoData(text: "Sin zancadas de galope en este trabajo")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                    AvoMetric(label: "VeDBA medio", value: TrackWorkText.g(vedbaMean), caption: "Galope de la sesión \(TrackWorkText.g(tw.girth.vedbaGallopG))")
                    AvoMetric(label: "Girando a la izquierda", value: TrackWorkText.seconds(leftS, 1), caption: "Zancadas con giro ≥ 4 °/s")
                    AvoMetric(label: "Girando a la derecha", value: TrackWorkText.seconds(rightS, 1), caption: "Zancadas con giro ≤ −4 °/s")
                    AvoMetric(label: "Mano", value: effort.leadText ?? "—", caption: "Zancadas izq./dcha. · cambios")
                    AvoMetric(label: "Desplaz. vertical", value: TrackWorkText.metres(dispMedian, 3), caption: "Mediana pico a pico del tronco")
                    AvoMetric(label: "Pico vertical", value: TrackWorkText.g(peakMedian), caption: "Mediana por zancada")
                }
            }
        }
    }

    static func median(_ v: [Double]) -> Double? {
        if v.isEmpty { return nil }
        let s: [Double] = v.sorted()
        let n: Int = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    private func h(_ t: String, _ w: CGFloat) -> some View {
        Text(t.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(Avo.textDim).frame(width: w, alignment: .leading)
    }

    private func c(_ t: String, _ w: CGFloat) -> some View {
        Text(t).lineLimit(1).minimumScaleFactor(0.8).frame(width: w, alignment: .leading)
    }
}

// MARK: - best distances of the session

private struct TrackWorkSessionBestCard: View {
    @Environment(AppModel.self) private var app
    let tw: TrackWorkResult

    var body: some View {
        let best: [TrackWorkBest] = tw.sessionBest
        AvoCard(title: "Mejores distancias de la sesión", subtitle: "Mejor tiempo en 200, 400, 600, 800, 1000, 1200 y 1600 m de todos los trabajos y pasadas · toca una fila para ver su trabajo") {
            if best.isEmpty {
                AvoNoData()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) { h("Distancia", 90); h("Tiempo", 90); h("km/h", 70); h("Trabajo", 160) }.padding(.vertical, 4)
                        Divider().overlay(Avo.line)
                        ForEach(best) { (b: TrackWorkBest) in
                            Button {
                                if let e = tw.effort(b.effortKey) { app.trackWork.select(e) }
                            } label: {
                                HStack(spacing: 8) {
                                    c(TrackWorkText.metres(b.distanceM), 90)
                                    c(TrackWorkText.seconds(b.timeS), 90)
                                    c(b.speedKmh.map { AvoFormat.f($0, 1) } ?? "—", 70)
                                    c(b.effortTitle, 160)
                                }
                                .font(.footnote.monospacedDigit()).foregroundStyle(Avo.text)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("trackwork.best")
    }

    private func h(_ t: String, _ w: CGFloat) -> some View {
        Text(t.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(Avo.textDim).frame(width: w, alignment: .leading)
    }

    private func c(_ t: String, _ w: CGFloat) -> some View {
        Text(t).lineLimit(1).frame(width: w, alignment: .leading)
    }
}

// MARK: - girth of the session

private struct TrackWorkGirthCard: View {
    let tw: TrackWorkResult

    var body: some View {
        let g: TrackWorkGirth = tw.girth
        AvoCard(title: "Cincha de la sesión", subtitle: "VeDBA (aceleración dinámica), giros por mano, zancadas y mano de galope (EXPERIMENTAL)") {
            if !g.available {
                AvoNoData(text: "Requiere cincha")
            } else {
                Group {
                ShellKeyValue(key: "VeDBA medio en movimiento", value: TrackWorkText.g(g.vedbaMeanG))
                ShellKeyValue(key: "VeDBA paso · trote · galope", value: "\(TrackWorkText.g(g.vedbaWalkG)) · \(TrackWorkText.g(g.vedbaTrotG)) · \(TrackWorkText.g(g.vedbaGallopG))")
                ShellKeyValue(key: "Carga VeDBA", value: g.vedbaLoadGmin.map { AvoFormat.f($0, 2) + " g·min" } ?? "—")
                ShellKeyValue(key: "Girando a la izquierda", value: "\(TrackWorkText.seconds(g.turns.leftS, 0)) · \(g.turns.leftDeg.map { AvoFormat.f($0, 0) + "°" } ?? "—")")
                ShellKeyValue(key: "Girando a la derecha", value: "\(TrackWorkText.seconds(g.turns.rightS, 0)) · \(g.turns.rightDeg.map { AvoFormat.f($0, 0) + "°" } ?? "—")")
                ShellKeyValue(key: "Galope: izquierda / derecha", value: "\(TrackWorkText.seconds(g.turnsGallop.leftS, 0)) / \(TrackWorkText.seconds(g.turnsGallop.rightS, 0))")
                ShellKeyValue(key: "Equilibrio (izq − dcha) / total", value: g.turns.balance.map { AvoFormat.f($0, 2) } ?? "—")
                ShellKeyValue(key: "Zancadas de galope", value: "\(tw.strides.count) · \(TrackWorkText.hertz(tw.strides.freqMedianHz)) · \(TrackWorkText.metres(tw.strides.lengthMedianM, 2))")
                ShellKeyValue(key: "Desplazamiento vertical (mediana)", value: TrackWorkText.metres(tw.strides.vertDispMedianM, 3))
                }
                Divider().overlay(Avo.line)
                HStack(spacing: 6) {
                    Text("MANO DE GALOPE").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim)
                    AvoPill(text: "EXPERIMENTAL", color: Avo.warn)
                }
                Group {
                ShellKeyValue(key: "Calibración", value: tw.lead.calibrationText + (tw.lead.curveAgreement.map { " · acuerdo " + AvoFormat.f($0 * 100, 0) + " %" } ?? ""))
                ShellKeyValue(key: "Zancadas izquierda / derecha", value: "\(tw.lead.leftStrides) / \(tw.lead.rightStrides)")
                ShellKeyValue(key: "Cambios de mano", value: String(tw.lead.changes))
                ShellKeyValue(key: "Mano de fuera en curva", value: TrackWorkText.percent(tw.lead.outsideInCurvePct, 0))
                }
                Divider().overlay(Avo.line)
                Group {
                ShellKeyValue(key: "Escala", value: g.scaleText)
                ShellKeyValue(key: "Calidad de la vertical", value: g.verticalQuality.map { AvoFormat.f($0, 2) } ?? "—")
                ShellKeyValue(key: "Muestras saturadas (±8 g)", value: String(g.saturatedSamples))
                }
            }
        }
    }
}

// MARK: - course (start / finish lines)

private struct TrackWorkCourseCard: View {
    let tw: TrackWorkResult
    let offset: Double

    var body: some View {
        AvoCard(title: "Recorrido", subtitle: "Pasadas de la línea de salida a la de meta (p. ej. Playa del Regatón, Laredo)") {
            if !tw.courseDefined {
                AvoNoData(text: "Requiere líneas de salida y meta")
                Text("Márcalas en Análisis («Salida aquí» / «Meta aquí») o en «Geocercas y líneas». Sin líneas, el motor detecta los trabajos por la velocidad.")
                    .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            } else {
                ShellKeyValue(key: "Nombre", value: tw.courseName.isEmpty ? "—" : tw.courseName)
                ShellKeyValue(key: "Salida → meta (línea recta)", value: TrackWorkText.metres(tw.gateDistanceM))
                ShellKeyValue(key: "Pasadas", value: String(tw.passes.count))
                ShellKeyValue(key: "Mejor pasada", value: TrackWorkText.seconds(tw.bestPassOpt) + (tw.bestPass.map { " · " + TrackWorkText.kmh($0.speedMeanOpt) } ?? ""))
                ShellKeyValue(key: "Dentro de la geocerca", value: tw.insideFencePct.map { AvoFormat.f($0, 1) + " %" } ?? "Sin geocerca")
                if let p = tw.insideFencePct, p < 95 {
                    Label("Menos del 95 % de la sesión dentro de la geocerca", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(Avo.warn)
                }
                ShellKeyValue(key: "Cruces que cuentan / ignorados", value: "\(tw.crossings.count - tw.ignoredCrossings) / \(tw.ignoredCrossings)")
                if tw.ignoredCrossings > 0 {
                    Text("Ignorados: cruces en sentido contrario (p. ej. el calentamiento hacia el otro lado).")
                        .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(tw.crossings) { (c: TrackWorkCrossing) in
                    HStack(spacing: 8) {
                        Text(TrackWorkText.clock(c.t.map { $0 - offset })).frame(width: 60, alignment: .leading)
                        Text(c.line).frame(width: 100, alignment: .leading)
                        Text(c.direction == "IZQ_A_DCHA" ? "izq. → dcha." : "dcha. → izq.").frame(width: 100, alignment: .leading)
                        Text(c.counts ? "cuenta" : "ignorado").foregroundStyle(c.counts ? Avo.ok : Avo.textDim)
                    }
                    .font(.caption.monospacedDigit()).foregroundStyle(Avo.text)
                }
            }
        }
    }
}

// MARK: - events

private struct TrackWorkEventsCard: View {
    let tw: TrackWorkResult
    let events: [TrackWorkEvent]
    let offset: Double
    let title: String
    let subtitle: String

    var body: some View {
        AvoCard(title: title, subtitle: subtitle) {
            if !tw.hasGirth {
                AvoNoData(text: "Requiere cincha")
            } else if events.isEmpty {
                AvoNoData(text: "Sin eventos")
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(events) { (e: TrackWorkEvent) in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(TrackWorkText.clock(e.t.map { $0 - offset })).frame(width: 60, alignment: .leading)
                            Text(e.typeText).fontWeight(.semibold)
                                .foregroundStyle(e.type == "IMPACTO_ATIPICO" || e.type == "MOVIMIENTO_LATERAL_BRUSCO" ? Avo.warn : Avo.text)
                                .frame(width: 200, alignment: .leading)
                            Text(e.valueText).frame(width: 90, alignment: .leading)
                            Text(e.detail).foregroundStyle(Avo.textDim).lineLimit(2)
                        }
                        .font(.caption.monospacedDigit()).foregroundStyle(Avo.text)
                    }
                }
            }
        }
    }
}
