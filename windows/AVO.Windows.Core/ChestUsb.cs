using System.Globalization;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Avo.Windows.Core;

// Download of trainings from the chest watch over the USB cable (protocol AVO1, CHEST >= 3.7.5-usb1).
// Spec: firmware/chest/V3_7_5_USB/PROTOCOLO_USB.md. The serial port itself lives in the WPF app (IChestLink).

/// <summary>Line transport to the watch (the USB serial port, or a simulated watch in the tests).</summary>
public interface IChestLink : IDisposable
{
    void WriteLine(string line);
    /// <summary>Next complete line (without the newline), or null if nothing arrived in time.</summary>
    string? ReadLine(TimeSpan timeout);
}

public sealed class ChestUsbException(string command, string code, string message) : Exception(message)
{
    public string Command { get; } = command;
    /// <summary>Firmware error code (recording, sd, id, open, segment, changed, range, io, cmd, mem) or "timeout"/"protocol".</summary>
    public string Code { get; } = code;
}

public sealed record ChestHello(int Api, string Name, string Firmware, string Device, bool Recording, bool SdMounted,
    int BatteryPct, bool Vbus, int RawFormat, int MaxRead);

public sealed record ChestTraining(string Id, int State, bool Ready, int Segments, long Size, long StartRtcMs,
    long ActiveMs, string Etag, IReadOnlyList<long> SegmentSizes)
{
    public DateTimeOffset? StartedAt => StartRtcMs is > 946684800000 and < 4102444800000 ? DateTimeOffset.FromUnixTimeMilliseconds(StartRtcMs) : null;
}

public sealed class ChestUsbClient(IChestLink link)
{
    private const string Prefix = "#AVO1 ";
    public TimeSpan ShortTimeout { get; set; } = TimeSpan.FromSeconds(3);
    public TimeSpan ShaTimeout { get; set; } = TimeSpan.FromSeconds(90);
    public TimeSpan LineTimeout { get; set; } = TimeSpan.FromSeconds(10);

    /// <summary>Discards whatever is waiting on the port (boot log, a late answer from an aborted command).</summary>
    public void Drain()
    {
        for (int i = 0; i < 10000 && link.ReadLine(TimeSpan.FromMilliseconds(60)) != null; i++) { }
    }

    private string Answer(string command, TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;
        while (true)
        {
            var left = deadline - DateTime.UtcNow;
            if (left <= TimeSpan.Zero) throw new ChestUsbException(command, "timeout", $"El reloj no responde a {command}");
            string? line = link.ReadLine(left);
            if (line is null) continue;
            int at = line.IndexOf(Prefix, StringComparison.Ordinal);   // a log fragment may precede it on the same line
            if (at < 0) continue;                                       // normal [AVO ...] log line
            string payload = line[(at + Prefix.Length)..].TrimEnd('\r');
            if (payload.StartsWith("ERR ", StringComparison.Ordinal))
            {
                var p = payload.Split(' ');
                string code = p.Length >= 3 ? p[2] : "protocol";
                throw new ChestUsbException(command, code, ErrorText(code));
            }
            return payload;
        }
    }

    public static string ErrorText(string code) => code switch
    {
        "recording" => "El reloj está grabando: la descarga se hará al terminar",
        "sd" => "El reloj no tiene la microSD disponible",
        "open" => "Entrenamiento sin cerrar en el reloj",
        "changed" => "El entrenamiento cambió en el reloj durante la descarga",
        "id" or "segment" or "range" => "Petición rechazada por el reloj (" + code + ")",
        "io" => "Error de lectura de la microSD del reloj",
        "mem" => "El reloj no tiene memoria libre",
        "cmd" => "Orden no reconocida por el firmware del reloj",
        _ => "Error del reloj: " + code,
    };

