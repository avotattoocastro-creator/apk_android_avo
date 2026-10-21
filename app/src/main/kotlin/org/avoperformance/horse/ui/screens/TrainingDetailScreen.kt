package org.avoperformance.horse.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.transformable
import androidx.compose.foundation.gestures.rememberTransformableState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.material3.FilterChip
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.ui.viewinterop.AndroidView
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.avoperformance.horse.maps.AvoImagery
import org.osmdroid.events.MapEventsReceiver
import org.osmdroid.util.BoundingBox
import org.osmdroid.util.GeoPoint as OsmPoint
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.MapEventsOverlay
import org.osmdroid.views.overlay.Marker
import org.osmdroid.views.overlay.Polyline
import org.osmdroid.views.overlay.CopyrightOverlay
import androidx.compose.ui.unit.IntOffset
import kotlin.math.hypot
import kotlin.math.roundToInt
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.HorizontalDivider
import androidx.compose.ui.graphics.Color
import kotlin.math.abs
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.material3.Slider
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import kotlinx.coroutines.delay
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.avoperformance.horse.AppContainer
import org.avoperformance.horse.core.geo.LocalFrame
import org.avoperformance.horse.core.raw.TrainingAnalysis
import org.avoperformance.horse.core.sync.SyncRules
import org.avoperformance.horse.core.sync.SyncState
import org.avoperformance.horse.ui.components.AvoCard
import org.avoperformance.horse.ui.components.ConfirmDialog
import org.avoperformance.horse.ui.components.Fmt
import org.avoperformance.horse.ui.components.KV
import org.avoperformance.horse.ui.components.Note
import org.avoperformance.horse.ui.components.StatusPill
import org.avoperformance.horse.ui.theme.AvoColors

