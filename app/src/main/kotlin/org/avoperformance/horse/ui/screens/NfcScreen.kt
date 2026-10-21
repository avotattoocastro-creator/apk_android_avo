package org.avoperformance.horse.ui.screens

import android.app.Activity
import android.nfc.NfcAdapter
import android.os.SystemClock
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
    val watchStatus by c.watch.status.collectAsStateWithLifecycle(null)
    val currentRecording by rememberUpdatedState(watchStatus?.session == org.avoperformance.horse.core.ble.WatchSessionState.RECORDING || watchStatus?.session == org.avoperformance.horse.core.ble.WatchSessionState.PAUSED || watchStatus?.rec == org.avoperformance.horse.core.ble.RecStatus.RECORDING)
    var kind by remember { mutableStateOf("horse") }
    var code by remember { mutableStateOf("") }
    var writeMode by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf("Acerca una etiqueta NFC compatible.") }
    val currentKind by rememberUpdatedState(kind)
    val currentCode by rememberUpdatedState(code)
    val currentWrite by rememberUpdatedState(writeMode)
    val lastScan = remember { java.util.concurrent.atomic.AtomicLong(0L) }
    var pendingSync by remember { mutableStateOf(false) }
    DisposableEffect(adapter, activity, horses, riders) {
        val callback = NfcAdapter.ReaderCallback { tag ->
            val now = SystemClock.elapsedRealtime()
            val previous = lastScan.get()
            if (now - previous >= 1500L && lastScan.compareAndSet(previous, now)) try {
                val result = if (currentWrite) {
                    val value = currentCode
                    require(value.isNotBlank()) { "Selecciona una ficha antes de grabar" }
                    val uri = if (currentKind == "horse") org.avoperformance.horse.core.nfc.AvoNfc.horse(horses.first { it.code == value }) else org.avoperformance.horse.core.nfc.AvoNfc.rider(riders.first { it.code == value })
                    val record = NdefRecord.createUri(uri)
                    val data = NdefMessage(arrayOf(record))
                    val ndef = Ndef.get(tag)
                    var verified = false
                    if (ndef != null) {
                        ndef.connect()
                        try {
                            require(ndef.isWritable) { "Etiqueta protegida contra escritura" }
                            require(ndef.maxSize >= data.toByteArray().size) { "Etiqueta sin capacidad suficiente" }
                            ndef.writeNdefMessage(data)
                            verified = ndef.ndefMessage?.records?.any { it.toUri() == uri } == true
                        } finally { ndef.close() }
                    } else {
                        val format = NdefFormatable.get(tag) ?: error("Etiqueta no compatible con NDEF")
                        format.connect()
                        try { format.format(data) } finally { format.close() }
                        // Android may retain the pre-format Tag technologies until it is removed
                        // from the field. A newly formatted NDEF tag often requires a fresh scan.
                        val verify = Ndef.get(tag)
                        if (verify != null) {
                            verified = runCatching {
                                verify.connect()
                                try { verify.ndefMessage?.records?.any { it.toUri() == uri } == true }
                                finally { verify.close() }
                            }.getOrDefault(false)
                        }
                    }
                    if (verified) "Etiqueta grabada y verificada: ${currentKind} · $value"
                    else "Escritura NFC completada: retira la tarjeta, pulsa Leer y vuelve a acercarla para verificar."
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
                    require(!currentRecording) { "No se puede cambiar caballo o jinete durante una sesión activa" }
                    activity?.runOnUiThread { message = "Etiqueta leída: $identity. Sincronizando…" }
                    scope.launch {
                        pendingSync = true
                        try {
                        val horseId = if (type == "horse") h?.id ?: withContext(Dispatchers.IO) { org.avoperformance.horse.core.nfc.AvoNfc.import(uri, c.db) } else c.settings.selectedHorseId
                        val riderId = if (type == "rider") r?.id ?: withContext(Dispatchers.IO) { org.avoperformance.horse.core.nfc.AvoNfc.import(uri, c.db) } else c.settings.selectedRiderId
                        val horse = withContext(Dispatchers.IO) { c.db.horses().byId(horseId) }
                        val rider = withContext(Dispatchers.IO) { c.db.riders().byId(riderId) }
                        if (type == "horse") c.settings.selectedHorseId = horseId
                        if (type == "rider") c.settings.selectedRiderId = riderId
                        message = if (horse != null && rider != null) {
                            val err = withContext(Dispatchers.IO) { c.config.setIdentity(horse.id, horse.code, rider.id, rider.code) }
                            if (err == null) "Identidad enviada al chaleco: ${horse.name} / ${rider.name}" else "Identidad guardada en móvil; no enviada: $err"
                        } else "Identidad seleccionada en móvil; falta seleccionar caballo o jinete."
                        } catch (e: Exception) {
                            message = "Identidad seleccionada en móvil; error de sincronización: ${e.message ?: "BLE no disponible"}"
                        } finally { pendingSync = false }
                    }
                    "Etiqueta leída: $identity"
                }
                activity?.runOnUiThread { if (currentWrite) message = result }
            } catch (e: Exception) {
                activity?.runOnUiThread { message = "NFC: ${e.message ?: "error de lectura"}" }
            }
        }
        if (activity != null && adapter?.isEnabled == true) {
            adapter.enableReaderMode(activity, callback, NfcAdapter.FLAG_READER_NFC_A or NfcAdapter.FLAG_READER_NFC_B, null)
        }
        onDispose {
            if (activity != null) runCatching { adapter?.disableReaderMode(activity) }
            (activity as? org.avoperformance.horse.MainActivity)?.enableGlobalNfc()
        }
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
            } else Note("Mantén esta pantalla abierta y acerca una tarjeta AVO. Se seleccionará su ficha y se enviará al reloj si está conectado.")
            Text(message)
            if (pendingSync) LinearProgressIndicator(Modifier.fillMaxWidth())
            Note("La lectura de identidad funciona en cualquier pantalla de AVO mientras la app esté abierta. Esta pantalla se utiliza para grabar tarjetas y ver los detalles. Android no garantiza lectura con el móvil bloqueado. No se cambia identidad durante una sesión activa.")
        } }
    }
}
