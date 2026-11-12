using System.Globalization;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;

namespace Avo.Windows;

/// <summary>Engine series drawn on the same index axis as the GNSS track charts (shared selection).</summary>
public sealed class EngineChart : FrameworkElement
{
    private double[] _values = [];
    private int[] _codes = [];
    private int _selected = -1;
    public string Title { get; set; } = "";
    public string Unit { get; set; } = "";
    public Color Stroke { get; set; } = Color.FromRgb(245, 196, 44);
    public string EmptyText { get; set; } = "Sin datos del motor";
    public double[] Values { get => _values; set { _values = value; InvalidateVisual(); } }
    /// <summary>Gait codes per track point (strip mode when non-empty).</summary>
    public int[] Codes { get => _codes; set { _codes = value; InvalidateVisual(); } }
    public int SelectedIndex { get => _selected; set { _selected = value; InvalidateVisual(); } }
    public event Action<int>? PointSelected;
    private static readonly Typeface Font = new("Segoe UI");
    private static readonly Brush Label = new SolidColorBrush(Color.FromRgb(152, 182, 201));
    private static readonly Pen GridPen = new(new SolidColorBrush(Color.FromRgb(40, 70, 92)), 1);

    public EngineChart() { MinHeight = 40; Cursor = Cursors.Cross; MouseLeftButtonDown += OnClick; }

    private int Count => Math.Max(_values.Length, _codes.Length);

    private void OnClick(object sender, MouseButtonEventArgs e)
    {
        if (Count < 1) return;
        double frac = Math.Clamp((e.GetPosition(this).X - 60) / Math.Max(1, ActualWidth - 82), 0, 1);
        SelectedIndex = (int)Math.Round(frac * (Count - 1));
        PointSelected?.Invoke(SelectedIndex);
    }

    public static Color GaitColor(int code) => code switch
    {
        0 => Color.FromRgb(110, 111, 118), 1 => Color.FromRgb(61, 155, 255), 2 => Color.FromRgb(255, 196, 44), 3 => Color.FromRgb(237, 18, 42),
        4 => Color.FromRgb(176, 124, 255), 5 => Color.FromRgb(58, 59, 66), _ => Color.FromRgb(30, 31, 36)
    };

    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc);
        double w = ActualWidth, h = ActualHeight;
        dc.DrawRectangle(new SolidColorBrush(Color.FromRgb(12, 34, 51)), null, new Rect(0, 0, w, h));
        Text(dc, Title + (Unit.Length > 0 ? $" ({Unit})" : ""), 11, 6, Brushes.White, 12);
        double x0 = 58, y0 = 26, pw = Math.Max(10, w - 80), ph = Math.Max(8, h - 40);
        int n = Count;
        if (n < 2) { Text(dc, EmptyText, x0 + 6, y0 + ph / 2 - 8, Label, 13); return; }
        double X(int i) => x0 + pw * i / (n - 1);
        if (_codes.Length > 0)
        {
            for (int i = 0; i + 1 < _codes.Length; i++)
                if (_codes[i] >= 0) dc.DrawRectangle(new SolidColorBrush(GaitColor(_codes[i])), null, new Rect(X(i), y0, Math.Max(1, X(i + 1) - X(i) + 0.5), ph));
        }
        else
        {
            var finite = _values.Where(double.IsFinite).ToArray();
            if (finite.Length < 2) { Text(dc, EmptyText, x0 + 6, y0 + ph / 2 - 8, Label, 13); return; }
            double lo = Math.Min(0, finite.Min()), hi = Math.Max(finite.Max(), lo + 1e-3);
            double Y(double v) => y0 + ph * (1 - (v - lo) / (hi - lo));
            for (int k = 0; k <= 3; k++) { double y = y0 + ph * k / 3; dc.DrawLine(GridPen, new Point(x0, y), new Point(x0 + pw, y)); Text(dc, (hi - (hi - lo) * k / 3).ToString("0.##", CultureInfo.InvariantCulture), 6, y - 8, Label, 10); }
            var pen = new Pen(new SolidColorBrush(Stroke), 1.6);
            var geo = new StreamGeometry();
            using (var ctx = geo.Open())
            {
                bool open = false;
                for (int i = 0; i < _values.Length; i++)
                {
                    if (!double.IsFinite(_values[i])) { open = false; continue; }
                    var p = new Point(X(i), Y(_values[i]));
                    if (!open) { ctx.BeginFigure(p, false, false); open = true; } else ctx.LineTo(p, true, false);
                }
            }
            geo.Freeze();
            dc.DrawGeometry(null, pen, geo);
        }
        if (_selected >= 0 && _selected < n) dc.DrawLine(new Pen(Brushes.White, 1), new Point(X(_selected), y0), new Point(X(_selected), y0 + ph));
    }

    private void Text(DrawingContext dc, string s, double x, double y, Brush b, double size) =>
        dc.DrawText(new FormattedText(s, CultureInfo.CurrentCulture, FlowDirection.LeftToRight, Font, size, b, VisualTreeHelper.GetDpi(this).PixelsPerDip), new Point(x, y));
}
