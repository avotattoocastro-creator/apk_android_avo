using System.Globalization;
using System.Text.Json;

namespace Avo.Windows.Core;

// «Datos clave» y «Calendario» — paridad iPad ↔ PC (docs/PARIDAD_IPAD_PC.md).
// Reglas IDÉNTICAS a ipad/AVOiPad/Core/KeyData.swift: todas las cifras salen del resultado del motor AVO Equine (el
// mismo para Windows e iPad), nunca de un cálculo propio de la app. Lo que el motor no da (pulso, recuperaciones) se
// muestra como «—» con el motivo; nunca se inventa.

/// <summary>One tile of «Datos clave». Group: 0 = velocidad y tiempos, 1 = pulso, 2 = tranco.
/// T0/T1 = engine-time window of the figure (best tramos), to open it in «Gráficas»; null when it has none.</summary>
public sealed record KeyTile(string Id, string Label, string Value, string Unit, string Caption, bool Available, int Group, double? T0 = null, double? T1 = null)
{
    public bool HasWindow => T0 is not null && T1 is not null;
}

/// <summary>One 200 m split of an effort (engine <c>trabajo_pista.trabajos.lista[].parciales</c>). Share = speed relative
/// to the fastest split of the effort (0…1); T0/T1 = engine-time window.</summary>
public sealed record KeySplit(int Id, string Label, string TimeText, string SpeedText, double Share, bool Fastest, double T0, double T1);

/// <summary>One effort with its splits.</summary>
public sealed record KeyEffort(int Id, string Title, string Kind, string Summary, double T0, double T1, IReadOnlyList<KeySplit> Splits);

/// <summary>Time spent in one gait (engine metric <c>tiempo_&lt;AIRE&gt;</c>).</summary>
public sealed record KeyGait(string Id, string Name, double Seconds, double Share)
{
    public string TimeText => KeyData.Clock(Seconds);
    public string ShareText => (Share * 100).ToString("0", KeyData.Es) + " %";
}

public sealed record KeyQualityRow(string Label, double Seconds, string ShareText);

public sealed class KeyData
{
    public static readonly CultureInfo Es = CultureInfo.GetCultureInfo("es-ES");
    public const string EcgCaption = "Llega con el ECG de la cincha";
    public const string GirthCaption = "Necesita la cincha montada";
    public const string NoFastCaption = "Sin trabajo rápido detectado";
    public const string NoRefCaption = "Sin galope a esa velocidad";

    public List<KeyTile> Tiles { get; } = [];
    public List<KeyGait> Gaits { get; } = [];
    public List<KeyEffort> Efforts { get; } = [];
    public bool HasEfforts => Efforts.Count > 0;
    /// <summary>Fraction (0…1) of the session in RTK FIX, from the engine <c>rtk</c> block; null without data.</summary>
    public double? FixShare { get; private set; }
    /// <summary>Dominant position quality: «RTK FIX», «RTK FLOAT», «DGNSS», «GNSS» or «Sin datos».</summary>
    public string QualityLabel { get; private set; } = "Sin datos";
    public List<KeyQualityRow> Quality { get; } = [];
    public bool HasEngine { get; private set; }
    /// <summary>Best 200 m time of the training (s), for the Cuadra/Jinetes totals (same rule as «Mejor 200 m»).</summary>
    public double? Best200S { get; private set; }

    public IEnumerable<KeyTile> SpeedTiles => Tiles.Where(t => t.Group == 0);
    public IEnumerable<KeyTile> HeartTiles => Tiles.Where(t => t.Group == 1);
    public IEnumerable<KeyTile> StrideTiles => Tiles.Where(t => t.Group == 2);
    public string FixText => FixShare is double f ? (f * 100).ToString("0", Es) + " % en FIX" : "";
    public bool ShowQualityWarning => QualityLabel is not ("RTK FIX" or "Sin datos");

