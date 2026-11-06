import Foundation
import Security

// MARK: - Modelos de Claude

/// Modelos de Claude que ofrece el «Asistente IA». Precios de lista en USD por millón de tokens (noviembre de 2026;
/// Haiku 5.5 con prompts de hasta 100 000 tokens). Solo sirven para ESTIMAR el gasto en la app: el gasto real es el de
/// Claude Console (platform.claude.com › Gasto).
enum ClaudeModel: String, CaseIterable, Identifiable {
    case sonnet = "claude-sonnet-5-5"
    case haiku = "claude-haiku-5-5"
    case opus = "claude-opus-5-5"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sonnet: return "Sonnet 5.5"
        case .haiku: return "Haiku 5.5"
        case .opus: return "Opus 5.5"
        }
    }

    var detail: String {
        switch self {
        case .sonnet: return "Recomendado: buen análisis a coste moderado"
        case .haiku: return "Muy rápido y muy barato, análisis más sencillo"
        case .opus: return "El más profundo; gasta los créditos unas 2 veces más rápido que Sonnet"
        }
    }

    /// USD por millón de tokens: entrada, salida, escritura en caché y lectura de caché.
    var price: (input: Double, output: Double, cacheWrite: Double, cacheRead: Double) {
        switch self {
        case .sonnet: return (2.0, 10.0, 2.5, 0.10)
        case .haiku: return (0.10, 0.50, 0.125, 0.01)
        case .opus: return (4.0, 20.0, 5.0, 0.40)
        }
    }
}

/// Tokens de una respuesta (bloque `usage` de la API).
struct ClaudeUsage {
    var input: Int = 0
    var output: Int = 0
    var cacheWrite: Int = 0
    var cacheRead: Int = 0

    func costUSD(_ m: ClaudeModel) -> Double {
        let p = m.price
        return (Double(input) * p.input + Double(output) * p.output + Double(cacheWrite) * p.cacheWrite
                + Double(cacheRead) * p.cacheRead) / 1_000_000.0
    }

    var totalTokens: Int { input + output + cacheWrite + cacheRead }
}

enum ClaudeStreamEvent {
    case text(String)
    case done(stopReason: String, usage: ClaudeUsage)
}

struct ClaudeError: LocalizedError {
    var message: String
    var status: Int = 0
    var errorDescription: String? { message }

    /// Mensaje claro en español a partir del código HTTP y del cuerpo de error de la API.
    static func from(status: Int, body: Data) -> ClaudeError {
        var apiMessage: String = ""
        var apiType: String = ""
        if let o = try? JSONSerialization.jsonObject(with: body) as? [String: Any], let e = o["error"] as? [String: Any] {
            apiMessage = (e["message"] as? String) ?? ""
            apiType = (e["type"] as? String) ?? ""
        }
        let low: String = apiMessage.lowercased()
        let text: String
        switch status {
        case 401: text = "La clave de API no es válida o se ha revocado. Créala de nuevo en Claude Console."
        case 403: text = "La clave no tiene permiso para este modelo o espacio de trabajo."
        case 429: text = "Demasiadas peticiones seguidas o límite de gasto del espacio de trabajo alcanzado. Espera un momento."
        case 529: text = "Los servidores de Claude están saturados. Prueba de nuevo en unos minutos."
        case 400 where low.contains("credit"):
            text = "No quedan créditos de API este mes. Los 100 $ del plan Max se renuevan cada mes."
        default:
            text = apiMessage.isEmpty ? "Error \(status) de la API de Claude" : "Error \(status): \(apiMessage)"
        }
        return ClaudeError(message: text + (apiType.isEmpty || status == 401 ? "" : " [\(apiType)]"), status: status)
    }
}

// MARK: - Llavero

/// Clave de API de Claude guardada en el Llavero de iOS (cifrada, solo en este iPad, nunca en copias de iCloud).
/// La clave NO está en el código ni en el repositorio: la pega el usuario en Ajustes del Asistente IA.
enum AvoKeychain {
    static let service: String = "org.avoperformance.horse.claude"
    static let apiKeyAccount: String = "anthropic-api-key"

