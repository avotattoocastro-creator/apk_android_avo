namespace Avo.Windows.Core;

public enum AlignmentMode { RelativeTime, Distance }

/// <summary>
/// Resamples several sessions on a common axis (relative time in s or cumulative distance in m) so they can be drawn and
/// compared point by point. Linear interpolation is only applied between two continuous samples; across a GNSS gap the
/// value is NaN. Different sampling rates are therefore handled without inventing data. Spatial correspondence (same
/// route) is decided by the engine comparison (DTW, lateral separation), not by start points looking similar.
/// </summary>
public static class SeriesAligner
{
    public sealed record Aligned(double[] Axis, IReadOnlyList<double[]> Values);

    public static Aligned Align(IReadOnlyList<SessionTimeline> sessions, Func<SessionTimeline, double[]> selector, AlignmentMode mode, double step)
    {
        if (sessions.Count == 0 || step <= 0) return new Aligned([], []);
        double end = sessions.Max(s => s.Count == 0 ? 0 : mode == AlignmentMode.RelativeTime ? s.T[^1] - s.T[0] : s.Distance[^1]);
        int n = (int)Math.Floor(end / step) + 1;
        n = Math.Clamp(n, 0, 2_000_000);
        var axis = new double[n];
        for (int i = 0; i < n; i++) axis[i] = i * step;
        var values = new List<double[]>(sessions.Count);
        foreach (var s in sessions)
        {
            var y = selector(s);
            var outv = new double[n];
            Array.Fill(outv, double.NaN);
            if (s.Count >= 2 && y.Length == s.Count)
            {
                var x = mode == AlignmentMode.RelativeTime ? s.T.Select(t => t - s.T[0]).ToArray() : s.Distance;
                int j = 0;
                for (int i = 0; i < n; i++)
                {
                    double a = axis[i];
                    while (j + 1 < s.Count && x[j + 1] < a) j++;
                    if (j + 1 >= s.Count) { if (Math.Abs(x[j] - a) < 1e-9) outv[i] = y[j]; break; }
                    if (a < x[j]) continue;
                    if (s.BreakBefore[j + 1] || s.JumpBefore[j + 1]) continue;
                    double dx = x[j + 1] - x[j];
                    if (dx <= 0) { outv[i] = y[j]; continue; }
                    double u = (a - x[j]) / dx;
                    outv[i] = y[j] + (y[j + 1] - y[j]) * u;
                }
            }
            values.Add(outv);
        }
        return new Aligned(axis, values);
    }

    /// <summary>Summary row of one session for the comparison table.</summary>
    public sealed record SessionSummary(string Label, double DistanceKm, double DurationS, double? MeanSpeedKmh, double? MaxSpeedKmh,
        double? MaxAccel, double? MaxDecel, double FixPercent, double? Cadence);

    public static SessionSummary Summarize(string label, SessionTimeline tl, EquineAnalysis? engine, double engineOffsetS = 0)
    {
        if (tl.Count < 2) return new SessionSummary(label, 0, 0, null, null, null, null, 0, null);
        var all = new SegmentDefinition { Name = label, T0 = tl.T[0], T1 = tl.T[^1] };
        var m = SegmentAnalyzer.Compute(tl, all, engine, engineOffsetS);
        double? cad = engine?.Metric("cadencia_media_imu0");
        return new SessionSummary(label, m.DistanceM / 1000, m.DurationS, m.MeanSpeedKmh, m.MaxSpeedKmh, m.MaxAccel, m.MaxDecel, m.FixFraction * 100, cad);
    }
}
