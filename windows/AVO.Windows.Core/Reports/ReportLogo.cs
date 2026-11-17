namespace Avo.Windows.Core;

/// <summary>Logo of the report header (trainer's sketch 13/11/2026): (1) the horse head and (2) the «AVO · Horse Edition ·
/// Performance» logotype, both cut from avo_brand_hero (embedded resources, same files as the iPad report_*.imageset).</summary>
public static class ReportLogo
{
    public sealed record Part(byte[] Jpeg, int Width, int Height);

    public static Part? Head { get; } = Load("report_head.jpg");
    public static Part? Text { get; } = Load("report_text.jpg");

    private static Part? Load(string name)
    {
        using var s = typeof(ReportLogo).Assembly.GetManifestResourceStream(name);
        if (s is null) return null;
        using var ms = new MemoryStream();
        s.CopyTo(ms);
        byte[] b = ms.ToArray();
        return JpegSize(b) is (int w, int h) ? new Part(b, w, h) : null;
    }

    /// <summary>Pixel size from the JPEG SOF0/SOF2 marker.</summary>
    public static (int W, int H)? JpegSize(byte[] b)
    {
        int i = 2;
        while (i + 9 < b.Length)
        {
            if (b[i] != 0xFF) { i++; continue; }
            byte m = b[i + 1];
            int len = (b[i + 2] << 8) | b[i + 3];
            if (m is 0xC0 or 0xC1 or 0xC2) return ((b[i + 7] << 8) | b[i + 8], (b[i + 5] << 8) | b[i + 6]);
            i += 2 + len;
        }
        return null;
    }
}
