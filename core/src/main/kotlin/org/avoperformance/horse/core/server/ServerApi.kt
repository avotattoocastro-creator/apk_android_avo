package org.avoperformance.horse.core.server

import java.io.File

/**
 * Server layer — ON HOLD by decision of the project owner.
 * The historical endpoints known from earlier AVO versions are listed only as
 * documentation; their request/response formats are NOT known and are NOT
 * implemented here (nothing is invented):
 *   /api/latest, /api/telemetry, /api/work/…, /api/session/raw_upload, /api/rtcm/chunk
 * Until a real implementation exists, [NotConfiguredServer] is used and no file
 * can ever reach the state "verificado por el servidor".
 */
interface ServerApi {
    val configured: Boolean
    /** Uploads a session; returns the SHA-256 the server computed (hex) only when the server confirmed storage. */
    fun uploadSession(sessionId: String, segments: List<File>, sha256Hex: String, horseCode: String?, riderCode: String?): UploadResult
    fun listTrainings(): List<RemoteTraining>
}

sealed class UploadResult {
    data class Confirmed(val serverSha256Hex: String, val serverId: String) : UploadResult()
    data class Rejected(val reason: String) : UploadResult()
    object NotConfigured : UploadResult()
    data class NetworkError(val reason: String) : UploadResult()
}

data class RemoteTraining(val id: String, val sessionId: String, val startMs: Long, val horseCode: String?, val sizeBytes: Long)

object NotConfiguredServer : ServerApi {
    override val configured = false
    override fun uploadSession(sessionId: String, segments: List<File>, sha256Hex: String, horseCode: String?, riderCode: String?) = UploadResult.NotConfigured
    override fun listTrainings(): List<RemoteTraining> = emptyList()
}
