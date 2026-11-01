import Foundation

/// Helpers that reproduce, byte for byte, the .NET formatting used by the Windows analysis/report code
/// (custom numeric format strings, Math.Round, shortest round-trip doubles, Utf8JsonWriter, HTML/XML escaping),
/// so the files written by the iPad (CSV, GPX, JSON, HTML, PDF) are interchangeable with those written by Windows.
enum DotNetFormat {
    /// Line terminator of the Windows app (StreamWriter.WriteLine / Utf8JsonWriter on Windows).
    static let newline: String = "\r\n"
    private static let posix: Locale = Locale(identifier: "en_US_POSIX")

    /// C# Math.Round(value, digits) (MidpointRounding.ToEven, scale by a power of ten).
    static func round(_ value: Double, _ digits: Int) -> Double {
        if !value.isFinite { return value }
        if abs(value) >= 1e16 { return value }
        let p: Double = pow(10.0, Double(digits))
        let scaled: Double = (value * p).rounded(.toNearestOrEven)
        return scaled / p
    }

    /// C# Math.Round(value) (banker's rounding).
    static func roundEven(_ value: Double) -> Double { value.rounded(.toNearestOrEven) }

    /// C# `(byte)Math.Round(x)` for colour channels.
    static func byteRound(_ value: Double) -> UInt8 {
        let r: Double = value.rounded(.toNearestOrEven)
        if !r.isFinite || r <= 0 { return 0 }
        if r >= 255 { return 255 }
        return UInt8(r)
    }

    // MARK: - Shortest round-trip ("R", Utf8JsonWriter, JsonSerializer)

    /// .NET Core 3.0+ shortest round-trippable representation of a double (invariant culture):
    /// "1" for 1.0, "-0" for negative zero, "1E-05" / "1E+15" in scientific notation.
    static func roundTrip(_ x: Double) -> String {
        if x.isNaN { return "NaN" }
        if x.isInfinite { return x < 0 ? "-Infinity" : "Infinity" }
        let negative: Bool = x.sign == .minus
        if x == 0 { return negative ? "-0" : "0" }
        var desc: String = "\(abs(x))"
        var exp: Int = 0
        if let eRange = desc.range(of: "e") {
            let expText: String = String(desc[eRange.upperBound...])
            exp = Int(expText.replacingOccurrences(of: "+", with: "")) ?? 0
            desc = String(desc[..<eRange.lowerBound])
        }
        var intPart: String = desc
        var fracPart: String = ""
        if let dot = desc.firstIndex(of: ".") {
            intPart = String(desc[..<dot])
            fracPart = String(desc[desc.index(after: dot)...])
        }
        var digits: [Character] = Array(intPart + fracPart)
        var pointPos: Int = intPart.count + exp
        while digits.count > 1 && digits[0] == "0" { digits.removeFirst(); pointPos -= 1 }
        while digits.count > 1 && digits[digits.count - 1] == "0" { digits.removeLast() }
        let digitText: String = String(digits)
        if digitText == "0" { return negative ? "-0" : "0" }
        let exp10: Int = pointPos - 1
        var body: String
        if exp10 >= 15 || exp10 < -4 {
            body = String(digits[0])
            if digits.count > 1 { body += "." + String(digits[1...]) }
            let e: Int = abs(exp10)
            body += "E" + (exp10 < 0 ? "-" : "+") + (e < 10 ? "0" : "") + String(e)
        } else if pointPos <= 0 {
            body = "0." + String(repeating: "0", count: -pointPos) + digitText
        } else if pointPos >= digits.count {
            body = digitText + String(repeating: "0", count: pointPos - digits.count)
        } else {
            body = String(digits[0..<pointPos]) + "." + String(digits[pointPos...])
        }
        return (negative ? "-" : "") + body
    }

    // MARK: - Custom numeric format strings ("0.00", "0.0#", "+0.0;-0.0;0.0", "#,##0" …)

