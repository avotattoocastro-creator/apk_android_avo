namespace Avo.Windows.Core.Watch;

public enum FenceType : byte { None = 0, Circle = 1, Polygon = 2 }

public readonly record struct GeoE7(int LatE7, int LonE7)
{
    public double Lat => LatE7 * 1e-7;
    public double Lon => LonE7 * 1e-7;
    public static GeoE7 Of(double lat, double lon) => new((int)Math.Round(lat * 1e7), (int)Math.Round(lon * 1e7));
    public bool Valid => LatE7 is >= -900000000 and <= 900000000 && LonE7 is >= -1800000000 and <= 1800000000 && !(LatE7 == 0 && LonE7 == 0);
}

/// <summary>Local equirectangular frame (avo_geo LocalFrame / Fence.kt LocalFrame), metres.</summary>
public sealed class LocalFrame
{
    public const double R = 6371008.8, Deg = Math.PI / 180;
    private readonly double _lat0, _lon0, _kx, _ky;
    public LocalFrame(GeoE7 r) { _lat0 = r.Lat; _lon0 = r.Lon; _ky = R * Deg; _kx = R * Deg * Math.Cos(_lat0 * Deg); }
    public LocalFrame(double lat, double lon) : this(GeoE7.Of(lat, lon)) { }
    public (double X, double Y) ToXY(GeoE7 p) => ToXY(p.Lat, p.Lon);
    public (double X, double Y) ToXY(double lat, double lon)
    {
        double dlon = lon - _lon0;
        if (dlon > 180) dlon -= 360;
        if (dlon < -180) dlon += 360;
        return (dlon * _kx, (lat - _lat0) * _ky);
    }
    public GeoE7 ToPoint(double x, double y) => GeoE7.Of(_lat0 + y / _ky, _lon0 + x / _kx);
}

/// <summary>Geofence exactly as the watch stores it (avo_geo.h FenceDef; Android Fence.kt).</summary>
public sealed record Fence(int Id, FenceType Type, string Name, GeoE7 Center = default, long RadiusCm = 0, IReadOnlyList<GeoE7>? Vertices = null)
{
    public const int MaxVertices = 24, MaxFences = 8;
    public IReadOnlyList<GeoE7> Verts => Vertices ?? [];

    public void EncodeBody(LeWriter w)
    {
        w.U8(Id).U8((byte)Type).Str(Name, 16).I32(Center.LatE7).I32(Center.LonE7).U32(RadiusCm).U8(Math.Min(Verts.Count, MaxVertices));
        foreach (var v in Verts.Take(MaxVertices)) { w.I32(v.LatE7); w.I32(v.LonE7); }
    }

    /// <summary>SET_FENCE request: u8 slot + body.</summary>
    public byte[] SetFenceRequest(int slot) { var w = new LeWriter().U8(slot); (this with { Id = slot }).EncodeBody(w); return w.ToArray(); }

    public static Fence? DecodeBody(LeReader r)
    {
        int id = r.U8(); var type = (FenceType)r.U8(); string name = r.Str(16);
        var c = new GeoE7(r.I32(), r.I32()); long radius = r.U32(); int n = r.U8();
        if (n > MaxVertices) return null;
        var v = new List<GeoE7>(n);
        for (int i = 0; i < n; i++) v.Add(new GeoE7(r.I32(), r.I32()));
        if (!Enum.IsDefined(type)) type = FenceType.None;
        return r.Ok ? new Fence(id, type, name, c, radius, v) : null;
    }

    public static Fence Empty(int slot) => new(slot, FenceType.None, "");

