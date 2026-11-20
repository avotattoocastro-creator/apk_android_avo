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
    @State private var cloudItems: [CloudItem] = []
    @State private var cloudState: String = "Pulsa «Ver mi nube»"
    @State private var cloudBusy: Bool = false

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
            AvoCard(title: "Nube AVO (mis entrenamientos)") {
                Text(app.live.signedCode.map { "Tarjeta AVO: " + $0 } ?? "Sin tarjeta: entra en LIVE con tu tarjeta AVO (enlace o código + clave).")
                    .font(.footnote).foregroundStyle(Avo.textDim)
                HStack {
                    Button("Ver mi nube") { Task { @MainActor in await loadCloud() } }
                        .buttonStyle(.avoPrimary).disabled(cloudBusy)
                    Button("Descargar todos") { Task { @MainActor in await downloadCloud(cloudItems) } }
                        .buttonStyle(.avoSecondary).disabled(cloudBusy || cloudItems.isEmpty)
                }
                Text(cloudState).font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                ForEach(cloudItems) { (it: CloudItem) in
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ServerView.cloudTitle(it)).font(.footnote.weight(.semibold)).foregroundStyle(Avo.silver)
                            Text(ServerView.cloudDetail(it)).font(.caption).foregroundStyle(Avo.textDim)
                        }
                        Spacer()
                        Button("Importar") { Task { @MainActor in await downloadCloud([it]) } }
                            .buttonStyle(.avoSecondary).disabled(cloudBusy)
                    }
                }
                Text("El Android sube cada entrenamiento verificado con el reloj (Compartir › Nube AVO). Aquí se descargan, se comprueba el SHA-256 y se importan con las mismas validaciones que un .avo.")
                    .font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
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
                Text("La Nube AVO (Firebase Storage, docs/NUBE_SESIONES.md) ya da el listado y la descarga con hash de tus entrenamientos. El panel web propio sigue pendiente (windows/docs/SERVIDOR_CONTRATO_PENDIENTE.md).")
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

    static func cloudTitle(_ it: CloudItem) -> String {
        let horse: String = it.horseName.isEmpty ? "Sin caballo" : it.horseName
        if it.startRtcMs <= 0 { return horse }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "dd/MM/yyyy HH:mm"
        return f.string(from: Date(timeIntervalSince1970: Double(it.startRtcMs) / 1000)) + " · " + horse
    }

    static func cloudDetail(_ it: CloudItem) -> String {
        var parts: [String] = []
        if !it.riderName.isEmpty { parts.append(it.riderName) }
        if let d = it.distanceM { parts.append(DotNetFormat.custom(d / 1000, "0.00", spanish: true) + " km") }
        parts.append(DotNetFormat.custom(Double(it.size) / 1_048_576, "0.0", spanish: true) + " MB")
        parts.append(it.sessionId.isEmpty ? it.fileName : it.sessionId)
        return parts.joined(separator: " · ")
    }

    @MainActor
    private func loadCloud() async {
        cloudBusy = true
        defer { cloudBusy = false }
        guard await app.live.ensureSignedIn(), let code = app.live.signedCode else {
            cloudState = "Entra primero en LIVE con tu tarjeta AVO."
            return
        }
        cloudState = "Consultando la nube…"
        do {
            cloudItems = try await app.live.cloud.list(code: code)
            cloudState = cloudItems.isEmpty ? "La nube está vacía (el Android sube los entrenamientos verificados)" : "\(cloudItems.count) entrenamientos en la nube"
        } catch {
            cloudState = error.localizedDescription
            app.log.warn("nube", "Listado fallido", error)
        }
    }

    @MainActor
    private func downloadCloud(_ items: [CloudItem]) async {
        guard !items.isEmpty else { return }
        cloudBusy = true
        defer { cloudBusy = false }
        let target: String = AvoFiles.join(app.paths.root, "nube")
        var files: [String] = []
        for (i, it) in items.enumerated() {
            cloudState = "Descargando \(i + 1)/\(items.count): " + it.fileName
            do { files.append(try await app.live.cloud.download(it, targetDirectory: target)) }
            catch {
                cloudState = error.localizedDescription
                app.log.warn("nube", "Descarga fallida", error)
            }
        }
        if files.isEmpty { return }
        cloudState = "Validando e importando \(files.count)…"
        await app.importFiles(files)
        cloudState = "Importados \(files.count) de la nube"
        refreshTick += 1
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
