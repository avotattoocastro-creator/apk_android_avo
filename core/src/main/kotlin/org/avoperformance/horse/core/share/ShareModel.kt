package org.avoperformance.horse.core.share

import java.security.MessageDigest

/*
 * AVO training sharing between users (Firebase Realtime Database, Spark plan).
 * Pure logic with no Android or Firebase: recipient resolution, stable identifiers, chunking, states,
 * expiry. The real backend (Firebase) and storage (Room) implement the interfaces in ShareBackend.kt.
 * User identity = AVO NFC card (code AVO-XXXX-XXXX).
 */

/** Why a recipient receives a training. When combining, the most "permanent" one is kept. */
enum class ShareOrigin { GLOBAL, HORSE, MANUAL }

/** Authorization of a sender by a recipient (invitation). Only ACCEPTED allows sending. */
enum class GrantState { PENDING, ACCEPTED, REJECTED, BLOCKED }

/** State of a delivery (training → recipient) seen by the sender. */
enum class OutState {
    /** In the queue; nothing uploaded yet (or waiting for network). */
    QUEUED,
    /** The recipient has not accepted the invitation yet: it stays waiting, without uploading data. */
    WAITING_ACCEPT,
    /** Content uploading (shared by all recipients of the same training). */
    UPLOADING,
    /** Content complete and notice published in the recipient's inbox. */
    NOTIFIED,
    /** The recipient confirmed that they imported it correctly. */
    RECEIVED,
    /** The recipient blocked this sender or rejected the invitation. */
    BLOCKED,
    /** Expiry policy met without confirmation: the temporary content was deleted. */
    EXPIRED,
    /** Permanent error (e.g. training too big). */
    FAILED;

    val terminal get() = this == RECEIVED || this == BLOCKED || this == EXPIRED || this == FAILED
}

/** State of a delivery seen by the recipient. */
enum class InState { DOWNLOADING, IMPORTED, ALREADY_PRESENT, NEEDS_CONFIRMATION, FAILED }

data class Contact(val code: String, val name: String)

/** Outgoing delivery: one row per (training, recipient). Persistent identifier = [key]. */
data class OutJob(
    val sessionId: String,
    val recipient: String,
    val recipientName: String,
    val origin: ShareOrigin,
    val state: OutState = OutState.QUEUED,
    val transferId: String? = null,
    val attempts: Int = 0,
    val lastError: String? = null,
    val createdMs: Long,
    val updatedMs: Long = createdMs,
    val receivedMs: Long? = null,
    val horseCode: String? = null,
) {
    val key get() = keyOf(sessionId, recipient)
    companion object { fun keyOf(sessionId: String, recipient: String) = "$sessionId|$recipient" }
}

/** Incoming delivery (history and deliveries pending confirmation). */
data class InRecord(
    val transferId: String,
    val from: String,
    val fromName: String,
    val sessionId: String,
    val horseName: String,
    val size: Long,
    val state: InState,
    val receivedMs: Long,
    val message: String? = null,
    val localFile: String? = null,
)

/** Shared content of a transfer (a single copy for all recipients). */
data class TransferMeta(
    val transferId: String,
    val owner: String,
    val ownerName: String,
    val sessionId: String,
    val horseName: String,
    val riderName: String,
    val size: Long,
    val sha256: String,
    val chunks: Int,
    val chunkSize: Int,
    val createdMs: Long,
    val expiresMs: Long,
)

/** Notice in the recipient's inbox: it only says that a transfer exists, without data. */
data class Notice(
    val transferId: String,
    val from: String,
    val fromName: String,
    val sessionId: String,
    val horseName: String,
    val size: Long,
    val createdMs: Long,
)

/** Configurable limits (Spark plan: 1 GB stored, 10 GB/month downloaded). */
data class ShareLimits(
    val maxTrainingBytes: Long = 30L * 1024 * 1024,
    val chunkBytes: Int = 256 * 1024,
    val expiryMs: Long = 14L * 24 * 3600 * 1000,
    /** Monthly upload+download warning (bytes). */
    val monthlyWarnBytes: Long = 5L * 1024 * 1024 * 1024,
) {
    init {
        require(chunkBytes in 16 * 1024..262_144) { "Trozo fuera de rango (las reglas limitan a 360 000 caracteres base64)" }
        require(maxTrainingBytes / chunkBytes <= MAX_CHUNKS) { "Demasiados trozos para las reglas" }
    }
    companion object { const val MAX_CHUNKS = 120 }
}

object ShareIds {
    private val CODE = Regex("AVO-[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{4}-[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{4}")
    fun isUserCode(s: String?) = s != null && CODE.matches(s)

    /**
     * Stable transfer identifier: same owner + same session + same content ⇒ same id.
     * This is how a re-share reuses the content and the recipient never ends up with two copies.
     */
    fun transferId(owner: String, sessionId: String, contentSha256: String): String =
        sha256Hex("$owner\n$sessionId\n${contentSha256.lowercase()}".toByteArray()).take(32)

    fun sha256Hex(b: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(b).joinToString("") { "%02x".format(it) }

    fun chunkCount(size: Long, chunk: Int): Int = ((size + chunk - 1) / chunk).toInt()
}

/**
 * Combines the three modes. Result: one recipient per user (the B that is global and per horse
 * receives a single copy), never yourself, only with an accepted invitation (the rest stay
 * waiting) and never blocked users.
 */
object RecipientResolver {
    data class Target(val contact: Contact, val origin: ShareOrigin, val grant: GrantState?)

    fun resolve(
        me: String,
        global: List<Contact>,
        globalEnabled: Boolean,
        horse: List<Contact>,
        horseEnabled: Boolean,
        manual: List<Contact>,
        grants: Map<String, GrantState>,
    ): List<Target> {
        val out = LinkedHashMap<String, Target>()
        fun add(list: List<Contact>, origin: ShareOrigin) = list.forEach { c ->
            if (c.code == me || !ShareIds.isUserCode(c.code)) return@forEach
            if (out[c.code] == null) out[c.code] = Target(c, origin, grants[c.code])
        }
        if (globalEnabled) add(global, ShareOrigin.GLOBAL)
        if (horseEnabled) add(horse, ShareOrigin.HORSE)
        add(manual, ShareOrigin.MANUAL)
        return out.values.toList()
    }
}