    public ChestHello Hello()
    {
        link.WriteLine("AVO1 HELLO");
        string a = Answer("HELLO", ShortTimeout);
        if (!a.StartsWith("HELLO ", StringComparison.Ordinal)) throw new ChestUsbException("HELLO", "protocol", "Respuesta inesperada del reloj");
        using var j = JsonDocument.Parse(a[6..]);
        var r = j.RootElement;
        var h = new ChestHello(Int(r, "api"), Str(r, "name"), Str(r, "fw"), Str(r, "device"), Bool(r, "recording"), Bool(r, "sd"),
            Int(r, "battery_pct", -1), Bool(r, "vbus"), Int(r, "raw_format"), Int(r, "max_read", 4096));
        if (h.Name != "AVO-CHEST" || h.Api < 1) throw new ChestUsbException("HELLO", "protocol", "El dispositivo USB no es un reloj AVO");
        if (!Regex.IsMatch(h.Device, "^[0-9a-fA-F]{12}$")) throw new ChestUsbException("HELLO", "protocol", "Identificador del reloj no válido");
        return h;
    }

    public List<ChestTraining> List()
    {
        link.WriteLine("AVO1 LIST");
        var list = new List<ChestTraining>();
        while (true)
        {
            string a = Answer("LIST", LineTimeout);
            if (a.StartsWith("END ", StringComparison.Ordinal))
            {
                if (!int.TryParse(a[4..], NumberStyles.None, CultureInfo.InvariantCulture, out int n) || n != list.Count)
                    throw new ChestUsbException("LIST", "protocol", "Lista del reloj incompleta");
                return list;
            }
            if (!a.StartsWith("T ", StringComparison.Ordinal)) throw new ChestUsbException("LIST", "protocol", "Respuesta inesperada del reloj");
            using var j = JsonDocument.Parse(a[2..]);
            var r = j.RootElement;
            var sizes = r.TryGetProperty("sizes", out var s) && s.ValueKind == JsonValueKind.Array ? s.EnumerateArray().Select(x => x.GetInt64()).ToList() : [];
            var t = new ChestTraining(Str(r, "id"), Int(r, "state"), Bool(r, "ready"), Int(r, "segments"), Long(r, "size"),
                Long(r, "start_rtc_ms"), Long(r, "active_ms"), Str(r, "etag"), sizes);
            if (!ValidId(t.Id) || !Regex.IsMatch(t.Etag, "^[0-9a-f]{8}$") || sizes.Count != t.Segments || sizes.Sum() != t.Size || t.Segments > 64)
                throw new ChestUsbException("LIST", "protocol", "Entrenamiento mal descrito por el reloj");
            list.Add(t);
        }
    }

    public string Sha256(string id)
    {
        if (!ValidId(id)) throw new ArgumentException("Identificador no válido", nameof(id));
        link.WriteLine("AVO1 SHA " + id);
        string a = Answer("SHA", ShaTimeout);
        if (!a.StartsWith("SHA ", StringComparison.Ordinal)) throw new ChestUsbException("SHA", "protocol", "Respuesta inesperada del reloj");
        using var j = JsonDocument.Parse(a[4..]);
        string sha = Str(j.RootElement, "sha256");
        if (Str(j.RootElement, "id") != id || !Regex.IsMatch(sha, "^[0-9a-f]{64}$")) throw new ChestUsbException("SHA", "protocol", "SHA-256 no válido");
        return sha;
    }

