namespace Avo.Windows.Core;

/// <summary>
/// Largest-Triangle-Three-Buckets reduction used ONLY for drawing. Calculations always use the full-resolution arrays.
/// NaN values split the series into runs; each run is reduced independently so gaps stay visible.
/// </summary>
public static class Downsampler
{
    public static int[] Lttb(double[] x, double[] y, int threshold)
    {
        int n = Math.Min(x.Length, y.Length);
        if (threshold <= 2 || n <= threshold) return Enumerable.Range(0, n).Where(i => double.IsFinite(y[i]) && double.IsFinite(x[i])).ToArray();
        var runs = new List<(int a, int b)>();
        int s = -1;
        for (int i = 0; i <= n; i++)
        {
            bool ok = i < n && double.IsFinite(y[i]) && double.IsFinite(x[i]);
            if (ok && s < 0) s = i;
            else if (!ok && s >= 0) { runs.Add((s, i - 1)); s = -1; }
        }
        int finite = runs.Sum(r => r.b - r.a + 1);
        if (finite == 0) return [];
        var result = new List<int>(threshold + runs.Count * 2);
        foreach (var (a, b) in runs)
        {
            int len = b - a + 1;
            int budget = Math.Max(2, (int)Math.Round((double)threshold * len / finite));
            if (len <= budget) { for (int i = a; i <= b; i++) result.Add(i); continue; }
            result.Add(a);
            double every = (double)(len - 2) / (budget - 2);
            int prev = a;
            for (int k = 0; k < budget - 2; k++)
            {
                int rangeStart = a + 1 + (int)Math.Floor(k * every);
                int rangeEnd = Math.Min(a + 1 + (int)Math.Floor((k + 1) * every), b);
                int nextStart = rangeEnd, nextEnd = Math.Min(a + 1 + (int)Math.Floor((k + 2) * every), b + 1);
                double avgX = 0, avgY = 0; int cnt = 0;
                for (int j = nextStart; j < nextEnd; j++) { avgX += x[j]; avgY += y[j]; cnt++; }
                if (cnt == 0) { avgX = x[b]; avgY = y[b]; } else { avgX /= cnt; avgY /= cnt; }
                double best = -1; int bestIdx = rangeStart;
                for (int j = rangeStart; j < rangeEnd; j++)
                {
                    double area = Math.Abs((x[prev] - avgX) * (y[j] - y[prev]) - (x[prev] - x[j]) * (avgY - y[prev]));
                    if (area > best) { best = area; bestIdx = j; }
                }
                result.Add(bestIdx);
                prev = bestIdx;
            }
            result.Add(b);
        }
        return result.Distinct().OrderBy(i => i).ToArray();
    }
}

/// <summary>Girth IMU series aligned to the GNSS timeline. Values stay in LSB; physical units only through the nominal
/// scale of the declared sensor (not calibrated, axis orientation not verified on the horse).</summary>
public sealed class ImuTimeline
{
    /// <summary>Nominal LSM6DS3TR-C / LSM6DSV16X configuration of girth REV B (girth_imu.cpp): ±8 g, ±2000 dps.</summary>
    public const double NominalAccelGPerLsb = 0.000244;
    public const double NominalGyroDpsPerLsb = 0.070;
    public const string ScaleNote = "Escala nominal del sensor (±8 g, ±2000 °/s) sin calibrar; orientación de ejes no verificada en el caballo.";
    /// <summary>BNO085 fixed point declared by GIRTH 0.4.3+ (header byte 15 = 1): acc Q8 m/s², gyro Q9 rad/s.</summary>
    public const double Bno085AccelGPerLsb = 1.0 / (256.0 * 9.80665);
    public const double Bno085GyroDpsPerLsb = 180.0 / Math.PI / 512.0;
    public const string Bno085ScaleNote = "Unidades declaradas por la cincha (BNO085: aceleración en m/s² Q8, giro en rad/s Q9), " +
        "calibración dinámica del propio sensor; orientación de ejes no verificada en el caballo.";
    public static string ScaleNoteFor(byte units) => units == 1 ? Bno085ScaleNote : ScaleNote;
    /// <summary>Scale actually used for this session.</summary>
    public string Note { get; private init; } = ScaleNote;
    public double AccelGPerLsb { get; private init; } = NominalAccelGPerLsb;
    public double GyroDpsPerLsb { get; private init; } = NominalGyroDpsPerLsb;

