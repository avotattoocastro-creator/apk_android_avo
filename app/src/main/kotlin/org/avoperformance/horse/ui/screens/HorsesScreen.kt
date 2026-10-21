package org.avoperformance.horse.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.launch
import org.avoperformance.horse.AppContainer
import org.avoperformance.horse.data.HorseEntity
import org.avoperformance.horse.data.RiderEntity
import org.avoperformance.horse.ui.components.AvoCard
import org.avoperformance.horse.ui.components.ConfirmDialog
import org.avoperformance.horse.ui.components.KV
import org.avoperformance.horse.ui.components.Note
import org.avoperformance.horse.ui.components.StatusPill
import org.avoperformance.horse.ui.theme.AvoColors

/** Codes travel to the watch (max 23 bytes, written into each file header). */
fun codeProblem(code: String): String? = when {
    code.isBlank() -> "El código es obligatorio"
    code.toByteArray(Charsets.UTF_8).size > 23 -> "Máximo 23 caracteres"
    !Regex("^[A-Za-z0-9_\\-]+$").matches(code) -> "Usa solo letras, números, _ y -"
    else -> null
}

@Composable
fun HorsesScreen(c: AppContainer, go: (String) -> Unit) {
    val horses by c.db.horses().all().collectAsStateWithLifecycle(emptyList())
    val scope = rememberCoroutineScope()
    var editing by remember { mutableStateOf<HorseEntity?>(null) }
    var deleting by remember { mutableStateOf<HorseEntity?>(null) }
    var selected by remember { mutableLongStateOf(c.settings.selectedHorseId) }
    LazyColumn(Modifier.fillMaxSize()) {
        item {
            Row(Modifier.fillMaxWidth().padding(12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = { editing = HorseEntity(code = "", name = "") }) { Text("Nuevo caballo") }
                OutlinedButton(onClick = { go("jinetes") }) { Text("Jinetes") }
            }
        }
        items(horses, key = { it.id }) { h ->
            AvoCard(onClick = { selected = h.id; c.settings.selectedHorseId = h.id }) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Column(Modifier.weight(1f)) {
                        Text(h.name, color = AvoColors.Text, fontSize = 17.sp)
                        Text(h.code, color = AvoColors.TextDim, fontSize = 13.sp)
                    }
                    if (selected == h.id) StatusPill("Seleccionado", AvoColors.Gold)
                }
                if (h.breed.isNotBlank()) KV("Raza", h.breed)
                h.birthYear?.let { KV("Año de nacimiento", "$it") }
                if (h.notes.isNotBlank()) Note(h.notes)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TextButton(onClick = { editing = h }) { Text("Editar") }
                    TextButton(onClick = { deleting = h }) { Text("Eliminar", color = AvoColors.Bad) }
                }
            }
        }
        if (horses.isEmpty()) item { Note("Añade tu primer caballo (por ejemplo, código HORSE_001).") }
    }
    editing?.let { h ->
        HorseDialog(h, onDismiss = { editing = null }) { n ->
            scope.launch {
                runCatching { if (n.id == 0L) c.db.horses().insert(n) else c.db.horses().update(n) }
                    .onFailure { c.log.w("DB", "caballo: ${it.message}") }
                editing = null
            }
        }
    }
    deleting?.let { h ->
        ConfirmDialog("Eliminar caballo", "¿Eliminar ${h.name} (${h.code}) de la app? Los entrenamientos ya grabados no se borran.", "Eliminar", danger = true,
            onConfirm = { scope.launch { c.db.horses().delete(h.id) } }, onDismiss = { deleting = null })
    }
}

