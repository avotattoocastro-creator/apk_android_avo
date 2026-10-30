using System.Globalization;
using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Microsoft.Win32;
using Avo.Windows.Core;

namespace Avo.Windows;

// Integration of the AVO Equine Intelligence Engine (avo_equine.dll) in the existing window:
// load -> process through the DLL (background, cancellable, stored per session) -> synchronised charts sharing the
// track selection -> per-gait analysis, curves, events, quality -> interval selection -> comparison -> export.
public partial class MainWindow
{
    private readonly Dictionary<string, EquineAnalysis> _engine = new(StringComparer.Ordinal);
    private CancellationTokenSource? _engineCts;
    private string? _engineRunning;
    private static readonly CultureInfo EsC = CultureInfo.GetCultureInfo("es-ES");
    private static string EngineRoot => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AVO Performance Horse", "Windows", "analisis");

    private void InitEngine()
    {
        EngSpeedChart.PointSelected += SelectPoint;
        EngAccelChart.PointSelected += SelectPoint;
        EngCadenceChart.PointSelected += SelectPoint;
        EngGaitChart.PointSelected += SelectPoint;
        EngSpeedChart.Stroke = Color.FromRgb(19, 184, 245);
        EngCadenceChart.Stroke = Color.FromRgb(53, 208, 232);
        EngComparePicker.ItemsSource = _sessions;
        if (!EquineEngine.Available) EngineStatus.Text = EquineEngine.UnavailableReason ?? "Motor no disponible";
    }

    private EquineAnalysis? ActiveEngine => _active is not null && _engine.TryGetValue(_active.SessionId, out var r) ? r : null;

    private static string Clean(string v) => string.Concat(v.Select(c => char.IsLetterOrDigit(c) || c is '-' or '_' ? c : '_'));

    private async Task RunEngineAsync(TrainingSession s, bool force)
    {
        if (!EquineEngine.Available) { EngineStatus.Text = EquineEngine.UnavailableReason ?? "Motor no disponible"; return; }
        if (s.RawSegmentPaths.Count == 0) { EngineStatus.Text = "Esta sesión no contiene segmentos RAW: el motor necesita los datos originales (.avr / .avo con segmentos)."; return; }
        _engineCts?.Cancel();
        var cts = new CancellationTokenSource();
        _engineCts = cts; _engineRunning = s.SessionId;
        EngineStatus.Text = (force ? "Reprocesando " : "Analizando ") + s.SessionId + "…";
        try
        {
            string dir = Path.Combine(EngineRoot, Clean(s.SessionId));
            var paths = s.RawSegmentPaths.ToList();
            var json = await Task.Run(() => EquineEngine.AnalyseJson(paths, EquineEngine.Options(true, dir, force), cts.Token));
            var r = EquineAnalysis.Parse(json);
            _engine[s.SessionId] = r;
            EngineStatus.Text = $"Motor {r.Engine} · {(r.Cache == "ACIERTO" ? "resultado guardado reutilizado" : r.Cache == "RECALCULADO" ? "recalculado" : "calculado")} · {r.Mode}" +
                (r.Warnings.Count > 0 ? " · " + string.Join(" · ", r.Warnings) : "");
        }
        catch (OperationCanceledException) { EngineStatus.Text = "Análisis cancelado."; }
        catch (Exception ex) { EngineStatus.Text = "Error del motor: " + ex.Message; }
        finally { if (ReferenceEquals(_engineCts, cts)) { _engineCts = null; _engineRunning = null; } cts.Dispose(); }
        if (_active == s) UpdateEngineView();
    }

    private async void EnsureEngine()
    {
        var s = _active;
        if (s is null || !EquineEngine.Available || _engine.ContainsKey(s.SessionId) || _engineRunning == s.SessionId || s.RawSegmentPaths.Count == 0) return;
        await RunEngineAsync(s, false);
    }