    /// C# `value.ToString(format, culture)` for custom numeric formats. `spanish` = es-ES (decimal comma, group dot),
    /// otherwise InvariantCulture. Doubles are first reduced to 15 significant digits (as .NET does for custom formats)
    /// and then rounded half away from zero.
    static func custom(_ x: Double, _ format: String, spanish: Bool) -> String {
        if x.isNaN { return "NaN" }
        if x.isInfinite {
            if spanish { return x < 0 ? "-∞" : "∞" }
            return x < 0 ? "-Infinity" : "Infinity"
        }
        let sections: [String] = format.components(separatedBy: ";")
        func section(_ k: Int) -> Int {
            if k < sections.count && !sections[k].isEmpty { return k }
            return 0
        }
        let digits15: (digits: [Int], scale: Int) = significantDigits(abs(x))
        let isZero: Bool = x == 0 || digits15.digits.allSatisfy { $0 == 0 }
        var sec: Int = isZero ? section(2) : (x < 0 ? section(1) : 0)
        var pattern: Pattern = parse(sections[sec])
        var rounded: (digits: [Int], scale: Int) = roundDigits(digits15, pattern.maxFrac)
        var roundedZero: Bool = rounded.digits.allSatisfy { $0 == 0 }
        if !isZero && roundedZero {
            let z: Int = section(2)
            if z != sec {
                sec = z
                pattern = parse(sections[sec])
                rounded = roundDigits(digits15, pattern.maxFrac)
                roundedZero = true
            }
        }
        let decimalSep: String = spanish ? "," : "."
        let groupSep: String = spanish ? "." : ","
        // integer and fraction digit strings
        var intDigits: [Int] = []
        var fracDigits: [Int] = []
        let d: [Int] = rounded.digits
        let scale: Int = rounded.scale
        if scale > 0 {
            for i in 0..<scale { intDigits.append(i < d.count ? d[i] : 0) }
        }
        if pattern.maxFrac > 0 {
            for k in 0..<pattern.maxFrac {
                let idx: Int = scale + k
                fracDigits.append(idx >= 0 && idx < d.count ? d[idx] : 0)
            }
        }
        while let first = intDigits.first, first == 0, intDigits.count > 0 { intDigits.removeFirst() }
        while intDigits.count < pattern.minInt { intDigits.insert(0, at: 0) }
        while fracDigits.count > pattern.minFrac, let last = fracDigits.last, last == 0 { fracDigits.removeLast() }
        var intText: String = ""
        let intChars: [String] = intDigits.map { String($0) }
        if pattern.grouping && intChars.count > 3 {
            var parts: [String] = []
            var end: Int = intChars.count
            while end > 0 {
                let start: Int = Swift.max(0, end - 3)
                parts.insert(intChars[start..<end].joined(), at: 0)
                end = start
            }
            intText = parts.joined(separator: groupSep)
        } else {
            intText = intChars.joined()
        }
        var number: String = intText
        if !fracDigits.isEmpty { number += decimalSep + fracDigits.map { String($0) }.joined() }
        let negativeSign: String = (x < 0 && sec == 0 && !roundedZero) ? "-" : ""
        return negativeSign + pattern.prefix + number + pattern.suffix
    }

    private struct Pattern {
        var prefix: String = ""
        var suffix: String = ""
        var minInt: Int = 0
        var minFrac: Int = 0
        var maxFrac: Int = 0
        var grouping: Bool = false
    }

