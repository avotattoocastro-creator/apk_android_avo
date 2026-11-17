package org.avoperformance.horse.core.share

import java.time.Instant
import java.time.format.DateTimeParseException

/**
 * AVO-ASSIGN-1 (docs/ASIGNACION_CABALLO.md): horse and rider assigned to a training after recording.
 * The manifest of the .avo package is the source of truth; the RAW is never modified.
 * Pure JVM (no Android): the app reads/writes the manifest with org.json and uses these rules.
 */
data class AvoAssignment(
    val horseCode: String?, val horseName: String?,
    val riderCode: String?, val riderName: String?,
    val updatedUtcMs: Long, val app: String,
    /** What the RAW header says (horse_name / rider_name), kept so a reassignment never loses it. */
    val rawHorse: String? = null, val rawRider: String? = null,
) {
    val isEmpty: Boolean get() = listOf(horseCode, horseName, riderCode, riderName).all { it.isNullOrBlank() }

    /** The «asignacion» block of the manifest as JSON text (keys in the order of the contract). */
    fun toJson(): String = buildString {
        append("{\"version\":1")
        field("horseCode", horseCode); field("horseName", horseName); field("riderCode", riderCode); field("riderName", riderName)
        append(",\"actualizadoUtc\":").append(str(iso(updatedUtcMs))).append(",\"app\":").append(str(app))
        append(",\"raw\":{\"horseCode\":").append(strOrNull(rawHorse)).append(",\"riderCode\":").append(strOrNull(rawRider)).append("}}")
    }

    private fun StringBuilder.field(k: String, v: String?) { append(",\"").append(k).append("\":").append(strOrNull(v)) }

    companion object {
        /** Builds the block from the values of a parsed «asignacion» object (null if nothing usable). */
        fun fromFields(get: (String) -> String?, rawGet: (String) -> String? = { null }): AvoAssignment? {
            fun g(k: String) = get(k)?.trim()?.takeIf { it.isNotEmpty() && it != "null" }
            val a = AvoAssignment(g("horseCode"), g("horseName"), g("riderCode"), g("riderName"),
                parseIso(get("actualizadoUtc")), g("app") ?: "",
                rawGet("horseCode")?.trim()?.takeIf { it.isNotEmpty() }, rawGet("riderCode")?.trim()?.takeIf { it.isNotEmpty() })
            return a.takeUnless { it.isEmpty }
        }

        /** The identity to use from a manifest: «asignacion» first, then the top-level fields. */
        fun resolve(block: AvoAssignment?, topHorseCode: String?, topHorseName: String?, topRiderCode: String?, topRiderName: String?): Identity {
            fun pick(a: String?, b: String?) = a?.takeIf { it.isNotBlank() } ?: b?.trim()?.takeIf { it.isNotBlank() }
            return Identity(pick(block?.horseCode, topHorseCode), pick(block?.horseName, topHorseName),
                pick(block?.riderCode, topRiderCode), pick(block?.riderName, topRiderName))
        }

        /**
         * On importing a training that already exists here: the file's assignment wins only if it is newer than the last
         * local change. A file without a block (older app) never overrides a horse already assigned on this phone.
         */
        fun fileWins(block: AvoAssignment?, localHorseCode: String?, localUpdatedMs: Long): Boolean = when {
            localHorseCode.isNullOrBlank() -> true
            block == null -> false
            else -> block.updatedUtcMs > localUpdatedMs
        }

        /** Engine option fragment ("asignacion":{…}) for avo_eq_analyse_ex, or null when nothing is known. */
        fun engineOption(horseCode: String?, horseName: String?, riderCode: String?, riderName: String?): String? {
            val parts = listOf("horseCode" to horseCode, "horseName" to horseName, "riderCode" to riderCode, "riderName" to riderName)
                .filter { !it.second.isNullOrBlank() }
            if (parts.isEmpty()) return null
            return "\"asignacion\":{" + parts.joinToString(",") { "\"${it.first}\":${str(it.second!!.trim())}" } + "}"
        }

        /** True if the watch configuration does not carry the horse/rider chosen in the app (send it before recording). */
        fun watchNeedsIdentity(watchHorse: String?, watchRider: String?, horseCode: String?, riderCode: String?): Boolean =
            (!horseCode.isNullOrBlank() && watchHorse?.trim() != horseCode.trim()) ||
                (!riderCode.isNullOrBlank() && watchRider?.trim() != riderCode.trim())

        fun iso(ms: Long): String = Instant.ofEpochMilli(ms).toString().let { if (it.contains('.')) it.substringBefore('.') + "Z" else it }
        fun parseIso(s: String?): Long = try { if (s.isNullOrBlank()) 0L else Instant.parse(s.trim()).toEpochMilli() } catch (_: DateTimeParseException) { 0L }

        fun str(s: String): String = buildString {
            append('"')
            s.forEach { ch -> when (ch) { '"' -> append("\\\""); '\\' -> append("\\\\"); else -> if (ch < ' ') append("\\u%04x".format(ch.code)) else append(ch) } }
            append('"')
        }
        private fun strOrNull(s: String?) = if (s.isNullOrBlank()) "null" else str(s.trim())
    }

    data class Identity(val horseCode: String?, val horseName: String?, val riderCode: String?, val riderName: String?)
}
