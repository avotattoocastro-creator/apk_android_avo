using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;

namespace Avo.Windows.Core.Watch;

/// <summary>
/// AVO BLE PROTOCOL v1 — C# port of the Android app (core/ble/BleProtocol.kt, AvoClient.kt, Messages.kt, auth/WatchAuth.kt),
/// which in turn copies the chest firmware (src/ble_service.cpp, lib/avo_core/src/avo_ble_proto.*, avo_ble_auth.*).
/// Nothing here is new: UUIDs, message types, layouts and checks are the ones the watch already implements, so the watch
/// needs no change to be configured from Windows.
/// </summary>
public static class AvoGatt
{
    public static readonly Guid Service = Guid.Parse("7a5e0001-4156-4f50-8e1f-3c0de5a1c0a3");
    public static readonly Guid Info = Guid.Parse("7a5e0002-4156-4f50-8e1f-3c0de5a1c0a3");
    public static readonly Guid CtrlRx = Guid.Parse("7a5e0003-4156-4f50-8e1f-3c0de5a1c0a3");   // write with response (encrypted)
    public static readonly Guid CtrlTx = Guid.Parse("7a5e0004-4156-4f50-8e1f-3c0de5a1c0a3");   // notify: responses, events
    public static readonly Guid Telem = Guid.Parse("7a5e0005-4156-4f50-8e1f-3c0de5a1c0a3");    // notify: telemetry
    public static readonly Guid Rtcm = Guid.Parse("7a5e0006-4156-4f50-8e1f-3c0de5a1c0a3");
    public static readonly Guid FileTx = Guid.Parse("7a5e0007-4156-4f50-8e1f-3c0de5a1c0a3");  // notify: FILE_DATA
    /// <summary>V3.4.2+: "AVO_XXXX"; V3.3: "AVO-XXXX".</summary>
    public static readonly System.Text.RegularExpressions.Regex NameRegex = new("^AVO[_-][0-9A-F]{4}$");
    public const int PreferredMtu = 247;
}

public enum MsgType : byte
{
    GetInfo = 0x01, GetStatus = 0x02,
    AuthHello = 0x08, AuthProof = 0x09, ClaimBegin = 0x0A, ClaimResult = 0x0B, AuthRevoke = 0x0C,
    SessionCmd = 0x10,
    GetConfig = 0x20, SetConfig = 0x21, SetFence = 0x22, GetFence = 0x23, SetActiveFences = 0x24,
    Rtcm = 0x30, RtcmAck = 0x31,
    Nack = 0x7E, Ack = 0x7F, Telemetry = 0x80, Event = 0x81,
}

public enum BleStatus : byte
{
    Ok = 0, BadCrc = 1, BadFormat = 2, UnknownType = 3, Busy = 4, NotAllowed = 5, NotFound = 6, TooLarge = 7, AuthRequired = 8,
    IoError = 9, StateConflict = 10, Duplicate = 11, Timeout = 12, VerifyFailed = 13, Unknown = 255,
}

public static class BleStatusText
{
    public static string Es(BleStatus s) => s switch
    {
        BleStatus.Ok => "correcto", BleStatus.BadCrc => "CRC erróneo", BleStatus.BadFormat => "formato erróneo",
        BleStatus.UnknownType => "comando no soportado por el firmware", BleStatus.Busy => "ocupado", BleStatus.NotAllowed => "no permitido",
        BleStatus.NotFound => "no encontrado", BleStatus.TooLarge => "demasiado grande", BleStatus.AuthRequired => "autorización necesaria",
        BleStatus.IoError => "error de E/S", BleStatus.StateConflict => "estado incompatible", BleStatus.Duplicate => "duplicado (ya ejecutado)",
        BleStatus.Timeout => "tiempo agotado", BleStatus.VerifyFailed => "verificación fallida", _ => "desconocido",
    };
    public static BleStatus Of(int code) => Enum.IsDefined(typeof(BleStatus), (byte)code) ? (BleStatus)code : BleStatus.Unknown;
}

/// <summary>CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF), as avo_crc.cpp.</summary>
public static class Crc16
{
    public static ushort Compute(ReadOnlySpan<byte> d)
    {
        int crc = 0xFFFF;
        foreach (byte b in d)
        {
            crc ^= b << 8;
            for (int k = 0; k < 8; k++) crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) & 0xFFFF : (crc << 1) & 0xFFFF;
        }
        return (ushort)crc;
    }
}

