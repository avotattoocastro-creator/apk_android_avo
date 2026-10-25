package org.avoperformance.horse.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import org.avoperformance.horse.ui.components.MetricGrid
import org.avoperformance.horse.ui.components.MetricTile
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.lazy.LazyColumn
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
import org.avoperformance.horse.service.AvoLinkService
import org.avoperformance.horse.ui.components.AvoCard
import org.avoperformance.horse.ui.components.Fmt
import org.avoperformance.horse.ui.components.KV
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
private fun StatusChip(label: String, value: String, color: androidx.compose.ui.graphics.Color, modifier: Modifier = Modifier, onClick: (() -> Unit)? = null) {
    val shape = RoundedCornerShape(12.dp)
    Column(
        modifier.clip(shape).background(AvoColors.Surface2).border(1.dp, color.copy(alpha = 0.45f), shape)
            .let { if (onClick != null) it.clickable { onClick() } else it }.padding(horizontal = 10.dp, vertical = 8.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(8.dp).background(color, CircleShape))
            Spacer(Modifier.width(6.dp))
            Text(label.uppercase(), color = AvoColors.TextDim, fontSize = 10.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.8.sp)
        }
        Text(value, color = color, fontSize = 14.sp, fontWeight = FontWeight.Bold, maxLines = 1)
    }
}

/**
 * Back unit: it only reports its battery voltage, so the % is estimated with the usual 1-cell Li-ion
 * discharge curve at low load (interpolated). Approximate: ±10 % depending on load and temperature.
 */
