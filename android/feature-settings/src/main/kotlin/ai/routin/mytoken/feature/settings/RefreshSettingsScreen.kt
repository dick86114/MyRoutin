package ai.routin.mytoken.feature.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.FilterChip
import ai.routin.mytoken.core.ui.GlassSwitch
import ai.routin.mytoken.core.ui.glassFilterChipBorder
import ai.routin.mytoken.core.ui.glassFilterChipColors
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import ai.routin.mytoken.core.ui.SettingRow
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * 刷新 section of the settings page. Background scheduling itself arrives with
 * Task 10; this screen only edits the local preferences.
 */
@Composable
fun RefreshSettingsSection(
    settings: RefreshSettings,
    onAutoRefreshChange: (Boolean) -> Unit,
    onIntervalChange: (Int) -> Unit,
    onWifiOnlyChange: (Boolean) -> Unit,
    onOpenAppRefreshChange: (Boolean) -> Unit,
    onRetryOnFailureChange: (Boolean) -> Unit,
) {
    Section(title = "刷新") {
        SettingSwitchRow(
            label = "自动刷新",
            checked = settings.autoRefreshEnabled,
            onChange = onAutoRefreshChange,
        )
        Text(
            text = "刷新频率",
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.padding(vertical = 4.dp),
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            RefreshSettings.ALLOWED_REFRESH_INTERVAL_MINUTES.sorted().forEach { minutes ->
                FilterChip(
                    selected = settings.refreshIntervalMinutes == minutes,
                    onClick = { onIntervalChange(minutes) },
                    label = { Text(text = "${minutes}分钟") },
                    colors = glassFilterChipColors(selected = settings.refreshIntervalMinutes == minutes),
                    border = glassFilterChipBorder(selected = settings.refreshIntervalMinutes == minutes),
                )
            }
        }
        SettingSwitchRow(
            label = "仅 Wi-Fi 下刷新",
            checked = settings.wifiOnly,
            onChange = onWifiOnlyChange,
        )
        SettingSwitchRow(
            label = "打开应用时刷新",
            checked = settings.openAppRefresh,
            onChange = onOpenAppRefreshChange,
        )
        SettingSwitchRow(
            label = "失败后自动重试",
            checked = settings.retryOnFailure,
            onChange = onRetryOnFailureChange,
        )
    }
}

@Composable
internal fun SettingSwitchRow(
    label: String,
    checked: Boolean,
    onChange: (Boolean) -> Unit,
) {
    SettingRow(title = label) {
        GlassSwitch(
            checked = checked,
            onCheckedChange = onChange,
            contentDescription = label,
        )
    }
}
