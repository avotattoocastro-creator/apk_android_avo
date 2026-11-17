package org.avoperformance.horse.core.license

import org.avoperformance.horse.core.identity.AvoUserCard
import java.nio.ByteBuffer
import java.security.MessageDigest

/**
 * «Activar móvil por NFC»: the phone with AVO Tarjetas emulates a card (Android Host Card Emulation, ISO 14443-4 /
 * ISO 7816 APDUs) and the user's phone with the AVO app reads it, like a physical card, but the licence it receives
 * is signed at that moment FOR THAT PHONE: [LicenseToken.uid] = [deviceId] of the reader and
 * [LicenseToken.FLAG_DEVICE] set. Copying it to another phone or to a card does not work.
 *
 * Protocol (proprietary AID [AID], short APDUs):
 *
 *   1. SELECT by AID                    → "AVOA" | ver | armed(0/1)                            9000
 *   2. ACTIVATE  80 10 00 00 Lc data     data = ver | idLen | deviceId                          → total(u16) 9000
 *                                        (6985 = AVO Tarjetas is not waiting to activate a phone)
 *   3. READ      80 12 hi lo Le          bytes [offset, offset+Le) of the result                → chunk 9000
 *
 *   result = "AVOA" | ver | uriLen(u16) | user card URI (UTF-8, with its secret) | tokenLen(u16) | token
 *
 * The user card (code, name and secret) also travels, so the phone gets the identity of the user exactly as when
 * their card is tapped (needed for licence files and sharing). NFC range is a few centimetres and AVO Tarjetas only
 * answers while the issuer has pressed «Activar móvil por NFC» for that user (and the screen is unlocked).
 */
object NfcActivation {
    /** Proprietary AID (F0 = proprietary range): "AVOLIC" 01. Also declared in cards/res/xml/avo_hce_service.xml. */
    val AID: ByteArray = hex("F041564F4C494301")
    val MAGIC: ByteArray = "AVOA".toByteArray(Charsets.US_ASCII)
    const val VERSION = 1
    const val INS_ACTIVATE: Byte = 0x10
    const val INS_READ: Byte = 0x12
    const val CLA: Byte = 0x80.toByte()
    /** Bytes of the device id put in the licence UID field. */
    const val DEVICE_ID_LEN = 10
    const val MAX_CHUNK = 240

    val SW_OK = byteArrayOf(0x90.toByte(), 0x00)
    val SW_NOT_ARMED = byteArrayOf(0x69, 0x85.toByte())
    val SW_WRONG_LENGTH = byteArrayOf(0x67, 0x00)
    val SW_NOT_FOUND = byteArrayOf(0x6A, 0x82.toByte())
    val SW_INS = byteArrayOf(0x6D, 0x00)
    val SW_CLA = byteArrayOf(0x6E, 0x00)
    val SW_ERROR = byteArrayOf(0x6F, 0x00)

    /**
     * Id of a phone for device licences: SHA-256 of the Android id of the app (stable for this phone, user and
     * signing key, also after reinstalling) and the package, first [DEVICE_ID_LEN] bytes.
     */
    fun deviceId(androidId: String, packageName: String): ByteArray =
        MessageDigest.getInstance("SHA-256").digest("AVO-DEVICE/1\u0000$packageName\u0000$androidId".toByteArray(Charsets.UTF_8))
            .copyOf(DEVICE_ID_LEN)

    fun selectApdu(): ByteArray = byteArrayOf(0x00, 0xA4.toByte(), 0x04, 0x00, AID.size.toByte()) + AID + byteArrayOf(0x00)

    fun activateApdu(deviceId: ByteArray): ByteArray {
        require(deviceId.size in 1..LicenseToken.MAX_UID) { "Id de móvil no válido" }
        val data = byteArrayOf(VERSION.toByte(), deviceId.size.toByte()) + deviceId
        return byteArrayOf(CLA, INS_ACTIVATE, 0, 0, data.size.toByte()) + data + byteArrayOf(0x00)
    }

    fun readApdu(offset: Int, length: Int): ByteArray =
        byteArrayOf(CLA, INS_READ, (offset shr 8).toByte(), offset.toByte(), length.toByte())

    /** Result sent to the phone: the user card and the licence signed for it. */
    data class Result(val card: AvoUserCard, val token: ByteArray) {
        fun encode(): ByteArray {
            val uri = card.toUri().toByteArray(Charsets.UTF_8)
            return ByteBuffer.allocate(4 + 1 + 2 + uri.size + 2 + token.size).apply {
                put(MAGIC); put(VERSION.toByte()); putShort(uri.size.toShort()); put(uri); putShort(token.size.toShort()); put(token)
            }.array()
        }

        override fun equals(other: Any?) = other is Result && card == other.card && token.contentEquals(other.token)
        override fun hashCode() = card.hashCode() * 31 + token.contentHashCode()

        companion object {
            fun decode(b: ByteArray): Result {
                require(b.size > 9) { "Respuesta incompleta" }
                val bb = ByteBuffer.wrap(b)
                require(ByteArray(4).also(bb::get).contentEquals(MAGIC)) { "No es una respuesta de AVO Tarjetas" }
                require(bb.get().toInt() == VERSION) { "Versión de AVO Tarjetas no compatible: actualiza las apps" }
                val ul = bb.short.toInt() and 0xFFFF
                require(ul in 1..bb.remaining() - 2) { "Respuesta dañada" }
                val uri = String(ByteArray(ul).also(bb::get), Charsets.UTF_8)
                val tl = bb.short.toInt() and 0xFFFF
                require(tl == bb.remaining() && tl > 0) { "Respuesta dañada" }
                return Result(AvoUserCard.parse(uri), ByteArray(tl).also(bb::get))
            }
        }
    }

