package org.avoperformance.horse.core.license

import org.avoperformance.horse.core.identity.AvoUserCard
import java.util.Base64

/**
 * One user of the AVO Tarjetas register: their card (code, name and secret — needed to write copies and to
 * encrypt licence files), the last licence given (roles + expiry) and contact data.
 */
data class RegUser(
    val card: AvoUserCard,
    val createdMs: Long,
    val revoked: Boolean = false,
    /** UID of the chip the last licence was written to ("" = unknown). */
    val uidHex: String = "",
    /** Roles of the last licence (0 = none). */
    val rolesBits: Int = 0,
    /** Expiry of the last licence (card or file; 0 = none). */
    val expiresS: Long = 0,
    val phone: String = "",
    val email: String = "",
    val notes: String = "",
) {
    val code: String get() = card.code
    val roles: Set<LicenseRole> get() = LicenseRole.fromBits(rolesBits)
    fun licenseActive(nowMs: Long) = expiresS > 0 && nowMs / 1000 < expiresS
}

/** Entry of the licence history (what was given, when and how). */
data class RegEvent(val ms: Long, val code: String, val kind: Kind, val rolesBits: Int = 0, val expiresS: Long = 0, val detail: String = "") {
    enum class Kind(val label: String) {
        ALTA("Alta"), TARJETA("Licencia en tarjeta"), ARCHIVO("Licencia por archivo"), COPIA("Copia de tarjeta"),
        BAJA("Baja"), REACTIVADA("Reactivada"), EDITADO("Datos editados"), IMPORTADA("Añadida desde una tarjeta"),
    }
}

/**
 * Register of users and licences of AVO Tarjetas (immutable; every change returns a new register).
 * Text format, one record per line, every field in base64 (UTF-8) so any name or note is safe:
 *
 *   AVO-REG-1
 *   U <cardUri> <createdMs> <revoked> <uidHex> <rolesBits> <expiresS> <phone> <email> <notes>
 *   E <ms> <code> <kind> <rolesBits> <expiresS> <detail>
 *
 * It contains the card secrets: it is only stored encrypted (SecureStore) or inside a password backup.
 */
data class IssuerRegistry(val users: List<RegUser> = emptyList(), val events: List<RegEvent> = emptyList()) {

    fun user(code: String): RegUser? = users.firstOrNull { it.code == code }

    fun history(code: String): List<RegEvent> = events.filter { it.code == code }.sortedByDescending { it.ms }

    /** Adds or replaces [u] (by code) and records [event] if given. */
    fun upsert(u: RegUser, event: RegEvent? = null): IssuerRegistry =
        IssuerRegistry(users.filterNot { it.code == u.code } + u, if (event != null) events + event else events)

    /** Users sorted by name; [query] matches name, code, phone, email or notes (case insensitive). */
    fun search(query: String): List<RegUser> {
        val q = query.trim()
        val base = users.sortedWith(compareBy({ it.revoked }, { it.card.name.lowercase() }))
        if (q.isEmpty()) return base
        return base.filter { u ->
            listOf(u.card.name, u.code, u.phone, u.email, u.notes).any { it.contains(q, ignoreCase = true) } ||
                LicenseRole.label(u.roles).contains(q, ignoreCase = true)
        }
    }

    /** Merges [other] (backup restore): users missing here are added; for the same user, the newer licence wins. */
    fun merge(other: IssuerRegistry): IssuerRegistry {
        val byCode = users.associateBy { it.code }.toMutableMap()
        for (u in other.users) {
            val cur = byCode[u.code]
            byCode[u.code] = when {
                cur == null -> u
                u.expiresS > cur.expiresS -> u.copy(phone = u.phone.ifBlank { cur.phone }, email = u.email.ifBlank { cur.email },
                    notes = u.notes.ifBlank { cur.notes })
                else -> cur
            }
        }
        val ev = (events + other.events).distinctBy { listOf(it.ms, it.code, it.kind, it.rolesBits, it.expiresS, it.detail) }.sortedBy { it.ms }
        return IssuerRegistry(byCode.values.toList(), ev)
    }

