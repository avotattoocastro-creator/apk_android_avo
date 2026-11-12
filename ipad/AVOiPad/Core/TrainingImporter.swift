import Foundation
import CryptoKit

/// Imports .avr (AVORAW1) files and .avo (AVO-TRAINING-1 ZIP) packages with the same checks as the Windows app.
enum TrainingImporter {
    private static let maxCompressedBytes: Int64 = 100 * 1024 * 1024
    private static let maxSegmentBytes: Int64 = 50 * 1024 * 1024

    /// Default folder for the verified RAW copies extracted from .avo packages (originals are never modified).
    static var defaultRawCacheDir: String { AvoFiles.join(AppPaths.defaultRoot, "raw") }

    private static func keepFileIdentity(_ s: TrainingSession) -> TrainingSession {
        s.horseInFile = s.horse
        s.riderInFile = s.rider
        return s
    }

    private static func hasExt(_ path: String, _ ext: String) -> Bool {
        ("." + (path as NSString).pathExtension).lowercased() == ext && !(path as NSString).pathExtension.isEmpty
    }

    static func importFile(_ path: String, rawCacheDir: String? = nil) throws -> TrainingSession {
        try `import`(path, rawCacheDir: rawCacheDir)
    }

    static func `import`(_ path: String, rawCacheDir: String? = nil) throws -> TrainingSession {
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: path, isDirectory: &isDir) || isDir.boolValue {
            throw AvoError.notFound("No existe el entrenamiento")
        }
        if AvoFiles.size(path) > maxCompressedBytes { throw AvoError.invalidData("Archivo de más de 100 MB") }
        let result = TrainingSession()
        result.sourceName = AvoFiles.fileName(path)
        if hasExt(path, ".avr") {
            guard let data = FileManager.default.contents(atPath: path) else { throw AvoError.notFound("No existe el entrenamiento") }
            result.segments.append(try RawReader.scan([UInt8](data), session: result, name: AvoFiles.fileName(path), segmentIndex: 0))
            result.hasRawTelemetry = true
            result.rawSegmentPaths.append(URL(fileURLWithPath: path).standardizedFileURL.path)
            result.integrity = result.segments.allSatisfy({ !$0.truncated }) ? "CRC válido" : "RAW truncado (parcial)"
            return keepFileIdentity(result)
        }
        if !hasExt(path, ".avo") { throw AvoError.invalidData("Formato no compatible: se esperan archivos .avo o .avr") }
        let zip = try ZipReader(path: path)
        if zip.entries.count < 2 || zip.entries.count > 400 { throw AvoError.invalidData("Cantidad de entradas ZIP incorrecta") }
        guard let manifestEntry = zip.entry("manifest.json") else { throw AvoError.invalidData("Falta manifest.json") }
        if manifestEntry.length < 1 || manifestEntry.length > 16_384 { throw AvoError.invalidData("Tamaño del manifiesto inválido") }
        var manifestBytes = try zip.read(manifestEntry, max: 16_384)
        if manifestBytes.count >= 3 && manifestBytes[0] == 0xEF && manifestBytes[1] == 0xBB && manifestBytes[2] == 0xBF {
            manifestBytes.removeFirst(3)
        }
        guard let parsed = try? JSONSerialization.jsonObject(with: Data(manifestBytes), options: []),
              let root = parsed as? [String: Any] else {
            throw AvoError.invalidData("manifest.json no es un JSON válido")
        }
        if AvoJSON.string(root, "format") != "AVO-TRAINING-1" { throw AvoError.invalidData("Formato AVO no compatible") }
        guard let sessionId = AvoJSON.string(root, "sessionId") else { throw AvoError.invalidData("Falta sessionId") }
        result.sessionId = sessionId
        result.declaredCanonicalSha256 = AvoJSON.string(root, "sha256")
        if let whole = result.declaredCanonicalSha256, AvoHex.isSha256(whole) { result.sha256 = whole.lowercased() }
        let idLength = sessionId.utf16.count
        if idLength < 3 || idLength > 128 || sessionId.contains("/") || sessionId.contains("\\") {
            throw AvoError.invalidData("ID de sesión inválido")
        }
        if let horse = AvoJSON.string(root, "horseName"), !horse.isEmpty { result.horse = horse } else { result.horse = "Sin identificar" }
        if let rider = AvoJSON.string(root, "riderName"), !rider.isEmpty { result.rider = rider } else { result.rider = "Sin identificar" }
        if let hc = AvoJSON.string(root, "horseCode"), !hc.isEmpty { result.horseCode = hc.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let rc = AvoJSON.string(root, "riderCode"), !rc.isEmpty { result.riderCode = rc.trimmingCharacters(in: .whitespacesAndNewlines) }
        result.declaredDistanceM = AvoJSON.number(root, "distanceM")
        result.declaredDurationS = AvoJSON.number(root, "durationS")
        result.declaredMaxSpeedMs = AvoJSON.number(root, "maxSpeedMs")
        if let ts = AvoJSON.number(root, "startRtcMs"), ts > 946_684_800_000, ts < 4_102_444_800_000 {
            result.startedAt = AvoTime.fromUnixMs(Double(Int64(ts)))
        }
        guard let hashObject = AvoJSON.dict(root, "segmentHashes") else {
            throw AvoError.invalidData("Faltan las huellas SHA-256 por segmento")
        }
        var hashes: [String: String] = [:]
        for (k, v) in hashObject { hashes[k] = (v as? String) ?? "" }
        var declaredSegments = -1
        if let d = AvoJSON.number(root, "segments"), d > -2_147_483_649, d < 2_147_483_648 { declaredSegments = Int(d) }
        let files: [ZipEntry] = zip.entries
            .filter { $0.fullName != "manifest.json" }
            .sorted { (a: ZipEntry, b: ZipEntry) -> Bool in a.fullName.utf16.lexicographicallyPrecedes(b.fullName.utf16) }
        if files.isEmpty || declaredSegments != files.count || hashes.count != files.count {
            throw AvoError.invalidData("El paquete tiene segmentos ausentes, duplicados o extra")
        }
        var total: Int64 = 0
        var idx = 0
        for entry in files {
            let full = entry.fullName
            let name = full.hasPrefix("segments/") ? String(full.dropFirst(9)) : ""
            if !full.hasPrefix("segments/") || !isSafeSegmentName(name) || entry.length < 1 || entry.length > maxSegmentBytes {
                throw AvoError.invalidData("Ruta o tamaño del segmento ZIP incorrecto")
            }
            guard let expected = hashes[name], AvoHex.isSha256(expected) else {
                throw AvoError.invalidData("No existe SHA-256 válido para \(name)")
            }
            total += entry.length
            if total > maxCompressedBytes { throw AvoError.invalidData("Tamaño descomprimido excesivo") }
            let data = try zip.read(entry, max: maxSegmentBytes)
            let actual = AvoHex.sha256(data)
            if actual != expected.lowercased() { throw AvoError.invalidData("Hash de \(name) no coincide") }
            if name.lowercased().hasSuffix(".avr") {
                result.segments.append(try RawReader.scan(data, session: result, name: name, segmentIndex: idx))
                result.hasRawTelemetry = true
                // verified copy for the analysis engine (name already restricted to [A-Za-z0-9_.-])
                let dir = AvoFiles.join(rawCacheDir ?? defaultRawCacheDir, sanitizedDirName(result.sessionId))
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                let copy = AvoFiles.join(dir, name)
                var needsWrite = true
                if let existing = FileManager.default.contents(atPath: copy), AvoHex.sha256(existing) == expected.lowercased() {
                    needsWrite = false
                }
                if needsWrite { try Data(data).write(to: URL(fileURLWithPath: copy), options: .atomic) }
                result.rawSegmentPaths.append(copy)
            } else {
                result.segments.append(SegmentSummary(name: name, index: idx, validBytes: Int64(data.count), blocks: 0, records: 0,
                                                      cleanClose: false, truncated: false, badRecords: 0))
            }
            idx += 1
        }
        result.integrity = result.segments.contains(where: { $0.truncated }) ? "SHA válido · RAW parcial" : "SHA-256 verificado por segmento"
        return keepFileIdentity(result)
    }

    /// ^[A-Za-z0-9_.-]{1,120}$ (checked character by character, no regex corner cases).
    static func isSafeSegmentName(_ name: String) -> Bool {
        let u = Array(name.utf8)
        if u.isEmpty || u.count > 120 { return false }
        for c in u {
            let ok = (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 46 || c == 45
            if !ok { return false }
        }
        return true
    }

    /// C#: string.Concat(id.Select(ch => char.IsLetterOrDigit(ch) || ch is '-' or '_' ? ch : '_')) over UTF-16 units.
    static func sanitizedDirName(_ id: String) -> String {
        var out = ""
        for scalar in id.unicodeScalars {
            if scalar.value > 0xFFFF { out += "__"; continue }   // surrogate pair: two non-letter UTF-16 units in C#
            if scalar == "-" || scalar == "_" { out.unicodeScalars.append(scalar); continue }
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .decimalNumber:
                out.unicodeScalars.append(scalar)
            default:
                out += "_"
            }
        }
        return out
    }
}
