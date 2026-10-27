package org.avoperformance.horse.cloud

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.avoperformance.horse.AppContainer
import org.avoperformance.horse.AvoApp
import org.avoperformance.horse.MainActivity
import org.avoperformance.horse.R
import org.avoperformance.horse.core.identity.AvoUserCard
import org.avoperformance.horse.core.share.*
import org.avoperformance.horse.data.ShareInEntity
import org.avoperformance.horse.data.ShareOutEntity
import org.avoperformance.horse.data.ShareRecipientEntity
import org.avoperformance.horse.share.TrainingImport
import org.avoperformance.horse.share.TrainingShare
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.TimeUnit

/**
 * Sharing between AVO users over Firebase. Three simultaneous modes:
 *  A) global recipients (every new training), B) recipients per horse (they are added),
 *  C) manual sharing of any training (also old ones, and again).
 * Offline-first: everything goes into a persistent queue (Room) and is sent with WorkManager when there is network
 * (backoff retries, network preferences). Reception: live listener while the app/service is
 * running + periodic check every 15 min + check when the app opens. No FCM: on the Spark
 * plan there is no server that can send the push (see SHARE_FIREBASE.md).
 */
class ShareManager(private val c: AppContainer) {
    val firebase = FirebaseShare(c.app)
    private val dao get() = c.db.share()
    private val lock = Mutex()

    data class Status(val running: Boolean = false, val lastRunMs: Long = 0, val message: String? = null, val error: String? = null)
    private val _status = MutableStateFlow(Status())
    val status: StateFlow<Status> = _status

    // ------------------------------------------------------------- persistent store (Room)

    private val store = object : ShareStore {
        override fun jobs(): List<OutJob> = dao.outAll().map { e ->
            OutJob(e.sessionId, e.recipient, e.recipientName, ShareOrigin.valueOf(e.origin), OutState.valueOf(e.state), e.transferId,
                e.attempts, e.lastError, e.createdMs, e.updatedMs, e.receivedMs, e.horseCode)
        }
        override fun upsert(job: OutJob) = dao.upsertOut(ShareOutEntity(job.sessionId, job.recipient, job.recipientName, job.origin.name,
            job.state.name, job.transferId, job.attempts, job.lastError, job.createdMs, job.updatedMs, job.receivedMs, job.horseCode))
        override fun incoming(): List<InRecord> = dao.inAll().map { e ->
            InRecord(e.transferId, e.fromCode, e.fromName, e.sessionId, e.horseName, e.size, InState.valueOf(e.state), e.receivedMs, e.message, e.localFile)
        }
        override fun upsertIncoming(r: InRecord) = dao.upsertIn(ShareInEntity(r.transferId, r.from, r.fromName, r.sessionId, r.horseName, r.size,
            r.state.name, r.receivedMs, r.message, r.localFile))
        override fun addUsage(uploaded: Long, downloaded: Long) = c.settings.addShareUsage(uploaded, downloaded)
    }

    // ------------------------------------------------------------- package and import (existing system)

    private val packager = object : Packager {
        override suspend fun build(sessionId: String): Packaged {
            val t = c.db.trainings().byId(sessionId) ?: error("Entrenamiento no encontrado")
            val horse = c.db.horses().all().first().firstOrNull { it.code == t.horseCode }?.name.orEmpty()
            val rider = c.db.riders().all().first().firstOrNull { it.code == t.riderCode }?.name.orEmpty()
            if (horse.isBlank() || rider.isBlank()) error("Falta caballo o jinete: asígnalos y pulsa Reintentar")
            val f = TrainingShare.buildPackage(c.app, t, horse, rider)   // also checks that it is verified with the watch
            val out = File(c.app.cacheDir, "share_out").also { it.mkdirs() }.resolve(f.name)
            f.copyTo(out, overwrite = true); f.delete()
            return Packaged(out, sha256(out), out.length(), horse, rider)
        }
    }