    private static func parse(_ s: String) -> Pattern {
        var p: Pattern = Pattern()
        let chars: [Character] = Array(s)
        var i: Int = 0
        var prefix: String = ""
        while i < chars.count && chars[i] != "0" && chars[i] != "#" && chars[i] != "." && chars[i] != "," {
            if chars[i] == "\\" && i + 1 < chars.count { prefix.append(chars[i + 1]); i += 2; continue }
            if chars[i] != "'" && chars[i] != "\"" { prefix.append(chars[i]) }
            i += 1
        }
        var intPart: String = ""
        var fracPart: String = ""
        var inFrac: Bool = false
        while i < chars.count && (chars[i] == "0" || chars[i] == "#" || chars[i] == "." || chars[i] == ",") {
            let c: Character = chars[i]
            if c == "." { if inFrac { break }; inFrac = true }
            else if inFrac { if c != "," { fracPart.append(c) } }
            else { intPart.append(c) }
            i += 1
        }
        var suffix: String = ""
        while i < chars.count {
            if chars[i] == "\\" && i + 1 < chars.count { suffix.append(chars[i + 1]); i += 2; continue }
            if chars[i] != "'" && chars[i] != "\"" { suffix.append(chars[i]) }
            i += 1
        }
        p.prefix = prefix
        p.suffix = suffix
        p.grouping = intPart.contains(",")
        let intOnly: [Character] = Array(intPart.replacingOccurrences(of: ",", with: ""))
        if let firstZero = intOnly.firstIndex(of: "0") { p.minInt = intOnly.count - firstZero }
        let frac: [Character] = Array(fracPart)
        p.maxFrac = frac.count
        if let lastZero = frac.lastIndex(of: "0") { p.minFrac = lastZero + 1 }
        return p
    }

    /// 15 significant digits of a non-negative finite value: digits d0…d14 and scale (number of integer digits).
    private static func significantDigits(_ v: Double) -> (digits: [Int], scale: Int) {
        if v == 0 { return ([0], 1) }
        let s: String = String(format: "%.14e", locale: posix, v)
        guard let eIdx = s.firstIndex(of: "e") else { return ([0], 1) }
        let mantissa: String = String(s[..<eIdx]).replacingOccurrences(of: ".", with: "")
        let expText: String = String(s[s.index(after: eIdx)...]).replacingOccurrences(of: "+", with: "")
        let exp: Int = Int(expText) ?? 0
        var digits: [Int] = []
        for ch in mantissa { if let n = ch.wholeNumberValue { digits.append(n) } }
        return (digits, exp + 1)
    }

    /// Rounds half away from zero keeping `frac` decimals.
    private static func roundDigits(_ n: (digits: [Int], scale: Int), _ frac: Int) -> (digits: [Int], scale: Int) {
        var digits: [Int] = n.digits
        var scale: Int = n.scale
        let keep: Int = scale + frac
        if keep >= digits.count { return (digits, scale) }
        if keep < 0 { return ([0], 1) }
        let roundUp: Bool = digits[keep] >= 5
        digits = Array(digits[0..<keep])
        if roundUp {
            var i: Int = keep - 1
            var carry: Bool = true
            while carry && i >= 0 {
                digits[i] += 1
                if digits[i] == 10 { digits[i] = 0; i -= 1 } else { carry = false }
            }
            if carry { digits.insert(1, at: 0); scale += 1 }
        }
        if digits.isEmpty { return ([0], 1) }
        return (digits, scale)
    }

    /// C# int.ToString("X2").
    static func hex2(_ b: UInt8) -> String { String(format: "%02X", UInt32(b)) }

    // MARK: - Dates

    /// Ticks (100 ns) since 1970-01-01 UTC of a Date (C# DateTimeOffset resolution).
    static func ticks(_ d: Date) -> Int64 { Int64((d.timeIntervalSince1970 * 1e7).rounded()) }
    static func date(ticks: Int64) -> Date { Date(timeIntervalSince1970: Double(ticks) / 1e7) }

    /// C# DateTimeOffset.AddSeconds(seconds) at tick precision (fraction truncated toward zero, as .NET 7+).
    static func addSeconds(_ ticks: Int64, _ seconds: Double) -> Int64 {
        let add: Double = seconds * 1e7
        if !add.isFinite { return ticks }
        return ticks + Int64(add)
    }

