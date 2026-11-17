package org.avoperformance.horse.core

import kotlinx.coroutines.runBlocking
import org.avoperformance.horse.core.auth.WatchAuth
import org.avoperformance.horse.core.auth.WatchCredential
import org.avoperformance.horse.core.ble.AuthOutcome
import org.avoperformance.horse.core.ble.AvoClient
import org.avoperformance.horse.core.ble.AvoGatt
import org.avoperformance.horse.core.ble.AvoTransport
import org.avoperformance.horse.core.ble.BleFlags
import org.avoperformance.horse.core.ble.BleFraming
import org.avoperformance.horse.core.ble.BleMessage
import org.avoperformance.horse.core.ble.BleReassembler
import org.avoperformance.horse.core.ble.BleStatus
import org.avoperformance.horse.core.ble.MsgType
import org.avoperformance.horse.core.ble.SessionCmd
import org.avoperformance.horse.core.ble.WatchSessionState
import org.avoperformance.horse.core.bytes.ByteReader
import org.avoperformance.horse.core.bytes.ByteWriter
import org.avoperformance.horse.core.bytes.Crc
import org.avoperformance.horse.core.sync.SessionDownload
import org.avoperformance.horse.core.telemetry.SessionCommandTracker
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files
import java.util.UUID

/**
 * AvoClient against a simulated watch that follows the firmware behaviour read from
 * ble_service.cpp / storage.cpp (dedup of the last 32 msg_ids, DUPLICATE answer,
 * FILE_DATA on FILE_TX, auth gate). This is a simulation, NOT the real watch:
 * real-hardware tests are listed in PRUEBAS.md as pending.
 */
class ClientProtocolTest {
    class SimWatch(private val att: Int) : AvoTransport {
        lateinit var client: AvoClient
        override val attPayload = att
        private val reasm = BleReassembler()
        private val seen = ArrayDeque<Int>()
        val key = TestRes.hex("vectors_auth.txt", "key")
        val keyId = byteArrayOf(1, 2, 3, 4, 5, 6, 7, 8)
        val devId = "A1B2C3D4E5F6"
        var authorized = false
        var session = WatchSessionState.IDLE
        var executedCommands = 0
        var dropNextResponses = 0
        private var pn = ByteArray(16); private var wn = ByteArray(16)
        val file = TestRes.bytes("sample.avr")
        val rtcmWrites = ArrayList<ByteArray>()

        private fun send(ch: UUID, type: Int, id: Int, status: BleStatus, p: ByteArray = ByteArray(0)) {
            if (dropNextResponses > 0) { dropNextResponses--; return }
            val flags = BleFlags.RESPONSE or (if (status != BleStatus.OK) BleFlags.ERROR else 0)
            val per = att - BleFraming.OVERHEAD
            val cnt = BleFraming.count(p.size, att)
            for (i in 0 until cnt) {
                val off = i * per
                client.onNotification(ch, BleFraming.build(type, id, i, cnt, flags, status.code, p, off, minOf(per, p.size - off)))
            }
        }

        override suspend fun writeRtcm(frag: ByteArray): Boolean { rtcmWrites += frag; return true }

        override suspend fun writeCtrl(frag: ByteArray) {
            val m = reasm.feed(frag) ?: return
            if (seen.contains(m.msgId)) { send(AvoGatt.CTRL_TX, m.type, m.msgId, BleStatus.DUPLICATE); return }
            seen.addLast(m.msgId); if (seen.size > 32) seen.removeFirst()
            handle(m)
        }

        private fun handle(m: BleMessage) {
            val t = MsgType.of(m.type)
            val open = t == MsgType.GET_INFO || t == MsgType.AUTH_HELLO || t == MsgType.AUTH_PROOF || t == MsgType.CLAIM_BEGIN || t == MsgType.CLAIM_RESULT
            if (!authorized && !open) { send(AvoGatt.CTRL_TX, m.type, m.msgId, BleStatus.AUTH_REQUIRED); return }
            val r = ByteReader(m.payload)
            when (t) {
                MsgType.AUTH_HELLO -> {
                    val kid = r.bytes(8); pn = r.bytes(16)
                    if (!kid.contentEquals(keyId)) { send(AvoGatt.CTRL_TX, m.type, m.msgId, BleStatus.NOT_FOUND); return }
                    wn = WatchAuth.nonce()
                    send(AvoGatt.CTRL_TX, m.type, m.msgId, BleStatus.OK, wn + WatchAuth.watchProof(key, pn, wn, devId))
                }
                MsgType.AUTH_PROOF -> {
                    authorized = WatchAuth.same(m.payload, WatchAuth.phoneProof(key, wn, pn, devId))
                    send(AvoGatt.CTRL_TX, m.type, m.msgId, if (authorized) BleStatus.OK else BleStatus.AUTH_REQUIRED)
                }
                MsgType.SESSION_CMD -> {
                    val c = r.u8(); val confirm = r.u8()
                    if (c == SessionCmd.STOP.code && confirm != 1) { send(AvoGatt.CTRL_TX, m.type, m.msgId, BleStatus.NOT_ALLOWED); return }
                    executedCommands++
                    session = when (c) { 1 -> WatchSessionState.RECORDING; 2 -> WatchSessionState.STOPPED_WAITING_UPLOAD; 3 -> WatchSessionState.PAUSED; 4 -> WatchSessionState.RECORDING; else -> session }
                    send(AvoGatt.CTRL_TX, m.type, m.msgId, BleStatus.OK)
                }
                MsgType.READ_FILE -> {
                    r.str(24); val seg = r.u16(); val off = r.u32(); val len = r.u32().toInt()
                    if (seg != 1) { send(AvoGatt.FILE_TX, MsgType.FILE_DATA.code, m.msgId, BleStatus.NOT_FOUND); return }
                    val n = minOf(len, 16384, file.size - off.toInt())
                    val d = file.copyOfRange(off.toInt(), off.toInt() + n)
                    send(AvoGatt.FILE_TX, MsgType.FILE_DATA.code, m.msgId, BleStatus.OK,
                        ByteWriter().u32(off).u32(file.size.toLong()).u32(Crc.crc32(d)).bytes(d).toByteArray())
                }
                else -> send(AvoGatt.CTRL_TX, m.type, m.msgId, BleStatus.UNKNOWN_TYPE)
            }
        }
    }

