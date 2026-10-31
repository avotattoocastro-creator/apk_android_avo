using System.Collections.ObjectModel;
using System.Windows.Media;
using Avo.Windows.Controls;
using Avo.Windows.Core;

namespace Avo.Windows.ViewModels;

public sealed record KeyValueRow(string Key, string Value);

public sealed partial class MainViewModel
{
    public static readonly Color Red = Color.FromRgb(0xED, 0x12, 0x2A), RedLight = Color.FromRgb(0xFF, 0x49, 0x5A), Blue = Color.FromRgb(0x3D, 0x9B, 0xFF),
        Cyan = Color.FromRgb(0x35, 0xD0, 0xE8), Silver = Color.FromRgb(0xC9, 0xCB, 0xD1), Ok = Color.FromRgb(0x52, 0xDD, 0x40), Warn = Color.FromRgb(0xFF, 0xC4, 0x2C),
        Dim = Color.FromRgb(0x93, 0x94, 0x9B), Violet = Color.FromRgb(0xA8, 0x6B, 0xFF);

    private IReadOnlyList<ChartSeries> _speedSeries = [], _accelSeries = [], _altSeries = [], _precSeries = [], _satSeries = [], _imuSeries = [], _gyroSeries = [], _cadSeries = [];
    public IReadOnlyList<ChartSeries> SpeedSeries { get => _speedSeries; private set => Set(ref _speedSeries, value); }
    public IReadOnlyList<ChartSeries> AccelSeries { get => _accelSeries; private set => Set(ref _accelSeries, value); }
    public IReadOnlyList<ChartSeries> AltitudeSeries { get => _altSeries; private set => Set(ref _altSeries, value); }
    public IReadOnlyList<ChartSeries> PrecisionSeries { get => _precSeries; private set => Set(ref _precSeries, value); }
    public IReadOnlyList<ChartSeries> SatelliteSeries { get => _satSeries; private set => Set(ref _satSeries, value); }
    public IReadOnlyList<ChartSeries> ImuSeries { get => _imuSeries; private set => Set(ref _imuSeries, value); }
    public IReadOnlyList<ChartSeries> GyroSeries { get => _gyroSeries; private set => Set(ref _gyroSeries, value); }
    public IReadOnlyList<ChartSeries> CadenceSeries { get => _cadSeries; private set => Set(ref _cadSeries, value); }
    private IReadOnlyList<ChartBand> _qualityBands = [], _gaitBands = [];
    public IReadOnlyList<ChartBand> QualityBands { get => _qualityBands; private set => Set(ref _qualityBands, value); }
    public IReadOnlyList<ChartBand> GaitBands { get => _gaitBands; private set => Set(ref _gaitBands, value); }

    private double[]? _speedSpark, _accelSpark, _altSpark, _cadSpark;
    public double[]? SpeedSpark { get => _speedSpark; private set => Set(ref _speedSpark, value); }
    public double[]? AccelSpark { get => _accelSpark; private set => Set(ref _accelSpark, value); }
    public double[]? AltitudeSpark { get => _altSpark; private set => Set(ref _altSpark, value); }
    public double[]? CadenceSpark { get => _cadSpark; private set => Set(ref _cadSpark, value); }

    private bool _showReported = true, _showDerived, _showFiltered = true, _showLateral = true;
    public bool ShowSpeedReported { get => _showReported; set { if (Set(ref _showReported, value)) RebuildCharts(); } }
    public bool ShowSpeedDerived { get => _showDerived; set { if (Set(ref _showDerived, value)) RebuildCharts(); } }
    public bool ShowSpeedFiltered { get => _showFiltered; set { if (Set(ref _showFiltered, value)) RebuildCharts(); } }
    public bool ShowLateral { get => _showLateral; set { if (Set(ref _showLateral, value)) RebuildCharts(); } }
    private bool _chartSpeed = true, _chartAccel = true, _chartImu = true, _chartAlt = true, _chartPrecision = true, _chartCadence = true;
    public bool ChartSpeed { get => _chartSpeed; set => Set(ref _chartSpeed, value); }
    public bool ChartAccel { get => _chartAccel; set => Set(ref _chartAccel, value); }
    public bool ChartImu { get => _chartImu; set => Set(ref _chartImu, value); }
    public bool ChartAltitude { get => _chartAlt; set => Set(ref _chartAlt, value); }
    public bool ChartPrecision { get => _chartPrecision; set => Set(ref _chartPrecision, value); }
    public bool ChartCadence { get => _chartCadence; set => Set(ref _chartCadence, value); }
    public string FilterDescription => Selected?.Timeline.FilterParameters.Describe() ?? new SpeedSmoother.Parameters().Describe();
    public string ImuScaleNote => Selected?.Imu.Note ?? ImuTimeline.ScaleNote;
    public string ImuChartHeader => Selected?.Session.ImuUnits == 1
        ? "IMU cincha · aceleración vertical z (g, unidades del BNO085)" : "IMU cincha · aceleración vertical z (g, escala nominal)";

