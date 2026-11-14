import Foundation

/// Calendario, navegador de sesiones y «abrir en Gráficas» desde «Datos clave» (paridad con MainViewModel.Parity.cs).
extension AppModel {
    /// Trainings as calendar / navigator entries (same fields as Windows CalendarEntries()).
    var calendarEntries: [CalendarEntry] {
        sessions.compactMap { (s: SessionItem) -> CalendarEntry? in
            guard let d = s.start else { return nil }
            let dur: Double = s.timeline.count > 1 ? s.timeline.durationS : s.session.durationSeconds
            let fix: Double? = s.engine.map { KeyData.cached(id: s.id, json: $0.rawJson).fixShare } ?? nil
            return CalendarEntry(id: s.id, start: d, horse: s.horse.isEmpty ? "Sin caballo" : s.horse, durationS: dur,
                                 distanceKm: s.distanceKmValue, fixShare: fix)
        }
    }

    /// Opens «Gráficas» with the tramo selected and zoomed. `t0`/`t1` are engine times (timeline = engine − offset).
    func openInCharts(engineT0: Double, engineT1: Double) {
        guard let s = selected, engineT0.isFinite, engineT1.isFinite, engineT1 > engineT0 else { return }
        let off: Double = s.engineOffsetS
        let a: Double = engineT0 - off, b: Double = engineT1 - off
        page = .charts
        rangeStart = a
        rangeEnd = b
        cursorTime = a
        let pad: Double = max(5, (b - a) * 0.25)
        charts?.setViewport(a - pad, b + pad)
    }

    /// «Distancia de trabajo» (trainer 14/11/2026: the selection must match the figure): selects from the first to the last
    /// moment at or above the engine «trabajo rápido» speed, on the same filtered speed as «Gráficas». Falls back to the
    /// engine efforts window when there is no threshold or no sample above it.
    func openFastWork(thresholdMs: Double?, fallbackT0: Double?, fallbackT1: Double?) {
        guard let s = selected else { return }
        let tl: SessionTimeline = s.timeline
        let v: [Double] = tl.speedFiltered
        if let thr = thresholdMs, thr > 0, v.count == tl.count, tl.count > 1 {
            var i0: Int = -1, i1: Int = -1
            for i in 0..<v.count where v[i].isFinite && v[i] >= thr {
                if i0 < 0 { i0 = i }
                i1 = i
            }
            if i0 >= 0, i1 > i0 {
                let a: Double = tl.t[i0], b: Double = tl.t[i1]
                page = .charts
                rangeStart = a
                rangeEnd = b
                cursorTime = a
                let pad: Double = max(5, (b - a) * 0.25)
                charts?.setViewport(a - pad, b + pad)
                return
            }
        }
        if let a = fallbackT0, let b = fallbackT1 { openInCharts(engineT0: a, engineT1: b) }
    }
}
