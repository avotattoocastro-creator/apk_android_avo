import SwiftUI
import Observation
import UIKit

// Replaces windows/AVO.Windows/ViewModels/MainViewModel.Usb.cs («Reloj USB»): iPadOS has no access to USB serial ports, so
// the trainings are downloaded over the watch's own Wi-Fi (firmware CHEST ≥ 3.7.4, protocol
// firmware/chest/V3_7_4_WIFI/PROTOCOLO_WIFI.md), like Android 2.3-wifi: authenticated Bluetooth link → WIFI_SYNC(start) →
// the iPad joins AVO_CHEST_XXXX → resumable HTTP download with SHA-256 check → Wi-Fi off. Each verified training is packed as
// an AVO-TRAINING-1 .avo (AvoPackageWriter, same as the Windows USB download) and imported into the library.

/// A training listed by the watch.
struct WatchTrainingRow: Identifiable {
    var id: String
    var ready: Bool
    var segments: Int
    var size: Int64
    var startRtcMs: Int64
    var activeMs: Int64
    var etag: String
    var downloaded: Bool = false
    var selected: Bool = false
    /// Download state of this training (Android names: Descargando · 45 %, Verificando…, Entrenamiento guardado ✓…).
    var state: String = ""
    var stateOk: Bool = true
    /// 0…1 while downloading, nil otherwise.
    var progress: Double? = nil

    var startDate: Date? {
        (startRtcMs > 946_684_800_000 && startRtcMs < 4_102_444_800_000) ? AvoTime.fromUnixMs(Double(startRtcMs)) : nil
    }
    var dateText: String { startDate.map { AvoTime.text($0) } ?? "Sin fecha" }
    var sizeText: String {
        if size < 1024 * 1024 { return AvoFormat.f(Double(size) / 1024.0, 0) + " KB" }
        return AvoFormat.f(Double(size) / (1024.0 * 1024.0), 1) + " MB"
    }
    var durationText: String { activeMs > 0 ? TimeText.clock(Double(activeMs) / 1000.0) : "—" }
    var readyText: String { ready ? "Cerrado" : "Sesión abierta" }
}

/// Entry of the index of trainings downloaded from a watch (same fields as Windows WatchLibraryEntry, indice_reloj.json).
struct WatchDownloadEntry {
    var device: String
    var id: String
    var etag: String
    var size: Int64
    var sha256: String
    var package: String
    var downloadedAt: Date

    func json() -> [String: Any] {
        return ["Device": device, "Id": id, "Etag": etag, "Size": NSNumber(value: size), "Sha256": sha256, "Package": package,
                "DownloadedAt": StableJson.date(downloadedAt)]
    }
    static func from(_ o: [String: Any]) -> WatchDownloadEntry? {
        guard let id = AvoJSON.string(o, "Id"), let pkg = AvoJSON.string(o, "Package") else { return nil }
        let date: Date = AvoJSON.string(o, "DownloadedAt").flatMap { StableJson.parseDate($0) } ?? Date()
        return WatchDownloadEntry(device: AvoJSON.string(o, "Device") ?? "", id: id, etag: AvoJSON.string(o, "Etag") ?? "",
                                  size: Int64(AvoJSON.number(o, "Size") ?? 0), sha256: AvoJSON.string(o, "Sha256") ?? "",
                                  package: pkg, downloadedAt: date)
    }
}

/// State shared with the download callbacks (they run off the main thread). Every access holds the lock.
final class WatchWifiShared {
    private let lock = NSLock()
    let folder: String
    private let indexPath: String
    private var entries: [WatchDownloadEntry] = []
    private var remote: [String: RemoteTraining] = [:]
    private var imports: [String] = []
    private var seen: [RemoteTraining] = []
    private var device: String = ""
    private var firmware: String = ""

    init(folder: String) {
        self.folder = folder
        self.indexPath = AvoFiles.join(folder, "indice_reloj.json")
        if let d = AvoFiles.read(indexPath), let any = try? JSONSerialization.jsonObject(with: d), let arr = any as? [Any] {
            entries = arr.compactMap { ($0 as? [String: Any]).flatMap { WatchDownloadEntry.from($0) } }
        }
    }

