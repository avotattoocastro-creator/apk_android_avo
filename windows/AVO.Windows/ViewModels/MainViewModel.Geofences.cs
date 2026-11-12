using System.Collections.ObjectModel;
using System.IO;
using System.Windows.Input;
using System.Windows.Media;
using Avo.Windows.Ble;
using Avo.Windows.Controls;
using Avo.Windows.Core;
using Avo.Windows.Core.Watch;

namespace Avo.Windows.ViewModels;

/// <summary>One of the 8 geofence slots of the watch, as edited on the PC.</summary>
public sealed class FenceSlotVm(int index) : ObservableObject
{
    public int Index { get; } = index;
    public string Number => (Index + 1).ToString();
    public PlanFence? Fence { get; set; }
    public bool IsEmpty => Fence is null;
    public string Title => Fence is null ? $"Hueco {Index + 1} · libre" : $"{Index + 1}. {Fence.Name}";
    public string Detail => Fence is null ? "Sin geocerca" :
        Fence.Type == FenceType.Circle ? $"Círculo · radio {Fence.RadiusM:0} m{(Fence.Active ? " · activa" : " · inactiva")}"
                                       : $"Polígono · {Fence.Vertices.Count} vértices{(Fence.Active ? " · activa" : " · inactiva")}";
    public string? Problem => Fence?.Problem();
    public bool HasProblem => Problem is not null;
    public void Refresh() => RaiseMany(nameof(IsEmpty), nameof(Title), nameof(Detail), nameof(Problem), nameof(HasProblem));
}

/// <summary>One of the 4 virtual lines of the watch.</summary>
public sealed class LineSlotVm(int index, PlanLine line) : ObservableObject
{
    public int Index { get; } = index;
    public PlanLine Line { get; set; } = line;
    public string Title => $"Línea {Index + 1} · {Line.Name}";
    public string Detail => !Line.Enabled ? "Desactivada" :
        Line.A is null || Line.B is null ? "Marca A y B en el mapa" :
        $"{Line.LengthM:0} m · {DirectionText(Line.Direction)}{(Index == 0 ? " · el reloj cronometra vueltas" : "")}";
    public static string DirectionText(LineDirection d) => d switch
    {
        LineDirection.LeftToRight => "marca solo en el sentido de la flecha",
        LineDirection.RightToLeft => "marca solo en sentido contrario",
        _ => "marca en ambos sentidos",
    };
    public string? Problem => Line.Problem();
    public bool HasProblem => Problem is not null;
    public void Refresh() => RaiseMany(nameof(Title), nameof(Detail), nameof(Problem), nameof(HasProblem));
}

public sealed record CrossingRow(string Line, string Time, string Direction, bool Counts, string CountsText);
public sealed record RunRow(string Kind, string Start, string Duration);

public sealed partial class MainViewModel
{
    public GeofencePlan GeoPlan { get; private set; } = null!;
    private string GeoPlanFile => Path.Combine(Paths.Root, "geocercas.json");
    public ObservableCollection<FenceSlotVm> FenceSlots { get; } = [];
    public ObservableCollection<LineSlotVm> LineSlots { get; } = [];
    public ObservableCollection<CrossingRow> CrossingRows { get; } = [];
    public ObservableCollection<RunRow> RunRows { get; } = [];
    public LineDirection[] LineDirections { get; } = [LineDirection.Both, LineDirection.LeftToRight, LineDirection.RightToLeft];
    public LineRole[] LineRoles { get; } = [LineRole.StartFinish, LineRole.Start, LineRole.Finish, LineRole.Checkpoint];

    public ICommand MapClickCommand { get; private set; } = null!;
    public ICommand NewCircleCommand { get; private set; } = null!;
    public ICommand NewPolygonCommand { get; private set; } = null!;
    public ICommand UndoVertexCommand { get; private set; } = null!;
    public ICommand ClearShapeCommand { get; private set; } = null!;
    public ICommand DeleteFenceCommand { get; private set; } = null!;
    public ICommand SendToWatchCommand { get; private set; } = null!;
    public ICommand ReadFromWatchCommand { get; private set; } = null!;
    public ICommand LinesToSegmentsCommand { get; private set; } = null!;

