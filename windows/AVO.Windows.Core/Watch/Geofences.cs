using System.Text.Json;
using System.Text.Json.Serialization;

namespace Avo.Windows.Core.Watch;

public enum LineRole { StartFinish, Start, Finish, Checkpoint }

/// <summary>
/// Which crossings count. Seen from A towards B: <see cref="LeftToRight"/> = crossing from the left side to the right side.
/// The watch counts BOTH directions (avo_session.cpp crosses()); the direction is applied by AVO Windows when it analyses
/// the recorded track. Making the watch itself ignore the other direction needs a firmware change (not done).
/// </summary>
public enum LineDirection { Both, LeftToRight, RightToLeft }

public sealed class PlanPoint
{
    public double Lat { get; set; }
    public double Lon { get; set; }
    public PlanPoint() { }
    public PlanPoint(double lat, double lon) { Lat = lat; Lon = lon; }
    public GeoE7 E7 => GeoE7.Of(Lat, Lon);
}

public sealed class PlanFence
{
    public string Name { get; set; } = "";
    public FenceType Type { get; set; } = FenceType.Circle;
    public PlanPoint? Center { get; set; }
    public double RadiusM { get; set; } = 50;
    public List<PlanPoint> Vertices { get; set; } = [];
    public bool Active { get; set; } = true;

    /// <summary>The fence exactly as it will be written to the watch slot.</summary>
    public Fence ToWatch(int slot) => Type == FenceType.Circle
        ? new Fence(slot, FenceType.Circle, Name.Trim(), Center?.E7 ?? default, (long)Math.Round(RadiusM * 100))
        : new Fence(slot, FenceType.Polygon, Name.Trim(), default, 0, Vertices.Select(v => v.E7).ToList());

    public string? Problem()
    {
        if (string.IsNullOrWhiteSpace(Name)) return "Pon un nombre";
        if (System.Text.Encoding.UTF8.GetByteCount(Name.Trim()) > 15) return "Nombre: máximo 15 caracteres";
        if (Type == FenceType.Circle && Center is null) return "Haz clic en el mapa para fijar el centro";
        if (Type == FenceType.Polygon && Vertices.Count == 0) return "Haz clic en el mapa para añadir vértices";
        return ToWatch(0).Validate();
    }
}

public sealed class PlanLine
{
    public bool Enabled { get; set; }
    public string Name { get; set; } = "";
    public LineRole Role { get; set; } = LineRole.StartFinish;
    public PlanPoint? A { get; set; }
    public PlanPoint? B { get; set; }
    public LineDirection Direction { get; set; } = LineDirection.Both;

    public VirtualLine ToWatch() => Enabled && A is not null && B is not null
        ? new VirtualLine(true, A.E7.LatE7, A.E7.LonE7, B.E7.LatE7, B.E7.LonE7)
        : new VirtualLine(false, A?.E7.LatE7 ?? 0, A?.E7.LonE7 ?? 0, B?.E7.LatE7 ?? 0, B?.E7.LonE7 ?? 0);

    public double LengthM => A is null || B is null ? 0 : Math.Sqrt(Sq(new LocalFrame(A.Lat, A.Lon).ToXY(B.Lat, B.Lon)));
    private static double Sq((double X, double Y) p) => p.X * p.X + p.Y * p.Y;

    public string? Problem()
    {
        if (!Enabled) return null;
        if (A is null || B is null) return "Marca los dos extremos de la línea en el mapa";
        if (!A.E7.Valid || !B.E7.Valid) return "Extremos con coordenadas no válidas";
        if (LengthM < 2) return "La línea es demasiado corta (mín. 2 m)";
        if (LengthM > 2000) return "La línea es demasiado larga (máx. 2 km)";
        return null;
    }
}

