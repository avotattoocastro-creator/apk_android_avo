using System.Buffers.Binary;
using System.Diagnostics;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Xml.Linq;
using Avo.Windows.Core;

namespace Avo.Windows.SelfTest;

/// <summary>Automated tests of Windows Advanced Analysis V2 PRO (Core). Synthetic data only, clearly marked.</summary>
public static class V2Tests
{
    private static Action<bool, string> _assert = (_, _) => { };
    private static void A(bool ok, string what) => _assert(ok, what);

    public static void Run(string dir, Action<bool, string> assert)
    {
        _assert = assert;
        GnssClassification();
        TimelineAndFilter();
        Downsampling();
        SegmentsAndStore(dir);
        Alignment();
        TidesWeatherAndTime();
        Geometry();
        RawImuDecoding(dir);
        ImporterSecurity(dir);
        Library(dir);
        Exports(dir);
        ServerAndNetwork(dir);
        DemoSessions(dir);
    }

    // ------------------------------------------------------------------ helpers
    private static TrainingSession Straight(double hz, double secs, Func<double, double> speed, double gapFrom = -1, double gapTo = -1, int carrier = 2)
    {
        var s = new TrainingSession { SessionId = "SINTETICA_PRUEBA" };
        double lat0 = 43.4247, lon0 = -3.4519, x = 0;
        int n = (int)(secs * hz);
        for (int i = 0; i < n; i++)
        {
            double t = i / hz;
            double v = speed(t);
            if (!(t >= gapFrom && t < gapTo))
            {
                double lon = lon0 + x / (111320.0 * Math.Cos(lat0 * Math.PI / 180));
                s.Track.Add(new TrackPoint(lat0, lon, v, 0.014, carrier, 345_600_000 + (long)Math.Round(t * 1000), 52, null, 3, 26, true, 0.05, 0, v, 90, 2.0,
                    new DateTimeOffset(2026, 10, 22, 6, 15, 0, TimeSpan.Zero).AddSeconds(t), (ulong)((t + 500) * 1e6)));
                s.GnssEpochs.Add(new GnssEpoch(345_600_000 + (long)Math.Round(t * 1000), carrier == 2 ? GnssSolution.RtkFix : GnssSolution.RtkFloat, 26, 0.014, 0));
                s.GnssSamples++;
            }
            x += v / hz;
        }
        return s;
    }

    // ------------------------------------------------------------------ tests
    private static void GnssClassification()
    {
        A(GnssQuality.Classify(true, 3, true, 2, false) == GnssSolution.RtkFix, "GNSS: carrSoln 2 = RTK FIX");
        A(GnssQuality.Classify(true, 3, true, 1, false) == GnssSolution.RtkFloat, "GNSS: carrSoln 1 = RTK FLOAT");
        A(GnssQuality.Classify(true, 3, true, 0, false) == GnssSolution.Dgnss, "GNSS: diffSoln = DGNSS");
        A(GnssQuality.Classify(true, 3, false, 0, false) == GnssSolution.Autonomous, "GNSS: autónomo");
        A(GnssQuality.Classify(false, 3, true, 2, false) == GnssSolution.None && GnssQuality.Classify(true, 5, false, 0, false) == GnssSolution.None
          && GnssQuality.Classify(true, 3, false, 2, true) == GnssSolution.None, "GNSS: sin solución válida (fixOK, solo tiempo, invalidLlh)");
    }

