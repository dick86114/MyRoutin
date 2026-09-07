package ai.routin.mytoken.feature.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
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
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(text = label, style = MaterialTheme.typography.bodyMedium)
        Switch(
            checked = checked,
            onCheckedChange = onChange,
            modifier = Modifier.semantics { contentDescription = label },
        )
    }
}
