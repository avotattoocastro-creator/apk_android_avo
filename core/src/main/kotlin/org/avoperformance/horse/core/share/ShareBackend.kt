package org.avoperformance.horse.core.share

import java.io.File

/**
 * Server operations (Firebase Realtime Database in the app; in-memory in the tests).
 * Every operation must be idempotent: the engine repeats them after any interruption.
 * Network errors are thrown as [OfflineException] (the engine stops and the work is retried later).
 */
interface ShareBackend {
    /** Authorization state that [recipient] has given to [sender]. */
    suspend fun grant(recipient: String, sender: String): GrantState?

    suspend fun meta(transferId: String): TransferMeta?
    /** Creates the content (meta). If it already exists with the same content, it does nothing. */
    suspend fun createMeta(m: TransferMeta)
    /** Number of chunks already uploaded consecutively from 0 (to resume). */
    suspend fun uploadedChunks(transferId: String): Int
    suspend fun putChunk(transferId: String, index: Int, data: ByteArray)
    suspend fun getChunk(transferId: String, index: Int): ByteArray?
    /** Marks the content complete (all chunks present). Only then can notices be published. */
    suspend fun markComplete(transferId: String)
    suspend fun isComplete(transferId: String): Boolean
    /** Gives [recipient] permission to read the content. */
    suspend fun allowRecipient(transferId: String, recipient: String)
    /** Revokes [recipient]'s read permission. */
    suspend fun revokeRecipient(transferId: String, recipient: String)

    suspend fun notify(recipient: String, n: Notice)
    suspend fun inbox(me: String): List<Notice>
    suspend fun removeNotice(me: String, transferId: String)

    /** Receipt by the recipient: "imported", "present" or "error:<reason>". */
    suspend fun putReceipt(transferId: String, me: String, value: String)
    suspend fun receipts(transferId: String): Map<String, String>

    /** Deletes the temporary content (meta, chunks, permissions and receipts). */
    suspend fun deleteTransfer(transferId: String)
}

class OfflineException(message: String, cause: Throwable? = null) : Exception(message, cause)

/** Local persistence of the queue and the history (Room in the app). */
interface ShareStore {
    fun jobs(): List<OutJob>
    fun upsert(job: OutJob)
    fun incoming(): List<InRecord>
    fun upsertIncoming(r: InRecord)
    fun addUsage(uploaded: Long, downloaded: Long)
}

/** Local package of a training (the .avo AVO-TRAINING-1 format of the WhatsApp/import system). */
data class Packaged(val file: File, val sha256: String, val size: Long, val horseName: String, val riderName: String)

interface Packager {
    /** Builds the package. Error if the training is not downloaded and verified or has no horse/rider. */
    suspend fun build(sessionId: String): Packaged
}

/** Imports a received package into the library (same validations as the manual import). */
interface Importer {
    sealed interface Result {
        data object Imported : Result
        /** It was already in the library with identical content: nothing is duplicated. */
        data object AlreadyPresent : Result
        /** There is a different version locally: it is not overwritten without the user's authorization. */
        data class NeedsConfirmation(val reason: String) : Result
    }
    suspend fun import(file: File, notice: Notice): Result
}