    // ------------------------------------------------------------------ parsing (same rules as KeyData.swift)
    public static KeyData From(string json)
    {
        var k = new KeyData();
        JsonDocument doc;
        try { doc = JsonDocument.Parse(json); } catch (JsonException) { return k; }
        using (doc)
        {
            var r = doc.RootElement;
            if (r.ValueKind != JsonValueKind.Object || Str(r, "formato") != "avo-equine-analysis") return k;
            k.HasEngine = true;

            var metrics = new Dictionary<string, double>(StringComparer.Ordinal);
            foreach (var m in Arr(r, "metricas"))
                if (Str(m, "nombre") is { Length: > 0 } name && Num(m, "valor") is double v) metrics[name] = v;
            var trabajos = Obj(Obj(r, "trabajo_pista"), "trabajos");
            var efforts = Arr(trabajos, "lista").Where(e => e.ValueKind == JsonValueKind.Object).ToList();

            // best time over `meters` among all efforts: (time, engine t0, effort number)
            (double Time, double? T0, int? Effort)? Best(double meters)
            {
                (double Time, double? T0, int? Effort)? b = null;
                foreach (var e in efforts)
                    foreach (var x in Arr(e, "mejores"))
                        if (Num(x, "distancia_m") is double d && Math.Abs(d - meters) < 1 && Num(x, "tiempo_s") is double t && t > 0 && (b is null || t < b.Value.Time))
                            b = (t, Num(x, "t0"), Num(e, "id") is double id ? (int)id : null);
                if (b is null && meters == 200 && Num(trabajos, "mejor_200m_s") is double t2 && t2 > 0) b = (t2, null, null);
                return b;
            }
            KeyTile BestTile(string id, double meters)
            {
                string label = $"Mejor {(int)meters} m";
                if (Best(meters) is not { } b) return new KeyTile(id, label, "—", "s", NoFastCaption, false, 0);
                string caption = b.Effort is int n ? $"Trabajo {n} · ver en gráficas" : $"Mejor tramo de {(int)meters} m";
                return new KeyTile(id, label, b.Time.ToString("0.00", Es), "s", caption, true, 0, b.T0, b.T0 + b.Time);
            }
            // stride at the breed reference speed k: median over the efforts of referencia[k] (same rule as the engine
            // training summary, training.cpp)
            double? Reference(int k, string key)
            {
                var v = new List<double>();
                foreach (var e in efforts)
                {
                    var arr = Obj(e, "referencia");
                    if (arr.ValueKind != JsonValueKind.Array || arr.GetArrayLength() <= k) continue;
                    if (Num(arr[k], key) is double y && y > 0) v.Add(y);
                }
                return Median(v);
            }
            double? MaxOf(string key)
            {
                double? m = null;
                foreach (var e in efforts) if (Num(e, key) is double v && v > 0 && (m is null || v > m)) m = v;
                return m;
            }
            double? Metric(string n) => metrics.TryGetValue(n, out var v) ? v : null;

            k.Tiles.Add(Tile("vmax", "Velocidad máxima", Metric("velocidad_maxima") * 3.6, "0.0", "km/h", "Motor AVO", "Sin datos GNSS", 0));
            k.Best200S = Best(200)?.Time;
            k.Tiles.Add(BestTile("best200", 200));
            k.Tiles.Add(BestTile("best600", 600));
            // «distancia de trabajo»: the hard work inside the whole training (engine distancia_rapida_m), in place of
            // «Mejor 1000 m» (trainer 14/11/2026)
            var work = Tile("workdist", "Distancia de trabajo", Num(trabajos, "distancia_rapida_m") is double wd && wd > 0 ? wd / 1000 : (double?)null,
                "0.00", "km", "Trabajo rápido del entrenamiento", NoFastCaption, 0);
            // opens the charts on the work (first effort start → last effort end), like «Mejor 200 m» (trainer 14/11/2026)
            double? w0 = null, w1 = null;
            foreach (var e in efforts)
            {
                if (Num(e, "t0") is double a && (w0 is null || a < w0)) w0 = a;
                if (Num(e, "t1") is double b && (w1 is null || b > w1)) w1 = b;
            }
            if (work.Available && w0 is double x0 && w1 is double x1 && x1 > x0)
                work = work with { T0 = x0, T1 = x1, Caption = "Trabajo rápido · ver en gráficas" };
            k.Tiles.Add(work);
            k.Tiles.Add(Tile("distance", "Distancia", Metric("distancia") / 1000, "0.00", "km", "Toda la sesión", "Sin datos", 0));
            double? dur = Metric("duracion");
            k.Tiles.Add(new KeyTile("duration", "Duración", dur is double ds ? Clock(ds) : "—", "", dur is null ? "Sin datos" : "Toda la sesión", dur is not null, 0));
            k.Tiles.Add(new KeyTile("hrmax", "Pulso máximo", "—", "lpm", EcgCaption, false, 1));
            k.Tiles.Add(new KeyTile("rec2", "Recuperación a 2 min", "—", "lpm", EcgCaption, false, 1));
            k.Tiles.Add(new KeyTile("hrend", "Pulso al terminar", "—", "lpm", EcgCaption, false, 1));
            k.Tiles.Add(Tile("lmax", "Tranco máximo", MaxOf("l_max_m"), "0.00", "m", "En galope", GirthCaption, 2));
            k.Tiles.Add(Tile("fmax", "Frecuencia máxima", MaxOf("f_max_hz"), "0.00", "tr/s", "En galope", GirthCaption, 2));
            var refs = Obj(Obj(Obj(r, "trabajo_pista"), "perfil"), "v_referencia");
            bool hasStride = MaxOf("l_max_m") is not null || MaxOf("f_max_hz") is not null;
            for (int q = 0; q < 2; q++)
            {
                double? v = refs.ValueKind == JsonValueKind.Array && refs.GetArrayLength() > q && refs[q].ValueKind == JsonValueKind.Number ? refs[q].GetDouble() : null;
                string at = v is double vv ? "a " + (vv * 3.6).ToString("0", Es) + " km/h" : $"a v. ref. {q + 1}";
                string miss = hasStride ? NoRefCaption : GirthCaption;
                k.Tiles.Add(Tile($"lref{q + 1}", "Tranco " + at, Reference(q, "l_m"), "0.00", "m", "Mediana de los trabajos", miss, 2));
                // 5 stride boxes (trainer 14/11/2026): no «frecuencia» at the second reference speed
                if (q == 0) k.Tiles.Add(Tile("fref1", "Frecuencia " + at, Reference(q, "f_hz"), "0.00", "tr/s", "Mediana de los trabajos", miss, 2));
            }

            // efforts with their 200 m splits
            foreach (var e in efforts)
            {
                if (Num(e, "id") is not double id || Num(e, "t0") is not double e0) continue;
                double acc = e0;
                var raw = new List<(string Label, double Time, double V, double T0)>();
                foreach (var p in Arr(e, "parciales"))
                {
                    if (Num(p, "desde_m") is not double a || Num(p, "hasta_m") is not double b || Num(p, "tiempo_s") is not double ts || ts <= 0) continue;
                    double v = Num(p, "v") ?? (b - a) / ts;
                    raw.Add(($"{(int)Math.Round(a, MidpointRounding.AwayFromZero)}–{(int)Math.Round(b, MidpointRounding.AwayFromZero)} m", ts, v, acc));
                    acc += ts;
                }
                if (raw.Count == 0) continue;
                double vTop = raw.Max(x => x.V);
                var splits = raw.Select((x, i) => new KeySplit(i, x.Label, x.Time.ToString("0.00", Es), (x.V * 3.6).ToString("0.0", Es),
                    vTop > 0 ? x.V / vTop : 0, x.V == vTop, x.T0, x.T0 + x.Time)).ToList();
                bool fast = Str(e, "tipo") == "TRABAJO_RAPIDO";
                var parts = new List<string>();
                if (Num(e, "distancia_m") is double dm) parts.Add(dm.ToString("0", Es) + " m");
                if (Num(e, "duracion_s") is double du) parts.Add(Clock(du));
                if (Num(e, "v_max") is double vm) parts.Add("máx. " + (vm * 3.6).ToString("0.0", Es) + " km/h");
                k.Efforts.Add(new KeyEffort((int)id, $"Trabajo {(int)id}", fast ? "Trabajo rápido" : "Galope de trabajo",
                    string.Join(" · ", parts), e0, Num(e, "t1") ?? acc, splits));
            }

            // gaits: engine metrics tiempo_<AIRE> (AIRE in capitals), e.g. tiempo_PASO
            var gaits = new List<KeyGait>();
            foreach (var name in metrics.Keys.OrderBy(GaitRank).ThenBy(x => x, StringComparer.Ordinal))
            {
                if (!name.StartsWith("tiempo_", StringComparison.Ordinal)) continue;
                string code = name["tiempo_".Length..];
                if (code.Length == 0 || !code.All(c => c is >= 'A' and <= 'Z' or '_') || metrics[name] <= 0) continue;
                gaits.Add(new KeyGait(code, GaitName(code), metrics[name], 0));
            }
            double total = gaits.Sum(g => g.Seconds);
            k.Gaits.AddRange(gaits.Select(g => g with { Share = total > 0 ? g.Seconds / total : 0 }));

            // position quality: engine `rtk` block
            var rtk = Obj(r, "rtk");
            if (Num(rtk, "total_s") is double tot && tot > 0)
            {
                var parts = new (string Label, double S)[]
                {
                    ("RTK FIX", Num(rtk, "fix_s") ?? 0), ("RTK FLOAT", Num(rtk, "float_s") ?? 0),
                    ("DGNSS", Num(rtk, "dgnss_s") ?? 0), ("GNSS", Num(rtk, "gnss_s") ?? 0),
                };
                double sum = parts.Sum(p => p.S);
                foreach (var p in parts) k.Quality.Add(new KeyQualityRow(p.Label, p.S, sum > 0 ? (p.S / sum * 100).ToString("0", Es) + " %" : "—"));
                k.FixShare = (Num(rtk, "fix_s") ?? 0) / tot;
                var top = parts.MaxBy(p => p.S);
                if (top.S > 0) k.QualityLabel = top.Label;
            }
        }
        return k;
    }

