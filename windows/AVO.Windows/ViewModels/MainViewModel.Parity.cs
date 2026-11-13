using System.Collections.ObjectModel;
using System.Windows.Input;
using Avo.Windows.Core;

namespace Avo.Windows.ViewModels;

/// <summary>Horse shown or hidden in «Calendario».</summary>
public sealed class CalendarHorseFilter : ObservableObject
{
    private readonly Action _changed;
    private bool _shown;
    public CalendarHorseFilter(string name, bool shown, Action changed) { Name = name; _shown = shown; _changed = changed; }
    public string Name { get; }
    public bool Shown { get => _shown; set { if (Set(ref _shown, value)) _changed(); } }
}

/// <summary>
/// «Calendario» y «Datos clave» — paridad iPad ↔ PC (docs/PARIDAD_IPAD_PC.md). Las cifras salen de
/// Core/Analysis/KeyData.cs, con las mismas reglas que el iPad (ipad/AVOiPad/Core/KeyData.swift).
/// </summary>
public sealed partial class MainViewModel
{
    // ------------------------------------------------------------------ shell (boceto del entrenador 13/11/2026)
    /// <summary>Pages of ONE training (same list as iPad Page.isTrainingPage): only these show the top bar; the general pages
    /// (Entrenamientos, Calendario, Cuadra, Jinetes, Geocercas, Servidor…) have none.</summary>
    public bool IsTrainingPage => Page is "Analysis" or "Map" or "Summary" or "Gps" or "Charts" or "TrackWork" or "Assistant" or "Segments"
        or "Biomech" or "Compare" or "Tides" or "Reports" or "Engine" or "KeyData";

    // ------------------------------------------------------------------ dashboard (same rules as iPad HomeView)
    public DashboardSummary Dashboard => DashboardSummary.From(CalendarEntries(), DateTimeOffset.UtcNow);
    public int HorseCount => HorseNames.Count;
    public int RiderCount => RiderNames.Count;
    private ICommand? _openDash;
    /// <summary>Opens one of the latest trainings in «Datos clave».</summary>
    public ICommand OpenDashCardCommand => _openDash ??= new RelayCommand(p =>
    {
        if (p is DashCard c && Sessions.FirstOrDefault(s => s.Id == c.Id) is SessionItem s) { Selected = s; Page = "KeyData"; }
    });
    public void RefreshDashboard() => RaiseMany(nameof(Dashboard), nameof(HorseCount), nameof(RiderCount));

    // ------------------------------------------------------------------ calendar
    private int _calYear = MadridTime.ToMadrid(DateTimeOffset.UtcNow).Year;
    private int _calMonth = MadridTime.ToMadrid(DateTimeOffset.UtcNow).Month;
    private bool _calYearView;
    private bool _calJumped;
    private readonly HashSet<string> _calHidden = new(StringComparer.CurrentCulture);

    public string[] CalendarWeekdays => TrainingCalendar.Weekdays;
    public bool CalendarYearView { get => _calYearView; set { if (Set(ref _calYearView, value)) RefreshCalendar(); } }
    public string CalendarTitle => _calYearView ? _calYear.ToString(KeyData.Es)
        : $"{char.ToUpper(TrainingCalendar.MonthNames[_calMonth - 1][0])}{TrainingCalendar.MonthNames[_calMonth - 1][1..]} {_calYear}";
    public string CalendarCountLabel => _calYearView ? "SESIONES DEL AÑO" : "SESIONES DEL MES";
    public List<CalendarDay> CalendarDays { get; private set; } = [];
    public List<CalendarMonthCell> CalendarYearCells { get; private set; } = [];
    public CalendarSummary CalendarSummary { get; private set; } = new(0, 0, 0, 0, 0);
    public ObservableCollection<CalendarHorseFilter> CalendarHorses { get; } = [];
    public bool CalendarHasHorses => CalendarHorses.Count > 0;

    private ICommand? _calPrev, _calNext, _calMonthView, _calYearViewCmd, _calOpen, _calOpenMonth;
    public ICommand CalendarPrevCommand => _calPrev ??= new RelayCommand(() => CalendarStep(-1));
    public ICommand CalendarNextCommand => _calNext ??= new RelayCommand(() => CalendarStep(1));
    public ICommand CalendarMonthViewCommand => _calMonthView ??= new RelayCommand(() => CalendarYearView = false);
    public ICommand CalendarYearViewCommand => _calYearViewCmd ??= new RelayCommand(() => CalendarYearView = true);
    public ICommand OpenCalendarEntryCommand => _calOpen ??= new RelayCommand(p =>
    {
        if (p is CalendarEntry e && Sessions.FirstOrDefault(s => s.Id == e.Id) is SessionItem s) { Selected = s; Page = "KeyData"; }
    });
    public ICommand OpenCalendarMonthCommand => _calOpenMonth ??= new RelayCommand(p =>
    {
        if (p is int m) { _calMonth = m; _calYearView = false; Raise(nameof(CalendarYearView)); RefreshCalendar(); }
    });

