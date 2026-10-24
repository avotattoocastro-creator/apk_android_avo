package org.avoperformance.horse.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.avoperformance.horse.AppContainer
import org.avoperformance.horse.core.raw.Gait
import org.avoperformance.horse.core.raw.Insights
import org.avoperformance.horse.core.raw.TrainingAnalysis
import org.avoperformance.horse.core.raw.TrainingInsights
import org.avoperformance.horse.core.sync.SyncRules
import org.avoperformance.horse.core.sync.SyncState
import org.avoperformance.horse.maps.AvoImagery
import org.avoperformance.horse.tide.TideRepository
import org.avoperformance.horse.ui.components.*
import org.avoperformance.horse.ui.theme.AvoColors
import org.osmdroid.events.MapEventsReceiver
import org.osmdroid.tileprovider.MapTileProviderBasic
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.util.BoundingBox
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.MapEventsOverlay
import org.osmdroid.views.overlay.Marker
import org.osmdroid.views.overlay.Polyline
import org.osmdroid.views.overlay.TilesOverlay
import java.util.Locale
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.roundToInt
import org.osmdroid.util.GeoPoint as OsmPoint

private val esL = Locale.forLanguageTag("es-ES")
private fun f1(v: Double?) = v?.takeIf { it.isFinite() }?.let { String.format(esL, "%.1f", it) }
private fun f2(v: Double?) = v?.takeIf { it.isFinite() }?.let { String.format(esL, "%.2f", it) }
private fun f0(v: Double?) = v?.takeIf { it.isFinite() }?.let { String.format(esL, "%.0f", it) }
private fun pct(n: Int, d: Int) = if (d > 0) "${n * 100 / d} %" else "—"
private fun mmss(s: Double?) = s?.takeIf { it.isFinite() }?.let { val t = it.roundToInt(); if (t >= 3600) "%d:%02d:%02d".format(t / 3600, t / 60 % 60, t % 60) else "%d:%02d".format(t / 60, t % 60) }

enum class TrackColor(val texto: String) { SPEED("Velocidad"), GAIT("Aire"), RTK("RTK") }
enum class MapStyle(val texto: String) { MAP("Mapa"), SATELLITE("Satélite"), HYBRID("Híbrido") }

fun gaitColor(g: Gait) = when (g) {
    Gait.STOPPED -> Color(0xFF6E6F76); Gait.WALK -> Color(0xFF3D9BFF); Gait.TROT -> Color(0xFFFFC42C); Gait.GALLOP -> Color(0xFFED122A)
}
private fun speedColor(fraction: Float): Color {
    // blue → cyan → yellow → red, same scale on map and charts
    val f = fraction.coerceIn(0f, 1f)
    return when {
        f < 0.33f -> lerpC(Color(0xFF2F6BFF), Color(0xFF35D0E8), f / 0.33f)
        f < 0.66f -> lerpC(Color(0xFF35D0E8), Color(0xFFFFC42C), (f - 0.33f) / 0.33f)
        else -> lerpC(Color(0xFFFFC42C), Color(0xFFED122A), (f - 0.66f) / 0.34f)
    }
}
private fun lerpC(a: Color, b: Color, t: Float) = Color(a.red + (b.red - a.red) * t, a.green + (b.green - a.green) * t, a.blue + (b.blue - a.blue) * t, 1f)
private fun Color.argb() = android.graphics.Color.argb((alpha * 255).toInt(), (red * 255).toInt(), (green * 255).toInt(), (blue * 255).toInt())

