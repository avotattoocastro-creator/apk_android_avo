namespace Avo.Windows.Core;

/// <summary>
/// Time-aligned analysis series of one session, derived from the original telemetry without modifying it.
/// t = seconds since the first usable GNSS epoch (GPS time of week, week roll-over handled).
/// Three speeds are kept apart on purpose:
///   SpeedReported  — gSpeed reported by the receiver (Doppler based), m/s;
///   SpeedDerived   — central difference of consecutive positions, m/s (noisier, independent check);
///   SpeedFiltered  — Kalman + Rauch–Tung–Striebel smoother of SpeedReported (see <see cref="SpeedSmoother"/>).
/// Accelerations are derived quantities with their own uncertainty, never measured directly by GNSS.
/// </summary>
public sealed class SessionTimeline
{
    public const double DefaultGapFactor = 2.5;

    public int Count => T.Length;
    public double[] T { get; private init; } = [];
    public double[] Lat { get; private init; } = [];
    public double[] Lon { get; private init; } = [];
    public double[] SpeedReported { get; private init; } = [];
    public double[] SpeedDerived { get; private init; } = [];
    public double[] SpeedFiltered { get; private init; } = [];
    public double[] SpeedFilteredSigma { get; private init; } = [];
    public double[] AccelLong { get; private init; } = [];
    public double[] AccelLongSigma { get; private init; } = [];
    public double[] AccelLateral { get; private init; } = [];
    public double[] Distance { get; private init; } = [];
    public double[] AltitudeMsl { get; private init; } = [];
    public double[] HAcc { get; private init; } = [];
    public double[] SpeedAcc { get; private init; } = [];
    public int[] NumSv { get; private init; } = [];
    public GnssSolution[] Solution { get; private init; } = [];
    /// <summary>True when the sample starts after a gap (no interpolation across it).</summary>
    public bool[] BreakBefore { get; private init; } = [];
    /// <summary>True when the step from the previous point was rejected as a position jump (excluded from distance).</summary>
    public bool[] JumpBefore { get; private init; } = [];
    public double NominalDtS { get; private init; }
    public List<SignalLoss> Losses { get; } = [];
    public long Itow0Ms { get; private init; }
    public DateTimeOffset? Utc0 { get; private init; }
    public double TotalDistanceM => Distance.Length > 0 ? Distance[^1] : 0;
    public double DurationS => T.Length > 1 ? T[^1] - T[0] : 0;
    public SpeedSmoother.Parameters FilterParameters { get; private init; } = new();

    public static long WeekDiffMs(long itow, long itow0)
    {
        long d = itow - itow0;
        if (d < -302_400_000L) d += 604_800_000L;
        else if (d > 302_400_000L) d -= 604_800_000L;
        return d;
    }

