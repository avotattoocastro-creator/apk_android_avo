using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Avo.Windows.Core;

/// <summary>Origin of an environmental value. Predictions and models are never shown as measurements.</summary>
public enum DataKind { Prediccion, Modelo, Medicion }

public static class MadridTime
{
    private static readonly Lazy<TimeZoneInfo> Zone = new(() =>
    {
        foreach (var id in new[] { "Europe/Madrid", "Romance Standard Time" })
        {
            try { return TimeZoneInfo.FindSystemTimeZoneById(id); }
            catch (TimeZoneNotFoundException) { }
            catch (InvalidTimeZoneException) { }
        }
        return TimeZoneInfo.Utc;
    });

    public static TimeZoneInfo TimeZone => Zone.Value;
    public static DateTimeOffset ToMadrid(DateTimeOffset utc) => TimeZoneInfo.ConvertTime(utc, Zone.Value);
    public static string Format(DateTimeOffset? utc, string fmt = "dd/MM/yyyy HH:mm") =>
        utc is DateTimeOffset u ? ToMadrid(u).ToString(fmt, CultureInfo.GetCultureInfo("es-ES")) : "Sin fecha";
    /// <summary>Abbreviation of the offset in force at that instant (CET / CEST).</summary>
    public static string ZoneLabel(DateTimeOffset utc) => Zone.Value.IsDaylightSavingTime(utc) ? "CEST (UTC+2)" : "CET (UTC+1)";
}

/// <summary>Reference place of the usual training area. Coordinates are approximate and editable in the settings.</summary>
public sealed record TrainingPlace(string Name, double Latitude, double Longitude)
{
    public static TrainingPlace Regaton { get; } = new("Playa del Regatón, Laredo (Cantabria)", 43.4247, -3.4519);
}

public sealed record TideExtreme(DateTimeOffset Utc, double HeightM, bool High);

public sealed record TidePort(string Id, string Name, double Latitude, double Longitude)
{
    public double DistanceKmTo(double lat, double lon) => Geo.HaversineM(new TrackPoint(Latitude, Longitude, 0, 0, 0, 0), new TrackPoint(lat, lon, 0, 0, 0, 0)) / 1000;
}

/// <summary>Official tide prediction of one reference port (never a measurement at the beach).</summary>
public sealed class TidePrediction
{
    public required string Source { get; init; }
    public required TidePort Port { get; init; }
    public DataKind Kind => DataKind.Prediccion;
    public required IReadOnlyList<TideExtreme> Extremes { get; init; }
    public double? PortDistanceKm { get; init; }

    /// <summary>Height between two extremes with cosine interpolation h = a + (b − a)(1 − cos πf)/2 (same as Android Tides.kt).</summary>
    public double? HeightAt(DateTimeOffset utc)
    {
        for (int i = 1; i < Extremes.Count; i++)
        {
            var a = Extremes[i - 1]; var b = Extremes[i];
            if (utc < a.Utc || utc > b.Utc) continue;
            double span = (b.Utc - a.Utc).TotalSeconds;
            if (span <= 0 || span > 10 * 3600) return null;
            double f = (utc - a.Utc).TotalSeconds / span;
            return a.HeightM + (b.HeightM - a.HeightM) * (1 - Math.Cos(Math.PI * f)) / 2;
        }
        return null;
    }

    /// <summary>"subiendo" / "bajando" at an instant, or null outside the data.</summary>
    public string? TrendAt(DateTimeOffset utc)
    {
        for (int i = 1; i < Extremes.Count; i++)
            if (utc >= Extremes[i - 1].Utc && utc <= Extremes[i].Utc) return Extremes[i].High ? "subiendo" : "bajando";
        return null;
    }

    /// <summary>Range (m) of the half-cycle containing the instant.</summary>
    public double? RangeAt(DateTimeOffset utc)
    {
        for (int i = 1; i < Extremes.Count; i++)
            if (utc >= Extremes[i - 1].Utc && utc <= Extremes[i].Utc) return Math.Abs(Extremes[i].HeightM - Extremes[i - 1].HeightM);
        return null;
    }

