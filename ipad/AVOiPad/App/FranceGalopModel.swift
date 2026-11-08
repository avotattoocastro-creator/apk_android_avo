import Foundation
import Observation
import WebKit

/// Horse found on a France Galop page (trainer / owner page) and what to do with it in the Cuadra.
struct FGScanItem: Identifiable, Equatable {
    var link: FGLink
    /// Cuadra horse code to link to; "" = ignore; FGScanItem.createNew = create it in the Cuadra.
    var target: String
    var id: String { link.href }
    static let createNew: String = "__nuevo__"
}

/// «France Galop» (full-screen): in-app browser on france-galop.com that reads horse sheets and trainer pages, links
/// them to the Cuadra horses and refreshes all of them on request (Core/FranceGalop.swift).
@Observable
final class FranceGalopModel {
    @ObservationIgnored unowned let app: AppModel
    @ObservationIgnored let store: FGStore
    @ObservationIgnored weak var webView: WKWebView? = nil
    @ObservationIgnored private var loadWaiter: CheckedContinuation<Void, Never>? = nil
    @ObservationIgnored private var queueTask: Task<Void, Never>? = nil

    var visible: Bool = false
    /// URL the browser must load (set by the model, observed by the web view).
    var requestURL: String = FranceGalop.home
    var requestId: Int = 0
    var currentURL: String = ""
    var loading: Bool = false
    var canGoBack: Bool = false
    var status: String = ""
    /// Last page read from the browser.
    var page: FGPage? = nil
    /// Horse of the Cuadra the sheet will be linked to.
    var linkTarget: String = ""
    var scan: [FGScanItem] = []
    var queueText: String = ""
    var busy: Bool = false
    var version: Int = 0

    init(app: AppModel) {
        self.app = app
        store = FGStore(root: app.paths.root)
    }