    // ------------------------------------------------------------------ helpers
    private static double? Num(JsonElement e, string key) =>
        e.ValueKind == JsonValueKind.Object && e.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.Number && double.IsFinite(v.GetDouble()) ? v.GetDouble() : null;
    private static string Str(JsonElement e, string key) =>
        e.ValueKind == JsonValueKind.Object && e.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() ?? "" : "";
    private static JsonElement Obj(JsonElement e, string key) => e.ValueKind == JsonValueKind.Object && e.TryGetProperty(key, out var v) ? v : default;
    private static IEnumerable<JsonElement> Arr(JsonElement e, string key) =>
        Obj(e, key) is { ValueKind: JsonValueKind.Array } a ? a.EnumerateArray() : Enumerable.Empty<JsonElement>();

    /// <summary>Median (mean of the two central values when the count is even); null when empty.</summary>
    public static double? Median(List<double> v)
    {
        if (v.Count == 0) return null;
        var s = v.OrderBy(x => x).ToList();
        int n = s.Count;
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2;
    }

    private static KeyTile Tile(string id, string label, double? v, string fmt, string unit, string caption, string missing, int group) =>
        v is double d && double.IsFinite(d)
            ? new KeyTile(id, label, d.ToString(fmt, Es), unit, caption, true, group)
            : new KeyTile(id, label, "—", unit, missing, false, group);

