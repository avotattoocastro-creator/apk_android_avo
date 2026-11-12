using System.Globalization;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using Avo.Windows.Core;

namespace Avo.Windows.Controls;

/// <summary>One series of a <see cref="SignalChart"/>. X must be ascending. NaN values or Breaks[i] = true cut the line.</summary>
public sealed class ChartSeries
{
    public string Name { get; init; } = "";
    public double[] X { get; init; } = [];
    public double[] Y { get; init; } = [];
    public bool[]? Breaks { get; init; }
    public Color Color { get; init; } = Colors.White;
    public double Thickness { get; init; } = 1.4;
    public bool Dashed { get; init; }
    public string Unit { get; init; } = "";
    public string Format { get; init; } = "0.0";
}

/// <summary>Coloured background band (gait, GNSS quality, segment…).</summary>
public readonly record struct ChartBand(double X0, double X1, Color Color);

public enum AxisFormat { Clock, Number, Kilometres, HourOfDay }

/// <summary>
/// High-performance time-series chart (custom rendering, no third-party library). Interaction:
/// click = cursor, drag = pan, Shift+drag = select a range, mouse wheel = zoom, double click = full view.
/// Rendering reduces each series with LTTB to about two points per pixel; the data arrays are never modified.
/// Charts sharing XMin/XMax/CursorX/RangeStart/RangeEnd bindings stay synchronised.
/// </summary>
public sealed class SignalChart : FrameworkElement
{
    public static readonly DependencyProperty SeriesProperty = Reg(nameof(Series), typeof(IReadOnlyList<ChartSeries>), null);
    public static readonly DependencyProperty BandsProperty = Reg(nameof(Bands), typeof(IReadOnlyList<ChartBand>), null);
    public static readonly DependencyProperty XMinProperty = RegTwoWay(nameof(XMin), double.NaN);
    public static readonly DependencyProperty XMaxProperty = RegTwoWay(nameof(XMax), double.NaN);
    public static readonly DependencyProperty CursorXProperty = RegTwoWay(nameof(CursorX), double.NaN);
    public static readonly DependencyProperty RangeStartProperty = RegTwoWay(nameof(RangeStart), double.NaN);
    public static readonly DependencyProperty RangeEndProperty = RegTwoWay(nameof(RangeEnd), double.NaN);
    public static readonly DependencyProperty YMinProperty = Reg(nameof(YMin), typeof(double), double.NaN);
    public static readonly DependencyProperty YMaxProperty = Reg(nameof(YMax), typeof(double), double.NaN);
    public static readonly DependencyProperty AxisProperty = Reg(nameof(Axis), typeof(AxisFormat), AxisFormat.Clock);
    public static readonly DependencyProperty ShowXAxisProperty = Reg(nameof(ShowXAxis), typeof(bool), true);
    public static readonly DependencyProperty IncludeZeroProperty = Reg(nameof(IncludeZero), typeof(bool), false);
    public static readonly DependencyProperty EmptyTextProperty = Reg(nameof(EmptyText), typeof(string), "Sin datos");
    public static readonly DependencyProperty ShowGridProperty = Reg(nameof(ShowGrid), typeof(bool), true);
    public static readonly DependencyProperty MarkerXProperty = Reg(nameof(MarkerX), typeof(double), double.NaN);

    private static DependencyProperty Reg(string name, Type t, object? def) =>
        DependencyProperty.Register(name, t, typeof(SignalChart), new FrameworkPropertyMetadata(def, FrameworkPropertyMetadataOptions.AffectsRender));
    private static DependencyProperty RegTwoWay(string name, double def) =>
        DependencyProperty.Register(name, typeof(double), typeof(SignalChart),
            new FrameworkPropertyMetadata(def, FrameworkPropertyMetadataOptions.AffectsRender | FrameworkPropertyMetadataOptions.BindsTwoWayByDefault));

