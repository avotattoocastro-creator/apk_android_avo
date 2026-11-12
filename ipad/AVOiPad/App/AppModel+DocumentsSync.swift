import Foundation

/// Automatic copy to «Archivos › En mi iPad › AVO Horse» (trainer's request 09/11/2026): the app checks its folders and
/// copies everything it keeps inside (not visible in Files) to its own folder, one subfolder per horse:
///
///   AVO Horse/Entrenamientos/<Caballo>/     verified originals (.avo / .avr), AVO_<yyyyMMdd_HHmm>_<caballo>.<ext>
///   AVO Horse/Informes/<Caballo>/           PDF / HTML / CSV / GPX / JSON written by «Informes», «Informe PDF» del tramo…
///   AVO Horse/Informes IA/<Caballo>/        «Informe IA» of the Asistente IA
///   AVO Horse/Carreras/<Caballo>/           tracking PDF of each race (and the race videos analysed, in «Vídeos»)
///   AVO Horse/Copia de seguridad/           data of the app (Cuadra, carreras, tramos, informes IA, notas…)
///   AVO Horse/Exportados/                   «Exportar a AVO Horse» (unchanged)
///
/// Runs at launch, every 2 minutes, when the app goes to the background and right after a report is written. It only adds
/// or updates files: it never deletes anything in AVO Horse.
enum DocumentsSync {
    static let folders: [String] = ["Entrenamientos", "Informes", "Informes IA", "Carreras", "Copia de seguridad", "Exportados"]
    static var running: Bool = false
    static var pending: Task<Void, Never>? = nil
    static var timer: Timer? = nil

    struct Job {
        var src: String
        var dst: String
        /// true = same name is the same document (reports, backups): replaced when it changes.
        /// false = training originals: never replaced, a «_2» name is used when a different file has the name.
        var replace: Bool
    }

    struct Result {
        var copied: Int = 0
        var updated: Int = 0
        var unchanged: Int = 0
        var failed: [String] = []
    }

    static var documents: String {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? NSTemporaryDirectory()
    }

    /// «POWER GOLD», from «POWER GOLD» or «POWER_GOLD».
    static func horseFolder(_ name: String?) -> String {
        let c: String = ExportNaming.clean(name ?? "").replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        return c.isEmpty ? "Sin caballo" : String(c.prefix(40))
    }

    /// Horse of a file named by ExportNaming («POWER_GOLD_2026-11-08_1138_Completo.pdf»); «Otros» for older names.
    static func horseOfFile(_ name: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"^(.+?)_\d{4}-\d{2}-\d{2}_\d{4}_"#),
              let m = re.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let r = Range(m.range(at: 1), in: name) else { return "Otros" }
        return horseFolder(String(name[r]))
    }

    /// Copies the jobs (background thread).
    static func run(_ jobs: [Job], root: String) -> Result {
        let fm = FileManager.default
        var res = Result()
        for f in folders { try? fm.createDirectory(atPath: AvoFiles.join(root, f), withIntermediateDirectories: true) }
        for j in jobs {
            guard fm.fileExists(atPath: j.src) else { continue }
            let dir: String = (j.dst as NSString).deletingLastPathComponent
            do {
                try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
                let srcSize: Int64 = AvoFiles.size(j.src)
                let srcDate: Date = modified(j.src)
                if fm.fileExists(atPath: j.dst) {
                    if j.replace {
                        if AvoFiles.size(j.dst) == srcSize && modified(j.dst) >= srcDate { res.unchanged += 1; continue }
                        try? fm.removeItem(atPath: j.dst)
                        try fm.copyItem(atPath: j.src, toPath: j.dst)
                        res.updated += 1
                        continue
                    }
                    if AvoFiles.size(j.dst) == srcSize { res.unchanged += 1; continue }
                    // a different training with the same name: first free «_2», «_3»… unless it is already there
                    let base: String = (j.dst as NSString).deletingPathExtension
                    let ext: String = (j.dst as NSString).pathExtension
                    var k: Int = 2
                    var target: String = base + "_\(k)." + ext
                    var done: Bool = false
                    while fm.fileExists(atPath: target) {
                        if AvoFiles.size(target) == srcSize { done = true; break }
                        k += 1
                        target = base + "_\(k)." + ext
                    }
                    if done { res.unchanged += 1; continue }
                    try fm.copyItem(atPath: j.src, toPath: target)
                    res.copied += 1
                    continue
                }
                try fm.copyItem(atPath: j.src, toPath: j.dst)
                res.copied += 1
            } catch {
                res.failed.append((j.src as NSString).lastPathComponent + ": " + error.localizedDescription)
            }
        }
        return res
    }

    static func modified(_ p: String) -> Date {
        ((try? FileManager.default.attributesOfItem(atPath: p))?[.modificationDate] as? Date) ?? .distantPast
    }

    static func files(_ dir: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: dir))?.filter { !$0.hasPrefix(".") }.sorted() ?? []
    }
}

extension AppModel {
    /// Starts the automatic copy (launch) and the 2-minute timer.
    func startDocumentsSync() {
        if captureMode { return }
        scheduleDocumentsSync(delay: 4)
        DocumentsSync.timer?.invalidate()
        let t = Timer(timeInterval: 120, repeats: true) { [weak self] _ in self?.scheduleDocumentsSync(delay: 0) }
        RunLoop.main.add(t, forMode: .common)
        DocumentsSync.timer = t
    }