@Composable
fun TrainingDetailScreen(c: AppContainer, id: String) {
    val t by c.db.trainings().observe(id).collectAsStateWithLifecycle(null)
    val horses by c.db.horses().all().collectAsStateWithLifecycle(emptyList())
    val riders by c.db.riders().all().collectAsStateWithLifecycle(emptyList())
    var analysis by remember { mutableStateOf<TrainingAnalysis?>(null) }
    var insights by remember { mutableStateOf<Insights?>(null) }
    var loading by remember { mutableStateOf(false) }
    var msg by remember { mutableStateOf<String?>(null) }
    var confirmDelete by remember { mutableStateOf(false) }
    var shareOpen by remember { mutableStateOf(false) }
    if (shareOpen) ShareDialog(c, id, onDismiss = { shareOpen = false })
    val marine by c.db.marine().observe(id).collectAsStateWithLifecycle(null)
    val scope = rememberCoroutineScope()
    var marineBusy by remember { mutableStateOf(false) }
    var marineMessage by remember { mutableStateOf<String?>(null) }
    val tt = t
    val engineStates by c.equine.all.collectAsStateWithLifecycle()
    val engine = engineStates[id] ?: org.avoperformance.horse.engine.EngineState.Idle
    val eng = (engine as? org.avoperformance.horse.engine.EngineState.Ready)?.result
    LaunchedEffect(tt?.localDir, tt?.downloadedBytes, tt?.state) {
        if (tt?.localDir != null && (tt.state == SyncState.VERIFICADO_LOCAL.name || tt.state == SyncState.PENDIENTE_SERVIDOR.name ||
                tt.state == SyncState.VERIFICADO_SERVIDOR.name || tt.state == SyncState.MARCADO_EN_RELOJ.name || tt.state == SyncState.DESCARGADO.name)) {
            loading = true
            analysis = withContext(Dispatchers.IO) { runCatching { c.sync.analysisFor(tt) }.getOrNull() }
            insights = analysis?.takeIf { it.track.size >= 2 }?.let { a -> withContext(Dispatchers.Default) { runCatching { TrainingInsights.compute(a) }.getOrNull() } }
            loading = false
            if (analysis != null) c.equine.open(tt)   // engine analysis in the background (stored, reused, cancellable)
        }
    }
    if (tt == null) { Note("Entrenamiento no encontrado"); return }
    val st = runCatching { SyncState.valueOf(tt.state) }.getOrNull()
    val a = analysis
    val ins = insights
    var sel by remember(id) { mutableStateOf<Int?>(null) }
    var playing by remember(id) { mutableStateOf(false) }
    var segStart by remember(id) { mutableIntStateOf(0) }
    var segEnd by remember(id) { mutableIntStateOf(Int.MAX_VALUE) }
    var tab by remember(id) { mutableIntStateOf(0) }
    var mapStyle by remember(id) { mutableStateOf(MapStyle.HYBRID) }
    var trackColor by remember(id) { mutableStateOf(TrackColor.SPEED) }
    var recenter by remember(id) { mutableIntStateOf(0) }
    val ctx = androidx.compose.ui.platform.LocalContext.current
    val segPrefs = remember(ctx) { ctx.getSharedPreferences("avo_training_segments", android.content.Context.MODE_PRIVATE) }
    var savedSegments by remember(id) { mutableStateOf(segPrefs.getString("segments_$id", "[]") ?: "[]") }
    var segLabel by remember(id) { mutableStateOf("") }
    val savedItems = remember(savedSegments) {
        runCatching {
            val arr = org.json.JSONArray(savedSegments)
            (0 until arr.length()).map { arr.getJSONObject(it) }.map { Triple(it.optString("name", "Tramo"), it.getInt("start"), it.getInt("end")) }
        }.getOrDefault(emptyList())
    }
    LaunchedEffect(playing, a) {
        while (playing && a != null && a.track.isNotEmpty()) {
            delay(200)
            val next = ((sel ?: 0) + 1).coerceAtMost(a.track.lastIndex)
            sel = next
            if (next == a.track.lastIndex) playing = false
        }
    }
    val horse = horses.firstOrNull { it.code == tt.horseCode }
    val rider = riders.firstOrNull { it.code == tt.riderCode }
    val last = (a?.track?.lastIndex ?: 1).coerceAtLeast(1)
    val s0 = segStart.coerceIn(0, last - 1)
    val s1 = segEnd.coerceIn(s0 + 1, last)
    fun pick(i: Int) { sel = i; playing = false }
    val engineTimes = remember(a, eng) { if (a == null || eng == null) emptyList() else a.track.map { eng.timeOfItow(it.itowMs) } }
    fun pickTime(t: Double) {
        if (engineTimes.isEmpty()) return
        var best = 0; var bd = Double.MAX_VALUE
        engineTimes.forEachIndexed { i, x -> if (x != null && abs(x - t) < bd) { bd = abs(x - t); best = i } }
        pick(best); tab = 1
    }

    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 16.dp)) {
        // Header
        item {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                HorsePhoto(horse?.photoPath, Modifier.size(58.dp))
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text((horse?.name ?: tt.horseCode ?: "Sin caballo").uppercase(), color = AvoColors.Text, fontSize = 20.sp, fontWeight = FontWeight.Black)
                    Text(listOfNotNull(Fmt.date(tt.startRtcMs), rider?.name ?: tt.riderCode).joinToString(" · "), color = AvoColors.TextDim, fontSize = 13.sp)
                }
                StatusPill(st?.texto?.substringBefore(" (")?.take(18) ?: tt.state, syncColor(st))
            }
            Segmented(listOf("Resumen", "Mapa y gráficas", "Datos", "Motor"), tab, { tab = it }, Modifier.padding(horizontal = 12.dp, vertical = 4.dp))
            if (loading) androidx.compose.material3.LinearProgressIndicator(Modifier.fillMaxWidth().padding(top = 6.dp), color = AvoColors.Red, trackColor = AvoColors.Surface2)
        }
        if (a == null && !loading) item {
            AvoCard { KV("Duración (reloj)", Fmt.duration(tt.activeMs)); KV("Análisis", "Disponible al descargar el entrenamiento") }
        }

        // ───────────── RESUMEN ─────────────
        if (tab == 0 && tt.localDir != null) item {
            AvoCard("Compartir", trailing = { Button(onClick = { shareOpen = true }) { Text("COMPARTIR", fontWeight = FontWeight.Bold) } }) {
                ShareStatusLine(c, tt.sessionId)
            }
        }
        if (tab == 0 && a != null) {
            item {
                AvoCard("Resumen") {
                    MetricGrid(listOf(
                        { m -> MetricTile("Distancia", f2(a.distanceM / 1000), "km", m) },
                        { m -> MetricTile("Tiempo", mmss(a.durationS) ?: Fmt.duration(tt.activeMs), "", m) },
                        { m -> MetricTile("En movimiento", mmss(ins?.movingSeconds), "", m) },
                        { m -> MetricTile("V. media", f1(a.avgSpeedMs?.times(3.6)), "km/h", m, AvoColors.Blue) },
                        { m -> MetricTile("V. máxima", f1(a.maxSpeedMs * 3.6), "km/h", m, AvoColors.Red) },
                        { m -> MetricTile("Ritmo", a.avgSpeedMs?.takeIf { it > 0.5 }?.let { mmss(1000 / it) }, "/km", m) },
                        { m -> MetricTile("Acel. máx", f2(ins?.maxAccelG), "g", m, AvoColors.Warn) },
                        { m -> MetricTile("Frenada máx", f2(ins?.maxDecelG?.let { abs(it) }), "g", m, AvoColors.Warn) },
                        { m -> MetricTile("Cadencia máx", f0(ins?.cadenceMax), "/min", m, AvoColors.Cyan) },
                        { m -> MetricTile("Desnivel +", f0(ins?.gainM), "m", m) },
                        { m -> MetricTile("Desnivel −", f0(ins?.lossM), "m", m) },
                        { m -> MetricTile("RTK FIX", pct(a.fixEpochs, a.gnssUsable), "", m, AvoColors.Ok) },
                    ))
                }
            }
            if (a.track.size >= 2) item {
                AvoCard("Recorrido") {
                    MapControls(mapStyle, { mapStyle = it }, trackColor, { trackColor = it }) { recenter++ }
                    Spacer(Modifier.height(8.dp))
                    RealTrackMap(a, sel, 0, a.track.lastIndex, trackColor, mapStyle, recenter, 280, ::pick)
                    MapLegend(a, trackColor, mapStyle)
                }
            }
            ins?.let { i ->
                item { GaitCard(i) }
                if (i.efforts.isNotEmpty()) item {
                    AvoCard("Tramos rápidos") {
                        i.efforts.sortedByDescending { it.maxSpeedMs }.take(6).forEachIndexed { n, e ->
                            ListRow(
                                badge = "${n + 1}", badgeColor = AvoColors.Red,
                                title = "${f0(e.distanceM)} m · ${mmss(e.durationS)}",
                                subtitle = "desde ${mmss(i.timeS.getOrNull(e.startIdx))}",
                                value = "${f1(e.maxSpeedMs * 3.6)} km/h", valueSub = "media ${f1(e.avgSpeedMs * 3.6)}",
                            ) { segStart = e.startIdx; segEnd = e.endIdx; pick(e.startIdx); tab = 1 }
                        }
                    }
                }
                if (i.events.isNotEmpty()) item {
                    AvoCard("Eventos") {
                        i.events.forEach { ev ->
                            ListRow(
                                badge = when (ev.kind.name) { "START" -> "▶"; "FINISH" -> "■"; "MAX_SPEED" -> "⚡"; "FIRST_GALLOP" -> "🐎"; else -> "⚑" },
                                badgeColor = if (ev.kind.name == "MAX_SPEED") AvoColors.Red else AvoColors.Surface2,
                                title = ev.kind.texto, subtitle = mmss(ev.timeS) ?: "",
                                value = ev.value?.let { "${f1(it * 3.6)} km/h" } ?: "", valueSub = null,
                            ) { pick(ev.index); tab = 1 }
                        }
                    }
                }
                if (i.splits.isNotEmpty()) item {
                    AvoCard("Parciales · ${f0(i.splitUnitM)} m") {
                        val best = i.splits.maxOf { it.avgSpeedMs }
                        i.splits.forEach { sp ->
                            Row(Modifier.fillMaxWidth().padding(vertical = 3.dp), verticalAlignment = Alignment.CenterVertically) {
                                Text("${sp.number}", color = AvoColors.TextDim, fontWeight = FontWeight.Bold, modifier = Modifier.width(26.dp))
                                Box(Modifier.weight(1f).height(18.dp).clip(RoundedCornerShape(6.dp)).background(AvoColors.Surface2)) {
                                    Box(Modifier.fillMaxHeight().fillMaxWidth((sp.avgSpeedMs / best).toFloat().coerceIn(0.05f, 1f))
                                        .background(if (sp.avgSpeedMs == best) AvoColors.Red else AvoColors.Blue.copy(alpha = 0.7f), RoundedCornerShape(6.dp)))
                                }
                                Text(mmss(sp.durationS) ?: "—", color = AvoColors.Text, fontWeight = FontWeight.Bold, modifier = Modifier.width(56.dp).padding(start = 8.dp))
                                Text("${f1(sp.avgSpeedMs * 3.6)}", color = AvoColors.TextDim, fontSize = 13.sp, modifier = Modifier.width(40.dp))
                            }
                        }
                    }
                }
            }
            item { ConditionsCard(marine, marineBusy, marineMessage, tt.startRtcMs > 0L) {
                marineBusy = true
                scope.launch {
                    try {
                        c.db.marine().upsert(marineSnapshotForTraining(c.tides, c.settings, tt.sessionId, tt.startRtcMs))
                        marineMessage = null
                    } catch (e: Exception) { marineMessage = e.message ?: "Error al consultar" } finally { marineBusy = false }
                }
            } }
        }

        // ───────────── MAPA Y GRÁFICAS ─────────────
        if (tab == 1 && a != null && a.track.size >= 2) {
            item {
                AvoCard("Mapa") {
                    MapControls(mapStyle, { mapStyle = it }, trackColor, { trackColor = it }) { recenter++ }
                    Spacer(Modifier.height(8.dp))
                    RealTrackMap(a, sel, s0, s1, trackColor, mapStyle, recenter, 340, ::pick)
                    MapLegend(a, trackColor, mapStyle)
                    Spacer(Modifier.height(8.dp))
                    PlaybackBar(a, ins, sel, playing, { playing = it }, ::pick)
                }
            }
            item {
                AvoCard("Gráficas sincronizadas") {
                    val x = ins?.timeS?.toList() ?: a.track.map { (it.itowMs - a.track.first().itowMs) / 1000.0 }
                    var zoom by remember(id) { mutableStateOf(1f) }
                    var center by remember(id) { mutableStateOf(0.5f) }
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        SmallBtn("＋") { zoom = (zoom * 1.6f).coerceAtMost(25f) }
                        SmallBtn("－") { zoom = (zoom / 1.6f).coerceAtLeast(1f) }
                        SmallBtn("Todo") { zoom = 1f; center = 0.5f }
                        if (s0 > 0 || s1 < last) SmallBtn("Tramo A–B") { zoom = (a.track.size.toFloat() / (s1 - s0 + 1)).coerceIn(1f, 25f); center = ((s0 + s1) / 2f) / last }
                    }
                    val win = ChartWindow(a.track.size, zoom, center)
                    val drag: (Float) -> Unit = { dx -> center = (center - dx / zoom).coerceIn(0f, 1f) }
                    ChartBlock("Velocidad", "km/h", a.track.map { it.speedMs * 3.6 }, sel, win, AvoColors.Red, x, drag, ::pick, fill = true)
                    ins?.let { i ->
                        ChartBlock("Aceleración", "g", i.accelMs2.map { it / TrainingInsights.G }, sel, win, AvoColors.Warn, x, drag, ::pick, signed = true)
                        if (i.cadence.any { it.isFinite() }) ChartBlock("Cadencia (IMU cincha)", "/min", i.cadence.toList(), sel, win, AvoColors.Cyan, x, drag, ::pick)
                        if (i.altM.any { it.isFinite() }) ChartBlock("Altitud", "m", i.altM.toList(), sel, win, AvoColors.Silver, x, drag, ::pick, fill = true)
                    }
                    ChartBlock("Precisión horizontal", "m", a.track.map { it.hAccM }, sel, win, AvoColors.Ok, x, drag, ::pick)
                    // ---- engine series aligned to the same track points (same selection, zoom and window)
                    eng?.let { r ->
                        val times = engineTimes
                        r.series?.let { es ->
                            ChartBlock("Aceleración longitudinal (motor)", "m/s²", r.alignGnss(es.accel, times), sel, win, AvoColors.Warn, x, drag, ::pick, signed = true)
                            ChartBlock("Aceleración lateral estimada (motor)", "m/s²", r.alignGnss(es.latAccel, times), sel, win, AvoColors.Silver, x, drag, ::pick, signed = true)
                            EngineGaitStrip(times.map { tt2 -> tt2?.let { r.gaitAt(it)?.code?.let(::codeIndex) } ?: -1 }, sel, win.first, win.end, ::pick)
                        }
                        val g = r.girth
                        if (!r.hasImu || g == null) Note("SIN DATOS DE CINCHA", AvoColors.Warn)
                        else {
                            ChartBlock("Cadencia (motor, cincha)", "/min", r.alignGirth(g.cadenceHz, times).map { it * 60 }, sel, win, AvoColors.Cyan, x, drag, ::pick)
                            ChartBlock("Correlación entre ciclos (motor)", "", r.alignGirth(g.cycleCorr, times), sel, win, AvoColors.Blue, x, drag, ::pick)
                        }
                    }
                }
            }
            eng?.let { r -> item { EngineInstantCard(r, sel?.let { engineTimes.getOrNull(it) }) } }
            item {
                AvoCard("Tramo A–B") {
                    KV("Inicio A", "${mmss(ins?.timeS?.getOrNull(s0))} · punto ${s0 + 1}")
                    Slider(value = s0.toFloat(), onValueChange = { segStart = it.roundToInt().coerceIn(0, s1 - 1) }, valueRange = 0f..(last - 1).toFloat(), colors = sliderColors())
                    KV("Final B", "${mmss(ins?.timeS?.getOrNull(s1))} · punto ${s1 + 1}")
                    Slider(value = s1.toFloat(), onValueChange = { segEnd = it.roundToInt().coerceIn(s0 + 1, last) }, valueRange = 1f..last.toFloat(), colors = sliderColors())
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        SmallBtn("A = punto") { sel?.let { segStart = it.coerceIn(0, s1 - 1) } }
                        SmallBtn("B = punto") { sel?.let { segEnd = it.coerceIn(s0 + 1, last) } }
                        SmallBtn("Todo") { segStart = 0; segEnd = Int.MAX_VALUE }
                    }
                    val portion = a.track.subList(s0, s1 + 1)
                    val dur = ((portion.last().itowMs - portion.first().itowMs) / 1000.0).coerceAtLeast(0.0)
                    val dist = ins?.let { it.distM[s1] - it.distM[s0] }
                    val spd = portion.map { it.speedMs }.filter { it.isFinite() && it >= 0.0 }
                    val acc = ins?.accelMs2?.toList()?.subList(s0, s1 + 1)
                    Spacer(Modifier.height(6.dp))
                    MetricGrid(listOf(
                        { m -> MetricTile("Duración", mmss(dur), "", m) },
                        { m -> MetricTile("Distancia", f0(dist), "m", m) },
                        { m -> MetricTile("V. media", if (dur > 0 && dist != null) f1(dist / dur * 3.6) else null, "km/h", m, AvoColors.Blue) },
                        { m -> MetricTile("V. máx", f1(spd.maxOrNull()?.times(3.6)), "km/h", m, AvoColors.Red) },
                        { m -> MetricTile("Acel. máx", f2(acc?.maxOrNull()?.div(TrainingInsights.G)), "g", m, AvoColors.Warn) },
                        { m -> MetricTile("RTK FIX", pct(portion.count { it.carrSoln == 2 }, portion.size), "", m, AvoColors.Ok) },
                    ))
                    OutlinedTextField(segLabel, { segLabel = it.take(64) }, label = { Text("Nombre del tramo") }, singleLine = true, modifier = Modifier.fillMaxWidth().padding(top = 6.dp))
                    Button(onClick = {
                        val arr = runCatching { org.json.JSONArray(savedSegments) }.getOrElse { org.json.JSONArray() }
                        arr.put(org.json.JSONObject().put("name", segLabel.ifBlank { "Tramo ${arr.length() + 1}" }).put("start", s0).put("end", s1))
                        savedSegments = arr.toString(); segPrefs.edit().putString("segments_$id", savedSegments).apply(); segLabel = ""
                    }, modifier = Modifier.fillMaxWidth()) { Text("GUARDAR TRAMO", fontWeight = FontWeight.Bold) }
                    savedItems.forEachIndexed { idx, s ->
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            Text("${s.first} · ${s.second + 1}–${s.third + 1}", color = AvoColors.Text, modifier = Modifier.weight(1f).clickable {
                                segStart = s.second.coerceIn(0, last - 1); segEnd = s.third.coerceIn(segStart + 1, last)
                            }.padding(vertical = 8.dp))
                            androidx.compose.material3.TextButton(onClick = {
                                val arr = org.json.JSONArray()
                                savedItems.forEachIndexed { i2, it -> if (i2 != idx) arr.put(org.json.JSONObject().put("name", it.first).put("start", it.second).put("end", it.third)) }
                                savedSegments = arr.toString(); segPrefs.edit().putString("segments_$id", savedSegments).apply()
                            }) { Text("Quitar", color = AvoColors.Bad) }
                        }
                    }
                }
            }
        }

        // ───────────── DATOS ─────────────
        if (tab == 2) {
            if (a != null) {
                item {
                    AvoCard("GNSS / RTK") {
                        val n = a.gnssUsable.coerceAtLeast(1)
                        Row(Modifier.fillMaxWidth().height(14.dp).clip(RoundedCornerShape(7.dp))) {
                            listOf(a.fixEpochs to AvoColors.Ok, a.floatEpochs to AvoColors.Warn, a.autonomousEpochs to AvoColors.Blue, a.noFix to AvoColors.Bad).forEach { (k, col) ->
                                if (k > 0) Box(Modifier.weight(k.toFloat()).fillMaxHeight().background(col))
                            }
                        }
                        Spacer(Modifier.height(8.dp))
                        MetricGrid(listOf(
                            { m -> MetricTile("FIX", pct(a.fixEpochs, n), "", m, AvoColors.Ok) },
                            { m -> MetricTile("FLOAT", pct(a.floatEpochs, n), "", m, AvoColors.Warn) },
                            { m -> MetricTile("Autónomo", pct(a.autonomousEpochs, n), "", m, AvoColors.Blue) },
                            { m -> MetricTile("Satélites", f1(ins?.avgSatellites), "", m) },
                            { m -> MetricTile("Precisión H", f2(ins?.avgHAccM), "m", m) },
                            { m -> MetricTile("Precisión V", f2(ins?.avgVAccM), "m", m) },
                        ))
                        KV("Frecuencia", "${a.navRateHz} Hz")
                        KV("Muestras válidas", "${a.gnssUsable} de ${a.gnssSamples}")
                        KV("Épocas sin solución", "${a.noFix}")
                        KV("Tiempo en FIX / FLOAT", "${mmss(a.fixTimeS) ?: "—"} / ${mmss(a.floatTimeS) ?: "—"}")
                    }
                }
                item {
                    AvoCard("IMU cincha") {
                        MetricGrid(listOf(
                            { m -> MetricTile("Muestras", if (a.imuAvailable) a.imuSamples.toString() else null, "", m) },
                            { m -> MetricTile("Cadencia media", f0(ins?.cadenceMean), "/min", m, AvoColors.Cyan) },
                            { m -> MetricTile("Cadencia máx", f0(ins?.cadenceMax), "/min", m, AvoColors.Cyan) },
                        ))
                        KV("Lotes", "${a.imuBatches}")
                        KV("Sensores", a.imuIds.sorted().joinToString { when (it) { 0 -> "central"; 1 -> "izquierdo"; 2 -> "derecho"; else -> "#$it" } }.ifBlank { null })
                        KV("Tramas UART erróneas", "${a.badUartFrames}", if (a.badUartFrames > 0) AvoColors.Warn else AvoColors.Text)
                    }
                }
                item {
                    AvoCard("Velocidad y tramos") {
                        val speeds = a.track.map { it.speedMs }.filter { it > 0.5 && it.isFinite() }
                        val mean = speeds.average().takeIf { !it.isNaN() && it > 0 } ?: 0.0
                        val variation = if (speeds.size >= 3 && mean > 0) kotlin.math.sqrt(speeds.map { (it - mean) * (it - mean) }.average()) / mean * 100 else null
                        KV("Velocidad media", a.avgSpeedMs?.let { "${f1(it * 3.6)} km/h" })
                        KV("Velocidad máxima", "${f1(a.maxSpeedMs * 3.6)} km/h")
                        KV("Ritmo medio", a.avgSpeedMs?.takeIf { it > 0.5 }?.let { "${f1(100.0 / it)} s/100 m" })
                        KV("Variación de velocidad", variation?.let { "${f1(it)} %" })
                        KV("Marcadores", "${a.markers}")
                        Spacer(Modifier.height(6.dp))
                        val first = a.track.first().itowMs; val lastT = a.track.last().itowMs
                        var w = first
                        while (w < lastT) {
                            val win = a.track.filter { it.itowMs in w until w + 30_000 }
                            if (win.isNotEmpty()) KV("${(w - first) / 1000}–${(w - first) / 1000 + 30} s", "${f1(win.map { it.speedMs }.average() * 3.6)} · máx ${f1((win.maxOfOrNull { it.speedMs } ?: 0.0) * 3.6)} km/h")
                            w += 30_000
                        }
                    }
                }
                ins?.let { i ->
                    item {
                        AvoCard("Pendiente y altitud") {
                            MetricGrid(listOf(
                                { m -> MetricTile("Alt. máx", f0(i.altMaxM), "m", m) },
                                { m -> MetricTile("Alt. mín", f0(i.altMinM), "m", m) },
                                { m -> MetricTile("Desnivel +", f0(i.gainM), "m", m) },
                                { m -> MetricTile("Desnivel −", f0(i.lossM), "m", m) },
                                { m -> MetricTile("Pend. máx", f1(i.slopeMaxPct), "%", m, AvoColors.Red) },
                                { m -> MetricTile("Pend. mín", f1(i.slopeMinPct), "%", m, AvoColors.Blue) },
                            ))
                            KV("Pendiente media (abs.)", i.slopeMeanAbsPct?.let { "${f1(it)} %" })
                        }
                    }
                }
            }
            item {
                AvoCard("Fichero") {
                    KV("Sesión", tt.sessionId)
                    KV("Inicio", Fmt.date(tt.startRtcMs))
                    KV("Caballo / jinete", listOfNotNull(tt.horseCode, tt.riderCode).joinToString(" / ").ifBlank { null })
                    KV("Tiempo activo (reloj)", Fmt.duration(tt.activeMs))
                    KV("Tamaño", Fmt.bytes(tt.totalBytes))
                    KV("SHA-256 local", tt.localSha256?.take(16)?.plus("…"))
                    KV("SHA-256 del reloj", tt.watchSha256?.take(16)?.plus("…"))
                    KV("Servidor", if (tt.serverSha256 != null) "verificado" else if (c.sync.serverConfigured) "pendiente" else "no configurado")
                    a?.let {
                        KV("Cierre", if (it.scan.cleanClose) "limpio" else "recuperado", if (it.scan.cleanClose) AvoColors.Ok else AvoColors.Warn)
                        if (it.scan.tailGarbage) KV("Último bloque", "incompleto (ignorado)", AvoColors.Warn)
                    }
                    msg?.let { Note(it, AvoColors.Warn) }
                    Spacer(Modifier.height(6.dp))
                    OutlinedButton(enabled = SyncRules.canOfferDelete(org.avoperformance.horse.core.sync.LocalTraining(tt.sessionId, tt.segments, tt.totalBytes,
                        tt.downloadedBytes, tt.localSha256, tt.watchSha256, tt.serverSha256, st ?: SyncState.EN_RELOJ,
                        org.avoperformance.horse.core.ble.WatchFileState.UNKNOWN, tt.startRtcMs, tt.activeMs)), onClick = { confirmDelete = true }) {
                        Text("Borrar del reloj")
                    }
                }
            }
        }

        // ───────────── MOTOR ─────────────
        if (tab == 3) engineItems(engine, onAnalyse = { c.equine.open(tt) }, onReprocess = { c.equine.open(tt, reprocess = true) },
            onCancel = { c.equine.cancel(tt.sessionId) }, select = ::pickTime)
    }
    if (confirmDelete) ConfirmDialog("Borrar del reloj", "Se borrará ${tt.sessionId} de la tarjeta del chaleco. La copia del teléfono se conserva.", "Borrar", danger = true,
        onConfirm = { c.scope.launch { msg = c.sync.deleteFromWatch(tt.sessionId) ?: "Borrado del reloj" } }, onDismiss = { confirmDelete = false })
}

