package org.avoperformance.horse.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.platform.LocalContext
import android.content.Intent
import org.avoperformance.horse.share.TrainingShare
import org.avoperformance.horse.share.TrainingImport
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.TextButton
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.first
import org.avoperformance.horse.AppContainer
import org.avoperformance.horse.core.sync.SyncState
import org.avoperformance.horse.data.TrainingEntity
import org.avoperformance.horse.data.HorseEntity
import org.avoperformance.horse.data.RiderEntity
import org.avoperformance.horse.ui.components.AvoCard
import org.avoperformance.horse.ui.components.Fmt
import org.avoperformance.horse.ui.components.KV
import org.avoperformance.horse.ui.components.Note
import org.avoperformance.horse.ui.components.StatusPill
import org.avoperformance.horse.ui.theme.AvoColors

fun syncColor(s: SyncState?) = when (s) {
    SyncState.VERIFICADO_SERVIDOR, SyncState.MARCADO_EN_RELOJ -> AvoColors.Ok
    SyncState.VERIFICADO_LOCAL, SyncState.PENDIENTE_SERVIDOR -> AvoColors.Info
    SyncState.DESCARGANDO, SyncState.DESCARGADO, SyncState.SUBIENDO, SyncState.GRABANDO -> AvoColors.Warn
    SyncState.ERROR_INTEGRIDAD -> AvoColors.Bad
    else -> AvoColors.Unknown
}

