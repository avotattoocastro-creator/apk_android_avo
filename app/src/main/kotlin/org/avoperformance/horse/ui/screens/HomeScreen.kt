package org.avoperformance.horse.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.delay
import org.avoperformance.horse.AppContainer
import org.avoperformance.horse.ble.LinkState
import org.avoperformance.horse.core.ntrip.NtripState
import org.avoperformance.horse.core.telemetry.RtkDeriver
import org.avoperformance.horse.core.telemetry.RtkState
import org.avoperformance.horse.service.AvoLinkService
import org.avoperformance.horse.ui.components.AvoCard
import org.avoperformance.horse.ui.components.BigValue
import org.avoperformance.horse.ui.components.Fmt
import org.avoperformance.horse.ui.components.KV
import org.avoperformance.horse.ui.components.Note
import org.avoperformance.horse.ui.components.StatusPill
import org.avoperformance.horse.ui.theme.AvoColors
import java.util.Locale

/** Clock that recomposes every 500 ms, so ages and staleness are always current. */
@Composable
fun rememberNow(): Long {
    val now = remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { delay(500); now.longValue = System.currentTimeMillis() } }
    return now.longValue
}

@Composable
fun HomeScreen(c: AppContainer, go: (String) -> Unit) {
    val link by c.watch.state.collectAsStateWithLifecycle()
    val detail by c.watch.detail.collectAsStateWithLifecycle()
    val info by c.watch.info.collectAsStateWithLifecycle()
    val tel by c.watch.telemetry.collectAsStateWithLifecycle()
    val ntripState by c.ntrip.state.collectAsStateWithLifecycle()
    val ntripStats by c.ntrip.stats.collectAsStateWithLifecycle()
    val path by c.ntrip.path.collectAsStateWithLifecycle()
    val now = rememberNow()
    val age = tel?.let { (now - it.receivedMs).coerceAtLeast(0L) } ?: Long.MAX_VALUE
    val fresh = age <= RtkDeriver.TELEMETRY_STALE_MS
    val t = if (fresh) tel?.t else null
    val rtk = RtkDeriver.derive(tel?.t, age)

    LazyColumn(Modifier.fillMaxSize()) {
        item { AvoCard("MAREAS · Regatón", onClick = { go("mareas") }) { Text("Ver nivel del mar previsto, pleamares y bajamares aproximadas, oleaje y temperatura del agua.") } }
        item {
            AvoCard("LIVE · Estado del sistema") {
                val states = listOf(
                    Triple("BLE", if (link == LinkState.LISTO) "ON" else "OFF", if (link == LinkState.LISTO) AvoColors.Ok else AvoColors.Bad),
                    Triple("ESP", if (fresh && t?.backLink == true) "LINK" else "—", if (fresh && t?.backLink == true) AvoColors.Ok else AvoColors.Unknown),
                    Triple("RTK", rtk.state.texto.take(8), AvoColors.rtk(rtk.state)),
                    Triple("REC", t?.rec?.texto?.take(8) ?: "—", if (fresh && t?.rec?.texto?.contains("grab", true) == true) AvoColors.Ok else AvoColors.Unknown),
                )
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    states.forEach { (label, value, color) ->
                        Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(label, color = AvoColors.TextDim)
                            StatusPill(value, color)
                        }
                    }
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                    BigValue(t?.let { Fmt.kmh(it.speedMmS / 1000.0) }, "km/h", "Velocidad")
                    BigValue(rtk.hAccM?.let { fmtAcc(it) }, "", "Precisión")
                    BigValue(rtk.satellites?.toString(), "", "Satélites")
                }
            }
        }
        item {
            AvoCard("Chaleco", onClick = { go("bluetooth") }) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(c.settings.authorizedWatchName ?: "Sin reloj", color = AvoColors.Text)
                    val col = when (link) { LinkState.LISTO -> AvoColors.Ok; LinkState.LISTO_SIN_AUTH -> AvoColors.Warn; LinkState.ERROR -> AvoColors.Bad
                        LinkState.NECESITA_AUTORIZACION, LinkState.ESPERANDO_BOOT -> AvoColors.Warn; else -> AvoColors.Unknown }
                    StatusPill(link.texto, col)
                }
                detail?.let { Note(it, AvoColors.Warn) }
                KV("Firmware", info?.firmware)
                KV("Batería", t?.batteryPct?.let { "$it %" } ?: t?.v2?.batteryMv?.takeIf { it > 0 }?.let { "$it mV" })
                KV("Tarjeta SD", t?.v2?.let { if (it.sdMounted) "montada" else "NO montada" }, if (t?.v2?.sdMounted == false) AvoColors.Bad else AvoColors.Text)
                KV("Enlace con la espalda", t?.let { if (it.backLink) "conectado" else "sin enlace" }, if (t?.backLink == false) AvoColors.Bad else AvoColors.Text)
                KV("Cincha (IMU)", t?.let { if (it.girth) "conectada" else "sin datos" }, if (t?.girth == false) AvoColors.Warn else AvoColors.Text)
                if (link == LinkState.SIN_RELOJ || link == LinkState.DESCONECTADO) {
                    Spacer(Modifier.height(8.dp))
                    Button(onClick = { if (link == LinkState.SIN_RELOJ) go("bluetooth") else AvoLinkService.start(c.app) }) {
                        Text(if (link == LinkState.SIN_RELOJ) "Buscar chaleco" else "Conectar")
                    }
                }
            }
        }
        item {
            AvoCard("Gestor de dispositivos y firmware") {
                Note("Actualización OTA BLE experimental solo para firmware V3.5.4 SHA-256 autorizado.")
                OutlinedButton(onClick = { go("dispositivos") }) { Text("Ver dispositivos y OTA") }
            }
        }
        item {
            AvoCard("Posicionamiento (receptor)") {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("Estado RTK", color = AvoColors.TextDim)
                    StatusPill(rtk.state.texto, AvoColors.rtk(rtk.state))
                }
                KV("Satélites", rtk.satellites?.toString())
                KV("Precisión horizontal", rtk.hAccM?.let { fmtAcc(it) })
                KV("Precisión vertical", rtk.vAccM?.let { fmtAcc(it) })
                KV("Edad de la corrección", rtk.correctionAgeMaxMs?.let { if (it == Long.MAX_VALUE) "> 120 s" else "≤ ${it / 1000} s" })
                KV("Último dato GNSS", rtk.gnssAgeMs?.let { "hace ${it} ms" })
                KV("Telemetría del reloj", tel?.let { if (fresh) "hace ${age} ms" else "sin datos recientes" }, if (tel != null && !fresh) AvoColors.Warn else AvoColors.Text)
                if (rtk.state == RtkState.DESCONOCIDO) Note("El estado RTK solo se muestra con datos reales del receptor.")
            }
        }
        item {
            AvoCard("Sesión") {
                KV("Sesión", t?.session?.texto)
                KV("Geocerca", t?.geofence?.texto)
                KV("Grabación", t?.rec?.texto)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                    BigValue(t?.let { Fmt.m(it.distanceCm / 100.0, 0) }, "m", "Distancia")
                    BigValue(t?.let { Fmt.kmh(it.speedMmS / 1000.0) }, "km/h", "Velocidad")
                    BigValue(t?.let { Fmt.duration(it.activeMs) }, "", "Tiempo activo")
                }
                if ((t?.droppedRecords ?: 0L) > 0L) KV("Registros descartados", t!!.droppedRecords.toString(), AvoColors.Bad)
                if (t?.inhibited == true) Note("Grabación inhibida por el reloj (batería o SD).", AvoColors.Bad)
            }
        }
        item {
            AvoCard("Correcciones NTRIP", onClick = { go("ntrip") }) {
                val col = when (ntripState) { is NtripState.Streaming -> AvoColors.Ok; is NtripState.Failed -> AvoColors.Bad; is NtripState.Stopped -> AvoColors.Unknown; else -> AvoColors.Warn }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(c.settings.ntrip.value.mountpoint.ifBlank { "Sin configurar" }, color = AvoColors.Text)
                    StatusPill(if (ntripState is NtripState.Streaming) "Recibiendo" else ntripState.texto.take(28), col)
                }
                KV("Recibido del caster", Fmt.bytes(ntripStats.bytesReceived.takeIf { it > 0 }))
                KV("Caudal", ntripStats.bytesPerSecond.takeIf { it > 0 }?.let { String.format(Locale.US, "%.0f B/s", it) })
                KV("Enviado al reloj", Fmt.bytes(path.sentBytes.takeIf { it > 0 }))
                KV("Tramas RTCM válidas / erróneas", if (path.framer.framesOk + path.framer.framesBadCrc > 0) "${path.framer.framesOk} / ${path.framer.framesBadCrc}" else null)
                KV("Reenviado a la espalda", t?.v2?.let { Fmt.bytes(it.rtcmToBackBytes) })
                KV("Usado por el receptor", t?.v2?.let { "${it.rtcmUsedByReceiver} mensajes" })
                val lost = path.droppedStale + path.droppedOverflow + path.watchDropped
                if (lost > 0) KV("Descartado (antiguo / cola / reloj)", "${path.droppedStale} / ${path.droppedOverflow} / ${path.watchDropped} B", AvoColors.Warn)
            }
        }
    }
}

fun fmtAcc(m: Double): String = if (m < 1) String.format(Locale.forLanguageTag("es-ES"), "%.1f cm", m * 100) else String.format(Locale.forLanguageTag("es-ES"), "%.2f m", m)

