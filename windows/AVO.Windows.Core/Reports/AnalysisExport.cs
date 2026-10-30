using System.Globalization;
using System.Text;
using System.Text.Json;

namespace Avo.Windows.Core;

/// <summary>Exports of the analysis (originals untouched). Units are always written explicitly.</summary>
public static class AnalysisExport
{
    private static readonly CultureInfo Inv = CultureInfo.InvariantCulture;
    public const string JsonFormat = "avo-windows-analysis";
    public const int JsonVersion = 1;

    private static string F(double v, string fmt) => double.IsFinite(v) ? v.ToString(fmt, Inv) : "";

    /// <summary>CSV (semicolon) of the timeline: raw and derived values side by side; empty cells = no data.</summary>
    public static void TimelineCsv(SessionTimeline tl, string path, double t0 = double.NegativeInfinity, double t1 = double.PositiveInfinity)
    {
        using var w = new StreamWriter(path, false, new UTF8Encoding(true));
        w.WriteLine("t_s;utc;latitud_deg;longitud_deg;velocidad_reportada_ms;velocidad_derivada_ms;velocidad_filtrada_ms;sigma_velocidad_ms;" +
                    "aceleracion_long_ms2;sigma_aceleracion_ms2;aceleracion_lateral_ms2;distancia_m;altitud_msl_m;hacc_m;sacc_ms;satelites;solucion;corte_previo;salto_previo");
        for (int i = 0; i < tl.Count; i++)
        {
            if (tl.T[i] < t0 || tl.T[i] > t1) continue;
            w.WriteLine(string.Join(";",
                F(tl.T[i], "0.000"), tl.UtcAt(i)?.UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ss.fffZ", Inv) ?? "",
                F(tl.Lat[i], "0.0000000"), F(tl.Lon[i], "0.0000000"), F(tl.SpeedReported[i], "0.000"), F(tl.SpeedDerived[i], "0.000"),
                F(tl.SpeedFiltered[i], "0.000"), F(tl.SpeedFilteredSigma[i], "0.000"), F(tl.AccelLong[i], "0.000"), F(tl.AccelLongSigma[i], "0.000"),
                F(tl.AccelLateral[i], "0.000"), F(tl.Distance[i], "0.00"), F(tl.AltitudeMsl[i], "0.000"), F(tl.HAcc[i], "0.000"), F(tl.SpeedAcc[i], "0.000"),
                tl.NumSv[i].ToString(Inv), GnssQuality.Name(tl.Solution[i]), tl.BreakBefore[i] ? "1" : "0", tl.JumpBefore[i] ? "1" : "0"));
        }
    }

