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
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.avoperformance.horse.core.identity.AvoUserCard
import org.avoperformance.horse.core.license.IssuerBackup
import org.avoperformance.horse.core.license.IssuerRegistry
import org.avoperformance.horse.core.license.LicenseCrypto
import org.avoperformance.horse.core.license.LicenseFeatures
import org.avoperformance.horse.core.license.LicenseFile
import org.avoperformance.horse.core.license.LicenseIssuer
import org.avoperformance.horse.core.license.LicenseKeyBackup
import org.avoperformance.horse.core.license.LicensePolicy
import org.avoperformance.horse.core.license.LicenseRole
import org.avoperformance.horse.core.license.LicenseToken
import org.avoperformance.horse.core.license.PasswordBox
import org.avoperformance.horse.core.license.RegEvent
import org.avoperformance.horse.core.license.RegUser
import org.avoperformance.horse.ui.components.AvoCard
import org.avoperformance.horse.ui.components.ConfirmDialog
import org.avoperformance.horse.ui.components.KV
import org.avoperformance.horse.ui.components.Note
import org.avoperformance.horse.ui.components.StatusPill
import org.avoperformance.horse.ui.theme.AvoColors
import org.avoperformance.horse.ui.theme.AvoTheme
import java.security.KeyPair
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.concurrent.thread

/**
 * What the next tapped card is used for. [licenseUntil]: last day of the app licence to write (null = no licence);
 * [roles]: roles of that licence (they decide the functions of the app).
 */
private sealed interface Mode {
    data object Read : Mode
    data class Write(val card: AvoUserCard, val kind: RegEvent.Kind, val licenseUntil: LocalDate?, val roles: Set<LicenseRole> = emptySet()) : Mode
}

/** Licence editor for a registered user: on the card, or as a file to send. */
private data class LicenseAsk(val user: RegUser, val byFile: Boolean)

/** Password dialog purpose. */
private sealed interface PwdAsk {
    data object Export : PwdAsk
    data class Import(val text: String) : PwdAsk
}

/** User card read with this phone that is not in the register yet. */
private data class Found(val card: AvoUserCard, val uidHex: String, val token: LicenseToken?)

private val DAY = DateTimeFormatter.ofPattern("dd/MM/yyyy")
private val DAY_TIME = DateTimeFormatter.ofPattern("dd/MM/yyyy HH:mm")

class CardsActivity : ComponentActivity() {
    private val adapter by lazy { NfcAdapter.getDefaultAdapter(this) }
    private val zone: ZoneId get() = ZoneId.systemDefault()
    private lateinit var store: RegistryStore
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
    private var registry by mutableStateOf(IssuerRegistry())
    private var found by mutableStateOf<Found?>(null)
    private var pwdAsk by mutableStateOf<PwdAsk?>(null)
    private var pendingExportPassword: CharArray? = null
    private var replaceKey by mutableStateOf<KeyPair?>(null)
    private var lastTap = 0L

    private val exportLauncher = registerForActivityResult(ActivityResultContracts.CreateDocument("text/plain")) { uri -> onExportTarget(uri) }
    private val importLauncher = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri -> onImportSource(uri) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        store = RegistryStore(this)
        keys = LicenseKeyStore(this)
        key = keys.load()
        registry = store.load()
        backedUp = prefs.getLong(BACKUP_MS, 0) > 0 && prefs.getLong(BACKUP_MS, 0) >= prefs.getLong(CHANGED_MS, 0)
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
    private fun hex(b: ByteArray) = b.joinToString("") { "%02X".format(it) }
    private fun day(expiresS: Long) = LicenseIssuer.lastDayOf(expiresS, zone).format(DAY)

    /** Every change of the register is saved at once (encrypted) and marks the backup as out of date. */
    @Synchronized
    private fun update(change: (IssuerRegistry) -> IssuerRegistry) {
        val next = change(store.load())
        store.save(next)
        prefs.edit().putLong(CHANGED_MS, System.currentTimeMillis()).apply()
        runOnUiThread { registry = next; backedUp = false }
    }

    /** Licence on a card checked against this phone's key: the token when it is valid and belongs to the card. */
    private fun validToken(bytes: ByteArray?, uid: ByteArray?): LicenseToken? {
        val k = key ?: return null
        val t = bytes?.let { runCatching { LicenseToken.decode(it) }.getOrNull() } ?: return null
        return t.takeIf { LicensePolicy.verifySignature(it, listOf(k.public)) && (uid == null || uid.contentEquals(it.uid)) }
    }

