import SwiftUI

/// Start screen = port of windows/AVO.Windows/Views/StartView.xaml + HeroArt.xaml: full-bleed hero photo with the AVO
/// lettering (in the photo's 2004×1098 coordinates, scaled like the Windows Viewbox UniformToFill, anchored top-left) and
/// the main actions in a translucent navy column on the right. The sidebar is hidden here (RootView shows a «Menú» button).
struct StartView: View {
    @Environment(AppModel.self) private var app

    private static let artW: CGFloat = 2004
    private static let artH: CGFloat = 1098

    var body: some View {
        GeometryReader { geo in
            let w: CGFloat = geo.size.width
            let h: CGFloat = geo.size.height
            let s: CGFloat = max(w / StartView.artW, h / StartView.artH)
            ZStack(alignment: .topLeading) {
                Color(hex: 0x0B1020)
                heroArt(scale: s)
                    .frame(width: StartView.artW * s, height: StartView.artH * s, alignment: .topLeading)
                    .frame(width: w, height: h, alignment: .topLeading)
                    .clipped()
                if h > w {
                    // portrait: the actions go in a band at the bottom so they never cover the title
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        actions
                            .frame(width: w, height: max(h * 0.34, 330))
                            .background(
                                LinearGradient(colors: [Color(hex: 0x202B3B, alpha: 0.70), Color(hex: 0x12192A, alpha: 0.86)],
                                               startPoint: .top, endPoint: .bottom)
                            )
                    }
                } else {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        actions
                            .frame(width: max(w * 0.271, 300))
                            .frame(maxHeight: .infinity)
                            .background(
                                LinearGradient(colors: [Color(hex: 0x202B3B, alpha: 0.65), Color(hex: 0x172130, alpha: 0.72),
                                                        Color(hex: 0x12192A, alpha: 0.78)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                    }
                }
            }
            .frame(width: w, height: h)
        }
        .ignoresSafeArea()
    }

    // ------------------------------------------------------------------ artwork
    private func heroArt(scale s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Image("avo_home_hero").resizable().frame(width: StartView.artW * s, height: StartView.artH * s)
            Group {
                Image("avo_logo").resizable().scaledToFit()
                    .frame(width: 170 * s, height: 170 * s)
                    .blendMode(.screen)
                    .position(x: 352 * s, y: 165 * s)
                Text("AVO")
                    .font(.system(size: 150 * s, weight: .light))
                    .tracking(14 * s)
                    .foregroundStyle(Color(hex: 0xF7F7F5))
                    .fixedSize()
                    .position(x: 341 * s, y: 378 * s)
                Text("PERFORMANCE HORSE")
                    .font(.system(size: 41 * s, weight: .medium))
                    .tracking(5 * s)
                    .foregroundStyle(Color(hex: 0xF7F7F5))
                    .fixedSize()
                    .position(x: 340 * s, y: 481 * s)
                Text("TRAINING ANALYSIS")
                    .font(.system(size: 29 * s, weight: .semibold))
                    .tracking(4 * s)
                    .foregroundStyle(Color(hex: 0xF7F7F5))
                    .fixedSize()
                    .position(x: 342 * s, y: 544 * s)
                Text("CIENCIA  ·  TECNOLOGÍA  ·  RENDIMIENTO")
                    .font(.system(size: 32 * s, weight: .semibold))
                    .tracking(4 * s)
                    .foregroundStyle(Color(hex: 0xF7F7F5))
                    .fixedSize()
                    .position(x: 493 * s, y: 1016 * s)
            }
            .shadow(color: Color.black.opacity(0.45), radius: 2.5, x: 0, y: 1.2)
        }
        .frame(width: StartView.artW * s, height: StartView.artH * s, alignment: .topLeading)
    }

    // ------------------------------------------------------------------ actions
    private var actions: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0).frame(maxHeight: .infinity).layoutPriority(-1)
            Rectangle().fill(Color(hex: 0x3A4A60)).frame(height: 1).padding(.horizontal, 10)
            action(icon: "folder", title: "Abrir entrenamiento", subtitle: "Archivos .avo / .avr") { app.showImporter = true }
            action(icon: "clock.arrow.circlepath", title: "Entrenamientos", subtitle: "Sesiones recientes, historial y favoritos") { app.page = .sessions }
            action(icon: "waveform.path.ecg", title: "Análisis", subtitle: "El caballo en el entrenamiento activo") { openAnalysis() }
            action(icon: "server.rack", title: "Servidor AVO", subtitle: "Descargar sesiones") { app.page = .server }
            action(icon: "square.split.2x1", title: "Comparar entrenamientos", subtitle: "Análisis avanzado") { app.page = .compare }
            action(icon: "doc.richtext", title: "Informes", subtitle: "Exportar y compartir") { app.page = .reports }
            Spacer(minLength: 0).frame(maxHeight: .infinity).layoutPriority(-1)
        }
        .padding(.leading, 10)
        .padding(.trailing, 24)
    }

    /// Opens «Análisis» with the active training (or the most recent one when none is selected yet).
    private func openAnalysis() {
        if app.selected == nil, let first = app.sessionsView.first { app.select(first) }
        app.page = .analysis
    }

    private func action(icon: String, title: String, subtitle: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 18) {
                ZStack {
                    Circle().fill(Color(hex: 0x1F3A5C)).frame(width: 44, height: 44)
                    Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Color(hex: 0xA9C9F2))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Color(hex: 0xF2F4F7))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(Color(hex: 0x8F9BAD)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .frame(maxWidth: .infinity, minHeight: 64, maxHeight: 120)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0x3A4A60)).frame(height: 1) }
        }
        .buttonStyle(StartActionStyle())
        .accessibilityIdentifier("start.\(title)")
    }
}

/// Hover/press highlight of the start actions (Windows StartAction style).
private struct StartActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.white.opacity(0.13) : Color.clear)
    }
}
