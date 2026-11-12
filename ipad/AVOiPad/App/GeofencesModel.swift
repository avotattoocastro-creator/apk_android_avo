import SwiftUI
import Observation
import UIKit

// Port of windows/AVO.Windows/ViewModels/MainViewModel.Geofences.cs: 8 geofence slots and 4 start/finish lines of the
// watch edited on a map (geocercas.json, same file as Windows), crossings of the open training with direction, laps and
// start → finish times, «Crear tramos», and «Enviar al reloj» / «Leer del reloj» over Bluetooth (IosWatchConnection +
// GeofenceSync, BOOT authorization the first time).

struct GeoCrossingRow: Identifiable {
    let id = UUID()
    var line: String
    var time: String
    var direction: String
    var counts: Bool
    var countsText: String
}

struct GeoRunRow: Identifiable {
    let id = UUID()
    var kind: String
    var start: String
    var duration: String
}

/// Confirmation asked in the middle of an async operation (C# Dialogs.Confirm while connected to the watch).
struct GeoConfirm: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var okLabel: String
}

/// Finds the watch the way Windows WithWatchAsync does: remembered one, the only one, or the strongest after asking.
enum WatchPicker {
    static func pick(progress: @escaping (String) -> Void,
                     ask: @MainActor (String, String, String) async -> Bool) async throws -> BleWatchFound? {
        progress("Buscando el reloj por Bluetooth (acerca el reloj al iPad)…")
        let found: [BleWatchFound] = try await IosBleCentral.shared.scan(duration: 6)
        let remembered: UUID? = IosWatchConnection.rememberedIdentifier
        var target: BleWatchFound? = found.first(where: { $0.identifier == remembered }) ?? (found.count == 1 ? found[0] : nil)
        if target == nil && found.count > 1 {
            let best = found[0]
            let list: String = found.map { "\($0.name) (\($0.rssi) dBm)" }.joined(separator: ", ")
            let ok: Bool = await ask("Reloj AVO", "Hay \(found.count) relojes cerca: \(list).\n\n¿Usar el más cercano, \(best.name)?", "Usar")
            if !ok { return nil }
            target = best
        }
        if target == nil {
            throw BleLinkError("No se encontró ningún reloj AVO. Enciéndelo, acércalo al iPad y cierra la app del móvil si está conectada (el reloj admite una sola conexión).")
        }
        return target
    }

    @MainActor static var clientName: String { "AVO iPad " + UIDevice.current.name }
}

@Observable
final class GeofencesModel {
    @ObservationIgnored unowned let app: AppModel
    @ObservationIgnored let plan: GeofencePlan
    @ObservationIgnored private let planFile: String

    /// Bumped on every plan change (the plan is a plain class): views and the map read it to refresh.
    var rev: Int = 0
    /// Bumped to ask the map to frame the shapes again.
    var fitRequest: Int = 0
    var selectedFence: Int? = 0
    var selectedLine: Int? = nil
    var crossingRows: [GeoCrossingRow] = []
    var runRows: [GeoRunRow] = []
    var watchLinkStatus: String = "Reloj: sin conectar. «Enviar al reloj» lo busca por Bluetooth."
    var watchBusy: Bool = false
    var confirm: GeoConfirm? = nil
    @ObservationIgnored private var confirmCont: CheckedContinuation<Bool, Never>? = nil
    @ObservationIgnored private var runs: [LineAnalysis.Run] = []
    @ObservationIgnored private var lastSessionId: String? = nil

    static let fenceColors: [UInt32] = [0xED122A, 0x3D9BFF, 0x2ED19A, 0xF2A33A, 0xB07CFF, 0x00C8E0, 0xFF6FB5, 0xC9CBD1]
    static let lineOn: UInt32 = 0xFFD54A
    static let lineOff: UInt32 = 0x8F9BAD

    init(app: AppModel) {
        self.app = app
        self.planFile = AvoFiles.join(app.paths.root, "geocercas.json")
        self.plan = GeofencePlan.load(planFile)
    }

    // ---------------------------------------------------------------- contract
    func sessionChanged() {
        let id: String? = app.selected?.id
        refreshCrossings()
        if id != lastSessionId {
            lastSessionId = id
            fitRequest += 1
        }
    }

    func pageShown() {
        refreshCrossings()
        rev += 1
    }