@Composable
private fun sliderColors() = SliderDefaults.colors(thumbColor = AvoColors.Red, activeTrackColor = AvoColors.Red, inactiveTrackColor = AvoColors.Surface2)

@Composable
private fun SmallBtn(text: String, onClick: () -> Unit) {
    val shape = RoundedCornerShape(50)
    Box(Modifier.clip(shape).background(AvoColors.Surface2).border(1.dp, AvoColors.Line, shape).clickable { onClick() }.padding(horizontal = 12.dp, vertical = 6.dp)) {
        Text(text, color = AvoColors.Text, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun ListRow(badge: String, badgeColor: Color, title: String, subtitle: String?, value: String, valueSub: String?, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 3.dp).clip(RoundedCornerShape(12.dp)).background(AvoColors.Surface2).clickable { onClick() }.padding(10.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(30.dp).background(badgeColor, CircleShape), contentAlignment = Alignment.Center) { Text(badge, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Bold) }
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Text(title, color = AvoColors.Text, fontWeight = FontWeight.Bold, fontSize = 14.sp)
            if (!subtitle.isNullOrBlank()) Text(subtitle, color = AvoColors.TextDim, fontSize = 12.sp)
        }
        Column(horizontalAlignment = Alignment.End) {
            Text(value, color = AvoColors.Text, fontWeight = FontWeight.Black, fontSize = 15.sp)
            if (valueSub != null) Text(valueSub, color = AvoColors.TextDim, fontSize = 12.sp)
        }
    }
}

