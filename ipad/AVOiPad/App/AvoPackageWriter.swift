import Foundation
import CryptoKit

/// Writes an AVO-TRAINING-1 package (.avo) from the RAW segments downloaded from the watch, with the same layout as the
/// Windows USB download (windows/AVO.Windows.Core/ChestUsb.cs WritePackage) and the Android app's .avo:
///   manifest.json  {format, sessionId, horseName, riderName, sha256, watchDevice, watchFirmware, source, startRtcMs,
///                   activeMs, segments, segmentHashes {P001.avr: sha256, …}}
///   segments/P001.avr, segments/P002.avr, …
/// ZIP entries are STORED (method 0) with the correct CRC-32 (ZipCRC32), so TrainingImporter/ZipReader validate them.
/// Segments are copied in 64 KB blocks (never the whole file in memory); the package is written to a .tmp and moved.
enum AvoPackageWriter {
    struct Meta {
        var sessionId: String
        /// SHA-256 (lower-case hex) of the concatenated segments, as verified against the watch.
        var sha256: String
        var watchDevice: String
        var watchFirmware: String
        var startRtcMs: Int64
        var activeMs: Int64
        var source: String = "wifi-ipad"
        var horseCode: String = ""
        var horseName: String = ""
        var riderCode: String = ""
        var riderName: String = ""
    }

    /// Same name as Windows WatchLibrary.PackageName: AVO_{id}_{device}.avo
    static func packageName(device: String, id: String) -> String {
        let safeId: String = TrainingImporter.sanitizedDirName(id)
        let dev: String = TrainingImporter.sanitizedDirName(device.lowercased())
        return "AVO_\(safeId)_\(dev).avo"
    }

    private struct Entry {
        var name: [UInt8]
        var crc: UInt32
        var size: UInt32
        var offset: UInt32
    }

    private final class Out {
        let h: FileHandle
        var pos: UInt64 = 0
        init(_ h: FileHandle) { self.h = h }
        func write(_ b: [UInt8]) throws {
            try h.write(contentsOf: Data(b))
            pos += UInt64(b.count)
        }
        func write(_ d: Data) throws {
            try h.write(contentsOf: d)
            pos += UInt64(d.count)
        }
    }


    /// MS-DOS time and date of `d` (local time, as ZIP tools expect).
    private static func dosTimeDate(_ d: Date) -> (time: Int, date: Int) {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
        let y = max(1980, c.year ?? 1980)
        let time = ((c.hour ?? 0) << 11) | ((c.minute ?? 0) << 5) | ((c.second ?? 0) / 2)
        let date = ((y - 1980) << 9) | ((c.month ?? 1) << 5) | (c.day ?? 1)
        return (time, date)
    }

    /// CRC-32, SHA-256 and size of a file, streamed.
    private static func scan(_ path: String) throws -> (crc: UInt32, sha: String, size: Int64) {
        guard let h = FileHandle(forReadingAtPath: path) else { throw AvoError.notFound("No se puede leer \(AvoFiles.fileName(path))") }
        defer { try? h.close() }
        var crc: UInt32 = 0xFFFF_FFFF
        var sha = SHA256()
        var size: Int64 = 0
        while true {
            let d: Data = try h.read(upToCount: 65_536) ?? Data()
            if d.isEmpty { break }
            size += Int64(d.count)
            sha.update(data: d)
            let bytes: [UInt8] = [UInt8](d)
            crc = bytes.withUnsafeBufferPointer { (b: UnsafeBufferPointer<UInt8>) -> UInt32 in ZipCRC32.update(crc, b) }
        }
        return (crc ^ 0xFFFF_FFFF, AvoHex.lower(sha.finalize()), size)
    }

    /// The manifest exactly as TrainingImporter reads it.
    static func manifest(_ meta: Meta, hashes: [String: String]) -> [String: Any] {
        return [
            "format": "AVO-TRAINING-1",
            "sessionId": meta.sessionId,
            // AVO-ASSIGN-1: what the watch recorded (RAW header); empty names made Android reject the package
            "horseCode": meta.horseCode, "horseName": meta.horseName,
            "riderCode": meta.riderCode, "riderName": meta.riderName,
            "sha256": meta.sha256.lowercased(),
            "watchDevice": meta.watchDevice,
            "watchFirmware": meta.watchFirmware,
            "source": meta.source,
            "startRtcMs": NSNumber(value: meta.startRtcMs),
            "activeMs": NSNumber(value: meta.activeMs),
            "segments": hashes.count,
            "segmentHashes": hashes,
        ]
    }

