package org.avoperformance.horse.ui.screens

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedButton
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.launch
import androidx.compose.material3.Checkbox
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import org.avoperformance.horse.core.ble.ChestOtaProtocol
import java.security.MessageDigest
import android.provider.OpenableColumns
import android.net.Uri
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.ui.Modifier
import org.avoperformance.horse.AppContainer
import org.avoperformance.horse.ui.components.AvoCard
import org.avoperformance.horse.ui.components.KV
import org.avoperformance.horse.ui.components.Note
import org.avoperformance.horse.ui.theme.AvoColors

/** Capability-driven, read-only device inventory. OTA is deliberately not enabled until
 *  firmware supports authenticated images, rollback, and chunked transport end to end. */
@Composable
fun DeviceManagerScreen(c: AppContainer) {
    val scope = rememberCoroutineScope()
    val ota by c.chestOta.state.collectAsStateWithLifecycle()
    var selectedImage by remember { mutableStateOf<ByteArray?>(null) }
    var userAccepts by remember { mutableStateOf(false) }
    var inspectedName by remember { mutableStateOf("Ningún firmware seleccionado") }
    var inspection by remember { mutableStateOf<ChestOtaProtocol.Inspection?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var authDiagnostic by remember { mutableStateOf("Pendiente") }
    fun displayName(uri: Uri): String? = runCatching {
        c.app.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (column >= 0 && cursor.moveToFirst()) cursor.getString(column) else null
        }
    }.getOrNull()
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            runCatching {
                val bytes = c.app.contentResolver.openInputStream(uri)?.use { input ->
                    val out = java.io.ByteArrayOutputStream()
                    val buf = ByteArray(8192)
                    while (true) {
                        val n = input.read(buf)
                        if (n < 0) break
                        if (out.size() + n > ChestOtaProtocol.MAX_FILE_SIZE) error("Archivo demasiado grande")
                        out.write(buf, 0, n)
                    }
                    out.toByteArray()
                } ?: error("No se puede leer el archivo")
                val resolvedName = displayName(uri) ?: "firmware seleccionado"
                inspectedName = resolvedName
                if (resolvedName != "firmware seleccionado") {
                    require(resolvedName.endsWith(".zip", ignoreCase = true)) { "Selecciona el paquete OTA firmado .zip: $resolvedName" }
                }
                val verified = c.chestOta.inspectSignedPackage(bytes)
                val result = ChestOtaProtocol.inspect(verified.firmware)
                selectedImage = bytes
                userAccepts = false
                inspection = result
                error = null
            }.onFailure { error = it.message; inspection = null; selectedImage = null }
        }
    }
    val link by c.watch.state.collectAsStateWithLifecycle()
    val info by c.watch.info.collectAsStateWithLifecycle()
    val sample by c.watch.telemetry.collectAsStateWithLifecycle()
    val now = rememberNow()
    val age = sample?.let { (now - it.receivedMs).coerceAtLeast(0L) }
    val fresh = age != null && age <= 5000L
    val t = sample?.t?.takeIf { fresh }
    LazyColumn(Modifier.fillMaxSize()) {
        item {
            AvoCard("Dispositivos · estado real") {
                KV("Enlace Android ↔ pecho", link.texto)
                KV("Identificador BLE", c.watch.authorizedAddress ?: "No vinculado")
                KV("Firmware pecho", info?.firmware ?: "No comunicado")
                KV("Última telemetría", age?.let { "hace ${it} ms" } ?: "Sin datos")
                KV("Pecho ↔ espalda", t?.let { if (it.backLink) "Conectado" else "Sin enlace" } ?: "No verificado")
                KV("Espalda ↔ cincha", t?.let { if (it.girth) "Conectada" else "Sin datos" } ?: "No verificado")
                KV("Firmware espalda", "No comunicado")
                KV("Firmware cincha", "No comunicado")
                Note("El estado de espalda y cincha procede de la telemetría del pecho, no de conexiones directas al móvil.")
            }
        }
        item {
            AvoCard("Actualización de firmware · PECHO") {
                KV("Dispositivo", info?.deviceId ?: "Sin conectar")
                KV("Versión actual", info?.firmware ?: "Sin comunicar")
                KV("OTA anunciada", if (info?.supportsOta == true) "Sí" else "No verificada")
                KV("Archivo", inspectedName)
                KV("Tamaño", inspection?.let { "${it.size} bytes" } ?: "—")
                KV("Validación de estructura", inspection?.reason ?: "Pendiente de selección")
                KV("SHA-256", inspection?.sha256?.joinToString("") { "%02x".format(it.toInt() and 255) } ?: "—")
                OutlinedButton(onClick = { picker.launch(arrayOf("application/octet-stream", "*/*")) }) { Text("Seleccionar paquete OTA firmado .zip") }
                error?.let { Note("Error al leer archivo: $it") }
                KV("Imagen autorizada", if (selectedImage?.let { c.chestOta.isApproved(it) } == true) "Firma ES256 válida (solo comprobación Android)" else "No compatible")
                KV("Estado OTA", ota.phase)
                if (ota.total > 0) KV("Progreso confirmado", "${ota.confirmed} / ${ota.total} bytes (${(ota.confirmed.toLong() * 100 / ota.total)} %)")
                ota.error?.let { Note("OTA: $it") }
                ota.versionBefore?.let { KV("Versión antes de OTA", it) }
                ota.versionAfter?.let { KV("Versión observada tras OTA", it) }
                if (ota.events.isNotEmpty()) {
                    Text("Diagnóstico OTA (confirmaciones y reinicio)")
                    ota.events.forEach { Note(it) }
                }
                Text("OTA firmada ES256: el reloj debe autorizar el manifiesto antes de recibir firmware. La instalación sigue bloqueada hasta completar las pruebas de seguridad.", color = AvoColors.Warn)
                KV("Diagnóstico de firma inválida", authDiagnostic)
                OutlinedButton(enabled = c.watch.isReady && info?.firmware == "3.5.7", onClick = {
                    scope.launch {
                        authDiagnostic = "Comprobando rechazo..."
                        authDiagnostic = runCatching { c.chestOta.probeInvalidAuthorization() }
                            .getOrElse { "Error de diagnóstico: ${it.message}" }
                    }
                }) { Text("Probar rechazo OTA_AUTH (sin instalar)") }
                Row(horizontalArrangement = Arrangement.Start) {
                    Checkbox(checked = userAccepts, onCheckedChange = { userAccepts = it })
                    Text("Acepto el riesgo y confirmo que no hay entrenamientos activos")
                }
                Button(enabled = c.chestOta.safeInstallationAvailable && selectedImage?.let { c.chestOta.isApproved(it) } == true && userAccepts && c.watch.isReady && ota.phase !in listOf("Preparando", "Transfiriendo", "Verificando en el pecho"), onClick = {
                    val firmware = selectedImage ?: return@Button
                    scope.launch { runCatching { c.chestOta.transfer(firmware) }.onFailure { error = it.message } }
                }) { Text("Instalar OTA firmada (pendiente validación)") }
                OutlinedButton(onClick = { c.chestOta.cancel() }) { Text("Solicitar cancelación") }
                KV("OTA espalda", "No compatible todavía")
                Note("No borra ni formatea la microSD. La versión posterior y la conservación de sesiones requieren comprobación física. Detén NTRIP antes de actualizar.")
            }
        }
        item {
            AvoCard("Arquitectura") {
                KV("Actual", "Android ↔ pecho BLE; pecho ↔ espalda ESP-NOW; espalda ↔ cincha ESP-NOW")
                KV("Futura V4", "Módulo único con capacidades anunciadas por firmware")
                Note("La futura arquitectura no debe habilitar funciones hasta que los dispositivos comuniquen sus capacidades reales.")
            }
        }
    }
}
