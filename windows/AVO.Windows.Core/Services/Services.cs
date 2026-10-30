using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Avo.Windows.Core;

/// <summary>Per-user folders. Nothing is written next to the original training files.</summary>
public sealed class AppPaths
{
    public string Root { get; }
    public AppPaths(string? root = null)
    {
        Root = root ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AVO Performance Horse", "Windows");
    }
    public string Library => Path.Combine(Root, "biblioteca");
    public string Segments => Path.Combine(Root, "tramos");
    public string Analysis => Path.Combine(Root, "analisis");
    public string EnvironmentCache => Path.Combine(Root, "entorno");
    public string Tiles => Path.Combine(Root, "teselas");
    public string Logs => Path.Combine(Root, "registros");
    public string Notes => Path.Combine(Root, "notas");
    public string SettingsFile => Path.Combine(Root, "ajustes.json");
    public string LibraryIndex => Path.Combine(Root, "biblioteca.json");
}

/// <summary>Structured JSON-lines log (one file per day) for debugging. Never logs credentials or file contents.</summary>
public sealed class AppLog
{
    private readonly string _dir;
    private readonly object _gate = new();
    public static AppLog? Current { get; set; }
    public AppLog(string dir) { _dir = dir; }

    public void Write(string level, string area, string message, Exception? ex = null, object? data = null)
    {
        try
        {
            Directory.CreateDirectory(_dir);
            var entry = new Dictionary<string, object?>
            {
                ["ts"] = DateTimeOffset.UtcNow.ToString("O"), ["nivel"] = level, ["area"] = area, ["mensaje"] = message,
                ["excepcion"] = ex is null ? null : $"{ex.GetType().Name}: {ex.Message}", ["datos"] = data,
            };
            string line = JsonSerializer.Serialize(entry);
            lock (_gate) File.AppendAllText(Path.Combine(_dir, $"avo-windows-{DateTime.UtcNow:yyyyMMdd}.log"), line + "\n", new UTF8Encoding(false));
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }
    public void Info(string area, string message, object? data = null) => Write("INFO", area, message, null, data);
    public void Warn(string area, string message, Exception? ex = null) => Write("AVISO", area, message, ex);
    public void Error(string area, string message, Exception? ex = null) => Write("ERROR", area, message, ex);
}

public enum MapProvider { EsriSatellite, EsriHybrid, VectorOffline }

/// <summary>User settings (no secrets: NTRIP credentials, tokens or keys are never stored by the Windows app).</summary>
public sealed class AppSettings
{
    public MapProvider Map { get; set; } = MapProvider.EsriSatellite;
    public double PlaceLatitude { get; set; } = TrainingPlace.Regaton.Latitude;
    public double PlaceLongitude { get; set; } = TrainingPlace.Regaton.Longitude;
    public string PlaceName { get; set; } = TrainingPlace.Regaton.Name;
    public string? TidePortId { get; set; }
    public bool OnlineEnvironment { get; set; } = true;
    public string ServerUrl { get; set; } = "https://live.avoperformance.org";
    public double JerkDensity { get; set; } = 4.0;

    private static readonly JsonSerializerOptions Json = new() { WriteIndented = true, Converters = { new JsonStringEnumConverter() } };

    public static AppSettings Load(string file)
    {
        try { return File.Exists(file) ? JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(file), Json) ?? new() : new(); }
        catch (JsonException) { return new(); }
    }

    public void Save(string file)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(file)!);
        File.WriteAllText(file + ".tmp", JsonSerializer.Serialize(this, Json));
        File.Move(file + ".tmp", file, true);
    }
}

/// <summary>Entry of the local library index: the verified copy of each imported file (content addressed by SHA-256).</summary>
public sealed class LibraryEntry
{
    public string Sha256 { get; set; } = "";
    public string SessionId { get; set; } = "";
    public string OriginalName { get; set; } = "";
    public string StoredPath { get; set; } = "";
    public DateTimeOffset ImportedUtc { get; set; }
}

public sealed record ImportOutcome(TrainingSession? Session, string File, string Status, bool Duplicate, string? Error);

/// <summary>
/// Imports .avo/.avr files into a local library: validates first (TrainingImporter), then copies the file unchanged into
/// the library (name = SHA-256) so the original stays untouched and the session survives if the source is moved.
/// Duplicates are detected by file SHA-256 and by session id.
/// </summary>
public sealed class TrainingLibrary
{
    private readonly AppPaths _paths;
    private readonly List<LibraryEntry> _entries;
    private static readonly JsonSerializerOptions Json = new() { WriteIndented = true };
    public IReadOnlyList<LibraryEntry> Entries => _entries;

    public TrainingLibrary(AppPaths paths)
    {
        _paths = paths;
        try { _entries = File.Exists(paths.LibraryIndex) ? JsonSerializer.Deserialize<List<LibraryEntry>>(File.ReadAllText(paths.LibraryIndex), Json) ?? [] : []; }
        catch (JsonException) { _entries = []; }
    }

