import Foundation

// Port of windows/AVO.Windows.Core/Stable/Nfc.cs — ONLY the pure parts (NDEF records and Type 2 TLV helpers).
// The iPad has no NFC and no PC/SC readers (PORTING.md): NtagApdu, PcscNfcReader (winscard.dll) and the simulated reader
// are not ported. The avohorse://identity/… parser (AvoIdentityTag) lives in Stable.swift, like in Stable.cs.
// C# FormatException → AvoError.invalidData(message).

/// Minimal NDEF (NFC Forum) reader/writer: what is needed for the URI records of the AVO identity tags.
enum Ndef {
    // NFC Forum URI RTD, abbreviation table (0x00 = none)
    static let uriPrefixes: [String] = [
        "", "http://www.", "https://www.", "http://", "https://", "tel:", "mailto:", "ftp://anonymous:anonymous@", "ftp://ftp.",
        "ftps://", "sftp://", "smb://", "nfs://", "ftp://", "dav://", "news:", "telnet://", "imap:", "rtsp://", "urn:", "pop:",
        "sip:", "sips:", "tftp:", "btspp://", "btl2cap://", "btgoep://", "tcpobex://", "irdaobex://", "file://", "urn:epc:id:",
        "urn:epc:tag:", "urn:epc:pat:", "urn:epc:raw:", "urn:epc:", "urn:nfc:",
    ]

    struct Record: Equatable {
        var tnf: UInt8
        var type: [UInt8]
        var id: [UInt8]
        var payload: [UInt8]
    }

    /// Parses an NDEF message. Throws AvoError.invalidData on malformed data (lengths are always checked).
    static func parse(_ m: [UInt8]) throws -> [Record] {
        var list: [Record] = []
        var i = 0
        while i < m.count {
            let h: UInt8 = m[i]
            i += 1
            let me: Bool = (h & 0x40) != 0
            let cf: Bool = (h & 0x20) != 0
            let sr: Bool = (h & 0x10) != 0
            let il: Bool = (h & 0x08) != 0
            let tnf: UInt8 = h & 7
            if cf { throw AvoError.invalidData("Registros NDEF fragmentados no admitidos") }
            if i >= m.count { throw AvoError.invalidData("NDEF truncado") }
            let typeLen = Int(m[i])
            i += 1
            var payLen: Int64 = 0
            if sr {
                try need(m, i, 1)
                payLen = Int64(m[i])
                i += 1
            } else {
                try need(m, i, 4)
                payLen = Int64(m[i]) << 24 | Int64(m[i + 1]) << 16 | Int64(m[i + 2]) << 8 | Int64(m[i + 3])
                i += 4
            }
            var idLen = 0
            if il {
                try need(m, i, 1)
                idLen = Int(m[i])
                i += 1
            }
            if payLen > 65536 { throw AvoError.invalidData("Registro NDEF demasiado grande") }
            let pl = Int(payLen)
            try need(m, i, typeLen + idLen + pl)
            let type: [UInt8] = Array(m[i..<(i + typeLen)]); i += typeLen
            let id: [UInt8] = Array(m[i..<(i + idLen)]); i += idLen
            let pay: [UInt8] = Array(m[i..<(i + pl)]); i += pl
            list.append(Record(tnf: tnf, type: type, id: id, payload: pay))
            if me { break }
        }
        return list
    }

    private static func need(_ m: [UInt8], _ i: Int, _ n: Int) throws {
        if n < 0 || i + n > m.count { throw AvoError.invalidData("NDEF truncado") }
    }

    /// URI of a well-known "U" record, or nil.
    static func uriOf(_ r: Record) -> String? {
        if r.tnf != 1 || r.type.count != 1 || r.type[0] != UInt8(ascii: "U") || r.payload.count < 1 { return nil }
        let code = Int(r.payload[0])
        let prefix: String = code < uriPrefixes.count ? uriPrefixes[code] : ""
        return prefix + String(decoding: r.payload[1...], as: UTF8.self)
    }

    /// All URIs of a message, in order.
    static func uris(_ message: [UInt8]) throws -> [String] {
        return try parse(message).compactMap { uriOf($0) }
    }

    /// One-record message with a URI record, like NdefRecord.createUri (no abbreviation applies to avohorse://).
    static func uriMessage(_ uri: String) -> [UInt8] {
        var code = 0
        for k in 1..<uriPrefixes.count {
            if uri.hasPrefix(uriPrefixes[k]) && uriPrefixes[k].utf8.count > uriPrefixes[code].utf8.count { code = k }
        }
        let rest: [UInt8] = Array(uri.utf8.dropFirst(uriPrefixes[code].utf8.count))
        var payload: [UInt8] = [UInt8(code)]
        payload.append(contentsOf: rest)
        var o: [UInt8] = []
        if payload.count < 256 {
            o.append(0xD1); o.append(1); o.append(UInt8(payload.count))
        } else {
            let n = UInt32(payload.count)
            o.append(0xC1); o.append(1)
            o.append(UInt8((n >> 24) & 0xFF)); o.append(UInt8((n >> 16) & 0xFF)); o.append(UInt8((n >> 8) & 0xFF)); o.append(UInt8(n & 0xFF))
        }
        o.append(UInt8(ascii: "U"))
        o.append(contentsOf: payload)
        return o
    }

    enum TlvScan { case found, absent, needMore }

    /// Finds the NDEF message TLV (type 0x03) in the data area of a Type 2 tag (from page 4).
    static func findMessageTlv(_ area: [UInt8]) throws -> [UInt8]? {
        let (st, m) = scanMessageTlv(area)
        if st == .needMore { throw AvoError.invalidData("TLV NDEF truncado") }
        return m
    }

    /// Scans the TLVs read so far: found (message), absent (terminator first) or needMore (not enough bytes yet).
    static func scanMessageTlv(_ area: [UInt8]) -> (TlvScan, [UInt8]?) {
        var i = 0
        while i < area.count {
            let t: UInt8 = area[i]
            i += 1
            if t == 0x00 { continue }          // NULL TLV
            if t == 0xFE { return (.absent, nil) }
            if i >= area.count { return (.needMore, nil) }
            var len = Int(area[i])
            i += 1
            if len == 0xFF {
                if i + 2 > area.count { return (.needMore, nil) }
                len = Int(area[i]) << 8 | Int(area[i + 1])
                i += 2
            }
            if i + len > area.count { return (.needMore, nil) }
            if t == 0x03 { return (.found, Array(area[i..<(i + len)])) }
            i += len                           // lock / memory control or proprietary TLV
        }
        return (.needMore, nil)
    }

    /// NDEF message TLV + terminator, padded to whole 4-byte pages.
    static func messageTlv(_ message: [UInt8]) -> [UInt8] {
        var o: [UInt8] = [0x03]
        if message.count < 0xFF {
            o.append(UInt8(message.count))
        } else {
            o.append(0xFF); o.append(UInt8((message.count >> 8) & 0xFF)); o.append(UInt8(message.count & 0xFF))
        }
        o.append(contentsOf: message)
        o.append(0xFE)
        while o.count % 4 != 0 { o.append(0x00) }
        return o
    }
}
