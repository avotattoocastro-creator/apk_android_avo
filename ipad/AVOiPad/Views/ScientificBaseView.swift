import SwiftUI

/// «Base científica» (KB-1) del motor: lo que el motor ya calcula con la literatura sobre PSI y árabe de carreras
/// (equine-intelligence/docs/algoritmos/14_BASE_CIENTIFICA.md). Dos tarjetas:
///  · KbSessionCard, dentro de Trabajo en pista: metros por banda B1/B2/B3 con sus límites en m/s, canter y galope
///    rápido (Verheyen 2006), fatiga ósea (validado y extrapolado lento) y velocidad de los últimos 600 m de cada trabajo;
///  · KbHistoryCard, en la historia del caballo: ventanas de 7, 30 y 60 días, días sin trabajo rápido, vuelta tras
///    descanso, cociente de galope, ratio de fatiga ósea semanal y reglas activas con su nivel, acción y evidencia.
/// Solo valores del motor: un campo null se enseña como «sin datos». Orientativo, sin validar con la cuadra.

// MARK: - por sesión

struct KbSessionCard: View {
    let tw: TrackWorkResult

    var body: some View {
        let kb: KbSessionBlock = tw.scientificBase
        AvoCard(title: "Base científica",
                subtitle: "Carga de la sesión según la literatura (KB-1\(kb.version.isEmpty ? "" : " " + kb.version)) · orientativo, sin validar con la cuadra") {
            if !kb.present {
                AvoNoData(text: "Sin datos: este análisis no trae la base científica; vuelve a analizar el entrenamiento.")
            } else {
                header(kb)
                Divider().overlay(Avo.line)
                bandsBlock(kb)
                Divider().overlay(Avo.line)
                verheyenBlock(kb)
                Divider().overlay(Avo.line)
                boneBlock(kb)
                Divider().overlay(Avo.line)
                finalSpeedBlock
            }
        }
        .accessibilityIdentifier("trackwork.kb")
    }

    private func header(_ kb: KbSessionBlock) -> some View {
        HStack(spacing: 8) {
            AvoPill(text: tw.breed.isEmpty ? "—" : tw.breed, color: Avo.cyan)
            Text("Ritmo de carrera \(KbText.ms(kb.racePace))").font(.callout.weight(.semibold)).foregroundStyle(Avo.text)
            Text("· \(kb.racePaceOriginText)").font(.caption).foregroundStyle(Avo.textDim)
            Spacer(minLength: 0)
        }
    }

