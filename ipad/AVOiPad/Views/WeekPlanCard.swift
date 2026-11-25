import SwiftUI

/// Planificador semanal (motor 2.0.0-dev37, TRAINING 1.4.0): semana natural de lunes a domingo. Los días pasados muestran
/// lo realizado según las sesiones; el resto es la propuesta orientativa del motor. Sin calibrar con datos propios; no
/// cambia el estado del caballo y el entrenador decide. Se usa en la historia del caballo y en la hoja «Planificador
/// semanal» de la Cuadra.
struct WeekPlanCard: View {
    let plan: WeekPlan

    private var today: String { WeekPlansModel.today }

    var body: some View {
        AvoCard(title: plan.calendarWeek ? "Planificador semanal" : "Semana siguiente (planificador)",
                subtitle: plan.available ? "\(WeekPlan.weekdayShort(plan.from)) \(dayText(plan.from)) – \(WeekPlan.weekdayShort(plan.to)) \(dayText(plan.to)) · propuesta orientativa, sin calibrar"
                                         : "propuesta orientativa, sin calibrar") {
            if !plan.available {
                AvoNoData(text: plan.reason.isEmpty ? "Sin propuesta" : KbText.sentence(plan.reason))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                    AvoMetric(label: "Fase", value: plan.phaseText,
                              caption: plan.ageYears.map { "\($0) años" } ?? "Sin edad del caballo",
                              accent: plan.phase.hasPrefix("REINCORPORACION") ? Avo.warn : Avo.text)
                    AvoMetric(label: "Trabajos rápidos", value: plan.fastText,
                              caption: plan.limited ? "Limitada por la base científica" : plan.fastCaption,
                              accent: plan.limited ? Avo.warn : Avo.text)
                    AvoMetric(label: "Distancia rápida", value: plan.fastMaxM.map { "hasta \(KbText.metres($0))" } ?? KbText.metres(plan.fastRefM),
                              caption: plan.fastMaxM == nil ? "Mediana propia de 60 d" : "Tope propuesto")
                }
                Divider().overlay(Avo.line)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(plan.days) { (d: WeekPlanDay) in
                        dayRow(d)
                    }
                }
                ForEach(plan.notes) { (n: WeekPlanNote) in
                    Text("\(WeekPlan.ruleTitle(n.rule)): \(KbText.sentence(n.text))").font(.caption).foregroundStyle(Avo.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(plan.calendarWeek ? "Los días pasados son lo realizado según los entrenamientos; el resto es una propuesta sin calibrar con datos propios: no cambia el estado del caballo y el entrenador decide."
                                       : "Propuesta sin calibrar con datos propios: no cambia el estado del caballo y el entrenador decide.")
                    .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("history.weekplan")
    }

    private func dayRow(_ d: WeekPlanDay) -> some View {
        let isToday: Bool = d.date == today
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(WeekPlan.weekdayShort(d.date)) \(dayText(d.date))")
                .fontWeight(isToday ? .bold : .regular)
                .foregroundStyle(isToday ? Avo.red : Avo.textDim).frame(width: 90, alignment: .leading)
            Text(d.typeText).fontWeight(.semibold).foregroundStyle(d.done ? Avo.textDim : color(d.type)).frame(width: 70, alignment: .leading)
            if d.done {
                AvoPill(text: "HECHO", color: Avo.silver)
            } else if isToday {
                AvoPill(text: "HOY", color: Avo.red)
            }
            Text(KbText.sentence(d.reason)).font(.caption).foregroundStyle(Avo.textDim)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Text(d.rules.map { WeekPlan.ruleTitle($0) }.joined(separator: " · ")).font(.caption2).foregroundStyle(Avo.textDim)
        }
        .opacity(d.done ? 0.7 : 1)
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

/// Hoja «Planificador semanal» de un caballo (botón de la Cuadra, junto a «Historia de entrenamientos»).
struct WeekPlanSheet: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m: WeekPlansModel = app.weekPlans
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let p = m.plans[m.sheetKey], !m.loading || p.available {
                        WeekPlanCard(plan: p)
                    } else if m.loading {
                        AvoCard {
                            HStack(spacing: 10) {
                                ProgressView().controlSize(.small)
                                Text(m.progressText.isEmpty ? "Calculando la semana con el motor…" : m.progressText)
                                    .font(.callout).foregroundStyle(Avo.textDim)
                            }
                        }
                    } else if let e = m.errors[m.sheetKey] {
                        AvoCard { AvoNoData(text: "No se pudo calcular la semana: \(e)") }
                    } else {
                        AvoCard { AvoNoData(text: "Sin propuesta para este caballo") }
                    }
                }
                .padding(16)
            }
            .background(Avo.bg)
            .navigationTitle("Planificador semanal · \(m.sheetName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { m.close() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        m.reloadOne(m.sheetKey, name: m.sheetName)
                    } label: { Label("Actualizar", systemImage: "arrow.clockwise") }
                        .disabled(m.loading)
                }
            }
        }
        .accessibilityIdentifier("sheet.weekplan")
    }
}
