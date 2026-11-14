import SwiftUI

/// «Equipo conectado» (trainer's sketch 14/11/2026): window that manages the hardware linked by Bluetooth. It only lists
/// what the link really reports (name, iPad identifier, time connected) and leads to the pages that work with the watch;
/// battery, GNSS or firmware figures are not shown here until the watch protocol reports them on this link.
struct HardwareSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if app.bleLinks.isEmpty {
                        AvoCard { AvoNoData(text: "No hay ningún equipo conectado por Bluetooth") }
                    }
                    ForEach(app.bleLinks) { (l: BleLink) in linkCard(l) }
                    AvoCard(title: "Gestionar") {
                        action("Reloj Wi-Fi y descargas", "wifi", "Red Wi-Fi del reloj, sincronización y descarga de entrenamientos") {
                            go(.watchWifi)
                        }
                        action("Geocercas y líneas", "mappin.and.ellipse", "Enviar al reloj las geocercas y líneas de meta") {
                            go(.geofences)
                        }
                        action("Configuración", "gearshape", "Ajustes de la app y del servidor AVO") { go(.settings) }
                    }
                }
                .padding(16)
            }
            .background(Avo.bg)
            .navigationTitle("Equipo conectado")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { dismiss() } }
            }
        }
        .accessibilityIdentifier("hardware.sheet")
    }

    private func linkCard(_ l: BleLink) -> some View {
        AvoCard {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "applewatch.radiowaves.left.and.right").font(.system(size: 30, weight: .light))
                    .foregroundStyle(Avo.ok).frame(width: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(l.name).font(.headline).foregroundStyle(Avo.text)
                    Text("Conectado desde las \(MadridTime.format(l.since, "HH:mm:ss"))").font(.caption).foregroundStyle(Avo.textDim)
                    Text("Identificador en este iPad: \(l.id.uuidString)").font(.caption2.monospaced()).foregroundStyle(Avo.textDim)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button(role: .destructive) { IosBleCentral.shared.disconnect(l.id) } label: {
                    Label("Desconectar", systemImage: "xmark.circle")
                }
                .buttonStyle(.avoSecondary)
                .foregroundStyle(Avo.bad)
            }
        }
    }

    private func action(_ title: String, _ icon: String, _ detail: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 24).foregroundStyle(Avo.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.callout.weight(.semibold)).foregroundStyle(Avo.text)
                    Text(detail).font(.caption).foregroundStyle(Avo.textDim)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Avo.textDim)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func go(_ p: Page) {
        dismiss()
        app.page = p
    }
}
