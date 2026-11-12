using System.Runtime.InteropServices;
using System.Text;

namespace Avo.Windows.Core;

/// <summary>Minimal NDEF (NFC Forum) reader/writer: what is needed for the URI records of the AVO identity tags.</summary>
public static class Ndef
{
    // NFC Forum URI RTD, abbreviation table (0x00 = none)
    private static readonly string[] UriPrefixes =
    [
        "", "http://www.", "https://www.", "http://", "https://", "tel:", "mailto:", "ftp://anonymous:anonymous@", "ftp://ftp.",
        "ftps://", "sftp://", "smb://", "nfs://", "ftp://", "dav://", "news:", "telnet://", "imap:", "rtsp://", "urn:", "pop:",
        "sip:", "sips:", "tftp:", "btspp://", "btl2cap://", "btgoep://", "tcpobex://", "irdaobex://", "file://", "urn:epc:id:",
        "urn:epc:tag:", "urn:epc:pat:", "urn:epc:raw:", "urn:epc:", "urn:nfc:",
    ];

    public sealed record Record(byte Tnf, byte[] Type, byte[] Id, byte[] Payload);

    /// <summary>Parses an NDEF message. Throws FormatException on malformed data (lengths are always checked).</summary>
    public static List<Record> Parse(ReadOnlySpan<byte> m)
    {
        var list = new List<Record>();
        int i = 0;
        while (i < m.Length)
        {
            byte h = m[i++];
            bool me = (h & 0x40) != 0, cf = (h & 0x20) != 0, sr = (h & 0x10) != 0, il = (h & 0x08) != 0;
            byte tnf = (byte)(h & 7);
            if (cf) throw new FormatException("Registros NDEF fragmentados no admitidos");
            if (i >= m.Length) throw new FormatException("NDEF truncado");
            int typeLen = m[i++];
            long payLen;
            if (sr) { Need(m, i, 1); payLen = m[i++]; }
            else { Need(m, i, 4); payLen = (uint)(m[i] << 24 | m[i + 1] << 16 | m[i + 2] << 8 | m[i + 3]); i += 4; }
            int idLen = 0;
            if (il) { Need(m, i, 1); idLen = m[i++]; }
            if (payLen > 65536) throw new FormatException("Registro NDEF demasiado grande");
            Need(m, i, typeLen + idLen + (int)payLen);
            var type = m.Slice(i, typeLen).ToArray(); i += typeLen;
            var id = m.Slice(i, idLen).ToArray(); i += idLen;
            var pay = m.Slice(i, (int)payLen).ToArray(); i += (int)payLen;
            list.Add(new Record(tnf, type, id, pay));
            if (me) break;
        }
        return list;
    }

    private static void Need(ReadOnlySpan<byte> m, int i, int n)
    {
        if (n < 0 || i + n > m.Length) throw new FormatException("NDEF truncado");
    }

    /// <summary>URI of a well-known "U" record, or null.</summary>
    public static string? UriOf(Record r)
    {
        if (r.Tnf != 1 || r.Type.Length != 1 || r.Type[0] != (byte)'U' || r.Payload.Length < 1) return null;
        int code = r.Payload[0];
        string prefix = code < UriPrefixes.Length ? UriPrefixes[code] : "";
        return prefix + Encoding.UTF8.GetString(r.Payload, 1, r.Payload.Length - 1);
    }

    /// <summary>All URIs of a message, in order.</summary>
    public static IEnumerable<string> Uris(ReadOnlySpan<byte> message) => Parse(message).Select(UriOf).OfType<string>().ToList();

    /// <summary>One-record message with a URI record, like NdefRecord.createUri (no abbreviation applies to avohorse://).</summary>
    public static byte[] UriMessage(string uri)
    {
        int code = 0;
        for (int k = 1; k < UriPrefixes.Length; k++)
            if (uri.StartsWith(UriPrefixes[k], StringComparison.Ordinal) && UriPrefixes[k].Length > UriPrefixes[code].Length) code = k;
        var rest = Encoding.UTF8.GetBytes(uri[UriPrefixes[code].Length..]);
        var payload = new byte[rest.Length + 1];
        payload[0] = (byte)code;
        rest.CopyTo(payload, 1);
        var o = new List<byte>();
        if (payload.Length < 256) { o.Add(0xD1); o.Add(1); o.Add((byte)payload.Length); }
        else { o.Add(0xC1); o.Add(1); o.AddRange([(byte)(payload.Length >> 24), (byte)(payload.Length >> 16), (byte)(payload.Length >> 8), (byte)payload.Length]); }
        o.Add((byte)'U');
        o.AddRange(payload);
        return o.ToArray();
    }