@Composable
fun TrainingDetailScreen(c: AppContainer, id: String) {
    val t by c.db.trainings().observe(id).collectAsStateWithLifecycle(null)
    var analysis by remember { mutableStateOf<TrainingAnalysis?>(null) }
    var loading by remember { mutableStateOf(false) }
    var msg by remember { mutableStateOf<String?>(null) }
    var confirmDelete by remember { mutableStateOf(false) }
    val tt = t
    LaunchedEffect(tt?.localDir, tt?.downloadedBytes, tt?.state) {
        if (tt?.localDir != null && (tt.state == SyncState.VERIFICADO_LOCAL.name || tt.state == SyncState.PENDIENTE_SERVIDOR.name ||
                tt.state == SyncState.VERIFICADO_SERVIDOR.name || tt.state == SyncState.MARCADO_EN_RELOJ.name || tt.state == SyncState.DESCARGADO.name)) {
            loading = true
            analysis = withContext(Dispatchers.IO) { runCatching { c.sync.analysisFor(tt) }.getOrNull() }
            loading = false
        }
    }
    if (tt == null) { Note("Entrenamiento no encontrado"); return }
    val st = runCatching { SyncState.valueOf(tt.state) }.getOrNull()
    val a = analysis
    var selectedTrackIndex by remember(id) { mutableStateOf<Int?>(null) }
    var playing by remember(id) { mutableStateOf(false) }
    var segmentStart by remember(id) { mutableIntStateOf(0) }
    var segmentEnd by remember(id) { mutableIntStateOf(Int.MAX_VALUE) }
    LaunchedEffect(playing, a) {
        while (playing && a != null && a.track.isNotEmpty()) {
            delay(250)
            val current = selectedTrackIndex ?: 0
            val next = (current + 1).coerceAtMost(a.track.lastIndex)
            selectedTrackIndex = next
            if (next == a.track.lastIndex) playing = false
        }
    }

    LazyColumn(Modifier.fillMaxSize()) {
        if (a != null) item {
            AvoCard("Resumen del entrenamiento") {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = androidx.compose.foundation.layout.Arrangement.SpaceEvenly) {
                    org.avoperformance.horse.ui.components.BigValue("${Fmt.m(a.distanceM,0)}", "m", "Distancia")
                    org.avoperformance.horse.ui.components.BigValue("${Fmt.kmh(a.maxSpeedMs)}", "km/h", "V. máxima")
                    org.avoperformance.horse.ui.components.BigValue(a.avgSpeedMs?.let { Fmt.kmh(it) }, "km/h", "V. media")
                }
                val acceleration = accelerationSeries(a)
                KV("Aceleración máxima", acceleration.maxOrNull()?.let { "%.2f m/s²".format(it) })
                KV("Desaceleración máxima", acceleration.minOrNull()?.let { "%.2f m/s²".format(it) })
                KV("Duración GNSS", a.durationS?.let { Fmt.duration((it*1000).toLong()) })
                KV("RTK FIX", "${pct(a.fixEpochs, a.gnssUsable)}")
                KV("GNSS válido", "${a.gnssUsable} / ${a.gnssSamples}")
            }
        }
        if (loading) item { Note("Analizando el fichero…") }
        if (a != null) {
            item {
                AvoCard("Análisis (datos del fichero)") {
                    KV("Distancia", "${Fmt.m(a.distanceM, 0)} m")
                    KV("Duración con GNSS", a.durationS?.let { Fmt.duration((it * 1000).toLong()) })
                    KV("Velocidad media", a.avgSpeedMs?.let { "${Fmt.kmh(it)} km/h" })
                    KV("Velocidad máxima", "${Fmt.kmh(a.maxSpeedMs)} km/h")
                    KV("Tiempo en RTK FIX", a.fixTimeS?.let { "${Fmt.m(it, 0)} s (${pct(a.fixEpochs, a.gnssUsable)})" })
                    KV("Tiempo en RTK FLOAT", a.floatTimeS?.let { "${Fmt.m(it, 0)} s (${pct(a.floatEpochs, a.gnssUsable)})" })
                    KV("Épocas sin solución", "${a.noFix}")
                    KV("Muestras GNSS válidas", "${a.gnssUsable} de ${a.gnssSamples}")
                    KV("IMU de la cincha", if (a.imuAvailable) "${a.imuSamples} muestras" else "no disponible en este entrenamiento")
                    KV("Marcadores", "${a.markers}")
                    KV("Cierre del fichero", if (a.scan.cleanClose) "limpio" else "recuperado / sin cierre limpio")
                    if (a.scan.tailGarbage) Note("El último bloque estaba incompleto (corte de alimentación); se ignoró.", AvoColors.Warn)
                }
            }
            if (a.track.size >= 2) {
                item { AvoCard("Control del entrenamiento") {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(onClick = { playing = !playing }) { Text(if (playing) "Pausar" else "Reproducir") }
                        OutlinedButton(onClick = { playing = false; selectedTrackIndex = 0 }) { Text("Inicio") }
                        OutlinedButton(onClick = { playing = false; selectedTrackIndex = a.track.lastIndex }) { Text("Final") }
                    }
                    Slider(
                        value = (selectedTrackIndex ?: 0).toFloat(),
                        onValueChange = { selectedTrackIndex = it.roundToInt().coerceIn(0, a.track.lastIndex); playing = false },
                        valueRange = 0f..a.track.lastIndex.toFloat()
                    )
                    selectedTrackIndex?.let { idx ->
                        val point = a.track[idx.coerceIn(0, a.track.lastIndex)]
                        KV("Tiempo", "%.1f s".format((point.itowMs-a.track.first().itowMs)/1000.0))
                        KV("Velocidad", "%.2f km/h".format(point.speedMs*3.6))
                        KV("Precisión horizontal", "%.2f m".format(point.hAccM))
                        KV("RTK", when(point.carrSoln) { 2 -> "FIX"; 1 -> "FLOAT"; else -> "No RTK" })
                    }
                } }
                item { AvoCard("V1.9 · Seleccionar tramo A–B") {
                    val lastIndex = a.track.lastIndex
                    val start = segmentStart.coerceIn(0, lastIndex - 1)
                    val end = segmentEnd.coerceIn(start + 1, lastIndex)
                    Note("Selecciona el inicio y el final del intervalo. Las estadísticas y gráficas de abajo corresponden solo a este tramo.")
                    KV("Inicio A", "Punto ${start + 1}")
                    Slider(value = start.toFloat(), onValueChange = { segmentStart = it.roundToInt().coerceIn(0, end - 1) }, valueRange = 0f..(lastIndex - 1).toFloat())
                    KV("Final B", "Punto ${end + 1}")
                    Slider(value = end.toFloat(), onValueChange = { segmentEnd = it.roundToInt().coerceIn(start + 1, lastIndex) }, valueRange = 1f..lastIndex.toFloat())
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(onClick = { selectedTrackIndex?.let { segmentStart = it.coerceIn(0, end - 1) } }) { Text("A = punto GPS") }
                        OutlinedButton(onClick = { selectedTrackIndex?.let { segmentEnd = it.coerceIn(start + 1, lastIndex) } }) { Text("B = punto GPS") }
                        OutlinedButton(onClick = { segmentStart = 0; segmentEnd = Int.MAX_VALUE }) { Text("Todo") }
                    }
                    val portion = a.track.subList(start, end + 1)
                    val duration = (portion.last().itowMs - portion.first().itowMs) / 1000.0
                    val distance = portion.zipWithNext().sumOf { (p, q) ->
                        val lat1 = Math.toRadians(p.p.lat)
                        val lat2 = Math.toRadians(q.p.lat)
                        val dLat = lat2 - lat1
                        val dLon = Math.toRadians(q.p.lon - p.p.lon)
                        val h = kotlin.math.sin(dLat / 2).let { it * it } +
                            kotlin.math.cos(lat1) * kotlin.math.cos(lat2) * kotlin.math.sin(dLon / 2).let { it * it }
                        12742000.0 * kotlin.math.asin(kotlin.math.sqrt(h.coerceIn(0.0, 1.0)))
                    }
                    val speed = portion.map { it.speedMs }.filter { it.isFinite() && it >= 0.0 }
                    val accelerations = portion.zipWithNext().mapNotNull { (p, q) ->
                        val dt = (q.itowMs - p.itowMs) / 1000.0
                        if (dt !in 0.08..10.0) null else ((q.speedMs - p.speedMs) / dt).takeIf { it.isFinite() && kotlin.math.abs(it) <= 12.0 }
                    }
                    KV("Duración", "%.1f s".format(duration))
                    KV("Distancia GPS", "%.1f m".format(distance))
                    KV("Velocidad media", speed.takeIf { it.isNotEmpty() }?.average()?.let { "%.2f km/h".format(it * 3.6) })
                    KV("Velocidad máxima", speed.maxOrNull()?.let { "%.2f km/h".format(it * 3.6) })
                    KV("Aceleración máxima", accelerations.maxOrNull()?.let { "%.2f m/s²".format(it) })
                    KV("Desaceleración máxima", accelerations.minOrNull()?.let { "%.2f m/s²".format(it) })
                    KV("RTK FIX", pct(portion.count { it.carrSoln == 2 }, portion.size))
                    KV("RTK FLOAT", pct(portion.count { it.carrSoln == 1 }, portion.size))
                    Text("Velocidad del tramo", color = AvoColors.Gold)
                    SynchronizedChart(portion.map { it.speedMs * 3.6 }, null, AvoColors.Gold, "km/h") { selectedTrackIndex = start + it; playing = false }
                    Text("Aceleración del tramo", color = AvoColors.Gold)
                    SynchronizedChart(List(portion.size) { i -> if (i == 0) 0.0 else {
                        val dt = (portion[i].itowMs - portion[i-1].itowMs) / 1000.0
                        if (dt !in 0.08..10.0) 0.0 else ((portion[i].speedMs - portion[i-1].speedMs) / dt).takeIf { it.isFinite() && kotlin.math.abs(it) <= 12.0 } ?: 0.0
                    } }, null, AvoColors.Warn, "m/s²") { selectedTrackIndex = start + it; playing = false }
                } }
                item { AvoCard("Recorrido GPS interactivo") { InteractiveTrack(a, selectedTrackIndex) { selectedTrackIndex = it; playing = false } } }
                item { AvoCard("Velocidad") { SynchronizedChart(a.track.map { it.speedMs * 3.6 }, selectedTrackIndex, AvoColors.Gold, "km/h") { selectedTrackIndex = it; playing = false } } }
                item { AvoCard("Aceleración longitudinal GNSS") {
                    Note("Derivada de la velocidad GNSS; no sustituye a la aceleración de las IMU. Se omiten saltos de tiempo y valores espurios.")
                    val acc = accelerationSeries(a)
                    if (acc.size > 1) {
                        KV("Aceleración máxima", "%.2f m/s²".format(acc.maxOrNull() ?: 0.0))
                        KV("Frenada máxima", "%.2f m/s²".format(acc.minOrNull() ?: 0.0))
                        SynchronizedAccelerationChart(a, selectedTrackIndex) { selectedTrackIndex = it; playing = false }
                    } else Note("No hay suficientes muestras GNSS válidas")
                } }
                item { AvoCard("Ritmo y regularidad") {
                    KV("Ritmo medio", a.avgSpeedMs?.takeIf { it > 0.5 }?.let { "%.1f s/100 m".format(100.0 / it) })
                    val speeds = a.track.map { it.speedMs }.filter { it > 0.5 && it.isFinite() }
                    val mean = speeds.average().takeIf { !it.isNaN() && it > 0 } ?: 0.0
                    val variation = if (speeds.size >= 3 && mean > 0) kotlin.math.sqrt(speeds.map { (it-mean)*(it-mean) }.average()) / mean * 100 else null
                    KV("Variación de velocidad", variation?.let { "%.1f %%".format(it) })
                    Note("Menos variación indica velocidad más uniforme; depende del trazado y el tipo de ejercicio.")
                } }
                item { AvoCard("Análisis por tramos") {
                    val points = a.track
                    val first = points.first().itowMs
                    val last = points.last().itowMs
                    val step = 30_000L
                    var start = first
                    while (start < last && step > 0) {
                        val window = points.filter { it.itowMs in start until (start + step) }
                        if (window.isNotEmpty()) {
                            val avg = window.map { it.speedMs }.average()
                            KV("${(start-first)/1000}–${(start-first)/1000+30} s", "%.1f km/h media · %.1f km/h máx".format(avg * 3.6, (window.maxOfOrNull { it.speedMs } ?: 0.0) * 3.6))
                        }
                        start += step
                    }
                } }
            }
        }
        item {
            AvoCard("Detalles técnicos del fichero") {
                Row { StatusPill(st?.texto ?: tt.state, syncColor(st)) }
                KV("Inicio", Fmt.date(tt.startRtcMs))
                KV("Sesión", tt.sessionId)
                KV("Caballo", tt.horseCode)
                KV("Jinete", tt.riderCode)
                KV("Tiempo activo (reloj)", Fmt.duration(tt.activeMs))
                KV("Tamaño", Fmt.bytes(tt.totalBytes))
                KV("SHA-256 local", tt.localSha256?.take(16)?.plus("…"))
                KV("SHA-256 del reloj", tt.watchSha256?.take(16)?.plus("…"))
                KV("Servidor", if (tt.serverSha256 != null) "verificado" else if (c.sync.serverConfigured) "pendiente" else "no configurado")
                msg?.let { Note(it, AvoColors.Warn) }
            }
        }
        item {
            AvoCard("Acciones") {
                OutlinedButton(enabled = SyncRules.canOfferDelete(org.avoperformance.horse.core.sync.LocalTraining(tt.sessionId, tt.segments, tt.totalBytes,
                    tt.downloadedBytes, tt.localSha256, tt.watchSha256, tt.serverSha256, st ?: SyncState.EN_RELOJ,
                    org.avoperformance.horse.core.ble.WatchFileState.UNKNOWN, tt.startRtcMs, tt.activeMs)), onClick = { confirmDelete = true }) {
                    Text("Borrar del reloj")
                }
                Note("La app nunca borra nada del reloj por su cuenta. Solo se puede borrar un entrenamiento verificado por el servidor, y el propio reloj lo comprueba.")
            }
        }
    }
    if (confirmDelete) ConfirmDialog("Borrar del reloj", "Se borrará ${tt.sessionId} de la tarjeta del chaleco. La copia del teléfono se conserva.", "Borrar", danger = true,
        onConfirm = { c.scope.launch { msg = c.sync.deleteFromWatch(tt.sessionId) ?: "Borrado del reloj" } }, onDismiss = { confirmDelete = false })
}

