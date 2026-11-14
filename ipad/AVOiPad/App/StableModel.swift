import SwiftUI
import Observation
import UIKit

// Port of windows/AVO.Windows/ViewModels/MainViewModel.Stable.cs: Cuadra (horses), Jinetes (riders) and the «Asignar» panel.
// The iPad has no NFC (PORTING.md): the stored tag UID is shown, and an avohorse://identity/… link copied from Android or
// Windows can be pasted to register the record (same rules as reading the tag: an existing record is never overwritten).

/// One horse (Cuadra) or rider (Jinetes) with the totals of its trainings (C# IdentityRow).
struct StableIdentityRow: Identifiable {
    let kind: IdentityKind
    let record: IdentityRecord
    let sessions: [SessionItem]

    var id: String { record.code }
    var code: String { record.code }
    var name: String { record.name }
    var isDemo: Bool { record.demo }
    var active: Bool { record.active }
    var hasNfc: Bool { !(record.nfcUid ?? "").isEmpty }
    var initial: String { name.isEmpty ? "?" : String(name.prefix(1)).uppercased() }

    var subtitle: String {
        var parts: [String] = [code]
        if kind == .horse && !record.breed.trimmed.isEmpty { parts.append(record.breed) }
        if kind == .horse, let y = record.birthYear { parts.append(String(y)) }
        if !record.active { parts.append("inactivo") }
        return parts.joined(separator: " · ")
    }

    var count: Int { sessions.count }
    var countText: String { count == 1 ? "1 entrenamiento" : "\(count) entrenamientos" }

    /// All its trainings; marked when demonstration (synthetic) sessions are included.
    var distanceText: String {
        var km: Double = 0
        for s in sessions { km += s.distanceKmValue }
        let demo: Bool = !isDemo && sessions.contains(where: { $0.isSynthetic })
        return AvoFormat.f(km, 1) + " km" + (demo ? " (demo)" : "")
    }

    var lastDate: Date? {
        let dates: [Date] = sessions.compactMap { $0.start }
        return dates.max()
    }
    var lastDateText: String { count == 0 ? "—" : (lastDate.map { AvoTime.text($0, "dd/MM/yyyy") } ?? "—") }
    var lastText: String { count == 0 ? "Sin entrenamientos" : "Último " + lastDateText }

    var bestSpeedText: String {
        if count == 0 { return "—" }
        var best: Double = 0
        for s in sessions where s.maxSpeedKmh.isFinite { best = max(best, s.maxSpeedKmh) }
        return AvoFormat.f(best, 1) + " km/h"
    }

    /// Best 200 m among its trainings (engine «Mejor 200 m»; trainer 14/11/2026).
    var best200Text: String {
        var b: Double? = nil
        for s in sessions {
            guard let e = s.engine, let t = KeyData.cached(id: s.id, json: e.rawJson).best200S else { continue }
            b = min(b ?? t, t)
        }
        return b.map { DotNetFormat.custom($0, "0.00", spanish: true) + " s" } ?? "—"
    }

    var totalTimeText: String {
        var sum: Double = 0
        for s in sessions { sum += s.timeline.count > 1 ? s.timeline.durationS : s.session.durationSeconds }
        return TimeText.clock(sum)
    }
}

/// Cuadra or Jinetes page: list, record editor, trainings of the selected record (C# IdentityPage).
@Observable
final class StableIdentityPage {
    @ObservationIgnored unowned let owner: StableModel
    let kind: IdentityKind

    /// Every record with its trainings (rebuilt by StableModel.refreshStable).
    var allRows: [StableIdentityRow] = []
    var search: String = ""
    var showInactive: Bool = true
    var selectedCode: String? = nil
    var isNew: Bool = false

    var editCode: String = ""
    var editName: String = ""
    var editBreed: String = ""
    var editYear: String = ""
    var editNotes: String = ""
    var editActive: Bool = true
    var message: String = ""

    init(owner: StableModel, kind: IdentityKind) {
        self.owner = owner
        self.kind = kind
    }

    var isHorse: Bool { kind == .horse }
    var title: String { isHorse ? "Cuadra" : "Jinetes" }
    var singular: String { isHorse ? "caballo" : "jinete" }
    var newLabel: String { isHorse ? "Nuevo caballo" : "Nuevo jinete" }
    var emptyText: String {
        isHorse
            ? "Todavía no hay caballos. Crea uno, pega el enlace avohorse:// de su etiqueta o importa entrenamientos que lo traigan."
            : "Todavía no hay jinetes. Crea uno, pega el enlace avohorse:// de su tarjeta o importa entrenamientos que lo traigan."
    }

