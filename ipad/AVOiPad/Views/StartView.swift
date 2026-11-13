import SwiftUI

/// Start screen = port of windows/AVO.Windows/Views/StartView.xaml + HeroArt.xaml: full-bleed hero photo with the AVO
/// lettering (in the photo's 2004×1098 coordinates, scaled like the Windows Viewbox UniformToFill, anchored top-left).
/// Trainer's sketch 13/11/2026: no side panel and no «Menú» button here; the motto centred at the bottom and one
/// «INICIAR» button above it, which opens the Dashboard (the sidebar comes back on every page other than Inicio).
struct StartView: View {
    @Environment(AppModel.self) private var app

    private static let artW: CGFloat = 2004
    private static let artH: CGFloat = 1098

    var body: some View {
        GeometryReader { geo in
            let w: CGFloat = geo.size.width
            let h: CGFloat = geo.size.height
            let s: CGFloat = max(w / StartView.artW, h / StartView.artH)
            // scale of the centred texts: as the artwork, but never wider than the screen (portrait)
            let t: CGFloat = min(s, w * 0.85 / 900)
            ZStack(alignment: .topLeading) {
                Color(hex: 0x0B1020)
                heroArt(scale: s)
                    .frame(width: StartView.artW * s, height: StartView.artH * s, alignment: .topLeading)
                    .frame(width: w, height: h, alignment: .topLeading)
                    .clipped()
                VStack(spacing: 34 * t) {
                    Spacer(minLength: 0)
                    startButton(scale: t)
                    Text("CIENCIA  ·  TECNOLOGÍA  ·  RENDIMIENTO")
                        .font(.system(size: 32 * t, weight: .semibold))
                        .tracking(4 * t)
                        .foregroundStyle(Color(hex: 0xF7F7F5))
                        .fixedSize()
                        .shadow(color: Color.black.opacity(0.45), radius: 2.5, x: 0, y: 1.2)
                        .accessibilityIdentifier("start.motto")
                }
                .padding(.bottom, max(28, h - 1030 * s))
                .frame(width: w, height: h)
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
                // round logo removed and the lettering moved up into its place (trainer's sketch 08/11/2026)
                Text("AVO")
                    .font(.system(size: 150 * s, weight: .light))
                    .tracking(14 * s)
                    .foregroundStyle(Color(hex: 0xF7F7F5))
                    .fixedSize()
                    .position(x: 341 * s, y: 190 * s)
                Text("PERFORMANCE HORSE")
                    .font(.system(size: 41 * s, weight: .medium))
                    .tracking(5 * s)
                    .foregroundStyle(Color(hex: 0xF7F7F5))
                    .fixedSize()
                    .position(x: 340 * s, y: 293 * s)
                Text("TRAINING ANALYSIS")
                    .font(.system(size: 29 * s, weight: .semibold))
                    .tracking(4 * s)
                    .foregroundStyle(Color(hex: 0xF7F7F5))
                    .fixedSize()
                    .position(x: 342 * s, y: 356 * s)
            }
            .shadow(color: Color.black.opacity(0.45), radius: 2.5, x: 0, y: 1.2)
        }
        .frame(width: StartView.artW * s, height: StartView.artH * s, alignment: .topLeading)
    }

    // ------------------------------------------------------------------ «INICIAR»
    /// Thin white outline over translucent navy, tracked capitals like the lettering of the photo. Opens the Dashboard.
    private func startButton(scale t: CGFloat) -> some View {
        Button {
            app.page = .sessions
        } label: {
            HStack(spacing: 12 * t) {
                if !app.startReady { ProgressView().tint(Color(hex: 0xF7F7F5)) }
                Text(app.startReady ? "INICIAR" : "CARGANDO DATOS DE AVO HORSE…")
            }
                .font(.system(size: (app.startReady ? 26 : 16) * t, weight: .semibold))
                .tracking((app.startReady ? 9 : 3) * t)
                .foregroundStyle(Color(hex: 0xF7F7F5))
                .padding(.leading, 9 * t)          // tracking adds space after the last letter: keep the word centred
                .padding(.horizontal, 64 * t)
                .padding(.vertical, 18 * t)
                .background(Color(hex: 0x12192A, alpha: 0.55), in: RoundedRectangle(cornerRadius: 6 * t))
                .overlay(RoundedRectangle(cornerRadius: 6 * t).stroke(Color(hex: 0xF7F7F5, alpha: 0.85), lineWidth: 1.5))
                .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 2)
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
