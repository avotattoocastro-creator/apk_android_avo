package org.avoperformance.horse.ui.screens

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import org.avoperformance.horse.core.sync.LocalTraining
import org.avoperformance.horse.core.sync.SyncState
import org.avoperformance.horse.core.sync.WatchDelete
import org.avoperformance.horse.data.TrainingEntity
import org.avoperformance.horse.ui.theme.AvoColors

/** TrainingEntity → LocalTraining for the deletion rules. */
fun TrainingEntity.forWatchDelete() = LocalTraining(sessionId, segments, totalBytes, downloadedBytes, localSha256, watchSha256, serverSha256,
    runCatching { SyncState.valueOf(state) }.getOrDefault(SyncState.EN_RELOJ),
    runCatching { org.avoperformance.horse.core.ble.WatchFileState.valueOf(watchState) }.getOrDefault(org.avoperformance.horse.core.ble.WatchFileState.UNKNOWN),
    startRtcMs, activeMs)

fun TrainingEntity.canDeleteFromWatch() = WatchDelete.canDelete(forWatchDelete(), watchState)
fun TrainingEntity.deletedFromWatch() = watchState == WatchDelete.DELETED_ON_WATCH

/**
 * Asks for the deletion password ("AVO") before deleting from the watch. A wrong password does not call [onConfirm].
 * [loses]: at least one training has no verified copy on the phone (red warning).
 */
@Composable
fun WatchDeleteDialog(title: String, text: String, loses: Boolean, confirmLabel: String = "Borrar del reloj",
                      onConfirm: (String) -> Unit, onDismiss: () -> Unit) {
    var pwd by remember { mutableStateOf("") }
    var wrong by remember { mutableStateOf(false) }
    AlertDialog(onDismissRequest = onDismiss, containerColor = AvoColors.Surface,
        title = { Text(title) },
        text = {
            Column {
                Text(text, color = AvoColors.Text)
                Spacer(Modifier.height(8.dp))
                if (loses) Text(WatchDelete.Safety.SE_PIERDE.texto.uppercase(), color = AvoColors.Bad, fontWeight = FontWeight.Bold)
                else Text(WatchDelete.Safety.COPIA_EN_MOVIL.texto, color = AvoColors.Ok)
                Spacer(Modifier.height(10.dp))
                OutlinedTextField(pwd, { pwd = it; wrong = false }, label = { Text("Contraseña de borrado") }, singleLine = true,
                    isError = wrong, visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters, keyboardType = KeyboardType.Password),
                    modifier = Modifier.fillMaxWidth())
                if (wrong) Text("Contraseña incorrecta", color = AvoColors.Bad)
            }
        },
        confirmButton = {
            TextButton(enabled = pwd.isNotBlank(), onClick = {
                if (WatchDelete.passwordOk(pwd)) { onConfirm(pwd.trim()); pwd = "" } else wrong = true
            }) { Text(confirmLabel, color = AvoColors.Bad) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancelar") } })
}
