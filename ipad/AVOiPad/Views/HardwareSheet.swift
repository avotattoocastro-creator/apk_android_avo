import SwiftUI

/// «Equipo conectado» (trainer's sketch 14/11/2026): window that manages the hardware linked by Bluetooth. It only lists
/// what the link really reports (name, iPad identifier, time connected) and leads to the pages that work with the watch;
/// battery, GNSS or firmware figures are not shown here until the watch protocol reports them on this link.
struct HardwareSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var status: WatchStatusFull? = nil
    @State private var reading: Bool = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if app.bleLinks.isEmpty {
                        AvoCard { AvoNoData(text: "No hay ningún equipo conectado por Bluetooth") }
                    }
                    ForEach(app.bleLinks) { (l: BleLink) in linkCard(l) }
                    if !app.bleLinks.isEmpty { modules }
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
        // battery and modules from GET_STATUS, refreshed every 5 s while the window is open
        .task {
            while !Task.isCancelled {
                let st: WatchStatusFull? = await app.watchWifi.readStatus()
                status = st
                reading = false
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    // trainer's sketch 14/11/2026: «% batería» and the three modules: Chaleco · Espalda · Cincha
    private var modules: some View {
        HStack(alignment: .top, spacing: 12) {
            module("Chaleco", "Reloj de pecho", icon: "applewatch",
                   ok: status != nil,
                   value: status.map { s in s.batteryPct.map { "\($0) %" } ?? "—" } ?? "—",
                   detail: status.map { s in
                       (s.charging ? "Cargando · " : "") + "\(s.batteryMv) mV" + (s.recording ? " · grabando" : "")
                   } ?? (reading ? "Leyendo estado…" : "Sin estado del reloj"))
            module("Espalda", "GNSS RTK", icon: "location.north.circle",
                   ok: status?.backLink == true,
                   value: status.map { $0.backLink ? "Enlazada" : "Sin enlace" } ?? "—",
                   detail: status.map { $0.backLink ? ($0.rtcmFlowing ? "Correcciones RTCM llegando" : "Sin correcciones RTCM") : "No responde al reloj" }
                       ?? "Sin estado del reloj")
            module("Cincha", "IMU", icon: "waveform.path.ecg",
                   ok: status?.girth == true,
                   value: status.map { $0.girth ? "Conectada" : "Sin conectar" } ?? "—",
                   detail: status.map { $0.girth ? "Enviando datos al reloj" : "No llega al reloj" } ?? "Sin estado del reloj")
        }
    }

    private func module(_ title: String, _ subtitle: String, icon: String, ok: Bool, value: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 26, weight: .light)).foregroundStyle(ok ? Avo.ok : Avo.textDim)
            Text(value).font(.title2.weight(.light)).foregroundStyle(ok ? Avo.text : Avo.textDim).lineLimit(1).minimumScaleFactor(0.6)
            Text(title.uppercased()).font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(Avo.silver)
            Text(subtitle).font(.caption2).foregroundStyle(Avo.textDim)
            Text(detail).font(.caption2).foregroundStyle(Avo.textDim).multilineTextAlignment(.center).lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 170)
        .background(Avo.cardBrush, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ok ? Avo.ok.opacity(0.6) : Avo.line, lineWidth: 1))
    }

    private func linkCard(_ l: BleLink) -> some View {
        AvoCard {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "applewatch.radiowaves.left.and.right").font(.system(size: 30, weight: .light))
                    .foregroundStyle(Avo.ok).frame(width: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(l.name).font(.headline).foregroundStyle(Avo.text)
                    // trainer's sketch 14/11/2026: «% batería» in place of the time and identifier
                    HStack(spacing: 6) {
                        Image(systemName: Self.batteryIcon(status?.batteryPct, charging: status?.charging == true))
                            .foregroundStyle((status?.batteryPct ?? 100) < 15 ? Avo.bad : Avo.ok)
                        Text(status?.batteryPct.map { "Batería \($0) %" } ?? (reading ? "Leyendo batería…" : "Batería sin datos"))
                            .font(.callout.weight(.semibold)).foregroundStyle(Avo.text)
                    }
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

    static func batteryIcon(_ pct: Int?, charging: Bool) -> String {
        if charging { return "battery.100.bolt" }
        guard let p = pct else { return "battery.0" }
        switch p {
        case 88...: return "battery.100"
        case 63..<88: return "battery.75"
        case 38..<63: return "battery.50"
        case 13..<38: return "battery.25"
        default: return "battery.0"
        }
    }

    private func go(_ p: Page) {
        dismiss()
        app.page = p
    }
}