/// <summary>
/// Geofences and lines prepared on the PC (geocercas.json). Slots and indexes are the watch's: 8 fence slots (0–7), 4 virtual
/// lines (0–3, line 0 is the one the watch uses to time laps). What is sent is exactly the watch format (SET_FENCE,
/// SET_ACTIVE_FENCES and the line sections of SET_CONFIG), the same messages the Android app sends.
/// </summary>
public sealed class GeofencePlan
{
    public int Version { get; set; } = 1;
    public List<PlanFence?> Fences { get; set; } = Enumerable.Range(0, Fence.MaxFences).Select(_ => (PlanFence?)null).ToList();
    public bool AutoEnabled { get; set; } = true;
    public List<PlanLine> Lines { get; set; } =
    [
        new() { Name = "Salida / meta", Role = LineRole.StartFinish },
        new() { Name = "Salida", Role = LineRole.Start },
        new() { Name = "Meta", Role = LineRole.Finish },
        new() { Name = "Control", Role = LineRole.Checkpoint },
    ];
    public DateTimeOffset? LastSent { get; set; }
    public string? LastSentTo { get; set; }

    public int ActiveMask
    {
        get
        {
            int m = 0;
            for (int i = 0; i < Fence.MaxFences; i++) if (Fences[i] is { Active: true }) m |= 1 << i;
            return m;
        }
    }

    public List<string> Problems()
    {
        var p = new List<string>();
        for (int i = 0; i < Fence.MaxFences; i++) if (Fences[i]?.Problem() is { } e) p.Add($"Geocerca {i + 1}: {e}");
        for (int i = 0; i < 4; i++) if (Lines[i].Problem() is { } e) p.Add($"Línea {i + 1} ({Lines[i].Name}): {e}");
        return p;
    }

    private static readonly JsonSerializerOptions Json = new() { WriteIndented = true, Converters = { new JsonStringEnumConverter() } };

    public static GeofencePlan Load(string path)
    {
        try
        {
            if (!File.Exists(path)) return new GeofencePlan();
            var p = JsonSerializer.Deserialize<GeofencePlan>(File.ReadAllText(path), Json) ?? new GeofencePlan();
            while (p.Fences.Count < Fence.MaxFences) p.Fences.Add(null);
            if (p.Fences.Count > Fence.MaxFences) p.Fences = p.Fences.Take(Fence.MaxFences).ToList();
            var def = new GeofencePlan().Lines;
            while (p.Lines.Count < 4) p.Lines.Add(def[p.Lines.Count]);
            if (p.Lines.Count > 4) p.Lines = p.Lines.Take(4).ToList();
            return p;
        }
        catch (JsonException ex)
        {
            try { File.Copy(path, path + ".danado-" + DateTime.Now.ToString("yyyyMMdd-HHmmss"), false); } catch (IOException) { }
            AppLog.Current?.Warn("geocercas", "geocercas.json dañado, se conserva una copia", ex);
            return new GeofencePlan();
        }
    }

    public void Save(string path)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        string tmp = path + "." + Guid.NewGuid().ToString("N")[..8] + ".tmp";
        File.WriteAllText(tmp, JsonSerializer.Serialize(this, Json));
        File.Move(tmp, path, true);
    }

    /// <summary>Takes what the watch has (to edit it on the PC). Directions and roles stay as they were on the PC.</summary>
    public void LoadFrom(WatchConfig c)
    {
        for (int i = 0; i < Fence.MaxFences; i++)
        {
            var f = i < c.Fences.Count ? c.Fences[i] : null;
            if (f is null || f.Type == FenceType.None) { Fences[i] = null; continue; }
            Fences[i] = new PlanFence
            {
                Name = f.Name, Type = f.Type, Active = (c.ActiveMask >> i & 1) == 1,
                Center = f.Type == FenceType.Circle ? new PlanPoint(f.Center.Lat, f.Center.Lon) : null, RadiusM = f.RadiusCm / 100.0,
                Vertices = f.Verts.Select(v => new PlanPoint(v.Lat, v.Lon)).ToList(),
            };
        }
        AutoEnabled = c.AutoEnabled;
        for (int i = 0; i < 4; i++)
        {
            var l = c.Lines[i];
            Lines[i].Enabled = l.Enabled;
            Lines[i].A = l.ALatE7 != 0 || l.ALonE7 != 0 ? new PlanPoint(l.A.Lat, l.A.Lon) : null;
            Lines[i].B = l.BLatE7 != 0 || l.BLonE7 != 0 ? new PlanPoint(l.B.Lat, l.B.Lon) : null;
        }
    }
}

