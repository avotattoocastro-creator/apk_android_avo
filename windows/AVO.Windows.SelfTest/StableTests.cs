using System.Text;
using Avo.Windows.Core;

namespace Avo.Windows.SelfTest;

/// <summary>Cuadra / Jinetes / assignments and NFC (NDEF + NTAG through a simulated PC/SC reader). No hardware involved.</summary>
public static class StableTests
{
    private static Action<bool, string> _a = (_, _) => { };
    private static void A(bool ok, string what) => _a(ok, what);

    public static void Run(string dir, Action<bool, string> assert)
    {
        _a = assert;
        IdentityUri();
        NdefCodec();
        NtagThroughReader();
        Store(Path.Combine(dir, "cuadra"));
    }

    private static bool Throws(Action f) { try { f(); return false; } catch (FormatException) { return true; } }

    // ---------------------------------------------------------------- the URI the Android app writes (AvoNfc.kt)
    private static void IdentityUri()
    {
        var h = AvoIdentityTag.Parse("avohorse://identity/horse/HORSE_001?v=2&name=Rayo%20de%20Luna&breed=PRE&birthYear=2015&notes=Ca%C3%B1a%20fina&active=true");
        A(h.Kind == IdentityKind.Horse && h.Code == "HORSE_001" && h.Name == "Rayo de Luna" && h.Breed == "PRE" && h.BirthYear == 2015 && h.Notes == "Caña fina" && h.Active,
            "NFC: etiqueta de caballo v2 (formato Android)");
        var r = AvoIdentityTag.Parse("avohorse://identity/rider/RIDER_007");
        A(r.Kind == IdentityKind.Rider && r.Code == "RIDER_007" && r.Name == "RIDER_007" && r.Active && r.BirthYear is null, "NFC: etiqueta antigua solo con identidad");
        A(AvoIdentityTag.Parse("avohorse://identity/rider/R1?v=2&name=Ana+Mar%C3%ADa&active=false") is { Name: "Ana María", Active: false }, "NFC: '+' es espacio y active=false");
        A(AvoIdentityTag.Parse("avohorse://identity/horse/H1?v=2&birthYear=1850") is { BirthYear: null, Name: "H1" }, "NFC: año fuera de rango se ignora");
        A(Throws(() => AvoIdentityTag.Parse("avohorse://identity/horse/H1?v=3")), "NFC: versión no compatible rechazada");
        A(Throws(() => AvoIdentityTag.Parse("avohorse://identity/dog/H1")), "NFC: tipo desconocido rechazado");
        A(Throws(() => AvoIdentityTag.Parse("avohorse://identity/horse/" + new string('X', 24))), "NFC: código de más de 23 caracteres rechazado");
        A(Throws(() => AvoIdentityTag.Parse("avohorse://identity/horse/%0A")), "NFC: código con caracteres de control rechazado");
        A(Throws(() => AvoIdentityTag.Parse("https://example.org/x")), "NFC: etiqueta no AVO rechazada");
        var rec = new IdentityRecord { Code = "HORSE_001", Name = "Rayo de Luna", Breed = "PRE", BirthYear = 2015, Notes = "" };
        A(AvoIdentityTag.BuildUri(IdentityKind.Horse, rec) == "avohorse://identity/horse/HORSE_001?v=2&name=Rayo%20de%20Luna&breed=PRE&birthYear=2015&notes=&active=true",
            "NFC: URI idéntica a AvoNfc.horse() de Android");
        var odd = new IdentityRecord { Code = "R-9", Name = "Ñandú & Co / ¿sí? 100%+", Notes = "línea1\nlínea2", Active = false };
        var back = AvoIdentityTag.Parse(AvoIdentityTag.BuildUri(IdentityKind.Rider, odd));
        A(back.Name == odd.Name && back.Notes == odd.Notes && !back.Active && back.Code == "R-9", "NFC: ida y vuelta con caracteres especiales");
    }

