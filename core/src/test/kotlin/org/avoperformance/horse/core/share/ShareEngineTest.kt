package org.avoperformance.horse.core.share

import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import kotlin.random.Random

/** In-memory server with fault injection (simulates network loss after N operations). */
class FakeServer {
    val grants = HashMap<Pair<String, String>, GrantState>() // (recipient, sender)
    val metas = HashMap<String, TransferMeta>()
    val chunks = HashMap<String, HashMap<Int, ByteArray>>()
    val complete = HashSet<String>()
    val allowed = HashMap<String, HashSet<String>>()
    val inboxes = HashMap<String, LinkedHashMap<String, Notice>>()
    val receipts = HashMap<String, HashMap<String, String>>()
    var opsUntilFailure = Int.MAX_VALUE
    var chunkPuts = 0
    var chunkGets = 0

    fun backendFor(user: String) = object : ShareBackend {
        private fun op() { if (opsUntilFailure-- <= 0) throw OfflineException("sin red (simulado)") }
        override suspend fun grant(recipient: String, sender: String) = op().let { grants[recipient to sender] }
        override suspend fun meta(transferId: String) = op().let { metas[transferId] }
        override suspend fun createMeta(m: TransferMeta) { op(); check(m.owner == user); metas.putIfAbsent(m.transferId, m) }
        override suspend fun uploadedChunks(transferId: String): Int { op(); val c = chunks[transferId] ?: return 0; var i = 0; while (c.containsKey(i)) i++; return i }
        override suspend fun putChunk(transferId: String, index: Int, data: ByteArray) { op(); check(metas[transferId]?.owner == user); chunkPuts++; chunks.getOrPut(transferId) { HashMap() }[index] = data }
        override suspend fun getChunk(transferId: String, index: Int): ByteArray? {
            op(); check(user in allowed[transferId].orEmpty()) { "PERMISSION_DENIED" }; chunkGets++; return chunks[transferId]?.get(index)
        }
        override suspend fun markComplete(transferId: String) { op(); complete += transferId }
        override suspend fun isComplete(transferId: String) = op().let { transferId in complete }
        override suspend fun allowRecipient(transferId: String, recipient: String) { op(); allowed.getOrPut(transferId) { HashSet() } += recipient }
        override suspend fun revokeRecipient(transferId: String, recipient: String) { op(); allowed[transferId]?.remove(recipient) }
        override suspend fun notify(recipient: String, n: Notice) {
            op(); check(grants[recipient to user] == GrantState.ACCEPTED) { "PERMISSION_DENIED" }
            inboxes.getOrPut(recipient) { LinkedHashMap() }[n.transferId] = n
        }
        override suspend fun inbox(me: String) = op().let { check(me == user); inboxes[me]?.values?.toList().orEmpty() }
        override suspend fun removeNotice(me: String, transferId: String) { op(); inboxes[me]?.remove(transferId) }
        override suspend fun putReceipt(transferId: String, me: String, value: String) { op(); receipts.getOrPut(transferId) { HashMap() }[me] = value }
        override suspend fun receipts(transferId: String) = op().let { receipts[transferId].orEmpty().toMap() }
        override suspend fun deleteTransfer(transferId: String) { op(); metas.remove(transferId); chunks.remove(transferId); complete.remove(transferId); allowed.remove(transferId); receipts.remove(transferId) }
    }
}

class MemStore : ShareStore {
    val jobs = LinkedHashMap<String, OutJob>()
    val inc = LinkedHashMap<String, InRecord>()
    var up = 0L; var down = 0L
    override fun jobs() = jobs.values.toList()
    override fun upsert(job: OutJob) { jobs[job.key] = job }
    override fun incoming() = inc.values.toList()
    override fun upsertIncoming(r: InRecord) { inc[r.transferId] = r }
    override fun addUsage(uploaded: Long, downloaded: Long) { up += uploaded; down += downloaded }
}

class ShareEngineTest {
    @get:Rule val tmp = TemporaryFolder()

