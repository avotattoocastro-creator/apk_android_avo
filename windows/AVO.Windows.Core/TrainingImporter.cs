using System.IO.Compression;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Avo.Windows.Core;

public static class TrainingImporter
{
    private const long MaxCompressedBytes = 100L * 1024 * 1024;
    private const long MaxSegmentBytes = 50L * 1024 * 1024;
    public static TrainingSession Import(string path)
    {
        if (!File.Exists(path)) throw new FileNotFoundException("No existe el entrenamiento", path);
        if (new FileInfo(path).Length > MaxCompressedBytes) throw new InvalidDataException("Archivo de más de 100 MB");
        var result = new TrainingSession { SourceName = Path.GetFileName(path) };
        if (Path.GetExtension(path).Equals(".avr", StringComparison.OrdinalIgnoreCase))
        {
            using var stream = File.OpenRead(path);
            result.Segments.Add(RawReader.Scan(stream, result, Path.GetFileName(path), 0));
            result.HasRawTelemetry = true;
            result.Integrity = result.Segments.All(s => !s.Truncated) ? "CRC válido" : "RAW truncado (parcial)";
            return result;
        }
        if (!Path.GetExtension(path).Equals(".avo", StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Formato no compatible: se esperan archivos .avo o .avr");
        using var zip = ZipFile.OpenRead(path);
        if (zip.Entries.Count is < 2 or > 400) throw new InvalidDataException("Cantidad de entradas ZIP incorrecta");
        var manifestEntry = zip.GetEntry("manifest.json") ?? throw new InvalidDataException("Falta manifest.json");
        if (manifestEntry.Length is < 1 or > 16384) throw new InvalidDataException("Tamaño del manifiesto inválido");
        using var json = JsonDocument.Parse(ReadBounded(manifestEntry, 16384));
        var root = json.RootElement;
        if (String(root, "format") != "AVO-TRAINING-1") throw new InvalidDataException("Formato AVO no compatible");
        result.SessionId = String(root, "sessionId") ?? throw new InvalidDataException("Falta sessionId");
        if (result.SessionId.Length is < 3 or > 128 || result.SessionId.Contains('/') || result.SessionId.Contains('\\'))
            throw new InvalidDataException("ID de sesión inválido");
        result.Horse = String(root, "horseName") is { Length: > 0 } horse ? horse : "Sin identificar";
        result.Rider = String(root, "riderName") is { Length: > 0 } rider ? rider : "Sin identificar";
        result.DeclaredDistanceM = Number(root, "distanceM");
        result.DeclaredDurationS = Number(root, "durationS");
        result.DeclaredMaxSpeedMs = Number(root, "maxSpeedMs");
        var ts = Number(root, "startRtcMs");
        if (ts is > 946684800000 and < 4102444800000) result.StartedAt = DateTimeOffset.FromUnixTimeMilliseconds((long)ts);
        if (!root.TryGetProperty("segmentHashes", out var hashObject) || hashObject.ValueKind != JsonValueKind.Object)
            throw new InvalidDataException("Faltan las huellas SHA-256 por segmento");
        var hashes = hashObject.EnumerateObject().ToDictionary(x => x.Name, x => x.Value.GetString() ?? "", StringComparer.Ordinal);
        int declaredSegments = (int)(Number(root, "segments") ?? -1);
        var files = zip.Entries.Where(e => e.FullName != "manifest.json").OrderBy(e => e.FullName, StringComparer.Ordinal).ToList();
        if (files.Count == 0 || declaredSegments != files.Count || hashes.Count != files.Count)
            throw new InvalidDataException("El paquete tiene segmentos ausentes, duplicados o extra");
        long total = 0;
        int idx = 0;
        foreach (var entry in files)
        {
            if (!entry.FullName.StartsWith("segments/", StringComparison.Ordinal) ||
                !Regex.IsMatch(entry.FullName[9..], @"^[A-Za-z0-9_.-]{1,120}$") || entry.Length is < 1 or > MaxSegmentBytes)
                throw new InvalidDataException("Ruta o tamaño del segmento ZIP incorrecto");
            string name = entry.FullName[9..];
            if (!hashes.TryGetValue(name, out string? expected) || !Regex.IsMatch(expected, "^[a-fA-F0-9]{64}$"))
                throw new InvalidDataException($"No existe SHA-256 válido para {name}");
            total += entry.Length;
            if (total > MaxCompressedBytes) throw new InvalidDataException("Tamaño descomprimido excesivo");
            byte[] data = ReadBounded(entry, MaxSegmentBytes);
            var actual = Convert.ToHexString(SHA256.HashData(data));
            if (!actual.Equals(expected, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException($"Hash de {name} no coincide");
            if (name.EndsWith(".avr", StringComparison.OrdinalIgnoreCase))
            {
                using var stream = new MemoryStream(data, false);
                result.Segments.Add(RawReader.Scan(stream, result, name, idx));
                result.HasRawTelemetry = true;
            }
            else result.Segments.Add(new SegmentSummary(name, idx, data.Length, 0, 0, false, false, 0));
            idx++;
        }
        result.Integrity = result.Segments.Any(s => s.Truncated) ? "SHA válido · RAW parcial" : "SHA-256 verificado por segmento";
        return result;
    }
    private static string? String(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;
    private static double? Number(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.Number && value.TryGetDouble(out var number) && double.IsFinite(number) ? number : null;
    private static byte[] ReadBounded(ZipArchiveEntry entry, long max)
    {
        using var source = entry.Open();
        using var target = new MemoryStream();
        byte[] buffer = new byte[8192];
        long count = 0;
        while (true)
        {
            int read = source.Read(buffer);
            if (read <= 0) break;
            count += read;
            if (count > max) throw new InvalidDataException("ZIP descomprimido excede el límite");
            target.Write(buffer, 0, read);
        }
        if (count != entry.Length) throw new InvalidDataException("Tamaño descomprimido incorrecto");
        return target.ToArray();
    }
}
