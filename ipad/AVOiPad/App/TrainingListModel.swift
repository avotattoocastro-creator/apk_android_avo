import SwiftUI
import Observation

// «Listado de entrenamientos»: dense table of every training loaded on the iPad with filters (caballo, jinete, fechas,
// geocerca visitada, modalidad, cincha, favoritos, DEMO) and «Buscar entrenamientos perdidos», which looks through every
// folder of the app container (Documents = «En mi iPad / AVO Horse» in Files, Inbox, tmp, Caches, the app root with the
// library, the RAW cache and the watch download folders) for .avo/.avr files and P00n.avr segment folders that are not
// loaded, and imports them with app.importFiles. Pure parts (fence matching, filter, scan) are static and unit-tested.

// MARK: - Geofence matching (pure)

/// A defined geofence of geocercas.json, copied as plain values so it can be used off the main thread.
struct TrainingListFence: Equatable {
    var slot: Int
    var name: String
    var isCircle: Bool
    var centerLat: Double = 0
    var centerLon: Double = 0
    var radiusM: Double = 0
    var vLat: [Double] = []
    var vLon: [Double] = []

    /// Bounding box (degrees) used to skip far points quickly.
    var box: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        if isCircle {
            let dLat: Double = radiusM / 111_000.0 * 1.01
            let c: Double = max(0.01, cos(centerLat * Double.pi / 180))
            let dLon: Double = radiusM / (111_000.0 * c) * 1.01
            return (centerLat - dLat, centerLat + dLat, centerLon - dLon, centerLon + dLon)
        }
        return (vLat.min() ?? 0, vLat.max() ?? 0, vLon.min() ?? 0, vLon.max() ?? 0)
    }

    func contains(lat: Double, lon: Double) -> Bool {
        if !lat.isFinite || !lon.isFinite { return false }
        if isCircle { return Geo.haversineM(centerLat, centerLon, lat, lon) <= radiusM }
        return TrainingListGeo.pointInPolygon(lat: lat, lon: lon, vLat: vLat, vLon: vLon)
    }
}

enum TrainingListGeo {
    /// The defined fences of the plan (circle with centre and radius > 0, polygon with at least 3 vertices), active or not.
    static func snapshot(_ plan: GeofencePlan) -> [TrainingListFence] {
        var out: [TrainingListFence] = []
        for i in 0..<plan.fences.count {
            guard let f = plan.fences[i] else { continue }
            let name: String = f.name.trimmed.isEmpty ? "Geocerca \(i + 1)" : f.name.trimmed
            if f.type == .circle {
                guard let c = f.center, f.radiusM.isFinite, f.radiusM > 0 else { continue }
                out.append(TrainingListFence(slot: i, name: name, isCircle: true, centerLat: c.lat, centerLon: c.lon, radiusM: f.radiusM))
            } else if f.type == .polygon {
                if f.vertices.count < 3 { continue }
                out.append(TrainingListFence(slot: i, name: name, isCircle: false,
                                             vLat: f.vertices.map { $0.lat }, vLon: f.vertices.map { $0.lon }))
            }
        }
        return out
    }

    /// Ray casting (x = longitude, y = latitude). Points exactly on an edge may fall on either side.
    static func pointInPolygon(lat: Double, lon: Double, vLat: [Double], vLon: [Double]) -> Bool {
        let n: Int = min(vLat.count, vLon.count)
        if n < 3 { return false }
        var inside: Bool = false
        var j: Int = n - 1
        for i in 0..<n {
            let yi: Double = vLat[i], yj: Double = vLat[j]
            let xi: Double = vLon[i], xj: Double = vLon[j]
            if (yi > lat) != (yj > lat) {
                let x: Double = (xj - xi) * (lat - yi) / (yj - yi) + xi
                if lon < x { inside = !inside }
            }
            j = i
        }
        return inside
    }

    /// Slots of the fences that contain at least one point of the track (ascending).
    static func visited(lat: [Double], lon: [Double], fences: [TrainingListFence]) -> [Int] {
        let n: Int = min(lat.count, lon.count)
        var out: [Int] = []
        for f in fences {
            let b = f.box
            var hit: Bool = false
            var i: Int = 0
            while i < n && !hit {
                let la: Double = lat[i], lo: Double = lon[i]
                if la.isFinite && lo.isFinite && !(la == 0 && lo == 0)
                    && la >= b.minLat && la <= b.maxLat && lo >= b.minLon && lo <= b.maxLon && f.contains(lat: la, lon: lo) {
                    hit = true
                }
                i += 1
            }
            if hit { out.append(f.slot) }
        }
        return out.sorted()
    }

