using System.Net;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Avo.Windows.Core;

/// <summary>
/// Nube AVO (Cloud Storage for Firebase, plan Blaze) por REST. Mismo contrato que el Android
/// (core/.../cloud/CloudSync.kt) y el iPad (ipad/AVOiPad/Core/CloudStorage.swift): <c>trainings/&lt;CODIGO&gt;/AVO_&lt;id&gt;.avo</c>,
/// paquetes AVO-TRAINING-1 con el metadato <c>sha256</c>. Solo el dueño de la tarjeta lista y descarga
/// (firebase/storage.rules). Documentación: docs/NUBE_SESIONES.md.
/// Los valores de configuración son públicos (van dentro de cada app); la seguridad la dan las reglas.
/// </summary>
public static class CloudConfig
{
    public const string ApiKey = "AIzaSyAjd0ZKXYWQgpCdq_mMyiQeJ-MUT47HOd0";
    public const string Bucket = "avo-performance-horse-7be14.firebasestorage.app";
    public const string Prefix = "trainings";
    public const long MaxBytes = 40L * 1024 * 1024;

    public static string FileName(string sessionId)
    {
        var sb = new StringBuilder();
        foreach (char ch in sessionId)
        {
            if (sb.Length >= 130) break;
            sb.Append(ch is >= 'A' and <= 'Z' or >= 'a' and <= 'z' or >= '0' and <= '9' or '_' or '-' ? ch : '_');
        }
        return "AVO_" + sb + ".avo";
    }

    public static string Folder(string code) => Prefix + "/" + code.ToUpperInvariant() + "/";

    /// <summary>Huella de lo empaquetado (igual que CloudSync.fingerprint del Android y CloudConfig.fingerprint del iPad).</summary>
    public static string Fingerprint(string localSha256, string? horseCode, string? riderCode, string horseName, string riderName)
    {
        string s = string.Join('\u001f', localSha256.ToLowerInvariant(), horseCode ?? "", riderCode ?? "", horseName, riderName);
        return Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(s))[..16]);
    }
}

/// <summary>Identidad escrita en el manifiesto de un .avo (prioridad AVO-ASSIGN-1: bloque «asignacion», luego primer nivel).</summary>
public sealed record CloudManifestIdentity(string SessionId, string RawSha256, string HorseCode, string HorseName, string RiderCode, string RiderName, long AssignedMs)
{
    public string Fingerprint => CloudConfig.Fingerprint(RawSha256, HorseCode.Length == 0 ? null : HorseCode, RiderCode.Length == 0 ? null : RiderCode, HorseName, RiderName);

    public static CloudManifestIdentity Read(string avoPath)
    {
        using var zip = System.IO.Compression.ZipFile.OpenRead(avoPath);
        var m = zip.GetEntry("manifest.json") ?? throw new InvalidDataException("Falta manifest.json");
        if (m.Length is < 1 or > AvoAssignment.ManifestMax) throw new InvalidDataException("Tamaño del manifiesto inválido");
        using var st = m.Open();
        using var ms = new MemoryStream();
        st.CopyTo(ms);
        byte[] b = ms.ToArray();
        int bom = b.Length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF ? 3 : 0;
        using var doc = JsonDocument.Parse(b.AsMemory(bom));
        return From(doc.RootElement);
    }

    public static CloudManifestIdentity From(JsonElement root)
    {
        var a = AvoAssignment.Read(root);
        string Top(string k) => root.TryGetProperty(k, out var v) && v.ValueKind == JsonValueKind.String ? (v.GetString() ?? "").Trim() : "";
        long when = a is null || a.UpdatedUtc == DateTimeOffset.MinValue ? 0 : a.UpdatedUtc.ToUnixTimeMilliseconds();
        return new CloudManifestIdentity(Top("sessionId"), Top("sha256").ToLowerInvariant(),
            a?.HorseCode ?? Top("horseCode"), a is { HorseName.Length: > 0 } ? a.HorseName : Top("horseName"),
            a?.RiderCode ?? Top("riderCode"), a is { RiderName.Length: > 0 } ? a.RiderName : Top("riderName"), when);
    }
}

/// <summary>Tarjeta personal AVO (la misma del Android): <c>avohorse://identity/user/AVO-XXXX-XXXX?v=1&amp;name=…&amp;k=&lt;32 hex&gt;</c>.</summary>
public sealed record AvoUserCard(string Code, string Name, string Secret)
{
    public const string Prefix = "avohorse://identity/user/";
    private const string Alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

    public string Email => Code.ToLowerInvariant() + "@avo-cards.app";

    public static bool ValidCode(string c)
    {
        var p = c.Split('-');
        return p.Length == 3 && p[0] == "AVO" && p[1].Length == 4 && p[2].Length == 4 && (p[1] + p[2]).All(ch => Alphabet.Contains(ch));
    }

