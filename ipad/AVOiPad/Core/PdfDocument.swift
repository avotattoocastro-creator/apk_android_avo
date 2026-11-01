import Foundation
import Compression

/// Minimal, dependency-free PDF 1.4 writer (vector text and graphics) for the AVO reports. Uses the standard Type 1
/// fonts Helvetica / Helvetica-Bold with WinAnsiEncoding (covers Spanish), Flate-compressed content streams and a
/// correct cross-reference table. Coordinates are in points with the origin at the TOP-left of the page.
final class PdfDocument {
    static let a4Width: Double = 595.28
    static let a4Height: Double = 841.89
    private var pages: [String] = []
    private var current: Int? = nil
    let width: Double = PdfDocument.a4Width
    let height: Double = PdfDocument.a4Height
    var pageCount: Int { pages.count }
    var title: String = "Informe AVO"

    enum Align { case left, center, right }

    init() {}

    func newPage() {
        pages.append("")
        current = pages.count - 1
    }

    private func append(_ s: String) {
        guard let c = current else { preconditionFailure("Llama a NewPage() antes de dibujar") }
        pages[c] += s
    }

    private static func n(_ v: Double) -> String { DotNetFormat.custom(DotNetFormat.round(v, 3), "0.###", spanish: false) }
    private static func rgb(_ c: AvoRGB) -> String {
        "\(n(Double(c.r) / 255.0)) \(n(Double(c.g) / 255.0)) \(n(Double(c.b) / 255.0))"
    }

