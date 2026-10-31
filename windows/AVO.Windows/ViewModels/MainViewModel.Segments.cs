using System.Collections.ObjectModel;
using System.IO;
using System.Windows.Input;
using System.Windows.Media;
using Avo.Windows.Controls;
using Avo.Windows.Core;

namespace Avo.Windows.ViewModels;

public sealed partial class MainViewModel
{
    // ------------------------------------------------------------------ map
    private IReadOnlyList<MapTrack> _tracks = [];
    public IReadOnlyList<MapTrack> Tracks { get => _tracks; private set => Set(ref _tracks, value); }
    private IReadOnlyList<MapTrack> _segmentTrack = [];
    public IReadOnlyList<MapTrack> SegmentTracks { get => _segmentTrack; private set => Set(ref _segmentTrack, value); }

    private void RebuildMap()
    {
        var s = Selected;
        Tracks = s is null || s.Timeline.Count < 2 ? [] : new[] { new MapTrack { Timeline = s.Timeline, Label = s.Summary, Gait = s.GaitByIndex } };
    }

    // ------------------------------------------------------------------ segments
    public ObservableCollection<SegmentMetrics> SegmentRows { get; } = [];
    private SegmentMetrics? _selectedSegment;
    public SegmentMetrics? SelectedSegment
    {
        get => _selectedSegment;
        set
        {
            if (!Set(ref _selectedSegment, value)) return;
            SegmentName = value?.Name ?? "";
            SegmentNotes = value?.Notes ?? "";
            if (value is not null) { RangeStart = value.T0; RangeEnd = value.T1; CursorTime = value.T0; }
            RefreshSegmentDetail();
        }
    }
    private string _segmentName = "", _segmentNotes = "";
    public string SegmentName { get => _segmentName; set => Set(ref _segmentName, value); }
    public string SegmentNotes { get => _segmentNotes; set => Set(ref _segmentNotes, value); }
    private double _segmentLength = 500;
    public double SegmentLength { get => _segmentLength; set => Set(ref _segmentLength, value); }
    public double[] SegmentLengths { get; } = [100, 200, 400, 500, 800, 1000, 2000];
    public ObservableCollection<KeyValueRow> SegmentDetail { get; } = [];
    private IReadOnlyList<ChartSeries> _segmentSpeed = [];
    public IReadOnlyList<ChartSeries> SegmentSpeedSeries { get => _segmentSpeed; private set => Set(ref _segmentSpeed, value); }
    public string SegmentObservations => SelectedSegment?.Observations ?? "";

    public ICommand AddSegmentFromRangeCommand { get; private set; } = null!;
    public ICommand AutoDistanceCommand { get; private set; } = null!;
    public ICommand AutoSpeedBandCommand { get; private set; } = null!;
    public ICommand EngineSegmentsCommand { get; private set; } = null!;
    public ICommand SaveSegmentCommand { get; private set; } = null!;
    public ICommand DeleteSegmentCommand { get; private set; } = null!;
    public ICommand ClearSegmentsCommand { get; private set; } = null!;

    private void InitSegments()
    {
        AddSegmentFromRangeCommand = new RelayCommand(() =>
        {
            if (Selected is null || !HasRange) { Status = "Selecciona un intervalo con Mayús + arrastrar en una gráfica"; return; }
            int n = Selected.SegmentDefs.Count(d => d.Kind == SegmentKind.Manual) + 1;
            AddDefs([new SegmentDefinition { Name = $"Tramo manual {n}", T0 = Math.Min(RangeStart, RangeEnd), T1 = Math.Max(RangeStart, RangeEnd) }], false);
        }, () => Selected is not null);
        AutoDistanceCommand = new RelayCommand(() => { if (Selected is not null) AddDefs(SegmentAnalyzer.ByDistance(Selected.Timeline, SegmentLength), true, SegmentKind.Distance); }, () => Selected is not null);
        AutoSpeedBandCommand = new RelayCommand(() => { if (Selected is not null) AddDefs(SegmentAnalyzer.BySpeedBand(Selected.Timeline), true, SegmentKind.SpeedBand); }, () => Selected is not null);
        EngineSegmentsCommand = new RelayCommand(() =>
        {
            if (Selected?.Engine is not { HasImu: true } e) { Status = "Los tramos por aire necesitan datos de cincha y el motor AVO"; return; }
            AddDefs(SegmentAnalyzer.FromEngine(e, Selected.EngineOffsetS), true, SegmentKind.Engine);
        }, () => Selected?.Engine is { HasImu: true });
        SaveSegmentCommand = new RelayCommand(() =>
        {
            if (Selected is null || SelectedSegment is null) return;
            var d = Selected.SegmentDefs.FirstOrDefault(x => x.Id == SelectedSegment.Id);
            if (d is null) return;
            d.Name = string.IsNullOrWhiteSpace(SegmentName) ? d.Name : SegmentName.Trim();
            d.Notes = SegmentNotes.Trim();
            if (HasRange) { d.T0 = Math.Min(RangeStart, RangeEnd); d.T1 = Math.Max(RangeStart, RangeEnd); }
            PersistSegments();
            RefreshSegmentRows(d.Id);
        }, () => SelectedSegment is not null);
        DeleteSegmentCommand = new RelayCommand(() =>
        {
            if (Selected is null || SelectedSegment is null) return;
            var d = Selected.SegmentDefs.FirstOrDefault(x => x.Id == SelectedSegment.Id);
            if (d is not null) Selected.SegmentDefs.Remove(d);
            PersistSegments();
            RefreshSegmentRows();
        }, () => SelectedSegment is not null);
        ClearSegmentsCommand = new RelayCommand(() =>
        {
            if (Selected is null) return;
            Selected.SegmentDefs.Clear();
            PersistSegments();
            RefreshSegmentRows();
        }, () => Selected is { SegmentDefs.Count: > 0 });
    }

