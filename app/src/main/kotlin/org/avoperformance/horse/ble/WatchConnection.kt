package org.avoperformance.horse.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout
import org.avoperformance.horse.AppLog
import org.avoperformance.horse.core.ble.AuthOutcome
import org.avoperformance.horse.core.ble.AvoClient
import org.avoperformance.horse.core.ble.BleMessage
import org.avoperformance.horse.core.ble.BleStatus
import org.avoperformance.horse.core.ble.MsgType
import org.avoperformance.horse.core.ble.RtcmAck
import org.avoperformance.horse.core.ble.SessionCmd
import org.avoperformance.horse.core.ble.Telemetry
import org.avoperformance.horse.core.ble.TimeSource
import org.avoperformance.horse.core.ble.WatchInfo
import org.avoperformance.horse.core.ble.WatchStatus
import org.avoperformance.horse.core.bytes.ByteReader
import org.avoperformance.horse.core.telemetry.SessionCommandTracker
import org.avoperformance.horse.data.Settings
import org.avoperformance.horse.security.SecureStore

enum class LinkState(val texto: String) {
    SIN_RELOJ("Ningún reloj vinculado"),
    DESCONECTADO("Desconectado"),
    VINCULANDO_BLE("Emparejando por Bluetooth…"),
    CONECTANDO("Conectando…"),
    AUTENTICANDO("Comprobando autorización…"),
    NECESITA_AUTORIZACION("Este teléfono no está autorizado en el reloj"),
    ESPERANDO_BOOT("Pulsa BOOT en el reloj para autorizar este teléfono"),
    LISTO("Conectado y autorizado"),
    LISTO_SIN_AUTH("Conectado (firmware sin autorización de app)"),
    ERROR("Error"),
}

data class TelemetrySample(val t: Telemetry, val receivedMs: Long)
data class WatchEvent(val code: Int, val text: String, val atMs: Long)

/**
 * One connection to the single authorized watch. Handles bonding, GATT,
 * application authorization (V3.4.4), telemetry and auto-reconnection.
 */
