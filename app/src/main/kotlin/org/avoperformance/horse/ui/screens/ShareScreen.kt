package org.avoperformance.horse.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.avoperformance.horse.AppContainer
import org.avoperformance.horse.cloud.FirebaseShare
import org.avoperformance.horse.cloud.ShareManager
import org.avoperformance.horse.core.share.Contact
import org.avoperformance.horse.core.share.GrantState
import org.avoperformance.horse.core.share.InState
import org.avoperformance.horse.core.share.OutState
import org.avoperformance.horse.data.ShareOutEntity
import org.avoperformance.horse.ui.components.*
import org.avoperformance.horse.ui.theme.AvoColors

internal fun outLabel(s: String) = when (runCatching { OutState.valueOf(s) }.getOrNull()) {
    OutState.QUEUED -> "En cola"
    OutState.WAITING_ACCEPT -> "Esperando que acepte la invitación"
    OutState.UPLOADING -> "Enviando"
    OutState.NOTIFIED -> "Enviado · pendiente de recepción"
    OutState.RECEIVED -> "Recibido"
    OutState.BLOCKED -> "Rechazado por el destinatario"
    OutState.EXPIRED -> "Caducado sin recibir"
    OutState.FAILED -> "Error"
    null -> s
}
internal fun outColor(s: String) = when (runCatching { OutState.valueOf(s) }.getOrNull()) {
    OutState.RECEIVED -> AvoColors.Ok
    OutState.NOTIFIED, OutState.UPLOADING, OutState.QUEUED -> AvoColors.Blue
    OutState.WAITING_ACCEPT -> AvoColors.Warn
    else -> AvoColors.Bad
}
private fun grantLabel(g: GrantState?) = when (g) {
    GrantState.ACCEPTED -> "Aceptado" ; GrantState.PENDING -> "Invitación pendiente"
    GrantState.REJECTED -> "Rechazó la invitación"; GrantState.BLOCKED -> "Te ha bloqueado"; null -> "Sin invitar"
}
private fun grantColor(g: GrantState?) = when (g) { GrantState.ACCEPTED -> AvoColors.Ok; GrantState.PENDING, null -> AvoColors.Warn; else -> AvoColors.Bad }
private fun mb(b: Long) = "%.1f MB".format(b / 1_048_576.0)

