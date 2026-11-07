import Foundation
import NetworkExtension

// Joining the watch's own Wi-Fi network (SoftAP AVO_CHEST_XXXX, WPA2, no Internet) with NEHotspotConfiguration, and the
// iPad version of Android's AvoWifiSyncManager (app/wifi/AvoWifiSyncManager.kt, branch feature/avo-wifi-sync).
// This replaces the Windows "Reloj USB" download: iPadOS has no access to USB serial ports.
//
// Notes (iPadOS):
//  · The first join shows the system "Join Wi-Fi network?" dialog every time (joinOnce = true keeps the network only while
//    the app is in the foreground and does not leave it saved in Settings).
//  · NEHotspotConfiguration cannot pin the BSSID: the SSID is unique per watch (AVO_CHEST_ + device id).
//  · The network has no Internet: iOS keeps cellular/other routes for the rest of the system; the watch subnet is reached
//    over Wi-Fi (URLSessionWatchHttpClient disables cellular access for these requests).
//  · Requires the entitlement com.apple.developer.networking.HotspotConfiguration (AVOiPad.entitlements) and
//    NSLocalNetworkUsageDescription (Info.plist).

struct WifiJoinError: Error, LocalizedError {
    var message: String
    var userDenied: Bool = false
    init(_ message: String, userDenied: Bool = false) { self.message = message; self.userDenied = userDenied }
    var errorDescription: String? { message }
}

enum WifiJoin {
    /// Joins `ssid` with WPA2 `passphrase` (joinOnce). Already being on that network counts as success.
    static func join(ssid: String, passphrase: String) async throws {
        let cfg = NEHotspotConfiguration(ssid: ssid, passphrase: passphrase, isWEP: false)
        cfg.joinOnce = true
        let shot = AvoOneShot<Void>()
        NEHotspotConfigurationManager.shared.apply(cfg) { error in
            guard let error = error else { shot.succeed(()); return }
            let ns = error as NSError
            if ns.domain == NEHotspotConfigurationErrorDomain {
                let code = NEHotspotConfigurationError(rawValue: ns.code)
                switch code {
                case .some(.alreadyAssociated):
                    shot.succeed(())
                case .some(.userDenied):
                    shot.fail(WifiJoinError("No se aceptó unirse a la red Wi-Fi del reloj.", userDenied: true))
                case .some(.invalidWPAPassphrase), .some(.invalidSSID):
                    shot.fail(WifiJoinError("Datos de la red Wi-Fi del reloj no válidos."))
                default:
                    shot.fail(WifiJoinError("No se pudo conectar a la red Wi-Fi del reloj: " + error.localizedDescription))
                }
            } else {
                shot.fail(WifiJoinError("No se pudo conectar a la red Wi-Fi del reloj: " + error.localizedDescription))
            }
        }
        // 60 s: includes the time of the system dialog
        try await shot.value(timeoutMs: 60_000, onTimeout: { .failure(WifiJoinError("La red Wi-Fi del reloj no respondió a tiempo.")) })
    }

    /// Forgets the watch network (the iPad goes back to its usual Wi-Fi).
    static func leave(ssid: String) {
        NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid)
    }

    /// SSID currently joined, when iOS tells it (it may be nil without the Wi-Fi information entitlement).
    static func currentSsid() async -> String? {
        let shot = AvoOneShot<String?>()
        NEHotspotNetwork.fetchCurrent { net in shot.succeed(net?.ssid) }
        return (try? await shot.value(timeoutMs: 3000, onTimeout: { .success(nil) })) ?? nil
    }
}

/// WifiConnector over NEHotspotConfiguration + URLSession (Android: WifiNetworkSpecifier + Network.openConnection).
final class HotspotWifiConnector: WifiConnector {
    private let log: (String) -> Void
    private let makeClient: () -> WatchHttpClient

    init(log: @escaping (String) -> Void = { _ in }, makeClient: @escaping () -> WatchHttpClient = { URLSessionWatchHttpClient() }) {
        self.log = log
        self.makeClient = makeClient
    }

    private final class Link: WifiLink {
        let http: WatchHttp
        let ssid: String
        init(http: WatchHttp, ssid: String) { self.http = http; self.ssid = ssid }
        func close() async { WifiJoin.leave(ssid: ssid) }
    }

    /// Why the last connect() failed (Spanish, shown in the Reloj Wi-Fi page).
    private(set) var lastFailure: String?