    private void InitGeofences()
    {
        GeoPlan = GeofencePlan.Load(GeoPlanFile);
        for (int i = 0; i < Core.Watch.Fence.MaxFences; i++) FenceSlots.Add(new FenceSlotVm(i) { Fence = GeoPlan.Fences[i] });
        for (int i = 0; i < 4; i++) LineSlots.Add(new LineSlotVm(i, GeoPlan.Lines[i]));
        MapClickCommand = new RelayCommand(p => { if (p is MapClick c) OnGeoClick(c); });
        NewCircleCommand = new RelayCommand(() => NewFence(FenceType.Circle), () => SelectedFenceSlot is not null);
        NewPolygonCommand = new RelayCommand(() => NewFence(FenceType.Polygon), () => SelectedFenceSlot is not null);
        UndoVertexCommand = new RelayCommand(() =>
        {
            if (SelectedFenceSlot?.Fence is { Type: FenceType.Polygon, Vertices.Count: > 0 } f) { f.Vertices.RemoveAt(f.Vertices.Count - 1); GeoChanged(); }
        });
        ClearShapeCommand = new RelayCommand(() =>
        {
            if (SelectedFenceSlot?.Fence is { } f) { f.Center = null; f.Vertices.Clear(); GeoChanged(); }
            else if (SelectedLineSlot is { } l) { l.Line.A = null; l.Line.B = null; GeoChanged(); }
        });
        DeleteFenceCommand = new RelayCommand(() =>
        {
            if (SelectedFenceSlot is not { Fence: not null } s) return;
            if (!Dialogs.Confirm("Geocercas", $"¿Vaciar el hueco {s.Index + 1} («{s.Fence.Name}»)? En el reloj se borrará al enviar.")) return;
            s.Fence = null; GeoPlan.Fences[s.Index] = null; GeoChanged();
        });
        SendToWatchCommand = new AsyncCommand(_ => SendGeofencesAsync(), Fail);
        ReadFromWatchCommand = new AsyncCommand(_ => ReadGeofencesAsync(), Fail);
        LinesToSegmentsCommand = new RelayCommand(LinesToSegments, () => Selected is not null && RunRows.Count > 0);
        SelectedFenceSlot = FenceSlots[0];
        RefreshGeo();
    }

    // ------------------------------------------------------------------ selection / editing
    private FenceSlotVm? _selFence;
    public FenceSlotVm? SelectedFenceSlot
    {
        get => _selFence;
        set
        {
            if (!Set(ref _selFence, value)) return;
            if (value is not null && _selLine is not null) { _selLine = null; Raise(nameof(SelectedLineSlot)); }
            RaiseGeoEditor();
        }
    }
    private LineSlotVm? _selLine;
    public LineSlotVm? SelectedLineSlot
    {
        get => _selLine;
        set
        {
            if (!Set(ref _selLine, value)) return;
            if (value is not null && _selFence is not null) { _selFence = null; Raise(nameof(SelectedFenceSlot)); }
            RaiseGeoEditor();
        }
    }
    public bool EditingFence => SelectedFenceSlot is not null;
    public bool EditingFenceShape => SelectedFenceSlot?.Fence is not null;
    public bool EditingLine => SelectedLineSlot is not null;
    public bool EditingCircle => SelectedFenceSlot?.Fence?.Type == FenceType.Circle;
    public bool EditingPolygon => SelectedFenceSlot?.Fence?.Type == FenceType.Polygon;

