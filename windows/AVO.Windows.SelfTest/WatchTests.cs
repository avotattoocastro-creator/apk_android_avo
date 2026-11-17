using System.Security.Cryptography;
using System.Text.Json;
using Avo.Windows.Core;
using Avo.Windows.Core.Watch;

namespace Avo.Windows.SelfTest;

/// <summary>
/// Geofences / start-finish lines / watch protocol. Codecs are checked against vectors produced by the REAL chest firmware
/// code (tools/watch-vectors, watch_vectors.json); the end-to-end flow runs against a simulated watch over the same BLE
/// framing. No Bluetooth hardware involved.
/// </summary>
public static class WatchTests
{
    private static Action<bool, string> _a = (_, _) => { };
    private static void A(bool ok, string what) => _a(ok, what);
    private static byte[] Hex(string s) => Convert.FromHexString(s);

    public static void Run(string dir, Action<bool, string> assert)
    {
        _a = assert;
        Vectors();
        Lines();
        Plan(dir);
        EndToEnd().GetAwaiter().GetResult();
    }

    private static void Vectors()
    {
        var v = JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "watch_vectors.json"))).RootElement;
        var blob = Hex(v.GetProperty("config").GetString()!);
        var c = WatchConfig.Decode(blob);
        A(c.HorseName == "HORSE_001" && c.RiderName == "RIDER_007" && c.ActiveMask == 5 && c.FenceCount == 3, "Reloj: configuración del firmware decodificada (identidad y geocercas activas)");
        A(c.Fences[0] is { Type: FenceType.Circle, RadiusCm: 15000, Name: "Regaton" } && c.Fences[2] is { Type: FenceType.Polygon } p && p.Verts.Count == 4 && c.Fences[1] is { Type: FenceType.None },
            "Reloj: círculo, hueco vacío y polígono como los guarda el firmware");
        A(c.Lines[0].Enabled && c.Lines[0].ALatE7 == 434240000 && c.Lines[2].Enabled && !c.Lines[1].Enabled, "Reloj: líneas virtuales del firmware");
        A(c.Encode().AsSpan().SequenceEqual(blob), "Reloj: SET_CONFIG byte a byte igual que config_serialize() del firmware");
        var w = new LeWriter(); c.Fences[2]!.EncodeBody(w);
        A(w.ToArray().AsSpan().SequenceEqual(Hex(v.GetProperty("fence_polygon").GetString()!)), "Reloj: geocerca SET_FENCE igual que fence_serialize()");
        var val = v.GetProperty("validate");
        A(val.GetProperty("ok_polygon").GetInt32() == 0 && c.Fences[2]!.Validate() is null, "Reloj: polígono válido para el firmware y para Windows");
        var bow = new Fence(0, FenceType.Polygon, "Lazo", default, 0, [new(434250000, -34530000), new(434260000, -34510000), new(434260000, -34530000), new(434250000, -34510000)]);
        var tiny = new Fence(0, FenceType.Polygon, "Mini", default, 0, [new(434250000, -34530000), new(434250200, -34530000), new(434250200, -34529800)]);
        var small = new Fence(0, FenceType.Circle, "C", new GeoE7(434247000, -34519000), 400);
        A(val.GetProperty("bowtie").GetInt32() != 0 && bow.Validate()!.Contains("corta"), "Reloj: polígono que se corta rechazado igual que validate_fence()");
        A(val.GetProperty("tiny").GetInt32() != 0 && tiny.Validate()!.Contains("pequeña"), "Reloj: área mínima igual que validate_fence()");
        A(val.GetProperty("small_circle").GetInt32() != 0 && small.Validate()!.Contains("radio"), "Reloj: radio mínimo igual que validate_fence()");
        A(BleFraming.Build((byte)MsgType.SetActiveFences, 0x1234, 0, 1, 0x01, 0, [5, 1]).AsSpan().SequenceEqual(Hex(v.GetProperty("frag_set_active").GetString()!)),
            "Reloj: fragmento BLE igual que ble_frag_build()");
        var key = Enumerable.Range(0, 32).Select(i => (byte)i).ToArray();
        var pn = Enumerable.Range(0, 16).Select(i => (byte)(0xA0 + i)).ToArray();
        var wn = Enumerable.Range(0, 16).Select(i => (byte)(0x50 + i)).ToArray();
        A(Convert.ToHexString(WatchAuth.WatchProof(key, pn, wn, "a0b1c2d3e4f5")).Equals(v.GetProperty("watch_proof").GetString(), StringComparison.OrdinalIgnoreCase) &&
          Convert.ToHexString(WatchAuth.PhoneProof(key, wn, pn, "a0b1c2d3e4f5")).Equals(v.GetProperty("phone_proof").GetString(), StringComparison.OrdinalIgnoreCase),
            "Reloj: pruebas HMAC de autorización iguales que avo_ble_auth");
        var cr = v.GetProperty("crosses").EnumerateArray().Select(x => x.GetInt32() == 1).ToArray();
        bool c1 = LineAnalysis.Crosses(0, 0, 10, 0, 5, 3, 5, -3, out bool l1), c2 = LineAnalysis.Crosses(0, 0, 10, 0, 5, -3, 5, 3, out bool l2);
        A(c1 == cr[0] && c2 == cr[1] && LineAnalysis.Crosses(0, 0, 10, 0, 1, 1, 9, 1, out _) == cr[2] && LineAnalysis.Crosses(0, 0, 10, 0, 15, 3, 15, -3, out _) == cr[3],
            "Líneas: mismo test de cruce que el reloj (avo_session.cpp)");
        A(l1 && !l2, "Líneas: sentido del cruce (izquierda→derecha mirando de A a B)");
        A(Crc16.Compute("123456789"u8) == 0x29B1, "Reloj: CRC-16/CCITT-FALSE");
    }

    // ---------------------------------------------------------------- crossings of a recorded track
    private static SessionTimeline Track(params (double Lat, double Lon)[] pts)
    {
        var s = new TrainingSession { SessionId = "SINTETICA_LINEAS" };
        const double v = 4.0;
        for (int i = 0; i < pts.Length; i++)
        {
            long itow = 345_600_000 + i * 1000L;
            s.Track.Add(new TrackPoint(pts[i].Lat, pts[i].Lon, v, 0.014, 2, itow, 52, null, 3, 26, true, 0.05, 0, v, 90, 2.0,
                new DateTimeOffset(2026, 10, 22, 6, 15, 0, TimeSpan.Zero).AddSeconds(i), (ulong)((i + 500) * 1e6)));
            s.GnssEpochs.Add(new GnssEpoch(itow, GnssSolution.RtkFix, 26, 0.014, 0));
            s.GnssSamples++;
        }
        return SessionTimeline.Build(s, new SpeedSmoother.Parameters());
    }

    private static void Lines()
    {
        // line along the beach (west → east), crossings going north (right→left) and south (left→right)
        var line = new PlanLine { Enabled = true, Name = "Meta", Role = LineRole.StartFinish, A = new(43.42400, -3.45300), B = new(43.42400, -3.45200), Direction = LineDirection.LeftToRight };
        double latN = 43.42403, latS = 43.42397, lon = -3.45290, d = 0.00002;
        var tl = Track((latN, lon), (latS, lon + d), (latS, lon + 2 * d), (latN, lon + 3 * d), (latN, lon + 4 * d), (latS, lon + 5 * d), (latS, lon + 6 * d),
                       (latN, lon + 7 * d), (latN, lon + 8 * d), (latS, lon + 9 * d));
        if (tl.Count < 10) { A(false, $"Líneas: recorrido sintético ({tl.Count} épocas)"); return; }
        var all = LineAnalysis.Detect(tl, line, 0);
        A(all.Count == 5 && all.Count(c => c.LeftToRight) == 3, "Líneas: 5 cruces, 3 hacia el sur (izquierda→derecha)");
        A(all.Where(c => c.Counts).All(c => c.LeftToRight) && all.Count(c => c.Counts) == 3, "Líneas: solo marcan los cruces en el sentido elegido");
        A(all.Count > 0 && Math.Abs(all[0].T - (tl.T[0] + 0.5)) < 0.02, "Líneas: hora del cruce interpolada entre épocas");
        var runs = LineAnalysis.Runs([line], all);
        A(runs.Count == 2 && runs.All(r => r.DurationS > 0), "Líneas: vueltas entre cruces válidos de salida/meta");
        line.Direction = LineDirection.Both;
        A(LineAnalysis.Detect(tl, line, 0).All(c => c.Counts), "Líneas: «ambos sentidos» marca todos (lo que hace el reloj)");
        var start = new PlanLine { Enabled = true, Name = "Salida", Role = LineRole.Start, A = line.A, B = line.B, Direction = LineDirection.LeftToRight };
        var fin = new PlanLine { Enabled = true, Name = "Meta", Role = LineRole.Finish, A = new(43.42390, -3.45281), B = new(43.42410, -3.45281), Direction = LineDirection.Both };
        var cs = LineAnalysis.Detect(tl, start, 0).Concat(LineAnalysis.Detect(tl, fin, 1)).ToList();
        A(LineAnalysis.Runs([start, fin], cs).Any(r => r.Kind.StartsWith("Salida → meta")), "Líneas: tramo de salida a meta");
    }

    // ---------------------------------------------------------------- plan file
    private static void Plan(string dir)
    {
        string path = Path.Combine(dir, "geocercas", "geocercas.json");
        if (File.Exists(path)) File.Delete(path);
        var p = GeofencePlan.Load(path);
        A(p.Fences.Count == 8 && p.Lines.Count == 4 && p.Lines[0].Role == LineRole.StartFinish, "Geocercas: plan vacío con 8 huecos y 4 líneas del reloj");
        p.Fences[0] = new PlanFence { Name = "Regatón", Type = FenceType.Circle, Center = new(43.4247, -3.4519), RadiusM = 150 };
        p.Fences[3] = new PlanFence { Name = "Pista", Type = FenceType.Polygon, Active = false, Vertices = [new(43.4250, -3.4530), new(43.4260, -3.4530), new(43.4260, -3.4510)] };
        p.Lines[0] = new PlanLine { Enabled = true, Name = "Salida / meta", Role = LineRole.StartFinish, A = new(43.4240, -3.4525), B = new(43.42405, -3.4520), Direction = LineDirection.RightToLeft };
        A(p.Problems().Count == 0 && p.ActiveMask == 0x01, "Geocercas: plan válido y máscara de activas");
        p.Save(path);
        var q = GeofencePlan.Load(path);
        A(q.Fences[3]!.Vertices.Count == 3 && q.Lines[0].Direction == LineDirection.RightToLeft && q.Fences[0]!.Name == "Regatón", "Geocercas: se guarda y se vuelve a leer");
        q.Fences[1] = new PlanFence { Name = "Nombre demasiado largo", Center = new(43.4, -3.4) };
        q.Lines[2] = new PlanLine { Enabled = true, Name = "Meta", A = new(43.4, -3.4) };
        A(q.Problems().Count == 2, "Geocercas: nombre > 15 B y línea sin extremo B detectados antes de enviar");
        File.WriteAllText(path, "{ roto");
        A(GeofencePlan.Load(path).Fences.All(f => f is null) && Directory.GetFiles(Path.GetDirectoryName(path)!, "geocercas.json.danado-*").Length >= 1, "Geocercas: archivo dañado se conserva aparte");
    }

    // ---------------------------------------------------------------- simulated watch + full flow
    private sealed class MemStore : IWatchCredentialStore
    {
        public readonly Dictionary<string, WatchCredential> D = [];
        public WatchCredential? Get(string id) => D.GetValueOrDefault(id);
        public void Save(WatchCredential c) => D[c.DeviceId] = c;
    }

    /// <summary>Watch double: same message handling rules as ble_service.cpp for the messages used here.</summary>
    private sealed class SimWatch : IAvoTransport
    {
        public AvoClient? Client;
        public WatchConfig Config;
        public byte[] Blob;
        public readonly List<(byte[] Kid, byte[] Key)> Keys = [];
        public bool Authorized, ClaimOpen, BootPressed;
        public int Polls, SetFences, SetConfigs, SetActives;
        public const string Dev = "a0b1c2d3e4f5";
        private byte[]? _wn, _pn, _kidKey;
        private readonly BleReassembler _rx = new();
        public int AttPayload => 244;
        public SimWatch(byte[] blob) { Blob = blob; Config = WatchConfig.Decode(blob); }

        public Task WriteCtrlAsync(byte[] fragment, CancellationToken ct)
        {
            var m = _rx.Feed(fragment);
            if (m is not null) Handle(m);
            return Task.CompletedTask;
        }

        private void Reply(BleMessage m, BleStatus st, byte[]? payload = null)
        {
            payload ??= [];
            int cnt = BleFraming.Count(payload.Length, AttPayload), per = AttPayload - BleFraming.Overhead;
            for (int i = 0; i < cnt; i++)
            {
                int off = i * per;
                Client!.OnNotification(AvoGatt.CtrlTx, BleFraming.Build(m.Type, m.MsgId, i, cnt, BleFraming.FlagResponse, (byte)st,
                    payload.AsSpan(off, Math.Min(per, payload.Length - off))));
            }
        }

        private void Store(WatchConfig c) { Blob = c.Encode(); Config = WatchConfig.Decode(Blob); }

        private void Handle(BleMessage m)
        {
            var t = (MsgType)m.Type;
            bool open = t is MsgType.GetInfo or MsgType.AuthHello or MsgType.AuthProof or MsgType.ClaimBegin or MsgType.ClaimResult;
            if (!Authorized && !open) { Reply(m, BleStatus.AuthRequired); return; }
            var r = new LeReader(m.Payload);
            switch (t)
            {
                case MsgType.GetInfo:
                    Reply(m, BleStatus.Ok, new LeWriter().U8(1).U8(1).U16(1).U16(1).Str("3.7.6", 16).Str(Dev, 16).U32(42).U16(247).U32(0xFFF)
                        .U8(Authorized ? 1 : 0).U8(Keys.Count).U8(ClaimOpen ? 1 : 0).U8(1).Str("sim", 32).ToArray());
                    break;
                case MsgType.AuthHello:
                    {
                        var kid = r.Bytes(8); _pn = r.Bytes(16);
                        var k = Keys.FirstOrDefault(x => x.Kid.AsSpan().SequenceEqual(kid));
                        if (k.Key is null) { Reply(m, BleStatus.NotFound); break; }
                        _kidKey = k.Key; _wn = RandomNumberGenerator.GetBytes(16);
                        Reply(m, BleStatus.Ok, [.. _wn, .. WatchAuth.WatchProof(k.Key, _pn, _wn, Dev)]);
                        break;
                    }
                case MsgType.AuthProof:
                    {
                        var pp = r.Bytes(32);
                        Authorized = _kidKey is not null && pp.AsSpan().SequenceEqual(WatchAuth.PhoneProof(_kidKey, _wn!, _pn!, Dev));
                        Reply(m, Authorized ? BleStatus.Ok : BleStatus.AuthRequired);
                        break;
                    }
                case MsgType.ClaimBegin: ClaimOpen = true; Reply(m, BleStatus.Ok, [60, 0]); break;
                case MsgType.ClaimResult:
                    if (!ClaimOpen) { Reply(m, BleStatus.NotFound); break; }
                    if (++Polls >= 2) BootPressed = true;                // the user presses BOOT on the second poll
                    if (!BootPressed) { Reply(m, BleStatus.Busy); break; }
                    var nk = (RandomNumberGenerator.GetBytes(8), RandomNumberGenerator.GetBytes(32));
                    Keys.Add(nk); ClaimOpen = false;
                    Reply(m, BleStatus.Ok, [.. nk.Item1, .. nk.Item2]);
                    break;
                case MsgType.GetConfig: Reply(m, BleStatus.Ok, Blob); break;
                case MsgType.SetConfig:
                    try { Store(WatchConfig.Decode(m.Payload)); SetConfigs++; Reply(m, BleStatus.Ok, [0, 0]); }
                    catch (FormatException) { Reply(m, BleStatus.BadFormat, [1]); }
                    break;
                case MsgType.SetFence:
                    {
                        int slot = r.U8();
                        var f = Fence.DecodeBody(r);
                        if (f is null || slot >= 8) { Reply(m, BleStatus.BadFormat); break; }
                        if (f.Type != FenceType.None && f.Validate() is not null) { Reply(m, BleStatus.BadFormat, [1]); break; }
                        var fs = Config.Fences.ToArray(); fs[slot] = f with { Id = slot };
                        Store(Config with { Fences = fs, FenceCount = Math.Max(Config.FenceCount, slot + 1) });
                        SetFences++;
                        Reply(m, BleStatus.Ok);
                        break;
                    }
                case MsgType.SetActiveFences:
                    Store(Config with { ActiveMask = r.U8(), AutoEnabled = r.U8() != 0 }); SetActives++; Reply(m, BleStatus.Ok); break;
                default: Reply(m, BleStatus.UnknownType); break;
            }
        }
    }

    private static async Task EndToEnd()
    {
        var v = JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "watch_vectors.json"))).RootElement;
        // the watch's configuration plus a section this app does not know (tag 42): it must survive
        var baseCfg = WatchConfig.Decode(Hex(v.GetProperty("config").GetString()!));
        var watch = new SimWatch((baseCfg with { UnknownSections = [(42, new byte[] { 1, 2, 3 })] }).Encode());
        var client = new AvoClient(watch, 100);
        watch.Client = client;
        var store = new MemStore();
        var msgs = new List<string>();
        var info = await WatchAuthorizer.EnsureAsync(client, store, "AVO Windows PC", new Progress<string>(msgs.Add), CancellationToken.None, 5000, 10);
        A(watch.Authorized && store.D.ContainsKey(SimWatch.Dev) && watch.Polls >= 2 && info.DeviceId == SimWatch.Dev, "Reloj: PC autorizado con BOOT (misma reclamación que Android)");
        // second connection: the saved key is enough
        watch.Authorized = false; int polls = watch.Polls;
        await WatchAuthorizer.EnsureAsync(new AvoClient(watch, 300) is var c2 ? Bind(watch, c2) : client, store, "AVO Windows PC", null, CancellationToken.None, 5000, 10);
        A(watch.Authorized && watch.Polls == polls, "Reloj: reconexión con la clave guardada, sin volver a pulsar BOOT");
        client = watch.Client!;

        var plan = new GeofencePlan();
        plan.LoadFrom(watch.Config);
        A(plan.Fences[0] is { Name: "Regaton", RadiusM: 150 } && plan.Fences[2]?.Vertices.Count == 4 && plan.Lines[0].Enabled, "Geocercas: «Leer del reloj» trae lo que tiene");
        plan.Fences[0] = null;                                                                               // delete slot 1
        plan.Fences[4] = new PlanFence { Name = "Playa sur", Type = FenceType.Circle, Center = new(43.4230, -3.4500), RadiusM = 80 };
        plan.Lines[1] = new PlanLine { Enabled = true, Name = "Salida", Role = LineRole.Start, A = new(43.4245, -3.4525), B = new(43.4245, -3.4520), Direction = LineDirection.LeftToRight };
        var rep = await GeofenceSync.SendAsync(client, plan, null, CancellationToken.None);
        A(rep.Verified && GeofenceSync.Differences(plan, watch.Config).Count == 0, "Envío: el reloj guarda exactamente geocercas, activas y líneas del plan");
        A(watch.Config.Fences[0] is { Type: FenceType.None } && watch.Config.Fences[4] is { Name: "Playa sur" } && watch.Config.Lines[1].Enabled, "Envío: hueco borrado, geocerca nueva y línea de salida");
        A(watch.Config.UnknownSections.Any(s => s.Tag == 42) && watch.Config.HorseName == "HORSE_001", "Envío: lo que no se toca (identidad, secciones desconocidas) se conserva");
        A(watch.SetFences == 2 && watch.SetConfigs == 1, "Envío: solo se envían los cambios (2 geocercas + 1 configuración)");
        int before = watch.SetFences + watch.SetConfigs + watch.SetActives;
        var again = await GeofenceSync.SendAsync(client, plan, null, CancellationToken.None);
        A(again.Verified && watch.SetFences + watch.SetConfigs + watch.SetActives == before && again.Steps[0].Contains("ya tenía"), "Envío: repetir no reescribe nada");
        plan.Fences[5] = new PlanFence { Name = "Mal", Type = FenceType.Polygon, Vertices = [new(43.4250, -3.4530), new(43.4260, -3.4510), new(43.4260, -3.4530), new(43.4250, -3.4510)] };
        bool refused = false;
        try { await GeofenceSync.SendAsync(client, plan, null, CancellationToken.None); } catch (InvalidOperationException) { refused = true; }
        A(refused && watch.SetFences + watch.SetConfigs + watch.SetActives == before, "Envío: un plan inválido no se envía (nada a medias)");
        // without authorization the watch refuses configuration (AUTH_REQUIRED), as the firmware does
        watch.Authorized = false;
        plan.Fences[5] = null;
        bool authRefused = false;
        try { await GeofenceSync.SendAsync(client, plan, null, CancellationToken.None); } catch (BleRequestException e) when (e.Status == BleStatus.AuthRequired) { authRefused = true; }
        A(authRefused, "Envío: sin autorización el reloj no acepta cambios");
    }

    private static AvoClient Bind(SimWatch w, AvoClient c) { w.Client = c; return c; }
}