    /// Writes `target` (.avo) from `segments` (P001.avr, P002.avr… in order). Throws AvoError on any problem; a partial
    /// package is never left behind.
    /// `manifestBase` (AVO-ASSIGN-1 rewrite of an existing package): that manifest is kept as it is, except "segments" and
    /// "segmentHashes", which are recomputed and must equal the ones it declares.
    static func write(target: String, meta: Meta, segments: [String], manifestBase: [String: Any]? = nil) throws {
        if segments.isEmpty { throw AvoError.invalidData("No hay segmentos que empaquetar") }
        let idLen = meta.sessionId.utf16.count
        if idLen < 3 || idLen > 128 || meta.sessionId.contains("/") || meta.sessionId.contains("\\") {
            throw AvoError.invalidData("ID de sesión inválido")
        }
        var infos: [(name: String, path: String, crc: UInt32, sha: String, size: Int64)] = []
        var hashes: [String: String] = [:]
        var total: Int64 = 0
        for p in segments {
            let name: String = AvoFiles.fileName(p)
            if !TrainingImporter.isSafeSegmentName(name) { throw AvoError.invalidData("Nombre de segmento no válido: \(name)") }
            let s = try scan(p)
            if s.size < 1 { throw AvoError.invalidData("Segmento vacío: \(name)") }
            if s.size > 50 * 1024 * 1024 { throw AvoError.invalidData("Segmento de más de 50 MB: \(name)") }
            total += s.size
            infos.append((name, p, s.crc, s.sha, s.size))
            hashes[name] = s.sha
        }
        if total > 100 * 1024 * 1024 { throw AvoError.invalidData("Entrenamiento de más de 100 MB") }
        infos.sort { $0.name < $1.name }

        var meta = meta
        if manifestBase == nil, meta.horseName.isEmpty, let first = infos.first {
            let raw = AvoAssignment.rawHeaderIdentity(first.path)
            meta.horseCode = raw.horse ?? ""; meta.horseName = raw.horse ?? ""
            meta.riderCode = raw.rider ?? ""; meta.riderName = raw.rider ?? ""
        }
        var body: [String: Any] = manifest(meta, hashes: hashes)
        if var base = manifestBase {
            if let declared = AvoJSON.dict(base, "segmentHashes") {
                for (k, v) in declared where (v as? String)?.lowercased() != hashes[k] { throw AvoError.invalidData("La huella de \(k) cambió") }
                if declared.count != hashes.count { throw AvoError.invalidData("El número de segmentos cambió") }
            }
            base["segments"] = hashes.count; base["segmentHashes"] = hashes
            body = base
        }
        let manifestData: Data = try JSONSerialization.data(withJSONObject: body,
                                                            options: [.sortedKeys, .withoutEscapingSlashes])
        let manifestBytes: [UInt8] = [UInt8](manifestData)

        AvoFiles.ensureDir((target as NSString).deletingLastPathComponent)
        let tmp = target + ".tmp"
        let fm = FileManager.default
        if fm.fileExists(atPath: tmp) { try? fm.removeItem(atPath: tmp) }   // left over by an interrupted attempt
        guard fm.createFile(atPath: tmp, contents: nil), let h = FileHandle(forWritingAtPath: tmp) else {
            throw AvoError.invalidOperation("No se puede crear \(AvoFiles.fileName(tmp))")
        }
        let out = Out(h)
        let (dosTime, dosDate) = dosTimeDate(Date())
        var entries: [Entry] = []
        do {
            func header(_ name: [UInt8], _ crc: UInt32, _ size: UInt32) throws {
                let w = LeWriter()
                w.u32(0x0403_4B50).u16(20).u16(0x0800).u16(0).u16(dosTime).u16(dosDate)
                w.u32(Int64(crc)).u32(Int64(size)).u32(Int64(size))
                w.u16(name.count).u16(0).bytes(name)
                try out.write(w.toArray())
            }
            // manifest.json first (as Windows/Android)
            let mName: [UInt8] = Array("manifest.json".utf8)
            let mCrc: UInt32 = ZipCRC32.compute(manifestBytes)
            entries.append(Entry(name: mName, crc: mCrc, size: UInt32(manifestBytes.count), offset: UInt32(out.pos)))
            try header(mName, mCrc, UInt32(manifestBytes.count))
            try out.write(manifestBytes)
            // segments
            for info in infos {
                let name: [UInt8] = Array(("segments/" + info.name).utf8)
                if out.pos > UInt64(UInt32.max - 1) { throw AvoError.invalidData("Paquete demasiado grande") }
                entries.append(Entry(name: name, crc: info.crc, size: UInt32(info.size), offset: UInt32(out.pos)))
                try header(name, info.crc, UInt32(info.size))
                guard let r = FileHandle(forReadingAtPath: info.path) else { throw AvoError.notFound("No se puede leer \(info.name)") }
                defer { try? r.close() }
                var copied: Int64 = 0
                while true {
                    let d: Data = try r.read(upToCount: 65_536) ?? Data()
                    if d.isEmpty { break }
                    copied += Int64(d.count)
                    try out.write(d)
                }
                if copied != info.size { throw AvoError.invalidData("\(info.name) cambió mientras se empaquetaba") }
            }
            // central directory
            let cdStart: UInt64 = out.pos
            for e in entries {
                let w = LeWriter()
                w.u32(0x0201_4B50).u16(20).u16(20).u16(0x0800).u16(0).u16(dosTime).u16(dosDate)
                w.u32(Int64(e.crc)).u32(Int64(e.size)).u32(Int64(e.size))
                w.u16(e.name.count).u16(0).u16(0).u16(0).u16(0)
                w.u32(0).u32(Int64(e.offset)).bytes(e.name)
                try out.write(w.toArray())
            }
            let cdSize: UInt64 = out.pos - cdStart
            let end = LeWriter()
            end.u32(0x0605_4B50).u16(0).u16(0).u16(entries.count).u16(entries.count)
            end.u32(Int64(cdSize)).u32(Int64(cdStart)).u16(0)
            try out.write(end.toArray())
            try h.synchronize()
            try h.close()
        } catch {
            try? h.close()
            try? fm.removeItem(atPath: tmp)
            throw error
        }
        do {
            if fm.fileExists(atPath: target) {
                _ = try fm.replaceItemAt(URL(fileURLWithPath: target), withItemAt: URL(fileURLWithPath: tmp))
            } else {
                try fm.moveItem(atPath: tmp, toPath: target)
            }
        } catch {
            try? fm.removeItem(atPath: tmp)
            throw error
        }
    }
}
