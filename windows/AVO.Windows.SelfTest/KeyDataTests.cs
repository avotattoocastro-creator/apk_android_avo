using Avo.Windows.Core;

namespace Avo.Windows.SelfTest;

/// <summary>Paridad iPad ↔ PC: el MISMO JSON y los MISMOS valores esperados que ipad/AVOiPadTests/KeyDataTests.swift.</summary>
public static class KeyDataTests
{
    public const string Json = """
    {"formato":"avo-equine-analysis","metricas":[{"nombre":"distancia","valor":7840.4},{"nombre":"duracion","valor":2652},
    {"nombre":"velocidad_maxima","valor":18.0555},{"nombre":"tiempo_PASO","valor":2000},{"nombre":"tiempo_TROTE","valor":330},
    {"nombre":"tiempo_GALOPE","valor":322},{"nombre":"tiempo_en_curva","valor":50}],
    "rtk":{"total_s":2652,"fix_s":0,"float_s":0,"dgnss_s":2400,"gnss_s":252},
    "trabajo_pista":{"perfil":{"v_referencia":[14,16]},"trabajos":{"v_max":18.0555,"mejor_200m_s":11.36,"distancia_rapida_m":1600,"lista":[
    {"id":1,"tipo":"TRABAJO_RAPIDO","t0":10,"t1":110,"distancia_m":1600,"duracion_s":100,"v_max":18.0555,
    "parciales":[{"desde_m":0,"hasta_m":200,"tiempo_s":12.5,"v":16},{"desde_m":200,"hasta_m":400,"tiempo_s":11.36,"v":17.6056},{"desde_m":400,"hasta_m":600,"tiempo_s":12.0,"v":16.6667}],
    "mejores":[{"distancia_m":200,"tiempo_s":11.36,"t0":40},{"distancia_m":600,"tiempo_s":35.31,"t0":30},{"distancia_m":1000,"tiempo_s":60.42,"t0":20}],"l_max_m":7.3,"f_max_hz":2.36,
    "referencia":[{"v":14,"f_hz":2.2,"l_m":6.4},{"v":16,"f_hz":null,"l_m":null}]},
    {"id":2,"tipo":"GALOPE_TRABAJO","t0":300,"t1":380,"mejores":[{"distancia_m":200,"tiempo_s":12.1},{"distancia_m":600,"tiempo_s":37.0}],"l_max_m":6.9,
    "referencia":[{"v":14,"f_hz":2.0,"l_m":6.8},{"v":16,"f_hz":null,"l_m":null}]}]}}}
    """;

