import Foundation

// Port of windows/AVO.Windows.Core/Stable/Stable.cs. cuadra.json uses the SAME keys the C# JsonSerializer writes
// (PascalCase, nulls omitted) so the file is interchangeable with AVO Windows.

enum IdentityKind: Int, CaseIterable {
    case horse = 0
    case rider = 1
}

/// Errors of the Cuadra store (C# ArgumentException / KeyNotFoundException).
enum StableError: Error, LocalizedError, Equatable {
    case invalidArgument(String)
    case keyNotFound(String)

    var errorDescription: String? {
        switch self {
        case .invalidArgument(let m), .keyNotFound(let m): return m
        }
    }
}

/// A horse of the Cuadra or a rider of Jinetes. Same fields as the Android app (HorseEntity / RiderEntity).
final class IdentityRecord {
    /// Identifier written to the watch and to the NFC tag (max 23 bytes), e.g. HORSE_001.
    var code: String = ""
    var name: String = ""
    var breed: String = ""          // horses only
    var birthYear: Int? = nil       // horses only
    var notes: String = ""
    var active: Bool = true
    /// UID (hex) of the last NFC tag read or written for this record (kept from Windows/Android; the iPad cannot read tags).
    var nfcUid: String? = nil
    /// Where it came from: manual, NFC, entrenamiento.
    var origin: String = "manual"
    /// Created from a SYNTHETIC demonstration session (never mixed with real data in totals).
    var demo: Bool = false
    var created: Date = Date()

    init() {}

    init(code: String, name: String, breed: String = "", birthYear: Int? = nil, notes: String = "", active: Bool = true,
         nfcUid: String? = nil, origin: String = "manual", demo: Bool = false, created: Date = Date()) {
        self.code = code; self.name = name; self.breed = breed; self.birthYear = birthYear; self.notes = notes
        self.active = active; self.nfcUid = nfcUid; self.origin = origin; self.demo = demo; self.created = created
    }

    func copy() -> IdentityRecord {
        IdentityRecord(code: code, name: name, breed: breed, birthYear: birthYear, notes: notes, active: active,
                       nfcUid: nfcUid, origin: origin, demo: demo, created: created)
    }

    // JSON (keys as C# System.Text.Json writes them; null values omitted like WhenWritingNull)
    func json() -> [String: Any] {
        var o: [String: Any] = [
            "Code": code, "Name": name, "Breed": breed, "Notes": notes, "Active": active,
            "Origin": origin, "Demo": demo, "Created": StableJson.date(created),
        ]
        if let y = birthYear { o["BirthYear"] = y }
        if let u = nfcUid { o["NfcUid"] = u }
        return o
    }

    static func from(_ o: [String: Any]) -> IdentityRecord {
        let r = IdentityRecord()
        r.code = AvoJSON.string(o, "Code") ?? ""
        r.name = AvoJSON.string(o, "Name") ?? ""
        r.breed = AvoJSON.string(o, "Breed") ?? ""
        if let y = AvoJSON.number(o, "BirthYear") { r.birthYear = Int(y) }
        r.notes = AvoJSON.string(o, "Notes") ?? ""
        r.active = AvoJSON.bool(o, "Active") ?? true
        r.nfcUid = AvoJSON.string(o, "NfcUid")
        r.origin = AvoJSON.string(o, "Origin") ?? "manual"
        r.demo = AvoJSON.bool(o, "Demo") ?? false
        if let s = AvoJSON.string(o, "Created"), let d = StableJson.parseDate(s) { r.created = d }
        return r
    }
}

/// Horse and rider of one training, chosen by the user. Only metadata on this iPad: the .avo/.avr is never changed.
final class TrainingAssignment {
    var horseCode: String? = nil
    var riderCode: String? = nil
    var updated: Date = Date()

    init() {}

    func json() -> [String: Any] {
        var o: [String: Any] = ["Updated": StableJson.date(updated)]
        if let h = horseCode { o["HorseCode"] = h }
        if let r = riderCode { o["RiderCode"] = r }
        return o
    }

    static func from(_ o: [String: Any]) -> TrainingAssignment {
        let a = TrainingAssignment()
        a.horseCode = AvoJSON.string(o, "HorseCode")
        a.riderCode = AvoJSON.string(o, "RiderCode")
        if let s = AvoJSON.string(o, "Updated"), let d = StableJson.parseDate(s) { a.updated = d }
        return a
    }
}