    private void UpdateEngineView()
    {
        var s = _active; var r = ActiveEngine;
        if (s is null) { EngineStatus.Text = "Selecciona una sesión"; }
        if (r is null || s is null)
        {
            EngSpeedChart.Values = []; EngAccelChart.Values = []; EngCadenceChart.Values = []; EngGaitChart.Codes = [];
            EngGaitTable.ItemsSource = null; EngSegmentsTable.ItemsSource = null; EngCurvesTable.ItemsSource = null; EngEventsTable.ItemsSource = null; EngQualityTable.ItemsSource = null;
            EngFusion.Text = ""; EngSymmetry.Text = "";
            EnsureEngine();
            return;
        }
        // engine series aligned to the track points of the existing charts (same index axis, same selection)
        var times = s.Track.Select(p => r.TimeOf(p.GpsWeekMs)).ToArray();
        EngSpeedChart.Values = times.Select(t => t is double x ? r.GnssAt(r.Speed, x) * 3.6 : double.NaN).ToArray();
        EngAccelChart.Values = times.Select(t => t is double x ? r.GnssAt(r.Accel, x) : double.NaN).ToArray();
        EngCadenceChart.Values = r.HasImu ? times.Select(t => t is double x ? r.CadenceAt(x) * 60 : double.NaN).ToArray() : [];
        EngGaitChart.Codes = times.Select(t => t is double x ? r.GaitAt(x) : -1).ToArray();
        EngGaitTable.ItemsSource = r.PerGait;
        EngSegmentsTable.ItemsSource = r.Segments;
        EngCurvesTable.ItemsSource = r.Curves;
        EngEventsTable.ItemsSource = r.Events;
        EngQualityTable.ItemsSource = r.Quality;
        EngFusion.Text = r.FusionSummary + (r.HasImu ? "" : " · SIN DATOS DE CINCHA");
        EngSymmetry.Text = $"{r.SymmetryLabel}: {(r.SymmetryAllowed ? "datos suficientes para describir diferencias de la señal" : "sin conclusiones (datos insuficientes o controles que bloquean)")}\n" + string.Join("\n", r.SymmetryControls);
    }

    private void EngineSelect(int index)
    {
        EngSpeedChart.SelectedIndex = index; EngAccelChart.SelectedIndex = index; EngCadenceChart.SelectedIndex = index; EngGaitChart.SelectedIndex = index;
        var s = _active; var r = ActiveEngine;
        if (s is null || r is null || index < 0 || index >= s.Track.Count) { EngInstant.Text = "Haz clic en una gráfica para ver los valores del instante"; return; }
        double t = r.TimeOf(s.Track[index].GpsWeekMs) ?? double.NaN;
        int g = r.GaitAt(t);
        string cad = r.HasImu ? $"{r.CadenceAt(t) * 60:0} /min" : "SIN DATOS DE CINCHA";
        EngInstant.Text = string.Format(EsC, "t = {0:0.0} s · velocidad {1:0.0} km/h · aceleración {2:0.00} m/s² · lateral (est.) {3:0.00} m/s² · aire {4} · cadencia {5}",
            t, r.GnssAt(r.Speed, t) * 3.6, r.GnssAt(r.Accel, t), r.GnssAt(r.LatAccel, t),
            g switch { 0 => "parado", 1 => "paso", 2 => "trote", 3 => "galope", 4 => "transición", 5 => "desconocido", 6 => "datos insuficientes", _ => "—" }, cad).Replace("NaN", "—");
    }

    private int IndexOfTime(double t)
    {
        var s = _active; var r = ActiveEngine;
        if (s is null || r is null || s.Track.Count == 0) return -1;
        int best = -1; double bd = double.MaxValue;
        for (int i = 0; i < s.Track.Count; i++) if (r.TimeOf(s.Track[i].GpsWeekMs) is double x && Math.Abs(x - t) < bd) { bd = Math.Abs(x - t); best = i; }
        return best;
    }

