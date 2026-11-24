import SwiftUI

/// Start screen: full-bleed sunset artwork (25/11/2026) that already carries the AVO lettering, «PERFORMANCE HORSE»,
/// «TRAINING ANALYSIS» and the motto «CIENCIA · TECNOLOGÍA · RENDIMIENTO» painted into the scene. The view only draws
/// the «INICIAR» button on the wet sand, above the motto, in the artwork's own 1448×1086 coordinates (scaled like
/// UniformToFill and centred), so it stays in the same place of the picture on every iPad.
/// Before 25/11/2026 the lettering was drawn here as text over the photo (port of the Windows HeroArt.xaml).
struct StartView: View {
    @Environment(AppModel.self) private var app

    private static let artW: CGFloat = 1448
    private static let artH: CGFloat = 1086
    /// Centre of «INICIAR» in the artwork: centred in width, on the wet sand above the motto (motto at y ≈ 962).
    private static let buttonX: CGFloat = 724
    private static let buttonY: CGFloat = 882

    var body: some View {
        GeometryReader { geo in
            let w: CGFloat = geo.size.width
            let h: CGFloat = geo.size.height
            let s: CGFloat = max(w / StartView.artW, h / StartView.artH)
            ZStack {
                Color(hex: 0x0B1020)
                ZStack(alignment: .topLeading) {
                    Image("avo_home_hero")
                        .resizable()
                        .frame(width: StartView.artW * s, height: StartView.artH * s)
                        .accessibilityLabel("AVO Performance Horse. Training Analysis. Ciencia, tecnología, rendimiento.")
                        .accessibilityIdentifier("start.motto")
                    startButton(scale: s)
                        .position(x: StartView.buttonX * s, y: StartView.buttonY * s)
                }
                .frame(width: StartView.artW * s, height: StartView.artH * s)
                .frame(width: w, height: h)
                .clipped()
            }
            .frame(width: w, height: h)
        }
        .ignoresSafeArea()
    }

    // ------------------------------------------------------------------ «INICIAR»
    /// Thin warm outline over translucent dark glass, tracked capitals like the lettering of the artwork.
    /// Opens the Dashboard.
    private func startButton(scale t: CGFloat) -> some View {
        Button {
            app.page = .sessions
        } label: {
            HStack(spacing: 12 * t) {
                if !app.startReady { ProgressView().tint(Color(hex: 0xF7EBDD)) }
                Text(app.startReady ? "INICIAR" : "CARGANDO DATOS DE AVO HORSE…")
            }
                .font(.system(size: (app.startReady ? 25 : 16) * t, weight: .semibold))
                .tracking((app.startReady ? 10 : 3) * t)
                .foregroundStyle(Color(hex: 0xF7EBDD))
                .padding(.leading, (app.startReady ? 10 : 3) * t)   // tracking adds space after the last letter
                .padding(.horizontal, 64 * t)
                .padding(.vertical, 18 * t)
                .background(.ultraThinMaterial.opacity(0.55), in: RoundedRectangle(cornerRadius: 6 * t))
                .background(Color(hex: 0x1C1418, alpha: 0.35), in: RoundedRectangle(cornerRadius: 6 * t))
                .overlay(RoundedRectangle(cornerRadius: 6 * t).stroke(Color(hex: 0xFFE0BA, alpha: 0.65), lineWidth: 1.2))
                .shadow(color: Color(hex: 0xFFB070, alpha: 0.25), radius: 14, x: 0, y: 0)
                .fixedSize()
                .contentShape(Rectangle())
        }
        .buttonStyle(StartButtonStyle())
        .disabled(!app.startReady)
        .accessibilityIdentifier("start.iniciar")
    }
}

/// Press feedback of «INICIAR».
private struct StartButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
