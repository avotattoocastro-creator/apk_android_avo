using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Threading;
using Avo.Windows.Controls;
using Avo.Windows.Core;

namespace Avo.Windows.ViewModels;

public sealed record ImportLogRow(string Time, string File, string Result, bool Ok);
public sealed record HorseCard(string Name, int Sessions, string LastDate, string BestSpeed);

/// <summary>
/// Shell view model: sessions, navigation, shared cursor/selection (two-way between map and charts), playback, engine.
/// Calculation-heavy work always runs on the thread pool; the UI thread only receives results.
/// </summary>
public sealed partial class MainViewModel : ObservableObject
{
    public static readonly CultureInfo Es = CultureInfo.GetCultureInfo("es-ES");
    public const string AppTitle = "AVO Performance Horse — Windows Advanced Analysis V2 PRO";
    public static string Version => typeof(MainViewModel).Assembly.GetName().Version?.ToString(3) ?? "2.0.0";

    public AppPaths Paths { get; }
    public AppSettings Settings { get; }
    public AppLog Log { get; }
    private readonly TrainingLibrary _library;
    private readonly SegmentStore _segmentStore;
    public IDialogs Dialogs { get; set; }

    public ObservableCollection<SessionItem> Sessions { get; } = [];
    public ICollectionView SessionsView { get; }
    public ObservableCollection<ImportLogRow> ImportLog { get; } = [];
    public ObservableCollection<HorseCard> Horses { get; } = [];

    public MainViewModel(AppPaths paths, IDialogs dialogs)
    {
        Paths = paths;
        Directory.CreateDirectory(paths.Root);
        Log = new AppLog(paths.Logs);
        AppLog.Current = Log;
        Settings = AppSettings.Load(paths.SettingsFile);
        _library = new TrainingLibrary(paths);
        _segmentStore = new SegmentStore(paths.Segments);
        _environment = new EnvironmentService(paths.EnvironmentCache);
        Dialogs = dialogs;
        _mapProvider = Settings.Map;
        SessionsView = CollectionViewSource.GetDefaultView(Sessions);
        SessionsView.Filter = o => o is SessionItem s && MatchesFilter(s);
        SessionsView.SortDescriptions.Add(new SortDescription(nameof(SessionItem.Start), ListSortDirection.Descending));

        NavigateCommand = new RelayCommand(p => { if (p is string s) Page = s; });
        ImportCommand = new AsyncCommand(_ => ImportFilesAsync(Dialogs.OpenTrainingFiles()), Fail);
        ImportFolderCommand = new AsyncCommand(async _ =>
        {
            var dir = Dialogs.OpenFolder();
            if (dir is null) return;
            var files = Directory.EnumerateFiles(dir, "*.*", SearchOption.TopDirectoryOnly)
                .Where(f => f.EndsWith(".avo", StringComparison.OrdinalIgnoreCase) || f.EndsWith(".avr", StringComparison.OrdinalIgnoreCase)).Take(200).ToArray();
            await ImportFilesAsync(files);
        }, Fail);
        RunEngineCommand = new AsyncCommand(_ => Selected is null ? Task.CompletedTask : RunEngineAsync(Selected, true), Fail);
        PlayCommand = new RelayCommand(TogglePlay, () => Selected is not null);
        ResetZoomCommand = new RelayCommand(() => { ChartXMin = double.NaN; ChartXMax = double.NaN; });
        ClearRangeCommand = new RelayCommand(() => { RangeStart = double.NaN; RangeEnd = double.NaN; });
        LoadDemoCommand = new AsyncCommand(_ => LoadDemoAsync(), Fail);
        OpenSessionCommand = new RelayCommand(p => { if (p is SessionItem s) { Selected = s; Page = "Analysis"; } });
        _timer = new DispatcherTimer(DispatcherPriority.Render) { Interval = TimeSpan.FromMilliseconds(50) };
        _timer.Tick += (_, _) => PlaybackTick();
        InitFavorites();
        InitWindows();
        InitUsb();
        InitSegments();
        InitCompare();
        InitReports();
        InitServer();
        InitEnvironment();
    }

