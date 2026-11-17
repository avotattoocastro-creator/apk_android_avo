import Foundation
import CoreBluetooth

/// Enlace BLE con el gadget AVO SYNC (hora GPS para el vídeo, protocolo v1 en `Core/AvoSync.swift`).
///
/// Usa su PROPIO `CBCentralManager` en una cola de alta prioridad, separado del de los relojes (`IosBleCentral`), para no
/// tocar el enlace con el pecho y para anotar t4 en cuanto llega la respuesta, sin esperar a la cola principal (cualquier
/// espera ahí sería asimetría y error de hora). iOS permite varios gestores; el permiso de Bluetooth es el mismo.
///
/// Los avisos (`onState`, `onSample`…) se entregan en la cola principal.
final class AvoSyncLink: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    enum State: Equatable {
        case off
        case unavailable(String)
        case scanning
        case connecting(String)
        case connected(String)

        var text: String {
            switch self {
            case .off: return "Desconectado"
            case .unavailable(let why): return why
            case .scanning: return "Buscando AVO SYNC…"
            case .connecting(let n): return "Conectando con \(n)…"
            case .connected(let n): return "Conectado a \(n)"
            }
        }
    }

    var onState: ((State) -> Void)?
    var onSample: ((AvoSyncSample, AvoSyncProtocol.Flags, UInt8) -> Void)?
    var onMark: ((AvoSyncProtocol.Mark) -> Void)?
    var onStatus: ((AvoSyncProtocol.Status) -> Void)?

    private let queue = DispatchQueue(label: "org.avoperformance.horse.avosync", qos: .userInteractive)
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var rx: CBCharacteristic?
    private var timer: DispatchSourceTimer?
    private var seq: UInt16 = 0
    /// El usuario quiere estar conectado: tras una desconexión se vuelve a buscar.
    private var wanted = false

    private let serviceId = CBUUID(string: AvoSyncProtocol.serviceUUID)
    private let rxId = CBUUID(string: AvoSyncProtocol.rxUUID)
    private let txId = CBUUID(string: AvoSyncProtocol.txUUID)

    func start() {
        queue.async {
            self.wanted = true
            if let c = self.central {
                self.centralManagerDidUpdateState(c)
            } else {
                self.central = CBCentralManager(delegate: self, queue: self.queue,
                                                options: [CBCentralManagerOptionShowPowerAlertKey: true])
            }
        }
    }

    func stop() {
        queue.async {
            self.wanted = false
            self.stopTimer()
            self.central?.stopScan()
            if let p = self.peripheral { self.central?.cancelPeripheralConnection(p) }
            self.peripheral = nil
            self.rx = nil
            self.emit(.off)
        }
    }

    // ------------------------------------------------------------------ helpers (cola propia)
    private func emit(_ s: State) {
        DispatchQueue.main.async { self.onState?(s) }
    }

    private func name(_ p: CBPeripheral) -> String { p.name ?? "AVO SYNC" }

    private func scan() {
        guard wanted, let c = central, c.state == .poweredOn else { return }
        c.scanForPeripherals(withServices: [serviceId], options: nil)
        emit(.scanning)
    }

    private func startTimer() {
        stopTimer()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .seconds(1), leeway: .milliseconds(5))
        t.setEventHandler { [weak self] in self?.sendTimeRequest() }
        timer = t
        t.resume()
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    private func sendTimeRequest() {
        guard let p = peripheral, let rx = rx, p.state == .connected else { return }
        seq &+= 1
        let t1 = AvoHostClock.nowNs()
        p.writeValue(AvoSyncProtocol.encodeTimeRequest(seq: seq, t1HostNs: t1), for: rx, type: .withoutResponse)
    }

    private func dropLink(retry: Bool) {
        stopTimer()
        peripheral = nil
        rx = nil
        if retry && wanted { scan() } else { emit(.off) }
    }

    // ------------------------------------------------------------------ CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if peripheral == nil { scan() }
        case .poweredOff:
            stopTimer(); peripheral = nil; rx = nil
            emit(.unavailable("Bluetooth apagado"))
        case .unauthorized:
            emit(.unavailable("Sin permiso de Bluetooth (Ajustes › AVO Horse)"))
        case .unsupported:
            emit(.unavailable("Este dispositivo no tiene Bluetooth LE"))
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard self.peripheral == nil else { return }
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        emit(.connecting(name(peripheral)))
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([serviceId])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        dropLink(retry: true)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        dropLink(retry: true)
    }

    // ------------------------------------------------------------------ CBPeripheralDelegate
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = peripheral.services?.first(where: { $0.uuid == serviceId }) else {
            central?.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.discoverCharacteristics([rxId, txId], for: s)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let chars = service.characteristics ?? []
        guard let rx = chars.first(where: { $0.uuid == rxId }), let tx = chars.first(where: { $0.uuid == txId }) else {
            central?.cancelPeripheralConnection(peripheral)
            return
        }
        self.rx = rx
        peripheral.setNotifyValue(true, for: tx)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == txId else { return }
        if error == nil && characteristic.isNotifying {
            emit(.connected(name(peripheral)))
            startTimer()
        } else {
            central?.cancelPeripheralConnection(peripheral)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        // t4 lo primero, antes de cualquier otra cosa
        let t4 = AvoHostClock.nowNs()
        guard characteristic.uuid == txId, let data = characteristic.value,
              let frame = AvoSyncProtocol.decode(data) else { return }
        switch frame {
        case .timeResponse(let r):
            let sample = AvoSyncSample(t1: r.t1HostNs, t2: r.t2UtcNs, t3: r.t3UtcNs, t4: t4)
            DispatchQueue.main.async { self.onSample?(sample, r.flags, r.satellites) }
        case .mark(let m):
            DispatchQueue.main.async { self.onMark?(m) }
        case .status(let s):
            DispatchQueue.main.async { self.onStatus?(s) }
        }
    }
}