/// Resolved identity of a training (what the app shows) and where it comes from.
struct ResolvedIdentity: Equatable {
    var code: String?
    var name: String
    var source: String
    var known: Bool { code != nil || name != StableStore.unknown }
}

/// JSON helpers for cuadra.json / geocercas.json (dates as C# DateTimeOffset, ISO 8601).
enum StableJson {
    static func date(_ d: Date) -> String { AvoTime.isoFrac(d) }

    /// Accepts what C# writes ("2026-11-01T09:12:33.1234567+00:00", up to 7 fractional digits) and plain ISO 8601.
    static func parseDate(_ s: String) -> Date? {
        var t = s.trimmed
        // ISO8601DateFormatter only copes reliably with 3 fractional digits: normalise the fraction
        if let r = t.range(of: "\\.[0-9]+", options: .regularExpression) {
            var frac = String(t[r].dropFirst())
            if frac.count > 3 { frac = String(frac.prefix(3)) }
            while frac.count < 3 { frac += "0" }
            t.replaceSubrange(r, with: "." + frac)
        }
        if let d = AvoTime.parseIso(t) { return d }
        return nil
    }

    /// Copies a damaged file aside ("<path>.danado-yyyyMMdd-HHmmss"), never overwriting a previous copy.
    static func keepDamaged(_ path: String) {
        let stamp = AvoTime.formatter("yyyyMMdd-HHmmss").string(from: Date())
        let target = path + ".danado-" + stamp
        if FileManager.default.fileExists(atPath: target) { return }
        try? FileManager.default.copyItem(atPath: path, toPath: target)
    }

    /// Writes to a unique .tmp next to the file and replaces it (C# File.WriteAllText(tmp) + File.Move(tmp, path, true)).
    static func writeAtomic(_ data: Data, to path: String) throws {
        AvoFiles.ensureDir((path as NSString).deletingLastPathComponent)
        let tmp = path + "." + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(8)) + ".tmp"
        try data.write(to: URL(fileURLWithPath: tmp))
        let fm = FileManager.default
        if fm.fileExists(atPath: path) {
            _ = try fm.replaceItemAt(URL(fileURLWithPath: path), withItemAt: URL(fileURLWithPath: tmp))
        } else {
            try fm.moveItem(atPath: tmp, toPath: path)
        }
        if fm.fileExists(atPath: tmp) { try? fm.removeItem(atPath: tmp) }
    }
}

/// Cuadra (horses), Jinetes (riders) and training assignments, stored as one JSON file (cuadra.json) written atomically.
/// Rules taken from the Android app: codes ≤ 23 bytes without control characters; a tag/file never overwrites a record the
/// user already has (same code); assigning only changes metadata, never the training file.
final class StableStore {
    static let unknown = "Sin identificar"

    private let path: String
    private let gate = NSLock()
    private var version: Int = 1
    private var horseList: [IdentityRecord] = []
    private var riderList: [IdentityRecord] = []
    private var assignments: [String: TrainingAssignment] = [:]

    /// C# event Changed: called after every save.
    var changed: (() -> Void)?

    init(path: String) {
        self.path = path
        guard let data = FileManager.default.contents(atPath: path) else { return }
        if !load(data) {
            // keep the damaged file for the user, start empty: never silently lose it
            StableJson.keepDamaged(path)
            AppLog.current?.warn("cuadra", "cuadra.json dañado, se conserva una copia")
            version = 1; horseList = []; riderList = []; assignments = [:]
        }
    }

