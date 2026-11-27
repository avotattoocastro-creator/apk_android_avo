import SwiftUI
import UniformTypeIdentifiers

/// «Dashboard» (trainer's sketch 27/11/2026): no banner image; one row of 6 figures at the top, then the latest
/// trainings and the LIVE list, each with its own scroll, so the whole page fits on the screen without a page scroll.
/// Before 27/11/2026: banner with the logo, figures in a right column and 5 cards of latest trainings at the bottom.
struct HomeView: View {
    @Environment(AppModel.self) private var app

    /// Trainings listed in «Últimos entrenamientos» (scroll inside the list).
    static let latestCount: Int = 60

    var body: some View {
        let d: DashboardSummary = DashboardSummary.from(app.calendarEntries, today: Date(), latest: HomeView.latestCount)
        GeometryReader { geo in
            let wide: Bool = geo.size.width >= 980
            if wide {
                VStack(alignment: .leading, spacing: 14) {
                    counters(d, columns: 6)
                    latestList(d).frame(maxHeight: .infinity)
                    liveList.frame(maxHeight: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        counters(d, columns: 3)
                        latestList(d).frame(height: 380)
                        liveList.frame(height: 280)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
        }
        .background(Avo.bg)
        .accessibilityIdentifier("page.dashboard")
    }

    // ------------------------------------------------------------------ figures at a glance (one row)
    private func counters(_ d: DashboardSummary, columns: Int) -> some View {
        let live: Int = app.bleLinks.count + (app.live?.activeSessions.count ?? 0)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
            counter("figure.equestrian.sports", "\(app.stable.horseNames.count)", "Caballos", "Activos en la cuadra") { app.page = .stable }
            counter("person", "\(app.stable.riderNames.count)", "Jockeys", "Jinetes activos") { app.page = .riders }
            counter("list.bullet.rectangle", "\(d.trainings)", "Entrenamientos", "En el iPad") { app.page = .trainingList }
            counter("calendar", "\(d.thisWeek)", "Esta semana", "De lunes a domingo") { app.page = .calendar }
            counter("exclamationmark.circle", "\(d.pending)", "Por revisar", "Sin caballo o sin analizar",
                    accent: d.pending > 0 ? Avo.warn : Avo.ok) { app.page = .trainingList }
            counter("dot.radiowaves.left.and.right", "\(live)", "Live", "Conectados en tiempo real",
                    accent: live == 0 ? Avo.textDim : Avo.ok) { app.page = .live }
        }
    }

    private func counter(_ icon: String, _ value: String, _ title: String, _ caption: String, accent: Color = Avo.text,
                         perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    ZStack {
                        Circle().fill(Avo.redSoft).frame(width: 34, height: 34)
                        Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Avo.redLight)
                    }
                    Spacer(minLength: 4)
                    Text(value).font(.system(size: 32, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(accent).lineLimit(1).minimumScaleFactor(0.6)
                }
                Text(title.uppercased()).font(.caption.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.silver).lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(caption).font(.caption2).foregroundStyle(Avo.textDim).lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Avo.cardBrush, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Avo.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dash.\(title)")
    }

    // ------------------------------------------------------------------ section frame (title + own scroll)
    private func section<Content: View>(_ title: String, _ trailing: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(Avo.silver)
                Spacer()
                Text(trailing).font(.caption2.monospacedDigit()).foregroundStyle(Avo.textDim)
            }
            ScrollView {
                LazyVStack(spacing: 6) { content() }.padding(8)
            }
            .frame(maxHeight: .infinity)
            .background(Avo.cardBrush, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Avo.line, lineWidth: 1))
        }
    }

    // ------------------------------------------------------------------ latest trainings (scroll)
    private func latestList(_ d: DashboardSummary) -> some View {
        section("ÚLTIMOS ENTRENAMIENTOS", d.latest.isEmpty ? "" : "\(d.latest.count) más recientes") {
            if d.latest.isEmpty {
                AvoNoData(text: "Sin entrenamientos todavía · ábrelos desde «Entrenamientos» o el «Reloj Wi-Fi»")
            } else {
                ForEach(d.latest) { (c: DashCard) in latestRow(c) }
            }
        }
        .accessibilityIdentifier("dash.latest")
    }

    private func latestRow(_ c: DashCard) -> some View {
        Button {
            if let s = app.sessions.first(where: { $0.id == c.id }) {
                app.select(s)
                app.page = .keyData
            }
        } label: {
            HStack(spacing: 14) {
                Text(c.dayText).font(.callout.weight(.bold)).foregroundStyle(Avo.redLight).lineLimit(1)
                    .frame(width: 120, alignment: .leading)
                Text(c.timeText).font(.callout.monospacedDigit()).foregroundStyle(Avo.textDim).frame(width: 52, alignment: .leading)
                Text(c.horse).font(.headline).foregroundStyle(Avo.text).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(c.distanceText + " · " + c.durationText).font(.callout.monospacedDigit()).foregroundStyle(Avo.silver)
                    .lineLimit(1).fixedSize()
                Text(c.quality).font(.caption.weight(.semibold)).lineLimit(1)
                    .foregroundStyle(c.quality == "RTK FIX" ? Avo.ok : (c.quality == "Sin FIX" ? Avo.warn : Avo.unknown))
                    .frame(width: 92, alignment: .trailing)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Avo.textDim)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Avo.surface2.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dash.latest.\(c.id)")
    }

    // ------------------------------------------------------------------ LIVE (scroll)
    /// Directos del servidor (un pecho encendido cada uno) y equipos conectados por Bluetooth a este iPad.
    private var liveList: some View {
        let server: [LiveSessionRef] = app.live?.activeSessions ?? []
        let links: [BleLink] = app.bleLinks
        return section("LIVE", server.isEmpty && links.isEmpty ? "" : "\(server.count + links.count) conectados") {
            if server.isEmpty && links.isEmpty {
                AvoNoData(text: "Nadie en directo ahora · aparecen aquí al encender el pecho o conectar un equipo por Bluetooth")
            } else {
                ForEach(server) { (r: LiveSessionRef) in
                    liveRow(icon: r.meta.state == "REC" ? "record.circle" : "location.circle",
                            color: r.meta.state == "REC" ? Avo.red : Avo.ok,
                            title: r.meta.horseName.isEmpty ? "Caballo sin asignar" : r.meta.horseName,
                            detail: [r.meta.riderName, r.meta.stateText].filter { !$0.isEmpty }.joined(separator: " · "),
                            tag: "EN DIRECTO") {
                        app.page = .live
                        if let live = app.live, live.current?.id != r.id { live.open(r) }
                    }
                }
                ForEach(links) { (l: BleLink) in
                    liveRow(icon: "antenna.radiowaves.left.and.right", color: Avo.ok, title: l.name,
                            detail: "Conectado desde las \(MadridTime.format(l.since, "HH:mm"))", tag: "BLUETOOTH") {
                        app.hardwareVisible = true
                    }
                }
            }
        }
        .accessibilityIdentifier("dash.live")
    }

    private func liveRow(icon: String, color: Color, title: String, detail: String, tag: String,
                         perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title3).frame(width: 28).foregroundStyle(color)
                Text(title).font(.headline).foregroundStyle(Avo.text).lineLimit(1)
                Text(detail).font(.callout).foregroundStyle(Avo.textDim).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(tag).font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(color)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Avo.textDim)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.45), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // ------------------------------------------------------------------ trainings
    private var sessionsCard: some View {
        @Bindable var app = app
        return AvoCard(title: "Sesiones recientes · historial y favoritos") {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Avo.textDim)
                    TextField("Buscar caballo, jinete, fecha, código…", text: $app.search)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Avo.surface2, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Avo.line, lineWidth: 1))
                Toggle("Solo favoritos", isOn: $app.onlyFavorites)
                    .toggleStyle(.button)
                    .tint(Avo.warn)
                    .font(.footnote)
            }
            let list: [SessionItem] = app.sessionsView
            if list.isEmpty {
                AvoNoData(text: app.sessions.isEmpty ? "Sin entrenamientos importados" : "Ningún entrenamiento coincide con el filtro")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(list) { (s: SessionItem) in
                        HomeSessionRow(item: s)
                        Divider().background(Avo.line)
                    }
                }
            }
        }
        .frame(minHeight: 360, alignment: .top)
    }

    // ------------------------------------------------------------------ side column
    private var sideColumn: some View {
        VStack(spacing: 12) {
            AvoCard(title: "Reloj AVO (Wi-Fi)") {
                Text("Descarga los entrenamientos del reloj de pecho por su propia red Wi-Fi (el iPad no admite el reloj por USB).")
                    .font(.footnote).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                Button("Sincronizar reloj") { app.page = .watchWifi }.buttonStyle(.avoPrimary)
            }
            AvoCard(title: "Caballos") {
                HStack {
                    Spacer()
                    Button("Ver cuadra ›") { app.page = .stable }.font(.caption).buttonStyle(.plain).foregroundStyle(Avo.redLight)
                }
                let cards: [HomeHorseCard] = app.horses
                if cards.isEmpty {
                    AvoNoData()
                } else {
                    ForEach(cards) { (h: HomeHorseCard) in
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().fill(Avo.surface2).frame(width: 34, height: 34)
                                Circle().stroke(Avo.line, lineWidth: 1).frame(width: 34, height: 34)
                                Image(systemName: "figure.equestrian.sports").font(.system(size: 14)).foregroundStyle(Avo.silver)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(h.name).font(.footnote.weight(.semibold)).foregroundStyle(Avo.text)
                                Text("\(h.sessions) entrenamientos · último \(h.lastDate)").font(.caption2).foregroundStyle(Avo.textDim)
                            }
                            Spacer(minLength: 4)
                            Text(h.bestSpeed).font(.footnote.weight(.semibold)).foregroundStyle(Avo.text)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
            AvoCard(title: "Disponibilidad de sensores") {
                let rows: [ShellRow] = app.sensorStatusRows
                if rows.isEmpty {
                    AvoNoData()
                } else {
                    ForEach(rows) { (r: ShellRow) in ShellKeyValue(key: r.key, value: r.value) }
                }
            }
            AvoCard(title: "Estado de importaciones") {
                if app.importLog.isEmpty {
                    AvoNoData(text: "Sin importaciones")
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(app.importLog) { (r: ImportLogRow) in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle().fill(r.ok ? Avo.ok : Avo.bad).frame(width: 8, height: 8).padding(.top, 5)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(r.file).font(.caption).foregroundStyle(Avo.text).lineLimit(1).truncationMode(.middle)
                                        Text("\(r.time) · \(r.result)").font(.caption2).foregroundStyle(Avo.textDim)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                }
            }
            AvoCard(title: "Estado del sistema") {
                ShellStatusIndicator(text: "Motor AVO Performance Equine", detail: app.engineShort, state: app.engineIndicator)
                ShellStatusIndicator(text: "Importación segura (SHA-256 / CRC)", detail: "Activa", state: .ok)
                ShellStatusIndicator(text: "Servidor AVO", detail: "Contrato pendiente", state: .warning)
                ShellStatusIndicator(text: "Mareas IHM / Open-Meteo", detail: "Bajo demanda", state: .info)
            }
        }
    }
}

/// One training of the list (Windows DataGrid row: ★, date, horse, rider, place, distance, duration, max speed,
/// girth, origin, Asignar). Tap = active training; «Análisis» opens it.
private struct HomeSessionRow: View {
    @Environment(AppModel.self) private var app
    let item: SessionItem

    var body: some View {
        let active: Bool = app.selected === item
        HStack(alignment: .center, spacing: 10) {
            Button {
                app.toggleFavorite(item)
            } label: {
                Text(item.isFavorite ? "★" : "☆").font(.system(size: 18))
                    .foregroundStyle(item.isFavorite ? Avo.warn : Avo.textDim)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Marcar / quitar favorito")
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.dateTimeText).font(.callout.weight(.semibold)).foregroundStyle(Avo.text)
                    Text("\(item.horse) · \(item.rider)").font(.callout).foregroundStyle(Avo.silver).lineLimit(1)
                    AvoPill(text: item.kind, color: item.isSynthetic ? Avo.warn : Avo.ok)
                }
                Text([item.discipline, item.distanceText, item.durationText, "máx " + item.maxSpeedText,
                      item.girthText].joined(separator: " · "))
                    .font(.caption).foregroundStyle(Avo.textDim).lineLimit(2)
            }
            Spacer(minLength: 6)
            Button("Asignar") { app.stable.openAssign(item) }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .foregroundStyle(item.needsIdentity ? Color.white : Avo.text)
                .background(item.needsIdentity ? Avo.red : Avo.surface2, in: RoundedRectangle(cornerRadius: 6))
                .buttonStyle(.plain)
            Button {
                app.select(item)
                app.page = .analysis
            } label: {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Avo.textDim)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Abrir análisis")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(active ? Avo.redSoft : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { app.select(item) }
        .contextMenu {
            Button("Ver análisis") { app.select(item); app.page = .analysis }
            Button("Asignar caballo y jinete") { app.stable.openAssign(item) }
            Button(item.isFavorite ? "Quitar de favoritos" : "Marcar como favorito") { app.toggleFavorite(item) }
        }
    }
}
