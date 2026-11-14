import SwiftUI
import UniformTypeIdentifiers

/// Sidebar entry (Windows MainWindow.xaml left navigation, same order; «Reloj Wi-Fi» replaces «Reloj USB»).
struct RootNavEntry: Identifiable {
    var page: Page
    var title: String
    var icon: String
    var id: String { page.rawValue }
}

/// Main window: sidebar with the GENERAL pages only, header (active training, Asignar, Reloj, Abrir) on general pages and
/// the training bar (active training + pages of that training) on the pages of one training, page area with the empty
/// state, status bar, alerts and the assignment sheet.
struct RootView: View {
    @Environment(AppModel.self) private var app
    /// The start screen (Inicio) shows no sidebar; every other page shows it (restored when leaving Inicio).
    @State private var columns: NavigationSplitViewVisibility = .detailOnly

    /// Sidebar: GENERAL pages only. «Análisis» opens the selected training (its pages are in the training bar).
    static let mainEntries: [RootNavEntry] = [
        // «Geocercas y líneas» and «Reloj Wi-Fi» live in «Configuración» (trainer's sketch 14/11/2026)
        // «Inicio» out of the sidebar (trainer's sketch 13/11/2026): the start screen only shows at launch
        // trainer's sketch 08/11/2026: «Entrenamientos» → «Dashboard», «Listado» → «Entrenamientos», Mapa before Análisis
        RootNavEntry(page: .sessions, title: "Dashboard", icon: "square.grid.2x2"),
        RootNavEntry(page: .trainingList, title: "Entrenamientos", icon: "list.bullet.rectangle"),
        // trainer's sketch 14/11/2026: «Calendario» is a button of «Entrenamientos»; «Biomecánica» right after «Análisis»;
        // «Carreras» after «Jinetes». «Mapa» is a tab of the training; «Análisis» opens it at «Resumen»
        RootNavEntry(page: .analysis, title: "Análisis", icon: "waveform.path.ecg"),
        RootNavEntry(page: .biomech, title: "Biomecánica", icon: "figure.walk.motion"),
        RootNavEntry(page: .reports, title: "Informes", icon: "doc.richtext"),
        RootNavEntry(page: .stable, title: "Cuadra", icon: "figure.equestrian.sports"),
        RootNavEntry(page: .riders, title: "Jinetes", icon: "person"),
        RootNavEntry(page: .races, title: "Carreras", icon: "flag.checkered"),
    ]
    static let systemEntries: [RootNavEntry] = [
        // trainer's sketch 13/11/2026: «Configuración» (maintenance, server and future settings) in place of «Servidor AVO»
        RootNavEntry(page: .settings, title: "Configuración", icon: "gearshape"),
    ]
    /// Pages of ONE training, in the training bar at the top of «Análisis».
    static let trainingTabs: [RootNavEntry] = [
        // trainer's sketches 14/11/2026: «Resumen» first, «Mapa» in the place of «Análisis» (hidden for now);
        // «Datos clave» inside Resumen; «Comparar» after «Trabajo en pista»; «Tramos» hidden for now (the stretch
        // analysis is in «Análisis tramo»); «Asistente IA» last
        RootNavEntry(page: .summary, title: "Resumen", icon: "list.bullet.clipboard"),
        RootNavEntry(page: .map, title: "Mapa", icon: "map"),
        RootNavEntry(page: .charts, title: "Gráficas", icon: "chart.xyaxis.line"),
        RootNavEntry(page: .trackWork, title: "Trabajo en pista", icon: "stopwatch"),
        RootNavEntry(page: .compare, title: "Comparar", icon: "square.split.2x1"),
        RootNavEntry(page: .gps, title: "GPS", icon: "location.circle"),
        RootNavEntry(page: .tides, title: "Mareas", icon: "water.waves"),
        RootNavEntry(page: .engine, title: "Motor", icon: "cpu"),
        RootNavEntry(page: .assistant, title: "Asistente IA", icon: "sparkles"),
    ]

