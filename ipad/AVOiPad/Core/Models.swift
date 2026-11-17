import Foundation

/// One usable GNSS epoch of the rider's vest (ZED-F9P NAV-PVT relayed as GNSS_SAMPLE). Position is the rider's
/// antenna, never an anatomical point of the horse. altitudeM keeps the historical meaning (ellipsoid height);
/// mslAltitudeM is the height above mean sea level reported by the receiver.
struct TrackPoint: Equatable {
    var latitude: Double
    var longitude: Double
    var speedMs: Double
    var accuracyM: Double
    var carrierSolution: Int
    var gpsWeekMs: Int64
    var altitudeM: Double = 0
    var elapsedSeconds: Double? = nil
    var fixType: Int = 0
    var numSv: Int = 0
    var diffSoln: Bool = false
    var speedAccMs: Double = .nan
    var velNorthMs: Double = .nan
    var velEastMs: Double = .nan
    var headingDeg: Double = .nan
    var mslAltitudeM: Double = .nan
    var utcTime: Date? = nil
    var chestUs: UInt64 = 0

    init(latitude: Double, longitude: Double, speedMs: Double, accuracyM: Double, carrierSolution: Int, gpsWeekMs: Int64,
         altitudeM: Double = 0, elapsedSeconds: Double? = nil, fixType: Int = 0, numSv: Int = 0, diffSoln: Bool = false,
         speedAccMs: Double = .nan, velNorthMs: Double = .nan, velEastMs: Double = .nan, headingDeg: Double = .nan,
         mslAltitudeM: Double = .nan, utcTime: Date? = nil, chestUs: UInt64 = 0) {
        self.latitude = latitude; self.longitude = longitude; self.speedMs = speedMs; self.accuracyM = accuracyM
        self.carrierSolution = carrierSolution; self.gpsWeekMs = gpsWeekMs; self.altitudeM = altitudeM
        self.elapsedSeconds = elapsedSeconds; self.fixType = fixType; self.numSv = numSv; self.diffSoln = diffSoln
        self.speedAccMs = speedAccMs; self.velNorthMs = velNorthMs; self.velEastMs = velEastMs; self.headingDeg = headingDeg
        self.mslAltitudeM = mslAltitudeM; self.utcTime = utcTime; self.chestUs = chestUs
    }

    static func == (a: TrackPoint, b: TrackPoint) -> Bool {
        a.latitude == b.latitude && a.longitude == b.longitude && a.gpsWeekMs == b.gpsWeekMs && a.chestUs == b.chestUs
    }

    var speedKmh: Double { speedMs * 3.6 }
    var rtkName: String {
        switch carrierSolution { case 2: return "FIX"; case 1: return "FLOAT"; default: return "GNSS" }
    }
    var solution: GnssSolution {
        GnssQuality.classify(gnssFixOk: true, fixType: fixType == 0 ? 3 : fixType, diffSoln: diffSoln,
                             carrierSolution: carrierSolution, invalidLlh: false)
    }
}

/// Every GNSS_SAMPLE received (usable or not): basis for quality timelines and signal-loss intervals.
struct GnssEpoch: Equatable {
    var gpsWeekMs: Int64
    var solution: GnssSolution
    var numSv: Int
    var hAccM: Double
    var chestUs: UInt64
}

/// Raw 9-axis sample of one girth IMU (IMU_SAMPLE fmt 0). Values are sensor LSB, NOT physical units.
struct ImuRawSample: Equatable {
    var imuId: UInt8
    var timeS: Double
    var ax: Int16, ay: Int16, az: Int16
    var gx: Int16, gy: Int16, gz: Int16
    var mx: Int16, my: Int16, mz: Int16
}

