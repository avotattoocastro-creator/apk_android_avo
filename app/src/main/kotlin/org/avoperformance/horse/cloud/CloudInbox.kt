package org.avoperformance.horse.cloud

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.avoperformance.horse.AppLog
import org.avoperformance.horse.MainActivity
import org.avoperformance.horse.R
import org.avoperformance.horse.core.identity.AvoUserCard
import org.json.JSONObject
import java.io.File

/**
 * Inbox for trainings received over the internet. It runs inside AvoLinkService (background) while the phone
 * has an AVO identity: it downloads each delivery, checks it, saves it in files/received and notifies.
 * Importing into the list stays manual (same validations as WhatsApp).
 */
class CloudInbox(private val ctx: Context, private val cloud: AvoCloud, private val log: AppLog) {
    data class Received(val file: File, val fromName: String, val fromCode: String, val sessionId: String, val receivedMs: Long)

    private val dir get() = File(ctx.filesDir, "received").also { it.mkdirs() }
    private val _received = MutableStateFlow(scan())
    val received: StateFlow<List<Received>> = _received
    private val _status = MutableStateFlow<String?>(null)
    val status: StateFlow<String?> = _status

    /** Listens to the inbox until cancelled. Reconnects with a pause if the network drops. */
    suspend fun watch(me: AvoUserCard) {
        var backoff = 5_000L
        while (true) {
            try {
                _status.value = "Conectando con el servicio de envío…"
                cloud.incoming(me).collect { m ->
                    _status.value = "Recibiendo de ${m.fromName}…"
                    val target = File(dir, "${m.id}.avo")
                    try {
                        cloud.receive(me, m, target)
                        File(dir, "${m.id}.json").writeText(JSONObject().put("fromName", m.fromName).put("from", m.from)
                            .put("sessionId", m.sessionId).put("receivedMs", System.currentTimeMillis()).toString())
                        refresh()
                        notifyNew(m, target)
                        log.i("CLOUD", "recibido ${m.sessionId} de ${m.from}")
                    } catch (e: Exception) {
                        log.w("CLOUD", "recepción ${m.id}: ${e.message}")
                        if (e.message?.contains("dañado") == true) runCatching { cloud.discard(me, m.id) }
                    }
                    _status.value = "Conectado: esperando entrenamientos"
                    backoff = 5_000L
                }
            } catch (e: kotlinx.coroutines.CancellationException) { throw e }
            catch (e: Exception) {
                _status.value = "Servicio de envío no disponible: ${e.message}"
                log.w("CLOUD", "bandeja: ${e.message}")
            }
            delay(backoff); backoff = (backoff * 2).coerceAtMost(300_000L)
        }
    }

    fun remove(r: Received) { r.file.delete(); File(dir, r.file.nameWithoutExtension + ".json").delete(); refresh() }
    fun refresh() { _received.value = scan() }

    private fun scan(): List<Received> = (File(ctx.filesDir, "received").listFiles { f -> f.extension == "avo" } ?: emptyArray()).mapNotNull { f ->
        val meta = runCatching { JSONObject(File(f.parentFile, f.nameWithoutExtension + ".json").readText()) }.getOrNull() ?: return@mapNotNull null
        Received(f, meta.optString("fromName"), meta.optString("from"), meta.optString("sessionId"), meta.optLong("receivedMs"))
    }.sortedByDescending { it.receivedMs }

    private fun notifyNew(m: AvoCloud.Incoming, file: File) {
        if (Build.VERSION.SDK_INT >= 33 && ActivityCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val nm = ctx.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "Entrenamientos recibidos", NotificationManager.IMPORTANCE_HIGH))
        val open = PendingIntent.getActivity(ctx, m.id.hashCode(), Intent(ctx, MainActivity::class.java).setAction(ACTION_OPEN_RECEIVED).setData(android.net.Uri.fromFile(file))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        NotificationManagerCompat.from(ctx).notify(m.id.hashCode(), NotificationCompat.Builder(ctx, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_avo)
            .setContentTitle("Nuevo entrenamiento recibido")
            .setContentText("${m.fromName} te ha enviado ${m.sessionId}")
            .setAutoCancel(true).setContentIntent(open).build())
    }

    companion object {
        const val CHANNEL = "avo_received"
        const val ACTION_OPEN_RECEIVED = "org.avoperformance.horse.OPEN_RECEIVED"
    }
}
