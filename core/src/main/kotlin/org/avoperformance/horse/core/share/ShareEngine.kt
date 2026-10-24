package org.avoperformance.horse.core.share

import java.io.File
import java.io.RandomAccessFile
import java.security.MessageDigest

/**
 * Sending and receiving engine. Each method runs one complete, idempotent pass: it can be cut
 * at any point (no network, app killed) and the next pass continues from where it was.
 *
 * Sending protocol (per training):
 *   1 package + SHA-256 → 2 stable id → 3 meta → 4 chunks (resuming from the last uploaded one) → 5 complete
 *   → 6 read permission per recipient → 7 notice in each inbox → 8 receipts → 9 deletion when
 *   everyone confirmed or the expiry date passed.
 * Receiving protocol: notice → meta → chunks → size+SHA-256 → import → receipt → delete notice.
 * The receipt is only written after a correct import (or if it was already identical).
 */
class ShareEngine(
    private val me: Contact,
    private val backend: ShareBackend,
    private val store: ShareStore,
    private val packager: Packager,
    private val importer: Importer,
    private val limits: ShareLimits = ShareLimits(),
    private val clock: () -> Long = System::currentTimeMillis,
    private val workDir: File,
    /** false = metered connection with "only Wi-Fi for large files": trainings bigger than [largeBytes] wait. */
    private val allowLarge: () -> Boolean = { true },
    private val largeBytes: Long = Long.MAX_VALUE,
) {
    data class Report(val sent: Int = 0, val received: Int = 0, val waiting: Int = 0, val errors: List<String> = emptyList())

    // ----------------------------------------------------------------- queue

    /**
     * Adds deliveries to the queue with deduplication: if (training, recipient) already exists it is not duplicated.
     * Automatic (GLOBAL/HORSE) never repeats a delivery. MANUAL can resend one that was already received
     * or expired ([resend]).
     */
    fun enqueue(sessionId: String, targets: List<RecipientResolver.Target>, horseCode: String?, resend: Boolean = false): Int {
        val now = clock()
        val existing = store.jobs().associateBy { it.key }
        var added = 0
        for (t in targets) {
            val key = OutJob.keyOf(sessionId, t.contact.code)
            val old = existing[key]
            if (old != null) {
                val reopen = resend && t.origin == ShareOrigin.MANUAL && (old.state == OutState.RECEIVED || old.state == OutState.EXPIRED || old.state == OutState.FAILED)
                if (!reopen) continue
                store.upsert(old.copy(state = OutState.QUEUED, origin = ShareOrigin.MANUAL, attempts = 0, lastError = null, updatedMs = now, receivedMs = null))
            } else {
                store.upsert(OutJob(sessionId, t.contact.code, t.contact.name, t.origin, horseCode = horseCode, createdMs = now))
            }
            added++
        }
        return added
    }

    // ----------------------------------------------------------------- sending

    suspend fun sendPending(): Report {
        var sent = 0; var waiting = 0
        val errors = mutableListOf<String>()
        val bySession = store.jobs().filter { it.state == OutState.QUEUED || it.state == OutState.UPLOADING || it.state == OutState.WAITING_ACCEPT }
            .groupBy { it.sessionId }
        for ((sessionId, jobs) in bySession) {
            // 1. Authorizations: only accepted recipients receive. The rest wait without consuming quota.
            val ready = mutableListOf<OutJob>()
            for (j in jobs) {
                when (backend.grant(j.recipient, me.code)) {
                    GrantState.ACCEPTED -> ready += j
                    GrantState.BLOCKED, GrantState.REJECTED -> update(j) { copy(state = OutState.BLOCKED, lastError = "El destinatario no acepta envíos") }
                    else -> { waiting++; if (j.state != OutState.WAITING_ACCEPT) update(j) { copy(state = OutState.WAITING_ACCEPT) } }
                }
            }
            if (ready.isEmpty()) continue
            val pkg = try { packager.build(sessionId) } catch (e: OfflineException) { throw e } catch (e: Exception) {
                ready.forEach { j -> update(j) { copy(state = OutState.FAILED, lastError = e.message ?: "No se pudo preparar") } }
                errors += "$sessionId: ${e.message}"; continue
            }
            try {
                if (!allowLarge() && pkg.size > largeBytes) { waiting += ready.size; continue }
                if (pkg.size > limits.maxTrainingBytes) {
                    ready.forEach { j -> update(j) { copy(state = OutState.FAILED, lastError = "Ocupa ${pkg.size / 1_048_576} MB; límite ${limits.maxTrainingBytes / 1_048_576} MB") } }
                    errors += "$sessionId: demasiado grande"; continue
                }
                val tid = upload(sessionId, pkg, ready)
                // 6-7. Permission + notice for each one (idempotent)
                for (j in ready) {
                    backend.allowRecipient(tid, j.recipient)
                    backend.notify(j.recipient, Notice(tid, me.code, me.name, sessionId, pkg.horseName, pkg.size, clock()))
                    update(j) { copy(state = OutState.NOTIFIED, transferId = tid, lastError = null) }
                    sent++
                }
            } finally { pkg.file.delete() }
        }
        return Report(sent = sent, waiting = waiting, errors = errors)
    }

    /** Uploads the content once for all recipients, resuming if it was already partly uploaded. */
    private suspend fun upload(sessionId: String, pkg: Packaged, jobs: List<OutJob>): String {
        val tid = ShareIds.transferId(me.code, sessionId, pkg.sha256)
        val chunks = ShareIds.chunkCount(pkg.size, limits.chunkBytes)
        jobs.forEach { j -> if (j.state != OutState.UPLOADING || j.transferId != tid) update(j) { copy(state = OutState.UPLOADING, transferId = tid, attempts = attempts + 1) } }
        val existing = backend.meta(tid)
        if (existing != null && backend.isComplete(tid)) return tid // reused (re-share or other recipients)
        if (existing == null) backend.createMeta(TransferMeta(tid, me.code, me.name, sessionId, pkg.horseName, pkg.riderName,
            pkg.size, pkg.sha256, chunks, limits.chunkBytes, clock(), clock() + limits.expiryMs))
        var from = backend.uploadedChunks(tid)
        RandomAccessFile(pkg.file, "r").use { raf ->
            val buf = ByteArray(limits.chunkBytes)
            while (from < chunks) {
                val off = from.toLong() * limits.chunkBytes
                val len = minOf(limits.chunkBytes.toLong(), pkg.size - off).toInt()
                raf.seek(off); raf.readFully(buf, 0, len)
                backend.putChunk(tid, from, buf.copyOf(len))
                store.addUsage(len.toLong(), 0)
                from++
            }
        }
        backend.markComplete(tid)
        return tid
    }

    // ----------------------------------------------------------------- receipts and cleanup

    /**
     * Updates confirmations and deletes the temporary content when all recipients of a transfer
     * have finished (received/blocked) or the expiry date has passed. Local trainings are never deleted.
     */
    suspend fun reconcile(): Report {
        var done = 0
        val notified = store.jobs().filter { it.transferId != null && (it.state == OutState.NOTIFIED || it.state.terminal) }
        for ((tid, jobs) in notified.groupBy { it.transferId!! }) {
            val meta = backend.meta(tid)
            val receipts = if (meta != null) backend.receipts(tid) else emptyMap()
            val now = clock()
            for (j in jobs.filter { it.state == OutState.NOTIFIED }) {
                val r = receipts[j.recipient]
                when {
                    r == "imported" || r == "present" -> { update(j) { copy(state = OutState.RECEIVED, receivedMs = now, lastError = null) }; done++ }
                    r != null && r.startsWith("error") -> update(j) { copy(lastError = r.removePrefix("error:")) }
                    meta == null || now > meta.expiresMs -> update(j) { copy(state = OutState.EXPIRED, lastError = "Caducado sin confirmación") }
                }
            }
            val current = store.jobs().filter { it.transferId == tid }
            val stillPending = current.any { !it.state.terminal }
            if (meta != null && (!stillPending || now > meta.expiresMs)) backend.deleteTransfer(tid)
        }
        return Report(sent = done)
    }

    // ----------------------------------------------------------------- receiving

    suspend fun receive(): Report {
        var received = 0
        val errors = mutableListOf<String>()
        workDir.mkdirs()
        for (n in backend.inbox(me.code)) {
            val known = store.incoming().firstOrNull { it.transferId == n.transferId }
            if (known?.state == InState.NEEDS_CONFIRMATION) continue // waiting for the user
            if (!allowLarge() && n.size > largeBytes) continue             // waits for Wi-Fi
            val meta = backend.meta(n.transferId)
            if (meta == null) { backend.removeNotice(me.code, n.transferId); continue } // expired or withdrawn by the sender
            if (meta.owner != n.from) { backend.removeNotice(me.code, n.transferId); errors += "Aviso falsificado de ${n.from}"; continue }
            if (!backend.isComplete(n.transferId)) continue
            record(n, InState.DOWNLOADING, null, null)
            val file = File(workDir, "${n.transferId}.avo")
            try {
                download(meta, file)
            } catch (e: OfflineException) { throw e } catch (e: Exception) {
                file.delete(); record(n, InState.FAILED, e.message, null); errors += "${n.sessionId}: ${e.message}"; continue
            }
            val result = try { importer.import(file, n) } catch (e: Exception) {
                record(n, InState.FAILED, e.message, null); errors += "${n.sessionId}: ${e.message}"; file.delete()
                backend.putReceipt(n.transferId, me.code, "error:" + (e.message ?: "importación fallida").take(120)); continue
            }
            when (result) {
                Importer.Result.Imported, Importer.Result.AlreadyPresent -> {
                    backend.putReceipt(n.transferId, me.code, if (result == Importer.Result.Imported) "imported" else "present")
                    backend.removeNotice(me.code, n.transferId)
                    record(n, if (result == Importer.Result.Imported) InState.IMPORTED else InState.ALREADY_PRESENT, null, null)
                    file.delete(); received++
                }
                is Importer.Result.NeedsConfirmation -> record(n, InState.NEEDS_CONFIRMATION, result.reason, file.absolutePath)
            }
        }
        return Report(received = received, errors = errors)
    }

    /** The user decides about a delivery that conflicts with a local version. */
    suspend fun resolveConfirmation(transferId: String, accepted: Boolean, importForced: suspend (File) -> Unit) {
        val r = store.incoming().firstOrNull { it.transferId == transferId && it.state == InState.NEEDS_CONFIRMATION } ?: return
        val f = r.localFile?.let(::File)
        if (accepted && f != null && f.exists()) {
            importForced(f)
            backend.putReceipt(transferId, me.code, "imported")
            store.upsertIncoming(r.copy(state = InState.IMPORTED, message = null, localFile = null, receivedMs = clock()))
        } else {
            backend.putReceipt(transferId, me.code, "present")
            store.upsertIncoming(r.copy(state = InState.ALREADY_PRESENT, message = "Se conservó la versión local", localFile = null))
        }
        backend.removeNotice(me.code, transferId)
        f?.delete()
    }

    private suspend fun download(meta: TransferMeta, target: File) {
        require(meta.size in 1..limits.maxTrainingBytes) { "Tamaño declarado no válido" }
        require(meta.chunks == ShareIds.chunkCount(meta.size, meta.chunkSize)) { "Manifiesto incoherente" }
        val part = File(target.parentFile, target.name + ".part")
        val sha = MessageDigest.getInstance("SHA-256")
        var total = 0L
        part.outputStream().use { out ->
            for (i in 0 until meta.chunks) {
                val b = backend.getChunk(meta.transferId, i) ?: error("Falta el trozo ${i + 1}/${meta.chunks}")
                total += b.size
                require(total <= meta.size) { "Datos de más" }
                sha.update(b); out.write(b)
                store.addUsage(0, b.size.toLong())
            }
        }
        val hex = sha.digest().joinToString("") { "%02x".format(it) }
        if (total != meta.size || hex != meta.sha256.lowercase()) { part.delete(); error("Integridad incorrecta (tamaño o SHA-256 distintos)") }
        target.delete()
        check(part.renameTo(target)) { "No se pudo guardar" }
    }

    // ----------------------------------------------------------------- utilities

    private fun update(j: OutJob, f: OutJob.() -> OutJob) {
        val cur = store.jobs().firstOrNull { it.key == j.key } ?: j
        store.upsert(cur.f().copy(updatedMs = clock()))
    }

    private fun record(n: Notice, s: InState, msg: String?, file: String?) =
        store.upsertIncoming(InRecord(n.transferId, n.from, n.fromName, n.sessionId, n.horseName, n.size, s, clock(), msg, file))
}