    /// <param name="timeBaseItowMs">GPS time of week that defines t = 0. Default: first usable epoch. A trimmed session passes the
    /// time base of the full file, so cursor, segments and engine times keep the same meaning after trimming.</param>
    public static SessionTimeline Build(TrainingSession session, SpeedSmoother.Parameters? parameters = null, long? timeBaseItowMs = null)
    {
        var p = parameters ?? new SpeedSmoother.Parameters();
        var track = session.Track;
        int n = track.Count;
        if (n == 0) return new SessionTimeline { FilterParameters = p };
        long itow0 = timeBaseItowMs ?? track[0].GpsWeekMs;
        var t = new double[n];
        long acc = WeekDiffMs(track[0].GpsWeekMs, itow0);
        for (int i = 0; i < n; i++)
        {
            if (i > 0)
            {
                long step = WeekDiffMs(track[i].GpsWeekMs, track[i - 1].GpsWeekMs);
                acc += step;
            }
            t[i] = acc / 1000.0;
        }
        var dts = new List<double>(n);
        for (int i = 1; i < n; i++) { double d = t[i] - t[i - 1]; if (d > 0) dts.Add(d); }
        double nominal = dts.Count > 0 ? Stats.Median(dts) : 1.0;
        double gapLimit = Math.Max(DefaultGapFactor * nominal, nominal + 0.05);

        var lat = new double[n]; var lon = new double[n]; var vRep = new double[n]; var hAcc = new double[n]; var sAcc = new double[n];
        var alt = new double[n]; var sv = new int[n]; var sol = new GnssSolution[n]; var brk = new bool[n]; var jump = new bool[n];
        for (int i = 0; i < n; i++)
        {
            var q = track[i];
            lat[i] = q.Latitude; lon[i] = q.Longitude; vRep[i] = q.SpeedMs; hAcc[i] = q.AccuracyM;
            sAcc[i] = q.SpeedAccMs; alt[i] = double.IsFinite(q.MslAltitudeM) ? q.MslAltitudeM : double.NaN;
            sv[i] = q.NumSv; sol[i] = q.Solution;
            brk[i] = i > 0 && (t[i] - t[i - 1] > gapLimit || t[i] - t[i - 1] <= 0);
        }

        // Distance with position-jump rejection (same rule family as the engine's validation: a step is implausible when it
        // exceeds 5 x (vmax*dt + 3*(hAcc1 + hAcc2) + 0.05 m)). Distance never bridges gaps.
        var dist = new double[n];
        var stepD = new double[n];
        for (int i = 1; i < n; i++)
        {
            double d = Geo.HaversineM(track[i - 1], track[i]);
            double dt = t[i] - t[i - 1];
            double vmax = Math.Max(vRep[i], vRep[i - 1]) + 3 * Math.Max(Finite(sAcc[i], 0.05), 0.05);
            double limit = 5 * (vmax * Math.Max(dt, 0) + 3 * (Finite(hAcc[i], 0) + Finite(hAcc[i - 1], 0)) + 0.05);
            if (brk[i]) { dist[i] = dist[i - 1]; stepD[i] = double.NaN; continue; }
            if (d > limit) { jump[i] = true; dist[i] = dist[i - 1]; stepD[i] = double.NaN; continue; }
            stepD[i] = d;
            dist[i] = dist[i - 1] + d;
        }

        // Speed derived from positions: central difference where both neighbours are continuous.
        var vDer = new double[n];
        for (int i = 0; i < n; i++)
        {
            double num = 0, den = 0;
            if (i > 0 && double.IsFinite(stepD[i])) { num += stepD[i]; den += t[i] - t[i - 1]; }
            if (i + 1 < n && double.IsFinite(stepD[i + 1])) { num += stepD[i + 1]; den += t[i + 1] - t[i]; }
            vDer[i] = den > 0 ? num / den : double.NaN;
        }

        var smooth = SpeedSmoother.Smooth(t, vRep, sAcc, brk, p);

        // Lateral acceleration a_lat = v * omega, omega = (vN dvE/dt - vE dvN/dt) / v^2 (only for v >= 2 m/s, central differences).
        var aLat = new double[n];
        for (int i = 0; i < n; i++)
        {
            aLat[i] = double.NaN;
            if (i == 0 || i == n - 1 || brk[i] || brk[i + 1]) continue;
            var a = track[i - 1]; var b = track[i]; var c = track[i + 1];
            if (!double.IsFinite(b.VelNorthMs) || !double.IsFinite(a.VelNorthMs) || !double.IsFinite(c.VelNorthMs)) continue;
            double v = Math.Sqrt(b.VelNorthMs * b.VelNorthMs + b.VelEastMs * b.VelEastMs);
            if (v < 2) continue;
            double dt = t[i + 1] - t[i - 1];
            if (dt <= 0) continue;
            double dvn = (c.VelNorthMs - a.VelNorthMs) / dt, dve = (c.VelEastMs - a.VelEastMs) / dt;
            double omega = (b.VelNorthMs * dve - b.VelEastMs * dvn) / (v * v);
            double al = v * omega;
            aLat[i] = Math.Abs(al) <= 15 ? al : double.NaN;
        }

        var tl = new SessionTimeline
        {
            T = t, Lat = lat, Lon = lon, SpeedReported = vRep, SpeedDerived = vDer, SpeedFiltered = smooth.Speed,
            SpeedFilteredSigma = smooth.SpeedSigma, AccelLong = smooth.Accel, AccelLongSigma = smooth.AccelSigma, AccelLateral = aLat,
            Distance = dist, AltitudeMsl = alt, HAcc = hAcc, SpeedAcc = sAcc, NumSv = sv, Solution = sol, BreakBefore = brk, JumpBefore = jump,
            NominalDtS = nominal, Itow0Ms = itow0, Utc0 = track[0].UtcTime ?? session.StartedAt, FilterParameters = p,
        };

        // Signal-loss intervals: gaps between usable epochs plus received epochs without a valid solution.
        for (int i = 1; i < n; i++)
            if (brk[i]) tl.Losses.Add(new SignalLoss(t[i - 1], t[i], "Sin épocas GNSS utilizables"));
        double? invalidStart = null;
        foreach (var e in session.GnssEpochs)
        {
            double te = WeekDiffMs(e.GpsWeekMs, itow0) / 1000.0;
            if (e.Solution == GnssSolution.None) invalidStart ??= te;
            else if (invalidStart is double s0) { if (te - s0 > nominal) tl.Losses.Add(new SignalLoss(s0, te, "Épocas sin solución válida")); invalidStart = null; }
        }
        return tl;
    }

