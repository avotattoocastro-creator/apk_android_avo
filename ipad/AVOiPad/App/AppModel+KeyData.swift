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
}
