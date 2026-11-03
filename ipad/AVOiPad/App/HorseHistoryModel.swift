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

/// Row of the AVO Track Work table of the history: last session, baseline and 8-week trend of one metric.
struct HorseTrackWorkRow: Identifiable {
    var id: String
    var label: String
    var last: String
    var median: String
    var n: Int
    /// NORMAL | VIGILAR | REVISAR | INFORMATIVO | OTRO_SENTIDO | SIN_LINEA_BASE
    var flag: String
    var flagText: String
    var trendText: String
    var trendArrow: String
    var trendHasData: Bool
}

/// Session of the history with atypical impacts of the girth (they raise the level to VIGILAR).
struct HorseImpactRow: Identifiable {
    var id: String
    var date: String
    var impacts: Int
    var lateral: Int
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
        return r.tendencias.filter { !TrainingAnalytics.isTrackWorkMetric($0.metrica) }.sorted { (a: TrainingTrend, b: TrainingTrend) -> Bool in
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

    // ---------------------------------------------------------------- AVO Track Work in the history
    /// Order of the Track Work metrics in the table (the engine names).
    static let trackWorkMetrics: [String] = [
        "RECORRIDO.mejor_pasada_s", "RECORRIDO.v_media_mejor", "TRABAJO.indice_caida_pct", "TRABAJO.recuperacion_hasta_paso_s",
        "CINCHA.vedba_galope_g", "carga_vedba", "TRABAJO.v_max", "TRABAJO.mejor_200m_s", "TRABAJO.caida_entre_series_pct",
        "TRABAJO.calentamiento_s", "TRABAJO.f_v1_hz", "TRABAJO.l_v1_m", "TRABAJO.f_v2_hz", "TRABAJO.l_v2_m",
        "TRABAJO.f_en_v_max_hz", "TRABAJO.l_en_v_max_m", "TRABAJO.desplazamiento_vertical_m", "TRABAJO.mano_de_fuera_curva_pct",
    ]

    /// Series of the small charts of Track Work (name, metric key for the format).
    static let trackWorkSeries: [(name: String, key: String)] = [
        ("Mejor pasada", "mejor_pasada_s"), ("Velocidad media de la mejor pasada", "v_media_mejor"),
        ("Índice de caída", "indice_caida_pct"), ("Recuperación hasta el paso", "recuperacion_hasta_paso_s"),
        ("VeDBA en galope", "vedba_galope_g"),
    ]

    /// At least one session of the history carries the AVO Track Work block.
    var hasTrackWork: Bool {
        guard let r = result else { return false }
        return r.sesiones.contains { $0.resumen?.trabajoPista != nil }
    }

    /// Value of one Track Work series in a session summary (display units applied by the view).
    static func trackWorkValue(_ t: TrainingTrackWorkSummary, _ key: String) -> Double? {
        switch key {
        case "mejor_pasada_s": return t.mejorPasadaS
        case "v_media_mejor": return t.vMediaMejor.map { $0 * 3.6 }
        case "indice_caida_pct": return t.indiceCaidaPct
        case "recuperacion_hasta_paso_s": return t.recuperacionMediaS
        case "vedba_galope_g": return t.vedbaGalopeG
        default: return nil
        }
    }

    /// Points of one Track Work series (per session).
    func trackWorkPoints(_ key: String) -> [HorseLinePoint] {
        guard let r = result else { return [] }
        var out: [HorseLinePoint] = []
        for s in r.sesiones {
            guard let d = s.date, let t = s.resumen?.trabajoPista, let v = HorseHistoryModel.trackWorkValue(t, key), v.isFinite else { continue }
            out.append(HorseLinePoint(id: s.id + "|" + key, date: d, series: key, value: v))
        }
        return out
    }

    /// VeDBA load of the girth (g·min) per day or week.
    var vedbaLoadBars: [HorseLinePoint] {
        guard let r = result else { return [] }
        var sums: [Date: Double] = [:]
        for s in r.sesiones {
            guard let d = s.date, let v = s.resumen?.trabajoPista?.cargaVedbaGmin, v.isFinite else { continue }
            sums[bucket(d), default: 0] += v
        }
        return sums.keys.sorted().map { HorseLinePoint(id: "\($0.timeIntervalSince1970)|vedba", date: $0, series: "Carga VeDBA", value: sums[$0] ?? 0) }
    }

    /// ACWR of the VeDBA load at each session.
    var acwrVedbaPoints: [HorseLinePoint] {
        guard let r = result else { return [] }
        var out: [HorseLinePoint] = []
        for s in r.sesiones {
            guard let d = s.date, let a = s.carga.acwrVedba, a.isFinite else { continue }
            out.append(HorseLinePoint(id: s.id + "|acwrv", date: d, series: "ACWR VeDBA", value: a))
        }
        return out
    }

    /// Last session, baseline and trend of every Track Work metric the engine reported.
    var trackWorkRows: [HorseTrackWorkRow] {
        guard let r = result else { return [] }
        let last: TrainingSessionResult? = r.lastSession
        let minN: Int = Int(r.param("min_sesiones_linea_base", 4))
        var out: [HorseTrackWorkRow] = []
        for m in HorseHistoryModel.trackWorkMetrics {
            let key: String = TrainingAnalytics.split(m).key
            let b: TrainingBaseline? = r.baseline(m)
            let t: TrainingTrend? = r.trend(m)
            let d: TrainingDeviation? = last?.deviation(m)
            var lastValue: Double? = d?.valor
            if lastValue == nil && m == "carga_vedba" { lastValue = last?.resumen?.trabajoPista?.cargaVedbaGmin }
            if b == nil && t == nil && d == nil && lastValue == nil { continue }
            var flag: String = "SIN_LINEA_BASE"
            var text: String = "Sin línea base (menos de \(minN) sesiones previas en 60 días)"
            if let dd = d {
                if dd.isInformative {
                    flag = "INFORMATIVO"
                    text = dd.nivel == "NORMAL" ? "Normal (informativo)" : "Desvío \(dd.direccion == "MAYOR" ? "por encima" : "por debajo") · informativo"
                } else if dd.flag != "NORMAL" {
                    flag = dd.flag
                    text = dd.flag
                } else if dd.nivel != "NORMAL" {
                    flag = "OTRO_SENTIDO"
                    text = "Desvío en sentido favorable"
                } else {
                    flag = "NORMAL"
                    text = "Normal"
                }
            } else if b?.estado == "DISPONIBLE" {
                flag = "INFORMATIVO"
                text = "Sin valor en la última sesión"
            }
            let trendText: String
            if let tt = t {
                trendText = tt.hasData ? "\(tt.direccion) · \(TrainingAnalytics.formatSlope(key, tt.pendienteSemana))" : "Sin datos (\(tt.n) sesiones)"
            } else {
                trendText = "—"
            }
            out.append(HorseTrackWorkRow(id: m, label: TrainingAnalytics.fullLabel(m), last: TrainingAnalytics.format(key, lastValue),
                                         median: TrainingAnalytics.format(key, b?.mediana), n: b?.n ?? 0, flag: flag, flagText: text,
                                         trendText: trendText, trendArrow: t?.arrow ?? "minus", trendHasData: t?.hasData ?? false))
        }
        return out
    }

    /// Sessions with atypical impacts or abrupt lateral movements of the girth, newest first.
    var impactRows: [HorseImpactRow] {
        guard let r = result else { return [] }
        var out: [HorseImpactRow] = []
        for s in r.sesiones.reversed() {
            guard let t = s.resumen?.trabajoPista, t.impactosAtipicos > 0 || t.lateralesBruscos > 0 else { continue }
            let date: String = s.date.map { AvoTime.text($0, "dd/MM/yyyy") } ?? s.fecha
            out.append(HorseImpactRow(id: s.id, date: date, impacts: t.impactosAtipicos, lateral: t.lateralesBruscos))
        }
        return out
    }

    /// Reasons of the state that come from the girth / Track Work (atypical impacts, lateral jolts, VeDBA, short warm-up).
    var trackWorkReasons: [String] {
        guard let r = result else { return [] }
        return r.motivos.filter { (m: String) -> Bool in
            let l: String = m.lowercased()
            return l.contains("impacto") || l.contains("lateral") || l.contains("vedba") || l.contains("calentamiento corto")
                || l.contains("mano de fuera") || l.contains("zancada")
        }
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
