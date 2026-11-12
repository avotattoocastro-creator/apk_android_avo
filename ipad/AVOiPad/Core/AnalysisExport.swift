import Foundation

/// Exports of the analysis (originals untouched). Units are always written explicitly.
/// Byte-compatible with the Windows exports (UTF-8, CRLF line ends, invariant numbers).
enum AnalysisExport {
    static let jsonFormat: String = "avo-windows-analysis"
    static let jsonVersion: Int = 1

    private static func f(_ v: Double, _ fmt: String) -> String { v.isFinite ? DotNetFormat.custom(v, fmt, spanish: false) : "" }

    /// CSV text (semicolon) of the timeline: raw and derived values side by side; empty cells = no data. Without BOM.
    static func timelineCsvText(_ tl: SessionTimeline, t0: Double = -Double.infinity, t1: Double = Double.infinity) -> String {
        let nl: String = DotNetFormat.newline
        var out: String = "t_s;utc;latitud_deg;longitud_deg;velocidad_reportada_ms;velocidad_derivada_ms;velocidad_filtrada_ms;sigma_velocidad_ms;" +
            "aceleracion_long_ms2;sigma_aceleracion_ms2;aceleracion_lateral_ms2;distancia_m;altitud_msl_m;hacc_m;sacc_ms;satelites;solucion;corte_previo;salto_previo" + nl
        for i in 0..<tl.count {
            if tl.t[i] < t0 || tl.t[i] > t1 { continue }
            var cells: [String] = []
            cells.reserveCapacity(19)
            cells.append(f(tl.t[i], "0.000"))
            if let ticks = tl.utcTicksAt(i) { cells.append(DotNetFormat.utcMillisStamp(ticks: ticks)) } else { cells.append("") }
            cells.append(f(tl.lat[i], "0.0000000")); cells.append(f(tl.lon[i], "0.0000000"))
            cells.append(f(tl.speedReported[i], "0.000")); cells.append(f(tl.speedDerived[i], "0.000"))
            cells.append(f(tl.speedFiltered[i], "0.000")); cells.append(f(tl.speedFilteredSigma[i], "0.000"))
            cells.append(f(tl.accelLong[i], "0.000")); cells.append(f(tl.accelLongSigma[i], "0.000"))
            cells.append(f(tl.accelLateral[i], "0.000")); cells.append(f(tl.distance[i], "0.00"))
            cells.append(f(tl.altitudeMsl[i], "0.000")); cells.append(f(tl.hAcc[i], "0.000")); cells.append(f(tl.speedAcc[i], "0.000"))
            cells.append(String(tl.numSv[i])); cells.append(GnssQuality.name(tl.solution[i]))
            cells.append(tl.breakBefore[i] ? "1" : "0"); cells.append(tl.jumpBefore[i] ? "1" : "0")
            out += cells.joined(separator: ";") + nl
        }
        return out
    }

    /// CSV file bytes: UTF-8 with BOM (as `new UTF8Encoding(true)` on Windows).
    static func timelineCsvData(_ tl: SessionTimeline, t0: Double = -Double.infinity, t1: Double = Double.infinity) -> Data {
        var d: Data = Data([0xEF, 0xBB, 0xBF])
        d.append(Data(timelineCsvText(tl, t0: t0, t1: t1).utf8))
        return d
    }

    static func timelineCsv(_ tl: SessionTimeline, _ path: String, t0: Double = -Double.infinity, t1: Double = Double.infinity) throws {
        try AvoFiles.writeAtomic(timelineCsvData(tl, t0: t0, t1: t1), to: path)
    }

    /// GPX 1.1 with UTC times and the reported speed as an extension (UTF-8 without BOM).
    static func gpxText(_ s: TrainingSession, _ tl: SessionTimeline, t0: Double = -Double.infinity, t1: Double = Double.infinity) -> String {
        let nl: String = DotNetFormat.newline
        var out: String = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" + nl
        out += "<gpx version=\"1.1\" creator=\"AVO Performance Horse Windows\" xmlns=\"http://www.topografix.com/GPX/1/1\" xmlns:avo=\"https://avoperformance.org/gpx/1\">" + nl
        let desc: String = s.horse + " / " + s.rider + " — trayectoria del chaleco GNSS del jinete"
        out += "<metadata><name>" + esc(s.sessionId) + "</name><desc>" + esc(desc) + "</desc></metadata>" + nl
        out += "<trk><name>\(esc(s.sessionId))</name><trkseg>" + nl
        for i in 0..<tl.count {
            if tl.t[i] < t0 || tl.t[i] > t1 { continue }
            if i > 0 && tl.breakBefore[i] { out += "</trkseg><trkseg>" + nl }
            var sb: String = "<trkpt lat=\"\(DotNetFormat.custom(tl.lat[i], "0.0000000", spanish: false))\" lon=\"\(DotNetFormat.custom(tl.lon[i], "0.0000000", spanish: false))\">"
            if tl.altitudeMsl[i].isFinite { sb += "<ele>\(DotNetFormat.custom(tl.altitudeMsl[i], "0.000", spanish: false))</ele>" }
            if let ticks = tl.utcTicksAt(i) { sb += "<time>\(DotNetFormat.utcMillisStamp(ticks: ticks))</time>" }
            sb += "<sat>\(tl.numSv[i])</sat><extensions><avo:speed>\(DotNetFormat.custom(tl.speedReported[i], "0.000", spanish: false))</avo:speed><avo:fix>\(GnssQuality.name(tl.solution[i]))</avo:fix></extensions></trkpt>"
            out += sb + nl
        }
        out += "</trkseg></trk></gpx>" + nl
        return out
    }

