package org.avoperformance.horse.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import org.avoperformance.horse.core.telemetry.RtkState

object AvoColors {
    val Bg = Color(0xFF0B0F14)
    val Surface = Color(0xFF141A22)
    val Surface2 = Color(0xFF1C2430)
    val Gold = Color(0xFFC9A227)
    val GoldDim = Color(0xFF8A7020)
    val Text = Color(0xFFE8ECF1)
    val TextDim = Color(0xFF9AA5B1)
    val Ok = Color(0xFF2FBF71)
    val Warn = Color(0xFFF2A93B)
    val Bad = Color(0xFFE5484D)
    val Info = Color(0xFF3B82F6)
    val Unknown = Color(0xFF6B7280)

    fun rtk(s: RtkState) = when (s) {
        RtkState.FIX -> Ok
        RtkState.FLOAT -> Warn
        RtkState.DGNSS -> Info
        RtkState.AUTONOMO -> Color(0xFFB0B7C3)
        RtkState.SIN_GNSS -> Bad
        RtkState.DESCONOCIDO -> Unknown
    }
}

private val scheme = darkColorScheme(
    primary = AvoColors.Gold, onPrimary = Color.Black,
    secondary = AvoColors.Info, onSecondary = Color.White,
    background = AvoColors.Bg, onBackground = AvoColors.Text,
    surface = AvoColors.Surface, onSurface = AvoColors.Text,
    surfaceVariant = AvoColors.Surface2, onSurfaceVariant = AvoColors.TextDim,
    error = AvoColors.Bad, onError = Color.White,
    outline = Color(0xFF2C3644),
)

@Composable
fun AvoTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = scheme, typography = Typography(), content = content)
}
