package org.avoperformance.horse.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.avoperformance.horse.ui.theme.AvoColors
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun AvoCard(title: String? = null, modifier: Modifier = Modifier, onClick: (() -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    Card(
        modifier = modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp).let { if (onClick != null) it.clickable { onClick() } else it },
        colors = CardDefaults.cardColors(containerColor = AvoColors.Surface),
        shape = RoundedCornerShape(14.dp),
    ) {
        Column(Modifier.padding(14.dp)) {
            if (title != null) {
                Text(title.uppercase(), color = AvoColors.Gold, fontSize = 12.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.sp)
                Spacer(Modifier.size(8.dp))
            }
            content()
        }
    }
}

@Composable
fun KV(label: String, value: String?, valueColor: Color = AvoColors.Text) {
    Row(Modifier.fillMaxWidth().padding(vertical = 3.dp), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, color = AvoColors.TextDim, fontSize = 14.sp, modifier = Modifier.weight(1f))
        Text(value ?: "—", color = if (value == null) AvoColors.Unknown else valueColor, fontSize = 14.sp, fontWeight = FontWeight.Medium)
    }
}

@Composable
fun StatusPill(text: String, color: Color) {
    Row(
        Modifier.background(color.copy(alpha = 0.16f), RoundedCornerShape(50)).padding(horizontal = 10.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(8.dp).background(color, CircleShape))
        Spacer(Modifier.width(6.dp))
        Text(text, color = color, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
fun BigValue(value: String?, unit: String, label: String, modifier: Modifier = Modifier) {
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(value ?: "—", color = if (value == null) AvoColors.Unknown else AvoColors.Text, fontSize = 26.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.width(3.dp))
            Text(unit, color = AvoColors.TextDim, fontSize = 13.sp, modifier = Modifier.padding(bottom = 4.dp))
        }
        Text(label, color = AvoColors.TextDim, fontSize = 12.sp)
    }
}

@Composable
fun ConfirmDialog(title: String, text: String, confirm: String = "Confirmar", danger: Boolean = false, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { Text(text) },
        confirmButton = { TextButton(onClick = { onDismiss(); onConfirm() }) { Text(confirm, color = if (danger) AvoColors.Bad else MaterialTheme.colorScheme.primary) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancelar") } },
    )
}

@Composable
fun Note(text: String, color: Color = AvoColors.TextDim) {
    Text(text, color = color, fontSize = 13.sp, modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
}

object Fmt {
    fun bytes(b: Long?): String? = b?.let {
        when {
            it >= 1L shl 30 -> String.format(Locale.US, "%.2f GB", it / 1073741824.0)
            it >= 1L shl 20 -> String.format(Locale.US, "%.1f MB", it / 1048576.0)
            it >= 1024 -> String.format(Locale.US, "%.1f kB", it / 1024.0)
            else -> "$it B"
        }
    }
    fun duration(ms: Long?): String? = ms?.let { val s = it / 1000; String.format(Locale.US, "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60) }
    fun date(ms: Long?): String? = ms?.takeIf { it > 1_600_000_000_000 }?.let { SimpleDateFormat("dd/MM/yyyy HH:mm", Locale.forLanguageTag("es-ES")).format(Date(it)) }
    fun m(v: Double?, dec: Int = 1): String? = v?.let { String.format(Locale.forLanguageTag("es-ES"), "%.${dec}f", it) }
    fun kmh(ms: Double?): String? = ms?.let { String.format(Locale.forLanguageTag("es-ES"), "%.1f", it * 3.6) }
}
