using System.Diagnostics;
using System.IO;
using System.IO.Ports;
using System.Windows.Input;
using System.Windows.Threading;
using Microsoft.Win32;
using Avo.Windows.Core;

namespace Avo.Windows.ViewModels;

// Automatic download of trainings from the chest watch over USB (CHEST >= 3.7.5-usb1, protocol AVO1), ported from
// Windows V1.1 (feature/chest-usb-pc-sync, MainWindow.Usb.cs). The window forwards WM_DEVICECHANGE; a 4 s timer covers
// drivers that do not send it and a watch that was recording.
public sealed partial class MainViewModel
{
    private readonly HashSet<string> _usbHandled = new(StringComparer.OrdinalIgnoreCase);
    private CancellationTokenSource? _usbCts;
    private bool _usbBusy;
    private DispatcherTimer? _usbTimer;
    private string _usbStatus = "Reloj: conecta el reloj de pecho por USB-C para descargar sus entrenamientos.";
    public string UsbStatus { get => _usbStatus; private set => Set(ref _usbStatus, value); }
    public string UsbFolder => WatchLibrary.DefaultFolder;
    public ICommand UsbSyncCommand { get; private set; } = null!;
    public ICommand UsbFolderCommand { get; private set; } = null!;
    /// <summary>Disabled in the CI capture mode (no watch, no registry probing noise).</summary>
    public bool UsbEnabled { get; set; } = true;

    private void InitUsb()
    {
        UsbSyncCommand = new AsyncCommand(_ => UsbScanAsync(true), Fail);
        UsbFolderCommand = new RelayCommand(() =>
        {
            try
            {
                Directory.CreateDirectory(WatchLibrary.DefaultFolder);
                Process.Start(new ProcessStartInfo("explorer.exe", "\"" + WatchLibrary.DefaultFolder + "\"") { UseShellExecute = true });
            }
            catch (Exception ex) { UsbStatus = "No se pudo abrir la carpeta: " + ex.Message; }
        });
        _usbTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(4) };
        _usbTimer.Tick += async (_, _) => { if (UsbEnabled) await UsbScanAsync(false); };
        _usbTimer.Start();
    }

    public void StopUsb() { _usbTimer?.Stop(); _usbCts?.Cancel(); }

    /// <summary>Called by the window on WM_DEVICECHANGE (after a short delay for Windows to create the COM port).</summary>
    public async Task UsbDeviceChangedAsync()
    {
        await Task.Delay(1500);
        if (UsbEnabled) await UsbScanAsync(false);
    }

    public async Task UsbScanAsync(bool manual)
    {
        if (_usbBusy) return;
        List<string> ports;
        try { ports = await Task.Run(ChestPortFinder.Find); }
        catch (Exception ex) { if (manual) UsbStatus = "No se pudieron leer los puertos USB: " + ex.Message; return; }
        _usbHandled.RemoveWhere(p => !ports.Contains(p, StringComparer.OrdinalIgnoreCase));   // unplugged: sync again next time
        var todo = manual ? ports : ports.Where(p => !_usbHandled.Contains(p)).ToList();
        if (todo.Count == 0)
        {
            if (manual) UsbStatus = "No se detecta ningún reloj AVO por USB (dispositivo VID 303A / PID 1001). Usa un cable USB-C de datos, no solo de carga.";
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
        var known = Sessions.Where(s => s.Session.Sha256 != null).GroupBy(s => s.Id)
            .ToDictionary(g => g.Key, g => g.First().Session.Sha256!, StringComparer.Ordinal);
        var progress = new Progress<ChestSyncProgress>(p => { UsbStatus = p.Text; Status = p.Text; });
        _usbCts = new CancellationTokenSource();
        var token = _usbCts.Token;
        UsbStatus = $"Reloj detectado en {port}: comprobando entrenamientos…";
        Status = UsbStatus;
        Busy = true;
        try
        {
            var result = await Task.Run(() =>
            {
                using var link = new SerialChestLink(port);
                var client = new ChestUsbClient(link);
                var library = new WatchLibrary(WatchLibrary.DefaultFolder);
                return ChestSync.Run(client, library, known, progress, token);
            }, token);
            if (result.Recording) _usbHandled.Remove(port);   // asked again until the recording ends
            var w = result.Watch;
            string head = w is null ? port : $"Reloj AVO {w.Device[^4..].ToUpperInvariant()} · firmware {w.Firmware} · batería {(w.BatteryPct >= 0 ? w.BatteryPct + " %" : "—")}";
            UsbStatus = head + " — " + result.Summary + (result.Messages.Count > 0 ? " · " + string.Join(" · ", result.Messages.Take(3)) : "");
            Status = result.Summary;
            Log.Info("usb", result.Summary, new { port, nuevos = result.NewPackages.Count });
            if (result.NewPackages.Count > 0)
            {
                if (Page == "Home") Page = "Sessions";
                await ImportFilesAsync(result.NewPackages);
            }
        }
        catch (OperationCanceledException) { UsbStatus = "Descarga del reloj cancelada"; }
        catch (ChestUsbException ex) when (ex.Command == "HELLO" && ex.Code == "timeout")
        {
            UsbStatus = $"Hay un reloj AVO en {port}, pero su firmware no tiene descarga por USB (necesita CHEST 3.7.5-usb1 o posterior, instalable con AVO Update). " +
                        "Mientras tanto: exporta el entrenamiento desde la app Android como .avo y ábrelo aquí.";
        }
        catch (UnauthorizedAccessException)
        {
            UsbStatus = $"El puerto {port} está ocupado por otro programa (¿AVO Update o un monitor serie?). Ciérralo y pulsa «Sincronizar reloj».";
        }
        catch (Exception ex) when (ex is ChestUsbException or IOException or InvalidOperationException or InvalidDataException)
        {
            UsbStatus = $"Descarga del reloj interrumpida ({port}): {ex.Message}. Se reanuda al volver a conectarlo.";
        }
        finally { Busy = false; Status = UsbStatus; }
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