    private void AddDefs(IEnumerable<SegmentDefinition> defs, bool replaceKind, SegmentKind kind = SegmentKind.Manual)
    {
        if (Selected is null) return;
        if (replaceKind) foreach (var old in Selected.SegmentDefs.Where(d => d.Kind == kind).ToList()) Selected.SegmentDefs.Remove(old);
        string? last = null;
        foreach (var d in defs) { Selected.SegmentDefs.Add(d); last = d.Id; }
        PersistSegments();
        RefreshSegmentRows(last);
        Status = $"{Selected.SegmentDefs.Count} tramos guardados (la telemetría original no se modifica)";
    }

    private void PersistSegments()
    {
        if (Selected is null) return;
        try { _segmentStore.Save(Selected.Id, Selected.SegmentDefs); }
        catch (IOException ex) { Log.Error("tramos", ex.Message, ex); Status = "No se pudieron guardar los tramos: " + ex.Message; }
    }

    private void LoadSegments() => RefreshSegmentRows();

    private void RefreshSegmentRows(string? selectId = null)
    {
        SegmentRows.Clear();
        var s = Selected;
        if (s is not null)
            foreach (var d in s.SegmentDefs.OrderBy(d => d.T0))
                SegmentRows.Add(SegmentAnalyzer.Compute(s.Timeline, d, s.Engine, s.EngineOffsetS));
        _selectedSegment = selectId is null ? null : SegmentRows.FirstOrDefault(r => r.Id == selectId);
        Raise(nameof(SelectedSegment));
        if (_selectedSegment is not null) { SegmentName = _selectedSegment.Name; SegmentNotes = _selectedSegment.Notes; }
        RefreshSegmentDetail();
    }

    private void RefreshSegmentDetail()
    {
        SegmentDetail.Clear();
        var s = Selected; var m = SelectedSegment;
        Raise(nameof(SegmentObservations));
        if (s is null || m is null) { SegmentSpeedSeries = []; SegmentTracks = []; return; }
        foreach (var r in MetricRows(m)) SegmentDetail.Add(r);
        var tl = s.Timeline;
        var idx = Enumerable.Range(0, tl.Count).Where(i => tl.T[i] >= m.T0 && tl.T[i] <= m.T1).ToArray();
        SegmentSpeedSeries =
        [
            new ChartSeries { Name = "Velocidad filtrada", X = idx.Select(i => tl.T[i]).ToArray(), Y = idx.Select(i => tl.SpeedFiltered[i] * 3.6).ToArray(),
                Breaks = idx.Select(i => tl.BreakBefore[i]).ToArray(), Color = Blue, Thickness = 1.6, Unit = "km/h" },
        ];
        SegmentTracks = new[] { new MapTrack { Timeline = tl, Label = m.Name } };
    }

    // ------------------------------------------------------------------ biomechanics
    public ObservableCollection<KeyValueRow> BiomechMetrics { get; } = [];
    public ObservableCollection<EngineSymmetryGroup> SymmetryRows { get; } = [];
    public ObservableCollection<string> SymmetryControls { get; } = [];
    private int[] _activeSensors = [];
    public int[] ActiveSensors { get => _activeSensors; private set => Set(ref _activeSensors, value); }
    private IReadOnlyList<ChartSeries> _imuWindow = [];
    public IReadOnlyList<ChartSeries> ImuWindowSeries { get => _imuWindow; private set => Set(ref _imuWindow, value); }
    private double _imuWinMin = double.NaN, _imuWinMax = double.NaN;
    public double ImuWindowMin { get => _imuWinMin; set => Set(ref _imuWinMin, value); }
    public double ImuWindowMax { get => _imuWinMax; set => Set(ref _imuWinMax, value); }
    public string BiomechStatus { get; private set; } = "Selecciona un entrenamiento.";
    public bool HasBiomech => Selected?.Engine is { HasImu: true };
    public bool HasGirthRaw => Selected is { Imu.Channels.Count: > 0 };
    public string SymmetryHeadline { get; private set; } = "—";
    public string RegularityHeadline { get; private set; } = "—";
    public string CadenceHeadline { get; private set; } = "—";
    public string StrideHeadline { get; private set; } = "—";

