package org.avoperformance.horse.ui.screens

import android.os.Build
import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import org.avoperformance.horse.data.SettingsBackup
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.Dispatchers
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.TextButton
import androidx.compose.material3.LinearProgressIndicator
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.avoperformance.horse.AppContainer
import org.avoperformance.horse.Perms
import org.avoperformance.horse.ble.LinkState
import org.avoperformance.horse.core.ble.BlackboxRecord
import org.avoperformance.horse.core.ntrip.NtripClient
import org.avoperformance.horse.core.ntrip.NtripState
import org.avoperformance.horse.service.AvoLinkService
import org.avoperformance.horse.ui.components.AvoCard
import org.avoperformance.horse.ui.components.ConfirmDialog
import org.avoperformance.horse.ui.components.Fmt
import org.avoperformance.horse.ui.components.KV
import org.avoperformance.horse.ui.components.Note
import org.avoperformance.horse.ui.components.StatusPill
import org.avoperformance.horse.ui.theme.AvoColors
import java.io.File
import java.util.Locale

@Composable
fun SettingsScreen(c: AppContainer, go: (String) -> Unit) {
    val ctx = LocalContext.current
    var backupStatus by remember { mutableStateOf<String?>(null) }
    var favoriteName by remember { mutableStateOf("") }
    var favorites by remember { mutableStateOf(c.settings.shareFavorites) }
    var defaultFavorite by remember { mutableStateOf(c.settings.shareDefaultFavorite) }
    var dndEnabled by remember { mutableStateOf(c.settings.autoDndGeofence) }
    var dndAccess by remember { mutableStateOf(c.dnd.hasPolicyAccess()) }
    val dndAccessLauncher = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) {
        dndAccess = c.dnd.hasPolicyAccess()
        if (!dndAccess) {
            dndEnabled = false
            c.settings.autoDndGeofence = false
            c.dnd.restoreOwned("permiso no disponible")
        }
    }
    val exportLauncher = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        if (uri != null) {
            backupStatus = runCatching {
                ctx.contentResolver.openOutputStream(uri)?.use { out ->
                    out.write(SettingsBackup.export(c.settings).toByteArray(Charsets.UTF_8))
                } ?: error("No se pudo escribir la copia")
                "Copia de configuración guardada. Contraseña NTRIP y claves BLE excluidas."
            }.getOrElse { "Error al exportar: ${it.message}" }
        }
    }
    val importLauncher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            backupStatus = runCatching {
                val bytes = ctx.contentResolver.openInputStream(uri)?.use { input ->
                    val data = input.readNBytes(256_001)
                    require(data.size <= 256_000) { "Archivo demasiado grande" }
                    data
                } ?: error("No se pudo leer el archivo")
                SettingsBackup.restore(c.settings, bytes.toString(Charsets.UTF_8))
                "Configuración restaurada. Introduce la contraseña NTRIP y vuelve a autorizar el reloj si es otro móvil."
            }.getOrElse { "Error al restaurar: ${it.message}" }
        }
    }
    val entries = listOf(
        "bluetooth" to "Bluetooth · chaleco y autorización",
        "ntrip" to "NTRIP · correcciones RTK",
        "geocercas" to "Geocercas",
        "compartir" to "Compartir y sincronizar · usuarios AVO",
        "sincronizacion" to "Sincronización",
        "diagnosticos" to "Diagnósticos",
        "almacenamiento" to "Almacenamiento",
        "jinetes" to "Jinetes",
        "nfc" to "NFC · Leer y grabar tarjetas",
        "dispositivos" to "Dispositivos",
    )
    LazyColumn(Modifier.fillMaxSize()) {
        items(entries) { (r, t) -> AvoCard(onClick = { go(r) }, trailing = { Text("›", color = AvoColors.TextDim, fontSize = 20.sp) }) { Text(t, color = AvoColors.Text, fontSize = 16.sp) } }
        item {
            var spotName by remember { mutableStateOf(c.settings.spotName) }
            var spotLat by remember { mutableStateOf(c.settings.spotLat.toString()) }
            var spotLon by remember { mutableStateOf(c.settings.spotLon.toString()) }
            val tel by c.watch.telemetry.collectAsStateWithLifecycle()
            AvoCard("Lugar de entrenamiento · mareas y tiempo") {
                OutlinedTextField(spotName, { spotName = it.take(40) }, label = { Text("Nombre") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(spotLat, { spotLat = it.take(12) }, label = { Text("Latitud") }, singleLine = true, modifier = Modifier.weight(1f))
                    OutlinedTextField(spotLon, { spotLon = it.take(12) }, label = { Text("Longitud") }, singleLine = true, modifier = Modifier.weight(1f))
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 6.dp)) {
                    OutlinedButton(enabled = tel?.t?.let { it.latE7 != 0 || it.lonE7 != 0 } == true, onClick = {
                        tel?.t?.let { spotLat = "%.5f".format(Locale.US, it.latE7 / 1e7); spotLon = "%.5f".format(Locale.US, it.lonE7 / 1e7) }
                    }) { Text("Posición del chaleco") }
                    Button(enabled = (spotLat.toDoubleOrNull() ?: 999.0) in -90.0..90.0 && (spotLon.toDoubleOrNull() ?: 999.0) in -180.0..180.0 && spotName.isNotBlank(), onClick = {
                        c.settings.spotName = spotName.trim(); c.settings.spotLat = spotLat.toDouble(); c.settings.spotLon = spotLon.toDouble()
                        c.settings.tidePortId = null
                    }) { Text("Guardar") }
                }
            }
        }
        item {
            AvoCard("No molestar automático por geocerca") {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text("Silenciar durante grabación automática", color = AvoColors.Text, modifier = Modifier.weight(1f))
                    Switch(checked = dndEnabled, onCheckedChange = { enabled ->
                        dndAccess = c.dnd.hasPolicyAccess()
                        if (enabled && !dndAccess) {
                            dndAccessLauncher.launch(Intent(android.provider.Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
                        } else {
                            dndEnabled = enabled
                            c.settings.autoDndGeofence = enabled
                            if (!enabled) c.dnd.restoreOwned("desactivado por el usuario")
                        }
                    })
                }
                KV("Permiso de Android", if (dndAccess) "Concedido" else "Pendiente")
                if (!dndAccess) {
                    OutlinedButton(onClick = {
                        dndAccessLauncher.launch(Intent(android.provider.Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
                    }) { Text("Autorizar No molestar") }
                }
            }
        }
        item {
            AvoCard("WhatsApp · destinatarios favoritos") {
                OutlinedTextField(value = favoriteName, onValueChange = { favoriteName = it.take(80) },
                    label = { Text("Nombre del favorito") }, singleLine = true)
                OutlinedButton(enabled = favoriteName.isNotBlank() && favorites.size < 12,
                    onClick = {
                        favorites = (favorites + favoriteName.trim()).distinctBy { it.lowercase(Locale.ROOT) }
                        c.settings.shareFavorites = favorites
                        favoriteName = ""
                    }) { Text("Añadir favorito") }
                favorites.forEach { name ->
                    Row(verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(name, modifier = Modifier.weight(1f))
                        OutlinedButton(onClick = {
                            defaultFavorite = name
                            c.settings.shareDefaultFavorite = name
                        }) { Text(if (defaultFavorite == name) "Predeterminado ✓" else "Predeterminar") }
                        OutlinedButton(onClick = {
                            favorites = favorites.filterNot { it == name }
                            c.settings.shareFavorites = favorites
                            if (defaultFavorite == name) {
                                defaultFavorite = ""
                                c.settings.shareDefaultFavorite = ""
                            }
                        }) { Text("Quitar") }
                    }
                }
            }
        }
        item {
            AvoCard("Copias de seguridad · sin servidor") {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = { exportLauncher.launch("AVO_CONFIG_V2_0.json") }) { Text("Guardar") }
                    OutlinedButton(onClick = { importLauncher.launch(arrayOf("application/json", "text/plain", "application/octet-stream")) }) { Text("Restaurar") }
                }
                backupStatus?.let { Note(it, AvoColors.Info) }
            }
        }
        item {
            AvoCard("Acerca de") {
                KV("Aplicación", "AVO Performance Horse ${org.avoperformance.horse.BuildConfig.VERSION_NAME}")
                KV("Paquete", "org.avoperformance.horse")
                KV("Protocolo BLE", "AVO BLE v1 (firmware V3.4.4 – V3.5.4)")
            }
        }
    }
}