    /// <summary>mm:ss, or h:mm:ss from one hour (same as iPad TimeText.clock).</summary>
    public static string Clock(double seconds)
    {
        if (!double.IsFinite(seconds)) return "—";
        long total = (long)Math.Max(0, seconds);
        long h = total / 3600 % 24, m = total / 60 % 60, s = total % 60;
        return seconds >= 3600 ? $"{h}:{m:00}:{s:00}" : $"{m:00}:{s:00}";
    }

    public static string GaitName(string code) => code switch
    {
        "PARADO" => "Parado", "PASO" => "Paso", "TROTE" => "Trote", "GALOPE" => "Galope",
        _ => code[..1] + code[1..].ToLowerInvariant().Replace('_', ' '),
    };

    private static int GaitRank(string name) => name switch
    {
        "tiempo_PARADO" => 0, "tiempo_PASO" => 1, "tiempo_TROTE" => 2, "tiempo_GALOPE" => 3, _ => 99,
    };

    // ------------------------------------------------------------------ cache (the analysis JSON can be large)
    private static readonly Dictionary<string, (int Length, KeyData Data)> Cache = new(StringComparer.Ordinal);
    private static readonly object CacheLock = new();

    /// <summary>KeyData of a training, parsed once per engine result.</summary>
    public static KeyData Cached(string id, string json)
    {
        lock (CacheLock) { if (Cache.TryGetValue(id, out var c) && c.Length == json.Length) return c.Data; }
        var k = From(json);
        lock (CacheLock) Cache[id] = (json.Length, k);
        return k;
    }
}