    // ---------------------------------------------------------------- slots
    func fence(_ i: Int) -> PlanFence? { (i >= 0 && i < plan.fences.count) ? plan.fences[i] : nil }
    func line(_ i: Int) -> PlanLine { plan.lines[i] }

    func fenceTitle(_ i: Int) -> String {
        _ = rev
        guard let f = fence(i) else { return "Hueco \(i + 1) · libre" }
        return "\(i + 1). \(f.name)"
    }
    func fenceDetail(_ i: Int) -> String {
        _ = rev
        guard let f = fence(i) else { return "Sin geocerca" }
        let act: String = f.active ? " · activa" : " · inactiva"
        if f.type == .circle { return "Círculo · radio \(AvoFormat.f(f.radiusM, 0)) m" + act }
        return "Polígono · \(f.vertices.count) vértices" + act
    }
    func fenceProblem(_ i: Int) -> String? { _ = rev; return fence(i)?.problem() }

    func lineTitle(_ i: Int) -> String { _ = rev; return "Línea \(i + 1) · \(line(i).name)" }
    func lineDetail(_ i: Int) -> String {
        _ = rev
        let l = line(i)
        if !l.enabled { return "Desactivada" }
        if l.a == nil || l.b == nil { return "Marca A y B en el mapa" }
        return "\(AvoFormat.f(l.lengthM, 0)) m · \(GeofencesModel.directionText(l.direction))" + (i == 0 ? " · el reloj cronometra vueltas" : "")
    }
    func lineProblem(_ i: Int) -> String? { _ = rev; return line(i).problem() }

    static func directionText(_ d: LineDirection) -> String {
        switch d {
        case .leftToRight: return "marca solo en el sentido de la flecha"
        case .rightToLeft: return "marca solo en sentido contrario"
        case .both: return "marca en ambos sentidos"
        }
    }
    static func directionLabel(_ d: LineDirection) -> String {
        switch d {
        case .both: return "Ambos sentidos"
        case .leftToRight: return "Solo en el sentido de la flecha"
        case .rightToLeft: return "Solo en sentido contrario"
        }
    }
    static func roleLabel(_ r: LineRole) -> String {
        switch r {
        case .startFinish: return "Salida y meta (vueltas)"
        case .start: return "Salida"
        case .finish: return "Meta"
        case .checkpoint: return "Control"
        }
    }

    func selectFence(_ i: Int) { selectedFence = i; selectedLine = nil; rev += 1 }
    func selectLine(_ i: Int) { selectedLine = i; selectedFence = nil; rev += 1 }

    var editingFence: Bool { selectedFence != nil }
    var editingFenceShape: Bool { _ = rev; return selectedFence.flatMap { fence($0) } != nil }
    var editingLine: Bool { selectedLine != nil }
    var editingCircle: Bool { _ = rev; return selectedFence.flatMap { fence($0) }?.type == .circle }
    var editingPolygon: Bool { _ = rev; return selectedFence.flatMap { fence($0) }?.type == .polygon }

    var geoHint: String {
        _ = rev
        if let i = selectedFence {
            guard let f = fence(i) else { return "Hueco libre: elige «Círculo» o «Polígono» y toca el mapa." }
            if f.type == .circle { return "Toca el mapa = centro del círculo. Ajusta el radio abajo." }
            return "Toca el mapa = nuevo vértice (\(f.vertices.count)/\(Fence.maxVertices)). El polígono se cierra solo."
        }
        if let i = selectedLine {
            let l = line(i)
            if l.a == nil { return "Toca el mapa = extremo A de la línea." }
            if l.b == nil { return "Toca el mapa = extremo B de la línea." }
            return "Toca el mapa = empezar de nuevo por el extremo A."
        }
        return "Elige una geocerca o una línea."
    }

    var geoProblem: String {
        _ = rev
        let p: String? = selectedFence.flatMap { fence($0)?.problem() } ?? selectedLine.flatMap { line($0).problem() }
        if let p = p { return p }
        return (editingFenceShape || editingLine) ? "Correcto: se puede enviar" : ""
    }
    var geoProblemOk: Bool {
        _ = rev
        let p: String? = selectedFence.flatMap { fence($0)?.problem() } ?? selectedLine.flatMap { line($0).problem() }
        return p == nil
    }

