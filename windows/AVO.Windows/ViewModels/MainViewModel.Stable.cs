using System.Collections.ObjectModel;
using System.IO;
using System.Windows;
using System.Windows.Input;
using Avo.Windows.Core;

namespace Avo.Windows.ViewModels;

/// <summary>One horse (Cuadra) or rider (Jinetes) with the totals of its trainings.</summary>
public sealed class IdentityRow : ObservableObject
{
    public IdentityKind Kind { get; }
    public IdentityRecord Record { get; }
    public IdentityRow(IdentityKind kind, IdentityRecord r, IReadOnlyList<SessionItem> sessions)
    {
        Kind = kind; Record = r; Sessions = sessions;
    }
    public IReadOnlyList<SessionItem> Sessions { get; }
    public string Code => Record.Code;
    public string Name => Record.Name;
    public bool IsDemo => Record.Demo;
    public bool Active => Record.Active;
    public bool HasNfc => !string.IsNullOrEmpty(Record.NfcUid);
    public string Initial => string.IsNullOrEmpty(Name) ? "?" : Name[..1].ToUpperInvariant();
    public string Subtitle
    {
        get
        {
            var parts = new List<string> { Code };
            if (Kind == IdentityKind.Horse && !string.IsNullOrWhiteSpace(Record.Breed)) parts.Add(Record.Breed);
            if (Kind == IdentityKind.Horse && Record.BirthYear is int y) parts.Add(y.ToString());
            if (!Record.Active) parts.Add("inactivo");
            return string.Join(" · ", parts);
        }
    }
    public int Count => Sessions.Count;
    public string CountText => Count == 1 ? "1 entrenamiento" : $"{Count} entrenamientos";
    /// <summary>All its trainings; marked when demonstration (synthetic) sessions are included.</summary>
    public string DistanceText => Sessions.Sum(s => s.DistanceKmValue).ToString("0.0", MainViewModel.Es) + " km" + (!IsDemo && Sessions.Any(s => s.IsSynthetic) ? " (demo)" : "");
    public string LastDateText => Sessions.Count == 0 ? "—" : MadridTime.Format(Sessions.Max(s => s.Start), "dd/MM/yyyy");
    public string LastText => Sessions.Count == 0 ? "Sin entrenamientos" : "Último " + MadridTime.Format(Sessions.Max(s => s.Start), "dd/MM/yyyy");
    public string BestSpeedText => Sessions.Count == 0 ? "—" : Sessions.Max(s => s.MaxSpeedKmh).ToString("0.0", MainViewModel.Es) + " km/h";
    public string TotalTimeText => Core.TimeText.Clock(Sessions.Sum(s => s.Timeline.Count > 1 ? s.Timeline.DurationS : s.Session.DurationSeconds));
}

/// <summary>Cuadra or Jinetes page: list, record editor, trainings of the selected record.</summary>
public sealed class IdentityPage : ObservableObject
{
    private readonly MainViewModel _vm;
    public IdentityKind Kind { get; }
    public bool IsHorse => Kind == IdentityKind.Horse;
    public string Title => IsHorse ? "Cuadra" : "Jinetes";
    public string Singular => IsHorse ? "caballo" : "jinete";
    public string NewLabel => IsHorse ? "Nuevo caballo" : "Nuevo jinete";
    public string EmptyText => IsHorse
        ? "Todavía no hay caballos. Crea uno, acerca su etiqueta NFC al lector o importa entrenamientos que lo traigan."
        : "Todavía no hay jinetes. Crea uno, acerca su tarjeta o etiqueta NFC al lector o importa entrenamientos que lo traigan.";
    public ObservableCollection<IdentityRow> Items { get; } = [];
    public ObservableCollection<SessionItem> Trainings { get; } = [];

    public IdentityPage(MainViewModel vm, IdentityKind kind)
    {
        _vm = vm; Kind = kind;
        NewCommand = new RelayCommand(StartNew);
        SaveCommand = new RelayCommand(Save, () => !string.IsNullOrWhiteSpace(EditName));
        DeleteCommand = new RelayCommand(Delete, () => Selected is not null && !IsNew);
        WriteTagCommand = new RelayCommand(() => _vm.ArmTagWrite(this), () => Selected is not null && !IsNew);
        CancelWriteCommand = new RelayCommand(() => _vm.CancelTagWrite());
        OpenTrainingCommand = new RelayCommand(p => { if (p is SessionItem s) { _vm.Selected = s; _vm.Page = "Analysis"; } });
        AssignUnknownCommand = new RelayCommand(() => _vm.AssignUnknownTo(this), () => Selected is not null && !IsNew && UnknownCount > 0);
    }