    /// Filtered list (search by name, code or breed; inactive ones optional).
    var items: [StableIdentityRow] {
        let q: String = search.trimmed
        return allRows.filter { (r: StableIdentityRow) -> Bool in
            if !showInactive && !r.active { return false }
            if q.isEmpty { return true }
            let rec = r.record
            return rec.name.localizedCaseInsensitiveContains(q) || rec.code.localizedCaseInsensitiveContains(q)
                || rec.breed.localizedCaseInsensitiveContains(q)
        }
    }
    var isEmpty: Bool { items.isEmpty }

    var selected: StableIdentityRow? {
        guard let c = selectedCode else { return nil }
        return allRows.first { $0.code.caseInsensitiveCompare(c) == .orderedSame }
    }
    var hasSelection: Bool { selected != nil || isNew }
    var header: String { isNew ? newLabel : (selected?.name ?? "") }
    var codeEditable: Bool { isNew }
    var canSave: Bool { !editName.trimmed.isEmpty && hasSelection }

    var trainings: [SessionItem] {
        guard let s = selected else { return [] }
        return s.sessions.sorted { (a: SessionItem, b: SessionItem) -> Bool in
            (a.start ?? Date.distantPast) > (b.start ?? Date.distantPast)
        }
    }

    var tagText: String {
        if let uid = selected?.record.nfcUid, !uid.isEmpty { return "Etiqueta NFC " + uid }
        return "Sin etiqueta NFC asociada"
    }
    var originText: String {
        guard let r = selected?.record, !isNew else { return "" }
        return "Origen: \(r.origin)" + (r.demo ? " · DEMOSTRACIÓN (datos sintéticos)" : "")
    }
    /// Same URI the Android app writes to the tag (to copy it to another device).
    var uriText: String {
        guard let r = selected?.record, !isNew else { return "" }
        return AvoIdentityTag.buildUri(kind, r)
    }

    var unknownCount: Int {
        owner.app.sessions.filter { (s: SessionItem) -> Bool in !(isHorse ? s.horseKnown : s.riderKnown) }.count
    }
    var unknownText: String {
        let n = unknownCount
        return n == 0 ? "Todos los entrenamientos tienen " + singular : "\(n) entrenamiento(s) sin \(singular)"
    }

    // ------------------------------------------------------------------ actions
    func choose(_ row: StableIdentityRow) {
        isNew = false
        selectedCode = row.code
        loadEditor(row.record)
    }

    private func loadEditor(_ r: IdentityRecord) {
        editCode = r.code
        editName = r.name
        editBreed = r.breed
        editYear = r.birthYear.map { String($0) } ?? ""
        editNotes = r.notes
        editActive = r.active
        message = ""
    }

    /// Back to the full-width list (trainer's sketch 13/11/2026).
    func backToList() {
        selectedCode = nil
        isNew = false
        message = ""
    }

    func startNew() {
        selectedCode = nil
        isNew = true
        editCode = (try? owner.store.nextCode(kind)) ?? ""
        editName = ""
        editBreed = ""
        editYear = ""
        editNotes = ""
        editActive = true
        message = "El código \(editCode) es el que se graba en el reloj y en la etiqueta NFC."
    }

    func save() {
        let yearText: String = editYear.trimmed
        var year: Int? = nil
        if let y = Int(yearText), y >= 1900 && y <= 2100 { year = y }
        if isHorse && !yearText.isEmpty && year == nil {
            message = "Año de nacimiento no válido (1900–2100)."
            return
        }
        if editName.trimmed.isEmpty { return }
        do {
            let code: String
            if isNew {
                let c: String = editCode.trimmed.uppercased()
                if !AvoIdentityTag.matchesCodePattern(c) {
                    message = "Código: de 1 a 23 caracteres, letras, números, «_» o «-»."
                    return
                }
                let rec = IdentityRecord(code: c, name: editName.trimmed, breed: isHorse ? editBreed.trimmed : "",
                                         birthYear: isHorse ? year : nil, notes: editNotes.trimmed, active: editActive,
                                         origin: "manual")
                code = try owner.store.add(kind, rec).code
                isNew = false
            } else if let sel = selected {
                code = sel.code
                let name = editName.trimmed, breed = editBreed.trimmed, notes = editNotes.trimmed, active = editActive
                let horse = isHorse
                try owner.store.update(kind, code) { (r: IdentityRecord) -> Void in
                    r.name = name
                    r.breed = horse ? breed : ""
                    r.birthYear = horse ? year : nil
                    r.notes = notes
                    r.active = active
                }
            } else {
                return
            }
            owner.reapplyIdentities()
            select(code)
            message = "Guardado."
        } catch {
            message = error.localizedDescription
        }
    }