    public static bool ValidSecret(string k) => k.Length == 32 && k.All(ch => ch is >= '0' and <= '9' or >= 'a' and <= 'f');

    public static AvoUserCard Create(string code, string name, string secret)
    {
        string c = code.Trim().ToUpperInvariant();
        string k = secret.Replace(" ", "").Replace("-", "").ToLowerInvariant();
        if (!ValidCode(c)) throw new InvalidDataException("Código de tarjeta no válido (AVO-XXXX-XXXX)");
        if (!ValidSecret(k)) throw new InvalidDataException("Clave de tarjeta no válida (32 caracteres 0-9 y a-f)");
        return new AvoUserCard(c, name.Trim(), k);
    }

    /// <summary>Enlace completo (Android: Compartir › Mi cuenta › «Entrar en el iPad»), o «código clave».</summary>
    public static AvoUserCard Parse(string text)
    {
        string u = text.Trim();
        if (!u.StartsWith(Prefix, StringComparison.Ordinal))
        {
            var parts = u.Split([' ', '\t', '\n', '\r'], StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length == 2) return Create(parts[0], "", parts[1]);
            throw new InvalidDataException("Pega el enlace de tu tarjeta AVO (avohorse://identity/user/…) o «código clave»");
        }
        string rest = u[Prefix.Length..];
        int q = rest.IndexOf('?');
        string code = q < 0 ? rest : rest[..q];
        var map = new Dictionary<string, string>();
        if (q >= 0)
            foreach (var kv in rest[(q + 1)..].Split('&'))
            {
                int e = kv.IndexOf('=');
                string key = Uri.UnescapeDataString(e < 0 ? kv : kv[..e]);
                map[key] = e < 0 ? "" : Uri.UnescapeDataString(kv[(e + 1)..].Replace('+', ' '));
            }
        if (!map.TryGetValue("v", out var v) || v != "1") throw new InvalidDataException("Versión de tarjeta no compatible");
        return Create(code, map.GetValueOrDefault("name", ""), map.GetValueOrDefault("k", ""));
    }

    public string ToLink() => $"{Prefix}{Code}?v=1&name={Uri.EscapeDataString(Name)}&k={Secret}";
}

/// <summary>Un entrenamiento guardado en la nube.</summary>
public sealed record CloudItem(string Name, long Size, string Updated, string Sha256, string SessionId, string HorseName, string RiderName,
    long StartRtcMs, double? DistanceM, string HorseCode = "", string RiderCode = "", long AssignedMs = 0, string Fp = "")
{
    public string FileName => Name[(Name.LastIndexOf('/') + 1)..];

    /// <summary>Metadatos de un objeto (<c>GET /v0/b/&lt;bucket&gt;/o/&lt;ruta&gt;</c>).</summary>
    public static CloudItem? Parse(JsonNode? j)
    {
        if (j is null || Str(j["name"]) is not { } name || !name.EndsWith(".avo", StringComparison.Ordinal)) return null;
        var m = j["metadata"];
        string S(string k) => Str(m?[k]) ?? "";
        long size = long.TryParse(Str(j["size"]), out var x) ? x
            : j["size"] is JsonValue sv && sv.GetValueKind() == JsonValueKind.Number ? sv.GetValue<long>() : 0;
        return new CloudItem(name, size, Str(j["updated"]) ?? "", S("sha256").ToLowerInvariant(), S("sessionId"), S("horseName"), S("riderName"),
            long.TryParse(S("startRtcMs"), out var t) ? t : 0,
            double.TryParse(S("distanceM"), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var d) ? d : null,
            S("horseCode"), S("riderCode"), long.TryParse(S("assignedMs"), out var am) ? am : 0, S("fp"));
    }

    private static string? Str(JsonNode? n) => n is JsonValue v && v.GetValueKind() == JsonValueKind.String ? v.GetValue<string>() : null;

    /// <summary>Nombres de la respuesta de listado (<c>{"items":[{"name":…}]}</c>).</summary>
    public static List<string> ListNames(JsonNode? j) =>
        (j?["items"] as JsonArray ?? new JsonArray()).Select(i => (string?)i?["name"]).OfType<string>().Where(n => n.EndsWith(".avo", StringComparison.Ordinal)).ToList();
}

public sealed class CloudException(string message, Exception? inner = null) : Exception(message, inner);

/// <summary>Cliente de la Nube AVO: entra con la tarjeta (Firebase Authentication) y lista o descarga de Cloud Storage.</summary>
public sealed class AvoCloudClient(HttpClient http)
{
    private AvoUserCard? _card;
    private string? _idToken;
    private string? _refresh;
    private DateTime _expires = DateTime.MinValue;

    public string? SignedInCode => _idToken is null ? null : _card?.Code;

