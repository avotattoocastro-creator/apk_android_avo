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
        public string[] NextOpen { get; set; } = [];
        public int OpenCalls { get; private set; }
        public string[] OpenTrainingFiles() { OpenCalls++; var r = NextOpen; NextOpen = []; return r; }
        public string? OpenFolder() => null;
        public string? SaveFile(string filter, string defaultName) => null;
        public void Show(string title, string message, bool error = false) => log.Write(error ? "AVISO" : "INFO", "dialogo", $"{title}: {message}");
        public bool ConfirmAnswer { get; set; } = true;
        public bool Confirm(string title, string message) { log.Write("INFO", "dialogo", $"{title}: {message} → {(ConfirmAnswer ? "sí" : "no")}"); return ConfirmAnswer; }
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
            vm.UsbEnabled = false;
            vm.UseNfcReader(new SimulatedNfcReader());
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
    private static readonly string[] Pages = ["Home", "Sessions", "Stable", "Riders", "Analysis", "Map", "Charts", "Segments", "Biomech", "Compare", "Geofences", "Tides", "Reports", "Server", "Engine"];

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
        // ---- functional check of the five start-screen actions, clicked through UI Automation like a user
        var clicks = new List<object>();
        var dialogs = (SilentDialogs)vm.Dialogs;
        var demoFiles = demoDir is not null && Directory.Exists(demoDir) ? Directory.GetFiles(demoDir, "*.avr").OrderBy(f => f).ToArray() : [];
        var start = FindAll<Avo.Windows.Views.StartView>(window).FirstOrDefault() ?? throw new InvalidOperationException("No se encuentra la pantalla de inicio");
        var buttons = FindAll<System.Windows.Controls.Button>(start).ToList();
        if (buttons.Count != 5) throw new InvalidOperationException($"La pantalla de inicio tiene {buttons.Count} acciones, se esperaban 5");
        string[] labels = ["Abrir entrenamiento", "Sesiones recientes", "Servidor AVO", "Comparar entrenamientos", "Informes"];
        string[] expected = ["Analysis", "Sessions", "Server", "Compare", "Reports"];
        for (int i = 0; i < 5; i++)
        {
            vm.Page = "Home";
            await Idle();
            if (i == 0 && demoFiles.Length > 0) dialogs.NextOpen = [demoFiles[^1]];
            var peer = new System.Windows.Automation.Peers.ButtonAutomationPeer(buttons[i]);
            ((System.Windows.Automation.Provider.IInvokeProvider)peer.GetPattern(System.Windows.Automation.Peers.PatternInterface.Invoke)!).Invoke();
            var limit = DateTime.UtcNow.AddSeconds(30);
            while (vm.Page == "Home" && DateTime.UtcNow < limit) await Task.Delay(100);
            await Idle();
            bool ok = vm.Page == expected[i] && (i != 0 || (dialogs.OpenCalls == 1 && vm.Sessions.Count == 1));
            clicks.Add(new { accion = labels[i], pagina = vm.Page, esperada = expected[i], correcto = ok });
            if (!ok) throw new InvalidOperationException($"Acción de inicio «{labels[i]}» llevó a «{vm.Page}» (esperado «{expected[i]}»)");
            if (i > 0) Render(window.Content is FrameworkElement fe0 ? fe0 : window, Path.Combine(dir, $"inicio_accion_{i + 1}_{expected[i]}.png"), 1);
        }
        perf["acciones_inicio"] = clicks;
        vm.Page = "Home";
        await Idle();
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
        perf["nfc_cuadra"] = await NfcWalkthroughAsync(window, vm, dir, main);
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
            vm.LoadExampleGeofences();
            vm.Page = "Tides";
            await vm.LoadEnvironmentAsync(true);
            vm.ReportCompare = true;
        }
        // Hosted runners have a 1280x768 screen and Windows clamps resizable captioned windows to it. In capture mode the window
        // is a borderless, non-resizable popup, which may be larger than the screen, so 1920x1080 and 2560x1440 are real sizes.
        // The content is moved into a Canvas, which arranges it at its explicit size without a layout clip, so it renders
        // completely even when the window itself is smaller than the requested capture size.
        var root = (FrameworkElement)window.Content;
        window.Content = null;
        var canvas = new System.Windows.Controls.Canvas();
        canvas.Children.Add(root);
        window.Content = canvas;
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

    /// <summary>
    /// Cuadra / Jinetes / assignment / NFC through the real view models with a SIMULATED reader (no hardware on the runner):
    /// tags in the Android format are "presented", registered, used in the assignment panel and written. Fails the capture if
    /// any step does not do what it should.
    /// </summary>
    private static async Task<object> NfcWalkthroughAsync(MainWindow window, MainViewModel vm, string dir, SessionItem? main)
    {
        var sim = (SimulatedNfcReader)vm.Nfc;
        var steps = new List<object>();
        void Check(bool ok, string what) { steps.Add(new { paso = what, correcto = ok }); if (!ok) throw new InvalidOperationException("NFC/Cuadra: " + what); }
        var horse = new IdentityRecord { Code = "HORSE_901", Name = "Tormenta (prueba NFC)", Breed = "PRE", BirthYear = 2017, Notes = "Etiqueta simulada en CI" };
        var rider = new IdentityRecord { Code = "RIDER_901", Name = "Lucía (prueba NFC)", Notes = "Tarjeta simulada en CI" };
        vm.Page = "Stable";
        await Idle();
        sim.Present("04A1B2C3D4E5F6", AvoIdentityTag.BuildUri(IdentityKind.Horse, horse));
        await Idle();
        Check(vm.Stable.Find(IdentityKind.Horse, "HORSE_901") is { Name: "Tormenta (prueba NFC)", Breed: "PRE", BirthYear: 2017, NfcUid: "04A1B2C3D4E5F6" }, "etiqueta de caballo registrada en la Cuadra");
        Check(vm.Page == "Stable" && vm.HorsesPage.Selected?.Code == "HORSE_901", "la Cuadra muestra el caballo leído");
        vm.Page = "Riders";
        await Idle();
        sim.Present("04112233445566", AvoIdentityTag.BuildUri(IdentityKind.Rider, rider));
        await Idle();
        Check(vm.Stable.Find(IdentityKind.Rider, "RIDER_901") is { Name: "Lucía (prueba NFC)" } && vm.RidersPage.Selected?.Code == "RIDER_901", "tarjeta de jinete registrada en Jinetes");
        // a second read never overwrites what the user has
        vm.Stable.Update(IdentityKind.Horse, "HORSE_901", r => r.Notes = "editado en el PC");
        sim.Present("04A1B2C3D4E5F6", AvoIdentityTag.BuildUri(IdentityKind.Horse, horse));
        await Idle();
        Check(vm.Stable.Find(IdentityKind.Horse, "HORSE_901")!.Notes == "editado en el PC", "releer la etiqueta no sobrescribe la ficha");
        sim.Present("04FFFFFFFFFFFF", "https://example.org/otra");
        await Idle();
        Check(!vm.NfcLastOk && vm.Stable.Horses.All(h => h.Code != ""), "etiqueta no AVO rechazada");
        // assignment of a training through the panel, filled by NFC
        var target = vm.Sessions.Where(s => s != main).OrderBy(s => s.Start).FirstOrDefault() ?? main;
        if (target is not null)
        {
            vm.Page = "Sessions";
            vm.OpenAssignCommand.Execute(target);
            await Idle();
            sim.Present("04A1B2C3D4E5F6", AvoIdentityTag.BuildUri(IdentityKind.Horse, horse));
            sim.Present("04112233445566", AvoIdentityTag.BuildUri(IdentityKind.Rider, rider));
            await Idle();
            Check(vm.AssignVisible && vm.AssignHorseText == "Tormenta (prueba NFC)" && vm.AssignRiderText == "Lucía (prueba NFC)", "el panel Asignar se rellena con las etiquetas");
            Render(window.Content is FrameworkElement fe ? fe : window, Path.Combine(dir, "asignar_caballo_jinete.png"), 1);
            vm.ConfirmAssignCommand.Execute(null);
            await Idle();
            Check(!vm.AssignVisible && target.Horse == "Tormenta (prueba NFC)" && target.Rider == "Lucía (prueba NFC)" && target.HorseCode == "HORSE_901", "entrenamiento asignado");
            Check(vm.HorsesPage.Items.First(i => i.Code == "HORSE_901").Count == 1 && vm.RidersPage.Items.First(i => i.Code == "RIDER_901").Count == 1, "el entrenamiento aparece en la ficha del caballo y del jinete");
            Check(File.Exists(target.Session.RawSegmentPaths.FirstOrDefault() ?? "") || target.Session.RawSegmentPaths.Count == 0, "archivo original intacto");
        }
        // write a tag from the record
        vm.Page = "Stable";
        vm.HorsesPage.Select("HORSE_901");
        vm.HorsesPage.WriteTagCommand.Execute(null);
        Check(vm.WriteArmed && sim.WriteArmed, "grabación de etiqueta preparada");
        sim.Present("04CAFE0000BEEF", "");
        await Idle();
        var expected = Ndef.UriMessage(AvoIdentityTag.BuildUri(IdentityKind.Horse, vm.Stable.Find(IdentityKind.Horse, "HORSE_901")!));
        Check(!vm.WriteArmed && sim.LastWritten is { } w && w.AsSpan().SequenceEqual(expected) && vm.Stable.Find(IdentityKind.Horse, "HORSE_901")!.NfcUid == "04CAFE0000BEEF",
            "etiqueta grabada con el formato Android y asociada a la ficha");
        vm.HorsesPage.Select("HORSE_901");
        vm.RidersPage.Select("RIDER_901");
        await Idle();
        return steps;
    }

    private static IEnumerable<T> FindAll<T>(DependencyObject root) where T : DependencyObject
    {
        int n = VisualTreeHelper.GetChildrenCount(root);
        for (int i = 0; i < n; i++)
        {
            var c = VisualTreeHelper.GetChild(root, i);
            if (c is T t) yield return t;
            foreach (var d in FindAll<T>(c)) yield return d;
        }
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
