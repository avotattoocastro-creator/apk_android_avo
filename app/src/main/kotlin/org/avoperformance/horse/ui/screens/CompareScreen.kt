package org.avoperformance.horse.ui.screens

import androidx.compose.foundation.layout.fillMaxSize
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
    if (first == null || second == null) { Note("No se encuentran las sesiones"); return }
    if (first?.horseCode == null || first?.horseCode != second?.horseCode) { Note("Solo es posible comparar dos sesiones del mismo caballo", AvoColors.Warn); return }
    LazyColumn(Modifier.fillMaxSize()) {
        item { AvoCard("Comparativa · ${first?.horseCode}") {
            KV("A", Fmt.date(first?.startRtcMs))
            KV("B", Fmt.date(second?.startRtcMs))
            Note("La comparación usa únicamente datos GNSS registrados; condiciones, distancia y terreno pueden ser distintos.")
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
                Note("Menor variación significa mayor uniformidad en velocidad, no necesariamente mejor entrenamiento.")
            } }
            item { AvoCard("Precisión RTK") {
                CompareMetric("RTK FIX", left.fixEpochs.toDouble() / left.gnssUsable.coerceAtLeast(1)*100, right.fixEpochs.toDouble() / right.gnssUsable.coerceAtLeast(1)*100, "%")
                KV("IMU A", if (left.imuAvailable) "${left.imuSamples} muestras" else "Sin datos")
                KV("IMU B", if (right.imuAvailable) "${right.imuSamples} muestras" else "Sin datos")
                Note("El análisis biomecánico por cada una de las tres IMU requiere decodificación y validación específica.")
            } }
        } else item { Note("Analizando los dos ficheros locales… Necesitas descargar y verificar ambas sesiones.") }
    }
}
private fun speedVariation(a: TrainingAnalysis): Double {
    val v = a.track.map { it.speedMs }.filter { it > 0.5 && it.isFinite() }
    if (v.size < 3) return 0.0
    val avg = v.average(); return if (avg > 0) sqrt(v.map { (it-avg)*(it-avg) }.average()) / avg * 100 else 0.0
}
@Composable
private fun CompareMetric(label: String, a: Double, b: Double, unit: String) {
    KV(label, "A: %.1f %s   |   B: %.1f %s   |   Δ %+,.1f %s".format(a,unit,b,unit,b-a,unit))
}
