import Foundation

// France Galop for the stable (private use requested by the trainer, 08/11/2026). The app shows france-galop.com in an
// in-app browser and READS what the page shows: the horse sheet (facts), its tables (career summary, performances =
// races, engagements) and the horse links of a trainer / owner page (the whole stable). It does not depend on the site's
// internal structure: it reads the visible text, the HTML tables and the links. Only on the user's request, one page at a
// time and with pauses («Actualizar toda la cuadra» waits several seconds between horses). Saved in france_galop.json.

struct FGFact: Codable, Equatable, Identifiable {
    var label: String
    var value: String
    var id: String { label }
}

struct FGTable: Codable, Equatable, Identifiable {
    var title: String
    var headers: [String]
    var rows: [[String]]
    var id: String { title + "|" + headers.joined(separator: ",") + "|\(rows.count)" }
}

struct FGLink: Codable, Equatable, Identifiable, Hashable {
    var text: String
    var href: String
    var id: String { href }
}

/// One page read from France Galop.
struct FGPage: Codable, Equatable {
    var url: String
    var readAt: Date = Date()
    var title: String
    var facts: [FGFact]
    var tables: [FGTable]
    var horseLinks: [FGLink]

    var isHorseSheet: Bool { !facts.isEmpty && (fact("Entraîneur") != nil || fact("Né le") != nil) }
    func fact(_ label: String) -> String? { facts.first { $0.label == label }?.value }

    /// Year of birth from «Né le dd/mm/yyyy».
    var birthYear: Int? {
        guard let n = fact("Né le"), let y = n.split(separator: "/").last.flatMap({ Int($0.prefix(4)) }) else { return nil }
        return (1900...2100).contains(y) ? y : nil
    }

    /// Breed of the Cuadra list (RacingBreed labels) from the sex / breed / coat line («FEMELLE PS GRI»).
    var breedLabel: String? {
        guard let line = fact("Sexe · race · robe")?.uppercased() else { return nil }
        let w: [String] = line.split(separator: " ").map(String.init)
        if w.contains("AQPS") { return "AQPS (Autre Que Pur-Sang)" }
        if w.contains("AR") || w.contains("PSAR") || line.contains("PUR-SANG ARABE") { return "Pura Sangre Árabe (PSA)" }
        if w.contains("AA") { return "Anglo-Árabe (AA)" }
        if w.contains("PS") { return "Pura Sangre Inglés (PSI)" }
        return nil
    }
}

enum FranceGalop {
    static let home: String = "https://www.france-galop.com/fr"

    /// Reads the visible page: h1, body text, every table (headers + rows) and the links.
    static let extractJS: String = """
    (function(){
      function t(e){return ((e && (e.innerText || e.textContent)) || '').replace(/\\s+/g,' ').trim();}
      var tables=[];
      document.querySelectorAll('table').forEach(function(tb){
        var hs=[]; var head=tb.querySelectorAll('thead th');
        if(head.length===0){ var fr=tb.querySelector('tr'); if(fr){ fr.querySelectorAll('th').forEach(function(h){hs.push(t(h));}); } }
        else { head.forEach(function(h){hs.push(t(h));}); }
        var rows=[];
        tb.querySelectorAll('tr').forEach(function(tr){ var c=[]; tr.querySelectorAll('td').forEach(function(td){c.push(t(td));}); if(c.length){rows.push(c);} });
        var title=''; var p=tb.previousElementSibling; var up=tb.parentElement;
        for(var k=0;k<6;k++){ if(!p && up){ p=up.previousElementSibling; up=up.parentElement; } if(!p){break;} var tx=t(p); if(tx && tx.length<90){title=tx;break;} p=p.previousElementSibling; }
        if(rows.length){ tables.push({title:title,headers:hs,rows:rows.slice(0,300)}); }
      });
      var links=[]; document.querySelectorAll('a[href]').forEach(function(a){ var x=t(a); if(x && x.length<70){ links.push({text:x,href:a.href}); } });
      var h1=document.querySelector('h1');
      return JSON.stringify({url:location.href,title:h1?t(h1):document.title,text:(document.body.innerText||'').slice(0,60000),tables:tables,links:links.slice(0,3000)});
    })()
    """

    /// Labels of the horse sheet, longest first so «PLAT Dernière valeur» wins over «Dernière valeur».
    static let labels: [String] = [
        "Crédit d'indemnités de transport", "Sous les couleurs de", "OBSTACLE Dernière valeur", "PLAT Dernière valeur",
        "Pays Entraînement", "Droit à la prime", "Dernière valeur", "Qualifié FEE", "Performances", "Propriétaire",
        "Entraîneur", "Éleveurs", "Éleveur", "Né le", "Par",
    ].sorted { $0.count > $1.count }