    /// Copy soon (several calls in a row make one copy).
    func scheduleDocumentsSync(delay: Double = 1.5) {
        if captureMode { return }
        DocumentsSync.pending?.cancel()
        DocumentsSync.pending = Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            if Task.isCancelled { return }
            _ = await self?.syncDocuments()
        }
    }

    /// What has to be in AVO Horse (built on the main thread from the loaded data).
    private func documentsJobs(_ root: String) -> [DocumentsSync.Job] {
        var jobs: [DocumentsSync.Job] = []
        // trainings: verified originals, by horse
        for s in sessions where !s.isSynthetic {
            guard let src = exportSource(s) else { continue }
            let dst: String = AvoFiles.join(AvoFiles.join(AvoFiles.join(root, "Entrenamientos"), DocumentsSync.horseFolder(s.horse)),
                                            AppModel.exportName(s, ext: AvoFiles.ext(src)))
            jobs.append(DocumentsSync.Job(src: src, dst: dst, replace: false))
        }
        // reports and AI reports
        let exp: String = AvoFiles.join(paths.root, "exportaciones")
        for name in DocumentsSync.files(exp) {
            let ai: Bool = name.contains("_Informe_IA_")
            let dir: String = AvoFiles.join(AvoFiles.join(root, ai ? "Informes IA" : "Informes"), DocumentsSync.horseOfFile(name))
            jobs.append(DocumentsSync.Job(src: AvoFiles.join(exp, name), dst: AvoFiles.join(dir, name), replace: true))
        }
        // races: tracking PDF and analysed videos, by horse
        let carreras: String = AvoFiles.join(root, "Carreras")
        for r in races.races where !r.isDemo && !r.sourceFile.isEmpty {
            let horse: String = DocumentsSync.horseFolder(r.horseName ?? r.ourRunnerName)
            jobs.append(DocumentsSync.Job(src: AvoFiles.join(races.pdfDir, r.sourceFile),
                                          dst: AvoFiles.join(AvoFiles.join(carreras, horse), r.sourceFile), replace: true))
        }
        let vids: String = AvoFiles.join(paths.root, "carreras_video")
        for name in DocumentsSync.files(vids) {
            jobs.append(DocumentsSync.Job(src: AvoFiles.join(vids, name), dst: AvoFiles.join(AvoFiles.join(carreras, "Vídeos"), name), replace: true))
        }
        // backup of the app data
        let backup: String = AvoFiles.join(root, "Copia de seguridad")
        for name in DocumentsSync.files(paths.root) where name.hasSuffix(".json") {
            jobs.append(DocumentsSync.Job(src: AvoFiles.join(paths.root, name), dst: AvoFiles.join(AvoFiles.join(backup, "Datos"), name), replace: true))
        }
        for name in DocumentsSync.files(paths.notes) {
            jobs.append(DocumentsSync.Job(src: AvoFiles.join(paths.notes, name), dst: AvoFiles.join(AvoFiles.join(backup, "Notas"), name), replace: true))
        }
        return jobs
    }

    /// Checks the folders of AVO Horse and copies what is missing or changed. Returns nil when a copy is already running.
    @MainActor
    @discardableResult
    func syncDocuments() async -> DocumentsSync.Result? {
        if DocumentsSync.running { return nil }
        DocumentsSync.running = true
        defer { DocumentsSync.running = false }
        let root: String = DocumentsSync.documents
        let jobs: [DocumentsSync.Job] = documentsJobs(root)
        let res: DocumentsSync.Result = await Task.detached(priority: .utility) { () -> DocumentsSync.Result in
            DocumentsSync.run(jobs, root: root)
        }.value
        if res.copied + res.updated > 0 || !res.failed.isEmpty {
            var t: String = "Copia en AVO Horse: \(res.copied) nuevos, \(res.updated) actualizados"
            if !res.failed.isEmpty { t += ", \(res.failed.count) con error" }
            status = t + " · Archivos › En mi iPad › AVO Horse"
            log.info("copia", "Copia automática en AVO Horse",
                     ["nuevos": String(res.copied), "actualizados": String(res.updated), "errores": String(res.failed.count)])
        }
        return res
    }

    /// «Copiar todo a AVO Horse» (button): copies now and tells where.
    @MainActor
    func syncDocumentsAndReport() async {
        while DocumentsSync.running { try? await Task.sleep(nanoseconds: 200_000_000) }
        guard let r = await syncDocuments() else { return }
        var msg: String = "\(r.copied) archivos nuevos, \(r.updated) actualizados, \(r.unchanged) ya estaban al día."
        msg += "\n\nArchivos › En mi iPad › AVO Horse:\n• Entrenamientos/<caballo>\n• Informes/<caballo>\n• Informes IA/<caballo>\n• Carreras/<caballo>\n• Copia de seguridad\n\nLa app lo copia sola al abrirse, cada 2 minutos, al salir y cada vez que crea un informe. Nunca borra nada de esa carpeta."
        if !r.failed.isEmpty { msg += "\n\nCon error:\n" + r.failed.prefix(6).joined(separator: "\n") }
        show("Copia en AVO Horse", msg, error: !r.failed.isEmpty)
    }
}