    private static void TimelineAndFilter()
    {
        // constant acceleration 0.5 m/s² from 2 to 10 m/s with Gaussian noise 0.05 m/s on the reported speed
        var rng = new Random(7);
        double Noise() => Math.Sqrt(-2 * Math.Log(1 - rng.NextDouble())) * Math.Cos(2 * Math.PI * rng.NextDouble());
        var s = Straight(8, 16, t => 2 + 0.5 * t);
        for (int i = 0; i < s.Track.Count; i++) s.Track[i] = s.Track[i] with { SpeedMs = s.Track[i].SpeedMs + 0.05 * Noise() };
        var tl = SessionTimeline.Build(s);
        A(tl.Count == s.Track.Count && Math.Abs(tl.DurationS - (s.Track.Count - 1) / 8.0) < 1e-9, "Línea temporal: épocas y duración");
        var mid = Enumerable.Range(16, tl.Count - 32).ToArray();
        double accErr = mid.Average(i => Math.Abs(tl.AccelLong[i] - 0.5)), accBias = mid.Average(i => tl.AccelLong[i] - 0.5);
        A(Math.Abs(accBias) < 0.03 && accErr < 0.12, $"Kalman+RTS: aceleración sin sesgo (sesgo {accBias:+0.000;-0.000}, error medio {accErr:0.000} m/s²)");
        double rmsRaw = Math.Sqrt(mid.Average(i => Math.Pow(tl.SpeedReported[i] - (2 + 0.5 * tl.T[i]), 2)));
        double rmsF = Math.Sqrt(mid.Average(i => Math.Pow(tl.SpeedFiltered[i] - (2 + 0.5 * tl.T[i]), 2)));
        A(rmsF < rmsRaw, $"Kalman+RTS reduce el ruido ({rmsRaw:0.000} → {rmsF:0.000} m/s) y conserva la señal original");
        A(mid.All(i => Math.Abs(tl.SpeedDerived[i] - (2 + 0.5 * tl.T[i])) < 0.2), "Velocidad derivada de posiciones coherente");
        double expected = 2 * tl.DurationS + 0.25 * tl.DurationS * tl.DurationS;
        A(Math.Abs(tl.TotalDistanceM - expected) < 0.01 * expected, $"Distancia geodésica ({tl.TotalDistanceM:0.00} m, teórica {expected:0.00} m)");

        // 6 s gap: no bridging, loss interval, filter restart
        var g = Straight(8, 60, _ => 5, 20, 26);
        var tg = SessionTimeline.Build(g);
        A(tg.BreakBefore.Count(b => b) == 1 && tg.Losses.Count == 1 && Math.Abs(tg.Losses[0].DurationS - 6.125) < 0.01, "Pérdida de señal detectada (6 s) sin interpolar");
        A(Math.Abs(tg.TotalDistanceM - 5 * (60 - 6 - 2 * 0.125)) < 1.0, $"La distancia no puentea huecos ({tg.TotalDistanceM:0.0} m)");
        // position jump
        var j = Straight(8, 20, _ => 4);
        j.Track[80] = j.Track[80] with { Latitude = j.Track[80].Latitude + 0.01 };
        var tj = SessionTimeline.Build(j);
        A(tj.JumpBefore.Count(b => b) >= 1 && tj.TotalDistanceM < 4 * 20 + 1, "Salto de posición (1,1 km) descartado de la distancia");
        // validated acceleration excludes FLOAT/gaps with large sigma? sigma small here -> valid
        A(SegmentAnalyzer.AccelValid(tl, tl.Count / 2), "Aceleración validada con RTK FIX y σ pequeña");
        // useful window (start/end chosen by the user): same time base, only that part analysed, original untouched
        var full = SessionTimeline.Build(g);
        var cut = SessionWindow.Apply(g, full.Itow0Ms, 30, 50);
        var tw = SessionTimeline.Build(cut, null, full.Itow0Ms);
        A(Math.Abs(tw.T[0] - 30) < 0.13 && Math.Abs(tw.T[^1] - 50) < 0.13 && Math.Abs(tw.TotalDistanceM - 5 * 20 * (6371008.8 * Math.PI / 180 / 111320)) < 1.5
          && g.Track.Count == full.Count && cut.Track.Count < g.Track.Count, $"Inicio y fin del entrenamiento útil: 30–50 s, {tw.TotalDistanceM:0.0} m, misma base de tiempo, original intacto");
        // week roll-over
        A(SessionTimeline.WeekDiffMs(1000, 604_799_000) == 2000, "Cambio de semana GPS en iTOW");
        // filter on large dataset: performance target 1 h at 8 Hz < 1.5 s
        var big = Straight(8, 3600, t => 3 + Math.Sin(t / 30));
        var sw = Stopwatch.StartNew();
        var tb = SessionTimeline.Build(big);
        sw.Stop();
        A(tb.Count == 28800 && sw.ElapsedMilliseconds < 1500, $"Rendimiento: línea temporal de 1 h a 8 Hz en {sw.ElapsedMilliseconds} ms (< 1500 ms)");
    }

    private static void Downsampling()
    {
        var x = Enumerable.Range(0, 100_000).Select(i => (double)i).ToArray();
        var y = x.Select(v => Math.Sin(v / 500) + (v == 50_000 ? 10 : 0)).ToArray();
        y[70_000] = double.NaN;
        var idx = Downsampler.Lttb(x, y, 1000);
        A(idx.Length <= 1010 && idx[0] == 0 && idx[^1] == 99_999, $"LTTB: {idx.Length} puntos, conserva extremos");
        A(idx.Contains(50_000), "LTTB conserva el pico (solo visualización)");
        A(!idx.Contains(70_000) && idx.Contains(69_999) && idx.Contains(70_001), "LTTB respeta los huecos (NaN)");
    }