    func fillRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ color: AvoRGB) {
        let N = PdfDocument.n
        append("\(PdfDocument.rgb(color)) rg \(N(x)) \(N(height - y - h)) \(N(w)) \(N(h)) re f\n")
    }

    func strokeRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ color: AvoRGB, width: Double = 0.5) {
        let N = PdfDocument.n
        append("\(PdfDocument.rgb(color)) RG \(N(width)) w \(N(x)) \(N(height - y - h)) \(N(w)) \(N(h)) re S\n")
    }

    func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ color: AvoRGB, width: Double = 0.5) {
        let N = PdfDocument.n
        append("\(PdfDocument.rgb(color)) RG \(N(width)) w 1 J \(N(x1)) \(N(height - y1)) m \(N(x2)) \(N(height - y2)) l S\n")
    }

    /// Open polyline; NaN points break the line.
    func polyline(_ pts: [(x: Double, y: Double)], _ color: AvoRGB, width: Double = 1) {
        let N = PdfDocument.n
        var s: String = "\(PdfDocument.rgb(color)) RG \(N(width)) w 1 J 1 j\n"
        var open: Bool = false
        for p in pts {
            if !p.x.isFinite || !p.y.isFinite {
                if open { s += "S\n" }
                open = false
                continue
            }
            let op: String = open ? " l\n" : " m\n"
            s += "\(N(p.x)) \(N(height - p.y))\(op)"
            open = true
        }
        if open { s += "S\n" }
        append(s)
    }

    func circle(_ cx: Double, _ cy: Double, _ r: Double, _ fill: AvoRGB) {
        let N = PdfDocument.n
        let k: Double = 0.5523
        let y: Double = height - cy
        var s: String = PdfDocument.rgb(fill) + " rg "
        s += "\(N(cx + r)) \(N(y)) m \(N(cx + r)) \(N(y + k * r)) \(N(cx + k * r)) \(N(y + r)) \(N(cx)) \(N(y + r)) c "
        s += "\(N(cx - k * r)) \(N(y + r)) \(N(cx - r)) \(N(y + k * r)) \(N(cx - r)) \(N(y)) c "
        s += "\(N(cx - r)) \(N(y - k * r)) \(N(cx - k * r)) \(N(y - r)) \(N(cx)) \(N(y - r)) c "
        s += "\(N(cx + k * r)) \(N(y - r)) \(N(cx + r)) \(N(y - k * r)) \(N(cx + r)) \(N(y)) c f\n"
        append(s)
    }

    /// Single line of text; y is the TOP of the text box.
    func text(_ x: Double, _ y: Double, _ text: String, size: Double = 10, bold: Bool = false, color: AvoRGB? = nil, align: Align = .left) {
        let N = PdfDocument.n
        let w: Double = PdfDocument.measureText(text, size, bold)
        var tx: Double = x
        switch align {
        case .center: tx = x - w / 2
        case .right: tx = x - w
        case .left: tx = x
        }
        let baseline: Double = height - y - size * 0.82
        let c: AvoRGB = color ?? (r: 0x10, g: 0x10, b: 0x14)
        let font: String = bold ? "F2 " : "F1 "
        append("BT /\(font)\(N(size)) Tf \(PdfDocument.rgb(c)) rg \(N(tx)) \(N(baseline)) Td (\(PdfDocument.escape(text))) Tj ET\n")
    }

    /// Word-wrapped paragraph. Returns the height used.
    @discardableResult
    func paragraph(_ x: Double, _ y: Double, _ maxWidth: Double, _ text: String, size: Double = 9.5, bold: Bool = false,
                   color: AvoRGB? = nil, leading: Double = 1.3) -> Double {
        let lineH: Double = size * leading
        var used: Double = 0
        let paras: [String] = text.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n")
        for para in paras {
            let words: [String] = para.components(separatedBy: " ").filter { !$0.isEmpty }
            var line: String = ""
            for word in words {
                let probe: String = line.isEmpty ? word : line + " " + word
                if PdfDocument.measureText(probe, size, bold) > maxWidth && !line.isEmpty {
                    self.text(x, y + used, line, size: size, bold: bold, color: color)
                    used += lineH
                    line = word
                } else {
                    line = probe
                }
            }
            if !line.isEmpty {
                self.text(x, y + used, line, size: size, bold: bold, color: color)
                used += lineH
            } else if words.isEmpty {
                used += lineH * 0.5
            }
        }
        return used
    }

    static func measureText(_ text: String, _ size: Double, _ bold: Bool) -> Double {
        var w: Double = 0
        for ch in text.utf16 { w += glyphWidth(ch, bold) }
        return w * size / 1000.0
    }

    // Adobe AFM widths of Helvetica and Helvetica-Bold for ASCII 32..126.
    private static let regular: [Int16] = [
        278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278, 556, 556, 556, 556, 556, 556, 556, 556, 556, 556,
        278, 278, 584, 584, 584, 556, 1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778, 667, 778, 722, 667,
        611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556, 333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833,
        556, 556, 556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584,
    ]
    private static let boldWidths: [Int16] = [
        278, 333, 474, 556, 556, 889, 722, 238, 333, 333, 389, 584, 278, 333, 278, 278, 556, 556, 556, 556, 556, 556, 556, 556, 556, 556,
        333, 333, 584, 584, 584, 611, 975, 722, 722, 722, 722, 667, 611, 778, 722, 278, 556, 722, 611, 833, 722, 778, 667, 778, 722, 667,
        611, 722, 667, 944, 667, 667, 611, 333, 278, 333, 584, 556, 333, 556, 611, 556, 611, 556, 333, 611, 611, 278, 278, 556, 278, 889,
        611, 611, 611, 611, 389, 556, 333, 611, 556, 778, 556, 556, 500, 389, 280, 389, 584,
    ]

    private static func glyphWidth(_ ch: UInt16, _ bold: Bool) -> Double {
        let table: [Int16] = bold ? boldWidths : regular
        if ch >= 32 && ch <= 126 { return Double(table[Int(ch) - 32]) }
        let b: UInt16 = baseLetter(ch)
        if b != ch && b >= 32 && b <= 126 { return Double(table[Int(b) - 32]) }
        switch ch {
        case 0x20AC: return 556          // €
        case 0x2013: return 556          // –
        case 0x2014: return 1000         // —
        case 0x2022: return 350          // •
        case 0x2026: return 1000         // …
        case 0x00B0: return 400          // °
        case 0x00B7: return 278          // ·
        case 0x00BA, 0x00AA: return 370  // º ª
        case 0x00B1, 0x00D7: return 584  // ± ×
        case 0x00B2, 0x00B3: return 333  // ² ³
        case 0x00BF: return 611          // ¿
        case 0x00A1: return 333          // ¡
        case 0x2018, 0x2019: return 222  // ‘ ’
        case 0x201C, 0x201D: return 333  // “ ”
        default: return 556
        }
    }

    private static func baseLetter(_ c: UInt16) -> UInt16 {
        switch c {
        case 0xE1, 0xE0, 0xE2, 0xE4: return 0x61   // a
        case 0xE9, 0xE8, 0xEA, 0xEB: return 0x65   // e
        case 0xED, 0xEC, 0xEE, 0xEF: return 0x69   // i
        case 0xF3, 0xF2, 0xF4, 0xF6: return 0x6F   // o
        case 0xFA, 0xF9, 0xFB, 0xFC: return 0x75   // u
        case 0xF1: return 0x6E                     // n
        case 0xE7: return 0x63                     // c
        case 0xC1, 0xC0: return 0x41               // A
        case 0xC9, 0xC8: return 0x45               // E
        case 0xCD: return 0x49                     // I
        case 0xD3: return 0x4F                     // O
        case 0xDA, 0xDC: return 0x55               // U
        case 0xD1: return 0x4E                     // N
        case 0xC7: return 0x43                     // C
        default: return c
        }
    }

    /// WinAnsiEncoding byte of a UTF-16 code unit, or '?' when it is not representable.
    static func winAnsi(_ c: UInt16) -> UInt8 {
        if c < 0x80 { return UInt8(c) }
        if c >= 0xA0 && c <= 0xFF { return UInt8(c) }
        switch c {
        case 0x20AC: return 0x80   // €
        case 0x201A: return 0x82   // ‚
        case 0x201E: return 0x84   // „
        case 0x2026: return 0x85   // …
        case 0x2018: return 0x91   // ‘
        case 0x2019: return 0x92   // ’
        case 0x201C: return 0x93   // “
        case 0x201D: return 0x94   // ”
        case 0x2022: return 0x95   // •
        case 0x2013: return 0x96   // –
        case 0x2014: return 0x97   // —
        case 0x2122: return 0x99   // ™
        case 0x2212: return 0x2D   // − → -
        default: return 0x3F       // ?
        }
    }

    private static func escape(_ s: String) -> String {
        var out: String = ""
        out.reserveCapacity(s.utf16.count + 8)
        for ch in s.utf16 {
            let b: UInt8 = winAnsi(ch)
            if b == 0x28 || b == 0x29 || b == 0x5C {
                out += "\\"
                out.unicodeScalars.append(Unicode.Scalar(b))
            } else if b < 32 || b > 126 {
                var oct: String = String(b, radix: 8)
                while oct.count < 3 { oct = "0" + oct }
                out += "\\" + oct
            } else {
                out.unicodeScalars.append(Unicode.Scalar(b))
            }
        }
        return out
    }

    /// Latin-1 bytes of a string (characters above U+00FF become '?', as Encoding.Latin1).
    private static func latin1(_ s: String) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(s.utf16.count)
        for u in s.utf16 { out.append(u < 256 ? UInt8(u) : 0x3F) }
        return out
    }

    /// zlib stream (RFC 1950: header + raw DEFLATE + Adler-32), as .NET ZLibStream.
    static func zlib(_ input: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [0x78, 0x9C]
        if input.isEmpty {
            out.append(contentsOf: [0x03, 0x00])
        } else {
            let capacity: Int = input.count + input.count / 2 + 1024
            var buffer: [UInt8] = [UInt8](repeating: 0, count: capacity)
            let written: Int = input.withUnsafeBufferPointer { (src: UnsafeBufferPointer<UInt8>) -> Int in
                buffer.withUnsafeMutableBufferPointer { (dst: inout UnsafeMutableBufferPointer<UInt8>) -> Int in
                    guard let d = dst.baseAddress, let s = src.baseAddress else { return 0 }
                    return compression_encode_buffer(d, dst.count, s, src.count, nil, COMPRESSION_ZLIB)
                }
            }
            if written > 0 {
                out.append(contentsOf: buffer[0..<written])
            } else {
                // Fallback: stored (uncompressed) DEFLATE blocks, still a valid zlib stream.
                var i: Int = 0
                while i < input.count {
                    let len: Int = min(65535, input.count - i)
                    let final: Bool = i + len >= input.count
                    out.append(final ? 0x01 : 0x00)
                    out.append(UInt8(len & 0xFF)); out.append(UInt8(len >> 8))
                    out.append(UInt8(~len & 0xFF)); out.append(UInt8((~len >> 8) & 0xFF))
                    out.append(contentsOf: input[i..<(i + len)])
                    i += len
                }
            }
        }
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in input {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        let adler: UInt32 = (b << 16) | a
        out.append(UInt8((adler >> 24) & 0xFF)); out.append(UInt8((adler >> 16) & 0xFF))
        out.append(UInt8((adler >> 8) & 0xFF)); out.append(UInt8(adler & 0xFF))
        return out
    }

    /// Complete PDF file.
    func save() -> Data {
        if pages.isEmpty { newPage() }
        var bytes: [UInt8] = []
        var offsets: [Int] = []
        func w(_ s: String) { bytes.append(contentsOf: PdfDocument.latin1(s)) }
        let N = PdfDocument.n
        w("%PDF-1.4\n%âãÏÓ\n")
        let pageCount: Int = pages.count
        let firstPageObj: Int = 5
        // 1 catalog, 2 pages, 3 F1, 4 F2, then (page, content) pairs, then info
        offsets.append(bytes.count); w("1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n")
        var kidsList: [String] = []
        for i in 0..<pageCount { kidsList.append("\(firstPageObj + 2 * i) 0 R") }
        let kids: String = kidsList.joined(separator: " ")
        offsets.append(bytes.count); w("2 0 obj\n<< /Type /Pages /Kids [\(kids)] /Count \(pageCount) >>\nendobj\n")
        offsets.append(bytes.count); w("3 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>\nendobj\n")
        offsets.append(bytes.count); w("4 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>\nendobj\n")
        for i in 0..<pageCount {
            let pageObj: Int = firstPageObj + 2 * i
            let contentObj: Int = pageObj + 1
            offsets.append(bytes.count)
            w("\(pageObj) 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \(N(width)) \(N(height))] /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents \(contentObj) 0 R >>\nendobj\n")
            let raw: [UInt8] = PdfDocument.latin1(pages[i])
            let packed: [UInt8] = PdfDocument.zlib(raw)
            offsets.append(bytes.count)
            w("\(contentObj) 0 obj\n<< /Length \(packed.count) /Filter /FlateDecode >>\nstream\n")
            bytes.append(contentsOf: packed)
            w("\nendstream\nendobj\n")
        }
        let infoObj: Int = firstPageObj + 2 * pageCount
        offsets.append(bytes.count)
        let stamp: DateFormatter = AvoTime.formatter("yyyyMMddHHmmss", utc: true)
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.calendar = Calendar(identifier: .gregorian)
        w("\(infoObj) 0 obj\n<< /Title (\(PdfDocument.escape(title))) /Producer (AVO Performance Horse Windows) /CreationDate (D:\(stamp.string(from: Date()))Z) >>\nendobj\n")
        let xref: Int = bytes.count
        w("xref\n0 \(offsets.count + 1)\n0000000000 65535 f \n")
        for o in offsets { w(String(format: "%010ld", o) + " 00000 n \n") }
        w("trailer\n<< /Size \(offsets.count + 1) /Root 1 0 R /Info \(infoObj) 0 R >>\nstartxref\n\(xref)\n%%EOF\n")
        return Data(bytes)
    }

    func save(to path: String) throws {
        try AvoFiles.writeAtomic(save(), to: path)
    }
}