    // ---------------------------------------------------------------- bandas
    private func bandsBlock(_ kb: KbSessionBlock) -> some View {
        let total: Double = kb.bands.compactMap { $0.distanceM }.reduce(0, +)
        let colors: [Color] = [Avo.blue, Avo.warn, Avo.red]
        return VStack(alignment: .leading, spacing: 6) {
            KbSectionTitle(text: "Metros por banda de velocidad")
            if total > 0 {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(kb.bands) { (b: KbBand) in
                            let f: Double = (b.distanceM ?? 0) / total
                            if f > 0 {
                                Rectangle().fill(colors[min(b.id, colors.count - 1)])
                                    .frame(width: max(2, (geo.size.width - 4) * f))
                            }
                        }
                    }
                }
                .frame(height: 10)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            HStack(spacing: 8) { KbHead(text: "Banda", width: 130); KbHead(text: "Límites", width: 130); KbHead(text: "Distancia", width: 90); KbHead(text: "Tiempo", width: 80) }
            ForEach(kb.bands) { (b: KbBand) in
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Circle().fill(colors[min(b.id, colors.count - 1)]).frame(width: 8, height: 8)
                        Text(b.name)
                    }
                    .frame(width: 130, alignment: .leading)
                    KbCell(text: b.limitsText, width: 130)
                    KbCell(text: KbText.metres(b.distanceM), width: 90)
                    KbCell(text: b.timeS.map { TrackWorkText.seconds($0, 0) } ?? KbText.noData, width: 80)
                }
                .font(.footnote.monospacedDigit()).foregroundStyle(Avo.text)
            }
            if !kb.hasRacePace {
                Text("Sin ritmo de carrera de referencia (perfil sin raza de carreras): todo el trabajo cuenta en B1 y no hay límites de B2 y B3.")
                    .font(.caption).foregroundStyle(Avo.warn).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("B1 desde el galope de trabajo hasta el 80 % del ritmo de carrera · B2 del 80 al 93 % · B3 desde el 93 %.")
                    .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // ---------------------------------------------------------------- Verheyen
    private func verheyenBlock(_ kb: KbSessionBlock) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            KbSectionTitle(text: "Canter y galope rápido (Verheyen 2006)")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
                AvoMetric(label: "Canter", value: KbText.metres(kb.canterM),
                          caption: "Entre \(KbText.ms(kb.canterMinSpeed)) y \(KbText.ms(kb.gallopCut))")
                AvoMetric(label: "Galope rápido", value: KbText.metres(kb.gallopM), caption: "Por encima de \(KbText.ms(kb.gallopCut))",
                          accent: (kb.gallopM ?? 0) > 0 ? Avo.red : Avo.text)
            }
            Text("Se suman en la historia: más de 44 km de canter o de 6 km de galope rápido en 30 días son umbrales de la literatura (reglas A1 y A2).")
                .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
        }
    }

    // ---------------------------------------------------------------- fatiga ósea
    private func boneBlock(_ kb: KbSessionBlock) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                KbSectionTitle(text: "Fatiga ósea por zancada (Morrice-West 2022)")
                if kb.calibrated == false { AvoPill(text: "SIN CALIBRAR", color: Avo.warn) }
                Spacer(minLength: 0)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
                AvoMetric(label: "Fatiga ósea", value: KbText.percent(kb.bonePct),
                          caption: "Desde \(KbText.ms(kb.boneValidMinSpeed, 2)) · \(kb.strides.map { AvoFormat.f($0, 0) + " zancadas estimadas" } ?? KbText.noData)")
                AvoMetric(label: "Extrapolado lento", value: KbText.percent(kb.boneLowPct),
                          caption: "4–\(kb.boneValidMinSpeed.map { AvoFormat.f($0, 2) } ?? "12,57") m/s, aparte: el modelo sobrestima el trabajo lento · \(kb.stridesLow.map { AvoFormat.f($0, 0) + " zancadas" } ?? KbText.noData)",
                          accent: Avo.textDim)
            }
            Text(KbText.boneDisclaimer).font(.footnote.weight(.semibold)).foregroundStyle(Avo.text)
            if kb.calibrated == false {
                Text(KbText.uncalibrated + " Compara al caballo consigo mismo, no con otros.")
                    .font(.caption).foregroundStyle(Avo.warn).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // ---------------------------------------------------------------- últimos 600 m
    private var finalSpeedBlock: some View {
        let list: [TrackWorkEffort] = tw.allEfforts
        return VStack(alignment: .leading, spacing: 6) {
            KbSectionTitle(text: "Velocidad de los últimos 600 m de cada trabajo (Schrurs 2024)")
            if list.isEmpty {
                Text(KbText.noData + ": sin trabajos de galope en la sesión.").font(.footnote).foregroundStyle(Avo.textDim)
            } else {
                HStack(spacing: 8) { KbHead(text: "Trabajo", width: 170); KbHead(text: "Distancia", width: 90); KbHead(text: "Últimos 600 m", width: 110); KbHead(text: "Tiempo", width: 80) }
                ForEach(list) { (e: TrackWorkEffort) in
                    HStack(spacing: 8) {
                        KbCell(text: "\(e.title) · \(e.kindText)", width: 170)
                        KbCell(text: KbText.metres(e.distanceOpt), width: 90)
                        KbCell(text: KbText.ms(e.speedLast600, 2), width: 110)
                        KbCell(text: e.last600S.map { TrackWorkText.seconds($0, 1) } ?? KbText.noData, width: 80)
                    }
                    .font(.footnote.monospacedDigit()).foregroundStyle(Avo.text)
                }
                Text("«sin datos» cuando el trabajo mide menos de 600 m. En la historia, la regla A8 compara esta velocidad con la línea base del caballo.")
                    .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - historia

struct KbHistoryCard: View {
    let status: KbHistoryStatus
    let sessions: [TrainingSessionResult]
    var referenceDate: String = ""

    var body: some View {
        AvoCard(title: "Base científica",
                subtitle: "Carga acumulada y reglas de la literatura (KB-1\(status.version.isEmpty ? "" : " " + status.version))\(referenceDate.isEmpty ? "" : " a " + referenceDate) · orientativo, sin validar con la cuadra") {
            if !status.present || !status.hasContent {
                AvoNoData(text: "Sin datos: ninguna sesión trae el trabajo en pista con la base científica (perfil PSI o árabe y motor actual). Vuelve a analizar las sesiones.")
            } else {
                if status.available {
                    windowsTable
                    Divider().overlay(Avo.line)
                    tiles
                    Divider().overlay(Avo.line)
                }
                rulesBlock
                if uncalibrated {
                    Text(KbText.uncalibrated).font(.caption).foregroundStyle(Avo.warn).fixedSize(horizontal: false, vertical: true)
                }
                if !status.note.isEmpty {
                    Text(KbText.sentence(status.note))
                        .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                }
                if !sessionRows.isEmpty {
                    Divider().overlay(Avo.line)
                    sessionsTable
                }
            }
        }
        .accessibilityIdentifier("history.kb")
    }

    private var uncalibrated: Bool {
        sessions.contains { $0.resumen?.trabajoPista?.raza == "ARABE" }
    }

    // ---------------------------------------------------------------- ventanas
    private var windowsTable: some View {
        let cols: [(String, KbWindow)] = [("7 días", status.d7), ("30 días", status.d30), ("30 días anteriores", status.prev30), ("60 días", status.d60)]
        let w0: CGFloat = 150, w: CGFloat = 120
        return VStack(alignment: .leading, spacing: 4) {
            KbSectionTitle(text: "Ventanas de la historia")
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        KbHead(text: "", width: w0)
                        ForEach(Array(cols.enumerated()), id: \.offset) { (c: (offset: Int, element: (String, KbWindow))) in KbHead(text: c.element.0, width: w) }
                    }
                    row("B1 · trabajo", w0, w, cols.map { KbText.distance($0.1.present ? $0.1.bandsM[0] : nil) })
                    row("B2 · intermedia", w0, w, cols.map { KbText.distance($0.1.present ? $0.1.bandsM[1] : nil) })
                    row("B3 · alta", w0, w, cols.map { KbText.distance($0.1.present ? $0.1.bandsM[2] : nil) })
                    row("Canter", w0, w, cols.map { KbText.distance($0.1.present ? $0.1.canterM : nil) })
                    row("Galope rápido", w0, w, cols.map { KbText.distance($0.1.present ? $0.1.gallopM : nil) })
                    row("Fatiga ósea", w0, w, cols.map { KbText.percent($0.1.present ? $0.1.bonePct : nil) })
                    row("Sesiones", w0, w, cols.map { (c: (String, KbWindow)) -> String in
                        guard c.1.present else { return KbText.noData }
                        return c.1.sessionsWithoutData > 0 ? "\(c.1.sessions) (+\(c.1.sessionsWithoutData) sin datos)" : "\(c.1.sessions)"
                    })
                }
            }
        }
    }

    private func row(_ name: String, _ w0: CGFloat, _ w: CGFloat, _ values: [String]) -> some View {
        HStack(spacing: 8) {
            Text(name).foregroundStyle(Avo.textDim).frame(width: w0, alignment: .leading)
            ForEach(Array(values.enumerated()), id: \.offset) { (v: (offset: Int, element: String)) in
                KbCell(text: v.element, width: w)
            }
        }
        .font(.footnote.monospacedDigit()).foregroundStyle(Avo.text)
    }

    // ---------------------------------------------------------------- indicadores
    private var tiles: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
            AvoMetric(label: "Días sin trabajo rápido", value: status.daysWithoutFastWork.map { String($0) } ?? KbText.noData,
                      caption: status.daysWithoutFastWork == nil ? "Ninguna sesión rápida en la historia" : "Desde la última sesión rápida")
            AvoMetric(label: "Vuelta tras descanso",
                      value: status.returnDay.map { "Día \($0)" } ?? "No",
                      caption: status.returnRestDays.map { "Tras \($0) días sin trabajo rápido (A5/A6)" } ?? "Sin vuelta en curso (≥ 60 días sin rápido)",
                      accent: status.returnDay != nil ? Avo.warn : Avo.text)
            AvoMetric(label: "Cociente de galope", value: KbText.ratio(status.gallopRatio),
                      caption: status.gallopRatio == nil ? "Hacen falta 90 días de historia hasta el último rápido"
                          : "\(status.gallopRatioDays60.map { String($0) } ?? "—") días en 60 d / \(status.gallopRatioDays90.map { String($0) } ?? "—") en 90 d + 1 · aviso ≤ 1,6",
                      accent: (status.gallopRatio ?? 2) <= 1.6 ? Avo.warn : Avo.text)
            AvoMetric(label: "Días de galope en 60 d", value: status.gallopDays60d.map { String($0) } ?? KbText.noData,
                      caption: "Días con sesión rápida · aviso con 2 o menos (A6B)")
            AvoMetric(label: "Fatiga ósea 7 d / semana habitual", value: KbText.ratio(status.boneRatio7d),
                      caption: status.boneWeeklyMedianPct.map { "Mediana semanal \(KbText.percent($0)) · aviso > 1,5" } ?? "Hacen falta 4 semanas de historia",
                      accent: (status.boneRatio7d ?? 0) > 1.5 ? Avo.warn : Avo.text)
        }
    }

    // ---------------------------------------------------------------- reglas
    private var rulesBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                KbSectionTitle(text: "Reglas")
                Text(status.rules.isEmpty ? "ninguna activa" : "\(status.rules.count) activa\(status.rules.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(status.rules.isEmpty ? Avo.ok : Avo.warn)
                Spacer(minLength: 0)
            }
            ForEach(status.rules) { (r: KbRule) in
                KbRuleRow(rule: r)
            }
            let inactive: [String] = KbRule.catalogue.filter { status.rule($0) == nil }
            if !inactive.isEmpty {
                Text("Sin aviso: " + inactive.map { KbRule.code($0) + " " + KbRule.title($0).lowercased() }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // ---------------------------------------------------------------- por sesión
    private var sessionRows: [TrainingSessionResult] {
        Array(sessions.filter { $0.resumen?.trabajoPista?.baseCientifica != nil }.suffix(12).reversed())
    }

    private var sessionsTable: some View {
        VStack(alignment: .leading, spacing: 3) {
            KbSectionTitle(text: "Últimas sesiones")
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        KbHead(text: "Fecha", width: 90); KbHead(text: "B1", width: 75); KbHead(text: "B2", width: 75); KbHead(text: "B3", width: 75)
                        KbHead(text: "Galope rápido", width: 100); KbHead(text: "Fatiga ósea", width: 90); KbHead(text: "Lento", width: 75); KbHead(text: "Reglas", width: 70)
                    }
                    ForEach(sessionRows) { (s: TrainingSessionResult) in
                        let k: KbSummaryLoad? = s.resumen?.trabajoPista?.baseCientifica
                        HStack(spacing: 8) {
                            KbCell(text: s.fecha, width: 90)
                            KbCell(text: KbText.metres(k?.bandsM[0]), width: 75)
                            KbCell(text: KbText.metres(k?.bandsM[1]), width: 75)
                            KbCell(text: KbText.metres(k?.bandsM[2]), width: 75)
                            KbCell(text: KbText.metres(k?.gallopM), width: 100)
                            KbCell(text: KbText.percent(k?.bonePct), width: 90)
                            KbCell(text: KbText.percent(k?.boneLowPct), width: 75)
                            Text(s.baseCientifica.rules.isEmpty ? "—" : s.baseCientifica.rules.map { $0.code }.joined(separator: " "))
                                .foregroundStyle(s.baseCientifica.rules.isEmpty ? Avo.textDim : Avo.warn).lineLimit(1).frame(width: 70, alignment: .leading)
                        }
                        .font(.footnote.monospacedDigit()).foregroundStyle(Avo.text)
                    }
                }
            }
        }
    }
}