    public ICommand NewCommand { get; }
    public ICommand SaveCommand { get; }
    public ICommand DeleteCommand { get; }
    public ICommand WriteTagCommand { get; }
    public ICommand CancelWriteCommand { get; }
    public ICommand OpenTrainingCommand { get; }
    public ICommand AssignUnknownCommand { get; }

    private string _search = "";
    public string Search { get => _search; set { if (Set(ref _search, value)) _vm.RefreshStable(); } }
    private bool _showInactive = true;
    public bool ShowInactive { get => _showInactive; set { if (Set(ref _showInactive, value)) _vm.RefreshStable(); } }

    private IdentityRow? _selected;
    public IdentityRow? Selected
    {
        get => _selected;
        set
        {
            if (!Set(ref _selected, value)) return;
            if (value is not null) { IsNew = false; LoadEditor(value.Record); }
            RefreshTrainings();
            RaiseMany(nameof(HasSelection), nameof(Header), nameof(TagText));
        }
    }
    public bool HasSelection => Selected is not null || IsNew;
    public string Header => IsNew ? NewLabel : Selected?.Name ?? "";

    private bool _isNew;
    public bool IsNew { get => _isNew; private set { if (Set(ref _isNew, value)) RaiseMany(nameof(HasSelection), nameof(Header), nameof(CodeEditable)); } }
    public bool CodeEditable => IsNew;

    private string _editCode = "", _editName = "", _editBreed = "", _editYear = "", _editNotes = "", _message = "";
    private bool _editActive = true;
    public string EditCode { get => _editCode; set => Set(ref _editCode, value.ToUpperInvariant()); }
    public string EditName { get => _editName; set => Set(ref _editName, value); }
    public string EditBreed { get => _editBreed; set => Set(ref _editBreed, value); }
    public string EditYear { get => _editYear; set => Set(ref _editYear, value); }
    public string EditNotes { get => _editNotes; set => Set(ref _editNotes, value); }
    public bool EditActive { get => _editActive; set => Set(ref _editActive, value); }
    public string Message { get => _message; set => Set(ref _message, value); }
    public string TagText => Selected?.Record.NfcUid is { Length: > 0 } uid ? "Etiqueta NFC " + uid : "Sin etiqueta NFC asociada";
    public string OriginText => Selected?.Record is { } r ? $"Origen: {r.Origin}{(r.Demo ? " · DEMOSTRACIÓN (datos sintéticos)" : "")}" : "";

    public int UnknownCount => _vm.Sessions.Count(s => !(IsHorse ? s.HorseKnown : s.RiderKnown));
    public string UnknownText => UnknownCount == 0 ? "Todos los entrenamientos tienen " + Singular
        : $"{UnknownCount} entrenamiento(s) sin {Singular}";

    private void LoadEditor(IdentityRecord r)
    {
        EditCode = r.Code; EditName = r.Name; EditBreed = r.Breed; EditYear = r.BirthYear?.ToString() ?? ""; EditNotes = r.Notes; EditActive = r.Active;
        Message = "";
        Raise(nameof(OriginText));
    }

    private void StartNew()
    {
        Selected = null;
        IsNew = true;
        EditCode = _vm.Stable.NextCode(Kind); EditName = ""; EditBreed = ""; EditYear = ""; EditNotes = ""; EditActive = true;
        Message = $"El código {EditCode} es el que se graba en el reloj y en la etiqueta NFC.";
        RaiseMany(nameof(Header), nameof(OriginText), nameof(TagText));
    }