private fun pct(n: Int, d: Int) = if (d > 0) "${n * 100 / d} %" else "—"

@Composable
private fun InteractiveTrack(a: TrainingAnalysis, selection: Int?, onSelect: (Int) -> Unit) {
    val pts = a.track
    if (pts.size < 2) return
    var colorBySpeed by remember(a) { mutableStateOf(true) }
    var useMap by remember(a) { mutableStateOf(true) }
    var imagery by remember(a) { mutableStateOf(false) }
    var recenterToken by remember(a) { mutableIntStateOf(0) }

    var scale by remember(a) { mutableStateOf(1f) }
    var pan by remember(a) { mutableStateOf(Offset.Zero) }
    val frame = remember(a) { LocalFrame(pts.first().p) }
    val xy = remember(a) { pts.map { frame.toXY(it.p) } }
    val minX = remember(a) { xy.minOf { it.first } }
    val maxX = remember(a) { xy.maxOf { it.first } }
    val minY = remember(a) { xy.minOf { it.second } }
    val maxY = remember(a) { xy.maxOf { it.second } }
    val speedMax = remember(a) { pts.maxOf { it.speedMs }.coerceAtLeast(0.1) }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        FilterChip(selected = colorBySpeed, onClick = { colorBySpeed = true }, label = { Text("Velocidad") })
        FilterChip(selected = !colorBySpeed, onClick = { colorBySpeed = false }, label = { Text("RTK") })
        OutlinedButton(onClick = { scale = 1f; pan = Offset.Zero; recenterToken++ }) { Text("Centrar") }
    }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        FilterChip(selected = useMap, onClick = { useMap = true }, label = { Text("Mapa real") })
        FilterChip(selected = !useMap, onClick = { useMap = false }, label = { Text("Plano offline") })
    }
    val selectedNow = selection
    if (useMap) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(selected = !imagery, onClick = { imagery = false }, label = { Text("Calles") })
            FilterChip(selected = imagery, onClick = { imagery = true }, label = { Text("Satélite") })
        }
        Note("Zoom con dos dedos, desplazamiento libre y selección de puntos sincronizados con las gráficas.")
        RealTrackMap(a, selection, colorBySpeed, imagery, recenterToken, onSelect)
        Text(
            text = if (imagery) AvoImagery.ATTRIBUTION else "© OpenStreetMap contributors",
            color = AvoColors.TextDim,
        )
        if (imagery) Note("Imágenes Esri World Imagery (fecha y resolución variables). Requiere acceso autorizado a ese servicio. La disponibilidad y el uso sin conexión dependen de sus condiciones.")
        else Note("Calles de OpenStreetMap. Las teselas ya visitadas pueden mantenerse temporalmente en la caché local.")
    } else {
        Note("Pellizca para ampliar, arrastra para moverte y toca un punto de la trayectoria.")
        Canvas(
        Modifier.fillMaxWidth().height(340.dp).background(AvoColors.Surface2)
            .pointerInput(a, scale, pan) {
                detectTapGestures { touch ->
                    val span = maxOf(maxX - minX, maxY - minY, 1.0)
                    val base = minOf(size.width.toFloat(), size.height.toFloat()) * 0.88f / span.toFloat()
                    val ox = (size.width - (maxX - minX).toFloat() * base) / 2f
                    val oy = (size.height - (maxY - minY).toFloat() * base) / 2f
                    var nearest = 0
                    var dist = Float.MAX_VALUE
                    xy.forEachIndexed { i, point ->
                        val xx = (ox + (point.first-minX).toFloat()*base - size.width/2f)*scale + size.width/2f + pan.x
                        val yy0 = size.height - (oy + (point.second-minY).toFloat()*base)
                        val yy = (yy0 - size.height/2f)*scale + size.height/2f + pan.y
                        val d = hypot(xx-touch.x, yy-touch.y)
                        if (d < dist) { dist = d; nearest = i }
                    }
                    if (dist < 45f) onSelect(nearest)
                }
            }
            .pointerInput(a) {
                detectTransformGestures { _, gesturePan, zoom, _ ->
                    scale = (scale * zoom).coerceIn(1f, 15f)
                    pan = pan + gesturePan
                }
            }
    ) {
        val span = maxOf(maxX - minX, maxY - minY, 1.0)
        val base = minOf(size.width, size.height) * 0.88f / span.toFloat()
        val ox = (size.width - (maxX-minX).toFloat()*base)/2
        val oy = (size.height - (maxY-minY).toFloat()*base)/2
        fun at(i: Int): Offset {
            val x = ox + (xy[i].first-minX).toFloat()*base
            val y = size.height - (oy + (xy[i].second-minY).toFloat()*base)
            return Offset((x-size.width/2)*scale+size.width/2+pan.x, (y-size.height/2)*scale+size.height/2+pan.y)
        }
        for (i in 1 until pts.size) {
            val color = if (colorBySpeed) {
                val ratio = (pts[i].speedMs / speedMax).toFloat().coerceIn(0f, 1f)
                Color(red = ratio, green = 0.82f * (1f-ratio), blue = 1f-ratio, alpha = 1f)
            } else when (pts[i].carrSoln) {
                2 -> AvoColors.Ok; 1 -> AvoColors.Warn; else -> AvoColors.TextDim
            }
            drawLine(color, at(i-1), at(i), strokeWidth=3.5f)
        }
        selectedNow?.takeIf { it in pts.indices }?.let { index ->
            drawCircle(AvoColors.Gold, radius=10f, center=at(index))
            drawCircle(Color.White, radius=3.5f, center=at(index))
        }
        }
    }
    selectedNow?.takeIf { it in pts.indices }?.let { i ->
        val item = pts[i]
        KV("Punto seleccionado", "${i+1} / ${pts.size}")
        KV("Tiempo desde inicio GNSS", "%.1f s".format((item.itowMs-pts.first().itowMs)/1000.0))
        KV("Velocidad", "%.2f km/h".format(item.speedMs*3.6))
        KV("Estado RTK", when(item.carrSoln) {2->"FIX";1->"FLOAT";else->"Sin solución RTK"})
    }
}

