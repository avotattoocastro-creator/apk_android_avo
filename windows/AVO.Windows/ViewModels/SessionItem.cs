using System.Collections.ObjectModel;
using System.Globalization;
using System.Windows.Media;
using Avo.Windows.Core;

namespace Avo.Windows.ViewModels;

/// <summary>One imported training with its derived (never persisted over the original) analysis objects.</summary>
public sealed class SessionItem : ObservableObject
{
    private static readonly CultureInfo Es = CultureInfo.GetCultureInfo("es-ES");
    public TrainingSession Session { get; }
    /// <summary>Whole recording, never trimmed.</summary>
    public SessionTimeline FullTimeline { get; }
    /// <summary>Analysed part: the whole recording or the start–end window chosen by the user (same time base).</summary>
    public SessionTimeline Timeline { get; private set; }
    public ImuTimeline Imu { get; private set; }
    public double? WindowStart { get; private set; }
    public double? WindowEnd { get; private set; }
    public bool IsTrimmed => WindowStart is not null && WindowEnd is not null;
    public string WindowText => IsTrimmed
        ? $"Entrenamiento útil {Core.TimeText.Clock(WindowStart!.Value)} – {Core.TimeText.Clock(WindowEnd!.Value)} de {Core.TimeText.Clock(FullTimeline.Count > 1 ? FullTimeline.T[^1] : 0)}"
        : $"Archivo completo · {Core.TimeText.Clock(FullTimeline.Count > 1 ? FullTimeline.T[^1] : 0)}";

    /// <summary>Applies (or clears with nulls) the useful window. Runs the analysis again on the filtered copy; the file is untouched.</summary>
    public void ApplyWindow(double? start, double? end, SpeedSmoother.Parameters p)
    {
        if (start is double a && end is double b && b - a >= 5 && FullTimeline.Count > 1)
        {
            WindowStart = Math.Max(a, FullTimeline.T[0]); WindowEnd = Math.Min(b, FullTimeline.T[^1]);
            var cut = SessionWindow.Apply(Session, FullTimeline.Itow0Ms, WindowStart.Value, WindowEnd.Value);
            Timeline = SessionTimeline.Build(cut, p, FullTimeline.Itow0Ms);
            Imu = ImuTimeline.Build(cut, Timeline, WindowStart.Value, WindowEnd.Value);
        }
        else
        {
            WindowStart = WindowEnd = null;
            Timeline = FullTimeline;
            Imu = _fullImu;
        }
        RaiseMany(nameof(Timeline), nameof(Imu), nameof(WindowStart), nameof(WindowEnd), nameof(IsTrimmed), nameof(WindowText), nameof(Start), nameof(DateText),
            nameof(DateTimeText), nameof(TimeText), nameof(DistanceKmValue), nameof(DistanceText), nameof(DurationText), nameof(MaxSpeedKmh), nameof(MaxSpeedText),
            nameof(MeanSpeedText), nameof(FixPercent), nameof(FixText), nameof(GirthText), nameof(Summary), nameof(GaitByIndex));
    }
    private readonly ImuTimeline _fullImu;
    public ObservableCollection<SegmentDefinition> SegmentDefs { get; } = [];

    private EquineAnalysis? _engine;
    public EquineAnalysis? Engine { get => _engine; set { if (Set(ref _engine, value)) RaiseMany(nameof(EngineOffsetS), nameof(GirthText), nameof(GaitByIndex)); } }
    /// <summary>engine time = timeline time + offset.</summary>
    public double EngineOffsetS => Engine?.Itow0Ms is long e0 ? SessionTimeline.WeekDiffMs(Timeline.Itow0Ms, e0) / 1000.0 : 0;

    private string _engineState = "Pendiente";
    public string EngineState { get => _engineState; set => Set(ref _engineState, value); }

    private string _notes = "";
    public string Notes { get => _notes; set => Set(ref _notes, value); }

    private bool _favorite;
    public bool IsFavorite { get => _favorite; set => Set(ref _favorite, value); }

    private bool _compare;
    public bool IsCompared { get => _compare; set => Set(ref _compare, value); }
    public Color CompareColor { get; set; } = Color.FromRgb(0x3D, 0x9B, 0xFF);
    public string ImportStatus { get; set; } = "";

    public SessionItem(TrainingSession s, SessionTimeline tl, ImuTimeline imu)
    {
        Session = s; FullTimeline = tl; Timeline = tl; Imu = imu; _fullImu = imu;
    }