    private void Save()
    {
        int? year = int.TryParse(EditYear.Trim(), out int y) && y is >= 1900 and <= 2100 ? y : null;
        if (IsHorse && !string.IsNullOrWhiteSpace(EditYear) && year is null) { Message = "Año de nacimiento no válido (1900–2100)."; return; }
        try
        {
            string code;
            if (IsNew)
            {
                if (!AvoIdentityTag.CodePattern.IsMatch(EditCode.Trim())) { Message = "Código: de 1 a 23 caracteres, letras, números, «_» o «-»."; return; }
                code = _vm.Stable.Add(Kind, new IdentityRecord
                {
                    Code = EditCode.Trim(), Name = EditName.Trim(), Breed = IsHorse ? EditBreed.Trim() : "", BirthYear = IsHorse ? year : null,
                    Notes = EditNotes.Trim(), Active = EditActive, Origin = "manual",
                }).Code;
                IsNew = false;
            }
            else if (Selected is not null)
            {
                code = Selected.Code;
                _vm.Stable.Update(Kind, code, r =>
                {
                    r.Name = EditName.Trim(); r.Breed = IsHorse ? EditBreed.Trim() : ""; r.BirthYear = IsHorse ? year : null; r.Notes = EditNotes.Trim(); r.Active = EditActive;
                });
            }
            else return;
            _vm.ReapplyIdentities();
            Select(code);
            Message = "Guardado.";
        }
        catch (ArgumentException ex) { Message = ex.Message; }
    }

    private void Delete()
    {
        if (Selected is null) return;
        string name = Selected.Name, code = Selected.Code;
        int n = Selected.Count;
        if (!_vm.Dialogs.Confirm(Title, $"¿Eliminar a {name} ({code})?\n\n{n} entrenamiento(s) volverán a mostrar el {Singular} que trae el archivo. Los archivos no se modifican."))
            return;
        _vm.Stable.Remove(Kind, code);
        _vm.ReapplyIdentities();
        Selected = null;
    }

    public void Select(string code)
    {
        var row = Items.FirstOrDefault(i => i.Code.Equals(code, StringComparison.OrdinalIgnoreCase));
        if (row is null && (!string.IsNullOrEmpty(Search) || !ShowInactive)) { _search = ""; _showInactive = true; RaiseMany(nameof(Search), nameof(ShowInactive)); _vm.RefreshStable(); row = Items.FirstOrDefault(i => i.Code.Equals(code, StringComparison.OrdinalIgnoreCase)); }
        _selected = null;
        Selected = row;
    }

    public void RefreshTrainings()
    {
        Trainings.Clear();
        if (Selected is not null) foreach (var s in Selected.Sessions.OrderByDescending(s => s.Start)) Trainings.Add(s);
        RaiseMany(nameof(UnknownCount), nameof(UnknownText), nameof(TagText), nameof(OriginText));
    }

    /// <summary>Rebuilds the list keeping the selection.</summary>
    public void Rebuild(IReadOnlyList<IdentityRecord> records, IReadOnlyList<SessionItem> sessions)
    {
        string? keep = Selected?.Code;
        Items.Clear();
        string q = Search.Trim();
        foreach (var r in records.OrderByDescending(r => r.Active).ThenBy(r => r.Demo).ThenBy(r => r.Name, StringComparer.CurrentCultureIgnoreCase))
        {
            if (!ShowInactive && !r.Active) continue;
            if (q.Length > 0 && !(r.Name.Contains(q, StringComparison.CurrentCultureIgnoreCase) || r.Code.Contains(q, StringComparison.OrdinalIgnoreCase)
                                  || r.Breed.Contains(q, StringComparison.CurrentCultureIgnoreCase))) continue;
            var mine = sessions.Where(s => string.Equals(IsHorse ? s.HorseCode : s.RiderCode, r.Code, StringComparison.OrdinalIgnoreCase)).ToList();
            Items.Add(new IdentityRow(Kind, r, mine));
        }
        var again = keep is null ? null : Items.FirstOrDefault(i => i.Code == keep);
        _selected = again;
        if (again is not null && !IsNew) LoadEditor(again.Record);
        Raise(nameof(Selected));
        RefreshTrainings();
        RaiseMany(nameof(HasSelection), nameof(Header), nameof(IsEmpty));
    }
    public bool IsEmpty => Items.Count == 0;
}

public sealed partial class MainViewModel
{
    public StableStore Stable { get; private set; } = null!;
    public IdentityPage HorsesPage { get; private set; } = null!;
    public IdentityPage RidersPage { get; private set; } = null!;
    public INfcReader Nfc { get; private set; } = null!;
    public ObservableCollection<string> HorseNames { get; } = [];
    public ObservableCollection<string> RiderNames { get; } = [];

