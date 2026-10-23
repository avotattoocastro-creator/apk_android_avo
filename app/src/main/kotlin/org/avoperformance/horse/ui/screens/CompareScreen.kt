package org.avoperformance.horse.ui.screens

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.avoperformance.horse.AppContainer
import org.avoperformance.horse.core.raw.TrainingAnalysis
import org.avoperformance.horse.data.TrainingEntity
import org.avoperformance.horse.ui.components.*
import org.avoperformance.horse.ui.theme.AvoColors
import kotlin.math.sqrt

@Composable
fun CompareScreen(c: AppContainer, firstId: String, secondId: String) {
    val first by c.db.trainings().observe(firstId).collectAsStateWithLifecycle(null)
    val second by c.db.trainings().observe(secondId).collectAsStateWithLifecycle(null)
    var a by remember(first?.localDir) { mutableStateOf<TrainingAnalysis?>(null) }
    var b by remember(second?.localDir) { mutableStateOf<TrainingAnalysis?>(null) }
    LaunchedEffect(first?.localDir) { first?.let { t -> a = withContext(Dispatchers.IO) { runCatching { c.sync.analysisFor(t) }.getOrNull() } } }
    LaunchedEffect(second?.localDir) { second?.let { t -> b = withContext(Dispatchers.IO) { runCatching { c.sync.analysisFor(t) }.getOrNull() } } }
    var sameRoute by remember { mutableStateOf(true) }
    var cmp by remember { mutableStateOf<org.avoperformance.horse.core.engine.EqComparison?>(null) }
    var cmpError by remember { mutableStateOf<String?>(null) }
    var cmpBusy by remember { mutableStateOf(false) }
    LaunchedEffect(first?.localDir, second?.localDir, sameRoute) {
        val fa = first; val fb = second
        if (fa?.localDir != null && fb?.localDir != null) {
            cmpBusy = true; cmpError = null
            try { cmp = c.equine.compare(fa, fb, sameRoute) } catch (e: kotlinx.coroutines.CancellationException) { throw e } catch (e: Exception) { cmpError = e.message ?: "error del motor" } finally { cmpBusy = false }
        }
    }
    if (first == null || second == null) { Note("No se encuentran las sesiones"); return }
    if (first?.horseCode == null || first?.horseCode != second?.horseCode) { Note("Solo es posible comparar dos sesiones del mismo caballo", AvoColors.Warn); return }
    LazyColumn(Modifier.fillMaxSize()) {
        item { AvoCard("Comparativa · ${first?.horseCode}") {
            KV("A", Fmt.date(first?.startRtcMs))
            KV("B", Fmt.date(second?.startRtcMs))
        } }
        if (a != null && b != null) {
            val left = a!!; val right = b!!
            item { AvoCard("Velocidad y distancia") {
                CompareMetric("Máxima", left.maxSpeedMs*3.6, right.maxSpeedMs*3.6, "km/h")
                if (left.avgSpeedMs != null && right.avgSpeedMs != null) CompareMetric("Media", left.avgSpeedMs!!*3.6, right.avgSpeedMs!!*3.6, "km/h")
                CompareMetric("Distancia", left.distanceM, right.distanceM, "m")
                if (left.durationS != null && right.durationS != null) CompareMetric("Duración", left.durationS!!, right.durationS!!, "s")
            } }
            item { AvoCard("Regularidad de velocidad") {
                CompareMetric("Variación relativa", speedVariation(left), speedVariation(right), "%")
            } }
            item { AvoCard("Precisión RTK") {
                CompareMetric("RTK FIX", left.fixEpochs.toDouble() / left.gnssUsable.coerceAtLeast(1)*100, right.fixEpochs.toDouble() / right.gnssUsable.coerceAtLeast(1)*100, "%")
                KV("IMU A", if (left.imuAvailable) "${left.imuSamples} muestras" else "Sin datos")
                KV("IMU B", if (right.imuAvailable) "${right.imuSamples} muestras" else "Sin datos")
            } }
        } else item { Note("Analizando los dos ficheros locales… Necesitas descargar y verificar ambas sesiones.") }
        // ---- AVO Equine Intelligence Engine comparison (says whether the sessions are really comparable)
        item { AvoCard("Comparación avanzada (motor)") {
            Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                androidx.compose.material3.Switch(checked = sameRoute, onCheckedChange = { sameRoute = it })
                Text("  Alinear como mismo recorrido", color = AvoColors.Text)
            }
            if (cmpBusy) androidx.compose.material3.LinearProgressIndicator(Modifier.fillMaxWidth(), color = AvoColors.Red, trackColor = AvoColors.Surface2)
            cmpError?.let { Note(it, AvoColors.Bad) }
            cmp?.let { r ->
                KV("Comparables", if (r.comparable) "sí" else "no", if (r.comparable) AvoColors.Ok else AvoColors.Warn)
                r.reasons.forEach { Note(it, AvoColors.Warn) }
                r.diffs.forEach { d ->
                    KV(d.name.replace('_', ' '), "A ${fmtD(d.a)} · B ${fmtD(d.b)} · Δ ${fmtD(d.diff)} ${d.unit}" + if (d.comparable) "" else "  (no comparable)",
                        if (d.comparable) AvoColors.Text else AvoColors.TextDim)
                }
                if (r.route.attempted) {
                    KV("Recorrido", if (r.route.comparable) "mismo recorrido" else "no comparable", if (r.route.comparable) AvoColors.Ok else AvoColors.Warn)
                    Note(r.route.reason)
                    if (r.route.comparable) {
                        KV("Separación lateral mediana", "${fmtD(r.route.medianXtrackM)} m")
                        KV("Δ velocidad media (B−A)", "${fmtD(r.route.meanSpeedDiff?.times(3.6))} km/h")
                        KV("Δ tiempo al final (B−A)", "${fmtD(r.route.totalTimeDiffS)} s")
                    }
                }
                if (r.patternComputed) KV("Forma del perfil (DTW)", "${fmtD(r.patternDtw)} m/s · ${r.patternNote}")
                KV("Curvas equivalentes", "${r.equivalentCurves}")
            }
        } }
    }
}
private fun speedVariation(a: TrainingAnalysis): Double {
    val v = a.track.map { it.speedMs }.filter { it > 0.5 && it.isFinite() }
    if (v.size < 3) return 0.0
    val avg = v.average(); return if (avg > 0) sqrt(v.map { (it-avg)*(it-avg) }.average()) / avg * 100 else 0.0
}
private fun fmtD(v: Double?) = v?.takeIf { it.isFinite() }?.let { "%.2f".format(it) } ?: "—"

@Composable
private fun CompareMetric(label: String, a: Double, b: Double, unit: String) {
    KV(label, "A: %.1f %s   |   B: %.1f %s   |   Δ %+,.1f %s".format(a,unit,b,unit,b-a,unit))
}
