using System.Globalization;

namespace Avo.Windows.Core;

public sealed record TrackPoint(double Latitude, double Longitude, double SpeedMs, double AccuracyM,
    int CarrierSolution, long GpsWeekMs, double AltitudeM = 0, double? ElapsedSeconds = null)
{
    public double SpeedKmh => SpeedMs * 3.6;
    public string RtkName => CarrierSolution switch { 2 => "FIX", 1 => "FLOAT", _ => "GNSS" };
}

public sealed record SegmentSummary(string Name, int Index, long ValidBytes, int Blocks, int Records,
    bool CleanClose, bool Truncated, int BadRecords);

public sealed class TrainingSession
{
    public string SessionId { get; set; } = "";
    public string Horse { get; set; } = "Sin identificar";
    public string Rider { get; set; } = "Sin identificar";
    public DateTimeOffset? StartedAt { get; set; }
    public string SourceName { get; set; } = "";
    public string Integrity { get; set; } = "Pendiente";
    public bool HasRawTelemetry { get; set; }
    public double? DeclaredDistanceM { get; set; }
    public double? DeclaredDurationS { get; set; }
    public double? DeclaredMaxSpeedMs { get; set; }
    public int TotalImuSamples { get; set; }
    public int TotalImuBatches { get; set; }
    public int InvalidFrames { get; set; }
    public int MarkerCount { get; set; }
    public int GnssSamples { get; set; }
    public int UnusableGnssSamples { get; set; }
    public int RtkFixCount { get; set; }
    public int RtkFloatCount { get; set; }
    public int GnssOtherCount { get; set; }
    public List<TrackPoint> Track { get; } = [];
    public List<SegmentSummary> Segments { get; } = [];
    /// <summary>RAW segment files on disk for the analysis engine (the .avr itself, or verified copies extracted from a .avo package).</summary>
    public List<string> RawSegmentPaths { get; } = [];
    public string? MarineSource { get; set; }
    public string? MarineKind { get; set; }
    public DateTimeOffset? MarineObservedAt { get; set; }
    public double? TideHeightM { get; set; }
    public double? WindKmh { get; set; }
    public double? WaveHeightM { get; set; }
    public string? MarineNotes { get; set; }
    public double DistanceM => Track.Count > 1 ? Track.Zip(Track.Skip(1), (a, b) => Geo.HaversineM(a, b))
        .Where(d => d < 250).Sum() : DeclaredDistanceM ?? 0;
    public double MaxSpeedKmh => Track.Count > 0 ? Track.Max(x => x.SpeedKmh) : (DeclaredMaxSpeedMs ?? 0) * 3.6;
    public double DurationSeconds
    {
        get
        {
            if (Track.Count >= 2)
            {
                var sec = Track[^1].ElapsedSeconds.GetValueOrDefault() - Track[0].ElapsedSeconds.GetValueOrDefault();
                if (sec > 0) return sec;
                var ms = Track[^1].GpsWeekMs - Track[0].GpsWeekMs;
                if (ms < 0) ms += 604_800_000;
                if (ms > 0) return ms / 1000.0;
            }
            return DeclaredDurationS ?? 0;
        }
    }
    public double MeanSpeedKmh => DurationSeconds > 0 ? DistanceM / DurationSeconds * 3.6 : 0;
    public double FixPercent => GnssSamples > 0 ? 100.0 * RtkFixCount / GnssSamples : 0;
    public string DateText => StartedAt?.ToLocalTime().ToString("dd/MM/yyyy HH:mm", CultureInfo.GetCultureInfo("es-ES")) ?? "Sin fecha";
    public string Summary => $"{Horse} · {DateText} · {DistanceM / 1000:0.00} km";
}

public static class Geo
{
    public static double HaversineM(TrackPoint a, TrackPoint b)
    {
        const double radius = 6371008.8;
        double r = Math.PI / 180, dl = (b.Latitude - a.Latitude) * r, dn = (b.Longitude - a.Longitude) * r;
        double h = Math.Pow(Math.Sin(dl / 2), 2) + Math.Cos(a.Latitude * r) * Math.Cos(b.Latitude * r) * Math.Pow(Math.Sin(dn / 2), 2);
        return 2 * radius * Math.Atan2(Math.Sqrt(h), Math.Sqrt(Math.Max(0, 1 - h)));
    }
}

public sealed record SpeedSection(int Index, int StartIndex, int EndIndex, double DistanceM,
    double DurationS, double AverageSpeedKmh, double MaximumSpeedKmh, string Name);

public static class Analytics
{
    public static IReadOnlyList<SpeedSection> Sections(TrainingSession session, double lengthM = 500)
    {
        var track = session.Track;
        if (track.Count < 2) return [];
        var result = new List<SpeedSection>();
        int start = 0, index = 1;
        double distance = 0;
        for (int i = 1; i < track.Count; i++)
        {
            var step = Geo.HaversineM(track[i - 1], track[i]);
            if (step > 250) { start = i; distance = 0; continue; }
            distance += step;
            if (distance >= lengthM || i == track.Count - 1)
            {
                var ms = track[i].GpsWeekMs - track[start].GpsWeekMs;
                if (ms < 0) ms += 604_800_000;
                var duration = ms / 1000.0;
                var section = track.Skip(start).Take(i - start + 1).ToArray();
                result.Add(new SpeedSection(index++, start, i, distance, duration,
                    duration > 0 ? distance / duration * 3.6 : 0, section.Max(p => p.SpeedKmh), $"Tramo {index - 1}"));
                start = i;
                distance = 0;
            }
        }
        return result;
    }
    public static string Duration(double seconds) => TimeSpan.FromSeconds(Math.Max(seconds, 0)).ToString(@"hh\:mm\:ss");
}