    private void InitStable()
    {
        Stable = new StableStore(Path.Combine(Paths.Root, "cuadra.json"));
        HorsesPage = new IdentityPage(this, IdentityKind.Horse);
        RidersPage = new IdentityPage(this, IdentityKind.Rider);
        OpenAssignCommand = new RelayCommand(p => OpenAssign(p as SessionItem ?? Selected), p => (p as SessionItem ?? Selected) is not null);
        ConfirmAssignCommand = new RelayCommand(ConfirmAssign);
        CancelAssignCommand = new RelayCommand(() => { AssignVisible = false; CancelTagWrite(); });
        ClearAssignCommand = new RelayCommand(() => { AssignHorseText = ""; AssignRiderText = ""; });
        UseNfcReader(new PcscNfcReader());
        RefreshStable();
    }

    /// <summary>Replaces the NFC reader (the capture mode uses a simulated one).</summary>
    public void UseNfcReader(INfcReader reader)
    {
        if (Nfc is not null)
        {
            Nfc.TagEvent -= OnNfcEventBg;
            Nfc.StatusChanged -= OnNfcStatusBg;
            Nfc.Dispose();
        }
        Nfc = reader;
        Nfc.TagEvent += OnNfcEventBg;
        Nfc.StatusChanged += OnNfcStatusBg;
        NfcStatus = Nfc.Status;
        Nfc.Start();
    }
    public void StopNfc() => Nfc?.Dispose();

    private void OnUi(Action a)
    {
        var d = Application.Current?.Dispatcher;
        if (d is null || d.CheckAccess()) a(); else d.BeginInvoke(a);
    }
    // events of a reader that has just been replaced are ignored
    private void OnNfcStatusBg(string s) { var r = Nfc; OnUi(() => { if (ReferenceEquals(r, Nfc)) NfcStatus = s; }); }
    private void OnNfcEventBg(NfcTagEvent e) { var r = Nfc; OnUi(() => { if (ReferenceEquals(r, Nfc)) OnNfcEvent(e); }); }

    private string _nfcStatus = "";
    public string NfcStatus { get => _nfcStatus; private set => Set(ref _nfcStatus, value); }
    private string _nfcLast = "";
    public string NfcLast { get => _nfcLast; private set => Set(ref _nfcLast, value); }
    private bool _nfcLastOk = true;
    public bool NfcLastOk { get => _nfcLastOk; private set => Set(ref _nfcLastOk, value); }

    private (IdentityKind Kind, string Code)? _pendingWrite;
    public bool WriteArmed => _pendingWrite is not null;
    public string WriteArmedText => _pendingWrite is { } w ? $"Acerca la etiqueta para grabar {w.Code}…" : "";

    public void ArmTagWrite(IdentityPage page)
    {
        if (page.Selected is null) return;
        var r = page.Selected.Record;
        var msg = Ndef.UriMessage(AvoIdentityTag.BuildUri(page.Kind, r));
        _pendingWrite = (page.Kind, r.Code);
        Nfc.ArmWrite(msg);
        RaiseMany(nameof(WriteArmed), nameof(WriteArmedText));
        Status = $"Grabar etiqueta: acerca una etiqueta NTAG al lector para {r.Name} ({r.Code})";
    }

    public void CancelTagWrite()
    {
        if (_pendingWrite is null) return;
        Nfc.ArmWrite(null);
        _pendingWrite = null;
        RaiseMany(nameof(WriteArmed), nameof(WriteArmedText));
    }