    public sealed record Channel(byte ImuId, double[] T, short[] Ax, short[] Ay, short[] Az, short[] Gx, short[] Gy, short[] Gz,
        double AccelGPerLsb = NominalAccelGPerLsb, double GyroDpsPerLsb = NominalGyroDpsPerLsb)
    {
        public string Name => ImuTimeline.SensorName(ImuId);
        public double[] AccelMagnitudeG()
        {
            var r = new double[T.Length];
            for (int i = 0; i < r.Length; i++) r[i] = Math.Sqrt((double)Ax[i] * Ax[i] + (double)Ay[i] * Ay[i] + (double)Az[i] * Az[i]) * AccelGPerLsb;
            return r;
        }
        public double[] AxisG(char axis) => (axis switch { 'x' => Ax, 'y' => Ay, _ => Az }).Select(v => v * AccelGPerLsb).ToArray();
        public double[] GyroDps(char axis) => (axis switch { 'x' => Gx, 'y' => Gy, _ => Gz }).Select(v => v * GyroDpsPerLsb).ToArray();
    }

    public List<Channel> Channels { get; } = [];

    /// <summary>Girth movement from the BNO085 fused output (IMU_SAMPLE fmt 1, GIRTH 0.4.x): linear acceleration (gravity
    /// removed) rotated to the world frame of the game rotation vector (Z up), and roll / pitch of the girth. The game
    /// rotation vector does not use the magnetometer, so the heading (yaw) drifts and is not shown.</summary>
    public sealed record FusedChannel(byte ImuId, double[] T, double[] VerticalMs2, double[] HorizontalMs2, double[] RollDeg, double[] PitchDeg)
    {
        public string Name => ImuTimeline.SensorName(ImuId);
    }
    public List<FusedChannel> Fused { get; } = [];

    /// <summary>One fused sample: lin = linear acceleration in sensor axes (Q8 m/s²), q = (i, j, k, real) in Q14.
    /// Returns world-up and horizontal linear acceleration (m/s²) and roll / pitch (degrees).</summary>
    public static (double Up, double Horizontal, double RollDeg, double PitchDeg) Fuse(short lx, short ly, short lz, short qi, short qj, short qk, short qr)
    {
        double x = qi / 16384.0, y = qj / 16384.0, z = qk / 16384.0, w = qr / 16384.0;
        double n = Math.Sqrt(x * x + y * y + z * z + w * w);
        if (n < 1e-6) return (double.NaN, double.NaN, double.NaN, double.NaN);
        x /= n; y /= n; z /= n; w /= n;
        double ax = lx / 256.0, ay = ly / 256.0, az = lz / 256.0;
        // v_world = R(q) · v_sensor
        double wx = (1 - 2 * (y * y + z * z)) * ax + 2 * (x * y - z * w) * ay + 2 * (x * z + y * w) * az;
        double wy = 2 * (x * y + z * w) * ax + (1 - 2 * (x * x + z * z)) * ay + 2 * (y * z - x * w) * az;
        double wz = 2 * (x * z - y * w) * ax + 2 * (y * z + x * w) * ay + (1 - 2 * (x * x + y * y)) * az;
        double roll = Math.Atan2(2 * (w * x + y * z), 1 - 2 * (x * x + y * y)) * 180 / Math.PI;
        double pitch = Math.Asin(Math.Clamp(2 * (w * y - z * x), -1, 1)) * 180 / Math.PI;
        return (wz, Math.Sqrt(wx * wx + wy * wy), roll, pitch);
    }
    /// <summary>Chest-to-GNSS offset used (s): t_gnss = t_chest - Offset. Median of (chest time - GNSS time) over GNSS records.</summary>
    public double OffsetS { get; private init; }
    public bool Aligned { get; private init; }
    public double SampleRateHz { get; private init; }

