namespace Avo.Windows.Core;

/// <summary>Solution type of one GNSS epoch, ordered from worst to best (same states as the Android RtkState).</summary>
public enum GnssSolution
{
    None = 0,
    Autonomous = 1,
    Dgnss = 2,
    RtkFloat = 3,
    RtkFix = 4,
}

public static class GnssQuality
{
    /// <summary>
    /// UBX-NAV-PVT rules: no solution when gnssFixOK is clear, the position is flagged invalid (flags3.invalidLlh) or the
    /// fix type is not 2D/3D/GNSS+DR. Otherwise carrier solution 2 = RTK FIX, 1 = RTK FLOAT, diffSoln = DGNSS, else autonomous.
    /// </summary>
    public static GnssSolution Classify(bool gnssFixOk, int fixType, bool diffSoln, int carrierSolution, bool invalidLlh)
    {
        if (!gnssFixOk || invalidLlh || fixType is < 2 or > 4) return GnssSolution.None;
        return carrierSolution switch
        {
            2 => GnssSolution.RtkFix,
            1 => GnssSolution.RtkFloat,
            _ => diffSoln ? GnssSolution.Dgnss : GnssSolution.Autonomous,
        };
    }

    public static string Name(GnssSolution s) => s switch
    {
        GnssSolution.RtkFix => "RTK FIX",
        GnssSolution.RtkFloat => "RTK FLOAT",
        GnssSolution.Dgnss => "DGNSS",
        GnssSolution.Autonomous => "Autónomo",
        _ => "Sin solución válida",
    };

    /// <summary>Percentage of received epochs per solution type.</summary>
    public static IReadOnlyDictionary<GnssSolution, double> Distribution(IReadOnlyList<GnssEpoch> epochs)
    {
        var d = Enum.GetValues<GnssSolution>().ToDictionary(x => x, _ => 0.0);
        if (epochs.Count == 0) return d;
        foreach (var e in epochs) d[e.Solution]++;
        foreach (var k in d.Keys.ToList()) d[k] = 100.0 * d[k] / epochs.Count;
        return d;
    }
}

/// <summary>Interval of the session without a usable GNSS solution (no epochs, or epochs without a valid fix).</summary>
public sealed record SignalLoss(double T0, double T1, string Reason)
{
    public double DurationS => T1 - T0;
}
