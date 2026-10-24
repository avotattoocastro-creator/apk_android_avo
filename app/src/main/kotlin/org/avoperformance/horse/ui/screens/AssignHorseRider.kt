package org.avoperformance.horse.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.launch
import org.avoperformance.horse.AppContainer
import org.avoperformance.horse.data.HorseEntity
import org.avoperformance.horse.data.RiderEntity
import org.avoperformance.horse.data.TrainingEntity
import org.avoperformance.horse.ui.components.Note
import org.avoperformance.horse.ui.theme.AvoColors

/**
 * Assigns (or changes) the horse and rider of a downloaded training. You can pick saved ones or
 * type a new name (it is saved in Cuadra/Jinetes). Only changes the training's metadata on the phone;
 * the RAW data and the watch are not touched.
 */
@Composable
fun AssignHorseRiderDialog(c: AppContainer, t: TrainingEntity, onDismiss: () -> Unit, onDone: (TrainingEntity) -> Unit = {}) {
    val horses by c.db.horses().all().collectAsStateWithLifecycle(emptyList())
    val riders by c.db.riders().all().collectAsStateWithLifecycle(emptyList())
    var horse by remember(t.sessionId, horses) { mutableStateOf(horses.firstOrNull { it.code == t.horseCode }?.name.orEmpty()) }
    var rider by remember(t.sessionId, riders) { mutableStateOf(riders.firstOrNull { it.code == t.riderCode }?.name.orEmpty()) }
    var horseMenu by remember { mutableStateOf(false) }
    var riderMenu by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    AlertDialog(onDismissRequest = onDismiss, title = { Text("Caballo y jinete") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(horse, { horse = it.take(120) }, label = { Text("Caballo") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                if (horses.isNotEmpty()) {
                    OutlinedButton(onClick = { horseMenu = true }) { Text("Elegir caballo guardado") }
                    DropdownMenu(expanded = horseMenu, onDismissRequest = { horseMenu = false }) {
                        horses.forEach { h -> DropdownMenuItem(text = { Text(h.name) }, onClick = { horse = h.name; horseMenu = false }) }
                    }
                }
                OutlinedTextField(rider, { rider = it.take(120) }, label = { Text("Jinete") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                if (riders.isNotEmpty()) {
                    OutlinedButton(onClick = { riderMenu = true }) { Text("Elegir jinete guardado") }
                    DropdownMenu(expanded = riderMenu, onDismissRequest = { riderMenu = false }) {
                        riders.forEach { r -> DropdownMenuItem(text = { Text(r.name) }, onClick = { rider = r.name; riderMenu = false }) }
                    }
                }
                error?.let { Note(it, AvoColors.Bad) }
            }
        },
        confirmButton = {
            Button(enabled = horse.isNotBlank() && rider.isNotBlank(), onClick = {
                scope.launch {
                    try {
                        val h = horse.trim(); val r = rider.trim()
                        val eh = horses.firstOrNull { it.name.equals(h, true) }
                        val er = riders.firstOrNull { it.name.equals(r, true) }
                        val hc = eh?.code ?: ("H_" + java.util.UUID.randomUUID().toString().take(16))
                        val rc = er?.code ?: ("R_" + java.util.UUID.randomUUID().toString().take(16))
                        if (eh == null) c.db.horses().insert(HorseEntity(code = hc, name = h))
                        if (er == null) c.db.riders().insert(RiderEntity(code = rc, name = r))
                        val current = c.db.trainings().byId(t.sessionId) ?: t
                        val linked = current.copy(horseCode = hc, riderCode = rc, updatedMs = System.currentTimeMillis())
                        c.db.trainings().upsert(linked)
                        onDone(linked)
                    } catch (e: Exception) { error = e.message ?: "No se pudo guardar" }
                }
            }) { Text("Guardar") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancelar") } })
}