    /// Changes whenever a fence changes (the cache is rebuilt).
    static func signature(_ fences: [TrainingListFence]) -> String {
        fences.map { (f: TrainingListFence) -> String in
            let pts: String = zip(f.vLat, f.vLon).map { "\($0.0),\($0.1)" }.joined(separator: ";")
            return "\(f.slot)|\(f.isCircle)|\(f.centerLat)|\(f.centerLon)|\(f.radiusM)|\(pts)"
        }.joined(separator: "#")
    }
}

// MARK: - Rows and filter (pure)

/// One line of the table (values copied from SessionItem; every column is sortable).
struct TrainingListRow: Identifiable, Equatable {
    var id: String
    var start: Date?
    var startKey: Double
    var dateTimeText: String
    var horse: String
    var rider: String
    var discipline: String
    var durationS: Double
    var durationText: String
    var distanceKm: Double
    var distanceText: String
    var maxSpeedKmh: Double
    var maxSpeedText: String
    var hasGirth: Bool
    var girthText: String
    /// nil while the fences of this training are being calculated.
    var fenceSlots: [Int]?
    var fencesText: String
    var origin: String
    var engineState: String
    var isFavorite: Bool
    var favKey: Int
    var isSynthetic: Bool
    /// Extra searchable text (id, codes, kind).
    var searchExtra: String
}

/// Filters of the page (persisted in UserDefaults as JSON).
struct TrainingListFilter: Codable, Equatable {
    var search: String = ""
    var horse: String = ""
    var rider: String = ""
    var from: Date? = nil
    var to: Date? = nil
    var fence: Int = -1
    var discipline: String = ""
    var onlyGirth: Bool = false
    var onlyFavorites: Bool = false
    var hideDemo: Bool = false

    var isEmpty: Bool { self == TrainingListFilter() }

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = AvoTime.madrid
        return c
    }

    /// from = start of that day (inclusive), to = end of that day (inclusive), Europe/Madrid days.
    func matches(_ r: TrainingListRow, calendar: Calendar = TrainingListFilter.calendar) -> Bool {
        if onlyFavorites && !r.isFavorite { return false }
        if onlyGirth && !r.hasGirth { return false }
        if hideDemo && r.isSynthetic { return false }
        if !horse.isEmpty && r.horse.caseInsensitiveCompare(horse) != .orderedSame { return false }
        if !rider.isEmpty && r.rider.caseInsensitiveCompare(rider) != .orderedSame { return false }
        if !discipline.isEmpty && r.discipline.caseInsensitiveCompare(discipline) != .orderedSame { return false }
        if fence >= 0 {
            guard let slots = r.fenceSlots, slots.contains(fence) else { return false }
        }
        if from != nil || to != nil {
            guard let d = r.start else { return false }
            if let f = from, d < calendar.startOfDay(for: f) { return false }
            if let t = to, let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: t)), d >= end { return false }
        }
        let q: String = search.trimmed
        if !q.isEmpty {
            let fields: [String] = [r.horse, r.rider, r.discipline, r.dateTimeText, r.fencesText, r.origin, r.id, r.searchExtra]
            if !fields.contains(where: { $0.localizedCaseInsensitiveContains(q) }) { return false }
        }
        return true
    }

    /// «N entrenamientos · X km · HH:MM total».
    static func summary(_ rows: [TrainingListRow]) -> String {
        var km: Double = 0
        var secs: Double = 0
        for r in rows {
            if r.distanceKm.isFinite { km += r.distanceKm }
            if r.durationS.isFinite { secs += max(0, r.durationS) }
        }
        let mins: Int = Int(secs / 60)
        let n: String = rows.count == 1 ? "1 entrenamiento" : "\(rows.count) entrenamientos"
        return "\(n) · \(DotNetFormat.custom(km, "0.0", spanish: true)) km · " + String(format: "%02d:%02d", mins / 60, mins % 60) + " total"
    }
}

// MARK: - Recovery of lost trainings (pure, runs off the main thread)

enum TrainingRecoveryStatus: Int {
    case pending = 0, recovered, duplicate, incomplete, damaged
    var title: String {
        switch self {
        case .pending: return "Pendiente"
        case .recovered: return "Recuperado"
        case .duplicate: return "Duplicado"
        case .incomplete: return "Incompleto"
        case .damaged: return "Dañado"
        }
    }
}