/** COMPARTIR Y SINCRONIZAR: Firebase state, account, invitations, global/per-horse recipients, transfers and network. */
@Composable
fun ShareScreen(c: AppContainer) {
    val sm = c.share
    val me by c.identity.card.collectAsStateWithLifecycle()
    val connected by remember { sm.firebase.connected() }.collectAsStateWithLifecycle(false)
    val status by sm.status.collectAsStateWithLifecycle()
    val recipients by sm.recipients().collectAsStateWithLifecycle(emptyList())
    val outs by c.db.share().outFlow().collectAsStateWithLifecycle(emptyList())
    val ins by c.db.share().inFlow().collectAsStateWithLifecycle(emptyList())
    val horses by c.db.horses().all().collectAsStateWithLifecycle(emptyList())
    val trainings by c.db.trainings().all().collectAsStateWithLifecycle(emptyList())
    val scope = rememberCoroutineScope()
    var msg by remember { mutableStateOf<String?>(null) }
    var grants by remember { mutableStateOf<Map<String, GrantState?>>(emptyMap()) }
    var invitations by remember { mutableStateOf<List<FirebaseShare.Invitation>>(emptyList()) }
    var picking by remember { mutableStateOf<String?>(null) } // scope (GLOBAL or horse code)
    var refreshTick by remember { mutableIntStateOf(0) }
    var globalOn by remember { mutableStateOf(c.settings.shareGlobalEnabled) }
    var disabledHorses by remember { mutableStateOf(c.settings.shareHorsesDisabled) }
    var paused by remember { mutableStateOf(c.settings.sharePaused) }

    val card = me
    LaunchedEffect(card, refreshTick, recipients.size) {
        if (card == null) return@LaunchedEffect
        try {
            sm.firebase.signIn(card)
            grants = recipients.map { it.code }.distinct().associateWith { runCatching { sm.firebase.outgoingState(card.code, it) }.getOrNull() }
            invitations = sm.firebase.invitations(card.code)
        } catch (e: Exception) { msg = e.message }
    }

    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp)) {
        item {
            AvoCard("Estado Firebase", trailing = {
                when {
                    paused -> StatusPill("EN PAUSA", AvoColors.Warn)
                    status.running -> StatusPill("SINCRONIZANDO", AvoColors.Blue)
                    status.error != null -> StatusPill("ERROR", AvoColors.Bad)
                    connected -> StatusPill("CONECTADO", AvoColors.Ok)
                    else -> StatusPill("DESCONECTADO", AvoColors.Unknown)
                }
            }) {
                status.message?.let { Note(it) }
                status.error?.let { Note(it, AvoColors.Bad) }
                if (status.lastRunMs > 0) KV("Última sincronización", (Fmt.date(status.lastRunMs) ?: "—"))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(enabled = card != null, onClick = { sm.runNow(); refreshTick++ }) { Text("Sincronizar ahora") }
                    OutlinedButton(onClick = { paused = !paused; c.settings.sharePaused = paused; if (!paused) sm.runNow() }) { Text(if (paused) "Reanudar" else "Pausar") }
                }
                Note("Sin servidor propio: los avisos llegan mientras la app o su servicio están activos, y como respaldo cada 15 minutos o al abrir la app.")
            }
        }
        item {
            AvoCard("Mi cuenta") {
                if (card == null) Note("Registro e inicio de sesión: acerca tu tarjeta AVO personal (NFC) en la pantalla NFC. Si cambias de móvil, acerca la misma tarjeta.")
                else {
                    KV("Usuario", card.name); KV("Identificador", card.code)
                    KV("Cuenta", "Tarjeta NFC (sin correo)")
                    Note("Recuperación: la propia tarjeta. Si se pierde, crea otra en AVO Tarjetas y vuelve a invitar a tus destinatarios.")
                }
            }
        }
        if (card != null) {
            item {
                AvoCard("Invitaciones recibidas") {
                    if (invitations.isEmpty()) Note("Nadie te ha invitado. Cuando alguien quiera enviarte entrenamientos aparecerá aquí; hasta que aceptes no recibirás nada.")
                    invitations.forEach { inv ->
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(inv.senderName.ifBlank { inv.sender }, color = AvoColors.Text, fontWeight = FontWeight.SemiBold)
                                Text(inv.sender, color = AvoColors.TextDim, fontSize = 12.sp)
                            }
                            StatusPill(when (inv.state) { GrantState.ACCEPTED -> "ACEPTADO"; GrantState.PENDING -> "PENDIENTE"; GrantState.REJECTED -> "RECHAZADO"; GrantState.BLOCKED -> "BLOQUEADO" },
                                when (inv.state) { GrantState.ACCEPTED -> AvoColors.Ok; GrantState.PENDING -> AvoColors.Warn; else -> AvoColors.Bad })
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            fun act(f: suspend () -> Unit) = scope.launch { try { f(); invitations = sm.firebase.invitations(card.code) } catch (e: Exception) { msg = e.message } }
                            if (inv.state != GrantState.ACCEPTED) TextButton(onClick = { act { sm.firebase.respond(card.code, inv.sender, GrantState.ACCEPTED) } }) { Text("Aceptar", color = AvoColors.Ok) }
                            if (inv.state == GrantState.PENDING) TextButton(onClick = { act { sm.firebase.respond(card.code, inv.sender, GrantState.REJECTED) } }) { Text("Rechazar") }
                            if (inv.state != GrantState.BLOCKED) TextButton(onClick = { act { sm.firebase.respond(card.code, inv.sender, GrantState.BLOCKED) } }) { Text("Bloquear", color = AvoColors.Bad) }
                            TextButton(onClick = { act { sm.firebase.forgetSender(card.code, inv.sender) } }) { Text(if (inv.state == GrantState.BLOCKED) "Desbloquear" else "Eliminar") }
                        }
                        HorizontalDivider(color = AvoColors.Line)
                    }
                }
            }
            item {
                AvoCard("Sincronización global", trailing = {
                    Switch(globalOn, { globalOn = it; c.settings.shareGlobalEnabled = it })
                }) {
                    Note("Reciben automáticamente todos tus entrenamientos nuevos.")
                    RecipientList(recipients.filter { it.scope == ShareManager.GLOBAL }.map { Contact(it.code, it.name) }, grants,
                        onRemove = { sm.removeRecipient(ShareManager.GLOBAL, it.code) })
                    OutlinedButton(onClick = { picking = ShareManager.GLOBAL }) { Text("Añadir usuario") }
                }
            }
            item {
                AvoCard("Sincronización por caballo") {
                    Note("Se suman a los globales; un usuario repetido recibe una sola copia.")
                    if (horses.isEmpty()) Note("No hay caballos en la cuadra.")
                    horses.forEach { h ->
                        val on = h.code !in disabledHorses
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(h.name, color = AvoColors.Text, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                            Switch(on, { v -> disabledHorses = if (v) disabledHorses - h.code else disabledHorses + h.code; c.settings.shareHorsesDisabled = disabledHorses })
                        }
                        RecipientList(recipients.filter { it.scope == h.code }.map { Contact(it.code, it.name) }, grants,
                            onRemove = { sm.removeRecipient(h.code, it.code) })
                        TextButton(onClick = { picking = h.code }) { Text("Añadir destinatario a ${h.name}") }
                        HorizontalDivider(color = AvoColors.Line)
                    }
                }
            }
        }
        item {
            val counts = outs.groupingBy { it.state }.eachCount()
            AvoCard("Transferencias") {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    StatusPill("Pend. ${(counts["QUEUED"] ?: 0) + (counts["WAITING_ACCEPT"] ?: 0)}", AvoColors.Warn)
                    StatusPill("Env. ${(counts["UPLOADING"] ?: 0) + (counts["NOTIFIED"] ?: 0)}", AvoColors.Blue)
                    StatusPill("OK ${counts["RECEIVED"] ?: 0}", AvoColors.Ok)
                }
                Spacer(Modifier.height(6.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    StatusPill("Recibidas ${ins.count { it.state == InState.IMPORTED.name || it.state == InState.ALREADY_PRESENT.name }}", AvoColors.Ok)
                    StatusPill("Errores ${(counts["FAILED"] ?: 0) + (counts["EXPIRED"] ?: 0) + ins.count { it.state == InState.FAILED.name }}", AvoColors.Bad)
                }
                if ((counts["FAILED"] ?: 0) > 0) TextButton(onClick = { sm.retryFailed() }) { Text("Reintentar los que fallaron") }
            }
        }
        val confirm = ins.filter { it.state == InState.NEEDS_CONFIRMATION.name }
        if (confirm.isNotEmpty()) item {
            AvoCard("Requieren tu decisión") {
                confirm.forEach { r ->
                    Text("${r.sessionId} · de ${r.fromName}", color = AvoColors.Text, fontWeight = FontWeight.SemiBold)
                    Note(r.message ?: "Ya tienes una versión distinta")
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(onClick = { scope.launch { try { sm.resolveConfirmation(r.transferId, true); msg = "Sustituido" } catch (e: Exception) { msg = e.message } } }) { Text("Sustituir la mía") }
                        TextButton(onClick = { scope.launch { try { sm.resolveConfirmation(r.transferId, false); msg = "Se conserva la tuya" } catch (e: Exception) { msg = e.message } } }) { Text("Conservar la mía") }
                    }
                }
            }
        }
        item {
            AvoCard("Historial · enviados") {
                if (outs.isEmpty()) Note("Sin envíos.")
                outs.take(60).forEach { o ->
                    val t = trainings.firstOrNull { it.sessionId == o.sessionId }
                    val horse = horses.firstOrNull { it.code == (o.horseCode ?: t?.horseCode) }?.name ?: o.horseCode ?: "—"
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(if (horse == "—") o.sessionId else "$horse · ${t?.let { Fmt.date(it.startRtcMs) } ?: o.sessionId}", color = AvoColors.Text, fontWeight = FontWeight.SemiBold, maxLines = 1)
                            Text("→ ${o.recipientName} · ${when (o.origin) { "GLOBAL" -> "global"; "HORSE" -> "por caballo"; else -> "manual" }}", color = AvoColors.TextDim, fontSize = 12.sp)
                            o.receivedMs?.let { Text("Recibido ${(Fmt.date(it) ?: "—")}", color = AvoColors.Ok, fontSize = 12.sp) }
                            o.lastError?.let { Text(it, color = AvoColors.Bad, fontSize = 12.sp) }
                        }
                        StatusPill(outLabel(o.state).substringBefore(" ·").uppercase(), outColor(o.state))
                    }
                    HorizontalDivider(color = AvoColors.Line)
                }
            }
        }
        item {
            AvoCard("Historial · recibidos") {
                if (ins.isEmpty()) Note("Sin recepciones.")
                ins.take(60).forEach { r ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text("${r.horseName} · ${r.sessionId}", color = AvoColors.Text, fontWeight = FontWeight.SemiBold, maxLines = 1)
                            Text("de ${r.fromName} · ${(Fmt.date(r.receivedMs) ?: "—")} · ${mb(r.size)}", color = AvoColors.TextDim, fontSize = 12.sp)
                            r.message?.let { Text(it, color = AvoColors.TextDim, fontSize = 12.sp) }
                        }
                        val (txt, col) = when (r.state) {
                            InState.IMPORTED.name -> "IMPORTADO" to AvoColors.Ok
                            InState.ALREADY_PRESENT.name -> "YA ESTABA" to AvoColors.Ok
                            InState.NEEDS_CONFIRMATION.name -> "DECIDIR" to AvoColors.Warn
                            InState.DOWNLOADING.name -> "DESCARGANDO" to AvoColors.Blue
                            else -> "ERROR" to AvoColors.Bad
                        }
                        StatusPill(txt, col)
                    }
                    HorizontalDivider(color = AvoColors.Line)
                }
            }
        }
        item { NetworkCard(c) }
        msg?.let { item { AvoCard { Note(it) } } }
    }

    picking?.let { sc ->
        UserPicker(c, title = if (sc == ShareManager.GLOBAL) "Destinatario global" else "Destinatario de ${horses.firstOrNull { it.code == sc }?.name ?: sc}",
            multi = true, onDismiss = { picking = null }) { chosen ->
            picking = null
            val myCard = card ?: return@UserPicker
            chosen.forEach { sm.addRecipient(sc, it) }
            scope.launch {
                chosen.forEach { u -> runCatching { sm.firebase.invite(Contact(myCard.code, myCard.name), u.code) }.onFailure { msg = it.message } }
                refreshTick++
            }
        }
    }
}

