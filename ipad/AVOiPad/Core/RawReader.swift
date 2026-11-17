import Foundation

/// Reader of AVORAW1 (.avr), ported from core/raw/RawSession.kt (via the Windows RawReader.cs).
/// Rejects invalid CRCs and torn blocks.
enum RawReader {
    private static let headerSize = 512
    private static let blockHeaderSize = 36
    private static let recordHeaderSize = 12
    private static let maxPayload = 65_536

    private static func u16(_ b: [UInt8], _ o: Int) -> Int { Int(BinaryReaderLE.u16(b, o)) }
    private static func u32(_ b: [UInt8], _ o: Int) -> UInt32 { BinaryReaderLE.u32(b, o) }
    private static func i32(_ b: [UInt8], _ o: Int) -> Int32 { BinaryReaderLE.i32(b, o) }
    private static func i16(_ b: [UInt8], _ o: Int) -> Int16 { BinaryReaderLE.i16(b, o) }
    private static func u64(_ b: [UInt8], _ o: Int) -> UInt64 { BinaryReaderLE.u64(b, o) }
    private static func crc32(_ b: [UInt8], _ o: Int, _ n: Int) -> UInt32 { ZipCRC32.compute(b, o, n) }

    private static func crc8(_ b: [UInt8], _ o: Int, _ n: Int) -> UInt8 {
        var crc: UInt8 = 0
        for k in o..<(o + n) {
            crc ^= b[k]
            for _ in 0..<8 { crc = (crc & 0x80) != 0 ? (crc << 1) ^ 0x07 : crc << 1 }
        }
        return crc
    }

    /// UTF-8 text up to the first NUL.
    private static func str(_ b: [UInt8], _ o: Int, _ n: Int) -> String {
        var end = o + n
        for k in o..<(o + n) where b[k] == 0 { end = k; break }
        return String(decoding: b[o..<end], as: UTF8.self)
    }