/// Una regla activa: código, nivel, acción, texto del motor y línea de evidencia.
struct KbRuleRow: View {
    let rule: KbRule

    var body: some View {
        let actionColor: Color = rule.isLimit ? Avo.red : Avo.warn
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                AvoPill(text: rule.code, color: Avo.cyan)
                Text(rule.title).font(.callout.weight(.semibold)).foregroundStyle(Avo.text).lineLimit(2)
                Spacer(minLength: 6)
                AvoPill(text: rule.level.isEmpty ? "—" : rule.level, color: rule.level == "VIGILAR" ? Avo.warn : Avo.blue)
                AvoPill(text: rule.action.isEmpty ? "—" : rule.action, color: actionColor)
            }
            if !rule.text.isEmpty {
                Text(KbText.sentence(rule.text))
                    .font(.footnote).foregroundStyle(Avo.text).fixedSize(horizontal: false, vertical: true)
            }
            if !rule.evidence.isEmpty {
                Text("Evidencia: " + rule.evidence).font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(actionColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(actionColor.opacity(0.4), lineWidth: 1))
    }
}

// MARK: - piezas

private struct KbSectionTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim)
    }
}

private struct KbHead: View {
    let text: String
    let width: CGFloat
    var body: some View {
        Text(text.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(Avo.textDim).lineLimit(1).frame(width: width, alignment: .leading)
    }
}

private struct KbCell: View {
    let text: String
    let width: CGFloat
    var body: some View {
        Text(text).lineLimit(1).frame(width: width, alignment: .leading)
            .foregroundStyle(text == KbText.noData ? Avo.textDim : Avo.text)
    }
}