@Composable
private fun GaitCard(i: Insights) {
    AvoCard("Aires (estimados por velocidad)") {
        Row(Modifier.fillMaxWidth().height(16.dp).clip(RoundedCornerShape(8.dp))) {
            Gait.entries.forEach { g -> val s = i.gaitShare(g).toFloat(); if (s > 0f) Box(Modifier.weight(s).fillMaxHeight().background(gaitColor(g))) }
        }
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Gait.entries.forEach { g ->
                Column(Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(8.dp).background(gaitColor(g), CircleShape)); Spacer(Modifier.width(4.dp))
                        Text(g.texto.uppercase(), color = AvoColors.TextDim, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                    }
                    Text(mmss(i.gaitSeconds[g] ?: 0.0) ?: "0:00", color = AvoColors.Text, fontWeight = FontWeight.Black, fontSize = 16.sp)
                    Text("${(i.gaitShare(g) * 100).roundToInt()} %", color = AvoColors.TextDim, fontSize = 12.sp)
                }
            }
        }
    }
}

@Composable
private fun ConditionsCard(marine: org.avoperformance.horse.data.TrainingMarineEntity?, busy: Boolean, message: String?, canFetch: Boolean, onFetch: () -> Unit) {
    AvoCard("Marea y condiciones") {
        if (marine == null) {
            Button(onClick = onFetch, enabled = !busy && canFetch, modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = AvoColors.Surface2, contentColor = AvoColors.Text)) {
                Text(if (busy) "Consultando…" else "Obtener marea y tiempo de la sesión")
            }
        } else {
            MetricGrid(listOf(
                { m -> MetricTile("Marea", marine.levelMsl?.let { f2(it) }, "m", m, Color(0xFF3D9BFF)) },
                { m -> MetricTile("Tendencia", when (marine.tideTrend) { "SUBIENDO" -> "▲ Sube"; "BAJANDO" -> "▼ Baja"; else -> null }, "", m) },
                { m -> MetricTile("Coeficiente", marine.tideCoefficient?.toString(), "", m, AvoColors.Red) },
                { m -> MetricTile("Viento", f0(marine.windKmh), "km/h", m) },
                { m -> MetricTile("Rachas", f0(marine.gustKmh), "km/h", m) },
                { m -> MetricTile("Ola", f1(marine.waveM), "m", m) },
                { m -> MetricTile("Periodo", f0(marine.wavePeriodS), "s", m) },
                { m -> MetricTile("Agua", f1(marine.waterC), "°C", m, AvoColors.Cyan) },
            ))
            Text("${marine.location} · ${marine.source}", color = AvoColors.TextDim, fontSize = 11.sp, modifier = Modifier.padding(top = 6.dp))
        }
        message?.let { Text(it, color = AvoColors.Warn, fontSize = 13.sp) }
    }
}