@Composable
fun BluetoothScreen(c: AppContainer, requestPerms: () -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val link by c.watch.state.collectAsStateWithLifecycle()
    val detail by c.watch.detail.collectAsStateWithLifecycle()
    val info by c.watch.info.collectAsStateWithLifecycle()
    val found by c.watch.scanner.found.collectAsStateWithLifecycle()
    val scanning by c.watch.scanner.scanning.collectAsStateWithLifecycle()
    val scanErr by c.watch.scanner.error.collectAsStateWithLifecycle()
    var msg by remember { mutableStateOf<String?>(null) }
    var confirmForget by remember { mutableStateOf(false) }
    val granted = Perms.bluetoothGranted(ctx)
    DisposableEffect(Unit) { onDispose { c.watch.scanner.stop() } }

    LazyColumn(Modifier.fillMaxSize()) {
        if (!granted) item {
            AvoCard("Permisos") {
                Note(if (Build.VERSION.SDK_INT >= 31) "La app necesita permiso para buscar y conectar dispositivos Bluetooth cercanos."
                     else "En Android 10 y 11 la búsqueda Bluetooth requiere el permiso de ubicación (la app no usa tu ubicación).")
                Button(onClick = requestPerms) { Text("Conceder permisos") }
            }
        }
        item {
            AvoCard("Chaleco autorizado") {
                KV("Nombre", c.settings.authorizedWatchName)
                KV("Dirección", c.settings.authorizedWatch)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                    Text("Estado", color = AvoColors.TextDim)
                    StatusPill(link.texto, if (c.watch.isReady) AvoColors.Ok else if (link == LinkState.ESPERANDO_BOOT || link == LinkState.NECESITA_AUTORIZACION) AvoColors.Warn else AvoColors.Unknown)
                }
                detail?.let { Note(it, AvoColors.Warn) }
                KV("Firmware", info?.firmware)
                KV("Id del reloj", info?.deviceId)
                KV("Teléfonos autorizados en el reloj", info?.authKeys?.toString())
                if (info != null && !info!!.supportsAuth) Note("Este firmware no tiene autorización de aplicación. Instala V3.4.4 (Firmware_Patches) para que solo tu teléfono pueda controlarlo.", AvoColors.Warn)
                msg?.let { Note(it, AvoColors.Info) }
                Spacer(Modifier.height(6.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (c.settings.authorizedWatch != null) {
                        Button(enabled = granted, onClick = { AvoLinkService.start(ctx) }) { Text("Conectar") }
                        OutlinedButton(onClick = { AvoLinkService.stop(ctx) }) { Text("Desconectar") }
                    }
                }
                if (link == LinkState.NECESITA_AUTORIZACION) {
                    Spacer(Modifier.height(8.dp))
                    Note("Pulsa «Vincular» y después BOOT en el reloj")
                    Button(onClick = { scope.launch { msg = c.watch.claim("${Build.MANUFACTURER} ${Build.MODEL}") } }) { Text("Vincular este teléfono") }
                }
                if (link == LinkState.ESPERANDO_BOOT) Note("Pulsa BOOT en el reloj ahora…", AvoColors.Gold)
                if (c.settings.authorizedWatch != null) TextButton2("Olvidar este chaleco") { confirmForget = true }
                else {
                    Note("No hay ningún chaleco vinculado: búscalo aquí abajo, tócalo y pulsa BOOT en el reloj cuando lo pida.", AvoColors.Warn)
                    Button(enabled = granted && !scanning, onClick = { c.watch.scanner.start() }) { Text(if (scanning) "Buscando…" else "Buscar y vincular reloj") }
                }
            }
        }
        item {
            AvoCard("Buscar chalecos") {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(enabled = granted && !scanning, onClick = { c.watch.scanner.start() }) { Text(if (scanning) "Buscando…" else "Buscar") }
                    OutlinedButton(enabled = scanning, onClick = { c.watch.scanner.stop() }) { Text("Parar") }
                }
                scanErr?.let { Note(it, AvoColors.Bad) }
                found.forEach { w ->
                    AvoCard(onClick = { c.watch.scanner.stop(); c.watch.selectWatch(w.address, w.name); AvoLinkService.start(ctx); msg = "Conectando con ${w.name}…" }) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Column { Text(w.name, color = AvoColors.Text); Text(w.address, color = AvoColors.TextDim, fontSize = 12.sp) }
                            Text("${w.rssi} dBm", color = if (w.rssi > -70) AvoColors.Ok else if (w.rssi > -85) AvoColors.Warn else AvoColors.Bad)
                        }
                    }
                }
            }
        }
        item {
            AvoCard("Funcionamiento en segundo plano") {
                var auto by remember { mutableStateOf(c.settings.autoStart) }
                Toggle("Iniciar automáticamente sin abrir la app", auto) { auto = it; c.settings.autoStart = it; if (it) AvoLinkService.startIfAutomatic(ctx, "activado por el usuario") }
                Note("Conecta con el chaleco al encender el móvil, al activar Bluetooth y cuando el reloj se enlaza; mantiene NTRIP y la descarga automática. «Desconectar» lo pausa hasta que pulses «Conectar».")
                val pm = ctx.getSystemService(android.os.PowerManager::class.java)
                var exempt by remember { mutableStateOf(pm?.isIgnoringBatteryOptimizations(ctx.packageName) == true) }
                KV("Optimización de batería", if (exempt) "desactivada (recomendado)" else "activa: Android puede impedir el inicio en segundo plano", if (exempt) AvoColors.Ok else AvoColors.Warn)
                if (!exempt) OutlinedButton(onClick = {
                    runCatching {
                        ctx.startActivity(android.content.Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, android.net.Uri.parse("package:" + ctx.packageName)))
                    }.onFailure { ctx.startActivity(android.content.Intent(android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)) }
                }) { Text("Permitir funcionamiento en segundo plano") }
                LaunchedEffect(Unit) { while (true) { kotlinx.coroutines.delay(1500); exempt = pm?.isIgnoringBatteryOptimizations(ctx.packageName) == true } }
                Note("En Xiaomi/Redmi activa también «Inicio automático» de AVO en Ajustes > Aplicaciones.")
            }
        }
    }
    if (confirmForget) ConfirmDialog("Olvidar chaleco", "Se borrará la clave de autorización guardada en este teléfono. Para volver a usarlo habrá que vincularlo pulsando BOOT.", "Olvidar", danger = true,
        onConfirm = { AvoLinkService.stop(ctx); c.watch.forgetWatch() }, onDismiss = { confirmForget = false })
}