    private void OnNfcEvent(NfcTagEvent e)
    {
        string when = DateTime.Now.ToString("HH:mm:ss", Es);
        if (e.Written)
        {
            if (_pendingWrite is { } w)
            {
                if (e.UidHex is not null) Stable.Update(w.Kind, w.Code, r => r.NfcUid = e.UidHex);
                NfcLast = $"{when} · Etiqueta grabada y verificada: {e.Tag?.Name} ({w.Code})";
                NfcLastOk = true;
                Log.Info("nfc", "etiqueta grabada", new { code = w.Code, uid = e.UidHex });
            }
            _pendingWrite = null;
            RaiseMany(nameof(WriteArmed), nameof(WriteArmedText));
            ReapplyIdentities();
            Status = NfcLast;
            return;
        }
        if (e.Tag is null)
        {
            NfcLast = $"{when} · {e.Error ?? "Etiqueta no reconocida"}{(e.UidHex is null ? "" : " · UID " + e.UidHex)}";
            NfcLastOk = false;
            Status = "NFC: " + (e.Error ?? "etiqueta no reconocida");
            return;
        }
        try
        {
            var (rec, created) = Stable.ImportTag(e.Tag, e.UidHex);
            string what = e.Tag.Kind == IdentityKind.Horse ? "Caballo" : "Jinete";
            NfcLast = $"{when} · {what} {rec.Name} ({rec.Code}) {(created ? "registrado desde la etiqueta" : "leído (ya estaba registrado; no se sobrescribe)")}";
            NfcLastOk = true;
            Log.Info("nfc", created ? "registrado" : "leído", new { kind = e.Tag.Kind.ToString(), code = rec.Code, uid = e.UidHex });
            ReapplyIdentities();
            if (AssignVisible)
            {
                if (e.Tag.Kind == IdentityKind.Horse) AssignHorseText = rec.Name; else AssignRiderText = rec.Name;
            }
            else if (Page is "Stable" or "Riders")
            {
                Page = e.Tag.Kind == IdentityKind.Horse ? "Stable" : "Riders";
                (e.Tag.Kind == IdentityKind.Horse ? HorsesPage : RidersPage).Select(rec.Code);
            }
            Status = "NFC: " + NfcLast[(when.Length + 3)..];
        }
        catch (ArgumentException ex)
        {
            NfcLast = $"{when} · {ex.Message}";
            NfcLastOk = false;
        }
    }

    /// <summary>Applies Cuadra/Jinetes names to every loaded training and refreshes everything that shows them.</summary>
    public void ReapplyIdentities()
    {
        foreach (var s in Sessions) ApplyIdentity(s);
        SessionsView.Refresh();
        RefreshHome();
        RefreshStable();
        RefreshSessionPanels();
        if (Page == "Compare") RefreshCompare();
        if (Page == "Reports") RefreshReportPreview();
    }

    private void ApplyIdentity(SessionItem s)
    {
        var (h, r) = Stable.Apply(s.Session);
        s.SetIdentity(h, r);
    }

    public void RefreshStable()
    {
        if (HorsesPage is null) return;
        var list = Sessions.ToList();
        HorsesPage.Rebuild(Stable.Horses, list);
        RidersPage.Rebuild(Stable.Riders, list);
        HorseNames.Clear(); foreach (var n in Stable.Horses.Where(h => h.Active).Select(h => h.Name).Distinct().OrderBy(x => x, StringComparer.CurrentCultureIgnoreCase)) HorseNames.Add(n);
        RiderNames.Clear(); foreach (var n in Stable.Riders.Where(h => h.Active).Select(h => h.Name).Distinct().OrderBy(x => x, StringComparer.CurrentCultureIgnoreCase)) RiderNames.Add(n);
        RaiseMany(nameof(UnknownHorseCount), nameof(UnknownRiderCount));
    }
    public int UnknownHorseCount => Sessions.Count(s => !s.HorseKnown);
    public int UnknownRiderCount => Sessions.Count(s => !s.RiderKnown);

    /// <summary>Called after an import: new horses/riders carried by the files go into the Cuadra/Jinetes, then names are applied.</summary>
    private void RegisterImported(IEnumerable<SessionItem> items)
    {
        foreach (var s in items)
        {
            try { Stable.RegisterFromTraining(s.Session); }
            catch (ArgumentException ex) { Log.Warn("cuadra", ex.Message); }
        }
        ReapplyIdentities();
    }

    // ------------------------------------------------------------------ assignment panel
    public ICommand OpenAssignCommand { get; private set; } = null!;
    public ICommand ConfirmAssignCommand { get; private set; } = null!;
    public ICommand CancelAssignCommand { get; private set; } = null!;
    public ICommand ClearAssignCommand { get; private set; } = null!;

    private bool _assignVisible;
    public bool AssignVisible { get => _assignVisible; set => Set(ref _assignVisible, value); }
    private SessionItem? _assignTarget;
    public SessionItem? AssignTarget { get => _assignTarget; private set => Set(ref _assignTarget, value); }
    private string _assignHorse = "", _assignRider = "", _assignMessage = "";
    public string AssignHorseText { get => _assignHorse; set => Set(ref _assignHorse, value ?? ""); }
    public string AssignRiderText { get => _assignRider; set => Set(ref _assignRider, value ?? ""); }
    public string AssignMessage { get => _assignMessage; set => Set(ref _assignMessage, value); }
    private bool _assignOthers;
    public bool AssignAlsoUnknown { get => _assignOthers; set => Set(ref _assignOthers, value); }
    public string AssignOthersText { get; private set; } = "";
    public string AssignFileText => AssignTarget is null ? "" :
        $"En el archivo: caballo «{AssignTarget.Session.HorseInFile}»{(AssignTarget.Session.HorseCode is { } hc ? $" ({hc})" : "")} · jinete «{AssignTarget.Session.RiderInFile}»{(AssignTarget.Session.RiderCode is { } rc ? $" ({rc})" : "")}";

