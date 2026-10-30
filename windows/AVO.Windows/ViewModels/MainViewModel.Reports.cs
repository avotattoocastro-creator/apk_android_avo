using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Text;
using System.Windows.Input;
using Avo.Windows.Core;

namespace Avo.Windows.ViewModels;

public sealed record LibraryRow(string Date, string Horse, string Rider, string Place, string Kind, string State, string Sha);

public sealed partial class MainViewModel
{
    // ------------------------------------------------------------------ reports
    private bool _rGeneral = true, _rHorse = true, _rDate = true, _rMap = true, _rGnss = true, _rSpeed = true, _rCharts = true, _rSegments = true, _rBio = true, _rCompare, _rTides = true, _rNotes = true;
    public bool ReportGeneral { get => _rGeneral; set => Set(ref _rGeneral, value); }
    public bool ReportHorseRider { get => _rHorse; set => Set(ref _rHorse, value); }
    public bool ReportDate { get => _rDate; set => Set(ref _rDate, value); }
    public bool ReportMap { get => _rMap; set => Set(ref _rMap, value); }
    public bool ReportGnss { get => _rGnss; set => Set(ref _rGnss, value); }
    public bool ReportSpeed { get => _rSpeed; set => Set(ref _rSpeed, value); }
    public bool ReportCharts { get => _rCharts; set => Set(ref _rCharts, value); }
    public bool ReportSegments { get => _rSegments; set => Set(ref _rSegments, value); }
    public bool ReportBiomech { get => _rBio; set => Set(ref _rBio, value); }
    public bool ReportCompare { get => _rCompare; set => Set(ref _rCompare, value); }
    public bool ReportTides { get => _rTides; set => Set(ref _rTides, value); }
    public bool ReportNotes { get => _rNotes; set => Set(ref _rNotes, value); }
    public string SessionNotes
    {
        get => Selected?.Notes ?? "";
        set
        {
            if (Selected is null) return;
            Selected.Notes = value;
            Raise();
            try
            {
                Directory.CreateDirectory(Paths.Notes);
                File.WriteAllText(NotesPath(Selected), value, new UTF8Encoding(false));
            }
            catch (IOException ex) { Log.Warn("notas", ex.Message, ex); }
        }
    }
    private string NotesPath(SessionItem s) => Path.Combine(Paths.Notes, Path.GetFileNameWithoutExtension(_segmentStore.PathFor(s.Id)) + ".txt");

    public ObservableCollection<KeyValueRow> ReportPreviewRows { get; } = [];
    public string ReportPreviewTitle => Selected is null ? "Informe de entrenamiento" : $"Informe de entrenamiento · {Selected.DateText}";
    private string _lastExport = "";
    public string LastExport { get => _lastExport; private set => Set(ref _lastExport, value); }

    public ICommand ExportPdfCommand { get; private set; } = null!;
    public ICommand ExportHtmlCommand { get; private set; } = null!;
    public ICommand ExportCsvCommand { get; private set; } = null!;
    public ICommand ExportGpxCommand { get; private set; } = null!;
    public ICommand ExportJsonCommand { get; private set; } = null!;
    public ICommand OpenLastExportCommand { get; private set; } = null!;

    private void InitReports()
    {
        ExportPdfCommand = new AsyncCommand(_ => ExportAsync("PDF (*.pdf)|*.pdf", "pdf", (d, p) => { using var f = File.Create(p); ReportBuilder.WritePdf(d, f); }), Fail);
        ExportHtmlCommand = new AsyncCommand(_ => ExportAsync("HTML imprimible (*.html)|*.html", "html", (d, p) => File.WriteAllText(p, ReportBuilder.Html(d), new UTF8Encoding(false))), Fail);
        ExportCsvCommand = new AsyncCommand(_ => ExportAsync("CSV (*.csv)|*.csv", "csv", (d, p) => AnalysisExport.TimelineCsv(d.Timeline, p, RangeOr(d, true), RangeOr(d, false))), Fail);
        ExportGpxCommand = new AsyncCommand(_ => ExportAsync("GPX (*.gpx)|*.gpx", "gpx", (d, p) => AnalysisExport.Gpx(d.Session, d.Timeline, p, RangeOr(d, true), RangeOr(d, false))), Fail);
        ExportJsonCommand = new AsyncCommand(_ => ExportAsync("JSON (*.json)|*.json", "json", (d, p) => File.WriteAllText(p, AnalysisExport.Json(d.Session, d.Timeline, d.Segments, d.Engine, true), new UTF8Encoding(false))), Fail);
        OpenLastExportCommand = new RelayCommand(() =>
        {
            if (File.Exists(LastExport)) Process.Start(new ProcessStartInfo(LastExport) { UseShellExecute = true });
        }, () => File.Exists(LastExport));
    }