@Composable
private fun TextButton2(text: String, onClick: () -> Unit) = androidx.compose.material3.TextButton(onClick = onClick) { Text(text, color = AvoColors.Bad) }

@Composable
fun NtripScreen(c: AppContainer) {
    val saved by c.settings.ntrip.collectAsStateWithLifecycle()
    val state by c.ntrip.state.collectAsStateWithLifecycle()
    val stats by c.ntrip.stats.collectAsStateWithLifecycle()
    val path by c.ntrip.path.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    var n by remember(saved) { mutableStateOf(saved) }
    var pass by remember { mutableStateOf("") }
    var mounts by remember { mutableStateOf<List<String>>(emptyList()) }
    var msg by remember { mutableStateOf<String?>(null) }
    val hasPass = remember { c.secure.ntripPassword != null }

    LazyColumn(Modifier.fillMaxSize()) {
        item {
            AvoCard("Caster") {
                OutlinedTextField(n.host, { n = n.copy(host = it.trim()) }, label = { Text("Servidor (host)") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(n.port.toString(), { n = n.copy(port = it.filter(Char::isDigit).take(5).toIntOrNull() ?: 0) }, label = { Text("Puerto") }, singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), modifier = Modifier.fillMaxWidth())
                OutlinedTextField(n.mountpoint, { n = n.copy(mountpoint = it.trim()) }, label = { Text("Mountpoint") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(n.user, { n = n.copy(user = it) }, label = { Text("Usuario") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(pass, { pass = it }, label = { Text(if (hasPass) "Contraseña (guardada; escribe para cambiarla)" else "Contraseña") }, singleLine = true,
                    visualTransformation = PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password), modifier = Modifier.fillMaxWidth())
                Toggle("TLS (cifrado)", n.tls) { n = n.copy(tls = it) }
                Toggle("NTRIP v2 (desactivar para v1)", n.v2) { n = n.copy(v2 = it) }
                Toggle("Enviar posición GGA", n.sendGga) { n = n.copy(sendGga = it) }
                OutlinedTextField(n.ggaIntervalS.toString(), { n = n.copy(ggaIntervalS = it.filter(Char::isDigit).take(3).toIntOrNull() ?: 0) }, label = { Text("Intervalo GGA (s)") },
                    singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), modifier = Modifier.fillMaxWidth())
                OutlinedTextField(n.timeoutS.toString(), { n = n.copy(timeoutS = it.filter(Char::isDigit).take(3).toIntOrNull() ?: 0) }, label = { Text("Tiempo máximo sin datos (s)") },
                    singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), modifier = Modifier.fillMaxWidth())
                Toggle("Reconectar automáticamente", n.reconnect) { n = n.copy(reconnect = it) }
                Toggle("Activar NTRIP al conectar el chaleco", n.enabled) { n = n.copy(enabled = it) }
                msg?.let { Note(it, AvoColors.Warn) }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = {
                        c.settings.saveNtrip(n, pass.ifEmpty { null }); pass = ""
                        val p = c.settings.ntripConfig().problems()
                        msg = if (p.isEmpty()) "Guardado" else p.joinToString("\n")
                    }) { Text("Guardar") }
                    OutlinedButton(onClick = {
                        c.settings.saveNtrip(n, pass.ifEmpty { null }); pass = ""
                        scope.launch {
                            msg = "Consultando mountpoints…"
                            mounts = withContext(Dispatchers.IO) { runCatching { NtripClient.fetchSourcetable(c.settings.ntripConfig()) }.getOrElse { msg = "Error: ${it.message}"; emptyList() } }
                            if (mounts.isNotEmpty()) msg = "${mounts.size} mountpoints"
                        }
                    }) { Text("Ver mountpoints") }
                }
                mounts.take(60).forEach { m -> androidx.compose.material3.TextButton(onClick = { n = n.copy(mountpoint = m) }) { Text(m) } }
            }
        }
        item {
            AvoCard("Estado") {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("Conexión", color = AvoColors.TextDim)
                    StatusPill(state.texto.take(40), when (state) { is NtripState.Streaming -> AvoColors.Ok; is NtripState.Failed -> AvoColors.Bad; is NtripState.Stopped -> AvoColors.Unknown; else -> AvoColors.Warn })
                }
                KV("Recibido", Fmt.bytes(stats.bytesReceived))
                KV("Caudal", String.format(Locale.US, "%.0f B/s", stats.bytesPerSecond))
                KV("Reconexiones", "${stats.reconnects}")
                KV("GGA enviadas", "${stats.ggaSent}")
                KV("Tramas RTCM válidas", "${path.framer.framesOk}")
                KV("Tramas con CRC erróneo", "${path.framer.framesBadCrc}", if (path.framer.framesBadCrc > 0) AvoColors.Warn else AvoColors.Text)
                KV("Bytes no RTCM descartados", "${path.framer.garbageBytes}")
                KV("Último tipo RTCM", path.framer.lastType.takeIf { it > 0 }?.toString())
                KV("Tipos recibidos", path.framer.typeCounts.entries.sortedBy { it.key }.joinToString { "${it.key}×${it.value}" }.ifBlank { null })
                KV("Enviado al reloj", "${Fmt.bytes(path.sentBytes)} en ${path.sentWrites} escrituras")
                KV("En cola", Fmt.bytes(path.queuedBytes.toLong()))
                KV("Descartado por antiguo (> 5 s)", Fmt.bytes(path.droppedStale))
                KV("Descartado por cola llena", Fmt.bytes(path.droppedOverflow))
                KV("Descartado por el reloj", Fmt.bytes(path.watchDropped))
                KV("Espacio libre en el reloj", Fmt.bytes(path.watchFree))
                KV("Último acuse del reloj", path.lastAckAgeMs?.let { "hace $it ms" })
                stats.lastError?.let { Note("Último error: $it", AvoColors.Warn) }
                Spacer(Modifier.height(6.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(enabled = !c.ntrip.running, onClick = { c.ntrip.start() }) { Text("Iniciar") }
                    OutlinedButton(enabled = c.ntrip.running, onClick = { c.ntrip.stop() }) { Text("Detener") }
                }
            }
        }
    }
}