    private func load(_ data: Data) -> Bool {
        var d = data
        if d.starts(with: [0xEF, 0xBB, 0xBF]) { d = d.dropFirst(3) }
        guard let any = try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed]) else { return false }
        if any is NSNull { return true }                       // "null" → empty store (C# Deserialize → null)
        guard let o = any as? [String: Any] else { return false }
        if let v = AvoJSON.number(o, "Version") { version = Int(v) }
        let sections: [(String, IdentityKind)] = [("Horses", .horse), ("Riders", .rider)]
        for (key, kind) in sections {
            guard let raw = o[key], !(raw is NSNull) else { continue }
            guard let arr = raw as? [Any] else { return false }
            var out: [IdentityRecord] = []
            for item in arr {
                guard let ro = item as? [String: Any] else { return false }
                out.append(IdentityRecord.from(ro))
            }
            if kind == .horse { horseList = out } else { riderList = out }
        }
        if let raw = o["Assignments"], !(raw is NSNull) {
            guard let dict = raw as? [String: Any] else { return false }
            for (k, v) in dict {
                guard let ao = v as? [String: Any] else { return false }
                assignments[k] = TrainingAssignment.from(ao)
            }
        }
        return true
    }

    var horses: [IdentityRecord] { gate.lock(); defer { gate.unlock() }; return horseList }
    var riders: [IdentityRecord] { gate.lock(); defer { gate.unlock() }; return riderList }
    func records(_ k: IdentityKind) -> [IdentityRecord] { k == .horse ? horses : riders }

    // must be called with the gate held
    private func list(_ k: IdentityKind) -> [IdentityRecord] { k == .horse ? horseList : riderList }
    private func setList(_ k: IdentityKind, _ l: [IdentityRecord]) { if k == .horse { horseList = l } else { riderList = l } }

    private static func sameCode(_ a: String, _ b: String) -> Bool { a.caseInsensitiveCompare(b) == .orderedSame }

    func find(_ k: IdentityKind, _ code: String?) -> IdentityRecord? {
        guard let code = code, !code.trimmed.isEmpty else { return nil }
        let c = code.trimmed
        gate.lock(); defer { gate.unlock() }
        return list(k).first { StableStore.sameCode($0.code, c) }
    }

    func findByName(_ k: IdentityKind, _ name: String?) -> IdentityRecord? {
        guard let name = name, !name.trimmed.isEmpty, name != StableStore.unknown else { return nil }
        let n = name.trimmed
        gate.lock(); defer { gate.unlock() }
        return list(k).first { $0.name.compare(n, options: [.caseInsensitive], range: nil, locale: AvoFormat.es) == .orderedSame }
    }

    /// Android rule (AvoNfc.import): not blank, ≤ 23 UTF-8 bytes, no control characters.
    static func validCode(_ code: String?) -> Bool {
        guard let code = code, !code.trimmed.isEmpty else { return false }
        if code.trimmed.utf8.count > 23 { return false }
        return !code.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }

    /// Next free HORSE_### / RIDER_### code (the format used by the watch and the Android app).
    func nextCode(_ k: IdentityKind) throws -> String {
        let prefix = k == .horse ? "HORSE_" : "RIDER_"
        gate.lock(); defer { gate.unlock() }
        let used = Set(list(k).map { $0.code.uppercased() })
        for n in 1..<100000 {
            let c = prefix + String(format: "%03d", n)
            if !used.contains(c) { return c }
        }
        throw AvoError.invalidOperation("No quedan códigos libres")
    }

    /// Adds a record. Throws if the code is invalid or already used.
    @discardableResult
    func add(_ k: IdentityKind, _ r: IdentityRecord) throws -> IdentityRecord {
        r.code = r.code.trimmed
        r.name = r.name.trimmed.isEmpty ? r.code : r.name.trimmed
        if !StableStore.validCode(r.code) {
            throw StableError.invalidArgument("Código no válido: máximo 23 caracteres, sin caracteres de control")
        }
        gate.lock()
        if list(k).contains(where: { StableStore.sameCode($0.code, r.code) }) {
            gate.unlock()
            throw StableError.invalidArgument("Ya existe \(k == .horse ? "un caballo" : "un jinete") con el código \(r.code)")
        }
        var l = list(k)
        l.append(r)
        setList(k, l)
        gate.unlock()
        try save()
        return r
    }

    /// Saves edits of an existing record (the code cannot change: it is what the watch and the tags carry).
    func update(_ k: IdentityKind, _ code: String, _ edit: (IdentityRecord) -> Void) throws {
        gate.lock()
        guard let r = list(k).first(where: { StableStore.sameCode($0.code, code) }) else {
            gate.unlock()
            throw StableError.keyNotFound(code)
        }
        let keep = r.code
        edit(r)
        r.code = keep
        if r.name.trimmed.isEmpty { r.name = keep }
        r.name = r.name.trimmed
        if let y = r.birthYear, y < 1900 || y > 2100 { r.birthYear = nil }
        gate.unlock()
        try save()
    }

    /// Deletes a record. Its trainings keep their code and show the name from the file again.
    @discardableResult
    func remove(_ k: IdentityKind, _ code: String) throws -> Bool {
        gate.lock()
        let before = list(k)
        let after = before.filter { !StableStore.sameCode($0.code, code) }
        setList(k, after)
        gate.unlock()
        let done = after.count < before.count
        if done { try save() }
        return done
    }

    /// Registers an identity read from a tag (on iPad: a pasted avohorse:// link). Like Android: if the code exists the local
    /// record is NOT overwritten (only the tag UID is remembered). Returns the record and whether it was new.
    func importTag(_ tag: AvoIdentityTag, uidHex: String?) throws -> (record: IdentityRecord, created: Bool) {
        if let existing = find(tag.kind, tag.code) {
            if let uid = uidHex, existing.nfcUid != uid {
                try update(tag.kind, existing.code) { $0.nfcUid = uid }
            }
            return (existing, false)
        }
        let r = try add(tag.kind, IdentityRecord(code: tag.code, name: tag.name, breed: tag.breed, birthYear: tag.birthYear,
                                                 notes: tag.notes, active: tag.active, nfcUid: uidHex, origin: "NFC"))
        return (r, true)
    }

    /// Adds to the Cuadra / Jinetes the horse and rider a training file carries, if not there yet (same code, or same name
    /// when the file has no code). Nothing is overwritten.
    @discardableResult
    func registerFromTraining(_ s: TrainingSession) throws -> Bool {
        var any = false
        if try registerOne(.horse, s.horseCode, StableStore.fileName(s, .horse), s.isSynthetic) { any = true }
        if try registerOne(.rider, s.riderCode, StableStore.fileName(s, .rider), s.isSynthetic) { any = true }
        return any
    }

    private func registerOne(_ k: IdentityKind, _ code: String?, _ name: String, _ demo: Bool) throws -> Bool {
        let hasName = !name.trimmed.isEmpty && name != StableStore.unknown
        if StableStore.validCode(code), let c = code?.trimmed {
            if find(k, c) != nil { return false }
            try add(k, IdentityRecord(code: c, name: hasName ? name : c, origin: "entrenamiento", demo: demo))
            return true
        }
        if !hasName || findByName(k, name) != nil { return false }
        // file with a name but no code: same rule as Android AssignHorseRider (H_/R_ + random), matched by name afterwards
        let rnd = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(16))
        let gen = (k == .horse ? "H_" : "R_") + rnd
        try add(k, IdentityRecord(code: gen, name: name, origin: "entrenamiento", demo: demo))
        return true
    }

    // ------------------------------------------------------------------ assignments
    /// AVO-ASSIGN-1: a file reassigned in another app (newer «asignacion» than this iPad's assignment) wins. Registers the
    /// horse and rider if needed. Returns true when this iPad's assignment changed.
    @discardableResult
    func adoptFileAssignment(_ s: TrainingSession) throws -> Bool {
        guard let fa = s.fileAssignment else { return false }
        let local = assignment(s.sessionId)
        if let l = local, l.updated >= fa.updated { return false }
        _ = try registerOne(.horse, fa.horseCode, fa.horseName, s.isSynthetic)
        _ = try registerOne(.rider, fa.riderCode, fa.riderName, s.isSynthetic)
        let h: String? = (find(.horse, fa.horseCode ?? "") ?? findByName(.horse, fa.horseName))?.code
        let r: String? = (find(.rider, fa.riderCode ?? "") ?? findByName(.rider, fa.riderName))?.code
        if h == nil && r == nil { return false }
        if let l = local, l.horseCode == h, l.riderCode == r { return false }
        gate.lock()
        let a = TrainingAssignment(); a.horseCode = h; a.riderCode = r; a.updated = fa.updated
        assignments[s.sessionId] = a
        gate.unlock()
        try save()
        return true
    }

    func assignment(_ sessionId: String) -> TrainingAssignment? {
        gate.lock(); defer { gate.unlock() }
        return assignments[sessionId]
    }

    /// Sets (code) or clears (nil) the horse and/or rider of a training. setHorse / setRider say which of the two is touched.
    func assign(_ sessionId: String, setHorse: Bool, horseCode: String?, setRider: Bool, riderCode: String?) throws {
        if setHorse, let h = horseCode, find(.horse, h) == nil { throw StableError.keyNotFound("Caballo no registrado: " + h) }
        if setRider, let r = riderCode, find(.rider, r) == nil { throw StableError.keyNotFound("Jinete no registrado: " + r) }
        gate.lock()
        let a = assignments[sessionId] ?? TrainingAssignment()
        if setHorse { a.horseCode = horseCode }
        if setRider { a.riderCode = riderCode }
        a.updated = Date()
        if a.horseCode == nil && a.riderCode == nil { assignments.removeValue(forKey: sessionId) } else { assignments[sessionId] = a }
        gate.unlock()
        try save()
    }

    private static func fileName(_ s: TrainingSession, _ k: IdentityKind) -> String {
        // sessions created in code (tests) may only set horse/rider
        var inFile = k == .horse ? s.horseInFile : s.riderInFile
        if inFile == unknown && !s.identityApplied { inFile = k == .horse ? s.horse : s.rider }
        return inFile
    }

    /// Who this training belongs to: 1) the user's assignment, 2) the code in the file, if registered, 3) the name in the
    /// file, if it matches a record, 4) the name/code in the file as it is, 5) «Sin identificar».
    func resolve(_ s: TrainingSession, _ k: IdentityKind) -> ResolvedIdentity {
        let fileName = StableStore.fileName(s, k)
        let fileCode: String? = k == .horse ? s.horseCode : s.riderCode
        let a = assignment(s.sessionId)
        let assigned: String? = k == .horse ? a?.horseCode : a?.riderCode
        if let assigned = assigned {
            if let ra = find(k, assigned) { return ResolvedIdentity(code: ra.code, name: ra.name, source: "asignado") }
            return ResolvedIdentity(code: assigned, name: assigned, source: "asignado (ficha eliminada)")
        }
        if let rc = find(k, fileCode) { return ResolvedIdentity(code: rc.code, name: rc.name, source: "archivo") }
        if let rn = findByName(k, fileName) { return ResolvedIdentity(code: rn.code, name: rn.name, source: "archivo (por nombre)") }
        if fileName != StableStore.unknown {
            return ResolvedIdentity(code: StableStore.validCode(fileCode) ? fileCode?.trimmed : nil, name: fileName, source: "archivo (sin ficha)")
        }
        if StableStore.validCode(fileCode), let c = fileCode?.trimmed {
            return ResolvedIdentity(code: c, name: c, source: "archivo (sin ficha)")
        }
        return ResolvedIdentity(code: nil, name: StableStore.unknown, source: "sin datos")
    }

    /// Writes the resolved names into the in-memory session (horse/rider, used by reports). The file is not touched.
    @discardableResult
    func apply(_ s: TrainingSession) -> (horse: ResolvedIdentity, rider: ResolvedIdentity) {
        if !s.identityApplied {
            if s.horseInFile == StableStore.unknown { s.horseInFile = s.horse }
            if s.riderInFile == StableStore.unknown { s.riderInFile = s.rider }
            s.identityApplied = true
        }
        let h = resolve(s, .horse)
        let r = resolve(s, .rider)
        s.horse = h.name
        s.rider = r.name
        return (h, r)
    }

    private func save() throws {
        gate.lock()
        var assign: [String: Any] = [:]
        for (k, v) in assignments { assign[k] = v.json() }
        let root: [String: Any] = [
            "Version": version,
            "Horses": horseList.map { $0.json() },
            "Riders": riderList.map { $0.json() },
            "Assignments": assign,
        ]
        gate.unlock()
        let data = (try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]))
            ?? Data("{}".utf8)
        try StableJson.writeAtomic(data, to: path)
        changed?()
    }
}