    // ---------------------------------------------------------------- NDEF
    private static void NdefCodec()
    {
        var m = Ndef.UriMessage("avohorse://identity/rider/RIDER_007");
        var expect = new byte[] { 0xD1, 0x01, 0x24, 0x55, 0x00 }.Concat(Encoding.ASCII.GetBytes("avohorse://identity/rider/RIDER_007")).ToArray();
        A(m.AsSpan().SequenceEqual(expect), "NDEF: registro URI corto como NdefRecord.createUri (sin abreviatura)");
        A(Ndef.Uris(m).Single() == "avohorse://identity/rider/RIDER_007", "NDEF: lectura del registro URI");
        A(Ndef.Uris(Ndef.UriMessage("https://www.avo.org")).Single() == "https://www.avo.org" && Ndef.UriMessage("https://www.avo.org")[4] == 0x02, "NDEF: abreviatura https://www.");
        string longUri = "avohorse://identity/horse/H1?v=2&notes=" + new string('a', 300);
        var lm = Ndef.UriMessage(longUri);
        A(lm[0] == 0xC1 && Ndef.Uris(lm).Single() == longUri, "NDEF: registro largo (>255 B)");
        // license card layout: identity URI, external record, AAR — the identity URI is found
        var multi = new List<byte>();
        var u = Ndef.UriMessage("avohorse://identity/rider/RIDER_001");
        u[0] = 0x91;                                                                   // MB | SR | TNF well-known (not ME)
        multi.AddRange(u);
        var lic = Encoding.ASCII.GetBytes("avoperformance.org:lic");
        multi.AddRange(new byte[] { 0x14, (byte)lic.Length, 3 }); multi.AddRange(lic); multi.AddRange(new byte[] { 1, 2, 3 });   // SR | TNF external
        var aar = Encoding.ASCII.GetBytes("android.com:pkg");
        multi.AddRange(new byte[] { 0x54, (byte)aar.Length, 2 }); multi.AddRange(aar); multi.AddRange("ab"u8.ToArray());        // ME | SR | TNF external
        A(Ndef.Uris(multi.ToArray()).First() == "avohorse://identity/rider/RIDER_001", "NDEF: tarjeta con licencia (URI + registro externo + AAR)");
        A(Throws(() => Ndef.Parse(m.AsSpan(0, m.Length - 3))), "NDEF: mensaje truncado rechazado");
        A(Ndef.FindMessageTlv(new byte[] { 0x01, 0x03, 0xA0, 0x0C, 0x34, 0x03, 0x02, 0xAA, 0xBB, 0xFE }) is [0xAA, 0xBB], "TLV: salta Lock Control y encuentra NDEF");
        A(Ndef.FindMessageTlv(new byte[] { 0x00, 0xFE, 0x03, 0x01, 0x00 }) is null, "TLV: terminador antes del mensaje");
        var tlv = Ndef.MessageTlv(m);
        A(tlv[0] == 0x03 && tlv[1] == m.Length && tlv[2 + m.Length] == 0xFE && tlv.Length % 4 == 0, "TLV: mensaje + terminador en páginas completas");
    }

    // ---------------------------------------------------------------- NTAG215 behind a PC/SC reader (simulated)
    private sealed class SimNtag
    {
        public readonly byte[] Mem = new byte[135 * 4];        // NTAG215: 135 pages
        public readonly HashSet<int> Written = [];
        public SimNtag(byte access = 0x00)
        {
            byte[] uid = [0x04, 0xA1, 0xB2, 0xC3, 0xD4, 0xE5, 0xF6];
            uid.AsSpan(0, 3).CopyTo(Mem); uid.AsSpan(3, 4).CopyTo(Mem.AsSpan(4));
            Mem[12] = 0xE1; Mem[13] = 0x10; Mem[14] = 0x3E; Mem[15] = access;   // CC: 496 B data area
            Mem[16] = 0x03; Mem[17] = 0x00; Mem[18] = 0xFE;                      // factory: empty NDEF
        }
        public byte[] Tx(byte[] a)
        {
            byte[] ok = [0x90, 0x00];
            if (a is [0xFF, 0xCA, 0x00, 0x00, ..]) return [0x04, 0xA1, 0xB2, 0xC3, 0xD4, 0xE5, 0xF6, .. ok];
            if (a.Length == 5 && a[0] == 0xFF && a[1] == 0xB0)
            {
                int p = a[3], n = a[4] == 0 ? 16 : a[4];
                if (p * 4 + n > Mem.Length) return [0x6A, 0x82];
                return [.. Mem.AsSpan(p * 4, n).ToArray(), .. ok];
            }
            if (a.Length == 9 && a[0] == 0xFF && a[1] == 0xD6 && a[4] == 4)
            {
                int p = a[3];
                if (p < 4 || p >= 130) return [0x63, 0x00];                     // refuse UID/CC/config pages like the chip
                a.AsSpan(5, 4).CopyTo(Mem.AsSpan(p * 4));
                Written.Add(p);
                return ok;
            }
            return [0x6D, 0x00];
        }
    }

