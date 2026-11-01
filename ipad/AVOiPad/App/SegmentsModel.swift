import SwiftUI
import Observation

/// Port of MainViewModel.Segments.cs: persistent segments ("tramos") of the selected session, stored apart from the
/// telemetry (SegmentStore, schema avo-windows-segments v1), with their metrics (SegmentAnalyzer.compute).
@Observable
final class SegmentsModel {
    unowned let app: AppModel

    private(set) var rows: [SegmentMetrics] = []
    private(set) var selectedId: String? = nil
    var segmentName: String = ""
    var segmentNotes: String = ""
    var segmentKind: SegmentKind = .manual
    var segmentLength: Double = 500
    let segmentLengths: [Double] = [100, 200, 400, 500, 800, 1000, 2000]
    private(set) var detail: [SyncStatRow] = []
    private(set) var speedPanel: SyncPanel = SyncPanel()
    /// Start marked with «Marcar inicio en el cursor» (NaN = none).
    private(set) var pendingStart: Double = .nan
    /// CSV of the metrics table ready to share (regenerated with «Exportar CSV»).
    private(set) var exportURL: URL? = nil

    init(app: AppModel) {
        self.app = app
    }

    var selected: SegmentMetrics? {
        guard let id = selectedId else { return nil }
        return rows.first { $0.id == id }
    }

    var observations: String { selected?.observations ?? "" }

    var hasSession: Bool { app.selected != nil }
    var hasEngineGait: Bool { app.selected?.engine?.hasImu == true }

    func sessionChanged() {
        pendingStart = .nan
        exportURL = nil
        refreshRows(nil)
    }

    func pageShown() {
        refreshRows(selectedId)
    }

    static func kindName(_ k: SegmentKind) -> String {
        switch k {
        case .manual: return "Manual"
        case .distance: return "Por distancia"
        case .speedBand: return "Banda de velocidad"
        case .engine: return "Aire (motor)"
        case .lines: return "Líneas"
        }
    }

    // ------------------------------------------------------------ selection (Windows SelectedSegment setter)
    func select(_ id: String?) {
        selectedId = id
        if let m = selected {
            segmentName = m.name
            segmentNotes = m.notes
            segmentKind = m.kind
            app.rangeStart = m.t0
            app.rangeEnd = m.t1
            app.cursorTime = m.t0
        } else {
            segmentName = ""
            segmentNotes = ""
            segmentKind = .manual
        }
        refreshDetail()
    }

    // ------------------------------------------------------------ commands
    func addFromRange() {
        guard let s = app.selected else { return }
        if !app.hasRange {
            app.status = "Selecciona un intervalo en una gráfica (mantén pulsado y arrastra, o «Seleccionar rango»)"
            return
        }
        let n: Int = s.segmentDefs.filter { $0.kind == .manual }.count + 1
        let d = SegmentDefinition(name: "Tramo manual \(n)", t0: min(app.rangeStart, app.rangeEnd), t1: max(app.rangeStart, app.rangeEnd))
        addDefs([d], replaceKind: false)
    }

    /// Touch flow without a range: first tap marks the start at the cursor, second tap creates the segment up to the cursor.
    func markFromCursor() {
        guard let s = app.selected else { return }
        let t: Double = app.cursorTime
        if !t.isFinite {
            app.status = "Coloca el cursor en el mapa o en las gráficas"
            return
        }
        if !pendingStart.isFinite {
            pendingStart = t
            app.status = "Inicio del tramo marcado en \(TimeText.clock(t)); mueve el cursor al final y pulsa «Crear hasta el cursor»"
            return
        }
        let a: Double = min(pendingStart, t)
        let b: Double = max(pendingStart, t)
        pendingStart = .nan
        if b - a <= 0.5 {
            app.status = "El tramo debe durar más de 0,5 s"
            return
        }
        let n: Int = s.segmentDefs.filter { $0.kind == .manual }.count + 1
        addDefs([SegmentDefinition(name: "Tramo manual \(n)", t0: a, t1: b)], replaceKind: false)
    }

    func cancelMark() { pendingStart = .nan }

    func autoDistance() {
        guard let s = app.selected else { return }
        addDefs(SegmentAnalyzer.byDistance(s.timeline, segmentLength), replaceKind: true, kind: .distance)
    }

    func autoSpeedBand() {
        guard let s = app.selected else { return }
        addDefs(SegmentAnalyzer.bySpeedBand(s.timeline), replaceKind: true, kind: .speedBand)
    }

    func fromEngine() {
        guard let s = app.selected, let e = s.engine, e.hasImu else {
            app.status = "Los tramos por aire necesitan datos de cincha y el motor AVO"
            return
        }
        addDefs(SegmentAnalyzer.fromEngine(e, s.engineOffsetS), replaceKind: true, kind: .engine)
    }

    /// Windows SaveSegmentCommand: rename, notes (and kind), and the current chart selection as new limits.
    func saveSelected() {
        guard let s = app.selected, let id = selectedId, let d = s.segmentDefs.first(where: { $0.id == id }) else { return }
        let name: String = segmentName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { d.name = name }
        d.notes = segmentNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        d.kind = segmentKind
        if app.hasRange {
            d.t0 = min(app.rangeStart, app.rangeEnd)
            d.t1 = max(app.rangeStart, app.rangeEnd)
        }
        persist()
        refreshRows(d.id)
    }

