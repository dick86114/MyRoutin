package ai.routin.mytoken.core.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val LightColors = lightColorScheme(
    primary = Color(0xFF175CD3),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFD8E6FF),
    onPrimaryContainer = Color(0xFF082444),
    secondary = Color(0xFF1F6F54),
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFD1F0DE),
    onSecondaryContainer = Color(0xFF04291C),
    tertiary = Color(0xFF8A4B00),
    onTertiary = Color.White,
    tertiaryContainer = Color(0xFFFFDCC2),
    onTertiaryContainer = Color(0xFF2D1400),
    background = Color(0xFFF7F8FA),
    onBackground = Color(0xFF171A1F),
    surface = Color(0xFFFFFFFF),
    onSurface = Color(0xFF171A1F),
    surfaceVariant = Color(0xFFEDEFF3),
    onSurfaceVariant = Color(0xFF5A6472),
    outlineVariant = Color(0xFFD9DDE4),
    error = Color(0xFFB3261E),
    onError = Color.White,
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFF9EC1FF),
    onPrimary = Color(0xFF002D68),
    primaryContainer = Color(0xFF204B8C),
    onPrimaryContainer = Color(0xFFD8E6FF),
    secondary = Color(0xFF94D5B8),
    onSecondary = Color(0xFF003826),
    secondaryContainer = Color(0xFF115339),
    onSecondaryContainer = Color(0xFFD1F0DE),
    tertiary = Color(0xFFFFB77B),
    onTertiary = Color(0xFF482900),
    tertiaryContainer = Color(0xFF673C00),
    onTertiaryContainer = Color(0xFFFFDCC2),
    background = Color(0xFF0E1116),
    onBackground = Color(0xFFE2E5EA),
    surface = Color(0xFF151921),
    onSurface = Color(0xFFE2E5EA),
    surfaceVariant = Color(0xFF222933),
    onSurfaceVariant = Color(0xFFAEB6C2),
    outlineVariant = Color(0xFF363E49),
    error = Color(0xFFFFB4AB),
    onError = Color(0xFF690005),
)

/** 固定使用 MyToken 的 macOS 品牌层级，避免动态取色破坏供应商语义色。 */
@Composable
fun MyTokenTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        content = content,
    )
}
