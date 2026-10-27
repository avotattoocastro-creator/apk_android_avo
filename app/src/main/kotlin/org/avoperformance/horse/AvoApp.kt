package org.avoperformance.horse

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.avoperformance.horse.ble.WatchConfigOps
import org.avoperformance.horse.ble.WatchConnection
import org.avoperformance.horse.core.server.NotConfiguredServer
import org.avoperformance.horse.core.server.ServerApi
import org.avoperformance.horse.data.AvoDatabase
import org.avoperformance.horse.data.LogEntity
import org.avoperformance.horse.data.Settings
import org.avoperformance.horse.ntrip.NtripManager
import org.avoperformance.horse.security.SecureStore
import org.avoperformance.horse.sync.WatchSyncManager
import org.avoperformance.horse.dnd.GeofenceDndController
import org.osmdroid.config.Configuration

/** Manual dependency container (no DI framework needed for this size). */
class AppContainer(val app: Application) {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    val db = AvoDatabase.create(app)
    val secure = SecureStore(app)
    val settings = Settings(app, secure)
    /** AVO user identity (NFC card) for app-to-app sending. */
    val identity = org.avoperformance.horse.identity.UserIdentity(secure)
    /** Server layer on hold: no endpoint is invented. */
    val server: ServerApi = NotConfiguredServer
    val log = AppLog(this)
    /** App licence (NFC card or file). Created before every hardware/network object: it sets LicenseGate. */
    val license = org.avoperformance.horse.license.LicenseManager(app, secure, log, scope)
    val dnd = GeofenceDndController(app, settings, log)
    val watch = WatchConnection(app, settings, secure, log, scope)
    val config = WatchConfigOps(watch)
    val ntrip = NtripManager(settings, watch, log, scope)
    val tides = org.avoperformance.horse.tide.TideRepository(app)
    val sync = WatchSyncManager(app, db, settings, watch, server, log, scope)
    /** Training download over Wi-Fi (CHEST V3.7.4+), BLE as fallback. */
    val wifiSync = org.avoperformance.horse.wifi.AvoWifiSyncManager(app, watch, log, { sync.trainingsDir },
        org.avoperformance.horse.core.wifi.VerifiedSink { id, dir, sha, bytes -> sync.completeFromWifi(id, dir, sha, bytes) }).also { sync.wifi = it }
    /** AVO Equine Intelligence Engine (C++ via JNI): advanced analysis of downloaded trainings. */
    val equine = org.avoperformance.horse.engine.EquineEngine(app, log, scope)
    /** Sharing between AVO users over Firebase (global, per horse and manual). */
    val share = org.avoperformance.horse.cloud.ShareManager(this).also { s -> sync.onVerified = { id -> s.onTrainingVerified(id) } }
    /** V3.9 GNSS: records RTK FIX losses and an L1-only antenna in the app log (Ajustes → Diagnóstico). */
    init {
        // Licence expired or missing: consultation mode. Stop the watch link, NTRIP, Wi-Fi download and the
        // background tasks; the link service stops itself. On (re)activation everything starts again.
        scope.launch {
            var wasFull: Boolean? = null
            license.status.collect { st ->
                val full = st.fullAccess
                if (full == wasFull) return@collect
                if (!full) {
                    runCatching { ntrip.stop() }; runCatching { watch.stop() }; runCatching { wifiSync.cancel() }
                    val wm = androidx.work.WorkManager.getInstance(app)
                    listOf("avo_sync", "avo_share_periodic", "avo_share_now", "avo_share_followup").forEach { wm.cancelUniqueWork(it) }
                } else if (wasFull == false) {
                    org.avoperformance.horse.service.AvoLinkService.startIfAutomatic(app, "licencia activada")
                    if (identity.card.value != null) { share.schedule(); share.runNow() }
                }
                wasFull = full
            }
        }
        scope.launch {
            var lastLost = -1; var l1Warned = false
            watch.telemetry.collect { s ->
                val q = s?.t?.v3 ?: return@collect
                if (lastLost >= 0 && q.fixLost > lastLost) log.w("RTK", "FIX perdido (${q.fixLost} desde el arranque de la espalda)")
                lastLost = q.fixLost
                if (q.l1Only && !l1Warned) { l1Warned = true; log.w("RTK", "antena sin segunda frecuencia (L2/E5b/B2): no habrá RTK FIX") }
                if (!q.l1Only && q.signalsFresh) l1Warned = false
            }
        }
    }
}

class AppLog(private val c: AppContainer) {
    fun i(tag: String, msg: String) = write("I", tag, msg)
    fun w(tag: String, msg: String) = write("W", tag, msg)
    fun e(tag: String, msg: String) = write("E", tag, msg)
    private fun write(level: String, tag: String, msg: String) {
        android.util.Log.println(if (level == "E") android.util.Log.ERROR else if (level == "W") android.util.Log.WARN else android.util.Log.INFO, "AVO/$tag", msg)
        c.scope.launch(Dispatchers.IO) { runCatching { c.db.log().insert(LogEntity(level = level, tag = tag, message = msg.take(500))); c.db.log().trim() } }
    }
}

class AvoApp : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
        MainThreadWatchdog(container.log).start()   // diagnostic: records where the UI freezes
        Configuration.getInstance().userAgentValue = packageName
        Configuration.getInstance().osmdroidBasePath = filesDir.resolve("osmdroid")
        Configuration.getInstance().osmdroidTileCache = cacheDir.resolve("osmdroid_tiles")
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL_LINK, getString(R.string.notif_channel), NotificationManager.IMPORTANCE_LOW))
    }

    companion object { const val CHANNEL_LINK = "avo_link" }
}