@Composable
private fun MapControls(style: MapStyle, onStyle: (MapStyle) -> Unit, color: TrackColor, onColor: (TrackColor) -> Unit, onCenter: () -> Unit) {
    Segmented(MapStyle.entries.map { it.texto }, style.ordinal, { onStyle(MapStyle.entries[it]) })
    Spacer(Modifier.height(6.dp))
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        TrackColor.entries.forEach { tc ->
            FilterChip(selected = color == tc, onClick = { onColor(tc) }, label = { Text(tc.texto, fontSize = 12.sp) },
                colors = FilterChipDefaults.filterChipColors(selectedContainerColor = AvoColors.RedDark, selectedLabelColor = Color.White, labelColor = AvoColors.TextDim))
        }
        Spacer(Modifier.weight(1f))
        SmallBtn("⌖", onCenter)
    }
}

@Composable
private fun MapLegend(a: TrainingAnalysis, color: TrackColor, style: MapStyle) {
    Row(Modifier.fillMaxWidth().padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        when (color) {
            TrackColor.SPEED -> {
                Text("0", color = AvoColors.TextDim, fontSize = 11.sp)
                Box(Modifier.padding(horizontal = 6.dp).weight(1f).height(6.dp).clip(RoundedCornerShape(3.dp))
                    .background(Brush.horizontalGradient((0..10).map { speedColor(it / 10f) })))
                Text("${f0(a.maxSpeedMs * 3.6)} km/h", color = AvoColors.TextDim, fontSize = 11.sp)
            }
            TrackColor.GAIT -> Gait.entries.forEach { g ->
                Box(Modifier.size(8.dp).background(gaitColor(g), CircleShape)); Text(" ${g.texto}   ", color = AvoColors.TextDim, fontSize = 11.sp)
            }
            TrackColor.RTK -> listOf("FIX" to AvoColors.Ok, "FLOAT" to AvoColors.Warn, "Otro" to AvoColors.Unknown).forEach { (l, cc) ->
                Box(Modifier.size(8.dp).background(cc, CircleShape)); Text(" $l   ", color = AvoColors.TextDim, fontSize = 11.sp)
            }
        }
    }
    Text(if (style == MapStyle.MAP) "© OpenStreetMap contributors" else AvoImagery.ATTRIBUTION, color = AvoColors.TextDim, fontSize = 10.sp)
}