    func deleteSelected() {
        guard let s = app.selected, let id = selectedId else { return }
        s.segmentDefs.removeAll { $0.id == id }
        persist()
        refreshRows(nil)
    }

    func delete(_ id: String) {
        guard let s = app.selected else { return }
        s.segmentDefs.removeAll { $0.id == id }
        persist()
        refreshRows(selectedId == id ? nil : selectedId)
    }

    func clearAll() {
        guard let s = app.selected else { return }
        s.segmentDefs.removeAll()
        persist()
        refreshRows(nil)
    }

    private func addDefs(_ defs: [SegmentDefinition], replaceKind: Bool, kind: SegmentKind = .manual) {
        guard let s = app.selected else { return }
        if replaceKind { s.segmentDefs.removeAll { $0.kind == kind } }
        var last: String? = nil
        for d in defs {
            s.segmentDefs.append(d)
            last = d.id
        }
        persist()
        refreshRows(last)
        app.status = "\(s.segmentDefs.count) tramos guardados (la telemetría original no se modifica)"
    }

    private func persist() {
        guard let s = app.selected else { return }
        do {
            try app.segmentStore.save(s.session.sessionId, s.segmentDefs)
        } catch {
            app.log.error("tramos", error.localizedDescription, error)
            app.status = "No se pudieron guardar los tramos: " + error.localizedDescription
        }
        exportURL = nil
    }

    // ------------------------------------------------------------ rows / detail
    func refreshRows(_ selectId: String?) {
        var out: [SegmentMetrics] = []
        if let s = app.selected {
            let defs: [SegmentDefinition] = s.segmentDefs.sorted { (a: SegmentDefinition, b: SegmentDefinition) -> Bool in a.t0 < b.t0 }
            for d in defs {
                out.append(SegmentAnalyzer.compute(s.timeline, d, engine: s.engine, engineOffsetS: s.engineOffsetS))
            }
        }
        rows = out
        if let id = selectId, out.contains(where: { $0.id == id }) {
            selectedId = id
            if let m = selected { segmentName = m.name; segmentNotes = m.notes; segmentKind = m.kind }
        } else {
            selectedId = nil
        }
        refreshDetail()
    }

    private func refreshDetail() {
        guard let s = app.selected, let m = selected else {
            detail = []
            speedPanel = SyncPanel()
            return
        }
        detail = ChartsModel.metricRows(m)
        let tl: SessionTimeline = s.timeline
        let src = SyncSource(name: "Velocidad filtrada", color: Avo.blue, width: 1.6, x: tl.t, y: tl.speedFiltered.map { $0 * 3.6 },
                             breaks: tl.breakBefore)
        speedPanel = ChartsModel.makePanel([src], m.t0, m.t1, threshold: 1000)
    }

    // ------------------------------------------------------------ export
    /// CSV (semicolon, invariant numbers, UTF-8 with BOM, as the Windows CSV exports) of the metrics table.
    static func csvText(_ rows: [SegmentMetrics]) -> String {
        let nl: String = "\r\n"
        func f(_ v: Double?, _ fmt: String) -> String {
            guard let d = v, d.isFinite else { return "" }
            return DotNetFormat.custom(d, fmt, spanish: false)
        }
        func q(_ s: String) -> String {
            if s.contains(";") || s.contains("\"") || s.contains("\n") || s.contains("\r") {
                return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            return s
        }
        var out: String = "id;nombre;tipo;inicio_s;fin_s;duracion_s;distancia_m;vel_media_kmh;vel_max_kmh;acel_max_validada_ms2;" +
            "frenada_max_validada_ms2;cambios_ritmo;rtk_fix_pct;float_o_mejor_pct;hacc_media_m;perdidas_senal;cadencia_ciclos_min;" +
            "correlacion_ciclos;cv_intervalos;observaciones;notas" + nl
        for m in rows {
            var c: [String] = []
            c.append(q(m.id)); c.append(q(m.name)); c.append(m.kind.rawValue)
            c.append(f(m.t0, "0.000")); c.append(f(m.t1, "0.000")); c.append(f(m.durationS, "0.000")); c.append(f(m.distanceM, "0.00"))
            c.append(f(m.meanSpeedKmh, "0.00")); c.append(f(m.maxSpeedKmh, "0.00")); c.append(f(m.maxAccel, "0.000")); c.append(f(m.maxDecel, "0.000"))
            c.append(String(m.speedChanges)); c.append(f(m.fixFraction * 100, "0.0")); c.append(f(m.floatOrBetterFraction * 100, "0.0"))
            c.append(f(m.meanHAccM, "0.000")); c.append(String(m.gapCount)); c.append(f(m.cadence, "0.0"))
            c.append(f(m.cycleCorrelation, "0.000")); c.append(f(m.intervalCv, "0.000"))
            c.append(q(m.observations)); c.append(q(m.notes))
            out += c.joined(separator: ";") + nl
        }
        return out
    }

    func exportCsv() {
        guard let s = app.selected, !rows.isEmpty else { return }
        var data: Data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(SegmentsModel.csvText(rows).utf8))
        let name: String = SyncExportFiles.name("tramos", s.session.sessionId, "csv")
        switch SyncExportFiles.write(data, root: app.paths.root, name: name) {
        case .success(let url):
            exportURL = url
            app.status = "CSV de tramos preparado: \(url.lastPathComponent)"
        case .failure(let e):
            app.log.error("tramos", e.localizedDescription, e)
            app.show("Exportar tramos", e.localizedDescription, error: true)
        }
    }
}
