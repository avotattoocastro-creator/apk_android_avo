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
import org.avoperformance.horse.core.identity.AvoUserCard
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
        setContent { MaterialTheme(colorScheme = darkColorScheme()) { Surface(Modifier.fillMaxSize()) { Screen() } } }
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
        LazyColumn(Modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item { Text("AVO Tarjetas", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold) }
            item {
                Card { Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Nueva tarjeta personal", fontWeight = FontWeight.SemiBold)
                    OutlinedTextField(value = name, onValueChange = { name = it.take(AvoUserCard.MAX_NAME) },
                        label = { Text("Nombre") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                    Button(enabled = name.isNotBlank(), onClick = {
                        val card = AvoUserCard.generate(name)
                        mode = Mode.Write(card, isNew = true)
                        status = "Acerca una tarjeta en blanco para grabar ${card.name} · ${card.code}"
                    }) { Text("Crear y grabar") }
                    Text("Usa NTAG215 o NTAG216 (las NTAG213 se quedan cortas).", style = MaterialTheme.typography.bodySmall)
                } }
            }
            item {
                Card { Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    val m = mode
                    Text(if (m is Mode.Write) "Grabando: ${m.card.name} · ${m.card.code}" else "Modo lectura", fontWeight = FontWeight.SemiBold)
                    Text(status)
                    if (m is Mode.Write) {
                        Row { Checkbox(overwrite, { overwrite = it }); Text("Sobrescribir si ya tiene datos AVO", Modifier.padding(top = 12.dp)) }
                        Row { Checkbox(lock, { lock = it }); Text("Bloquear tarjeta (IRREVERSIBLE: no se podrá volver a grabar)", Modifier.padding(top = 12.dp)) }
                        OutlinedButton(onClick = { mode = Mode.Read; status = "Cancelado." }) { Text("Cancelar") }
                    }
                } }
            }
            item { Text("Tarjetas emitidas (${issued.size})", fontWeight = FontWeight.SemiBold) }
            if (issued.isEmpty()) item { Text("Ninguna todavía.", style = MaterialTheme.typography.bodySmall) }
            items(issued, key = { it.card.code }) { i ->
                Card { Column(Modifier.padding(12.dp)) {
                    Text("${i.card.name} · ${i.card.code}" + if (i.revoked) " · BAJA" else "", fontWeight = FontWeight.SemiBold)
                    Text("Emitida ${DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(i.createdMs))}", style = MaterialTheme.typography.bodySmall)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        if (!i.revoked) TextButton(onClick = {
                            mode = Mode.Write(i.card, isNew = false)
                            status = "Acerca una tarjeta para grabar una copia de ${i.card.name}"
                        }) { Text("Grabar copia") }
                        TextButton(onClick = { if (i.revoked) { store.save(i.copy(revoked = false)); issued = store.all() } else confirmRevoke = i }) {
                            Text(if (i.revoked) "Reactivar" else "Dar de baja")
                        }
                    }
                } }
            }
            item {
                Text("La baja impedirá el envío y la recepción con esa tarjeta cuando el servicio de envío entre apps esté activo. Hoy solo queda registrada en este móvil.",
                    style = MaterialTheme.typography.bodySmall)
            }
        }
        confirmRevoke?.let { i ->
            AlertDialog(onDismissRequest = { confirmRevoke = null },
                title = { Text("Dar de baja") },
                text = { Text("¿Dar de baja la tarjeta de ${i.card.name} (${i.card.code})? Úsalo si se ha perdido.") },
                confirmButton = { TextButton(onClick = { store.save(i.copy(revoked = true)); issued = store.all(); confirmRevoke = null }) { Text("Dar de baja") } },
                dismissButton = { TextButton(onClick = { confirmRevoke = null }) { Text("Cancelar") } })
        }
    }
}