    /**
     * Card side (AVO Tarjetas, HostApduService). [issue] is called once per ACTIVATE with the reader's device id;
     * it returns the result, or null when no activation is armed. Stateless apart from the last result (READ).
     */
    class Card(private val issue: (deviceId: ByteArray) -> Result?, private val armed: () -> Boolean) {
        private var selected = false
        private var pending: ByteArray? = null

        fun deselect() { selected = false; pending = null }

        fun process(apdu: ByteArray): ByteArray = try { handle(apdu) } catch (e: Exception) { SW_ERROR }

        private fun handle(a: ByteArray): ByteArray {
            if (a.size < 4) return SW_WRONG_LENGTH
            val cla = a[0]; val ins = a[1]
            if (cla == 0x00.toByte() && ins == 0xA4.toByte() && a[2] == 0x04.toByte()) {
                if (a.size < 5) return SW_WRONG_LENGTH
                val lc = a[4].toInt() and 0xFF
                if (a.size < 5 + lc) return SW_WRONG_LENGTH
                if (!a.copyOfRange(5, 5 + lc).contentEquals(AID)) { selected = false; return SW_NOT_FOUND }
                selected = true; pending = null
                return MAGIC + byteArrayOf(VERSION.toByte(), if (armed()) 1 else 0) + SW_OK
            }
            if (!selected) return SW_NOT_FOUND
            if (cla != CLA) return SW_CLA
            return when (ins) {
                INS_ACTIVATE -> {
                    if (a.size < 5) return SW_WRONG_LENGTH
                    val lc = a[4].toInt() and 0xFF
                    if (a.size < 5 + lc || lc < 3) return SW_WRONG_LENGTH
                    val d = a.copyOfRange(5, 5 + lc)
                    if (d[0].toInt() != VERSION) return SW_ERROR
                    val n = d[1].toInt() and 0xFF
                    if (n !in 1..LicenseToken.MAX_UID || d.size != 2 + n) return SW_WRONG_LENGTH
                    val r = issue(d.copyOfRange(2, 2 + n)) ?: return SW_NOT_ARMED
                    val bytes = r.encode()
                    pending = bytes
                    byteArrayOf((bytes.size shr 8).toByte(), bytes.size.toByte()) + SW_OK
                }
                INS_READ -> {
                    val p = pending ?: return SW_NOT_ARMED
                    val off = ((a[2].toInt() and 0xFF) shl 8) or (a[3].toInt() and 0xFF)
                    var le = if (a.size >= 5) a[4].toInt() and 0xFF else MAX_CHUNK
                    if (le == 0) le = 256
                    if (off > p.size) return SW_WRONG_LENGTH
                    p.copyOfRange(off, minOf(p.size, off + minOf(le, MAX_CHUNK))) + SW_OK
                }
                else -> SW_INS
            }
        }
    }

    /** What the reader learnt from the other phone. */
    sealed interface Outcome {
        /** The tapped device is not AVO Tarjetas (any other NFC phone / card): ignore silently. */
        data object NotAvo : Outcome
        /** AVO Tarjetas is there but the issuer has not pressed «Activar móvil por NFC». */
        data object NotArmed : Outcome
        data class Received(val result: Result) : Outcome
        data class Failed(val reason: String) : Outcome
    }

    /** Reader side (AVO app): runs the exchange over [transceive] (IsoDep). */
    fun read(transceive: (ByteArray) -> ByteArray, deviceId: ByteArray): Outcome {
        val sel = runCatching { transceive(selectApdu()) }.getOrElse { return Outcome.NotAvo }
        if (sel.size < 2 || !sel.takeLast(2).toByteArray().contentEquals(SW_OK) || sel.size < 4 + 2 + 2 ||
            !sel.copyOfRange(0, 4).contentEquals(MAGIC)) return Outcome.NotAvo
        if (sel[4].toInt() != VERSION) return Outcome.Failed("Versión de AVO Tarjetas no compatible: actualiza las dos apps")
        val act = runCatching { transceive(activateApdu(deviceId)) }.getOrElse { return Outcome.Failed("Se perdió el contacto NFC: vuelve a juntar los móviles") }
        val sw = act.takeLast(2).toByteArray()
        if (sw.contentEquals(SW_NOT_ARMED)) return Outcome.NotArmed
        if (!sw.contentEquals(SW_OK) || act.size != 4) return Outcome.Failed("AVO Tarjetas no pudo emitir la licencia")
        val total = ((act[0].toInt() and 0xFF) shl 8) or (act[1].toInt() and 0xFF)
        if (total !in 10..4096) return Outcome.Failed("Respuesta dañada")
        val out = java.io.ByteArrayOutputStream(total)
        while (out.size() < total) {
            val r = runCatching { transceive(readApdu(out.size(), minOf(MAX_CHUNK, total - out.size()))) }
                .getOrElse { return Outcome.Failed("Se perdió el contacto NFC: vuelve a juntar los móviles") }
            if (r.size < 3 || !r.takeLast(2).toByteArray().contentEquals(SW_OK)) return Outcome.Failed("Lectura NFC incompleta")
            out.write(r, 0, r.size - 2)
        }
        return try { Outcome.Received(Result.decode(out.toByteArray())) } catch (e: IllegalArgumentException) {
            Outcome.Failed(e.message ?: "Respuesta dañada")
        }
    }

    private fun hex(s: String) = ByteArray(s.length / 2) { s.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
}
