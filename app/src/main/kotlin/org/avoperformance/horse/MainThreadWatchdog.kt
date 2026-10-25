package org.avoperformance.horse

import android.os.Handler
import android.os.Looper
import android.os.SystemClock

/**
 * Diagnostic: detects when the main (UI) thread is blocked for more than [limitMs] and writes where it was
 * stuck into the app log ("Registro de la app", tag BLOQUEO). Android shows "no responde" after ~5 s; this
 * reports from 2 s on, so the cause is recorded even if the user closes the app. One report per blocking.
 */
class MainThreadWatchdog(private val log: AppLog, private val limitMs: Long = 2_000) : Thread("avo-watchdog") {
    @Volatile private var lastTick = SystemClock.uptimeMillis()
    private val main = Handler(Looper.getMainLooper())
    private val tick = Runnable { lastTick = SystemClock.uptimeMillis() }

    init { isDaemon = true; priority = MIN_PRIORITY }

    override fun run() {
        var reported = 0L
        while (true) {
            main.post(tick)
            try { sleep(500) } catch (_: InterruptedException) { return }
            val blocked = SystemClock.uptimeMillis() - lastTick
            if (blocked < limitMs) { reported = 0; continue }
            if (reported == lastTick) continue
            reported = lastTick
            val st = Looper.getMainLooper().thread.stackTrace
            // own code first (that is where the fix goes), then the top of the stack for context
            val own = st.filter { it.className.startsWith("org.avoperformance") }.take(8)
            val top = st.take(6)
            val fmt = { e: StackTraceElement -> "${e.className.substringAfterLast('.')}.${e.methodName}:${e.lineNumber}" }
            log.w("BLOQUEO", "hilo principal bloqueado ${blocked} ms. App: " + own.joinToString(" < ", transform = fmt))
            log.w("BLOQUEO", "pila: " + top.joinToString(" < ", transform = fmt))
        }
    }
}
