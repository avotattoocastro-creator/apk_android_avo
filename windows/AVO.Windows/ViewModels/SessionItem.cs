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
    public SessionTimeline Timeline { get; }
    public ImuTimeline Imu { get; }
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
        Session = s; Timeline = tl; Imu = imu;
    }

    public string Id => Session.SessionId;
    public string Horse => Session.Horse;
    public string Rider => Session.Rider;
    public DateTimeOffset? Start => Timeline.Utc0 ?? Session.StartedAt;
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
