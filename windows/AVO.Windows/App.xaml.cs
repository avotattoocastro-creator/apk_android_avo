using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Avo.Windows.Controls;
using Avo.Windows.Core;
using Avo.Windows.ViewModels;

namespace Avo.Windows;

public partial class App : Application
{
    private sealed class SilentDialogs(AppLog log) : IDialogs
    {
        public string[] OpenTrainingFiles() => [];
        public string? OpenFolder() => null;
        public string? SaveFile(string filter, string defaultName) => null;
        public void Show(string title, string message, bool error = false) => log.Write(error ? "AVISO" : "INFO", "dialogo", $"{title}: {message}");
    }

    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        var args = e.Args;
        string? Arg(string name) { int i = Array.IndexOf(args, name); return i >= 0 && i + 1 < args.Length ? args[i + 1] : null; }
        var paths = new AppPaths(Arg("--root"));
        var vm = new MainViewModel(paths, new SilentDialogs(new AppLog(paths.Logs)));
        DispatcherUnhandledException += (_, ex) =>
        {
            vm.Log.Error("app", "Excepción no controlada", ex.Exception);
            if (Arg("--capture") is null) MessageBox.Show(ex.Exception.Message, "AVO Performance Horse", MessageBoxButton.OK, MessageBoxImage.Error);
            ex.Handled = true;
        };
        TaskScheduler.UnobservedTaskException += (_, ex) => { vm.Log.Error("app", "Tarea no observada", ex.Exception); ex.SetObserved(); };
        vm.Log.Info("app", "Inicio", new { version = MainViewModel.Version, os = Environment.OSVersion.VersionString, motor = EquineEngine.Available ? EquineEngine.Version() : "no disponible" });

