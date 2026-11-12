import SwiftUI

/// AVO corporate palette — 1:1 from app/src/main/kotlin/.../ui/theme/Theme.kt (AvoColors) and windows/.../AvoColors.xaml.
enum Avo {
    static let bg = Color(hex: 0x030406)
    static let surface = Color(hex: 0x101014)
    static let surface2 = Color(hex: 0x1A1B20)
    static let line = Color(hex: 0x2A2B31)
    static let red = Color(hex: 0xED122A)
    static let redDark = Color(hex: 0xB71625)
    static let redLight = Color(hex: 0xFF495A)
    static let blue = Color(hex: 0x3D9BFF)
    static let cyan = Color(hex: 0x35D0E8)
    static let silver = Color(hex: 0xC9CBD1)
    static let text = Color(hex: 0xF2F2F4)
    static let textDim = Color(hex: 0x9C9DA4)
    static let ok = Color(hex: 0x52DD40)
    static let warn = Color(hex: 0xFFC42C)
    static let bad = Color(hex: 0xFF3945)
    static let unknown = Color(hex: 0x93949B)
    static let redSoft = Color(hex: 0xED122A, alpha: 0.2)

    static let cardBrush = LinearGradient(colors: [Color(hex: 0x15161B), Color(hex: 0x0D0D11)], startPoint: .top, endPoint: .bottom)
    static let headerBrush = LinearGradient(colors: [Color(hex: 0x0A0B0E), Color(hex: 0x15161B), Color(hex: 0x0A0B0E)], startPoint: .leading, endPoint: .trailing)
    static let speedScale: [Color] = [Color(hex: 0x2F6BFF), Color(hex: 0x35D0E8), Color(hex: 0xFFC42C), Color(hex: 0xED122A)]
    static let accelScale: [Color] = [Color(hex: 0x3D9BFF), Color(hex: 0x93949B), Color(hex: 0xED122A)]

    /// Colour along a multi-stop scale, t in 0…1.
    static func scale(_ stops: [Color], _ t: Double) -> Color {
        guard stops.count > 1, t.isFinite else { return stops.first ?? .gray }
        let x = min(max(t, 0), 1) * Double(stops.count - 1)
        let i = min(Int(x), stops.count - 2)
        let f = x - Double(i)
        let a = UIColor(stops[i]), b = UIColor(stops[i + 1])
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let k = CGFloat(f)
        return Color(red: Double(r1 + (r2 - r1) * k), green: Double(g1 + (g2 - g1) * k), blue: Double(b1 + (b2 - b1) * k))
    }

    /// Colour of a GNSS solution (same as Windows/Android).
    static func solution(_ s: GnssSolution) -> Color {
        switch s {
        case .rtkFix: return ok
        case .rtkFloat: return warn
        case .dgnss: return cyan
        case .autonomous: return blue
        case .none: return bad
        }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

/// Visual state of an indicator (Windows AvoState).
enum AvoState { case ok, warning, error, unknown, info
    var color: Color {
        switch self {
        case .ok: return Avo.ok
        case .warning: return Avo.warn
        case .error: return Avo.bad
        case .unknown: return Avo.unknown
        case .info: return Avo.cyan
        }
    }
}

// MARK: - Reusable components (Windows Themes/AvoComponents.xaml + Controls/AvoComponents.cs)

/// Card with the Android gradient, hairline border and 10 pt corners.
struct AvoCard<Content: View>: View {
    var title: String? = nil
    var subtitle: String? = nil
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = title {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.uppercased()).font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(Avo.silver)
                    if let subtitle = subtitle { Text(subtitle).font(.caption2).foregroundStyle(Avo.textDim) }
                }
            }
            content()
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Avo.cardBrush, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Avo.line, lineWidth: 1))
    }
}

/// Metric tile: label, big value, unit and optional caption.
struct AvoMetric: View {
    var label: String
    var value: String
    var unit: String = ""
    var caption: String? = nil
    var accent: Color = Avo.text
    var icon: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let icon = icon { Image(systemName: icon).font(.caption).foregroundStyle(Avo.red) }
                Text(label.uppercased()).font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 26, weight: .semibold, design: .rounded)).foregroundStyle(accent)
                    .lineLimit(1).minimumScaleFactor(0.5)
                if !unit.isEmpty { Text(unit).font(.footnote).foregroundStyle(Avo.textDim) }
            }
            if let caption = caption { Text(caption).font(.caption2).foregroundStyle(Avo.textDim).lineLimit(2) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Avo.cardBrush, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Avo.line, lineWidth: 1))
    }
}

/// Small coloured state pill (FIX / FLOAT / DEMO …).
struct AvoPill: View {
    var text: String
    var color: Color = Avo.cyan
    var body: some View {
        Text(text).font(.caption2.weight(.bold)).padding(.horizontal, 7).padding(.vertical, 3)
            .foregroundStyle(color).background(color.opacity(0.14), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.45), lineWidth: 1))
    }
}

struct AvoPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.callout.weight(.semibold)).padding(.horizontal, 16).padding(.vertical, 9)
            .foregroundStyle(.white)
            .background(configuration.isPressed ? Avo.redDark : Avo.red, in: RoundedRectangle(cornerRadius: 7))
    }
}

struct AvoSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.callout).padding(.horizontal, 14).padding(.vertical, 8)
            .foregroundStyle(Avo.text)
            .background(configuration.isPressed ? Avo.line : Avo.surface2, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Avo.line, lineWidth: 1))
    }
}

extension ButtonStyle where Self == AvoPrimaryButtonStyle { static var avoPrimary: AvoPrimaryButtonStyle { AvoPrimaryButtonStyle() } }
extension ButtonStyle where Self == AvoSecondaryButtonStyle { static var avoSecondary: AvoSecondaryButtonStyle { AvoSecondaryButtonStyle() } }

/// Section title used at the top of every page.
struct AvoPageTitle: View {
    var title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title2.weight(.semibold)).foregroundStyle(Avo.text)
            if let subtitle = subtitle { Text(subtitle).font(.footnote).foregroundStyle(Avo.textDim) }
        }
    }
}

/// "Sin datos" placeholder, never invented values.
struct AvoNoData: View {
    var text: String = "Sin datos"
    var body: some View {
        Text(text).font(.footnote).foregroundStyle(Avo.textDim).frame(maxWidth: .infinity, minHeight: 80)
    }
}