    /// Parses the JSON returned by `extractJS`.
    static func parse(_ json: String) -> FGPage? {
        guard let d = json.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        let url: String = o["url"] as? String ?? ""
        let title: String = (o["title"] as? String ?? "").trimmed
        let text: String = o["text"] as? String ?? ""
        var tables: [FGTable] = []
        for case let t as [String: Any] in (o["tables"] as? [Any] ?? []) {
            let rows: [[String]] = (t["rows"] as? [[String]] ?? []).filter { r in r.contains { !$0.isEmpty } }
            if rows.isEmpty { continue }
            tables.append(FGTable(title: (t["title"] as? String ?? "").trimmed, headers: t["headers"] as? [String] ?? [], rows: rows))
        }
        var links: [FGLink] = []
        var seen = Set<String>()
        let host: String = URL(string: url)?.host ?? "france-galop.com"
        for case let l as [String: String] in (o["links"] as? [Any] ?? []) {
            guard let href = l["href"], let txt = l["text"]?.trimmed, !txt.isEmpty else { continue }
            guard let u = URL(string: href), let h = u.host, h.hasSuffix(hostRoot(host)) else { continue }
            // horse sheets: «cheval» in the path, and not the page itself
            if !u.path.lowercased().contains("cheval") || href == url || seen.contains(href) { continue }
            seen.insert(href)
            links.append(FGLink(text: txt, href: href))
        }
        return FGPage(url: url, title: title, facts: facts(text), tables: tables, horseLinks: links)
    }

    private static func hostRoot(_ h: String) -> String {
        let p: [Substring] = h.split(separator: ".")
        return p.count >= 2 ? p.suffix(2).joined(separator: ".") : h
    }

    /// «Label value» or «Label» + value on the next line, for the known labels; plus the «FEMELLE PS GRI» line.
    static func facts(_ text: String) -> [FGFact] {
        let lines: [String] = text.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "\t", with: " ").trimmed }
            .filter { !$0.isEmpty }
        var out: [FGFact] = []
        var done = Set<String>()
        for (i, line) in lines.enumerated() {
            if !done.contains("Sexe · race · robe"),
               let w = line.split(separator: " ").first.map({ String($0).uppercased() }),
               ["MALE", "MÂLE", "FEMELLE", "HONGRE"].contains(w), line.count < 40 {
                out.append(FGFact(label: "Sexe · race · robe", value: line))
                done.insert("Sexe · race · robe")
                continue
            }
            for l in labels where !done.contains(l) {
                guard line.lowercased().hasPrefix(l.lowercased()) else { continue }
                var v: String = String(line.dropFirst(l.count)).trimmed
                while v.hasPrefix(":") { v = String(v.dropFirst()).trimmed }
                if v.isEmpty, i + 1 < lines.count, !labels.contains(where: { lines[i + 1].lowercased().hasPrefix($0.lowercased()) }) {
                    v = lines[i + 1].trimmed
                }
                if l == "Par" && !v.contains(" et ") { break }   // «Par» only for the parents line
                if !v.isEmpty && v.count < 160 {
                    out.append(FGFact(label: l, value: v))
                    done.insert(l)
                }
                break
            }
        }
        return out
    }

    /// Name comparison key: upper case, no accents, letters and digits only.
    static func key(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .uppercased().filter { $0.isLetter || $0.isNumber }
    }
}

/// france_galop.json: France Galop sheet linked to each Cuadra horse and the last page read.
final class FGStore {
    private struct File: Codable {
        var links: [String: String] = [:]
        var pages: [String: FGPage] = [:]
    }
    private let path: String
    private var file = File()

    init(root: String) {
        path = AvoFiles.join(root, "france_galop.json")
        if let d = AvoFiles.read(path) {
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            file = (try? dec.decode(File.self, from: d)) ?? File()
        }
    }

    private func save() throws {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try AvoFiles.writeAtomic(try enc.encode(file), to: path)
    }

    func url(_ code: String) -> String? { file.links[code] }
    func page(_ code: String) -> FGPage? { file.pages[code] }
    var linked: [(code: String, url: String)] { file.links.map { ($0.key, $0.value) }.sorted { $0.code < $1.code } }

    func link(_ code: String, _ url: String) throws {
        file.links[code] = url
        try save()
    }

    func set(_ code: String, _ page: FGPage) throws {
        file.links[code] = page.url
        file.pages[code] = page
        try save()
    }

    func unlink(_ code: String) throws {
        file.links[code] = nil
        file.pages[code] = nil
        try save()
    }
}
