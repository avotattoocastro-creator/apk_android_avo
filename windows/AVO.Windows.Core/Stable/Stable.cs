using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace Avo.Windows.Core;

public enum IdentityKind { Horse, Rider }

/// <summary>A horse of the Cuadra or a rider of Jinetes. Same fields as the Android app (HorseEntity / RiderEntity).</summary>
public sealed class IdentityRecord
{
    /// <summary>Identifier written to the watch and to the NFC tag (max 23 bytes), e.g. HORSE_001.</summary>
    public string Code { get; set; } = "";
    public string Name { get; set; } = "";
    public string Breed { get; set; } = "";        // horses only
    public int? BirthYear { get; set; }             // horses only
    public string Notes { get; set; } = "";
    public bool Active { get; set; } = true;
    /// <summary>UID (hex) of the last NFC tag read or written for this record.</summary>
    public string? NfcUid { get; set; }
    /// <summary>Where it came from: manual, NFC, training file.</summary>
    public string Origin { get; set; } = "manual";
    /// <summary>Created from a SYNTHETIC demonstration session (never mixed with real data in totals).</summary>
    public bool Demo { get; set; }
    public DateTimeOffset Created { get; set; } = DateTimeOffset.UtcNow;
}

/// <summary>Horse and rider of one training, chosen by the user. Only metadata on this PC: the .avo/.avr is never changed.</summary>
public sealed class TrainingAssignment
{
    public string? HorseCode { get; set; }
    public string? RiderCode { get; set; }
    public DateTimeOffset Updated { get; set; } = DateTimeOffset.UtcNow;
}

/// <summary>Resolved identity of a training (what the app shows) and where it comes from.</summary>
public sealed record ResolvedIdentity(string? Code, string Name, string Source)
{
    public bool Known => Code is not null || Name != StableStore.Unknown;
}

/// <summary>
/// Cuadra (horses), Jinetes (riders) and training assignments, stored as one JSON file (cuadra.json) written atomically.
/// Rules taken from the Android app: codes ≤ 23 bytes without control characters; a tag/file never overwrites a record the
/// user already has (same code); assigning only changes metadata, never the training file.
/// </summary>
public sealed class StableStore
{
    public const string Unknown = "Sin identificar";
    private readonly string _path;
    private readonly object _gate = new();
    private Data _d = new();

    private sealed class Data
    {
        public int Version { get; set; } = 1;
        public List<IdentityRecord> Horses { get; set; } = [];
        public List<IdentityRecord> Riders { get; set; } = [];
        public Dictionary<string, TrainingAssignment> Assignments { get; set; } = new(StringComparer.Ordinal);
    }

    private static readonly JsonSerializerOptions Json = new() { WriteIndented = true, DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull };

    public StableStore(string path)
    {
        _path = path;
        try
        {
            if (File.Exists(path)) _d = JsonSerializer.Deserialize<Data>(File.ReadAllText(path), Json) ?? new Data();
        }
        catch (JsonException ex)
        {
            // keep the damaged file for the user, start empty: never silently lose it
            try { File.Copy(path, path + ".danado-" + DateTime.Now.ToString("yyyyMMdd-HHmmss"), false); } catch (IOException) { }
            AppLog.Current?.Warn("cuadra", "cuadra.json dañado, se conserva una copia", ex);
            _d = new Data();
        }
        _d.Assignments = new Dictionary<string, TrainingAssignment>(_d.Assignments ?? [], StringComparer.Ordinal);
    }

    public event Action? Changed;

    public IReadOnlyList<IdentityRecord> Horses { get { lock (_gate) return _d.Horses.ToList(); } }
    public IReadOnlyList<IdentityRecord> Riders { get { lock (_gate) return _d.Riders.ToList(); } }
    public IReadOnlyList<IdentityRecord> Records(IdentityKind k) => k == IdentityKind.Horse ? Horses : Riders;
    private List<IdentityRecord> L(IdentityKind k) => k == IdentityKind.Horse ? _d.Horses : _d.Riders;

    public IdentityRecord? Find(IdentityKind k, string? code)
    {
        if (string.IsNullOrWhiteSpace(code)) return null;
        lock (_gate) return L(k).FirstOrDefault(r => r.Code.Equals(code.Trim(), StringComparison.OrdinalIgnoreCase));
    }
    public IdentityRecord? FindByName(IdentityKind k, string? name)
    {
        if (string.IsNullOrWhiteSpace(name) || name == Unknown) return null;
        lock (_gate) return L(k).FirstOrDefault(r => r.Name.Equals(name.Trim(), StringComparison.CurrentCultureIgnoreCase));
    }