    public string GeoHint => SelectedFenceSlot switch
    {
        { Fence: null } => "Hueco libre: elige «Círculo» o «Polígono» y haz clic en el mapa.",
        { Fence.Type: FenceType.Circle } => "Clic en el mapa = centro del círculo. Ajusta el radio abajo.",
        { Fence.Type: FenceType.Polygon } => $"Clic en el mapa = nuevo vértice ({SelectedFenceSlot.Fence!.Vertices.Count}/{Core.Watch.Fence.MaxVertices}). El polígono se cierra solo.",
        _ => SelectedLineSlot is { } l
            ? (l.Line.A is null ? "Clic en el mapa = extremo A de la línea." : l.Line.B is null ? "Clic en el mapa = extremo B de la línea." : "Clic en el mapa = empezar de nuevo por el extremo A.")
            : "Elige una geocerca o una línea a la izquierda.",
    };
    public string GeoProblem => SelectedFenceSlot?.Problem ?? SelectedLineSlot?.Problem ?? (EditingFenceShape || EditingLine ? "Correcto: se puede enviar" : "");
    public bool GeoProblemOk => (SelectedFenceSlot?.Problem ?? SelectedLineSlot?.Problem) is null;

    // fence fields
    public string FenceName
    {
        get => SelectedFenceSlot?.Fence?.Name ?? "";
        set { if (SelectedFenceSlot?.Fence is { } f) { f.Name = value.Length > 15 ? value[..15] : value; GeoChanged(false); } }
    }
    public double FenceRadius
    {
        get => SelectedFenceSlot?.Fence?.RadiusM ?? 50;
        set { if (SelectedFenceSlot?.Fence is { } f) { f.RadiusM = Math.Clamp(Math.Round(value), 5, 5000); GeoChanged(); } }
    }
    public bool FenceActive
    {
        get => SelectedFenceSlot?.Fence?.Active ?? false;
        set { if (SelectedFenceSlot?.Fence is { } f) { f.Active = value; GeoChanged(); } }
    }
    public bool GeoAuto
    {
        get => GeoPlan.AutoEnabled;
        set { GeoPlan.AutoEnabled = value; GeoChanged(false); }
    }
    // line fields
    public string LineName
    {
        get => SelectedLineSlot?.Line.Name ?? "";
        set { if (SelectedLineSlot is { } l) { l.Line.Name = value.Length > 30 ? value[..30] : value; GeoChanged(false); } }
    }
    public bool LineEnabled
    {
        get => SelectedLineSlot?.Line.Enabled ?? false;
        set { if (SelectedLineSlot is { } l) { l.Line.Enabled = value; GeoChanged(); } }
    }
    public LineRole SelectedLineRole
    {
        get => SelectedLineSlot?.Line.Role ?? LineRole.StartFinish;
        set { if (SelectedLineSlot is { } l) { l.Line.Role = value; GeoChanged(); } }
    }
    public LineDirection SelectedLineDirection
    {
        get => SelectedLineSlot?.Line.Direction ?? LineDirection.Both;
        set { if (SelectedLineSlot is { } l) { l.Line.Direction = value; GeoChanged(); } }
    }

    private void RaiseGeoEditor() => RaiseMany(nameof(EditingFence), nameof(EditingFenceShape), nameof(EditingLine), nameof(EditingCircle), nameof(EditingPolygon),
        nameof(GeoHint), nameof(GeoProblem), nameof(GeoProblemOk), nameof(FenceName), nameof(FenceRadius), nameof(FenceActive), nameof(LineName), nameof(LineEnabled),
        nameof(SelectedLineRole), nameof(SelectedLineDirection), nameof(GeoShapes));

    private void NewFence(FenceType type)
    {
        if (SelectedFenceSlot is not { } s) return;
        var old = s.Fence;
        var f = new PlanFence { Type = type, Name = old?.Name is { Length: > 0 } n ? n : $"Geocerca {s.Index + 1}", Active = old?.Active ?? true, RadiusM = old?.RadiusM ?? 50 };
        if (old is not null && old.Type == type) return;
        if (old is not null && type == FenceType.Circle && old.Vertices.Count > 0)
            f.Center = new PlanPoint(old.Vertices.Average(v => v.Lat), old.Vertices.Average(v => v.Lon));
        s.Fence = f; GeoPlan.Fences[s.Index] = f;
        GeoChanged();
    }