    func askDelete() {
        guard let sel = selected, !isNew else { return }
        let name = sel.name, code = sel.code, n = sel.count
        owner.confirm = StableConfirm(
            title: title,
            message: "¿Eliminar a \(name) (\(code))?\n\n\(n) entrenamiento(s) volverán a mostrar el \(singular) que trae el archivo. Los archivos no se modifican.",
            okLabel: "Eliminar", destructive: true) { [weak self] in
                guard let self = self else { return }
                do {
                    _ = try self.owner.store.remove(self.kind, code)
                } catch {
                    self.message = error.localizedDescription
                    return
                }
                self.selectedCode = nil
                self.owner.reapplyIdentities()
            }
    }

    func askAssignUnknown() {
        owner.assignUnknownTo(self)
    }

    /// Selects a record, clearing the filters if it is hidden by them (C# Select).
    func select(_ code: String) {
        let visible: Bool = items.contains { $0.code.caseInsensitiveCompare(code) == .orderedSame }
        if !visible && (!search.isEmpty || !showInactive) {
            search = ""
            showInactive = true
        }
        if let row = allRows.first(where: { $0.code.caseInsensitiveCompare(code) == .orderedSame }) {
            isNew = false
            selectedCode = row.code
            loadEditor(row.record)
        } else {
            selectedCode = nil
        }
    }

    /// Rebuilds the list keeping the selection (the editor keeps what the user is typing).
    func rebuild(_ records: [IdentityRecord], _ sessions: [SessionItem]) {
        let sorted: [IdentityRecord] = records.sorted { (a: IdentityRecord, b: IdentityRecord) -> Bool in
            if a.active != b.active { return a.active }
            if a.demo != b.demo { return !a.demo }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        var rows: [StableIdentityRow] = []
        for r in sorted {
            let mine: [SessionItem] = sessions.filter { (s: SessionItem) -> Bool in
                guard let c = (kind == .horse ? s.horseCode : s.riderCode) else { return false }
                return c.caseInsensitiveCompare(r.code) == .orderedSame
            }
            rows.append(StableIdentityRow(kind: kind, record: r, sessions: mine))
        }
        allRows = rows
        if let c = selectedCode, !rows.contains(where: { $0.code.caseInsensitiveCompare(c) == .orderedSame }) {
            selectedCode = nil
        }
    }
}

/// Confirmation asked by the Cuadra/Jinetes pages (C# Dialogs.Confirm).
struct StableConfirm: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var okLabel: String = "Aceptar"
    var destructive: Bool = false
    var action: () -> Void
}

@Observable
final class StableModel {
    @ObservationIgnored unowned let app: AppModel
    @ObservationIgnored let store: StableStore
    @ObservationIgnored private(set) var horses: StableIdentityPage!
    @ObservationIgnored private(set) var riders: StableIdentityPage!

    var horseNames: [String] = []
    var riderNames: [String] = []
    var confirm: StableConfirm? = nil
    /// Last pasted avohorse:// link (Windows NfcLast / NfcLastOk).
    var linkLast: String = ""
    var linkLastOk: Bool = true

    // ---------------------------------------------------------------- assignment panel
    var assignVisible: Bool = false
    var assignTarget: SessionItem? = nil
    var assignHorseText: String = ""
    var assignRiderText: String = ""
    var assignMessage: String = ""
    var assignAlsoUnknown: Bool = false
    var assignOthersText: String = ""

    init(app: AppModel) {
        self.app = app
        self.store = StableStore(path: AvoFiles.join(app.paths.root, "cuadra.json"))
        self.horses = StableIdentityPage(owner: self, kind: .horse)
        self.riders = StableIdentityPage(owner: self, kind: .rider)
        horses.rebuild(store.horses, [])
        riders.rebuild(store.riders, [])
        rebuildNames()
    }

    func page(_ kind: IdentityKind) -> StableIdentityPage { kind == .horse ? horses : riders }

    // ---------------------------------------------------------------- contract
    func sessionChanged() { refreshStable() }
    func pageShown() { refreshStable() }

