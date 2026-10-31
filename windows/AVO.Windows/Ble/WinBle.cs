using System.Collections.Concurrent;
using System.IO;
using System.Runtime.InteropServices.WindowsRuntime;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;
using Avo.Windows.Core.Watch;
using Windows.Devices.Bluetooth;
using Windows.Devices.Bluetooth.Advertisement;
using Windows.Devices.Bluetooth.GenericAttributeProfile;
using Windows.Devices.Enumeration;

namespace Avo.Windows.Ble;

public sealed record BleWatchFound(ulong Address, string Name, short Rssi)
{
    public string AddressText => string.Join(":", BitConverter.GetBytes(Address).Take(6).Reverse().Select(b => b.ToString("X2")));
}

/// <summary>Finds AVO watches advertising (name AVO_XXXX / AVO-XXXX or the AVO service).</summary>
public static class WinBleScanner
{
    public static async Task<List<BleWatchFound>> ScanAsync(TimeSpan duration, CancellationToken ct)
    {
        var found = new ConcurrentDictionary<ulong, BleWatchFound>();
        var w = new BluetoothLEAdvertisementWatcher { ScanningMode = BluetoothLEScanningMode.Active };
        w.Received += (_, a) =>
        {
            string name = a.Advertisement.LocalName ?? "";
            bool avo = AvoGatt.NameRegex.IsMatch(name) || a.Advertisement.ServiceUuids.Contains(AvoGatt.Service);
            if (!avo) return;
            found.AddOrUpdate(a.BluetoothAddress, new BleWatchFound(a.BluetoothAddress, name, a.RawSignalStrengthInDBm),
                (_, old) => old with { Name = string.IsNullOrEmpty(name) ? old.Name : name, Rssi = a.RawSignalStrengthInDBm });
        };
        w.Start();
        try { await Task.Delay(duration, ct); }
        catch (TaskCanceledException) { }
        finally { w.Stop(); }
        if (w.Status == BluetoothLEAdvertisementWatcherStatus.Aborted)
            throw new IOException("Bluetooth no disponible: actívalo en Windows (Configuración → Bluetooth y dispositivos).");
        return found.Values.OrderByDescending(f => f.Rssi).ToList();
    }
}

/// <summary>
/// GATT link to the watch through the Windows Bluetooth LE API. Pairs with "Just Works" when the watch requires an encrypted
/// link (ble_require_bond, as with the Android app), subscribes to CTRL_TX and writes requests on CTRL_RX with response.
/// </summary>
public sealed class WinBleTransport : IAvoTransport, IDisposable
{
    private readonly BluetoothLEDevice _dev;
    private readonly GattSession _session;
    private readonly GattDeviceService _service;
    private readonly GattCharacteristic _rx;
    private readonly List<GattCharacteristic> _notify = [];
    public event Action<Guid, byte[]>? Notification;
    public event Action? Disconnected;
    public string Name => _dev.Name;
    public int AttPayload => Math.Max(20, _session.MaxPduSize - 3);

    private WinBleTransport(BluetoothLEDevice dev, GattSession session, GattDeviceService service, GattCharacteristic rx)
    {
        _dev = dev; _session = session; _service = service; _rx = rx;
        _dev.ConnectionStatusChanged += (d, _) => { if (d.ConnectionStatus == BluetoothConnectionStatus.Disconnected) Disconnected?.Invoke(); };
    }