    /// <summary>Android rule (AvoNfc.import): not blank, ≤ 23 UTF-8 bytes, no control characters.</summary>
    public static bool ValidCode(string? code) =>
        !string.IsNullOrWhiteSpace(code) && System.Text.Encoding.UTF8.GetByteCount(code.Trim()) <= 23 && !code.Any(char.IsControl);

    /// <summary>Next free HORSE_### / RIDER_### code (the format used by the watch and the Android app).</summary>
    public string NextCode(IdentityKind k)
    {
        string prefix = k == IdentityKind.Horse ? "HORSE_" : "RIDER_";
        lock (_gate)
        {
            var used = L(k).Select(r => r.Code.ToUpperInvariant()).ToHashSet();
            for (int n = 1; n < 100000; n++)
            {
                string c = prefix + n.ToString("000");
                if (!used.Contains(c)) return c;
            }
        }
        throw new InvalidOperationException("No quedan códigos libres");
    }

    /// <summary>Adds a record. Throws if the code is invalid or already used.</summary>
    public IdentityRecord Add(IdentityKind k, IdentityRecord r)
    {
        r.Code = r.Code.Trim();
        r.Name = string.IsNullOrWhiteSpace(r.Name) ? r.Code : r.Name.Trim();
        if (!ValidCode(r.Code)) throw new ArgumentException("Código no válido: máximo 23 caracteres, sin caracteres de control");
        lock (_gate)
        {
            if (L(k).Any(x => x.Code.Equals(r.Code, StringComparison.OrdinalIgnoreCase)))
                throw new ArgumentException($"Ya existe {(k == IdentityKind.Horse ? "un caballo" : "un jinete")} con el código {r.Code}");
            L(k).Add(r);
        }
        Save();
        return r;
    }

    /// <summary>Saves edits of an existing record (the code cannot change: it is what the watch and the tags carry).</summary>
    public void Update(IdentityKind k, string code, Action<IdentityRecord> edit)
    {
        lock (_gate)
        {
            var r = L(k).FirstOrDefault(x => x.Code.Equals(code, StringComparison.OrdinalIgnoreCase)) ?? throw new KeyNotFoundException(code);
            string keep = r.Code;
            edit(r);
            r.Code = keep;
            if (string.IsNullOrWhiteSpace(r.Name)) r.Name = keep;
            r.Name = r.Name.Trim();
            if (r.BirthYear is int y && (y < 1900 || y > 2100)) r.BirthYear = null;
        }
        Save();
    }

    /// <summary>Deletes a record. Its trainings keep their code and show the name from the file again.</summary>
    public bool Remove(IdentityKind k, string code)
    {
        bool done;
        lock (_gate) done = L(k).RemoveAll(x => x.Code.Equals(code, StringComparison.OrdinalIgnoreCase)) > 0;
        if (done) Save();
        return done;
    }

    /// <summary>
    /// Registers an identity read from an NFC tag. Like Android: if the code exists the local record is NOT overwritten
    /// (only the tag UID is remembered). Returns the record and whether it was new.
    /// </summary>
    public (IdentityRecord Record, bool Created) ImportTag(AvoIdentityTag tag, string? uidHex)
    {
        var existing = Find(tag.Kind, tag.Code);
        if (existing is not null)
        {
            if (uidHex is not null && existing.NfcUid != uidHex) Update(tag.Kind, existing.Code, r => r.NfcUid = uidHex);
            return (existing, false);
        }
        var r = Add(tag.Kind, new IdentityRecord
        {
            Code = tag.Code, Name = tag.Name, Breed = tag.Breed, BirthYear = tag.BirthYear, Notes = tag.Notes, Active = tag.Active,
            NfcUid = uidHex, Origin = "NFC",
        });
        return (r, true);
    }

    /// <summary>
    /// Adds to the Cuadra / Jinetes the horse and rider a training file carries, if not there yet (same code, or same name
    /// when the file has no code). Nothing is overwritten.
    /// </summary>
    public bool RegisterFromTraining(TrainingSession s)
    {
        bool any = false;
        any |= RegisterOne(IdentityKind.Horse, s.HorseCode, FileName(s, IdentityKind.Horse), s.IsSynthetic);
        any |= RegisterOne(IdentityKind.Rider, s.RiderCode, FileName(s, IdentityKind.Rider), s.IsSynthetic);
        return any;
    }