    private static func floorDiv(_ a: Int64, _ b: Int64) -> Int64 {
        let q: Int64 = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }

    /// Invariant UTC "yyyy-MM-dd'T'HH:mm:ss" formatter (shared; DateFormatter is thread-safe for formatting).
    private static let utcSecondsFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    /// UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ss.fffZ", Invariant) from ticks since 1970.
    static func utcMillisStamp(ticks: Int64) -> String {
        let secs: Int64 = floorDiv(ticks, 10_000_000)
        let rem: Int64 = ticks - secs * 10_000_000
        let ms: Int64 = rem / 10_000
        let base: String = utcSecondsFormatter.string(from: Date(timeIntervalSince1970: Double(secs)))
        return base + "." + String(format: "%03ld", Int(ms)) + "Z"
    }

    /// "yyyy-MM-ddTHH:mm:ssZ" (UTC, invariant).
    static func utcSecondsStamp(_ d: Date) -> String {
        let secs: Int64 = floorDiv(ticks(d), 10_000_000)
        return utcSecondsFormatter.string(from: Date(timeIntervalSince1970: Double(secs))) + "Z"
    }

    /// System.Text.Json form of a UTC DateTimeOffset: "2026-11-01T10:15:30.1234567+00:00" (trailing fraction zeros trimmed).
    static func jsonDateTimeOffset(_ d: Date) -> String {
        let t: Int64 = ticks(d)
        let secs: Int64 = floorDiv(t, 10_000_000)
        let rem: Int64 = t - secs * 10_000_000
        var s: String = utcSecondsFormatter.string(from: Date(timeIntervalSince1970: Double(secs)))
        if rem > 0 {
            var frac: String = String(format: "%07ld", Int(rem))
            while frac.hasSuffix("0") { frac.removeLast() }
            s += "." + frac
        }
        return s + "+00:00"
    }

    /// Parses an ISO 8601 date with optional fraction (any length) and "Z" or ±hh:mm offset.
    static func parseIsoDate(_ text: String) -> Date? {
        let s: [Character] = Array(text.trimmingCharacters(in: .whitespaces))
        func num(_ a: Int, _ len: Int) -> Int? {
            guard a + len <= s.count else { return nil }
            return Int(String(s[a..<(a + len)]))
        }
        guard s.count >= 19, let y = num(0, 4), let mo = num(5, 2), let da = num(8, 2), let h = num(11, 2), let mi = num(14, 2), let se = num(17, 2) else {
            return AvoTime.parseIso(text)
        }
        var i: Int = 19
        var frac: Double = 0
        if i < s.count && s[i] == "." {
            i += 1
            var digits: String = ""
            while i < s.count, s[i].isNumber { digits.append(s[i]); i += 1 }
            if !digits.isEmpty { frac = Double("0." + digits) ?? 0 }
        }
        var offsetS: Int = 0
        if i < s.count {
            if s[i] == "Z" || s[i] == "z" { offsetS = 0 }
            else if s[i] == "+" || s[i] == "-" {
                let sign: Int = s[i] == "-" ? -1 : 1
                guard let oh = num(i + 1, 2) else { return nil }
                var om: Int = 0
                if i + 3 < s.count && s[i + 3] == ":" { om = num(i + 4, 2) ?? 0 } else { om = num(i + 3, 2) ?? 0 }
                offsetS = sign * (oh * 3600 + om * 60)
            }
        }
        var comps: DateComponents = DateComponents()
        comps.year = y; comps.month = mo; comps.day = da; comps.hour = h; comps.minute = mi; comps.second = se
        var cal: Calendar = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        guard let base = cal.date(from: comps) else { return nil }
        return Date(timeIntervalSince1970: base.timeIntervalSince1970 - Double(offsetS) + frac)
    }
}

