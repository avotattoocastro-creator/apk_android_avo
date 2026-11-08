import SwiftUI
import WebKit

/// WKWebView driven by FranceGalopModel (requestURL / requestId) that reports navigation back to it.
struct FGWebView: UIViewRepresentable {
    let model: FranceGalopModel

    func makeCoordinator() -> Coordinator { Coordinator(model) }

    func makeUIView(context: Context) -> WKWebView {
        let w = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        w.navigationDelegate = context.coordinator
        w.allowsBackForwardNavigationGestures = true
        model.webView = w
        if let u = URL(string: model.requestURL) { w.load(URLRequest(url: u)) }
        context.coordinator.lastId = model.requestId
        return w
    }

    func updateUIView(_ w: WKWebView, context: Context) {
        if context.coordinator.lastId != model.requestId {
            context.coordinator.lastId = model.requestId
            if let u = URL(string: model.requestURL) { w.load(URLRequest(url: u)) }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let model: FranceGalopModel
        var lastId: Int = -1
        init(_ m: FranceGalopModel) { model = m }
        func webView(_ w: WKWebView, didStartProvisionalNavigation n: WKNavigation!) { model.didStart() }
        func webView(_ w: WKWebView, didFinish n: WKNavigation!) { model.didFinish(w) }
        func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { model.didFinish(w) }
        func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) {
            model.didFinish(w)
            model.status = "No se pudo abrir la página: " + e.localizedDescription
        }
    }
}