/// AVO identity tag, the NDEF URI the Android app writes (core/nfc/AvoNfc.kt):
/// avohorse://identity/horse/{code}?v=2&name=…&breed=…&birthYear=…&notes=…&active=true
/// avohorse://identity/rider/{code}?v=2&name=…&notes=…&active=true
/// Older identity-only tags have no query. The same validations as AvoNfc.import are applied.
/// On iPad there is no NFC: this is used for pasted avohorse:// links and to show the URI of a record.
struct AvoIdentityTag: Equatable {
    var kind: IdentityKind
    var code: String
    var name: String
    var breed: String
    var birthYear: Int?
    var notes: String
    var active: Bool

    static let codePattern = "^[A-Za-z0-9_-]{1,23}$"
    static func matchesCodePattern(_ s: String) -> Bool { s.matches(codePattern) }

    /// Throws AvoError.invalidData (C# FormatException) with the same Spanish messages.
    static func parse(_ uri: String) throws -> AvoIdentityTag {
        let prefix = "avohorse://identity/"
        guard uri.lowercased().hasPrefix(prefix) else { throw AvoError.invalidData("Etiqueta no AVO") }
        let rest = String(uri.dropFirst(prefix.count))
        var path = rest
        var query = ""
        if let q = rest.firstIndex(of: "?") {
            path = String(rest[rest.startIndex..<q])
            query = String(rest[rest.index(after: q)...])
        }
        if let h = query.firstIndex(of: "#") { query = String(query[query.startIndex..<h]) }
        let seg: [String] = path.split(separator: "/", omittingEmptySubsequences: true).map { String($0) }
        let kind = seg.count > 0 ? seg[0] : ""
        let code = seg.count > 1 ? unescape(seg[1]).trimmed : ""
        if kind != "horse" && kind != "rider" { throw AvoError.invalidData("Tipo de ficha desconocido") }
        if !StableStore.validCode(code) || code.utf16.count > 23 { throw AvoError.invalidData("ID no válido") }
        var p: [String: String] = [:]
        for part in query.split(separator: "&", omittingEmptySubsequences: true) {
            let s = String(part)
            var key = s
            var val = ""
            if let e = s.firstIndex(of: "=") {
                key = String(s[s.startIndex..<e])
                val = String(s[s.index(after: e)...])
            }
            let k = decode(key)
            if p[k] == nil { p[k] = decode(val) }   // first value wins (Uri.getQueryParameter)
        }
        if let v = p["v"], v != "2" { throw AvoError.invalidData("Versión NFC no compatible") }
        func f(_ key: String, _ fallback: String) -> String {
            guard let x = p[key] else { return fallback }
            return x.count > 512 ? String(x.prefix(512)) : x
        }
        var name = f("name", code)
        if name.trimmed.isEmpty { name = code }
        var birth: Int? = nil
        if let y = Int(f("birthYear", "").trimmed), y >= 1900 && y <= 2100 { birth = y }
        let horse = kind == "horse"
        return AvoIdentityTag(kind: horse ? .horse : .rider, code: code, name: name, breed: horse ? f("breed", "") : "",
                              birthYear: horse ? birth : nil, notes: f("notes", ""), active: f("active", "true") != "false")
    }