    static func read(_ account: String = apiKeyAccount) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef? = nil
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        let s: String = String(decoding: d, as: UTF8.self)
        return s.isEmpty ? nil : s
    }

    @discardableResult
    static func write(_ value: String, _ account: String = apiKeyAccount) -> Bool {
        delete(account)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account,
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                kSecValueData as String: Data(value.utf8)]
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ account: String = apiKeyAccount) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
    }
}

// MARK: - Cliente de la API de mensajes

/// Cliente mínimo de la API de mensajes de Claude (https://api.anthropic.com/v1/messages) con respuesta en streaming.
/// Llama directamente desde el iPad con la clave del Llavero. Más adelante puede apuntar al Servidor AVO cambiando
/// `endpoint` y quitando la clave.
struct ClaudeClient {
    static let endpoint: URL = URL(string: "https://api.anthropic.com/v1/messages")!
    static let apiVersion: String = "2023-06-01"

    var apiKey: String
    var endpoint: URL = ClaudeClient.endpoint

    /// Forma básica de la clave (sk-ant-…). No garantiza que sea válida: eso lo dice «Probar conexión».
    static func looksLikeKey(_ k: String) -> Bool {
        let t: String = k.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.hasPrefix("sk-ant-") && t.count >= 40 && !t.contains(" ")
    }

    private func request(_ body: [String: Any]) throws -> URLRequest {
        var r = URLRequest(url: endpoint)
        r.httpMethod = "POST"
        r.timeoutInterval = 300
        r.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        r.setValue(ClaudeClient.apiVersion, forHTTPHeaderField: "anthropic-version")
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        return r
    }

    /// Petición pequeña sin streaming para comprobar la clave. Devuelve el texto de la respuesta.
    func test(model: ClaudeModel) async throws -> (text: String, usage: ClaudeUsage) {
        let body: [String: Any] = ["model": model.rawValue, "max_tokens": 32,
                                   "messages": [["role": "user", "content": "Responde solo: Conexión correcta"]]]
        let (data, resp) = try await URLSession.shared.data(for: try request(body))
        let status: Int = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status != 200 { throw ClaudeError.from(status: status, body: data) }
        guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeError(message: "Respuesta inesperada de la API")
        }
        var text: String = ""
        for b in (o["content"] as? [[String: Any]]) ?? [] where (b["type"] as? String) == "text" {
            text += (b["text"] as? String) ?? ""
        }
        return (text, ClaudeClient.usage(o["usage"] as? [String: Any], into: ClaudeUsage()))
    }

    /// Mensaje con streaming (SSE). `system` son bloques de texto (el último puede llevar `cache_control`).
    func stream(model: ClaudeModel, system: [[String: Any]], messages: [[String: Any]],
                maxTokens: Int) -> AsyncThrowingStream<ClaudeStreamEvent, Error> {
        let body: [String: Any] = ["model": model.rawValue, "max_tokens": maxTokens, "stream": true,
                                   "system": system, "messages": messages]
        return AsyncThrowingStream { (cont: AsyncThrowingStream<ClaudeStreamEvent, Error>.Continuation) in
            let task = Task {
                do {
                    let (bytes, resp) = try await URLSession.shared.bytes(for: try request(body))
                    let status: Int = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    if status != 200 {
                        var d = Data()
                        for try await b in bytes { d.append(b); if d.count > 64_000 { break } }
                        throw ClaudeError.from(status: status, body: d)
                    }
                    var usage = ClaudeUsage()
                    var stop: String = ""
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard line.hasPrefix("data:") else { continue }
                        let payload: String = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        guard let d = payload.data(using: .utf8),
                              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
                        switch (o["type"] as? String) ?? "" {
                        case "message_start":
                            usage = ClaudeClient.usage((o["message"] as? [String: Any])?["usage"] as? [String: Any], into: usage)
                        case "content_block_delta":
                            if let delta = o["delta"] as? [String: Any], (delta["type"] as? String) == "text_delta",
                               let t = delta["text"] as? String {
                                cont.yield(.text(t))
                            }
                        case "message_delta":
                            if let delta = o["delta"] as? [String: Any], let s = delta["stop_reason"] as? String { stop = s }
                            usage = ClaudeClient.usage(o["usage"] as? [String: Any], into: usage)
                        case "error":
                            let e = o["error"] as? [String: Any]
                            throw ClaudeError(message: "Error de la API: " + ((e?["message"] as? String) ?? "desconocido"))
                        default:
                            break
                        }
                    }
                    cont.yield(.done(stopReason: stop, usage: usage))
                    cont.finish()
                } catch {
                    cont.finish(throwing: error)
                }
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }

    /// Mezcla un bloque `usage` (los campos que trae; `message_delta` solo trae la salida acumulada).
    static func usage(_ u: [String: Any]?, into base: ClaudeUsage) -> ClaudeUsage {
        guard let u = u else { return base }
        var r = base
        if let v = u["input_tokens"] as? Int { r.input = v }
        if let v = u["output_tokens"] as? Int { r.output = v }
        if let v = u["cache_creation_input_tokens"] as? Int { r.cacheWrite = v }
        if let v = u["cache_read_input_tokens"] as? Int { r.cacheRead = v }
        return r
    }
}