/// HTML / XML escaping identical to .NET.
enum DotNetText {
    /// System.Net.WebUtility.HtmlEncode: &lt; &gt; &quot; &#39; &amp;, characters 160–255 and non-BMP as &#N;.
    static func htmlEncode(_ s: String?) -> String {
        guard let s = s else { return "" }
        var out: String = ""
        out.reserveCapacity(s.utf16.count + 8)
        for scalar in s.unicodeScalars {
            switch scalar {
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            case "&": out += "&amp;"
            default:
                let v: UInt32 = scalar.value
                if (v >= 160 && v < 256) || v > 0xFFFF { out += "&#\(v);" } else { out.unicodeScalars.append(scalar) }
            }
        }
        return out
    }

    /// System.Security.SecurityElement.Escape.
    static func xmlEscape(_ s: String) -> String {
        var out: String = ""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            case "&": out += "&amp;"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}

/// Minimal clone of System.Text.Json.Utf8JsonWriter (default encoder; Indented = 2 spaces, Windows new lines).
struct DotNetJsonWriter {
    private(set) var text: String = ""
    private var counts: [Int] = []
    private let indented: Bool
    private let newline: String

    init(indented: Bool = true, newline: String = DotNetFormat.newline) {
        self.indented = indented
        self.newline = newline
    }

    private mutating func separator() {
        if counts.isEmpty { return }
        if counts[counts.count - 1] > 0 { text += "," }
        if indented {
            text += newline
            text += String(repeating: " ", count: counts.count * 2)
        }
        counts[counts.count - 1] += 1
    }

    private mutating func property(_ name: String) {
        separator()
        text += DotNetJsonWriter.quote(name)
        text += indented ? ": " : ":"
    }

    mutating func writeStartObject() { separator(); text += "{"; counts.append(0) }
    mutating func writeStartObject(_ name: String) { property(name); text += "{"; counts.append(0) }
    mutating func writeEndObject() { close("}") }
    mutating func writeStartArray() { separator(); text += "["; counts.append(0) }
    mutating func writeStartArray(_ name: String) { property(name); text += "["; counts.append(0) }
    mutating func writeEndArray() { close("]") }

    private mutating func close(_ c: String) {
        let n: Int = counts.popLast() ?? 0
        if n > 0 && indented {
            text += newline
            text += String(repeating: " ", count: counts.count * 2)
        }
        text += c
    }

    mutating func writeString(_ name: String, _ value: String) { property(name); text += DotNetJsonWriter.quote(value) }
    mutating func writeNumber(_ name: String, _ value: Double) { property(name); text += DotNetFormat.roundTrip(value) }
    mutating func writeNumber(_ name: String, _ value: Int) { property(name); text += String(value) }
    mutating func writeBoolean(_ name: String, _ value: Bool) { property(name); text += value ? "true" : "false" }
    mutating func writeNull(_ name: String) { property(name); text += "null" }
    mutating func writeNumberValue(_ value: Double) { separator(); text += DotNetFormat.roundTrip(value) }
    mutating func writeNullValue() { separator(); text += "null" }
    mutating func writeStringValue(_ value: String) { separator(); text += DotNetJsonWriter.quote(value) }

    /// JSON string literal escaped with JavaScriptEncoder.Default (non-ASCII and HTML-sensitive characters as \uXXXX).
    static func quote(_ s: String) -> String {
        var out: String = "\""
        for u in s.utf16 {
            switch u {
            case 0x0A: out += "\\n"
            case 0x0D: out += "\\r"
            case 0x09: out += "\\t"
            case 0x08: out += "\\b"
            case 0x0C: out += "\\f"
            case 0x5C: out += "\\\\"
            case 0x22, 0x26, 0x27, 0x2B, 0x3C, 0x3E, 0x60: out += String(format: "\\u%04X", UInt32(u))
            default:
                if u >= 0x20 && u <= 0x7E { out.unicodeScalars.append(Unicode.Scalar(UInt8(u))) }
                else { out += String(format: "\\u%04X", UInt32(u)) }
            }
        }
        return out + "\""
    }
}
