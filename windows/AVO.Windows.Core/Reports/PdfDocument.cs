using System.Globalization;
using System.IO.Compression;
using System.Text;

namespace Avo.Windows.Core;

/// <summary>
/// Minimal, dependency-free PDF 1.4 writer (vector text and graphics) for the AVO reports. Uses the standard Type 1
/// fonts Helvetica / Helvetica-Bold with WinAnsiEncoding (covers Spanish), Flate-compressed content streams and a
/// correct cross-reference table. Coordinates are in points with the origin at the TOP-left of the page.
/// </summary>
public sealed class PdfDocument
{
    public const double A4Width = 595.28, A4Height = 841.89;
    private static readonly CultureInfo Inv = CultureInfo.InvariantCulture;
    private readonly List<StringBuilder> _pages = [];
    private StringBuilder? _cur;
    public double Width { get; } = A4Width;
    public double Height { get; } = A4Height;
    public int PageCount => _pages.Count;
    public string Title { get; set; } = "Informe AVO";

    public void NewPage()
    {
        _cur = new StringBuilder();
        _pages.Add(_cur);
    }

    private StringBuilder C => _cur ?? throw new InvalidOperationException("Llama a NewPage() antes de dibujar");
    private static string N(double v) => Math.Round(v, 3).ToString("0.###", Inv);
    private static string Rgb((byte r, byte g, byte b) c) => $"{N(c.r / 255.0)} {N(c.g / 255.0)} {N(c.b / 255.0)}";

    public void FillRect(double x, double y, double w, double h, (byte, byte, byte) color) =>
        C.Append(Rgb(color)).Append(" rg ").Append(N(x)).Append(' ').Append(N(Height - y - h)).Append(' ').Append(N(w)).Append(' ').Append(N(h)).Append(" re f\n");

    public void StrokeRect(double x, double y, double w, double h, (byte, byte, byte) color, double width = 0.5) =>
        C.Append(Rgb(color)).Append(" RG ").Append(N(width)).Append(" w ").Append(N(x)).Append(' ').Append(N(Height - y - h)).Append(' ').Append(N(w)).Append(' ').Append(N(h)).Append(" re S\n");

    public void Line(double x1, double y1, double x2, double y2, (byte, byte, byte) color, double width = 0.5)
    {
        C.Append(Rgb(color)).Append(" RG ").Append(N(width)).Append(" w 1 J ")
            .Append(N(x1)).Append(' ').Append(N(Height - y1)).Append(" m ").Append(N(x2)).Append(' ').Append(N(Height - y2)).Append(" l S\n");
    }

    /// <summary>Open polyline; NaN points break the line.</summary>
    public void Polyline(IReadOnlyList<(double x, double y)> pts, (byte, byte, byte) color, double width = 1)
    {
        C.Append(Rgb(color)).Append(" RG ").Append(N(width)).Append(" w 1 J 1 j\n");
        bool open = false;
        foreach (var (x, y) in pts)
        {
            if (!double.IsFinite(x) || !double.IsFinite(y)) { if (open) C.Append("S\n"); open = false; continue; }
            C.Append(N(x)).Append(' ').Append(N(Height - y)).Append(open ? " l\n" : " m\n");
            open = true;
        }
        if (open) C.Append("S\n");
    }

    public void Circle(double cx, double cy, double r, (byte, byte, byte) fill)
    {
        const double k = 0.5523;
        double y = Height - cy;
        C.Append(Rgb(fill)).Append(" rg ")
            .Append($"{N(cx + r)} {N(y)} m {N(cx + r)} {N(y + k * r)} {N(cx + k * r)} {N(y + r)} {N(cx)} {N(y + r)} c ")
            .Append($"{N(cx - k * r)} {N(y + r)} {N(cx - r)} {N(y + k * r)} {N(cx - r)} {N(y)} c ")
            .Append($"{N(cx - r)} {N(y - k * r)} {N(cx - k * r)} {N(y - r)} {N(cx)} {N(y - r)} c ")
            .Append($"{N(cx + k * r)} {N(y - r)} {N(cx + r)} {N(y - k * r)} {N(cx + r)} {N(y)} c f\n");
    }