// ------------------------------------------------------------------ calendar (same rules as TrainingCalendar in KeyData.swift)

/// <summary>One training in the calendar. FixShare = fraction in RTK FIX (engine); null while the engine has not run.</summary>
public sealed record CalendarEntry(string Id, DateTimeOffset Start, string Horse, double DurationS, double DistanceKm, double? FixShare)
{
    public string Label => $"{Horse} · {MadridTime.Format(Start, "HH:mm")}";
    public string Detail => $"{DistanceKm.ToString("0.00", KeyData.Es)} km · {KeyData.Clock(DurationS)}";
}

public sealed record CalendarDay(string Id, int Day, bool InMonth, bool IsToday, IReadOnlyList<CalendarEntry> Entries)
{
    public IEnumerable<CalendarEntry> Shown => Entries.Take(3);
    public string MoreText => Entries.Count > 3 ? $"+{Entries.Count - 3} más" : "";
}

public sealed record CalendarSummary(int Count, double DurationS, double DistanceKm, int RtkCount, int AnalysedCount)
{
    public string CountText => Count.ToString(KeyData.Es);
    public string DurationText { get { int m = (int)Math.Round(DurationS / 60, MidpointRounding.AwayFromZero); return m >= 60 ? $"{m / 60} h {m % 60} min" : $"{m} min"; } }
    public string MeanText => Count == 0 ? "—" : $"{(int)Math.Round(DurationS / Count / 60, MidpointRounding.AwayFromZero)} min";
    public string DistanceText => DistanceKm.ToString("0.00", KeyData.Es) + " km";
    public string RtkText => AnalysedCount == 0 ? "—" : $"{RtkCount} de {AnalysedCount}";
}

public sealed record CalendarMonthCell(int Month, string Name, CalendarSummary Summary)
{
    public string CountText => Summary.Count == 0 ? "—" : $"{Summary.Count} sesiones";
    public string Detail => Summary.Count == 0 ? "" : $"{Summary.DistanceText} · {Summary.DurationText}";
}

