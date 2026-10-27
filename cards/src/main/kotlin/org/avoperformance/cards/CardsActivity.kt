package org.avoperformance.cards

import android.app.DatePickerDialog
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.nfc.NfcAdapter
import android.os.Bundle
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.avoperformance.horse.core.identity.AvoUserCard
import org.avoperformance.horse.core.license.LicenseCrypto
import org.avoperformance.horse.core.license.LicenseFile
import org.avoperformance.horse.core.license.LicenseIssuer
import org.avoperformance.horse.core.license.LicenseKeyBackup
import org.avoperformance.horse.core.license.LicenseToken
import org.avoperformance.horse.ui.components.AvoCard
import org.avoperformance.horse.ui.components.ConfirmDialog
import org.avoperformance.horse.ui.components.KV
import org.avoperformance.horse.ui.components.Note
import org.avoperformance.horse.ui.components.StatusPill
import org.avoperformance.horse.ui.theme.AvoColors
import org.avoperformance.horse.ui.theme.AvoTheme
import java.security.KeyPair
import java.text.DateFormat
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Date
import kotlin.concurrent.thread

/** What the next tapped card is used for. [licenseUntil]: last day of the app licence to write (null = no licence). */
private sealed interface Mode {
    data object Read : Mode
    data class Write(val card: AvoUserCard, val isNew: Boolean, val licenseUntil: LocalDate?) : Mode
}

/** Password dialog purpose. */
private sealed interface PwdAsk {
    data object Export : PwdAsk
    data class Import(val text: String) : PwdAsk
}

private val DAY = DateTimeFormatter.ofPattern("dd/MM/yyyy")

class CardsActivity : ComponentActivity() {
    private val adapter by lazy { NfcAdapter.getDefaultAdapter(this) }
    private val zone: ZoneId get() = ZoneId.systemDefault()
    private lateinit var store: IssuedCards
    private lateinit var keys: LicenseKeyStore
    private val prefs by lazy { getSharedPreferences("license_issuer", Context.MODE_PRIVATE) }
    private var key by mutableStateOf<KeyPair?>(null)
    private var backedUp by mutableStateOf(false)
    private var busy by mutableStateOf<String?>(null)
    private var mode by mutableStateOf<Mode>(Mode.Read)
    private var overwrite by mutableStateOf(false)
    private var lock by mutableStateOf(false)
    private var status by mutableStateOf("Acerca una tarjeta para leerla, o crea una nueva.")
    private var keyMessage by mutableStateOf<String?>(null)
    private var issued by mutableStateOf<List<Issued>>(emptyList())
    private var pwdAsk by mutableStateOf<PwdAsk?>(null)
    private var pendingExportPassword: CharArray? = null
    private var replaceKey by mutableStateOf<KeyPair?>(null)
    private var lastTap = 0L

