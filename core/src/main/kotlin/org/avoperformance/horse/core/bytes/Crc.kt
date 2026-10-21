package org.avoperformance.horse.core.bytes

import java.util.zip.CRC32

/** CRC functions identical to avo_crc.cpp in the watch firmware. */
object Crc {
    /** CRC-16/CCITT-FALSE: poly 0x1021, init 0xFFFF. check("123456789") = 0x29B1 */
    fun crc16(d: ByteArray, off: Int = 0, len: Int = d.size - off): Int {
        var crc = 0xFFFF
        for (i in off until off + len) {
            crc = crc xor ((d[i].toInt() and 0xFF) shl 8)
            for (b in 0 until 8) crc = if (crc and 0x8000 != 0) ((crc shl 1) xor 0x1021) and 0xFFFF else (crc shl 1) and 0xFFFF
        }
        return crc
    }

    /** CRC-32/ISO-HDLC (zlib). check("123456789") = 0xCBF43926 */
    fun crc32(d: ByteArray, off: Int = 0, len: Int = d.size - off): Long {
        val c = CRC32(); c.update(d, off, len); return c.value
    }

    /** CRC-8/SMBUS: poly 0x07, init 0. check = 0xF4 */
    fun crc8(d: ByteArray, off: Int = 0, len: Int = d.size - off): Int {
        var crc = 0
        for (i in off until off + len) {
            crc = crc xor (d[i].toInt() and 0xFF)
            for (b in 0 until 8) crc = if (crc and 0x80 != 0) ((crc shl 1) xor 0x07) and 0xFF else (crc shl 1) and 0xFF
        }
        return crc
    }

    /** CRC-24Q (RTCM 3). check = 0xCDE703 */
    fun crc24q(d: ByteArray, off: Int = 0, len: Int = d.size - off): Int {
        var crc = 0
        for (i in off until off + len) {
            crc = crc xor ((d[i].toInt() and 0xFF) shl 16)
            for (b in 0 until 8) {
                crc = crc shl 1
                if (crc and 0x1000000 != 0) crc = crc xor 0x1864CFB
            }
        }
        return crc and 0xFFFFFF
    }
}
