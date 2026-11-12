using System.Collections.Concurrent;
using System.Globalization;
using System.IO;
using System.Net.Http;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Avo.Windows.Core;

namespace Avo.Windows.Controls;

public enum RouteColorMode { Speed, Acceleration, GnssQuality, Gait, Single }

/// <summary>A route drawn on the map. Positions are the rider's GNSS antenna (vest), never a point of the horse.</summary>
public sealed class MapTrack
{
    public required SessionTimeline Timeline { get; init; }
    public string Label { get; init; } = "";
    public Color SingleColor { get; init; } = Color.FromRgb(0x3D, 0x9B, 0xFF);
    /// <summary>Optional gait code per timeline index (engine; -1 unknown).</summary>
    public int[]? Gait { get; init; }
    internal double[]? Px0, Py0;   // projected coordinates at zoom 0 (256 px world)
}

/// <summary>Shape drawn over the map (geofence outline, start/finish line…), in lat/lon.</summary>
public sealed class MapShape
{
    public required IReadOnlyList<(double Lat, double Lon)> Points { get; init; }
    public bool Closed { get; init; }
    public Color Stroke { get; init; } = Color.FromRgb(0xED, 0x12, 0x2A);
    public Color Fill { get; init; } = Colors.Transparent;
    public double Thickness { get; init; } = 2.5;
    public string? Label { get; init; }
    public bool ShowVertices { get; init; }
    /// <summary>Lines only: 0 = no arrow, 1 = crossing counts left→right (seen from A to B), -1 = right→left, 2 = both directions.</summary>
    public int Arrow { get; init; }
    /// <summary>Lines only: write A and B at the ends.</summary>
    public bool EndLabels { get; init; }
}

/// <summary>Point clicked on the map when <see cref="MapControl.MapClickCommand"/> is set.</summary>
public sealed record MapClick(double Lat, double Lon);

/// <summary>
/// Interactive Web-Mercator map with optional imagery tiles (Esri World Imagery / hybrid, same provider and attribution
/// as the Android app) cached on disk, and an offline vector mode. Mouse wheel zooms, drag pans, click selects the nearest
/// route point (two-way synchronised with the charts through CursorTime).
/// </summary>
public sealed class MapControl : FrameworkElement
{
    public static readonly DependencyProperty TracksProperty = DependencyProperty.Register(nameof(Tracks), typeof(IReadOnlyList<MapTrack>), typeof(MapControl),
        new FrameworkPropertyMetadata(null, FrameworkPropertyMetadataOptions.AffectsRender, (d, _) => ((MapControl)d).OnTracksChanged()));
    public static readonly DependencyProperty ColorModeProperty = DependencyProperty.Register(nameof(ColorMode), typeof(RouteColorMode), typeof(MapControl),
        new FrameworkPropertyMetadata(RouteColorMode.Speed, FrameworkPropertyMetadataOptions.AffectsRender));
    public static readonly DependencyProperty ProviderProperty = DependencyProperty.Register(nameof(Provider), typeof(MapProvider), typeof(MapControl),
        new FrameworkPropertyMetadata(MapProvider.EsriSatellite, FrameworkPropertyMetadataOptions.AffectsRender));
    public static readonly DependencyProperty CursorTimeProperty = DependencyProperty.Register(nameof(CursorTime), typeof(double), typeof(MapControl),
        new FrameworkPropertyMetadata(double.NaN, FrameworkPropertyMetadataOptions.AffectsRender | FrameworkPropertyMetadataOptions.BindsTwoWayByDefault));
    public static readonly DependencyProperty RangeStartProperty = DependencyProperty.Register(nameof(RangeStart), typeof(double), typeof(MapControl),
        new FrameworkPropertyMetadata(double.NaN, FrameworkPropertyMetadataOptions.AffectsRender));
    public static readonly DependencyProperty RangeEndProperty = DependencyProperty.Register(nameof(RangeEnd), typeof(double), typeof(MapControl),
        new FrameworkPropertyMetadata(double.NaN, FrameworkPropertyMetadataOptions.AffectsRender));
    public static readonly DependencyProperty TileCacheDirProperty = DependencyProperty.Register(nameof(TileCacheDir), typeof(string), typeof(MapControl), new PropertyMetadata(null));
    public static readonly DependencyProperty ShowMarkersProperty = DependencyProperty.Register(nameof(ShowMarkers), typeof(bool), typeof(MapControl),
        new FrameworkPropertyMetadata(true, FrameworkPropertyMetadataOptions.AffectsRender));
    public static readonly DependencyProperty ShowRouteProperty = DependencyProperty.Register(nameof(ShowRoute), typeof(bool), typeof(MapControl),
        new FrameworkPropertyMetadata(true, FrameworkPropertyMetadataOptions.AffectsRender));
    public static readonly DependencyProperty ShapesProperty = DependencyProperty.Register(nameof(Shapes), typeof(IReadOnlyList<MapShape>), typeof(MapControl),
        new FrameworkPropertyMetadata(null, FrameworkPropertyMetadataOptions.AffectsRender, (d, _) => ((MapControl)d).OnShapesChanged()));
    public static readonly DependencyProperty MapClickCommandProperty = DependencyProperty.Register(nameof(MapClickCommand), typeof(ICommand), typeof(MapControl));
    public static readonly DependencyProperty FitPaddingProperty = DependencyProperty.Register(nameof(FitPadding), typeof(Thickness), typeof(MapControl),
        new PropertyMetadata(new Thickness(40)));