struct TrainingRecoveryItem: Identifiable {
    let id: UUID = UUID()
    var name: String
    var path: String
    var status: TrainingRecoveryStatus
    var reason: String
    /// File handed to app.importFiles (the file itself, a copy in «entrada» or the .avo packed from a segment folder).
    var importPath: String? = nil
    /// Temporary copy to delete after the import.
    var tempCopy: String? = nil
}

/// What a recursive scan found.
struct TrainingRecoveryScan {
    var files: [String] = []
    var segmentDirs: [String] = []
    var partials: [String] = []
    var scanned: Int = 0
    var limited: Bool = false
}

/// What is already loaded (never imported again).
struct TrainingRecoveryKnown {
    var shas: Set<String> = []
    var sessionIds: Set<String> = []
    /// Canonical paths of files already used by loaded trainings (library copies, RAW cache, sources).
    var paths: Set<String> = []
}

struct TrainingRecoveryReport {
    var scanned: Int = 0
    var limited: Bool = false
    var items: [TrainingRecoveryItem] = []
    var folder: String = ""

    func count(_ s: TrainingRecoveryStatus) -> Int { items.filter { $0.status == s }.count }
    var summary: String {
        let bad: Int = count(.incomplete) + count(.damaged)
        return "\(scanned) archivos revisados · \(count(.recovered)) recuperados · \(count(.duplicate)) duplicados · \(bad) incompletos/dañados"
    }
}

enum TrainingRecovery {
    static let segmentPattern: String = "^P[0-9]{3}\\.avr$"
    /// Folders of the app root that never hold trainings (map tiles, weather cache, logs, engine cache).
    static let skippedDirNames: Set<String> = ["teselas", "entorno", "registros", "analisis", "tramos", "notas", ".Trash"]

    static func canonical(_ p: String) -> String {
        URL(fileURLWithPath: p).resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// Every folder of the app container where a training can be.
    static func containerRoots(appRoot: String) -> [String] {
        let fm = FileManager.default
        var r: [String] = []
        if let d = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            r.append(d.path)
            r.append(d.appendingPathComponent("Inbox", isDirectory: true).path)
        }
        r.append(NSTemporaryDirectory())
        if let c = fm.urls(for: .cachesDirectory, in: .userDomainMask).first { r.append(c.path) }
        r.append(appRoot)
        if let a = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first { r.append(a.path) }
        return r
    }

    /// Recursive scan (depth 0 = the root itself). Folders with P00n.avr are reported as segment folders (their P00n files
    /// are not listed one by one). Stops after `maxFiles` files.
    static func collect(_ roots: [String], maxDepth: Int, maxFiles: Int,
                        skipDirNames: Set<String> = TrainingRecovery.skippedDirNames) -> TrainingRecoveryScan {
        let fm = FileManager.default
        var out = TrainingRecoveryScan()
        var visited: Set<String> = []

        func walk(_ dir: String, _ depth: Int) {
            if out.limited { return }
            let key: String = canonical(dir)
            if visited.contains(key) { return }
            visited.insert(key)
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return }
            var subdirs: [String] = []
            var hasSegments: Bool = false
            for name in names.sorted() {
                let p: String = AvoFiles.join(dir, name)
                var isDir: ObjCBool = false
                if !fm.fileExists(atPath: p, isDirectory: &isDir) { continue }
                if isDir.boolValue {
                    if !skipDirNames.contains(name) && !name.hasSuffix(".app") { subdirs.append(p) }
                    continue
                }
                if out.scanned >= maxFiles { out.limited = true; return }
                out.scanned += 1
                let lower: String = name.lowercased()
                if name.matches(segmentPattern) {
                    hasSegments = true
                } else if lower.hasSuffix(".avo") || lower.hasSuffix(".avr") {
                    out.files.append(p)
                } else if lower.hasSuffix(".avo.tmp") || lower.hasSuffix(".avr.tmp") || lower.hasSuffix(".part") {
                    out.partials.append(p)
                }
            }
            if hasSegments { out.segmentDirs.append(dir) }
            if depth < maxDepth {
                for s in subdirs { walk(s, depth + 1) }
            }
        }