    public ObservableCollection<KeyValueRow> RangeStats { get; } = [];
    public ObservableCollection<KeyValueRow> SessionStats { get; } = [];
    public ObservableCollection<KeyValueRow> GnssStats { get; } = [];

    private static double[] Scale(double[] v, double k) { var r = new double[v.Length]; for (int i = 0; i < v.Length; i++) r[i] = v[i] * k; return r; }

    private void RebuildCharts()
    {
        var s = Selected;
        if (s is null || s.Timeline.Count < 2)
        {
            SpeedSeries = []; AccelSeries = []; AltitudeSeries = []; PrecisionSeries = []; SatelliteSeries = []; ImuSeries = []; GyroSeries = []; CadenceSeries = [];
            QualityBands = []; GaitBands = []; SpeedSpark = null; AccelSpark = null; AltitudeSpark = null; CadenceSpark = null;
            return;
        }
        var tl = s.Timeline;
        var sp = new List<ChartSeries>();
        if (ShowSpeedReported) sp.Add(new ChartSeries { Name = "Reportada (GNSS)", X = tl.T, Y = Scale(tl.SpeedReported, 3.6), Breaks = tl.BreakBefore, Color = Color.FromArgb(0xA0, 0x3D, 0x9B, 0xFF), Thickness = 1, Unit = "km/h" });
        if (ShowSpeedDerived) sp.Add(new ChartSeries { Name = "Derivada de posiciones", X = tl.T, Y = Scale(tl.SpeedDerived, 3.6), Breaks = tl.BreakBefore, Color = Silver, Thickness = 1, Dashed = true, Unit = "km/h" });
        if (ShowSpeedFiltered) sp.Add(new ChartSeries { Name = "Filtrada (Kalman RTS)", X = tl.T, Y = Scale(tl.SpeedFiltered, 3.6), Breaks = tl.BreakBefore, Color = Red, Thickness = 1.6, Unit = "km/h" });
        SpeedSeries = sp;
        var validAccel = Enumerable.Range(0, tl.Count).Select(i => SegmentAnalyzer.AccelValid(tl, i) ? tl.AccelLong[i] : double.NaN).ToArray();
        var ac = new List<ChartSeries> { new() { Name = "Longitudinal (validada)", X = tl.T, Y = validAccel, Breaks = tl.BreakBefore, Color = Warn, Thickness = 1.3, Unit = "m/s²", Format = "0.00" } };
        if (ShowLateral) ac.Add(new ChartSeries { Name = "Lateral (v·ω, v ≥ 2 m/s)", X = tl.T, Y = tl.AccelLateral, Breaks = tl.BreakBefore, Color = Cyan, Thickness = 1, Unit = "m/s²", Format = "0.00" });
        AccelSeries = ac;
        AltitudeSeries = tl.AltitudeMsl.Any(double.IsFinite)
            ? new[] { new ChartSeries { Name = "Altitud GNSS (nivel medio del mar)", X = tl.T, Y = tl.AltitudeMsl, Breaks = tl.BreakBefore, Color = Ok, Unit = "m" } } : Array.Empty<ChartSeries>();
        PrecisionSeries = [new ChartSeries { Name = "hAcc reportada", X = tl.T, Y = tl.HAcc, Breaks = tl.BreakBefore, Color = Violet, Unit = "m", Format = "0.000" }];
        SatelliteSeries = [new ChartSeries { Name = "Satélites", X = tl.T, Y = tl.NumSv.Select(x => (double)x).ToArray(), Breaks = tl.BreakBefore, Color = Silver, Unit = "", Format = "0" }];
        // quality bands (contiguous runs)
        var qb = new List<ChartBand>();
        int start = 0;
        for (int i = 1; i <= tl.Count; i++)
        {
            if (i == tl.Count || tl.Solution[i] != tl.Solution[start] || tl.BreakBefore[i])
            {
                var (r, g, b) = SpeedScale.Solution(tl.Solution[start]);
                qb.Add(new ChartBand(tl.T[start], tl.T[Math.Min(i, tl.Count - 1)], Color.FromRgb(r, g, b)));
                start = i;
            }
        }
        foreach (var l in tl.Losses) qb.Add(new ChartBand(l.T0, l.T1, Color.FromRgb(0xFF, 0x39, 0x45)));
        QualityBands = qb;
        // gait bands from the engine
        var gb = new List<ChartBand>();
        if (s.Engine is { HasImu: true } eng)
        {
            foreach (var seg in eng.Segments)
            {
                int code = seg.GaitCode switch { "STOPPED" => 0, "WALK" => 1, "TROT" => 2, "CANTER_GALLOP" => 3, _ => -1 };
                var (r, g, b) = SpeedScale.Gait(code);
                gb.Add(new ChartBand(seg.T0 - s.EngineOffsetS, seg.T1 - s.EngineOffsetS, Color.FromRgb(r, g, b)));
            }
        }
        GaitBands = gb;
        // girth IMU (vertical axis z and |a|, nominal scale, not calibrated)
        var imu = new List<ChartSeries>(); var gyro = new List<ChartSeries>();
        foreach (var ch in s.Imu.Channels)
        {
            var c = HorseDiagram.SensorColor(ch.ImuId);
            imu.Add(new ChartSeries { Name = ch.Name, X = ch.T, Y = ch.AxisG('z'), Color = c, Thickness = 1, Unit = "g", Format = "0.00" });
            gyro.Add(new ChartSeries { Name = ch.Name, X = ch.T, Y = ch.GyroDps('x'), Color = c, Thickness = 1, Unit = "°/s", Format = "0" });
        }
        ImuSeries = imu; GyroSeries = gyro;
        var cad = new List<ChartSeries>();
        if (s.Engine is { HasImu: true } e2 && e2.GirthT.Length > 0)
        {
            foreach (var id in e2.GirthImu.Distinct().OrderBy(x => x))
            {
                var idx = Enumerable.Range(0, e2.GirthT.Length).Where(k => e2.GirthImu[k] == id && double.IsFinite(e2.GirthT[k])).OrderBy(k => e2.GirthT[k]).ToArray();
                cad.Add(new ChartSeries
                {
                    Name = ImuTimeline.SensorName((byte)id), X = idx.Select(k => e2.GirthT[k] - s.EngineOffsetS).ToArray(),
                    Y = idx.Select(k => e2.GirthStatus[k] == "OK" ? e2.GirthCadenceHz[k] * 60 : double.NaN).ToArray(),
                    Color = HorseDiagram.SensorColor((byte)id), Thickness = 1.4, Unit = "ciclos/min", Format = "0",
                });
            }
        }
        CadenceSeries = cad;
        SpeedSpark = Scale(tl.SpeedFiltered, 3.6);
        AccelSpark = validAccel;
        AltitudeSpark = tl.AltitudeMsl.Any(double.IsFinite) ? tl.AltitudeMsl : null;
        CadenceSpark = cad.Count > 0 ? cad[0].Y : null;
        Raise(nameof(FilterDescription));
        Raise(nameof(ImuScaleNote));
        Raise(nameof(ImuChartHeader));
    }