/// <summary>Little-endian writer with the firmware's fixed-width string rule (width-1 bytes max, NUL padded, UTF-8 safe).</summary>
public sealed class LeWriter
{
    private readonly List<byte> _b = [];
    public int Size => _b.Count;
    public LeWriter U8(int v) { _b.Add((byte)v); return this; }
    public LeWriter U16(int v) { _b.Add((byte)v); _b.Add((byte)(v >> 8)); return this; }
    public LeWriter U32(long v) { for (int i = 0; i < 4; i++) _b.Add((byte)(v >> (8 * i))); return this; }
    public LeWriter I32(int v) => U32((uint)v);
    public LeWriter U64(long v) { for (int i = 0; i < 8; i++) _b.Add((byte)(v >> (8 * i))); return this; }
    public LeWriter Bytes(ReadOnlySpan<byte> d) { foreach (var x in d) _b.Add(x); return this; }
    public LeWriter Str(string? s, int width)
    {
        var b = Encoding.UTF8.GetBytes(s ?? "");
        int l = Math.Min(b.Length, width - 1);
        while (l > 0 && l < b.Length && (b[l] & 0xC0) == 0x80) l--;      // never cut a UTF-8 sequence
        for (int i = 0; i < width; i++) _b.Add(i < l ? b[i] : (byte)0);
        return this;
    }
    public byte[] ToArray() => _b.ToArray();
}

public sealed class LeReader
{
    private readonly byte[] _b;
    private readonly int _end;
    public int Pos { get; private set; }
    public bool Ok { get; private set; } = true;
    public LeReader(byte[] b, int start = 0, int? end = null) { _b = b; Pos = start; _end = end ?? b.Length; }
    public int Remaining => Ok ? _end - Pos : 0;
    private bool Room(int n) { if (!Ok || Pos + n > _end) { Ok = false; return false; } return true; }
    public int U8() => Room(1) ? _b[Pos++] : 0;
    public int I8() => Room(1) ? (sbyte)_b[Pos++] : 0;
    public int U16() { if (!Room(2)) return 0; int v = _b[Pos] | _b[Pos + 1] << 8; Pos += 2; return v; }
    public long U32() { if (!Room(4)) return 0; long v = (uint)(_b[Pos] | _b[Pos + 1] << 8 | _b[Pos + 2] << 16 | _b[Pos + 3] << 24); Pos += 4; return v; }
    public int I32() => (int)(uint)U32();
    public long U64() { if (!Room(8)) return 0; long v = 0; for (int i = 0; i < 8; i++) v |= (long)_b[Pos + i] << (8 * i); Pos += 8; return v; }
    public byte[] Bytes(int n) { if (!Room(n)) return []; var r = _b.AsSpan(Pos, n).ToArray(); Pos += n; return r; }
    public string Str(int width)
    {
        if (!Room(width)) return "";
        int l = 0;
        while (l < width && _b[Pos + l] != 0) l++;
        var s = Encoding.UTF8.GetString(_b, Pos, l);
        Pos += width;
        return s;
    }
}

public sealed record BleMessage(byte Type, ushort MsgId, byte Flags, byte Status, byte[] Payload)
{
    public bool IsResponse => (Flags & BleFraming.FlagResponse) != 0;
    public BleStatus StatusEnum => BleStatusText.Of(Status);
}

/// <summary>One application fragment per ATT write/notification: 10-byte header + payload + CRC-16 (avo_ble_proto).</summary>
public static class BleFraming
{
    public const int Version = 1, Header = 10, Overhead = Header + 2, MaxMessage = 4096;
    public const byte FlagAckReq = 0x01, FlagResponse = 0x02, FlagError = 0x04;

    public static byte[] Build(byte type, ushort msgId, int idx, int cnt, byte flags, byte status, ReadOnlySpan<byte> payload)
    {
        if (cnt <= 0 || idx >= cnt) throw new ArgumentOutOfRangeException(nameof(idx));
        var w = new LeWriter().U8(Version).U8(type).U16(msgId).U16(idx).U16(cnt).U8(flags).U8(status).Bytes(payload);
        var body = w.ToArray();
        return [.. body, .. new LeWriter().U16(Crc16.Compute(body)).ToArray()];
    }

    public static (byte Type, ushort MsgId, int Idx, int Cnt, byte Flags, byte Status, byte[] Payload)? Parse(byte[] p)
    {
        if (p.Length < Overhead) return null;
        int want = p[^2] | p[^1] << 8;
        if (Crc16.Compute(p.AsSpan(0, p.Length - 2)) != want) return null;
        int ver = p[0], idx = p[4] | p[5] << 8, cnt = p[6] | p[7] << 8;
        if (ver == 0 || cnt == 0 || idx >= cnt) return null;
        return (p[1], (ushort)(p[2] | p[3] << 8), idx, cnt, p[8], p[9], p.AsSpan(Header, p.Length - Overhead).ToArray());
    }