    public string Id => Session.SessionId;
    /// <summary>Name shown (Cuadra/Jinetes when known, otherwise what the file carries).</summary>
    public string Horse => Session.Horse;
    public string Rider => Session.Rider;
    public string? HorseCode { get; private set; }
    public string? RiderCode { get; private set; }
    public bool HorseKnown { get; private set; }
    public bool RiderKnown { get; private set; }
    public string IdentitySource { get; private set; } = "";
    public void SetIdentity(ResolvedIdentity h, ResolvedIdentity r)
    {
        HorseCode = h.Code; RiderCode = r.Code; HorseKnown = h.Known; RiderKnown = r.Known;
        IdentitySource = $"Caballo: {h.Source} · Jinete: {r.Source}";
        RaiseMany(nameof(Horse), nameof(Rider), nameof(HorseCode), nameof(RiderCode), nameof(HorseKnown), nameof(RiderKnown), nameof(IdentitySource), nameof(Summary), nameof(NeedsIdentity));
    }
    public bool NeedsIdentity => !HorseKnown || !RiderKnown;
    /// <summary>Start of the recording (date of the training; not moved by the useful-window trim).</summary>
    public DateTimeOffset? Start => FullTimeline.Utc0 ?? Session.StartedAt;
    public string DateText => MadridTime.Format(Start, "dd/MM/yyyy");
    public string DateTimeText => MadridTime.Format(Start, "dd/MM/yyyy HH:mm");
    public string TimeText => MadridTime.Format(Start, "HH:mm");
    public double DistanceKmValue => Timeline.Count > 1 ? Timeline.TotalDistanceM / 1000 : (Session.DeclaredDistanceM ?? 0) / 1000;
    public string DistanceText => DistanceKmValue.ToString("0.00", Es) + " km";
    public string DurationText => Core.TimeText.Clock(Timeline.Count > 1 ? Timeline.DurationS : Session.DurationSeconds);
    public double MaxSpeedKmh => Timeline.Count > 0 ? Stats.MaxFinite(Timeline.SpeedFiltered, 0) * 3.6 : Session.MaxSpeedKmh;
    public string MaxSpeedText => MaxSpeedKmh.ToString("0.0", Es) + " km/h";
    public string MeanSpeedText
    {
        get
        {
            if (Timeline.Count < 2) return "Sin datos";
            var m = SegmentAnalyzer.Compute(Timeline, new SegmentDefinition { T0 = Timeline.T[0], T1 = Timeline.T[^1] });
            return TextOf(m.MeanSpeedKmh, "0.0", " km/h");
        }
    }
    public double FixPercent => Timeline.Count > 0 ? Timeline.FractionAtLeast(GnssSolution.RtkFix, double.NegativeInfinity, double.PositiveInfinity) * 100 : 0;
    public string FixText => FixPercent.ToString("0", Es) + " %";
    public bool HasGirth => Imu.Channels.Count > 0 || Session.TotalImuSamples > 0;
    public string GirthText => Imu.Channels.Count > 0 ? $"{Imu.Channels.Count}/3 IMU · {Imu.SampleRateHz:0} Hz" : Session.TotalImuSamples > 0 ? $"{Session.TotalImuSamples} muestras (formato no decodificado)" : "Sin datos de cincha";
    public string Kind => Session.IsSynthetic ? "DEMOSTRACIÓN" : "Medido";
    public bool IsSynthetic => Session.IsSynthetic;
    public string Integrity => Session.Integrity;
    public string Discipline => string.IsNullOrWhiteSpace(Session.Discipline) ? "Playa" : Session.Discipline;
    public string Summary => $"{Horse} · {DateTimeText} · {DistanceText}";

    /// <summary>Gait code (engine) for each timeline index; -1 when unknown or without engine/girth.</summary>
    public int[] GaitByIndex
    {
        get
        {
            var r = new int[Timeline.Count];
            Array.Fill(r, -1);
            if (Engine is null || !Engine.HasImu) return r;
            double off = EngineOffsetS;
            for (int i = 0; i < r.Length; i++) r[i] = Engine.GaitAt(Timeline.T[i] + off);
            return r;
        }
    }

    public static string TextOf(double? v, string fmt, string unit = "") => Core.TimeText.Num(v, fmt, unit);
}
