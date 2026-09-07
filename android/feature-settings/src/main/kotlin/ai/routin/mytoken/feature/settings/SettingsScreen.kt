package ai.routin.mytoken.feature.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/**
 * Top-level settings page: 刷新 / 首页显示 / 数据迁移 / 关于.
 * Deliberately excludes macOS-specific options (menu bar style, login item, window
 * behavior); the mobile equivalents are card density, metric visibility and defaults.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    state: SettingsUiState,
    appVersion: String,
    onBack: () -> Unit,
    onAutoRefreshChange: (Boolean) -> Unit,
    onIntervalChange: (Int) -> Unit,
    onWifiOnlyChange: (Boolean) -> Unit,
    onOpenAppRefreshChange: (Boolean) -> Unit,
    onRetryOnFailureChange: (Boolean) -> Unit,
    onCardDensityChange: (CardDensity) -> Unit,
    onShowDisabledCredentialsChange: (Boolean) -> Unit,
    onDefaultExpandGroupsChange: (Boolean) -> Unit,
    onShowUsageProgressChange: (Boolean) -> Unit,
    onShowBalanceChange: (Boolean) -> Unit,
    onShowResetTimeChange: (Boolean) -> Unit,
    onOpenTransfer: () -> Unit,
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(text = "设置") },
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
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .testTag("settings_list"),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item(key = "refresh") {
                RefreshSettingsSection(
                    settings = state.refresh,
                    onAutoRefreshChange = onAutoRefreshChange,
                    onIntervalChange = onIntervalChange,
                    onWifiOnlyChange = onWifiOnlyChange,
                    onOpenAppRefreshChange = onOpenAppRefreshChange,
                    onRetryOnFailureChange = onRetryOnFailureChange,
                )
            }
            item(key = "display") {
                DisplaySettingsSection(
                    settings = state.display,
                    onCardDensityChange = onCardDensityChange,
                    onShowDisabledCredentialsChange = onShowDisabledCredentialsChange,
                    onDefaultExpandGroupsChange = onDefaultExpandGroupsChange,
                    onShowUsageProgressChange = onShowUsageProgressChange,
                    onShowBalanceChange = onShowBalanceChange,
                    onShowResetTimeChange = onShowResetTimeChange,
                )
            }
            item(key = "migration") {
                Section(title = "数据迁移") {
                    Text(
                        text = "从 Mac 的 MyToken 扫码迁移凭证，密钥端到端加密传输，只在两台设备间流转。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(bottom = 8.dp),
                    )
                    Button(onClick = onOpenTransfer) {
                        Text(text = "从 Mac 导入")
                    }
                }
            }
            item(key = "about") {
                Section(title = "关于") {
                    Text(
                        text = "MyToken $appVersion",
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Medium,
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = "在手机上查看多家大模型供应商的用量、余额、剩余额度与重置时间。" +
                            "凭证只保存在本机：密钥经系统安全存储加密，排序等个性化设置独立于 Mac。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = "帮助：先在 Mac 端 MyToken 发起迁移获取凭证；" +
                            "如用量显示异常，可在凭证页对单个凭证执行「测试连接」排查。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

/** Grouped section container shared by the settings sub-screens. */
@Composable
internal fun Section(
    title: String,
    content: @Composable () -> Unit,
) {
    Column {
        Text(
            text = title,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(bottom = 8.dp),
        )
        content()
    }
}
