import SwiftUI

/// Capa 2 del planificador (motor 2.0.0-dev35): propuesta orientativa de la semana siguiente en la historia del caballo.
/// Sin calibrar con datos propios; no cambia el estado del caballo y el entrenador decide.
struct WeekPlanCard: View {
    let plan: WeekPlan

    var body: some View {
        AvoCard(title: "Semana siguiente (planificador)",
                subtitle: plan.available ? "\(dayText(plan.from)) – \(dayText(plan.to)) · propuesta orientativa, sin calibrar" : "propuesta orientativa, sin calibrar") {
            if !plan.available {
                AvoNoData(text: plan.reason.isEmpty ? "Sin propuesta" : KbText.sentence(plan.reason))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                    AvoMetric(label: "Fase", value: plan.phaseText,
                              caption: plan.ageYears.map { "\($0) años" } ?? "Sin edad del caballo",
                              accent: plan.phase.hasPrefix("REINCORPORACION") ? Avo.warn : Avo.text)
                    AvoMetric(label: "Trabajos rápidos", value: plan.fastText,
                              caption: plan.limited ? "Limitada por la base científica" : "≥ 72 h entre rápidos",
                              accent: plan.limited ? Avo.warn : Avo.text)
                    AvoMetric(label: "Distancia rápida", value: plan.fastMaxM.map { "hasta \(KbText.metres($0))" } ?? KbText.metres(plan.fastRefM),
                              caption: plan.fastMaxM == nil ? "Mediana propia de 60 d" : "Tope propuesto")
                }
                Divider().overlay(Avo.line)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(plan.days) { (d: WeekPlanDay) in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(dayText(d.date)).foregroundStyle(Avo.textDim).frame(width: 70, alignment: .leading)
                            Text(d.typeText).fontWeight(.semibold).foregroundStyle(color(d.type)).frame(width: 70, alignment: .leading)
                            Text(KbText.sentence(d.reason)).font(.caption).foregroundStyle(Avo.textDim)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            Text(d.rules.map { WeekPlan.ruleTitle($0) }.joined(separator: " · ")).font(.caption2).foregroundStyle(Avo.textDim)
                        }
                    }
                }
                ForEach(plan.notes) { (n: WeekPlanNote) in
                    Text("\(WeekPlan.ruleTitle(n.rule)): \(KbText.sentence(n.text))").font(.caption).foregroundStyle(Avo.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Propuesta sin calibrar con datos propios: no cambia el estado del caballo y el entrenador decide.")
                    .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("history.weekplan")
    }

    private func color(_ t: String) -> Color {
        switch t {
        case "RAPIDO": return Avo.red
        case "CARRERA": return Avo.warn
        case "LIBRE": return Avo.ok
        default: return Avo.text
        }
    }

    /// AAAA-MM-DD → DD/MM
    private func dayText(_ s: String) -> String {
        let p = s.prefix(10).split(separator: "-")
        return p.count == 3 ? "\(p[2])/\(p[1])" : s
    }
}
