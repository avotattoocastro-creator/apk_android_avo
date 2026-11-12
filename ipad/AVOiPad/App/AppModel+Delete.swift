import Foundation

/// «Eliminar entrenamiento» (Listado, with confirmation). Removes the training from the app: its copy in the library,
/// the RAW / download copies the app keeps inside its own folder, the engine results and training summary, the zones
/// corrected by hand, the trainer rating, the segments, the notes, the favourite mark and the useful window. Files of the
/// user outside the app folder (Files, AirDrop…) are never touched. The SHA-256 and the session id are remembered in
/// eliminados.json so «Buscar entrenamientos perdidos» does not bring the training back; opening the file again on
/// purpose («Abrir») imports it as usual and forgets that mark.
extension AppModel {
    var deletedFile: String { AvoFiles.join(paths.root, "eliminados.json") }

    struct DeletedTrainings: Codable {
        var shas: [String] = []
        var sessionIds: [String] = []
    }

    func loadDeleted() -> DeletedTrainings {
        guard let data = AvoFiles.read(deletedFile),
              let d = try? JSONDecoder().decode(DeletedTrainings.self, from: data) else { return DeletedTrainings() }
        return d
    }

    private func saveDeleted(_ d: DeletedTrainings) {
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            try AvoFiles.writeAtomic(try enc.encode(d), to: deletedFile)
        } catch {
            log.warn("eliminar", "No se pudo guardar eliminados.json", error)
        }
    }

    /// A training opened again on purpose is no longer «deleted».
    func forgetDeleted(sha: String?, sessionId: String) {
        var d: DeletedTrainings = loadDeleted()
        let n: Int = d.shas.count + d.sessionIds.count
        if let s = sha?.lowercased() { d.shas.removeAll { $0 == s } }
        d.sessionIds.removeAll { $0 == sessionId }
        if d.shas.count + d.sessionIds.count != n { saveDeleted(d) }
    }

    /// True for a path inside the app's own folder (the only files this function may delete).
    private func isAppFile(_ path: String) -> Bool {
        let root: String = (paths.root as NSString).standardizingPath + "/"
        return (path as NSString).standardizingPath.hasPrefix(root)
    }

    @MainActor
    func deleteTraining(_ item: SessionItem) {
        let id: String = item.id
        let sha: String? = item.session.fileSha256?.lowercased()
        let fm = FileManager.default
        var removedFiles: Int = 0
        func rm(_ p: String) {
            guard !p.isEmpty, isAppFile(p), fm.fileExists(atPath: p) else { return }
            do { try fm.removeItem(atPath: p); removedFiles += 1 } catch { log.warn("eliminar", "No se pudo borrar \(p)", error) }
        }
        if isPlaying { stopPlay() }
        // 1. copies kept by the app (library, RAW cache, downloads inside the app folder)
        if let s = sha {
            for e in library.entries where e.sha256.lowercased() == s { rm(e.storedPath) }
            library.remove(s)
        }
        for p in item.session.rawSegmentPaths { rm(p) }
        if let src = item.session.sourcePath { rm(src) }
        // 2. everything derived from it
        rm(engineDir(id))
        rm(segmentStore.pathFor(id))
        rm(notesPath(item))
        corrections.forget(id)
        if rating(for: id) != nil {
            var all: [String: TrainingRating] = shellState.ratings ?? TrainingRatingStore.load(ratingsFile)
            all.removeValue(forKey: id)
            shellState.ratings = all
            try? TrainingRatingStore.save(all, to: ratingsFile)
        }
        if item.isFavorite { toggleFavorite(item) }
        shellState.windows.removeValue(forKey: id)
        // 3. remembered, so the recovery scan does not import it again
        var d: DeletedTrainings = loadDeleted()
        if let s = sha, !d.shas.contains(s) { d.shas.append(s) }
        if !d.sessionIds.contains(id) { d.sessionIds.append(id) }
        saveDeleted(d)
        // 4. out of the list
        sessions.removeAll { $0 === item }
        if selected === item {
            selected = nil
            select(AppModel.byDateDescending(sessions).first)
        }
        notifySessionChanged()
        status = "Entrenamiento eliminado (\(item.dateTimeText) · \(item.horse)) · \(removedFiles) archivos borrados"
        log.info("eliminar", "Entrenamiento eliminado", ["id": id, "sha": sha ?? "", "archivos": String(removedFiles)])
    }
}