    static func gpxData(_ s: TrainingSession, _ tl: SessionTimeline, t0: Double = -Double.infinity, t1: Double = Double.infinity) -> Data {
        Data(gpxText(s, tl, t0: t0, t1: t1).utf8)
    }

    static func gpx(_ s: TrainingSession, _ tl: SessionTimeline, _ path: String, t0: Double = -Double.infinity, t1: Double = Double.infinity) throws {
        try AvoFiles.writeAtomic(gpxData(s, tl, t0: t0, t1: t1), to: path)
    }

    private static func esc(_ s: String) -> String { DotNetText.xmlEscape(s) }

    /// Versioned JSON with summary, segments and provenance (format avo-windows-analysis v1).
    static func json(_ s: TrainingSession, _ tl: SessionTimeline, _ segments: [SegmentMetrics], _ engine: EquineAnalysis?, _ includeSeries: Bool) -> String {
        var j = DotNetJsonWriter(indented: true)
        j.writeStartObject()
        j.writeString("formato", jsonFormat)
        j.writeNumber("version_formato", jsonVersion)
        j.writeString("generado_utc", DotNetFormat.utcSecondsStamp(Date()))
        j.writeString("aplicacion", "AVO Performance Horse — Windows Advanced Analysis V2 PRO")
        j.writeStartObject("sesion")
        j.writeString("id", s.sessionId); j.writeString("caballo", s.horse); j.writeString("jinete", s.rider)
        j.writeString("archivo", s.sourceName); j.writeString("integridad", s.integrity); j.writeBoolean("sintetica", s.isSynthetic)
        if let u = tl.utc0Ticks { j.writeString("inicio_utc", DotNetFormat.utcMillisStamp(ticks: u)) }
        if let sha = s.fileSha256 { j.writeString("sha256_archivo", sha) }
        j.writeEndObject()
        j.writeStartObject("procedencia")
        j.writeString("origen_posicion", "Chaleco GNSS del jinete (no es un punto anatómico del caballo)")
        j.writeString("filtro_velocidad", tl.filterParameters.describe())
        j.writeString("motor", engine?.engine ?? "no disponible")
        j.writeEndObject()
        j.writeStartObject("unidades")
        j.writeString("velocidad", "m/s"); j.writeString("aceleracion", "m/s2"); j.writeString("distancia", "m"); j.writeString("tiempo", "s")
        j.writeEndObject()
        j.writeStartObject("resumen")
        j.writeNumber("distancia_m", DotNetFormat.round(tl.totalDistanceM, 2))
        j.writeNumber("duracion_s", DotNetFormat.round(tl.durationS, 3))
        j.writeNumber("epocas_gnss", s.gnssSamples)
        j.writeNumber("perdidas_senal", tl.losses.count)
        j.writeEndObject()
        j.writeStartArray("tramos")
        for m in segments {
            j.writeStartObject()
            j.writeString("id", m.id); j.writeString("nombre", m.name); j.writeString("tipo", m.kind.rawValue)
            j.writeNumber("t0", DotNetFormat.round(m.t0, 3)); j.writeNumber("t1", DotNetFormat.round(m.t1, 3))
            j.writeNumber("distancia_m", DotNetFormat.round(m.distanceM, 2)); j.writeNumber("duracion_s", DotNetFormat.round(m.durationS, 3))
            opt(&j, "velocidad_max_kmh", m.maxSpeedKmh); opt(&j, "velocidad_media_kmh", m.meanSpeedKmh)
            opt(&j, "aceleracion_max_ms2", m.maxAccel); opt(&j, "desaceleracion_max_ms2", m.maxDecel)
            j.writeNumber("fraccion_fix", DotNetFormat.round(m.fixFraction, 4)); j.writeNumber("cambios_ritmo", m.speedChanges)
            opt(&j, "cadencia_trancos_min", m.cadence)
            j.writeString("observaciones", m.observations); j.writeString("notas", m.notes)
            j.writeEndObject()
        }
        j.writeEndArray()
        if includeSeries {
            j.writeStartObject("series")
            arr(&j, "t", tl.t); arr(&j, "velocidad_reportada", tl.speedReported); arr(&j, "velocidad_filtrada", tl.speedFiltered)
            arr(&j, "aceleracion_long", tl.accelLong); arr(&j, "distancia", tl.distance)
            j.writeEndObject()
        }
        j.writeEndObject()
        return j.text
    }

    /// JSON file (UTF-8 without BOM, as File.WriteAllText with `new UTF8Encoding(false)`).
    static func writeJson(_ s: TrainingSession, _ tl: SessionTimeline, _ segments: [SegmentMetrics], _ engine: EquineAnalysis?,
                          _ includeSeries: Bool, to path: String) throws {
        try AvoFiles.writeAtomic(Data(json(s, tl, segments, engine, includeSeries).utf8), to: path)
    }

    private static func opt(_ j: inout DotNetJsonWriter, _ name: String, _ v: Double?) {
        if let d = v, d.isFinite { j.writeNumber(name, DotNetFormat.round(d, 4)) } else { j.writeNull(name) }
    }

    private static func arr(_ j: inout DotNetJsonWriter, _ name: String, _ values: [Double]) {
        j.writeStartArray(name)
        for v in values {
            if v.isFinite { j.writeNumberValue(DotNetFormat.round(v, 4)) } else { j.writeNullValue() }
        }
        j.writeEndArray()
    }
}
