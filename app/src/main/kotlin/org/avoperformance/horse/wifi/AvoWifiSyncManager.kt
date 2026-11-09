package org.avoperformance.horse.wifi

import android.content.Context
import android.net.ConnectivityManager
import android.net.MacAddress
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiNetworkSpecifier
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import org.avoperformance.horse.AppLog
import org.avoperformance.horse.ble.WatchConnection
import org.avoperformance.horse.core.ble.BleStatus
import org.avoperformance.horse.core.ble.Idempotency
import org.avoperformance.horse.core.ble.MsgType
import org.avoperformance.horse.core.ble.WatchSessionState
import org.avoperformance.horse.core.wifi.*
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import kotlin.coroutines.resume

/**
 * Automatic training download over Wi-Fi (watch CHEST V3.7.4+ with capability b11).
 *
 *  1. Over authenticated BLE asks the watch for WIFI_SYNC(start) → network, password, token and BSSID (memory only).
 *  2. Asks Android for that network with WifiNetworkSpecifier (with BSSID): the first time Android shows its
 *     mandatory dialog; after approving it, the system remembers the approval and the next connections are
 *     automatic. The network has no Internet: it is only used through Network.openConnection (the default
 *     network of the phone does not change, mobile data/Wi-Fi keep working for the other apps).
 *  3. Downloads with Range, verifies SHA-256 and records the training as with BLE.
 *  4. Turns off the watch Wi-Fi and releases the network. NTRIP to the watch paused during the download.
 * If the firmware has no Wi-Fi or Android does not connect, the existing BLE download is used.
 */