    private static double Finite(double v, double fallback) => double.IsFinite(v) ? v : fallback;

    /// <summary>Index of the sample nearest to t (binary search), or -1 if empty.</summary>
    public int IndexAt(double time)
    {
        if (T.Length == 0) return -1;
        int i = Array.BinarySearch(T, time);
        if (i >= 0) return i;
        i = ~i;
        if (i <= 0) return 0;
        if (i >= T.Length) return T.Length - 1;
        return time - T[i - 1] <= T[i] - time ? i - 1 : i;
    }

    /// <summary>Index of the sample nearest to cumulative distance d.</summary>
    public int IndexAtDistance(double d)
    {
        if (Distance.Length == 0) return -1;
        int i = Array.BinarySearch(Distance, d);
        if (i >= 0) return i;
        i = ~i;
        return Math.Clamp(i, 0, Distance.Length - 1);
    }

    public DateTimeOffset? UtcAt(int index) => Utc0 is DateTimeOffset u && index >= 0 && index < T.Length ? u.AddSeconds(T[index] - T[0]) : null;

    /// <summary>Seconds since the first GNSS epoch for a GPS time of week (ms).</summary>
    public double TimeOfItow(long itow) => WeekDiffMs(itow, Itow0Ms) / 1000.0;

    /// <summary>Fraction (0..1) of samples in [t0,t1] with the given minimum solution.</summary>
    public double FractionAtLeast(GnssSolution min, double t0, double t1)
    {
        int total = 0, ok = 0;
        for (int i = 0; i < T.Length; i++)
        {
            if (T[i] < t0 || T[i] > t1) continue;
            total++;
            if (Solution[i] >= min) ok++;
        }
        return total > 0 ? (double)ok / total : 0;
    }
}

/// <summary>
/// Kalman filter + Rauch–Tung–Striebel smoother of the reported ground speed. Model: state [v, a], constant-acceleration
/// with white jerk (spectral density <see cref="Parameters.JerkDensity"/>, m²/s⁵). Measurement z = gSpeed with
/// variance max(sAcc, MinSpeedSigma)², where sAcc is the speed accuracy reported by the receiver (FallbackSpeedSigma when
/// unavailable). The filter restarts after every gap, so it never interpolates through missing data.
/// Effects: removes measurement noise of the Doppler speed and yields a longitudinal acceleration with its 1-sigma
/// uncertainty; it smooths short real peaks (about 1/3 s at the defaults). The unfiltered speed is always kept.
/// </summary>
public static class SpeedSmoother
{
    public sealed record Parameters(double JerkDensity = 1.0, double MinSpeedSigma = 0.05, double FallbackSpeedSigma = 0.15,
        double InitialAccelSigma = 2.0)
    {
        public string Describe() => $"Kalman v-a + suavizado RTS · densidad de sacudida {JerkDensity:0.##} m²/s⁵ · σv mín. {MinSpeedSigma:0.###} m/s · σv sin sAcc {FallbackSpeedSigma:0.###} m/s";
    }

    public sealed record Result(double[] Speed, double[] SpeedSigma, double[] Accel, double[] AccelSigma);

    public static Result Smooth(double[] t, double[] z, double[] sAcc, bool[] breakBefore, Parameters p)
    {
        int n = t.Length;
        var v = new double[n]; var a = new double[n]; var sv = new double[n]; var sa = new double[n];
        if (n == 0) return new Result(v, sv, a, sa);
        int start = 0;
        for (int i = 1; i <= n; i++)
        {
            if (i == n || breakBefore[i])
            {
                RunPiece(t, z, sAcc, p, start, i, v, a, sv, sa);
                start = i;
            }
        }
        return new Result(v, sv, a, sa);
    }