    /// <summary>Tide coefficient approximation used by Android: 70 · range / mean range, clamped 20–120. Needs ≥ 3 days of data.</summary>
    public double? CoefficientAt(DateTimeOffset utc)
    {
        var r = RangeAt(utc);
        if (r is null || Extremes.Count < 12) return null;
        var ranges = new List<double>();
        for (int i = 1; i < Extremes.Count; i++) ranges.Add(Math.Abs(Extremes[i].HeightM - Extremes[i - 1].HeightM));
        double mean = ranges.Average();
        return mean > 0 ? Math.Clamp(70 * r.Value / mean, 20, 120) : null;
    }

    public IEnumerable<(DateTimeOffset t, double h)> Curve(DateTimeOffset from, DateTimeOffset to, TimeSpan step)
    {
        for (var t = from; t <= to; t += step)
            if (HeightAt(t) is double h) yield return (t, h);
    }
}

/// <summary>Parser and client of the Instituto Hidrográfico de la Marina API (the same public source used by Android).</summary>
public static class IhmTides
{
    public const string Api = "https://ideihm.covam.es/api-ihm/getmarea";
    public const string SourceName = "Instituto Hidrográfico de la Marina (predicción oficial)";

    /// <summary>getlist: estaciones.puertos[] {id, puerto, lat, lon} (numbers may come as text).</summary>
    public static List<TidePort> ParsePorts(string json)
    {
        using var d = JsonDocument.Parse(json);
        var list = new List<TidePort>();
        if (!d.RootElement.TryGetProperty("estaciones", out var e) || !e.TryGetProperty("puertos", out var arr) || arr.ValueKind != JsonValueKind.Array) return list;
        foreach (var p in arr.EnumerateArray())
        {
            if (Dbl(p, "lat") is double lat && Dbl(p, "lon") is double lon)
                list.Add(new TidePort(Text(p, "id"), Text(p, "puerto"), lat, lon));
        }
        return list;
    }