/// Fused sample of the BNO085 girth (IMU_SAMPLE fmt 1, GIRTH 0.4.x): linear acceleration (gravity removed)
/// and game rotation vector quaternion, in sensor fixed point (Q8 m/s², Q14). Same times as the fmt 0 batch.
struct ImuFusedSample: Equatable {
    var imuId: UInt8
    var timeS: Double
    var lx: Int16, ly: Int16, lz: Int16
    var qi: Int16, qj: Int16, qk: Int16, qr: Int16
}

struct MarkerEvent: Equatable {
    var chestUs: UInt64
    var source: Int
    var count: UInt32
    var sourceName: String {
        switch source {
        case 0: return "Botón"
        case 1: return "App"
        case 2: return "Desarrollo"
        case 3: return "Alimentación"
        case 4: return "Sistema"
        default: return "Desconocido"
        }
    }
}

struct SegmentSummary: Equatable {
    var name: String
    var index: Int
    var validBytes: Int64
    var blocks: Int
    var records: Int
    var cleanClose: Bool
    var truncated: Bool
    var badRecords: Int
}

final class TrainingSession {
    var sessionId: String = ""
    /// SHA-256 of the concatenated segments declared by the .avo manifest (as verified against the watch), if any.
    var sha256: String?
    var horse: String = "Sin identificar"
    var rider: String = "Sin identificar"
    /// Horse / rider code written in the file (manifest horseCode/riderCode or AVORAW1 header), nil if none.
    var horseCode: String?
    var riderCode: String?
    /// Names exactly as the file carries them (horse/rider may later show the Cuadra/Jinetes name; the file is never changed).
    var horseInFile: String = "Sin identificar"
    var riderInFile: String = "Sin identificar"
    /// What the AVORAW1 header itself says (horse_name / rider_name), whatever the manifest says (AVO-ASSIGN-1 «raw»).
    var rawHorse: String?
    var rawRider: String?
    /// The «asignacion» block of the .avo manifest (AVO-ASSIGN-1), nil if the file has none.
    var fileAssignment: AvoAssignmentData?
    /// Set once the Cuadra/Jinetes names have been applied to horse/rider (in memory only).
    var identityApplied: Bool = false
    var startedAt: Date?
    var sourceName: String = ""
    var integrity: String = "Pendiente"
    var hasRawTelemetry: Bool = false
    var declaredDistanceM: Double?
    var declaredDurationS: Double?
    var declaredMaxSpeedMs: Double?
    var totalImuSamples: Int = 0
    var totalImuBatches: Int = 0
    var invalidFrames: Int = 0
    var markerCount: Int = 0
    var gnssSamples: Int = 0
    var unusableGnssSamples: Int = 0
    var rtkFixCount: Int = 0
    var rtkFloatCount: Int = 0
    var gnssOtherCount: Int = 0
    var track: [TrackPoint] = []
    var gnssEpochs: [GnssEpoch] = []
    /// Decoded girth IMU samples; timeS is chest time in seconds (aligned to GNSS later by the timeline).
    var imu: [ImuRawSample] = []
    var imuPeriodUs: Int = 0
    var imuOpaqueBatches: Int = 0
    /// Units declared by the girth in the IMU header (byte 15): 0 = not declared (nominal scale of the REV B
    /// LSM6), 1 = BNO085 fixed point (GIRTH 0.4.3+: acc Q8 m/s², gyro Q9 rad/s, mag Q4 µT, quaternion Q14).
    var imuUnits: UInt8 = 0
    var imuFused: [ImuFusedSample] = []
    var imuFusedBatches: Int = 0
    var markers: [MarkerEvent] = []
    var segments: [SegmentSummary] = []
    /// SHA-256 of the imported file as received (duplicate detection). Not the watch canonical hash.
    var fileSha256: String?
    var sourcePath: String?
    /// Canonical hash declared by the watch in manifest.json (sha256 over the segments); informative only.
    var declaredCanonicalSha256: String?
    var discipline: String = ""
    /// RAW segment files on disk for the analysis engine (the .avr itself, or verified copies extracted from a .avo package).
    var rawSegmentPaths: [String] = []
    var marineSource: String?
    var marineKind: String?
    var marineObservedAt: Date?
    var tideHeightM: Double?
    var windKmh: Double?
    var waveHeightM: Double?
    var marineNotes: String?