    private static void NtagThroughReader()
    {
        var tag = new SimNtag();
        A(NtagApdu.ReadUid(tag.Tx) == "04A1B2C3D4E5F6", "NTAG: UID por GET DATA");
        A(NtagApdu.ReadMessage(tag.Tx) is { Length: 0 }, "NTAG: etiqueta nueva = mensaje NDEF vacío");
        var rec = new IdentityRecord { Code = "HORSE_014", Name = "Duna", Breed = "Hispano-árabe", BirthYear = 2016, Notes = "Cicatriz en la mano izquierda" };
        var msg = Ndef.UriMessage(AvoIdentityTag.BuildUri(IdentityKind.Horse, rec));
        NtagApdu.WriteMessage(tag.Tx, msg);
        A(tag.Written.Count > 0 && tag.Written.All(p => p >= 4 && p < 4 + 496 / 4), "NTAG: solo se escribe el área de datos (nunca UID, CC ni configuración)");
        var read = NtagApdu.ReadMessage(tag.Tx);
        A(read is not null && read.AsSpan().SequenceEqual(msg), "NTAG: lo grabado se lee igual");
        var parsed = AvoIdentityTag.Parse(Ndef.Uris(read!).Single());
        A(parsed is { Code: "HORSE_014", Name: "Duna", Breed: "Hispano-árabe", BirthYear: 2016 }, "NTAG: ficha completa desde la etiqueta");
        var locked = new SimNtag(access: 0x0F);
        bool refused = false;
        try { NtagApdu.WriteMessage(locked.Tx, msg); } catch (NfcException) { refused = true; }
        A(refused && locked.Written.Count == 0, "NTAG: etiqueta de solo lectura no se toca");
        bool tooBig = false;
        try { NtagApdu.WriteMessage(new SimNtag().Tx, Ndef.UriMessage("avohorse://identity/horse/H?v=2&notes=" + new string('n', 600))); } catch (NfcException) { tooBig = true; }
        A(tooBig, "NTAG: mensaje que no cabe rechazado antes de escribir");
        var notNdef = new SimNtag(); notNdef.Mem[12] = 0x00;
        bool nf = false;
        try { NtagApdu.ReadMessage(notNdef.Tx); } catch (NfcException) { nf = true; }
        A(nf, "NTAG: etiqueta sin formato NDEF detectada");
    }