    public enum Align { Left, Center, Right }

    /// <summary>Single line of text; y is the TOP of the text box.</summary>
    public void Text(double x, double y, string text, double size = 10, bool bold = false, (byte, byte, byte)? color = null, Align align = Align.Left)
    {
        double w = MeasureText(text, size, bold);
        double tx = align switch { Align.Center => x - w / 2, Align.Right => x - w, _ => x };
        double baseline = Height - y - size * 0.82;
        C.Append("BT /").Append(bold ? "F2 " : "F1 ").Append(N(size)).Append(" Tf ").Append(Rgb(color ?? (0x10, 0x10, 0x14)))
            .Append(" rg ").Append(N(tx)).Append(' ').Append(N(baseline)).Append(" Td (").Append(Escape(text)).Append(") Tj ET\n");
    }

    /// <summary>Word-wrapped paragraph. Returns the height used.</summary>
    public double Paragraph(double x, double y, double maxWidth, string text, double size = 9.5, bool bold = false, (byte, byte, byte)? color = null, double leading = 1.3)
    {
        double lineH = size * leading, used = 0;
        foreach (var para in text.Replace("\r", "").Split('\n'))
        {
            var words = para.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            var line = new StringBuilder();
            foreach (var word in words)
            {
                string probe = line.Length == 0 ? word : line + " " + word;
                if (MeasureText(probe, size, bold) > maxWidth && line.Length > 0)
                {
                    Text(x, y + used, line.ToString(), size, bold, color);
                    used += lineH;
                    line.Clear().Append(word);
                }
                else { line.Clear().Append(probe); }
            }
            if (line.Length > 0) { Text(x, y + used, line.ToString(), size, bold, color); used += lineH; }
            else if (words.Length == 0) used += lineH * 0.5;
        }
        return used;
    }

    public static double MeasureText(string text, double size, bool bold)
    {
        double w = 0;
        foreach (char ch in text) w += GlyphWidth(ch, bold);
        return w * size / 1000.0;
    }

    // Adobe AFM widths of Helvetica and Helvetica-Bold for ASCII 32..126.
    private static readonly short[] Regular =
    [
        278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278, 556, 556, 556, 556, 556, 556, 556, 556, 556, 556,
        278, 278, 584, 584, 584, 556, 1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778, 667, 778, 722, 667,
        611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556, 333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833,
        556, 556, 556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584,
    ];
    private static readonly short[] Bold =
    [
        278, 333, 474, 556, 556, 889, 722, 238, 333, 333, 389, 584, 278, 333, 278, 278, 556, 556, 556, 556, 556, 556, 556, 556, 556, 556,
        333, 333, 584, 584, 584, 611, 975, 722, 722, 722, 722, 667, 611, 778, 722, 278, 556, 722, 611, 833, 722, 778, 667, 778, 722, 667,
        611, 722, 667, 944, 667, 667, 611, 333, 278, 333, 584, 556, 333, 556, 611, 556, 611, 556, 333, 611, 611, 278, 278, 556, 278, 889,
        611, 611, 611, 611, 389, 556, 333, 611, 556, 778, 556, 556, 500, 389, 280, 389, 584,
    ];

    private static double GlyphWidth(char ch, bool bold)
    {
        var table = bold ? Bold : Regular;
        if (ch >= 32 && ch <= 126) return table[ch - 32];
        char b = BaseLetter(ch);
        if (b != ch && b >= 32 && b <= 126) return table[b - 32];
        return ch switch
        {
            '€' => 556, '–' => 556, '—' => 1000, '•' => 350, '…' => 1000, '°' => 400, '·' => 278, 'º' or 'ª' => 370,
            '±' or '×' => 584, '²' or '³' => 333, '¿' => 611, '¡' => 333, '‘' or '’' => 222, '“' or '”' => 333, _ => 556,
        };
    }

