import SwiftUI

/// «Datos clave» de un entrenamiento (paridad iPad ↔ PC, docs/PARIDAD_IPAD_PC.md): rejilla de cifras con icono, reparto
/// de aires y calidad de la posición. Todas las cifras salen del motor AVO Equine (Core/KeyData.swift), con las mismas
/// reglas que windows/AVO.Windows/Views/KeyDataView.xaml. Pulso y recuperaciones se muestran vacíos hasta que exista
/// el ECG de la cincha: nunca se inventan.
struct KeyDataView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let s = app.selected {
                    if let e = s.engine {
                        content(s, KeyData.cached(id: s.id, json: e.rawJson))
                    } else {
                        AvoCard(title: "Datos clave") {
                            AvoNoData(text: "El motor AVO todavía no ha analizado este entrenamiento · \(s.engineState)")
                        }
                    }
                } else {
                    AvoNoData(text: "Elige un entrenamiento")
                }
            }
            .padding(16)
        }
        .background(Avo.bg)
        .accessibilityIdentifier("page.keyData")
    }

    @ViewBuilder
    private func content(_ s: SessionItem, _ k: KeyData) -> some View {
        AvoPageTitle(title: "\(s.horse) · \(s.dateTimeText)",
                     subtitle: "Cifras del motor AVO Equine · iguales en iPad y PC")
        section("Velocidad y tiempos", k.tiles.filter { $0.group == 0 })
        section("Pulso", k.tiles.filter { $0.group == 1 })
        section("Tranco", k.tiles.filter { $0.group == 2 })
        HStack(alignment: .top, spacing: 12) {
            gaitsCard(k)
            qualityCard(k)
        }
    }

    private func section(_ title: String, _ tiles: [KeyTile]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(Avo.silver)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
                ForEach(tiles) { (t: KeyTile) in tile(t) }
            }
        }
    }

    private func tile(_ t: KeyTile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: Self.icon(t.id)).font(.title3)
                .foregroundStyle(t.group == 1 ? Avo.redLight : (t.group == 2 ? Avo.silver : Avo.blue))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(t.value).font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(t.available ? Avo.text : Avo.unknown)
                    .lineLimit(1).minimumScaleFactor(0.5)
                if !t.unit.isEmpty { Text(t.unit).font(.footnote).foregroundStyle(Avo.textDim) }
            }
            Text(t.label).font(.callout.weight(.semibold)).foregroundStyle(Avo.text)
            Text(t.caption).font(.caption2).foregroundStyle(t.available ? Avo.textDim : Avo.warn).lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(Avo.cardBrush, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Avo.line, style: StrokeStyle(lineWidth: 1, dash: t.available ? [] : [5, 4])))
        .accessibilityIdentifier("keydata.\(t.id)")
    }

    private func gaitsCard(_ k: KeyData) -> some View {
        AvoCard(title: "Aires", subtitle: "Tiempo en cada aire según el motor") {
            if k.gaits.isEmpty {
                AvoNoData(text: "Sin reparto de aires")
            } else {
                GeometryReader { (g: GeometryProxy) in
                    HStack(spacing: 0) {
                        ForEach(k.gaits) { (a: KeyGait) in
                            Rectangle().fill(Self.gaitColor(a.id)).frame(width: max(0, g.size.width * a.share))
                        }
                    }
                }
                .frame(height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                ForEach(k.gaits) { (a: KeyGait) in
                    HStack {
                        Circle().fill(Self.gaitColor(a.id)).frame(width: 10, height: 10)
                        Text(a.name).font(.callout).foregroundStyle(Avo.text)
                        Spacer()
                        Text(TimeText.clock(a.seconds)).font(.callout.monospacedDigit()).foregroundStyle(Avo.silver)
                        Text(DotNetFormat.custom(a.share * 100, "0", spanish: true) + " %")
                            .font(.callout.weight(.semibold).monospacedDigit()).foregroundStyle(Avo.text).frame(width: 56, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func qualityCard(_ k: KeyData) -> some View {
        AvoCard(title: "Calidad de la posición", subtitle: "Solución GNSS de la espalda (bloque rtk del motor)") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(k.qualityLabel).font(.title2.weight(.semibold))
                    .foregroundStyle(k.qualityLabel == "RTK FIX" ? Avo.ok : (k.qualityLabel == "Sin datos" ? Avo.unknown : Avo.warn))
                if let f = k.fixShare {
                    Text(DotNetFormat.custom(f * 100, "0", spanish: true) + " % en FIX").font(.callout).foregroundStyle(Avo.textDim)
                }
            }
            let total: Double = k.qualitySeconds.reduce(0) { $0 + $1.seconds }
            ForEach(k.qualitySeconds.indices, id: \.self) { (i: Int) in
                HStack {
                    Text(k.qualitySeconds[i].label).font(.callout).foregroundStyle(Avo.text)
                    Spacer()
                    Text(total > 0 ? DotNetFormat.custom(k.qualitySeconds[i].seconds / total * 100, "0", spanish: true) + " %" : "—")
                        .font(.callout.monospacedDigit()).foregroundStyle(Avo.silver)
                }
            }
            if k.qualityLabel != "RTK FIX" && k.qualityLabel != "Sin datos" {
                Text("Sin RTK FIX la precisión es de decímetros: tiempos y velocidades válidos, cifras centimétricas no.")
                    .font(.caption2).foregroundStyle(Avo.warn)
            }
        }
    }

    static func icon(_ id: String) -> String {
        switch id {
        case "vmax": return "gauge.with.dots.needle.67percent"
        case "best200", "best600", "best1000": return "stopwatch"
        case "distance": return "point.topleft.down.to.point.bottomright.curvepath"
        case "duration": return "clock"
        case "hrmax", "hrend": return "waveform.path.ecg"
        case "rec2", "rec15": return "heart.text.square"
        case "lmax": return "ruler"
        case "fmax": return "metronome"
        default: return "circle"
        }
    }

    static func gaitColor(_ code: String) -> Color {
        switch code {
        case "PARADO": return Avo.line
        case "PASO": return Avo.unknown
        case "TROTE": return Avo.cyan
        case "GALOPE": return Avo.blue
        default: return Avo.silver
        }
    }
}