    /// <summary>Reads up to <paramref name="length"/> bytes of segment <paramref name="segment"/> (1-based); checks offset, length and CRC-32.</summary>
    public byte[] Read(string id, int segment, long offset, int length, string etag)
    {
        if (!ValidId(id)) throw new ArgumentException("Identificador no válido", nameof(id));
        link.WriteLine(string.Create(CultureInfo.InvariantCulture, $"AVO1 READ {id} {segment} {offset} {length} {etag}"));
        string a = Answer("READ", ShortTimeout);
        var p = a.Split(' ');
        if (p.Length != 6 || p[0] != "DATA") throw new ChestUsbException("READ", "protocol", "Respuesta inesperada del reloj");
        if (p[1] != segment.ToString(CultureInfo.InvariantCulture) || p[2] != offset.ToString(CultureInfo.InvariantCulture))
            throw new ChestUsbException("READ", "protocol", "Bloque fuera de orden");
        byte[] data;
        try { data = Convert.FromBase64String(p[5]); }
        catch (FormatException) { throw new ChestUsbException("READ", "protocol", "Bloque dañado (base64)"); }
        if (!int.TryParse(p[3], NumberStyles.None, CultureInfo.InvariantCulture, out int n) || n != data.Length || n < 1 || n > length)
            throw new ChestUsbException("READ", "protocol", "Bloque dañado (longitud)");
        if (!uint.TryParse(p[4], NumberStyles.HexNumber, CultureInfo.InvariantCulture, out uint crc) || crc != Crc32(data))
            throw new ChestUsbException("READ", "protocol", "Bloque dañado (CRC)");
        return data;
    }

    /// <summary>
    /// Tells the watch what the PC is doing, for its "CONECTADO AL PC" screen (CHEST >= 3.7.5-usb1).
    /// Best effort: an older firmware answers ERR cmd and the download goes on.
    /// Phases: 1 comparing, 2 downloading, 3 synced, 4 recording, 5 error.
    /// </summary>
    public void Progress(int phase, int index = 0, int count = 0, int pct = 0, int newCount = 0)
    {
        try
        {
            link.WriteLine(string.Create(CultureInfo.InvariantCulture,
                $"AVO1 PROGRESS {phase} {Math.Clamp(index, 0, 65535)} {Math.Clamp(count, 0, 65535)} {Math.Clamp(pct, 0, 100)} {Math.Clamp(newCount, 0, 65535)}"));
            Answer("PROGRESS", ShortTimeout);
        }
        catch (ChestUsbException) { /* screen only */ }
    }

    public static bool ValidId(string id) => Regex.IsMatch(id, "^S[A-Za-z0-9_-]{1,22}$");

    public static uint Crc32(ReadOnlySpan<byte> data)
    {
        uint crc = 0xFFFFFFFF;
        foreach (byte b in data)
        {
            crc ^= b;
            for (int i = 0; i < 8; i++) crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320u : crc >> 1;
        }
        return ~crc;
    }

    private static string Str(JsonElement e, string n) => e.TryGetProperty(n, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() ?? "" : "";
    private static int Int(JsonElement e, string n, int def = 0) => e.TryGetProperty(n, out var v) && v.ValueKind == JsonValueKind.Number && v.TryGetInt32(out int x) ? x : def;
    private static long Long(JsonElement e, string n) => e.TryGetProperty(n, out var v) && v.ValueKind == JsonValueKind.Number && v.TryGetInt64(out long x) ? x : 0;
    private static bool Bool(JsonElement e, string n) => e.TryGetProperty(n, out var v) && v.ValueKind == JsonValueKind.True;
}

/// <summary>Entry of the PC library index: one training downloaded from a watch.</summary>
public sealed class WatchLibraryEntry
{
    public string Device { get; set; } = "";
    public string Id { get; set; } = "";
    public string Etag { get; set; } = "";
    public long Size { get; set; }
    public string Sha256 { get; set; } = "";
    public string Package { get; set; } = "";
    public DateTimeOffset DownloadedAt { get; set; }
}

/// <summary>Folder on the PC where the watch trainings are kept as verified .avo packages (AVO-TRAINING-1).</summary>
public sealed class WatchLibrary
{
    private readonly string _indexPath;
    private readonly List<WatchLibraryEntry> _entries;
    public string Folder { get; }
    public IReadOnlyList<WatchLibraryEntry> Entries => _entries;

    public static string DefaultFolder => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "AVO Performance Horse", "Reloj");

