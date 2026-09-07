package ai.routin.mytoken.feature.home

import ai.routin.mytoken.domain.model.CredentialKind
import ai.routin.mytoken.domain.model.ProviderId
import ai.routin.mytoken.domain.usage.RefreshStatus
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import java.time.ZoneId
import java.time.format.DateTimeFormatter

private val fullTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")

internal fun formatFullTime(instant: java.time.Instant): String =
    fullTimeFormatter.format(instant.atZone(ZoneId.systemDefault()))

internal fun credentialKindLabel(kind: CredentialKind): String = when (kind) {
    CredentialKind.BearerApiKey -> "Bearer Token"
    CredentialKind.ApiKey -> "API Key"
    CredentialKind.AccessKeyPair -> "Access Key Pair"
}

/**
 * Credential detail screen: all provider-supported metrics, last update time, failure
 * reason, single-credential refresh, and edit/delete entries (Task 9 owns the real
 * editor and deletion flows — the callbacks here are placeholders for that wiring).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CredentialDetailScreen(
    card: CredentialCardUi?,
    onBack: () -> Unit,
    onRefresh: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(text = card?.credential?.name ?: "凭证详情") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "返回",
                        )
                    }
                },
            )
        },
        bottomBar = {
            if (card != null) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Button(
                        onClick = onRefresh,
                        modifier = Modifier.weight(1f),
                    ) {
                        Text(text = "刷新")
                    }
                    OutlinedButton(
                        onClick = onEdit,
                        modifier = Modifier.weight(1f),
                    ) {
                        Text(text = "编辑")
                    }
                    Button(
                        onClick = onDelete,
                        modifier = Modifier.weight(1f),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.error,
                            contentColor = MaterialTheme.colorScheme.onError,
                        ),
                    ) {
                        Text(text = "删除")
                    }
                }
            }
        },
    ) { padding ->
        if (card == null) {
            Text(
                text = "凭证不存在或已被删除",
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier
                    .padding(padding)
                    .padding(24.dp),
            )
            return@Scaffold
        }
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = ProviderCatalog.displayName(card.credential.providerId) +
                    " · " + credentialKindLabel(card.credential.credentialKind),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                statusLabel(card)?.let { label ->
                    StatusBadge(
                        text = label,
                        color = when (card.status) {
                            RefreshStatus.Failed -> StatusTone.Critical
                            RefreshStatus.Loading -> MaterialTheme.colorScheme.primary
                            RefreshStatus.Disabled -> StatusTone.Neutral
                            RefreshStatus.Ready -> StatusTone.Warning
                        },
                    )
                }
            }

            val updatedText = card.snapshot?.fetchedAt?.let { "更新时间 ${formatFullTime(it)}" }
                ?: "更新时间 从未成功刷新"
            Text(
                text = updatedText,
                style = MaterialTheme.typography.bodyMedium,
            )
            Text(
                text = card.freshness.text,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            card.error?.let { error ->
                Text(
                    text = "失败原因",
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Medium,
                    color = MaterialTheme.colorScheme.error,
                )
                Text(
                    text = error.message ?: "刷新用量失败",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }

            val metrics = card.snapshot?.metrics.orEmpty()
            if (metrics.isEmpty()) {
                Text(
                    text = "暂无数据，请刷新后查看",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                UsageMetricGrid(metrics = metrics)
            }
        }
    }
}