    func setWatch(device: String, firmware: String) { lock.lock(); self.device = device; self.firmware = firmware; lock.unlock() }
    func setRemote(_ list: [RemoteTraining]) {
        lock.lock()
        for t in list { remote[t.id] = t }
        lock.unlock()
    }
    func noteSeen(_ t: RemoteTraining) { lock.lock(); seen.append(t); remote[t.id] = t; lock.unlock() }
    func takeSeen() -> [RemoteTraining] { lock.lock(); defer { lock.unlock() }; let s = seen; seen = []; return s }
    func takeImports() -> [String] { lock.lock(); defer { lock.unlock() }; let s = imports; imports = []; return s }

    /// The package of this training if it is still on disk.
    func downloaded(_ id: String) -> WatchDownloadEntry? {
        lock.lock(); defer { lock.unlock() }
        return entries.first { $0.id == id && (device.isEmpty || $0.device.caseInsensitiveCompare(device) == .orderedSame)
            && AvoFiles.exists(AvoFiles.join(folder, $0.package)) }
    }

    /// Sink of the coordinator: packs the verified P00n.avr folder as .avo, records it and queues it for import.
    func packageVerified(id: String, dir: String, sha: String, bytes: Int64) throws {
        lock.lock()
        let dev = device, fw = firmware
        let t: RemoteTraining? = remote[id]
        lock.unlock()
        let segs: [String] = WifiDownloader.segFiles(dir)
        if segs.isEmpty { throw WifiIoError("No hay segmentos descargados de \(id)") }
        let name: String = AvoPackageWriter.packageName(device: dev.isEmpty ? "reloj" : dev, id: id)
        let target: String = AvoFiles.join(folder, name)
        let meta = AvoPackageWriter.Meta(sessionId: id, sha256: sha, watchDevice: dev, watchFirmware: fw,
                                         startRtcMs: t?.startRtcMs ?? 0, activeMs: t?.activeMs ?? 0, source: "wifi-ipad")
        try AvoPackageWriter.write(target: target, meta: meta, segments: segs)
        let e = WatchDownloadEntry(device: dev, id: id, etag: t?.etag ?? "", size: bytes, sha256: sha, package: name, downloadedAt: Date())
        lock.lock()
        entries.removeAll { $0.id == id && $0.device.caseInsensitiveCompare(dev) == .orderedSame }
        entries.append(e)
        let all: [[String: Any]] = entries.map { $0.json() }
        imports.append(target)
        lock.unlock()
        let data = (try? JSONSerialization.data(withJSONObject: all, options: [.prettyPrinted, .withoutEscapingSlashes])) ?? Data("[]".utf8)
        try? StableJson.writeAtomic(data, to: indexPath)
        try? FileManager.default.removeItem(atPath: dir)     // the verified copy now lives in the .avo
    }
}

@Observable
final class WatchWifiModel {
    @ObservationIgnored unowned let app: AppModel
    @ObservationIgnored private var conn: IosWatchConnection? = nil
    @ObservationIgnored private var manager: WifiSyncManager? = nil
    @ObservationIgnored let shared: WatchWifiShared

    var connected: Bool = false
    var connecting: Bool = false
    var busy: Bool = false
    var watchText: String = "Sin conectar"
    var supportsWifi: Bool = false
    var unsupportedText: String = ""
    var status: String = "Conecta con el reloj por Bluetooth para ver sus entrenamientos."
    var statusOk: Bool = true
    var phase: String = ""
    var overall: WifiSyncProgress = WifiSyncProgress()
    var rows: [WatchTrainingRow] = []
    var listed: Bool = false
    var confirm: GeoConfirm? = nil
    @ObservationIgnored private var confirmCont: CheckedContinuation<Bool, Never>? = nil

    init(app: AppModel) {
        self.app = app
        self.shared = WatchWifiShared(folder: AvoFiles.join(app.paths.root, "reloj"))
    }

    // ---------------------------------------------------------------- contract
    func sessionChanged() { refreshDownloaded() }
    func pageShown() { refreshDownloaded() }

    private var downloadDir: String { AvoFiles.join(shared.folder, "descargas") }

    func refreshDownloaded() {
        let loaded = Set<String>(app.sessions.map { $0.id })
        var r = rows
        for i in r.indices { r[i].downloaded = shared.downloaded(r[i].id) != nil || loaded.contains(r[i].id) }
        rows = r
    }

    var selectedCount: Int { rows.filter { $0.selected && $0.ready }.count }
    var canDownload: Bool { connected && supportsWifi && !busy }

