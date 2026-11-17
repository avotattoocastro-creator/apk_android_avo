import Foundation

enum AlignmentMode: Equatable {
    case relativeTime
    case distance
}

/// Resamples several sessions on a common axis (relative time in s or cumulative distance in m) so they can be drawn and
/// compared point by point. Linear interpolation is only applied between two continuous samples; across a GNSS gap the
/// value is NaN. Different sampling rates are therefore handled without inventing data. Spatial correspondence (same
/// route) is decided by the engine comparison (DTW, lateral separation), not by start points looking similar.
enum SeriesAligner {
    struct Aligned {
        var axis: [Double]
        var values: [[Double]]
    }

    static func align(_ sessions: [SessionTimeline], _ selector: (SessionTimeline) -> [Double], _ mode: AlignmentMode, _ step: Double) -> Aligned {
        if sessions.isEmpty || step <= 0 { return Aligned(axis: [], values: []) }
        var end: Double = -Double.infinity
        for s in sessions {
            let e: Double = s.count == 0 ? 0 : (mode == .relativeTime ? s.t[s.count - 1] - s.t[0] : s.distance[s.count - 1])
            if e > end || end == -Double.infinity { end = e }
        }
        let nD: Double = (end / step).rounded(.down) + 1
        var n: Int = 0
        if nD.isFinite { n = Int(min(max(nD, 0), 2_000_000)) }
        var axis: [Double] = [Double](repeating: 0, count: n)
        for i in 0..<n { axis[i] = Double(i) * step }
        var values: [[Double]] = []
        values.reserveCapacity(sessions.count)
        for s in sessions {
            let y: [Double] = selector(s)
            var outv: [Double] = [Double](repeating: .nan, count: n)
            if s.count >= 2 && y.count == s.count {
                let x: [Double] = mode == .relativeTime ? s.t.map { $0 - s.t[0] } : s.distance
                var j: Int = 0
                var i: Int = 0
                while i < n {
                    let a: Double = axis[i]
                    while j + 1 < s.count && x[j + 1] < a { j += 1 }
                    if j + 1 >= s.count {
                        if abs(x[j] - a) < 1e-9 { outv[i] = y[j] }
                        break
                    }
                    if a < x[j] { i += 1; continue }
                    if s.breakBefore[j + 1] || s.jumpBefore[j + 1] { i += 1; continue }
                    let dx: Double = x[j + 1] - x[j]
                    if dx <= 0 { outv[i] = y[j]; i += 1; continue }
                    let u: Double = (a - x[j]) / dx
                    outv[i] = y[j] + (y[j + 1] - y[j]) * u
                    i += 1
                }
            }
            values.append(outv)
        }
        return Aligned(axis: axis, values: values)
    }

    /// Summary row of one session for the comparison table.
    struct SessionSummary: Equatable {
        var label: String
        var distanceKm: Double
        var durationS: Double
        var meanSpeedKmh: Double?
        var maxSpeedKmh: Double?
        var maxAccel: Double?
        var maxDecel: Double?
        var fixPercent: Double
        var cadence: Double?
    }

    static func summarize(_ label: String, _ tl: SessionTimeline, _ engine: EquineAnalysis?, _ engineOffsetS: Double = 0) -> SessionSummary {
        if tl.count < 2 {
            return SessionSummary(label: label, distanceKm: 0, durationS: 0, meanSpeedKmh: nil, maxSpeedKmh: nil, maxAccel: nil,
                                  maxDecel: nil, fixPercent: 0, cadence: nil)
        }
        let all = SegmentDefinition(name: label, t0: tl.t[0], t1: tl.t[tl.count - 1])
        let m: SegmentMetrics = SegmentAnalyzer.compute(tl, all, engine: engine, engineOffsetS: engineOffsetS)
        var cad: Double? = nil
        if let e = engine { cad = AnalysisForeignAPI.metric(e, "cadencia_media_imu0") }
        return SessionSummary(label: label, distanceKm: m.distanceM / 1000, durationS: m.durationS, meanSpeedKmh: m.meanSpeedKmh,
                              maxSpeedKmh: m.maxSpeedKmh, maxAccel: m.maxAccel, maxDecel: m.maxDecel, fixPercent: m.fixFraction * 100, cadence: cad)
    }
}

/// The only calls this module makes into types ported by other files (EquineEngine.swift, TrainingEnvironment.swift).
/// Kept together so a different argument-label choice there needs a fix in one place only.
enum AnalysisForeignAPI {
    static func metric(_ e: EquineAnalysis, _ name: String) -> Double? { e.metric(name) }
    static func tideHeight(_ tp: TidePrediction, _ utc: Date) -> Double? { tp.heightAt(utc) }
    static func tideTrend(_ tp: TidePrediction, _ utc: Date) -> String? { tp.trendAt(utc) }
    static func tideCoefficient(_ tp: TidePrediction, _ utc: Date) -> Double? { tp.coefficientAt(utc) }
    static func weatherAt(_ wm: WeatherModel, _ utc: Date) -> WeatherHour? { wm.at(utc) }
}