    /// <summary>Same checks and limits as validate_fence() in the firmware (and Fence.validate() in Android). null = valid.</summary>
    public string? Validate()
    {
        switch (Type)
        {
            case FenceType.Circle:
                if (!Center.Valid) return "Centro no válido";
                if (RadiusCm is < 500 or > 500000) return "El radio debe estar entre 5 m y 5 km";
                return null;
            case FenceType.Polygon:
                if (Verts.Count < 3) return "Un polígono necesita al menos 3 vértices";
                if (Verts.Count > MaxVertices) return $"Máximo {MaxVertices} vértices";
                if (!Verts.All(v => v.Valid)) return "Hay vértices con coordenadas no válidas";
                var fr = new LocalFrame(Verts[0]);
                var xy = Verts.Select(fr.ToXY).ToList();
                if (xy.Any(p => Math.Abs(p.X) > 10000 || Math.Abs(p.Y) > 10000)) return "La geocerca es demasiado grande (máx. 10 km)";
                int n = xy.Count;
                for (int i = 0; i < n; i++)
                {
                    int i2 = (i + 1) % n;
                    for (int j = i + 1; j < n; j++)
                    {
                        int j2 = (j + 1) % n;
                        if (j == i2 || j2 == i) continue;
                        if (Geo2.SegmentsIntersect(xy[i], xy[i2], xy[j], xy[j2])) return "El polígono se corta a sí mismo";
                    }
                }
                double a2 = 0;
                for (int i = 0; i < n; i++) { int j = (i + 1) % n; a2 += xy[i].X * xy[j].Y - xy[j].X * xy[i].Y; }
                if (Math.Abs(a2) / 2 < 25.0) return "El área es demasiado pequeña (mín. 25 m²)";
                return null;
            default:
                return "Sin tipo";
        }
    }

    /// <summary>Signed distance (m) to the boundary, negative inside, as the watch computes it.</summary>
    public double SignedDistanceM(double lat, double lon)
    {
        if (Type == FenceType.Circle)
        {
            var (x, y) = new LocalFrame(Center).ToXY(lat, lon);
            return Math.Sqrt(x * x + y * y) - RadiusCm / 100.0;
        }
        if (Type != FenceType.Polygon || Verts.Count < 3) return double.MaxValue;
        var fr = new LocalFrame(Verts[0]);
        var xy = Verts.Select(fr.ToXY).ToList();
        var (px, py) = fr.ToXY(lat, lon);
        bool inside = false; double dmin = double.MaxValue;
        for (int i = 0, j = xy.Count - 1; i < xy.Count; j = i++)
        {
            var (xi, yi) = xy[i]; var (xj, yj) = xy[j];
            if ((yi > py) != (yj > py) && px < (xj - xi) * (py - yi) / (yj - yi) + xi) inside = !inside;
            dmin = Math.Min(dmin, Geo2.SegDist(px, py, xj, yj, xi, yi));
        }
        return inside ? -dmin : dmin;
    }

    /// <summary>Circle approximated by a polygon (drawing only).</summary>
    public IReadOnlyList<GeoE7> Outline(int n = 72)
    {
        if (Type == FenceType.Polygon) return Verts;
        var fr = new LocalFrame(Center);
        double r = RadiusCm / 100.0;
        return Enumerable.Range(0, n).Select(i => { double a = 2 * Math.PI * i / n; return fr.ToPoint(r * Math.Cos(a), r * Math.Sin(a)); }).ToList();
    }
}

public static class Geo2
{
    public static double SegDist(double px, double py, double ax, double ay, double bx, double by)
    {
        double vx = bx - ax, vy = by - ay, l2 = vx * vx + vy * vy;
        double t = l2 > 0 ? ((px - ax) * vx + (py - ay) * vy) / l2 : 0;
        t = Math.Clamp(t, 0, 1);
        double dx = px - (ax + t * vx), dy = py - (ay + t * vy);
        return Math.Sqrt(dx * dx + dy * dy);
    }