@Composable
fun HistoryScreen(c: AppContainer, go: (String) -> Unit, incomingAvo: android.net.Uri? = null, onImportHandled: () -> Unit = {}) {
    val context = LocalContext.current
    var tab by rememberSaveable { mutableIntStateOf(0) }
    val all by c.db.trainings().all().collectAsStateWithLifecycle(emptyList())
    val progress by c.sync.progress.collectAsStateWithLifecycle()
    // modo descarga: pantalla encendida mientras se descarga (evita que Android limite el Bluetooth en segundo plano)
    val view = androidx.compose.ui.platform.LocalView.current
    DisposableEffect(progress.busy) { view.keepScreenOn = progress.busy; onDispose { view.keepScreenOn = false } }
    var msg by remember { mutableStateOf<String?>(null) }
    var horseFilter by remember { mutableStateOf("") }
    var dateFilter by remember { mutableStateOf("") }
    var sessionFilter by remember { mutableStateOf("") }
    val savedHorses by c.db.horses().all().collectAsStateWithLifecycle(emptyList())
    val savedRiders by c.db.riders().all().collectAsStateWithLifecycle(emptyList())
    var shareCandidate by remember { mutableStateOf<TrainingEntity?>(null) }
    var shareHorseName by remember { mutableStateOf("") }
    var shareRiderName by remember { mutableStateOf("") }
    var horseOptionsVisible by remember { mutableStateOf(false) }
    var riderOptionsVisible by remember { mutableStateOf(false) }
    fun shareSelected(t: TrainingEntity) {
        val horse = savedHorses.firstOrNull { it.code == t.horseCode }?.name.orEmpty()
        val rider = savedRiders.firstOrNull { it.code == t.riderCode }?.name.orEmpty()
        if (horse.isBlank() || rider.isBlank()) {
            shareCandidate = t
            shareHorseName = horse
            shareRiderName = rider
        } else c.scope.launch {
            try { context.startActivity(Intent.createChooser(TrainingShare.prepare(context, t, horse, rider),
                c.settings.shareDefaultFavorite.takeIf { it.isNotBlank() }?.let { "Compartir · favorito: $it" } ?: "Compartir entrenamiento")) }
            catch (e: Exception) { msg = e.message ?: "No se pudo compartir" }
        }
    }
    // ---- WhatsApp: download if needed, send, then delete from the phone (the watch keeps its copy)
    var whatsAppPending by remember { mutableStateOf<String?>(null) }
    val whatsAppLauncher = rememberLauncherForActivityResult(androidx.activity.result.contract.ActivityResultContracts.StartActivityForResult()) {
        val id = whatsAppPending ?: return@rememberLauncherForActivityResult
        whatsAppPending = null
        if (c.settings.deleteAfterWhatsApp) c.scope.launch { msg = c.sync.deleteLocal(id) ?: "Enviado por WhatsApp y borrado del móvil (sigue en el reloj)" }
    }
    fun whatsApp(t: TrainingEntity) = c.scope.launch {
        try {
            var current = c.db.trainings().byId(t.sessionId) ?: error("Sesión no encontrada")
            if (current.localSha256 == null || current.localSha256 != current.watchSha256) {
                msg = "Descargando para enviar por WhatsApp…"
                val err = c.sync.download(t.sessionId); if (err != null) error(err)
                current = c.db.trainings().byId(t.sessionId) ?: error("Sesión no disponible")
            }
            val horse = savedHorses.firstOrNull { it.code == current.horseCode }?.name.orEmpty()
            val rider = savedRiders.firstOrNull { it.code == current.riderCode }?.name.orEmpty()
            if (horse.isBlank() || rider.isBlank()) { shareSelected(current); msg = "Asigna caballo y jinete; después pulsa WhatsApp otra vez"; return@launch }
            val intent = TrainingShare.prepare(context, current, horse, rider)
            val pkg = listOf("com.whatsapp", "com.whatsapp.w4b").firstOrNull { p -> runCatching { context.packageManager.getPackageInfo(p, 0) }.isSuccess }
                ?: error("WhatsApp no está instalado")
            intent.setPackage(pkg)
            whatsAppPending = current.sessionId
            whatsAppLauncher.launch(intent)
        } catch (e: Exception) { msg = e.message ?: "No se pudo enviar por WhatsApp" }
    }
    var confirmDeleteLocal by remember { mutableStateOf<TrainingEntity?>(null) }
    confirmDeleteLocal?.let { d ->
        AlertDialog(onDismissRequest = { confirmDeleteLocal = null },
            title = { Text("Borrar del móvil") },
            text = { Text("Se borra la copia del teléfono de ${d.sessionId}. La del reloj no se toca y se puede volver a descargar mientras siga en el reloj.") },
            confirmButton = { TextButton(onClick = { confirmDeleteLocal = null; c.scope.launch { msg = c.sync.deleteLocal(d.sessionId) ?: "Borrado del móvil" } }) { Text("Borrar", color = AvoColors.Bad) } },
            dismissButton = { TextButton(onClick = { confirmDeleteLocal = null }) { Text("Cancelar") } })
    }
    shareCandidate?.let { pending ->
        AlertDialog(
            onDismissRequest = { shareCandidate = null },
            title = { Text("Identificar entrenamiento") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Selecciona caballo y jinete. Puedes escribir un nombre nuevo; se guardará para próximos entrenamientos.")
                    OutlinedTextField(value = shareHorseName, onValueChange = { shareHorseName = it }, label = { Text("Caballo") }, singleLine = true)
                    OutlinedButton(onClick = { horseOptionsVisible = true }) { Text("Elegir caballo guardado") }
                    DropdownMenu(expanded = horseOptionsVisible, onDismissRequest = { horseOptionsVisible = false }) {
                        savedHorses.forEach { h -> DropdownMenuItem(text = { Text(h.name) }, onClick = { shareHorseName = h.name; horseOptionsVisible = false }) }
                    }
                    OutlinedTextField(value = shareRiderName, onValueChange = { shareRiderName = it }, label = { Text("Jinete") }, singleLine = true)
                    OutlinedButton(onClick = { riderOptionsVisible = true }) { Text("Elegir jinete guardado") }
                    DropdownMenu(expanded = riderOptionsVisible, onDismissRequest = { riderOptionsVisible = false }) {
                        savedRiders.forEach { r -> DropdownMenuItem(text = { Text(r.name) }, onClick = { shareRiderName = r.name; riderOptionsVisible = false }) }
                    }
                }
            },
            confirmButton = {
                TextButton(enabled = shareHorseName.trim().isNotEmpty() && shareRiderName.trim().isNotEmpty(), onClick = {
                    val horse = shareHorseName.trim().take(120)
                    val rider = shareRiderName.trim().take(120)
                    shareCandidate = null
                    c.scope.launch {
                        try {
                            val existingHorse = savedHorses.firstOrNull { it.name.equals(horse, true) }
                            val existingRider = savedRiders.firstOrNull { it.name.equals(rider, true) }
                            val horseCode = existingHorse?.code ?: "H_" + java.util.UUID.randomUUID().toString().take(16)
                            val riderCode = existingRider?.code ?: "R_" + java.util.UUID.randomUUID().toString().take(16)
                            if (existingHorse == null) c.db.horses().insert(HorseEntity(code = horseCode, name = horse))
                            if (existingRider == null) c.db.riders().insert(RiderEntity(code = riderCode, name = rider))
                            val linked = pending.copy(horseCode = horseCode, riderCode = riderCode)
                            c.db.trainings().upsert(linked)
                            context.startActivity(Intent.createChooser(TrainingShare.prepare(context, linked, horse, rider),
                                c.settings.shareDefaultFavorite.takeIf { it.isNotBlank() }?.let { "Compartir · favorito: $it" } ?: "Compartir entrenamiento"))
                        } catch (e: Exception) { msg = e.message ?: "Error al preparar entrenamiento" }
                    }
                }) { Text("Guardar y compartir") }
            },
            dismissButton = { TextButton(onClick = { shareCandidate = null }) { Text("Cancelar") } }
        )
    }

    var pendingImport by remember { mutableStateOf<TrainingImport.Preview?>(null) }
    LaunchedEffect(incomingAvo) {
        if (incomingAvo != null) {
            try {
                pendingImport?.let(TrainingImport::discard)
                pendingImport = TrainingImport.inspect(c, incomingAvo)
                tab = 1
            } catch (e: Exception) {
                msg = e.message ?: "No se pudo abrir el entrenamiento recibido"
            } finally { onImportHandled() }
        }
    }
    val openAvo = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) c.scope.launch {
            try { pendingImport?.let(TrainingImport::discard); pendingImport = TrainingImport.inspect(c, uri) }
            catch (e: Exception) { msg = e.message ?: "No se pudo leer el archivo AVO" }
        }
    }
    pendingImport?.let { pending ->
        AlertDialog(
            onDismissRequest = { TrainingImport.discard(pending); pendingImport = null },
            title = { Text(if (pending.duplicate) "Entrenamiento ya existente" else "Importar entrenamiento") },
            text = { Text("${pending.horseName} · ${pending.riderName}\nSesión: ${pending.sessionId}\n" +
                if (pending.identical) "Este archivo es idéntico al guardado." else if (pending.duplicate) "Ya existe esta sesión. ¿Actualizarla o descartarla?" else "¿Guardar este entrenamiento y registrar el caballo y jinete si faltan?") },
            confirmButton = { TextButton(enabled = !pending.identical, onClick = {
                pendingImport = null
                c.scope.launch { try { msg = TrainingImport.import(c, pending) } catch (e: Exception) { msg = e.message ?: "Error al importar" } }
            }) { Text(if (pending.duplicate) "Actualizar" else "Importar") } },
            dismissButton = { TextButton(onClick = { TrainingImport.discard(pending); pendingImport = null }) { Text("Descartar") } }
        )
    }
    var compareFirst by remember { mutableStateOf<String?>(null) }
    var compareSecond by remember { mutableStateOf<String?>(null) }
    Column(Modifier.fillMaxSize()) {
        TabRow(selectedTabIndex = tab, containerColor = AvoColors.Bg, contentColor = AvoColors.Gold) {
            Tab(tab == 0, { tab = 0 }, text = { Text("Entrenamientos del chaleco") })
            Tab(tab == 1, { tab = 1 }, text = { Text("Mis entrenamientos") })
        }
        if (tab == 0) {
            Row(Modifier.fillMaxWidth().padding(12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                OutlinedButton(enabled = !progress.busy, onClick = { c.scope.launch { msg = c.sync.refresh() } }) { Text("Leer lista del reloj") }
                OutlinedButton(enabled = !progress.busy, onClick = { c.sync.autoSync() }) { Text("Descargar todo") }
            }
            progress.message?.let { Note(it) }
            msg?.let { Note(it, AvoColors.Warn) }
            if (progress.busy && progress.total > 0) LinearProgressIndicator(progress = { (progress.bytes.toFloat() / progress.total).coerceIn(0f, 1f) }, modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp))
            LazyColumn {
                items(all, key = { it.sessionId }) { t -> TrainingRow(t, onOpen = { go("detalle/${t.sessionId}") }, onDownload = { c.scope.launch { msg = c.sync.download(t.sessionId) } }, onShare = { c.scope.launch {
                    try {
                        var current = c.db.trainings().byId(t.sessionId) ?: error("Sesión no encontrada")
                        if (current.localSha256 == null || current.localSha256 != current.watchSha256) {
                            val err = c.sync.download(t.sessionId); if (err != null) error(err)
                            current = c.db.trainings().byId(t.sessionId) ?: error("Sesión no disponible")
                        }
                        shareSelected(current)
                    } catch (e: Exception) { msg = e.message ?: "No se pudo compartir" }
                } }, onWhatsApp = { whatsApp(t) }, onDeleteLocal = { confirmDeleteLocal = t }) }
                if (all.isEmpty()) item { Note("Sin entrenamientos") }
            }
        } else {
            val mine = all.filter { t ->
                val horseMatches = horseFilter.isBlank() || t.horseCode?.contains(horseFilter, ignoreCase = true) == true ||
                    savedHorses.any { it.code == t.horseCode && it.name.contains(horseFilter, ignoreCase = true) }
                val dateMatches = dateFilter.isBlank() || (Fmt.date(t.startRtcMs) ?: "").contains(dateFilter, ignoreCase = true)
                val sessionMatches = sessionFilter.isBlank() || t.sessionId.contains(sessionFilter, ignoreCase = true)
                t.localDir != null && t.downloadedBytes > 0 && horseMatches && dateMatches && sessionMatches
            }
            LazyColumn {
                item {
                    AvoCard("Importar entrenamientos recibidos") {
                        OutlinedButton(onClick = { openAvo.launch(arrayOf("application/zip", "application/octet-stream", "*/*")) }) { Text("Abrir archivo .avo recibido") }
                        msg?.let { Note(it) }
                    }
                    AvoCard("Análisis y comparación") {
                        TextField(value = horseFilter, onValueChange = { horseFilter = it }, label = { Text("Filtrar por caballo (nombre o código)") }, singleLine = true)
                        TextField(value = dateFilter, onValueChange = { dateFilter = it }, label = { Text("Filtrar por fecha") }, singleLine = true)
                        TextField(value = sessionFilter, onValueChange = { sessionFilter = it }, label = { Text("Buscar identificador de sesión") }, singleLine = true)
                        OutlinedButton(onClick = { horseFilter = ""; dateFilter = ""; sessionFilter = "" }) { Text("Limpiar filtros") }
                        KV("Resultados", "${mine.size} de ${all.count { it.localDir != null && it.downloadedBytes > 0 }}")
                        val eligible = mine.filter { it.horseCode != null }
                        eligible.forEach { t ->
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text((t.horseCode ?: "") + " · " + (Fmt.date(t.startRtcMs) ?: t.sessionId), modifier = Modifier.weight(1f), maxLines = 1)
                                OutlinedButton(onClick = { compareFirst = t.sessionId }) { Text(if (compareFirst == t.sessionId) "A ✓" else "A") }
                                OutlinedButton(onClick = { compareSecond = t.sessionId }) { Text(if (compareSecond == t.sessionId) "B ✓" else "B") }
                            }
                        }
                        val first = all.firstOrNull { it.sessionId == compareFirst }
                        val second = all.firstOrNull { it.sessionId == compareSecond }
                        OutlinedButton(enabled = first != null && second != null && first.sessionId != second.sessionId && first.horseCode == second.horseCode,
                            onClick = { go("comparar/${first?.sessionId}/${second?.sessionId}") }) { Text("Comparar entrenamientos") }
                        if (first != null && second != null && first.horseCode != second.horseCode) Note("La comparación requiere el mismo caballo", AvoColors.Warn)
                    }
                }
                item {
                    AvoCard("Servidor") {
                        KV("Estado", if (c.sync.serverConfigured) "Conectado" else "En pausa · copias en el teléfono")
                    }
                }
                items(mine, key = { it.sessionId }) { t -> TrainingRow(t, onOpen = { go("detalle/${t.sessionId}") }, onDownload = null, onShare = { shareSelected(t) }, onWhatsApp = { whatsApp(t) }, onDeleteLocal = { confirmDeleteLocal = t }) }
                if (mine.isEmpty()) item { Note("Sin entrenamientos descargados") }
            }
        }
    }
}