    public async Task SignInAsync(AvoUserCard card, CancellationToken ct = default)
    {
        _card = card;
        var body = new JsonObject { ["email"] = card.Email, ["password"] = card.Secret, ["returnSecureToken"] = true };
        using var resp = await http.PostAsync($"https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key={CloudConfig.ApiKey}",
            new StringContent(body.ToJsonString(), Encoding.UTF8, "application/json"), ct);
        var j = await ReadJson(resp, ct);
        if (resp.StatusCode != HttpStatusCode.OK) { _idToken = null; throw new CloudException(AuthMessage(j)); }
        Take((string?)j?["idToken"], (string?)j?["refreshToken"], (string?)j?["expiresIn"]);
    }

    public void SignOut() { _card = null; _idToken = null; _refresh = null; _expires = DateTime.MinValue; }

    public static string AuthMessage(JsonNode? j)
    {
        string m = (string?)j?["error"]?["message"] ?? "error desconocido";
        if (m.Contains("INVALID_LOGIN_CREDENTIALS") || m.Contains("INVALID_PASSWORD") || m.Contains("EMAIL_NOT_FOUND"))
            return "Tarjeta o clave incorrectas, o la tarjeta aún no se ha usado en el Android (Compartir)";
        if (m.Contains("API_KEY") || m.Contains("blocked") || m.Contains("Android client"))
            return $"Firebase rechaza la clave para Windows ({m}): hay que quitar la restricción de la clave o añadir una app web en la consola.";
        return "Firebase: " + m;
    }

    private void Take(string? id, string? refresh, string? expiresIn)
    {
        if (string.IsNullOrEmpty(id)) throw new CloudException("Firebase no devolvió la sesión");
        _idToken = id; _refresh = refresh;
        _expires = DateTime.UtcNow.AddSeconds(double.TryParse(expiresIn, out var s) ? s : 3600);
    }

    private async Task<string> TokenAsync(CancellationToken ct)
    {
        if (_idToken is not null && DateTime.UtcNow < _expires.AddMinutes(-5)) return _idToken;
        if (_refresh is not null)
        {
            using var resp = await http.PostAsync($"https://securetoken.googleapis.com/v1/token?key={CloudConfig.ApiKey}",
                new FormUrlEncodedContent(new Dictionary<string, string> { ["grant_type"] = "refresh_token", ["refresh_token"] = _refresh }), ct);
            var j = await ReadJson(resp, ct);
            if (resp.StatusCode == HttpStatusCode.OK) { Take((string?)j?["id_token"], (string?)j?["refresh_token"], (string?)j?["expires_in"]); return _idToken!; }
        }
        if (_card is null) throw new CloudException("Entra con tu tarjeta AVO");
        await SignInAsync(_card, ct);
        return _idToken!;
    }

    private static async Task<JsonNode?> ReadJson(HttpResponseMessage r, CancellationToken ct)
    {
        try { return JsonNode.Parse(await r.Content.ReadAsStringAsync(ct)); } catch (JsonException) { return null; }
    }

    private static string ObjectUrl(string path, bool media = false) =>
        $"https://firebasestorage.googleapis.com/v0/b/{CloudConfig.Bucket}/o/{Uri.EscapeDataString(path)}" + (media ? "?alt=media" : "");

    private async Task<HttpResponseMessage> GetAsync(string url, CancellationToken ct, HttpCompletionOption opt = HttpCompletionOption.ResponseContentRead)
    {
        var req = new HttpRequestMessage(HttpMethod.Get, url);
        req.Headers.Authorization = new AuthenticationHeaderValue("Firebase", await TokenAsync(ct));
        return await http.SendAsync(req, opt, ct);
    }

    public static void Check(HttpStatusCode code, string what)
    {
        int c = (int)code;
        if (c is >= 200 and <= 299) return;
        throw new CloudException(c switch
        {
            401 or 403 => $"Nube: sin permiso para {what}. ¿Están publicadas las reglas de Storage (firebase/storage.rules)?",
            404 => $"Nube: no encontrado ({what}). ¿Está activado Storage en la consola de Firebase?",
            _ => $"Nube: el servidor respondió {c} ({what})",
        });
    }

    /// <summary>Mis entrenamientos en la nube, del más reciente al más antiguo.</summary>
    public async Task<List<CloudItem>> ListAsync(CancellationToken ct = default)
    {
        string code = _card?.Code ?? throw new CloudException("Entra con tu tarjeta AVO");
        var names = new List<string>();
        string? page = null;
        do
        {
            string url = $"https://firebasestorage.googleapis.com/v0/b/{CloudConfig.Bucket}/o?prefix={Uri.EscapeDataString(CloudConfig.Folder(code))}&delimiter=%2F"
                + (page is null ? "" : "&pageToken=" + Uri.EscapeDataString(page));
            using var resp = await GetAsync(url, ct);
            Check(resp.StatusCode, "listar la nube");
            var j = await ReadJson(resp, ct);
            names.AddRange(CloudItem.ListNames(j));
            page = (string?)j?["nextPageToken"];
        } while (page is not null && names.Count < 5000);
        var items = new List<CloudItem>();
        foreach (var n in names)
        {
            using var resp = await GetAsync(ObjectUrl(n), ct);
            Check(resp.StatusCode, n);
            if (CloudItem.Parse(await ReadJson(resp, ct)) is { } it) items.Add(it);
        }
        return items.OrderByDescending(i => i.StartRtcMs).ThenByDescending(i => i.Updated, StringComparer.Ordinal).ToList();
    }