    private double RangeOr(ReportData d, bool start) =>
        HasRange ? (start ? Math.Min(RangeStart, RangeEnd) : Math.Max(RangeStart, RangeEnd)) : (start ? double.NegativeInfinity : double.PositiveInfinity);

    public ReportSections SelectedSections()
    {
        var r = ReportSections.None;
        if (ReportGeneral) r |= ReportSections.General;
        if (ReportHorseRider) r |= ReportSections.HorseRider;
        if (ReportDate) r |= ReportSections.DateDuration;
        if (ReportMap) r |= ReportSections.Map;
        if (ReportGnss) r |= ReportSections.GnssStats;
        if (ReportSpeed) r |= ReportSections.SpeedAccel;
        if (ReportCharts) r |= ReportSections.Charts;
        if (ReportSegments) r |= ReportSections.Segments;
        if (ReportBiomech) r |= ReportSections.Biomechanics;
        if (ReportCompare) r |= ReportSections.Comparison;
        if (ReportTides) r |= ReportSections.Tides;
        if (ReportNotes) r |= ReportSections.Notes;
        return r;
    }

    public ReportData? BuildReportData()
    {
        var s = Selected;
        if (s is null) return null;
        return new ReportData
        {
            Session = s.Session, Timeline = s.Timeline, Engine = s.Engine,
            Segments = s.SegmentDefs.OrderBy(d => d.T0).Select(d => SegmentAnalyzer.Compute(s.Timeline, d, s.Engine, s.EngineOffsetS)).ToList(),
            Comparison = ReportCompare ? Sessions.Where(x => x.IsCompared).Select(x => SeriesAligner.Summarize($"{x.Horse} · {x.DateText}", x.Timeline, x.Engine, x.EngineOffsetS)).ToList() : [],
            Tides = _envLoadedFor == s.Id ? Tides : null, Weather = _envLoadedFor == s.Id ? Weather : null,
            Notes = s.Notes, Sections = SelectedSections(),
        };
    }

    private async Task ExportAsync(string filter, string ext, Action<ReportData, string> write)
    {
        var data = BuildReportData();
        if (data is null) { Dialogs.Show("Exportar", "Selecciona un entrenamiento."); return; }
        string name = $"AVO_{string.Concat(data.Session.SessionId.Select(c => char.IsLetterOrDigit(c) || c is '-' or '_' ? c : '_'))}.{ext}";
        var path = Dialogs.SaveFile(filter, name);
        if (path is null) return;
        await ExportToAsync(data, path, write);
    }

    public async Task ExportToAsync(ReportData data, string path, Action<ReportData, string> write)
    {
        Busy = true;
        try
        {
            string tmp = path + ".tmp";
            await Task.Run(() => write(data, tmp));
            File.Move(tmp, path, true);
            LastExport = path;
            Status = "Exportado: " + path;
            Log.Info("exportar", "Exportado", new { archivo = Path.GetFileName(path) });
        }
        finally { Busy = false; }
    }

    public Task ExportPdfToAsync(string path) => BuildReportData() is ReportData d ? ExportToAsync(d, path, (x, p) => { using var f = File.Create(p); ReportBuilder.WritePdf(x, f); }) : Task.CompletedTask;

