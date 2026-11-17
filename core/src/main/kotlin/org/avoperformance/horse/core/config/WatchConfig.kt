package org.avoperformance.horse.core.config

import org.avoperformance.horse.core.bytes.ByteReader
import org.avoperformance.horse.core.bytes.ByteWriter
import org.avoperformance.horse.core.bytes.Crc
import org.avoperformance.horse.core.bytes.leU16
import org.avoperformance.horse.core.bytes.leU32
import org.avoperformance.horse.core.geo.Fence
import org.avoperformance.horse.core.geo.FenceType

/**
 * AVO CONFIG SCHEMA v1 — byte-exact Kotlin port of avo_config.cpp.
 * "AVOC" | u16 schema | u16 0 | u32 body_len | TLV sections | u32 CRC-32.
 * The app always edits the configuration read from the watch (GET_CONFIG),
 * changes only the fields the user touched and writes it back (SET_CONFIG),
 * so fields this app version does not know are preserved.
 */
enum class ExitAction(val code: Int, val texto: String) {
    STOP_AND_SAVE(0, "Finalizar y guardar"), PAUSE(1, "Pausar y reanudar"), CONTINUE(2, "Continuar grabando");
    companion object { fun of(v: Int) = values().firstOrNull { it.code == v } ?: STOP_AND_SAVE }
}

data class VirtualLine(val enabled: Boolean = false, val aLatE7: Int = 0, val aLonE7: Int = 0, val bLatE7: Int = 0, val bLonE7: Int = 0)