    private static char BaseLetter(char c) => c switch
    {
        'á' or 'à' or 'â' or 'ä' => 'a', 'é' or 'è' or 'ê' or 'ë' => 'e', 'í' or 'ì' or 'î' or 'ï' => 'i', 'ó' or 'ò' or 'ô' or 'ö' => 'o',
        'ú' or 'ù' or 'û' or 'ü' => 'u', 'ñ' => 'n', 'ç' => 'c', 'Á' or 'À' => 'A', 'É' or 'È' => 'E', 'Í' => 'I', 'Ó' => 'O', 'Ú' or 'Ü' => 'U',
        'Ñ' => 'N', 'Ç' => 'C', _ => c,
    };

    /// <summary>WinAnsiEncoding byte of a character, or '?' when it is not representable.</summary>
    public static byte WinAnsi(char c)
    {
        if (c < 0x80) return (byte)c;
        if (c >= 0xA0 && c <= 0xFF) return (byte)c;
        return c switch
        {
            '€' => 0x80, '‚' => 0x82, '„' => 0x84, '…' => 0x85, '‘' => 0x91, '’' => 0x92, '“' => 0x93, '”' => 0x94, '•' => 0x95, '–' => 0x96,
            '—' => 0x97, '™' => 0x99, '−' => (byte)'-', '²' => 0xB2, _ => (byte)'?',
        };
    }

    private static string Escape(string s)
    {
        var sb = new StringBuilder(s.Length + 8);
        foreach (char ch in s)
        {
            byte b = WinAnsi(ch);
            if (b == '(' || b == ')' || b == '\\') sb.Append('\\').Append((char)b);
            else if (b < 32 || b > 126) sb.Append('\\').Append(Convert.ToString(b, 8).PadLeft(3, '0'));
            else sb.Append((char)b);
        }
        return sb.ToString();
    }

    public void Save(Stream output)
    {
        if (_pages.Count == 0) NewPage();
        var offsets = new List<long>();
        var latin = Encoding.Latin1;
        long pos = 0;
        void W(string s) { var b = latin.GetBytes(s); output.Write(b); pos += b.Length; }
        void WB(byte[] b) { output.Write(b); pos += b.Length; }
        W("%PDF-1.4\n%âãÏÓ\n");
        int pageCount = _pages.Count;
        int firstPageObj = 5;
        // 1 catalog, 2 pages, 3 F1, 4 F2, then (page, content) pairs, then info
        offsets.Add(pos); W("1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n");
        var kids = string.Join(" ", Enumerable.Range(0, pageCount).Select(i => $"{firstPageObj + 2 * i} 0 R"));
        offsets.Add(pos); W($"2 0 obj\n<< /Type /Pages /Kids [{kids}] /Count {pageCount} >>\nendobj\n");
        offsets.Add(pos); W("3 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>\nendobj\n");
        offsets.Add(pos); W("4 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>\nendobj\n");
        for (int i = 0; i < pageCount; i++)
        {
            int pageObj = firstPageObj + 2 * i, contentObj = pageObj + 1;
            offsets.Add(pos);
            W($"{pageObj} 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {N(Width)} {N(Height)}] /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents {contentObj} 0 R >>\nendobj\n");
            byte[] raw = latin.GetBytes(_pages[i].ToString());
            byte[] packed;
            using (var ms = new MemoryStream())
            {
                using (var z = new ZLibStream(ms, CompressionLevel.Optimal, true)) z.Write(raw);
                packed = ms.ToArray();
            }
            offsets.Add(pos);
            W($"{contentObj} 0 obj\n<< /Length {packed.Length} /Filter /FlateDecode >>\nstream\n");
            WB(packed);
            W("\nendstream\nendobj\n");
        }
        int infoObj = firstPageObj + 2 * pageCount;
        offsets.Add(pos);
        W($"{infoObj} 0 obj\n<< /Title ({Escape(Title)}) /Producer (AVO Performance Horse Windows) /CreationDate (D:{DateTime.UtcNow:yyyyMMddHHmmss}Z) >>\nendobj\n");
        long xref = pos;
        W($"xref\n0 {offsets.Count + 1}\n0000000000 65535 f \n");
        foreach (var o in offsets) W($"{o:D10} 00000 n \n");
        W($"trailer\n<< /Size {offsets.Count + 1} /Root 1 0 R /Info {infoObj} 0 R >>\nstartxref\n{xref}\n%%EOF\n");
    }
}