@Composable
fun Toggle(label: String, value: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, color = AvoColors.Text, modifier = Modifier.weight(1f))
        Switch(checked = value, onCheckedChange = onChange)
    }
}

@Composable
fun SyncScreen(c: AppContainer) {
    val all by c.db.trainings().all().collectAsStateWithLifecycle(emptyList())
    var auto by remember { mutableStateOf(c.settings.autoDownload) }
    val progress by c.sync.progress.collectAsStateWithLifecycle()
    LazyColumn(Modifier.fillMaxSize()) {
        item {
            AvoCard("Rutas de sincronización") {
                KV("Chaleco → WiFi → servidor", "pendiente (firmware sin WiFi)", AvoColors.Warn)
                KV("Chaleco → Bluetooth → teléfono", "activa", AvoColors.Ok)
                KV("Teléfono → servidor", if (c.sync.serverConfigured) "activa" else "servidor pendiente", if (c.sync.serverConfigured) AvoColors.Ok else AvoColors.Warn)
            }
        }
        item {
            AvoCard("Descarga automática") {
                Toggle("Descargar al conectar el chaleco", auto) { auto = it; c.settings.autoDownload = it }
                OutlinedButton(onClick = { c.sync.autoSync() }) { Text("Sincronizar ahora") }
                progress.message?.let { Note(it) }
            }
        }
        item {
            AvoCard("Resumen") {
                org.avoperformance.horse.core.sync.SyncState.values().forEach { s ->
                    val n = all.count { it.state == s.name }
                    if (n > 0) KV(s.texto, "$n", syncColor(s))
                }
                if (all.isEmpty()) Note("Sin entrenamientos registrados todavía.")
            }
        }
    }
}

