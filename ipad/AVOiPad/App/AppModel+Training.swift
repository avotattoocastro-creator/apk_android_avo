import Foundation

// AVO Training Analytics 1.0.0 in the shell: trainer ratings (valoraciones.json), the per-session summary written next
// to the engine analysis (paths.analysis/<id>/training_summary.json) and the history of one horse
// (avo_eq_training_analyse with the summaries of all its sessions). Orientative, never a veterinary diagnosis.

extension AppModel {
    // ------------------------------------------------------------------ ratings
    var ratingsFile: String { AvoFiles.join(paths.root, "valoraciones.json") }

    private var allRatings: [String: TrainingRating] {
        if let r = shellState.ratings { return r }
        let r: [String: TrainingRating] = TrainingRatingStore.load(ratingsFile)
        shellState.ratings = r
        return r
    }

    func rating(for id: String) -> TrainingRating? { allRatings[id] }

    /// Stores (or clears, with nil / empty) the trainer's rating of a session and regenerates its training summary.
    /// Returns an error text, nil when saved.
    @MainActor
    func saveRating(_ item: SessionItem, _ rating: TrainingRating?) async -> String? {
        var all: [String: TrainingRating] = allRatings
        if var r = rating, !r.isEmpty {
            r.actualizado_utc = AvoTime.iso(Date())
            all[item.id] = r
        } else {
            all.removeValue(forKey: item.id)
        }
        shellState.ratings = all
        do {
            try TrainingRatingStore.save(all, to: ratingsFile)
        } catch {
            log.warn("valoraciones", error.localizedDescription, error)
            return error.localizedDescription
        }
        log.info("valoraciones", "Valoración guardada", ["id": item.id])
        if let e = item.engine {
            await writeTrainingSummary(item, analysisJson: e.rawJson)
        } else {
            // the summary is regenerated with the rating when the engine runs again
            try? FileManager.default.removeItem(atPath: trainingSummaryPath(item.id))
        }
        return nil
    }

    // ------------------------------------------------------------------ per-session summary
    /// Stable identity of the horse of a session: the Cuadra record code if known, otherwise the name.
    func horseKey(_ s: SessionItem) -> String {
        if let c = s.horseCode, !c.trimmed.isEmpty { return c }
        return s.horse
    }

    func trainingSummaryPath(_ id: String) -> String {
        AvoFiles.join(engineDir(id), TrainingAnalytics.summaryFileName)
    }

    /// avo_eq_training_summary of the analysis JSON with {"id","caballo","jinete","fecha_utc","valoracion","pista"}.
    @MainActor
    func writeTrainingSummary(_ item: SessionItem, analysisJson: String) async {
        if analysisJson.isEmpty { return }
        let extra: String = TrainingAnalytics.extraJson(id: item.id, horse: horseKey(item), rider: item.rider,
                                                        dateUtc: item.start.map { AvoTime.iso($0) }, rating: rating(for: item.id))
        let path: String = trainingSummaryPath(item.id)
        let err: String? = await Task.detached(priority: .utility) { () -> String? in
            do {
                let text: String = try EquineEngine.trainingSummary(analysisJson: analysisJson, extraJson: extra)
                try AvoFiles.writeAtomic(Data(text.utf8), to: path)
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value
        if let e = err { log.warn("entrenamiento", "Resumen de entrenamiento de \(item.id): " + e) }
    }

    /// Makes sure the session has its training summary: from the analysis in memory, or running the engine (stored result
    /// reused) without keeping the analysis in memory. False when the session cannot be analysed.
    @MainActor
    func ensureTrainingSummary(_ item: SessionItem) async -> Bool {
        let path: String = trainingSummaryPath(item.id)
        if AvoFiles.exists(path) { return true }
        if let e = item.engine {
            await writeTrainingSummary(item, analysisJson: e.rawJson)
            return AvoFiles.exists(path)
        }
        if !EquineEngine.available || item.session.rawSegmentPaths.isEmpty { return false }
        while shellState.engineBusy {
            if Task.isCancelled { return false }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        shellState.engineBusy = true
        var json: String = ""
        do {
            let options: String = EquineEngine.options(series: true, cacheDir: engineDir(item.id), force: false)
            json = try await EquineEngine.analyseJson(item.session.rawSegmentPaths, options)
        } catch {
            shellState.engineBusy = false
            if !(error is CancellationError) { log.warn("entrenamiento", "Motor para el resumen de \(item.id): " + error.localizedDescription) }
            return false
        }
        await writeTrainingSummary(item, analysisJson: json)
        shellState.engineBusy = false
        return AvoFiles.exists(path)
    }

    // ------------------------------------------------------------------ history of one horse
    /// A horse of the Cuadra marked DEMO, or (without record) a horse whose sessions are all demonstration sessions.
    func isDemoHorse(_ key: String) -> Bool {
        if let r = stable.store.find(.horse, key) { return r.demo }
        let mine: [SessionItem] = sessions.filter { horseKey($0).caseInsensitiveCompare(key) == .orderedSame }
        return !mine.isEmpty && mine.allSatisfy { $0.isSynthetic }
    }

    func horseName(_ key: String) -> String {
        if let r = stable.store.find(.horse, key) { return r.name }
        return sessions.first { horseKey($0).caseInsensitiveCompare(key) == .orderedSame }?.horse ?? key
    }

    /// Sessions of a horse (DEMO sessions only for a demo horse), optionally only those that started before `until`.
    func historySessions(_ key: String, until: Date? = nil) -> [SessionItem] {
        let demoHorse: Bool = isDemoHorse(key)
        return sessions.filter { (s: SessionItem) -> Bool in
            if horseKey(s).caseInsensitiveCompare(key) != .orderedSame { return false }
            if s.isSynthetic && !demoHorse { return false }
            if let u = until, let d = s.start, d >= u { return false }
            return true
        }
    }

    /// avo_eq_training_analyse with every summary of the horse. `reference` = "AAAA-MM-DD" (nil = last session).
    /// `until` limits the sessions (race card: before the day after the race). `progress(done, total)` while summaries
    /// are prepared. Returns the result and how many sessions have no summary.
    @MainActor
    func analyseHorseHistory(_ key: String, reference: String?, until: Date? = nil,
                             progress: ((Int, Int) -> Void)? = nil) async throws -> (result: TrainingAnalysisResult, missing: Int) {
        let list: [SessionItem] = historySessions(key, until: until)
        var entries: [TrainingAnalytics.HistoryEntry] = []
        var k: Int = 0
        for s in list {
            k += 1
            progress?(k, list.count)
            if Task.isCancelled { throw CancellationError() }
            _ = await ensureTrainingSummary(s)
            entries.append(TrainingAnalytics.HistoryEntry(id: s.id, summaryPath: trainingSummaryPath(s.id), horse: key, rider: s.rider,
                                                          dateUtc: s.start.map { AvoTime.iso($0) }, rating: rating(for: s.id)))
        }
        if Task.isCancelled { throw CancellationError() }
        let horse: String = key
        let input: (json: String, used: Int, missing: [String]) = await Task.detached(priority: .userInitiated) {
            () -> (json: String, used: Int, missing: [String]) in
            TrainingAnalytics.historyInput(horse: horse, reference: reference, entries: entries)
        }.value
        let json: String = try await EquineEngine.trainingAnalyse(inputJson: input.json, optionsJson: nil)
        let result: TrainingAnalysisResult = try await Task.detached(priority: .userInitiated) { () -> TrainingAnalysisResult in
            try TrainingAnalysisResult.parse(json)
        }.value
        return (result, input.missing.count)
    }
}
