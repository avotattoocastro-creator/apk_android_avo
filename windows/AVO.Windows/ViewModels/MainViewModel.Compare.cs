using System.Collections.ObjectModel;
using System.Windows.Input;
using System.Windows.Media;
using Avo.Windows.Controls;
using Avo.Windows.Core;

namespace Avo.Windows.ViewModels;

public sealed record CompareRow(string Label, Color Color, string Date, string Distance, string Duration, string MeanSpeed, string MaxSpeed, string MaxAccel, string Fix, string Cadence);

public sealed partial class MainViewModel
{
    private static readonly Color[] ComparePalette =
    [
        Color.FromRgb(0x3D, 0x9B, 0xFF), Color.FromRgb(0xFF, 0xC4, 0x2C), Color.FromRgb(0xED, 0x12, 0x2A), Color.FromRgb(0x52, 0xDD, 0x40),
        Color.FromRgb(0x35, 0xD0, 0xE8), Color.FromRgb(0xA8, 0x6B, 0xFF), Color.FromRgb(0xC9, 0xCB, 0xD1),
    ];

    public ObservableCollection<CompareRow> CompareRows { get; } = [];
    private IReadOnlyList<MapTrack> _compareTracks = [];
    public IReadOnlyList<MapTrack> CompareTracks { get => _compareTracks; private set => Set(ref _compareTracks, value); }
    private IReadOnlyList<ChartSeries> _compareSpeed = [], _compareAccel = [];
    public IReadOnlyList<ChartSeries> CompareSpeedSeries { get => _compareSpeed; private set => Set(ref _compareSpeed, value); }
    public IReadOnlyList<ChartSeries> CompareAccelSeries { get => _compareAccel; private set => Set(ref _compareAccel, value); }
    private AlignmentMode _align = AlignmentMode.RelativeTime;
    public AlignmentMode Alignment { get => _align; set { if (Set(ref _align, value)) { Raise(nameof(CompareAxis)); RefreshCompare(); } } }
    public AxisFormat CompareAxis => Alignment == AlignmentMode.Distance ? AxisFormat.Kilometres : AxisFormat.Clock;
    private string _compareVerdict = "Marca dos o más entrenamientos para compararlos.";
    public string CompareVerdict { get => _compareVerdict; private set => Set(ref _compareVerdict, value); }
    public ObservableCollection<EngineDiffRow> EngineDiffRows { get; } = [];
    public ICommand RefreshCompareCommand { get; private set; } = null!;
    public ICommand EngineCompareCommand { get; private set; } = null!;
    public ICommand ToggleCompareCommand { get; private set; } = null!;

    private void InitCompare()
    {
        RefreshCompareCommand = new RelayCommand(RefreshCompare);
        ToggleCompareCommand = new RelayCommand(p => { if (p is SessionItem s) { s.IsCompared = !s.IsCompared; RefreshCompare(); } });
        EngineCompareCommand = new AsyncCommand(async _ =>
        {
            var picked = Sessions.Where(s => s.IsCompared).Take(2).ToList();
            if (picked.Count < 2) { CompareVerdict = "El motor compara dos sesiones: marca dos."; return; }
            if (!EquineEngine.Available) { CompareVerdict = EquineEngine.UnavailableReason ?? "Motor no disponible"; return; }
            var a = picked[0].Session.RawSegmentPaths.ToList(); var b = picked[1].Session.RawSegmentPaths.ToList();
            CompareVerdict = "Comparando con el motor AVO…";
            var json = await Task.Run(() => EquineEngine.CompareJson(a, b, EquineEngine.Options(false, null, false, "\"mismo_recorrido\":true")));
            var (rows, verdict) = EquineComparisonRows.Parse(json);
            EngineDiffRows.Clear();
            foreach (var r in rows) EngineDiffRows.Add(r);
            CompareVerdict = verdict;
        }, Fail);
    }

    private void AssignCompareColors()
    {
        int k = 0;
        foreach (var s in Sessions.OrderByDescending(s => s.Start)) s.CompareColor = ComparePalette[k++ % ComparePalette.Length];
        if (!Sessions.Any(s => s.IsCompared)) foreach (var s in Sessions.OrderByDescending(s => s.Start).Take(3)) s.IsCompared = true;
    }

    private void RefreshCompare()
    {
        var picked = Sessions.Where(s => s.IsCompared && s.Timeline.Count > 1).OrderByDescending(s => s.Start).ToList();
        CompareRows.Clear();
        foreach (var s in picked)
        {
            var m = SeriesAligner.Summarize(s.Summary, s.Timeline, s.Engine, s.EngineOffsetS);
            CompareRows.Add(new CompareRow($"{s.Horse} · {s.Rider}", s.CompareColor, s.DateTimeText, Core.TimeText.Num(m.DistanceKm, "0.00", " km"), Core.TimeText.Clock(m.DurationS),
                Core.TimeText.Num(m.MeanSpeedKmh, "0.0", " km/h"), Core.TimeText.Num(m.MaxSpeedKmh, "0.0", " km/h"), Core.TimeText.Num(m.MaxAccel, "0.00", " m/s²"),
                Core.TimeText.Num(m.FixPercent, "0", " %"), Core.TimeText.Num(m.Cadence, "0", " /min")));
        }
        CompareTracks = picked.Select(s => new MapTrack { Timeline = s.Timeline, Label = s.Summary, SingleColor = s.CompareColor }).ToList();
        if (picked.Count == 0) { CompareSpeedSeries = []; CompareAccelSeries = []; return; }
        double step = Alignment == AlignmentMode.Distance ? 5 : 1;
        var tls = picked.Select(s => s.Timeline).ToList();
        var sp = SeriesAligner.Align(tls, t => t.SpeedFiltered, Alignment, step);
        var ac = SeriesAligner.Align(tls, t => Enumerable.Range(0, t.Count).Select(i => SegmentAnalyzer.AccelValid(t, i) ? t.AccelLong[i] : double.NaN).ToArray(), Alignment, step);
        CompareSpeedSeries = picked.Select((s, i) => new ChartSeries { Name = s.DateText, X = sp.Axis, Y = Scale(sp.Values[i], 3.6), Color = s.CompareColor, Thickness = 1.3, Unit = "km/h" }).ToList();
        CompareAccelSeries = picked.Select((s, i) => new ChartSeries { Name = s.DateText, X = ac.Axis, Y = ac.Values[i], Color = s.CompareColor, Thickness = 1.1, Unit = "m/s²", Format = "0.00" }).ToList();
        if (CompareVerdict.StartsWith("Marca", StringComparison.Ordinal) || CompareVerdict.StartsWith("Comparando", StringComparison.Ordinal))
            CompareVerdict = $"{picked.Count} entrenamientos alineados por {(Alignment == AlignmentMode.Distance ? "distancia recorrida" : "tiempo relativo")}. " +
                             "Las series no se interpolan a través de pérdidas de señal. La correspondencia espacial se comprueba con el motor (botón «Comparar con el motor»).";
    }
}
