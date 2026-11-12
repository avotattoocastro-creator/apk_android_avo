using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Avo.Windows.Core;

/// <summary>Horse and rider assigned to a training after recording (AVO-ASSIGN-1, docs/ASIGNACION_CABALLO.md).</summary>
public sealed record AvoAssignmentData(string? HorseCode, string HorseName, string? RiderCode, string RiderName, DateTimeOffset UpdatedUtc, string App);

/// <summary>
/// AVO-ASSIGN-1: the manifest of the .avo package is the source of truth for the identity of a training.
/// Reassigning rewrites ONLY manifest.json; the RAW segments are copied byte for byte (their SHA-256 never changes).
/// </summary>
public static class AvoAssignment
{
    public const int ManifestMax = 16384;

    /// <summary>The "asignacion" block of a manifest, or null if the file predates AVO-ASSIGN-1.</summary>
    public static AvoAssignmentData? Read(JsonElement root)
    {
        if (!root.TryGetProperty("asignacion", out var a) || a.ValueKind != JsonValueKind.Object) return null;
        static string? S(JsonElement e, string n) => e.TryGetProperty(n, out var v) && v.ValueKind == JsonValueKind.String && v.GetString() is { Length: > 0 } s ? s.Trim() : null;
        var when = S(a, "actualizadoUtc") is { } w && DateTimeOffset.TryParse(w, System.Globalization.CultureInfo.InvariantCulture,
            System.Globalization.DateTimeStyles.AssumeUniversal, out var t) ? t : DateTimeOffset.MinValue;
        string? hc = S(a, "horseCode"), hn = S(a, "horseName"), rc = S(a, "riderCode"), rn = S(a, "riderName");
        if (hc is null && hn is null && rc is null && rn is null) return null;
        return new AvoAssignmentData(hc, hn ?? hc ?? "", rc, rn ?? rc ?? "", when, S(a, "app") ?? "");
    }

    /// <summary>Engine option fragment ("asignacion":{…}) for avo_eq_analyse_ex, or null when nothing is known.</summary>
    public static string? EngineOption(string? horseCode, string? horseName, string? riderCode, string? riderName)
    {
        var o = new JsonObject();
        void Put(string k, string? v) { if (!string.IsNullOrWhiteSpace(v) && v != StableStore.Unknown) o[k] = v.Trim(); }
        Put("horseCode", horseCode); Put("horseName", horseName); Put("riderCode", riderCode); Put("riderName", riderName);
        return o.Count == 0 ? null : "\"asignacion\":" + o.ToJsonString();
    }

    /// <summary>
    /// Rewrites the identity in the manifest of <paramref name="avoPath"/>: top-level horseCode/horseName/riderCode/riderName
    /// and the "asignacion" block (keeping the RAW values in asignacion.raw). Written to a temporary file, verified (every
    /// segment byte-identical, manifest hashes unchanged) and then moved over the original.
    /// </summary>
    public static void Write(string avoPath, AvoAssignmentData a, string? rawHorse, string? rawRider)
    {
        var entries = new List<(string Name, byte[] Data)>();
        JsonNode manifest;
        using (var zip = ZipFile.OpenRead(avoPath))
        {
            var m = zip.GetEntry("manifest.json") ?? throw new InvalidDataException("Falta manifest.json");
            if (m.Length is < 1 or > ManifestMax) throw new InvalidDataException("Tamaño del manifiesto inválido");
            byte[] mb = ReadAll(m);
            int bom = mb.AsSpan().StartsWith(new byte[] { 0xEF, 0xBB, 0xBF }) ? 3 : 0;
            manifest = JsonNode.Parse(mb.AsSpan(bom)) ?? throw new InvalidDataException("Manifiesto vacío");
            if ((string?)manifest["format"] != "AVO-TRAINING-1") throw new InvalidDataException("Formato AVO no compatible");
            foreach (var e in zip.Entries)
                if (e.FullName != "manifest.json") entries.Add((e.FullName, ReadAll(e)));
        }
        string? sha = (string?)manifest["sha256"];
        string? hashes = manifest["segmentHashes"]?.ToJsonString();
        // the RAW values survive every reassignment: taken from an earlier block if there is one
        var old = manifest["asignacion"]?["raw"];
        string? keepHorse = (string?)old?["horseCode"] ?? rawHorse, keepRider = (string?)old?["riderCode"] ?? rawRider;
        static JsonNode? N(string? v) => string.IsNullOrWhiteSpace(v) ? null : JsonValue.Create(v.Trim());
        manifest["horseCode"] = a.HorseCode ?? ""; manifest["horseName"] = a.HorseName;
        manifest["riderCode"] = a.RiderCode ?? ""; manifest["riderName"] = a.RiderName;
        manifest["asignacion"] = new JsonObject
        {
            ["version"] = 1,
            ["horseCode"] = N(a.HorseCode), ["horseName"] = N(a.HorseName),
            ["riderCode"] = N(a.RiderCode), ["riderName"] = N(a.RiderName),
            ["actualizadoUtc"] = a.UpdatedUtc.UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ssZ", System.Globalization.CultureInfo.InvariantCulture),
            ["app"] = a.App,
            ["raw"] = new JsonObject { ["horseCode"] = N(keepHorse), ["riderCode"] = N(keepRider) },
        };
        byte[] newManifest = Encoding.UTF8.GetBytes(manifest.ToJsonString(new JsonSerializerOptions { WriteIndented = false }));
        if (newManifest.Length > ManifestMax) throw new InvalidDataException("El manifiesto resultante es demasiado grande");

        string tmp = avoPath + ".asignando";
        try
        {
            using (var fs = new FileStream(tmp, FileMode.Create, FileAccess.Write, FileShare.None))
            using (var zip = new ZipArchive(fs, ZipArchiveMode.Create))
            {
                Add(zip, "manifest.json", newManifest);   // manifest first, as Android, iPad and the USB download write it
                foreach (var (name, data) in entries) Add(zip, name, data);
            }
            // verify before replacing: every segment identical, hashes in the manifest untouched
            using (var check = ZipFile.OpenRead(tmp))
            {
                foreach (var (name, data) in entries)
                {
                    var e = check.GetEntry(name) ?? throw new InvalidDataException("Falta " + name + " en la copia");
                    if (!SHA256.HashData(ReadAll(e)).AsSpan().SequenceEqual(SHA256.HashData(data))) throw new InvalidDataException("La copia de " + name + " no coincide");
                }
                using var doc = JsonDocument.Parse(ReadAll(check.GetEntry("manifest.json")!));
                var r = doc.RootElement;
                string? sha2 = r.TryGetProperty("sha256", out var s2) ? s2.GetString() : null;
                string? hashes2 = r.TryGetProperty("segmentHashes", out var h2) ? JsonNode.Parse(h2.GetRawText())?.ToJsonString() : null;
                if (sha2 != sha || hashes2 != hashes) throw new InvalidDataException("Las huellas del manifiesto cambiaron");
            }
            File.Move(tmp, avoPath, overwrite: true);
        }
        finally { if (File.Exists(tmp)) File.Delete(tmp); }
    }

    private static void Add(ZipArchive zip, string name, byte[] data)
    {
        var e = zip.CreateEntry(name, CompressionLevel.Optimal);
        using var s = e.Open();
        s.Write(data);
    }

    private static byte[] ReadAll(ZipArchiveEntry e)
    {
        using var s = e.Open();
        using var ms = new MemoryStream();
        s.CopyTo(ms);
        return ms.ToArray();
    }
}
