package ai.routin.mytoken.feature.home

import ai.routin.mytoken.domain.usage.RefreshStatus
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
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

internal data class StatusColors(
    val normal: Color,
    val warning: Color,
    val critical: Color,
    val neutral: Color,
) {
    companion object {
        val lightPalette = StatusColors(Color(0xFF24A148), Color(0xFFD97706), Color(0xFFDA1E28), Color(0xFF8D8D8D))
        val darkPalette = StatusColors(Color(0xFF42BE65), Color(0xFFF1C21B), Color(0xFFFA4D56), Color(0xFFA8A8A8))
        fun forTheme(isDark: Boolean) = if (isDark) darkPalette else lightPalette
    }
}

@Composable
internal fun statusColors(): StatusColors =
    StatusColors.forTheme(MaterialTheme.colorScheme.background.luminance() < 0.5f)

internal fun statusLabel(card: CredentialCardUi): String? = when (card.status) {
    RefreshStatus.Loading -> "正在加载"
    RefreshStatus.Disabled -> "已停用"
    RefreshStatus.Failed -> "更新失败"
    RefreshStatus.Ready -> if (card.isStale) "显示上次成功数据" else null
}

@Composable
fun CredentialUsageCard(
    card: CredentialCardUi,
    onOpen: () -> Unit,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val accent = ProviderCatalog.accentColor(card.credential.providerId)
    val providerName = ProviderCatalog.displayName(card.credential.providerId)
    val plan = card.snapshot?.planName.orEmpty()
    Card(
        onClick = onOpen,
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        colors = CardDefaults.cardColors(containerColor = accent.copy(alpha = 0.12f)),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
        border = BorderStroke(1.dp, accent.copy(alpha = 0.22f)),
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(verticalAlignment = Alignment.Top) {
                Text(
                    text = card.credential.name,
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Column(modifier = Modifier.padding(start = 10.dp, top = 4.dp)) {
                    Text(
                        text = if (plan.isEmpty()) providerName else "$providerName · $plan",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                    )
                    val start = card.snapshot?.subscriptionStartAt
                    val end = card.snapshot?.subscriptionEndAt
                    if (start != null || end != null) {
                        Row(modifier = Modifier.padding(top = 2.dp)) {
                            Text(
                                text = "开始 ${formatSubscriptionTime(start)}",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.weight(1f),
                            )
                            Text(
                                text = "结束 ${formatSubscriptionTime(end)}",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.weight(1f),
                                textAlign = androidx.compose.ui.text.style.TextAlign.End,
                            )
                        }
                    }
                }
            }

            val metrics = card.snapshot?.metrics.orEmpty()
            when (card.credential.providerId) {
                ai.routin.mytoken.domain.model.ProviderId.Glm -> GLMMetrics(metrics)
                ai.routin.mytoken.domain.model.ProviderId.NewAPI -> NewAPIMetrics(metrics)
                ai.routin.mytoken.domain.model.ProviderId.Volcengine -> VolcengineMetrics(metrics)
                else -> UsageMetricGrid(metrics = metrics)
            }

            if (card.status == RefreshStatus.Loading) {
                LinearProgressIndicator(modifier = Modifier.fillMaxWidth().height(3.dp))
            }
            val status = when {
                card.status == RefreshStatus.Loading -> "正在加载"
                card.status == RefreshStatus.Failed -> card.error?.message ?: "更新失败"
                card.isStale -> "显示上次成功数据"
                else -> null
            }
            status?.let {
                Text(text = it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.labelSmall)
            }
            if (card.status == RefreshStatus.Failed) {
                TextButton(onClick = onRetry, contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp)) {
                    Text(text = "重试")
                }
            }
        }
    }
}
