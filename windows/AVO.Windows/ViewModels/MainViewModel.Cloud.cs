using System.Collections.ObjectModel;
using System.Globalization;
using System.IO;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Windows.Input;
using Avo.Windows.Core;

namespace Avo.Windows.ViewModels;

/// <summary>Una fila de la Nube AVO en la página Servidor.</summary>
public sealed record CloudRow(CloudItem Item, string Title, string Detail);

/// <summary>
/// Nube AVO (página Servidor): entrar con la tarjeta AVO, ver los entrenamientos que sube el Android y descargarlos e
/// importarlos con las mismas validaciones que un .avo. La tarjeta se guarda cifrada con DPAPI para el usuario de Windows
/// (%LOCALAPPDATA%\AVO Performance Horse\Windows\nube.tarjeta). Contrato: docs/NUBE_SESIONES.md.
/// </summary>
public sealed partial class MainViewModel
{
    private static readonly byte[] CloudEntropy = "AVO-CLOUD-CARD/1"u8.ToArray();
    private static readonly HttpClient CloudHttp = new() { Timeout = TimeSpan.FromMinutes(5) };
    private readonly AvoCloudClient _cloud = new(CloudHttp);
    private string CloudCardFile => Path.Combine(Paths.Root, "nube.tarjeta");

    private string _cloudCardText = "";
    public string CloudCardText { get => _cloudCardText; set => Set(ref _cloudCardText, value); }
    private string _cloudState = "Pega el enlace de tu tarjeta AVO (Android: Compartir › Mi cuenta › «Entrar en el iPad») y pulsa Entrar.";
    public string CloudState { get => _cloudState; private set => Set(ref _cloudState, value); }
    private string _cloudAccount = "Sin tarjeta";
    public string CloudAccount { get => _cloudAccount; private set => Set(ref _cloudAccount, value); }
    public ObservableCollection<CloudRow> CloudRows { get; } = [];
    public ICommand CloudSignInCommand { get; private set; } = null!;
    public ICommand CloudSignOutCommand { get; private set; } = null!;
    public ICommand CloudRefreshCommand { get; private set; } = null!;
    public ICommand CloudImportCommand { get; private set; } = null!;
    public ICommand CloudImportAllCommand { get; private set; } = null!;

    private void InitCloud()
    {
        CloudSignInCommand = new AsyncCommand(async _ =>
        {
            AvoUserCard card;
            try { card = AvoUserCard.Parse(CloudCardText); }
            catch (InvalidDataException ex) { CloudState = ex.Message; return; }
            await CloudSignIn(card, save: true);
            if (_cloud.SignedInCode is not null) { CloudCardText = ""; await CloudList(); }
        }, CloudFail);
        CloudSignOutCommand = new RelayCommand(() =>
        {
            _cloud.SignOut();
            try { File.Delete(CloudCardFile); } catch (IOException) { }
            CloudRows.Clear();
            CloudAccount = "Sin tarjeta";
            CloudState = "Tarjeta olvidada en este PC";
        });
        CloudRefreshCommand = new AsyncCommand(async _ => { if (await CloudEnsureSignedIn()) await CloudList(); }, CloudFail);
        CloudImportCommand = new AsyncCommand(async p => { if (p is CloudRow r) await CloudImport([r.Item]); }, CloudFail);
        CloudImportAllCommand = new AsyncCommand(async _ => await CloudImport(CloudRows.Select(r => r.Item).ToList()), CloudFail);
        if (File.Exists(CloudCardFile)) CloudAccount = "Tarjeta guardada en este PC (pulsa Ver mi nube)";
    }

    private void CloudFail(Exception ex)
    {
        CloudState = ex.Message;
        Log.Warn("nube", "Nube AVO", ex);
    }

    private async Task CloudSignIn(AvoUserCard card, bool save)
    {
        CloudState = "Entrando…";
        await _cloud.SignInAsync(card);
        CloudAccount = $"Tarjeta {card.Code}" + (card.Name.Length > 0 ? " · " + card.Name : "");
        if (save)
        {
            Directory.CreateDirectory(Paths.Root);
            File.WriteAllBytes(CloudCardFile, ProtectedData.Protect(Encoding.UTF8.GetBytes(card.ToLink()), CloudEntropy, DataProtectionScope.CurrentUser));
        }
        CloudState = "Sesión iniciada";
    }

    private async Task<bool> CloudEnsureSignedIn()
    {
        if (_cloud.SignedInCode is not null) return true;
        if (!File.Exists(CloudCardFile)) { CloudState = "Entra primero con tu tarjeta AVO"; return false; }
        AvoUserCard card;
        try { card = AvoUserCard.Parse(Encoding.UTF8.GetString(ProtectedData.Unprotect(File.ReadAllBytes(CloudCardFile), CloudEntropy, DataProtectionScope.CurrentUser))); }
        catch (Exception ex) when (ex is CryptographicException or InvalidDataException or IOException) { CloudState = "La tarjeta guardada no se puede leer: vuelve a entrar"; return false; }
        await CloudSignIn(card, save: false);
        return _cloud.SignedInCode is not null;
    }

    private async Task CloudList()
    {
        CloudState = "Consultando la nube…";
        var items = await _cloud.ListAsync();
        CloudRows.Clear();
        var es = CultureInfo.GetCultureInfo("es-ES");
        foreach (var it in items)
        {
            string date = it.StartRtcMs > 0 ? DateTimeOffset.FromUnixTimeMilliseconds(it.StartRtcMs).ToLocalTime().ToString("dd/MM/yyyy HH:mm", es) + " · " : "";
            var parts = new List<string>();
            if (it.RiderName.Length > 0) parts.Add(it.RiderName);
            if (it.DistanceM is double d) parts.Add((d / 1000).ToString("0.00", es) + " km");
            parts.Add((it.Size / 1048576.0).ToString("0.0", es) + " MB");
            parts.Add(it.SessionId.Length > 0 ? it.SessionId : it.FileName);
            CloudRows.Add(new CloudRow(it, date + (it.HorseName.Length > 0 ? it.HorseName : "Sin caballo"), string.Join(" · ", parts)));
        }
        CloudState = items.Count == 0 ? "La nube está vacía (el Android sube los entrenamientos verificados)" : $"{items.Count} entrenamientos en la nube";
    }

    private async Task CloudImport(List<CloudItem> items)
    {
        if (items.Count == 0 || !await CloudEnsureSignedIn()) return;
        var files = new List<string>();
        string dir = Path.Combine(Paths.Root, "nube");
        for (int i = 0; i < items.Count; i++)
        {
            CloudState = $"Descargando {i + 1}/{items.Count}: {items[i].FileName}";
            try { files.Add(await _cloud.DownloadAsync(items[i], dir)); }
            catch (Exception ex) when (ex is CloudException or HttpRequestException or IOException or TaskCanceledException) { CloudFail(ex); }
        }
        if (files.Count == 0) return;
        CloudState = $"Validando e importando {files.Count}…";
        await ImportFilesAsync(files.ToArray());
        CloudState = $"Importados {files.Count} de la nube";
        RefreshLibrary();
    }
}
