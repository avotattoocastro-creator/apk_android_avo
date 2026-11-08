import Foundation

/// Names of the exported files (trainer's request 08/11/2026): «<Caballo>_<aaaa-mm-dd>_<hhmm>_<Tipo>.<ext>», e.g.
/// BELLA_AL_SHAHANIA_2026-11-08_0955_Completo.pdf or BELLA_AL_SHAHANIA_2026-11-08_0955_Tramo_1826-2038.pdf
/// (date and time of the training in Europe/Madrid). Only letters, digits, «-» and «_».
enum ExportNaming {
    static func name(_ s: SessionItem, _ kind: String, _ ext: String) -> String {
        var horse: String = clean(s.horse)
        if horse.isEmpty { horse = "Caballo" }
        if horse.count > 40 { horse = String(horse.prefix(40)) }
        let when: String = s.start.map { MadridTime.format($0, "yyyy-MM-dd_HHmm") } ?? clean(s.id)
        return horse + "_" + when + "_" + clean(kind) + "." + ext
    }

    /// «Tramo_1826-2038» (times of the timeline, mm:ss or h:mm:ss without separators); with a name «Tramo-<nombre>_…».
    static func rangeKind(_ t0: Double, _ t1: Double, base: String = "Tramo", label: String = "") -> String {
        func c(_ t: Double) -> String { TimeText.clock(t).replacingOccurrences(of: ":", with: "") }
        let head: String = label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? base : base + "-" + label
        return head + "_" + c(min(t0, t1)) + "-" + c(max(t0, t1))
    }

    static func clean(_ text: String) -> String {
        var out: String = ""
        let folded: String = text.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "es_ES"))
        for ch in folded {
            if ch.isLetter || ch.isNumber || ch == "-" { out.append(ch) }
            else if ch == " " || ch == "_" || ch == "." || ch == "/" { if !out.hasSuffix("_") { out.append("_") } }
        }
        while out.hasSuffix("_") { out.removeLast() }
        while out.hasPrefix("_") { out.removeFirst() }
        return out
    }
}