    var geoSummary: String {
        _ = rev
        let f: Int = plan.fences.filter { $0 != nil }.count
        let l: Int = plan.lines.filter { $0.enabled }.count
        var s = "\(f) geocerca(s) · \(l) línea(s) activas · grabación automática \(plan.autoEnabled ? "sí" : "no")"
        if let d = plan.lastSent {
            s += " · último envío \(AvoTime.text(d, "dd/MM/yyyy HH:mm")) a \(plan.lastSentTo ?? "")"
        } else {
            s += " · sin enviar todavía"
        }
        return s
    }
    var geoProblems: [String] { _ = rev; return plan.problems() }

    // ---------------------------------------------------------------- fence fields
    var fenceName: String {
        get { _ = rev; return selectedFence.flatMap { fence($0) }?.name ?? "" }
        set {
            guard let f = selectedFence.flatMap({ fence($0) }) else { return }
            f.name = newValue.count > 15 ? String(newValue.prefix(15)) : newValue
            geoChanged(redraw: false)
        }
    }
    var fenceRadius: Double {
        get { _ = rev; return selectedFence.flatMap { fence($0) }?.radiusM ?? 50 }
        set {
            guard let f = selectedFence.flatMap({ fence($0) }) else { return }
            f.radiusM = min(max(newValue.rounded(), 5), 5000)
            geoChanged(redraw: false)     // fences do not change the line crossings
        }
    }
    var fenceActive: Bool {
        get { _ = rev; return selectedFence.flatMap { fence($0) }?.active ?? false }
        set {
            guard let f = selectedFence.flatMap({ fence($0) }) else { return }
            f.active = newValue
            geoChanged()
        }
    }
    var geoAuto: Bool {
        get { _ = rev; return plan.autoEnabled }
        set { plan.autoEnabled = newValue; geoChanged(redraw: false) }
    }

    // ---------------------------------------------------------------- line fields
    var lineName: String {
        get { _ = rev; return selectedLine.map { line($0).name } ?? "" }
        set {
            guard let i = selectedLine else { return }
            line(i).name = newValue.count > 30 ? String(newValue.prefix(30)) : newValue
            geoChanged(redraw: false)
        }
    }
    var lineEnabled: Bool {
        get { _ = rev; return selectedLine.map { line($0).enabled } ?? false }
        set { guard let i = selectedLine else { return }; line(i).enabled = newValue; geoChanged() }
    }
    var lineRole: LineRole {
        get { _ = rev; return selectedLine.map { line($0).role } ?? .startFinish }
        set { guard let i = selectedLine else { return }; line(i).role = newValue; geoChanged() }
    }
    var lineDirection: LineDirection {
        get { _ = rev; return selectedLine.map { line($0).direction } ?? .both }
        set { guard let i = selectedLine else { return }; line(i).direction = newValue; geoChanged() }
    }

    // ---------------------------------------------------------------- editing
    func newFence(_ type: FenceType) {
        guard let i = selectedFence else { return }
        let old: PlanFence? = fence(i)
        if let o = old, o.type == type { return }
        let name: String = (old?.name.isEmpty == false) ? (old?.name ?? "") : "Geocerca \(i + 1)"
        let f = PlanFence(name: name, type: type, center: nil, radiusM: old?.radiusM ?? 50, vertices: [], active: old?.active ?? true)
        if let o = old, type == .circle, !o.vertices.isEmpty {
            var la = 0.0, lo = 0.0
            for v in o.vertices { la += v.lat; lo += v.lon }
            f.center = PlanPoint(la / Double(o.vertices.count), lo / Double(o.vertices.count))
        }
        plan.fences[i] = f
        geoChanged()
    }

    func undoVertex() {
        guard let f = selectedFence.flatMap({ fence($0) }), f.type == .polygon, !f.vertices.isEmpty else { return }
        f.vertices.removeLast()
        geoChanged()
    }

    func clearShape() {
        if let f = selectedFence.flatMap({ fence($0) }) {
            f.center = nil
            f.vertices = []
            geoChanged()
        } else if let i = selectedLine {
            line(i).a = nil
            line(i).b = nil
            geoChanged()
        }
    }

