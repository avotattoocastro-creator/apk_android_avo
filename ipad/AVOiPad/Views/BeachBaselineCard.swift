import SwiftUI

/// Línea base de la playa por franja (PL2–PL6, motor 2.0.0-dev39) en la historia del caballo: sesiones y métricas por
/// franja, zancada ajustada a una velocidad común (efecto de la franja), impactos relativos a su franja y marcas de
/// suelo. Descriptiva y sin calibrar: no cambia el estado ni es una predicción de lesiones.
struct BeachBaselineCard: View {
    let beach: TrainingBeachBaseline

    var body: some View {
        AvoCard(title: "Playa por franjas (PL2–PL6)",
                subtitle: "Línea base propia de cada franja · sin calibrar, informativo") {
            if !beach.available {
                AvoNoData(text: beach.reason.isEmpty ? "Sin sesiones de playa con franja" : KbText.sentence(beach.reason))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                    AvoMetric(label: "Sesiones de playa", value: "\(beach.beachSessions)",
                              caption: beach.refBand.isEmpty ? "Sin franja de referencia" : "Referencia: " + TrainingBeachBaseline.bandTitle(beach.refBand))
                    AvoMetric(label: "Zancada por velocidad", value: beach.slopeText,
                              caption: "Velocidad común " + KbText.ms(beach.commonSpeed, 1))
                    AvoMetric(label: "Rápidos en orilla firme 7 d", value: "\(beach.fastFirm7d)",
                              caption: "Última: " + (beach.lastBand.isEmpty ? KbText.noData : TrainingBeachBaseline.bandTitle(beach.lastBand)))
                    AvoMetric(label: "Impactos de la última", value: KbText.ratio(beach.lastImpactsKm, 1), unit: "/km",
                              caption: beach.lastImpactsRelative.map { "× " + AvoFormat.f($0, 2) + " de su franja" } ?? "Sin línea base de su franja")
                    AvoMetric(label: "Humedad del suelo", value: TrainingBeachBaseline.soilTitle(beach.lastSoilClass),
                              caption: "Sonda TDR en la ficha de campo")
                }
                Divider().overlay(Avo.line)
                bandsTable
                if !beach.marks.isEmpty {
                    Divider().overlay(Avo.line)
                    ForEach(beach.marks) { (m: BeachMarkStatus) in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dateText(m.date) + " · " + KbText.sentence(m.text)).font(.footnote).foregroundStyle(Avo.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(m.evidence).font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                ForEach(Array(beach.notes.enumerated()), id: \.offset) { (n: (offset: Int, element: String)) in
                    Text(KbText.sentence(n.element)).font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                }
                Text("Cada franja se compara solo consigo misma. Umbrales sin calibrar; no cambia el estado del caballo.")
                    .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("history.beach")
    }

    private func dateText(_ iso: String) -> String {
        let p = iso.split(separator: "-")
        return p.count == 3 ? "\(p[2])/\(p[1])" : iso
    }

    private var bandsTable: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Por franja".uppercased()).font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim)
            ForEach(beach.bands) { (b: BeachBandStatus) in
                HStack(spacing: 8) {
                    Text(TrainingBeachBaseline.bandTitle(b.band)).foregroundStyle(Avo.textDim).frame(width: 120, alignment: .leading)
                    Text("\(b.sessions) ses." + (b.usable ? "" : " (pocas)")).frame(width: 90, alignment: .leading)
                    Text("Zancada " + (b.stride.median.map { AvoFormat.f($0, 2) + " m" } ?? KbText.noData)).frame(width: 130, alignment: .leading)
                    Text("Efecto " + b.strideEffectText).frame(width: 120, alignment: .leading)
                    Text("V200 " + KbText.ms(b.v200.median, 2)).frame(width: 120, alignment: .leading)
                }
                .font(.footnote.monospacedDigit()).foregroundStyle(b.usable ? Avo.text : Avo.textDim).lineLimit(1)
            }
        }
    }
}
