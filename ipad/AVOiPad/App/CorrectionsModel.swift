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

    /// The training was deleted: its corrections go too.
    func forget(_ id: String) {
        if entries.removeValue(forKey: id) != nil { save() }
        if app.selected?.id == id { pendingRepStart = .nan; message = "" }
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
        // AVO-ASSIGN-1: the engine reports the assigned horse/rider (the RAW header may still say HORSE_001)
        let h = app.stable.store.resolve(item.session, .horse), r = app.stable.store.resolve(item.session, .rider)
        if let asg = AvoAssignment.engineOption(horseCode: h.code, horseName: h.known ? h.name : nil, riderCode: r.code, riderName: r.known ? r.name : nil) {
            parts.append(asg)
        }
        if let c = entries[item.id], !c.isEmpty {
            let f: String = c.optionsFragment()
            if !f.isEmpty { parts.append(f) }
        }
        return parts.joined(separator: ",")
    }

    var summaryText: String {
        guard let c = current, !c.isEmpty else { return "Zonas automáticas · arrastra los bordes en la gráfica para corregirlas" }
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

    // ------------------------------------------------------------------ drag handles on the speed profile
    /// Ids: 1 start of the work phase, 2 end of the work phase, 100 + 2k start and 101 + 2k end of repetition k.
    func handles(_ s: SessionItem?) -> [SyncHandle] {
        guard let s = s, let e = s.engine else { return [] }
        let tw: TrackWorkResult = e.trackWork
        let off: Double = s.engineOffsetS
        var h: [SyncHandle] = []
        if tw.work.present && tw.work.t0.isFinite && tw.work.t1.isFinite {
            h.append(SyncHandle(id: 1, x: tw.work.t0 - off, color: CorrectionsModel.workColor, label: "Inicio trabajo"))
            h.append(SyncHandle(id: 2, x: tw.work.t1 - off, color: CorrectionsModel.workColor, label: "Fin trabajo"))
        }
        for (k, w) in tw.efforts.enumerated() {
            let c: Color = w.kind == "TRABAJO_RAPIDO" ? CorrectionsModel.fastColor : CorrectionsModel.canterColor
            h.append(SyncHandle(id: 100 + 2 * k, x: w.t0 - off, color: c, label: "Inicio rep. \(k + 1)", lane: 1))
            h.append(SyncHandle(id: 101 + 2 * k, x: w.t1 - off, color: c, label: "Fin rep. \(k + 1)", lane: 1))
        }
        return h
    }

    /// A handle was dropped at `t` (timeline seconds): moves that limit and analyses again.
    func moveHandle(_ id: Int, to t: Double) {
        guard let s = app.selected, t.isFinite else { return }
        let v: Double = itow(s, t)
        if id == 1 || id == 2 {
            mutate { (c: inout TrainingCorrection) in if id == 1 { c.workStartItow = v } else { c.workEndItow = v } }
            message = (id == 1 ? "Inicio" : "Fin") + " del trabajo movido a \(TimeText.clock(t))"
            return
        }
        guard id >= 100 else { return }
        let k: Int = (id - 100) / 2
        let isEnd: Bool = (id - 100) % 2 == 1
        var moved: Bool = false
        mutate { (c: inout TrainingCorrection) in
            var list: [[Double]] = c.works ?? self.automaticWorks(s)
            guard k < list.count, list[k].count == 2 else { return }
            var w: [Double] = list[k]
            if isEnd { w[1] = max(v, w[0] + 2000) } else { w[0] = min(v, w[1] - 2000) }
            list[k] = w
            list.sort { $0[0] < $1[0] }
            c.works = list
            moved = true
        }
        message = moved ? "Repetición \(k + 1): \(isEnd ? "fin" : "inicio") en \(TimeText.clock(t))" : "No se pudo mover la repetición"
    }

    // ------------------------------------------------------------------ start / finish lines on the map
    func mapLines(_ s: SessionItem?) -> [MapCourseLine] {
        guard let s = s, let c = entries[s.id] else { return [] }
        var out: [MapCourseLine] = []
        if let l = c.start { out.append(CorrectionsModel.mapLine(l, id: "salida", title: "Salida", color: 0x30A46C)) }
        if let l = c.finish { out.append(CorrectionsModel.mapLine(l, id: "meta", title: "Meta", color: 0xE5484D)) }
        return out
    }

    /// The line and an arrow from its middle towards the side the horse crosses to (counting direction).
    static func mapLine(_ l: TrainingLine, id: String, title: String, color: UInt32) -> MapCourseLine {
        var m = MapCourseLine(id: id, title: title, colorHex: color, line: [[l.aLat, l.aLon], [l.bLat, l.bLon]])
        let lat0: Double = (l.aLat + l.bLat) / 2, lon0: Double = (l.aLon + l.bLon) / 2
        let ky: Double = 111_320.0, kx: Double = 111_320.0 * cos(lat0 * Double.pi / 180)
        let dx: Double = (l.bLon - l.aLon) * kx, dy: Double = (l.bLat - l.aLat) * ky
        let n: Double = hypot(dx, dy)
        guard n > 0.5, l.direction != "AMBOS" else { return m }
        let ux: Double = dx / n, uy: Double = dy / n
        // seen from A towards B: DCHA_A_IZQ ends on the left (−uy, ux), IZQ_A_DCHA on the right (uy, −ux)
        let fx: Double = l.direction == "DCHA_A_IZQ" ? -uy : uy
        let fy: Double = l.direction == "DCHA_A_IZQ" ? ux : -ux
        func pt(_ e: Double, _ nn: Double) -> [Double] { [lat0 + nn / ky, lon0 + e / kx] }
        let tipE: Double = fx * 14, tipN: Double = fy * 14
        m.arrow = [[pt(0, 0), pt(tipE, tipN)],
                   [pt(tipE, tipN), pt(tipE - fx * 5 + ux * 4, tipN - fy * 5 + uy * 4)],
                   [pt(tipE, tipN), pt(tipE - fx * 5 - ux * 4, tipN - fy * 5 - uy * 4)]]
        return m
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
