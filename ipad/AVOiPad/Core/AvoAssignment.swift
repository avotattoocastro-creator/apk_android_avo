import Foundation
import CryptoKit

/// Horse and rider assigned to a training after recording (AVO-ASSIGN-1, docs/ASIGNACION_CABALLO.md).
struct AvoAssignmentData: Equatable {
    var horseCode: String?
    var horseName: String
    var riderCode: String?
    var riderName: String
    var updated: Date
    var app: String
}

/// AVO-ASSIGN-1: the manifest of the .avo package is the source of truth for the identity of a training.
/// Reassigning rewrites ONLY manifest.json; the RAW segments are copied byte for byte (their SHA-256 never changes).
/// Same rules as windows/AVO.Windows.Core/AvoAssignment.cs and the Android core (share/AvoAssignment.kt).
enum AvoAssignment {
    /// The «asignacion» block of a manifest, or nil if the file predates AVO-ASSIGN-1.
    static func read(_ root: [String: Any]) -> AvoAssignmentData? {
        guard let a = AvoJSON.dict(root, "asignacion") else { return nil }
        func s(_ k: String) -> String? {
            guard let v = AvoJSON.string(a, k)?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
            return v
        }
        let hc = s("horseCode"), hn = s("horseName"), rc = s("riderCode"), rn = s("riderName")
        if hc == nil && hn == nil && rc == nil && rn == nil { return nil }
        let when = s("actualizadoUtc").flatMap { AvoTime.parseIso($0) } ?? Date(timeIntervalSince1970: 0)
        return AvoAssignmentData(horseCode: hc, horseName: hn ?? hc ?? "", riderCode: rc, riderName: rn ?? rc ?? "",
                                 updated: when, app: s("app") ?? "")
    }

    /// Engine option fragment ("asignacion":{…}) for avo_eq_analyse_ex, or nil when nothing is known.
    static func engineOption(horseCode: String?, horseName: String?, riderCode: String?, riderName: String?) -> String? {
        var o: [(String, String)] = []
        func put(_ k: String, _ v: String?) {
            guard let t = v?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty, t != StableStore.unknown else { return }
            o.append((k, t))
        }
        put("horseCode", horseCode); put("horseName", horseName); put("riderCode", riderCode); put("riderName", riderName)
        if o.isEmpty { return nil }
        let body = o.map { "\"\($0.0)\":" + jsonString($0.1) }.joined(separator: ",")
        return "\"asignacion\":{" + body + "}"
    }

    /// horse_name / rider_name of the AVORAW1 header of a segment (offsets 124 and 152, 24 bytes each).
    static func rawHeaderIdentity(_ segmentPath: String) -> (horse: String?, rider: String?) {
        guard let h = FileHandle(forReadingAtPath: segmentPath) else { return (nil, nil) }
        defer { try? h.close() }
        guard let d = try? h.read(upToCount: 176), d.count >= 176 else { return (nil, nil) }
        func field(_ off: Int) -> String? {
            let bytes = [UInt8](d[off..<(off + 24)]).prefix { $0 != 0 }
            let s = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? nil : s
        }
        return (field(124), field(152))
    }

    /// Rewrites the identity in the manifest of `avoPath` (top-level fields + «asignacion», keeping the RAW values in
    /// asignacion.raw). The segments are extracted, checked against the manifest hashes and packed again by
    /// AvoPackageWriter (written to a .tmp and moved over the original): their bytes never change.
    static func write(_ avoPath: String, _ a: AvoAssignmentData, rawHorse: String?, rawRider: String?) throws {
        let zip = try ZipReader(path: avoPath)
        guard let m = zip.entry("manifest.json") else { throw AvoError.invalidData("Falta manifest.json") }
        var mb = try zip.read(m, max: 16_384)
        if mb.count >= 3 && mb[0] == 0xEF && mb[1] == 0xBB && mb[2] == 0xBF { mb.removeFirst(3) }
        guard var manifest = AvoJSON.object(Data(mb)), AvoJSON.string(manifest, "format") == "AVO-TRAINING-1",
              let sessionId = AvoJSON.string(manifest, "sessionId") else { throw AvoError.invalidData("Manifiesto no compatible") }
        let declared = AvoJSON.dict(manifest, "segmentHashes") ?? [:]
        let tmpDir = AvoFiles.join(NSTemporaryDirectory(), "avo_asignacion_" + UUID().uuidString)
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }
        var segs: [String] = []
        for e in zip.entries where e.fullName != "manifest.json" {
            let name = AvoFiles.fileName(e.fullName)
            let bytes = try zip.read(e, max: 50 * 1024 * 1024)
            let sha = AvoHex.lower(SHA256.hash(data: Data(bytes)))
            if let want = declared[name] as? String, want.lowercased() != sha { throw AvoError.invalidData("\(name) no coincide con su huella") }
            let p = AvoFiles.join(tmpDir, name)
            FileManager.default.createFile(atPath: p, contents: Data(bytes))
            segs.append(p)
        }
        // the RAW values survive every reassignment: taken from an earlier block if there is one
        let oldRaw = AvoJSON.dict(manifest, "asignacion").flatMap { AvoJSON.dict($0, "raw") }
        let keepHorse = (oldRaw?["horseCode"] as? String) ?? rawHorse, keepRider = (oldRaw?["riderCode"] as? String) ?? rawRider
        func v(_ s: String?) -> Any { if let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }; return NSNull() }
        manifest["horseCode"] = a.horseCode ?? ""; manifest["horseName"] = a.horseName
        manifest["riderCode"] = a.riderCode ?? ""; manifest["riderName"] = a.riderName
        manifest["asignacion"] = [
            "version": 1, "horseCode": v(a.horseCode), "horseName": v(a.horseName), "riderCode": v(a.riderCode), "riderName": v(a.riderName),
            "actualizadoUtc": AvoTime.iso(a.updated), "app": a.app,
            "raw": ["horseCode": v(keepHorse), "riderCode": v(keepRider)],
        ] as [String: Any]
        let meta = AvoPackageWriter.Meta(sessionId: sessionId, sha256: AvoJSON.string(manifest, "sha256") ?? "",
                                         watchDevice: AvoJSON.string(manifest, "watchDevice") ?? "", watchFirmware: AvoJSON.string(manifest, "watchFirmware") ?? "",
                                         startRtcMs: Int64(AvoJSON.number(manifest, "startRtcMs") ?? 0), activeMs: Int64(AvoJSON.number(manifest, "activeMs") ?? 0))
        try AvoPackageWriter.write(target: avoPath, meta: meta, segments: segs, manifestBase: manifest)
    }

    static func jsonString(_ s: String) -> String {
        let d = (try? JSONSerialization.data(withJSONObject: [s], options: [.withoutEscapingSlashes])) ?? Data("[\"\"]".utf8)
        let t = String(decoding: d, as: UTF8.self)
        return String(t.dropFirst().dropLast())
    }
}