@Composable
private fun HorseDialog(h: HorseEntity, onDismiss: () -> Unit, onSave: (HorseEntity) -> Unit) {
    var code by remember { mutableStateOf(h.code) }
    var name by remember { mutableStateOf(h.name) }
    var breed by remember { mutableStateOf(h.breed) }
    var year by remember { mutableStateOf(h.birthYear?.toString() ?: "") }
    var notes by remember { mutableStateOf(h.notes) }
    val err = codeProblem(code) ?: if (name.isBlank()) "El nombre es obligatorio" else null
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (h.id == 0L) "Nuevo caballo" else "Editar caballo") },
        text = {
            Column {
                OutlinedTextField(code, { code = it.trim().uppercase() }, label = { Text("Código (p. ej. HORSE_001)") }, singleLine = true)
                OutlinedTextField(name, { name = it }, label = { Text("Nombre") }, singleLine = true)
                OutlinedTextField(breed, { breed = it }, label = { Text("Raza") }, singleLine = true)
                OutlinedTextField(year, { year = it.filter(Char::isDigit).take(4) }, label = { Text("Año de nacimiento") }, singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
                OutlinedTextField(notes, { notes = it }, label = { Text("Notas") })
                err?.let { Text(it, color = AvoColors.Bad) }
            }
        },
        confirmButton = { TextButton(enabled = err == null, onClick = { onSave(h.copy(code = code, name = name.trim(), breed = breed.trim(), birthYear = year.toIntOrNull(), notes = notes.trim())) }) { Text("Guardar") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancelar") } },
    )
}

@Composable
fun RidersScreen(c: AppContainer) {
    val riders by c.db.riders().all().collectAsStateWithLifecycle(emptyList())
    val scope = rememberCoroutineScope()
    var editing by remember { mutableStateOf<RiderEntity?>(null) }
    var deleting by remember { mutableStateOf<RiderEntity?>(null) }
    var selected by remember { mutableLongStateOf(c.settings.selectedRiderId) }
    LazyColumn(Modifier.fillMaxSize()) {
        item { Button(onClick = { editing = RiderEntity(code = "", name = "") }, modifier = Modifier.padding(12.dp)) { Text("Nuevo jinete") } }
        items(riders, key = { it.id }) { r ->
            AvoCard(onClick = { selected = r.id; c.settings.selectedRiderId = r.id }) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Column(Modifier.weight(1f)) {
                        Text(r.name, color = AvoColors.Text, fontSize = 17.sp)
                        Text(r.code, color = AvoColors.TextDim, fontSize = 13.sp)
                    }
                    if (selected == r.id) StatusPill("Seleccionado", AvoColors.Gold)
                }
                if (r.notes.isNotBlank()) Note(r.notes)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TextButton(onClick = { editing = r }) { Text("Editar") }
                    TextButton(onClick = { deleting = r }) { Text("Eliminar", color = AvoColors.Bad) }
                }
            }
        }
        if (riders.isEmpty()) item { Note("Añade un jinete para asociarlo a los entrenamientos.") }
    }
    editing?.let { r ->
        var code by remember(r) { mutableStateOf(r.code) }
        var name by remember(r) { mutableStateOf(r.name) }
        var notes by remember(r) { mutableStateOf(r.notes) }
        val err = codeProblem(code) ?: if (name.isBlank()) "El nombre es obligatorio" else null
        AlertDialog(
            onDismissRequest = { editing = null },
            title = { Text(if (r.id == 0L) "Nuevo jinete" else "Editar jinete") },
            text = {
                Column {
                    OutlinedTextField(code, { code = it.trim().uppercase() }, label = { Text("Código (p. ej. RIDER_001)") }, singleLine = true)
                    OutlinedTextField(name, { name = it }, label = { Text("Nombre") }, singleLine = true)
                    OutlinedTextField(notes, { notes = it }, label = { Text("Notas") })
                    err?.let { Text(it, color = AvoColors.Bad) }
                }
            },
            confirmButton = {
                TextButton(enabled = err == null, onClick = {
                    val n = r.copy(code = code, name = name.trim(), notes = notes.trim())
                    scope.launch {
                        runCatching { if (n.id == 0L) c.db.riders().insert(n) else c.db.riders().update(n) }.onFailure { c.log.w("DB", "jinete: ${it.message}") }
                        editing = null
                    }
                }) { Text("Guardar") }
            },
            dismissButton = { TextButton(onClick = { editing = null }) { Text("Cancelar") } },
        )
    }
    deleting?.let { r ->
        ConfirmDialog("Eliminar jinete", "¿Eliminar ${r.name} (${r.code}) de la app?", "Eliminar", danger = true,
            onConfirm = { scope.launch { c.db.riders().delete(r.id) } }, onDismiss = { deleting = null })
    }
}