/// <summary>A crossing of a line found in a recorded track.</summary>
public sealed record LineCrossing(int Line, double T, bool LeftToRight, bool Counts, double Lat, double Lon);

/// <summary>Crossing analysis of a recorded GNSS track, with the same geometry test as the watch (avo_session.cpp crosses()).</summary>
public static class LineAnalysis
{
    /// <summary>Firmware test: P and Q on different sides of AB and the segment PQ crossing the infinite… segment AB.</summary>
    public static bool Crosses(double ax, double ay, double bx, double by, double px, double py, double qx, double qy, out bool leftToRight)
    {
        double sp = (bx - ax) * (py - ay) - (by - ay) * (px - ax);
        double sq = (bx - ax) * (qy - ay) - (by - ay) * (qx - ax);
        bool pPos = sp >= 0, qPos = sq >= 0;
        leftToRight = pPos && !qPos;
        if (pPos == qPos) return false;
        double sa = (qx - px) * (ay - py) - (qy - py) * (ax - px);
        double sb = (qx - px) * (by - py) - (qy - py) * (bx - px);
        return (sa >= 0) != (sb >= 0) || sa == 0 || sb == 0;
    }

    public static List<LineCrossing> Detect(SessionTimeline tl, PlanLine line, int index)
    {
        var r = new List<LineCrossing>();
        if (line.A is null || line.B is null || tl.Count < 2) return r;
        var fr = new LocalFrame(line.A.Lat, line.A.Lon);
        var (ax, ay) = fr.ToXY(line.A.Lat, line.A.Lon);
        var (bx, by) = fr.ToXY(line.B.Lat, line.B.Lon);
        for (int i = 1; i < tl.Count; i++)
        {
            if (tl.BreakBefore[i] || tl.JumpBefore[i]) continue;
            if (!double.IsFinite(tl.Lat[i - 1]) || !double.IsFinite(tl.Lat[i])) continue;
            var (px, py) = fr.ToXY(tl.Lat[i - 1], tl.Lon[i - 1]);
            var (qx, qy) = fr.ToXY(tl.Lat[i], tl.Lon[i]);
            if (!Crosses(ax, ay, bx, by, px, py, qx, qy, out bool ltr)) continue;
            // time at the crossing: fraction along PQ where it meets AB
            double dx = qx - px, dy = qy - py, ex = bx - ax, ey = by - ay;
            double den = dx * ey - dy * ex;
            double f = Math.Abs(den) > 1e-12 ? Math.Clamp(((ax - px) * ey - (ay - py) * ex) / den, 0, 1) : 0.5;
            double t = tl.T[i - 1] + f * (tl.T[i] - tl.T[i - 1]);
            bool counts = line.Direction == LineDirection.Both || (line.Direction == LineDirection.LeftToRight) == ltr;
            r.Add(new LineCrossing(index, t, ltr, counts, tl.Lat[i - 1] + f * (tl.Lat[i] - tl.Lat[i - 1]), tl.Lon[i - 1] + f * (tl.Lon[i] - tl.Lon[i - 1])));
        }
        return r;
    }

    public sealed record Run(string Kind, double T0, double T1)
    {
        public double DurationS => T1 - T0;
    }

    /// <summary>
    /// Laps between consecutive counting crossings of each start/finish line, and start → finish runs (first counting crossing
    /// of a Salida line, then the next counting crossing of a Meta line). Only counting crossings (right direction) are used.
    /// </summary>
    public static List<Run> Runs(IReadOnlyList<PlanLine> lines, IReadOnlyList<LineCrossing> crossings)
    {
        var runs = new List<Run>();
        var ok = crossings.Where(c => c.Counts).OrderBy(c => c.T).ToList();
        for (int i = 0; i < lines.Count; i++)
        {
            if (lines[i].Role != LineRole.StartFinish) continue;
            var mine = ok.Where(c => c.Line == i).ToList();
            for (int k = 1; k < mine.Count; k++) runs.Add(new Run($"Vuelta {k} ({lines[i].Name})", mine[k - 1].T, mine[k].T));
        }
        double? start = null;
        int n = 0;
        foreach (var c in ok)
        {
            var role = lines[c.Line].Role;
            if (role == LineRole.Start) start = c.T;
            else if (role == LineRole.Finish && start is double s) { runs.Add(new Run($"Salida → meta {++n}", s, c.T)); start = null; }
        }
        return runs.OrderBy(r => r.T0).ToList();
    }
}