    /// <summary>Fragment count for an ATT payload size (MTU − 3), as ble_frag_count().</summary>
    public static int Count(int len, int attPayload)
    {
        int per = attPayload - Overhead;
        if (per <= 0) throw new ArgumentOutOfRangeException(nameof(attPayload));
        int c = (len + per - 1) / per;
        return c == 0 ? 1 : c;
    }

    public static List<byte[]> Fragment(byte type, ushort msgId, byte[] payload, int attPayload, byte flags = FlagAckReq)
    {
        if (payload.Length > MaxMessage) throw new ArgumentException($"mensaje BLE de {payload.Length} B supera {MaxMessage} B");
        int cnt = Count(payload.Length, attPayload), per = attPayload - Overhead;
        var r = new List<byte[]>(cnt);
        for (int i = 0; i < cnt; i++)
        {
            int off = i * per;
            r.Add(Build(type, msgId, i, cnt, flags, 0, payload.AsSpan(off, Math.Min(per, payload.Length - off))));
        }
        return r;
    }
}

/// <summary>Reassembles notifications (fragments of one message arrive contiguously and in order).</summary>
public sealed class BleReassembler(int maxMessage = 64 * 1024)
{
    private sealed class Slot { public byte Type; public ushort Id; public int Cnt, Next; public byte Flags, Status; public MemoryStream Buf = new(); }
    private readonly Dictionary<int, Slot> _slots = [];
    public int CrcErrors { get; private set; }
    public int Gaps { get; private set; }

    public BleMessage? Feed(byte[] raw)
    {
        var f = BleFraming.Parse(raw);
        if (f is null) { CrcErrors++; return null; }
        var (type, id, idx, cnt, flags, status, payload) = f.Value;
        int key = type << 16 | id;
        if (cnt == 1) { _slots.Remove(key); return new BleMessage(type, id, flags, status, payload); }
        _slots.TryGetValue(key, out var s);
        if (idx == 0) { s = new Slot { Type = type, Id = id, Cnt = cnt, Flags = flags, Status = status }; _slots[key] = s; }
        if (s is null || idx != s.Next || cnt != s.Cnt) { Gaps++; _slots.Remove(key); return null; }
        s.Buf.Write(payload);
        if (s.Buf.Length > maxMessage) { _slots.Remove(key); Gaps++; return null; }
        if (++s.Next < s.Cnt) return null;
        _slots.Remove(key);
        return new BleMessage(s.Type, s.Id, s.Flags, s.Status, s.Buf.ToArray());
    }
    public void Reset() => _slots.Clear();
}

/// <summary>GATT access implemented by the Windows Bluetooth layer or by a test double.</summary>
public interface IAvoTransport
{
    /// <summary>Write with response on CTRL_RX (one fragment). Throws on failure.</summary>
    Task WriteCtrlAsync(byte[] fragment, CancellationToken ct);
    /// <summary>ATT payload size (negotiated MTU − 3).</summary>
    int AttPayload { get; }
}

public sealed class BleRequestException(BleStatus status, string message) : Exception(message)
{
    public BleStatus Status { get; } = status;
}

public enum AuthOutcome { Ok, UnknownKey, Rejected, Locked, WatchNotAuthentic, Error }

/// <summary>Credential for one watch (key id 8 B + key 32 B), as the claim returns it.</summary>
public sealed record WatchCredential(string DeviceId, byte[] KeyId, byte[] Key);

public sealed record WatchInfo(int BleProto, int UartProto, int RawFormat, int ConfigSchema, string Firmware, string DeviceId, long BootCount,
    int Mtu, long Caps, bool? Authorized, int? AuthKeys, bool? ClaimPending, bool? AuthRequired, string? BuildFingerprint)
{
    public bool SupportsAuth => (Caps & 0x80) != 0;
    public bool SupportsConfig => (Caps & 0x04) != 0;
    public bool SupportsFences => (Caps & 0x08) != 0;

    public static WatchInfo? Decode(byte[] p)
    {
        var r = new LeReader(p);
        int bp = r.U8(), up = r.U8(), rf = r.U16(), cs = r.U16();
        string fw = r.Str(16), dev = r.Str(16);
        long boot = r.U32(); int mtu = r.U16(); long caps = r.U32();
        if (!r.Ok) return null;
        bool? a = null, cp = null, req = null; int? k = null; string? fp = null;
        if (r.Remaining >= 4) { a = r.U8() != 0; k = r.U8(); cp = r.U8() != 0; req = r.U8() != 0; }
        if (r.Remaining >= 32) fp = r.Str(32);
        return new WatchInfo(bp, up, rf, cs, fw, dev, boot, mtu, caps, a, k, cp, req, fp);
    }
}

