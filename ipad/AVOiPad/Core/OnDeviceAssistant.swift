import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Modelo de lenguaje de Apple dentro del iPad (framework Foundation Models, iPadOS 26 con Apple Intelligence activado).
/// Gratis, sin conexión y sin clave. Es un modelo pequeño (unos 3 000 millones de parámetros y una ventana de contexto
/// corta), así que solo recibe el resumen de la sesión y sirve para explicaciones sencillas, no para análisis a fondo.
/// Con un SDK anterior a iOS 26 (CI de pruebas en macOS 15) este código compila sin el framework y `available` es false.
enum OnDeviceAssistant {
    /// Límite de caracteres del contexto que se manda al modelo de Apple (su ventana es de unos 4 000 tokens).
    static let maxContextChars: Int = 7_000

    static var available: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// Motivo legible cuando no está disponible.
    static var unavailableReason: String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return ""
            default: return "Apple Intelligence no está disponible o no está activado en Ajustes del iPad."
            }
        }
        #endif
        return "Necesita iPadOS 26 con Apple Intelligence."
    }

    static func respond(instructions: String, prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt)
            return response.content
        }
        #endif
        throw ClaudeError(message: unavailableReason)
    }
}
