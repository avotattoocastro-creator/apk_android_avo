package org.avoperformance.horse

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
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
    val share = org.avoperformance.horse.cloud.ShareManager(this).also { s ->
        sync.onVerified = { id -> s.onTrainingVerified(id) }
        // roles of the licence in the sharing profile: mine published, the others' verified with the app keys
        s.firebase.licenseToken = { license.publicTokenB64 }
        s.firebase.verifyRoles = { code, token -> license.verifiedRoles(code, token) }
    }
    // declared before init: the coroutines launched in init use them
    private val riderLock = kotlinx.coroutines.sync.Mutex()
    private val licPrefs = app.getSharedPreferences("license_rider", android.content.Context.MODE_PRIVATE)
    /** V3.9 GNSS: records RTK FIX losses and an L1-only antenna in the app log (Ajustes → Diagnóstico). */
    init {
        // Licence: functions by role. Without GRABAR the watch link, NTRIP, Wi-Fi download and the download task
        // stop; without COMPARTIR the sharing tasks stop. When a function comes back, everything starts again.
        scope.launch {
            var prev: Set<org.avoperformance.horse.core.license.LicenseFeature>? = null
            license.features.collect { f ->
                val p = prev; prev = f
                if (p == f) return@collect
                val rec = org.avoperformance.horse.core.license.LicenseFeature.GRABAR in f
                val shr = org.avoperformance.horse.core.license.LicenseFeature.COMPARTIR in f
                val wm = androidx.work.WorkManager.getInstance(app)
                if (!rec) { runCatching { ntrip.stop() }; runCatching { watch.stop() }; runCatching { wifiSync.cancel() }; wm.cancelUniqueWork("avo_sync") }
                if (!shr) listOf("avo_share_periodic", "avo_share_now", "avo_share_followup").forEach { wm.cancelUniqueWork(it) }
                val gained = p != null && ((rec && org.avoperformance.horse.core.license.LicenseFeature.GRABAR !in p) ||
                    (shr && org.avoperformance.horse.core.license.LicenseFeature.COMPARTIR !in p))
                if (gained) {
                    org.avoperformance.horse.service.AvoLinkService.startIfAutomatic(app, "licencia activada")
                    if (shr && identity.card.value != null) { share.schedule(); share.runNow() }
                }
            }
        }
        // Licence with the Jinete role: the holder is the rider of the trainings recorded with this app
        scope.launch {
            kotlinx.coroutines.flow.combine(license.status, watch.state) { _, _ -> Unit }.collect { applyLicenseRider() }
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

    /**
     * Jinete licence: makes sure the holder exists as a rider, selects them (once per licence; always when the
     * licence fixes the rider) and writes them in the watch configuration when it is connected and not recording,
     * so every training recorded with this app carries this rider.
     */
    suspend fun applyLicenseRider(): Unit = riderLock.withLock {
        val (code, name) = license.licenseRider ?: return@withLock
        val serial = (license.status.value as? org.avoperformance.horse.core.license.LicenseStatus.Active)?.token?.serial
            ?.joinToString("") { "%02X".format(it) } ?: return@withLock
        val rider = withContext(Dispatchers.IO) {
            db.riders().all().first().firstOrNull { it.code == code }
                ?: org.avoperformance.horse.data.RiderEntity(code = code, name = name).let { r -> r.copy(id = db.riders().insert(r)) }
        }
        val locked = license.riderLocked
        val firstTime = licPrefs.getString("applied", null) != serial
        if (settings.selectedRiderId != rider.id && (locked || firstTime)) {
            settings.selectedRiderId = rider.id
            log.i("LICENCIA", "jinete de la licencia seleccionado: ${rider.name} ($code)")
        }
        licPrefs.edit().putString("applied", serial).apply()
        val sess = watch.telemetry.value?.t?.session
        val recording = sess == org.avoperformance.horse.core.ble.WatchSessionState.RECORDING || sess == org.avoperformance.horse.core.ble.WatchSessionState.PAUSED
        if (watch.isReady && !recording && (locked || firstTime || settings.selectedRiderId == rider.id)) {
            val cfg = config.read().getOrNull() ?: return@withLock
            if (cfg.riderName != code && (locked || settings.selectedRiderId == rider.id)) {
                val err = config.setRider(rider.id, code)
                log.i("LICENCIA", if (err == null) "jinete $code enviado al chaleco" else "jinete no enviado al chaleco: $err")
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