    public WatchLibrary(string folder)
    {
        Folder = folder;
        Directory.CreateDirectory(folder);
        _indexPath = Path.Combine(folder, "indice_reloj.json");
        _entries = [];
        if (File.Exists(_indexPath))
        {
            try { _entries = JsonSerializer.Deserialize<List<WatchLibraryEntry>>(File.ReadAllText(_indexPath)) ?? []; }
            catch (JsonException) { _entries = []; }   // damaged index: it is rebuilt by downloading again
        }
    }

    /// <summary>The entry for this training if its package is still on disk.</summary>
    public WatchLibraryEntry? Find(string device, string id) =>
        _entries.FirstOrDefault(e => e.Device.Equals(device, StringComparison.OrdinalIgnoreCase) && e.Id == id && File.Exists(Path.Combine(Folder, e.Package)));

    public void Put(WatchLibraryEntry entry)
    {
        _entries.RemoveAll(e => e.Device.Equals(entry.Device, StringComparison.OrdinalIgnoreCase) && e.Id == entry.Id);
        _entries.Add(entry);
        string tmp = _indexPath + ".tmp";
        File.WriteAllText(tmp, JsonSerializer.Serialize(_entries, new JsonSerializerOptions { WriteIndented = true }));
        File.Move(tmp, _indexPath, true);
    }

    public string PartialDir(string device, string id) => Path.Combine(Folder, ".descargando", device.ToLowerInvariant() + "_" + id);
    public static string PackageName(string device, string id) => $"AVO_{id}_{device.ToLowerInvariant()}.avo";
}

public sealed record ChestSyncProgress(int Index, int Count, string Id, long Done, long Total, string Text);

public sealed class ChestSyncResult
{
    public ChestHello? Watch { get; set; }
    public int OnWatch { get; set; }
    public int AlreadyOnPc { get; set; }
    public int NotReady { get; set; }
    public int Failed { get; set; }
    public bool Recording { get; set; }
    public List<string> NewPackages { get; } = [];
    public List<string> Messages { get; } = [];
    public string Summary => Recording ? "El reloj está grabando: se descargará cuando termine" :
        NewPackages.Count == 0 && Failed == 0 ? $"Reloj sincronizado: {OnWatch} entrenamientos, todos ya en el PC" :
        $"Descargados {NewPackages.Count} de {OnWatch - AlreadyOnPc - NotReady} que faltaban" + (Failed > 0 ? $" · {Failed} con error" : "") +
        (NotReady > 0 ? $" · {NotReady} sin cerrar en el reloj" : "");
}

public static class ChestSync
{
    private const int Attempts = 3;

