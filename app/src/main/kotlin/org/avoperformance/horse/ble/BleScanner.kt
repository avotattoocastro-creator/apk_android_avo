package org.avoperformance.horse.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.ParcelUuid
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.avoperformance.horse.core.ble.AvoGatt

data class FoundWatch(val address: String, val name: String, val rssi: Int, val bonded: Boolean, val lastSeenMs: Long)

/** Scans only for devices advertising the AVO service UUID (or an AVO_XXXX / AVO-XXXX name). */
@SuppressLint("MissingPermission")
class BleScanner(ctx: Context) {
    private val adapter = ctx.getSystemService(BluetoothManager::class.java)?.adapter
    private val _found = MutableStateFlow<List<FoundWatch>>(emptyList())
    val found: StateFlow<List<FoundWatch>> = _found
    private val _scanning = MutableStateFlow(false)
    val scanning: StateFlow<Boolean> = _scanning
    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error

    private val cb = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, r: ScanResult) = add(r)
        override fun onBatchScanResults(results: MutableList<ScanResult>) = results.forEach { add(it) }
        override fun onScanFailed(errorCode: Int) { _error.value = "Error de escaneo BLE ($errorCode)"; _scanning.value = false }
    }

    private fun add(r: ScanResult) {
        val name = r.scanRecord?.deviceName ?: r.device.name ?: ""
        val hasSvc = r.scanRecord?.serviceUuids?.any { it.uuid == AvoGatt.SERVICE } == true
        if (!hasSvc && !AvoGatt.NAME_REGEX.matches(name)) return
        val w = FoundWatch(r.device.address, name.ifEmpty { "(sin nombre)" }, r.rssi, r.device.bondState == android.bluetooth.BluetoothDevice.BOND_BONDED, System.currentTimeMillis())
        _found.value = (_found.value.filter { it.address != w.address } + w).sortedByDescending { it.rssi }
    }

    fun start() {
        val s = adapter?.bluetoothLeScanner ?: run { _error.value = "Bluetooth desactivado"; return }
        _error.value = null
        _found.value = emptyList()
        // Two filters (OR): by service UUID, and an empty filter is NOT used so we never list unrelated devices.
        val filters = listOf(ScanFilter.Builder().setServiceUuid(ParcelUuid(AvoGatt.SERVICE)).build())
        s.startScan(filters, ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(), cb)
        _scanning.value = true
    }

    fun stop() {
        if (!_scanning.value) return
        runCatching { adapter?.bluetoothLeScanner?.stopScan(cb) }
        _scanning.value = false
    }
}