class AvoWifiSyncManager(
    private val ctx: Context,
    private val watch: WatchConnection,
    private val log: AppLog,
    trainingsDir: () -> File,
    sink: VerifiedSink,
) {
    private val cm = ctx.getSystemService(ConnectivityManager::class.java)

    private fun recording() = watch.telemetry.value?.t?.session.let { it == WatchSessionState.RECORDING || it == WatchSessionState.PAUSED }

    /**
     * Protection against reboot loops: before each WIFI_SYNC(start) the watch boot counter is saved. If on
     * reconnecting the counter went up (the watch rebooted while turning Wi-Fi on), Wi-Fi is disabled for that
     * firmware and the download goes over BLE. It is re-enabled on its own when the firmware version changes.
     * Field case 3.7.4-wifi-rc1: reboot every ~5 s when starting the AP.
     */
    private val guard = ctx.getSharedPreferences("avo_wifi_guard", Context.MODE_PRIVATE)

    private fun checkGuard(): Boolean {
        val info = watch.info.value ?: return false
        val fwBlocked = guard.getString("blocked_fw", null)
        if (fwBlocked != null && fwBlocked == info.firmware) return false
        if (fwBlocked != null && fwBlocked != info.firmware) guard.edit().remove("blocked_fw").apply()   // new firmware: try again
        val attFw = guard.getString("attempt_fw", null)
        val attBoot = guard.getLong("attempt_boot", -1)
        val attAt = guard.getLong("attempt_at", 0L)
        // 2.8: only a reboot shortly after the attempt counts. Before, a WIFI_SYNC(start) left without an answer stayed
        // marked and the next NORMAL power-off/on of the watch (boot counter up) blocked Wi-Fi for that firmware forever.
        if (attFw != null && attAt > 0 && System.currentTimeMillis() - attAt > REBOOT_WINDOW_MS) { clearAttempt(); return true }
        if (attFw != null && attFw == info.firmware && attBoot >= 0 && info.bootCount > attBoot) {
            guard.edit().putString("blocked_fw", info.firmware).remove("attempt_fw").remove("attempt_boot").apply()
            log.w("WIFI", "el reloj se reinició al activar el Wi-Fi (arranque $attBoot → ${info.bootCount}): Wi-Fi desactivado para ${info.firmware}, se usa Bluetooth")
            return false
        }
        return true
    }
    private fun markAttempt() { watch.info.value?.let { guard.edit().putString("attempt_fw", it.firmware).putLong("attempt_boot", it.bootCount).putLong("attempt_at", System.currentTimeMillis()).commit() } }
    private fun clearAttempt() { guard.edit().remove("attempt_fw").remove("attempt_boot").remove("attempt_at").apply() }

    /** 2.8: lets the user try Wi-Fi again after a block (Dispositivos). */
    fun unblock() { guard.edit().remove("blocked_fw").remove("attempt_fw").remove("attempt_boot").remove("attempt_at").apply() }

    private companion object { const val REBOOT_WINDOW_MS = 5 * 60_000L }

    /** The watch firmware rebooted when turning on Wi-Fi: blocked until another firmware. */
    val blockedFirmware: String? get() = guard.getString("blocked_fw", null)

    /** Firmware with Wi-Fi download (by capability, never by version number) and without a reboot history. */
    val supported: Boolean get() = watch.info.value?.supportsWifiSync == true && checkGuard()

    private val control = object : WatchWifiControl {
        override suspend fun start(): WatchWifiControl.Start {
            if (!supported) return WatchWifiControl.Start.Unsupported
            val c = watch.client ?: throw IOException("Sin conexión con el reloj")
            markAttempt()
            val m = c.request(MsgType.WIFI_SYNC, byteArrayOf(1), Idempotency.STATE_CHANGING, timeoutMs = 12_000)
            // 2.8: any answer means the watch did NOT reboot while turning the AP on (it answers after the AP is up)
            clearAttempt()
            return when (m.statusEnum) {
                BleStatus.OK -> WifiCredentials.decode(m.payload)?.let { WatchWifiControl.Start.Ok(it) }
                    ?: WatchWifiControl.Start.Refused("credenciales ilegibles", false)
                BleStatus.STATE_CONFLICT -> WatchWifiControl.Start.Refused("grabando", true)
                BleStatus.NOT_ALLOWED -> WatchWifiControl.Start.Refused("batería baja", true)
                BleStatus.BUSY -> WatchWifiControl.Start.Refused("ocupado", true)
                BleStatus.UNKNOWN_TYPE -> WatchWifiControl.Start.Unsupported
                else -> when (m.payload.firstOrNull()?.toInt()) {
                    3 -> WatchWifiControl.Start.Refused("sin microSD", true)
                    6 -> WatchWifiControl.Start.Refused("Wi-Fi del reloj bloqueado tras un reinicio (se desbloquea al actualizar el reloj)", false)
                    7 -> WatchWifiControl.Start.Refused("poca memoria libre en el reloj", false)
                    else -> WatchWifiControl.Start.Refused("radio del reloj", false)
                }.also { log.w("WIFI", "el reloj rechazó el Wi-Fi: ${it.reason} (estado ${m.statusEnum}, motivo ${m.payload.firstOrNull()})") }
            }
        }
        override suspend fun stop() { runCatching { watch.client?.request(MsgType.WIFI_SYNC, byteArrayOf(2), Idempotency.STATE_CHANGING, timeoutMs = 4000) } }
        override fun recording() = this@AvoWifiSyncManager.recording()
    }

    private val connector = object : WifiConnector {
        /**
         * 2.8: after Android joins the watch network the first requests can be lost (address/route still being set up:
         * same case seen on the iPad on 07/11). Before, the first metadata request failing ended the pass and the app
         * went to Bluetooth. Now /api/v1/status is polled (4 s per try, every second, up to 30 s) before downloading.
         */
        override suspend fun connect(creds: WifiCredentials): WifiConnector.Link? {
            val link = join(creds) ?: return null
            val http = link.http as NetworkWatchHttp
            val t0 = System.currentTimeMillis()
            var tries = 0
            var last: String? = null
            while (System.currentTimeMillis() - t0 < 30_000) {
                tries++
                val r = runCatching { http.probe() }
                if (r.isSuccess) { log.i("WIFI", "el reloj responde por Wi-Fi (intento $tries, ${System.currentTimeMillis() - t0} ms)"); return link }
                last = r.exceptionOrNull()?.let { "${it.javaClass.simpleName}: ${it.message}" }
                if (r.exceptionOrNull() is AuthException) break
                kotlinx.coroutines.delay(1000)
            }
            log.w("WIFI", "conectado a ${creds.ssid} pero el reloj no responde por HTTP tras $tries intentos ($last) → Bluetooth")
            link.close()
            return null
        }

        private suspend fun join(creds: WifiCredentials): WifiConnector.Link? = suspendCancellableCoroutine { cont ->
            val spec = WifiNetworkSpecifier.Builder().setSsid(creds.ssid).setWpa2Passphrase(creds.password)
                .apply { runCatching { setBssid(MacAddress.fromBytes(creds.bssid)) } }.build()
            val req = NetworkRequest.Builder().addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).setNetworkSpecifier(spec).build()
            var done = false
            val cb = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    if (done) return; done = true
                    val self = this
                    log.i("WIFI", "conectado a ${creds.ssid}")
                    cont.resume(object : WifiConnector.Link {
                        override val http: WatchHttp = NetworkWatchHttp(network, creds)
                        override fun close() { runCatching { cm.unregisterNetworkCallback(self) } }
                    })
                }
                override fun onUnavailable() {
                    if (done) return; done = true
                    log.w("WIFI", "Android no conectó con ${creds.ssid} (rechazado o sin respuesta)")
                    runCatching { cm.unregisterNetworkCallback(this) }
                    cont.resume(null)
                }
            }
            // 60 s: includes the time of the mandatory system dialog the first time
            runCatching { cm.requestNetwork(req, cb, 60_000) }.onFailure { e ->
                log.w("WIFI", "requestNetwork: ${e.message}"); if (!done) { done = true; cont.resume(null) }
            }
            cont.invokeOnCancellation { runCatching { cm.unregisterNetworkCallback(cb) } }
        }
    }

    val coordinator = WifiSyncCoordinator(control, connector, { id -> File(trainingsDir(), id) }, sink) { log.i("WIFI", it) }
    val progress get() = coordinator.progress

    /** One pass (only one at a time). NTRIP to the watch in pause while it lasts. */
    suspend fun sync(pending: List<Pair<String, String?>>): WifiSyncReport = withContext(Dispatchers.IO) {
        if (pending.isEmpty()) return@withContext WifiSyncReport(emptyList(), emptyMap(), emptyList())
        if (!supported) {
            val info = watch.info.value
            log.i("WIFI", when {
                info == null -> "sin datos del reloj todavía → Bluetooth"
                !info.supportsWifiSync -> "firmware ${info.firmware} sin Wi-Fi (caps=0x${java.lang.Long.toHexString(info.caps)}) → Bluetooth"
                blockedFirmware == info.firmware -> "Wi-Fi bloqueado para ${info.firmware} (reinicio al activarlo) → Bluetooth"
                else -> "Wi-Fi no disponible → Bluetooth"
            })
            return@withContext WifiSyncReport(emptyList(), emptyMap(), pending.map { it.first })
        }
        log.i("WIFI", "pidiendo Wi-Fi al reloj ${watch.info.value?.firmware} para ${pending.size} entrenamiento(s)")
        watch.downloadMode.value = true
        try {
            val r = coordinator.sync(pending)
            // still connected over BLE after the pass → the watch did not reboot because of Wi-Fi
            if (watch.isReady) clearAttempt()
            r
        } finally { watch.downloadMode.value = false }
    }

    fun cancel() = coordinator.cancel()
    /** Pause persists across app restarts. */
    var paused: Boolean
        get() = coordinator.paused
        set(v) { coordinator.paused = v; guard.edit().putBoolean("paused", v).apply(); if (v) coordinator.cancel() }

    init { coordinator.paused = guard.getBoolean("paused", false) }
}