    static var trainingTypes: [UTType] {
        var t: [UTType] = []
        if let avo = UTType(filenameExtension: "avo") { t.append(avo) }
        if let avr = UTType(filenameExtension: "avr") { t.append(avr) }
        if t.isEmpty { t.append(.data) }
        return t
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            sidebar
                .navigationSplitViewColumnWidth(min: 230, ideal: 250, max: 280)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear { columns = app.page == .home ? .detailOnly : .doubleColumn }
        .onChange(of: app.page) { (_: Page, newPage: Page) in
            withAnimation(.easeInOut(duration: 0.25)) {
                columns = newPage == .home ? .detailOnly : .doubleColumn
            }
        }
        .fileImporter(isPresented: Binding(get: { app.showImporter }, set: { app.showImporter = $0 }),
                      allowedContentTypes: RootView.trainingTypes, allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                Task { @MainActor in await app.importURLs(urls) }
            case .failure(let error):
                app.fail(error)
            }
        }
        .alert(app.alert?.title ?? "",
               isPresented: Binding(get: { app.alert != nil }, set: { if !$0 { app.alert = nil } })) {
            Button("Aceptar", role: .cancel) { app.alert = nil }
        } message: {
            Text(app.alert?.message ?? "")
        }
        .sheet(isPresented: Binding(get: { app.stable.assignVisible }, set: { app.stable.assignVisible = $0 })) {
            AssignSheet()
                .environment(app)
                .avoColorScheme()
        }
        .fullScreenCover(isPresented: Binding(get: { app.horseHistory.visible },
                                              set: { (v: Bool) in if !v { app.horseHistory.close() } })) {
            HorseHistoryView(model: app.horseHistory)
                .environment(app)
                .avoColorScheme()
        }
        .fullScreenCover(isPresented: Binding(get: { app.stretch.visible },
                                              set: { (v: Bool) in if !v { app.stretch.close() } })) {
            StretchAnalysisView(model: app.stretch)
                .environment(app)
                .avoColorScheme()
        }
        .sheet(item: Binding(get: { app.pdfViewer }, set: { app.pdfViewer = $0 })) { (f: ExportedFile) in
            PdfViewerSheet(file: f)
                .avoColorScheme()
        }
        .fullScreenCover(isPresented: Binding(get: { app.raceVideo.visible && !app.franceGalop.visible },
                                              set: { (v: Bool) in if !v && !app.franceGalop.visible { app.raceVideo.close() } })) {
            RaceVideoView(model: app.raceVideo)
                .environment(app)
                .avoColorScheme()
        }
        .fullScreenCover(isPresented: Binding(get: { app.franceGalop.visible },
                                              set: { (v: Bool) in if !v { app.franceGalop.close() } })) {
            FranceGalopView(model: app.franceGalop)
                .environment(app)
                .avoColorScheme()
        }
    }

    // ------------------------------------------------------------------ sidebar
    private var liveSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(Avo.ok).frame(width: 8, height: 8)
                Text("LIVE").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Avo.text)
                Spacer()
                Text("\(min(4, app.bleLinks.count)) / 4").font(.caption2.monospacedDigit()).foregroundStyle(Avo.textDim)
            }
            .padding(.horizontal, 12)
            ForEach(Array(app.bleLinks.prefix(4))) { (l: BleLink) in
                Button { app.hardwareVisible = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "antenna.radiowaves.left.and.right").font(.callout).frame(width: 22).foregroundStyle(Avo.ok)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(l.name).font(.callout.weight(.semibold)).foregroundStyle(Avo.text).lineLimit(1)
                            Text("Conectado desde las \(MadridTime.format(l.since, "HH:mm"))").font(.caption2).foregroundStyle(Avo.textDim).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Avo.ok.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Avo.ok.opacity(0.5), lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 10)
        .accessibilityIdentifier("nav.live")
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(RootView.mainEntries) { (e: RootNavEntry) in navButton(e) }
                    Divider().background(Avo.line).padding(.horizontal, 14).padding(.vertical, 8)
                    ForEach(RootView.systemEntries) { (e: RootNavEntry) in navButton(e) }
                    // trainer's sketches 14/11/2026: hidden until the system connects by Bluetooth; «LIVE» with one row per
                    // connected equipment (caballo/jockey, máximo 4); each row opens the window that manages the hardware
                    if !app.bleLinks.isEmpty { liveSection }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
            }
            VStack(alignment: .leading, spacing: 3) {
                // app data (trainer's sketch 14/11/2026: «datos, versión, fecha…»)
                Text("AVO Performance Horse").font(.caption2.weight(.semibold)).foregroundStyle(Avo.silver)
                Text("Versión \(AppModel.appVersion) · build \(AppModel.buildNumber)").font(.caption2).foregroundStyle(Avo.textDim)
                Text("Compilada el \(AppModel.buildDateText)").font(.caption2).foregroundStyle(Avo.textDim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Avo.surface)
        // «Equipo conectado» window (kept here: the root modifier chain is already at the type-checker limit)
        .sheet(isPresented: Binding(get: { app.hardwareVisible }, set: { app.hardwareVisible = $0 })) {
            HardwareSheet().environment(app).avoColorScheme()
        }
        .navigationTitle("AVO")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func navButton(_ e: RootNavEntry) -> some View {
        // «Análisis» stays highlighted on every page of the training
        // «Análisis» stays highlighted on every page of the training except the full-screen «Mapa»
        let active: Bool = e.page == .analysis
            ? (app.page.isTrainingPage && app.page != .reports && app.page != .biomech)
            : app.page == e.page
        // Mapa, Análisis and Biomecánica only work once a training has been opened (trainer's sketch 14/11/2026)
        let locked: Bool = [.map, .analysis, .biomech].contains(e.page) && !(app.trainingOpened && app.selected != nil) && !app.captureMode
        return Button {
            app.page = e.page
            if e.page == .home { columns = .detailOnly }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: e.icon).font(.body).frame(width: 22)
                    .foregroundStyle(active ? Avo.red : Avo.silver)
                Text(e.title).font(.callout.weight(active ? .semibold : .regular)).lineLimit(1).minimumScaleFactor(0.75)   // never split a name (sketch 13/11/2026)
                    .foregroundStyle(active ? Avo.text : Avo.silver)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(active ? Avo.redSoft : Color.clear, in: RoundedRectangle(cornerRadius: 7))
            .overlay(alignment: .leading) {
                if active { RoundedRectangle(cornerRadius: 1.5).fill(Avo.red).frame(width: 3).padding(.vertical, 6) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .opacity(locked ? 0.4 : 1)
        .accessibilityIdentifier("nav.\(e.page.rawValue)")
    }

    // ------------------------------------------------------------------ detail
    private var detail: some View {
        VStack(spacing: 0) {
            // no navigation title bar (trainer's sketch 08/11/2026): the AVO header / training bar is the top row of
            // every page; with the sidebar hidden, a button at its left brings the menu back
            // trainer's sketch 13/11/2026: the general pages have no top bar (only the menu button when the sidebar is hidden)
            if app.page != .home && (app.page.isTrainingPage || columns == .detailOnly) {
                HStack(spacing: 0) {
                    if columns == .detailOnly {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) { columns = .doubleColumn }
                        } label: {
                            Image(systemName: "sidebar.left").font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Avo.text).frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 8)
                        .accessibilityLabel("Mostrar menú")
                    }
                    if app.page.isTrainingPage {
                        TrainingBar()
                    } else {
                        Spacer(minLength: 0).frame(height: 52)
                    }
                }
                .background(Avo.headerBrush)
            }
            ZStack {
                Avo.bg.ignoresSafeArea()
                pageView(app.page)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if app.showEmptyState { RootEmptyState() }
                // Inicio has no «Menú» button (trainer's sketch 13/11/2026): its «INICIAR» opens the Dashboard and the sidebar
                if app.captureMode && app.captureReady {
                    Text("capture.ready")
                        .font(.system(size: 2))
                        .opacity(0.02)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("capture.ready")
                }
            }
            if app.page != .home { RootStatusBar() }
        }
        .background(Avo.bg)
        .navigationTitle(RootView.title(app.page))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Avo.surface, for: .navigationBar)
        .toolbar(.hidden, for: .navigationBar)
    }

    static func title(_ p: Page) -> String {
        for e in trainingTabs where e.page == p { return e.title }
        for e in mainEntries + systemEntries where e.page == p { return e.title }
        return "AVO"
    }

    @ViewBuilder
    private func pageView(_ p: Page) -> some View {
        switch p {
        case .home: StartView()
        case .sessions: HomeView()
        case .trainingList: TrainingListView()
        case .races: RacesView()
        case .stable: StableView(kind: .horse)
        case .riders: StableView(kind: .rider)
        case .analysis: MapPageView()
        case .map: MapPageView(mapOnly: true)
        case .summary: AnalysisView()
        case .gps: GpsView()
        case .charts: ChartsView()
        case .trackWork: TrackWorkView()
        case .assistant: AssistantView()
        case .segments: SegmentsView()
        case .biomech: BiomechView()
        case .compare: CompareView()
        case .geofences: GeofencesView()
        case .tides: TidesView()
        case .reports: ReportsView()
        case .watchWifi: WatchWifiView()
        case .server: ServerView()
        case .settings: SettingsView()
        case .engine: EngineView()
        case .calendar: CalendarView()
        case .keyData: KeyDataView()
        }
    }
}

