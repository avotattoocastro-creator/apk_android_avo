import Foundation

/// Answer of the «Asistente IA» saved on the horse as an «Informe IA» (trainer's request 09/11/2026): it is seen from
/// the horse sheet in Cuadra (button «Análisis IA» of each training) and goes into the full training report.
struct SavedAIReport: Codable, Identifiable, Equatable {
    var id: String = SegmentDefinition.newId()
    var horseCode: String
    var horseName: String
    var rider: String
    var sessionId: String
    var sessionDate: String
    var question: String
    var text: String
    /// «Claude Opus 5.5 · 12 400 tokens · ~0,03 $» or «Apple (en el iPad)».
    var model: String
    var savedAt: Date = Date()

    /// Short label for menus: «09/11 00:12 · Explícame este entrenamiento…».
    var menuTitle: String {
        let q: String = question.count > 48 ? String(question.prefix(46)) + "…" : question
        return MadridTime.format(savedAt, "dd/MM HH:mm") + " · " + (q.isEmpty ? "Informe IA" : q)
    }
}

/// informes_ia.json in the app folder (never next to the original training files).
final class AIReportStore {
    private let file: String
    private(set) var items: [SavedAIReport] = []

    init(root: String) {
        file = AvoFiles.join(root, "informes_ia.json")
        load()
    }

    func load() {
        guard let d = AvoFiles.read(file) else { items = []; return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        items = (try? dec.decode([SavedAIReport].self, from: d)) ?? []
    }

    func save() throws {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try AvoFiles.writeAtomic(try enc.encode(items), to: file)
    }

    func add(_ r: SavedAIReport) throws {
        items.append(r)
        try save()
    }

    func remove(_ id: String) throws {
        items.removeAll { $0.id == id }
        try save()
    }

    /// Reports of one training, oldest first.
    func of(session id: String) -> [SavedAIReport] {
        items.filter { $0.sessionId == id }.sorted { $0.savedAt < $1.savedAt }
    }
}