        for r in roots {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: r, isDirectory: &isDir), isDir.boolValue { walk(r, 0) }
        }
        return out
    }

    /// AVORAW1 header: session id and start (RTC ms), nil if it is not a RAW segment.
    static func rawHeader(_ path: String) -> (id: String, rtcMs: Int64)? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        guard let d = try? h.read(upToCount: 512), d.count == 512 else { return nil }
        let b: [UInt8] = [UInt8](d)
        let magic: [UInt8] = [0x41, 0x56, 0x4F, 0x52, 0x41, 0x57, 0x31, 0x00]
        if Array(b[0..<8]) != magic { return nil }
        var end: Int = 36
        for k in 12..<36 where b[k] == 0 { end = k; break }
        let id: String = String(decoding: b[12..<end], as: UTF8.self).trimmed
        if id.isEmpty { return nil }
        let rtc: Int64 = BinaryReaderLE.i64(b, 40)
        return (id, rtc)
    }

    /// manifest.json of a .avo package, nil if it is not a valid ZIP with a manifest.
    static func avoManifest(_ path: String) -> [String: Any]? {
        guard let zip = try? ZipReader(path: path), let e = zip.entry("manifest.json"), e.length > 0, e.length <= 16_384,
              var bytes = try? zip.read(e, max: 16_384) else { return nil }
        if bytes.count >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF { bytes.removeFirst(3) }
        return AvoJSON.object(Data(bytes))
    }

    /// Classifies what the scan found. Complete segment folders are packed as .avo into `packDir` (like the watch
    /// download); when `copyInbox` is given, importable files are copied there first (folders outside the app).
    static func evaluate(_ scan: TrainingRecoveryScan, known: TrainingRecoveryKnown, packDir: String,
                         copyInbox: String? = nil) -> [TrainingRecoveryItem] {
        var items: [TrainingRecoveryItem] = []
        var seenShas: Set<String> = []
        var seenIds: Set<String> = []
        let maxBytes: Int64 = 100 * 1024 * 1024

        for p in scan.files {
            let name: String = AvoFiles.fileName(p)
            func add(_ s: TrainingRecoveryStatus, _ reason: String) {
                items.append(TrainingRecoveryItem(name: name, path: p, status: s, reason: reason))
            }
            if known.paths.contains(canonical(p)) { add(.duplicate, "Ya es parte de un entrenamiento cargado"); continue }
            let size: Int64 = AvoFiles.size(p)
            if size <= 0 { add(.damaged, "Archivo vacío o ilegible"); continue }
            if size > maxBytes { add(.damaged, "Archivo de más de 100 MB"); continue }
            guard let sha = try? TrainingLibrary.fileSha256(p) else { add(.damaged, "No se puede leer el archivo"); continue }
            if known.shas.contains(sha) { add(.duplicate, "Mismo SHA-256 que un entrenamiento ya cargado"); continue }
            if seenShas.contains(sha) { add(.duplicate, "Copia repetida de otro archivo encontrado"); continue }
            seenShas.insert(sha)
            var id: String = ""
            if AvoFiles.ext(p) == ".avr" {
                guard let h = rawHeader(p) else { add(.damaged, "Cabecera AVORAW1 no válida"); continue }
                id = h.id
            } else {
                guard let m = avoManifest(p) else { add(.damaged, "Paquete .avo no válido (ZIP o manifest.json)"); continue }
                id = AvoJSON.string(m, "sessionId") ?? ""
                if id.isEmpty { add(.damaged, "El manifiesto no tiene sessionId"); continue }
            }
            if known.sessionIds.contains(id) { add(.duplicate, "La sesión \(id) ya está cargada"); continue }
            if seenIds.contains(id) { add(.duplicate, "Otro archivo de la sesión \(id) ya se recupera"); continue }
            seenIds.insert(id)
            var item = TrainingRecoveryItem(name: name, path: p, status: .pending, reason: "Sesión \(id)", importPath: p)
            if let inbox = copyInbox {
                let r: (path: String?, error: String?) = AppModel.copyIn(URL(fileURLWithPath: p), inbox: inbox)
                guard let copy = r.path else {
                    add(.damaged, "No se pudo copiar: " + (r.error ?? "error de lectura"))
                    continue
                }
                item.importPath = copy
                item.tempCopy = copy
            }
            items.append(item)
        }

        for dir in scan.segmentDirs {
            let name: String = AvoFiles.fileName(dir) + "/"
            func add(_ s: TrainingRecoveryStatus, _ reason: String) {
                items.append(TrainingRecoveryItem(name: name, path: dir, status: s, reason: reason))
            }
            let segs: [String] = WifiDownloader.segFiles(dir)
            if segs.isEmpty { continue }
            if AvoFiles.exists(AvoFiles.join(dir, ".wifi_etag")) || AvoFiles.exists(AvoFiles.join(dir, BleSessionDownloader.sizesFile)) {
                add(.incomplete, "Descarga del reloj sin terminar (\(segs.count) segmento(s)): se reanuda desde «Reloj Wi-Fi»")
                continue
            }
            var gap: String? = nil
            for (k, s) in segs.enumerated() where AvoFiles.fileName(s) != String(format: "P%03d.avr", k + 1) {
                gap = String(format: "P%03d.avr", k + 1)
                break
            }
            if let g = gap { add(.incomplete, "Falta el segmento \(g)"); continue }
            var id: String = ""
            var rtc: Int64 = 0
            var problem: String? = nil
            for s in segs {
                guard let h = rawHeader(s) else { problem = "Cabecera AVORAW1 no válida en \(AvoFiles.fileName(s))"; break }
                if id.isEmpty { id = h.id; rtc = h.rtcMs } else if h.id != id { problem = "Los segmentos son de sesiones distintas"; break }
            }
            if let pr = problem { add(.damaged, pr); continue }
            if known.sessionIds.contains(id) { add(.duplicate, "La sesión \(id) ya está cargada"); continue }
            if seenIds.contains(id) { add(.duplicate, "Otro archivo de la sesión \(id) ya se recupera"); continue }
            guard let sha = try? WifiDownloader.sha256(dir) else { add(.damaged, "No se pueden leer los segmentos"); continue }
            if known.shas.contains(sha) || seenShas.contains(sha) { add(.duplicate, "Mismo SHA-256 que un entrenamiento ya cargado"); continue }
            seenShas.insert(sha)
            seenIds.insert(id)
            let target: String = AvoFiles.join(packDir, AvoPackageWriter.packageName(device: "recuperado", id: id))
            let startMs: Int64 = (rtc > 946_684_800_000 && rtc < 4_102_444_800_000) ? rtc : 0
            let meta = AvoPackageWriter.Meta(sessionId: id, sha256: sha, watchDevice: "", watchFirmware: "",
                                             startRtcMs: startMs, activeMs: 0, source: "recuperado-ipad")
            do {
                try AvoPackageWriter.write(target: target, meta: meta, segments: segs)
            } catch {
                add(.damaged, "No se pudo empaquetar: " + error.localizedDescription)
                continue
            }
            items.append(TrainingRecoveryItem(name: name, path: dir, status: .pending,
                                              reason: "Sesión \(id) · empaquetada desde \(segs.count) segmento(s)", importPath: target))
        }

        for p in scan.partials {
            items.append(TrainingRecoveryItem(name: AvoFiles.fileName(p), path: p, status: .incomplete,
                                              reason: "Descarga o copia interrumpida (archivo temporal)"))
        }
        return items
    }
}

