package org.avoperformance.horse.ui.screens

import android.app.Activity
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.NdefMessage
import android.nfc.NdefRecord
import android.nfc.tech.Ndef
import android.nfc.tech.NdefFormatable
import android.net.Uri
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.avoperformance.horse.AppContainer
import org.avoperformance.horse.ui.components.AvoCard
import org.avoperformance.horse.ui.components.Note

/** NFC reader mode is intentionally foreground-only. Android does not promise reads with screen off. */
@Composable
fun NfcScreen(c: AppContainer) {
    val context = LocalContext.current
    val activity = context as? Activity
    val adapter = remember { NfcAdapter.getDefaultAdapter(context) }
    val horses by c.db.horses().all().collectAsStateWithLifecycle(emptyList())
    val riders by c.db.riders().all().collectAsStateWithLifecycle(emptyList())
    val scope = rememberCoroutineScope()
    var kind by remember { mutableStateOf("horse") }
    var code by remember { mutableStateOf("") }
    var writeMode by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf("Acerca una etiqueta NFC compatible.") }
    val currentKind by rememberUpdatedState(kind)
    val currentCode by rememberUpdatedState(code)
    val currentWrite by rememberUpdatedState(writeMode)
    DisposableEffect(adapter, activity) {
        val callback = NfcAdapter.ReaderCallback { tag ->
            try {
                val result = if (currentWrite) {
                    val value = currentCode
                    require(value.isNotBlank()) { "Selecciona una ficha antes de grabar" }
                    val uri = Uri.parse("avohorse://identity/${currentKind}/${Uri.encode(value)}")
                    val record = NdefRecord.createUri(uri)
                    val data = NdefMessage(arrayOf(record))
                    val ndef = Ndef.get(tag)
                    if (ndef != null) {
                        ndef.connect()
                        try {
                            require(ndef.isWritable) { "Etiqueta protegida contra escritura" }
                            require(ndef.maxSize >= data.toByteArray().size) { "Etiqueta sin capacidad suficiente" }
                            ndef.writeNdefMessage(data)
                            require(ndef.ndefMessage.records.any { it.toUri() == uri }) { "No se pudo verificar la escritura" }
                        } finally { ndef.close() }
                    } else {
                        val format = NdefFormatable.get(tag) ?: error("Etiqueta no compatible con NDEF")
                        format.connect()
                        try { format.format(data) } finally { format.close() }
                    }
                    "Etiqueta grabada: ${currentKind} · $value"
                } else {
                    val ndef = Ndef.get(tag) ?: error("Etiqueta sin contenido NDEF")
                    ndef.connect()
                    val uri = try { ndef.ndefMessage?.records?.firstNotNullOfOrNull { it.toUri() } } finally { ndef.close() }
                    require(uri?.scheme == "avohorse" && uri.host == "identity") { "No es una etiqueta AVO" }
                    val type = uri.pathSegments.getOrNull(0)
                    val identity = uri.pathSegments.getOrNull(1)
                    require(type in listOf("horse", "rider") && !identity.isNullOrBlank()) { "Identidad NFC inválida" }
                    val h = if (type == "horse") horses.firstOrNull { it.code == identity } else null
                    val r = if (type == "rider") riders.firstOrNull { it.code == identity } else null
                    require(h != null || r != null) { "Ficha no encontrada en este móvil: $identity" }
                    scope.launch {
                        val horseId = h?.id ?: c.settings.selectedHorseId
                        val riderId = r?.id ?: c.settings.selectedRiderId
                        val horse = withContext(Dispatchers.IO) { c.db.horses().byId(horseId) }
                        val rider = withContext(Dispatchers.IO) { c.db.riders().byId(riderId) }
                        if (h != null) c.settings.selectedHorseId = h.id
                        if (r != null) c.settings.selectedRiderId = r.id
                        message = if (horse != null && rider != null) {
                            val err = withContext(Dispatchers.IO) { c.config.setIdentity(horse.id, horse.code, rider.id, rider.code) }
                            if (err == null) "Identidad enviada al chaleco: ${horse.name} / ${rider.name}" else "Identidad guardada en móvil; no enviada: $err"
                        } else "Identidad seleccionada en móvil; falta seleccionar caballo o jinete."
                    }
                    "Etiqueta leída: $identity"
                }
                activity?.runOnUiThread { if (currentWrite) message = result }
            } catch (e: Exception) {
                activity?.runOnUiThread { message = "NFC: ${e.message ?: "error de lectura"}" }
            }
        }
        if (activity != null && adapter?.isEnabled == true) {
            adapter.enableReaderMode(activity, callback, NfcAdapter.FLAG_READER_NFC_A or NfcAdapter.FLAG_READER_NFC_B or NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK.inv().and(0), null)
        }
        onDispose { if (activity != null) runCatching { adapter?.disableReaderMode(activity) } }
    }
    LazyColumn(Modifier.fillMaxSize().padding(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item { AvoCard("NFC · Caballos y jinetes") {
            Note(if (adapter == null) "Este móvil no tiene NFC." else if (!adapter.isEnabled) "Activa NFC en los ajustes de Android." else "Lector NFC disponible.")
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = { writeMode = false }) { Text("Leer") }
                OutlinedButton(onClick = { writeMode = true }) { Text("Grabar") }
            }
            if (writeMode) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = { kind = "horse"; code = "" }) { Text("Caballo") }
                    OutlinedButton(onClick = { kind = "rider"; code = "" }) { Text("Jinete") }
                }
                (if (kind == "horse") horses.map { it.code to it.name } else riders.map { it.code to it.name }).forEach { (id, name) ->
                    OutlinedButton(onClick = { code = id }) { Text(if (code == id) "✓ $name" else name) }
                }
                Note("Seleccionado: ${code.ifBlank { "ninguno" }}. Acerca la tarjeta para grabar y verificar.")
            } else Note("Acerca una tarjeta AVO para seleccionar su ficha y enviarla al reloj si está conectado.")
            Text(message)
            Note("La lectura con la pantalla apagada no está garantizada. Durante una grabación activa, evita cambiar la identidad.")
        } }
    }
}