    private void Fail(Exception ex)
    {
        Log.Error("ui", ex.Message, ex);
        Status = "Error: " + ex.Message;
        Dialogs.Show("AVO Performance Horse", ex.Message, true);
    }

    // ------------------------------------------------------------------ navigation & status
    private string _page = "Home";
    public string Page { get => _page; set { if (Set(ref _page, value)) OnPageChanged(); } }
    private void OnPageChanged()
    {
        if (Page == "Compare") RefreshCompare();
        if (Page == "Tides") _ = LoadEnvironmentAsync(false);
        if (Page == "Reports") RefreshReportPreview();
        Raise(nameof(ShowEmptyState));
    }

    /// <summary>Analysis pages without any training: show a clear «import / demo» panel instead of empty widgets.</summary>
    public bool ShowEmptyState => Sessions.Count == 0 && Page is not ("Home" or "Sessions" or "Server" or "Engine");

    public const string DemoUrl = "https://github.com/avotattoocastro-creator/apk_android_avo/releases/download/windows-v2-pro-latest/AVO_Windows_V2_DEMO_SINTETICA.zip";
    private string _demoState = "";
    public string DemoState { get => _demoState; private set => Set(ref _demoState, value); }

    /// <summary>Downloads the SYNTHETIC demonstration sessions published with the build and imports them (clearly labelled demo).</summary>
    private async Task LoadDemoAsync()
    {
        DemoState = "Descargando sesiones de demostración (16 MB)…";
        Busy = true;
        string dir = Path.Combine(Paths.Root, "demo");
        try
        {
            Directory.CreateDirectory(dir);
            string zip = Path.Combine(dir, "demo.zip");
            using (var http = new System.Net.Http.HttpClient { Timeout = TimeSpan.FromMinutes(3) })
            using (var r = await http.GetAsync(DemoUrl, System.Net.Http.HttpCompletionOption.ResponseHeadersRead))
            {
                r.EnsureSuccessStatusCode();
                if (r.Content.Headers.ContentLength > 80_000_000) throw new InvalidDataException("Paquete de demostración demasiado grande");
                await using var f = File.Create(zip);
                await r.Content.CopyToAsync(f);
            }
            var files = new List<string>();
            using (var z = System.IO.Compression.ZipFile.OpenRead(zip))
                foreach (var e in z.Entries)
                {
                    // only flat DEMO_*.avr names: no paths from the archive are ever used
                    if (!System.Text.RegularExpressions.Regex.IsMatch(e.Name, @"^DEMO_[A-Za-z0-9_]{1,60}\.avr$") || e.Length > 40_000_000) continue;
                    string target = Path.Combine(dir, e.Name);
                    System.IO.Compression.ZipFileExtensions.ExtractToFile(e, target, true);
                    files.Add(target);
                }
            DemoState = $"Importando {files.Count} sesiones de demostración…";
            await ImportFilesAsync(files);
            DemoState = files.Count > 0 ? "Sesiones de demostración cargadas (DATOS SINTÉTICOS)." : "El paquete no contenía sesiones válidas.";
        }
        catch (Exception ex) when (ex is System.Net.Http.HttpRequestException or IOException or InvalidDataException or TaskCanceledException)
        {
            DemoState = "No se pudo descargar la demostración: " + ex.Message;
            Log.Warn("demo", ex.Message, ex);
        }
        finally { Busy = false; }
    }

    private string _status = "Listo · importa un entrenamiento .avo o .avr";
    public string Status { get => _status; set => Set(ref _status, value); }
    private bool _busy;
    public bool Busy { get => _busy; set => Set(ref _busy, value); }
    private double _progress;
    public double Progress { get => _progress; set => Set(ref _progress, value); }
    public string EngineInfo => EquineEngine.Available ? $"Motor AVO Equine {EquineEngine.Version()}" : "Motor no disponible: " + (EquineEngine.UnavailableReason ?? "");
    public bool EngineAvailable => EquineEngine.Available;
    public string EngineShort => EquineEngine.Available ? EquineEngine.Version() : "No disponible";
    public AvoState EngineIndicator => EquineEngine.Available ? AvoState.Ok : AvoState.Error;

