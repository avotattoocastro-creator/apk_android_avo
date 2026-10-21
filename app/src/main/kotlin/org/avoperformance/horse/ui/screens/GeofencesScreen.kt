package org.avoperformance.horse.ui.screens

import android.graphics.Color as AColor
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.FilterChip
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.launch
import org.avoperformance.horse.AppContainer
import org.avoperformance.horse.core.config.WatchConfig
import org.avoperformance.horse.core.geo.Fence
import org.avoperformance.horse.core.geo.FenceType
import org.avoperformance.horse.core.geo.GeoPoint
import org.avoperformance.horse.core.geo.circleOutline
import org.avoperformance.horse.data.FenceEntity
import org.avoperformance.horse.ui.components.AvoCard
import org.avoperformance.horse.ui.components.ConfirmDialog
import org.avoperformance.horse.ui.components.KV
import org.avoperformance.horse.ui.components.Note
import org.avoperformance.horse.ui.theme.AvoColors
import org.osmdroid.events.MapEventsReceiver
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.MapEventsOverlay
import org.osmdroid.views.overlay.Marker
import org.osmdroid.views.overlay.Polygon
import org.osmdroid.util.GeoPoint as OsmPoint

private fun GeoPoint.osm() = OsmPoint(lat, lon)

/**
 * Geofence editor. The fences live on the watch (configuration slots 0–7);
 * this screen reads them, lets the user draw a circle or polygon on the map,
 * validates with the firmware rules and writes the slot with SET_FENCE.
 * No coordinates are pre-loaded: the user draws them.
 */
