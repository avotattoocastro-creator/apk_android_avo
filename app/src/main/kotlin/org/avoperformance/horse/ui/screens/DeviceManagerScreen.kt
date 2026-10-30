package org.avoperformance.horse.ui.screens

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import org.avoperformance.horse.AppContainer
import org.avoperformance.horse.ui.components.AvoCard
import org.avoperformance.horse.ui.components.KV
import org.avoperformance.horse.ui.theme.AvoColors

/** Read-only device inventory. Firmware updates are done with the AVO USB updater app. */
@Composable
fun DeviceManagerScreen(c: AppContainer) {
    val link by c.watch.state.collectAsStateWithLifecycle()
    val info by c.watch.info.collectAsStateWithLifecycle()
    val sample by c.watch.telemetry.collectAsStateWithLifecycle()
    val now = rememberNow()
    val age = sample?.let { (now - it.receivedMs).coerceAtLeast(0L) }
    val fresh = age != null && age <= 5000L
    val t = sample?.t?.takeIf { fresh }
    fun ok(b: Boolean?) = when (b) { true -> AvoColors.Ok; false -> AvoColors.Bad; null -> AvoColors.Unknown }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(vertical = 8.dp)) {
        item {
            AvoCard("Pecho") {
                KV("Enlace", link.texto)
                KV("Identificador", info?.deviceId)
                KV("Dirección BLE", c.watch.authorizedAddress ?: "No vinculado")
                KV("Firmware", info?.firmware)
                KV("Última telemetría", age?.let { "hace ${it} ms" }, if (fresh) AvoColors.Ok else AvoColors.Warn)
            }
        }
        item {
            AvoCard("Espalda") {
                KV("Enlace con el pecho", t?.let { if (it.backLink) "Conectado" else "Sin enlace" }, ok(t?.backLink))
                KV("Firmware", "No comunicado")
            }
        }
        item {
            AvoCard("Cincha") {
                KV("Enlace con la espalda", t?.let { if (it.girth) "Conectada" else "Sin datos" }, ok(t?.girth))
                KV("Firmware", "No comunicado")
            }
        }
    }
}