    public ICommand NavigateCommand { get; }
    public ICommand ImportCommand { get; }
    public ICommand ImportFolderCommand { get; }
    public ICommand RunEngineCommand { get; }
    public ICommand PlayCommand { get; }
    public ICommand ResetZoomCommand { get; }
    public ICommand ClearRangeCommand { get; }
    public ICommand OpenSessionCommand { get; }
    public ICommand LoadDemoCommand { get; }

    // ------------------------------------------------------------------ filter
    private string _search = "";
    public string Search { get => _search; set { if (Set(ref _search, value)) SessionsView.Refresh(); } }
    private bool _onlyFavorites;
    public bool OnlyFavorites { get => _onlyFavorites; set { if (Set(ref _onlyFavorites, value)) SessionsView.Refresh(); } }
    private readonly HashSet<string> _favorites = new(StringComparer.Ordinal);
    private string FavoritesFile => Path.Combine(Paths.Root, "favoritos.json");
    public ICommand ToggleFavoriteCommand { get; private set; } = null!;

    private void InitFavorites()
    {
        try
        {
            if (File.Exists(FavoritesFile))
                foreach (var id in System.Text.Json.JsonSerializer.Deserialize<string[]>(File.ReadAllText(FavoritesFile)) ?? []) _favorites.Add(id);
        }
        catch (Exception ex) when (ex is IOException or System.Text.Json.JsonException) { Log.Warn("favoritos", ex.Message, ex); }
        ToggleFavoriteCommand = new RelayCommand(p =>
        {
            if (p is not SessionItem s) return;
            s.IsFavorite = !s.IsFavorite;
            if (s.IsFavorite) _favorites.Add(s.Id); else _favorites.Remove(s.Id);
            try { File.WriteAllText(FavoritesFile, System.Text.Json.JsonSerializer.Serialize(_favorites.OrderBy(x => x).ToArray())); }
            catch (IOException ex) { Log.Warn("favoritos", ex.Message, ex); }
            if (OnlyFavorites) SessionsView.Refresh();
        });
    }

    private bool MatchesFilter(SessionItem s)
    {
        if (OnlyFavorites && !s.IsFavorite) return false;
        if (string.IsNullOrWhiteSpace(Search)) return true;
        string q = Search.Trim();
        return new[] { s.Horse, s.Rider, s.Id, s.DateText, s.Discipline, s.Kind }.Any(x => x.Contains(q, StringComparison.CurrentCultureIgnoreCase));
    }

    // ------------------------------------------------------------------ selection
    private SessionItem? _selected;
    public SessionItem? Selected
    {
        get => _selected;
        set
        {
            if (!Set(ref _selected, value)) return;
            StopPlay();
            CursorTime = value is { Timeline.Count: > 0 } ? value.Timeline.T[0] : double.NaN;
            RangeStart = double.NaN; RangeEnd = double.NaN; ChartXMin = double.NaN; ChartXMax = double.NaN;
            OnSelectedChanged();
            if (value is not null && value.Engine is null) _ = RunEngineAsync(value, false);
        }
    }

    private void OnSelectedChanged()
    {
        RebuildCharts();
        RebuildMap();
        LoadSegments();
        RefreshBiomech();
        RefreshSessionPanels();
        RefreshReportPreview();
        RaiseMany(nameof(HasSession), nameof(TimelineEnd), nameof(TimelineStart), nameof(WindowText), nameof(IsTrimmed));
        if (Page == "Tides") _ = LoadEnvironmentAsync(false);
    }

    public bool HasSession => Selected is not null;
    public double TimelineEnd => Selected is { Timeline.Count: > 1 } s ? s.Timeline.T[^1] : 1;

    // ------------------------------------------------------------------ shared cursor / range / x-viewport
    private double _cursor = double.NaN;
    public double CursorTime { get => _cursor; set { if (Set(ref _cursor, value)) OnCursorChanged(); } }
    private double _rangeStart = double.NaN, _rangeEnd = double.NaN;
    public double RangeStart { get => _rangeStart; set { if (Set(ref _rangeStart, value)) OnRangeChanged(); } }
    public double RangeEnd { get => _rangeEnd; set { if (Set(ref _rangeEnd, value)) OnRangeChanged(); } }
    private double _xmin = double.NaN, _xmax = double.NaN;
    public double ChartXMin { get => _xmin; set => Set(ref _xmin, value); }
    public double ChartXMax { get => _xmax; set => Set(ref _xmax, value); }
    public bool HasRange => double.IsFinite(RangeStart) && double.IsFinite(RangeEnd) && Math.Abs(RangeEnd - RangeStart) > 0.5;

