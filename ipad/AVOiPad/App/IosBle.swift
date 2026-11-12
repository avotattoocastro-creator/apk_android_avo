import Foundation
import CoreBluetooth
import Security

// Port of windows/AVO.Windows/Ble/WinBle.cs (WinRT Bluetooth LE) to CoreBluetooth: scanner, GATT transport implementing
// AvoTransport (CTRL_RX write with response, CTRL_TX + FILE_TX notifications) and the per-watch key store. On Windows the key
// was encrypted with DPAPI per user; on the iPad it goes to the Keychain (this device only, after first unlock).
//
// Pairing: if the watch requires an encrypted link (ble_require_bond), iOS pairs by itself ("Just Works" system dialog) the
// first time a protected characteristic is accessed; nothing else is needed here.
// iOS never exposes the Bluetooth MAC address: watches are identified by the CBPeripheral identifier (stable per iPad).

/// C# IOException of the Bluetooth layer.
struct BleLinkError: Error, LocalizedError {
    var message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct BleWatchFound: Equatable {
    var identifier: UUID
    var name: String
    var rssi: Int
    /// iOS has no MAC address: the peripheral identifier is shown instead.
    var addressText: String { identifier.uuidString }
}

/// The single CBCentralManager of the app (CoreBluetooth wants one per app), with async/await wrappers.
final class IosBleCentral: NSObject, CBCentralManagerDelegate {
    static let shared = IosBleCentral()

    let queue = DispatchQueue(label: "org.avoperformance.horse.ble")
    private var manager: CBCentralManager!
    private let lock = NSLock()
    private var stateWaiters: [AvoOneShot<Void>] = []
    private var found: [UUID: BleWatchFound] = [:]
    private var scanning = false
    private var scanByName = false
    private var known: [UUID: CBPeripheral] = [:]
    private var connectWaiters: [UUID: AvoOneShot<Void>] = [:]
    private var disconnectHandlers: [UUID: (Error?) -> Void] = [:]

    /// Sync critical section (NSLock must not be used directly from async functions).
    private func locked<T>(_ f: () throws -> T) rethrows -> T { lock.lock(); defer { lock.unlock() }; return try f() }

    private override init() {
        super.init()
        manager = CBCentralManager(delegate: self, queue: queue, options: [CBCentralManagerOptionShowPowerAlertKey: true])
    }

    static let serviceUuid = CBUUID(nsuuid: AvoGatt.service)

    // ------------------------------------------------------------------ state
    private func stateError(_ s: CBManagerState) -> Error? {
        switch s {
        case .poweredOn: return nil
        case .unauthorized: return BleLinkError("Permiso de Bluetooth denegado: actívalo en Ajustes → AVO Horse → Bluetooth.")
        case .poweredOff: return BleLinkError("Bluetooth desactivado: actívalo en el Centro de control o en Ajustes.")
        case .unsupported: return BleLinkError("Este iPad no admite Bluetooth LE.")
        default: return nil   // unknown / resetting: wait
        }
    }

    func waitPoweredOn(timeoutMs: Int = 5000) async throws {
        let w = AvoOneShot<Void>()
        let ready: Bool = try locked {
            let s = manager.state
            if s == .poweredOn { return true }
            if let e = stateError(s) { throw e }
            stateWaiters.append(w)
            return false
        }
        if ready { return }
        try await w.value(timeoutMs: timeoutMs, onTimeout: { .failure(BleLinkError("Bluetooth no disponible: actívalo en Ajustes.")) })
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        lock.lock()
        let waiters = stateWaiters
        let s = central.state
        let err = stateError(s)
        let ready = s == .poweredOn
        if ready || err != nil { stateWaiters.removeAll() }
        let handlers = Array(disconnectHandlers.values)
        lock.unlock()
        if ready { for w in waiters { w.succeed(()) } } else if let e = err { for w in waiters { w.fail(e) } }
        if s == .poweredOff || s == .unauthorized || s == .resetting {
            for h in handlers { h(BleLinkError("Bluetooth desactivado")) }
        }
    }