    // ---------------------------------------------------------------- Cuadra / Jinetes / assignments
    private static void Store(string dir)
    {
        if (Directory.Exists(dir)) Directory.Delete(dir, true);
        Directory.CreateDirectory(dir);
        string path = Path.Combine(dir, "cuadra.json");
        var st = new StableStore(path);
        A(st.NextCode(IdentityKind.Horse) == "HORSE_001" && st.NextCode(IdentityKind.Rider) == "RIDER_001", "Cuadra: códigos HORSE_001 / RIDER_001");
        st.Add(IdentityKind.Horse, new IdentityRecord { Code = "HORSE_001", Name = "Rayo" });
        A(st.NextCode(IdentityKind.Horse) == "HORSE_002", "Cuadra: siguiente código libre");
        bool dup = false;
        try { st.Add(IdentityKind.Horse, new IdentityRecord { Code = "horse_001", Name = "Otro" }); } catch (ArgumentException) { dup = true; }
        A(dup, "Cuadra: código repetido rechazado");

        // a tag never overwrites the local record
        st.Update(IdentityKind.Horse, "HORSE_001", r => r.Notes = "nota local");
        var (same, created) = st.ImportTag(AvoIdentityTag.Parse("avohorse://identity/horse/HORSE_001?v=2&name=Otro%20nombre"), "04AA");
        A(!created && same.Name == "Rayo" && same.Notes == "nota local" && st.Find(IdentityKind.Horse, "HORSE_001")!.NfcUid == "04AA", "Cuadra: la etiqueta no sobrescribe la ficha (solo recuerda el UID)");
        var (nr, c2) = st.ImportTag(AvoIdentityTag.Parse("avohorse://identity/rider/RIDER_007?v=2&name=Antonio"), "04BB");
        A(c2 && nr.Name == "Antonio" && nr.Origin == "NFC", "Jinetes: alta desde etiqueta");

        // trainings: code in the file, name only, nothing
        var withCode = new TrainingSession { SessionId = "S1", HorseCode = "HORSE_001", Horse = "HORSE_001", Rider = "Antonio" };
        var nameOnly = new TrainingSession { SessionId = "S2", Horse = "Brisa", Rider = "Sin identificar" };
        var nothing = new TrainingSession { SessionId = "S3" };
        var demo = new TrainingSession { SessionId = "DEMO_X", HorseCode = "HORSE_D1", Horse = "Demo" };
        foreach (var s in new[] { withCode, nameOnly, nothing, demo }) st.RegisterFromTraining(s);
        A(st.Find(IdentityKind.Horse, "HORSE_D1") is { Demo: true } && st.FindByName(IdentityKind.Horse, "Brisa") is { Origin: "entrenamiento" }, "Cuadra: caballos de los archivos registrados (demo marcado)");
        A(st.Riders.Count(x => x.Name == "Antonio") == 1, "Jinetes: un archivo con el mismo nombre no duplica");
        var a1 = st.Apply(withCode);
        A(a1.Horse.Name == "Rayo" && a1.Horse.Code == "HORSE_001" && withCode.Horse == "Rayo" && withCode.HorseInFile == "HORSE_001", "Asignación: código del archivo → nombre de la Cuadra");
        A(a1.Rider.Code == "RIDER_007" && withCode.Rider == "Antonio", "Asignación: nombre del archivo → ficha del jinete");
        var a3 = st.Apply(nothing);
        A(!a3.Horse.Known && !a3.Rider.Known && nothing.Horse == StableStore.Unknown, "Asignación: entrenamiento sin caballo ni jinete");
        st.Assign("S3", true, "HORSE_001", true, "RIDER_007");
        var a3b = st.Apply(nothing);
        A(a3b.Horse.Name == "Rayo" && a3b.Rider.Name == "Antonio" && a3b.Horse.Source == "asignado", "Asignación: caballo y jinete asignados a un entrenamiento que venía sin ellos");
        st.Assign("S1", true, st.FindByName(IdentityKind.Horse, "Brisa")!.Code, false, null);
        A(st.Apply(withCode).Horse.Name == "Brisa" && st.Apply(withCode).Rider.Name == "Antonio", "Asignación: la del usuario manda sobre el archivo, y solo cambia lo elegido");
        st.Assign("S1", true, null, false, null);
        A(st.Apply(withCode).Horse.Name == "Rayo" && st.Assignment("S1") is null, "Asignación: vaciar vuelve a lo que dice el archivo");
        bool unknownRef = false;
        try { st.Assign("S2", true, "NO_EXISTE", false, null); } catch (KeyNotFoundException) { unknownRef = true; }
        A(unknownRef, "Asignación: no se asigna un código que no está registrado");
        st.Update(IdentityKind.Horse, "HORSE_001", r => r.Name = "Rayo de Luna");
        A(st.Apply(nothing).Horse.Name == "Rayo de Luna", "Cuadra: renombrar se ve en sus entrenamientos");
        st.Remove(IdentityKind.Horse, "HORSE_001");
        A(st.Apply(nothing).Horse.Source.Contains("eliminada") && st.Apply(withCode).Horse.Name == "HORSE_001", "Cuadra: eliminar no rompe los entrenamientos (vuelve el nombre del archivo)");

        // persistence and a damaged file
        var again = new StableStore(path);
        A(again.Riders.Any(r => r.Code == "RIDER_007" && r.NfcUid == "04BB") && again.Assignment("S3")?.RiderCode == "RIDER_007", "Cuadra: se guarda y se vuelve a leer");
        File.WriteAllText(path, "{ roto");
        var broken = new StableStore(path);
        A(broken.Horses.Count == 0 && Directory.GetFiles(dir, "cuadra.json.danado-*").Length == 1, "Cuadra: archivo dañado se conserva aparte, nunca se pierde en silencio");
        A(!StableStore.ValidCode("") && !StableStore.ValidCode("ÑÑÑÑÑÑÑÑÑÑÑÑ") && StableStore.ValidCode("HORSE_001"), "Cuadra: validación del código (23 bytes, como el reloj)");
    }
}