    private void OnCursorChanged()
    {
        RaiseMany(nameof(CursorText), nameof(CursorSpeed), nameof(CursorAccel), nameof(CursorAltitude), nameof(CursorQuality), nameof(CursorCadence),
            nameof(CursorPosition), nameof(PlaybackText), nameof(CursorDistance));
        if (Page == "Biomech") RefreshImuWindow();
    }

    private void OnRangeChanged()
    {
        Raise(nameof(HasRange));
        RefreshRangeStats();
    }

    private int CursorIndex => Selected is { } s && double.IsFinite(CursorTime) ? s.Timeline.IndexAt(CursorTime) : -1;
    public string CursorText => Selected is null || !double.IsFinite(CursorTime) ? "—" : Core.TimeText.Clock(CursorTime);
    public string CursorSpeed => Val(i => Selected!.Timeline.SpeedFiltered[i] * 3.6, "0.0");
    public string CursorAccel => Val(i => SegmentAnalyzer.AccelValid(Selected!.Timeline, i) ? Selected.Timeline.AccelLong[i] : double.NaN, "0.00");
    public string CursorAltitude => Val(i => Selected!.Timeline.AltitudeMsl[i], "0.0");
    public string CursorDistance => Val(i => Selected!.Timeline.Distance[i] / 1000, "0.00");
    public string CursorQuality => CursorIndex is int i and >= 0 ? $"{GnssQuality.Name(Selected!.Timeline.Solution[i])} · {Selected.Timeline.NumSv[i]} sat · hAcc {Selected.Timeline.HAcc[i].ToString("0.000", Es)} m" : "—";
    public string CursorPosition => CursorIndex is int i and >= 0 ? $"{Selected!.Timeline.Lat[i].ToString("0.000000", CultureInfo.InvariantCulture)}, {Selected.Timeline.Lon[i].ToString("0.000000", CultureInfo.InvariantCulture)}" : "—";
    public string CursorCadence
    {
        get
        {
            if (Selected?.Engine is not { HasImu: true } e || !double.IsFinite(CursorTime)) return "—";
            double f = e.CadenceAt(CursorTime + Selected.EngineOffsetS);
            return double.IsFinite(f) ? (f * 60).ToString("0", Es) : "—";
        }
    }
    private string Val(Func<int, double> f, string fmt)
    {
        int i = CursorIndex;
        if (i < 0) return "—";
        double v = f(i);
        return double.IsFinite(v) ? v.ToString(fmt, Es) : "—";
    }

    // ------------------------------------------------------------------ playback
    private readonly DispatcherTimer _timer;
    private DateTime _lastTick;
    private bool _playing;
    public bool IsPlaying { get => _playing; private set => Set(ref _playing, value); }
    public double[] PlaybackSpeeds { get; } = [1, 2, 5, 10, 20, 60];
    private double _playbackSpeed = 10;
    public double PlaybackSpeed { get => _playbackSpeed; set => Set(ref _playbackSpeed, value); }
    public string PlaybackText => Selected is null ? "00:00 / 00:00" : $"{CursorText} / {Core.TimeText.Clock(TimelineEnd)}";

    private void TogglePlay()
    {
        if (IsPlaying) { StopPlay(); return; }
        if (Selected is null) return;
        if (!double.IsFinite(CursorTime) || CursorTime >= TimelineEnd - 0.5) CursorTime = Selected.Timeline.T[0];
        _lastTick = DateTime.UtcNow;
        IsPlaying = true;
        _timer.Start();
    }
    private void StopPlay() { _timer.Stop(); IsPlaying = false; }
    private void PlaybackTick()
    {
        var now = DateTime.UtcNow;
        double dt = (now - _lastTick).TotalSeconds * PlaybackSpeed;
        _lastTick = now;
        double next = (double.IsFinite(CursorTime) ? CursorTime : 0) + dt;
        if (next >= TimelineEnd) { CursorTime = TimelineEnd; StopPlay(); return; }
        CursorTime = next;
    }