    public IReadOnlyList<ChartSeries>? Series { get => (IReadOnlyList<ChartSeries>?)GetValue(SeriesProperty); set => SetValue(SeriesProperty, value); }
    public IReadOnlyList<ChartBand>? Bands { get => (IReadOnlyList<ChartBand>?)GetValue(BandsProperty); set => SetValue(BandsProperty, value); }
    public double XMin { get => (double)GetValue(XMinProperty); set => SetValue(XMinProperty, value); }
    public double XMax { get => (double)GetValue(XMaxProperty); set => SetValue(XMaxProperty, value); }
    public double CursorX { get => (double)GetValue(CursorXProperty); set => SetValue(CursorXProperty, value); }
    public double RangeStart { get => (double)GetValue(RangeStartProperty); set => SetValue(RangeStartProperty, value); }
    public double RangeEnd { get => (double)GetValue(RangeEndProperty); set => SetValue(RangeEndProperty, value); }
    public double YMin { get => (double)GetValue(YMinProperty); set => SetValue(YMinProperty, value); }
    public double YMax { get => (double)GetValue(YMaxProperty); set => SetValue(YMaxProperty, value); }
    public AxisFormat Axis { get => (AxisFormat)GetValue(AxisProperty); set => SetValue(AxisProperty, value); }
    public bool ShowXAxis { get => (bool)GetValue(ShowXAxisProperty); set => SetValue(ShowXAxisProperty, value); }
    public bool IncludeZero { get => (bool)GetValue(IncludeZeroProperty); set => SetValue(IncludeZeroProperty, value); }
    public string EmptyText { get => (string)GetValue(EmptyTextProperty); set => SetValue(EmptyTextProperty, value); }
    public bool ShowGrid { get => (bool)GetValue(ShowGridProperty); set => SetValue(ShowGridProperty, value); }
    /// <summary>Fixed vertical marker (e.g. training time on the tide curve).</summary>
    public double MarkerX { get => (double)GetValue(MarkerXProperty); set => SetValue(MarkerXProperty, value); }

    private static readonly Brush GridBrush = Frozen(new SolidColorBrush(Color.FromArgb(0x30, 0xC9, 0xCB, 0xD1)));
    private static readonly Brush LabelBrush = Frozen(new SolidColorBrush(Color.FromRgb(0x9C, 0x9D, 0xA4)));
    private static readonly Brush RangeBrush = Frozen(new SolidColorBrush(Color.FromArgb(0x30, 0xED, 0x12, 0x2A)));
    private static readonly Pen GridPen = FrozenPen(new Pen(GridBrush, 1) { DashStyle = new DashStyle([2, 4], 0) });
    private static readonly Pen CursorPen = FrozenPen(new Pen(new SolidColorBrush(Color.FromRgb(0xF2, 0xF2, 0xF4)), 1.2));
    private static readonly Pen MarkerPen = FrozenPen(new Pen(new SolidColorBrush(Color.FromRgb(0xED, 0x12, 0x2A)), 1.5));
    private static readonly Typeface Face = new(new FontFamily("Segoe UI"), FontStyles.Normal, FontWeights.Normal, FontStretches.Normal);
    private static T Frozen<T>(T f) where T : Freezable { f.Freeze(); return f; }
    private static Pen FrozenPen(Pen p) { p.Freeze(); return p; }

    private const double LeftPad = 44, BottomPadAxis = 18, TopPad = 4, RightPad = 8;
    private Point? _down;
    private double _downXMin, _downXMax;
    private bool _dragging, _selecting;

    public event EventHandler<double>? CursorMoved;

    public SignalChart()
    {
        ClipToBounds = true;
        Focusable = true;
        Cursor = Cursors.Cross;
        SnapsToDevicePixels = true;
    }

    private (double lo, double hi) DataXRange()
    {
        double lo = double.PositiveInfinity, hi = double.NegativeInfinity;
        foreach (var s in Series ?? [])
        {
            if (s.X.Length == 0) continue;
            lo = Math.Min(lo, s.X[0]); hi = Math.Max(hi, s.X[^1]);
        }
        return double.IsFinite(lo) && hi > lo ? (lo, hi) : (0, 1);
    }

    private (double lo, double hi) ViewX()
    {
        var (dlo, dhi) = DataXRange();
        double lo = double.IsFinite(XMin) ? XMin : dlo, hi = double.IsFinite(XMax) ? XMax : dhi;
        if (hi - lo < 1e-9) hi = lo + 1;
        return (lo, hi);
    }

    private Rect Plot => new(LeftPad, TopPad, Math.Max(1, ActualWidth - LeftPad - RightPad), Math.Max(1, ActualHeight - TopPad - (ShowXAxis ? BottomPadAxis : 2)));

    private double ToPx(double x, double lo, double hi, Rect p) => p.Left + (x - lo) / (hi - lo) * p.Width;
    private double ToX(double px, double lo, double hi, Rect p) => lo + (px - p.Left) / p.Width * (hi - lo);