    private val A = Contact("AVO-AAAA-AAAA", "Propietario")
    private val B = Contact("AVO-BBBB-BBBB", "Entrenador")
    private val C = Contact("AVO-CCCC-CCCC", "Veterinario")
    private val D = Contact("AVO-DDDD-DDDD", "Jinete")
    private lateinit var server: FakeServer
    private val sessions = HashMap<String, ByteArray>()
    private val libraries = HashMap<String, HashMap<String, String>>() // user -> sessionId -> sha

    private fun pkgr(dir: File) = object : Packager {
        override suspend fun build(sessionId: String): Packaged {
            val b = sessions[sessionId] ?: error("Entrenamiento no descargado")
            val f = File(dir, "$sessionId.avo").also { it.parentFile.mkdirs(); it.writeBytes(b) }
            return Packaged(f, ShareIds.sha256Hex(b), b.size.toLong(), "LEZAMA DREAMS", "Ana")
        }
    }
    private fun importer(user: String) = object : Importer {
        override suspend fun import(file: File, notice: Notice): Importer.Result {
            val lib = libraries.getOrPut(user) { HashMap() }
            val sha = ShareIds.sha256Hex(file.readBytes())
            val old = lib[notice.sessionId]
            return when {
                old == null -> { lib[notice.sessionId] = sha; Importer.Result.Imported }
                old == sha -> Importer.Result.AlreadyPresent
                else -> Importer.Result.NeedsConfirmation("Versión local distinta")
            }
        }
    }

    private var now = 1_000_000L
    private fun engine(me: Contact, store: ShareStore, limits: ShareLimits = ShareLimits(maxTrainingBytes = 1_500_000, chunkBytes = 16 * 1024)) =
        ShareEngine(me, server.backendFor(me.code), store, pkgr(tmp.root.resolve("out_${me.code}")), importer(me.code), limits, { now }, tmp.root.resolve("in_${me.code}"))

    private fun accept(recipient: Contact, sender: Contact) { server.grants[recipient.code to sender.code] = GrantState.ACCEPTED }

    @Before fun setUp() {
        server = FakeServer()
        sessions["S1"] = Random(1).nextBytes(100_000)
        sessions["S2"] = Random(2).nextBytes(40_000)
    }

    @Test fun threeModesCombinedAndDeduplicated() {
        val targets = RecipientResolver.resolve(A.code, global = listOf(A, B), globalEnabled = true,
            horse = listOf(B, C), horseEnabled = true, manual = listOf(D, B), grants = emptyMap())
        assertEquals(listOf(B.code, C.code, D.code), targets.map { it.contact.code }) // A = me (excluded); B once only
        assertEquals(ShareOrigin.GLOBAL, targets.first { it.contact == B }.origin)
        assertEquals(ShareOrigin.HORSE, targets.first { it.contact == C }.origin)
        assertEquals(ShareOrigin.MANUAL, targets.first { it.contact == D }.origin)
    }

    @Test fun disabledModesAreIgnored() {
        val t = RecipientResolver.resolve(A.code, listOf(B), false, listOf(C), false, emptyList(), emptyMap())
        assertTrue(t.isEmpty())
    }

    @Test fun oneUploadForSeveralRecipientsAndEveryoneReceives() = runBlocking {
        listOf(B, C, D).forEach { accept(it, A) }
        val sa = MemStore()
        val ea = engine(A, sa)
        val targets = RecipientResolver.resolve(A.code, listOf(B), true, listOf(B, C), true, listOf(D), emptyMap())
        assertEquals(3, ea.enqueue("S1", targets, "H1"))
        assertEquals(3, ea.sendPending().sent)
        assertEquals(ShareIds.chunkCount(100_000, 16 * 1024), server.chunkPuts) // a single copy of the content
        for (u in listOf(B, C, D)) assertEquals(1, engine(u, MemStore()).receive().received)
        listOf(B, C, D).forEach { assertEquals(ShareIds.sha256Hex(sessions["S1"]!!), libraries[it.code]!!["S1"]) }
        ea.reconcile()
        assertTrue(sa.jobs().all { it.state == OutState.RECEIVED })
        assertTrue("content deleted after confirmations", server.metas.isEmpty() && server.chunks.isEmpty())
    }

