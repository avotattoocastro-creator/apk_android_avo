using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using Avo.Windows.Core;

namespace Avo.Windows;

/// <summary>Dependency-free telemetry plot with crosshair and optional comparison series.</summary>
public sealed class TelemetryChart : FrameworkElement
{
    public TrainingSession? Session { get => _session; set { _session = value; InvalidateVisual(); } }
    public TrainingSession? Comparison { get => _comparison; set { _comparison = value; InvalidateVisual(); } }
    public bool ShowAccuracy { get => _accuracy; set { _accuracy = value; InvalidateVisual(); } }
    public int SelectedIndex { get => _selected; set { _selected = value; InvalidateVisual(); } }
    public event Action<int>? PointSelected;
    private TrainingSession? _session, _comparison;
    private bool _accuracy;
    private int _selected = -1;
    private static readonly Typeface Font = new("Segoe UI");
    private static readonly Pen GridPen = new(new SolidColorBrush(Color.FromRgb(40, 70, 92)), 1);
    private static readonly Pen MarkerPen = new(Brushes.White, 1);
    private static readonly Brush Label = new SolidColorBrush(Color.FromRgb(152, 182, 201));
    public TelemetryChart() { MinHeight = 90; Cursor = Cursors.Cross; MouseLeftButtonDown += Click; }
    private void Click(object sender, MouseButtonEventArgs e)
    {
        var n = Session?.Track.Count ?? 0;
        if (n < 1) return;
        double frac = Math.Clamp((e.GetPosition(this).X - 60) / Math.Max(1, ActualWidth - 82), 0, 1);
        SelectedIndex = (int)Math.Round(frac * (n - 1));
        PointSelected?.Invoke(SelectedIndex);
    }
    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc);
        double width = ActualWidth, height = ActualHeight;
        dc.DrawRectangle(new SolidColorBrush(Color.FromRgb(12, 34, 51)), null, new Rect(0, 0, width, height));
        var tracks = new[] { Session?.Track, Comparison?.Track }.Where(t => t is { Count: > 0 }).ToArray();
        string metric = ShowAccuracy ? "Precisión horizontal (m)" : "Velocidad (km/h)";
        DrawText(dc, metric, 11, 9, Brushes.White, 13);
        if (tracks.Length == 0) { DrawText(dc, "Importa una sesión con muestras GNSS para visualizar", 65, height / 2, Label, 14); return; }
        double minX = 58, minY = 34, plotW = Math.Max(10, width - 80), plotH = Math.Max(10, height - 62);
        double max = Math.Max(1, tracks.SelectMany(x => x!).Max(p => GetValue(p)) * 1.1);
        for (int i = 0; i <= 4; i++)
        {
            double y = minY + plotH * i / 4;
            dc.DrawLine(GridPen, new Point(minX, y), new Point(minX + plotW, y));
            DrawText(dc, (max * (1 - i / 4.0)).ToString("0.#"), 9, y - 9, Label, 11);
        }
        for (int i = 0; i <= 6; i++)
        {
            double x = minX + plotW * i / 6;
            dc.DrawLine(GridPen, new Point(x, minY), new Point(x, minY + plotH));
        }
        DrawTrace(dc, Session?.Track, minX, minY, plotW, plotH, max, Color.FromRgb(19, 184, 245));
        DrawTrace(dc, Comparison?.Track, minX, minY, plotW, plotH, max, Color.FromRgb(245, 144, 61));
        if (SelectedIndex >= 0 && Session?.Track.Count > 0)
        {
            int i = Math.Min(SelectedIndex, Session.Track.Count - 1);
            double x = minX + plotW * i / Math.Max(1, Session.Track.Count - 1);
            dc.DrawLine(MarkerPen, new Point(x, minY), new Point(x, minY + plotH));
            DrawText(dc, GetValue(Session.Track[i]).ToString("0.00"), Math.Min(x + 8, width - 80), minY + 3, Brushes.White, 13);
        }
    }
    private double GetValue(TrackPoint p) => ShowAccuracy ? p.AccuracyM : p.SpeedKmh;
    private void DrawTrace(DrawingContext dc, List<TrackPoint>? points, double x0, double y0, double w, double h, double max, Color color)
    {
        if (points is not { Count: > 0 }) return;
        var geom = new StreamGeometry();
        using (var ctx = geom.Open())
        {
            int stride = Math.Max(1, points.Count / 3500);
            bool first = true;
            for (int i = 0; i < points.Count; i += stride)
            {
                double v = GetValue(points[i]);
                var p = new Point(x0 + w * i / Math.Max(1, points.Count - 1), y0 + h * (1 - Math.Clamp(v / max, 0, 1)));
                if (first) { ctx.BeginFigure(p, false, false); first = false; }
                else ctx.LineTo(p, true, false);
            }
        }
        geom.Freeze();
        var pen = new Pen(new SolidColorBrush(color), 1.9); pen.Freeze();
        dc.DrawGeometry(null, pen, geom);
    }
    private void DrawText(DrawingContext dc, string content, double x, double y, Brush brush, double size)
    {
        var text = new FormattedText(content, System.Globalization.CultureInfo.GetCultureInfo("es-ES"),
            FlowDirection.LeftToRight, Font, size, brush, VisualTreeHelper.GetDpi(this).PixelsPerDip);
        dc.DrawText(text, new Point(x, y));
    }
}
