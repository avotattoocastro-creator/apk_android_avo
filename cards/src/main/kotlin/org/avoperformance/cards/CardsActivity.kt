package org.avoperformance.cards

import android.nfc.NfcAdapter
import android.os.Bundle
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.Image
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.sp
import org.avoperformance.horse.core.identity.AvoUserCard
import org.avoperformance.horse.ui.components.AvoCard
import org.avoperformance.horse.ui.components.ConfirmDialog
import org.avoperformance.horse.ui.components.KV
import org.avoperformance.horse.ui.components.Note
import org.avoperformance.horse.ui.components.StatusPill
import org.avoperformance.horse.ui.theme.AvoColors
import org.avoperformance.horse.ui.theme.AvoTheme
import java.text.DateFormat
import java.util.Date

/** What the next tapped card is used for. */
private sealed interface Mode {
    data object Read : Mode
    data class Write(val card: AvoUserCard, val isNew: Boolean) : Mode
}

class CardsActivity : ComponentActivity() {
    private val adapter by lazy { NfcAdapter.getDefaultAdapter(this) }
    private lateinit var store: IssuedCards
    private var mode by mutableStateOf<Mode>(Mode.Read)
    private var overwrite by mutableStateOf(false)
    private var lock by mutableStateOf(false)
    private var status by mutableStateOf("Acerca una tarjeta para leerla, o crea una nueva.")
    private var issued by mutableStateOf<List<Issued>>(emptyList())
    private var lastTap = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        store = IssuedCards(this)
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

    private fun onTag(tag: android.nfc.Tag) {
        val now = SystemClock.elapsedRealtime()
        if (now - lastTap < 1500) return
        lastTap = now
        val m = mode
        val text = try {
            when (m) {
                Mode.Read -> {
                    val uri = CardWriter.readUri(tag)
                    if (uri == null) "Tarjeta vacía o sin formato AVO."
                    else {
                        val desc = CardWriter.describe(uri)
                        val known = if (AvoUserCard.isUserUri(uri)) runCatching { store.byCode(AvoUserCard.parse(uri).code) }.getOrNull() else null
                        "Leída: $desc" + when {
                            known == null && AvoUserCard.isUserUri(uri) -> " · no emitida desde este móvil"
                            known?.revoked == true -> " · DADA DE BAJA"
                            else -> ""
                        }
                    }
                }
                is Mode.Write -> when (val r = CardWriter.write(tag, m.card, overwrite, lock)) {
                    is CardWriter.Outcome.Refused -> r.reason
                    is CardWriter.Outcome.Written -> {
                        if (m.isNew) store.save(Issued(m.card, System.currentTimeMillis(), revoked = false))
                        runOnUiThread { issued = store.all(); mode = Mode.Read; overwrite = false; lock = false }
                        buildString {
                            append("Tarjeta grabada: ${m.card.name} · ${m.card.code}")
                            append(if (r.verified) " · verificada" else " · retírala y léela para verificar")
                            if (r.locked) append(" · bloqueada")
                        }
                    }
                }
            }
        } catch (e: Exception) {
            "Error NFC: ${e.message ?: e.javaClass.simpleName}. Mantén la tarjeta quieta y vuelve a acercarla."
        }
        runOnUiThread { status = text }
    }

