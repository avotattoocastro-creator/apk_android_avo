package org.avoperformance.horse.ui.screens

import androidx.compose.foundation.layout.Arrangement
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import org.avoperformance.horse.ui.components.Fmt
import org.avoperformance.horse.ui.components.MetricTile
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

/** Copies the picked image into app storage, scaled to ≤ 720 px so it never fills the RAM. */
suspend fun saveHorsePhoto(ctx: Context, horseId: Long, uri: Uri): String = withContext(Dispatchers.IO) {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    ctx.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
    var sample = 1
    while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= 720) sample *= 2
    val bmp = ctx.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample }) }
        ?: error("No se pudo leer la imagen")
    val dir = File(ctx.filesDir, "horses").apply { mkdirs() }
    val file = File(dir, "horse_${horseId}_${System.currentTimeMillis()}.jpg")
    file.outputStream().use { bmp.compress(Bitmap.CompressFormat.JPEG, 88, it) }
    dir.listFiles()?.filter { it.name.startsWith("horse_${horseId}_") && it != file }?.forEach { it.delete() }
    file.absolutePath
}

@Composable
fun HorsePhoto(path: String?, modifier: Modifier = Modifier) {
    val img = remember(path) { path?.let { runCatching { BitmapFactory.decodeFile(it)?.asImageBitmap() }.getOrNull() } }
    val shape = RoundedCornerShape(14.dp)
    Box(modifier.clip(shape).background(AvoColors.Surface2).border(1.dp, AvoColors.RedDark, shape), contentAlignment = Alignment.Center) {
        if (img != null) Image(img, "Foto del caballo", Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        else Text("🐎", fontSize = 30.sp)
    }
}

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
    val trainings by c.db.trainings().all().collectAsStateWithLifecycle(emptyList())
    var photoFor by remember { mutableStateOf<HorseEntity?>(null) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        val h = photoFor ?: return@rememberLauncherForActivityResult
        photoFor = null
        if (uri != null) scope.launch {
            runCatching { saveHorsePhoto(c.app, h.id, uri) }
                .onSuccess { c.db.horses().update(h.copy(photoPath = it)) }
                .onFailure { c.log.w("DB", "foto: ${it.message}") }
        }
    }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = androidx.compose.foundation.layout.PaddingValues(vertical = 6.dp)) {
        item {
            Row(Modifier.fillMaxWidth().padding(12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = { editing = HorseEntity(code = "", name = "") }) { Text("Nuevo caballo") }
                OutlinedButton(onClick = { go("jinetes") }) { Text("Jinetes") }
            }
        }
        items(horses, key = { it.id }) { h ->
            val mine = trainings.filter { it.horseCode == h.code }
            AvoCard(onClick = { selected = h.id; c.settings.selectedHorseId = h.id }) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    HorsePhoto(h.photoPath, Modifier.size(78.dp).clickable { photoFor = h; picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) })
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(h.name.uppercase(), color = AvoColors.Text, fontSize = 19.sp, fontWeight = FontWeight.Black)
                        Text(listOf(h.code, h.breed, h.birthYear?.toString().orEmpty()).filter { it.isNotBlank() }.joinToString(" · "), color = AvoColors.TextDim, fontSize = 13.sp)
                        if (selected == h.id) { Spacer(Modifier.height(4.dp)); StatusPill("Seleccionado", AvoColors.Red) }
                    }
                }
                Spacer(Modifier.height(10.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    MetricTile("Sesiones", mine.size.toString(), "", Modifier.weight(1f))
                    MetricTile("Distancia", mine.sumOf { it.distanceM ?: 0.0 }.takeIf { it > 0 }?.let { Fmt.m(it / 1000.0, 1) }, "km", Modifier.weight(1f))
                    MetricTile("V. máx", mine.mapNotNull { it.maxSpeedMs }.maxOrNull()?.let { Fmt.kmh(it) }, "km/h", Modifier.weight(1f), AvoColors.Red)
                }
                if (h.notes.isNotBlank()) Note(h.notes)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TextButton(onClick = { editing = h }) { Text("Editar") }
                    TextButton(onClick = { photoFor = h; picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }) { Text(if (h.photoPath == null) "Añadir foto" else "Cambiar foto") }
                    TextButton(onClick = { deleting = h }) { Text("Eliminar", color = AvoColors.Bad) }
                }
            }
        }
        if (horses.isEmpty()) item { Note("Sin caballos") }
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
        if (riders.isEmpty()) item { Note("Sin jinetes") }
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