/** MapView keeps its camera when the palette changes; overlays are rebuilt only when required. */
private class TrackMapRender(
    val analysis: TrainingAnalysis,
    var bySpeed: Boolean,
    var imagery: Boolean,
    var marker: Marker? = null,
    var recenterToken: Int,
)

@Composable
private fun RealTrackMap(
    analysis: TrainingAnalysis,
    selectedIndex: Int?,
    bySpeed: Boolean,
    imagery: Boolean,
    recenterToken: Int,
    onSelect: (Int) -> Unit,
) {
    val onSelectLatest by rememberUpdatedState(onSelect)
    val mapRef = remember(analysis) { mutableStateOf<MapView?>(null) }

    DisposableEffect(mapRef) {
        onDispose {
            mapRef.value?.onPause()
            mapRef.value?.onDetach()
        }
    }

    AndroidView(
        modifier = Modifier.fillMaxWidth().height(360.dp),
        factory = { context ->
            MapView(context).apply {
                setTileSource(TileSourceFactory.MAPNIK)
                setMultiTouchControls(true)
                controller.setZoom(16.0)
                onResume()
                mapRef.value = this
            }
        },
        update = { map ->
            var render = map.tag as? TrackMapRender
            val resetBounds = render == null || render.analysis !== analysis
            if (resetBounds || render?.imagery != imagery) {
                map.setTileSource(if (imagery) AvoImagery.tileSource else TileSourceFactory.MAPNIK)
            }
            if (resetBounds || render?.bySpeed != bySpeed || render.imagery != imagery) {
                map.overlays.clear()
                render = TrackMapRender(analysis, bySpeed, imagery, recenterToken = recenterToken)
                map.tag = render

                map.overlays.add(MapEventsOverlay(object : MapEventsReceiver {
                    override fun singleTapConfirmedHelper(tap: OsmPoint): Boolean {
                        val touch = map.projection.toPixels(tap, android.graphics.Point())
                        var nearest = -1
                        var minDistance = Double.MAX_VALUE
                        analysis.track.forEachIndexed { i, point ->
                            val xy = map.projection.toPixels(OsmPoint(point.p.lat, point.p.lon), android.graphics.Point())
                            val distance = hypot((xy.x - touch.x).toDouble(), (xy.y - touch.y).toDouble())
                            if (distance < minDistance) {
                                nearest = i
                                minDistance = distance
                            }
                        }
                        val maxTapPx = 48.0 * map.resources.displayMetrics.density
                        if (nearest >= 0 && minDistance <= maxTapPx) {
                            onSelectLatest(nearest)
                            return true
                        }
                        return false
                    }

                    override fun longPressHelper(tap: OsmPoint): Boolean = false
                }))
                addColoredRoute(map, analysis, bySpeed)
                // Attribution remains visible beneath the map (Compose), independent of osmdroid copyright hooks.
            }

            val display = render ?: return@AndroidView
            if (resetBounds || display.recenterToken != recenterToken) {
                display.recenterToken = recenterToken
                val track = analysis.track
                val north = track.maxOf { it.p.lat } + 0.00012
                val south = track.minOf { it.p.lat } - 0.00012
                val east = track.maxOf { it.p.lon } + 0.00012
                val west = track.minOf { it.p.lon } - 0.00012
                map.post { map.zoomToBoundingBox(BoundingBox(north, east, south, west), false, 48) }
            }

            val selected = selectedIndex?.takeIf { it in analysis.track.indices }
            if (selected == null) {
                display.marker?.let { map.overlays.remove(it) }
                display.marker = null
            } else {
                val point = analysis.track[selected]
                val marker = display.marker ?: Marker(map).also {
                    it.setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM)
                    display.marker = it
                    map.overlays.add(it)
                }
                marker.position = OsmPoint(point.p.lat, point.p.lon)
                marker.title = "Punto " + (selected + 1) + " · " + "%.2f km/h".format(point.speedMs * 3.6)
            }
            map.invalidate()
        },
    )
}