    // ------------------------------------------------------------------ import
    public async Task RestoreLibraryAsync()
    {
        var files = _library.StoredFiles().ToArray();
        if (files.Length > 0) await ImportFilesAsync(files, restoring: true);
    }

    public async Task ImportFilesAsync(IEnumerable<string> files, bool restoring = false)
    {
        var list = files.Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        if (list.Length == 0) return;
        Busy = true;
        int ok = 0, bad = 0, dup = 0, k = 0;
        SessionItem? lastImported = null;
        try
        {
            foreach (var f in list)
            {
                Status = $"Validando {Path.GetFileName(f)} ({++k}/{list.Length})…";
                Progress = (double)k / list.Length;
                var loaded = Sessions.Select(s => s.Id).ToHashSet();
                var outcome = await Task.Run(() => _library.Import(f, loaded));
                if (outcome.Session is null)
                {
                    bad++;
                    ImportLog.Insert(0, new ImportLogRow(DateTime.Now.ToString("HH:mm", Es), Path.GetFileName(f), "Rechazado: " + outcome.Error, false));
                    Log.Warn("import", $"{Path.GetFileName(f)} rechazado: {outcome.Error}");
                    continue;
                }
                if (Sessions.Any(s => s.Session.FileSha256 == outcome.Session.FileSha256)) { dup++; continue; }
                var item = await Task.Run(() => BuildItem(outcome.Session));
                item.ImportStatus = outcome.Status;
                var same = Sessions.FirstOrDefault(s => s.Id == item.Id);
                if (same is not null) { Sessions.Remove(same); dup++; }
                Sessions.Add(item);
                item.IsFavorite = _favorites.Contains(item.Id);
                lastImported = item;
                ok++;
                if (!restoring || ImportLog.Count < 8)
                    ImportLog.Insert(0, new ImportLogRow(DateTime.Now.ToString("HH:mm", Es), outcome.Session.SourceName, outcome.Status + (item.IsSynthetic ? " · DEMOSTRACIÓN" : ""), true));
                Log.Info("import", outcome.Status, new { id = item.Id, sha = outcome.Session.FileSha256 });
            }
        }
        finally { Busy = false; Progress = 0; }
        Status = $"Importación: {ok} aceptados, {bad} rechazados, {dup} duplicados · {Sessions.Count} sesiones";
        AssignCompareColors();
        RefreshHome();
        if (!restoring && lastImported is not null)
        {
            Selected = lastImported;                     // what the user just opened
            if (Page is "Home" or "Sessions") Page = "Analysis";
        }
        if (Selected is null && Sessions.Count > 0) Selected = Sessions.OrderByDescending(s => s.Start).First();
        if (bad > 0 && !restoring) Dialogs.Show("Importación", $"{bad} archivo(s) rechazados. Consulta «Estado de importaciones» en Inicio.", true);
    }

    private SessionItem BuildItem(TrainingSession s)
    {
        var tl = SessionTimeline.Build(s, new SpeedSmoother.Parameters(JerkDensity: Settings.JerkDensity));
        var imu = ImuTimeline.Build(s, tl);
        var item = new SessionItem(s, tl, imu);
        RestoreWindow(item);
        try { foreach (var d in _segmentStore.Load(s.SessionId)) item.SegmentDefs.Add(d); }
        catch (Exception ex) when (ex is IOException or System.Text.Json.JsonException) { Log.Warn("tramos", "No se pudieron leer los tramos guardados", ex); }
        try
        {
            string notes = Path.Combine(Paths.Notes, _segmentStore.PathFor(s.SessionId).Split(Path.DirectorySeparatorChar)[^1].Replace(".json", ".txt"));
            if (File.Exists(notes)) item.Notes = File.ReadAllText(notes);
        }
        catch (IOException) { }
        return item;
    }