    private void RefreshReportPreview()
    {
        ReportPreviewRows.Clear();
        var s = Selected;
        Raise(nameof(ReportPreviewTitle)); Raise(nameof(SessionNotes));
        if (s is null) return;
        ReportPreviewRows.Add(new("Caballo", s.Horse));
        ReportPreviewRows.Add(new("Jinete", s.Rider));
        ReportPreviewRows.Add(new("Disciplina", s.Discipline));
        ReportPreviewRows.Add(new("Duración", s.DurationText));
        ReportPreviewRows.Add(new("Distancia", s.DistanceText));
        ReportPreviewRows.Add(new("Vel. máxima", s.MaxSpeedText));
        ReportPreviewRows.Add(new("RTK FIX", s.FixText));
    }

    // ------------------------------------------------------------------ server
    private IAvoServerClient _server = new PendingContractServerClient();
    public string ServerStatus => _server.StatusText;
    public string ServerStateText => _server.State switch
    {
        ServerState.Connected => "Conectado", ServerState.ContractPending => "No conectado · contrato de API pendiente",
        ServerState.Error => "Error", _ => "No configurado",
    };
    private string _panelUrl = "https://live.avoperformance.org";
    public string PanelUrl { get => _panelUrl; set => Set(ref _panelUrl, value); }
    private string _downloadUrl = "";
    public string DownloadUrl { get => _downloadUrl; set => Set(ref _downloadUrl, value); }
    private string _downloadState = "Sin descargas";
    public string DownloadState { get => _downloadState; private set => Set(ref _downloadState, value); }
    public ObservableCollection<LibraryRow> LibraryRows { get; } = [];
    public ICommand OpenPanelCommand { get; private set; } = null!;
    public ICommand DownloadCommand { get; private set; } = null!;
    public ICommand RefreshLibraryCommand { get; private set; } = null!;

    private void InitServer()
    {
        PanelUrl = Settings.ServerUrl;
        OpenPanelCommand = new RelayCommand(() =>
        {
            if (!Uri.TryCreate(PanelUrl, UriKind.Absolute, out var u) || u.Scheme != Uri.UriSchemeHttps) { Dialogs.Show("Servidor AVO", "Introduce una URL HTTPS válida.", true); return; }
            Process.Start(new ProcessStartInfo(u.ToString()) { UseShellExecute = true });
        });
        DownloadCommand = new AsyncCommand(async _ =>
        {
            if (!Uri.TryCreate(DownloadUrl.Trim(), UriKind.Absolute, out var u)) { DownloadState = "Enlace no válido"; return; }
            DownloadState = "Descargando…";
            var progress = new Progress<double>(p => DownloadState = $"Descargando… {p * 100:0} %");
            try
            {
                string file = await HttpsDownloader.DownloadAvoAsync(u, Path.Combine(Paths.Root, "descargas"), progress, CancellationToken.None);
                DownloadState = "Descargado; validando SHA-256 de segmentos y CRC…";
                await ImportFilesAsync([file]);
                DownloadState = "Descargado e importado: " + Path.GetFileName(file);
            }
            catch (Exception ex) when (ex is HttpRequestException or InvalidDataException or IOException or TaskCanceledException)
            {
                DownloadState = "Error: " + ex.Message;
                Log.Warn("servidor", "Descarga fallida", ex);
            }
            RefreshLibrary();
        }, Fail);
        RefreshLibraryCommand = new RelayCommand(RefreshLibrary);
    }

    public void RefreshLibrary()
    {
        LibraryRows.Clear();
        foreach (var s in Sessions.OrderByDescending(s => s.Start))
            LibraryRows.Add(new LibraryRow(s.DateText, s.Horse, s.Rider, s.Discipline, s.Kind, "Local · verificado", (s.Session.FileSha256 ?? "")[..Math.Min(12, (s.Session.FileSha256 ?? "").Length)]));
        Raise(nameof(ServerStatus)); Raise(nameof(ServerStateText));
    }
}