    // ---------------------------------------------------------------- identities
    /// AVO-ASSIGN-1: writes the assignment into the library copy (.avo) of each training so that the exported package,
    /// Android and Windows see the same horse. The RAW segments are never changed. If a file cannot be written the
    /// assignment stays in this iPad's Cuadra only and it is reported.
    func writeAssignmentToFiles(_ items: [SessionItem]) {
        var failed = 0
        for s in items where !s.isSynthetic {
            let h = store.resolve(s.session, .horse), r = store.resolve(s.session, .rider)
            let a = AvoAssignmentData(horseCode: h.code, horseName: h.known ? h.name : "", riderCode: r.code, riderName: r.known ? r.name : "",
                                      updated: Date(), app: "ipad")
            do {
                if let sha = try app.library.writeAssignment(s.id, a, rawHorse: s.session.rawHorse, rawRider: s.session.rawRider) {
                    s.session.fileSha256 = sha
                }
                s.engine = nil   // the analysis carries the identity: recomputed with the new assignment
            } catch {
                failed += 1
                app.log.warn("cuadra", "no se pudo escribir la asignación en el archivo de \(s.id): \(error.localizedDescription)", error)
            }
        }
        if failed > 0 { app.status = "Asignación guardada en este iPad; \(failed) archivo(s) no se pudieron actualizar (ver registro)" }
    }

    /// Applies the Cuadra/Jinetes names to one training (in memory; the file is never changed).
    func applyIdentity(_ s: SessionItem) {
        let r = store.apply(s.session)
        s.setIdentity(r.horse, r.rider)
    }

    /// Applies Cuadra/Jinetes names to every loaded training and refreshes everything that shows them.
    func reapplyIdentities() {
        for s in app.sessions { applyIdentity(s) }
        refreshStable()
        app.notifySessionChanged()
    }

    func refreshStable() {
        let list: [SessionItem] = app.sessions
        horses.rebuild(store.horses, list)
        riders.rebuild(store.riders, list)
        rebuildNames()
    }

    private func rebuildNames() {
        horseNames = StableModel.activeNames(store.horses)
        riderNames = StableModel.activeNames(store.riders)
    }

