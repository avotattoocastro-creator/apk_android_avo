import Foundation

/// AVO BEACH 1.0.0 (motor 2.0.0-dev36, 25/11/2026): marea del trabajo y franja de playa automática.
/// Opciones que se pasan al motor con cada análisis:
///  - "marea": la predicción del IHM del puerto más cercano (la misma de la página Mareas), de 16 h antes a 3 h después del
///    entrenamiento, cada 10 min. Se guarda en disco (30 días), así que funciona sin conexión una vez descargada.
///  - "playa": de la geocerca POLÍGONO cuyo nombre contiene «Playa» (Geocercas): vértices 1 y 2 en el pie de la duna o del
///    paseo (línea seca), vértices 3 y 4 en la orilla de una bajamar viva. Debe quedar DESACTIVADA para que no vaya al reloj
///    ni haga de recorrido. Alturas por defecto del motor (4,6 m y 0,4 m).
extension AppModel {
    /// Opciones extra del motor de una sesión: raza, asignación y correcciones (CorrectionsModel) + marea y playa.
    /// Todas las llamadas al motor usan esta misma función para que el resultado guardado (caché) sea el mismo.
    func engineExtra(_ item: SessionItem) async -> String {
        let beach: String = await beachOptions(item)
        return [corrections.engineOptions(item), beach].filter { !$0.isEmpty }.joined(separator: ",")
    }

    func beachOptions(_ item: SessionItem) async -> String {
        guard let start = item.start else { return "" }
        var parts: [String] = []
        var lat: Double = settings.placeLatitude, lon: Double = settings.placeLongitude
        if item.timeline.count > 0 && item.timeline.lat[0].isFinite && item.timeline.lon[0].isFinite {
            lat = item.timeline.lat[0]; lon = item.timeline.lon[0]
        }
        // marea (predicción IHM, la misma que la página Mareas)
        if settings.onlineEnvironment {
            let svc = EnvironmentService(cacheDir: paths.environmentCache)
            do {
                let all: [TidePort] = try await svc.ports()
                let port: TidePort? = all.first(where: { $0.id == settings.tidePortId })
                    ?? all.min(by: { $0.distanceKmTo(lat, lon) < $1.distanceKmTo(lat, lon) })
                if let p = port {
                    let tp: TidePrediction = try await svc.tides(p, aroundUtc: start, placeLat: lat, placeLon: lon)
                    let end: Date = start.addingTimeInterval(max(0, item.timeline.durationS))
                    let pts: [TideCurvePoint] = tp.curve(from: start.addingTimeInterval(-16 * 3600), to: end.addingTimeInterval(3 * 3600), step: 600)
                    if pts.count >= 2 {
                        let curve: String = pts.map { "[\(Int($0.t.timeIntervalSince1970)),\(String(format: "%.3f", $0.h))]" }.joined(separator: ",")
                        parts.append("\"marea\":{\"curva\":[" + curve + "],\"fuente\":" + AvoJSON.quote(tp.source + " · " + p.name) + "}")
                    }
                }
            } catch {
                log.info("playa", "sin marea para el motor: " + error.localizedDescription)
            }
        }
        // playa: polígono «Playa» de Geocercas (4 vértices: 2 en la línea seca, 2 en la de bajamar)
        if let g = geofences {
            let fences: [PlanFence] = g.plan.fences.compactMap { $0 }
            if let f = fences.first(where: { $0.type == .polygon && $0.vertices.count >= 4 &&
                $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains("playa") }) {
                let v: [PlanPoint] = f.vertices
                func pt(_ p: PlanPoint) -> String { "[\(p.lat),\(p.lon)]" }
                parts.append("\"playa\":{\"linea_seca\":{\"a\":\(pt(v[0])),\"b\":\(pt(v[1]))},\"linea_bajamar\":{\"a\":\(pt(v[2])),\"b\":\(pt(v[3]))}}")
            }
        }
        return parts.joined(separator: ",")
    }
}