/// Header of every page except the start screen (Windows MainWindow header).
private struct RootHeader: View {
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        HStack(spacing: 12) {
            if sizeClass != .compact {
                HStack(spacing: 10) {
                    Image("avo_logo").resizable().scaledToFit().frame(width: 36, height: 36)
                    Text("AVO").font(.system(size: 26, weight: .light)).foregroundStyle(Avo.silver)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("PERFORMANCE HORSE").font(.caption.weight(.semibold)).foregroundStyle(Avo.text)
                        (Text("iPad · Advanced Analysis").foregroundColor(Avo.textDim)
                            + Text(" V2 PRO").foregroundColor(Avo.red).fontWeight(.semibold))
                            .font(.caption2)
                    }
                }
                .fixedSize()
            }
            Spacer(minLength: 8)
            RootSessionMenu()
            Button {
                app.stable.openAssign(app.selected)
            } label: {
                Label("Asignar", systemImage: "figure.equestrian.sports")
            }
            .buttonStyle(.avoSecondary)
            .disabled(app.selected == nil)
            Button {
                app.page = .watchWifi
            } label: {
                Label("Reloj Wi-Fi", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.avoSecondary)
            Button {
                app.showImporter = true
            } label: {
                Label("Abrir", systemImage: "folder")
            }
            .buttonStyle(.avoPrimary)
        }
        .lineLimit(1)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Avo.headerBrush)
        .overlay(alignment: .bottom) { Rectangle().fill(Avo.line).frame(height: 1) }
    }
}