/// «France Galop» full screen: browser on the left, actions and what was read on the right.
struct FranceGalopView: View {
    @Environment(AppModel.self) private var app
    @Bindable var model: FranceGalopModel

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().overlay(Avo.line)
            HStack(spacing: 0) {
                FGWebView(model: model)
                Divider().overlay(Avo.line)
                ScrollView { panel.padding(14) }
                    .frame(width: 400)
                    .background(Avo.surface)
            }
        }
        .background(Avo.bg)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { model.close() } label: { Label("Cerrar", systemImage: "xmark") }
                .buttonStyle(.avoSecondary)
            Button { model.webView?.goBack() } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.avoSecondary).disabled(!model.canGoBack)
            Button { model.webView?.reload() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.avoSecondary)
            Button { model.load(FranceGalop.home) } label: { Label("Inicio", systemImage: "house") }
                .buttonStyle(.avoSecondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("FRANCE GALOP").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(Avo.silver)
                Text(model.currentURL).font(.caption2).foregroundStyle(Avo.textDim).lineLimit(1).truncationMode(.middle)
            }
            if model.loading { ProgressView().controlSize(.small) }
            Spacer(minLength: 8)
            Button {
                Task { @MainActor in await model.readPage() }
            } label: {
                Label("Leer página", systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(.avoPrimary)
            .disabled(model.loading || model.busy)
            .accessibilityIdentifier("fg.read")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Avo.headerBrush)
    }

    @ViewBuilder
    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Busca el caballo o al entrenador en France Galop, abre su página y pulsa «Leer página».")
                .font(.footnote).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            if !model.status.isEmpty {
                Text(model.status).font(.footnote).foregroundStyle(Avo.cyan).fixedSize(horizontal: false, vertical: true)
            }
            if !model.queueText.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.queueText).font(.footnote).foregroundStyle(Avo.text)
                    Spacer()
                    Button("Detener") { model.stopQueue() }.buttonStyle(.avoSecondary)
                }
            }
            if let p = model.page, p.isHorseSheet { sheetBox(p) }
            if let p = model.page, !p.horseLinks.isEmpty { stableBox(p) }
            AvoCard(title: "Toda la cuadra", subtitle: "\(model.store.linked.count) caballos vinculados con France Galop") {
                Button {
                    model.updateAll()
                } label: {
                    Label("Actualizar toda la cuadra", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.avoPrimary)
                .disabled(model.busy || model.store.linked.isEmpty)
                Text("Abre cada ficha vinculada, una a una y con pausas, y guarda sus datos, su carrera y sus actuaciones.")
                    .font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sheetBox(_ p: FGPage) -> some View {
        AvoCard(title: "Ficha: \(p.title)", subtitle: "\(p.facts.count) datos · \(p.tables.count) tablas") {
            ForEach(p.facts.prefix(8)) { (f: FGFact) in
                HStack(alignment: .top) {
                    Text(f.label).font(.caption).foregroundStyle(Avo.textDim).frame(width: 120, alignment: .leading)
                    Text(f.value).font(.caption).foregroundStyle(Avo.text).fixedSize(horizontal: false, vertical: true)
                }
            }
            Picker("Caballo de la Cuadra", selection: $model.linkTarget) {
                Text("Elige el caballo…").tag("")
                Text("➕ Crear «\(p.title)» en la Cuadra").tag(FGScanItem.createNew)
                ForEach(model.horses) { (h: StableIdentityRow) in Text(h.name).tag(h.code) }
            }
            .pickerStyle(.menu)
            Button {
                model.saveSheet(to: model.linkTarget)
            } label: {
                Label("Guardar en la Cuadra", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.avoPrimary)
            .disabled(model.linkTarget.isEmpty)
            .accessibilityIdentifier("fg.saveSheet")
        }
    }

    private func stableBox(_ p: FGPage) -> some View {
        AvoCard(title: "Caballos en esta página", subtitle: "\(p.horseLinks.count) enlaces a fichas de caballos") {
            if model.scan.isEmpty {
                Button {
                    model.scanPage()
                } label: {
                    Label("Vincular estos caballos con la Cuadra", systemImage: "link")
                }
                .buttonStyle(.avoSecondary)
            } else {
                ForEach($model.scan) { $it in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(it.link.text).font(.caption.weight(.semibold)).foregroundStyle(Avo.text)
                        Picker("", selection: $it.target) {
                            Text("No vincular").tag("")
                            Text("➕ Crear en la Cuadra").tag(FGScanItem.createNew)
                            ForEach(model.horses) { (h: StableIdentityRow) in Text(h.name).tag(h.code) }
                        }
                        .pickerStyle(.menu)
                    }
                    Divider().overlay(Avo.line)
                }
                Button {
                    model.applyScan()
                } label: {
                    Label("Vincular", systemImage: "link.badge.plus")
                }
                .buttonStyle(.avoPrimary)
            }
        }
    }
}

/// «France Galop» card of a horse in Cuadra: facts, career summary and performances read from its sheet.
struct FranceGalopHorseCard: View {
    let row: StableIdentityRow
    @Environment(AppModel.self) private var app

    var body: some View {
        let m: FranceGalopModel = app.franceGalop
        let _ = m.version
        let p: FGPage? = m.store.page(row.code)
        AvoCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("FRANCE GALOP · \(row.name.uppercased())")
                        .font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(Avo.silver)
                    Spacer()
                    if let p = p {
                        Text("Leído " + MadridTime.format(p.readAt, "dd/MM/yyyy HH:mm")).font(.caption2).foregroundStyle(Avo.textDim)
                    }
                    Button {
                        m.open(horseCode: row.code)
                    } label: {
                        Label(m.store.url(row.code) == nil ? "Buscar en France Galop" : "Actualizar", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.avoPrimary)
                    .accessibilityIdentifier("stable.franceGalop")
                    if m.store.url(row.code) != nil {
                        Button(role: .destructive) { m.unlink(row.code) } label: { Image(systemName: "link.badge.minus") }
                            .buttonStyle(.avoSecondary).foregroundStyle(Avo.bad)
                            .accessibilityLabel("Desvincular de France Galop")
                    }
                }
                if let p = p {
                    Text(p.title).font(.title3.weight(.semibold)).foregroundStyle(Avo.text)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 10, alignment: .topLeading)], alignment: .leading, spacing: 6) {
                        ForEach(p.facts) { (f: FGFact) in
                            HStack(alignment: .top, spacing: 6) {
                                Text(f.label).font(.caption).foregroundStyle(Avo.textDim)
                                Text(f.value).font(.caption.weight(.semibold)).foregroundStyle(Avo.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    ForEach(p.tables) { (t: FGTable) in FGTableView(table: t) }
                } else {
                    Text(m.store.url(row.code) == nil
                         ? "Sin vincular. Pulsa «Buscar en France Galop», abre la ficha de \(row.name) y pulsa «Leer página» y «Guardar en la Cuadra»."
                         : "Vinculado; pulsa «Actualizar» para leer su ficha.")
                        .font(.footnote).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A table read from France Galop (career summary, performances, engagements…), as it comes.
struct FGTableView: View {
    let table: FGTable

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !table.title.isEmpty {
                Text(table.title.uppercased()).font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.silver)
            }
            ScrollView(.horizontal, showsIndicators: true) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    if !table.headers.isEmpty {
                        GridRow {
                            ForEach(Array(table.headers.enumerated()), id: \.offset) { (_: Int, h: String) in
                                Text(h).font(.caption2.weight(.semibold)).foregroundStyle(Avo.textDim).lineLimit(2)
                            }
                        }
                        Divider().overlay(Avo.line)
                    }
                    ForEach(Array(table.rows.prefix(60).enumerated()), id: \.offset) { (_: Int, r: [String]) in
                        GridRow {
                            ForEach(Array(r.enumerated()), id: \.offset) { (_: Int, c: String) in
                                Text(c).font(.caption.monospacedDigit()).foregroundStyle(Avo.text).lineLimit(2)
                                    .frame(maxWidth: 260, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(8)
        .background(Avo.surface2, in: RoundedRectangle(cornerRadius: 7))
    }
}