    private static func unescape(_ s: String) -> String { s.removingPercentEncoding ?? s }
    // Android Uri.getQueryParameter decodes '+' as a space (since Jelly Bean)
    private static func decode(_ s: String) -> String { unescape(s.replacingOccurrences(of: "+", with: " ")) }

    /// Same URI as AvoNfc.horse()/rider() (Uri.encode / appendQueryParameter percent-encoding, spaces as %20).
    static func buildUri(_ k: IdentityKind, _ r: IdentityRecord) -> String {
        var sb = "avohorse://identity/" + (k == .horse ? "horse/" : "rider/") + enc(r.code)
        sb += "?v=2&name=" + enc(r.name)
        if k == .horse {
            sb += "&breed=" + enc(r.breed) + "&birthYear=" + (r.birthYear.map { String($0) } ?? "")
        }
        sb += "&notes=" + enc(r.notes) + "&active=" + (r.active ? "true" : "false")
        return sb
    }

    // android.net.Uri.encode keeps letters, digits and _-!.~'()* ; everything else as UTF-8 %XX (upper case)
    private static func enc(_ s: String) -> String {
        let keep: [UInt8] = Array("_-!.~'()*".utf8)
        var out = ""
        for b in s.utf8 {
            let isAlnum = (b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122)
            if b < 0x80 && (isAlnum || keep.contains(b)) {
                out.unicodeScalars.append(Unicode.Scalar(b))
            } else {
                out += String(format: "%%%02X", Int(b))
            }
        }
        return out
    }
}