    public enum TlvScan { Found, Absent, NeedMore }

    /// <summary>Finds the NDEF message TLV (type 0x03) in the data area of a Type 2 tag (from page 4).</summary>
    public static byte[]? FindMessageTlv(ReadOnlySpan<byte> area)
    {
        var st = ScanMessageTlv(area, out var m);
        if (st == TlvScan.NeedMore) throw new FormatException("TLV NDEF truncado");
        return m;
    }

    /// <summary>Scans the TLVs read so far: Found (message), Absent (terminator first) or NeedMore (not enough bytes yet).</summary>
    public static TlvScan ScanMessageTlv(ReadOnlySpan<byte> area, out byte[]? message)
    {
        message = null;
        int i = 0;
        while (i < area.Length)
        {
            byte t = area[i++];
            if (t == 0x00) continue;          // NULL TLV
            if (t == 0xFE) return TlvScan.Absent;
            if (i >= area.Length) return TlvScan.NeedMore;
            int len = area[i++];
            if (len == 0xFF)
            {
                if (i + 2 > area.Length) return TlvScan.NeedMore;
                len = area[i] << 8 | area[i + 1];
                i += 2;
            }
            if (i + len > area.Length) return TlvScan.NeedMore;
            if (t == 0x03) { message = area.Slice(i, len).ToArray(); return TlvScan.Found; }
            i += len;                          // lock / memory control or proprietary TLV
        }
        return TlvScan.NeedMore;
    }

    /// <summary>NDEF message TLV + terminator, padded to whole 4-byte pages.</summary>
    public static byte[] MessageTlv(byte[] message)
    {
        var o = new List<byte> { 0x03 };
        if (message.Length < 0xFF) o.Add((byte)message.Length);
        else { o.Add(0xFF); o.Add((byte)(message.Length >> 8)); o.Add((byte)message.Length); }
        o.AddRange(message);
        o.Add(0xFE);
        while (o.Count % 4 != 0) o.Add(0x00);
        return o.ToArray();
    }
}

public sealed class NfcException(string message) : Exception(message);

/// <summary>
/// NTAG21x / NFC Forum Type 2 tags through a PC/SC reader, using the PC/SC Part 3 storage-card APDUs that USB readers
/// (ACS ACR122U / ACR1252U and compatible) translate: GET DATA (UID), READ BINARY, UPDATE BINARY by page.
/// Only the NDEF data area (page 4 up to the size in the Capability Container) is ever written; CC, lock and
/// configuration pages are never touched, and a read-only tag (CC access byte ≠ 0) is refused.
/// </summary>
public static class NtagApdu
{
    public delegate byte[] Transmit(byte[] apdu);

    public static string ReadUid(Transmit tx)
    {
        var r = Ok(tx([0xFF, 0xCA, 0x00, 0x00, 0x00]), "leer el UID");
        return Convert.ToHexString(r);
    }

    private static byte[] Ok(byte[] r, string what)
    {
        if (r.Length < 2 || r[^2] != 0x90 || r[^1] != 0x00)
            throw new NfcException($"El lector no pudo {what} (estado {(r.Length >= 2 ? r[^2].ToString("X2") + r[^1].ToString("X2") : "vacío")})");
        return r[..^2];
    }

    /// <summary>Reads 4 bytes of one page (READ BINARY with Le = 4: accepted by every PC/SC Type 2 implementation).</summary>
    private static byte[] Page(Transmit tx, int page)
    {
        var d = Ok(tx([0xFF, 0xB0, 0x00, (byte)page, 0x04]), $"leer la página {page}");
        if (d.Length < 4) throw new NfcException($"Página {page} incompleta");
        return d[..4];
    }

    /// <summary>Capability Container: (data area bytes, writable).</summary>
    public static (int Size, bool Writable) ReadCapability(Transmit tx)
    {
        var cc = Page(tx, 3);
        if (cc[0] != 0xE1) throw new NfcException("La etiqueta no está formateada como NDEF (Type 2)");
        int size = cc[2] * 8;
        if (size < 16 || size > 2048) throw new NfcException("Tamaño de etiqueta no válido");
        return (size, (cc[3] & 0x0F) == 0x00);   // CC byte 3: high nibble = read access, low nibble = write access
    }

