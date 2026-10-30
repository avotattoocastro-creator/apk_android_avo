using System.Diagnostics;
using System.IO;
using System.IO.Ports;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Threading;
using Microsoft.Win32;
using Avo.Windows.Core;

namespace Avo.Windows;

// Automatic download from the chest watch when it is plugged in by USB (CHEST >= 3.7.5-usb1, protocol AVO1).
public partial class MainWindow
{
    private const int WmDeviceChange = 0x0219;
    private readonly HashSet<string> _usbHandled = new(StringComparer.OrdinalIgnoreCase);
    private CancellationTokenSource? _usbCts;
    private bool _usbBusy;

    private void InitUsb()
    {
        SourceInitialized += (_, _) =>
        {
            if (PresentationSource.FromVisual(this) is HwndSource source) source.AddHook(UsbHook);
        };
        // Periodic check as well: some drivers do not send WM_DEVICECHANGE to the window, and a watch that was
        // recording is asked again until the recording ends.
        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(4) };
        timer.Tick += async (_, _) => await UsbScanAsync(false);
        Loaded += (_, _) => timer.Start();
        Closing += (_, _) => { timer.Stop(); _usbCts?.Cancel(); };
        UsbFolderText.Text = "Carpeta: " + WatchLibrary.DefaultFolder;
    }

    private IntPtr UsbHook(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WmDeviceChange)
        {
            // Windows needs a moment to create the COM port after the arrival notice.
            var once = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(1500) };
            once.Tick += async (_, _) => { once.Stop(); await UsbScanAsync(false); };
            once.Start();
        }
        return IntPtr.Zero;
    }

    private async void UsbSync_Click(object sender, RoutedEventArgs e) => await UsbScanAsync(true);

    private void UsbFolder_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Directory.CreateDirectory(WatchLibrary.DefaultFolder);
            Process.Start(new ProcessStartInfo("explorer.exe", "\"" + WatchLibrary.DefaultFolder + "\"") { UseShellExecute = true });
        }
        catch (Exception ex) { UsbStatus.Text = "No se pudo abrir la carpeta: " + ex.Message; }
    }

    private async Task UsbScanAsync(bool manual)
    {
        if (_usbBusy) return;
        List<string> ports;
        try { ports = await Task.Run(ChestPortFinder.Find); }
        catch (Exception ex) { if (manual) UsbStatus.Text = "No se pudieron leer los puertos USB: " + ex.Message; return; }
        _usbHandled.RemoveWhere(p => !ports.Contains(p, StringComparer.OrdinalIgnoreCase));   // unplugged: sync again next time
        var todo = manual ? ports : ports.Where(p => !_usbHandled.Contains(p)).ToList();
        if (todo.Count == 0)
        {
            if (manual) UsbStatus.Text = "No hay ningún reloj AVO conectado por USB";
            return;
        }
        _usbBusy = true;
        try
        {
            foreach (string port in todo)
            {
                _usbHandled.Add(port);
                await SyncPortAsync(port);
            }
        }
        finally { _usbBusy = false; }
    }

    private async Task SyncPortAsync(string port)
    {
        var known = _sessions.Where(s => s.Sha256 != null).GroupBy(s => s.SessionId)
            .ToDictionary(g => g.Key, g => g.First().Sha256!, StringComparer.Ordinal);
        var progress = new Progress<ChestSyncProgress>(p => { UsbStatus.Text = p.Text; StatusLine.Text = p.Text; });
        _usbCts = new CancellationTokenSource();
        var token = _usbCts.Token;
        UsbStatus.Text = $"Reloj detectado en {port}: comprobando…";
        try
        {
            var result = await Task.Run(() =>
            {
                using var link = new SerialChestLink(port);
                var client = new ChestUsbClient(link);
                var library = new WatchLibrary(WatchLibrary.DefaultFolder);
                return ChestSync.Run(client, library, known, progress, token);
            }, token);
            if (result.Recording) _usbHandled.Remove(port);   // asked again on the next check, until the recording ends
            if (result.NewPackages.Count > 0) await ImportManyAsync(result.NewPackages, true);
            var w = result.Watch;
            string head = w is null ? port : $"Reloj AVO {w.Device[^4..].ToUpperInvariant()} · {w.Firmware} · batería {(w.BatteryPct >= 0 ? w.BatteryPct + " %" : "—")}";
            UsbStatus.Text = head + "\n" + result.Summary + (result.Messages.Count > 0 ? "\n" + string.Join("\n", result.Messages.Take(3)) : "");
            StatusLine.Text = result.Summary;
            if (result.NewPackages.Count > 0) Views.SelectedIndex = 0;
        }
        catch (OperationCanceledException) { UsbStatus.Text = "Descarga del reloj cancelada"; }
        catch (ChestUsbException ex) when (ex.Command == "HELLO" && ex.Code == "timeout")
        {
            UsbStatus.Text = $"El dispositivo USB de {port} no responde como reloj AVO. Hace falta el firmware 3.7.5-usb1 o posterior " +
                             "(o el reloj está en modo de programación).";
        }
        catch (UnauthorizedAccessException)
        {
            UsbStatus.Text = $"El puerto {port} está ocupado por otro programa (¿AVO Update o un monitor serie?). Ciérralo y pulsa SINCRONIZAR RELOJ.";
        }
        catch (Exception ex) when (ex is ChestUsbException or IOException or InvalidOperationException or InvalidDataException)
        {
            UsbStatus.Text = $"Descarga del reloj interrumpida ({port}): {ex.Message}. Se reanuda al volver a conectarlo.";
            StatusLine.Text = UsbStatus.Text;
        }
    }
}