/**
 * Bound overlay count to approximately 120 polylines, even for 5000 GNSS samples,
 * while retaining all GPS positions inside each polyline segment.
 */
private fun addColoredRoute(map: MapView, a: TrainingAnalysis, bySpeed: Boolean) {
    val track = a.track
    if (track.size < 2) return
    val stride = ((track.size - 2) / 120 + 1).coerceAtLeast(1)
    val speedMax = track.maxOf { it.speedMs }.coerceAtLeast(0.1)
    var start = 1
    while (start < track.size) {
        val end = (start + stride - 1).coerceAtMost(track.lastIndex)
        val midpoint = track[(start + end) / 2]
        val lineColor = if (bySpeed) {
            val fraction = (midpoint.speedMs / speedMax).toFloat().coerceIn(0f, 1f)
            android.graphics.Color.HSVToColor(floatArrayOf(210f * (1f - fraction), 0.90f, 0.96f))
        } else when (midpoint.carrSoln) {
            2 -> android.graphics.Color.rgb(43, 190, 107)
            1 -> android.graphics.Color.rgb(255, 182, 48)
            else -> android.graphics.Color.rgb(165, 165, 175)
        }
        val points = (start - 1..end).map { i -> OsmPoint(track[i].p.lat, track[i].p.lon) }
        map.overlays.add(Polyline(map).apply {
            setPoints(points)
            outlinePaint.color = lineColor
            outlinePaint.strokeWidth = 5f * map.resources.displayMetrics.density
        })
        start = end + 1
    }
}