@Composable
fun GeofencesScreen(c: AppContainer) {
    val scope = rememberCoroutineScope()
    val cfg by c.config.config.collectAsStateWithLifecycle()
    val tel by c.watch.telemetry.collectAsStateWithLifecycle()
    var slot by remember { mutableIntStateOf(0) }
    var type by remember { mutableStateOf(FenceType.CIRCLE) }
    var name by remember { mutableStateOf("") }
    var center by remember { mutableStateOf<GeoPoint?>(null) }
    var radiusM by remember { mutableStateOf(50f) }
    val verts = remember { mutableStateListOf<GeoPoint>() }
    var msg by remember { mutableStateOf<String?>(null) }
    var confirmDelete by remember { mutableStateOf(false) }
    var mapRef by remember { mutableStateOf<MapView?>(null) }

    LaunchedEffect(Unit) { if (c.watch.isReady) c.config.read().onFailure { msg = it.message } }

    fun load(s: Int, conf: WatchConfig?) {
        val f = conf?.fences?.getOrNull(s)
        slot = s
        verts.clear()
        if (f == null || f.type == FenceType.NONE) { name = ""; center = null; type = FenceType.CIRCLE; return }
        name = f.name; type = f.type
        if (f.type == FenceType.CIRCLE) { center = f.center; radiusM = (f.radiusCm / 100f).coerceIn(5f, 5000f) }
        else { center = null; verts.addAll(f.vertices) }
        (f.vertices.firstOrNull() ?: f.center).let { mapRef?.controller?.setCenter(it.osm()) }
    }
    LaunchedEffect(cfg) { load(slot, cfg) }

    val draft: Fence? = when (type) {
        FenceType.CIRCLE -> center?.let { Fence(slot, FenceType.CIRCLE, name, it, (radiusM * 100).toLong()) }
        FenceType.POLYGON -> if (verts.size >= 1) Fence(slot, FenceType.POLYGON, name, vertices = verts.toList()) else null
        else -> null
    }
    val problem = when {
        name.isBlank() -> "Pon un nombre"
        name.toByteArray().size > 15 -> "Nombre: máximo 15 caracteres"
        draft == null -> if (type == FenceType.CIRCLE) "Toca el mapa para fijar el centro" else "Toca el mapa para añadir vértices"
        else -> draft.validate()
    }

    Column(Modifier.fillMaxSize()) {
        AndroidView(
            factory = { context ->
                MapView(context).apply {
                    setTileSource(TileSourceFactory.MAPNIK)
                    setMultiTouchControls(true)
                    controller.setZoom(17.0)
                    overlays.add(MapEventsOverlay(object : MapEventsReceiver {
                        override fun singleTapConfirmedHelper(p: OsmPoint): Boolean {
                            val g = GeoPoint.of(p.latitude, p.longitude)
                            if (type == FenceType.CIRCLE) center = g else if (verts.size < Fence.MAX_VERTICES) verts.add(g)
                            return true
                        }
                        override fun longPressHelper(p: OsmPoint): Boolean = false
                    }))
                    mapRef = this
                }
            },
            update = { map ->
                // keep the events overlay (index 0), redraw the rest
                while (map.overlays.size > 1) map.overlays.removeAt(map.overlays.size - 1)
                cfg?.fences?.forEachIndexed { i, f ->
                    if (f != null && f.type != FenceType.NONE && i != slot) map.overlays.add(fencePolygon(f, AColor.argb(60, 120, 130, 140), AColor.GRAY))
                }
                draft?.let { d ->
                    val ok = problem == null
                    map.overlays.add(fencePolygon(d, AColor.argb(70, 201, 162, 39), if (ok) AColor.rgb(201, 162, 39) else AColor.rgb(229, 72, 77)))
                    if (d.type == FenceType.POLYGON) d.vertices.forEachIndexed { i, v ->
                        map.overlays.add(Marker(map).apply { position = v.osm(); title = "Vértice ${i + 1}"; setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_CENTER) })
                    }
                }
                tel?.t?.let { t -> if (t.latE7 != 0 || t.lonE7 != 0) map.overlays.add(Marker(map).apply { position = OsmPoint(t.latE7 * 1e-7, t.lonE7 * 1e-7); title = "Chaleco" }) }
                map.invalidate()
            },
            modifier = Modifier.fillMaxWidth().height(340.dp),
        )
        DisposableEffect(Unit) { onDispose { mapRef?.onDetach() } }

        Column(Modifier.verticalScroll(rememberScrollState())) {
            AvoCard("Geocerca del reloj") {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    (0 until WatchConfig.MAX_FENCES).forEach { i ->
                        val f = cfg?.fences?.getOrNull(i)
                        FilterChip(selected = slot == i, onClick = { load(i, cfg) }, label = { Text(if (f != null && f.type != FenceType.NONE) "${i + 1}" else "${i + 1}·") })
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    FilterChip(type == FenceType.CIRCLE, { type = FenceType.CIRCLE; verts.clear() }, label = { Text("Círculo") })
                    FilterChip(type == FenceType.POLYGON, { type = FenceType.POLYGON; center = null }, label = { Text("Polígono") })
                }
                OutlinedTextField(name, { name = it.take(15) }, label = { Text("Nombre") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                if (type == FenceType.CIRCLE) {
                    KV("Radio", "${radiusM.toInt()} m")
                    Slider(radiusM, { radiusM = it }, valueRange = 5f..1000f)
                } else {
                    KV("Vértices", "${verts.size} (mín. 3, máx. ${Fence.MAX_VERTICES})")
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(enabled = verts.isNotEmpty(), onClick = { verts.removeAt(verts.size - 1) }) { Text("Deshacer") }
                        OutlinedButton(enabled = verts.isNotEmpty(), onClick = { verts.clear() }) { Text("Borrar") }
                    }
                }
                OutlinedButton(onClick = {
                    tel?.t?.takeIf { it.latE7 != 0 || it.lonE7 != 0 }?.let { mapRef?.controller?.animateTo(OsmPoint(it.latE7 * 1e-7, it.lonE7 * 1e-7)) }
                        ?: run { msg = "Sin posición del chaleco" }
                }) { Text("Centrar en el chaleco") }
                Note(problem ?: "Geocerca válida", if (problem == null) AvoColors.Ok else AvoColors.Warn)
                msg?.let { Note(it, AvoColors.Info) }
                val active = cfg?.let { (it.activeMask shr slot) and 1 == 1 } ?: false
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(checked = active, enabled = cfg != null && c.watch.isReady, onCheckedChange = { on ->
                        val conf = cfg ?: return@Checkbox
                        val mask = if (on) conf.activeMask or (1 shl slot) else conf.activeMask and (1 shl slot).inv()
                        scope.launch { msg = c.config.setActive(mask and 0xFF, conf.autoEnabled) ?: "Geocercas activas actualizadas" }
                    })
                    Text("Activa para la grabación automática", color = AvoColors.Text)
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 6.dp)) {
                    Button(enabled = problem == null && c.watch.isReady, onClick = {
                        val f = draft!!.copy(name = name.trim())
                        scope.launch {
                            val err = c.config.setFence(slot, f)
                            msg = err ?: "Geocerca guardada en el reloj (hueco ${slot + 1})"
                            if (err == null) c.db.fences().upsert(FenceEntity(slot, f.name, f.type.code, f.center.latE7, f.center.lonE7, f.radiusCm,
                                f.vertices.joinToString(";") { "${it.latE7},${it.lonE7}" }, active, true))
                        }
                    }) { Text("Enviar al reloj") }
                    OutlinedButton(enabled = c.watch.isReady && cfg?.fences?.getOrNull(slot)?.type?.let { it != FenceType.NONE } == true, onClick = { confirmDelete = true }) { Text("Eliminar") }
                }
                Note("Las geocercas se guardan en el reloj. Para que el reloj grabe solo, activa la geocerca y la grabación automática (pestaña Entrenamiento).")
            }
        }
    }
    if (confirmDelete) ConfirmDialog("Eliminar geocerca", "Se borrará la geocerca del hueco ${slot + 1} en el reloj.", "Eliminar", danger = true, onConfirm = {
        scope.launch {
            val conf = cfg
            if (conf != null && (conf.activeMask shr slot) and 1 == 1) c.config.setActive(conf.activeMask and (1 shl slot).inv(), conf.autoEnabled)
            msg = c.config.setFence(slot, Fence.empty(slot)) ?: "Geocerca eliminada"
            c.db.fences().delete(slot)
        }
    }, onDismiss = { confirmDelete = false })
}

private fun fencePolygon(f: Fence, fill: Int, stroke: Int): Polygon = Polygon().apply {
    setPoints(when (f.type) {
        FenceType.CIRCLE -> circleOutline(f.center, f.radiusCm / 100.0).map { it.osm() }
        else -> f.vertices.map { it.osm() }
    })
    fillPaint.color = fill
    outlinePaint.color = stroke
    outlinePaint.strokeWidth = 5f
    title = f.name
}