    private static void SegmentsAndStore(string dir)
    {
        var s = Straight(8, 400, t => t < 100 ? 1.5 : t < 200 ? 3.6 : t < 300 ? 7 : 1.4);
        var tl = SessionTimeline.Build(s);
        var byDist = SegmentAnalyzer.ByDistance(tl, 500);
        A(byDist.Count == (int)Math.Ceiling(tl.TotalDistanceM / 500) && byDist.All(d => d.Kind == SegmentKind.Distance), $"Tramos automáticos de 500 m ({byDist.Count})");
        var bands = SegmentAnalyzer.BySpeedBand(tl);
        A(bands.Count == 4, $"Tramos por banda de velocidad ({bands.Count}: {string.Join(", ", bands.Select(b => b.Name))})");
        var m = SegmentAnalyzer.Compute(tl, new SegmentDefinition { Name = "galope", T0 = 210, T1 = 290 });
        A(Math.Abs(m.DistanceM - 7 * 80) < 2 && Math.Abs(m.MaxSpeedKmh!.Value - 25.2) < 0.5 && Math.Abs(m.MeanSpeedKmh!.Value - 25.2) < 0.3, "Métricas de tramo (distancia, v. máx, v. media)");
        A(m.FixFraction == 1 && m.Cadence is null && m.Observations.Contains("sin datos de cincha"), "Tramo sin cincha: regularidad no disponible, sin inventar");
        var whole = SegmentAnalyzer.Compute(tl, new SegmentDefinition { T0 = 0, T1 = 400 });
        A(whole.SpeedChanges == 3 && whole.MaxAccel > 0 && whole.MaxDecel < 0, $"Cambios de ritmo ({whole.SpeedChanges}) y aceleración/frenada validadas");
        var store = new SegmentStore(Path.Combine(dir, "tramos"));
        store.Save("SINTETICA_PRUEBA", [new SegmentDefinition { Name = "Tramo 1", T0 = 1, T1 = 2, Notes = "nota" }]);
        var back = store.Load("SINTETICA_PRUEBA");
        A(back.Count == 1 && back[0].Name == "Tramo 1" && back[0].Notes == "nota", "Tramos guardados y recuperados (JSON versionado)");
        A(store.Load("OTRA").Count == 0, "Tramos de otra sesión no se mezclan");
    }

    private static void Alignment()
    {
        var a = SessionTimeline.Build(Straight(8, 100, _ => 4));
        var b = SessionTimeline.Build(Straight(4, 80, _ => 5, 30, 40));
        var al = SeriesAligner.Align([a, b], t => t.SpeedFiltered, AlignmentMode.RelativeTime, 1);
        A(al.Axis.Length == 100 && al.Values[0].Length == 100 && al.Values.Count == 2, "Alineación por tiempo: rejilla común con frecuencias distintas");
        A(double.IsNaN(al.Values[1][35]) && Math.Abs(al.Values[1][20] - 5) < 0.05 && double.IsNaN(al.Values[1][90]), "Sin interpolar a través de huecos ni más allá del final");
        var ad = SeriesAligner.Align([a, b], t => t.SpeedFiltered, AlignmentMode.Distance, 5);
        A(ad.Axis.Length > 70 && Math.Abs(ad.Values[0][20] - 4) < 0.05, "Alineación por distancia recorrida");
    }