    /// <summary>Reads the NDEF message (null when the tag has none).</summary>
    public static byte[]? ReadMessage(Transmit tx)
    {
        var (size, _) = ReadCapability(tx);
        var area = new List<byte>(size);
        for (int p = 4; area.Count < size; p++)
        {
            area.AddRange(Page(tx, p));
            var st = Ndef.ScanMessageTlv(System.Runtime.InteropServices.CollectionsMarshal.AsSpan(area), out var m);
            if (st == Ndef.TlvScan.Found) return m;
            if (st == Ndef.TlvScan.Absent) return null;
        }
        return null;
    }

    /// <summary>Writes an NDEF message into the data area and reads it back to verify it.</summary>
    public static void WriteMessage(Transmit tx, byte[] message)
    {
        var (size, writable) = ReadCapability(tx);
        if (!writable) throw new NfcException("La etiqueta está bloqueada (solo lectura)");
        var tlv = Ndef.MessageTlv(message);
        if (tlv.Length > size) throw new NfcException($"El mensaje ({tlv.Length} B) no cabe en la etiqueta ({size} B)");
        for (int k = 0; k < tlv.Length; k += 4)
        {
            int page = 4 + k / 4;
            Ok(tx([0xFF, 0xD6, 0x00, (byte)page, 0x04, tlv[k], tlv[k + 1], tlv[k + 2], tlv[k + 3]]), $"escribir la página {page}");
        }
        var back = ReadMessage(tx);
        if (back is null || !back.AsSpan().SequenceEqual(message)) throw new NfcException("La verificación tras escribir no coincide");
    }
}

/// <summary>Result of presenting a tag to the reader.</summary>
public sealed record NfcTagEvent(string Reader, string? UidHex, string? AvoUri, AvoIdentityTag? Tag, string? Error, bool Written = false);

public interface INfcReader : IDisposable
{
    event Action<NfcTagEvent>? TagEvent;
    event Action<string>? StatusChanged;
    string Status { get; }
    bool ReaderPresent { get; }
    void Start();
    /// <summary>The next tag presented is written with this NDEF message instead of being read (cancel with null).</summary>
    void ArmWrite(byte[]? message);
    bool WriteArmed { get; }
}

/// <summary>PC/SC (winscard.dll) reader watcher. Windows only; elsewhere it reports that NFC is not available.</summary>
public sealed class PcscNfcReader : INfcReader
{
    public event Action<NfcTagEvent>? TagEvent;
    public event Action<string>? StatusChanged;
    private string _status = "Lector NFC: iniciando…";
    public string Status => _status;
    public bool ReaderPresent { get; private set; }
    private volatile byte[]? _write;
    public bool WriteArmed => _write is not null;
    public void ArmWrite(byte[]? message) => _write = message;

    private Thread? _thread;
    private volatile bool _stop;
    private IntPtr _ctx;

    public void Start()
    {
        if (_thread is not null) return;
        if (!OperatingSystem.IsWindows()) { SetStatus("Lector NFC: solo disponible en Windows"); return; }
        _thread = new Thread(Loop) { IsBackground = true, Name = "AVO NFC" };
        _thread.Start();
    }

    private void SetStatus(string s)
    {
        if (s == _status) return;
        _status = s;
        StatusChanged?.Invoke(s);
    }

