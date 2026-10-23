package org.avoperformance.horse.data

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.avoperformance.horse.core.ntrip.NtripConfig
import org.avoperformance.horse.core.ntrip.NtripVersion
import org.avoperformance.horse.security.SecureStore

/** Non-secret preferences. Secrets go to [SecureStore]. */
class Settings(ctx: Context, private val secure: SecureStore) {
    private val p = ctx.getSharedPreferences("avo_settings", Context.MODE_PRIVATE)

    data class Ntrip(
        val enabled: Boolean = false, val host: String = "", val port: Int = 2101, val mountpoint: String = "",
        val user: String = "", val tls: Boolean = false, val v2: Boolean = true, val sendGga: Boolean = true,
        val ggaIntervalS: Int = 10, val timeoutS: Int = 15, val reconnect: Boolean = true,
    )

    private val _ntrip = MutableStateFlow(loadNtrip())
    val ntrip: StateFlow<Ntrip> = _ntrip

    private fun loadNtrip() = Ntrip(
        p.getBoolean("ntrip.enabled", false), p.getString("ntrip.host", "")!!, p.getInt("ntrip.port", 2101),
        p.getString("ntrip.mount", "")!!, p.getString("ntrip.user", "")!!, p.getBoolean("ntrip.tls", false),
        p.getBoolean("ntrip.v2", true), p.getBoolean("ntrip.gga", true), p.getInt("ntrip.ggaS", 10),
        p.getInt("ntrip.timeoutS", 15), p.getBoolean("ntrip.reconnect", true),
    )

    fun saveNtrip(n: Ntrip, password: String?) {
        p.edit().putBoolean("ntrip.enabled", n.enabled).putString("ntrip.host", n.host.trim()).putInt("ntrip.port", n.port)
            .putString("ntrip.mount", n.mountpoint.trim()).putString("ntrip.user", n.user).putBoolean("ntrip.tls", n.tls)
            .putBoolean("ntrip.v2", n.v2).putBoolean("ntrip.gga", n.sendGga).putInt("ntrip.ggaS", n.ggaIntervalS)
            .putInt("ntrip.timeoutS", n.timeoutS).putBoolean("ntrip.reconnect", n.reconnect).apply()
        if (password != null) secure.ntripPassword = password
        _ntrip.value = n
    }

    fun ntripConfig(): NtripConfig {
        val n = _ntrip.value
        return NtripConfig(n.host, n.port, n.mountpoint, n.user, secure.ntripPassword ?: "", n.tls,
            if (n.v2) NtripVersion.V2 else NtripVersion.V1, n.sendGga, n.ggaIntervalS, 10_000, n.timeoutS * 1000, n.reconnect)
    }

    /** The single watch this phone is allowed to talk to (BLE address). */
    var authorizedWatch: String?
        get() = p.getString("watch.address", null)
        set(v) { p.edit().putString("watch.address", v).apply() }
    var authorizedWatchName: String?
        get() = p.getString("watch.name", null)
        set(v) { p.edit().putString("watch.name", v).apply() }

    var selectedHorseId: Long
        get() = p.getLong("sel.horse", 0)
        set(v) { p.edit().putLong("sel.horse", v).apply() }
    var selectedRiderId: Long
        get() = p.getLong("sel.rider", 0)
        set(v) { p.edit().putLong("sel.rider", v).apply() }

    /** Favorite WhatsApp recipient labels; WhatsApp itself chooses the conversation. */
    var shareFavorites: List<String>
        get() = runCatching {
            org.json.JSONArray(p.getString("share.favorites", "[]") ?: "[]").let { arr ->
                (0 until arr.length()).map { arr.getString(it) }.filter { it.isNotBlank() }.take(12)
            }
        }.getOrDefault(emptyList())
        set(values) {
            val cleaned = values.map { it.trim().take(80) }.filter { it.isNotBlank() }
                .distinctBy { it.lowercase(java.util.Locale.ROOT) }.take(12)
            p.edit().putString("share.favorites", org.json.JSONArray(cleaned).toString()).apply()
        }

    var shareDefaultFavorite: String
        get() = p.getString("share.defaultFavorite", "") ?: ""
        set(value) { p.edit().putString("share.defaultFavorite", value.take(80)).apply() }

    /** Explicit opt-in; no DND change occurs unless Android grants policy access. */
    var autoDndGeofence: Boolean
        get() = p.getBoolean("training.dnd.geofence", false)
        set(v) { p.edit().putBoolean("training.dnd.geofence", v).apply() }

    var autoDownload: Boolean
        get() = p.getBoolean("sync.autoDownload", true)
        set(v) { p.edit().putBoolean("sync.autoDownload", v).apply() }

    /** Tide port chosen from the official IHM list (null = nearest to the training spot). */
    var tidePortId: String?
        get() = p.getString("tide.port.id", null)
        set(v) { p.edit().putString("tide.port.id", v).apply() }

    /** Training spot used for weather, sun/moon and the nearest tide port (default: El Regatón, Laredo). */
    var spotName: String
        get() = p.getString("tide.spot.name", "El Regatón") ?: "El Regatón"
        set(v) { p.edit().putString("tide.spot.name", v).apply() }
    var spotLat: Double
        get() = p.getFloat("tide.spot.lat", 43.397f).toDouble()
        set(v) { p.edit().putFloat("tide.spot.lat", v.toFloat()).apply() }
    var spotLon: Double
        get() = p.getFloat("tide.spot.lon", -3.426f).toDouble()
        set(v) { p.edit().putFloat("tide.spot.lon", v.toFloat()).apply() }
}
