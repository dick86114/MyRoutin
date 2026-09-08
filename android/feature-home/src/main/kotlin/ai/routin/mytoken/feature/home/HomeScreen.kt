package ai.routin.mytoken.feature.home

import ai.routin.mytoken.domain.model.ProviderId
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import ai.routin.mytoken.core.ui.GlassButton
import ai.routin.mytoken.core.ui.GlassButtonTone
import ai.routin.mytoken.core.ui.glassFilterChipBorder
import ai.routin.mytoken.core.ui.glassFilterChipColors
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import java.util.UUID

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    state: HomeUiState,
    onRefreshAll: () -> Unit,
    onRefreshCredential: (UUID) -> Unit,
    onOpenCredential: (UUID) -> Unit,
    onImportFromMac: () -> Unit,
    onAddManually: () -> Unit,
) {
    var selectedProvider by remember { mutableStateOf<ProviderId?>(null) }
    val listState = rememberLazyListState()
    val allCards = remember(state.cards) {
        state.cards.filter { it.status != ai.routin.mytoken.domain.usage.RefreshStatus.Disabled }
    }
    val visibleProviders = remember(state.groups) { state.groups.map { it.providerId } }
    val visibleCards = remember(allCards, selectedProvider) {
        selectedProvider
            ?.let { provider -> allCards.filter { it.credential.providerId == provider } }
            ?: allCards
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(
                            text = "账户用量",
                            style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Text(
                            text = "${visibleCards.size} 个凭证",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                },
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
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.background),
        ) {
            when {
                state.isLoading -> Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }

                allCards.isEmpty() -> EmptyState(
                    onImportFromMac = onImportFromMac,
                    onAddManually = onAddManually,
                )

                else -> Column(modifier = Modifier.fillMaxSize()) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .horizontalScroll(rememberScrollState())
                            .padding(horizontal = 16.dp, vertical = 4.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        FilterChip(
                            selected = selectedProvider == null,
                            onClick = { selectedProvider = null },
                            label = { Text(text = "全部") },
                            colors = glassFilterChipColors(selected = selectedProvider == null),
                            border = glassFilterChipBorder(selected = selectedProvider == null),
                        )
                        visibleProviders.forEach { provider ->
                            FilterChip(
                                selected = selectedProvider == provider,
                                onClick = {
                                    selectedProvider = if (selectedProvider == provider) null else provider
                                },
                                label = { Text(text = ProviderCatalog.displayName(provider)) },
                                colors = glassFilterChipColors(selected = selectedProvider == provider),
                                border = glassFilterChipBorder(selected = selectedProvider == provider),
                            )
                        }
                    }

                    LazyColumn(
                        state = listState,
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(start = 12.dp, end = 12.dp, top = 4.dp, bottom = 96.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        items(
                            visibleCards,
                            key = { it.credential.id },
                            contentType = { "credential-usage-card" },
                        ) { card ->
                            CredentialUsageCard(
                                card = card,
                                onOpen = { onOpenCredential(card.credential.id) },
                                onRetry = { onRefreshCredential(card.credential.id) },
                            )
                        }
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
            text = "尚未配置 Key",
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold,
        )
        Spacer(modifier = Modifier.height(6.dp))
        Text(
            text = "从 Mac 迁移，或手动添加一个 plan Key",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(modifier = Modifier.height(24.dp))
    GlassButton(
        onClick = onImportFromMac,
        tone = GlassButtonTone.Primary,
        text = "从 Mac 导入",
    )
    Spacer(modifier = Modifier.height(8.dp))
    GlassButton(
        onClick = onAddManually,
        text = "手动添加",
    )
}
}
