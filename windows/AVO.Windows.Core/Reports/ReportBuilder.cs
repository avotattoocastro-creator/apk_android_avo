using System.Globalization;
using System.Net;
using System.Text;

namespace Avo.Windows.Core;

[Flags]
public enum ReportSections
{
    None = 0,
    General = 1, HorseRider = 2, DateDuration = 4, Map = 8, GnssStats = 16, SpeedAccel = 32, Charts = 64,
    Segments = 128, Biomechanics = 256, Comparison = 512, Tides = 1024, Notes = 2048,
    All = General | HorseRider | DateDuration | Map | GnssStats | SpeedAccel | Charts | Segments | Biomechanics | Comparison | Tides | Notes,
}

/// <summary>Everything a report may contain. Missing parts are printed as «Sin datos» / «No disponible».</summary>
public sealed class ReportData
{
    public required TrainingSession Session { get; init; }
    public required SessionTimeline Timeline { get; init; }
    public EquineAnalysis? Engine { get; init; }
    public IReadOnlyList<SegmentMetrics> Segments { get; init; } = [];
    public IReadOnlyList<SeriesAligner.SessionSummary> Comparison { get; init; } = [];
    public TidePrediction? Tides { get; init; }
    public WeatherModel? Weather { get; init; }
    public string Notes { get; init; } = "";
    public ReportSections Sections { get; init; } = ReportSections.All;
}

public static class ReportBuilder
{
    private static readonly CultureInfo Es = CultureInfo.GetCultureInfo("es-ES");
    private static readonly (byte, byte, byte) Ink = (0x10, 0x10, 0x14), Dim = (0x5B, 0x5C, 0x63), Red = (0xED, 0x12, 0x2A),
        Line = (0xD8, 0xD9, 0xDE), Panel = (0xF3, 0xF3, 0xF5), Dark = (0x10, 0x10, 0x14), Blue = (0x3D, 0x9B, 0xFF), White = (0xFF, 0xFF, 0xFF);

    public static string Num(double? v, string fmt, string unit = "") => TimeText.Num(v, fmt, unit);

