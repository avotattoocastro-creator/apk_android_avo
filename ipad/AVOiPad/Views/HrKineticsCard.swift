import SwiftUI

/// Cinética de la FC (CF2, RC1, FW1, WU3; motor 2.0.0-dev40) en la historia del caballo: recuperación, tiempo hasta
/// 100 lpm y FC del trote fijo del calentamiento frente a su propia mediana. Tendencia propia sin calibrar: no cambia
/// el estado ni es un diagnóstico.
struct HrKineticsCard: View {
    let kin: TrainingHrKinetics

    var body: some View {
        AvoCard(title: "Calentamiento y recuperación (FC)",
                subtitle: "Tendencia del propio caballo · sin calibrar, informativo") {
            if !kin.available {
                AvoNoData(text: kin.reason.isEmpty ? "Sin sesiones con pulso de la cincha" : KbText.sentence(kin.reason))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                    ForEach(kin.metrics) { (m: HrKineticsMetric) in
                        AvoMetric(label: m.title, value: m.valueText, caption: m.changeText)
                    }
                    AvoMetric(label: "Vuelta a la calma", value: TrainingHrKinetics.cooldownTitle(kin.cooldown),
                              caption: "Calentamiento " + KbText.distance(kin.warmupM))
                }
                if !kin.marks.isEmpty {
                    Divider().overlay(Avo.line)
                    ForEach(kin.marks) { (m: HrKineticsMark) in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dateText(m.date) + " · " + KbText.sentence(m.text)).font(.footnote).foregroundStyle(Avo.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(m.evidence).font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                ForEach(Array(kin.notes.enumerated()), id: \.offset) { (n: (offset: Int, element: String)) in
                    Text(KbText.sentence(n.element)).font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                }
                Text("Solo se compara con sesiones de la misma superficie, vuelta a la calma y calentamiento parecido. Umbrales sin calibrar; no cambia el estado del caballo.")
                    .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("history.hrkinetics")
    }

    private func dateText(_ iso: String) -> String {
        let p = iso.split(separator: "-")
        return p.count == 3 ? "\(p[2])/\(p[1])" : iso
    }
}
