import Foundation

/// Tarjeta personal AVO (la misma del Android): `avohorse://identity/user/AVO-XXXX-XXXX?v=1&name=…&k=<32 hex>`.
/// Port de core/.../identity/AvoUserCard.kt. La clave `k` solo sirve para entrar en Firebase; nunca se muestra ni se registra.
struct AvoUserCard: Equatable {
    let code: String
    let name: String
    let secret: String

    static let alphabet: String = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
    static let prefix: String = "avohorse://identity/user/"

    static func validCode(_ c: String) -> Bool {
        let p: [Substring] = c.split(separator: "-", omittingEmptySubsequences: false)
        guard p.count == 3, p[0] == "AVO", p[1].count == 4, p[2].count == 4 else { return false }
        return (p[1] + p[2]).allSatisfy { alphabet.contains($0) }
    }

    static func validSecret(_ k: String) -> Bool { k.count == 32 && k.allSatisfy { "0123456789abcdef".contains($0) } }

    init(code: String, name: String, secret: String) throws {
        let c: String = code.trimmingCharacters(in: .whitespaces).uppercased()
        let k: String = secret.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "").lowercased()
        guard AvoUserCard.validCode(c) else { throw AvoError.invalidData("Código de tarjeta no válido (AVO-XXXX-XXXX)") }
        guard AvoUserCard.validSecret(k) else { throw AvoError.invalidData("Clave de tarjeta no válida (32 caracteres 0-9 y a-f)") }
        self.code = c
        self.name = name.trimmingCharacters(in: .whitespaces)
        self.secret = k
    }

    /// Enlace completo de la tarjeta (el que comparte el Android en «Entrar en el iPad»).
    static func parse(_ uri: String) throws -> AvoUserCard {
        let u: String = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard u.hasPrefix(prefix) else { throw AvoError.invalidData("No es un enlace de tarjeta AVO (avohorse://identity/user/…)") }
        let rest: Substring = u.dropFirst(prefix.count)
        let code: String = String(rest.split(separator: "?", maxSplits: 1).first ?? "")
        var q: [String: String] = [:]
        if let qs = rest.split(separator: "?", maxSplits: 1).dropFirst().first {
            for kv in qs.split(separator: "&") {
                let p: [Substring] = kv.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let k: String = String(p[0]).removingPercentEncoding ?? String(p[0])
                let v: String = p.count > 1 ? (String(p[1]).removingPercentEncoding ?? String(p[1])) : ""
                q[k] = v
            }
        }
        guard q["v"] == "1" else { throw AvoError.invalidData("Versión de tarjeta no compatible") }
        return try AvoUserCard(code: code, name: q["name"] ?? "", secret: q["k"] ?? "")
    }

    var email: String { code.lowercased() + "@avo-cards.app" }
}

/// Firebase (proyecto avo-performance-horse-7be14, el mismo del Android) por REST, sin SDK ni dependencias:
/// Authentication (correo de la tarjeta + clave) y Realtime Database (lecturas y flujo de eventos «text/event-stream»).
/// Los valores son públicos (van dentro de cada app, igual que app/.../cloud/FirebaseConfig.kt); la seguridad la dan las
/// reglas de firebase/database.rules.json.
enum LiveFirebaseConfig {
    static let apiKey: String = "AIzaSyAjd0ZKXYWQgpCdq_mMyiQeJ-MUT47HOd0"
    static let databaseUrl: String = "https://avo-performance-horse-7be14-default-rtdb.europe-west1.firebasedatabase.app"
}

struct LiveFirebaseError: Error, LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

/// Una sesión en directo disponible: dueño (código AVO), nombre del dueño y su ficha.
struct LiveSessionRef: Identifiable, Equatable {
    var owner: String
    var ownerName: String
    var sid: String
    var meta: LiveMeta
    var id: String { owner + "/" + sid }
}

final class LiveFirebaseClient {
    private let session: URLSession
    private var card: AvoUserCard?
    private var idToken: String?
    private var refreshToken: String?
    private var expires: Date = .distantPast

    init(session: URLSession = .shared) { self.session = session }

    var signedInCode: String? { idToken == nil ? nil : card?.code }

    // ------------------------------------------------------------------ Authentication

    func signIn(_ c: AvoUserCard) async throws {
        card = c
        let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=\(LiveFirebaseConfig.apiKey)")!
        let body: [String: Any] = ["email": c.email, "password": c.secret, "returnSecureToken": true]
        let j: [String: Any] = try await postJSON(url, body)
        try takeTokens(j["idToken"], j["refreshToken"], j["expiresIn"])
    }

    func signOut() { card = nil; idToken = nil; refreshToken = nil; expires = .distantPast }