    // ------------------------------------------------------------------------------------------------ PDF
    public static void WritePdf(ReportData d, Stream output)
    {
        var pdf = new PdfDocument { Title = $"Informe AVO {d.Session.SessionId}" };
        double y = 0;
        const double M = 40;
        double W = pdf.Width - 2 * M;
        int page = 0;

        void Header()
        {
            pdf.NewPage(); page++;
            pdf.FillRect(0, 0, pdf.Width, 64, Dark);
            pdf.FillRect(0, 64, pdf.Width, 3, Red);
            pdf.Text(M, 16, "AVO", 26, true, White);
            pdf.Text(M + 62, 20, "PERFORMANCE HORSE", 11, true, (0xC9, 0xCB, 0xD1));
            pdf.Text(M + 62, 35, "Informe de entrenamiento", 9, false, (0x9C, 0x9D, 0xA4));
            pdf.Text(pdf.Width - M, 22, MadridTime.Format(d.Timeline.Utc0 ?? d.Session.StartedAt, "dd/MM/yyyy HH:mm") + " (Europe/Madrid)", 9, false, White, PdfDocument.Align.Right);
            pdf.Text(pdf.Width - M, 37, "Sesión " + d.Session.SessionId, 8, false, (0x9C, 0x9D, 0xA4), PdfDocument.Align.Right);
            if (d.Session.IsSynthetic)
            {
                pdf.FillRect(M, 76, W, 18, (0xFF, 0xF1, 0xC9));
                pdf.Text(M + 8, 80, "DEMOSTRACIÓN — DATOS SINTÉTICOS. No corresponde a un entrenamiento medido.", 9, true, (0x7A, 0x52, 0x00));
                y = 104;
            }
            else y = 84;
            pdf.Line(M, pdf.Height - 34, pdf.Width - M, pdf.Height - 34, Line);
            pdf.Text(M, pdf.Height - 28, "GNSS del chaleco del jinete (no es un punto anatómico del caballo). IMU de cincha sin calibrar: índices exploratorios, no diagnósticos.", 6.8, false, Dim);
            pdf.Text(pdf.Width - M, pdf.Height - 28, $"Página {page}", 7, false, Dim, PdfDocument.Align.Right);
        }

        void Ensure(double h) { if (y + h > pdf.Height - 50) Header(); }
        void Title(string t) { Ensure(40); y += 8; pdf.Text(M, y, t.ToUpperInvariant(), 11, true, Red); y += 16; pdf.Line(M, y, M + W, y, Line); y += 8; }

        Header();
        var s = d.Session; var tl = d.Timeline;
        var whole = tl.Count >= 2 ? SegmentAnalyzer.Compute(tl, new SegmentDefinition { Name = "Sesión", T0 = tl.T[0], T1 = tl.T[^1] }, d.Engine) : null;

        if (d.Sections.HasFlag(ReportSections.General) || d.Sections.HasFlag(ReportSections.HorseRider) || d.Sections.HasFlag(ReportSections.DateDuration))
        {
            Title("Datos generales");
            var rows = new List<(string, string)>();
            if (d.Sections.HasFlag(ReportSections.HorseRider)) { rows.Add(("Caballo", s.Horse)); rows.Add(("Jinete", s.Rider)); }
            if (d.Sections.HasFlag(ReportSections.DateDuration))
            {
                rows.Add(("Fecha y hora", MadridTime.Format(tl.Utc0 ?? s.StartedAt, "dddd dd/MM/yyyy HH:mm")));
                rows.Add(("Duración", TimeText.Clock(tl.Count > 1 ? tl.DurationS : s.DurationSeconds)));
            }
            if (d.Sections.HasFlag(ReportSections.General))
            {
                rows.Add(("Archivo", s.SourceName)); rows.Add(("Integridad", s.Integrity));
                if (!string.IsNullOrWhiteSpace(s.Discipline)) rows.Add(("Modalidad", s.Discipline));
            }
            KeyValues(rows);
            Tiles(new[]
            {
                ("Distancia", Num(whole?.DistanceM / 1000, "0.00", " km")),
                ("Vel. media", Num(whole?.MeanSpeedKmh, "0.0", " km/h")),
                ("Vel. máxima", Num(whole?.MaxSpeedKmh, "0.0", " km/h")),
                ("RTK FIX", Num(whole is null ? null : whole.FixFraction * 100, "0", " %")),
            });
        }

        if (d.Sections.HasFlag(ReportSections.Map) && tl.Count > 1)
        {
            Title("Mapa del recorrido (velocidad filtrada)");
            Ensure(300);
            DrawRoute(pdf, tl, M, y, W, 280);
            y += 288;
            pdf.Text(M, y, "Escala de velocidad azul → cian → amarillo → rojo (igual que Android). Posiciones del chaleco GNSS del jinete.", 7.5, false, Dim);
            y += 14;
        }

        if (d.Sections.HasFlag(ReportSections.GnssStats))
        {
            Title("Calidad GNSS / RTK");
            var dist = GnssQuality.Distribution(s.GnssEpochs);
            KeyValues(
            [
                ("Épocas recibidas", s.GnssSamples.ToString(Es)),
                ("RTK FIX", Num(dist[GnssSolution.RtkFix], "0.0", " %")),
                ("RTK FLOAT", Num(dist[GnssSolution.RtkFloat], "0.0", " %")),
                ("DGNSS", Num(dist[GnssSolution.Dgnss], "0.0", " %")),
                ("Autónomo", Num(dist[GnssSolution.Autonomous], "0.0", " %")),
                ("Sin solución válida", Num(dist[GnssSolution.None], "0.0", " %")),
                ("Satélites (mediana)", tl.Count > 0 ? Stats.Median(tl.NumSv.Select(x => (double)x)).ToString("0", Es) : "Sin datos"),
                ("Precisión horizontal reportada (mediana)", tl.Count > 0 ? Num(Stats.Median(tl.HAcc), "0.000", " m") : "Sin datos"),
                ("Pérdidas de señal", $"{tl.Losses.Count} intervalos · {TimeText.Clock(tl.Losses.Sum(l => l.DurationS))}"),
                ("Saltos de posición descartados", tl.JumpBefore.Count(x => x).ToString(Es)),
            ]);
            y += pdf.Paragraph(M, y, W, "La precisión horizontal es la estimada por el receptor (hAcc), no un error verificado. RTK FIX no garantiza por sí mismo precisión centimétrica ni un error de velocidad determinado.", 7.5, false, Dim);
        }

        if (d.Sections.HasFlag(ReportSections.SpeedAccel) && whole is not null)
        {
            Title("Velocidades y aceleraciones");
            KeyValues(
            [
                ("Velocidad máxima (filtrada)", Num(whole.MaxSpeedKmh, "0.0", " km/h")),
                ("Velocidad máxima reportada (sin filtrar)", Num(Stats.MaxFinite(tl.SpeedReported) * 3.6, "0.0", " km/h")),
                ("Velocidad media en movimiento", Num(whole.MeanSpeedKmh, "0.0", " km/h")),
                ("Aceleración máxima validada", Num(whole.MaxAccel, "0.00", " m/s²")),
                ("Desaceleración máxima validada", Num(whole.MaxDecel, "0.00", " m/s²")),
                ("Cambios de banda de velocidad", whole.SpeedChanges.ToString(Es)),
                ("Filtro", tl.FilterParameters.Describe()),
            ]);
        }

        if (d.Sections.HasFlag(ReportSections.Charts) && tl.Count > 1)
        {
            Title("Gráficas");
            Ensure(150);
            Chart(pdf, "Velocidad (km/h) — filtrada (rojo) y reportada (gris)", tl.T, [tl.SpeedFiltered.Select(v => v * 3.6).ToArray(), tl.SpeedReported.Select(v => v * 3.6).ToArray()],
                [Red, (0xA0, 0xA1, 0xA8)], M, y, W, 120, tl.BreakBefore);
            y += 136;
            Ensure(150);
            Chart(pdf, "Aceleración longitudinal (m/s²)", tl.T, [tl.AccelLong], [Blue], M, y, W, 110, tl.BreakBefore);
            y += 126;
            if (tl.AltitudeMsl.Any(double.IsFinite))
            {
                Ensure(140);
                Chart(pdf, "Altitud GNSS sobre el nivel del mar (m)", tl.T, [tl.AltitudeMsl], [(0x52, 0xDD, 0x40)], M, y, W, 90, tl.BreakBefore);
                y += 106;
            }
        }

        if (d.Sections.HasFlag(ReportSections.Segments))
        {
            Title("Tramos");
            if (d.Segments.Count == 0) { pdf.Text(M, y, "No hay tramos guardados para esta sesión.", 9, false, Dim); y += 16; }
            else
            {
                string[] head = ["Tramo", "Inicio", "Fin", "Dist.", "Dur.", "V. máx", "V. media", "Acel. máx", "Desac. máx", "FIX"];
                double[] cols = [120, 40, 40, 44, 40, 44, 46, 44, 46, 32];
                Table(head, cols, d.Segments.Select(m => new[]
                {
                    m.Name, TimeText.Clock(m.T0), TimeText.Clock(m.T1), Num(m.DistanceM, "0", " m"), TimeText.Clock(m.DurationS),
                    Num(m.MaxSpeedKmh, "0.0"), Num(m.MeanSpeedKmh, "0.0"), Num(m.MaxAccel, "0.00"), Num(m.MaxDecel, "0.00"), Num(m.FixFraction * 100, "0", "%"),
                }).ToList());
                pdf.Text(M, y, "Velocidades en km/h, aceleraciones en m/s² (solo épocas validadas).", 7.5, false, Dim); y += 12;
            }
        }

        if (d.Sections.HasFlag(ReportSections.Biomechanics))
        {
            Title("Biomecánica (cincha)");
            var e = d.Engine;
            if (e is null || !e.HasImu)
                y += pdf.Paragraph(M, y, W, "Sin datos de cincha en esta sesión: no se calculan cadencia, regularidad ni simetría. Ningún valor se estima sin datos.", 9, false, Dim);
            else
            {
                KeyValues(
                [
                    ("Cadencia media", Num(e.Metric("cadencia_media_imu0"), "0", " ciclos/min")),
                    ("Correlación entre ciclos", Num(e.Metric("correlacion_entre_ciclos_imu0"), "0.00")),
                    ("Variabilidad de intervalos (CV)", Num(e.Metric("variabilidad_intervalos_imu0"), "0.000")),
                    ("Estabilidad espectral", Num(e.Metric("estabilidad_espectral_imu0"), "0.00")),
                    ("Simetría", (e.SymmetryLabel.Length > 0 ? e.SymmetryLabel : "—") + (e.SymmetryAllowed ? " (exploratoria)" : " (no concluyente)")),
                ]);
                y += pdf.Paragraph(M, y, W, "Índices calculados por el motor AVO Equine Intelligence a partir de IMU sin calibrar. Son estimaciones exploratorias: no son diagnóstico clínico, carga de extremidad ni lesión.", 7.5, false, Dim);
            }
        }

        if (d.Sections.HasFlag(ReportSections.Comparison) && d.Comparison.Count > 0)
        {
            Title("Comparativa");
            string[] head = ["Entrenamiento", "Distancia", "Duración", "V. media", "V. máx", "Acel. máx", "FIX", "Cadencia"];
            double[] cols = [150, 50, 50, 50, 50, 50, 40, 50];
            Table(head, cols, d.Comparison.Select(c => new[]
            {
                c.Label, Num(c.DistanceKm, "0.00", " km"), TimeText.Clock(c.DurationS), Num(c.MeanSpeedKmh, "0.0"), Num(c.MaxSpeedKmh, "0.0"),
                Num(c.MaxAccel, "0.00"), Num(c.FixPercent, "0", "%"), Num(c.Cadence, "0"),
            }).ToList());
        }

        if (d.Sections.HasFlag(ReportSections.Tides))
        {
            Title("Mareas y entorno");
            var t0 = tl.Utc0 ?? s.StartedAt;
            if (d.Tides is null && d.Weather is null) { pdf.Text(M, y, "No disponible: no se consultaron fuentes de mareas ni meteorología.", 9, false, Dim); y += 16; }
            if (d.Tides is TidePrediction tp && t0 is DateTimeOffset ut)
            {
                KeyValues(
                [
                    ("Fuente", tp.Source), ("Tipo de dato", "Predicción (no medición)"),
                    ("Puerto de referencia", $"{tp.Port.Name} · a {Num(tp.PortDistanceKm, "0.0", " km")} de la zona de entrenamiento"),
                    ("Altura al inicio", Num(tp.HeightAt(ut), "0.00", " m (cero hidrográfico)")),
                    ("Tendencia", tp.TrendAt(ut) ?? "Sin datos"), ("Coeficiente aproximado", Num(tp.CoefficientAt(ut), "0")),
                ]);
            }
            if (d.Weather is WeatherModel wm && t0 is DateTimeOffset ut2)
            {
                var h = wm.At(ut2);
                KeyValues(
                [
                    ("Fuente", wm.Source), ("Tipo de dato", "Modelo numérico (no medición)"),
                    ("Temperatura", Num(h?.TemperatureC, "0.0", " °C")), ("Viento", Num(h?.WindKmh, "0", " km/h") + (h?.WindDirDeg is double wd ? $" ({wd:0}°)" : "")),
                    ("Presión", Num(h?.PressureHpa, "0", " hPa")), ("Oleaje", Num(h?.WaveHeightM, "0.0", " m")),
                ]);
            }
            y += pdf.Paragraph(M, y, W, "Las mareas son predicciones de un puerto de referencia y no mediciones en la playa. Las comparaciones con el rendimiento son exploratorias y no demuestran relaciones causales.", 7.5, false, Dim);
        }

        if (d.Sections.HasFlag(ReportSections.Notes) && !string.IsNullOrWhiteSpace(d.Notes))
        {
            Title("Notas y observaciones");
            y += pdf.Paragraph(M, y, W, d.Notes, 9.5);
        }
        pdf.Save(output);

        void KeyValues(IReadOnlyList<(string k, string v)> rows)
        {
            foreach (var (k, v) in rows)
            {
                Ensure(16);
                pdf.Text(M, y, k, 9, false, Dim);
                double used = pdf.Paragraph(M + 190, y, W - 190, v, 9, true, Ink, 1.25);
                y += Math.Max(14, used + 2);
            }
            y += 4;
        }

        void Tiles(IReadOnlyList<(string label, string value)> tiles)
        {
            Ensure(56);
            double tw = (W - 10 * (tiles.Count - 1)) / tiles.Count;
            for (int i = 0; i < tiles.Count; i++)
            {
                double x = M + i * (tw + 10);
                pdf.FillRect(x, y, tw, 48, Panel);
                pdf.FillRect(x, y, 3, 48, Red);
                pdf.Text(x + 10, y + 8, tiles[i].label.ToUpperInvariant(), 7.5, true, Dim);
                pdf.Text(x + 10, y + 22, tiles[i].value, 15, true, Ink);
            }
            y += 58;
        }

        void Table(string[] head, double[] cols, List<string[]> rows)
        {
            double scale = W / cols.Sum();
            var cw = cols.Select(c => c * scale).ToArray();
            void HeadRow()
            {
                Ensure(18);
                pdf.FillRect(M, y, W, 16, Dark);
                double x = M + 4;
                for (int i = 0; i < head.Length; i++) { pdf.Text(x, y + 4, head[i], 7.5, true, White); x += cw[i]; }
                y += 18;
            }
            HeadRow();
            int r = 0;
            foreach (var row in rows)
            {
                if (y + 15 > pdf.Height - 50) { Header(); HeadRow(); }
                if (r++ % 2 == 1) pdf.FillRect(M, y - 1, W, 14, Panel);
                double x = M + 4;
                for (int i = 0; i < head.Length && i < row.Length; i++)
                {
                    string cell = row[i];
                    while (cell.Length > 3 && PdfDocument.MeasureText(cell, 7.5, false) > cw[i] - 6) cell = cell[..^2];
                    pdf.Text(x, y + 2, cell, 7.5, false, Ink);
                    x += cw[i];
                }
                y += 14;
            }
            y += 6;
        }
    }