    private void CalendarStep(int d)
    {
        if (_calYearView) _calYear += d;
        else
        {
            _calMonth += d;
            if (_calMonth < 1) { _calMonth = 12; _calYear--; }
            if (_calMonth > 12) { _calMonth = 1; _calYear++; }
        }
        RefreshCalendar();
    }

    private List<CalendarEntry> CalendarEntries() => Sessions
        .Where(s => s.Start is not null)
        .Select(s => new CalendarEntry(s.Id, s.Start!.Value, string.IsNullOrWhiteSpace(s.Horse) ? "Sin caballo" : s.Horse,
            s.Timeline.Count > 1 ? s.Timeline.DurationS : s.Session.DurationSeconds, s.DistanceKmValue,
            s.Engine is EquineAnalysis e ? KeyData.Cached(s.Id, e.RawJson).FixShare : null))
        .ToList();

    public void RefreshCalendar()
    {
        var all = CalendarEntries();
        if (!_calJumped && all.Count > 0)
        {
            // first visit: open the month of the most recent training
            var ym = TrainingCalendar.YearMonth(all.Max(e => e.Start));
            _calYear = ym.Year; _calMonth = ym.Month; _calJumped = true;
        }
        var names = all.Select(e => e.Horse).Distinct().OrderBy(n => n, StringComparer.CurrentCulture).ToList();
        if (!names.SequenceEqual(CalendarHorses.Select(h => h.Name)))
        {
            CalendarHorses.Clear();
            foreach (var n in names) CalendarHorses.Add(new CalendarHorseFilter(n, !_calHidden.Contains(n), () => OnCalendarHorseToggled(n)));
        }
        var visible = all.Where(e => !_calHidden.Contains(e.Horse)).ToList();
        CalendarDays = TrainingCalendar.MonthGrid(_calYear, _calMonth, visible, DateTimeOffset.UtcNow);
        CalendarYearCells = TrainingCalendar.YearCells(_calYear, visible);
        CalendarSummary = TrainingCalendar.Summary(TrainingCalendar.Entries(_calYear, _calYearView ? null : _calMonth, visible));
        RaiseMany(nameof(CalendarDays), nameof(CalendarYearCells), nameof(CalendarSummary), nameof(CalendarTitle),
            nameof(CalendarCountLabel), nameof(CalendarHasHorses));
    }

    private void OnCalendarHorseToggled(string name)
    {
        var f = CalendarHorses.FirstOrDefault(h => h.Name == name);
        if (f is null) return;
        if (f.Shown) _calHidden.Remove(name); else _calHidden.Add(name);
        RefreshCalendar();
    }

    // ------------------------------------------------------------------ key data
    public KeyData? SelectedKeyData => Selected?.Engine is EquineAnalysis e ? KeyData.Cached(Selected.Id, e.RawJson) : null;
    public bool HasKeyData => SelectedKeyData?.HasEngine == true;
    public string KeyDataTitle => Selected is SessionItem s ? $"{s.Horse} · {s.DateTimeText}" : "Elige un entrenamiento";
    public string KeyDataEmptyText => Selected is null ? "Elige un entrenamiento"
        : $"El motor AVO todavía no ha analizado este entrenamiento · {Selected.EngineState}";

    public void RefreshKeyData()
    {
        RaiseMany(nameof(SelectedKeyData), nameof(HasKeyData), nameof(KeyDataTitle), nameof(KeyDataEmptyText));
        RaiseKeyTiles();
        RefreshKeyNav();
    }

    // ------------------------------------------------------------------ open a tramo in «Gráficas» (same as iPad openInCharts)
    private ICommand? _openKeyWindow;
    /// <summary>Opens «Gráficas» with the tramo of a tile, an effort or a split selected and zoomed.</summary>
    public ICommand OpenKeyWindowCommand => _openKeyWindow ??= new RelayCommand(p =>
    {
        switch (p)
        {
            case KeyTileView { Tile: { T0: double a, T1: double b } }: OpenInCharts(a, b); break;
            case KeySplit sp: OpenInCharts(sp.T0, sp.T1); break;
            case KeyEffort ef: OpenInCharts(ef.T0, ef.T1); break;
        }
    });