    // ------------------------------------------------------------------ scan
    /// Finds AVO watches advertising the AVO service (or, with byName, the name AVO_XXXX / AVO-XXXX), strongest first.
    func scan(duration: TimeInterval, byName: Bool = false) async throws -> [BleWatchFound] {
        try await waitPoweredOn()
        locked {
            found = [:]
            scanning = true
            scanByName = byName
        }
        // watches already connected to this iPad by the system do not advertise
        for p in manager.retrieveConnectedPeripherals(withServices: [IosBleCentral.serviceUuid]) {
            locked {
                known[p.identifier] = p
                found[p.identifier] = BleWatchFound(identifier: p.identifier, name: p.name ?? "AVO", rssi: 0)
            }
        }
        manager.scanForPeripherals(withServices: byName ? nil : [IosBleCentral.serviceUuid],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        do {
            try await Task.sleep(nanoseconds: UInt64(max(0.5, duration) * 1_000_000_000))
        } catch {
            stopScan()
            throw error
        }
        stopScan()
        let r: [BleWatchFound] = locked { Array(found.values) }
        return r.sorted { $0.rssi > $1.rssi }
    }

    private func stopScan() {
        lock.lock(); scanning = false; lock.unlock()
        if manager.isScanning { manager.stopScan() }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let local = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = local ?? peripheral.name ?? ""
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        lock.lock()
        defer { lock.unlock() }
        guard scanning else { return }
        let avo = AvoGatt.isWatchName(name) || services.contains(IosBleCentral.serviceUuid) || !scanByName
        if !avo { return }
        let rssi = RSSI.intValue == 127 ? -127 : RSSI.intValue      // 127 = not available
        known[peripheral.identifier] = peripheral
        let old = found[peripheral.identifier]
        found[peripheral.identifier] = BleWatchFound(identifier: peripheral.identifier,
                                                     name: name.isEmpty ? (old?.name ?? "AVO") : name, rssi: rssi)
    }

    // ------------------------------------------------------------------ connect
    func peripheral(_ id: UUID) -> CBPeripheral? {
        lock.lock()
        if let p = known[id] { lock.unlock(); return p }
        lock.unlock()
        let p = manager.retrievePeripherals(withIdentifiers: [id]).first
        if let p = p { lock.lock(); known[id] = p; lock.unlock() }
        return p
    }

    func connect(_ p: CBPeripheral, timeoutMs: Int, onDisconnect: @escaping (Error?) -> Void) async throws {
        let w = AvoOneShot<Void>()
        locked {
            connectWaiters[p.identifier] = w
            disconnectHandlers[p.identifier] = onDisconnect
        }
        manager.connect(p, options: nil)
        do {
            try await w.value(timeoutMs: timeoutMs, onTimeout: {
                .failure(BleLinkError("No se pudo conectar con el reloj. Acércalo al iPad y comprueba que está encendido."))
            })
        } catch {
            locked {
                _ = connectWaiters.removeValue(forKey: p.identifier)
                _ = disconnectHandlers.removeValue(forKey: p.identifier)
            }
            manager.cancelPeripheralConnection(p)
            throw error
        }
    }

    func cancel(_ p: CBPeripheral) {
        lock.lock()
        disconnectHandlers.removeValue(forKey: p.identifier)
        lock.unlock()
        manager.cancelPeripheralConnection(p)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        lock.lock()
        let w = connectWaiters.removeValue(forKey: peripheral.identifier)
        lock.unlock()
        w?.succeed(())
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        lock.lock()
        let w = connectWaiters.removeValue(forKey: peripheral.identifier)
        disconnectHandlers.removeValue(forKey: peripheral.identifier)
        lock.unlock()
        w?.fail(BleLinkError(IosBleTransport.connectErrorText(error)))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        lock.lock()
        let w = connectWaiters.removeValue(forKey: peripheral.identifier)
        let h = disconnectHandlers.removeValue(forKey: peripheral.identifier)
        lock.unlock()
        w?.fail(BleLinkError(IosBleTransport.isPairingLost(error) ? IosBleTransport.pairingLostText : "El reloj se desconectó"))
        h?(error)
    }
}

/// GATT link to the watch (C# WinBleTransport). Subscribes to CTRL_TX and FILE_TX and writes requests on CTRL_RX with response.
final class IosBleTransport: NSObject, AvoTransport, CBPeripheralDelegate {
    let peripheral: CBPeripheral
    /// (characteristic, value) of every notification; wire to AvoClient.onNotification.
    var onNotification: ((UUID, [UInt8]) -> Void)?
    /// Wire to AvoClient.onDisconnected.
    var onDisconnected: (() -> Void)?

