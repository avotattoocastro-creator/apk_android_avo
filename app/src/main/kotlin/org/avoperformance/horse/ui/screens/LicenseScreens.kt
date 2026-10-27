package org.avoperformance.horse.ui.screens

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.avoperformance.horse.AppContainer
import org.avoperformance.horse.core.license.LicenseStatus
import org.avoperformance.horse.license.LicenseManager
import org.avoperformance.horse.ui.components.AvoCard
import org.avoperformance.horse.ui.components.KV
import org.avoperformance.horse.ui.components.Note
import org.avoperformance.horse.ui.components.StatusPill
import org.avoperformance.horse.ui.theme.AvoColors

/** Routes usable without an active licence: consultation of the data already collected. */
val LICENSE_FREE_ROUTES = setOf("inicio", "historial", "caballos", "detalle/{id}", "comparar/{a}/{b}",
    "caballo/{code}", "jinete/{code}", "acerca", "licencia")

@Composable
private fun Banner(title: String, text: String, color: Color, action: String?, onAction: () -> Unit) {
    val shape = RoundedCornerShape(16.dp)
    Column(Modifier.padding(horizontal = 12.dp, vertical = 6.dp).fillMaxWidth().clip(shape)
        .background(Brushes.banner(color)).border(1.dp, color.copy(alpha = 0.7f), shape).padding(16.dp)) {
        Text(title, color = color, fontWeight = FontWeight.Black, fontSize = 15.sp, letterSpacing = 1.2.sp)
        Spacer(Modifier.height(6.dp))
        Text(text, color = AvoColors.Text, fontSize = 14.sp)
        if (action != null) {
            Spacer(Modifier.height(10.dp))
            Button(onClick = onAction, colors = ButtonDefaults.buttonColors(containerColor = color, contentColor = Color.Black)) {
                Text(action, fontWeight = FontWeight.Bold)
            }
        }
    }
}

private object Brushes {
    fun banner(c: Color) = androidx.compose.ui.graphics.Brush.verticalGradient(listOf(c.copy(alpha = 0.22f), Color(0xFF0D0D11)))
}

/** Notice at the top of Inicio: licence about to expire, expired / missing, or phone clock moved back. */
@Composable
fun LicenseNotice(c: AppContainer, go: (String) -> Unit) {
    val st by c.license.status.collectAsStateWithLifecycle()
    val behind by c.license.clockBehind.collectAsStateWithLifecycle()
    when (val s = st) {
        is LicenseStatus.Active -> if (s.expiringSoon) Banner("TU LICENCIA CADUCA PRONTO",
            "Tu licencia AVO Performance Horse es válida hasta el ${LicenseManager.day(s.token.expiresAtS)} " +
                "(${if (s.daysLeft == 1L) "último día" else "quedan ${s.daysLeft} días"}). Renuévala para seguir grabando sin interrupciones.",
            AvoColors.Warn, "Ver licencia") { go("licencia") }
        is LicenseStatus.Expired -> Banner("SISTEMA SIN LICENCIA ACTIVA",
            "Tu licencia caducó el ${LicenseManager.day(s.token.expiresAtS)}. Puedes seguir consultando todos tus entrenamientos " +
                "guardados. Para volver a conectar el chaleco, grabar y usar todas las funciones, renueva tu licencia AVO y " +
                "acerca tu tarjeta al móvil o abre el archivo de licencia que te enviemos.",
            AvoColors.Red, "Reactivar licencia") { go("licencia") }
        LicenseStatus.None -> Banner("ACTIVA TU SISTEMA AVO",
            "Esta app necesita una licencia AVO Performance Horse. Acerca tu tarjeta AVO personal al móvil para activarla. " +
                "Mientras tanto puedes consultar los entrenamientos guardados.",
            AvoColors.Red, "Activar licencia") { go("licencia") }
        is LicenseStatus.Invalid -> Banner("LICENCIA NO VÁLIDA", s.reason + ". Acerca tu tarjeta AVO para activarla de nuevo.",
            AvoColors.Red, "Activar licencia") { go("licencia") }
        LicenseStatus.NotEnforced -> Unit
    }
    if (behind && st !is LicenseStatus.NotEnforced) Banner("HORA DEL MÓVIL ATRASADA",
        "La fecha del teléfono es anterior a la última hora conocida. Pon la fecha y hora automáticas en los ajustes de Android.",
        AvoColors.Warn, null) {}
}

/** Inicio without an active licence: only the notice and the way to the saved data. */
@Composable
fun RestrictedHome(c: AppContainer, go: (String) -> Unit) {
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(vertical = 6.dp)) {
        item { LicenseNotice(c, go) }
        item {
            AvoCard("Modo consulta") {
                Note("Disponible: entrenamientos guardados, análisis, comparativas y la cuadra. " +
                    "Bloqueado hasta reactivar: conexión con el chaleco, espalda y cincha, grabación, descargas, NTRIP, mareas, " +
                    "compartir y ajustes.")
                Spacer(Modifier.height(10.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = { go("historial") }) { Text("VER ENTRENAMIENTOS", fontWeight = FontWeight.Bold) }
                    OutlinedButton(onClick = { go("caballos") }) { Text("Cuadra") }
                }
            }
        }
    }
}