    fun encode(): String = buildString {
        append(HEADER).append('\n')
        users.forEach { u ->
            append(listOf("U", b(u.card.toUri()), u.createdMs, if (u.revoked) 1 else 0, b(u.uidHex), u.rolesBits, u.expiresS,
                b(u.phone), b(u.email), b(u.notes)).joinToString("\t")).append('\n')
        }
        events.forEach { e ->
            append(listOf("E", e.ms, b(e.code), e.kind.name, e.rolesBits, e.expiresS, b(e.detail)).joinToString("\t")).append('\n')
        }
    }

    companion object {
        const val HEADER = "AVO-REG-1"
        private fun b(s: String) = Base64.getEncoder().encodeToString(s.toByteArray(Charsets.UTF_8))
        private fun u(s: String) = String(Base64.getDecoder().decode(s), Charsets.UTF_8)

        /** Damaged lines are skipped (a single bad record must not lose the whole register). */
        fun decode(text: String): IssuerRegistry {
            val lines = text.lines().filter { it.isNotBlank() }
            require(lines.firstOrNull()?.trim() == HEADER) { "Registro de AVO Tarjetas no válido" }
            val users = mutableListOf<RegUser>()
            val events = mutableListOf<RegEvent>()
            for (line in lines.drop(1)) {
                val p = line.split('\t')
                runCatching {
                    when (p[0]) {
                        "U" -> users += RegUser(AvoUserCard.parse(u(p[1])), p[2].toLong(), p[3] == "1", u(p[4]), p[5].toInt(), p[6].toLong(),
                            u(p[7]), u(p[8]), u(p[9]))
                        "E" -> events += RegEvent(p[1].toLong(), u(p[2]), RegEvent.Kind.valueOf(p[3]), p[4].toInt(), p[5].toLong(), u(p[6]))
                    }
                }
            }
            return IssuerRegistry(users.distinctBy { it.code }, events)
        }
    }
}

/**
 * Full backup of AVO Tarjetas in one password file: signing key (optional) + register. Restoring it on a
 * new phone (or after reinstalling) brings back everything needed to keep issuing licences.
 */
object IssuerBackup {
    const val HEADER = "AVO-TARJETAS-COPIA-1"

    fun export(key: java.security.KeyPair?, registry: IssuerRegistry, password: CharArray,
               random: java.security.SecureRandom = java.security.SecureRandom(), iterations: Int = LicenseKeyBackup.ITERATIONS): String {
        val enc = Base64.getEncoder()
        val keyLine = key?.let { "KEY\t${enc.encodeToString(it.public.encoded)}\t${enc.encodeToString(it.private.encoded)}" } ?: "KEY\t-\t-"
        return PasswordBox.seal(HEADER, (keyLine + "\n" + registry.encode()).toByteArray(Charsets.UTF_8), password, random, iterations)
    }

    data class Restored(val key: java.security.KeyPair?, val registry: IssuerRegistry)

    fun import(text: String, password: CharArray): Restored {
        val content = String(PasswordBox.open(text, HEADER, password), Charsets.UTF_8)
        val first = content.substringBefore('\n').split('\t')
        require(first.size == 3 && first[0] == "KEY") { "Copia dañada" }
        val key = if (first[1] == "-") null else try {
            java.security.KeyPair(LicenseCrypto.publicKeyFromSpki(Base64.getDecoder().decode(first[1])),
                LicenseCrypto.privateKeyFromPkcs8(Base64.getDecoder().decode(first[2])))
        } catch (e: Exception) { throw IllegalArgumentException("Copia dañada") }
        if (key != null) require(LicenseKeyBackup.pairMatches(key)) { "La clave de la copia no es coherente" }
        return Restored(key, IssuerRegistry.decode(content.substringAfter('\n')))
    }
}
