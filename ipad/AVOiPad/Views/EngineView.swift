import SwiftUI

/// «Motor AVO» page = port of windows/AVO.Windows/Views/EngineView.xaml: detailed results of the AVO Equine Intelligence
/// Engine (same C++ engine as Android and Windows) for the active training.
struct EngineView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        GeometryReader { geo in
            let wide: Bool = geo.size.width >= 1000
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ShellSessionHeader()
                    infoCard
                    if wide {
                        HStack(alignment: .top, spacing: 12) {
                            segmentsCard.frame(maxWidth: .infinity)
                            qualityCard.frame(maxWidth: .infinity)
                        }
                        HStack(alignment: .top, spacing: 12) {
                            curvesCard.frame(maxWidth: .infinity)
                            eventsCard.frame(maxWidth: .infinity)
                        }
                    } else {
                        segmentsCard
                        qualityCard
                        curvesCard
                        eventsCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(Avo.bg)
    }

    private var engine: EquineAnalysis? { app.selected?.engine }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(app.engineInfo).font(.callout.weight(.semibold)).foregroundStyle(Avo.text)
            if let e = engine {
                if !e.fusionSummary.isEmpty {
                    Text(e.fusionSummary).font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                }
                let warnings: [String] = e.warnings.filter { (w: String) -> Bool in !GpsTerms.mentionsGnss(w) }
                ForEach(0..<warnings.count, id: \.self) { (i: Int) in
                    Text(warnings[i]).font(.caption).foregroundStyle(Avo.warn).fixedSize(horizontal: false, vertical: true)
                }
            } else if let s = app.selected {
                Text("Motor: \(s.engineState)").font(.caption).foregroundStyle(Avo.textDim)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Avo.cardBrush, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Avo.line, lineWidth: 1))
    }

    private var segmentsCard: some View {
        AvoCard(title: "Segmentos de rendimiento (clasificador de aires)") {
            ShellTable(columns: [
                ShellTable.Column(title: "#", width: 30), ShellTable.Column(title: "Aire", width: 90),
                ShellTable.Column(title: "Desde", width: 60), ShellTable.Column(title: "Hasta", width: 60),
                ShellTable.Column(title: "Distancia", width: 75), ShellTable.Column(title: "V. media", width: 80),
                ShellTable.Column(title: "Cadencia", width: 80), ShellTable.Column(title: "Tranco", width: 65),
                ShellTable.Column(title: "IMU", width: 160),
            ], rows: (engine?.segments ?? []).map { (r: EngineSegmentRow) -> [String] in
                ["\(r.id)", r.aire, r.desde, r.hasta, r.distancia, r.velocidadMedia, r.cadencia, r.tranco, r.calidadImu]
            })
        }
    }

    private var qualityCard: some View {
        AvoCard(title: "Calidad por dominio") {
            ShellTable(columns: [
                ShellTable.Column(title: "Dominio", width: 110), ShellTable.Column(title: "Nivel", width: 100),
                ShellTable.Column(title: "Motivos", width: 280),
            ], rows: (engine?.quality ?? [])
                .filter { (r: EngineQualityRow) -> Bool in !GpsTerms.mentionsGnss(r.dominio) }
                .map { (r: EngineQualityRow) -> [String] in [r.dominio, r.nivel, r.motivos] })
        }
    }

    private var curvesCard: some View {
        AvoCard(title: "Curvas detectadas") {
            ShellTable(columns: [
                ShellTable.Column(title: "#", width: 30), ShellTable.Column(title: "Sentido", width: 70),
                ShellTable.Column(title: "Inicio", width: 60), ShellTable.Column(title: "Giro", width: 60),
                ShellTable.Column(title: "Radio", width: 110), ShellTable.Column(title: "Lateral estimada", width: 180),
            ], rows: (engine?.curves ?? []).map { (r: EngineCurveRow) -> [String] in
                ["\(r.id)", r.direccion, r.inicio, r.giro, r.radio, r.lateralEstimada]
            })
        }
    }

    private var eventsCard: some View {
        AvoCard(title: "Eventos trazables") {
            ShellTable(columns: [
                ShellTable.Column(title: "Id", width: 60), ShellTable.Column(title: "Tipo", width: 130),
                ShellTable.Column(title: "Inicio", width: 60), ShellTable.Column(title: "Fin", width: 60),
                ShellTable.Column(title: "Motivo", width: 240),
            ], rows: (engine?.events ?? [])
                .filter { (r: EngineEventRow) -> Bool in !GpsTerms.mentionsGnss(r.tipo) && !GpsTerms.mentionsGnss(r.motivo) }
                .map { (r: EngineEventRow) -> [String] in [r.id, r.tipo, r.inicio, r.fin, r.motivo] })
        }
    }
}
