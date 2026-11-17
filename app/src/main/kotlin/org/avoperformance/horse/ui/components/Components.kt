package org.avoperformance.horse.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.ui.draw.clip
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
fun AvoCard(title: String? = null, modifier: Modifier = Modifier, onClick: (() -> Unit)? = null, trailing: (@Composable () -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    val shape = RoundedCornerShape(16.dp)
    Column(
        modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 5.dp)
            .clip(shape).background(AvoColors.CardBrush).border(1.dp, AvoColors.Line, shape)
            .let { if (onClick != null) it.clickable { onClick() } else it }
            .padding(14.dp)
    ) {
        if (title != null) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(width = 3.dp, height = 14.dp).background(AvoColors.Red, RoundedCornerShape(2.dp)))
                Spacer(Modifier.width(8.dp))
                Text(title.uppercase(), color = AvoColors.Silver, fontSize = 12.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.2.sp, modifier = Modifier.weight(1f))
                trailing?.invoke()
            }
            Spacer(Modifier.size(10.dp))
        }
        content()
    }
}

/** Compact metric tile used across the app (value + unit + label, optional accent colour). */
@Composable
fun MetricTile(label: String, value: String?, unit: String = "", modifier: Modifier = Modifier, accent: Color = AvoColors.Text, icon: String? = null) {
    val shape = RoundedCornerShape(12.dp)
    Column(
        modifier.clip(shape).background(AvoColors.Surface2).border(1.dp, AvoColors.Line, shape).padding(horizontal = 10.dp, vertical = 9.dp)
    ) {
        Text((icon?.let { "$it " } ?: "") + label.uppercase(), color = AvoColors.TextDim, fontSize = 10.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.8.sp, maxLines = 1)
        Row(verticalAlignment = Alignment.Bottom) {
            Text(value ?: "—", color = if (value == null) AvoColors.Unknown else accent, fontSize = 22.sp, fontWeight = FontWeight.Black, maxLines = 1)
            if (unit.isNotEmpty()) {
                Spacer(Modifier.width(3.dp))
                Text(unit, color = AvoColors.TextDim, fontSize = 11.sp, modifier = Modifier.padding(bottom = 3.dp))
            }
        }
    }
}

/** Grid of metric tiles, [columns] per row. */
@Composable
fun MetricGrid(items: List<@Composable (Modifier) -> Unit>, columns: Int = 3) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        items.chunked(columns).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { it(Modifier.weight(1f)) }
                repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

/** Pill-style segmented selector (Resumen / Mapa / Datos, Mapa / Satélite / Híbrido…). */
@Composable
fun Segmented(options: List<String>, selected: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(50)
    Row(modifier.fillMaxWidth().clip(shape).background(AvoColors.Surface).border(1.dp, AvoColors.Line, shape).padding(3.dp)) {
        options.forEachIndexed { i, label ->
            val on = i == selected
            Box(
                Modifier.weight(1f).clip(shape).background(if (on) AvoColors.Red else Color.Transparent).clickable { onSelect(i) }.padding(vertical = 8.dp),
                contentAlignment = Alignment.Center
            ) { Text(label, color = if (on) Color.White else AvoColors.TextDim, fontSize = 13.sp, fontWeight = if (on) FontWeight.Bold else FontWeight.Medium, maxLines = 1) }
        }
    }
}

/** Screen header: big title, optional subtitle and trailing actions. */
@Composable
fun ScreenHeader(title: String, subtitle: String? = null, actions: @Composable () -> Unit = {}) {
    Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 8.dp, top = 10.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title.uppercase(), color = AvoColors.Text, fontSize = 22.sp, fontWeight = FontWeight.Black, letterSpacing = 1.sp)
            if (subtitle != null) Text(subtitle, color = AvoColors.TextDim, fontSize = 13.sp)
        }
        actions()
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
