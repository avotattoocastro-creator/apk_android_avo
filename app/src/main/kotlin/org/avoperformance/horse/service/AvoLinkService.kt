package org.avoperformance.horse.service

import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleService
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import org.avoperformance.horse.AvoApp
import org.avoperformance.horse.MainActivity
import org.avoperformance.horse.R
import org.avoperformance.horse.ble.LinkState
import org.avoperformance.horse.core.telemetry.RtkDeriver

/**
 * Keeps the BLE link, NTRIP and automatic download alive while the screen is off
 * (foreground service of type connectedDevice).
 */
class AvoLinkService : LifecycleService() {
    private val c get() = (application as AvoApp).container
    private var collecting = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        if (intent?.action == ACTION_STOP) {
            c.settings.autoStartPaused = true
            c.dnd.restoreOwned("desconexión voluntaria")
            c.ntrip.stop(); c.watch.stop()
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        val type = if (Build.VERSION.SDK_INT >= 29) ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE else 0
        ServiceCompat.startForeground(this, NOTIF_ID, build("Iniciando…"), type)
        c.dnd.restoreExpired()
        c.watch.start()
        if (c.settings.ntrip.value.enabled) c.ntrip.start()
        c.sync.scheduleWorker()
        if (collecting) return START_STICKY
        collecting = true
        lifecycleScope.launch {
            var lastText = ""
            var wasReady = false
            combine(c.watch.state, c.watch.telemetry, c.ntrip.state) { s, t, n -> Triple(s, t, n) }.collect { (s, t, n) ->
                val rtk = RtkDeriver.derive(t?.t, t?.let { System.currentTimeMillis() - it.receivedMs } ?: Long.MAX_VALUE)
                val text = buildString {
                    append(s.texto)
                    if (s == LinkState.LISTO || s == LinkState.LISTO_SIN_AUTH) append(" · ").append(rtk.state.texto)
                    if (c.ntrip.running) append(" · NTRIP: ").append(n.texto)
                }
                if (text != lastText && (androidx.core.app.ActivityCompat.checkSelfPermission(this@AvoLinkService, android.Manifest.permission.POST_NOTIFICATIONS) == android.content.pm.PackageManager.PERMISSION_GRANTED || Build.VERSION.SDK_INT < 33)) {
                    NotificationManagerCompat.from(this@AvoLinkService).notify(NOTIF_ID, build(text))
                    lastText = text
                }
                val ready = c.watch.isReady
                c.dnd.onWatchTelemetry(t?.t, t?.receivedMs ?: 0L, ready)
                if (ready && !wasReady) c.sync.autoSync()      // download finished trainings after each (re)connection
                wasReady = ready
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        c.dnd.restoreOwned("servicio detenido")
        super.onDestroy()
    }

    private fun build(text: String): Notification {
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1, Intent(this, AvoLinkService::class.java).setAction(ACTION_STOP), PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat.Builder(this, AvoApp.CHANNEL_LINK)
            .setSmallIcon(R.drawable.ic_stat_avo)
            .setContentTitle("AVO Performance Horse")
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(open)
            .addAction(0, "Desconectar", stop)
            .build()
    }

    companion object {
        const val NOTIF_ID = 42
        const val ACTION_STOP = "org.avoperformance.horse.STOP"
        fun start(ctx: Context) {
            (ctx.applicationContext as AvoApp).container.settings.autoStartPaused = false
            ContextCompat.startForegroundService(ctx, Intent(ctx, AvoLinkService::class.java))
        }
        fun stop(ctx: Context) {
            (ctx.applicationContext as AvoApp).container.settings.autoStartPaused = true
            ctx.startService(Intent(ctx, AvoLinkService::class.java).setAction(ACTION_STOP))
        }

        /**
         * Background start without opening the app (boot, app update, Bluetooth link with the watch, app process start).
         * Only when enabled, a watch is authorised, Bluetooth permission is granted and the user did not disconnect.
         * Android allows it from boot/update broadcasts and, at any time, when battery optimisation is disabled for the app.
         */
        fun startIfAutomatic(ctx: Context, reason: String): Boolean {
            val app = ctx.applicationContext as AvoApp
            val s = app.container.settings
            if (!s.autoStart || s.autoStartPaused || s.authorizedWatch == null) return false
            if (Build.VERSION.SDK_INT >= 31 && ContextCompat.checkSelfPermission(ctx, android.Manifest.permission.BLUETOOTH_CONNECT) != android.content.pm.PackageManager.PERMISSION_GRANTED) return false
            return try {
                ContextCompat.startForegroundService(ctx, Intent(ctx, AvoLinkService::class.java))
                app.container.log.i("LINK", "inicio automático en segundo plano ($reason)")
                true
            } catch (e: Exception) {   // ForegroundServiceStartNotAllowedException when Android forbids it
                app.container.log.w("LINK", "inicio automático no permitido ($reason): ${e.message}")
                false
            }
        }
    }
}
