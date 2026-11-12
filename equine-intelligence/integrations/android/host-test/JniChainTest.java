import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import org.avoperformance.horse.engine.AvoEquine;

/** RAW -> JNI -> engine -> JSON on the host JVM. Usage: java -Djava.library.path=DIR JniChainTest SESSION.avo WORKDIR */
public class JniChainTest {
  static int fails = 0;
  static void check(boolean c, String what) { System.out.println((c ? "[ OK ] " : "[FALLO] ") + what); if (!c) fails++; }
  static byte[] u(String s) { return s.getBytes(StandardCharsets.UTF_8); }
  static String s(byte[] b) { return new String(b, StandardCharsets.UTF_8); }

  public static void main(String[] a) throws Exception {
    Path src = Paths.get(a[0]); Path work = Paths.get(a[1]);
    Files.createDirectories(work);
    // UTF-8 outside the BMP in the path: would break modified-UTF-8 string passing
    Path p = work.resolve("sesión_🐎.avo");
    Files.copy(src, p, StandardCopyOption.REPLACE_EXISTING);
    check(s(AvoEquine.nativeVersion()).startsWith("1.1.0"), "versión del motor " + s(AvoEquine.nativeVersion()));
    check(AvoEquine.nativeApiVersion() == 2, "API C versión 2");
    byte[][] paths = { u(p.toString()) };
    long tok = AvoEquine.nativeNewToken();
    String opts = "{\"series\":true,\"cache_dir\":\"" + work.resolve("analisis").toString().replace("\\", "\\\\") + "\"}";
    String r1 = s(AvoEquine.nativeAnalyse(paths, u(opts), tok));
    check(r1.contains("\"cache\":\"CALCULADO\"") && r1.contains("\"formato\":\"avo-equine-analysis\""), "análisis con persistencia (CALCULADO)");
    check(r1.contains("\"series_cincha\"") && r1.contains("\"rendimiento\""), "resultado con series y rendimiento por aire");
    String r2 = s(AvoEquine.nativeAnalyse(paths, u(opts), tok));
    check(r2.contains("\"cache\":\"ACIERTO\""), "segunda apertura reutiliza el análisis guardado (ACIERTO)");
    AvoEquine.nativeCancel(tok);
    String r3 = s(AvoEquine.nativeAnalyse(paths, u("{}"), tok));
    check(r3.contains("\"cancelado\":true"), "cancelación desde otro hilo / antes de empezar");
    AvoEquine.nativeFreeToken(tok);
    String r4 = s(AvoEquine.nativeAnalyse(new byte[][] { u(work.resolve("no_existe.avo").toString()) }, u("{}"), 0));
    check(r4.contains("\"error\"") && r4.contains("\"codigo\":1"), "error de entrada devuelto como JSON");
    String c = s(AvoEquine.nativeCompare(paths, paths, u("{\"mismo_recorrido\":true}"), 0));
    check(c.contains("\"formato\":\"avo-equine-comparison\"") && c.contains("\"comparable\":true"), "comparación de la sesión consigo misma");
    check(AvoEquine.nativeCacheInvalidate(u(work.resolve("analisis").toString())) == 0, "sin análisis obsoletos que invalidar");
    check(Files.size(p) == Files.size(src) && java.util.Arrays.equals(Files.readAllBytes(p), Files.readAllBytes(src)), "el fichero RAW no se modifica");
    System.out.println(fails == 0 ? "JNI: cadena completa correcta" : "JNI: " + fails + " fallos");
    System.exit(fails == 0 ? 0 : 1);
  }
}
