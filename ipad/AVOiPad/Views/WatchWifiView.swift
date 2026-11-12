import SwiftUI

/// «Reloj Wi-Fi»: replaces the Windows «Reloj USB» page (iPadOS has no USB serial access). Downloads the trainings of the
/// chest watch over its own Wi-Fi network (or over Bluetooth when Wi-Fi is not available), verifies them (SHA-256) and
/// imports them.
struct WatchWifiView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let w: WatchWifiModel = app.watchWifi
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AvoPageTitle(title: "Reloj Wi-Fi",
                             subtitle: "Descarga los entrenamientos del reloj de pecho por su propia red Wi-Fi o, si no es posible, por Bluetooth (sustituye al cable USB de Windows)")
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        WatchWifiConnectCard(w: w).frame(maxWidth: .infinity)
                        WatchWifiHowCard().frame(width: 380)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        WatchWifiConnectCard(w: w)
                        WatchWifiHowCard()
                    }
                }
                WatchWifiListCard(w: w)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Avo.bg)
        .onAppear { w.pageShown() }
        .alert(w.confirm?.title ?? "",
               isPresented: Binding(get: { w.confirm != nil }, set: { if !$0 { w.answer(false) } }),
               presenting: w.confirm) { c in
            Button("Cancelar", role: .cancel) { w.answer(false) }
            Button(c.okLabel) { w.answer(true) }
        } message: { c in
            Text(c.message)
        }
    }
}

private struct WatchWifiConnectCard: View {
    let w: WatchWifiModel

    var body: some View {
        AvoCard(title: "Reloj de pecho", subtitle: w.watchText) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    if w.connected {
                        Button("Desconectar") { w.disconnect() }
                            .buttonStyle(.avoSecondary)
                            .disabled(w.busy)
                    } else {
                        Button {
                            Task { await w.connect() }
                        } label: {
                            Label("Conectar por Bluetooth", systemImage: "antenna.radiowaves.left.and.right")
                        }
                        .buttonStyle(.avoPrimary)
                        .disabled(w.connecting)
                        .accessibilityIdentifier("wifi.connect")
                    }
                    if w.connecting { ProgressView().tint(Avo.red) }
                    Spacer(minLength: 0)
                    if w.connected {
                        AvoPill(text: !w.supportsWifi ? "SOLO BLUETOOTH" : (w.wifiFailure != nil ? "WI-FI FALLÓ" : "WI-FI DISPONIBLE"),
                                color: w.supportsWifi && w.wifiFailure == nil ? Avo.ok : Avo.warn)
                    }
                }
                if w.connected && w.supportsWifi, let f = w.wifiFailure {
                    Label("Wi-Fi: " + f, systemImage: "wifi.exclamationmark")
                        .font(.footnote).foregroundStyle(Avo.warn).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("wifi.failure")
                }
                if w.connected && !w.supportsWifi && !w.unsupportedText.isEmpty {
                    Label(w.unsupportedText, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(Avo.warn).fixedSize(horizontal: false, vertical: true)
                }
                if w.connected && w.wifiBlocked && !w.supportsWifi {
                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            w.retryWifi()
                        } label: {
                            Label("Volver a intentar el Wi-Fi", systemImage: "wifi.exclamationmark")
                        }
                        .buttonStyle(.avoSecondary)
                        .disabled(w.busy)
                        .accessibilityIdentifier("wifi.retryWifi")
                        Text(w.retryWifiNote)
                            .font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { actionButtons }
                    VStack(alignment: .leading, spacing: 8) { actionButtons }
                }
                if w.busy {
                    VStack(alignment: .leading, spacing: 6) {
                        if !w.transport.isEmpty {
                            AvoPill(text: w.transport == "Bluetooth" ? "POR BLUETOOTH (MÁS LENTO)" : "POR WI-FI",
                                    color: w.transport == "Bluetooth" ? Avo.warn : Avo.ok)
                        }
                        if !w.phase.isEmpty {
                            Text(w.phase).font(.footnote.weight(.semibold)).foregroundStyle(Avo.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if w.overall.state == .downloading && w.overall.total > 0 {
                            ProgressView(value: Double(w.overall.bytes), total: Double(max(1, w.overall.total))).tint(Avo.red)
                            Text("Entrenamiento \(min(w.overall.done + 1, max(1, w.overall.pending))) de \(max(1, w.overall.pending)) · \(w.overall.percent) % · \(w.overall.bytesText)"
                                 + (w.overall.speedText.isEmpty ? "" : " · " + w.overall.speedText))
                                .font(.caption).foregroundStyle(Avo.textDim)
                        } else {
                            ProgressView().tint(Avo.red)
                        }
                    }
                }
                Text(w.status).font(.footnote).foregroundStyle(w.statusOk ? Avo.cyan : Avo.warn)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("wifi.status")
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button("Ver entrenamientos del reloj") { Task { await w.readList() } }
            .buttonStyle(.avoSecondary)
            .disabled(!w.canDownload)
        Button("Descargar seleccionados (\(w.selectedCount))") { Task { await w.downloadSelected() } }
            .buttonStyle(.avoSecondary)
            .disabled(!w.canDownload || w.selectedCount == 0)
        Button("Descargar todo") { Task { await w.downloadAll() } }
            .buttonStyle(.avoPrimary)
            .disabled(!w.canDownload)
            .accessibilityIdentifier("wifi.downloadAll")
        if w.busy {
            Button("Cancelar") { w.cancel() }.buttonStyle(.avoSecondary)
        }
    }
}

private struct WatchWifiHowCard: View {
    var body: some View {
        AvoCard(title: "Cómo funciona") {
            VStack(alignment: .leading, spacing: 8) {
                step("1", "El iPad se conecta al reloj por Bluetooth. La primera vez el reloj pide pulsar BOOT para autorizar este iPad.")
                step("2", "El reloj enciende su propia red Wi-Fi AVO_CHEST_XXXX y el iPad se une a ella. La primera vez iOS pregunta «¿Conectarse a la red Wi-Fi AVO_CHEST_…?»: pulsa «Conectarse». Esa red no tiene Internet; al terminar el iPad vuelve a su Wi-Fi habitual.")
                step("·", "Si el Wi-Fi no está disponible o falla, se descarga por Bluetooth (más lento, unos kB/s) con la misma comprobación SHA-256.")
                step("3", "Se descarga cada entrenamiento (se reanuda si se corta), se comprueba su huella SHA-256 con el reloj y se importa. El original del reloj no se borra.")
                Divider().overlay(Avo.line)
                Label("El reloj no debe estar grabando (termina la sesión antes).", systemImage: "record.circle")
                    .font(.caption).foregroundStyle(Avo.textDim)
                Label("Batería del reloj al menos al 15 % (o conectado al cargador).", systemImage: "battery.25")
                    .font(.caption).foregroundStyle(Avo.textDim)
                Label("Wi-Fi: firmware del pecho CHEST 3.7.4 o posterior (si no, Bluetooth).", systemImage: "cpu")
                    .font(.caption).foregroundStyle(Avo.textDim)
                Label("Mantén la app abierta y el iPad cerca del reloj mientras descarga.", systemImage: "ipad")
                    .font(.caption).foregroundStyle(Avo.textDim)
                Label("Si el móvil está conectado al reloj, desconéctalo antes (el reloj admite una sola conexión Bluetooth).", systemImage: "iphone.slash")
                    .font(.caption).foregroundStyle(Avo.textDim)
            }
        }
    }