@Composable
private fun PlaybackBar(a: TrainingAnalysis, ins: Insights?, sel: Int?, playing: Boolean, setPlaying: (Boolean) -> Unit, pick: (Int) -> Unit) {
    val i = (sel ?: 0).coerceIn(0, a.track.lastIndex)
    val p = a.track[i]
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(42.dp).background(AvoColors.Red, CircleShape).clickable { setPlaying(!playing) }, contentAlignment = Alignment.Center) {
            Text(if (playing) "❚❚" else "▶", color = Color.White, fontWeight = FontWeight.Bold)
        }
        Slider(value = i.toFloat(), onValueChange = { pick(it.roundToInt().coerceIn(0, a.track.lastIndex)) }, valueRange = 0f..a.track.lastIndex.toFloat(),
            colors = sliderColors(), modifier = Modifier.weight(1f).padding(horizontal = 8.dp))
    }
    MetricGrid(listOf(
        { m -> MetricTile("Tiempo", mmss(ins?.timeS?.getOrNull(i) ?: ((p.itowMs - a.track.first().itowMs) / 1000.0)), "", m) },
        { m -> MetricTile("Velocidad", f1(p.speedMs * 3.6), "km/h", m, AvoColors.Red) },
        { m -> MetricTile("Distancia", f0(ins?.distM?.getOrNull(i)), "m", m) },
        { m -> MetricTile("Aire", TrainingInsights.gaitOf(p.speedMs).texto, "", m, gaitColor(TrainingInsights.gaitOf(p.speedMs))) },
        { m -> MetricTile("Cadencia", f0(ins?.cadence?.getOrNull(i)), "/min", m, AvoColors.Cyan) },
        { m -> MetricTile("RTK", when (p.carrSoln) { 2 -> "FIX"; 1 -> "FLOAT"; else -> "—" }, "", m, when (p.carrSoln) { 2 -> AvoColors.Ok; 1 -> AvoColors.Warn; else -> AvoColors.Unknown }) },
    ))
}

