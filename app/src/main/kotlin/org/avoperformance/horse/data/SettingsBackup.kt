package org.avoperformance.horse.data

import org.json.JSONObject

/** Portable settings backup v1. Does not export credentials, BLE trust keys or phone-specific IDs. */
object SettingsBackup {
    fun export(settings: Settings): String {
        val n = settings.ntrip.value
        return JSONObject().put("format", "AVO_SETTINGS_BACKUP")
            .put("schema", 1)
            .put("ntrip", JSONObject()
                .put("enabled", n.enabled).put("host", n.host).put("port", n.port)
                .put("mountpoint", n.mountpoint).put("user", n.user)
                .put("tls", n.tls).put("v2", n.v2).put("sendGga", n.sendGga)
                .put("ggaIntervalS", n.ggaIntervalS).put("timeoutS", n.timeoutS)
                .put("reconnect", n.reconnect))
            .put("sync", JSONObject().put("autoDownload", settings.autoDownload))
            .put("sharing", JSONObject()
                .put("favorites", org.json.JSONArray(settings.shareFavorites))
                .put("default", settings.shareDefaultFavorite))
            .put("securityNote", "NTRIP password and BLE authorization keys excluded")
            .toString(2)
    }

    fun restore(settings: Settings, json: String) {
        require(json.length <= 256_000) { "Copia demasiado grande" }
        val root = JSONObject(json)
        require(root.optString("format") == "AVO_SETTINGS_BACKUP" && root.optInt("schema") == 1) {
            "Formato o versión de copia no compatible"
        }
        val o = root.getJSONObject("ntrip")
        fun string(k: String, max: Int) = o.getString(k).also { require(it.length <= max) { "Campo $k demasiado largo" } }
        fun range(k: String, min: Int, max: Int) = o.getInt(k).also { require(it in min..max) { "Valor $k no válido" } }
        val candidate = Settings.Ntrip(
            enabled = o.getBoolean("enabled"), host = string("host", 255),
            port = range("port", 1, 65535), mountpoint = string("mountpoint", 255),
            user = string("user", 255), tls = o.getBoolean("tls"), v2 = o.getBoolean("v2"),
            sendGga = o.getBoolean("sendGga"), ggaIntervalS = range("ggaIntervalS", 1, 3600),
            timeoutS = range("timeoutS", 1, 180), reconnect = o.getBoolean("reconnect")
        )
        val auto = root.getJSONObject("sync").getBoolean("autoDownload")
        val sharing = root.optJSONObject("sharing")
        val favorites = sharing?.optJSONArray("favorites")?.let { arr ->
            require(arr.length() <= 12) { "Demasiados destinatarios" }
            (0 until arr.length()).map { arr.getString(it).also { name ->
                require(name.isNotBlank() && name.length <= 80) { "Favorito no válido" }
            } }
        } ?: emptyList()
        val defaultFavorite = sharing?.optString("default") ?: ""
        require(defaultFavorite.length <= 80) { "Destinatario demasiado largo" }
        // No partial modification before every field is validated.
        settings.saveNtrip(candidate, null)
        settings.autoDownload = auto
        if (sharing != null) {
            settings.shareFavorites = favorites
            settings.shareDefaultFavorite = defaultFavorite.takeIf { it in favorites }.orEmpty()
        }
    }
}
