using System.IO;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Globalization;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
using Avo.Windows.Core;

namespace Avo.Windows;

public partial class MainWindow : Window
{
    private readonly ObservableCollection<TrainingSession> _sessions = [];
    private readonly List<string> _sources = [];
    private readonly string _prefsDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "AVO Performance Horse", "Windows");
    private TrainingSession? _active;
    private bool _isLoading;
    private sealed record TrainingRow(TrainingSession Training)
    {
        public string Caballo => Training.Horse;
        public string Jinete => Training.Rider;
        public string Fecha => Training.DateText;
        public string Distancia => $"{Training.DistanceM / 1000:0.00} km";
        public string Duración => Analytics.Duration(Training.DurationSeconds);
        public string Integridad => Training.Integrity;
    }
    public MainWindow()
    {
        InitializeComponent();
        SessionPicker.ItemsSource = _sessions;
        ComparePicker.ItemsSource = _sessions;
        AnalysisChart.PointSelected += SelectPoint;
        VelocityChart.PointSelected += SelectPoint;
        AccuracyChart.PointSelected += SelectPoint;
        AnalysisRoute.SelectedIndex = -1;
        AccuracyChart.ShowAccuracy = true;
        Loaded += async (_, _) => await RestoreAsync();
        InitEngine();
        InitUsb();
        UpdateViews();
    }
    private void Navigate_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button b && int.TryParse(b.Tag?.ToString(), out int index)) Views.SelectedIndex = index;
    }
    private void SessionPicker_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isLoading) return;
        _active = SessionPicker.SelectedItem as TrainingSession;
        SelectPoint(-1);
        UpdateViews();
    }
    private void ComparePicker_SelectionChanged(object sender, SelectionChangedEventArgs e) => UpdateComparison();
    private void HomeList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (HomeList.SelectedItem is TrainingRow row) { SessionPicker.SelectedItem = row.Training; Views.SelectedIndex = 1; }
    }
    private async void Open_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog { Title = "Selecciona entrenamientos AVO", Filter = "Entrenamientos AVO (*.avo;*.avr)|*.avo;*.avr", Multiselect = true };
        if (dialog.ShowDialog(this) == true) await ImportManyAsync(dialog.FileNames);
    }
    private async void Folder_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new OpenFolderDialog { Title = "Carpeta con entrenamientos .avo / .avr" };
        if (dlg.ShowDialog(this) != true) return;
        var paths = Directory.EnumerateFiles(dlg.FolderName, "*", SearchOption.TopDirectoryOnly)
            .Where(p => p.EndsWith(".avo", StringComparison.OrdinalIgnoreCase) || p.EndsWith(".avr", StringComparison.OrdinalIgnoreCase)).Take(100).ToArray();
        await ImportManyAsync(paths);
    }
    private async Task RestoreAsync()
    {
        try
        {
            Directory.CreateDirectory(_prefsDir);
            string file = Path.Combine(_prefsDir, "recientes.json");
            if (File.Exists(file))
            {
                var paths = JsonSerializer.Deserialize<string[]>(await File.ReadAllTextAsync(file)) ?? [];
                await ImportManyAsync(paths.Where(File.Exists).Take(100), true);
            }
        }
        catch (Exception ex) { StatusLine.Text = "No se pudo restaurar historial: " + ex.Message; }
    }
    private async Task ImportManyAsync(IEnumerable<string> filenames, bool restoring = false)
    {
        var names = filenames.Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        int imported = 0, rejected = 0;
        foreach (string filename in names)
        {
            try
            {
                StatusLine.Text = "Validando: " + Path.GetFileName(filename);
                var session = await Task.Run(() => TrainingImporter.Import(filename));
                var existing = _sessions.FirstOrDefault(x => x.SessionId == session.SessionId);
                if (existing != null) { _sessions.Remove(existing); _sources.RemoveAll(p => p.Equals(existing.SourceName, StringComparison.OrdinalIgnoreCase)); }
                LoadMarineCache(session);
                _sessions.Add(session);
                if (!_sources.Contains(filename, StringComparer.OrdinalIgnoreCase)) _sources.Add(filename);
                imported++;
            }
            catch (Exception ex)
            {
                rejected++;
                if (!restoring) MessageBox.Show(this, $"{Path.GetFileName(filename)}: {ex.Message}", "Archivo rechazado", MessageBoxButton.OK, MessageBoxImage.Warning);
            }
        }
        if (_active is null || !_sessions.Contains(_active))
        {
            _isLoading = true;
            SessionPicker.SelectedItem = _sessions.LastOrDefault();
            _active = SessionPicker.SelectedItem as TrainingSession;
            _isLoading = false;
        }
        StatusLine.Text = $"Importación: {imported} aceptados, {rejected} rechazados · {_sessions.Count} sesiones";
        UpdateViews();
        if (imported > 0) await SaveHistoryAsync();
    }
    private async Task SaveHistoryAsync()
    {
        try
        {
            Directory.CreateDirectory(_prefsDir);
            await File.WriteAllTextAsync(Path.Combine(_prefsDir, "recientes.json"), JsonSerializer.Serialize(_sources));
        }
        catch (Exception ex) { StatusLine.Text = "No se pudo guardar historial: " + ex.Message; }
    }
    private string MarineCacheFile(TrainingSession s)
    {
        var name = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(s.SessionId)));
        return Path.Combine(_prefsDir, "marine", name + ".json");
    }
    private void LoadMarineCache(TrainingSession session)
    {
        string path = MarineCacheFile(session);
        if (File.Exists(path))
        {
            try { MarineMetadata.LoadJson(session, path); }
            catch { /* Older incompatible metadata remains untrusted and is not shown. */ }
        }
    }
    private void UpdateViews()
    {
        var s = _active;
        HomeCount.Text = _sessions.Count.ToString(CultureInfo.InvariantCulture);
        HomeHorse.Text = s?.Horse ?? "—";
        HomeSpeed.Text = s is null ? "—" : $"{s.MaxSpeedKmh:0.0} km/h";
        HomeIntegrity.Text = s?.Integrity ?? "No hay datos";
        HomeList.ItemsSource = _sessions.Select(x => new TrainingRow(x)).ToList();
        SideIntegrity.Text = s?.Integrity ?? "Importa un entrenamiento";
        StatDistance.Text = s is null ? "—" : $"{s.DistanceM / 1000:0.00} km";
        StatDuration.Text = s is null ? "—" : Analytics.Duration(s.DurationSeconds);
        StatMax.Text = s is null ? "—" : $"{s.MaxSpeedKmh:0.0} km/h";
        StatMean.Text = s is null ? "—" : $"{s.MeanSpeedKmh:0.0} km/h";
        StatFix.Text = s is null ? "—" : $"{s.FixPercent:0.0} %";
        AnalysisRoute.Session = s;
        AnalysisChart.Session = s;
        VelocityChart.Session = s;
        AccuracyChart.Session = s;
        SegmentsTable.ItemsSource = s is null ? null : Analytics.Sections(s);
        ImuSamplesText.Text = s?.TotalImuSamples.ToString(CultureInfo.InvariantCulture) ?? "—";
        ImuBatchesText.Text = s?.TotalImuBatches.ToString(CultureInfo.InvariantCulture) ?? "—";
        InvalidFramesText.Text = s?.InvalidFrames.ToString(CultureInfo.InvariantCulture) ?? "—";
        MarineTide.Text = s?.TideHeightM?.ToString("0.##") ?? "Sin datos";
        MarineWind.Text = s?.WindKmh?.ToString("0.#") ?? "Sin datos";
        MarineWave.Text = s?.WaveHeightM?.ToString("0.##") ?? "Sin datos";
        MarineSourceText.Text = s?.MarineSource is null ? "Sin instantánea marina válida para esta sesión." :
            $"Fuente: {s.MarineSource}\nTipo: {s.MarineKind}\nReferencia: {s.MarineObservedAt:dd/MM/yyyy HH:mm zzz}\nNotas: {s.MarineNotes}";
        ReportPreview.Text = s is null ? "Importa un entrenamiento para crear informes" :
            $"Caballo: {s.Horse}\nJinete: {s.Rider}\nFecha: {s.DateText}\nDistancia: {s.DistanceM / 1000:0.00} km\nDuración: {Analytics.Duration(s.DurationSeconds)}\nVelocidad máxima: {s.MaxSpeedKmh:0.0} km/h\nIntegridad: {s.Integrity}";
        UpdateComparison();
        UpdateEngineView();
    }
    private void SelectPoint(int index)
    {
        AnalysisRoute.SelectedIndex = index;
        AnalysisChart.SelectedIndex = index;
        VelocityChart.SelectedIndex = index;
        AccuracyChart.SelectedIndex = index;
        if (_active?.Track is { Count: > 0 } t && index >= 0 && index < t.Count)
            StatPoint.Text = $"{t[index].Latitude:F7}, {t[index].Longitude:F7}\n{t[index].SpeedKmh:0.0} km/h · {t[index].RtkName} · hAcc {t[index].AccuracyM:0.0} m";
        else StatPoint.Text = "Haz clic en la gráfica";
        EngineSelect(index);
    }
    private void UpdateComparison()
    {
        var selected = ComparePicker.SelectedItem as TrainingSession;
        CompareChart.Session = _active;
        CompareChart.Comparison = selected == _active ? null : selected;
        if (_active is null || selected is null) { CompareTable.ItemsSource = null; return; }
        CompareTable.ItemsSource = new[]
        {
            new { Metrica = "Caballo", Actual = _active.Horse, Comparativa = selected.Horse },
            new { Metrica = "Distancia", Actual = $"{_active.DistanceM / 1000:0.00} km", Comparativa = $"{selected.DistanceM / 1000:0.00} km" },
            new { Metrica = "Duración", Actual = Analytics.Duration(_active.DurationSeconds), Comparativa = Analytics.Duration(selected.DurationSeconds) },
            new { Metrica = "Velocidad media", Actual = $"{_active.MeanSpeedKmh:0.0} km/h", Comparativa = $"{selected.MeanSpeedKmh:0.0} km/h" },
            new { Metrica = "Velocidad máxima", Actual = $"{_active.MaxSpeedKmh:0.0} km/h", Comparativa = $"{selected.MaxSpeedKmh:0.0} km/h" },
            new { Metrica = "RTK FIX", Actual = $"{_active.FixPercent:0.0} %", Comparativa = $"{selected.FixPercent:0.0} %" }
        };
    }
    private async void MarineImport_Click(object sender, RoutedEventArgs e)
    {
        if (_active is null) { MessageBox.Show("Selecciona primero una sesión."); return; }
        var dlg = new OpenFileDialog { Filter = "Instantánea marina AVO (*.json)|*.json" };
        if (dlg.ShowDialog(this) != true) return;
        try
        {
            MarineMetadata.LoadJson(_active, dlg.FileName);
            string cache = MarineCacheFile(_active);
            Directory.CreateDirectory(Path.GetDirectoryName(cache)!);
            await File.WriteAllTextAsync(cache, await File.ReadAllTextAsync(dlg.FileName));
            UpdateViews();
            StatusLine.Text = "Metadatos marinos incorporados sin modificar telemetría original";
        }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "Contexto marino inválido", MessageBoxButton.OK, MessageBoxImage.Warning); }
    }
    private void ExportCsv_Click(object sender, RoutedEventArgs e) => ExportFile("CSV (*.csv)|*.csv", "csv", ExportService.ExportCsv);
    private void ExportGpx_Click(object sender, RoutedEventArgs e) => ExportFile("GPS Exchange Format (*.gpx)|*.gpx", "gpx", ExportService.ExportGpx);
    private void ExportHtml_Click(object sender, RoutedEventArgs e) => ExportFile("Informe HTML (*.html)|*.html", "html", ExportService.ExportHtml);
    private void ExportFile(string filter, string ext, Action<TrainingSession, string> export)
    {
        if (_active is null) { MessageBox.Show(this, "Importa un entrenamiento.", "Sin datos"); return; }
        var dlg = new SaveFileDialog { Filter = filter, FileName = $"AVO_{Sanitize(_active.SessionId)}.{ext}" };
        if (dlg.ShowDialog(this) != true) return;
        try { export(_active, dlg.FileName); StatusLine.Text = "Exportado: " + dlg.FileName; }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "Error al exportar", MessageBoxButton.OK, MessageBoxImage.Error); }
    }
    private static string Sanitize(string value) => string.Concat(value.Select(c => char.IsLetterOrDigit(c) || c is '-' or '_' ? c : '_'));
    private void OpenServer_Click(object sender, RoutedEventArgs e)
    {
        if (!Uri.TryCreate(ServerPanelUrl.Text, UriKind.Absolute, out var url) || url.Scheme != Uri.UriSchemeHttps)
        { MessageBox.Show("Introduce una URL HTTPS válida."); return; }
        try { Process.Start(new ProcessStartInfo(url.ToString()) { UseShellExecute = true }); }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "Navegador", MessageBoxButton.OK, MessageBoxImage.Error); }
    }
    private async void DownloadAvo_Click(object sender, RoutedEventArgs e)
    {
        if (!Uri.TryCreate(DownloadUrl.Text, UriKind.Absolute, out var url) || url.Scheme != Uri.UriSchemeHttps || !url.AbsolutePath.EndsWith(".avo", StringComparison.OrdinalIgnoreCase))
        { MessageBox.Show("Es necesario proporcionar un enlace HTTPS directo a un archivo .avo."); return; }
        string temp = Path.Combine(Path.GetTempPath(), "AVO_" + Guid.NewGuid().ToString("N") + ".avo");
        try
        {
            ServerStatus.Text = "Descargando paquete...";
            using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(90) };
            using var response = await client.GetAsync(url, HttpCompletionOption.ResponseHeadersRead);
            response.EnsureSuccessStatusCode();
            if (response.Content.Headers.ContentLength > 100L * 1024 * 1024) throw new InvalidDataException("Archivo excesivo");
            await using (var output = File.Create(temp))
            await using (var input = await response.Content.ReadAsStreamAsync())
            {
                var buffer = new byte[65536]; long total = 0;
                int count;
                while ((count = await input.ReadAsync(buffer)) > 0)
                {
                    total += count;
                    if (total > 100L * 1024 * 1024) throw new InvalidDataException("Descarga excede 100 MB");
                    await output.WriteAsync(buffer.AsMemory(0, count));
                }
            }
            var dir = Path.Combine(_prefsDir, "descargas"); Directory.CreateDirectory(dir);
            var dest = Path.Combine(dir, Guid.NewGuid().ToString("N") + ".avo");
            File.Move(temp, dest);
            try { await ImportManyAsync([dest]); ServerStatus.Text = "Paquete descargado y validado localmente; sincronización automática no configurada."; }
            catch { File.Delete(dest); throw; }
        }
        catch (Exception ex) { ServerStatus.Text = "Error descargando: " + ex.Message; }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }
}
