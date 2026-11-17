using System.Collections.ObjectModel;
using System.IO;
using System.Net.Http;
using System.Windows.Input;
using Avo.Windows.Controls;
using Avo.Windows.Core;

namespace Avo.Windows.ViewModels;

public sealed partial class MainViewModel
{
    private readonly EnvironmentService _environment;
    private TidePrediction? _tides;
    private WeatherModel? _weather;
    public TidePrediction? Tides { get => _tides; private set => Set(ref _tides, value); }
    public WeatherModel? Weather { get => _weather; private set => Set(ref _weather, value); }
    public ObservableCollection<TidePort> TidePorts { get; } = [];
    private TidePort? _port;
    public TidePort? SelectedPort
    {
        get => _port;
        set
        {
            if (!Set(ref _port, value) || value is null) return;
            Settings.TidePortId = value.Id;
            try { Settings.Save(Paths.SettingsFile); } catch (System.IO.IOException) { }
            _ = LoadEnvironmentAsync(true);
        }
    }
    private string _envStatus = "Sin datos de entorno";
    public string EnvironmentStatus { get => _envStatus; private set => Set(ref _envStatus, value); }
    private IReadOnlyList<ChartSeries> _tideSeries = [];
    public IReadOnlyList<ChartSeries> TideSeries { get => _tideSeries; private set => Set(ref _tideSeries, value); }
    private double _tideMarker = double.NaN, _tideMin = double.NaN, _tideMax = double.NaN;
    public double TideMarker { get => _tideMarker; private set => Set(ref _tideMarker, value); }
    public double TideXMin { get => _tideMin; set => Set(ref _tideMin, value); }
    public double TideXMax { get => _tideMax; set => Set(ref _tideMax, value); }
    public ObservableCollection<KeyValueRow> TideRows { get; } = [];
    public ObservableCollection<KeyValueRow> WeatherRows { get; } = [];
    public ObservableCollection<KeyValueRow> TideEvents { get; } = [];
    public string PlaceName => Settings.PlaceName;
    public string TideHeadline { get; private set; } = "Sin datos";
    public string TideTrend { get; private set; } = "No disponible";
    public string WindHeadline { get; private set; } = "Sin datos";
    public string TempHeadline { get; private set; } = "Sin datos";
    public string PressureHeadline { get; private set; } = "Sin datos";
    public string WaveHeadline { get; private set; } = "Sin datos";
    public bool OnlineEnvironment { get => Settings.OnlineEnvironment; set { Settings.OnlineEnvironment = value; Raise(); } }
    public ICommand LoadEnvironmentCommand { get; private set; } = null!;

    private void InitEnvironment()
    {
        LoadEnvironmentCommand = new AsyncCommand(_ => LoadEnvironmentAsync(true), Fail);
    }

    private string? _envLoadedFor;
    private int _envRequest;