    @Composable
    private fun Screen() {
        var name by remember { mutableStateOf("") }
        var confirmRevoke by remember { mutableStateOf<Issued?>(null) }
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp)) {
            item {
                // Brand header, same as the main app and AVO Update
                Box {
                    Image(painterResource(R.drawable.avo_brand_hero), contentDescription = "AVO Performance Horse",
                        contentScale = ContentScale.FillWidth, modifier = Modifier.fillMaxWidth().heightIn(max = 220.dp))
                }
                Row(Modifier.padding(start = 16.dp, top = 10.dp, bottom = 6.dp), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                    Text("AVO", color = AvoColors.Red, fontSize = 24.sp, fontWeight = FontWeight.Black, letterSpacing = 3.sp)
                    Text("  TARJETAS", color = AvoColors.Text, fontSize = 17.sp, fontWeight = FontWeight.Black, letterSpacing = 2.sp)
                }
            }
            item {
                AvoCard("Nueva tarjeta personal") {
                    OutlinedTextField(value = name, onValueChange = { name = it.take(AvoUserCard.MAX_NAME) },
                        label = { Text("Nombre") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                    Spacer(Modifier.height(8.dp))
                    Button(enabled = name.isNotBlank(), modifier = Modifier.fillMaxWidth(), onClick = {
                        val card = AvoUserCard.generate(name)
                        mode = Mode.Write(card, isNew = true)
                        status = "Acerca una tarjeta en blanco para grabar ${card.name}."
                    }) { Text("CREAR Y GRABAR", fontWeight = FontWeight.Bold) }
                    Spacer(Modifier.height(6.dp))
                    Note("Usa NTAG215 o NTAG216 (las NTAG213 se quedan cortas).")
                }
            }
            item {
                val m = mode
                AvoCard("Lector NFC", trailing = {
                    if (m is Mode.Write) StatusPill("GRABANDO", AvoColors.Red) else StatusPill("LECTURA", AvoColors.Blue)
                }) {
                    if (m is Mode.Write) KV("Tarjeta", "${m.card.name} · ${m.card.code}")
                    Text(status, color = AvoColors.Text)
                    if (m is Mode.Write) {
                        Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                            Checkbox(overwrite, { overwrite = it }); Text("Sobrescribir si ya tiene datos AVO", color = AvoColors.Text)
                        }
                        Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                            Checkbox(lock, { lock = it }); Text("Bloquear tarjeta (irreversible)", color = if (lock) AvoColors.Warn else AvoColors.Text)
                        }
                        OutlinedButton(onClick = { mode = Mode.Read; status = "Cancelado." }) { Text("Cancelar") }
                    }
                }
            }
            item {
                AvoCard("Tarjetas emitidas (${issued.size})") {
                    if (issued.isEmpty()) Note("Ninguna todavía.")
                    issued.forEachIndexed { idx, i ->
                        if (idx > 0) HorizontalDivider(color = AvoColors.Line, modifier = Modifier.padding(vertical = 6.dp))
                        Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(i.card.name, color = AvoColors.Text, fontWeight = FontWeight.SemiBold)
                                Text("${i.card.code} · ${DateFormat.getDateInstance(DateFormat.SHORT).format(Date(i.createdMs))}", color = AvoColors.TextDim, fontSize = 12.sp)
                            }
                            if (i.revoked) StatusPill("BAJA", AvoColors.Bad)
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            if (!i.revoked) TextButton(onClick = {
                                mode = Mode.Write(i.card, isNew = false)
                                status = "Acerca una tarjeta para grabar una copia de ${i.card.name}."
                            }) { Text("Grabar copia") }
                            TextButton(onClick = { if (i.revoked) { store.save(i.copy(revoked = false)); issued = store.all() } else confirmRevoke = i }) {
                                Text(if (i.revoked) "Reactivar" else "Dar de baja", color = if (i.revoked) AvoColors.Ok else AvoColors.Bad)
                            }
                        }
                    }
                    Spacer(Modifier.height(6.dp))
                    Note("La baja de momento queda registrada solo en este móvil.")
                }
            }
        }
        confirmRevoke?.let { i ->
            ConfirmDialog(title = "Dar de baja", text = "¿Dar de baja la tarjeta de ${i.card.name} (${i.card.code})? Úsalo si se ha perdido.",
                confirm = "Dar de baja", danger = true,
                onConfirm = { store.save(i.copy(revoked = true)); issued = store.all(); confirmRevoke = null },
                onDismiss = { confirmRevoke = null })
        }
    }
}