    /// <summary>
    /// Compares the trainings on the watch with the PC library and downloads the missing ones.
    /// <paramref name="knownSha"/>: trainings already present on the PC by another route (for example a .avo exported by
    /// the Android app), session id → SHA-256 of the concatenated segments; those are not downloaded again.
    /// </summary>
    public static ChestSyncResult Run(ChestUsbClient client, WatchLibrary library, IReadOnlyDictionary<string, string>? knownSha = null,
        IProgress<ChestSyncProgress>? progress = null, CancellationToken ct = default)
    {
        var result = new ChestSyncResult();
        client.Drain();
        var hello = client.Hello();
        result.Watch = hello;
        if (hello.Recording) { result.Recording = true; client.Progress(4); return result; }
        client.Progress(1);
        if (!hello.SdMounted) throw new ChestUsbException("HELLO", "sd", ChestUsbClient.ErrorText("sd"));
        int block = Math.Clamp(hello.MaxRead, 256, 65536);
        progress?.Report(new ChestSyncProgress(0, 0, "", 0, 0, "Comparando entrenamientos del reloj con el PC…"));
        var list = client.List().OrderBy(t => t.StartRtcMs).ThenBy(t => t.Id, StringComparer.Ordinal).ToList();
        result.OnWatch = list.Count;
        var missing = new List<(ChestTraining T, string? Sha)>();
        foreach (var t in list)
        {
            ct.ThrowIfCancellationRequested();
            if (!t.Ready) { result.NotReady++; continue; }
            var have = library.Find(hello.Device, t.Id);
            if (have != null && have.Etag == t.Etag && have.Size == t.Size) { result.AlreadyOnPc++; continue; }
            string? known = knownSha != null && knownSha.TryGetValue(t.Id, out var k) ? k : have?.Sha256;
            if (known != null && (have == null || have.Size == t.Size))
            {
                // Same training with a different etag (for example marked as uploaded by the phone): confirm by SHA-256.
                string sha = client.Sha256(t.Id);
                if (sha.Equals(known, StringComparison.OrdinalIgnoreCase))
                {
                    result.AlreadyOnPc++;
                    if (have != null) { have.Etag = t.Etag; library.Put(have); }
                    continue;
                }
                missing.Add((t, sha));
                continue;
            }
            missing.Add((t, null));
        }
        int lastPct = -1, lastIndex = -1;
        // Inline (same thread): the watch is asked between two READs, never at the same time.
        var watchProgress = new InlineProgress<ChestSyncProgress>(p =>
        {
            int pct = (int)(p.Done * 100 / Math.Max(1, p.Total));
            if (p.Index != lastIndex || pct >= lastPct + 5 || (pct == 100 && lastPct != 100))
            {
                lastIndex = p.Index; lastPct = pct;
                client.Progress(2, p.Index, p.Count, pct);
            }
            progress?.Report(p);
        });
        for (int i = 0; i < missing.Count; i++)
        {
            ct.ThrowIfCancellationRequested();
            var (t, sha) = missing[i];
            try
            {
                var (pkg, warning) = Download(client, library, hello, t, sha, block, i + 1, missing.Count, watchProgress, ct);
                result.NewPackages.Add(pkg);
                if (warning != null) result.Messages.Add($"{t.Id}: {warning}");
            }
            catch (ChestUsbException ex) when (ex.Code == "recording")
            {
                result.Recording = true;
                result.Messages.Add(ex.Message);
                break;
            }
            catch (Exception ex) when (ex is ChestUsbException or IOException or InvalidDataException)
            {
                result.Failed++;
                result.Messages.Add($"{t.Id}: {ex.Message}");
                if (ex is ChestUsbException { Code: "timeout" }) break;   // the watch is gone or not answering
            }
        }
        if (result.Recording) client.Progress(4);
        else if (result.Failed > 0) client.Progress(5);
        else client.Progress(3, 0, 0, 100, result.NewPackages.Count);
        return result;
    }

    private sealed class InlineProgress<T>(Action<T> report) : IProgress<T>
    {
        public void Report(T value) => report(value);
    }

