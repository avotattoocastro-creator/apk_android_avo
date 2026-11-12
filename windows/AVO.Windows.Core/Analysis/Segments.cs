using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Avo.Windows.Core;

public enum SegmentKind { Manual, Distance, SpeedBand, Engine, Lines }

/// <summary>User or automatic selection of a time interval of one session. Stored apart from the telemetry.</summary>
public sealed class SegmentDefinition
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N")[..12];
    public string Name { get; set; } = "";
    public double T0 { get; set; }
    public double T1 { get; set; }
    public SegmentKind Kind { get; set; } = SegmentKind.Manual;
    public string Notes { get; set; } = "";
    public DateTimeOffset CreatedUtc { get; set; } = DateTimeOffset.UtcNow;
}

/// <summary>Metrics of a segment. Null = not available with the data present (shown as «Sin datos»).</summary>
public sealed record SegmentMetrics(
    string Id, string Name, SegmentKind Kind, double T0, double T1, double DurationS, double DistanceM,
    double? MaxSpeedKmh, double? MeanSpeedKmh, double? MaxAccel, double? MaxDecel, int SpeedChanges,
    double FixFraction, double FloatOrBetterFraction, double? MeanHAccM, int GapCount,
    double? Cadence, double? CycleCorrelation, double? IntervalCv, string Observations)
{
    public string Notes { get; init; } = "";
}

public static class SegmentAnalyzer
{
    /// <summary>Acceleration samples count as "validated" only with σa ≤ this value (m/s²), no gap/jump nearby and at least
    /// a DGNSS solution. The same band as the engine's USABLE quality (σ ≤ 0.8 m/s²).</summary>
    public const double MaxAccelSigma = 0.8;

    /// <summary>Speed bands used to count rhythm changes. They are speed bands, not gaits.</summary>
    public static readonly double[] SpeedBandEdgesMs = [0.4, 2.2, 4.6];

    /// <param name="engineOffsetS">engine time = timeline time + offset (difference of the first GNSS epochs used by each).</param>
    public static SegmentMetrics Compute(SessionTimeline tl, SegmentDefinition seg, EquineAnalysis? engine = null, double engineOffsetS = 0)
    {
        double t0 = Math.Min(seg.T0, seg.T1), t1 = Math.Max(seg.T0, seg.T1);
        var idx = Enumerable.Range(0, tl.Count).Where(i => tl.T[i] >= t0 && tl.T[i] <= t1).ToArray();
        if (idx.Length < 2)
            return new SegmentMetrics(seg.Id, seg.Name, seg.Kind, t0, t1, t1 - t0, 0, null, null, null, null, 0, 0, 0, null, 0, null, null, null,
                "Sin datos GNSS utilizables en el intervalo") { Notes = seg.Notes };
        int first = idx[0], last = idx[^1];
        double dist = tl.Distance[last] - tl.Distance[first];
        double dur = tl.T[last] - tl.T[first];
        int gaps = idx.Skip(1).Count(i => tl.BreakBefore[i]);
        double activeTime = 0;
        for (int k = 1; k < idx.Length; k++) if (!tl.BreakBefore[idx[k]]) activeTime += tl.T[idx[k]] - tl.T[idx[k - 1]];
        double vmax = Stats.MaxFinite(idx.Select(i => tl.SpeedFiltered[i]));
        double? mean = activeTime > 0 ? dist / activeTime * 3.6 : null;
        var valid = idx.Where(i => AccelValid(tl, i)).ToArray();
        double? amax = valid.Length > 0 ? Stats.MaxFinite(valid.Select(i => tl.AccelLong[i])) : null;
        double? dmax = valid.Length > 0 ? Stats.MinFinite(valid.Select(i => tl.AccelLong[i])) : null;
        if (amax is double am && am <= 0) amax = null;
        if (dmax is double dm && dm >= 0) dmax = null;
        int changes = CountBandChanges(tl, idx);
        double fix = idx.Count(i => tl.Solution[i] == GnssSolution.RtkFix) / (double)idx.Length;
        double flt = idx.Count(i => tl.Solution[i] >= GnssSolution.RtkFloat) / (double)idx.Length;
        double? hacc = idx.Select(i => tl.HAcc[i]).Where(double.IsFinite).DefaultIfEmpty(double.NaN).Average() is double h && double.IsFinite(h) ? h : null;

        double? cad = null, corr = null, cv = null;
        if (engine is not null && engine.HasImu && engine.Segments.Count > 0)
        {
            // Duration-weighted average of engine performance segments overlapping the interval.
            double wsum = 0, csum = 0;
            double e0 = t0 + engineOffsetS, e1 = t1 + engineOffsetS;
            foreach (var es in engine.Segments)
            {
                double o = Math.Min(es.T1, e1) - Math.Max(es.T0, e0);
                if (o <= 0 || !double.IsFinite(o)) continue;
                if (es.CadenceHz is double f && double.IsFinite(f)) { csum += f * o; wsum += o; }
            }
            if (wsum > 0) cad = csum / wsum * 60;
            var corrs = engine.Segments.Where(e => Math.Min(e.T1, e1) - Math.Max(e.T0, e0) > 0 && e.CycleCorrelation is double c && double.IsFinite(c)).Select(e => e.CycleCorrelation!.Value).ToArray();
            if (corrs.Length > 0) corr = corrs.Average();
            var cvs = engine.Segments.Where(e => Math.Min(e.T1, e1) - Math.Max(e.T0, e0) > 0 && e.IntervalCv is double c && double.IsFinite(c)).Select(e => e.IntervalCv!.Value).ToArray();
            if (cvs.Length > 0) cv = cvs.Average();
        }

        var obs = new List<string>();
        if (gaps > 0) obs.Add($"{gaps} pérdida(s) de señal GNSS");
        if (fix < 0.5) obs.Add("menos del 50 % en RTK FIX");
        if (valid.Length < idx.Length * 0.5) obs.Add("aceleración validada en menos de la mitad de las épocas");
        if (engine is null || !engine.HasImu) obs.Add("sin datos de cincha: regularidad no disponible");
        return new SegmentMetrics(seg.Id, seg.Name, seg.Kind, tl.T[first], tl.T[last], dur, dist,
            double.IsFinite(vmax) ? vmax * 3.6 : null, mean, amax, dmax, changes, fix, flt, hacc, gaps, cad, corr, cv,
            obs.Count == 0 ? "Datos completos" : string.Join("; ", obs)) { Notes = seg.Notes };
    }

