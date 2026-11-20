using Avo.Windows.Core;
using System.Text.Json.Nodes;

namespace Avo.Windows.SelfTest;

/// <summary>Nube AVO: mismas rutas que core/src/test/.../CloudSyncTest.kt e ipad/AVOiPadTests/CloudStorageTests.swift.</summary>
public static class CloudTests
{
    public static void Run(Action<bool, string> assert)
    {
        assert(CloudConfig.FileName("S20261120_0001") == "AVO_S20261120_0001.avo" && CloudConfig.FileName("a/b c.") == "AVO_a_b_c_.avo",
            "Nube: nombre de archivo igual que Android e iPad");
        assert(CloudConfig.FileName(new string('x', 400)).Length == 138 && CloudConfig.Folder("avo-abcd-ef23") == "trainings/AVO-ABCD-EF23/",
            "Nube: nombre acotado y carpeta por tarjeta");

        string k = new('a', 32);
        var c = AvoUserCard.Parse($"avohorse://identity/user/AVO-ABCD-EF23?v=1&name=Ana%20Ruiz&k={k}");
        assert(c.Code == "AVO-ABCD-EF23" && c.Name == "Ana Ruiz" && c.Secret == k && c.Email == "avo-abcd-ef23@avo-cards.app",
            "Nube: enlace de la tarjeta AVO");
        assert(AvoUserCard.Parse(c.ToLink()) == c && AvoUserCard.Parse($"avo-abcd-ef23 {k.ToUpperInvariant()}").Code == "AVO-ABCD-EF23",
            "Nube: tarjeta por enlace o «código clave»");
        bool bad;
        try { AvoUserCard.Parse("AVO-ABCD-EF2I " + k); bad = false; } catch (InvalidDataException) { bad = true; }
        assert(bad, "Nube: código de tarjeta con letras no permitidas rechazado");

        var it = CloudItem.Parse(JsonNode.Parse("""
            {"name":"trainings/AVO-ABCD-EF23/AVO_S1.avo","size":"2048","updated":"2026-11-20T12:00:00Z",
             "metadata":{"sha256":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","sessionId":"S1","horseName":"LEZAMA",
             "riderName":"Ana","startRtcMs":"1763640000000","distanceM":"3200"}}
            """));
        assert(it is { Size: 2048, FileName: "AVO_S1.avo", StartRtcMs: 1763640000000, DistanceM: 3200 } && it.Sha256 == new string('a', 64),
            "Nube: metadatos del objeto");
        assert(CloudItem.Parse(JsonNode.Parse("""{"name":"trainings/A/otro.zip"}""")) is null, "Nube: solo paquetes .avo");
        var names = CloudItem.ListNames(JsonNode.Parse("""{"items":[{"name":"trainings/A/AVO_1.avo"},{"name":"trainings/A/x.txt"}],"prefixes":[]}"""));
        assert(names.Count == 1 && names[0] == "trainings/A/AVO_1.avo", "Nube: listado");
        bool denied;
        try { AvoCloudClient.Check(System.Net.HttpStatusCode.Forbidden, "listar"); denied = false; } catch (CloudException e) { denied = e.Message.Contains("storage.rules"); }
        assert(denied, "Nube: permiso denegado explica las reglas");
    }
}