    /// <summary>gettide (month): mareas.datos.marea[] {fecha "yyyy-MM-dd", hora "HH:mm" UTC, altura (m, decimal comma allowed), tipo}.</summary>
    public static List<TideExtreme> ParseMonth(string json)
    {
        using var d = JsonDocument.Parse(json);
        var list = new List<TideExtreme>();
        if (!d.RootElement.TryGetProperty("mareas", out var m) || !m.TryGetProperty("datos", out var datos) || !datos.TryGetProperty("marea", out var raw)) return list;
        var items = new List<JsonElement>();
        if (raw.ValueKind == JsonValueKind.Array) items.AddRange(raw.EnumerateArray());
        else if (raw.ValueKind == JsonValueKind.Object) items.Add(raw);
        foreach (var x in items)
        {
            string fecha = Text(x, "fecha"), hora = Text(x, "hora").PadLeft(5, '0');
            if (!DateTime.TryParseExact($"{fecha}T{hora}", "yyyy-MM-dd'T'HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal, out var t)) continue;
            if (!double.TryParse(Text(x, "altura").Replace(',', '.'), NumberStyles.Float, CultureInfo.InvariantCulture, out var h)) continue;
            list.Add(new TideExtreme(new DateTimeOffset(DateTime.SpecifyKind(t, DateTimeKind.Utc)), h, Text(x, "tipo").StartsWith("plea", StringComparison.OrdinalIgnoreCase)));
        }
        return list.OrderBy(x => x.Utc).ToList();
    }

    private static string Text(JsonElement e, string k) => e.TryGetProperty(k, out var v) ? v.ValueKind switch
    {
        JsonValueKind.String => v.GetString() ?? "",
        JsonValueKind.Number => v.GetRawText(),
        _ => "",
    } : "";
    private static double? Dbl(JsonElement e, string k) =>
        double.TryParse(Text(e, k).Replace(',', '.'), NumberStyles.Float, CultureInfo.InvariantCulture, out var v) && double.IsFinite(v) ? v : null;
}

/// <summary>Hourly weather / sea state of a numerical model (Open-Meteo archive and marine APIs) — a MODEL, not a measurement.</summary>
public sealed record WeatherHour(DateTimeOffset Utc, double? TemperatureC, double? WindKmh, double? WindGustKmh, double? WindDirDeg,
    double? PressureHpa, double? HumidityPct, double? WaveHeightM, double? WavePeriodS);

public sealed class WeatherModel
{
    public required string Source { get; init; }
    public DataKind Kind => DataKind.Modelo;
    public required double Latitude { get; init; }
    public required double Longitude { get; init; }
    public required IReadOnlyList<WeatherHour> Hours { get; init; }

    public WeatherHour? At(DateTimeOffset utc) =>
        Hours.Where(h => Math.Abs((h.Utc - utc).TotalMinutes) <= 45).OrderBy(h => Math.Abs((h.Utc - utc).TotalMinutes)).FirstOrDefault();

    /// <summary>Parses Open-Meteo "hourly" objects (time in GMT, ISO without zone).</summary>
    public static List<WeatherHour> ParseHourly(string? weatherJson, string? marineJson)
    {
        var map = new SortedDictionary<DateTimeOffset, WeatherHour>();
        if (weatherJson is not null)
        {
            using var d = JsonDocument.Parse(weatherJson);
            if (d.RootElement.TryGetProperty("hourly", out var h) && h.TryGetProperty("time", out var times))
            {
                int i = 0;
                foreach (var tt in times.EnumerateArray())
                {
                    if (Time(tt.GetString()) is DateTimeOffset t)
                        map[t] = new WeatherHour(t, N(h, "temperature_2m", i), N(h, "wind_speed_10m", i), N(h, "wind_gusts_10m", i), N(h, "wind_direction_10m", i),
                            N(h, "pressure_msl", i), N(h, "relative_humidity_2m", i), null, null);
                    i++;
                }
            }
        }
        if (marineJson is not null)
        {
            using var d = JsonDocument.Parse(marineJson);
            if (d.RootElement.TryGetProperty("hourly", out var h) && h.TryGetProperty("time", out var times))
            {
                int i = 0;
                foreach (var tt in times.EnumerateArray())
                {
                    if (Time(tt.GetString()) is DateTimeOffset t)
                    {
                        var baseHour = map.TryGetValue(t, out var w) ? w : new WeatherHour(t, null, null, null, null, null, null, null, null);
                        map[t] = baseHour with { WaveHeightM = N(h, "wave_height", i), WavePeriodS = N(h, "wave_period", i) };
                    }
                    i++;
                }
            }
        }
        return map.Values.ToList();
    }

    private static DateTimeOffset? Time(string? s) =>
        s is not null && DateTime.TryParseExact(s, "yyyy-MM-dd'T'HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal, out var t)
            ? new DateTimeOffset(DateTime.SpecifyKind(t, DateTimeKind.Utc)) : null;

    private static double? N(JsonElement hourly, string key, int i)
    {
        if (!hourly.TryGetProperty(key, out var arr) || arr.ValueKind != JsonValueKind.Array || i >= arr.GetArrayLength()) return null;
        var v = arr[i];
        return v.ValueKind == JsonValueKind.Number && v.TryGetDouble(out var d) && double.IsFinite(d) ? d : null;
    }
}

/// <summary>Cached HTTPS access to the public environment sources. Every response is cached on disk; offline use reads the
/// cache. Failures are reported, never replaced with invented values.</summary>
public sealed class EnvironmentService
{
    private readonly string _cacheDir;
    private readonly HttpClient _http;

    public EnvironmentService(string cacheDir, HttpClient? http = null)
    {
        _cacheDir = cacheDir;
        _http = http ?? new HttpClient { Timeout = TimeSpan.FromSeconds(25) };
        if (http is null) _http.DefaultRequestHeaders.UserAgent.ParseAdd("AVO-Performance-Horse-Windows/2.0");
    }

    private async Task<string> CachedAsync(string url, TimeSpan maxAge, CancellationToken ct)
    {
        Directory.CreateDirectory(_cacheDir);
        string file = Path.Combine(_cacheDir, Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(url)))[..32] + ".json");
        if (File.Exists(file) && DateTime.UtcNow - File.GetLastWriteTimeUtc(file) < maxAge)
        {
            try { return await File.ReadAllTextAsync(file, ct); }
            catch (IOException) { /* being replaced by a concurrent request: fetch again */ }
        }
        try
        {
            using var r = await _http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, ct);
            r.EnsureSuccessStatusCode();
            if (r.Content.Headers.ContentLength > 8_000_000) throw new InvalidDataException("Respuesta demasiado grande");
            string text = await r.Content.ReadAsStringAsync(ct);
            if (text.Length > 8_000_000) throw new InvalidDataException("Respuesta demasiado grande");
            using (JsonDocument.Parse(text)) { }
            string tmp = file + "." + Guid.NewGuid().ToString("N") + ".tmp";
            await File.WriteAllTextAsync(tmp, text, ct);
            try { File.Move(tmp, file, true); }
            catch (IOException) { File.Delete(tmp); }   // a concurrent request already stored the same response
            return text;
        }
        catch (Exception) when (File.Exists(file))
        {
            return await File.ReadAllTextAsync(file, ct);   // stale cache is better than nothing; the age is shown by the caller
        }
    }