    public static bool SegmentsIntersect((double X, double Y) a, (double X, double Y) b, (double X, double Y) c, (double X, double Y) d)
    {
        static int Orient((double X, double Y) p, (double X, double Y) q, (double X, double Y) r)
        {
            double v = (q.X - p.X) * (r.Y - p.Y) - (q.Y - p.Y) * (r.X - p.X);
            return Math.Abs(v) < 1e-12 ? 0 : v > 0 ? 1 : -1;
        }
        static bool OnSeg((double X, double Y) p, (double X, double Y) q, (double X, double Y) r) =>
            Math.Min(p.X, q.X) - 1e-9 <= r.X && r.X <= Math.Max(p.X, q.X) + 1e-9 && Math.Min(p.Y, q.Y) - 1e-9 <= r.Y && r.Y <= Math.Max(p.Y, q.Y) + 1e-9;
        int o1 = Orient(a, b, c), o2 = Orient(a, b, d), o3 = Orient(c, d, a), o4 = Orient(c, d, b);
        if (o1 != o2 && o3 != o4) return true;
        return (o1 == 0 && OnSeg(a, b, c)) || (o2 == 0 && OnSeg(a, b, d)) || (o3 == 0 && OnSeg(c, d, a)) || (o4 == 0 && OnSeg(c, d, b));
    }
}

/// <summary>Virtual line of the watch (avo_config.h VirtualLine): the watch counts crossings in BOTH directions; line 0 also times laps.</summary>
public sealed record VirtualLine(bool Enabled = false, int ALatE7 = 0, int ALonE7 = 0, int BLatE7 = 0, int BLonE7 = 0)
{
    public GeoE7 A => new(ALatE7, ALonE7);
    public GeoE7 B => new(BLatE7, BLonE7);
}

public enum ExitAction : byte { StopAndSave = 0, Pause = 1, Continue = 2 }

/// <summary>
/// AVO CONFIG SCHEMA v1 — byte-exact port of avo_config.cpp (and Android WatchConfig.kt):
/// "AVOC" | u16 schema | u16 0 | u32 body_len | TLV sections | u32 CRC-32. Always edited read-modify-write: the PC changes
/// only what the user touched; unknown sections are written back untouched.
/// </summary>
public sealed record WatchConfig
{
    public const int Schema = 1;
    private const int TIdentity = 1, TGeoParam = 2, TFence = 3, TDisplay = 4, TRecording = 5, TBle = 6, TTraining = 7, TLine = 8, TUart = 9, TPower = 10;

    public string DeviceName { get; init; } = "AVO-CHEST";
    public long HorseId { get; init; }
    public string HorseName { get; init; } = "";
    public long RiderId { get; init; }
    public string RiderName { get; init; } = "";
    public bool AutoEnabled { get; init; } = true;
    public int ActiveMask { get; init; } = 0x01;
    public int EntryConfirmS { get; init; } = 5;
    public int ExitConfirmS { get; init; } = 15;
    public long EntryMarginCm { get; init; } = 500;
    public long ExitMarginCm { get; init; } = 1500;
    public long HAccMaxCm { get; init; } = 1000;
    public int UncertaintyKx100 { get; init; } = 100;
    public ExitAction ExitAction { get; init; } = ExitAction.StopAndSave;
    public int PreS { get; init; } = 30;
    public int PostS { get; init; } = 15;
    public int RearmTimeoutS { get; init; }
    public int GnssLossMs { get; init; } = 3000;
    public int ResumeWindowS { get; init; } = 300;
    public int FenceCount { get; init; }
    public IReadOnlyList<Fence?> Fences { get; init; } = new Fence?[Fence.MaxFences];
    public int Brightness { get; init; } = 180;
    public int ScreenTimeoutS { get; init; } = 30;
    public bool DimOnLowBatt { get; init; } = true;
    public int FlushMs { get; init; } = 1000;
    public int FsyncMs { get; init; } = 2000;
    public int SegmentMb { get; init; } = 512;
    public long NominalRateBps { get; init; } = 32000;
    public bool BleRequireBond { get; init; } = true;
    public int SeriesSpeedCms { get; init; } = 400;
    public int SeriesMinS { get; init; } = 10;
    public IReadOnlyList<VirtualLine> Lines { get; init; } = Enumerable.Range(0, 4).Select(_ => new VirtualLine()).ToArray();
    public long UartBaud { get; init; } = 921600;
    public int LowBattPct { get; init; } = 15;
    public int CriticalBattPct { get; init; } = 5;
    public int CriticalBattMv { get; init; } = 3450;
    public IReadOnlyList<(int Tag, byte[] Body)> UnknownSections { get; init; } = [];
    public bool NewerSchema { get; init; }

