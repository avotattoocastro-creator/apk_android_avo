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

    // Original side-view drawing in a 400 x 262 design box (horse drawn at x + 36). Proportions of a riding horse: body depth
    // about the leg length, knees and hocks marked, girth just behind the withers and the elbow.
    private static readonly Geometry Body = Geometry.Parse("M30,72 C28,68 30,64 33,61 L60,34 C64,30 68,27 72,25 L72,13 L78,22 L83,11 L85,24 C100,32 118,48 134,66 C144,78 152,88 162,93 C178,98 192,104 208,104 C224,104 240,99 256,96 C270,93 288,94 300,102 C308,108 312,118 310,130 C308,146 302,160 298,170 C294,180 292,192 291,202 C290,212 291,224 292,232 C293,238 296,244 298,250 L286,250 L285,240 C284,232 283,222 283,212 C283,206 280,202 276,198 C270,190 264,180 260,170 C254,168 246,166 238,166 C220,168 204,171 188,171 C170,171 152,170 136,166 C134,178 130,188 128,197 C127,210 127,224 127,234 C128,240 130,245 131,250 L119,250 L119,244 C118,236 117,226 117,214 C117,206 117,200 116,195 C115,184 112,174 110,166 C107,158 100,150 97,140 C94,128 92,116 88,104 C84,94 80,86 76,80 C74,76 70,74 66,74 C60,78 54,80 46,82 C40,84 34,80 30,72 Z");
    private static readonly Geometry FarLegs = Geometry.Parse("M150,170 C148,182 146,192 145,202 C144,214 144,226 144,234 C144,240 146,245 147,250 L136,250 L136,243 C135,236 134,226 134,214 C134,204 136,192 138,178 Z M262,172 C266,184 270,192 272,200 C274,210 273,222 272,232 C272,238 274,244 276,250 L265,250 L264,240 C263,232 262,222 262,212 C262,204 258,196 252,188 Z");
    private static readonly Geometry Tail = Geometry.Parse("M300,102 C318,106 330,126 330,156 C330,182 324,204 316,222 C314,200 314,176 308,150 C306,134 304,118 300,108 Z");
    private static readonly Geometry Mane = Geometry.Parse("M84,24 C98,34 114,48 130,64 C142,78 152,88 164,93");
    private static readonly Geometry Hooves = Geometry.Parse("M119,244 L131,244 L131,250 L119,250 Z M286,244 L297,244 L298,250 L286,250 Z M136,244 L147,244 L147,250 L136,250 Z M265,244 L275,244 L276,250 L265,250 Z");
    private static readonly Geometry Details = Geometry.Parse("M36,66 C38,64 41,64 42,66 M33,76 C38,78 44,78 48,76 M66,58 C70,64 70,70 66,74 M110,166 C116,160 124,158 132,160 M262,172 C268,156 270,138 266,118");
    private static readonly Geometry Girth = Geometry.Parse("M160,94 L178,99 L176,172 L158,170 Z");

    private static readonly (int id, Point pos, string label, Point labelPos)[] Sensors =
    [
        (1, new Point(167, 134), "Izquierda", new Point(196, 192)),
        (0, new Point(166, 166), "Central", new Point(46, 222)),
        (2, new Point(169, 104), "Derecha (lado opuesto)", new Point(196, 34)),
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
        dc.PushTransform(new TranslateTransform(36, 0));
        dc.DrawGeometry(new SolidColorBrush(Color.FromRgb(0x26, 0x27, 0x2D)), new Pen(new SolidColorBrush(Color.FromRgb(0x8E, 0x90, 0x99)), 0.9), FarLegs);
        dc.DrawGeometry(new SolidColorBrush(Color.FromRgb(0x2A, 0x2B, 0x31)), edge, Tail);
        dc.DrawGeometry(fill, edge, Body);
        dc.DrawGeometry(null, new Pen(new SolidColorBrush(Color.FromRgb(0x9C, 0x9D, 0xA4)), 3) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round }, Mane);
        dc.DrawGeometry(new SolidColorBrush(Color.FromRgb(0x10, 0x11, 0x14)), null, Hooves);
        dc.DrawGeometry(null, new Pen(new SolidColorBrush(Color.FromRgb(0x7D, 0x7F, 0x88)), 0.9) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round }, Details);
        dc.DrawEllipse(new SolidColorBrush(Color.FromRgb(0xC9, 0xCB, 0xD1)), null, new Point(58, 46), 2, 2);
        dc.DrawGeometry(new SolidColorBrush(Color.FromArgb(0xD9, 0xCC, 0x1A, 0x2A)), new Pen(new SolidColorBrush(Color.FromRgb(0xFF, 0x49, 0x5A)), 1), Girth);
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
        dc.Pop();   // translate
        var note = new FormattedText("Esquema ilustrativo · cincha con 3 IMU", CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
            new Typeface("Segoe UI"), 10, new SolidColorBrush(Color.FromRgb(0x93, 0x94, 0x9B)), dip);
        dc.DrawText(note, new Point(2, 2));
        dc.Pop();
    }
}