    public async Task LoadEnvironmentAsync(bool force)
    {
        var s = Selected;
        if (s?.Start is not DateTimeOffset start) { EnvironmentStatus = "La sesión no tiene fecha: no se pueden asociar mareas ni meteorología."; ClearEnvironment(); return; }
        if (!force && _envLoadedFor == s.Id) return;
        _envLoadedFor = s.Id;
        int request = ++_envRequest;
        ClearEnvironment();
        if (!OnlineEnvironment) { EnvironmentStatus = "Consulta en línea desactivada: sin datos de entorno."; return; }
        EnvironmentStatus = "Consultando predicción de mareas (IHM) y modelo meteorológico (Open-Meteo)…";
        var errors = new List<string>();
        double lat = Settings.PlaceLatitude, lon = Settings.PlaceLongitude;
        if (s.Timeline.Count > 0) { lat = s.Timeline.Lat[0]; lon = s.Timeline.Lon[0]; }
        try
        {
            if (TidePorts.Count == 0)
            {
                var ports = await _environment.PortsAsync(CancellationToken.None);
                foreach (var p in ports.OrderBy(p => p.DistanceKmTo(lat, lon)).Take(12)) TidePorts.Add(p);
            }
            var port = TidePorts.FirstOrDefault(p => p.Id == Settings.TidePortId) ?? TidePorts.FirstOrDefault();
            if (port is not null)
            {
                _port = port; Raise(nameof(SelectedPort));
                Tides = await _environment.TidesAsync(port, start, lat, lon, CancellationToken.None);
            }
            else errors.Add("sin puertos de referencia");
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or System.Text.Json.JsonException or InvalidDataException or IOException)
        { errors.Add("mareas: " + ex.Message); Log.Warn("entorno", "IHM no disponible", ex); }
        try { Weather = await _environment.WeatherAsync(lat, lon, start, CancellationToken.None); }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or System.Text.Json.JsonException or InvalidDataException or IOException)
        { errors.Add("meteorología: " + ex.Message); Log.Warn("entorno", "Open-Meteo no disponible", ex); }
        if (Selected != s || request != _envRequest) return;   // a newer request owns the panels
        FillEnvironment(s, start);
        EnvironmentStatus = errors.Count == 0 ? "Datos de entorno cargados (con copia local para uso sin conexión)." : "Parcial — " + string.Join(" · ", errors);
    }

    private void ClearEnvironment()
    {
        Tides = null; Weather = null;
        TideRows.Clear(); WeatherRows.Clear(); TideEvents.Clear();
        TideSeries = []; TideMarker = double.NaN;
        TideHeadline = WindHeadline = TempHeadline = PressureHeadline = WaveHeadline = "Sin datos"; TideTrend = "No disponible";
        RaiseMany(nameof(TideHeadline), nameof(WindHeadline), nameof(TempHeadline), nameof(PressureHeadline), nameof(WaveHeadline), nameof(TideTrend));
    }

    private void FillEnvironment(SessionItem s, DateTimeOffset start)
    {
        var day0 = new DateTimeOffset(MadridTime.ToMadrid(start).Date, MadridTime.ToMadrid(start).Offset);
        if (Tides is TidePrediction tp)
        {
            var curve = tp.Curve(day0.ToUniversalTime(), day0.AddDays(1).ToUniversalTime(), TimeSpan.FromMinutes(10)).ToList();
            double ToX(DateTimeOffset u) => (MadridTime.ToMadrid(u) - day0).TotalSeconds;
            TideSeries = curve.Count > 1 ? new[] { new ChartSeries { Name = "Marea (predicción)", X = curve.Select(c => ToX(c.t)).ToArray(), Y = curve.Select(c => c.h).ToArray(), Color = Blue, Thickness = 2, Unit = "m", Format = "0.00" } } : Array.Empty<ChartSeries>();
            TideMarker = ToX(start); TideXMin = 0; TideXMax = 86400;
            double? h = tp.HeightAt(start);
            TideHeadline = Core.TimeText.Num(h, "0.00", " m");
            TideTrend = tp.TrendAt(start) is string tr ? (tr == "subiendo" ? "Subiendo" : "Bajando") : "No disponible";
            TideRows.Add(new("Fuente", tp.Source));
            TideRows.Add(new("Tipo de dato", "Predicción (no es una medición)"));
            TideRows.Add(new("Puerto de referencia", $"{tp.Port.Name} · {Core.TimeText.Num(tp.PortDistanceKm, "0.0", " km")}"));
            TideRows.Add(new("Altura al inicio", Core.TimeText.Num(h, "0.00", " m (cero hidrográfico)")));
            TideRows.Add(new("Altura al final", Core.TimeText.Num(tp.HeightAt(start.AddSeconds(s.Timeline.DurationS)), "0.00", " m")));
            TideRows.Add(new("Amplitud del semiciclo", Core.TimeText.Num(tp.RangeAt(start), "0.00", " m")));
            TideRows.Add(new("Coeficiente aproximado", Core.TimeText.Num(tp.CoefficientAt(start), "0")));
            foreach (var x in tp.Extremes.Where(x => x.Utc >= day0 && x.Utc < day0.AddDays(1)))
                TideEvents.Add(new(x.High ? "Pleamar" : "Bajamar", $"{MadridTime.Format(x.Utc, "HH:mm")} · {x.HeightM.ToString("0.00", Es)} m"));
        }
        if (Weather is WeatherModel wm && wm.At(start) is WeatherHour w)
        {
            WindHeadline = Core.TimeText.Num(w.WindKmh, "0", " km/h") + (w.WindDirDeg is double d ? " " + Compass(d) : "");
            TempHeadline = Core.TimeText.Num(w.TemperatureC, "0.0", " °C");
            PressureHeadline = Core.TimeText.Num(w.PressureHpa, "0", " hPa");
            WaveHeadline = Core.TimeText.Num(w.WaveHeightM, "0.0", " m");
            WeatherRows.Add(new("Fuente", wm.Source));
            WeatherRows.Add(new("Tipo de dato", "Modelo numérico (no es una medición en la playa)"));
            WeatherRows.Add(new("Hora del modelo", MadridTime.Format(w.Utc, "dd/MM HH:mm")));
            WeatherRows.Add(new("Viento / rachas", $"{Core.TimeText.Num(w.WindKmh, "0", " km/h")} / {Core.TimeText.Num(w.WindGustKmh, "0", " km/h")}"));
            WeatherRows.Add(new("Humedad relativa", Core.TimeText.Num(w.HumidityPct, "0", " %")));
            WeatherRows.Add(new("Oleaje (altura / periodo)", $"{Core.TimeText.Num(w.WaveHeightM, "0.0", " m")} / {Core.TimeText.Num(w.WavePeriodS, "0", " s")}"));
        }
        RaiseMany(nameof(TideHeadline), nameof(WindHeadline), nameof(TempHeadline), nameof(PressureHeadline), nameof(WaveHeadline), nameof(TideTrend));
    }

    private static string Compass(double deg)
    {
        string[] n = ["N", "NE", "E", "SE", "S", "SO", "O", "NO"];
        return n[(int)Math.Round(((deg % 360) + 360) % 360 / 45) % 8];
    }
}