    private static void DrawRoute(PdfDocument pdf, SessionTimeline tl, double x, double y, double w, double h)
    {
        pdf.FillRect(x, y, w, h, (0xEC, 0xED, 0xF0));
        pdf.StrokeRect(x, y, w, h, Line);
        var pts = Enumerable.Range(0, tl.Count).Select(i => (lat: tl.Lat[i], lon: tl.Lon[i])).ToArray();
        double minLat = pts.Min(p => p.lat), maxLat = pts.Max(p => p.lat), minLon = pts.Min(p => p.lon), maxLon = pts.Max(p => p.lon);
        double zoom = TileMath.FitZoom(minLat, minLon, maxLat, maxLon, w, h, 24);
        var c0 = TileMath.LatLonToPixel((minLat + maxLat) / 2, (minLon + maxLon) / 2, zoom);
        (double, double) P(int i)
        {
            var p = TileMath.LatLonToPixel(tl.Lat[i], tl.Lon[i], zoom);
            return (x + w / 2 + (p.x - c0.x), y + h / 2 + (p.y - c0.y));
        }
        double vmax = Math.Max(0.1, Stats.MaxFinite(tl.SpeedFiltered, 0.1));
        for (int i = 1; i < tl.Count; i++)
        {
            if (tl.BreakBefore[i] || tl.JumpBefore[i]) continue;
            var a = P(i - 1); var b = P(i);
            pdf.Line(a.Item1, a.Item2, b.Item1, b.Item2, SpeedScale.Color(tl.SpeedFiltered[i], vmax), 2.2);
        }
        var s0 = P(0); var s1 = P(tl.Count - 1);
        pdf.Circle(s0.Item1, s0.Item2, 4.5, (0x52, 0xDD, 0x40));
        pdf.Circle(s1.Item1, s1.Item2, 4.5, Red);
        pdf.Text(s0.Item1 + 7, s0.Item2 - 5, "Inicio", 7.5, true, Ink);
        pdf.Text(s1.Item1 + 7, s1.Item2 - 5, "Fin", 7.5, true, Ink);
        // scale bar
        double mpp = TileMath.MetersPerPixel((minLat + maxLat) / 2, zoom);
        double target = mpp * 100;
        double nice = new[] { 10, 20, 50, 100, 200, 500, 1000, 2000, 5000 }.Select(v => (double)v).OrderBy(v => Math.Abs(v - target)).First();
        double px = nice / mpp;
        pdf.FillRect(x + 12, y + h - 18, px, 3, Ink);
        pdf.Text(x + 12, y + h - 32, nice >= 1000 ? $"{nice / 1000:0} km" : $"{nice:0} m", 7.5, true, Ink);
        pdf.Text(x + w - 14, y + 10, "N", 10, true, Ink, PdfDocument.Align.Center);
        pdf.Line(x + w - 14, y + 24, x + w - 14, y + 40, Ink, 1.2);
    }