    private void OnGeoClick(MapClick c)
    {
        var pt = new PlanPoint(Math.Round(c.Lat, 7), Math.Round(c.Lon, 7));
        if (SelectedFenceSlot is { } s)
        {
            if (s.Fence is null) NewFence(FenceType.Circle);
            var f = s.Fence!;
            if (f.Type == FenceType.Circle) f.Center = pt;
            else if (f.Vertices.Count < Core.Watch.Fence.MaxVertices) f.Vertices.Add(pt);
            GeoChanged();
        }
        else if (SelectedLineSlot is { } l)
        {
            if (l.Line.A is null) l.Line.A = pt;
            else if (l.Line.B is null) { l.Line.B = pt; l.Line.Enabled = true; }
            else { l.Line.A = pt; l.Line.B = null; }
            GeoChanged();
        }
    }

    private void GeoChanged(bool redraw = true)
    {
        foreach (var f in FenceSlots) f.Refresh();
        foreach (var l in LineSlots) l.Refresh();
        try { GeoPlan.Save(GeoPlanFile); }
        catch (IOException ex) { Log.Warn("geocercas", ex.Message, ex); }
        RaiseGeoEditor();
        if (redraw) RefreshCrossings();
        RaiseMany(nameof(GeoSummary), nameof(GeoProblems));
    }

    public string GeoSummary
    {
        get
        {
            int f = GeoPlan.Fences.Count(x => x is not null), l = GeoPlan.Lines.Count(x => x.Enabled);
            return $"{f} geocerca(s) · {l} línea(s) activas · grabación automática {(GeoPlan.AutoEnabled ? "sí" : "no")}"
                   + (GeoPlan.LastSent is { } d ? $" · último envío {MadridTime.Format(d, "dd/MM/yyyy HH:mm")} a {GeoPlan.LastSentTo}" : " · sin enviar todavía");
        }
    }
    public string GeoProblems => GeoPlan.Problems() is { Count: > 0 } p ? string.Join("\n", p) : "";

    // ------------------------------------------------------------------ map
    private static readonly Color[] FenceColors = [Color.FromRgb(0xED, 0x12, 0x2A), Color.FromRgb(0x3D, 0x9B, 0xFF), Color.FromRgb(0x2E, 0xD1, 0x9A), Color.FromRgb(0xF2, 0xA3, 0x3A),
        Color.FromRgb(0xB0, 0x7C, 0xFF), Color.FromRgb(0x00, 0xC8, 0xE0), Color.FromRgb(0xFF, 0x6F, 0xB5), Color.FromRgb(0xC9, 0xCB, 0xD1)];