    public static string FileSha256(string path)
    {
        using var f = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(f)).ToLowerInvariant();
    }

    public ImportOutcome Import(string path, IReadOnlyCollection<string> loadedSessionIds)
    {
        string? created = null;
        try
        {
            string sha = FileSha256(path);
            var existing = _entries.FirstOrDefault(e => e.Sha256 == sha && File.Exists(e.StoredPath));
            if (existing is not null)
            {
                var again = TrainingImporter.Import(existing.StoredPath);
                again.FileSha256 = sha; again.SourcePath = path; again.SourceName = existing.OriginalName;
                return new ImportOutcome(again, path, "Ya estaba en la biblioteca (mismo SHA-256)", true, null);
            }
            Directory.CreateDirectory(_paths.Library);
            string stored = Path.Combine(_paths.Library, sha + Path.GetExtension(path).ToLowerInvariant());
            if (!File.Exists(stored)) { File.Copy(path, stored, false); created = stored; }
            if (FileSha256(stored) != sha) throw new IOException("La copia de la biblioteca no coincide con el original");
            var session = TrainingImporter.Import(stored);
            session.FileSha256 = sha;
            session.SourcePath = path;
            session.SourceName = Path.GetFileName(path);
            bool dupId = loadedSessionIds.Contains(session.SessionId) || _entries.Any(e => e.SessionId == session.SessionId);
            _entries.RemoveAll(e => e.Sha256 == sha);
            _entries.Add(new LibraryEntry { Sha256 = sha, SessionId = session.SessionId, OriginalName = Path.GetFileName(path), StoredPath = stored, ImportedUtc = DateTimeOffset.UtcNow });
            SaveIndex();
            created = null;
            return new ImportOutcome(session, path, dupId ? "Importado (otra copia de una sesión ya existente)" : "Importado y verificado", dupId, null);
        }
        catch (Exception ex) when (ex is InvalidDataException or IOException or UnauthorizedAccessException or JsonException)
        {
            if (created is not null) { try { File.Delete(created); } catch (IOException) { } }
            return new ImportOutcome(null, path, "Rechazado", false, ex.Message);
        }
    }

    public IEnumerable<string> StoredFiles() => _entries.Where(e => File.Exists(e.StoredPath)).Select(e => e.StoredPath);

    public void Remove(string sha)
    {
        _entries.RemoveAll(e => e.Sha256 == sha);
        SaveIndex();
    }

    private void SaveIndex()
    {
        Directory.CreateDirectory(_paths.Root);
        File.WriteAllText(_paths.LibraryIndex + ".tmp", JsonSerializer.Serialize(_entries, Json));
        File.Move(_paths.LibraryIndex + ".tmp", _paths.LibraryIndex, true);
    }
}

// ------------------------------------------------------------------------------------------------ AVO server
public enum ServerState { NotConfigured, ContractPending, Connected, Error }

public sealed record RemoteSession(string Id, string Horse, string Rider, DateTimeOffset? Start, string? Sha256, long? SizeBytes);

/// <summary>
/// Contract the Windows app needs from the AVO server. No implementation talks to live.avoperformance.org yet because no
/// endpoint, authentication scheme or response format has been documented or validated (core/server/ServerApi.kt is
/// "ON HOLD"). Endpoints must not be invented: see windows/docs/SERVIDOR_CONTRATO_PENDIENTE.md.
/// </summary>
public interface IAvoServerClient
{
    ServerState State { get; }
    string StatusText { get; }
    Task<IReadOnlyList<RemoteSession>> ListSessionsAsync(CancellationToken ct);
    Task<string> DownloadAsync(RemoteSession session, string targetDirectory, IProgress<double>? progress, CancellationToken ct);
}

public sealed class PendingContractServerClient : IAvoServerClient
{
    public ServerState State => ServerState.ContractPending;
    public string StatusText => "No conectado: el servidor AVO no tiene todavía un contrato de API validado (sesiones, autenticación y descargas). Disponible: abrir el panel web y descargar manualmente un .avo por HTTPS.";
    public Task<IReadOnlyList<RemoteSession>> ListSessionsAsync(CancellationToken ct) => throw new NotSupportedException(StatusText);
    public Task<string> DownloadAsync(RemoteSession session, string targetDirectory, IProgress<double>? progress, CancellationToken ct) => throw new NotSupportedException(StatusText);
}

/// <summary>Manual HTTPS download of a .avo package with a size limit and resumable progress reporting.</summary>
public static class HttpsDownloader
{
    public const long MaxBytes = 100L * 1024 * 1024;

    public static async Task<string> DownloadAvoAsync(Uri url, string targetDirectory, IProgress<double>? progress, CancellationToken ct, HttpClient? client = null)
    {
        if (url.Scheme != Uri.UriSchemeHttps) throw new InvalidDataException("Solo se admiten enlaces HTTPS");
        if (!url.AbsolutePath.EndsWith(".avo", StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("El enlace debe apuntar a un archivo .avo");
        var http = client ?? new HttpClient { Timeout = TimeSpan.FromSeconds(120) };
        Directory.CreateDirectory(targetDirectory);
        string temp = Path.Combine(targetDirectory, Guid.NewGuid().ToString("N") + ".part");
        try
        {
            using var response = await http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, ct);
            response.EnsureSuccessStatusCode();
            long? len = response.Content.Headers.ContentLength;
            if (len > MaxBytes) throw new InvalidDataException("Archivo de más de 100 MB");
            await using (var output = File.Create(temp))
            await using (var input = await response.Content.ReadAsStreamAsync(ct))
            {
                var buffer = new byte[65536]; long total = 0; int count;
                while ((count = await input.ReadAsync(buffer, ct)) > 0)
                {
                    total += count;
                    if (total > MaxBytes) throw new InvalidDataException("La descarga excede 100 MB");
                    await output.WriteAsync(buffer.AsMemory(0, count), ct);
                    if (len > 0) progress?.Report((double)total / len.Value);
                }
            }
            string dest = Path.ChangeExtension(temp, ".avo");
            File.Move(temp, dest);
            return dest;
        }
        finally
        {
            if (File.Exists(temp)) File.Delete(temp);
            if (client is null) http.Dispose();
        }
    }
}
