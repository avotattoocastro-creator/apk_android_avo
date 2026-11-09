import SwiftUI
import Observation

/// Race waiting for the user to confirm the horse of the Cuadra and the runner of the PDF.
struct RacePendingImport: Identifiable {
    let id = UUID()
    var race: Race
    /// Path of the PDF already copied to paths.root/carreras (deleted when the import is cancelled).
    var storedPdf: String
    /// Started from the horse card: the horse is known and cannot be changed in the sheet.
    var horseFixed: Bool
    var horseCode: String?
    var runnerName: String?
    var message: String
}

/// «Carreras»: races imported from the France Galop / McLloyd tracking PDF (carreras.json + copy of the PDF in
/// paths.root/carreras), linked to a horse of the Cuadra, with the analysis against its trainings (Core/RaceAnalysis.swift).
@Observable
final class RacesModel {
    @ObservationIgnored unowned let app: AppModel

    var races: [Race] = []
    /// Race card shown on the «Carreras» page (nil = list).
    var selectedRaceId: String? = nil
    /// fileImporter of the Races page / horse card.
    var showImporter: Bool = false
    /// Horse of the card that started the import (nil = started from the Races page).
    var importHorseCode: String? = nil
    var pending: RacePendingImport? = nil
    var busy: Bool = false
    var message: String = ""
    var messageIsError: Bool = false

    // filters of the list
    var filterHorse: String = ""          // record code; "" = all
    var useDateFrom: Bool = false
    var dateFrom: Date = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()
    var useDateTo: Bool = false
    var dateTo: Date = Date()

    /// Analysis of each race (recomputed when the trainings change).
    var reports: [String: RaceReport] = [:]
    var computing: Set<String> = []
    @ObservationIgnored private var trainingCache: [String: TrainingWorkSummary] = [:]

    init(app: AppModel) {
        self.app = app
        races = RacesModel.load(file: AvoFiles.join(app.paths.root, "carreras.json"), log: app.log)
    }

    // ---------------------------------------------------------------- contract
    func sessionChanged() {
        // trainings, trims or assignments may have changed: analyses are recomputed when shown
        reports = [:]
    }

    func pageShown() {
        if let id = selectedRaceId, races.contains(where: { $0.id == id }) {
            if let r = race(id) { requestReport(r) }
        } else {
            selectedRaceId = nil
        }
    }

    // ---------------------------------------------------------------- storage
    var file: String { AvoFiles.join(app.paths.root, "carreras.json") }
    var pdfDir: String { AvoFiles.join(app.paths.root, "carreras") }

    static func load(file: String, log: AppLog) -> [Race] {
        guard let data = AvoFiles.read(file) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        do {
            return try dec.decode([Race].self, from: data)
        } catch {
            log.warn("carreras", "carreras.json no válido: " + error.localizedDescription)
            StableJson.keepDamaged(file)
            return []
        }
    }

    private func save() {
        defer { app.scheduleDocumentsSync() }
        do {
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try AvoFiles.writeAtomic(try enc.encode(races), to: file)
        } catch {
            app.log.warn("carreras", error.localizedDescription, error)
            app.show("Carreras", "No se pudo guardar carreras.json: " + error.localizedDescription, error: true)
        }
    }

    // ---------------------------------------------------------------- queries
    func race(_ id: String) -> Race? { races.first { $0.id == id } }

    var selectedRace: Race? { selectedRaceId.flatMap { race($0) } }

    func racesOf(horse code: String) -> [Race] {
        RacesModel.byDate(races.filter { ($0.horseRecordCode ?? "").caseInsensitiveCompare(code) == .orderedSame })
    }

    static func byDate(_ l: [Race]) -> [Race] {
        l.sorted { (a: Race, b: Race) -> Bool in (a.date ?? a.importedAt) > (b.date ?? b.importedAt) }
    }

