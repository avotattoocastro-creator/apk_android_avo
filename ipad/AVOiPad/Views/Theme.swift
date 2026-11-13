import SwiftUI

/// AVO corporate palette — 1:1 from app/src/main/kotlin/.../ui/theme/Theme.kt (AvoColors) and windows/.../AvoColors.xaml.
/// Every colour has a DARK value (the original palette) and a LIGHT value (trainer's request 13/11/2026); the one shown
/// follows the colour scheme chosen in «Configuración» (AvoAppearance), applied at the root with preferredColorScheme.
enum Avo {
    //                                  oscuro      claro
    static let bg = Color.avo(0x030406, 0xE6E8EC)
    static let surface = Color.avo(0x101014, 0xFFFFFF)
    static let surface2 = Color.avo(0x1A1B20, 0xDDE0E5)
    static let line = Color.avo(0x2A2B31, 0xC6C9D0)
    static let red = Color.avo(0xED122A, 0xD50F27)
    static let redDark = Color.avo(0xB71625, 0xB71625)
    static let redLight = Color.avo(0xFF495A, 0xC8102A)
    static let blue = Color.avo(0x3D9BFF, 0x1F6FD1)
    static let cyan = Color.avo(0x35D0E8, 0x0A879C)
    static let silver = Color.avo(0xC9CBD1, 0x45484F)
    static let text = Color.avo(0xF2F2F4, 0x15161A)
    static let textDim = Color.avo(0x9C9DA4, 0x666972)
    static let ok = Color.avo(0x52DD40, 0x2A8F1E)
    static let warn = Color.avo(0xFFC42C, 0xA86F00)
    static let bad = Color.avo(0xFF3945, 0xD02331)
    static let unknown = Color.avo(0x93949B, 0x7A7C84)
    static let redSoft = Color.avo(0xED122A, 0xED122A, darkAlpha: 0.2, lightAlpha: 0.12)

    static let cardBrush = LinearGradient(colors: [Color.avo(0x15161B, 0xFFFFFF), Color.avo(0x0D0D11, 0xF4F5F7)], startPoint: .top, endPoint: .bottom)
    static let headerBrush = LinearGradient(colors: [Color.avo(0x0A0B0E, 0xDDE0E5), Color.avo(0x15161B, 0xEDEFF2), Color.avo(0x0A0B0E, 0xDDE0E5)],
                                            startPoint: .leading, endPoint: .trailing)
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

/// Colour scheme of the app, chosen in «Configuración» (stored in UserDefaults «avo.appearance»). There is no «as the
/// system» option: Info.plist fixes UIUserInterfaceStyle = Dark, so only an explicit scheme overrides it.
enum AvoAppearance: String, CaseIterable, Identifiable {
    case dark, light
    static let key: String = "avo.appearance"
    var id: String { rawValue }
    var title: String { self == .dark ? "Oscuro" : "Claro" }
    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
}

/// Applies the chosen colour scheme (root and sheets, which do not always inherit it).
struct AvoColorScheme: ViewModifier {
    @AppStorage(AvoAppearance.key) private var raw: String = AvoAppearance.dark.rawValue
    func body(content: Content) -> some View {
        content.preferredColorScheme((AvoAppearance(rawValue: raw) ?? .dark).colorScheme)
    }
}

extension View {
    func avoColorScheme() -> some View { modifier(AvoColorScheme()) }
}

extension Color {
    /// Dynamic colour: `dark` in dark mode, `light` in light mode.
    static func avo(_ dark: UInt32, _ light: UInt32, darkAlpha: Double = 1, lightAlpha: Double = 1) -> Color {
        Color(UIColor { (t: UITraitCollection) -> UIColor in
            t.userInterfaceStyle == .light ? UIColor(Color(hex: light, alpha: lightAlpha)) : UIColor(Color(hex: dark, alpha: darkAlpha))
        })
    }

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
/// Figure box of the whole app in the «Datos clave» style (trainer 14/11/2026: «todos los recuadros de la app de este
/// estilo»): no box; thin icon, the figure and its unit centred, the name in small capitals and hairlines around.
struct AvoMetric: View {
    var label: String
    var value: String
    var unit: String = ""
    var caption: String? = nil
    var accent: Color = Avo.text
    var icon: String? = nil

    var body: some View {
        VStack(spacing: 5) {
            if let ic = icon ?? AvoMetric.autoIcon(label) {
                Image(systemName: ic).font(.system(size: 22, weight: .ultraLight)).foregroundStyle(Avo.silver).frame(height: 26)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: 24, weight: .regular)).foregroundStyle(accent)
                    .lineLimit(1).minimumScaleFactor(0.5)
                if !unit.isEmpty { Text(unit).font(.caption).foregroundStyle(Avo.textDim) }
            }
            Text(label.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.5).foregroundStyle(Avo.silver)
                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
            if let caption = caption {
                Text(caption).font(.caption2).foregroundStyle(Avo.textDim).multilineTextAlignment(.center).lineLimit(2)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 12)
        // all boxes the same size (trainer 14/11/2026: «todos de la misma medida»)
        .frame(maxWidth: .infinity, minHeight: 138)
        .overlay(alignment: .bottom) { Rectangle().fill(Avo.line).frame(height: 1).padding(.horizontal, 10) }
        .overlay(alignment: .trailing) { Rectangle().fill(Avo.line).frame(width: 1).padding(.vertical, 12) }
    }

    /// Icon from the name of the figure (same families as «Datos clave»).
    static func autoIcon(_ label: String) -> String? {
        let l: String = label.lowercased()
        if l.contains("pulso") || l.contains("lpm") || l.contains("fc ") { return "waveform.path.ecg" }
        if l.contains("velocidad") || l.contains("v. m") || l.contains("vel.") || l.contains("mejor") { return "figure.equestrian.sports" }
        if l.contains("distancia") || l.contains("km") { return "point.topleft.down.to.point.bottomright.curvepath" }
        if l.contains("tiempo") || l.contains("duración") || l.contains("media") && l.contains("min") { return "clock" }
        if l.contains("tranco") || l.contains("zancada") { return "ruler" }
        if l.contains("frecuencia") { return "metronome" }
        if l.contains("entrenamiento") || l.contains("sesion") || l.contains("sesión") { return "list.bullet.rectangle" }
        if l.contains("último") || l.contains("fecha") || l.contains("semana") { return "calendar" }
        if l.contains("rtk") || l.contains("fix") || l.contains("gnss") { return "location.circle" }
        if l.contains("aceleración") || l.contains("carga") { return "bolt" }
        return nil
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