    private static void TidesWeatherAndTime()
    {
        string ports = """{"estaciones":{"puertos":[{"id":"21","puerto":"Santander","lat":"43.4613","lon":"-3.7914"},{"id":"99","puerto":"Sin coordenadas","lat":"","lon":""}]}}""";
        var p = IhmTides.ParsePorts(ports);
        A(p.Count == 1 && p[0].Name == "Santander" && Math.Abs(p[0].DistanceKmTo(43.4247, -3.4519) - 27.6) < 2, "IHM: lista de puertos (coordenadas en texto)");
        string month = """{"mareas":{"datos":{"marea":[{"fecha":"2026-10-22","hora":"02:10","altura":"4,10","tipo":"pleamar"},{"fecha":"2026-10-22","hora":"08:25","altura":"0,90","tipo":"bajamar"},{"fecha":"2026-10-22","hora":"14:40","altura":"4,00","tipo":"pleamar"}]}}}""";
        var ex = IhmTides.ParseMonth(month);
        A(ex.Count == 3 && ex[0].High && !ex[1].High && Math.Abs(ex[0].HeightM - 4.1) < 1e-9 && ex[0].Utc.Offset == TimeSpan.Zero, "IHM: pleamar/bajamar en UTC y coma decimal");
        var tp = new TidePrediction { Source = IhmTides.SourceName, Port = p[0], Extremes = ex };
        var midT = ex[0].Utc + (ex[1].Utc - ex[0].Utc) / 2;
        A(Math.Abs(tp.HeightAt(midT)!.Value - 2.5) < 1e-6 && tp.TrendAt(midT) == "bajando", "Interpolación coseno entre extremos y tendencia");
        A(tp.HeightAt(ex[0].Utc.AddHours(-3)) is null && tp.Kind == DataKind.Prediccion, "Fuera de los datos: «Sin datos»; tipo = predicción");
        string w = """{"hourly":{"time":["2026-10-22T06:00","2026-10-22T07:00"],"temperature_2m":[14.2,null],"wind_speed_10m":[12,13],"pressure_msl":[1018,1018.4]}}""";
        string sea = """{"hourly":{"time":["2026-10-22T06:00"],"wave_height":[0.8],"wave_period":[9]}}""";
        var hours = WeatherModel.ParseHourly(w, sea);
        var wm = new WeatherModel { Source = "prueba", Latitude = 0, Longitude = 0, Hours = hours };
        var h = wm.At(new DateTimeOffset(2026, 10, 22, 6, 20, 0, TimeSpan.Zero));
        A(hours.Count == 2 && h is not null && h.TemperatureC == 14.2 && h.WaveHeightM == 0.8 && hours[1].TemperatureC is null, "Open-Meteo: valores nulos quedan «Sin datos»");
        A(wm.At(new DateTimeOffset(2026, 10, 22, 12, 0, 0, TimeSpan.Zero)) is null && wm.Kind == DataKind.Modelo, "Sin hora cercana: no se inventa; tipo = modelo");
        // Europe/Madrid, DST
        A(MadridTime.Format(new DateTimeOffset(2026, 7, 1, 10, 0, 0, TimeSpan.Zero), "HH:mm") == "12:00", "Europe/Madrid verano (UTC+2)");
        A(MadridTime.Format(new DateTimeOffset(2026, 1, 15, 10, 0, 0, TimeSpan.Zero), "HH:mm") == "11:00", "Europe/Madrid invierno (UTC+1)");
        var before = new DateTimeOffset(2026, 10, 25, 0, 30, 0, TimeSpan.Zero); var after = new DateTimeOffset(2026, 10, 25, 1, 30, 0, TimeSpan.Zero);
        A(MadridTime.Format(before, "HH:mm") == "02:30" && MadridTime.Format(after, "HH:mm") == "02:30" && MadridTime.ZoneLabel(before) != MadridTime.ZoneLabel(after),
            "Cambio de hora 25/10/2026: misma hora local con zonas distintas");
        A(MadridTime.Format(new DateTimeOffset(2026, 10, 22, 22, 30, 0, TimeSpan.Zero), "dd/MM HH:mm") == "23/10 00:30", "Sesión que cruza medianoche local");
    }

    private static void Geometry()
    {
        var px = TileMath.LatLonToPixel(43.4247, -3.4519, 15);
        var ll = TileMath.PixelToLatLon(px.x, px.y, 15);
        A(Math.Abs(ll.lat - 43.4247) < 1e-9 && Math.Abs(ll.lon + 3.4519) < 1e-9, "Web Mercator: ida y vuelta");
        A(TileMath.FitZoom(43.42, -3.46, 43.43, -3.44, 1000, 700) is > 13 and < 17, "Ajuste de zoom al recorrido");
        A(SpeedScale.Color(0, 10) == (0x2F, 0x6B, 0xFF) && SpeedScale.Color(10, 10) == (0xED, 0x12, 0x2A) && SpeedScale.Color(3.3, 10) == (0x35, 0xD0, 0xE8),
            "Escala de velocidad idéntica a Android (azul → cian → amarillo → rojo)");
    }