    private void RefreshRangeStats()
    {
        RangeStats.Clear();
        var s = Selected;
        if (s is null || !HasRange) return;
        var m = SegmentAnalyzer.Compute(s.Timeline, new SegmentDefinition { Name = "Selección", T0 = RangeStart, T1 = RangeEnd }, s.Engine, s.EngineOffsetS);
        foreach (var r in MetricRows(m)) RangeStats.Add(r);
    }

    public static IEnumerable<KeyValueRow> MetricRows(SegmentMetrics m)
    {
        yield return new("Inicio", Core.TimeText.Clock(m.T0));
        yield return new("Fin", Core.TimeText.Clock(m.T1));
        yield return new("Duración", Core.TimeText.Clock(m.DurationS));
        yield return new("Distancia", Core.TimeText.Num(m.DistanceM / 1000, "0.00", " km"));
        yield return new("Vel. media", Core.TimeText.Num(m.MeanSpeedKmh, "0.0", " km/h"));
        yield return new("Vel. máxima", Core.TimeText.Num(m.MaxSpeedKmh, "0.0", " km/h"));
        yield return new("Aceleración máx. validada", Core.TimeText.Num(m.MaxAccel, "0.00", " m/s²"));
        yield return new("Frenada máx. validada", Core.TimeText.Num(m.MaxDecel, "0.00", " m/s²"));
        yield return new("Cambios de ritmo", m.SpeedChanges.ToString(Es));
        yield return new("RTK FIX", Core.TimeText.Num(m.FixFraction * 100, "0", " %"));
        yield return new("Cadencia (motor)", Core.TimeText.Num(m.Cadence, "0", " ciclos/min"));
        yield return new("Regularidad (correlación ciclos)", Core.TimeText.Num(m.CycleCorrelation, "0.00"));
    }

