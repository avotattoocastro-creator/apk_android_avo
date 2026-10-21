package org.avoperformance.horse.core.ble

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout
import org.avoperformance.horse.core.auth.WatchAuth
import org.avoperformance.horse.core.auth.WatchCredential
import java.util.concurrent.ConcurrentHashMap

/**
 * Raw GATT access implemented by the Android layer (BluetoothGatt) or by a test double.
 * Writes must be serialized by the implementation (Android allows one GATT op at a time).
 */
interface AvoTransport {
    /** Write with response on CTRL_RX. Throws on GATT failure. */
    suspend fun writeCtrl(frag: ByteArray)
    /** Write without response on RTCM. Returns false if the stack refused it (buffer full). */
    suspend fun writeRtcm(frag: ByteArray): Boolean
    /** ATT payload size (negotiated MTU - 3). */
    val attPayload: Int
}

class BleRequestException(val status: BleStatus, message: String) : Exception(message)

/** Retry policy: idempotent reads get a fresh msg_id; state-changing commands keep it (the watch answers DUPLICATE and does not execute twice). */
enum class Idempotency { READ_ONLY, STATE_CHANGING }

/**
 * Request/response engine on top of the AVO BLE protocol v1.
 * - One request in flight (the firmware reassembles at most 2 messages).
 * - Responses are matched by msg_id (READ_FILE answers come on FILE_TX with type FILE_DATA).
 * - Unsolicited messages (TELEMETRY, RTCM_ACK, EVENT; msg_id ≥ 0x8000) go to [onUnsolicited].
 */