/// <summary>Where credentials for each watch live (Windows: DPAPI, per user; tests: memory). Never in the repository.</summary>
public interface IWatchCredentialStore
{
    WatchCredential? Get(string deviceId);
    void Save(WatchCredential c);
}

/// <summary>Authorization of this PC on the watch with the same procedure as the Android app (key + BOOT-button claim).</summary>
public static class WatchAuthorizer
{
    public static async Task<WatchInfo> EnsureAsync(AvoClient c, IWatchCredentialStore store, string clientName, IProgress<string>? p,
        CancellationToken ct, int claimWaitMs = 65000, int pollMs = 1000)
    {
        var info = await c.GetInfoAsync(ct);
        if (!info.SupportsAuth || info.AuthRequired == false) return info;
        var cred = store.Get(info.DeviceId);
        if (cred is not null)
        {
            p?.Report("Comprobando la autorización de este PC…");
            var o = await c.AuthenticateAsync(cred, ct);
            if (o == AuthOutcome.Ok) return info;
            if (o == AuthOutcome.WatchNotAuthentic) throw new BleRequestException(BleStatus.VerifyFailed, "El reloj no demostró conocer la clave (posible suplantación). No se envía nada.");
            if (o == AuthOutcome.Locked) throw new BleRequestException(BleStatus.Busy, "Demasiados intentos de autorización; espera un minuto y vuelve a probar.");
        }
        p?.Report("Este PC no está autorizado en el reloj: pulsa BOOT en el reloj (tienes 60 s)…");
        var st = await c.ClaimBeginAsync(clientName, ct);
        if (st == BleStatus.AuthRequired) throw new BleRequestException(st, "El reloj exige emparejamiento Bluetooth antes de autorizar (vuelve a conectar).");
        if (st != BleStatus.Ok) throw new BleRequestException(st, "El reloj no aceptó iniciar la autorización: " + BleStatusText.Es(st));
        var until = DateTime.UtcNow.AddMilliseconds(claimWaitMs);
        while (DateTime.UtcNow < until)
        {
            await Task.Delay(pollMs, ct);
            var (rs, nc) = await c.ClaimResultAsync(info.DeviceId, ct);
            if (rs == BleStatus.Busy) continue;
            if (rs == BleStatus.Ok && nc is not null)
            {
                store.Save(nc);
                var o = await c.AuthenticateAsync(nc, ct);
                if (o != AuthOutcome.Ok) throw new BleRequestException(BleStatus.AuthRequired, "Autorización recibida pero el reloj no la acepta: " + o);
                p?.Report("PC autorizado en el reloj.");
                return info;
            }
            if (rs == BleStatus.Timeout) throw new BleRequestException(rs, "No se pulsó BOOT a tiempo. Vuelve a intentarlo.");
            throw new BleRequestException(rs, "Autorización fallida: " + BleStatusText.Es(rs));
        }
        throw new BleRequestException(BleStatus.Timeout, "No se pulsó BOOT a tiempo. Vuelve a intentarlo.");
    }
}

public sealed record SyncReport(List<string> Steps, bool Verified, WatchConfig After);

/// <summary>Sends a plan with the watch's own messages and reads the configuration back to check it.</summary>
public static class GeofenceSync
{
    private static byte[] Body(Fence? f, int slot)
    {
        var w = new LeWriter();
        ((f is null || f.Type == FenceType.None) ? Fence.Empty(slot) : f with { Id = slot }).EncodeBody(w);
        return w.ToArray();
    }

    public static bool SameFence(Fence? a, Fence? b, int slot)
    {
        bool ea = a is null || a.Type == FenceType.None, eb = b is null || b.Type == FenceType.None;
        if (ea || eb) return ea == eb;
        return Body(a, slot).AsSpan().SequenceEqual(Body(b, slot));
    }

