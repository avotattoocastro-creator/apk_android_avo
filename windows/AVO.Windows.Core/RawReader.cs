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
        // the AVORAW1 header carries the code written to the watch (e.g. HORSE_001)
        if (!string.IsNullOrWhiteSpace(horse) && string.IsNullOrWhiteSpace(session.HorseCode)) session.HorseCode = horse.Trim();
        if (!string.IsNullOrWhiteSpace(rider) && string.IsNullOrWhiteSpace(session.RiderCode)) session.RiderCode = rider.Trim();

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
                ulong chestUs = U64(payload.AsSpan(offset + 4, 8));
                if (type == 0x05)
                {
                    session.MarkerCount++;
                    // MARKER: u8 source, u32 marker_count (chest controller.cpp); older writers may differ -> keep time only.
                    session.Markers.Add(data.Length >= 5 ? new MarkerEvent(chestUs, data[0], U32(data.Slice(1, 4))) : new MarkerEvent(chestUs, -1, 0));
                }
                if (type == 0x01) ReadUart(data, session, chestUs);
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

    private static void ReadUart(ReadOnlySpan<byte> data, TrainingSession session, ulong chestUs)
    {
        if (data.Length < 19 || data[0] != 0xA5 || data[1] != 0x5A || Crc8(data.Slice(2, 12)) != data[14])
        { session.InvalidFrames++; return; }
        int length = U16(data.Slice(8, 2));
        if (length + 19 != data.Length || U32(data.Slice(15 + length, 4)) != Crc32(data.Slice(2, 13 + length)))
        { session.InvalidFrames++; return; }
        var payload = data.Slice(15, length);
        switch (data[3])
        {
            case 0x10: ReadGnss(payload, session, chestUs); break;
            case 0x20:
                if (payload.Length >= 24) { session.TotalImuBatches++; session.TotalImuSamples += payload[2]; ReadImu(payload, session, chestUs); }
                else session.InvalidFrames++;
                break;
        }
    }

    /// <summary>
    /// IMU_SAMPLE (avo_payloads.h): 24-byte header {u8 girth_id, u8 imu_id, u8 count, u8 fmt, u32 girth_seq, u32 girth_t0_us,
    /// u16 period_us, u8 sync_state, u8 reserved, u32 back_rx_ms, i32 girth_to_back_us} followed by count x 18 bytes
    /// (int16 ax ay az gx gy gz mx my mz) when fmt = 0. Values stay in sensor LSB. Sample times use the chest clock of the
    /// record (last sample of the batch) and the nominal period, as in core/raw/RawSession.kt.
    /// </summary>
    private static void ReadImu(ReadOnlySpan<byte> p, TrainingSession session, ulong chestUs)
    {
        int count = p[2], fmt = p[3];
        int period = U16(p.Slice(12, 2));
        if (fmt != 0) { session.ImuOpaqueBatches++; return; }
        if (count == 0 || p.Length < 24 + count * 18 || period is < 1000 or > 100000) { session.InvalidFrames++; return; }
        if (session.ImuPeriodUs == 0) session.ImuPeriodUs = period;
        byte imu = p[1];
        for (int i = 0; i < count; i++)
        {
            var s = p.Slice(24 + i * 18, 18);
            double t = ((double)chestUs - (double)(count - 1 - i) * period) / 1e6;
            session.Imu.Add(new ImuRawSample(imu, t, I16(s), I16(s[2..]), I16(s[4..]), I16(s[6..]), I16(s[8..]), I16(s[10..]), I16(s[12..]), I16(s[14..]), I16(s[16..])));
        }
    }
    private static short I16(ReadOnlySpan<byte> b) => BinaryPrimitives.ReadInt16LittleEndian(b);

    /// <summary>GNSS_SAMPLE v1 (85 bytes, avo_payloads.cpp encode_gnss): compact UBX-NAV-PVT of the vest receiver.</summary>
    private static void ReadGnss(ReadOnlySpan<byte> b, TrainingSession session, ulong chestUs)
    {
        if (b.Length < 85) { session.InvalidFrames++; return; }
        session.GnssSamples++;
        long itow = U32(b.Slice(0, 4));
        int fixType = b[20], flags = b[21], flags3 = U16(b.Slice(22, 2)), numSv = b[24];
        bool fixOk = (flags & 1) != 0, diff = (flags & 2) != 0, invalidLlh = (flags3 & 1) != 0;
        int carrier = (flags >> 6) & 3;
        double hAcc = U32(b.Slice(41, 4)) / 1000.0;
        var solution = GnssQuality.Classify(fixOk, fixType, diff, carrier, invalidLlh);
        session.GnssEpochs.Add(new GnssEpoch(itow, solution, numSv, hAcc, chestUs));
        if (solution == GnssSolution.None)
        { session.UnusableGnssSamples++; return; }
        if (carrier == 2) session.RtkFixCount++;
        else if (carrier == 1) session.RtkFloatCount++;
        else session.GnssOtherCount++;
        double lon = I32(b.Slice(25, 4)) * 1e-7, lat = I32(b.Slice(29, 4)) * 1e-7;
        double speed = I32(b.Slice(61, 4)) / 1000.0;
        if (!double.IsFinite(speed) || speed < 0 || lat is < -90 or > 90 || lon is < -180 or > 180)
        { session.UnusableGnssSamples++; return; }
        DateTimeOffset? utc = null;
        int valid = b[11];
        if ((valid & 3) == 3)
        {
            int year = U16(b.Slice(4, 2)), month = b[6], day = b[7], hour = b[8], minute = b[9], second = b[10];
            int nano = I32(b.Slice(12, 4));
            if (year is >= 2000 and <= 2100 && month is >= 1 and <= 12 && day is >= 1 and <= 31 && hour < 24 && minute < 60 && second < 61)
            {
                try { utc = new DateTimeOffset(year, month, day, hour, minute, Math.Min(second, 59), TimeSpan.Zero).AddTicks(nano / 100); }
                catch (ArgumentOutOfRangeException) { utc = null; }
            }
        }
        double head = I32(b.Slice(65, 4)) * 1e-5;
        session.Track.Add(new TrackPoint(lat, lon, speed, hAcc, carrier, itow, I32(b.Slice(33, 4)) / 1000.0, null,
            fixType, numSv, diff, U32(b.Slice(69, 4)) / 1000.0, I32(b.Slice(49, 4)) / 1000.0, I32(b.Slice(53, 4)) / 1000.0,
            head, I32(b.Slice(37, 4)) / 1000.0, utc, chestUs));
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