    /// <summary>GPX 1.1 with UTC times and the reported speed as an extension.</summary>
    public static void Gpx(TrainingSession s, SessionTimeline tl, string path, double t0 = double.NegativeInfinity, double t1 = double.PositiveInfinity)
    {
        using var w = new StreamWriter(path, false, new UTF8Encoding(false));
        w.WriteLine("<?xml version=\"1.0\" encoding=\"UTF-8\"?>");
        w.WriteLine("<gpx version=\"1.1\" creator=\"AVO Performance Horse Windows\" xmlns=\"http://www.topografix.com/GPX/1/1\" xmlns:avo=\"https://avoperformance.org/gpx/1\">");
        w.WriteLine($"<metadata><name>{Esc(s.SessionId)}</name><desc>{Esc($"{s.Horse} / {s.Rider} — trayectoria del chaleco GNSS del jinete")}</desc></metadata>");
        w.WriteLine($"<trk><name>{Esc(s.SessionId)}</name><trkseg>");
        for (int i = 0; i < tl.Count; i++)
        {
            if (tl.T[i] < t0 || tl.T[i] > t1) continue;
            if (i > 0 && tl.BreakBefore[i]) w.WriteLine("</trkseg><trkseg>");
            var sb = new StringBuilder();
            sb.Append($"<trkpt lat=\"{tl.Lat[i].ToString("0.0000000", Inv)}\" lon=\"{tl.Lon[i].ToString("0.0000000", Inv)}\">");
            if (double.IsFinite(tl.AltitudeMsl[i])) sb.Append($"<ele>{tl.AltitudeMsl[i].ToString("0.000", Inv)}</ele>");
            if (tl.UtcAt(i) is DateTimeOffset u) sb.Append($"<time>{u.UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ss.fffZ", Inv)}</time>");
            sb.Append($"<sat>{tl.NumSv[i].ToString(Inv)}</sat><extensions><avo:speed>{tl.SpeedReported[i].ToString("0.000", Inv)}</avo:speed><avo:fix>{GnssQuality.Name(tl.Solution[i])}</avo:fix></extensions></trkpt>");
            w.WriteLine(sb.ToString());
        }
        w.WriteLine("</trkseg></trk></gpx>");
    }

    private static string Esc(string s) => System.Security.SecurityElement.Escape(s) ?? "";

    /// <summary>Versioned JSON with summary, segments and provenance (format avo-windows-analysis v1).</summary>
    public static string Json(TrainingSession s, SessionTimeline tl, IEnumerable<SegmentMetrics> segments, EquineAnalysis? engine, bool includeSeries)
    {
        using var ms = new MemoryStream();
        using (var j = new Utf8JsonWriter(ms, new JsonWriterOptions { Indented = true }))
        {
            j.WriteStartObject();
            j.WriteString("formato", JsonFormat);
            j.WriteNumber("version_formato", JsonVersion);
            j.WriteString("generado_utc", DateTimeOffset.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", Inv));
            j.WriteString("aplicacion", "AVO Performance Horse — Windows Advanced Analysis V2 PRO");
            j.WriteStartObject("sesion");
            j.WriteString("id", s.SessionId); j.WriteString("caballo", s.Horse); j.WriteString("jinete", s.Rider);
            j.WriteString("archivo", s.SourceName); j.WriteString("integridad", s.Integrity); j.WriteBoolean("sintetica", s.IsSynthetic);
            if (tl.Utc0 is DateTimeOffset u) j.WriteString("inicio_utc", u.UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ss.fffZ", Inv));
            if (s.FileSha256 is not null) j.WriteString("sha256_archivo", s.FileSha256);
            j.WriteEndObject();
            j.WriteStartObject("procedencia");
            j.WriteString("origen_posicion", "Chaleco GNSS del jinete (no es un punto anatómico del caballo)");
            j.WriteString("filtro_velocidad", tl.FilterParameters.Describe());
            j.WriteString("motor", engine?.Engine ?? "no disponible");
            j.WriteEndObject();
            j.WriteStartObject("unidades");
            j.WriteString("velocidad", "m/s"); j.WriteString("aceleracion", "m/s2"); j.WriteString("distancia", "m"); j.WriteString("tiempo", "s");
            j.WriteEndObject();
            j.WriteStartObject("resumen");
            j.WriteNumber("distancia_m", Math.Round(tl.TotalDistanceM, 2));
            j.WriteNumber("duracion_s", Math.Round(tl.DurationS, 3));
            j.WriteNumber("epocas_gnss", s.GnssSamples);
            j.WriteNumber("perdidas_senal", tl.Losses.Count);
            j.WriteEndObject();
            j.WriteStartArray("tramos");
            foreach (var m in segments)
            {
                j.WriteStartObject();
                j.WriteString("id", m.Id); j.WriteString("nombre", m.Name); j.WriteString("tipo", m.Kind.ToString());
                j.WriteNumber("t0", Math.Round(m.T0, 3)); j.WriteNumber("t1", Math.Round(m.T1, 3));
                j.WriteNumber("distancia_m", Math.Round(m.DistanceM, 2)); j.WriteNumber("duracion_s", Math.Round(m.DurationS, 3));
                Opt(j, "velocidad_max_kmh", m.MaxSpeedKmh); Opt(j, "velocidad_media_kmh", m.MeanSpeedKmh);
                Opt(j, "aceleracion_max_ms2", m.MaxAccel); Opt(j, "desaceleracion_max_ms2", m.MaxDecel);
                j.WriteNumber("fraccion_fix", Math.Round(m.FixFraction, 4)); j.WriteNumber("cambios_ritmo", m.SpeedChanges);
                Opt(j, "cadencia_trancos_min", m.Cadence);
                j.WriteString("observaciones", m.Observations); j.WriteString("notas", m.Notes);
                j.WriteEndObject();
            }
            j.WriteEndArray();
            if (includeSeries)
            {
                j.WriteStartObject("series");
                Arr(j, "t", tl.T); Arr(j, "velocidad_reportada", tl.SpeedReported); Arr(j, "velocidad_filtrada", tl.SpeedFiltered);
                Arr(j, "aceleracion_long", tl.AccelLong); Arr(j, "distancia", tl.Distance);
                j.WriteEndObject();
            }
            j.WriteEndObject();
        }
        return Encoding.UTF8.GetString(ms.ToArray());
    }

    private static void Opt(Utf8JsonWriter j, string name, double? v)
    {
        if (v is double d && double.IsFinite(d)) j.WriteNumber(name, Math.Round(d, 4)); else j.WriteNull(name);
    }

    private static void Arr(Utf8JsonWriter j, string name, double[] values)
    {
        j.WriteStartArray(name);
        foreach (var v in values) { if (double.IsFinite(v)) j.WriteNumberValue(Math.Round(v, 4)); else j.WriteNullValue(); }
        j.WriteEndArray();
    }
}
