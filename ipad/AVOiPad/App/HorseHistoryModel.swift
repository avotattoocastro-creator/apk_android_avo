import SwiftUI
import Observation

/// Bar of the load chart: one component (gait or high speed) of the external load of one day or week.
struct HorseLoadBar: Identifiable {
    var id: String
    var date: Date
    var part: String
    var value: Double
}

/// Point of a line of the history charts (acute / chronic load, ACWR, sRPE).
struct HorseLinePoint: Identifiable {
    var id: String
    var date: Date
    var series: String
    var value: Double
}

/// Row of the baseline table: last session against its own baseline.
struct HorseBaselineRow: Identifiable {
    var id: String
    var gait: String
    var label: String
    var value: String
    var median: String
    var mad: String
    var z: String
    /// NORMAL | VIGILAR | REVISAR | INFORMATIVO | OTRO_SENTIDO | SIN_LINEA_BASE
    var flag: String
    var flagText: String
}

/// Row of the list of sessions of the history.
struct HorseSessionRow: Identifiable {
    var id: String
    var date: String
    var walkMin: String
    var trotMin: String
    var canterMin: String
    var distance: String
    var highSpeed: String
    var load: String
    var rpe: String
    var trainerState: String
    var level: String
    var loaded: Bool
    var demo: Bool
}

/// «Historia del caballo»: AVO Training Analytics over every session of one horse (App/AppModel+Training.swift).
/// Opened from the horse card (Cuadra) and from the horse name in Análisis; presented by RootView as a full-screen cover.
@Observable
final class HorseHistoryModel {
    @ObservationIgnored unowned let app: AppModel
    @ObservationIgnored private var task: Task<Void, Never>? = nil

    var visible: Bool = false
    var horseKey: String = ""
    var horseName: String = ""
    var isDemoHorse: Bool = false
    var loading: Bool = false
    var progressText: String = ""
    var errorText: String? = nil
    var result: TrainingAnalysisResult? = nil
    var missing: Int = 0
    var byWeek: Bool = false

    init(app: AppModel) {
        self.app = app
    }

    // ---------------------------------------------------------------- contract
    func sessionChanged() {}
    func pageShown() {}

    // ---------------------------------------------------------------- actions
    func open(horseKey key: String, name: String? = nil) {
        let k: String = key.trimmed
        if k.isEmpty { return }
        if k != horseKey { result = nil }
        horseKey = k
        horseName = name ?? app.horseName(k)
        isDemoHorse = app.isDemoHorse(k)
        visible = true
        reload()
    }

    func open(for item: SessionItem) {
        open(horseKey: app.horseKey(item), name: item.horse)
    }

    func close() {
        task?.cancel()
        task = nil
        loading = false
        visible = false
    }

    func reload() {
        task?.cancel()
        task = Task { @MainActor [weak self] in
            await self?.load()
        }
    }

    @MainActor
    private func load() async {
        let key: String = horseKey
        loading = true
        errorText = nil
        progressText = "Preparando los resúmenes de las sesiones…"
        do {
            let r: (result: TrainingAnalysisResult, missing: Int) = try await app.analyseHorseHistory(key, reference: nil) { [weak self] (done: Int, total: Int) in
                self?.progressText = "Preparando resúmenes de sesión \(done)/\(total)…"
            }
            if Task.isCancelled || key != horseKey { return }
            result = r.result
            missing = r.missing
            loading = false
            progressText = ""
        } catch is CancellationError {
            return
        } catch {
            if key != horseKey { return }
            errorText = error.localizedDescription
            loading = false
            progressText = ""
            app.log.warn("historia", error.localizedDescription, error)
        }
    }

    /// Opens one session of the history in «Análisis».
    func openSession(_ id: String) {
        guard let s = app.sessions.first(where: { $0.id == id }) else { return }
        close()
        app.select(s)
        app.page = .analysis
    }