    // ---------------------------------------------------------------- open
    func open(horseCode: String? = nil) {
        page = nil
        scan = []
        status = ""
        linkTarget = horseCode ?? ""
        load(horseCode.flatMap { store.url($0) } ?? FranceGalop.home)
        visible = true
        if horseCode != nil && store.url(horseCode!) != nil {
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                await self.waitForLoad()
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                await self.readPage()
                if let c = horseCode, self.page?.isHorseSheet == true { self.saveSheet(to: c) }
            }
        }
    }

    func close() {
        stopQueue()
        visible = false
    }

    func load(_ url: String) {
        requestURL = url
        requestId += 1
    }

    var horses: [StableIdentityRow] { app.stable.horses.allRows.filter { !$0.record.demo } }

    func horseName(_ code: String) -> String { horses.first { $0.code == code }?.name ?? code }

    // ---------------------------------------------------------------- web view callbacks
    func didStart() { loading = true }

    func didFinish(_ w: WKWebView) {
        loading = false
        currentURL = w.url?.absoluteString ?? ""
        canGoBack = w.canGoBack
        let c = loadWaiter
        loadWaiter = nil
        c?.resume()
    }

    @ObservationIgnored private var waitToken: Int = 0

    @MainActor
    private func waitForLoad(timeoutS: Double = 25) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            if !loading && !currentURL.isEmpty && webView?.isLoading == false {
                c.resume()
                return
            }
            waitToken += 1
            let token: Int = waitToken
            loadWaiter = c
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeoutS * 1_000_000_000))
                guard let self = self, self.waitToken == token, let w = self.loadWaiter else { return }
                self.loadWaiter = nil
                w.resume()
            }
        }
    }

    // ---------------------------------------------------------------- read the page
    @MainActor
    func readPage() async {
        guard let w = webView else { status = "El navegador no está listo."; return }
        do {
            let r: Any? = try await w.evaluateJavaScript(FranceGalop.extractJS)
            guard let json = r as? String, let p = FranceGalop.parse(json) else {
                status = "No se pudo leer la página."
                return
            }
            page = p
            if p.isHorseSheet {
                if linkTarget.isEmpty, let m = match(p.title) { linkTarget = m }
                status = "Ficha leída: \(p.title) · \(p.facts.count) datos y \(p.tables.count) tablas."
            } else if !p.horseLinks.isEmpty {
                status = "\(p.horseLinks.count) caballos encontrados en esta página."
            } else {
                status = "No es una ficha de caballo ni una página con caballos. Busca el caballo o el entrenador en France Galop."
            }
        } catch {
            status = "No se pudo leer la página: " + error.localizedDescription
        }
    }

    /// Cuadra horse whose name matches (same letters, or one contained in the other).
    func match(_ name: String) -> String? {
        let k: String = FranceGalop.key(name)
        if k.isEmpty { return nil }
        if let h = horses.first(where: { FranceGalop.key($0.name) == k }) { return h.code }
        return horses.first(where: { let hk = FranceGalop.key($0.name); return hk.count >= 4 && (k.contains(hk) || hk.contains(k)) })?.code
    }

    // ---------------------------------------------------------------- link a sheet
    func saveSheet(to code: String) {
        guard let p = page, p.isHorseSheet else { status = "Abre antes la ficha del caballo en France Galop."; return }
        var target: String = code
        do {
            if target == FGScanItem.createNew {
                target = try createHorse(p.title, page: p)
            }
            try store.set(target, p)
            fillHorse(target, p)
            version += 1
            status = "Guardado en \(horseName(target)): \(p.facts.count) datos y \(p.tables.count) tablas de France Galop."
            app.log.info("francegalop", "ficha guardada", ["caballo": target, "url": p.url])
        } catch {
            status = "No se pudo guardar: " + error.localizedDescription
        }
    }

    /// Creates the horse in the Cuadra with the name, breed and year of the sheet. Returns its code.
    private func createHorse(_ name: String, page: FGPage?) throws -> String {
        let st: StableStore = app.stable.store
        let rec = IdentityRecord(code: try st.nextCode(.horse), name: name.trimmed, breed: page?.breedLabel ?? "",
                                 birthYear: page?.birthYear, notes: "Creado desde France Galop", origin: "France Galop")
        let code: String = try st.add(.horse, rec).code
        app.stable.reapplyIdentities()
        return code
    }

    /// Fills breed and year of birth of the Cuadra horse when they are empty (never overwrites what the user wrote).
    private func fillHorse(_ code: String, _ p: FGPage) {
        guard let rec = app.stable.store.horses.first(where: { $0.code == code }) else { return }
        let breed: String? = rec.breed.trimmed.isEmpty ? p.breedLabel : nil
        let year: Int? = rec.birthYear == nil ? p.birthYear : nil
        if breed == nil && year == nil { return }
        try? app.stable.store.update(.horse, code) { (r: IdentityRecord) -> Void in
            if let b = breed { r.breed = b }
            if let y = year { r.birthYear = y }
        }
        app.stable.reapplyIdentities()
    }

    func unlink(_ code: String) {
        try? store.unlink(code)
        version += 1
    }

    // ---------------------------------------------------------------- whole stable (trainer / owner page)
    func scanPage() {
        guard let p = page, !p.horseLinks.isEmpty else {
            status = "Abre la página del entrenador o del propietario (con la lista de sus caballos) y pulsa «Leer página»."
            return
        }
        scan = p.horseLinks.map { (l: FGLink) -> FGScanItem in
            let linked: String? = store.linked.first { $0.url == l.href }?.code
            return FGScanItem(link: l, target: linked ?? match(l.text) ?? "")
        }
        status = "\(scan.count) caballos: elige con qué caballo de la Cuadra va cada uno (o «Crear en la Cuadra») y pulsa «Vincular»."
    }

    func applyScan() {
        var n: Int = 0
        var created: Int = 0
        for it in scan where !it.target.isEmpty {
            do {
                var code: String = it.target
                if code == FGScanItem.createNew {
                    code = try createHorse(it.link.text, page: nil)
                    created += 1
                }
                try store.link(code, it.link.href)
                n += 1
            } catch {
                status = "Error al vincular \(it.link.text): " + error.localizedDescription
                return
            }
        }
        version += 1
        scan = []
        status = "\(n) caballos vinculados" + (created > 0 ? " (\(created) creados en la Cuadra)" : "") + ". Pulsa «Actualizar toda la cuadra» para leer sus fichas."
    }

    // ---------------------------------------------------------------- refresh every linked horse
    func updateAll() {
        let list = store.linked
        guard !list.isEmpty, !busy else {
            status = "No hay caballos vinculados con France Galop todavía."
            return
        }
        busy = true
        queueTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            var ok: Int = 0
            for (i, l) in list.enumerated() {
                if Task.isCancelled { break }
                self.queueText = "Leyendo \(i + 1) de \(list.count): \(self.horseName(l.code))…"
                self.load(l.url)
                try? await Task.sleep(nanoseconds: 400_000_000)
                await self.waitForLoad()
                try? await Task.sleep(nanoseconds: 2_500_000_000)   // the page fills its tables
                if Task.isCancelled { break }
                await self.readPage()
                if let p = self.page, p.isHorseSheet {
                    try? self.store.set(l.code, p)
                    self.fillHorse(l.code, p)
                    ok += 1
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)   // pause between horses
            }
            self.version += 1
            self.queueText = ""
            self.status = "Actualizados \(ok) de \(list.count) caballos desde France Galop."
            self.busy = false
            self.queueTask = nil
        }
    }

    func stopQueue() {
        queueTask?.cancel()
        queueTask = nil
        busy = false
        queueText = ""
    }
}