    private bool RegisterOne(IdentityKind k, string? code, string name, bool demo)
    {
        bool hasName = !string.IsNullOrWhiteSpace(name) && name != Unknown;
        if (ValidCode(code))
        {
            if (Find(k, code) is not null) return false;
            Add(k, new IdentityRecord { Code = code!.Trim(), Name = hasName ? name : code!.Trim(), Origin = "entrenamiento", Demo = demo });
            return true;
        }
        if (!hasName || FindByName(k, name) is not null) return false;
        // file with a name but no code: same rule as Android AssignHorseRider (H_/R_ + random), matched by name afterwards
        string gen = (k == IdentityKind.Horse ? "H_" : "R_") + Guid.NewGuid().ToString("N")[..16];
        Add(k, new IdentityRecord { Code = gen, Name = name, Origin = "entrenamiento", Demo = demo });
        return true;
    }

    // ------------------------------------------------------------------ assignments
    public TrainingAssignment? Assignment(string sessionId)
    {
        lock (_gate) return _d.Assignments.TryGetValue(sessionId, out var a) ? a : null;
    }

    /// <summary>Sets (code) or clears (null) the horse and/or rider of a training. <paramref name="setHorse"/> / <paramref name="setRider"/>
    /// say which of the two is touched.</summary>
    public void Assign(string sessionId, bool setHorse, string? horseCode, bool setRider, string? riderCode)
    {
        if (setHorse && horseCode is not null && Find(IdentityKind.Horse, horseCode) is null) throw new KeyNotFoundException("Caballo no registrado: " + horseCode);
        if (setRider && riderCode is not null && Find(IdentityKind.Rider, riderCode) is null) throw new KeyNotFoundException("Jinete no registrado: " + riderCode);
        lock (_gate)
        {
            var a = _d.Assignments.TryGetValue(sessionId, out var x) ? x : new TrainingAssignment();
            if (setHorse) a.HorseCode = horseCode;
            if (setRider) a.RiderCode = riderCode;
            a.Updated = DateTimeOffset.UtcNow;
            if (a.HorseCode is null && a.RiderCode is null) _d.Assignments.Remove(sessionId);
            else _d.Assignments[sessionId] = a;
        }
        Save();
    }

    private static string FileName(TrainingSession s, IdentityKind k)
    {
        // sessions created in code (tests) may only set Horse/Rider
        string inFile = k == IdentityKind.Horse ? s.HorseInFile : s.RiderInFile;
        if (inFile == Unknown && !s.IdentityApplied) inFile = k == IdentityKind.Horse ? s.Horse : s.Rider;
        return inFile;
    }

    /// <summary>
    /// Who this training belongs to: 1) the user's assignment, 2) the code in the file, if registered, 3) the name in the
    /// file, if it matches a record, 4) the name/code in the file as it is, 5) «Sin identificar».
    /// </summary>
    public ResolvedIdentity Resolve(TrainingSession s, IdentityKind k)
    {
        string fileName = FileName(s, k);
        string? fileCode = k == IdentityKind.Horse ? s.HorseCode : s.RiderCode;
        var a = Assignment(s.SessionId);
        string? assigned = k == IdentityKind.Horse ? a?.HorseCode : a?.RiderCode;
        if (assigned is not null)
            return Find(k, assigned) is { } ra ? new(ra.Code, ra.Name, "asignado") : new(assigned, assigned, "asignado (ficha eliminada)");
        if (Find(k, fileCode) is { } rc) return new(rc.Code, rc.Name, "archivo");
        if (FindByName(k, fileName) is { } rn) return new(rn.Code, rn.Name, "archivo (por nombre)");
        if (fileName != Unknown) return new(ValidCode(fileCode) ? fileCode!.Trim() : null, fileName, "archivo (sin ficha)");
        if (ValidCode(fileCode)) return new(fileCode!.Trim(), fileCode!.Trim(), "archivo (sin ficha)");
        return new(null, Unknown, "sin datos");
    }

    /// <summary>Writes the resolved names into the in-memory session (Horse/Rider, used by reports). The file is not touched.</summary>
    public (ResolvedIdentity Horse, ResolvedIdentity Rider) Apply(TrainingSession s)
    {
        if (!s.IdentityApplied)
        {
            if (s.HorseInFile == Unknown) s.HorseInFile = s.Horse;
            if (s.RiderInFile == Unknown) s.RiderInFile = s.Rider;
            s.IdentityApplied = true;
        }
        var h = Resolve(s, IdentityKind.Horse);
        var r = Resolve(s, IdentityKind.Rider);
        s.Horse = h.Name; s.Rider = r.Name;
        return (h, r);
    }

    private void Save()
    {
        string json;
        lock (_gate) json = JsonSerializer.Serialize(_d, Json);
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        string tmp = _path + "." + Guid.NewGuid().ToString("N")[..8] + ".tmp";
        File.WriteAllText(tmp, json);
        File.Move(tmp, _path, true);
        Changed?.Invoke();
    }
}