    /// <summary>Metadatos de un entrenamiento de la nube, o null si no está.</summary>
    public async Task<CloudItem?> ItemAsync(string sessionId, CancellationToken ct = default)
    {
        string code = _card?.Code ?? throw new CloudException("Entra con tu tarjeta AVO");
        string path = CloudConfig.Folder(code) + CloudConfig.FileName(sessionId);
        using var resp = await GetAsync(ObjectUrl(path), ct);
        if (resp.StatusCode == HttpStatusCode.NotFound) return null;
        Check(resp.StatusCode, path);
        return CloudItem.Parse(await ReadJson(resp, ct));
    }

    /// <summary>Sube (o reemplaza) un .avo con sus metadatos (subida «multipart» de Firebase Storage).</summary>
    public async Task UploadAsync(string avoPath, string sessionId, IDictionary<string, string> metadata, CancellationToken ct = default)
    {
        string code = _card?.Code ?? throw new CloudException("Entra con tu tarjeta AVO");
        byte[] data = await File.ReadAllBytesAsync(avoPath, ct);
        if (data.LongLength > CloudConfig.MaxBytes) throw new CloudException("Nube: archivo de más de 40 MB");
        string name = CloudConfig.Folder(code) + CloudConfig.FileName(sessionId);
        var meta = new JsonObject();
        foreach (var kv in metadata) meta[kv.Key] = kv.Value;
        meta["sha256"] = Convert.ToHexStringLower(SHA256.HashData(data));
        var json = new JsonObject { ["name"] = name, ["contentType"] = "application/octet-stream", ["metadata"] = meta };
        string boundary = "avo" + Guid.NewGuid().ToString("N");
        using var body = new MemoryStream();
        void W(string t) { var b = Encoding.UTF8.GetBytes(t); body.Write(b, 0, b.Length); }
        W($"--{boundary}\r\nContent-Type: application/json; charset=utf-8\r\n\r\n{json.ToJsonString()}\r\n--{boundary}\r\nContent-Type: application/octet-stream\r\n\r\n");
        body.Write(data, 0, data.Length);
        W($"\r\n--{boundary}--");
        var req = new HttpRequestMessage(HttpMethod.Post,
            $"https://firebasestorage.googleapis.com/v0/b/{CloudConfig.Bucket}/o?name={Uri.EscapeDataString(name)}");
        req.Headers.Authorization = new AuthenticationHeaderValue("Firebase", await TokenAsync(ct));
        req.Headers.TryAddWithoutValidation("X-Goog-Upload-Protocol", "multipart");
        req.Content = new ByteArrayContent(body.ToArray());
        req.Content.Headers.TryAddWithoutValidation("Content-Type", $"multipart/related; boundary={boundary}");
        using var resp = await http.SendAsync(req, ct);
        Check(resp.StatusCode, "subir " + CloudConfig.FileName(sessionId));
    }

    /// <summary>Descarga un .avo y comprueba su SHA-256 con el de la nube. Devuelve la ruta del archivo.</summary>
    public async Task<string> DownloadAsync(CloudItem item, string targetDirectory, CancellationToken ct = default)
    {
        if (item.Size > CloudConfig.MaxBytes) throw new CloudException("Nube: archivo de más de 40 MB");
        using var resp = await GetAsync(ObjectUrl(item.Name, media: true), ct, HttpCompletionOption.ResponseHeadersRead);
        Check(resp.StatusCode, item.FileName);
        byte[] data = await resp.Content.ReadAsByteArrayAsync(ct);
        if (data.LongLength > CloudConfig.MaxBytes) throw new CloudException("Nube: archivo de más de 40 MB");
        string sha = Convert.ToHexStringLower(SHA256.HashData(data));
        if (item.Sha256.Length > 0 && sha != item.Sha256) throw new CloudException($"Nube: el SHA-256 de {item.FileName} no coincide; descarga descartada");
        Directory.CreateDirectory(targetDirectory);
        string target = Path.Combine(targetDirectory, item.FileName);
        string tmp = target + ".part";
        await File.WriteAllBytesAsync(tmp, data, ct);
        File.Move(tmp, target, overwrite: true);
        return target;
    }
}
