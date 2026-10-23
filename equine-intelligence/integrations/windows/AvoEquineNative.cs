// P/Invoke access to avo_equine.dll (same C++ engine as Android). Add to AVO.Windows.Core and copy the DLL next to the EXE.
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace AVO.Windows.Core
{
    public static class AvoEquineNative
    {
        private const string Dll = "avo_equine";

        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] private static extern IntPtr avo_eq_version();
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
        private static extern int avo_eq_analyse_files(IntPtr[] paths, int n, IntPtr processedAt, int series, out IntPtr json);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] private static extern void avo_eq_free(IntPtr p);

        public static string Version() => Utf8(avo_eq_version());

        /// <summary>Analyses one session (its RAW segments in order). Returns the analysis JSON; throws on error.</summary>
        public static string Analyse(string[] segments, bool withSeries = false)
        {
            var ptrs = new IntPtr[segments.Length];
            IntPtr when = IntPtr.Zero, json = IntPtr.Zero;
            try
            {
                for (int i = 0; i < segments.Length; i++) ptrs[i] = ToUtf8(segments[i]);
                when = ToUtf8(DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"));
                int rc = avo_eq_analyse_files(ptrs, ptrs.Length, when, withSeries ? 1 : 0, out json);
                string text = Utf8(json);
                if (rc != 0) throw new InvalidOperationException(text);
                return text;
            }
            finally
            {
                foreach (var p in ptrs) if (p != IntPtr.Zero) Marshal.FreeHGlobal(p);
                if (when != IntPtr.Zero) Marshal.FreeHGlobal(when);
                if (json != IntPtr.Zero) avo_eq_free(json);
            }
        }

        private static IntPtr ToUtf8(string s)
        {
            byte[] b = Encoding.UTF8.GetBytes(s + "\0");
            IntPtr p = Marshal.AllocHGlobal(b.Length);
            Marshal.Copy(b, 0, p, b.Length);
            return p;
        }

        private static string Utf8(IntPtr p)
        {
            if (p == IntPtr.Zero) return "";
            int n = 0; while (Marshal.ReadByte(p, n) != 0) n++;
            var b = new byte[n]; Marshal.Copy(p, b, 0, n);
            return Encoding.UTF8.GetString(b);
        }
    }
}