    private void RefreshSessionPanels()
    {
        SessionStats.Clear(); GnssStats.Clear();
        var s = Selected;
        if (s is null) return;
        var tl = s.Timeline;
        SessionStats.Add(new("Caballo", s.Horse));
        SessionStats.Add(new("Jinete", s.Rider));
        SessionStats.Add(new("Modalidad", s.Discipline));
        SessionStats.Add(new("Fecha", s.DateTimeText));
        SessionStats.Add(new("Zona horaria", s.Start is DateTimeOffset u ? "Europe/Madrid · " + MadridTime.ZoneLabel(u) : "—"));
        SessionStats.Add(new("Duración", s.DurationText));
        SessionStats.Add(new("Distancia", s.DistanceText));
        SessionStats.Add(new("Datos", s.Kind));
        var dist = GnssQuality.Distribution(s.Session.GnssEpochs);
        GnssStats.Add(new("RTK FIX", dist[GnssSolution.RtkFix].ToString("0.0", Es) + " %"));
        GnssStats.Add(new("RTK FLOAT", dist[GnssSolution.RtkFloat].ToString("0.0", Es) + " %"));
        GnssStats.Add(new("DGNSS", dist[GnssSolution.Dgnss].ToString("0.0", Es) + " %"));
        GnssStats.Add(new("Autónomo", dist[GnssSolution.Autonomous].ToString("0.0", Es) + " %"));
        GnssStats.Add(new("Sin solución válida", dist[GnssSolution.None].ToString("0.0", Es) + " %"));
        GnssStats.Add(new("Satélites (mediana)", tl.Count > 0 ? Stats.Median(tl.NumSv.Select(x => (double)x)).ToString("0", Es) : "—"));
        GnssStats.Add(new("hAcc reportada (mediana)", tl.Count > 0 ? Stats.Median(tl.HAcc).ToString("0.000", Es) + " m" : "—"));
        GnssStats.Add(new("Pérdidas de señal", $"{tl.Losses.Count} · {Core.TimeText.Clock(tl.Losses.Sum(l => l.DurationS))}"));
        GnssStats.Add(new("Saltos descartados", tl.JumpBefore.Count(x => x).ToString(Es)));
        GnssStats.Add(new("Frecuencia GNSS", tl.NominalDtS > 0 ? (1 / tl.NominalDtS).ToString("0.#", Es) + " Hz" : "—"));
        RaiseMany(nameof(SessionHeaderTitle), nameof(SessionHeaderSubtitle), nameof(EngineStateText), nameof(SensorStatus));
    }

    public string SessionHeaderTitle => Selected is null ? "Sin entrenamiento seleccionado" : $"Entrenamiento {Selected.DateTimeText}";
    public string SessionHeaderSubtitle => Selected is null ? "Importa un archivo .avo o .avr" : $"{Selected.Horse} · {Selected.Rider} · {Selected.Discipline}";
    public string EngineStateText => Selected?.EngineState ?? "—";
    public IReadOnlyList<KeyValueRow> SensorStatus => Selected is null ? Array.Empty<KeyValueRow>() : new KeyValueRow[]
    {
        new("GNSS/RTK chaleco", $"{Selected.Session.GnssSamples} épocas · {Selected.FixText} FIX"),
        new("Cincha IMU", Selected.GirthText),
        new("Marcadores", Selected.Session.Markers.Count.ToString(Es)),
        new("Integridad", Selected.Integrity),
    };
}
