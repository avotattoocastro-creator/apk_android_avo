using System.Globalization;
using System.Text;
using System.Text.Json;

namespace Avo.Windows.Core;

/// <summary>Explicitly sourced marine snapshot; never infer observed tides from model predictions.</summary>
public static class MarineMetadata
{
    public static void LoadJson(TrainingSession session, string filename)
    {
        using var document = JsonDocument.Parse(File.ReadAllText(filename, Encoding.UTF8));
        var root = document.RootElement;
        string source = GetString(root, "source") ?? throw new InvalidDataException("Los datos marinos necesitan una fuente");
        string kind = GetString(root, "kind") ?? throw new InvalidDataException("Falta tipo de dato (prediccion/medicion/modelo)");
        if (kind is not ("prediccion" or "medicion" or "modelo")) throw new InvalidDataException("Tipo marino no reconocido");
        string observed = GetString(root, "timestamp") ?? throw new InvalidDataException("Falta hora de referencia");
        if (!DateTimeOffset.TryParse(observed, CultureInfo.InvariantCulture, DateTimeStyles.None, out var when))
            throw new InvalidDataException("Hora sin zona horaria o inválida");
        if (!observed.EndsWith('Z') && !System.Text.RegularExpressions.Regex.IsMatch(observed, @"[+-]\d{2}:\d{2}$"))
            throw new InvalidDataException("La hora marina debe contener zona horaria");
        if (string.IsNullOrWhiteSpace(source) || source.Length > 300) throw new InvalidDataException("Fuente vacía o excesivamente larga");
        session.MarineSource = source;
        session.MarineKind = kind;
        session.MarineObservedAt = when;
        session.TideHeightM = Number(root, "tideHeightM");
        session.WindKmh = Number(root, "windKmh");
        session.WaveHeightM = Number(root, "waveHeightM");
        session.MarineNotes = GetString(root, "notes");
    }
    private static string? GetString(JsonElement item, string key) => item.TryGetProperty(key, out var element) && element.ValueKind == JsonValueKind.String ? element.GetString() : null;
    private static double? Number(JsonElement item, string key) => item.TryGetProperty(key, out var element) && element.ValueKind == JsonValueKind.Number && element.TryGetDouble(out var value) && double.IsFinite(value) ? value : null;
}