    private static void Chart(PdfDocument pdf, string title, double[] t, double[][] series, (byte, byte, byte)[] colors, double x, double y, double w, double h, bool[] breaks)
    {
        pdf.Text(x, y, title, 8.5, true, Ink);
        double top = y + 14, ch = h - 14;
        pdf.FillRect(x, top, w, ch, (0xF7, 0xF7, 0xF9));
        double t0 = t[0], t1 = t[^1];
        double lo = series.Min(s => Stats.MinFinite(s, 0)), hi = series.Max(s => Stats.MaxFinite(s, 1));
        if (hi - lo < 1e-6) { hi += 1; lo -= 1; }
        double pad = (hi - lo) * 0.08; lo -= pad; hi += pad;
        for (int g = 0; g <= 4; g++)
        {
            double gy = top + ch * g / 4;
            pdf.Line(x, gy, x + w, gy, Line, 0.3);
            pdf.Text(x + 2, gy - (g == 0 ? -1 : 9), (hi - (hi - lo) * g / 4).ToString("0.#", Es), 6.5, false, Dim);
        }
        for (int si = series.Length - 1; si >= 0; si--)
        {
            var idx = Downsampler.Lttb(t, series[si], 900);
            var pts = new List<(double, double)>(idx.Length + 8);
            int prev = -1;
            foreach (int i in idx)
            {
                if (prev >= 0 && Enumerable.Range(prev + 1, i - prev).Any(k => breaks[k])) pts.Add((double.NaN, double.NaN));
                pts.Add((x + (t[i] - t0) / Math.Max(t1 - t0, 1e-6) * w, top + (hi - series[si][i]) / (hi - lo) * ch));
                prev = i;
            }
            pdf.Polyline(pts, colors[si], si == 0 ? 1.1 : 0.7);
        }
        pdf.Text(x + w, top + ch + 2, TimeText.Clock(t1 - t0), 6.5, false, Dim, PdfDocument.Align.Right);
        pdf.Text(x, top + ch + 2, "0:00", 6.5, false, Dim);
    }

