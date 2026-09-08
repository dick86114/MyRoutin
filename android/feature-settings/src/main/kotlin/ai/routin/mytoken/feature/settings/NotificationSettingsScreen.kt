package ai.routin.mytoken.feature.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Remove
import androidx.compose.runtime.Composable
import ai.routin.mytoken.core.ui.SettingRow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/**
 * 通知 section of the settings page: enable alerts, edit the usage thresholds
 * (default 50/80) and the invalid-credential alert switch. When the Android 13+
 * POST_NOTIFICATIONS runtime permission is denied, the status is shown here so the
 * silent degradation is visible to the user.
 */
@Composable
fun NotificationSettingsSection(
    settings: NotificationSettings,
    permissionGranted: Boolean,
    onRequestPermission: () -> Unit,
    onNotificationsEnabledChange: (Boolean) -> Unit,
    onCredentialFailureAlertsChange: (Boolean) -> Unit,
    onLowThresholdChange: (Int) -> Unit,
    onHighThresholdChange: (Int) -> Unit,
) {
    Section(title = "通知") {
        SettingSwitchRow(
            label = "启用提醒",
            checked = settings.notificationsEnabled,
            onChange = onNotificationsEnabledChange,
        )
        ThresholdStepperRow(
            label = "用量提醒低阈值",
            value = settings.lowThresholdPercent,
            onDecrease = { onLowThresholdChange(settings.lowThresholdPercent - THRESHOLD_STEP) },
            onIncrease = { onLowThresholdChange(settings.lowThresholdPercent + THRESHOLD_STEP) },
        )
        ThresholdStepperRow(
            label = "用量提醒高阈值",
            value = settings.highThresholdPercent,
            onDecrease = { onHighThresholdChange(settings.highThresholdPercent - THRESHOLD_STEP) },
            onIncrease = { onHighThresholdChange(settings.highThresholdPercent + THRESHOLD_STEP) },
        )
        Text(
            text = "用量超过阈值、余额异常或凭证失效时提醒，最多每次刷新提醒一次；重置后重新提醒。",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(vertical = 4.dp),
        )
        SettingSwitchRow(
            label = "凭证失效提醒",
            checked = settings.credentialFailureAlertsEnabled,
            onChange = onCredentialFailureAlertsChange,
        )
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(
                text = if (permissionGranted) "系统通知权限：已允许" else "系统通知权限：未授予，提醒将静默",
                style = MaterialTheme.typography.bodySmall,
                color = if (permissionGranted) {
                    MaterialTheme.colorScheme.onSurfaceVariant
                } else {
                    MaterialTheme.colorScheme.error
                },
            )
            if (!permissionGranted) {
                TextButton(onClick = onRequestPermission) {
                    Text(text = "去授权")
                }
            }
        }
    }
}

@Composable
private fun ThresholdStepperRow(
    label: String,
    value: Int,
    onDecrease: () -> Unit,
    onIncrease: () -> Unit,
) {
    SettingRow(title = label) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onDecrease) {
                Icon(imageVector = Icons.Filled.Remove, contentDescription = "$label 减少")
            }
            Text(
                text = "$value%",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
            )
            IconButton(onClick = onIncrease) {
                Icon(imageVector = Icons.Filled.Add, contentDescription = "$label 增加")
            }
        }
    }
}

private const val THRESHOLD_STEP = 5