    // ------------------------------------------------------------------ engine
    private readonly SemaphoreSlim _engineGate = new(1);
    public async Task RunEngineAsync(SessionItem item, bool force)
    {
        if (!EquineEngine.Available) { item.EngineState = "Motor no disponible"; return; }
        if (item.Session.RawSegmentPaths.Count == 0) { item.EngineState = "Sin segmentos RAW"; return; }
        await _engineGate.WaitAsync();
        try
        {
            if (item.Engine is not null && !force) return;
            item.EngineState = "Analizando…";
            if (item == Selected) Status = $"Motor AVO analizando {item.Id}…";
            string dir = Path.Combine(Paths.Analysis, string.Concat(item.Id.Select(c => char.IsLetterOrDigit(c) || c is '-' or '_' ? c : '_')));
            var paths = item.Session.RawSegmentPaths.ToList();
            var json = await Task.Run(() => EquineEngine.AnalyseJson(paths, EquineEngine.Options(true, dir, force)));
            item.Engine = await Task.Run(() => EquineAnalysis.Parse(json));
            item.EngineState = item.Engine.Cache == "ACIERTO" ? "Resultado guardado reutilizado" : "Calculado";
            if (item == Selected)
            {
                Status = $"Motor {item.Engine.Engine}: {item.EngineState}";
                RebuildCharts(); RebuildMap(); RefreshBiomech(); RefreshSegmentRows(); RefreshSessionPanels();
            }
        }
        catch (Exception ex) when (ex is InvalidDataException or InvalidOperationException or IOException or OperationCanceledException or System.Text.Json.JsonException)
        {
            item.EngineState = "Error del motor: " + ex.Message;
            Log.Error("motor", ex.Message, ex);
        }
        finally { _engineGate.Release(); }
    }

    /// <summary>Waits for the engine of every loaded session (used by the capture mode).</summary>
    public async Task RunEngineForAllAsync()
    {
        foreach (var s in Sessions.ToList()) await RunEngineAsync(s, false);
    }

    // ------------------------------------------------------------------ home
    public int SessionCount => Sessions.Count;
    public string TotalDistanceText => Sessions.Where(s => !s.IsSynthetic).Sum(s => s.DistanceKmValue).ToString("0.0", Es) + " km";
    public string DemoDistanceText => Sessions.Where(s => s.IsSynthetic).Sum(s => s.DistanceKmValue).ToString("0.0", Es) + " km";
    public bool HasDemo => Sessions.Any(s => s.IsSynthetic);
    public string BestSpeedText => Sessions.Count == 0 ? "—" : Sessions.Max(s => s.MaxSpeedKmh).ToString("0.0", Es) + " km/h";
    public IEnumerable<SessionItem> RecentSessions => Sessions.OrderByDescending(s => s.Start).Take(6);

    private void RefreshHome()
    {
        Horses.Clear();
        foreach (var g in Sessions.GroupBy(s => s.Horse).OrderByDescending(g => g.Count()))
            Horses.Add(new HorseCard(g.Key, g.Count(), g.Max(s => s.Start) is DateTimeOffset d ? MadridTime.Format(d, "dd/MM/yyyy") : "—", g.Max(s => s.MaxSpeedKmh).ToString("0.0", Es) + " km/h"));
        RaiseMany(nameof(ShowEmptyState), nameof(SessionCount), nameof(TotalDistanceText), nameof(DemoDistanceText), nameof(HasDemo), nameof(BestSpeedText), nameof(RecentSessions));
    }

    // ------------------------------------------------------------------ settings
    private MapProvider _mapProvider;
    public MapProvider MapProvider
    {
        get => _mapProvider;
        set
        {
            if (!Set(ref _mapProvider, value)) return;
            Settings.Map = value;
            try { Settings.Save(Paths.SettingsFile); } catch (IOException ex) { Log.Warn("ajustes", ex.Message); }
        }
    }
    private RouteColorMode _colorMode = RouteColorMode.Speed;
    public RouteColorMode ColorMode { get => _colorMode; set { if (Set(ref _colorMode, value)) Raise(nameof(LegendTitle)); } }
    public string LegendTitle => ColorMode switch
    {
        RouteColorMode.Speed => "Velocidad (km/h)",
        RouteColorMode.Acceleration => "Aceleración longitudinal (m/s²)",
        RouteColorMode.GnssQuality => "Calidad GNSS",
        RouteColorMode.Gait => "Aire (motor AVO)",
        _ => "",
    };
    public string TileCacheDir => Paths.Tiles;
}