    public IReadOnlyList<MapTrack>? Tracks { get => (IReadOnlyList<MapTrack>?)GetValue(TracksProperty); set => SetValue(TracksProperty, value); }
    public RouteColorMode ColorMode { get => (RouteColorMode)GetValue(ColorModeProperty); set => SetValue(ColorModeProperty, value); }
    public MapProvider Provider { get => (MapProvider)GetValue(ProviderProperty); set => SetValue(ProviderProperty, value); }
    public double CursorTime { get => (double)GetValue(CursorTimeProperty); set => SetValue(CursorTimeProperty, value); }
    public double RangeStart { get => (double)GetValue(RangeStartProperty); set => SetValue(RangeStartProperty, value); }
    public double RangeEnd { get => (double)GetValue(RangeEndProperty); set => SetValue(RangeEndProperty, value); }
    public string? TileCacheDir { get => (string?)GetValue(TileCacheDirProperty); set => SetValue(TileCacheDirProperty, value); }
    public bool ShowMarkers { get => (bool)GetValue(ShowMarkersProperty); set => SetValue(ShowMarkersProperty, value); }
    public bool ShowRoute { get => (bool)GetValue(ShowRouteProperty); set => SetValue(ShowRouteProperty, value); }
    /// <summary>Extra room kept free around the route when fitting (overlays on top of the map).</summary>
    public Thickness FitPadding { get => (Thickness)GetValue(FitPaddingProperty); set => SetValue(FitPaddingProperty, value); }

    public IReadOnlyList<MapShape>? Shapes { get => (IReadOnlyList<MapShape>?)GetValue(ShapesProperty); set => SetValue(ShapesProperty, value); }
    /// <summary>When set, a click (without dragging) sends a <see cref="MapClick"/> instead of selecting the nearest route point.</summary>
    public ICommand? MapClickCommand { get => (ICommand?)GetValue(MapClickCommandProperty); set => SetValue(MapClickCommandProperty, value); }
    private bool _shapesFitted;
    private void OnShapesChanged()
    {
        // without a route, the first shapes decide the view (later edits keep the user's view)
        if (!_shapesFitted && (Tracks is null || Tracks.Count == 0) && Shapes is { Count: > 0 } && !_userMoved) { _shapesFitted = true; FitToRoute(); }
    }

    public double Zoom { get; private set; } = 14.5;
    public static double HomeLatitude { get; set; } = TrainingPlace.Regaton.Latitude;
    public static double HomeLongitude { get; set; } = TrainingPlace.Regaton.Longitude;
    private double _cx = TileMath.LatLonToPixel(TrainingPlace.Regaton.Latitude, TrainingPlace.Regaton.Longitude, 0).x,
                   _cy = TileMath.LatLonToPixel(TrainingPlace.Regaton.Latitude, TrainingPlace.Regaton.Longitude, 0).y;    // view centre in zoom-0 world pixels
    private bool _fitPending = true;
    private bool _userMoved;   // keep the user's view on resize; otherwise the route stays fitted
    private Point? _down; private double _downCx, _downCy; private bool _moved;

