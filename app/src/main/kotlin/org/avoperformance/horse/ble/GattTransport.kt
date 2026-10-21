package org.avoperformance.horse.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.content.Context
import android.os.Build
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout
import org.avoperformance.horse.core.ble.AvoGatt
import org.avoperformance.horse.core.ble.AvoTransport
import java.io.IOException
import java.util.UUID

/**
 * BluetoothGatt wrapper: every GATT operation goes through one mutex and waits
 * for its callback (Android only allows one outstanding operation).
 * Permissions (BLUETOOTH_CONNECT) are checked by the caller before connecting.
 */
@SuppressLint("MissingPermission")
class GattTransport(
    private val ctx: Context,
    private val device: BluetoothDevice,
    private val onNotify: (UUID, ByteArray) -> Unit,
    private val onLinkLost: (Int) -> Unit,
) : AvoTransport {
    private var gatt: BluetoothGatt? = null
    private val op = Mutex()
    @Volatile private var pending: CompletableDeferred<Int>? = null
    private var connected = CompletableDeferred<Int>()
    private var servicesDone = CompletableDeferred<Int>()
    @Volatile private var mtu = 23
    @Volatile var closed = false; private set

    override val attPayload: Int get() = mtu - 3
    val negotiatedMtu get() = mtu

    private val cb = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED && status == BluetoothGatt.GATT_SUCCESS) connected.complete(status)
            else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                connected.complete(-1)
                pending?.complete(-1)
                if (!closed) onLinkLost(status)
            }
        }
        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) { servicesDone.complete(status) }
        override fun onMtuChanged(g: BluetoothGatt, m: Int, status: Int) { if (status == BluetoothGatt.GATT_SUCCESS) mtu = m; pending?.complete(status) }
        override fun onCharacteristicWrite(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) { pending?.complete(status) }
        override fun onDescriptorWrite(g: BluetoothGatt, d: BluetoothGattDescriptor, status: Int) { pending?.complete(status) }
        @Deprecated("API < 33")
        @Suppress("DEPRECATION")
        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic) {
            if (Build.VERSION.SDK_INT < 33) onNotify(c.uuid, c.value ?: ByteArray(0))
        }
        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic, value: ByteArray) { onNotify(c.uuid, value) }
    }

    suspend fun connect(timeoutMs: Long = 15_000) {
        connected = CompletableDeferred(); servicesDone = CompletableDeferred()
        gatt = device.connectGatt(ctx, false, cb, BluetoothDevice.TRANSPORT_LE)
        val st = withTimeout(timeoutMs) { connected.await() }
        if (st != BluetoothGatt.GATT_SUCCESS) throw IOException("No se pudo conectar (estado $st)")
        val g = gatt!!
        g.requestConnectionPriority(BluetoothGatt.CONNECTION_PRIORITY_HIGH)
        // MTU first (the watch prefers 247); a failure keeps 23 and the protocol still works (more fragments)
        runCatching { gattOp { g.requestMtu(AvoGatt.PREFERRED_MTU) } }
        if (!g.discoverServices()) throw IOException("discoverServices falló")
        if (withTimeout(10_000) { servicesDone.await() } != BluetoothGatt.GATT_SUCCESS) throw IOException("Descubrimiento de servicios fallido")
        val svc = g.getService(AvoGatt.SERVICE) ?: throw IOException("El dispositivo no tiene el servicio AVO")
        for (u in listOf(AvoGatt.CTRL_TX, AvoGatt.TELEM, AvoGatt.FILE_TX)) enableNotify(svc.getCharacteristic(u) ?: throw IOException("Falta la característica $u"))
    }

    private suspend fun enableNotify(c: BluetoothGattCharacteristic) {
        val g = gatt ?: throw IOException("sin conexión")
        g.setCharacteristicNotification(c, true)
        val d = c.getDescriptor(AvoGatt.CCCD) ?: throw IOException("Falta CCCD")
        val st = gattOp {
            if (Build.VERSION.SDK_INT >= 33) g.writeDescriptor(d, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE) == BluetoothStatusCodes.SUCCESS
            else legacyWriteDescriptor(g, d, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
        }
        // Insufficient encryption here means the bond is missing: the caller re-bonds
        if (st != BluetoothGatt.GATT_SUCCESS) throw IOException("No se pudieron activar las notificaciones (estado $st)")
    }

    /** Runs one GATT operation and waits for its callback status. */
    private suspend fun gattOp(timeoutMs: Long = 5000, start: () -> Boolean): Int = op.withLock {
        val d = CompletableDeferred<Int>()
        pending = d
        try {
            if (!start()) return@withLock -2
            withTimeout(timeoutMs) { d.await() }
        } finally { pending = null }
    }

    private fun ch(u: UUID): BluetoothGattCharacteristic =
        gatt?.getService(AvoGatt.SERVICE)?.getCharacteristic(u) ?: throw IOException("Sin conexión con el reloj")

    private fun write(c: BluetoothGattCharacteristic, v: ByteArray, type: Int): Boolean {
        val g = gatt ?: return false
        return if (Build.VERSION.SDK_INT >= 33) g.writeCharacteristic(c, v, type) == BluetoothStatusCodes.SUCCESS
        else legacyWrite(g, c, v, type)
    }

    @Suppress("DEPRECATION")
    private fun legacyWrite(g: BluetoothGatt, c: BluetoothGattCharacteristic, v: ByteArray, type: Int): Boolean {
        c.writeType = type; c.value = v; return g.writeCharacteristic(c)
    }

    @Suppress("DEPRECATION")
    private fun legacyWriteDescriptor(g: BluetoothGatt, d: BluetoothGattDescriptor, v: ByteArray): Boolean {
        d.value = v; return g.writeDescriptor(d)
    }

    override suspend fun writeCtrl(frag: ByteArray) {
        val c = ch(AvoGatt.CTRL_RX)
        var st = -2
        for (i in 0 until 3) {   // the stack may be momentarily busy
            st = gattOp { write(c, frag, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT) }
            if (st == BluetoothGatt.GATT_SUCCESS) return
            if (st != -2) break
            kotlinx.coroutines.delay(20)
        }
        throw IOException("Escritura BLE fallida (estado $st)")
    }

    override suspend fun writeRtcm(frag: ByteArray): Boolean {
        val c = ch(AvoGatt.RTCM)
        return gattOp(2000) { write(c, frag, BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE) } == BluetoothGatt.GATT_SUCCESS
    }

    fun close() {
        closed = true
        try { gatt?.disconnect() } catch (_: Exception) {}
        try { gatt?.close() } catch (_: Exception) {}
        gatt = null
        pending?.complete(-1)
    }
}
