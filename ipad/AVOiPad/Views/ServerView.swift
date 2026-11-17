import SwiftUI

/// «Servidor AVO» page = port of windows/AVO.Windows/Views/ServerView.xaml (+ server part of MainViewModel.Reports.cs).
/// The real API contract is not validated: the page shows it as NOT CONNECTED and offers the verified manual routes
/// (web panel, HTTPS download of a .avo with full integrity checks).
struct ServerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var panelUrl: String = ""
    @State private var downloadUrl: String = ""
    @State private var downloadState: String = "Sin descargas"
    @State private var downloading: Bool = false
    @State private var refreshTick: Int = 0

    private let server: AvoServerClient = PendingContractServerClient()

    private var serverStateText: String {
        switch server.state {
        case .connected: return "Conectado"
        case .contractPending: return "No conectado · contrato de API pendiente"
        case .error: return "Error"
        case .notConfigured: return "No configurado"
        }
    }

    var body: some View {
        GeometryReader { geo in
            let wide: Bool = geo.size.width >= 900
            ScrollView {
                Group {
                    if wide {
                        HStack(alignment: .top, spacing: 12) {
                            leftColumn.frame(width: 380)
                            libraryCard.frame(maxWidth: .infinity)
                        }
                    } else {
                        VStack(spacing: 12) {
                            leftColumn
                            libraryCard
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(Avo.bg)
        .onAppear { if panelUrl.isEmpty { panelUrl = app.settings.serverUrl } }
    }

    private var leftColumn: some View {
        VStack(spacing: 12) {
            AvoCard(title: "Servidor AVO") {
                ShellStatusIndicator(text: "Estado", detail: serverStateText, state: .warning)
                Text(server.statusText).font(.footnote).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                Text("Panel web").font(.caption.weight(.semibold)).foregroundStyle(Avo.silver).padding(.top, 6)
                TextField("https://", text: $panelUrl)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Abrir panel en el navegador") { openPanel() }
                    .buttonStyle(.avoSecondary)
            }
            AvoCard(title: "Descargar entrenamiento (.avo por HTTPS)") {
                TextField("https://…/entrenamiento.avo", text: $downloadUrl)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Descargar, verificar e importar") { Task { @MainActor in await download() } }
                    .buttonStyle(.avoPrimary)
                    .disabled(downloading || downloadUrl.trimmed.isEmpty)
                Text(downloadState).font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                Text("Solo HTTPS, máximo 100 MB. Tras descargar se validan manifiesto, SHA-256 por segmento y CRC de bloques; los duplicados se detectan por SHA-256 y por ID de sesión. Funciona sin conexión con la biblioteca local.")
                    .font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            }
            AvoCard(title: "Pendiente para sincronización automática") {
                Text("Contrato documentado en windows/docs/SERVIDOR_CONTRATO_PENDIENTE.md: listado de sesiones del usuario autenticado, descarga por ID con hash, autenticación y gestión de errores. La interfaz IAvoServerClient ya está preparada; no se inventan endpoints ni se guardan credenciales.")
                    .font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var libraryCard: some View {
        AvoCard(title: "Mis entrenamientos (biblioteca local verificada)") {
            HStack {
                Spacer()
                Button("Actualizar") { refreshTick += 1 }.buttonStyle(.avoSecondary)
            }
            ShellTable(columns: [
                ShellTable.Column(title: "Fecha", width: 95), ShellTable.Column(title: "Caballo", width: 150),
                ShellTable.Column(title: "Jinete", width: 150), ShellTable.Column(title: "Lugar", width: 90),
                ShellTable.Column(title: "Origen", width: 110), ShellTable.Column(title: "Estado", width: 140),
                ShellTable.Column(title: "SHA-256", width: 120),
            ], rows: libraryRows(), empty: "Sin entrenamientos en la biblioteca local")
            .id(refreshTick)
        }
    }

    private func libraryRows() -> [[String]] {
        AppModel.byDateDescending(app.sessions).map { (s: SessionItem) -> [String] in
            let sha: String = s.session.fileSha256 ?? ""
            return [s.dateText, s.horse, s.rider, s.discipline, s.kind, "Local · verificado", String(sha.prefix(12))]
        }
    }

    private func openPanel() {
        guard let u = URL(string: panelUrl.trimmed), u.scheme?.lowercased() == "https", u.host != nil else {
            app.show("Servidor AVO", "Introduce una URL HTTPS válida.", error: true)
            return
        }
        openURL(u)
    }

    @MainActor
    private func download() async {
        guard let u = URL(string: downloadUrl.trimmed), u.scheme != nil else {
            downloadState = "Enlace no válido"
            return
        }
        downloading = true
        downloadState = "Descargando…"
        let target: String = AvoFiles.join(app.paths.root, "descargas")
        do {
            let file: String = try await HttpsDownloader.downloadAvo(u, targetDirectory: target, progress: { (p: Double) in
                DispatchQueue.main.async {
                    downloadState = "Descargando… " + DotNetFormat.custom(p * 100, "0", spanish: true) + " %"
                }
            })
            downloadState = "Descargado; validando SHA-256 de segmentos y CRC…"
            await app.importFiles([file])
            downloadState = "Descargado e importado: " + AvoFiles.fileName(file)
        } catch {
            downloadState = "Error: " + error.localizedDescription
            app.log.warn("servidor", "Descarga fallida", error)
        }
        downloading = false
        refreshTick += 1
    }
}
