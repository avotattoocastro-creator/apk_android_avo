import Foundation

/// Solution type of one GNSS epoch, ordered from worst to best (same states as the Android RtkState).
enum GnssSolution: Int, CaseIterable, Comparable, Codable {
    case none = 0
    case autonomous = 1
    case dgnss = 2
    case rtkFloat = 3
    case rtkFix = 4

    static func < (a: GnssSolution, b: GnssSolution) -> Bool { a.rawValue < b.rawValue }
}

enum GnssQuality {
    /// UBX-NAV-PVT rules: no solution when gnssFixOK is clear, the position is flagged invalid (flags3.invalidLlh) or the
    /// fix type is not 2D/3D/GNSS+DR. Otherwise carrier solution 2 = RTK FIX, 1 = RTK FLOAT, diffSoln = DGNSS, else autonomous.
    static func classify(gnssFixOk: Bool, fixType: Int, diffSoln: Bool, carrierSolution: Int, invalidLlh: Bool) -> GnssSolution {
        if !gnssFixOk || invalidLlh || fixType < 2 || fixType > 4 { return .none }
        switch carrierSolution {
        case 2: return .rtkFix
        case 1: return .rtkFloat
        default: return diffSoln ? .dgnss : .autonomous
        }
    }

    static func name(_ s: GnssSolution) -> String {
        switch s {
        case .rtkFix: return "RTK FIX"
        case .rtkFloat: return "RTK FLOAT"
        case .dgnss: return "DGNSS"
        case .autonomous: return "Autónomo"
        case .none: return "Sin solución válida"
        }
    }

    /// Percentage of received epochs per solution type.
    static func distribution(_ epochs: [GnssEpoch]) -> [GnssSolution: Double] {
        var d: [GnssSolution: Double] = [:]
        for s in GnssSolution.allCases { d[s] = 0 }
        if epochs.isEmpty { return d }
        for e in epochs { d[e.solution, default: 0] += 1 }
        for k in GnssSolution.allCases { d[k] = 100.0 * (d[k] ?? 0) / Double(epochs.count) }
        return d
    }
}

/// Interval of the session without a usable GNSS solution (no epochs, or epochs without a valid fix).
struct SignalLoss: Equatable {
    var t0: Double
    var t1: Double
    var reason: String
    var durationS: Double { t1 - t0 }
}