class AvoClient(
    private val t: AvoTransport,
    private val onUnsolicited: (BleMessage) -> Unit,
    startMsgId: Int = (1 + java.security.SecureRandom().nextInt(0x7000)),
) {
    private val reasmCtrl = BleReassembler()
    private val reasmFile = BleReassembler()
    private val reasmTelem = BleReassembler()
    private val pending = ConcurrentHashMap<Int, CompletableDeferred<BleMessage>>()
    private val inFlight = Mutex()
    private var nextId = startMsgId and 0x7FFF
    private var rtcmMsgId = 0
    var lateResponses = 0; private set
    var stats = Stats(); private set

    data class Stats(val requests: Long = 0, val retries: Long = 0, val timeouts: Long = 0, val duplicates: Long = 0, val crcErrors: Int = 0, val gaps: Int = 0)

    private fun newId(): Int { nextId = (nextId + 1) and 0x7FFF; if (nextId == 0) nextId = 1; return nextId }

    /** Feed every notification here, tagged with the characteristic it came from. */
    fun onNotification(ch: java.util.UUID, value: ByteArray) {
        val r = when (ch) { AvoGatt.FILE_TX -> reasmFile; AvoGatt.TELEM -> reasmTelem; else -> reasmCtrl }
        val m = r.feed(value) ?: run { stats = stats.copy(crcErrors = reasmCtrl.crcErrors + reasmFile.crcErrors + reasmTelem.crcErrors, gaps = reasmCtrl.gaps + reasmFile.gaps + reasmTelem.gaps); return }
        if (m.isResponse) { if (pending.remove(m.msgId)?.complete(m) == null) lateResponses++ }   // late response (after timeout): ignored, counted
        else onUnsolicited(m)
    }

    fun onDisconnected() {
        reasmCtrl.reset(); reasmFile.reset(); reasmTelem.reset()
        pending.values.forEach { it.completeExceptionally(BleRequestException(BleStatus.TIMEOUT, "Conexión perdida")) }
        pending.clear()
    }

    /**
     * Sends a request and waits for its response. Returns the response message
     * (status may be != OK; the caller decides). Throws only after all retries time out.
     */
    suspend fun request(type: MsgType, payload: ByteArray = ByteArray(0), idem: Idempotency = Idempotency.READ_ONLY,
                        timeoutMs: Long = 3000, retries: Int = 2): BleMessage = inFlight.withLock {
        var id = newId()
        var attempt = 0
        stats = stats.copy(requests = stats.requests + 1)
        while (true) {
            val d = CompletableDeferred<BleMessage>()
            pending[id] = d
            try {
                for (f in BleFraming.fragment(type.code, id, payload, t.attPayload)) t.writeCtrl(f)
                val m = withTimeout(timeoutMs) { d.await() }
                if (m.statusEnum == BleStatus.DUPLICATE) stats = stats.copy(duplicates = stats.duplicates + 1)
                if (m.statusEnum == BleStatus.BAD_CRC && attempt < retries) { attempt++; stats = stats.copy(retries = stats.retries + 1); continue }
                return@withLock m
            } catch (e: TimeoutCancellationException) {
                pending.remove(id)
                stats = stats.copy(timeouts = stats.timeouts + 1)
                if (attempt >= retries) throw BleRequestException(BleStatus.TIMEOUT, "Sin respuesta del reloj (${type.name})")
                attempt++
                stats = stats.copy(retries = stats.retries + 1)
                if (idem == Idempotency.READ_ONLY) id = newId()   // same id for state-changing commands
            } finally {
                pending.remove(id)
            }
        }
        @Suppress("UNREACHABLE_CODE") throw IllegalStateException()
    }

    suspend fun requestOk(type: MsgType, payload: ByteArray = ByteArray(0), idem: Idempotency = Idempotency.READ_ONLY, timeoutMs: Long = 3000): ByteArray {
        val m = request(type, payload, idem, timeoutMs)
        if (m.statusEnum != BleStatus.OK) throw BleRequestException(m.statusEnum, "${type.name}: ${m.statusEnum.texto}")
        return m.payload
    }

    // ---------------------------------------------------------------- typed helpers
    suspend fun getInfo(): WatchInfo = WatchInfo.decode(requestOk(MsgType.GET_INFO)) ?: throw BleRequestException(BleStatus.BAD_FORMAT, "GET_INFO ilegible")
    suspend fun getStatus(): WatchStatus = WatchStatus.decode(requestOk(MsgType.GET_STATUS)) ?: throw BleRequestException(BleStatus.BAD_FORMAT, "GET_STATUS ilegible")

    /** HMAC challenge-response (both directions). Returns true when the watch accepted the phone. */
    suspend fun authenticate(cred: WatchCredential): AuthOutcome {
        val pn = WatchAuth.nonce()
        val m = request(MsgType.AUTH_HELLO, Requests.authHello(cred.keyId, pn))
        when (m.statusEnum) {
            BleStatus.OK -> {}
            BleStatus.NOT_FOUND -> return AuthOutcome.UNKNOWN_KEY
            BleStatus.BUSY -> return AuthOutcome.LOCKED
            else -> return AuthOutcome.ERROR
        }
        if (m.payload.size < 48) return AuthOutcome.ERROR
        val wn = m.payload.copyOfRange(0, 16)
        val wp = m.payload.copyOfRange(16, 48)
        if (!WatchAuth.same(wp, WatchAuth.watchProof(cred.key, pn, wn, cred.deviceId))) return AuthOutcome.WATCH_NOT_AUTHENTIC
        val r = request(MsgType.AUTH_PROOF, WatchAuth.phoneProof(cred.key, wn, pn, cred.deviceId))
        return when (r.statusEnum) {
            BleStatus.OK -> AuthOutcome.OK
            BleStatus.BUSY -> AuthOutcome.LOCKED
            BleStatus.AUTH_REQUIRED -> AuthOutcome.REJECTED
            else -> AuthOutcome.ERROR
        }
    }

    /** Starts the BOOT-button claim. The watch shows "PULSA BOOT" for 60 s. */
    suspend fun claimBegin(phoneName: String): BleStatus = request(MsgType.CLAIM_BEGIN, Requests.claimBegin(phoneName), Idempotency.STATE_CHANGING).statusEnum

    /** Polls CLAIM_RESULT. OK → credential; BUSY → still waiting for BOOT. */
    suspend fun claimResult(deviceId: String): Pair<BleStatus, WatchCredential?> {
        val m = request(MsgType.CLAIM_RESULT)
        if (m.statusEnum == BleStatus.OK && m.payload.size >= 40)
            return BleStatus.OK to WatchCredential(deviceId, m.payload.copyOfRange(0, 8), m.payload.copyOfRange(8, 40))
        return m.statusEnum to null
    }

    suspend fun sessionCommand(cmd: SessionCmd, confirmed: Boolean): BleStatus =
        request(MsgType.SESSION_CMD, Requests.sessionCmd(cmd, confirmed), Idempotency.STATE_CHANGING).statusEnum

    suspend fun listSessions(): List<WatchSessionEntry> {
        val out = ArrayList<WatchSessionEntry>()
        var page = 0
        while (page < 200) {
            val p = SessionListPage.decode(requestOk(MsgType.LIST_SESSIONS, Requests.listSessions(page), timeoutMs = 8000))
                ?: throw BleRequestException(BleStatus.BAD_FORMAT, "Lista de sesiones ilegible")
            out += p.entries
            if (!p.more) break
            page++
        }
        return out
    }

    /** One READ_FILE. Returns null at end of segments (NOT_FOUND). Verifies the chunk CRC-32. */
    suspend fun readChunk(sessionId: String, segment: Int, offset: Long, length: Int = 16384): FileChunk? {
        val m = request(MsgType.READ_FILE, Requests.readFile(sessionId, segment, offset, length), timeoutMs = 8000, retries = 3)
        if (m.statusEnum == BleStatus.NOT_FOUND) return null
        if (m.statusEnum != BleStatus.OK) throw BleRequestException(m.statusEnum, "READ_FILE: ${m.statusEnum.texto}")
        val c = FileChunk.decode(m.payload) ?: throw BleRequestException(BleStatus.BAD_FORMAT, "Bloque de fichero ilegible")
        if (c.offset != offset) throw BleRequestException(BleStatus.BAD_FORMAT, "Desplazamiento inesperado")
        if (org.avoperformance.horse.core.bytes.Crc.crc32(c.data) != c.crc32) throw BleRequestException(BleStatus.BAD_CRC, "CRC del bloque incorrecto")
        return c
    }

    /** SHA-256 of all segments computed by the watch (can take seconds for large sessions). */
    suspend fun fileSha256(sessionId: String): ByteArray {
        val p = requestOk(MsgType.FILE_SHA256, Requests.sessionOnly(sessionId), timeoutMs = 120_000)
        if (p.size < 32) throw BleRequestException(BleStatus.BAD_FORMAT, "SHA-256 ilegible")
        return p.copyOf(32)
    }

    /** Only after real server confirmation. The watch recomputes the hash and refuses if it differs. */
    suspend fun markUploaded(sessionId: String, sha256: ByteArray): BleStatus =
        request(MsgType.MARK_UPLOADED, Requests.markUploaded(sessionId, sha256), Idempotency.STATE_CHANGING, 120_000).statusEnum

    /**
     * Manual deletion of a session on the watch, in two steps (token valid 60 s).
     * The watch itself refuses (NOT_ALLOWED) to delete a session that is not marked UPLOADED unless force=1;
     * this app never sends force=1.
     */
    suspend fun deleteSession(sessionId: String): BleStatus {
        val prep = request(MsgType.DELETE_PREPARE, Requests.sessionOnly(sessionId), Idempotency.STATE_CHANGING)
        if (prep.statusEnum != BleStatus.OK || prep.payload.size < 4) return prep.statusEnum
        val token = org.avoperformance.horse.core.bytes.leU32(prep.payload, 0)
        return request(MsgType.DELETE_COMMIT, Requests.deleteCommit(sessionId, token, force = false), Idempotency.STATE_CHANGING, 15_000).statusEnum
    }

    suspend fun getConfig(): ByteArray = requestOk(MsgType.GET_CONFIG, timeoutMs = 5000)
    suspend fun setConfig(blob: ByteArray): BleMessage = request(MsgType.SET_CONFIG, blob, Idempotency.STATE_CHANGING, 8000)
    suspend fun setFence(req: ByteArray): BleMessage = request(MsgType.SET_FENCE, req, Idempotency.STATE_CHANGING, 8000)
    suspend fun setActiveFences(mask: Int, auto: Boolean): BleStatus = request(MsgType.SET_ACTIVE_FENCES, Requests.setActiveFences(mask, auto), Idempotency.STATE_CHANGING).statusEnum
    suspend fun timeSet(unixMs: Long): BleStatus = request(MsgType.TIME_SET, Requests.timeSet(unixMs), Idempotency.STATE_CHANGING).statusEnum
    suspend fun diag(): Map<String, String> = DiagParser.parse(String(requestOk(MsgType.DIAG_GET, timeoutMs = 5000), Charsets.UTF_8))
    suspend fun blackbox(n: Int): List<BlackboxRecord> = BlackboxRecord.decodeList(requestOk(MsgType.BLACKBOX_READ, Requests.blackbox(n), timeoutMs = 5000))
    suspend fun reboot(force: Boolean): BleStatus = request(MsgType.REBOOT, Requests.reboot(force), Idempotency.STATE_CHANGING).statusEnum

    /** RTCM write (no response). The sequence comes from [org.avoperformance.horse.core.rtcm.RtcmPacer]. */
    suspend fun writeRtcm(seq: Long, data: ByteArray): Boolean {
        rtcmMsgId = (rtcmMsgId + 1) and 0x7FFF
        return t.writeRtcm(Requests.rtcmWrite(seq, data, 0, data.size, rtcmMsgId))
    }
}

enum class AuthOutcome(val texto: String) {
    OK("Autorizado"), UNKNOWN_KEY("El reloj no reconoce este teléfono (vuelve a vincular)"),
    REJECTED("El reloj rechazó la prueba"), LOCKED("Demasiados intentos; espera y reintenta"),
    WATCH_NOT_AUTHENTIC("El reloj no demostró conocer la clave (posible suplantación)"), ERROR("Error de autorización"),
}
