import SwiftUI
import Observation

/// Zones of a training that the user can move («Botones mod. zonas» of the Análisis page): start and finish lines,
/// limits of the work phase and the repetitions. Stored per session in correcciones.json (absolute GPS time, iTOW ms);
/// the recorded files are never modified. Every change runs the engine again with the corrections as options.
@Observable
final class CorrectionsModel {
    unowned let app: AppModel

    private(set) var entries: [String: TrainingCorrection] = [:]
    /// Start of a repetition being marked (timeline seconds), waiting for «Fin repetición».
    var pendingRepStart: Double = .nan
    private(set) var message: String = ""

    init(app: AppModel) {
        self.app = app
        load()
    }

    // ------------------------------------------------------------------ storage
    private var file: String { AvoFiles.join(app.paths.root, "correcciones.json") }

    private func load() {
        guard let data = AvoFiles.read(file) else { return }
        var d: Data = data
        if d.starts(with: [0xEF, 0xBB, 0xBF]) { d = Data(d.dropFirst(3)) }
        if let e = try? JSONDecoder().decode([String: TrainingCorrection].self, from: d) {
            entries = e
        } else {
            app.log.warn("correcciones", "correcciones.json no válido: se ignora")
        }
    }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data: Data = try enc.encode(entries)
            try AvoFiles.writeAtomic(data, to: file)
        } catch {
            app.log.error("correcciones", "No se pudo guardar correcciones.json", error)
        }
    }

    // ------------------------------------------------------------------ queries
    func correction(_ id: String) -> TrainingCorrection? { entries[id] }
    var current: TrainingCorrection? { app.selected.flatMap { entries[$0.id] } }
    var hasCorrections: Bool { !(current?.isEmpty ?? true) }
    var canEdit: Bool { (app.selected?.timeline.count ?? 0) > 1 && app.cursorTime.isFinite }

    /// Engine options of one session: breed profile of its horse (Cuadra) plus the corrections.
    func engineOptions(_ item: SessionItem) -> String {
        var parts: [String] = []
        let breedText: String = app.stable.store.find(.horse, app.horseKey(item))?.breed ?? ""
        parts.append("\"raza\":" + AvoJSON.quote(TrackWorkBreed.engineName(breedText)))
        if let c = entries[item.id], !c.isEmpty {
            let f: String = c.optionsFragment()
            if !f.isEmpty { parts.append(f) }
        }
        return parts.joined(separator: ",")
    }

    var summaryText: String {
        guard let c = current, !c.isEmpty else { return "Zonas automáticas (velocidad RTK y cincha)" }
        var p: [String] = []
        if c.start != nil { p.append("salida") }
        if c.finish != nil { p.append("meta") }
        if c.workStartItow != nil || c.workEndItow != nil { p.append("fase de trabajo") }
        if let w = c.works { p.append("\(w.count) repeticiones") }
        return "Corregido a mano: " + p.joined(separator: ", ")
    }

    // ------------------------------------------------------------------ zones of the profile (timeline seconds)
    /// Bands under the speed profile: lane 0 phases, lane 1 repetitions, lane 2 course passes.
    func bands(_ s: SessionItem?) -> [SyncBand] {
        guard let s = s, let e = s.engine else { return [] }
        let tw: TrackWorkResult = e.trackWork
        let off: Double = s.engineOffsetS
        var b: [SyncBand] = []
        func add(_ t0: Double, _ t1: Double, _ c: Color, lane: Int) {
            guard t0.isFinite, t1.isFinite, t1 > t0 else { return }
            b.append(SyncBand(id: b.count, x0: t0 - off, x1: t1 - off, color: c, lane: lane, height: 7))
        }
        if tw.warmup.present { add(tw.warmup.t0, tw.warmup.t1, CorrectionsModel.warmupColor, lane: 0) }
        if tw.work.present { add(tw.work.t0, tw.work.t1, CorrectionsModel.workColor, lane: 0) }
        if tw.cooldown.present { add(tw.cooldown.t0, tw.cooldown.t1, CorrectionsModel.cooldownColor, lane: 0) }
        for w in tw.efforts {
            add(w.t0, w.t1, w.kind == "TRABAJO_RAPIDO" ? CorrectionsModel.fastColor : CorrectionsModel.canterColor, lane: 1)
        }
        for p in tw.passes { add(p.t0, p.t1, CorrectionsModel.passColor, lane: 2) }
        if pendingRepStart.isFinite, app.cursorTime.isFinite {
            let a: Double = min(pendingRepStart, app.cursorTime), z: Double = max(pendingRepStart, app.cursorTime)
            if z > a { b.append(SyncBand(id: b.count, x0: a, x1: z, color: Color.white.opacity(0.75), lane: 1, height: 7)) }
        }
        return b
    }

    static let warmupColor: Color = Color(hex: 0x3D8BFD)
    static let workColor: Color = Color(hex: 0xE5484D)
    static let cooldownColor: Color = Color(hex: 0x30A46C)
    static let fastColor: Color = Color(hex: 0xFF8B3E)
    static let canterColor: Color = Color(hex: 0xF5D90A)
    static let passColor: Color = Color(hex: 0xB78AF7)

    // ------------------------------------------------------------------ actions (cursor = point of the timeline)
    /// «Salida aquí» / «Meta aquí»: line across the route at the cursor, counted in the direction of motion.
    func setLine(finish: Bool) {
        guard let s = app.selected, let line = lineAtCursor(s) else {
            message = "Sin posición GPS en este punto: mueve la barra de tiempo"
            return
        }
        mutate { (c: inout TrainingCorrection) in if finish { c.finish = line } else { c.start = line } }
        message = finish ? "Meta marcada en \(TimeText.clock(app.cursorTime))" : "Salida marcada en \(TimeText.clock(app.cursorTime))"
    }

    /// «Inicio trabajo» / «Fin trabajo»: limits of the work phase (warm-up before, cool-down after).
    func setWorkLimit(end: Bool) {
        guard let s = app.selected, canEdit else { return }
        let v: Double = itow(s, app.cursorTime)
        mutate { (c: inout TrainingCorrection) in if end { c.workEndItow = v } else { c.workStartItow = v } }
        message = end ? "Fin del trabajo en \(TimeText.clock(app.cursorTime))" : "Inicio del trabajo en \(TimeText.clock(app.cursorTime))"
    }

    func beginRepetition() {
        guard canEdit else { return }
        pendingRepStart = app.cursorTime
        message = "Inicio de repetición en \(TimeText.clock(app.cursorTime)): mueve la barra y pulsa «Fin repetición»"
    }

    func endRepetition() {
        guard let s = app.selected, canEdit, pendingRepStart.isFinite else { return }
        let a: Double = min(pendingRepStart, app.cursorTime), z: Double = max(pendingRepStart, app.cursorTime)
        pendingRepStart = .nan
        if z - a < 2 { message = "Repetición demasiado corta"; return }
        let span: [Double] = [itow(s, a), itow(s, z)]
        mutate { (c: inout TrainingCorrection) in
            var list: [[Double]] = c.works ?? self.automaticWorks(s)
            list.removeAll { (w: [Double]) -> Bool in w.count == 2 && w[0] < span[1] && w[1] > span[0] }   // replaces overlapping ones
            list.append(span)
            list.sort { $0[0] < $1[0] }
            c.works = list
        }
        message = "Repetición \(TimeText.clock(a)) – \(TimeText.clock(z)) guardada"
    }

    /// Removes the repetition under the cursor.
    func removeRepetitionAtCursor() {
        guard let s = app.selected, canEdit else { return }
        let x: Double = itow(s, app.cursorTime)
        var removed: Bool = false
        mutate { (c: inout TrainingCorrection) in
            var list: [[Double]] = c.works ?? self.automaticWorks(s)
            let n: Int = list.count
            list.removeAll { (w: [Double]) -> Bool in w.count == 2 && w[0] <= x && x <= w[1] }
            removed = list.count != n
            c.works = list
        }
        message = removed ? "Repetición quitada" : "No hay ninguna repetición en este punto"
    }

    /// Back to the automatic zones of this training.
    func reset() {
        guard let s = app.selected else { return }
        pendingRepStart = .nan
        if entries[s.id] == nil { message = "Ya está en automático"; return }
        entries[s.id] = nil
        save()
        message = "Zonas automáticas restablecidas"
        reanalyse(s)
    }

    // ------------------------------------------------------------------ helpers
    private func mutate(_ f: (inout TrainingCorrection) -> Void) {
        guard let s = app.selected else { return }
        var c: TrainingCorrection = entries[s.id] ?? TrainingCorrection()
        f(&c)
        entries[s.id] = c.isEmpty ? nil : c
        save()
        reanalyse(s)
    }

    private func reanalyse(_ s: SessionItem) {
        Task { @MainActor in await self.app.runEngine(s, force: true) }
    }

    /// Absolute GPS time (iTOW ms) of a timeline time.
    private func itow(_ s: SessionItem, _ t: Double) -> Double { Double(s.timeline.itow0Ms) + t * 1000.0 }

    /// Repetitions found by the engine, as iTOW spans (the starting point of a manual list).
    private func automaticWorks(_ s: SessionItem) -> [[Double]] {
        guard let e = s.engine, let e0 = e.itow0Ms else { return [] }
        return e.trackWork.efforts.map { (w: TrackWorkEffort) -> [Double] in [Double(e0) + w.t0 * 1000.0, Double(e0) + w.t1 * 1000.0] }
    }

    /// Line of 50 m across the route at the cursor: A on the left of the motion, B on the right, so moving forward
    /// crosses it from right to left (DCHA_A_IZQ, seen from A towards B, as the watch and AVO Windows).
    private func lineAtCursor(_ s: SessionItem) -> TrainingLine? {
        let tl: SessionTimeline = s.timeline
        guard app.cursorTime.isFinite, tl.count > 2 else { return nil }
        let i: Int = tl.indexAt(app.cursorTime)
        guard i >= 0 else { return nil }
        func valid(_ k: Int) -> Bool { k >= 0 && k < tl.count && tl.lat[k].isFinite && tl.lon[k].isFinite && !(tl.lat[k] == 0 && tl.lon[k] == 0) }
        var c: Int = i
        if !valid(c) {
            var found: Int = -1
            for d in 1..<min(200, tl.count) {
                if valid(i - d) { found = i - d; break }
                if valid(i + d) { found = i + d; break }
            }
            if found < 0 { return nil }
            c = found
        }
        let lat0: Double = tl.lat[c], lon0: Double = tl.lon[c]
        let ky: Double = 111_320.0, kx: Double = 111_320.0 * cos(lat0 * Double.pi / 180)
        // direction of motion: the nearest points at least 3 m before and after
        var a: Int = c, b: Int = c
        while a > 0 {
            a -= 1
            if valid(a), hypot((tl.lon[a] - lon0) * kx, (tl.lat[a] - lat0) * ky) >= 3 { break }
        }
        while b < tl.count - 1 {
            b += 1
            if valid(b), hypot((tl.lon[b] - lon0) * kx, (tl.lat[b] - lat0) * ky) >= 3 { break }
        }
        guard valid(a), valid(b), a != b else { return nil }
        var fx: Double = (tl.lon[b] - tl.lon[a]) * kx, fy: Double = (tl.lat[b] - tl.lat[a]) * ky
        let n: Double = hypot(fx, fy)
        guard n > 0.5 else { return nil }
        fx /= n; fy /= n
        let rx: Double = fy, ry: Double = -fx      // right of the motion
        let half: Double = 25
        return TrainingLine(aLat: lat0 - ry * half / ky, aLon: lon0 - rx * half / kx,
                            bLat: lat0 + ry * half / ky, bLon: lon0 + rx * half / kx,
                            direction: "DCHA_A_IZQ")
    }
}