@Composable
private fun SynchronizedChart(
    values: List<Double>, selection: Int?, color: Color, unit: String,
    onSelect: (Int) -> Unit
) {
    if (values.size < 2) return
    var zoom by remember(values) { mutableStateOf(1f) }
    var center by remember(values) { mutableStateOf(0.5f) }
    val low = minOf(values.minOrNull() ?: 0.0, 0.0)
    val high = maxOf(values.maxOrNull() ?: 1.0, 0.0)
    val span = (high-low).coerceAtLeast(0.001)
    val visible = (values.size / zoom).coerceAtLeast(2f)
    val first = ((center * values.lastIndex) - visible / 2).toInt().coerceIn(0, (values.size-visible.toInt()).coerceAtLeast(0))
    val end = (first + visible.toInt()).coerceAtMost(values.lastIndex)
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        OutlinedButton(onClick = { zoom = (zoom * 1.6f).coerceAtMost(20f) }) { Text("Ampliar +") }
        OutlinedButton(onClick = { zoom = (zoom / 1.6f).coerceAtLeast(1f) }) { Text("Reducir −") }
        OutlinedButton(onClick = { zoom = 1f; center = 0.5f }) { Text("Completa") }
    }
    Text("${"%.1f".format(high)} $unit máximo · arrastra horizontalmente para moverte; toca para seleccionar", color=AvoColors.TextDim)
    Canvas(Modifier.fillMaxWidth().height(210.dp).background(AvoColors.Surface2)
        .pointerInput(values, first, end) {
            detectTapGestures { pos ->
                val i = (first + (pos.x / size.width * (end-first)).roundToInt()).coerceIn(0, values.lastIndex)
                onSelect(i)
            }
        }
        .pointerInput(values, zoom) {
            detectDragGestures { change, drag ->
                change.consume()
                center = (center - drag.x / size.width * (1f / zoom)).coerceIn(0f, 1f)
            }
        }
    ) {
        val path = Path()
        for (i in first..end) {
            val x = size.width * (i-first) / (end-first).coerceAtLeast(1)
            val y = (size.height * (1-(values[i]-low)/span)).toFloat().coerceIn(0f,size.height)
            if (i==first) path.moveTo(x,y) else path.lineTo(x,y)
        }
        if (low < 0 && high > 0) {
            val y0 = (size.height * (high/span)).toFloat()
            drawLine(AvoColors.TextDim, Offset(0f,y0),Offset(size.width,y0),strokeWidth=1f)
        }
        drawPath(path,color,style=Stroke(width=3f))
        selection?.takeIf { it in first..end }?.let { i ->
            val x = size.width * (i-first)/(end-first).coerceAtLeast(1)
            drawLine(Color.White, Offset(x,0f),Offset(x,size.height),strokeWidth=2f)
            val y = (size.height * (1-(values[i]-low)/span)).toFloat().coerceIn(0f,size.height)
            drawCircle(AvoColors.Gold,radius=6f,center=Offset(x,y))
        }
    }
}