/// Status bar (Windows MainWindow row 2).
private struct RootStatusBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 10) {
            if app.busy {
                if app.progress > 0 {
                    ProgressView(value: min(max(app.progress, 0), 1)).frame(width: 80)
                } else {
                    ProgressView().controlSize(.mini)
                }
            }
            Text(app.busy ? app.status : "Versión motor IA · AVO Performance Equine " + app.engineShort).font(.caption2).foregroundStyle(Avo.textDim).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8)
            // trainer's sketch 14/11/2026: engine version on the left, copyright on the right
            Text("© \(AppModel.copyrightYear) AVO Performance Horse · Todos los derechos reservados")
                .font(.caption2).foregroundStyle(Avo.textDim).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 14)
        .frame(height: 28)
        .background(Avo.surface)
        .overlay(alignment: .top) { Rectangle().fill(Avo.line).frame(height: 1) }
    }
}

/// Empty state: no training imported yet (Windows ShowEmptyState panel).
private struct RootEmptyState: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            Color(hex: 0x030406, alpha: 0.9).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: "folder").font(.system(size: 36)).foregroundStyle(Avo.red)
                Text("Todavía no hay entrenamientos").font(.title2.weight(.semibold)).foregroundStyle(Avo.text)
                    .padding(.top, 14).padding(.bottom, 6)
                Text("Abre un archivo .avo exportado desde la app Android (Compartir entrenamiento) o un .avr de la tarjeta SD del pecho. También puedes abrirlo desde Archivos, AirDrop o Compartir, o descargarlo del reloj por Wi-Fi. Para ver la aplicación con datos, carga las sesiones de demostración (datos sintéticos, marcados como tales).")
                    .font(.footnote).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { buttons }
                    VStack(alignment: .leading, spacing: 10) { buttons }
                }
                .padding(.top, 20)
                if !app.demoState.isEmpty {
                    Text(app.demoState).font(.caption).foregroundStyle(Avo.textDim).padding(.top, 12)
                }
                if app.busy {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(app.status).font(.caption).foregroundStyle(Avo.cyan)
                    }
                    .padding(.top, 12)
                }
            }
            .padding(.horizontal, 32).padding(.vertical, 28)
            .frame(maxWidth: 640, alignment: .leading)
            .background(Avo.cardBrush, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Avo.line, lineWidth: 1))
            .padding(24)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        Button {
            app.showImporter = true
        } label: {
            Label("Abrir entrenamiento", systemImage: "folder")
        }
        .buttonStyle(.avoPrimary)
        Button("Descargar del reloj (Wi-Fi)") { app.page = .watchWifi }
            .buttonStyle(.avoSecondary)
        Button("Cargar demostración") {
            Task { @MainActor in await app.loadDemo() }
        }
        .buttonStyle(.avoSecondary)
        .disabled(app.busy)
    }
}