// MARK: - Model

@Observable
final class TrainingListModel {
    @ObservationIgnored unowned let app: AppModel
    static let filterKey: String = "avo.ipad.listado.filtros"

    var filter: TrainingListFilter = TrainingListFilter() {
        didSet { if oldValue != filter { saveFilter() } }
    }
    /// Fence slots visited by each training (session id), computed once per session and fence plan.
    var fenceCache: [String: [Int]] = [:]
    /// Origin of each training (Archivo / Wi-Fi / Bluetooth / Demo / Recuperado).
    var originCache: [String: String] = [:]
    var fences: [TrainingListFence] = []
    var computing: Bool = false

    var scanning: Bool = false
    var scanStatus: String = ""
    var report: TrainingRecoveryReport? = nil
    var pickingFolder: Bool = false

    @ObservationIgnored private var fenceSignature: String = ""
    @ObservationIgnored private var refreshAgain: Bool = false

    init(app: AppModel) {
        self.app = app
        if !AppModel.isCaptureLaunch, let d = UserDefaults.standard.data(forKey: TrainingListModel.filterKey),
           let f = try? JSONDecoder().decode(TrainingListFilter.self, from: d) {
            filter = f
        }
        TrainingListModel.ensureDocumentsFolder()
    }

    // ---------------------------------------------------------------- contract
    func sessionChanged() { refreshCaches() }
    func pageShown() { refreshCaches() }

    /// Documents is the folder Files shows as «En mi iPad / AVO Horse» (UIFileSharingEnabled + LSSupportsOpeningDocumentsInPlace);
    /// a subfolder makes it appear even before any file is saved there.
    static func ensureDocumentsFolder() {
        guard let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        AvoFiles.ensureDir(d.appendingPathComponent("Entrenamientos", isDirectory: true).path)
    }

