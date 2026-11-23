import Foundation

/// AVO PPK 1.0.0 (docs/PPK.md): posición poscalculada de la espalda con la base del IGN.
/// Orden: resultado guardado en el iPad → resultado en la nube (lo calculó otra app) → cálculo aquí y subida a la nube.
extension AppModel {
    var ppkStore: PpkStore { PpkStore(paths: paths) }

    func ppkSummary(_ item: SessionItem) -> PpkSummary? {
        ppkStore.load(item.id).flatMap { PpkSummary.parse($0) }
    }

    func ppkJson(_ item: SessionItem) -> String? { ppkStore.load(item.id) }

    /// Lo que necesita la sesión (horas UTC, posición aproximada). Bloqueante: se ejecuta fuera del hilo principal.
    @MainActor
    func ppkNeed(_ item: SessionItem) async throws -> PpkNeed {
        let segs: [String] = item.session.rawSegmentPaths
        if segs.isEmpty { throw PpkError.noRaw }
        let text: String = try await Task.detached(priority: .userInitiated) { try EquineEngine.ppkNeed(segs) }.value
        guard let need = PpkNeed.parse(text), need.hasRaw else { throw PpkError.noRaw }
        return need
    }

    /// Calcula (o reutiliza) el PPK. `manualBase`: ficheros RINEX de la base elegidos a mano (pueden ir en .gz).
    /// `station`: estación ERGNSS (4 caracteres) para descargar la base del IGN; nil = la de Ajustes.
    @MainActor
    func runPpk(_ item: SessionItem, station: String? = nil, manualBase: [String] = [], recalc: Bool = false,
                progress: @escaping @MainActor (String) -> Void) async throws -> PpkSummary {
        let sid: String = item.id
        let store: PpkStore = ppkStore
        if !recalc && manualBase.isEmpty, let s = ppkSummary(item) { return s }
        // 1) ¿lo calculó ya otra app? (nube del usuario, mismo .avo)
        var remote: CloudItem? = nil
        var code: String? = nil
        if await live.ensureSignedIn(), let c = live.signedCode {
            code = c
            remote = try? await live.cloud.item(code: c, sessionId: sid)
            if !recalc && manualBase.isEmpty, let r = remote {
                progress("Buscando el PPK en la nube…")
                if let j = try? await live.cloud.downloadPpk(code: c, sessionId: sid, avoSha256: r.sha256),
                   let s = PpkSummary.parse(j) {
                    try store.save(sid, j)
                    log.info("ppk", "\(sid): PPK traído de la nube (\(s.base), FIX \(Int(s.pctFix)) %)")
                    return s
                }
            }
        }
        // 2) base
        progress("Leyendo los datos RAWX de la sesión…")
        let need: PpkNeed = try await ppkNeed(item)
        var base: [String] = []
        if !manualBase.isEmpty {
            AvoFiles.ensureDir(store.baseDir)
            for p in manualBase {
                if p.lowercased().hasSuffix(".gz") {
                    let data: Data = try Data(contentsOf: URL(fileURLWithPath: p))
                    let target: String = AvoFiles.join(store.baseDir, String(AvoFiles.fileName(p).dropLast(3)))
                    try Gzip.decompress(data).write(to: URL(fileURLWithPath: target), options: .atomic)
                    base.append(target)
                } else {
                    base.append(p)
                }
            }
        } else {
            let sta: String = (station ?? PpkConfig.station).trimmingCharacters(in: .whitespaces).uppercased()
            if sta.count != 4 { throw PpkError.noStation }
            progress("Descargando la base \(sta) del IGN (\(need.hours.count) h)…")
            base = try await IgnBase.download(station: sta, hours: need.hours, into: store.baseDir)
        }
        // 3) cálculo (RTKLIB en el motor)
        progress("Calculando el PPK (RTKLIB)…")
        let segs: [String] = item.session.rawSegmentPaths
        let opts: String = "{\"dir_trabajo\":" + AvoJSON.quote(store.baseDir) + "}"
        let json: String = try await EquineEngine.ppk(segs, base: base, optionsJson: opts)
        guard let summary = PpkSummary.parse(json) else { throw PpkError.failed("Respuesta del motor no válida") }
        try store.save(sid, json)
        log.info("ppk", "\(sid): PPK calculado (\(summary.base), FIX \(Int(summary.pctFix)) %, \(summary.epochs) épocas)")
        // 4) a la nube, junto al .avo, para que las demás apps no lo repitan
        if let c = code, let r = remote {
            progress("Subiendo el PPK a la nube…")
            do { try await live.cloud.uploadPpk(json: json, code: c, sessionId: sid, avoSha256: r.sha256) }
            catch { log.warn("ppk", "\(sid): no se pudo subir el PPK a la nube", error) }
        }
        return summary
    }

    /// Tras descargar entrenamientos de la nube: PPK en segundo plano de los que tengan RAWX (si hay estación elegida).
    /// Los que aún no tienen base publicada en el IGN quedan para la próxima vez; nunca molesta con avisos.
    @MainActor
    func autoPpk(_ sessionIds: [String]) async {
        for sid in sessionIds {
            guard let item = sessions.first(where: { $0.id == sid }), ppkSummary(item) == nil else { continue }
            do {
                _ = try await runPpk(item, progress: { _ in })
            } catch PpkError.noRaw {
                continue
            } catch PpkError.noStation {
                // sin estación elegida: el PPK de la nube (si lo hay) ya se intentó dentro de runPpk
                continue
            } catch {
                log.warn("ppk", "\(sid): PPK automático pendiente", error)
            }
        }
    }
}