public static class TrainingCalendar
{
    public static readonly string[] MonthNames = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto",
        "septiembre", "octubre", "noviembre", "diciembre"];
    public static readonly string[] Weekdays = ["LUN", "MAR", "MIÉ", "JUE", "VIE", "SÁB", "DOM"];

    /// <summary>(year, month) of an instant in Europe/Madrid.</summary>
    public static (int Year, int Month) YearMonth(DateTimeOffset utc) { var d = MadridTime.ToMadrid(utc); return (d.Year, d.Month); }

    public static List<CalendarEntry> Entries(int year, int? month, IEnumerable<CalendarEntry> all) =>
        all.Where(e => { var ym = YearMonth(e.Start); return ym.Year == year && (month is null || ym.Month == month); }).ToList();

    /// <summary>42 cells (6 weeks, Monday first) of a month in Europe/Madrid.</summary>
    public static List<CalendarDay> MonthGrid(int year, int month, IEnumerable<CalendarEntry> entries, DateTimeOffset today)
    {
        var first = new DateTime(year, month, 1);
        int lead = ((int)first.DayOfWeek + 6) % 7;            // Monday first
        var gridStart = first.AddDays(-lead);
        var t = MadridTime.ToMadrid(today).Date;
        var byDay = entries.GroupBy(e => MadridTime.ToMadrid(e.Start).Date).ToDictionary(g => g.Key, g => g.OrderBy(e => e.Start).ToList());
        var cells = new List<CalendarDay>(42);
        for (int i = 0; i < 42; i++)
        {
            var d = gridStart.AddDays(i);
            cells.Add(new CalendarDay($"{d.Year}-{d.Month}-{d.Day}", d.Day, d.Month == month, d == t,
                byDay.TryGetValue(d, out var list) ? list : []));
        }
        return cells;
    }

    /// <summary>Monday (Europe/Madrid date) of the week of an instant.</summary>
    public static DateTime WeekStart(DateTimeOffset utc)
    {
        var d = MadridTime.ToMadrid(utc).Date;
        return d.AddDays(-(((int)d.DayOfWeek + 6) % 7));
    }

    /// <summary>The 7 days (Monday first) of the week starting at <paramref name="monday"/> (Madrid dates).</summary>
    public static List<CalendarDay> WeekGrid(DateTime monday, IEnumerable<CalendarEntry> entries, DateTimeOffset today)
    {
        var t = MadridTime.ToMadrid(today).Date;
        var byDay = entries.GroupBy(e => MadridTime.ToMadrid(e.Start).Date).ToDictionary(g => g.Key, g => g.OrderBy(e => e.Start).ToList());
        return Enumerable.Range(0, 7).Select(i =>
        {
            var d = monday.Date.AddDays(i);
            return new CalendarDay($"{d.Year}-{d.Month}-{d.Day}", d.Day, true, d == t, byDay.TryGetValue(d, out var list) ? list : []);
        }).ToList();
    }

    /// <summary>«3 – 9 nov 2025», «27 oct – 2 nov 2025» or «29 dic 2025 – 4 ene 2026».</summary>
    public static string WeekTitle(DateTime monday)
    {
        var a = monday.Date; var b = a.AddDays(6);
        string M(int m) => SessionNavigator.MonthShort[m - 1].ToLowerInvariant();
        if (a.Year != b.Year) return $"{a.Day} {M(a.Month)} {a.Year} – {b.Day} {M(b.Month)} {b.Year}";
        if (a.Month != b.Month) return $"{a.Day} {M(a.Month)} – {b.Day} {M(b.Month)} {b.Year}";
        return $"{a.Day} – {b.Day} {M(b.Month)} {b.Year}";
    }

    public static CalendarSummary Summary(IEnumerable<CalendarEntry> entries)
    {
        int count = 0, rtk = 0, analysed = 0; double dur = 0, km = 0;
        foreach (var e in entries)
        {
            count++; dur += Math.Max(0, e.DurationS); km += Math.Max(0, e.DistanceKm);
            if (e.FixShare is double f) { analysed++; if (f >= 0.5) rtk++; }
        }
        return new CalendarSummary(count, dur, km, rtk, analysed);
    }

    public static List<CalendarMonthCell> YearCells(int year, IEnumerable<CalendarEntry> all)
    {
        var list = all.ToList();
        return Enumerable.Range(1, 12).Select(m => new CalendarMonthCell(m, MonthNames[m - 1].ToUpperInvariant(), Summary(Entries(year, m, list)))).ToList();
    }
}

// ------------------------------------------------------------------ session navigator (same rules as SessionNavigator in KeyData.swift)

public sealed record NavGroup(string Id, string Title, IReadOnlyList<CalendarEntry> Entries);

public static class SessionNavigator
{
    public static readonly string[] MonthShort = ["ENE", "FEB", "MAR", "ABR", "MAY", "JUN", "JUL", "AGO", "SEP", "OCT", "NOV", "DIC"];