    private func saveFilter() {
        if let d = try? JSONEncoder().encode(filter) { UserDefaults.standard.set(d, forKey: TrainingListModel.filterKey) }
    }

    // ---------------------------------------------------------------- rows
    func row(_ s: SessionItem) -> TrainingListRow {
        let dur: Double = s.timeline.count > 1 ? s.timeline.durationS : s.session.durationSeconds
        let slots: [Int]? = fenceCache[s.id]
        var fenceText: String = "…"
        if let sl = slots {
            let names: [String] = sl.compactMap { (k: Int) -> String? in fences.first(where: { $0.slot == k })?.name }
            fenceText = names.isEmpty ? "—" : names.joined(separator: ", ")
        } else if fences.isEmpty {
            fenceText = "—"
        }
        let origin: String = s.isSynthetic ? "Demo" : (originCache[s.id] ?? "…")
        let rowSlots: [Int]? = fences.isEmpty ? Optional<[Int]>.some([]) : slots
        return TrainingListRow(id: s.id, start: s.start, startKey: s.start?.timeIntervalSince1970 ?? -1e12,
                               dateTimeText: s.dateTimeText, horse: s.horse, rider: s.rider, discipline: s.discipline,
                               durationS: dur.isFinite ? dur : 0, durationText: s.durationText,
                               distanceKm: s.distanceKmValue, distanceText: s.distanceText,
                               maxSpeedKmh: s.maxSpeedKmh, maxSpeedText: s.maxSpeedText,
                               hasGirth: s.hasGirth, girthText: s.hasGirth ? "Sí" : "No",
                               fenceSlots: rowSlots, fencesText: fenceText, origin: origin,
                               engineState: s.engineState, isFavorite: s.isFavorite, favKey: s.isFavorite ? 1 : 0,
                               isSynthetic: s.isSynthetic,
                               searchExtra: [s.horseCode ?? "", s.riderCode ?? "", s.kind, s.session.sourceName].joined(separator: " "))
    }

    var allRows: [TrainingListRow] { app.sessions.map { row($0) } }

    /// Filtered rows, newest first.
    var rows: [TrainingListRow] {
        let f: TrainingListFilter = filter
        let cal: Calendar = TrainingListFilter.calendar
        return allRows.filter { f.matches($0, calendar: cal) }.sorted { $0.startKey > $1.startKey }
    }

    func item(_ id: String) -> SessionItem? { app.sessions.first(where: { $0.id == id }) }

    /// Opens the training in «Análisis».
    func open(_ id: String) {
        guard let s = item(id) else { return }
        app.select(s)
        app.page = .analysis
    }

    func toggleFavorite(_ id: String) {
        if let s = item(id) { app.toggleFavorite(s) }
    }

    // ---------------------------------------------------------------- filter options
    private static func sortedUnique(_ l: [String]) -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for x in l {
            let t: String = x.trimmed
            if t.isEmpty || seen.contains(t.lowercased()) { continue }
            seen.insert(t.lowercased())
            out.append(t)
        }
        return out.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var horseOptions: [String] { TrainingListModel.sortedUnique(app.sessions.map { $0.horse } + (app.stable?.horseNames ?? [])) }
    var riderOptions: [String] { TrainingListModel.sortedUnique(app.sessions.map { $0.rider } + (app.stable?.riderNames ?? [])) }
    var disciplineOptions: [String] { TrainingListModel.sortedUnique(app.sessions.map { $0.discipline }) }

    func fenceName(_ slot: Int) -> String { fences.first(where: { $0.slot == slot })?.name ?? "Geocerca \(slot + 1)" }

    func clearFilters() { filter = TrainingListFilter() }

    /// Quick date chips: nil = Todo, 1 = Hoy, 7 / 30 días (counting today).
    func setQuick(_ days: Int?) {
        guard let n = days else { filter.from = nil; filter.to = nil; return }
        let cal: Calendar = TrainingListFilter.calendar
        let today: Date = cal.startOfDay(for: Date())
        filter.from = cal.date(byAdding: .day, value: -(n - 1), to: today) ?? today
        filter.to = nil
    }

    func isQuick(_ days: Int?) -> Bool {
        guard let n = days else { return filter.from == nil && filter.to == nil }
        if filter.to != nil { return false }
        guard let f = filter.from else { return false }
        let cal: Calendar = TrainingListFilter.calendar
        let today: Date = cal.startOfDay(for: Date())
        guard let want = cal.date(byAdding: .day, value: -(n - 1), to: today) else { return false }
        return cal.isDate(f, inSameDayAs: want)
    }

