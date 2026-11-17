import Foundation

/// Explicitly sourced marine snapshot; never infer observed tides from model predictions.
enum MarineMetadata {
    static func loadJson(_ session: TrainingSession, _ filename: String) throws {
        guard let raw = AvoFiles.read(filename) else { throw AvoError.notFound("No existe el archivo de datos marinos") }
        guard let root = AvoJSON.object(raw) else { throw AvoError.invalidData("Los datos marinos no son un JSON válido") }
        guard let source = AvoJSON.string(root, "source") else { throw AvoError.invalidData("Los datos marinos necesitan una fuente") }
        guard let kind = AvoJSON.string(root, "kind") else { throw AvoError.invalidData("Falta tipo de dato (prediccion/medicion/modelo)") }
        if kind != "prediccion" && kind != "medicion" && kind != "modelo" { throw AvoError.invalidData("Tipo marino no reconocido") }
        guard let observed = AvoJSON.string(root, "timestamp") else { throw AvoError.invalidData("Falta hora de referencia") }
        let hasZone = observed.hasSuffix("Z") || observed.range(of: #"[+-]\d{2}:\d{2}$"#, options: .regularExpression) != nil
        // A valid time without zone is reported as "missing zone" (as on Windows), an unparseable one as invalid.
        let when: Date? = hasZone ? DotNetDate.parse(observed) : DotNetDate.parse(observed + "Z")
        guard let instant = when else { throw AvoError.invalidData("Hora sin zona horaria o inválida") }
        if !hasZone { throw AvoError.invalidData("La hora marina debe contener zona horaria") }
        if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || source.utf16.count > 300 {
            throw AvoError.invalidData("Fuente vacía o excesivamente larga")
        }
        session.marineSource = source
        session.marineKind = kind
        session.marineObservedAt = instant
        session.tideHeightM = AvoJSON.number(root, "tideHeightM")
        session.windKmh = AvoJSON.number(root, "windKmh")
        session.waveHeightM = AvoJSON.number(root, "waveHeightM")
        session.marineNotes = AvoJSON.string(root, "notes")
    }
}