    // RAW writer for IMU frames (same layout as the chest writer)
    private static uint Crc32(ReadOnlySpan<byte> b)
    {
        uint c = 0xFFFFFFFF;
        foreach (byte x in b) { c ^= x; for (int i = 0; i < 8; i++) c = (c & 1) != 0 ? (c >> 1) ^ 0xEDB88320 : c >> 1; }
        return c ^ 0xFFFFFFFF;
    }
    private static byte Crc8(ReadOnlySpan<byte> b)
    {
        byte c = 0;
        foreach (byte v in b) { c ^= v; for (int i = 0; i < 8; i++) c = (byte)((c & 0x80) != 0 ? (c << 1) ^ 0x07 : c << 1); }
        return c;
    }
    private static byte[] Uart(byte type, byte[] payload)
    {
        var f = new byte[19 + payload.Length];
        f[0] = 0xA5; f[1] = 0x5A; f[3] = type; f[5] = 2;
        BinaryPrimitives.WriteUInt16LittleEndian(f.AsSpan(8), (ushort)payload.Length);
        f[14] = Crc8(f.AsSpan(2, 12));
        payload.CopyTo(f.AsSpan(15));
        BinaryPrimitives.WriteUInt32LittleEndian(f.AsSpan(f.Length - 4), Crc32(f.AsSpan(2, 13 + payload.Length)));
        return f;
    }
    private static byte[] Raw(string id, params (byte recType, ulong chestUs, byte[] data)[] recs)
    {
        var header = new byte[512];
        "AVORAW1\0"u8.CopyTo(header);
        BinaryPrimitives.WriteUInt16LittleEndian(header.AsSpan(8), 1); BinaryPrimitives.WriteUInt16LittleEndian(header.AsSpan(10), 512);
        Encoding.UTF8.GetBytes(id).CopyTo(header.AsSpan(12));
        BinaryPrimitives.WriteUInt32LittleEndian(header.AsSpan(508), Crc32(header.AsSpan(0, 508)));
        var body = new List<byte>();
        foreach (var (t, us, d) in recs)
        {
            var r = new byte[12 + d.Length];
            r[0] = t; BinaryPrimitives.WriteUInt16LittleEndian(r.AsSpan(2), (ushort)d.Length); BinaryPrimitives.WriteUInt64LittleEndian(r.AsSpan(4), us);
            d.CopyTo(r.AsSpan(12));
            body.AddRange(r);
        }
        var payload = body.ToArray();
        var block = new byte[36 + payload.Length];
        BinaryPrimitives.WriteUInt32LittleEndian(block, 0x424F5641); BinaryPrimitives.WriteUInt32LittleEndian(block.AsSpan(4), 1);
        BinaryPrimitives.WriteUInt32LittleEndian(block.AsSpan(8), (uint)payload.Length);
        BinaryPrimitives.WriteUInt16LittleEndian(block.AsSpan(12), (ushort)recs.Length); BinaryPrimitives.WriteUInt16LittleEndian(block.AsSpan(14), 2);
        BinaryPrimitives.WriteUInt32LittleEndian(block.AsSpan(28), Crc32(payload)); BinaryPrimitives.WriteUInt32LittleEndian(block.AsSpan(32), Crc32(block.AsSpan(0, 32)));
        payload.CopyTo(block.AsSpan(36));
        return [.. header, .. block];
    }
    private static byte[] Imu(byte imuId, byte fmt, params short[][] samples)
    {
        var p = new byte[24 + samples.Length * 18];
        p[1] = imuId; p[2] = (byte)samples.Length; p[3] = fmt;
        BinaryPrimitives.WriteUInt16LittleEndian(p.AsSpan(12), 9615);
        for (int i = 0; i < samples.Length; i++)
            for (int k = 0; k < 9; k++) BinaryPrimitives.WriteInt16LittleEndian(p.AsSpan(24 + i * 18 + 2 * k), samples[i][k]);
        return p;
    }

    private static void RawImuDecoding(string dir)
    {
        short[] s1 = [10, -20, 4096, 70, -70, 140, 1, 2, 3], s2 = [11, -21, 4100, 71, -71, 141, 4, 5, 6];
        var raw = Raw("SINTETICA_IMU", (1, 2_000_000, Uart(0x20, Imu(2, 0, s1, s2))), (1, 2_100_000, Uart(0x20, Imu(1, 7, s1))),
            (1, 2_200_000, Uart(0x20, Imu(0, 0, s1)[..30])), (5, 2_300_000, [0, 3, 0, 0, 0]));
        string f = Path.Combine(dir, "imu.avr");
        File.WriteAllBytes(f, raw);
        var s = TrainingImporter.Import(f);
        A(s.Imu.Count == 2 && s.Imu[0].ImuId == 2 && s.Imu[1].Az == 4100 && s.Imu[0].Gz == 140 && s.Imu[1].Mz == 6, "IMU_SAMPLE fmt 0: 9 ejes int16 decodificados (LSB)");
        A(Math.Abs(s.Imu[1].TimeS - 2.0) < 1e-9 && Math.Abs(s.Imu[0].TimeS - (2.0 - 0.009615)) < 1e-9 && s.ImuPeriodUs == 9615, "Tiempos IMU: reloj del pecho y periodo nominal");
        A(s.ImuOpaqueBatches == 1 && s.InvalidFrames == 1, "Formato IMU desconocido conservado como opaco; lote truncado rechazado");
        A(s.Markers.Count == 1 && s.Markers[0].Count == 3 && s.Markers[0].SourceName == "Botón", "Registro MARKER binario (origen + contador)");
        A(Math.Abs(s.Imu[1].Az * ImuTimeline.NominalAccelGPerLsb - 1.0004) < 1e-3 && ImuTimeline.SensorName(1) == "Izquierda", "Escala nominal ±8 g y asignación de sensores");
    }

