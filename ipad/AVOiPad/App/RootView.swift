import SwiftUI
import UniformTypeIdentifiers

/// Sidebar entry (Windows MainWindow.xaml left navigation, same order; «Reloj Wi-Fi» replaces «Reloj USB»).
struct RootNavEntry: Identifiable {
    var page: Page
    var title: String
    var icon: String
    var id: String { page.rawValue }
}

/// Main window = port of windows/AVO.Windows/MainWindow.xaml: sidebar, header (active training, Asignar, Reloj, Abrir),
/// page area with the empty state, status bar, alerts and the assignment sheet.
struct RootView: View {
    @Environment(AppModel.self) private var app
    /// The start screen (Inicio) shows no sidebar; every other page shows it (restored when leaving Inicio).
    @State private var columns: NavigationSplitViewVisibility = .detailOnly

    static let mainEntries: [RootNavEntry] = [
        RootNavEntry(page: .home, title: "Inicio", icon: "house"),
        RootNavEntry(page: .sessions, title: "Entrenamientos", icon: "clock.arrow.circlepath"),
        RootNavEntry(page: .stable, title: "Cuadra", icon: "figure.equestrian.sports"),
        RootNavEntry(page: .riders, title: "Jinetes", icon: "person"),
        RootNavEntry(page: .analysis, title: "Análisis", icon: "waveform.path.ecg"),
        RootNavEntry(page: .map, title: "Mapa", icon: "map"),
        RootNavEntry(page: .gps, title: "GPS", icon: "location.circle"),
        RootNavEntry(page: .charts, title: "Gráficas", icon: "chart.xyaxis.line"),
        RootNavEntry(page: .segments, title: "Tramos", icon: "ruler"),
        RootNavEntry(page: .biomech, title: "Biomecánica", icon: "figure.walk.motion"),
        RootNavEntry(page: .compare, title: "Comparar", icon: "square.split.2x1"),
        RootNavEntry(page: .geofences, title: "Geocercas y líneas", icon: "flag"),
        RootNavEntry(page: .watchWifi, title: "Reloj Wi-Fi", icon: "wifi"),
        RootNavEntry(page: .tides, title: "Mareas y entorno", icon: "water.waves"),
        RootNavEntry(page: .reports, title: "Informes", icon: "doc.richtext"),
    ]
    static let systemEntries: [RootNavEntry] = [
        RootNavEntry(page: .server, title: "Servidor AVO", icon: "server.rack"),
        RootNavEntry(page: .engine, title: "Motor AVO", icon: "cpu"),
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
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear { columns = app.page == .home ? .detailOnly : .all }
        .onChange(of: app.page) { (_: Page, newPage: Page) in
            withAnimation(.easeInOut(duration: 0.25)) {
                columns = newPage == .home ? .detailOnly : .all
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
                .preferredColorScheme(.dark)
        }
    }

    // ------------------------------------------------------------------ sidebar
    private var sidebar: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(RootView.mainEntries) { (e: RootNavEntry) in navButton(e) }
                    Divider().background(Avo.line).padding(.horizontal, 14).padding(.vertical, 8)
                    ForEach(RootView.systemEntries) { (e: RootNavEntry) in navButton(e) }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(app.engineInfo).font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                Text("Formato AVO-TRAINING-1 · AVORAW1").font(.caption2).foregroundStyle(Avo.textDim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Avo.surface)
        .navigationTitle("AVO")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func navButton(_ e: RootNavEntry) -> some View {
        let active: Bool = app.page == e.page
        return Button {
            app.page = e.page
            if e.page == .home { columns = .detailOnly }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: e.icon).font(.body).frame(width: 22)
                    .foregroundStyle(active ? Avo.red : Avo.silver)
                Text(e.title).font(.callout.weight(active ? .semibold : .regular))
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
        .accessibilityIdentifier("nav.\(e.page.rawValue)")
    }

    // ------------------------------------------------------------------ detail
    private var detail: some View {
        VStack(spacing: 0) {
            if app.page != .home { RootHeader() }
            ZStack {
                Avo.bg.ignoresSafeArea()
                pageView(app.page)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if app.showEmptyState { RootEmptyState() }
                if app.page == .home && columns == .detailOnly {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { columns = .all }
                    } label: {
                        Label("Menú", systemImage: "sidebar.left")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Color(hex: 0xF2F4F7))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color(hex: 0x12192A, alpha: 0.72), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0x3A4A60), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 16)
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .accessibilityLabel("Mostrar menú")
                    .accessibilityIdentifier("start.menu")
                }
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
        .toolbar(app.page == .home ? .hidden : .visible, for: .navigationBar)
    }

    static func title(_ p: Page) -> String {
        for e in mainEntries + systemEntries where e.page == p { return e.title }
        return "AVO"
    }

    @ViewBuilder
    private func pageView(_ p: Page) -> some View {
        switch p {
        case .home: StartView()
        case .sessions: HomeView()
        case .stable: StableView(kind: .horse)
        case .riders: StableView(kind: .rider)
        case .analysis: AnalysisView()
        case .map: MapPageView()
        case .gps: GpsView()
        case .charts: ChartsView()
        case .segments: SegmentsView()
        case .biomech: BiomechView()
        case .compare: CompareView()
        case .geofences: GeofencesView()
        case .tides: TidesView()
        case .reports: ReportsView()
        case .watchWifi: WatchWifiView()
        case .server: ServerView()
        case .engine: EngineView()
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
            sessionMenu
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

    private var sessionMenu: some View {
        Menu {
            ForEach(app.sessionsView) { (s: SessionItem) in
                Button {
                    app.select(s)
                } label: {
                    if s === app.selected {
                        Label("\(s.dateTimeText) · \(s.horse) · \(s.distanceText)", systemImage: "checkmark")
                    } else {
                        Text("\(s.dateTimeText) · \(s.horse) · \(s.distanceText)")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if let s = app.selected {
                    Text(s.dateTimeText).fontWeight(.semibold).foregroundStyle(Avo.text)
                    Text("· \(s.horse) · \(s.distanceText)").foregroundStyle(Avo.textDim)
                } else {
                    Text("Sin entrenamiento").foregroundStyle(Avo.textDim)
                }
                Image(systemName: "chevron.down").font(.caption).foregroundStyle(Avo.textDim)
            }
            .font(.callout)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: 340, alignment: .leading)
            .background(Avo.surface2, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Avo.line, lineWidth: 1))
        }
        .disabled(app.sessions.isEmpty)
        .accessibilityLabel("Entrenamiento activo")
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
            Text(app.status).font(.caption2).foregroundStyle(Avo.textDim).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8)
            Text("TELEMETRÍA ORIGINAL INTACTA · IMU = CINCHA · Europe/Madrid · v\(AppModel.appVersion)")
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
