package org.avoperformance.horse.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.avoperformance.horse.core.engine.EquineResult
import org.avoperformance.horse.engine.EngineState
import org.avoperformance.horse.ui.components.*
import org.avoperformance.horse.ui.theme.AvoColors
import java.util.Locale
import kotlin.math.roundToInt

// Engine (AVO Equine Intelligence Engine) views added to the existing training screens.
// Every value comes from the engine result; missing values are shown as "—", never estimated here.

private val esE = Locale.forLanguageTag("es-ES")
private fun e0(v: Double?) = v?.takeIf { it.isFinite() }?.let { String.format(esE, "%.0f", it) }
private fun e1(v: Double?) = v?.takeIf { it.isFinite() }?.let { String.format(esE, "%.1f", it) }
private fun e2(v: Double?) = v?.takeIf { it.isFinite() }?.let { String.format(esE, "%.2f", it) }
private fun eTime(s: Double?) = s?.takeIf { it.isFinite() }?.let { val t = it.roundToInt(); "%d:%02d".format(t / 60, t % 60) }

/** Colours of the engine gait codes (0..6): same palette as the app's speed-based gaits plus the states. */
fun engineGaitColor(code: Int): Color = when (code) {
    0 -> Color(0xFF6E6F76); 1 -> Color(0xFF3D9BFF); 2 -> Color(0xFFFFC42C); 3 -> Color(0xFFED122A)
    4 -> Color(0xFFB07CFF); 5 -> Color(0xFF3A3B42); else -> Color(0xFF1E1F24)
}
fun engineGaitText(code: String) = when (code) {
    "STOPPED" -> "Parado"; "WALK" -> "Paso"; "TROT" -> "Trote"; "CANTER_GALLOP" -> "Galope"; "TRANSITION" -> "Transición"
    "UNKNOWN" -> "Desconocido"; "INSUFFICIENT_DATA" -> "Datos insuficientes"; else -> code
}
private fun qualityColor(q: String) = when (q) { "BUENA" -> AvoColors.Ok; "UTILIZABLE" -> AvoColors.Blue; "BAJA" -> AvoColors.Warn; "NO_UTILIZABLE" -> AvoColors.Bad; else -> AvoColors.Unknown }
private val eventText = mapOf(
    "INICIO_MOVIMIENTO" to "Inicio de movimiento", "PARADA" to "Parada", "ACELERACION_SOSTENIDA" to "Aceleración sostenida",
    "DESACELERACION_SOSTENIDA" to "Desaceleración sostenida", "INICIO_CURVA" to "Inicio de curva", "FIN_CURVA" to "Fin de curva",
    "TRANSICION_AIRE" to "Transición de aire", "CAMBIO_BRUSCO_CADENCIA" to "Cambio brusco de cadencia", "PERDIDA_REGULARIDAD" to "Pérdida de regularidad",
    "PERDIDA_CALIDAD_GNSS" to "Pérdida de calidad GNSS", "PERDIDA_SINCRONIZACION" to "Pérdida de sincronización",
)

@Composable
private fun EngRow(title: String, subtitle: String?, value: String, valueSub: String?, badgeColor: Color, onClick: (() -> Unit)?) {
    Row(Modifier.fillMaxWidth().padding(vertical = 3.dp).clip(RoundedCornerShape(12.dp)).background(AvoColors.Surface2)
        .let { if (onClick != null) it.clickable { onClick() } else it }.padding(10.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(10.dp).background(badgeColor, CircleShape)); Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Text(title, color = AvoColors.Text, fontWeight = FontWeight.Bold, fontSize = 14.sp)
            if (!subtitle.isNullOrBlank()) Text(subtitle, color = AvoColors.TextDim, fontSize = 12.sp)
        }
        Column(horizontalAlignment = Alignment.End) {
            Text(value, color = AvoColors.Text, fontWeight = FontWeight.Black, fontSize = 14.sp)
            if (valueSub != null) Text(valueSub, color = AvoColors.TextDim, fontSize = 12.sp)
        }
    }
}