    /** Human description of the licence on a card, checked against this phone's key. */
    private fun describeLicense(bytes: ByteArray?, uid: ByteArray?): String {
        if (bytes == null) return "sin licencia de la app"
        val t = runCatching { LicenseToken.decode(bytes) }.getOrElse { return "licencia dañada" }
        val k = key
        val sig = when {
            k == null -> "firma sin comprobar (no hay clave en este móvil)"
            !LicenseCrypto.keyId(k.public).contentEquals(t.keyId) -> "firmada con OTRA clave"
            !LicenseCrypto.verify(t, k.public) -> "FIRMA NO VÁLIDA"
            uid != null && !uid.contentEquals(t.uid) -> "NO pertenece a esta tarjeta (copia)"
            else -> "firma válida"
        }
        val expired = System.currentTimeMillis() >= t.expiresAtMs
        return "licencia hasta ${day(t.expiresAtS)}${if (expired) " (CADUCADA)" else ""} · ${LicenseRole.label(t.roleSet)} · $sig"
    }

    private fun onTag(tag: android.nfc.Tag) {
        val now = SystemClock.elapsedRealtime()
        if (now - lastTap < 1500) return
        lastTap = now
        val text = try {
            when (val m = mode) {
                Mode.Read -> readCard(tag)
                is Mode.Write -> writeCard(tag, m)
            }
        } catch (e: Exception) {
            "Error NFC: ${e.message ?: e.javaClass.simpleName}. Mantén la tarjeta quieta y vuelve a acercarla."
        }
        runOnUiThread { status = text }
    }

    private fun readCard(tag: android.nfc.Tag): String {
        val r = CardWriter.read(tag)
        val uri = r.uri ?: return "Tarjeta vacía o sin formato AVO."
        val desc = CardWriter.describe(uri)
        if (!AvoUserCard.isUserUri(uri)) { runOnUiThread { found = null }; return "Leída: $desc" }
        val card = AvoUserCard.parse(uri)
        val known = store.load().user(card.code)
        runOnUiThread { found = if (known == null) Found(card, hex(tag.id), validToken(r.license, tag.id)) else null }
        return "Leída: $desc" + when {
            known == null -> " · NO está en el registro"
            known.revoked -> " · DADA DE BAJA"
            else -> " · en el registro"
        } + "\n" + describeLicense(r.license, tag.id)
    }

    private fun writeCard(tag: android.nfc.Tag, m: Mode.Write): String {
        val until = m.licenseUntil
        val k = key
        if (until != null && k == null) return "No hay clave de licencias en este móvil."
        if (until != null && m.roles.isEmpty()) return "Marca al menos un rol para la licencia."
        var issued: LicenseToken? = null
        val signer: ((ByteArray) -> ByteArray)? = if (until == null || k == null) null else { uid ->
            LicenseIssuer.issue(k, uid, m.card.code, System.currentTimeMillis(), until, zone, m.roles).also { issued = it }.encode()
        }
        return when (val r = CardWriter.write(tag, m.card, overwrite, lock && until == null, signer)) {
            is CardWriter.Outcome.Refused -> r.reason
            is CardWriter.Outcome.Written -> {
                val t = issued
                val nowMs = System.currentTimeMillis()
                update { reg ->
                    val base = reg.user(m.card.code) ?: RegUser(m.card, nowMs)
                    val user = if (t != null) base.copy(uidHex = hex(tag.id), rolesBits = t.roles, expiresS = t.expiresAtS, revoked = false) else base
                    // the new user was already registered (ALTA) when pressing «Crear y grabar»
                    val kind = when { t != null -> RegEvent.Kind.TARJETA; m.kind == RegEvent.Kind.ALTA -> null; else -> m.kind }
                    reg.upsert(user, kind?.let { RegEvent(nowMs, m.card.code, it, t?.roles ?: 0, t?.expiresAtS ?: 0, "UID ${hex(tag.id)}") })
                }
                runOnUiThread { mode = Mode.Read; overwrite = false; lock = false }
                buildString {
                    append("Tarjeta grabada: ${m.card.name} · ${m.card.code}")
                    if (until != null) append("\nLicencia de la app hasta ${until.format(DAY)} · ${LicenseRole.label(m.roles)}")
                    append(if (r.verified) " · verificada" else " · retírala y léela para verificar")
                    if (r.locked) append(" · bloqueada")
                }
            }
        }
    }

    /** Adds a card read with this phone (issued elsewhere or before the register) to the register. */
    private fun addFound(f: Found) {
        val nowMs = System.currentTimeMillis()
        update { reg ->
            reg.upsert(RegUser(f.card, nowMs, uidHex = f.uidHex, rolesBits = f.token?.roles ?: 0, expiresS = f.token?.expiresAtS ?: 0),
                RegEvent(nowMs, f.card.code, RegEvent.Kind.IMPORTADA, f.token?.roles ?: 0, f.token?.expiresAtS ?: 0, "UID ${f.uidHex}"))
        }
        found = null
        status = "${f.card.name} añadido al registro."
    }

    // ---- key and full backup