    /// <summary>Sessions grouped by day (Europe/Madrid), newest first; <paramref name="query"/> filters by horse (case and
    /// accents ignored).</summary>
    public static List<NavGroup> Groups(IEnumerable<CalendarEntry> all, string query = "")
    {
        string q = Fold(query.Trim());
        var list = all.Where(e => q.Length == 0 || Fold(e.Horse).Contains(q, StringComparison.Ordinal)).OrderByDescending(e => e.Start).ToList();
        var outList = new List<NavGroup>();
        foreach (var e in list)
        {
            var d = MadridTime.ToMadrid(e.Start);
            string key = $"{d.Year}-{d.Month}-{d.Day}";
            if (outList.Count > 0 && outList[^1].Id == key)
            {
                var g = outList[^1];
                outList[^1] = g with { Entries = g.Entries.Append(e).ToList() };
            }
            else
            {
                string wd = TrainingCalendar.Weekdays[((int)d.DayOfWeek + 6) % 7];
                outList.Add(new NavGroup(key, $"{wd} {d.Day} {MonthShort[d.Month - 1]} {d.Year}", [e]));
            }
        }
        return outList;
    }

    /// <summary>«HH:mm · caballo» in Europe/Madrid.</summary>
    public static string ItemText(CalendarEntry e) => MadridTime.Format(e.Start, "HH:mm") + " · " + e.Horse;

    private static string Fold(string s)
    {
        var n = s.ToLowerInvariant().Normalize(System.Text.NormalizationForm.FormD);
        var sb = new System.Text.StringBuilder(n.Length);
        foreach (var c in n) if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark) sb.Append(c);
        return sb.ToString();
    }
}

// ------------------------------------------------------------------ dashboard (same rules as DashboardSummary in KeyData.swift)

/// <summary>One of the latest trainings shown at the bottom of the Dashboard. Quality: «RTK FIX» (≥ 50 % of the time in
/// FIX), «Sin FIX» or «Sin analizar».</summary>
public sealed record DashCard(string Id, string DayText, string TimeText, string Horse, string DistanceText, string DurationText, string Quality)
{
    public string QualityColor => Quality switch { "RTK FIX" => "#52DD40", "Sin FIX" => "#FFC42C", _ => "#93949B" };
}

/// <summary>ThisWeek = Monday to Sunday of the current week (Europe/Madrid); Pending = without a horse or not analysed.</summary>
public sealed record DashboardSummary(int Trainings, int ThisWeek, int Pending, IReadOnlyList<DashCard> Latest)
{
    public const string NoHorse = "Sin caballo";

    public static DashboardSummary From(IEnumerable<CalendarEntry> all, DateTimeOffset today, int latest = 5)
    {
        var list = all.ToList();
        var t = MadridTime.ToMadrid(today).Date;
        var monday = t.AddDays(-(((int)t.DayOfWeek + 6) % 7));
        var next = monday.AddDays(7);
        int week = list.Count(e => { var d = MadridTime.ToMadrid(e.Start); return d >= monday && d < next; });
        int pending = list.Count(e => e.FixShare is null || e.Horse == NoHorse);
        var cards = list.OrderByDescending(e => e.Start).Take(latest).Select(e =>
        {
            var d = MadridTime.ToMadrid(e.Start);
            int m = (int)Math.Round(Math.Max(0, e.DurationS) / 60, MidpointRounding.AwayFromZero);
            string q = e.FixShare is double f ? (f >= 0.5 ? "RTK FIX" : "Sin FIX") : "Sin analizar";
            return new DashCard(e.Id, $"{TrainingCalendar.Weekdays[((int)d.DayOfWeek + 6) % 7]} {d.Day} {SessionNavigator.MonthShort[d.Month - 1]}",
                d.ToString("HH:mm", KeyData.Es), e.Horse, Math.Max(0, e.DistanceKm).ToString("0.00", KeyData.Es) + " km",
                m >= 60 ? $"{m / 60} h {m % 60} min" : $"{m} min", q);
        }).ToList();
        return new DashboardSummary(list.Count, week, pending, cards);
    }
}