/** Status / actions card: analyse, reprocess, cancel, errors. */
@Composable
fun EngineStatusCard(state: EngineState, onAnalyse: () -> Unit, onReprocess: () -> Unit, onCancel: () -> Unit) {
    AvoCard("Motor de análisis AVO") {
        when (state) {
            is EngineState.Idle -> { Button(onClick = onAnalyse, modifier = Modifier.fillMaxWidth()) { Text("ANALIZAR", fontWeight = FontWeight.Bold) } }
            is EngineState.Running -> {
                Text(if (state.reprocess) "Reprocesando la sesión…" else "Analizando la sesión…", color = AvoColors.Text)
                LinearProgressIndicator(Modifier.fillMaxWidth().padding(vertical = 8.dp), color = AvoColors.Red, trackColor = AvoColors.Surface2)
                OutlinedButton(onClick = onCancel, modifier = Modifier.fillMaxWidth()) { Text("Cancelar") }
            }
            is EngineState.Ready -> {
                val r = state.result
                KV("Motor", r.engine)
                KV("Procesado", r.processedAt.take(19).replace('T', ' '))
                KV("Resultado", when (r.cache) { "ACIERTO" -> "guardado (sin cambios)"; "RECALCULADO" -> "recalculado"; "CALCULADO" -> "calculado ahora"; else -> "—" })
                KV("Modo", if (r.mode == "REALTIME_ANALYSIS") "tiempo real" else "análisis completo (offline)")
                r.warnings.forEach { Note(it, AvoColors.Warn) }
                OutlinedButton(onClick = onReprocess, modifier = Modifier.fillMaxWidth().padding(top = 6.dp)) { Text("Reprocesar") }
            }
            is EngineState.Failed -> { Note("Error del motor: ${state.message}", AvoColors.Bad); Button(onClick = onAnalyse, modifier = Modifier.fillMaxWidth()) { Text("Reintentar") } }
            is EngineState.Cancelled -> { Note("Análisis cancelado.", AvoColors.Warn); Button(onClick = onAnalyse, modifier = Modifier.fillMaxWidth()) { Text("ANALIZAR", fontWeight = FontWeight.Bold) } }
            is EngineState.Unavailable -> Note(state.reason, AvoColors.Warn)
        }
    }
}