    private let lock = NSLock()
    private var rx: CBCharacteristic?
    private var servicesShot: AvoOneShot<Void>?
    private var charsShot: AvoOneShot<Void>?
    private var notifyShots: [CBUUID: AvoOneShot<Void>] = [:]
    private var writeShot: AvoOneShot<Void>?
    private var closed = false

    private func locked<T>(_ f: () throws -> T) rethrows -> T { lock.lock(); defer { lock.unlock() }; return try f() }

    private static let rxUuid = CBUUID(nsuuid: AvoGatt.ctrlRx)
    private static let txUuid = CBUUID(nsuuid: AvoGatt.ctrlTx)
    private static let fileUuid = CBUUID(nsuuid: AvoGatt.fileTx)

    var name: String { peripheral.name ?? "AVO" }
    var identifier: UUID { peripheral.identifier }
    /// ATT payload = negotiated MTU − 3 (what iOS reports for writes without response).
    var attPayload: Int { max(20, peripheral.maximumWriteValueLength(for: .withoutResponse)) }

    private init(_ p: CBPeripheral) {
        peripheral = p
        super.init()
        p.delegate = self
    }

    static func connect(_ identifier: UUID, progress: ((String) -> Void)? = nil, timeoutMs: Int = 15000) async throws -> IosBleTransport {
        let central = IosBleCentral.shared
        try await central.waitPoweredOn()
        progress?("Conectando con el reloj por Bluetooth…")
        guard let p = central.peripheral(identifier) else {
            throw BleLinkError("No se encuentra el reloj. Acércalo al iPad y comprueba que está encendido.")
        }
        let t = IosBleTransport(p)
        try await central.connect(p, timeoutMs: timeoutMs) { [weak t] err in t?.handleDisconnect(err) }
        do {
            try await t.setUp(timeoutMs: timeoutMs)
        } catch {
            t.close()
            throw error
        }
        return t
    }

    private func setUp(timeoutMs: Int) async throws {
        let s = AvoOneShot<Void>()
        locked { servicesShot = s }
        peripheral.discoverServices([IosBleCentral.serviceUuid])
        try await s.value(timeoutMs: timeoutMs, onTimeout: { .failure(BleLinkError("El reloj no responde (servicios)")) })
        guard let svc = peripheral.services?.first(where: { $0.uuid == IosBleCentral.serviceUuid }) else {
            throw BleLinkError("El dispositivo no ofrece el servicio AVO (¿es un reloj AVO?)")
        }
        let c = AvoOneShot<Void>()
        locked { charsShot = c }
        peripheral.discoverCharacteristics([IosBleTransport.rxUuid, IosBleTransport.txUuid, IosBleTransport.fileUuid], for: svc)
        try await c.value(timeoutMs: timeoutMs, onTimeout: { .failure(BleLinkError("El reloj no responde (características)")) })
        let chars = svc.characteristics ?? []
        guard let rxc = chars.first(where: { $0.uuid == IosBleTransport.rxUuid }) else {
            throw BleLinkError("Falta la característica \(AvoGatt.ctrlRx.uuidString.lowercased())")
        }
        locked { rx = rxc }
        for id in [IosBleTransport.txUuid, IosBleTransport.fileUuid] {
            guard let ch = chars.first(where: { $0.uuid == id }) else {
                throw BleLinkError("Falta la característica \(id.uuidString.lowercased())")
            }
            let n = AvoOneShot<Void>()
            locked { notifyShots[id] = n }
            peripheral.setNotifyValue(true, for: ch)
            // the first time, iOS may show its pairing dialog here: give the user time
            try await n.value(timeoutMs: max(timeoutMs, 60000), onTimeout: {
                .failure(BleLinkError("No se pudieron activar las notificaciones del reloj (tiempo agotado)"))
            })
        }
    }

    /// Pairing lost on the watch side (firmware update or bonds erased): only the user can remove the old pairing of
    /// the iPad (iOS does not let apps do it).
    static let pairingLostText: String =
        "El reloj ha olvidado el emparejamiento con este iPad (pasa al actualizar su firmware o al borrar sus emparejamientos). "
        + "En el iPad abre Ajustes › Bluetooth, toca (i) junto a AVO_CHEST… y elige «Omitir este dispositivo». "
        + "Después vuelve aquí, pulsa «Conectar por Bluetooth» y pulsa BOOT en el reloj cuando lo pida."