@Composable
private fun SynchronizedAccelerationChart(a: TrainingAnalysis, selection: Int?, onSelect: (Int) -> Unit) {
    val points = a.track
    val values = List(points.size) { i ->
        if (i == 0) 0.0 else {
            val dt = (points[i].itowMs - points[i-1].itowMs) / 1000.0
            if (dt !in 0.08..10.0) 0.0 else ((points[i].speedMs-points[i-1].speedMs)/dt).takeIf { it.isFinite() && abs(it)<=12.0 } ?: 0.0
        }
    }
    SynchronizedChart(values,selection,AvoColors.Warn,"m/s²",onSelect)
}

/** Exclude invalid GPS time jumps, week rollover and noise spikes. */
private fun accelerationSeries(a: TrainingAnalysis): List<Double> = a.track.zipWithNext().mapNotNull { (p, q) ->
    val dt = (q.itowMs - p.itowMs) / 1000.0
    if (dt !in 0.08..10.0 || !p.speedMs.isFinite() || !q.speedMs.isFinite()) null
    else ((q.speedMs-p.speedMs)/dt).takeIf { it.isFinite() && abs(it) <= 12.0 }
}

@Composable
private fun SeriesChart(values: List<Double>, col: Color, signed: Boolean = false) {
    if (values.size < 2) return
    val low = if (signed) minOf(values.minOrNull() ?: 0.0, 0.0) else 0.0
    val high = maxOf(values.maxOrNull() ?: 1.0, 0.0)
    val span = (high-low).coerceAtLeast(0.01)
    Canvas(Modifier.fillMaxWidth().height(165.dp).background(AvoColors.Surface2)) {
        val path = Path()
        values.forEachIndexed { i, v ->
            val x = size.width * i / (values.size-1)
            val y = (size.height * (1 - (v-low)/span)).toFloat().coerceIn(0f,size.height)
            if (i == 0) path.moveTo(x,y) else path.lineTo(x,y)
        }
        if (low < 0 && high > 0) {
            val zeroY = (size.height * high/span).toFloat()
            drawLine(AvoColors.TextDim, Offset(0f,zeroY), Offset(size.width,zeroY), strokeWidth=1f)
        }
        drawPath(path,col,style=Stroke(width=3f))
    }
}