    public IReadOnlyList<MapShape> GeoShapes
    {
        get
        {
            var r = new List<MapShape>();
            for (int i = 0; i < FenceSlots.Count; i++)
            {
                var f = FenceSlots[i].Fence;
                if (f is null) continue;
                bool sel = SelectedFenceSlot?.Index == i;
                var c = FenceColors[i];
                IReadOnlyList<(double, double)> pts = f.Type == FenceType.Circle
                    ? f.Center is null ? [] : f.ToWatch(i).Outline().Select(p => (p.Lat, p.Lon)).ToList()
                    : f.Vertices.Select(v => (v.Lat, v.Lon)).ToList();
                if (pts.Count == 0) continue;
                r.Add(new MapShape
                {
                    Points = pts, Closed = pts.Count > 2, Stroke = sel ? Colors.White : c, Fill = Color.FromArgb((byte)(f.Active ? (sel ? 0x55 : 0x33) : 0x14), c.R, c.G, c.B),
                    Thickness = sel ? 3.5 : 2.5, Label = $"{i + 1}. {f.Name}", ShowVertices = sel && f.Type == FenceType.Polygon,
                });
                if (sel && f.Type == FenceType.Circle && f.Center is { } ctr) r.Add(new MapShape { Points = [(ctr.Lat, ctr.Lon)], Stroke = c });
            }
            for (int i = 0; i < LineSlots.Count; i++)
            {
                var l = LineSlots[i].Line;
                var pts = new List<(double, double)>();
                if (l.A is not null) pts.Add((l.A.Lat, l.A.Lon));
                if (l.B is not null) pts.Add((l.B.Lat, l.B.Lon));
                if (pts.Count == 0) continue;
                bool sel = SelectedLineSlot?.Index == i;
                var c = l.Enabled ? Color.FromRgb(0xFF, 0xD5, 0x4A) : Color.FromRgb(0x8F, 0x9B, 0xAD);
                r.Add(new MapShape
                {
                    Points = pts, Stroke = sel ? Colors.White : c, Thickness = sel ? 4 : 3, ShowVertices = true, EndLabels = pts.Count == 2, Label = l.Name,
                    Arrow = pts.Count < 2 ? 0 : l.Direction switch { LineDirection.LeftToRight => 1, LineDirection.RightToLeft => -1, _ => 2 },
                });
            }
            return r;
        }
    }

    // ------------------------------------------------------------------ crossings in the active training
    public string CrossingsTitle => Selected is null ? "Cruces de líneas (abre un entrenamiento)" : $"Cruces de líneas en {Selected.DateTimeText}";
    public string CrossingsEmpty => Selected is null ? "Abre un entrenamiento para ver por dónde cruzó las líneas." :
        GeoPlan.Lines.All(l => !l.Enabled || l.A is null || l.B is null) ? "No hay líneas activas con sus dos extremos." :
        CrossingRows.Count == 0 ? "El recorrido de este entrenamiento no cruza ninguna línea activa." : "";

    private void RefreshCrossings()
    {
        CrossingRows.Clear(); RunRows.Clear();
        if (Selected is { Timeline.Count: > 1 } s)
        {
            var all = new List<LineCrossing>();
            for (int i = 0; i < 4; i++)
                if (GeoPlan.Lines[i] is { Enabled: true, A: not null, B: not null } l) all.AddRange(LineAnalysis.Detect(s.Timeline, l, i));
            foreach (var c in all.OrderBy(c => c.T))
                CrossingRows.Add(new CrossingRow(GeoPlan.Lines[c.Line].Name, Core.TimeText.Clock(c.T), c.LeftToRight ? "Sentido de la flecha" : "Sentido contrario",
                    c.Counts, c.Counts ? "Marca" : "No marca"));
            foreach (var r in LineAnalysis.Runs(GeoPlan.Lines, all))
                RunRows.Add(new RunRow(r.Kind, Core.TimeText.Clock(r.T0), Core.TimeText.Clock(r.DurationS)));
        }
        RaiseMany(nameof(CrossingsTitle), nameof(CrossingsEmpty), nameof(GeoShapes));
    }

    private void RefreshGeo()
    {
        foreach (var f in FenceSlots) f.Refresh();
        foreach (var l in LineSlots) l.Refresh();
        RaiseGeoEditor();
        RefreshCrossings();
        RaiseMany(nameof(GeoSummary), nameof(GeoProblems));
    }

    private void LinesToSegments()
    {
        if (Selected is null) return;
        var all = new List<LineCrossing>();
        for (int i = 0; i < 4; i++)
            if (GeoPlan.Lines[i] is { Enabled: true, A: not null, B: not null } l) all.AddRange(LineAnalysis.Detect(Selected.Timeline, l, i));
        var defs = LineAnalysis.Runs(GeoPlan.Lines, all).Select(r => new SegmentDefinition { Name = r.Kind, T0 = r.T0, T1 = r.T1, Kind = SegmentKind.Lines, Notes = "Creado desde las líneas de salida/meta" });
        AddDefs(defs, true, SegmentKind.Lines);
        Page = "Segments";
    }

