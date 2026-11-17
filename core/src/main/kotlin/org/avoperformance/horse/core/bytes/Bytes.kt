package org.avoperformance.horse.core.bytes

/**
 * Little-endian, field-by-field (de)serialisation, mirroring avo_bytes.h of the
 * watch firmware. All AVO binary formats are little-endian with no padding.
 */
class ByteWriter(initial: Int = 64) {
    private var buf = ByteArray(initial)
    var size = 0
        private set

    private fun ensure(k: Int) {
        if (size + k > buf.size) buf = buf.copyOf(maxOf(buf.size * 2, size + k))
    }

    fun u8(v: Int): ByteWriter { ensure(1); buf[size++] = v.toByte(); return this }
    fun i8(v: Int): ByteWriter = u8(v)
    fun u16(v: Int): ByteWriter { ensure(2); buf[size++] = v.toByte(); buf[size++] = (v ushr 8).toByte(); return this }
    fun u32(v: Long): ByteWriter {
        ensure(4)
        for (i in 0 until 4) buf[size++] = (v ushr (8 * i)).toByte()
        return this
    }
    fun i32(v: Int): ByteWriter = u32(v.toLong() and 0xFFFFFFFFL)
    fun u64(v: Long): ByteWriter {
        ensure(8)
        for (i in 0 until 8) buf[size++] = (v ushr (8 * i)).toByte()
        return this
    }
    fun bytes(d: ByteArray, off: Int = 0, len: Int = d.size - off): ByteWriter {
        ensure(len); System.arraycopy(d, off, buf, size, len); size += len; return this
    }
    /** Fixed-width, zero padded, always NUL terminated inside (UTF-8, truncated on byte boundary). */
    fun str(s: String?, width: Int): ByteWriter {
        ensure(width)
        val b = (s ?: "").toByteArray(Charsets.UTF_8)
        var l = minOf(b.size, width - 1)
        // never cut a UTF-8 multi-byte sequence in half
        while (l > 0 && l < b.size && (b[l].toInt() and 0xC0) == 0x80) l--
        System.arraycopy(b, 0, buf, size, l)
        for (i in l until width) buf[size + i] = 0
        size += width
        return this
    }
    fun toByteArray(): ByteArray = buf.copyOf(size)
}

class ByteReader(private val b: ByteArray, private val start: Int = 0, private val end: Int = b.size) {
    var pos = start
        private set
    var ok = true
        private set

    val remaining: Int get() = if (ok) end - pos else 0

    private fun room(k: Int): Boolean {
        if (!ok || pos + k > end) { ok = false; return false }
        return true
    }

    fun u8(): Int = if (room(1)) b[pos++].toInt() and 0xFF else 0
    fun i8(): Int = if (room(1)) b[pos++].toInt() else 0
    fun u16(): Int {
        if (!room(2)) return 0
        val v = (b[pos].toInt() and 0xFF) or ((b[pos + 1].toInt() and 0xFF) shl 8)
        pos += 2; return v
    }
    fun u32(): Long {
        if (!room(4)) return 0
        var v = 0L
        for (i in 0 until 4) v = v or ((b[pos + i].toLong() and 0xFF) shl (8 * i))
        pos += 4; return v
    }
    fun i32(): Int = u32().toInt()
    fun u64(): Long {
        if (!room(8)) return 0
        var v = 0L
        for (i in 0 until 8) v = v or ((b[pos + i].toLong() and 0xFF) shl (8 * i))
        pos += 8; return v
    }
    fun bytes(n: Int): ByteArray {
        if (!room(n)) return ByteArray(n)
        val r = b.copyOfRange(pos, pos + n); pos += n; return r
    }
    fun str(width: Int): String {
        if (!room(width)) return ""
        var l = 0
        while (l < width && b[pos + l].toInt() != 0) l++
        val s = String(b, pos, l, Charsets.UTF_8)
        pos += width
        return s
    }
    fun skip(n: Int) { if (room(n)) pos += n }
    fun rest(): ByteArray = if (ok) b.copyOfRange(pos, end).also { pos = end } else ByteArray(0)
}

fun leU16(b: ByteArray, off: Int): Int = (b[off].toInt() and 0xFF) or ((b[off + 1].toInt() and 0xFF) shl 8)
fun leU32(b: ByteArray, off: Int): Long {
    var v = 0L
    for (i in 0 until 4) v = v or ((b[off + i].toLong() and 0xFF) shl (8 * i))
    return v
}
fun leU64(b: ByteArray, off: Int): Long {
    var v = 0L
    for (i in 0 until 8) v = v or ((b[off + i].toLong() and 0xFF) shl (8 * i))
    return v
}
fun putLeU32(b: ByteArray, off: Int, v: Long) { for (i in 0 until 4) b[off + i] = (v ushr (8 * i)).toByte() }

fun ByteArray.toHex(): String {
    val h = "0123456789abcdef"
    val sb = StringBuilder(size * 2)
    for (x in this) { sb.append(h[(x.toInt() shr 4) and 15]); sb.append(h[x.toInt() and 15]) }
    return sb.toString()
}
fun String.hexToBytes(): ByteArray {
    val s = trim()
    require(s.length % 2 == 0) { "odd hex length" }
    return ByteArray(s.length / 2) { i -> s.substring(2 * i, 2 * i + 2).toInt(16).toByte() }
}