/// <summary>COM ports of the chest watch (ESP32-S3 USB-Serial/JTAG, VID 303A / PID 1001) that are present now.</summary>
internal static class ChestPortFinder
{
    public static List<string> Find()
    {
        var present = new HashSet<string>(SerialPort.GetPortNames(), StringComparer.OrdinalIgnoreCase);
        var found = new List<string>();
        using var usb = Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Enum\USB");
        if (usb is null) return found;
        foreach (string dev in usb.GetSubKeyNames().Where(n => n.StartsWith("VID_303A&PID_1001", StringComparison.OrdinalIgnoreCase)))
        {
            using var devKey = usb.OpenSubKey(dev);
            if (devKey is null) continue;
            foreach (string inst in devKey.GetSubKeyNames())
            {
                using var p = devKey.OpenSubKey(inst + @"\Device Parameters");
                if (p?.GetValue("PortName") is string name && present.Contains(name) && !found.Contains(name, StringComparer.OrdinalIgnoreCase))
                    found.Add(name);
            }
        }
        return found;
    }
}

/// <summary>USB serial port of the watch. DTR and RTS stay low: that combination never resets the ESP32-S3.</summary>
internal sealed class SerialChestLink : IChestLink
{
    private readonly SerialPort _port;
    private readonly byte[] _buf = new byte[65536];
    private readonly List<byte> _acc = [];

    public SerialChestLink(string name)
    {
        _port = new SerialPort(name, 115200)
        {
            DtrEnable = false,
            RtsEnable = false,
            Handshake = Handshake.None,
            ReadBufferSize = 1 << 20,
            WriteTimeout = 2000,
        };
        _port.Open();
    }

    public void WriteLine(string line)
    {
        try
        {
            byte[] b = System.Text.Encoding.ASCII.GetBytes(line + "\n");
            _port.BaseStream.Write(b, 0, b.Length);
            _port.BaseStream.Flush();
        }
        catch (Exception ex) when (ex is IOException or InvalidOperationException or TimeoutException)
        {
            throw new ChestUsbException("USB", "timeout", "Reloj desconectado");
        }
    }

    public string? ReadLine(TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;
        while (true)
        {
            int nl = _acc.IndexOf((byte)'\n');
            if (nl >= 0)
            {
                string line = System.Text.Encoding.Latin1.GetString(_acc.GetRange(0, nl).ToArray());
                _acc.RemoveRange(0, nl + 1);
                return line;
            }
            var left = deadline - DateTime.UtcNow;
            if (left <= TimeSpan.Zero) return null;
            _port.ReadTimeout = Math.Max(1, (int)Math.Min(left.TotalMilliseconds, 1000));
            try
            {
                int n = _port.BaseStream.Read(_buf, 0, _buf.Length);
                for (int i = 0; i < n; i++) _acc.Add(_buf[i]);
                if (_acc.Count > 1 << 20) _acc.Clear();   // garbage without newlines: never grow without limit
            }
            catch (TimeoutException) { }
            catch (Exception ex) when (ex is IOException or InvalidOperationException)
            {
                throw new ChestUsbException("USB", "timeout", "Reloj desconectado");
            }
        }
    }

    public void Dispose() => _port.Dispose();
}