/// Active training selector (header of the general pages and training bar).
struct RootSessionMenu: View {
    @Environment(AppModel.self) private var app
    var maxWidth: CGFloat = 340
    @State private var open: Bool = false

    private var sep: some View { Text("|").foregroundStyle(Avo.line) }

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 6) {
                if let s = app.selected {
                    // trainer's sketch 14/11/2026: Fecha | Caballo | V. máx. | Tiempo | Km
                    Text(s.dateTimeText).fontWeight(.semibold).foregroundStyle(Avo.text)
                    sep
                    Text(s.horse).fontWeight(.semibold).foregroundStyle(Avo.text)
                    sep
                    Text("V. máx. " + s.maxSpeedText).monospacedDigit().foregroundStyle(Avo.silver)
                    sep
                    Text(s.durationText).monospacedDigit().foregroundStyle(Avo.silver)
                    sep
                    Text(s.distanceText).monospacedDigit().foregroundStyle(Avo.silver)
                } else {
                    Text("Sin entrenamiento").foregroundStyle(Avo.textDim)
                }
                Image(systemName: "chevron.down").font(.caption).foregroundStyle(Avo.textDim)
            }
            .font(.callout)
            .lineLimit(1)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .background(Avo.surface2, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Avo.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(app.sessions.isEmpty)
        .accessibilityLabel("Entrenamiento activo")
        // trainer's sketch 14/11/2026: «el listado lo quiero alargado con toda la info en línea»
        .popover(isPresented: $open, arrowEdge: .top) {
            RootSessionList { (s: SessionItem) in
                app.select(s)
                open = false
            }
            .environment(app)
            .avoColorScheme()
        }
    }
}

/// Wide list of the trainings, one line each: Fecha | Caballo | Jinete | Disciplina | V. máx. | Tiempo | Km.
struct RootSessionList: View {
    @Environment(AppModel.self) private var app
    let pick: (SessionItem) -> Void

    private static let widths: [CGFloat] = [150, 200, 170, 90, 110, 80, 90]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(["Fecha", "Caballo", "Jinete", "Disciplina", "V. máx.", "Tiempo", "Km"], header: true, selected: false)
                .background(Avo.surface2)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(app.sessionsView) { (s: SessionItem) in
                        Button { pick(s) } label: {
                            row([s.dateTimeText, s.horse, s.rider, s.discipline, s.maxSpeedText, s.durationText, s.distanceText],
                                header: false, selected: s === app.selected)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(width: RootSessionList.widths.reduce(0, +) + 60)
        .frame(maxHeight: 520)
        .background(Avo.surface)
    }

    private func row(_ cells: [String], header: Bool, selected: Bool) -> some View {
        HStack(spacing: 0) {
            Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Avo.red)
                .opacity(selected ? 1 : 0).frame(width: 28)
            ForEach(0..<cells.count, id: \.self) { (i: Int) in
                Text(cells[i])
                    .font(header ? .caption.weight(.semibold) : .callout.weight(i < 2 ? .semibold : .regular))
                    .foregroundStyle(header ? Avo.textDim : (i < 2 ? Avo.text : Avo.silver))
                    .monospacedDigit()
                    .lineLimit(1).truncationMode(.tail)
                    .frame(width: RootSessionList.widths[i], alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, header ? 8 : 11)
        .padding(.trailing, 12)
        .background(selected ? Avo.redSoft : Color.clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Avo.line).frame(height: 1) }
        .contentShape(Rectangle())
    }
}

/// «Entreno 2»: second training to compare with the active one on «Análisis» / «Mapa» (overlaid, blue vs yellow).
struct RootPairMenu: View {
    @Environment(AppModel.self) private var app
    var maxWidth: CGFloat = 260

