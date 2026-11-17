using System.Globalization;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Avo.Windows.Controls;

/// <summary>
/// Side view of a horse (X-ray style image owned by the user, Assets/horse_xray.png, transparent background) with the girth
/// and the three girth IMUs (left, central, right) drawn on top. Illustrative: not an anatomical measurement of the horse.
/// Sensors without data are drawn hollow.
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

    // Image and overlay coordinates are image pixels (1448 x 1086).
    private const double ImgW = 1448, ImgH = 1086;
    private static readonly Lazy<BitmapImage?> Image = new(() =>
    {
        try
        {
            var b = new BitmapImage();
            b.BeginInit();
            b.UriSource = new Uri("pack://application:,,,/Assets/horse_xray.png", UriKind.Absolute);
            b.CacheOption = BitmapCacheOption.OnLoad;
            b.EndInit();
            b.Freeze();
            return b;
        }
        catch (Exception) { return null; }   // missing resource: the overlay is still drawn
    });

    // Girth just behind the elbow, from the withers to the belly.
    private static readonly Point[] Girth = [new(592, 248), new(636, 254), new(626, 620), new(580, 614)];

    private static readonly (int id, Point pos, string label, Point labelPos)[] Sensors =
    [
        (1, new Point(606, 450), "Izquierda", new Point(700, 700)),
        (0, new Point(602, 600), "Central", new Point(170, 690)),
        (2, new Point(612, 296), "Derecha (lado opuesto)", new Point(700, 120)),
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
        double s = Math.Min(ActualWidth / ImgW, ActualHeight / ImgH);
        if (s <= 0) return;
        double ox = (ActualWidth - ImgW * s) / 2, oy = (ActualHeight - ImgH * s) / 2;
        Point M(Point p) => new(ox + p.X * s, oy + p.Y * s);

        if (Image.Value is { } img)
        {
            RenderOptions.SetBitmapScalingMode(this, BitmapScalingMode.HighQuality);
            dc.DrawImage(img, new Rect(ox, oy, ImgW * s, ImgH * s));
        }

        var girth = new StreamGeometry();
        using (var g = girth.Open())
        {
            g.BeginFigure(M(Girth[0]), true, true);
            for (int i = 1; i < Girth.Length; i++) g.LineTo(M(Girth[i]), true, true);
        }
        girth.Freeze();
        dc.DrawGeometry(new SolidColorBrush(Color.FromArgb(0x8C, 0xCC, 0x1A, 0x2A)), new Pen(new SolidColorBrush(Color.FromRgb(0xFF, 0x49, 0x5A)), 1.2), girth);

        var active = ActiveSensors ?? [];
        var dip = VisualTreeHelper.GetDpi(this).PixelsPerDip;
        foreach (var (id, pos, label, lpImg) in Sensors)
        {
            var c = SensorColor(id);
            bool on = active.Contains(id);
            Point p = M(pos), lp = M(lpImg);
            var linePen = new Pen(new SolidColorBrush(Color.FromArgb(0xC0, c.R, c.G, c.B)), 1) { DashStyle = DashStyles.Dash };
            dc.DrawLine(linePen, p, lp);
            double r = Highlight == id ? 9 : 7;
            dc.DrawEllipse(on ? new SolidColorBrush(c) : new SolidColorBrush(Color.FromArgb(0x99, 0x10, 0x10, 0x14)), new Pen(new SolidColorBrush(c), 2.4), p, r, r);
            if (on) dc.DrawEllipse(null, new Pen(new SolidColorBrush(Color.FromArgb(0x70, c.R, c.G, c.B)), 4), p, r + 4, r + 4);
            var ft = new FormattedText(label + (on ? "" : " · sin datos"), CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
                new Typeface("Segoe UI"), 13, new SolidColorBrush(Color.FromRgb(0xF2, 0xF2, 0xF4)), dip);
            dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromArgb(0xD8, 0x10, 0x10, 0x14)), new Pen(new SolidColorBrush(c), 1),
                new Rect(lp.X - 5, lp.Y - 3, ft.Width + 10, ft.Height + 6), 4, 4);
            dc.DrawText(ft, lp);
        }
        var note = new FormattedText("Imagen ilustrativa · cincha con 3 IMU", CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
            new Typeface("Segoe UI"), 10, new SolidColorBrush(Color.FromRgb(0x93, 0x94, 0x9B)), dip);
        dc.DrawText(note, new Point(4, 2));
    }
}