@Composable
fun DiagnosticsScreen(c: AppContainer) {
    val scope = rememberCoroutineScope()
    val info by c.watch.info.collectAsStateWithLifecycle()
    val status by c.watch.status.collectAsStateWithLifecycle()
    val logs by c.db.log().last(80).collectAsStateWithLifecycle(emptyList())
    var diag by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    var bb by remember { mutableStateOf<List<BlackboxRecord>>(emptyList()) }
    var msg by remember { mutableStateOf<String?>(null) }
    var confirmReboot by remember { mutableStateOf(false) }
    val cl = c.watch.client
    val stats = cl?.stats

    LazyColumn(Modifier.fillMaxSize()) {
        item {
            AvoCard("Reloj") {
                KV("Firmware", info?.firmware); KV("Huella de compilación", info?.buildFingerprint); KV("Id", info?.deviceId)
                KV("Arranques", info?.bootCount?.toString()); KV("MTU", info?.mtu?.toString())
                KV("Capacidades", info?.caps?.let { "0x" + it.toString(16) })
                KV("Protocolo BLE / UART / RAW / config", info?.let { "${it.bleProto} / ${it.uartProto} / ${it.rawFormat} / ${it.configSchema}" })
                KV("SD libre", Fmt.bytes(status?.sdFreeBytes))
                KV("Fuente de hora", status?.timeSource?.name)
                KV("Registros descartados", status?.droppedRecords?.toString())
                KV("Ocupación del búfer", status?.ringPermille?.let { "${it / 10.0} %" })
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(enabled = cl != null, onClick = { scope.launch {
                        c.watch.refreshStatus()
                        diag = runCatching { cl!!.diag() }.getOrElse { msg = it.message; emptyMap() }
                        bb = runCatching { cl!!.blackbox(50) }.getOrElse { msg = it.message; emptyList() }
                    } }) { Text("Leer diagnóstico") }
                    OutlinedButton(enabled = cl != null && info?.supportsReboot == true, onClick = { confirmReboot = true }) { Text("Reiniciar reloj") }
                }
                msg?.let { Note(it, AvoColors.Warn) }
            }
        }
        item {
            AvoCard("Enlace Bluetooth (app)") {
                KV("Peticiones", stats?.requests?.toString()); KV("Reintentos", stats?.retries?.toString()); KV("Tiempo agotado", stats?.timeouts?.toString())
                KV("Duplicados detectados por el reloj", stats?.duplicates?.toString()); KV("Fragmentos con CRC erróneo", stats?.crcErrors?.toString())
                KV("Mensajes incompletos", stats?.gaps?.toString())
            }
        }
        if (diag.isNotEmpty()) item { AvoCard("Diagnóstico del reloj") { diag.forEach { (k, v) -> KV(k, v) } } }
        if (bb.isNotEmpty()) item {
            AvoCard("Caja negra (últimos ${bb.size})") {
                bb.forEach { r -> Text("#${r.seq} t=${r.uptimeMs / 1000}s ${BlackboxRecord.codeName(r.code)} sev=${r.severity} ${r.arg0}/${r.arg1}", color = AvoColors.TextDim, fontSize = 12.sp) }
            }
        }
        item {
            AvoCard("Registro de la app") {
                logs.forEach { l -> Text("${java.text.SimpleDateFormat("HH:mm:ss", Locale.US).format(java.util.Date(l.timeMs))} ${l.level} ${l.tag}: ${l.message}",
                    color = if (l.level == "E") AvoColors.Bad else if (l.level == "W") AvoColors.Warn else AvoColors.TextDim, fontSize = 12.sp) }
            }
        }
    }
    if (confirmReboot) ConfirmDialog("Reiniciar el reloj", "El reloj se reiniciará. Si hay una grabación en curso, el reloj la rechazará.", "Reiniciar", danger = true,
        onConfirm = { scope.launch { msg = cl?.reboot(false)?.texto } }, onDismiss = { confirmReboot = false })
}

@Composable
fun StorageScreen(c: AppContainer) {
    val status by c.watch.status.collectAsStateWithLifecycle()
    val all by c.db.trainings().all().collectAsStateWithLifecycle(emptyList())
    var used by remember { mutableStateOf<Long?>(null) }
    LaunchedEffect(all.size) { used = withContext(Dispatchers.IO) { dirSize(c.sync.trainingsDir) } }
    val ctx = LocalContext.current
    LazyColumn(Modifier.fillMaxSize()) {
        item {
            AvoCard("Chaleco (tarjeta SD)") {
                KV("Libre", Fmt.bytes(status?.sdFreeBytes))
                KV("Montada", status?.sdMounted?.let { if (it) "sí" else "no" })
                KV("Entrenamientos en el reloj", all.count { it.watchState != "UNKNOWN" }.toString())
            }
        }
        item {
            AvoCard("Teléfono") {
                KV("Entrenamientos descargados", Fmt.bytes(used))
                KV("Espacio libre del teléfono", Fmt.bytes(ctx.filesDir.usableSpace))
            }
        }
    }
}

private fun dirSize(f: File): Long = if (f.isFile) f.length() else (f.listFiles()?.sumOf { dirSize(it) } ?: 0L)
