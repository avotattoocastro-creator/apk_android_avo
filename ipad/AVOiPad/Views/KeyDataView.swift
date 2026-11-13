import SwiftUI

/// «Datos clave» de un entrenamiento (paridad iPad ↔ PC, docs/PARIDAD_IPAD_PC.md): rejilla de cifras con icono, reparto
/// de aires y calidad de la posición. Todas las cifras salen del motor AVO Equine (Core/KeyData.swift), con las mismas
/// reglas que windows/AVO.Windows/Views/KeyDataView.xaml. Pulso y recuperaciones se muestran vacíos hasta que exista
/// el ECG de la cincha: nunca se inventan.
struct KeyDataView: View {
    @Environment(AppModel.self) private var app
    /// nil = automatic (shown when there is room for 6 tiles beside it).
    @State private var showNav: Bool? = nil
    @State private var query: String = ""

    var body: some View {
        GeometryReader { (g: GeometryProxy) in
            let nav: Bool = showNav ?? (g.size.width >= 1100)
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let s = app.selected {
                            if let e = s.engine {
                                content(s, KeyData.cached(id: s.id, json: e.rawJson), nav)
                            } else {
                                header(s, nav)
                                AvoCard(title: "Datos clave") {
                                    AvoNoData(text: "El motor AVO todavía no ha analizado este entrenamiento · \(s.engineState)")
                                }
                            }
                        } else {
                            AvoNoData(text: "Elige un entrenamiento")
                        }
                    }
                    .padding(16)
                }
                if nav {
                    navigator.frame(width: 260)
                }
            }
        }
        .background(Avo.bg)
        .accessibilityIdentifier("page.keyData")
    }

    private func header(_ s: SessionItem, _ nav: Bool) -> some View {
        HStack(alignment: .top) {
            AvoPageTitle(title: "\(s.horse) · \(s.dateTimeText)",
                         subtitle: "Cifras del motor AVO Equine · iguales en iPad y PC")
            Spacer()
            Button {
                showNav = !nav
            } label: {
                Label(nav ? "Ocultar sesiones" : "Sesiones", systemImage: "sidebar.right")
            }
            .buttonStyle(.avoSecondary)
            .accessibilityIdentifier("keydata.toggleNav")
        }
    }

    @ViewBuilder
    private func content(_ s: SessionItem, _ k: KeyData, _ nav: Bool) -> some View {
        header(s, nav)
        section("Velocidad y tiempos", k.tiles.filter { $0.group == 0 })
        section("Pulso", k.tiles.filter { $0.group == 1 })
        section("Tranco", k.tiles.filter { $0.group == 2 })
        splitsCard(k)
        HStack(alignment: .top, spacing: 12) {
            gaitsCard(k)
            qualityCard(k)
        }
    }

    /// Always 6 columns (user request: «6 en línea»), so the rows of the three sections line up.
    private func section(_ title: String, _ tiles: [KeyTile]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(Avo.silver)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 6), spacing: 0) {
                ForEach(tiles) { (t: KeyTile) in
                    if let a = t.t0, let b = t.t1 {
                        Button { app.openInCharts(engineT0: a, engineT1: b) } label: { tile(t) }
                            .buttonStyle(.plain)
                    } else {
                        tile(t)
                    }
                }
            }
        }
    }

    /// Equimetre «Key parameters» style (trainer's request 13/11/2026): no boxes; thin line icon, the figure and its unit
    /// centred, the name in small capitals below, cells separated by hairlines.
    private func tile(_ t: KeyTile) -> some View {
        VStack(spacing: 6) {
            Image(systemName: Self.icon(t.id)).font(.system(size: 26, weight: .ultraLight))
                .foregroundStyle(t.group == 1 ? Avo.redLight : Avo.silver)
                .frame(height: 30)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(t.value).font(.system(size: 26, weight: .regular))
                    .foregroundStyle(t.available ? Avo.text : Avo.unknown)
                    .lineLimit(1).minimumScaleFactor(0.5)
                if !t.unit.isEmpty { Text(t.unit).font(.caption).foregroundStyle(Avo.textDim) }
            }
            Text(t.label.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.5).foregroundStyle(Avo.silver)
                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
            Text(t.caption).font(.caption2).foregroundStyle(t.available ? Avo.textDim : Avo.warn)
                .multilineTextAlignment(.center).lineLimit(2)
        }
        .padding(.horizontal, 8).padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 150)
        .overlay(alignment: .topTrailing) {
            if t.t0 != nil {
                Image(systemName: "chart.xyaxis.line").font(.caption2).foregroundStyle(Avo.textDim).padding(8)
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Avo.line).frame(height: 1).padding(.horizontal, 10) }
        .overlay(alignment: .trailing) { Rectangle().fill(Avo.line).frame(width: 1).padding(.vertical, 14) }
        .contentShape(Rectangle())
        .accessibilityIdentifier("keydata.\(t.id)")
    }

    // ------------------------------------------------------------------ splits (engine parciales)
    private func splitsCard(_ k: KeyData) -> some View {
        AvoCard(title: "Parciales cada 200 m", subtitle: "Por trabajo · toca un parcial para verlo en Gráficas") {
            if k.efforts.isEmpty {
                AvoNoData(text: "Sin trabajos con parciales en este entrenamiento")
            } else {
                ForEach(k.efforts) { (e: KeyEffort) in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(e.title).font(.callout.weight(.semibold)).foregroundStyle(Avo.text)
                            Text(e.kind).font(.caption).foregroundStyle(e.kind == "Trabajo rápido" ? Avo.redLight : Avo.blue)
                            Text(e.summary).font(.caption.monospacedDigit()).foregroundStyle(Avo.textDim)
                            Spacer()
                            Button { app.openInCharts(engineT0: e.t0, engineT1: e.t1) } label: {
                                Label("Ver en gráficas", systemImage: "chart.xyaxis.line")
                            }
                            .buttonStyle(.avoSecondary)
                        }
                        ForEach(e.splits) { (p: KeySplit) in
                            Button { app.openInCharts(engineT0: p.t0, engineT1: p.t1) } label: { splitRow(p) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .accessibilityIdentifier("keydata.splits")
    }

    private func splitRow(_ p: KeySplit) -> some View {
        HStack(spacing: 10) {
            Text(p.label).font(.caption.monospacedDigit()).foregroundStyle(Avo.silver).frame(width: 96, alignment: .leading)
            GeometryReader { (g: GeometryProxy) in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Avo.surface2)
                    RoundedRectangle(cornerRadius: 3).fill(p.fastest ? Avo.red : Avo.blue)
                        .frame(width: max(2, g.size.width * p.share))
                }
            }
            .frame(height: 10)
            Text(p.timeText + " s").font(.callout.weight(p.fastest ? .bold : .regular).monospacedDigit())
                .foregroundStyle(Avo.text).frame(width: 76, alignment: .trailing)
            Text(p.speedText + " km/h").font(.caption.monospacedDigit()).foregroundStyle(Avo.textDim).frame(width: 84, alignment: .trailing)
        }
        .contentShape(Rectangle())
    }

    // ------------------------------------------------------------------ session navigator (Equimetre-style side list)
    private var navigator: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SESIONES").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(Avo.silver)
            TextField("Buscar caballo", text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("keydata.navSearch")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4, pinnedViews: [.sectionHeaders]) {
                    ForEach(SessionNavigator.groups(app.calendarEntries, query: query)) { (g: NavGroup) in
                        Section {
                            ForEach(g.entries) { (e: CalendarEntry) in navItem(e) }
                        } header: {
                            Text(g.title).font(.caption.weight(.bold)).foregroundStyle(Avo.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Avo.redDark, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Avo.surface)
        .accessibilityIdentifier("keydata.navigator")
    }

    private func navItem(_ e: CalendarEntry) -> some View {
        let on: Bool = app.selected?.id == e.id
        return Button {
            if let s = app.sessions.first(where: { $0.id == e.id }) { app.select(s) }
        } label: {
            HStack(spacing: 8) {
                Circle().fill(on ? Avo.red : Avo.line).frame(width: 8, height: 8)
                Text(SessionNavigator.itemText(e)).font(.callout).foregroundStyle(on ? Avo.text : Avo.silver).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(on ? Avo.redSoft : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func gaitsCard(_ k: KeyData) -> some View {
        AvoCard(title: "Aires", subtitle: "Tiempo en cada aire según el motor") {
            if k.gaits.isEmpty {
                AvoNoData(text: "Sin reparto de aires")
            } else {
                GeometryReader { (g: GeometryProxy) in
                    HStack(spacing: 0) {
                        ForEach(k.gaits) { (a: KeyGait) in
                            Rectangle().fill(Self.gaitColor(a.id)).frame(width: max(0, g.size.width * a.share))
                        }
                    }
                }
                .frame(height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                ForEach(k.gaits) { (a: KeyGait) in
                    HStack {
                        Circle().fill(Self.gaitColor(a.id)).frame(width: 10, height: 10)
                        Text(a.name).font(.callout).foregroundStyle(Avo.text)
                        Spacer()
                        Text(TimeText.clock(a.seconds)).font(.callout.monospacedDigit()).foregroundStyle(Avo.silver)
                        Text(DotNetFormat.custom(a.share * 100, "0", spanish: true) + " %")
                            .font(.callout.weight(.semibold).monospacedDigit()).foregroundStyle(Avo.text).frame(width: 56, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func qualityCard(_ k: KeyData) -> some View {
        AvoCard(title: "Calidad de la posición", subtitle: "Solución GNSS de la espalda (bloque rtk del motor)") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(k.qualityLabel).font(.title2.weight(.semibold))
                    .foregroundStyle(k.qualityLabel == "RTK FIX" ? Avo.ok : (k.qualityLabel == "Sin datos" ? Avo.unknown : Avo.warn))
                if let f = k.fixShare {
                    Text(DotNetFormat.custom(f * 100, "0", spanish: true) + " % en FIX").font(.callout).foregroundStyle(Avo.textDim)
                }
            }
            let total: Double = k.qualitySeconds.reduce(0) { $0 + $1.seconds }
            ForEach(k.qualitySeconds.indices, id: \.self) { (i: Int) in
                HStack {
                    Text(k.qualitySeconds[i].label).font(.callout).foregroundStyle(Avo.text)
                    Spacer()
                    Text(total > 0 ? DotNetFormat.custom(k.qualitySeconds[i].seconds / total * 100, "0", spanish: true) + " %" : "—")
                        .font(.callout.monospacedDigit()).foregroundStyle(Avo.silver)
                }
            }
            if k.qualityLabel != "RTK FIX" && k.qualityLabel != "Sin datos" {
                Text("Sin RTK FIX la precisión es de decímetros: tiempos y velocidades válidos, cifras centimétricas no.")
                    .font(.caption2).foregroundStyle(Avo.warn)
            }
        }
    }

    static func icon(_ id: String) -> String {
        switch id {
        case "vmax", "best200", "best600", "best1000": return "figure.equestrian.sports"
        case "distance": return "point.topleft.down.to.point.bottomright.curvepath"
        case "duration": return "clock"
        case "hrmax", "hrend": return "waveform.path.ecg"
        case "rec2", "rec15": return "heart.text.square"
        case "lmax", "lref1", "lref2": return "ruler"
        case "fmax", "fref1", "fref2": return "metronome"
        default: return "circle"
        }
    }

    static func gaitColor(_ code: String) -> Color {
        switch code {
        case "PARADO": return Avo.line
        case "PASO": return Avo.unknown
        case "TROTE": return Avo.cyan
        case "GALOPE": return Avo.blue
        default: return Avo.silver
        }
    }
}