    private static readonly HttpClient Http = CreateHttp();
    private static readonly ConcurrentDictionary<string, ImageSource?> TileMemory = new();
    private static readonly ConcurrentDictionary<string, byte> Pending = new();
    private static readonly SemaphoreSlim Gate = new(6);
    private static int _tileFailures;
    public static int LoadedTiles => TileMemory.Count(kv => kv.Value is not null);
    public static int PendingTiles => Pending.Count;

    private static HttpClient CreateHttp()
    {
        var h = new HttpClient { Timeout = TimeSpan.FromSeconds(20) };
        h.DefaultRequestHeaders.UserAgent.ParseAdd("AVO-Performance-Horse-Windows/2.0");
        return h;
    }

    public const string Attribution = "Imágenes: © Esri, Maxar, Earthstar Geographics y GIS User Community";

    public MapControl()
    {
        ClipToBounds = true;
        Cursor = Cursors.Hand;
        SizeChanged += (_, _) => { if (_fitPending || !_userMoved) FitToRoute(); };
    }

    private void OnTracksChanged()
    {
        foreach (var t in Tracks ?? [])
        {
            if (t.Px0 is not null) continue;
            var tl = t.Timeline;
            t.Px0 = new double[tl.Count]; t.Py0 = new double[tl.Count];
            for (int i = 0; i < tl.Count; i++) { var (x, y) = TileMath.LatLonToPixel(tl.Lat[i], tl.Lon[i], 0); t.Px0[i] = x; t.Py0[i] = y; }
        }
        _fitPending = true;
        _userMoved = false;
        FitToRoute();
    }

    public void FitToRoute()
    {
        _userMoved = false;
        var tracks = Tracks ?? [];
        if (ActualWidth < 10 || ActualHeight < 10) { _fitPending = true; return; }
        double minX = double.MaxValue, minY = double.MaxValue, maxX = double.MinValue, maxY = double.MinValue;
        foreach (var t in tracks)
            for (int i = 0; t.Px0 is not null && i < t.Px0.Length; i++)
            { minX = Math.Min(minX, t.Px0[i]); maxX = Math.Max(maxX, t.Px0[i]); minY = Math.Min(minY, t.Py0![i]); maxY = Math.Max(maxY, t.Py0[i]); }
        if (minX > maxX)
            foreach (var sh in Shapes ?? [])
                foreach (var (la, lo) in sh.Points)
                {
                    var (x, y) = TileMath.LatLonToPixel(la, lo, 0);
                    minX = Math.Min(minX, x); maxX = Math.Max(maxX, x); minY = Math.Min(minY, y); maxY = Math.Max(maxY, y);
                }
        if (maxX - minX < 1e-6 && maxX >= minX) { minX -= 0.002; maxX += 0.002; minY -= 0.002; maxY += 0.002; }   // a single point
        if (minX > maxX)
        {
            // No route: show the usual training area (Playa del Regatón, Laredo) instead of an empty ocean at 0°,0°.
            var (hx, hy) = TileMath.LatLonToPixel(HomeLatitude, HomeLongitude, 0);
            _cx = hx; _cy = hy; Zoom = 14.5; _fitPending = false;
            InvalidateVisual();
            return;
        }
        var pad = FitPadding;
        double w = Math.Max(20, ActualWidth - pad.Left - pad.Right), h = Math.Max(20, ActualHeight - pad.Top - pad.Bottom);
        double zx = Math.Log2(w / Math.Max(maxX - minX, 1e-9)), zy = Math.Log2(h / Math.Max(maxY - minY, 1e-9));
        Zoom = Math.Clamp(Math.Min(zx, zy), 2, 19);
        double s = Math.Pow(2, Zoom);
        // centre so that the route sits in the padded area
        _cx = (minX + maxX) / 2 - (pad.Left - pad.Right) / 2 / s;
        _cy = (minY + maxY) / 2 - (pad.Top - pad.Bottom) / 2 / s;
        _fitPending = false;
        InvalidateVisual();
    }

    public void ZoomBy(double delta) { _userMoved = true; Zoom = Math.Clamp(Zoom + delta, 2, 19.5); InvalidateVisual(); }

    private Point Screen(double x0, double y0)
    {
        double s = Math.Pow(2, Zoom);
        return new Point((x0 - _cx) * s + ActualWidth / 2, (y0 - _cy) * s + ActualHeight / 2);
    }