    private static void RunPiece(double[] t, double[] z, double[] sAcc, Parameters p, int i0, int i1, double[] vOut, double[] aOut, double[] svOut, double[] saOut)
    {
        int m = i1 - i0;
        // Forward pass storage: filtered and predicted states/covariances (2x2 symmetric: [p00, p01, p11]).
        var xf = new double[m, 2]; var pf = new double[m, 3]; var xp = new double[m, 2]; var pp = new double[m, 3];
        double x0 = double.IsFinite(z[i0]) ? z[i0] : 0, x1 = 0;
        double r0 = Sigma(sAcc[i0], p);
        double p00 = r0 * r0, p01 = 0, p11 = p.InitialAccelSigma * p.InitialAccelSigma;
        for (int k = 0; k < m; k++)
        {
            int i = i0 + k;
            if (k > 0)
            {
                double dt = Math.Max(t[i] - t[i - 1], 1e-3);
                // predict
                double nx0 = x0 + dt * x1, nx1 = x1;
                double q = p.JerkDensity;
                double q00 = q * dt * dt * dt / 3, q01 = q * dt * dt / 2, q11 = q * dt;
                double n00 = p00 + 2 * dt * p01 + dt * dt * p11 + q00;
                double n01 = p01 + dt * p11 + q01;
                double n11 = p11 + q11;
                x0 = nx0; x1 = nx1; p00 = n00; p01 = n01; p11 = n11;
            }
            xp[k, 0] = x0; xp[k, 1] = x1; pp[k, 0] = p00; pp[k, 1] = p01; pp[k, 2] = p11;
            double zi = z[i];
            if (double.IsFinite(zi))
            {
                double r = Sigma(sAcc[i], p); double rr = r * r;
                double s = p00 + rr;
                double k0 = p00 / s, k1 = p01 / s;
                double y = zi - x0;
                x0 += k0 * y; x1 += k1 * y;
                double u00 = (1 - k0) * p00, u01 = (1 - k0) * p01, u11 = p11 - k1 * p01;
                p00 = u00; p01 = u01; p11 = u11;
            }
            xf[k, 0] = x0; xf[k, 1] = x1; pf[k, 0] = p00; pf[k, 1] = p01; pf[k, 2] = p11;
        }
        // RTS backward pass
        double sx0 = xf[m - 1, 0], sx1 = xf[m - 1, 1], s00 = pf[m - 1, 0], s01 = pf[m - 1, 1], s11 = pf[m - 1, 2];
        Store(m - 1);
        for (int k = m - 2; k >= 0; k--)
        {
            int i = i0 + k + 1;
            double dt = Math.Max(t[i] - t[i - 1], 1e-3);
            // C = Pf F^T Pp(k+1)^-1
            double f00 = pf[k, 0], f01 = pf[k, 1], f11 = pf[k, 2];
            // Pf F^T with F = [[1, dt],[0, 1]]: [[f00 + dt f01, f01],[f01 + dt f11, f11]]
            double a00 = f00 + dt * f01, a01 = f01, a10 = f01 + dt * f11, a11 = f11;
            double q00 = pp[k + 1, 0], q01 = pp[k + 1, 1], q11 = pp[k + 1, 2];
            double det = q00 * q11 - q01 * q01;
            if (Math.Abs(det) < 1e-18) { sx0 = xf[k, 0]; sx1 = xf[k, 1]; s00 = f00; s01 = f01; s11 = f11; Store(k); continue; }
            double i00 = q11 / det, i01 = -q01 / det, i11 = q00 / det;
            double c00 = a00 * i00 + a01 * i01, c01 = a00 * i01 + a01 * i11;
            double c10 = a10 * i00 + a11 * i01, c11 = a10 * i01 + a11 * i11;
            double d0 = sx0 - xp[k + 1, 0], d1 = sx1 - xp[k + 1, 1];
            double nx0 = xf[k, 0] + c00 * d0 + c01 * d1;
            double nx1 = xf[k, 1] + c10 * d0 + c11 * d1;
            // Ps = Pf + C (Ps(k+1) - Pp(k+1)) C^T
            double e00 = s00 - q00, e01 = s01 - q01, e11 = s11 - q11;
            double g00 = c00 * e00 + c01 * e01, g01 = c00 * e01 + c01 * e11;
            double g10 = c10 * e00 + c11 * e01, g11 = c10 * e01 + c11 * e11;
            double n00 = f00 + g00 * c00 + g01 * c01;
            double n01 = f01 + g00 * c10 + g01 * c11;
            double n11 = f11 + g10 * c10 + g11 * c11;
            sx0 = nx0; sx1 = nx1; s00 = n00; s01 = n01; s11 = n11;
            Store(k);
        }

        void Store(int k)
        {
            vOut[i0 + k] = Math.Max(0, sx0);
            aOut[i0 + k] = sx1;
            svOut[i0 + k] = Math.Sqrt(Math.Max(0, s00));
            saOut[i0 + k] = Math.Sqrt(Math.Max(0, s11));
        }
    }