    @Test fun duplicateEnqueueIsIgnoredAndNoDuplicateInLibrary() = runBlocking {
        accept(B, A)
        val sa = MemStore(); val ea = engine(A, sa)
        val t = RecipientResolver.resolve(A.code, listOf(B), true, listOf(B), true, listOf(B), emptyMap())
        assertEquals(1, ea.enqueue("S1", t, null))
        assertEquals(0, ea.enqueue("S1", t, null))   // automatic second time: nothing
        ea.sendPending()
        val eb = engine(B, MemStore())
        eb.receive()
        // manual re-share of an already received training: same id, same content → "already present"
        ea.reconcile()
        assertEquals(1, ea.enqueue("S1", listOf(RecipientResolver.Target(B, ShareOrigin.MANUAL, null)), null, resend = true))
        ea.sendPending()
        val r = eb.receive()
        assertEquals(0, r.received)
        assertEquals(1, libraries[B.code]!!.size)
        ea.reconcile()
        assertEquals(OutState.RECEIVED, sa.jobs().single().state)
    }

    @Test fun noSendingWithoutAcceptedInvitation() = runBlocking {
        val sa = MemStore(); val ea = engine(A, sa)
        ea.enqueue("S1", listOf(RecipientResolver.Target(B, ShareOrigin.GLOBAL, null)), null)
        val r = ea.sendPending()
        assertEquals(0, r.sent); assertEquals(1, r.waiting)
        assertEquals(OutState.WAITING_ACCEPT, sa.jobs().single().state)
        assertEquals(0, server.chunkPuts) // no quota used
        accept(B, A)
        assertEquals(1, ea.sendPending().sent)
    }

    @Test fun blockedRecipientNeverReceives() = runBlocking {
        server.grants[B.code to A.code] = GrantState.BLOCKED
        val sa = MemStore(); val ea = engine(A, sa)
        ea.enqueue("S1", listOf(RecipientResolver.Target(B, ShareOrigin.MANUAL, null)), null)
        ea.sendPending()
        assertEquals(OutState.BLOCKED, sa.jobs().single().state)
        assertTrue(server.inboxes[B.code].isNullOrEmpty())
    }

    @Test fun permissionsOnlyAuthorizedRecipientReadsChunks() = runBlocking {
        accept(B, A)
        val ea = engine(A, MemStore())
        ea.enqueue("S1", listOf(RecipientResolver.Target(B, ShareOrigin.MANUAL, null)), null)
        ea.sendPending()
        val tid = server.metas.keys.single()
        val intruder = server.backendFor(C.code)
        assertThrows(IllegalStateException::class.java) { runBlocking { intruder.getChunk(tid, 0) } }
    }

    @Test fun disconnectionDuringUploadResumesWithoutReuploading() = runBlocking {
        accept(B, A)
        val sa = MemStore(); val ea = engine(A, sa)
        ea.enqueue("S1", listOf(RecipientResolver.Target(B, ShareOrigin.GLOBAL, null)), null)
        server.opsUntilFailure = 6 // drops halfway through the upload
        assertThrows(OfflineException::class.java) { runBlocking { ea.sendPending() } }
        val uploadedBefore = server.chunkPuts
        assertTrue(uploadedBefore in 1 until 7)
        assertEquals(OutState.UPLOADING, sa.jobs().single().state)
        server.opsUntilFailure = Int.MAX_VALUE
        // "restart": new engine with the same persistent store
        assertEquals(1, engine(A, sa).sendPending().sent)
        assertEquals(ShareIds.chunkCount(100_000, 16 * 1024), server.chunkPuts) // only the missing ones
        assertEquals(1, engine(B, MemStore()).receive().received)
    }

