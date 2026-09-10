package ai.routin.mytoken.feature.home

import ai.routin.mytoken.domain.model.ProviderId
import androidx.compose.ui.graphics.Color

/**
 * Provider display names and accent colors, mirroring the macOS popover
 * (ProviderRegistry display names + ProviderTheme accent colors).
 */
object ProviderCatalog {
    fun displayName(providerId: ProviderId): String = when (providerId) {
        ProviderId.Routin -> "Routin"
        ProviderId.DeepSeek -> "DeepSeek"
        ProviderId.Glm -> "智谱 GLM"
        ProviderId.Volcengine -> "火山方舟"
        ProviderId.NewAPI -> "New API"
        ProviderId.CommandCode -> "Command Code"
    }

    fun accentColor(providerId: ProviderId): Color = when (providerId) {
        ProviderId.Routin -> Color(0xFF1565C0)
        ProviderId.DeepSeek -> Color(0xFF3949AB)
        ProviderId.Glm -> Color(0xFF2E7D32)
        ProviderId.Volcengine -> Color(0xFFEF6C00)
        ProviderId.NewAPI -> Color(0xFF6A1B9A)
        ProviderId.CommandCode -> Color(0xFF00897B)
    }
}