    // ------------------------------------------------------------------------------------------------ HTML (printable)
    public static string Html(ReportData d)
    {
        static string E(string? s) => WebUtility.HtmlEncode(s ?? "—");
        var s = d.Session; var tl = d.Timeline;
        var whole = tl.Count >= 2 ? SegmentAnalyzer.Compute(tl, new SegmentDefinition { Name = "Sesión", T0 = tl.T[0], T1 = tl.T[^1] }, d.Engine) : null;
        var sb = new StringBuilder();
        sb.Append("<!doctype html><html lang=\"es\"><head><meta charset=\"utf-8\"><title>AVO Performance Horse · Informe</title><style>")
          .Append("body{font:14px 'Segoe UI',Arial,sans-serif;color:#101014;margin:0}header{background:#101014;color:#fff;padding:22px 40px;border-bottom:4px solid #ED122A}")
          .Append("header b{font-size:34px;letter-spacing:2px}header span{color:#C9CBD1;margin-left:14px;font-weight:600}main{padding:10px 40px 40px}h2{color:#ED122A;font-size:15px;text-transform:uppercase;border-bottom:1px solid #D8D9DE;padding-bottom:6px;margin-top:28px}")
          .Append(".tiles{display:grid;grid-template-columns:repeat(4,1fr);gap:12px}.tile{background:#F3F3F5;border-left:4px solid #ED122A;padding:10px 14px}.tile small{color:#5B5C63;text-transform:uppercase;font-weight:700;font-size:11px}.tile div{font-size:24px;font-weight:700}")
          .Append("table{border-collapse:collapse;width:100%;font-size:12px}th{background:#101014;color:#fff;text-align:left;padding:6px}td{padding:5px 6px;border-bottom:1px solid #E4E4E8}.kv td:first-child{color:#5B5C63;width:38%}")
          .Append(".note{color:#5B5C63;font-size:12px}.demo{background:#FFF1C9;color:#7A5200;padding:8px 12px;font-weight:700;margin-top:12px}svg{background:#F3F3F5;width:100%;height:auto}@media print{header{-webkit-print-color-adjust:exact;print-color-adjust:exact}}</style></head><body>")
          .Append("<header><b>AVO</b><span>PERFORMANCE HORSE · Informe de entrenamiento</span><div style=\"float:right;text-align:right;color:#C9CBD1\">")
          .Append(E(MadridTime.Format(tl.Utc0 ?? s.StartedAt))).Append(" (Europe/Madrid)<br>Sesión ").Append(E(s.SessionId)).Append("</div></header><main>");
        if (s.IsSynthetic) sb.Append("<div class=\"demo\">DEMOSTRACIÓN — DATOS SINTÉTICOS. No corresponde a un entrenamiento medido.</div>");
        sb.Append("<h2>Datos generales</h2><table class=\"kv\">")
          .Append(Kv("Caballo", s.Horse)).Append(Kv("Jinete", s.Rider)).Append(Kv("Fecha", MadridTime.Format(tl.Utc0 ?? s.StartedAt, "dddd dd/MM/yyyy HH:mm")))
          .Append(Kv("Duración", TimeText.Clock(tl.Count > 1 ? tl.DurationS : s.DurationSeconds))).Append(Kv("Integridad", s.Integrity)).Append("</table>");
        sb.Append("<div class=\"tiles\" style=\"margin-top:14px\">")
          .Append(Tile("Distancia", Num(whole?.DistanceM / 1000, "0.00", " km"))).Append(Tile("Vel. media", Num(whole?.MeanSpeedKmh, "0.0", " km/h")))
          .Append(Tile("Vel. máxima", Num(whole?.MaxSpeedKmh, "0.0", " km/h"))).Append(Tile("RTK FIX", Num(whole is null ? null : whole.FixFraction * 100, "0", " %"))).Append("</div>");
        if (d.Sections.HasFlag(ReportSections.Map) && tl.Count > 1) sb.Append("<h2>Recorrido</h2>").Append(RouteSvg(tl)).Append("<p class=\"note\">Posiciones del chaleco GNSS del jinete; color por velocidad filtrada (azul → cian → amarillo → rojo).</p>");
        if (d.Sections.HasFlag(ReportSections.Segments) && d.Segments.Count > 0)
        {
            sb.Append("<h2>Tramos</h2><table><tr><th>Tramo</th><th>Inicio</th><th>Fin</th><th>Distancia</th><th>Duración</th><th>V. máx</th><th>V. media</th><th>Acel. máx</th><th>Desac. máx</th><th>RTK FIX</th><th>Observaciones</th></tr>");
            foreach (var m in d.Segments)
                sb.Append("<tr><td>").Append(E(m.Name)).Append("</td><td>").Append(TimeText.Clock(m.T0)).Append("</td><td>").Append(TimeText.Clock(m.T1)).Append("</td><td>")
                  .Append(Num(m.DistanceM, "0", " m")).Append("</td><td>").Append(TimeText.Clock(m.DurationS)).Append("</td><td>").Append(Num(m.MaxSpeedKmh, "0.0", " km/h"))
                  .Append("</td><td>").Append(Num(m.MeanSpeedKmh, "0.0", " km/h")).Append("</td><td>").Append(Num(m.MaxAccel, "0.00", " m/s²")).Append("</td><td>")
                  .Append(Num(m.MaxDecel, "0.00", " m/s²")).Append("</td><td>").Append(Num(m.FixFraction * 100, "0", " %")).Append("</td><td>").Append(E(m.Observations)).Append("</td></tr>");
            sb.Append("</table>");
        }
        if (d.Sections.HasFlag(ReportSections.Biomechanics))
        {
            sb.Append("<h2>Biomecánica</h2>");
            if (d.Engine is null || !d.Engine.HasImu) sb.Append("<p>Sin datos de cincha: no se calculan cadencia, regularidad ni simetría.</p>");
            else sb.Append("<table class=\"kv\">").Append(Kv("Cadencia media", Num(d.Engine.Metric("cadencia_media_imu0"), "0", " ciclos/min")))
                   .Append(Kv("Correlación entre ciclos", Num(d.Engine.Metric("correlacion_entre_ciclos_imu0"), "0.00")))
                   .Append(Kv("Simetría (exploratoria)", d.Engine.SymmetryLabel)).Append("</table><p class=\"note\">Índices exploratorios de IMU sin calibrar; no son diagnóstico clínico.</p>");
        }
        if (d.Sections.HasFlag(ReportSections.Tides) && (d.Tides is not null || d.Weather is not null))
        {
            sb.Append("<h2>Mareas y entorno</h2><table class=\"kv\">");
            var t0 = tl.Utc0 ?? s.StartedAt;
            if (d.Tides is TidePrediction tp && t0 is DateTimeOffset u)
                sb.Append(Kv("Marea (predicción)", $"{Num(tp.HeightAt(u), "0.00", " m")} · {tp.TrendAt(u) ?? "sin datos"} · {tp.Port.Name} ({tp.Source})"));
            if (d.Weather is WeatherModel wm && t0 is DateTimeOffset u2 && wm.At(u2) is WeatherHour h)
                sb.Append(Kv("Meteorología (modelo)", $"{Num(h.TemperatureC, "0.0", " °C")} · viento {Num(h.WindKmh, "0", " km/h")} · {Num(h.PressureHpa, "0", " hPa")} · oleaje {Num(h.WaveHeightM, "0.0", " m")} ({wm.Source})"));
            sb.Append("</table>");
        }
        if (d.Sections.HasFlag(ReportSections.Notes) && !string.IsNullOrWhiteSpace(d.Notes)) sb.Append("<h2>Notas</h2><p>").Append(E(d.Notes).Replace("\n", "<br>")).Append("</p>");
        sb.Append("<p class=\"note\" style=\"margin-top:30px\">GNSS del chaleco del jinete; no es un punto anatómico del caballo. Generado por AVO Performance Horse — Windows Advanced Analysis V2 PRO.</p></main></body></html>");
        return sb.ToString();

        static string Kv(string k, string v) => $"<tr><td>{WebUtility.HtmlEncode(k)}</td><td><b>{WebUtility.HtmlEncode(v)}</b></td></tr>";
        static string Tile(string k, string v) => $"<div class=\"tile\"><small>{WebUtility.HtmlEncode(k)}</small><div>{WebUtility.HtmlEncode(v)}</div></div>";
    }