    var body: some View {
        let pair: SessionItem? = app.compare.isPaired ? app.compare.pairSession : nil
        Menu {
            if pair != nil {
                Button(role: .destructive) { app.compare.setPair(nil) } label: { Label("Sin entreno 2", systemImage: "xmark") }
                Divider()
            }
            ForEach(app.sessionsView.filter { $0.id != app.selected?.id }) { (s: SessionItem) in
                Button {
                    app.compare.setPair(s.id)
                    if app.page != .analysis && app.page != .map { app.page = .analysis }
                } label: {
                    if s.id == pair?.id {
                        Label("\(s.dateTimeText) · \(s.horse) · \(s.distanceText)", systemImage: "checkmark")
                    } else {
                        Text("\(s.dateTimeText) · \(s.horse) · \(s.distanceText)")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if let p = pair {
                    RoundedRectangle(cornerRadius: 2).fill(CompareModel.pairColors.second).frame(width: 12, height: 4)
                    Text(p.dateTimeText).fontWeight(.semibold).foregroundStyle(Avo.text)
                    Text("· \(p.horse)").foregroundStyle(Avo.textDim)
                } else {
                    Image(systemName: "plus.square.on.square").foregroundStyle(Avo.textDim)
                    Text("Entreno 2").foregroundStyle(Avo.textDim)
                }
                Image(systemName: "chevron.down").font(.caption).foregroundStyle(Avo.textDim)
            }
            .font(.callout)
            .lineLimit(1)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .background(Avo.surface2, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(pair == nil ? Avo.line : CompareModel.pairColors.second.opacity(0.6), lineWidth: 1))
        }
        .disabled(app.sessions.count < 2 || app.selected == nil)
        .accessibilityLabel("Entreno 2 para comparar")
        .accessibilityIdentifier("training.pair")
    }
}

/// Bar of the pages of ONE training (top of «Análisis»): active training, its pages and «Asignar».
private struct TrainingBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 0) {
        HStack(spacing: 10) {
            if app.page == .map {
                // «Mapa»: training picker and «Análisis tramo» (the pages of the training are in the row below)
                RootSessionMenu(maxWidth: 820)
                Spacer(minLength: 0)
                // «Análisis tramo»: full-screen analysis of the stretch selected on the chart (trainer's sketch 08/11/2026)
                Button {
                    app.stretch.openCurrent()
                } label: {
                    Label("Análisis tramo", systemImage: "chart.bar.doc.horizontal")
                }
                .buttonStyle(.avoPrimary)
                .disabled(!app.hasRange || app.selected == nil)
                .accessibilityIdentifier("map.stretchAnalysis")
            } else {
            // like «Mapa» (trainer's sketch 14/11/2026): only the training with its data; no «Entreno 2» here.
            // On «Comparar» the bar holds the selector of the trainings to compare (sketch 14/11/2026)
            if app.page == .compare { CompareSelector() } else { RootSessionMenu(maxWidth: 900) }
            Spacer(minLength: 0)
            Button {
                app.stable.openAssign(app.selected)
            } label: {
                Label("Asignar", systemImage: "figure.equestrian.sports")
            }
            .buttonStyle(.avoSecondary)
            .disabled(app.selected == nil)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Avo.headerBrush)
        .overlay(alignment: .bottom) { Rectangle().fill(Avo.line).frame(height: 1) }
        // pages of the training in their own row under the bar, all visible (trainer's sketch 08/11/2026);
        // not on Informes and Biomecánica (sidebar pages). «Mapa» is a tab of the training since 14/11/2026, so the row
        // shows there too (sketch: «falta el menú que todos llevan en análisis»)
        if app.page != .reports && app.page != .biomech {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(RootView.trainingTabs) { (e: RootNavEntry) in tab(e) }
                }
                .padding(.horizontal, 12).padding(.vertical, 4)
            }
            .accessibilityIdentifier("training.tabs")
            .background(Avo.headerBrush)
            .overlay(alignment: .bottom) { Rectangle().fill(Avo.line).frame(height: 1) }
        }
        }
    }

    private func tab(_ e: RootNavEntry) -> some View {
        let active: Bool = app.page == e.page
        return Button {
            app.page = e.page
        } label: {
            HStack(spacing: 6) {
                Image(systemName: e.icon).font(.footnote)
                Text(e.title).font(.callout.weight(active ? .semibold : .regular)).lineLimit(1).minimumScaleFactor(0.75)   // never split a name (sketch 13/11/2026)
            }
            .foregroundStyle(active ? Avo.text : Avo.silver)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(active ? Avo.redSoft : Color.clear, in: RoundedRectangle(cornerRadius: 7))
            .overlay(alignment: .bottom) {
                if active { RoundedRectangle(cornerRadius: 1.5).fill(Avo.red).frame(height: 3).padding(.horizontal, 8) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tab.\(e.page.rawValue)")
    }
}
