using System.Globalization;
using System.Security.Cryptography;
using System.Text.Json;
using Avo.Windows.Core;

namespace Avo.Windows.SelfTest;

/// <summary>Replays the answers of the REAL firmware (usb_sync.cpp built on the host, see tests_test_usb_v375.py).</summary>
internal sealed class TranscriptLink : IChestLink
{
    private readonly Dictionary<string, string> _answers = new(StringComparer.Ordinal);
    private readonly Queue<string> _out = new();
    public List<string> Sent { get; } = [];

    public TranscriptLink(string path)
    {
        using var doc = JsonDocument.Parse(File.ReadAllText(path));
        foreach (var e in doc.RootElement.GetProperty("exchanges").EnumerateArray())
            _answers[e.GetProperty("cmd").GetString()!] = e.GetProperty("out").GetString()!;
        _out.Enqueue("ESP-ROM:esp32s3-20210327");          // boot noise before anything is asked
        _out.Enqueue("[AVO] AVO-CHEST 3.7.5-usb1 ready");
    }

    public void WriteLine(string line)
    {
        Sent.Add(line);
        if (!_answers.TryGetValue(line, out var answer)) throw new InvalidOperationException("Orden fuera de la transcripción: " + line);
        foreach (var l in answer.Split('\n', StringSplitOptions.RemoveEmptyEntries)) _out.Enqueue(l);
    }

    public string? ReadLine(TimeSpan timeout) => _out.Count > 0 ? _out.Dequeue() : null;
    public void Dispose() { }
}

/// <summary>Watch simulated in C# (same protocol) to inject faults: noise, damaged blocks, lost answers, unplugging…</summary>
internal sealed class SimWatch : IChestLink
{
    public sealed class Training
    {
        public required string Id { get; init; }
        public int State { get; set; } = 2;
        public long StartRtcMs { get; init; }
        public required List<byte[]> Segments { get; init; }
    }

    private readonly Queue<string> _out = new();
    public List<Training> Trainings { get; } = [];
    public List<string> Sent { get; } = [];
    public bool Recording { get; set; }
    public int CorruptReadNumber { get; set; } = -1;   // that READ answer goes out with a bad CRC
    public int DropReadNumber { get; set; } = -1;      // that READ answer never arrives
    public int UnplugAfterReads { get; set; } = -1;    // the cable is pulled after this many READ answers
    public bool LieSha { get; set; }
    public Action? OnRead { get; set; }
    public int Reads { get; private set; }

    public static string Etag(Training t)
    {
        uint h = 2166136261u;
        for (int s = 0; s < t.Segments.Count; s++)
        {
            h = unchecked((h ^ (uint)t.Segments[s].Length) * 16777619u);
            h = unchecked((h ^ (uint)(s + 1)) * 16777619u);
        }
        h = unchecked((h ^ (uint)t.StartRtcMs) * 16777619u);
        h = unchecked((h ^ (uint)t.State) * 16777619u);
        return h.ToString("x8", CultureInfo.InvariantCulture);
    }

    public static string Sha(Training t)
    {
        using var h = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        foreach (var s in t.Segments) h.AppendData(s);
        return Convert.ToHexStringLower(h.GetHashAndReset());
    }

    private void Say(string payload)
    {
        _out.Enqueue("[AVO NOW] telemetry line from another task");
        _out.Enqueue("#AVO1 " + payload);
    }

    public void WriteLine(string line)
    {
        if (UnplugAfterReads >= 0 && Reads >= UnplugAfterReads) throw new ChestUsbException("USB", "timeout", "Reloj desconectado");
        Sent.Add(line);
        var p = line.Split(' ');
        if (p[0] != "AVO1") return;
        switch (p[1])
        {
            case "HELLO":
                Say("HELLO {\"api\":1,\"name\":\"AVO-CHEST\",\"fw\":\"3.7.5-usb1\",\"device\":\"a0b1c2d3e4f5\",\"recording\":" +
                    (Recording ? "true" : "false") + ",\"sd\":true,\"battery_pct\":64,\"vbus\":true,\"raw_format\":1,\"max_read\":4096}");
                return;
            case "LIST":
                if (Recording) { Say("ERR LIST recording"); return; }
                foreach (var t in Trainings)
                    Say("T " + JsonSerializer.Serialize(new Dictionary<string, object>
                    {
                        ["id"] = t.Id, ["state"] = t.State, ["ready"] = t.State != 1, ["segments"] = t.Segments.Count,
                        ["size"] = t.Segments.Sum(s => (long)s.Length), ["start_rtc_ms"] = t.StartRtcMs, ["active_ms"] = 60000,
                        ["etag"] = Etag(t), ["sizes"] = t.Segments.Select(s => s.Length).ToArray(),
                    }));
                Say("END " + Trainings.Count.ToString(CultureInfo.InvariantCulture));
                return;
            case "SHA":
            {
                var t = Trainings.FirstOrDefault(x => x.Id == p[2]);
                if (Recording) Say("ERR SHA recording");
                else if (t is null) Say("ERR SHA id");
                else if (t.State == 1) Say("ERR SHA open");
                else Say($"SHA {{\"id\":\"{t.Id}\",\"sha256\":\"{(LieSha ? new string('0', 64) : Sha(t))}\",\"size\":{t.Segments.Sum(s => (long)s.Length)},\"etag\":\"{Etag(t)}\"}}");
                return;
            }
            case "READ":
            {
                Reads++;
                OnRead?.Invoke();
                var t = Trainings.FirstOrDefault(x => x.Id == p[2]);
                int seg = int.Parse(p[3], CultureInfo.InvariantCulture);
                long off = long.Parse(p[4], CultureInfo.InvariantCulture);
                int len = Math.Min(int.Parse(p[5], CultureInfo.InvariantCulture), 4096);
                if (Recording) { Say("ERR READ recording"); return; }
                if (t is null) { Say("ERR READ id"); return; }
                if (p[6] != Etag(t)) { Say("ERR READ changed"); return; }
                var data = t.Segments[seg - 1];
                if (off >= data.Length) { Say("ERR READ range"); return; }
                len = (int)Math.Min(len, data.Length - off);
                var chunk = data.AsSpan((int)off, len).ToArray();
                uint crc = ChestUsbClient.Crc32(chunk);
                if (Reads == CorruptReadNumber) crc ^= 1;
                if (Reads == DropReadNumber) return;
                Say($"DATA {seg} {off} {len} {crc:x8} {Convert.ToBase64String(chunk)}");
                return;
            }
            default:
                Say($"ERR {p[1]} cmd");
                return;
        }
    }

    public string? ReadLine(TimeSpan timeout) => _out.Count > 0 ? _out.Dequeue() : null;
    public void Dispose() { }

    public static byte[] Big(int n, int seed)
    {
        var b = new byte[n];
        new Random(seed).NextBytes(b);
        return b;
    }
}