    private val importer = object : Importer {
        override suspend fun import(file: File, notice: Notice): Importer.Result {
            val p = TrainingImport.inspect(c, android.net.Uri.fromFile(file))
            return when {
                p.identical -> { TrainingImport.discard(p); Importer.Result.AlreadyPresent }
                p.duplicate -> { TrainingImport.discard(p); Importer.Result.NeedsConfirmation("Ya tienes otra versión de ${p.sessionId}") }
                else -> { TrainingImport.import(c, p); notifyReceived(notice); Importer.Result.Imported }
            }
        }
    }

    private fun engine(card: AvoUserCard): ShareEngine {
        val s = c.settings
        val limits = ShareLimits(maxTrainingBytes = s.shareMaxMb.coerceIn(1, 30) * 1024L * 1024L)
        return ShareEngine(Contact(card.code, card.name), firebase.backend(), store, packager, importer, limits,
            workDir = File(c.app.filesDir, "share_in"),
            allowLarge = { !isMetered() || s.shareWifiOnlyLargeMb <= 0 },
            largeBytes = s.shareWifiOnlyLargeMb.coerceAtLeast(1) * 1024L * 1024L)
    }

    // ------------------------------------------------------------- recipients

    fun recipients() = dao.recipientsFlow()
    fun addRecipient(scope: String, contact: Contact) { c.scope.launch(Dispatchers.IO) { dao.upsertRecipient(ShareRecipientEntity(scope, contact.code, contact.name)) } }
    fun removeRecipient(scope: String, code: String) { c.scope.launch(Dispatchers.IO) { dao.deleteRecipient(scope, code) } }

    /** Called after each download verified against the watch: modes A + B. Imported trainings are never forwarded. */
    fun onTrainingVerified(sessionId: String) = c.scope.launch(Dispatchers.IO) {
        if (!org.avoperformance.horse.license.LicenseGate.fullAccess) return@launch
        val card = c.identity.card.value ?: return@launch
        val t = c.db.trainings().byId(sessionId) ?: return@launch
        if (t.watchState == "IMPORTADO") return@launch
        val all = dao.recipientsAll()
        val global = all.filter { it.scope == GLOBAL }.map { Contact(it.code, it.name) }
        val horse = t.horseCode?.let { h -> all.filter { it.scope == h }.map { Contact(it.code, it.name) } }.orEmpty()
        val targets = RecipientResolver.resolve(card.code, global, c.settings.shareGlobalEnabled, horse,
            t.horseCode != null && t.horseCode !in c.settings.shareHorsesDisabled, emptyList(), emptyMap())
        if (targets.isEmpty()) return@launch
        val n = engine(card).enqueue(sessionId, targets, t.horseCode)
        if (n > 0) { c.log.i("SHARE", "$sessionId en cola para $n destinatarios"); runNow() }
    }

    /** Mode C: manual sharing (also old ones and re-sending). */
    suspend fun shareManually(sessionId: String, contacts: List<Contact>): Int = withContext(Dispatchers.IO) {
        check(org.avoperformance.horse.license.LicenseGate.fullAccess) { org.avoperformance.horse.license.LicenseGate.BLOCKED }
        val card = c.identity.card.value ?: error("Primero acerca tu tarjeta AVO personal (NFC)")
        val horse = c.db.trainings().byId(sessionId)?.horseCode
        val targets = RecipientResolver.resolve(card.code, emptyList(), false, emptyList(), false, contacts, emptyMap())
        val n = engine(card).enqueue(sessionId, targets, horse, resend = true)
        runNow()
        n
    }

    /** Manually retry the failed ones (e.g. after assigning a horse/rider). */
    fun retryFailed() = c.scope.launch(Dispatchers.IO) {
        store.jobs().filter { it.state == OutState.FAILED }.forEach { store.upsert(it.copy(state = OutState.QUEUED, lastError = null, updatedMs = System.currentTimeMillis())) }
        runNow()
    }

    suspend fun resolveConfirmation(transferId: String, accept: Boolean) {
        val card = c.identity.card.value ?: return
        firebase.signIn(card)
        engine(card).resolveConfirmation(transferId, accept) { f ->
            val p = TrainingImport.inspect(c, android.net.Uri.fromFile(f))
            // The user authorizes replacing the local version: the import keeps a backup until it is validated.
            TrainingImport.import(c, p.copy(identical = false))
        }
    }