/** Replaces a blocked screen in consultation mode. */
@Composable
fun LockedFeature(go: (String) -> Unit) {
    Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
        Text("🔒", fontSize = 44.sp)
        Spacer(Modifier.height(12.dp))
        Text("FUNCIÓN BLOQUEADA", color = AvoColors.Red, fontWeight = FontWeight.Black, fontSize = 18.sp, letterSpacing = 1.5.sp)
        Spacer(Modifier.height(8.dp))
        Text("Esta función está disponible con una licencia AVO Performance Horse activa. Tus entrenamientos guardados " +
            "siguen disponibles para consulta.", color = AvoColors.Text, textAlign = TextAlign.Center)
        Spacer(Modifier.height(16.dp))
        Button(onClick = { go("licencia") }) { Text("REACTIVAR LICENCIA", fontWeight = FontWeight.Bold) }
        OutlinedButton(onClick = { go("historial") }, modifier = Modifier.padding(top = 8.dp)) { Text("Ver entrenamientos") }
    }
}

/** Licence details, activation by card or by file. Always reachable, even with the licence expired. */
@Composable
fun LicenseScreen(c: AppContainer) {
    val st by c.license.status.collectAsStateWithLifecycle()
    val msg by c.license.message.collectAsStateWithLifecycle()
    val card by c.identity.card.collectAsStateWithLifecycle()
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) { c.license.refresh() }
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) scope.launch {
            val text = withContext(Dispatchers.IO) {
                runCatching { ctx.contentResolver.openInputStream(uri)!!.use { it.readBytes().take(64 * 1024).toByteArray().toString(Charsets.US_ASCII) } }.getOrNull()
            }
            if (text == null) return@launch
            withContext(Dispatchers.Default) { c.license.activateFromFile(text, c.identity.card.value) }
        }
    }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(vertical = 6.dp)) {
        item {
            val (label, color) = when (st) {
                is LicenseStatus.Active -> (if ((st as LicenseStatus.Active).expiringSoon) "CADUCA PRONTO" else "ACTIVA") to
                    (if ((st as LicenseStatus.Active).expiringSoon) AvoColors.Warn else AvoColors.Ok)
                is LicenseStatus.Expired -> "CADUCADA" to AvoColors.Bad
                LicenseStatus.None -> "SIN LICENCIA" to AvoColors.Bad
                is LicenseStatus.Invalid -> "NO VÁLIDA" to AvoColors.Bad
                LicenseStatus.NotEnforced -> "NO REQUERIDA" to AvoColors.Unknown
            }
            AvoCard("Licencia AVO Performance Horse", trailing = { StatusPill(label, color) }) {
                KV("Estado", c.license.describe(st))
                when (val s = st) {
                    is LicenseStatus.Active -> { KV("Usuario", "${s.userName.ifBlank { "—" }} · ${s.token.userCode}"); KV("Días restantes", s.daysLeft.toString()) }
                    is LicenseStatus.Expired -> KV("Usuario", "${s.userName.ifBlank { "—" }} · ${s.token.userCode}")
                    else -> Unit
                }
                card?.let { KV("Tarjeta de este móvil", "${it.name} · ${it.code}") }
                if (st is LicenseStatus.NotEnforced) Note("Esta compilación no lleva claves de licencia (versión de desarrollo): la app funciona sin restricciones.")
                msg?.let { Spacer(Modifier.height(8.dp)); Text(it, color = AvoColors.Text, fontWeight = FontWeight.SemiBold) }
            }
        }
        if (c.license.enforced) {
            item {
                AvoCard("Activar o renovar con la tarjeta") {
                    Note("Acerca tu tarjeta AVO personal a la parte trasera del móvil con esta app abierta. La licencia queda guardada " +
                        "en el móvil hasta la fecha grabada en la tarjeta.")
                }
            }
            item {
                AvoCard("Activar con un archivo de licencia") {
                    Note("Si no puedes llevar tu tarjeta para renovarla, AVO te puede enviar un archivo de licencia por WhatsApp o email. " +
                        "Solo funciona en el móvil que ya conoce tu tarjeta.")
                    Spacer(Modifier.height(8.dp))
                    Button(onClick = { pick.launch(arrayOf("*/*")) }) { Text("ABRIR ARCHIVO DE LICENCIA", fontWeight = FontWeight.Bold) }
                    if (card == null) Note("Este móvil aún no conoce tu tarjeta: acércala una vez (aunque esté caducada) y después abre el archivo.", AvoColors.Warn)
                }
            }
        }
    }
}
