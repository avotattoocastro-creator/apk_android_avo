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
    "trabajo_pista":{"trabajos":{"v_max":18.0555,"mejor_200m_s":11.36,"lista":[
    {"id":1,"t0":10,"t1":110,"mejores":[{"distancia_m":200,"tiempo_s":11.36},{"distancia_m":600,"tiempo_s":35.31},{"distancia_m":1000,"tiempo_s":60.42}],"l_max_m":7.3,"f_max_hz":2.36},
    {"id":2,"t0":300,"t1":380,"mejores":[{"distancia_m":200,"tiempo_s":12.1},{"distancia_m":600,"tiempo_s":37.0}],"l_max_m":6.9}]}}}
    """;

    public static void Run(Action<bool, string> assert)
    {
        var k = KeyData.From(Json);
        string V(string id) => k.Tiles.FirstOrDefault(t => t.Id == id)?.Value ?? "?";
        assert(k.HasEngine, "Datos clave: resultado del motor reconocido");
        assert(V("vmax") == "65,0" && V("best200") == "11,36" && V("best600") == "35,31" && V("best1000") == "60,42",
            $"Datos clave: velocidad y mejores tramos ({V("vmax")} · {V("best200")} · {V("best600")} · {V("best1000")})");
        assert(V("distance") == "7,84" && V("duration") == "44:12", $"Datos clave: distancia y duración ({V("distance")} · {V("duration")})");
        assert(V("hrmax") == "—" && V("lmax") == "7,30" && V("fmax") == "2,36", "Datos clave: pulso vacío y tranco del motor");
        assert(string.Join(",", k.Gaits.Select(g => g.Id)) == "PASO,TROTE,GALOPE", "Datos clave: aires en orden y sin tiempo_en_curva");
        assert(k.QualityLabel == "DGNSS" && k.FixShare == 0, "Datos clave: calidad DGNSS y 0 % en FIX");

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
    }
}
