using System.IO.Compression;
using System.Security.Cryptography;
using System.Text.Json;
using Avo.Windows.Core;

namespace Avo.Windows.SelfTest;

/// <summary>AVO-ASSIGN-1 (docs/ASIGNACION_CABALLO.md): the assignment travels in the .avo manifest; the RAW never changes.</summary>
public static class AssignmentTests
{
    public static void Run(string dir, Action<bool, string> A, string sourceAvo)
    {
        string d = Path.Combine(dir, "asignacion");
        if (Directory.Exists(d)) Directory.Delete(d, true);
        Directory.CreateDirectory(d);
        string avo = Path.Combine(d, "copia.avo");
        File.Copy(sourceAvo, avo);
        string segBefore = SegmentsSha(avo);

        var s0 = TrainingImporter.Import(avo, Path.Combine(d, "raw0"));
        A(s0.FileAssignment is null && s0.RawHorse == "Rayo", "Asignación: un .avo antiguo no trae bloque y el RAW dice «Rayo»");

        var t1 = new DateTimeOffset(2026, 11, 12, 22, 0, 0, TimeSpan.Zero);
        AvoAssignment.Write(avo, new AvoAssignmentData("H_ZAKINA", "Zakina", "AVO-A66T-F2E9", "Andoni Lezama", t1, "windows"), s0.RawHorse, s0.RawRider);
        A(SegmentsSha(avo) == segBefore, "Asignación: reescribir el manifiesto no cambia ningún byte del RAW");
        var s1 = TrainingImporter.Import(avo, Path.Combine(d, "raw1"));
        A(s1.Horse == "Zakina" && s1.HorseCode == "H_ZAKINA" && s1.Rider == "Andoni Lezama" && s1.RawHorse == "Rayo",
          "Asignación: al importar manda el bloque «asignacion»; el valor del RAW se conserva aparte");
        A(s1.FileAssignment is { App: "windows" } fa && fa.UpdatedUtc == t1, "Asignación: app y fecha de la asignación");
        A(s1.Integrity.Contains("SHA-256"), "Asignación: las huellas por segmento siguen verificándose");

        using (var zip = ZipFile.OpenRead(avo))
        using (var doc = JsonDocument.Parse(zip.GetEntry("manifest.json")!.Open()))
        {
            var r = doc.RootElement;
            A(zip.Entries[0].FullName == "manifest.json", "Asignación: el manifiesto sigue siendo la primera entrada");
            A(r.GetProperty("horseName").GetString() == "Zakina" && r.GetProperty("asignacion").GetProperty("raw").GetProperty("horseCode").GetString() == "Rayo",
              "Asignación: campos de primer nivel (lectores antiguos) y raw.horseCode");
        }
        // a second reassignment keeps what the RAW says, not the previous assignment
        AvoAssignment.Write(avo, new AvoAssignmentData("H_MALWINA", "Malwina", "AVO-A66T-F2E9", "Andoni Lezama", t1.AddHours(1), "windows"), "OTRO", null);
        var s2 = TrainingImporter.Import(avo, Path.Combine(d, "raw2"));
        using (var zip = ZipFile.OpenRead(avo))
        using (var doc = JsonDocument.Parse(zip.GetEntry("manifest.json")!.Open()))
            A(s2.Horse == "Malwina" && doc.RootElement.GetProperty("asignacion").GetProperty("raw").GetProperty("horseCode").GetString() == "Rayo",
              "Asignación: reasignar otra vez no pierde el valor original del RAW");

        string? opt = AvoAssignment.EngineOption("H_ZAKINA", "Zakina", null, StableStore.Unknown);
        A(opt == "\"asignacion\":{\"horseCode\":\"H_ZAKINA\",\"horseName\":\"Zakina\"}" && AvoAssignment.EngineOption(null, null, null, null) is null,
          "Asignación: opción del motor (sin «Sin identificar» ni campos vacíos)");

        // library: the file SHA-256 changes, the original is still a duplicate
        var lib = new TrainingLibrary(new AppPaths(Path.Combine(d, "app")));
        string original = Path.Combine(d, "original.avo");
        File.Copy(sourceAvo, original);
        var first = lib.Import(original, []);
        string oldSha = first.Session!.FileSha256!;
        string? newSha = lib.WriteAssignment(first.Session.SessionId, new AvoAssignmentData("H_ZAKINA", "Zakina", null, "", t1, "windows"), "Rayo", null);
        A(newSha is not null && newSha != oldSha && lib.Entries.Single().PreviousSha256.Contains(oldSha), "Biblioteca: nueva huella del fichero y la anterior guardada");
        var again = lib.Import(original, [first.Session.SessionId]);
        A(again.Duplicate && again.Session!.Horse == "Zakina", "Biblioteca: reimportar el original es un duplicado y muestra la asignación");

        // cuadra: a newer assignment in the file wins, an older one does not
        var st = new StableStore(Path.Combine(d, "cuadra.json"));
        st.Add(IdentityKind.Horse, new IdentityRecord { Code = "H_ZAKINA", Name = "Zakina" });
        st.Add(IdentityKind.Horse, new IdentityRecord { Code = "H_MALWINA", Name = "Malwina" });
        st.Assign(s1.SessionId, true, "H_ZAKINA", false, null);
        A(!st.AdoptFileAssignment(new TrainingSession { SessionId = s1.SessionId, FileAssignment = s1.FileAssignment }),
          "Cuadra: una asignación del fichero más antigua no pisa la de este PC");
        var newer = new TrainingSession { SessionId = s1.SessionId, FileAssignment = s1.FileAssignment! with { HorseCode = "H_MALWINA", HorseName = "Malwina", UpdatedUtc = DateTimeOffset.UtcNow.AddMinutes(5) } };
        A(st.AdoptFileAssignment(newer) && st.Assignment(s1.SessionId)?.HorseCode == "H_MALWINA", "Cuadra: una asignación más reciente de otra app se adopta");
        var unknownHorse = new TrainingSession { SessionId = "S_NUEVO", FileAssignment = new AvoAssignmentData("H_NUEVO", "Nueva", null, "", DateTimeOffset.UtcNow, "android") };
        A(st.AdoptFileAssignment(unknownHorse) && st.Find(IdentityKind.Horse, "H_NUEVO")?.Name == "Nueva", "Cuadra: el caballo asignado en otra app se da de alta");
    }

    private static string SegmentsSha(string avo)
    {
        using var zip = ZipFile.OpenRead(avo);
        var parts = zip.Entries.Where(e => e.FullName != "manifest.json").OrderBy(e => e.FullName, StringComparer.Ordinal).Select(e =>
        {
            using var s = e.Open(); using var ms = new MemoryStream(); s.CopyTo(ms);
            return e.FullName + ":" + Convert.ToHexString(SHA256.HashData(ms.ToArray()));
        });
        return string.Join("|", parts);
    }
}