@Composable
private fun RecipientList(list: List<Contact>, grants: Map<String, GrantState?>, onRemove: (Contact) -> Unit) {
    if (list.isEmpty()) Note("Sin destinatarios.")
    list.forEach { u ->
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(u.name, color = AvoColors.Text)
                Text("${u.code} · ${grantLabel(grants[u.code])}", color = grantColor(grants[u.code]), fontSize = 12.sp)
            }
            TextButton(onClick = { onRemove(u) }) { Text("Quitar", color = AvoColors.Bad) }
        }
    }
}

@Composable
private fun NetworkCard(c: AppContainer) {
    val s = c.settings
    var wifi by remember { mutableStateOf(s.shareAllowWifi) }
    var mobile by remember { mutableStateOf(s.shareAllowMobile) }
    var large by remember { mutableIntStateOf(s.shareWifiOnlyLargeMb) }
    var retry by remember { mutableStateOf(s.shareAutoRetry) }
    var maxMb by remember { mutableIntStateOf(s.shareMaxMb) }
    val (up, down) = s.shareUsage
    AvoCard("Red y consumo") {
        Row(verticalAlignment = Alignment.CenterVertically) { Text("Permitir WiFi", color = AvoColors.Text, modifier = Modifier.weight(1f)); Switch(wifi, { wifi = it; s.shareAllowWifi = it; c.share.schedule() }) }
        Row(verticalAlignment = Alignment.CenterVertically) { Text("Permitir datos móviles", color = AvoColors.Text, modifier = Modifier.weight(1f)); Switch(mobile, { mobile = it; s.shareAllowMobile = it; c.share.schedule() }) }
        Row(verticalAlignment = Alignment.CenterVertically) { Text("Reintentar automáticamente", color = AvoColors.Text, modifier = Modifier.weight(1f)); Switch(retry, { retry = it; s.shareAutoRetry = it }) }
        Text("Solo WiFi para archivos de más de ${if (large == 0) "— (desactivado)" else "$large MB"}", color = AvoColors.Text)
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            listOf(0, 2, 5, 10).forEach { v -> FilterChip(large == v, { large = v; s.shareWifiOnlyLargeMb = v }, label = { Text(if (v == 0) "No" else "$v MB") }) }
        }
        Text("Tamaño máximo por entrenamiento: $maxMb MB", color = AvoColors.Text)
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            listOf(10, 20, 30).forEach { v -> FilterChip(maxMb == v, { maxMb = v; s.shareMaxMb = v }, label = { Text("$v MB") }) }
        }
        KV("Este mes (este móvil)", "subido ${mb(up)} · descargado ${mb(down)}")
        if (up + down > s.shareMonthlyWarnMb * 1_048_576L) Note("Consumo alto este mes: el plan gratuito de Firebase permite 10 GB de descarga al mes para todo el proyecto.", AvoColors.Warn)
        Note("Plan gratuito Spark: 1 GB guardado y 10 GB/mes de descarga para todos los usuarios juntos. El contenido temporal se borra al confirmarse la recepción o a los 14 días.")
    }
}

