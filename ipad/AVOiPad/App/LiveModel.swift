import SwiftUI
import Observation

/// «LIVE» (Actualizaciones 1, 19/11/2026): entrenamiento en directo desde el servidor (Firebase). El Android sube la
/// TELEMETRY del pecho y el iPad la recibe; el iPad NO se conecta al pecho (el pecho acepta un solo móvil y ese móvil
/// manda el RTCM). Sin cambios de protocolo: pulso y aceleración de la IMU no llegan en directo todavía.
@Observable
final class LiveModel {
    unowned let app: AppModel

    enum Source: Equatable { case none, server, simulation }

    // cuenta
    var signedCode: String? = nil
    var signedName: String = ""
    var busy: Bool = false
    var message: String? = nil
    var error: String? = nil

    // directos disponibles y el que se ve
    var available: [LiveSessionRef] = []
    var current: LiveSessionRef? = nil
    var source: Source = .none
    var state: LiveSessionState = LiveSessionState()
    var lastEventAt: Date? = nil
    /// Muestras y series ya calculadas (se recalculan al llegar datos, como mucho 4 veces por segundo).
    var samples: [LiveSample] = []
    var series: LiveSeries = LiveSeries()

    @ObservationIgnored private let client = LiveFirebaseClient()
    @ObservationIgnored private var streamTask: Task<Void, Never>? = nil
    @ObservationIgnored private var simTask: Task<Void, Never>? = nil
    @ObservationIgnored private var pollTask: Task<Void, Never>? = nil
    @ObservationIgnored private var rebuildPending: Bool = false

    static let keychainAccount: String = "avo-user-card"

    /// Nube AVO (página Servidor): misma sesión de Firebase que el LIVE.
    @ObservationIgnored private(set) var cloud: AvoCloudClient! = nil

    init(app: AppModel) {
        self.app = app
        let c: LiveFirebaseClient = client
        self.cloud = AvoCloudClient(token: { try await c.token() })
    }

    /// Nube AVO: tras cambiar el caballo/jinete en este iPad, vuelve a subir el .avo si ese entrenamiento está en la nube
    /// del usuario (gana la asignación más reciente; el Android la aplica en su siguiente comprobación).
    @MainActor
    func pushAssignmentToCloud(_ sessionIds: [String]) async {
        guard !sessionIds.isEmpty, await ensureSignedIn(), let code = signedCode else { return }
        var sent: Int = 0
        for sid in sessionIds {
            guard let path = app.library.storedAvoPath(sid) else { continue }
            do {
                guard let remote = try await cloud.item(code: code, sessionId: sid) else { continue }   // no está en la nube
                let id: CloudManifestIdentity = try CloudManifestIdentity.read(path)
                if id.horseName.isEmpty || id.riderName.isEmpty { continue }
                var meta: [String: String] = [
                    "fp": id.fingerprint, "sessionId": sid, "horseCode": id.horseCode, "horseName": id.horseName,
                    "riderCode": id.riderCode, "riderName": id.riderName, "assignedMs": String(id.assignedMs), "app": "ipad",
                    "startRtcMs": String(remote.startRtcMs),
                ]
                if let d = remote.distanceM { meta["distanceM"] = String(Int(d.rounded())) }
                try await cloud.upload(fileAt: path, code: code, sessionId: sid, metadata: meta)
                sent += 1
            } catch {
                app.log.warn("nube", "no se pudo actualizar \(sid) en la nube: \(error.localizedDescription)", error)
            }
        }
        if sent > 0 { app.log.info("nube", "asignación actualizada en la nube", ["count": sent] as [String: Any]) }
    }

    /// Entra con la tarjeta guardada en el Llavero si aún no hay sesión. Devuelve si hay sesión.
    @MainActor
    func ensureSignedIn() async -> Bool {
        if signedCode != nil { return true }
        guard let saved = AvoKeychain.read(LiveModel.keychainAccount), let card = try? AvoUserCard.parse(saved) else { return false }
        await signIn(card, save: false)
        return signedCode != nil
    }

    func sessionChanged() {}