    private val exportLauncher = registerForActivityResult(ActivityResultContracts.CreateDocument("text/plain")) { uri -> onExportTarget(uri) }
    private val importLauncher = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri -> onImportSource(uri) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        store = IssuedCards(this)
        keys = LicenseKeyStore(this)
        key = keys.load()
        backedUp = key != null && prefs.getString(BACKED_UP, null) == key?.let(::keyIdHex)
        issued = store.all()
        setContent { AvoTheme { Surface(Modifier.fillMaxSize(), color = AvoColors.Bg) { Screen() } } }
    }

    override fun onResume() {
        super.onResume()
        val a = adapter
        status = when {
            a == null -> "Este móvil no tiene NFC."
            !a.isEnabled -> "Activa NFC en los ajustes de Android."
            else -> status
        }
        a?.takeIf { it.isEnabled }?.enableReaderMode(this, { tag -> onTag(tag) },
            NfcAdapter.FLAG_READER_NFC_A, null)
    }

    override fun onPause() {
        runCatching { adapter?.disableReaderMode(this) }
        super.onPause()
    }

    private fun keyIdHex(k: KeyPair) = LicenseCrypto.keyId(k.public).joinToString("") { "%02X".format(it) }

    /** Human description of the licence on a card, checked against this phone's key. */
    private fun describeLicense(bytes: ByteArray?, uid: ByteArray?): String {
        if (bytes == null) return "sin licencia de la app"
        val t = runCatching { LicenseToken.decode(bytes) }.getOrElse { return "licencia dañada" }
        val until = LicenseIssuer.lastDayOf(t.expiresAtS, zone).format(DAY)
        val k = key
        val sig = when {
            k == null -> "firma sin comprobar (no hay clave en este móvil)"
            !LicenseCrypto.keyId(k.public).contentEquals(t.keyId) -> "firmada con OTRA clave"
            !LicenseCrypto.verify(t, k.public) -> "FIRMA NO VÁLIDA"
            uid != null && !uid.contentEquals(t.uid) -> "NO pertenece a esta tarjeta (copia)"
            else -> "firma válida"
        }
        val expired = System.currentTimeMillis() >= t.expiresAtMs
        return "licencia hasta $until${if (expired) " (CADUCADA)" else ""} · $sig"
    }

    private fun onTag(tag: android.nfc.Tag) {
        val now = SystemClock.elapsedRealtime()
        if (now - lastTap < 1500) return
        lastTap = now
        val m = mode
        val text = try {
            when (m) {
                Mode.Read -> {
                    val r = CardWriter.read(tag)
                    val uri = r.uri
                    if (uri == null) "Tarjeta vacía o sin formato AVO."
                    else {
                        val desc = CardWriter.describe(uri)
                        val known = if (AvoUserCard.isUserUri(uri)) runCatching { store.byCode(AvoUserCard.parse(uri).code) }.getOrNull() else null
                        "Leída: $desc" + when {
                            known == null && AvoUserCard.isUserUri(uri) -> " · no emitida desde este móvil"
                            known?.revoked == true -> " · DADA DE BAJA"
                            else -> ""
                        } + if (AvoUserCard.isUserUri(uri)) "\n" + describeLicense(r.license, tag.id) else ""
                    }
                }
                is Mode.Write -> {
                    val until = m.licenseUntil
                    val k = key
                    if (until != null && k == null) "No hay clave de licencias en este móvil."
                    else {
                        val signer: ((ByteArray) -> ByteArray)? = if (until == null || k == null) null else { uid ->
                            LicenseIssuer.issue(k, uid, m.card.code, System.currentTimeMillis(), until, zone).encode()
                        }
                        when (val r = CardWriter.write(tag, m.card, overwrite, lock && until == null, signer)) {
                            is CardWriter.Outcome.Refused -> r.reason
                            is CardWriter.Outcome.Written -> {
                                val expiresS = until?.let { LicenseIssuer.expiryForLastDay(it, zone) }
                                val prev = store.byCode(m.card.code)
                                val base = prev ?: Issued(m.card, System.currentTimeMillis(), revoked = false)
                                val uidHex = if (until != null) tag.id.joinToString("") { "%02X".format(it) } else base.uidHex
                                if (m.isNew || prev != null) store.save(base.copy(licenseExpiresS = expiresS ?: base.licenseExpiresS, uidHex = uidHex))
                                runOnUiThread { issued = store.all(); mode = Mode.Read; overwrite = false; lock = false }
                                buildString {
                                    append("Tarjeta grabada: ${m.card.name} · ${m.card.code}")
                                    if (until != null) append("\nLicencia de la app hasta ${until.format(DAY)}")
                                    append(if (r.verified) " · verificada" else " · retírala y léela para verificar")
                                    if (r.locked) append(" · bloqueada")
                                }
                            }
                        }
                    }
                }
            }
        } catch (e: Exception) {
            "Error NFC: ${e.message ?: e.javaClass.simpleName}. Mantén la tarjeta quieta y vuelve a acercarla."
        }
        runOnUiThread { status = text }
    }

    // ---- key management

    private fun copyPublicKey(k: KeyPair) {
        getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("Clave pública AVO", LicenseCrypto.publicKeyToBase64(k.public)))
        keyMessage = "Clave pública copiada."
    }

    private fun sharePublicKey(k: KeyPair) {
        val text = "Clave pública de licencias AVO (${keyIdHex(k)}):\n${LicenseCrypto.publicKeyToBase64(k.public)}"
        startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text), "Compartir clave pública"))
    }

    private fun onExportTarget(uri: Uri?) {
        val pwd = pendingExportPassword; pendingExportPassword = null
        val k = key
        if (uri == null || pwd == null || k == null) { pwd?.fill(' '); return }
        busy = "Cifrando la copia…"
        thread {
            val msg = try {
                val text = LicenseKeyBackup.export(k, pwd)
                contentResolver.openOutputStream(uri, "wt")!!.use { it.write(text.toByteArray(Charsets.US_ASCII)) }
                prefs.edit().putString(BACKED_UP, keyIdHex(k)).apply()
                runOnUiThread { backedUp = true }
                "Copia cifrada guardada. Guárdala fuera del móvil (ordenador, nube) y no olvides la contraseña."
            } catch (e: Exception) { "No se pudo guardar la copia: ${e.message}" } finally { pwd.fill(' ') }
            runOnUiThread { busy = null; keyMessage = msg }
        }
    }

    private fun onImportSource(uri: Uri?) {
        if (uri == null) return
        val text = runCatching { contentResolver.openInputStream(uri)!!.use { it.readBytes().toString(Charsets.US_ASCII) } }.getOrNull()
        if (text == null || !text.trimStart().startsWith(LicenseKeyBackup.HEADER)) { keyMessage = "Ese archivo no es una copia de la clave de licencias AVO."; return }
        pwdAsk = PwdAsk.Import(text)
    }

    private fun doImport(text: String, pwd: CharArray) {
        busy = "Descifrando la copia…"
        thread {
            val result = runCatching { LicenseKeyBackup.import(text, pwd) }
            pwd.fill(' ')
            runOnUiThread {
                busy = null
                result.onFailure { keyMessage = "No se pudo importar: ${it.message}" }
                result.onSuccess { pair ->
                    val cur = key
                    if (cur != null && !cur.public.encoded.contentEquals(pair.public.encoded)) replaceKey = pair
                    else installKey(pair, fromBackup = true)
                }
            }
        }
    }

    private fun installKey(pair: KeyPair, fromBackup: Boolean) {
        keys.save(pair)
        key = pair
        if (fromBackup) prefs.edit().putString(BACKED_UP, keyIdHex(pair)).apply()
        backedUp = fromBackup || prefs.getString(BACKED_UP, null) == keyIdHex(pair)
        keyMessage = if (fromBackup) "Clave ${keyIdHex(pair)} importada." else "Clave ${keyIdHex(pair)} generada. Haz ahora la copia cifrada."
    }

    /** Licence for a user who cannot bring the card: encrypted file for email/WhatsApp (see LicenseFile). */
    private fun sendLicenseFile(i: Issued, lastDay: LocalDate) {
        val k = key ?: return
        try {
            val uid = i.uidHex.takeIf { it.length in 2..20 && it.length % 2 == 0 }
                ?.chunked(2)?.map { it.toInt(16).toByte() }?.toByteArray() ?: byteArrayOf(0)
            val token = LicenseIssuer.issue(k, uid, i.card.code, System.currentTimeMillis(), lastDay, zone, remote = true)
            val dir = java.io.File(cacheDir, "licencias").apply { mkdirs(); listFiles()?.forEach { it.delete() } }
            val file = java.io.File(dir, "AVO_licencia_${i.card.code}_hasta_$lastDay.${LicenseFile.EXTENSION}")
            file.writeText(LicenseFile.encode(token, i.card), Charsets.US_ASCII)
            store.save(i.copy(licenseExpiresS = token.expiresAtS)); issued = store.all()
            val uri = androidx.core.content.FileProvider.getUriForFile(this, "org.avoperformance.cards.files", file)
            val text = "Licencia de AVO Performance Horse para ${i.card.name} hasta el ${lastDay.format(DAY)}. " +
                "Abre este archivo con la app AVO Performance Horse (o en la app: Inicio → Licencia → Abrir archivo)."
            val send = Intent(Intent.ACTION_SEND).setType("application/octet-stream")
                .putExtra(Intent.EXTRA_STREAM, uri).putExtra(Intent.EXTRA_TEXT, text)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            startActivity(Intent.createChooser(send, "Enviar licencia a ${i.card.name}"))
            status = "Licencia por archivo para ${i.card.name} hasta el ${lastDay.format(DAY)}: solo la puede abrir el móvil que conoce su tarjeta."
        } catch (e: Exception) {
            status = "No se pudo crear el archivo de licencia: ${e.message}"
        }
    }

    private fun pickDate(initial: LocalDate?, onPicked: (LocalDate) -> Unit) {
        val d = initial ?: LocalDate.now(zone).plusYears(1)
        DatePickerDialog(this, { _, y, mo, day -> onPicked(LocalDate.of(y, mo + 1, day)) }, d.year, d.monthValue - 1, d.dayOfMonth).apply {
            datePicker.minDate = System.currentTimeMillis() - 1000
            setTitle("Licencia activa hasta…")
        }.show()
    }

    @Composable
    private fun Screen() {
        var name by remember { mutableStateOf("") }
        var withLicense by remember { mutableStateOf(true) }
        var until by remember { mutableStateOf<LocalDate?>(null) }
        var confirmRevoke by remember { mutableStateOf<Issued?>(null) }
        var confirmGenerate by remember { mutableStateOf(false) }
        val k = key
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp)) {
            item {
                // Brand header, same as the main app and AVO Update
                Box {
                    Image(painterResource(R.drawable.avo_brand_hero), contentDescription = "AVO Performance Horse",
                        contentScale = ContentScale.FillWidth, modifier = Modifier.fillMaxWidth().heightIn(max = 220.dp))
                }
                Row(Modifier.padding(start = 16.dp, top = 10.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("AVO", color = AvoColors.Red, fontSize = 24.sp, fontWeight = FontWeight.Black, letterSpacing = 3.sp)
                    Text("  TARJETAS", color = AvoColors.Text, fontSize = 17.sp, fontWeight = FontWeight.Black, letterSpacing = 2.sp)
                }
            }
            item {
                AvoCard("Clave de licencias", trailing = {
                    when {
                        k == null -> StatusPill("SIN CLAVE", AvoColors.Bad)
                        !backedUp -> StatusPill("SIN COPIA", AvoColors.Warn)
                        else -> StatusPill("LISTA", AvoColors.Ok)
                    }
                }) {
                    if (k == null) {
                        Note("Para grabar licencias de la app hace falta una clave de firma. Genérala una sola vez en este móvil, o importa la copia cifrada si ya la tienes.")
                        Spacer(Modifier.height(8.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Button(onClick = { confirmGenerate = true }, enabled = busy == null) { Text("GENERAR CLAVE", fontWeight = FontWeight.Bold) }
                            OutlinedButton(onClick = { importLauncher.launch(arrayOf("text/plain", "*/*")) }, enabled = busy == null) { Text("Importar copia") }
                        }
                    } else {
                        KV("Identificador", keyIdHex(k))
                        Spacer(Modifier.height(4.dp))
                        Text("Clave pública", color = AvoColors.TextDim, fontSize = 12.sp)
                        SelectionContainer { Text(LicenseCrypto.publicKeyToBase64(k.public), color = AvoColors.Silver, fontSize = 11.sp, fontFamily = FontFamily.Monospace) }
                        Spacer(Modifier.height(6.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            OutlinedButton(onClick = { copyPublicKey(k) }) { Text("Copiar") }
                            OutlinedButton(onClick = { sharePublicKey(k) }) { Text("Compartir") }
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Button(onClick = { pwdAsk = PwdAsk.Export }, enabled = busy == null) { Text("EXPORTAR COPIA CIFRADA", fontWeight = FontWeight.Bold) }
                        }
                        TextButton(onClick = { importLauncher.launch(arrayOf("text/plain", "*/*")) }, enabled = busy == null) { Text("Importar otra copia") }
                        Note("La app AVO Performance Horse solo acepta licencias firmadas con las claves que lleva compiladas. " +
                            "Añade la clave pública en GitHub → Settings → Secrets and variables → Actions → Variables → AVO_LICENSE_PUBLIC_KEYS.")
                    }
                    busy?.let { Spacer(Modifier.height(6.dp)); Text(it, color = AvoColors.Blue) }
                    keyMessage?.let { Spacer(Modifier.height(6.dp)); Text(it, color = AvoColors.Text) }
                }
            }
            item {
                AvoCard("Nueva tarjeta personal") {
                    OutlinedTextField(value = name, onValueChange = { name = it.take(AvoUserCard.MAX_NAME) },
                        label = { Text("Nombre") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                    Spacer(Modifier.height(4.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(withLicense && k != null, { withLicense = it }, enabled = k != null)
                        Text("Licencia de la app", color = if (k != null) AvoColors.Text else AvoColors.TextDim)
                    }
                    if (withLicense && k != null) {
                        OutlinedButton(onClick = { pickDate(until) { until = it } }, modifier = Modifier.fillMaxWidth()) {
                            Text(until?.let { "Activa hasta el ${it.format(DAY)}" } ?: "Elegir fecha de activación")
                        }
                    }
                    Spacer(Modifier.height(8.dp))
                    val needsDate = withLicense && k != null && until == null
                    Button(enabled = name.isNotBlank() && !needsDate, modifier = Modifier.fillMaxWidth(), onClick = {
                        val card = AvoUserCard.generate(name)
                        val lic = if (withLicense && k != null) until else null
                        mode = Mode.Write(card, isNew = true, licenseUntil = lic)
                        status = "Acerca una tarjeta en blanco para grabar ${card.name}" + (lic?.let { " con licencia hasta el ${it.format(DAY)}." } ?: ".")
                    }) { Text("CREAR Y GRABAR", fontWeight = FontWeight.Bold) }
                    Spacer(Modifier.height(6.dp))
                    Note("Usa NTAG215 o NTAG216 (las NTAG213 se quedan cortas). La licencia queda ligada al chip: copiada a otra tarjeta no funciona.")
                }
            }
            item {
                val m = mode
                AvoCard("Lector NFC", trailing = {
                    if (m is Mode.Write) StatusPill("GRABANDO", AvoColors.Red) else StatusPill("LECTURA", AvoColors.Blue)
                }) {
                    if (m is Mode.Write) {
                        KV("Tarjeta", "${m.card.name} · ${m.card.code}")
                        KV("Licencia", m.licenseUntil?.let { "hasta el ${it.format(DAY)}" } ?: "sin licencia")
                    }
                    Text(status, color = AvoColors.Text)
                    if (m is Mode.Write) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Checkbox(overwrite, { overwrite = it }); Text("Sobrescribir si ya tiene datos AVO", color = AvoColors.Text)
                        }
                        if (m.licenseUntil == null) Row(verticalAlignment = Alignment.CenterVertically) {
                            Checkbox(lock, { lock = it }); Text("Bloquear tarjeta (irreversible)", color = if (lock) AvoColors.Warn else AvoColors.Text)
                        } else Note("Las tarjetas con licencia no se bloquean: así se pueden renovar.")
                        OutlinedButton(onClick = { mode = Mode.Read; status = "Cancelado." }) { Text("Cancelar") }
                    }
                }
            }
            item {
                AvoCard("Tarjetas emitidas (${issued.size})") {
                    if (issued.isEmpty()) Note("Ninguna todavía.")
                    issued.forEachIndexed { idx, i ->
                        if (idx > 0) HorizontalDivider(color = AvoColors.Line, modifier = Modifier.padding(vertical = 6.dp))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(i.card.name, color = AvoColors.Text, fontWeight = FontWeight.SemiBold)
                                Text("${i.card.code} · ${DateFormat.getDateInstance(DateFormat.SHORT).format(Date(i.createdMs))}", color = AvoColors.TextDim, fontSize = 12.sp)
                                if (i.licenseExpiresS > 0) {
                                    val expired = System.currentTimeMillis() / 1000 >= i.licenseExpiresS
                                    Text("Licencia hasta el ${LicenseIssuer.lastDayOf(i.licenseExpiresS, zone).format(DAY)}" + if (expired) " · CADUCADA" else "",
                                        color = if (expired) AvoColors.Bad else AvoColors.Ok, fontSize = 12.sp)
                                } else Text("Sin licencia de la app", color = AvoColors.TextDim, fontSize = 12.sp)
                            }
                            if (i.revoked) StatusPill("BAJA", AvoColors.Bad)
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            if (!i.revoked && k != null) TextButton(onClick = {
                                pickDate(null) { d ->
                                    mode = Mode.Write(i.card, isNew = false, licenseUntil = d)
                                    status = "Acerca la tarjeta de ${i.card.name} para grabar la licencia hasta el ${d.format(DAY)}."
                                }
                            }) { Text(if (i.licenseExpiresS > 0) "Renovar" else "Licencia") }
                            if (!i.revoked && k != null) TextButton(onClick = { pickDate(null) { d -> sendLicenseFile(i, d) } }) { Text("Por archivo") }
                            if (!i.revoked) TextButton(onClick = {
                                val keep = i.licenseExpiresS.takeIf { it > System.currentTimeMillis() / 1000 && k != null }?.let { LicenseIssuer.lastDayOf(it, zone) }
                                mode = Mode.Write(i.card, isNew = false, licenseUntil = keep)
                                status = "Acerca una tarjeta para grabar una copia de ${i.card.name}" + (keep?.let { " (licencia hasta el ${it.format(DAY)})." } ?: ".")
                            }) { Text("Copia") }
                            TextButton(onClick = { if (i.revoked) { store.save(i.copy(revoked = false)); issued = store.all() } else confirmRevoke = i }) {
                                Text(if (i.revoked) "Reactivar" else "Baja", color = if (i.revoked) AvoColors.Ok else AvoColors.Bad)
                            }
                        }
                    }
                    Spacer(Modifier.height(6.dp))
                    Note("La baja de momento queda registrada solo en este móvil. «Por archivo» envía la licencia por WhatsApp o email a quien no puede traer la tarjeta: va cifrada con la clave de su tarjeta, así que solo sirve en su móvil.")
                }
            }
        }
        confirmRevoke?.let { i ->
            ConfirmDialog(title = "Dar de baja", text = "¿Dar de baja la tarjeta de ${i.card.name} (${i.card.code})? Úsalo si se ha perdido.",
                confirm = "Dar de baja", danger = true,
                onConfirm = { store.save(i.copy(revoked = true)); issued = store.all(); confirmRevoke = null },
                onDismiss = { confirmRevoke = null })
        }
        if (confirmGenerate) ConfirmDialog(title = "Generar clave de licencias",
            text = "Se crea la clave que firma todas las licencias. Haz después la copia cifrada: si pierdes este móvil sin copia, habrá que regrabar todas las tarjetas y publicar una app nueva.",
            confirm = "Generar", onConfirm = { confirmGenerate = false; installKey(keys.generate(), fromBackup = false) }, onDismiss = { confirmGenerate = false })
        replaceKey?.let { pair ->
            ConfirmDialog(title = "Sustituir la clave", danger = true,
                text = "La copia contiene otra clave (${keyIdHex(pair)}). Si sustituyes la actual (${k?.let(::keyIdHex)}), este móvil dejará de firmar con ella. Las tarjetas ya grabadas siguen valiendo mientras la app incluya su clave pública.",
                confirm = "Sustituir", onConfirm = { replaceKey = null; installKey(pair, fromBackup = true) }, onDismiss = { replaceKey = null })
        }
        pwdAsk?.let { ask -> PasswordDialog(ask, onDismiss = { pwdAsk = null }, onOk = { pwd ->
            pwdAsk = null
            when (ask) {
                PwdAsk.Export -> { pendingExportPassword = pwd; exportLauncher.launch("AVO_clave_licencias_${k?.let(::keyIdHex)}.txt") }
                is PwdAsk.Import -> doImport(ask.text, pwd)
            }
        }) }
    }

    @Composable
    private fun PasswordDialog(ask: PwdAsk, onDismiss: () -> Unit, onOk: (CharArray) -> Unit) {
        var p1 by remember { mutableStateOf("") }
        var p2 by remember { mutableStateOf("") }
        val export = ask is PwdAsk.Export
        val ok = if (export) p1.length >= LicenseKeyBackup.MIN_PASSWORD && p1 == p2 else p1.isNotEmpty()
        AlertDialog(onDismissRequest = onDismiss, containerColor = AvoColors.Surface,
            title = { Text(if (export) "Contraseña de la copia" else "Contraseña de la copia importada") },
            text = {
                Column {
                    if (export) Note("Mínimo ${LicenseKeyBackup.MIN_PASSWORD} caracteres. Sin esta contraseña la copia no sirve: apúntala en un lugar seguro.")
                    OutlinedTextField(p1, { p1 = it }, label = { Text("Contraseña") }, singleLine = true,
                        visualTransformation = PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password))
                    if (export) OutlinedTextField(p2, { p2 = it }, label = { Text("Repetir contraseña") }, singleLine = true,
                        visualTransformation = PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password))
                }
            },
            confirmButton = { TextButton(enabled = ok, onClick = { onOk(p1.toCharArray()); p1 = ""; p2 = "" }) { Text("Aceptar") } },
            dismissButton = { TextButton(onClick = onDismiss) { Text("Cancelar") } })
    }

    private companion object { const val BACKED_UP = "backed_up_key_id" }
}