/** "Motor" tab content. [select] jumps to a GNSS time on the synchronised charts. */
fun LazyListScope.engineItems(state: EngineState, onAnalyse: () -> Unit, onReprocess: () -> Unit, onCancel: () -> Unit, select: (Double) -> Unit) {
    item { EngineStatusCard(state, onAnalyse, onReprocess, onCancel) }
    val r = (state as? EngineState.Ready)?.result ?: return
    // ---- GNSS summary
    item {
        AvoCard("Resumen GNSS") {
            val fix = if (r.rtk.totalS > 0) r.rtk.fixS / r.rtk.totalS * 100 else null
            MetricGrid(listOf(
                { m -> MetricTile("Distancia", e0(r.metric("distancia")?.value), "m", m) },
                { m -> MetricTile("Duración", eTime(r.metric("duracion")?.value), "", m) },
                { m -> MetricTile("V. media", e1(r.metric("velocidad_media")?.value?.times(3.6)), "km/h", m, AvoColors.Blue) },
                { m -> MetricTile("V. máxima", e1(r.metric("velocidad_maxima")?.value?.times(3.6)), "km/h", m, AvoColors.Red) },
                { m -> MetricTile("Acel. máx", e2(r.metric("aceleracion_maxima")?.value), "m/s²", m, AvoColors.Warn) },
                { m -> MetricTile("Desacel. máx", e2(r.metric("desaceleracion_maxima")?.value), "m/s²", m, AvoColors.Warn) },
                { m -> MetricTile("Lateral máx (est.)", e2(r.metric("aceleracion_lateral_maxima_estimada")?.value), "m/s²", m) },
                { m -> MetricTile("RTK FIX", e0(fix), "%", m, AvoColors.Ok) },
                { m -> MetricTile("Hasta FIX", eTime(r.rtk.timeToFixS), "", m) },
            ))
            KV("Pérdidas de FIX", "${r.rtk.fixLosses}")
            KV("Precisión H estimada (FIX)", r.rtk.hAccMedianFixM?.let { "${e2(it * 100)} cm (estimación del receptor)" })
            Note("Aceleraciones de la trayectoria GNSS (antena del jinete); no son aceleraciones medidas por la cincha.")
        }
    }
    // ---- quality
    item {
        AvoCard("Calidad de los datos") {
            r.quality.forEach { q ->
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 4.dp)) {
                    StatusPill(q.level, qualityColor(q.level)); Spacer(Modifier.width(8.dp))
                    Text(q.domain, color = AvoColors.Text, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                }
                q.reasons.forEach { Text("· $it", color = AvoColors.TextDim, fontSize = 12.sp) }
            }
        }
    }
    // ---- gaits and performance
    item {
        AvoCard("Aires detectados (${r.performance.classifier})") {
            val total = r.performance.segments.sumOf { it.durationS }.coerceAtLeast(1e-9)
            Row(Modifier.fillMaxWidth().height(16.dp).clip(RoundedCornerShape(8.dp))) {
                r.performance.segments.forEach { s -> Box(Modifier.weight((s.durationS / total).toFloat().coerceAtLeast(0.001f)).fillMaxHeight().background(engineGaitColor(codeIndex(s.code)))) }
            }
            Spacer(Modifier.height(6.dp))
            r.performance.perGait.forEach { g ->
                EngRow(engineGaitText(g.code), "${g.segments} tramos · ${e0(g.timeFraction * 100)} % del tiempo",
                    eTime(g.durationS) ?: "—", listOfNotNull(g.speedMean?.let { "${e1(it * 3.6)} km/h" }, g.cadenceHz?.let { "${e0(it * 60)} /min" }).joinToString(" · ").ifBlank { null },
                    engineGaitColor(codeIndex(g.code)), null)
            }
            Note("Clasificación inicial con umbrales sin validar en caballos reales. V2 se muestra para comparar; no se declara mejor que V1.")
            KV("V1 / V2", "${r.gaitV1.segments.size} / ${r.gaitV2.segments.size} segmentos")
        }
    }
    item {
        AvoCard("Rendimiento por tramo") {
            r.performance.segments.forEach { s ->
                EngRow("${engineGaitText(s.code)} · ${eTime(s.t0)}–${eTime(s.t1)}",
                    listOfNotNull(s.distanceM?.let { "${e0(it)} m" }, s.speedMax?.let { "máx ${e1(it * 3.6)} km/h" }, s.strideLengthM?.let { "tranco ${e2(it)} m" },
                        "GNSS ${s.gnssQuality.lowercase()} · IMU ${s.imuQuality.lowercase()}").joinToString(" · "),
                    s.speedMean?.let { "${e1(it * 3.6)} km/h" } ?: "—",
                    s.cadenceHz?.let { "${e0(it * 60)} /min ±${e1((s.cadenceSigmaHz ?: 0.0) * 60)}" } ?: if (s.warnings.any { it.contains("CINCHA") }) "SIN DATOS DE CINCHA" else null,
                    engineGaitColor(codeIndex(s.code))) { select((s.t0 + s.t1) / 2) }
            }
        }
    }
    // ---- cadence and regularity
    item {
        AvoCard("Cadencia y regularidad (cincha)") {
            if (!r.hasImu) { Note("SIN DATOS DE CINCHA", AvoColors.Warn); return@AvoCard }
            r.performance.segments.filter { it.cadenceHz != null }.forEach { s ->
                KV(engineGaitText(s.code) + " " + eTime(s.t0), "${e0(s.cadenceHz!! * 60)} /min · CV intervalos ${e2(s.intervalCv) ?: "—"} · corr. ciclos ${e2(s.cycleCorr) ?: "—"} · estab. espectral ${e2(s.spectralStability) ?: "—"}")
            }
            r.fusion.relations.filter { it.y == "cadencia_hz" && it.slope != null }.forEach { rel ->
                KV("Cadencia vs velocidad (${rel.gait})", "${e2(rel.slope!! * 60)} /min por m/s · r ${e2(rel.r)} · n ${rel.n}")
            }
            Note("Métricas independientes; no se combinan en una puntuación. Amplitudes sin calibrar.")
        }
    }
    // ---- curves
    item {
        AvoCard("Curvas") {
            if (r.curves.isEmpty()) Note("Sin curvas fiables (radio < 40 m, giro ≥ 30°, velocidad ≥ 2 m/s).")
            r.curves.forEach { cv ->
                EngRow("Curva ${cv.id} · ${cv.direction.lowercase()} · ${e0(kotlin.math.abs(cv.headingDeg))}°",
                    "R ${e1(cv.radiusM)} ± ${e1(cv.radiusSigmaM)} m · lateral ${e2(cv.latAccMean)} ± ${e2(cv.latAccSigma)} m/s² (est.)" +
                        (cv.cadenceDuringHz?.let { " · cadencia ${e0(it * 60)} /min" } ?: ""),
                    "${e1(cv.vEntry * 3.6)} → ${e1(cv.vExit * 3.6)}", "km/h entrada → salida", qualityColor(cv.quality)) { select(cv.t0) }
            }
        }
    }
    // ---- events
    item {
        AvoCard("Eventos") {
            if (r.events.isEmpty()) Note("Sin eventos detectados.")
            r.events.forEach { ev ->
                EngRow(eventText[ev.type] ?: ev.type, "${ev.id} · ${ev.reason}", eTime(ev.t0) ?: "—", if (ev.t1 > ev.t0 + 0.5) "hasta ${eTime(ev.t1)}" else null, qualityColor(ev.quality)) { select(ev.t0) }
            }
        }
    }
    // ---- exploratory symmetry
    item {
        AvoCard("Simetría exploratoria") {
            Text(r.symmetry.label, color = AvoColors.TextDim, fontSize = 11.sp, fontWeight = FontWeight.Bold)
            r.symmetry.controls.forEach { (ctl, st, why) -> KV(ctl, "$st · $why", when (st) { "OK" -> AvoColors.Ok; "BLOQUEA" -> AvoColors.Bad; else -> AvoColors.Warn }) }
            if (!r.symmetry.allowed) Note("No hay datos suficientes para describir diferencias reproducibles.", AvoColors.Warn)
            else r.symmetry.groups.filter { it.gait == "TODOS" }.forEach { g ->
                KV("IMU ${g.imu} · ${g.windows} ventanas", "amplitud ${e2(g.ampLogRatio.median)}${if (g.ampLogRatio.reproducible) " (reproducible)" else ""} · temporal ${e2(g.timingAsym.median)}${if (g.timingAsym.reproducible) " (reproducible)" else ""}")
            }
            r.symmetry.notes.forEach { Note(it) }
        }
    }
}

