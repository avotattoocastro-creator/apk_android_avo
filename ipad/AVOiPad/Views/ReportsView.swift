import SwiftUI
import WebKit
import PDFKit
import UIKit

/// Reports and export (Windows Views/ReportsView.xaml): printable preview, real PDF/HTML/CSV/GPX/JSON written to
/// paths.root/exportaciones and handed to the share sheet (Files, AirDrop, Mail…).
struct ReportsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        let model: ReportsModel = app.reports
        @Bindable var m = model
        GeometryReader { geo in
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                FeatureSessionHeader()
                if hSize == .compact {
                    ReportsPreviewCard(model: model).frame(height: 620)
                    ReportsExportCard(model: model)
                    ReportsNotesCard(model: model)
                    ReportsOptionsCard(model: model)
                } else if geo.size.width < 1100 {
                    // iPad in portrait or Split View: preview on top, controls in two columns below
                    ReportsPreviewCard(model: model).frame(height: 640)
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 12) {
                            ReportsExportCard(model: model)
                            ReportsNotesCard(model: model)
                        }
                        ReportsOptionsCard(model: model).frame(width: 300)
                    }
                } else {
                    HStack(alignment: .top, spacing: 14) {
                        ReportsPreviewCard(model: model).frame(minWidth: 380, idealWidth: 460).frame(height: 760)
                        VStack(spacing: 12) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(spacing: 12) {
                                    ReportsExportCard(model: model)
                                    ReportsNotesCard(model: model)
                                }
                                ReportsOptionsCard(model: model).frame(width: 270)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        }
        .background(Avo.bg)
        .onAppear { model.pageShown() }
        .onDisappear { model.saveNotes() }
        .sheet(item: $m.shareFile) { (f: ExportedFile) in
            ReportsActivitySheet(url: f.url).ignoresSafeArea()
        }
    }
}

/// White page like the printed report: AVO header, title, DEMO mark, key rows and the HTML / PDF preview.
private struct ReportsPreviewCard: View {
    @Environment(AppModel.self) private var app
    var model: ReportsModel

    var body: some View {
        @Bindable var m = model
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("AVO").font(.system(size: 30, weight: .light)).foregroundStyle(Color(hex: 0x101014))
                VStack(alignment: .leading, spacing: 0) {
                    Text("PERFORMANCE HORSE").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(hex: 0x101014))
                    Text("Training analysis").font(.system(size: 10)).foregroundStyle(Color(hex: 0x5B5C63))
                }
                Spacer()
                Picker("Vista previa", selection: $m.previewMode) {
                    ForEach(ReportPreviewMode.allCases) { (p: ReportPreviewMode) in Text(p.rawValue).tag(p) }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }
            Rectangle().fill(Avo.red).frame(height: 3)
            Text(model.previewTitle).font(.system(size: 17, weight: .semibold)).foregroundStyle(Color(hex: 0x101014))
            if let s = app.selected, s.isSynthetic {
                Text("DEMOSTRACIÓN — DATOS SINTÉTICOS").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(hex: 0x7A5200))
                    .padding(.horizontal, 8).padding(.vertical, 4).background(Color(hex: 0xFFF1C9))
            }
            if !model.previewRows.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 2) {
                    ForEach(model.previewRows) { (r: FeatureKV) in
                        GridRow {
                            Text(r.key + ":").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: 0x101014))
                            Text(r.value).font(.system(size: 12)).foregroundStyle(Color(hex: 0x101014))
                        }
                    }
                }
            }
            ZStack {
                if app.selected == nil {
                    Text("Selecciona un entrenamiento.").font(.footnote).foregroundStyle(Color(hex: 0x5B5C63))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.previewMode == .html {
                    ReportsHtmlView(html: model.previewHtml)
                } else if let pdf = model.previewPdf {
                    ReportsPdfView(data: pdf)
                } else {
                    Color.white
                }
                if model.previewBusy {
                    ProgressView().tint(Color(hex: 0x101014))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(hex: 0xD8D9DE), lineWidth: 1))
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Avo.line, lineWidth: 1))
        .accessibilityIdentifier("reports.preview")
    }
}

private struct ReportsExportCard: View {
    @Environment(AppModel.self) private var app
    var model: ReportsModel