    protected override void OnRender(DrawingContext dc)
    {
        dc.DrawRectangle(new SolidColorBrush(Color.FromRgb(0x0B, 0x0C, 0x10)), null, new Rect(0, 0, ActualWidth, ActualHeight));
        if (Provider != MapProvider.VectorOffline) DrawTiles(dc);
        else DrawGrid(dc);
        var tracks = Tracks ?? [];
        if (ShowRoute) foreach (var t in tracks) DrawTrack(dc, t, tracks.Count > 1);
        foreach (var sh in Shapes ?? []) DrawShape(dc, sh);
        DrawScale(dc);
        if (Provider != MapProvider.VectorOffline)
        {
            var ft = Text(Attribution, 9.5, new SolidColorBrush(Color.FromArgb(0xE0, 0xF2, 0xF2, 0xF4)));
            dc.DrawRectangle(new SolidColorBrush(Color.FromArgb(0x99, 0, 0, 0)), null, new Rect(ActualWidth - ft.Width - 10, ActualHeight - ft.Height - 4, ft.Width + 10, ft.Height + 4));
            dc.DrawText(ft, new Point(ActualWidth - ft.Width - 5, ActualHeight - ft.Height - 2));
        }
        if (tracks.Count == 0)
        {
            var ft = Text("Sin recorrido GNSS: importa o selecciona un entrenamiento", 13, Brushes.White);
            var box = new Rect((ActualWidth - ft.Width) / 2 - 12, (ActualHeight - ft.Height) / 2 - 7, ft.Width + 24, ft.Height + 14);
            dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromArgb(0xCC, 0x10, 0x10, 0x14)), null, box, 5, 5);
            dc.DrawText(ft, new Point(box.X + 12, box.Y + 7));
        }
    }

    private void DrawGrid(DrawingContext dc)
    {
        var pen = new Pen(new SolidColorBrush(Color.FromArgb(0x22, 0xC9, 0xCB, 0xD1)), 1); pen.Freeze();
        for (double x = 0; x < ActualWidth; x += 64) dc.DrawLine(pen, new Point(x, 0), new Point(x, ActualHeight));
        for (double y = 0; y < ActualHeight; y += 64) dc.DrawLine(pen, new Point(0, y), new Point(ActualWidth, y));
        var ft = Text("Modo vectorial sin conexión (sin teselas)", 10, new SolidColorBrush(Color.FromRgb(0x93, 0x94, 0x9B)));
        dc.DrawText(ft, new Point(10, ActualHeight - ft.Height - 6));
    }

    private void DrawTiles(DrawingContext dc)
    {
        int z = (int)Math.Clamp(Math.Floor(Zoom + 0.25), 1, 19);
        double s = Math.Pow(2, Zoom - z);              // screen px per tile px
        double worldScale = Math.Pow(2, z);
        double cx = _cx * worldScale, cy = _cy * worldScale;   // centre in tile-pixel space at z
        double halfW = ActualWidth / 2 / s, halfH = ActualHeight / 2 / s;
        int x0 = (int)Math.Floor((cx - halfW) / 256), x1 = (int)Math.Floor((cx + halfW) / 256);
        int y0 = (int)Math.Floor((cy - halfH) / 256), y1 = (int)Math.Floor((cy + halfH) / 256);
        int max = (1 << z) - 1;
        var layers = Provider == MapProvider.EsriHybrid
            ? new[] { "World_Imagery", "Reference/World_Transportation", "Reference/World_Boundaries_and_Places" }
            : new[] { "World_Imagery" };
        for (int ty = Math.Max(0, y0); ty <= Math.Min(max, y1); ty++)
            for (int tx = x0; tx <= x1; tx++)
            {
                int wx = ((tx % (max + 1)) + max + 1) % (max + 1);
                var rect = new Rect((tx * 256 - cx) * s + ActualWidth / 2, (ty * 256 - cy) * s + ActualHeight / 2, 256 * s + 0.5, 256 * s + 0.5);
                foreach (var layer in layers)
                {
                    var img = Tile(layer, z, wx, ty);
                    if (img is not null) dc.DrawImage(img, rect);
                    else if (layer == "World_Imagery")
                    {
                        // fall back to a parent tile while loading
                        var parent = ParentTile(layer, z, wx, ty, out Rect src);
                        if (parent is not null)
                        {
                            dc.PushClip(new RectangleGeometry(rect));
                            double k = 256 * s / src.Width;
                            dc.DrawImage(parent, new Rect(rect.X - src.X * k, rect.Y - src.Y * k, 256 * k, 256 * k));
                            dc.Pop();
                        }
                    }
                }
            }
    }

    private ImageSource? ParentTile(string layer, int z, int x, int y, out Rect src)
    {
        for (int up = 1; up <= 4 && z - up >= 1; up++)
        {
            int pz = z - up, px = x >> up, py = y >> up;
            if (TileMemory.TryGetValue(Key(layer, pz, px, py), out var img) && img is not null)
            {
                double size = 256.0 / (1 << up);
                src = new Rect((x - (px << up)) * size, (y - (py << up)) * size, size, size);
                return img;
            }
        }
        src = Rect.Empty;
        return null;
    }

    private static string Key(string layer, int z, int x, int y) => $"{layer}/{z}/{y}/{x}";

    private ImageSource? Tile(string layer, int z, int x, int y)
    {
        string key = Key(layer, z, x, y);
        if (TileMemory.TryGetValue(key, out var img)) return img;
        if (_tileFailures > 60) return null;    // offline (60 consecutive failures): stop trying, the vector route is still drawn
        if (Pending.TryAdd(key, 0)) _ = LoadTileAsync(layer, z, x, y, key, TileCacheDir);
        return null;
    }

    private async Task LoadTileAsync(string layer, int z, int x, int y, string key, string? cacheDir)
    {
        await Gate.WaitAsync();
        try
        {
            string ext = layer == "World_Imagery" ? "jpg" : "png";
            string? file = cacheDir is null ? null : Path.Combine(cacheDir, layer.Replace('/', '_'), z.ToString(CultureInfo.InvariantCulture), y.ToString(CultureInfo.InvariantCulture), x + "." + ext);
            byte[]? data = null;
            if (file is not null && File.Exists(file) && DateTime.UtcNow - File.GetLastWriteTimeUtc(file) < TimeSpan.FromDays(30)) data = await File.ReadAllBytesAsync(file);
            if (data is null)
            {
                string url = $"https://server.arcgisonline.com/ArcGIS/rest/services/{layer}/MapServer/tile/{z}/{y}/{x}";
                data = await Http.GetByteArrayAsync(url);
                if (file is not null)
                {
                    Directory.CreateDirectory(Path.GetDirectoryName(file)!);
                    await File.WriteAllBytesAsync(file, data);
                }
            }
            var bmp = await Task.Run(() =>
            {
                var b = new BitmapImage();
                b.BeginInit(); b.CacheOption = BitmapCacheOption.OnLoad; b.StreamSource = new MemoryStream(data); b.EndInit();
                b.Freeze();
                return b;
            });
            TileMemory[key] = bmp;
            Interlocked.Exchange(ref _tileFailures, 0);   // consecutive failures only
        }
        catch (Exception ex) when (ex is HttpRequestException or IOException or TaskCanceledException or NotSupportedException or UnauthorizedAccessException or InvalidOperationException)
        {
            Interlocked.Increment(ref _tileFailures);
            TileMemory[key] = null;
        }
        finally
        {
            Pending.TryRemove(key, out _);
            Gate.Release();
            _ = Dispatcher.BeginInvoke(new Action(InvalidateVisual));
        }
    }

    private static readonly Pen Casing = MakePen(Color.FromArgb(170, 0, 0, 0), 7.5);
    private static Pen MakePen(Color c, double w)
    {
        var p = new Pen(new SolidColorBrush(c), w) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round };
        p.Freeze();
        return p;
    }

    private void DrawTrack(DrawingContext dc, MapTrack t, bool multi)
    {
        var tl = t.Timeline;
        if (t.Px0 is null || t.Py0 is null || tl.Count < 2) return;
        var mode = multi ? RouteColorMode.Single : ColorMode;
        double vmax = Math.Max(0.1, Stats.MaxFinite(tl.SpeedFiltered, 0.1));
        double amax = 2.0;
        const int Bins = 24;
        // screen points, decimated to ~1 point per 1.5 px
        var pts = new Point[tl.Count];
        for (int i = 0; i < tl.Count; i++) pts[i] = Screen(t.Px0[i], t.Py0[i]);
        var keys = new int[tl.Count];
        var palette = new Dictionary<int, Color>();
        for (int i = 0; i < tl.Count; i++)
        {
            Color c;
            int key;
            switch (mode)
            {
                case RouteColorMode.Speed:
                {
                    int b = (int)Math.Round(Math.Clamp(tl.SpeedFiltered[i] / vmax, 0, 1) * (Bins - 1));
                    var (r, g, bb) = SpeedScale.Color(b / (double)(Bins - 1), 1); key = b; c = Color.FromRgb(r, g, bb); break;
                }
                case RouteColorMode.Acceleration:
                {
                    double a = SegmentAnalyzer.AccelValid(tl, i) ? tl.AccelLong[i] : 0;
                    int b = (int)Math.Round((Math.Clamp(a / amax, -1, 1) + 1) / 2 * (Bins - 1));
                    var (r, g, bb) = SpeedScale.Diverging((b / (double)(Bins - 1)) * 2 - 1, 1); key = 100 + b; c = Color.FromRgb(r, g, bb); break;
                }
                case RouteColorMode.GnssQuality:
                {
                    var (r, g, bb) = SpeedScale.Solution(tl.Solution[i]); key = 200 + (int)tl.Solution[i]; c = Color.FromRgb(r, g, bb); break;
                }
                case RouteColorMode.Gait:
                {
                    int code = t.Gait is not null && i < t.Gait.Length ? t.Gait[i] : -1;
                    var (r, g, bb) = SpeedScale.Gait(code); key = 300 + code; c = Color.FromRgb(r, g, bb); break;
                }
                default: key = 400; c = t.SingleColor; break;
            }
            keys[i] = key;
            palette[key] = c;
        }
        // casing first
        var casingGeo = new StreamGeometry();
        using (var g = casingGeo.Open()) AddRuns(g, pts, tl, _ => true);
        casingGeo.Freeze();
        dc.DrawGeometry(null, Casing, casingGeo);
        // With a selected range (chart selection or segment) only the range keeps its colours; the rest is dimmed.
        bool ranged = !multi && double.IsFinite(RangeStart) && double.IsFinite(RangeEnd) && Math.Abs(RangeEnd - RangeStart) > 0.5;
        double ra = Math.Min(RangeStart, RangeEnd), rb = Math.Max(RangeStart, RangeEnd);
        if (ranged)
        {
            var dim = new StreamGeometry();
            using (var g = dim.Open()) AddRuns(g, pts, tl, i => tl.T[i] < ra || tl.T[i] > rb);
            dim.Freeze();
            dc.DrawGeometry(null, MakePen(Color.FromArgb(0xB0, 0x93, 0x94, 0x9B), 3.2), dim);
        }
        foreach (var kv in palette)
        {
            var geo = new StreamGeometry();
            int k = kv.Key;
            using (var g = geo.Open()) AddRuns(g, pts, tl, i => keys[i] == k && (!ranged || (tl.T[i] >= ra && tl.T[i] <= rb)));
            geo.Freeze();
            dc.DrawGeometry(null, MakePen(kv.Value, ranged ? 5 : 4.2), geo);
        }
        if (ShowMarkers && !multi)
        {
            Marker(dc, pts[0], Color.FromRgb(0x52, 0xDD, 0x40), "Inicio");
            Marker(dc, pts[^1], Color.FromRgb(0xED, 0x12, 0x2A), "Fin");
        }
        else if (multi)
        {
            dc.DrawEllipse(new SolidColorBrush(t.SingleColor), new Pen(Brushes.White, 1.5), pts[0], 5, 5);
        }
        if (double.IsFinite(CursorTime))
        {
            int ci = tl.IndexAt(CursorTime);
            if (ci >= 0 && (Math.Abs(tl.T[ci] - CursorTime) < 3 || !multi))
            {
                dc.DrawEllipse(Brushes.White, new Pen(new SolidColorBrush(Color.FromRgb(0xED, 0x12, 0x2A)), 3), pts[ci], 7, 7);
            }
        }
    }

    private static void AddRuns(StreamGeometryContext g, Point[] pts, SessionTimeline tl, Func<int, bool> include)
    {
        bool open = false;
        Point last = default;
        for (int i = 1; i < pts.Length; i++)
        {
            bool ok = include(i) && !tl.BreakBefore[i] && !tl.JumpBefore[i];
            if (!ok) { open = false; continue; }
            if (!open) { g.BeginFigure(pts[i - 1], false, false); open = true; last = pts[i - 1]; }
            if (Math.Abs(pts[i].X - last.X) + Math.Abs(pts[i].Y - last.Y) < 1.2 && i < pts.Length - 1) continue;
            g.LineTo(pts[i], true, true);
            last = pts[i];
        }
    }

    private void Marker(DrawingContext dc, Point p, Color c, string label)
    {
        dc.DrawEllipse(new SolidColorBrush(c), new Pen(Brushes.White, 2), p, 7, 7);
        var ft = Text(label, 11, Brushes.White);
        var box = new Rect(p.X + 10, p.Y - 22, ft.Width + 12, ft.Height + 4);
        dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromArgb(0xD8, 0x10, 0x10, 0x14)), new Pen(new SolidColorBrush(c), 1), box, 3, 3);
        dc.DrawText(ft, new Point(box.X + 6, box.Y + 2));
    }

    private Point ScreenOf(double lat, double lon) { var (x, y) = TileMath.LatLonToPixel(lat, lon, 0); return Screen(x, y); }

    private void DrawShape(DrawingContext dc, MapShape sh)
    {
        if (sh.Points.Count == 0) return;
        var pts = sh.Points.Select(p => ScreenOf(p.Lat, p.Lon)).ToArray();
        var pen = new Pen(new SolidColorBrush(sh.Stroke), sh.Thickness) { LineJoin = PenLineJoin.Round, StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
        if (pts.Length > 1)
        {
            var g = new StreamGeometry();
            using (var c = g.Open())
            {
                c.BeginFigure(pts[0], sh.Closed && sh.Fill.A > 0, sh.Closed);
                c.PolyLineTo(pts.Skip(1).ToList(), true, true);
            }
            g.Freeze();
            dc.DrawGeometry(sh.Closed && sh.Fill.A > 0 ? new SolidColorBrush(sh.Fill) : null, pen, g);
        }
        var white = new Pen(Brushes.White, 1.5);
        if (sh.ShowVertices || pts.Length == 1)
            foreach (var p in pts) dc.DrawEllipse(new SolidColorBrush(sh.Stroke), white, p, 4.5, 4.5);
        if (sh.Arrow != 0 && pts.Length >= 2)
        {
            var a = pts[0]; var b = pts[^1];
            var m = new Point((a.X + b.X) / 2, (a.Y + b.Y) / 2);
            double dx = b.X - a.X, dy = b.Y - a.Y, len = Math.Sqrt(dx * dx + dy * dy);
            if (len > 4)
            {
                // left of A→B on screen (north up, y down) = (dy, -dx)/len ; a left→right crossing points the other way
                var lr = new Vector(-dy / len, dx / len);
                void Arrow(Vector dir)
                {
                    var tip = m + dir * 30;
                    var side = new Vector(-dir.Y, dir.X);
                    dc.DrawLine(pen, m, tip);
                    var head = new StreamGeometry();
                    using (var c = head.Open()) { c.BeginFigure(tip, true, true); c.LineTo(tip - dir * 10 + side * 6, true, true); c.LineTo(tip - dir * 10 - side * 6, true, true); }
                    head.Freeze();
                    dc.DrawGeometry(new SolidColorBrush(sh.Stroke), null, head);
                }
                if (sh.Arrow is 1 or 2) Arrow(lr);
                if (sh.Arrow is -1 or 2) Arrow(-lr);
            }
        }
        if (sh.EndLabels && pts.Length >= 2)
        {
            dc.DrawText(Text("A", 11, Brushes.White), pts[0] + new Vector(6, -16));
            dc.DrawText(Text("B", 11, Brushes.White), pts[^1] + new Vector(6, -16));
        }
        if (!string.IsNullOrEmpty(sh.Label))
        {
            var at = pts.Length > 2 && sh.Closed ? new Point(pts.Average(p => p.X), pts.Average(p => p.Y)) : pts[0];
            var ft = Text(sh.Label, 11, Brushes.White);
            var box = new Rect(at.X - ft.Width / 2 - 5, at.Y - ft.Height - 10, ft.Width + 10, ft.Height + 4);
            dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromArgb(0xD8, 0x10, 0x10, 0x14)), new Pen(new SolidColorBrush(sh.Stroke), 1), box, 3, 3);
            dc.DrawText(ft, new Point(box.X + 5, box.Y + 2));
        }
    }

    private void DrawScale(DrawingContext dc)
    {
        double lat = TileMath.PixelToLatLon(_cx, _cy, 0).lat;
        double mpp = TileMath.MetersPerPixel(lat, Zoom);
        double target = mpp * 110;
        double nice = new double[] { 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000 }.OrderBy(v => Math.Abs(v - target)).First();
        double px = nice / mpp;
        double x = 14, y = ActualHeight - 26;
        dc.DrawRectangle(new SolidColorBrush(Color.FromArgb(0xB0, 0x10, 0x10, 0x14)), null, new Rect(x - 6, y - 18, px + 12, 30));
        var pen = new Pen(Brushes.White, 2); pen.Freeze();
        dc.DrawLine(pen, new Point(x, y + 6), new Point(x + px, y + 6));
        dc.DrawLine(pen, new Point(x, y + 1), new Point(x, y + 8));
        dc.DrawLine(pen, new Point(x + px, y + 1), new Point(x + px, y + 8));
        dc.DrawText(Text(nice >= 1000 ? $"{nice / 1000:0} km" : $"{nice:0} m", 10.5, Brushes.White), new Point(x, y - 15));
    }

    private FormattedText Text(string s, double size, Brush brush) =>
        new(s, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, new Typeface("Segoe UI"), size, brush, VisualTreeHelper.GetDpi(this).PixelsPerDip);

    // ------------------------------------------------------------------ interaction
    protected override void OnMouseWheel(MouseWheelEventArgs e)
    {
        base.OnMouseWheel(e);
        var pos = e.GetPosition(this);
        double s0 = Math.Pow(2, Zoom);
        double wx = _cx + (pos.X - ActualWidth / 2) / s0, wy = _cy + (pos.Y - ActualHeight / 2) / s0;
        _userMoved = true;
        Zoom = Math.Clamp(Zoom + (e.Delta > 0 ? 0.5 : -0.5), 2, 19.5);
        double s1 = Math.Pow(2, Zoom);
        _cx = wx - (pos.X - ActualWidth / 2) / s1; _cy = wy - (pos.Y - ActualHeight / 2) / s1;
        InvalidateVisual();
        e.Handled = true;
    }

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonDown(e);
        if (e.ClickCount == 2) { _userMoved = false; FitToRoute(); return; }
        _down = e.GetPosition(this); _downCx = _cx; _downCy = _cy; _moved = false;
        CaptureMouse();
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        if (_down is not Point d || e.LeftButton != MouseButtonState.Pressed) return;
        var p = e.GetPosition(this);
        if (Math.Abs(p.X - d.X) + Math.Abs(p.Y - d.Y) > 3) _moved = true;
        if (!_moved) return;
        _userMoved = true;
        double s = Math.Pow(2, Zoom);
        _cx = _downCx - (p.X - d.X) / s; _cy = _downCy - (p.Y - d.Y) / s;
        InvalidateVisual();
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonUp(e);
        ReleaseMouseCapture();
        if (_down is Point d && !_moved)
        {
            if (MapClickCommand is { } cmd)
            {
                double sc = Math.Pow(2, Zoom);
                var (lat, lon) = TileMath.PixelToLatLon(_cx + (d.X - ActualWidth / 2) / sc, _cy + (d.Y - ActualHeight / 2) / sc, 0);
                var click = new MapClick(lat, lon);
                if (cmd.CanExecute(click)) cmd.Execute(click);
            }
            else SelectNearest(d);
        }
        _down = null;
    }

    private void SelectNearest(Point p)
    {
        double best = 14 * 14; double? bestT = null;
        foreach (var t in Tracks ?? [])
        {
            if (t.Px0 is null || t.Py0 is null) continue;
            for (int i = 0; i < t.Px0.Length; i++)
            {
                var q = Screen(t.Px0[i], t.Py0[i]);
                double d2 = (q.X - p.X) * (q.X - p.X) + (q.Y - p.Y) * (q.Y - p.Y);
                if (d2 < best) { best = d2; bestT = t.Timeline.T[i]; }
            }
        }
        if (bestT is double tt) CursorTime = tt;
    }
}