/// <summary>Application authorization (firmware V3.4.4, avo_ble_auth.cpp).</summary>
public static class WatchAuth
{
    public static byte[] Nonce() => RandomNumberGenerator.GetBytes(16);
    private static byte[] Proof(string tag, byte[] key, byte[] a, byte[] b, string devId)
    {
        if (key.Length != 32 || a.Length != 16 || b.Length != 16) throw new ArgumentException("tamaños de autorización");
        var dev = new byte[12];
        var d = Encoding.ASCII.GetBytes(devId);
        Array.Copy(d, dev, Math.Min(12, d.Length));
        return HMACSHA256.HashData(key, [.. Encoding.ASCII.GetBytes(tag), .. a, .. b, .. dev]);
    }
    /// <summary>watch_proof = HMAC-SHA256(K, "AVOW" | pn | wn | dev_id)</summary>
    public static byte[] WatchProof(byte[] key, byte[] phoneNonce, byte[] watchNonce, string devId) => Proof("AVOW", key, phoneNonce, watchNonce, devId);
    /// <summary>phone_proof = HMAC-SHA256(K, "AVOP" | wn | pn | dev_id)</summary>
    public static byte[] PhoneProof(byte[] key, byte[] watchNonce, byte[] phoneNonce, string devId) => Proof("AVOP", key, watchNonce, phoneNonce, devId);
}

/// <summary>
/// Request/response engine (same rules as AvoClient.kt): one request in flight; responses matched by msg_id; state-changing
/// commands keep their msg_id on retry so the watch answers DUPLICATE instead of executing twice.
/// </summary>
public sealed class AvoClient
{
    private readonly IAvoTransport _t;
    private readonly BleReassembler _ctrl = new(), _other = new();
    private readonly ConcurrentDictionary<ushort, TaskCompletionSource<BleMessage>> _pending = new();
    private readonly SemaphoreSlim _gate = new(1, 1);
    private int _next;
    public event Action<BleMessage>? Unsolicited;
    public int LateResponses { get; private set; }

    public AvoClient(IAvoTransport t, int? startMsgId = null)
    {
        _t = t;
        _next = (startMsgId ?? RandomNumberGenerator.GetInt32(1, 0x7000)) & 0x7FFF;
    }

    private ushort NewId() { _next = (_next + 1) & 0x7FFF; if (_next == 0) _next = 1; return (ushort)_next; }

    /// <summary>Feed every notification here, with the characteristic it came from.</summary>
    public void OnNotification(Guid characteristic, byte[] value)
    {
        var m = (characteristic == AvoGatt.CtrlTx ? _ctrl : _other).Feed(value);
        if (m is null) return;
        if (m.IsResponse) { if (_pending.TryRemove(m.MsgId, out var tcs)) tcs.TrySetResult(m); else LateResponses++; }
        else Unsolicited?.Invoke(m);
    }

    public void OnDisconnected()
    {
        _ctrl.Reset(); _other.Reset();
        foreach (var p in _pending.Values) p.TrySetException(new BleRequestException(BleStatus.Timeout, "Conexión perdida"));
        _pending.Clear();
    }

    public async Task<BleMessage> RequestAsync(MsgType type, byte[]? payload = null, bool stateChanging = false, int timeoutMs = 3000, int retries = 2,
        CancellationToken ct = default)
    {
        payload ??= [];
        await _gate.WaitAsync(ct);
        try
        {
            ushort id = NewId();
            for (int attempt = 0; ; attempt++)
            {
                var tcs = new TaskCompletionSource<BleMessage>(TaskCreationOptions.RunContinuationsAsynchronously);
                _pending[id] = tcs;
                try
                {
                    foreach (var f in BleFraming.Fragment((byte)type, id, payload, _t.AttPayload)) await _t.WriteCtrlAsync(f, ct);
                    var done = await Task.WhenAny(tcs.Task, Task.Delay(timeoutMs, ct));
                    if (done == tcs.Task)
                    {
                        var m = await tcs.Task;
                        if (m.StatusEnum == BleStatus.BadCrc && attempt < retries) continue;
                        return m;
                    }
                    ct.ThrowIfCancellationRequested();
                    if (attempt >= retries) throw new BleRequestException(BleStatus.Timeout, $"Sin respuesta del reloj ({type})");
                    if (!stateChanging) id = NewId();
                }
                finally { _pending.TryRemove(id, out _); }
            }
        }
        finally { _gate.Release(); }
    }