    private static (string Package, string? Warning) Download(ChestUsbClient client, WatchLibrary lib, ChestHello watch, ChestTraining t, string? sha, int block,
        int index, int count, IProgress<ChestSyncProgress>? progress, CancellationToken ct)
    {
        string dir = lib.PartialDir(watch.Device, t.Id);
        Directory.CreateDirectory(dir);
        string etagFile = Path.Combine(dir, "etag.txt");
        if (!File.Exists(etagFile) || File.ReadAllText(etagFile).Trim() != t.Etag)
        {
            // Partial download of another version of the training: start again.
            foreach (var f in Directory.EnumerateFiles(dir)) File.Delete(f);
            File.WriteAllText(etagFile, t.Etag);
        }
        long done = 0;
        for (int s = 1; s <= t.Segments; s++)
        {
            string path = Path.Combine(dir, $"P{s:000}.avr");
            long size = t.SegmentSizes[s - 1];
            using var fs = new FileStream(path, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            if (fs.Length > size) fs.SetLength(0);
            long off = fs.Length;                       // resume where the previous attempt stopped
            fs.Seek(off, SeekOrigin.Begin);
            done += off;
            while (off < size)
            {
                ct.ThrowIfCancellationRequested();
                int want = (int)Math.Min(block, size - off);
                byte[] data = ReadWithRetry(client, t, s, off, want);
                fs.Write(data);
                off += data.Length;
                done += data.Length;
                progress?.Report(new ChestSyncProgress(index, count, t.Id, done, t.Size,
                    $"Descargando {index} de {count} · {t.Id} · {done * 100 / Math.Max(1, t.Size)} %"));
            }
            fs.Flush(true);
        }
        progress?.Report(new ChestSyncProgress(index, count, t.Id, t.Size, t.Size, $"Verificando {t.Id} (SHA-256)…"));
        sha ??= client.Sha256(t.Id);
        var segs = Enumerable.Range(1, t.Segments).Select(s => Path.Combine(dir, $"P{s:000}.avr")).ToList();
        using (var h = IncrementalHash.CreateHash(HashAlgorithmName.SHA256))
        {
            foreach (var p in segs) h.AppendData(File.ReadAllBytes(p));
            string local = Convert.ToHexStringLower(h.GetHashAndReset());
            if (local != sha)
            {
                foreach (var f in Directory.EnumerateFiles(dir)) File.Delete(f);
                throw new InvalidDataException("La copia no coincide con el reloj (SHA-256); se repetirá en la próxima conexión");
            }
        }
        string name = WatchLibrary.PackageName(watch.Device, t.Id);
        string target = Path.Combine(lib.Folder, name);
        WritePackage(target, watch, t, sha, segs);
        string? warning = null;
        // The copy is byte-identical to the watch (SHA-256): it is kept even if this app cannot interpret the RAW yet.
        try { TrainingImporter.Import(target, Path.Combine(dir, "comprobacion")); }
        catch (InvalidDataException ex) { warning = "descargado y verificado, pero no se puede abrir: " + ex.Message; }
        lib.Put(new WatchLibraryEntry { Device = watch.Device, Id = t.Id, Etag = t.Etag, Size = t.Size, Sha256 = sha, Package = name, DownloadedAt = DateTimeOffset.Now });
        Directory.Delete(dir, true);
        return (target, warning);
    }

    private static byte[] ReadWithRetry(ChestUsbClient client, ChestTraining t, int seg, long off, int want)
    {
        for (int attempt = 1; ; attempt++)
        {
            try { return client.Read(t.Id, seg, off, want, t.Etag); }
            catch (ChestUsbException ex) when (attempt < Attempts && ex.Code is "protocol" or "timeout" or "io")
            {
                client.Drain();   // drop a late or damaged answer before asking again
            }
        }
    }

    /// <summary>Writes the AVO-TRAINING-1 package (same layout as the Android app's .avo) atomically.</summary>
    public static void WritePackage(string target, ChestHello watch, ChestTraining t, string sha, IReadOnlyList<string> segments)
    {
        var hashes = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var p in segments) hashes[Path.GetFileName(p)] = Convert.ToHexStringLower(SHA256.HashData(File.ReadAllBytes(p)));
        var manifest = new Dictionary<string, object?>
        {
            ["format"] = "AVO-TRAINING-1",
            ["sessionId"] = t.Id,
            ["horseName"] = "",
            ["riderName"] = "",
            ["sha256"] = sha,
            ["watchDevice"] = watch.Device,
            ["watchFirmware"] = watch.Firmware,
            ["source"] = "usb-pc",
            ["startRtcMs"] = t.StartRtcMs,
            ["activeMs"] = t.ActiveMs,
            ["segments"] = segments.Count,
            ["segmentHashes"] = hashes,
        };
        string tmp = target + ".tmp";
        File.Delete(tmp);   // left over by an interrupted earlier attempt
        using (var zip = ZipFile.Open(tmp, ZipArchiveMode.Create))
        {
            var m = zip.CreateEntry("manifest.json");
            using (var w = m.Open()) w.Write(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(manifest)));
            foreach (var p in segments)
            {
                var e = zip.CreateEntry("segments/" + Path.GetFileName(p), CompressionLevel.Optimal);
                using var w = e.Open();
                using var r = File.OpenRead(p);
                r.CopyTo(w);
            }
        }
        File.Move(tmp, target, true);
    }
}
