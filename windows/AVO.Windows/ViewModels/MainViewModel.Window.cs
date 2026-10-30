using System.IO;
using System.Text.Json;
using System.Windows.Input;
using Avo.Windows.Core;

namespace Avo.Windows.ViewModels;

// Start and end of the useful training inside the whole recording. Stored per session in recortes.json (never in the
// original file); every view, statistic, comparison and report then uses that part only, with the same time base.
public sealed partial class MainViewModel
{
    private sealed record WindowEntry(double Start, double End);
    private Dictionary<string, WindowEntry> _windows = new(StringComparer.Ordinal);
    private string WindowsFile => Path.Combine(Paths.Root, "recortes.json");

    public ICommand WindowStartCommand { get; private set; } = null!;
    public ICommand WindowEndCommand { get; private set; } = null!;
    public ICommand WindowFromRangeCommand { get; private set; } = null!;
    public ICommand WindowResetCommand { get; private set; } = null!;
    public string WindowText => Selected?.WindowText ?? "—";
    public bool IsTrimmed => Selected?.IsTrimmed == true;
    public double TimelineStart => Selected is { Timeline.Count: > 1 } s ? s.Timeline.T[0] : 0;

    private void InitWindows()
    {
        try
        {
            if (File.Exists(WindowsFile))
                _windows = JsonSerializer.Deserialize<Dictionary<string, WindowEntry>>(File.ReadAllText(WindowsFile)) ?? _windows;
        }
        catch (Exception ex) when (ex is IOException or JsonException) { Log.Warn("recortes", ex.Message, ex); }
        WindowStartCommand = new RelayCommand(() =>
        {
            var s = Selected!;
            double end = s.WindowEnd ?? s.FullTimeline.T[^1];
            SetWindow(s, CursorTime, end);
        }, () => Selected is { FullTimeline.Count: > 1 } && double.IsFinite(CursorTime));
        WindowEndCommand = new RelayCommand(() =>
        {
            var s = Selected!;
            double start = s.WindowStart ?? s.FullTimeline.T[0];
            SetWindow(s, start, CursorTime);
        }, () => Selected is { FullTimeline.Count: > 1 } && double.IsFinite(CursorTime));
        WindowFromRangeCommand = new RelayCommand(() => SetWindow(Selected!, Math.Min(RangeStart, RangeEnd), Math.Max(RangeStart, RangeEnd)),
            () => Selected is not null && HasRange);
        WindowResetCommand = new RelayCommand(() => SetWindow(Selected!, null, null), () => Selected?.IsTrimmed == true);
    }

    private void RestoreWindow(SessionItem item)
    {
        if (_windows.TryGetValue(item.Id, out var w))
            item.ApplyWindow(w.Start, w.End, new SpeedSmoother.Parameters(JerkDensity: Settings.JerkDensity));
    }

    private void SetWindow(SessionItem s, double? start, double? end)
    {
        if (start is double a && end is double b && b - a < 5)
        {
            Status = "El fin debe quedar al menos 5 s después del inicio: mueve el cursor y vuelve a marcar.";
            return;
        }
        s.ApplyWindow(start, end, new SpeedSmoother.Parameters(JerkDensity: Settings.JerkDensity));
        if (s.IsTrimmed) _windows[s.Id] = new WindowEntry(s.WindowStart!.Value, s.WindowEnd!.Value); else _windows.Remove(s.Id);
        try { File.WriteAllText(WindowsFile, JsonSerializer.Serialize(_windows)); }
        catch (IOException ex) { Log.Warn("recortes", ex.Message, ex); }
        Status = s.IsTrimmed ? s.WindowText + " (el archivo original no se modifica)" : "Se analiza el archivo completo";
        if (s == Selected)
        {
            RangeStart = double.NaN; RangeEnd = double.NaN; ChartXMin = double.NaN; ChartXMax = double.NaN;
            if (double.IsFinite(CursorTime) && s.Timeline.Count > 1) CursorTime = Math.Clamp(CursorTime, s.Timeline.T[0], s.Timeline.T[^1]);
            OnSelectedChanged();
            _envLoadedFor = null;
        }
        RefreshHome();
        if (Page == "Compare") RefreshCompare();
        RaiseMany(nameof(WindowText), nameof(IsTrimmed), nameof(TimelineStart));
    }
}
