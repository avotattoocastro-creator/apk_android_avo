using Avo.Windows.Core;
using Avo.Windows.SelfTest;
using System.Buffers.Binary;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

int passed = 0;
void Assert(bool condition, string description)
{
    if (!condition) throw new InvalidOperationException("FAILED: " + description);
    Console.WriteLine("PASS: " + description);
    passed++;
}
uint Crc(ReadOnlySpan<byte> data)
{
    uint crc = 0xFFFFFFFF;
    foreach (byte c in data)
    {
        crc ^= c;
        for (int i = 0; i < 8; i++) crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
    return crc ^ 0xFFFFFFFF;
}
byte Crc8(ReadOnlySpan<byte> data)
{
    byte crc = 0;
    foreach (var c in data)
    {
        crc ^= c;
        for (int i = 0; i < 8; i++) crc = (byte)((crc & 0x80) != 0 ? crc << 1 ^ 7 : crc << 1);
    }
    return crc;
}
void W16(byte[] bytes, int offset, ushort value) => BinaryPrimitives.WriteUInt16LittleEndian(bytes.AsSpan(offset, 2), value);
void W32(byte[] bytes, int offset, uint value) => BinaryPrimitives.WriteUInt32LittleEndian(bytes.AsSpan(offset, 4), value);
void W64(byte[] bytes, int offset, ulong value) => BinaryPrimitives.WriteUInt64LittleEndian(bytes.AsSpan(offset, 8), value);
byte[] Frame(uint gpsTimeMs, int latE7, int lonE7, int speedMmS)
{
    var sample = new byte[85];
    W32(sample, 0, gpsTimeMs);
    W16(sample, 4, 2026);
    sample[6] = 10; sample[7] = 22;
    sample[20] = 3; sample[21] = 0x81; sample[24] = 17;
    W32(sample, 25, unchecked((uint)lonE7));
    W32(sample, 29, unchecked((uint)latE7));
    W32(sample, 33, 2500);
    W32(sample, 41, 450);
    W32(sample, 61, (uint)speedMmS);
    sample[84] = 10;
    var frame = new byte[19 + sample.Length];
    frame[0] = 0xA5; frame[1] = 0x5A; frame[3] = 0x10; frame[5] = 2;
    W16(frame, 8, (ushort)sample.Length);
    frame[14] = Crc8(frame.AsSpan(2, 12));
    sample.CopyTo(frame.AsSpan(15));
    W32(frame, frame.Length - 4, Crc(frame.AsSpan(2, 13 + sample.Length)));
    return frame;
}
byte[] Record(byte[] frame, ulong chestUs)
{
    var record = new byte[12 + frame.Length];
    record[0] = 1;
    W16(record, 2, (ushort)frame.Length);
    W64(record, 4, chestUs);
    frame.CopyTo(record.AsSpan(12));
    return record;
}
byte[] BuildRaw(string rawSessionId = "DEMO_INTEGRATION_001")
{
    var header = new byte[512];
    "AVORAW1\0"u8.CopyTo(header);
    W16(header, 8, 1); W16(header, 10, 512);
    Encoding.UTF8.GetBytes(rawSessionId).CopyTo(header.AsSpan(12));
    W64(header, 40, 1792656000000);
    Encoding.UTF8.GetBytes("Rayo").CopyTo(header.AsSpan(124));
    Encoding.UTF8.GetBytes("Antonio").CopyTo(header.AsSpan(152));
    W32(header, 508, Crc(header.AsSpan(0, 508)));
    var records = Record(Frame(100000, 434135000, -34920000, 8200), 1234567)
        .Concat(Record(Frame(101000, 434135500, -34919700, 11200), 2234567)).ToArray();
    var block = new byte[36 + records.Length];
    W32(block, 0, 0x424F5641); W32(block, 4, 1); W32(block, 8, (uint)records.Length);
    W16(block, 12, 2); W16(block, 14, 2);
    W32(block, 28, Crc(records)); W32(block, 32, Crc(block.AsSpan(0, 32)));
    records.CopyTo(block.AsSpan(36));
    return header.Concat(block).ToArray();
}
string dir = Path.Combine(Path.GetTempPath(), "avo_windows_test_" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(dir);
try
{
    var raw = BuildRaw();
    string avr = Path.Combine(dir, "segment0.avr");
    File.WriteAllBytes(avr, raw);
    var standalone = TrainingImporter.Import(avr);
    Assert(standalone.SessionId == "DEMO_INTEGRATION_001", "Cabecera AVR real / sessionId");
    Assert(standalone.Horse == "Rayo" && standalone.Rider == "Antonio", "Caballo y jinete de cabecera RAW");
    Assert(standalone.Track.Count == 2 && standalone.RtkFixCount == 2, "Tramas UART GNSS y estado RTK FIX");
    Assert(standalone.MaxSpeedKmh > 40 && standalone.DistanceM > 0, "Velocidad GNSS y distancia geodésica");
    Assert(standalone.Segments[0].CleanClose && !standalone.Segments[0].Truncated, "CRC bloque y cierre limpio");
    Assert(standalone.DurationSeconds == 1, "Tiempo iTOW GNSS");

    string avo = Path.Combine(dir, "training.avo");
    using (var zip = ZipFile.Open(avo, ZipArchiveMode.Create))
    {
        string name = "segment0.avr";
        var manifest = new
        {
            format = "AVO-TRAINING-1", sessionId = "DEMO_INTEGRATION_001", horseName = "Rayo", riderName = "Antonio",
            sha256 = new string('f', 64), segments = 1, startRtcMs = 1792656000000L, distanceM = 1234.0,
            segmentHashes = new Dictionary<string, string> { [name] = Convert.ToHexString(SHA256.HashData(raw)).ToLowerInvariant() }
        };
        using (var write = new StreamWriter(zip.CreateEntry("manifest.json").Open(), Encoding.UTF8)) write.Write(JsonSerializer.Serialize(manifest));
        using (var stream = zip.CreateEntry("segments/" + name).Open()) stream.Write(raw);
    }
    var session = TrainingImporter.Import(avo, Path.Combine(dir, "raw"));
    Assert(session.Integrity.Contains("SHA-256") && session.Track.Count == 2, "ZIP AVO-TRAINING-1 y SHA-256 segmento");
    Assert(session.DistanceM != 1234 && session.HasRawTelemetry, "Se prioriza distancia calculada del RAW sobre resumen declarado");
    string csv = Path.Combine(dir, "export.csv"), gpx = Path.Combine(dir, "export.gpx"), html = Path.Combine(dir, "report.html");
    ExportService.ExportCsv(session, csv); ExportService.ExportGpx(session, gpx); ExportService.ExportHtml(session, html);
    Assert(File.ReadAllLines(csv).Length == 3 && File.ReadAllText(csv).Contains("FIX"), "Exportación CSV");
    Assert(File.ReadAllText(gpx).Contains("<trkpt") && File.ReadAllText(gpx).Contains("434" ) == false, "Exportación GPX con coordenadas");
    Assert(File.ReadAllText(html).Contains("AVO PERFORMANCE HORSE"), "Informe HTML imprimible");
    string marine = Path.Combine(dir, "marine.json");
    File.WriteAllText(marine, """{"source":"Estación de referencia / modelo de prueba","kind":"modelo","timestamp":"2026-10-22T10:15:00+02:00","tideHeightM":1.5,"windKmh":12}""");
    MarineMetadata.LoadJson(session, marine);
    Assert(session.TideHeightM == 1.5 && session.MarineKind == "modelo", "Marea y procedencia explícitas");
    File.WriteAllText(marine, """{"source":"sin datos","kind":"inventado","timestamp":"2026-10-22T10:15:00+02:00"}""");
    bool rejected = false;
    try { MarineMetadata.LoadJson(session, marine); } catch (InvalidDataException) { rejected = true; }
    Assert(rejected, "Rechazo de tipo de marea inventado");
    var broken = (byte[])raw.Clone(); broken[508] ^= 0x10;
    File.WriteAllBytes(avr, broken);
    rejected = false;
    try { TrainingImporter.Import(avr); } catch (InvalidDataException) { rejected = true; }
    Assert(rejected, "Rechazo de cabecera con CRC corrupto");
    var torn = raw[..^9]; File.WriteAllBytes(avr, torn);
    var partial = TrainingImporter.Import(avr);
    Assert(partial.Segments[0].Truncated && partial.Integrity.Contains("parcial"), "Bloque incompleto señalado, no interpretado");
    // ---- AVO Equine Intelligence Engine (avo_equine.dll) on the SYNTHETIC reference session.
    // RAW -> importer -> P/Invoke -> C++ engine -> JSON -> C# model used by the window. Not a validation on real horses.
    string fixture = Path.Combine(AppContext.BaseDirectory, "synthetic_session.avo");
    bool requireNative = Environment.GetEnvironmentVariable("AVO_EQ_REQUIRE_NATIVE") == "1";
    if (!EquineEngine.Available || !File.Exists(fixture))
    {
        Assert(!requireNative, "Motor nativo requerido en CI: " + (EquineEngine.UnavailableReason ?? "falta la sesión de referencia"));
        Console.WriteLine("AVISO: motor nativo o sesión de referencia no disponibles; pruebas del motor omitidas");
    }
    else
    {
        Assert(EquineEngine.Version().StartsWith("1.1.0", StringComparison.Ordinal), "Versión del motor " + EquineEngine.Version());
        var synthetic = File.ReadAllBytes(fixture);
        string avo2 = Path.Combine(dir, "sintetica.avo");
        using (var zip = ZipFile.Open(avo2, ZipArchiveMode.Create))
        {
            var manifest = new
            {
                format = "AVO-TRAINING-1", sessionId = "SINTETICA_0001", horseName = "PRUEBA", riderName = "",
                segments = 1, startRtcMs = 1792656000000L,
                segmentHashes = new Dictionary<string, string> { ["P001.avr"] = Convert.ToHexString(SHA256.HashData(synthetic)).ToLowerInvariant() }
            };
            using (var write = new StreamWriter(zip.CreateEntry("manifest.json").Open(), Encoding.UTF8)) write.Write(JsonSerializer.Serialize(manifest));
            using (var stream = zip.CreateEntry("segments/P001.avr").Open()) stream.Write(synthetic);
        }
        var s2 = TrainingImporter.Import(avo2, Path.Combine(dir, "raw"));
        Assert(s2.RawSegmentPaths.Count == 1 && File.Exists(s2.RawSegmentPaths[0]), "Copia RAW verificada para el motor");
        string cache = Path.Combine(dir, "analisis");
        var r1 = EquineAnalysis.Parse(EquineEngine.AnalyseJson(s2.RawSegmentPaths, EquineEngine.Options(true, cache)));
        Assert(r1.SessionId == "SINTETICA_0001" && r1.Cache == "CALCULADO", "Análisis del motor con persistencia");
        Assert(r1.HasImu && r1.Segments.Any(x => x.Aire == "Paso") && r1.Segments.Any(x => x.Aire == "Trote"), "Rendimiento por aire");
        Assert(r1.Curves.Count == 1 && r1.Events.Count > 0 && r1.Quality.Count > 0, "Curvas, eventos y calidad");
        var tp = s2.Track[s2.Track.Count * 3 / 4];
        double t3 = r1.TimeOf(tp.GpsWeekMs) ?? double.NaN;
        Assert(Math.Abs(r1.GnssAt(r1.Speed, t3) - tp.SpeedMs) < 0.05, "Series del motor sincronizadas con el recorrido");
        Assert(Math.Abs(r1.CadenceAt(t3) - 1.45) < 0.05, "Cadencia de la cincha en el instante seleccionado");
        var r2 = EquineAnalysis.Parse(EquineEngine.AnalyseJson(s2.RawSegmentPaths, EquineEngine.Options(true, cache)));
        Assert(r2.Cache == "ACIERTO", "Reapertura sin recalcular");
        var r3 = EquineAnalysis.Parse(EquineEngine.AnalyseJson(s2.RawSegmentPaths, EquineEngine.Options(true, cache, force: true)));
        Assert(r3.Cache == "RECALCULADO", "Reprocesamiento forzado");
        using (var cts = new CancellationTokenSource())
        {
            cts.Cancel();
            bool cancelled = false;
            try { EquineEngine.AnalyseJson(s2.RawSegmentPaths, "{}", cts.Token); } catch (OperationCanceledException) { cancelled = true; }
            Assert(cancelled, "Cancelación del análisis");
        }
        var (rows, verdict) = EquineComparisonRows.Parse(EquineEngine.CompareJson(s2.RawSegmentPaths, s2.RawSegmentPaths, "{\"mismo_recorrido\":true}"));
        Assert(rows.Count > 0 && verdict.StartsWith("Comparables", StringComparison.Ordinal), "Comparación de sesiones: " + verdict);
        bool inputError = false;
        try { EquineEngine.AnalyseJson([Path.Combine(dir, "no_existe.avr")], "{}"); } catch (InvalidDataException) { inputError = true; }
        Assert(inputError, "Error de entrada informado");
        Assert(SHA256.HashData(File.ReadAllBytes(s2.RawSegmentPaths[0])).AsSpan().SequenceEqual(SHA256.HashData(synthetic)), "El RAW no se modifica");
    }
    UsbTests();
    Console.WriteLine($"TODAS LAS PRUEBAS CORRECTAS: {passed}");
}
finally { Directory.Delete(dir, true); }

// ---------------------------------------------------------------- USB download from the watch (CHEST 3.7.5-usb1)
void UsbTests()
{
    // 1. Answers of the REAL firmware (usb_sync.cpp on the host): compare, download the missing ones, verify.
    string transcript = Path.Combine(AppContext.BaseDirectory, "usb_transcript.json");
    Assert(File.Exists(transcript), "Transcripción del firmware USB presente");
    string libDir = Path.Combine(dir, "reloj");
    var link = new TranscriptLink(transcript);
    var r = ChestSync.Run(new ChestUsbClient(link) { ShortTimeout = TimeSpan.FromMilliseconds(200) }, new WatchLibrary(libDir));
    Assert(r.Watch?.Firmware == "3.7.5-usb1" && r.Watch.Device == "a0b1c2d3e4f5", "USB: HELLO del firmware real");
    Assert(r.OnWatch == 3 && r.NotReady == 1 && r.AlreadyOnPc == 0 && r.NewPackages.Count == 2 && r.Failed == 0,
        $"USB: compara y descarga los 2 que faltan (sin el abierto): {r.Summary}");
    using var tdoc = JsonDocument.Parse(File.ReadAllText(transcript));
    var shaLines = tdoc.RootElement.GetProperty("exchanges").EnumerateArray()
        .SelectMany(x => x.GetProperty("out").GetString()!.Split('\n'))
        .Where(l => l.StartsWith("#AVO1 SHA ", StringComparison.Ordinal)).Select(l => JsonDocument.Parse(l[10..])).ToList();
    foreach (var pkg in r.NewPackages)
    {
        using var zip = ZipFile.OpenRead(pkg);
        using var man = JsonDocument.Parse(zip.GetEntry("manifest.json")!.Open());
        string id = man.RootElement.GetProperty("sessionId").GetString()!;
        using var h = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        foreach (var e in zip.Entries.Where(e => e.FullName.StartsWith("segments/", StringComparison.Ordinal)).OrderBy(e => e.FullName, StringComparer.Ordinal))
        {
            using var st = e.Open(); var ms = new MemoryStream(); st.CopyTo(ms); h.AppendData(ms.ToArray());
        }
        string got = Convert.ToHexStringLower(h.GetHashAndReset());
        Assert(shaLines.Any(d => d.RootElement.GetProperty("id").GetString() == id && d.RootElement.GetProperty("sha256").GetString() == got)
               && man.RootElement.GetProperty("sha256").GetString() == got, $"USB: {id} idéntico byte a byte al reloj (SHA-256)");
    }
    var link2 = new TranscriptLink(transcript);
    var r2 = ChestSync.Run(new ChestUsbClient(link2), new WatchLibrary(libDir));
    Assert(r2.AlreadyOnPc == 2 && r2.NewPackages.Count == 0 && !link2.Sent.Any(x => x.StartsWith("AVO1 READ", StringComparison.Ordinal)),
        "USB: segunda conexión, nada que descargar y ninguna lectura");

    // 2. Simulated watch with real RAW: noise, a damaged block and a lost answer are retried; the package opens.
    const string id1 = "S20261028_120000", id2 = "S20261029_083000";
    var sim = new SimWatch { CorruptReadNumber = 1, DropReadNumber = 2 };
    var raw1 = BuildRaw(id1);
    sim.Trainings.Add(new SimWatch.Training { Id = id1, StartRtcMs = 1793188800000, Segments = [raw1, BuildRaw(id1)] });
    sim.Trainings.Add(new SimWatch.Training { Id = id2, StartRtcMs = 1793262600000, Segments = [BuildRaw(id2)] });
    sim.Trainings.Add(new SimWatch.Training { Id = "S20261030_070000", State = 1, StartRtcMs = 1793343600000, Segments = [BuildRaw("S20261030_070000")] });
    string lib2 = Path.Combine(dir, "reloj2");
    var client = new ChestUsbClient(sim) { ShortTimeout = TimeSpan.FromMilliseconds(150) };
    var progressTexts = new List<string>();
    var r3 = ChestSync.Run(client, new WatchLibrary(lib2), null, new SyncProgress(progressTexts));
    Assert(r3.NewPackages.Count == 2 && r3.Failed == 0 && r3.NotReady == 1 && r3.Messages.Count == 0, "USB: bloque con CRC dañado y respuesta perdida se repiten: " + r3.Summary);
    var opened = TrainingImporter.Import(r3.NewPackages.Single(x => x.Contains(id1, StringComparison.Ordinal)), Path.Combine(dir, "raw_usb"));
    Assert(opened.SessionId == id1 && opened.Track.Count >= 2 && opened.Segments.Count == 2 && opened.Integrity.Contains("SHA-256", StringComparison.Ordinal),
        "USB: el paquete descargado se abre como cualquier .avo (2 segmentos, recorrido)");
    Assert(progressTexts.Any(t => t.StartsWith("Descargando 1 de 2", StringComparison.Ordinal)), "USB: progreso de la descarga");

    // 3. Already on the PC through the Android app (.avo with the same SHA-256): not downloaded again.
    var sim2 = new SimWatch();
    sim2.Trainings.AddRange(sim.Trainings);
    var known = new Dictionary<string, string> { [id1] = SimWatch.Sha(sim.Trainings[0]), [id2] = SimWatch.Sha(sim.Trainings[1]) };
    var r4 = ChestSync.Run(new ChestUsbClient(sim2), new WatchLibrary(Path.Combine(dir, "reloj3")), known);
    Assert(r4.AlreadyOnPc == 2 && r4.NewPackages.Count == 0 && sim2.Reads == 0, "USB: reconoce los entrenamientos ya importados desde Android");

    // 4. The phone marked one as uploaded (new etag, same bytes): confirmed by SHA-256, no download.
    sim2.Trainings[0].State = 4;
    var r5 = ChestSync.Run(new ChestUsbClient(sim2), new WatchLibrary(lib2));
    Assert(r5.AlreadyOnPc == 2 && sim2.Reads == 0 && sim2.Sent.Contains("AVO1 SHA " + id1), "USB: cambio de estado sin cambio de datos → sin descarga");

    // 5. Cable pulled halfway: the next connection resumes from the byte already written.
    var big = new SimWatch.Training { Id = "S20261030_101010", StartRtcMs = 1793354000000, Segments = [SimWatch.Big(20000, 7)] };
    var sim3 = new SimWatch { UnplugAfterReads = 2 };
    sim3.Trainings.Add(big);
    string lib3 = Path.Combine(dir, "reloj4");
    var r6 = ChestSync.Run(new ChestUsbClient(sim3) { ShortTimeout = TimeSpan.FromMilliseconds(150) }, new WatchLibrary(lib3));
    Assert(r6.Failed == 1 && r6.NewPackages.Count == 0, "USB: desconexión a mitad informada");
    var sim4 = new SimWatch();
    sim4.Trainings.Add(big);
    var r7 = ChestSync.Run(new ChestUsbClient(sim4), new WatchLibrary(lib3));
    var firstRead = sim4.Sent.First(x => x.StartsWith("AVO1 READ", StringComparison.Ordinal)).Split(' ');
    Assert(r7.NewPackages.Count == 1 && firstRead[4] == "8192" && sim4.Reads == 3, "USB: reanuda desde el byte 8192 (3 lecturas, no 5)");
    Assert(r7.Messages.Count == 1, "USB: RAW no interpretable se conserva verificado y se avisa");

    // 6. Recording on the watch: nothing is listed or read.
    var sim5 = new SimWatch { Recording = true };
    sim5.Trainings.Add(big);
    var r8 = ChestSync.Run(new ChestUsbClient(sim5), new WatchLibrary(Path.Combine(dir, "reloj5")));
    Assert(r8.Recording && sim5.Sent.Count == 1 && r8.Summary.Contains("grabando", StringComparison.Ordinal), "USB: con el reloj grabando no se descarga");

    // 7. The training changes on the watch during the download, and a watch whose SHA-256 does not match.
    var sim6 = new SimWatch();
    var moving = new SimWatch.Training { Id = "S20261030_111111", StartRtcMs = 1793357000000, Segments = [SimWatch.Big(10000, 9)] };
    sim6.Trainings.Add(moving);
    sim6.OnRead = () => { if (sim6.Reads == 2) moving.State = 3; };
    var r9 = ChestSync.Run(new ChestUsbClient(sim6), new WatchLibrary(Path.Combine(dir, "reloj6")));
    Assert(r9.Failed == 1 && r9.Messages[0].Contains("cambió", StringComparison.Ordinal), "USB: entrenamiento modificado durante la descarga");
    var sim7 = new SimWatch { LieSha = true };
    sim7.Trainings.Add(new SimWatch.Training { Id = "S20261030_121212", StartRtcMs = 1793360000000, Segments = [SimWatch.Big(3000, 11)] });
    string lib7 = Path.Combine(dir, "reloj7");
    var r10 = ChestSync.Run(new ChestUsbClient(sim7), new WatchLibrary(lib7));
    Assert(r10.Failed == 1 && r10.NewPackages.Count == 0 && !Directory.EnumerateFiles(lib7, "*.avo").Any(), "USB: SHA-256 distinto → no se guarda nada");

    // 8. Protocol client: rejects a device that is not an AVO watch.
    var bad = new TranscriptLinkStub("#AVO1 HELLO {\"api\":1,\"name\":\"OTRO\",\"fw\":\"1\",\"device\":\"a0b1c2d3e4f5\"}");
    bool rejected = false;
    try { new ChestUsbClient(bad).Hello(); } catch (ChestUsbException) { rejected = true; }
    Assert(rejected, "USB: rechaza un dispositivo que no es un reloj AVO");
}

sealed class SyncProgress(List<string> texts) : IProgress<ChestSyncProgress>
{
    public void Report(ChestSyncProgress value) => texts.Add(value.Text);
}

sealed class TranscriptLinkStub(string answer) : IChestLink
{
    private bool _asked;
    public void WriteLine(string line) => _asked = true;
    public string? ReadLine(TimeSpan timeout) { if (!_asked) return null; _asked = false; return answer; }
    public void Dispose() { }
}