    private func step(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(n).font(.caption.weight(.bold)).foregroundStyle(.white)
                .frame(width: 20, height: 20).background(Avo.red, in: Circle())
            Text(text).font(.footnote).foregroundStyle(Avo.text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct WatchWifiListCard: View {
    let w: WatchWifiModel

    var body: some View {
        AvoCard(title: "Entrenamientos en el reloj", subtitle: w.listed ? "\(w.rows.count) en la microSD del reloj" : nil) {
            VStack(alignment: .leading, spacing: 8) {
                if w.rows.isEmpty {
                    AvoNoData(text: w.listed ? "El reloj no tiene entrenamientos."
                              : "Sin datos · conecta con el reloj y pulsa «Ver entrenamientos del reloj» (o «Descargar todo»).")
                } else {
                    HStack {
                        Button("Marcar los no descargados") { w.selectAllPending() }
                            .buttonStyle(.avoSecondary).disabled(w.busy)
                        Spacer()
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            WatchWifiHeader()
                            ForEach(w.rows) { r in
                                WatchWifiRowView(r: r, busy: w.busy) { w.toggle(r.id) }
                                Divider().overlay(Avo.line)
                            }
                        }
                    }
                }
            }
        }
    }
}

private enum WatchWifiCols {
    static let check: CGFloat = 30, id: CGFloat = 170, date: CGFloat = 130, ready: CGFloat = 120, size: CGFloat = 80,
               dur: CGFloat = 70, segs: CGFloat = 60, local: CGFloat = 110, state: CGFloat = 220
}

private struct WatchWifiHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("").frame(width: WatchWifiCols.check)
            cell("Entrenamiento", WatchWifiCols.id)
            cell("Fecha", WatchWifiCols.date)
            cell("Estado", WatchWifiCols.ready)
            cell("Tamaño", WatchWifiCols.size)
            cell("Duración", WatchWifiCols.dur)
            cell("Partes", WatchWifiCols.segs)
            cell("En el iPad", WatchWifiCols.local)
            cell("Descarga", WatchWifiCols.state)
        }
        .font(.caption2.weight(.semibold)).foregroundStyle(Avo.textDim)
        .padding(.vertical, 6)
    }
    private func cell(_ t: String, _ wd: CGFloat) -> some View { Text(t.uppercased()).frame(width: wd, alignment: .leading) }
}

private struct WatchWifiRowView: View {
    let r: WatchTrainingRow
    let busy: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggle) {
                Image(systemName: r.selected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(r.ready ? (r.selected ? Avo.red : Avo.silver) : Avo.line)
            }
            .buttonStyle(.plain)
            .disabled(!r.ready || busy)
            .frame(width: WatchWifiCols.check)
            Text(r.id).lineLimit(1).frame(width: WatchWifiCols.id, alignment: .leading)
            Text(r.dateText).lineLimit(1).frame(width: WatchWifiCols.date, alignment: .leading)
            HStack { AvoPill(text: r.readyText, color: r.ready ? Avo.ok : Avo.warn) }
                .frame(width: WatchWifiCols.ready, alignment: .leading)
            Text(r.sizeText).frame(width: WatchWifiCols.size, alignment: .leading)
            Text(r.durationText).frame(width: WatchWifiCols.dur, alignment: .leading)
            Text(String(r.segments)).frame(width: WatchWifiCols.segs, alignment: .leading)
            HStack {
                if r.downloaded { AvoPill(text: "DESCARGADO", color: Avo.cyan) } else { Text("—").foregroundStyle(Avo.textDim) }
            }
            .frame(width: WatchWifiCols.local, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(r.state).lineLimit(2).foregroundStyle(r.stateOk ? Avo.text : Avo.warn)
                if let p = r.progress { ProgressView(value: p).tint(Avo.red) }
            }
            .frame(width: WatchWifiCols.state, alignment: .leading)
        }
        .font(.footnote).foregroundStyle(Avo.text)
        .padding(.vertical, 6)
    }
}
