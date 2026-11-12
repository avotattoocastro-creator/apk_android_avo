using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;

namespace Avo.Windows.Core;

/// <summary>
/// P/Invoke access to avo_equine.dll — the AVO Equine Intelligence Engine (same C++17 code as Android and Python).
/// Strings are UTF-8. Calls are blocking: run them with Task.Run. Cancellation sets a native flag polled by the engine.
/// </summary>
public static class EquineEngine
{
    private const string Dll = "avo_equine";

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] private static extern IntPtr avo_eq_version();
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] private static extern int avo_eq_api_version();
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] private static extern int avo_eq_analyse_ex(IntPtr[] paths, int n, IntPtr options, IntPtr cancel, out IntPtr json);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] private static extern int avo_eq_compare_ex(IntPtr[] a, int na, IntPtr[] b, int nb, IntPtr options, IntPtr cancel, out IntPtr json);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] private static extern int avo_eq_cache_invalidate(IntPtr dir);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] private static extern void avo_eq_free(IntPtr p);

    private static readonly Lazy<string?> LoadError = new(() =>
    {
        try { return avo_eq_api_version() >= 2 ? null : "versión de la API del motor no compatible"; }
        catch (Exception ex) when (ex is DllNotFoundException or EntryPointNotFoundException or BadImageFormatException) { return "motor no disponible (avo_equine.dll): " + ex.Message; }
    });

    public static bool Available => LoadError.Value is null;
    public static string? UnavailableReason => LoadError.Value;
    public static string Version() => Available ? Utf8(avo_eq_version()) : "no disponible";

    public static string AnalyseJson(IReadOnlyList<string> segments, string optionsJson, CancellationToken ct = default) =>
        Call(segments, null, optionsJson, ct);

    public static string CompareJson(IReadOnlyList<string> a, IReadOnlyList<string> b, string optionsJson, CancellationToken ct = default) =>
        Call(a, b, optionsJson, ct);

    public static int InvalidateCache(string dir)
    {
        if (!Available) return -1;
        IntPtr p = ToUtf8(dir);
        try { return avo_eq_cache_invalidate(p); } finally { Marshal.FreeHGlobal(p); }
    }

    private static string Call(IReadOnlyList<string> a, IReadOnlyList<string>? b, string options, CancellationToken ct)
    {
        if (!Available) throw new InvalidOperationException(UnavailableReason);
        var pa = a.Select(ToUtf8).ToArray();
        var pb = (b ?? []).Select(ToUtf8).ToArray();
        IntPtr opt = ToUtf8(options), cancel = Marshal.AllocHGlobal(4), json = IntPtr.Zero;
        Marshal.WriteInt32(cancel, 0);
        try
        {
            using (ct.Register(() => Marshal.WriteInt32(cancel, 1)))
            {
                int rc = b is null ? avo_eq_analyse_ex(pa, pa.Length, opt, cancel, out json) : avo_eq_compare_ex(pa, pa.Length, pb, pb.Length, opt, cancel, out json);
                string text = Utf8(json);
                if (rc == 4) throw new OperationCanceledException(ct);
                if (rc != 0) throw new InvalidDataException(ErrorOf(text));
                return text;
            }
        }
        finally
        {
            foreach (var p in pa) Marshal.FreeHGlobal(p);
            foreach (var p in pb) Marshal.FreeHGlobal(p);
            Marshal.FreeHGlobal(opt);
            if (json != IntPtr.Zero) avo_eq_free(json);
            Marshal.FreeHGlobal(cancel);   // the native call has returned: nobody reads the flag any more
        }
    }

    private static string ErrorOf(string json)
    {
        try { using var d = JsonDocument.Parse(json); return d.RootElement.TryGetProperty("error", out var e) ? e.GetString() ?? json : json; }
        catch (JsonException) { return json; }
    }

    private static IntPtr ToUtf8(string s)
    {
        byte[] b = Encoding.UTF8.GetBytes(s + "\0");
        IntPtr p = Marshal.AllocHGlobal(b.Length);
        Marshal.Copy(b, 0, p, b.Length);
        return p;
    }

    private static string Utf8(IntPtr p) => p == IntPtr.Zero ? "" : Marshal.PtrToStringUTF8(p) ?? "";

    /// <summary>Options JSON with proper escaping.</summary>
    public static string Options(bool series = true, string? cacheDir = null, bool force = false, string? extra = null)
    {
        var sb = new StringBuilder("{\"series\":").Append(series ? "true" : "false").Append(",\"forzar\":").Append(force ? "true" : "false");
        sb.Append(",\"procesado_utc\":").Append(JsonSerializer.Serialize(DateTimeOffset.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", CultureInfo.InvariantCulture)));
        if (cacheDir is not null) sb.Append(",\"cache_dir\":").Append(JsonSerializer.Serialize(cacheDir));
        if (!string.IsNullOrEmpty(extra)) sb.Append(',').Append(extra);
        return sb.Append('}').ToString();
    }
}

// ------------------------------------------------------------------ result model (format avo-equine-analysis v2)
public sealed record EngineQualityRow(string Dominio, string Nivel, string Motivos);
public sealed record EngineSegmentRow(int Id, string Aire, string Desde, string Hasta, string Distancia, string VelocidadMedia, string VelocidadMax,
    string Cadencia, string Tranco, string CorrCiclos, string CvIntervalos, string CalidadGnss, string CalidadImu, string Avisos)
{ public double T0 { get; init; } public double T1 { get; init; } }
public sealed record EngineGaitRow(string Aire, int Tramos, string Duracion, string FraccionTiempo, string Distancia, string VelocidadMedia, string Cadencia, string Tranco);
public sealed record EngineCurveRow(int Id, string Direccion, string Inicio, string Giro, string Radio, string VEntrada, string VSalida, string LateralEstimada, string Cadencia, string Calidad)
{ public double T0 { get; init; } }
public sealed record EngineEventRow(string Id, string Tipo, string Inicio, string Fin, string Calidad, string Motivo, string Algoritmo)
{ public double T0 { get; init; } }
public sealed record EngineDiffRow(string Metrica, string A, string B, string Diferencia, string Comparable, string Contexto);

public sealed class EquineAnalysis
{
    public string Engine { get; private set; } = "";
    public string SessionId { get; private set; } = "";
    public string? Cache { get; private set; }
    public string Mode { get; private set; } = "";
    public bool HasImu { get; private set; }
    public long? Itow0Ms { get; private set; }
    public List<string> Warnings { get; } = [];
    public Dictionary<string, double> Metrics { get; } = new(StringComparer.Ordinal);
    public List<EngineQualityRow> Quality { get; } = [];
    public List<EngineSegmentRow> Segments { get; } = [];
    public List<EngineGaitRow> PerGait { get; } = [];
    public List<EngineCurveRow> Curves { get; } = [];
    public List<EngineEventRow> Events { get; } = [];
    public string Classifier { get; private set; } = "";
    public string SymmetryLabel { get; private set; } = "";
    public bool SymmetryAllowed { get; private set; }
    public List<string> SymmetryControls { get; } = [];
    public string FusionSummary { get; private set; } = "";
    public double[] T { get; private set; } = [];
    public double[] Speed { get; private set; } = [];
    public double[] Accel { get; private set; } = [];
    public double[] LatAccel { get; private set; } = [];
    public int[] GaitCode { get; private set; } = [];
    public int[] GirthImu { get; private set; } = [];
    public double[] GirthT { get; private set; } = [];
    public double[] GirthCadenceHz { get; private set; } = [];
    public string[] GirthStatus { get; private set; } = [];
    public string RawJson { get; private set; } = "";

    private static readonly CultureInfo Es = CultureInfo.GetCultureInfo("es-ES");
    private static string F(double? v, string fmt, string unit = "") => v is double d && double.IsFinite(d) ? d.ToString(fmt, Es) + unit : "—";
    private static string Time(double s) => double.IsFinite(s) ? $"{(int)(s / 60)}:{(int)(s % 60):00}" : "—";
    private static double? Num(JsonElement e, string k) => e.ValueKind == JsonValueKind.Object && e.TryGetProperty(k, out var v) && v.ValueKind == JsonValueKind.Number ? v.GetDouble() : null;
    private static string Str(JsonElement e, string k) => e.ValueKind == JsonValueKind.Object && e.TryGetProperty(k, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() ?? "" : "";
    private static bool Bool(JsonElement e, string k) => e.ValueKind == JsonValueKind.Object && e.TryGetProperty(k, out var v) && v.ValueKind == JsonValueKind.True;
    private static JsonElement Obj(JsonElement e, string k) => e.ValueKind == JsonValueKind.Object && e.TryGetProperty(k, out var v) ? v : default;
    private static IEnumerable<JsonElement> Arr(JsonElement e, string k) => Obj(e, k) is { ValueKind: JsonValueKind.Array } a ? a.EnumerateArray() : Enumerable.Empty<JsonElement>();
    private static double[] Doubles(JsonElement e, string k) => Arr(e, k).Select(x => x.ValueKind == JsonValueKind.Number ? x.GetDouble() : double.NaN).ToArray();
    private static string Strings(JsonElement e, string k, string sep = "; ") => string.Join(sep, Arr(e, k).Select(x => x.GetString() ?? ""));
    public static string GaitText(string code) => code switch
    {
        "STOPPED" => "Parado", "WALK" => "Paso", "TROT" => "Trote", "CANTER_GALLOP" => "Galope", "TRANSITION" => "Transición",
        "UNKNOWN" => "Desconocido", "INSUFFICIENT_DATA" => "Datos insuficientes", _ => code
    };

    public static EquineAnalysis Parse(string json)
    {
        using var doc = JsonDocument.Parse(json);
        var r = doc.RootElement;
        if (r.TryGetProperty("error", out var err)) throw new InvalidDataException(err.GetString());
        if (Str(r, "formato") != "avo-equine-analysis") throw new InvalidDataException("no es un resultado del motor AVO");
        var a = new EquineAnalysis { RawJson = json, Engine = Str(r, "motor"), SessionId = Str(Obj(r, "sesion"), "id") };
        a.Cache = Str(r, "cache") is { Length: > 0 } c ? c : null;
        var p = Obj(r, "procedencia");
        a.Mode = Str(p, "modo"); a.HasImu = Bool(p, "tiene_cincha");
        a.Itow0Ms = Num(p, "itow_inicial_ms") is double i0 ? (long)i0 : null;
        a.Warnings.AddRange(Arr(r, "advertencias").Select(x => x.GetString() ?? ""));
        foreach (var m in Arr(r, "metricas")) if (Num(m, "valor") is double v) a.Metrics[Str(m, "nombre")] = v;
        foreach (var q in Arr(r, "calidad")) a.Quality.Add(new EngineQualityRow(Str(q, "dominio"), Str(q, "nivel"), Strings(q, "motivos")));
        var perf = Obj(r, "rendimiento");
        a.Classifier = Str(perf, "clasificador");
        foreach (var s in Arr(perf, "segmentos"))
        {
            double t0 = Num(s, "t0") ?? double.NaN, t1 = Num(s, "t1") ?? double.NaN;
            a.Segments.Add(new EngineSegmentRow((int)(Num(s, "id") ?? 0), GaitText(Str(s, "codigo")), Time(t0), Time(t1), F(Num(s, "distancia_m"), "0", " m"),
                F(Num(s, "velocidad_media") * 3.6, "0.0", " km/h"), F(Num(s, "velocidad_max") * 3.6, "0.0", " km/h"),
                Num(s, "cadencia_media_hz") is double f ? F(f * 60, "0", " /min") : (a.HasImu ? "—" : "SIN DATOS DE CINCHA"),
                F(Num(s, "longitud_tranco_m"), "0.00", " m"), F(Num(s, "correlacion_ciclos"), "0.00"), F(Num(s, "cv_intervalos"), "0.000"),
                Str(s, "calidad_gnss"), Str(s, "calidad_imu"), Strings(s, "avisos")) { T0 = t0, T1 = t1 });
        }
        foreach (var g in Arr(perf, "por_aire"))
            a.PerGait.Add(new EngineGaitRow(GaitText(Str(g, "codigo")), (int)(Num(g, "segmentos") ?? 0), Time(Num(g, "duracion_s") ?? double.NaN),
                F(Num(g, "fraccion_tiempo") * 100, "0", " %"), F(Num(g, "distancia_m"), "0", " m"), F(Num(g, "velocidad_media") * 3.6, "0.0", " km/h"),
                F(Num(g, "cadencia_media_hz") * 60, "0", " /min"), F(Num(g, "longitud_tranco_m"), "0.00", " m")));
        foreach (var c2 in Arr(Obj(r, "curvas"), "lista"))
        {
            double t0 = Num(c2, "t0") ?? double.NaN;
            a.Curves.Add(new EngineCurveRow((int)(Num(c2, "id") ?? 0), Str(c2, "direccion"), Time(t0), F(Num(c2, "giro_deg"), "0", "°"),
                $"{F(Num(c2, "radio_m"), "0.0")} ± {F(Num(c2, "radio_sigma_m"), "0.0")} m", F(Num(c2, "v_entrada") * 3.6, "0.0", " km/h"), F(Num(c2, "v_salida") * 3.6, "0.0", " km/h"),
                $"{F(Num(c2, "a_lateral_media"), "0.00")} ± {F(Num(c2, "a_lateral_sigma"), "0.00")} m/s²", F(Num(c2, "cadencia_durante_hz") * 60, "0", " /min"), Str(c2, "calidad")) { T0 = t0 });
        }
        foreach (var e in Arr(r, "eventos"))
        {
            double t0 = Num(e, "t0") ?? double.NaN;
            a.Events.Add(new EngineEventRow(Str(e, "id"), Str(e, "tipo"), Time(t0), Time(Num(e, "t1") ?? double.NaN), Str(e, "calidad"), Str(e, "motivo"), $"{Str(e, "algoritmo")} {Str(e, "version")}") { T0 = t0 });
        }
        var fu = Obj(r, "fusion");
        a.FusionSummary = $"Fusión {Str(fu, "modo")}: {(Num(fu, "ventanas_ok") ?? 0):0} de {(Num(fu, "ventanas") ?? 0):0} ventanas · incertidumbre temporal {F(Num(fu, "incertidumbre_temporal_mediana_ms"), "0.0", " ms")}";
        var sy = Obj(r, "simetria");
        a.SymmetryLabel = Str(sy, "etiqueta"); a.SymmetryAllowed = Bool(sy, "conclusiones_permitidas");
        a.SymmetryControls.AddRange(Arr(sy, "controles").Select(x => $"{Str(x, "control")}: {Str(x, "estado")} — {Str(x, "motivo")}"));
        var se = Obj(r, "series");
        if (se.ValueKind == JsonValueKind.Object)
        {
            a.T = Doubles(se, "t"); a.Speed = Doubles(se, "velocidad"); a.Accel = Doubles(se, "aceleracion"); a.LatAccel = Doubles(se, "aceleracion_lateral");
            a.GaitCode = Doubles(se, "aire").Select(x => double.IsFinite(x) ? (int)x : -1).ToArray();
        }
        var gi = Obj(r, "series_cincha");
        if (gi.ValueKind == JsonValueKind.Object)
        {
            a.GirthImu = Doubles(gi, "imu").Select(x => (int)x).ToArray(); a.GirthT = Doubles(gi, "t"); a.GirthCadenceHz = Doubles(gi, "cadencia_hz");
            a.GirthStatus = Arr(gi, "estado").Select(x => x.GetString() ?? "").ToArray();
        }
        return a;
    }

    /// <summary>GNSS seconds of a track point (GPS time of week in ms).</summary>
    public double? TimeOf(long gpsWeekMs)
    {
        if (Itow0Ms is not long t0) return null;
        long d = gpsWeekMs - t0;
        if (d < -302_400_000L) d += 604_800_000L;
        return d / 1000.0;
    }

    public double GnssAt(double[] values, double t, double maxDt = 0.3)
    {
        if (T.Length == 0) return double.NaN;
        int i = Array.BinarySearch(T, t);
        if (i < 0) { i = ~i; if (i > 0 && (i == T.Length || Math.Abs(T[i - 1] - t) < Math.Abs(T[i] - t))) i--; }
        i = Math.Clamp(i, 0, T.Length - 1);
        return Math.Abs(T[i] - t) <= maxDt && i < values.Length ? values[i] : double.NaN;
    }

    public double CadenceAt(double t, double maxDt = 1.5)
    {
        if (GirthT.Length == 0) return double.NaN;
        int imu = GirthImu.Min();
        double best = double.NaN, bd = double.MaxValue;
        for (int k = 0; k < GirthT.Length; k++)
            if (GirthImu[k] == imu && double.IsFinite(GirthT[k]) && Math.Abs(GirthT[k] - t) < bd) { bd = Math.Abs(GirthT[k] - t); best = GirthCadenceHz[k]; }
        return bd <= maxDt ? best : double.NaN;
    }

    public int GaitAt(double t)
    {
        if (T.Length == 0 || GaitCode.Length != T.Length) return -1;
        int i = Array.BinarySearch(T, t);
        if (i < 0) i = Math.Clamp(~i - 1, 0, T.Length - 1);
        return Math.Abs(T[i] - t) <= 0.5 ? GaitCode[i] : -1;
    }
}

public static class EquineComparisonRows
{
    private static readonly CultureInfo Es = CultureInfo.GetCultureInfo("es-ES");
    /// <summary>Rows of an avo-equine-comparison result plus a one-line verdict with the reasons.</summary>
    public static (List<EngineDiffRow> rows, string verdict) Parse(string json)
    {
        using var doc = JsonDocument.Parse(json);
        var r = doc.RootElement;
        if (r.TryGetProperty("error", out var err)) throw new InvalidDataException(err.GetString());
        string N(JsonElement e, string k) => e.TryGetProperty(k, out var v) && v.ValueKind == JsonValueKind.Number ? v.GetDouble().ToString("0.###", Es) : "—";
        var rows = r.GetProperty("diferencias").EnumerateArray().Select(d => new EngineDiffRow(d.GetProperty("metrica").GetString() ?? "", N(d, "a"), N(d, "b"), N(d, "diferencia"),
            d.GetProperty("comparable").GetBoolean() ? "sí" : "no", d.GetProperty("contexto").GetString() ?? "")).ToList();
        var reasons = string.Join("; ", r.GetProperty("motivos").EnumerateArray().Select(x => x.GetString()));
        var route = r.GetProperty("recorrido");
        string routeText = route.GetProperty("intentado").GetBoolean()
            ? (route.GetProperty("comparable").GetBoolean() ? $" · mismo recorrido: Δv {N(route, "diferencia_velocidad_media")} m/s, Δt {N(route, "diferencia_tiempo_total_s")} s" : " · recorrido no comparable: " + route.GetProperty("motivo").GetString())
            : "";
        string verdict = (r.GetProperty("comparable").GetBoolean() ? "Comparables" : "No comparables") + (reasons.Length > 0 ? " — " + reasons : "") + routeText;
        return (rows, verdict);
    }
}

public sealed record EngineKvRow(string Metrica, string Valor);

public static class EquineSection
{
    private static readonly CultureInfo Es = CultureInfo.GetCultureInfo("es-ES");
    /// <summary>Statistics of section "a" of a comparison result (used to analyse a selected interval of one session).</summary>
    public static List<EngineKvRow> ParseA(string json)
    {
        using var doc = JsonDocument.Parse(json);
        var r = doc.RootElement;
        if (r.TryGetProperty("error", out var err)) throw new InvalidDataException(err.GetString());
        var a = r.GetProperty("a");
        string N(string k, double scale = 1, string fmt = "0.##", string unit = "") =>
            a.TryGetProperty(k, out var v) && v.ValueKind == JsonValueKind.Number ? (v.GetDouble() * scale).ToString(fmt, Es) + unit : "—";
        return
        [
            new("Duración", N("duracion_s", 1, "0.0", " s")), new("Distancia", N("distancia_m", 1, "0.0", " m")),
            new("Velocidad media", N("velocidad_media", 3.6, "0.0", " km/h")), new("Velocidad máxima", N("velocidad_max", 3.6, "0.0", " km/h")),
            new("Cadencia", N("cadencia_hz", 60, "0", " /min")), new("Correlación entre ciclos", N("correlacion_ciclos")),
            new("CV intervalos", N("cv_intervalos", 1, "0.000")), new("RTK FIX", N("fraccion_fix", 100, "0", " %")),
            new("Eventos", N("eventos", 1, "0")), new("Aire dominante", EquineAnalysis.GaitText(a.TryGetProperty("aire_dominante", out var g) ? g.GetString() ?? "" : "")),
        ];
    }
}