    private fun copyPublicKey(k: KeyPair) {
        getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("Clave pública AVO", LicenseCrypto.publicKeyToBase64(k.public)))
        keyMessage = "Clave pública copiada."
    }

    private fun sharePublicKey(k: KeyPair) {
        val text = "Clave pública de licencias AVO (${keyIdHex(k)}):\n${LicenseCrypto.publicKeyToBase64(k.public)}"
        startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text), "Compartir clave pública"))
    }

    /** Full backup: signing key + register (card secrets, licences, history, contacts) in one password file. */
    private fun onExportTarget(uri: Uri?) {
        val pwd = pendingExportPassword; pendingExportPassword = null
        if (uri == null || pwd == null) { pwd?.fill(' '); return }
        val k = key
        val reg = store.load()
        busy = "Cifrando la copia…"
        thread {
            val msg = try {
                val text = IssuerBackup.export(k, reg, pwd)
                contentResolver.openOutputStream(uri, "wt")!!.use { it.write(text.toByteArray(Charsets.US_ASCII)) }
                prefs.edit().putLong(BACKUP_MS, System.currentTimeMillis()).apply()
                runOnUiThread { backedUp = true }
                "Copia completa guardada (clave ${k?.let(::keyIdHex) ?: "—"} + ${reg.users.size} usuarios). Guárdala fuera del móvil y no olvides la contraseña."
            } catch (e: Exception) { "No se pudo guardar la copia: ${e.message}" } finally { pwd.fill(' ') }
            runOnUiThread { busy = null; keyMessage = msg }
        }
    }

    private fun onImportSource(uri: Uri?) {
        if (uri == null) return
        val text = runCatching { contentResolver.openInputStream(uri)!!.use { it.readBytes().toString(Charsets.US_ASCII) } }.getOrNull()
        if (text == null || !(PasswordBox.isBox(text, IssuerBackup.HEADER) || PasswordBox.isBox(text, LicenseKeyBackup.HEADER))) {
            keyMessage = "Ese archivo no es una copia de AVO Tarjetas."; return
        }
        pwdAsk = PwdAsk.Import(text)
    }

    /** Restores a full backup (key + register, merged with what is here) or an old key-only backup. */
    private fun doImport(text: String, pwd: CharArray) {
        busy = "Descifrando la copia…"
        thread {
            val result = runCatching {
                if (PasswordBox.isBox(text, IssuerBackup.HEADER)) IssuerBackup.import(text, pwd)
                else IssuerBackup.Restored(LicenseKeyBackup.import(text, pwd), IssuerRegistry())
            }
            pwd.fill(' ')
            result.onSuccess { r -> if (r.registry.users.isNotEmpty()) update { it.merge(r.registry) } }
            runOnUiThread {
                busy = null
                result.onFailure { keyMessage = "No se pudo importar: ${it.message}" }
                result.onSuccess { r ->
                    val pair = r.key
                    val cur = key
                    keyMessage = "Copia restaurada: ${r.registry.users.size} usuarios en la copia, ${registry.users.size} en el registro."
                    when {
                        pair == null -> Unit
                        cur != null && !cur.public.encoded.contentEquals(pair.public.encoded) -> replaceKey = pair
                        else -> installKey(pair, fromBackup = true)
                    }
                }
            }
        }
    }

    private fun installKey(pair: KeyPair, fromBackup: Boolean) {
        keys.save(pair)
        key = pair
        if (!fromBackup) prefs.edit().putLong(CHANGED_MS, System.currentTimeMillis()).apply()
        backedUp = fromBackup && backedUp
        keyMessage = if (fromBackup) "Clave ${keyIdHex(pair)} importada." else "Clave ${keyIdHex(pair)} generada. Haz ahora la copia completa."
    }

    // ---- licence by file (no card needed)

    private enum class Channel { WHATSAPP, EMAIL, OTRA }

    /** Licence for a user who cannot bring the card: encrypted file for WhatsApp / email (see LicenseFile). */
    private fun sendLicenseFile(u: RegUser, lastDay: LocalDate, roles: Set<LicenseRole>, channel: Channel) {
        val k = key ?: return
        try {
            val uid = u.uidHex.takeIf { it.length in 2..20 && it.length % 2 == 0 }
                ?.chunked(2)?.map { it.toInt(16).toByte() }?.toByteArray() ?: byteArrayOf(0)
            val token = LicenseIssuer.issue(k, uid, u.code, System.currentTimeMillis(), lastDay, zone, roles, remote = true)
            val dir = java.io.File(cacheDir, "licencias").apply { mkdirs(); listFiles()?.forEach { it.delete() } }
            val file = java.io.File(dir, "AVO_licencia_${u.code}_hasta_$lastDay.${LicenseFile.EXTENSION}")
            file.writeText(LicenseFile.encode(token, u.card), Charsets.US_ASCII)
            val nowMs = System.currentTimeMillis()
            update { reg ->
                reg.upsert(u.copy(expiresS = token.expiresAtS, rolesBits = token.roles, revoked = false),
                    RegEvent(nowMs, u.code, RegEvent.Kind.ARCHIVO, token.roles, token.expiresAtS, channel.name.lowercase()))
            }
            val uri = androidx.core.content.FileProvider.getUriForFile(this, "org.avoperformance.cards.files", file)
            val text = "Licencia de AVO Performance Horse para ${u.card.name} (${LicenseRole.label(roles)}) hasta el ${lastDay.format(DAY)}. " +
                "Abre este archivo con la app AVO Performance Horse (o en la app: Inicio → Licencia → Abrir archivo)."
            val send = Intent(Intent.ACTION_SEND).setType("application/octet-stream")
                .putExtra(Intent.EXTRA_STREAM, uri).putExtra(Intent.EXTRA_TEXT, text)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            when (channel) {
                Channel.EMAIL -> {
                    send.putExtra(Intent.EXTRA_SUBJECT, "Licencia AVO Performance Horse · ${u.card.name}")
                    if (u.email.isNotBlank()) send.putExtra(Intent.EXTRA_EMAIL, arrayOf(u.email.trim()))
                    startActivity(Intent.createChooser(send, "Enviar por email"))
                }
                Channel.WHATSAPP -> {
                    val digits = u.phone.filter { it.isDigit() }
                    if (digits.length >= 8) send.putExtra("jid", "$digits@s.whatsapp.net")
                    val pkg = listOf("com.whatsapp", "com.whatsapp.w4b").firstOrNull {
                        runCatching { packageManager.getPackageInfo(it, 0) }.isSuccess
                    }
                    if (pkg != null) startActivity(send.setPackage(pkg)) else startActivity(Intent.createChooser(send, "Enviar licencia"))
                }
                Channel.OTRA -> startActivity(Intent.createChooser(send, "Enviar licencia a ${u.card.name}"))
            }
            status = "Licencia por archivo para ${u.card.name} hasta el ${lastDay.format(DAY)}: solo la puede abrir el móvil que conoce su tarjeta."
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

    // ---- UI

    @Composable
    private fun Screen() {
        var name by remember { mutableStateOf("") }
        var phone by remember { mutableStateOf("") }
        var email by remember { mutableStateOf("") }
        var withLicense by remember { mutableStateOf(true) }
        var until by remember { mutableStateOf<LocalDate?>(null) }
        var newRoles by remember { mutableStateOf(setOf(LicenseRole.JINETE)) }
        var query by remember { mutableStateOf("") }
        var openUser by remember { mutableStateOf<String?>(null) }
        var licenseAsk by remember { mutableStateOf<LicenseAsk?>(null) }
        var confirmGenerate by remember { mutableStateOf(false) }
        val k = key
        val reg = registry
        val nowMs = System.currentTimeMillis()
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
                AvoCard("Clave y copia de seguridad", trailing = {
                    when {
                        k == null -> StatusPill("SIN CLAVE", AvoColors.Bad)
                        !backedUp -> StatusPill("COPIA PENDIENTE", AvoColors.Warn)
                        else -> StatusPill("AL DÍA", AvoColors.Ok)
                    }
                }) {
                    if (k == null) {
                        Note("Para grabar licencias hace falta una clave de firma. Genérala una sola vez, o restaura tu copia si ya la tienes.")
                        Spacer(Modifier.height(8.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Button(onClick = { confirmGenerate = true }, enabled = busy == null) { Text("GENERAR CLAVE", fontWeight = FontWeight.Bold) }
                            OutlinedButton(onClick = { importLauncher.launch(arrayOf("text/plain", "*/*")) }, enabled = busy == null) { Text("Restaurar copia") }
                        }
                    } else {
                        KV("Clave", keyIdHex(k))
                        Text("Clave pública", color = AvoColors.TextDim, fontSize = 12.sp)
                        SelectionContainer { Text(LicenseCrypto.publicKeyToBase64(k.public), color = AvoColors.Silver, fontSize = 11.sp, fontFamily = FontFamily.Monospace) }
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            OutlinedButton(onClick = { copyPublicKey(k) }) { Text("Copiar") }
                            OutlinedButton(onClick = { sharePublicKey(k) }) { Text("Compartir") }
                        }
                        Spacer(Modifier.height(6.dp))
                        KV("Última copia", prefs.getLong(BACKUP_MS, 0).takeIf { it > 0 }?.let { Instant.ofEpochMilli(it).atZone(zone).format(DAY_TIME) } ?: "nunca")
                        Button(onClick = { pwdAsk = PwdAsk.Export }, enabled = busy == null, modifier = Modifier.fillMaxWidth()) {
                            Text("EXPORTAR COPIA COMPLETA", fontWeight = FontWeight.Bold)
                        }
                        TextButton(onClick = { importLauncher.launch(arrayOf("text/plain", "*/*")) }, enabled = busy == null) { Text("Restaurar una copia") }
                        Note("La copia completa guarda la clave y todo el registro (usuarios, claves de sus tarjetas, licencias e historial). " +
                            "Con ella se recupera todo en otro móvil o si hubiera que reinstalar. Hazla después de cada cambio importante.")
                    }
                    busy?.let { Spacer(Modifier.height(6.dp)); Text(it, color = AvoColors.Blue) }
                    keyMessage?.let { Spacer(Modifier.height(6.dp)); Text(it, color = AvoColors.Text) }
                }
            }
            item {
                AvoCard("Nuevo usuario y tarjeta") {
                    OutlinedTextField(value = name, onValueChange = { name = it.take(AvoUserCard.MAX_NAME) },
                        label = { Text("Nombre") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(value = phone, onValueChange = { phone = it.take(30) }, label = { Text("Teléfono (WhatsApp, opcional)") },
                        singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone), modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(value = email, onValueChange = { email = it.take(80) }, label = { Text("Email (opcional)") },
                        singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email), modifier = Modifier.fillMaxWidth())
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(withLicense && k != null, { withLicense = it }, enabled = k != null)
                        Text("Licencia de la app", color = if (k != null) AvoColors.Text else AvoColors.TextDim)
                    }
                    if (withLicense && k != null) {
                        RolePicker(newRoles) { newRoles = it }
                        OutlinedButton(onClick = { pickDate(until) { until = it } }, modifier = Modifier.fillMaxWidth()) {
                            Text(until?.let { "Activa hasta el ${it.format(DAY)}" } ?: "Elegir fecha de activación")
                        }
                    }
                    Spacer(Modifier.height(8.dp))
                    val needsDate = withLicense && k != null && (until == null || newRoles.isEmpty())
                    Button(enabled = name.isNotBlank() && !needsDate, modifier = Modifier.fillMaxWidth(), onClick = {
                        val card = AvoUserCard.generate(name)
                        val lic = if (withLicense && k != null) until else null
                        val ms = System.currentTimeMillis()
                        // registered at once with its contact data; the card itself is written on the next tap
                        update { it.upsert(RegUser(card, ms, phone = phone.trim(), email = email.trim()), RegEvent(ms, card.code, RegEvent.Kind.ALTA)) }
                        mode = Mode.Write(card, RegEvent.Kind.ALTA, lic, newRoles)
                        status = "Acerca una tarjeta en blanco para grabar ${card.name}" + (lic?.let { " con licencia hasta el ${it.format(DAY)}." } ?: ".")
                        name = ""; phone = ""; email = ""
                    }) { Text("CREAR Y GRABAR", fontWeight = FontWeight.Bold) }
                    Note("Usa NTAG215 o NTAG216. La licencia queda ligada al chip: copiada a otra tarjeta no funciona.")
                }
            }
            item {
                val m = mode
                AvoCard("Lector NFC", trailing = {
                    if (m is Mode.Write) StatusPill("GRABANDO", AvoColors.Red) else StatusPill("LECTURA", AvoColors.Blue)
                }) {
                    if (m is Mode.Write) {
                        KV("Tarjeta", "${m.card.name} · ${m.card.code}")
                        KV("Licencia", m.licenseUntil?.let { "hasta el ${it.format(DAY)} · ${LicenseRole.label(m.roles)}" } ?: "sin licencia")
                    }
                    Text(status, color = AvoColors.Text)
                    found?.let { f ->
                        Spacer(Modifier.height(6.dp))
                        Button(onClick = { addFound(f) }) { Text("AÑADIR ${f.card.name.uppercase()} AL REGISTRO", fontWeight = FontWeight.Bold) }
                    }
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
                val active = reg.users.count { !it.revoked && it.licenseActive(nowMs) }
                AvoCard("Registro de usuarios (${reg.users.size})", trailing = { StatusPill("$active ACTIVAS", AvoColors.Ok) }) {
                    OutlinedTextField(query, { query = it }, label = { Text("Buscar: nombre, código, teléfono, rol…") }, singleLine = true,
                        modifier = Modifier.fillMaxWidth())
                    Note("Toca un usuario para renovar su licencia, enviársela por WhatsApp o email sin su tarjeta, ver el historial o editar sus datos.")
                }
            }
            val list = reg.search(query)
            if (list.isEmpty()) item { Note(if (reg.users.isEmpty()) "  Ningún usuario todavía." else "  Sin resultados.") }
            items(list, key = { it.code }) { u ->
                AvoCard(onClick = { openUser = u.code }, trailing = { UserPill(u, nowMs) }) {
                    Text(u.card.name, color = AvoColors.Text, fontWeight = FontWeight.SemiBold)
                    Text(u.code + (u.phone.takeIf { it.isNotBlank() }?.let { " · $it" } ?: ""), color = AvoColors.TextDim, fontSize = 12.sp)
                    if (u.expiresS > 0) Text("Hasta el ${day(u.expiresS)} · ${LicenseRole.label(u.roles).ifBlank { "sin roles" }}",
                        color = if (u.licenseActive(nowMs)) AvoColors.Ok else AvoColors.Bad, fontSize = 12.sp)
                    else Text("Sin licencia de la app", color = AvoColors.TextDim, fontSize = 12.sp)
                }
            }
        }
        openUser?.let { code ->
            reg.user(code)?.let { u ->
                UserDialog(u, onDismiss = { openUser = null }, onLicense = { byFile -> openUser = null; licenseAsk = LicenseAsk(u, byFile) })
            } ?: run { openUser = null }
        }
        licenseAsk?.let { ask ->
            LicenseDialog(ask, onDismiss = { licenseAsk = null }) { day, roles, channel ->
                licenseAsk = null
                if (ask.byFile) sendLicenseFile(ask.user, day, roles, channel)
                else {
                    mode = Mode.Write(ask.user.card, RegEvent.Kind.TARJETA, day, roles)
                    status = "Acerca la tarjeta de ${ask.user.card.name} para grabar la licencia (${LicenseRole.label(roles)}) hasta el ${day.format(DAY)}."
                }
            }
        }
        if (confirmGenerate) ConfirmDialog(title = "Generar clave de licencias",
            text = "Se crea la clave que firma todas las licencias. Haz después la copia completa: si pierdes este móvil sin copia, habrá que regrabar todas las tarjetas y publicar una app nueva.",
            confirm = "Generar", onConfirm = { confirmGenerate = false; installKey(keys.generate(), fromBackup = false) }, onDismiss = { confirmGenerate = false })
        replaceKey?.let { pair ->
            ConfirmDialog(title = "Sustituir la clave", danger = true,
                text = "La copia contiene otra clave (${keyIdHex(pair)}). Si sustituyes la actual (${k?.let(::keyIdHex)}), este móvil dejará de firmar con ella. Las licencias ya emitidas siguen valiendo mientras la app incluya su clave pública.",
                confirm = "Sustituir", onConfirm = { replaceKey = null; installKey(pair, fromBackup = true) }, onDismiss = { replaceKey = null })
        }
        pwdAsk?.let { ask -> PasswordDialog(ask, onDismiss = { pwdAsk = null }, onOk = { pwd ->
            pwdAsk = null
            when (ask) {
                PwdAsk.Export -> { pendingExportPassword = pwd; exportLauncher.launch("AVO_Tarjetas_copia_${LocalDate.now(zone)}.txt") }
                is PwdAsk.Import -> doImport(ask.text, pwd)
            }
        }) }
    }

    @Composable
    private fun UserPill(u: RegUser, nowMs: Long) = when {
        u.revoked -> StatusPill("BAJA", AvoColors.Bad)
        u.licenseActive(nowMs) -> StatusPill("ACTIVA", AvoColors.Ok)
        u.expiresS > 0 -> StatusPill("CADUCADA", AvoColors.Bad)
        else -> StatusPill("SIN LICENCIA", AvoColors.Unknown)
    }

    /** One user of the register: data, licence, history and actions (with or without the card). */
    @Composable
    private fun UserDialog(u: RegUser, onDismiss: () -> Unit, onLicense: (byFile: Boolean) -> Unit) {
        var editing by remember { mutableStateOf(false) }
        var phone by remember(u) { mutableStateOf(u.phone) }
        var email by remember(u) { mutableStateOf(u.email) }
        var notes by remember(u) { mutableStateOf(u.notes) }
        var confirmRevoke by remember { mutableStateOf(false) }
        val k = key
        val nowMs = System.currentTimeMillis()
        AlertDialog(onDismissRequest = onDismiss, containerColor = AvoColors.Surface,
            title = { Text(u.card.name) },
            text = {
                Column(Modifier.heightIn(max = 560.dp).verticalScroll(rememberScrollState())) {
                    KV("Código", u.code)
                    KV("Alta", Instant.ofEpochMilli(u.createdMs).atZone(zone).format(DAY))
                    KV("Licencia", if (u.expiresS > 0) "hasta el ${day(u.expiresS)}" + if (u.licenseActive(nowMs)) "" else " (caducada)" else "sin licencia")
                    if (u.rolesBits != 0) KV("Roles", LicenseRole.label(u.roles))
                    KV("Chip", u.uidHex.ifBlank { "desconocido" })
                    if (u.revoked) Note("Usuario dado de baja.", AvoColors.Bad)
                    Spacer(Modifier.height(6.dp))
                    if (editing) {
                        OutlinedTextField(phone, { phone = it.take(30) }, label = { Text("Teléfono") }, singleLine = true,
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone))
                        OutlinedTextField(email, { email = it.take(80) }, label = { Text("Email") }, singleLine = true,
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email))
                        OutlinedTextField(notes, { notes = it.take(500) }, label = { Text("Notas") })
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Button(onClick = {
                                val ms = System.currentTimeMillis()
                                update { it.upsert(u.copy(phone = phone.trim(), email = email.trim(), notes = notes.trim()), RegEvent(ms, u.code, RegEvent.Kind.EDITADO)) }
                                editing = false
                            }) { Text("Guardar") }
                            TextButton(onClick = { editing = false }) { Text("Cancelar") }
                        }
                    } else {
                        KV("Teléfono", u.phone.ifBlank { "—" })
                        KV("Email", u.email.ifBlank { "—" })
                        if (u.notes.isNotBlank()) Note(u.notes)
                        TextButton(onClick = { editing = true }) { Text("Editar datos") }
                    }
                    HorizontalDivider(color = AvoColors.Line, modifier = Modifier.padding(vertical = 6.dp))
                    if (!u.revoked && k != null) {
                        Button(onClick = { onLicense(true) }, modifier = Modifier.fillMaxWidth()) { Text("ACTIVAR POR ARCHIVO (SIN TARJETA)", fontWeight = FontWeight.Bold) }
                        OutlinedButton(onClick = { onLicense(false) }, modifier = Modifier.fillMaxWidth()) {
                            Text(if (u.expiresS > 0) "Renovar en la tarjeta" else "Grabar licencia en la tarjeta")
                        }
                    }
                    if (!u.revoked) OutlinedButton(onClick = {
                        val keepRoles = u.roles
                        val keep = u.expiresS.takeIf { u.licenseActive(nowMs) && k != null && keepRoles.isNotEmpty() }?.let { LicenseIssuer.lastDayOf(it, zone) }
                        mode = Mode.Write(u.card, RegEvent.Kind.COPIA, keep, keepRoles)
                        status = "Acerca una tarjeta para grabar una copia de ${u.card.name}" + (keep?.let { " (licencia hasta el ${it.format(DAY)})." } ?: ".")
                        onDismiss()
                    }, modifier = Modifier.fillMaxWidth()) { Text("Grabar copia de la tarjeta") }
                    TextButton(onClick = {
                        if (u.revoked) { val ms = System.currentTimeMillis(); update { it.upsert(u.copy(revoked = false), RegEvent(ms, u.code, RegEvent.Kind.REACTIVADA)) } }
                        else confirmRevoke = true
                    }) { Text(if (u.revoked) "Reactivar usuario" else "Dar de baja", color = if (u.revoked) AvoColors.Ok else AvoColors.Bad) }
                    HorizontalDivider(color = AvoColors.Line, modifier = Modifier.padding(vertical = 6.dp))
                    Text("Historial", color = AvoColors.TextDim, fontSize = 12.sp)
                    val hist = registry.history(u.code)
                    if (hist.isEmpty()) Note("Sin movimientos.")
                    hist.take(30).forEach { e ->
                        Text(Instant.ofEpochMilli(e.ms).atZone(zone).format(DAY_TIME) + " · " + e.kind.label +
                            (if (e.expiresS > 0) " · hasta el ${day(e.expiresS)}" else "") +
                            (if (e.rolesBits != 0) " · ${LicenseRole.label(LicenseRole.fromBits(e.rolesBits))}" else "") +
                            (if (e.detail.isNotBlank()) " · ${e.detail}" else ""), color = AvoColors.Text, fontSize = 12.sp)
                    }
                }
            },
            confirmButton = { TextButton(onClick = onDismiss) { Text("Cerrar") } })
        if (confirmRevoke) ConfirmDialog(title = "Dar de baja", text = "¿Dar de baja a ${u.card.name} (${u.code})? Queda en el registro marcado como baja. " +
            "Su licencia actual sigue valiendo hasta su fecha: para cortarla antes, regraba su tarjeta sin licencia.",
            confirm = "Dar de baja", danger = true,
            onConfirm = { val ms = System.currentTimeMillis(); update { it.upsert(u.copy(revoked = true), RegEvent(ms, u.code, RegEvent.Kind.BAJA)) }; confirmRevoke = false },
            onDismiss = { confirmRevoke = false })
    }

    /** Role checkboxes with the functions each role enables (table LicenseFeatures, shared with the app). */
    @Composable
    private fun RolePicker(selected: Set<LicenseRole>, onChange: (Set<LicenseRole>) -> Unit) {
        Text("Roles de la licencia", color = AvoColors.TextDim, fontSize = 12.sp)
        LicenseRole.entries.forEach { r ->
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.clickable { onChange(if (r in selected) selected - r else selected + r) }) {
                Checkbox(r in selected, { on -> onChange(if (on) selected + r else selected - r) })
                Column {
                    Text(r.label, color = AvoColors.Text)
                    Text(r.summary, color = AvoColors.TextDim, fontSize = 11.sp)
                }
            }
        }
        if (selected.isEmpty()) Note("Marca al menos un rol.", AvoColors.Warn)
        else Note("Funciones: " + LicenseFeatures.of(selected).joinToString(", ") { it.label.lowercase() } +
            if (LicenseFeatures.fixedRider(selected)) ". El titular queda como jinete fijo de sus entrenamientos." else
                if (LicenseFeatures.defaultRider(selected)) ". El titular queda como jinete por defecto." else ".")
    }

    /** Licence for a registered user: roles + last day, written on the card or sent as a file. */
    @Composable
    private fun LicenseDialog(ask: LicenseAsk, onDismiss: () -> Unit, onOk: (LocalDate, Set<LicenseRole>, Channel) -> Unit) {
        var roles by remember { mutableStateOf(ask.user.roles.ifEmpty { setOf(LicenseRole.JINETE) }) }
        var day by remember { mutableStateOf<LocalDate?>(null) }
        val ready = day != null && roles.isNotEmpty()
        AlertDialog(onDismissRequest = onDismiss, containerColor = AvoColors.Surface,
            title = { Text((if (ask.byFile) "Activar por archivo · " else "Licencia en tarjeta · ") + ask.user.card.name) },
            text = {
                Column(Modifier.heightIn(max = 560.dp).verticalScroll(rememberScrollState())) {
                    RolePicker(roles) { roles = it }
                    Spacer(Modifier.height(6.dp))
                    OutlinedButton(onClick = { pickDate(day) { day = it } }, modifier = Modifier.fillMaxWidth()) {
                        Text(day?.let { "Activa hasta el ${it.format(DAY)}" } ?: "Elegir fecha de activación")
                    }
                    if (ask.byFile) {
                        Spacer(Modifier.height(8.dp))
                        Note("El archivo va cifrado con la clave de la tarjeta de ${ask.user.card.name}: solo se abre en un móvil donde se haya acercado su tarjeta alguna vez.")
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Button(enabled = ready, onClick = { day?.let { onOk(it, roles, Channel.WHATSAPP) } }) { Text("WhatsApp") }
                            Button(enabled = ready, onClick = { day?.let { onOk(it, roles, Channel.EMAIL) } }) { Text("Email") }
                        }
                        TextButton(enabled = ready, onClick = { day?.let { onOk(it, roles, Channel.OTRA) } }) { Text("Otra app…") }
                    }
                }
            },
            confirmButton = {
                if (!ask.byFile) TextButton(enabled = ready, onClick = { day?.let { onOk(it, roles, Channel.OTRA) } }) { Text("Grabar en la tarjeta") }
            },
            dismissButton = { TextButton(onClick = onDismiss) { Text("Cancelar") } })
    }

    @Composable
    private fun PasswordDialog(ask: PwdAsk, onDismiss: () -> Unit, onOk: (CharArray) -> Unit) {
        var p1 by remember { mutableStateOf("") }
        var p2 by remember { mutableStateOf("") }
        val export = ask is PwdAsk.Export
        val ok = if (export) p1.length >= LicenseKeyBackup.MIN_PASSWORD && p1 == p2 else p1.isNotEmpty()
        AlertDialog(onDismissRequest = onDismiss, containerColor = AvoColors.Surface,
            title = { Text(if (export) "Contraseña de la copia" else "Contraseña de la copia a restaurar") },
            text = {
                Column {
                    if (export) Note("Mínimo ${LicenseKeyBackup.MIN_PASSWORD} caracteres. Puedes usar la misma que en la copia de la clave. Sin ella la copia no sirve.")
                    OutlinedTextField(p1, { p1 = it }, label = { Text("Contraseña") }, singleLine = true,
                        visualTransformation = PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password))
                    if (export) OutlinedTextField(p2, { p2 = it }, label = { Text("Repetir contraseña") }, singleLine = true,
                        visualTransformation = PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password))
                }
            },
            confirmButton = { TextButton(enabled = ok, onClick = { onOk(p1.toCharArray()); p1 = ""; p2 = "" }) { Text("Aceptar") } },
            dismissButton = { TextButton(onClick = onDismiss) { Text("Cancelar") } })
    }

    private companion object {
        const val BACKUP_MS = "full_backup_ms"
        const val CHANGED_MS = "registry_changed_ms"
    }
}