    func connect(_ creds: WifiCredentials) async -> WifiLink? {
        lastFailure = nil
        // The watch answers WIFI_SYNC(start) before its SoftAP is always beaconing: one more try after a pause.
        var joined = false
        for attempt in 1...2 {
            do {
                try await WifiJoin.join(ssid: creds.ssid, passphrase: creds.password)
                joined = true
                break
            } catch {
                let denied = (error as? WifiJoinError)?.userDenied ?? false
                log("wifi: el iPad no se unió a \(creds.ssid) (intento \(attempt)): \(error.localizedDescription)")
                lastFailure = denied ? "no se aceptó unirse a \(creds.ssid) (pulsa «Conectarse» cuando iOS lo pregunte)"
                                     : "el iPad no se unió a \(creds.ssid): \(error.localizedDescription)"
                if denied || attempt == 2 || Task.isCancelled { return nil }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
        if !joined { return nil }
        if let cur = await WifiJoin.currentSsid(), cur != creds.ssid {
            log("wifi: iOS dice que está en \(cur), no en \(creds.ssid)")
        }
        log("wifi: unido a \(creds.ssid)")
        let http = UrlWatchHttp(creds, client: makeClient())
        // DHCP, the route to 192.168.4.x and the first-use «local network» permission take a moment: probe the API with a
        // short timeout every second for up to 30 s (a single 20 s request used to use up the whole window).
        let until = Date().addingTimeInterval(30)
        var lastError = ""
        while Date() < until {
            do {
                try await http.probe(timeout: 4)
                return Link(http: http, ssid: creds.ssid)
            } catch let e as WatchHttpError {
                // the watch answered (token/recording…): the network works, the coordinator handles the error
                log("wifi: el reloj respondió \(e.code)")
                return Link(http: http, ssid: creds.ssid)
            } catch {
                lastError = error.localizedDescription
                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        log("wifi: sin respuesta HTTP del reloj en \(creds.ssid): \(lastError)")
        lastFailure = "el iPad se unió a \(creds.ssid) pero el reloj no respondió"
            + (lastError.isEmpty ? "" : " (\(lastError))")
            + ". Revisa Ajustes › Privacidad › Red local › AVO"
        WifiJoin.leave(ssid: creds.ssid)
        return nil
    }
}

/// Wi-Fi download of trainings from the chest watch (Android AvoWifiSyncManager): WIFI_SYNC over the authenticated BLE
/// client, NEHotspotConfiguration join, resumable HTTP download, SHA-256 check, then `sink` imports the P00n.avr folder.
/// The watch Wi-Fi is always turned off at the end. The original on the watch is never deleted.
final class WifiSyncManager {
    let control: BleWifiControl
    let coordinator: WifiSyncCoordinator
    private let info: () -> WatchInfo?
    private let client: () -> AvoClient?
    private let log: (String) -> Void

    /// client/info: current authenticated BLE connection (IosWatchConnection); isRecording: session state;
    /// trainingsDir: base folder (one sub-folder per training id); sink(id, folder, sha256, bytes): import as RAW segments.
    init(client: @escaping () -> AvoClient?, info: @escaping () -> WatchInfo?, isRecording: @escaping () -> Bool = { false },
         trainingsDir: @escaping () -> String, sink: @escaping WifiSyncCoordinator.VerifiedSink,
         log: @escaping (String) -> Void = { NSLog("[WIFI] %@", $0) }) {
        self.info = info
        self.client = client
        self.log = log
        let guardStore = WifiBootGuard()
        let ctl = BleWifiControl(client: client, info: info, isRecording: isRecording, bootGuard: guardStore)
        control = ctl
        coordinator = WifiSyncCoordinator(control: ctl, connector: HotspotWifiConnector(log: log),
                                          dirFor: { id in AvoFiles.join(trainingsDir(), id) }, sink: sink, log: log)
        coordinator.paused = guardStore.paused
    }

    /// The watch firmware rebooted when turning on Wi-Fi: blocked until another firmware.
    var blockedFirmware: String? { control.bootGuard.blockedFirmware }
    /// Firmware with Wi-Fi download (capability bit 11) and without a reboot history.
    var supported: Bool { control.supported }
    var progress: WifiSyncProgress { coordinator.progress }
    var busy: Bool { coordinator.busy }

    /// Why Wi-Fi cannot be used now (Spanish, for the UI), nil when it can.
    func unsupportedReason() -> String? {
        guard let i = info() else { return "Conecta antes con el reloj por Bluetooth." }
        if !i.supportsWifiSync { return "El reloj (\(i.firmware)) no admite descarga por Wi-Fi: actualiza el firmware del pecho." }
        if let b = blockedFirmware, b == i.firmware { return "Wi-Fi desactivado para \(i.firmware): el reloj se reinició al activarlo." }
        return supported ? nil : "Wi-Fi no disponible."
    }

    /// One pass for the given trainings (id, SHA already verified locally or nil). Only one at a time.
    func sync(_ pending: [(String, String?)]) async throws -> WifiSyncReport {
        if pending.isEmpty { return WifiSyncReport(verified: [], failed: [:], fallbackBle: []) }
        if !supported {
            log(unsupportedReason() ?? "Wi-Fi no disponible")
            return WifiSyncReport(verified: [], failed: [:], fallbackBle: pending.map { $0.0 }, wifiUnavailable: true)
        }
        log("pidiendo Wi-Fi al reloj \(info()?.firmware ?? "") para \(pending.count) entrenamiento(s)")
        let r = try await coordinator.sync(pending)
        // still connected over BLE after the pass → the watch did not reboot because of Wi-Fi
        if client() != nil { control.bootGuard.clearAttempt() }
        return r
    }

    /// "Descargar todo": lists the closed trainings on the watch and downloads those `want` accepts
    /// (nil = skip; .some(sha or nil) = download, with the local verified SHA if any).
    func syncAvailable(_ want: @escaping (RemoteTraining) -> String??) async throws -> WifiSyncReport {
        if !supported {
            log(unsupportedReason() ?? "Wi-Fi no disponible")
            return WifiSyncReport(verified: [], failed: [:], fallbackBle: [], wifiUnavailable: true)
        }
        let r = try await coordinator.syncAvailable(want)
        if client() != nil { control.bootGuard.clearAttempt() }
        return r
    }

    func cancel() { coordinator.cancel() }

    /// Pause persists across app restarts.
    var paused: Bool {
        get { coordinator.paused }
        set {
            coordinator.paused = newValue
            control.bootGuard.paused = newValue
            if newValue { coordinator.cancel() }
        }
    }
}