    /// List of the page with the filters applied, newest first.
    var filtered: [Race] {
        let cal: Calendar = RacesModel.madridCalendar
        let from: Date = cal.startOfDay(for: dateFrom)
        let toEnd: Date = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: dateTo)) ?? dateTo
        return RacesModel.byDate(races.filter { (r: Race) -> Bool in
            if !filterHorse.isEmpty && (r.horseRecordCode ?? "").caseInsensitiveCompare(filterHorse) != .orderedSame { return false }
            let d: Date = r.date ?? r.importedAt
            if useDateFrom && d < from { return false }
            if useDateTo && d >= toEnd { return false }
            return true
        })
    }

    var hasFilters: Bool { !filterHorse.isEmpty || useDateFrom || useDateTo }

    func clearFilters() {
        filterHorse = ""
        useDateFrom = false
        useDateTo = false
    }

    static var madridCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = AvoTime.madrid
        return c
    }

    /// Horses of the Cuadra (active first) for pickers.
    var horses: [IdentityRecord] {
        app.stable.store.horses.sorted { (a: IdentityRecord, b: IdentityRecord) -> Bool in
            if a.active != b.active { return a.active }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    func horseName(_ code: String?) -> String {
        guard let c = code, let r = app.stable.store.find(.horse, c) else { return code ?? "Sin caballo" }
        return r.name
    }

    // ---------------------------------------------------------------- import
    /// «Añadir carrera» from the Races page (horse = nil) or from the horse card (horse code).
    func startImport(horseCode: String?) {
        importHorseCode = horseCode
        showImporter = true
    }

    @MainActor
    func importPDF(_ url: URL) async {
        let horse: String? = importHorseCode
        importHorseCode = nil
        busy = true
        message = "Leyendo \(url.lastPathComponent)…"
        messageIsError = false
        let dir: String = pdfDir
        let result: (race: Race?, stored: String?, error: String?) = await Task.detached(priority: .userInitiated) { () -> (race: Race?, stored: String?, error: String?) in
            RacesModel.copyAndParse(url, dir: dir)
        }.value
        busy = false
        guard var race = result.race, let stored = result.stored else {
            message = result.error ?? RaceTrackingParser.unrecognised
            messageIsError = true
            app.show("Añadir carrera", message, error: true)
            return
        }
        race.sourceFile = AvoFiles.fileName(stored)
        message = ""
        if let code = horse {
            let rec: IdentityRecord? = app.stable.store.find(.horse, code)
            let names: [String] = [rec?.name ?? "", code]
            let cands: [Int] = RaceNames.candidates(names, race.runners)
            if cands.count == 1 {
                finish(race, stored: stored, horseCode: code, runner: race.runners[cands[0]].name)
                return
            }
            let msg: String = cands.isEmpty
                ? "No se encontró «\(rec?.name ?? code)» entre los \(race.runners.count) participantes: elige cuál es."
                : "Hay \(cands.count) participantes que coinciden con «\(rec?.name ?? code)»: elige cuál es."
            pending = RacePendingImport(race: race, storedPdf: stored, horseFixed: true, horseCode: code,
                                        runnerName: cands.first.map { race.runners[$0].name }, message: msg)
        } else {
            // from the Races page: propose the best automatic match (one stable horse ↔ one runner)
            var pairs: [(String, Int)] = []
            for h in horses where h.active {
                for i in RaceNames.candidates([h.name, h.code], race.runners) { pairs.append((h.code, i)) }
            }
            let code: String? = pairs.count == 1 ? pairs[0].0 : nil
            let runner: String? = pairs.count == 1 ? race.runners[pairs[0].1].name : nil
            let msg: String = pairs.count == 1
                ? "Coincidencia automática: «\(horseName(code))» = «\(runner ?? "")». Confírmalo o cámbialo."
                : (pairs.isEmpty ? "Ningún caballo de la Cuadra coincide con los participantes: elige el caballo y su nombre en la carrera."
                                 : "Varias coincidencias posibles: elige el caballo y su nombre en la carrera.")
            pending = RacePendingImport(race: race, storedPdf: stored, horseFixed: false, horseCode: code, runnerName: runner, message: msg)
        }
    }

    /// Copies the PDF (security-scoped) to paths.root/carreras/<yyyyMMdd>_<name> and parses it.
    static func copyAndParse(_ url: URL, dir: String) -> (race: Race?, stored: String?, error: String?) {
        let access: Bool = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        AvoFiles.ensureDir(dir)
        let base: String = url.lastPathComponent.isEmpty ? "carrera.pdf" : url.lastPathComponent
        var target: String = AvoFiles.join(dir, AvoTime.formatter("yyyyMMdd-HHmmss").string(from: Date()) + "_" + base)
        if AvoFiles.exists(target) { target = AvoFiles.join(dir, UUID().uuidString + "_" + base) }
        do {
            try FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: target))
        } catch {
            return (nil, nil, "No se pudo leer el archivo: " + error.localizedDescription)
        }
        do {
            let race: Race = try RaceTrackingParser.parse(url: URL(fileURLWithPath: target))
            return (race, target, nil)
        } catch {
            try? FileManager.default.removeItem(atPath: target)
            return (nil, nil, error.localizedDescription)
        }
    }

    func confirmPending() {
        guard let p = pending else { return }
        guard let code = p.horseCode, !code.isEmpty else {
            pending?.message = "Elige el caballo de la Cuadra."
            return
        }
        guard let runner = p.runnerName, p.race.runners.contains(where: { $0.name == runner }) else {
            pending?.message = "Elige el nombre del caballo en la carrera."
            return
        }
        pending = nil
        finish(p.race, stored: p.storedPdf, horseCode: code, runner: runner)
    }

    func cancelPending() {
        if let p = pending { try? FileManager.default.removeItem(atPath: p.storedPdf) }
        pending = nil
    }

    /// Runners that match a horse (for the sheet: preselect when the horse changes).
    func suggestedRunner(_ race: Race, horseCode: String?) -> String? {
        guard let c = horseCode else { return nil }
        let rec: IdentityRecord? = app.stable.store.find(.horse, c)
        let cands: [Int] = RaceNames.candidates([rec?.name ?? "", c], race.runners)
        return cands.count == 1 ? race.runners[cands[0]].name : nil
    }

    private func finish(_ race: Race, stored: String, horseCode: String, runner: String) {
        var r: Race = race
        r.horseRecordCode = horseCode
        r.horseName = horseName(horseCode)
        r.ourRunnerName = runner
        races.append(r)
        save()
        app.log.info("carreras", "Carrera importada", ["race": r.raceName, "horse": horseCode, "runner": runner])
        app.status = "Carrera importada: \(r.title) · \(r.horseName ?? horseCode) \(r.finishText)"
        selectedRaceId = r.id
        if app.page != .races { app.page = .races }
        requestReport(r)
    }

    /// Race estimated from the video (RaceVideoModel): saved like an imported race and opened in «Carreras».
    func addVideoRace(_ race: Race) {
        races.append(race)
        save()
        app.log.info("carreras", "Carrera analizada desde vídeo", ["race": race.raceName, "horse": race.horseRecordCode ?? ""])
        app.status = "Carrera analizada desde el vídeo: \(race.title) · \(race.horseName ?? race.ourRunnerName ?? "")"
        selectedRaceId = race.id
        if app.page != .races { app.page = .races }
        requestReport(race)
    }

    // ---------------------------------------------------------------- edit
    func delete(_ id: String) {
        guard let r = race(id) else { return }
        races.removeAll { $0.id == id }
        if !r.isDemo && !r.sourceFile.isEmpty { try? FileManager.default.removeItem(atPath: AvoFiles.join(pdfDir, r.sourceFile)) }
        if selectedRaceId == id { selectedRaceId = nil }
        reports.removeValue(forKey: id)
        save()
    }

    func saveNotes(_ id: String, _ text: String) {
        guard let i = races.firstIndex(where: { $0.id == id }) else { return }
        races[i].notes = text
        save()
    }

    func open(_ r: Race) {
        selectedRaceId = r.id
        if app.page != .races { app.page = .races }
        requestReport(r)
    }

    func pdfPath(_ r: Race) -> String? {
        if r.isDemo { return Bundle.main.path(forResource: "demo_race_20261029BOU03", ofType: "pdf") }
        if r.sourceFile.isEmpty { return nil }
        let p: String = AvoFiles.join(pdfDir, r.sourceFile)
        return AvoFiles.exists(p) ? p : nil
    }

    // ---------------------------------------------------------------- analysis
    /// Trainings of the horse before the day of the race (Europe/Madrid), in the useful window chosen by the user.
    func trainings(for r: Race) -> [SessionItem] {
        guard let code = r.horseRecordCode else { return [] }
        let cal: Calendar = RacesModel.madridCalendar
        let limit: Date = cal.startOfDay(for: r.date ?? r.importedAt)
        return AppModel.byDateDescending(app.sessions.filter { (s: SessionItem) -> Bool in
            guard let c = s.horseCode, c.caseInsensitiveCompare(code) == .orderedSame else { return false }
            guard let d = s.start else { return false }
            return d < limit
        })
    }

    func requestReport(_ r: Race) {
        if reports[r.id] != nil || computing.contains(r.id) { return }
        guard let idx = r.ourIndex else { return }
        computing.insert(r.id)
        // copy the arrays on the main actor; the windows are computed off the main thread
        struct Input { var key: String; var id: String; var date: Date?; var demo: Bool; var t: [Double]; var d: [Double]; var v: [Double]; var b: [Bool] }
        var inputs: [Input] = []
        var cached: [TrainingWorkSummary] = []
        for s in trainings(for: r) {
            let key: String = "\(s.id)|\(s.windowStart ?? -1)|\(s.windowEnd ?? -1)"
            if let c = trainingCache[key] { cached.append(c); continue }
            let tl: SessionTimeline = s.timeline
            inputs.append(Input(key: key, id: s.id, date: s.start, demo: s.isSynthetic, t: tl.t, d: tl.distance, v: tl.speedFiltered,
                                b: tl.breakBefore))
        }
        let race: Race = r
        Task { @MainActor [weak self] in
            let computed: [(String, TrainingWorkSummary)] = await Task.detached(priority: .userInitiated) { () -> [(String, TrainingWorkSummary)] in
                inputs.map { (x: Input) -> (String, TrainingWorkSummary) in
                    (x.key, TrainingWorkAnalyzer.analyze(sessionId: x.id, date: x.date, isDemo: x.demo, t: x.t, distance: x.d,
                                                         speedMs: x.v, breaks: x.b))
                }
            }.value
            guard let self = self else { return }
            var all: [TrainingWorkSummary] = cached
            for (k, s) in computed {
                self.trainingCache[k] = s
                all.append(s)
            }
            let rep: RaceReport = RaceAnalysis.analyze(race: race, ourIndex: idx, trainings: all)
            self.reports[race.id] = rep
            self.computing.remove(race.id)
            await self.computeForm(race)
        }
    }

    // ---------------------------------------------------------------- training vs race, sector by sector (AVO Track Work)
    /// Trainings of the horse in the `RaceTrainingSplits.windowDays` days before the race.
    func splitTrainings(for r: Race) -> [SessionItem] {
        guard let d = r.date else { return [] }
        let cal: Calendar = RacesModel.madridCalendar
        let from: Date = cal.date(byAdding: .day, value: -RaceTrainingSplits.windowDays, to: cal.startOfDay(for: d)) ?? d
        return trainings(for: r).filter { (s: SessionItem) -> Bool in (s.start ?? .distantPast) >= from }
    }

    /// Efforts and passes with splits of those trainings (only the ones already analysed by the engine).
    func splitCandidates(for r: Race) -> [RaceTrainingCandidate] {
        guard let d = r.date else { return [] }
        let sources: [RaceTrainingSource] = splitTrainings(for: r).compactMap { (s: SessionItem) -> RaceTrainingSource? in
            guard let e = s.engine else { return nil }
            return RaceTrainingSource(sessionId: s.id, date: s.start, isDemo: s.isSynthetic, trackWork: e.trackWork)
        }
        return RaceTrainingSplits.candidates(sources, raceDate: d, calendar: RacesModel.madridCalendar)
    }

    /// Trainings of the window without an engine result yet.
    func splitPending(for r: Race) -> Int {
        splitTrainings(for: r).filter { $0.engine == nil }.count
    }

    /// Races whose trainings are being analysed for the sector comparison.
    var splitsAnalysing: Set<String> = []

    /// Runs the engine (cached results are reused) on the trainings of the window that have no result yet.
    func analyseSplitTrainings(_ r: Race) {
        if splitsAnalysing.contains(r.id) { return }
        let pending: [SessionItem] = splitTrainings(for: r).filter { $0.engine == nil }
        if pending.isEmpty { return }
        splitsAnalysing.insert(r.id)
        Task { @MainActor [weak self] in
            for s in pending {
                guard let self = self else { return }
                await self.app.runEngine(s, force: false)
            }
            self?.splitsAnalysing.remove(r.id)
        }
    }

    /// «Forma antes de la carrera»: history of the horse at the race date (AVO Training Analytics), added to the report.
    @MainActor
    private func computeForm(_ race: Race) async {
        guard let code = race.horseRecordCode, !code.isEmpty else {
            reports[race.id]?.formState = "Carrera sin caballo de la Cuadra"
            return
        }
        guard let date = race.date else {
            reports[race.id]?.formState = "Carrera sin fecha"
            return
        }
        let reference: String = AvoTime.formatter("yyyy-MM-dd").string(from: date)
        // sessions up to the end of the race day (Europe/Madrid); the engine ignores those after fecha_referencia
        let until: Date = RacesModel.madridCalendar.date(byAdding: .day, value: 1, to: RacesModel.madridCalendar.startOfDay(for: date)) ?? date
        do {
            let r: (result: TrainingAnalysisResult, missing: Int) = try await app.analyseHorseHistory(code, reference: reference, until: until)
            if r.result.sesionesUsadas == 0 {
                reports[race.id]?.formState = "Sin entrenamientos analizables de este caballo hasta el día de la carrera"
                return
            }
            let form: RaceTrainingForm = RaceAnalysis.form(r.result, demo: app.isDemoHorse(code))
            guard reports[race.id] != nil else { return }
            reports[race.id]?.form = form
            reports[race.id]?.formState = ""
            reports[race.id]?.observations.append(contentsOf: RaceAnalysis.formObservations(form))
        } catch is CancellationError {
            return
        } catch {
            reports[race.id]?.formState = "No se pudo calcular: " + error.localizedDescription
            app.log.warn("carreras", "Forma antes de la carrera: " + error.localizedDescription, error)
        }
    }

    // ---------------------------------------------------------------- capture mode (CI screenshots)
    /// Imports the sample race bundled with the app and links it to the DEMO horse «Rayo (demo)» (DEMOSTRACIÓN).
    @MainActor
    func importDemoForCapture() async {
        guard let path = Bundle.main.path(forResource: "demo_race_20261029BOU03", ofType: "pdf") else {
            app.log.warn("carreras", "Sin carrera de demostración en el paquete")
            return
        }
        let parsed: Race? = await Task.detached(priority: .userInitiated) { () -> Race? in
            try? RaceTrackingParser.parse(url: URL(fileURLWithPath: path))
        }.value
        guard var race = parsed else { return }
        let rec: IdentityRecord? = app.stable.store.findByName(.horse, "Rayo (demo)")
        race.isDemo = true
        race.sourceFile = "demo_race_20261029BOU03.pdf"
        race.horseRecordCode = rec?.code
        race.horseName = rec?.name ?? "Rayo (demo)"
        let runners: [RaceRunner] = race.runners
        let zakyna: String? = RaceNames.candidates(["Zakyna"], runners).first.map { runners[$0].name }
        race.ourRunnerName = zakyna
        race.notes = "DEMOSTRACIÓN: carrera real de muestra (Zakyna, Burdeos) enlazada al caballo de demostración «Rayo (demo)» solo para las capturas."
        races = [race]
        save()
        selectedRaceId = race.id
        requestReport(race)
    }
}