// MARK: - Datos para el asistente

/// Compacta el JSON del motor para mandarlo a Claude sin gastar tokens de más: quita las series temporales, resume las
/// listas largas de números (n, mín., máx., media) y recorta las listas largas de objetos; redondea los decimales.
enum AssistantJSON {
    static func compact(_ json: String, dropKeys: Set<String> = ["series"], maxArray: Int = 24) -> String {
        guard let d = json.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) else { return "" }
        let c: Any = compact(o, dropKeys: dropKeys, maxArray: maxArray, depth: 0)
        guard JSONSerialization.isValidJSONObject(c),
              let out = try? JSONSerialization.data(withJSONObject: c, options: [.withoutEscapingSlashes]) else { return "" }
        return String(decoding: out, as: UTF8.self)
    }

    private static func compact(_ v: Any, dropKeys: Set<String>, maxArray: Int, depth: Int) -> Any {
        if let o = v as? [String: Any] {
            var r: [String: Any] = [:]
            for (k, x) in o where !(depth == 0 && dropKeys.contains(k)) {
                r[k] = compact(x, dropKeys: dropKeys, maxArray: maxArray, depth: depth + 1)
            }
            return r
        }
        if let a = v as? [Any] {
            if a.count > maxArray {
                let nums: [Double] = a.compactMap { number($0) }
                if nums.count == a.count {
                    let finite: [Double] = nums.filter { $0.isFinite }
                    var s: [String: Any] = ["n": a.count]
                    if let mn = finite.min(), let mx = finite.max() {
                        s["min"] = round(mn); s["max"] = round(mx)
                        s["media"] = round(finite.reduce(0, +) / Double(finite.count))
                    }
                    return ["_lista_resumida": s]
                }
                var r: [Any] = a.prefix(maxArray - 4).map { compact($0, dropKeys: dropKeys, maxArray: maxArray, depth: depth + 1) }
                r.append(["_omitidos": a.count - (maxArray - 1)])
                r.append(contentsOf: a.suffix(3).map { compact($0, dropKeys: dropKeys, maxArray: maxArray, depth: depth + 1) })
                return r
            }
            return a.map { compact($0, dropKeys: dropKeys, maxArray: maxArray, depth: depth + 1) }
        }
        if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), CFNumberIsFloatType(n as CFNumber) {
            let x: Double = n.doubleValue
            return x.isFinite ? round(x) : NSNull()
        }
        return v
    }

    private static func number(_ v: Any) -> Double? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.doubleValue
    }

    /// 4 cifras significativas como máximo (3 decimales para valores pequeños).
    static func round(_ x: Double) -> Double {
        let a: Double = abs(x)
        let decimals: Double = a >= 1000 ? 1 : (a >= 100 ? 2 : 3)
        let k: Double = pow(10, decimals)
        return (x * k).rounded() / k
    }
}