    /// <summary>imu_id convention in avo_payloads.h: 0 central, 1 left, 2 right.</summary>
    public static string SensorName(byte id) => id switch { 0 => "Central", 1 => "Izquierda", 2 => "Derecha", _ => $"IMU {id}" };

    public static ImuTimeline Build(TrainingSession s, SessionTimeline gnss, double t0 = double.NegativeInfinity, double t1 = double.PositiveInfinity)
    {
        double offset = 0; bool aligned = false;
        if (gnss.Count > 0)
        {
            var diffs = new List<double>();
            foreach (var p in s.Track)
                if (p.ChestUs > 0) diffs.Add(p.ChestUs / 1e6 - gnss.TimeOfItow(p.GpsWeekMs));
            if (diffs.Count > 0) { offset = Stats.Median(diffs); aligned = true; }
        }
        bool bno = s.ImuUnits == 1;
        var tl = new ImuTimeline
        {
            OffsetS = offset, Aligned = aligned, SampleRateHz = s.ImuPeriodUs > 0 ? 1e6 / s.ImuPeriodUs : 0, Note = ScaleNoteFor(s.ImuUnits),
            AccelGPerLsb = bno ? Bno085AccelGPerLsb : NominalAccelGPerLsb, GyroDpsPerLsb = bno ? Bno085GyroDpsPerLsb : NominalGyroDpsPerLsb,
        };
        foreach (var g in s.Imu.GroupBy(x => x.ImuId).OrderBy(g => g.Key))
        {
            var a = g.Where(x => x.TimeS - offset >= t0 && x.TimeS - offset <= t1).OrderBy(x => x.TimeS).ToArray();
            if (a.Length == 0) continue;
            tl.Channels.Add(new Channel(g.Key, a.Select(x => x.TimeS - offset).ToArray(), a.Select(x => x.Ax).ToArray(), a.Select(x => x.Ay).ToArray(),
                a.Select(x => x.Az).ToArray(), a.Select(x => x.Gx).ToArray(), a.Select(x => x.Gy).ToArray(), a.Select(x => x.Gz).ToArray(),
                tl.AccelGPerLsb, tl.GyroDpsPerLsb));
        }
        foreach (var g in s.ImuFused.GroupBy(x => x.ImuId).OrderBy(g => g.Key))
        {
            var a = g.Where(x => x.TimeS - offset >= t0 && x.TimeS - offset <= t1).OrderBy(x => x.TimeS).ToArray();
            if (a.Length == 0) continue;
            int n = a.Length;
            var t = new double[n]; var up = new double[n]; var hz = new double[n]; var roll = new double[n]; var pitch = new double[n];
            for (int i = 0; i < n; i++)
            {
                var f = a[i];
                t[i] = f.TimeS - offset;
                (up[i], hz[i], roll[i], pitch[i]) = Fuse(f.Lx, f.Ly, f.Lz, f.Qi, f.Qj, f.Qk, f.Qr);
            }
            tl.Fused.Add(new FusedChannel(g.Key, t, up, hz, roll, pitch));
        }
        return tl;
    }
}

/// <summary>Speed colour scale shared with Android (TrainingDetailScreen.kt): blue #2F6BFF → cyan #35D0E8 (0.33) →
/// yellow #FFC42C (0.66) → red #ED122A (1.0), linear RGB interpolation over f = clamp(v / vmax).</summary>
public static class SpeedScale
{
    private static readonly (double f, byte r, byte g, byte b)[] Stops =
    [
        (0.0, 0x2F, 0x6B, 0xFF), (0.33, 0x35, 0xD0, 0xE8), (0.66, 0xFF, 0xC4, 0x2C), (1.0, 0xED, 0x12, 0x2A),
    ];

    public static (byte r, byte g, byte b) Color(double value, double max)
    {
        double f = max > 0 && double.IsFinite(value) ? Math.Clamp(value / max, 0, 1) : 0;
        for (int i = 1; i < Stops.Length; i++)
        {
            if (f <= Stops[i].f)
            {
                var a = Stops[i - 1]; var b = Stops[i];
                double u = (f - a.f) / (b.f - a.f);
                return ((byte)Math.Round(a.r + (b.r - a.r) * u), (byte)Math.Round(a.g + (b.g - a.g) * u), (byte)Math.Round(a.b + (b.b - a.b) * u));
            }
        }
        return (Stops[^1].r, Stops[^1].g, Stops[^1].b);
    }

