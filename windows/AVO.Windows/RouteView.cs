using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using Avo.Windows.Core;

namespace Avo.Windows;

/// <summary>Offline, georeferenced route visualization; mouse wheel zoom and drag pan.</summary>
public sealed class RouteView : FrameworkElement
{
    private TrainingSession? _session;
    private int _selected = -1;
    private double _zoom = 1, _panX, _panY;
    private Point? _drag;
    private static readonly Typeface Font = new("Segoe UI");
    public TrainingSession? Session { get => _session; set { _session = value; _zoom = 1; _panX = _panY = 0; InvalidateVisual(); } }
    public int SelectedIndex { get => _selected; set { _selected = value; InvalidateVisual(); } }
    public RouteView()
    {
        ClipToBounds = true; Cursor = Cursors.SizeAll;
        MouseWheel += (_, e) => { _zoom = Math.Clamp(_zoom * (e.Delta > 0 ? 1.2 : 1 / 1.2), 0.5, 120); InvalidateVisual(); };
        MouseLeftButtonDown += (_, e) => { _drag = e.GetPosition(this); CaptureMouse(); };
        MouseLeftButtonUp += (_, _) => { _drag = null; ReleaseMouseCapture(); };
        MouseMove += (_, e) => { if (_drag is not { } old) return; var next = e.GetPosition(this); _panX += next.X - old.X; _panY += next.Y - old.Y; _drag = next; InvalidateVisual(); };
    }
    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc);
        double w = ActualWidth, h = ActualHeight;
        dc.DrawRectangle(new SolidColorBrush(Color.FromRgb(13, 37, 51)), null, new Rect(0, 0, w, h));
        var dotPen = new Pen(new SolidColorBrush(Color.FromRgb(35, 69, 82)), 1);
        for (int x = 0; x < w; x += 58) dc.DrawLine(dotPen, new Point(x, 0), new Point(x, h));
        for (int y = 0; y < h; y += 58) dc.DrawLine(dotPen, new Point(0, y), new Point(w, y));
        var track = Session?.Track;
        if (track is not { Count: > 0 })
        {
            Print(dc, "MAPA GNSS", 25, 26, Brushes.White, 25);
            Print(dc, "Importa datos con posiciones reales para mostrar el recorrido", 25, 68, Brushes.LightSteelBlue, 15);
            return;
        }
        double centerLat = (track.Min(t => t.Latitude) + track.Max(t => t.Latitude)) / 2;
        double centerLon = (track.Min(t => t.Longitude) + track.Max(t => t.Longitude)) / 2;
        double mLat = 111195, mLon = 111195 * Math.Cos(centerLat * Math.PI / 180);
        double maxX = track.Max(t => Math.Abs((t.Longitude - centerLon) * mLon));
        double maxY = track.Max(t => Math.Abs((t.Latitude - centerLat) * mLat));
        double pxPerMeter = Math.Min(w * .85 / Math.Max(40, 2 * maxX), h * .77 / Math.Max(40, 2 * maxY)) * _zoom;
        Point ToPoint(TrackPoint p) => new(w / 2 + _panX + (p.Longitude - centerLon) * mLon * pxPerMeter,
                                           h / 2 + _panY - (p.Latitude - centerLat) * mLat * pxPerMeter);
        for (int i = 1; i < track.Count; i++)
        {
            double speed = track[i].SpeedKmh;
            Color color = speed < 12 ? Color.FromRgb(24, 210, 144) : speed < 24 ? Color.FromRgb(175, 220, 69) :
                speed < 37 ? Color.FromRgb(246, 179, 42) : Color.FromRgb(238, 69, 64);
            var pen = new Pen(new SolidColorBrush(color), 3.5);
            dc.DrawLine(pen, ToPoint(track[i - 1]), ToPoint(track[i]));
        }
        dc.DrawEllipse(new SolidColorBrush(Color.FromRgb(42, 231, 143)), new Pen(Brushes.White, 2), ToPoint(track[0]), 8, 8);
        dc.DrawEllipse(new SolidColorBrush(Color.FromRgb(240, 98, 72)), new Pen(Brushes.White, 2), ToPoint(track[^1]), 8, 8);
        if (_selected >= 0 && _selected < track.Count)
            dc.DrawEllipse(Brushes.White, new Pen(new SolidColorBrush(Color.FromRgb(20, 150, 233)), 4), ToPoint(track[_selected]), 7, 7);
        dc.DrawRectangle(new SolidColorBrush(Color.FromArgb(215, 5, 20, 32)), null, new Rect(13, 12, 286, 54));
        Print(dc, "RECORRIDO GNSS · MAPA VECTORIAL", 22, 19, Brushes.White, 13);
        Print(dc, "Zoom rueda · mover arrastrando", 22, 41, Brushes.LightBlue, 11);
        dc.DrawRectangle(new SolidColorBrush(Color.FromArgb(215, 5, 20, 32)), null, new Rect(14, h - 45, 420, 32));
        Print(dc, "COLOR: 0–12 verde · 12–24 lima · 24–37 naranja · +37 rojo (km/h)", 23, h - 37, Brushes.LightGray, 11);
        Print(dc, "N", w - 45, 15, Brushes.White, 17);
        Print(dc, "SIN IMAGINERÍA SATELITAL · coordenadas originales", w - 340, h - 27, Brushes.LightBlue, 10);
    }
    private void Print(DrawingContext ctx, string text, double x, double y, Brush brush, double size)
    {
        ctx.DrawText(new FormattedText(text, System.Globalization.CultureInfo.GetCultureInfo("es-ES"),
            FlowDirection.LeftToRight, Font, size, brush, VisualTreeHelper.GetDpi(this).PixelsPerDip), new Point(x, y));
    }
}