    public async Task<byte[]> RequestOkAsync(MsgType type, byte[]? payload = null, bool stateChanging = false, int timeoutMs = 3000, CancellationToken ct = default)
    {
        var m = await RequestAsync(type, payload, stateChanging, timeoutMs, ct: ct);
        if (m.StatusEnum != BleStatus.Ok) throw new BleRequestException(m.StatusEnum, $"{type}: {BleStatusText.Es(m.StatusEnum)}");
        return m.Payload;
    }

    public async Task<WatchInfo> GetInfoAsync(CancellationToken ct = default) =>
        WatchInfo.Decode(await RequestOkAsync(MsgType.GetInfo, ct: ct)) ?? throw new BleRequestException(BleStatus.BadFormat, "GET_INFO ilegible");

    /// <summary>HMAC challenge-response in both directions (the PC also checks that the watch knows the key).</summary>
    public async Task<AuthOutcome> AuthenticateAsync(WatchCredential cred, CancellationToken ct = default)
    {
        var pn = WatchAuth.Nonce();
        var m = await RequestAsync(MsgType.AuthHello, [.. cred.KeyId, .. pn], ct: ct);
        switch (m.StatusEnum)
        {
            case BleStatus.Ok: break;
            case BleStatus.NotFound: return AuthOutcome.UnknownKey;
            case BleStatus.Busy: return AuthOutcome.Locked;
            default: return AuthOutcome.Error;
        }
        if (m.Payload.Length < 48) return AuthOutcome.Error;
        var wn = m.Payload[..16];
        var wp = m.Payload[16..48];
        if (!CryptographicOperations.FixedTimeEquals(wp, WatchAuth.WatchProof(cred.Key, pn, wn, cred.DeviceId))) return AuthOutcome.WatchNotAuthentic;
        var r = await RequestAsync(MsgType.AuthProof, WatchAuth.PhoneProof(cred.Key, wn, pn, cred.DeviceId), ct: ct);
        return r.StatusEnum switch
        {
            BleStatus.Ok => AuthOutcome.Ok,
            BleStatus.Busy => AuthOutcome.Locked,
            BleStatus.AuthRequired => AuthOutcome.Rejected,
            _ => AuthOutcome.Error,
        };
    }

    /// <summary>Starts the BOOT-button claim: the watch shows "PULSA BOOT" for 60 s.</summary>
    public async Task<BleStatus> ClaimBeginAsync(string clientName, CancellationToken ct = default) =>
        (await RequestAsync(MsgType.ClaimBegin, new LeWriter().Str(clientName, 24).ToArray(), stateChanging: true, ct: ct)).StatusEnum;

    /// <summary>Polls CLAIM_RESULT: OK → credential; BUSY → still waiting for BOOT.</summary>
    public async Task<(BleStatus Status, WatchCredential? Credential)> ClaimResultAsync(string deviceId, CancellationToken ct = default)
    {
        var m = await RequestAsync(MsgType.ClaimResult, ct: ct);
        if (m.StatusEnum == BleStatus.Ok && m.Payload.Length >= 40) return (BleStatus.Ok, new WatchCredential(deviceId, m.Payload[..8], m.Payload[8..40]));
        return (m.StatusEnum, null);
    }

    public Task<byte[]> GetConfigAsync(CancellationToken ct = default) => RequestOkAsync(MsgType.GetConfig, timeoutMs: 5000, ct: ct);
    public Task<BleMessage> SetConfigAsync(byte[] blob, CancellationToken ct = default) => RequestAsync(MsgType.SetConfig, blob, true, 8000, ct: ct);
    public Task<BleMessage> SetFenceAsync(byte[] request, CancellationToken ct = default) => RequestAsync(MsgType.SetFence, request, true, 8000, ct: ct);
    public async Task<BleStatus> SetActiveFencesAsync(int mask, bool auto, CancellationToken ct = default) =>
        (await RequestAsync(MsgType.SetActiveFences, [(byte)mask, (byte)(auto ? 1 : 0)], true, ct: ct)).StatusEnum;
}