    public static bool SameLine(VirtualLine a, VirtualLine b) =>
        a.Enabled == b.Enabled && (!a.Enabled || (a.ALatE7 == b.ALatE7 && a.ALonE7 == b.ALonE7 && a.BLatE7 == b.BLatE7 && a.BLonE7 == b.BLonE7));

    /// <summary>Differences between the plan and a configuration (empty = the watch has exactly the plan).</summary>
    public static List<string> Differences(GeofencePlan plan, WatchConfig c)
    {
        var d = new List<string>();
        for (int i = 0; i < Fence.MaxFences; i++)
            if (!SameFence(plan.Fences[i]?.ToWatch(i), c.Fences[i], i)) d.Add($"geocerca {i + 1}");
        if ((c.ActiveMask & 0xFF) != plan.ActiveMask) d.Add("geocercas activas");
        if (c.AutoEnabled != plan.AutoEnabled) d.Add("grabación automática");
        for (int i = 0; i < 4; i++) if (!SameLine(plan.Lines[i].ToWatch(), c.Lines[i])) d.Add($"línea {i + 1}");
        return d;
    }

    public static async Task<SyncReport> SendAsync(AvoClient c, GeofencePlan plan, IProgress<string>? p, CancellationToken ct)
    {
        var problems = plan.Problems();
        if (problems.Count > 0) throw new InvalidOperationException("No se envía: " + string.Join("; ", problems));
        var steps = new List<string>();
        var cur = WatchConfig.Decode(await c.GetConfigAsync(ct));
        // 1. fences, one slot at a time (SET_FENCE: the watch validates with validate_fence())
        for (int i = 0; i < Fence.MaxFences; i++)
        {
            var want = plan.Fences[i]?.ToWatch(i);
            if (SameFence(want, cur.Fences[i], i)) continue;
            if (want is null && (cur.Fences[i] is null || cur.Fences[i]!.Type == FenceType.None)) continue;
            p?.Report($"Geocerca {i + 1}…");
            var m = await c.SetFenceAsync((want ?? Fence.Empty(i)).SetFenceRequest(i), ct);
            if (m.StatusEnum != BleStatus.Ok) throw new BleRequestException(m.StatusEnum, $"El reloj rechazó la geocerca {i + 1}: {BleStatusText.Es(m.StatusEnum)}");
            steps.Add(want is null ? $"Geocerca {i + 1} borrada" : $"Geocerca {i + 1} «{want.Name}» enviada");
        }
        // 2. active fences + automatic recording
        if ((cur.ActiveMask & 0xFF) != plan.ActiveMask || cur.AutoEnabled != plan.AutoEnabled)
        {
            p?.Report("Geocercas activas…");
            var st = await c.SetActiveFencesAsync(plan.ActiveMask, plan.AutoEnabled, ct);
            if (st != BleStatus.Ok) throw new BleRequestException(st, "El reloj rechazó las geocercas activas: " + BleStatusText.Es(st));
            steps.Add("Geocercas activas actualizadas");
        }
        // 3. lines: read-modify-write of the whole configuration read NOW (so nothing else is overwritten)
        var now = WatchConfig.Decode(await c.GetConfigAsync(ct));
        var lines = Enumerable.Range(0, 4).Select(i => plan.Lines[i].ToWatch()).ToArray();
        if (Enumerable.Range(0, 4).Any(i => !SameLine(lines[i], now.Lines[i])))
        {
            p?.Report("Líneas de salida y meta…");
            var m = await c.SetConfigAsync((now with { Lines = lines }).Encode(), ct);
            if (m.StatusEnum != BleStatus.Ok) throw new BleRequestException(m.StatusEnum, "El reloj rechazó las líneas: " + BleStatusText.Es(m.StatusEnum));
            steps.Add("Líneas enviadas");
        }
        // 4. verification
        p?.Report("Comprobando lo que ha guardado el reloj…");
        var after = WatchConfig.Decode(await c.GetConfigAsync(ct));
        var diff = Differences(plan, after);
        if (steps.Count == 0) steps.Add("El reloj ya tenía exactamente estas geocercas y líneas");
        if (diff.Count > 0) steps.Add("Diferencias tras enviar: " + string.Join(", ", diff));
        return new SyncReport(steps, diff.Count == 0, after);
    }
}
