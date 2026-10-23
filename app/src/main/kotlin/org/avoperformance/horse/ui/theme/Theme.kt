package org.avoperformance.horse.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import org.avoperformance.horse.core.telemetry.RtkState

/** Palette taken from the AVO boot screen (black, racing red, silver) plus an electric blue for data. */
object AvoColors {
    val Bg = Color(0xFF030406)
    val Surface = Color(0xFF101014)
    val Surface2 = Color(0xFF1A1B20)
    val Line = Color(0xFF2A2B31)
    val Red = Color(0xFFED122A)
    val RedDark = Color(0xFFB71625)
    val RedLight = Color(0xFFFF495A)
    val Blue = Color(0xFF3D9BFF)
    val Cyan = Color(0xFF35D0E8)
    val Silver = Color(0xFFC9CBD1)
    /** Accent used for titles and highlights (kept under the old name so every screen follows the brand). */
    val Gold = Red
    val GoldDim = RedDark
    val Text = Color(0xFFF2F2F4)
    val TextDim = Color(0xFF9C9DA4)
    val Ok = Color(0xFF52DD40)
    val Warn = Color(0xFFFFC42C)
    val Bad = Color(0xFFFF3945)
    val Info = Blue
    val Unknown = Color(0xFF93949B)

    val CardBrush = Brush.verticalGradient(listOf(Color(0xFF15161B), Color(0xFF0D0D11)))

    fun rtk(s: RtkState) = when (s) {
        RtkState.FIX -> Ok
        RtkState.FLOAT -> Warn
        RtkState.DGNSS -> Blue
        RtkState.AUTONOMO -> Silver
        RtkState.SIN_GNSS -> Bad
        RtkState.DESCONOCIDO -> Unknown
    }
}

private val scheme = darkColorScheme(
    primary = AvoColors.Red, onPrimary = Color.White,
    primaryContainer = AvoColors.RedDark, onPrimaryContainer = Color.White,
    secondary = AvoColors.Blue, onSecondary = Color.White,
    tertiary = AvoColors.Silver,
    background = AvoColors.Bg, onBackground = AvoColors.Text,
    surface = AvoColors.Bg, onSurface = AvoColors.Text,
    surfaceVariant = AvoColors.Surface2, onSurfaceVariant = AvoColors.TextDim,
    surfaceContainer = AvoColors.Surface, surfaceContainerHigh = AvoColors.Surface2,
    surfaceContainerLow = AvoColors.Surface, surfaceContainerHighest = AvoColors.Surface2,
    error = AvoColors.Bad, onError = Color.White,
    outline = AvoColors.Line, outlineVariant = AvoColors.Line,
)

private val base = Typography()
private val type = base.copy(
    headlineLarge = base.headlineLarge.copy(fontWeight = FontWeight.Black, letterSpacing = 0.5.sp),
    headlineMedium = base.headlineMedium.copy(fontWeight = FontWeight.Black),
    headlineSmall = base.headlineSmall.copy(fontWeight = FontWeight.Bold),
    titleLarge = base.titleLarge.copy(fontWeight = FontWeight.Bold, letterSpacing = 0.5.sp),
    titleMedium = base.titleMedium.copy(fontWeight = FontWeight.SemiBold),
    labelSmall = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.Medium, letterSpacing = 0.6.sp),
)

@Composable
fun AvoTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = scheme, typography = type, content = content)
}
