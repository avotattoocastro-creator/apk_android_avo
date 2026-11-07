import SwiftUI
import UniformTypeIdentifiers

/// «Entrenamientos» page = port of windows/AVO.Windows/Views/HomeView.xaml: hero + main actions, headline metrics, the
/// training list (search, favourites, assignment), the watch card (Wi-Fi instead of USB), horses, sensors, import log and
/// system status.
struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var pickingFolder: Bool = false

    var body: some View {
        GeometryReader { geo in
            let wide: Bool = geo.size.width >= 980
            // «Dashboard» (trainer's sketches 08/11/2026): only the banner, quick actions and the figures; the recent
            // sessions, watch, horses, sensors, imports and system cards were removed (the trainings are in
            // «Entrenamientos», the watch in «Reloj Wi-Fi», the horses in «Cuadra»). Landscape: no scroll, so nothing is
            // ever cut at the top: banner + figures on the left, the actions down the whole right side.
            if wide {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 14) {
                        heroBanner.frame(maxHeight: .infinity)
                        metrics(columns: geo.size.width >= 1250 ? 5 : 3)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    actionsCard(fill: true).frame(width: 340).frame(maxHeight: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        hero(wide: false)
                        metrics(columns: 3)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
        }
        .background(Avo.bg)
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [UTType.folder], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let u = urls.first { Task { @MainActor in await app.importFolder(u) } }
            case .failure(let error):
                app.fail(error)
            }
        }
    }

    // ------------------------------------------------------------------ hero + actions
    @ViewBuilder
    private func hero(wide: Bool) -> some View {
        if wide {
            HStack(alignment: .top, spacing: 14) {
                heroBanner.frame(maxWidth: .infinity)
                actionsCard.frame(width: 340)
            }
            .frame(height: 330)
        } else {
            VStack(spacing: 14) {
                heroBanner.frame(height: 300)
                actionsCard
            }
        }
    }

    private var heroBanner: some View {
        ZStack(alignment: .leading) {
            Color(hex: 0x030406)
            Image("avo_brand_hero").resizable().scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .clipped()
            LinearGradient(stops: [
                .init(color: Color(hex: 0x030406, alpha: 0.95), location: 0),
                .init(color: Color(hex: 0x030406, alpha: 0.70), location: 0.45),
                .init(color: Color(hex: 0x030406, alpha: 0), location: 0.8),
            ], startPoint: .leading, endPoint: .trailing)
            VStack(alignment: .leading, spacing: 0) {
                Text("AVO").font(.system(size: 64, weight: .light)).foregroundStyle(Avo.text)
                Text("PERFORMANCE HORSE").font(.system(size: 20, weight: .semibold)).foregroundStyle(Avo.silver).padding(.leading, 2)
                RoundedRectangle(cornerRadius: 1.5).fill(Avo.red).frame(width: 120, height: 3).padding(.vertical, 14).padding(.leading, 2)
                Text("Bienvenido a AVO Performance Horse").font(.title3.weight(.semibold)).foregroundStyle(Avo.text)
                Text("Análisis avanzado del rendimiento ecuestre: velocidad, aires, esfuerzo, cincha, tramos, comparativas, mareas e informes.")
                    .font(.footnote).foregroundStyle(Avo.textDim).padding(.top, 6).fixedSize(horizontal: false, vertical: true)
                Text("CIENCIA  ·  TECNOLOGÍA  ·  RENDIMIENTO").font(.caption2.weight(.semibold)).foregroundStyle(Avo.textDim).padding(.top, 22)
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(.leading, 36)
            .padding(.trailing, 16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Avo.line, lineWidth: 1))
    }

    private var actionsCard: some View { actionsCard(fill: false) }

    /// fill = the card takes the whole height (landscape Dashboard) and the actions spread over it.
    private func actionsCard(fill: Bool) -> some View {
        VStack(spacing: fill ? 10 : 2) {
            homeAction("folder", "Abrir entrenamiento", "Archivos .avo (Android) / .avr (RAW)") { app.showImporter = true }
            homeAction("clock.arrow.circlepath", "Importar carpeta", "Varias sesiones a la vez, con detección de duplicados") { pickingFolder = true }
            homeAction("server.rack", "Servidor AVO", "Panel web y descarga HTTPS de .avo") { app.page = .server }
            homeAction("square.split.2x1", "Comparar entrenamientos", "Recorridos y curvas superpuestas") { app.page = .compare }
            homeAction("doc.richtext", "Informes", "PDF, HTML, CSV, GPX y JSON") { app.page = .reports }
            if fill { Spacer(minLength: 0) }
        }
        .padding(8)
        .padding(.top, fill ? 8 : 0)
        .frame(maxHeight: fill ? .infinity : nil, alignment: .top)
        .background(Avo.cardBrush, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Avo.line, lineWidth: 1))
    }

    private func homeAction(_ icon: String, _ title: String, _ caption: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Avo.redSoft).frame(width: 38, height: 38)
                    Image(systemName: icon).font(.system(size: 15)).foregroundStyle(Avo.redLight)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.callout.weight(.semibold)).foregroundStyle(Avo.text)
                    Text(caption).font(.caption2).foregroundStyle(Avo.textDim).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // ------------------------------------------------------------------ metrics
    private func metrics(columns: Int) -> some View {
        let grid: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: columns)
        return LazyVGrid(columns: grid, alignment: .leading, spacing: 10) {
            AvoMetric(label: "Entrenamientos", value: "\(app.sessionCount)", caption: "Importados y verificados")
            AvoMetric(label: "Distancia medida", value: app.totalDistanceText, caption: "Solo sesiones reales")
            AvoMetric(label: "Distancia demostración", value: app.demoDistanceText, caption: "Datos sintéticos, no medidos", accent: Avo.warn)
            AvoMetric(label: "Velocidad máxima", value: app.bestSpeedText, caption: "Filtrada, todas las sesiones")
            AvoMetric(label: "Sesión activa", value: app.selected?.dateText ?? "—", caption: app.selected?.horse ?? "Ninguna")
        }
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