        var window = new MainWindow(vm);
        MainWindow = window;
        if (Arg("--capture") is string captureDir)
        {
            vm.Dialogs = new SilentDialogs(vm.Log);
            int code = 0;
            try { await CaptureAsync(window, vm, captureDir, Arg("--demo"), Arg("--sizes") ?? "1920x1080,1366x768,2560x1440@150"); }
            catch (Exception ex)
            {
                code = 1;
                Directory.CreateDirectory(captureDir);
                File.WriteAllText(Path.Combine(captureDir, "ERROR.txt"), ex.ToString());
            }
            Shutdown(code);
            return;
        }
        window.Show();
        var files = args.Where(a => !a.StartsWith("--", StringComparison.Ordinal) && File.Exists(a)).ToArray();
        await vm.RestoreLibraryAsync();
        if (files.Length > 0) await vm.ImportFilesAsync(files);
    }

    // ------------------------------------------------------------------ capture mode (CI visual evidence)
    private static readonly string[] Pages = ["Home", "Analysis", "Map", "Charts", "Segments", "Biomech", "Compare", "Tides", "Reports", "Server", "Engine"];

    private static async Task CaptureAsync(MainWindow window, MainViewModel vm, string dir, string? demoDir, string sizes)
    {
        Directory.CreateDirectory(dir);
        var perf = new Dictionary<string, object?>();
        var sw = Stopwatch.StartNew();
        window.WindowStyle = WindowStyle.None;
        window.ResizeMode = ResizeMode.NoResize;
        window.MinWidth = 0; window.MinHeight = 0;
        window.WindowStartupLocation = WindowStartupLocation.Manual;
        window.Left = 0; window.Top = 0;
        window.Show();
        await Idle();
        perf["arranque_ms"] = sw.ElapsedMilliseconds;
        if (demoDir is not null && Directory.Exists(demoDir))
        {
            sw.Restart();
            var files = Directory.GetFiles(demoDir).Where(f => f.EndsWith(".avr", StringComparison.OrdinalIgnoreCase) || f.EndsWith(".avo", StringComparison.OrdinalIgnoreCase)).OrderBy(f => f).ToArray();
            await vm.ImportFilesAsync(files);
            perf["importacion_ms"] = sw.ElapsedMilliseconds;
            perf["sesiones"] = vm.Sessions.Count;
            sw.Restart();
            await vm.RunEngineForAllAsync();
            perf["motor_ms"] = sw.ElapsedMilliseconds;
        }
        var main = vm.Sessions.Where(s => s.HasGirth).OrderByDescending(s => s.Start).FirstOrDefault() ?? vm.Sessions.FirstOrDefault();
        if (main is not null)
        {
            vm.Selected = main;
            await Idle();
            if (main.SegmentDefs.Count == 0)
            {
                if (main.Engine is { HasImu: true }) vm.EngineSegmentsCommand.Execute(null);
                else vm.AutoSpeedBandCommand.Execute(null);
            }
            double t = main.Timeline.T[0] + main.Timeline.DurationS * 0.58;
            vm.RangeStart = main.Timeline.T[0] + main.Timeline.DurationS * 0.50;
            vm.RangeEnd = main.Timeline.T[0] + main.Timeline.DurationS * 0.66;
            vm.CursorTime = t;
            vm.SelectedSegment = vm.SegmentRows.Skip(2).FirstOrDefault() ?? vm.SegmentRows.FirstOrDefault();
            vm.CursorTime = t;
            vm.Page = "Tides";
            await vm.LoadEnvironmentAsync(true);
            vm.ReportCompare = true;
        }
        // Hosted runners have a 1280x768 screen and Windows clamps resizable captioned windows to it. In capture mode the window
        // is a borderless, non-resizable popup, which may be larger than the screen, so 1920x1080 and 2560x1440 are real sizes.
        var root = (FrameworkElement)window.Content;
        var report = new List<object>();
        foreach (var spec in sizes.Split(',', StringSplitOptions.RemoveEmptyEntries))
        {
            var parts = spec.Split('@');
            var wh = parts[0].Split('x');
            double w = double.Parse(wh[0], System.Globalization.CultureInfo.InvariantCulture), h = double.Parse(wh[1], System.Globalization.CultureInfo.InvariantCulture);
            double scale = parts.Length > 1 ? double.Parse(parts[1], System.Globalization.CultureInfo.InvariantCulture) / 100 : 1;
            double lw = w / scale, lh = h / scale;
            window.Width = lw; window.Height = lh;
            Layout(root, lw, lh);
            await Idle();
            int n = 0;
            foreach (var page in Pages)
            {
                vm.Page = page;
                Layout(root, lw, lh);
                await Idle();
                Layout(root, lw, lh);
                if (page is "Map" or "Analysis" or "Segments" or "Compare" or "Reports") { await WaitTilesAsync(); Layout(root, lw, lh); }
                await Idle();
                Layout(root, lw, lh);
                string name = $"{(int)w}x{(int)h}{(scale != 1 ? $"@{scale * 100:0}" : "")}_{++n:00}_{page}.png";
                var sizeInfo = Render(root, Path.Combine(dir, name), scale);
                report.Add(new { archivo = name, pagina = page, ancho = sizeInfo.w, alto = sizeInfo.h, escala = scale, raiz = $"{root.ActualWidth:0}x{root.ActualHeight:0}", ventana = $"{window.ActualWidth:0}x{window.ActualHeight:0}" });
            }
        }
        // exports produced by the same code paths as the buttons
        if (vm.BuildReportData() is ReportData data)
        {
            sw.Restart();
            await vm.ExportToAsync(data, Path.Combine(dir, "informe_demo.pdf"), (d, p) => { using var f = File.Create(p); ReportBuilder.WritePdf(d, f); });
            perf["pdf_ms"] = sw.ElapsedMilliseconds;
            await vm.ExportToAsync(data, Path.Combine(dir, "informe_demo.html"), (d, p) => File.WriteAllText(p, ReportBuilder.Html(d), new UTF8Encoding(false)));
            await vm.ExportToAsync(data, Path.Combine(dir, "serie_demo.csv"), (d, p) => AnalysisExport.TimelineCsv(d.Timeline, p));
            await vm.ExportToAsync(data, Path.Combine(dir, "recorrido_demo.gpx"), (d, p) => AnalysisExport.Gpx(d.Session, d.Timeline, p));
            await vm.ExportToAsync(data, Path.Combine(dir, "analisis_demo.json"), (d, p) => File.WriteAllText(p, AnalysisExport.Json(d.Session, d.Timeline, d.Segments, d.Engine, false)));
        }
        perf["memoria_trabajo_mb"] = Process.GetCurrentProcess().WorkingSet64 / 1048576.0;
        perf["memoria_gc_mb"] = GC.GetTotalMemory(false) / 1048576.0;
        perf["teselas_cargadas"] = MapControl.LoadedTiles;
        perf["motor"] = vm.EngineInfo;
        perf["entorno"] = vm.EnvironmentStatus;
        perf["capturas"] = report;
        File.WriteAllText(Path.Combine(dir, "capture-report.json"), JsonSerializer.Serialize(perf, new JsonSerializerOptions { WriteIndented = true }));
    }

    private static async Task WaitTilesAsync()
    {
        var limit = DateTime.UtcNow.AddSeconds(25);
        await Task.Delay(300);
        while (DateTime.UtcNow < limit && MapControl.PendingTiles > 0) await Task.Delay(250);
        await Idle();
    }

    private static async Task Idle()
    {
        await Current.Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle);
        await Task.Delay(120);
        await Current.Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle);
    }

    private static void Layout(FrameworkElement root, double w, double h)
    {
        root.Width = w; root.Height = h;
        root.UpdateLayout();
    }

    private static (int w, int h) Render(FrameworkElement root, string file, double scale)
    {
        root.UpdateLayout();
        int pw = (int)Math.Round(root.ActualWidth * scale), ph = (int)Math.Round(root.ActualHeight * scale);
        var rtb = new RenderTargetBitmap(pw, ph, 96 * scale, 96 * scale, PixelFormats.Pbgra32);
        var bg = new DrawingVisual();
        using (var dc = bg.RenderOpen()) dc.DrawRectangle((Brush)Current.Resources["AvoBg"], null, new Rect(0, 0, root.ActualWidth, root.ActualHeight));
        rtb.Render(bg);
        rtb.Render(root);   // the element itself (not a VisualBrush, which would rescale to the descendants' bounds)
        var enc = new PngBitmapEncoder();
        enc.Frames.Add(BitmapFrame.Create(rtb));
        using var f = File.Create(file);
        enc.Save(f);
        return (pw, ph);
    }
}