    protected override void OnRender(DrawingContext dc)
    {
        dc.DrawRectangle(Brushes.Transparent, null, new Rect(0, 0, ActualWidth, ActualHeight));
        var p = Plot;
        var series = Series ?? [];
        if (series.Count == 0 || series.All(s => s.Y.Length == 0 || !s.Y.Any(double.IsFinite)))
        {
            var ft = Text(EmptyText, 12, LabelBrush);
            dc.DrawText(ft, new Point(p.Left + (p.Width - ft.Width) / 2, p.Top + (p.Height - ft.Height) / 2));
            return;
        }
        var (lo, hi) = ViewX();
        // y range from the visible data
        double ymin = double.PositiveInfinity, ymax = double.NegativeInfinity;
        foreach (var s in series)
        {
            int a = Lower(s.X, lo), b = Upper(s.X, hi);
            for (int i = a; i <= b && i < s.Y.Length; i++) { double v = s.Y[i]; if (double.IsFinite(v)) { if (v < ymin) ymin = v; if (v > ymax) ymax = v; } }
        }
        if (!double.IsFinite(ymin)) { ymin = 0; ymax = 1; }
        if (IncludeZero) { ymin = Math.Min(ymin, 0); ymax = Math.Max(ymax, 0); }
        if (double.IsFinite(YMin)) ymin = YMin;
        if (double.IsFinite(YMax)) ymax = YMax;
        if (ymax - ymin < 1e-9) { ymax += 0.5; ymin -= 0.5; }
        double pad = (ymax - ymin) * 0.08;
        if (!double.IsFinite(YMax)) ymax += pad;
        if (!double.IsFinite(YMin)) ymin -= pad;

        // bands
        foreach (var band in Bands ?? [])
        {
            double x0 = Math.Max(ToPx(band.X0, lo, hi, p), p.Left), x1 = Math.Min(ToPx(band.X1, lo, hi, p), p.Right);
            if (x1 > x0) dc.DrawRectangle(new SolidColorBrush(band.Color), null, new Rect(x0, p.Bottom - 4, x1 - x0, 4));
        }
        // grid + y labels
        foreach (var yv in NiceTicks(ymin, ymax, Math.Max(2, (int)(p.Height / 34))))
        {
            double py = p.Bottom - (yv - ymin) / (ymax - ymin) * p.Height;
            if (ShowGrid) dc.DrawLine(GridPen, new Point(p.Left, py), new Point(p.Right, py));
            var ft = Text(yv.ToString(Math.Abs(ymax - ymin) < 5 ? "0.##" : "0.#", CultureInfo.GetCultureInfo("es-ES")), 10, LabelBrush);
            dc.DrawText(ft, new Point(p.Left - ft.Width - 6, py - ft.Height / 2));
        }
        if (ShowXAxis)
        {
            foreach (var xv in NiceTicks(lo, hi, Math.Max(2, (int)(p.Width / 90)), Axis == AxisFormat.Clock || Axis == AxisFormat.HourOfDay))
            {
                double px = ToPx(xv, lo, hi, p);
                if (px < p.Left - 1 || px > p.Right + 1) continue;
                if (ShowGrid) dc.DrawLine(GridPen, new Point(px, p.Top), new Point(px, p.Bottom));
                var ft = Text(FormatX(xv), 10, LabelBrush);
                dc.DrawText(ft, new Point(Math.Clamp(px - ft.Width / 2, p.Left, p.Right - ft.Width), p.Bottom + 3));
            }
        }
        // selected range
        if (double.IsFinite(RangeStart) && double.IsFinite(RangeEnd))
        {
            double a = ToPx(Math.Min(RangeStart, RangeEnd), lo, hi, p), b = ToPx(Math.Max(RangeStart, RangeEnd), lo, hi, p);
            a = Math.Max(a, p.Left); b = Math.Min(b, p.Right);
            if (b > a) dc.DrawRectangle(RangeBrush, null, new Rect(a, p.Top, b - a, p.Height));
        }
        dc.PushClip(new RectangleGeometry(p));
        int target = Math.Max(50, (int)(p.Width * 2));
        foreach (var s in series)
        {
            if (s.X.Length < 2 || s.Y.Length != s.X.Length) continue;
            int a = Math.Max(0, Lower(s.X, lo) - 1), b = Math.Min(s.X.Length - 1, Upper(s.X, hi) + 1);
            if (b <= a) continue;
            int n = b - a + 1;
            var xs = new double[n]; var ys = new double[n];
            Array.Copy(s.X, a, xs, 0, n); Array.Copy(s.Y, a, ys, 0, n);
            var idx = Downsampler.Lttb(xs, ys, target);
            var geo = new StreamGeometry();
            using (var g = geo.Open())
            {
                bool open = false; int prev = -1;
                foreach (int k in idx)
                {
                    bool brk = prev >= 0 && s.Breaks is not null && HasBreak(s.Breaks, a + prev + 1, a + k);
                    if (prev >= 0 && k - prev > 1 && HasNaN(ys, prev + 1, k - 1)) brk = true;
                    var pt = new Point(ToPx(xs[k], lo, hi, p), p.Bottom - (ys[k] - ymin) / (ymax - ymin) * p.Height);
                    if (!open || brk) { g.BeginFigure(pt, false, false); open = true; }
                    else g.LineTo(pt, true, false);
                    prev = k;
                }
            }
            geo.Freeze();
            var pen = new Pen(new SolidColorBrush(s.Color), s.Thickness) { LineJoin = PenLineJoin.Round };
            if (s.Dashed) pen.DashStyle = DashStyles.Dash;
            pen.Freeze();
            dc.DrawGeometry(null, pen, geo);
        }
        if (double.IsFinite(MarkerX))
        {
            double mx = ToPx(MarkerX, lo, hi, p);
            dc.DrawLine(MarkerPen, new Point(mx, p.Top), new Point(mx, p.Bottom));
        }
        if (double.IsFinite(CursorX))
        {
            double cx = ToPx(CursorX, lo, hi, p);
            if (cx >= p.Left && cx <= p.Right)
            {
                dc.DrawLine(CursorPen, new Point(cx, p.Top), new Point(cx, p.Bottom));
                foreach (var s in series)
                {
                    double v = ValueAt(s, CursorX);
                    if (!double.IsFinite(v)) continue;
                    double py = p.Bottom - (v - ymin) / (ymax - ymin) * p.Height;
                    dc.DrawEllipse(new SolidColorBrush(s.Color), CursorPen, new Point(cx, py), 3.5, 3.5);
                }
            }
        }
        dc.Pop();
    }

