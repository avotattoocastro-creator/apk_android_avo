package org.avoperformance.horse.core.nfc

import android.net.Uri
import org.avoperformance.horse.data.*
import kotlinx.coroutines.flow.first

/** Versioned NDEF URI, backwards-compatible with AVO identity-only tags. */
object AvoNfc {
    fun horse(h: HorseEntity): Uri = Uri.parse("avohorse://identity/horse/${Uri.encode(h.code)}").buildUpon()
        .appendQueryParameter("v", "2").appendQueryParameter("name", h.name)
        .appendQueryParameter("breed", h.breed).appendQueryParameter("birthYear", h.birthYear?.toString() ?: "")
        .appendQueryParameter("notes", h.notes).appendQueryParameter("active", h.active.toString()).build()
    fun rider(r: RiderEntity): Uri = Uri.parse("avohorse://identity/rider/${Uri.encode(r.code)}").buildUpon()
        .appendQueryParameter("v", "2").appendQueryParameter("name", r.name)
        .appendQueryParameter("notes", r.notes).appendQueryParameter("active", r.active.toString()).build()

    suspend fun import(uri: Uri, db: AvoDatabase): Long {
        require(uri.scheme == "avohorse" && uri.host == "identity") { "Etiqueta no AVO" }
        val kind = uri.pathSegments.getOrNull(0)
        val code = uri.pathSegments.getOrNull(1)?.trim().orEmpty()
        require(kind == "horse" || kind == "rider") { "Tipo de ficha desconocido" }
        require(code.isNotBlank() && code.length <= 23 && code.none { it.isISOControl() }) { "ID no válido" }
        val version = uri.getQueryParameter("v")
        require(version == null || version == "2") { "Versión NFC no compatible" }
        fun field(key: String, fallback: String) = uri.getQueryParameter(key)?.take(512) ?: fallback
        val name = field("name", code).ifBlank { code }
        val notes = field("notes", "")
        val active = field("active", "true") != "false"
        if (kind == "horse") {
            val existing = db.horses().all().first().firstOrNull { it.code == code }
            if (existing != null) return existing.id // Never overwrite locally edited records.
            val birth = uri.getQueryParameter("birthYear")?.toIntOrNull()?.takeIf { it in 1900..2100 }
            return db.horses().insert(HorseEntity(code = code, name = name, breed = field("breed", ""), birthYear = birth, notes = notes, active = active))
        }
        val existing = db.riders().all().first().firstOrNull { it.code == code }
        if (existing != null) return existing.id
        return db.riders().insert(RiderEntity(code = code, name = name, notes = notes, active = active))
    }
}
