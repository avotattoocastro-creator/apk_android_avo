using System.Globalization;
using System.Windows;
using System.Windows.Media;

namespace Avo.Windows.Controls;

/// <summary>
/// Illustrative side view of a horse with the girth and the three girth IMUs (left, central, right). It is an original
/// schematic drawing, not a 3D model nor an anatomical measurement; sensors without data are drawn hollow.
/// </summary>
public sealed class HorseDiagram : FrameworkElement
{
    public static readonly DependencyProperty ActiveSensorsProperty = DependencyProperty.Register(nameof(ActiveSensors), typeof(int[]), typeof(HorseDiagram),
        new FrameworkPropertyMetadata(Array.Empty<int>(), FrameworkPropertyMetadataOptions.AffectsRender));
    public static readonly DependencyProperty HighlightProperty = DependencyProperty.Register(nameof(Highlight), typeof(int), typeof(HorseDiagram),
        new FrameworkPropertyMetadata(-1, FrameworkPropertyMetadataOptions.AffectsRender));
    /// <summary>imu_id values with data (0 central, 1 left, 2 right).</summary>
    public int[] ActiveSensors { get => (int[])GetValue(ActiveSensorsProperty); set => SetValue(ActiveSensorsProperty, value); }
    public int Highlight { get => (int)GetValue(HighlightProperty); set => SetValue(HighlightProperty, value); }

    // Drawing in a 400 x 260 design box (original geometry).
    private static readonly Geometry Body = Geometry.Parse(
        "M118,112 C140,92 220,88 296,96 C330,99 350,116 346,146 C343,168 326,178 304,174 L292,173 C270,178 200,178 160,172 C134,168 112,146 118,112 Z");
    private static readonly Geometry Neck = Geometry.Parse("M120,128 C108,98 94,72 80,50 L100,38 C116,60 138,86 168,100 Z");
    private static readonly Geometry Head = Geometry.Parse("M80,50 C72,40 62,36 52,40 L30,66 C27,72 32,78 39,77 L58,70 C68,66 84,60 100,38 Z M86,42 L88,26 L96,38 Z");
    private static readonly Geometry Legs = Geometry.Parse(
        "M140,164 L134,238 L145,238 L154,170 Z M168,170 L172,240 L183,240 L182,168 Z M286,170 L292,238 L303,238 L302,166 Z M318,164 L328,236 L339,236 L337,150 Z");
    private static readonly Geometry Tail = Geometry.Parse("M342,118 C366,132 372,172 362,210 C352,184 346,152 334,134 Z");
    private static readonly Geometry Mane = Geometry.Parse("M98,40 C112,58 128,80 150,96");
    private static readonly Geometry Girth = Geometry.Parse("M176,92 L194,92 L192,176 L174,176 Z");

    private static readonly (int id, Point pos, string label, Point labelPos)[] Sensors =
    [
        (1, new Point(184, 136), "Izquierda", new Point(214, 210)),
        (0, new Point(183, 172), "Central", new Point(120, 248)),
        (2, new Point(190, 108), "Derecha (lado opuesto)", new Point(214, 60)),
    ];

    public static Color SensorColor(int id) => id switch
    {
        1 => Color.FromRgb(0x3D, 0x9B, 0xFF),
        0 => Color.FromRgb(0x52, 0xDD, 0x40),
        2 => Color.FromRgb(0xFF, 0xC4, 0x2C),
        _ => Color.FromRgb(0x93, 0x94, 0x9B),
    };

    protected override void OnRender(DrawingContext dc)
    {
        double s = Math.Min(ActualWidth / 400, ActualHeight / 262);
        if (s <= 0) return;
        double ox = (ActualWidth - 400 * s) / 2, oy = (ActualHeight - 262 * s) / 2;
        dc.PushTransform(new MatrixTransform(s, 0, 0, s, ox, oy));
        var fill = new LinearGradientBrush(Color.FromRgb(0x4A, 0x4C, 0x55), Color.FromRgb(0x1A, 0x1B, 0x20), 90);
        var edge = new Pen(new SolidColorBrush(Color.FromRgb(0xC9, 0xCB, 0xD1)), 1.2) { LineJoin = PenLineJoin.Round };
        dc.DrawGeometry(new SolidColorBrush(Color.FromRgb(0x2A, 0x2B, 0x31)), edge, Tail);
        dc.DrawGeometry(fill, edge, Legs);
        dc.DrawGeometry(fill, edge, Neck);
        dc.DrawGeometry(fill, edge, Body);
        dc.DrawGeometry(fill, edge, Head);
        dc.DrawGeometry(null, new Pen(new SolidColorBrush(Color.FromRgb(0x9C, 0x9D, 0xA4)), 3) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round }, Mane);
        dc.DrawGeometry(new SolidColorBrush(Color.FromArgb(0xCC, 0xED, 0x12, 0x2A)), new Pen(new SolidColorBrush(Color.FromRgb(0xFF, 0x49, 0x5A)), 1), Girth);
        var active = ActiveSensors ?? [];
        var dip = VisualTreeHelper.GetDpi(this).PixelsPerDip;
        foreach (var (id, pos, label, lp) in Sensors)
        {
            var c = SensorColor(id);
            bool on = active.Contains(id);
            var linePen = new Pen(new SolidColorBrush(Color.FromArgb(0xB0, c.R, c.G, c.B)), 1) { DashStyle = DashStyles.Dash };
            dc.DrawLine(linePen, pos, lp);
            double r = Highlight == id ? 9 : 7;
            dc.DrawEllipse(on ? new SolidColorBrush(c) : Brushes.Transparent, new Pen(new SolidColorBrush(c), 2.4), pos, r, r);
            if (on) dc.DrawEllipse(null, new Pen(new SolidColorBrush(Color.FromArgb(0x60, c.R, c.G, c.B)), 4), pos, r + 4, r + 4);
            var ft = new FormattedText(label + (on ? "" : " · sin datos"), CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
                new Typeface("Segoe UI"), 12, new SolidColorBrush(Color.FromRgb(0xF2, 0xF2, 0xF4)), dip);
            dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromArgb(0xD0, 0x10, 0x10, 0x14)), new Pen(new SolidColorBrush(c), 1),
                new Rect(lp.X - 4, lp.Y - 2, ft.Width + 8, ft.Height + 4), 3, 3);
            dc.DrawText(ft, lp);
        }
        var note = new FormattedText("Esquema ilustrativo · cincha con 3 IMU", CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
            new Typeface("Segoe UI"), 10, new SolidColorBrush(Color.FromRgb(0x93, 0x94, 0x9B)), dip);
        dc.DrawText(note, new Point(2, 2));
        dc.Pop();
    }
}