    // ------------------------------------------------------------------ watch (Bluetooth)
    private string _watchLink = "Reloj: sin conectar. «Enviar al reloj» lo busca por Bluetooth.";
    public string WatchLinkStatus { get => _watchLink; private set => Set(ref _watchLink, value); }
    private bool _watchBusy;
    public bool WatchBusy { get => _watchBusy; private set => Set(ref _watchBusy, value); }
    private string WatchFile => Path.Combine(Paths.Root, "reloj", "reloj_ble.txt");

    /// <summary>Connects to the watch (scan, pair, authorize this PC with BOOT if needed) and runs <paramref name="work"/>.</summary>
    private async Task WithWatchAsync(Func<AvoClient, string, Task> work)
    {
        if (WatchBusy) return;
        WatchBusy = true;
        var progress = new Progress<string>(m => { WatchLinkStatus = m; Status = m; });
        WinBleTransport? t = null;
        try
        {
            IProgress<string> p = progress;
            p.Report("Buscando el reloj por Bluetooth (acerca el reloj al PC)…");
            var found = await WinBleScanner.ScanAsync(TimeSpan.FromSeconds(6), CancellationToken.None);
            ulong? remembered = null;
            try { if (File.Exists(WatchFile) && ulong.TryParse(File.ReadAllText(WatchFile).Trim(), out var a)) remembered = a; } catch (IOException) { }
            var target = found.FirstOrDefault(f => f.Address == remembered) ?? (found.Count == 1 ? found[0] : null);
            if (target is null && found.Count > 1)
            {
                target = found[0];
                if (!Dialogs.Confirm("Reloj AVO", $"Hay {found.Count} relojes cerca: {string.Join(", ", found.Select(f => $"{f.Name} ({f.Rssi} dBm)"))}.\n\n¿Usar el más cercano, {target.Name}?")) return;
            }
            if (target is null) throw new IOException("No se encontró ningún reloj AVO. Enciéndelo, acércalo al PC y cierra la app del móvil si está conectada (el reloj admite una sola conexión).");
            t = await WinBleTransport.ConnectAsync(target.Address, p, CancellationToken.None);
            var client = new AvoClient(t);
            t.Notification += client.OnNotification;
            t.Disconnected += client.OnDisconnected;
            var info = await WatchAuthorizer.EnsureAsync(client, new DpapiCredentialStore(Path.Combine(Paths.Root, "reloj")), $"AVO Windows {System.Environment.MachineName}", p, CancellationToken.None);
            if (!info.SupportsFences) throw new IOException($"El reloj {info.Firmware} no admite geocercas por Bluetooth.");
            Directory.CreateDirectory(Path.GetDirectoryName(WatchFile)!);
            File.WriteAllText(WatchFile, target.Address.ToString());
            await work(client, $"{target.Name} · pecho {info.Firmware}");
        }
        catch (Exception ex) when (ex is IOException or BleRequestException or InvalidOperationException or UnauthorizedAccessException or System.Runtime.InteropServices.COMException)
        {
            WatchLinkStatus = "Reloj: " + ex.Message;
            Log.Warn("reloj", ex.Message, ex);
            Dialogs.Show("Reloj AVO", ex.Message, true);
        }
        finally
        {
            t?.Dispose();
            WatchBusy = false;
        }
    }