/** Common visible window shared by every chart so they stay aligned. */
internal class ChartWindow(n: Int, zoom: Float, center: Float) {
    val last = (n - 1).coerceAtLeast(1)
    private val visible = (n / zoom).coerceAtLeast(2f).toInt()
    val first = ((center * last) - visible / 2f).toInt().coerceIn(0, (n - visible).coerceAtLeast(0))
    val end = (first + visible).coerceAtMost(last)
    val zoom = zoom
}

@Composable
internal fun ChartBlock(
    title: String, unit: String, values: List<Double>, sel: Int?, win: ChartWindow, color: Color, x: List<Double>,
    onDrag: (Float) -> Unit, onSelect: (Int) -> Unit, signed: Boolean = false, fill: Boolean = false,
) {
    val finite = values.filter { it.isFinite() }
    if (finite.size < 2) return
    val lo = if (signed) minOf(finite.min(), 0.0) else if (fill && unit == "m" && title == "Altitud") finite.min() - 1 else minOf(finite.min(), 0.0)
    val hi = maxOf(finite.max(), lo + 0.001)
    val selVal = sel?.let { values.getOrNull(it) }?.takeIf { it.isFinite() }
    Row(Modifier.fillMaxWidth().padding(top = 12.dp, bottom = 4.dp), verticalAlignment = Alignment.Bottom) {
        Box(Modifier.size(8.dp).background(color, CircleShape)); Spacer(Modifier.width(6.dp))
        Text(title.uppercase(), color = AvoColors.Silver, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.8.sp, modifier = Modifier.weight(1f))
        Text(if (selVal != null) "${f2(selVal)} $unit" else "máx ${f1(finite.max())} $unit", color = if (selVal != null) color else AvoColors.TextDim, fontSize = 12.sp, fontWeight = FontWeight.Bold)
    }
    val first = win.first; val end = win.end
    Canvas(
        Modifier.fillMaxWidth().height(120.dp).clip(RoundedCornerShape(10.dp)).background(AvoColors.Surface2)
            .pointerInput(values, first, end) { detectTapGestures { pos -> onSelect((first + (pos.x / size.width * (end - first)).roundToInt()).coerceIn(0, values.lastIndex)) } }
            .pointerInput(values, win.zoom) {
                detectDragGestures { ch, d ->
                    ch.consume()
                    if (win.zoom > 1.01f) onDrag(d.x / size.width)
                    else onSelect((first + (ch.position.x / size.width * (end - first)).roundToInt()).coerceIn(0, values.lastIndex))
                }
            }
    ) {
        val span = (hi - lo)
        fun px(i: Int) = size.width * (i - first) / (end - first).coerceAtLeast(1)
        fun py(v: Double) = (size.height * (1 - (v - lo) / span)).toFloat().coerceIn(0f, size.height)
        for (k in 1..3) drawLine(AvoColors.Line, Offset(0f, size.height * k / 4f), Offset(size.width, size.height * k / 4f), 1f)
        if (lo < 0 && hi > 0) drawLine(AvoColors.TextDim, Offset(0f, py(0.0)), Offset(size.width, py(0.0)), 1.5f)
        val stride = ((end - first) / 800).coerceAtLeast(1)
        val path = Path(); var started = false; var lastX = 0f; var firstX = 0f
        for (i in first..end step stride) {
            val v = values[i]
            if (!v.isFinite()) { started = false; continue }
            val xx = px(i); val yy = py(v)
            if (!started) { path.moveTo(xx, yy); started = true; if (i == first || firstX == 0f) firstX = xx } else path.lineTo(xx, yy)
            lastX = xx
        }
        if (fill && !signed) {
            val area = Path().apply { addPath(path); lineTo(lastX, size.height); lineTo(firstX, size.height); close() }
            drawPath(area, Brush.verticalGradient(listOf(color.copy(alpha = 0.35f), color.copy(alpha = 0.02f))))
        }
        drawPath(path, color, style = Stroke(width = 3f, cap = StrokeCap.Round))
        sel?.takeIf { it in first..end }?.let { i ->
            val xx = px(i)
            drawLine(Color.White.copy(alpha = 0.85f), Offset(xx, 0f), Offset(xx, size.height), 2f)
            values[i].takeIf { it.isFinite() }?.let { drawCircle(Color.White, 6f, Offset(xx, py(it))); drawCircle(color, 4f, Offset(xx, py(it))) }
        }
    }
    Row(Modifier.fillMaxWidth()) {
        Text(mmss(x.getOrNull(first)) ?: "", color = AvoColors.TextDim, fontSize = 10.sp, modifier = Modifier.weight(1f))
        Text(mmss(x.getOrNull(end)) ?: "", color = AvoColors.TextDim, fontSize = 10.sp)
    }
}

private class TrackMapRender(
    val analysis: TrainingAnalysis, var color: TrackColor, var style: MapStyle,
    var startIndex: Int, var endIndex: Int, var marker: Marker? = null, var recenterToken: Int,
)

