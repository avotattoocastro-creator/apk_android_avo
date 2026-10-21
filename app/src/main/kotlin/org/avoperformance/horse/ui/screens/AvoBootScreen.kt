package org.avoperformance.horse.ui.screens

import android.bluetooth.BluetoothManager
import android.content.Context
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import org.avoperformance.horse.AppContainer
import org.avoperformance.horse.BuildConfig
import org.avoperformance.horse.R
import org.avoperformance.horse.ble.LinkState
import org.avoperformance.horse.core.ntrip.NtripState

/** Branded startup with genuine subsystem status, never fabricated success. */
@Composable
fun AvoBootScreen(c: AppContainer, onContinue: () -> Unit) {
    val ctx = LocalContext.current
    val link by c.watch.state.collectAsStateWithLifecycle()
    val info by c.watch.info.collectAsStateWithLifecycle()
    val tel by c.watch.telemetry.collectAsStateWithLifecycle()
    val ntrip by c.ntrip.state.collectAsStateWithLifecycle()
    val stats by c.ntrip.stats.collectAsStateWithLifecycle()
    val adapter = remember { ctx.getSystemService(BluetoothManager::class.java)?.adapter }
    val ok = Color(0xFF52DD40)
    val wait = Color(0xFFFFC42C)
    val paused = Color(0xFF93949B)
    val error = Color(0xFFFF3945)
    val connected = link == LinkState.LISTO || link == LinkState.LISTO_SIN_AUTH
    val fresh = tel?.let { System.currentTimeMillis() - it.receivedMs < 5000L } == true
    val gps = tel?.t
    val ntripLive = ntrip is NtripState.Streaming && stats.bytesReceived > 0L
    val rows = listOf(
        Triple("Interfaz", "OK", ok),
        Triple("Bluetooth", when { adapter == null -> "No disponible"; adapter.isEnabled -> "Activo"; else -> "Desactivado" }, if (adapter?.isEnabled == true) ok else wait),
        Triple("Reloj", if (connected) "Conectado" else link.texto, if (connected) ok else if (link == LinkState.ERROR) error else wait),
        Triple("Chaleco", if (fresh && gps?.backLink == true) "Conectado" else "Esperando enlace", if (fresh && gps?.backLink == true) ok else wait),
        Triple("GNSS", if (fresh && gps != null) "Telemetría disponible" else "Esperando señal", if (fresh && gps != null) ok else wait),
        Triple("NTRIP", if (ntripLive) "Recibiendo RTCM" else ntrip.texto, if (ntripLive) ok else if (ntrip is NtripState.Failed) error else if (ntrip is NtripState.Stopped) paused else wait),
        Triple("Servidor", "En pausa", paused),
        Triple("Almacenamiento", if (ctx.filesDir.exists() && ctx.filesDir.canWrite()) "OK" else "No disponible", if (ctx.filesDir.canWrite()) ok else error)
    )
    Column(Modifier.fillMaxSize().background(Color(0xFF030406))) {
        Image(
            painter = painterResource(R.drawable.avo_brand_hero),
            contentDescription = "AVO Horse Edition Performance, silueta de caballo",
            contentScale = ContentScale.FillWidth,
            modifier = Modifier.fillMaxWidth().weight(0.47f)
        )
        Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text("INICIANDO SISTEMA", color = Color.White, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(9.dp))
            LinearProgressIndicator(modifier = Modifier.fillMaxWidth(), color = Color(0xFFED122A), trackColor = Color(0xFF27292C))
            Spacer(Modifier.height(14.dp))
        }
        LazyColumn(
            modifier = Modifier.weight(0.53f).padding(horizontal = 14.dp)
                .border(1.dp, Color(0xFFB71625), RoundedCornerShape(16.dp))
                .background(Color(0xFF101014), RoundedCornerShape(16.dp)),
            contentPadding = PaddingValues(horizontal = 14.dp, vertical = 8.dp)
        ) {
            items(rows.size) { i ->
                val (label, value, statusColor) = rows[i]
                Row(Modifier.fillMaxWidth().heightIn(min = 36.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(label, modifier = Modifier.weight(0.38f), color = Color(0xFFE8E8EA), style = MaterialTheme.typography.bodySmall)
                    Text("●", color = statusColor, modifier = Modifier.padding(end = 8.dp))
                    Text(value, modifier = Modifier.weight(0.62f), color = statusColor, style = MaterialTheme.typography.bodySmall, maxLines = 2)
                }
                if (i < rows.lastIndex) HorizontalDivider(color = Color(0xFF36373B), thickness = 0.5.dp)
            }
        }
        Spacer(Modifier.height(9.dp))
        Text(
            "App ${BuildConfig.VERSION_NAME}   |   Firmware ${info?.firmware ?: "—"}   |   AVO",
            color = Color(0xFFABABAE),
            modifier = Modifier.align(Alignment.CenterHorizontally).padding(bottom = 6.dp),
            style = MaterialTheme.typography.labelSmall
        )
        TextButton(onClick = onContinue, modifier = Modifier.align(Alignment.CenterHorizontally)) { Text("ENTRAR AHORA", color = Color(0xFFFF495A)) }
    }
}