    private static func isBlank(_ s: String?) -> Bool {
        guard let s = s else { return true }
        return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func scan(_ data: Data, session: TrainingSession, name: String, segmentIndex: Int) throws -> SegmentSummary {
        try scan([UInt8](data), session: session, name: name, segmentIndex: segmentIndex)
    }

    /// Scans one RAW segment (the whole file content) and fills `session`.
    static func scan(_ bytes: [UInt8], session: TrainingSession, name: String, segmentIndex: Int) throws -> SegmentSummary {
        let b = bytes
        if b.count < headerSize { throw AvoError.invalidData("Cabecera AVORAW1 incompleta") }
        let magic: [UInt8] = [0x41, 0x56, 0x4F, 0x52, 0x41, 0x57, 0x31, 0x00]   // "AVORAW1\0"
        if Array(b[0..<8]) != magic || u32(b, 508) != crc32(b, 0, 508) {
            throw AvoError.invalidData("Cabecera AVORAW1 o CRC-32 incorrectos")
        }
        if u16(b, 8) < 1 || u16(b, 10) != headerSize { throw AvoError.invalidData("Versión AVORAW no compatible") }
        let id = str(b, 12, 24)
        if isBlank(session.sessionId) { session.sessionId = id }
        else if id != session.sessionId { throw AvoError.invalidData("Los segmentos pertenecen a sesiones diferentes") }
        if session.startedAt == nil {
            let rtc = Int64(bitPattern: u64(b, 40))
            if rtc > 946_684_800_000 && rtc < 4_102_444_800_000 { session.startedAt = AvoTime.fromUnixMs(Double(rtc)) }
        }
        let horse = str(b, 124, 24)
        let rider = str(b, 152, 24)
        if !isBlank(horse) && session.rawHorse == nil { session.rawHorse = horse.trimmingCharacters(in: .whitespacesAndNewlines) }
        if !isBlank(rider) && session.rawRider == nil { session.rawRider = rider.trimmingCharacters(in: .whitespacesAndNewlines) }
        if !isBlank(horse) && session.horse == "Sin identificar" { session.horse = horse }
        if !isBlank(rider) && session.rider == "Sin identificar" { session.rider = rider }
        // the AVORAW1 header carries the code written to the watch (e.g. HORSE_001)
        if !isBlank(horse) && isBlank(session.horseCode) { session.horseCode = horse.trimmingCharacters(in: .whitespacesAndNewlines) }
        if !isBlank(rider) && isBlank(session.riderCode) { session.riderCode = rider.trimmingCharacters(in: .whitespacesAndNewlines) }

        var validBytes = Int64(headerSize)
        var blocks = 0, records = 0, bad = 0
        var clean = false, torn = false
        var pos = headerSize
        while true {
            let read = Swift.min(blockHeaderSize, b.count - pos)
            if read == 0 { break }
            if read != blockHeaderSize { torn = true; break }
            let bh = pos
            pos += blockHeaderSize
            let declared = u32(b, bh + 8)
            let length = declared > UInt32(Int32.max) ? Int(Int32.max) : Int(declared)
            if u32(b, bh) != 0x424F_5641 || u32(b, bh + 32) != crc32(b, bh, 32) || length > maxPayload { torn = true; break }
            if b.count - pos < length { torn = true; break }
            let p = pos
            pos += length
            if u32(b, bh + 28) != crc32(b, p, length) { torn = true; break }
            let recordCount = u16(b, bh + 12)
            let flags = u16(b, bh + 14)
            var offset = 0, parsed = 0
            while parsed < recordCount && offset + recordHeaderSize <= length {
                let type = b[p + offset]
                let dataLength = u16(b, p + offset + 2)
                if offset + recordHeaderSize + dataLength > length { bad += recordCount - parsed; break }
                let dataStart = p + offset + recordHeaderSize
                let chestUs = u64(b, p + offset + 4)
                if type == 0x05 {
                    session.markerCount += 1
                    // MARKER: u8 source, u32 marker_count (chest controller.cpp); older writers may differ -> keep time only.
                    if dataLength >= 5 {
                        session.markers.append(MarkerEvent(chestUs: chestUs, source: Int(b[dataStart]), count: u32(b, dataStart + 1)))
                    } else {
                        session.markers.append(MarkerEvent(chestUs: chestUs, source: -1, count: 0))
                    }
                }
                if type == 0x01 { readUart(b, dataStart, dataLength, session, chestUs) }
                offset += recordHeaderSize + dataLength
                parsed += 1
            }
            if parsed < recordCount && bad == 0 { bad += recordCount - parsed }
            validBytes += Int64(blockHeaderSize + length)
            blocks += 1
            records += parsed
            if (flags & 2) != 0 { clean = true }
        }
        return SegmentSummary(name: name, index: segmentIndex, validBytes: validBytes, blocks: blocks, records: records,
                              cleanClose: clean, truncated: torn, badRecords: bad)
    }

    private static func readUart(_ b: [UInt8], _ o: Int, _ n: Int, _ session: TrainingSession, _ chestUs: UInt64) {
        if n < 19 || b[o] != 0xA5 || b[o + 1] != 0x5A || crc8(b, o + 2, 12) != b[o + 14] {
            session.invalidFrames += 1; return
        }
        let length = u16(b, o + 8)
        if length + 19 != n || u32(b, o + 15 + length) != crc32(b, o + 2, 13 + length) {
            session.invalidFrames += 1; return
        }
        let p = o + 15
        switch b[o + 3] {
        case 0x10:
            readGnss(b, p, length, session, chestUs)
        case 0x20:
            if length >= 24 {
                session.totalImuBatches += 1
                session.totalImuSamples += Int(b[p + 2])
                readImu(b, p, length, session, chestUs)
            } else {
                session.invalidFrames += 1
            }
        default:
            break
        }
    }

    /// IMU_SAMPLE (avo_payloads.h): 24-byte header {u8 girth_id, u8 imu_id, u8 count, u8 fmt, u32 girth_seq, u32 girth_t0_us,
    /// u16 period_us, u8 sync_state, u8 reserved, u32 back_rx_ms, i32 girth_to_back_us} followed by count x 18 bytes
    /// (int16 ax ay az gx gy gz mx my mz) when fmt = 0. Values stay in sensor LSB. Sample times use the chest clock of the
    /// record (last sample of the batch) and the nominal period, as in core/raw/RawSession.kt.
    private static func readImu(_ b: [UInt8], _ p: Int, _ n: Int, _ session: TrainingSession, _ chestUs: UInt64) {
        let count = Int(b[p + 2]), fmt = Int(b[p + 3])
        let period = u16(b, p + 12)
        if fmt == 1 {
            // GIRTH 0.4.x: linear acceleration + quaternion, 14 bytes per sample
            if count == 0 || n < 24 + count * 14 || period < 1000 || period > 100_000 { session.invalidFrames += 1; return }
            session.imuFusedBatches += 1
            let imuId = b[p + 1]
            for i in 0..<count {
                let f = p + 24 + i * 14
                let tf = (Double(chestUs) - Double(count - 1 - i) * Double(period)) / 1e6
                session.imuFused.append(ImuFusedSample(imuId: imuId, timeS: tf,
                                                       lx: i16(b, f), ly: i16(b, f + 2), lz: i16(b, f + 4),
                                                       qi: i16(b, f + 6), qj: i16(b, f + 8), qk: i16(b, f + 10), qr: i16(b, f + 12)))
            }
            return
        }
        if fmt != 0 { session.imuOpaqueBatches += 1; return }
        if count == 0 || n < 24 + count * 18 || period < 1000 || period > 100_000 { session.invalidFrames += 1; return }
        if session.imuPeriodUs == 0 { session.imuPeriodUs = period }
        if b[p + 15] == 1 { session.imuUnits = 1 }   // units declared by the girth (GIRTH 0.4.3+: BNO085 fixed point)
        let imu = b[p + 1]
        for i in 0..<count {
            let s = p + 24 + i * 18
            let t = (Double(chestUs) - Double(count - 1 - i) * Double(period)) / 1e6
            session.imu.append(ImuRawSample(imuId: imu, timeS: t,
                                            ax: i16(b, s), ay: i16(b, s + 2), az: i16(b, s + 4),
                                            gx: i16(b, s + 6), gy: i16(b, s + 8), gz: i16(b, s + 10),
                                            mx: i16(b, s + 12), my: i16(b, s + 14), mz: i16(b, s + 16)))
        }
    }

    /// GNSS_SAMPLE v1 (85 bytes, avo_payloads.cpp encode_gnss): compact UBX-NAV-PVT of the vest receiver.
    private static func readGnss(_ b: [UInt8], _ o: Int, _ n: Int, _ session: TrainingSession, _ chestUs: UInt64) {
        if n < 85 { session.invalidFrames += 1; return }
        session.gnssSamples += 1
        let itow = Int64(u32(b, o))
        let fixType = Int(b[o + 20]), flags = Int(b[o + 21]), flags3 = u16(b, o + 22), numSv = Int(b[o + 24])
        let fixOk = (flags & 1) != 0, diff = (flags & 2) != 0, invalidLlh = (flags3 & 1) != 0
        let carrier = (flags >> 6) & 3
        let hAcc = Double(u32(b, o + 41)) / 1000.0
        let solution = GnssQuality.classify(gnssFixOk: fixOk, fixType: fixType, diffSoln: diff, carrierSolution: carrier, invalidLlh: invalidLlh)
        session.gnssEpochs.append(GnssEpoch(gpsWeekMs: itow, solution: solution, numSv: numSv, hAccM: hAcc, chestUs: chestUs))
        if solution == .none { session.unusableGnssSamples += 1; return }
        if carrier == 2 { session.rtkFixCount += 1 }
        else if carrier == 1 { session.rtkFloatCount += 1 }
        else { session.gnssOtherCount += 1 }
        let lon = Double(i32(b, o + 25)) * 1e-7, lat = Double(i32(b, o + 29)) * 1e-7
        let speed = Double(i32(b, o + 61)) / 1000.0
        if !speed.isFinite || speed < 0 || lat < -90 || lat > 90 || lon < -180 || lon > 180 {
            session.unusableGnssSamples += 1; return
        }
        var utc: Date? = nil
        let valid = Int(b[o + 11])
        if (valid & 3) == 3 {
            let year = u16(b, o + 4), month = Int(b[o + 6]), day = Int(b[o + 7])
            let hour = Int(b[o + 8]), minute = Int(b[o + 9]), second = Int(b[o + 10])
            let nano = Int(i32(b, o + 12))
            if year >= 2000 && year <= 2100 && month >= 1 && month <= 12 && day >= 1 && day <= 31 && hour < 24 && minute < 60 && second < 61 {
                utc = utcDate(year, month, day, hour, minute, Swift.min(second, 59), ticks: nano / 100)
            }
        }
        let head = Double(i32(b, o + 65)) * 1e-5
        session.track.append(TrackPoint(latitude: lat, longitude: lon, speedMs: speed, accuracyM: hAcc, carrierSolution: carrier,
                                        gpsWeekMs: itow, altitudeM: Double(i32(b, o + 33)) / 1000.0, elapsedSeconds: nil,
                                        fixType: fixType, numSv: numSv, diffSoln: diff,
                                        speedAccMs: Double(u32(b, o + 69)) / 1000.0,
                                        velNorthMs: Double(i32(b, o + 49)) / 1000.0, velEastMs: Double(i32(b, o + 53)) / 1000.0,
                                        headingDeg: head, mslAltitudeM: Double(i32(b, o + 37)) / 1000.0, utcTime: utc, chestUs: chestUs))
    }

    /// UTC instant of a civil date, nil if the date does not exist (C# DateTimeOffset constructor would throw).
    /// `ticks` are 100 ns units added afterwards (C# AddTicks).
    private static func utcDate(_ y: Int, _ m: Int, _ d: Int, _ hh: Int, _ mm: Int, _ ss: Int, ticks: Int) -> Date? {
        let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
        let dim: [Int] = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        if d > dim[m - 1] { return nil }
        // days from civil (H. Hinnant)
        let yy = m <= 2 ? y - 1 : y
        let era = (yy >= 0 ? yy : yy - 399) / 400
        let yoe = yy - era * 400
        let mp = (m + 9) % 12
        let doy = (153 * mp + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        let days = era * 146_097 + doe - 719_468
        let seconds = Double(days) * 86_400 + Double(hh * 3600 + mm * 60 + ss)
        return Date(timeIntervalSince1970: seconds + Double(ticks) * 1e-7)
    }
}