    public static string RouteSvg(SessionTimeline tl, int w = 900, int h = 420)
    {
        var inv = CultureInfo.InvariantCulture;
        double minLat = tl.Lat.Min(), maxLat = tl.Lat.Max(), minLon = tl.Lon.Min(), maxLon = tl.Lon.Max();
        double zoom = TileMath.FitZoom(minLat, minLon, maxLat, maxLon, w, h, 24);
        var c0 = TileMath.LatLonToPixel((minLat + maxLat) / 2, (minLon + maxLon) / 2, zoom);
        double vmax = Math.Max(0.1, Stats.MaxFinite(tl.SpeedFiltered, 0.1));
        var sb = new StringBuilder($"<svg viewBox=\"0 0 {w} {h}\" xmlns=\"http://www.w3.org/2000/svg\">");
        for (int i = 1; i < tl.Count; i++)
        {
            if (tl.BreakBefore[i] || tl.JumpBefore[i]) continue;
            var a = TileMath.LatLonToPixel(tl.Lat[i - 1], tl.Lon[i - 1], zoom); var b = TileMath.LatLonToPixel(tl.Lat[i], tl.Lon[i], zoom);
            var (r, g, bl) = SpeedScale.Color(tl.SpeedFiltered[i], vmax);
            sb.Append(string.Format(inv, "<line x1=\"{0:0.#}\" y1=\"{1:0.#}\" x2=\"{2:0.#}\" y2=\"{3:0.#}\" stroke=\"#{4:X2}{5:X2}{6:X2}\" stroke-width=\"3\" stroke-linecap=\"round\"/>",
                w / 2.0 + a.x - c0.x, h / 2.0 + a.y - c0.y, w / 2.0 + b.x - c0.x, h / 2.0 + b.y - c0.y, r, g, bl));
        }
        sb.Append("</svg>");
        return sb.ToString();
    }
}
