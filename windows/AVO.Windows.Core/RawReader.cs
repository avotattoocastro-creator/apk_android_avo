using System.Buffers.Binary;
using System.Text;

namespace Avo.Windows.Core;

/// <summary>Reader of AVORAW1 (.avr), ported from core/raw/RawSession.kt. Rejects invalid CRCs and torn blocks.</summary>
public static class RawReader
{
    private const int HeaderSize = 512;
    private const int BlockHeaderSize = 36;
    private const int RecordHeaderSize = 12;
    private const int MaxPayload = 65536;
    private static ushort U16(ReadOnlySpan<byte> b) => BinaryPrimitives.ReadUInt16LittleEndian(b);
    private static uint U32(ReadOnlySpan<byte> b) => BinaryPrimitives.ReadUInt32LittleEndian(b);
    private static int I32(ReadOnlySpan<byte> b) => BinaryPrimitives.ReadInt32LittleEndian(b);
    private static ulong U64(ReadOnlySpan<byte> b) => BinaryPrimitives.ReadUInt64LittleEndian(b);
    private static uint Crc32(ReadOnlySpan<byte> b)
    {
        uint crc = 0xFFFFFFFF;
        foreach (byte x in b)
        {
            crc ^= x;
            for (int i = 0; i < 8; i++) crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
        }
        return crc ^ 0xFFFFFFFF;
    }

    private static byte Crc8(ReadOnlySpan<byte> bytes)
    {
        byte crc = 0;
        foreach (byte v in bytes)
        {
            crc ^= v;
            for (int bit = 0; bit < 8; bit++)
                crc = (byte)((crc & 0x80) != 0 ? (crc << 1) ^ 0x07 : crc << 1);
        }
        return crc;
    }

    private static string Str(ReadOnlySpan<byte> bytes)
    {
        int end = bytes.IndexOf((byte)0);
        return Encoding.UTF8.GetString(bytes[..(end < 0 ? bytes.Length : end)]);
    }

    public static SegmentSummary Scan(Stream stream, TrainingSession session, string name, int segmentIndex)
    {
        var header = new byte[HeaderSize];
        if (!ReadExactlyOrFalse(stream, header)) throw new InvalidDataException("Cabecera AVORAW1 incompleta");
        if (!header.AsSpan(0, 8).SequenceEqual("AVORAW1\0"u8) || U32(header.AsSpan(508, 4)) != Crc32(header.AsSpan(0, 508)))
            throw new InvalidDataException("Cabecera AVORAW1 o CRC-32 incorrectos");
        if (U16(header.AsSpan(8, 2)) < 1 || U16(header.AsSpan(10, 2)) != HeaderSize)
            throw new InvalidDataException("Versión AVORAW no compatible");
        var id = Str(header.AsSpan(12, 24));
        if (string.IsNullOrWhiteSpace(session.SessionId)) session.SessionId = id;
        else if (id != session.SessionId) throw new InvalidDataException("Los segmentos pertenecen a sesiones diferentes");
        if (session.StartedAt is null)
        {
            long rtc = (long)U64(header.AsSpan(40, 8));
            if (rtc is > 946684800000 and < 4102444800000) session.StartedAt = DateTimeOffset.FromUnixTimeMilliseconds(rtc);
        }
        var horse = Str(header.AsSpan(124, 24));
        var rider = Str(header.AsSpan(152, 24));
        if (!string.IsNullOrWhiteSpace(horse) && session.Horse == "Sin identificar") session.Horse = horse;
        if (!string.IsNullOrWhiteSpace(rider) && session.Rider == "Sin identificar") session.Rider = rider;

        long validBytes = HeaderSize;
        int blocks = 0, records = 0, bad = 0;
        bool clean = false, torn = false;
        var bh = new byte[BlockHeaderSize];
        while (true)
        {
            int read = ReadAtMost(stream, bh);
            if (read == 0) break;
            if (read != BlockHeaderSize) { torn = true; break; }
            int length = checked((int)Math.Min(U32(bh.AsSpan(8, 4)), int.MaxValue));
            if (U32(bh.AsSpan(0, 4)) != 0x424F5641 || U32(bh.AsSpan(32, 4)) != Crc32(bh.AsSpan(0, 32)) || length > MaxPayload)
            { torn = true; break; }
            var payload = new byte[length];
            if (!ReadExactlyOrFalse(stream, payload) || U32(bh.AsSpan(28, 4)) != Crc32(payload))
            { torn = true; break; }
            int recordCount = U16(bh.AsSpan(12, 2));
            int flags = U16(bh.AsSpan(14, 2));
            int offset = 0, parsed = 0;
            while (parsed < recordCount && offset + RecordHeaderSize <= length)
            {
                int type = payload[offset];
                int dataLength = U16(payload.AsSpan(offset + 2, 2));
                if (offset + RecordHeaderSize + dataLength > length) { bad += recordCount - parsed; break; }
                var data = payload.AsSpan(offset + RecordHeaderSize, dataLength);
                if (type == 0x05) session.MarkerCount++;
                if (type == 0x01) ReadUart(data, session);
                offset += RecordHeaderSize + dataLength;
                parsed++;
            }
            if (parsed < recordCount && bad == 0) bad += recordCount - parsed;
            validBytes += BlockHeaderSize + length;
            blocks++;
            records += parsed;
            clean |= (flags & 2) != 0;
        }
        return new SegmentSummary(name, segmentIndex, validBytes, blocks, records, clean, torn, bad);
    }