private val LIION = intArrayOf(3300, 3500, 3600, 3700, 3750, 3800, 3850, 3900, 4000, 4100, 4200)
private val LIION_PCT = intArrayOf(0, 5, 10, 20, 30, 40, 50, 60, 75, 90, 100)
private fun liionPct(mv: Int): Int {
    if (mv <= LIION[0]) return 0
    if (mv >= LIION.last()) return 100
    val i = LIION.indexOfFirst { it >= mv }
    val f = (mv - LIION[i - 1]).toFloat() / (LIION[i] - LIION[i - 1])
    return (LIION_PCT[i - 1] + f * (LIION_PCT[i] - LIION_PCT[i - 1])).toInt()
}
private fun battColor(pct: Int) = if (pct > 20) AvoColors.Ok else AvoColors.Low

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
    val linkColor = when (link) { LinkState.LISTO -> AvoColors.Ok; LinkState.LISTO_SIN_AUTH -> AvoColors.Warn; LinkState.ERROR -> AvoColors.Bad
        LinkState.NECESITA_AUTORIZACION, LinkState.ESPERANDO_BOOT -> AvoColors.Warn; else -> AvoColors.Unknown }
    val ntripColor = when (ntripState) { is NtripState.Streaming -> AvoColors.Ok; is NtripState.Failed -> AvoColors.Bad; is NtripState.Stopped -> AvoColors.Unknown; else -> AvoColors.Warn }
    val recording = t?.rec?.texto?.contains("grab", true) == true

    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(vertical = 6.dp)) {
        item {
            AvoCard(c.settings.authorizedWatchName ?: "Sin chaleco vinculado", onClick = { go("bluetooth") }, trailing = { StatusPill(link.texto, linkColor) }) {
                detail?.let { Text(it, color = AvoColors.Warn, fontSize = 13.sp) ; Spacer(Modifier.height(6.dp)) }
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    // Row 1: the three units with their battery. Red = off / no link, orange = low battery, green = OK.
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        val pct = t?.batteryPct ?: t?.v2?.batteryMv?.takeIf { it > 0 }?.let { liionPct(it) }
                        StatusChip("Pecho", pct?.let { "$it %" } ?: if (t == null) "Apagado" else "— %",
                            when { t == null -> AvoColors.Bad; pct == null -> AvoColors.Unknown; else -> battColor(pct) }, Modifier.weight(1f))
                        val backPct = t?.v2?.takeIf { it.backStatusValid }?.backBatteryMv?.takeIf { it > 0 }?.let { liionPct(it) }
                        StatusChip("Espalda", when { t == null || !t.backLink -> "Apagada"; backPct != null -> "$backPct %"; else -> "— %" },
                            when { t == null || !t.backLink -> AvoColors.Bad; backPct == null -> AvoColors.Unknown; else -> battColor(backPct) }, Modifier.weight(1f))
                        // The girth does not report its battery yet (not in the telemetry): only its link is shown.
                        StatusChip("Cincha", if (t != null && t.girth) "— %" else "Apagada",
                            if (t != null && t.girth) AvoColors.Unknown else AvoColors.Bad, Modifier.weight(1f))
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        StatusChip("NTRIP", if (ntripState is NtripState.Streaming) "Recibiendo" else ntripState.texto, ntripColor, Modifier.weight(1f)) { go("ntrip") }
                        StatusChip("SD", t?.v2?.let { if (recording) "Grabando" else if (it.sdMounted) "Lista" else "No montada" } ?: "—",
                            when { t?.v2 == null -> AvoColors.Unknown; recording -> AvoColors.Warn; t!!.v2!!.sdMounted -> AvoColors.Ok; else -> AvoColors.Bad }, Modifier.weight(1f))
                        StatusChip("GNSS", rtk.state.texto, AvoColors.rtk(rtk.state), Modifier.weight(1f))
                    }
                }
                KV("Firmware", info?.firmware)
                if (link == LinkState.SIN_RELOJ || link == LinkState.DESCONECTADO) {
                    Spacer(Modifier.height(8.dp))
                    Button(onClick = { if (link == LinkState.SIN_RELOJ) go("bluetooth") else AvoLinkService.start(c.app) }, modifier = Modifier.fillMaxWidth()) {
                        Text(if (link == LinkState.SIN_RELOJ) "BUSCAR CHALECO" else "CONECTAR", fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
        item {
            AvoCard("En directo", trailing = { if (recording) StatusPill("REC", AvoColors.Red) }) {
                MetricGrid(listOf(
                    { m -> MetricTile("Velocidad", t?.let { Fmt.kmh(it.speedMmS / 1000.0) }, "km/h", m, AvoColors.Text) },
                    { m -> MetricTile("Distancia", t?.let { Fmt.m(it.distanceCm / 100.0, 0) }, "m", m) },
                    { m -> MetricTile("Tiempo", t?.let { Fmt.duration(it.activeMs) }, "", m) },
                    { m -> MetricTile("Precisión H", rtk.hAccM?.let { fmtAcc(it) }, "", m, AvoColors.rtk(rtk.state)) },
                    { m -> MetricTile("Precisión V", rtk.vAccM?.let { fmtAcc(it) }, "", m) },
                    { m -> MetricTile("Satélites", rtk.satellites?.toString(), "", m, AvoColors.Blue) },
                ))
                Spacer(Modifier.height(8.dp))
                KV("Sesión", t?.session?.texto)
                KV("Geocerca", t?.geofence?.texto)
                KV("Grabación", t?.rec?.texto)
                KV("Edad de la corrección", rtk.correctionAgeMaxMs?.let { if (it == Long.MAX_VALUE) "> 120 s" else "≤ ${it / 1000} s" })
                KV("Último dato GNSS", rtk.gnssAgeMs?.let { "hace ${it} ms" })
                KV("Telemetría", tel?.let { if (fresh) "hace ${age} ms" else "sin datos recientes" }, if (tel != null && !fresh) AvoColors.Warn else AvoColors.Text)
                if ((t?.droppedRecords ?: 0L) > 0L) KV("Registros descartados", t!!.droppedRecords.toString(), AvoColors.Bad)
                if (t?.inhibited == true) KV("Grabación", "Inhibida por el reloj (batería o SD)", AvoColors.Bad)
            }
        }
        item { GnssQualityCard(t?.v3?.takeIf { fresh }, rtk.state, t?.v2?.rtcmUsedByReceiver) }
        item {
            AvoCard("Correcciones NTRIP", onClick = { go("ntrip") }, trailing = { StatusPill(if (ntripState is NtripState.Streaming) "Recibiendo" else ntripState.texto.take(22), ntripColor) }) {
                val activeMount by c.ntrip.activeMount.collectAsStateWithLifecycle()
                KV("Punto de montaje", (activeMount ?: c.settings.ntrip.value.mountpoint).ifBlank { null },
                    if (activeMount != null && activeMount != c.settings.ntrip.value.mountpoint) AvoColors.Warn else AvoColors.Text)
                if (activeMount != null && activeMount != c.settings.ntrip.value.mountpoint) KV("Fuente", "de reserva (la principal falló)", AvoColors.Warn)
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
        item {
            AvoCard("Dispositivos", onClick = { go("dispositivos") }) {
                KV("Pecho", info?.firmware)
                KV("Espalda", t?.let { if (it.backLink) "Conectada" else "Sin enlace" })
                KV("Cincha", t?.let { if (it.girth) "Conectada" else "Sin datos" })
            }
        }
    }
}

fun fmtAcc(m: Double): String = if (m < 1) String.format(Locale.forLanguageTag("es-ES"), "%.1f cm", m * 100) else String.format(Locale.forLanguageTag("es-ES"), "%.2f m", m)


/**
 * GNSS quality from the receiver (BACK 3.9.0: UBX-NAV-SAT/NAV-SIG summary, RTK FIX tracking; CHEST 3.7.6 telemetry v3).
 * Diagnosis only: these values tell whether RTK can work and why not, they do not change the position.
 */
@Composable
private fun GnssQualityCard(q: org.avoperformance.horse.core.ble.TelemetryV3?, state: org.avoperformance.horse.core.telemetry.RtkState, rtcmUsed: Long?) {
    val es = Locale.forLanguageTag("es-ES")
    AvoCard("Calidad GNSS") {
        if (q == null || !q.backHasQuality) {
            Text("Necesita espalda 3.9.0 y pecho 3.7.6 o posteriores.", color = AvoColors.TextDim, fontSize = 13.sp)
            return@AvoCard
        }
        val diag = when {
            !q.signalsFresh -> "Esperando el resumen de señales del receptor" to AvoColors.Unknown
            q.l1Only -> "Antena solo L1: sin segunda frecuencia no hay RTK FIX" to AvoColors.Bad
            (rtcmUsed ?: 0L) == 0L -> "El receptor no está usando correcciones RTCM" to AvoColors.Warn
            state == org.avoperformance.horse.core.telemetry.RtkState.FIX -> "RTK FIX: precisión centimétrica" to AvoColors.Ok
            q.cnoMean in 1..34 -> "Señal débil (cielo tapado o antena mal colocada)" to AvoColors.Warn
            q.sigCarrierUsed < 10 -> "Pocas señales con fase de portadora: RTK aún convergiendo" to AvoColors.Warn
            else -> "Correcciones aplicadas, convergiendo hacia FIX" to AvoColors.Blue
        }
        Text(diag.first, color = diag.second, fontSize = 14.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(6.dp))
        if (q.signalsFresh) {
            KV("Satélites usados / seguidos", "${q.svUsed} / ${q.svTracked}")
            KV("Señales usadas / seguidas", "${q.sigUsed} / ${q.sigTracked}")
            KV("Segunda frecuencia (L2/E5b/B2)", "${q.sigL2Used} usadas / ${q.sigL2}", if (q.sigL2 == 0) AvoColors.Bad else AvoColors.Text)
            KV("Con fase de portadora (RTK)", q.sigCarrierUsed.toString(), if (q.sigCarrierUsed == 0) AvoColors.Warn else AvoColors.Text)
            KV("Con correcciones", q.sigCorrected.toString())
            KV("C/N₀ media (mín–máx)", if (q.cnoMean > 0) "${q.cnoMean} dBHz (${q.cnoMin}–${q.cnoMax})" else null,
                if (q.cnoMean in 1..34) AvoColors.Warn else AvoColors.Text)
            KV("Señales débiles (< 30 dBHz)", q.sigWeak.toString(), if (q.sigWeak > q.sigTracked / 3) AvoColors.Warn else AvoColors.Text)
        } else if (q.qualityMon == 2) KV("Mensajes de calidad", "rechazados por el receptor", AvoColors.Warn)
        else if (q.qualityMon == 3) KV("Mensajes de calidad", "UART del receptor demasiado lenta", AvoColors.Warn)
        KV("Precisión de la velocidad", if (q.sAccMmS > 0) String.format(es, "%.2f km/h", q.sAccMmS * 0.0036) else null)
        KV("PDOP", if (q.pdopE2 > 0) String.format(es, "%.2f", q.pdopE2 / 100.0) else null)
        KV("Primer RTK FIX", q.firstFixS?.let { "a los ${it / 60} min ${it % 60} s del arranque" } ?: "todavía no")
        KV("Tiempo en FIX / FLOAT", "${Fmt.duration(q.fixedMs)} / ${Fmt.duration(q.floatMs)}")
        KV("Pérdidas de FIX", q.fixLost.toString(), if (q.fixLost > 0) AvoColors.Warn else AvoColors.Text)
    }
}
