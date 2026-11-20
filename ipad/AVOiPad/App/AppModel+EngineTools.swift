import Foundation

/// Buttons of the «Motor» page (trainer's sketch 19/11/2026, build 173: a column of buttons at the top right of
/// «Lectura del entrenamiento»): reprocess one training, reprocess every training of the horse, export the engine JSON
/// and delete the stored engine results. The engine itself decides when a stored result is still valid (same engine
/// version, algorithm versions, input fingerprint and parameters: equine-intelligence/src/core/store.cpp).
extension AppModel {
    /// Trainings of the same horse as `item` (Cuadra code, or the horse name when there is no code), oldest first.
    func sessionsOfSameHorse(_ item: SessionItem) -> [SessionItem] {
        let key: String = horseKey(item)
        return sessions.filter { horseKey($0).caseInsensitiveCompare(key) == .orderedSame }
            .sorted { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }
    }

    /// Runs the current engine (forced, the stored result is not reused) on every training of the list, one after the
    /// other. `progress(done, total)` is called on the main actor. Returns how many ended with a result.
    @MainActor
    func reprocess(_ items: [SessionItem], progress: @escaping (Int, Int) -> Void) async -> Int {
        var ok: Int = 0
        for (i, s) in items.enumerated() {
            if Task.isCancelled { break }
            progress(i, items.count)
            await runEngine(s, force: true)
            if s.engine != nil { ok += 1 }
        }
        progress(items.count, items.count)
        log.info("motor", "Reprocesados \(ok) de \(items.count) entrenamientos con el motor \(EquineEngine.version())")
        return ok
    }

    /// Writes the engine result of the training (JSON as returned by the engine) to Documentos › Exportados.
    func exportEngineJson(_ item: SessionItem) throws -> URL {
        guard let e = item.engine, !e.rawJson.isEmpty else {
            throw AvoError.invalidOperation("Este entrenamiento todavía no tiene resultado del motor")
        }
        let path: String = AvoFiles.join(exportDir, AppModel.exportName(item, ext: "_motor.json"))
        try AvoFiles.writeAtomic(Data(e.rawJson.utf8), to: path)
        return URL(fileURLWithPath: path)
    }

    /// Deletes every stored engine result (analisis_*.json in each training folder of paths.analysis). The training
    /// summaries and the corrections are kept. Returns how many files were deleted.
    func deleteEngineCache() -> Int {
        var n: Int = 0
        for dir in AvoFiles.list(paths.analysis) {
            for f in AvoFiles.list(dir) {
                let name: String = AvoFiles.fileName(f)
                guard name.hasPrefix("analisis_") && name.hasSuffix(".json") else { continue }
                if (try? FileManager.default.removeItem(atPath: f)) != nil { n += 1 }
            }
        }
        log.info("motor", "Caché del motor borrada: \(n) resultados")
        return n
    }
}
