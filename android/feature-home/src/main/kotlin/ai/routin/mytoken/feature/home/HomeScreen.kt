package ai.routin.mytoken.feature.home

import ai.routin.mytoken.domain.model.ProviderId
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import java.util.UUID

/**
 * Home dashboard, adapted from the macOS menu bar popover (UsagePopoverView):
 * provider-grouped credential cards, status colors paired with text labels, metric
 * hierarchy, pull-to-refresh for all credentials, per-card refresh, and an
 * import/manual-add empty state.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    state: HomeUiState,
    onRefreshAll: () -> Unit,
    onRefreshCredential: (UUID) -> Unit,
    onToggleGroup: (ProviderId) -> Unit,
    onOpenCredential: (UUID) -> Unit,
    onImportFromMac: () -> Unit,
    onAddManually: () -> Unit,
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(text = "MyToken") },
                actions = {
                    IconButton(onClick = onRefreshAll) {
                        Icon(imageVector = Icons.Filled.Refresh, contentDescription = "刷新全部")
                    }
                },
            )
        },
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = state.isRefreshingAll,
            onRefresh = onRefreshAll,
            modifier = Modifier
                .padding(padding)
                .fillMaxSize(),
        ) {
            if (state.credentialCount == 0) {
                EmptyState(
                    onImportFromMac = onImportFromMac,
                    onAddManually = onAddManually,
                )
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    item(key = "header") {
                        val subtitle = buildString {
                            append("${state.credentialCount} 个凭证")
                            state.lastUpdatedText?.let { append(" · 更新于$it") }
                        }
                        Column {
                            Text(
                                text = "账户用量",
                                style = MaterialTheme.typography.titleLarge,
                                fontWeight = FontWeight.SemiBold,
                            )
                            Text(
                                text = subtitle,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                    items(state.groups, key = { it.providerId }) { group ->
                        ProviderGroupSection(
                            group = group,
                            onToggleGroup = onToggleGroup,
                            onOpenCredential = onOpenCredential,
                            onRefreshCredential = onRefreshCredential,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun EmptyState(
    onImportFromMac: () -> Unit,
    onAddManually: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = "尚未添加凭证",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = "先在 Mac 的 MyToken 中发起迁移，或手动添加一个供应商凭证",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(modifier = Modifier.height(24.dp))
        Button(onClick = onImportFromMac) {
            Text(text = "从 Mac 导入")
        }
        Spacer(modifier = Modifier.height(8.dp))
        OutlinedButton(onClick = onAddManually) {
            Text(text = "手动添加")
        }
    }
}
