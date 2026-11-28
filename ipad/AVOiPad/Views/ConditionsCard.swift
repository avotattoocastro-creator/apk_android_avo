import SwiftUI

/// Comparables por condiciones (TC1–TC4, PC1–PC3, GO1; motor 2.0.0-dev41) en la historia del caballo: tiempo, calor,
/// going y peso de la última sesión y cuántas sesiones quedan para comparar cada métrica. Sin calibrar: no cambia el
/// estado ni es un diagnóstico.
struct ConditionsCard: View {
    let cond: TrainingConditions

    var body: some View {
        AvoCard(title: "Condiciones del trabajo",
                subtitle: "Con qué sesiones se compara · sin calibrar, informativo") {
            if !cond.available {
                AvoNoData(text: cond.reason.isEmpty ? "Sin sesiones" : KbText.sentence(cond.reason))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                    AvoMetric(label: "Temperatura y humedad", value: cond.weatherText, caption: "WBGT " + cond.wbgtText)
                    AvoMetric(label: "Calor", value: cond.heatText,
                              caption: cond.heat == "CALOR" ? "La V200 de hoy no se compara" : "Comparables con ±5 °C")
                    AvoMetric(label: "Going", value: TrainingConditions.stratumTitle(cond.goingStratum),
                              caption: "Mismo estado del terreno")
                    AvoMetric(label: "Jinete con equipo", value: cond.weightText,
                              caption: cond.rider.isEmpty ? "Sin jinete anotado" : cond.rider)
                    ForEach(cond.rules) { (r: ConditionsRuleCount) in
                        AvoMetric(label: r.title, value: r.valueText, caption: r.excludedText)
                    }
                }
                if !cond.marks.isEmpty {
                    Divider().overlay(Avo.line)
                    ForEach(cond.marks) { (m: ConditionsMark) in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dateText(m.date) + " · " + KbText.sentence(m.text)).font(.footnote).foregroundStyle(Avo.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(m.evidence).font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                ForEach(Array(cond.notes.enumerated()), id: \.offset) { (n: (offset: Int, element: String)) in
                    Text(KbText.sentence(n.element)).font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                }
                Text("Las sesiones con otro calor, otro going o más de 3 kg de diferencia de peso no se usan como referencia. Sin coeficiente de corrección; no cambia el estado del caballo.")
                    .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("history.conditions")
    }

    private func dateText(_ iso: String) -> String {
        let p = iso.split(separator: "-")
        return p.count == 3 ? "\(p[2])/\(p[1])" : iso
    }
}