    // ---------------------------------------------------------------- caches (off the main thread)
    func refreshCaches() {
        if computing { refreshAgain = true; return }
        var snap: [TrainingListFence] = []
        if let g = app.geofences { snap = TrainingListGeo.snapshot(g.plan) }
        let sig: String = TrainingListGeo.signature(snap)
        if sig != fenceSignature {
            fenceSignature = sig
            fenceCache = [:]
        }
        if fences != snap { fences = snap }
        var fenceJobs: [(id: String, lat: [Double], lon: [Double])] = []
        var originJobs: [(id: String, path: String)] = []
        var stored: [String: String] = [:]
        for e in app.library.entries where !e.sha256.isEmpty { stored[e.sha256.lowercased()] = e.storedPath }
        for s in app.sessions {
            if !snap.isEmpty && fenceCache[s.id] == nil {
                fenceJobs.append((s.id, s.fullTimeline.lat, s.fullTimeline.lon))
            }
            if originCache[s.id] == nil && !s.isSynthetic {
                let sha: String = (s.session.fileSha256 ?? "").lowercased()
                let path: String = stored[sha] ?? s.session.sourcePath ?? ""
                originJobs.append((s.id, path))
            }
        }
        if fenceJobs.isEmpty && originJobs.isEmpty { return }
        computing = true
        let fenceList: [(id: String, lat: [Double], lon: [Double])] = fenceJobs
        let originList: [(id: String, path: String)] = originJobs
        let fenceSnap: [TrainingListFence] = snap
        Task { @MainActor [weak self] in
            let result: (fences: [String: [Int]], origins: [String: String]) = await Task.detached(priority: .utility) {
                () -> (fences: [String: [Int]], origins: [String: String]) in
                var f: [String: [Int]] = [:]
                for j in fenceList { f[j.id] = TrainingListGeo.visited(lat: j.lat, lon: j.lon, fences: fenceSnap) }
                var o: [String: String] = [:]
                for j in originList { o[j.id] = TrainingListModel.origin(ofFile: j.path) }
                return (f, o)
            }.value
            guard let self = self else { return }
            if self.fenceSignature == sig {
                for (k, v) in result.fences { self.fenceCache[k] = v }
            }
            for (k, v) in result.origins { self.originCache[k] = v }
            self.computing = false
            if self.refreshAgain {
                self.refreshAgain = false
                self.refreshCaches()
            }
        }
    }

    /// Origin of a training from its file: the «source» of the .avo manifest (wifi-ipad, ble-ipad, recuperado-ipad), else Archivo.
    static func origin(ofFile path: String) -> String {
        if path.isEmpty || AvoFiles.ext(path) != ".avo" { return "Archivo" }
        guard let m = TrainingRecovery.avoManifest(path) else { return "Archivo" }
        switch (AvoJSON.string(m, "source") ?? "").lowercased() {
        case "wifi-ipad", "wifi", "wifi-android": return "Wi-Fi"
        case "ble-ipad", "ble", "ble-android": return "Bluetooth"
        case "recuperado-ipad": return "Recuperado"
        default: return "Archivo"
        }
    }

    // ---------------------------------------------------------------- lost trainings
    private func knownInputs() -> (shas: [String], ids: [String], paths: [String]) {
        var shas: [String] = []
        var paths: [String] = []
        for s in app.sessions {
            if let a = s.session.fileSha256 { shas.append(a.lowercased()) }
            if let b = s.session.sha256 { shas.append(b.lowercased()) }
            paths.append(contentsOf: s.session.rawSegmentPaths)
            if let p = s.session.sourcePath { paths.append(p) }
        }
        let loaded: Set<String> = Set(shas)
        for e in app.library.entries where loaded.contains(e.sha256.lowercased()) { paths.append(e.storedPath) }
        // trainings deleted by the user count as known: the scan must not bring them back
        let deleted = app.loadDeleted()
        shas.append(contentsOf: deleted.shas)
        return (shas, app.sessions.map { $0.id } + deleted.sessionIds, paths)
    }

    private static func makeKnown(_ k: (shas: [String], ids: [String], paths: [String])) -> TrainingRecoveryKnown {
        var r = TrainingRecoveryKnown()
        r.shas = Set(k.shas)
        r.sessionIds = Set(k.ids)
        r.paths = Set(k.paths.map { TrainingRecovery.canonical($0) })
        return r
    }