    public static async Task<WinBleTransport> ConnectAsync(ulong address, IProgress<string>? p, CancellationToken ct)
    {
        p?.Report("Conectando con el reloj por Bluetooth…");
        var dev = await BluetoothLEDevice.FromBluetoothAddressAsync(address).AsTask(ct)
                  ?? throw new IOException("No se encuentra el reloj. Acércalo al PC y comprueba que está encendido.");
        var info = dev.DeviceInformation;
        if (!info.Pairing.IsPaired && info.Pairing.CanPair)
        {
            p?.Report("Emparejando por Bluetooth (sin código, como el móvil)…");
            var custom = info.Pairing.Custom;
            void Accept(DeviceInformationCustomPairing s, DevicePairingRequestedEventArgs a) => a.Accept();
            custom.PairingRequested += Accept;
            try
            {
                var r = await custom.PairAsync(DevicePairingKinds.ConfirmOnly, DevicePairingProtectionLevel.Encryption).AsTask(ct);
                if (r.Status is not (DevicePairingResultStatus.Paired or DevicePairingResultStatus.AlreadyPaired))
                    throw new IOException("No se pudo emparejar con el reloj: " + r.Status);
            }
            finally { custom.PairingRequested -= Accept; }
        }
        var session = await GattSession.FromDeviceIdAsync(dev.BluetoothDeviceId).AsTask(ct);
        session.MaintainConnection = true;
        var sr = await dev.GetGattServicesForUuidAsync(AvoGatt.Service, BluetoothCacheMode.Uncached).AsTask(ct);
        if (sr.Status != GattCommunicationStatus.Success || sr.Services.Count == 0)
            throw new IOException("El dispositivo no ofrece el servicio AVO (¿es un reloj AVO?). Estado: " + sr.Status);
        var svc = sr.Services[0];
        async Task<GattCharacteristic> Char(Guid id)
        {
            var cr = await svc.GetCharacteristicsForUuidAsync(id, BluetoothCacheMode.Uncached).AsTask(ct);
            if (cr.Status != GattCommunicationStatus.Success || cr.Characteristics.Count == 0) throw new IOException($"Falta la característica {id} ({cr.Status})");
            return cr.Characteristics[0];
        }
        var t = new WinBleTransport(dev, session, svc, await Char(AvoGatt.CtrlRx));
        foreach (var id in new[] { AvoGatt.CtrlTx, AvoGatt.FileTx })
        {
            var ch = await Char(id);
            ch.ValueChanged += (c, a) => t.Notification?.Invoke(c.Uuid, a.CharacteristicValue.ToArray());
            var st = await ch.WriteClientCharacteristicConfigurationDescriptorAsync(GattClientCharacteristicConfigurationDescriptorValue.Notify).AsTask(ct);
            if (st != GattCommunicationStatus.Success)
                throw new IOException(st == GattCommunicationStatus.AccessDenied
                    ? "El reloj exige un enlace cifrado: empareja el reloj con Windows y vuelve a intentarlo."
                    : "No se pudieron activar las notificaciones del reloj: " + st);
            t._notify.Add(ch);
        }
        return t;
    }

    public async Task WriteCtrlAsync(byte[] fragment, CancellationToken ct)
    {
        var r = await _rx.WriteValueWithResultAsync(fragment.AsBuffer(), GattWriteOption.WriteWithResponse).AsTask(ct);
        if (r.Status != GattCommunicationStatus.Success)
            throw new IOException(r.Status == GattCommunicationStatus.AccessDenied ? "El reloj rechazó la escritura (enlace sin cifrar)" : "Error de escritura Bluetooth: " + r.Status);
    }

    public void Dispose()
    {
        try { _session.MaintainConnection = false; } catch (ObjectDisposedException) { }
        _service.Dispose();
        _session.Dispose();
        _dev.Dispose();
    }
}

/// <summary>
/// Watch keys of this PC, encrypted with Windows DPAPI for the current user (%LOCALAPPDATA%\AVO Performance Horse\Windows\reloj).
/// Never stored in clear text nor in the repository.
/// </summary>
public sealed class DpapiCredentialStore(string dir) : IWatchCredentialStore
{
    private static readonly byte[] Entropy = "AVO-WATCH-KEY/1"u8.ToArray();
    private sealed record Dto(string DeviceId, string KeyId, string Key);

    private string? PathFor(string deviceId) => Regex.IsMatch(deviceId, "^[0-9A-Fa-f]{1,16}$") ? Path.Combine(dir, deviceId.ToLowerInvariant() + ".clave") : null;

    public WatchCredential? Get(string deviceId)
    {
        var p = PathFor(deviceId);
        if (p is null || !File.Exists(p)) return null;
        try
        {
            var json = ProtectedData.Unprotect(File.ReadAllBytes(p), Entropy, DataProtectionScope.CurrentUser);
            var d = JsonSerializer.Deserialize<Dto>(json);
            return d is null ? null : new WatchCredential(d.DeviceId, Convert.FromHexString(d.KeyId), Convert.FromHexString(d.Key));
        }
        catch (Exception ex) when (ex is CryptographicException or JsonException or FormatException or IOException) { return null; }
    }

    public void Save(WatchCredential c)
    {
        var p = PathFor(c.DeviceId) ?? throw new ArgumentException("Identificador de reloj no válido");
        Directory.CreateDirectory(dir);
        var json = JsonSerializer.SerializeToUtf8Bytes(new Dto(c.DeviceId, Convert.ToHexString(c.KeyId), Convert.ToHexString(c.Key)));
        File.WriteAllBytes(p, ProtectedData.Protect(json, Entropy, DataProtectionScope.CurrentUser));
    }
}