    public async Task<List<TidePort>> PortsAsync(CancellationToken ct) =>
        IhmTides.ParsePorts(await CachedAsync($"{IhmTides.Api}?request=getlist&format=json", TimeSpan.FromDays(7), ct));

    public async Task<TidePrediction> TidesAsync(TidePort port, DateTimeOffset aroundUtc, double placeLat, double placeLon, CancellationToken ct)
    {
        var months = new[] { aroundUtc.AddDays(-20), aroundUtc, aroundUtc.AddDays(20) }.Select(d => d.ToString("yyyyMM", CultureInfo.InvariantCulture)).Distinct();
        var all = new List<TideExtreme>();
        foreach (var m in months)
        {
            try { all.AddRange(IhmTides.ParseMonth(await CachedAsync($"{IhmTides.Api}?request=gettide&id={Uri.EscapeDataString(port.Id)}&month={m}&format=json", TimeSpan.FromDays(30), ct))); }
            catch (Exception ex) when (ex is HttpRequestException or InvalidDataException or JsonException) { if (m == aroundUtc.ToString("yyyyMM", CultureInfo.InvariantCulture)) throw; }
        }
        return new TidePrediction
        {
            Source = IhmTides.SourceName, Port = port, Extremes = all.DistinctBy(x => x.Utc).OrderBy(x => x.Utc).ToList(),
            PortDistanceKm = port.DistanceKmTo(placeLat, placeLon),
        };
    }

    public async Task<WeatherModel> WeatherAsync(double lat, double lon, DateTimeOffset utc, CancellationToken ct)
    {
        string day = utc.UtcDateTime.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        string la = lat.ToString("0.0000", CultureInfo.InvariantCulture), lo = lon.ToString("0.0000", CultureInfo.InvariantCulture);
        bool recent = DateTimeOffset.UtcNow - utc < TimeSpan.FromDays(5);
        string vars = "temperature_2m,wind_speed_10m,wind_gusts_10m,wind_direction_10m,pressure_msl,relative_humidity_2m";
        string wurl = recent
            ? $"https://api.open-meteo.com/v1/forecast?latitude={la}&longitude={lo}&hourly={vars}&past_days=5&forecast_days=1&timezone=GMT"
            : $"https://archive-api.open-meteo.com/v1/archive?latitude={la}&longitude={lo}&start_date={day}&end_date={day}&hourly={vars}&timezone=GMT";
        string murl = $"https://marine-api.open-meteo.com/v1/marine?latitude={la}&longitude={lo}&hourly=wave_height,wave_period&start_date={day}&end_date={day}&timezone=GMT";
        string? w = null, m = null;
        try { w = await CachedAsync(wurl, recent ? TimeSpan.FromHours(1) : TimeSpan.FromDays(30), ct); } catch (Exception ex) when (ex is HttpRequestException or InvalidDataException or JsonException or TaskCanceledException) { }
        try { m = await CachedAsync(murl, recent ? TimeSpan.FromHours(1) : TimeSpan.FromDays(30), ct); } catch (Exception ex) when (ex is HttpRequestException or InvalidDataException or JsonException or TaskCanceledException) { }
        if (w is null && m is null) throw new HttpRequestException("Open-Meteo no disponible y sin copia local");
        return new WeatherModel { Source = "Open-Meteo (modelo meteorológico y de oleaje)", Latitude = lat, Longitude = lon, Hours = WeatherModel.ParseHourly(w, m) };
    }
}