    @Test fun disconnectionDuringDownloadDoesNotConfirmAndResumes() = runBlocking {
        accept(B, A)
        val ea = engine(A, MemStore())
        ea.enqueue("S1", listOf(RecipientResolver.Target(B, ShareOrigin.GLOBAL, null)), null)
        ea.sendPending()
        val sb = MemStore()
        server.opsUntilFailure = 5
        assertThrows(OfflineException::class.java) { runBlocking { engine(B, sb).receive() } }
        assertTrue(server.receipts.isEmpty())                 // no confirmation without import
        assertTrue(server.inboxes[B.code]!!.isNotEmpty())     // the notice is kept
        assertNull(libraries[B.code]?.get("S1"))
        server.opsUntilFailure = Int.MAX_VALUE
        assertEquals(1, engine(B, sb).receive().received)
        assertEquals("imported", server.receipts.values.single()[B.code])
    }

    @Test fun corruptedContentIsRejected() = runBlocking {
        accept(B, A)
        val ea = engine(A, MemStore())
        ea.enqueue("S1", listOf(RecipientResolver.Target(B, ShareOrigin.GLOBAL, null)), null)
        ea.sendPending()
        val tid = server.metas.keys.single()
        server.chunks[tid]!![2] = ByteArray(16 * 1024) // tampered chunk
        val sb = MemStore()
        val r = engine(B, sb).receive()
        assertEquals(0, r.received)
        assertEquals(InState.FAILED, sb.incoming().single().state)
        assertNull(libraries[B.code]?.get("S1"))
        assertTrue(server.receipts[tid].isNullOrEmpty())
    }

    @Test fun forgedNoticeFromAnotherUserIsDiscarded() = runBlocking {
        accept(B, A)
        val ea = engine(A, MemStore())
        ea.enqueue("S1", listOf(RecipientResolver.Target(B, ShareOrigin.GLOBAL, null)), null)
        ea.sendPending()
        val n = server.inboxes[B.code]!!.values.single()
        server.inboxes[B.code]!![n.transferId] = n.copy(from = C.code, fromName = "Impostor")
        val r = engine(B, MemStore()).receive()
        assertEquals(0, r.received)
        assertTrue(r.errors.single().contains("falsificado"))
    }

    @Test fun conflictWithDifferentLocalVersionAsksBeforeOverwriting() = runBlocking {
        accept(B, A)
        libraries.getOrPut(B.code) { HashMap() }["S1"] = "otra-version"
        val ea = engine(A, MemStore())
        ea.enqueue("S1", listOf(RecipientResolver.Target(B, ShareOrigin.GLOBAL, null)), null)
        ea.sendPending()
        val sb = MemStore(); val eb = engine(B, sb)
        eb.receive()
        val rec = sb.incoming().single()
        assertEquals(InState.NEEDS_CONFIRMATION, rec.state)
        assertEquals("otra-version", libraries[B.code]!!["S1"])
        assertTrue(server.receipts.isEmpty())
        eb.receive() // does not repeat the download while waiting for the user
        assertEquals(1, server.chunkGets / ShareIds.chunkCount(100_000, 16 * 1024))
        var forced = false
        eb.resolveConfirmation(rec.transferId, accepted = true) { forced = true }
        assertTrue(forced)
        assertEquals(InState.IMPORTED, sb.incoming().single().state)
        assertEquals("imported", server.receipts.values.single()[B.code])
    }

    @Test fun expiryDeletesContentAndMarksHistory() = runBlocking {
        accept(B, A)
        val sa = MemStore(); val ea = engine(A, sa, ShareLimits(maxTrainingBytes = 1_500_000, chunkBytes = 16 * 1024, expiryMs = 1000))
        ea.enqueue("S1", listOf(RecipientResolver.Target(B, ShareOrigin.GLOBAL, null)), null)
        ea.sendPending()
        now += 5000 // B never connected
        ea.reconcile()
        assertEquals(OutState.EXPIRED, sa.jobs().single().state)
        assertTrue(server.metas.isEmpty() && server.chunks.isEmpty())
        // B connects late: the notice points to deleted content and is cleaned without importing anything
        assertEquals(0, engine(B, MemStore()).receive().received)
        assertTrue(server.inboxes[B.code]!!.isEmpty())
    }

