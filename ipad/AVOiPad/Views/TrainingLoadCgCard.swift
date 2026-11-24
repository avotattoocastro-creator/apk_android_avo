import SwiftUI

/// CG1–CG3 (motor 2.0.0-dev34): carga interna (TRIMP con la FC del ECG) y externa (metros de trabajo rápido por bandas)
/// en la historia del caballo. Descriptiva: aguda y crónica por separado y su cociente como cambio relativo; no cambia
/// el estado ni es un riesgo de lesión.
struct TrainingLoadCgCard: View {
    let cg: TrainingLoadCg
    var referenceDate: String = ""

    var body: some View {
        AvoCard(title: "Carga de entrenamiento (CG1–CG3)",
                subtitle: "TRIMP con la FC de la cincha y metros de trabajo rápido\(referenceDate.isEmpty ? "" : " a " + referenceDate) · descriptivo, sin validar en caballos de carreras") {
            if !cg.available {
                AvoNoData(text: "Sin datos: las sesiones no traen el ECG de la cincha ni las bandas de velocidad del motor 2.0.0-dev34. Vuelve a analizarlas.")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                    AvoMetric(label: "Trabajo rápido 7 d", value: KbText.distance(cg.externalLoad.total7d),
                              caption: "30 d: \(KbText.distance(cg.externalLoad.total30d))")
                    AvoMetric(label: "Media 7 d / 28 d", value: pair(cg.externalLoad, 0, "m/día"),
                              caption: ratioCaption(cg.externalLoad))
                    AvoMetric(label: "TRIMP 7 d", value: KbText.ratio(cg.internalLoad.total7d, 1),
                              caption: "30 d: \(KbText.ratio(cg.internalLoad.total30d, 1)) UA")
                    AvoMetric(label: "TRIMP 7 d / 28 d", value: pair(cg.internalLoad, 1, "UA/día"),
                              caption: ratioCaption(cg.internalLoad))
                    AvoMetric(label: "Monotonía (trabajo rápido)", value: KbText.ratio(cg.externalLoad.monotony),
                              caption: "Strain \(KbText.ratio(cg.externalLoad.strain, 0)) · Foster, informativo")
                    AvoMetric(label: "FC máxima del TRIMP", value: cg.hrMax.map { AvoFormat.f($0, 0) } ?? KbText.noData, unit: "lpm",
                              caption: cg.hrMaxText, accent: cg.hrMaxOrigin == "POR_DEFECTO" ? Avo.warn : Avo.text)
                }
                if !cg.bands.isEmpty {
                    Divider().overlay(Avo.line)
                    bandsTable
                }
                ForEach(Array(cg.notes.enumerated()), id: \.offset) { (n: (offset: Int, element: String)) in
                    Text(KbText.sentence(n.element)).font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                }
                Text("Cambio relativo frente a la propia historia; no es un riesgo de lesión y no cambia el estado del caballo.")
                    .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("history.cg")
    }

    private func pair(_ s: CgSeriesStatus, _ decimals: Int, _ unit: String) -> String {
        guard let a = s.ewmaAcute, let c = s.ewmaChronic else { return KbText.noData }
        return "\(AvoFormat.f(a, decimals)) / \(AvoFormat.f(c, decimals)) \(unit)"
    }

    private func ratioCaption(_ s: CgSeriesStatus) -> String {
        if let r = s.ratio { return "Cociente \(AvoFormat.f(r, 2)) (cambio relativo)" }
        return s.reason.isEmpty ? "Sin cociente" : "Sin cociente: \(s.reason)"
    }

    private var bandsTable: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text((cg.scale == "RELATIVAS_V_CARRERA" ? "Bandas de velocidad (escaladas por la velocidad de carrera)" : "Bandas de velocidad (Morrice-West 2020)").uppercased())
                .font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim)
            ForEach(cg.bands) { (b: CgBand) in
                HStack(spacing: 8) {
                    Text(TrainingLoadCg.bandTitle(b.name)).foregroundStyle(Avo.textDim).frame(width: 90, alignment: .leading)
                    Text(b.limitsText).frame(width: 120, alignment: .leading)
                    Text("7 d " + KbText.distance(b.total7dM)).frame(width: 110, alignment: .leading)
                    Text("30 d " + KbText.distance(b.total30dM)).frame(width: 120, alignment: .leading)
                }
                .font(.footnote.monospacedDigit()).foregroundStyle(Avo.text).lineLimit(1)
            }
        }
    }
}
