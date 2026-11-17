import SwiftUI
import PDFKit

/// PDF over any page (Informe IA, informe completo from Cuadra): PDFKit view + «Compartir» (Files, AirDrop, Mail…).
struct PdfViewerSheet: View {
    let file: ExportedFile
    @Environment(\.dismiss) private var dismiss
    @State private var sharing: Bool = false

    var body: some View {
        NavigationStack {
            PdfFileView(url: file.url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(file.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cerrar") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button { sharing = true } label: { Label("Compartir", systemImage: "square.and.arrow.up") }
                    }
                }
        }
        .sheet(isPresented: $sharing) {
            ReportsActivitySheet(url: file.url)
        }
    }
}

private struct PdfFileView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.backgroundColor = UIColor(white: 0.93, alpha: 1)
        v.document = PDFKit.PDFDocument(url: url)
        return v
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url { uiView.document = PDFKit.PDFDocument(url: url) }
    }
}