    /// «Buscar entrenamientos perdidos»: the whole app container.
    @MainActor
    func scanDevice() async {
        if scanning { return }
        if app.busy { scanStatus = "Espera a que termine la importación en curso."; return }
        scanning = true
        scanStatus = "Buscando en la memoria del iPad…"
        let inputs = knownInputs()
        let root: String = app.paths.root
        let packDir: String = AvoFiles.join(root, "reloj", "recuperados")
        let found: (items: [TrainingRecoveryItem], scan: TrainingRecoveryScan) = await Task.detached(priority: .userInitiated) {
            () -> (items: [TrainingRecoveryItem], scan: TrainingRecoveryScan) in
            let known: TrainingRecoveryKnown = TrainingListModel.makeKnown(inputs)
            let scan: TrainingRecoveryScan = TrainingRecovery.collect(TrainingRecovery.containerRoots(appRoot: root),
                                                                      maxDepth: 12, maxFiles: 50_000)
            return (TrainingRecovery.evaluate(scan, known: known, packDir: packDir), scan)
        }.value
        await finishScan(found.items, scan: found.scan, folder: "Memoria del iPad")
    }

    /// «Buscar en una carpeta…»: a folder chosen in Files (security-scoped), depth 6, at most 2000 files.
    @MainActor
    func scanFolder(_ url: URL) async {
        if scanning { return }
        if app.busy { scanStatus = "Espera a que termine la importación en curso."; return }
        scanning = true
        scanStatus = "Buscando en «\(url.lastPathComponent)»…"
        let inputs = knownInputs()
        let root: String = app.paths.root
        let packDir: String = AvoFiles.join(root, "reloj", "recuperados")
        let inbox: String = AvoFiles.join(root, "entrada")
        let found: (items: [TrainingRecoveryItem], scan: TrainingRecoveryScan) = await Task.detached(priority: .userInitiated) {
            () -> (items: [TrainingRecoveryItem], scan: TrainingRecoveryScan) in
            let access: Bool = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let known: TrainingRecoveryKnown = TrainingListModel.makeKnown(inputs)
            let scan: TrainingRecoveryScan = TrainingRecovery.collect([url.path], maxDepth: 6, maxFiles: 2000, skipDirNames: [])
            return (TrainingRecovery.evaluate(scan, known: known, packDir: packDir, copyInbox: inbox), scan)
        }.value
        await finishScan(found.items, scan: found.scan, folder: url.lastPathComponent)
    }

    @MainActor
    private func finishScan(_ found: [TrainingRecoveryItem], scan: TrainingRecoveryScan, folder: String) async {
        var items: [TrainingRecoveryItem] = found
        let paths: [String] = items.compactMap { $0.status == .pending ? $0.importPath : nil }
        if !paths.isEmpty {
            scanStatus = "Importando \(paths.count) entrenamiento(s) recuperado(s)…"
            await app.importFiles(paths)
        }
        let loaded: Set<String> = Set(app.sessions.compactMap { $0.session.sourcePath.map { TrainingRecovery.canonical($0) } })
        for i in items.indices where items[i].status == .pending {
            let p: String = items[i].importPath ?? ""
            if loaded.contains(TrainingRecovery.canonical(p)) {
                items[i].status = .recovered
            } else {
                items[i].status = .damaged
                let fname: String = AvoFiles.fileName(p)
                let why: String = app.importLog.first(where: { $0.file == fname && !$0.ok })?.result ?? "Rechazado al importar"
                items[i].reason = why
            }
            if let c = items[i].tempCopy { try? FileManager.default.removeItem(atPath: (c as NSString).deletingLastPathComponent) }
        }
        let order: [TrainingRecoveryStatus] = [.recovered, .incomplete, .damaged, .duplicate, .pending]
        items.sort { (a: TrainingRecoveryItem, b: TrainingRecoveryItem) -> Bool in
            let ia: Int = order.firstIndex(of: a.status) ?? 9
            let ib: Int = order.firstIndex(of: b.status) ?? 9
            return ia != ib ? ia < ib : a.name < b.name
        }
        let rep = TrainingRecoveryReport(scanned: scan.scanned, limited: scan.limited, items: items, folder: folder)
        app.log.info("listado", "Búsqueda de entrenamientos perdidos", ["carpeta": folder, "resumen": rep.summary])
        scanning = false
        scanStatus = rep.summary
        app.status = "Búsqueda de entrenamientos perdidos: " + rep.summary
        report = rep
        refreshCaches()
    }
}