    private static string Zip(string dir, string name, Action<ZipArchive> fill)
    {
        string p = Path.Combine(dir, name);
        if (File.Exists(p)) File.Delete(p);
        using var z = ZipFile.Open(p, ZipArchiveMode.Create);
        fill(z);
        return p;
    }
    private static void Entry(ZipArchive z, string name, byte[] data) { using var s = z.CreateEntry(name).Open(); s.Write(data); }
    private static byte[] Manifest(string id, Dictionary<string, string> hashes, int? segments = null) =>
        JsonSerializer.SerializeToUtf8Bytes(new { format = "AVO-TRAINING-1", sessionId = id, horseName = "Rayo", riderName = "Antonio", segments = segments ?? hashes.Count, segmentHashes = hashes });
    private static bool Rejects(string path)
    {
        try { TrainingImporter.Import(path, Path.Combine(Path.GetDirectoryName(path)!, "rawcache")); return false; }
        catch (InvalidDataException) { return true; }
    }

    private static void ImporterSecurity(string dir)
    {
        var raw = Raw("SINTETICA_ZIP", (5, 1, [0, 1, 0, 0, 0]));
        string sha = Convert.ToHexString(SHA256.HashData(raw)).ToLowerInvariant();
        A(Rejects(Zip(dir, "slip.avo", z => { Entry(z, "manifest.json", Manifest("SINTETICA_ZIP", new() { ["../evil.avr"] = sha })); Entry(z, "segments/../evil.avr", raw); })),
            "ZIP con ruta arbitraria (../) rechazado");
        A(Rejects(Zip(dir, "hash.avo", z => { Entry(z, "manifest.json", Manifest("SINTETICA_ZIP", new() { ["P001.avr"] = new string('0', 64) })); Entry(z, "segments/P001.avr", raw); })),
            "SHA-256 de segmento incorrecto rechazado");
        A(Rejects(Zip(dir, "count.avo", z => { Entry(z, "manifest.json", Manifest("SINTETICA_ZIP", new() { ["P001.avr"] = sha }, 2)); Entry(z, "segments/P001.avr", raw); })),
            "Número de segmentos inconsistente rechazado (sesión incompleta)");
        A(Rejects(Zip(dir, "nomanifest.avo", z => { Entry(z, "segments/P001.avr", raw); Entry(z, "segments/P002.avr", raw); })), "ZIP sin manifest.json rechazado");
        A(Rejects(Zip(dir, "bomb.avo", z => { Entry(z, "manifest.json", Manifest("SINTETICA_ZIP", new() { ["P001.avr"] = sha })); Entry(z, "segments/P001.avr", new byte[51 * 1024 * 1024]); })),
            "Segmento descomprimido > 50 MB rechazado (protección ZIP)");
        string ok = Zip(dir, "ok.avo", z => { Entry(z, "manifest.json", [0xEF, 0xBB, 0xBF, .. Manifest("SINTETICA_ZIP", new() { ["P001.avr"] = sha })]); Entry(z, "segments/P001.avr", raw); });
        var s = TrainingImporter.Import(ok, Path.Combine(dir, "rawcache"));
        A(s.SessionId == "SINTETICA_ZIP" && s.IsSynthetic && s.Integrity.Contains("SHA-256"), "Paquete válido (con BOM) importado y marcado como sintético");
        string exe = Path.Combine(dir, "x.exe"); File.WriteAllBytes(exe, raw);
        A(Rejects(exe), "Extensión no admitida rechazada");
    }

    private static void Library(string dir)
    {
        var paths = new AppPaths(Path.Combine(dir, "app"));
        var lib = new TrainingLibrary(paths);
        var raw = Raw("SINTETICA_LIB", (5, 1, [0, 1, 0, 0, 0]));
        string f = Path.Combine(dir, "lib.avr"); File.WriteAllBytes(f, raw);
        string before = TrainingLibrary.FileSha256(f);
        var a = lib.Import(f, []);
        var b = new TrainingLibrary(paths).Import(f, ["SINTETICA_LIB"]);
        A(a.Session is not null && !a.Duplicate && b.Duplicate && b.Session?.SessionId == "SINTETICA_LIB", "Biblioteca: duplicado detectado por SHA-256 (también tras reiniciar)");
        A(TrainingLibrary.FileSha256(f) == before && File.Exists(Path.Combine(paths.Library, before + ".avr")), "Original intacto y copia verificada en la biblioteca");
        string bad = Path.Combine(dir, "bad.avr"); File.WriteAllBytes(bad, raw[..100]);
        var c = lib.Import(bad, []);
        A(c.Session is null && c.Error is not null && !File.Exists(Path.Combine(paths.Library, TrainingLibrary.FileSha256(bad) + ".avr")), "Archivo truncado rechazado sin dejar copia");
    }

