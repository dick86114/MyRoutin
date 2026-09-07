package ai.routin.mytoken.feature.home

import ai.routin.mytoken.domain.usage.RefreshStatus
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

/**
 * Status colors resolved from the active theme so contrast holds in dark mode.
 * Light palette: saturated dark tones on light backgrounds; dark palette: lighter
 * tones for dark backgrounds. Selection is derived from the composed color scheme
 * (background luminance), so it follows whatever scheme is installed — system or explicit.
 */
internal data class StatusColors(
    val normal: Color,
    val warning: Color,
    val critical: Color,
    val neutral: Color,
) {
    companion object {
        val lightPalette: StatusColors = StatusColors(
            normal = Color(0xFF2E7D32),
            warning = Color(0xFFEF6C00),
            critical = Color(0xFFC62828),
            neutral = Color(0xFF757575),
        )

        val darkPalette: StatusColors = StatusColors(
            normal = Color(0xFF81C784),
            warning = Color(0xFFFFB74D),
            critical = Color(0xFFE57373),
            neutral = Color(0xFFB0BEC5),
        )

        fun forTheme(isDark: Boolean): StatusColors =
            if (isDark) darkPalette else lightPalette
    }
}

/** Resolves [StatusColors] from the composed MaterialTheme color scheme. */
@Composable
internal fun statusColors(): StatusColors =
    StatusColors.forTheme(isDark = MaterialTheme.colorScheme.background.luminance() < 0.5f)

/** Badge color for a credential's status; every color is paired with [statusLabel] text. */
internal fun statusBadgeColor(
    card: CredentialCardUi,
    colors: StatusColors,
    loadingColor: Color,
): Color = when (card.status) {
    RefreshStatus.Failed -> colors.critical
    RefreshStatus.Loading -> loadingColor
    RefreshStatus.Disabled -> colors.neutral
    RefreshStatus.Ready -> colors.warning
}

/** Human-readable status labels; every status color is paired with a text label. */
internal fun statusLabel(card: CredentialCardUi): String? = when (card.status) {
    RefreshStatus.Loading -> "刷新中…"
    RefreshStatus.Disabled -> "已停用"
    RefreshStatus.Failed -> "更新失败"
    RefreshStatus.Ready -> if (card.isStale) "数据已过期" else null
}

/**
 * Credential card for the home grid: provider accent border, credential name, status badge
 * with text label, freshness line, key metric grid (2 columns), and failure handling that
 * keeps the last successful snapshot visible with a stale marker and a retry action.
 * A Loading card (including one left by a cancelled refresh) renders as "刷新中…", never
 * as an error.
 */
@Composable
fun CredentialUsageCard(
    card: CredentialCardUi,
    onOpen: () -> Unit,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val accent = ProviderCatalog.accentColor(card.credential.providerId)
    val colors = statusColors()
    Card(
        onClick = onOpen,
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        border = BorderStroke(1.dp, accent.copy(alpha = 0.25f)),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = card.credential.name,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                statusLabel(card)?.let { label ->
                    StatusBadge(
                        text = label,
                        color = statusBadgeColor(card, colors, MaterialTheme.colorScheme.primary),
                    )
                }
            }

            Text(
                text = card.freshness.text,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            if (card.status == RefreshStatus.Loading) {
                LinearProgressIndicator(
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            card.snapshot?.metrics
                ?.takeIf { it.isNotEmpty() }
                ?.let { metrics ->
                    UsageMetricGrid(metrics = metrics.take(CARD_METRIC_LIMIT))
                }

            if (card.isStale) {
                Text(
                    text = "已显示上次成功数据",
                    style = MaterialTheme.typography.labelSmall,
                    color = colors.warning,
                )
            }

            if (card.status == RefreshStatus.Failed) {
                card.error?.let { error ->
                    Text(
                        text = error.message ?: "刷新用量失败",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
                TextButton(onClick = onRetry) {
                    Text(text = "重试")
                }
            }
        }
    }
}

@Composable
internal fun StatusBadge(
    text: String,
    color: Color,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(50),
        color = color.copy(alpha = 0.14f),
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.labelMedium,
            color = color,
            fontWeight = FontWeight.Medium,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
        )
    }
}

private const val CARD_METRIC_LIMIT = 4