    /// <summary>Diverging scale for accelerations: blue (braking) → grey (0) → red (accelerating).</summary>
    public static (byte r, byte g, byte b) Diverging(double value, double maxAbs)
    {
        double f = maxAbs > 0 && double.IsFinite(value) ? Math.Clamp(value / maxAbs, -1, 1) : 0;
        (double r, double g, double b) mid = (0x93, 0x94, 0x9B);
        (double r, double g, double b) end = f >= 0 ? (0xED, 0x12, 0x2A) : (0x3D, 0x9B, 0xFF);
        double u = Math.Abs(f);
        return ((byte)Math.Round(mid.r + (end.r - mid.r) * u), (byte)Math.Round(mid.g + (end.g - mid.g) * u), (byte)Math.Round(mid.b + (end.b - mid.b) * u));
    }

    /// <summary>Colours of the GNSS solution states (Android AvoColors.rtk).</summary>
    public static (byte r, byte g, byte b) Solution(GnssSolution s) => s switch
    {
        GnssSolution.RtkFix => (0x52, 0xDD, 0x40),
        GnssSolution.RtkFloat => (0xFF, 0xC4, 0x2C),
        GnssSolution.Dgnss => (0x3D, 0x9B, 0xFF),
        GnssSolution.Autonomous => (0xC9, 0xCB, 0xD1),
        _ => (0xFF, 0x39, 0x45),
    };

    /// <summary>Gait colours of Android: stopped #6E6F76, walk #3D9BFF, trot #FFC42C, canter/gallop #ED122A.</summary>
    public static (byte r, byte g, byte b) Gait(int code) => code switch
    {
        0 => (0x6E, 0x6F, 0x76),
        1 => (0x3D, 0x9B, 0xFF),
        2 => (0xFF, 0xC4, 0x2C),
        3 => (0xED, 0x12, 0x2A),
        _ => (0x93, 0x94, 0x9B),
    };
}

/// <summary>Web Mercator (EPSG:3857) tile mathematics for the map control.</summary>
public static class TileMath
{
    public const int TileSize = 256;

    /// <summary>Global pixel coordinates at a zoom level.</summary>
    public static (double x, double y) LatLonToPixel(double lat, double lon, double zoom)
    {
        double scale = TileSize * Math.Pow(2, zoom);
        double x = (lon + 180.0) / 360.0 * scale;
        double s = Math.Sin(Math.Clamp(lat, -85.05112878, 85.05112878) * Math.PI / 180);
        double y = (0.5 - Math.Log((1 + s) / (1 - s)) / (4 * Math.PI)) * scale;
        return (x, y);
    }

    public static (double lat, double lon) PixelToLatLon(double x, double y, double zoom)
    {
        double scale = TileSize * Math.Pow(2, zoom);
        double lon = x / scale * 360.0 - 180.0;
        double n = Math.PI - 2 * Math.PI * y / scale;
        double lat = 180.0 / Math.PI * Math.Atan(Math.Sinh(n));
        return (lat, lon);
    }

    /// <summary>Metres per pixel at a latitude.</summary>
    public static double MetersPerPixel(double lat, double zoom) => Math.Cos(lat * Math.PI / 180) * 2 * Math.PI * 6378137 / (TileSize * Math.Pow(2, zoom));

    /// <summary>Largest zoom (≤ maxZoom) at which the bounding box fits in the viewport with padding.</summary>
    public static double FitZoom(double minLat, double minLon, double maxLat, double maxLon, double width, double height, double padding = 40, double maxZoom = 19)
    {
        for (double z = maxZoom; z >= 1; z -= 0.25)
        {
            var a = LatLonToPixel(maxLat, minLon, z); var b = LatLonToPixel(minLat, maxLon, z);
            if (Math.Abs(b.x - a.x) <= width - 2 * padding && Math.Abs(b.y - a.y) <= height - 2 * padding) return z;
        }
        return 1;
    }
}
