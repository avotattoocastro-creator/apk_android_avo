package org.avoperformance.horse.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import org.avoperformance.horse.AppContainer
import org.avoperformance.horse.data.TrainingEntity
import org.avoperformance.horse.ui.components.*
import org.avoperformance.horse.ui.theme.AvoColors

/** Horse profile: data, totals and its trainings from newest to oldest. */
@Composable
fun HorseProfileScreen(c: AppContainer, code: String, go: (String) -> Unit) {
    val horses by c.db.horses().all().collectAsStateWithLifecycle(emptyList())
    val riders by c.db.riders().all().collectAsStateWithLifecycle(emptyList())
    val trainings by c.db.trainings().all().collectAsStateWithLifecycle(emptyList())
    val h = horses.firstOrNull { it.code == code } ?: run { Note("Caballo no encontrado"); return }
    var selected by remember { mutableLongStateOf(c.settings.selectedHorseId) }
    val mine = trainings.filter { it.horseCode == h.code }.sortedByDescending { it.startRtcMs }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 16.dp)) {
        item {
            AvoCard {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    HorsePhoto(h.photoPath, Modifier.size(84.dp))
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(h.name.uppercase(), color = AvoColors.Text, fontSize = 21.sp, fontWeight = FontWeight.Black)
                        Text(listOf(h.code, h.breed, h.birthYear?.toString().orEmpty()).filter { it.isNotBlank() }.joinToString(" · "), color = AvoColors.TextDim, fontSize = 13.sp)
                        Spacer(Modifier.height(4.dp))
                        if (selected == h.id) StatusPill("Seleccionado", AvoColors.Red)
                        else TextButton(onClick = { selected = h.id; c.settings.selectedHorseId = h.id }) { Text("Seleccionar") }
                    }
                }
                if (h.notes.isNotBlank()) Text(h.notes, color = AvoColors.TextDim, fontSize = 13.sp)
                Spacer(Modifier.height(10.dp))
                Totals(mine)
            }
        }
        item { SectionTitle("Entrenamientos (${mine.size})") }
        if (mine.isEmpty()) item { AvoCard { Note("Sin entrenamientos") } }
        items(mine, key = { it.sessionId }) { t ->
            ProfileTrainingRow(t, subtitle = riders.firstOrNull { it.code == t.riderCode }?.name ?: "Sin jinete") { go("detalle/${t.sessionId}") }
        }
    }
}

/** Rider profile: data, totals and their trainings from newest to oldest. */
@Composable
fun RiderProfileScreen(c: AppContainer, code: String, go: (String) -> Unit) {
    val horses by c.db.horses().all().collectAsStateWithLifecycle(emptyList())
    val riders by c.db.riders().all().collectAsStateWithLifecycle(emptyList())
    val trainings by c.db.trainings().all().collectAsStateWithLifecycle(emptyList())
    val r = riders.firstOrNull { it.code == code } ?: run { Note("Jinete no encontrado"); return }
    var selected by remember { mutableLongStateOf(c.settings.selectedRiderId) }
    val mine = trainings.filter { it.riderCode == r.code }.sortedByDescending { it.startRtcMs }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 16.dp)) {
        item {
            AvoCard {
                Text(r.name.uppercase(), color = AvoColors.Text, fontSize = 21.sp, fontWeight = FontWeight.Black)
                Text(r.code, color = AvoColors.TextDim, fontSize = 13.sp)
                if (selected == r.id) StatusPill("Seleccionado", AvoColors.Red)
                else TextButton(onClick = { selected = r.id; c.settings.selectedRiderId = r.id }) { Text("Seleccionar") }
                if (r.notes.isNotBlank()) Text(r.notes, color = AvoColors.TextDim, fontSize = 13.sp)
                Spacer(Modifier.height(10.dp))
                Totals(mine)
            }
        }
        item { SectionTitle("Entrenamientos (${mine.size})") }
        if (mine.isEmpty()) item { AvoCard { Note("Sin entrenamientos") } }
        items(mine, key = { it.sessionId }) { t ->
            ProfileTrainingRow(t, subtitle = horses.firstOrNull { it.code == t.horseCode }?.name ?: "Sin caballo") { go("detalle/${t.sessionId}") }
        }
    }
}

@Composable
private fun Totals(list: List<TrainingEntity>) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        MetricTile("Sesiones", list.size.toString(), "", Modifier.weight(1f))
        MetricTile("Distancia", list.sumOf { it.distanceM ?: 0.0 }.takeIf { it > 0 }?.let { Fmt.m(it / 1000.0, 1) }, "km", Modifier.weight(1f))
        MetricTile("V. máx", list.mapNotNull { it.maxSpeedMs }.maxOrNull()?.let { Fmt.kmh(it) }, "km/h", Modifier.weight(1f), AvoColors.Red)
    }
}

@Composable
private fun SectionTitle(t: String) = Text(t.uppercase(), color = AvoColors.Red, fontSize = 12.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.2.sp,
    modifier = Modifier.padding(start = 18.dp, top = 12.dp, bottom = 2.dp))

@Composable
private fun ProfileTrainingRow(t: TrainingEntity, subtitle: String, onOpen: () -> Unit) {
    AvoCard(onClick = onOpen, trailing = { Text("›", color = AvoColors.TextDim, fontSize = 20.sp) }) {
        Text(Fmt.date(t.startRtcMs) ?: t.sessionId, color = AvoColors.Text, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
        Text("$subtitle · ${t.sessionId}", color = AvoColors.TextDim, fontSize = 12.sp)
        Spacer(Modifier.height(6.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            MetricTile("Tiempo", Fmt.duration(t.activeMs), "", Modifier.weight(1f))
            MetricTile("Distancia", t.distanceM?.let { Fmt.m(it / 1000.0, 2) }, "km", Modifier.weight(1f))
            MetricTile("V. máx", t.maxSpeedMs?.let { Fmt.kmh(it) }, "km/h", Modifier.weight(1f), AvoColors.Red)
        }
        if (t.localDir == null) Text("Solo en el reloj", color = AvoColors.TextDim, fontSize = 12.sp)
    }
}