@Composable
private fun TrainingRow(t: TrainingEntity, onOpen: () -> Unit, onDownload: (() -> Unit)?, onShare: (() -> Unit)?, onWhatsApp: (() -> Unit)? = null, onDeleteLocal: (() -> Unit)? = null) {
    val st = runCatching { SyncState.valueOf(t.state) }.getOrNull()
    AvoCard(onClick = onOpen) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(Fmt.date(t.startRtcMs) ?: "Fecha desconocida", color = AvoColors.Text, fontWeight = androidx.compose.ui.text.font.FontWeight.Bold, fontSize = 16.sp)
                Text(t.sessionId, color = AvoColors.TextDim, fontSize = 12.sp)
            }
            StatusPill(st?.texto?.substringBefore(" (")?.take(26) ?: t.state, syncColor(st))
        }
        KV("Caballo / jinete", listOfNotNull(t.horseCode, t.riderCode).joinToString(" / ").ifBlank { null })
        androidx.compose.foundation.layout.Spacer(Modifier.padding(top = 6.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            org.avoperformance.horse.ui.components.MetricTile("Tiempo", Fmt.duration(t.activeMs), "", Modifier.weight(1f))
            org.avoperformance.horse.ui.components.MetricTile("Distancia", t.distanceM?.let { Fmt.m(it / 1000.0, 2) }, "km", Modifier.weight(1f))
            org.avoperformance.horse.ui.components.MetricTile("V. máx", t.maxSpeedMs?.let { Fmt.kmh(it) }, "km/h", Modifier.weight(1f), AvoColors.Red)
        }
        KV("Tamaño", if (t.downloadedBytes in 1 until t.totalBytes) "${Fmt.bytes(t.downloadedBytes)} de ${Fmt.bytes(t.totalBytes)}" else Fmt.bytes(t.totalBytes))
        t.lastError?.let { Note(it, AvoColors.Warn) }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (onShare != null) OutlinedButton(onClick = onShare) { Text("Compartir") }
            if (onWhatsApp != null) OutlinedButton(onClick = onWhatsApp) { Text("WhatsApp") }
        }
        if (onDeleteLocal != null && t.localDir != null) androidx.compose.material3.TextButton(onClick = onDeleteLocal) { Text("Borrar del móvil", color = AvoColors.Bad) }
        if (onDownload != null && (st == SyncState.EN_RELOJ || st == SyncState.DESCARGANDO || st == SyncState.ERROR_INTEGRIDAD))
            OutlinedButton(onClick = onDownload) { Text(if (t.downloadedBytes > 0) "Reanudar descarga" else "Descargar") }
    }
}


private suspend fun prepareShareWithNames(c: AppContainer, context: android.content.Context, t: TrainingEntity): Intent {
    val horses = c.db.horses().all().first()
    val riders = c.db.riders().all().first()
    val horse = horses.firstOrNull { it.code == t.horseCode }?.name.orEmpty()
    val rider = riders.firstOrNull { it.code == t.riderCode }?.name.orEmpty()
    return TrainingShare.prepare(context, t, horse, rider)
}