@SuppressLint("MissingPermission")
class WatchConnection(
    private val ctx: Context,
    private val settings: Settings,
    private val secure: SecureStore,
    private val log: AppLog,
    private val scope: CoroutineScope,
) {
    private val adapter = ctx.getSystemService(BluetoothManager::class.java)?.adapter
    val scanner = BleScanner(ctx)

    private val _state = MutableStateFlow(if (settings.authorizedWatch == null) LinkState.SIN_RELOJ else LinkState.DESCONECTADO)
    val state: StateFlow<LinkState> = _state
    private val _detail = MutableStateFlow<String?>(null)
    val detail: StateFlow<String?> = _detail
    private val _info = MutableStateFlow<WatchInfo?>(null)
    val info: StateFlow<WatchInfo?> = _info
    private val _status = MutableStateFlow<WatchStatus?>(null)
    val status: StateFlow<WatchStatus?> = _status
    private val _telemetry = MutableStateFlow<TelemetrySample?>(null)
    val telemetry: StateFlow<TelemetrySample?> = _telemetry
    private val _events = MutableSharedFlow<WatchEvent>(extraBufferCapacity = 32)
    val events: SharedFlow<WatchEvent> = _events
    private val _rssiMtu = MutableStateFlow<Int?>(null)
    val mtu: StateFlow<Int?> = _rssiMtu
    val commandTracker = MutableStateFlow<SessionCommandTracker.State>(SessionCommandTracker.State.Idle)
    private val tracker = SessionCommandTracker()

    @Volatile var rtcmAckListener: ((RtcmAck) -> Unit)? = null
    @Volatile var client: AvoClient? = null; private set
    private var transport: GattTransport? = null
    private var loop: Job? = null
    private val connectLock = Mutex()
    @Volatile private var wanted = false
    @Volatile private var reconnects = 0

    val isReady get() = _state.value == LinkState.LISTO || _state.value == LinkState.LISTO_SIN_AUTH
    val authorizedAddress get() = settings.authorizedWatch

    /** Selects the watch (from the scan) as the only authorized device and connects. */
    fun selectWatch(address: String, name: String) {
        if (settings.authorizedWatch != null && settings.authorizedWatch != address) {
            secure.forgetWatch(settings.authorizedWatch!!)
        }
        settings.authorizedWatch = address
        settings.authorizedWatchName = name
        start()
    }

    fun forgetWatch() {
        stop()
        settings.authorizedWatch?.let { secure.forgetWatch(it) }
        settings.authorizedWatch = null
        settings.authorizedWatchName = null
        _state.value = LinkState.SIN_RELOJ
    }

    /** Keeps the link up (auto-reconnect with backoff) until [stop]. */
    fun start() {
        if (settings.authorizedWatch == null) { _state.value = LinkState.SIN_RELOJ; return }
        wanted = true
        if (loop?.isActive == true) return
        loop = scope.launch(Dispatchers.IO) {
            var backoff = 2000L
            while (isActive && wanted) {
                // Waiting for Bluetooth to return must not exponentially back off:
                // reconnect promptly after airplane mode / Bluetooth toggle.
                if (adapter?.isEnabled != true) {
                    _state.value = LinkState.DESCONECTADO
                    _detail.value = "Esperando a que se active Bluetooth"
                    backoff = 2000L
                    delay(1000L)
                    continue
                }
                val ok = runCatching { connectOnce() }.onFailure {
                    _detail.value = it.message
                    log.w("BLE", "conexión fallida: ${it.message}")
                }.getOrDefault(false)
                if (ok) {
                    backoff = 2000L
                    linkLost.await()            // until the link drops
                    reconnects++
                }
                cleanup()
                if (!wanted) break
                if (_state.value != LinkState.NECESITA_AUTORIZACION) _state.value = LinkState.DESCONECTADO
                delay(backoff)
                backoff = minOf(backoff * 2, 30_000L)
            }
        }
    }

    fun stop() {
        wanted = false
        loop?.cancel()
        loop = null
        cleanup()
        if (settings.authorizedWatch != null) _state.value = LinkState.DESCONECTADO
    }

    private var linkLost = CompletableDeferred<Unit>()

    private fun cleanup() {
        client?.onDisconnected()
        client = null
        transport?.close()
        transport = null
    }

    private suspend fun connectOnce(): Boolean = connectLock.withLock {
        val addr = settings.authorizedWatch ?: return false
        val bt = adapter ?: throw IllegalStateException("Este teléfono no tiene Bluetooth")
        if (!bt.isEnabled) throw IllegalStateException("Bluetooth desactivado")
        val dev = bt.getRemoteDevice(addr)
        // 1) Bonding (Just Works on V3.4.4: no PIN on the watch). The bond only encrypts the link;
        //    authorization is done afterwards with the per-phone key.
        if (dev.bondState != BluetoothDevice.BOND_BONDED) {
            _state.value = LinkState.VINCULANDO_BLE
            bond(dev)
        }
        // 2) GATT
        _state.value = LinkState.CONECTANDO
        linkLost = CompletableDeferred()
        val t = GattTransport(ctx, dev, ::onNotify) { st -> log.w("BLE", "enlace perdido (estado $st)"); linkLost.complete(Unit) }
        transport = t
        val c = AvoClient(t, ::onUnsolicited)
        client = c
        t.connect()
        _rssiMtu.value = t.negotiatedMtu
        // 3) Info and authorization
        val info = c.getInfo()
        _info.value = info
        log.i("BLE", "reloj ${info.deviceId} fw ${info.firmware} caps=0x${info.caps.toString(16)} auth=${info.authorized}")
        if (!info.supportsAuth || info.authRequired == false) {
            _state.value = LinkState.LISTO_SIN_AUTH
        } else {
            _state.value = LinkState.AUTENTICANDO
            val cred = secure.watch(addr)
            val outcome = if (cred == null || cred.deviceId != info.deviceId) AuthOutcome.UNKNOWN_KEY else c.authenticate(cred)
            when (outcome) {
                AuthOutcome.OK -> _state.value = LinkState.LISTO
                AuthOutcome.UNKNOWN_KEY, AuthOutcome.REJECTED -> {
                    _state.value = LinkState.NECESITA_AUTORIZACION
                    _detail.value = outcome.texto
                    return true      // stay connected so the user can start the BOOT claim
                }
                AuthOutcome.WATCH_NOT_AUTHENTIC -> { _detail.value = outcome.texto; log.e("AUTH", outcome.texto); throw IllegalStateException(outcome.texto) }
                else -> { _detail.value = outcome.texto; throw IllegalStateException(outcome.texto) }
            }
        }
        afterReady(c)
        true
    }

    private suspend fun afterReady(c: AvoClient) {
        _detail.value = null
        val st = runCatching { c.getStatus() }.getOrNull()
        _status.value = st
        // Give the watch the phone time only when it has no time source at all (GNSS always wins on the watch)
        if (st != null && st.timeSource == TimeSource.NONE) {
            val r = runCatching { c.timeSet(System.currentTimeMillis()) }.getOrNull()
            log.i("BLE", "hora del teléfono enviada: $r")
        }
    }

    private suspend fun bond(dev: BluetoothDevice) {
        val done = CompletableDeferred<Int>()
        val rx = object : BroadcastReceiver() {
            override fun onReceive(c: Context, i: Intent) {
                val d: BluetoothDevice? = deviceExtra(i)
                if (d?.address != dev.address) return
                val s = i.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.ERROR)
                if (s == BluetoothDevice.BOND_BONDED || s == BluetoothDevice.BOND_NONE) done.complete(s)
            }
        }
        ctx.registerReceiver(rx, IntentFilter(BluetoothDevice.ACTION_BOND_STATE_CHANGED))
        try {
            if (!dev.createBond()) throw IllegalStateException("No se pudo iniciar el emparejamiento")
            val s = withTimeout(60_000) { done.await() }
            if (s != BluetoothDevice.BOND_BONDED) throw IllegalStateException("Emparejamiento rechazado o cancelado")
            log.i("BLE", "emparejado con ${dev.address}")
        } finally { runCatching { ctx.unregisterReceiver(rx) } }
    }

    @Suppress("DEPRECATION")
    private fun deviceExtra(i: Intent): BluetoothDevice? =
        if (Build.VERSION.SDK_INT >= 33) i.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
        else i.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)

    /**
     * BOOT-button claim: asks the watch for a new key. The user must press BOOT
     * on the watch within 60 s. The key is stored encrypted in the Keystore.
     */
    suspend fun claim(phoneName: String): String {
        val c = client ?: return "Sin conexión con el reloj"
        val info = _info.value ?: return "Sin información del reloj"
        val addr = settings.authorizedWatch ?: return "Ningún reloj seleccionado"
        when (val st = c.claimBegin(phoneName.take(23))) {
            BleStatus.OK -> {}
            BleStatus.AUTH_REQUIRED -> return "El enlace no está cifrado: vuelve a emparejar el reloj"
            BleStatus.STATE_CONFLICT -> return "El reloj no admite la vinculación ahora mismo"
            else -> return "El reloj respondió: ${st.texto}"
        }
        _state.value = LinkState.ESPERANDO_BOOT
        val deadline = System.currentTimeMillis() + 62_000
        while (System.currentTimeMillis() < deadline) {
            delay(1000)
            val (st, cred) = c.claimResult(info.deviceId)
            when (st) {
                BleStatus.OK -> {
                    secure.saveWatch(addr, cred!!)
                    log.i("AUTH", "teléfono autorizado (clave ${cred.keyId.joinToString("") { "%02x".format(it) }})")
                    _state.value = LinkState.AUTENTICANDO
                    val o = c.authenticate(cred)
                    return if (o == AuthOutcome.OK) { _state.value = LinkState.LISTO; afterReady(c); "Teléfono autorizado" }
                    else { _state.value = LinkState.NECESITA_AUTORIZACION; o.texto }
                }
                BleStatus.BUSY -> continue
                BleStatus.TIMEOUT -> { _state.value = LinkState.NECESITA_AUTORIZACION; return "No se pulsó BOOT a tiempo" }
                BleStatus.IO_ERROR -> { _state.value = LinkState.NECESITA_AUTORIZACION; return "El reloj no pudo guardar la clave" }
                else -> { _state.value = LinkState.NECESITA_AUTORIZACION; return "Vinculación cancelada (${st.texto})" }
            }
        }
        _state.value = LinkState.NECESITA_AUTORIZACION
        return "Tiempo agotado"
    }

    private fun onNotify(ch: java.util.UUID, v: ByteArray) { client?.onNotification(ch, v) }

    private fun onUnsolicited(m: BleMessage) {
        when (m.msgType) {
            MsgType.TELEMETRY -> Telemetry.decode(m.payload)?.let {
                val now = System.currentTimeMillis()
                _telemetry.value = TelemetrySample(it, now)
                tracker.onTelemetry(it.session, now)
                commandTracker.value = tracker.state
            }
            MsgType.RTCM_ACK -> RtcmAck.decode(m.payload)?.let { rtcmAckListener?.invoke(it) }
            MsgType.EVENT -> {
                val r = ByteReader(m.payload)
                val e = WatchEvent(r.u16(), r.str(32), System.currentTimeMillis())
                _events.tryEmit(e)
                log.i("EVENTO", "${e.code}: ${e.text}")
            }
            else -> {}
        }
    }

    /**
     * Session command with real confirmation (BLE status + telemetry state).
     * Returns null when accepted for confirmation, or an error text.
     */
    suspend fun sessionCommand(cmd: SessionCmd, userConfirmedStop: Boolean = false): String? {
        val c = client ?: return "Sin conexión con el reloj"
        if (!isReady) return "El reloj no está listo (${_state.value.texto})"
        if (!tracker.begin(cmd, System.currentTimeMillis())) return "Ya hay una orden en curso"
        commandTracker.value = tracker.state
        try {
            val st = c.sessionCommand(cmd, cmd == SessionCmd.STOP && userConfirmedStop)
            tracker.onResponse(st, System.currentTimeMillis(), _telemetry.value?.t?.session)
        } catch (e: Exception) {
            tracker.onTransportError(e.message ?: "error")
        }
        commandTracker.value = tracker.state
        // Wait for the watch telemetry to show the new state (or time out)
        while (tracker.state is SessionCommandTracker.State.WaitingTelemetry) {
            delay(250)
            val now = System.currentTimeMillis()
            _telemetry.value?.let { if (it.receivedMs > now - 2000) tracker.onTelemetry(it.t.session, now) }
            tracker.onTick(now)
            commandTracker.value = tracker.state
        }
        return (tracker.state as? SessionCommandTracker.State.Failed)?.reason
    }

    fun resetCommand() { tracker.reset(); commandTracker.value = tracker.state }

    suspend fun refreshStatus(): WatchStatus? = client?.let { c -> runCatching { c.getStatus() }.getOrNull()?.also { _status.value = it } }
}
