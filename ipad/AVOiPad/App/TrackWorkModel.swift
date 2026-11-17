import SwiftUI
import Observation

/// Columns of the table of efforts / passes of «Trabajo en pista».
enum TrackWorkSortColumn: String, CaseIterable {
    case type, start, duration, distance, vmax, mean, last200, last400, fatigue, recovery, lead
}

/// Point of the speed-over-distance curve of one effort.
struct TrackWorkCurvePoint: Identifiable {
    var id: Int
    var distanceM: Double
    var speedKmh: Double
}

/// «Trabajo en pista» (AVO Track Work 1.0.0) of the selected training: selected effort / pass, sorting of the table.
/// Selecting an effort sets the range and the cursor of the app, so «Análisis» (map) and «Gráficas» follow it.
@Observable
final class TrackWorkModel {
    @ObservationIgnored unowned let app: AppModel
    @ObservationIgnored private var sessionId: String = ""

    var selectedKey: String? = nil
    var sortColumn: TrackWorkSortColumn = .start
    var ascending: Bool = true
    /// Bar chart of the splits: false = time (s), true = speed (km/h).
    var splitsBySpeed: Bool = false

    init(app: AppModel) {
        self.app = app
    }

    // ---------------------------------------------------------------- contract
    func sessionChanged() {
        let id: String = app.selected?.id ?? ""
        if id != sessionId {
            sessionId = id
            selectedKey = nil
            return
        }
        // a new engine result (corrections) can renumber the efforts
        if let k = selectedKey, result?.effort(k) == nil { selectedKey = nil }
    }

    func pageShown() {
        sessionChanged()
        // CI screenshots: show the detail of the fastest effort (without moving the range of the other pages)
        if app.captureMode && selectedKey == nil, let r = result {
            let best: TrackWorkEffort? = r.allEfforts.max { ($0.vmaxOpt ?? 0) < ($1.vmaxOpt ?? 0) }
            selectedKey = best?.key
        }
    }

    // ---------------------------------------------------------------- data
    var result: TrackWorkResult? {
        guard let e = app.selected?.engine, e.trackWork.present else { return nil }
        return e.trackWork
    }

    /// engine time − offset = timeline time.
    var offset: Double { app.selected?.engineOffsetS ?? 0 }

    var selected: TrackWorkEffort? {
        guard let k = selectedKey else { return nil }
        return result?.effort(k)
    }

    /// Breed text of the horse card (Cuadra) of the selected training, "" when unknown.
    var horseBreedText: String {
        guard let s = app.selected else { return "" }
        return app.stable.store.find(.horse, app.horseKey(s))?.breed ?? ""
    }

    /// Engine profile that the horse card asks for (it may differ from the one of the stored result).
    var horseProfile: String { TrackWorkBreed.engineName(horseBreedText) }

    // ---------------------------------------------------------------- actions
    func select(_ e: TrackWorkEffort) {
        selectedKey = e.key
        let a: Double = e.t0 - offset, b: Double = e.t1 - offset
        guard a.isFinite, b.isFinite, b > a else { return }
        app.rangeStart = a
        app.rangeEnd = b
        app.cursorTime = a
        // Gráficas: show the effort with a margin (applied when the page is shown)
        let pad: Double = max(5, (b - a) * 0.15)
        app.charts.setViewport(a - pad, b + pad, refresh: app.page == .charts)
    }

    func clearSelection() {
        selectedKey = nil
    }

    func sort(by c: TrackWorkSortColumn) {
        if sortColumn == c { ascending.toggle() } else { sortColumn = c; ascending = true }
    }

    /// Efforts and passes sorted by the chosen column (missing values always last).
    func sorted(_ list: [TrackWorkEffort]) -> [TrackWorkEffort] {
        let asc: Bool = ascending
        let col: TrackWorkSortColumn = sortColumn
        func value(_ e: TrackWorkEffort) -> Double? {
            switch col {
            case .type: return e.isPass ? 2 : (e.kind == "TRABAJO_RAPIDO" ? 1 : 0)
            case .start: return e.t0
            case .duration: return e.durationOpt
            case .distance: return e.distanceOpt
            case .vmax: return e.vmaxOpt
            case .mean: return e.speedMeanOpt
            case .last200: return e.last200Opt
            case .last400: return e.last400S
            case .fatigue: return e.fatigueOpt
            case .recovery: return e.recoveryOpt
            case .lead: return (e.leadLeft + e.leadRight) > 0 ? Double(e.leadLeft - e.leadRight) : nil
            }
        }
        return list.sorted { (a: TrackWorkEffort, b: TrackWorkEffort) -> Bool in
            let va: Double? = value(a), vb: Double? = value(b)
            switch (va, vb) {
            case (nil, nil): return a.t0 < b.t0
            case (nil, _): return false
            case (_, nil): return true
            default:
                let x: Double = va ?? 0, y: Double = vb ?? 0
                if x == y { return a.t0 < b.t0 }
                return asc ? x < y : x > y
            }
        }
    }

    /// Speed (km/h) against distance (m) of one effort, from the engine series.
    func speedCurve(_ e: TrackWorkEffort) -> [TrackWorkCurvePoint] {
        guard let en = app.selected?.engine else { return [] }
        let pts: [(d: Double, v: Double)] = TrackWorkResult.speedOverDistance(t: en.t, speed: en.speed, t0: e.t0, t1: e.t1)
        var out: [TrackWorkCurvePoint] = []
        for (i, p) in pts.enumerated() { out.append(TrackWorkCurvePoint(id: i, distanceM: p.d, speedKmh: p.v * 3.6)) }
        return out
    }

    /// Opens the map page (Análisis) with the selected effort as range.
    func showOnMap() {
        app.page = .analysis
    }

    func showOnCharts() {
        app.page = .charts
    }
}