    func askDeleteFence() {
        guard let i = selectedFence, let f = fence(i) else { return }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let ok: Bool = await self.ask("Geocercas", "¿Vaciar el hueco \(i + 1) («\(f.name)»)? En el reloj se borrará al enviar.", "Vaciar")
            if !ok { return }
            self.plan.fences[i] = nil
            self.geoChanged()
        }
    }

    /// Tap on the map (C# OnGeoClick): centre of the circle, new polygon vertex or line end.
    func mapTap(lat: Double, lon: Double) {
        let pt = PlanPoint((lat * 1e7).rounded() / 1e7, (lon * 1e7).rounded() / 1e7)
        if let i = selectedFence {
            if fence(i) == nil { newFence(.circle) }
            guard let f = fence(i) else { return }
            if f.type == .circle {
                f.center = pt
            } else if f.vertices.count < Fence.maxVertices {
                f.vertices.append(pt)
            }
            geoChanged()
        } else if let i = selectedLine {
            let l = line(i)
            if l.a == nil {
                l.a = pt
            } else if l.b == nil {
                l.b = pt
                l.enabled = true
            } else {
                l.a = pt
                l.b = nil
            }
            geoChanged()
        }
    }

    func geoChanged(redraw: Bool = true) {
        do {
            try plan.save(planFile)
        } catch {
            app.log.warn("geocercas", error.localizedDescription, error)
        }
        if redraw { refreshCrossings() }
        rev += 1
    }

    // ---------------------------------------------------------------- crossings of the open training
    var crossingsTitle: String {
        guard let s = app.selected else { return "Cruces de líneas (abre un entrenamiento)" }
        return "Cruces de líneas en \(s.dateTimeText)"
    }
    var crossingsEmpty: String {
        _ = rev
        if app.selected == nil { return "Abre un entrenamiento para ver por dónde cruzó las líneas." }
        if plan.lines.allSatisfy({ !$0.enabled || $0.a == nil || $0.b == nil }) { return "No hay líneas activas con sus dos extremos." }
        if crossingRows.isEmpty { return "El recorrido de este entrenamiento no cruza ninguna línea activa." }
        return ""
    }
    var canCreateSegments: Bool { app.selected != nil && !runRows.isEmpty }

    private func detectAll(_ s: SessionItem) -> [LineCrossing] {
        var all: [LineCrossing] = []
        for i in 0..<4 {
            let l = plan.lines[i]
            if l.enabled && l.a != nil && l.b != nil { all.append(contentsOf: LineAnalysis.detect(s.timeline, l, i)) }
        }
        return all
    }

    func refreshCrossings() {
        var cr: [GeoCrossingRow] = []
        var rr: [GeoRunRow] = []
        var rs: [LineAnalysis.Run] = []
        if let s = app.selected, s.timeline.count > 1 {
            let all: [LineCrossing] = detectAll(s).sorted { $0.t < $1.t }
            for c in all {
                cr.append(GeoCrossingRow(line: plan.lines[c.line].name, time: TimeText.clock(c.t),
                                         direction: c.leftToRight ? "Sentido de la flecha" : "Sentido contrario",
                                         counts: c.counts, countsText: c.counts ? "Marca" : "No marca"))
            }
            rs = LineAnalysis.runs(plan.lines, all)
            for r in rs { rr.append(GeoRunRow(kind: r.kind, start: TimeText.clock(r.t0), duration: TimeText.clock(r.durationS))) }
        }
        crossingRows = cr
        runRows = rr
        runs = rs
    }

    /// «Crear tramos con estos tiempos»: replaces the line segments of the training (kind Lines) and opens Tramos.
    func linesToSegments() {
        guard let s = app.selected else { return }
        refreshCrossings()
        if runs.isEmpty { return }
        s.segmentDefs.removeAll { $0.kind == .lines }
        for r in runs {
            s.segmentDefs.append(SegmentDefinition(name: r.kind, t0: r.t0, t1: r.t1, kind: .lines,
                                                   notes: "Creado desde las líneas de salida/meta"))
        }
        do {
            try app.segmentStore.save(s.id, s.segmentDefs)
            app.status = "\(s.segmentDefs.count) tramos guardados (la telemetría original no se modifica)"
        } catch {
            app.log.error("tramos", error.localizedDescription, error)
            app.status = "No se pudieron guardar los tramos: " + error.localizedDescription
        }
        app.notifySessionChanged()
        app.page = .segments
    }

    // ---------------------------------------------------------------- confirmations
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

    // ---------------------------------------------------------------- watch (Bluetooth)
    /// Connects to the watch (scan, connect, authorize this iPad with BOOT if needed) and runs `work` (C# WithWatchAsync).
    @MainActor
    private func withWatch(_ work: @MainActor (IosWatchConnection, String) async throws -> Void) async {
        if watchBusy { return }
        watchBusy = true
        app.busy = true
        let report: (String) -> Void = { [weak self] (m: String) in
            Task { @MainActor in
                guard let self = self else { return }
                self.watchLinkStatus = m
                self.app.status = m
            }
        }
        var conn: IosWatchConnection? = nil
        do {
            let target: BleWatchFound? = try await WatchPicker.pick(progress: report, ask: { [weak self] (t: String, m: String, ok: String) async -> Bool in
                guard let self = self else { return false }
                return await self.ask(t, m, ok)
            })
            if let target = target {
                let c = try await IosWatchConnection.open(target: target, clientName: WatchPicker.clientName, progress: report)
                conn = c
                if !c.info.supportsFences { throw BleLinkError("El reloj \(c.info.firmware) no admite geocercas por Bluetooth.") }
                try await work(c, "\(target.name) · pecho \(c.info.firmware)")
            } else {
                watchLinkStatus = "Envío cancelado."
            }
        } catch {
            watchLinkStatus = "Reloj: " + error.localizedDescription
            app.log.warn("reloj", error.localizedDescription, error)
            app.show("Reloj AVO", error.localizedDescription, error: true)
        }
        conn?.close()
        watchBusy = false
        app.busy = false
    }

    @MainActor
    func sendToWatch() async {
        let problems: [String] = plan.problems()
        if !problems.isEmpty {
            app.show("Geocercas", "Corrige antes de enviar:\n\n" + problems.joined(separator: "\n"), error: true)
            return
        }
        await withWatch { (conn: IosWatchConnection, who: String) in
            let cur: WatchConfig = try WatchConfig.decode(try await conn.client.getConfig())
            let diff: [String] = GeofenceSync.differences(self.plan, cur)
            if diff.isEmpty {
                self.watchLinkStatus = "\(who): ya tiene exactamente estas geocercas y líneas."
                return
            }
            let dirNote: String = self.plan.lines.contains(where: { $0.enabled && $0.direction != .both })
                ? "\n\nAviso: el reloj cuenta los cruces de las líneas en los DOS sentidos (su firmware no guarda sentido). El sentido elegido se aplica al analizar el entrenamiento en este iPad."
                : ""
            let ok: Bool = await self.ask("Enviar al reloj",
                                          "Se cambiará en \(who): \(diff.joined(separator: ", ")).\(dirNote)\n\n¿Enviar?", "Enviar")
            if !ok {
                self.watchLinkStatus = "Envío cancelado."
                return
            }
            let report: (String) -> Void = { [weak self] (m: String) in
                Task { @MainActor in self?.watchLinkStatus = m }
            }
            let rep: SyncReport = try await GeofenceSync.send(conn.client, self.plan, progress: report)
            if rep.verified {
                self.plan.lastSent = Date()
                self.plan.lastSentTo = who
                self.geoChanged(redraw: false)
            }
            self.watchLinkStatus = (rep.verified ? "Enviado y comprobado: " : "Enviado con diferencias: ") + rep.steps.joined(separator: " · ")
            self.app.status = self.watchLinkStatus
            self.app.log.info("reloj", "geocercas enviadas", ["who": who, "verified": rep.verified, "steps": rep.steps] as [String: Any])
        }
    }

    @MainActor
    func readFromWatch() async {
        await withWatch { (conn: IosWatchConnection, who: String) in
            let cur: WatchConfig = try WatchConfig.decode(try await conn.client.getConfig())
            let d: [String] = GeofenceSync.differences(self.plan, cur)
            if !d.isEmpty {
                let ok: Bool = await self.ask("Leer del reloj",
                                              "Lo que tienes en el iPad se sustituirá por lo del reloj (\(d.joined(separator: ", "))). Los sentidos y nombres de las líneas se conservan. ¿Continuar?",
                                              "Sustituir")
                if !ok { return }
            }
            self.plan.loadFrom(cur)
            self.geoChanged()
            self.fitRequest += 1
            self.watchLinkStatus = "Leído de \(who)."
        }
    }
}