/** HTTP over the watch network (does not change the default network of the phone). */
private class NetworkWatchHttp(private val network: Network, private val c: WifiCredentials) : WatchHttp {
    private fun open(path: String, method: String = "GET"): HttpURLConnection {
        val u = URL("http", c.ip, c.port, path)
        val conn = network.openConnection(u) as HttpURLConnection
        conn.requestMethod = method
        conn.connectTimeout = 5_000
        conn.readTimeout = 20_000
        conn.useCaches = false
        conn.setRequestProperty("Authorization", "Bearer ${c.token}")
        conn.setRequestProperty("Accept-Encoding", "identity")
        return conn
    }

    private fun check(conn: HttpURLConnection, vararg ok: Int): HttpURLConnection {
        val code = try { conn.responseCode } catch (e: IOException) { conn.disconnect(); throw e }
        if (code in ok) return conn
        conn.disconnect()
        throw when (code) {
            401 -> AuthException()
            409 -> RecordingException()
            412 -> ChangedException()
            else -> WatchHttpException(code, "HTTP $code del reloj")
        }
    }

    private fun text(path: String): String {
        val conn = check(open(path), 200)
        return try { conn.inputStream.use { it.readBytes().toString(Charsets.UTF_8) } } finally { conn.disconnect() }
    }

    /** 2.8: short status request used to check that the watch answers over Wi-Fi. */
    fun probe() {
        val conn = open("/api/v1/status")
        conn.connectTimeout = 3_000
        conn.readTimeout = 4_000
        check(conn, 200)
        try { conn.inputStream.use { it.readBytes() } } finally { conn.disconnect() }
    }

    override fun list() = WatchHttp.parseList(text("/api/v1/trainings"))
    override fun metadata(id: String) = WatchHttp.parseMeta(text("/api/v1/trainings/$id/metadata"))
    override fun sha256(id: String) = WatchHttp.parseSha(text("/api/v1/trainings/$id/sha256"))

    override fun openSegment(id: String, seg: Int, from: Long, etag: String): InputStream {
        val conn = open("/api/v1/trainings/$id/segments/$seg")
        conn.setRequestProperty("Range", "bytes=$from-")
        conn.setRequestProperty("If-Match", "\"$etag\"")
        conn.readTimeout = 15_000
        check(conn, if (from > 0) 206 else 200, 206, 200)
        val ins = conn.inputStream
        return object : InputStream() {
            override fun read() = ins.read()
            override fun read(b: ByteArray, off: Int, len: Int) = ins.read(b, off, len)
            override fun close() { runCatching { ins.close() }; conn.disconnect() }
        }
    }

    override fun complete(id: String, sha256: String, done: Boolean) {
        val conn = open("/api/v1/sync/complete", "POST")
        conn.doOutput = true
        conn.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
        conn.outputStream.use { it.write("id=$id&sha256=$sha256&done=${if (done) 1 else 0}".toByteArray()) }
        check(conn, 200).disconnect()
    }
}