    /// Token válido (se renueva 5 min antes de caducar; la sesión de Firebase dura 1 h).
    func token() async throws -> String {
        if let t = idToken, Date() < expires.addingTimeInterval(-300) { return t }
        guard let r = refreshToken else {
            if let c = card { try await signIn(c); if let t = idToken { return t } }
            throw LiveFirebaseError("Entra con tu tarjeta AVO")
        }
        let url = URL(string: "https://securetoken.googleapis.com/v1/token?key=\(LiveFirebaseConfig.apiKey)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("grant_type=refresh_token&refresh_token=\(r)".utf8)
        let (data, resp) = try await session.data(for: req)
        let j: [String: Any] = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if (resp as? HTTPURLResponse)?.statusCode != 200 {
            idToken = nil; refreshToken = nil
            if let c = card { try await signIn(c); if let t = idToken { return t } }
            throw LiveFirebaseError(LiveFirebaseClient.authMessage(j))
        }
        try takeTokens(j["id_token"], j["refresh_token"], j["expires_in"])
        return idToken ?? ""
    }

    private func takeTokens(_ id: Any?, _ refresh: Any?, _ expiresIn: Any?) throws {
        guard let t = id as? String, !t.isEmpty else { throw LiveFirebaseError("Firebase no devolvió la sesión") }
        idToken = t
        refreshToken = refresh as? String
        let secs: Double = Double(expiresIn as? String ?? "") ?? (expiresIn as? NSNumber)?.doubleValue ?? 3600
        expires = Date().addingTimeInterval(secs)
    }

    private func postJSON(_ url: URL, _ body: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        let j: [String: Any] = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if (resp as? HTTPURLResponse)?.statusCode != 200 { throw LiveFirebaseError(LiveFirebaseClient.authMessage(j)) }
        return j
    }

    static func authMessage(_ j: [String: Any]) -> String {
        let m: String = ((j["error"] as? [String: Any])?["message"] as? String) ?? (j["error"] as? String) ?? "error desconocido"
        if m.contains("INVALID_LOGIN_CREDENTIALS") || m.contains("INVALID_PASSWORD") || m.contains("EMAIL_NOT_FOUND") {
            return "Tarjeta o clave incorrectas, o la tarjeta aún no se ha usado en el Android (Compartir)"
        }
        if m.contains("API_KEY") || m.contains("blocked") || m.contains("Android client") {
            return "Firebase rechaza la clave de la app para iPad (\(m)). Hay que añadir la app iOS en la consola de Firebase o quitar la restricción de la clave."
        }
        return "Firebase: \(m)"
    }

    // ------------------------------------------------------------------ Realtime Database

    private func dbURL(_ path: String, _ extra: String = "") async throws -> URL {
        let t: String = try await token()
        let p: String = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        guard let u = URL(string: "\(LiveFirebaseConfig.databaseUrl)/\(p).json?auth=\(t)\(extra)") else {
            throw LiveFirebaseError("Ruta no válida")
        }
        return u
    }

    func get(_ path: String, shallow: Bool = false) async throws -> Any? {
        let (data, resp) = try await session.data(from: try await dbURL(path, shallow ? "&shallow=true" : ""))
        let code: Int = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 || code == 403 { throw LiveFirebaseError("Sin permiso para leer \(path)") }
        if code != 200 { throw LiveFirebaseError("Firebase respondió \(code)") }
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    /// Sesiones en directo que puedo ver: las mías y las de quien me envía (grants ACCEPTED), sin terminar o de < 2 h.
    func liveSessions() async throws -> [LiveSessionRef] {
        guard let me = card?.code else { throw LiveFirebaseError("Entra con tu tarjeta AVO") }
        var owners: [(String, String)] = [(me, card?.name ?? me)]
        if let g = try? await get("grants/\(me)") as? [String: Any] {
            for (sender, v) in g {
                guard let d = v as? [String: Any], d["state"] as? String == "ACCEPTED" else { continue }
                owners.append((sender, d["senderName"] as? String ?? sender))
            }
        }
        var out: [LiveSessionRef] = []
        let now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
        for (owner, name) in owners {
            guard let keys = try? await get("live/\(owner)", shallow: true) as? [String: Any] else { continue }
            for sid in keys.keys {
                guard let m = try? await get("live/\(owner)/\(sid)/meta") as? [String: Any] else { continue }
                let meta = LiveMeta(json: m)
                if meta.expiresMs > 0 && meta.expiresMs < now { continue }
                if meta.isEnded && now - meta.updatedMs > 2 * 3600_000 { continue }
                out.append(LiveSessionRef(owner: owner, ownerName: name, sid: sid, meta: meta))
            }
        }
        return out.sorted { ($0.meta.isEnded ? 1 : 0, -$0.meta.startMs) < ($1.meta.isEnded ? 1 : 0, -$1.meta.startMs) }
    }

    /// Flujo de eventos de una sesión (`put`/`patch` con `path` y `data`). Termina al cancelar la tarea, o lanza si se
    /// corta; el modelo vuelve a conectar (con un token nuevo si caducó: evento `auth_revoked`).
    func stream(_ path: String, onEvent: @escaping (String, String, Any?) -> Void) async throws {
        var req = URLRequest(url: try await dbURL(path))
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 90   // Firebase manda keep-alive cada ~30 s
        let (bytes, resp) = try await session.bytes(for: req)
        let code: Int = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code != 200 { throw LiveFirebaseError(code == 401 || code == 403 ? "Sin permiso para ver este directo" : "Firebase respondió \(code)") }
        var event: String = ""
        for try await line in bytes.lines {
            if line.hasPrefix("event:") {
                event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                let payload: String = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                switch event {
                case "put", "patch":
                    guard let d = payload.data(using: .utf8),
                          let j = (try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed])) as? [String: Any] else { continue }
                    onEvent(event, j["path"] as? String ?? "/", j["data"] is NSNull ? nil : j["data"])
                case "auth_revoked":
                    idToken = nil
                    throw LiveFirebaseError("Sesión de Firebase renovada")
                case "cancel":
                    throw LiveFirebaseError("Sin permiso para ver este directo")
                default:
                    break
                }
            }
        }
    }
}
