import SwiftUI
import WebKit
import UniformTypeIdentifiers

/// «Demostración» (27/11/2026, plan `docs/PLAN_MODO_DEMOSTRACION_IPAD.md`, primera versión):
/// caballo y jockey 3D con el casco prototipo A y la cincha, paquetes del sistema y el móvil con la sesión en directo.
/// Es la página web de `demo/avo-3d/web-3d` empaquetada en la app (carpeta de recursos `demo3d`, la monta el CI):
/// three.js va dentro de la app, así que funciona sin conexión. Los modelos de Enozone llegan cifrados al repositorio y el
/// CI los descifra con el secreto `AVO_ASSETS_3D_KEY`; si no están, se muestra la versión 2D de Muybridge (dominio público).
/// Telemetría SIMULADA: no lee el reloj ni el directo todavía (fase F3 del plan).
struct DemoView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                AvoPageTitle(title: "Demostración",
                             subtitle: DemoAssets.has3D
                                ? "Caballo y jockey 3D con el casco y la cincha AVO · datos SIMULADOS"
                                : "Galope real de Muybridge con el sistema AVO · datos SIMULADOS (faltan los modelos 3D en esta compilación)")
                Spacer()
            }
            if DemoAssets.root != nil {
                DemoWebView(start: DemoAssets.startURL)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .accessibilityIdentifier("demo.web")
            } else {
                AvoNoData(text: "Esta compilación no incluye la demostración (carpeta demo3d ausente).")
            }
        }
        .padding(16)
    }
}

/// Where the bundled demo lives and which page opens first.
enum DemoAssets {
    static let scheme = "avo-demo"
    static var root: URL? { Bundle.main.url(forResource: "demo3d", withExtension: nil) }
    static var has3D: Bool {
        guard let r = root else { return false }
        return FileManager.default.fileExists(atPath: r.appendingPathComponent("3d/modelos/modelos.zip").path)
    }
    static var startURL: URL { URL(string: "\(scheme)://local/\(has3D ? "3d" : "2d")/index.html")! }
}

/// WKWebView that serves the bundled `demo3d` folder through the `avo-demo://` scheme. A custom scheme (instead of
/// file://) gives the page a real origin, so ES modules, fetch() of the model zip and textures all load.
struct DemoWebView: UIViewRepresentable {
    let start: URL

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.setURLSchemeHandler(DemoSchemeHandler(), forURLScheme: DemoAssets.scheme)
        cfg.allowsInlineMediaPlayback = true
        let w = WKWebView(frame: .zero, configuration: cfg)
        w.isOpaque = false
        w.backgroundColor = .black
        w.scrollView.backgroundColor = .black
        w.load(URLRequest(url: start))
        return w
    }

    func updateUIView(_ w: WKWebView, context: Context) {}
}

/// Serves files from the `demo3d` bundle folder. Only paths inside that folder are answered.
final class DemoSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let root = DemoAssets.root?.standardizedFileURL else {
            task.didFailWithError(URLError(.badURL)); return
        }
        var rel = url.path
        while rel.hasPrefix("/") { rel.removeFirst() }
        if rel.isEmpty { rel = "2d/index.html" }
        let file = root.appendingPathComponent(rel).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf: file) else {
            let r = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/plain"])!
            task.didReceive(r); task.didReceive(Data("no encontrado".utf8)); task.didFinish(); return
        }
        let r = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                headerFields: ["Content-Type": DemoSchemeHandler.mime(file.pathExtension),
                                               "Content-Length": String(data.count),
                                               "Access-Control-Allow-Origin": "*"])!
        task.didReceive(r)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    static func mime(_ ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "json": return "application/json"
        case "css": return "text/css"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "zip": return "application/zip"
        default: return UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
        }
    }
}