    private static bool HasBreak(bool[] br, int from, int to)
    {
        for (int i = Math.Max(0, from); i <= to && i < br.Length; i++) if (br[i]) return true;
        return false;
    }
    private static bool HasNaN(double[] y, int from, int to)
    {
        for (int i = from; i <= to; i++) if (!double.IsFinite(y[i])) return true;
        return false;
    }

    /// <summary>Value of a series at x (nearest sample within two sample steps), NaN otherwise.</summary>
    public static double ValueAt(ChartSeries s, double x)
    {
        if (s.X.Length == 0) return double.NaN;
        int i = Array.BinarySearch(s.X, x);
        if (i < 0) { i = ~i; if (i > 0 && (i == s.X.Length || x - s.X[i - 1] < s.X[i] - x)) i--; }
        i = Math.Clamp(i, 0, s.X.Length - 1);
        double step = s.X.Length > 1 ? (s.X[^1] - s.X[0]) / (s.X.Length - 1) : 1;
        return Math.Abs(s.X[i] - x) <= 2.5 * step ? s.Y[i] : double.NaN;
    }

    private string FormatX(double x) => Axis switch
    {
        AxisFormat.Clock => TimeText.Clock(x),
        AxisFormat.Kilometres => (x / 1000).ToString("0.#", CultureInfo.GetCultureInfo("es-ES")) + " km",
        AxisFormat.HourOfDay => $"{(int)Math.Floor(x / 3600) % 24:00}:{(int)(x % 3600 / 60):00}",
        _ => x.ToString("0.##", CultureInfo.GetCultureInfo("es-ES")),
    };

    private static int Lower(double[] x, double v)
    {
        int i = Array.BinarySearch(x, v);
        return i >= 0 ? i : Math.Max(0, ~i - 1);
    }
    private static int Upper(double[] x, double v)
    {
        int i = Array.BinarySearch(x, v);
        return i >= 0 ? i : Math.Min(x.Length - 1, ~i);
    }