    static func isPairingLost(_ e: Error?) -> Bool {
        guard let ns = e as NSError? else { return false }
        // CBErrorPeerRemovedPairingInformation = 14, CBErrorEncryptionTimedOut = 15
        return ns.domain == CBErrorDomain && (ns.code == 14 || ns.code == 15)
    }

    static func connectErrorText(_ e: Error?) -> String {
        if isPairingLost(e) { return pairingLostText }
        return "No se pudo conectar con el reloj: " + (e?.localizedDescription ?? "error desconocido")
    }

    private static func describe(_ e: Error) -> String {
        if isPairingLost(e) { return pairingLostText }
        if let att = e as? CBATTError,
           att.code == .insufficientAuthentication || att.code == .insufficientEncryption || att.code == .insufficientAuthorization {
            return "El reloj exige un enlace cifrado: acepta el emparejamiento Bluetooth y vuelve a intentarlo."
        }
        return e.localizedDescription
    }

    // ------------------------------------------------------------------ AvoTransport
    func writeCtrl(_ fragment: [UInt8]) async throws {
        let w = AvoOneShot<Void>()
        let ch: CBCharacteristic = try locked {
            if closed { throw BleLinkError("Conexión con el reloj cerrada") }
            guard let c = rx else { throw BleLinkError("Conexión con el reloj no preparada") }
            writeShot = w
            return c
        }
        peripheral.writeValue(Data(fragment), for: ch, type: .withResponse)
        try await w.value(timeoutMs: 5000, onTimeout: { .failure(BleLinkError("Error de escritura Bluetooth: tiempo agotado")) })
    }

    func close() {
        lock.lock()
        closed = true
        lock.unlock()
        IosBleCentral.shared.cancel(peripheral)
        failAll(BleLinkError("Conexión con el reloj cerrada"))
    }

    private func failAll(_ e: Error) {
        lock.lock()
        let shots: [AvoOneShot<Void>] = [servicesShot, charsShot, writeShot].compactMap { $0 } + Array(notifyShots.values)
        servicesShot = nil; charsShot = nil; writeShot = nil; notifyShots = [:]
        lock.unlock()
        for s in shots { s.fail(e) }
    }

    private func handleDisconnect(_ err: Error?) {
        lock.lock()
        closed = true
        lock.unlock()
        failAll(BleLinkError(IosBleTransport.isPairingLost(err) ? IosBleTransport.pairingLostText : "El reloj se desconectó"))
        onDisconnected?()
    }

    // ------------------------------------------------------------------ CBPeripheralDelegate (central queue)
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        lock.lock(); let s = servicesShot; servicesShot = nil; lock.unlock()
        if let e = error { s?.fail(BleLinkError("No se pudieron leer los servicios del reloj: " + IosBleTransport.describe(e))) } else { s?.succeed(()) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        lock.lock(); let s = charsShot; charsShot = nil; lock.unlock()
        if let e = error { s?.fail(BleLinkError("No se pudieron leer las características: " + IosBleTransport.describe(e))) } else { s?.succeed(()) }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        lock.lock(); let s = notifyShots.removeValue(forKey: characteristic.uuid); lock.unlock()
        if let e = error {
            s?.fail(BleLinkError("No se pudieron activar las notificaciones del reloj: " + IosBleTransport.describe(e)))
        } else {
            s?.succeed(())
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        lock.lock(); let s = writeShot; writeShot = nil; lock.unlock()
        if let e = error {
            s?.fail(BleLinkError(IosBleTransport.describe(e).hasPrefix("El reloj exige")
                ? "El reloj rechazó la escritura (enlace sin cifrar)" : "Error de escritura Bluetooth: " + e.localizedDescription))
        } else {
            s?.succeed(())
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let v = characteristic.value else { return }
        let id: UUID
        if characteristic.uuid == IosBleTransport.txUuid { id = AvoGatt.ctrlTx }
        else if characteristic.uuid == IosBleTransport.fileUuid { id = AvoGatt.fileTx }
        else { id = UUID(uuidString: characteristic.uuid.uuidString) ?? AvoGatt.telem }
        onNotification?(id, [UInt8](v))
    }
}

/// Connected and authorized watch (C# MainViewModel.WithWatchAsync without the UI): scan, connect, authorize with BOOT if needed.
final class IosWatchConnection {
    let transport: IosBleTransport
    let client: AvoClient
    let info: WatchInfo
    let found: BleWatchFound

    private init(transport: IosBleTransport, client: AvoClient, info: WatchInfo, found: BleWatchFound) {
        self.transport = transport; self.client = client; self.info = info; self.found = found
    }

    /// Last watch used (Windows kept its address in reloj_ble.txt).
    static var rememberedIdentifier: UUID? {
        get { UserDefaults.standard.string(forKey: "avo.watch.ble").flatMap { UUID(uuidString: $0) } }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: "avo.watch.ble") }
    }