    private static double Sigma(double sAcc, Parameters p) => double.IsFinite(sAcc) && sAcc > 0 ? Math.Max(sAcc, p.MinSpeedSigma) : p.FallbackSpeedSigma;
}

public static class Stats
{
    public static double Median(IEnumerable<double> values)
    {
        var a = values.Where(double.IsFinite).OrderBy(x => x).ToArray();
        if (a.Length == 0) return double.NaN;
        return a.Length % 2 == 1 ? a[a.Length / 2] : (a[a.Length / 2 - 1] + a[a.Length / 2]) / 2;
    }

    public static double MaxFinite(IEnumerable<double> values, double fallback = double.NaN)
    {
        double m = double.NegativeInfinity;
        foreach (var v in values) if (double.IsFinite(v) && v > m) m = v;
        return double.IsNegativeInfinity(m) ? fallback : m;
    }

    public static double MinFinite(IEnumerable<double> values, double fallback = double.NaN)
    {
        double m = double.PositiveInfinity;
        foreach (var v in values) if (double.IsFinite(v) && v < m) m = v;
        return double.IsPositiveInfinity(m) ? fallback : m;
    }
}


/// <summary>
/// Useful part of a training chosen by the user (start and end inside the whole recording). The original file is never
/// modified: a filtered copy of the decoded data is analysed with the time base of the full file.
/// </summary>
public static class SessionWindow
{
    public static TrainingSession Apply(TrainingSession s, long itow0, double t0, double t1)
    {
        bool In(long itow) { double t = SessionTimeline.WeekDiffMs(itow, itow0) / 1000.0; return t >= t0 && t <= t1; }
        var c = new TrainingSession
        {
            SessionId = s.SessionId, Sha256 = s.Sha256, Horse = s.Horse, Rider = s.Rider, StartedAt = s.StartedAt, SourceName = s.SourceName,
            Integrity = s.Integrity, HasRawTelemetry = s.HasRawTelemetry, DeclaredDistanceM = s.DeclaredDistanceM, DeclaredDurationS = s.DeclaredDurationS,
            DeclaredMaxSpeedMs = s.DeclaredMaxSpeedMs, TotalImuSamples = s.TotalImuSamples, TotalImuBatches = s.TotalImuBatches, InvalidFrames = s.InvalidFrames,
            MarkerCount = s.MarkerCount, ImuPeriodUs = s.ImuPeriodUs, ImuOpaqueBatches = s.ImuOpaqueBatches, FileSha256 = s.FileSha256,
            SourcePath = s.SourcePath, DeclaredCanonicalSha256 = s.DeclaredCanonicalSha256, Discipline = s.Discipline,
        };
        c.Track.AddRange(s.Track.Where(p => In(p.GpsWeekMs)));
        foreach (var e in s.GnssEpochs.Where(e => In(e.GpsWeekMs))) c.GnssEpochs.Add(e);
        c.GnssSamples = c.GnssEpochs.Count;
        c.RtkFixCount = c.Track.Count(p => p.CarrierSolution == 2);
        c.RtkFloatCount = c.Track.Count(p => p.CarrierSolution == 1);
        c.GnssOtherCount = c.Track.Count - c.RtkFixCount - c.RtkFloatCount;
        c.UnusableGnssSamples = c.GnssSamples - c.Track.Count;
        c.Imu.AddRange(s.Imu);            // clipped to the window by ImuTimeline.Build
        c.Markers.AddRange(s.Markers);
        c.Segments.AddRange(s.Segments);
        c.RawSegmentPaths.AddRange(s.RawSegmentPaths);
        return c;
    }
}
