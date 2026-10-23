package org.avoperformance.horse.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.launch
import org.avoperformance.horse.AppContainer
import org.avoperformance.horse.core.ble.SessionCmd
import org.avoperformance.horse.core.ble.WatchSessionState
import org.avoperformance.horse.core.telemetry.RtkDeriver
import org.avoperformance.horse.core.telemetry.SessionCommandTracker
import org.avoperformance.horse.data.HorseEntity
import org.avoperformance.horse.data.RiderEntity
import org.avoperformance.horse.ui.components.AvoCard
import org.avoperformance.horse.ui.components.ConfirmDialog
import org.avoperformance.horse.ui.components.Fmt
import org.avoperformance.horse.ui.components.KV
import org.avoperformance.horse.ui.components.Note
import org.avoperformance.horse.ui.theme.AvoColors

@Composable
fun TrainingScreen(c: AppContainer, go: (String) -> Unit) {
    val scope = rememberCoroutineScope()
    val horses by c.db.horses().all().collectAsStateWithLifecycle(emptyList())
    val riders by c.db.riders().all().collectAsStateWithLifecycle(emptyList())
    val tel by c.watch.telemetry.collectAsStateWithLifecycle()
    val link by c.watch.state.collectAsStateWithLifecycle()
    val cmd by c.watch.commandTracker.collectAsStateWithLifecycle()
    val cfg by c.config.config.collectAsStateWithLifecycle()
    val now = rememberNow()
    var selHorse by remember { mutableLongStateOf(c.settings.selectedHorseId) }
    var selRider by remember { mutableLongStateOf(c.settings.selectedRiderId) }
    var msg by remember { mutableStateOf<String?>(null) }
    var confirmStop by remember { mutableStateOf(false) }
    var confirmStart by remember { mutableStateOf(false) }
    val fresh = tel != null && now - tel!!.receivedMs <= RtkDeriver.TELEMETRY_STALE_MS
    val session = if (fresh) tel!!.t.session else null
    val ready = c.watch.isReady
    val busy = cmd is SessionCommandTracker.State.Sending || cmd is SessionCommandTracker.State.WaitingTelemetry

    LaunchedEffect(link) { if (c.watch.isReady && c.config.config.value == null) c.config.read() }

    fun send(command: SessionCmd, stopConfirmed: Boolean = false) = scope.launch {
        msg = null
        val err = c.watch.sessionCommand(command, stopConfirmed)
        msg = err ?: when (command) {
            SessionCmd.START -> "Grabación iniciada (confirmada por el reloj)"
            SessionCmd.STOP -> "Grabación detenida (confirmada por el reloj)"
            SessionCmd.PAUSE -> "En pausa (confirmado por el reloj)"
            SessionCmd.RESUME -> "Reanudada (confirmado por el reloj)"
            SessionCmd.MARKER -> "Marcador guardado"
            SessionCmd.REARM -> "Rearmado"
        }
        c.watch.resetCommand()
    }

    LazyColumn(Modifier.fillMaxSize(), contentPadding = androidx.compose.foundation.layout.PaddingValues(vertical = 6.dp)) {
        item {
            AvoCard("Caballo y jinete") {
                Picker("Caballo", horses.firstOrNull { it.id == selHorse }?.let { "${it.code} · ${it.name}" }, horses.map { it.id to "${it.code} · ${it.name}" }) {
                    selHorse = it; c.settings.selectedHorseId = it
                }
                Picker("Jinete", riders.firstOrNull { it.id == selRider }?.let { "${it.code} · ${it.name}" }, riders.map { it.id to "${it.code} · ${it.name}" }) {
                    selRider = it; c.settings.selectedRiderId = it
                }
                KV("En el reloj", cfg?.let { "${it.horseName.ifBlank { "—" }} / ${it.riderName.ifBlank { "—" }}" })
                Spacer(Modifier.height(6.dp))
                OutlinedButton(enabled = ready && session != WatchSessionState.RECORDING, onClick = {
                    val h: HorseEntity? = horses.firstOrNull { it.id == selHorse }
                    val r: RiderEntity? = riders.firstOrNull { it.id == selRider }
                    if (h == null) msg = "Selecciona un caballo"
                    else scope.launch { msg = c.config.setIdentity(h.id, h.code, r?.id ?: 0, r?.code ?: "") ?: "Caballo y jinete guardados en el reloj" }
                }) { Text("Enviar al reloj") }
            }
        }
        item {
            AvoCard("Grabación", trailing = { if (session == WatchSessionState.RECORDING) org.avoperformance.horse.ui.components.StatusPill("REC", AvoColors.Red) }) {
                val tt = if (fresh) tel!!.t else null
                org.avoperformance.horse.ui.components.MetricGrid(listOf(
                    { m -> org.avoperformance.horse.ui.components.MetricTile("Tiempo", tt?.let { Fmt.duration(it.activeMs) }, "", m) },
                    { m -> org.avoperformance.horse.ui.components.MetricTile("Distancia", tt?.let { Fmt.m(it.distanceCm / 100.0, 0) }, "m", m) },
                    { m -> org.avoperformance.horse.ui.components.MetricTile("Velocidad", tt?.let { Fmt.kmh(it.speedMmS / 1000.0) }, "km/h", m, AvoColors.Blue) },
                ))
                Spacer(Modifier.height(8.dp))
                KV("Estado del reloj", session?.texto ?: if (ready) "esperando telemetría" else link.texto)
                KV("Geocerca", if (fresh) tel!!.t.geofence.texto else null)
                KV("Tiempo activo", if (fresh) Fmt.duration(tel!!.t.activeMs) else null)
                when (val s = cmd) {
                    is SessionCommandTracker.State.Sending -> Note("Enviando ${s.cmd.name}…", AvoColors.Warn)
                    is SessionCommandTracker.State.WaitingTelemetry -> Note("Esperando confirmación del reloj…", AvoColors.Warn)
                    else -> {}
                }
                msg?.let { Note(it, if (it.contains("confirmad") || it.contains("guardad")) AvoColors.Ok else AvoColors.Warn) }
                Spacer(Modifier.height(8.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    val canStart = ready && !busy && (session == WatchSessionState.IDLE || session == WatchSessionState.ARMED || session == WatchSessionState.COMPLETED || session == WatchSessionState.STOPPED_WAITING_UPLOAD)
                    Button(enabled = canStart, onClick = { confirmStart = true }, modifier = Modifier.weight(1f),
                        colors = ButtonDefaults.buttonColors(containerColor = AvoColors.Red)) { Text("▶  INICIAR", fontWeight = androidx.compose.ui.text.font.FontWeight.Black) }
                    val canStop = ready && !busy && (session == WatchSessionState.RECORDING || session == WatchSessionState.PAUSED)
                    Button(enabled = canStop, onClick = { confirmStop = true }, modifier = Modifier.weight(1f),
                        colors = ButtonDefaults.buttonColors(containerColor = AvoColors.Surface2, contentColor = AvoColors.Text)) { Text("■  DETENER", fontWeight = androidx.compose.ui.text.font.FontWeight.Black) }
                }
                Row(Modifier.fillMaxWidth().padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(enabled = ready && !busy && session == WatchSessionState.RECORDING, onClick = { send(SessionCmd.PAUSE) }, modifier = Modifier.weight(1f)) { Text("Pausar") }
                    OutlinedButton(enabled = ready && !busy && session == WatchSessionState.PAUSED, onClick = { send(SessionCmd.RESUME) }, modifier = Modifier.weight(1f)) { Text("Reanudar") }
                    OutlinedButton(enabled = ready && !busy && session == WatchSessionState.RECORDING, onClick = { send(SessionCmd.MARKER) }, modifier = Modifier.weight(1f)) { Text("Marca") }
                }
            }
        }
        item {
            AvoCard("Grabación automática por geocerca") {
                val conf = cfg
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text("Automática", color = AvoColors.Text, modifier = Modifier.weight(1f))
                    Switch(checked = conf?.autoEnabled == true, enabled = ready && conf != null && !busy, onCheckedChange = { on ->
                        scope.launch { msg = c.config.setActive(conf!!.activeMask, on) ?: if (on) "Automática activada" else "Automática desactivada" }
                    })
                }
                val active = conf?.fences?.withIndex()?.filter { (i, f) -> f != null && (conf.activeMask shr i) and 1 == 1 && f.type.code != 0 }?.joinToString { it.value!!.name }
                KV("Geocercas activas", active?.ifBlank { "ninguna" })
                KV("Precisión mínima para decidir", conf?.let { "${it.hAccMaxCm / 100.0} m" })
                OutlinedButton(onClick = { go("geocercas") }) { Text("Editar geocercas") }
            }
        }
    }

    if (confirmStart) ConfirmDialog("Iniciar grabación", "¿Iniciar ahora una grabación manual en el chaleco?", "Iniciar",
        onConfirm = { send(SessionCmd.START) }, onDismiss = { confirmStart = false })
    if (confirmStop) ConfirmDialog("Detener grabación", "La sesión se cerrará en el reloj. ¿Detener la grabación?", "Detener", danger = true,
        onConfirm = { send(SessionCmd.STOP, stopConfirmed = true) }, onDismiss = { confirmStop = false })
}

@Composable
fun Picker(label: String, current: String?, options: List<Pair<Long, String>>, onPick: (Long) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, color = AvoColors.TextDim, modifier = Modifier.weight(1f))
        OutlinedButton(onClick = { open = true }) { Text(current ?: if (options.isEmpty()) "Crea uno primero" else "Elegir") }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            options.forEach { (id, text) -> DropdownMenuItem(text = { Text(text) }, onClick = { open = false; onPick(id) }) }
        }
    }
}