    private void Loop()
    {
        var known = new Dictionary<string, uint>(StringComparer.Ordinal);
        while (!_stop)
        {
            try
            {
                if (_ctx == IntPtr.Zero)
                {
                    int rc = W.SCardEstablishContext(W.ScopeUser, IntPtr.Zero, IntPtr.Zero, out _ctx);
                    if (rc != 0) { _ctx = IntPtr.Zero; ReaderPresent = false; SetStatus("Lector NFC: no hay lector conectado (servicio de tarjetas inteligentes inactivo)"); Sleep(3000); continue; }
                }
                var readers = W.ListReaders(_ctx, out int lrc);
                if (lrc is W.ErrNoService or W.ErrServiceStopped or W.ErrInvalidHandle) { Release(); continue; }
                ReaderPresent = readers.Count > 0;
                if (readers.Count == 0)
                {
                    known.Clear();
                    SetStatus("Lector NFC: no hay lector conectado (USB PC/SC, p. ej. ACR122U)");
                    var pnp = new[] { W.State(W.PnP, 0) };
                    int r0 = W.SCardGetStatusChange(_ctx, 2000, pnp, 1);
                    if (r0 is not (0 or W.ErrTimeout or W.ErrNoReaders)) Release();
                    continue;
                }
                foreach (var k in known.Keys.Except(readers).ToList()) known.Remove(k);
                var states = readers.Select(r => W.State(r, known.TryGetValue(r, out var s) ? s : 0)).Append(W.State(W.PnP, (uint)readers.Count << 16)).ToArray();
                if (!WriteArmed) SetStatus($"Lector NFC: {readers[0]}{(readers.Count > 1 ? $" (+{readers.Count - 1})" : "")} · acerca una etiqueta");
                else SetStatus("Lector NFC: acerca la etiqueta que quieres GRABAR");
                int rc2 = W.SCardGetStatusChange(_ctx, 1000, states, states.Length);
                if (rc2 == W.ErrTimeout) continue;
                if (rc2 == W.ErrCancelled) break;
                if (rc2 != 0) { Release(); Sleep(500); continue; }
                for (int i = 0; i < readers.Count; i++)
                {
                    uint ev = states[i].dwEventState;
                    bool wasPresent = known.TryGetValue(readers[i], out var prev) && (prev & W.StatePresent) != 0;
                    known[readers[i]] = ev & ~W.StateChanged;
                    if ((ev & W.StatePresent) != 0 && !wasPresent && (ev & W.StateMute) == 0) HandleCard(readers[i]);
                }
            }
            catch (Exception ex) when (ex is DllNotFoundException or EntryPointNotFoundException or BadImageFormatException)
            {
                SetStatus("Lector NFC: winscard.dll no disponible");
                return;
            }
            catch (Exception ex)
            {
                AppLog.Current?.Warn("nfc", ex.Message, ex);
                Release();
                Sleep(1000);
            }
        }
        Release();
    }

    private void HandleCard(string reader)
    {
        int rc = W.SCardConnect(_ctx, reader, W.ShareShared, W.ProtoT0 | W.ProtoT1, out IntPtr card, out uint proto);
        if (rc != 0) { TagEvent?.Invoke(new NfcTagEvent(reader, null, null, null, $"No se pudo conectar con la etiqueta (0x{rc:X8})")); return; }
        try
        {
            byte[] Tx(byte[] apdu)
            {
                var pci = new W.IoRequest { dwProtocol = proto, cbPciLength = 8 };
                var rx = new byte[262];
                int len = rx.Length;
                int r = W.SCardTransmit(card, ref pci, apdu, apdu.Length, IntPtr.Zero, rx, ref len);
                if (r != 0) throw new NfcException($"Error de comunicación con el lector (0x{r:X8})");
                return rx[..len];
            }
            string? uid = null;
            try { uid = NtagApdu.ReadUid(Tx); } catch (NfcException) { }
            var w = _write;
            if (w is not null)
            {
                NtagApdu.WriteMessage(Tx, w);
                _write = null;
                var uri = Ndef.Uris(w).FirstOrDefault();
                TagEvent?.Invoke(new NfcTagEvent(reader, uid, uri, uri is null ? null : SafeParse(uri, out _), null, Written: true));
                return;
            }
            var msg = NtagApdu.ReadMessage(Tx);
            if (msg is null || msg.Length == 0) { TagEvent?.Invoke(new NfcTagEvent(reader, uid, null, null, "Etiqueta vacía (sin mensaje NDEF)")); return; }
            var avo = Ndef.Uris(msg).FirstOrDefault(u => u.StartsWith("avohorse://identity/", StringComparison.OrdinalIgnoreCase));
            if (avo is null) { TagEvent?.Invoke(new NfcTagEvent(reader, uid, null, null, "Etiqueta no AVO")); return; }
            var tag = SafeParse(avo, out string? err);
            TagEvent?.Invoke(new NfcTagEvent(reader, uid, avo, tag, err));
        }
        catch (Exception ex) when (ex is NfcException or FormatException)
        {
            TagEvent?.Invoke(new NfcTagEvent(reader, null, null, null, ex.Message));
        }
        finally { W.SCardDisconnect(card, 0); }
    }

    private static AvoIdentityTag? SafeParse(string uri, out string? error)
    {
        try { error = null; return AvoIdentityTag.Parse(uri); }
        catch (FormatException ex) { error = ex.Message; return null; }
    }

    private void Sleep(int ms) { for (int t = 0; t < ms && !_stop; t += 100) Thread.Sleep(100); }

    private void Release()
    {
        if (_ctx != IntPtr.Zero) { try { W.SCardReleaseContext(_ctx); } catch (DllNotFoundException) { } _ctx = IntPtr.Zero; }
    }

    public void Dispose()
    {
        _stop = true;
        if (_ctx != IntPtr.Zero) try { W.SCardCancel(_ctx); } catch (DllNotFoundException) { }
        _thread?.Join(3000);
    }

