package ai.routin.mytoken.feature.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.material3.HorizontalDivider
import ai.routin.mytoken.core.ui.SectionCard
import ai.routin.mytoken.core.ui.GlassButton
import ai.routin.mytoken.core.ui.GlassButtonTone
import ai.routin.mytoken.core.ui.glassFilterChipBorder
import ai.routin.mytoken.core.ui.glassFilterChipColors
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    state: SettingsUiState,
    appVersion: String,
    updateState: AppUpdateUiState = AppUpdateUiState.Idle,
    onAutoRefreshChange: (Boolean) -> Unit,
    onIntervalChange: (Int) -> Unit,
    onWifiOnlyChange: (Boolean) -> Unit,
    onOpenAppRefreshChange: (Boolean) -> Unit,
    onRetryOnFailureChange: (Boolean) -> Unit,
    onThemeModeChange: (AppThemeMode) -> Unit,
    onOpenTransfer: () -> Unit,
    onNotificationsEnabledChange: (Boolean) -> Unit = {},
    onCredentialFailureAlertsChange: (Boolean) -> Unit = {},
    onLowThresholdChange: (Int) -> Unit = {},
    onHighThresholdChange: (Int) -> Unit = {},
    notificationPermissionGranted: Boolean = true,
    onRequestNotificationPermission: () -> Unit = {},
    onCheckForUpdates: () -> Unit = {},
    onDownloadAndInstall: (String, String) -> Unit = { _, _ -> },
    onOpenInstallPermissionSettings: () -> Unit = {},
    onInstallDownloadedUpdate: () -> Unit = {},
    onMirrorBaseChange: (String) -> Unit = {},
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = "设置",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.SemiBold,
                    )
                },
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier.padding(padding).fillMaxSize().testTag("settings_list"),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 96.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item(key = "theme") {
                SectionCard(title = "主题") {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        ThemeChip("跟随系统", state.display.themeMode == AppThemeMode.SYSTEM) {
                            onThemeModeChange(AppThemeMode.SYSTEM)
                        }
                        ThemeChip("浅色", state.display.themeMode == AppThemeMode.LIGHT) {
                            onThemeModeChange(AppThemeMode.LIGHT)
                        }
                        ThemeChip("深色", state.display.themeMode == AppThemeMode.DARK) {
                            onThemeModeChange(AppThemeMode.DARK)
                        }
                    }
                }
            }
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
            item(key = "notification") {
                NotificationSettingsSection(
                    settings = state.notifications,
                    permissionGranted = notificationPermissionGranted,
                    onRequestPermission = onRequestNotificationPermission,
                    onNotificationsEnabledChange = onNotificationsEnabledChange,
                    onCredentialFailureAlertsChange = onCredentialFailureAlertsChange,
                    onLowThresholdChange = onLowThresholdChange,
                    onHighThresholdChange = onHighThresholdChange,
                )
            }
            item(key = "migration") {
                SectionCard(title = "数据迁移") {
                    Text(
                        text = "从 Mac 扫码迁移凭证，密钥端到端加密传输。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    GlassButton(
                        onClick = onOpenTransfer,
                        tone = GlassButtonTone.Primary,
                        text = "从 Mac 导入",
                    )
                }
            }
            item(key = "about") {
                SectionCard(title = "关于") {
                    Text(
                        text = buildAnnotatedString {
                            withStyle(
                                SpanStyle(
                                    fontWeight = FontWeight.SemiBold,
                                    color = MaterialTheme.colorScheme.onSurface,
                                )
                            ) {
                                append("MyToken")
                            }
                            withStyle(
                                SpanStyle(color = MaterialTheme.colorScheme.onSurfaceVariant)
                            ) {
                                append(" $appVersion")
                            }
                        },
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = "更新通道",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    UpdateChannelSection(
                        mirrorBase = state.update.mirrorBase,
                        onMirrorBaseChange = onMirrorBaseChange,
                    )
                    HorizontalDivider(
                        modifier = Modifier.padding(vertical = 6.dp),
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f),
                    )
                    UpdateSection(
                        state = updateState,
                        currentVersion = appVersion,
                        onCheckForUpdates = onCheckForUpdates,
                        onDownloadAndInstall = onDownloadAndInstall,
                        onOpenInstallPermissionSettings = onOpenInstallPermissionSettings,
                        onInstallDownloadedUpdate = onInstallDownloadedUpdate,
                    )
                }
            }
        }
    }
}