    public static bool AccelValid(SessionTimeline tl, int i) =>
        double.IsFinite(tl.AccelLong[i]) && tl.AccelLongSigma[i] <= MaxAccelSigma && tl.Solution[i] >= GnssSolution.Dgnss &&
        !tl.BreakBefore[i] && !(i + 1 < tl.Count && tl.BreakBefore[i + 1]) && !tl.JumpBefore[i];

    private static int Band(double v)
    {
        int b = 0;
        foreach (var e in SpeedBandEdgesMs) if (v >= e) b++;
        return b;
    }

    /// <summary>Changes of speed band lasting at least 3 s (hysteresis against flicker at the edges).</summary>
    public static int CountBandChanges(SessionTimeline tl, int[] idx)
    {
        int changes = 0, current = -1, candidate = -1; double since = 0;
        foreach (int i in idx)
        {
            double v = tl.SpeedFiltered[i];
            if (!double.IsFinite(v)) continue;
            int b = Band(v);
            if (current < 0) { current = b; continue; }
            if (b == current) { candidate = -1; continue; }
            if (b != candidate) { candidate = b; since = tl.T[i]; continue; }
            if (tl.T[i] - since >= 3) { changes++; current = b; candidate = -1; }
        }
        return changes;
    }

    /// <summary>Consecutive segments of fixed distance (default 500 m), restarting after gaps.</summary>
    public static List<SegmentDefinition> ByDistance(SessionTimeline tl, double lengthM = 500)
    {
        var list = new List<SegmentDefinition>();
        if (tl.Count < 2 || lengthM <= 0) return list;
        int start = 0;
        for (int i = 1; i < tl.Count; i++)
        {
            if (tl.BreakBefore[i]) { start = i; continue; }
            if (tl.Distance[i] - tl.Distance[start] >= lengthM || i == tl.Count - 1)
            {
                if (tl.T[i] - tl.T[start] > 0)
                    list.Add(new SegmentDefinition
                    {
                        Name = $"{tl.Distance[start] / 1000:0.0#}–{tl.Distance[i] / 1000:0.0#} km",
                        T0 = tl.T[start], T1 = tl.T[i], Kind = SegmentKind.Distance,
                    });
                start = i;
            }
        }
        return list;
    }

    private static readonly string[] BandNames = ["Parado", "Velocidad baja", "Velocidad media", "Velocidad alta"];

