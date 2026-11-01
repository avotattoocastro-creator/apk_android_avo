import Foundation
import Compression

/// CRC-32 (IEEE 802.3, polynomial 0xEDB88320), table driven. Used by the ZIP reader and the AVORAW1 parser.
enum ZipCRC32 {
    static let table: [UInt32] = {
        var t = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1) != 0 ? (c >> 1) ^ 0xEDB8_8320 : c >> 1 }
            t[i] = c
        }
        return t
    }()

    /// Running update (start with 0xFFFFFFFF, finish with `^ 0xFFFFFFFF`).
    static func update(_ crc: UInt32, _ bytes: UnsafeBufferPointer<UInt8>) -> UInt32 {
        var c = crc
        table.withUnsafeBufferPointer { (t: UnsafeBufferPointer<UInt32>) -> Void in
            for b in bytes { c = t[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        }
        return c
    }

    /// CRC-32 of `count` bytes of `bytes` starting at `from` (bounds must be valid).
    static func compute(_ bytes: [UInt8], _ from: Int, _ count: Int) -> UInt32 {
        if count <= 0 { return 0 }
        return bytes.withUnsafeBufferPointer { (all: UnsafeBufferPointer<UInt8>) -> UInt32 in
            let slice = UnsafeBufferPointer<UInt8>(rebasing: all[from..<(from + count)])
            return update(0xFFFF_FFFF, slice) ^ 0xFFFF_FFFF
        }
    }

    static func compute(_ bytes: [UInt8]) -> UInt32 { compute(bytes, 0, bytes.count) }
}

/// Central-directory record of one ZIP entry.
struct ZipEntry: Equatable {
    /// Name exactly as stored in the archive ("segments/P001.avr").
    var fullName: String
    /// Uncompressed size declared by the central directory (C# ZipArchiveEntry.Length).
    var length: Int64
    var compressedLength: Int64
    var method: UInt16
    var crc32: UInt32
    var flags: UInt16
    var localHeaderOffset: Int64
}

/// Minimal, defensive ZIP reader (replaces System.IO.Compression.ZipFile for .avo packages).
/// Parses the central directory only, supports stored (0) and deflate (8) entries, never extracts to disk
/// and verifies CRC-32 and declared sizes of every entry read. ZIP64 records are understood.
final class ZipReader {
    private let bytes: [UInt8]
    let entries: [ZipEntry]

    static let maxEntriesDefault = 65_535

    convenience init(path: String, maxEntries: Int = ZipReader.maxEntriesDefault) throws {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw AvoError.notFound("No se puede leer el archivo ZIP")
        }
        try self.init(bytes: [UInt8](data), maxEntries: maxEntries)
    }

    convenience init(data: Data, maxEntries: Int = ZipReader.maxEntriesDefault) throws {
        try self.init(bytes: [UInt8](data), maxEntries: maxEntries)
    }

    init(bytes: [UInt8], maxEntries: Int = ZipReader.maxEntriesDefault) throws {
        self.bytes = bytes
        self.entries = try ZipReader.parseCentralDirectory(bytes, maxEntries: maxEntries)
    }

    /// First entry with exactly this name (as ZipArchive.GetEntry), nil if none.
    func entry(_ name: String) -> ZipEntry? {
        for e in entries where e.fullName == name { return e }
        return nil
    }

    /// Reads an entry into memory with the semantics of the Windows ReadBounded: stops with an error as soon as more
    /// than `max` bytes come out, and requires the result to have exactly the declared uncompressed size.
    /// Also verifies the CRC-32 of the data.
    func read(_ entry: ZipEntry, max: Int64) throws -> [UInt8] {
        if (entry.flags & 1) != 0 { throw AvoError.invalidData("Entrada ZIP cifrada no admitida") }
        let start = try dataStart(entry)
        guard entry.compressedLength >= 0, start <= Int64(bytes.count),
              entry.compressedLength <= Int64(bytes.count) - start else {
            throw AvoError.invalidData("Entrada ZIP fuera de los límites del archivo")
        }
        let from = Int(start)
        let count = Int(entry.compressedLength)
        var out: [UInt8]
        switch entry.method {
        case 0:
            if Int64(count) > max { throw AvoError.invalidData("ZIP descomprimido excede el límite") }
            out = Array(bytes[from..<(from + count)])
        case 8:
            out = try ZipReader.inflate(bytes, from: from, count: count, max: max, expected: entry.length)
        default:
            throw AvoError.invalidData("Método de compresión ZIP no compatible")
        }
        if Int64(out.count) != entry.length { throw AvoError.invalidData("Tamaño descomprimido incorrecto") }
        if ZipCRC32.compute(out) != entry.crc32 { throw AvoError.invalidData("CRC-32 incorrecto en la entrada ZIP \(entry.fullName)") }
        return out
    }

    // MARK: - parsing

    private func dataStart(_ e: ZipEntry) throws -> Int64 {
        let o = e.localHeaderOffset
        guard o >= 0, o + 30 <= Int64(bytes.count) else { throw AvoError.invalidData("Cabecera local ZIP fuera del archivo") }
        let i = Int(o)
        guard BinaryReaderLE.u32(bytes, i) == 0x0403_4B50 else { throw AvoError.invalidData("Cabecera local ZIP incorrecta") }
        let nameLen = Int64(BinaryReaderLE.u16(bytes, i + 26))
        let extraLen = Int64(BinaryReaderLE.u16(bytes, i + 28))
        let start = o + 30 + nameLen + extraLen
        guard start <= Int64(bytes.count) else { throw AvoError.invalidData("Cabecera local ZIP fuera del archivo") }
        return start
    }

    private static func parseCentralDirectory(_ b: [UInt8], maxEntries: Int) throws -> [ZipEntry] {
        let n = b.count
        guard n >= 22 else { throw AvoError.invalidData("Archivo ZIP no válido") }
        // End of central directory: last occurrence, comment up to 65535 bytes.
        var eocd = -1
        var i = n - 22
        let lowest = Swift.max(0, n - 22 - 65_535)
        while i >= lowest {
            if b[i] == 0x50 && b[i + 1] == 0x4B && b[i + 2] == 0x05 && b[i + 3] == 0x06 {
                let commentLen = Int(BinaryReaderLE.u16(b, i + 20))
                if i + 22 + commentLen <= n { eocd = i; break }
            }
            i -= 1
        }
        guard eocd >= 0 else { throw AvoError.invalidData("Archivo ZIP no válido (sin directorio central)") }
        var total = Int64(BinaryReaderLE.u16(b, eocd + 10))
        var cdSize = Int64(BinaryReaderLE.u32(b, eocd + 12))
        var cdOffset = Int64(BinaryReaderLE.u32(b, eocd + 16))
        let diskNo = BinaryReaderLE.u16(b, eocd + 4)
        let cdDisk = BinaryReaderLE.u16(b, eocd + 6)
        // ZIP64 end of central directory locator (20 bytes just before the EOCD)
        if eocd >= 20 && BinaryReaderLE.u32(b, eocd - 20) == 0x0706_4B50 {
            let z64 = BinaryReaderLE.u64(b, eocd - 20 + 8)
            guard n >= 56, z64 <= UInt64(n - 56), BinaryReaderLE.u32(b, Int(z64)) == 0x0606_4B50 else {
                throw AvoError.invalidData("Registro ZIP64 incorrecto")
            }
            let z = Int(z64)
            let t64 = BinaryReaderLE.u64(b, z + 32)
            let s64 = BinaryReaderLE.u64(b, z + 40)
            let o64 = BinaryReaderLE.u64(b, z + 48)
            guard t64 <= UInt64(Int32.max), s64 <= UInt64(n), o64 <= UInt64(n) else {
                throw AvoError.invalidData("Registro ZIP64 incorrecto")
            }
            total = Int64(t64); cdSize = Int64(s64); cdOffset = Int64(o64)
        } else if diskNo != 0 || cdDisk != 0 {
            throw AvoError.invalidData("ZIP multivolumen no admitido")
        }
        if total > Int64(maxEntries) { throw AvoError.invalidData("Cantidad de entradas ZIP incorrecta") }
        guard cdOffset >= 0, cdSize >= 0, cdOffset + cdSize <= Int64(n) else {
            throw AvoError.invalidData("Directorio central ZIP fuera del archivo")
        }
        var result: [ZipEntry] = []
        result.reserveCapacity(Int(total))
        var p = Int(cdOffset)
        let end = Int(cdOffset + cdSize)
        for _ in 0..<Int(total) {
            guard p + 46 <= end, BinaryReaderLE.u32(b, p) == 0x0201_4B50 else {
                throw AvoError.invalidData("Directorio central ZIP incorrecto")
            }
            let flags = BinaryReaderLE.u16(b, p + 8)
            let method = BinaryReaderLE.u16(b, p + 10)
            let crc = BinaryReaderLE.u32(b, p + 16)
            var csize = Int64(BinaryReaderLE.u32(b, p + 20))
            var usize = Int64(BinaryReaderLE.u32(b, p + 24))
            let nameLen = Int(BinaryReaderLE.u16(b, p + 28))
            let extraLen = Int(BinaryReaderLE.u16(b, p + 30))
            let commentLen = Int(BinaryReaderLE.u16(b, p + 32))
            var local = Int64(BinaryReaderLE.u32(b, p + 42))
            let nameStart = p + 46
            guard nameStart + nameLen + extraLen + commentLen <= end else {
                throw AvoError.invalidData("Directorio central ZIP incorrecto")
            }
            let name = String(decoding: b[nameStart..<(nameStart + nameLen)], as: UTF8.self)
            // ZIP64 extended information extra field (0x0001): only the fields saturated in the record are present.
            var x = nameStart + nameLen
            let xEnd = x + extraLen
            while x + 4 <= xEnd {
                let tag = BinaryReaderLE.u16(b, x)
                let size = Int(BinaryReaderLE.u16(b, x + 2))
                let body = x + 4
                if body + size > xEnd { break }
                if tag == 0x0001 {
                    var q = body
                    if usize == 0xFFFF_FFFF && q + 8 <= body + size { usize = Int64(clamping: BinaryReaderLE.u64(b, q)); q += 8 }
                    if csize == 0xFFFF_FFFF && q + 8 <= body + size { csize = Int64(clamping: BinaryReaderLE.u64(b, q)); q += 8 }
                    if local == 0xFFFF_FFFF && q + 8 <= body + size { local = Int64(clamping: BinaryReaderLE.u64(b, q)); q += 8 }
                }
                x = body + size
            }
            result.append(ZipEntry(fullName: name, length: usize, compressedLength: csize, method: method, crc32: crc,
                                   flags: flags, localHeaderOffset: local))
            p = nameStart + nameLen + extraLen + commentLen
        }
        return result
    }

    /// Raw deflate (RFC 1951) with Apple's Compression framework (COMPRESSION_ZLIB is raw deflate), streaming so that
    /// a decompression bomb never allocates more than `max` + one chunk.
    private static func inflate(_ src: [UInt8], from: Int, count: Int, max: Int64, expected: Int64) throws -> [UInt8] {
        var out: [UInt8] = []
        if expected > 0 && expected <= max { out.reserveCapacity(Int(expected)) }
        let chunk = 65_536
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer { dst.deallocate() }
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw AvoError.invalidData("No se puede descomprimir la entrada ZIP")
        }
        defer { compression_stream_destroy(stream) }
        var failure: AvoError? = nil
        src.withUnsafeBufferPointer { (all: UnsafeBufferPointer<UInt8>) -> Void in
            guard let base = all.baseAddress else { failure = AvoError.invalidData("Entrada ZIP vacía"); return }
            stream.pointee.src_ptr = base + from
            stream.pointee.src_size = count
            let finalize = Int32(bitPattern: COMPRESSION_STREAM_FINALIZE.rawValue)
            var stalled = 0
            while true {
                stream.pointee.dst_ptr = dst
                stream.pointee.dst_size = chunk
                let status = compression_stream_process(stream, finalize)
                if status == COMPRESSION_STATUS_ERROR {
                    failure = AvoError.invalidData("Datos deflate corruptos en la entrada ZIP"); return
                }
                let produced = chunk - stream.pointee.dst_size
                if produced > 0 {
                    if Int64(out.count) + Int64(produced) > max {
                        failure = AvoError.invalidData("ZIP descomprimido excede el límite"); return
                    }
                    out.append(contentsOf: UnsafeBufferPointer<UInt8>(start: dst, count: produced))
                }
                if status == COMPRESSION_STATUS_END { return }
                stalled = produced == 0 ? stalled + 1 : 0
                if stalled >= 3 {
                    failure = AvoError.invalidData("Datos deflate incompletos en la entrada ZIP"); return
                }
            }
        }
        if let f = failure { throw f }
        return out
    }
}