    private fun setup(att: Int = 244): Pair<SimWatch, AvoClient> {
        val w = SimWatch(att)
        val c = AvoClient(w, {}, startMsgId = 100)
        w.client = c
        return w to c
    }

    @Test fun commandsRejectedBeforeAuthorization(): Unit = runBlocking {
        val (w, c) = setup()
        assertEquals(BleStatus.AUTH_REQUIRED, c.sessionCommand(SessionCmd.START, false))
        assertEquals(0, w.executedCommands)
    }

    @Test fun mutualAuthentication(): Unit = runBlocking {
        val (w, c) = setup()
        assertEquals(AuthOutcome.OK, c.authenticate(WatchCredential(w.devId, w.keyId, w.key)))
        assertTrue(w.authorized)
        val (w2, c2) = setup()
        val wrongKey = w2.key.copyOf().also { it[0] = (it[0] + 1).toByte() }
        // a watch that does not know our key cannot produce a valid proof → detected by the phone
        assertEquals(AuthOutcome.WATCH_NOT_AUTHENTIC, c2.authenticate(WatchCredential(w2.devId, w2.keyId, wrongKey)))
        assertEquals(AuthOutcome.UNKNOWN_KEY, c2.authenticate(WatchCredential(w2.devId, ByteArray(8), w2.key)))
    }

    @Test fun lostResponseDoesNotExecuteCommandTwice(): Unit = runBlocking {
        val (w, c) = setup()
        c.authenticate(WatchCredential(w.devId, w.keyId, w.key))
        val tracker = SessionCommandTracker()
        assertTrue(tracker.begin(SessionCmd.START, 0))
        assertTrue(!tracker.begin(SessionCmd.START, 1))          // double tap ignored
        w.dropNextResponses = 1                                   // response lost over the air
        val st = c.sessionCommand(SessionCmd.START, false)        // client retries with the SAME msg_id
        assertEquals(BleStatus.DUPLICATE, st)
        assertEquals(1, w.executedCommands)
        tracker.onResponse(st, 100, null)
        assertTrue(tracker.state is SessionCommandTracker.State.WaitingTelemetry)
        tracker.onTelemetry(w.session, 500)                       // confirmed only by the watch state
        assertTrue(tracker.state is SessionCommandTracker.State.Confirmed)
        // STOP without confirmation is refused by the watch
        assertEquals(BleStatus.NOT_ALLOWED, c.sessionCommand(SessionCmd.STOP, false))
        assertEquals(BleStatus.OK, c.sessionCommand(SessionCmd.STOP, true))
        assertEquals(WatchSessionState.STOPPED_WAITING_UPLOAD, w.session)
    }

    @Test fun fileDownloadWithLostChunkAndSmallMtu(): Unit = runBlocking {
        val (w, c) = setup(att = 64)      // worst case: no MTU negotiation → many fragments
        c.authenticate(WatchCredential(w.devId, w.keyId, w.key))
        val dir = Files.createTempDirectory("avo_cli").toFile()
        try {
            val d = SessionDownload(dir, "SA1B2_000123_001", 1)
            var pos: Pair<Int, Long>? = d.position()
            var n = 0
            while (pos != null) {
                if (n++ == 1) w.dropNextResponses = 1             // one chunk response lost → retried with a new msg_id
                val ch = c.readChunk("SA1B2_000123_001", pos.first, pos.second) ?: break
                pos = d.append(pos.first, pos.second, ch.data, ch.fileSize)
            }
            assertArrayEquals(w.file, d.segFile(1).readBytes())
            assertTrue(c.stats.retries >= 1)
            assertEquals(null, c.readChunk("SA1B2_000123_001", 2, 0))   // end of segments
        } finally { dir.deleteRecursively() }
    }

    @Test fun rtcmWritesCarrySequence(): Unit = runBlocking {
        val (w, c) = setup()
        c.writeRtcm(41, byteArrayOf(0xD3.toByte(), 0, 0, 0, 0, 0))
        val f = BleFraming.parse(w.rtcmWrites.single())!!
        assertEquals(MsgType.RTCM.code, f.type)
        assertEquals(41L, ByteReader(f.payload).u32())
        assertEquals(0, f.flags)
    }
}