    public static IEnumerable<double> NiceTicks(double lo, double hi, int count, bool time = false)
    {
        double span = hi - lo;
        if (span <= 0 || !double.IsFinite(span)) yield break;
        double raw = span / Math.Max(1, count);
        double step;
        if (time)
        {
            double[] steps = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600, 7200, 10800, 21600];
            step = steps.FirstOrDefault(s => s >= raw, 43200);
        }
        else
        {
            double mag = Math.Pow(10, Math.Floor(Math.Log10(raw)));
            double r = raw / mag;
            step = (r <= 1 ? 1 : r <= 2 ? 2 : r <= 5 ? 5 : 10) * mag;
        }
        double start = Math.Ceiling(lo / step) * step;
        for (double v = start; v <= hi + step * 1e-6; v += step) yield return Math.Abs(v) < step * 1e-9 ? 0 : v;
    }

    private FormattedText Text(string s, double size, Brush brush) =>
        new(s, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, Face, size, brush, VisualTreeHelper.GetDpi(this).PixelsPerDip);

    // ------------------------------------------------------------------ interaction
    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonDown(e);
        if (e.ClickCount == 2) { XMin = double.NaN; XMax = double.NaN; e.Handled = true; return; }
        _down = e.GetPosition(this);
        var (lo, hi) = ViewX();
        _downXMin = lo; _downXMax = hi;
        _selecting = Keyboard.Modifiers.HasFlag(ModifierKeys.Shift);
        _dragging = false;
        CaptureMouse();
        e.Handled = true;
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        if (_down is not Point d || e.LeftButton != MouseButtonState.Pressed) return;
        var pos = e.GetPosition(this);
        var p = Plot;
        if (Math.Abs(pos.X - d.X) > 3) _dragging = true;
        if (!_dragging) return;
        if (_selecting)
        {
            RangeStart = ToX(d.X, _downXMin, _downXMax, p);
            RangeEnd = ToX(pos.X, _downXMin, _downXMax, p);
        }
        else
        {
            double dx = (pos.X - d.X) / p.Width * (_downXMax - _downXMin);
            var (dlo, dhi) = DataXRange();
            double w = _downXMax - _downXMin;
            double nlo = Math.Clamp(_downXMin - dx, dlo - w * 0.05, dhi - w * 0.95);
            XMin = nlo; XMax = nlo + w;
        }
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonUp(e);
        if (_down is Point d && !_dragging)
        {
            var (lo, hi) = ViewX();
            double x = ToX(d.X, lo, hi, Plot);
            CursorX = x;
            CursorMoved?.Invoke(this, x);
            if (_selecting) { RangeStart = double.NaN; RangeEnd = double.NaN; }
        }
        _down = null; _dragging = false;
        ReleaseMouseCapture();
    }

    protected override void OnMouseWheel(MouseWheelEventArgs e)
    {
        base.OnMouseWheel(e);
        var (lo, hi) = ViewX();
        var (dlo, dhi) = DataXRange();
        var p = Plot;
        double at = ToX(e.GetPosition(this).X, lo, hi, p);
        double f = e.Delta > 0 ? 0.8 : 1.25;
        double nlo = at - (at - lo) * f, nhi = at + (hi - at) * f;
        if (nhi - nlo >= (dhi - dlo) * 0.999) { XMin = double.NaN; XMax = double.NaN; }
        else if (nhi - nlo > (dhi - dlo) * 1e-4) { XMin = Math.Max(dlo, nlo); XMax = Math.Min(dhi, nhi); }
        e.Handled = true;
    }
}

/// <summary>Minimal sparkline used inside metric tiles.</summary>
public sealed class Sparkline : FrameworkElement
{
    public static readonly DependencyProperty ValuesProperty = DependencyProperty.Register(nameof(Values), typeof(double[]), typeof(Sparkline),
        new FrameworkPropertyMetadata(null, FrameworkPropertyMetadataOptions.AffectsRender));
    public static readonly DependencyProperty StrokeProperty = DependencyProperty.Register(nameof(Stroke), typeof(Brush), typeof(Sparkline),
        new FrameworkPropertyMetadata(Brushes.White, FrameworkPropertyMetadataOptions.AffectsRender));
    public double[]? Values { get => (double[]?)GetValue(ValuesProperty); set => SetValue(ValuesProperty, value); }
    public Brush Stroke { get => (Brush)GetValue(StrokeProperty); set => SetValue(StrokeProperty, value); }

    protected override void OnRender(DrawingContext dc)
    {
        var v = Values;
        if (v is null || v.Length < 2 || ActualWidth < 4) return;
        var x = Enumerable.Range(0, v.Length).Select(i => (double)i).ToArray();
        var idx = Downsampler.Lttb(x, v, Math.Max(20, (int)ActualWidth));
        if (idx.Length < 2) return;
        double lo = idx.Min(i => v[i]), hi = idx.Max(i => v[i]);
        if (hi - lo < 1e-9) hi = lo + 1;
        var geo = new StreamGeometry();
        using (var g = geo.Open())
        {
            bool first = true;
            foreach (int i in idx)
            {
                var pt = new Point(i / (double)(v.Length - 1) * ActualWidth, ActualHeight - 1 - (v[i] - lo) / (hi - lo) * (ActualHeight - 2));
                if (first) { g.BeginFigure(pt, false, false); first = false; } else g.LineTo(pt, true, false);
            }
        }
        geo.Freeze();
        var pen = new Pen(Stroke, 1.3); pen.Freeze();
        dc.DrawGeometry(null, pen, geo);
    }
}