    public static void Run(Action<bool, string> assert)
    {
        var k = KeyData.From(Json);
        string V(string id) => k.Tiles.FirstOrDefault(t => t.Id == id)?.Value ?? "?";
        assert(k.HasEngine, "Datos clave: resultado del motor reconocido");
        assert(V("vmax") == "65,0" && V("best200") == "11,36" && V("best600") == "35,31" && V("workdist") == "1,60",
            $"Datos clave: velocidad y mejores tramos ({V("vmax")} · {V("best200")} · {V("best600")} · {V("workdist")})");
        var wdt = k.Tiles.FirstOrDefault(t => t.Id == "workdist");
        assert(wdt?.T0 is double wa && wdt.T1 is double wb && wb > wa, "Datos clave: la distancia de trabajo abre las gráficas en el trabajo");
        assert(k.Best200S is double b2 && Math.Abs(b2 - 11.36) < 0.006, $"Datos clave: mejor 200 m numérico para Cuadra/Jinetes ({k.Best200S})");
        assert(V("distance") == "7,84" && V("duration") == "44:12", $"Datos clave: distancia y duración ({V("distance")} · {V("duration")})");
        assert(V("hrmax") == "—" && V("lmax") == "7,30" && V("fmax") == "2,36", "Datos clave: pulso vacío y tranco del motor");
        assert(string.Join(",", k.Gaits.Select(g => g.Id)) == "PASO,TROTE,GALOPE", "Datos clave: aires en orden y sin tiempo_en_curva");
        assert(k.QualityLabel == "DGNSS" && k.FixShare == 0, "Datos clave: calidad DGNSS y 0 % en FIX");

        KeyTile? T(string id) => k.Tiles.FirstOrDefault(t => t.Id == id);
        assert(T("best600") is { T0: 30 } b6 && Math.Abs(b6.T1!.Value - 65.31) < 1e-9 && b6.Caption == "Trabajo 1 · ver en gráficas",
            "Datos clave: ventana del mejor 600 m para abrir en gráficas");
        assert(k.SpeedTiles.Count() == 6 && string.Join(",", k.StrideTiles.Select(t => t.Id)) == "lmax,fmax,lref1,fref1,lref2"
            && string.Join(",", k.HeartTiles.Select(t => t.Id)) == "hrmax,rec2,hrend",
            "Datos clave: 6 recuadros en velocidad, 3 en pulso y 5 en tranco");
        assert(T("lref1")?.Label == "Tranco a 50 km/h" && V("lref1") == "6,60" && V("fref1") == "2,10",
            $"Datos clave: tranco a velocidad de referencia ({T("lref1")?.Label} · {V("lref1")} · {V("fref1")})");
        assert(T("lref2") is { Label: "Tranco a 58 km/h", Value: "—", Caption: "Sin galope a esa velocidad" }, "Datos clave: referencia sin datos");
        var ef = k.Efforts.FirstOrDefault();
        assert(k.Efforts.Count == 1 && ef is not null && ef.Kind == "Trabajo rápido" && ef.Summary == "1600 m · 01:40 · máx. 65,0 km/h",
            $"Parciales: trabajos con parciales ({ef?.Summary})");
        assert(ef is not null && string.Join("|", ef.Splits.Select(x => x.Label)) == "0–200 m|200–400 m|400–600 m"
            && string.Join("|", ef.Splits.Select(x => x.TimeText)) == "12,50|11,36|12,00"
            && string.Join("|", ef.Splits.Select(x => x.SpeedText)) == "57,6|63,4|60,0"
            && string.Join("|", ef.Splits.Select(x => x.Fastest)) == "False|True|False"
            && Math.Abs(ef.Splits[1].T0 - 22.5) < 1e-9 && Math.Abs(ef.Splits[1].T1 - 33.86) < 1e-9,
            "Parciales: etiquetas, tiempos, velocidades, el más rápido y su ventana");

        var days = TrainingCalendar.MonthGrid(2026, 11, [], DateTimeOffset.FromUnixTimeSeconds(0));
        assert(days.Count == 42 && days[0].Day == 26 && !days[0].InMonth && days[6].Day == 1 && days[6].InMonth,
            "Calendario: noviembre 2026 empieza el lunes 26 de octubre");
        var d = DateTimeOffset.FromUnixTimeSeconds(1_762_590_000);
        var s = TrainingCalendar.Summary([
            new CalendarEntry("a", d, "Zakina", 2640, 7.84, 0),
            new CalendarEntry("b", d, "Maalwina", 3480, 8.60, 0.8),
            new CalendarEntry("c", d, "Maalwina", 1800, 6.04, null),
        ]);
        assert(s.Count == 3 && s.DurationText == "2 h 12 min" && s.DistanceText == "22,48 km" && s.RtkText == "1 de 2",
            $"Calendario: acumulados ({s.DurationText} · {s.DistanceText} · {s.RtkText})");

        var ne = new List<CalendarEntry>
        {
            new("a", d, "Zakina", 0, 0, null), new("b", d.AddHours(1), "Maalwina", 0, 0, null), new("c", d.AddDays(-1), "Árabe Test", 0, 0, null),
        };
        var ng = SessionNavigator.Groups(ne);
        assert(string.Join("|", ng.Select(g => g.Title)) == "SÁB 8 NOV 2025|VIE 7 NOV 2025" && string.Join(",", ng[0].Entries.Select(x => x.Id)) == "b,a"
            && SessionNavigator.ItemText(ng[0].Entries[0]) == "10:20 · Maalwina"
            && string.Join(",", SessionNavigator.Groups(ne, "arabe").SelectMany(g => g.Entries).Select(x => x.Id)) == "c",
            $"Navegador: sesiones por día, hora de Madrid y búsqueda sin acentos ({string.Join("|", ng.Select(g => g.Title))})");

        var monday = TrainingCalendar.WeekStart(d);
        var wk = TrainingCalendar.WeekGrid(monday, new List<CalendarEntry>
        {
            new("a", d, "Zakina", 0, 0, null), new("b", d.AddHours(-1), "Maalwina", 0, 0, null), new("c", d.AddDays(7), "Otra semana", 0, 0, null),
        }, d);
        assert(TrainingCalendar.WeekTitle(monday) == "3 – 9 nov 2025" && string.Join(",", wk.Select(x => x.Day)) == "3,4,5,6,7,8,9"
            && string.Join(",", wk[5].Entries.Select(x => x.Id)) == "b,a" && wk[5].IsToday && wk.Sum(x => x.Entries.Count) == 2
            && TrainingCalendar.WeekTitle(TrainingCalendar.WeekStart(DateTimeOffset.FromUnixTimeSeconds(1_761_900_000))) == "27 oct – 2 nov 2025",
            $"Calendario: semana de lunes a domingo ({TrainingCalendar.WeekTitle(monday)})");

        var de = new List<CalendarEntry>
        {
            new("a", d, "Zakina", 2640, 7.84, 0), new("b", d.AddHours(1), "Sin caballo", 3480, 8.60, 0.8),
            new("c", d.AddDays(-1), "Maalwina", 1800, 6.04, null), new("e", d.AddDays(-8), "Zakina", 600, 1.0, 0.9),
        };
        var ds = DashboardSummary.From(de, d.AddHours(2), 3);
        var dc = ds.Latest[0];
        assert(ds.Trainings == 4 && ds.ThisWeek == 3 && ds.Pending == 2 && string.Join(",", ds.Latest.Select(x => x.Id)) == "b,a,c"
            && dc.DayText == "SÁB 8 NOV" && dc.TimeText == "10:20" && dc.DistanceText == "8,60 km" && dc.DurationText == "58 min"
            && string.Join("|", ds.Latest.Select(x => x.Quality)) == "RTK FIX|Sin FIX|Sin analizar",
            $"Dashboard: contadores y últimos entrenamientos ({ds.Trainings}/{ds.ThisWeek}/{ds.Pending} · {dc.DayText} {dc.TimeText} · {dc.Quality})");
    }
}