    private void EngRow_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (sender is not DataGrid dg) return;
        double? t = dg.SelectedItem switch { EngineSegmentRow sr => sr.T0, EngineCurveRow cr => cr.T0, EngineEventRow er => er.T0, _ => null };
        if (t is double v && double.IsFinite(v)) { int i = IndexOfTime(v); if (i >= 0) SelectPoint(i); }
    }

    private async void EngineAnalyse_Click(object sender, RoutedEventArgs e) { if (_active is not null) await RunEngineAsync(_active, false); }
    private async void EngineReprocess_Click(object sender, RoutedEventArgs e) { if (_active is not null) await RunEngineAsync(_active, true); }
    private void EngineCancel_Click(object sender, RoutedEventArgs e) => _engineCts?.Cancel();

    private double? SelectedTime()
    {
        var s = _active; var r = ActiveEngine;
        int i = EngSpeedChart.SelectedIndex;
        return s is not null && r is not null && i >= 0 && i < s.Track.Count ? r.TimeOf(s.Track[i].GpsWeekMs) : null;
    }
    private void EngFromPoint_Click(object sender, RoutedEventArgs e) { if (SelectedTime() is double t) EngFrom.Text = t.ToString("0.0", CultureInfo.InvariantCulture); }
    private void EngToPoint_Click(object sender, RoutedEventArgs e) { if (SelectedTime() is double t) EngTo.Text = t.ToString("0.0", CultureInfo.InvariantCulture); }

    private async void EngInterval_Click(object sender, RoutedEventArgs e)
    {
        var s = _active;
        if (s is null || s.RawSegmentPaths.Count == 0 || !EquineEngine.Available) { EngineStatus.Text = "Selecciona una sesión con datos RAW"; return; }
        if (!double.TryParse(EngFrom.Text.Replace(',', '.'), NumberStyles.Float, CultureInfo.InvariantCulture, out double a) ||
            !double.TryParse(EngTo.Text.Replace(',', '.'), NumberStyles.Float, CultureInfo.InvariantCulture, out double b) || b <= a)
        { EngineStatus.Text = "Intervalo no válido: indica inicio y fin en segundos (fin > inicio)"; return; }
        string sel = string.Format(CultureInfo.InvariantCulture, "{{\"tipo\":\"TIEMPO\",\"a\":{0},\"b\":{1}}}", a, b);
        try
        {
            var paths = s.RawSegmentPaths.ToList();
            var json = await Task.Run(() => EquineEngine.CompareJson(paths, paths, "{\"seleccion_a\":" + sel + ",\"seleccion_b\":" + sel + "}"));
            EngIntervalTable.ItemsSource = EquineSection.ParseA(json);
        }
        catch (Exception ex) { EngineStatus.Text = "Error en el intervalo: " + ex.Message; }
    }

    private async void EngCompare_Click(object sender, RoutedEventArgs e)
    {
        var s = _active; var other = EngComparePicker.SelectedItem as TrainingSession;
        if (s is null || other is null) { EngCompareVerdict.Text = "Elige la sesión con la que comparar"; return; }
        if (s.RawSegmentPaths.Count == 0 || other.RawSegmentPaths.Count == 0) { EngCompareVerdict.Text = "Las dos sesiones necesitan segmentos RAW"; return; }
        bool route = EngSameRoute.IsChecked == true;
        EngCompareVerdict.Text = "Comparando…";
        try
        {
            var pa = s.RawSegmentPaths.ToList(); var pb = other.RawSegmentPaths.ToList();
            var json = await Task.Run(() => EquineEngine.CompareJson(pa, pb, route ? "{\"mismo_recorrido\":true}" : "{}"));
            var (rows, verdict) = EquineComparisonRows.Parse(json);
            EngCompareTable.ItemsSource = rows; EngCompareVerdict.Text = verdict;
        }
        catch (Exception ex) { EngCompareVerdict.Text = "Error del motor: " + ex.Message; }
    }

    private void EngineExportJson_Click(object sender, RoutedEventArgs e)
    {
        var r = ActiveEngine; if (r is null || _active is null) { MessageBox.Show(this, "Analiza primero la sesión con el motor.", "Sin resultado"); return; }
        var dlg = new SaveFileDialog { Filter = "Resultado del motor (*.json)|*.json", FileName = $"AVO_motor_{Clean(_active.SessionId)}.json" };
        if (dlg.ShowDialog(this) != true) return;
        File.WriteAllText(dlg.FileName, r.RawJson, new UTF8Encoding(false));
        StatusLine.Text = "Exportado: " + dlg.FileName;
    }

    private void EngineExportCsv_Click(object sender, RoutedEventArgs e)
    {
        var r = ActiveEngine; if (r is null || _active is null) { MessageBox.Show(this, "Analiza primero la sesión con el motor.", "Sin resultado"); return; }
        var dlg = new SaveFileDialog { Filter = "CSV (*.csv)|*.csv", FileName = $"AVO_motor_tramos_{Clean(_active.SessionId)}.csv" };
        if (dlg.ShowDialog(this) != true) return;
        var sb = new StringBuilder("id;aire;desde;hasta;distancia;velocidad_media;velocidad_max;cadencia;tranco;correlacion_ciclos;cv_intervalos;calidad_gnss;calidad_imu;avisos\n");
        foreach (var x in r.Segments)
            sb.AppendLine(string.Join(';', new[] { x.Id.ToString(CultureInfo.InvariantCulture), x.Aire, x.Desde, x.Hasta, x.Distancia, x.VelocidadMedia, x.VelocidadMax, x.Cadencia, x.Tranco, x.CorrCiclos, x.CvIntervalos, x.CalidadGnss, x.CalidadImu, x.Avisos }.Select(v => v.Replace(';', ','))));
        File.WriteAllText(dlg.FileName, sb.ToString(), new UTF8Encoding(true));
        StatusLine.Text = "Exportado: " + dlg.FileName;
    }
}