    private void RefreshBiomech()
    {
        BiomechMetrics.Clear(); SymmetryRows.Clear(); SymmetryControls.Clear();
        var s = Selected;
        ActiveSensors = s?.Imu.Channels.Select(c => (int)c.ImuId).ToArray() ?? [];
        SymmetryHeadline = RegularityHeadline = CadenceHeadline = StrideHeadline = "—";
        if (s is null) BiomechStatus = "Selecciona un entrenamiento.";
        else if (!s.HasGirth) BiomechStatus = "Sin datos de cincha en esta sesión: no se calcula ningún índice biomecánico.";
        else if (s.Engine is null) BiomechStatus = "Datos de cincha decodificados; el motor AVO todavía no ha terminado el análisis.";
        else if (!s.Engine.HasImu) BiomechStatus = "El motor no ha podido usar los datos de la cincha.";
        else
        {
            var e = s.Engine;
            BiomechStatus = $"{e.FusionSummary}. Índices exploratorios de IMU sin calibrar: no son diagnóstico clínico, carga de extremidad ni lesión.";
            foreach (var id in e.GirthImu.Distinct().OrderBy(x => x))
            {
                string n = ImuTimeline.SensorName((byte)id);
                BiomechMetrics.Add(new($"{n} · cadencia", Core.TimeText.Num(e.Metric($"cadencia_media_imu{id}"), "0", " ciclos/min")));
                BiomechMetrics.Add(new($"{n} · correlación entre ciclos", Core.TimeText.Num(e.Metric($"correlacion_entre_ciclos_imu{id}"), "0.000")));
                BiomechMetrics.Add(new($"{n} · CV de intervalos", Core.TimeText.Num(e.Metric($"variabilidad_intervalos_imu{id}"), "0.000")));
                BiomechMetrics.Add(new($"{n} · CV de amplitud", Core.TimeText.Num(e.Metric($"regularidad_amplitud_cv_imu{id}"), "0.000")));
                BiomechMetrics.Add(new($"{n} · estabilidad espectral", Core.TimeText.Num(e.Metric($"estabilidad_espectral_imu{id}"), "0.000")));
            }
            foreach (var g in e.SymmetryGroups) SymmetryRows.Add(g);
            foreach (var c in e.SymmetryControls) SymmetryControls.Add(c);
            CadenceHeadline = Core.TimeText.Num(e.Metric("cadencia_media_imu0"), "0", "", "—");
            RegularityHeadline = Core.TimeText.Num(e.Metric("correlacion_entre_ciclos_imu0"), "0.00", "", "—");
            var seg = e.Segments.Where(x => x.StrideLengthM is double d && double.IsFinite(d)).Select(x => x.StrideLengthM!.Value).ToArray();
            StrideHeadline = seg.Length > 0 ? seg.Average().ToString("0.00", Es) : "—";
            // Exploratory temporal asymmetry (d1 − d2)/(d1 + d2) of the engine, only from groups it marks reproducible. Shown as is
            // (signed, %), never converted into a "symmetry score".
            var rep = e.SymmetryGroups.Where(g => g.TemporalReproducible && g.TemporalAsymmetry is double).Select(g => g.TemporalAsymmetry!.Value).ToArray();
            SymmetryHeadline = rep.Length > 0 ? (100 * Stats.Median(rep)).ToString("+0.0;-0.0;0.0", Es) : "—";
        }
        RaiseMany(nameof(BiomechStatus), nameof(HasBiomech), nameof(HasGirthRaw), nameof(SymmetryHeadline), nameof(RegularityHeadline), nameof(CadenceHeadline), nameof(StrideHeadline));
        RefreshImuWindow();
    }

    /// <summary>Raw girth signal (nominal g) in a 4 s window around the cursor: movement pattern of the three sensors.</summary>
    private void RefreshImuWindow()
    {
        var s = Selected;
        if (s is null || s.Imu.Channels.Count == 0) { ImuWindowSeries = []; return; }
        double c = double.IsFinite(CursorTime) ? CursorTime : s.Timeline.T[0] + 60;
        double a = c - 2, b = c + 2;
        var list = new List<ChartSeries>();
        foreach (var ch in s.Imu.Channels)
        {
            int i0 = Array.BinarySearch(ch.T, a); if (i0 < 0) i0 = ~i0;
            int i1 = Array.BinarySearch(ch.T, b); if (i1 < 0) i1 = ~i1;
            if (i1 - i0 < 4) continue;
            var x = new double[i1 - i0]; var y = new double[i1 - i0];
            for (int i = i0; i < i1; i++) { x[i - i0] = ch.T[i] - a; y[i - i0] = Math.Sqrt((double)ch.Ax[i] * ch.Ax[i] + (double)ch.Ay[i] * ch.Ay[i] + (double)ch.Az[i] * ch.Az[i]) * ch.AccelGPerLsb; }
            list.Add(new ChartSeries { Name = ch.Name, X = x, Y = y, Color = HorseDiagram.SensorColor(ch.ImuId), Thickness = 1.4, Unit = "g", Format = "0.00" });
        }
        ImuWindowSeries = list;
    }
}
