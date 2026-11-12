package org.avoperformance.horse.engine

import android.content.Context
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import org.avoperformance.horse.AppLog
import org.avoperformance.horse.core.engine.EqComparison
import org.avoperformance.horse.core.engine.EquineResult
import org.avoperformance.horse.core.sync.SessionDownload
import org.avoperformance.horse.data.TrainingEntity
import java.io.File
import java.time.Instant

/** State of the engine analysis of one training, observed by the UI. */
sealed class EngineState {
    data object Idle : EngineState()
    data class Running(val reprocess: Boolean) : EngineState()
    data class Ready(val result: EquineResult) : EngineState()
    data class Failed(val message: String) : EngineState()
    data object Cancelled : EngineState()
    data class Unavailable(val reason: String) : EngineState()
}

/**
 * Connects the C++ engine to the app's training flow:
 *   downloaded RAW segments (files/trainings/<id>/P###.avr, never modified) -> validation + engine (background,
 *   cancellable) -> derived results stored in files/equine/<id>/ (one file per input fingerprint + parameters,
 *   recalculated automatically when the engine or an algorithm version changes) -> parsed model for the UI.
 */
class EquineEngine(private val ctx: Context, private val log: AppLog, private val scope: CoroutineScope) {
    private val states = MutableStateFlow<Map<String, EngineState>>(emptyMap())
    private val jobs = HashMap<String, Job>()
    val all: StateFlow<Map<String, EngineState>> = states.asStateFlow()

    fun stateOf(id: String): EngineState = states.value[id] ?: EngineState.Idle

    fun resultDir(sessionId: String) = File(ctx.filesDir, "equine/$sessionId")

    private fun segments(t: TrainingEntity): List<File> {
        val dir = File(t.localDir ?: return emptyList())
        return SessionDownload(dir, t.sessionId, t.segments).segments()
    }

    private fun set(id: String, s: EngineState) = states.update { it + (id to s) }

    /** Opens (or recalculates when [reprocess]) the analysis of a downloaded training. Safe to call repeatedly. */
    @Synchronized fun open(t: TrainingEntity, reprocess: Boolean = false) {
        if (!AvoEquine.available) { set(t.sessionId, EngineState.Unavailable(AvoEquine.unavailableReason ?: "no disponible")); return }
        val running = jobs[t.sessionId]
        if (running?.isActive == true) { if (!reprocess) return; running.cancel() }
        if (!reprocess && stateOf(t.sessionId) is EngineState.Ready) return
        set(t.sessionId, EngineState.Running(reprocess))
        jobs[t.sessionId] = scope.launch {
            try {
                val r = analyse(t, reprocess)
                set(t.sessionId, EngineState.Ready(r))
                log.i("Motor", "${t.sessionId}: análisis ${r.cache ?: ""} motor ${r.engine}")
            } catch (e: CancellationException) {
                set(t.sessionId, EngineState.Cancelled); throw e
            } catch (e: Exception) {
                set(t.sessionId, EngineState.Failed(e.message ?: e.toString()))
                log.w("Motor", "${t.sessionId}: ${e.message}")
            }
        }
    }

    @Synchronized fun cancel(id: String) { jobs[id]?.cancel() }

    suspend fun analyse(t: TrainingEntity, reprocess: Boolean): EquineResult {
        val segs = segments(t)
        require(segs.isNotEmpty()) { "la sesión no está descargada en el teléfono" }
        val dir = resultDir(t.sessionId).apply { mkdirs() }
        val opts = """{"series":true,"cache_dir":${jsonStr(dir.absolutePath)},"forzar":$reprocess,"procesado_utc":${jsonStr(Instant.now().toString())}}"""
        val text = runNative { token -> AvoEquine.nativeAnalyse(segs.map { AvoEquine.utf8(it.absolutePath) }.toTypedArray(), AvoEquine.utf8(opts), token) }
        return EquineResult.parse(text)
    }

    /** Compares two downloaded trainings (whole sessions by default, optionally the same route). */
    suspend fun compare(a: TrainingEntity, b: TrainingEntity, sameRoute: Boolean): EqComparison {
        check(AvoEquine.available) { AvoEquine.unavailableReason ?: "motor no disponible" }
        val sa = segments(a); val sb = segments(b)
        require(sa.isNotEmpty() && sb.isNotEmpty()) { "las dos sesiones deben estar descargadas" }
        val opts = """{"mismo_recorrido":$sameRoute}"""
        val text = runNative { token ->
            AvoEquine.nativeCompare(sa.map { AvoEquine.utf8(it.absolutePath) }.toTypedArray(), sb.map { AvoEquine.utf8(it.absolutePath) }.toTypedArray(), AvoEquine.utf8(opts), token)
        }
        return EqComparison.parse(text)
    }

    /** Runs a blocking native call off the main thread; coroutine cancellation sets the native cancel flag. */
    private suspend fun runNative(call: (Long) -> ByteArray): String {
        val token = AvoEquine.nativeNewToken()
        try {
            return coroutineScope {
                val job = async(Dispatchers.Default) { AvoEquine.text(call(token)) }
                try { job.await() } catch (e: CancellationException) { AvoEquine.nativeCancel(token); throw e }
            }
        } finally {
            AvoEquine.nativeFreeToken(token)   // coroutineScope returned: the native call has finished
        }
    }

    private fun jsonStr(s: String) = buildString {
        append('"'); s.forEach { ch -> when (ch) { '"' -> append("\\\""); '\\' -> append("\\\\"); else -> if (ch < ' ') append("\\u%04x".format(ch.code)) else append(ch) } }; append('"')
    }
}