    private let columns: [GridItem] = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        AvoCard(title: "Exportar") {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(ReportExportKind.allCases) { (k: ReportExportKind) in
                    exportButton(k)
                }
                if let last = model.lastExport {
                    ShareLink(item: last.url) {
                        Label("Compartir último", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.avoSecondary)
                    .accessibilityIdentifier("reports.shareLast")
                }
            }
            .disabled(model.exporting)
            if model.exporting {
                HStack(spacing: 8) { ProgressView(); Text("Exportando…").font(.caption).foregroundStyle(Avo.textDim) }
            }
            if let last = model.lastExport {
                Text("Último: \(last.url.path)").font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            }
            Text("CSV y GPX exportan el intervalo seleccionado si hay uno; si no, la sesión completa. El PDF se genera internamente (sin dependencias externas).")
                .font(.caption).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
            if model.exports.count > 1 {
                Divider().background(Avo.line)
                Text("EXPORTACIONES ANTERIORES").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Avo.textDim)
                ForEach(model.exports.prefix(8)) { (f: ExportedFile) in
                    HStack {
                        Image(systemName: f.kind.icon).foregroundStyle(Avo.silver)
                        Text(f.name).font(.caption).foregroundStyle(Avo.text).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(f.time).font(.caption2).foregroundStyle(Avo.textDim)
                        ShareLink(item: f.url) { Image(systemName: "square.and.arrow.up") }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func exportButton(_ k: ReportExportKind) -> some View {
        let label = Label(k.title, systemImage: k.icon).lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity)
        if k == .pdf {
            Button { Task { await model.export(k) } } label: { label }
                .buttonStyle(.avoPrimary)
                .accessibilityIdentifier("reports.export.\(k.rawValue)")
        } else {
            Button { Task { await model.export(k) } } label: { label }
                .buttonStyle(.avoSecondary)
                .accessibilityIdentifier("reports.export.\(k.rawValue)")
        }
    }
}

private struct ReportsNotesCard: View {
    @Environment(AppModel.self) private var app
    var model: ReportsModel
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var m = model
        AvoCard(title: "Notas y observaciones") {
            TextEditor(text: $m.notesDraft)
                .focused($focused)
                .scrollContentBackground(.hidden)
                .foregroundStyle(Avo.text)
                .frame(height: 140)
                .padding(6)
                .background(Avo.surface2, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Avo.line, lineWidth: 1))
                .disabled(app.selected == nil)
                .accessibilityIdentifier("reports.notes")
            HStack {
                Spacer()
                Button("Guardar notas") { focused = false; model.saveNotes() }
                    .buttonStyle(.avoSecondary)
                    .disabled(app.selected == nil)
            }
        }
        .onChange(of: focused) { if !focused { model.saveNotes() } }
    }
}

private struct ReportsOptionsCard: View {
    var model: ReportsModel

    var body: some View {
        @Bindable var m = model
        AvoCard(title: "Opciones del informe") {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Datos generales", isOn: $m.general)
                Toggle("Caballo y jinete", isOn: $m.horseRider)
                Toggle("Fecha y duración", isOn: $m.date)
                Toggle("Mapa del recorrido", isOn: $m.map)
                Toggle("Datos GPS", isOn: $m.gnss)
                Toggle("Velocidades y aceleraciones", isOn: $m.speed)
                Toggle("Gráficas", isOn: $m.charts)
                Toggle("Tramos", isOn: $m.segments)
                Toggle("Biomecánica", isOn: $m.biomech)
                Toggle("Comparativas (sesiones marcadas)", isOn: $m.compare)
                Toggle("Mareas y entorno", isOn: $m.tides)
                Toggle("Análisis IA (asistente y tramos)", isOn: $m.aiSection)
                Toggle("Notas y observaciones", isOn: $m.notesSection)
            }
            .toggleStyle(.switch)
            .tint(Avo.red)
            .font(.callout)
            .foregroundStyle(Avo.text)
            Text("Mareas y entorno: solo si se han consultado en la página Mareas para esta sesión.")
                .font(.caption2).foregroundStyle(Avo.textDim).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - UIKit bridges

/// Printable HTML preview (the same HTML that is exported).
private struct ReportsHtmlView: UIViewRepresentable {
    var html: String

    final class Coordinator {
        var lastHtml: String = ""
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.isOpaque = false
        v.backgroundColor = .white
        return v
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.lastHtml == html { return }
        context.coordinator.lastHtml = html
        uiView.loadHTMLString(html, baseURL: nil)
    }
}

/// PDF preview with PDFKit (the PDF written by the app's own PdfDocument).
private struct ReportsPdfView: UIViewRepresentable {
    var data: Data

    final class Coordinator {
        var lastData: Data? = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.backgroundColor = UIColor(white: 0.93, alpha: 1)
        return v
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if context.coordinator.lastData == data { return }
        context.coordinator.lastData = data
        uiView.document = PDFKit.PDFDocument(data: data)
    }
}

/// Share sheet for an exported file (Save to Files, AirDrop, Mail…).
struct ReportsActivitySheet: UIViewControllerRepresentable {
    var url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