    private Task SendGeofencesAsync()
    {
        var problems = GeoPlan.Problems();
        if (problems.Count > 0) { Dialogs.Show("Geocercas", "Corrige antes de enviar:\n\n" + string.Join("\n", problems), true); return Task.CompletedTask; }
        return WithWatchAsync(async (client, who) =>
        {
            var cur = WatchConfig.Decode(await client.GetConfigAsync());
            var diff = GeofenceSync.Differences(GeoPlan, cur);
            if (diff.Count == 0) { WatchLinkStatus = $"{who}: ya tiene exactamente estas geocercas y líneas."; return; }
            string dirNote = GeoPlan.Lines.Any(l => l.Enabled && l.Direction != LineDirection.Both)
                ? "\n\nAviso: el reloj cuenta los cruces de las líneas en los DOS sentidos (su firmware no guarda sentido). El sentido elegido se aplica al analizar el entrenamiento en este PC."
                : "";
            if (!Dialogs.Confirm("Enviar al reloj", $"Se cambiará en {who}: {string.Join(", ", diff)}.{dirNote}\n\n¿Enviar?")) { WatchLinkStatus = "Envío cancelado."; return; }
            var rep = await GeofenceSync.SendAsync(client, GeoPlan, new Progress<string>(m => WatchLinkStatus = m), CancellationToken.None);
            if (rep.Verified)
            {
                GeoPlan.LastSent = DateTimeOffset.UtcNow; GeoPlan.LastSentTo = who;
                GeoChanged(false);
            }
            WatchLinkStatus = (rep.Verified ? "Enviado y comprobado: " : "Enviado con diferencias: ") + string.Join(" · ", rep.Steps);
            Log.Info("reloj", "geocercas enviadas", new { who, rep.Verified, steps = rep.Steps });
        });
    }

    private Task ReadGeofencesAsync() => WithWatchAsync(async (client, who) =>
    {
        var cur = WatchConfig.Decode(await client.GetConfigAsync());
        if (GeofenceSync.Differences(GeoPlan, cur) is { Count: > 0 } d &&
            !Dialogs.Confirm("Leer del reloj", $"Lo que tienes en el PC se sustituirá por lo del reloj ({string.Join(", ", d)}). Los sentidos y nombres de las líneas se conservan. ¿Continuar?")) return;
        GeoPlan.LoadFrom(cur);
        for (int i = 0; i < FenceSlots.Count; i++) FenceSlots[i].Fence = GeoPlan.Fences[i];
        GeoChanged();
        WatchLinkStatus = $"Leído de {who}.";
    });

    /// <summary>Capture mode: an example plan over the demo track (clearly named).</summary>
    public void LoadExampleGeofences()
    {
        var s = Selected;
        if (s is not { Timeline.Count: > 10 }) return;
        var tl = s.Timeline;
        double latC = tl.Lat.Where(double.IsFinite).Average(), lonC = tl.Lon.Where(double.IsFinite).Average();
        GeoPlan.Fences[0] = new PlanFence { Name = "Playa (demo)", Type = FenceType.Circle, Center = new PlanPoint(latC, lonC), RadiusM = 600 };
        int a = tl.Count / 5, b = tl.Count / 5 + 3;
        var fr = new LocalFrame(tl.Lat[a], tl.Lon[a]);
        var (dx, dy) = fr.ToXY(tl.Lat[b], tl.Lon[b]);
        double len = Math.Max(1, Math.Sqrt(dx * dx + dy * dy));
        var p1 = fr.ToPoint(-dy / len * 25, dx / len * 25); var p2 = fr.ToPoint(dy / len * 25, -dx / len * 25);
        GeoPlan.Lines[0] = new PlanLine { Enabled = true, Name = "Salida / meta (demo)", Role = LineRole.StartFinish, A = new(p1.Lat, p1.Lon), B = new(p2.Lat, p2.Lon), Direction = LineDirection.LeftToRight };
        for (int i = 0; i < FenceSlots.Count; i++) FenceSlots[i].Fence = GeoPlan.Fences[i];
        LineSlots[0].Line = GeoPlan.Lines[0];
        SelectedLineSlot = LineSlots[0];
        GeoChanged();
    }
}