    /// <summary>t0/t1 are engine times (timeline = engine − offset).</summary>
    public void OpenInCharts(double engineT0, double engineT1)
    {
        if (Selected is not SessionItem s || !double.IsFinite(engineT0) || !double.IsFinite(engineT1) || engineT1 <= engineT0) return;
        double off = s.EngineOffsetS, a = engineT0 - off, b = engineT1 - off, pad = Math.Max(5, (b - a) * 0.25);
        Page = "Charts";
        RangeStart = a; RangeEnd = b; CursorTime = a;
        ChartXMin = a - pad; ChartXMax = b + pad;
    }

    // ------------------------------------------------------------------ session navigator (same as iPad SessionNavigator)
    private string _navQuery = "";
    private bool _showKeyNav = true;
    public string KeyNavQuery { get => _navQuery; set { if (Set(ref _navQuery, value)) RefreshKeyNav(); } }
    public bool ShowKeyNav { get => _showKeyNav; set { if (Set(ref _showKeyNav, value)) Raise(nameof(KeyNavToggleText)); } }
    public string KeyNavToggleText => _showKeyNav ? "Ocultar sesiones" : "Sesiones";
    public List<NavGroupView> KeyNavGroups { get; private set; } = [];

    private ICommand? _toggleKeyNav, _openNav;
    public ICommand ToggleKeyNavCommand => _toggleKeyNav ??= new RelayCommand(() => ShowKeyNav = !ShowKeyNav);
    public ICommand OpenNavEntryCommand => _openNav ??= new RelayCommand(p =>
    {
        if (p is NavItemView n && Sessions.FirstOrDefault(s => s.Id == n.Id) is SessionItem s) Selected = s;
    });

    private void RefreshKeyNav()
    {
        string? sel = Selected?.Id;
        KeyNavGroups = SessionNavigator.Groups(CalendarEntries(), _navQuery)
            .Select(g => new NavGroupView(g.Title, g.Entries.Select(e => new NavItemView(e.Id, SessionNavigator.ItemText(e), e.Id == sel)).ToList()))
            .ToList();
        Raise(nameof(KeyNavGroups));
    }
}

public sealed record NavItemView(string Id, string Text, bool IsSelected);
public sealed record NavGroupView(string Title, IReadOnlyList<NavItemView> Items);

/// <summary>Tile of «Datos clave» with its icon (Segoe MDL2 Assets) and colour; the figures come from Core KeyData.</summary>
public sealed record KeyTileView(KeyTile Tile)
{
    public string Label => Tile.Label;
    public string Value => Tile.Value;
    public string Unit => Tile.Unit;
    public string Caption => Tile.Caption;
    public bool Available => Tile.Available;
    public bool HasWindow => Tile.HasWindow;
    public string Glyph => Tile.Id switch
    {
        "vmax" => "\uEC4A", "best200" or "best600" or "best1000" => "\uE916", "distance" => "\uE707", "duration" => "\uE121",
        "hrmax" or "hrend" or "rec2" or "rec15" => "\uEB51", "lmax" or "lref1" or "lref2" => "\uED5E", "fmax" or "fref1" or "fref2" => "\uE895",
        _ => "\uE9D9",
    };
    public string Accent => Tile.Group switch { 1 => "#FF495A", 2 => "#C9CBD1", _ => "#3D9BFF" };
    public string ValueColor => Tile.Available ? "#F2F2F4" : "#93949B";
    public string CaptionColor => Tile.Available ? "#9C9DA4" : "#FFC42C";
}

public sealed partial class MainViewModel
{
    public List<KeyTileView> KeySpeedTiles => SelectedKeyData?.SpeedTiles.Select(t => new KeyTileView(t)).ToList() ?? [];
    public List<KeyTileView> KeyHeartTiles => SelectedKeyData?.HeartTiles.Select(t => new KeyTileView(t)).ToList() ?? [];
    public List<KeyTileView> KeyStrideTiles => SelectedKeyData?.StrideTiles.Select(t => new KeyTileView(t)).ToList() ?? [];
    private void RaiseKeyTiles() => RaiseMany(nameof(KeySpeedTiles), nameof(KeyHeartTiles), nameof(KeyStrideTiles));
}