internal fun codeIndex(code: String) = when (code) { "STOPPED" -> 0; "WALK" -> 1; "TROT" -> 2; "CANTER_GALLOP" -> 3; "TRANSITION" -> 4; "UNKNOWN" -> 5; else -> 6 }

/** Engine values at the selected instant (synchronised with the map and the charts). */
@Composable
fun EngineInstantCard(r: EquineResult, t: Double?) {
    AvoCard("Motor en el instante") {
        if (t == null) { Note("Toca una gráfica o el mapa para seleccionar un instante."); return@AvoCard }
        val s = r.series
        val gait = r.gaitAt(t)
        val k = r.girthAt(t)
        val g = r.girth
        MetricGrid(listOf(
            { m -> MetricTile("Tiempo", eTime(t), "", m) },
            { m -> MetricTile("Velocidad", s?.let { e1(r.gnssAt(it.speed, t) * 3.6) }, "km/h", m, AvoColors.Red) },
            { m -> MetricTile("Aceleración", s?.let { e2(r.gnssAt(it.accel, t)) }, "m/s²", m, AvoColors.Warn) },
            { m -> MetricTile("Lateral (est.)", s?.let { e2(r.gnssAt(it.latAccel, t)) }, "m/s²", m) },
            { m -> MetricTile("Aire", gait?.let { engineGaitText(it.code) }, "", m, gait?.let { engineGaitColor(codeIndex(it.code)) } ?: AvoColors.Text) },
            { m -> MetricTile("Cadencia", if (!r.hasImu) "SIN DATOS" else k?.let { e0(g!!.cadenceHz[it] * 60) }, if (r.hasImu) "/min" else "", m, AvoColors.Cyan) },
            { m -> MetricTile("Tranco", k?.let { e2(g!!.strideLengthM[it]) }, "m", m) },
            { m -> MetricTile("Corr. ciclos", k?.let { e2(g!!.cycleCorr[it]) }, "", m) },
            { m -> MetricTile("Estado cincha", if (!r.hasImu) "SIN DATOS DE CINCHA" else k?.let { g!!.status[it] } ?: "sin ventana", "", m) },
        ))
    }
}

/** Gait strip aligned with the app charts (one code per track point). */
@Composable
fun EngineGaitStrip(codes: List<Int>, sel: Int?, first: Int, end: Int, onSelect: (Int) -> Unit) {
    if (codes.isEmpty()) return
    Text("AIRE (MOTOR)", color = AvoColors.Silver, fontSize = 11.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 12.dp, bottom = 4.dp))
    Canvas(Modifier.fillMaxWidth().height(22.dp).clip(RoundedCornerShape(6.dp)).background(AvoColors.Surface2)
        .pointerInput(codes, first, end) { detectTapGestures { pos -> onSelect((first + (pos.x / size.width * (end - first)).roundToInt()).coerceIn(0, codes.lastIndex)) } }) {
        val span = (end - first).coerceAtLeast(1)
        val w = size.width / span
        for (i in first until end.coerceAtMost(codes.lastIndex)) {
            val c = codes[i]; if (c < 0) continue
            drawRect(engineGaitColor(c), Offset(size.width * (i - first) / span, 0f), Size(w + 1f, size.height))
        }
        sel?.takeIf { it in first..end }?.let { drawLine(Color.White, Offset(size.width * (it - first) / span, 0f), Offset(size.width * (it - first) / span, size.height), 2f) }
    }
}
