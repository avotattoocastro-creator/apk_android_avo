using System.Globalization;
using System.Net;
using System.Text;

namespace Avo.Windows.Core;

public static class ExportService
{
    private static readonly CultureInfo Inv = CultureInfo.InvariantCulture;
    public static void ExportCsv(TrainingSession training, string fileName)
    {
        using var writer = new StreamWriter(fileName, false, new UTF8Encoding(true));
        writer.WriteLine("tiempo_gps_ms;latitud;longitud;velocidad_kmh;precision_horizontal_m;rtk;altitud_m");
        foreach (var p in training.Track)
            writer.WriteLine(string.Join(";", p.GpsWeekMs.ToString(Inv), p.Latitude.ToString("F7", Inv), p.Longitude.ToString("F7", Inv),
                p.SpeedKmh.ToString("F3", Inv), p.AccuracyM.ToString("F3", Inv), p.RtkName, p.AltitudeM.ToString("F3", Inv)));
    }
    public static void ExportGpx(TrainingSession training, string fileName)
    {
        var escaped = System.Security.SecurityElement.Escape(training.SessionId) ?? "AVO";
        using var writer = new StreamWriter(fileName, false, new UTF8Encoding(false));
        writer.WriteLine("<?xml version=\"1.0\" encoding=\"UTF-8\"?>");
        writer.WriteLine("<gpx version=\"1.1\" creator=\"AVO Performance Horse Windows\" xmlns=\"http://www.topografix.com/GPX/1/1\">");
        writer.WriteLine($"<trk><name>{escaped}</name><trkseg>");
        foreach (var p in training.Track)
            writer.WriteLine($"<trkpt lat=\"{p.Latitude.ToString("F7", Inv)}\" lon=\"{p.Longitude.ToString("F7", Inv)}\"><ele>{p.AltitudeM.ToString("F3", Inv)}</ele></trkpt>");
        writer.WriteLine("</trkseg></trk></gpx>");
    }
    public static string RenderReport(TrainingSession s)
    {
        static string Esc(string? x) => WebUtility.HtmlEncode(x ?? "—");
        return """
            <!doctype html><html lang="es"><head><meta charset="utf-8" />
            <title>AVO Performance Horse | Informe</title>
            <style>body{font:16px 'Segoe UI',sans-serif;color:#132539;margin:36px}header{border-bottom:4px solid #1587d1;padding:12px 0}h1{font-size:30px}h2{color:#0f76be;margin-top:36px}.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}article{background:#ecf6fc;padding:20px;border-radius:8px}b{display:block;font-size:24px}.note{font-size:13px;color:#566}table{border-collapse:collapse;width:100%}td,th{padding:10px;text-align:left;border-bottom:1px solid #ddd}</style>
            </head><body>
            """ + $"<header><h1>AVO PERFORMANCE HORSE</h1><p>Informe de entrenamiento · {Esc(s.DateText)}</p></header>" +
            $"<h2>{Esc(s.Horse)} / {Esc(s.Rider)}</h2><p>Sesión: {Esc(s.SessionId)} · Archivo: {Esc(s.SourceName)}</p>" +
            "<div class='grid'>" +
            $"<article>Distancia<b>{s.DistanceM / 1000:0.00} km</b></article>" +
            $"<article>Duración<b>{Analytics.Duration(s.DurationSeconds)}</b></article>" +
            $"<article>Velocidad máxima<b>{s.MaxSpeedKmh:0.0} km/h</b></article>" +
            $"<article>Velocidad media<b>{s.MeanSpeedKmh:0.0} km/h</b></article>" +
            $"<article>GNSS utilizable<b>{s.GnssSamples - s.UnusableGnssSamples}</b></article>" +
            $"<article>RTK FIX<b>{s.FixPercent:0.0} %</b></article></div>" +
            $"<h2>Calidad e integridad</h2><p>{Esc(s.Integrity)} · {s.Segments.Count} segmentos · {s.InvalidFrames} tramas rechazadas</p>" +
            $"<h2>Cincha e IMU</h2><p>{s.TotalImuBatches} lotes / {s.TotalImuSamples} muestras registradas. Sin estimar simetría sin calibración validada.</p>" +
            $"<h2>Condiciones marinas</h2><p>Fuente: {Esc(s.MarineSource)} · Tipo: {Esc(s.MarineKind)} · Hora de referencia: {Esc(s.MarineObservedAt?.ToString("O"))}</p>" +
            $"<p>Altura: {Format(s.TideHeightM, "m")} · Viento: {Format(s.WindKmh, "km/h")} · Olas: {Format(s.WaveHeightM, "m")} · {Esc(s.MarineNotes)}</p>" +
            "<h2>Tramos de 500 m</h2><table><tr><th>Tramo</th><th>Distancia</th><th>Tiempo</th><th>V. media</th><th>V. máxima</th></tr>" +
            string.Join("", Analytics.Sections(s).Select(x => $"<tr><td>{x.Index}</td><td>{x.DistanceM:0} m</td><td>{Analytics.Duration(x.DurationS)}</td><td>{x.AverageSpeedKmh:0.0} km/h</td><td>{x.MaximumSpeedKmh:0.0} km/h</td></tr>")) +
            "</table><p class='note'>El mapa, la trayectoria y las conclusiones deben revisarse junto a la calidad GNSS/RTK. Distancias derivadas de GNSS de jinete, no del centro de masas del caballo.</p></body></html>";
    }
    private static string Format(double? value, string suffix) => value.HasValue ? value.Value.ToString("0.##", Inv) + " " + suffix : "No disponible";
    public static void ExportHtml(TrainingSession s, string path) => File.WriteAllText(path, RenderReport(s), new UTF8Encoding(false));
}