    // ------------------------------------------------------------- execution

    /** Full pass: send, confirmations/cleanup and reception. Returns false if it must be retried. */
    suspend fun runPass(reason: String): Boolean = withContext(Dispatchers.IO) { lock.withLock { pass(reason) } }

    private suspend fun pass(reason: String): Boolean {
        if (!org.avoperformance.horse.license.LicenseGate.fullAccess) { _status.value = _status.value.copy(running = false, message = org.avoperformance.horse.license.LicenseGate.BLOCKED); return true }
        val card = c.identity.card.value ?: return true
        if (c.settings.sharePaused) { _status.value = _status.value.copy(message = "Transferencias en pausa"); return true }
        if (onWifi() && !c.settings.shareAllowWifi) return false
        if (isMetered() && !c.settings.shareAllowMobile) return false
        _status.value = _status.value.copy(running = true, message = "Sincronizando…", error = null)
        return try {
            firebase.signIn(card)
            val e = engine(card)
            val sent = e.sendPending()
            e.reconcile()
            val got = e.receive()
            val errs = sent.errors + got.errors
            _status.value = Status(false, System.currentTimeMillis(),
                "Enviados ${sent.sent} · recibidos ${got.received}" + if (sent.waiting > 0) " · ${sent.waiting} esperando" else "",
                errs.firstOrNull())
            c.log.i("SHARE", "pasada ($reason): enviados ${sent.sent}, recibidos ${got.received}, esperando ${sent.waiting}, errores ${errs.size}")
            scheduleFollowUp()
            true
        } catch (e: OfflineException) {
            _status.value = Status(false, System.currentTimeMillis(), "Sin conexión: se reintentará", null); false
        } catch (e: Exception) {
            _status.value = Status(false, System.currentTimeMillis(), null, e.message ?: e.javaClass.simpleName)
            c.log.w("SHARE", "pasada ($reason): ${e.message}"); false
        }
    }

    private fun constraints() = Constraints.Builder()
        .setRequiredNetworkType(if (c.settings.shareAllowMobile) NetworkType.CONNECTED else NetworkType.UNMETERED).build()