    /// <summary>winscard.dll (PC/SC) declarations.</summary>
    private static class W
    {
        public const uint ScopeUser = 0, ShareShared = 2, ProtoT0 = 1, ProtoT1 = 2;
        public const uint StateChanged = 0x2, StatePresent = 0x20, StateMute = 0x200;
        public const int ErrTimeout = unchecked((int)0x8010000A), ErrCancelled = unchecked((int)0x80100002), ErrNoReaders = unchecked((int)0x8010002E),
            ErrNoService = unchecked((int)0x8010001D), ErrServiceStopped = unchecked((int)0x8010001E), ErrInvalidHandle = unchecked((int)0x80100003);
        public const string PnP = "\\\\?PnP?\\Notification";

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct ReaderState
        {
            public string szReader;
            public IntPtr pvUserData;
            public uint dwCurrentState;
            public uint dwEventState;
            public uint cbAtr;
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 36)] public byte[] rgbAtr;
        }
        [StructLayout(LayoutKind.Sequential)]
        public struct IoRequest { public uint dwProtocol; public uint cbPciLength; }

        public static ReaderState State(string reader, uint current) => new() { szReader = reader, dwCurrentState = current, rgbAtr = new byte[36] };

        [DllImport("winscard.dll")] public static extern int SCardEstablishContext(uint scope, IntPtr r1, IntPtr r2, out IntPtr ctx);
        [DllImport("winscard.dll")] public static extern int SCardReleaseContext(IntPtr ctx);
        [DllImport("winscard.dll")] public static extern int SCardCancel(IntPtr ctx);
        [DllImport("winscard.dll", EntryPoint = "SCardListReadersW", CharSet = CharSet.Unicode)]
        private static extern int SCardListReaders(IntPtr ctx, string? groups, char[]? readers, ref int len);
        [DllImport("winscard.dll", EntryPoint = "SCardGetStatusChangeW", CharSet = CharSet.Unicode)]
        public static extern int SCardGetStatusChange(IntPtr ctx, int timeout, [In, Out] ReaderState[] states, int count);
        [DllImport("winscard.dll", EntryPoint = "SCardConnectW", CharSet = CharSet.Unicode)]
        public static extern int SCardConnect(IntPtr ctx, string reader, uint share, uint protocols, out IntPtr card, out uint active);
        [DllImport("winscard.dll")] public static extern int SCardDisconnect(IntPtr card, uint disposition);
        [DllImport("winscard.dll")]
        public static extern int SCardTransmit(IntPtr card, ref IoRequest send, byte[] sendBuf, int sendLen, IntPtr recvPci, byte[] recvBuf, ref int recvLen);

        public static List<string> ListReaders(IntPtr ctx, out int rc)
        {
            int len = 0;
            rc = SCardListReaders(ctx, null, null, ref len);
            if (rc != 0 || len <= 0) return [];
            var buf = new char[len];
            rc = SCardListReaders(ctx, null, buf, ref len);
            if (rc != 0) return [];
            return new string(buf, 0, Math.Max(0, len)).Split('\0', StringSplitOptions.RemoveEmptyEntries).ToList();
        }
    }
}

/// <summary>Reader used by the capture mode and the self-tests: tags are "presented" in code. Never used with real data.</summary>
public sealed class SimulatedNfcReader : INfcReader
{
    public event Action<NfcTagEvent>? TagEvent;
    public event Action<string>? StatusChanged;
    public string Status { get; private set; } = "Lector NFC simulado (pruebas)";
    public bool ReaderPresent => true;
    public bool WriteArmed { get; private set; }
    public byte[]? LastWritten { get; private set; }
    public void Start() => StatusChanged?.Invoke(Status);
    public void ArmWrite(byte[]? message) { _armed = message; WriteArmed = message is not null; }
    private byte[]? _armed;
    public void Present(string uid, string uri)
    {
        if (_armed is not null)
        {
            LastWritten = _armed; _armed = null; WriteArmed = false;
            var u = Ndef.Uris(LastWritten).First();
            TagEvent?.Invoke(new NfcTagEvent("Simulado", uid, u, AvoIdentityTag.Parse(u), null, true));
            return;
        }
        AvoIdentityTag? t = null; string? err = null;
        try { t = AvoIdentityTag.Parse(uri); } catch (FormatException ex) { err = ex.Message; }
        TagEvent?.Invoke(new NfcTagEvent("Simulado", uid, uri, t, err));
    }
    public void Dispose() { }
}