    public static WatchConfig Decode(byte[] p)
    {
        if (p.Length < 16) throw new FormatException("configuración demasiado corta");
        if (p[0] != 'A' || p[1] != 'V' || p[2] != 'O' || p[3] != 'C') throw new FormatException("magic incorrecto");
        int schema = p[4] | p[5] << 8;
        long body = (uint)(p[8] | p[9] << 8 | p[10] << 16 | p[11] << 24);
        if (body + 16 != p.Length) throw new FormatException("longitud incorrecta");
        uint want = (uint)(p[^4] | p[^3] << 8 | p[^2] << 16 | p[^1] << 24);
        if (Crc32(p.AsSpan(0, p.Length - 4)) != want) throw new FormatException("CRC incorrecto");
        var c = new WatchConfig();
        var fences = new Fence?[Fence.MaxFences];
        var lines = Enumerable.Range(0, 4).Select(_ => new VirtualLine()).ToArray();
        var unknown = new List<(int, byte[])>();
        var r = new LeReader(p, 12, 12 + (int)body);
        while (r.Remaining >= 4)
        {
            int tag = r.U16(), len = r.U16();
            if (len > r.Remaining) break;
            var sec = r.Bytes(len);
            var s = new LeReader(sec);
            switch (tag)
            {
                case TIdentity when len >= 76:
                    c = c with { DeviceName = s.Str(20), HorseId = s.U32(), HorseName = s.Str(24), RiderId = s.U32(), RiderName = s.Str(24) }; break;
                case TGeoParam when len >= 30:
                    c = c with
                    {
                        AutoEnabled = s.U8() != 0, ActiveMask = s.U8(), EntryConfirmS = s.U16(), ExitConfirmS = s.U16(), EntryMarginCm = s.U32(),
                        ExitMarginCm = s.U32(), HAccMaxCm = s.U32(), UncertaintyKx100 = s.U16(), ExitAction = (ExitAction)s.U8(), PreS = s.U8(),
                        PostS = s.U8(), RearmTimeoutS = s.U16(), GnssLossMs = s.U16(), ResumeWindowS = s.U16(), FenceCount = s.U8(),
                    }; break;
                case TFence:
                    {
                        int idx = s.U8();
                        var f = Fence.DecodeBody(s);
                        if (idx < Fence.MaxFences && f is not null) fences[idx] = f;
                        break;
                    }
                case TDisplay when len >= 4: c = c with { Brightness = s.U8(), ScreenTimeoutS = s.U16(), DimOnLowBatt = s.U8() != 0 }; break;
                case TRecording when len >= 10: c = c with { FlushMs = s.U16(), FsyncMs = s.U16(), SegmentMb = s.U16(), NominalRateBps = s.U32() }; break;
                case TBle when len >= 1: c = c with { BleRequireBond = s.U8() != 0 }; break;
                case TTraining when len >= 4: c = c with { SeriesSpeedCms = s.U16(), SeriesMinS = s.U16() }; break;
                case TLine:
                    {
                        int i = s.U8();
                        if (i < 4 && s.Remaining >= 17) lines[i] = new VirtualLine(s.U8() != 0, s.I32(), s.I32(), s.I32(), s.I32());
                        break;
                    }
                case TUart when len >= 4: c = c with { UartBaud = s.U32() }; break;
                case TPower when len >= 4: c = c with { LowBattPct = s.U8(), CriticalBattPct = s.U8(), CriticalBattMv = s.U16() }; break;
                case TIdentity or TGeoParam or TDisplay or TRecording or TBle or TTraining or TUart or TPower: break;   // too short: defaults
                default: unknown.Add((tag, sec)); break;
            }
        }
        return c with { Fences = fences, Lines = lines, UnknownSections = unknown, NewerSchema = schema > Schema };
    }