/// <summary>
/// AVO identity tag, the NDEF URI the Android app writes (core/nfc/AvoNfc.kt):
/// avohorse://identity/horse/{code}?v=2&amp;name=…&amp;breed=…&amp;birthYear=…&amp;notes=…&amp;active=true
/// avohorse://identity/rider/{code}?v=2&amp;name=…&amp;notes=…&amp;active=true
/// Older identity-only tags have no query. The same validations as AvoNfc.import are applied.
/// </summary>
public sealed record AvoIdentityTag(IdentityKind Kind, string Code, string Name, string Breed, int? BirthYear, string Notes, bool Active)
{
    public static AvoIdentityTag Parse(string uri)
    {
        const string Prefix = "avohorse://identity/";
        if (!uri.StartsWith(Prefix, StringComparison.OrdinalIgnoreCase)) throw new FormatException("Etiqueta no AVO");
        string rest = uri[Prefix.Length..];
        int q = rest.IndexOf('?');
        string path = q >= 0 ? rest[..q] : rest, query = q >= 0 ? rest[(q + 1)..] : "";
        int h = query.IndexOf('#');
        if (h >= 0) query = query[..h];
        var seg = path.Split('/', StringSplitOptions.RemoveEmptyEntries);
        string kind = seg.Length > 0 ? seg[0] : "";
        string code = seg.Length > 1 ? Uri.UnescapeDataString(seg[1]).Trim() : "";
        if (kind is not ("horse" or "rider")) throw new FormatException("Tipo de ficha desconocido");
        if (!StableStore.ValidCode(code) || code.Length > 23) throw new FormatException("ID no válido");
        var p = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var part in query.Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            int e = part.IndexOf('=');
            string key = Decode(e >= 0 ? part[..e] : part), val = e >= 0 ? Decode(part[(e + 1)..]) : "";
            p.TryAdd(key, val);   // first value wins (Uri.getQueryParameter)
        }
        if (p.TryGetValue("v", out var v) && v != "2") throw new FormatException("Versión NFC no compatible");
        string F(string key, string fallback) => p.TryGetValue(key, out var x) ? (x.Length > 512 ? x[..512] : x) : fallback;
        string name = F("name", code);
        if (string.IsNullOrWhiteSpace(name)) name = code;
        int? birth = int.TryParse(F("birthYear", ""), out int y) && y is >= 1900 and <= 2100 ? y : null;
        return new AvoIdentityTag(kind == "horse" ? IdentityKind.Horse : IdentityKind.Rider, code, name,
            kind == "horse" ? F("breed", "") : "", kind == "horse" ? birth : null, F("notes", ""), F("active", "true") != "false");
    }

    // Android Uri.getQueryParameter decodes '+' as a space (since Jelly Bean)
    private static string Decode(string s) => Uri.UnescapeDataString(s.Replace('+', ' '));

    /// <summary>Same URI as AvoNfc.horse()/rider() (Uri.encode / appendQueryParameter percent-encoding, spaces as %20).</summary>
    public static string BuildUri(IdentityKind k, IdentityRecord r)
    {
        var sb = new System.Text.StringBuilder("avohorse://identity/").Append(k == IdentityKind.Horse ? "horse/" : "rider/").Append(Enc(r.Code));
        sb.Append("?v=2&name=").Append(Enc(r.Name));
        if (k == IdentityKind.Horse)
            sb.Append("&breed=").Append(Enc(r.Breed)).Append("&birthYear=").Append(r.BirthYear?.ToString(System.Globalization.CultureInfo.InvariantCulture) ?? "");
        sb.Append("&notes=").Append(Enc(r.Notes)).Append("&active=").Append(r.Active ? "true" : "false");
        return sb.ToString();
    }

    // android.net.Uri.encode keeps letters, digits and _-!.~'()* ; everything else as UTF-8 %XX (upper case)
    private static string Enc(string s)
    {
        var sb = new System.Text.StringBuilder();
        foreach (byte b in System.Text.Encoding.UTF8.GetBytes(s ?? ""))
        {
            char c = (char)b;
            if (b < 0x80 && (char.IsAsciiLetterOrDigit(c) || "_-!.~'()*".Contains(c))) sb.Append(c);
            else sb.Append('%').Append(b.ToString("X2"));
        }
        return sb.ToString();
    }

    public static readonly Regex CodePattern = new("^[A-Za-z0-9_-]{1,23}$", RegexOptions.Compiled);
}