    private static void Exports(string dir)
    {
        var s = Straight(8, 120, t => 3 + t / 40, 60, 63);
        s.Horse = "Rayo"; s.Rider = "Antonio";
        var tl = SessionTimeline.Build(s);
        var segs = new[] { SegmentAnalyzer.Compute(tl, new SegmentDefinition { Name = "T1", T0 = 10, T1 = 50 }) };
        var data = new ReportData { Session = s, Timeline = tl, Segments = segs, Notes = "Arena compacta.\nSegunda línea con acentos: ñ á é." };
        string pdf = Path.Combine(dir, "r.pdf");
        using (var fs = File.Create(pdf)) ReportBuilder.WritePdf(data, fs);
        var bytes = File.ReadAllBytes(pdf);
        string text = Encoding.Latin1.GetString(bytes);
        A(text.StartsWith("%PDF-1.4", StringComparison.Ordinal) && text.TrimEnd().EndsWith("%%EOF", StringComparison.Ordinal), "PDF: cabecera y final");
        int xref = int.Parse(text[(text.LastIndexOf("startxref", StringComparison.Ordinal) + 10)..].Split('\n')[0]);
        var lines = text[xref..].Split('\n');
        int count = int.Parse(lines[1].Split(' ')[1]);
        bool offsetsOk = true;
        for (int i = 1; i < count; i++)
        {
            int off = int.Parse(lines[2 + i][..10]);
            offsetsOk &= text[off..].StartsWith($"{i} 0 obj", StringComparison.Ordinal);
        }
        A(offsetsOk && count > 6, $"PDF: tabla xref válida ({count - 1} objetos)");
        int st = text.IndexOf("stream\n", StringComparison.Ordinal) + 7, en = text.IndexOf("\nendstream", st, StringComparison.Ordinal);
        using var z = new ZLibStream(new MemoryStream(bytes[st..en]), CompressionMode.Decompress);
        using var rd = new StreamReader(z, Encoding.Latin1);
        string content = rd.ReadToEnd();
        A(content.Contains("BT /F2") && content.Contains("Informe de entrenamiento") && content.Contains("DEMOSTRACI\\323N"), "PDF: contenido comprimido con texto WinAnsi (Ó)");
        A(Math.Abs(PdfDocument.MeasureText("AVO", 10, true) - (722 + 667 + 778) / 100.0) < 1e-9, "PDF: métricas Helvetica-Bold");
        string html = ReportBuilder.Html(data);
        A(html.Contains("DEMOSTRACIÓN") && html.Contains("<svg") && html.Contains("Arena compacta"), "HTML imprimible con mapa SVG y notas");
        string csv = Path.Combine(dir, "t.csv"); AnalysisExport.TimelineCsv(tl, csv);
        var rows = File.ReadAllLines(csv);
        A(rows.Length == tl.Count + 1 && rows[0].Contains("velocidad_filtrada_ms") && rows.Count(r => r.EndsWith(";1;0", StringComparison.Ordinal)) == 1, "CSV con unidades, valores originales y marca de corte");
        string gpx = Path.Combine(dir, "t.gpx"); AnalysisExport.Gpx(s, tl, gpx);
        var xd = XDocument.Load(gpx);
        XNamespace ns = "http://www.topografix.com/GPX/1/1";
        A(xd.Descendants(ns + "trkpt").Count() == tl.Count && xd.Descendants(ns + "trkseg").Count() == 2 && xd.Descendants(ns + "time").Any(), "GPX 1.1 con hora UTC y segmento nuevo tras el hueco");
        using var jd = JsonDocument.Parse(AnalysisExport.Json(s, tl, segs, null, true));
        A(jd.RootElement.GetProperty("formato").GetString() == AnalysisExport.JsonFormat && jd.RootElement.GetProperty("version_formato").GetInt32() == 1
          && jd.RootElement.GetProperty("tramos").GetArrayLength() == 1 && jd.RootElement.GetProperty("tramos")[0].GetProperty("cadencia_trancos_min").ValueKind == JsonValueKind.Null,
            "JSON versionado: ausencias como null, no como cifras");
    }

