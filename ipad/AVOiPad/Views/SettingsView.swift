import SwiftUI
import UniformTypeIdentifiers

/// «Configuración» (trainer's sketch 13/11/2026): appearance (dark / light), maintenance of the trainings stored on the
/// iPad (moved here from «Entrenamientos») and access to the AVO server.
struct SettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        SettingsContent(model: app.trainingList)
    }
}

private struct SettingsContent: View {
    @Environment(AppModel.self) private var app
    @Bindable var model: TrainingListModel
    @AppStorage(AvoAppearance.key) private var appearance: String = AvoAppearance.dark.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AvoPageTitle(title: "Configuración", subtitle: "Mantenimiento de los entrenamientos del iPad y conexiones")
                AvoCard(title: "Apariencia", subtitle: "Colores de toda la app; se aplica al momento") {
                    Picker("Modo", selection: $appearance) {
                        ForEach(AvoAppearance.allCases) { (m: AvoAppearance) in
                            Label(m.title, systemImage: m == .dark ? "moon.fill" : "sun.max.fill").tag(m.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 360)
                    .accessibilityIdentifier("settings.appearance")
                }
                AvoCard(title: "Entrenamientos en el iPad",
                        subtitle: "Recuperar archivos, buscar en carpetas y copiar a la carpeta AVO Horse de Archivos") {
                    VStack(alignment: .leading, spacing: 10) {
                        settingButton("arrow.triangle.2.circlepath", "Buscar entrenamientos perdidos",
                                      "Revisa el iPad y recupera los .avo / .avr que no están en la lista", primary: true) {
                            Task { @MainActor in await model.scanDevice() }
                        }
                        .disabled(model.scanning || app.busy)
                        .accessibilityIdentifier("settings.recover")
                        settingButton("folder.badge.questionmark", "Buscar en una carpeta…",
                                      "Elige una carpeta y se importan sus entrenamientos, sin duplicados") {
                            model.pickingFolder = true
                        }
                        .disabled(model.scanning || app.busy)
                        settingButton("square.and.arrow.up.on.square", "Exportar \(app.sessions.count) a AVO Horse",
                                      "Un .avo por entrenamiento en Archivos › En mi iPad › AVO Horse") {
                            Task { @MainActor in await app.exportTrainingsAndReport(app.sessions) }
                        }
                        .disabled(app.sessions.isEmpty || app.busy)
                        .accessibilityIdentifier("settings.export")
                        settingButton("externaldrive.badge.checkmark", "Copiar todo a AVO Horse",
                                      "Copia de seguridad de todos los archivos del iPad") {
                            Task { @MainActor in await app.syncDocumentsAndReport() }
                        }
                        .disabled(app.busy)
                        .accessibilityIdentifier("settings.syncDocs")
                        if model.scanning || !model.scanStatus.isEmpty {
                            HStack(spacing: 6) {
                                if model.scanning { ProgressView().controlSize(.mini) }
                                Text(model.scanStatus).font(.caption).foregroundStyle(Avo.cyan).lineLimit(3)
                            }
                        }
                    }
                }
                AvoCard(title: "Reloj y conexiones", subtitle: "Reloj de pecho, geocercas y servidor") {
                    VStack(alignment: .leading, spacing: 10) {
                        settingButton("wifi", "Reloj Wi-Fi", "Descargar los entrenamientos del reloj de pecho (Wi-Fi o Bluetooth)") {
                            app.page = .watchWifi
                        }
                        .accessibilityIdentifier("nav.WatchWifi")
                        settingButton("flag", "Geocercas y líneas", "Zonas de la pista y líneas de salida y meta") {
                            app.page = .geofences
                        }
                        .accessibilityIdentifier("nav.Geofences")
                        settingButton("server.rack", "Servidor AVO", "Panel web y descarga HTTPS de .avo") {
                            app.page = .server
                        }
                        .accessibilityIdentifier("nav.Server")
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Avo.bg)
        .accessibilityIdentifier("page.settings")
        .fileImporter(isPresented: $model.pickingFolder, allowedContentTypes: [UTType.folder], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let u = urls.first { Task { @MainActor in await model.scanFolder(u) } }
            case .failure(let error):
                app.fail(error)
            }
        }
        .sheet(isPresented: Binding(get: { model.report != nil }, set: { if !$0 { model.report = nil } })) {
            if let r = model.report {
                TrainingRecoverySheet(report: r) { model.report = nil }
                    .avoColorScheme()
            }
        }
    }

    private func settingButton(_ icon: String, _ title: String, _ caption: String, primary: Bool = false,
                               perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(primary ? Avo.red : Avo.redSoft).frame(width: 38, height: 38)
                    Image(systemName: icon).font(.system(size: 15)).foregroundStyle(primary ? Avo.text : Avo.redLight)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.callout.weight(.semibold)).foregroundStyle(Avo.text)
                    Text(caption).font(.caption2).foregroundStyle(Avo.textDim).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Avo.textDim)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Avo.surface2, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