    @Test fun notDeletedWhileARecipientIsPending() = runBlocking {
        accept(B, A); accept(C, A)
        val ea = engine(A, MemStore())
        ea.enqueue("S1", listOf(RecipientResolver.Target(B, ShareOrigin.GLOBAL, null), RecipientResolver.Target(C, ShareOrigin.GLOBAL, null)), null)
        ea.sendPending()
        engine(B, MemStore()).receive()
        ea.reconcile()
        assertEquals(1, server.metas.size) // C has not received yet
        engine(C, MemStore()).receive()
        ea.reconcile()
        assertTrue(server.metas.isEmpty())
    }

    @Test fun offlineWorksLocallyAndSendsWhenConnectionReturns() = runBlocking {
        accept(B, A)
        val sa = MemStore(); val ea = engine(A, sa)
        server.opsUntilFailure = 0
        ea.enqueue("S1", listOf(RecipientResolver.Target(B, ShareOrigin.GLOBAL, null)), null) // enqueuing needs no network
        assertThrows(OfflineException::class.java) { runBlocking { ea.sendPending() } }
        assertEquals(OutState.QUEUED, sa.jobs().single().state)
        server.opsUntilFailure = Int.MAX_VALUE
        assertEquals(1, ea.sendPending().sent)
    }

    @Test fun oldTrainingCanBeSharedManually() = runBlocking {
        accept(B, A)
        val ea = engine(A, MemStore())
        ea.enqueue("S2", listOf(RecipientResolver.Target(B, ShareOrigin.MANUAL, null)), null)
        assertEquals(1, ea.sendPending().sent)
        assertEquals(1, engine(B, MemStore()).receive().received)
        assertNotNull(libraries[B.code]!!["S2"])
    }

    @Test fun tooLargeFailsWithoutUploading() = runBlocking {
        accept(B, A)
        sessions["BIG"] = ByteArray(200_000)
        val sa = MemStore(); val ea = engine(A, sa, ShareLimits(maxTrainingBytes = 100_000, chunkBytes = 16 * 1024))
        ea.enqueue("BIG", listOf(RecipientResolver.Target(B, ShareOrigin.MANUAL, null)), null)
        ea.sendPending()
        assertEquals(OutState.FAILED, sa.jobs().single().state)
        assertEquals(0, server.chunkPuts)
    }

    @Test fun stableIds() {
        val a = ShareIds.transferId(A.code, "S1", "ab".repeat(32))
        assertEquals(a, ShareIds.transferId(A.code, "S1", "AB".repeat(32)))
        assertNotEquals(a, ShareIds.transferId(B.code, "S1", "ab".repeat(32)))
        assertNotEquals(a, ShareIds.transferId(A.code, "S1", "cd".repeat(32)))
        assertEquals(32, a.length)
    }

    @Test fun usageIsCounted() = runBlocking {
        accept(B, A)
        val sa = MemStore(); val sb = MemStore()
        val ea = engine(A, sa)
        ea.enqueue("S2", listOf(RecipientResolver.Target(B, ShareOrigin.MANUAL, null)), null)
        ea.sendPending(); engine(B, sb).receive()
        assertEquals(40_000L, sa.up); assertEquals(40_000L, sb.down)
    }

    @Test fun largeFilesWaitForWifi() = runBlocking {
        accept(B, A)
        var wifi = false
        val sa = MemStore()
        val ea = ShareEngine(A, server.backendFor(A.code), sa, pkgr(tmp.root.resolve("o")), importer(A.code),
            ShareLimits(maxTrainingBytes = 1_500_000, chunkBytes = 16 * 1024), { now }, tmp.root.resolve("i"), { wifi }, 50_000)
        ea.enqueue("S1", listOf(RecipientResolver.Target(B, ShareOrigin.GLOBAL, null)), null) // 100 kB > 50 kB
        ea.enqueue("S2", listOf(RecipientResolver.Target(B, ShareOrigin.GLOBAL, null)), null) // 40 kB
        val r = ea.sendPending()
        assertEquals(1, r.sent); assertEquals(1, r.waiting)
        assertEquals(OutState.QUEUED, sa.jobs().first { it.sessionId == "S1" }.state)
        wifi = true
        assertEquals(1, ea.sendPending().sent)
    }
}