    func pageShown() {
        // evidencias de CI (modo captura): simulación instantánea con el entrenamiento DEMO abierto
        if app.captureMode && signedCode == nil {
            if source == .none && app.selected != nil { Task { @MainActor in self.simulate(instant: true) } }
            return
        }
        if signedCode == nil, let saved = AvoKeychain.read(LiveModel.keychainAccount), let card = try? AvoUserCard.parse(saved) {
            Task { @MainActor in await signIn(card, save: false) }
        }
        // mientras la página está a la vista y no hay directo abierto, se busca uno cada 15 s
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                if self.signedCode != nil && self.source == .none && !self.busy { await self.refresh() }
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    func pageHidden() {
        pollTask?.cancel(); pollTask = nil
        // el directo sigue en segundo plano mientras la app está abierta; solo se para la simulación
        if source == .simulation { stop() }
    }

    // ------------------------------------------------------------------ cuenta

    @MainActor
    func signIn(_ card: AvoUserCard, save: Bool) async {
        busy = true; error = nil
        defer { busy = false }
        do {
            try await client.signIn(card)
            signedCode = card.code
            signedName = card.name
            if save { AvoKeychain.write("\(AvoUserCard.prefix)\(card.code)?v=1&name=\(card.name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")&k=\(card.secret)", LiveModel.keychainAccount) }
            app.log.info("LIVE", "sesión iniciada como \(card.code)")
            await refresh()
        } catch let e {
            error = e.localizedDescription
            app.log.warn("LIVE", "no se pudo entrar: \(e.localizedDescription)")
        }
    }

    func signOut() {
        stop()
        client.signOut()
        AvoKeychain.delete(LiveModel.keychainAccount)
        signedCode = nil; signedName = ""; available = []
    }

    // ------------------------------------------------------------------ lista

    /// Directos activos ahora (pecho encendido: en espera, grabando o en pausa), para el selector y la barra lateral.
    var activeSessions: [LiveSessionRef] { available.filter { !$0.meta.isEnded } }

    /// Lista de directos en segundo plano (barra lateral «LIVE»), cada 20 s mientras la app está abierta.
    /// No abre ningún directo por su cuenta: solo actualiza la lista.
    @MainActor
    func backgroundLoop() async {
        while !Task.isCancelled {
            if !app.captureMode, await ensureSignedIn(), !busy {
                if let list = try? await client.liveSessions() { available = list }
            }
            try? await Task.sleep(nanoseconds: 20_000_000_000)
        }
    }

    @MainActor
    func refresh() async {
        guard signedCode != nil else { return }
        busy = true
        defer { busy = false }
        do {
            available = try await client.liveSessions()
            message = available.isEmpty ? "No hay ningún directo ahora. Enciende el pecho conectado al Android con «Directo (LIVE en el iPad)» activado en Compartir." : nil
            error = nil
            // si hay un directo activo y no se está viendo ninguno, se abre el primero (grabando antes que en espera)
            if source == .none, let first = available.first(where: { $0.meta.state == "REC" }) ?? activeSessions.first { open(first) }
        } catch let e {
            error = e.localizedDescription
        }
    }

    // ------------------------------------------------------------------ directo

    func open(_ ref: LiveSessionRef) {
        stop()
        current = ref
        source = .server
        state = LiveSessionState()
        state.meta = ref.meta
        samples = []; series = LiveSeries()
        let path: String = "live/\(ref.owner)/\(ref.sid)"
        streamTask = Task { [weak self] in
            var delay: UInt64 = 1_000_000_000
            while !Task.isCancelled {
                guard let self = self else { return }
                do {
                    try await self.client.stream(path) { [weak self] ev, p, d in
                        Task { @MainActor in self?.onEvent(ev, p, d) }
                    }
                    delay = 1_000_000_000
                } catch let e {
                    if Task.isCancelled { return }
                    await MainActor.run { self.error = "Directo: \(e.localizedDescription). Reconectando…" }
                }
                try? await Task.sleep(nanoseconds: delay)
                delay = min(delay * 2, 15_000_000_000)
            }
        }
    }

    private func onEvent(_ ev: String, _ path: String, _ data: Any?) {
        guard source == .server else { return }
        state.apply(event: ev, path: path, data: data)
        lastEventAt = Date()
        error = nil
        scheduleRebuild()
    }

    func stop() {
        streamTask?.cancel(); streamTask = nil
        simTask?.cancel(); simTask = nil
        source = .none
        current = nil
    }

    private func scheduleRebuild() {
        if rebuildPending { return }
        rebuildPending = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self = self else { return }
            self.rebuildPending = false
            let s: [LiveSample] = self.state.samples
            self.samples = s
            self.series = LiveSeries.build(s)
        }
    }

    // ------------------------------------------------------------------ simulación

    /// Reproduce el entrenamiento abierto como si llegara en directo (2 Hz), para probar la pantalla sin caballo.
    /// Siempre marcado SIMULACIÓN; no sube nada a ningún sitio.
    func simulate(speed: Double = 4, instant: Bool = false) {
        guard let item = app.selected else { error = "Abre antes un entrenamiento (Entrenamientos) para simularlo"; return }
        stop()
        let tl: SessionTimeline = item.timeline
        guard tl.count > 1 else { error = "El entrenamiento no tiene datos GNSS"; return }
        source = .simulation
        var meta = LiveMeta()
        meta.horseName = item.horse; meta.riderName = item.rider; meta.state = "REC"
        meta.startMs = Int64((item.start ?? Date()).timeIntervalSince1970 * 1000)
        current = LiveSessionRef(owner: "SIMULACIÓN", ownerName: "Simulación", sid: item.id, meta: meta)
        state = LiveSessionState(); state.meta = meta
        samples = []; series = LiveSeries(); error = nil
        // re-muestreo a 2 Hz del entrenamiento real
        var all: [LiveSample] = []
        let t0: Double = tl.t[0]
        var next: Double = t0
        for i in 0..<tl.count where tl.t[i] >= next {
            next = tl.t[i] + 0.5
            let sol: GnssSolution = i < tl.solution.count ? tl.solution[i] : .autonomous
            all.append(LiveSample(tMs: Int64((tl.t[i] - t0) * 1000), latE7: Int32(clamping: Int64((tl.lat[i] * 1e7).rounded())),
                                  lonE7: Int32(clamping: Int64((tl.lon[i] * 1e7).rounded())),
                                  speedMmS: Int32(clamping: Int64(((i < tl.speedReported.count ? tl.speedReported[i] : 0) * 1000).rounded())),
                                  distCm: Int64(((i < tl.distance.count ? tl.distance[i] : 0) * 100).rounded()),
                                  fix: sol == .none ? 0 : 3, carr: sol == .rtkFix ? 2 : (sol == .rtkFloat ? 1 : 0),
                                  hAccMm: Int64(((i < tl.hAcc.count ? tl.hAcc[i] : 0) * 1000).rounded()),
                                  numSv: i < tl.numSv.count ? tl.numSv[i] : 0, session: 2))
        }
        if instant {
            for (k, s) in all.enumerated() { state.chunks[k / 20, default: []].append(s) }
            state.last = all.last
            state.meta.state = "END"
            lastEventAt = Date()
            samples = state.samples
            series = LiveSeries.build(samples)
            return
        }
        let pace: UInt64 = UInt64(max(0.02, 0.5 / max(speed, 0.1)) * 1_000_000_000)
        simTask = Task { @MainActor [weak self] in
            for (k, s) in all.enumerated() {
                if Task.isCancelled { return }
                guard let self = self else { return }
                self.state.chunks[k / 20, default: []].append(s)
                self.state.last = s
                self.lastEventAt = Date()
                self.scheduleRebuild()
                try? await Task.sleep(nanoseconds: pace)
            }
            self?.state.meta.state = "END"
        }
    }

    // ------------------------------------------------------------------ datos para la vista

    var latest: LiveSample? { samples.last }

    /// Segundos desde el último dato (para «sin datos desde hace…»).
    func ageSeconds(_ now: Date) -> Double? { lastEventAt.map { now.timeIntervalSince($0) } }

    var isLive: Bool { source != .none }
}