    // ---------------------------------------------------------------- confirmation
    @MainActor
    func ask(_ title: String, _ message: String, _ okLabel: String) async -> Bool {
        if let c = confirmCont { confirmCont = nil; c.resume(returning: false) }
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            self.confirmCont = c
            self.confirm = GeoConfirm(title: title, message: message, okLabel: okLabel)
        }
    }

    func answer(_ yes: Bool) {
        let c = confirmCont
        confirmCont = nil
        confirm = nil
        c?.resume(returning: yes)
    }

    // ---------------------------------------------------------------- Bluetooth
    @MainActor
    func connect() async {
        if connecting || busy { return }
        disconnect()
        connecting = true
        statusOk = true
        let report: (String) -> Void = { [weak self] (m: String) in
            Task { @MainActor in
                self?.status = m
                self?.app.status = m
            }
        }
        do {
            let target: BleWatchFound? = try await WatchPicker.pick(progress: report, ask: { [weak self] (t: String, m: String, ok: String) async -> Bool in
                guard let self = self else { return false }
                return await self.ask(t, m, ok)
            })
            guard let w = target else {
                connecting = false
                status = "Conexión cancelada."
                return
            }
            let c = try await IosWatchConnection.open(target: w, clientName: WatchPicker.clientName, progress: report)
            let client = c.client
            c.transport.onDisconnected = { [weak self, weak client] in
                client?.onDisconnected()
                Task { @MainActor in self?.linkLost() }
            }
            conn = c
            shared.setWatch(device: c.info.deviceId, firmware: c.info.firmware)
            let log = app.log
            manager = WifiSyncManager(client: { [weak self] in self?.conn?.client },
                                      info: { [weak self] in self?.conn?.info },
                                      isRecording: { false },
                                      trainingsDir: { [weak self] in self?.downloadDir ?? NSTemporaryDirectory() },
                                      sink: { [weak self] (id: String, dir: String, sha: String, bytes: Int64) async throws -> Void in
                                          guard let self = self else { return }
                                          try self.shared.packageVerified(id: id, dir: dir, sha: sha, bytes: bytes)
                                      },
                                      log: { (m: String) in log.info("wifi", m) })
            manager?.coordinator.onProgress = { [weak self] (p: WifiSyncProgress) in
                Task { @MainActor in self?.applyProgress(p) }
            }
            connected = true
            watchText = "\(w.name) · pecho \(c.info.firmware) · \(c.info.deviceId)"
            supportsWifi = c.info.supportsWifiSync && (manager?.supported ?? false)
            if !c.info.supportsWifiSync {
                unsupportedText = "El reloj tiene el firmware \(c.info.firmware), sin descarga por Wi-Fi. Hace falta CHEST 3.7.4 o posterior (instálalo con AVO Update). Mientras tanto, exporta el entrenamiento desde la app Android como .avo y ábrelo aquí."
            } else {
                unsupportedText = manager?.unsupportedReason() ?? ""
            }
            status = supportsWifi ? "Conectado. Pulsa «Ver entrenamientos del reloj» o «Descargar todo»." : unsupportedText
            statusOk = supportsWifi
            app.log.info("wifi", "reloj conectado", ["fw": c.info.firmware, "wifi": supportsWifi] as [String: Any])
        } catch {
            status = error.localizedDescription
            statusOk = false
            app.log.warn("wifi", error.localizedDescription, error)
        }
        connecting = false
    }

    func disconnect() {
        manager?.cancel()
        conn?.close()
        conn = nil
        manager = nil
        connected = false
        supportsWifi = false
        watchText = "Sin conectar"
    }

    private func linkLost() {
        if conn == nil { return }
        conn = nil
        connected = false
        supportsWifi = false
        watchText = "Sin conectar"
        if !busy {
            status = "El reloj se desconectó. Vuelve a conectar para seguir."
            statusOk = false
        }
    }

    // ---------------------------------------------------------------- list
    static func refusedText(_ reason: String) -> String {
        switch reason {
        case "grabando": return "El reloj está grabando: termina la sesión en el reloj y vuelve a intentarlo."
        case "batería baja": return "Batería del reloj por debajo del 15 %: ponlo a cargar o cárgalo antes de descargar por Wi-Fi."
        case "sin microSD": return "El reloj no tiene la tarjeta microSD."
        case "ocupado": return "El reloj está ocupado; vuelve a intentarlo en unos segundos."
        case "pendiente": return "Pendiente: se reanuda en la próxima descarga (lo ya recibido se conserva)."
        default: return reason
        }
    }

    /// Turns on the watch Wi-Fi, joins it, reads /api/v1/trainings and turns the Wi-Fi off again.
    @MainActor
    func readList() async {
        guard let m = manager, connected else { status = "Conecta antes con el reloj por Bluetooth."; statusOk = false; return }
        if !supportsWifi { status = unsupportedText; statusOk = false; return }
        if busy { return }
        busy = true
        statusOk = true
        phase = WifiSyncState.wifiStarting.texto
        status = "Pidiendo al reloj que active su Wi-Fi…"
        let ctl: BleWifiControl = m.control
        var failure: String? = nil
        do {
            let r: WifiStartResult = try await ctl.start()
            switch r {
            case .ok(let creds):
                phase = WifiSyncState.connecting.texto
                status = "Uniendo el iPad a la red \(creds.ssid)… (la primera vez iOS pide permiso)"
                let log = app.log
                let connector = HotspotWifiConnector(log: { (s: String) in log.info("wifi", s) })
                if let link = await connector.connect(creds) {
                    phase = WifiSyncState.discovering.texto
                    var list: [RemoteTraining] = []
                    do { list = try await link.http.list() } catch { failure = error.localizedDescription }
                    await link.close()
                    await ctl.stop()
                    if conn != nil { ctl.bootGuard.clearAttempt() }
                    if failure == nil { applyList(list) }
                } else {
                    await ctl.stop()
                    failure = "El iPad no pudo unirse a la red Wi-Fi del reloj (\(creds.ssid)). Acepta el permiso de iOS, acerca el iPad al reloj y vuelve a intentarlo."
                }
            case .refused(let reason, _):
                failure = WatchWifiModel.refusedText(reason)
            case .unsupported:
                failure = unsupportedText.isEmpty ? "El reloj no admite descarga por Wi-Fi." : unsupportedText
            }
        } catch {
            failure = error.localizedDescription
        }
        phase = ""
        busy = false
        if let f = failure {
            status = f
            statusOk = false
        } else {
            let ready = rows.filter { $0.ready }.count
            let pending = rows.filter { $0.ready && !$0.downloaded }.count
            status = rows.isEmpty ? "El reloj no tiene entrenamientos." : "\(rows.count) entrenamiento(s) en el reloj · \(ready) cerrados · \(pending) sin descargar"
            statusOk = true
        }
    }

    private func applyList(_ list: [RemoteTraining]) {
        shared.setRemote(list)
        let old: [String: WatchTrainingRow] = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let loaded = Set<String>(app.sessions.map { $0.id })
        var out: [WatchTrainingRow] = []
        for t in list {
            var r = WatchTrainingRow(id: t.id, ready: t.ready, segments: t.segments, size: t.size, startRtcMs: t.startRtcMs,
                                     activeMs: t.activeMs, etag: t.etag)
            r.downloaded = shared.downloaded(t.id) != nil || loaded.contains(t.id)
            if let o = old[t.id] {
                r.selected = o.selected
                r.state = o.state
                r.stateOk = o.stateOk
            }
            if r.state.isEmpty { r.state = !t.ready ? "Sesión abierta en el reloj" : (r.downloaded ? "Ya descargado" : "Sin descargar") }
            out.append(r)
        }
        rows = out.sorted { $0.startRtcMs > $1.startRtcMs }
        listed = true
    }

    func toggle(_ id: String) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[i].selected.toggle()
    }

    func selectAllPending() {
        var r = rows
        for i in r.indices { r[i].selected = r[i].ready && !r[i].downloaded }
        rows = r
    }

    // ---------------------------------------------------------------- download
    private func setRow(_ id: String, _ change: (inout WatchTrainingRow) -> Void) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        var r = rows[i]
        change(&r)
        rows[i] = r
    }

    private func applyProgress(_ p: WifiSyncProgress) {
        overall = p
        phase = p.state == .idle || p.state == .cleanup ? "" : p.label
        guard let id = p.sessionId else { return }
        setRow(id) { (r: inout WatchTrainingRow) in
            switch p.state {
            case .downloading:
                r.state = "Descargando · \(p.percent) %"
                r.progress = p.total > 0 ? Double(p.bytes) / Double(p.total) : 0
                r.stateOk = true
            case .verifying:
                r.state = WifiSyncState.verifying.texto
                r.progress = 1
            case .completed:
                r.state = WifiSyncState.completed.texto
                r.progress = nil
                r.downloaded = true
                r.selected = false
            default:
                r.state = p.label
            }
        }
    }

    @MainActor
    func downloadSelected() async {
        let ids: [String] = rows.filter { $0.selected && $0.ready }.map { $0.id }
        if ids.isEmpty { status = "Marca antes los entrenamientos que quieres descargar."; statusOk = false; return }
        await runPass(ids: ids)
    }

    @MainActor
    func downloadAll() async {
        await runPass(ids: nil)
    }

    func cancel() {
        manager?.cancel()
        status = "Cancelando… (lo ya recibido se conserva y se reanuda la próxima vez)"
    }

    @MainActor
    private func runPass(ids: [String]?) async {
        guard let m = manager, connected else { status = "Conecta antes con el reloj por Bluetooth."; statusOk = false; return }
        if !supportsWifi { status = unsupportedText; statusOk = false; return }
        if busy { return }
        busy = true
        statusOk = true
        status = "Pidiendo al reloj que active su Wi-Fi…"
        if let ids = ids {
            for id in ids { setRow(id) { $0.state = "Pendiente"; $0.stateOk = true; $0.progress = nil } }
        }
        let known = Set<String>(rows.filter { $0.downloaded }.map { $0.id })
        let loaded = Set<String>(app.sessions.map { $0.id })
        let sharedRef = shared
        var report: WifiSyncReport? = nil
        var failure: String? = nil
        do {
            if let ids = ids {
                let pending: [(String, String?)] = ids.map { (id: String) -> (String, String?) in (id, nil) }
                report = try await m.sync(pending)
            } else {
                report = try await m.syncAvailable { (t: RemoteTraining) -> String?? in
                    sharedRef.noteSeen(t)
                    if known.contains(t.id) || loaded.contains(t.id) || sharedRef.downloaded(t.id) != nil { return nil }
                    let download: String?? = .some(nil)
                    return download
                }
            }
        } catch {
            failure = error.localizedDescription
        }
        // trainings listed during «Descargar todo»
        let seen: [RemoteTraining] = shared.takeSeen()
        if ids == nil && !seen.isEmpty {
            var merged: [RemoteTraining] = seen
            for r in rows where !seen.contains(where: { $0.id == r.id }) {
                merged.append(RemoteTraining(id: r.id, ready: r.ready, segments: r.segments, size: r.size,
                                             startRtcMs: r.startRtcMs, activeMs: r.activeMs, etag: r.etag))
            }
            applyList(merged)
        }
        // import what was verified and packed
        let paths: [String] = shared.takeImports()
        if !paths.isEmpty {
            status = "Importando \(paths.count) entrenamiento(s)…"
            await app.importFiles(paths)
        }
        busy = false
        phase = ""
        refreshDownloaded()
        if let f = failure {
            status = "Descarga interrumpida: " + f + " Lo ya recibido se conserva y se reanuda la próxima vez."
            statusOk = false
            return
        }
        guard let rep = report else { return }
        for (id, reason) in rep.failed where id != "*" {
            setRow(id) { (r: inout WatchTrainingRow) in
                r.state = "Pendiente: " + WatchWifiModel.refusedText(reason)
                r.stateOk = false
                r.progress = nil
            }
        }
        if rep.skipped {
            status = m.paused ? "Descarga por Wi-Fi en pausa." : "Ya hay una descarga en curso."
            statusOk = false
        } else if !rep.fallbackBle.isEmpty {
            status = "No se pudo usar el Wi-Fi del reloj: el iPad no se unió a su red AVO_CHEST_… o el reloj lo rechazó. Acepta el permiso de iOS, acerca el iPad al reloj y vuelve a intentarlo."
            statusOk = false
        } else if let general = rep.failed["*"] {
            status = "No se pudo leer la lista del reloj: " + general
            statusOk = false
        } else if !rep.failed.isEmpty {
            let reasons: [String] = Array(Set(rep.failed.values.map { WatchWifiModel.refusedText($0) })).sorted()
            status = "\(rep.verified.count) descargado(s) y verificado(s) · \(rep.failed.count) pendiente(s): " + reasons.joined(separator: " · ")
            statusOk = rep.verified.count > 0
        } else if rep.verified.isEmpty {
            status = ids == nil ? "No hay entrenamientos nuevos en el reloj." : "Nada que descargar."
            statusOk = true
        } else {
            status = "\(rep.verified.count) entrenamiento(s) descargado(s), verificado(s) (SHA-256) e importado(s)."
            statusOk = true
            if app.page == .home { app.page = .sessions }
        }
        app.status = status
    }
}