    private void OpenAssign(SessionItem? s)
    {
        if (s is null) return;
        AssignTarget = s;
        AssignHorseText = s.HorseKnown ? s.Horse : "";
        AssignRiderText = s.RiderKnown ? s.Rider : "";
        AssignAlsoUnknown = false;
        int others = Sessions.Count(x => x != s && (!x.HorseKnown || !x.RiderKnown));
        AssignOthersText = others == 0 ? "" : $"Aplicar también a los otros {others} entrenamiento(s) sin caballo o sin jinete (solo rellena lo que falta)";
        AssignMessage = "Escribe o elige el caballo y el jinete, o acerca su etiqueta NFC al lector. Solo cambia la ficha en este PC: el archivo del entrenamiento no se modifica.";
        RaiseMany(nameof(AssignOthersText), nameof(AssignFileText), nameof(HasAssignOthers));
        AssignVisible = true;
    }
    public bool HasAssignOthers => AssignOthersText.Length > 0;
    /// <summary>Pickers next to the text boxes: choosing a saved one fills the text.</summary>
    public string? PickHorse { get => null; set { if (!string.IsNullOrEmpty(value)) AssignHorseText = value; } }
    public string? PickRider { get => null; set { if (!string.IsNullOrEmpty(value)) AssignRiderText = value; } }

    /// <summary>Finds a record by name or code; creates it (next free code) when the text is new. Empty → null (clear).</summary>
    private string? CodeFor(IdentityKind k, string text)
    {
        text = text.Trim();
        if (text.Length == 0) return null;
        var r = Stable.FindByName(k, text) ?? Stable.Find(k, text);
        if (r is not null) return r.Code;
        return Stable.Add(k, new IdentityRecord { Code = Stable.NextCode(k), Name = text, Origin = "asignación" }).Code;
    }

    private void ConfirmAssign()
    {
        if (AssignTarget is not { } t) return;
        try
        {
            string? h = CodeFor(IdentityKind.Horse, AssignHorseText), r = CodeFor(IdentityKind.Rider, AssignRiderText);
            Stable.Assign(t.Id, true, h, true, r);
            int extra = 0;
            if (AssignAlsoUnknown)
                foreach (var s in Sessions.Where(x => x != t))
                {
                    bool sh = !s.HorseKnown && h is not null, sr = !s.RiderKnown && r is not null;
                    if (!sh && !sr) continue;
                    Stable.Assign(s.Id, sh, h, sr, r);
                    extra++;
                }
            Log.Info("cuadra", "asignación", new { session = t.Id, horse = h, rider = r, extra });
            AssignVisible = false;
            ReapplyIdentities();
            Status = $"Asignado: {t.Horse} · {t.Rider}{(extra > 0 ? $" (y {extra} entrenamiento(s) más)" : "")}";
        }
        catch (Exception ex) when (ex is ArgumentException or KeyNotFoundException or IOException)
        {
            AssignMessage = ex.Message;
        }
    }

    /// <summary>From the Cuadra/Jinetes page: give the selected record to every training without horse (or rider).</summary>
    public void AssignUnknownTo(IdentityPage page)
    {
        if (page.Selected is null) return;
        var list = Sessions.Where(s => !(page.IsHorse ? s.HorseKnown : s.RiderKnown)).ToList();
        if (list.Count == 0) return;
        if (!Dialogs.Confirm(page.Title, $"¿Asignar {page.Selected.Name} a {list.Count} entrenamiento(s) sin {page.Singular}?\n\nSe puede cambiar después en cada entrenamiento («Asignar»). Los archivos no se modifican."))
            return;
        foreach (var s in list) Stable.Assign(s.Id, page.IsHorse, page.IsHorse ? page.Selected.Code : null, !page.IsHorse, page.IsHorse ? null : page.Selected.Code);
        string code = page.Selected.Code;
        ReapplyIdentities();
        page.Select(code);
        page.Message = $"Asignado a {list.Count} entrenamiento(s).";
    }
}