@Composable
private fun RealTrackMap(
    analysis: TrainingAnalysis, selectedIndex: Int?, startIndex: Int, endIndex: Int,
    color: TrackColor, style: MapStyle, recenterToken: Int, heightDp: Int, onSelect: (Int) -> Unit,
) {
    val onSelectLatest by rememberUpdatedState(onSelect)
    val mapRef = remember(analysis) { mutableStateOf<MapView?>(null) }
    DisposableEffect(mapRef) { onDispose { mapRef.value?.onPause(); mapRef.value?.onDetach() } }
    AndroidView(
        modifier = Modifier.fillMaxWidth().height(heightDp.dp).clip(RoundedCornerShape(12.dp)),
        factory = { context ->
            MapView(context).apply {
                setTileSource(TileSourceFactory.MAPNIK)
                setMultiTouchControls(true)
                zoomController.setVisibility(org.osmdroid.views.CustomZoomButtonsController.Visibility.NEVER)
                controller.setZoom(16.0)
                onResume()
                mapRef.value = this
            }
        },
        update = { map ->
            var render = map.tag as? TrackMapRender
            val reset = render == null || render.analysis !== analysis
            if (reset || render?.color != color || render.style != style || render.startIndex != startIndex || render.endIndex != endIndex) {
                map.overlays.clear()
                map.setTileSource(if (style == MapStyle.MAP) TileSourceFactory.MAPNIK else AvoImagery.tileSource)
                if (style == MapStyle.HYBRID) {
                    listOf(AvoImagery.roadsSource, AvoImagery.placesSource).forEach { src ->
                        map.overlays.add(TilesOverlay(MapTileProviderBasic(map.context, src), map.context).apply { setLoadingBackgroundColor(android.graphics.Color.TRANSPARENT); setLoadingLineColor(android.graphics.Color.TRANSPARENT) })
                    }
                }
                render = TrackMapRender(analysis, color, style, startIndex, endIndex, recenterToken = if (reset) -1 else render!!.recenterToken)
                map.tag = render
                map.overlays.add(MapEventsOverlay(object : MapEventsReceiver {
                    override fun singleTapConfirmedHelper(tap: OsmPoint): Boolean {
                        val touch = map.projection.toPixels(tap, android.graphics.Point())
                        var nearest = -1; var best = Double.MAX_VALUE
                        analysis.track.forEachIndexed { i, pt ->
                            val xy = map.projection.toPixels(OsmPoint(pt.p.lat, pt.p.lon), android.graphics.Point())
                            val d = hypot((xy.x - touch.x).toDouble(), (xy.y - touch.y).toDouble())
                            if (d < best) { nearest = i; best = d }
                        }
                        if (nearest >= 0 && best <= 48.0 * map.resources.displayMetrics.density) { onSelectLatest(nearest); return true }
                        return false
                    }
                    override fun longPressHelper(tap: OsmPoint): Boolean = false
                }))
                addColoredRoute(map, analysis, color, startIndex, endIndex)
                if (startIndex > 0 || endIndex < analysis.track.lastIndex) listOf(startIndex to "A", endIndex to "B").forEach { (idx, title) ->
                    analysis.track.getOrNull(idx)?.let { s -> map.overlays.add(Marker(map).apply { position = OsmPoint(s.p.lat, s.p.lon); setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM); this.title = title }) }
                }
            }
            val display = render ?: return@AndroidView
            if (display.recenterToken != recenterToken) {
                display.recenterToken = recenterToken
                val tr = analysis.track
                map.post { map.zoomToBoundingBox(BoundingBox(tr.maxOf { it.p.lat } + 0.00012, tr.maxOf { it.p.lon } + 0.00012, tr.minOf { it.p.lat } - 0.00012, tr.minOf { it.p.lon } - 0.00012), false, 40) }
            }
            val s = selectedIndex?.takeIf { it in analysis.track.indices }
            if (s == null) { display.marker?.let { map.overlays.remove(it) }; display.marker = null }
            else {
                val pt = analysis.track[s]
                val mk = display.marker ?: Marker(map).also { it.setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM); display.marker = it; map.overlays.add(it) }
                mk.position = OsmPoint(pt.p.lat, pt.p.lon)
                mk.title = "%.1f km/h".format(pt.speedMs * 3.6)
            }
            map.invalidate()
        },
    )
}

/** About 150 polylines whatever the track length; every GNSS position is kept inside its polyline. */
private fun addColoredRoute(map: MapView, a: TrainingAnalysis, color: TrackColor, startIndex: Int, endIndex: Int) {
    val tr = a.track
    if (tr.size < 2) return
    val stride = ((tr.size - 2) / 150 + 1).coerceAtLeast(1)
    val vmax = tr.maxOf { it.speedMs }.coerceAtLeast(0.1)
    val density = map.resources.displayMetrics.density
    // dark casing under the coloured line so it reads on satellite imagery
    map.overlays.add(Polyline(map).apply {
        setPoints(tr.map { OsmPoint(it.p.lat, it.p.lon) })
        outlinePaint.color = android.graphics.Color.argb(170, 0, 0, 0); outlinePaint.strokeWidth = 8f * density
        outlinePaint.strokeCap = android.graphics.Paint.Cap.ROUND
    })
    var s = 1
    while (s < tr.size) {
        val e = (s + stride - 1).coerceAtMost(tr.lastIndex)
        val mid = tr[(s + e) / 2]
        val col = when (color) {
            TrackColor.SPEED -> speedColor((mid.speedMs / vmax).toFloat()).argb()
            TrackColor.GAIT -> gaitColor(TrainingInsights.gaitOf(mid.speedMs)).argb()
            TrackColor.RTK -> when (mid.carrSoln) { 2 -> AvoColors.Ok.argb(); 1 -> AvoColors.Warn.argb(); else -> AvoColors.Unknown.argb() }
        }
        val inside = e >= startIndex && s <= endIndex
        map.overlays.add(Polyline(map).apply {
            setPoints((s - 1..e).map { OsmPoint(tr[it].p.lat, tr[it].p.lon) })
            outlinePaint.color = if (inside) col else android.graphics.Color.argb(90, 160, 160, 160)
            outlinePaint.strokeWidth = (if (inside) 5f else 3f) * density
            outlinePaint.strokeCap = android.graphics.Paint.Cap.ROUND
        })
        s = e + 1
    }
    listOf(0 to android.graphics.Color.rgb(82, 221, 64), tr.lastIndex to android.graphics.Color.rgb(237, 18, 42)).forEach { (i, cc) ->
        map.overlays.add(Polyline(map).apply {
            setPoints(listOf(OsmPoint(tr[i].p.lat, tr[i].p.lon), OsmPoint(tr[i].p.lat + 1e-7, tr[i].p.lon)))
            outlinePaint.color = cc; outlinePaint.strokeWidth = 14f * density; outlinePaint.strokeCap = android.graphics.Paint.Cap.ROUND
        })
    }
}