    /// <summary>Automatic segmentation by speed band of the filtered speed, minimum duration minS (default 10 s).
    /// Labels are speed bands, explicitly not gaits (gait needs the girth IMU and the engine).</summary>
    public static List<SegmentDefinition> BySpeedBand(SessionTimeline tl, double minS = 10)
    {
        var raw = new List<(int band, double t0, double t1)>();
        int cur = -1; double ts = 0, tp = 0;
        for (int i = 0; i < tl.Count; i++)
        {
            double v = tl.SpeedFiltered[i];
            if (!double.IsFinite(v)) continue;
            int b = Band(v);
            if (cur < 0) { cur = b; ts = tl.T[i]; }
            else if (b != cur || tl.BreakBefore[i]) { raw.Add((cur, ts, tp)); cur = b; ts = tl.T[i]; }
            tp = tl.T[i];
        }
        if (cur >= 0) raw.Add((cur, ts, tp));
        // merge short pieces into the previous one
        var merged = new List<(int band, double t0, double t1)>();
        foreach (var r in raw)
        {
            if (merged.Count > 0 && (r.t1 - r.t0 < minS || merged[^1].band == r.band))
            {
                var m = merged[^1];
                merged[^1] = (m.t1 - m.t0 >= r.t1 - r.t0 ? m.band : r.band, m.t0, r.t1);
            }
            else merged.Add(r);
        }
        return merged.Select((m, k) => new SegmentDefinition
        {
            Name = $"{k + 1}. {BandNames[Math.Clamp(m.band, 0, 3)]}", T0 = m.t0, T1 = m.t1, Kind = SegmentKind.SpeedBand,
        }).ToList();
    }

    /// <summary>Engine performance segments (gait classification of the engine; only meaningful with girth data).</summary>
    public static List<SegmentDefinition> FromEngine(EquineAnalysis engine, double engineOffsetS = 0) =>
        engine.Segments.Where(s => double.IsFinite(s.T0) && double.IsFinite(s.T1) && s.T1 > s.T0)
            .Select(s => new SegmentDefinition { Name = $"{s.Id}. {s.Aire}", T0 = s.T0 - engineOffsetS, T1 = s.T1 - engineOffsetS, Kind = SegmentKind.Engine }).ToList();
}

/// <summary>Persistent per-session segment store (JSON, schema avo-windows-segments v1). Never touches the telemetry.</summary>
public sealed class SegmentStore
{
    public const string Schema = "avo-windows-segments";
    public const int Version = 1;
    private readonly string _dir;
    private static readonly JsonSerializerOptions Json = new() { WriteIndented = true, Converters = { new JsonStringEnumConverter() } };

    public SegmentStore(string directory) { _dir = directory; }

    private sealed class FileModel
    {
        public string Schema { get; set; } = SegmentStore.Schema;
        public int Version { get; set; } = SegmentStore.Version;
        public string SessionId { get; set; } = "";
        public List<SegmentDefinition> Segments { get; set; } = [];
    }

    public string PathFor(string sessionId) =>
        System.IO.Path.Combine(_dir, Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(sessionId)))[..24] + ".json");

    public List<SegmentDefinition> Load(string sessionId)
    {
        string p = PathFor(sessionId);
        if (!File.Exists(p)) return [];
        var m = JsonSerializer.Deserialize<FileModel>(File.ReadAllText(p, Encoding.UTF8), Json);
        if (m is null || m.Schema != Schema || m.Version > Version || m.SessionId != sessionId) return [];
        return m.Segments.Where(s => double.IsFinite(s.T0) && double.IsFinite(s.T1)).ToList();
    }

    public void Save(string sessionId, IEnumerable<SegmentDefinition> segments)
    {
        Directory.CreateDirectory(_dir);
        string p = PathFor(sessionId), tmp = p + ".tmp";
        File.WriteAllText(tmp, JsonSerializer.Serialize(new FileModel { SessionId = sessionId, Segments = segments.ToList() }, Json), new UTF8Encoding(false));
        File.Move(tmp, p, true);
    }
}

public static class TimeText
{
    private static readonly CultureInfo Es = CultureInfo.GetCultureInfo("es-ES");
    public static string Clock(double seconds)
    {
        if (!double.IsFinite(seconds)) return "—";
        var ts = TimeSpan.FromSeconds(Math.Max(0, seconds));
        return ts.TotalHours >= 1 ? ts.ToString(@"h\:mm\:ss", Es) : ts.ToString(@"mm\:ss", Es);
    }
    public static string Num(double? v, string fmt, string unit = "", string missing = "Sin datos") =>
        v is double d && double.IsFinite(d) ? d.ToString(fmt, Es) + unit : missing;
}