    private static void ReadUart(ReadOnlySpan<byte> data, TrainingSession session)
    {
        if (data.Length < 19 || data[0] != 0xA5 || data[1] != 0x5A || Crc8(data.Slice(2, 12)) != data[14])
        { session.InvalidFrames++; return; }
        int length = U16(data.Slice(8, 2));
        if (length + 19 != data.Length || U32(data.Slice(15 + length, 4)) != Crc32(data.Slice(2, 13 + length)))
        { session.InvalidFrames++; return; }
        var payload = data.Slice(15, length);
        switch (data[3])
        {
            case 0x10: ReadGnss(payload, session); break;
            case 0x20:
                if (payload.Length >= 24) { session.TotalImuBatches++; session.TotalImuSamples += payload[2]; }
                else session.InvalidFrames++;
                break;
        }
    }
    private static void ReadGnss(ReadOnlySpan<byte> b, TrainingSession session)
    {
        if (b.Length < 85) { session.InvalidFrames++; return; }
        session.GnssSamples++;
        int fixType = b[20], flags = b[21], flags3 = U16(b.Slice(22, 2));
        if ((flags & 1) == 0 || (flags3 & 1) != 0 || fixType is < 2 or > 4)
        { session.UnusableGnssSamples++; return; }
        int carrier = (flags >> 6) & 3;
        if (carrier == 2) session.RtkFixCount++;
        else if (carrier == 1) session.RtkFloatCount++;
        else session.GnssOtherCount++;
        double lon = I32(b.Slice(25, 4)) * 1e-7, lat = I32(b.Slice(29, 4)) * 1e-7;
        double speed = I32(b.Slice(61, 4)) / 1000.0;
        if (!double.IsFinite(speed) || speed < 0 || lat is < -90 or > 90 || lon is < -180 or > 180)
        { session.UnusableGnssSamples++; return; }
        long itow = U32(b.Slice(0, 4));
        session.Track.Add(new TrackPoint(lat, lon, speed, U32(b.Slice(41, 4)) / 1000.0,
            carrier, itow, I32(b.Slice(33, 4)) / 1000.0));
    }
    private static bool ReadExactlyOrFalse(Stream stream, byte[] data) => ReadAtMost(stream, data) == data.Length;
    private static int ReadAtMost(Stream stream, byte[] buffer)
    {
        int got = 0;
        while (got < buffer.Length)
        {
            int n = stream.Read(buffer, got, buffer.Length - got);
            if (n <= 0) break;
            got += n;
        }
        return got;
    }
}