@Composable
private fun UpdateSection(
    state: AppUpdateUiState,
    currentVersion: String,
    onCheckForUpdates: () -> Unit,
    onDownloadAndInstall: (String, String) -> Unit,
    onOpenInstallPermissionSettings: () -> Unit,
    onInstallDownloadedUpdate: () -> Unit,
) {
    when (state) {
        is AppUpdateUiState.Checking -> {
            Text(
                text = "正在检查更新...",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            GlassButton(
                onClick = onCheckForUpdates,
                enabled = false,
                text = "检测更新",
            )
        }

        is AppUpdateUiState.Downloading -> {
            val progress = state.progress
            Text(
                text = if (progress == null) "正在下载更新..." else "正在下载更新 ${(progress * 100).toInt()}%",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            LinearProgressIndicator(
                progress = { ((progress ?: 0f).coerceIn(0f, 1f)) },
                modifier = Modifier.fillMaxWidth(),
            )
        }

        is AppUpdateUiState.Available -> {
            Text(
                text = "发现新版本 v${state.version}",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
            )
            if (state.releaseNotes.isNotBlank()) {
                MarkdownText(
                    markdown = state.releaseNotes,
                )
            }
            GlassButton(
                onClick = { onDownloadAndInstall(state.version, state.downloadUrl) },
                modifier = Modifier.fillMaxWidth(),
                tone = GlassButtonTone.Primary,
                text = "下载并安装",
            )
        }

        is AppUpdateUiState.NeedsInstallPermission -> {
            Text(
                text = "安装更新前，需要允许 MyToken 安装未知来源应用。",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            GlassButton(
                onClick = onOpenInstallPermissionSettings,
                text = "打开安装权限设置",
            )
            GlassButton(
                onClick = onInstallDownloadedUpdate,
                text = "授权后继续安装",
            )
        }

        is AppUpdateUiState.ReadyToInstall -> {
            Text(
                text = "v${state.version} 已下载完成。",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            GlassButton(
                onClick = onInstallDownloadedUpdate,
                tone = GlassButtonTone.Primary,
                text = "安装更新",
            )
        }

        is AppUpdateUiState.Error -> {
            Text(
                text = state.message,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
            )
            GlassButton(
                onClick = onCheckForUpdates,
                text = "重试",
            )
        }

        is AppUpdateUiState.UpToDate -> {
            Text(
                text = "v$currentVersion 已是最新版本。"
                    .takeIf { state.currentVersion == currentVersion }
                    ?: "当前已是最新版本。",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            GlassButton(
                onClick = onCheckForUpdates,
                tone = GlassButtonTone.Primary,
                text = "检测更新",
            )
        }

        AppUpdateUiState.Idle -> GlassButton(
            onClick = onCheckForUpdates,
            tone = GlassButtonTone.Primary,
            text = "检测更新",
        )
    }
}

@Composable
private fun ThemeChip(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
) {
    FilterChip(
        selected = selected,
        onClick = onClick,
        label = { Text(text = label) },
        colors = glassFilterChipColors(selected = selected),
        border = glassFilterChipBorder(selected = selected),
    )
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun UpdateChannelSection(
    mirrorBase: String,
    onMirrorBaseChange: (String) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(
                selected = mirrorBase.isEmpty(),
                onClick = { onMirrorBaseChange("") },
                label = { Text(text = "GitHub 直连") },
                colors = glassFilterChipColors(selected = mirrorBase.isEmpty()),
                border = glassFilterChipBorder(selected = mirrorBase.isEmpty()),
            )
            FilterChip(
                selected = mirrorBase.isNotEmpty(),
                onClick = { if (mirrorBase.isEmpty()) onMirrorBaseChange(DEFAULT_UPDATE_CDN_BASES.first()) },
                label = { Text(text = "CDN 加速") },
                colors = glassFilterChipColors(selected = mirrorBase.isNotEmpty()),
                border = glassFilterChipBorder(selected = mirrorBase.isNotEmpty()),
            )
        }
        if (mirrorBase.isNotEmpty()) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                DEFAULT_UPDATE_CDN_BASES.forEach { base ->
                    FilterChip(
                        selected = mirrorBase == base,
                        onClick = { onMirrorBaseChange(base) },
                        label = { Text(text = base.removePrefix("https://")) },
                        colors = glassFilterChipColors(selected = mirrorBase == base),
                        border = glassFilterChipBorder(selected = mirrorBase == base),
                    )
                }
            }
            Text(
                text = "大陆网络建议选择 CDN 加速；若某镜像不可用可切换其他源。",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

private val DEFAULT_UPDATE_CDN_BASES = listOf(
    "https://ghfast.top",
    "https://gh-proxy.com",
    "https://ghproxy.net",
)

@Composable
internal fun Section(
    title: String,
    content: @Composable () -> Unit,
) {
    SectionCard(title = title) { content() }
}
