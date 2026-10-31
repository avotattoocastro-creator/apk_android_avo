using System.Globalization;
using System.Windows;
using System.Windows.Media;

namespace Avo.Windows.Controls;

/// <summary>
/// Illustrative side view of a walking horse (anatomical style) with the girth and the three girth IMUs (left, central, right). It is an original
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

    // Original anatomical-style drawing (muscle groups, tendons and joints) of a walking horse, in a 400 x 262 design box.
    // It is an illustration, not an anatomical model: the sensors are placed on the girth just behind the withers and the elbow.
    private static readonly Geometry FarLegs = Geometry.Parse("M138.1,161.8 C139.5,166.0 144.4,179.8 146.6,187.2 C148.8,194.5 150.4,201.4 151.6,205.8 C152.7,210.2 152.7,209.6 153.5,213.6 C154.4,217.5 156.0,225.2 156.5,229.4 C157.0,233.6 156.4,236.0 156.5,238.6 C156.7,241.1 157.5,242.8 157.6,244.7 C157.6,246.6 157.1,249.1 157.0,250.0 L169.0,250.0 C168.6,248.9 167.0,245.4 166.4,243.3 C165.8,241.2 166.0,239.9 165.5,237.4 C165.0,235.0 164.0,232.7 163.5,228.6 C163.0,224.4 162.6,216.5 162.5,212.4 C162.3,208.4 162.6,208.8 162.4,204.2 C162.3,199.6 161.5,192.5 161.4,184.8 C161.3,177.2 161.8,162.6 161.9,158.2 Z M248.3,155.0 C248.6,159.5 250.1,174.5 250.2,182.2 C250.2,190.0 249.0,197.0 248.7,201.6 C248.3,206.2 248.5,205.9 248.1,210.0 C247.8,214.1 247.3,221.8 246.6,226.4 C245.8,230.9 244.2,234.4 243.6,237.2 C242.9,240.0 243.2,241.1 242.6,243.3 C242.0,245.4 240.4,248.9 240.0,250.0 L252.0,250.0 C251.9,249.1 251.4,246.6 251.4,244.7 C251.5,242.9 252.1,241.6 252.4,238.8 C252.8,235.9 252.5,232.1 253.4,227.6 C254.4,223.2 256.6,215.9 257.9,212.0 C259.2,208.1 259.7,208.8 261.3,204.4 C263.0,200.0 264.8,193.0 267.8,185.8 C270.9,178.5 277.7,165.1 279.7,161.0 Z");
    private static readonly Geometry Tail = Geometry.Parse("M318,104 C336,104 348,120 350,146 C352,172 348,196 342,214 C338,196 336,170 330,148 C326,132 322,118 318,110 Z");
    private static readonly Geometry[] Near = [Geometry.Parse("M269.9,156.3 C272.8,160.6 282.6,174.3 287.6,181.8 C292.6,189.3 297.1,196.9 299.9,201.4 C302.7,206.0 302.3,205.3 304.4,209.1 C306.4,212.9 310.4,219.6 312.2,224.3 C314.0,229.0 314.4,233.9 315.2,237.4 C316.0,240.9 316.8,243.3 317.2,245.4 C317.6,247.5 317.4,249.2 317.5,250.0 L330.5,250.0 C329.9,248.8 327.8,245.2 326.8,242.6 C325.9,240.1 326.0,238.1 324.8,234.6 C323.6,231.1 321.3,226.7 319.8,221.7 C318.2,216.7 316.6,209.1 315.6,204.9 C314.7,200.7 314.6,201.7 314.1,196.6 C313.6,191.4 312.4,183.0 312.4,174.2 C312.4,165.4 313.8,148.8 314.1,143.7 Z"), Geometry.Parse("M38,88 C40,80 52,64 66,48 C71,42 75,38 80,35 L77,22 L84,30 L88,20 L90,33 C108,40 130,58 148,80 C156,88 162,94 172,96 C192,100 208,106 226,106 C248,106 268,98 288,96 C302,95 314,100 320,112 C326,124 326,140 320,154 C314,166 306,174 296,180 C276,178 250,172 214,174 C186,176 164,174 144,170 C128,166 114,156 108,140 C104,122 98,100 92,80 C90,88 86,92 80,94 C72,97 64,98 56,100 C50,102 44,100 41,97 C37,94 36,91 38,88 Z"), Geometry.Parse("M117.7,153.6 C117.3,158.2 116.7,173.2 115.5,181.0 C114.3,188.8 112.1,195.7 110.6,200.4 C109.1,205.1 108.0,204.7 106.5,208.9 C104.9,213.1 103.1,221.0 101.3,225.5 C99.5,229.9 97.2,232.9 95.6,235.7 C94.0,238.4 92.9,239.4 91.5,241.8 C90.2,244.2 88.2,248.6 87.5,250.0 L100.5,250.0 C100.5,249.4 99.8,247.8 100.5,246.2 C101.1,244.6 103.0,243.3 104.4,240.3 C105.8,237.4 106.8,233.1 108.7,228.5 C110.6,224.0 113.4,216.9 115.5,213.1 C117.7,209.3 118.6,209.9 121.4,205.6 C124.2,201.3 128.3,194.2 132.5,187.0 C136.6,179.8 144.0,166.5 146.3,162.4 Z")];
    private static readonly (Geometry g, Color fill)[] Muscles =
    [
        (Geometry.Parse("M60,70 C66,60 80,62 84,72 C88,82 82,92 72,93 C62,94 56,82 60,70 Z"), Color.FromArgb(0xFF, 0xb0, 0x57, 0x3d)),
        (Geometry.Parse("M44,92 C48,86 56,84 60,88 C58,94 52,98 46,98 Z"), Color.FromArgb(0xFF, 0x8a, 0x3a, 0x28)),
        (Geometry.Parse("M84,50 C100,58 120,72 138,90 C126,92 110,86 98,78 C92,70 88,60 84,50 Z"), Color.FromArgb(0xFF, 0xb8, 0x61, 0x4a)),
        (Geometry.Parse("M90,82 C98,98 106,118 112,138 C118,136 122,130 120,122 C114,106 104,90 94,78 Z"), Color.FromArgb(0xFF, 0xc0, 0x6a, 0x4f)),
        (Geometry.Parse("M98,78 C112,86 128,94 140,92 C150,100 156,110 150,118 C136,116 120,104 106,96 Z"), Color.FromArgb(0xFF, 0x9c, 0x46, 0x30)),
        (Geometry.Parse("M166,98 C160,112 150,128 140,138 C130,146 120,144 114,138 C122,124 136,108 150,96 C156,94 162,95 166,98 Z"), Color.FromArgb(0xFF, 0xc4, 0x70, 0x4f)),
        (Geometry.Parse("M140,138 C150,128 160,118 168,108 C172,124 168,146 160,160 C150,164 140,160 134,152 C134,146 136,142 140,138 Z"), Color.FromArgb(0xFF, 0xa9, 0x52, 0x38)),
        (Geometry.Parse("M114,140 C122,146 132,152 136,162 C130,166 120,164 112,156 Z"), Color.FromArgb(0xFF, 0x8f, 0x3f, 0x2b)),
        (Geometry.Parse("M168,106 C196,112 232,112 266,104 C274,120 272,142 262,162 C236,170 204,172 176,166 C166,150 172,128 168,106 Z"), Color.FromArgb(0xFF, 0xb2, 0x5a, 0x40)),
        (Geometry.Parse("M172,140 C184,132 196,130 206,134 C200,146 190,156 178,162 Z"), Color.FromArgb(0xFF, 0xc2, 0x6c, 0x50)),
        (Geometry.Parse("M206,152 C226,140 246,134 262,136 C262,148 258,158 252,166 C236,168 220,166 206,152 Z"), Color.FromArgb(0xFF, 0x9e, 0x48, 0x32)),
        (Geometry.Parse("M262,104 C276,100 296,98 312,104 C318,114 316,128 306,136 C290,134 276,126 268,118 Z"), Color.FromArgb(0xFF, 0xc9, 0x73, 0x52)),
        (Geometry.Parse("M312,106 C324,120 324,142 316,158 C308,170 300,176 294,178 C296,164 302,148 304,134 C306,124 308,114 312,106 Z"), Color.FromArgb(0xFF, 0xa2, 0x4a, 0x34)),
        (Geometry.Parse("M268,118 C280,126 294,134 304,136 C302,152 296,166 288,174 C278,170 270,166 264,162 C268,148 270,132 268,118 Z"), Color.FromArgb(0xFF, 0xb9, 0x64, 0x4a)),
        (Geometry.Parse("M124,166 C132,170 136,180 130,194 C126,200 120,202 116,200 C116,190 118,178 124,166 Z"), Color.FromArgb(0xFF, 0xc0, 0x6a, 0x4f)),
        (Geometry.Parse("M298,178 C306,184 310,194 308,204 C304,206 300,204 298,198 C296,190 296,184 298,178 Z"), Color.FromArgb(0xFF, 0xb2, 0x5e, 0x44)),
    ];
    private static readonly Geometry Fibres = Geometry.Parse("M180,112.0 C186,130 184,150 178,166.0 M194,112.5 C200,130 198,150 192,165.7 M208,113.0 C214,130 212,150 206,165.4 M222,113.5 C228,130 226,150 220,165.1 M236,114.0 C242,130 240,150 234,164.8 M250,114.5 C256,130 254,150 248,164.5 M102,60 C110,70 120,78 130,86 M110,67 C118,77 128,85 138,92 M118,74 C126,84 136,92 146,98 M126,81 C134,91 144,99 154,104 M150,104 C146,118 138,130 128,140 M156,112 C152,124 146,134 138,144 M280,106 C290,108 300,112 306,120 M276,114 C288,118 298,122 304,128 M314,116 C316,132 312,150 304,166 M308,120 C310,136 306,152 298,168");
    private static readonly Geometry Tendons = Geometry.Parse("M112,206 C108,218 104,228 101,236 M309,206 C313,218 317,228 320,236 M158,210 C159,220 160,228 161,236 M253,208 C251,218 249,228 248,236");
    private static readonly (double x, double y, double rx, double ry)[] Joints = [(113, 204, 4.5, 3.5), (100, 238, 4, 3), (309, 206, 4.5, 3.5), (320, 238, 4, 3), (157, 207, 3.5, 3), (161, 239, 3.5, 2.6), (254, 206, 3.5, 3), (248, 239, 3.5, 2.6), (116, 141, 3.5, 3), (296, 182, 3, 3)];
    private static readonly Geometry Hooves = Geometry.Parse("M86,246 L102,246 L102,250 L86,250 Z M316,246 L330,246 L331,250 L316,250 Z M156,246 L168,246 L169,250 L156,250 Z M240,246 L252,246 L252,250 L240,250 Z");
    private static readonly Geometry Mane = Geometry.Parse("M86,32 C100,38 116,50 130,62 C142,74 152,86 166,94");
    private static readonly Geometry ManeStrands = Geometry.Parse("M86.0,32.0 l-3.0,-7.0 M89.8,34.6 l-5.0,-9.0 M93.6,37.2 l-7.0,-5.0 M97.4,39.9 l-3.0,-7.0 M101.2,42.6 l-5.0,-9.0 M105.0,45.3 l-7.0,-5.0 M108.9,48.1 l-3.0,-7.0 M112.7,50.9 l-5.0,-9.0 M116.5,53.7 l-7.0,-5.0 M120.3,56.6 l-3.0,-7.0 M124.1,59.5 l-5.0,-9.0 M127.9,62.5 l-7.0,-5.0 M131.7,65.5 l-3.0,-7.0 M135.5,68.5 l-5.0,-9.0 M139.3,71.6 l-7.0,-5.0 M143.1,74.7 l-3.0,-7.0 M147.0,77.8 l-5.0,-9.0 M150.8,81.0 l-7.0,-5.0 M154.6,84.2 l-3.0,-7.0 M158.4,87.4 l-5.0,-9.0 M162.2,90.7 l-7.0,-5.0 M166.0,94.0 l-3.0,-7.0");
    private static readonly Geometry Nostril = Geometry.Parse("M44,90 C45,88 47,88 48,90");
    private static readonly Geometry Girth = Geometry.Parse("M164,97 L182,100 L178,174 L158,172 Z");

    private static readonly (int id, Point pos, string label, Point labelPos)[] Sensors =
    [
        (1, new Point(170, 136), "Izquierda", new Point(198, 192)),
        (0, new Point(168, 168), "Central", new Point(14, 226)),
        (2, new Point(173, 106), "Derecha (lado opuesto)", new Point(198, 36)),
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
        Brush B(Color c) { var b = new SolidColorBrush(c); b.Freeze(); return b; }
        Pen P(Color c, double w) { var p = new Pen(B(c), w) { LineJoin = PenLineJoin.Round, StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round }; p.Freeze(); return p; }
        LinearGradientBrush V(Color top, Color bottom) => new(top, bottom, new Point(0, 20), new Point(0, 250)) { MappingMode = BrushMappingMode.Absolute };
        var outline = Color.FromRgb(0x2A, 0x0F, 0x08);
        var bone = Color.FromRgb(0xD8, 0xC6, 0xA6);
        // far side legs, tail
        dc.DrawGeometry(V(Color.FromRgb(0x7A, 0x3A, 0x2A), Color.FromRgb(0x3A, 0x16, 0x0E)), P(outline, 0.8), FarLegs);
        dc.DrawGeometry(new LinearGradientBrush(Color.FromRgb(0x3A, 0x3A, 0x3E), Color.FromRgb(0x15, 0x15, 0x17), 90), P(Color.FromRgb(0x1A, 0x1A, 0x1C), 0.8), Tail);
        // near side: outline first, then the fills cover the inner seams
        var skin = V(Color.FromRgb(0xBF, 0x6A, 0x4E), Color.FromRgb(0x5E, 0x24, 0x18));
        foreach (var g in Near) dc.DrawGeometry(null, P(outline, 2), g);
        foreach (var g in Near) dc.DrawGeometry(skin, null, g);
        // muscle groups with a soft highlight, fibres, tendons and joints
        var hl = new RadialGradientBrush(Color.FromArgb(0x59, 0xFF, 0xD2, 0xBD), Color.FromArgb(0x00, 0xFF, 0xD2, 0xBD))
        { Center = new Point(0.4, 0.35), GradientOrigin = new Point(0.4, 0.35), RadiusX = 0.7, RadiusY = 0.7 };
        var musclePen = P(Color.FromArgb(0xEB, 0x3A, 0x14, 0x0C), 0.6);
        foreach (var (g, c) in Muscles) { dc.DrawGeometry(B(Color.FromArgb(0xEB, c.R, c.G, c.B)), musclePen, g); dc.DrawGeometry(hl, null, g); }
        dc.DrawGeometry(null, P(Color.FromArgb(0x8C, 0xE3, 0x9A, 0x7C), 0.6), Fibres);
        dc.DrawGeometry(null, P(Color.FromArgb(0xE6, bone.R, bone.G, bone.B), 1.5), Tendons);
        foreach (var (x, y, rx, ry) in Joints) dc.DrawEllipse(B(Color.FromArgb(0xD9, bone.R, bone.G, bone.B)), P(Color.FromRgb(0x6B, 0x5A, 0x44), 0.4), new Point(x, y), rx, ry);
        dc.DrawGeometry(B(Color.FromRgb(0x2B, 0x2A, 0x28)), P(Color.FromRgb(0x11, 0x11, 0x11), 0.6), Hooves);
        dc.DrawGeometry(null, P(Color.FromRgb(0x2C, 0x2C, 0x30), 4), Mane);
        dc.DrawGeometry(null, P(Color.FromRgb(0x55, 0x55, 0x5B), 0.8), ManeStrands);
        dc.DrawEllipse(B(Color.FromRgb(0x1A, 0x0E, 0x0A)), null, new Point(66, 58), 3, 2.2);
        dc.DrawEllipse(B(Color.FromRgb(0xEE, 0xEE, 0xEE)), null, new Point(66.8, 57.4), 0.7, 0.7);
        dc.DrawGeometry(null, P(outline, 1), Nostril);
        dc.DrawGeometry(B(Color.FromArgb(0xD9, 0xCC, 0x1A, 0x2A)), P(Color.FromRgb(0xFF, 0x49, 0x5A), 1), Girth);
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