    private sealed class FailingHandler : HttpMessageHandler
    {
        public int Calls;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct) { Calls++; throw new HttpRequestException("sin red (prueba)"); }
    }

    private static void ServerAndNetwork(string dir)
    {
        var h = new FailingHandler();
        var env = new EnvironmentService(Path.Combine(dir, "env"), new HttpClient(h));
        bool threw = false;
        try { env.PortsAsync(CancellationToken.None).GetAwaiter().GetResult(); } catch (HttpRequestException) { threw = true; }
        A(threw && h.Calls == 1, "Sin red y sin copia local: error informado, ningún dato inventado");
        bool ns = false;
        try { new PendingContractServerClient().ListSessionsAsync(CancellationToken.None).GetAwaiter().GetResult(); } catch (NotSupportedException) { ns = true; }
        A(ns && new PendingContractServerClient().State == ServerState.ContractPending, "Servidor: contrato pendiente, sin endpoints inventados");
        bool http = false, ext = false;
        try { HttpsDownloader.DownloadAvoAsync(new Uri("http://example.org/a.avo"), dir, null, CancellationToken.None).GetAwaiter().GetResult(); } catch (InvalidDataException) { http = true; }
        try { HttpsDownloader.DownloadAvoAsync(new Uri("https://example.org/a.exe"), dir, null, CancellationToken.None).GetAwaiter().GetResult(); } catch (InvalidDataException) { ext = true; }
        A(http && ext, "Descarga manual: solo HTTPS y archivos .avo");
        var settings = new AppSettings();
        string sf = Path.Combine(dir, "ajustes.json"); settings.Save(sf);
        string stext = File.ReadAllText(sf);
        A(!stext.Contains("password", StringComparison.OrdinalIgnoreCase) && !stext.Contains("token", StringComparison.OrdinalIgnoreCase) && AppSettings.Load(sf).Map == MapProvider.EsriSatellite,
            "Ajustes sin secretos (NTRIP, tokens) y recuperables");
    }

    private static void DemoSessions(string dir)
    {
        string? demo = Environment.GetEnvironmentVariable("AVO_DEMO_DIR");
        string file = demo is null ? "" : Path.Combine(demo, "DEMO_REGATON_20261022.avr");
        if (!File.Exists(file))
        {
            A(Environment.GetEnvironmentVariable("AVO_REQUIRE_DEMO") != "1", "Sesiones de demostración requeridas en CI");
            Console.WriteLine("AVISO: AVO_DEMO_DIR no definido; pruebas con sesiones de demostración omitidas");
            return;
        }
        var sw = Stopwatch.StartNew();
        var s = TrainingImporter.Import(file);
        var tl = SessionTimeline.Build(s);
        var imu = ImuTimeline.Build(s, tl);
        sw.Stop();
        A(s.IsSynthetic && s.Horse.Contains("demo") && imu.Channels.Count == 3 && Math.Abs(imu.SampleRateHz - 104) < 0.1, "Demostración: 3 IMU a 104 Hz, marcada como sintética");
        A(sw.ElapsedMilliseconds < 5000, $"Rendimiento: importar + series de 20 min con 3 IMU en {sw.ElapsedMilliseconds} ms (< 5000 ms)");
        A(tl.Losses.Any(l => l.DurationS is > 5 and < 8) && tl.FractionAtLeast(GnssSolution.RtkFix, 0, 1e9) is > 0.8 and < 1, "Demostración: pérdida de 6 s y periodos FLOAT/autónomos detectados");
        A(Math.Abs(imu.OffsetS - 500) < 0.05 && imu.Aligned, $"Alineación reloj pecho → GNSS ({imu.OffsetS:0.000} s)");
        A(tl.Utc0 is DateTimeOffset u && u.Year == 2026 && MadridTime.Format(u, "HH:mm") == "08:15", "Hora UTC del receptor → 08:15 Europe/Madrid");
        A(Stats.MaxFinite(tl.SpeedFiltered) * 3.6 is > 38 and < 44, "Velocidad máxima de la demostración (galope ~41 km/h)");
        if (EquineEngine.Available)
        {
            var e = EquineAnalysis.Parse(EquineEngine.AnalyseJson([file], EquineEngine.Options(true, Path.Combine(dir, "eng"))));
            double off = SessionTimeline.WeekDiffMs(tl.Itow0Ms, e.Itow0Ms ?? tl.Itow0Ms) / 1000.0;
            A(e.HasImu && e.Segments.Any(x => x.GaitCode == "CANTER_GALLOP") && e.Segments.Any(x => x.GaitCode == "WALK"), "Motor: aires de la demostración (paso … galope)");
            var m = SegmentAnalyzer.Compute(tl, new SegmentDefinition { T0 = 400, T1 = 500 }, e, off);
            A(m.Cadence is > 80 and < 95 && m.CycleCorrelation > 0.9, $"Cadencia del tramo de trote vía motor ({m.Cadence:0} ciclos/min)");
            var data = new ReportData { Session = s, Timeline = tl, Engine = e };
            using var ms = new MemoryStream();
            ReportBuilder.WritePdf(data, ms);
            A(ms.Length > 20_000, $"Informe PDF de la demostración ({ms.Length / 1024} KB)");
        }
    }
}