    /** Runs a pass as soon as possible (with network). */
    fun runNow() {
        if (!org.avoperformance.horse.license.LicenseGate.fullAccess) return
        val req = OneTimeWorkRequestBuilder<ShareWorker>().setConstraints(constraints())
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS).build()
        WorkManager.getInstance(c.app).enqueueUniqueWork("avo_share_now", ExistingWorkPolicy.REPLACE, req)
    }

    /**
     * While there are deliveries "Enviado · pendiente de recepción" sent less than 2 h ago, it repeats a short pass
     * every ~30 s to collect the receipt without waiting for the 15-minute periodic task.
     */
    private fun scheduleFollowUp() {
        val now = System.currentTimeMillis()
        val pending = dao.outAll().any { it.state == OutState.NOTIFIED.name && now - it.updatedMs < 2 * 3600_000L }
        if (!pending) return
        val req = OneTimeWorkRequestBuilder<ShareWorker>().setConstraints(constraints())
            .setInitialDelay(30, TimeUnit.SECONDS).build()
        WorkManager.getInstance(c.app).enqueueUniqueWork("avo_share_followup", ExistingWorkPolicy.REPLACE, req)
    }

    /** Recovery every 15 minutes (minimum allowed by Android), compatible with battery saving. */
    fun schedule() {
        if (!org.avoperformance.horse.license.LicenseGate.fullAccess) return
        val req = PeriodicWorkRequestBuilder<ShareWorker>(15, TimeUnit.MINUTES).setConstraints(constraints())
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 60, TimeUnit.SECONDS).build()
        WorkManager.getInstance(c.app).enqueueUniquePeriodicWork("avo_share_periodic", ExistingPeriodicWorkPolicy.UPDATE, req)
    }

    /** Live listener (with the service running): as soon as a notice arrives, a pass is launched. */
    suspend fun listen(card: AvoUserCard) = kotlinx.coroutines.coroutineScope {
        // There is no push when someone accepts: while deliveries are waiting for acceptance,
        // check every minute (tiny reads) and send as soon as it is accepted.
        // Likewise for "Enviado": check every 20 s whether the recipient has already confirmed reception
        // (receipt) so it moves to OK straight away.
        launch {
            var tick = 0
            while (true) {
                delay(20_000); tick++
                runCatching {
                    val outs = withContext(Dispatchers.IO) { dao.outAll() }
                    val notified = outs.filter { it.state == OutState.NOTIFIED.name && it.transferId != null }
                    val backend = firebase.backend()
                    if (notified.isNotEmpty() && notified.groupBy { it.transferId!! }.any { (tid, js) ->
                            val r = backend.receipts(tid); js.any { r.containsKey(it.recipient) } || backend.meta(tid) == null }) runNow()
                    if (tick % 3 == 0) {
                        val waiting = outs.filter { it.state == OutState.WAITING_ACCEPT.name }.map { it.recipient }.distinct()
                        if (waiting.isNotEmpty() && waiting.any { firebase.outgoingState(card.code, it) == GrantState.ACCEPTED }) runNow()
                    }
                }
            }
        }
        listenInbox(card)
    }

    private suspend fun listenInbox(card: AvoUserCard) {
        var backoff = 5_000L
        while (true) {
            try {
                firebase.signIn(card)
                firebase.inboxChanges(card.code).collect { runNow(); backoff = 5_000L }
            } catch (e: kotlinx.coroutines.CancellationException) { throw e } catch (e: Exception) {
                c.log.w("SHARE", "escucha: ${e.message}")
            }
            delay(backoff); backoff = (backoff * 2).coerceAtMost(15 * 60_000L)
        }
    }

    private fun isMetered(): Boolean {
        val cm = c.app.getSystemService(ConnectivityManager::class.java) ?: return true
        return cm.isActiveNetworkMetered
    }
    private fun onWifi(): Boolean {
        val cm = c.app.getSystemService(ConnectivityManager::class.java) ?: return false
        return cm.getNetworkCapabilities(cm.activeNetwork)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
    }

    private fun notifyReceived(n: Notice) {
        if (Build.VERSION.SDK_INT >= 33 && ActivityCompat.checkSelfPermission(c.app, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val nm = c.app.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "Entrenamientos recibidos", NotificationManager.IMPORTANCE_HIGH))
        val open = PendingIntent.getActivity(c.app, n.transferId.hashCode(), Intent(c.app, MainActivity::class.java).setAction(ACTION_OPEN_SHARE)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        NotificationManagerCompat.from(c.app).notify(n.transferId.hashCode(), NotificationCompat.Builder(c.app, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_avo).setContentTitle("Nuevo entrenamiento recibido")
            .setContentText("${n.fromName}: ${n.horseName} · ${n.sessionId}").setAutoCancel(true).setContentIntent(open).build())
    }

    private fun sha256(f: File): String {
        val d = MessageDigest.getInstance("SHA-256")
        f.inputStream().use { i -> val b = ByteArray(65536); while (true) { val n = i.read(b); if (n < 0) break; d.update(b, 0, n) } }
        return d.digest().joinToString("") { "%02x".format(it) }
    }

    companion object {
        const val GLOBAL = "GLOBAL"
        const val CHANNEL = "avo_received"
        const val ACTION_OPEN_SHARE = "org.avoperformance.horse.OPEN_SHARE"
    }
}

class ShareWorker(ctx: Context, params: WorkerParameters) : CoroutineWorker(ctx, params) {
    override suspend fun doWork(): Result {
        val c = (applicationContext as AvoApp).container
        // safety net: if Android stopped the listening service, try to start it again
        runCatching { org.avoperformance.horse.service.AvoLinkService.startIfAutomatic(applicationContext, "comprobación de compartir") }
        val ok = c.share.runPass(if (tags.any { it.contains("Periodic") }) "periódica" else "inmediata")
        return when {
            ok -> Result.success()
            c.settings.shareAutoRetry && runAttemptCount < 10 -> Result.retry()
            else -> Result.success() // the periodic pass will try again
        }
    }
}
