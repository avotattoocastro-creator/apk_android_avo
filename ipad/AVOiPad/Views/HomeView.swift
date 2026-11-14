import SwiftUI
import UniformTypeIdentifiers

/// «Dashboard» = port of windows/AVO.Windows/Views/HomeView.xaml (top part): banner, figures at a glance and the latest
/// trainings. The older cards below (list, watch, horses, sensors…) are no longer shown.
struct HomeView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let d: DashboardSummary = DashboardSummary.from(app.calendarEntries, today: Date())
        GeometryReader { geo in
            let wide: Bool = geo.size.width >= 980
            // «Dashboard» (trainer's sketch 13/11/2026): the banner is only the image; on the right, figures needed at a
            // glance (caballos, jockeys, entrenamientos, esta semana, por revisar) instead of buttons; at the bottom the
            // latest trainings instead of the totals row. Same rules as Windows (Core DashboardSummary).
            if wide {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 14) {
                        heroBanner.frame(maxWidth: .infinity, maxHeight: .infinity)
                        counters(d).frame(width: 340).frame(maxHeight: .infinity)
                    }
                    .frame(maxHeight: .infinity)
                    latestRow(d, columns: 5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        heroBanner.frame(height: 300)
                        counters(d)
                        latestRow(d, columns: 2)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
        }
        .background(Avo.bg)
        .accessibilityIdentifier("page.dashboard")
    }

    // ------------------------------------------------------------------ banner (image only)
    private var heroBanner: some View {
        // the image fills the box WITHOUT asking for more width (scaledToFill inside an overlay): it used to push the
        // figures column off the screen (build 88, the numbers were not visible)
        Color.black
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            // whole logo always visible (trainer 14/11/2026: «PERFORMANCE» was cut and the page unbalanced without the
            // sidebar): the image fits inside the box on the logo's own black background
            .overlay { Image("avo_brand_hero").resizable().scaledToFit() }
            .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Avo.line, lineWidth: 1))
    }

    // ------------------------------------------------------------------ figures at a glance
    private func counters(_ d: DashboardSummary) -> some View {
        VStack(spacing: 8) {
            counter("figure.equestrian.sports", "\(app.stable.horseNames.count)", "Caballos", "Activos en la cuadra") { app.page = .stable }
            counter("person", "\(app.stable.riderNames.count)", "Jockeys", "Jinetes activos") { app.page = .riders }
            counter("list.bullet.rectangle", "\(d.trainings)", "Entrenamientos", "En el iPad") { app.page = .trainingList }
            counter("calendar", "\(d.thisWeek)", "Esta semana", "De lunes a domingo") { app.page = .calendar }
            counter("exclamationmark.circle", "\(d.pending)", "Por revisar", "Sin caballo o sin analizar",
                    accent: d.pending > 0 ? Avo.warn : Avo.ok) { app.page = .trainingList }
            // trainer's sketch 14/11/2026: «LIVE» = equipment connected in real time (caballo/jockey, máximo 4)
            counter("dot.radiowaves.left.and.right", "\(min(4, app.bleLinks.count))", "Live", "Conectados en tiempo real · máx. 4",
                    accent: app.bleLinks.isEmpty ? Avo.textDim : Avo.ok) { if !app.bleLinks.isEmpty { app.hardwareVisible = true } }
        }
        .padding(8)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Avo.cardBrush, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Avo.line, lineWidth: 1))
    }

    private func counter(_ icon: String, _ value: String, _ title: String, _ caption: String, accent: Color = Avo.text,
                         perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Avo.redSoft).frame(width: 40, height: 40)
                    Image(systemName: icon).font(.system(size: 16)).foregroundStyle(Avo.redLight)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title.uppercased()).font(.caption.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.silver)
                    Text(caption).font(.caption2).foregroundStyle(Avo.textDim).lineLimit(1)
                }
                .layoutPriority(0)
                Spacer(minLength: 4)
                Text(value).font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(accent)
                    .lineLimit(1).fixedSize().layoutPriority(1)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dash.\(title)")
    }

    // ------------------------------------------------------------------ latest trainings
    private func latestRow(_ d: DashboardSummary, columns: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ÚLTIMOS ENTRENAMIENTOS").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(Avo.silver)
            if d.latest.isEmpty {
                AvoNoData(text: "Sin entrenamientos todavía · ábrelos desde «Entrenamientos» o el «Reloj Wi-Fi»")
            } else {
                // always 5 slots of the same size (trainer's sketch 13/11/2026: «misma medida todos»)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
                    ForEach(d.latest) { (c: DashCard) in latestCard(c) }
                    ForEach(0..<max(0, 5 - d.latest.count), id: \.self) { (_: Int) in
                        RoundedRectangle(cornerRadius: 8).stroke(Avo.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                            .frame(height: Self.latestHeight)
                    }
                }
            }
        }
    }

    static let latestHeight: CGFloat = 104

    private func latestCard(_ c: DashCard) -> some View {
        Button {
            if let s = app.sessions.first(where: { $0.id == c.id }) {
                app.select(s)
                app.page = .keyData
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(c.dayText).font(.caption.weight(.bold)).foregroundStyle(Avo.redLight).lineLimit(1).fixedSize()
                    Text(c.timeText).font(.caption.monospacedDigit()).foregroundStyle(Avo.textDim).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(c.quality).font(.caption2.weight(.semibold)).lineLimit(1).fixedSize()
                        .foregroundStyle(c.quality == "RTK FIX" ? Avo.ok : (c.quality == "Sin FIX" ? Avo.warn : Avo.unknown))
                }
                Text(c.horse).font(.headline).foregroundStyle(Avo.text).lineLimit(1)
                Text(c.distanceText + " · " + c.durationText).font(.callout.monospacedDigit()).foregroundStyle(Avo.silver)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: Self.latestHeight, maxHeight: Self.latestHeight, alignment: .topLeading)
            .background(Avo.cardBrush, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Avo.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dash.latest.\(c.id)")
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
                ShellStatusIndicator(text: "Motor AVO Equine Intelligence", detail: app.engineShort, state: app.engineIndicator)
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
