import Foundation

/// «Exportar a AVO Horse»: copies trainings to Archivos › En mi iPad › AVO Horse › Exportados (the app's Documents
/// folder, visible in Files), to send them or move them to another iPad, a PC (AVO Windows) or Android. The file
/// exported is the ORIGINAL the app verified on import (the library copy, same SHA-256: .avo package or .avr RAW), so
/// every AVO app reads it exactly as this one. Names: AVO_<yyyyMMdd_HHmm>_<horse>.<ext> (suffix when two collide).
extension AppModel {
    /// Documents/Exportados (created on demand).
    var exportDir: String {
        let docs: String = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path
            ?? AvoFiles.join(paths.root, "Documents")
        return AvoFiles.join(docs, "Exportados")
    }

    /// The verified original of a training: its library copy, otherwise the file it was opened from.
    func exportSource(_ item: SessionItem) -> String? {
        if let sha = item.session.fileSha256?.lowercased(),
           let e = library.entries.first(where: { $0.sha256.lowercased() == sha && AvoFiles.exists($0.storedPath) }) {
            return e.storedPath
        }
        if let src = item.session.sourcePath, AvoFiles.exists(src) { return src }
        if item.session.rawSegmentPaths.count == 1, AvoFiles.exists(item.session.rawSegmentPaths[0]) { return item.session.rawSegmentPaths[0] }
        return nil
    }

    static func exportName(_ item: SessionItem, ext: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "yyyyMMdd_HHmm"
        let when: String = item.start.map { f.string(from: $0) } ?? TrainingImporter.sanitizedDirName(item.id)
        var horse: String = TrainingImporter.sanitizedDirName(item.horse)
        if horse.count > 32 { horse = String(horse.prefix(32)) }
        return "AVO_\(when)_\(horse)" + ext
    }

    /// Copies the trainings; returns (exported, already there, failures).
    @MainActor
    func exportTrainings(_ items: [SessionItem]) async -> (copied: Int, existing: Int, failed: [String]) {
        let dir: String = exportDir
        var jobs: [(src: String, name: String, label: String)] = []
        var failed: [String] = []
        for it in items {
            guard let src = exportSource(it) else { failed.append("\(it.dateTimeText) · \(it.horse): sin archivo original"); continue }
            jobs.append((src, AppModel.exportName(it, ext: AvoFiles.ext(src)), "\(it.dateTimeText) · \(it.horse)"))
        }
        busy = true
        status = "Exportando \(jobs.count) entrenamiento(s) a AVO Horse › Exportados…"
        let result: (Int, Int, [String]) = await Task.detached(priority: .userInitiated) { () -> (Int, Int, [String]) in
            let fm = FileManager.default
            var copied: Int = 0, existing: Int = 0
            var errs: [String] = []
            do { try fm.createDirectory(atPath: dir, withIntermediateDirectories: true) } catch {
                return (0, 0, ["No se pudo crear la carpeta Exportados: " + error.localizedDescription])
            }
            for j in jobs {
                let base: String = (j.name as NSString).deletingPathExtension
                let ext: String = (j.name as NSString).pathExtension
                let srcSize: Int64 = AvoFiles.size(j.src)
                var target: String = AvoFiles.join(dir, j.name)
                var k: Int = 2
                var skip: Bool = false
                while fm.fileExists(atPath: target) {
                    // the same file already exported: nothing to do
                    if AvoFiles.size(target) == srcSize,
                       let a = try? TrainingLibrary.fileSha256(target), let b = try? TrainingLibrary.fileSha256(j.src), a == b {
                        skip = true
                        break
                    }
                    target = AvoFiles.join(dir, "\(base)_\(k).\(ext)")
                    k += 1
                }
                if skip { existing += 1; continue }
                do {
                    try fm.copyItem(atPath: j.src, toPath: target)
                    copied += 1
                } catch {
                    errs.append(j.label + ": " + error.localizedDescription)
                }
            }
            return (copied, existing, errs)
        }.value
        busy = false
        failed.append(contentsOf: result.2)
        status = "Exportación: \(result.0) copiados, \(result.1) ya estaban, \(failed.count) con error · Archivos › En mi iPad › AVO Horse › Exportados"
        log.info("exportar", "Entrenamientos exportados", ["copiados": String(result.0), "existentes": String(result.1), "errores": String(failed.count)])
        return (result.0, result.1, failed)
    }

    /// Exports and tells the user where the files are.
    @MainActor
    func exportTrainingsAndReport(_ items: [SessionItem]) async {
        if items.isEmpty { show("Exportar", "No hay entrenamientos que exportar."); return }
        let r = await exportTrainings(items)
        var msg: String = "\(r.copied) entrenamiento(s) copiados"
        if r.existing > 0 { msg += ", \(r.existing) ya estaban exportados" }
        msg += ".\n\nEstán en Archivos › En mi iPad › AVO Horse › Exportados: desde ahí puedes enviarlos por AirDrop, correo o WhatsApp, o copiarlos a otro iPad, al PC (AVO Windows) o a Android. Son los archivos originales verificados (.avo / .avr)."
        if !r.failed.isEmpty { msg += "\n\nNo exportados:\n" + r.failed.prefix(8).joined(separator: "\n") }
        show("Exportar a AVO Horse", msg, error: !r.failed.isEmpty && r.copied == 0)
    }
}