    // ---------------------------------------------------------------- derived data for the view
    static let utcCalendar: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "UTC") ?? TimeZone.current
        return c
    }()

    private func bucket(_ d: Date) -> Date {
        if !byWeek { return d }
        return HorseHistoryModel.utcCalendar.dateInterval(of: .weekOfYear, for: d)?.start ?? d
    }

    static let loadParts: [String] = ["Paso", "Trote", "Galope", "Alta velocidad"]

    /// External load per day (or ISO week) stacked by component.
    var loadBars: [HorseLoadBar] {
        guard let r = result else { return [] }
        var sums: [Date: [String: Double]] = [:]
        for s in r.sesiones {
            guard let d = s.date, let sum = s.resumen else { continue }
            let b: Date = bucket(d)
            for p in r.loadParts(sum) where p.value > 0 {
                sums[b, default: [:]][p.name, default: 0] += p.value
            }
        }
        var out: [HorseLoadBar] = []
        for d in sums.keys.sorted() {
            for name in HorseHistoryModel.loadParts {
                if let v = sums[d]?[name], v > 0 {
                    out.append(HorseLoadBar(id: "\(d.timeIntervalSince1970)|\(name)", date: d, part: name, value: v))
                }
            }
        }
        return out
    }

    /// Acute (7 d) and chronic (28 d / 4) load at each session: weekly units; per-day mode shows them divided by 7.
    var loadLines: [HorseLinePoint] {
        guard let r = result else { return [] }
        let k: Double = byWeek ? 1 : 1.0 / 7.0
        var out: [HorseLinePoint] = []
        for s in r.sesiones {
            guard let d = s.date else { continue }
            if let a = s.carga.aguda { out.append(HorseLinePoint(id: s.id + "|a", date: d, series: "Aguda 7 d", value: a * k)) }
            if let c = s.carga.cronicaSemanal { out.append(HorseLinePoint(id: s.id + "|c", date: d, series: "Crónica 28 d", value: c * k)) }
        }
        return out
    }

    var acwrPoints: [HorseLinePoint] {
        guard let r = result else { return [] }
        var out: [HorseLinePoint] = []
        for s in r.sesiones {
            guard let d = s.date, let a = s.carga.acwr else { continue }
            out.append(HorseLinePoint(id: s.id + "|acwr", date: d, series: "ACWR", value: a))
            if let b = s.carga.acwrSrpe { out.append(HorseLinePoint(id: s.id + "|acwrs", date: d, series: "ACWR sRPE", value: b)) }
        }
        return out
    }

    /// sRPE load (RPE × minutes) per day or week, only sessions rated by the trainer.
    var srpeBars: [HorseLinePoint] {
        guard let r = result else { return [] }
        var sums: [Date: Double] = [:]
        for s in r.sesiones {
            guard let d = s.date, let v = s.carga.srpe else { continue }
            sums[bucket(d), default: 0] += v
        }
        return sums.keys.sorted().map { HorseLinePoint(id: "\($0.timeIntervalSince1970)|srpe", date: $0, series: "sRPE", value: sums[$0] ?? 0) }
    }

    var dateDomain: ClosedRange<Date>? {
        guard let r = result else { return nil }
        let dates: [Date] = r.sesiones.compactMap { $0.date }
        guard let a = dates.min(), let b = dates.max() else { return nil }
        let pad: TimeInterval = byWeek ? 4 * 86_400 : 86_400
        return a.addingTimeInterval(-pad)...b.addingTimeInterval(pad)
    }

    /// Last session against its own baseline (deviations computed by the engine with the previous sessions).
    var baselineRows: [HorseBaselineRow] {
        guard let r = result, let last = r.lastSession else { return [] }
        var out: [HorseBaselineRow] = []
        let minN: Int = Int(r.param("min_sesiones_linea_base", 4))
        for g in TrainingAnalytics.gaits {
            let gs: TrainingGaitSummary? = last.resumen?.gait(g)
            for key in TrainingAnalytics.metricKeys {
                let metric: String = g + "." + key
                let value: Double? = gs?.value(key)
                if value == nil && last.deviation(metric) == nil { continue }
                let label: String = TrainingAnalytics.gaitLabel(g) + " · " + TrainingAnalytics.metricLabel(key)
                if let d = last.deviation(metric) {
                    let flag: String
                    let text: String
                    if d.isInformative {
                        flag = "INFORMATIVO"
                        text = d.nivel == "NORMAL" ? "Normal (informativo)" : "Desvío \(d.direccion == "MAYOR" ? "por encima" : "por debajo") · informativo"
                    } else if d.flag != "NORMAL" {
                        flag = d.flag
                        text = d.flag == "REVISAR" ? "REVISAR" : "VIGILAR"
                    } else if d.nivel != "NORMAL" {
                        flag = "OTRO_SENTIDO"
                        text = "Desvío en sentido favorable (no sube el nivel)"
                    } else {
                        flag = "NORMAL"
                        text = "Normal"
                    }
                    out.append(HorseBaselineRow(id: metric, gait: g, label: label, value: TrainingAnalytics.format(key, d.valor),
                                                median: TrainingAnalytics.format(key, d.lineaBase),
                                                mad: TrainingAnalytics.format(key, d.mad),
                                                z: d.z.map { AvoFormat.f($0, 1) } ?? "—", flag: flag, flagText: text))
                } else {
                    out.append(HorseBaselineRow(id: metric, gait: g, label: label, value: TrainingAnalytics.format(key, value),
                                                median: "—", mad: "—", z: "—", flag: "SIN_LINEA_BASE",
                                                flagText: "Sin línea base (menos de \(minN) sesiones previas en 60 días)"))
                }
            }
        }
        return out
    }

    /// Trends of the last 8 weeks: those with data first.
    var trends: [TrainingTrend] {
        guard let r = result else { return [] }
        let order: [String] = ["carga_externa", "distancia_m"]
        return r.tendencias.sorted { (a: TrainingTrend, b: TrainingTrend) -> Bool in
            if a.hasData != b.hasData { return a.hasData }
            let ia: Int = order.firstIndex(of: a.metrica) ?? 99
            let ib: Int = order.firstIndex(of: b.metrica) ?? 99
            if ia != ib { return ia < ib }
            return a.metrica < b.metrica
        }
    }

    /// Sessions of the history, newest first.
    var sessionRows: [HorseSessionRow] {
        guard let r = result else { return [] }
        let loaded: Set<String> = Set(app.sessions.map { $0.id })
        var out: [HorseSessionRow] = []
        for s in r.sesiones.reversed() {
            let sum: TrainingSessionSummary? = s.resumen
            let item: SessionItem? = app.sessions.first { $0.id == s.id }
            func mins(_ g: TrainingGaitSummary?) -> String {
                guard let v = g?.duracionS, v > 0 else { return "—" }
                return AvoFormat.f(v / 60, 0) + " min"
            }
            let date: String = item.map { $0.dateTimeText } ?? (s.date.map { AvoTime.text($0, "dd/MM/yyyy") } ?? s.fecha)
            out.append(HorseSessionRow(id: s.id, date: date, walkMin: mins(sum?.paso), trotMin: mins(sum?.trote), canterMin: mins(sum?.galope),
                                       distance: sum?.distanciaM.map { AvoFormat.f($0 / 1000, 2) + " km" } ?? "—",
                                       highSpeed: sum?.distanciaAltaVelocidadM.map { AvoFormat.f($0, 0) + " m" } ?? "—",
                                       load: s.carga.externa.map { AvoFormat.f($0, 0) } ?? "—",
                                       rpe: sum?.rpe.map { AvoFormat.f($0, 0) } ?? "—",
                                       trainerState: sum?.estado ?? "—",
                                       level: s.nivel, loaded: loaded.contains(s.id), demo: item?.isSynthetic ?? false))
        }
        return out
    }

    static func levelColor(_ l: String) -> Color {
        switch l {
        case "REVISAR": return Avo.bad
        case "VIGILAR": return Avo.warn
        case "NORMAL": return Avo.ok
        default: return Avo.unknown
        }
    }
}