    private static func activeNames(_ l: [IdentityRecord]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for r in l where r.active {
            if seen.insert(r.name).inserted { out.append(r.name) }
        }
        return out.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var unknownHorseCount: Int { app.sessions.filter { !$0.horseKnown }.count }
    var unknownRiderCount: Int { app.sessions.filter { !$0.riderKnown }.count }

    /// Called by the shell after an import: new horses/riders carried by the files go into the Cuadra/Jinetes (marked DEMO
    /// when they come from a demonstration session), then the names are applied to every training.
    func registerImported(_ items: [SessionItem]) {
        for s in items {
            do {
                try store.registerFromTraining(s.session)
                try store.adoptFileAssignment(s.session)   // AVO-ASSIGN-1: newer assignment made in another app
            } catch {
                app.log.warn("cuadra", error.localizedDescription, error)
            }
        }
        reapplyIdentities()
    }

    // ---------------------------------------------------------------- pasted avohorse:// link (instead of NFC)
    /// Reads an avohorse://identity/… link from the clipboard and registers it (like reading the tag on Android/Windows).
    func pasteLink() {
        let text: String = (UIPasteboard.general.string ?? "").trimmed
        registerLink(text)
    }

    func registerLink(_ text: String) {
        let when: String = AvoTime.text(Date(), "HH:mm:ss")
        if text.isEmpty {
            linkLast = "\(when) · El portapapeles no tiene ningún enlace avohorse://"
            linkLastOk = false
            return
        }
        do {
            let tag = try AvoIdentityTag.parse(text)
            let res = try store.importTag(tag, uidHex: nil)
            let what: String = tag.kind == .horse ? "Caballo" : "Jinete"
            let rec = res.record
            linkLast = "\(when) · \(what) \(rec.name) (\(rec.code)) "
                + (res.created ? "registrado desde el enlace" : "leído (ya estaba registrado; no se sobrescribe)")
            linkLastOk = true
            app.log.info("cuadra", res.created ? "registrado desde enlace" : "enlace leído", ["code": rec.code])
            reapplyIdentities()
            if assignVisible {
                if tag.kind == .horse { assignHorseText = rec.name } else { assignRiderText = rec.name }
            } else if app.page == .stable || app.page == .riders {
                app.page = tag.kind == .horse ? .stable : .riders
                page(tag.kind).select(rec.code)
            }
            app.status = String(linkLast.dropFirst(when.count + 3))
        } catch {
            linkLast = "\(when) · " + error.localizedDescription
            linkLastOk = false
        }
    }

    // ---------------------------------------------------------------- assignment panel
    var assignFileText: String {
        guard let t = assignTarget else { return "" }
        let s = t.session
        let hc: String = s.horseCode.map { " (\($0))" } ?? ""
        let rc: String = s.riderCode.map { " (\($0))" } ?? ""
        return "En el archivo: caballo «\(s.horseInFile)»\(hc) · jinete «\(s.riderInFile)»\(rc)"
    }
    var hasAssignOthers: Bool { !assignOthersText.isEmpty }

    func openAssign(_ item: SessionItem?) {
        guard let s = item ?? app.selected else { return }
        assignTarget = s
        assignHorseText = s.horseKnown ? s.horse : ""
        assignRiderText = s.riderKnown ? s.rider : ""
        assignAlsoUnknown = false
        let others: Int = app.sessions.filter { $0 !== s && (!$0.horseKnown || !$0.riderKnown) }.count
        assignOthersText = others == 0 ? ""
            : "Aplicar también a los otros \(others) entrenamiento(s) sin caballo o sin jinete (solo rellena lo que falta)"
        assignMessage = "Escribe o elige el caballo y el jinete, o pega el enlace avohorse:// de su etiqueta. Solo cambia la ficha en este iPad: el archivo del entrenamiento no se modifica."
        rebuildNames()
        assignVisible = true
    }

    func cancelAssign() { assignVisible = false }

    func clearAssign() {
        assignHorseText = ""
        assignRiderText = ""
    }

    /// Names of the Cuadra/Jinetes that match what is typed (suggestions under the text fields).
    func suggestions(_ kind: IdentityKind, _ text: String) -> [String] {
        let names: [String] = kind == .horse ? horseNames : riderNames
        let q: String = text.trimmed
        if q.isEmpty { return Array(names.prefix(8)) }
        let exact: Bool = names.contains { $0.caseInsensitiveCompare(q) == .orderedSame }
        if exact { return [] }
        return Array(names.filter { $0.localizedCaseInsensitiveContains(q) }.prefix(8))
    }

    /// Finds a record by name or code; creates it (next free code) when the text is new. Empty → nil (clear).
    private func codeFor(_ k: IdentityKind, _ text: String) throws -> String? {
        let t: String = text.trimmed
        if t.isEmpty { return nil }
        if let r = store.findByName(k, t) ?? store.find(k, t) { return r.code }
        let rec = IdentityRecord(code: try store.nextCode(k), name: t, origin: "asignación")
        return try store.add(k, rec).code
    }

    func confirmAssign() {
        guard let t = assignTarget else { return }
        do {
            let h: String? = try codeFor(.horse, assignHorseText)
            let r: String? = try codeFor(.rider, assignRiderText)
            try store.assign(t.id, setHorse: true, horseCode: h, setRider: true, riderCode: r)
            var touched: [SessionItem] = [t]
            var extra = 0
            if assignAlsoUnknown {
                for s in app.sessions where s !== t {
                    let sh: Bool = !s.horseKnown && h != nil
                    let sr: Bool = !s.riderKnown && r != nil
                    if !sh && !sr { continue }
                    try store.assign(s.id, setHorse: sh, horseCode: h, setRider: sr, riderCode: r)
                    touched.append(s)
                    extra += 1
                }
            }
            app.log.info("cuadra", "asignación", ["session": t.id, "horse": h ?? "", "rider": r ?? "", "extra": extra] as [String: Any])
            assignVisible = false
            reapplyIdentities()
            writeAssignmentToFiles(touched)
            app.status = "Asignado: \(t.horse) · \(t.rider)" + (extra > 0 ? " (y \(extra) entrenamiento(s) más)" : "")
        } catch {
            assignMessage = error.localizedDescription
        }
    }

    /// From the Cuadra/Jinetes page: give the selected record to every training without horse (or rider).
    func assignUnknownTo(_ p: StableIdentityPage) {
        guard let sel = p.selected else { return }
        let horse: Bool = p.isHorse
        let list: [SessionItem] = app.sessions.filter { !(horse ? $0.horseKnown : $0.riderKnown) }
        if list.isEmpty { return }
        let code: String = sel.code
        confirm = StableConfirm(
            title: p.title,
            message: "¿Asignar \(sel.name) a \(list.count) entrenamiento(s) sin \(p.singular)?\n\nSe puede cambiar después en cada entrenamiento («Asignar»). Los archivos no se modifican.",
            okLabel: "Asignar") { [weak self, weak p] in
                guard let self = self, let p = p else { return }
                do {
                    for s in list {
                        try self.store.assign(s.id, setHorse: horse, horseCode: horse ? code : nil,
                                              setRider: !horse, riderCode: horse ? nil : code)
                    }
                } catch {
                    p.message = error.localizedDescription
                    return
                }
                self.reapplyIdentities()
                self.writeAssignmentToFiles(list)
                p.select(code)
                p.message = "Asignado a \(list.count) entrenamiento(s)."
            }
    }

    /// Opens a training of the record in Análisis.
    func openTraining(_ s: SessionItem) {
        app.select(s)
        app.page = .analysis
    }
}