    public byte[] Encode()
    {
        var w = new LeWriter();
        w.Bytes("AVOC"u8).U16(Schema).U16(0).U32(0);
        void Section(int tag, Action<LeWriter> body)
        {
            var b = new LeWriter(); body(b);
            var bytes = b.ToArray();
            w.U16(tag).U16(bytes.Length).Bytes(bytes);
        }
        Section(TIdentity, s => s.Str(DeviceName, 20).U32(HorseId).Str(HorseName, 24).U32(RiderId).Str(RiderName, 24));
        Section(TGeoParam, s => s.U8(AutoEnabled ? 1 : 0).U8(ActiveMask).U16(EntryConfirmS).U16(ExitConfirmS).U32(EntryMarginCm).U32(ExitMarginCm)
            .U32(HAccMaxCm).U16(UncertaintyKx100).U8((byte)ExitAction).U8(PreS).U8(PostS).U16(RearmTimeoutS).U16(GnssLossMs).U16(ResumeWindowS).U8(FenceCount));
        for (int i = 0; i < Math.Min(FenceCount, Fence.MaxFences); i++)
        {
            var f = (i < Fences.Count ? Fences[i] : null) ?? Fence.Empty(i);
            Section(TFence, s => { s.U8(i); f.EncodeBody(s); });
        }
        Section(TDisplay, s => s.U8(Brightness).U16(ScreenTimeoutS).U8(DimOnLowBatt ? 1 : 0));
        Section(TRecording, s => s.U16(FlushMs).U16(FsyncMs).U16(SegmentMb).U32(NominalRateBps));
        Section(TBle, s => s.U8(BleRequireBond ? 1 : 0));
        Section(TTraining, s => s.U16(SeriesSpeedCms).U16(SeriesMinS));
        for (int i = 0; i < 4; i++)
        {
            var l = i < Lines.Count ? Lines[i] : new VirtualLine();
            Section(TLine, s => s.U8(i).U8(l.Enabled ? 1 : 0).I32(l.ALatE7).I32(l.ALonE7).I32(l.BLatE7).I32(l.BLonE7));
        }
        Section(TUart, s => s.U32(UartBaud));
        Section(TPower, s => s.U8(LowBattPct).U8(CriticalBattPct).U16(CriticalBattMv));
        foreach (var (tag, b) in UnknownSections) if (tag is < 1 or > 10) w.U16(tag).U16(b.Length).Bytes(b);
        var raw = w.ToArray();
        int bodyLen = raw.Length - 12;
        for (int i = 0; i < 4; i++) raw[8 + i] = (byte)(bodyLen >> (8 * i));
        return [.. raw, .. new LeWriter().U32(Crc32(raw)).ToArray()];
    }

    /// <summary>Same ranges as config_validate() in the firmware (Spanish list of problems).</summary>
    public List<string> Problems()
    {
        var p = new List<string>();
        if (EntryConfirmS is < 0 or > 60) p.Add("Tiempo de entrada fuera de 0–60 s");
        if (ExitConfirmS is < 0 or > 120) p.Add("Tiempo de salida fuera de 0–120 s");
        if (EntryMarginCm is < 0 or > 10000) p.Add("Margen de entrada fuera de 0–100 m");
        if (ExitMarginCm is < 0 or > 10000) p.Add("Margen de salida fuera de 0–100 m");
        if (HAccMaxCm is < 50 or > 5000) p.Add("Precisión mínima fuera de 0,5–50 m");
        if (PreS is < 0 or > 60) p.Add("Pre-grabación fuera de 0–60 s");
        if (PostS is < 0 or > 60) p.Add("Post-grabación fuera de 0–60 s");
        if (Brightness is < 10 or > 255) p.Add("Brillo fuera de 10–255");
        if (UartBaud is not (115200 or 230400 or 460800 or 921600)) p.Add("Velocidad UART no admitida");
        return p;
    }

    public static uint Crc32(ReadOnlySpan<byte> d) => ChestUsbClient.Crc32(d);
}