    /// target: the watch chosen by the user (nil = the remembered one, or the only one found). Throws BleLinkError /
    /// BleRequestError with the Spanish message to show.
    static func open(target: BleWatchFound? = nil, clientName: String, store: WatchCredentialStore = KeychainCredentialStore(),
                     progress: ((String) -> Void)? = nil) async throws -> IosWatchConnection {
        var chosen = target
        if chosen == nil {
            progress?("Buscando el reloj por Bluetooth (acerca el reloj al iPad)…")
            let list = try await IosBleCentral.shared.scan(duration: 6)
            let remembered = rememberedIdentifier
            chosen = list.first(where: { $0.identifier == remembered }) ?? (list.count == 1 ? list[0] : nil)
            if chosen == nil && list.count > 1 { chosen = list[0] }   // strongest signal (the UI may ask first)
        }
        guard let w = chosen else {
            throw BleLinkError("No se encontró ningún reloj AVO. Enciéndelo, acércalo al iPad y cierra la app del móvil si está conectada (el reloj admite una sola conexión).")
        }
        let t = try await IosBleTransport.connect(w.identifier, progress: progress)
        let c = AvoClient(t)
        t.onNotification = { [weak c] ch, v in c?.onNotification(ch, v) }
        t.onDisconnected = { [weak c] in c?.onDisconnected() }
        do {
            let info = try await WatchAuthorizer.ensure(c, store, clientName: clientName, progress: progress)
            rememberedIdentifier = w.identifier
            return IosWatchConnection(transport: t, client: c, info: info, found: w)
        } catch {
            t.close()
            throw error
        }
    }

    func close() { transport.close() }
}

// ---------------------------------------------------------------------------------------------------------- Keychain

/// Minimal generic-password Keychain access.
enum KeychainStore {
    static func set(_ data: Data, service: String, account: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func get(service: String, account: String) -> Data? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        let st = SecItemCopyMatching(q as CFDictionary, &out)
        guard st == errSecSuccess else { return nil }
        return out as? Data
    }

    @discardableResult
    static func delete(service: String, account: String) -> Bool {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let st = SecItemDelete(q as CFDictionary)
        return st == errSecSuccess || st == errSecItemNotFound
    }
}

/// Watch keys of this iPad in the Keychain (C# DpapiCredentialStore). Same JSON as the Windows DTO: DeviceId, KeyId, Key (hex).
final class KeychainCredentialStore: WatchCredentialStore {
    static let service = "org.avoperformance.horse.watch-key"
    private let service: String

    init(service: String = KeychainCredentialStore.service) { self.service = service }

    private func account(_ deviceId: String) -> String? {
        deviceId.matches("^[0-9A-Fa-f]{1,16}$") ? deviceId.lowercased() : nil
    }

    func get(_ deviceId: String) -> WatchCredential? {
        guard let a = account(deviceId), let d = KeychainStore.get(service: service, account: a), let o = AvoJSON.object(d),
              let dev = AvoJSON.string(o, "DeviceId"), let kid = AvoJSON.string(o, "KeyId").flatMap({ AvoHex.bytes($0) }),
              let key = AvoJSON.string(o, "Key").flatMap({ AvoHex.bytes($0) }) else { return nil }
        return WatchCredential(deviceId: dev, keyId: kid, key: key)
    }

    func save(_ c: WatchCredential) {
        guard let a = account(c.deviceId) else {
            NSLog("[reloj] identificador de reloj no válido: no se guarda la clave")
            return
        }
        let o: [String: Any] = ["DeviceId": c.deviceId, "KeyId": AvoHex.upper(c.keyId), "Key": AvoHex.upper(c.key)]
        if !KeychainStore.set(AvoJSON.data(o), service: service, account: a) {
            NSLog("[reloj] no se pudo guardar la clave del reloj en el llavero")
        }
    }

    func remove(_ deviceId: String) {
        if let a = account(deviceId) { KeychainStore.delete(service: service, account: a) }
    }
}