/** User selection: search, favorites (automatic recipients) and multi-selection. */
@Composable
fun UserPicker(c: AppContainer, title: String, multi: Boolean, onDismiss: () -> Unit, onChosen: (List<Contact>) -> Unit) {
    val me by c.identity.card.collectAsStateWithLifecycle()
    val favorites by c.share.recipients().collectAsStateWithLifecycle(emptyList())
    var all by remember { mutableStateOf<List<Contact>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var q by remember { mutableStateOf("") }
    var chosen by remember { mutableStateOf<Set<String>>(emptySet()) }
    LaunchedEffect(me) {
        val card = me ?: run { error = "Primero acerca tu tarjeta AVO personal (NFC)"; return@LaunchedEffect }
        try { c.share.firebase.signIn(card); all = c.share.firebase.directory().filter { it.code != card.code } }
        catch (e: Exception) { error = e.message ?: "Sin conexión" }
    }
    val favCodes = favorites.map { it.code }.toSet()
    AlertDialog(onDismissRequest = onDismiss, title = { Text(title) },
        text = {
            Column(Modifier.heightIn(max = 460.dp).verticalScroll(rememberScrollState())) {
                error?.let { Note(it, AvoColors.Bad) }
                OutlinedTextField(q, { q = it }, label = { Text("Buscar por nombre o código") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                val list = all
                if (list == null && error == null) { Spacer(Modifier.height(8.dp)); LinearProgressIndicator(Modifier.fillMaxWidth()) }
                val filtered = list.orEmpty().filter { q.isBlank() || it.name.contains(q, true) || it.code.contains(q.trim(), true) }
                    .sortedWith(compareByDescending<Contact> { it.code in favCodes }.thenBy { it.name.lowercase() })
                if (list != null && filtered.isEmpty()) Note("Sin resultados. Cada persona aparece cuando acerca su tarjeta AVO en su móvil.")
                filtered.forEach { u ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(u.code in chosen, { on -> chosen = if (on) (if (multi) chosen + u.code else setOf(u.code)) else chosen - u.code })
                        Column(Modifier.weight(1f)) {
                            Text((if (u.code in favCodes) "★ " else "") + u.name, color = AvoColors.Text)
                            Text(u.code, color = AvoColors.TextDim, fontSize = 12.sp)
                        }
                    }
                }
            }
        },
        confirmButton = { Button(enabled = chosen.isNotEmpty(), onClick = { onChosen(all.orEmpty().filter { it.code in chosen }) }) { Text("Confirmar") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancelar") } })
}

/** COMPARTIR: choose recipients, send and follow progress/reception of a training. */
@Composable
fun ShareDialog(c: AppContainer, sessionId: String, onDismiss: () -> Unit) {
    val me by c.identity.card.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    var sentTo by remember { mutableStateOf<Set<String>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    val jobs by c.db.share().outFor(sessionId).collectAsStateWithLifecycle(emptyList())
    val status by c.share.status.collectAsStateWithLifecycle()
    val training by c.db.trainings().observe(sessionId).collectAsStateWithLifecycle(null)
    val horses by c.db.horses().all().collectAsStateWithLifecycle(emptyList())
    val riders by c.db.riders().all().collectAsStateWithLifecycle(emptyList())
    val tr = training
    var namesSkipped by remember { mutableStateOf(false) }
    if (sentTo == null && tr != null && !namesSkipped &&
        (horses.none { it.code == tr.horseCode } || riders.none { it.code == tr.riderCode })) {
        // without horse and rider the training cannot be packaged: ask for them first
        AssignHorseRiderDialog(c, tr, onDismiss = onDismiss, onDone = { namesSkipped = true })
        return
    }
    if (sentTo == null) {
        UserPicker(c, "Compartir entrenamiento", multi = true, onDismiss = onDismiss) { chosen ->
            val card = me ?: return@UserPicker
            sentTo = chosen.map { it.code }.toSet()
            scope.launch {
                try {
                    chosen.forEach { u -> c.share.firebase.invite(Contact(card.code, card.name), u.code) }
                    c.share.shareManually(sessionId, chosen)
                } catch (e: Exception) { error = e.message }
            }
        }
        return
    }
    AlertDialog(onDismissRequest = onDismiss, title = { Text("Envío") },
        text = {
            Column {
                error?.let { Note(it, AvoColors.Bad) }
                if (status.running) LinearProgressIndicator(Modifier.fillMaxWidth())
                jobs.filter { it.recipient in sentTo.orEmpty() }.forEach { j: ShareOutEntity ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(j.recipientName, color = AvoColors.Text, modifier = Modifier.weight(1f))
                        StatusPill(outLabel(j.state).substringBefore(" ·"), outColor(j.state))
                    }
                    j.lastError?.let { Note(it, AvoColors.Bad) }
                }
                Note("Puedes cerrar: el envío continúa en segundo plano y verás aquí y en «Compartir y sincronizar» cuando lo reciban.")
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Cerrar") } })
}

/** Small sharing-state indicator of a training (analysis screen). */
@Composable
fun ShareStatusLine(c: AppContainer, sessionId: String) {
    val jobs by c.db.share().outFor(sessionId).collectAsStateWithLifecycle(emptyList())
    if (jobs.isEmpty()) { Note("Sin compartir"); return }
    val received = jobs.count { it.state == OutState.RECEIVED.name }
    val pending = jobs.count { !runCatching { OutState.valueOf(it.state).terminal }.getOrDefault(true) }
    val failed = jobs.size - received - pending
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        if (received > 0) StatusPill("Recibido por $received", AvoColors.Ok)
        if (pending > 0) StatusPill("Pendiente $pending", AvoColors.Blue)
        if (failed > 0) StatusPill("Sin entregar $failed", AvoColors.Bad)
    }
}
