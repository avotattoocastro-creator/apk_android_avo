package org.avoperformance.horse.core.license

import org.avoperformance.horse.core.identity.AvoUserCard
import java.nio.ByteBuffer

/**
 * AVO app licence carried by the user's NFC card (NDEF external record `avoperformance.org:lic`).
 *
 * Binary layout v1 (big-endian), 107 bytes with a 7-byte UID:
 *
 *   "AVOL" | ver=1 | keyId(4) | uidLen(1) | uid(1..10) | userCode(13 ASCII) |
 *   issuedAt(u32 s) | expiresAt(u32 s) | serial(4) | flags(1) | signature(64, ECDSA P-256 r||s)
 *
 * The signature covers [DOMAIN] + every byte before it, so changing the date, the user or the UID
 * invalidates it. The UID ties the licence to one physical card: copying the record to another
 * ordinary card does not work (a "magic" card with a writable UID can still clone it — limitation
 * accepted with the NTAG21x cards; NTAG 424 DNA would be needed to stop that).
 *
 * [expiresAtS] is exclusive: the licence is valid while `now < expiresAt` (the issuer sets it to
 * 00:00 of the day after the chosen date, so "activa hasta el 31/12" includes the whole 31st).
 */
class LicenseToken(
    val keyId: ByteArray,
    val uid: ByteArray,
    val userCode: String,
    val issuedAtS: Long,
    val expiresAtS: Long,
    val serial: ByteArray,
    val flags: Int,
    val signature: ByteArray,
) {
    init {
        require(keyId.size == 4) { "keyId" }
        require(uid.size in 1..MAX_UID) { "UID de tarjeta no válido" }
        require(AvoUserCard.CODE.matches(userCode)) { "Código de usuario no válido" }
        require(issuedAtS in 0..U32_MAX && expiresAtS in 0..U32_MAX) { "Fecha fuera de rango" }
        require(expiresAtS > issuedAtS) { "La caducidad es anterior a la emisión" }
        require(serial.size == 4) { "serial" }
        require(flags in 0..255) { "flags" }
        require(signature.size == 64) { "firma" }
    }

    val expiresAtMs: Long get() = expiresAtS * 1000
    /** Licence delivered as a file (email/WhatsApp) instead of written on the card. */
    val isRemote: Boolean get() = flags and FLAG_REMOTE != 0
    val issuedAtMs: Long get() = issuedAtS * 1000

    /** Bytes covered by the signature (domain-separated). */
    fun signedBytes(): ByteArray = DOMAIN + body()

    fun encode(): ByteArray = body() + signature

    private fun body(): ByteArray = ByteBuffer.allocate(HEADER + uid.size + 13 + 4 + 4 + 4 + 1).apply {
        put(MAGIC); put(VERSION.toByte()); put(keyId); put(uid.size.toByte()); put(uid)
        put(userCode.toByteArray(Charsets.US_ASCII))
        putInt(issuedAtS.toInt()); putInt(expiresAtS.toInt()); put(serial); put(flags.toByte())
    }.array()

    fun withSignature(sig: ByteArray) = LicenseToken(keyId, uid, userCode, issuedAtS, expiresAtS, serial, flags, sig)

    override fun equals(other: Any?) = other is LicenseToken && encode().contentEquals(other.encode())
    override fun hashCode() = encode().contentHashCode()
    override fun toString() = "LicenseToken($userCode, uid=${uid.hex()}, expires=$expiresAtS, key=${keyId.hex()})"

    companion object {
        val DOMAIN = "AVO-LICENSE/1\u0000".toByteArray(Charsets.US_ASCII)
        val MAGIC = byteArrayOf('A'.code.toByte(), 'V'.code.toByte(), 'O'.code.toByte(), 'L'.code.toByte())
        const val VERSION = 1
        const val FLAG_REMOTE = 0x01
        const val MAX_UID = 10
        const val NDEF_DOMAIN = "avoperformance.org"
        const val NDEF_TYPE = "lic"
        /** Full external type as Android reports it (`domain:type`, lower case). */
        const val NDEF_EXTERNAL_TYPE = "$NDEF_DOMAIN:$NDEF_TYPE"
        private const val HEADER = 4 + 1 + 4 + 1
        private const val U32_MAX = 0xFFFF_FFFFL

        fun decode(bytes: ByteArray): LicenseToken {
            require(bytes.size >= HEADER + 1 + 13 + 13 + 64) { "Licencia incompleta" }
            val b = ByteBuffer.wrap(bytes)
            val magic = ByteArray(4).also(b::get)
            require(magic.contentEquals(MAGIC)) { "No es una licencia AVO" }
            val ver = b.get().toInt() and 0xFF
            require(ver == VERSION) { "Versión de licencia no compatible ($ver)" }
            val keyId = ByteArray(4).also(b::get)
            val uidLen = b.get().toInt() and 0xFF
            require(uidLen in 1..MAX_UID) { "UID de tarjeta no válido" }
            require(bytes.size == HEADER + uidLen + 13 + 13 + 64) { "Longitud de licencia incorrecta" }
            val uid = ByteArray(uidLen).also(b::get)
            val code = String(ByteArray(13).also(b::get), Charsets.US_ASCII)
            val issued = b.int.toLong() and U32_MAX
            val expires = b.int.toLong() and U32_MAX
            val serial = ByteArray(4).also(b::get)
            val flags = b.get().toInt() and 0xFF
            val sig = ByteArray(64).also(b::get)
            return LicenseToken(keyId, uid, code, issued, expires, serial, flags, sig)
        }

        /** Unsigned token, ready to be signed by [LicenseCrypto.sign]. */
        fun unsigned(keyId: ByteArray, uid: ByteArray, userCode: String, issuedAtS: Long, expiresAtS: Long, serial: ByteArray, flags: Int = 0) =
            LicenseToken(keyId, uid, userCode, issuedAtS, expiresAtS, serial, flags, ByteArray(64))
    }
}

internal fun ByteArray.hex(): String = joinToString("") { "%02X".format(it) }