    init() {}

    /// Synthetic/demonstration data: never to be presented as a measured training.
    var isSynthetic: Bool {
        let u = sessionId.uppercased()
        return u.hasPrefix("SINTETICA") || u.hasPrefix("DEMO")
    }

    var distanceM: Double {
        guard track.count > 1 else { return declaredDistanceM ?? 0 }
        var sum = 0.0
        for i in 1..<track.count {
            let d = Geo.haversineM(track[i - 1], track[i])
            if d < 250 { sum += d }
        }
        return sum
    }
    var maxSpeedKmh: Double {
        track.isEmpty ? (declaredMaxSpeedMs ?? 0) * 3.6 : (track.map { $0.speedKmh }.max() ?? 0)
    }
    var durationSeconds: Double {
        if track.count >= 2 {
            let sec = (track[track.count - 1].elapsedSeconds ?? 0) - (track[0].elapsedSeconds ?? 0)
            if sec > 0 { return sec }
            var ms = track[track.count - 1].gpsWeekMs - track[0].gpsWeekMs
            if ms < 0 { ms += 604_800_000 }
            if ms > 0 { return Double(ms) / 1000.0 }
        }
        return declaredDurationS ?? 0
    }
    var meanSpeedKmh: Double { durationSeconds > 0 ? distanceM / durationSeconds * 3.6 : 0 }
    var fixPercent: Double { gnssSamples > 0 ? 100.0 * Double(rtkFixCount) / Double(gnssSamples) : 0 }
    var dateText: String { AvoTime.text(startedAt) }
    var summary: String { "\(horse) · \(dateText) · \(AvoFormat.f(distanceM / 1000, 2)) km" }
}

enum Geo {
    static func haversineM(_ a: TrackPoint, _ b: TrackPoint) -> Double {
        haversineM(a.latitude, a.longitude, b.latitude, b.longitude)
    }
    static func haversineM(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let radius = 6371008.8
        let r = Double.pi / 180
        let dl = (lat2 - lat1) * r, dn = (lon2 - lon1) * r
        let h = pow(sin(dl / 2), 2) + cos(lat1 * r) * cos(lat2 * r) * pow(sin(dn / 2), 2)
        return 2 * radius * atan2(sqrt(h), sqrt(max(0, 1 - h)))
    }
}

struct SpeedSection: Equatable {
    var index: Int
    var startIndex: Int
    var endIndex: Int
    var distanceM: Double
    var durationS: Double
    var averageSpeedKmh: Double
    var maximumSpeedKmh: Double
    var name: String
}

enum Analytics {
    static func sections(_ session: TrainingSession, lengthM: Double = 500) -> [SpeedSection] {
        let track = session.track
        guard track.count >= 2 else { return [] }
        var result: [SpeedSection] = []
        var start = 0, index = 1
        var distance = 0.0
        for i in 1..<track.count {
            let step = Geo.haversineM(track[i - 1], track[i])
            if step > 250 { start = i; distance = 0; continue }
            distance += step
            if distance >= lengthM || i == track.count - 1 {
                var ms = track[i].gpsWeekMs - track[start].gpsWeekMs
                if ms < 0 { ms += 604_800_000 }
                let duration = Double(ms) / 1000.0
                let maxKmh = track[start...i].map { $0.speedKmh }.max() ?? 0
                result.append(SpeedSection(index: index, startIndex: start, endIndex: i, distanceM: distance, durationS: duration,
                                           averageSpeedKmh: duration > 0 ? distance / duration * 3.6 : 0,
                                           maximumSpeedKmh: maxKmh, name: "Tramo \(index)"))
                index += 1
                start = i
                distance = 0
            }
        }
        return result
    }
    static func duration(_ seconds: Double) -> String { AvoTime.hms(seconds) }
}