data class WatchConfig(
    val schema: Int = SCHEMA,
    val deviceName: String = "AVO-CHEST",
    val horseId: Long = 0, val horseName: String = "",
    val riderId: Long = 0, val riderName: String = "",
    val autoEnabled: Boolean = true,
    val activeMask: Int = 0x01,
    val entryConfirmS: Int = 5, val exitConfirmS: Int = 15,
    val entryMarginCm: Long = 500, val exitMarginCm: Long = 1500,
    val hAccMaxCm: Long = 1000, val uncertaintyKx100: Int = 100,
    val exitAction: ExitAction = ExitAction.STOP_AND_SAVE,
    val preS: Int = 30, val postS: Int = 15,
    val rearmTimeoutS: Int = 0, val gnssLossMs: Int = 3000, val resumeWindowS: Int = 300,
    val fences: List<Fence?> = List(MAX_FENCES) { null },   // index = slot
    val fenceCount: Int = 0,
    val brightness: Int = 180, val screenTimeoutS: Int = 30, val dimOnLowBatt: Boolean = true,
    val flushMs: Int = 1000, val fsyncMs: Int = 2000, val segmentMb: Int = 512, val nominalRateBps: Long = 32000,
    val bleRequireBond: Boolean = true,
    val seriesSpeedCms: Int = 400, val seriesMinS: Int = 10,
    val lines: List<VirtualLine> = List(4) { VirtualLine() },
    val uartBaud: Long = 921600,
    val lowBattPct: Int = 15, val criticalBattPct: Int = 5, val criticalBattMv: Int = 3450,
    val unknownSections: List<Pair<Int, ByteArray>> = emptyList(),
) {
    companion object {
        const val SCHEMA = 1
        const val MAX_FENCES = 8
        const val MAX_VERTICES = 24
        private const val T_IDENTITY = 1; private const val T_GEOPARAM = 2; private const val T_FENCE = 3
        private const val T_DISPLAY = 4; private const val T_RECORDING = 5; private const val T_BLE = 6
        private const val T_TRAINING = 7; private const val T_LINE = 8; private const val T_UART = 9; private const val T_POWER = 10
        private val KNOWN = setOf(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)

        sealed class Result {
            data class Ok(val config: WatchConfig, val migrated: Boolean, val newerSchema: Boolean) : Result()
            data class Error(val reason: String) : Result()
        }

        fun decode(p: ByteArray): Result {
            if (p.size < 16) return Result.Error("demasiado corto")
            if (String(p, 0, 4, Charsets.US_ASCII) != "AVOC") return Result.Error("magic incorrecto")
            val schema = leU16(p, 4)
            val body = leU32(p, 8).toInt()
            if (body + 16 != p.size) return Result.Error("longitud incorrecta")
            if (Crc.crc32(p, 0, p.size - 4) != leU32(p, p.size - 4)) return Result.Error("CRC incorrecto")
            var c = WatchConfig()
            val fences = MutableList<Fence?>(MAX_FENCES) { null }
            val lines = MutableList(4) { VirtualLine() }
            val unknown = ArrayList<Pair<Int, ByteArray>>()
            val r = ByteReader(p, 12, 12 + body)
            while (r.remaining >= 4) {
                val tag = r.u16()
                val len = r.u16()
                if (len > r.remaining) break
                val start = r.pos
                val sec = r.bytes(len)
                val s = ByteReader(sec)
                when (tag) {
                    T_IDENTITY -> if (len >= 76) c = c.copy(deviceName = s.str(20), horseId = s.u32(), horseName = s.str(24), riderId = s.u32(), riderName = s.str(24))
                    T_GEOPARAM -> if (len >= 30) c = c.copy(
                        autoEnabled = s.u8() != 0, activeMask = s.u8(), entryConfirmS = s.u16(), exitConfirmS = s.u16(),
                        entryMarginCm = s.u32(), exitMarginCm = s.u32(), hAccMaxCm = s.u32(), uncertaintyKx100 = s.u16(),
                        exitAction = ExitAction.of(s.u8()), preS = s.u8(), postS = s.u8(), rearmTimeoutS = s.u16(),
                        gnssLossMs = s.u16(), resumeWindowS = s.u16(), fenceCount = s.u8())
                    T_FENCE -> {
                        val idx = s.u8()
                        val f = Fence.decodeBody(s)
                        if (idx < MAX_FENCES && f != null) fences[idx] = f
                    }
                    T_DISPLAY -> if (len >= 4) c = c.copy(brightness = s.u8(), screenTimeoutS = s.u16(), dimOnLowBatt = s.u8() != 0)
                    T_RECORDING -> if (len >= 10) c = c.copy(flushMs = s.u16(), fsyncMs = s.u16(), segmentMb = s.u16(), nominalRateBps = s.u32())
                    T_BLE -> if (len >= 1) c = c.copy(bleRequireBond = s.u8() != 0)
                    T_TRAINING -> if (len >= 4) c = c.copy(seriesSpeedCms = s.u16(), seriesMinS = s.u16())
                    T_LINE -> {
                        val i = s.u8()
                        if (i < 4 && s.remaining >= 17) lines[i] = VirtualLine(s.u8() != 0, s.i32(), s.i32(), s.i32(), s.i32())
                    }
                    T_UART -> if (len >= 4) c = c.copy(uartBaud = s.u32())
                    T_POWER -> if (len >= 4) c = c.copy(lowBattPct = s.u8(), criticalBattPct = s.u8(), criticalBattMv = s.u16())
                    else -> unknown += tag to sec
                }
                check(r.pos == start + len)
            }
            c = c.copy(fences = fences, lines = lines, unknownSections = unknown, schema = SCHEMA)
            return Result.Ok(c, (schema < SCHEMA), (schema > SCHEMA))
        }
    }

    fun encode(): ByteArray {
        val w = ByteWriter(1024)
        w.bytes("AVOC".toByteArray(Charsets.US_ASCII)).u16(SCHEMA).u16(0).u32(0)
        fun section(tag: Int, body: ByteWriter.() -> Unit) {
            val b = ByteWriter(64).apply(body).toByteArray()
            w.u16(tag).u16(b.size).bytes(b)
        }
        section(T_IDENTITY) { str(deviceName, 20); u32(horseId); str(horseName, 24); u32(riderId); str(riderName, 24) }
        section(T_GEOPARAM) {
            u8(if (autoEnabled) 1 else 0); u8(activeMask); u16(entryConfirmS); u16(exitConfirmS); u32(entryMarginCm); u32(exitMarginCm)
            u32(hAccMaxCm); u16(uncertaintyKx100); u8(exitAction.code); u8(preS); u8(postS); u16(rearmTimeoutS); u16(gnssLossMs)
            u16(resumeWindowS); u8(fenceCount)
        }
        for (i in 0 until minOf(fenceCount, MAX_FENCES)) {
            val f = fences.getOrNull(i) ?: Fence.empty(i)
            section(T_FENCE) { u8(i); f.encodeBody(this) }
        }
        section(T_DISPLAY) { u8(brightness); u16(screenTimeoutS); u8(if (dimOnLowBatt) 1 else 0) }
        section(T_RECORDING) { u16(flushMs); u16(fsyncMs); u16(segmentMb); u32(nominalRateBps) }
        section(T_BLE) { u8(if (bleRequireBond) 1 else 0) }
        section(T_TRAINING) { u16(seriesSpeedCms); u16(seriesMinS) }
        for (i in 0 until 4) {
            val l = lines.getOrElse(i) { VirtualLine() }
            section(T_LINE) { u8(i); u8(if (l.enabled) 1 else 0); i32(l.aLatE7); i32(l.aLonE7); i32(l.bLatE7); i32(l.bLonE7) }
        }
        section(T_UART) { u32(uartBaud) }
        section(T_POWER) { u8(lowBattPct); u8(criticalBattPct); u16(criticalBattMv) }
        for ((tag, b) in unknownSections) if (tag !in KNOWN) { w.u16(tag).u16(b.size).bytes(b) }
        val raw = w.toByteArray()
        val bodyLen = raw.size - 12
        for (i in 0 until 4) raw[8 + i] = (bodyLen ushr (8 * i)).toByte()
        return ByteWriter(raw.size + 4).bytes(raw).u32(Crc.crc32(raw)).toByteArray()
    }

    /** Same ranges as config_validate() in the firmware; returns a list of problems in Spanish. */
    fun problems(): List<String> {
        val p = ArrayList<String>()
        if (entryConfirmS !in 0..60) p += "Tiempo de entrada fuera de 0–60 s"
        if (exitConfirmS !in 0..120) p += "Tiempo de salida fuera de 0–120 s"
        if (entryMarginCm !in 0..10000) p += "Margen de entrada fuera de 0–100 m"
        if (exitMarginCm !in 0..10000) p += "Margen de salida fuera de 0–100 m"
        if (hAccMaxCm !in 50..5000) p += "Precisión mínima fuera de 0,5–50 m"
        if (preS !in 0..60) p += "Pre-grabación fuera de 0–60 s"
        if (postS !in 0..60) p += "Post-grabación fuera de 0–60 s"
        if (brightness !in 10..255) p += "Brillo fuera de 10–255"
        if (uartBaud !in setOf(115200L, 230400L, 460800L, 921600L)) p += "Velocidad UART no admitida"
        if (deviceName.toByteArray().size > 19) p += "Nombre del dispositivo demasiado largo (máx. 19 bytes)"
        if (horseName.toByteArray().size > 23) p += "Identificador de caballo demasiado largo (máx. 23 bytes)"
        if (riderName.toByteArray().size > 23) p += "Identificador de jinete demasiado largo (máx. 23 bytes)"
        return p
    }

    fun withFence(slot: Int, f: Fence?): WatchConfig {
        require(slot in 0 until MAX_FENCES)
        val l = fences.toMutableList().also { while (it.size < MAX_FENCES) it += null }
        l[slot] = f?.copy(id = slot)
        val count = maxOf(fenceCount, if (f != null && f.type != FenceType.NONE) slot + 1 else 0)
        return copy(fences = l, fenceCount = count)
    }
}
