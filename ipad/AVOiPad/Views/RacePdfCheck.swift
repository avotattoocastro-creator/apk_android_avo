import SwiftUI

/// «PDF» check of each group of data of the race card: whether that card goes into the «Informe PDF»
/// (trainer 15/11/2026). The choice is kept between races (RacesModel.pdfSections).
struct RacePdfCheck: View {
    @Environment(AppModel.self) private var app
    let section: RacePdfSection

    var body: some View {
        let on: Bool = app.races.pdfSections.contains(section)
        Button {
            app.races.togglePdf(section)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 17, weight: .semibold))
                Text("PDF").font(.caption2.weight(.bold)).tracking(0.5)
            }
            .foregroundStyle(on ? Avo.red : Avo.textDim)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(Avo.surface2.opacity(0.9), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(on ? "Incluido en el informe PDF: \(section.title)" : "No incluido en el informe PDF: \(section.title)")
        .accessibilityIdentifier("race.pdf.\(section.rawValue)")
    }
}

extension View {
    /// Puts the «PDF» check in the top-right corner of a card of the race card.
    func racePdfCheck(_ s: RacePdfSection) -> some View {
        overlay(alignment: .topTrailing) { RacePdfCheck(section: s).padding(8) }
    }
}
