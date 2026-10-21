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
import org.osmdroid.config.Configuration

/** Manual dependency container (no DI framework needed for this size). */
class AppContainer(val app: Application) {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    val db = AvoDatabase.create(app)
    val secure = SecureStore(app)
    val settings = Settings(app, secure)
    /** Server layer on hold: no endpoint is invented. */
    val server: ServerApi = NotConfiguredServer
    val log = AppLog(this)
    val watch = WatchConnection(app, settings, secure, log, scope)
    val config = WatchConfigOps(watch)
    val ntrip = NtripManager(settings, watch, log, scope)
    val sync = WatchSyncManager(app, db, settings, watch, server, log, scope)
    val chestOta = org.avoperformance.horse.ota.ChestOtaManager(this)
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
        Configuration.getInstance().userAgentValue = packageName
        Configuration.getInstance().osmdroidBasePath = filesDir.resolve("osmdroid")
        Configuration.getInstance().osmdroidTileCache = cacheDir.resolve("osmdroid_tiles")
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL_LINK, getString(R.string.notif_channel), NotificationManager.IMPORTANCE_LOW))
    }

    companion object { const val CHANNEL_LINK = "avo_link" }
}
